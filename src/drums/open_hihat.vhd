library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

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
  signal amp     : unsigned(19 downto 0) := (others => '0');  -- widened from
    -- 16 to 20 bits (same fix as cymbal.vhd) -- sim's shared
    -- render_metallic_core was widened during the CY fix and VHDL must
    -- match exactly. At K=11-14 the old 16-bit floor caused an audible
    -- death-click when the voice cut out early.
  signal active  : std_logic := '0';
  -- BPF: 1-stage LP + 4-stage HP. Widened to 18-bit (see hihat.vhd comment
  -- for rationale -- square-sum + noise can reach +-53118, overflowing a
  -- 16-bit signed accumulator and causing runaway noise buildup).
  signal lp_acc : signed(17 downto 0) := (others => '0');
  signal hp_acc0, hp_acc1, hp_acc2, hp_acc3 : signed(17 downto 0) := (others => '0');

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
          active <= '1'; amp <= to_unsigned(1048575, 20);
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

          -- BPF: 1-stage LP (shift=1) + 4-stage HP (shift=2). No noise
          -- source (removed - real 808 OH is a clean tonal sound,
          -- measured flatness ~0.05, noise made it too broadband/hissy).
          -- LP shift=1 brings centroid down from ~12300Hz to ~9350Hz,
          -- matching real 808 OH measurements.
          lp_acc <= lp_acc + shift_right(raw - lp_acc, 1);
          lp_out := lp_acc;
          hp_acc0 <= hp_acc0 + shift_right(lp_out - hp_acc0, 2);
          x0 := lp_out - hp_acc0;
          hp_acc1 <= hp_acc1 + shift_right(x0 - hp_acc1, 2);
          x1 := x0 - hp_acc1;
          hp_acc2 <= hp_acc2 + shift_right(x1 - hp_acc2, 2);
          x2 := x1 - hp_acc2;
          hp_acc3 <= hp_acc3 + shift_right(x2 - hp_acc3, 2);
          x3 := x2 - hp_acc3;

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
            when 11 =>
              if amp(19 downto 11) = "000000000" then amp <= (others => '0');
              else amp <= amp - ("000000000" & amp(19 downto 11)); end if;
            when 12 =>
              if amp(19 downto 12) = "00000000" then amp <= (others => '0');
              else amp <= amp - ("00000000" & amp(19 downto 12)); end if;
            when 13 =>
              if amp(19 downto 13) = "0000000" then amp <= (others => '0');
              else amp <= amp - ("0000000" & amp(19 downto 13)); end if;
            when others => -- 14
              if amp(19 downto 14) = "000000" then amp <= (others => '0');
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
