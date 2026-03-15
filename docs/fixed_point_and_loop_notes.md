# Phase 1 Fixed-Point and Loop Notes

## Input and Internal Types
- Input sample format: signed `cs16` (`I[15:0]`, `Q[15:0]`)
- Prompt accumulators: signed 24-bit in tracking block
- Integrator utility output: signed 32-bit
- Acquisition metric: unsigned 32-bit

## NCO Notes
- Code NCO is fractional and sample-driven to support `2 MSPS` with non-integer samples/chip.
- Code FCW constant is currently:
  - `C_CODE_NCO_FCW = 0x82EF9DB2`
- This represents a first-order fixed-point step for `1.023 Mcps` behavior at `2 MSPS`.

## Loop Notes
- PLL/DLL gains and lock threshold are exposed in control registers now.
- In this Phase 1 scaffold, gain values are placeholders for forward compatibility.
- Full loop filter tuning and discriminator refinement are planned for follow-up work.
