library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity tom is
  generic (
    G_FREQ : unsigned(15 downto 0) := to_unsigned(221, 16)
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
  signal phase : unsigned(15 downto 0) := (others => '0');
  signal freq  : unsigned(15 downto 0) := (others => '0');
  signal amp   : unsigned(15 downto 0) := (others => '0');
  signal active: std_logic := '0';
  signal div   : unsigned(0 downto 0) := (others => '0');

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

  signal sine_val : signed(11 downto 0);
begin
  sine_val <= SINE(to_integer(phase(15 downto 10)));

  process(clk)
    variable product : signed(23 downto 0);
  begin
    if rising_edge(clk) then
      if rst = '1' then
        phase <= (others => '0'); freq <= (others => '0');
        amp <= (others => '0'); active <= '0'; div <= "0";
        audio_out <= (others => '0');
      else
        if trigger = '1' then
          active <= '1'; phase <= (others => '0');
          freq <= G_FREQ + ("00" & G_FREQ(15 downto 2));  -- start 25% higher
          amp <= to_unsigned(65535, 16); div <= "0";
        end if;

        if sample_tick = '1' and active = '1' then
          phase <= phase + freq;

          -- Pitch dive to base
          if freq > G_FREQ then freq <= freq - 1; end if;

          -- Sine * amplitude
          product := sine_val * signed('0' & amp(15 downto 5));
          audio_out <= product(22 downto 11);

          -- Exponential decay K=12 (tau ~84ms)
          amp <= amp - ("000000000000" & amp(15 downto 12));
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
