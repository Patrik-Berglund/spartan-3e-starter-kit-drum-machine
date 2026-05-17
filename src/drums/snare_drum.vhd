library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

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
  -- LFSR for noise
  signal lfsr      : std_logic_vector(15 downto 0) := x"ACE1";
  -- Tone component (phase accumulator)
  signal phase     : unsigned(15 downto 0) := (others => '0');
  signal amplitude : unsigned(11 downto 0) := (others => '0');
  signal tone_amp  : unsigned(11 downto 0) := (others => '0');
  signal active    : std_logic := '0';
  signal tick_cnt  : unsigned(9 downto 0) := (others => '0');
begin

  process(clk)
    variable noise_val : signed(11 downto 0);
    variable tone_val  : signed(11 downto 0);
    variable mix       : signed(12 downto 0);
    variable scaled    : signed(23 downto 0);
  begin
    if rising_edge(clk) then
      if rst = '1' then
        phase     <= (others => '0');
        amplitude <= (others => '0');
        tone_amp  <= (others => '0');
        active    <= '0';
        audio_out <= (others => '0');
        lfsr      <= x"ACE1";
        tick_cnt  <= (others => '0');
      else
        if trigger = '1' then
          active    <= '1';
          amplitude <= to_unsigned(4095, 12);
          tone_amp  <= to_unsigned(4095, 12);
          phase     <= (others => '0');
          tick_cnt  <= (others => '0');
        end if;

        if sample_tick = '1' and active = '1' then
          -- LFSR advance (Galois, taps at 16,14,13,11)
          lfsr <= lfsr(14 downto 0) & (lfsr(15) xor lfsr(13) xor lfsr(12) xor lfsr(10));

          -- Tone: ~200 Hz body
          phase <= phase + to_unsigned(840, 16);

          tick_cnt <= tick_cnt + 1;

          -- Noise amplitude decay (fast)
          if tick_cnt(2 downto 0) = "111" then
            amplitude <= amplitude - ("000" & amplitude(11 downto 3));
          end if;

          -- Tone decay (faster)
          if tick_cnt(1 downto 0) = "11" then
            tone_amp <= tone_amp - ("00" & tone_amp(11 downto 2));
          end if;

          if amplitude < 8 then
            active <= '0';
            amplitude <= (others => '0');
          end if;

          -- Noise: LFSR top bits as signed
          noise_val := signed(lfsr(11 downto 0));
          -- Scale noise by amplitude
          scaled := noise_val * signed('0' & amplitude);
          noise_val := scaled(23 downto 12);

          -- Tone: triangle from phase
          if phase(15) = '0' then
            tone_val := signed('0' & phase(14 downto 4)) - 1024;
          else
            tone_val := 1024 - signed('0' & phase(14 downto 4));
          end if;
          -- Scale tone
          scaled := tone_val * signed('0' & tone_amp);
          tone_val := scaled(23 downto 12);

          -- Mix: noise dominant, tone adds body
          mix := resize(noise_val, 13) + resize(shift_right(tone_val, 1), 13);
          -- Saturate to 12 bits
          if mix > 2047 then
            audio_out <= to_signed(2047, 12);
          elsif mix < -2048 then
            audio_out <= to_signed(-2048, 12);
          else
            audio_out <= mix(11 downto 0);
          end if;
        elsif active = '0' then
          audio_out <= (others => '0');
        end if;
      end if;
    end if;
  end process;

end architecture rtl;
