#!/usr/bin/env python3
"""Bit-exact VHDL simulator - integer arithmetic, matching FPGA logic.
All voices parameterized with TR-808 panel knobs (0-255 range, 8-bit).
Architecture: 256-entry sine + interp, 18-bit internal, MULT18x18, 12-bit DAC."""

import os, wave
import numpy as np

SR = 48828
OUTDIR = os.path.join(os.path.dirname(os.path.abspath(__file__)), "output_vhdl")

# 256-entry sine table, 12-bit signed
SINE = [int(round(2047 * np.sin(2 * np.pi * i / 256))) for i in range(256)]

def lfsr_next(reg, taps):
    fb = 0
    for t in taps:
        fb ^= (reg >> t) & 1
    return ((reg << 1) | fb) & 0xFFFF

def sine_lookup(phase):
    """256-entry + linear interpolation. 1 MULT18x18."""
    idx = (phase >> 8) & 255
    frac = phase & 255
    s0 = SINE[idx]
    s1 = SINE[(idx + 1) & 255]
    return s0 + ((s1 - s0) * frac >> 8)

def amp_multiply(sine_val, amp):
    """18x18 multiply -> 18-bit output."""
    return (sine_val * amp) >> 10


# === BD (Bass Drum) — knobs: TONE (0-255), DECAY (0-255) ===

def render_kick(n_samples, tone=128, decay=128):
    """Sine sweep, exponential decay. TONE=start freq, DECAY=decay rate."""
    # TONE: start freq inc 96 (tone=0) to 151 (tone=255)
    freq_start = 96 + ((tone * 55) >> 8)
    freq_end = 68  # ~51Hz
    # DECAY: K value 9 (fast, decay=0) to 14 (slow, decay=255)
    decay_k = 9 + ((decay * 5) >> 8)
    # Pitch sweep: freq decrements by 1 every N samples
    sweep_div = 7  # every 7 samples

    phase = 0; freq = freq_start; amp = 65535; div = 0
    out = []
    for _ in range(n_samples):
        if amp < 64:
            out.append(0); continue
        s = sine_lookup(phase)
        out.append(amp_multiply(s, amp))
        new_phase = (phase + freq) & 0xFFFF
        new_div = (div + 1) & 7
        new_freq = freq
        if div == (sweep_div - 1) and freq > freq_end:
            new_freq = freq - 1
            new_div = 0
        new_amp = amp - (amp >> decay_k)
        phase, freq, amp, div = new_phase, new_freq, new_amp, new_div
    return out


# === SD (Snare Drum) — knobs: TONE (0-255), SNAPPY (0-255) ===

def render_snare(n_samples, tone=128, snappy=128):
    """Two sines (173+346Hz) + LFSR noise through HPF.
    TONE=balance between oscillators, SNAPPY=noise level."""
    # Phase increments: 173Hz=232, 346Hz=464
    inc_lo = 232; inc_hi = 464
    # TONE: lo_gain and hi_gain (shift-based)
    # tone=0: lo dominates, tone=255: hi dominates
    lo_shift = 0 + (tone >> 7)   # 0 or 1 (divide by 1 or 2)
    hi_shift = 1 - (tone >> 7)   # 1 or 0

    phase1 = 0; phase2 = 0
    tone_amp = 65535; noise_amp = 65535
    lfsr = 0xACE1; hp_acc = 0
    out = []
    for _ in range(n_samples):
        if tone_amp < 64 and noise_amp < 64:
            out.append(0); continue
        s1 = sine_lookup(phase1)
        s2 = sine_lookup(phase2)
        new_lfsr = lfsr_next(lfsr, [15, 13, 12, 10])
        # Tone mix (18-bit)
        t1 = (s1 * tone_amp) >> (10 + lo_shift)
        t2 = (s2 * tone_amp) >> (10 + hi_shift)
        tone_out = t1 + t2
        # Noise: LFSR -> HPF -> amplitude
        noise_raw = (lfsr & 0x7FF) - 1024  # 11-bit signed
        old_hp = hp_acc
        hp_acc = old_hp + ((noise_raw - old_hp) >> 3)
        hp_out = noise_raw - old_hp
        # SNAPPY controls noise gain: snappy=0 -> off, snappy=255 -> full
        noise_out = (hp_out * noise_amp * snappy) >> 24 if snappy > 16 else 0
        mix = tone_out + noise_out
        out.append(mix)
        # Updates
        phase1 = (phase1 + inc_lo) & 0xFFFF
        phase2 = (phase2 + inc_hi) & 0xFFFF
        lfsr = new_lfsr
        tone_amp -= tone_amp >> 10  # K=10, tau~21ms
        noise_amp -= noise_amp >> 11  # K=11, tau~42ms
    return out


# === LT/MT/HT (Toms) — knob: TUNING (0-255) ===

def render_tom(n_samples, tuning=128, freq_lo=110, freq_hi=135):
    """Sine + pitch dive. TUNING sets base frequency."""
    # Base freq from tuning knob
    base_freq = freq_lo + ((tuning * (freq_hi - freq_lo)) >> 8)
    freq_start = base_freq + (base_freq >> 2)  # +25% for pitch dive

    phase = 0; freq = freq_start; amp = 65535
    out = []
    for _ in range(n_samples):
        if amp < 64:
            out.append(0); continue
        s = sine_lookup(phase)
        out.append(amp_multiply(s, amp))
        phase = (phase + freq) & 0xFFFF
        if freq > base_freq:
            freq -= 1
        amp -= amp >> 12  # K=12, tau~84ms
    return out

def render_lt(n_samples, tuning=128):
    return render_tom(n_samples, tuning, freq_lo=82, freq_hi=134)

def render_mt(n_samples, tuning=128):
    return render_tom(n_samples, tuning, freq_lo=110, freq_hi=214)

def render_ht(n_samples, tuning=128):
    return render_tom(n_samples, tuning, freq_lo=228, freq_hi=295)


# === CY (Cymbal) — knobs: TONE (0-255), DECAY (0-255) ===

def render_cymbal(n_samples, tone=128, decay=128):
    """6 square oscillators + 4-stage HPF, multi-band decay."""
    incs = [274, 408, 496, 701, 725, 1074]
    phases = [0]*6
    hp_accs = [0]*4
    amp_hi = 65535; amp_lo = 65535
    # DECAY: K for main decay
    decay_k = 11 + ((decay * 4) >> 8)  # K=11 (fast) to K=15 (slow)
    # HPF shift from TONE
    hpf_shift = 4 - ((tone * 2) >> 8)  # 4 (dark) to 2 (bright)
    hpf_shift = max(2, min(4, hpf_shift))

    out = []
    for _ in range(n_samples):
        sq_sum = 0
        for i in range(6):
            sq_sum += 1 if (phases[i] & 0x8000) else -1
        for i in range(6):
            phases[i] = (phases[i] + incs[i]) & 0xFFFF
        if amp_hi < 512 and amp_lo < 512:
            out.append(0); continue
        raw = sq_sum * 170
        # 4-stage HPF
        hp = raw
        new_accs = list(hp_accs)
        for j in range(4):
            old_acc = hp_accs[j]
            new_accs[j] = old_acc + ((hp - old_acc) >> hpf_shift)
            hp = hp - old_acc
        hp_accs = new_accs
        # Output with frequency-dependent decay (hi dies faster)
        val = (hp * amp_hi) >> 10
        out.append(val)
        amp_hi -= amp_hi >> decay_k
        amp_lo -= amp_lo >> (decay_k + 2)
    return out


# === OH (Open HiHat) — knob: DECAY (0-255) ===

def render_oh(n_samples, decay=128):
    """Same 6 oscillators + HPF as CH, longer decay."""
    decay_k = 11 + ((decay * 4) >> 8)  # K=11 to K=15
    return render_hihat_core(n_samples, decay_k, 3)


# === CH (Closed HiHat) — no knobs ===

def render_ch(n_samples):
    return render_hihat_core(n_samples, 11, 3)

def render_hihat_core(n_samples, decay_k, hpf_shift):
    """6 free-running square oscs + 4-stage HPF."""
    incs = [274, 408, 496, 701, 725, 1074]
    phases = [0]*6
    hp_accs = [0]*4
    amp = 65535
    out = []
    for _ in range(n_samples):
        sq_sum = 0
        for i in range(6):
            sq_sum += 1 if (phases[i] & 0x8000) else -1
        for i in range(6):
            phases[i] = (phases[i] + incs[i]) & 0xFFFF
        if amp < 512:
            out.append(0); continue
        raw = sq_sum * 170
        hp = raw
        new_accs = list(hp_accs)
        for j in range(4):
            old_acc = hp_accs[j]
            new_accs[j] = old_acc + ((hp - old_acc) >> hpf_shift)
            hp = hp - old_acc
        hp_accs = new_accs
        val = (hp * amp) >> 10
        out.append(val)
        amp -= amp >> decay_k
    return out


# === CB (Cowbell) — no knobs ===

def render_cowbell(n_samples):
    """2 square oscillators (540/800Hz) + narrow BPF."""
    phases = [0, 0]; incs = [725, 1074]
    lp_acc = 0; hp_acc = 0; amp = 65535
    out = []
    for _ in range(n_samples):
        sq = 0
        for i in range(2):
            sq += 1 if (phases[i] & 0x8000) else -1
        for i in range(2):
            phases[i] = (phases[i] + incs[i]) & 0xFFFF
        if amp < 64:
            out.append(0); continue
        raw = sq * 512
        old_lp = lp_acc
        old_hp = hp_acc
        lp_acc = old_lp + ((raw - old_lp) >> 2)
        hp_acc = old_hp + ((old_lp - old_hp) >> 4)
        bp = old_lp - old_hp
        val = (bp * amp) >> 10
        out.append(val)
        amp -= amp >> 10  # K=10, faster decay for ring
    return out


# === RS (Rimshot) — no knobs ===

def render_rimshot(n_samples):
    """455Hz hard-clipped sine, fast decay K=8."""
    phase = 0; inc = 610; amp = 65535  # 455Hz
    out = []
    for _ in range(n_samples):
        if amp < 64:
            out.append(0); continue
        s = sine_lookup(phase)
        # Hard clip to add harmonics (swing VCA)
        s = max(-1024, min(1024, s * 2))
        out.append(amp_multiply(s, amp))
        phase = (phase + inc) & 0xFFFF
        amp -= amp >> 8  # K=8, tau~5ms
    return out


# === CL (Claves) — no knobs ===

def render_claves(n_samples):
    """2500Hz damped sine, K=9."""
    phase = 0; inc = 3355; amp = 65535  # 2500Hz
    out = []
    for _ in range(n_samples):
        if amp < 64:
            out.append(0); continue
        s = sine_lookup(phase)
        out.append(amp_multiply(s, amp))
        phase = (phase + inc) & 0xFFFF
        amp -= amp >> 9  # K=9, tau~10ms
    return out


# === CP (Hand Clap) — no knobs ===

def render_clap(n_samples):
    """LFSR noise + BPF, 3-burst envelope then tail."""
    lfsr = 0xBEEF; lp_acc = 0; hp_acc = 0; amp = 65535; count = 0
    out = []
    for _ in range(n_samples):
        if amp < 64 and count >= 2440:
            out.append(0); continue
        new_lfsr = lfsr_next(lfsr, [15, 13, 11, 0])
        count += 1
        c = count
        # 3 bursts: 0-195 (4ms), 586-781 (4ms), 1172-1367 (4ms), tail from 1465
        if   c < 195:  gate = True
        elif c < 586:  gate = False
        elif c < 781:  gate = True
        elif c < 1172: gate = False
        elif c < 1367: gate = True
        elif c < 1465: gate = False
        else:          gate = True  # tail
        noise_12 = lfsr & 0xFFF
        noise_raw = noise_12 - 4096 if noise_12 & 0x800 else noise_12
        old_lp = lp_acc
        old_hp = hp_acc
        lp_acc = old_lp + ((noise_raw - old_lp) >> 3)
        hp_acc = old_hp + ((old_lp - old_hp) >> 4)
        bp = old_lp - old_hp
        if gate:
            val = (bp * amp) >> 10
        else:
            val = 0
        out.append(val)
        if c >= 1465:
            amp -= amp >> 11  # tail decay K=11
        lfsr = new_lfsr
    return out


# === MA (Maracas) — no knobs ===

def render_maracas(n_samples):
    """LFSR noise through HPF, very fast decay K=8."""
    lfsr = 0xDEAD; hp_acc = 0; amp = 65535
    out = []
    for _ in range(n_samples):
        if amp < 64:
            out.append(0); continue
        new_lfsr = lfsr_next(lfsr, [15, 13, 11, 0])
        noise_raw = (lfsr & 0x7FF) - 1024
        old_hp = hp_acc
        hp_acc = old_hp + ((noise_raw - old_hp) >> 2)
        hp_out = noise_raw - old_hp
        val = (hp_out * amp) >> 10
        out.append(val)
        amp -= amp >> 8  # K=8, very fast
        lfsr = new_lfsr
    return out


# === Output ===

def apply_mixer_lpf(samples):
    """Truncate 18-bit to 12-bit at DAC output."""
    for i in range(len(samples)):
        samples[i] = max(-2048, min(2047, samples[i] >> 6))
    return samples

def save_wav(filename, samples):
    samples = apply_mixer_lpf(samples)
    path = os.path.join(OUTDIR, filename)
    data = np.array([s * 16 for s in samples], dtype=np.int16)
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
        ("10_claves.wav", render_claves, SR // 4),
        ("11_maracas.wav", render_maracas, SR // 4),
    ]
    for fname, renderer, n in voices:
        save_wav(fname, renderer(n))
    save_wav("12_demo_pattern.wav", render_demo())
    print("Done.")

if __name__ == "__main__":
    main()
