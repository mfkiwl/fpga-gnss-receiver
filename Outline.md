# GNSS Receiver HDL Implementation Outline

## 1. System-Level Partition

### 1.1 External Interfaces
- RF/front-end sample input
  - Complex IF or zero-IF sample stream from ADC or RFIC
  - Separate input paths for L1 and L5 bands, if dual-band
- Host/control interface
  - Register bus for configuration and status
  - DMA or streaming link for measurements, debug, and logs
- Time/frequency references
  - Sample clock
  - Optional disciplined oscillator or 1PPS input

### 1.2 Top-Level Receiver Decomposition
- Signal source ingress
  - Sample framing
  - Clock-domain crossing
  - Overflow and validity tracking
- Per-band signal conditioner
  - L1 conditioner
  - L5 conditioner
- Per-signal processing engines
  - GPS L1 C/A channel bank
  - Galileo E1 B/C channel bank
  - GPS L5 channel bank
  - Galileo E5a channel bank
- Shared measurement backend
  - Observables generation
  - Navigation database interface
  - PVT interface
- Control and monitoring plane
  - Scheduler
  - Interrupt/status collection
  - Built-in debug capture

## 2. Front-End and Signal Conditioning

### 2.1 Sample Ingress
- ADC/RFIC stream adapter
- I/Q unpacking and sign extension
- Gain normalization
- Timestamp tagging

### 2.2 Digital Conditioning
- DC offset removal
- AGC support or amplitude monitoring
- FIR channel filtering
- Band-specific decimation
- Optional resampler to a common internal rate

### 2.3 Data Representation
- Fixed-point format selection
  - Sample width
  - Correlator accumulator width
  - NCO phase width
- Saturation and rounding policy
- Format conversion blocks shared across pipelines

## 3. Multi-Constellation / Multi-Band Architecture

### 3.1 Band-Level Partition
- L1 processing island
  - Shared conditioner and clocking
  - GPS L1 C/A bank
  - Galileo E1 B/C bank
- L5 processing island
  - Shared conditioner and clocking
  - GPS L5 bank
  - Galileo E5a bank

### 3.2 Signal-Specific Channel Banks
- Each bank contains `N` independent channels
- Each channel supports:
  - Acquisition
  - Tracking
  - Telemetry decoding
- A channel manager assigns PRNs/signals to free channels

### 3.3 Resource Sharing Strategy
- Option A: fully parallel channels
  - Highest throughput
  - Highest DSP/BRAM usage
- Option B: time-multiplexed correlator engines
  - Lower area
  - Higher control complexity
- Option C: hybrid
  - Parallel tracking channels
  - Shared acquisition accelerator

## 4. Channel Microarchitecture

### 4.1 Common Per-Channel Blocks
- Carrier NCO and wipeoff mixer
- Code NCO and PRN generator
- Correlator engine
  - Prompt
  - Early
  - Late
  - Optional very-early/very-late taps
- Integration and dump logic
- Channel state machine

### 4.2 Channel States
- Idle
- Assisted initialization
- Acquisition search
- Verification / lock confirmation
- Pull-in tracking
- Steady-state tracking
- Bit/frame synchronization
- Telemetry decode
- Loss-of-lock / reacquisition

### 4.3 Channel Outputs
- Code phase
- Carrier phase
- Doppler estimate
- CN0 / lock metrics
- Prompt I/Q
- Decoded symbols/bits
- Measurement-valid flags

## 5. Acquisition Engine

### 5.1 Functional Goals
- Detect visible satellites
- Estimate coarse Doppler
- Estimate coarse code delay
- Produce handoff parameters for tracking

### 5.2 HDL Building Blocks
- PRN/code memory or on-the-fly generator
- Local replica generator
- Search controller
- Correlation engine
  - Serial search
  - Parallel code phase search
  - FFT-based circular correlation accelerator
- Peak detector and threshold logic

### 5.3 Architectural Choices
- Cold-start wide Doppler bin search
- Warm-start assisted narrow search
- Coherent integration window control
- Non-coherent accumulation across multiple dwells

### 5.4 Per-Signal Adaptation
- GPS L1 C/A
  - 1.023 Mcps C/A code
  - 1 ms code epoch
- Galileo E1 B/C
  - Pilot/data handling split
  - Secondary-code-aware search
- GPS L5
  - Dual-component structure
  - Longer coherent opportunities on pilot
- Galileo E5a
  - Pilot/data separation
  - Wideband signal conditioning implications

## 6. Tracking Engine

### 6.1 Carrier Tracking
- FLL for pull-in
- PLL for fine lock
- NCO update path
- Phase discriminator
- Loop filter implementation

### 6.2 Code Tracking
- DLL or equivalent delay lock loop
- Early-minus-late discriminator
- Code loop filter
- Code/carrier aiding path

### 6.3 Correlator Variants
- 3-tap correlator for simple signals
- Multi-tap correlator for BOC or multipath mitigation
- Pilot/data split correlators where applicable

### 6.4 Lock Monitoring
- Carrier lock indicator
- Code lock indicator
- CN0 estimator
- Cycle-slip / divergence detection
- Reacquisition trigger generation

## 7. Telemetry Decoder

### 7.1 Symbol and Bit Processing
- Prompt arm selection
- Bit integration windowing
- Hard-decision or soft-decision output
- Data/pilot selection per signal

### 7.2 Synchronization
- Bit sync
- Word sync
- Subframe/page sync
- Secondary code removal when required

### 7.3 Message Decoding
- Parity or CRC checks
- Frame parser
- Ephemeris extraction
- Almanac and clock data extraction
- Health and issue-of-data tracking

### 7.4 Output Products
- Ephemeris records
- Time-of-week / week number
- Satellite health
- Decoder lock status

## 8. Observables Engine

### 8.1 Measurement Collection
- Gather tracking outputs from all valid channels
- Align channels to a common measurement epoch
- Associate decoded navigation data with channel state

### 8.2 Observable Computation
- Pseudorange
- Carrier phase
- Doppler / pseudorange rate
- Signal quality metadata

### 8.3 Common Services
- Receiver clock counter
- Epoch scheduler
- Satellite ID / signal ID tagging
- Outlier and stale-data rejection

## 9. PVT and Navigation Solution Partition

### 9.1 Minimal HDL Scope
- Package observables and decoded nav data
- Stream measurements to an embedded CPU or host

### 9.2 Optional HDL Acceleration
- Satellite position computation helpers
- Matrix/vector arithmetic blocks
- Least-squares assist engine

### 9.3 Practical Partition Recommendation
- Keep full PVT in software first
- Move only bottleneck math to HDL if needed

## 10. Control Plane and Firmware Interface

### 10.1 Configuration Registers
- Sample rate and decimation settings
- Enabled constellations/signals
- Per-channel PRN assignment
- Loop bandwidth settings
- Acquisition thresholds

### 10.2 Runtime Management
- Channel allocation
- Assisted start parameters
- Loss-of-lock handling
- Health/status counters

### 10.3 Debug and Visibility
- Correlator dump capture
- NCO state readback
- Lock metric history
- Trace buffers for failed acquisitions

## 11. Memory, Interconnect, and Timing

### 11.1 Memory Map
- PRN/code storage
- Channel context RAM
- Measurement FIFOs
- Telemetry message buffers

### 11.2 On-Chip Interconnect
- Streaming datapath for samples
- Register bus for control
- DMA path for observables/debug data

### 11.3 Timing Architecture
- High-rate sample clock domain
- Lower-rate loop update domain
- Host/control clock domain
- Safe CDC boundaries between all domains

## 12. Verification Strategy

### 12.1 Unit-Level Verification
- NCOs
- PRN generators
- Correlators
- Loop discriminators and filters
- Telemetry parsers

### 12.2 Channel-Level Verification
- Acquisition detection on recorded IF samples
- Tracking lock under Doppler/code offsets
- Bit/frame sync on known captures

### 12.3 System-Level Verification
- Replay known GNSS recordings
- Compare HDL measurements against GNSS-SDR software outputs
- Check pseudorange consistency across channels
- Validate ephemeris decode and measurement timing

## 13. Incremental Implementation Roadmap

### 13.1 Phase 1: Narrow First Target
- Single-band L1 only
- GPS L1 C/A only
- One acquisition engine
- One tracking channel
- Observables streamed to software PVT

### 13.2 Phase 2: Scalable Receiver Core
- Multi-channel GPS L1 C/A bank
- Shared acquisition plus per-channel tracking
- Basic telemetry decode

### 13.3 Phase 3: Multi-Constellation Expansion
- Add Galileo E1 B/C
- Add shared observables epoch alignment
- Extend firmware scheduler

### 13.4 Phase 4: Dual-Band Expansion
- Add L5/E5a conditioning path
- Add GPS L5 and Galileo E5a channels
- Revisit bandwidth, BRAM, and DSP budgets

### 13.5 Phase 5: Optimization
- Time-multiplex low-utilization resources
- Add debug instrumentation
- Improve fixed-point precision only where error budgets require it

## 14. Recommended First Concrete HDL Deliverable

### 14.1 Initial Demonstrator
- `Signal conditioner`
- `GPS L1 C/A acquisition`
- `Single GPS L1 C/A tracking channel`
- `Basic nav-bit extraction`
- `Observable packet output to software`

### 14.2 Success Criteria
- Detect at least one GPS L1 C/A satellite from recorded samples
- Hold lock for multiple seconds
- Produce coarse pseudorange and Doppler
- Match software reference behavior within expected fixed-point error
