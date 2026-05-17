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
  signal lfsr      : std_logic_vector(15 downto 0) := x"1234";
  signal amplitude : unsigned(11 downto 0) := (others => '0');
  signal active    : std_logic := '0';
  signal prev_samp : signed(11 downto 0) := (others => '0');
begin

  process(clk)
    variable noise_raw : signed(11 downto 0);
    variable hp_out    : signed(12 downto 0);
    variable scaled    : signed(23 downto 0);
  begin
    if rising_edge(clk) then
      if rst = '1' then
        lfsr      <= x"1234";
        amplitude <= (others => '0');
        active    <= '0';
        audio_out <= (others => '0');
        prev_samp <= (others => '0');
      else
        if trigger = '1' then
          active    <= '1';
          amplitude <= to_unsigned(3000, 12);
        end if;

        if sample_tick = '1' and active = '1' then
          -- LFSR advance (different taps from snare for variety)
          lfsr <= lfsr(14 downto 0) & (lfsr(15) xor lfsr(14) xor lfsr(12) xor lfsr(3));

          -- Raw noise
          noise_raw := signed(lfsr(11 downto 0));

          -- Simple high-pass: output = current - previous (emphasizes high freq)
          hp_out := resize(noise_raw, 13) - resize(prev_samp, 13);
          prev_samp <= noise_raw;

          -- Clamp hp_out to 12 bits
          if hp_out > 2047 then
            noise_raw := to_signed(2047, 12);
          elsif hp_out < -2048 then
            noise_raw := to_signed(-2048, 12);
          else
            noise_raw := hp_out(11 downto 0);
          end if;

          -- Scale by amplitude
          scaled := noise_raw * signed('0' & amplitude);
          audio_out <= scaled(23 downto 12);

          -- Very fast decay
          amplitude <= amplitude - ("00" & amplitude(11 downto 2));
          if amplitude < 8 then
            active <= '0';
            amplitude <= (others => '0');
            audio_out <= (others => '0');
          end if;
        elsif active = '0' then
          audio_out <= (others => '0');
        end if;
      end if;
    end if;
  end process;

end architecture rtl;
