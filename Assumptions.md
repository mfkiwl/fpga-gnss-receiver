# GNSS Receiver HDL Assumptions

## 1. Scope and Architectural Assumptions

### 1.1 Processing Location
- No DMA engines will be implemented.
- All signal processing is assumed to happen inside the FPGA fabric.
- Data movement between internal blocks should therefore be modeled as direct streaming or local buffering within the FPGA.

### 1.2 Front-End Input Assumption
- For now, decimation and filtering are out of scope.
- Each supported signal/constellation is assumed to arrive as an already-prepared complex I/Q stream.
- The sample format is assumed to be signed complex 16-bit (`cs16`):
  - `I`: signed 16-bit
  - `Q`: signed 16-bit
- The incoming stream is assumed to already have the correct sample rate for the target signal.
- Front-end conditioning, sample-rate adaptation, and anti-alias filtering are treated as external responsibilities at this stage.

### 1.3 Control and Status Assumption
- The origin of control and status traffic is out of scope for now.
- The design should assume a simple memory-mapped control bus with the following interface:

```text
ctrl_wreq
ctrl_waddr[ADDRW-1:0]
ctrl_wdata[DATAW-1:0]
ctrl_wack
ctrl_rreq
ctrl_raddr[ADDRW-1:0]
ctrl_rdata[DATAW-1:0]
ctrl_rack
```

- This interface is treated as the baseline programming and status-readout mechanism until a more complete system integration decision is made.

## 2. Implementation Assumptions

### 2.1 HDL Language
- The implementation language is VHDL.
- New design modules, reusable blocks, and top-level integration should be written in VHDL unless there is a strong project-specific reason to do otherwise.

### 2.2 Internal Interface Preference
- AXI-Stream should be used where practical for datapath-style interfaces.
- This applies especially to:
  - Sample ingress between processing stages
  - Channelized measurement streams
  - Debug or observables streaming paths
- Non-streaming configuration and status paths may use simpler local interfaces when AXI-Stream is not a natural fit.

### 2.3 FPGA Vendor Targeting
- The design should prefer coding templates and implementation styles that infer Xilinx primitives where practical.
- The design should also be written with Xilinx synthesis in mind.
- Examples include inference-friendly templates for:
  - Block RAM
  - DSP slices
  - Shift-register resources
  - Clocking and reset structures where appropriate

## 3. Output and External Reporting Assumptions

### 3.1 Output Transport
- Output products will be sent over a serial interface such as UART.
- The exact packet format is still to be defined.
- Packet structure can be documented separately in `packet_definition.md`.

### 3.2 Expected Output Content
- The serial output path is assumed to carry receiver products such as:
  - Channel status
  - Telemetry results
  - Observables
  - Other debug or navigation outputs as needed

## 4. Practical Design Consequences

### 4.1 What This Means for the Current Architecture
- The current architecture should not reserve area or interfaces for DMA.
- The current architecture should not include front-end filtering or decimation blocks.
- The current architecture should include:
  - VHDL-first module boundaries
  - AXI-Stream-friendly datapaths
  - A simple control/status register bank around the assumed control bus
  - A UART-oriented output path placeholder

### 4.2 What Remains Open
- Exact source of the input sample streams
- Exact control-plane master
- Exact UART packet definition
- Whether later revisions add filtering, decimation, DMA, or a richer SoC integration layer
