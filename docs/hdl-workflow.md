# HDL Workflow

## Source Locations

- VHDL RTL: `rtl/vhdl/`
- SystemVerilog RTL: `rtl/sv/`
- VHDL testbenches: `tb/vhdl/`
- SystemVerilog testbenches: `tb/sv/`
- Lint scripts: `lint/`
- Simulation scripts: `sim/`
- Synthesis check script: `synth/`

## Compile Order

- VHDL compile order is defined in `vhdl.files`.
- SystemVerilog file list is defined in `sv.f`.
- The scripts consume these files directly and should be treated as source of truth.

## Top Units

- VHDL TB top: `gps_l1_ca_phase1_tb`
- SystemVerilog TB top: `top_tb`

## Verification Source of Truth

- VHDL lint/check: `make lint-vhdl`
- SV lint/check: `make lint-sv`
- Smoke simulations: `make sim-smoke`
- Basic regression: `make sim-regress`

Supporting docs:
- `docs/phase1_register_map.md`
- `docs/packet_definition.md`
- `docs/fixed_point_and_loop_notes.md`
- `docs/phase1_verification_notes.md`

## Definition of Done

- `make lint-vhdl` passes
- `make lint-sv` passes
- `make sim-smoke` passes
- No new latch/multi-driver/width/uninitialized warnings introduced
- Any interface changes are reflected in docs and testbenches

## Phase 1 Module Map

- Top integration: `gps_l1_ca_phase1_top`
- Shared package: `gps_l1_ca_pkg`
- Control/status: `gps_l1_ca_ctrl`
- Sample ingress: `axis_sample_ingress`
- Shared acquisition: `gps_l1_ca_acq`
- Tracking channel: `gps_l1_ca_track_chan`
- Navigation bit extraction: `gps_l1_ca_nav`
- Report packing: `gps_l1_ca_report`
- UART transport: `uart_tx`
