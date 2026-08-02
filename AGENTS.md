# AGENTS.md

## Project

TR-808 drum machine on the Xilinx Spartan-3E Starter Kit.
Mono audio output via SPI DAC (LTC2624 channel A on header J5).
All voices parameterized via register map, accessible from serial (UART).

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

## Program (IMPORTANT: 2-step process)

The Spartan-3E starter kit has an onboard Cypress FX2 USB chip that needs firmware
loaded before it works as a JTAG programmer. This must be done every time the board
is power-cycled or the USB is reconnected.

### Step 1: Load programmer firmware

```bash
sudo fxload -v -t fx2 -I /opt/Xilinx/14.7/ISE_DS/common/bin/lin/xusb_xlp.hex -D /dev/bus/usb/001/002
```

Note: The device path (`/dev/bus/usb/001/002`) may vary. Find it with:
```bash
lsusb | grep "03fd:000d"  # Before firmware load (Xilinx, Inc.)
```

After firmware loads, the device re-enumerates as `03fd:0008` (Platform Cable USB II).

### Step 2: Reattach USB in WSL (if using WSL)

The device re-enumerates after firmware load. In WSL, you must reattach it:
```
# From Windows PowerShell (admin):
usbipd attach --wsl --busid <busid>
```

Verify it's visible:
```bash
lsusb | grep "03fd:0008"  # Should show Platform Cable USB II
```

### Step 3: Program the FPGA

```bash
sudo xc3sprog -v -c xpc -p 0 build/top.bit
```

Expected output: `Programming time ~1300 ms`, `done.`

## Architecture

```
src/
  top.vhd                  — Top-level wiring
  infrastructure/
    register_map.vhd       — 128x8-bit dual-port RAM (voice params, triggers, BPM)
    sine_table.vhd         — 256-entry 12-bit + linear interpolation (1 MULT18x18)
    sample_capture.vhd     — 12288-sample capture buffer (12 BRAMs, see DAC Capture section)
    uart_tx.vhd            — 115200 8N1 transmitter (for capture dump)
    debounce.vhd, rotary_decoder.vhd, spi_master.vhd, dac_driver.vhd, lcd_controller.vhd
  drums/                   — All 11 drum voice modules (parameterized)
  sequencer/               — Step sequencer + tempo clock
  ui/                      — Pixel renderer, font ROM, VGA timing, PS/2, keyboard
  serial/
    uart_rx.vhd            — 115200 8N1 UART receiver, writes to register map
constraints/
  top.ucf                  — Pin assignments (serial_rx on R7, serial_tx on M14)
build/
  top.xst, top.prj         — Synthesis scripts
scripts/
  sim_ideal.py             — Float reference simulator (all voices parameterized)
  sim_vhdl.py              — Bit-exact integer simulator (matches FPGA)
  compare_voice.py         — Automated voice comparison tool
```

## Register Map

All voice parameters accessible via UART serial (115200 8N1, RX=pin R7, TX=pin M14).
Protocol: 2 bytes — [address] [data].

| Address | Voice | Parameter | Range |
|---------|-------|-----------|-------|
| 0x00-0x0A | All | Trigger (write 1) | pulse |
| 0x10-0x1A | All | Level | 0-255 |
| 0x20 | BD | Tone | 0-255 |
| 0x21 | SD | Tone | 0-255 |
| 0x22 | LT | Tuning | 0-255 |
| 0x23 | MT | Tuning | 0-255 |
| 0x24 | HT | Tuning | 0-255 |
| 0x28 | CY | Tone | 0-255 |
| 0x30 | BD | Decay | 0-255 |
| 0x31 | SD | Snappy | 0-255 |
| 0x38 | CY | Decay | 0-255 |
| 0x39 | OH | Decay | 0-255 |
| 0x40 | — | BPM | 40-240 |
| 0x41 | — | Play/Stop toggle | write 1 |
| 0x7B | — | Capture offset high byte | 0-255 |
| 0x7C | — | Capture offset low byte | 0-255 |
| 0x7D | — | Arm capture (write 1) | pulse |
| 0x7E | — | Dump capture buffer (write 1) | pulse |

Voice indices: 0=BD, 1=SD, 2=LT, 3=MT, 4=HT, 5=RS, 6=CP, 7=CB, 8=CY, 9=OH, 10=CH

## Audio Engine

- Sample rate: ~48.8 kHz (50 MHz / 1024)
- Output: 12-bit mono via SPI DAC (LTC2624 channel A)
- Signal path: 256-entry sine table + interpolation → MULT18x18 → 18-bit internal → 12-bit DAC
- No LPF on sine-based voices (kick, toms, snare tones, rimshot)
- 6 square oscillators for metallic voices (hihats, cymbal):
  - CH/OH: 2-pole resonant state-variable bandpass filter (Chamberlin SVF,
    same topology as the cowbell) — see `src/drums/hihat.vhd` /
    `open_hihat.vhd`. A cascade of real single-pole HP/LP stages (the
    original design) can only produce a monotonic rolloff and can never
    reproduce the real 808's *concentrated* spectral band (CH: 65% of
    energy in 8-16kHz, 7.7% in 16-24kHz) — confirmed by sweeping dozens of
    stage/shift combinations against the real reference WAVs. Only a
    resonant (peaked) filter can do this.
  - CY still uses the older N-stage HP-cascade + LP-rolloff design
    (`render_metallic_core` in `scripts/sim_vhdl.py`) — not yet ported to
    the resonant-filter approach.

## Resource Usage

| Resource | Used | Available | % |
|----------|------|-----------|---|
| Slices | 3,036 | 4,656 | 65% |
| MULT18x18 | 19 | 20 | 95% |
| BRAM | 14 | 20 | 70% |
| Flip-flops | 2,068 | 9,312 | 22% |
| LUTs | 5,676 | 9,312 | 60% |

(Slices/FFs/LUTs dropped from the previous 71%/23%/67% after CH/OH moved
from a 5-9 stage HP/LP cascade to a 2-pole resonant filter — fewer
registers and adders needed per voice.)

**MULT18x18 is nearly exhausted (95%).** Adding any new multiply (e.g. a
gain compensation stage) will likely need to be converted to shift-and-add
instead of a `*` operator — see Design Gotchas below. Above ~19/20, XST's
placer can hit a fatal internal error (`Pl_Uap_Flow1FitterRuleFastFeedbacks:
bad index to sec_nodes array`) on certain netlist patterns; freeing a
multiplier resolved it once already (see CH/OH/CY filter rework).

## UI

- VGA: 640×480 pixel-based UI (colored step pads)
- PS/2 keyboard: step editing, transport control
- LCD: BPM + status display
- LEDs: playhead position (0-3), playing indicator (7)
- Rotary: tempo adjust + play/stop

## Python Tools

```bash
python3 scripts/sim_ideal.py    # Float reference → scripts/output_ideal/
python3 scripts/sim_vhdl.py     # Bit-exact FPGA sim → scripts/output_vhdl/
python3 scripts/compare_voice.py docs/TR808WAV/BD scripts/output_compare/BD  # Compare vs 808
```

## Serial Control from Python

```python
import serial
ser = serial.Serial('/dev/ttyUSB0', 115200)
ser.write(bytes([0x20, 200]))  # BD TONE = 200
ser.write(bytes([0x30, 100]))  # BD DECAY = 100
ser.write(bytes([0x00, 1]))    # Trigger BD
```

## DAC Sample Capture (Hardware Debugging)

Captures the mixer output (12-bit DAC samples) into a 12288-sample BRAM buffer
(~252ms at 48828Hz), then dumps over UART TX for comparison with the sim.

### Usage

```bash
# Basic capture (first 252ms after trigger)
python3 scripts/capture_dump.py --voice bd --output scripts/output_capture/bd.wav

# With offset (capture 252-504ms after trigger)
python3 scripts/capture_dump.py --voice bd --offset 12288 --output scripts/output_capture/bd_chunk2.wav

# Compare with sim output
python3 scripts/capture_dump.py --voice bd --compare scripts/output_vhdl/01_kick.wav
```

### Protocol

1. Set offset (optional): `[0x7B, hi_byte]` then `[0x7C, lo_byte]` (16-bit sample count to skip)
2. Arm capture: `[0x7D, 0x01]` — buffer waits for any voice trigger
3. Trigger a voice: `[0x00, 0x01]` — starts capture after offset samples
4. Wait for buffer to fill: offset/48828 + 0.252 seconds
5. Request dump: `[0x7E, 0x01]` — FPGA sends 24576 bytes (12288 × 16-bit, MSB first)
6. At 115200 baud, dump takes ~2.1 seconds

### Stitching for longer captures

For recordings longer than 252ms, capture multiple chunks with increasing offsets:
- Chunk 1: offset=0 (0-252ms)
- Chunk 2: offset=12288 (252-504ms)
- Chunk 3: offset=24576 (504-756ms)

Each chunk requires a separate trigger, so the sound must be deterministic.

### Storage format

Samples are signed 16-bit: `(mix_out - 2048) << 4` where mix_out is the 12-bit unsigned DAC value.
Transmitted MSB first per sample. Sample rate is 48828Hz (50MHz / 1024).

## Development Workflow (IMPORTANT)

The goal is to match the real TR-808 sound as closely as possible.
Reference materials are in `docs/`:
- `docs/808-synthesis-reference.md` — target parameters per voice
- `docs/TR808WAV/` — real TR-808 samples for A/B comparison
- `docs/reference-images/` — service manual schematics
  - `voices1.PNG` — BD, SD, LT/MT/HT, RS/CL, CP/MA block diagrams
  - `voices2.PNG` — CB, CY, OH, CH block diagrams
- `docs/reference-text/` — service manual analysis, Gemini voice descriptions

### Sim-first workflow

**Always fix voices in the Python VHDL sim first, then port to VHDL.**

1. Edit `scripts/sim_vhdl.py` — this is the bit-exact integer model of the FPGA
2. Run `python3 scripts/sim_vhdl.py` to generate WAVs in `scripts/output_vhdl/`
3. Compare output against real 808 samples (`docs/TR808WAV/`)
4. Once the sim sounds correct, port the fix to the VHDL source in `src/drums/`
5. Build (`make`), program (`xc3sprog`), verify on hardware via serial triggers

The sim must always match the VHDL 1:1. If you change VHDL, update the sim.
If you change the sim, port to VHDL.

### Serial testing on hardware

```python
import serial
ser = serial.Serial('/dev/ttyUSB0', 115200)
ser.write(bytes([0x00, 1]))  # Trigger BD
```

No `sudo` needed for fxload or xc3sprog on this setup.

### Common issues found across voices

- Phase accumulator values too small for exponential sweeps to work with bit shifts
- Overflow/wrap bugs invisible in Python (unlimited int) but real on FPGA (fixed width)
- The `sN()`/`uN()` helpers in sim_vhdl.py exist to catch these — use them

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
7. **Signal (`<=`) vs variable (`:=`) timing in cascaded filter stages** —
   a signal assigned with `<=` does NOT update until after the clock edge;
   reading that signal later in the SAME process invocation gives the OLD
   value. In a multi-stage IIR filter cascade (`acc <= acc + delta; x :=
   input - acc`), this silently breaks the filter — `x` gets the pre-update
   accumulator instead of the intended post-update value. Fix: compute the
   new value into a variable first (`new_acc := acc + delta; x := input -
   new_acc; acc <= new_acc;`). Caused a severe bug in the CH/OH/CY hihat
   filters (hardware output clipped/garbage, -0.13 correlation to sim)
   that passed synthesis and P&R with zero errors/warnings — this class of
   bug is invisible to the toolchain and only shows up as wrong audio.
8. **Constant multiplies eat MULT18X18 blocks** — `signal * to_signed(70,
   8)` infers a dedicated multiplier even for compile-time constants.
   When near the 20-multiplier budget, convert to shift-and-add (`70 =
   64+4+2` → three `shift_left` + `+`) to avoid tipping into placer
   failures (see Design Gotchas #6).

## Design Gotchas

1. **Rotary encoder direction** — `rot_dir <= not b_deb` gives CW=increment on this board
2. **Always debounce buttons** — 2ms bounce, always edge-detect
3. **LCD init is timing-critical** — HD44780 power-on sequence must be exact
4. **SPI bus is shared** — only DAC uses it in this project, but disable other devices (sf_ce0='1', fpga_init_b='1')
5. **Programmer needs firmware** — fxload MUST be run before xc3sprog (see Program section)
6. **MULT18x18 near-exhaustion causes fatal placer errors** — above ~19/20
   multipliers used, XST's placer can hit `Pl_Uap_Flow1FitterRuleFastFeedbacks:
   bad index to sec_nodes array` on certain netlist patterns, even though
   synthesis reports 0 errors. The fix is to free a multiplier (e.g.
   convert a constant multiply to shift-and-add), not to debug the netlist
   pattern itself — the error is in the ISE 14.7 placer, not the design.
7. **Resonant filter state must be reset on every trigger, not just on
   global `rst`** — CH/OH's 2-pole resonant SVF (`bp_reg`/`lp_reg` in
   `hihat.vhd`/`open_hihat.vhd`) carried its state forward between hits by
   only clearing on `rst`. On real hardware, after enough retriggers the
   leftover state could occasionally kick the filter into a self-sustaining
   near-full-scale oscillation — audibly a clean ringing "ice pick on a
   metal anvil" tone (hard clipping at a single high frequency) instead of
   the intended broadband shimmer. Reproduced with ~2-3 back-to-back
   triggers on hardware; NOT visible in single-hit sim testing, since each
   sim render call already starts from a fresh zero state (only multi-
   trigger sequences on real hardware exposed it). Fix: reset `bp_reg`/
   `lp_reg` to 0 in the same `if trigger = '1'` block that resets `amp`.
   Any future resonant/feedback filter design in this project should reset
   its state on every trigger for the same reason — a damped, non-resonant
   cascade (the old CH/OH/CY design) doesn't have this failure mode since
   it always decays toward zero on its own, but a resonant filter (bp/lp
   feeding back into itself) can retain energy indefinitely.
8. **Known issue: CY (cymbal) doesn't meet 50MHz timing** — pre-existing,
   confirmed present before the CH/OH resonant-filter rework (150 failing
   paths / -12.7ns worst slack in `build/top_timing.twr` from before that
   change; grew to ~190-200 failing paths / -17.6ns after, apparently from
   added routing congestion elsewhere on the chip, though none of the
   failing paths are in CH/OH). All failing paths are inside `u_cy`. Not
   yet root-caused or fixed - worth a dedicated look.
