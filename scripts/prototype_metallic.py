#!/usr/bin/env python3
"""Prototype comparison for metallic voice (hihat/cymbal/cowbell) quality fix.

Compares candidate approaches against the current 6-square-oscillator method:

  A) CURRENT: 6 hard squares (np.sign), summed to a 7-level staircase, then BPF.
  B) DITHERED SUM: same 6 squares, but add a small amount of triangular dither
     before quantization/filtering to break up the staircase steps.
  C) FULL-RESOLUTION SQUARES: same topology, but don't collapse to a small
     integer sum at all -- filter each oscillator's true bandlimited square
     wave individually then sum in the (wide) filter accumulator. This is
     mathematically almost identical to (A) in continuous time, since summing
     6 ideal squares IS just a 7-level waveform by definition (that's a
     property of the source signal, not a resolution artifact) -- included
     to demonstrate this is a dead end.
  D) FM SYNTHESIS: 2 sine oscillators, non-harmonic frequency ratio, one
     modulates the other's phase (or a third carrier). Produces a rich,
     continuously-varying metallic spectrum with no quantization steps.
  E) HYBRID: 6 squares (for authentic 808 beating pattern / frequency content)
     but summed at high internal sample-and-hold resolution AND with the
     squares individually low-pass pre-filtered (bandlimited, not hard
     np.sign) before summing -- avoids the harsh staircase transitions while
     keeping the real 808 oscillator frequencies.

Generates WAVs to scripts/output_prototype/ for listening comparison, and
prints spectral centroid / flatness metrics for objective comparison against
the real TR808WAV reference samples.
"""

import os
import numpy as np
from scipy.signal import butter, lfilter, sosfilt

SR = 48828
OUTDIR = os.path.join(os.path.dirname(os.path.abspath(__file__)), "output_prototype")
os.makedirs(OUTDIR, exist_ok=True)

HH_FREQS = [204.7, 304.4, 369.6, 522.7, 540.4, 800.6]


def save_wav(filename, samples):
    import wave
    path = os.path.join(OUTDIR, filename)
    s = np.array(samples, dtype=np.float64)
    peak = np.max(np.abs(s))
    if peak > 0:
        s = s / peak * 0.95
    data = (s * 32767).astype(np.int16)
    with wave.open(path, 'w') as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes(data.tobytes())
    print(f"  wrote {path}")


def bpf(sig, lo, hi, order=2):
    sos = butter(order, [lo / (SR / 2), hi / (SR / 2)], btype='band', output='sos')
    return sosfilt(sos, sig)


def hpf(sig, fc, order=2):
    sos = butter(order, fc / (SR / 2), btype='high', output='sos')
    return sosfilt(sos, sig)


def spectral_centroid(sig, sr=SR):
    n = len(sig)
    spec = np.abs(np.fft.rfft(sig * np.hanning(n)))
    freqs = np.fft.rfftfreq(n, 1 / sr)
    if spec.sum() < 1e-12:
        return 0.0
    return float((spec * freqs).sum() / spec.sum())


def spectral_flatness(sig):
    """Geometric mean / arithmetic mean of spectrum. Higher = more noise-like
    (smoother, less 'combed' spectrum). Real metallic percussion is fairly
    high in flatness because of dense non-harmonic partials."""
    spec = np.abs(np.fft.rfft(sig * np.hanning(len(sig)))) + 1e-12
    gm = np.exp(np.mean(np.log(spec)))
    am = np.mean(spec)
    return float(gm / am)


def quantization_step_metric(sig):
    """Crude 'steppiness' metric: fraction of samples where the first
    difference is exactly zero for 3+ consecutive samples (flat plateaus
    indicative of coarse quantization before smoothing)."""
    d = np.diff(sig)
    flat = np.abs(d) < 1e-9
    # count runs of >=3 consecutive flats
    run = 0
    total = 0
    for f in flat:
        if f:
            run += 1
        else:
            if run >= 3:
                total += run
            run = 0
    return total / max(1, len(sig))


def approach_a_current(n):
    """Current implementation: hard squares summed to 7-level staircase."""
    t = np.arange(n) / SR
    sig = np.zeros(n)
    for f in HH_FREQS:
        sig += np.sign(np.sin(2 * np.pi * f * t))
    sig = bpf(sig, 6000, 10000)
    return sig * np.exp(-t / 0.015)


def approach_b_dithered(n):
    """Same squares, triangular dither added pre-filter to break up steps."""
    t = np.arange(n) / SR
    sig = np.zeros(n)
    for f in HH_FREQS:
        sig += np.sign(np.sin(2 * np.pi * f * t))
    rng = np.random.default_rng(0)
    dither = (rng.random(n) - rng.random(n)) * 1.0  # triangular, +/-1 LSB-ish
    sig = sig + dither
    sig = bpf(sig, 6000, 10000)
    return sig * np.exp(-t / 0.015)


def approach_d_fm(n):
    """FM synthesis: 2 non-harmonic sine pairs, cross-modulated, summed.
    Chosen ratios inspired by the 6 non-harmonic square frequencies but
    implemented as FM operators for a continuously rich spectrum."""
    t = np.arange(n) / SR
    # carrier/modulator pairs at non-harmonic ratios (not integer!)
    pairs = [(800.6, 522.7), (540.4, 369.6), (304.4, 204.7)]
    sig = np.zeros(n)
    for carrier, mod in pairs:
        mod_index = 3.5  # heavy FM index -> dense sidebands = metallic
        modulator = np.sin(2 * np.pi * mod * t)
        phase = 2 * np.pi * carrier * t + mod_index * modulator
        sig += np.sin(phase)
    sig = bpf(sig, 6000, 10000)
    return sig * np.exp(-t / 0.015)


def approach_e_hybrid(n):
    """Real 808 oscillator frequencies, but bandlimited (pre-filtered)
    squares summed at full float resolution before the main BPF -- avoids
    the harsh staircase while preserving authentic beating pattern."""
    t = np.arange(n) / SR
    sig = np.zeros(n)
    for f in HH_FREQS:
        sq = np.sign(np.sin(2 * np.pi * f * t))
        # bandlimit each oscillator individually before summing (soften edges)
        sq = bpf(sq, max(50, f * 0.5), 12000, order=1)
        sig += sq
    sig = bpf(sig, 6000, 10000)
    return sig * np.exp(-t / 0.015)


def approach_f_squares_plus_noise(n):
    """6 squares (authentic 808 frequencies/beating) + small amount of
    high-frequency noise mixed in before the BPF. Real analog oscillators
    have jitter/noise the pure digital np.sign() squares lack; this fills
    in the spectral gaps between the discrete square harmonics, raising
    flatness toward the real reference without abandoning the 808 topology."""
    t = np.arange(n) / SR
    sig = np.zeros(n)
    for f in HH_FREQS:
        sig += np.sign(np.sin(2 * np.pi * f * t))
    rng = np.random.default_rng(1)
    noise = rng.standard_normal(n)
    # Scale noise relative to the square sum's RMS so it fills gaps without
    # dominating the fundamental beating pattern.
    noise_gain = 1.2 * np.std(sig)
    sig = sig + noise * noise_gain
    sig = bpf(sig, 6000, 10000)
    return sig * np.exp(-t / 0.015)


def approach_g_squares_plus_noise_wide(n):
    """Same as F but with a wider/brighter BPF matching the reference's
    higher centroid (~12kHz) more closely."""
    t = np.arange(n) / SR
    sig = np.zeros(n)
    for f in HH_FREQS:
        sig += np.sign(np.sin(2 * np.pi * f * t))
    rng = np.random.default_rng(1)
    noise = rng.standard_normal(n)
    noise_gain = 1.5 * np.std(sig)
    sig = sig + noise * noise_gain
    sig = hpf(sig, 7000, order=2)
    return sig * np.exp(-t / 0.015)


def approach_h_tuned(n, noise_mult=1.0, hpf_fc=8500):
    """Tunable version of G for sweeping noise gain / filter cutoff to match
    the reference centroid (~11.9kHz) and flatness (~0.49) more precisely."""
    t = np.arange(n) / SR
    sig = np.zeros(n)
    for f in HH_FREQS:
        sig += np.sign(np.sin(2 * np.pi * f * t))
    rng = np.random.default_rng(1)
    noise = rng.standard_normal(n)
    noise_gain = noise_mult * np.std(sig)
    sig = sig + noise * noise_gain
    sig = hpf(sig, hpf_fc, order=2)
    return sig * np.exp(-t / 0.015)


def approach_i_bandpass_tuned(n, noise_mult=0.5, lo=6000, hi=14000, order=3):
    """Bandpass (not just highpass) version: constrains both the square
    harmonics and the injected noise to a band centered near the reference's
    measured centroid (~11.9kHz), using a steeper (order=3) filter so energy
    actually rolls off above ~14kHz instead of leaking to Nyquist."""
    t = np.arange(n) / SR
    sig = np.zeros(n)
    for f in HH_FREQS:
        sig += np.sign(np.sin(2 * np.pi * f * t))
    rng = np.random.default_rng(1)
    noise = rng.standard_normal(n)
    noise_gain = noise_mult * np.std(sig)
    sig = sig + noise * noise_gain
    sig = bpf(sig, lo, hi, order=order)
    return sig * np.exp(-t / 0.015)


def approach_j_balanced(n, noise_mult=1.2, lo=5500, hi=13000, order=2):
    """Gentle (order=2) bandpass, but with noise gain increased to compensate
    for the extra attenuation a bandpass (vs a plain highpass) introduces at
    the edges -- aims to hit both centroid and flatness targets together."""
    t = np.arange(n) / SR
    sig = np.zeros(n)
    for f in HH_FREQS:
        sig += np.sign(np.sin(2 * np.pi * f * t))
    rng = np.random.default_rng(1)
    noise = rng.standard_normal(n)
    noise_gain = noise_mult * np.std(sig)
    sig = sig + noise * noise_gain
    sig = bpf(sig, lo, hi, order=order)
    return sig * np.exp(-t / 0.015)


def main():
    n = int(0.3 * SR)
    approaches = {
        "A_current_squares": approach_a_current,
        "H1_tuned_1.0x_8500hz": lambda n: approach_h_tuned(n, 1.0, 8500),
        "I1_bp_0.5x_6-14k_o3": lambda n: approach_i_bandpass_tuned(n, 0.5, 6000, 14000, 3),
        "J1_bal_1.2x_5.5-13k_o2": lambda n: approach_j_balanced(n, 1.2, 5500, 13000, 2),
        "J2_bal_1.5x_5.5-13k_o2": lambda n: approach_j_balanced(n, 1.5, 5500, 13000, 2),
        "J3_bal_1.8x_6-13k_o2": lambda n: approach_j_balanced(n, 1.8, 6000, 13000, 2),
        "J4_bal_1.5x_6-12k_o2": lambda n: approach_j_balanced(n, 1.5, 6000, 12000, 2),
        "J5_bal_2.5x_6-13k_o2": lambda n: approach_j_balanced(n, 2.5, 6000, 13000, 2),
        "J6_bal_3.0x_7-14k_o2": lambda n: approach_j_balanced(n, 3.0, 7000, 14000, 2),
        "J7_bal_4.0x_7-14k_o2": lambda n: approach_j_balanced(n, 4.0, 7000, 14000, 2),
        "J8_bal_2.5x_6.5-13k_o1": lambda n: approach_j_balanced(n, 2.5, 6500, 13000, 1),
        "J9_bal_2.0x_6.5-13k_o1": lambda n: approach_j_balanced(n, 2.0, 6500, 13000, 1),
        "J10_bal_3.0x_6.5-13k_o1": lambda n: approach_j_balanced(n, 3.0, 6500, 13000, 1),
        "J11_bal_2.5x_6-12k_o1": lambda n: approach_j_balanced(n, 2.5, 6000, 12000, 1),
    }

    print("Generating prototype WAVs...")
    results = {}
    for name, fn in approaches.items():
        sig = fn(n)
        save_wav(f"{name}.wav", sig)
        results[name] = {
            "centroid_hz": spectral_centroid(sig),
            "flatness": spectral_flatness(sig),
            "steppiness": quantization_step_metric(sig),
        }

    # Reference for comparison, if available
    ref_path = os.path.join(
        os.path.dirname(os.path.abspath(__file__)), "..", "docs", "TR808WAV", "CH"
    )
    print("\nMetrics (lower steppiness = smoother / less staircase artifact):")
    print(f"{'approach':<24} {'centroid(Hz)':>14} {'flatness':>10} {'steppiness':>12}")
    for name, m in results.items():
        print(f"{name:<24} {m['centroid_hz']:>14.1f} {m['flatness']:>10.4f} {m['steppiness']:>12.5f}")

    if os.path.isdir(ref_path):
        import glob
        wavs = glob.glob(os.path.join(ref_path, "*.WAV")) + glob.glob(os.path.join(ref_path, "*.wav"))
        if wavs:
            import wave
            with wave.open(wavs[0], 'r') as w:
                sr = w.getframerate()
                data = np.frombuffer(w.readframes(w.getnframes()), dtype=np.int16).astype(float)
            data = data / max(np.abs(data).max(), 1)
            print(f"\nReference ({os.path.basename(wavs[0])}):")
            print(f"  centroid_hz={spectral_centroid(data, sr):.1f} flatness={spectral_flatness(data):.4f}")


if __name__ == "__main__":
    main()
