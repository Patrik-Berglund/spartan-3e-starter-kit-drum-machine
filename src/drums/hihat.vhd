library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

-- 808 Closed Hi-Hat - 6 oscillators through a resonant bandpass filter.
--
-- Previous design used a 5-stage cascade of real single-pole HP filters.
-- A hardware DAC capture (2026-08-02) confirmed the cascade matched the
-- sim exactly (not a hardware bug) but both disagreed badly with the real
-- TR-808 reference: real CH energy is *concentrated* in the 8-16kHz band
-- (65.2%, vs only 7.7% in 16-24kHz), and a cascade of N real single poles
-- can only produce a monotonic rolloff -- it mathematically cannot
-- reproduce a concentrated/resonant band no matter how many stages are
-- stacked. That mismatch (old: 46.9%/24.9% in the two bands) is what
-- made the real board sound "way too thin" / "like a bell" instead of
-- broadband metallic shimmer.
--
-- Fix: a 2-pole resonant state-variable filter (Chamberlin SVF, same
-- topology as the cowbell's bandpass) with an actual resonant peak,
-- f=1 (no attenuation), res=3/8. Achieved bands (2-4k/4-8k/8-16k/16-24k):
-- 2.7/23.9/66.1/6.7 vs real 0.1/26.9/65.2/7.7. noise_mult=12 (post-filter
-- LFSR noise, higher than the old cascade needed since the resonant peak
-- alone is narrower than the real noisy texture).

entity hihat is
  port (
    clk         : in  std_logic;
    rst         : in  std_logic;
    sample_tick : in  std_logic;
    trigger     : in  std_logic;
    audio_out   : out signed(15 downto 0)
  );
end entity hihat;

architecture rtl of hihat is
  signal p0, p1, p2, p3, p4, p5 : unsigned(15 downto 0) := (others => '0');
  signal amp     : unsigned(19 downto 0) := (others => '0');
  signal active  : std_logic := '0';
  -- Resonant state-variable filter state (bandpass output = bp)
  signal lp_reg, bp_reg : signed(18 downto 0) := (others => '0');
  signal lfsr : std_logic_vector(15 downto 0) := x"F00D";
begin
  process(clk)
    variable sq : signed(4 downto 0);
    variable raw : signed(18 downto 0);
    variable noise_raw : signed(15 downto 0);
    variable noise_scaled : signed(18 downto 0);
    variable res_term : signed(18 downto 0);
    variable new_hp : signed(18 downto 0);
    variable new_bp, new_lp : signed(18 downto 0);
    variable bp_clamped : signed(15 downto 0);
    variable product : signed(27 downto 0);
    variable dec_term : unsigned(19 downto 0);
  begin
    if rising_edge(clk) then
      if rst = '1' then
        p0 <= (others => '0'); p1 <= (others => '0');
        p2 <= (others => '0'); p3 <= (others => '0');
        p4 <= (others => '0'); p5 <= (others => '0');
        amp <= (others => '0'); active <= '0';
        lp_reg <= (others => '0'); bp_reg <= (others => '0');
        lfsr <= x"F00D";
        audio_out <= (others => '0');
      else
        if sample_tick = '1' then
          p0 <= p0 + to_unsigned(275, 16);
          p1 <= p1 + to_unsigned(409, 16);
          p2 <= p2 + to_unsigned(496, 16);
          p3 <= p3 + to_unsigned(702, 16);
          p4 <= p4 + to_unsigned(725, 16);
          p5 <= p5 + to_unsigned(1075, 16);
        end if;

        if trigger = '1' then
          active <= '1';
          amp <= to_unsigned(1048575, 20);
        end if;

        if sample_tick = '1' and active = '1' then
          sq := to_signed(0, 5);
          if p0(15) = '1' then sq := sq + 1; else sq := sq - 1; end if;
          if p1(15) = '1' then sq := sq + 1; else sq := sq - 1; end if;
          if p2(15) = '1' then sq := sq + 1; else sq := sq - 1; end if;
          if p3(15) = '1' then sq := sq + 1; else sq := sq - 1; end if;
          if p4(15) = '1' then sq := sq + 1; else sq := sq - 1; end if;
          if p5(15) = '1' then sq := sq + 1; else sq := sq - 1; end if;

          -- Scale: sq*5440
          raw := shift_left(resize(sq, 19), 12) + shift_left(resize(sq, 19), 10) +
                 shift_left(resize(sq, 19), 8) + shift_left(resize(sq, 19), 6);

          -- Broadband LFSR noise mixed in before filtering, noise_mult=12
          -- (=8+4, shift-and-add to avoid a MULT18X18 - see gotcha #8).
          lfsr <= lfsr(14 downto 0) & (lfsr(15) xor lfsr(13) xor lfsr(12) xor lfsr(10));
          noise_raw := signed(resize(unsigned(lfsr(14 downto 0)), 16)) - to_signed(16384, 16);
          noise_scaled := shift_right(shift_left(resize(noise_raw, 19), 3) +
                                       shift_left(resize(noise_raw, 19), 2), 3);
          raw := raw + noise_scaled;

          -- Resonant state-variable bandpass (Chamberlin SVF):
          --   hp = raw - lp - res*bp   (res = 3/8, shift-and-add: bp*3>>3)
          --   bp += f*hp               (f = 1, full rate)
          --   lp += f*bp               (uses the NEW bp - see gotcha #7:
          --     computing into a variable first, not reading the signal,
          --     matches the sim's immediate-update semantics and avoids
          --     the severe sim/hardware mismatch bug found previously)
          res_term := shift_right(shift_left(resize(bp_reg, 19), 1) + resize(bp_reg, 19), 3);
          new_hp := raw - lp_reg - res_term;
          new_bp := bp_reg + new_hp;
          new_lp := lp_reg + new_bp;
          bp_reg <= new_bp;
          lp_reg <= new_lp;

          if new_bp > 32767 then bp_clamped := to_signed(32767, 16);
          elsif new_bp < -32768 then bp_clamped := to_signed(-32768, 16);
          else bp_clamped := new_bp(15 downto 0);
          end if;

          -- Multiply by amplitude (top 11 bits of the 20-bit amp)
          product := bp_clamped * signed('0' & amp(19 downto 9));
          audio_out <= product(26 downto 11);

          -- Exponential decay: K=10, with linear tail
          dec_term := "0000000000" & amp(19 downto 10);
          if dec_term = 0 then
            amp <= amp - 1;
          else
            amp <= amp - dec_term;
          end if;

          if amp < 8192 then
            active <= '0';
            audio_out <= (others => '0');
          end if;
        elsif active = '0' then
          audio_out <= (others => '0');
        end if;
      end if;
    end if;
  end process;
end architecture rtl;
