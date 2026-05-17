library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

-- Tom: Square wave oscillator with slight pitch dive. Decay ~100ms.

entity tom is
  generic (
    G_FREQ : unsigned(15 downto 0) := to_unsigned(221, 16)  -- LT=221, MT=181, HT=295
  );
  port (
    clk         : in  std_logic;
    rst         : in  std_logic;
    sample_tick : in  std_logic;
    trigger     : in  std_logic;
    audio_out   : out signed(11 downto 0)
  );
end entity tom;

architecture rtl of tom is
  signal phase  : unsigned(15 downto 0) := (others => '0');
  signal freq   : unsigned(15 downto 0) := (others => '0');
  signal amp    : unsigned(11 downto 0) := (others => '0');
  signal active : std_logic := '0';
  signal div    : unsigned(0 downto 0) := (others => '0');
begin
  process(clk)
  begin
    if rising_edge(clk) then
      if rst = '1' then
        phase <= (others => '0'); freq <= (others => '0');
        amp <= (others => '0'); active <= '0'; div <= (others => '0');
        audio_out <= (others => '0');
      else
        if trigger = '1' then
          active <= '1';
          phase <= (others => '0');
          -- Start 20% higher for pitch dive
          freq <= G_FREQ + ("00" & G_FREQ(15 downto 2));
          amp <= to_unsigned(2047, 12);
          div <= (others => '0');
        end if;

        if sample_tick = '1' and active = '1' then
          phase <= phase + freq;

          -- Pitch dive back to base over ~10ms (488 samples)
          if freq > G_FREQ then
            freq <= freq - 1;
          end if;

          -- Square wave ±amp
          if phase(15) = '1' then
            audio_out <= signed(resize(amp, 12));
          else
            audio_out <= -signed(resize(amp, 12));
          end if;

          -- Decay: 100ms = subtract 1 every 2 samples
          div <= div + 1;
          if div = "1" then
            if amp > 0 then
              amp <= amp - 1;
            else
              active <= '0';
            end if;
          end if;
        elsif active = '0' then
          audio_out <= (others => '0');
        end if;
      end if;
    end if;
  end process;
end architecture rtl;
