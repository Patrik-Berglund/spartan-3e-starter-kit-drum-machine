library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity rotary_decoder is
  generic (
    G_DEBOUNCE_MAX : integer := 500000  -- 10 ms @ 50 MHz
  );
  port (
    clk        : in  std_logic;
    rst        : in  std_logic;
    rot_a      : in  std_logic;
    rot_b      : in  std_logic;
    rot_center : in  std_logic;
    rot_event  : out std_logic;
    rot_dir    : out std_logic;  -- '1'=CW, '0'=CCW
    rot_press  : out std_logic
  );
end entity rotary_decoder;

architecture rtl of rotary_decoder is
  signal a_deb, b_deb, c_deb : std_logic_vector(0 downto 0);
  signal a_prev : std_logic := '0';
  signal c_prev : std_logic := '0';
begin

  deb_ab : entity work.debounce
    generic map (G_WIDTH => 1, G_COUNT_MAX => G_DEBOUNCE_MAX)
    port map (clk => clk, rst => rst, input(0) => rot_a, output => a_deb);

  deb_b : entity work.debounce
    generic map (G_WIDTH => 1, G_COUNT_MAX => G_DEBOUNCE_MAX)
    port map (clk => clk, rst => rst, input(0) => rot_b, output => b_deb);

  deb_c : entity work.debounce
    generic map (G_WIDTH => 1, G_COUNT_MAX => G_DEBOUNCE_MAX)
    port map (clk => clk, rst => rst, input(0) => rot_center, output => c_deb);

  process(clk)
  begin
    if rising_edge(clk) then
      if rst = '1' then
        a_prev    <= '0';
        c_prev    <= '0';
        rot_event <= '0';
        rot_dir   <= '0';
        rot_press <= '0';
      else
        rot_event <= '0';
        rot_press <= '0';

        -- Detect rotation on rising edge of A
        if a_deb(0) = '1' and a_prev = '0' then
          rot_event <= '1';
          rot_dir   <= not b_deb(0);  -- B high on A rise = CW
        end if;
        a_prev <= a_deb(0);

        -- Detect center press (rising edge)
        if c_deb(0) = '1' and c_prev = '0' then
          rot_press <= '1';
        end if;
        c_prev <= c_deb(0);
      end if;
    end if;
  end process;

end architecture rtl;
