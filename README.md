# Spartan-3E TR-808 Drum Machine

TR-808 style drum machine running on the Xilinx Spartan-3E Starter Kit (XC3S500E-FG320-4). All sound synthesis in pure VHDL — no CPU, no samples, no software.

## Features

- **11 drum voices:** BD, SD, LT, MT, HT, RS, CP, CB, CY, OH, CH — all synthesized in logic
- **16-step sequencer** with per-voice pattern editing
- **VGA display:** 640×480 pixel-based UI mimicking the TR-808 panel (colored step pads)
- **PS/2 keyboard:** full editing — number keys for step toggle, arrows for navigation
- **Rotary encoder:** tempo adjust + play/stop
- **LCD:** BPM + status display
- **Mono audio output:** 12-bit DAC at ~48.8 kHz on header J5

## Sound Synthesis

Voices are based on the TR-808 service manual circuit analysis:

| Voice | Topology | Frequency | Decay |
|-------|----------|-----------|-------|
| BD (Kick) | Sine table, pitch sweep 112→56Hz | 56 Hz | ~250ms |
| SD (Snare) | Two sines (238+476Hz) + LFSR noise | 238/476 Hz | 42/84ms |
| LT/MT/HT (Toms) | Sine table with pitch dive | 165/135/220 Hz | ~84ms |
| RS (Rimshot) | 3 parallel sines (455+680+1020Hz) | 455 Hz | ~5ms |
| CP (Clap) | Bandpass-filtered noise, 3 bursts + tail | ~1000 Hz BP | 84ms tail |
| CB (Cowbell) | 2 square waves (540+800Hz) + bandpass | 540/800 Hz | ~42ms |
| CY (Cymbal) | 6 non-harmonic square oscillators + 4-stage HPF | 205-801 Hz | ~670ms |
| OH (Open HiHat) | Same 6 oscillators + 4-stage HPF | 205-801 Hz | ~84ms |
| CH (Closed HiHat) | Same 6 oscillators + 4-stage HPF | 205-801 Hz | ~42ms |

Key DSP techniques:
- 64-entry sine lookup table for tonal voices (kick, snare, toms, rimshot)
- 6 free-running square wave oscillators for metallic voices (hihats, cymbal, cowbell)
- 4-stage cascaded high-pass filter (24dB/oct) on metallic voices
- 16-bit exponential amplitude decay (`amp -= amp >> K`)
- Mixer output low-pass filter (~6kHz) for anti-aliasing
- 12×11-bit multiply using MULT18x18 hardware blocks

## Hardware Setup

| Connection | Details |
|-----------|---------|
| Audio out | J5 header pin 1 (DAC A) → powered speaker/amp, pin 5 → GND |
| Display | VGA cable to monitor (640×480, 8 colors) |
| Keyboard | PS/2 keyboard to PS/2 port |
| Program | USB-JTAG cable |

## Controls

### PS/2 Keyboard

| Key | Function |
|-----|----------|
| Space | Play / Stop |
| 1-0 | Toggle steps 1-10 |
| Q-Y | Toggle steps 11-16 |
| ↑/↓ | Select track |
| ←/→ | Move cursor |
| +/- | Tempo up/down |
| Backspace | Clear track pattern |

### On-board Controls

| Control | Function |
|---------|----------|
| Rotary turn | Tempo adjust |
| Rotary press | Play/Stop |
| LEDs 0-3 | Playhead position |
| LED 7 | Playing indicator |
| LCD | BPM + status |

## Architecture

```
┌─────────────────────────────────────────────────────────┐
│                     top.vhd                              │
├──────────┬───────────────────┬──────────────┬───────────┤
│ Sequencer│   Drum Voices     │     UI       │   Infra   │
│          │                   │              │           │
│ tempo    │ kick (sine tbl)   │ pixel render │ SPI master│
│ clock    │ snare (sine+lfsr) │ font ROM     │ DAC driver│
│ patterns │ hihat (6-osc+HPF) │ PS/2 rx      │ rotary    │
│ playhead │ toms (sine tbl)   │ keyboard ctrl│ LCD ctrl  │
│          │ clap (BP noise)   │ VGA timing   │ debounce  │
│          │ cowbell (2-osc+BP)│              │           │
│          │ cymbal (6-osc+HPF)│              │           │
│          │ rimshot (3 sines) │              │           │
├──────────┴───────────────────┴──────────────┴───────────┤
│              Mixer (sum + LPF) → SPI DAC (48.8 kHz)      │
└─────────────────────────────────────────────────────────┘
```

## Resource Usage

| Resource | Used | Available | % |
|----------|------|-----------|---|
| Slices | ~2,400 | 4,656 | 51% |
| Flip-flops | ~1,500 | 9,312 | 16% |
| LUTs | ~3,400 | 9,312 | 36% |
| MULT18x18 | 12 | 20 | 60% |
| BRAMs | 0 | 20 | 0% |
| IOBs | 37 | 232 | 16% |

## Build

### Requirements

- Xilinx ISE 14.7 (WebPack, free license)
- xc3sprog (JTAG programmer)
- Linux / WSL
- Python 3 + numpy + scipy (for simulation scripts)

### Compile & Program

```bash
source /opt/Xilinx/14.7/ISE_DS/settings64.sh
make

# Step 1: Load programmer firmware (required after every power cycle)
sudo fxload -v -t fx2 -I /opt/Xilinx/14.7/ISE_DS/common/bin/lin/xusb_xlp.hex -D /dev/bus/usb/001/002

# Step 2: (WSL only) Reattach USB after re-enumeration
# From Windows PowerShell: usbipd attach --wsl --busid <busid>

# Step 3: Program
sudo xc3sprog -v -c xpc -p 0 build/top.bit
```

## Simulation Scripts

Two Python scripts for development and debugging:

```bash
python3 scripts/sim_vhdl.py    # Bit-exact FPGA simulation → scripts/output_vhdl/
python3 scripts/sim_ideal.py   # Ideal float reference → scripts/output_ideal/
```

Both generate individual voice WAVs (01-09) and a demo pattern (10_demo_pattern.wav). Compare them to identify where the FPGA implementation differs from the ideal target.

## Project Structure

```
src/
  top.vhd                  — Top-level entity (wiring only)
  mixer.vhd                — Voice summation + output LPF
  infrastructure/          — Debounce, rotary, SPI master, DAC driver, LCD
  drums/                   — All 11 drum voice modules
  sequencer/               — Step sequencer + tempo clock
  ui/                      — Pixel renderer, font ROM, VGA timing, PS/2, keyboard
constraints/
  top.ucf                  — Pin assignments
build/
  top.xst, top.prj         — Synthesis scripts
scripts/
  sim_vhdl.py              — Bit-exact VHDL simulator (integer arithmetic)
  sim_ideal.py             — Ideal reference (float, scipy filters)
docs/
  808-synthesis-reference.md — Voice synthesis parameters
  reference-wavs/          — Generated reference audio files
```

## Status

🔊 **Working** — plays a demo pattern on startup with all 11 voices. Sound quality is functional but still being refined toward authentic 808 character. See TODO.md for planned improvements.
