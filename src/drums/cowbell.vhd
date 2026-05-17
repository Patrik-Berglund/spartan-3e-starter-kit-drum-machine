library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

-- Cowbell: 2 square waves at 540Hz and 800Hz, bandpass filtered, short decay

entity cowbell is
  port (
    clk         : in  std_logic;
    rst         : in  std_logic;
    sample_tick : in  std_logic;
    trigger     : in  std_logic;
    audio_out   : out signed(11 downto 0)
  );
end entity cowbell;

architecture rtl of cowbell is
  signal p0, p1 : unsigned(19 downto 0) := (others => '0');
  constant INC0 : unsigned(19 downto 0) := to_unsigned(11605, 20); -- 540 Hz
  constant INC1 : unsigned(19 downto 0) := to_unsigned(17191, 20); -- 800 Hz
  signal amp    : unsigned(13 downto 0) := (others => '0');
  signal active : std_logic := '0';
  signal bp_state : signed(15 downto 0) := (others => '0');
begin
  process(clk)
    variable sq_sum : signed(2 downto 0);
    variable raw    : signed(11 downto 0);
    variable scaled : signed(25 downto 0);
  begin
    if rising_edge(clk) then
      if rst = '1' then
        p0 <= (others => '0'); p1 <= (others => '0');
        amp <= (others => '0'); active <= '0';
        bp_state <= (others => '0');
        audio_out <= (others => '0');
      else
        if trigger = '1' then
          active <= '1';
          amp <= to_unsigned(14000, 14);
        end if;

        if sample_tick = '1' and active = '1' then
          p0 <= p0 + INC0;
          p1 <= p1 + INC1;

          sq_sum := to_signed(0, 3);
          if p0(19) = '1' then sq_sum := sq_sum + 1; else sq_sum := sq_sum - 1; end if;
          if p1(19) = '1' then sq_sum := sq_sum + 1; else sq_sum := sq_sum - 1; end if;

          -- Scale: -2..+2 -> -1024..+1024
          raw := resize(sq_sum, 12) * to_signed(512, 12);
          raw := raw(11 downto 0);

          -- Bandpass
          bp_state <= bp_state + shift_right(resize(raw, 16) - bp_state, 2);
          raw := bp_state(15 downto 4);

          scaled := raw * signed('0' & amp(13 downto 1));
          audio_out <= scaled(24 downto 13);

          -- Fast decay ~50ms
          amp <= amp - ("0000000000" & amp(13 downto 10));
          if amp < 16 then
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
