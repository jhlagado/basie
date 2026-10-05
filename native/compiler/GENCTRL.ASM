; Post-parse absolute-label and structured-loop lowering. All generated branch
; operands are compiler-private absolute words and are resolved before the
; generated program is published.

GC_COUNT EQU  EM_ORG
GC_MODE EQU  EM_ORG+1
GC_STEP EQU  EM_HEAD
GC_POS EQU  EM_XFIX
GC_TOP EQU  EM_FFIX
GC_EXIT EQU  EM_FFIX+1

; C is a label ordinal and DE is the address of a generated word operand.
; Bit 7 distinguishes a cross-bank address operand. Bits 5..6 retain the site
; bank and bits 0..4 retain the globally unique label ordinal.
;@ROUTINE IN C,DE OUT A,CARRY,ZERO CLOBBERS SIGN,PARITY,HALFCARRY,B,C,D,DE,HL
GC_PEND:
    LD   A,C
    AND  $1F
    CP   GC_LCAP
    JP   NC,CT_ELABS
    LD   A,(GC_FCNT)
    CP   GC_FCAP
    JR   NC,.FULL
    PUSH BC
    LD   L,A
    LD   H,0
    ADD  A,A
    ADD  A,L
    LD   L,A
    LD   H,0
    LD   BC,GC_FTAB
    ADD  HL,BC
    POP  BC
    LD   A,(TG_OBANK)
    RLCA
    RLCA
    RLCA
    RLCA
    RLCA
    OR   C
    LD   (HL),A
    INC  HL
    LD   (HL),E
    INC  HL
    LD   (HL),D
    LD   HL,GC_FCNT
    INC  (HL)
    XOR  A
    RET
.FULL:
    CALL DG_RAISE
    DB   DG_FIXUP

; Emit opcode A with a zero word operand and retain that operand for label C.
;@ROUTINE IN A,C OUT A,CARRY,ZERO CLOBBERS SIGN,PARITY,HALFCARRY,B,C,D,DE,HL
GC_OPFAR:
    SET  7,C
;@ROUTINE IN A,C OUT A,CARRY,ZERO CLOBBERS SIGN,PARITY,HALFCARRY,B,C,D,DE,HL
GC_OPREF:
    PUSH BC
    CALL EM_BYTE
    POP  BC
    LD   DE,(EM_PTR)
    PUSH BC
    PUSH DE
    LD   HL,0
    CALL EM_WORD
    POP  DE
    POP  BC
    JR   GC_PEND

;@ROUTINE OUT A,CARRY,ZERO CLOBBERS SIGN,PARITY,HALFCARRY,B,C,D,DE,HL
GC_LABEL:
    CALL EM_READB
    LD   C,A
;@ROUTINE IN C OUT A,CARRY,ZERO CLOBBERS SIGN,PARITY,HALFCARRY,B,C,D,DE,HL
GC_PLACE:
    LD   A,C
    CP   GC_LCAP
    JP   NC,CT_ELABS
    LD   B,0
    LD   HL,GC_VALID
    ADD  HL,BC
    LD   A,(HL)
    OR   A
    JP   NZ,GX_BADOP
    LD   A,(TG_OBANK)
    INC  A
    LD   (HL),A
    LD   L,C
    LD   H,0
    ADD  HL,HL
    LD   BC,GC_LADDR
    ADD  HL,BC
    LD   DE,(EM_PTR)
    LD   (HL),E
    INC  HL
    LD   (HL),D
    XOR  A
    RET

;@ROUTINE OUT A,CARRY,ZERO CLOBBERS SIGN,PARITY,HALFCARRY,B,C,D,DE,HL
GC_IFNOT:
    CALL EM_READB
    LD   C,A
    PUSH BC
    LD   HL,GT_ANDIF
    CALL EM_THREE
    POP  BC
    LD   A,$CA                     ; JP Z,nn
    JR   GC_OPREF

;@ROUTINE OUT A,CARRY,ZERO CLOBBERS SIGN,PARITY,HALFCARRY,B,C,D,DE,HL
GC_JUMP:
    CALL EM_READB
    LD   C,A
    LD   A,$C3                     ; JP nn
    JR   GC_OPREF

; Resolve every retained absolute operand after all label locations are known.
;@ROUTINE OUT A,CARRY,ZERO CLOBBERS SIGN,PARITY,HALFCARRY,B,C,D,DE,HL,IX,IY
GC_PATCH:
    CALL TG_SAVE
    LD   A,(GC_FCNT)
    OR   A
    RET  Z
    LD   B,A
    LD   IX,GC_FTAB
.NEXT:
    LD   C,(IX+0)
    LD   A,C
    RLCA
    RLCA
    RLCA
    AND  $03
    LD   E,(IX+1)
    LD   D,(IX+2)
    PUSH BC
    PUSH DE
    LD   E,A
    LD   D,C
    LD   A,C
    AND  $1F
    LD   C,A
    LD   A,E
    LD   (TG_OBANK),A
    LD   A,C
    LD   B,0
    LD   HL,GC_VALID
    ADD  HL,BC
    LD   A,(HL)
    OR   A
    JR   Z,.UNWIND
    DEC  A
    BIT  7,D
    JR   NZ,.BANKOK
    CP   E
    JR   NZ,.UNWIND
.BANKOK:
    LD   H,0
    LD   L,C
    ADD  HL,HL
    LD   BC,GC_LADDR
    ADD  HL,BC
    LD   C,(HL)
    INC  HL
    LD   H,(HL)
    LD   L,C
    POP  DE
    CALL EM_FIXW
    POP  BC
    INC  IX
    INC  IX
    INC  IX
    DJNZ .NEXT
    LD   A,TG_OFF
    LD   (TG_OBANK),A
    XOR  A
    RET
.UNWIND:
    POP  DE
    POP  BC
.BAD:
    JP   GX_BADOP

; Emit a local load into HL without pushing a new expression carrier.
; C is the byte offset, A bit 2 selects u16.
;@ROUTINE IN A,C OUT A,CARRY,ZERO CLOBBERS SIGN,PARITY,HALFCARRY,B,C,D,DE,HL
GC_LOAD:
    LD   D,A
    LD   A,C
    CPL
    LD   C,A
    PUSH BC
    PUSH DE
    CALL EM_IDIOM
    DB   EP_LDLO
    POP  DE
    POP  BC
    LD   A,C
    PUSH DE
    CALL EM_BYTE
    POP  DE
    BIT  2,D
    JR   NZ,.UPPER
    LD   HL,GT_ZEROH
    JP   EM_PAIR
.UPPER:
    DEC  C
    PUSH BC
    CALL EM_IDIOM
    DB   EP_LDHI
    POP  BC
    LD   A,C
    JP   EM_BYTE

; Store HL to counter byte offset C; A bit 2 selects u16.
;@ROUTINE IN A,C OUT A,CARRY,ZERO CLOBBERS SIGN,PARITY,HALFCARRY,B,C,D,DE,HL
GC_STORE:
    LD   D,A
    LD   A,C
    CPL
    LD   C,A
    PUSH BC
    PUSH DE
    CALL EM_IDIOM
    DB   EP_STLO
    POP  DE
    POP  BC
    LD   A,C
    PUSH BC
    PUSH DE
    CALL EM_BYTE
    POP  DE
    POP  BC
    BIT  2,D
    RET  Z
    DEC  C
    PUSH BC
    CALL EM_IDIOM
    DB   EP_STHI
    POP  BC
    LD   A,C
    JP   EM_BYTE

;@ROUTINE OUT A,CARRY,ZERO CLOBBERS SIGN,PARITY,HALFCARRY,B,C,D,DE,HL
GC_FOR:
    CALL EM_READB
    LD   C,A
    CALL EM_READB
    LD   B,A
    PUSH BC
    CALL EM_IDIOM
    DB   EP_ARGS
    POP  BC
    LD   A,B
    CALL GC_STORE
    CALL EM_ENDOP
    DB   $D5                       ; PUSH DE, retained bound

;@ROUTINE OUT A,CARRY,ZERO CLOBBERS SIGN,PARITY,HALFCARRY,B,C,D,DE,HL,IX,IY
GC_TEST:
    CALL EM_READB
    LD   C,A                       ; counter
    CALL EM_READB
    LD   B,A                       ; mode
    CALL EM_READB
    LD   D,A                       ; exit label
    LD   (GC_EXIT),A
    PUSH BC
    PUSH DE
    CALL EM_IDIOM
    DB   EP_TOPDE
    POP  DE
    POP  BC
    PUSH BC
    PUSH DE
    LD   A,B
    CALL GC_LOAD
    POP  DE
    POP  BC
    BIT  1,B
    JR   NZ,.DOWN
    BIT  0,B
    LD   A,EX_LT
    JR   Z,.COMPARE
    LD   A,EX_LE
    JR   .COMPARE
.DOWN:
    BIT  0,B
    LD   A,EX_GT
    JR   Z,.COMPARE
    LD   A,EX_GE
.COMPARE:
    CALL GX_TEST
    LD   A,(GC_EXIT)
    LD   C,A
    CALL EM_IDIOM
    DB   EP_TESTL
    LD   A,$CA
    JP   GC_OPREF

;@ROUTINE IN DE OUT A,CARRY,ZERO CLOBBERS SIGN,PARITY,HALFCARRY,B,C,D,DE,HL
EM_LDDE:
    LD   A,$11                     ; LD DE,nn
    PUSH DE
    CALL EM_BYTE
    POP  DE
    LD   H,D
    LD   L,E
    JP   EM_WORD

; Read and retain the fixed-width ForNext operands in emitter scratch.
;@ROUTINE OUT A,CARRY,ZERO CLOBBERS SIGN,PARITY,HALFCARRY,B,C,D,DE,HL,IX,IY
GC_NEXT:
    CALL EM_READB
    LD   (GC_TOP),A
    CALL EM_READB
    LD   (GC_EXIT),A
    CALL EM_READB
    LD   (GC_COUNT),A
    CALL EM_READB
    LD   (GC_MODE),A
    CALL EM_READW
    LD   (GC_STEP),DE
    CALL EM_READW
    LD   (GC_POS),DE
    XOR  A
    CALL EM_IDIOM
    DB   EP_TOPDE
    LD   A,(GC_COUNT)
    LD   C,A
    LD   A,(GC_MODE)
    CALL GC_LOAD
    CALL EM_OP
    DB   $E5                       ; preserve current counter
    LD   A,(GC_MODE)
    BIT  1,A
    JR   NZ,.DOWN
    CALL EM_OP
    DB   $EB                       ; EX DE,HL => bound-current
.DOWN:
    LD   HL,GT_SUBDE
    CALL EM_THREE
    LD   DE,(GC_STEP)
    CALL EM_LDDE
    LD   A,(GC_MODE)
    AND  1
    LD   A,EX_LT
    JR   NZ,.COMPARE
; until exits when distance <= step; to exits when distance < step.
    LD   A,(GC_MODE)
    BIT  0,A
    LD   A,EX_LT
    JR   NZ,.COMPARE
    LD   A,EX_LE
.COMPARE:
    CALL GX_TEST
    LD   HL,GT_PROBE
    CALL EM_THREE
    LD   A,(GC_EXIT)
    LD   C,A
    LD   A,$C2                     ; JP NZ,exit cleanup
    CALL GC_OPREF
    LD   DE,(GC_STEP)
    CALL EM_LDDE
    LD   A,(GC_MODE)
    BIT  1,A
    JR   NZ,.MINUS
    LD   A,$19                     ; ADD HL,DE
    CALL EM_BYTE
    JR   .CHECK
.MINUS:
    LD   HL,GT_SUBDE
    CALL EM_THREE
.CHECK:
    LD   A,(GC_MODE)
    BIT  2,A
    JR   NZ,.STORE
    BIT  1,A
    JR   NZ,.STORE
    CALL EM_IDIOM
    DB   EP_TESTH
    CALL EM_OP
    DB   $CA                       ; JP Z,fit
    LD   HL,(EM_PTR)
    LD   (EM_UFIX),HL
    LD   HL,0
    CALL EM_WORD
    LD   HL,(GC_POS)
    LD   A,4
    CALL GX_RAISE
    LD   DE,(EM_UFIX)
    LD   HL,(EM_PTR)
    CALL EM_FIXW
.STORE:
    LD   A,(GC_COUNT)
    LD   C,A
    LD   A,(GC_MODE)
    CALL GC_STORE
    LD   A,(GC_TOP)
    LD   C,A
    LD   A,$C3
    JP   GC_OPREF

;@ROUTINE OUT A,CARRY,ZERO CLOBBERS SIGN,PARITY,HALFCARRY,B,DE,HL
GC_DROP:
    CALL EM_ENDOP
    DB   $D1                       ; POP DE, discard retained bound

GT_SUBDE: DB   $B7,$ED,$52
GT_PROBE: DB   $7D,$B7,$E1
