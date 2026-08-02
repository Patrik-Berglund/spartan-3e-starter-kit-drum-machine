library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

-- 808 Snare Drum - fixed frequencies, TONE=mix ratio, separate decays
-- Simplified arithmetic to avoid XST synthesis issues.

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
  signal lfsr : std_logic_vector(15 downto 0) := x"ACE1";

  signal tone1_amp : unsigned(15 downto 0) := (others => '0');
  signal tone2_amp : unsigned(15 downto 0) := (others => '0');
  signal noise_amp : unsigned(15 downto 0) := (others => '0');
  signal active    : std_logic := '0';

  -- BPF accumulators
  signal hp_acc1 : signed(15 downto 0) := (others => '0');
  signal hp_acc2 : signed(15 downto 0) := (others => '0');
  signal lp_acc  : signed(15 downto 0) := (others => '0');

  -- 64-entry sine table
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

  -- Fixed phase increments
  constant PINC1 : unsigned(15 downto 0) := to_unsigned(252, 16);  -- ~188Hz
  constant PINC2 : unsigned(15 downto 0) := to_unsigned(464, 16);  -- ~345Hz

begin

  s1 <= SINE(to_integer(phase1(15 downto 10)));
  s2 <= SINE(to_integer(phase2(15 downto 10)));

  process(clk)
    variable p1, p2      : signed(23 downto 0);
    variable t1_out      : signed(15 downto 0);
    variable t2_out      : signed(15 downto 0);
    variable noise_raw   : signed(15 downto 0);
    variable bp_out      : signed(15 downto 0);
    variable noise_scaled: signed(15 downto 0);
    variable mix         : signed(16 downto 0);
    variable dec1        : unsigned(15 downto 0);
    variable dec2        : unsigned(15 downto 0);
    variable decn        : unsigned(15 downto 0);
  begin
    if rising_edge(clk) then
      if rst = '1' then
        phase1 <= (others => '0'); phase2 <= (others => '0');
        lfsr <= x"ACE1";
        tone1_amp <= (others => '0'); tone2_amp <= (others => '0');
        noise_amp <= (others => '0'); active <= '0';
        hp_acc1 <= (others => '0'); hp_acc2 <= (others => '0');
        lp_acc <= (others => '0');
        audio_out <= (others => '0');
      else
        if trigger = '1' then
          active <= '1';
          phase1 <= (others => '0'); phase2 <= (others => '0');
          tone1_amp <= to_unsigned(65535, 16);
          tone2_amp <= to_unsigned(65535, 16);
          noise_amp <= to_unsigned(65535, 16);
        end if;

        if sample_tick = '1' and active = '1' then
          phase1 <= phase1 + PINC1;
          phase2 <= phase2 + PINC2;
          lfsr <= lfsr(14 downto 0) & (lfsr(15) xor lfsr(13) xor lfsr(12) xor lfsr(10));

          -- Lower tone: s1 * tone1_amp(15:5), scaled by (255-tone)
          -- p1 is 24-bit. Take p1(22:8) = 15-bit signal.
          -- Then shift right by tone(7:5) to reduce when tone is high.
          -- Simple approach: tone=0 -> t1 full, tone=255 -> t1 >> 3
          p1 := s1 * signed('0' & tone1_amp(15 downto 5));
          -- tone(7:6): 0=full, 1=>>1, 2=>>2, 3=>>3
          case tone(7 downto 6) is
            when "00" => t1_out := p1(22 downto 7);
            when "01" => t1_out := p1(22) & p1(22 downto 8);
            when "10" => t1_out := p1(22) & p1(22) & p1(22 downto 9);
            when others => t1_out := p1(22) & p1(22) & p1(22) & p1(22 downto 10);
          end case;

          -- Upper tone: s2 * tone2_amp(15:5), scaled by tone
          -- tone=0 -> t2 >> 3, tone=255 -> t2 full
          p2 := s2 * signed('0' & tone2_amp(15 downto 5));
          case tone(7 downto 6) is
            when "00" => t2_out := p2(22) & p2(22) & p2(22) & p2(22 downto 10);
            when "01" => t2_out := p2(22) & p2(22) & p2(22 downto 9);
            when "10" => t2_out := p2(22) & p2(22 downto 8);
            when others => t2_out := p2(22 downto 7);
          end case;

          -- Noise from LFSR (signed 15-bit)
          noise_raw := signed(lfsr(14 downto 0) & '0') - to_signed(16384, 16);

          -- BPF: 2-stage HP (shift 2) + 1-stage LP (shift 1)
          -- HP stage 1
          hp_acc1 <= hp_acc1 + shift_right(noise_raw - hp_acc1, 2);
          -- HP stage 2 (input = noise_raw - hp_acc1)
          hp_acc2 <= hp_acc2 + shift_right((noise_raw - hp_acc1) - hp_acc2, 2);
          -- LP stage (input = hp2_out = (noise_raw-hp_acc1) - hp_acc2 roughly)
          bp_out := lp_acc;
          lp_acc <= lp_acc + shift_right(((noise_raw - hp_acc1) - hp_acc2) - lp_acc, 1);

          -- Scale noise: bp_out * noise_amp(15:8) >> 7
          noise_scaled := resize(
            shift_right(bp_out * signed('0' & noise_amp(15 downto 8)), 7),
            16);

          -- Apply snappy: shift based on snappy level
          -- snappy(7:6): 0=>>3(quiet), 1=>>2, 2=>>1, 3=full
          case snappy(7 downto 6) is
            when "00" => noise_scaled := shift_right(noise_scaled, 3);
            when "01" => noise_scaled := shift_right(noise_scaled, 2);
            when "10" => noise_scaled := shift_right(noise_scaled, 1);
            when others => null;  -- full level
          end case;

          -- Mix
          mix := resize(t1_out, 17) + resize(t2_out, 17) + resize(noise_scaled, 17);
          if mix > 32767 then audio_out <= to_signed(32767, 16);
          elsif mix < -32768 then audio_out <= to_signed(-32768, 16);
          else audio_out <= mix(15 downto 0); end if;

          -- Decay envelopes with linear tail
          -- Only decay if amp >= 64 (prevent unsigned underflow wrap!)
          -- Lower tone: K=10
          if tone1_amp >= 64 then
            dec1 := "0000000000" & tone1_amp(15 downto 10);
            if dec1 = 0 then tone1_amp <= tone1_amp - 1;
            else tone1_amp <= tone1_amp - dec1; end if;
          end if;

          -- Upper tone: K=9
          if tone2_amp >= 64 then
            dec2 := "000000000" & tone2_amp(15 downto 9);
            if dec2 = 0 then tone2_amp <= tone2_amp - 1;
            else tone2_amp <= tone2_amp - dec2; end if;
          end if;

          -- Noise: K=11
          if noise_amp >= 64 then
            decn := "00000000000" & noise_amp(15 downto 11);
            if decn = 0 then noise_amp <= noise_amp - 1;
            else noise_amp <= noise_amp - decn; end if;
          end if;

          if tone1_amp < 64 and tone2_amp < 64 and noise_amp < 64 then
            active <= '0';
          end if;
        elsif active = '0' then
          audio_out <= (others => '0');
        end if;
      end if;
    end if;
  end process;
end architecture rtl;
