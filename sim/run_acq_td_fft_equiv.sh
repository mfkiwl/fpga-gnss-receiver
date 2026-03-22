#!/usr/bin/env bash
set -euo pipefail

NVC_STDERR_LEVEL="${NVC_STDERR_LEVEL:-none}"
ACQ_EQ_STOP_TIME="${ACQ_EQ_STOP_TIME:-3ms}"
ACQ_EQ_METRIC_TOL="${ACQ_EQ_METRIC_TOL:-4}"
ACQ_EQ_RUN_LINT="${ACQ_EQ_RUN_LINT:-1}"
ACQ_EQ_HEAP="${ACQ_EQ_HEAP:-512m}"
ACQ_EQ_REPORT_JSON="${ACQ_EQ_REPORT_JSON:-sim/reports/acq_td_fft_equiv.json}"
ACQ_EQ_REPORT_CSV="${ACQ_EQ_REPORT_CSV:-sim/reports/acq_td_fft_equiv.csv}"

if [[ "${ACQ_EQ_RUN_LINT}" == "1" || "${ACQ_EQ_RUN_LINT}" == "true" || "${ACQ_EQ_RUN_LINT}" == "TRUE" ]]; then
  ./lint/lint_vhdl.sh
fi

mkdir -p "$(dirname "${ACQ_EQ_REPORT_JSON}")" "$(dirname "${ACQ_EQ_REPORT_CSV}")"

if ! command -v nvc >/dev/null 2>&1; then
  echo "error: nvc not found. Cannot run acquisition equivalence check."
  exit 1
fi

tmp_td_log="$(mktemp)"
tmp_fft_log="$(mktemp)"
cleanup() {
  rm -f "${tmp_td_log}" "${tmp_fft_log}"
}
trap cleanup EXIT

echo "==> Running gps_l1_ca_acq_tb (time-domain mode)"
cmd_td=(
  nvc --std=2008
  --stderr="${NVC_STDERR_LEVEL}"
  -H "${ACQ_EQ_HEAP}"
  -e
  -gG_DUT_ACQ_IMPL_FFT=false
  gps_l1_ca_acq_tb
  -r
  gps_l1_ca_acq_tb
  --stop-time="${ACQ_EQ_STOP_TIME}"
)
"${cmd_td[@]}" 2>&1 | tee "${tmp_td_log}"

echo "==> Running gps_l1_ca_acq_tb (FFT mode)"
cmd_fft=(
  nvc --std=2008
  --stderr="${NVC_STDERR_LEVEL}"
  -H "${ACQ_EQ_HEAP}"
  -e
  -gG_DUT_ACQ_IMPL_FFT=true
  gps_l1_ca_acq_tb
  -r
  gps_l1_ca_acq_tb
  --stop-time="${ACQ_EQ_STOP_TIME}"
)
"${cmd_fft[@]}" 2>&1 | tee "${tmp_fft_log}"

echo "==> Comparing ACQ_TUPLE logs (TD vs FFT)"
python3 - "${tmp_td_log}" "${tmp_fft_log}" "${ACQ_EQ_METRIC_TOL}" "${ACQ_EQ_REPORT_JSON}" "${ACQ_EQ_REPORT_CSV}" <<'PY'
import re
import sys
import json
from pathlib import Path

_, td_path, fft_path, metric_tol_s, report_json_path, report_csv_path = sys.argv
metric_tol = int(metric_tol_s)
pat = re.compile(
    r"ACQ_TUPLE\s+tag=(\S+)\s+success='([01])'\s+valid='([01])'\s+"
    r"prn=([-0-9]+)\s+code=([-0-9]+)\s+dopp=([-0-9]+)\s+metric=([-0-9]+)"
)

def parse(path: Path):
    out = {}
    for line in path.read_text(encoding="utf-8", errors="ignore").splitlines():
      m = pat.search(line)
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

td = parse(Path(td_path))
fft = parse(Path(fft_path))
required = {
    "run4_dopp_inversion",
    "run5_no_signal_a",
    "run6_no_signal_b",
}

missing_td = sorted(required - td.keys())
missing_fft = sorted(required - fft.keys())
if missing_td:
    print("ERROR: TD run missing tags:", ", ".join(missing_td), file=sys.stderr)
    sys.exit(1)
if missing_fft:
    print("ERROR: FFT run missing tags:", ", ".join(missing_fft), file=sys.stderr)
    sys.exit(1)

ok = True
ratio_ref_tag = "run4_dopp_inversion"
td_ref_metric = td[ratio_ref_tag]["metric"]
fft_ref_metric = fft[ratio_ref_tag]["metric"]
metric_ratio = 1.0
if td_ref_metric > 0 and fft_ref_metric > 0:
    metric_ratio = td_ref_metric / fft_ref_metric

rows = []
for tag in sorted(required):
    a = td[tag]
    b = fft[tag]
    row = {
        "tag": tag,
        "td": a,
        "fft": b,
        "pass": True,
        "metric_error": 0.0,
    }
    for field in ("success", "valid", "prn", "code", "dopp"):
        if a[field] != b[field]:
            ok = False
            row["pass"] = False
            print(
                f"ERROR: {tag} mismatch {field}: td={a[field]} fft={b[field]}",
                file=sys.stderr,
            )
    if a["metric"] == 0 or b["metric"] == 0:
        metric_err = abs(a["metric"] - b["metric"])
        row["metric_error"] = float(metric_err)
        if metric_err > metric_tol:
            ok = False
            row["pass"] = False
            print(
                f"ERROR: {tag} metric mismatch exceeds tol {metric_tol}: "
                f"td={a['metric']} fft={b['metric']}",
                file=sys.stderr,
            )
    else:
        metric_err = abs(a["metric"] - (b["metric"] * metric_ratio))
        row["metric_error"] = float(metric_err)
        if metric_err > metric_tol:
            ok = False
            row["pass"] = False
            print(
                f"ERROR: {tag} metric mismatch exceeds tol {metric_tol} after "
                f"ratio normalization ({metric_ratio:.6f}): "
                f"td={a['metric']} fft={b['metric']}",
                file=sys.stderr,
            )
    rows.append(row)

summary = {
    "metric_tol": metric_tol,
    "metric_ratio": metric_ratio,
    "required_tags": sorted(required),
    "pass": ok,
    "rows": rows,
}
Path(report_json_path).write_text(json.dumps(summary, indent=2, sort_keys=True), encoding="utf-8")

with Path(report_csv_path).open("w", encoding="utf-8") as fp:
    fp.write("tag,td_success,fft_success,td_valid,fft_valid,td_prn,fft_prn,td_code,fft_code,td_dopp,fft_dopp,td_metric,fft_metric,metric_error,pass\n")
    for row in rows:
        tag = row["tag"]
        td_v = row["td"]
        fft_v = row["fft"]
        fp.write(
            f"{tag},{td_v['success']},{fft_v['success']},{td_v['valid']},{fft_v['valid']},"
            f"{td_v['prn']},{fft_v['prn']},{td_v['code']},{fft_v['code']},{td_v['dopp']},{fft_v['dopp']},"
            f"{td_v['metric']},{fft_v['metric']},{row['metric_error']:.6f},{int(bool(row['pass']))}\n"
        )

if not ok:
    sys.exit(1)

print(
    f"ACQ TD/FFT equivalence passed for {len(required)} tags "
    f"(metric_tol={metric_tol}, metric_ratio={metric_ratio:.6f})."
)
PY

echo "Acquisition TD/FFT equivalence check passed."
