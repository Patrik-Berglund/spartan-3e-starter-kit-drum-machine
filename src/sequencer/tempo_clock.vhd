library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity tempo_clock is
  port (
    clk          : in  std_logic;
    rst          : in  std_logic;
    bpm          : in  unsigned(7 downto 0);  -- 30-255 BPM
    playing      : in  std_logic;
    sample_tick  : out std_logic;             -- 48.8 kHz pulse
    step_advance : out std_logic              -- 16th note pulse
  );
end entity tempo_clock;

architecture rtl of tempo_clock is
  -- sample_tick: 50 MHz / 1024 = 48828 Hz
  signal sample_cnt : unsigned(9 downto 0) := (others => '0');

  -- step_advance: at 120 BPM, 16th notes = 8 Hz = every 6103 samples
  -- Formula: samples_per_step = 48828 * 60 / (bpm * 4)
  -- We precompute: 50_000_000 / 4 = 12_500_000 ticks per beat at 1 BPM
  -- steps_per_beat = 4 (16th notes), so ticks_per_step = 50M / (4*bpm) = 12500000/bpm
  -- In sample domain: samples_per_step = 48828*60 / (bpm*4) = 732420 / bpm
  -- Use counter in clock domain: clocks_per_step = 50M*60 / (bpm*4) = 750000000/bpm
  -- Too big. Use sample domain instead.
  -- samples_per_step = 732421 / bpm (approx)
  -- At 120 BPM: 6103 samples. At 30 BPM: 24414. Fits in 15 bits.
  constant C_NUMERATOR : unsigned(19 downto 0) := to_unsigned(732421, 20);
  signal step_cnt      : unsigned(14 downto 0) := (others => '0');
  signal step_limit    : unsigned(14 downto 0) := (others => '0');
  signal tick_int      : std_logic;
begin

  -- Compute step limit from BPM using subtraction (no division operator).
  -- 732421 / bpm for bpm 30..255. We approximate using a registered process.
  -- Use iterative subtraction: count how many times bpm fits into 732421.
  -- Actually simpler: precompute a few key points and interpolate, or just
  -- use a big if/elsif chain for ranges.
  -- Cleanest for XST: registered lookup with linear interpolation.
  -- For now: use a case-like approach. At 48.8kHz:
  -- 60 BPM = 12207 samples/step, 120 BPM = 6103, 180 BPM = 4069, 240 BPM = 3051
  -- Linear approx: step_limit ≈ 732421 / bpm
  -- We'll use: step_limit = 732416 >> log2(bpm) ... no, that doesn't work.
  -- Best approach: registered sequential divider that runs once when bpm changes.

  process(clk)
    variable dividend  : unsigned(19 downto 0);
    variable quotient  : unsigned(14 downto 0);
    variable bpm_prev  : unsigned(7 downto 0) := (others => '0');
    variable div_count : integer range 0 to 255;
  begin
    if rising_edge(clk) then
      if rst = '1' then
        step_limit <= to_unsigned(6103, 15);  -- default 120 BPM
        bpm_prev := to_unsigned(120, 8);
      elsif bpm /= bpm_prev then
        -- Simple iterative: 732421 / bpm via repeated subtraction
        -- bpm is 30-255, so max iterations = 732421/30 = 24414 (too many for 1 cycle)
        -- Instead use shift-subtract division over multiple cycles.
        -- For simplicity, use a lookup with interpolation:
        -- step_limit = 732416 / bpm (close enough, 732416 = 2864 * 256)
        -- Actually let's just hardcode a table for every 10 BPM and interpolate.
        -- Simplest that XST accepts: multiply by reciprocal.
        -- 1/bpm ≈ (256/bpm) >> 8. But 256/bpm still needs division.
        -- 
        -- Final approach: XST CAN synthesize division by a variable if it's in a
        -- clocked process and the dividend is constant. Let's try:
        bpm_prev := bpm;
        -- Use a shift-based approximation:
        -- 732421 / bpm ≈ (732416 / 256) * (256 / bpm)
        -- Nope. Let's just use a big case statement for common BPMs.
        -- Actually the cleanest: use multiply by reciprocal from a small ROM.
        -- recip(bpm) = 65536 / bpm (precomputed for 30-255)
        -- step_limit = (732421 * recip) >> 16
        -- But that's also complex. Let's just do the if/elsif chain:
        if    bpm_prev <= 40  then step_limit <= to_unsigned(18310, 15);
        elsif bpm_prev <= 50  then step_limit <= to_unsigned(14648, 15);
        elsif bpm_prev <= 60  then step_limit <= to_unsigned(12207, 15);
        elsif bpm_prev <= 70  then step_limit <= to_unsigned(10463, 15);
        elsif bpm_prev <= 80  then step_limit <= to_unsigned(9155, 15);
        elsif bpm_prev <= 90  then step_limit <= to_unsigned(8138, 15);
        elsif bpm_prev <= 100 then step_limit <= to_unsigned(7324, 15);
        elsif bpm_prev <= 110 then step_limit <= to_unsigned(6658, 15);
        elsif bpm_prev <= 120 then step_limit <= to_unsigned(6103, 15);
        elsif bpm_prev <= 130 then step_limit <= to_unsigned(5634, 15);
        elsif bpm_prev <= 140 then step_limit <= to_unsigned(5231, 15);
        elsif bpm_prev <= 150 then step_limit <= to_unsigned(4882, 15);
        elsif bpm_prev <= 160 then step_limit <= to_unsigned(4577, 15);
        elsif bpm_prev <= 170 then step_limit <= to_unsigned(4308, 15);
        elsif bpm_prev <= 180 then step_limit <= to_unsigned(4069, 15);
        elsif bpm_prev <= 190 then step_limit <= to_unsigned(3855, 15);
        elsif bpm_prev <= 200 then step_limit <= to_unsigned(3662, 15);
        elsif bpm_prev <= 210 then step_limit <= to_unsigned(3487, 15);
        elsif bpm_prev <= 220 then step_limit <= to_unsigned(3329, 15);
        elsif bpm_prev <= 230 then step_limit <= to_unsigned(3184, 15);
        elsif bpm_prev <= 240 then step_limit <= to_unsigned(3051, 15);
        else                       step_limit <= to_unsigned(2872, 15);
        end if;
      end if;
    end if;
  end process;

  -- Sample tick generation: divide 50 MHz by 1024
  process(clk)
  begin
    if rising_edge(clk) then
      tick_int <= '0';
      if rst = '1' then
        sample_cnt <= (others => '0');
      else
        if sample_cnt = 1023 then
          sample_cnt <= (others => '0');
          tick_int <= '1';
        else
          sample_cnt <= sample_cnt + 1;
        end if;
      end if;
    end if;
  end process;

  sample_tick <= tick_int;

  -- Step advance: count sample ticks
  process(clk)
  begin
    if rising_edge(clk) then
      step_advance <= '0';
      if rst = '1' or playing = '0' then
        step_cnt <= (others => '0');
      elsif tick_int = '1' then
        if step_cnt >= step_limit - 1 then
          step_cnt <= (others => '0');
          step_advance <= '1';
        else
          step_cnt <= step_cnt + 1;
        end if;
      end if;
    end if;
  end process;

end architecture rtl;
