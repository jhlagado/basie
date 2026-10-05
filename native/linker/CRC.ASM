; CRC-16/CCITT-FALSE (object format §7.6): polynomial $1021, initial $FFFF,
; no reflection.

CRC_V:  DW      $FFFF

; Start a CRC.
CRC_NEW:
        LD      HL,$FFFF
        LD      (CRC_V),HL
        RET

; Add A to the CRC. Preserves BC, DE and HL.
CRC_ADD:
        PUSH    BC
        PUSH    HL
        LD      HL,(CRC_V)
        XOR     H
        LD      H,A
        LD      B,8
.BIT:   ADD     HL,HL
        JR      NC,.NEXT
        LD      A,H
        XOR     $10
        LD      H,A
        LD      A,L
        XOR     $21
        LD      L,A
.NEXT:  DJNZ    .BIT
        LD      (CRC_V),HL
        POP     HL
        POP     BC
        RET
