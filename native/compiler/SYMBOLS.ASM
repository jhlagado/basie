; Bounded exact-name table for the first general scalar slice.

; Compare the current NAME token with committed entries. Carry returns a
; matching entry in HL. The provisional entry at SY_CNT is invisible.
;@ROUTINE OUT A,CARRY,ZERO,HL CLOBBERS SIGN,PARITY,HALFCARRY,B,C,D,DE
SY_FIND:
    LD   A,(SY_CNT)
    OR   A
    RET  Z
    LD   C,A
    LD   HL,SY_BASE
.LOOP:
    CALL TK_SAME
    RET  C
    LD   DE,SY_RECB
    ADD  HL,DE
    DEC  C
    JR   NZ,.LOOP
    OR   A
    RET

; Compatibility entry for the older slices: D is class/type information and E
; is a byte-sized payload. New typed declarations call the word entry below.
;@ROUTINE IN D,BC OUT A,CARRY,ZERO,HL CLOBBERS SIGN,PARITY,HALFCARRY,B,C,D,DE
SY_NEW:
    PUSH BC
    PUSH DE
    CALL SY_FIND
    POP  DE
    POP  BC
    JP   C,EX_EDUP
    LD   A,(SY_CNT)
    CP   SY_CAP
    JR   NC,.FULL
    PUSH BC
    LD   C,A
    LD   B,0
    LD   H,0
    LD   L,C
    ADD  HL,HL
    ADD  HL,HL
    ADD  HL,BC
    ADD  HL,BC
    LD   BC,SY_BASE
    ADD  HL,BC
    CALL TK_KEEP
    INC  HL
    LD   (HL),D
    INC  HL
    POP  BC
    LD   (HL),C
    INC  HL
    LD   (HL),B
    OR   A
    RET
.FULL:
    LD   A,DG_SYMS
    JR   DG_ISSUE

; Retain A as the aggregate-type ordinal for the symbol about to be committed.
; BC remains the caller's prepared symbol payload.
;@ROUTINE IN A,BC OUT A,BC,CARRY,ZERO CLOBBERS SIGN,PARITY,HALFCARRY,DE,HL
SY_TAG:
    PUSH AF
    LD   A,(SY_CNT)
    LD   E,A
    LD   D,0
    LD   HL,AG_SYTAB
    ADD  HL,DE
    POP  AF
    LD   (HL),A
;@ROUTINE OUT A,CARRY,ZERO CLOBBERS SIGN,PARITY,HALFCARRY,HL
SY_CMT:
    LD   HL,SY_CNT
    INC  (HL)
    XOR  A
    RET

; Return the current name's class/type in A and word payload in BC.
;@ROUTINE OUT A,BC,CARRY,ZERO CLOBBERS SIGN,PARITY,HALFCARRY,D,DE,HL
SY_GET:
    CALL SY_FIND
    JR   NC,SY_UNDEF
    INC  HL
    INC  HL
    INC  HL
    LD   A,(HL)
    INC  HL
    LD   C,(HL)
    INC  HL
    LD   B,(HL)
    OR   A
    RET
SY_UNDEF:
    LD   A,DG_UNDEF
