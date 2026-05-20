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
    debounce.vhd, rotary_decoder.vhd, spi_master.vhd, dac_driver.vhd, lcd_controller.vhd
  drums/                   — All 11 drum voice modules (parameterized)
  sequencer/               — Step sequencer + tempo clock
  ui/                      — Pixel renderer, font ROM, VGA timing, PS/2, keyboard
  serial/
    uart_rx.vhd            — 115200 8N1 UART receiver, writes to register map
constraints/
  top.ucf                  — Pin assignments (includes serial_rx on R7)
build/
  top.xst, top.prj         — Synthesis scripts
scripts/
  sim_ideal.py             — Float reference simulator (all voices parameterized)
  sim_vhdl.py              — Bit-exact integer simulator (matches FPGA)
  compare_voice.py         — Automated voice comparison tool
```

## Register Map

All voice parameters accessible via UART serial (115200 8N1, pin R7).
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

Voice indices: 0=BD, 1=SD, 2=LT, 3=MT, 4=HT, 5=RS, 6=CP, 7=CB, 8=CY, 9=OH, 10=CH

## Audio Engine

- Sample rate: ~48.8 kHz (50 MHz / 1024)
- Output: 12-bit mono via SPI DAC (LTC2624 channel A)
- Signal path: 256-entry sine table + interpolation → MULT18x18 → 18-bit internal → 12-bit DAC
- No LPF on sine-based voices (kick, toms, snare tones, rimshot)
- 6 square oscillators + 4-stage HPF for metallic voices (hihats, cymbal)

## Resource Usage

| Resource | Used | Available | % |
|----------|------|-----------|---|
| Slices | 2,601 | 4,656 | 55% |
| MULT18x18 | 16 | 20 | 80% |
| BRAM | 1 | 20 | 5% |
| Flip-flops | 1,871 | 9,312 | 20% |
| LUTs | 4,857 | 9,312 | 52% |

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
5. **Programmer needs firmware** — fxload MUST be run before xc3sprog (see Program section)
