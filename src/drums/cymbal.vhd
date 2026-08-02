library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity cymbal is
  port (
    clk         : in  std_logic;
    rst         : in  std_logic;
    sample_tick : in  std_logic;
    trigger     : in  std_logic;
    tone        : in  unsigned(7 downto 0);
    decay       : in  unsigned(7 downto 0);
    audio_out   : out signed(15 downto 0)
  );
end entity cymbal;

architecture rtl of cymbal is
  signal p0, p1, p2, p3, p4, p5 : unsigned(15 downto 0) := (others => '0');
  signal amp     : unsigned(19 downto 0) := (others => '0');  -- widened from
    -- 16 to 20 bits: at K=13-15 (needed for the real 808's 185-758ms decay
    -- times), a 16-bit amp's floor (2^K = 8192-32768) sits at only -6 to
    -- -12dB below full scale, causing an audible "death click" when the
    -- voice cuts out. 20 bits pushes the floor down to -30dB or lower.
  signal active  : std_logic := '0';
  -- BPF: 1-stage LP + 4-stage HP. Widened to 18-bit (see hihat.vhd comment
  -- for rationale -- square-sum + noise can reach +-53118, overflowing a
  -- 16-bit signed accumulator and causing runaway noise buildup).
  signal lp_acc : signed(17 downto 0) := (others => '0');
  signal hp_acc0, hp_acc1, hp_acc2, hp_acc3 : signed(17 downto 0) := (others => '0');
  -- Broadband noise source (same rationale as hihat.vhd) -- unique seed to
  -- decorrelate from CH/OH.
  signal lfsr : std_logic_vector(15 downto 0) := x"C0DE";

  -- TONE: LP shift (brighter at high tone) + HP shift (brighter cymbal
  -- character than CH/OH -- real 808 CY centroid ~5800-6450Hz measured)
  signal lp_shift : integer range 1 to 2;
  signal hp_shift : integer range 2 to 3;
  -- DECAY: K value 13-15 (real 808 CY decay tau 185-758ms, much longer
  -- than CH/OH's ms-scale decays)
  signal decay_k : integer range 13 to 15;
begin
  -- Map tone 0-255: darker below mid, brighter above
  hp_shift <= 3 when tone < 86 else 2;
  lp_shift <= 1 when tone >= 171 else 2;

  -- Map decay 0-255 to K 13..15 (matches measured real 808 tau 185-758ms)
  decay_k <= 13 when decay < 86 else
             14 when decay < 171 else
             15;

  process(clk)
    variable sq : signed(4 downto 0);
    variable raw : signed(17 downto 0);
    variable noise_raw : signed(15 downto 0);
    variable noise_wide : signed(18 downto 0);
    variable noise_scaled : signed(17 downto 0);
    variable lp_out : signed(17 downto 0);
    variable x0, x1, x2, x3 : signed(17 downto 0);
    variable x3_clamped : signed(15 downto 0);
    variable product : signed(27 downto 0);
  begin
    if rising_edge(clk) then
      if rst = '1' then
        p0 <= (others => '0'); p1 <= (others => '0');
        p2 <= (others => '0'); p3 <= (others => '0');
        p4 <= (others => '0'); p5 <= (others => '0');
        amp <= (others => '0'); active <= '0';
        lp_acc <= (others => '0');
        hp_acc0 <= (others => '0'); hp_acc1 <= (others => '0');
        hp_acc2 <= (others => '0'); hp_acc3 <= (others => '0');
        lfsr <= x"C0DE";
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
          active <= '1'; amp <= to_unsigned(1048575, 20);  -- 20-bit full scale
        end if;

        if sample_tick = '1' and active = '1' then
          sq := to_signed(0, 5);
          if p0(15) = '1' then sq := sq + 1; else sq := sq - 1; end if;
          if p1(15) = '1' then sq := sq + 1; else sq := sq - 1; end if;
          if p2(15) = '1' then sq := sq + 1; else sq := sq - 1; end if;
          if p3(15) = '1' then sq := sq + 1; else sq := sq - 1; end if;
          if p4(15) = '1' then sq := sq + 1; else sq := sq - 1; end if;
          if p5(15) = '1' then sq := sq + 1; else sq := sq - 1; end if;

          raw := shift_left(resize(sq, 18), 12) + shift_left(resize(sq, 18), 10) +
                 shift_left(resize(sq, 18), 8) + shift_left(resize(sq, 18), 6);

          -- Mix in broadband LFSR noise (noise_mult=10, scaled by >>3);
          -- shift-and-add (10x = 8x+2x) instead of a multiply to avoid
          -- consuming a MULT18X18 block.
          lfsr <= lfsr(14 downto 0) & (lfsr(15) xor lfsr(13) xor lfsr(12) xor lfsr(10));
          noise_raw := signed(lfsr(14 downto 0) & '0') - to_signed(16384, 16);
          noise_wide := shift_left(resize(noise_raw, 19), 3) + shift_left(resize(noise_raw, 19), 1);
          noise_scaled := resize(shift_right(noise_wide, 3), 18);
          raw := raw + noise_scaled;

          -- BPF: 1-stage LP (variable shift) + 4-stage HP (shift=4) --
          -- retuned to preserve the injected noise's spectral contribution
          -- (sim result vs real CY5050.WAV: centroid=6557Hz/flatness=0.60
          -- vs ref centroid=6924Hz/flatness=0.49).
          case lp_shift is
            when 2 => lp_acc <= lp_acc + shift_right(raw - lp_acc, 2);
            when others => lp_acc <= lp_acc + shift_right(raw - lp_acc, 1);
          end case;
          lp_out := lp_acc;
          case hp_shift is
            when 3 =>
              hp_acc0 <= hp_acc0 + shift_right(lp_out - hp_acc0, 3);
              x0 := lp_out - hp_acc0;
              hp_acc1 <= hp_acc1 + shift_right(x0 - hp_acc1, 3);
              x1 := x0 - hp_acc1;
              hp_acc2 <= hp_acc2 + shift_right(x1 - hp_acc2, 3);
              x2 := x1 - hp_acc2;
              hp_acc3 <= hp_acc3 + shift_right(x2 - hp_acc3, 3);
              x3 := x2 - hp_acc3;
            when others =>
              hp_acc0 <= hp_acc0 + shift_right(lp_out - hp_acc0, 2);
              x0 := lp_out - hp_acc0;
              hp_acc1 <= hp_acc1 + shift_right(x0 - hp_acc1, 2);
              x1 := x0 - hp_acc1;
              hp_acc2 <= hp_acc2 + shift_right(x1 - hp_acc2, 2);
              x2 := x1 - hp_acc2;
              hp_acc3 <= hp_acc3 + shift_right(x2 - hp_acc3, 2);
              x3 := x2 - hp_acc3;
          end case;

          -- Clamp back to 16-bit before the amplitude multiply.
          if x3 > 32767 then x3_clamped := to_signed(32767, 16);
          elsif x3 < -32768 then x3_clamped := to_signed(-32768, 16);
          else x3_clamped := x3(15 downto 0);
          end if;

          product := x3_clamped * signed('0' & amp(19 downto 9));
          audio_out <= product(26 downto 11);

          -- Exponential decay with variable K on the 20-bit amp register.
          -- Force to 0 once the decay term itself is 0.
          case decay_k is
            when 13 =>
              if amp(19 downto 13) = "0000000" then amp <= (others => '0');
              else amp <= amp - ("0000000" & amp(19 downto 13)); end if;
            when 14 =>
              if amp(19 downto 14) = "000000" then amp <= (others => '0');
              else amp <= amp - ("000000" & amp(19 downto 14)); end if;
            when others => -- 15
              if amp(19 downto 15) = "00000" then amp <= (others => '0');
              else amp <= amp - ("00000" & amp(19 downto 15)); end if;
          end case;

          if amp < 8192 then
            active <= '0'; audio_out <= (others => '0');
          end if;
        elsif active = '0' then
          audio_out <= (others => '0');
        end if;
      end if;
    end if;
  end process;
end architecture rtl;
