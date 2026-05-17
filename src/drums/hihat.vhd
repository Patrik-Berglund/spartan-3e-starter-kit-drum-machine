library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

-- Closed hi-hat: 6 square wave oscillators at non-harmonic frequencies,
-- summed and high-pass filtered. Fast decay (~25ms).

entity hihat is
  port (
    clk         : in  std_logic;
    rst         : in  std_logic;
    sample_tick : in  std_logic;
    trigger     : in  std_logic;
    audio_out   : out signed(11 downto 0)
  );
end entity hihat;

architecture rtl of hihat is
  -- 6 phase accumulators (20-bit)
  signal p0, p1, p2, p3, p4, p5 : unsigned(19 downto 0) := (others => '0');
  -- Phase increments for 204.7, 304.4, 369.6, 522.7, 540.4, 800.6 Hz @ 48828 Hz
  constant INC0 : unsigned(19 downto 0) := to_unsigned(4396, 20);
  constant INC1 : unsigned(19 downto 0) := to_unsigned(6537, 20);
  constant INC2 : unsigned(19 downto 0) := to_unsigned(7937, 20);
  constant INC3 : unsigned(19 downto 0) := to_unsigned(11225, 20);
  constant INC4 : unsigned(19 downto 0) := to_unsigned(11605, 20);
  constant INC5 : unsigned(19 downto 0) := to_unsigned(17191, 20);

  signal amp    : unsigned(13 downto 0) := (others => '0');
  signal active : std_logic := '0';
  signal hp_prev: signed(11 downto 0) := (others => '0');
begin
  process(clk)
    variable sq_sum : signed(3 downto 0);
    variable raw    : signed(11 downto 0);
    variable hp     : signed(12 downto 0);
    variable scaled : signed(25 downto 0);
  begin
    if rising_edge(clk) then
      if rst = '1' then
        p0 <= (others => '0'); p1 <= (others => '0');
        p2 <= (others => '0'); p3 <= (others => '0');
        p4 <= (others => '0'); p5 <= (others => '0');
        amp <= (others => '0');
        active <= '0';
        hp_prev <= (others => '0');
        audio_out <= (others => '0');
      else
        if trigger = '1' then
          active <= '1';
          amp <= to_unsigned(16383, 14);
        end if;

        if sample_tick = '1' and active = '1' then
          p0 <= p0 + INC0; p1 <= p1 + INC1;
          p2 <= p2 + INC2; p3 <= p3 + INC3;
          p4 <= p4 + INC4; p5 <= p5 + INC5;

          -- Sum of 6 square waves: each is +1 or -1 based on MSB
          sq_sum := to_signed(0, 4);
          if p0(19) = '1' then sq_sum := sq_sum + 1; else sq_sum := sq_sum - 1; end if;
          if p1(19) = '1' then sq_sum := sq_sum + 1; else sq_sum := sq_sum - 1; end if;
          if p2(19) = '1' then sq_sum := sq_sum + 1; else sq_sum := sq_sum - 1; end if;
          if p3(19) = '1' then sq_sum := sq_sum + 1; else sq_sum := sq_sum - 1; end if;
          if p4(19) = '1' then sq_sum := sq_sum + 1; else sq_sum := sq_sum - 1; end if;
          if p5(19) = '1' then sq_sum := sq_sum + 1; else sq_sum := sq_sum - 1; end if;

          -- Scale to 12-bit range: sq_sum is -6..+6, scale by 341 (~2048/6)
          raw := resize(sq_sum, 12) * to_signed(341, 12);
          raw := raw(11 downto 0);

          -- Simple high-pass: out = current - 0.9*previous
          -- Approx: hp = raw - prev + prev/8 (leaky)
          hp := resize(raw, 13) - resize(hp_prev, 13) + resize(shift_right(hp_prev, 3), 13);
          hp_prev <= raw;

          if hp > 2047 then raw := to_signed(2047, 12);
          elsif hp < -2048 then raw := to_signed(-2048, 12);
          else raw := hp(11 downto 0);
          end if;

          -- Apply amplitude envelope
          scaled := raw * signed('0' & amp(13 downto 1));
          audio_out <= scaled(24 downto 13);

          -- Fast decay: tau ~25ms = ~1220 samples, shift ~10
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
