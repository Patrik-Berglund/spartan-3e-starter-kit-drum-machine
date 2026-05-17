library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

-- 303-style oscillator: sawtooth waveform with phase accumulator.
-- Note input: 0-47 (4 octaves, C1-B4).
-- Uses a lookup table for base octave phase increments, then shifts for octave.

entity bass_osc is
  port (
    clk         : in  std_logic;
    rst         : in  std_logic;
    sample_tick : in  std_logic;
    note        : in  unsigned(5 downto 0);  -- 0=C1, 12=C2, 24=C3, 36=C4
    gate        : in  std_logic;             -- held high while note active
    audio_out   : out signed(11 downto 0)
  );
end entity bass_osc;

architecture rtl of bass_osc is
  -- Phase accumulator: 20-bit for good frequency resolution
  signal phase : unsigned(19 downto 0) := (others => '0');
  signal phase_inc : unsigned(19 downto 0) := (others => '0');

  -- Base phase increments for C1-B1 at 48828 Hz sample rate
  -- freq = note_freq, inc = freq * 2^20 / 48828
  -- C1=32.7Hz -> inc=701, C#1=34.6->743, D1=36.7->788, etc.
  type inc_table_t is array (0 to 11) of unsigned(19 downto 0);
  constant BASE_INC : inc_table_t := (
    to_unsigned(701, 20),   -- C
    to_unsigned(743, 20),   -- C#
    to_unsigned(787, 20),   -- D
    to_unsigned(834, 20),   -- D#
    to_unsigned(883, 20),   -- E
    to_unsigned(936, 20),   -- F
    to_unsigned(991, 20),   -- F#
    to_unsigned(1050, 20),  -- G
    to_unsigned(1113, 20),  -- G#
    to_unsigned(1179, 20),  -- A
    to_unsigned(1249, 20),  -- A#
    to_unsigned(1323, 20)   -- B
  );

  signal note_reg : unsigned(5 downto 0) := (others => '0');
begin

  -- Compute phase increment from note
  process(clk)
    variable semitone : integer range 0 to 11;
    variable octave   : integer range 0 to 3;
    variable base     : unsigned(19 downto 0);
  begin
    if rising_edge(clk) then
      if rst = '1' then
        phase_inc <= (others => '0');
        note_reg  <= (others => '0');
      else
        if gate = '1' and note /= note_reg then
          note_reg <= note;
          -- Decompose note into octave + semitone
          if note < 12 then
            octave := 0; semitone := to_integer(note);
          elsif note < 24 then
            octave := 1; semitone := to_integer(note) - 12;
          elsif note < 36 then
            octave := 2; semitone := to_integer(note) - 24;
          else
            octave := 3; semitone := to_integer(note) - 36;
          end if;
          base := BASE_INC(semitone);
          phase_inc <= shift_left(base, octave);
        end if;
      end if;
    end if;
  end process;

  -- Phase accumulator + sawtooth output
  process(clk)
  begin
    if rising_edge(clk) then
      if rst = '1' then
        phase     <= (others => '0');
        audio_out <= (others => '0');
      elsif sample_tick = '1' then
        if gate = '1' then
          phase <= phase + phase_inc;
          -- Sawtooth: phase top 12 bits mapped to -2048..+2047
          audio_out <= signed(phase(19 downto 8)) - 2048;
        else
          audio_out <= (others => '0');
        end if;
      end if;
    end if;
  end process;

end architecture rtl;
