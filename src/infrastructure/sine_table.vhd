-- Shared sine table with linear interpolation
-- 256 x 12-bit entries, one MULT18x18 for interpolation
-- TDM: accepts phase input, returns interpolated sine value in 2 clock cycles

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

  -- Generate sine table at elaboration
  function init_sine return sine_rom_t is
    variable tbl : sine_rom_t;
    variable angle : real;
  begin
    for i in 0 to 255 loop
      angle := real(i) * 6.283185307 / 256.0;
      tbl(i) := to_signed(integer(2047.0 * sin(angle)), 12);
    end loop;
    return tbl;
  end function;

  -- Use MATH_REAL for init
  constant SINE_ROM : sine_rom_t := (
    to_signed(0,12),to_signed(50,12),to_signed(100,12),to_signed(150,12),
    to_signed(200,12),to_signed(249,12),to_signed(297,12),to_signed(345,12),
    to_signed(392,12),to_signed(437,12),to_signed(482,12),to_signed(526,12),
    to_signed(568,12),to_signed(609,12),to_signed(649,12),to_signed(687,12),
    to_signed(724,12),to_signed(758,12),to_signed(791,12),to_signed(822,12),
    to_signed(851,12),to_signed(878,12),to_signed(903,12),to_signed(926,12),
    to_signed(946,12),to_signed(964,12),to_signed(980,12),to_signed(993,12),
    to_signed(1004,12),to_signed(1013,12),to_signed(1019,12),to_signed(1023,12),
    to_signed(1024,12),to_signed(1023,12),to_signed(1019,12),to_signed(1013,12),
    to_signed(1004,12),to_signed(993,12),to_signed(980,12),to_signed(964,12),
    to_signed(946,12),to_signed(926,12),to_signed(903,12),to_signed(878,12),
    to_signed(851,12),to_signed(822,12),to_signed(791,12),to_signed(758,12),
    to_signed(724,12),to_signed(687,12),to_signed(649,12),to_signed(609,12),
    to_signed(568,12),to_signed(526,12),to_signed(482,12),to_signed(437,12),
    to_signed(392,12),to_signed(345,12),to_signed(297,12),to_signed(249,12),
    to_signed(200,12),to_signed(150,12),to_signed(100,12),to_signed(50,12),
    to_signed(0,12),to_signed(-50,12),to_signed(-100,12),to_signed(-150,12),
    to_signed(-200,12),to_signed(-249,12),to_signed(-297,12),to_signed(-345,12),
    to_signed(-392,12),to_signed(-437,12),to_signed(-482,12),to_signed(-526,12),
    to_signed(-568,12),to_signed(-609,12),to_signed(-649,12),to_signed(-687,12),
    to_signed(-724,12),to_signed(-758,12),to_signed(-791,12),to_signed(-822,12),
    to_signed(-851,12),to_signed(-878,12),to_signed(-903,12),to_signed(-926,12),
    to_signed(-946,12),to_signed(-964,12),to_signed(-980,12),to_signed(-993,12),
    to_signed(-1004,12),to_signed(-1013,12),to_signed(-1019,12),to_signed(-1023,12),
    to_signed(-1024,12),to_signed(-1023,12),to_signed(-1019,12),to_signed(-1013,12),
    to_signed(-1004,12),to_signed(-993,12),to_signed(-980,12),to_signed(-964,12),
    to_signed(-946,12),to_signed(-926,12),to_signed(-903,12),to_signed(-878,12),
    to_signed(-851,12),to_signed(-822,12),to_signed(-791,12),to_signed(-758,12),
    to_signed(-724,12),to_signed(-687,12),to_signed(-649,12),to_signed(-609,12),
    to_signed(-568,12),to_signed(-526,12),to_signed(-482,12),to_signed(-437,12),
    to_signed(-392,12),to_signed(-345,12),to_signed(-297,12),to_signed(-249,12),
    to_signed(-200,12),to_signed(-150,12),to_signed(-100,12),to_signed(-50,12),
    -- Second half (128-255): repeat with proper values
    to_signed(0,12),to_signed(50,12),to_signed(100,12),to_signed(150,12),
    to_signed(200,12),to_signed(249,12),to_signed(297,12),to_signed(345,12),
    to_signed(392,12),to_signed(437,12),to_signed(482,12),to_signed(526,12),
    to_signed(568,12),to_signed(609,12),to_signed(649,12),to_signed(687,12),
    to_signed(724,12),to_signed(758,12),to_signed(791,12),to_signed(822,12),
    to_signed(851,12),to_signed(878,12),to_signed(903,12),to_signed(926,12),
    to_signed(946,12),to_signed(964,12),to_signed(980,12),to_signed(993,12),
    to_signed(1004,12),to_signed(1013,12),to_signed(1019,12),to_signed(1023,12),
    to_signed(1024,12),to_signed(1023,12),to_signed(1019,12),to_signed(1013,12),
    to_signed(1004,12),to_signed(993,12),to_signed(980,12),to_signed(964,12),
    to_signed(946,12),to_signed(926,12),to_signed(903,12),to_signed(878,12),
    to_signed(851,12),to_signed(822,12),to_signed(791,12),to_signed(758,12),
    to_signed(724,12),to_signed(687,12),to_signed(649,12),to_signed(609,12),
    to_signed(568,12),to_signed(526,12),to_signed(482,12),to_signed(437,12),
    to_signed(392,12),to_signed(345,12),to_signed(297,12),to_signed(249,12),
    to_signed(200,12),to_signed(150,12),to_signed(100,12),to_signed(50,12),
    to_signed(0,12),to_signed(-50,12),to_signed(-100,12),to_signed(-150,12),
    to_signed(-200,12),to_signed(-249,12),to_signed(-297,12),to_signed(-345,12),
    to_signed(-392,12),to_signed(-437,12),to_signed(-482,12),to_signed(-526,12),
    to_signed(-568,12),to_signed(-609,12),to_signed(-649,12),to_signed(-687,12),
    to_signed(-724,12),to_signed(-758,12),to_signed(-791,12),to_signed(-822,12),
    to_signed(-851,12),to_signed(-878,12),to_signed(-903,12),to_signed(-926,12),
    to_signed(-946,12),to_signed(-964,12),to_signed(-980,12),to_signed(-993,12),
    to_signed(-1004,12),to_signed(-1013,12),to_signed(-1019,12),to_signed(-1023,12),
    to_signed(-1024,12),to_signed(-1023,12),to_signed(-1019,12),to_signed(-1013,12),
    to_signed(-1004,12),to_signed(-993,12),to_signed(-980,12),to_signed(-964,12),
    to_signed(-946,12),to_signed(-926,12),to_signed(-903,12),to_signed(-878,12),
    to_signed(-851,12),to_signed(-822,12),to_signed(-791,12),to_signed(-758,12),
    to_signed(-724,12),to_signed(-687,12),to_signed(-649,12),to_signed(-609,12),
    to_signed(-568,12),to_signed(-526,12),to_signed(-482,12),to_signed(-437,12),
    to_signed(-392,12),to_signed(-345,12),to_signed(-297,12),to_signed(-249,12),
    to_signed(-200,12),to_signed(-150,12),to_signed(-100,12),to_signed(-50,12)
  );

  signal idx     : unsigned(7 downto 0);
  signal frac    : unsigned(7 downto 0);
  signal s0, s1  : signed(11 downto 0);
  signal diff    : signed(11 downto 0);
  signal interp  : signed(19 downto 0);  -- diff * frac (12 * 8 = 20 bit)
begin

  -- Pipeline stage 1: table lookup
  idx  <= phase(15 downto 8);
  frac <= phase(7 downto 0);

  process(clk)
  begin
    if rising_edge(clk) then
      s0 <= SINE_ROM(to_integer(idx));
      s1 <= SINE_ROM(to_integer(idx + 1));
    end if;
  end process;

  -- Pipeline stage 2: interpolation (uses 1 MULT18x18)
  diff <= s1 - s0;
  interp <= diff * signed("0" & frac);  -- 12-bit * 9-bit = 20-bit

  sine_out <= s0 + interp(19 downto 8);  -- s0 + (diff * frac >> 8)

end architecture rtl;
