library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity mixer is
  port (
    clk         : in  std_logic;
    rst         : in  std_logic;
    sample_tick : in  std_logic;
    -- 11 voice inputs (12-bit signed)
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
    -- Output (12-bit unsigned for DAC)
    mix_out     : out unsigned(11 downto 0)
  );
end entity mixer;

architecture rtl of mixer is
begin
  process(clk)
    variable sum : signed(15 downto 0);
    variable sat : signed(11 downto 0);
  begin
    if rising_edge(clk) then
      if rst = '1' then
        mix_out <= (others => '0');
      elsif sample_tick = '1' then
        sum := resize(in_bd, 16) + resize(in_sd, 16) + resize(in_lt, 16) +
               resize(in_mt, 16) + resize(in_ht, 16) + resize(in_rs, 16) +
               resize(in_cp, 16) + resize(in_cb, 16) + resize(in_cy, 16) +
               resize(in_oh, 16) + resize(in_ch, 16);
        -- Attenuate by /8 (11 voices, /8 gives ~1.4x headroom)
        sum := shift_right(sum, 3);
        if sum > 2047 then sat := to_signed(2047, 12);
        elsif sum < -2048 then sat := to_signed(-2048, 12);
        else sat := sum(11 downto 0);
        end if;
        mix_out <= unsigned(sat + 2048);
      end if;
    end if;
  end process;
end architecture rtl;
