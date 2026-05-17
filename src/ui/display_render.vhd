library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

-- Renders the drum machine UI to the VGA text buffer.
-- Layout (80 cols x 30 rows):
--   Row 0: Title + BPM
--   Row 2: Step numbers    "  1  2  3  4  5  6  7  8  9 10 11 12 13 14 15 16"
--   Row 3: KICK pattern
--   Row 4: SNARE pattern
--   Row 5: HIHAT pattern
--   Row 6: CLAP pattern
--   Row 7: BASS pattern
--   Row 9: Playhead indicator
-- Cursor shown with highlight color. Playhead shown with different color.

entity display_render is
  port (
    clk          : in  std_logic;
    rst          : in  std_logic;
    frame_tick   : in  std_logic;  -- ~60 Hz refresh trigger
    -- State to display
    playing      : in  std_logic;
    current_step : in  unsigned(3 downto 0);
    edit_track   : in  unsigned(2 downto 0);
    edit_step    : in  unsigned(3 downto 0);
    bpm          : in  unsigned(7 downto 0);
    -- Pattern data (one track at a time, we cycle through)
    disp_track   : out unsigned(2 downto 0);
    disp_pattern : in  std_logic_vector(15 downto 0);
    -- VGA text write port
    wr_en        : out std_logic;
    wr_addr      : out unsigned(12 downto 0);
    wr_char      : out unsigned(6 downto 0);
    wr_fg        : out std_logic_vector(2 downto 0);
    wr_bg        : out std_logic_vector(2 downto 0)
  );
end entity display_render;

architecture rtl of display_render is
  -- Rendering state machine
  type state_t is (S_IDLE, S_HEADER, S_STEPNUMS, S_TRACKS, S_PLAYHEAD, S_DONE);
  signal state     : state_t := S_IDLE;
  signal char_idx  : unsigned(6 downto 0) := (others => '0');
  signal track_idx : unsigned(2 downto 0) := (others => '0');
  signal step_idx  : unsigned(3 downto 0) := (others => '0');

  -- Track names (4 chars each)
  type name_char_t is array (0 to 3) of unsigned(6 downto 0);
  type name_array_t is array (0 to 4) of name_char_t;
  constant TRACK_NAMES : name_array_t := (
    (to_unsigned(75,7), to_unsigned(73,7), to_unsigned(67,7), to_unsigned(75,7)),   -- KICK
    (to_unsigned(83,7), to_unsigned(78,7), to_unsigned(82,7), to_unsigned(69,7)),   -- SNRE
    (to_unsigned(72,7), to_unsigned(72,7), to_unsigned(65,7), to_unsigned(84,7)),   -- HHAT
    (to_unsigned(67,7), to_unsigned(76,7), to_unsigned(65,7), to_unsigned(80,7)),   -- CLAP
    (to_unsigned(66,7), to_unsigned(65,7), to_unsigned(83,7), to_unsigned(83,7))    -- BASS
  );

  signal patterns_buf : std_logic_vector(15 downto 0) := (others => '0');
  signal sub_state    : unsigned(4 downto 0) := (others => '0');

  -- BPM to ASCII digits
  signal bpm_h, bpm_t, bpm_u : unsigned(6 downto 0);

  function to_digit(v : integer) return unsigned is
  begin
    return to_unsigned(48 + v, 7);
  end function;

begin

  -- BPM digit extraction (hundreds, tens, units) via subtraction
  process(bpm)
    variable b : integer;
    variable h, t : integer;
  begin
    b := to_integer(bpm);
    if b >= 200 then h := 2; b := b - 200;
    elsif b >= 100 then h := 1; b := b - 100;
    else h := 0;
    end if;
    if    b >= 90 then t := 9; b := b - 90;
    elsif b >= 80 then t := 8; b := b - 80;
    elsif b >= 70 then t := 7; b := b - 70;
    elsif b >= 60 then t := 6; b := b - 60;
    elsif b >= 50 then t := 5; b := b - 50;
    elsif b >= 40 then t := 4; b := b - 40;
    elsif b >= 30 then t := 3; b := b - 30;
    elsif b >= 20 then t := 2; b := b - 20;
    elsif b >= 10 then t := 1; b := b - 10;
    else t := 0;
    end if;
    bpm_h <= to_digit(h);
    bpm_t <= to_digit(t);
    bpm_u <= to_digit(b);
  end process;

  process(clk)
    variable row  : unsigned(4 downto 0);
    variable col  : unsigned(6 downto 0);
    variable addr : unsigned(12 downto 0);
  begin
    if rising_edge(clk) then
      wr_en <= '0';

      if rst = '1' then
        state <= S_IDLE;
      else
        case state is
          when S_IDLE =>
            if frame_tick = '1' then
              state    <= S_HEADER;
              sub_state <= (others => '0');
            end if;

          -- Write "DR-808  BPM:120  [PLAY/STOP]"
          when S_HEADER =>
            wr_en <= '1';
            row := to_unsigned(2, 5);
            col := resize(sub_state, 7);
            addr := resize(row, 13) * 80 + resize(col, 13);
            wr_addr <= addr;
            wr_bg <= "000";

            case to_integer(sub_state) is
              when 0  => wr_char <= to_unsigned(68,7); wr_fg <= "110"; -- D (yellow)
              when 1  => wr_char <= to_unsigned(82,7); wr_fg <= "110"; -- R
              when 2  => wr_char <= to_unsigned(45,7); wr_fg <= "110"; -- -
              when 3  => wr_char <= to_unsigned(56,7); wr_fg <= "110"; -- 8
              when 4  => wr_char <= to_unsigned(48,7); wr_fg <= "110"; -- 0
              when 5  => wr_char <= to_unsigned(56,7); wr_fg <= "110"; -- 8
              when 6  => wr_char <= to_unsigned(32,7); wr_fg <= "111"; -- space
              when 7  => wr_char <= to_unsigned(32,7); wr_fg <= "111"; -- space
              when 8  => wr_char <= bpm_h; wr_fg <= "111";
              when 9  => wr_char <= bpm_t; wr_fg <= "111";
              when 10 => wr_char <= bpm_u; wr_fg <= "111";
              when 11 => wr_char <= to_unsigned(66,7); wr_fg <= "111"; -- B
              when 12 => wr_char <= to_unsigned(80,7); wr_fg <= "111"; -- P
              when 13 => wr_char <= to_unsigned(77,7); wr_fg <= "111"; -- M
              when 14 => wr_char <= to_unsigned(32,7); wr_fg <= "111"; -- space
              when 15 =>
                if playing = '1' then
                  wr_char <= to_unsigned(62,7); wr_fg <= "010"; -- > (green)
                else
                  wr_char <= to_unsigned(91,7); wr_fg <= "100"; -- [ (red)
                end if;
              when others => wr_char <= to_unsigned(32,7); wr_fg <= "111";
            end case;

            if sub_state = 15 then
              sub_state <= (others => '0');
              state <= S_STEPNUMS;
              step_idx <= (others => '0');
            else
              sub_state <= sub_state + 1;
            end if;

          -- Write step numbers on row 2: "     1  2  3 ..."
          when S_STEPNUMS =>
            wr_en <= '1';
            row := to_unsigned(4, 5);
            col := to_unsigned(5, 7) + resize(step_idx, 7) * 3;
            addr := resize(row, 13) * 80 + resize(col, 13);
            wr_addr <= addr;
            wr_bg <= "000";
            wr_fg <= "011"; -- cyan

            if step_idx < 9 then
              wr_char <= to_digit(to_integer(step_idx) + 1);
            else
              -- Two-digit: write tens digit, then come back for units
              if sub_state(0) = '0' then
                wr_char <= to_unsigned(49, 7); -- '1'
                sub_state(0) <= '1';
              else
                addr := resize(row, 13) * 80 + resize(col, 13) + 1;
                wr_addr <= addr;
                wr_char <= to_digit(to_integer(step_idx) + 1 - 10);
                sub_state(0) <= '0';
                step_idx <= step_idx + 1;
                if step_idx = 15 then
                  state <= S_TRACKS;
                  track_idx <= (others => '0');
                  step_idx <= (others => '0');
                  sub_state <= (others => '0');
                  disp_track <= (others => '0');
                end if;
              end if;
            end if;

            if step_idx < 9 then
              step_idx <= step_idx + 1;
            end if;

          -- Write track patterns (rows 3-7)
          when S_TRACKS =>
            -- sub_state: 0-3 = name chars, 4 = space, 5-20 = step chars
            wr_en <= '1';
            row := to_unsigned(5, 5) + resize(track_idx, 5);
            wr_bg <= "000";

            if sub_state < 4 then
              -- Track name
              col := resize(sub_state, 7);
              addr := resize(row, 13) * 80 + resize(col, 13);
              wr_addr <= addr;
              wr_char <= TRACK_NAMES(to_integer(track_idx))(to_integer(sub_state(1 downto 0)));
              if track_idx = edit_track then
                wr_fg <= "110"; -- yellow = selected track
              else
                wr_fg <= "011"; -- cyan
              end if;
              sub_state <= sub_state + 1;
            elsif sub_state = 4 then
              -- Request pattern data for this track
              disp_track <= track_idx;
              sub_state <= sub_state + 1;
            elsif sub_state = 5 then
              -- Latch pattern (1 cycle delay for readback)
              patterns_buf <= disp_pattern;
              step_idx <= (others => '0');
              sub_state <= sub_state + 1;
            else
              -- Write step indicators
              col := to_unsigned(5, 7) + resize(step_idx, 7) * 3;
              addr := resize(row, 13) * 80 + resize(col, 13);
              wr_addr <= addr;

              if patterns_buf(to_integer(step_idx)) = '1' then
                wr_char <= to_unsigned(88, 7); -- 'X'
                if step_idx = current_step and playing = '1' then
                  wr_fg <= "111"; wr_bg <= "010"; -- white on green = playing
                elsif step_idx = edit_step and track_idx = edit_track then
                  wr_fg <= "000"; wr_bg <= "110"; -- black on yellow = cursor
                else
                  wr_fg <= "010"; -- green
                end if;
              else
                wr_char <= to_unsigned(46, 7); -- '.'
                if step_idx = current_step and playing = '1' then
                  wr_fg <= "111"; wr_bg <= "001"; -- white on blue = playhead
                elsif step_idx = edit_step and track_idx = edit_track then
                  wr_fg <= "000"; wr_bg <= "110"; -- cursor
                else
                  wr_fg <= "111"; -- white
                  wr_bg <= "000";
                end if;
              end if;

              if step_idx = 15 then
                step_idx <= (others => '0');
                sub_state <= (others => '0');
                if track_idx = 4 then
                  state <= S_PLAYHEAD;
                  sub_state <= (others => '0');
                else
                  track_idx <= track_idx + 1;
                end if;
              else
                step_idx <= step_idx + 1;
              end if;
            end if;

          when S_PLAYHEAD =>
            -- Done rendering this frame
            state <= S_DONE;

          when S_DONE =>
            state <= S_IDLE;

        end case;
      end if;
    end if;
  end process;

end architecture rtl;
