# TR-808 Voice Synthesis Reference

Based on analysis of the original TR-808 service manual schematics and
various DSP implementations (Aaron Lanterman's GT course, Yee-King, etc.)

## Bass Drum (BD)
- **Topology**: Bridged-T oscillator (self-oscillating bandpass)
- **Frequency**: Starts at ~320 Hz, sweeps down to ~51 Hz
- **Pitch envelope**: Exponential decay, time constant ~30ms
- **Amplitude envelope**: Exponential decay, time constant ~200ms (DECAY knob: 100-500ms)
- **Key character**: Initial click transient (1-2 samples of full-scale pulse)
- **TONE knob**: Controls pitch sweep depth (more tone = higher start freq)
- **Output**: Pure sine, no harmonics

## Snare Drum (SD)
- **Topology**: Two bridged-T oscillators + noise source
- **Tone 1**: ~180 Hz sine, fast decay (~50ms)
- **Tone 2**: ~330 Hz sine, fast decay (~50ms)  
- **Noise**: White noise through bandpass filter (center ~5kHz, Q~3)
- **Noise envelope**: Exponential decay, ~100ms (DECAY knob)
- **TONE knob**: Mix ratio between tones and noise
- **SNAPPY knob**: Noise amplitude (0 = pure tone, max = mostly noise)
- **Key character**: The two non-harmonic tones give the "body"

## Closed Hi-Hat (CH)
- **Topology**: 6 square wave oscillators at non-harmonic frequencies, summed, then bandpass filtered
- **Frequencies**: 204.7, 369.6, 304.4, 522.7, 540.4, 800.6 Hz
- **Filter**: Highpass ~6kHz + bandpass resonance ~10kHz
- **Envelope**: Very fast decay, ~20-30ms
- **Key character**: Metallic shimmer from non-harmonic squares

## Open Hi-Hat (OH)
- **Same oscillator bank as CH**
- **Envelope**: Much longer decay, ~200-500ms (DECAY knob)
- **CH trigger cuts OH** (mutual exclusion in original)

## Cymbal (CY)
- **Same 6-oscillator topology as hihats**
- **Filter**: Different bandpass, lower center (~8kHz), wider Q
- **Envelope**: Long decay, ~500ms-2s
- **TONE knob**: Filter frequency

## Hand Clap (CP)
- **Topology**: Noise source → bandpass filter → envelope
- **Filter**: Bandpass centered ~1kHz, Q~2
- **Envelope**: 4 short bursts (each ~5ms) with ~15ms gaps, then sustained decay (~150ms)
- **Key character**: The repeated bursts simulate multiple hands

## Rim Shot (RS)
- **Topology**: Short pulse excites a bandpass filter
- **Frequency**: ~500 Hz resonance
- **Envelope**: Extremely short, ~5ms total
- **Key character**: Sharp metallic "tick"

## Toms (LT/MT/HT)
- **Topology**: Bridged-T oscillator (like BD but higher pitched)
- **Low Tom**: ~100 Hz
- **Mid Tom**: ~150 Hz  
- **Hi Tom**: ~200 Hz
- **Pitch envelope**: Slight downward sweep (~10% over decay time)
- **Amplitude envelope**: ~100-200ms (DECAY knob)
- **TUNING knob**: Base frequency ±50%

## Cowbell (CB)
- **Topology**: 2 square wave oscillators at non-harmonic frequencies
- **Frequencies**: ~540 Hz and ~800 Hz
- **Filter**: Bandpass ~800Hz, Q~5
- **Envelope**: ~50ms decay (short, metallic)
- **TUNING knob**: Both frequencies shift together

## Key Implementation Notes for FPGA

### Sample Rate
48828 Hz (50MHz / 1024)

### Exponential Decay
Real 808 uses RC discharge: `amp = amp * (1 - 1/tau)`
In fixed-point: `amp <= amp - shift_right(amp, N)` where N controls time constant.
- N=4: tau ≈ 16 samples = 0.33ms (very fast)
- N=6: tau ≈ 64 samples = 1.3ms
- N=8: tau ≈ 256 samples = 5.2ms  
- N=10: tau ≈ 1024 samples = 21ms
- N=12: tau ≈ 4096 samples = 84ms
- N=14: tau ≈ 16384 samples = 335ms

### Metallic Sound (Hihats/Cymbal)
The 6 square waves at non-harmonic ratios are essential. White noise does NOT sound like a hihat.
Frequencies (Hz): 204.7, 369.6, 304.4, 522.7, 540.4, 800.6
Phase increments at 48828 Hz (20-bit accumulator):
- 204.7 Hz: inc = 4396
- 304.4 Hz: inc = 6537  
- 369.6 Hz: inc = 7937
- 522.7 Hz: inc = 11225
- 540.4 Hz: inc = 11605
- 800.6 Hz: inc = 17191

### Pitch Envelope (Kick)
Start freq: 320 Hz (inc = 6872)
End freq: 51 Hz (inc = 1095)
Sweep time: ~30ms = 1465 samples
Per-sample freq decrement: (6872-1095)/1465 ≈ 4 per sample

## Reference Samples

Real TR-808 voice samples for A/B comparison:
https://audio.com/drum-machine/collections/roland-tr-808
