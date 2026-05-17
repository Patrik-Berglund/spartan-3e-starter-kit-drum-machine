library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

-- DAC driver for LTC2624 on Spartan-3E Starter Kit.
-- Sends 12-bit sample to channel A at sample_tick rate.
-- Uses spi_master for the 32-bit SPI transfer.
-- Also disables other SPI bus devices.

entity dac_driver is
  port (
    clk         : in  std_logic;
    rst         : in  std_logic;
    sample_tick : in  std_logic;
    sample_in   : in  unsigned(11 downto 0);
    -- SPI pins
    spi_sck     : out std_logic;
    spi_mosi    : out std_logic;
    spi_miso    : in  std_logic;
    dac_cs      : out std_logic;
    dac_clr     : out std_logic;
    -- Disable other SPI devices
    spi_ss_b    : out std_logic;  -- SPI Flash CS (active low, disable=1)
    amp_cs      : out std_logic;  -- Preamp CS (active low, disable=1)
    ad_conv     : out std_logic;  -- ADC convert (active high, disable=0)
    sf_ce0      : out std_logic;  -- StrataFlash CE (active low, disable=1)
    fpga_init_b : out std_logic   -- Platform Flash (active low, disable=1)
  );
end entity dac_driver;

architecture rtl of dac_driver is
  signal spi_start : std_logic := '0';
  signal spi_busy  : std_logic;
  signal spi_done  : std_logic;
  signal tx_word   : std_logic_vector(31 downto 0) := (others => '0');

  type state_t is (S_IDLE, S_LOAD, S_WAIT, S_DONE);
  signal state : state_t := S_IDLE;
  signal sample_hold : unsigned(11 downto 0) := (others => '0');
begin

  -- Disable all other SPI devices
  spi_ss_b    <= '1';
  amp_cs      <= '1';
  ad_conv     <= '0';
  sf_ce0      <= '1';
  fpga_init_b <= '1';
  dac_clr     <= '1';  -- not in reset

  u_spi : entity work.spi_master
    generic map (G_CLK_DIV => 4)  -- 50MHz/8 = 6.25 MHz SPI clock
    port map (
      clk      => clk,
      rst      => rst,
      tx_data  => tx_word,
      rx_data  => open,
      num_bits => to_unsigned(32, 6),
      start    => spi_start,
      busy     => spi_busy,
      done     => spi_done,
      spi_sck  => spi_sck,
      spi_mosi => spi_mosi,
      spi_miso => spi_miso
    );

  -- LTC2624 32-bit command word:
  -- [31:24] don't care (0x00)
  -- [23:20] command = 0011 (write and update)
  -- [19:16] address = 0000 (channel A)
  -- [15:4]  data (12-bit unsigned)
  -- [3:0]   don't care (0x0)

  process(clk)
  begin
    if rising_edge(clk) then
      if rst = '1' then
        state     <= S_IDLE;
        spi_start <= '0';
        dac_cs    <= '1';
      else
        spi_start <= '0';

        case state is
          when S_IDLE =>
            dac_cs <= '1';
            if sample_tick = '1' then
              sample_hold <= sample_in;
              state <= S_LOAD;
            end if;

          when S_LOAD =>
            -- Build command word
            tx_word <= x"00" & "0011" & "0000" &
                       std_logic_vector(sample_hold) & "0000";
            dac_cs    <= '0';
            spi_start <= '1';
            state     <= S_WAIT;

          when S_WAIT =>
            dac_cs <= '0';
            if spi_done = '1' then
              state <= S_DONE;
            end if;

          when S_DONE =>
            dac_cs <= '1';  -- rising edge triggers DAC conversion
            state  <= S_IDLE;
        end case;
      end if;
    end if;
  end process;

end architecture rtl;
