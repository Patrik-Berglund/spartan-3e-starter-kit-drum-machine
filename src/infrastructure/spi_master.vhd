library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

-- Shared SPI master with variable-width transfers.
-- Directly drives SCK and MOSI. CS is managed externally.

entity spi_master is
  generic (
    G_CLK_DIV : integer := 8  -- sck half-period in clk cycles
  );
  port (
    clk      : in  std_logic;
    rst      : in  std_logic;
    -- Transaction interface
    tx_data  : in  std_logic_vector(31 downto 0);  -- MSB-aligned
    rx_data  : out std_logic_vector(31 downto 0);  -- MSB-aligned
    num_bits : in  unsigned(5 downto 0);           -- 1-32
    start    : in  std_logic;
    busy     : out std_logic;
    done     : out std_logic;
    -- SPI pins
    spi_sck  : out std_logic;
    spi_mosi : out std_logic;
    spi_miso : in  std_logic
  );
end entity spi_master;

architecture rtl of spi_master is
  type state_t is (S_IDLE, S_LEADING, S_TRAILING);
  signal state    : state_t := S_IDLE;
  signal shift_tx : std_logic_vector(31 downto 0) := (others => '0');
  signal shift_rx : std_logic_vector(31 downto 0) := (others => '0');
  signal bits_rem : unsigned(5 downto 0) := (others => '0');
  signal clk_cnt  : integer range 0 to G_CLK_DIV-1 := 0;
  signal sck_int  : std_logic := '0';
begin

  process(clk)
  begin
    if rising_edge(clk) then
      if rst = '1' then
        state    <= S_IDLE;
        sck_int  <= '0';
        shift_tx <= (others => '0');
        shift_rx <= (others => '0');
        bits_rem <= (others => '0');
        clk_cnt  <= 0;
        done     <= '0';
      else
        done <= '0';

        case state is
          when S_IDLE =>
            sck_int <= '0';
            if start = '1' then
              shift_tx <= tx_data;
              shift_rx <= (others => '0');
              bits_rem <= num_bits - 1;
              clk_cnt  <= 0;
              state    <= S_LEADING;
            end if;

          -- SCK low phase: MOSI is valid (set from shift_tx MSB)
          when S_LEADING =>
            sck_int <= '0';
            if clk_cnt = G_CLK_DIV - 1 then
              clk_cnt <= 0;
              sck_int <= '1';
              -- Sample MISO on rising edge
              shift_rx <= shift_rx(30 downto 0) & spi_miso;
              state <= S_TRAILING;
            else
              clk_cnt <= clk_cnt + 1;
            end if;

          -- SCK high phase
          when S_TRAILING =>
            sck_int <= '1';
            if clk_cnt = G_CLK_DIV - 1 then
              clk_cnt <= 0;
              -- Shift MOSI on falling edge
              shift_tx <= shift_tx(30 downto 0) & '0';
              if bits_rem = 0 then
                sck_int <= '0';
                rx_data <= shift_rx;
                done    <= '1';
                state   <= S_IDLE;
              else
                bits_rem <= bits_rem - 1;
                state    <= S_LEADING;
              end if;
            else
              clk_cnt <= clk_cnt + 1;
            end if;

        end case;
      end if;
    end if;
  end process;

  spi_sck  <= sck_int;
  spi_mosi <= shift_tx(31);
  busy     <= '0' when state = S_IDLE else '1';

end architecture rtl;
