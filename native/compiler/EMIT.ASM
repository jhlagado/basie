; Streaming direct-Z80 encoder for the counted-loop semantic stream.

;@ROUTINE IN A OUT A,CARRY,ZERO CLOBBERS SIGN,PARITY,HALFCARRY,B,DE,HL
EM_BYTE:
    LD   B,A
    LD   HL,(EM_LIM)
    LD   A,H
    OR   L
    JP   Z,TG_FULL
    DEC  HL
    LD   (EM_LIM),HL
    LD   HL,(EM_PTR)
    PUSH BC
    LD   A,(TG_OBANK)
    LD   C,A
    LD   A,B
    PUSH HL
    CALL PUB_BYTE
    POP  HL
    POP  BC
    JP   C,TG_FAIL
    INC  HL
    LD   (EM_PTR),HL
    OR   A
    RET

;@ROUTINE NORETURN
EM_ENDOP:
    POP  HL
    LD   A,(HL)
    JR   EM_BYTE

;@ROUTINE NORETURN
EM_OP:
    POP  HL
    LD   A,(HL)
    INC  HL
    PUSH HL
    JR   EM_BYTE

;@ROUTINE NORETURN
EM_IDIOM:
    POP  HL
    LD   A,(HL)
    INC  HL
    PUSH HL
    ADD  A,A
    LD   L,A
    LD   H,0
    LD   DE,.IDIOMS
    ADD  HL,DE
    JR   EM_PAIR

EP_DECSP EQU  0
EP_LDLO EQU  1
EP_LDHI EQU  2
EP_STLO EQU  3
EP_STHI EQU  4
EP_ARGS EQU  5
EP_TOPDE EQU  6
EP_TESTL EQU  7
EP_TESTH EQU  8
EP_POPA EQU  9
EP_FIELD EQU  10
EP_ARGSX EQU  11
EP_ZEROH EQU  12
EP_LDIR EQU  13
.IDIOMS:
    DB   $3B,$3B                   ; DEC SP / DEC SP
    DB   $DD,$6E                   ; LD L,(IX+n)
    DB   $DD,$66                   ; LD H,(IX+n)
    DB   $DD,$75                   ; LD (IX+n),L
    DB   $DD,$74                   ; LD (IX+n),H
    DB   $D1,$E1                   ; POP DE / POP HL
    DB   $D1,$D5                   ; POP DE / PUSH DE
    DB   $7D,$B7                   ; LD A,L / OR A
    DB   $7C,$B7                   ; LD A,H / OR A
    DB   $E1,$7D                   ; POP HL / LD A,L
    DB   $E1,$11                   ; POP HL / LD DE,nn
    DB   $E1,$D1                   ; POP HL / POP DE
    DB   $26,$00                   ; LD H,0
    DB   $ED,$B0                   ; LDIR

;@ROUTINE IN HL OUT A,CARRY,ZERO CLOBBERS SIGN,PARITY,HALFCARRY,B,C,DE,HL
EM_WORD:
    LD   C,H
    LD   A,L
    CALL EM_BYTE
    LD   A,C
    JR   EM_BYTE

; Copy B retained opcode bytes. Shared fixed sequences are cheaper as data
; once two or more encoder paths need four or more emitted bytes.
;@ROUTINE IN B,HL OUT A,CARRY,ZERO CLOBBERS SIGN,PARITY,HALFCARRY,B,C,DE,HL
EM_BYTES:
    PUSH BC
    LD   C,B
    LD   B,0
    CALL EM_BLOCK
    POP  BC
    RET

; Copy the complete BC-byte region through the checked output sink.
;@ROUTINE IN BC,HL OUT A,CARRY,ZERO CLOBBERS SIGN,PARITY,HALFCARRY,B,C,DE,HL
EM_BLOCK:
    LD   A,B
    OR   C
    RET  Z
    LD   A,(HL)
    INC  HL
    PUSH BC
    PUSH HL
    CALL EM_BYTE
    POP  HL
    POP  BC
    DEC  BC
    JR   EM_BLOCK

;@ROUTINE IN HL OUT A,CARRY,ZERO CLOBBERS SIGN,PARITY,HALFCARRY,B,C,DE,HL
EM_EIGHT:
    LD   B,8
    JR   EM_TAIL
;@ROUTINE IN HL OUT A,CARRY,ZERO CLOBBERS SIGN,PARITY,HALFCARRY,B,C,DE,HL
EM_FIVE:
    LD   B,5
    JR   EM_TAIL
;@ROUTINE IN HL OUT A,CARRY,ZERO CLOBBERS SIGN,PARITY,HALFCARRY,B,C,DE,HL
EM_FOUR:
    LD   B,4
    JR   EM_TAIL
;@ROUTINE IN HL OUT A,CARRY,ZERO CLOBBERS SIGN,PARITY,HALFCARRY,B,C,DE,HL
EM_THREE:
    LD   B,3
    JR   EM_TAIL
;@ROUTINE IN HL OUT A,CARRY,ZERO CLOBBERS SIGN,PARITY,HALFCARRY,B,C,DE,HL
EM_PAIR:
    LD   B,2
;@ROUTINE IN B,HL OUT A,CARRY,ZERO CLOBBERS SIGN,PARITY,HALFCARRY,B,C,DE,HL
EM_TAIL:
    JR   EM_BYTES

; Patch one Z80 relative displacement. DE is the operand and HL the target.
;@ROUTINE IN DE,HL OUT A,CARRY,ZERO CLOBBERS SIGN,PARITY,HALFCARRY,B,C,DE,HL,IX,IY
EM_FIXJR:
    LD   (EM_FIXAT),DE
    INC  DE
    OR   A
    SBC  HL,DE
    LD   C,L
    LD   A,C
    ADD  A,A
    SBC  A,A
    CP   H
    JR   NZ,.TOOFAR
.STORE:
    LD   B,C
    LD   HL,(EM_FIXAT)
    LD   A,(TG_OBANK)
    LD   C,A
    LD   A,B
    CALL PUB_FIXB
    JP   C,TG_FAIL
    OR   A
    RET
.TOOFAR:
    CALL DG_RAISE
    DB   DG_REACH

; Small instruction emitters shared by the direct back end. Multiple entry
; points share the opcode-plus-operand tails rather than repeating them in
; every semantic operation.
;@ROUTINE IN A,HL OUT A,CARRY,ZERO CLOBBERS SIGN,PARITY,HALFCARRY,B,C,DE,HL
EM_OPW:
    PUSH HL
    CALL EM_BYTE
    POP  HL
    JR   EM_WORD

;@ROUTINE IN HL OUT A,CARRY,ZERO CLOBBERS SIGN,PARITY,HALFCARRY,B,C,DE,HL
EM_CALL:
    LD   A,$CD
    JR   EM_OPW

;@ROUTINE IN HL OUT A,CARRY,ZERO CLOBBERS SIGN,PARITY,HALFCARRY,B,C,DE,HL
EM_LDHL:
    LD   A,$21
    JR   EM_OPW

;@ROUTINE IN HL OUT A,CARRY,ZERO CLOBBERS SIGN,PARITY,HALFCARRY,B,C,DE,HL
EM_LDBC:
    LD   A,$01
    JR   EM_OPW

;@ROUTINE IN HL OUT A,CARRY,ZERO CLOBBERS SIGN,PARITY,HALFCARRY,B,C,DE,HL
EM_PUTA:
    LD   A,$32
    JR   EM_OPW

; Emit LD (state-base+DE),A through the target-linked writable-state address.
;@ROUTINE IN DE OUT A,CARRY,ZERO CLOBBERS SIGN,PARITY,HALFCARRY,B,C,DE,HL
EM_TOVAR:
    CALL TG_VAR
    JR   EM_PUTA

;@ROUTINE IN A,C OUT A,CARRY,ZERO CLOBBERS SIGN,PARITY,HALFCARRY,B,DE,HL
EM_OPB:
    CALL EM_BYTE
    LD   A,C
    JP   EM_BYTE

;@ROUTINE IN A OUT A,CARRY,ZERO CLOBBERS SIGN,PARITY,HALFCARRY,B,C,DE,HL
EM_LDA:
    LD   C,A
    LD   A,$3E
    JR   EM_OPB

;@ROUTINE OUT A,CARRY,ZERO CLOBBERS SIGN,PARITY,HALFCARRY,B,C,DE,HL
EM_DONE:
    LD   A,RT_OK
    JR   EM_STOP

; At runtime A carries the trap number and HL carries the source offset.
;@ROUTINE OUT A,CARRY,ZERO CLOBBERS SIGN,PARITY,HALFCARRY,B,C,DE,HL
EM_TRAP:
    LD   DE,RT_TNUM-RT_BASE
    CALL EM_TOVAR
    CALL EM_OP
    DB   $AF
    LD   DE,RT_TSUB-RT_BASE
    CALL EM_TOVAR
    LD   DE,RT_TPOS-RT_BASE
    CALL TG_VAR
    LD   A,$22
    CALL EM_OPW
    LD   A,RT_TRAP
;@ROUTINE IN A OUT A,CARRY,ZERO CLOBBERS SIGN,PARITY,HALFCARRY,B,C,DE,HL
EM_STOP:
    CALL EM_LDA
    LD   DE,RT_RUN-RT_BASE
    CALL EM_TOVAR
    LD   A,(TG_EBANK)
    LD   D,A
    LD   A,(TG_OBANK)
    CP   D
    JR   Z,.NEAR
    LD   A,D
    CALL EM_LDA
    LD   HL,(TG_TERM)
    CALL EM_LDHL
    LD   A,10                      ; far-jump vector ordinal
    JP   EM_JUMPV
.NEAR:
    LD   HL,(TG_TERM)
    LD   A,$C3
    JR   EM_OPW

; At runtime A carries an unhandled error and HL the failing source offset.
;@ROUTINE OUT A,CARRY,ZERO CLOBBERS SIGN,PARITY,HALFCARRY,B,C,DE,HL
EM_STRAY:
    LD   DE,RT_TERR-RT_BASE
    CALL EM_TOVAR
    LD   A,6
    JR   EM_LDA

;@ROUTINE OUT A,CARRY,ZERO,DE CLOBBERS SIGN,PARITY,HALFCARRY,B,HL
EM_JR:
    LD   A,$18
    JR   EM_JRCC
;@ROUTINE OUT A,CARRY,ZERO,DE CLOBBERS SIGN,PARITY,HALFCARRY,B,HL
EM_JRNC:
    LD   A,$30
;@ROUTINE IN A OUT A,CARRY,ZERO,DE CLOBBERS SIGN,PARITY,HALFCARRY,B,HL
EM_JRCC:
    CALL EM_BYTE
    LD   HL,(EM_PTR)
    PUSH HL
    XOR  A
    CALL EM_BYTE
    POP  DE
    RET

;@ROUTINE IN DE,HL OUT A,CARRY,ZERO CLOBBERS SIGN,PARITY,HALFCARRY,DE,HL
EM_FIXW:
    PUSH BC
    LD   A,(TG_OBANK)
    LD   C,A
    CALL PUB_FIXW
    POP  BC
    JP   C,TG_FAIL
    OR   A
    RET

; Patch a stored displacement to the current output position.
;@ROUTINE IN DE OUT A,CARRY,ZERO CLOBBERS SIGN,PARITY,HALFCARRY,B,C,DE,HL,IX,IY
EM_LAND:
    LD   HL,(EM_PTR)
    JP   EM_FIXJR

; Read one operand from the checked semantic transcript. The operation count
; bounds dispatch; individual handlers know the fixed width of their operands.
RG_BEG:
;@ROUTINE OUT A,CARRY,ZERO CLOBBERS SIGN,PARITY,HALFCARRY,HL
EM_READB:
    LD   HL,(EM_READP)
    LD   A,(HL)
    INC  HL
    LD   (EM_READP),HL
    OR   A
    RET

;@ROUTINE OUT A,DE,CARRY,ZERO CLOBBERS SIGN,PARITY,HALFCARRY,HL
EM_READW:
    CALL EM_READB
    LD   E,A
    CALL EM_READB
    LD   D,A
    RET

; Dense ordinal dispatcher for the first non-positional backend. A pushed
; continuation turns the Z80's JP (HL) into a compact indirect call. This
; entry is post-parse only: TR_CLOSE must have published the complete
; transcript before emitter scratch overlays the retained forward signature.

; Dense postfix-expression backend. Program data follows an initial JP, so its
; address is known before the code entry is patched. Scalar locals use an IX
; frame and therefore remain per activation; the evaluation stack lies below
; that frame and is empty at every statement boundary.

;@ROUTINE OUT A,HL,CARRY,ZERO CLOBBERS SIGN,PARITY,HALFCARRY,B,C,D,E,IX,IY
EM_READA:
    CALL EM_READW
    BIT  7,D
    JR   Z,.DATA
    RES  7,D
    LD   HL,(TG_BSS)
    JR   .OFFSET
.DATA:
    LD   HL,(TG_CDATA)
.OFFSET:
    ADD  HL,DE
    OR   A
    RET

;@ROUTINE OUT A,CARRY,ZERO CLOBBERS SIGN,PARITY,HALFCARRY,B,DE,HL
EM_LEAVE:
    LD   HL,GT_LEAVE
    JP   EM_FOUR

GT_ENTER:
    DB   $DD,$E5,$DD,$21,$00,$00,$DD,$39
GT_LEAVE:
    DB   $DD,$F9,$DD,$E1
