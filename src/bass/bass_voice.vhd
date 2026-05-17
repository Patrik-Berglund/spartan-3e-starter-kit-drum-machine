library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

-- Top-level bass voice: oscillator → filter → amplitude envelope.
-- Filter cutoff sweeps down from trigger (envelope mod).

entity bass_voice is
  port (
    clk         : in  std_logic;
    rst         : in  std_logic;
    sample_tick : in  std_logic;
    trigger     : in  std_logic;
    note        : in  unsigned(5 downto 0);
    audio_out   : out signed(11 downto 0)
  );
end entity bass_voice;

architecture rtl of bass_voice is
  signal osc_out    : signed(11 downto 0);
  signal filt_out   : signed(11 downto 0);
  signal gate       : std_logic := '0';
  signal env_cutoff : unsigned(11 downto 0) := (others => '0');
  signal amp_env    : unsigned(11 downto 0) := (others => '0');
  signal tick_cnt   : unsigned(3 downto 0) := (others => '0');
begin

  u_osc : entity work.bass_osc
    port map (
      clk         => clk,
      rst         => rst,
      sample_tick => sample_tick,
      note        => note,
      gate        => gate,
      audio_out   => osc_out
    );

  u_filter : entity work.bass_filter
    port map (
      clk         => clk,
      rst         => rst,
      sample_tick => sample_tick,
      audio_in    => osc_out,
      cutoff      => env_cutoff,
      resonance   => to_unsigned(10, 4),  -- fixed high resonance for acid sound
      audio_out   => filt_out
    );

  process(clk)
    variable scaled : signed(23 downto 0);
  begin
    if rising_edge(clk) then
      if rst = '1' then
        gate       <= '0';
        env_cutoff <= (others => '0');
        amp_env    <= (others => '0');
        audio_out  <= (others => '0');
        tick_cnt   <= (others => '0');
      else
        if trigger = '1' then
          gate       <= '1';
          env_cutoff <= to_unsigned(4000, 12);  -- start open
          amp_env    <= to_unsigned(4095, 12);
          tick_cnt   <= (others => '0');
        end if;

        if sample_tick = '1' and gate = '1' then
          tick_cnt <= tick_cnt + 1;

          -- Filter envelope: decay cutoff (slow, every 16 samples)
          if tick_cnt = "1111" then
            if env_cutoff > 300 then
              env_cutoff <= env_cutoff - ("000" & env_cutoff(11 downto 3));
            end if;
          end if;

          -- Amplitude envelope: slow decay (every 8 samples)
          if tick_cnt(2 downto 0) = "111" then
            amp_env <= amp_env - ("00000" & amp_env(11 downto 5));
            if amp_env < 16 then
              gate    <= '0';
              amp_env <= (others => '0');
            end if;
          end if;

          -- Apply amplitude envelope to filter output
          scaled := filt_out * signed('0' & amp_env);
          audio_out <= scaled(23 downto 12);
        elsif gate = '0' then
          audio_out <= (others => '0');
        end if;
      end if;
    end if;
  end process;

end architecture rtl;
