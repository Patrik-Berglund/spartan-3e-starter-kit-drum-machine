-- Register map for TR-808 drum machine
-- Dual-port RAM: Port A = write (serial/keyboard/encoder), Port B = read (voices/VGA)
-- 128 x 8-bit registers
--
-- Address map:
--   0x00-0x0A: Voice trigger (write 1 to trigger, auto-clears)
--   0x10-0x1A: Voice level (0-255)
--   0x20-0x2A: Voice param 1 (TONE/TUNING)
--   0x30-0x3A: Voice param 2 (DECAY/SNAPPY)
--   0x40:      BPM (40-240)
--   0x41:      Play/Stop (write 1 to toggle)
--   0x42:      Current step (read-only)
--   0x43:      Edit track (0-10)
--   0x44:      Edit step (0-15)
--
-- Voice indices: 0=BD, 1=SD, 2=LT, 3=MT, 4=HT, 5=RS, 6=CP, 7=CB, 8=CY, 9=OH, 10=CH

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity register_map is
  port (
    clk       : in  std_logic;
    rst       : in  std_logic;
    -- Port A: write access (serial, keyboard, encoder)
    wr_en     : in  std_logic;
    wr_addr   : in  unsigned(6 downto 0);
    wr_data   : in  unsigned(7 downto 0);
    -- Port B: read access (voices, VGA, any module)
    rd_addr   : in  unsigned(6 downto 0);
    rd_data   : out unsigned(7 downto 0);
    -- Direct outputs for voice triggers (active one clock cycle)
    triggers  : out std_logic_vector(10 downto 0);
    -- Direct outputs for commonly used params (avoid read latency)
    bpm       : out unsigned(7 downto 0);
    playing   : out std_logic;
    -- Direct outputs for voice parameters
    bd_tone   : out unsigned(7 downto 0);
    bd_decay  : out unsigned(7 downto 0);
    sd_tone   : out unsigned(7 downto 0);
    sd_snappy : out unsigned(7 downto 0);
    lt_tuning : out unsigned(7 downto 0);
    mt_tuning : out unsigned(7 downto 0);
    ht_tuning : out unsigned(7 downto 0);
    cy_tone   : out unsigned(7 downto 0);
    cy_decay  : out unsigned(7 downto 0);
    oh_decay  : out unsigned(7 downto 0)
  );
end entity register_map;

architecture rtl of register_map is
  type reg_array_t is array(0 to 127) of unsigned(7 downto 0);
  signal regs : reg_array_t := (
    -- Default levels (0x10-0x1A) = 200
    16 => to_unsigned(200, 8), 17 => to_unsigned(200, 8),
    18 => to_unsigned(200, 8), 19 => to_unsigned(200, 8),
    20 => to_unsigned(200, 8), 21 => to_unsigned(200, 8),
    22 => to_unsigned(200, 8), 23 => to_unsigned(200, 8),
    24 => to_unsigned(200, 8), 25 => to_unsigned(200, 8),
    26 => to_unsigned(200, 8),
    -- Default params (0x20-0x2A) = 128 (mid)
    32 => to_unsigned(128, 8), 33 => to_unsigned(128, 8),
    34 => to_unsigned(128, 8), 35 => to_unsigned(128, 8),
    36 => to_unsigned(128, 8), 37 => to_unsigned(128, 8),
    38 => to_unsigned(128, 8), 39 => to_unsigned(128, 8),
    40 => to_unsigned(128, 8), 41 => to_unsigned(128, 8),
    42 => to_unsigned(128, 8),
    -- Default params 2 (0x30-0x3A) = 128 (mid)
    48 => to_unsigned(128, 8), 49 => to_unsigned(128, 8),
    50 => to_unsigned(128, 8), 51 => to_unsigned(128, 8),
    52 => to_unsigned(128, 8), 53 => to_unsigned(128, 8),
    54 => to_unsigned(128, 8), 55 => to_unsigned(128, 8),
    56 => to_unsigned(128, 8), 57 => to_unsigned(128, 8),
    58 => to_unsigned(128, 8),
    -- BPM default
    64 => to_unsigned(120, 8),
    others => (others => '0')
  );
  signal trig_reg : std_logic_vector(10 downto 0) := (others => '0');
  signal play_state : std_logic := '0';
begin

  process(clk)
  begin
    if rising_edge(clk) then
      if rst = '1' then
        trig_reg <= (others => '0');
        play_state <= '0';
      else
        -- Auto-clear triggers after one cycle
        trig_reg <= (others => '0');

        if wr_en = '1' then
          -- Trigger registers (0x00-0x0A): pulse, don't store
          if wr_addr < 11 then
            trig_reg(to_integer(wr_addr)) <= '1';
          -- Play/stop toggle (0x41)
          elsif wr_addr = 65 and wr_data(0) = '1' then
            play_state <= not play_state;
          -- All other registers: store directly
          else
            regs(to_integer(wr_addr)) <= wr_data;
          end if;
        end if;
      end if;
    end if;
  end process;

  -- Read port (combinational)
  rd_data <= regs(to_integer(rd_addr));

  -- Direct outputs
  triggers <= trig_reg;
  bpm <= regs(64);
  playing <= play_state;

  -- Voice parameter direct outputs (zero logic cost - just wires)
  bd_tone   <= regs(32);  -- 0x20
  bd_decay  <= regs(48);  -- 0x30
  sd_tone   <= regs(33);  -- 0x21
  sd_snappy <= regs(49);  -- 0x31
  lt_tuning <= regs(34);  -- 0x22
  mt_tuning <= regs(35);  -- 0x23
  ht_tuning <= regs(36);  -- 0x24
  cy_tone   <= regs(40);  -- 0x28
  cy_decay  <= regs(56);  -- 0x38
  oh_decay  <= regs(57);  -- 0x39

end architecture rtl;
