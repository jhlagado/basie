; Proof-layout runtime wrapper. Target-linked runtime images use the separate
; nucleus-target-runtime-link.asm entry and exclude the proof service adapter.

RuntimeProofServices .equ 1
            .include "loop-z80-runtime.asm"
