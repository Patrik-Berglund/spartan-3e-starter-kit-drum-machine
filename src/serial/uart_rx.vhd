library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity uart_rx is
  port (
    clk       : in  std_logic;
    rst       : in  std_logic;
    rx        : in  std_logic;
    wr_en     : out std_logic;
    wr_addr   : out unsigned(6 downto 0);
    wr_data   : out unsigned(7 downto 0)
  );
end entity uart_rx;

architecture rtl of uart_rx is
  constant CLKS_PER_BIT : unsigned(8 downto 0) := to_unsigned(434, 9);
  constant HALF_BIT     : unsigned(8 downto 0) := to_unsigned(217, 9);

  type state_t is (S_IDLE, S_START, S_DATA, S_STOP);
  signal state    : state_t := S_IDLE;
  signal bit_cnt  : unsigned(2 downto 0) := (others => '0');
  signal clk_cnt  : unsigned(8 downto 0) := (others => '0');
  signal shift    : std_logic_vector(7 downto 0) := (others => '0');
  signal rx_sync  : std_logic_vector(1 downto 0) := "11";
  signal byte_cnt : std_logic := '0';
  signal addr_reg : unsigned(6 downto 0) := (others => '0');
begin

  process(clk)
  begin
    if rising_edge(clk) then
      rx_sync <= rx_sync(0) & rx;
    end if;
  end process;

  process(clk)
    variable got_byte : std_logic;
  begin
    if rising_edge(clk) then
      wr_en <= '0';
      got_byte := '0';

      if rst = '1' then
        state <= S_IDLE;
        byte_cnt <= '0';
      else
        case state is
          when S_IDLE =>
            if rx_sync(1) = '0' then
              state <= S_START;
              clk_cnt <= (others => '0');
            end if;

          when S_START =>
            if clk_cnt = HALF_BIT then
              if rx_sync(1) = '0' then
                state <= S_DATA;
                clk_cnt <= (others => '0');
                bit_cnt <= (others => '0');
              else
                state <= S_IDLE;
              end if;
            else
              clk_cnt <= clk_cnt + 1;
            end if;

          when S_DATA =>
            if clk_cnt = CLKS_PER_BIT then
              clk_cnt <= (others => '0');
              shift <= rx_sync(1) & shift(7 downto 1);
              if bit_cnt = 7 then
                state <= S_STOP;
              else
                bit_cnt <= bit_cnt + 1;
              end if;
            else
              clk_cnt <= clk_cnt + 1;
            end if;

          when S_STOP =>
            if clk_cnt = CLKS_PER_BIT then
              state <= S_IDLE;
              got_byte := '1';
            else
              clk_cnt <= clk_cnt + 1;
            end if;
        end case;

        -- 2-byte protocol
        if got_byte = '1' then
          if byte_cnt = '0' then
            addr_reg <= unsigned(shift(6 downto 0));
            byte_cnt <= '1';
          else
            wr_addr <= addr_reg;
            wr_data <= unsigned(shift);
            wr_en <= '1';
            byte_cnt <= '0';
          end if;
        end if;
      end if;
    end if;
  end process;

end architecture rtl;
