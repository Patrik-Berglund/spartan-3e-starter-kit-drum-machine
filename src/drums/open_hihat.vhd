library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

-- 808 Open Hi-Hat - 6 oscillators through HP cascade + LP rolloff.
--
-- Deep re-investigation found the old filter let too much low-frequency
-- energy through (sounded buzzy). OH's real character is darker and less
-- "shimmery" than CH (centroid~9343Hz vs CH's ~11517Hz, ZCR~14976/s vs
-- CH's ~22352/s) - matches the real circuit having one fewer filter
-- stage than CH (per service manual: CH has an extra Q31 HPF that OH
-- lacks). 4-stage HP cascade (shifts 1,2,2,2, gentler than CH's all-1s)
-- + LP rolloff + small noise for shimmer + gain compensation.

entity open_hihat is
  port (
    clk         : in  std_logic;
    rst         : in  std_logic;
    sample_tick : in  std_logic;
    trigger     : in  std_logic;
    decay       : in  unsigned(7 downto 0);
    audio_out   : out signed(15 downto 0)
  );
end entity open_hihat;

architecture rtl of open_hihat is
  signal p0, p1, p2, p3, p4, p5 : unsigned(15 downto 0) := (others => '0');
  signal amp     : unsigned(19 downto 0) := (others => '0');
  signal active  : std_logic := '0';
  -- 4-stage HP cascade (shifts 1,2,2,2), then LP rolloff stage
  signal hp_acc0, hp_acc1, hp_acc2, hp_acc3 : signed(17 downto 0) := (others => '0');
  signal lp_out_acc : signed(17 downto 0) := (others => '0');
  -- Post-filter noise source for shimmer (LFSR)
  signal lfsr : std_logic_vector(15 downto 0) := x"BEE5";

  -- DECAY: K value 11-14 (real 808 OH decay 74-448ms)
  signal decay_k : integer range 11 to 14;
begin
  decay_k <= 11 when decay < 64 else
             12 when decay < 128 else
             13 when decay < 192 else
             14;

  process(clk)
    variable sq : signed(4 downto 0);
    variable raw : signed(17 downto 0);
    variable x0, x1, x2, x3 : signed(17 downto 0);
    variable new_hp0, new_hp1, new_hp2, new_hp3 : signed(17 downto 0);
    variable new_lp : signed(17 downto 0);
    variable bp : signed(17 downto 0);
    variable noise_raw : signed(15 downto 0);
    variable noise_scaled : signed(17 downto 0);
    variable bp_gained : signed(23 downto 0);
    variable bp_clamped : signed(15 downto 0);
    variable product : signed(27 downto 0);
  begin
    if rising_edge(clk) then
      if rst = '1' then
        p0 <= (others => '0'); p1 <= (others => '0');
        p2 <= (others => '0'); p3 <= (others => '0');
        p4 <= (others => '0'); p5 <= (others => '0');
        amp <= (others => '0'); active <= '0';
        hp_acc0 <= (others => '0'); hp_acc1 <= (others => '0');
        hp_acc2 <= (others => '0'); hp_acc3 <= (others => '0');
        lp_out_acc <= (others => '0');
        lfsr <= x"BEE5";
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

          raw := shift_left(resize(sq, 18), 12) + shift_left(resize(sq, 18), 10) +
                 shift_left(resize(sq, 18), 8) + shift_left(resize(sq, 18), 6);

          -- Mix in broadband LFSR noise BEFORE filtering (noise_mult=1,
          -- scaled by >>3) - matches sim's render_metallic_core exactly.
          lfsr <= lfsr(14 downto 0) & (lfsr(15) xor lfsr(13) xor lfsr(12) xor lfsr(10));
          noise_raw := signed(resize(unsigned(lfsr(14 downto 0)), 16)) - to_signed(16384, 16);
          noise_scaled := resize(shift_right(resize(noise_raw, 18), 3), 18);
          raw := raw + noise_scaled;

          -- 4-stage HP cascade (shifts 1,2,2,2). Uses new_hp variables for
          -- immediate-update semantics matching sim (see hihat.vhd comment
          -- for why reading the signal directly here was a critical bug).
          new_hp0 := hp_acc0 + shift_right(raw - hp_acc0, 1);
          x0 := raw - new_hp0;
          hp_acc0 <= new_hp0;
          new_hp1 := hp_acc1 + shift_right(x0 - hp_acc1, 2);
          x1 := x0 - new_hp1;
          hp_acc1 <= new_hp1;
          new_hp2 := hp_acc2 + shift_right(x1 - hp_acc2, 2);
          x2 := x1 - new_hp2;
          hp_acc2 <= new_hp2;
          new_hp3 := hp_acc3 + shift_right(x2 - hp_acc3, 2);
          x3 := x2 - new_hp3;
          hp_acc3 <= new_hp3;
          bp := x3;

          -- LP rolloff stage (shift=2)
          new_lp := lp_out_acc + shift_right(bp - lp_out_acc, 2);
          bp := new_lp;
          lp_out_acc <= new_lp;

          -- Gain compensation (x15 = x1+x2+x4+x8) for the filter's reduced
          -- level. Shift-and-add instead of a multiply to save a MULT18X18.
          bp_gained := resize(bp, 24) + shift_left(resize(bp, 24), 1) +
                       shift_left(resize(bp, 24), 2) + shift_left(resize(bp, 24), 3);
          if bp_gained > 32767 then bp_clamped := to_signed(32767, 16);
          elsif bp_gained < -32768 then bp_clamped := to_signed(-32768, 16);
          else bp_clamped := bp_gained(15 downto 0);
          end if;

          -- Multiply by amplitude (top 11 bits of the 20-bit amp)
          product := bp_clamped * signed('0' & amp(19 downto 9));
          audio_out <= product(26 downto 11);

          -- Exponential decay with variable K, linear tail
          case decay_k is
            when 11 =>
              if amp(19 downto 11) = "000000000" then amp <= amp - 1;
              else amp <= amp - ("000000000" & amp(19 downto 11)); end if;
            when 12 =>
              if amp(19 downto 12) = "00000000" then amp <= amp - 1;
              else amp <= amp - ("00000000" & amp(19 downto 12)); end if;
            when 13 =>
              if amp(19 downto 13) = "0000000" then amp <= amp - 1;
              else amp <= amp - ("0000000" & amp(19 downto 13)); end if;
            when others => -- 14
              if amp(19 downto 14) = "000000" then amp <= amp - 1;
              else amp <= amp - ("000000" & amp(19 downto 14)); end if;
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
