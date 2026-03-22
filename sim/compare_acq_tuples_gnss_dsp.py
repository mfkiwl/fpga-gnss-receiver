#!/usr/bin/env python3
"""Compare ACQ_TUPLE logs against GNSS-DSP reference acquisition tuples."""

from __future__ import annotations

import argparse
import json
import re
import sys
from pathlib import Path
from typing import Dict, List

import validate_acq_fullspace_prn1 as acq_ref

PAT = re.compile(
    r"ACQ_TUPLE\s+tag=(\S+)\s+success='([01])'\s+valid='([01])'\s+"
    r"prn=([-0-9]+)\s+code=([-0-9]+)\s+dopp=([-0-9]+)\s+metric=([-0-9]+)"
)

TAG_TO_PRN = {
    "file_prn1": 1,
    "file_prn11": 11,
    "file_prn17": 17,
    "file_prn20": 20,
    "file_prn32": 32,
}


def parse_reference_csv(path: Path) -> Dict[int, Dict[str, int]]:
    out: Dict[int, Dict[str, int]] = {}
    if not path.exists():
        return out
    for line in path.read_text(encoding="utf-8", errors="ignore").splitlines():
        row = line.strip()
        if not row or row.startswith("prn,"):
            continue
        parts = row.split(",")
        if len(parts) < 4:
            continue
        try:
            prn = int(parts[0])
            if prn in out:
                continue
            out[prn] = {
                "prn": prn,
                "code": int(parts[1]),
                "dopp": int(parts[2]),
                "metric": int(parts[3]),
            }
        except ValueError:
            continue
    return out


def parse_log(path: Path) -> Dict[str, Dict[str, int]]:
    out: Dict[str, Dict[str, int]] = {}
    for line in path.read_text(encoding="utf-8", errors="ignore").splitlines():
        m = PAT.search(line)
        if not m:
            continue
        tag, suc, val, prn, code, dopp, metric = m.groups()
        out[tag] = {
            "success": int(suc),
            "valid": int(val),
            "prn": int(prn),
            "code": int(code),
            "dopp": int(dopp),
            "metric": int(metric),
        }
    return out


def run_reference_for_prn(input_file: Path, prn: int) -> Dict[str, int]:
    ns = argparse.Namespace(
        input_file=str(input_file),
        file_sample_rate=2_000_000,
        dut_sample_rate=2_000_000,
        time_offset=0.0,
        window_size=acq_ref.C_SAMPLES_PER_MS,
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
    return {
        "prn": prn,
        "code": int(res.best_code),
        "dopp": int(res.best_dopp),
        "metric": int(res.best_metric),
    }


def parse_args() -> argparse.Namespace:
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--log", required=True, help="Path to simulation log containing ACQ_TUPLE lines.")
    p.add_argument(
        "--input-file",
        default="2013_04_04_GNSS_SIGNAL_at_CTTC_SPAIN/2013_04_04_GNSS_SIGNAL_at_CTTC_SPAIN_2msps.dat",
    )
    p.add_argument("--report-json", default="sim/reports/acq_tuple_diff.json")
    p.add_argument("--report-csv", default="sim/reports/acq_tuple_diff.csv")
    p.add_argument(
        "--reference-csv",
        default="sim/reports/acq_assignment_reference.csv",
        help="Optional precomputed reference CSV from sim/gen_gnss_dsp_vectors.py.",
    )
    p.add_argument(
        "--metric-rel-tol",
        type=float,
        default=0.35,
        help="Maximum relative metric delta for pass/fail annotation.",
    )
    return p.parse_args()


def main() -> int:
    args = parse_args()
    log_path = Path(args.log)
    input_file = Path(args.input_file)
    report_json = Path(args.report_json)
    report_csv = Path(args.report_csv)
    reference_csv = Path(args.reference_csv) if args.reference_csv else Path()
    report_json.parent.mkdir(parents=True, exist_ok=True)
    report_csv.parent.mkdir(parents=True, exist_ok=True)

    if not log_path.exists():
        print(f"ERROR: log not found: {log_path}", file=sys.stderr)
        return 1
    if not input_file.exists():
        print(f"ERROR: input file not found: {input_file}", file=sys.stderr)
        return 1

    dut = parse_log(log_path)
    missing = sorted(tag for tag in TAG_TO_PRN if tag not in dut)
    if missing:
        found = sorted(dut.keys())
        print(f"ERROR: missing required ACQ_TUPLE tags: {', '.join(missing)}", file=sys.stderr)
        print(
            f"ERROR: tags found in log ({len(found)}): {', '.join(found) if found else '<none>'}",
            file=sys.stderr,
        )
        return 1

    rows: List[Dict[str, object]] = []
    failed_rows: List[Dict[str, object]] = []
    hard_fail = False
    precomputed_ref = parse_reference_csv(reference_csv) if reference_csv else {}
    reference_source = (
        f"precomputed:{reference_csv}"
        if precomputed_ref
        else "validate_acq_fullspace_prn1"
    )

    for tag, prn in TAG_TO_PRN.items():
        if prn in precomputed_ref:
            ref = precomputed_ref[prn]
        else:
            ref = run_reference_for_prn(input_file=input_file, prn=prn)
        d = dut[tag]
        code_delta = d["code"] - ref["code"]
        dopp_delta = d["dopp"] - ref["dopp"]
        metric_delta = d["metric"] - ref["metric"]
        metric_rel = abs(metric_delta) / max(1.0, float(ref["metric"]))

        row = {
            "tag": tag,
            "prn": prn,
            "dut_success": d["success"],
            "dut_valid": d["valid"],
            "dut_code": d["code"],
            "dut_dopp": d["dopp"],
            "dut_metric": d["metric"],
            "ref_code": ref["code"],
            "ref_dopp": ref["dopp"],
            "ref_metric": ref["metric"],
            "delta_code": code_delta,
            "delta_dopp": dopp_delta,
            "delta_metric": metric_delta,
            "delta_metric_rel": metric_rel,
        }
        fail_reasons: List[str] = []
        if d["success"] != 1:
            fail_reasons.append(f"success={d['success']} (expected 1)")
        if d["valid"] != 1:
            fail_reasons.append(f"valid={d['valid']} (expected 1)")
        if d["prn"] != prn:
            fail_reasons.append(f"prn={d['prn']} (expected {prn})")
        if code_delta != 0:
            fail_reasons.append(
                f"code mismatch: dut={d['code']} ref={ref['code']} delta={code_delta}"
            )
        if dopp_delta != 0:
            fail_reasons.append(
                f"dopp mismatch: dut={d['dopp']} ref={ref['dopp']} delta={dopp_delta}"
            )
        if metric_rel > args.metric_rel_tol:
            fail_reasons.append(
                f"metric mismatch: dut={d['metric']} ref={ref['metric']} "
                f"delta={metric_delta} rel={metric_rel:.6f} tol={args.metric_rel_tol:.6f}"
            )

        row["fail_reasons"] = fail_reasons
        row["pass"] = (
            d["success"] == 1
            and d["valid"] == 1
            and d["prn"] == prn
            and code_delta == 0
            and dopp_delta == 0
            and metric_rel <= args.metric_rel_tol
        )
        if not row["pass"]:
            hard_fail = True
            failed_rows.append(row)
        rows.append(row)

    with report_csv.open("w", encoding="utf-8") as f:
        f.write(
            "tag,prn,dut_success,dut_valid,dut_code,dut_dopp,dut_metric,"
            "ref_code,ref_dopp,ref_metric,delta_code,delta_dopp,delta_metric,delta_metric_rel,pass\n"
        )
        for r in rows:
            f.write(
                f"{r['tag']},{r['prn']},{r['dut_success']},{r['dut_valid']},"
                f"{r['dut_code']},{r['dut_dopp']},{r['dut_metric']},"
                f"{r['ref_code']},{r['ref_dopp']},{r['ref_metric']},"
                f"{r['delta_code']},{r['delta_dopp']},{r['delta_metric']},"
                f"{float(r['delta_metric_rel']):.6f},{int(bool(r['pass']))}\n"
            )

    summary = {
        "log": str(log_path),
        "input_file": str(input_file),
        "reference_source": reference_source,
        "metric_rel_tol": args.metric_rel_tol,
        "total_tags": len(rows),
        "failed_tags": len(failed_rows),
        "rows": rows,
        "pass": not hard_fail,
    }
    with report_json.open("w", encoding="utf-8") as f:
        json.dump(summary, f, indent=2, sort_keys=True)

    if hard_fail:
        print("ACQ tuple GNSS-DSP comparison failed.", file=sys.stderr)
        print(
            f"ERROR: {len(failed_rows)}/{len(rows)} ACQ tuples did not match reference.",
            file=sys.stderr,
        )
        for row in failed_rows:
            tag = row["tag"]
            prn = row["prn"]
            reasons = row["fail_reasons"]
            reason_text = "; ".join(str(r) for r in reasons) if reasons else "unknown mismatch"
            print(f"ERROR: tag={tag} prn={prn}: {reason_text}", file=sys.stderr)
        print(f"ERROR: detailed JSON report: {report_json}", file=sys.stderr)
        print(f"ERROR: detailed CSV report: {report_csv}", file=sys.stderr)
        return 1

    print("ACQ tuple GNSS-DSP comparison passed.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
