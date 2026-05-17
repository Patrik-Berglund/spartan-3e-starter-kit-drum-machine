library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

-- Hand clap: bandpass filtered noise with 4 short bursts then decay

entity clap is
  port (
    clk         : in  std_logic;
    rst         : in  std_logic;
    sample_tick : in  std_logic;
    trigger     : in  std_logic;
    audio_out   : out signed(11 downto 0)
  );
end entity clap;

architecture rtl of clap is
  signal lfsr     : std_logic_vector(15 downto 0) := x"BEEF";
  signal amp      : unsigned(13 downto 0) := (others => '0');
  signal active   : std_logic := '0';
  signal count    : unsigned(11 downto 0) := (others => '0');
  -- Burst timing: 4 bursts of ~250 samples (5ms) with ~730 sample gaps (15ms)
  signal burst_phase : unsigned(1 downto 0) := (others => '0');  -- 0-3 = bursts
  signal in_burst : std_logic := '0';
  signal burst_done : std_logic := '0';
  -- Bandpass state
  signal bp_state : signed(15 downto 0) := (others => '0');
begin
  process(clk)
    variable noise_raw : signed(11 downto 0);
    variable filtered  : signed(11 downto 0);
    variable scaled    : signed(25 downto 0);
    variable sub_count : unsigned(9 downto 0);
  begin
    if rising_edge(clk) then
      if rst = '1' then
        lfsr <= x"BEEF"; amp <= (others => '0');
        active <= '0'; count <= (others => '0');
        burst_phase <= (others => '0');
        in_burst <= '0'; burst_done <= '0';
        bp_state <= (others => '0');
        audio_out <= (others => '0');
      else
        if trigger = '1' then
          active <= '1';
          amp <= to_unsigned(16383, 14);
          count <= (others => '0');
          burst_phase <= (others => '0');
          in_burst <= '1';
          burst_done <= '0';
        end if;

        if sample_tick = '1' and active = '1' then
          lfsr <= lfsr(14 downto 0) & (lfsr(15) xor lfsr(13) xor lfsr(11) xor lfsr(0));
          count <= count + 1;

          -- Burst timing: each cycle is 980 samples (~20ms)
          -- First 250 samples = burst on, next 730 = gap
          sub_count := count(9 downto 0);
          if burst_done = '0' then
            if sub_count < 250 then
              in_burst <= '1';
            else
              in_burst <= '0';
              if sub_count = 979 then
                count <= (others => '0');
                if burst_phase = 3 then
                  burst_done <= '1';
                  in_burst <= '1';  -- sustained tail
                else
                  burst_phase <= burst_phase + 1;
                end if;
              end if;
            end if;
          else
            in_burst <= '1';  -- sustained decay after bursts
          end if;

          -- Bandpass filter on noise (~1kHz)
          noise_raw := signed(lfsr(11 downto 0));
          bp_state <= bp_state + shift_right(resize(noise_raw, 16) - bp_state, 3);
          filtered := bp_state(15 downto 4);

          -- Apply envelope
          if in_burst = '1' then
            scaled := filtered * signed('0' & amp(13 downto 1));
            audio_out <= scaled(24 downto 13);
          else
            audio_out <= (others => '0');
          end if;

          -- Decay (only during sustained tail)
          if burst_done = '1' then
            amp <= amp - ("000000000000" & amp(13 downto 12));
            if amp < 16 then
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
