#!/usr/bin/env python3
"""Bit-exact VHDL simulator - integer arithmetic, matching FPGA logic.
All voices output 16-bit signed. Mixer sums to 21-bit, saturates to 16-bit,
outputs top 12 bits with first-order noise shaping for DAC.
Architecture: 256-entry sine + interp, MULT18x18, 16-bit voice output."""

import os, wave
import numpy as np

SR = 48828
OUTDIR = os.path.join(os.path.dirname(os.path.abspath(__file__)), "output_vhdl")

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
    """Exponential pitch sweep from ~113Hz to ~51Hz, exponential amplitude decay.
    Matches real 808 measured behavior."""
    # Start/end freq as phase increments
    # tone=128: start=152 (113Hz), end=68 (51Hz)
    freq_start = 96 + ((tone >> 4) * 3) + (tone >> 5)
    freq_end = 68
    # Exponential pitch sweep: freq approaches freq_end with tau
    # tau = ~5ms = ~244 samples. Use: freq -= (freq - freq_end) >> 6 each sample
    # That gives tau = 64 samples = 1.3ms. Too fast.
    # Use >> 8 for tau = 256 samples = 5.2ms. Good.
    pitch_shift = 4  # tau ~16 samples = 0.33ms (very fast sweep)

    # Decay K: 10 + decay(7:6)
    decay_k = 10 + (decay >> 6)

    phase = 0; freq = freq_start; amp = 65535
    out = []
    for _ in range(n_samples):
        if amp < 64:
            out.append(0); continue
        s = sine_lookup(phase)
        amp_11 = amp >> 5
        product = s * amp_11
        out.append(clamp16(product >> 7))
        phase = (phase + freq) & 0xFFFF
        # Exponential pitch sweep: freq -= (freq - freq_end) >> shift
        if freq > freq_end:
            diff = freq - freq_end
            step = diff >> pitch_shift
            if step < 1: step = 1
            freq -= step
        amp -= amp >> decay_k
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
        tone_amp -= tone_amp >> 9   # K=9, tau ~10ms
        noise_amp -= noise_amp >> 11  # K=11, tau ~42ms
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
        amp -= amp >> 11  # K=11, tau ~42ms (real 808 toms: 76-111ms to -20dB)
    return out

def render_lt(n_samples, tuning=128):
    return render_tom(n_samples, tuning, g_freq=165)  # ~82Hz

def render_mt(n_samples, tuning=128):
    return render_tom(n_samples, tuning, g_freq=181)  # ~135Hz

def render_ht(n_samples, tuning=128):
    return render_tom(n_samples, tuning, g_freq=295)  # ~220Hz


# === Metallic voices: 6 square oscillators + BPF ===

def render_metallic_core(n_samples, decay_k, bpf_lp_shift, bpf_hp_shift):
    """6 free-running square oscs + multi-stage BPF.
    Real 808 frequencies: 205, 304, 370, 523, 540, 800 Hz.
    Target: pass ~6-12kHz (beating products), reject fundamentals."""
    # Correct phase increments for real 808 frequencies
    incs = [275, 409, 496, 702, 725, 1075]
    phases = [0]*6
    # 1-stage LP (anti-alias) + 4-stage HP (remove fundamentals aggressively)
    lp1 = 0
    hp1 = 0; hp2 = 0; hp3 = 0; hp4 = 0
    amp = 65535
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
        # LP: gentle anti-alias (shift=1, fc~3.9kHz)
        lp1 = lp1 + signed_rshift(raw - lp1, bpf_lp_shift)
        # 4-stage HP cascade (each stage shift=2, combined gives steep rolloff below ~3kHz)
        hp1 = hp1 + signed_rshift(lp1 - hp1, bpf_hp_shift)
        x1 = lp1 - hp1
        hp2 = hp2 + signed_rshift(x1 - hp2, bpf_hp_shift)
        x2 = x1 - hp2
        hp3 = hp3 + signed_rshift(x2 - hp3, bpf_hp_shift)
        x3 = x2 - hp3
        hp4 = hp4 + signed_rshift(x3 - hp4, bpf_hp_shift)
        bp = x3 - hp4
        # Multiply by amplitude
        bp_16 = max(-32768, min(32767, bp))
        amp_11 = amp >> 5
        product = bp_16 * amp_11
        out.append(clamp16(product >> 11))
        amp -= amp >> decay_k
    return out


# === CH (Closed HiHat) ===

def render_ch(n_samples):
    """Short metallic hit. Decay K=9 (~10ms to -20dB)."""
    return render_metallic_core(n_samples, decay_k=9, bpf_lp_shift=1, bpf_hp_shift=3)


# === OH (Open HiHat) ===

def render_oh(n_samples, decay=128):
    if decay < 52: dk = 11
    elif decay < 103: dk = 12
    elif decay < 154: dk = 13
    elif decay < 205: dk = 14
    else: dk = 15
    return render_metallic_core(n_samples, decay_k=dk, bpf_lp_shift=1, bpf_hp_shift=3)


# === CY (Cymbal) ===

def render_cymbal(n_samples, tone=128, decay=128):
    if tone < 86: lp_shift = 2  # darker
    elif tone < 171: lp_shift = 1
    else: lp_shift = 1  # brighter (less LP filtering)
    if decay < 52: dk = 11
    elif decay < 103: dk = 12
    elif decay < 154: dk = 13
    elif decay < 205: dk = 14
    else: dk = 15
    return render_metallic_core(n_samples, decay_k=dk, bpf_lp_shift=lp_shift, bpf_hp_shift=4)


# === CB (Cowbell) ===

def render_cowbell(n_samples):
    """2 square oscillators (540/800Hz) + narrow BPF."""
    phases = [0, 0]; incs = [725, 1075]
    lp1 = 0; lp2 = 0; hp1 = 0; hp2 = 0
    amp = 65535
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
        # Narrow BPF: tight LP + HP
        lp1 = lp1 + signed_rshift(raw - lp1, 2)
        lp2 = lp2 + signed_rshift(lp1 - lp2, 2)
        hp1 = hp1 + signed_rshift(lp2 - hp1, 4)
        hp2 = hp2 + signed_rshift(hp1 - hp2, 4)
        bp = lp2 - hp2
        bp_16 = max(-32768, min(32767, bp))
        amp_11 = amp >> 5
        product = bp_16 * amp_11
        out.append(clamp16(product >> 11))
        amp -= amp >> 10  # K=10, fast ring decay
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
        amp -= amp >> 8  # K=8, tau~5ms
    return out


# === CP (Hand Clap) ===

def render_clap(n_samples):
    """LFSR noise + BPF (1-8kHz), 3-burst envelope then tail."""
    lfsr = 0xBEEF; lp_acc = 0; hp_acc = 0; amp = 65535; count = 0
    out = []
    for _ in range(n_samples):
        if amp < 64 and count >= 2196:
            out.append(0); continue
        lfsr = lfsr_next(lfsr, [15, 13, 11, 0])
        count += 1
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
        lp_acc = lp_acc + signed_rshift(noise_raw - lp_acc, 1)
        hp_acc = hp_acc + signed_rshift(lp_acc - hp_acc, 3)
        bp = lp_acc - hp_acc
        if gate:
            bp_16 = max(-32768, min(32767, bp))
            amp_11 = amp >> 5
            product = bp_16 * amp_11
            out.append(clamp16(product >> 11))
        else:
            out.append(0)
        if c >= 2196:
            amp -= amp >> 11  # K=11, tail decay
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
    # Mixer: saturate to 16-bit
    for i in range(total):
        mix[i] = clamp16(mix[i])
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
