#!/usr/bin/env bash
set -euo pipefail

NVC_STDERR_LEVEL="${NVC_STDERR_LEVEL:-none}"
GNSS_VECTOR_PROFILE="${GNSS_VECTOR_PROFILE:-regress}"
GNSS_CROSSCHECK_RUN_LINT="${GNSS_CROSSCHECK_RUN_LINT:-1}"
GNSS_CROSSCHECK_STOP_TIME="${GNSS_CROSSCHECK_STOP_TIME:-3ms}"
GNSS_CROSSCHECK_LOG="${GNSS_CROSSCHECK_LOG:-sim/reports/acq_gnss_dsp_tb.log}"
GNSS_CROSSCHECK_INPUT_FILE="${GNSS_CROSSCHECK_INPUT_FILE:-2013_04_04_GNSS_SIGNAL_at_CTTC_SPAIN/2013_04_04_GNSS_SIGNAL_at_CTTC_SPAIN_2msps.dat}"
GNSS_CROSSCHECK_FILE_SAMPLE_RATE_SPS="${GNSS_CROSSCHECK_FILE_SAMPLE_RATE_SPS:-2000000}"
GNSS_CROSSCHECK_DUT_SAMPLE_RATE_SPS="${GNSS_CROSSCHECK_DUT_SAMPLE_RATE_SPS:-2000000}"
GNSS_CROSSCHECK_ACQ_IMPL_FFT="${GNSS_CROSSCHECK_ACQ_IMPL_FFT:-true}"
GNSS_CROSSCHECK_METRIC_REL_TOL="${GNSS_CROSSCHECK_METRIC_REL_TOL:-0.35}"
GNSS_CROSSCHECK_REQUIRE_DATA="${GNSS_CROSSCHECK_REQUIRE_DATA:-0}"
GNSS_CROSSCHECK_HEAP="${GNSS_CROSSCHECK_HEAP:-512m}"
GNSS_CROSSCHECK_STRICT="${GNSS_CROSSCHECK_STRICT:-1}"

mkdir -p "$(dirname "${GNSS_CROSSCHECK_LOG}")"

python3 sim/gen_gnss_dsp_vectors.py --profile "${GNSS_VECTOR_PROFILE}" --derive-assignments

if [[ ! -f "${GNSS_CROSSCHECK_INPUT_FILE}" ]]; then
  if [[ "${GNSS_CROSSCHECK_REQUIRE_DATA}" == "1" || "${GNSS_CROSSCHECK_REQUIRE_DATA}" == "true" || "${GNSS_CROSSCHECK_REQUIRE_DATA}" == "TRUE" ]]; then
    echo "error: GNSS cross-check input file not found: ${GNSS_CROSSCHECK_INPUT_FILE}"
    exit 1
  fi
  echo "warning: GNSS cross-check input file not found, skipping file-based tuple comparison."
  exit 0
fi

if [[ "${GNSS_CROSSCHECK_RUN_LINT}" == "1" || "${GNSS_CROSSCHECK_RUN_LINT}" == "true" || "${GNSS_CROSSCHECK_RUN_LINT}" == "TRUE" ]]; then
  ./lint/lint_vhdl.sh
fi

if ! command -v nvc >/dev/null 2>&1; then
  echo "error: nvc not found. Cannot run GNSS-DSP cross-check."
  exit 1
fi

echo "==> Running gps_l1_ca_acq_tb reduced file profile (GNSS-DSP cross-check)"
nvc_cmd=(
  nvc --std=2008
  --stderr="${NVC_STDERR_LEVEL}"
  -H "${GNSS_CROSSCHECK_HEAP}"
  -e
  -gG_USE_FILE_INPUT=true
  -gG_INPUT_FILE="${GNSS_CROSSCHECK_INPUT_FILE}"
  -gG_FILE_SAMPLE_RATE_SPS="${GNSS_CROSSCHECK_FILE_SAMPLE_RATE_SPS}"
  -gG_DUT_SAMPLE_RATE_SPS="${GNSS_CROSSCHECK_DUT_SAMPLE_RATE_SPS}"
  -gG_DUT_ACQ_IMPL_FFT="${GNSS_CROSSCHECK_ACQ_IMPL_FFT}"
  -gG_ENABLE_FULL_PRN_SWEEP=false
  gps_l1_ca_acq_tb
  -r
  gps_l1_ca_acq_tb
  --stop-time="${GNSS_CROSSCHECK_STOP_TIME}"
)

"${nvc_cmd[@]}" 2>&1 | tee "${GNSS_CROSSCHECK_LOG}"

echo "==> Comparing ACQ_TUPLE tags against GNSS-DSP reference"
if python3 sim/compare_acq_tuples_gnss_dsp.py \
  --log "${GNSS_CROSSCHECK_LOG}" \
  --input-file "${GNSS_CROSSCHECK_INPUT_FILE}" \
  --report-json sim/reports/acq_tuple_diff.json \
  --report-csv sim/reports/acq_tuple_diff.csv \
  --reference-csv sim/reports/acq_assignment_reference.csv \
  --metric-rel-tol "${GNSS_CROSSCHECK_METRIC_REL_TOL}"; then
  echo "GNSS-DSP cross-check passed."
else
  if [[ "${GNSS_CROSSCHECK_STRICT}" == "1" || "${GNSS_CROSSCHECK_STRICT}" == "true" || "${GNSS_CROSSCHECK_STRICT}" == "TRUE" ]]; then
    echo "error: GNSS-DSP tuple comparison failed in strict mode."
    echo "error: see sim/reports/acq_tuple_diff.json and sim/reports/acq_tuple_diff.csv for full details."
    exit 1
  fi
  echo "warning: GNSS-DSP tuple comparison failed (non-strict mode); report saved to sim/reports/acq_tuple_diff.{json,csv}"
fi
