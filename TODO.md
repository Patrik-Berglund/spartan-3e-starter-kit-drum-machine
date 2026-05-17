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
and the reference samples at https://audio.com/drum-machine/collections/roland-tr-808 to A/B compare.

Known gaps:
- [ ] Kick still sounds more like a sub sweep than a punchy thump (needs faster pitch sweep, shorter decay at default)
- [ ] Cowbell sounds too "Mario" (bandpass Q needs tuning)
- [ ] Clap noise is still harsh (bandpass too wide?)
- [ ] Rimshot needs frequency/decay tuning against reference
- [ ] Overall mix balance: hats too loud relative to kick
- [ ] Consider 2× oversampling (SPI headroom available at 12.5MHz)
- [ ] External RC filter on J5 output (10nF cap) would help significantly
