# TODO - TR-808 Enhancements

## Per-Voice Parameters
- [ ] Expand each voice with parameter ports (decay, tone/tuning, level)
- [ ] BD: Tone (pitch sweep range), Decay, Level
- [ ] SD: Tone (body pitch), Snappy (noise mix), Decay, Level
- [ ] LT/MT/HT: Tuning (base freq), Decay, Level
- [ ] RS: Tuning, Decay, Level
- [ ] CP: Tuning, Decay, Level
- [ ] CB: Tuning, Decay, Level
- [ ] CY: Tone (metallic character), Decay, Level
- [ ] OH: Decay, Level
- [ ] CH: Tuning, Decay, Level

## Parameter Storage & Editing
- [ ] Create param_store.vhd (register file: 12 tracks × 3 params × 8 bits)
- [ ] Update keyboard_ctrl: F1-F4 select parameter to edit
- [ ] Rotary encoder adjusts selected parameter value
- [ ] LCD shows "BD DECAY: 12" style feedback
- [ ] VGA: show param value bar or number near track label

## Mixer Enhancements
- [ ] Per-voice level applied in mixer (from param_store)
- [ ] Total Accent: boost volume on accented steps

## Shuffle / Swing
- [ ] Add shuffle amount (global, adjustable)
- [ ] Offset even-numbered steps by variable amount in tempo_clock

## Serial / MIDI
- [ ] UART receiver (31250 baud for MIDI, 115200 for pattern upload)
- [ ] Pattern upload mode: PC sends step data, board stores in sequencer
- [ ] MIDI sound module mode: note-on triggers voices in real-time (play from DAW)
- [ ] MIDI clock sync: lock internal sequencer to external tempo
- [ ] MIDI CC: control per-voice parameters from DAW
- [ ] Python script: .mid file → serial pattern upload

## Sound Refinements (IN PROGRESS)
The voices work but don't yet match the real 808 character. Use sim_vhdl.py vs sim_ideal.py
and the reference samples in docs/TR808WAV/ to A/B compare.

### Completed
- [x] Signal chain widened: 16-bit voices → 21-bit mixer → 12-bit DAC
- [x] First-order noise shaping at DAC output (+12dB in-band SNR)
- [x] Metallic voices: proper BPF (1-stage LP + 4-stage HP cascade, centroid ~7kHz)
- [x] Snare noise: 2-stage LP + HP bandpass
- [x] Kick: exponential pitch sweep
- [x] Correct 808 oscillator frequencies (205, 304, 370, 523, 540, 800 Hz)
- [x] sq width bugs fixed (cowbell 4-bit, hihats/cymbal 5-bit)
- [x] Full 16-bit multiply for filtered voices (no 12-bit truncation before multiply)

### Next: Quality Gap (sounds "C64-like")
- [ ] **Metallic voices use higher-resolution source waveforms** — current 6 square oscillators produce only 7 amplitude levels (3-bit effective). Use full 16-bit phase accumulator (triangle/saw) per oscillator to get rich beating patterns before BPF. Model in sim_vhdl.py first.
- [ ] **Explore FM synthesis for metallic voices** — two sine oscillators with non-harmonic FM ratios naturally produce rich metallic spectra (like real cymbal/hihat). No need for 6 crude squares + aggressive filtering. We already have the sine table. Could replace the entire metallic voice topology. Start with sim_ideal.py prototype comparing FM metallic vs current approach.
- [ ] Snare LFSR noise is 1-bit — consider multi-bit noise source
- [ ] Cowbell BPF Q still too wide (sounds "Mario")
- [ ] Clap envelope timing needs tuning against reference
- [ ] Overall mix balance tuning
- [ ] Consider 2× oversampling (SPI headroom available at 12.5MHz)

### Future: Audio Capture Buffer
- [ ] BRAM capture buffer (4-8 BRAMs = 84-168ms of audio)
- [ ] Configurable source: mixer output or individual voice (0-11)
- [ ] UART dump command to download captured audio to PC
- [ ] Python script to receive and save as WAV for comparison
