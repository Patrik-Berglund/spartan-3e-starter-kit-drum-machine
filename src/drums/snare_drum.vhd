library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity snare_drum is
  port (
    clk         : in  std_logic;
    rst         : in  std_logic;
    sample_tick : in  std_logic;
    trigger     : in  std_logic;
    audio_out   : out signed(11 downto 0)
  );
end entity snare_drum;

architecture rtl of snare_drum is
  signal phase1, phase2 : unsigned(15 downto 0) := (others => '0');
  signal lfsr   : std_logic_vector(15 downto 0) := x"ACE1";
  signal tone_amp  : unsigned(15 downto 0) := (others => '0');
  signal noise_amp : unsigned(15 downto 0) := (others => '0');
  signal active : std_logic := '0';
  signal div    : unsigned(0 downto 0) := (others => '0');

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
begin
  s1 <= SINE(to_integer(phase1(15 downto 10)));
  s2 <= SINE(to_integer(phase2(15 downto 10)));

  process(clk)
    variable p1, p2 : signed(23 downto 0);
    variable noise  : signed(11 downto 0);
    variable mix    : signed(12 downto 0);
  begin
    if rising_edge(clk) then
      if rst = '1' then
        phase1 <= (others => '0'); phase2 <= (others => '0');
        lfsr <= x"ACE1"; tone_amp <= (others => '0');
        noise_amp <= (others => '0'); active <= '0'; div <= "0";
        audio_out <= (others => '0');
      else
        if trigger = '1' then
          active <= '1';
          phase1 <= (others => '0'); phase2 <= (others => '0');
          tone_amp  <= to_unsigned(65535, 16);
          noise_amp <= to_unsigned(65535, 16);
          div <= "0";
        end if;

        if sample_tick = '1' and active = '1' then
          phase1 <= phase1 + to_unsigned(319, 16);  -- 238Hz
          phase2 <= phase2 + to_unsigned(638, 16);  -- 476Hz
          lfsr <= lfsr(14 downto 0) & (lfsr(15) xor lfsr(13) xor lfsr(12) xor lfsr(10));

          -- Tones scaled by tone_amp
          p1 := s1 * signed('0' & tone_amp(15 downto 5));
          p2 := s2 * signed('0' & tone_amp(15 downto 5));

          -- Noise: ±noise_amp(15 downto 5)
          if lfsr(15) = '1' then
            noise := signed('0' & noise_amp(15 downto 5));
          else
            noise := -signed('0' & noise_amp(15 downto 5));
          end if;

          -- Mix: tone1/2 + tone2/4 + noise/2
          mix := resize(p1(22 downto 12), 13) + resize(shift_right(p2(22 downto 11), 1), 13) +
                 resize(shift_right(noise, 1), 13);

          if mix > 2047 then audio_out <= to_signed(2047, 12);
          elsif mix < -2048 then audio_out <= to_signed(-2048, 12);
          else audio_out <= mix(11 downto 0);
          end if;

          -- Exponential decay: tone K=11, noise K=12
          tone_amp <= tone_amp - ("00000000000" & tone_amp(15 downto 11));
          noise_amp <= noise_amp - ("000000000000" & noise_amp(15 downto 12));

          if tone_amp < 64 and noise_amp < 64 then active <= '0'; end if;
        elsif active = '0' then
          audio_out <= (others => '0');
        end if;
      end if;
    end if;
  end process;
end architecture rtl;
