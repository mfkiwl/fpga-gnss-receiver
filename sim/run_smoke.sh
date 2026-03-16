#!/usr/bin/env bash
set -euo pipefail

VHDL_TB_TOP="${VHDL_TB_TOP:-gps_l1_ca_phase2_tb}"
NVC_STDERR_LEVEL="${NVC_STDERR_LEVEL:-none}"
NVC_STOP_TIME="${NVC_STOP_TIME:-40ms}"
NVC_WAVE_FILE="${NVC_WAVE_FILE:-sim/gps_l1_ca_phase2_tb.fst}"
TB_GENERIC_ARGS="${TB_GENERIC_ARGS:-}"
FAST_MODE="${FAST_MODE:-0}"
NVC_ENABLE_WAVE="${NVC_ENABLE_WAVE:-1}"

./lint/lint_vhdl.sh

if command -v nvc >/dev/null 2>&1; then
  echo "==> Running VHDL smoke simulation"
  echo "    NVC stderr level: ${NVC_STDERR_LEVEL}"
  if [[ -n "${TB_GENERIC_ARGS}" ]]; then
    # Optional, space-delimited nvc generic args such as:
    # TB_GENERIC_ARGS="-gG_MAX_FILE_SAMPLES=50000"
    read -r -a tb_generic_argv <<< "${TB_GENERIC_ARGS}"
  else
    tb_generic_argv=()
  fi
  if [[ "${FAST_MODE}" == "1" || "${FAST_MODE}" == "true" || "${FAST_MODE}" == "TRUE" ]]; then
    echo "    FAST_MODE enabled (no wave dump, reduced TB work)"
    if [[ "${TB_GENERIC_ARGS}" != *"G_FAST_MODE"* ]]; then
      tb_generic_argv+=("-gG_FAST_MODE=true")
    fi
  fi

  wave_dump_enabled=1
  if [[ "${FAST_MODE}" == "1" || "${FAST_MODE}" == "true" || "${FAST_MODE}" == "TRUE" ]]; then
    wave_dump_enabled=0
  elif [[ "${NVC_ENABLE_WAVE}" == "0" || "${NVC_ENABLE_WAVE}" == "false" || "${NVC_ENABLE_WAVE}" == "FALSE" ]]; then
    wave_dump_enabled=0
  fi

  if [[ "${TB_GENERIC_ARGS}" != *"G_ENABLE_WAVE_DUMP"* ]]; then
    if [[ "${wave_dump_enabled}" == "1" ]]; then
      tb_generic_argv+=("-gG_ENABLE_WAVE_DUMP=true")
    else
      tb_generic_argv+=("-gG_ENABLE_WAVE_DUMP=false")
    fi
  fi

  if [[ ${#tb_generic_argv[@]} -gt 0 ]]; then
    nvc_cmd=(
      nvc --std=2008
      --stderr="${NVC_STDERR_LEVEL}"
      -e
      "${tb_generic_argv[@]}"
      "${VHDL_TB_TOP}"
      -r
      "${VHDL_TB_TOP}"
      --stop-time="${NVC_STOP_TIME}"
    )
  else
    nvc_cmd=(
      nvc --std=2008
      --stderr="${NVC_STDERR_LEVEL}"
      -r
      "${VHDL_TB_TOP}"
      --stop-time="${NVC_STOP_TIME}"
    )
  fi

  if [[ "${wave_dump_enabled}" == "1" ]]; then
    nvc_cmd+=(--wave="${NVC_WAVE_FILE}")
  else
    echo "    Wave dump disabled."
  fi

  "${nvc_cmd[@]}"
else
  echo "error: nvc not found. Cannot run VHDL smoke simulation."
  exit 1
fi

echo "VHDL smoke simulation passed."
