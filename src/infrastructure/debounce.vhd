library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity debounce is
  generic (
    G_WIDTH     : integer := 1;
    G_COUNT_MAX : integer := 500000  -- 10 ms @ 50 MHz
  );
  port (
    clk    : in  std_logic;
    rst    : in  std_logic;
    input  : in  std_logic_vector(G_WIDTH-1 downto 0);
    output : out std_logic_vector(G_WIDTH-1 downto 0)
  );
end entity debounce;

architecture rtl of debounce is
  signal sync0, sync1 : std_logic_vector(G_WIDTH-1 downto 0) := (others => '0');
  signal stable       : std_logic_vector(G_WIDTH-1 downto 0) := (others => '0');
  type count_array is array (0 to G_WIDTH-1) of integer range 0 to G_COUNT_MAX;
  signal counts : count_array := (others => 0);
begin
  process(clk)
  begin
    if rising_edge(clk) then
      if rst = '1' then
        sync0  <= (others => '0');
        sync1  <= (others => '0');
        stable <= (others => '0');
        counts <= (others => 0);
      else
        sync0 <= input;
        sync1 <= sync0;
        for i in 0 to G_WIDTH-1 loop
          if sync1(i) /= stable(i) then
            if counts(i) = G_COUNT_MAX then
              stable(i) <= sync1(i);
              counts(i) <= 0;
            else
              counts(i) <= counts(i) + 1;
            end if;
          else
            counts(i) <= 0;
          end if;
        end loop;
      end if;
    end if;
  end process;

  output <= stable;
end architecture rtl;
