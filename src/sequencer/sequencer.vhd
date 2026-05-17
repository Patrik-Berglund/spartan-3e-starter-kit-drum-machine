library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

-- 12-track sequencer: AC, BD, SD, LT, MT, HT, RS, CP, CB, CY, OH, CH
-- Track 0 = Accent (modifies volume, not a voice itself)
-- Tracks 1-11 = drum voices
-- Bass note entry removed for now (pure 808 mode).

entity sequencer is
  port (
    clk          : in  std_logic;
    rst          : in  std_logic;
    -- Transport
    play_stop    : in  std_logic;
    step_advance : in  std_logic;
    -- Pattern editing
    edit_track   : in  unsigned(3 downto 0);  -- 0-11
    edit_step    : in  unsigned(3 downto 0);  -- 0-15
    toggle_step  : in  std_logic;
    clear_track  : in  std_logic;
    -- Status
    playing      : out std_logic;
    current_step : out unsigned(3 downto 0);
    -- Trigger outputs (one cycle pulse)
    trig_out     : out std_logic_vector(11 downto 0);
    accent       : out std_logic;
    -- Full pattern readback for display (192 bits)
    pattern_flat : out std_logic_vector(191 downto 0)
  );
end entity sequencer;

architecture rtl of sequencer is
  type pattern_array is array (0 to 11) of std_logic_vector(15 downto 0);
  signal patterns : pattern_array := (others => (others => '0'));
  signal play_reg : std_logic := '0';
  signal step_reg : unsigned(3 downto 0) := (others => '0');
begin
  playing      <= play_reg;
  current_step <= step_reg;

  -- Flatten patterns for display
  gen_flat: for i in 0 to 11 generate
    pattern_flat(i*16+15 downto i*16) <= patterns(i);
  end generate;

  process(clk)
    variable stp : integer range 0 to 15;
    variable trk : integer range 0 to 11;
  begin
    if rising_edge(clk) then
      trig_out <= (others => '0');
      accent   <= '0';

      if rst = '1' then
        play_reg <= '1';  -- auto-play on startup
        step_reg <= (others => '0');
        -- Demo pattern: classic 808 beat
        patterns(0)  <= "0000000000000000"; -- AC
        patterns(1)  <= "0000000100000001"; -- BD (step 0, 8)
        patterns(2)  <= "0001000000010000"; -- SD (step 4, 12)
        patterns(3)  <= "0000000000000000"; -- LT
        patterns(4)  <= "0000000000000000"; -- MT
        patterns(5)  <= "0000000000000000"; -- HT
        patterns(6)  <= "0000000000000000"; -- RS
        patterns(7)  <= "0000010000000000"; -- CP (step 10)
        patterns(8)  <= "0000000000000000"; -- CB
        patterns(9)  <= "0000000000000000"; -- CY
        patterns(10) <= "0000000100000000"; -- OH (step 8)
        patterns(11) <= "0101010101010101"; -- CH (every even step)
      else
        -- Play/stop toggle
        if play_stop = '1' then
          play_reg <= not play_reg;
          if play_reg = '0' then
            step_reg <= (others => '0');
          end if;
        end if;

        -- Step advance
        if step_advance = '1' and play_reg = '1' then
          stp := to_integer(step_reg);
          -- Fire triggers for active steps
          for i in 0 to 11 loop
            if patterns(i)(stp) = '1' then
              trig_out(i) <= '1';
            end if;
          end loop;
          -- Accent flag
          if patterns(0)(stp) = '1' then
            accent <= '1';
          end if;
          step_reg <= step_reg + 1;
        end if;

        -- Editing
        if toggle_step = '1' then
          trk := to_integer(edit_track);
          stp := to_integer(edit_step);
          if trk < 12 then
            patterns(trk)(stp) <= not patterns(trk)(stp);
          end if;
        end if;

        if clear_track = '1' then
          trk := to_integer(edit_track);
          if trk < 12 then
            patterns(trk) <= (others => '0');
          end if;
        end if;
      end if;
    end if;
  end process;
end architecture rtl;
