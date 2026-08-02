library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

-- 808 Bass Drum - based on service manual bridged-T oscillator analysis.
-- TONE: controls base oscillation frequency (narrow range, ~53-58Hz)
-- DECAY: controls ring time (K=9..14 mapping SHORT=50ms to LONG=800ms)
-- Initial transient click + subtle pitch sweep from ~63Hz to base freq.
-- Uses 24-bit fractional frequency for smooth exponential pitch decay.

entity kick_drum is
  port (
    clk         : in  std_logic;
    rst         : in  std_logic;
    sample_tick : in  std_logic;
    trigger     : in  std_logic;
    tone        : in  unsigned(7 downto 0);
    decay       : in  unsigned(7 downto 0);
    audio_out   : out signed(15 downto 0)
  );
end entity kick_drum;

architecture rtl of kick_drum is
  signal phase      : unsigned(15 downto 0) := (others => '0');
  signal freq_frac  : unsigned(23 downto 0) := (others => '0');
  signal end_frac   : unsigned(23 downto 0) := (others => '0');
  signal amp        : unsigned(15 downto 0) := (others => '0');
  signal active     : std_logic := '0';
  signal sample_cnt : unsigned(1 downto 0) := (others => '0');

  -- Sine table interface
  signal sine_val : signed(11 downto 0);

  -- Param mapping
  signal base_inc : unsigned(7 downto 0);
  signal decay_k  : unsigned(3 downto 0);
begin

  -- TONE -> base_inc: 71 + tone>>5 (range 71..78, giving ~53-58Hz)
  base_inc <= to_unsigned(71, 8) + ("000" & tone(7 downto 5));

  -- End freq (fractional) = base_inc << 8
  end_frac <= resize(base_inc, 16) & x"00";

  -- DECAY mapping to match real 808 measured times
  decay_k <= to_unsigned(10, 4) when decay < 48 else
             to_unsigned(12, 4) when decay < 160 else
             to_unsigned(13, 4);

  -- Shared sine table
  u_sine : entity work.sine_table
    port map (clk => clk, phase => phase, sine_out => sine_val);

  process(clk)
    variable product    : signed(23 downto 0);
    variable diff24     : unsigned(23 downto 0);
    variable step24     : unsigned(23 downto 0);
    variable freq_inc   : unsigned(15 downto 0);
    variable dec_term   : unsigned(15 downto 0);
    variable start_inc  : unsigned(7 downto 0);
  begin
    if rising_edge(clk) then
      if rst = '1' then
        phase <= (others => '0');
        freq_frac <= (others => '0');
        amp <= (others => '0');
        active <= '0';
        sample_cnt <= (others => '0');
        audio_out <= (others => '0');
      else
        if trigger = '1' then
          active <= '1';
          phase <= (others => '0');
          sample_cnt <= (others => '0');
          amp <= to_unsigned(65535, 16);
          -- Start freq = (base_inc + base_inc>>2) << 8
          start_inc := base_inc + ("00" & base_inc(7 downto 2));
          freq_frac <= resize(start_inc, 16) & x"00";
        end if;

        if sample_tick = '1' and active = '1' then

          -- Click transient for first 2 samples
          if sample_cnt < 2 then
            if sample_cnt = 0 then
              audio_out <= to_signed(24000, 16);
            else
              audio_out <= to_signed(-12000, 16);
            end if;
            sample_cnt <= sample_cnt + 1;
          else
            -- Normal sine synthesis: sine * amp(15:5)
            product := sine_val * signed('0' & amp(15 downto 5));
            audio_out <= product(22 downto 7);
          end if;

          -- Phase advance using top bits of freq_frac as increment
          freq_inc := resize(freq_frac(23 downto 8), 16);
          phase <= phase + freq_inc;

          -- Exponential pitch sweep on 24-bit fractional freq (shift=10)
          if freq_frac > end_frac then
            diff24 := freq_frac - end_frac;
            step24 := "0000000000" & diff24(23 downto 10);
            if step24 = 0 then
              freq_frac <= freq_frac - 1;
            else
              freq_frac <= freq_frac - step24;
            end if;
          end if;

          -- Exponential amplitude decay: amp -= amp >> K
          -- When amp >> K = 0, subtract 1 (smooth linear tail)
          case to_integer(decay_k) is
            when 10 =>
              dec_term := "0000000000" & amp(15 downto 10);
              if dec_term = 0 then
                amp <= amp - 1;
              else
                amp <= amp - dec_term;
              end if;
            when 12 =>
              dec_term := "000000000000" & amp(15 downto 12);
              if dec_term = 0 then
                amp <= amp - 1;
              else
                amp <= amp - dec_term;
              end if;
            when others => -- 13
              dec_term := "0000000000000" & amp(15 downto 13);
              if dec_term = 0 then
                amp <= amp - 1;
              else
                amp <= amp - dec_term;
              end if;
          end case;

          if amp < 64 then
            active <= '0';
          end if;
        elsif active = '0' then
          audio_out <= (others => '0');
        end if;
      end if;
    end if;
  end process;
end architecture rtl;
