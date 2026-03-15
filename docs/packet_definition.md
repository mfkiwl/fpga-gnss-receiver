# UART Packet Definition (Phase 1 Placeholder)

## Packet Length
- 16 bytes per report

## Format
- Byte 0: `0xA5` (sync0)
- Byte 1: `0x5A` (sync1)
- Byte 2: PRN (`[5:0]`)
- Byte 3: status flags
  - `[1:0]` tracking state (`00=IDLE, 01=PULLIN, 10=LOCKED`)
  - `[2]` code lock
  - `[3]` carrier lock
  - `[4]` nav bit valid
  - `[5]` nav bit value
- Bytes 4..7: sample counter (MSB first)
- Bytes 8..9: Doppler estimate (signed, Hz, MSB first)
- Bytes 10..11: code phase estimate (11-bit value in 16 bits)
- Bytes 12..13: prompt I low 16 bits
- Byte 14: prompt Q low 8 bits
- Byte 15: XOR checksum of bytes 0..14

## Notes
- This is a Phase 1 debug/status packet, not a final observables packet.
- A richer packet map can be introduced in Phase 2 without changing internal report records.
