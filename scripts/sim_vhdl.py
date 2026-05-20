#!/usr/bin/env python3
"""Bit-exact VHDL simulator - integer arithmetic only, matching FPGA logic."""

import os, wave
import numpy as np

SR = 48828
OUTDIR = os.path.join(os.path.dirname(os.path.abspath(__file__)), "output_vhdl")

# 256-entry sine table, 12-bit signed (matches FPGA distributed RAM)
SINE = [int(round(2047 * np.sin(2 * np.pi * i / 256))) for i in range(256)]

def lfsr_next(reg, taps):
    fb = 0
    for t in taps:
        fb ^= (reg >> t) & 1
    return ((reg << 1) | fb) & 0xFFFF

def clip12(x):
    if x > 2047: return 2047
    if x < -2048: return -2048
    return x

def sine_lookup(phase):
    """256-entry 12-bit table with linear interpolation. Uses 1 MULT18x18.
    Index from bits 15:8, fraction from bits 7:0."""
    idx = (phase >> 8) & 255
    frac = phase & 255
    s0 = SINE[idx]
    s1 = SINE[(idx + 1) & 255]
    return s0 + ((s1 - s0) * frac >> 8)

def amp_multiply(sine_val, amp):
    """Full 18x18 multiply: sine(12-bit signed) * amp(16-bit unsigned).
    Returns 18-bit signed result (matches MULT18x18 output precision)."""
    product = sine_val * amp  # 28-bit
    return product >> 10  # keep top 18 bits


def render_kick(n_samples):
    """VHDL: kick_drum.vhd. Sine sweep 150→75, decay K=12, silence <64."""
    out = []
    phase = 0; freq = 150; amp = 65535; div = 0
    for _ in range(n_samples):
        if amp < 64:
            out.append(0); continue
        s = sine_lookup(phase)
        val = amp_multiply(s, amp)
        out.append(val)
        new_phase = (phase + freq) & 0xFFFF
        new_div = (div + 1) & 7
        new_freq = freq
        if div == 6 and freq > 75:  # "110" = 6
            new_freq = freq - 1
            new_div = 0
        new_amp = amp - (amp >> 12)
        phase, freq, amp, div = new_phase, new_freq, new_amp, new_div
    return out


def render_snare(n_samples):
    """VHDL: snare_drum.vhd. Two sines + LFSR noise, silence <64 on both."""
    out = []
    phase1 = 0; phase2 = 0; tone_amp = 65535; noise_amp = 65535
    lfsr = 0xACE1
    for _ in range(n_samples):
        if tone_amp < 64 and noise_amp < 64:
            out.append(0); continue
        s1 = sine_lookup(phase1)
        s2 = sine_lookup(phase2)
        # LFSR feedback: bit15^bit13^bit12^bit10
        new_lfsr = lfsr_next(lfsr, [15, 13, 12, 10])
        # Tones
        p1 = s1 * tone_amp
        p2 = s2 * tone_amp
        # Noise: sign from lfsr(15) (OLD lfsr, before update)
        noise = noise_amp if (lfsr >> 15) & 1 else -noise_amp
        # Mix to 18-bit: divide total by 3 to stay in range
        t1 = p1 >> 12       # 28-bit >> 12 = 16-bit
        t2 = p2 >> 13       # half of t1
        t3 = noise >> 1     # 16-bit >> 1 = 15-bit
        mix = t1 + t2 + t3
        out.append(mix)
        # Updates
        phase1 = (phase1 + 319) & 0xFFFF
        phase2 = (phase2 + 638) & 0xFFFF
        lfsr = new_lfsr
        tone_amp -= tone_amp >> 11
        noise_amp -= noise_amp >> 12
    return out


def render_hihat_core(n_samples, decay_k, hpf_shift):
    """VHDL: hihat/open_hihat/cymbal. 6 free-running oscs + 4-stage HPF."""
    incs = [274, 408, 496, 701, 725, 1074]
    phases = [0]*6
    hp_accs = [0]*4
    amp = 65535
    out = []
    for _ in range(n_samples):
        # sq reads OLD phase values (before increment)
        sq_sum = 0
        for i in range(6):
            sq_sum += 1 if (phases[i] & 0x8000) else -1
        # Phases always advance (free-running, outside active check)
        for i in range(6):
            phases[i] = (phases[i] + incs[i]) & 0xFFFF
        if amp < 512:
            out.append(0); continue
        raw = sq_sum * 170
        # 4-stage HPF (signal semantics: x uses OLD accumulator value)
        hp = raw
        new_accs = list(hp_accs)
        for j in range(4):
            old_acc = hp_accs[j]
            new_accs[j] = old_acc + ((hp - old_acc) >> hpf_shift)
            hp = hp - old_acc
        hp_accs = new_accs
        # Output: full 18-bit multiply
        val = (hp * amp) >> 10
        out.append(val)
        amp -= amp >> decay_k
    return out

def render_ch(n_samples): return render_hihat_core(n_samples, 11, 3)
def render_oh(n_samples): return render_hihat_core(n_samples, 12, 3)
def render_cymbal(n_samples): return render_hihat_core(n_samples, 15, 4)


def render_cowbell(n_samples):
    """VHDL: cowbell.vhd. 2 oscs + bandpass, decay K=11, silence <64."""
    phases = [0, 0]; incs = [725, 1074]
    lp_acc = 0; hp_acc = 0; amp = 65535
    out = []
    for _ in range(n_samples):
        # sq reads OLD phase values
        sq = 0
        for i in range(2):
            sq += 1 if (phases[i] & 0x8000) else -1
        # Phases always advance
        for i in range(2):
            phases[i] = (phases[i] + incs[i]) & 0xFFFF
        if amp < 64:
            out.append(0); continue
        raw = sq * 512
        # Bandpass (signal semantics: all reads use old values)
        old_lp = lp_acc
        old_hp = hp_acc
        lp_acc = old_lp + ((raw - old_lp) >> 2)
        hp_acc = old_hp + ((old_lp - old_hp) >> 4)
        bp = old_lp - old_hp
        val = (bp * amp) >> 10
        out.append(val)
        amp -= amp >> 11
    return out


def render_clap(n_samples):
    """VHDL: clap.vhd. LFSR noise + bandpass, burst pattern, decay K=12 in tail."""
    lfsr = 0xBEEF; lp_acc = 0; hp_acc = 0; amp = 65535; count = 0
    out = []
    for _ in range(n_samples):
        if amp < 64 and count >= 2196:
            out.append(0); continue
        # LFSR advances, count increments (signal updates)
        new_lfsr = lfsr_next(lfsr, [15, 13, 11, 0])
        count += 1
        c = count
        # Burst pattern
        if   c < 244:  gate = True
        elif c < 976:  gate = False
        elif c < 1220: gate = True
        elif c < 1952: gate = False
        elif c < 2196: gate = True
        else:          gate = True  # tail
        # Noise: signed(lfsr(11:0)) - uses NEW lfsr (variable in VHDL process)
        # Actually VHDL does: lfsr <= lfsr(14:0) & feedback THEN reads lfsr(11:0)
        # Since lfsr is a SIGNAL, the read gets the OLD value
        noise_12 = lfsr & 0xFFF
        noise_raw = noise_12 - 4096 if noise_12 & 0x800 else noise_12
        # Bandpass (signal semantics)
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
        # Decay only during tail
        if c >= 2196:
            amp -= amp >> 12
        lfsr = new_lfsr
    return out


def render_rimshot(n_samples):
    """VHDL: rimshot.vhd. 3 sines each /4 then summed, decay K=8, silence <64."""
    phases = [0, 0, 0]; incs = [610, 912, 1368]
    amp = 65535
    out = []
    for _ in range(n_samples):
        if amp < 64:
            out.append(0); continue
        s = 0
        for i in range(3):
            s += sine_lookup(phases[i]) >> 2
        s = max(-2048, min(2047, s))
        val = amp_multiply(s, amp)
        out.append(val)
        for i in range(3):
            phases[i] = (phases[i] + incs[i]) & 0xFFFF
        amp -= amp >> 8
    return out


def render_tom(n_samples):
    """VHDL: tom.vhd G_FREQ=181. Pitch dive every sample, decay K=12, silence <64."""
    base_freq = 181
    phase = 0; freq = base_freq + (base_freq >> 2); amp = 65535  # 226
    out = []
    for _ in range(n_samples):
        if amp < 64:
            out.append(0); continue
        s = sine_lookup(phase)
        val = amp_multiply(s, amp)
        out.append(val)
        phase = (phase + freq) & 0xFFFF
        if freq > base_freq:
            freq -= 1
        amp -= amp >> 12
    return out


def apply_mixer_lpf(samples):
    """Final DAC output: truncate 18-bit to 12-bit. No LPF on sine voices."""
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
    """120 BPM, 4 seconds, 16 steps. BD=0,8 SD=4,12 CH=all even OH=8 CP=10."""
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
        ("08_tom.wav", render_tom, SR),
        ("09_cymbal.wav", render_cymbal, SR * 2),
    ]
    for fname, renderer, n in voices:
        save_wav(fname, renderer(n))
    save_wav("10_demo_pattern.wav", render_demo())
    print("Done.")

if __name__ == "__main__":
    main()
