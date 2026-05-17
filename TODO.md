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

## Sound Refinements
- [ ] BD: add click transient at attack
- [ ] SD: bandpass filter on noise component
- [ ] CY/OH: 6-square-wave metallic model (closer to real 808)
- [ ] Accent: velocity-sensitive trigger (louder hit)
