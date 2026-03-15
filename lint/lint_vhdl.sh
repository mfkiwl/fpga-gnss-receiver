#!/usr/bin/env bash
set -euo pipefail

if ! command -v ghdl >/dev/null 2>&1; then
  echo "error: ghdl not found. Install GHDL to run VHDL checks."
  exit 1
fi

if [[ ! -f vhdl.files ]]; then
  echo "error: vhdl.files not found."
  exit 1
fi

mapfile -t vhdl_sources < <(grep -vE '^\s*(#|$)' vhdl.files)

if [[ ${#vhdl_sources[@]} -eq 0 ]]; then
  echo "error: vhdl.files has no source entries."
  exit 1
fi

echo "==> GHDL analyze"
ghdl -a --std=08 "${vhdl_sources[@]}"

echo "==> GHDL elaborate fifo_tb"
ghdl -e --std=08 fifo_tb

echo "VHDL lint/check passed."
