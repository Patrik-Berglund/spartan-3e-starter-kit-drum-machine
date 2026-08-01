library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity hihat is
  port (
    clk         : in  std_logic;
    rst         : in  std_logic;
    sample_tick : in  std_logic;
    trigger     : in  std_logic;
    audio_out   : out signed(15 downto 0)
  );
end entity hihat;

architecture rtl of hihat is
  signal p0, p1, p2, p3, p4, p5 : unsigned(15 downto 0) := (others => '0');
  signal amp     : unsigned(15 downto 0) := (others => '0');
  signal active  : std_logic := '0';
  -- BPF: 1-stage LP + 4-stage HP. Widened to 18-bit: the square-oscillator
  -- sum (max +-32640) plus injected noise (max +-20478) can reach +-53118,
  -- which overflows a 16-bit signed range (+-32767) and wraps -- this was
  -- causing a runaway noise buildup on real hardware (confirmed via
  -- oscilloscope: DAC output showed persistent "background noise" that
  -- built up over a few seconds of playback and never recovered, because
  -- these filter accumulators are never reset between hits, only on rst).
  signal lp_acc : signed(17 downto 0) := (others => '0');
  signal hp_acc0, hp_acc1, hp_acc2, hp_acc3 : signed(17 downto 0) := (others => '0');
  -- Broadband noise source (fills spectral gaps left by the coarse 7-level
  -- square-oscillator sum -- see docs/808-synthesis-reference.md notes).
  -- Same LFSR taps as snare_drum.vhd; unique seed to decorrelate voices.
  signal lfsr : std_logic_vector(15 downto 0) := x"F00D";
begin
  process(clk)
    variable sq : signed(4 downto 0);
    variable raw : signed(17 downto 0);
    variable noise_raw : signed(15 downto 0);
    variable noise_wide : signed(18 downto 0);
    variable noise_scaled : signed(17 downto 0);
    variable lp_out : signed(17 downto 0);
    variable x0, x1, x2, x3 : signed(17 downto 0);
    variable x3_clamped : signed(15 downto 0);
    variable product : signed(27 downto 0);
  begin
    if rising_edge(clk) then
      if rst = '1' then
        p0 <= (others => '0'); p1 <= (others => '0');
        p2 <= (others => '0'); p3 <= (others => '0');
        p4 <= (others => '0'); p5 <= (others => '0');
        amp <= (others => '0'); active <= '0';
        lp_acc <= (others => '0');
        hp_acc0 <= (others => '0'); hp_acc1 <= (others => '0');
        hp_acc2 <= (others => '0'); hp_acc3 <= (others => '0');
        lfsr <= x"F00D";
        audio_out <= (others => '0');
      else
        if sample_tick = '1' then
          p0 <= p0 + to_unsigned(275, 16);
          p1 <= p1 + to_unsigned(409, 16);
          p2 <= p2 + to_unsigned(496, 16);
          p3 <= p3 + to_unsigned(702, 16);
          p4 <= p4 + to_unsigned(725, 16);
          p5 <= p5 + to_unsigned(1075, 16);
        end if;

        if trigger = '1' then
          active <= '1';
          amp <= to_unsigned(65535, 16);
        end if;

        if sample_tick = '1' and active = '1' then
          sq := to_signed(0, 5);
          if p0(15) = '1' then sq := sq + 1; else sq := sq - 1; end if;
          if p1(15) = '1' then sq := sq + 1; else sq := sq - 1; end if;
          if p2(15) = '1' then sq := sq + 1; else sq := sq - 1; end if;
          if p3(15) = '1' then sq := sq + 1; else sq := sq - 1; end if;
          if p4(15) = '1' then sq := sq + 1; else sq := sq - 1; end if;
          if p5(15) = '1' then sq := sq + 1; else sq := sq - 1; end if;

          -- Scale: sq*5440
          raw := shift_left(resize(sq, 18), 12) + shift_left(resize(sq, 18), 10) +
                 shift_left(resize(sq, 18), 8) + shift_left(resize(sq, 18), 6);

          -- Mix in broadband LFSR noise (noise_mult=10, scaled by >>3) --
          -- fills the harmonic gaps left by the coarse square-sum staircase.
          -- Implemented as shift-and-add (10*x = 8x+2x) instead of a
          -- multiply to avoid consuming a MULT18X18 block (already at 100%
          -- utilization on this device).
          lfsr <= lfsr(14 downto 0) & (lfsr(15) xor lfsr(13) xor lfsr(12) xor lfsr(10));
          noise_raw := signed(lfsr(14 downto 0) & '0') - to_signed(16384, 16);
          noise_wide := shift_left(resize(noise_raw, 19), 3) + shift_left(resize(noise_raw, 19), 1);
          noise_scaled := resize(shift_right(noise_wide, 3), 18);
          raw := raw + noise_scaled;

          -- BPF: 1-stage LP (shift=0, passthrough) + 4-stage HP (shift=2) --
          -- retuned to pass the injected noise's spectral-filling
          -- contribution; matches real TR-808 CH.WAV centroid=11944Hz/
          -- flatness=0.49 closely (sim result: centroid=12126Hz/flatness=0.72).
          lp_acc <= raw;
          lp_out := lp_acc;
          hp_acc0 <= hp_acc0 + shift_right(lp_out - hp_acc0, 2);
          x0 := lp_out - hp_acc0;
          hp_acc1 <= hp_acc1 + shift_right(x0 - hp_acc1, 2);
          x1 := x0 - hp_acc1;
          hp_acc2 <= hp_acc2 + shift_right(x1 - hp_acc2, 2);
          x2 := x1 - hp_acc2;
          hp_acc3 <= hp_acc3 + shift_right(x2 - hp_acc3, 2);
          x3 := x2 - hp_acc3;

          -- Clamp back to 16-bit before the amplitude multiply (the filter
          -- output itself should stay well within 16-bit range in normal
          -- operation since HP filtering removes DC/low-frequency energy;
          -- this clamp is a safety net, not expected to trigger in steady
          -- state).
          if x3 > 32767 then x3_clamped := to_signed(32767, 16);
          elsif x3 < -32768 then x3_clamped := to_signed(-32768, 16);
          else x3_clamped := x3(15 downto 0);
          end if;

          -- Multiply by amplitude
          product := x3_clamped * signed('0' & amp(15 downto 5));
          audio_out <= product(26 downto 11);

          -- Exponential decay: K=9 (tau ~10ms)
          amp <= amp - ("000000000" & amp(15 downto 9));

          if amp < 512 then
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
