library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity lcd_controller is
  port (
    clk    : in  std_logic;
    rst    : in  std_logic;
    line1  : in  std_logic_vector(127 downto 0);
    line2  : in  std_logic_vector(127 downto 0);
    update : in  std_logic;
    busy   : out std_logic;
    lcd_e  : out std_logic;
    lcd_rs : out std_logic;
    lcd_rw : out std_logic;
    lcd_db : out std_logic_vector(3 downto 0)
  );
end entity lcd_controller;

architecture rtl of lcd_controller is
  constant C_ENABLE : integer := 12;   -- 240 ns @ 50 MHz

  -- Command sequence for init + refresh
  -- Each entry: (rs, data_byte)
  -- Init: 8 commands, then set addr line1 + 16 chars + set addr line2 + 16 chars = 42 total
  constant SEQ_LEN : integer := 42;

  signal seq_idx   : integer range 0 to SEQ_LEN-1 := 0;
  signal seq_byte  : std_logic_vector(7 downto 0);
  signal seq_rs    : std_logic;

  type state_t is (S_POWERON, S_INIT0, S_INIT1, S_INIT2, S_INIT3,
                   S_IDLE, S_NIBBLE_HI, S_NIBBLE_HI_E, S_GAP,
                   S_NIBBLE_LO, S_NIBBLE_LO_E, S_WAIT, S_NEXT);
  signal state     : state_t := S_POWERON;
  signal wait_cnt  : integer range 0 to 750000 := 0;
  signal pending   : std_logic := '0';
  signal line1_buf : std_logic_vector(127 downto 0) := (others => '0');
  signal line2_buf : std_logic_vector(127 downto 0) := (others => '0');

  -- Wait times
  constant C_15MS  : integer := 750000;
  constant C_4_1MS : integer := 205000;
  constant C_100US : integer := 5000;
  constant C_40US  : integer := 2000;
  constant C_1_64MS: integer := 82000;
  constant C_1US   : integer := 50;

  -- Current wait target
  signal wait_target : integer range 0 to 750000 := 0;
begin

  lcd_rw <= '0';

  -- Determine current byte and RS based on seq_idx
  process(seq_idx, line1_buf, line2_buf)
  begin
    case seq_idx is
      -- Init commands (RS=0)
      when 0 => seq_rs <= '0'; seq_byte <= x"28";  -- Function set
      when 1 => seq_rs <= '0'; seq_byte <= x"06";  -- Entry mode
      when 2 => seq_rs <= '0'; seq_byte <= x"0C";  -- Display on
      when 3 => seq_rs <= '0'; seq_byte <= x"01";  -- Clear
      -- Set DD RAM addr line 1
      when 4 => seq_rs <= '0'; seq_byte <= x"80";
      -- Line 1 chars (idx 5..20)
      when 5  => seq_rs <= '1'; seq_byte <= line1_buf(127 downto 120);
      when 6  => seq_rs <= '1'; seq_byte <= line1_buf(119 downto 112);
      when 7  => seq_rs <= '1'; seq_byte <= line1_buf(111 downto 104);
      when 8  => seq_rs <= '1'; seq_byte <= line1_buf(103 downto 96);
      when 9  => seq_rs <= '1'; seq_byte <= line1_buf(95 downto 88);
      when 10 => seq_rs <= '1'; seq_byte <= line1_buf(87 downto 80);
      when 11 => seq_rs <= '1'; seq_byte <= line1_buf(79 downto 72);
      when 12 => seq_rs <= '1'; seq_byte <= line1_buf(71 downto 64);
      when 13 => seq_rs <= '1'; seq_byte <= line1_buf(63 downto 56);
      when 14 => seq_rs <= '1'; seq_byte <= line1_buf(55 downto 48);
      when 15 => seq_rs <= '1'; seq_byte <= line1_buf(47 downto 40);
      when 16 => seq_rs <= '1'; seq_byte <= line1_buf(39 downto 32);
      when 17 => seq_rs <= '1'; seq_byte <= line1_buf(31 downto 24);
      when 18 => seq_rs <= '1'; seq_byte <= line1_buf(23 downto 16);
      when 19 => seq_rs <= '1'; seq_byte <= line1_buf(15 downto 8);
      when 20 => seq_rs <= '1'; seq_byte <= line1_buf(7 downto 0);
      -- Set DD RAM addr line 2
      when 21 => seq_rs <= '0'; seq_byte <= x"C0";
      -- Line 2 chars (idx 22..37)
      when 22 => seq_rs <= '1'; seq_byte <= line2_buf(127 downto 120);
      when 23 => seq_rs <= '1'; seq_byte <= line2_buf(119 downto 112);
      when 24 => seq_rs <= '1'; seq_byte <= line2_buf(111 downto 104);
      when 25 => seq_rs <= '1'; seq_byte <= line2_buf(103 downto 96);
      when 26 => seq_rs <= '1'; seq_byte <= line2_buf(95 downto 88);
      when 27 => seq_rs <= '1'; seq_byte <= line2_buf(87 downto 80);
      when 28 => seq_rs <= '1'; seq_byte <= line2_buf(79 downto 72);
      when 29 => seq_rs <= '1'; seq_byte <= line2_buf(71 downto 64);
      when 30 => seq_rs <= '1'; seq_byte <= line2_buf(63 downto 56);
      when 31 => seq_rs <= '1'; seq_byte <= line2_buf(55 downto 48);
      when 32 => seq_rs <= '1'; seq_byte <= line2_buf(47 downto 40);
      when 33 => seq_rs <= '1'; seq_byte <= line2_buf(39 downto 32);
      when 34 => seq_rs <= '1'; seq_byte <= line2_buf(31 downto 24);
      when 35 => seq_rs <= '1'; seq_byte <= line2_buf(23 downto 16);
      when 36 => seq_rs <= '1'; seq_byte <= line2_buf(15 downto 8);
      when 37 => seq_rs <= '1'; seq_byte <= line2_buf(7 downto 0);
      -- Padding (shouldn't reach here)
      when others => seq_rs <= '0'; seq_byte <= x"00";
    end case;
  end process;

  process(clk)
  begin
    if rising_edge(clk) then
      if rst = '1' then
        state    <= S_POWERON;
        wait_cnt <= 0;
        seq_idx  <= 0;
        lcd_e    <= '0';
        lcd_rs   <= '0';
        lcd_db   <= "0000";
        pending  <= '0';
      else
        if update = '1' then
          line1_buf <= line1;
          line2_buf <= line2;
          pending   <= '1';
        end if;

        case state is
          when S_POWERON =>
            lcd_e <= '0';
            if wait_cnt = C_15MS then
              wait_cnt <= 0; state <= S_INIT0;
            else
              wait_cnt <= wait_cnt + 1;
            end if;

          -- Three writes of 0x3, then 0x2 (raw nibbles, no lower nibble)
          when S_INIT0 =>
            lcd_db <= "0011"; lcd_rs <= '0'; lcd_e <= '0';
            if wait_cnt = 0 then
              lcd_e <= '1';
            elsif wait_cnt = C_ENABLE then
              lcd_e <= '0';
            elsif wait_cnt = C_ENABLE + C_4_1MS then
              wait_cnt <= 0; state <= S_INIT1;
            end if;
            if wait_cnt < C_ENABLE + C_4_1MS then
              wait_cnt <= wait_cnt + 1;
            end if;

          when S_INIT1 =>
            lcd_db <= "0011"; lcd_rs <= '0'; lcd_e <= '0';
            if wait_cnt = 0 then
              lcd_e <= '1';
            elsif wait_cnt = C_ENABLE then
              lcd_e <= '0';
            elsif wait_cnt = C_ENABLE + C_100US then
              wait_cnt <= 0; state <= S_INIT2;
            end if;
            if wait_cnt < C_ENABLE + C_100US then
              wait_cnt <= wait_cnt + 1;
            end if;

          when S_INIT2 =>
            lcd_db <= "0011"; lcd_rs <= '0'; lcd_e <= '0';
            if wait_cnt = 0 then
              lcd_e <= '1';
            elsif wait_cnt = C_ENABLE then
              lcd_e <= '0';
            elsif wait_cnt = C_ENABLE + C_40US then
              wait_cnt <= 0; state <= S_INIT3;
            end if;
            if wait_cnt < C_ENABLE + C_40US then
              wait_cnt <= wait_cnt + 1;
            end if;

          when S_INIT3 =>
            lcd_db <= "0010"; lcd_rs <= '0'; lcd_e <= '0';
            if wait_cnt = 0 then
              lcd_e <= '1';
            elsif wait_cnt = C_ENABLE then
              lcd_e <= '0';
            elsif wait_cnt = C_ENABLE + C_40US then
              wait_cnt <= 0;
              seq_idx <= 0;
              state <= S_NIBBLE_HI;
            end if;
            if wait_cnt < C_ENABLE + C_40US then
              wait_cnt <= wait_cnt + 1;
            end if;

          -- Idle: wait for pending refresh
          when S_IDLE =>
            lcd_e <= '0';
            if pending = '1' then
              pending <= '0';
              seq_idx <= 4;  -- skip init commands, start at set addr
              state <= S_NIBBLE_HI;
            end if;

          -- Write upper nibble setup
          when S_NIBBLE_HI =>
            lcd_rs <= seq_rs;
            lcd_db <= seq_byte(7 downto 4);
            lcd_e  <= '0';
            wait_cnt <= 0;
            state <= S_NIBBLE_HI_E;

          -- Pulse E for upper nibble
          when S_NIBBLE_HI_E =>
            lcd_e <= '1';
            if wait_cnt = C_ENABLE then
              lcd_e <= '0';
              wait_cnt <= 0;
              state <= S_GAP;
            else
              wait_cnt <= wait_cnt + 1;
            end if;

          -- 1 us gap between nibbles
          when S_GAP =>
            if wait_cnt = C_1US then
              wait_cnt <= 0;
              state <= S_NIBBLE_LO;
            else
              wait_cnt <= wait_cnt + 1;
            end if;

          -- Write lower nibble setup
          when S_NIBBLE_LO =>
            lcd_db <= seq_byte(3 downto 0);
            lcd_e  <= '0';
            wait_cnt <= 0;
            state <= S_NIBBLE_LO_E;

          -- Pulse E for lower nibble
          when S_NIBBLE_LO_E =>
            lcd_e <= '1';
            if wait_cnt = C_ENABLE then
              lcd_e <= '0';
              wait_cnt <= 0;
              -- Set wait time based on command
              if seq_idx = 3 then
                wait_target <= C_1_64MS;  -- Clear display
              else
                wait_target <= C_40US;
              end if;
              state <= S_WAIT;
            else
              wait_cnt <= wait_cnt + 1;
            end if;

          -- Wait for command execution
          when S_WAIT =>
            if wait_cnt = wait_target then
              wait_cnt <= 0;
              state <= S_NEXT;
            else
              wait_cnt <= wait_cnt + 1;
            end if;

          -- Advance to next in sequence
          when S_NEXT =>
            if seq_idx = 37 then
              -- Done with full refresh
              state <= S_IDLE;
            elsif seq_idx = 3 then
              -- After clear, continue init → set addr line1
              seq_idx <= 4;
              state <= S_NIBBLE_HI;
            else
              seq_idx <= seq_idx + 1;
              state <= S_NIBBLE_HI;
            end if;

        end case;
      end if;
    end if;
  end process;

  busy <= '0' when state = S_IDLE else '1';

end architecture rtl;
