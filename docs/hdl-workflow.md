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

- VHDL TB top: `fifo_tb`
- SystemVerilog TB top: `top_tb`

## Verification Source of Truth

- VHDL lint/check: `make lint-vhdl`
- SV lint/check: `make lint-sv`
- Smoke simulations: `make sim-smoke`
- Basic regression: `make sim-regress`

## Definition of Done

- `make lint-vhdl` passes
- `make lint-sv` passes
- `make sim-smoke` passes
- No new latch/multi-driver/width/uninitialized warnings introduced
- Any interface changes are reflected in docs and testbenches
