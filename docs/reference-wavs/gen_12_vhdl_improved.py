#!/usr/bin/env python3
"""
Generate 12_vhdl_improved.wav — FPGA-compatible drum machine simulation.
All arithmetic is integer-only (shifts, multiplies, adds). No floats in synthesis.
"""
import wave, struct, os, random

SR = 48828
OUT = os.path.dirname(os.path.abspath(__file__))

SINE_TABLE = [
    0,201,399,594,783,965,1137,1299,1447,1582,1702,1805,1891,1959,2008,2037,
    2047,2037,2008,1959,1891,1805,1702,1582,1447,1299,1137,965,783,594,399,201,
    0,-201,-399,-594,-783,-965,-1137,-1299,-1447,-1582,-1702,-1805,-1891,-1959,
    -2008,-2037,-2047,-2037,-2008,-1959,-1891,-1805,-1702,-1582,-1447,-1299,
    -1137,-965,-783,-594,-399,-201
]

def save_wav(filename, samples_int16):
    """Save list of int16 samples as WAV."""
    with wave.open(os.path.join(OUT, filename), 'w') as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(SR)
        for s in samples_int16:
            w.writeframes(struct.pack('<h', max(-32767, min(32767, s))))


class LFSR16:
    """16-bit LFSR for noise generation (taps at 16,14,13,11 — maximal)."""
    def __init__(self, seed=0xACE1):
        self.state = seed

    def next(self):
        bit = ((self.state >> 0) ^ (self.state >> 2) ^ (self.state >> 3) ^ (self.state >> 5)) & 1
        self.state = ((self.state >> 1) | (bit << 15)) & 0xFFFF
        # Return signed 12-bit value
        val = self.state & 0xFFF
        if val >= 2048:
            val -= 4096
        return val


def hpf_4stage(samples, shift=3):
    """4-stage cascaded HPF. Each stage: acc += (in - acc) >> shift; out = in - acc."""
    acc = [0, 0, 0, 0]
    out = []
    for s in samples:
        x = s
        for i in range(4):
            diff = x - acc[i]
            acc[i] += diff >> shift
            x = diff - (diff >> shift)  # x = input - acc (after update) ≈ input - acc
            # Actually: out = in - acc_new = in - (acc_old + (in-acc_old)>>shift)
            # Simpler: just do out = in - acc after update
            x = x  # already correct: x = diff - (diff>>shift) which is the HP output
        out.append(x)
    return out


def hpf_4stage_v2(samples, shift=3):
    """4-stage cascaded HPF. Each: acc += (in-acc)>>shift; out = in - acc."""
    acc = [0, 0, 0, 0]
    out = []
    for s in samples:
        x = s
        for i in range(4):
            acc[i] += (x - acc[i]) >> shift
            x = x - acc[i]
        out.append(x)
    return out


def gen_kick(n_samples):
    """Kick: sine with pitch sweep, exponential decay (K=12)."""
    # Phase accumulator: start at high freq, sweep down
    # Freq 112Hz -> 56Hz. Phase inc = freq * 64 / SR (64 entries in table)
    # At 112Hz: inc = 112*64/48828 ≈ 0.1468 (use fixed point 16.16)
    # inc_start = int(112 * 64 * 65536 / SR) = 9614
    # inc_end = int(56 * 64 * 65536 / SR) = 4807
    # Pitch decay: subtract (inc - inc_end) >> 5 each sample for fast sweep
    
    inc_start = int(112 * 64 * 65536 / SR)  # ~9614
    inc_end = int(56 * 64 * 65536 / SR)     # ~4807
    
    phase = 0  # 16.16 fixed point, table index = phase >> 16, then & 63
    inc = inc_start
    amp = 65535  # 16-bit amplitude
    
    out = [0] * n_samples
    
    # Pitch sweep: exponential with K=6 (tau=64 samples ≈ 1.3ms)
    for i in range(n_samples):
        # Sine lookup
        idx = (phase >> 16) & 63
        sine_val = SINE_TABLE[idx]  # -2047..2047 (12-bit)
        
        # Output: sine * amp >> 16 gives 12-bit output, scale to 16-bit
        sample = (sine_val * (amp >> 4)) >> 12  # 12-bit * 12-bit >> 12 = 12-bit
        out[i] = sample
        
        # Phase advance
        phase = (phase + inc) & 0xFFFFFFFF
        
        # Pitch sweep: exponential decay toward inc_end
        if inc > inc_end:
            inc -= (inc - inc_end) >> 5  # tau ≈ 32 samples ≈ 0.65ms (fast sweep)
        
        # Amplitude decay: K=12 (tau=4096 samples ≈ 84ms)
        amp -= amp >> 12
        if amp < 0:
            amp = 0
    
    # Add click transient
    if n_samples > 2:
        out[0] = 2047
        out[1] = -1600
    
    return out


def gen_snare(n_samples):
    """Snare: two sine tones + filtered noise, exponential decays."""
    # Tone: 238Hz + 476Hz
    inc1 = int(238 * 64 * 65536 / SR)  # phase increment for 238Hz
    inc2 = int(476 * 64 * 65536 / SR)  # phase increment for 476Hz
    
    phase1 = 0
    phase2 = 0
    amp_tone = 65535   # K=11, tau=2048 samples ≈ 42ms
    amp_noise = 65535  # K=12, tau=4096 samples ≈ 84ms
    
    lfsr = LFSR16(0xBEEF)
    
    tone_out = [0] * n_samples
    noise_raw = [0] * n_samples
    
    for i in range(n_samples):
        # Tone component
        idx1 = (phase1 >> 16) & 63
        idx2 = (phase2 >> 16) & 63
        t = (SINE_TABLE[idx1] + SINE_TABLE[idx2]) >> 1  # average, stays 12-bit
        tone_sample = (t * (amp_tone >> 4)) >> 12
        tone_out[i] = tone_sample
        
        phase1 = (phase1 + inc1) & 0xFFFFFFFF
        phase2 = (phase2 + inc2) & 0xFFFFFFFF
        amp_tone -= amp_tone >> 11
        
        # Noise component
        noise_val = lfsr.next()  # -2048..2047
        noise_sample = (noise_val * (amp_noise >> 4)) >> 12
        noise_raw[i] = noise_sample
        
        amp_noise -= amp_noise >> 12
        if amp_noise < 512:
            amp_noise = 0
    
    # HPF the noise (2 stages, shift=4 for moderate cutoff ~3kHz)
    noise_hp = hpf_4stage_v2(noise_raw, shift=4)
    
    # Mix: tone + noise
    out = [0] * n_samples
    for i in range(n_samples):
        out[i] = (tone_out[i] + noise_hp[i]) >> 1
    
    return out


def gen_hihat(n_samples, amp_k):
    """Hi-hat: LFSR noise through 4-stage HPF, exponential decay."""
    lfsr = LFSR16(0xCAFE)
    amp = 65535
    
    raw = [0] * n_samples
    for i in range(n_samples):
        noise_val = lfsr.next()  # -2048..2047
        sample = (noise_val * (amp >> 4)) >> 12
        raw[i] = sample
        amp -= amp >> amp_k
        if amp < 512:
            amp = 0
    
    # 4-stage HPF with shift=3 (strong high-pass, ~6kHz cutoff)
    out = hpf_4stage_v2(raw, shift=3)
    return out


def gen_clap(n_samples):
    """Clap: 3 noise bursts + exponential tail, bandpass via HPF+LPF."""
    lfsr = LFSR16(0xDEAD)
    
    # Burst timing: 3 bursts of ~5ms with ~15ms gaps
    burst_len = int(0.005 * SR)   # ~244 samples
    gap_len = int(0.015 * SR)     # ~732 samples
    
    raw = [0] * n_samples
    amp = 0
    burst_count = 0
    sample_pos = 0
    in_burst = True
    burst_remaining = burst_len
    gap_remaining = 0
    tail_started = False
    tail_amp = 0
    
    for i in range(n_samples):
        noise_val = lfsr.next()
        
        if not tail_started:
            if in_burst:
                # During burst: full amplitude with fast decay
                amp = 65535 if burst_remaining == burst_len else amp
                amp -= amp >> 8  # very fast decay within burst
                burst_remaining -= 1
                if burst_remaining <= 0:
                    burst_count += 1
                    if burst_count >= 3:
                        tail_started = True
                        tail_amp = 50000
                    else:
                        in_burst = False
                        gap_remaining = gap_len
                        amp = 0
            else:
                gap_remaining -= 1
                if gap_remaining <= 0:
                    in_burst = True
                    burst_remaining = burst_len
                    amp = 65535
        else:
            # Tail: exponential decay K=12
            amp = tail_amp
            tail_amp -= tail_amp >> 12
        
        sample = (noise_val * (amp >> 4)) >> 12
        raw[i] = sample
    
    # Bandpass: HPF (shift=4) then LPF (simple 1-pole)
    hp = hpf_4stage_v2(raw, shift=4)
    
    # Simple LPF: acc += (in - acc) >> 2
    lp_acc = 0
    out = [0] * n_samples
    for i in range(n_samples):
        lp_acc += (hp[i] - lp_acc) >> 2
        out[i] = lp_acc
    
    return out


def gen_pattern():
    """Generate demo pattern: 120 BPM, 16 steps, 4 seconds."""
    bpm = 120
    step_samples = int(SR * 60 / bpm / 4)  # 16th note = 6103 samples
    total_samples = 4 * SR  # 4 seconds
    
    # Voice durations
    kick_dur = int(0.3 * SR)
    snare_dur = int(0.2 * SR)
    ch_dur = int(0.08 * SR)
    oh_dur = int(0.5 * SR)
    clap_dur = int(0.25 * SR)
    
    # Pre-render voices
    kick = gen_kick(kick_dur)
    snare = gen_snare(snare_dur)
    ch = gen_hihat(ch_dur, 11)   # K=11, tau=2048 ≈ 42ms
    oh = gen_hihat(oh_dur, 12)   # K=12, tau=4096 ≈ 84ms
    clap = gen_clap(clap_dur)
    
    # Pattern (0-indexed steps)
    pattern = {
        'kick':  [0, 8],
        'snare': [4, 12],
        'ch':    [0, 2, 4, 6, 8, 10, 12, 14],
        'oh':    [8],
        'clap':  [10],
    }
    
    # Mix buffer (32-bit to avoid overflow)
    mix = [0] * total_samples
    
    def place(voice, steps, gain_shift=0):
        """Place voice at given steps. gain_shift: right-shift for volume."""
        for step in steps:
            start = step * step_samples
            for j in range(len(voice)):
                pos = start + j
                if pos < total_samples:
                    mix[pos] += voice[j] >> gain_shift
            # Also place in second bar (steps 0-15 repeat at 16-31)
            start2 = (step + 16) * step_samples
            for j in range(len(voice)):
                pos = start2 + j
                if pos < total_samples:
                    mix[pos] += voice[j] >> gain_shift
    
    place(kick, pattern['kick'], 0)      # Full volume
    place(snare, pattern['snare'], 1)    # -6dB
    place(ch, pattern['ch'], 2)          # -12dB
    place(oh, pattern['oh'], 2)          # -12dB
    place(clap, pattern['clap'], 1)      # -6dB
    
    # 12-bit DAC truncation: clip mix to -2048..+2047 (matches FPGA saturating mixer)
    peak_before = max(abs(s) for s in mix)
    clipped = 0
    for i in range(total_samples):
        if mix[i] > 2047:
            mix[i] = 2047
            clipped += 1
        elif mix[i] < -2048:
            mix[i] = -2048
            clipped += 1
    print(f"  DAC truncation: peak_before={peak_before}, clipped {clipped}/{total_samples} samples")

    # Scale 12-bit range (-2048..2047) to 16-bit WAV range (-32768..32767)
    out = [0] * total_samples
    for i in range(total_samples):
        out[i] = mix[i] * 16  # 2047*16 = 32752, -2048*16 = -32768
    
    return out


if __name__ == "__main__":
    print("Generating 12_vhdl_improved.wav (FPGA-compatible integer synthesis)...")
    samples = gen_pattern()
    save_wav("12_vhdl_improved.wav", samples)
    print("Done! Written to docs/reference-wavs/12_vhdl_improved.wav")
    print()
    print("Changes from 11_vhdl_simulation.wav:")
    print("  1. EXPONENTIAL DECAY: amp -= amp >> K (per sample)")
    print("     - Kick K=12 (tau≈84ms), Snare tone K=11 (tau≈42ms)")
    print("     - Snare noise K=12, CH K=11, OH K=12, Clap K=12")
    print("     - 16-bit amplitude for smooth decay resolution")
    print("  2. 4-STAGE CASCADED HPF on metallic voices (24dB/oct rolloff)")
    print("     - Each stage: acc += (in-acc)>>3; out = in - acc")
    print("     - Much stronger than old 1-pole shift-by-3")
    print("  3. PROPER MIXING with gain staging (shifts for level control)")
    print("  4. 12-BIT DAC TRUNCATION: clip to -2048..+2047 before WAV output")
    print("     - Matches FPGA saturating mixer behavior")
    print("  All operations: integer multiply, shift, add only. FPGA-ready.")
