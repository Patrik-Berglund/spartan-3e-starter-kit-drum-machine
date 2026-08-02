library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

-- 808 Tom - bridged-T oscillator with amplitude-dependent pitch.
-- Used for LT, MT, HT with different generic parameters.
-- G_FREQ_MIN: phase increment at tuning=0
-- G_FREQ_RANGE: additional increment at tuning=255
-- G_DECAY_K: decay shift (12 for LT, 11 for MT/HT)

entity tom is
  generic (
    G_FREQ     : unsigned(15 downto 0) := to_unsigned(109, 16);  -- legacy, unused
    G_FREQ_MIN : unsigned(15 downto 0) := to_unsigned(109, 16);
    G_FREQ_RNG : unsigned(15 downto 0) := to_unsigned(25, 16);
    G_DECAY_K  : integer := 12
  );
  port (
    clk         : in  std_logic;
    rst         : in  std_logic;
    sample_tick : in  std_logic;
    trigger     : in  std_logic;
    tuning      : in  unsigned(7 downto 0);
    audio_out   : out signed(15 downto 0)
  );
end entity tom;

architecture rtl of tom is
  signal phase : unsigned(15 downto 0) := (others => '0');
  signal amp   : unsigned(15 downto 0) := (others => '0');
  signal active: std_logic := '0';

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

  signal sine_val    : signed(11 downto 0);
  signal target_freq : unsigned(15 downto 0);
  signal freq_scaled : unsigned(23 downto 0);
begin
  sine_val <= SINE(to_integer(phase(15 downto 10)));

  -- Target frequency: freq_min + (tuning * freq_range) >> 8
  freq_scaled <= resize(tuning, 16) * G_FREQ_RNG;
  target_freq <= G_FREQ_MIN + ("00000000" & freq_scaled(15 downto 8));

  process(clk)
    variable product  : signed(23 downto 0);
    variable freq_now : unsigned(15 downto 0);
    variable dec_term : unsigned(15 downto 0);
  begin
    if rising_edge(clk) then
      if rst = '1' then
        phase <= (others => '0');
        amp <= (others => '0'); active <= '0';
        audio_out <= (others => '0');
      else
        if trigger = '1' then
          active <= '1'; phase <= (others => '0');
          amp <= to_unsigned(65535, 16);
        end if;

        if sample_tick = '1' and active = '1' then
          -- Amplitude-dependent pitch: target + (amp >> 14)
          -- At full amp: offset = 3-4 phase units (~2-4% pitch sweep)
          freq_now := target_freq + ("00000000000000" & amp(15 downto 14));
          phase <= phase + freq_now;

          -- Sine * amplitude
          product := sine_val * signed('0' & amp(15 downto 5));
          audio_out <= product(22 downto 7);

          -- Exponential decay with linear tail (prevent stuck voices)
          case G_DECAY_K is
            when 10 =>
              dec_term := "0000000000" & amp(15 downto 10);
            when 11 =>
              dec_term := "00000000000" & amp(15 downto 11);
            when others => -- 12
              dec_term := "000000000000" & amp(15 downto 12);
          end case;

          if dec_term = 0 then
            amp <= amp - 1;
          else
            amp <= amp - dec_term;
          end if;

          if amp < 64 then
            active <= '0';
          end if;
        elsif active = '0' then
          audio_out <= (others => '0');
        end if;
      end if;
    end if;
  end process;
end architecture rtl;
