library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

-- Tom drum: pitched sine wave with amplitude decay.
-- Instantiate 3 times with different G_FREQ for LT/MT/HT.

entity tom is
  generic (
    G_FREQ : unsigned(15 downto 0) := to_unsigned(1200, 16)  -- phase increment
  );
  port (
    clk         : in  std_logic;
    rst         : in  std_logic;
    sample_tick : in  std_logic;
    trigger     : in  std_logic;
    audio_out   : out signed(11 downto 0)
  );
end entity tom;

architecture rtl of tom is
  signal phase     : unsigned(15 downto 0) := (others => '0');
  signal amplitude : unsigned(11 downto 0) := (others => '0');
  signal active    : std_logic := '0';
  signal tick_cnt  : unsigned(3 downto 0) := (others => '0');
begin
  process(clk)
    variable sine_val : signed(11 downto 0);
    variable scaled   : signed(23 downto 0);
    variable half     : unsigned(14 downto 0);
    variable tri      : signed(11 downto 0);
  begin
    if rising_edge(clk) then
      if rst = '1' then
        phase <= (others => '0');
        amplitude <= (others => '0');
        active <= '0';
        audio_out <= (others => '0');
      else
        if trigger = '1' then
          active <= '1';
          phase <= (others => '0');
          amplitude <= to_unsigned(4095, 12);
          tick_cnt <= (others => '0');
        end if;

        if sample_tick = '1' and active = '1' then
          phase <= phase + G_FREQ;
          tick_cnt <= tick_cnt + 1;

          -- Triangle approximation of sine
          half := phase(14 downto 0);
          if phase(14) = '0' then
            tri := signed('0' & resize(half(13 downto 3), 11));
          else
            tri := signed('0' & (not resize(half(13 downto 3), 11)));
          end if;
          sine_val := tri - 1024;
          if phase(15) = '1' then sine_val := -sine_val; end if;

          -- Amplitude decay (every 8 samples)
          if tick_cnt(2 downto 0) = "111" then
            amplitude <= amplitude - ("0000" & amplitude(11 downto 4));
            if amplitude < 16 then
              active <= '0';
              amplitude <= (others => '0');
            end if;
          end if;

          scaled := sine_val * signed('0' & amplitude);
          audio_out <= scaled(23 downto 12);
        elsif active = '0' then
          audio_out <= (others => '0');
        end if;
      end if;
    end if;
  end process;
end architecture rtl;
