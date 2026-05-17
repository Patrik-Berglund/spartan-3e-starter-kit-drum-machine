library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity hihat is
  port (
    clk         : in  std_logic;
    rst         : in  std_logic;
    sample_tick : in  std_logic;
    trigger     : in  std_logic;
    audio_out   : out signed(11 downto 0)
  );
end entity hihat;

architecture rtl of hihat is
  signal p0, p1, p2, p3, p4, p5 : unsigned(15 downto 0) := (others => '0');
  signal amp     : unsigned(15 downto 0) := (others => '0');
  signal active  : std_logic := '0';
  -- 4-stage HPF accumulators
  signal hp_acc0, hp_acc1, hp_acc2, hp_acc3 : signed(15 downto 0) := (others => '0');
begin
  process(clk)
    variable sq : signed(3 downto 0);
    variable raw : signed(15 downto 0);
    variable x0, x1, x2, x3 : signed(15 downto 0);
    variable product : signed(23 downto 0);
  begin
    if rising_edge(clk) then
      if rst = '1' then
        p0 <= (others => '0'); p1 <= (others => '0');
        p2 <= (others => '0'); p3 <= (others => '0');
        p4 <= (others => '0'); p5 <= (others => '0');
        amp <= (others => '0'); active <= '0';
        hp_acc0 <= (others => '0'); hp_acc1 <= (others => '0');
        hp_acc2 <= (others => '0'); hp_acc3 <= (others => '0');
        audio_out <= (others => '0');
      else
        if sample_tick = '1' then
          p0 <= p0 + to_unsigned(274, 16);
          p1 <= p1 + to_unsigned(408, 16);
          p2 <= p2 + to_unsigned(496, 16);
          p3 <= p3 + to_unsigned(701, 16);
          p4 <= p4 + to_unsigned(725, 16);
          p5 <= p5 + to_unsigned(1074, 16);
        end if;

        if trigger = '1' then
          active <= '1';
          amp <= to_unsigned(65535, 16);
        end if;

        if sample_tick = '1' and active = '1' then
          sq := to_signed(0, 4);
          if p0(15) = '1' then sq := sq + 1; else sq := sq - 1; end if;
          if p1(15) = '1' then sq := sq + 1; else sq := sq - 1; end if;
          if p2(15) = '1' then sq := sq + 1; else sq := sq - 1; end if;
          if p3(15) = '1' then sq := sq + 1; else sq := sq - 1; end if;
          if p4(15) = '1' then sq := sq + 1; else sq := sq - 1; end if;
          if p5(15) = '1' then sq := sq + 1; else sq := sq - 1; end if;

          -- Scale: sq*170
          raw := shift_left(resize(sq, 16), 7) + shift_left(resize(sq, 16), 5) +
                 shift_left(resize(sq, 16), 3) + shift_left(resize(sq, 16), 1);

          -- 4-stage HPF (24dB/oct)
          hp_acc0 <= hp_acc0 + shift_right(raw - hp_acc0, 3);
          x0 := raw - hp_acc0;
          hp_acc1 <= hp_acc1 + shift_right(x0 - hp_acc1, 3);
          x1 := x0 - hp_acc1;
          hp_acc2 <= hp_acc2 + shift_right(x1 - hp_acc2, 3);
          x2 := x1 - hp_acc2;
          hp_acc3 <= hp_acc3 + shift_right(x2 - hp_acc3, 3);
          x3 := x2 - hp_acc3;

          -- Multiply by amplitude
          product := x3(15 downto 4) * signed('0' & amp(15 downto 5));
          audio_out <= product(22 downto 11);

          -- Exponential decay: K=11 (tau ~42ms)
          amp <= amp - ("00000000000" & amp(15 downto 11));

          if amp < 512 then
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
