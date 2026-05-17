library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

-- Bass Drum: Phase accumulator square wave at 56Hz with pitch sweep from 112Hz.
-- Linear amplitude decay over 500ms. Full-scale output.

entity kick_drum is
  port (
    clk         : in  std_logic;
    rst         : in  std_logic;
    sample_tick : in  std_logic;
    trigger     : in  std_logic;
    audio_out   : out signed(11 downto 0)
  );
end entity kick_drum;

architecture rtl of kick_drum is
  signal phase  : unsigned(15 downto 0) := (others => '0');
  signal freq   : unsigned(15 downto 0) := (others => '0');
  signal amp    : unsigned(11 downto 0) := (others => '0');
  signal active : std_logic := '0';
  signal div    : unsigned(3 downto 0) := (others => '0');
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
          freq  <= to_unsigned(150, 16);  -- start at 112Hz
          amp   <= to_unsigned(2047, 12); -- full scale
          div   <= (others => '0');
        end if;

        if sample_tick = '1' and active = '1' then
          phase <= phase + freq;

          -- Pitch sweep: 112Hz -> 56Hz over ~30ms (1465 samples)
          -- Decrement by 1 every 20 samples: (150-75)/1465*20 ≈ 1
          div <= div + 1;
          if div = 0 and freq > 75 then
            freq <= freq - 1;
          end if;

          -- Square wave output scaled by amplitude
          if phase(15) = '1' then
            audio_out <= signed(resize(amp, 12));
          else
            audio_out <= -signed(resize(amp, 12));
          end if;

          -- Linear decay: subtract 1 every 12 samples = 502ms total
          if div(3 downto 0) = "1011" then
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
