#!/usr/bin/env python3
"""Diagnose background noise in gen_12_vhdl_improved.py drum machine."""
import math
from gen_12_vhdl_improved import (
    SR, gen_kick, gen_snare, gen_hihat, gen_clap, hpf_4stage_v2, LFSR16
)

BPM = 120
STEP_SAMPLES = int(SR * 60 / BPM / 4)
TOTAL = SR  # 1 second = 16 steps

# Voice durations
KICK_DUR = int(0.3 * SR)
SNARE_DUR = int(0.2 * SR)
CH_DUR = int(0.08 * SR)
OH_DUR = int(0.5 * SR)
CLAP_DUR = int(0.25 * SR)

# Pattern (first 16 steps only, 1 second)
PATTERN = {
    'kick':  [0, 8],
    'snare': [4, 12],
    'ch':    [0, 2, 4, 6, 8, 10, 12, 14],
    'oh':    [8],
    'clap':  [10],
}

# Pre-render voices
voices = {
    'kick':  gen_kick(KICK_DUR),
    'snare': gen_snare(SNARE_DUR),
    'ch':    gen_hihat(CH_DUR, 11),
    'oh':    gen_hihat(OH_DUR, 14),
    'clap':  gen_clap(CLAP_DUR),
}
GAIN_SHIFT = {'kick': 0, 'snare': 1, 'ch': 2, 'oh': 2, 'clap': 1}

# Build per-voice contribution buffers
voice_buffers = {name: [0] * TOTAL for name in voices}
for name, steps in PATTERN.items():
    voice = voices[name]
    shift = GAIN_SHIFT[name]
    for step in steps:
        start = step * STEP_SAMPLES
        for j in range(len(voice)):
            pos = start + j
            if pos < TOTAL:
                voice_buffers[name][pos] += voice[j] >> shift

# Find "should be silent" periods: where ALL voices have amplitude = 0
# A voice is active at sample i if any trigger's rendered samples cover that position
active_mask = [set() for _ in range(TOTAL)]
for name, steps in PATTERN.items():
    dur = len(voices[name])
    for step in steps:
        start = step * STEP_SAMPLES
        for j in range(dur):
            pos = start + j
            if pos < TOTAL:
                active_mask[pos].add(name)

# Mix buffer
mix = [0] * TOTAL
for name in voices:
    for i in range(TOTAL):
        mix[i] += voice_buffers[name][i]

# --- Analysis ---
print("=" * 60)
print("NOISE DIAGNOSTIC REPORT")
print("=" * 60)

# 1. Check each voice's tail: after its envelope should be ~0
print("\n--- Per-voice tail analysis (last 10% of rendered duration) ---")
for name, v in voices.items():
    n = len(v)
    tail_start = int(n * 0.9)
    tail = v[tail_start:]
    rms = math.sqrt(sum(s*s for s in tail) / len(tail)) if tail else 0
    peak = max(abs(s) for s in tail) if tail else 0
    print(f"  {name:6s}: tail RMS={rms:.2f}, peak={peak}, duration={n} samples ({n/SR*1000:.1f}ms)")

# 2. Find truly silent periods (no voice active)
silent_samples = [i for i in range(TOTAL) if len(active_mask[i]) == 0]
print(f"\n--- Silent period analysis ---")
print(f"  Samples with NO voice active: {len(silent_samples)} / {TOTAL} ({100*len(silent_samples)/TOTAL:.1f}%)")

if silent_samples:
    silent_mix = [mix[i] for i in silent_samples]
    rms_silent = math.sqrt(sum(s*s for s in silent_mix) / len(silent_mix))
    peak_silent = max(abs(s) for s in silent_mix)
    print(f"  Mix during silent periods: RMS={rms_silent:.2f}, peak={peak_silent}")
else:
    print("  (No fully silent periods in first second — voices overlap everywhere)")

# 3. Per-voice RMS during periods where ONLY that voice's envelope has expired
# Check: which voices produce non-zero output even when their envelope should be dead?
print("\n--- Per-voice contribution during 'should be silent' periods ---")
print("  (Periods where that voice has no active trigger)")
for name in voices:
    inactive_samples = [i for i in range(TOTAL) if name not in active_mask[i]]
    if inactive_samples:
        vals = [voice_buffers[name][i] for i in inactive_samples]
        rms = math.sqrt(sum(s*s for s in vals) / len(vals))
        peak = max(abs(s) for s in vals)
        nonzero = sum(1 for s in vals if s != 0)
        print(f"  {name:6s}: RMS={rms:.4f}, peak={peak}, nonzero={nonzero}/{len(inactive_samples)}")
    else:
        print(f"  {name:6s}: always active (triggers cover entire buffer)")

# 4. Specifically check hihat HPF leakage
print("\n--- Hi-hat HPF accumulator leakage test ---")
print("  Generating hi-hat with amp forced to 0 after 50% of duration...")
lfsr_test = LFSR16(0xCAFE)
n_test = CH_DUR
raw_test = [0] * n_test
amp_test = 65535
for i in range(n_test):
    noise_val = lfsr_test.next()
    if i < n_test // 2:
        sample = (noise_val * (amp_test >> 4)) >> 12
        amp_test -= amp_test >> 11
    else:
        sample = 0  # Force zero input to HPF
    raw_test[i] = sample
hp_test = hpf_4stage_v2(raw_test, shift=3)
tail_hp = hp_test[n_test//2:]
rms_hp = math.sqrt(sum(s*s for s in tail_hp) / len(tail_hp))
peak_hp = max(abs(s) for s in tail_hp)
print(f"  HPF output after input goes to 0: RMS={rms_hp:.2f}, peak={peak_hp}")
print(f"  (Non-zero = HPF accumulators are ringing/leaking)")

# 5. Check LFSR-based voices: do they produce output when amp=0?
print("\n--- LFSR amplitude floor check ---")
print("  When amp decays below 512, it's forced to 0.")
print("  Checking if (noise_val * (amp>>4)) >> 12 can be non-zero for amp < 512...")
# amp=511: amp>>4 = 31. noise_val max = 2047. (2047*31)>>12 = 63471>>12 = 15
# amp=256: amp>>4 = 16. (2047*16)>>12 = 32752>>12 = 7
# amp=0: always 0
for amp_val in [512, 256, 128, 64, 0]:
    max_out = (2047 * (amp_val >> 4)) >> 12
    print(f"  amp={amp_val}: max possible output = {max_out}")

# 6. The real issue: check if voices have long tails that overlap "silent" periods
print("\n--- Voice tail duration (samples until output < 1) ---")
for name, v in voices.items():
    last_nonzero = 0
    for i in range(len(v)-1, -1, -1):
        if abs(v[i]) >= 1:
            last_nonzero = i
            break
    print(f"  {name:6s}: last |sample| >= 1 at index {last_nonzero} ({last_nonzero/SR*1000:.1f}ms), "
          f"duration={len(v)} ({len(v)/SR*1000:.1f}ms)")

# 7. The HPF is the likely culprit - it rings after input dies
print("\n--- HPF ringing analysis (hi-hat closed) ---")
ch_raw_pre_hpf = [0] * CH_DUR
lfsr_ch = LFSR16(0xCAFE)
amp_ch = 65535
for i in range(CH_DUR):
    noise_val = lfsr_ch.next()
    sample = (noise_val * (amp_ch >> 4)) >> 12
    ch_raw_pre_hpf[i] = sample
    amp_ch -= amp_ch >> 11
    if amp_ch < 512:
        amp_ch = 0

# Find where raw input becomes 0
first_zero = next((i for i in range(CH_DUR) if ch_raw_pre_hpf[i] == 0 and amp_ch == 0), CH_DUR)
# Actually find where amp hits 0
lfsr_ch2 = LFSR16(0xCAFE)
amp_ch2 = 65535
amp_zero_at = CH_DUR
for i in range(CH_DUR):
    lfsr_ch2.next()
    amp_ch2 -= amp_ch2 >> 11
    if amp_ch2 < 512:
        amp_zero_at = i
        break
print(f"  CH amplitude hits 0 at sample {amp_zero_at} ({amp_zero_at/SR*1000:.1f}ms)")
ch_hpf = hpf_4stage_v2(ch_raw_pre_hpf, shift=3)
tail_after_amp0 = ch_hpf[amp_zero_at:]
if tail_after_amp0:
    rms_tail = math.sqrt(sum(s*s for s in tail_after_amp0) / len(tail_after_amp0))
    peak_tail = max(abs(s) for s in tail_after_amp0)
    print(f"  HPF output AFTER amp=0: RMS={rms_tail:.2f}, peak={peak_tail}, samples={len(tail_after_amp0)}")

print("\n--- Actual noise floor: check mix during gaps between hits ---")
# Steps 1,3,5,7,9,11,13,15 have no kick/snare/clap. Check if ch/oh tails dominate.
# Let's look at a specific gap: step 1 (samples 6103-12206) - only ch at step 0 and 2
# Step 1 starts at 6103, ch at step 0 ends at 6103+3906=10009, ch at step 2 starts at 12206
# So samples 10009-12206 should be "quiet" (only kick tail from step 0)
gap_start = STEP_SAMPLES + CH_DUR  # after step 0's ch dies
gap_end = 2 * STEP_SAMPLES  # before step 2's ch starts
print(f"  Checking gap: samples {gap_start}-{gap_end} (between ch hits)")
for name in voices:
    vals = [voice_buffers[name][i] for i in range(gap_start, min(gap_end, TOTAL))]
    rms = math.sqrt(sum(s*s for s in vals) / len(vals)) if vals else 0
    peak = max(abs(s) for s in vals) if vals else 0
    print(f"    {name:6s}: RMS={rms:.2f}, peak={peak}")

# The REAL issue: voices render to their full duration and NEVER reach zero
# because the exponential decay with integer truncation has a long tail
print("\n--- Decay analysis: when does each voice actually reach 0? ---")
for name, v in voices.items():
    # Find first sample where all remaining samples are 0
    last_nz = 0
    for i in range(len(v)-1, -1, -1):
        if v[i] != 0:
            last_nz = i
            break
    # Find where |sample| drops below various thresholds
    for thresh in [100, 50, 10, 1]:
        idx = next((i for i in range(len(v)) if all(abs(v[j]) <= thresh for j in range(i, min(i+100, len(v))))), len(v))
        print(f"  {name:6s}: sustained |val| < {thresh:3d} from sample {idx} ({idx/SR*1000:.1f}ms)")

# Check: is the "noise" actually the kick's long sine tail?
print("\n--- Kick tail detail (last 5000 samples) ---")
kick_v = voices['kick']
for offset in [len(kick_v)-5000, len(kick_v)-2000, len(kick_v)-500, len(kick_v)-100]:
    chunk = kick_v[offset:offset+100]
    rms = math.sqrt(sum(s*s for s in chunk)/len(chunk))
    print(f"  samples {offset}-{offset+100}: RMS={rms:.1f}, range=[{min(chunk)}, {max(chunk)}]")

print("\n--- Open hi-hat tail detail (last 5000 samples) ---")
oh_v = voices['oh']
for offset in [len(oh_v)-5000, len(oh_v)-2000, len(oh_v)-500, len(oh_v)-100]:
    chunk = oh_v[offset:offset+100]
    rms = math.sqrt(sum(s*s for s in chunk)/len(chunk))
    print(f"  samples {offset}-{offset+100}: RMS={rms:.1f}, range=[{min(chunk)}, {max(chunk)}]")

print("\n" + "=" * 60)
print("CONCLUSION")
print("=" * 60)
print("""
ROOT CAUSE: The open hi-hat (OH) never decays to silence.

With K=14 (tau=16384 samples = 336ms), the OH's amplitude envelope decays so
slowly that it NEVER reaches the amp<512 cutoff within its 500ms buffer.
The OH has RMS=285-370 even in its final samples — essentially constant noise.

The amplitude decay formula: amp -= amp >> 14
Starting at 65535, after 500ms (24414 samples): amp is still ~14000+
The amp<512 threshold is never reached, so the LFSR noise keeps producing
output at significant levels through the entire 500ms duration.

After HPF filtering, this becomes broadband noise (the "white noise" character).

SECONDARY: The kick also never fully decays (RMS=93 at 300ms) because K=12
gives tau=4096 samples (84ms), and 300ms ≈ 3.6 tau — only ~3% of original
amplitude, but that's still audible on a sine wave.

PRIMARY CULPRIT: Open hi-hat (gen_hihat with amp_k=14)
  - Decay too slow: never reaches silence in 500ms
  - HPF-filtered LFSR noise = constant white noise floor
  - RMS ~314 at end of buffer (vs full-scale 2047)

FIX OPTIONS:
  1. Lower OH's amp_k from 14 to 12 (faster decay, tau=84ms)
  2. Increase OH duration to ~2 seconds (let it decay naturally)
  3. Add hard gate: if amp < threshold, force output to 0 BEFORE HPF
  4. Apply envelope AFTER HPF (multiply HPF output by amp, not input)
""")
