#!/usr/bin/env python3
"""Sweep noise_mult / hp_stages / bpf_hp_shift for render_metallic_core
directly in the bit-exact integer simulator, to retune against the real
TR-808 reference now that we know the float-domain prototype's filter
constants don't transfer 1:1 to the fixed-point implementation."""
import sys, os
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import numpy as np, wave
from sim_vhdl import render_metallic_core, SR
from prototype_metallic import spectral_centroid, spectral_flatness, quantization_step_metric


def load(p):
    with wave.open(p, 'r') as w:
        sr = w.getframerate()
        d = np.frombuffer(w.readframes(w.getnframes()), dtype=np.int16).astype(float)
    return d / max(np.abs(d).max(), 1), sr


ref, sr2 = load(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "docs", "TR808WAV", "CH", "CH.WAV"))
print(f"Reference: centroid={spectral_centroid(ref, sr2):.1f} flatness={spectral_flatness(ref):.4f}\n")

n = SR // 2
configs = [
    ("orig_4stage_noNoise", dict(decay_k=9, bpf_lp_shift=1, bpf_hp_shift=3, noise_mult=0, hp_stages=4)),
    ("1stage_shift3_noise2", dict(decay_k=9, bpf_lp_shift=1, bpf_hp_shift=3, noise_mult=2, hp_stages=1)),
    ("1stage_shift3_noise4", dict(decay_k=9, bpf_lp_shift=1, bpf_hp_shift=3, noise_mult=4, hp_stages=1)),
    ("2stage_shift3_noise3", dict(decay_k=9, bpf_lp_shift=1, bpf_hp_shift=3, noise_mult=3, hp_stages=2)),
    ("2stage_shift3_noise5", dict(decay_k=9, bpf_lp_shift=1, bpf_hp_shift=3, noise_mult=5, hp_stages=2)),
    ("3stage_shift3_noise3", dict(decay_k=9, bpf_lp_shift=1, bpf_hp_shift=3, noise_mult=3, hp_stages=3)),
    ("4stage_shift3_noise3", dict(decay_k=9, bpf_lp_shift=1, bpf_hp_shift=3, noise_mult=3, hp_stages=4)),
    ("4stage_shift3_noise6", dict(decay_k=9, bpf_lp_shift=1, bpf_hp_shift=3, noise_mult=6, hp_stages=4)),
    ("4stage_shift3_noise10", dict(decay_k=9, bpf_lp_shift=1, bpf_hp_shift=3, noise_mult=10, hp_stages=4)),
    ("4stage_shift3_noise16", dict(decay_k=9, bpf_lp_shift=1, bpf_hp_shift=3, noise_mult=16, hp_stages=4)),
    ("4stage_shift3_noise24", dict(decay_k=9, bpf_lp_shift=1, bpf_hp_shift=3, noise_mult=24, hp_stages=4)),
    ("4stage_shift2_noise10", dict(decay_k=9, bpf_lp_shift=1, bpf_hp_shift=2, noise_mult=10, hp_stages=4)),
    ("4stage_shift2_noise16", dict(decay_k=9, bpf_lp_shift=1, bpf_hp_shift=2, noise_mult=16, hp_stages=4)),
    ("lpshift0_4stage_shift3_noise10", dict(decay_k=9, bpf_lp_shift=0, bpf_hp_shift=3, noise_mult=10, hp_stages=4)),
    ("lpshift0_4stage_shift3_noise6", dict(decay_k=9, bpf_lp_shift=0, bpf_hp_shift=3, noise_mult=6, hp_stages=4)),
    ("lpshift0_4stage_shift3_noise14", dict(decay_k=9, bpf_lp_shift=0, bpf_hp_shift=3, noise_mult=14, hp_stages=4)),
    ("lpshift0_4stage_shift2_noise10", dict(decay_k=9, bpf_lp_shift=0, bpf_hp_shift=2, noise_mult=10, hp_stages=4)),
    ("lpshift0_3stage_shift3_noise10", dict(decay_k=9, bpf_lp_shift=0, bpf_hp_shift=3, noise_mult=10, hp_stages=3)),
]

print(f"{'config':<24} {'centroid(Hz)':>14} {'flatness':>10} {'steppiness':>12}")
for name, kw in configs:
    out = render_metallic_core(n, lfsr_seed=0xF00D, **kw)
    sig = np.array(out, dtype=np.float64)
    sig = sig / max(np.abs(sig).max(), 1)
    c = spectral_centroid(sig, SR)
    f = spectral_flatness(sig)
    s = quantization_step_metric(sig)
    print(f"{name:<24} {c:>14.1f} {f:>10.4f} {s:>12.5f}")
