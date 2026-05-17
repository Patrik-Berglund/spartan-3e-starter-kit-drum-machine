library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity kick_drum is
  port (
    clk         : in  std_logic;
    rst         : in  std_logic;
    sample_tick : in  std_logic;
    trigger     : in  std_logic;
    audio_out   : out signed(11 downto 0)
  );
end entity kick_drum;

architecture rtl of kick_drum is
  signal phase : unsigned(19 downto 0) := (others => '0');
  signal freq  : unsigned(19 downto 0) := (others => '0');
  signal amp   : unsigned(13 downto 0) := (others => '0');
  signal active: std_logic := '0';
  signal click : unsigned(3 downto 0) := (others => '0');

  -- 64-entry sine table, 12-bit signed
  type sine_t is array(0 to 63) of signed(11 downto 0);
  constant SINE : sine_t := (
    to_signed(0,12),    to_signed(201,12),  to_signed(399,12),  to_signed(591,12),
    to_signed(775,12),  to_signed(946,12),  to_signed(1101,12), to_signed(1237,12),
    to_signed(1351,12), to_signed(1440,12), to_signed(1503,12), to_signed(1538,12),
    to_signed(1545,12), to_signed(1524,12), to_signed(1476,12), to_signed(1400,12),
    to_signed(1299,12), to_signed(1175,12), to_signed(1028,12), to_signed(862,12),
    to_signed(679,12),  to_signed(483,12),  to_signed(277,12),  to_signed(64,12),
    to_signed(-150,12), to_signed(-362,12), to_signed(-566,12), to_signed(-759,12),
    to_signed(-936,12), to_signed(-1092,12),to_signed(-1224,12),to_signed(-1329,12),
    to_signed(-1404,12),to_signed(-1448,12),to_signed(-1460,12),to_signed(-1440,12),
    to_signed(-1389,12),to_signed(-1308,12),to_signed(-1199,12),to_signed(-1065,12),
    to_signed(-908,12), to_signed(-732,12), to_signed(-541,12), to_signed(-339,12),
    to_signed(-130,12), to_signed(82,12),   to_signed(293,12),  to_signed(498,12),
    to_signed(693,12),  to_signed(874,12),  to_signed(1037,12), to_signed(1179,12),
    to_signed(1296,12), to_signed(1387,12), to_signed(1449,12), to_signed(1481,12),
    to_signed(1483,12), to_signed(1455,12), to_signed(1398,12), to_signed(1313,12),
    to_signed(1203,12), to_signed(1069,12), to_signed(914,12),  to_signed(741,12)
  );
begin
  process(clk)
    variable s : signed(11 downto 0);
    variable out_v : signed(12 downto 0);
  begin
    if rising_edge(clk) then
      if rst = '1' then
        phase <= (others => '0');
        freq  <= (others => '0');
        amp   <= (others => '0');
        active <= '0';
        click <= (others => '0');
        audio_out <= (others => '0');
      else
        if trigger = '1' then
          active <= '1';
          phase  <= (others => '0');
          freq   <= to_unsigned(6872, 20);   -- 320 Hz start
          amp    <= to_unsigned(16383, 14);   -- full
          click  <= to_unsigned(3, 4);        -- 3 samples of click
        end if;

        if sample_tick = '1' and active = '1' then
          phase <= phase + freq;

          -- Pitch envelope: sweep 320Hz -> 51Hz in ~30ms (1465 samples)
          if freq > 1095 then
            freq <= freq - 4;
          end if;

          -- Amplitude envelope: tau ~335ms (shift 14 too slow, use 12 = 84ms)
          amp <= amp - ("000000" & amp(13 downto 6));

          if amp < 32 then
            active <= '0';
          end if;

          -- Sine lookup
          s := SINE(to_integer(phase(19 downto 14)));

          -- Apply amplitude
          out_v := resize(s, 13);
          -- Scale by amp/16384 (just shift)
          out_v := shift_right(out_v * signed('0' & amp(13 downto 2)), 12)(12 downto 0);

          -- Click transient at start
          if click > 0 then
            click <= click - 1;
            audio_out <= to_signed(2047, 12);
          else
            if out_v > 2047 then audio_out <= to_signed(2047, 12);
            elsif out_v < -2048 then audio_out <= to_signed(-2048, 12);
            else audio_out <= out_v(11 downto 0);
            end if;
          end if;
        elsif active = '0' then
          audio_out <= (others => '0');
        end if;
      end if;
    end if;
  end process;
end architecture rtl;
