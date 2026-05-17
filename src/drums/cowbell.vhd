library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

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
  signal p0, p1 : unsigned(15 downto 0) := (others => '0');
  signal amp    : unsigned(15 downto 0) := (others => '0');
  signal active : std_logic := '0';
  signal lp_acc : signed(15 downto 0) := (others => '0');
  signal hp_acc : signed(15 downto 0) := (others => '0');
begin
  process(clk)
    variable sq : signed(2 downto 0);
    variable raw : signed(15 downto 0);
    variable bp_out : signed(15 downto 0);
    variable product : signed(23 downto 0);
  begin
    if rising_edge(clk) then
      if rst = '1' then
        p0 <= (others => '0'); p1 <= (others => '0');
        amp <= (others => '0'); active <= '0';
        lp_acc <= (others => '0'); hp_acc <= (others => '0');
        audio_out <= (others => '0');
      else
        if sample_tick = '1' then
          p0 <= p0 + to_unsigned(725, 16);   -- 540Hz
          p1 <= p1 + to_unsigned(1074, 16);  -- 800Hz
        end if;

        if trigger = '1' then
          active <= '1'; amp <= to_unsigned(65535, 16);
        end if;

        if sample_tick = '1' and active = '1' then
          sq := to_signed(0, 3);
          if p0(15) = '1' then sq := sq + 1; else sq := sq - 1; end if;
          if p1(15) = '1' then sq := sq + 1; else sq := sq - 1; end if;

          -- Scale: ±2 * 512 = ±1024
          raw := shift_left(resize(sq, 16), 9);

          -- Bandpass: LP then subtract HP
          lp_acc <= lp_acc + shift_right(raw - lp_acc, 2);
          hp_acc <= hp_acc + shift_right(lp_acc - hp_acc, 4);
          bp_out := lp_acc - hp_acc;

          product := bp_out(15 downto 4) * signed('0' & amp(15 downto 5));
          audio_out <= product(22 downto 11);

          -- Exponential decay K=11 (tau ~42ms)
          amp <= amp - ("00000000000" & amp(15 downto 11));
          if amp < 64 then active <= '0'; audio_out <= (others => '0');
          end if;
        elsif active = '0' then
          audio_out <= (others => '0');
        end if;
      end if;
    end if;
  end process;
end architecture rtl;
