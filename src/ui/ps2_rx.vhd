library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

-- PS/2 keyboard receiver
-- Outputs scan code bytes with make/break/extended flags

entity ps2_rx is
  port (
    clk       : in  std_logic;  -- 50 MHz
    rst       : in  std_logic;
    ps2_clk   : in  std_logic;
    ps2_data  : in  std_logic;
    -- Output: one-clock pulse when a key event is ready
    key_valid : out std_logic;
    key_code  : out std_logic_vector(7 downto 0);  -- scan code
    key_break : out std_logic;  -- '1' = release, '0' = press
    key_ext   : out std_logic   -- '1' = extended (E0 prefix)
  );
end entity ps2_rx;

architecture rtl of ps2_rx is
  -- Synchronize PS/2 signals
  signal clk_sync  : std_logic_vector(2 downto 0) := "111";
  signal data_sync : std_logic_vector(1 downto 0) := "11";
  signal clk_fall  : std_logic;

  -- Shift register for 11-bit frame
  signal shift_reg : std_logic_vector(10 downto 0) := (others => '1');
  signal bit_cnt   : unsigned(3 downto 0) := (others => '0');

  -- Byte output
  signal rx_byte   : std_logic_vector(7 downto 0);
  signal rx_valid  : std_logic := '0';

  -- State for multi-byte sequences
  signal is_break  : std_logic := '0';
  signal is_ext    : std_logic := '0';

  -- Timeout: if no bits for ~100us, reset receiver
  signal timeout   : unsigned(12 downto 0) := (others => '0');

begin

  -- Synchronize PS/2 clock (3-stage for metastability + edge detect)
  process(clk)
  begin
    if rising_edge(clk) then
      clk_sync  <= clk_sync(1 downto 0) & ps2_clk;
      data_sync <= data_sync(0) & ps2_data;
    end if;
  end process;

  -- Falling edge of PS/2 clock
  clk_fall <= clk_sync(2) and not clk_sync(1);

  -- Shift in bits on falling edge of PS/2 clock
  process(clk)
  begin
    if rising_edge(clk) then
      rx_valid <= '0';

      if rst = '1' then
        bit_cnt  <= (others => '0');
        shift_reg <= (others => '1');
        timeout  <= (others => '0');
      else
        -- Timeout reset
        if bit_cnt /= 0 then
          timeout <= timeout + 1;
          if timeout = 0 then  -- wrapped around (~82us at 50MHz with 13 bits)
            bit_cnt <= (others => '0');
          end if;
        end if;

        if clk_fall = '1' then
          timeout <= (others => '0');
          shift_reg <= data_sync(1) & shift_reg(10 downto 1);
          if bit_cnt = 10 then
            -- Full frame received: start(0) + 8 data + parity + stop(1)
            bit_cnt <= (others => '0');
            -- Check start=0 and stop=1
            if shift_reg(0) = '0' and data_sync(1) = '1' then
              rx_byte <= shift_reg(8 downto 1);
              rx_valid <= '1';
            end if;
          else
            bit_cnt <= bit_cnt + 1;
          end if;
        end if;
      end if;
    end if;
  end process;

  -- Decode multi-byte sequences (E0 prefix, F0 break code)
  process(clk)
  begin
    if rising_edge(clk) then
      key_valid <= '0';

      if rst = '1' then
        is_break <= '0';
        is_ext   <= '0';
      elsif rx_valid = '1' then
        if rx_byte = x"F0" then
          is_break <= '1';
        elsif rx_byte = x"E0" then
          is_ext <= '1';
        else
          -- Actual scan code
          key_code  <= rx_byte;
          key_break <= is_break;
          key_ext   <= is_ext;
          key_valid <= '1';
          is_break  <= '0';
          is_ext    <= '0';
        end if;
      end if;
    end if;
  end process;

end architecture rtl;
