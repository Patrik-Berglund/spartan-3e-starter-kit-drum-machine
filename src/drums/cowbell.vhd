library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

-- 808 Cowbell - two square oscillators through resonant BPF, dual decay.
-- Circuit (voices2.PNG): Two square-wave oscillators -> individual VCAs
-- (shared envelope) -> sum -> BANDPASS FILTER -> buffer. NO noise source.
-- Real 808 measured: f1=557Hz (secondary, -15.9dB), f2=824Hz (dominant).
-- Dual-exponential envelope: fast (tau~10.5ms) + slow ring tail (tau~42ms).

entity cowbell is
  port (
    clk         : in  std_logic;
    rst         : in  std_logic;
    sample_tick : in  std_logic;
    trigger     : in  std_logic;
    audio_out   : out signed(15 downto 0)
  );
end entity cowbell;

architecture rtl of cowbell is
  signal p0, p1 : unsigned(15 downto 0) := (others => '0');
  signal amp_fast, amp_slow : unsigned(15 downto 0) := (others => '0');
  signal active : std_logic := '0';

  -- State-variable filter (resonant bandpass)
  signal svf_lp : signed(15 downto 0) := (others => '0');
  signal svf_bp : signed(15 downto 0) := (others => '0');
begin
  process(clk)
    variable sq1, sq2 : signed(2 downto 0);
    variable raw : signed(15 downto 0);
    variable hp        : signed(15 downto 0);
    variable bp_out     : signed(15 downto 0);
    variable combined_amp : unsigned(15 downto 0);
    variable product   : signed(27 downto 0);
    variable dec_fast, dec_slow : unsigned(15 downto 0);
  begin
    if rising_edge(clk) then
      if rst = '1' then
        p0 <= (others => '0'); p1 <= (others => '0');
        amp_fast <= (others => '0'); amp_slow <= (others => '0');
        active <= '0';
        svf_lp <= (others => '0'); svf_bp <= (others => '0');
        audio_out <= (others => '0');
      else
        if sample_tick = '1' then
          p0 <= p0 + to_unsigned(748, 16);   -- 557Hz
          p1 <= p1 + to_unsigned(1106, 16);  -- 824Hz
        end if;

        if trigger = '1' then
          active <= '1';
          amp_fast <= to_unsigned(65535, 16);
          amp_slow <= to_unsigned(65535, 16);
        end if;

        if sample_tick = '1' and active = '1' then
          if p0(15) = '1' then sq1 := to_signed(1, 3); else sq1 := to_signed(-1, 3); end if;
          if p1(15) = '1' then sq2 := to_signed(1, 3); else sq2 := to_signed(-1, 3); end if;

          -- Weight osc2 (824Hz) 2x relative to osc1 (557Hz): sq1 + sq2*2
          -- range: -3..+3, scale by 4096 -> ±12288
          raw := shift_left(resize(sq1, 16) + shift_left(resize(sq2, 16), 1), 12);

          -- State-variable filter: hp = in - lp - (bp>>2); bp += hp>>3; lp += bp>>3
          -- (matches sim's exact update order: hp uses old bp/lp, then bp
          -- updates using hp, then lp updates using the NEW bp)
          hp := raw - svf_lp - shift_right(svf_bp, 2);
          bp_out := svf_bp + shift_right(hp, 3);
          svf_bp <= bp_out;
          svf_lp <= svf_lp + shift_right(bp_out, 3);

          -- Combined dual-decay envelope: (fast*3 + slow) >> 2
          combined_amp := resize(shift_right(
            resize(amp_fast(15 downto 5), 18) * 3 + resize(amp_slow(15 downto 5), 18),
            2), 16);

          product := bp_out * signed('0' & combined_amp(10 downto 0));
          audio_out <= product(26 downto 11);

          -- Fast decay: K=9, only decay if >=64 (prevent underflow wrap)
          if amp_fast >= 64 then
            dec_fast := "000000000" & amp_fast(15 downto 9);
            if dec_fast = 0 then amp_fast <= amp_fast - 1;
            else amp_fast <= amp_fast - dec_fast; end if;
          end if;

          -- Slow decay: K=11
          if amp_slow >= 64 then
            dec_slow := "00000000000" & amp_slow(15 downto 11);
            if dec_slow = 0 then amp_slow <= amp_slow - 1;
            else amp_slow <= amp_slow - dec_slow; end if;
          end if;

          if amp_fast < 64 and amp_slow < 64 then
            active <= '0';
          end if;
        elsif active = '0' then
          audio_out <= (others => '0');
        end if;
      end if;
    end if;
  end process;
end architecture rtl;
