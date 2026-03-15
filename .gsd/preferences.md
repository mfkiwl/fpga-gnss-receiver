# GSD HDL Preferences

Always run lint before simulation.

Do not change `vhdl.files` unless the task explicitly requires it.

Treat warnings related to latches, multiple drivers, width mismatch, and uninitialized signals as high priority.

For VHDL package/interface changes, update dependent units and rerun full compile.

Use tool output as ground truth over assumptions.
