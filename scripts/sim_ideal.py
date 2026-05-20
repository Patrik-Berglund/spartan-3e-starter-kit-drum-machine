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

def render_kick(n_samples, tone=5.0, decay=5.0):
    """BD: sine oscillator with pitch sweep.
    tone:  0-10, controls pitch sweep depth (start freq)
    decay: 0-10, controls amplitude decay time
    """
    t = np.arange(n_samples) / SR
    # Measured from real 808 references:
    # Settling freq always ~51 Hz
    # Start freq: ~72Hz (tone=0) to ~113Hz (tone=10)
    freq_end = 51.0
    freq_start = 72 + (113 - 72) * (tone / 10.0)
    # Pitch sweep tau ~5ms (fast, consistent across settings)
    tau_p = 0.005
    # Decay: measured -20dB times from references:
    #   decay=0: 18ms, 2.5: 22ms, 5.0: 60ms, 7.5: 78ms, 10: 155ms
    # Empirical tau values tuned to match measured -20dB times:
    tau_a_table = {0: 0.015, 2.5: 0.028, 5.0: 0.100, 7.5: 0.140, 10.0: 0.500}
    # Interpolate
    knobs = sorted(tau_a_table.keys())
    taus = [tau_a_table[k] for k in knobs]
    tau_a = np.interp(decay, knobs, taus)

    freq = freq_end + (freq_start - freq_end) * np.exp(-t / tau_p)
    phase = 2 * np.pi * np.cumsum(freq) / SR
    sig = np.sin(phase) * np.exp(-t / tau_a)
    return sig

def render_snare(n_samples, tone=5.0, snappy=5.0):
    """SD: Two sine oscillators + LFSR noise through simple HPF.
    All operations map to VHDL: sine table, shifts, LFSR, IIR.
    tone:   0-10, balance between low osc (~167Hz) and high osc (~333Hz)
    snappy: 0-10, noise level
    """
    t = np.arange(n_samples) / SR
    # Two oscillators (from shared sine table in VHDL)
    osc_lo = np.sin(2 * np.pi * 167 * t)
    osc_hi = np.sin(2 * np.pi * 333 * t)
    # TONE knob: crossfade between oscillators
    # Both always present, TONE shifts the balance
    lo_gain = 1.0 - (tone / 10.0) * 0.8   # 1.0 → 0.2
    hi_gain = 0.2 + (tone / 10.0) * 0.8   # 0.2 → 1.0
    tone_sig = osc_lo * lo_gain + osc_hi * hi_gain
    # Each oscillator has its own decay (measured from references):
    # Low osc (167Hz): slow decay, tau~42ms (K=11)
    # High osc (333Hz): fast decay, tau~5ms (K=8)
    lo_tau = (2**11) / SR  # ~42ms
    hi_tau = (2**8) / SR   # ~5ms
    tone_sig = osc_lo * lo_gain * np.exp(-t / lo_tau) + osc_hi * hi_gain * np.exp(-t / hi_tau)
    # Noise: LFSR (white) through simple HPF
    # VHDL: LFSR + single-stage IIR HPF (hp += (input - hp) >> 3)
    np.random.seed(42)
    noise = np.random.randn(n_samples)
    # Simple 1-pole HPF at ~2kHz: y[n] = x[n] - lp[n], lp += (x-lp)>>3
    lp = 0.0
    hpf_out = np.zeros(n_samples)
    alpha = 1.0 / 8.0  # >>3
    for i in range(n_samples):
        lp += (noise[i] - lp) * alpha
        hpf_out[i] = noise[i] - lp
    # Noise decay: K=11 (tau~42ms)
    noise_tau = (2**11) / SR
    hpf_out *= np.exp(-t / noise_tau)
    # SNAPPY knob: noise gain (0 = off, 10 = loud)
    noise_gain = max(0, (snappy - 1.5) / 8.5)
    return tone_sig + hpf_out * noise_gain * 0.8

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
