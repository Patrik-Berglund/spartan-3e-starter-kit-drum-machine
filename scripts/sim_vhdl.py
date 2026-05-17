#!/usr/bin/env python3
"""Bit-exact VHDL simulator - integer arithmetic only, matching FPGA logic."""

import os, wave, struct
import numpy as np

SR = 48828
OUTDIR = os.path.join(os.path.dirname(os.path.abspath(__file__)), "output_vhdl")

SINE = [0,201,399,594,783,965,1137,1299,1447,1582,1702,1805,1891,1959,2008,2037,
        2047,2037,2008,1959,1891,1805,1702,1582,1447,1299,1137,965,783,594,399,201,
        0,-201,-399,-594,-783,-965,-1137,-1299,-1447,-1582,-1702,-1805,-1891,-1959,
        -2008,-2037,-2047,-2037,-2008,-1959,-1891,-1805,-1702,-1582,-1447,-1299,
        -1137,-965,-783,-594,-399,-201]

def lfsr_next(reg, taps):
    """16-bit LFSR step. taps is list of bit positions for XOR feedback."""
    fb = 0
    for t in taps:
        fb ^= (reg >> t) & 1
    return ((reg << 1) | fb) & 0xFFFF

def clip12(x):
    if x > 2047: return 2047
    if x < -2048: return -2048
    return x

def render_kick(n_samples):
    out = []
    phase = 0; freq = 150; amp = 65535; count = 0
    for _ in range(n_samples):
        if amp < 512:
            out.append(0); continue
        s = SINE[(phase >> 10) & 63]
        val = (s * (amp >> 5)) >> 11
        out.append(clip12(val))
        phase = (phase + freq) & 0xFFFF
        amp -= amp >> 12
        count += 1
        if count >= 7 and freq > 75:
            freq -= 1; count = 0
    return out

def render_snare(n_samples):
    out = []
    phase1 = 0; phase2 = 0; tone_amp = 65535; noise_amp = 65535
    lfsr = 0xACE1
    for _ in range(n_samples):
        if tone_amp < 512 and noise_amp < 512:
            out.append(0); continue
        s1 = SINE[(phase1 >> 10) & 63]
        s2 = SINE[(phase2 >> 10) & 63]
        lfsr = lfsr_next(lfsr, [15, 13, 12, 10])
        noise_val = (noise_amp >> 5) if (lfsr & 1) else -(noise_amp >> 5)
        mix = ((s1 * (tone_amp >> 5)) >> 12) + (((s2 * (tone_amp >> 5)) >> 11) >> 1) + (noise_val >> 1)
        out.append(clip12(mix))
        phase1 = (phase1 + 319) & 0xFFFF
        phase2 = (phase2 + 638) & 0xFFFF
        tone_amp -= tone_amp >> 11
        noise_amp -= noise_amp >> 12
    return out

def render_hihat_core(n_samples, decay_k, hpf_shift):
    incs = [274, 408, 496, 701, 725, 1074]
    phases = [0]*6
    hp_accs = [0]*4
    amp = 65535
    out = []
    for _ in range(n_samples):
        if amp < 512:
            out.append(0); continue
        sq_sum = 0
        for i in range(6):
            sq_sum += 1 if (phases[i] & 0x8000) else -1
            phases[i] = (phases[i] + incs[i]) & 0xFFFF
        raw = sq_sum * 170
        hp = raw
        for j in range(4):
            hp_accs[j] += (hp - hp_accs[j]) >> hpf_shift
            hp = hp - hp_accs[j]
        val = (hp >> 4) * (amp >> 5) >> 11
        out.append(clip12(val))
        amp -= amp >> decay_k
    return out

def render_ch(n_samples): return render_hihat_core(n_samples, 11, 3)
def render_oh(n_samples): return render_hihat_core(n_samples, 12, 3)
def render_cymbal(n_samples): return render_hihat_core(n_samples, 15, 4)

def render_cowbell(n_samples):
    phases = [0, 0]; incs = [725, 1074]
    lp_acc = 0; hp_acc = 0; amp = 65535
    out = []
    for _ in range(n_samples):
        if amp < 512:
            out.append(0); continue
        sq = 0
        for i in range(2):
            sq += 1 if (phases[i] & 0x8000) else -1
            phases[i] = (phases[i] + incs[i]) & 0xFFFF
        raw = sq * 512
        lp_acc += (raw - lp_acc) >> 2
        hp_acc += (lp_acc - hp_acc) >> 4
        bp = lp_acc - hp_acc
        val = ((bp >> 4) * (amp >> 5)) >> 11
        out.append(clip12(val))
        amp -= amp >> 11
    return out

def render_clap(n_samples):
    lfsr = 0xBEEF; lp_acc = 0; hp_acc = 0; amp = 65535
    out = []
    for i in range(n_samples):
        if amp < 512 and i >= 2196:
            out.append(0); continue
        lfsr = lfsr_next(lfsr, [15, 13, 11, 0])
        noise = 1024 if (lfsr & 1) else -1024
        lp_acc += (noise - lp_acc) >> 3
        hp_acc += (lp_acc - hp_acc) >> 4
        bp = lp_acc - hp_acc
        if i <= 243: gate = True
        elif i <= 975: gate = False
        elif i <= 1219: gate = True
        elif i <= 1951: gate = False
        elif i <= 2195: gate = True
        else:
            gate = True
            amp -= amp >> 12
        if gate and amp >= 512:
            val = ((bp >> 4) * (amp >> 5)) >> 11
        else:
            val = 0
        out.append(clip12(val))
    return out

def render_rimshot(n_samples):
    phases = [0, 0, 0]; incs = [610, 912, 1368]
    amp = 65535
    out = []
    for _ in range(n_samples):
        if amp < 512:
            out.append(0); continue
        s = 0
        for i in range(3):
            s += SINE[(phases[i] >> 10) & 63]
            phases[i] = (phases[i] + incs[i]) & 0xFFFF
        s = s // 4
        val = (s * (amp >> 5)) >> 11
        out.append(clip12(val))
        amp -= amp >> 8
    return out

def render_tom(n_samples):
    phase = 0; freq = 226; amp = 65535; count = 0
    out = []
    for _ in range(n_samples):
        if amp < 512:
            out.append(0); continue
        s = SINE[(phase >> 10) & 63]
        val = (s * (amp >> 5)) >> 11
        out.append(clip12(val))
        phase = (phase + freq) & 0xFFFF
        amp -= amp >> 12
        count += 1
        if count >= 7 and freq > 181:
            freq -= 1; count = 0
    return out

def apply_lpf(samples):
    """Mixer LPF: lp += (input - lp) >> 2  (cutoff ~6kHz at 48828Hz)"""
    lp_state = 0
    for i in range(len(samples)):
        diff = samples[i] - lp_state
        lp_state = lp_state + (diff >> 2)
        samples[i] = max(-2048, min(2047, lp_state))
    return samples

def save_wav(filename, samples):
    samples = apply_lpf(samples)
    path = os.path.join(OUTDIR, filename)
    data = np.array([s * 16 for s in samples], dtype=np.int16)
    with wave.open(path, 'w') as w:
        w.setnchannels(1); w.setsampwidth(2); w.setframerate(SR)
        w.writeframes(data.tobytes())
    print(f"  {path}")

def render_demo():
    """120 BPM, 4 seconds, 16 steps."""
    step_samples = SR * 60 // 120 // 4  # samples per 16th note
    total = SR * 4
    mix = [0] * total
    # Pattern: BD=0,8 SD=4,12 CH=0,2,4,6,8,10,12,14 OH=8 CP=10
    pattern = {
        'kick': [0,8], 'snare': [4,12], 'ch': [0,2,4,6,8,10,12,14],
        'oh': [8], 'clap': [10]
    }
    renderers = {'kick': render_kick, 'snare': render_snare, 'ch': render_ch,
                 'oh': render_oh, 'clap': render_clap}
    voice_len = SR  # 1 second max per hit
    for voice, steps in pattern.items():
        for step in steps:
            offset = step * step_samples
            snd = renderers[voice](min(voice_len, total - offset))
            for i, s in enumerate(snd):
                if offset + i < total:
                    mix[offset + i] += s
    # Clip
    return [clip12(s) for s in mix]

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
        ("08_tom.wav", render_tom, SR),
        ("09_cymbal.wav", render_cymbal, SR * 2),
    ]
    for fname, renderer, n in voices:
        save_wav(fname, renderer(n))
    save_wav("10_demo_pattern.wav", render_demo())
    print("Done.")

if __name__ == "__main__":
    main()
