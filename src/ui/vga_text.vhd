library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

-- VGA text-mode controller: 80x60 character grid (8x8 font, 640x480)
-- Dual-port: write side for logic, read side for scanout
-- Each cell: 7-bit char code + 6-bit color (3-bit fg, 3-bit bg)

entity vga_text is
  port (
    clk       : in  std_logic;  -- 50 MHz
    rst       : in  std_logic;
    -- Write port (from sequencer/UI logic)
    wr_en     : in  std_logic;
    wr_addr   : in  unsigned(12 downto 0);  -- 0..4799 (80*60)
    wr_char   : in  unsigned(6 downto 0);   -- ASCII 32-95
    wr_fg     : in  std_logic_vector(2 downto 0);
    wr_bg     : in  std_logic_vector(2 downto 0);
    -- VGA output
    vga_red   : out std_logic;
    vga_green : out std_logic;
    vga_blue  : out std_logic;
    vga_hsync : out std_logic;
    vga_vsync : out std_logic;
    frame_tick: out std_logic
  );
end entity vga_text;

architecture rtl of vga_text is
  -- Tile RAM: 80*60 = 4800 cells, 13 bits per cell (7 char + 3 fg + 3 bg)
  type tile_ram_t is array (0 to 4799) of std_logic_vector(12 downto 0);
  signal tile_ram : tile_ram_t := (others => "0111" & "000" & "000000");
  -- Default: space (32=0x20, code 0), white on black

  -- VGA timing signals
  signal pixel_x   : unsigned(9 downto 0);
  signal pixel_y   : unsigned(9 downto 0);
  signal active    : std_logic;
  signal hsync_i   : std_logic;
  signal vsync_i   : std_logic;
  signal ftick     : std_logic;

  -- Tile lookup
  signal char_col  : unsigned(6 downto 0);  -- 0-79
  signal char_row  : unsigned(5 downto 0);  -- 0-59
  signal sub_x     : unsigned(2 downto 0);
  signal sub_y     : unsigned(2 downto 0);
  signal tile_addr : unsigned(12 downto 0);
  signal tile_data : std_logic_vector(12 downto 0);

  -- Font lookup
  signal font_char : unsigned(6 downto 0);
  signal font_row  : unsigned(2 downto 0);
  signal font_data : std_logic_vector(7 downto 0);

  -- Pipeline registers (1 clock delay for BRAM read)
  signal sub_x_d   : unsigned(2 downto 0);
  signal fg_d      : std_logic_vector(2 downto 0);
  signal bg_d      : std_logic_vector(2 downto 0);
  signal active_d  : std_logic;
  signal hsync_d   : std_logic;
  signal vsync_d   : std_logic;

  signal pixel_bit : std_logic;
  signal rgb       : std_logic_vector(2 downto 0);

begin

  -- VGA timing generator
  u_timing : entity work.vga_timing
    port map (
      clk       => clk,
      rst       => rst,
      hsync     => hsync_i,
      vsync     => vsync_i,
      active    => active,
      pixel_x   => pixel_x,
      pixel_y   => pixel_y,
      frame_tick => ftick
    );

  frame_tick <= ftick;

  -- Character cell position
  char_col <= pixel_x(9 downto 3);
  char_row <= pixel_y(8 downto 3);
  sub_x    <= pixel_x(2 downto 0);
  sub_y    <= pixel_y(2 downto 0);

  -- Tile address = char_row * 80 + char_col
  -- 80 = 64 + 16, so row*80 = row*64 + row*16
  tile_addr <= resize(char_row & "000000", 13) + resize(char_row & "0000", 13) + resize(char_col, 13);

  -- Tile RAM: dual-port (write + read)
  process(clk)
  begin
    if rising_edge(clk) then
      -- Write port
      if wr_en = '1' then
        tile_ram(to_integer(wr_addr)) <= std_logic_vector(wr_char) & wr_fg & wr_bg;
      end if;
      -- Read port (for scanout)
      tile_data <= tile_ram(to_integer(tile_addr));
    end if;
  end process;

  -- Extract char code and colors from tile data (1 clock after address)
  font_char <= unsigned(tile_data(12 downto 6));
  font_row  <= sub_y;

  -- Pipeline delay to match BRAM read latency
  process(clk)
  begin
    if rising_edge(clk) then
      sub_x_d  <= sub_x;
      fg_d     <= tile_data(5 downto 3);
      bg_d     <= tile_data(2 downto 0);
      active_d <= active;
      hsync_d  <= hsync_i;
      vsync_d  <= vsync_i;
    end if;
  end process;

  -- Font ROM
  u_font : entity work.font_rom
    port map (
      char_code => font_char,
      row       => font_row,
      data      => font_data
    );

  -- Select pixel bit (MSB = leftmost)
  pixel_bit <= font_data(7 - to_integer(sub_x_d));

  -- Color mux: foreground if pixel set, background otherwise
  rgb <= fg_d when pixel_bit = '1' else bg_d;

  -- Output
  vga_red   <= rgb(2) when active_d = '1' else '0';
  vga_green <= rgb(1) when active_d = '1' else '0';
  vga_blue  <= rgb(0) when active_d = '1' else '0';
  vga_hsync <= hsync_d;
  vga_vsync <= vsync_d;

end architecture rtl;
