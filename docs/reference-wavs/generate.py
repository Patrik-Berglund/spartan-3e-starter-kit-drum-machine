#!/usr/bin/env python3
"""Generate TR-808 reference WAV files per service manual specs."""
import numpy as np
import wave, struct, os

SR = 48828
OUT = os.path.dirname(os.path.abspath(__file__))

def save_wav(name, samples):
    samples = np.clip(samples, -1.0, 1.0)
    data = (samples * 32767).astype(np.int16)
    with wave.open(os.path.join(OUT, name), 'w') as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes(data.tobytes())

def bandpass(sig, fc, Q):
    w0 = 2 * np.pi * fc / SR
    alpha = np.sin(w0) / (2 * Q)
    b0 = alpha; b1 = 0; b2 = -alpha
    a0 = 1 + alpha; a1 = -2 * np.cos(w0); a2 = 1 - alpha
    return biquad(sig, b0/a0, b1/a0, b2/a0, a1/a0, a2/a0)

def highpass(sig, fc, Q=0.707):
    w0 = 2 * np.pi * fc / SR
    alpha = np.sin(w0) / (2 * Q)
    b0 = (1 + np.cos(w0)) / 2; b1 = -(1 + np.cos(w0)); b2 = b0
    a0 = 1 + alpha; a1 = -2 * np.cos(w0); a2 = 1 - alpha
    return biquad(sig, b0/a0, b1/a0, b2/a0, a1/a0, a2/a0)

def biquad(sig, b0, b1, b2, a1, a2):
    out = np.zeros_like(sig)
    x1 = x2 = y1 = y2 = 0.0
    for i in range(len(sig)):
        x0 = sig[i]
        y0 = b0*x0 + b1*x1 + b2*x2 - a1*y1 - a2*y2
        out[i] = y0
        x2, x1 = x1, x0
        y2, y1 = y1, y0
    return out

def metallic_source(n_samples, freqs, seed=42):
    rng = np.random.default_rng(seed)
    phases = rng.uniform(0, 2*np.pi, len(freqs))
    t = np.arange(n_samples) / SR
    sig = np.zeros(n_samples)
    for f, ph in zip(freqs, phases):
        sig += np.sign(np.sin(2*np.pi*f*t + ph))
    return sig / len(freqs)

METAL_FREQS = [204.7, 304.4, 369.6, 522.7, 540.4, 800.6]

# 1. Kick
def gen_kick():
    dur = 0.6
    n = int(dur * SR)
    t = np.arange(n) / SR
    tau = 0.5 / 5  # 500ms decay, tau = time to ~e^-5
    punch_n = int(0.004 * SR)
    freq = np.where(np.arange(n) < punch_n, 112.0, 56.0)
    phase = np.cumsum(2 * np.pi * freq / SR)
    sig = np.sin(phase) * np.exp(-t / (0.5 / 5))
    save_wav("01_kick_bd.wav", sig * 0.9)

# 2. Snare
def gen_snare():
    dur = 0.15
    n = int(dur * SR)
    t = np.arange(n) / SR
    tau = 0.06 / 5
    body = np.sin(2*np.pi*238*t) * np.exp(-t / tau)
    noise = np.random.default_rng(1).standard_normal(n)
    snappy = bandpass(noise, 1000, 3) * np.exp(-t / tau)
    snappy /= (np.max(np.abs(snappy)) + 1e-10)
    sig = 0.5 * body + 0.5 * snappy
    save_wav("02_snare_sd.wav", sig * 0.9)

# 3. Closed Hi-Hat
def gen_ch():
    dur = 0.08
    n = int(dur * SR)
    t = np.arange(n) / SR
    src = metallic_source(n, METAL_FREQS)
    sig = bandpass(src, 10000, 1.5)
    sig = highpass(sig, 7000)
    sig *= np.exp(-t / (0.05 / 5))
    sig /= (np.max(np.abs(sig)) + 1e-10)
    save_wav("03_closed_hihat_ch.wav", sig * 0.9)

# 4. Open Hi-Hat
def gen_oh():
    dur = 0.6
    n = int(dur * SR)
    t = np.arange(n) / SR
    src = metallic_source(n, METAL_FREQS)
    sig = bandpass(src, 10000, 1.5)
    sig = highpass(sig, 7000)
    sig *= np.exp(-t / (0.45 / 5))
    sig /= (np.max(np.abs(sig)) + 1e-10)
    save_wav("04_open_hihat_oh.wav", sig * 0.9)

# 5. Cymbal
def gen_cy():
    dur = 1.0
    n = int(dur * SR)
    t = np.arange(n) / SR
    src = metallic_source(n, METAL_FREQS, seed=77)
    sig = bandpass(src, 8000, 2)
    sig = highpass(sig, 6000)
    sig *= np.exp(-t / (0.8 / 5))
    sig /= (np.max(np.abs(sig)) + 1e-10)
    save_wav("05_cymbal_cy.wav", sig * 0.9)

# 6. Cowbell
def gen_cb():
    dur = 0.08
    n = int(dur * SR)
    t = np.arange(n) / SR
    src = metallic_source(n, [540.0, 800.0], seed=33)
    sig = bandpass(src, 670, 3)
    sig *= np.exp(-t / (0.05 / 5))
    sig /= (np.max(np.abs(sig)) + 1e-10)
    save_wav("06_cowbell_cb.wav", sig * 0.9)

# 7. Handclap
def gen_cp():
    dur = 0.2
    n = int(dur * SR)
    t = np.arange(n) / SR
    noise = np.random.default_rng(7).standard_normal(n)
    filtered = bandpass(noise, 1000, 3)
    filtered /= (np.max(np.abs(filtered)) + 1e-10)
    env = np.zeros(n)
    # 3 bursts in first 30ms, each ~10ms apart, sawtooth shape
    burst_starts = [0, int(0.010*SR), int(0.020*SR)]
    burst_tau = 0.004
    for bs in burst_starts:
        for i in range(bs, min(bs + int(0.010*SR), n)):
            env[i] += np.exp(-(i - bs) / SR / burst_tau)
    # 4th reverb tail starting at 30ms
    tail_start = int(0.030 * SR)
    tail_tau = 0.1 / 5
    for i in range(tail_start, n):
        env[i] += np.exp(-(i - tail_start) / SR / tail_tau)
    sig = filtered * env
    sig /= (np.max(np.abs(sig)) + 1e-10)
    save_wav("07_handclap_cp.wav", sig * 0.9)

# 8. Rimshot
def gen_rs():
    dur = 0.02
    n = int(dur * SR)
    t = np.arange(n) / SR
    tau = 0.01 / 5
    # Three resonant frequencies around 455Hz
    sig = (np.sin(2*np.pi*455*t) + np.sin(2*np.pi*364*t) + np.sin(2*np.pi*546*t)) / 3
    sig *= np.exp(-t / tau)
    save_wav("08_rimshot_rs.wav", sig * 0.9)

# 9. Tom
def gen_tom():
    dur = 0.2
    n = int(dur * SR)
    t = np.arange(n) / SR
    # Pitch dive: start ~1.5x base, settle to 135Hz with fast exponential
    pitch_tau = 0.015
    freq_t = 135 * (1 + 0.5 * np.exp(-t / pitch_tau))
    phase = np.cumsum(2 * np.pi * freq_t / SR)
    sig = np.sin(phase) * np.exp(-t / (0.13 / 5))
    save_wav("09_tom_mt.wav", sig * 0.9)

# 10. Demo pattern
def gen_demo():
    bpm = 120
    step_samples = int(SR * 60 / bpm / 4)  # 16th note
    n_steps = 32  # 2 bars
    total = step_samples * n_steps * 2  # loop twice
    out = np.zeros(total)

    # Pre-render each voice
    def render_kick():
        n = int(0.6 * SR)
        t = np.arange(n) / SR
        punch_n = int(0.004 * SR)
        freq = np.where(np.arange(n) < punch_n, 112.0, 56.0)
        phase = np.cumsum(2 * np.pi * freq / SR)
        return np.sin(phase) * np.exp(-t / (0.5/5))

    def render_snare():
        n = int(0.15 * SR)
        t = np.arange(n) / SR
        tau = 0.06 / 5
        body = np.sin(2*np.pi*238*t) * np.exp(-t / tau)
        noise = np.random.default_rng(1).standard_normal(n)
        snappy = bandpass(noise, 1000, 3) * np.exp(-t / tau)
        snappy /= (np.max(np.abs(snappy)) + 1e-10)
        return 0.5 * body + 0.5 * snappy

    def render_ch():
        n = int(0.08 * SR)
        t = np.arange(n) / SR
        src = metallic_source(n, METAL_FREQS)
        sig = bandpass(src, 10000, 1.5)
        sig = highpass(sig, 7000)
        sig *= np.exp(-t / (0.05/5))
        sig /= (np.max(np.abs(sig)) + 1e-10)
        return sig

    def render_oh():
        n = int(0.6 * SR)
        t = np.arange(n) / SR
        src = metallic_source(n, METAL_FREQS)
        sig = bandpass(src, 10000, 1.5)
        sig = highpass(sig, 7000)
        sig *= np.exp(-t / (0.45/5))
        sig /= (np.max(np.abs(sig)) + 1e-10)
        return sig

    def render_cp():
        n = int(0.2 * SR)
        t = np.arange(n) / SR
        noise = np.random.default_rng(7).standard_normal(n)
        filtered = bandpass(noise, 1000, 3)
        filtered /= (np.max(np.abs(filtered)) + 1e-10)
        env = np.zeros(n)
        burst_starts = [0, int(0.010*SR), int(0.020*SR)]
        for bs in burst_starts:
            for i in range(bs, min(bs + int(0.010*SR), n)):
                env[i] += np.exp(-(i - bs) / SR / 0.004)
        tail_start = int(0.030 * SR)
        for i in range(tail_start, n):
            env[i] += np.exp(-(i - tail_start) / SR / (0.1/5))
        sig = filtered * env
        sig /= (np.max(np.abs(sig)) + 1e-10)
        return sig

    bd = render_kick()
    sd = render_snare()
    ch = render_ch()
    oh = render_oh()
    cp = render_cp()

    def place(voice, step, gain=0.7):
        for loop in range(2):
            pos = (loop * 32 + step) * step_samples
            end = min(pos + len(voice), total)
            out[pos:end] += voice[:end-pos] * gain

    # BD on 0, 8 (per bar, so 0,8,16,24 in 32 steps)
    for s in [0, 8, 16, 24]:
        place(bd, s, 0.8)
    # SD on 4, 12
    for s in [4, 12, 20, 28]:
        place(sd, s, 0.7)
    # CH on even steps
    for s in range(0, 32, 2):
        place(ch, s, 0.5)
    # OH on 8
    for s in [8, 24]:
        place(oh, s, 0.5)
    # CP on 10
    for s in [10, 26]:
        place(cp, s, 0.6)

    out /= (np.max(np.abs(out)) + 1e-10)
    save_wav("10_demo_pattern.wav", out * 0.9)

if __name__ == "__main__":
    print("Generating TR-808 reference WAVs...")
    gen_kick(); print("  01_kick_bd.wav")
    gen_snare(); print("  02_snare_sd.wav")
    gen_ch(); print("  03_closed_hihat_ch.wav")
    gen_oh(); print("  04_open_hihat_oh.wav")
    gen_cy(); print("  05_cymbal_cy.wav")
    gen_cb(); print("  06_cowbell_cb.wav")
    gen_cp(); print("  07_handclap_cp.wav")
    gen_rs(); print("  08_rimshot_rs.wav")
    gen_tom(); print("  09_tom_mt.wav")
    gen_demo(); print("  10_demo_pattern.wav")
    print("Done.")
