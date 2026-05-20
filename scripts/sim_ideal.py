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
    tau_a_table = {0: 0.022, 2.5: 0.030, 5.0: 0.100, 7.5: 0.140, 10.0: 0.300}
    # Interpolate
    knobs = sorted(tau_a_table.keys())
    taus = [tau_a_table[k] for k in knobs]
    tau_a = np.interp(decay, knobs, taus)

    freq = freq_end + (freq_start - freq_end) * np.exp(-t / tau_p)
    phase = 2 * np.pi * np.cumsum(freq) / SR
    sig = np.sin(phase) * np.exp(-t / tau_a)
    return sig

def render_snare(n_samples, tone=5.0, snappy=5.0):
    """SD: Two bridged-T oscillators + noise.
    Service manual design: 238/476Hz. Actual recording: ~173/346Hz.
    Using recorded values (component tolerances shift frequency).
    tone:   0-10, output ratio of the two oscillators
    snappy: 0-10, noise envelope amplitude
    """
    t = np.arange(n_samples) / SR
    # Two oscillators: ~173Hz and ~346Hz (measured from recording)
    osc_lo = np.sin(2 * np.pi * 173 * t)
    osc_hi = np.sin(2 * np.pi * 346 * t)
    # TONE knob: balance between fundamental and harmonic
    lo_gain = 1.0 - (tone / 10.0) * 0.8
    hi_gain = 0.2 + (tone / 10.0) * 0.8
    # Decay: ~30ms fundamental, ~15ms harmonic (gives -20dB at ~46ms)
    lo_tau = 0.030
    hi_tau = 0.015
    tone_sig = osc_lo * lo_gain * np.exp(-t / lo_tau) + osc_hi * hi_gain * np.exp(-t / hi_tau)
    # Noise: LFSR through HPF
    np.random.seed(42)
    noise = np.random.randn(n_samples)
    lp = 0.0
    hpf_out = np.zeros(n_samples)
    alpha = 1.0 / 8.0
    for i in range(n_samples):
        lp += (noise[i] - lp) * alpha
        hpf_out[i] = noise[i] - lp
    noise_tau = (2**11) / SR
    hpf_out *= np.exp(-t / noise_tau)
    # SNAPPY knob
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
    """CH: 6 square oscillators + BPF. Measured: decay=34ms, centroid=11.5kHz."""
    freqs = [204.7, 304.4, 369.6, 522.7, 540.4, 800.6]
    t = np.arange(n_samples) / SR
    sig = square_osc_mix(n_samples, freqs)
    sig = bpf(sig, 6000, 10000)
    return sig * np.exp(-t / 0.015)  # tau=15ms gives -20dB at ~34ms

def render_oh(n_samples, decay=5.0):
    """OH: Same 6 oscillators + BPF, longer decay.
    decay: 0-10, controls decay time (74-448ms measured)."""
    freqs = [204.7, 304.4, 369.6, 522.7, 540.4, 800.6]
    t = np.arange(n_samples) / SR
    sig = square_osc_mix(n_samples, freqs)
    sig = bpf(sig, 6000, 10000)
    # Decay: 74ms (knob=0) to 448ms (knob=10)
    tau_table = {0: 0.032, 2.5: 0.077, 5.0: 0.200, 7.5: 0.250, 10.0: 0.280}
    knobs = sorted(tau_table.keys())
    taus = [tau_table[k] for k in knobs]
    tau = np.interp(decay, knobs, taus)
    return sig * np.exp(-t / tau)

def render_cymbal(n_samples, tone=5.0, decay=5.0):
    """CY: 6 square oscillators split into 3 frequency bands with different decays.
    Service manual: 3 VCAs (Q16, Q17, Q18) for high/mid/low bands.
    High band decays fastest, low band sustains longest.
    Reference shows centroid drifting from 10kHz down to 5kHz over 1s."""
    freqs = [204.7, 304.4, 369.6, 522.7, 540.4, 800.6]
    t = np.arange(n_samples) / SR
    sig = square_osc_mix(n_samples, freqs)
    # Split into 3 bands like the real circuit
    hi = hpf(sig, 10000)       # Q16: highest, shortest decay
    mid = bpf(sig, 5000, 10000) # Q17: mid, controllable decay
    lo = bpf(sig, 2000, 5000)   # Q18: lowest, longest decay
    # Decay times: hi=fast, mid=medium (DECAY knob), lo=slow
    # Service manual: CY decay 350/800/1200ms at short/mid/long
    base_tau = 0.060 + (decay / 10.0) * 0.200  # 60-260ms base
    hi_decay = base_tau * 0.3   # high dies fast
    mid_decay = base_tau * 0.7  # mid is the main body
    lo_decay = base_tau * 1.5   # low sustains
    out = hi * np.exp(-t / hi_decay) + mid * np.exp(-t / mid_decay) + lo * np.exp(-t / lo_decay)
    return out

def render_cowbell(n_samples):
    """CB: 2 square oscillators + high-Q BPF. Measured: freq=822Hz, decay=42ms.
    Service manual: two Schmitt oscillators (540/800Hz) through IC2 bandpass.
    The 'ring' character comes from the high-Q resonance at ~800Hz."""
    t = np.arange(n_samples) / SR
    sig = np.sign(np.sin(2*np.pi*540*t)) + np.sign(np.sin(2*np.pi*800*t))
    sig = bpf(sig, 700, 900)  # narrow BPF = high Q resonance
    return sig * np.exp(-t / 0.018)

def render_clap(n_samples):
    """CP: Noise bursts + BPF. Service manual Fig 13: sawtooth envelope generator.
    3 bursts with ~10ms gaps, then reverb tail. Total ~80ms active."""
    t = np.arange(n_samples) / SR
    noise = np.random.randn(n_samples)
    noise_filt = bpf(noise, 1000, 8000)
    # Envelope: 3 bursts then sustained reverb tail
    # Burst 1: 0-4ms, Burst 2: 12-16ms, Burst 3: 24-28ms, Tail: 30ms+
    env = np.zeros(n_samples)
    burst_times_ms = [0, 12, 24]  # burst start times
    burst_dur_ms = 4
    for bt in burst_times_ms:
        start = int(bt * SR / 1000)
        dur = int(burst_dur_ms * SR / 1000)
        end = min(start + dur, n_samples)
        burst_t = np.arange(end - start) / SR
        env[start:end] = np.exp(-burst_t / 0.002)  # each burst decays fast
    # Reverb tail starts at ~30ms, decays over ~50ms
    tail_start = int(30 * SR / 1000)
    if tail_start < n_samples:
        tail_t = np.arange(n_samples - tail_start) / SR
        tail = 0.7 * np.exp(-tail_t / 0.020)
        env[tail_start:] = np.maximum(env[tail_start:], tail)
    return noise_filt * env

def render_rimshot(n_samples):
    """RS: 455Hz bridged-T through swing-type VCA (adds harmonics).
    Service manual: freq=455Hz, decay=2.2ms. VCA adds many high harmonics.
    Recording shows 79% energy above 1kHz, centroid=4594Hz.
    The swing VCA is heavily nonlinear — almost turns sine into square."""
    t = np.arange(n_samples) / SR
    # 455Hz resonator
    sig = np.sin(2 * np.pi * 455 * t)
    # Swing VCA: heavy distortion (hard clip to near-square)
    sig = np.clip(sig * 4, -1, 1)
    # Fast decay: service manual says 2.2ms, recording shows -20dB at 9ms
    env = np.exp(-t / 0.004)
    return sig * env

def render_tom(n_samples, tuning=5.0):
    """Tom: Sine with pitch dive. Parameterized by TUNING knob.
    Measured frequencies: LT 82-100Hz, MT 124-155Hz, HT 170-214Hz.
    This renders MT by default; LT/HT use freq_base parameter."""
    t = np.arange(n_samples) / SR
    # MT: 124Hz (tuning=0) to 155Hz (tuning=10)
    freq_base = 124 + (155 - 124) * (tuning / 10.0)
    freq_start = freq_base * 1.25  # 25% pitch dive
    tau_p = 0.005  # pitch sweep tau
    tau_a = 0.060  # amplitude decay ~83-97ms to -20dB
    freq = freq_base + (freq_start - freq_base) * np.exp(-t / tau_p)
    phase = 2 * np.pi * np.cumsum(freq) / SR
    return np.sin(phase) * np.exp(-t / tau_a)

def render_tom_lt(n_samples, tuning=5.0):
    """LT: Low Tom. Measured: 82-100Hz, decay 76-111ms."""
    t = np.arange(n_samples) / SR
    freq_base = 82 + (100 - 82) * (tuning / 10.0)
    freq_start = freq_base * 1.25
    freq = freq_base + (freq_start - freq_base) * np.exp(-t / 0.005)
    phase = 2 * np.pi * np.cumsum(freq) / SR
    return np.sin(phase) * np.exp(-t / 0.070)

def render_tom_ht(n_samples, tuning=5.0):
    """HT: Hi Tom. Measured: 170-214Hz, decay 72-94ms."""
    t = np.arange(n_samples) / SR
    freq_base = 170 + (214 - 170) * (tuning / 10.0)
    freq_start = freq_base * 1.25
    freq = freq_base + (freq_start - freq_base) * np.exp(-t / 0.005)
    phase = 2 * np.pi * np.cumsum(freq) / SR
    return np.sin(phase) * np.exp(-t / 0.035)

def render_maracas(n_samples):
    """MA: Short noise burst. Measured: decay=9ms, centroid=11.3kHz."""
    t = np.arange(n_samples) / SR
    noise = np.random.randn(n_samples)
    noise_filt = hpf(noise, 5000)
    return noise_filt * np.exp(-t / 0.004)

def render_claves(n_samples):
    """CL: Short resonant tone. Measured: decay=22ms, centroid=3667Hz."""
    t = np.arange(n_samples) / SR
    # Similar to rimshot but lower frequency, longer decay
    sig = np.sin(2 * np.pi * 2500 * t)
    return sig * np.exp(-t / 0.010)

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
