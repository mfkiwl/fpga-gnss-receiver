SHELL := /usr/bin/env bash

.PHONY: help lint-vhdl lint-sv sim-smoke sim-regress synth-check waves

help:
	@echo "Targets:"
	@echo "  make lint-vhdl    - Run VHDL checks with GHDL"
	@echo "  make lint-sv      - Run SystemVerilog checks with slang/verilator"
	@echo "  make sim-smoke    - Run smoke simulations"
	@echo "  make sim-regress  - Run regression suite"
	@echo "  make synth-check  - Run synthesis sanity check"
	@echo "  make waves        - Print waveform artifact paths"

lint-vhdl:
	@./lint/lint_vhdl.sh

lint-sv:
	@./lint/lint_sv.sh

sim-smoke:
	@./sim/run_smoke.sh

sim-regress:
	@./sim/run_regression.sh

synth-check:
	@./synth/check_synth.sh

waves:
	@echo "VHDL waveform: sim/fifo_tb.vcd"
	@echo "SV waveform (if enabled by simulator flags): sim/obj_dir/"
