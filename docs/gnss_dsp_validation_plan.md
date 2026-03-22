# GNSS-DSP Validation Augmentation Plan

## Scope

This plan maps tools under `GNSS-DSP-tools/gnsstools` (and related scripts in `GNSS-DSP-tools/`) to concrete augmentation points for:

- `rtl/vhdl/acquisition/*`
- `rtl/vhdl/tracking/*`

Note: the repository path is `rtl/vhdl/...` (not `rt/vhdl/...`).

## Usable GNSS-DSP Tools for GPS L1 C/A

- Acquisition reference:
  - `GNSS-DSP-tools/acquire-gps-l1.py`
- Tracking reference:
  - `GNSS-DSP-tools/track-gps-l1.py`
- C/N0 estimator:
  - `GNSS-DSP-tools/cn0.py`
- PRN/code/correlation primitives:
  - `GNSS-DSP-tools/gnsstools/gps/ca.py`
- Discriminators:
  - `GNSS-DSP-tools/gnsstools/discriminator.py`
- NCO/mixer:
  - `GNSS-DSP-tools/gnsstools/nco.py`

## Augmentation Points (All Places to Use These in Unit TBs)

1. `tb/vhdl/gps_l1_ca_acq_fft_prn_gen_tb.vhd` for `rtl/vhdl/acquisition/gps_l1_ca_acq_fft_prn_gen.vhd`
   - Replace duplicated internal PRN reference logic with external vectors from `gnsstools.gps.ca.ca_code()` / `first_10_chips()` checks.
   - Goal: independent PRN generator evidence.

2. `tb/vhdl/gps_l1_ca_acq_fft_code_gen_tb.vhd` for `rtl/vhdl/acquisition/gps_l1_ca_acq_fft_code_gen.vhd`
   - Generate golden `code_fft` vectors in Python (`ca.code` + NumPy FFT), then compare in TB.
   - Goal: avoid circular validation via RTL package math.

3. `tb/vhdl/gps_l1_ca_acq_fft_mix_fft_tb.vhd` for `rtl/vhdl/acquisition/gps_l1_ca_acq_fft_mix_fft.vhd`
   - Use `gnsstools.nco.mix()` + FFT to produce expected mixed spectra for multiple Doppler bins and sign/saturation corners.
   - Goal: independent carrier wipeoff + FFT verification.

4. `tb/vhdl/gps_l1_ca_acq_fft_corr_tb.vhd` for `rtl/vhdl/acquisition/gps_l1_ca_acq_fft_corr.vhd`
   - Cross-check with GNSS-DSP spectral correlation math (`ifft(C * conj(X))` or lag-0 spectral dot-product equivalent).
   - Goal: independent complex correlation evidence.

5. `tb/vhdl/gps_l1_ca_acq_fft_tb.vhd` for `rtl/vhdl/gps_l1_ca_acq_fft.vhd`
   - Extend beyond completion/success assertions by checking `{PRN, Doppler, code}` vs `acquire-gps-l1.py` over matched search grids.
   - Goal: behavioral correctness of integrated FFT acquisition pipeline.

6. `tb/vhdl/gps_l1_ca_acq_tb.vhd`
   - Use existing `ACQ_TUPLE` logging to compare DUT tuples against GNSS-DSP acquisition outputs on identical captures/windows.
   - Goal: hard evidence artifact (tuple-diff report per run tag).

7. `tb/vhdl/tracking/gps_l1_ca_track_discriminators_tb.vhd` for `rtl/vhdl/tracking/gps_l1_ca_track_discriminators.vhd`
   - Feed prompt/early/late traces derived from `track-gps-l1.py`.
   - Compare PLL/FLL discriminator behavior with `gnsstools.discriminator`.
   - Goal: independent discriminator validation on realistic traces.

8. `tb/vhdl/tracking/gps_l1_ca_track_loop_filters_tb.vhd` for `rtl/vhdl/tracking/gps_l1_ca_track_loop_filters.vhd`
   - Drive realistic error streams from software tracking logs and assert transient/settling behavior (`dopp_o`, FCW command evolution).
   - Goal: dynamic loop behavior evidence, not only single-cycle algebra.

9. `tb/vhdl/tracking/gps_l1_ca_track_power_lock_tb.vhd` for `rtl/vhdl/tracking/gps_l1_ca_track_power_lock.vhd`
   - Compare DUT CN0 trend against `cn0.py` computed on matching tracking windows.
   - Goal: independent lock-quality/CN0 corroboration.

10. `tb/vhdl/tracking/gps_l1_ca_track_lock_state_tb.vhd` for `rtl/vhdl/tracking/gps_l1_ca_track_lock_state.vhd`
    - Replay realistic `{cn0, carrier_metric, dll_err}` sequences from software tracking outputs.
    - Validate state transitions and hysteresis timing under noisy conditions.

11. `tb/vhdl/gps_l1_ca_chan_bank_tb.vhd` for `rtl/vhdl/gps_l1_ca_track_chan.vhd` integration
    - Replace hard-coded acquisition-derived assignment tuples with tuples generated from `acquire-gps-l1.py`.
    - Goal: traceable end-to-end acquisition->tracking lock evidence.

12. `tb/vhdl/gps_l1_ca_chan_bank_nav_store_tb.vhd`
    - Add software-track-derived lock-window/CN0 expected ranges per channel.
    - Goal: stronger evidence at bank/system level.

13. Regression/CI hooks:
    - `sim/run_unit_tbs.sh`
    - `sim/run_regression.sh`
    - `sim/run_acq_td_fft_equiv.sh`
    - `Makefile` targets (`sim-unit`, `sim-regress`, `sim-acq-equiv`)
    - Add GNSS-DSP cross-check stages producing machine-readable artifacts (CSV/JSON + pass/fail summary).

## Evidence Artifacts to Produce

- Acquisition:
  - Per-tag tuple comparison (`prn`, `code`, `dopp`, `metric`) DUT vs GNSS-DSP.
  - Full PRN sweep summary with ranked bins and metric deltas.
- Tracking:
  - Epoch-by-epoch discriminator and loop command deltas.
  - CN0 trend overlays (DUT vs `cn0.py`).
  - Lock-state transition timeline and hysteresis evidence.
- Regression:
  - Version-stamped reports tied to commit SHA and input file metadata.

## Practical Run Notes (Observed)

- `acquire-gps-l1.py` currently fails for 2 MSPS input due to fixed FIR cutoff setting near/above Nyquist in that mode.
- It runs successfully on the 4 MSPS capture (`2013_04_04_GNSS_SIGNAL_at_CTTC_SPAIN.dat`).
- `track-gps-l1.py` and `cn0.py` run successfully on the 4 MSPS file and produce usable per-epoch outputs.
- `spectrum.py`/`squaring.py` consume int8 IQ (`gnsstools/io.py`), so they are diagnostic-only unless format adapters are added for cs16 replay.

## Immediate Implementation Sequence

1. Add Python generators that emit golden CSV vectors for acquisition sub-blocks and tracking sub-block metrics.
2. Extend existing TBs to load/consume these vectors and assert tolerance-bounded equivalence.
3. Add regression targets that run GNSS-DSP generation + NVC simulation + diff checks.
4. Store artifacts under `sim/reports/` with commit/file provenance.

## Revision Metadata

- Main repo commit during analysis: `09b1783`
- `GNSS-DSP-tools` commit during analysis: `17c664b`
- Date: 2026-03-21

