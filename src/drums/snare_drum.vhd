library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

-- Snare: Two square waves (238Hz + 476Hz) + noise. Linear decay ~60ms.

entity snare_drum is
  port (
    clk         : in  std_logic;
    rst         : in  std_logic;
    sample_tick : in  std_logic;
    trigger     : in  std_logic;
    audio_out   : out signed(11 downto 0)
  );
end entity snare_drum;

architecture rtl of snare_drum is
  signal phase1 : unsigned(15 downto 0) := (others => '0');
  signal phase2 : unsigned(15 downto 0) := (others => '0');
  signal lfsr   : std_logic_vector(15 downto 0) := x"ACE1";
  signal amp    : unsigned(11 downto 0) := (others => '0');
  signal active : std_logic := '0';
begin
  process(clk)
    variable tone1, tone2 : signed(11 downto 0);
    variable noise : signed(11 downto 0);
    variable mix : signed(12 downto 0);
  begin
    if rising_edge(clk) then
      if rst = '1' then
        phase1 <= (others => '0'); phase2 <= (others => '0');
        lfsr <= x"ACE1"; amp <= (others => '0');
        active <= '0'; audio_out <= (others => '0');
      else
        if trigger = '1' then
          active <= '1';
          phase1 <= (others => '0'); phase2 <= (others => '0');
          amp <= to_unsigned(2047, 12);
        end if;

        if sample_tick = '1' and active = '1' then
          phase1 <= phase1 + to_unsigned(319, 16);  -- 238Hz
          phase2 <= phase2 + to_unsigned(638, 16);  -- 476Hz
          lfsr <= lfsr(14 downto 0) & (lfsr(15) xor lfsr(13) xor lfsr(12) xor lfsr(10));

          -- Tones: ±amp/4 each
          if phase1(15) = '1' then tone1 := signed("00" & amp(11 downto 2));
          else tone1 := -signed("00" & amp(11 downto 2)); end if;
          if phase2(15) = '1' then tone2 := signed("000" & amp(11 downto 3));
          else tone2 := -signed("000" & amp(11 downto 3)); end if;

          -- Noise: ±amp/2 (dominant)
          if lfsr(15) = '1' then noise := signed('0' & amp(11 downto 1));
          else noise := -signed('0' & amp(11 downto 1)); end if;

          -- Mix
          mix := resize(tone1, 13) + resize(tone2, 13) + resize(noise, 13);
          if mix > 2047 then audio_out <= to_signed(2047, 12);
          elsif mix < -2048 then audio_out <= to_signed(-2048, 12);
          else audio_out <= mix(11 downto 0); end if;

          -- Decay: 60ms = 2930 samples. Subtract 1 per sample = 42ms. Close enough.
          if amp > 0 then
            amp <= amp - 1;
          else
            active <= '0';
          end if;
        elsif active = '0' then
          audio_out <= (others => '0');
        end if;
      end if;
    end if;
  end process;
end architecture rtl;
