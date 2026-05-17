#!/usr/bin/env python3
"""Ideal reference simulator - floating-point, scipy filters, best possible sound."""

import os, wave
import numpy as np
from scipy.signal import butter, lfilter

SR = 48828
OUTDIR = os.path.join(os.path.dirname(os.path.abspath(__file__)), "output_ideal")

def save_wav(filename, samples):
    path = os.path.join(OUTDIR, filename)
    s = np.array(samples, dtype=np.float64)
    peak = np.max(np.abs(s))
    if peak > 0:
        s = s / peak * 0.95
    data = (s * 32767).astype(np.int16)
    with wave.open(path, 'w') as w:
        w.setnchannels(1); w.setsampwidth(2); w.setframerate(SR)
        w.writeframes(data.tobytes())
    print(f"  {path}")

def bpf(sig, lo, hi, order=2):
    b, a = butter(order, [lo/(SR/2), hi/(SR/2)], btype='band')
    return lfilter(b, a, sig)

def hpf(sig, fc, order=2):
    b, a = butter(order, fc/(SR/2), btype='high')
    return lfilter(b, a, sig)

def render_kick(n_samples):
    t = np.arange(n_samples) / SR
    tau_p = 0.005; tau_a = 0.08
    freq = 56 + (112 - 56) * np.exp(-t / tau_p)
    phase = 2 * np.pi * np.cumsum(freq) / SR
    sig = np.sin(phase) * np.exp(-t / tau_a)
    sig[:2] = [1.0, -1.0]  # click transient
    return sig

def render_snare(n_samples):
    t = np.arange(n_samples) / SR
    tone = (np.sin(2*np.pi*238*t) + np.sin(2*np.pi*476*t)) * 0.5 * np.exp(-t/0.042)
    noise = np.random.randn(n_samples)
    noise_filt = bpf(noise, 500, 5000) * np.exp(-t/0.084)
    return tone * 0.5 + noise_filt * 0.5

def square_osc_mix(n_samples, freqs):
    """6 free-running square oscillators with random start phases."""
    sig = np.zeros(n_samples)
    t = np.arange(n_samples) / SR
    for f in freqs:
        ph = np.random.uniform(0, 1)
        sig += np.sign(np.sin(2*np.pi*f*t + 2*np.pi*ph))
    return sig

def render_ch(n_samples):
    freqs = [204.7, 304.4, 369.6, 522.7, 540.4, 800.6]
    t = np.arange(n_samples) / SR
    sig = square_osc_mix(n_samples, freqs)
    sig = hpf(sig, 6000)
    return sig * np.exp(-t / 0.042)

def render_oh(n_samples):
    freqs = [204.7, 304.4, 369.6, 522.7, 540.4, 800.6]
    t = np.arange(n_samples) / SR
    sig = square_osc_mix(n_samples, freqs)
    sig = hpf(sig, 6000)
    return sig * np.exp(-t / 0.200)

def render_cymbal(n_samples):
    freqs = [204.7, 304.4, 369.6, 522.7, 540.4, 800.6]
    t = np.arange(n_samples) / SR
    sig = square_osc_mix(n_samples, freqs)
    sig = hpf(sig, 4000)
    return sig * np.exp(-t / 0.670)

def render_cowbell(n_samples):
    t = np.arange(n_samples) / SR
    sig = np.sign(np.sin(2*np.pi*540*t)) + np.sign(np.sin(2*np.pi*800*t))
    sig = bpf(sig, 667, 933)
    return sig * np.exp(-t / 0.042)

def render_clap(n_samples):
    t = np.arange(n_samples) / SR
    noise = np.random.randn(n_samples)
    noise_filt = bpf(noise, 750, 1250)
    # Burst envelope: 3 bursts (5ms on, 15ms gap), then tail
    env = np.zeros(n_samples)
    burst_on = int(0.005 * SR)
    burst_gap = int(0.015 * SR)
    pos = 0
    for _ in range(3):
        burst_t = np.arange(burst_on) / SR
        env[pos:pos+burst_on] = np.exp(-burst_t / 0.003)  # fast sawtooth-like decay
        pos += burst_on + burst_gap
    # Tail
    tail_t = np.arange(n_samples - pos) / SR
    env[pos:] = np.exp(-tail_t / 0.084)
    return noise_filt * env

def render_rimshot(n_samples):
    t = np.arange(n_samples) / SR
    sig = (np.sin(2*np.pi*455*t) + np.sin(2*np.pi*680*t) + np.sin(2*np.pi*1020*t)) / 3
    sig = hpf(sig, 400)
    return sig * np.exp(-t / 0.002)

def render_tom(n_samples):
    t = np.arange(n_samples) / SR
    freq = 135 + (160 - 135) * np.exp(-t / 0.005)
    phase = 2 * np.pi * np.cumsum(freq) / SR
    return np.sin(phase) * np.exp(-t / 0.084)

def render_demo():
    """120 BPM, 4 seconds, 16 steps."""
    step_samples = SR * 60 // 120 // 4
    total = SR * 4
    mix = np.zeros(total)
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
            n = min(voice_len, total - offset)
            snd = renderers[voice](n)
            mix[offset:offset+n] += snd
    return mix

def main():
    os.makedirs(OUTDIR, exist_ok=True)
    np.random.seed(42)
    print("Generating ideal reference WAV files:")
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
