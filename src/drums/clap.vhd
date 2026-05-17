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
  signal lfsr      : std_logic_vector(15 downto 0) := x"BEEF";
  signal amplitude : unsigned(11 downto 0) := (others => '0');
  signal active    : std_logic := '0';
  signal tick_cnt  : unsigned(9 downto 0) := (others => '0');
  -- Burst state: 3 short bursts then sustained decay
  signal burst_num : unsigned(1 downto 0) := (others => '0');
  signal burst_cnt : unsigned(5 downto 0) := (others => '0');
  signal in_gap    : std_logic := '0';
begin

  process(clk)
    variable noise_val : signed(11 downto 0);
    variable scaled    : signed(23 downto 0);
  begin
    if rising_edge(clk) then
      if rst = '1' then
        lfsr      <= x"BEEF";
        amplitude <= (others => '0');
        active    <= '0';
        audio_out <= (others => '0');
        tick_cnt  <= (others => '0');
        burst_num <= (others => '0');
        burst_cnt <= (others => '0');
        in_gap    <= '0';
      else
        if trigger = '1' then
          active    <= '1';
          amplitude <= to_unsigned(4095, 12);
          tick_cnt  <= (others => '0');
          burst_num <= (others => '0');
          burst_cnt <= (others => '0');
          in_gap    <= '0';
        end if;

        if sample_tick = '1' and active = '1' then
          -- LFSR
          lfsr <= lfsr(14 downto 0) & (lfsr(15) xor lfsr(13) xor lfsr(11) xor lfsr(0));

          tick_cnt <= tick_cnt + 1;

          -- Burst phase: 3 bursts of ~20 samples with ~10 sample gaps
          if burst_num < 3 then
            burst_cnt <= burst_cnt + 1;
            if in_gap = '0' then
              if burst_cnt = 20 then
                in_gap <= '1';
                burst_cnt <= (others => '0');
              end if;
            else
              if burst_cnt = 10 then
                in_gap <= '0';
                burst_cnt <= (others => '0');
                burst_num <= burst_num + 1;
              end if;
            end if;
          end if;

          -- Decay after bursts
          if burst_num = 3 then
            if tick_cnt(2 downto 0) = "111" then
              amplitude <= amplitude - ("000" & amplitude(11 downto 3));
            end if;
          end if;

          if amplitude < 8 and burst_num = 3 then
            active <= '0';
            amplitude <= (others => '0');
          end if;

          -- Output
          noise_val := signed(lfsr(11 downto 0));
          if in_gap = '1' then
            audio_out <= (others => '0');
          else
            scaled := noise_val * signed('0' & amplitude);
            audio_out <= scaled(23 downto 12);
          end if;
        elsif active = '0' then
          audio_out <= (others => '0');
        end if;
      end if;
    end if;
  end process;

end architecture rtl;
