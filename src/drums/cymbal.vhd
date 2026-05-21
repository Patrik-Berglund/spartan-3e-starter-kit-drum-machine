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
  signal amp     : unsigned(15 downto 0) := (others => '0');
  signal active  : std_logic := '0';
  -- BPF: 1-stage LP + 4-stage HP
  signal lp_acc : signed(15 downto 0) := (others => '0');
  signal hp_acc0, hp_acc1, hp_acc2, hp_acc3 : signed(15 downto 0) := (others => '0');

  -- TONE: LP shift 2 (darker) or 1 (brighter)
  signal lp_shift : integer range 1 to 2;
  -- DECAY: K value 11-15. decay=0->11(short), decay=255->15(long)
  signal decay_k : integer range 11 to 15;
begin
  -- Map tone 0-255 to lp_shift: low tone = 2 (darker), high tone = 1 (brighter)
  lp_shift <= 2 when tone < 86 else 1;

  -- Map decay 0-255 to K 11..15
  decay_k <= 11 when decay < 52 else
             12 when decay < 103 else
             13 when decay < 154 else
             14 when decay < 205 else
             15;

  process(clk)
    variable sq : signed(4 downto 0);
    variable raw : signed(15 downto 0);
    variable lp_out : signed(15 downto 0);
    variable x0, x1, x2, x3 : signed(15 downto 0);
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
          active <= '1'; amp <= to_unsigned(65535, 16);
        end if;

        if sample_tick = '1' and active = '1' then
          sq := to_signed(0, 5);
          if p0(15) = '1' then sq := sq + 1; else sq := sq - 1; end if;
          if p1(15) = '1' then sq := sq + 1; else sq := sq - 1; end if;
          if p2(15) = '1' then sq := sq + 1; else sq := sq - 1; end if;
          if p3(15) = '1' then sq := sq + 1; else sq := sq - 1; end if;
          if p4(15) = '1' then sq := sq + 1; else sq := sq - 1; end if;
          if p5(15) = '1' then sq := sq + 1; else sq := sq - 1; end if;

          raw := shift_left(resize(sq, 16), 12) + shift_left(resize(sq, 16), 10) +
                 shift_left(resize(sq, 16), 8) + shift_left(resize(sq, 16), 6);

          -- BPF: 1-stage LP (variable shift) + 4-stage HP (shift=4)
          case lp_shift is
            when 2 => lp_acc <= lp_acc + shift_right(raw - lp_acc, 2);
            when others => lp_acc <= lp_acc + shift_right(raw - lp_acc, 1);
          end case;
          lp_out := lp_acc;
          hp_acc0 <= hp_acc0 + shift_right(lp_out - hp_acc0, 4);
          x0 := lp_out - hp_acc0;
          hp_acc1 <= hp_acc1 + shift_right(x0 - hp_acc1, 4);
          x1 := x0 - hp_acc1;
          hp_acc2 <= hp_acc2 + shift_right(x1 - hp_acc2, 4);
          x2 := x1 - hp_acc2;
          hp_acc3 <= hp_acc3 + shift_right(x2 - hp_acc3, 4);
          x3 := x2 - hp_acc3;

          product := x3 * signed('0' & amp(15 downto 5));
          audio_out <= product(26 downto 11);

          -- Exponential decay with variable K
          case decay_k is
            when 11 => amp <= amp - ("00000000000" & amp(15 downto 11));
            when 12 => amp <= amp - ("000000000000" & amp(15 downto 12));
            when 13 => amp <= amp - ("0000000000000" & amp(15 downto 13));
            when 14 => amp <= amp - ("00000000000000" & amp(15 downto 14));
            when others => amp <= amp - ("000000000000000" & amp(15 downto 15));
          end case;

          if amp < 512 then
            active <= '0'; audio_out <= (others => '0');
          end if;
        elsif active = '0' then
          audio_out <= (others => '0');
        end if;
      end if;
    end if;
  end process;
end architecture rtl;
