# GSD HDL Preferences

Always run lint before simulation.

Do not change `vhdl.files` or `sv.f` unless the task explicitly requires it.

Treat warnings related to latches, multiple drivers, width mismatch, and uninitialized signals as high priority.

For VHDL package/interface changes, update dependent units and rerun full compile.

For SystemVerilog modules, preserve `always_ff`/`always_comb` usage where applicable.

Use tool output as ground truth over assumptions.
