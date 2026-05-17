library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity top is
  port (
    clk_50mhz : in  std_logic;
    btn_south  : in  std_logic;
    ps2_clk    : in  std_logic;
    ps2_data   : in  std_logic;
    vga_red    : out std_logic;
    vga_green  : out std_logic;
    vga_blue   : out std_logic;
    vga_hsync  : out std_logic;
    vga_vsync  : out std_logic;
    led        : out std_logic_vector(7 downto 0)
  );
end entity top;

architecture rtl of top is
  signal rst : std_logic;

  -- VGA text write port
  signal wr_en   : std_logic := '0';
  signal wr_addr : unsigned(12 downto 0) := (others => '0');
  signal wr_char : unsigned(6 downto 0) := (others => '0');
  signal wr_fg   : std_logic_vector(2 downto 0) := "111";
  signal wr_bg   : std_logic_vector(2 downto 0) := "000";

  -- PS/2 keyboard
  signal key_valid : std_logic;
  signal key_code  : std_logic_vector(7 downto 0);
  signal key_break : std_logic;
  signal key_ext   : std_logic;

  -- Display cursor (where next scancode gets written)
  signal cursor    : unsigned(12 downto 0) := (others => '0');
  signal frame_tick: std_logic;

  -- Hex display helper
  function hex_char(v : std_logic_vector(3 downto 0)) return unsigned is
  begin
    if unsigned(v) < 10 then
      return to_unsigned(48, 7) + resize(unsigned(v), 7);  -- '0'-'9'
    else
      return to_unsigned(65, 7) + resize(unsigned(v) - 10, 7);  -- 'A'-'F'
    end if;
  end function;

begin
  rst <= btn_south;
  led <= key_code;

  -- VGA text display
  u_vga : entity work.vga_text
    port map (
      clk       => clk_50mhz,
      rst       => rst,
      wr_en     => wr_en,
      wr_addr   => wr_addr,
      wr_char   => wr_char,
      wr_fg     => wr_fg,
      wr_bg     => wr_bg,
      vga_red   => vga_red,
      vga_green => vga_green,
      vga_blue  => vga_blue,
      vga_hsync => vga_hsync,
      vga_vsync => vga_vsync,
      frame_tick => frame_tick
    );

  -- PS/2 keyboard receiver
  u_ps2 : entity work.ps2_rx
    port map (
      clk       => clk_50mhz,
      rst       => rst,
      ps2_clk   => ps2_clk,
      ps2_data  => ps2_data,
      key_valid => key_valid,
      key_code  => key_code,
      key_break => key_break,
      key_ext   => key_ext
    );

  -- Display scancodes on screen as hex pairs
  process(clk_50mhz)
    variable state : integer range 0 to 3 := 0;
    variable code_save : std_logic_vector(7 downto 0);
    variable brk_save  : std_logic;
  begin
    if rising_edge(clk_50mhz) then
      wr_en <= '0';
      if rst = '1' then
        cursor <= (others => '0');
        state := 0;
      else
        case state is
          when 0 =>
            if key_valid = '1' then
              code_save := key_code;
              brk_save  := key_break;
              -- Write high nibble
              wr_en   <= '1';
              wr_addr <= cursor;
              wr_char <= hex_char(key_code(7 downto 4));
              if key_break = '0' then
                wr_fg <= "010";
              else
                wr_fg <= "100";
              end if;
              wr_bg   <= "000";
              state := 1;
            end if;
          when 1 =>
            -- Write low nibble
            wr_en   <= '1';
            wr_addr <= cursor + 1;
            wr_char <= hex_char(code_save(3 downto 0));
            if brk_save = '0' then
              wr_fg <= "010";
            else
              wr_fg <= "100";
            end if;
            wr_bg   <= "000";
            state := 2;
          when 2 =>
            -- Write space separator
            wr_en   <= '1';
            wr_addr <= cursor + 2;
            wr_char <= to_unsigned(32, 7);
            wr_fg   <= "111";
            wr_bg   <= "000";
            state := 3;
          when 3 =>
            -- Advance cursor
            if cursor + 3 >= 4800 then
              cursor <= (others => '0');
            else
              cursor <= cursor + 3;
            end if;
            state := 0;
          when others =>
            state := 0;
        end case;
      end if;
    end if;
  end process;

end architecture rtl;
