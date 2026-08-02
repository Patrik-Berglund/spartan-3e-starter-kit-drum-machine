library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

-- 808 Closed Hi-Hat - 6 oscillators through BPF, very short decay.
-- Real 808 measured: centroid ~10991Hz, flatness ~0.10 (tonal, not
-- broadband), decay -20dB at ~26ms, peak amplitude ~18347.
-- No noise source in the real circuit (confirmed via voices2.PNG
-- schematic) - unlike the earlier (buggy) version, this does NOT mix
-- in LFSR noise. hp_stages=3 with shift=2 matches real 808 measurements.

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
  signal amp     : unsigned(19 downto 0) := (others => '0');  -- 20-bit, matches
    -- render_metallic_core in sim and the other metallic voices (CY/OH)
  signal active  : std_logic := '0';
  -- BPF: 1-stage LP (passthrough) + 3-stage HP (shift=2). Widened to
  -- 18-bit (square-oscillator sum alone can reach +-32640, safe headroom
  -- without noise injection, but kept wide for consistency with CY/OH).
  signal lp_acc : signed(17 downto 0) := (others => '0');
  signal hp_acc0, hp_acc1, hp_acc2 : signed(17 downto 0) := (others => '0');
begin
  process(clk)
    variable sq : signed(4 downto 0);
    variable raw : signed(17 downto 0);
    variable lp_out : signed(17 downto 0);
    variable x0, x1, x2 : signed(17 downto 0);
    variable x2_clamped : signed(15 downto 0);
    variable product : signed(27 downto 0);
    variable dec_term : unsigned(19 downto 0);
  begin
    if rising_edge(clk) then
      if rst = '1' then
        p0 <= (others => '0'); p1 <= (others => '0');
        p2 <= (others => '0'); p3 <= (others => '0');
        p4 <= (others => '0'); p5 <= (others => '0');
        amp <= (others => '0'); active <= '0';
        lp_acc <= (others => '0');
        hp_acc0 <= (others => '0'); hp_acc1 <= (others => '0'); hp_acc2 <= (others => '0');
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

          -- BPF: 1-stage LP (passthrough) + 3-stage HP (shift=2)
          lp_acc <= raw;
          lp_out := lp_acc;
          hp_acc0 <= hp_acc0 + shift_right(lp_out - hp_acc0, 2);
          x0 := lp_out - hp_acc0;
          hp_acc1 <= hp_acc1 + shift_right(x0 - hp_acc1, 2);
          x1 := x0 - hp_acc1;
          hp_acc2 <= hp_acc2 + shift_right(x1 - hp_acc2, 2);
          x2 := x1 - hp_acc2;

          -- Clamp back to 16-bit before the amplitude multiply.
          if x2 > 32767 then x2_clamped := to_signed(32767, 16);
          elsif x2 < -32768 then x2_clamped := to_signed(-32768, 16);
          else x2_clamped := x2(15 downto 0);
          end if;

          -- Multiply by amplitude (top 11 bits of the 20-bit amp)
          product := x2_clamped * signed('0' & amp(19 downto 9));
          audio_out <= product(26 downto 11);

          -- Exponential decay: K=9, with linear tail to prevent the
          -- voice getting permanently stuck once amp>>9 rounds to 0
          -- (K=9 floor is 512, well above the amp<8192 threshold below,
          -- so without the linear tail amp would stall active forever).
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
