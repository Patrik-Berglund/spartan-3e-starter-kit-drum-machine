library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

-- Rim Shot: Square wave at 455Hz, very fast decay (10ms).

entity rimshot is
  port (
    clk         : in  std_logic;
    rst         : in  std_logic;
    sample_tick : in  std_logic;
    trigger     : in  std_logic;
    audio_out   : out signed(11 downto 0)
  );
end entity rimshot;

architecture rtl of rimshot is
  signal phase : unsigned(15 downto 0) := (others => '0');
  signal amp   : unsigned(11 downto 0) := (others => '0');
  signal active: std_logic := '0';
begin
  process(clk)
  begin
    if rising_edge(clk) then
      if rst = '1' then
        phase <= (others => '0'); amp <= (others => '0');
        active <= '0'; audio_out <= (others => '0');
      else
        if trigger = '1' then
          active <= '1';
          phase <= (others => '0');
          amp <= to_unsigned(2047, 12);
        end if;

        if sample_tick = '1' and active = '1' then
          phase <= phase + to_unsigned(610, 16);  -- 455Hz

          -- Square wave ±amp
          if phase(15) = '1' then
            audio_out <= signed(resize(amp, 12));
          else
            audio_out <= -signed(resize(amp, 12));
          end if;

          -- Very fast decay: 10ms = 488 samples. Subtract 4 per sample.
          if amp > 4 then
            amp <= amp - 4;
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
