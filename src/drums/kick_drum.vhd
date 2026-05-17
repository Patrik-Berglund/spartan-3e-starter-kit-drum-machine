library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity kick_drum is
  port (
    clk         : in  std_logic;
    rst         : in  std_logic;
    sample_tick : in  std_logic;
    trigger     : in  std_logic;
    audio_out   : out signed(11 downto 0)
  );
end entity kick_drum;

architecture rtl of kick_drum is
  signal phase  : unsigned(15 downto 0) := (others => '0');
  signal freq   : unsigned(15 downto 0) := (others => '0');
  signal amp    : unsigned(15 downto 0) := (others => '0');  -- 16-bit for smooth exp decay
  signal active : std_logic := '0';
  signal div    : unsigned(2 downto 0) := (others => '0');

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
        amp <= (others => '0'); active <= '0'; div <= (others => '0');
        audio_out <= (others => '0');
      else
        if trigger = '1' then
          active <= '1';
          phase <= (others => '0');
          freq  <= to_unsigned(150, 16);  -- 112Hz
          amp   <= to_unsigned(65535, 16);
          div   <= (others => '0');
        end if;

        if sample_tick = '1' and active = '1' then
          phase <= phase + freq;
          div <= div + 1;

          -- Pitch sweep: 112Hz->56Hz in ~10ms (dec by 1 every 7 samples)
          if div = "110" and freq > 75 then
            freq <= freq - 1;
            div <= (others => '0');
          end if;

          -- Multiply sine by amplitude: 12-bit * 11-bit = 23-bit
          product := sine_val * signed('0' & amp(15 downto 5));
          audio_out <= product(22 downto 11);

          -- Exponential decay: amp -= amp >> 12 (tau ~84ms)
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
