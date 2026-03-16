# Phase 3 Verification Notes

## Commands
- `make phase3-eval`
- `make phase3-gate`

`phase3-eval` always prints the metric table.
`phase3-gate` returns non-zero when one or more primary thresholds fail.

## Pass/Fail Tables

### GNSS-SDR Alignment

| Metric | Target | Current | Status |
| --- | --- | --- | --- |
| First-fix presence | both have >=1 fix | FAIL (sim=0, ref=13) | FAIL |
| Horizontal RMS error | <= 25 m | N/A (no paired epochs) | FAIL |
| Vertical RMS error | <= 40 m | N/A (no paired epochs) | FAIL |
| 3D error p95 | <= 75 m | N/A (no paired epochs) | FAIL |
| Static jitter RMS | <= 15 m | N/A (no fixes) | FAIL |
| Min observations used | >= 4 | N/A (no fixes) | FAIL |

### Block De-Scaffolding

| Block | Pass Condition | Current Status |
| --- | --- | --- |
| Acquisition | Correlation-based PRN/code/doppler output + runtime accumulation control | PASS (explicit code/doppler bin search) |
| Tracking | DLL/FLL/PLL discriminator-driven lock | PASS (FLL pull-in + PLL lock mode + metric-state lock score) |
| NAV decode | Word/parity/subframe decode + ephemeris fields | PASS functional; structural split into dedicated sub-entities still pending |
| Observables | Timing-consistent pseudorange/rate + corrections + metadata outputs | PASS (rate/carrier/CN0/lock-quality surfaced) |
| PVT | Weighted iterative LS + residual gating + solution quality outputs | PASS (RMS residual + DOP approximations on interface) |

## Notes
- This file is the Phase 3 scoreboard companion to `Phase-3-Plans-and-Goal.md`.
- The authoritative numeric values are produced by `sim/phase3_compare.py` from simulation logs and `tb/txt/expected_output.txt`.
- Current values above were produced on 2026-03-16 with `make phase3-eval` after acquisition/tracking/observables/PVT interface upgrades.
- Pre-ephemeris fallback satellite geometry has been removed from reset behavior. Alignment currently fails because no end-to-end fixes are produced in the smoke run window.
