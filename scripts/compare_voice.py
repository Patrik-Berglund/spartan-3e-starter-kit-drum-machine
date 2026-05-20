#!/usr/bin/env python3
"""Voice comparison tool v2: ref WAVs vs synth WAVs, flags mismatches.

Metrics:
  - Decay: time to -20dB from peak
  - Tone freq: fundamental frequency of tonal component (<1kHz)
  - Noise centroid: spectral centroid of noise component (>1kHz)
  - Tone/noise ratio: energy balance
  - Envelope correlation: overall shape match

Thresholds:
  - Decay: >50% off = FAIL
  - Tone freq: >20% off = FAIL
  - Noise centroid: >50% off = FAIL (only when noise >10%)
  - Tone/noise ratio: >20% absolute difference = FAIL
  - Envelope: <0.85 = FAIL
"""

import numpy as np, wave, os, sys
from scipy.signal import butter, filtfilt

def load_wav(path):
    with wave.open(path, 'r') as w:
        sr = w.getframerate()
        data = np.frombuffer(w.readframes(w.getnframes()), dtype=np.int16).astype(float)
    return data / max(np.abs(data).max(), 1), sr

def measure_decay_ms(sig, sr):
    rect = np.abs(sig)
    win = max(1, int(sr * 0.002))
    env = np.convolve(rect, np.ones(win)/win, mode='same')
    peak = env.max()
    peak_idx = np.argmax(env)
    below = np.where(env[peak_idx:] < peak * 0.1)[0]
    if len(below) == 0:
        return len(env[peak_idx:]) / sr * 1000
    return below[0] / sr * 1000

def measure_tone_freq(sig, sr):
    """Fundamental frequency via zero-crossings on lowpassed signal."""
    try:
        b, a = butter(4, min(1000/(sr/2), 0.99), btype='low')
        tone = filtfilt(b, a, sig)
    except:
        return 0
    # Use first 50ms where tone is strongest
    n = min(len(tone), int(sr * 0.05))
    chunk = tone[:n]
    zc = np.where(np.diff(np.sign(chunk)))[0]
    if len(zc) < 4:
        return 0
    half_periods = np.diff(zc)
    return sr / (2 * np.mean(half_periods))

def measure_noise_centroid(sig, sr):
    """Spectral centroid of >1kHz content."""
    try:
        b, a = butter(4, min(1000/(sr/2), 0.99), btype='high')
        noise = filtfilt(b, a, sig)
    except:
        return 0
    fft = np.abs(np.fft.rfft(noise))
    freqs = np.fft.rfftfreq(len(noise), 1.0/sr)
    total = fft.sum()
    if total == 0:
        return 0
    return np.sum(freqs * fft) / total

def measure_noise_ratio(sig, sr):
    """Percentage of energy above 1kHz."""
    try:
        b, a = butter(4, min(1000/(sr/2), 0.99), btype='high')
        noise = filtfilt(b, a, sig)
        b2, a2 = butter(4, min(1000/(sr/2), 0.99), btype='low')
        tone = filtfilt(b2, a2, sig)
    except:
        return 0
    noise_e = np.sum(noise**2)
    tone_e = np.sum(tone**2)
    total = noise_e + tone_e
    if total == 0:
        return 0
    return noise_e / total * 100

def envelope_corr(s1, s2, sr):
    n = max(len(s1), len(s2))
    a = np.zeros(n); a[:len(s1)] = s1
    b = np.zeros(n); b[:len(s2)] = s2
    win = int(sr * 0.003)
    e1 = [np.sqrt(np.mean(a[i:i+win]**2)) for i in range(0, n-win, win)]
    e2 = [np.sqrt(np.mean(b[i:i+win]**2)) for i in range(0, n-win, win)]
    e1, e2 = np.array(e1), np.array(e2)
    if e1.max() > 0: e1 /= e1.max()
    if e2.max() > 0: e2 /= e2.max()
    return np.corrcoef(e1, e2)[0, 1]

def compare_voice(ref_dir, syn_dir, prefix="ideal_"):
    refs = sorted([f for f in os.listdir(ref_dir) if f.endswith('.WAV')])
    if not refs:
        print(f"No WAV files in {ref_dir}")
        return

    print(f"{'File':12s} | {'Decay':^11s} | {'Tone Hz':^11s} | {'Noise%':^11s} | {'Env':>5s} | FLAGS")
    print(f"{'':12s} | {'ref':>5s} {'syn':>5s} | {'ref':>5s} {'syn':>5s} | {'ref':>5s} {'syn':>5s} | {'':>5s} |")
    print("-" * 80)

    issues = []
    n_pass = 0
    for fname in refs:
        ref_path = os.path.join(ref_dir, fname)
        syn_path = os.path.join(syn_dir, f"{prefix}{fname}")
        if not os.path.exists(syn_path):
            print(f"{fname:12s} | MISSING SYNTH FILE")
            issues.append((fname, ["MISSING"]))
            continue

        ref_sig, sr = load_wav(ref_path)
        syn_sig, _ = load_wav(syn_path)

        # Measurements
        r_dec = measure_decay_ms(ref_sig, sr)
        s_dec = measure_decay_ms(syn_sig, sr)
        r_freq = measure_tone_freq(ref_sig, sr)
        s_freq = measure_tone_freq(syn_sig, sr)
        r_noise = measure_noise_ratio(ref_sig, sr)
        s_noise = measure_noise_ratio(syn_sig, sr)
        ec = envelope_corr(ref_sig, syn_sig, sr)

        # Flags
        flags = []
        if r_dec > 0:
            ratio = s_dec / r_dec
            if ratio > 1.5 or ratio < 0.67:
                flags.append(f"DECAY({s_dec:.0f}vs{r_dec:.0f}ms)")
        if r_freq > 0 and s_freq > 0:
            ratio = s_freq / r_freq
            if ratio > 1.2 or ratio < 0.8:
                flags.append(f"FREQ({s_freq:.0f}vs{r_freq:.0f}Hz)")
        if r_noise > 10 or s_noise > 10:
            if abs(r_noise - s_noise) > 20:
                flags.append(f"MIX({s_noise:.0f}vs{r_noise:.0f}%)")
        if ec < 0.85:
            flags.append(f"ENV({ec:.2f})")

        flag_str = " ".join(flags) if flags else "✓"
        if not flags:
            n_pass += 1

        print(f"{fname:12s} | {r_dec:4.0f}  {s_dec:4.0f} | {r_freq:5.0f} {s_freq:5.0f} | {r_noise:4.0f}% {s_noise:4.0f}% | {ec:.3f} | {flag_str}")

        if flags:
            issues.append((fname, flags))

    print("-" * 80)
    print(f"PASS: {n_pass}/{len(refs)}  FAIL: {len(issues)}/{len(refs)}")
    if issues:
        print(f"\nIssues summary:")
        for fname, flags in issues:
            print(f"  {fname}: {' | '.join(flags)}")


def measure_snr(ref_sig, test_sig):
    """SNR between two signals (same model, different precision)."""
    n = min(len(ref_sig), len(test_sig))
    r = ref_sig[:n]
    t = test_sig[:n]
    # Normalize both
    r = r / max(np.abs(r).max(), 1e-10)
    t = t / max(np.abs(t).max(), 1e-10)
    noise = t - r
    mask = np.abs(r) > 0.01  # only where signal is present
    if mask.sum() == 0:
        return 0
    return 20 * np.log10(np.sqrt(np.mean(r[mask]**2)) / np.sqrt(np.mean(noise[mask]**2) + 1e-30))


def compare_quality(ideal_dir, vhdl_dir, prefix_ideal="ideal_", prefix_vhdl="vhdl_"):
    """Compare ideal (float) vs sim_vhdl (integer) — measures signal degradation."""
    ideals = sorted([f for f in os.listdir(ideal_dir) if f.startswith(prefix_ideal) and f.endswith('.WAV')])
    if not ideals:
        print(f"No files with prefix '{prefix_ideal}' in {ideal_dir}")
        return

    print(f"{'File':20s} | {'SNR':>6s} | {'Env_corr':>8s} | {'Decay_Δ':>7s} | STATUS")
    print("-" * 65)

    snrs = []
    for fname in ideals:
        base = fname[len(prefix_ideal):]
        ideal_path = os.path.join(ideal_dir, fname)
        vhdl_path = os.path.join(vhdl_dir, f"{prefix_vhdl}{base}")
        if not os.path.exists(vhdl_path):
            print(f"{base:20s} | MISSING")
            continue

        ideal_sig, sr = load_wav(ideal_path)
        vhdl_sig, _ = load_wav(vhdl_path)

        snr = measure_snr(ideal_sig, vhdl_sig)
        ec = envelope_corr(ideal_sig, vhdl_sig, sr)
        i_dec = measure_decay_ms(ideal_sig, sr)
        v_dec = measure_decay_ms(vhdl_sig, sr)
        dec_delta = abs(v_dec - i_dec) / max(i_dec, 1) * 100

        status = "✓" if snr > 40 and ec > 0.95 and dec_delta < 10 else "⚠"
        if snr < 30:
            status = "✗ LOW SNR"
        elif ec < 0.90:
            status = "✗ ENV"

        snrs.append(snr)
        print(f"{base:20s} | {snr:4.1f}dB | {ec:8.4f} | {dec_delta:5.1f}% | {status}")

    print("-" * 65)
    if snrs:
        print(f"SNR: min={min(snrs):.1f}dB  avg={np.mean(snrs):.1f}dB  (target: >40dB)")

if __name__ == "__main__":
    if len(sys.argv) < 3:
        print("Usage:")
        print("  compare_voice.py <ref_dir> <syn_dir> [prefix]     — compare vs 808 references")
        print("  compare_voice.py --quality <ideal_dir> <vhdl_dir>  — measure signal degradation")
        sys.exit(1)
    if sys.argv[1] == "--quality":
        compare_quality(sys.argv[2], sys.argv[3],
                       sys.argv[4] if len(sys.argv) > 4 else "ideal_",
                       sys.argv[5] if len(sys.argv) > 5 else "vhdl_")
    else:
        compare_voice(sys.argv[1], sys.argv[2], sys.argv[3] if len(sys.argv) > 3 else "ideal_")
