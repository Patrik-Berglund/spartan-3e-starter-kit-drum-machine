library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity keyboard_ctrl is
  port (
    clk         : in  std_logic;
    rst         : in  std_logic;
    key_valid   : in  std_logic;
    key_code    : in  std_logic_vector(7 downto 0);
    key_break   : in  std_logic;
    key_ext     : in  std_logic;
    -- Outputs
    play_stop   : out std_logic;
    edit_track  : out unsigned(3 downto 0);
    edit_step   : out unsigned(3 downto 0);
    toggle_step : out std_logic;
    clear_track : out std_logic;
    tempo_up    : out std_logic;
    tempo_down  : out std_logic
  );
end entity keyboard_ctrl;

architecture rtl of keyboard_ctrl is
  signal track_reg : unsigned(3 downto 0) := (others => '0');
  signal step_reg  : unsigned(3 downto 0) := (others => '0');

  constant SC_SPACE : std_logic_vector(7 downto 0) := x"29";
  constant SC_1     : std_logic_vector(7 downto 0) := x"16";
  constant SC_2     : std_logic_vector(7 downto 0) := x"1E";
  constant SC_3     : std_logic_vector(7 downto 0) := x"26";
  constant SC_4     : std_logic_vector(7 downto 0) := x"25";
  constant SC_5     : std_logic_vector(7 downto 0) := x"2E";
  constant SC_6     : std_logic_vector(7 downto 0) := x"36";
  constant SC_7     : std_logic_vector(7 downto 0) := x"3D";
  constant SC_8     : std_logic_vector(7 downto 0) := x"3E";
  constant SC_9     : std_logic_vector(7 downto 0) := x"46";
  constant SC_0     : std_logic_vector(7 downto 0) := x"45";
  constant SC_MINUS : std_logic_vector(7 downto 0) := x"4E";
  constant SC_EQUAL : std_logic_vector(7 downto 0) := x"55";
  constant SC_BKSP  : std_logic_vector(7 downto 0) := x"66";
  constant SC_Q     : std_logic_vector(7 downto 0) := x"15";
  constant SC_W     : std_logic_vector(7 downto 0) := x"1D";
  constant SC_E     : std_logic_vector(7 downto 0) := x"24";
  constant SC_R     : std_logic_vector(7 downto 0) := x"2D";
  constant SC_T     : std_logic_vector(7 downto 0) := x"2C";
  constant SC_Y     : std_logic_vector(7 downto 0) := x"35";
  constant SC_UP    : std_logic_vector(7 downto 0) := x"75";
  constant SC_DOWN  : std_logic_vector(7 downto 0) := x"72";
  constant SC_LEFT  : std_logic_vector(7 downto 0) := x"6B";
  constant SC_RIGHT : std_logic_vector(7 downto 0) := x"74";
begin
  edit_track <= track_reg;
  edit_step  <= step_reg;

  process(clk)
  begin
    if rising_edge(clk) then
      play_stop   <= '0';
      toggle_step <= '0';
      clear_track <= '0';
      tempo_up    <= '0';
      tempo_down  <= '0';

      if rst = '1' then
        track_reg <= (others => '0');
        step_reg  <= (others => '0');
      elsif key_valid = '1' and key_break = '0' then
        if key_code = SC_SPACE then play_stop <= '1'; end if;

        -- Number keys toggle steps 0-9
        if key_code = SC_1 then toggle_step <= '1'; step_reg <= x"0"; end if;
        if key_code = SC_2 then toggle_step <= '1'; step_reg <= x"1"; end if;
        if key_code = SC_3 then toggle_step <= '1'; step_reg <= x"2"; end if;
        if key_code = SC_4 then toggle_step <= '1'; step_reg <= x"3"; end if;
        if key_code = SC_5 then toggle_step <= '1'; step_reg <= x"4"; end if;
        if key_code = SC_6 then toggle_step <= '1'; step_reg <= x"5"; end if;
        if key_code = SC_7 then toggle_step <= '1'; step_reg <= x"6"; end if;
        if key_code = SC_8 then toggle_step <= '1'; step_reg <= x"7"; end if;
        if key_code = SC_9 then toggle_step <= '1'; step_reg <= x"8"; end if;
        if key_code = SC_0 then toggle_step <= '1'; step_reg <= x"9"; end if;
        -- Q-Y toggle steps 10-15
        if key_code = SC_Q then toggle_step <= '1'; step_reg <= x"A"; end if;
        if key_code = SC_W then toggle_step <= '1'; step_reg <= x"B"; end if;
        if key_code = SC_E then toggle_step <= '1'; step_reg <= x"C"; end if;
        if key_code = SC_R then toggle_step <= '1'; step_reg <= x"D"; end if;
        if key_code = SC_T then toggle_step <= '1'; step_reg <= x"E"; end if;
        if key_code = SC_Y then toggle_step <= '1'; step_reg <= x"F"; end if;

        -- Arrow keys: track/step navigation
        if key_ext = '1' then
          if key_code = SC_UP and track_reg > 0 then
            track_reg <= track_reg - 1;
          end if;
          if key_code = SC_DOWN and track_reg < 11 then
            track_reg <= track_reg + 1;
          end if;
          if key_code = SC_LEFT and step_reg > 0 then
            step_reg <= step_reg - 1;
          end if;
          if key_code = SC_RIGHT and step_reg < 15 then
            step_reg <= step_reg + 1;
          end if;
        end if;

        if key_code = SC_EQUAL then tempo_up <= '1'; end if;
        if key_code = SC_MINUS then tempo_down <= '1'; end if;
        if key_code = SC_BKSP then clear_track <= '1'; end if;
      end if;
    end if;
  end process;
end architecture rtl;
