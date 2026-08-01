library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity clap is
  port (
    clk         : in  std_logic;
    rst         : in  std_logic;
    sample_tick : in  std_logic;
    trigger     : in  std_logic;
    audio_out   : out signed(15 downto 0)
  );
end entity clap;

architecture rtl of clap is
  signal lfsr   : std_logic_vector(15 downto 0) := x"BEEF";
  signal amp    : unsigned(15 downto 0) := (others => '0');
  signal active : std_logic := '0';
  signal count  : unsigned(12 downto 0) := (others => '0');
  signal lp_acc : signed(15 downto 0) := (others => '0');
  signal hp_acc : signed(15 downto 0) := (others => '0');
begin
  process(clk)
    variable noise_raw : signed(15 downto 0);
    variable bp_out : signed(15 downto 0);
    variable product : signed(27 downto 0);
    variable c : integer;
    variable gate : std_logic;
  begin
    if rising_edge(clk) then
      if rst = '1' then
        lfsr <= x"BEEF"; amp <= (others => '0');
        active <= '0'; count <= (others => '0');
        lp_acc <= (others => '0'); hp_acc <= (others => '0');
        audio_out <= (others => '0');
      else
        if trigger = '1' then
          active <= '1'; amp <= to_unsigned(65535, 16); count <= (others => '0');
        end if;

        if sample_tick = '1' and active = '1' then
          lfsr <= lfsr(14 downto 0) & (lfsr(15) xor lfsr(13) xor lfsr(11) xor lfsr(0));
          -- count is unsigned(12 downto 0), max 8191. Original code
          -- incremented it unconditionally every sample_tick while active
          -- with no upper bound -- confirmed (via scripts/sim_vhdl.py's
          -- fixed-width wrappers) that it wraps from 8191 back to 0 after
          -- ~170ms of sustained activity, which re-evaluates the burst
          -- gate logic from the start (c<244 becomes true again) and
          -- RE-FIRES the attack bursts without any new trigger -- and
          -- since `active` only clears when amp<64 AND count>=2196, a
          -- wrap back below 2196 could prevent `active` from ever
          -- clearing. Fix: hold count at 2196 (start of tail) once
          -- reached, instead of letting it free-run toward the register's
          -- 13-bit ceiling.
          if count < 2196 then
            count <= count + 1;
          end if;
          c := to_integer(count);

          -- Burst pattern per service manual Figure 13
          if    c < 244  then gate := '1';   -- burst 1
          elsif c < 976  then gate := '0';   -- gap
          elsif c < 1220 then gate := '1';   -- burst 2
          elsif c < 1952 then gate := '0';   -- gap
          elsif c < 2196 then gate := '1';   -- burst 3
          else                gate := '1';   -- tail
          end if;

          -- Bandpass filtered noise (~1000Hz)
          noise_raw := shift_left(resize(signed(lfsr(11 downto 0)), 16), 3);
          lp_acc <= lp_acc + shift_right(noise_raw - lp_acc, 3);
          hp_acc <= hp_acc + shift_right(lp_acc - hp_acc, 4);
          bp_out := lp_acc - hp_acc;

          if gate = '1' then
            product := bp_out * signed('0' & amp(15 downto 5));
            audio_out <= product(26 downto 11);
          else
            audio_out <= (others => '0');
          end if;

          -- Exponential decay only during tail K=12 (tau ~84ms). Force to
          -- 0 once the decay term itself is 0 -- K=12 floor is 4096, above
          -- the old amp<64 threshold, so amp would get permanently stuck
          -- without this (compounding with the count wraparound bug above
          -- to make clap play forever after a single trigger).
          if c >= 2196 then
            if amp(15 downto 12) = "0000" then amp <= (others => '0');
            else amp <= amp - ("000000000000" & amp(15 downto 12)); end if;
            if amp < 64 then active <= '0'; end if;
          end if;
        elsif active = '0' then
          audio_out <= (others => '0');
        end if;
      end if;
    end if;
  end process;
end architecture rtl;
