library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

-- Snare: two bridged-T oscillators (180Hz + 330Hz) + bandpass filtered noise

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
  signal phase1   : unsigned(19 downto 0) := (others => '0');
  signal phase2   : unsigned(19 downto 0) := (others => '0');
  signal lfsr     : std_logic_vector(15 downto 0) := x"ACE1";
  signal tone_amp : unsigned(13 downto 0) := (others => '0');
  signal noise_amp: unsigned(13 downto 0) := (others => '0');
  signal active   : std_logic := '0';
  -- Bandpass state for noise
  signal bp_state : signed(15 downto 0) := (others => '0');
  signal bp_out   : signed(15 downto 0) := (others => '0');

  -- 180 Hz: inc = 3866, 330 Hz: inc = 7087 @ 48828 Hz
  constant INC1 : unsigned(19 downto 0) := to_unsigned(3866, 20);
  constant INC2 : unsigned(19 downto 0) := to_unsigned(7087, 20);
begin
  process(clk)
    variable t1, t2 : signed(11 downto 0);
    variable noise_raw : signed(11 downto 0);
    variable tone_mix : signed(12 downto 0);
    variable noise_filt : signed(11 downto 0);
    variable mix : signed(12 downto 0);
    variable scaled_t, scaled_n : signed(25 downto 0);
  begin
    if rising_edge(clk) then
      if rst = '1' then
        phase1 <= (others => '0'); phase2 <= (others => '0');
        lfsr <= x"ACE1";
        tone_amp <= (others => '0'); noise_amp <= (others => '0');
        active <= '0';
        bp_state <= (others => '0'); bp_out <= (others => '0');
        audio_out <= (others => '0');
      else
        if trigger = '1' then
          active <= '1';
          phase1 <= (others => '0'); phase2 <= (others => '0');
          tone_amp  <= to_unsigned(16383, 14);
          noise_amp <= to_unsigned(14000, 14);
        end if;

        if sample_tick = '1' and active = '1' then
          phase1 <= phase1 + INC1;
          phase2 <= phase2 + INC2;
          lfsr <= lfsr(14 downto 0) & (lfsr(15) xor lfsr(13) xor lfsr(12) xor lfsr(10));

          -- Two sine-ish tones (triangle approx from phase)
          -- Tone 1: 180 Hz
          if phase1(19) = '0' then
            t1 := signed('0' & phase1(18 downto 8)) - 1024;
          else
            t1 := 1024 - signed('0' & phase1(18 downto 8));
          end if;
          -- Tone 2: 330 Hz
          if phase2(19) = '0' then
            t2 := signed('0' & phase2(18 downto 8)) - 1024;
          else
            t2 := 1024 - signed('0' & phase2(18 downto 8));
          end if;

          -- Mix tones
          tone_mix := resize(t1, 13) + resize(t2, 13);

          -- Bandpass filter on noise (~5kHz center)
          -- Simple 1-pole BP: bp += alpha*(input - bp)
          -- alpha ~= 0.25 for ~5kHz at 48.8kHz
          noise_raw := signed(lfsr(11 downto 0));
          bp_state <= bp_state + shift_right(resize(noise_raw, 16) - bp_state, 2);
          bp_out <= bp_state - shift_right(bp_state, 2);
          noise_filt := bp_out(15 downto 4);

          -- Apply envelopes
          scaled_t := tone_mix(11 downto 0) * signed('0' & tone_amp(13 downto 1));
          scaled_n := noise_filt * signed('0' & noise_amp(13 downto 1));

          mix := resize(scaled_t(24 downto 13), 13) + resize(scaled_n(24 downto 13), 13);

          if mix > 2047 then audio_out <= to_signed(2047, 12);
          elsif mix < -2048 then audio_out <= to_signed(-2048, 12);
          else audio_out <= mix(11 downto 0);
          end if;

          -- Tone decay: fast ~50ms (shift ~11)
          tone_amp <= tone_amp - ("00000000000" & tone_amp(13 downto 11));
          -- Noise decay: ~100ms (shift ~12)
          noise_amp <= noise_amp - ("000000000000" & noise_amp(13 downto 12));

          if tone_amp < 16 and noise_amp < 16 then
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
