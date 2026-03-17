#!/usr/bin/env bash
set -euo pipefail

NVC_STDERR_LEVEL="${NVC_STDERR_LEVEL:-none}"
ACQ_EQ_STOP_TIME="${ACQ_EQ_STOP_TIME:-3ms}"
ACQ_EQ_METRIC_TOL="${ACQ_EQ_METRIC_TOL:-4}"
ACQ_EQ_RUN_LINT="${ACQ_EQ_RUN_LINT:-1}"

if [[ "${ACQ_EQ_RUN_LINT}" == "1" || "${ACQ_EQ_RUN_LINT}" == "true" || "${ACQ_EQ_RUN_LINT}" == "TRUE" ]]; then
  ./lint/lint_vhdl.sh
fi

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
  -e
  -gG_DUT_ACQ_IMPL_FFT=true
  gps_l1_ca_acq_tb
  -r
  gps_l1_ca_acq_tb
  --stop-time="${ACQ_EQ_STOP_TIME}"
)
"${cmd_fft[@]}" 2>&1 | tee "${tmp_fft_log}"

echo "==> Comparing ACQ_TUPLE logs (TD vs FFT)"
python3 - "${tmp_td_log}" "${tmp_fft_log}" "${ACQ_EQ_METRIC_TOL}" <<'PY'
import re
import sys
from pathlib import Path

_, td_path, fft_path, metric_tol_s = sys.argv
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
    "run1_zero_thresh",
    "run2_max_thresh",
    "run3_realistic_thresh",
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
ratio_ref_tag = "run1_zero_thresh"
td_ref_metric = td[ratio_ref_tag]["metric"]
fft_ref_metric = fft[ratio_ref_tag]["metric"]
metric_ratio = 1.0
if td_ref_metric > 0 and fft_ref_metric > 0:
    metric_ratio = td_ref_metric / fft_ref_metric

for tag in sorted(required):
    a = td[tag]
    b = fft[tag]
    for field in ("success", "valid", "prn", "code", "dopp"):
        if a[field] != b[field]:
            ok = False
            print(
                f"ERROR: {tag} mismatch {field}: td={a[field]} fft={b[field]}",
                file=sys.stderr,
            )
    if a["metric"] == 0 or b["metric"] == 0:
        if abs(a["metric"] - b["metric"]) > metric_tol:
            ok = False
            print(
                f"ERROR: {tag} metric mismatch exceeds tol {metric_tol}: "
                f"td={a['metric']} fft={b['metric']}",
                file=sys.stderr,
            )
    else:
        metric_err = abs(a["metric"] - (b["metric"] * metric_ratio))
        if metric_err > metric_tol:
            ok = False
            print(
                f"ERROR: {tag} metric mismatch exceeds tol {metric_tol} after "
                f"ratio normalization ({metric_ratio:.6f}): "
                f"td={a['metric']} fft={b['metric']}",
                file=sys.stderr,
            )

if not ok:
    sys.exit(1)

print(
    f"ACQ TD/FFT equivalence passed for {len(required)} tags "
    f"(metric_tol={metric_tol}, metric_ratio={metric_ratio:.6f})."
)
PY

echo "Acquisition TD/FFT equivalence check passed."
