library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

-- Minimal standalone DAC/SPI test harness.
-- Bypasses the entire drum machine (sequencer, mixer, all voices, UI) and
-- drives dac_driver directly with a free-running sine wave generated via
-- the *actual* src/infrastructure/sine_table.vhd module (same one used by
-- kick_drum.vhd) -- used to verify both the SPI/DAC path AND the shared
-- sine table/interpolation pipeline in isolation with an oscilloscope,
-- before debugging voice-level issues in the full design (top.vhd).
--
-- Expected scope result on the DAC output (J5 pin 1): a clean sine wave,
-- swinging near the full 0-3.3V DAC range, at a fixed audible frequency
-- (see PHASE_INC below -- default gives roughly 190 Hz at ~48.8kHz sample
-- rate: 190 * 65536 / 48828 =~ 255).
--
-- If this shows a clean sine: SPI/DAC path AND sine_table/interpolation
-- pipeline are both good -- bug is elsewhere in the full design's
-- voice-specific logic, sequencer, or mixer.
-- If this shows noise/glitches/wrong shape: bug is in sine_table.vhd's
-- pipeline (e.g. a timing-sensitive path there) or the DAC/SPI path itself.

entity dac_test is
  port (
    clk_50mhz : in  std_logic;
    btn_south : in  std_logic;

    -- SPI / DAC (same pins as top.vhd)
    spi_sck     : out std_logic;
    spi_mosi    : out std_logic;
    spi_miso    : in  std_logic;
    dac_cs      : out std_logic;
    dac_clr     : out std_logic;
    spi_ss_b    : out std_logic;
    amp_cs      : out std_logic;
    ad_conv     : out std_logic;
    sf_ce0      : out std_logic;
    fpga_init_b : out std_logic;

    -- LEDs: heartbeat + sample_tick indicator (visual confirmation the
    -- design is alive even without a scope)
    led : out std_logic_vector(7 downto 0)
  );
end entity dac_test;

architecture rtl of dac_test is
  signal rst : std_logic;

  -- Sample tick generator: same divide as the main design (50MHz / 1024 =
  -- ~48.8kHz) so this test exercises the DAC path at the real audio rate.
  signal tick_cnt    : unsigned(9 downto 0) := (others => '0');
  signal sample_tick : std_logic := '0';

  -- Free-running phase accumulator driving sine_table.vhd (same module
  -- kick_drum.vhd uses). PHASE_INC=255 -> ~190Hz at 48828 Hz sample rate
  -- (255 * 48828 / 65536 =~ 190).
  signal phase   : unsigned(15 downto 0) := (others => '0');
  constant PHASE_INC : unsigned(15 downto 0) := to_unsigned(255, 16);

  signal sine_val : signed(11 downto 0);
  signal dac_sample : unsigned(11 downto 0);

  signal heartbeat : unsigned(23 downto 0) := (others => '0');
begin
  rst <= btn_south;

  -- Sample tick: 50MHz / 1024 ~= 48.8kHz
  process(clk_50mhz)
  begin
    if rising_edge(clk_50mhz) then
      if rst = '1' then
        tick_cnt <= (others => '0');
        sample_tick <= '0';
      else
        if tick_cnt = 1023 then
          tick_cnt <= (others => '0');
          sample_tick <= '1';
        else
          tick_cnt <= tick_cnt + 1;
          sample_tick <= '0';
        end if;
      end if;
    end if;
  end process;

  -- Free-running phase accumulator
  process(clk_50mhz)
  begin
    if rising_edge(clk_50mhz) then
      if rst = '1' then
        phase <= (others => '0');
      elsif sample_tick = '1' then
        phase <= phase + PHASE_INC;
      end if;
    end if;
  end process;

  -- Same sine table module used by kick_drum.vhd
  u_sine : entity work.sine_table
    port map (clk => clk_50mhz, phase => phase, sine_out => sine_val);

  -- Offset signed sine (~-2047..2047) to unsigned DAC range (0..4095)
  dac_sample <= unsigned(resize(sine_val, 13) + 2048);

  -- Heartbeat LED so it's visually obvious the FPGA is running even
  -- without a scope attached.
  process(clk_50mhz)
  begin
    if rising_edge(clk_50mhz) then
      heartbeat <= heartbeat + 1;
    end if;
  end process;
  led(7) <= heartbeat(23);
  led(6 downto 1) <= (others => '0');
  led(0) <= sample_tick;

  u_dac : entity work.dac_driver
    port map (
      clk         => clk_50mhz,
      rst         => rst,
      sample_tick => sample_tick,
      sample_in   => dac_sample,
      spi_sck     => spi_sck,
      spi_mosi    => spi_mosi,
      spi_miso    => spi_miso,
      dac_cs      => dac_cs,
      dac_clr     => dac_clr,
      spi_ss_b    => spi_ss_b,
      amp_cs      => amp_cs,
      ad_conv     => ad_conv,
      sf_ce0      => sf_ce0,
      fpga_init_b => fpga_init_b
    );

end architecture rtl;
