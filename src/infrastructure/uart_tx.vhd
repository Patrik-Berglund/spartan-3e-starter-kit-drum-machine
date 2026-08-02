library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

-- Simple 115200 8N1 UART transmitter
-- 50 MHz clock, 434 clocks per bit

entity uart_tx is
  port (
    clk      : in  std_logic;
    rst      : in  std_logic;
    tx_data  : in  std_logic_vector(7 downto 0);
    tx_start : in  std_logic;
    tx_pin   : out std_logic;
    tx_ready : out std_logic
  );
end entity uart_tx;

architecture rtl of uart_tx is
  constant CLKS_PER_BIT : unsigned(8 downto 0) := to_unsigned(434, 9);

  type state_t is (S_IDLE, S_START, S_DATA, S_STOP);
  signal state   : state_t := S_IDLE;
  signal clk_cnt : unsigned(8 downto 0) := (others => '0');
  signal bit_idx : unsigned(2 downto 0) := (others => '0');
  signal shift   : std_logic_vector(7 downto 0) := (others => '0');
begin

  process(clk)
  begin
    if rising_edge(clk) then
      if rst = '1' then
        state  <= S_IDLE;
        tx_pin <= '1';
      else
        case state is
          when S_IDLE =>
            tx_pin <= '1';
            if tx_start = '1' then
              shift   <= tx_data;
              state   <= S_START;
              clk_cnt <= (others => '0');
            end if;

          when S_START =>
            tx_pin <= '0';
            if clk_cnt = CLKS_PER_BIT - 1 then
              clk_cnt <= (others => '0');
              state   <= S_DATA;
              bit_idx <= (others => '0');
            else
              clk_cnt <= clk_cnt + 1;
            end if;

          when S_DATA =>
            tx_pin <= shift(0);
            if clk_cnt = CLKS_PER_BIT - 1 then
              clk_cnt <= (others => '0');
              shift   <= '0' & shift(7 downto 1);
              if bit_idx = 7 then
                state <= S_STOP;
              else
                bit_idx <= bit_idx + 1;
              end if;
            else
              clk_cnt <= clk_cnt + 1;
            end if;

          when S_STOP =>
            tx_pin <= '1';
            if clk_cnt = CLKS_PER_BIT - 1 then
              state <= S_IDLE;
            else
              clk_cnt <= clk_cnt + 1;
            end if;
        end case;
      end if;
    end if;
  end process;

  tx_ready <= '1' when state = S_IDLE else '0';

end architecture rtl;
