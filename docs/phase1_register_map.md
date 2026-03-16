# Phase 1 Control/Status Register Map

All addresses are byte addresses on the assumed simple control bus.

## Control/Config
- `0x00` Control
  - `[0]` core enable
  - `[1]` soft reset pulse
  - `[2]` acquisition start pulse
  - `[3]` tracking enable
  - `[4]` UART enable
- `0x04` Acquisition PRN range
  - `[5:0]` PRN start
  - `[13:8]` PRN stop
- `0x08` Doppler min (signed 16)
- `0x0C` Doppler max (signed 16)
- `0x10` Doppler step (signed 16)
- `0x14` Detection threshold (unsigned 32)
- `0x18` PLL gain placeholder (unsigned 16)
- `0x1C` DLL gain placeholder (unsigned 16)
- `0x20` Lock threshold placeholder (unsigned 16)
- `0x24` Initial PRN override (`[5:0]`)
- `0x28` Initial Doppler override (signed 16)
- `0x2C` Tracking Doppler update step in pull-in state (unsigned 16, Hz)
- `0x30` Tracking Doppler update step in locked state (unsigned 16, Hz)

## Status
- `0x40` Status flags
  - `[0]` acquisition done
  - `[1]` acquisition success
  - `[2]` code lock
  - `[3]` carrier lock
  - `[4]` nav bit valid
  - `[5]` UART busy
  - `[7:6]` tracking state
- `0x44` Acquisition result
  - `[5:0]` detected PRN
  - `[26:16]` detected code phase
- `0x48` Acquisition Doppler (signed 16)
