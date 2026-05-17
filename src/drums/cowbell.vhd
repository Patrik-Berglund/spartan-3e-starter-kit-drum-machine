library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

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
  signal phase1    : unsigned(15 downto 0) := (others => '0');
  signal phase2    : unsigned(15 downto 0) := (others => '0');
  signal amplitude : unsigned(11 downto 0) := (others => '0');
  signal active    : std_logic := '0';
begin
  process(clk)
    variable sq1, sq2 : signed(11 downto 0);
    variable mix : signed(12 downto 0);
    variable scaled : signed(23 downto 0);
  begin
    if rising_edge(clk) then
      if rst = '1' then
        phase1 <= (others => '0');
        phase2 <= (others => '0');
        amplitude <= (others => '0');
        active <= '0';
        audio_out <= (others => '0');
      else
        if trigger = '1' then
          active <= '1';
          phase1 <= (others => '0');
          phase2 <= (others => '0');
          amplitude <= to_unsigned(3500, 12);
        end if;

        if sample_tick = '1' and active = '1' then
          -- Two square waves at ~587Hz and ~845Hz (non-harmonic = metallic)
          phase1 <= phase1 + to_unsigned(2510, 16);
          phase2 <= phase2 + to_unsigned(3614, 16);

          -- Square waves
          if phase1(15) = '1' then sq1 := to_signed(1024, 12);
          else sq1 := to_signed(-1024, 12); end if;
          if phase2(15) = '1' then sq2 := to_signed(1024, 12);
          else sq2 := to_signed(-1024, 12); end if;

          mix := resize(sq1, 13) + resize(sq2, 13);

          scaled := mix(11 downto 0) * signed('0' & amplitude);
          audio_out <= scaled(23 downto 12);

          -- Medium-fast decay
          amplitude <= amplitude - ("000" & amplitude(11 downto 3));
          if amplitude < 8 then
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
