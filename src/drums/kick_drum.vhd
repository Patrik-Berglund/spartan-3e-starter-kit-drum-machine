library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity kick_drum is
  port (
    clk         : in  std_logic;
    rst         : in  std_logic;
    sample_tick : in  std_logic;
    trigger     : in  std_logic;
    tone        : in  unsigned(7 downto 0);
    decay       : in  unsigned(7 downto 0);
    audio_out   : out signed(11 downto 0)
  );
end entity kick_drum;

architecture rtl of kick_drum is
  signal phase    : unsigned(15 downto 0) := (others => '0');
  signal freq     : unsigned(15 downto 0) := (others => '0');
  signal amp      : unsigned(15 downto 0) := (others => '0');
  signal active   : std_logic := '0';
  signal div      : unsigned(2 downto 0) := (others => '0');

  -- Sine table interface
  signal sine_val : signed(11 downto 0);

  -- Param mapping
  signal start_freq : unsigned(15 downto 0);
  signal decay_k    : unsigned(3 downto 0);
begin

  -- TONE maps 0-255 to phase_inc 96-151
  -- start_freq = 96 + (tone * 55) >> 8  (approx: tone >> 4 + tone >> 5 + 96)
  -- Simplified: 96 + tone(7 downto 4) * 3 + tone(7 downto 5)
  start_freq <= to_unsigned(96, 16) + resize(tone(7 downto 4), 16) +
                resize(tone(7 downto 4), 16) + resize(tone(7 downto 4), 16) +
                resize(tone(7 downto 5), 16);

  -- DECAY maps 0-255 to K value 10-14
  -- decay_k = 10 + decay(7 downto 6)
  decay_k <= to_unsigned(10, 4) + resize(decay(7 downto 6), 4);

  -- Shared sine table
  u_sine : entity work.sine_table
    port map (clk => clk, phase => phase, sine_out => sine_val);

  process(clk)
    variable product : signed(23 downto 0);
    variable shift_amt : integer;
  begin
    if rising_edge(clk) then
      if rst = '1' then
        phase <= (others => '0');
        freq <= (others => '0');
        amp <= (others => '0');
        active <= '0';
        audio_out <= (others => '0');
      else
        if trigger = '1' then
          active <= '1';
          phase <= (others => '0');
          freq <= start_freq;
          amp <= to_unsigned(65535, 16);
          div <= (others => '0');
        end if;

        if sample_tick = '1' and active = '1' then
          phase <= phase + freq;
          div <= div + 1;

          -- Pitch sweep down to end freq (68) every 7 samples
          if div = "110" and freq > 68 then
            freq <= freq - 1;
            div <= (others => '0');
          end if;

          -- Amplitude modulation: sine * amp(15:5)
          product := sine_val * signed('0' & amp(15 downto 5));
          audio_out <= product(22 downto 11);

          -- Exponential decay: amp -= amp >> K
          shift_amt := to_integer(decay_k);
          case shift_amt is
            when 10 => amp <= amp - ("0000000000" & amp(15 downto 10));
            when 11 => amp <= amp - ("00000000000" & amp(15 downto 11));
            when 12 => amp <= amp - ("000000000000" & amp(15 downto 12));
            when 13 => amp <= amp - ("0000000000000" & amp(15 downto 13));
            when others => amp <= amp - ("00000000000000" & amp(15 downto 14));
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
