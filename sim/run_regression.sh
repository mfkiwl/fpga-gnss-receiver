#!/usr/bin/env bash
set -euo pipefail

./sim/run_unit_tbs.sh
./sim/run_acq_td_fft_equiv.sh
./sim/run_smoke.sh
