library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

-- 808 Rimshot - dual resonant modes from shared RS/CL oscillator circuit.
-- Real 808 RS spectrum: 1712Hz (dominant, fast decay) + 458Hz (secondary, slower decay).
-- Two independent envelopes create the bright-attack/warm-tail character.

entity rimshot is
  port (
    clk         : in  std_logic;
    rst         : in  std_logic;
    sample_tick : in  std_logic;
    trigger     : in  std_logic;
    audio_out   : out signed(15 downto 0)
  );
end entity rimshot;

architecture rtl of rimshot is
  signal ph_lo, ph_hi : unsigned(15 downto 0) := (others => '0');
  signal amp_lo, amp_hi : unsigned(15 downto 0) := (others => '0');
  signal active : std_logic := '0';

  type sine_t is array(0 to 63) of signed(11 downto 0);
  constant SINE : sine_t := (
    to_signed(0,12),to_signed(201,12),to_signed(399,12),to_signed(594,12),
    to_signed(783,12),to_signed(965,12),to_signed(1137,12),to_signed(1299,12),
    to_signed(1447,12),to_signed(1582,12),to_signed(1702,12),to_signed(1805,12),
    to_signed(1891,12),to_signed(1959,12),to_signed(2008,12),to_signed(2037,12),
    to_signed(2047,12),to_signed(2037,12),to_signed(2008,12),to_signed(1959,12),
    to_signed(1891,12),to_signed(1805,12),to_signed(1702,12),to_signed(1582,12),
    to_signed(1447,12),to_signed(1299,12),to_signed(1137,12),to_signed(965,12),
    to_signed(783,12),to_signed(594,12),to_signed(399,12),to_signed(201,12),
    to_signed(0,12),to_signed(-201,12),to_signed(-399,12),to_signed(-594,12),
    to_signed(-783,12),to_signed(-965,12),to_signed(-1137,12),to_signed(-1299,12),
    to_signed(-1447,12),to_signed(-1582,12),to_signed(-1702,12),to_signed(-1805,12),
    to_signed(-1891,12),to_signed(-1959,12),to_signed(-2008,12),to_signed(-2037,12),
    to_signed(-2047,12),to_signed(-2037,12),to_signed(-2008,12),to_signed(-1959,12),
    to_signed(-1891,12),to_signed(-1805,12),to_signed(-1702,12),to_signed(-1582,12),
    to_signed(-1447,12),to_signed(-1299,12),to_signed(-1137,12),to_signed(-965,12),
    to_signed(-783,12),to_signed(-594,12),to_signed(-399,12),to_signed(-201,12)
  );

  signal s_lo, s_hi : signed(11 downto 0);

  constant PINC_LO : unsigned(15 downto 0) := to_unsigned(615, 16);   -- 458Hz
  constant PINC_HI : unsigned(15 downto 0) := to_unsigned(2298, 16);  -- 1712Hz
begin
  s_lo <= SINE(to_integer(ph_lo(15 downto 10)));
  s_hi <= SINE(to_integer(ph_hi(15 downto 10)));

  process(clk)
    variable p_lo, p_hi : signed(27 downto 0);
    variable mix        : signed(16 downto 0);
    variable dec_lo, dec_hi : unsigned(15 downto 0);
  begin
    if rising_edge(clk) then
      if rst = '1' then
        ph_lo <= (others => '0'); ph_hi <= (others => '0');
        amp_lo <= (others => '0'); amp_hi <= (others => '0');
        active <= '0'; audio_out <= (others => '0');
      else
        if trigger = '1' then
          active <= '1';
          ph_lo <= (others => '0'); ph_hi <= (others => '0');
          amp_lo <= to_unsigned(65535, 16);
          amp_hi <= to_unsigned(65535, 16);
        end if;

        if sample_tick = '1' and active = '1' then
          ph_lo <= ph_lo + PINC_LO;
          ph_hi <= ph_hi + PINC_HI;

          -- p_lo = (s_lo * (amp_lo>>5) * 3) >> 2  [matches sim exactly]
          p_lo := shift_right(resize(s_lo * signed('0' & amp_lo(15 downto 5)), 28) *
                  to_signed(3, 3), 2);
          -- p_hi = s_hi * (amp_hi>>5) * 5
          p_hi := resize(s_hi * signed('0' & amp_hi(15 downto 5)), 28) * to_signed(5, 4);

          -- mix = p_lo>>9 + p_hi>>10  [matches sim]
          mix := resize(shift_right(p_lo, 9), 17) + resize(shift_right(p_hi, 10), 17);

          if mix > 32767 then audio_out <= to_signed(32767, 16);
          elsif mix < -32768 then audio_out <= to_signed(-32768, 16);
          else audio_out <= mix(15 downto 0); end if;

          -- Lower tone: K=9 (tau~10ms), only decay if >= 64 (prevent underflow wrap)
          if amp_lo >= 64 then
            dec_lo := "000000000" & amp_lo(15 downto 9);
            if dec_lo = 0 then amp_lo <= amp_lo - 1;
            else amp_lo <= amp_lo - dec_lo; end if;
          end if;

          -- Upper tone: K=8 (tau~5ms), only decay if >= 64
          if amp_hi >= 64 then
            dec_hi := "00000000" & amp_hi(15 downto 8);
            if dec_hi = 0 then amp_hi <= amp_hi - 1;
            else amp_hi <= amp_hi - dec_hi; end if;
          end if;

          if amp_lo < 64 and amp_hi < 64 then
            active <= '0';
          end if;
        elsif active = '0' then
          audio_out <= (others => '0');
        end if;
      end if;
    end if;
  end process;
end architecture rtl;
