library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity sine_table is
  port (
    clk       : in  std_logic;
    phase     : in  unsigned(15 downto 0);
    sine_out  : out signed(11 downto 0)
  );
end entity sine_table;

architecture rtl of sine_table is
  type sine_rom_t is array(0 to 255) of signed(11 downto 0);
  constant SINE_ROM : sine_rom_t := (
    to_signed(0,12),to_signed(50,12),to_signed(100,12),to_signed(151,12),to_signed(201,12),to_signed(251,12),to_signed(300,12),to_signed(350,12),
    to_signed(399,12),to_signed(449,12),to_signed(497,12),to_signed(546,12),to_signed(594,12),to_signed(642,12),to_signed(690,12),to_signed(737,12),
    to_signed(783,12),to_signed(830,12),to_signed(875,12),to_signed(920,12),to_signed(965,12),to_signed(1009,12),to_signed(1052,12),to_signed(1095,12),
    to_signed(1137,12),to_signed(1179,12),to_signed(1219,12),to_signed(1259,12),to_signed(1299,12),to_signed(1337,12),to_signed(1375,12),to_signed(1411,12),
    to_signed(1447,12),to_signed(1483,12),to_signed(1517,12),to_signed(1550,12),to_signed(1582,12),to_signed(1614,12),to_signed(1644,12),to_signed(1674,12),
    to_signed(1702,12),to_signed(1729,12),to_signed(1756,12),to_signed(1781,12),to_signed(1805,12),to_signed(1828,12),to_signed(1850,12),to_signed(1871,12),
    to_signed(1891,12),to_signed(1910,12),to_signed(1927,12),to_signed(1944,12),to_signed(1959,12),to_signed(1973,12),to_signed(1986,12),to_signed(1997,12),
    to_signed(2008,12),to_signed(2017,12),to_signed(2025,12),to_signed(2032,12),to_signed(2037,12),to_signed(2041,12),to_signed(2045,12),to_signed(2046,12),
    to_signed(2047,12),to_signed(2046,12),to_signed(2045,12),to_signed(2041,12),to_signed(2037,12),to_signed(2032,12),to_signed(2025,12),to_signed(2017,12),
    to_signed(2008,12),to_signed(1997,12),to_signed(1986,12),to_signed(1973,12),to_signed(1959,12),to_signed(1944,12),to_signed(1927,12),to_signed(1910,12),
    to_signed(1891,12),to_signed(1871,12),to_signed(1850,12),to_signed(1828,12),to_signed(1805,12),to_signed(1781,12),to_signed(1756,12),to_signed(1729,12),
    to_signed(1702,12),to_signed(1674,12),to_signed(1644,12),to_signed(1614,12),to_signed(1582,12),to_signed(1550,12),to_signed(1517,12),to_signed(1483,12),
    to_signed(1447,12),to_signed(1411,12),to_signed(1375,12),to_signed(1337,12),to_signed(1299,12),to_signed(1259,12),to_signed(1219,12),to_signed(1179,12),
    to_signed(1137,12),to_signed(1095,12),to_signed(1052,12),to_signed(1009,12),to_signed(965,12),to_signed(920,12),to_signed(875,12),to_signed(830,12),
    to_signed(783,12),to_signed(737,12),to_signed(690,12),to_signed(642,12),to_signed(594,12),to_signed(546,12),to_signed(497,12),to_signed(449,12),
    to_signed(399,12),to_signed(350,12),to_signed(300,12),to_signed(251,12),to_signed(201,12),to_signed(151,12),to_signed(100,12),to_signed(50,12),
    to_signed(0,12),to_signed(-50,12),to_signed(-100,12),to_signed(-151,12),to_signed(-201,12),to_signed(-251,12),to_signed(-300,12),to_signed(-350,12),
    to_signed(-399,12),to_signed(-449,12),to_signed(-497,12),to_signed(-546,12),to_signed(-594,12),to_signed(-642,12),to_signed(-690,12),to_signed(-737,12),
    to_signed(-783,12),to_signed(-830,12),to_signed(-875,12),to_signed(-920,12),to_signed(-965,12),to_signed(-1009,12),to_signed(-1052,12),to_signed(-1095,12),
    to_signed(-1137,12),to_signed(-1179,12),to_signed(-1219,12),to_signed(-1259,12),to_signed(-1299,12),to_signed(-1337,12),to_signed(-1375,12),to_signed(-1411,12),
    to_signed(-1447,12),to_signed(-1483,12),to_signed(-1517,12),to_signed(-1550,12),to_signed(-1582,12),to_signed(-1614,12),to_signed(-1644,12),to_signed(-1674,12),
    to_signed(-1702,12),to_signed(-1729,12),to_signed(-1756,12),to_signed(-1781,12),to_signed(-1805,12),to_signed(-1828,12),to_signed(-1850,12),to_signed(-1871,12),
    to_signed(-1891,12),to_signed(-1910,12),to_signed(-1927,12),to_signed(-1944,12),to_signed(-1959,12),to_signed(-1973,12),to_signed(-1986,12),to_signed(-1997,12),
    to_signed(-2008,12),to_signed(-2017,12),to_signed(-2025,12),to_signed(-2032,12),to_signed(-2037,12),to_signed(-2041,12),to_signed(-2045,12),to_signed(-2046,12),
    to_signed(-2047,12),to_signed(-2046,12),to_signed(-2045,12),to_signed(-2041,12),to_signed(-2037,12),to_signed(-2032,12),to_signed(-2025,12),to_signed(-2017,12),
    to_signed(-2008,12),to_signed(-1997,12),to_signed(-1986,12),to_signed(-1973,12),to_signed(-1959,12),to_signed(-1944,12),to_signed(-1927,12),to_signed(-1910,12),
    to_signed(-1891,12),to_signed(-1871,12),to_signed(-1850,12),to_signed(-1828,12),to_signed(-1805,12),to_signed(-1781,12),to_signed(-1756,12),to_signed(-1729,12),
    to_signed(-1702,12),to_signed(-1674,12),to_signed(-1644,12),to_signed(-1614,12),to_signed(-1582,12),to_signed(-1550,12),to_signed(-1517,12),to_signed(-1483,12),
    to_signed(-1447,12),to_signed(-1411,12),to_signed(-1375,12),to_signed(-1337,12),to_signed(-1299,12),to_signed(-1259,12),to_signed(-1219,12),to_signed(-1179,12),
    to_signed(-1137,12),to_signed(-1095,12),to_signed(-1052,12),to_signed(-1009,12),to_signed(-965,12),to_signed(-920,12),to_signed(-875,12),to_signed(-830,12),
    to_signed(-783,12),to_signed(-737,12),to_signed(-690,12),to_signed(-642,12),to_signed(-594,12),to_signed(-546,12),to_signed(-497,12),to_signed(-449,12),
    to_signed(-399,12),to_signed(-350,12),to_signed(-300,12),to_signed(-251,12),to_signed(-201,12),to_signed(-151,12),to_signed(-100,12),to_signed(-50,12)
  );

  -- Pipeline stage 1 registers
  signal s0_r, s1_r : signed(11 downto 0);
  signal frac_r     : unsigned(7 downto 0);

  -- Pipeline stage 2 register
  signal out_r : signed(11 downto 0);

  -- Interpolation wires
  signal diff   : signed(12 downto 0);
  signal interp : signed(21 downto 0);  -- 13-bit * 9-bit = 22-bit
begin

  -- Stage 1: ROM lookup (registered)
  process(clk)
    variable idx : unsigned(7 downto 0);
    variable nxt : unsigned(7 downto 0);
  begin
    if rising_edge(clk) then
      idx := phase(15 downto 8);
      nxt := idx + 1;
      s0_r   <= SINE_ROM(to_integer(idx));
      s1_r   <= SINE_ROM(to_integer(nxt));
      frac_r <= phase(7 downto 0);
    end if;
  end process;

  -- Stage 2: linear interpolation (1 MULT18x18)
  diff   <= resize(s1_r, 13) - resize(s0_r, 13);
  interp <= diff * signed("0" & frac_r);  -- 13 * 9 = 22 bits

  process(clk)
  begin
    if rising_edge(clk) then
      out_r <= s0_r + interp(19 downto 8);
    end if;
  end process;

  sine_out <= out_r;

end architecture rtl;
