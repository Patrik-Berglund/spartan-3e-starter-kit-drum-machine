library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

-- Tom: sine oscillator with slight pitch sweep down, medium decay.
-- G_FREQ sets base pitch: LT~100Hz(2148), MT~150Hz(3222), HT~200Hz(4296)

entity tom is
  generic (
    G_FREQ : unsigned(19 downto 0) := to_unsigned(3222, 20)
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
  signal phase : unsigned(19 downto 0) := (others => '0');
  signal freq  : unsigned(19 downto 0) := (others => '0');
  signal amp   : unsigned(13 downto 0) := (others => '0');
  signal active: std_logic := '0';

  -- Sine table (16 entries, 12-bit) - quarter wave, mirrored
  type qt_t is array(0 to 15) of unsigned(11 downto 0);
  constant QT : qt_t := (
    to_unsigned(0,12),    to_unsigned(392,12),  to_unsigned(784,12),  to_unsigned(1137,12),
    to_unsigned(1448,12), to_unsigned(1710,12), to_unsigned(1872,12), to_unsigned(1981,12),
    to_unsigned(2047,12), to_unsigned(1981,12), to_unsigned(1872,12), to_unsigned(1710,12),
    to_unsigned(1448,12), to_unsigned(1137,12), to_unsigned(784,12),  to_unsigned(392,12)
  );
begin
  process(clk)
    variable idx : integer range 0 to 15;
    variable s   : signed(11 downto 0);
    variable scaled : signed(25 downto 0);
  begin
    if rising_edge(clk) then
      if rst = '1' then
        phase <= (others => '0'); freq <= (others => '0');
        amp <= (others => '0'); active <= '0';
        audio_out <= (others => '0');
      else
        if trigger = '1' then
          active <= '1';
          phase <= (others => '0');
          freq <= G_FREQ + shift_right(G_FREQ, 3); -- start 12% higher
          amp <= to_unsigned(16383, 14);
        end if;

        if sample_tick = '1' and active = '1' then
          phase <= phase + freq;

          -- Slight pitch sweep down to base
          if freq > G_FREQ then
            freq <= freq - 1;
          end if;

          -- Sine from quarter-wave table
          idx := to_integer(phase(19 downto 16));
          if phase(19) = '0' then
            s := signed(resize(QT(to_integer(phase(18 downto 15))), 12));
          else
            s := -signed(resize(QT(to_integer(phase(18 downto 15))), 12));
          end if;

          scaled := s * signed('0' & amp(13 downto 1));
          audio_out <= scaled(24 downto 13);

          -- Decay: ~150ms (shift ~13)
          amp <= amp - ("0000000000000" & amp(13 downto 13));
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
