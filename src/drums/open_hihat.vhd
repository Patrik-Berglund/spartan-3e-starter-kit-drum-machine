library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity open_hihat is
  port (
    clk         : in  std_logic;
    rst         : in  std_logic;
    sample_tick : in  std_logic;
    trigger     : in  std_logic;
    audio_out   : out signed(11 downto 0)
  );
end entity open_hihat;

architecture rtl of open_hihat is
  signal lfsr      : std_logic_vector(15 downto 0) := x"5678";
  signal amplitude : unsigned(11 downto 0) := (others => '0');
  signal active    : std_logic := '0';
  signal prev_samp : signed(11 downto 0) := (others => '0');
  signal tick_cnt  : unsigned(3 downto 0) := (others => '0');
begin
  process(clk)
    variable noise_raw : signed(11 downto 0);
    variable hp_out    : signed(12 downto 0);
    variable scaled    : signed(23 downto 0);
  begin
    if rising_edge(clk) then
      if rst = '1' then
        lfsr <= x"5678";
        amplitude <= (others => '0');
        active <= '0';
        audio_out <= (others => '0');
        prev_samp <= (others => '0');
      else
        if trigger = '1' then
          active <= '1';
          amplitude <= to_unsigned(3000, 12);
          tick_cnt <= (others => '0');
        end if;

        if sample_tick = '1' and active = '1' then
          lfsr <= lfsr(14 downto 0) & (lfsr(15) xor lfsr(14) xor lfsr(11) xor lfsr(2));
          tick_cnt <= tick_cnt + 1;

          noise_raw := signed(lfsr(11 downto 0));
          -- High-pass
          hp_out := resize(noise_raw, 13) - resize(prev_samp, 13);
          prev_samp <= noise_raw;
          if hp_out > 2047 then noise_raw := to_signed(2047, 12);
          elsif hp_out < -2048 then noise_raw := to_signed(-2048, 12);
          else noise_raw := hp_out(11 downto 0);
          end if;

          scaled := noise_raw * signed('0' & amplitude);
          audio_out <= scaled(23 downto 12);

          -- Slow decay (every 8 samples) - longer than closed hat
          if tick_cnt(2 downto 0) = "111" then
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
