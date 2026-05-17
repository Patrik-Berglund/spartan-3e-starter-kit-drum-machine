library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

-- Pixel-based TR-808 panel renderer.
-- 640x480, 1-bit RGB (8 colors).
-- Layout:
--   Row 0-30:   Title bar "Rhythm Composer TR-808" + BPM
--   Row 32-46:  Step numbers 1-16
--   Row 48-479: 12 instrument rows (36px each), each with:
--               - Label area (cols 0-55)
--               - 16 step pads (cols 60-635, each 34px wide, 2px gap)

entity pixel_renderer is
  port (
    pixel_x      : in  unsigned(9 downto 0);
    pixel_y      : in  unsigned(9 downto 0);
    active       : in  std_logic;
    -- Sequencer state
    playing      : in  std_logic;
    current_step : in  unsigned(3 downto 0);
    edit_track   : in  unsigned(3 downto 0);  -- 0-11
    edit_step    : in  unsigned(3 downto 0);  -- 0-15
    bpm          : in  unsigned(7 downto 0);
    -- Pattern data: 12 tracks x 16 steps, active-high
    pattern      : in  std_logic_vector(191 downto 0); -- 12*16 bits
    -- Font ROM interface
    font_char    : out unsigned(6 downto 0);
    font_row     : out unsigned(2 downto 0);
    font_data    : in  std_logic_vector(7 downto 0);
    -- VGA output
    vga_red      : out std_logic;
    vga_green    : out std_logic;
    vga_blue     : out std_logic
  );
end entity pixel_renderer;

architecture rtl of pixel_renderer is
  -- Layout constants
  constant LABEL_W     : integer := 56;
  constant PAD_START_X : integer := 64;
  constant PAD_W       : integer := 30;
  constant PAD_PITCH   : integer := 32; -- power of 2 for division
  constant PAD_MARGIN_Y: integer := 2;
  constant PAD_INNER_H : integer := 28; -- ROW_H - 2*margin
  constant ROW_H       : integer := 32; -- power of 2 for division

  -- Track colors (fg for label, pad active color)
  -- 0=AC(red), 1=BD(red), 2=SD(red), 3=LT(yellow), 4=MT(yellow), 5=HT(yellow)
  -- 6=RS(white), 7=CP(white), 8=CB(white), 9=CY(cyan), 10=OH(cyan), 11=CH(cyan)
  type color_array is array(0 to 11) of std_logic_vector(2 downto 0);
  constant TRACK_COLOR : color_array := (
    "100", "100", "100",  -- AC, BD, SD = red
    "110", "110", "110",  -- LT, MT, HT = yellow
    "111", "111", "111",  -- RS, CP, CB = white
    "011", "011", "011"   -- CY, OH, CH = cyan
  );

  -- Track label characters (3 chars each, ASCII)
  type label_char_t is array(0 to 2) of integer range 0 to 127;
  type label_array_t is array(0 to 11) of label_char_t;
  constant TRACK_LABEL : label_array_t := (
    (65, 67, 32),   -- "AC "
    (66, 68, 32),   -- "BD "
    (83, 68, 32),   -- "SD "
    (76, 84, 32),   -- "LT "
    (77, 84, 32),   -- "MT "
    (72, 84, 32),   -- "HT "
    (82, 83, 32),   -- "RS "
    (67, 80, 32),   -- "CP "
    (67, 66, 32),   -- "CB "
    (67, 89, 32),   -- "CY "
    (79, 72, 32),   -- "OH "
    (67, 72, 32)    -- "CH "
  );

  -- Title string "TR-808" (6 chars)
  type title_t is array(0 to 5) of integer range 0 to 127;
  constant TITLE_STR : title_t := (84, 82, 45, 56, 48, 56);

  -- Signals for pixel decode
  signal px : integer range 0 to 639;
  signal py : integer range 0 to 479;
  signal rgb : std_logic_vector(2 downto 0);

  -- Font lookup
  signal font_char_s : unsigned(6 downto 0);
  signal font_row_s  : unsigned(2 downto 0);
  signal font_col_s  : unsigned(2 downto 0);
  signal font_pixel  : std_logic;

begin
  px <= to_integer(pixel_x);
  py <= to_integer(pixel_y);

  -- Font ROM drive
  font_char <= font_char_s;
  font_row  <= font_row_s;
  font_pixel <= font_data(7 - to_integer(font_col_s));

  -- Main pixel logic
  process(px, py, active, playing, current_step, edit_track, edit_step,
          bpm, pattern, font_pixel)
    variable track_idx : integer range 0 to 11;
    variable step_idx  : integer range 0 to 15;
    variable row_y     : integer;
    variable in_pad    : boolean;
    variable pad_active: std_logic;
    variable is_playhead : boolean;
    variable is_cursor : boolean;
    variable local_x, local_y : integer;
    variable char_idx  : integer;
    variable bpm_h, bpm_t, bpm_u : integer;
    variable bpm_v : integer;
  begin
    rgb <= "000";
    font_char_s <= to_unsigned(32, 7);
    font_row_s <= (others => '0');
    font_col_s <= (others => '0');

    if active = '0' then
      rgb <= "000";

    -- Title bar (y 16-31)
    elsif py >= 16 and py < 32 then
      -- "TR-808" at x=8, y=20, 8x8 font
      if py >= 20 and py < 28 and px >= 8 and px < 56 then
        char_idx := (px - 8) / 8;
        font_char_s <= to_unsigned(TITLE_STR(char_idx), 7);
        font_row_s <= to_unsigned(py - 20, 3);
        font_col_s <= to_unsigned((px - 8) mod 8, 3);
        if font_pixel = '1' then rgb <= "110"; end if;
      -- BPM at x=540
      elsif py >= 20 and py < 28 and px >= 540 and px < 564 then
        bpm_v := to_integer(bpm);
        if bpm_v >= 200 then bpm_h := 2; bpm_v := bpm_v - 200;
        elsif bpm_v >= 100 then bpm_h := 1; bpm_v := bpm_v - 100;
        else bpm_h := 0; end if;
        if    bpm_v >= 90 then bpm_t := 9; bpm_v := bpm_v - 90;
        elsif bpm_v >= 80 then bpm_t := 8; bpm_v := bpm_v - 80;
        elsif bpm_v >= 70 then bpm_t := 7; bpm_v := bpm_v - 70;
        elsif bpm_v >= 60 then bpm_t := 6; bpm_v := bpm_v - 60;
        elsif bpm_v >= 50 then bpm_t := 5; bpm_v := bpm_v - 50;
        elsif bpm_v >= 40 then bpm_t := 4; bpm_v := bpm_v - 40;
        elsif bpm_v >= 30 then bpm_t := 3; bpm_v := bpm_v - 30;
        elsif bpm_v >= 20 then bpm_t := 2; bpm_v := bpm_v - 20;
        elsif bpm_v >= 10 then bpm_t := 1; bpm_v := bpm_v - 10;
        else bpm_t := 0; end if;
        bpm_u := bpm_v;
        char_idx := (px - 540) / 8;
        if char_idx = 0 then font_char_s <= to_unsigned(48 + bpm_h, 7);
        elsif char_idx = 1 then font_char_s <= to_unsigned(48 + bpm_t, 7);
        elsif char_idx = 2 then font_char_s <= to_unsigned(48 + bpm_u, 7);
        end if;
        font_row_s <= to_unsigned(py - 20, 3);
        font_col_s <= to_unsigned((px - 540) mod 8, 3);
        if font_pixel = '1' then rgb <= "111"; end if;
      -- Play indicator
      elsif py >= 20 and py < 28 and px >= 580 and px < 588 then
        if playing = '1' then font_char_s <= to_unsigned(62, 7);
        else font_char_s <= to_unsigned(61, 7); end if;
        font_row_s <= to_unsigned(py - 20, 3);
        font_col_s <= to_unsigned((px - 580) mod 8, 3);
        if font_pixel = '1' then
          if playing = '1' then rgb <= "010"; else rgb <= "100"; end if;
        end if;
      end if;

    -- Step number row (y 34-41)
    elsif py >= 34 and py < 42 then
      if px >= PAD_START_X then
        step_idx := (px - PAD_START_X) / PAD_PITCH;
        local_x := (px - PAD_START_X) - step_idx * PAD_PITCH;
        if step_idx < 16 and local_x < PAD_W then
          local_y := py - 34;
          if step_idx < 9 then
            if local_x >= 13 and local_x < 21 then
              font_char_s <= to_unsigned(49 + step_idx, 7);
              font_row_s <= to_unsigned(local_y, 3);
              font_col_s <= to_unsigned(local_x - 13, 3);
              if font_pixel = '1' then rgb <= "011"; end if;
            end if;
          else
            if local_x >= 9 and local_x < 17 then
              font_char_s <= to_unsigned(49, 7);
              font_row_s <= to_unsigned(local_y, 3);
              font_col_s <= to_unsigned(local_x - 9, 3);
              if font_pixel = '1' then rgb <= "011"; end if;
            elsif local_x >= 17 and local_x < 25 then
              font_char_s <= to_unsigned(48 + step_idx + 1 - 10, 7);
              font_row_s <= to_unsigned(local_y, 3);
              font_col_s <= to_unsigned(local_x - 17, 3);
              if font_pixel = '1' then rgb <= "011"; end if;
            end if;
          end if;
        end if;
      end if;

    -- Grid area (y 44+): 12 rows, 32px each
    elsif py >= 44 then
      row_y := py - 44;
      track_idx := row_y / ROW_H;

      if track_idx < 12 then
        local_y := row_y - track_idx * ROW_H;

        -- Label (x 0-55)
        if px < LABEL_W then
          if local_y >= 14 and local_y < 22 and px >= 8 and px < 32 then
            char_idx := (px - 8) / 8;
            if char_idx < 3 then
              font_char_s <= to_unsigned(TRACK_LABEL(track_idx)(char_idx), 7);
              font_row_s <= to_unsigned(local_y - 14, 3);
              font_col_s <= to_unsigned((px - 8) mod 8, 3);
              if font_pixel = '1' then
                if to_unsigned(track_idx, 4) = edit_track then
                  rgb <= "111";
                else
                  rgb <= TRACK_COLOR(track_idx);
                end if;
              end if;
            end if;
          end if;

        -- Pads (x 60+)
        elsif px >= PAD_START_X then
          step_idx := (px - PAD_START_X) / PAD_PITCH;
          local_x := (px - PAD_START_X) - step_idx * PAD_PITCH;

          if step_idx < 16 and local_x < PAD_W and
             local_y >= PAD_MARGIN_Y and local_y < PAD_MARGIN_Y + PAD_INNER_H then

            pad_active := pattern(track_idx * 16 + step_idx);
            is_playhead := (playing = '1') and (to_unsigned(step_idx, 4) = current_step);
            is_cursor := (to_unsigned(track_idx, 4) = edit_track) and
                         (to_unsigned(step_idx, 4) = edit_step);

            if is_playhead and pad_active = '1' then
              rgb <= "111";
            elsif is_playhead then
              rgb <= "010";
            elsif is_cursor then
              if local_x < 2 or local_x >= PAD_W - 2 or
                 (local_y - PAD_MARGIN_Y) < 2 or (local_y - PAD_MARGIN_Y) >= PAD_INNER_H - 2 then
                rgb <= "110";
              elsif pad_active = '1' then
                rgb <= TRACK_COLOR(track_idx);
              else
                rgb <= "001";
              end if;
            elsif pad_active = '1' then
              rgb <= TRACK_COLOR(track_idx);
            else
              rgb <= "001";
            end if;
          end if;
        end if;
      end if;
    end if;
  end process;

  vga_red   <= rgb(2) when active = '1' else '0';
  vga_green <= rgb(1) when active = '1' else '0';
  vga_blue  <= rgb(0) when active = '1' else '0';

end architecture rtl;
