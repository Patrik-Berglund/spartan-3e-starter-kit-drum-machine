library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity kick_drum is
  port (
    clk         : in  std_logic;
    rst         : in  std_logic;
    sample_tick : in  std_logic;
    trigger     : in  std_logic;
    audio_out   : out signed(11 downto 0)
  );
end entity kick_drum;

architecture rtl of kick_drum is
  -- Phase accumulator (16-bit) for sine approximation
  signal phase     : unsigned(15 downto 0) := (others => '0');
  signal freq      : unsigned(15 downto 0) := (others => '0');
  signal amplitude : unsigned(11 downto 0) := (others => '0');
  signal decay_cnt : unsigned(7 downto 0) := (others => '0');
  signal active    : std_logic := '0';

  -- Sine approximation: parabolic, using top bits of phase
  -- phase(15..14) = quadrant, phase(13..0) = position
  function sine_approx(ph : unsigned(15 downto 0)) return signed is
    variable half : unsigned(14 downto 0);
    variable x    : signed(12 downto 0);
    variable y    : signed(12 downto 0);
  begin
    half := ph(14 downto 0);
    -- Triangle wave first, then shape
    if ph(14) = '0' then
      x := signed('0' & resize(half(13 downto 2), 12));
    else
      x := signed('0' & (not resize(half(13 downto 2), 12)));
    end if;
    -- Scale to +/- range
    y := x - 2048;
    if ph(15) = '1' then
      y := -y;
    end if;
    return y(11 downto 0);
  end function;

begin
  process(clk)
    variable sine_val : signed(11 downto 0);
    variable scaled   : signed(23 downto 0);
  begin
    if rising_edge(clk) then
      if rst = '1' then
        phase     <= (others => '0');
        freq      <= (others => '0');
        amplitude <= (others => '0');
        active    <= '0';
        audio_out <= (others => '0');
        decay_cnt <= (others => '0');
      else
        if trigger = '1' then
          active    <= '1';
          phase     <= (others => '0');
          freq      <= to_unsigned(3200, 16);  -- ~150 Hz start
          amplitude <= to_unsigned(4095, 12);
          decay_cnt <= (others => '0');
        end if;

        if sample_tick = '1' and active = '1' then
          -- Advance phase
          phase <= phase + freq;

          -- Pitch decay (sweep down): every 4 samples, reduce freq
          decay_cnt <= decay_cnt + 1;
          if decay_cnt(1 downto 0) = "11" then
            if freq > 400 then  -- ~20 Hz floor
              freq <= freq - 4;
            end if;
          end if;

          -- Amplitude decay: every 8 samples, reduce
          if decay_cnt(2 downto 0) = "111" then
            amplitude <= amplitude - ("0000" & amplitude(11 downto 4));
            if amplitude < 16 then
              active <= '0';
              amplitude <= (others => '0');
            end if;
          end if;

          -- Output
          sine_val := sine_approx(phase);
          scaled := sine_val * signed('0' & amplitude);
          audio_out <= scaled(23 downto 12);
        elsif active = '0' then
          audio_out <= (others => '0');
        end if;
      end if;
    end if;
  end process;

end architecture rtl;
