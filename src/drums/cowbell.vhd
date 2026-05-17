library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

-- Cowbell: 2 free-running square waves (540Hz + 800Hz) + HPF. Decay 50ms.

entity cowbell is
  port (
    clk         : in  std_logic;
    rst         : in  std_logic;
    sample_tick : in  std_logic;
    trigger     : in  std_logic;
    audio_out   : out signed(11 downto 0)
  );
end entity cowbell;

architecture rtl of cowbell is
  signal p0, p1 : unsigned(15 downto 0) := (others => '0');
  signal amp    : unsigned(11 downto 0) := (others => '0');
  signal active : std_logic := '0';
  signal prev   : signed(11 downto 0) := (others => '0');
begin
  process(clk)
    variable sq : signed(2 downto 0);
    variable raw, hp : signed(11 downto 0);
  begin
    if rising_edge(clk) then
      if rst = '1' then
        p0 <= (others => '0'); p1 <= (others => '0');
        amp <= (others => '0'); active <= '0';
        prev <= (others => '0'); audio_out <= (others => '0');
      else
        if sample_tick = '1' then
          p0 <= p0 + to_unsigned(725, 16);   -- 540Hz
          p1 <= p1 + to_unsigned(1074, 16);  -- 800Hz
        end if;

        if trigger = '1' then
          active <= '1';
          amp <= to_unsigned(2047, 12);
        end if;

        if sample_tick = '1' and active = '1' then
          sq := to_signed(0, 3);
          if p0(15) = '1' then sq := sq + 1; else sq := sq - 1; end if;
          if p1(15) = '1' then sq := sq + 1; else sq := sq - 1; end if;

          -- Scale: sq is -2..+2, scale to ±amp/2
          raw := resize(sq, 12) * signed("00" & amp(11 downto 2));
          -- 3-bit * 10-bit = fine

          -- HPF
          hp := raw - prev;
          prev <= raw;
          audio_out <= hp;

          -- Decay: 50ms = subtract 1 per sample
          if amp > 0 then
            amp <= amp - 1;
          else
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
