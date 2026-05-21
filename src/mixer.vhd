library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity mixer is
  port (
    clk         : in  std_logic;
    rst         : in  std_logic;
    sample_tick : in  std_logic;
    in_bd       : in  signed(15 downto 0);
    in_sd       : in  signed(15 downto 0);
    in_lt       : in  signed(15 downto 0);
    in_mt       : in  signed(15 downto 0);
    in_ht       : in  signed(15 downto 0);
    in_rs       : in  signed(15 downto 0);
    in_cp       : in  signed(15 downto 0);
    in_cb       : in  signed(15 downto 0);
    in_cy       : in  signed(15 downto 0);
    in_oh       : in  signed(15 downto 0);
    in_ch       : in  signed(15 downto 0);
    mix_out     : out unsigned(11 downto 0)
  );
end entity mixer;

architecture rtl of mixer is
  -- Pipeline registers: 11 voices of 16-bit need 20-bit sum
  signal sum_a, sum_b, sum_c : signed(18 downto 0) := (others => '0');
  signal sum_d : signed(17 downto 0) := (others => '0');
  signal sum_total : signed(20 downto 0) := (others => '0');
  signal pipe : unsigned(1 downto 0) := (others => '0');
  -- Noise shaping error accumulator
  signal ns_error : signed(3 downto 0) := (others => '0');
begin
  process(clk)
    variable sat : signed(15 downto 0);
    variable shaped : signed(15 downto 0);
    variable dac_val : signed(11 downto 0);
  begin
    if rising_edge(clk) then
      if rst = '1' then
        mix_out <= (others => '0');
        pipe <= (others => '0');
        ns_error <= (others => '0');
      else
        if sample_tick = '1' then
          -- Stage 1: partial sums (3+3+3+2)
          sum_a <= resize(in_bd, 19) + resize(in_sd, 19) + resize(in_lt, 19);
          sum_b <= resize(in_mt, 19) + resize(in_ht, 19) + resize(in_rs, 19);
          sum_c <= resize(in_cp, 19) + resize(in_cb, 19) + resize(in_cy, 19);
          sum_d <= resize(in_oh, 18) + resize(in_ch, 18);
          pipe <= "01";
        elsif pipe = "01" then
          -- Stage 2: final sum
          sum_total <= (resize(sum_a, 21) + resize(sum_b, 21)) +
                       (resize(sum_c, 21) + resize(sum_d, 21));
          pipe <= "10";
        elsif pipe = "10" then
          -- Stage 3: saturate to 16-bit
          if sum_total > 32767 then sat := to_signed(32767, 16);
          elsif sum_total < -32768 then sat := to_signed(-32768, 16);
          else sat := sum_total(15 downto 0);
          end if;
          -- First-order noise shaping: add previous error
          shaped := sat + resize(ns_error, 16);
          -- Quantize to 12-bit (truncate lower 4 bits)
          dac_val := shaped(15 downto 4);
          -- Update error: residual = shaped - reconstructed
          ns_error <= shaped(3 downto 0);
          -- Output as unsigned 12-bit (add 2048 offset)
          mix_out <= unsigned(dac_val + 2048);
          pipe <= "00";
        end if;
      end if;
    end if;
  end process;
end architecture rtl;
