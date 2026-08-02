#!/usr/bin/env python3
"""Compare rimshot synthesis (bit-exact VHDL sim) against real 808 RS.WAV."""

import numpy as np
import wave, os, sys

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
REF_WAV = os.path.join(SCRIPT_DIR, "../docs/TR808WAV/RS/RS.WAV")
OUT_DIR = os.path.join(SCRIPT_DIR, "output_compare")

# VHDL parameters
SR_FPGA = 48828
SINE = [0,201,399,594,783,965,1137,1299,1447,1582,1702,1805,1891,1959,2008,2037,
        2047,2037,2008,1959,1891,1805,1702,1582,1447,1299,1137,965,783,594,399,201,
        0,-201,-399,-594,-783,-965,-1137,-1299,-1447,-1582,-1702,-1805,-1891,-1959,
        -2008,-2037,-2047,-2037,-2008,-1959,-1891,-1805,-1702,-1582,-1447,-1299,
        -1137,-965,-783,-594,-399,-201]

def render_rimshot(n_samples, incs=(610, 912, 1368), decay_k=8):
    phases = [0, 0, 0]
    amp = 65535
    out = []
    for _ in range(n_samples):
        if amp < 64:
            out.append(0); continue
        s = 0
        for i in range(3):
            s += SINE[(phases[i] >> 10) & 63] >> 2
        s = max(-2048, min(2047, s))
        val = (s * (amp >> 5)) >> 11
        out.append(max(-2048, min(2047, val)))
        for i in range(3):
            phases[i] = (phases[i] + incs[i]) & 0xFFFF
        amp -= amp >> decay_k
    return np.array(out, dtype=np.float64)

def load_wav(path):
    with wave.open(path, 'r') as w:
        sr = w.getframerate()
        n = w.getnframes()
        raw = w.readframes(n)
        if w.getsampwidth() == 2:
            data = np.frombuffer(raw, dtype=np.int16).astype(np.float64)
        else:
            data = np.frombuffer(raw, dtype=np.uint8).astype(np.float64) - 128
            data *= 256
    return data, sr

def envelope(sig, window=64):
    """RMS envelope."""
    env = np.zeros(len(sig))
    for i in range(len(sig)):
        start = max(0, i - window//2)
        end = min(len(sig), i + window//2)
        env[i] = np.sqrt(np.mean(sig[start:end]**2))
    return env

def spectral_peaks(sig, sr, n_peaks=5):
    """Find top frequency peaks."""
    fft = np.abs(np.fft.rfft(sig))
    freqs = np.fft.rfftfreq(len(sig), 1.0/sr)
    # Only look at 100-3000 Hz range
    mask = (freqs > 100) & (freqs < 3000)
    fft_masked = fft.copy()
    fft_masked[~mask] = 0
    indices = np.argsort(fft_masked)[-n_peaks:][::-1]
    return [(freqs[i], fft[i]) for i in indices]

def main():
    os.makedirs(OUT_DIR, exist_ok=True)

    # Load reference
    ref, ref_sr = load_wav(REF_WAV)
    print(f"Reference: {REF_WAV}")
    print(f"  Sample rate: {ref_sr} Hz, Length: {len(ref)} samples ({len(ref)/ref_sr*1000:.1f} ms)")
    print(f"  Peak amplitude: {np.max(np.abs(ref)):.0f}")

    # Normalize reference to ±2048 range (12-bit) for fair comparison
    ref_norm = ref / np.max(np.abs(ref)) * 2047

    # Generate synth at reference sample rate for spectral comparison
    # Need to recalculate phase increments for 44100 Hz
    # Original: inc = freq * 65536 / SR_FPGA
    # At ref_sr: inc = freq * 65536 / ref_sr
    f1, f2, f3 = 455, 680, 1020  # Target frequencies
    inc1_ref = int(f1 * 65536 / ref_sr)
    inc2_ref = int(f2 * 65536 / ref_sr)
    inc3_ref = int(f3 * 65536 / ref_sr)
    print(f"\n  Phase incs at {ref_sr}Hz: {inc1_ref}, {inc2_ref}, {inc3_ref}")
    print(f"  Actual freqs: {inc1_ref*ref_sr/65536:.1f}, {inc2_ref*ref_sr/65536:.1f}, {inc3_ref*ref_sr/65536:.1f} Hz")

    # Also show what the FPGA actually produces
    print(f"\n  FPGA phase incs at {SR_FPGA}Hz: 610, 912, 1368")
    print(f"  FPGA actual freqs: {610*SR_FPGA/65536:.1f}, {912*SR_FPGA/65536:.1f}, {1368*SR_FPGA/65536:.1f} Hz")

    # Render at ref sample rate for comparison
    synth = render_rimshot(len(ref), incs=(inc1_ref, inc2_ref, inc3_ref), decay_k=8)

    # Spectral analysis
    print(f"\n--- Spectral Peaks (reference) ---")
    ref_peaks = spectral_peaks(ref_norm, ref_sr)
    for freq, mag in ref_peaks:
        print(f"  {freq:.0f} Hz  (mag: {mag:.0f})")

    print(f"\n--- Spectral Peaks (synth) ---")
    syn_peaks = spectral_peaks(synth, ref_sr)
    for freq, mag in syn_peaks:
        print(f"  {freq:.0f} Hz  (mag: {mag:.0f})")

    # Envelope comparison
    ref_env = envelope(ref_norm)
    syn_env = envelope(synth)
    # Normalize envelopes
    ref_env /= max(ref_env.max(), 1)
    syn_env /= max(syn_env.max(), 1)

    # Find decay time (time to reach -20dB = 10% amplitude)
    ref_t10 = np.argmax(ref_env < 0.1) / ref_sr * 1000 if np.any(ref_env < 0.1) else -1
    syn_t10 = np.argmax(syn_env < 0.1) / ref_sr * 1000 if np.any(syn_env < 0.1) else -1
    print(f"\n--- Envelope Decay ---")
    print(f"  Reference -20dB time: {ref_t10:.1f} ms")
    print(f"  Synth -20dB time:     {syn_t10:.1f} ms")

    # Correlation of envelopes
    min_len = min(len(ref_env), len(syn_env))
    corr = np.corrcoef(ref_env[:min_len], syn_env[:min_len])[0,1]
    print(f"  Envelope correlation: {corr:.4f}")

    # Save synth WAV for listening
    out_path = os.path.join(OUT_DIR, "rimshot_synth.wav")
    data16 = np.clip(synth * 16, -32768, 32767).astype(np.int16)
    with wave.open(out_path, 'w') as w:
        w.setnchannels(1); w.setsampwidth(2); w.setframerate(ref_sr)
        w.writeframes(data16.tobytes())
    print(f"\n  Synth saved: {out_path}")

    # Save reference normalized for A/B listening
    out_ref = os.path.join(OUT_DIR, "rimshot_ref_norm.wav")
    ref16 = np.clip(ref_norm * 16, -32768, 32767).astype(np.int16)
    with wave.open(out_ref, 'w') as w:
        w.setnchannels(1); w.setsampwidth(2); w.setframerate(ref_sr)
        w.writeframes(ref16.tobytes())
    print(f"  Ref saved:   {out_ref}")

if __name__ == "__main__":
    main()
