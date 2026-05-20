#!/usr/bin/env python3
"""BD (Bass Drum) analysis: characterize references, run model, compare."""

import numpy as np, wave, os
from scipy.signal import hilbert

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
REF_DIR = os.path.join(SCRIPT_DIR, "../docs/TR808WAV/BD")
OUT_DIR = os.path.join(SCRIPT_DIR, "output_compare/BD")
os.makedirs(OUT_DIR, exist_ok=True)

SR_FPGA = 48828
SINE = [0,201,399,594,783,965,1137,1299,1447,1582,1702,1805,1891,1959,2008,2037,
        2047,2037,2008,1959,1891,1805,1702,1582,1447,1299,1137,965,783,594,399,201,
        0,-201,-399,-594,-783,-965,-1137,-1299,-1447,-1582,-1702,-1805,-1891,-1959,
        -2008,-2037,-2047,-2037,-2008,-1959,-1891,-1805,-1702,-1582,-1447,-1299,
        -1137,-965,-783,-594,-399,-201]

# --- Reference analysis ---

def load_wav(path):
    with wave.open(path, 'r') as w:
        sr = w.getframerate()
        data = np.frombuffer(w.readframes(w.getnframes()), dtype=np.int16).astype(float)
    return data, sr

def measure_freq(sig, sr):
    """Measure fundamental frequency via zero crossings in first 50ms."""
    n = min(len(sig), int(sr * 0.05))
    chunk = sig[:n]
    # Find zero crossings
    zc = np.where(np.diff(np.sign(chunk)))[0]
    if len(zc) < 4:
        return 0
    half_periods = np.diff(zc)
    return sr / (2 * np.mean(half_periods))

def measure_freq_late(sig, sr):
    """Measure frequency in the 50-150ms region (after pitch sweep settles)."""
    start = int(sr * 0.05)
    end = min(len(sig), int(sr * 0.15))
    if end - start < 100:
        return 0
    chunk = sig[start:end]
    zc = np.where(np.diff(np.sign(chunk)))[0]
    if len(zc) < 4:
        return 0
    half_periods = np.diff(zc)
    return sr / (2 * np.mean(half_periods))

def measure_decay(sig, sr):
    """Measure time to -20dB from peak using RMS envelope."""
    rect = np.abs(sig)
    # Smooth with 2ms window
    win = max(1, int(sr * 0.002))
    env = np.convolve(rect, np.ones(win)/win, mode='same')
    peak = env.max()
    peak_idx = np.argmax(env)
    env_from_peak = env[peak_idx:]
    # Time to 10% of peak (-20dB)
    below = np.where(env_from_peak < peak * 0.1)[0]
    if len(below) == 0:
        return len(env_from_peak) / sr * 1000  # never reaches -20dB
    return below[0] / sr * 1000

def spectral_centroid(sig, sr):
    """Spectral centroid in Hz."""
    fft = np.abs(np.fft.rfft(sig))
    freqs = np.fft.rfftfreq(len(sig), 1.0/sr)
    mask = freqs < 200  # only look below 200Hz for kick
    fft_low = fft.copy()
    fft_low[~mask] = 0
    total = fft_low.sum()
    if total == 0:
        return 0
    return np.sum(freqs * fft_low) / total


# --- Current model ---

def apply_lpf(samples):
    """Mixer LPF: lp += (input - lp) >> 2. Same as VHDL mixer."""
    lp = 0
    out = []
    for s in samples:
        s = max(-2048, min(2047, int(s)))
        lp += (s - lp) >> 2
        out.append(max(-2048, min(2047, lp)))
    return np.array(out, dtype=float)

def render_kick_current(n_samples):
    """Current sim_vhdl.py kick model - fixed parameters."""
    phase = 0; freq = 150; amp = 65535; div = 0
    out = []
    for _ in range(n_samples):
        if amp < 64:
            out.append(0); continue
        s = SINE[(phase >> 10) & 63]
        val = (s * (amp >> 5)) >> 11
        out.append(max(-2048, min(2047, val)))
        new_phase = (phase + freq) & 0xFFFF
        new_div = (div + 1) & 7
        new_freq = freq
        if div == 6 and freq > 75:
            new_freq = freq - 1
            new_div = 0
        new_amp = amp - (amp >> 12)
        phase, freq, amp, div = new_phase, new_freq, new_amp, new_div
    return apply_lpf(out)


def save_wav(path, samples, sr):
    data16 = np.clip(np.array(samples) * 16, -32768, 32767).astype(np.int16)
    with wave.open(path, 'w') as w:
        w.setnchannels(1); w.setsampwidth(2); w.setframerate(sr)
        w.writeframes(data16.tobytes())


def spectral_corr(sig1, sig2):
    """Spectral correlation between two signals (zero-padded to same length)."""
    n = max(len(sig1), len(sig2))
    s1 = np.zeros(n); s1[:len(sig1)] = sig1
    s2 = np.zeros(n); s2[:len(sig2)] = sig2
    f1 = np.abs(np.fft.rfft(s1))
    f2 = np.abs(np.fft.rfft(s2))
    return np.corrcoef(f1, f2)[0, 1]


def envelope_corr(sig1, sig2, sr):
    """Envelope correlation (RMS, 5ms window)."""
    n = max(len(sig1), len(sig2))
    s1 = np.zeros(n); s1[:len(sig1)] = sig1
    s2 = np.zeros(n); s2[:len(sig2)] = sig2
    win = int(sr * 0.005)
    e1 = np.array([np.sqrt(np.mean(s1[max(0,i-win):i+win]**2)) for i in range(0, n, win)])
    e2 = np.array([np.sqrt(np.mean(s2[max(0,i-win):i+win]**2)) for i in range(0, n, win)])
    if e1.max() > 0: e1 /= e1.max()
    if e2.max() > 0: e2 /= e2.max()
    return np.corrcoef(e1, e2)[0, 1]


# --- Main ---

def main():
    # Parse all BD reference files
    knob_settings = []  # (tone, decay, filename)
    for f in sorted(os.listdir(REF_DIR)):
        if not f.endswith('.WAV'):
            continue
        name = f.replace('.WAV', '')
        tone_str = name[2:4]
        decay_str = name[4:6]
        # Convert: '00'->0, '25'->2.5, '50'->5, '75'->7.5, '10'->10
        tone = float(tone_str) / 10.0 if tone_str != '10' else 10.0
        decay = float(decay_str) / 10.0 if decay_str != '10' else 10.0
        knob_settings.append((tone, decay, f))

    # Phase 1: Characterize references
    print("=" * 70)
    print("PHASE 1: Reference WAV characteristics")
    print("=" * 70)
    print(f"{'File':12s} {'TONE':>5s} {'DECAY':>5s} {'Freq_early':>10s} {'Freq_late':>10s} {'Decay_ms':>9s}")
    print("-" * 70)

    ref_data = {}
    for tone, decay, fname in knob_settings:
        sig, sr = load_wav(os.path.join(REF_DIR, fname))
        sig_norm = sig / max(np.abs(sig).max(), 1)
        f_early = measure_freq(sig, sr)
        f_late = measure_freq_late(sig, sr)
        decay_ms = measure_decay(sig, sr)
        print(f"{fname:12s} {tone:5.1f} {decay:5.1f} {f_early:8.1f}Hz {f_late:8.1f}Hz {decay_ms:7.1f}ms")
        ref_data[fname] = {'sig': sig_norm, 'sr': sr, 'tone': tone, 'decay': decay,
                           'freq_early': f_early, 'freq_late': f_late, 'decay_ms': decay_ms}

    # Summarize knob effects
    print("\n" + "=" * 70)
    print("KNOB EFFECTS SUMMARY")
    print("=" * 70)

    # Group by TONE (fix DECAY=5.0 mid)
    print("\nTONE effect (DECAY fixed at 5.0):")
    for tone in [0, 2.5, 5.0, 7.5, 10.0]:
        key = [k for k, v in ref_data.items() if v['tone'] == tone and v['decay'] == 5.0]
        if key:
            d = ref_data[key[0]]
            print(f"  TONE={tone:4.1f}: freq_early={d['freq_early']:.1f}Hz, freq_late={d['freq_late']:.1f}Hz, decay={d['decay_ms']:.0f}ms")

    # Group by DECAY (fix TONE=5.0 mid)
    print("\nDECAY effect (TONE fixed at 5.0):")
    for decay in [0, 2.5, 5.0, 7.5, 10.0]:
        key = [k for k, v in ref_data.items() if v['tone'] == 5.0 and v['decay'] == decay]
        if key:
            d = ref_data[key[0]]
            print(f"  DECAY={decay:4.1f}: freq_early={d['freq_early']:.1f}Hz, freq_late={d['freq_late']:.1f}Hz, decay={d['decay_ms']:.0f}ms")

    # Phase 2: Current model comparison
    print("\n" + "=" * 70)
    print("PHASE 2: Current model vs references (fixed params, no knobs)")
    print("=" * 70)

    # Generate model at FPGA rate, resample to 44100 for comparison
    model_raw = render_kick_current(SR_FPGA * 3)  # 3 seconds
    model_norm = model_raw / max(np.abs(model_raw).max(), 1)

    print(f"\nCurrent model: start~112Hz, end~56Hz, decay K=12")
    print(f"{'File':12s} {'TONE':>5s} {'DECAY':>5s} {'Spec_corr':>9s} {'Env_corr':>9s}")
    print("-" * 50)

    for tone, decay, fname in knob_settings:
        d = ref_data[fname]
        sig = d['sig']
        sr = d['sr']
        # Resample model to reference SR
        n_ref = len(sig)
        n_model = int(n_ref * SR_FPGA / sr)
        model_chunk = model_norm[:min(n_model, len(model_norm))]
        # Simple resample
        indices = np.linspace(0, len(model_chunk)-1, n_ref).astype(int)
        model_resampled = model_chunk[indices]

        sc = spectral_corr(sig, model_resampled)
        ec = envelope_corr(sig, model_resampled, sr)
        print(f"{fname:12s} {tone:5.1f} {decay:5.1f} {sc:9.4f} {ec:9.4f}")

    # Phase 3: Generate A/B WAVs for listening
    print("\n" + "=" * 70)
    print("PHASE 3: A/B WAVs for listening")
    print("=" * 70)

    # Generate at 5 key points: corners + center
    listen_points = [
        ('BD0000.WAV', 'min tone, min decay'),
        ('BD0010.WAV', 'min tone, max decay'),
        ('BD5050.WAV', 'mid tone, mid decay'),
        ('BD1000.WAV', 'max tone, min decay'),
        ('BD1010.WAV', 'max tone, max decay'),
    ]

    # Save model output at same duration as each reference
    for fname, desc in listen_points:
        d = ref_data[fname]
        sr = d['sr']
        n_ref = len(d['sig'])
        n_model = int(n_ref * SR_FPGA / sr)
        model_chunk = model_norm[:min(n_model, len(model_norm))]
        indices = np.linspace(0, len(model_chunk)-1, n_ref).astype(int)
        model_resampled = model_chunk[indices]

        out_path = os.path.join(OUT_DIR, f"synth_{fname}")
        save_wav(out_path, model_resampled * 2047, sr)

    print("\nA/B listening pairs:")
    for fname, desc in listen_points:
        print(f"  {desc}:")
        print(f"    REF: docs/TR808WAV/BD/{fname}")
        print(f"    SYN: scripts/output_compare/BD/synth_{fname}")
        print()


if __name__ == "__main__":
    main()
