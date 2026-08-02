library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

-- DAC sample capture buffer
-- 12288 samples x 16-bit stored in inferred BRAM (2 x 16384x8)
-- State machine: IDLE -> ARMED -> CAPTURING -> FULL -> DUMP_* -> IDLE
-- Captures mix_out (12-bit unsigned) converted to signed 16-bit
-- Dumps over UART TX on command (MSB first per sample)

entity sample_capture is
  port (
    clk         : in  std_logic;
    rst         : in  std_logic;
    sample_tick : in  std_logic;
    mix_in      : in  unsigned(11 downto 0);
    any_trig    : in  std_logic;
    cmd_arm     : in  std_logic;
    cmd_dump    : in  std_logic;
    -- Offset: number of samples to skip after trigger before capturing
    -- Set via register write before arming
    offset_hi   : in  unsigned(7 downto 0);  -- offset(15:8)
    offset_lo   : in  unsigned(7 downto 0);  -- offset(7:0)
    tx_data     : out std_logic_vector(7 downto 0);
    tx_start    : out std_logic;
    tx_ready    : in  std_logic;
    state_out   : out std_logic_vector(2 downto 0)
  );
end entity sample_capture;

architecture rtl of sample_capture is
  constant BUF_SIZE  : integer := 12288;
  constant BUF_DEPTH : integer := 16384;

  type ram_t is array(0 to BUF_DEPTH-1) of std_logic_vector(7 downto 0);
  signal ram_hi : ram_t := (others => (others => '0'));
  signal ram_lo : ram_t := (others => (others => '0'));

  attribute ram_style : string;
  attribute ram_style of ram_hi : signal is "block";
  attribute ram_style of ram_lo : signal is "block";

  -- States: simple sequential dump with proper handshake
  type state_t is (S_IDLE, S_ARMED, S_SKIPPING, S_CAPTURING, S_FULL,
                   S_DUMP_HI_LOAD, S_DUMP_HI_SEND, S_DUMP_HI_BUSY, S_DUMP_HI_WAIT,
                   S_DUMP_LO_LOAD, S_DUMP_LO_SEND, S_DUMP_LO_BUSY, S_DUMP_LO_WAIT);
  signal state : state_t := S_IDLE;

  signal wr_ptr : unsigned(13 downto 0) := (others => '0');
  signal rd_ptr : unsigned(13 downto 0) := (others => '0');
  signal skip_cnt : unsigned(15 downto 0) := (others => '0');

  signal sample_s16 : signed(15 downto 0);
  signal tx_byte    : std_logic_vector(7 downto 0) := (others => '0');
  signal tx_start_i : std_logic := '0';

begin

  -- Convert: (mix_out << 4) - 32768 => signed 16-bit centered
  sample_s16 <= signed(mix_in & "0000") - to_signed(32768, 16);

  state_out <= "000" when state = S_IDLE else
               "001" when state = S_ARMED else
               "010" when state = S_CAPTURING else
               "011" when state = S_FULL else
               "100";

  tx_data  <= tx_byte;
  tx_start <= tx_start_i;

  process(clk)
  begin
    if rising_edge(clk) then
      tx_start_i <= '0';

      if rst = '1' then
        state  <= S_IDLE;
        wr_ptr <= (others => '0');
        rd_ptr <= (others => '0');
      else
        case state is
          when S_IDLE =>
            if cmd_arm = '1' then
              state  <= S_ARMED;
              wr_ptr <= (others => '0');
            end if;

          when S_ARMED =>
            if any_trig = '1' then
              -- Load offset and start skipping (or go straight to capture if 0)
              skip_cnt <= offset_hi & offset_lo;
              if (offset_hi & offset_lo) = 0 then
                state <= S_CAPTURING;
              else
                state <= S_SKIPPING;
              end if;
            end if;

          when S_SKIPPING =>
            if sample_tick = '1' then
              if skip_cnt = 1 then
                state <= S_CAPTURING;
              else
                skip_cnt <= skip_cnt - 1;
              end if;
            end if;

          when S_CAPTURING =>
            if sample_tick = '1' then
              ram_hi(to_integer(wr_ptr)) <= std_logic_vector(sample_s16(15 downto 8));
              ram_lo(to_integer(wr_ptr)) <= std_logic_vector(sample_s16(7 downto 0));
              if wr_ptr = BUF_SIZE - 1 then
                state <= S_FULL;
              else
                wr_ptr <= wr_ptr + 1;
              end if;
            end if;

          when S_FULL =>
            if cmd_dump = '1' then
              rd_ptr <= (others => '0');
              state  <= S_DUMP_HI_LOAD;
            end if;

          -- === DUMP HIGH BYTE ===
          when S_DUMP_HI_LOAD =>
            -- Load hi byte from BRAM (1 cycle for read)
            tx_byte <= ram_hi(to_integer(rd_ptr));
            state   <= S_DUMP_HI_SEND;

          when S_DUMP_HI_SEND =>
            -- Wait for UART ready, then send
            if tx_ready = '1' then
              tx_start_i <= '1';
              state      <= S_DUMP_HI_BUSY;
            end if;

          when S_DUMP_HI_BUSY =>
            -- Wait for UART to become busy (tx_ready = '0')
            if tx_ready = '0' then
              state <= S_DUMP_HI_WAIT;
            end if;

          when S_DUMP_HI_WAIT =>
            -- Wait for UART to finish (tx_ready = '1' again)
            if tx_ready = '1' then
              state <= S_DUMP_LO_LOAD;
            end if;

          -- === DUMP LOW BYTE ===
          when S_DUMP_LO_LOAD =>
            -- Load lo byte from BRAM
            tx_byte <= ram_lo(to_integer(rd_ptr));
            state   <= S_DUMP_LO_SEND;

          when S_DUMP_LO_SEND =>
            -- Wait for UART ready, then send
            if tx_ready = '1' then
              tx_start_i <= '1';
              state      <= S_DUMP_LO_BUSY;
            end if;

          when S_DUMP_LO_BUSY =>
            -- Wait for UART to become busy
            if tx_ready = '0' then
              state <= S_DUMP_LO_WAIT;
            end if;

          when S_DUMP_LO_WAIT =>
            -- Wait for UART to finish, then advance
            if tx_ready = '1' then
              if rd_ptr = BUF_SIZE - 1 then
                state <= S_IDLE;
              else
                rd_ptr <= rd_ptr + 1;
                state  <= S_DUMP_HI_LOAD;
              end if;
            end if;

          when others =>
            state <= S_IDLE;
        end case;
      end if;
    end if;
  end process;

end architecture rtl;
