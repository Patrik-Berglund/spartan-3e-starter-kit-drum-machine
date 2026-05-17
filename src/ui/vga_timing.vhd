library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity vga_timing is
  port (
    clk       : in  std_logic;  -- 50 MHz
    rst       : in  std_logic;
    hsync     : out std_logic;
    vsync     : out std_logic;
    active    : out std_logic;
    pixel_x   : out unsigned(9 downto 0);
    pixel_y   : out unsigned(9 downto 0);
    frame_tick : out std_logic  -- one pulse per frame (at vsync start)
  );
end entity vga_timing;

architecture rtl of vga_timing is
  -- 640x480 @ 60 Hz timing
  constant H_ACTIVE : integer := 640;
  constant H_FP     : integer := 16;
  constant H_SYNC   : integer := 96;
  constant H_BP     : integer := 48;
  constant H_TOTAL  : integer := 800;

  constant V_ACTIVE : integer := 480;
  constant V_FP     : integer := 10;
  constant V_SYNC   : integer := 2;
  constant V_BP     : integer := 29;
  constant V_TOTAL  : integer := 521;

  signal pix_en  : std_logic := '0';
  signal h_cnt   : unsigned(9 downto 0) := (others => '0');
  signal v_cnt   : unsigned(9 downto 0) := (others => '0');
begin

  -- 25 MHz pixel enable (toggle at 50 MHz)
  process(clk)
  begin
    if rising_edge(clk) then
      if rst = '1' then
        pix_en <= '0';
      else
        pix_en <= not pix_en;
      end if;
    end if;
  end process;

  -- Counters
  process(clk)
  begin
    if rising_edge(clk) then
      if rst = '1' then
        h_cnt <= (others => '0');
        v_cnt <= (others => '0');
      elsif pix_en = '1' then
        if h_cnt = H_TOTAL - 1 then
          h_cnt <= (others => '0');
          if v_cnt = V_TOTAL - 1 then
            v_cnt <= (others => '0');
          else
            v_cnt <= v_cnt + 1;
          end if;
        else
          h_cnt <= h_cnt + 1;
        end if;
      end if;
    end if;
  end process;

  -- Sync signals (active low for 640x480@60Hz)
  hsync <= '0' when (h_cnt >= H_ACTIVE + H_FP) and (h_cnt < H_ACTIVE + H_FP + H_SYNC) else '1';
  vsync <= '0' when (v_cnt >= V_ACTIVE + V_FP) and (v_cnt < V_ACTIVE + V_FP + V_SYNC) else '1';

  -- Active display area
  active <= '1' when (h_cnt < H_ACTIVE) and (v_cnt < V_ACTIVE) else '0';

  -- Pixel coordinates
  pixel_x <= h_cnt;
  pixel_y <= v_cnt;

  -- Frame tick: one clock pulse at start of vsync
  process(clk)
  begin
    if rising_edge(clk) then
      if rst = '1' then
        frame_tick <= '0';
      elsif pix_en = '1' and h_cnt = 0 and v_cnt = V_ACTIVE + V_FP then
        frame_tick <= '1';
      else
        frame_tick <= '0';
      end if;
    end if;
  end process;

end architecture rtl;
