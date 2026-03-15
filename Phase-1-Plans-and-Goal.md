# Phase 1 Plans and Goal

## 1. Phase 1 Goal

The goal of Phase 1 is to build a first working HDL receiver for `GPS L1 C/A` using a fixed `2 MSPS` complex input stream and to do so in a way that is fully aligned with [Assumptions.md](/home/rigo/test/Assumptions.md) and [Outline.md](/home/rigo/test/Outline.md).

Phase 1 should prove the core receiver chain end to end:

- accept a `cs16` I/Q stream at `2 MSPS`
- acquire at least one GPS L1 C/A satellite
- hand off acquisition results to a tracking channel
- maintain code and carrier lock
- recover navigation bits
- emit basic receiver outputs over a UART-oriented output path

The design should be small enough to implement and verify quickly, but structured so that later phases can add:

- more tracking channels
- a proper channel manager
- additional observables logic
- additional constellations and bands
- more complete telemetry decode
- eventual in-FPGA navigation or PVT functions if desired

## 2. Phase 1 Compliance Targets

### 2.1 Required Compliance with Assumptions.md
- No DMA is used.
- All implemented signal processing is inside the FPGA.
- The input is assumed to be a ready-to-use `cs16` complex stream at `2 MSPS`.
- No front-end filtering or decimation is included in Phase 1.
- Control and status are exposed through the assumed simple control bus.
- Datapath-style interfaces use AXI-Stream where practical.
- Implementation is in VHDL.
- Coding style should infer Xilinx-friendly RAM/DSP structures where practical.
- Output products are sent through a UART path with a packet format to be defined later.

### 2.2 Required Compliance with Outline.md
- Preserve the architectural split between:
  - signal ingress
  - acquisition
  - tracking
  - telemetry decode
  - output products
- Keep clear boundaries between shared blocks and per-channel blocks.
- Build reusable channel-oriented components even if Phase 1 instantiates only one tracking channel.
- Keep room for future observables and multi-channel expansion.

## 3. Phase 1 Scope

### 3.1 In Scope
- Single-band support: `L1`
- Single-signal support: `GPS L1 C/A`
- Fixed input sample rate: `2 MSPS`
- One shared acquisition engine
- One tracking channel
- Basic navigation bit extraction
- Basic status and measurement output over UART
- Simple control/status register map

### 3.2 Explicitly Out of Scope
- Front-end filtering
- Decimation or resampling stages
- Multi-constellation support
- Multi-band support
- DMA
- External processor offload
- Full PVT solution
- Multi-satellite navigation solution
- Advanced assisted-GNSS features

## 4. Functional Interpretation of the 2 MSPS Requirement

### 4.1 Input Assumption
- The input is a complex baseband or suitably conditioned low-IF stream already appropriate for GPS L1 C/A processing.
- The FPGA receives one valid complex sample at `2,000,000 samples/s`.
- Each sample contains:
  - `I[15:0]`
  - `Q[15:0]`

### 4.2 Important Design Consequence
- The GPS C/A code rate is `1.023 Mcps`, which is not an integer divisor of `2 MSPS`.
- Therefore, the receiver must not rely on a fixed integer samples-per-chip representation.
- Instead, the design should use a fractional code NCO and generate the local code replica at sample time.

### 4.3 Why This Is the Right Phase 1 Choice
- It avoids adding a resampler, which would conflict with the current assumptions and add complexity.
- It keeps the code-tracking and acquisition architecture compatible with later sample-rate changes.
- It matches the long-term architecture in `Outline.md`, where code/carrier generation is already channel-local and scalable.

## 5. Proposed Phase 1 Architecture

### 5.1 Top-Level Block Diagram
- `sample ingress`
- `control/status block`
- `acquisition engine`
- `tracking channel`
- `nav-bit / telemetry block`
- `measurement and status formatter`
- `UART packet transmitter`

### 5.2 Recommended Top-Level VHDL Partition
- `gps_l1_ca_phase1_top`
  - top-level integration
- `gps_l1_ca_pkg`
  - shared constants, types, record definitions
- `gps_l1_ca_ctrl`
  - control/status register bank on the assumed control bus
- `axis_sample_ingress`
  - adapts incoming `cs16` samples into an internal AXI-Stream form
- `gps_l1_ca_acq`
  - shared acquisition engine
- `gps_l1_ca_track_chan`
  - one tracking channel
- `gps_l1_ca_nav`
  - nav-bit extraction and basic frame sync hooks
- `gps_l1_ca_report`
  - output record packing for UART transport
- `uart_tx`
  - serial output block

## 6. Internal Interface Strategy

### 6.1 Control Plane
- Use the assumed simple control bus exactly as documented in `Assumptions.md`.
- Implement a register bank for:
  - start/stop control
  - acquisition configuration
  - PRN selection or PRN search enable mask
  - tracking loop parameters
  - status and interrupt flags

### 6.2 Datapath Plane
- Use AXI-Stream for sample and result movement where practical.
- Suggested internal streams:
  - input sample stream
  - acquisition result stream
  - tracking measurement stream
  - telemetry/status report stream

### 6.3 Future-Proofing Rule
- Even if there is only one tracking channel in Phase 1, define the output of acquisition as if it were feeding a future channel allocator.
- Even if UART is the only current egress, define internal report records so later phases can route the same content to observables, debug, or PVT blocks.

## 7. Detailed Block Plan

### 7.1 Sample Ingress
- Accept `cs16` complex samples.
- Convert them into an internal signed format suitable for DSP inference.
- Attach a sample-valid handshake using AXI-Stream semantics.
- Maintain a free-running sample counter for timing and debug.

Phase 1 note:
- No filtering, DC removal, AGC, or decimation is inserted here.

### 7.2 Shared Acquisition Engine
- Implement one acquisition engine shared across the design.
- Buffer `1 ms` worth of samples:
  - `2,000` complex samples per block
- Search over:
  - PRN space
  - Doppler bins
  - code phase offsets
- Produce a best-hit result containing:
  - detected PRN
  - coarse Doppler
  - coarse code phase
  - peak metric

Recommended Phase 1 approach:
- Start with a simple, deterministic search engine rather than a highly optimized FFT architecture.
- Use a design that is easy to verify first, even if it takes longer to search.
- Keep the acquisition engine encapsulated so it can later be replaced by a faster implementation without affecting the tracking channel interface.

### 7.3 Tracking Channel
- Instantiate one reusable tracking-channel block.
- The block should include:
  - carrier NCO
  - code NCO
  - prompt/early/late correlators
  - coherent integrate-and-dump
  - FLL-assisted PLL path
  - DLL path
  - lock metrics

Phase 1 operating mode:
- acquisition provides initial PRN, code phase, and Doppler
- tracking enters a pull-in state
- tracking transitions to steady lock when code and carrier metrics are stable

Why this structure matters:
- It matches the per-channel architecture in `Outline.md`
- It keeps the tracking channel reusable when Phase 2 adds multiple channels

### 7.4 Navigation Bit and Telemetry Processing
- Use prompt correlator output to form `20 ms` nav-bit decisions.
- Implement:
  - bit accumulation
  - bit sign decision
  - simple bit timing alignment
- If practical in Phase 1, add:
  - preamble detection
  - subframe boundary indication

Phase 1 success does not require full ephemeris decode.

Phase 1 does require:
- stable bit extraction while locked
- enough status output to prove the receiver is following a real signal

### 7.5 Measurement and Status Output
- Generate a compact internal report record containing:
  - sample counter or epoch counter
  - PRN
  - carrier Doppler estimate
  - code phase estimate
  - prompt I/Q
  - lock indicators
  - nav-bit value when available
- Pass this report to a UART formatter/transmitter path.

Phase 1 note:
- This block is the placeholder for a future observables engine.
- Keep it modular so Phase 2 can replace or sit beside it with minimal disruption.

## 8. Recommended Control Register Set

### 8.1 Basic Control
- core enable
- soft reset
- acquisition start
- tracking enable
- UART enable

### 8.2 Acquisition Configuration
- PRN search start
- PRN search stop
- Doppler bin min
- Doppler bin max
- Doppler step
- detection threshold

### 8.3 Tracking Configuration
- initial PRN override
- initial Doppler override
- PLL gains
- DLL gains
- lock thresholds

### 8.4 Status
- acquisition done
- acquisition success
- detected PRN
- detected code phase
- detected Doppler
- tracking state
- code lock
- carrier lock
- nav-bit valid
- UART busy

## 9. Suggested VHDL Entity Breakdown

### 9.1 Shared Packages
- `gps_l1_ca_pkg`
  - constants for sample rate, code rate, epoch lengths, PRN count
  - enumerated types for channel state
  - record types for acquisition results and tracking reports

### 9.2 Reusable Utility Blocks
- `nco_phase_accum`
- `ca_prn_gen`
- `complex_mixer`
- `integrate_dump`
- `uart_tx`
- `axis_skid_buffer`
- `xilinx_inferred_true_dual_port_ram` or equivalent inference-friendly RAM template

### 9.3 Phase 1 Functional Blocks
- `gps_l1_ca_acq`
- `gps_l1_ca_track_chan`
- `gps_l1_ca_nav`
- `gps_l1_ca_report`
- `gps_l1_ca_ctrl`
- `gps_l1_ca_phase1_top`

## 10. Implementation Strategy

### 10.1 Step 1: Common Infrastructure
- Create the shared package.
- Define internal record types and constants.
- Define AXI-Stream conventions for complex samples and report streams.
- Implement the control/status register block skeleton.

### 10.2 Step 2: Input and Output Plumbing
- Implement sample ingress.
- Implement UART transmit path.
- Implement a simple report packet placeholder.
- Verify control, sample flow, and output formatting independently.

### 10.3 Step 3: Local Replica Generation
- Implement the GPS C/A PRN generator.
- Implement the carrier NCO.
- Implement the fractional code NCO for `2 MSPS`.
- Verify code epoch timing and NCO stepping numerically in simulation.

### 10.4 Step 4: Acquisition Engine
- Implement sample buffering.
- Implement a simple search loop over PRN, Doppler, and code phase.
- Implement thresholding and best-peak selection.
- Verify using recorded or synthetic vectors with known PRN and Doppler.

### 10.5 Step 5: Tracking Channel
- Implement prompt/early/late correlation.
- Implement integrate-and-dump logic.
- Implement DLL and FLL/PLL loops.
- Verify pull-in and steady-state lock starting from acquisition outputs.

### 10.6 Step 6: Navigation Bit Recovery
- Implement 20 ms bit accumulation.
- Export bit values and validity flags.
- Add optional preamble detection if time permits.

### 10.7 Step 7: End-to-End Integration
- Connect acquisition handoff to tracking.
- Connect tracking to nav and report formatting.
- Stream status and measurement packets over UART.
- Verify the full chain on known GPS L1 C/A input data.

## 11. Verification Goals

### 11.1 Unit-Level Verification
- PRN generator produces correct C/A sequences
- code NCO supports fractional stepping at `2 MSPS`
- carrier NCO frequency control behaves correctly
- correlators integrate correctly over `1 ms`
- UART packetization is stable

### 11.2 Block-Level Verification
- acquisition detects known PRNs under expected Doppler offsets
- tracking converges from acquisition handoff values
- nav-bit extraction stabilizes once tracking is locked

### 11.3 System-Level Verification
- with representative `2 MSPS cs16` input data, the design:
  - detects a GPS L1 C/A satellite
  - reaches a stable tracking state
  - emits coherent status and measurement reports

## 12. Phase 1 Deliverables

### 12.1 HDL Deliverables
- top-level VHDL integration
- control/status register block
- acquisition engine
- single tracking channel
- nav-bit extraction block
- UART report path

### 12.2 Documentation Deliverables
- this plan
- updated packet definition when the report format is chosen
- notes on fixed-point widths and loop constants
- test and verification notes

## 13. Success Criteria

Phase 1 is complete when the following are true:

- the design accepts a fixed `2 MSPS cs16` GPS L1 C/A input stream
- acquisition identifies at least one valid satellite candidate
- tracking maintains lock on that candidate for a useful interval
- the design recovers navigation bits or an equivalent proof of stable prompt tracking
- the design emits meaningful reports over UART
- the implementation remains modular enough that more channels can be added without reworking the basic interfaces

## 14. How This Enables Phase 2

The key to making Phase 2 easy is to avoid building Phase 1 as a one-off demo.

Phase 1 should therefore deliberately preserve these expansion points:

- the acquisition result interface should already look like a future channel-allocation input
- the tracking channel should already be packaged as a reusable per-channel block
- the report path should already separate internal measurement records from UART packet formatting
- the control block should reserve address space for future channels and future signal families
- shared packages should already separate GPS L1 C/A specifics from generic utility functions

If these rules are followed, Phase 2 can add:

- more GPS L1 C/A tracking channels
- a channel manager
- richer observables generation
- better telemetry decode
- additional signal families

without forcing a redesign of the Phase 1 foundation.
