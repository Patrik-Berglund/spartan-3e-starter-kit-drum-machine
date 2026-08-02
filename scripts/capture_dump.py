#!/usr/bin/env python3
"""
capture_dump.py - DAC sample capture tool for Spartan-3E TR-808

Captures the mixer output from the FPGA via serial and saves as WAV.

Protocol:
  - Send [0x7D, 0x01] to arm capture (waits for next voice trigger)
  - Send [0x00, 0x01] to trigger BD (or any voice trigger)
  - Send [0x7E, 0x01] to dump buffer (24576 bytes, MSB first per sample)

The buffer holds 12288 samples at 48828 Hz (~252ms).
Samples are signed 16-bit: (mix_out - 2048) << 4.

Usage:
  python3 scripts/capture_dump.py [options]

Options:
  --port PORT       Serial port (default: /dev/ttyUSB0)
  --voice VOICE     Voice to trigger: bd,sd,lt,mt,ht,rs,cp,cb,cy,oh,ch (default: bd)
  --output FILE     Output WAV file (default: scripts/output_capture/capture.wav)
  --plot            Show waveform plot
  --compare FILE    Compare with reference WAV file
  --no-trigger      Skip triggering (capture whatever plays next)
  --delay SECS      Delay after trigger before dump (default: 0.3)
"""

import argparse
import os
import struct
import sys
import time

import numpy as np

try:
    import serial
except ImportError:
    print("ERROR: pyserial not installed. Run: pip install pyserial")
    sys.exit(1)

SAMPLE_RATE = 48828
NUM_SAMPLES = 12288
NUM_BYTES = NUM_SAMPLES * 2  # 24576 bytes

# Voice trigger addresses (register map)
VOICE_ADDRS = {
    'bd': 0x00, 'sd': 0x01, 'lt': 0x02, 'mt': 0x03, 'ht': 0x04,
    'rs': 0x05, 'cp': 0x06, 'cb': 0x07, 'cy': 0x08, 'oh': 0x09, 'ch': 0x0A
}

# Capture commands
CMD_ARM  = 0x7D   # Address for arm capture
CMD_DUMP = 0x7E   # Address for dump buffer


def arm_capture(ser):
    """Send arm command to FPGA."""
    ser.write(bytes([CMD_ARM, 0x01]))
    ser.flush()
    print("  Armed capture buffer (waiting for trigger)")


def trigger_voice(ser, voice):
    """Send voice trigger to FPGA."""
    addr = VOICE_ADDRS[voice]
    ser.write(bytes([addr, 0x01]))
    ser.flush()
    print(f"  Triggered {voice.upper()} (addr 0x{addr:02X})")


def dump_buffer(ser, timeout=5.0):
    """Request buffer dump and receive all bytes."""
    # Flush any stale data
    ser.reset_input_buffer()

    # Send dump command
    ser.write(bytes([CMD_DUMP, 0x01]))
    ser.flush()
    print(f"  Requested dump ({NUM_BYTES} bytes)...")

    # Receive data
    data = bytearray()
    start_time = time.time()

    while len(data) < NUM_BYTES:
        remaining = NUM_BYTES - len(data)
        chunk = ser.read(min(remaining, 4096))
        if chunk:
            data.extend(chunk)
            elapsed = time.time() - start_time
            pct = len(data) / NUM_BYTES * 100
            print(f"\r  Receiving: {len(data)}/{NUM_BYTES} bytes ({pct:.1f}%)", end='')
        elif time.time() - start_time > timeout:
            print(f"\n  TIMEOUT after {timeout}s (got {len(data)}/{NUM_BYTES} bytes)")
            break

    print()
    return bytes(data)


def bytes_to_samples(data):
    """Convert raw bytes (MSB first per sample) to signed 16-bit numpy array."""
    if len(data) < NUM_BYTES:
        # Pad with zeros if incomplete
        data = data + b'\x00' * (NUM_BYTES - len(data))

    samples = np.zeros(NUM_SAMPLES, dtype=np.int16)
    for i in range(NUM_SAMPLES):
        hi = data[i * 2]
        lo = data[i * 2 + 1]
        val = (hi << 8) | lo
        # Convert from unsigned to signed
        if val >= 32768:
            val -= 65536
        samples[i] = val

    return samples


def save_wav(filename, samples, sample_rate=SAMPLE_RATE):
    """Save samples as 16-bit signed PCM WAV."""
    import wave
    os.makedirs(os.path.dirname(filename), exist_ok=True)
    with wave.open(filename, 'w') as wf:
        wf.setnchannels(1)
        wf.setsampwidth(2)
        wf.setframerate(sample_rate)
        wf.writeframes(samples.tobytes())
    print(f"  Saved: {filename} ({len(samples)} samples, {len(samples)/sample_rate*1000:.1f}ms)")


def plot_waveform(samples, title="Capture", compare_samples=None, compare_label="Reference"):
    """Plot waveform using matplotlib."""
    try:
        import matplotlib.pyplot as plt
    except ImportError:
        print("  WARNING: matplotlib not available, skipping plot")
        return

    t_ms = np.arange(len(samples)) / SAMPLE_RATE * 1000

    fig, axes = plt.subplots(2 if compare_samples is not None else 1, 1, figsize=(12, 6))
    if compare_samples is None:
        axes = [axes]

    axes[0].plot(t_ms, samples, linewidth=0.5)
    axes[0].set_title(f"{title} ({len(samples)} samples, {SAMPLE_RATE} Hz)")
    axes[0].set_xlabel("Time (ms)")
    axes[0].set_ylabel("Amplitude")
    axes[0].set_xlim(0, t_ms[-1])
    axes[0].grid(True, alpha=0.3)

    if compare_samples is not None:
        t_ref = np.arange(len(compare_samples)) / SAMPLE_RATE * 1000
        axes[1].plot(t_ref, compare_samples, linewidth=0.5, color='orange')
        axes[1].set_title(f"{compare_label}")
        axes[1].set_xlabel("Time (ms)")
        axes[1].set_ylabel("Amplitude")
        axes[1].set_xlim(0, max(t_ms[-1], t_ref[-1]))
        axes[1].grid(True, alpha=0.3)

    plt.tight_layout()
    plt.show()


def load_reference_wav(filename):
    """Load a WAV file as int16 samples."""
    import wave
    with wave.open(filename, 'r') as wf:
        n_frames = wf.getnframes()
        raw = wf.readframes(n_frames)
        if wf.getsampwidth() == 2:
            samples = np.frombuffer(raw, dtype=np.int16)
        else:
            # 8-bit unsigned
            samples = (np.frombuffer(raw, dtype=np.uint8).astype(np.int16) - 128) * 256
    return samples


def main():
    parser = argparse.ArgumentParser(description="DAC sample capture for Spartan-3E TR-808")
    parser.add_argument('--port', default='/dev/ttyUSB0', help='Serial port')
    parser.add_argument('--voice', default='bd', choices=VOICE_ADDRS.keys(),
                        help='Voice to trigger (default: bd)')
    parser.add_argument('--output', default='scripts/output_capture/capture.wav',
                        help='Output WAV file')
    parser.add_argument('--plot', action='store_true', help='Show waveform plot')
    parser.add_argument('--compare', help='Reference WAV file to compare against')
    parser.add_argument('--no-trigger', action='store_true',
                        help='Skip triggering (capture whatever plays next)')
    parser.add_argument('--delay', type=float, default=0.3,
                        help='Delay after trigger before dump (seconds)')
    parser.add_argument('--offset', type=int, default=0,
                        help='Sample offset: skip N samples after trigger before capturing (0-65535)')
    parser.add_argument('--baud', type=int, default=115200, help='Baud rate')
    args = parser.parse_args()

    print(f"DAC Sample Capture - Spartan-3E TR-808")
    print(f"  Port: {args.port} @ {args.baud}")
    print(f"  Buffer: {NUM_SAMPLES} samples ({NUM_SAMPLES/SAMPLE_RATE*1000:.1f}ms @ {SAMPLE_RATE} Hz)")
    print()

    # Open serial port
    try:
        ser = serial.Serial(args.port, args.baud, timeout=1)
    except serial.SerialException as e:
        print(f"ERROR: Cannot open {args.port}: {e}")
        sys.exit(1)

    time.sleep(0.1)  # Let port settle

    # Step 1: Set offset and arm capture
    print("Step 1: Arm capture")
    if args.offset > 0:
        offset_hi = (args.offset >> 8) & 0xFF
        offset_lo = args.offset & 0xFF
        ser.write(bytes([0x7B, offset_hi]))  # offset high byte
        time.sleep(0.01)
        ser.write(bytes([0x7C, offset_lo]))  # offset low byte
        time.sleep(0.01)
        skip_ms = args.offset / SAMPLE_RATE * 1000
        print(f"  Set offset: {args.offset} samples ({skip_ms:.1f}ms)")
    arm_capture(ser)
    time.sleep(0.05)

    # Step 2: Trigger voice (optional)
    if not args.no_trigger:
        print(f"Step 2: Trigger {args.voice.upper()}")
        trigger_voice(ser, args.voice)
    else:
        print("Step 2: Skipped (waiting for external trigger)")

    # Step 3: Wait for capture to complete
    total_wait = args.delay + args.offset / SAMPLE_RATE
    print(f"Step 3: Waiting {total_wait:.1f}s for capture to complete...")
    time.sleep(total_wait)

    # Step 4: Dump buffer
    print("Step 4: Dump buffer")
    raw_data = dump_buffer(ser)
    ser.close()

    if len(raw_data) < NUM_BYTES:
        print(f"  WARNING: Only received {len(raw_data)}/{NUM_BYTES} bytes")

    # Step 5: Convert and save
    print("Step 5: Convert and save")
    samples = bytes_to_samples(raw_data)
    save_wav(args.output, samples)

    # Statistics
    print(f"\n  Peak amplitude: {np.max(np.abs(samples))}")
    print(f"  RMS: {np.sqrt(np.mean(samples.astype(np.float64)**2)):.1f}")
    nonzero = np.count_nonzero(samples)
    print(f"  Non-zero samples: {nonzero}/{NUM_SAMPLES} ({nonzero/NUM_SAMPLES*100:.1f}%)")

    # Step 6: Compare (optional)
    compare_samples = None
    if args.compare:
        print(f"\nComparing with: {args.compare}")
        compare_samples = load_reference_wav(args.compare)
        # Trim/pad to same length for comparison
        min_len = min(len(samples), len(compare_samples))
        diff = samples[:min_len].astype(np.float64) - compare_samples[:min_len].astype(np.float64)
        rms_diff = np.sqrt(np.mean(diff**2))
        print(f"  RMS difference: {rms_diff:.1f}")
        print(f"  Max difference: {np.max(np.abs(diff)):.0f}")

    # Step 7: Plot (optional)
    if args.plot:
        plot_waveform(samples, title=f"Captured {args.voice.upper()}",
                      compare_samples=compare_samples,
                      compare_label=f"Reference: {args.compare}" if args.compare else None)

    print("\nDone!")


if __name__ == '__main__':
    main()
