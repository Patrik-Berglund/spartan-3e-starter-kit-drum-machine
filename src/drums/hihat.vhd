library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

-- 808 Closed Hi-Hat - 6 oscillators through steep HP cascade + LP rolloff.
--
-- Deep re-investigation found the previous filter (3-4 gentle HP stages)
-- let 21-31% of energy leak through below 4kHz, giving a "buzzy" character
-- instead of the real 808's "shimmery" metallic sound (measured <2% energy
-- below 4kHz). Root cause: real circuit has 3 cascaded filter stages
-- (op-amp HPF + VCA rolloff + 2nd HPF specific to CH).
--
-- 5-stage HP cascade (all shift=1) + LP rolloff (shift=2) + small amount
-- of POST-FILTER noise (restores the real 808's fast "shimmer" -
-- ZCR~22-25k/s vs the old filter's ~8k/s) + gain compensation for the
-- much lower pass-band level after steeper filtering.

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
  -- 5-stage HP cascade (all shift=1), then LP rolloff stage
  signal hp_acc0, hp_acc1, hp_acc2, hp_acc3, hp_acc4 : signed(17 downto 0) := (others => '0');
  signal lp_out_acc : signed(17 downto 0) := (others => '0');
  -- Post-filter noise source for shimmer (LFSR)
  signal lfsr : std_logic_vector(15 downto 0) := x"F00D";
begin
  process(clk)
    variable sq : signed(4 downto 0);
    variable raw : signed(17 downto 0);
    variable x0, x1, x2, x3, x4 : signed(17 downto 0);
    variable new_hp0, new_hp1, new_hp2, new_hp3, new_hp4 : signed(17 downto 0);
    variable new_lp : signed(17 downto 0);
    variable bp : signed(17 downto 0);
    variable noise_raw : signed(15 downto 0);
    variable noise_scaled : signed(17 downto 0);
    variable bp_gained : signed(23 downto 0);
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
        hp_acc0 <= (others => '0'); hp_acc1 <= (others => '0');
        hp_acc2 <= (others => '0'); hp_acc3 <= (others => '0'); hp_acc4 <= (others => '0');
        lp_out_acc <= (others => '0');
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
          raw := shift_left(resize(sq, 18), 12) + shift_left(resize(sq, 18), 10) +
                 shift_left(resize(sq, 18), 8) + shift_left(resize(sq, 18), 6);

          -- Mix in broadband LFSR noise BEFORE filtering (noise_mult=3,
          -- scaled by >>3) - matches sim's render_metallic_core exactly.
          lfsr <= lfsr(14 downto 0) & (lfsr(15) xor lfsr(13) xor lfsr(12) xor lfsr(10));
          noise_raw := signed(resize(unsigned(lfsr(14 downto 0)), 16)) - to_signed(16384, 16);
          noise_scaled := resize(shift_right(resize(noise_raw, 18) * 3, 3), 18);
          raw := raw + noise_scaled;

          -- 5-stage HP cascade, all shift=1. Compute the new accumulator
          -- value into a variable FIRST, then subtract that (not the old
          -- signal value) to get x_i -- matches sim's immediate-update
          -- semantics (hp[i]=hp[i]+delta; x=x-hp[i] uses the NEW hp[i]).
          -- Reading the signal directly for the subtraction would use the
          -- OLD (pre-clock-edge) value instead, causing a severe
          -- amplitude/spectral mismatch vs the sim (confirmed on hardware:
          -- output was clipping/garbage instead of a clean filtered tone).
          new_hp0 := hp_acc0 + shift_right(raw - hp_acc0, 1);
          x0 := raw - new_hp0;
          hp_acc0 <= new_hp0;
          new_hp1 := hp_acc1 + shift_right(x0 - hp_acc1, 1);
          x1 := x0 - new_hp1;
          hp_acc1 <= new_hp1;
          new_hp2 := hp_acc2 + shift_right(x1 - hp_acc2, 1);
          x2 := x1 - new_hp2;
          hp_acc2 <= new_hp2;
          new_hp3 := hp_acc3 + shift_right(x2 - hp_acc3, 1);
          x3 := x2 - new_hp3;
          hp_acc3 <= new_hp3;
          new_hp4 := hp_acc4 + shift_right(x3 - hp_acc4, 1);
          x4 := x3 - new_hp4;
          hp_acc4 <= new_hp4;
          bp := x4;

          -- LP rolloff stage (shift=2) - same immediate-update fix as HP cascade
          new_lp := lp_out_acc + shift_right(bp - lp_out_acc, 2);
          bp := new_lp;
          lp_out_acc <= new_lp;

          -- Gain compensation (x70 = x2+x4+x64) for the steeper filter's
          -- reduced level. Shift-and-add instead of a multiply to avoid
          -- consuming a MULT18X18 block (device is at 95% utilization).
          bp_gained := shift_left(resize(bp, 24), 1) + shift_left(resize(bp, 24), 2) +
                       shift_left(resize(bp, 24), 6);
          if bp_gained > 32767 then bp_clamped := to_signed(32767, 16);
          elsif bp_gained < -32768 then bp_clamped := to_signed(-32768, 16);
          else bp_clamped := bp_gained(15 downto 0);
          end if;

          -- Multiply by amplitude (top 11 bits of the 20-bit amp)
          product := bp_clamped * signed('0' & amp(19 downto 9));
          audio_out <= product(26 downto 11);

          -- Exponential decay: K=9, with linear tail
          dec_term := "000000000" & amp(19 downto 9);
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
