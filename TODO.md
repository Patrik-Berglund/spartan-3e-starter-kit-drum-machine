# TODO - TR-808 Enhancements

## Per-Voice Parameters (DONE)
- [x] Each voice has parameter ports (decay, tone/tuning, level) via register map
- [x] BD: Tone (base freq narrow range), Decay, Level
- [x] SD: Tone (tone mix ratio), Snappy (noise mix), Decay via K mapping, Level
- [x] LT/MT/HT: Tuning (freq_min/freq_range per voice), Decay, Level
- [x] RS: dual resonance (fixed, no tunable params — matches real 808)
- [x] CP: burst timing fixed, Level
- [x] CB: dual-oscillator + resonant filter, Level (no tunable params — matches real 808)
- [x] CY: Tone (filter brightness), Decay, Level
- [x] OH: Decay, Level
- [x] CH: fixed decay (no tunable params — matches real 808), Level

## Parameter Storage & Editing
- [ ] Create param_store.vhd (register file: 12 tracks × 3 params × 8 bits) for
      per-step/per-track parameter automation (current params are global per-voice,
      set via serial register writes — not yet editable from the on-board UI)
- [ ] Update keyboard_ctrl: F1-F4 select parameter to edit
- [ ] Rotary encoder adjusts selected parameter value
- [ ] LCD shows "BD DECAY: 12" style feedback
- [ ] VGA: show param value bar or number near track label

## Mixer Enhancements
- [ ] Per-voice level applied in mixer (currently level register exists but mixer
      does not yet apply per-voice level scaling)
- [ ] Total Accent: boost volume on accented steps

## Shuffle / Swing
- [ ] Add shuffle amount (global, adjustable)
- [ ] Offset even-numbered steps by variable amount in tempo_clock

## Serial / MIDI
- [ ] MIDI receiver (31250 baud) as an alternative to the current 115200 register protocol
- [ ] Pattern upload mode: PC sends step data, board stores in sequencer
- [ ] MIDI sound module mode: note-on triggers voices in real-time (play from DAW)
- [ ] MIDI clock sync: lock internal sequencer to external tempo
- [ ] MIDI CC: control per-voice parameters from DAW
- [ ] Python script: .mid file → serial pattern upload

## Sound Refinements

Voice-by-voice debugging pass against real 808 samples is complete for all 11
voices (BD/SD/LT/MT/HT/RS/CP/CB/CY/OH/CH). See AGENTS.md "Development Workflow"
for the sim-first methodology used, and git log for the fix history per voice.

### Completed
- [x] DAC sample capture buffer (12 BRAMs, 252ms, offset-based stitching for
      longer captures) + UART TX + Python capture_dump.py tool — see AGENTS.md
- [x] BD: 24-bit fractional phase accumulator, click transient, correct
      TONE/DECAY mapping vs real 808 measurements
- [x] SD: fixed frequencies (188/345Hz) with TONE as mix ratio, separate
      decay envelopes per tone, noise BPF retuned, fixed a critical unsigned
      underflow-wrap bug (envelope could wrap to max and re-trigger forever)
- [x] LT/MT/HT: fixed wrong frequencies (were using Low/High Conga freqs
      from the service manual table instead of Tom freqs), amplitude-dependent
      pitch sweep, per-voice decay constants
- [x] RS: fixed completely wrong frequencies (was 455/680/1020Hz 3-osc model;
      real 808 has 2 resonant modes at 458Hz + 1712Hz), dual independent
      decay envelopes
- [x] CP: fixed sim/VHDL BPF coefficient mismatch, corrected burst timing
      (4×5ms bursts, not 3×15ms), fixed 8x-too-quiet output gain, fixed decay
- [x] CB: removed erroneous noise (real 808 CB has no noise source per
      schematic), added resonant (SVF) filter, dual-decay envelope
- [x] CY/OH/CH: major architectural fix — old filters let 21-31% of energy
      leak through below 4kHz (real 808 has <2%), sounding "buzzy" instead
      of "shimmery". Redesigned with configurable per-stage HP shifts +
      output LP rolloff + gain compensation, retuned per-voice against real
      808 spectral centroid/ZCR/E<4kHz measurements. Found and fixed a
      critical VHDL signal-vs-variable timing bug in the filter cascade
      (see AGENTS.md XST Gotcha #7) that caused hardware clipping invisible
      to synthesis/P&R. Widened shared amp register 16→20 bit across
      CH/OH/CY to fix an audible "death click" at long decay settings.
- [x] Correct 808 oscillator frequencies (205, 304, 370, 523, 540, 800 Hz)
- [x] Full 16-bit multiply for filtered voices (no 12-bit truncation before multiply)

### Possible further refinements (not blocking)
- [ ] CY/OH real 808 envelope is dual-exponential (fast + slow component);
      current implementation approximates with a single K per DECAY
      setting — a true second amp register would improve long-tail accuracy
- [ ] CH→OH choke (CH trigger should kill OH envelope on the real 808) —
      not yet implemented, voices currently trigger independently
- [ ] Snare LFSR noise is 1-bit — consider multi-bit noise source
- [ ] Explore FM synthesis as an alternative metallic voice topology (two
      sine oscillators with non-harmonic FM ratios) — current 6-square-osc
      + filter approach now matches real 808 spectral measurements
      reasonably well after the CY/OH/CH rework, so this is lower priority
      than originally thought
- [ ] Overall mix balance tuning across all 11 voices together
- [ ] Consider 2× oversampling (SPI headroom available at 12.5MHz)
- [ ] MULT18X18 at 95% (19/20) — any new voice feature needing a multiply
      will likely need shift-and-add instead (see AGENTS.md Gotcha #8)
