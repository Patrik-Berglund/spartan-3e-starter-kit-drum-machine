library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

-- 2-pole state-variable filter (low-pass output).
-- Cutoff and resonance controlled externally.
-- Uses 2 MULT18x18 for the multiply operations.

entity bass_filter is
  port (
    clk         : in  std_logic;
    rst         : in  std_logic;
    sample_tick : in  std_logic;
    audio_in    : in  signed(11 downto 0);
    cutoff      : in  unsigned(11 downto 0);  -- 0=closed, 4095=open (maps to F coefficient)
    resonance   : in  unsigned(3 downto 0);   -- 0=none, 15=max
    audio_out   : out signed(11 downto 0)
  );
end entity bass_filter;

architecture rtl of bass_filter is
  -- SVF state: band-pass and low-pass accumulators (18-bit for headroom)
  signal bp : signed(17 downto 0) := (others => '0');
  signal lp : signed(17 downto 0) := (others => '0');

  -- F coefficient: cutoff scaled to 0..4095 range (12-bit fraction)
  -- Q damping: 2 - resonance/8 (in 12-bit fixed point)
  signal f_coeff : signed(12 downto 0) := (others => '0');
  signal q_damp  : signed(12 downto 0) := (others => '0');
begin

  -- Map cutoff to F coefficient (direct pass-through, scaled)
  -- F = cutoff (0-4095 maps to 0.0 - ~1.0 in 12-bit fixed point)
  f_coeff <= signed('0' & cutoff);

  -- Q damping = 2.0 - resonance * 0.12 (in 12-bit fixed: 8192 - res*500)
  -- At res=0: damp=8192 (2.0), at res=15: damp=700 (~0.17) = self-oscillation
  q_damp <= to_signed(8192 - to_integer(resonance) * 500, 13);

  process(clk)
    variable hp       : signed(17 downto 0);
    variable bp_new   : signed(17 downto 0);
    variable lp_new   : signed(17 downto 0);
    variable f_bp     : signed(30 downto 0);  -- f * bp (13 * 18 = 31 bits)
    variable q_bp     : signed(30 downto 0);  -- q * bp
    variable input_ext: signed(17 downto 0);
  begin
    if rising_edge(clk) then
      if rst = '1' then
        bp <= (others => '0');
        lp <= (others => '0');
        audio_out <= (others => '0');
      elsif sample_tick = '1' then
        input_ext := resize(audio_in, 18);

        -- SVF equations (fixed-point, 12 fractional bits):
        -- hp = input - lp - q*bp
        -- bp_new = bp + f*hp
        -- lp_new = lp + f*bp

        -- lp_new = lp + f*bp (use old bp)
        f_bp := f_coeff * bp;
        lp_new := lp + f_bp(29 downto 12);  -- shift right 12 (fixed point)

        -- hp = input - lp - q*bp
        q_bp := q_damp * bp;
        hp := input_ext - lp - q_bp(29 downto 12);

        -- bp_new = bp + f*hp
        f_bp := f_coeff * resize(hp, 18);
        bp_new := bp + f_bp(29 downto 12);

        -- Clamp state to prevent overflow
        if bp_new > 131071 then bp_new := to_signed(131071, 18);
        elsif bp_new < -131072 then bp_new := to_signed(-131072, 18);
        end if;
        if lp_new > 131071 then lp_new := to_signed(131071, 18);
        elsif lp_new < -131072 then lp_new := to_signed(-131072, 18);
        end if;

        bp <= bp_new;
        lp <= lp_new;

        -- Output: low-pass, scaled back to 12 bits
        if lp_new > 2047 then
          audio_out <= to_signed(2047, 12);
        elsif lp_new < -2048 then
          audio_out <= to_signed(-2048, 12);
        else
          audio_out <= lp_new(11 downto 0);
        end if;
      end if;
    end if;
  end process;

end architecture rtl;
