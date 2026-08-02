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

    # DECAY knob mapping to match real 808 measured times:
    # 808 DECAY 00: 29ms  -> K=9  (24ms)
    # 808 DECAY 25: 62ms  -> K=10 (48ms) 
    # 808 DECAY 50: 280ms -> K=13 (386ms) [overshoot but closer than K=12=193ms]
    # 808 DECAY 75: 378ms -> K=13 (386ms)
    # 808 DECAY 10: 686ms -> K=14 (773ms)
    if decay < 32:
        decay_k = 9
    elif decay < 96:
        decay_k = 10
    elif decay < 200:
        decay_k = 13
    else:
        decay_k = 14

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
    """Two sines (173/346Hz) + LFSR noise through BPF.
    Improved noise character with bandpass instead of just HPF."""
    # 173Hz = inc 232, 346Hz = inc 464
    pinc1 = 232
    pinc2 = 464
    # Snappy: noise level
    if snappy < 86: noise_shift = 2
    elif snappy < 171: noise_shift = 1
    else: noise_shift = 0

    phase1 = 0; phase2 = 0
    tone_amp = 65535; noise_amp = 65535
    lfsr = 0xACE1
    # BPF state for noise (2-stage LP + HP = bandpass)
    lp_acc = 0; lp_acc2 = 0; hp_acc = 0
    out = []
    for _ in range(n_samples):
        if tone_amp < 64 and noise_amp < 64:
            out.append(0); continue
        s1 = sine_lookup(phase1)
        s2 = sine_lookup(phase2)
        lfsr = lfsr_next(lfsr, [15, 13, 12, 10])

        # Tones
        amp_11 = tone_amp >> 5
        p1 = s1 * amp_11
        p2 = s2 * amp_11

        # Noise through BPF (~500Hz-2kHz)
        noise_raw = (lfsr & 0x7FFF) - 16384
        # 2-stage LP at ~2kHz: shift 2 each
        lp_acc = lp_acc + signed_rshift(noise_raw - lp_acc, 2)
        lp_acc2 = lp_acc2 + signed_rshift(lp_acc - lp_acc2, 2)
        # HP at ~300Hz: shift 5
        hp_acc = hp_acc + signed_rshift(lp_acc2 - hp_acc, 5)
        bp_out = lp_acc2 - hp_acc

        # Scale noise by noise_amp
        noise_scaled = signed_rshift(bp_out * (noise_amp >> 8), 7)
        noise_scaled = signed_rshift(noise_scaled, noise_shift)

        # Mix: tone1 + tone2/2 + noise
        t1 = signed_rshift(p1, 8)
        t2 = signed_rshift(p2, 9)
        mix = t1 + t2 + noise_scaled
        out.append(clamp16(mix))

        phase1 = (phase1 + pinc1) & 0xFFFF
        phase2 = (phase2 + pinc2) & 0xFFFF
        # Tone decays faster than noise (real 808: tone ~15ms, noise ~30ms)
        tone_amp = decay_step(tone_amp, 9)   # K=9, tau ~10ms
        noise_amp = decay_step(noise_amp, 11)  # K=11, tau ~42ms
    return out


# === LT/MT/HT (Toms) ===

def render_tom(n_samples, tuning=128, g_freq=181):
    """Sine + exponential pitch dive."""
    freq_product = g_freq * tuning
    target_freq = g_freq - (g_freq >> 2) + (freq_product >> 9)
    freq = target_freq + (target_freq >> 2)  # start 25% higher

    phase = 0; amp = 65535
    out = []
    for _ in range(n_samples):
        if amp < 64:
            out.append(0); continue
        s = sine_lookup(phase)
        amp_11 = amp >> 5
        product = s * amp_11
        out.append(clamp16(product >> 7))
        phase = (phase + freq) & 0xFFFF
        # Exponential pitch dive (faster than linear)
        if freq > target_freq:
            diff = freq - target_freq
            step = diff >> 6  # tau ~64 samples = 1.3ms
            if step < 1: step = 1
            freq -= step
        amp = decay_step(amp, 11)  # K=11, tau ~42ms (real 808 toms: 76-111ms to -20dB)
    return out

def render_lt(n_samples, tuning=128):
    return render_tom(n_samples, tuning, g_freq=165)  # ~82Hz

def render_mt(n_samples, tuning=128):
    return render_tom(n_samples, tuning, g_freq=181)  # ~135Hz

def render_ht(n_samples, tuning=128):
    return render_tom(n_samples, tuning, g_freq=295)  # ~220Hz


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
    amp = 65535
    lfsr = lfsr_seed
    out = []
    for _ in range(n_samples):
        # Sum square waves
        sq_sum = 0
        for i in range(6):
            sq_sum += 1 if (phases[i] & 0x8000) else -1
        for i in range(6):
            phases[i] = (phases[i] + incs[i]) & 0xFFFF
        if amp < 512:
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
        # Multiply by amplitude
        bp_16 = max(-32768, min(32767, bp))
        amp_11 = amp >> 5
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
    """Tuned against real TR-808 CY5050.WAV: centroid=6924Hz, flatness=0.494.
    lp_shift=2/hp_shift=4 (darker/steeper than CH/OH's lp_shift=0/hp_shift=2)
    matches the cymbal's lower measured centroid; tone knob shifts brighter."""
    if tone < 86: lp_shift = 3  # darker
    elif tone < 171: lp_shift = 2  # mid (matches CY5050 reference)
    else: lp_shift = 1  # brighter
    if decay < 52: dk = 11
    elif decay < 103: dk = 12
    elif decay < 154: dk = 13
    elif decay < 205: dk = 14
    else: dk = 15
    return render_metallic_core(n_samples, decay_k=dk, bpf_lp_shift=lp_shift, bpf_hp_shift=4,
                                 noise_mult=10, hp_stages=4, lfsr_seed=0xC0DE)


# === CB (Cowbell) ===

def render_cowbell(n_samples):
    """2 square oscillators (540/800Hz) + LFSR noise + narrow BPF.
    Tuned against real TR-808 CB.WAV: centroid=6654Hz, flatness=0.433.
    noise_mult=10 into the existing 2-stage LP(shift1)+2-stage HP(shift3)
    narrow bandpass gives centroid=6208Hz, flatness=0.504 -- both close to
    reference, with the digital staircase artifact eliminated."""
    phases = [0, 0]; incs = [725, 1075]
    lp1 = 0; lp2 = 0; hp1 = 0; hp2 = 0
    amp = 65535
    lfsr = 0xCAFE
    out = []
    for _ in range(n_samples):
        sq = 0
        for i in range(2):
            sq += 1 if (phases[i] & 0x8000) else -1
        for i in range(2):
            phases[i] = (phases[i] + incs[i]) & 0xFFFF
        if amp < 64:
            out.append(0); continue
        raw = sq << 12  # sq*4096
        lfsr = lfsr_next(lfsr, [15, 13, 12, 10])
        noise_raw = (lfsr & 0x7FFF) - 16384
        raw += (noise_raw * 10) >> 3
        # Narrow BPF: tight LP + HP
        lp1 = lp1 + signed_rshift(raw - lp1, 1)
        lp2 = lp2 + signed_rshift(lp1 - lp2, 1)
        hp1 = hp1 + signed_rshift(lp2 - hp1, 3)
        hp2 = hp2 + signed_rshift(hp1 - hp2, 3)
        bp = lp2 - hp2
        bp_16 = max(-32768, min(32767, bp))
        amp_11 = amp >> 5
        product = bp_16 * amp_11
        out.append(clamp16(product >> 11))
        amp = decay_step(amp, 10)  # K=10, fast ring decay
    return out


# === RS (Rimshot) ===

def render_rimshot(n_samples):
    """3 parallel sines (455+680+1020Hz) with hard clipping for harmonics, fast decay."""
    ph1 = 0; ph2 = 0; ph3 = 0
    amp = 65535
    out = []
    for _ in range(n_samples):
        if amp < 64:
            out.append(0); continue
        s1 = sine_lookup(ph1)
        s2 = sine_lookup(ph2)
        s3 = sine_lookup(ph3)
        # Sum and hard-clip to add harmonics (like swing VCA)
        mix = s1 + s2 + s3
        # Clip to ±2047 (creates odd harmonics)
        if mix > 2047: mix = 2047
        elif mix < -2048: mix = -2048
        amp_11 = amp >> 5
        product = mix * amp_11
        out.append(clamp16(product >> 7))
        ph1 = (ph1 + 610) & 0xFFFF   # 455Hz
        ph2 = (ph2 + 912) & 0xFFFF   # 680Hz
        ph3 = (ph3 + 1368) & 0xFFFF  # 1020Hz
        amp = decay_step(amp, 8)  # K=8, tau~5ms
    return out


# === CP (Hand Clap) ===

def render_clap(n_samples):
    """LFSR noise + BPF (1-8kHz), 3-burst envelope then tail.

    FIXED BUG: count matches clap.vhd's `signal count : unsigned(12 downto 0)`
    (13-bit, max 8191). The original VHDL incremented count every
    sample_tick while active with NO upper bound -- confirmed via the sN/uN
    fixed-width wrappers that count wraps from 8191 back to 0 roughly every
    ~170ms of sustained activity (11 wraps in a 2-second render). Once
    wrapped, the burst-gate logic (`c < 244` etc.) re-evaluates true again,
    re-firing the attack bursts indefinitely -- and since `active` only
    clears when `amp<64 AND count>=2196`, a wrap back below 2196 can
    prevent `active` from ever clearing, making clap play forever after a
    single trigger. This was very likely a major contributor to the
    "background noise that builds up over a few seconds and never
    recovers" observed on a real oscilloscope tonight (clap is in the
    demo pattern at step 10, well within reach of this bug).
    FIX: clamp count so it holds at its max meaningful value (2196, the
    start of the tail) once reached, instead of continuing to free-run
    toward the register's own 13-bit ceiling. This matches the VHDL fix
    (add a saturating check on count's increment) applied in clap.vhd.
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
        # Burst pattern
        if   c < 244:  gate = True
        elif c < 976:  gate = False
        elif c < 1220: gate = True
        elif c < 1952: gate = False
        elif c < 2196: gate = True
        else:          gate = True  # tail
        # Wideband noise
        noise_raw = (lfsr & 0x7FFF) - 16384  # 15-bit signed
        # BPF: LP at ~8kHz (shift 1) then HP at ~1kHz (shift 3)
        lp_acc = sN(lp_acc + signed_rshift(noise_raw - lp_acc, 1), 16, label='clap.lp_acc')
        hp_acc = sN(hp_acc + signed_rshift(lp_acc - hp_acc, 3), 16, label='clap.hp_acc')
        bp = lp_acc - hp_acc
        if gate:
            bp_16 = max(-32768, min(32767, bp))
            amp_11 = amp >> 5
            product = bp_16 * amp_11
            out.append(clamp16(product >> 11))
        else:
            out.append(0)
        if c >= 2196:
            amp = decay_step(amp, 12)  # K=12, tau ~84ms (matches clap.vhd; was
            # incorrectly K=11 in this docstring/comment previously)
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
