library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

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
  signal amp    : unsigned(15 downto 0) := (others => '0');
  signal active : std_logic := '0';
  signal count  : unsigned(12 downto 0) := (others => '0');
  signal lp_acc : signed(15 downto 0) := (others => '0');
  signal hp_acc : signed(15 downto 0) := (others => '0');
begin
  process(clk)
    variable noise_raw : signed(15 downto 0);
    variable bp_out : signed(15 downto 0);
    variable product : signed(23 downto 0);
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
          count <= count + 1;
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
          noise_raw := resize(signed(lfsr(11 downto 0)), 16);
          lp_acc <= lp_acc + shift_right(noise_raw - lp_acc, 3);
          hp_acc <= hp_acc + shift_right(lp_acc - hp_acc, 4);
          bp_out := lp_acc - hp_acc;

          if gate = '1' then
            product := bp_out(15 downto 4) * signed('0' & amp(15 downto 5));
            audio_out <= product(22 downto 11);
          else
            audio_out <= (others => '0');
          end if;

          -- Exponential decay only during tail K=12 (tau ~84ms)
          if c >= 2196 then
            amp <= amp - ("000000000000" & amp(15 downto 12));
            if amp < 64 then active <= '0'; end if;
          end if;
        elsif active = '0' then
          audio_out <= (others => '0');
        end if;
      end if;
    end if;
  end process;
end architecture rtl;
