library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

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
  signal lfsr      : std_logic_vector(15 downto 0) := x"CAFE";
  signal phase1    : unsigned(15 downto 0) := (others => '0');
  signal phase2    : unsigned(15 downto 0) := (others => '0');
  signal amplitude : unsigned(11 downto 0) := (others => '0');
  signal active    : std_logic := '0';
  signal tick_cnt  : unsigned(3 downto 0) := (others => '0');
begin
  process(clk)
    variable noise : signed(11 downto 0);
    variable metal : signed(11 downto 0);
    variable mix   : signed(12 downto 0);
    variable scaled: signed(23 downto 0);
  begin
    if rising_edge(clk) then
      if rst = '1' then
        lfsr <= x"CAFE";
        amplitude <= (others => '0');
        active <= '0';
        audio_out <= (others => '0');
      else
        if trigger = '1' then
          active <= '1';
          amplitude <= to_unsigned(3000, 12);
          tick_cnt <= (others => '0');
        end if;

        if sample_tick = '1' and active = '1' then
          lfsr <= lfsr(14 downto 0) & (lfsr(15) xor lfsr(12) xor lfsr(10) xor lfsr(3));
          phase1 <= phase1 + to_unsigned(4200, 16);
          phase2 <= phase2 + to_unsigned(5731, 16);
          tick_cnt <= tick_cnt + 1;

          -- Mix noise with two square waves for metallic character
          noise := signed(lfsr(11 downto 0));
          if phase1(15) = phase2(15) then
            metal := shift_right(noise, 1);
          else
            metal := noise;
          end if;

          scaled := metal * signed('0' & amplitude);
          audio_out <= scaled(23 downto 12);

          -- Slow decay (every 16 samples)
          if tick_cnt = "1111" then
            amplitude <= amplitude - ("00000" & amplitude(11 downto 5));
            if amplitude < 8 then
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
