#!/usr/bin/env bash
set -euo pipefail

./sim/run_unit_tbs.sh
ACQ_EQ_RUN_LINT=0 ./sim/run_acq_td_fft_equiv.sh
GNSS_CROSSCHECK_RUN_LINT=0 ./sim/run_gnss_dsp_crosscheck.sh
./sim/run_smoke.sh
