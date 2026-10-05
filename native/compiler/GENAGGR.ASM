; Aggregate Z80 publisher. The complete checked initialized-data and constant
; image is emitted after
; the initial JP and before main's first instruction. .MAIN
; patches the JP operand to the first code byte, so source execution cannot
; observe initialization in progress.

; Emit every aggregate constant exactly once in declaration order. Symbols
; retain per-bank offsets, while IY walks the single declaration-ordered
; compiler backing image. Switching banks never replays source or semantics.
;@ROUTINE OUT A,CARRY,ZERO CLOBBERS SIGN,PARITY,HALFCARRY,BC,DE,HL,IX,IY
GA_PLACE:
    LD   A,(SY_CNT)
    OR   A
    RET  Z
    LD   B,A
    LD   C,0
    LD   IX,SY_BASE
    LD   IY,AG_DATA
    LD   DE,(AG_DLEN)
    ADD  IY,DE
.SYMLOOP:
    LD   A,(IX+3)
    LD   D,A
    AND  SY_AGGR+SY_CMASK
    CP   SY_AGGR+SY_CONST
    JR   NZ,.NEXT
    LD   A,D
    CALL TG_SPLIT
    PUSH BC
    CALL TG_PICK
    POP  BC
    LD   H,0
    LD   L,C
    LD   DE,AG_SYTAB
    ADD  HL,DE
    LD   A,(HL)
    CALL AG_SIZE
    EX   DE,HL
.BYTELOOP:
    LD   A,D
    OR   E
    JR   Z,.NEXT
    LD   A,(IY+0)
    INC  IY
    PUSH BC
    PUSH DE
    CALL EM_BYTE
    POP  DE
    POP  BC
    DEC  DE
    JR   .BYTELOOP
.NEXT:
    LD   DE,SY_RECB
    ADD  IX,DE
    INC  C
    DJNZ .SYMLOOP
    OR   A
    RET

;@ROUTINE OUT A,CARRY,ZERO CLOBBERS SIGN,PARITY,HALFCARRY,B,C,D,DE,HL,IX,IY
GA_BUILD:
    LD   IX,(TG_DESC)
    CALL TG_OPEN
;@ROUTINE IN HL OUT A,CARRY,ZERO CLOBBERS SIGN,PARITY,HALFCARRY,B,C,D,DE,HL,IX,IY
GA_IMAGE:
    LD   A,(TG_BCNT)
    CP   1
    JR   NZ,.CODE
; TG_OPEN already selected the first read-only byte.
    LD   A,(TG_LMODE)
    OR   A
    JR   Z,.LOADED
    LD   HL,(EM_PTR)
    CALL TG_RAM
    JR   .ALL
.LOADED:
    LD   HL,AG_DATA
    LD   DE,(AG_DLEN)
    ADD  HL,DE
    LD   BC,(AG_ROLEN)
    JR   .COPY
.ALL:
    LD   HL,(AG_ROLEN)
    LD   BC,(AG_DLEN)
    ADD  HL,BC
    LD   B,H
    LD   C,L
    LD   HL,AG_DATA
.COPY:
    CALL EM_BLOCK
.CODE:
    LD   A,(TG_BCNT)
    CP   1
    JR   NZ,.BOUNDS
    LD   HL,(EM_PTR)
    LD   (TG_CODE),HL
    LD   A,(TG_LMODE)
    OR   A
    JR   NZ,.BOUNDS
    LD   HL,(TG_CCAP)
    LD   (EM_LIM),HL
.BOUNDS:
    LD   A,(TG_BCNT)
    CP   1
    JR   NZ,.GENERATE
    LD   HL,(TG_CRO)
    LD   (TG_ROPOS),HL
    LD   HL,(TG_COCAP)
    LD   (TG_ROCAP),HL
.GENERATE:
    CALL GX_WALK
    JP   TG_SHUT

GA_ABORT EQU  TG_ABORT
