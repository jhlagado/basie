; Memory-backed implementation of the ordered source-byte adapter.

;@ROUTINE IN A,DE,HL OUT A,CARRY,ZERO CLOBBERS SIGN,PARITY,HALFCARRY,BC,DE,HL
SRC_INIT:
    LD   (SRC_ID),A
    LD   (SRC_PTR),HL
    EX   DE,HL
    LD   (SRC_END),HL
    LD   HL,0
    LD   (SRC_POS),HL
    INC  HL
    LD   (SRC_LINE),HL
    LD   (SRC_COL),HL
    XOR  A
    LD   (TK_LIVE),A
    LD   (TK_NEST),A
    RET

; A is a bounded part count and HL points to five-byte descriptors containing
; stable identity, source start, and source end. The source and descriptors
; remain resident until compilation finishes.
;@ROUTINE IN A,HL OUT A,CARRY,ZERO CLOBBERS SIGN,PARITY,HALFCARRY,BC,DE,HL
SRC_OPEN:
    DEC  A
    CP   SRC_CAP
    JR   NC,.FULL
    LD   (SRC_LEFT),A
    JR   SRC_LOAD
.FULL:
    XOR  A
    LD   H,A
    LD   L,A
    LD   D,A
    LD   E,A
    CALL SRC_INIT
    CALL TK_MARK
    CALL DG_RAISE
    DB   DG_FILES

; Load the descriptor at HL and retain the address of the following one.
;@ROUTINE IN HL OUT A,CARRY,ZERO CLOBBERS SIGN,PARITY,HALFCARRY,BC,DE,HL
SRC_LOAD:
    LD   A,(HL)
    INC  HL
    LD   E,(HL)
    INC  HL
    LD   D,(HL)
    INC  HL
    PUSH DE
    LD   E,(HL)
    INC  HL
    LD   D,(HL)
    INC  HL
    LD   (SRC_DESC),HL
    POP  HL
    JR   SRC_INIT

; Return the current source byte in A. Carry denotes the separate EOF event.
;@ROUTINE OUT A,CARRY,ZERO CLOBBERS SIGN,PARITY,HALFCARRY,DE,HL
SRC_PEEK:
    LD   HL,(SRC_PTR)
    LD   DE,(SRC_END)
    OR   A
    SBC  HL,DE
    ADD  HL,DE
    JR   NZ,.BYTE
    SCF
    RET
.BYTE:
    LD   A,(HL)
    OR   A
    RET

; Consume one byte and advance byte offset and byte column. Newline handling
; is separate because LF and CRLF each advance the logical line only once.
;@ROUTINE OUT A,CARRY,ZERO CLOBBERS SIGN,PARITY,HALFCARRY,DE,HL
SRC_TAKE:
    PUSH BC
    CALL SRC_PEEK
    JR   C,.EOF
    LD   B,A
    LD   HL,(SRC_PTR)
    INC  HL
    LD   (SRC_PTR),HL
    LD   HL,(SRC_POS)
    INC  HL
    LD   (SRC_POS),HL
    LD   HL,(SRC_COL)
    INC  HL
    LD   (SRC_COL),HL
    LD   A,B
    POP  BC
    OR   A
    RET
.EOF:
    POP  BC
    SCF
    RET

;@ROUTINE OUT CARRY,ZERO CLOBBERS SIGN,PARITY,HALFCARRY,A,HL
SRC_EOL:
    LD   HL,(SRC_LINE)
    INC  HL
    LD   (SRC_LINE),HL
    LD   HL,1
    LD   (SRC_COL),HL
    OR   A
    RET
