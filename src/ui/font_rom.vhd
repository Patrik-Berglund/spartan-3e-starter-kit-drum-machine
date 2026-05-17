library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity font_rom is
  port (
    char_code : in  unsigned(6 downto 0);  -- ASCII 0-127 (we use 32-127)
    row       : in  unsigned(2 downto 0);  -- row within character (0-7)
    data      : out std_logic_vector(7 downto 0)  -- 8 pixels, MSB=left
  );
end entity font_rom;

architecture rtl of font_rom is
  -- 64 characters (space..underscore) x 8 rows = 512 bytes
  type rom_t is array (0 to 511) of std_logic_vector(7 downto 0);
  constant ROM : rom_t := (
    -- Space (32)
    x"00", x"00", x"00", x"00", x"00", x"00", x"00", x"00",
    -- ! (33)
    x"18", x"18", x"18", x"18", x"18", x"00", x"18", x"00",
    -- " (34)
    x"6C", x"6C", x"24", x"00", x"00", x"00", x"00", x"00",
    -- # (35)
    x"6C", x"6C", x"FE", x"6C", x"FE", x"6C", x"6C", x"00",
    -- $ (36)
    x"18", x"7E", x"C0", x"7C", x"06", x"FC", x"18", x"00",
    -- % (37)
    x"00", x"C6", x"CC", x"18", x"30", x"66", x"C6", x"00",
    -- & (38)
    x"38", x"6C", x"38", x"76", x"DC", x"CC", x"76", x"00",
    -- ' (39)
    x"18", x"18", x"30", x"00", x"00", x"00", x"00", x"00",
    -- ( (40)
    x"0C", x"18", x"30", x"30", x"30", x"18", x"0C", x"00",
    -- ) (41)
    x"30", x"18", x"0C", x"0C", x"0C", x"18", x"30", x"00",
    -- * (42)
    x"00", x"66", x"3C", x"FF", x"3C", x"66", x"00", x"00",
    -- + (43)
    x"00", x"18", x"18", x"7E", x"18", x"18", x"00", x"00",
    -- , (44)
    x"00", x"00", x"00", x"00", x"00", x"18", x"18", x"30",
    -- - (45)
    x"00", x"00", x"00", x"7E", x"00", x"00", x"00", x"00",
    -- . (46)
    x"00", x"00", x"00", x"00", x"00", x"18", x"18", x"00",
    -- / (47)
    x"06", x"0C", x"18", x"30", x"60", x"C0", x"80", x"00",
    -- 0 (48)
    x"7C", x"C6", x"CE", x"DE", x"F6", x"E6", x"7C", x"00",
    -- 1 (49)
    x"18", x"38", x"78", x"18", x"18", x"18", x"7E", x"00",
    -- 2 (50)
    x"7C", x"C6", x"06", x"1C", x"30", x"60", x"FE", x"00",
    -- 3 (51)
    x"7C", x"C6", x"06", x"3C", x"06", x"C6", x"7C", x"00",
    -- 4 (52)
    x"1C", x"3C", x"6C", x"CC", x"FE", x"0C", x"0C", x"00",
    -- 5 (53)
    x"FE", x"C0", x"FC", x"06", x"06", x"C6", x"7C", x"00",
    -- 6 (54)
    x"3C", x"60", x"C0", x"FC", x"C6", x"C6", x"7C", x"00",
    -- 7 (55)
    x"FE", x"C6", x"0C", x"18", x"30", x"30", x"30", x"00",
    -- 8 (56)
    x"7C", x"C6", x"C6", x"7C", x"C6", x"C6", x"7C", x"00",
    -- 9 (57)
    x"7C", x"C6", x"C6", x"7E", x"06", x"0C", x"78", x"00",
    -- : (58)
    x"00", x"18", x"18", x"00", x"00", x"18", x"18", x"00",
    -- ; (59)
    x"00", x"18", x"18", x"00", x"00", x"18", x"18", x"30",
    -- < (60)
    x"0C", x"18", x"30", x"60", x"30", x"18", x"0C", x"00",
    -- = (61)
    x"00", x"00", x"7E", x"00", x"7E", x"00", x"00", x"00",
    -- > (62)
    x"60", x"30", x"18", x"0C", x"18", x"30", x"60", x"00",
    -- ? (63)
    x"7C", x"C6", x"0C", x"18", x"18", x"00", x"18", x"00",
    -- @ (64)
    x"7C", x"C6", x"DE", x"DE", x"DC", x"C0", x"7C", x"00",
    -- A (65)
    x"38", x"6C", x"C6", x"C6", x"FE", x"C6", x"C6", x"00",
    -- B (66)
    x"FC", x"C6", x"C6", x"FC", x"C6", x"C6", x"FC", x"00",
    -- C (67)
    x"7C", x"C6", x"C0", x"C0", x"C0", x"C6", x"7C", x"00",
    -- D (68)
    x"F8", x"CC", x"C6", x"C6", x"C6", x"CC", x"F8", x"00",
    -- E (69)
    x"FE", x"C0", x"C0", x"FC", x"C0", x"C0", x"FE", x"00",
    -- F (70)
    x"FE", x"C0", x"C0", x"FC", x"C0", x"C0", x"C0", x"00",
    -- G (71)
    x"7C", x"C6", x"C0", x"C0", x"CE", x"C6", x"7E", x"00",
    -- H (72)
    x"C6", x"C6", x"C6", x"FE", x"C6", x"C6", x"C6", x"00",
    -- I (73)
    x"7E", x"18", x"18", x"18", x"18", x"18", x"7E", x"00",
    -- J (74)
    x"1E", x"06", x"06", x"06", x"06", x"C6", x"7C", x"00",
    -- K (75)
    x"C6", x"CC", x"D8", x"F0", x"D8", x"CC", x"C6", x"00",
    -- L (76)
    x"C0", x"C0", x"C0", x"C0", x"C0", x"C0", x"FE", x"00",
    -- M (77)
    x"C6", x"EE", x"FE", x"D6", x"C6", x"C6", x"C6", x"00",
    -- N (78)
    x"C6", x"E6", x"F6", x"DE", x"CE", x"C6", x"C6", x"00",
    -- O (79)
    x"7C", x"C6", x"C6", x"C6", x"C6", x"C6", x"7C", x"00",
    -- P (80)
    x"FC", x"C6", x"C6", x"FC", x"C0", x"C0", x"C0", x"00",
    -- Q (81)
    x"7C", x"C6", x"C6", x"C6", x"D6", x"CC", x"76", x"00",
    -- R (82)
    x"FC", x"C6", x"C6", x"FC", x"D8", x"CC", x"C6", x"00",
    -- S (83)
    x"7C", x"C6", x"C0", x"7C", x"06", x"C6", x"7C", x"00",
    -- T (84)
    x"7E", x"18", x"18", x"18", x"18", x"18", x"18", x"00",
    -- U (85)
    x"C6", x"C6", x"C6", x"C6", x"C6", x"C6", x"7C", x"00",
    -- V (86)
    x"C6", x"C6", x"C6", x"C6", x"6C", x"38", x"10", x"00",
    -- W (87)
    x"C6", x"C6", x"C6", x"D6", x"FE", x"EE", x"C6", x"00",
    -- X (88)
    x"C6", x"C6", x"6C", x"38", x"6C", x"C6", x"C6", x"00",
    -- Y (89)
    x"66", x"66", x"66", x"3C", x"18", x"18", x"18", x"00",
    -- Z (90)
    x"FE", x"06", x"0C", x"18", x"30", x"60", x"FE", x"00",
    -- [ (91)
    x"3C", x"30", x"30", x"30", x"30", x"30", x"3C", x"00",
    -- \ (92)
    x"C0", x"60", x"30", x"18", x"0C", x"06", x"02", x"00",
    -- ] (93)
    x"3C", x"0C", x"0C", x"0C", x"0C", x"0C", x"3C", x"00",
    -- ^ (94)
    x"10", x"38", x"6C", x"C6", x"00", x"00", x"00", x"00",
    -- _ (95)
    x"00", x"00", x"00", x"00", x"00", x"00", x"FE", x"00"
  );

  signal char_idx : unsigned(5 downto 0);
  signal addr : unsigned(8 downto 0);
begin
  -- Address = (char_code - 32) * 8 + row
  char_idx <= resize(char_code - 32, 6);
  addr <= char_idx & row;
  data <= ROM(to_integer(addr)) when to_integer(char_code) >= 32 and to_integer(char_code) < 96
          else x"00";
end architecture rtl;
