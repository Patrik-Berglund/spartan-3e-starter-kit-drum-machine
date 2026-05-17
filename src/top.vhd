library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity top is
  port (
    clk_50mhz   : in  std_logic;
    btn_south    : in  std_logic;
    ps2_clk      : in  std_logic;
    ps2_data     : in  std_logic;
    vga_red      : out std_logic;
    vga_green    : out std_logic;
    vga_blue     : out std_logic;
    vga_hsync    : out std_logic;
    vga_vsync    : out std_logic;
    led          : out std_logic_vector(7 downto 0);
    spi_sck      : out std_logic;
    spi_mosi     : out std_logic;
    spi_miso     : in  std_logic;
    dac_cs       : out std_logic;
    dac_clr      : out std_logic;
    spi_ss_b     : out std_logic;
    amp_cs       : out std_logic;
    ad_conv      : out std_logic;
    sf_ce0       : out std_logic;
    fpga_init_b  : out std_logic;
    rot_a        : in  std_logic;
    rot_b        : in  std_logic;
    rot_center   : in  std_logic;
    lcd_e        : out std_logic;
    lcd_rs       : out std_logic;
    lcd_rw       : out std_logic;
    lcd_db       : out std_logic_vector(3 downto 0)
  );
end entity top;

architecture rtl of top is
  signal rst : std_logic;

  -- Timing
  signal sample_tick, step_advance : std_logic;
  signal bpm : unsigned(7 downto 0) := to_unsigned(120, 8);
  signal playing : std_logic;
  signal current_step : unsigned(3 downto 0);

  -- Sequencer
  signal play_stop, play_stop_kbd, toggle_step, clear_track : std_logic;
  signal edit_track : unsigned(3 downto 0);
  signal edit_step  : unsigned(3 downto 0);
  signal tempo_up, tempo_down : std_logic;
  signal trig_out : std_logic_vector(11 downto 0);
  signal accent_flag : std_logic;
  signal pattern_flat : std_logic_vector(191 downto 0);

  -- Audio voices (12-bit signed)
  signal audio_bd, audio_sd, audio_lt, audio_mt, audio_ht : signed(11 downto 0);
  signal audio_rs, audio_cp, audio_cb, audio_cy, audio_oh, audio_ch : signed(11 downto 0);
  signal mix_out : unsigned(11 downto 0);

  -- PS/2
  signal key_valid : std_logic;
  signal key_code  : std_logic_vector(7 downto 0);
  signal key_break, key_ext : std_logic;

  -- VGA
  signal pixel_x : unsigned(9 downto 0);
  signal pixel_y : unsigned(9 downto 0);
  signal vga_active, frame_tick : std_logic;
  signal font_char_code : unsigned(6 downto 0);
  signal font_row_sel   : unsigned(2 downto 0);
  signal font_data      : std_logic_vector(7 downto 0);

  -- Rotary
  signal rot_event, rot_dir, rot_press : std_logic;

  -- LCD
  signal lcd_line1, lcd_line2 : std_logic_vector(127 downto 0);
  signal lcd_update, lcd_busy : std_logic;
  signal lcd_cnt : unsigned(19 downto 0) := (others => '0');
begin
  rst <= btn_south;
  led(3 downto 0) <= std_logic_vector(current_step);
  led(7) <= playing;
  led(6 downto 4) <= std_logic_vector(edit_track(2 downto 0));

  -- Tempo clock
  u_tempo : entity work.tempo_clock
    port map (clk => clk_50mhz, rst => rst, bpm => bpm,
              playing => playing, sample_tick => sample_tick, step_advance => step_advance);

  -- Sequencer
  u_seq : entity work.sequencer
    port map (clk => clk_50mhz, rst => rst, play_stop => play_stop,
              step_advance => step_advance, edit_track => edit_track,
              edit_step => edit_step, toggle_step => toggle_step,
              clear_track => clear_track, playing => playing,
              current_step => current_step, trig_out => trig_out,
              accent => accent_flag, pattern_flat => pattern_flat);

  -- Drum voices: trig_out(0)=AC, (1)=BD, (2)=SD, (3)=LT, (4)=MT, (5)=HT
  --              (6)=RS, (7)=CP, (8)=CB, (9)=CY, (10)=OH, (11)=CH
  u_bd : entity work.kick_drum
    port map (clk => clk_50mhz, rst => rst, sample_tick => sample_tick,
              trigger => trig_out(1), audio_out => audio_bd);

  u_sd : entity work.snare_drum
    port map (clk => clk_50mhz, rst => rst, sample_tick => sample_tick,
              trigger => trig_out(2), audio_out => audio_sd);

  u_lt : entity work.tom
    generic map (G_FREQ => to_unsigned(221, 16))  -- 165Hz
    port map (clk => clk_50mhz, rst => rst, sample_tick => sample_tick,
              trigger => trig_out(3), audio_out => audio_lt);

  u_mt : entity work.tom
    generic map (G_FREQ => to_unsigned(181, 16))  -- 135Hz
    port map (clk => clk_50mhz, rst => rst, sample_tick => sample_tick,
              trigger => trig_out(4), audio_out => audio_mt);

  u_ht : entity work.tom
    generic map (G_FREQ => to_unsigned(295, 16))  -- 220Hz
    port map (clk => clk_50mhz, rst => rst, sample_tick => sample_tick,
              trigger => trig_out(5), audio_out => audio_ht);

  u_rs : entity work.rimshot
    port map (clk => clk_50mhz, rst => rst, sample_tick => sample_tick,
              trigger => trig_out(6), audio_out => audio_rs);

  u_cp : entity work.clap
    port map (clk => clk_50mhz, rst => rst, sample_tick => sample_tick,
              trigger => trig_out(7), audio_out => audio_cp);

  u_cb : entity work.cowbell
    port map (clk => clk_50mhz, rst => rst, sample_tick => sample_tick,
              trigger => trig_out(8), audio_out => audio_cb);

  u_cy : entity work.cymbal
    port map (clk => clk_50mhz, rst => rst, sample_tick => sample_tick,
              trigger => trig_out(9), audio_out => audio_cy);

  u_oh : entity work.open_hihat
    port map (clk => clk_50mhz, rst => rst, sample_tick => sample_tick,
              trigger => trig_out(10), audio_out => audio_oh);

  u_ch : entity work.hihat
    port map (clk => clk_50mhz, rst => rst, sample_tick => sample_tick,
              trigger => trig_out(11), audio_out => audio_ch);

  -- Mixer
  u_mixer : entity work.mixer
    port map (clk => clk_50mhz, rst => rst, sample_tick => sample_tick,
              in_bd => audio_bd, in_sd => audio_sd, in_lt => audio_lt,
              in_mt => audio_mt, in_ht => audio_ht, in_rs => audio_rs,
              in_cp => audio_cp, in_cb => audio_cb, in_cy => audio_cy,
              in_oh => audio_oh, in_ch => audio_ch, mix_out => mix_out);

  -- DAC
  u_dac : entity work.dac_driver
    port map (clk => clk_50mhz, rst => rst, sample_tick => sample_tick,
              sample_in => mix_out, spi_sck => spi_sck, spi_mosi => spi_mosi,
              spi_miso => spi_miso, dac_cs => dac_cs, dac_clr => dac_clr,
              spi_ss_b => spi_ss_b, amp_cs => amp_cs, ad_conv => ad_conv,
              sf_ce0 => sf_ce0, fpga_init_b => fpga_init_b);

  -- PS/2 + Keyboard
  u_ps2 : entity work.ps2_rx
    port map (clk => clk_50mhz, rst => rst, ps2_clk => ps2_clk, ps2_data => ps2_data,
              key_valid => key_valid, key_code => key_code,
              key_break => key_break, key_ext => key_ext);

  u_kbd : entity work.keyboard_ctrl
    port map (clk => clk_50mhz, rst => rst, key_valid => key_valid,
              key_code => key_code, key_break => key_break, key_ext => key_ext,
              play_stop => play_stop_kbd, edit_track => edit_track, edit_step => edit_step,
              toggle_step => toggle_step, clear_track => clear_track,
              tempo_up => tempo_up, tempo_down => tempo_down);

  -- VGA timing
  u_vga_timing : entity work.vga_timing
    port map (clk => clk_50mhz, rst => rst, hsync => vga_hsync, vsync => vga_vsync,
              active => vga_active, pixel_x => pixel_x, pixel_y => pixel_y,
              frame_tick => frame_tick);

  -- Font ROM
  u_font : entity work.font_rom
    port map (char_code => font_char_code, row => font_row_sel, data => font_data);

  -- Pixel renderer
  u_render : entity work.pixel_renderer
    port map (pixel_x => pixel_x, pixel_y => pixel_y, active => vga_active,
              playing => playing, current_step => current_step,
              edit_track => edit_track, edit_step => edit_step, bpm => bpm,
              pattern => pattern_flat, font_char => font_char_code,
              font_row => font_row_sel, font_data => font_data,
              vga_red => vga_red, vga_green => vga_green, vga_blue => vga_blue);

  -- Rotary encoder
  u_rotary : entity work.rotary_decoder
    port map (clk => clk_50mhz, rst => rst, rot_a => rot_a, rot_b => rot_b,
              rot_center => rot_center, rot_event => rot_event,
              rot_dir => rot_dir, rot_press => rot_press);

  -- Tempo control + rotary play/stop
  process(clk_50mhz)
  begin
    if rising_edge(clk_50mhz) then
      if rst = '1' then
        bpm <= to_unsigned(120, 8);
      else
        if tempo_up = '1' and bpm < 240 then bpm <= bpm + 1;
        elsif tempo_down = '1' and bpm > 40 then bpm <= bpm - 1;
        end if;
        if rot_event = '1' then
          if rot_dir = '1' and bpm < 240 then bpm <= bpm + 1;
          elsif rot_dir = '0' and bpm > 40 then bpm <= bpm - 1;
          end if;
        end if;
      end if;
    end if;
  end process;

  -- Rotary press = play/stop (directly pulse the sequencer)
  play_stop <= rot_press or play_stop_kbd;

  -- LCD
  u_lcd : entity work.lcd_controller
    port map (clk => clk_50mhz, rst => rst, line1 => lcd_line1, line2 => lcd_line2,
              update => lcd_update, busy => lcd_busy,
              lcd_e => lcd_e, lcd_rs => lcd_rs, lcd_rw => lcd_rw, lcd_db => lcd_db);

  process(clk_50mhz)
    variable b : unsigned(7 downto 0);
    variable h, t, u : unsigned(7 downto 0);
  begin
    if rising_edge(clk_50mhz) then
      lcd_update <= '0';
      lcd_cnt <= lcd_cnt + 1;
      if lcd_cnt = 0 and lcd_busy = '0' then lcd_update <= '1'; end if;

      b := bpm;
      if b >= 200 then h := to_unsigned(2,8); b := b - 200;
      elsif b >= 100 then h := to_unsigned(1,8); b := b - 100;
      else h := to_unsigned(0,8); end if;
      if    b >= 90 then t := to_unsigned(9,8); b := b - 90;
      elsif b >= 80 then t := to_unsigned(8,8); b := b - 80;
      elsif b >= 70 then t := to_unsigned(7,8); b := b - 70;
      elsif b >= 60 then t := to_unsigned(6,8); b := b - 60;
      elsif b >= 50 then t := to_unsigned(5,8); b := b - 50;
      elsif b >= 40 then t := to_unsigned(4,8); b := b - 40;
      elsif b >= 30 then t := to_unsigned(3,8); b := b - 30;
      elsif b >= 20 then t := to_unsigned(2,8); b := b - 20;
      elsif b >= 10 then t := to_unsigned(1,8); b := b - 10;
      else t := to_unsigned(0,8); end if;
      u := b;

      lcd_line1 <= x"54" & x"52" & x"2D" & x"38" & x"30" & x"38" & x"20" & x"20" &
                   std_logic_vector(to_unsigned(48+to_integer(h),8)) &
                   std_logic_vector(to_unsigned(48+to_integer(t),8)) &
                   std_logic_vector(to_unsigned(48+to_integer(u),8)) &
                   x"20" & x"42" & x"50" & x"4D" & x"20";
      if playing = '1' then
        lcd_line2 <= x"3E" & x"50" & x"4C" & x"41" & x"59" & x"20" &
                     x"20" & x"20" & x"20" & x"20" & x"20" & x"20" &
                     x"20" & x"20" & x"20" & x"20";
      else
        lcd_line2 <= x"5B" & x"53" & x"54" & x"4F" & x"50" & x"5D" &
                     x"20" & x"20" & x"20" & x"20" & x"20" & x"20" &
                     x"20" & x"20" & x"20" & x"20";
      end if;
    end if;
  end process;

end architecture rtl;
