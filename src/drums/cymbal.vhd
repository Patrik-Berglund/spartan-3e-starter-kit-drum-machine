library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

-- Cymbal: 6 free-running square oscillators + HPF. Decay 800ms.

entity cymbal is
  port (
    clk         : in  std_logic;
    rst         : in  std_logic;
    sample_tick : in  std_logic;
    trigger     : in  std_logic;
    audio_out   : out signed(11 downto 0)
  );
end entity cymbal;

architecture rtl of cymbal is
  signal p0, p1, p2, p3, p4, p5 : unsigned(15 downto 0) := (others => '0');
  signal amp    : unsigned(11 downto 0) := (others => '0');
  signal active : std_logic := '0';
  signal prev   : signed(11 downto 0) := (others => '0');
  signal div    : unsigned(4 downto 0) := (others => '0');
begin
  process(clk)
    variable sq : signed(3 downto 0);
    variable raw, hp : signed(11 downto 0);
  begin
    if rising_edge(clk) then
      if rst = '1' then
        p0 <= (others => '0'); p1 <= (others => '0');
        p2 <= (others => '0'); p3 <= (others => '0');
        p4 <= (others => '0'); p5 <= (others => '0');
        amp <= (others => '0'); active <= '0';
        prev <= (others => '0'); div <= (others => '0');
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
          amp <= to_unsigned(2047, 12);
          div <= (others => '0');
        end if;

        if sample_tick = '1' and active = '1' then
          sq := to_signed(0, 4);
          if p0(15) = '1' then sq := sq + 1; else sq := sq - 1; end if;
          if p1(15) = '1' then sq := sq + 1; else sq := sq - 1; end if;
          if p2(15) = '1' then sq := sq + 1; else sq := sq - 1; end if;
          if p3(15) = '1' then sq := sq + 1; else sq := sq - 1; end if;
          if p4(15) = '1' then sq := sq + 1; else sq := sq - 1; end if;
          if p5(15) = '1' then sq := sq + 1; else sq := sq - 1; end if;

          raw := resize(sq, 12) * signed('0' & amp(11 downto 3));
          hp := raw - prev;
          prev <= raw;
          audio_out <= hp;

          -- Decay: 800ms = subtract 1 every 19 samples
          div <= div + 1;
          if div = 18 then
            div <= (others => '0');
            if amp > 0 then
              amp <= amp - 1;
            else
              active <= '0';
              audio_out <= (others => '0');
            end if;
          end if;
        elsif active = '0' then
          audio_out <= (others => '0');
        end if;
      end if;
    end if;
  end process;
end architecture rtl;
