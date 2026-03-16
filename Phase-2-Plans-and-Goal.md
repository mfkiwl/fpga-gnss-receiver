# Phase 2 Plans and Goal

## 1. Phase 2 Goal

The goal of Phase 2 is to extend the Phase 1 GPS L1 C/A receiver into a `PVT-capable` receiver by scaling from one tracking channel to a small channel bank and by adding the missing backend blocks required to compute navigation observables and a first position solution.

Phase 2 should turn the Phase 1 design from a `single-channel signal-processing demonstrator` into a `small but complete GPS receiver`.

The recommended Phase 2 target is:

- fixed `2 MSPS` `cs16` GPS L1 C/A input, same as Phase 1
- `4` tracking channels as the minimum PVT-capable configuration
- `5` tracking channels as the preferred baseline for robustness
- shared acquisition front end
- reusable per-channel tracking architecture
- common-epoch observables generation
- navigation message decode sufficient for timing and satellite state
- first PVT solution computed inside the FPGA
- UART output extended to carry observables and PVT results

## 2. Why Phase 2 Exists

Phase 1 proves that the receiver can:

- accept the fixed input stream
- acquire a GPS L1 C/A signal
- track one satellite
- recover navigation bits
- emit basic status output

That is necessary, but not sufficient, to produce a receiver position.

Phase 2 adds the missing receiver-level capabilities:

- simultaneous tracking of multiple satellites
- common time alignment across channels
- observable formation
- navigation data handling for satellite position and clock corrections
- a solver for receiver state

## 3. Compliance Targets

### 3.1 Required Compliance with Assumptions.md
- No DMA is used.
- All implemented processing remains inside the FPGA.
- The input remains a ready-to-use `cs16` complex stream at `2 MSPS`.
- No new filtering, decimation, or resampling blocks are introduced.
- The control/status interface remains the assumed simple control bus.
- AXI-Stream remains the preferred datapath interface where practical.
- Implementation remains VHDL-first.
- Coding style should continue to favor Xilinx-friendly inference patterns.
- Output products continue to leave through a UART-oriented serial interface.

### 3.2 Required Compliance with Outline.md
- Preserve the split between:
  - signal ingress
  - acquisition
  - tracking
  - telemetry decode
  - observables
  - PVT
- Keep the architecture channel-oriented and scalable.
- Keep shared blocks and per-channel blocks cleanly separated.
- Add Phase 2 features without forcing a redesign of the Phase 1 channel microarchitecture.

## 4. Phase 2 Scope

### 4.1 In Scope
- GPS L1 C/A only
- Same fixed `2 MSPS` input assumption as Phase 1
- Multi-channel tracking bank
- Minimum `4` simultaneous tracking channels
- Preferred `5` tracking channels
- Shared acquisition scheduler capable of filling the channel bank
- Per-channel navigation bit handling
- Navigation message decode sufficient for PVT
- Observables engine
- Satellite ephemeris and timing storage
- First FPGA-based PVT solution
- UART packet expansion for multi-channel and PVT reporting

### 4.2 Explicitly Out of Scope
- Galileo support
- L5/E5a support
- Front-end filtering or decimation
- DMA or external high-throughput streaming
- Carrier-phase precision navigation
- RTK, SBAS, PPP, or differential features
- High-rate velocity solution beyond basic Doppler reporting
- Full production-grade navigation integrity monitoring

## 5. Target Channel Count

### 5.1 Minimum Phase 2 Configuration
- `4` tracking channels

This is the minimum useful target because four simultaneous satellites are required to solve for:

- receiver `x`
- receiver `y`
- receiver `z`
- receiver clock bias

### 5.2 Preferred Phase 2 Configuration
- `5` tracking channels

This is the preferred target because the fifth channel adds:

- redundancy
- a better-conditioned least-squares solve
- residual checking
- limited tolerance to one poor measurement

### 5.3 Design Rule
- The architecture should be written for `N` channels even if the initial synthesis target is `4` or `5`.
- Channel count should be a package constant or top-level generic where practical.

## 6. Functional Requirements for a First PVT Solution

To compute a first GPS PVT solution, the receiver must provide the following at a common measurement epoch:

- at least `4` valid tracked satellites
- a satellite ID for each channel
- receiver measurement time or epoch counter
- pseudorange for each valid satellite
- Doppler or range-rate where available
- signal quality and validity flags
- decoded navigation timing information
- decoded ephemeris and satellite clock parameters

The Phase 2 architecture should therefore produce:

- aligned per-channel observables
- a shared navigation-data store
- a PVT engine that consumes those products

## 7. Proposed Phase 2 Architecture

### 7.1 Top-Level Block Diagram
- `sample ingress`
- `control/status block`
- `shared acquisition scheduler`
- `GPS L1 C/A channel bank`
- `navigation data manager`
- `observables engine`
- `PVT engine`
- `UART packet/report path`

### 7.2 Recommended VHDL Partition
- `gps_l1_ca_phase2_top`
  - top-level integration
- `gps_l1_ca_pkg`
  - extended shared types and constants
- `gps_l1_ca_ctrl`
  - expanded control/status register bank
- `gps_l1_ca_acq_sched`
  - channel assignment and acquisition scheduling
- `gps_l1_ca_acq`
  - shared acquisition engine, reused or upgraded from Phase 1
- `gps_l1_ca_track_chan`
  - reusable per-channel tracking block from Phase 1
- `gps_l1_ca_chan_bank`
  - instantiates `N` tracking channels
- `gps_l1_ca_nav`
  - per-channel nav-bit and message decode
- `gps_l1_ca_nav_store`
  - ephemeris, clock, and timing storage
- `gps_l1_ca_observables`
  - common-epoch measurement formation
- `gps_l1_ca_pvt`
  - first PVT solver
- `gps_l1_ca_report`
  - report selection and formatting
- `uart_tx`
  - serial egress

## 8. Detailed Block Plan

### 8.1 Shared Acquisition Scheduler
- Maintain a list of satellites to search.
- Assign successful acquisitions to free tracking channels.
- Re-trigger acquisition when a channel loses lock.
- Prevent duplicate channel assignment to the same PRN.

Phase 2 design note:
- Keep acquisition shared.
- Do not replicate a full acquisition engine per channel unless later timing analysis proves it necessary.

### 8.2 Channel Bank
- Reuse the Phase 1 tracking channel as the per-channel primitive.
- Instantiate `N` channels with identical interfaces.
- Add a lightweight channel state table containing:
  - PRN
  - allocation valid
  - acquisition handoff parameters
  - lock state
  - measurement-valid flags
  - nav decode state

The bank should expose:

- per-channel tracking reports
- per-channel nav reports
- per-channel health and lock metrics

### 8.3 Navigation Data Handling
- Extend the Phase 1 nav-bit block into a true GPS L1 C/A navigation decoder.
- Add:
  - preamble detection
  - word synchronization
  - subframe synchronization
  - parity checking
  - HOW/TOW handling
  - ephemeris field extraction
- Store decoded navigation content in a shared nav-data memory.

Phase 2 goal:
- Decode enough of the GPS navigation message to compute satellite position and time corrections for tracked satellites.

### 8.4 Observables Engine
- Collect valid channel measurements at a common epoch.
- Generate, for each valid channel:
  - pseudorange
  - Doppler
  - code phase
  - carrier phase placeholder
  - CN0 or lock-quality metadata
- Tag each measurement with:
  - PRN
  - epoch index
  - validity flags

The observables engine should also provide:

- a common measurement scheduler
- stale-data rejection
- basic residual or consistency flags where possible

### 8.5 PVT Engine
- Accept a set of aligned measurements and associated satellite state.
- Compute a first receiver state estimate:
  - ECEF position
  - receiver clock bias
- Optionally compute:
  - velocity using Doppler
  - receiver clock drift

Recommended Phase 2 solver approach:
- Start with iterative least squares.
- Use a sequential or lightly pipelined matrix engine rather than a fully parallel solver.
- Favor a small, understandable architecture that reuses DSP resources over a large fully-unrolled design.

This approach is consistent with:

- small channel count
- FPGA-only processing
- Phase 2 bring-up needs

## 9. PVT Data Requirements

### 9.1 Required Inputs Per Satellite
- PRN
- measurement-valid flag
- pseudorange
- Doppler if available
- transmit-time information
- satellite clock correction terms
- ephemeris parameters

### 9.2 Required Shared Inputs
- common receiver epoch
- receiver sample or epoch counter
- receiver time estimate
- channel validity mask

### 9.3 Required Outputs
- ECEF `x, y, z`
- receiver clock bias
- solution-valid flag
- number of satellites used
- residual metric or fit-quality indicator

### 9.4 Recommended Additional Outputs
- latitude / longitude / altitude conversion
- velocity estimate
- clock drift estimate
- per-satellite residuals

## 10. Suggested Packet Strategy

Phase 1 used a small debug/status UART packet. Phase 2 should extend that into at least three logical packet types:

- `channel status packet`
  - per-channel lock state, PRN, Doppler, code phase, nav status
- `observables packet`
  - epoch-tagged measurements for valid channels
- `PVT packet`
  - receiver solution, validity, and quality metrics

The packet format can continue to live in [packet_definition.md](/home/rigo/test/docs/packet_definition.md), but the internal report records should remain separate from the UART byte layout.

## 11. Control and Register Expansion

### 11.1 New Control Functions
- channel enable mask
- preferred channel count
- acquisition rescan enable
- nav decode enable
- observables enable
- PVT enable

### 11.2 New Status Functions
- channel allocation bitmap
- per-channel lock bitmap
- valid-observables count
- ephemeris-valid bitmap
- PVT-valid flag
- satellite count used in last solve

### 11.3 Address Map Guidance
- Reserve grouped address ranges per channel.
- Keep shared blocks in separate register regions:
  - acquisition
  - navigation store
  - observables
  - PVT

## 12. Fixed-Point and Numeric Strategy

### 12.1 General Rule
- Keep Phase 1 signal-processing widths unless a verified accuracy issue requires expansion.
- Add width only where Phase 2 math requires it.

### 12.2 New Numeric Areas Requiring Care
- pseudorange formation
- satellite position computation
- clock correction evaluation
- least-squares matrix accumulation
- matrix inversion or linear solve

### 12.3 Practical Recommendation
- Use fixed-point for the Phase 2 PVT engine.
- Keep the first implementation simple, documented, and heavily verified.
- If needed, allow a mixed architecture where tracking remains fully streaming but PVT runs as a sequential solver at a slower update rate.

## 13. Verification Strategy

### 13.1 Unit-Level Verification
- channel allocation logic
- nav-word parsing and parity checking
- ephemeris storage
- pseudorange formation
- least-squares update step
- ECEF-to-LLA conversion if implemented

### 13.2 Block-Level Verification
- `N`-channel lock maintenance with mixed PRNs
- common-epoch observable capture
- nav-data decode on multiple channels
- PVT solve from known synthetic measurement sets

### 13.3 System-Level Verification
- replay representative GPS L1 C/A data
- acquire and track at least `4` satellites
- form aligned observables
- compute a valid position solution
- compare observables and PVT outputs against a software reference

### 13.4 Reference Comparison Strategy
- compare tracking outputs to Phase 1 expectations
- compare observables against known-good software calculations
- compare final PVT against a trusted GPS software receiver or offline reference script

## 14. Implementation Roadmap

### 14.1 Step 1: Generalize Phase 1 Interfaces
- Promote single-channel records to channel-bank-aware records.
- Make channel count configurable.
- Preserve compatibility with the existing Phase 1 tracking block.

### 14.2 Step 2: Build the Channel Bank
- Instantiate `4` channels first.
- Prove acquisition-to-channel assignment and lock tracking.
- Expand to `5` channels once the control and report paths are stable.

### 14.3 Step 3: Complete Navigation Decode
- Add robust GPS subframe handling.
- Extract and store ephemeris and timing fields.
- Verify parity and field decode on known captures.

### 14.4 Step 4: Add Observables Engine
- Create epoch-aligned measurement capture.
- Generate pseudorange and related metadata.
- Verify inter-channel consistency.

### 14.5 Step 5: Add PVT Engine
- Implement the first least-squares solver.
- Feed it from the observables and nav-data stores.
- Verify position convergence on representative data.

### 14.6 Step 6: Expand UART Reporting
- Add packet types for channel status, observables, and PVT.
- Keep packetization separate from core records.
- Verify that UART throughput remains adequate for the chosen report rate.

## 15. Success Criteria

Phase 2 is complete when the following are true:

- the receiver can simultaneously track at least `4` GPS L1 C/A satellites
- the preferred build can support `5` channels without architectural changes
- the design forms epoch-aligned observables
- the design decodes enough GPS navigation data to support a position fix
- the FPGA computes a valid first PVT solution
- the UART output can export multi-channel status, observables, and PVT results
- the Phase 2 changes preserve a clean path toward later constellation and band expansion

## 16. How Phase 2 Enables Later Phases

If Phase 2 is implemented with clean block boundaries, later phases can add:

- more channels
- additional constellations
- additional bands
- richer observables
- improved telemetry decode
- more advanced navigation filters
- higher-rate or higher-accuracy position solutions

The critical design rule is to keep these boundaries stable:

- acquisition scheduler to channel bank
- channel bank to observables
- nav-data store to PVT
- internal report records to UART packetization

That preserves the Phase 1 investment and keeps the design compatible with the broader receiver architecture described in [Outline.md](/home/rigo/test/Outline.md).
