# Spartan-3E Drum Machine

808-style drum machine + 303-style acid bass synthesizer running on the Xilinx Spartan-3E Starter Kit (XC3S500E-FG320-4). All sound synthesis in pure VHDL — no CPU, no samples, no software.

## Features

- **4 drum voices:** kick, snare, hi-hat, clap — all synthesized in logic
- **303-style bass:** saw/square oscillator with resonant low-pass filter, slide & accent
- **16-step sequencer** with per-voice pattern editing
- **VGA display:** 640×480 text-mode UI showing pattern grid (8-color, retro aesthetic)
- **PS/2 keyboard:** full editing — piano keys for note entry, number keys for step toggle
- **MIDI pattern loading:** upload patterns from PC via UART using a Python script
- **Mono audio output:** 12-bit DAC at ~48.8 kHz on header J5

## Hardware Setup

| Connection | Details |
|-----------|---------|
| Audio out | J5 header pin 1 (DAC A) → powered speaker/amp, pin 5 → GND |
| Display | VGA cable to monitor (640×480, 8 colors) |
| Keyboard | PS/2 keyboard to PS/2 port |
| Serial | RS-232 DCE port (or USB-serial adapter) for pattern upload |
| Program | USB-JTAG cable |

## Controls

### PS/2 Keyboard

| Key | Function |
|-----|----------|
| Space | Play / Stop |
| 1-9, 0 | Toggle steps 1-10 |
| ↑/↓ | Select track (kick/snare/hat/clap/bass) |
| ←/→ | Move cursor |
| Z X C V B N M | Piano keys (bass note entry): C D E F G A B |
| S D G H J | Sharps: C# D# F# G# A# |
| +/- | Tempo up/down |
| Tab | Switch drum/bass editing |
| Enter | Toggle accent |
| Backspace | Clear track pattern |

### On-board Controls

| Control | Function |
|---------|----------|
| Rotary turn | Tempo adjust |
| Rotary press | Play/Stop |
| BTN North | — |
| LEDs | Playhead position (8 steps visible) |
| LCD | BPM + status |
| Switches | TBD (pattern bank, voice select) |

## Architecture

```
┌─────────────────────────────────────────────────────┐
│                     top.vhd                          │
├──────────┬──────────┬───────────┬──────────┬────────┤
│ Sequencer│  Drums   │   Bass    │   UI     │ Serial │
│          │          │           │          │        │
│ tempo    │ kick     │ oscillator│ VGA text │ UART   │
│ clock    │ snare    │ filter    │ PS/2 kbd │ rx     │
│ patterns │ hi-hat   │ envelope  │ LCD ctrl │        │
│ playhead │ clap     │ slide     │          │        │
├──────────┴──────────┴───────────┴──────────┴────────┤
│              Mixer → SPI DAC (48.8 kHz)              │
└─────────────────────────────────────────────────────┘
```

## Resource Budget (estimated)

| Block | Slices | BRAM | Multipliers |
|-------|--------|------|-------------|
| Drum voices | ~400 | 0 | 0 |
| Bass (osc + filter) | ~350 | 0 | 5 |
| Sequencer + patterns | ~200 | 1 | 0 |
| VGA text mode | ~550 | 3-5 | 0 |
| PS/2 keyboard | ~150 | 0 | 0 |
| UART receiver | ~100 | 0 | 0 |
| Infrastructure | ~200 | 0 | 0 |
| **Total** | **~1,950** | **4-6** | **5** |
| **Available** | **4,656** | **20** | **20** |

## Pattern Upload (MIDI)

Load patterns from standard MIDI files:

```bash
python3 scripts/load_pattern.py --port /dev/ttyUSB0 pattern.mid
```

The script parses MIDI, maps GM drum notes to voices, quantizes to 16 steps, and sends via serial. Search "808 MIDI patterns free" for ready-made content.

## Build

### Requirements

- Xilinx ISE 14.7 (WebPack, free license)
- xc3sprog (JTAG programmer)
- Linux / WSL

### Compile

```bash
source /opt/Xilinx/14.7/ISE_DS/settings64.sh
make
```

### Program

```bash
sudo xc3sprog -c xpc -p 0 build/top.bit
```

## Project Structure

```
src/
  top.vhd                  — Top-level entity
  infrastructure/          — Debounce, rotary, SPI master, LCD controller
  drums/                   — Drum voice modules (kick, snare, hat, clap)
  bass/                    — 303 bass (oscillator, filter, envelope)
  sequencer/               — Step sequencer, tempo clock, pattern RAM
  ui/                      — VGA text display, PS/2 keyboard handler
  serial/                  — UART pattern receiver
constraints/
  top.ucf                  — Pin assignments
build/
  top.xst, top.prj         — Synthesis scripts
scripts/
  load_pattern.py          — MIDI → serial pattern loader
docs/
  — Design notes
```

## Status

🚧 **Work in progress** — project structure set up, implementation starting.
