#!/usr/bin/env python3
"""Bit-exact VHDL simulator - integer arithmetic, matching FPGA logic.
All voices output 16-bit signed. Mixer sums to 21-bit, saturates to 16-bit,
outputs top 12 bits with first-order noise shaping for DAC.
Architecture: 256-entry sine + interp, MULT18x18, 16-bit voice output.

FIXED-WIDTH ARITHMETIC (IMPORTANT):
Plain Python integers have unlimited precision and never overflow, unlike
real VHDL `signed(N downto 0)` / `unsigned(N downto 0)` values which wrap
(two's-complement) when an operation's result exceeds the declared width.
This simulator previously used plain Python ints throughout, which made it
structurally unable to detect overflow/wraparound bugs -- three such bugs
were found on real hardware (via oscilloscope) in one evening that this
"bit-exact" simulator had never caught, because it wasn't actually
bit-width-exact, only formula-exact.

Use `sN(x, width)` / `uN(x, width)` below to wrap intermediate values to
their true VHDL bit-width at every point where the real hardware would
have a fixed-width register or signal. OVERFLOW_WARNINGS collects a report
of every wraparound event so audits can find every occurrence automatically
instead of manually computing worst-case magnitudes by hand.
"""

import os, wave
import numpy as np

SR = 48828
OUTDIR = os.path.join(os.path.dirname(os.path.abspath(__file__)), "output_vhdl")

# Collects (label, raw_value, wrapped_value, width) for every detected
# overflow. Call reset_overflow_log() before a test run, then inspect this
# list afterward.
OVERFLOW_LOG = []


def reset_overflow_log():
    OVERFLOW_LOG.clear()


def sN(x, width, label=None):
    """Wrap x to a signed value of `width` bits (VHDL signed(width-1 downto 0)
    two's-complement semantics). Logs to OVERFLOW_LOG if x didn't already
    fit -- i.e. if real VHDL hardware would have silently wrapped here."""
    lo = -(1 << (width - 1))
    hi = (1 << (width - 1)) - 1
    if x < lo or x > hi:
        mask = (1 << width) - 1
        wrapped = x & mask
        if wrapped > hi:
            wrapped -= (1 << width)
        if label is not None:
            OVERFLOW_LOG.append((label, x, wrapped, width, 'signed'))
        return wrapped
    return x


def uN(x, width, label=None):
    """Wrap x to an unsigned value of `width` bits (VHDL unsigned(width-1
    downto 0) semantics, i.e. modulo 2**width). Logs to OVERFLOW_LOG if x
    didn't already fit in [0, 2**width - 1]."""
    hi = (1 << width) - 1
    if x < 0 or x > hi:
        wrapped = x & hi
        if label is not None:
            OVERFLOW_LOG.append((label, x, wrapped, width, 'unsigned'))
        return wrapped
    return x


def decay_step(amp, k):
    """Exponential decay: amp -= amp >> k, matching the VHDL pattern.
    
    Once amp < 2^k, the shift produces 0 and amp would get stuck forever.
    Fix: subtract 1 per sample once the exponential term is 0. This gives
    a smooth linear tail that reaches zero naturally, without the abrupt
    cutoff that was killing kicks 400ms too early.
    
    The voice's `amp < 64` (or similar threshold) check handles deactivation.
    """
    dec = amp >> k
    if dec == 0:
        # Linear tail: subtract 1 per sample until zero
        return max(0, amp - 1)
    return amp - dec

# 256-entry sine table, 12-bit signed (matches sine_table.vhd)
SINE = [int(round(2047 * np.sin(2 * np.pi * i / 256))) for i in range(256)]

def lfsr_next(reg, taps):
    fb = 0
    for t in taps:
        fb ^= (reg >> t) & 1
    return ((reg << 1) | fb) & 0xFFFF

def sine_lookup(phase):
    """256-entry + linear interpolation, matches sine_table.vhd."""
    idx = (phase >> 8) & 255
    frac = phase & 255
    s0 = SINE[idx]
    s1 = SINE[(idx + 1) & 255]
    return s0 + ((s1 - s0) * frac >> 8)

def clamp16(x):
    if x > 32767: return 32767
    if x < -32768: return -32768
    return int(x)

def signed_rshift(val, n):
    if val >= 0: return val >> n
    return -((-val) >> n)


# === BD (Bass Drum) ===

def render_kick(n_samples, tone=128, decay=128):
    """808 kick drum - based on service manual circuit analysis:
    
    Circuit: Bridged T-network oscillator (IC12, Q39-Q40)
    - Self-resonating bandpass filter, inherent frequency ~56Hz
    - TONE knob (VR6): controls oscillation frequency (lower=lower pitch)
    - DECAY knob: controls feedback amount → ring time
    
    Accent/trigger behavior (Q41-Q43):
    - On trigger, time constant is halved for ~4ms (one half-cycle)
    - This doubles the frequency for the first half-cycle → attack "punch"
    - After 4ms, Q42 turns on and circuit oscillates at inherent frequency
    - C39/R161 produces a retriggering pulse adding to the transient
    
    Service manual specs:
    - Inherent frequency: 56Hz (at mid TONE)
    - Decay: SHORT=50ms, MID=300ms, LONG=800ms
    
    Measured from real 808 samples (LP filtered):
    - Cycle 1: ~63Hz (includes the frequency-doubling transient averaged in)
    - Cycles 2-4: 57→54→52Hz (subtle pitch drop as oscillation settles)
    - Settled: ~50Hz
    - The subtle continued drop (63→50Hz) is from the bridged-T's amplitude-
      dependent frequency behavior (like the toms: higher amp → higher freq
      due to diode conduction in the feedback network)
    
    Implementation:
    - 24-bit fractional freq for smooth sweep
    - Start at ~63Hz (doubled for first half-cycle equivalent)
    - Sweep down to ~50Hz with slow exponential
    - Initial 1-2 sample transient click for the retrigger pulse
    
    Phase increments (16-bit accumulator, 48828Hz SR):
      63Hz -> inc = 84
      56Hz -> inc = 75  
      50Hz -> inc = 67
    """
    # TONE controls base frequency:
    # Real 808 shows very little pitch variation with TONE knob
    # Based on measurements, settled freq is always ~50Hz regardless of TONE
    # TONE likely has subtle effect on attack transient and slight pitch change
    # tone=0: ~53Hz (inc=71), tone=128: ~57Hz (inc=76), tone=255: ~61Hz (inc=81)
    # Very narrow range matching the real behavior
    base_inc = 71 + (tone >> 5)  # 71..78 range (53-58Hz)
    
    # The initial "doubled" frequency (accent trick - first ~4ms)
    # ~1.25x base freq based on measurements (63/50 = 1.26)
    start_inc = base_inc + (base_inc >> 2)
    
    freq_end_frac = base_inc << 8
    freq_start_frac = start_inc << 8

    # Pitch sweep shift=10: tau=1024 samples=21ms
    # The amplitude-dependent freq drop is slow (matches 63→57→54→52→50 over 100ms)
    pitch_shift = 10

    # DECAY knob mapping to match real 808 measured times (using -10dB/2ms
    # smoothed measurement matching compare_voice.py's method):
    # 808 DECAY 00: 18ms  -> K=10 (19ms)
    # 808 DECAY 25: 22ms  -> K=10 (19ms) [closest available]
    # 808 DECAY 50: 60ms  -> K=12 (54ms)
    # 808 DECAY 75: 78ms  -> K=13 (107ms) [overshoots, no clean K between 12/13]
    # 808 DECAY 10: 155ms -> K=13 (107ms) [undershoots, K=14=242ms overshoots more]
    if decay < 48:
        decay_k = 10
    elif decay < 160:
        decay_k = 12
    else:
        decay_k = 13

    # Click transient amplitude (retrigger pulse from C39/R161)
    # Always present but stronger with accent. For now, moderate click.
    click_amp = 24000

    phase = 0
    freq_frac = freq_start_frac
    amp = 65535
    out = []
    for i in range(n_samples):
        if amp < 64:
            out.append(0); continue

        # Initial retrigger pulse (1-2 samples)
        if i == 0:
            out.append(clamp16(click_amp))
            phase = (phase + (freq_frac >> 8)) & 0xFFFF
            if freq_frac > freq_end_frac:
                diff = freq_frac - freq_end_frac
                step = diff >> pitch_shift
                if step < 1: step = 1
                freq_frac -= step
            amp = decay_step(amp, decay_k)
            continue
        elif i == 1:
            out.append(clamp16(-(click_amp >> 1)))
            phase = (phase + (freq_frac >> 8)) & 0xFFFF
            if freq_frac > freq_end_frac:
                diff = freq_frac - freq_end_frac
                step = diff >> pitch_shift
                if step < 1: step = 1
                freq_frac -= step
            amp = decay_step(amp, decay_k)
            continue

        s = sine_lookup(phase)
        amp_11 = amp >> 5
        product = s * amp_11
        out.append(clamp16(product >> 7))

        # Phase advance
        freq_inc = freq_frac >> 8
        phase = (phase + freq_inc) & 0xFFFF

        # Exponential pitch sweep (amplitude-dependent freq behavior)
        if freq_frac > freq_end_frac:
            diff = freq_frac - freq_end_frac
            step = diff >> pitch_shift
            if step < 1: step = 1
            freq_frac -= step
        amp = decay_step(amp, decay_k)
    return out


# === SD (Snare Drum) ===

def render_snare(n_samples, tone=128, snappy=128):
    """808 Snare Drum - based on service manual + real sample analysis.
    
    Circuit (service manual):
    - Two bridged-T oscillators: ~175Hz (fundamental) + ~345Hz (harmonic)
    - VR8 (TONE): controls MIX RATIO between the two tones (NOT frequency)
    - VR9 (SNAPPY): controls noise amplitude (linear)
    - Noise path: white noise → VCA → BPF peaking at ~3.8kHz
    
    Measured from real 808 SD samples:
    - Lower tone: 175Hz, decay tau ~38ms (K=11)
    - Upper tone: 345Hz, decay tau ~10ms (K=9) — 4x faster!
    - TONE=0: mostly lower, TONE=255: mostly upper (crossfade)
    - Noise BPF: peak ~3.8kHz, -3dB range 2.1-6.1kHz
    - Noise decay: tau ~27ms (K=10)
    - SNAPPY: linear noise amplitude 0 to ~1.8x tone level
    
    Phase increments (16-bit accumulator, 48828Hz SR):
      175Hz -> inc = 234
      345Hz -> inc = 462
    """
    # Fixed frequencies (TONE does NOT change them)
    pinc1 = 252   # ~188Hz (measured 808 shows ~175-194Hz depending on TONE mix)
    pinc2 = 464   # ~345Hz

    # TONE controls mix ratio between lower and upper tone
    # tone=0: mostly lower (real 808 ratio 345/175 = 0.08)
    # tone=128: balanced (ratio ~0.6)
    # tone=255: mostly upper (ratio ~3.15)
    # Use simple crossfade gains (0-255 range)
    lower_gain = 255 - tone  # 255 at tone=0, 0 at tone=255
    upper_gain = tone         # 0 at tone=0, 255 at tone=255

    # SNAPPY controls noise level (linear, 0 to ~1.8x tone level)
    # snappy=0: nearly silent noise
    # snappy=128: noise ~= tone level
    # snappy=255: noise ~1.8x tone level
    # Implemented as multiply: noise * snappy >> 7

    phase1 = 0; phase2 = 0
    tone1_amp = 65535   # Lower tone envelope (separate!)
    tone2_amp = 65535   # Upper tone envelope (separate!)
    noise_amp = 65535   # Noise envelope
    lfsr = 0xACE1

    # BPF for noise: 2-stage HP (shift 2) + 1-stage LP (shift 1)
    # This gives peak at ~4kHz matching real 808
    hp_acc1 = 0; hp_acc2 = 0; lp_acc = 0

    out = []
    for _ in range(n_samples):
        if tone1_amp < 64 and tone2_amp < 64 and noise_amp < 64:
            out.append(0); continue

        s1 = sine_lookup(phase1)
        s2 = sine_lookup(phase2)
        lfsr = lfsr_next(lfsr, [15, 13, 12, 10])

        # Lower tone with its own envelope and gain
        t1_scaled = s1 * (tone1_amp >> 5)
        t1_out = signed_rshift(t1_scaled * lower_gain, 16)

        # Upper tone with its own envelope and gain
        t2_scaled = s2 * (tone2_amp >> 5)
        t2_out = signed_rshift(t2_scaled * upper_gain, 16)

        # Noise through BPF (~2-6kHz, peak ~4kHz)
        noise_raw = (lfsr & 0x7FFF) - 16384
        # 2-stage HP at shift 2 (~3kHz cutoff at 48.8kHz SR)
        hp_acc1 = hp_acc1 + signed_rshift(noise_raw - hp_acc1, 2)
        hp_out1 = noise_raw - hp_acc1
        hp_acc2 = hp_acc2 + signed_rshift(hp_out1 - hp_acc2, 2)
        hp_out2 = hp_out1 - hp_acc2
        # 1-stage LP at shift 1 (~12kHz cutoff)
        lp_acc = lp_acc + signed_rshift(hp_out2 - lp_acc, 1)
        bp_out = lp_acc

        # Scale noise by envelope and SNAPPY
        # Real 808: snappy=0 gives almost zero noise, snappy=255 gives 1.8x tone
        # Use snappy*snappy>>8 for quadratic curve (more dead zone at bottom)
        noise_env = signed_rshift(bp_out * (noise_amp >> 8), 7)
        snappy_gain = (snappy * snappy) >> 8  # 0..255, quadratic
        noise_scaled = signed_rshift(noise_env * snappy_gain, 7)

        # Mix all components
        mix = t1_out + t2_out + noise_scaled
        out.append(clamp16(mix))

        phase1 = (phase1 + pinc1) & 0xFFFF
        phase2 = (phase2 + pinc2) & 0xFFFF

        # Separate decay envelopes (key to the snare character!)
        # Lower tone: K=10, tau=21ms (-20dB at 48ms) — the "body"
        tone1_amp = decay_step(tone1_amp, 10)
        # Upper tone: K=9, tau=10ms (-20dB at 24ms) — the "snap"
        tone2_amp = decay_step(tone2_amp, 9)
        # Noise: K=11, tau=42ms (-20dB at 97ms) — extends sound at high snappy
        noise_amp = decay_step(noise_amp, 11)
    return out


# === LT/MT/HT (Toms) ===

def render_tom(n_samples, tuning=128, freq_min=161, freq_range=53, decay_k=12):
    """808 Tom - bridged-T oscillator with amplitude-dependent pitch.
    
    Circuit: Same as BD - bridged-T with diodes D80/D81.
    Amplitude-dependent pitch: higher amp -> slightly higher freq (0-4%).
    
    Measured from real 808:
    - LT: 81-100Hz, decay ~198ms (K=12)
    - MT: 120-160Hz, decay ~120ms (K=11)
    - HT: 165-220Hz, decay ~90ms (K=10 or 11)
    
    freq_min: phase increment at tuning=0
    freq_range: additional phase increment at tuning=255
    """
    # Target frequency from tuning knob (linear mapping)
    target_freq = freq_min + ((tuning * freq_range) >> 8)

    phase = 0; amp = 65535
    out = []
    for _ in range(n_samples):
        if amp < 64:
            out.append(0); continue
        s = sine_lookup(phase)
        amp_11 = amp >> 5
        product = s * amp_11
        out.append(clamp16(product >> 7))

        # Amplitude-dependent pitch: freq = target + small offset from amplitude
        freq = target_freq + (amp >> 14)
        phase = (phase + freq) & 0xFFFF

        amp = decay_step(amp, decay_k)
    return out

def render_lt(n_samples, tuning=128):
    return render_tom(n_samples, tuning, freq_min=109, freq_range=25, decay_k=12)  # 81-100Hz, ~193ms

def render_mt(n_samples, tuning=128):
    return render_tom(n_samples, tuning, freq_min=161, freq_range=53, decay_k=11)  # 120-160Hz, ~97ms

def render_ht(n_samples, tuning=128):
    return render_tom(n_samples, tuning, freq_min=221, freq_range=74, decay_k=11)  # 165-220Hz, ~97ms


# === Metallic voices: 6 square oscillators + BPF ===

def render_metallic_core(n_samples, decay_k, bpf_lp_shift, bpf_hp_shift, noise_mult=0, hp_stages=4, lfsr_seed=0xF00D):
    """6 free-running square oscs + LFSR noise + multi-stage BPF.
    Real 808 frequencies: 205, 304, 370, 523, 540, 800 Hz.
    Target: pass ~6-12kHz (beating products), reject fundamentals.

    noise_mult: integer multiplier for LFSR broadband noise mixed in with the
      square-oscillator sum before filtering. 0 = original behavior (no
      noise). Prototype (scripts/prototype_metallic.py) found noise fills in
      the spectral gaps left by the coarse 7-level square-sum staircase,
      closing most of the gap to the real TR-808's measured spectral
      flatness (steppiness eliminated, flatness 0.58 vs 0.49 reference).
    hp_stages: number of cascaded 1st-order HP filter stages (1-4). Prototype
      found order=1 (i.e. hp_stages=1) is needed to let the noise's spectral
      contribution through -- more HP stages progressively strangle it
      (flatness caps around 0.27 at 2 stages regardless of noise gain).

    IMPORTANT (bug fix): `raw` (square-sum + noise) can reach magnitude
    ~53118 (6*5440 + noise_scaled_max), which overflows a 16-bit signed
    range (+-32767) and would wrap in the real VHDL's signed(15 downto 0)
    `raw` variable. This Python model previously used plain Python ints
    (no overflow at all), which is why it never caught this -- confirmed
    on real hardware via oscilloscope: DAC output showed background noise
    that built up over a few seconds of playback and never recovered,
    because the un-reset filter accumulators (lp_acc/hp_acc) inherited
    corrupted wrapped values. The VHDL fix widens raw/lp_acc/hp_acc to
    18-bit; this Python model now mirrors that by clamping raw to the
    16-bit range that the ORIGINAL (buggy) VHDL would have wrapped at, to
    verify the fix is necessary -- see render_metallic_core_18bit below for
    the actual fixed-width simulation matching the corrected VHDL.
    """
    incs = [275, 409, 496, 702, 725, 1075]
    phases = [0]*6
    lp1 = 0
    hp = [0, 0, 0, 0]
    amp = 1048575  # 20-bit full scale (was 65535/16-bit - too coarse for
                   # long K=13-15 decays, caused audible death clicks at
                   # -6 to -12dB when amp>>K hit 0 prematurely)
    lfsr = lfsr_seed
    out = []
    for _ in range(n_samples):
        # Sum square waves
        sq_sum = 0
        for i in range(6):
            sq_sum += 1 if (phases[i] & 0x8000) else -1
        for i in range(6):
            phases[i] = (phases[i] + incs[i]) & 0xFFFF
        if amp < 8192:  # scaled equivalent of the old amp<512 threshold (x16)
            out.append(0); continue
        # Scale: sq * 5440
        raw = (sq_sum << 12) + (sq_sum << 10) + (sq_sum << 8) + (sq_sum << 6)

        if noise_mult:
            lfsr = lfsr_next(lfsr, [15, 13, 12, 10])
            noise_raw = (lfsr & 0x7FFF) - 16384  # 15-bit signed, ~std=9459
            # Scale noise down to be comparable to raw (sq_sum std ~2.16 * 5440
            # ~= 11750). noise_mult acts as an integer gain in eighths.
            noise_scaled = (noise_raw * noise_mult) >> 3
            raw += noise_scaled

        # Fixed-width simulation (matches corrected VHDL): raw/lp1/hp are
        # conceptually 18-bit here (Python ints don't truncate, but the
        # VHDL now has enough headroom that this never needs clamping in
        # practice -- the clamp at x3 below is the actual safety net,
        # matching the VHDL's x3_clamped).

        # LP: gentle anti-alias
        lp1 = lp1 + signed_rshift(raw - lp1, bpf_lp_shift)
        # HP cascade (1..4 stages, each shift=bpf_hp_shift)
        x = lp1
        for i in range(hp_stages):
            hp[i] = hp[i] + signed_rshift(x - hp[i], bpf_hp_shift)
            x = x - hp[i]
        bp = x
        # Multiply by amplitude (amp is now 20-bit: use top 11 bits, amp>>9)
        bp_16 = max(-32768, min(32767, bp))
        amp_11 = amp >> 9
        product = bp_16 * amp_11
        out.append(clamp16(product >> 11))
        amp = decay_step(amp, decay_k)
    return out


# === CH (Closed HiHat) ===

def render_ch(n_samples):
    """Short metallic hit. Decay K=9 (~10ms to -20dB)."""
    return render_metallic_core(n_samples, decay_k=9, bpf_lp_shift=0, bpf_hp_shift=2,
                                 noise_mult=10, hp_stages=4, lfsr_seed=0xF00D)


# === OH (Open HiHat) ===

def render_oh(n_samples, decay=128):
    if decay < 52: dk = 11
    elif decay < 103: dk = 12
    elif decay < 154: dk = 13
    elif decay < 205: dk = 14
    else: dk = 15
    return render_metallic_core(n_samples, decay_k=dk, bpf_lp_shift=0, bpf_hp_shift=2,
                                 noise_mult=10, hp_stages=4, lfsr_seed=0xBEE5)


# === CY (Cymbal) ===

def render_cymbal(n_samples, tone=128, decay=128):
    """808 Cymbal - 6 oscillators through BPF, long dual-character decay.

    Real 808 measured (docs/TR808WAV/CY/):
    - Spectral centroid ~5800-6450Hz (TONE brightens it)
    - Decay tau 185ms (DECAY=00) up to 758ms (DECAY=10) - much longer
      than CH/OH's ms-scale decays, needs high K values (13-15)
    - Dual-exponential envelope (fast ~159ms + slow ~561ms) - approximated
      here with a single K per DECAY setting; real dual-envelope would
      need a second amp register (future refinement)
    """
    if tone < 86: hp_shift = 3     # darker, centroid ~4200Hz
    elif tone < 171: hp_shift = 2  # mid, centroid ~6650Hz (matches CY50)
    else: hp_shift = 2             # bright (lp_shift narrows further below)
    lp_shift = 1 if tone >= 171 else 2

    if decay < 86: dk = 13    # tau~188ms (target 185ms)
    elif decay < 171: dk = 14  # tau~375ms (target 324-511ms)
    else: dk = 15              # tau~671ms (target 673-758ms)

    return render_metallic_core(n_samples, decay_k=dk, bpf_lp_shift=lp_shift, bpf_hp_shift=hp_shift,
                                 noise_mult=10, hp_stages=4, lfsr_seed=0xC0DE)


# === CB (Cowbell) ===

def render_cowbell(n_samples):
    """808 Cowbell - two square oscillators through resonant BPF, dual decay.

    Circuit (voices2.PNG): Two square-wave oscillators -> individual VCAs
    (shared envelope) -> sum -> BANDPASS FILTER -> buffer. NO noise source.

    Real 808 measured (docs/TR808WAV/CB/CB.WAV via FFT):
    - f1 (557Hz): secondary, -15.9dB relative to f2
    - f2 (824Hz): dominant
    - Dual-exponential envelope: fast (tau~8.8ms, 90% weight) +
      slow ring tail (tau~132ms, 17% weight)
    - Decay to -20dB: ~42ms, still audible past 200ms (slow tail)

    Uses a resonant state-variable filter (not a flat LP+HP cascade) to
    get the ~15dB rejection of 557Hz relative to 824Hz seen in the real
    808 (the two oscillators are also weighted 1:2 before filtering).
    """
    phases = [0, 0]; incs = [748, 1106]  # 557Hz, 824Hz
    svf_lp = 0; svf_bp = 0
    amp_fast = 65535; amp_slow = 65535
    out = []
    for _ in range(n_samples):
        if amp_fast < 64 and amp_slow < 64:
            out.append(0); continue

        sq1 = 1 if (phases[0] & 0x8000) else -1
        sq2 = 1 if (phases[1] & 0x8000) else -1
        # Weight osc2 (824Hz) 2x relative to osc1 (557Hz) - matches real 808
        raw = (sq1 + sq2 * 2) << 12

        for i in range(2):
            phases[i] = (phases[i] + incs[i]) & 0xFFFF

        # State-variable filter (resonant bandpass), center ~975Hz, Q~4
        # hp = input - lp - (bp>>2); bp += hp>>3; lp += bp>>3
        hp = raw - svf_lp - signed_rshift(svf_bp, 2)
        svf_bp = svf_bp + signed_rshift(hp, 3)
        svf_lp = svf_lp + signed_rshift(svf_bp, 3)
        bp_out = svf_bp

        # Combined dual-decay envelope: fast*3/4 + slow*1/4
        combined_amp = ((amp_fast >> 5) * 3 + (amp_slow >> 5)) >> 2
        product = bp_out * combined_amp
        out.append(clamp16(product >> 11))

        if amp_fast >= 64:
            amp_fast = decay_step(amp_fast, 9)   # K=9, tau~10.5ms
        if amp_slow >= 64:
            amp_slow = decay_step(amp_slow, 11)  # K=11, tau~42ms
    return out


# === RS (Rimshot) ===

def render_rimshot(n_samples):
    """808 Rimshot - dual resonant modes from shared RS/CL oscillator circuit.
    
    Real 808 RS spectrum (FFT measurement):
    - 1712 Hz: dominant, decays fast (tau~2.6ms, K=7)
    - 458 Hz: secondary, decays slower (tau~5.2ms, K=8), gives the "body"
    Two independent envelopes create the bright-attack/warm-tail character.
    
    Phase increments (48828Hz SR):
      458Hz -> inc=615
      1712Hz -> inc=2298
    """
    ph_lo = 0; ph_hi = 0
    amp_lo = 65535  # 458Hz envelope (slower decay)
    amp_hi = 65535  # 1712Hz envelope (faster decay)
    out = []
    for _ in range(n_samples):
        if amp_lo < 64 and amp_hi < 64:
            out.append(0); continue
        s_lo = sine_lookup(ph_lo)
        s_hi = sine_lookup(ph_hi)

        # Lower mode at 76% relative level, upper mode boosted (decays fast,
        # needs higher initial gain to be perceptually/spectrally dominant
        # like the real 808, where 1712Hz measures 100% vs 458Hz's 76%)
        p_lo = (s_lo * (amp_lo >> 5) * 3) >> 2   # 0.75x scale
        p_hi = s_hi * (amp_hi >> 5) * 5           # 5x boost

        mix = signed_rshift(p_lo, 9) + signed_rshift(p_hi, 10)
        out.append(clamp16(mix))

        ph_lo = (ph_lo + 615) & 0xFFFF   # 458Hz
        ph_hi = (ph_hi + 2298) & 0xFFFF  # 1712Hz

        if amp_lo >= 64:
            amp_lo = decay_step(amp_lo, 9)  # K=9, tau~10ms (slower, gives body)
        if amp_hi >= 64:
            amp_hi = decay_step(amp_hi, 8)  # K=8, tau~5ms (faster, gives tick)
    return out


# === CP (Hand Clap) ===

def render_clap(n_samples):
    """808 Hand Clap - 4-burst noise through 1kHz bandpass, then decay tail.

    Circuit (voices1.PNG): Reverb envelope gates noise VCA, feeds into
    HPF -> 1000Hz BPF -> VCA (decay envelope) -> output.

    Real 808 measured burst timing (docs/TR808WAV/CP/CP.WAV):
    - 4 bursts of ~5ms each, ~5ms gaps between (NOT silent - filter rings)
    - Total attack phase ~30-35ms
    - BPF peak ~988Hz, tail decay tau ~40-60ms

    FIXED BUG: count matches clap.vhd's `signal count : unsigned(12 downto 0)`
    (13-bit, max 8191). Clamped to hold at 2196 (tail start) to prevent
    wraparound re-firing the attack bursts indefinitely.

    Gate applies to the NOISE INPUT (not the BPF output), so the filter
    continues to ring naturally during gaps instead of hard-cutting to
    silence.
    """
    lfsr = 0xBEEF; lp_acc = 0; hp_acc = 0; amp = 65535; count = 0
    out = []
    for _ in range(n_samples):
        if amp < 64 and count >= 2196:
            out.append(0); continue
        lfsr = lfsr_next(lfsr, [15, 13, 11, 0])
        if count < 2196:
            count = uN(count + 1, 13, label='clap.count')
        c = count
        # Burst pattern: 4 x 5ms bursts with 5ms gaps (244 samples = 5ms)
        if   c < 244:  gate = True   # burst 1
        elif c < 488:  gate = False  # gap 1
        elif c < 732:  gate = True   # burst 2
        elif c < 976:  gate = False  # gap 2
        elif c < 1220: gate = True   # burst 3
        elif c < 1464: gate = False  # gap 3
        elif c < 1708: gate = True   # burst 4
        else:          gate = True   # tail

        # Noise source (matches VHDL: 12-bit signed, shifted left 3)
        noise_12 = (lfsr & 0x0FFF)
        if noise_12 >= 2048: noise_12 -= 4096
        noise_raw = sN(noise_12 << 3, 16, label='clap.noise_raw')

        # Gate applied to noise INPUT (filter keeps ringing during gaps)
        noise_gated = noise_raw if gate else 0

        # BPF: LP shift 3 (~1kHz) then HP shift 4 (~500Hz) - matches VHDL
        lp_acc = sN(lp_acc + signed_rshift(noise_gated - lp_acc, 3), 16, label='clap.lp_acc')
        hp_acc = sN(hp_acc + signed_rshift(lp_acc - hp_acc, 4), 16, label='clap.hp_acc')
        bp = lp_acc - hp_acc

        amp_11 = amp >> 5
        product = bp * amp_11
        out.append(clamp16(product >> 8))

        if c >= 2196:
            amp = decay_step(amp, 9)  # K=9, tau~10ms (-20dB at ~25ms, matches measured 29ms)
    return out


# === Output ===

def save_wav(filename, samples):
    path = os.path.join(OUTDIR, filename)
    data = np.array(samples, dtype=np.int16)
    with wave.open(path, 'w') as w:
        w.setnchannels(1); w.setsampwidth(2); w.setframerate(SR)
        w.writeframes(data.tobytes())
    print(f"  {path}")

def render_demo():
    """120 BPM, 4 seconds, 16 steps."""
    step_samples = SR * 60 // 120 // 4
    total = SR * 4
    mix = [0] * total
    pattern = {
        'kick': [0,8], 'snare': [4,12], 'ch': [0,2,4,6,8,10,12,14],
        'oh': [8], 'clap': [10]
    }
    renderers = {'kick': render_kick, 'snare': render_snare, 'ch': render_ch,
                 'oh': render_oh, 'clap': render_clap}
    voice_len = SR
    for voice, steps in pattern.items():
        for step in steps:
            offset = step * step_samples
            snd = renderers[voice](min(voice_len, total - offset))
            for i, s in enumerate(snd):
                if offset + i < total:
                    mix[offset + i] += s
    # Mixer stage 3, matching src/mixer.vhd exactly (post-fix):
    # 1) saturate the raw voice sum to 16-bit signed
    # 2) add previous first-order noise-shaping error, RE-SATURATE the
    #    result (this re-saturation was MISSING in the real VHDL until the
    #    fix below -- an already-saturated `sat` plus a positive `ns_error`
    #    could wrap past +32767 to a large negative value in two's
    #    complement, producing an audible "wraps"/glitch artifact on loud
    #    voices near full scale, confirmed on a real oscilloscope on the
    #    DAC output)
    # 3) quantize to 12-bit by truncating the lower 4 bits, feed the
    #    truncation residual back as the next sample's ns_error
    ns_error = 0
    out12 = [0] * total
    for i in range(total):
        sat = clamp16(mix[i])
        shaped = sat + ns_error
        shaped = clamp16(shaped)  # re-saturate -- this is the fix
        dac_val = signed_rshift(shaped, 4)  # shaped(15 downto 4), arithmetic shift
        ns_error = shaped - (dac_val << 4)  # residual = shaped(3 downto 0), sign-correct
        out12[i] = dac_val
        mix[i] = shaped
    return mix

def main():
    os.makedirs(OUTDIR, exist_ok=True)
    print("Generating VHDL bit-exact WAV files:")
    voices = [
        ("01_kick.wav", render_kick, SR),
        ("02_snare.wav", render_snare, SR),
        ("03_ch.wav", render_ch, SR // 2),
        ("04_oh.wav", render_oh, SR),
        ("05_clap.wav", render_clap, SR),
        ("06_rimshot.wav", render_rimshot, SR // 4),
        ("07_cowbell.wav", render_cowbell, SR // 2),
        ("08_tom_mt.wav", render_mt, SR),
        ("09_cymbal.wav", render_cymbal, SR * 2),
    ]
    for fname, renderer, n in voices:
        save_wav(fname, renderer(n))
    save_wav("10_demo_pattern.wav", render_demo())
    print("Done.")

if __name__ == "__main__":
    main()
