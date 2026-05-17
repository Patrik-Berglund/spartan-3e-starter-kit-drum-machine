#!/usr/bin/env python3
"""Generate TR-808 reference WAV files. 48828 Hz, 16-bit mono."""

import numpy as np
from scipy.signal import butter, lfilter
import wave, struct, os

SR = 48828
OUT = os.path.dirname(os.path.abspath(__file__))

def save_wav(filename, samples):
    """Save float samples [-1,1] as 16-bit mono WAV."""
    samples = np.clip(samples, -1, 1)
    data = (samples * 32767).astype(np.int16)
    with wave.open(os.path.join(OUT, filename), 'w') as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes(data.tobytes())

def highpass(sig, cutoff, order=2):
    b, a = butter(order, cutoff / (SR/2), btype='high')
    return lfilter(b, a, sig)

def bandpass(sig, low, high, order=2):
    b, a = butter(order, [low/(SR/2), high/(SR/2)], btype='band')
    return lfilter(b, a, sig)

def square_osc(freq, n_samples):
    return np.sign(np.sin(2*np.pi*freq*np.arange(n_samples)/SR))

# --- 01 KICK ---
def gen_kick():
    dur = 0.3
    n = int(dur * SR)
    t = np.arange(n) / SR
    # Pitch sweep: 112->56 Hz in 5ms
    tau_pitch = 0.005
    freq = 56 + 56 * np.exp(-t / tau_pitch)
    phase = 2*np.pi * np.cumsum(freq) / SR
    sig = np.sin(phase)
    # Amplitude envelope
    env = np.exp(-t / 0.08)
    sig *= env
    # Click transient
    sig[0] = 1.0
    sig[1] = -0.8
    save_wav("01_kick_bd.wav", sig)
    return sig

# --- 02 SNARE ---
def gen_snare():
    dur = 0.2
    n = int(dur * SR)
    t = np.arange(n) / SR
    # Tones
    tone = 0.5*np.sin(2*np.pi*238*t) + 0.5*np.sin(2*np.pi*476*t)
    tone *= np.exp(-t / 0.06)
    # Bandpass-filtered noise
    noise = np.random.randn(n)
    noise = bandpass(noise, 500, 5000)
    noise = noise / (np.max(np.abs(noise)) + 1e-9)
    noise *= np.exp(-t / 0.1)
    sig = 0.5*tone + 0.5*noise
    sig /= np.max(np.abs(sig)) + 1e-9
    save_wav("02_snare_sd.wav", sig)
    return sig

# --- 03 CLOSED HIHAT ---
def gen_ch(decay=0.05, hpf_cutoff=6000, filename="03_closed_hihat_ch.wav"):
    dur = decay * 6
    n = int(dur * SR)
    t = np.arange(n) / SR
    freqs = [204.7, 304.4, 369.6, 522.7, 540.4, 800.6]
    sig = sum(square_osc(f, n) for f in freqs) / len(freqs)
    sig = highpass(sig, hpf_cutoff)
    sig = sig / (np.max(np.abs(sig)) + 1e-9)
    sig *= np.exp(-t / decay)
    save_wav(filename, sig)
    return sig

# --- 04 OPEN HIHAT ---
def gen_oh():
    return gen_ch(decay=0.3, hpf_cutoff=6000, filename="04_open_hihat_oh.wav")

# --- 05 CYMBAL ---
def gen_cy():
    return gen_ch(decay=0.8, hpf_cutoff=4000, filename="05_cymbal_cy.wav")

# --- 06 COWBELL ---
def gen_cowbell():
    dur = 0.15
    n = int(dur * SR)
    t = np.arange(n) / SR
    sig = 0.5*square_osc(540, n) + 0.5*square_osc(800, n)
    # Bandpass ~800Hz, Q~3 -> BW = 800/3 ~ 267 -> 667-933
    sig = bandpass(sig, 667, 933)
    sig = sig / (np.max(np.abs(sig)) + 1e-9)
    sig *= np.exp(-t / 0.05)
    save_wav("06_cowbell_cb.wav", sig)
    return sig

# --- 07 HANDCLAP ---
def gen_clap():
    burst_dur = 0.005
    gap_dur = 0.015
    tail_dur = 0.15
    total_dur = 3*(burst_dur + gap_dur) + tail_dur
    n = int(total_dur * SR)
    t = np.arange(n) / SR
    # Bandpass-filtered noise
    noise = np.random.randn(n)
    noise = bandpass(noise, 750, 1250)
    noise = noise / (np.max(np.abs(noise)) + 1e-9)
    # Build envelope: 3 bursts then decay tail
    env = np.zeros(n)
    pos = 0
    for i in range(3):
        b_start = int(pos * SR)
        b_end = int((pos + burst_dur) * SR)
        env[b_start:b_end] = 1.0
        pos += burst_dur + gap_dur
    # Tail with exponential decay
    tail_start = int(pos * SR)
    env[tail_start:] = np.exp(-np.arange(n - tail_start) / (0.1 * SR))
    sig = noise * env
    sig /= np.max(np.abs(sig)) + 1e-9
    save_wav("07_handclap_cp.wav", sig)
    return sig

# --- 08 RIMSHOT ---
def gen_rimshot():
    dur = 0.02
    n = int(dur * SR)
    t = np.arange(n) / SR
    tau = 0.001
    sig = (np.sin(2*np.pi*800*t) + np.sin(2*np.pi*1500*t) + np.sin(2*np.pi*2500*t)) / 3
    sig *= np.exp(-t / tau)
    sig = highpass(sig, 600)
    sig = sig / (np.max(np.abs(sig)) + 1e-9)
    save_wav("08_rimshot_rs.wav", sig)
    return sig

# --- 09 TOM ---
def gen_tom():
    dur = 0.2
    n = int(dur * SR)
    t = np.arange(n) / SR
    # Pitch dive 160->135 in 5ms
    freq = 135 + 25 * np.exp(-t / 0.005)
    phase = 2*np.pi * np.cumsum(freq) / SR
    sig = np.sin(phase)
    sig *= np.exp(-t / 0.1)
    save_wav("09_tom_mt.wav", sig)
    return sig

# --- 10 DEMO PATTERN ---
def gen_demo():
    bpm = 120
    steps = 16
    step_dur = 60.0 / bpm / 4  # 16th notes
    total_dur = 4.0
    n = int(total_dur * SR)
    mix = np.zeros(n)

    def place(voice_samples, step):
        start = int(step * step_dur * SR)
        end = min(start + len(voice_samples), n)
        mix[start:end] += voice_samples[:end-start]

    # Generate voices fresh for mixing
    kick = gen_kick_raw()
    snare = gen_snare_raw()
    ch = gen_ch_raw()
    oh = gen_oh_raw()
    clap = gen_clap_raw()

    # BD on 1,9 (0-indexed: 0,8)
    for s in [0, 8]:
        place(kick, s)
    # SD on 5,13 (0-indexed: 4,12)
    for s in [4, 12]:
        place(snare, s)
    # CH on every even step
    for s in [0,2,4,6,8,10,12,14]:
        place(ch, s)
    # OH on 9 (0-indexed: 8) - wait, instructions say "OH on 9" meaning step 9 = index 8? 
    # "BD on steps 1,9" - these are 1-indexed. So OH on step 9 = index 8
    # But BD is also on step 9/index 8. Let me re-read...
    # "BD on steps 1,9; SD on 5,13; CH on every even step (0,2,4,6,8,10,12,14); OH on 9; CP on 11"
    # CH uses 0-indexed. So pattern is 0-indexed throughout.
    # BD: 1,9 (these look 1-indexed given CH is 0-indexed with even numbers)
    # Actually CH "every even step (0,2,4,6,8,10,12,14)" - that's 0-indexed.
    # BD on steps 1,9 means 1-indexed -> 0,8
    # SD on 5,13 -> 4,12
    # OH on 9 -> 8
    # CP on 11 -> 10
    place(oh, 8)
    place(clap, 10)

    # Normalize
    peak = np.max(np.abs(mix))
    if peak > 0:
        mix = mix / peak * 0.9
    save_wav("10_demo_pattern.wav", mix)

# Raw generators (return float arrays without saving)
def gen_kick_raw():
    dur = 0.3; n = int(dur*SR); t = np.arange(n)/SR
    freq = 56 + 56*np.exp(-t/0.005)
    phase = 2*np.pi*np.cumsum(freq)/SR
    sig = np.sin(phase) * np.exp(-t/0.08)
    sig[0] = 1.0; sig[1] = -0.8
    return sig

def gen_snare_raw():
    dur = 0.2; n = int(dur*SR); t = np.arange(n)/SR
    tone = 0.5*np.sin(2*np.pi*238*t) + 0.5*np.sin(2*np.pi*476*t)
    tone *= np.exp(-t/0.06)
    noise = np.random.randn(n)
    noise = bandpass(noise, 500, 5000)
    noise = noise/(np.max(np.abs(noise))+1e-9)
    noise *= np.exp(-t/0.1)
    sig = 0.5*tone + 0.5*noise
    return sig / (np.max(np.abs(sig))+1e-9)

def gen_ch_raw():
    decay=0.05; n=int(0.3*SR); t=np.arange(n)/SR
    freqs=[204.7,304.4,369.6,522.7,540.4,800.6]
    sig = sum(square_osc(f,n) for f in freqs)/len(freqs)
    sig = highpass(sig, 6000)
    sig = sig/(np.max(np.abs(sig))+1e-9)
    sig *= np.exp(-t/decay)
    return sig * 0.6

def gen_oh_raw():
    decay=0.3; n=int(1.8*SR); t=np.arange(n)/SR
    freqs=[204.7,304.4,369.6,522.7,540.4,800.6]
    sig = sum(square_osc(f,n) for f in freqs)/len(freqs)
    sig = highpass(sig, 6000)
    sig = sig/(np.max(np.abs(sig))+1e-9)
    sig *= np.exp(-t/decay)
    return sig * 0.5

def gen_clap_raw():
    burst_dur=0.005; gap_dur=0.015; tail_dur=0.15
    total_dur = 3*(burst_dur+gap_dur)+tail_dur
    n=int(total_dur*SR); t=np.arange(n)/SR
    noise = np.random.randn(n)
    noise = bandpass(noise, 750, 1250)
    noise = noise/(np.max(np.abs(noise))+1e-9)
    env = np.zeros(n); pos=0
    for i in range(3):
        b_s=int(pos*SR); b_e=int((pos+burst_dur)*SR)
        env[b_s:b_e]=1.0; pos+=burst_dur+gap_dur
    tail_s=int(pos*SR)
    env[tail_s:] = np.exp(-np.arange(n-tail_s)/(0.1*SR))
    sig = noise*env
    return sig/(np.max(np.abs(sig))+1e-9) * 0.7

if __name__ == "__main__":
    print("Generating TR-808 reference WAVs...")
    gen_kick(); print("  01_kick_bd.wav")
    gen_snare(); print("  02_snare_sd.wav")
    gen_ch(); print("  03_closed_hihat_ch.wav")
    gen_oh(); print("  04_open_hihat_oh.wav")
    gen_cy(); print("  05_cymbal_cy.wav")
    gen_cowbell(); print("  06_cowbell_cb.wav")
    gen_clap(); print("  07_handclap_cp.wav")
    gen_rimshot(); print("  08_rimshot_rs.wav")
    gen_tom(); print("  09_tom_mt.wav")
    gen_demo(); print("  10_demo_pattern.wav")
    print("Done!")
