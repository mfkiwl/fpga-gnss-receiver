#!/usr/bin/env bash
set -euo pipefail

if [[ ! -f sv.f ]]; then
  echo "error: sv.f not found."
  exit 1
fi

mapfile -t sv_sources < <(grep -vE '^\s*(#|$)' sv.f)

if [[ ${#sv_sources[@]} -eq 0 ]]; then
  echo "error: sv.f has no source entries."
  exit 1
fi

if command -v slang >/dev/null 2>&1; then
  echo "==> slang semantic checks"
  slang --single-unit "${sv_sources[@]}"
else
  echo "warn: slang not found; skipping slang checks."
fi

if command -v verilator >/dev/null 2>&1; then
  echo "==> verilator lint"
  verilator --lint-only -Wall "${sv_sources[@]}"
else
  echo "error: verilator not found. Install Verilator for SV lint checks."
  exit 1
fi

echo "SystemVerilog lint/check passed."
