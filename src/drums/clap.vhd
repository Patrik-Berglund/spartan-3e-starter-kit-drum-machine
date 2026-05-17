library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

-- Hand Clap: Noise with 3 bursts (5ms on, 15ms gap) then decay tail.

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
  signal lfsr   : std_logic_vector(15 downto 0) := x"BEEF";
  signal amp    : unsigned(11 downto 0) := (others => '0');
  signal active : std_logic := '0';
  signal count  : unsigned(13 downto 0) := (others => '0');
begin
  process(clk)
    variable c : integer;
    variable gate : std_logic;
  begin
    if rising_edge(clk) then
      if rst = '1' then
        lfsr <= x"BEEF"; amp <= (others => '0');
        active <= '0'; count <= (others => '0');
        audio_out <= (others => '0');
      else
        if trigger = '1' then
          active <= '1';
          amp <= to_unsigned(2047, 12);
          count <= (others => '0');
        end if;

        if sample_tick = '1' and active = '1' then
          lfsr <= lfsr(14 downto 0) & (lfsr(15) xor lfsr(13) xor lfsr(11) xor lfsr(0));
          count <= count + 1;
          c := to_integer(count);

          -- Burst pattern: 3 bursts of 244 samples (5ms), gaps of 732 (15ms)
          -- Burst 1: 0-243
          -- Gap 1: 244-975
          -- Burst 2: 976-1219
          -- Gap 2: 1220-1951
          -- Burst 3: 1952-2195
          -- Tail: 2196+
          if c < 244 then gate := '1';
          elsif c < 976 then gate := '0';
          elsif c < 1220 then gate := '1';
          elsif c < 1952 then gate := '0';
          elsif c < 2196 then gate := '1';
          else gate := '1';  -- sustained tail
          end if;

          if gate = '1' then
            -- Noise ±amp
            if lfsr(15) = '1' then
              audio_out <= signed(resize(amp, 12));
            else
              audio_out <= -signed(resize(amp, 12));
            end if;
          else
            audio_out <= (others => '0');
          end if;

          -- Decay only during tail
          if c >= 2196 then
            if amp > 0 then
              amp <= amp - 1;
            else
              active <= '0';
            end if;
          end if;
        elsif active = '0' then
          audio_out <= (others => '0');
        end if;
      end if;
    end if;
  end process;
end architecture rtl;
