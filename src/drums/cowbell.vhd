library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

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
  signal amp    : unsigned(15 downto 0) := (others => '0');
  signal active : std_logic := '0';
  signal lp_acc1 : signed(15 downto 0) := (others => '0');
  signal lp_acc2 : signed(15 downto 0) := (others => '0');
  signal hp_acc1 : signed(15 downto 0) := (others => '0');
  signal hp_acc2 : signed(15 downto 0) := (others => '0');
  -- Broadband noise source (same rationale as hihat.vhd).
  signal lfsr : std_logic_vector(15 downto 0) := x"CAFE";
begin
  process(clk)
    variable sq : signed(3 downto 0);
    variable raw : signed(15 downto 0);
    variable noise_raw : signed(15 downto 0);
    variable noise_wide : signed(18 downto 0);
    variable noise_scaled : signed(15 downto 0);
    variable lp1_next, lp2_next : signed(15 downto 0);
    variable hp1_next, hp2_next : signed(15 downto 0);
    variable bp_out : signed(15 downto 0);
    variable product : signed(27 downto 0);
  begin
    if rising_edge(clk) then
      if rst = '1' then
        p0 <= (others => '0'); p1 <= (others => '0');
        amp <= (others => '0'); active <= '0';
        lp_acc1 <= (others => '0'); lp_acc2 <= (others => '0');
        hp_acc1 <= (others => '0'); hp_acc2 <= (others => '0');
        lfsr <= x"CAFE";
        audio_out <= (others => '0');
      else
        if sample_tick = '1' then
          p0 <= p0 + to_unsigned(725, 16);   -- 540Hz
          p1 <= p1 + to_unsigned(1075, 16);  -- 800Hz
        end if;

        if trigger = '1' then
          active <= '1'; amp <= to_unsigned(65535, 16);
        end if;

        if sample_tick = '1' and active = '1' then
          sq := to_signed(0, 4);
          if p0(15) = '1' then sq := sq + 1; else sq := sq - 1; end if;
          if p1(15) = '1' then sq := sq + 1; else sq := sq - 1; end if;

          -- Scale: ±2 * 4096 = ±8192
          raw := shift_left(resize(sq, 16), 12);

          -- Mix in broadband LFSR noise (noise_mult=10, scaled by >>3);
          -- shift-and-add (10x = 8x+2x) instead of a multiply to avoid
          -- consuming a MULT18X18 block.
          lfsr <= lfsr(14 downto 0) & (lfsr(15) xor lfsr(13) xor lfsr(12) xor lfsr(10));
          noise_raw := signed(lfsr(14 downto 0) & '0') - to_signed(16384, 16);
          noise_wide := shift_left(resize(noise_raw, 19), 3) + shift_left(resize(noise_raw, 19), 1);
          noise_scaled := resize(shift_right(noise_wide, 3), 16);
          raw := raw + noise_scaled;

          -- BPF: 2-stage LP (shift 1, was 2) + 2-stage HP (shift 3, was 4) --
          -- widened slightly to preserve the injected noise's spectral
          -- contribution (sim result vs real CB.WAV: centroid=5215Hz/
          -- flatness=0.44 vs ref centroid=6654Hz/flatness=0.43).
          lp1_next := lp_acc1 + shift_right(raw - lp_acc1, 1);
          lp_acc1 <= lp1_next;
          lp2_next := lp_acc2 + shift_right(lp1_next - lp_acc2, 1);
          lp_acc2 <= lp2_next;
          hp1_next := hp_acc1 + shift_right(lp2_next - hp_acc1, 3);
          hp_acc1 <= hp1_next;
          hp2_next := hp_acc2 + shift_right(hp1_next - hp_acc2, 3);
          hp_acc2 <= hp2_next;
          bp_out := lp2_next - hp2_next;

          product := bp_out * signed('0' & amp(15 downto 5));
          audio_out <= product(26 downto 11);

          -- Exponential decay K=10. Force to 0 once the decay term itself
          -- is 0 -- K=10 floor is 1024, above the old amp<64 threshold, so
          -- amp would get permanently stuck without this.
          if amp(15 downto 10) = "000000" then amp <= (others => '0');
          else amp <= amp - ("0000000000" & amp(15 downto 10)); end if;
          if amp < 64 then active <= '0'; audio_out <= (others => '0');
          end if;
        elsif active = '0' then
          audio_out <= (others => '0');
        end if;
      end if;
    end if;
  end process;
end architecture rtl;
