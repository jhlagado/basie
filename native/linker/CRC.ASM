; CRC-16/CCITT-FALSE (object format §7.6): polynomial $1021, initial $FFFF,
; no reflection. Several CRCs run at once, each a word: CRC_VAL for the
; directory being read, and others the callers keep.

CRC_VAL:  DW      $FFFF

; Start CRC_VAL.
CRC_NEW:
        LD      HL,$FFFF
        LD      (CRC_VAL),HL
        RET

; Add A to CRC_VAL. Preserves BC, DE and HL.
CRC_ADD:
        PUSH    HL
        LD      HL,CRC_VAL
        CALL    CRC_FOLD
        POP     HL
        RET

; Add A to the CRC word at HL. Preserves A, BC, DE and HL.
CRC_FOLD:
        PUSH    AF
        PUSH    BC
        PUSH    DE
        PUSH    HL
        LD      E,(HL)
        INC     HL
        LD      D,(HL)
        EX      DE,HL           ; HL = the CRC, DE = its address + 1
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
        EX      DE,HL
        LD      (HL),D
        DEC     HL
        LD      (HL),E
        POP     HL
        POP     DE
        POP     BC
        POP     AF
        RET
