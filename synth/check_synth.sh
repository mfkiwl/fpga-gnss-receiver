#!/usr/bin/env bash
set -euo pipefail

if command -v yosys >/dev/null 2>&1; then
  echo "==> Running basic synthesis check with Yosys (SV top)"
  yosys -p 'read_verilog -sv rtl/sv/top.sv; hierarchy -top top; proc; opt; stat'
  echo "Synthesis check passed (Yosys)."
else
  echo "warn: yosys not found. No synthesis check executed."
  echo "Install Yosys or replace this script with your vendor synthesis flow."
fi
