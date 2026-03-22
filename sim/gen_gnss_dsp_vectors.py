#!/usr/bin/env python3
"""Generate GNSS-DSP validation vectors and evidence artifacts.

This script emits deterministic vector files consumed by VHDL TBs and
machine-readable reports under ``sim/reports``.
"""

from __future__ import annotations

import argparse
import json
import math
import subprocess
import sys
from dataclasses import dataclass
from datetime import datetime, timezone
from pathlib import Path
from typing import Iterable, List, Sequence, Tuple

import numpy as np

ROOT = Path(__file__).resolve().parents[1]
GNSS_TOOLS_DIR = ROOT / "GNSS-DSP-tools"
if str(GNSS_TOOLS_DIR) not in sys.path:
    sys.path.insert(0, str(GNSS_TOOLS_DIR))
if str(ROOT / "sim") not in sys.path:
    sys.path.insert(0, str(ROOT / "sim"))

import gnsstools.discriminator as discriminator  # noqa: E402
import gnsstools.gps.ca as ca  # noqa: E402

try:
    import validate_acq_fullspace_prn1 as acq_ref  # noqa: E402
except Exception:  # pragma: no cover - optional dependency path
    acq_ref = None

C_SAMPLES_PER_MS = 2000
C_NFFT = 2048
C_FFT_BITS = 11
C_CODE_NCO_FCW = 0x82EF9DB2
C_CARR_FCW_PER_HZ = 2147

C_PHASE_ERR_MAX_Q15 = 24576
C_CODE_LOOP_KP_PER_HZ_Q8 = 32768
C_CODE_LOOP_KI_DIV = 128
C_PLL_LOOP_KI_DIV = 256
C_FLL_LOOP_STEP_SCALE = 4
C_PULLIN_PLL_ASSIST_DIV = 4
C_PLL_GAIN_MIN_Q8_8 = 64
C_DLL_GAIN_MIN_Q8_8 = 16
C_FLL_GAIN_MIN_Q8_8 = 64
C_CODE_FCW_DELTA_MAX = 0x00200000
C_CARR_FCW_DELTA_MAX = 64000000

C_CN0_AVG_DIV = 16
C_LOCK_SMOOTH_DIV = 8
C_CARR_LOCK_HYST_Q15 = 2048
C_PROMPT_MAG_MIN = 2500
C_DLL_ERR_LOCK_MAX = 40000
C_CARR_ERR_LOCK_MAX = 40000
C_DLL_ERR_TRACK_MAX = 40000
C_CARR_ERR_TRACK_MAX = 40000
C_LOCK_SCORE_MAX = 255
C_LOCK_SCORE_INC_BOTH = 4
C_LOCK_SCORE_INC_CODE = 2
C_LOCK_SCORE_DEC_CODE = 6
C_LOCK_SCORE_DEC_CARR = 2

TRACK_IDLE = 0
TRACK_PULLIN = 1
TRACK_LOCKED = 2

ASSIGNMENT_DEFAULTS: List[Tuple[int, int, int, int, int, int, int]] = [
    # ch, prn, dopp, code, max_ms, hold_ms, do_assign
    (0, 1, -1000, 848, 8, 1, 1),
    (0, 20, -1000, 320, 8, 1, 1),
    (0, 32, -1500, 1008, 8, 1, 1),
    (0, 17, -1500, 992, 8, 1, 1),
    (0, 11, 750, 928, 8, 1, 1),
    (0, 11, 750, 928, 50, 40, 0),
]


def trunc_div_tz(num: int, den: int) -> int:
    return int(num / den)


def div_pow2_tz(x: int, sh: int) -> int:
    if sh <= 0:
        return x
    if x < 0:
        return -((-x) >> sh)
    return x >> sh


def wrap_u32(x: int) -> int:
    return x & 0xFFFFFFFF


def wrap_s32(x: int) -> int:
    x &= 0xFFFFFFFF
    if x & 0x80000000:
        return x - 0x100000000
    return x


def sat_s32(x: int) -> int:
    if x > 0x7FFFFFFF:
        return 0x7FFFFFFF
    if x < -0x80000000:
        return -0x80000000
    return x


def clamp_i(x: int, lo: int, hi: int) -> int:
    return max(lo, min(hi, x))


def clamp_s16(x: int) -> int:
    return clamp_i(x, -32768, 32767)


def abs_i(x: int) -> int:
    return -x if x < 0 else x


def carr_fcw_from_hz_i(dopp_hz: int) -> int:
    return dopp_hz * C_CARR_FCW_PER_HZ


def bit_reverse(i: int, bits: int) -> int:
    out = 0
    v = i
    for _ in range(bits):
        out = (out << 1) | (v & 1)
        v >>= 1
    return out


def lo_luts_q15() -> Tuple[List[int], List[int]]:
    cos_lut = [int(round(math.cos(2.0 * math.pi * k / 1024.0) * 32767.0)) for k in range(1024)]
    sin_lut = [int(round(math.sin(2.0 * math.pi * k / 1024.0) * 32767.0)) for k in range(1024)]
    return cos_lut, sin_lut


def cpx_mul_q15(ar: int, ai: int, wr: int, wi: int) -> Tuple[int, int]:
    rr = ar * wr
    ii = ai * wi
    ri = ar * wi
    ir = ai * wr
    sum_re = rr - ii
    sum_im = ri + ir
    return sat_s32(div_pow2_tz(sum_re, 15)), sat_s32(div_pow2_tz(sum_im, 15))


def cpx_add_sat(a: Tuple[int, int], b: Tuple[int, int]) -> Tuple[int, int]:
    return sat_s32(a[0] + b[0]), sat_s32(a[1] + b[1])


def cpx_sub_sat(a: Tuple[int, int], b: Tuple[int, int]) -> Tuple[int, int]:
    return sat_s32(a[0] - b[0]), sat_s32(a[1] - b[1])


def fft_radix2_fixed(vec: Sequence[Tuple[int, int]], inverse: bool = False) -> List[Tuple[int, int]]:
    if len(vec) != C_NFFT:
        raise ValueError(f"expected FFT length {C_NFFT}, got {len(vec)}")

    cos_lut, sin_lut = lo_luts_q15()
    a: List[Tuple[int, int]] = [(0, 0)] * C_NFFT
    for i, sample in enumerate(vec):
        a[bit_reverse(i, C_FFT_BITS)] = sample

    fft_len = 2
    while fft_len <= C_NFFT:
        half = fft_len // 2
        base = 0
        while base < C_NFFT:
            for k in range(half):
                j = base + k
                tw_idx = (k * 1024) // fft_len
                wr = cos_lut[tw_idx]
                wi = sin_lut[tw_idx] if inverse else -sin_lut[tw_idx]
                tr, ti = cpx_mul_q15(a[j + half][0], a[j + half][1], wr, wi)
                u = a[j]
                a[j] = cpx_add_sat(u, (tr, ti))
                a[j + half] = cpx_sub_sat(u, (tr, ti))
            base += fft_len
        fft_len *= 2

    if inverse:
        a = [(sat_s32(div_pow2_tz(xr, C_FFT_BITS)), sat_s32(div_pow2_tz(xi, C_FFT_BITS))) for xr, xi in a]
    return a


def corr0_from_spectra(sig_fft: Sequence[Tuple[int, int]], code_fft: Sequence[Tuple[int, int]]) -> Tuple[int, int]:
    acc_re = 0
    acc_im = 0
    for (sr, si), (cr, ci) in zip(sig_fft, code_fft):
        acc_re += (sr * cr) + (si * ci)
        acc_im += (si * cr) - (sr * ci)
    return sat_s32(div_pow2_tz(acc_re, C_FFT_BITS)), sat_s32(div_pow2_tz(acc_im, C_FFT_BITS))


def build_prn_bits(prn: int) -> List[int]:
    if acq_ref is not None:
        return [int(v) for v in acq_ref.build_prn_sequence(prn)]
    bits = ca.ca_code(prn)
    return [1 if bool(v) else 0 for v in bits]


def build_code_fft_input(prn_bits: Sequence[int], code_start: int) -> List[Tuple[int, int]]:
    out: List[Tuple[int, int]] = [(0, 0)] * C_NFFT
    chip_idx = code_start % 1023
    code_nco = wrap_u32(chip_idx << 21)
    for s in range(C_SAMPLES_PER_MS):
        # Keep local-code samples in Q15 range so subsequent Q15 FFT twiddle
        # multiplies preserve dynamic range instead of collapsing to zeros.
        out[s] = (-32767, 0) if prn_bits[chip_idx] else (32767, 0)
        next_code = wrap_u32(code_nco + C_CODE_NCO_FCW)
        if next_code < code_nco:
            chip_idx = 0 if chip_idx == 1022 else chip_idx + 1
        code_nco = next_code
    return out


def build_mixed_fft_input(cap_i: Sequence[int], cap_q: Sequence[int], dopp_hz: int) -> List[Tuple[int, int]]:
    if len(cap_i) != C_SAMPLES_PER_MS or len(cap_q) != C_SAMPLES_PER_MS:
        raise ValueError("cap_i/cap_q must be 1 ms vectors")
    out: List[Tuple[int, int]] = [(0, 0)] * C_NFFT
    cos_lut, sin_lut = lo_luts_q15()
    carr_phase = 0
    carr_fcw = wrap_s32(dopp_hz * C_CARR_FCW_PER_HZ)
    for s in range(C_SAMPLES_PER_MS):
        phase_idx = (wrap_u32(carr_phase) >> 22) & 0x3FF
        lo_i = cos_lut[phase_idx]
        lo_q = -sin_lut[phase_idx]
        mix_re = trunc_div_tz((cap_i[s] * lo_i) - (cap_q[s] * lo_q), 32768)
        mix_im = trunc_div_tz((cap_i[s] * lo_q) + (cap_q[s] * lo_i), 32768)
        out[s] = (sat_s32(mix_re), sat_s32(mix_im))
        carr_phase = wrap_s32(carr_phase + carr_fcw)
    return out


def ten_log10_db100(x: int) -> int:
    lut = [0, 26, 51, 75, 97, 118, 138, 158, 176, 194, 211, 227, 243, 258, 273, 287, 301]
    if x <= 0:
        return 0
    base = 1
    octave = 0
    while base <= x // 2:
        base *= 2
        octave += 1
    frac_q10 = ((x - base) * 1024) // base
    frac_q10 = clamp_i(frac_q10, 0, 1023)
    seg = clamp_i(frac_q10 // 64, 0, 15)
    seg_frac = frac_q10 - (seg * 64)
    y0 = lut[seg]
    y1 = lut[seg + 1]
    interp = y0 + (((y1 - y0) * seg_frac + 32) // 64)
    return octave * 301 + interp


def cn0_dbhz_from_powers(sig_pow: int, noise_pow: int) -> int:
    if sig_pow <= 0:
        return 0
    noise = max(1, noise_pow)
    cn0_db100 = ten_log10_db100(sig_pow) - ten_log10_db100(noise) + 3000
    cn0_i = (cn0_db100 + 50) // 100
    return clamp_i(cn0_i, 0, 99)


def cn0_py_dbhz(x: np.ndarray) -> float:
    s = float(np.mean(np.abs(np.real(x))))
    r = float(np.sqrt(2.0) * np.std(np.imag(x)))
    if r <= 0.0:
        return 99.0
    return (20.0 * math.log10(s / r)) + 30.0


def rtl_discriminator_case(
    state: int,
    prev_valid: int,
    prompt_i_acc: int,
    prompt_q_acc: int,
    early_i_acc: int,
    early_q_acc: int,
    late_i_acc: int,
    late_q_acc: int,
    prev_prompt_i: int,
    prev_prompt_q: int,
) -> dict:
    prompt_mag = abs_i(prompt_i_acc) + abs_i(prompt_q_acc)
    early_mag = abs_i(early_i_acc) + abs_i(early_q_acc)
    late_mag = abs_i(late_i_acc) + abs_i(late_q_acc)
    curr_i = prompt_i_acc >> 12
    curr_q = prompt_q_acc >> 12

    dll_err = early_mag - late_mag
    dll_den = early_mag + late_mag + 1
    ratio_q8 = trunc_div_tz(dll_err * 256, dll_den)
    dll_q15 = clamp_i(ratio_q8 * 128, -32767, 32767)

    if state == TRACK_LOCKED:
        den = abs_i(curr_i) + 1
        ratio_q8 = trunc_div_tz(curr_q * 256, den)
        carrier_pll = clamp_i(ratio_q8 * 128, -C_PHASE_ERR_MAX_Q15, C_PHASE_ERR_MAX_Q15)
        carrier_fll = carrier_pll
    else:
        if prev_valid:
            prev_i = prev_prompt_i >> 12
            prev_q = prev_prompt_q >> 12
            cross = (prev_i * curr_q) - (prev_q * curr_i)
            dot = (prev_i * curr_i) + (prev_q * curr_q)
            den = abs_i(dot) + 1
            ratio_q8 = trunc_div_tz(cross * 256, den)
            carrier_fll = clamp_i(ratio_q8 * 128, -C_PHASE_ERR_MAX_Q15, C_PHASE_ERR_MAX_Q15)
        else:
            den = abs_i(curr_i) + 1
            ratio_q8 = trunc_div_tz(curr_q * 256, den)
            carrier_fll = clamp_i(ratio_q8 * 128, -C_PHASE_ERR_MAX_Q15, C_PHASE_ERR_MAX_Q15)
        carrier_pll = carrier_fll

    return {
        "prompt_mag": prompt_mag,
        "early_mag": early_mag,
        "late_mag": late_mag,
        "dll_q15": dll_q15,
        "pll_q15": carrier_pll,
        "fll_q15": carrier_fll,
        "sel_q15": carrier_pll if state == TRACK_LOCKED else carrier_fll,
        "prompt_i_s": curr_i,
        "prompt_q_s": curr_q,
        "early_i_s": early_i_acc >> 12,
        "early_q_s": early_q_acc >> 12,
        "late_i_s": late_i_acc >> 12,
        "late_q_s": late_q_acc >> 12,
    }


def rtl_loop_filter_step(
    state: int,
    dll_err_q15: int,
    carrier_err_pll_q15: int,
    carrier_err_fll_q15: int,
    code_loop_i: int,
    carr_loop_i: int,
    dopp_step_pullin: int,
    dopp_step_lock: int,
    pll_bw_hz: int,
    dll_bw_hz: int,
    pll_bw_narrow_hz: int,
    dll_bw_narrow_hz: int,
    fll_bw_hz: int,
) -> dict:
    if state == TRACK_LOCKED:
        pll_bw_sel = pll_bw_narrow_hz
        dll_bw_sel = dll_bw_narrow_hz
    else:
        pll_bw_sel = pll_bw_hz
        dll_bw_sel = dll_bw_hz

    pll_bw_sel = max(pll_bw_sel, C_PLL_GAIN_MIN_Q8_8)
    dll_bw_sel = max(dll_bw_sel, C_DLL_GAIN_MIN_Q8_8)

    code_kp = max(1, (dll_bw_sel * C_CODE_LOOP_KP_PER_HZ_Q8 + 128) // 256)
    code_ki = max(1, code_kp // C_CODE_LOOP_KI_DIV)
    code_int = clamp_i(code_loop_i + trunc_div_tz(dll_err_q15 * code_ki, 32768), -C_CODE_FCW_DELTA_MAX, C_CODE_FCW_DELTA_MAX)
    code_prop = trunc_div_tz(dll_err_q15 * code_kp, 32768)
    code_delta = clamp_i(code_int + code_prop, -C_CODE_FCW_DELTA_MAX, C_CODE_FCW_DELTA_MAX)
    code_fcw = C_CODE_NCO_FCW + code_delta

    if state == TRACK_LOCKED:
        carr_kp = max(1, (pll_bw_sel * C_CARR_FCW_PER_HZ + 128) // 256)
        carr_ki = max(1, carr_kp // C_PLL_LOOP_KI_DIV)
        carr_int = clamp_i(carr_loop_i + trunc_div_tz(carrier_err_pll_q15 * carr_ki, 32768), -C_CARR_FCW_DELTA_MAX, C_CARR_FCW_DELTA_MAX)
        carr_prop = trunc_div_tz(carrier_err_pll_q15 * carr_kp, 32768)
        carr_max_step = max(1, carr_fcw_from_hz_i(dopp_step_lock))
        carr_prop = clamp_i(carr_prop, -carr_max_step, carr_max_step)
        carr_cmd = clamp_i(carr_int + carr_prop, -C_CARR_FCW_DELTA_MAX, C_CARR_FCW_DELTA_MAX)
    else:
        fll_gain = max(fll_bw_hz, C_FLL_GAIN_MIN_Q8_8)
        carr_kp = max(1, (fll_gain * C_CARR_FCW_PER_HZ * C_FLL_LOOP_STEP_SCALE + 128) // 256)
        fll_step = trunc_div_tz(carrier_err_fll_q15 * carr_kp, 32768)
        carr_max_step = max(1, carr_fcw_from_hz_i(dopp_step_pullin))
        fll_step = clamp_i(fll_step, -carr_max_step, carr_max_step)
        pll_assist = trunc_div_tz(carrier_err_pll_q15 * carr_kp, 32768)
        pll_assist = trunc_div_tz(pll_assist, C_PULLIN_PLL_ASSIST_DIV)
        pll_assist = clamp_i(pll_assist, -carr_max_step, carr_max_step)
        carr_cmd = clamp_i(carr_loop_i + fll_step + pll_assist, -C_CARR_FCW_DELTA_MAX, C_CARR_FCW_DELTA_MAX)
        carr_int = carr_cmd

    dopp = clamp_s16(trunc_div_tz(carr_cmd, C_CARR_FCW_PER_HZ))
    return {
        "code_loop_i_o": code_int,
        "code_delta": code_delta,
        "code_fcw_o": code_fcw,
        "carr_loop_i_o": carr_int,
        "carr_fcw_cmd_o": carr_cmd,
        "dopp_o": dopp,
    }


def rtl_power_lock_step(
    prompt_i: int,
    prompt_q: int,
    early_i: int,
    early_q: int,
    late_i: int,
    late_q: int,
    cn0_sig_avg_i: int,
    cn0_noise_avg_i: int,
    nbd_avg_i: int,
    nbp_avg_i: int,
) -> dict:
    sig_pow = prompt_i * prompt_i + prompt_q * prompt_q
    early_pow = early_i * early_i + early_q * early_q
    late_pow = late_i * late_i + late_q * late_q
    noise_sample = max(1, (early_pow // 2) + (late_pow // 2))
    sig_sample = max(1, sig_pow - noise_sample)

    cn0_sig_avg = cn0_sig_avg_i + trunc_div_tz(sig_sample - cn0_sig_avg_i, C_CN0_AVG_DIV)
    cn0_noise_avg = cn0_noise_avg_i + trunc_div_tz(noise_sample - cn0_noise_avg_i, C_CN0_AVG_DIV)
    cn0_sig_avg = clamp_i(cn0_sig_avg, 1, 2_000_000)
    cn0_noise_avg = clamp_i(cn0_noise_avg, 1, 2_000_000)
    cn0_dbhz = cn0_dbhz_from_powers(cn0_sig_avg, cn0_noise_avg)

    nbd_sample = (prompt_i * prompt_i) - (prompt_q * prompt_q)
    nbp_sample = max(1, (prompt_i * prompt_i) + (prompt_q * prompt_q))
    nbd_avg = nbd_avg_i + trunc_div_tz(nbd_sample - nbd_avg_i, C_LOCK_SMOOTH_DIV)
    nbp_avg = nbp_avg_i + trunc_div_tz(nbp_sample - nbp_avg_i, C_LOCK_SMOOTH_DIV)
    nbp_avg = max(1, nbp_avg)

    metric = trunc_div_tz(nbd_avg * 32768, nbp_avg)
    metric = clamp_i(metric, -32768, 32767)
    return {
        "cn0_sig_avg_o": cn0_sig_avg,
        "cn0_noise_avg_o": cn0_noise_avg,
        "nbd_avg_o": nbd_avg,
        "nbp_avg_o": nbp_avg,
        "cn0_dbhz_o": clamp_i(cn0_dbhz, 0, 99),
        "carrier_metric_o": metric,
    }


def rtl_lock_state_step(
    state_i: int,
    prompt_mag_i: int,
    cn0_dbhz_i: int,
    min_cn0_dbhz_i: int,
    dll_err_q15_i: int,
    carrier_metric_i: int,
    carrier_err_q15_i: int,
    carrier_lock_th_i: int,
    max_lock_fail_i: int,
    lock_score_i: int,
) -> dict:
    code_enter = (prompt_mag_i > C_PROMPT_MAG_MIN) and (cn0_dbhz_i >= min_cn0_dbhz_i) and (abs_i(dll_err_q15_i) < C_DLL_ERR_LOCK_MAX)
    code_track = (prompt_mag_i > C_PROMPT_MAG_MIN) and (cn0_dbhz_i >= min_cn0_dbhz_i) and (abs_i(dll_err_q15_i) < C_DLL_ERR_TRACK_MAX)

    carrier_enter_th = carrier_lock_th_i
    carrier_track_th = carrier_enter_th - C_CARR_LOCK_HYST_Q15
    carrier_track_th = max(carrier_track_th, -32768)
    carrier_metric_eval = abs_i(carrier_metric_i) if state_i == TRACK_PULLIN else carrier_metric_i
    carrier_enter = (carrier_metric_eval >= carrier_enter_th) and (abs_i(carrier_err_q15_i) < C_CARR_ERR_LOCK_MAX)
    carrier_track = (carrier_metric_eval >= carrier_track_th) and (abs_i(carrier_err_q15_i) < C_CARR_ERR_TRACK_MAX)

    max_lock_fail = clamp_i(max_lock_fail_i, 4, C_LOCK_SCORE_MAX - 8)
    lock_enter_th = max_lock_fail
    lock_exit_th = max(2, lock_enter_th // 2)

    lock_score = lock_score_i
    if code_track and carrier_track:
        lock_score += C_LOCK_SCORE_INC_BOTH
    elif code_track:
        lock_score += C_LOCK_SCORE_INC_CODE
    else:
        lock_score -= C_LOCK_SCORE_DEC_CODE
    if not carrier_track:
        lock_score -= C_LOCK_SCORE_DEC_CARR
    lock_score = clamp_i(lock_score, 0, C_LOCK_SCORE_MAX)

    state_o = state_i
    code_lock_o = 0
    carrier_lock_o = 0
    if state_i == TRACK_PULLIN:
        if code_enter and carrier_enter and lock_score >= lock_enter_th:
            state_o = TRACK_LOCKED
            code_lock_o = 1
            carrier_lock_o = 1
        else:
            code_lock_o = 1 if code_enter else 0
            carrier_lock_o = 1 if carrier_enter else 0
    elif state_i == TRACK_LOCKED:
        if lock_score <= lock_exit_th:
            state_o = TRACK_PULLIN
            code_lock_o = 0
            carrier_lock_o = 0
        else:
            state_o = TRACK_LOCKED
            code_lock_o = 1
            carrier_lock_o = 1 if carrier_track else 0
    return {
        "state_o": state_o,
        "code_lock_o": code_lock_o,
        "carrier_lock_o": carrier_lock_o,
        "lock_score_o": lock_score,
    }


def write_int_lines(path: Path, values: Iterable[int]) -> None:
    with path.open("w", encoding="utf-8") as f:
        for v in values:
            f.write(f"{int(v)}\n")


def git_rev(path: Path) -> str:
    try:
        out = subprocess.check_output(["git", "-C", str(path), "rev-parse", "--short", "HEAD"], text=True).strip()
        return out
    except Exception:
        return "unknown"


def generate_acquisition_vectors(vectors_dir: Path, reports_dir: Path) -> None:
    def first10(bits_v: Sequence[int]) -> int:
        r_v = 0
        for i in range(10):
            r_v = (r_v * 2) + (1 if bits_v[i] else 0)
        return r_v

    def gnsstools_bits(prn_v: int) -> List[int]:
        return [1 if bool(v) else 0 for v in ca.ca_code(prn_v)]

    prn1 = build_prn_bits(1)
    prn7 = build_prn_bits(7)
    prn19 = build_prn_bits(19)
    prn1_gns = gnsstools_bits(1)
    prn7_gns = gnsstools_bits(7)
    prn19_gns = gnsstools_bits(19)

    if prn1 != prn1_gns or prn7 != prn7_gns or prn19 != prn19_gns:
        raise ValueError(
            "PRN convention mismatch between RTL/reference generator and gnsstools "
            "(PRN1/7/19 sequence disagreement)."
        )

    write_int_lines(vectors_dir / "acq_fft_prn_prn1.txt", prn1)
    write_int_lines(vectors_dir / "acq_fft_prn_prn7.txt", prn7)
    write_int_lines(vectors_dir / "acq_fft_prn_prn19.txt", prn19)

    code_input = build_code_fft_input(prn7, 17)
    code_fft = fft_radix2_fixed(code_input, inverse=False)
    with (vectors_dir / "acq_fft_code_gen_expected_prn7_code17.txt").open("w", encoding="utf-8") as f:
        for re_v, im_v in code_fft:
            f.write(f"{re_v} {im_v}\n")

    mix_cases: List[dict] = []
    cap_i0 = [0] * C_SAMPLES_PER_MS
    cap_q0 = [0] * C_SAMPLES_PER_MS
    cap_i0[0] = 1200
    cap_i0[1] = -700
    cap_q0[0] = 300
    cap_q0[1] = 500
    mix_cases.append({"dopp": 1250, "cap_i": cap_i0, "cap_q": cap_q0})

    cap_i1 = [0] * C_SAMPLES_PER_MS
    cap_q1 = [0] * C_SAMPLES_PER_MS
    cap_i1[0] = 32767
    cap_q1[0] = -32768
    cap_i1[1] = -32768
    cap_q1[1] = 32767
    cap_i1[2] = 16000
    cap_q1[2] = -14000
    mix_cases.append({"dopp": -4000, "cap_i": cap_i1, "cap_q": cap_q1})

    cap_i2 = [0] * C_SAMPLES_PER_MS
    cap_q2 = [0] * C_SAMPLES_PER_MS
    pattern_i = [18000, -12000, 8000, -4000, 2000, -1000, 500, -250]
    pattern_q = [-9000, 6000, -4000, 2000, -1000, 500, -250, 125]
    for idx in range(len(pattern_i)):
        cap_i2[idx] = pattern_i[idx]
        cap_q2[idx] = pattern_q[idx]
    mix_cases.append({"dopp": 0, "cap_i": cap_i2, "cap_q": cap_q2})

    cap_i3 = [0] * C_SAMPLES_PER_MS
    cap_q3 = [0] * C_SAMPLES_PER_MS
    for idx in range(64):
        cap_i3[idx] = ((idx * 913) % 28001) - 14000
        cap_q3[idx] = 12000 - ((idx * 733) % 24001)
    mix_cases.append({"dopp": 9500, "cap_i": cap_i3, "cap_q": cap_q3})

    cap_i4 = [0] * C_SAMPLES_PER_MS
    cap_q4 = [0] * C_SAMPLES_PER_MS
    for idx in range(128):
        cap_i4[idx] = 32767 if (idx % 2) == 0 else -32768
        cap_q4[idx] = -16384 if (idx % 4) < 2 else 16384
    mix_cases.append({"dopp": -10000, "cap_i": cap_i4, "cap_q": cap_q4})

    with (vectors_dir / "acq_fft_mix_fft_cases.txt").open("w", encoding="utf-8") as f:
        f.write(f"{len(mix_cases)}\n")
        for case in mix_cases:
            mixed = build_mixed_fft_input(case["cap_i"], case["cap_q"], case["dopp"])
            sig_fft = fft_radix2_fixed(mixed, inverse=False)
            f.write(f"{case['dopp']}\n")
            for i_v, q_v in zip(case["cap_i"], case["cap_q"]):
                f.write(f"{i_v} {q_v}\n")
            for re_v, im_v in sig_fft:
                f.write(f"{re_v} {im_v}\n")

    corr_cases = [
        (4096, 0, 0, 2048, 2, 0, 0, 1),
        (12345, -6789, -111, 222, 3, -2, 4, 1),
        (-2500, 3200, 777, -1555, -3, 2, 5, -4),
        (32767, -32768, -32768, 32767, 15, -11, -9, 7),
        (250000, 125000, -400000, 300000, 6, 5, -4, 9),
        (-900000, 450000, 700000, -200000, -8, 3, 2, -5),
        (1, -1, -1, 1, 32767, 0, 0, -32768),
        (0, 0, 0, 0, 123, -456, 789, -1011),
    ]
    with (vectors_dir / "acq_fft_corr_cases.txt").open("w", encoding="utf-8") as f:
        f.write(f"{len(corr_cases)}\n")
        for case in corr_cases:
            sig = [(0, 0)] * C_NFFT
            code = [(0, 0)] * C_NFFT
            sig[0] = (case[0], case[1])
            sig[1] = (case[2], case[3])
            code[0] = (case[4], case[5])
            code[1] = (case[6], case[7])
            corr_re, corr_im = corr0_from_spectra(sig, code)
            f.write(
                " ".join(str(v) for v in (*case, corr_re, corr_im)) + "\n"
            )

    with (vectors_dir / "acq_fft_tb_expected.txt").open("w", encoding="utf-8") as f:
        f.write("1 0 0 0\n")

    # Secondary artifact: floating FFT comparison to bound fixed-point deltas.
    code_np = np.zeros(C_NFFT, dtype=np.complex128)
    code_np[:C_SAMPLES_PER_MS] = np.array([v[0] + 1j * v[1] for v in code_input[:C_SAMPLES_PER_MS]], dtype=np.complex128)
    code_np_fft = np.fft.fft(code_np)
    abs_delta = np.abs(np.array([complex(*v) for v in code_fft]) - code_np_fft)
    max_abs_delta = float(np.max(abs_delta))
    mean_abs_delta = float(np.mean(abs_delta))
    max_fft_mag = float(np.max(np.abs(code_np_fft)))
    max_abs_delta_ratio = max_abs_delta / max(1.0, max_fft_mag)
    unique_bins = len(set(code_fft))
    nonzero_bins = sum(1 for re_v, im_v in code_fft if re_v != 0 or im_v != 0)

    # Guardrails to catch accidental fixed-point degeneracy in vector generation.
    if unique_bins <= 8:
        raise ValueError(
            f"Code FFT vector degeneracy detected: only {unique_bins} unique bins."
        )
    if nonzero_bins < (C_NFFT // 8):
        raise ValueError(
            f"Code FFT vector degeneracy detected: only {nonzero_bins} non-zero bins."
        )
    if max_abs_delta_ratio > 0.30:
        raise ValueError(
            "Fixed-point FFT diverges from independent NumPy FFT beyond tolerance: "
            f"ratio={max_abs_delta_ratio:.4f}"
        )

    summary = {
        "code_fft_np_vs_fixed_max_abs_delta": max_abs_delta,
        "code_fft_np_vs_fixed_mean_abs_delta": mean_abs_delta,
        "code_fft_np_vs_fixed_max_abs_delta_ratio": max_abs_delta_ratio,
        "code_fft_unique_bins": unique_bins,
        "code_fft_nonzero_bins": nonzero_bins,
        "mix_case_count": len(mix_cases),
        "corr_case_count": len(corr_cases),
        "first10": {
            "prn1_tb": first10(prn1),
            "prn7_tb": first10(prn7),
            "prn19_tb": first10(prn19),
            "prn1_gnsstools": first10(prn1_gns),
            "prn7_gnsstools": first10(prn7_gns),
            "prn19_gnsstools": first10(prn19_gns),
        },
    }
    with (reports_dir / "acq_subblock_summary.json").open("w", encoding="utf-8") as f:
        json.dump(summary, f, indent=2, sort_keys=True)


def generate_tracking_vectors(vectors_dir: Path, reports_dir: Path) -> None:
    # Discriminator vectors.
    disc_rows: List[List[int]] = []
    disc_report_rows: List[str] = []
    prompt_trace = [
        complex(90.0, 20.0),
        complex(100.0, 30.0),
        complex(115.0, 10.0),
        complex(120.0, -15.0),
        complex(80.0, -35.0),
        complex(70.0, -45.0),
    ]
    for idx, p in enumerate(prompt_trace):
        state = TRACK_PULLIN if idx < 3 else TRACK_LOCKED
        prev_valid = 1 if idx > 0 else 0
        prev = prompt_trace[idx - 1] if idx > 0 else complex(0.0, 0.0)
        e = p * 0.8 + complex(5.0, -2.0)
        l = p * 0.6 + complex(-4.0, 1.0)
        row_in = [
            state,
            prev_valid,
            int(round(p.real * 4096.0)),
            int(round(p.imag * 4096.0)),
            int(round(e.real * 4096.0)),
            int(round(e.imag * 4096.0)),
            int(round(l.real * 4096.0)),
            int(round(l.imag * 4096.0)),
            int(round(prev.real * 4096.0)),
            int(round(prev.imag * 4096.0)),
        ]
        rtl = rtl_discriminator_case(*row_in)
        row = row_in + [
            rtl["prompt_mag"],
            rtl["early_mag"],
            rtl["late_mag"],
            rtl["dll_q15"],
            rtl["pll_q15"],
            rtl["fll_q15"],
            rtl["sel_q15"],
            rtl["prompt_i_s"],
            rtl["prompt_q_s"],
            rtl["early_i_s"],
            rtl["early_q_s"],
            rtl["late_i_s"],
            rtl["late_q_s"],
        ]
        disc_rows.append(row)

        sw_pll = discriminator.pll_costas(p)
        sw_fll = discriminator.fll_atan2(p, prev) if prev_valid else sw_pll
        disc_report_rows.append(
            f"{idx},{rtl['pll_q15']},{rtl['fll_q15']},{sw_pll:.6f},{sw_fll:.6f}"
        )

    with (vectors_dir / "track_discriminators_vectors.txt").open("w", encoding="utf-8") as f:
        f.write(f"{len(disc_rows)}\n")
        for row in disc_rows:
            f.write(" ".join(str(v) for v in row) + "\n")

    with (reports_dir / "track_discriminator_vs_gnsstools.csv").open("w", encoding="utf-8") as f:
        f.write("epoch,rtl_pll_q15,rtl_fll_q15,gnsstools_pll_rad,gnsstools_fll_rad\n")
        for row in disc_report_rows:
            f.write(row + "\n")

    # Loop filter vectors.
    loop_rows: List[List[int]] = []
    code_loop_i = 8000
    carr_loop_i = 12000
    for idx in range(12):
        state = TRACK_PULLIN if idx < 6 else TRACK_LOCKED
        dll_err = int(round(2800.0 * math.cos(idx * 0.45)))
        pll_err = int(round(1800.0 * math.sin(idx * 0.33)))
        fll_err = int(round(3200.0 * math.sin(idx * 0.27 + 0.2)))
        out = rtl_loop_filter_step(
            state=state,
            dll_err_q15=dll_err,
            carrier_err_pll_q15=pll_err,
            carrier_err_fll_q15=fll_err,
            code_loop_i=code_loop_i,
            carr_loop_i=carr_loop_i,
            dopp_step_pullin=80,
            dopp_step_lock=20,
            pll_bw_hz=8960,
            dll_bw_hz=512,
            pll_bw_narrow_hz=1280,
            dll_bw_narrow_hz=128,
            fll_bw_hz=2560,
        )
        row = [
            state,
            dll_err,
            pll_err,
            fll_err,
            code_loop_i,
            carr_loop_i,
            out["code_loop_i_o"],
            out["code_delta"],
            out["carr_loop_i_o"],
            out["carr_fcw_cmd_o"],
            out["dopp_o"],
        ]
        loop_rows.append(row)
        code_loop_i = out["code_loop_i_o"]
        carr_loop_i = out["carr_loop_i_o"]

    with (vectors_dir / "track_loop_filters_vectors.txt").open("w", encoding="utf-8") as f:
        f.write(f"{len(loop_rows)}\n")
        for row in loop_rows:
            f.write(" ".join(str(v) for v in row) + "\n")

    # Power lock vectors.
    power_rows: List[List[int]] = []
    cn0_sig_avg = 1000
    cn0_noise_avg = 300
    nbd_avg = 50
    nbp_avg = 400
    cn0_track_complex: List[complex] = []
    for idx in range(24):
        amp = 85 + int(round(18.0 * math.sin(idx * 0.35)))
        q_amp = 25 + int(round(12.0 * math.cos(idx * 0.29)))
        prompt_i = amp
        prompt_q = q_amp
        early_i = int(round(0.82 * amp))
        early_q = int(round(0.76 * q_amp))
        late_i = int(round(0.71 * amp))
        late_q = int(round(0.64 * q_amp))
        out = rtl_power_lock_step(
            prompt_i=prompt_i,
            prompt_q=prompt_q,
            early_i=early_i,
            early_q=early_q,
            late_i=late_i,
            late_q=late_q,
            cn0_sig_avg_i=cn0_sig_avg,
            cn0_noise_avg_i=cn0_noise_avg,
            nbd_avg_i=nbd_avg,
            nbp_avg_i=nbp_avg,
        )
        row = [
            prompt_i,
            prompt_q,
            early_i,
            early_q,
            late_i,
            late_q,
            cn0_sig_avg,
            cn0_noise_avg,
            nbd_avg,
            nbp_avg,
            out["cn0_sig_avg_o"],
            out["cn0_noise_avg_o"],
            out["nbd_avg_o"],
            out["nbp_avg_o"],
            out["cn0_dbhz_o"],
            out["carrier_metric_o"],
        ]
        power_rows.append(row)
        cn0_sig_avg = out["cn0_sig_avg_o"]
        cn0_noise_avg = out["cn0_noise_avg_o"]
        nbd_avg = out["nbd_avg_o"]
        nbp_avg = out["nbp_avg_o"]
        cn0_track_complex.append(complex(float(prompt_i), float(prompt_q)))

    with (vectors_dir / "track_power_lock_vectors.txt").open("w", encoding="utf-8") as f:
        f.write(f"{len(power_rows)}\n")
        for row in power_rows:
            f.write(" ".join(str(v) for v in row) + "\n")

    with (reports_dir / "track_cn0_trend.csv").open("w", encoding="utf-8") as f:
        f.write("window_idx,cn0_py_dbhz,rtl_cn0_dbhz_last\n")
        win = 6
        for idx in range(0, len(cn0_track_complex), win):
            blk = np.array(cn0_track_complex[idx : idx + win], dtype=np.complex128)
            if len(blk) < 2:
                break
            py_cn0 = cn0_py_dbhz(blk)
            rtl_cn0 = power_rows[min(idx + win - 1, len(power_rows) - 1)][14]
            f.write(f"{idx // win},{py_cn0:.3f},{rtl_cn0}\n")

    # Lock state vectors.
    lock_rows: List[List[int]] = []
    state = TRACK_PULLIN
    lock_score = 10
    for idx in range(28):
        if idx < 8:
            prompt_mag = 11000
            cn0 = 42
            dll_err = 120
            carrier_metric = 24000
            carrier_err = 140
        elif idx < 18:
            prompt_mag = 9500
            cn0 = 36
            dll_err = 2200
            carrier_metric = 19000
            carrier_err = 1200
        else:
            prompt_mag = 1200
            cn0 = 5
            dll_err = 25000
            carrier_metric = 1000
            carrier_err = 18000

        out = rtl_lock_state_step(
            state_i=state,
            prompt_mag_i=prompt_mag,
            cn0_dbhz_i=cn0,
            min_cn0_dbhz_i=20,
            dll_err_q15_i=dll_err,
            carrier_metric_i=carrier_metric,
            carrier_err_q15_i=carrier_err,
            carrier_lock_th_i=16384,
            max_lock_fail_i=20,
            lock_score_i=lock_score,
        )

        row = [
            state,
            prompt_mag,
            cn0,
            20,
            dll_err,
            carrier_metric,
            carrier_err,
            16384,
            20,
            lock_score,
            out["state_o"],
            out["code_lock_o"],
            out["carrier_lock_o"],
            out["lock_score_o"],
        ]
        lock_rows.append(row)
        state = out["state_o"]
        lock_score = out["lock_score_o"]

    with (vectors_dir / "track_lock_state_vectors.txt").open("w", encoding="utf-8") as f:
        f.write(f"{len(lock_rows)}\n")
        for row in lock_rows:
            f.write(" ".join(str(v) for v in row) + "\n")


@dataclass
class AssignmentResult:
    rows: List[Tuple[int, int, int, int, int, int, int]]
    source: str
    metrics: List[Tuple[int, int, int, int]]


def derive_assignments(input_file: Path) -> AssignmentResult:
    if acq_ref is None or not input_file.exists():
        return AssignmentResult(
            rows=ASSIGNMENT_DEFAULTS,
            source="defaults",
            metrics=[(row[1], row[3], row[2], 0) for row in ASSIGNMENT_DEFAULTS],
        )

    metrics: List[Tuple[int, int, int, int]] = []
    derived: List[Tuple[int, int, int, int, int, int, int]] = []
    targets = [(0, 1), (0, 20), (0, 32), (0, 17), (0, 11)]
    for ch, prn in targets:
        try:
            ns = argparse.Namespace(
                input_file=str(input_file),
                file_sample_rate=2_000_000,
                dut_sample_rate=2_000_000,
                time_offset=0.0,
                window_size=C_SAMPLES_PER_MS,
                anti_alias=True,
                prn=prn,
                doppler_min=-2000,
                doppler_max=2000,
                doppler_step=250,
                code_bins=64,
                code_step=16,
                doppler_bins=17,
                expected_result_code=None,
                expected_result_dopp=None,
                require_nonzero=True,
                progress=False,
                plot_3d=False,
                plots_dir="sim/plots",
                show_plots=False,
            )
            res = acq_ref.run_reference(ns)
            derived.append((ch, prn, int(res.best_dopp), int(res.best_code), 8, 1, 1))
            metrics.append((prn, int(res.best_code), int(res.best_dopp), int(res.best_metric)))
        except Exception:
            return AssignmentResult(
                rows=ASSIGNMENT_DEFAULTS,
                source="defaults_fallback",
                metrics=[(row[1], row[3], row[2], 0) for row in ASSIGNMENT_DEFAULTS],
            )

    # Keep final hold check row from default sequence.
    derived.append(ASSIGNMENT_DEFAULTS[-1])
    metrics.append((ASSIGNMENT_DEFAULTS[-1][1], ASSIGNMENT_DEFAULTS[-1][3], ASSIGNMENT_DEFAULTS[-1][2], 0))
    return AssignmentResult(rows=derived, source="validate_acq_fullspace_prn1", metrics=metrics)


def write_assignment_files(vectors_dir: Path, reports_dir: Path, input_file: Path, derive: bool) -> None:
    if derive:
        assignment = derive_assignments(input_file)
    else:
        assignment = AssignmentResult(
            rows=ASSIGNMENT_DEFAULTS,
            source="defaults",
            metrics=[(row[1], row[3], row[2], 0) for row in ASSIGNMENT_DEFAULTS],
        )

    with (vectors_dir / "chan_bank_assignments.txt").open("w", encoding="utf-8") as f:
        f.write(f"{len(assignment.rows)}\n")
        for row in assignment.rows:
            f.write(" ".join(str(v) for v in row) + "\n")

    # channel index, min cn0, max cn0
    cn0_ranges = [
        (0, 12, 70),
        (1, 12, 70),
        (2, 12, 70),
        (3, 12, 70),
    ]
    with (vectors_dir / "chan_bank_nav_store_cn0_ranges.txt").open("w", encoding="utf-8") as f:
        f.write(f"{len(cn0_ranges)}\n")
        for row in cn0_ranges:
            f.write(" ".join(str(v) for v in row) + "\n")

    with (reports_dir / "acq_assignment_reference.csv").open("w", encoding="utf-8") as f:
        f.write("prn,code,dopp,metric\n")
        for prn, code, dopp, metric in assignment.metrics:
            f.write(f"{prn},{code},{dopp},{metric}\n")

    with (reports_dir / "acq_assignment_reference.json").open("w", encoding="utf-8") as f:
        json.dump(
            {
                "source": assignment.source,
                "rows": [
                    {
                        "channel": r[0],
                        "prn": r[1],
                        "dopp_hz": r[2],
                        "code": r[3],
                        "max_ms": r[4],
                        "hold_ms": r[5],
                        "do_assign": r[6],
                    }
                    for r in assignment.rows
                ],
            },
            f,
            indent=2,
            sort_keys=True,
        )


def write_metadata(reports_dir: Path, vectors_dir: Path, input_file: Path, profile: str, derive_assignments_flag: bool) -> None:
    input_meta = {
        "path": str(input_file),
        "exists": input_file.exists(),
        "size_bytes": input_file.stat().st_size if input_file.exists() else 0,
    }
    meta = {
        "generated_utc": datetime.now(timezone.utc).isoformat(),
        "profile": profile,
        "derive_assignments": derive_assignments_flag,
        "main_repo_commit": git_rev(ROOT),
        "gnss_dsp_tools_commit": git_rev(GNSS_TOOLS_DIR),
        "input_capture": input_meta,
        "vectors_dir": str(vectors_dir),
        "reports_dir": str(reports_dir),
    }
    with (reports_dir / "gnss_dsp_provenance.json").open("w", encoding="utf-8") as f:
        json.dump(meta, f, indent=2, sort_keys=True)


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--profile", choices=("unit", "regress"), default="unit")
    parser.add_argument("--vectors-dir", default="sim/vectors")
    parser.add_argument("--reports-dir", default="sim/reports")
    parser.add_argument(
        "--input-file",
        default="2013_04_04_GNSS_SIGNAL_at_CTTC_SPAIN/2013_04_04_GNSS_SIGNAL_at_CTTC_SPAIN_2msps.dat",
    )
    parser.add_argument("--derive-assignments", action="store_true", default=False)
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    vectors_dir = (ROOT / args.vectors_dir).resolve() if not Path(args.vectors_dir).is_absolute() else Path(args.vectors_dir)
    reports_dir = (ROOT / args.reports_dir).resolve() if not Path(args.reports_dir).is_absolute() else Path(args.reports_dir)
    input_file = (ROOT / args.input_file).resolve() if not Path(args.input_file).is_absolute() else Path(args.input_file)

    vectors_dir.mkdir(parents=True, exist_ok=True)
    reports_dir.mkdir(parents=True, exist_ok=True)

    derive_assignments_flag = args.derive_assignments or args.profile == "regress"

    generate_acquisition_vectors(vectors_dir=vectors_dir, reports_dir=reports_dir)
    generate_tracking_vectors(vectors_dir=vectors_dir, reports_dir=reports_dir)
    write_assignment_files(
        vectors_dir=vectors_dir,
        reports_dir=reports_dir,
        input_file=input_file,
        derive=derive_assignments_flag,
    )
    write_metadata(
        reports_dir=reports_dir,
        vectors_dir=vectors_dir,
        input_file=input_file,
        profile=args.profile,
        derive_assignments_flag=derive_assignments_flag,
    )

    print(f"Generated GNSS-DSP vectors in {vectors_dir}")
    print(f"Generated GNSS-DSP reports in {reports_dir}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
