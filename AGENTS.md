# AGENTS.md

## Project

808-style drum machine + 303-style acid bass on the Xilinx Spartan-3E Starter Kit.
Mono audio output via SPI DAC (LTC2624 channel A on header J5).

## Board

Xilinx Spartan-3E Starter Kit (XC3S500E-FG320-4).

## Toolchain

- Xilinx ISE 14.7 (CLI tools: xst, ngdbuild, map, par, bitgen)
- Source environment: `source /opt/Xilinx/14.7/ISE_DS/settings64.sh`
- Programmer: `xc3sprog` (not iMPACT — libusb issues on WSL)
- Language: VHDL-93 (do NOT use `-vhdl2008`)
- No GUI tools — CLI only

## Build

```bash
source /opt/Xilinx/14.7/ISE_DS/settings64.sh
make
```

Flow: xst → ngdbuild → map → par → bitgen

## Program

```bash
sudo xc3sprog -c xpc -p 0 build/top.bit
```

## Architecture

```
src/
  top.vhd              — Top-level: clock, reset, module instantiation, DAC output
  infrastructure/      — Reusable modules (debounce, rotary, SPI master, LCD)
  drums/               — Drum voice synthesis (kick, snare, hat, clap)
  bass/                — 303-style bass (oscillator, resonant filter, envelope)
  sequencer/           — Step sequencer, pattern storage, tempo clock
  ui/                  — VGA text-mode display, PS/2 keyboard input
  serial/              — UART receiver for pattern upload from PC
constraints/           — UCF pin assignments
build/                 — Synthesis scripts and output
scripts/               — Python tools (MIDI loader, etc.)
docs/                  — Documentation
```

## Audio Engine

- Sample rate: ~48.8 kHz (50 MHz / 1024)
- Output: 12-bit mono via SPI DAC (LTC2624 channel A)
- Drum voices: kick (sine sweep), snare (sine + noise), hi-hat (noise), clap (noise bursts)
- Bass voice: saw/square oscillator → 2-pole resonant filter → amplitude envelope
- Mixer: sum all voices, saturate to 12 bits

## UI

- VGA: 640×480 text mode (80×30 chars, 8-color), shows pattern grid
- PS/2 keyboard: step editing, note entry, transport control
- LCD: tempo/status display
- LEDs: playhead position
- Rotary: tempo adjust

## Pattern Upload

- UART (115200 baud) receives binary pattern data from PC
- Python script parses MIDI files and sends patterns to the board
- Patterns stored in block RAM (lost on power-off)

## Conventions

- Top-level entity is always named `top`
- UCF format for constraints
- All source in `src/`, constraints in `constraints/`, build scripts in `build/`
- Commit and push after every meaningful change

## XST / VHDL-93 Gotchas

1. **No `-vhdl2008`** — XST doesn't recognize it
2. **No `character'val()`** — use `to_unsigned()` instead
3. **No division/modulo by non-power-of-2** — not synthesizable
4. **No conditional expressions in port maps** — use intermediate signals
5. **No hex literals in aggregates** — `(others => x"20")` is invalid
6. **`mkdir -p build/xst/tmp` required** — Makefile handles this

## Design Gotchas

1. **Rotary encoder direction** — `rot_dir <= not b_deb` gives CW=increment on this board
2. **Always debounce buttons** — 2ms bounce, always edge-detect
3. **LCD init is timing-critical** — HD44780 power-on sequence must be exact
4. **SPI bus is shared** — only DAC uses it in this project, but disable other devices (sf_ce0='1', fpga_init_b='1')
