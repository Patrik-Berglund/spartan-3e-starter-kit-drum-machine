library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity mixer is
  port (
    clk         : in  std_logic;
    rst         : in  std_logic;
    sample_tick : in  std_logic;
    in_bd       : in  signed(11 downto 0);
    in_sd       : in  signed(11 downto 0);
    in_lt       : in  signed(11 downto 0);
    in_mt       : in  signed(11 downto 0);
    in_ht       : in  signed(11 downto 0);
    in_rs       : in  signed(11 downto 0);
    in_cp       : in  signed(11 downto 0);
    in_cb       : in  signed(11 downto 0);
    in_cy       : in  signed(11 downto 0);
    in_oh       : in  signed(11 downto 0);
    in_ch       : in  signed(11 downto 0);
    mix_out     : out unsigned(11 downto 0)
  );
end entity mixer;

architecture rtl of mixer is
  signal lp_state : signed(15 downto 0) := (others => '0');
  -- Pipeline registers for sum
  signal sum_a, sum_b, sum_c : signed(14 downto 0) := (others => '0');
  signal sum_d : signed(13 downto 0) := (others => '0');
  signal sum_total : signed(15 downto 0) := (others => '0');
  signal pipe : unsigned(2 downto 0) := (others => '0');
begin
  process(clk)
    variable sat : signed(11 downto 0);
    variable diff : signed(15 downto 0);
  begin
    if rising_edge(clk) then
      if rst = '1' then
        mix_out <= (others => '0');
        lp_state <= (others => '0');
        pipe <= (others => '0');
      else
        if sample_tick = '1' then
          -- Stage 1: partial sums (3+3+3+2 voices)
          sum_a <= resize(in_bd, 15) + resize(in_sd, 15) + resize(in_lt, 15);
          sum_b <= resize(in_mt, 15) + resize(in_ht, 15) + resize(in_rs, 15);
          sum_c <= resize(in_cp, 15) + resize(in_cb, 15) + resize(in_cy, 15);
          sum_d <= resize(in_oh, 14) + resize(in_ch, 14);
          pipe <= "001";
        elsif pipe = "001" then
          -- Stage 2: final sum + attenuation
          sum_total <= (resize(sum_a, 16) + resize(sum_b, 16)) +
                       (resize(sum_c, 16) + resize(sum_d, 16));
          pipe <= "010";
        elsif pipe = "010" then
          -- Stage 3: saturate + LPF + output
          -- Attenuate >>2
          if sum_total > 8191 then sat := to_signed(2047, 12);
          elsif sum_total < -8192 then sat := to_signed(-2048, 12);
          else sat := sum_total(13 downto 2);
          end if;

          diff := resize(sat, 16) - lp_state;
          lp_state <= lp_state + shift_right(diff, 2);

          if lp_state > 2047 then
            mix_out <= to_unsigned(4095, 12);
          elsif lp_state < -2048 then
            mix_out <= to_unsigned(0, 12);
          else
            mix_out <= unsigned(lp_state(11 downto 0) + 2048);
          end if;
          pipe <= "000";
        end if;
      end if;
    end if;
  end process;
end architecture rtl;
