library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

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
  signal phase     : unsigned(15 downto 0) := (others => '0');
  signal amplitude : unsigned(11 downto 0) := (others => '0');
  signal active    : std_logic := '0';
begin
  process(clk)
    variable tri : signed(11 downto 0);
    variable scaled : signed(23 downto 0);
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
        end if;

        if sample_tick = '1' and active = '1' then
          -- High frequency ~1.5kHz ping
          phase <= phase + to_unsigned(6400, 16);

          -- Triangle wave
          if phase(15) = '0' then
            tri := signed('0' & phase(14 downto 4)) - 1024;
          else
            tri := 1024 - signed('0' & phase(14 downto 4));
          end if;

          scaled := tri * signed('0' & amplitude);
          audio_out <= scaled(23 downto 12);

          -- Very fast decay
          amplitude <= amplitude - ("00" & amplitude(11 downto 2));
          if amplitude < 8 then
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
