library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

-- Rim shot: short pulse excites a resonant filter at ~500Hz. Very short decay.

entity rimshot is
  port (
    clk         : in  std_logic;
    rst         : in  std_logic;
    sample_tick : in  std_logic;
    trigger     : in  std_logic;
    audio_out   : out signed(11 downto 0)
  );
end entity rimshot;

architecture rtl of rimshot is
  signal phase : unsigned(19 downto 0) := (others => '0');
  signal amp   : unsigned(13 downto 0) := (others => '0');
  signal active: std_logic := '0';
  -- 500 Hz @ 48828 Hz: inc = 10737
  constant FREQ : unsigned(19 downto 0) := to_unsigned(10737, 20);
begin
  process(clk)
    variable s : signed(11 downto 0);
    variable scaled : signed(25 downto 0);
  begin
    if rising_edge(clk) then
      if rst = '1' then
        phase <= (others => '0'); amp <= (others => '0');
        active <= '0'; audio_out <= (others => '0');
      else
        if trigger = '1' then
          active <= '1';
          phase <= (others => '0');
          amp <= to_unsigned(16383, 14);
        end if;

        if sample_tick = '1' and active = '1' then
          phase <= phase + FREQ;

          -- Triangle wave (sharp, metallic)
          if phase(19) = '0' then
            s := signed('0' & phase(18 downto 8)) - 1024;
          else
            s := 1024 - signed('0' & phase(18 downto 8));
          end if;

          scaled := s * signed('0' & amp(13 downto 1));
          audio_out <= scaled(24 downto 13);

          -- Very fast decay: ~5ms (shift ~8)
          amp <= amp - ("00000000" & amp(13 downto 8));
          if amp < 16 then
            active <= '0';
            audio_out <= (others => '0');
          end if;
        elsif active = '0' then
          audio_out <= (others => '0');
        end if;
      end if;
    end if;
  end process;
end architecture rtl;
