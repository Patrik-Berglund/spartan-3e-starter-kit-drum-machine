library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity rimshot is
  port (
    clk         : in  std_logic;
    rst         : in  std_logic;
    sample_tick : in  std_logic;
    trigger     : in  std_logic;
    audio_out   : out signed(15 downto 0)
  );
end entity rimshot;

architecture rtl of rimshot is
  signal ph1, ph2, ph3 : unsigned(15 downto 0) := (others => '0');
  signal amp : unsigned(15 downto 0) := (others => '0');
  signal active : std_logic := '0';

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

  signal s1, s2, s3 : signed(11 downto 0);
begin
  s1 <= SINE(to_integer(ph1(15 downto 10)));
  s2 <= SINE(to_integer(ph2(15 downto 10)));
  s3 <= SINE(to_integer(ph3(15 downto 10)));

  process(clk)
    variable mix : signed(13 downto 0);
    variable product : signed(23 downto 0);
  begin
    if rising_edge(clk) then
      if rst = '1' then
        ph1 <= (others => '0'); ph2 <= (others => '0'); ph3 <= (others => '0');
        amp <= (others => '0'); active <= '0'; audio_out <= (others => '0');
      else
        if trigger = '1' then
          active <= '1';
          ph1 <= (others => '0'); ph2 <= (others => '0'); ph3 <= (others => '0');
          amp <= to_unsigned(65535, 16);
        end if;

        if sample_tick = '1' and active = '1' then
          -- 455Hz=610, 680Hz=912, 1020Hz=1368
          ph1 <= ph1 + to_unsigned(610, 16);
          ph2 <= ph2 + to_unsigned(912, 16);
          ph3 <= ph3 + to_unsigned(1368, 16);

          -- Sum 3 sines
          mix := resize(s1, 14) + resize(s2, 14) + resize(s3, 14);

          -- Apply amplitude
          product := resize(mix, 12) * signed('0' & amp(15 downto 5));
          audio_out <= product(22 downto 7);

          -- Very fast exponential decay K=8 (tau ~5ms)
          amp <= amp - ("00000000" & amp(15 downto 8));
          if amp < 64 then active <= '0'; audio_out <= (others => '0');
          end if;
        elsif active = '0' then
          audio_out <= (others => '0');
        end if;
      end if;
    end if;
  end process;
end architecture rtl;
