# Phase 1 Verification Notes

## Implemented Verification Hooks
- Unit-oriented reusable blocks are separated (`nco_phase_accum`, `ca_prn_gen`, `integrate_dump`, RAM template).
- Block-level flow exists for ingress, acquisition, tracking, nav-bit extraction, and reporting.
- End-to-end VHDL testbench: `tb/vhdl/gps_l1_ca_phase1_tb.vhd`.

## Smoke Flow
- `make lint-vhdl`
- `make sim-smoke`

VHDL smoke sim target:
- `gps_l1_ca_phase1_tb`
- FST output: `sim/gps_l1_ca_phase1_tb.fst`

## Current Environment Limitation
- Full smoke flow may still depend on local toolchain availability.

## Expected Functional Signals in Sim
- Acquisition transitions to done/success with configured low threshold.
- Tracking transitions `IDLE -> PULLIN -> LOCKED`.
- Nav block emits periodic `nav_valid` with `nav_bit`.
- UART path emits 16-byte status packets.
