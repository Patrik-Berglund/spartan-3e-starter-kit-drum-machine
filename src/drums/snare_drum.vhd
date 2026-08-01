library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity snare_drum is
  port (
    clk         : in  std_logic;
    rst         : in  std_logic;
    sample_tick : in  std_logic;
    trigger     : in  std_logic;
    tone        : in  unsigned(7 downto 0);
    snappy      : in  unsigned(7 downto 0);
    audio_out   : out signed(15 downto 0)
  );
end entity snare_drum;

architecture rtl of snare_drum is
  signal phase1, phase2 : unsigned(15 downto 0) := (others => '0');
  signal lfsr   : std_logic_vector(15 downto 0) := x"ACE1";
  signal tone_amp  : unsigned(15 downto 0) := (others => '0');
  signal noise_amp : unsigned(15 downto 0) := (others => '0');
  signal active : std_logic := '0';
  -- BPF accumulators for noise
  signal lp_acc  : signed(15 downto 0) := (others => '0');
  signal lp_acc2 : signed(15 downto 0) := (others => '0');
  signal hp_acc  : signed(15 downto 0) := (others => '0');

  type sine_t is array(0 to 63) of signed(11 downto 0);
  constant SINE : sine_t := (
    to_signed(0,12),to_signed(201,12),to_signed(399,12),to_signed(594,12),
    to_signed(783,12),to_signed(965,12),to_signed(1137,12),to_signed(1299,12),
    to_signed(1447,12),to_signed(1582,12),to_signed(1702,12),to_signed(1805,12),
    to_signed(1891,12),to_signed(1959,12),to_signed(2008,12),to_signed(2037,12),
    to_signed(2047,12),to_signed(2037,12),to_signed(2008,12),to_signed(1959,12),
    to_signed(1891,12),to_signed(1805,12),to_signed(1702,12),to_signed(1582,12),
    to_signed(1447,12),to_signed(1299,12),to_signed(1137,12),to_signed(965,12),
    to_signed(783,12),to_signed(594,12),to_signed(399,12),to_signed(201,12),
    to_signed(0,12),to_signed(-201,12),to_signed(-399,12),to_signed(-594,12),
    to_signed(-783,12),to_signed(-965,12),to_signed(-1137,12),to_signed(-1299,12),
    to_signed(-1447,12),to_signed(-1582,12),to_signed(-1702,12),to_signed(-1805,12),
    to_signed(-1891,12),to_signed(-1959,12),to_signed(-2008,12),to_signed(-2037,12),
    to_signed(-2047,12),to_signed(-2037,12),to_signed(-2008,12),to_signed(-1959,12),
    to_signed(-1891,12),to_signed(-1805,12),to_signed(-1702,12),to_signed(-1582,12),
    to_signed(-1447,12),to_signed(-1299,12),to_signed(-1137,12),to_signed(-965,12),
    to_signed(-783,12),to_signed(-594,12),to_signed(-399,12),to_signed(-201,12)
  );

  signal s1, s2 : signed(11 downto 0);

  -- Param-derived signals
  -- TONE: controls phase_inc1 range 232-406 (173-303Hz), phase_inc2 = 2*phase_inc1
  -- tone=0 -> 232, tone=255 -> 406. Delta=174. Approx: 232 + tone(7:1) + tone(7:3)
  signal pinc1 : unsigned(15 downto 0);
  signal pinc2 : unsigned(15 downto 0);
  -- SNAPPY: noise gain shift. snappy=0 -> noise/4, snappy=255 -> noise*1
  -- Map to noise_shift: 0=shift right 2, 128=shift right 1, 255=no shift
  signal noise_shift : unsigned(1 downto 0);
begin
  -- Tone param -> phase increments
  pinc1 <= to_unsigned(232, 16) + resize(tone(7 downto 1), 16) + resize(tone(7 downto 3), 16);
  pinc2 <= shift_left(pinc1, 1);

  -- Snappy param -> noise shift (0-85: >>2, 86-170: >>1, 171-255: >>0)
  noise_shift <= "10" when snappy < 86 else
                 "01" when snappy < 171 else
                 "00";

  s1 <= SINE(to_integer(phase1(15 downto 10)));
  s2 <= SINE(to_integer(phase2(15 downto 10)));

  process(clk)
    variable p1, p2 : signed(23 downto 0);
    variable noise_raw  : signed(15 downto 0);
    variable lp1_next   : signed(15 downto 0);
    variable lp2_next   : signed(15 downto 0);
    variable hp_next    : signed(15 downto 0);
    variable bp_out     : signed(15 downto 0);
    variable noise_scaled : signed(15 downto 0);
    variable mix    : signed(16 downto 0);
  begin
    if rising_edge(clk) then
      if rst = '1' then
        phase1 <= (others => '0'); phase2 <= (others => '0');
        lfsr <= x"ACE1"; tone_amp <= (others => '0');
        noise_amp <= (others => '0'); active <= '0';
        lp_acc <= (others => '0'); lp_acc2 <= (others => '0');
        hp_acc <= (others => '0');
        audio_out <= (others => '0');
      else
        if trigger = '1' then
          active <= '1';
          phase1 <= (others => '0'); phase2 <= (others => '0');
          tone_amp  <= to_unsigned(65535, 16);
          noise_amp <= to_unsigned(65535, 16);
        end if;

        if sample_tick = '1' and active = '1' then
          phase1 <= phase1 + pinc1;
          phase2 <= phase2 + pinc2;
          lfsr <= lfsr(14 downto 0) & (lfsr(15) xor lfsr(13) xor lfsr(12) xor lfsr(10));

          -- Tones scaled by tone_amp
          p1 := s1 * signed('0' & tone_amp(15 downto 5));
          p2 := s2 * signed('0' & tone_amp(15 downto 5));

          -- Noise: 15-bit signed from LFSR
          noise_raw := signed(lfsr(14 downto 0) & '0') - to_signed(16384, 16);

          -- BPF: 2-stage LP (shift 2) + 1-stage HP (shift 5)
          lp1_next := lp_acc + shift_right(noise_raw - lp_acc, 2);
          lp_acc <= lp1_next;
          lp2_next := lp_acc2 + shift_right(lp1_next - lp_acc2, 2);
          lp_acc2 <= lp2_next;
          hp_next := hp_acc + shift_right(lp2_next - hp_acc, 5);
          hp_acc <= hp_next;
          bp_out := lp2_next - hp_next;

          -- Scale noise by noise_amp
          noise_scaled := resize(shift_right(bp_out * signed('0' & noise_amp(15 downto 8)), 7), 16);

          -- Apply snappy scaling
          case noise_shift is
            when "10"   => noise_scaled := shift_right(noise_scaled, 2);
            when "01"   => noise_scaled := shift_right(noise_scaled, 1);
            when others => null;
          end case;

          -- Mix: tone1 >> 8 + tone2 >> 9 + noise_scaled
          mix := resize(p1(22 downto 8), 17) + resize(p2(22 downto 9), 17) +
                 resize(noise_scaled, 17);

          if mix > 32767 then audio_out <= to_signed(32767, 16);
          elsif mix < -32768 then audio_out <= to_signed(-32768, 16);
          else audio_out <= mix(15 downto 0);
          end if;

          -- Exponential decay: tone K=9, noise K=11. Force to 0 once the
          -- decay term itself is 0 (see kick_drum.vhd comment for why --
          -- K=9/K=11 floors of 512/2048 are both above the old amp<64
          -- threshold, so both amps would get permanently stuck without
          -- this fix).
          if tone_amp(15 downto 9) = "0000000" then tone_amp <= (others => '0');
          else tone_amp <= tone_amp - ("000000000" & tone_amp(15 downto 9)); end if;
          if noise_amp(15 downto 11) = "00000" then noise_amp <= (others => '0');
          else noise_amp <= noise_amp - ("00000000000" & noise_amp(15 downto 11)); end if;

          if tone_amp < 64 and noise_amp < 64 then active <= '0'; end if;
        elsif active = '0' then
          audio_out <= (others => '0');
        end if;
      end if;
    end if;
  end process;
end architecture rtl;
