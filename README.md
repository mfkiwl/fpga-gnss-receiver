# HDL Starter Kit (GSD-Driven)

This repository is a concrete starter implementation of the workflow described in `Intro.md`:

- GSD-2 as project manager/orchestrator
- HDL tools as ground truth (GHDL, slang, Verilator, optional synthesis)
- Mechanical verification commands through scripts and Make targets

## Layout

```text
rtl/
  vhdl/
  sv/
tb/
  vhdl/
  sv/
sim/
  scripts/
lint/
  scripts/
synth/
constraints/
docs/
```

## Canonical Commands

```bash
make lint-vhdl
make lint-sv
make sim-smoke
make sim-regress
make synth-check
make waves
```

See `docs/hdl-workflow.md` for details.
