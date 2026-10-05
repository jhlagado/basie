; Correctness-first direct-Z80 backend for the complete scalar-expression
; increment. All evaluation values use canonical 16-bit carriers on the Z80
; stack. Declared u8/boolean objects still occupy one byte; u16 occupies two.

; Typed dispatch and loop dispatch are currently mutually exclusive. These
; aliases make the temporary reuse visible; merging the dispatchers requires
; dedicated storage or a new liveness proof.
GX_POS EQU  EM_HEAD
GX_WIDTH EQU  EM_ORG

;@ROUTINE OUT A,CARRY,ZERO CLOBBERS SIGN,PARITY,HALFCARRY,B,C,DE,HL,IX,IY
GX_WALK:
    LD   HL,TR_BODY
    LD   (EM_READP),HL
    XOR  A
    LD   (GX_BCNT),A
    LD   (GC_FCNT),A
    LD   HL,GC_VALID
    LD   B,GC_LCAP
.CLEAR:
    LD   (HL),A
    INC  HL
    DJNZ .CLEAR
    LD   A,(TR_BASE)
    OR   A
    RET  Z
    LD   B,A
.NEXT:
    PUSH BC
    CALL EM_READB
    SUB  OP_DEF8
    CP   GX_OPCNT
    JR   NC,.BAD
    ADD  A,A
    LD   E,A
    LD   D,0
    LD   HL,GX_OPTAB
    ADD  HL,DE
    LD   E,(HL)
    INC  HL
    LD   D,(HL)
    EX   DE,HL
    LD   DE,.RETURN
    PUSH DE
    JP   (HL)
.RETURN:
    POP  BC
    DJNZ .NEXT
    JP   GC_PATCH
.BAD:
    POP  BC
GX_BADOP:
    JP   EX_EPOP
GX_FULL:
    CALL DG_RAISE
    DB   DG_ANDOR

GX_OPTAB:
    DW   .DATA8                    ; 20
    DW   .MAIN                     ; 21
    DW   GX_VAR8                   ; 22
    DW   GX_BADOP                  ; 23 retired literal8
    DW   GX_LD8                    ; 24
    DW   GX_LDX8                   ; 25
    DW   GX_BADOP                  ; 26 retired multiply8
    DW   GX_BADOP                  ; 27 retired add8
    DW   GX_ST8                    ; 28
    DW   GX_STX8                   ; 29
    DW   GX_WRITE                  ; 30
    DW   GX_EXIT                   ; 31
    DW   .DATA16                   ; 32
    DW   GX_VAR16                  ; 33
    DW   GX_NUM16                  ; 34
    DW   GX_LD16                   ; 35
    DW   GX_LDX16                  ; 36
    DW   GX_ADD8                   ; 37
    DW   GX_ADD16                  ; 38
    DW   GX_SUB8                   ; 39
    DW   GX_SUB16                  ; 40
    DW   GX_MUL8                   ; 41
    DW   GX_MUL16                  ; 42
    DW   GX_DIV8                   ; 43
    DW   GX_DIV16                  ; 44
    DW   GX_NEG8                   ; 45
    DW   GX_NEG16                  ; 46
    DW   GX_NOT8                   ; 47
    DW   GX_NOT16                  ; 48
    DW   GX_FLIP                   ; 49
    DW   GX_AND8                   ; 50
    DW   GX_AND16                  ; 51
    DW   GX_OR8                    ; 52
    DW   GX_OR16                   ; 53
    DW   GX_XOR8                   ; 54
    DW   GX_XOR16                  ; 55
    DW   GX_MOD8                   ; 56
    DW   GX_MOD16                  ; 57
    DW   GX_RELOP                  ; 58
    DW   GX_RELOP                  ; 59
    DW   GX_RELOP                  ; 60
    DW   GX_FIT8                   ; 61
    DW   GX_ST16                   ; 62
    DW   GX_STX16                  ; 63
    DW   GX_ANDIF                  ; 64
    DW   GX_ORIF                   ; 65
    DW   GX_JOIN                   ; 66
    DW   GC_LABEL                  ; 67
    DW   GC_IFNOT                  ; 68
    DW   GC_JUMP                   ; 69
    DW   GC_FOR                    ; 70
    DW   GC_TEST                   ; 71
    DW   GC_NEXT                   ; 72
    DW   GC_DROP                   ; 73
    DW   GX_ENTER                  ; 74
    DW   GX_LDX8                   ; 75 parameter u8
    DW   GX_LDX16                  ; 76 parameter u16
    DW   GX_CALL                   ; 77
    DW   GX_RET                    ; 78
    DW   GX_STX8                   ; 79 parameter u8
    DW   GX_STX16                  ; 80 parameter u16
    DW   GX_CLOSE                  ; 81
    DW   RG_ENTER                  ; 82
    DW   RG_BIND                   ; 83
    DW   RG_CALL                   ; 84
    DW   RG_RET                    ; 85
    DW   RG_CLOSE                  ; 86
    DW   RG_GLOB                   ; 87
    DW   RG_PARAM                  ; 88
    DW   RG_FIELD                  ; 89
    DW   RG_INDEX                  ; 90
    DW   RG_GET8                   ; 91
    DW   RG_GET16                  ; 92
    DW   RG_PUT8                   ; 93
    DW   RG_PUT16                  ; 94
    DW   RG_COPY                   ; 95
    DW   RG_LEN                    ; 96
    DW   RG_CHAR                   ; 97
    DW   RG_FAIL                   ; 98
    DW   RG_FATAL                  ; 99
    DW   RG_RETOK                  ; 100
    DW   RG_RETOK                  ; 101
    DW   RG_ENDOK                  ; 102
    DW   RG_SKIP                   ; 103
    DW   RG_CATCH                  ; 104
    DW   RG_JOIN                   ; 105
    DW   RG_MAIN                   ; 106
    DW   RG_CONST                  ; 107
    DW   OS_LEN                    ; 108
    DW   OS_CHAR                   ; 109
    DW   OS_ARG                    ; 110
GX_OPCNT EQU  91

;@ROUTINE OUT A,CARRY,ZERO CLOBBERS SIGN,PARITY,HALFCARRY,B,DE,HL
.DATA8:
    CALL EM_READB                  ; byte offset
    CALL EM_READB                  ; value
    JP   EM_BYTE

;@ROUTINE OUT A,CARRY,ZERO CLOBBERS SIGN,PARITY,HALFCARRY,B,DE,HL
.DATA16:
    CALL EM_READB                  ; byte offset
    CALL EM_READB
    CALL EM_BYTE
    CALL EM_READB
    JP   EM_BYTE

;@ROUTINE OUT A,CARRY,ZERO CLOBBERS SIGN,PARITY,HALFCARRY,B,C,DE,HL
.MAIN:
    CALL GX_START
    LD   HL,GT_ENTER
    JP   EM_EIGHT

;@ROUTINE OUT A,CARRY,ZERO CLOBBERS SIGN,PARITY,HALFCARRY,B,C,DE,HL
GX_START:
    LD   DE,(EM_DFIX)
    LD   HL,(EM_PTR)
    CALL EM_FIXW
    JP   GX_SAVE

;@ROUTINE OUT A,CARRY,ZERO CLOBBERS SIGN,PARITY,HALFCARRY,B,DE,HL
GX_VAR8:
    CALL EM_READB
    CALL EM_ENDOP
    DB   $3B                       ; DEC SP

;@ROUTINE OUT A,CARRY,ZERO CLOBBERS SIGN,PARITY,HALFCARRY,B,DE,HL
GX_VAR16:
    CALL GX_VAR8
    CALL EM_ENDOP
    DB   $3B

;@ROUTINE OUT A,CARRY,ZERO CLOBBERS SIGN,PARITY,HALFCARRY,B,C,DE,HL
GX_NUM16:
    CALL EM_READB
    LD   C,A
    CALL EM_READB
    LD   H,A
    LD   L,C
    LD   A,$21                     ; LD HL,nn
;@ROUTINE IN A,HL OUT A,CARRY,ZERO CLOBBERS SIGN,PARITY,HALFCARRY,B,C,DE,HL
GX_FETCH:
    CALL EM_OPW
    CALL EM_ENDOP
    DB   $E5                       ; PUSH HL

;@ROUTINE OUT A,CARRY,ZERO CLOBBERS SIGN,PARITY,HALFCARRY,B,C,D,DE,HL,IX,IY
GX_LD8:
    CALL EM_READA
    LD   A,$3A                     ; LD A,(nn)
    CALL EM_OPW
    LD   HL,GT_ATOHL
    JP   EM_FOUR

;@ROUTINE OUT A,CARRY,ZERO CLOBBERS SIGN,PARITY,HALFCARRY,B,C,D,DE,HL,IX,IY
GX_LD16:
    CALL EM_READA
    LD   A,$2A                     ; LD HL,(nn)
    JR   GX_FETCH

; C receives -(byte offset + 1), the displacement of the low byte from IX.
;@ROUTINE OUT A,C,CARRY,ZERO CLOBBERS SIGN,PARITY,HALFCARRY,B,D,DE,HL
GX_LOCAL:
    CALL EM_READB
    CPL
    LD   C,A
    OR   A
    RET

;@ROUTINE IN C,HL OUT A,C,CARRY,ZERO CLOBBERS SIGN,PARITY,HALFCARRY,B,D,DE,HL
GX_IXOP:
    LD   B,0
    PUSH BC
    LD   B,2
    CALL EM_BYTES
    POP  BC
    LD   A,C
    JP   EM_BYTE

;@ROUTINE OUT A,CARRY,ZERO CLOBBERS SIGN,PARITY,HALFCARRY,B,DE,HL
GX_POP:
    CALL EM_ENDOP
    DB   $E1                       ; POP HL

;@ROUTINE OUT A,C,CARRY,ZERO CLOBBERS SIGN,PARITY,HALFCARRY,B,D,DE,HL
GX_GETLO:
    CALL GX_LOCAL
    LD   HL,GT_LDLO
    JR   GX_IXOP

;@ROUTINE OUT A,CARRY,ZERO CLOBBERS SIGN,PARITY,HALFCARRY,B,C,D,DE,HL
GX_LDX8:
    CALL GX_GETLO
    LD   HL,GT_LTOHL
    JP   EM_THREE

;@ROUTINE OUT A,CARRY,ZERO CLOBBERS SIGN,PARITY,HALFCARRY,B,C,D,DE,HL
GX_LDX16:
    CALL GX_GETLO
    DEC  C
    LD   HL,GT_LDHI
    CALL GX_IXOP
    CALL EM_ENDOP
    DB   $E5

;@ROUTINE OUT A,CARRY,ZERO CLOBBERS SIGN,PARITY,HALFCARRY,B,DE,HL
GX_ARGS:
    LD   HL,GT_ARGS
    JP   EM_PAIR

;@ROUTINE OUT A,CARRY,ZERO CLOBBERS SIGN,PARITY,HALFCARRY,B,DE,HL
GX_PUSH:
    CALL EM_ENDOP
    DB   $E5

;@ROUTINE IN B,HL OUT A,CARRY,ZERO CLOBBERS SIGN,PARITY,HALFCARRY,B,C,DE,HL
GX_BINOP:
    PUSH BC
    PUSH HL
    CALL GX_ARGS
    POP  HL
    POP  BC
    CALL EM_BYTES
    JR   GX_PUSH

;@ROUTINE OUT A,CARRY,ZERO CLOBBERS SIGN,PARITY,HALFCARRY,B,C,DE,HL
GX_ADD8:
    LD   HL,GT_ADD8
    JR   GX_BIN8
;@ROUTINE OUT A,CARRY,ZERO CLOBBERS SIGN,PARITY,HALFCARRY,B,C,DE,HL
GX_SUB8:
    LD   HL,GT_SUB8
    JR   GX_BIN8
;@ROUTINE OUT A,CARRY,ZERO CLOBBERS SIGN,PARITY,HALFCARRY,B,C,DE,HL
GX_XOR8:
    LD   HL,GT_XOR8
    JR   GX_BIN8
;@ROUTINE OUT A,CARRY,ZERO CLOBBERS SIGN,PARITY,HALFCARRY,B,C,DE,HL
GX_AND8:
    LD   HL,GT_AND8
    JR   GX_BIN8
;@ROUTINE OUT A,CARRY,ZERO CLOBBERS SIGN,PARITY,HALFCARRY,B,C,DE,HL
GX_OR8:
    LD   HL,GT_OR8
;@ROUTINE IN HL OUT A,CARRY,ZERO CLOBBERS SIGN,PARITY,HALFCARRY,B,C,DE,HL
GX_BIN8:
    LD   B,5
    JR   GX_BINOP

;@ROUTINE OUT A,CARRY,ZERO CLOBBERS SIGN,PARITY,HALFCARRY,B,C,DE,HL
GX_XOR16:
    LD   HL,GT_XOR16
    JR   GX_BIN16
;@ROUTINE OUT A,CARRY,ZERO CLOBBERS SIGN,PARITY,HALFCARRY,B,C,DE,HL
GX_AND16:
    LD   HL,GT_AND16
    JR   GX_BIN16
;@ROUTINE OUT A,CARRY,ZERO CLOBBERS SIGN,PARITY,HALFCARRY,B,C,DE,HL
GX_OR16:
    LD   HL,GT_OR16
;@ROUTINE IN HL OUT A,CARRY,ZERO CLOBBERS SIGN,PARITY,HALFCARRY,B,C,DE,HL
GX_BIN16:
    LD   B,6
    JR   GX_BINOP

;@ROUTINE OUT A,CARRY,ZERO CLOBBERS SIGN,PARITY,HALFCARRY,B,C,DE,HL
GX_ADD16:
    LD   HL,GT_ADD16
    LD   B,1
    JR   GX_BINOP
;@ROUTINE OUT A,CARRY,ZERO CLOBBERS SIGN,PARITY,HALFCARRY,B,C,DE,HL
GX_SUB16:
    LD   HL,GT_SUB16
    LD   B,3
    JR   GX_BINOP

;@ROUTINE OUT A,CARRY,ZERO CLOBBERS SIGN,PARITY,HALFCARRY,B,C,DE,HL
GX_MUL8:
    CALL GX_MULOP
    CALL EM_IDIOM
    DB   EP_ZEROH
    JR   GX_PUSH
;@ROUTINE OUT A,CARRY,ZERO CLOBBERS SIGN,PARITY,HALFCARRY,B,C,DE,HL
GX_MUL16:
    CALL GX_MULOP
    JR   GX_PUSH
;@ROUTINE OUT A,CARRY,ZERO CLOBBERS SIGN,PARITY,HALFCARRY,B,C,DE,HL
GX_MULOP:
    CALL GX_ARGS
    LD   DE,RT_MUL16
    JP   EM_HELP

; Emit a call whose carry-clear success path must skip a generated failure
; outcome. DE returns the branch operand for the caller to patch.
;@ROUTINE IN HL OUT A,DE,CARRY,ZERO CLOBBERS SIGN,PARITY,HALFCARRY,B,C,HL
.TRYCALL:
    CALL EM_CALL
    JP   EM_JRNC

;@ROUTINE IN DE OUT A,DE,CARRY,ZERO CLOBBERS SIGN,PARITY,HALFCARRY,B,C,HL
GX_TRY:
    CALL EM_HELP
    JP   EM_JRNC

;@ROUTINE OUT A,DE,HL,CARRY,ZERO CLOBBERS SIGN,PARITY,HALFCARRY
GX_NOTE:
    CALL EM_READW
    LD   (GX_POS),DE
    RET

;@ROUTINE IN DE OUT A,CARRY,ZERO CLOBBERS SIGN,PARITY,HALFCARRY,B,C,DE,HL
GX_ARM:
    LD   (EM_XFIX),DE
    LD   HL,(GX_POS)
    JP   EM_LDHL

;@ROUTINE OUT A,CARRY,ZERO CLOBBERS SIGN,PARITY,HALFCARRY,B,C,DE,HL,IX,IY
GX_DIV8:
    LD   C,1
    JR   GX_DIVOP
;@ROUTINE OUT A,CARRY,ZERO CLOBBERS SIGN,PARITY,HALFCARRY,B,C,DE,HL,IX,IY
GX_DIV16:
    LD   C,0
    JR   GX_DIVOP
;@ROUTINE OUT A,CARRY,ZERO CLOBBERS SIGN,PARITY,HALFCARRY,B,C,DE,HL,IX,IY
GX_MOD8:
    LD   C,3
    JR   GX_DIVOP
;@ROUTINE OUT A,CARRY,ZERO CLOBBERS SIGN,PARITY,HALFCARRY,B,C,DE,HL
GX_MOD16:
    LD   C,2
GX_DIVOP:
    CALL GX_NOTE
    LD   A,C
    LD   (GX_WIDTH),A
    CALL GX_ARGS
    LD   DE,RT_DIV16
    LD   A,(GX_WIDTH)
    BIT  1,A
    JR   Z,.HELPER
    LD   DE,RT_MOD16
.HELPER:
    CALL GX_TRY
    LD   A,3
    CALL GX_TRAP
    LD   A,(GX_WIDTH)
    AND  1
    JR   Z,.RESULT
    CALL EM_IDIOM
    DB   EP_ZEROH
.RESULT:
    JP   GX_PUSH

;@ROUTINE OUT A,CARRY,ZERO CLOBBERS SIGN,PARITY,HALFCARRY,B,C,DE,HL,IX,IY
GX_NEG8:
    LD   HL,GT_NEG8
    LD   B,6
    JR   GX_UNARY
;@ROUTINE OUT A,CARRY,ZERO CLOBBERS SIGN,PARITY,HALFCARRY,B,C,DE,HL,IX,IY
GX_NEG16:
    LD   HL,GT_NEG16
    LD   B,8
    JR   GX_UNARY
;@ROUTINE OUT A,CARRY,ZERO CLOBBERS SIGN,PARITY,HALFCARRY,B,C,DE,HL,IX,IY
GX_NOT8:
    LD   HL,GT_NOT8
    LD   B,6
    JR   GX_UNARY
;@ROUTINE OUT A,CARRY,ZERO CLOBBERS SIGN,PARITY,HALFCARRY,B,C,DE,HL,IX,IY
GX_NOT16:
    LD   HL,GT_NOT16
    LD   B,7
    JR   GX_UNARY
;@ROUTINE OUT A,CARRY,ZERO CLOBBERS SIGN,PARITY,HALFCARRY,B,C,DE,HL
GX_FLIP:
    LD   HL,GT_FLIP
    LD   B,7
GX_UNARY:
    CALL EM_BYTES
    JP   GX_PUSH

;@ROUTINE IN A OUT A,CARRY,ZERO CLOBBERS SIGN,PARITY,HALFCARRY,B,C,DE,HL
GX_TEST:
    CALL EM_LDA
    LD   DE,RT_CMP16
    JP   EM_HELP

;@ROUTINE OUT A,CARRY,ZERO CLOBBERS SIGN,PARITY,HALFCARRY,B,C,DE,HL
GX_RELOP:
    CALL EM_READB
    LD   C,A
    PUSH BC
    CALL GX_ARGS
    POP  BC
    LD   A,C
    CALL GX_TEST
    JP   GX_PUSH

;@ROUTINE OUT A,CARRY,ZERO CLOBBERS SIGN,PARITY,HALFCARRY,B,C,DE,HL
GX_FIT8:
    CALL GX_NOTE
    CALL GX_POP
    CALL EM_IDIOM
    DB   EP_TESTH
    LD   A,$28                     ; JR Z,success
    CALL EM_JRCC
    LD   A,2
    CALL GX_TRAP
    JP   GX_PUSH

;@ROUTINE OUT A,CARRY,ZERO CLOBBERS SIGN,PARITY,HALFCARRY,B,C,D,DE,HL,IX,IY
GX_ST8:
    CALL EM_READA
    PUSH HL
    CALL EM_IDIOM
    DB   EP_POPA
    POP  HL
    LD   A,$32
    JP   EM_OPW
;@ROUTINE OUT A,CARRY,ZERO CLOBBERS SIGN,PARITY,HALFCARRY,B,C,D,DE,HL,IX,IY
GX_ST16:
    CALL EM_READA
    PUSH HL
    CALL GX_POP
    POP  HL
    LD   A,$22
    JP   EM_OPW

;@ROUTINE OUT A,C,CARRY,ZERO CLOBBERS SIGN,PARITY,HALFCARRY,B,D,DE,HL
GX_STX8:
    CALL GX_LOCAL
    CALL GX_POP
    LD   HL,GT_STLO
    JP   GX_IXOP
;@ROUTINE OUT A,CARRY,ZERO CLOBBERS SIGN,PARITY,HALFCARRY,B,C,D,DE,HL
GX_STX16:
    CALL GX_STX8
    DEC  C
    LD   HL,GT_STHI
    JP   GX_IXOP

;@ROUTINE OUT A,CARRY,ZERO CLOBBERS SIGN,PARITY,HALFCARRY,B,C,DE,HL
GX_WRITE:
    CALL GX_NOTE
    CALL EM_IDIOM
    DB   EP_POPA
    LD   A,1
    CALL EM_CALLV
    CALL EM_JRNC
    CALL GX_ARM
    CALL EM_STRAY
    JR   GX_FIRE

; Every terminal typed-expression trap must dismantle the routine frame before
; emitting the common trap record and RET. Without this epilogue the generated
; return consumes local bytes or the saved IX value as its return address.
;@ROUTINE OUT A,CARRY,ZERO CLOBBERS SIGN,PARITY,HALFCARRY,B,C,DE,HL
GX_ABORT:
    CALL GX_RESET
    CALL EM_OP
    DB   $F5                       ; PUSH AF, preserve trap reason
    CALL EM_OP
    DB   $AF                       ; XOR A
    LD   DE,RT_DEPTH-RT_BASE
    CALL EM_TOVAR
    CALL EM_OP
    DB   $F1                       ; POP AF
    JP   EM_TRAP

; Emit the common terminal trap body for source position HL and trap code A.
; The caller owns and patches the conditional branch around this terminal path.
;@ROUTINE IN A,HL OUT A,CARRY,ZERO CLOBBERS SIGN,PARITY,HALFCARRY,B,C,DE,HL
GX_RAISE:
    PUSH AF
    CALL EM_LDHL
    POP  AF
    CALL EM_LDA
    JR   GX_ABORT

; Emit and patch a terminal trap using the retained typed-expression source
; position. A is the trap code and DE the success-branch operand.
;@ROUTINE IN A,DE OUT A,CARRY,ZERO CLOBBERS SIGN,PARITY,HALFCARRY,B,C,DE,HL
GX_TRAP:
    PUSH AF
    CALL GX_ARM
    POP  AF
    CALL EM_LDA

;@ROUTINE OUT A,CARRY,ZERO CLOBBERS SIGN,PARITY,HALFCARRY,B,C,DE,HL
GX_FIRE:
    CALL GX_ABORT
    LD   DE,(EM_XFIX)
    JP   EM_LAND

; Save the outer machine frame before main allocates locals, and restore that
; exact frame on every terminal trap, including a trap inside recursive calls.
;@ROUTINE OUT A,CARRY,ZERO CLOBBERS SIGN,PARITY,HALFCARRY,B,C,DE,HL
GX_SAVE:
    LD   HL,GT_STSP
    JR   GX_ROOT

;@ROUTINE OUT A,CARRY,ZERO CLOBBERS SIGN,PARITY,HALFCARRY,B,C,DE,HL
GX_RESET:
    LD   HL,GT_LDSP
;@ROUTINE IN HL OUT A,CARRY,ZERO CLOBBERS SIGN,PARITY,HALFCARRY,B,C,DE,HL
GX_ROOT:
    PUSH HL
    CALL EM_PAIR
    POP  HL
    PUSH HL
    LD   DE,RT_SP-RT_BASE
    CALL TG_VAR
    CALL EM_WORD
    POP  HL
    INC  HL
    INC  HL
    CALL EM_PAIR
    LD   DE,RT_IX-RT_BASE
    CALL TG_VAR
    JP   EM_WORD

; Begin the single retained value routine. Operand bytes are routine ordinal
; and parameter type. HL carries the copied argument into this entry.
;@ROUTINE OUT A,CARRY,ZERO CLOBBERS SIGN,PARITY,HALFCARRY,B,C,D,DE,HL,IX,IY
GX_ENTER:
    CALL EM_READB
    CALL EM_READB
    LD   (GX_WIDTH),A
    LD   C,CT_RDEST
    CALL GC_PLACE
    LD   HL,GT_ENTER
    CALL EM_EIGHT
    LD   A,(GX_WIDTH)
    CP   SY_U16
    LD   HL,GT_NEW8
    LD   B,4
    JR   NZ,.PARAM
    LD   HL,GT_NEW16
    LD   B,8
.PARAM:
    JP   EM_BYTES

; Evaluate has already left the copied argument as one canonical carrier.
; Claim activation capacity before the callee begins, then call the fixed
; forward label. The result returns in HL and becomes the enclosing carrier.
;@ROUTINE OUT A,CARRY,ZERO CLOBBERS SIGN,PARITY,HALFCARRY,B,C,D,DE,HL,IX,IY
GX_CALL:
    CALL EM_READB                  ; ordinal
    CALL EM_READB                  ; result type
    LD   (GX_WIDTH),A
    CALL GX_NOTE
    CALL GX_POP                    ; argument
    LD   DE,RT_CLAIM
    CALL GX_TRY
    LD   A,5
    CALL GX_TRAP
    LD   C,CT_RDEST
    LD   A,$CD                     ; CALL nn
    CALL GC_OPREF
    LD   DE,RT_FREE
    CALL EM_HELP
    CALL EM_ENDOP
    DB   $E5                       ; PUSH HL result carrier

;@ROUTINE OUT A,CARRY,ZERO CLOBBERS SIGN,PARITY,HALFCARRY,B,DE,HL
GX_RET:
    CALL GX_POP                    ; result
    CALL EM_LEAVE
    CALL EM_ENDOP
    DB   $C9

;@ROUTINE OUT A,CARRY,ZERO CLOBBERS SIGN,PARITY,HALFCARRY
GX_CLOSE:
    XOR  A
    RET

;@ROUTINE IN DE OUT A,CARRY,ZERO CLOBBERS SIGN,PARITY,HALFCARRY,B,C,DE,HL
GX_PUTJR:
    LD   A,(GX_BCNT)
    CP   GX_BCAP
    JP   NC,GX_FULL
    LD   C,A
    LD   B,0
    LD   HL,GX_BBASE
    ADD  HL,BC
    ADD  HL,BC
    LD   (HL),E
    INC  HL
    LD   (HL),D
    LD   A,(GX_BCNT)
    INC  A
    LD   (GX_BCNT),A
    OR   A
    RET

;@ROUTINE OUT A,CARRY,ZERO,DE CLOBBERS SIGN,PARITY,HALFCARRY,B,C,HL
GX_GETJR:
    LD   A,(GX_BCNT)
    OR   A
    JP   Z,GX_BADOP
    DEC  A
    LD   (GX_BCNT),A
    LD   C,A
    LD   B,0
    LD   HL,GX_BBASE
    ADD  HL,BC
    ADD  HL,BC
    LD   E,(HL)
    INC  HL
    LD   D,(HL)
    OR   A
    RET

;@ROUTINE OUT A,CARRY,ZERO CLOBBERS SIGN,PARITY,HALFCARRY,B,C,DE,HL,IX,IY
GX_ANDIF:
    LD   HL,GT_ANDIF
    LD   B,6
    JR   GX_SHORT
;@ROUTINE OUT A,CARRY,ZERO CLOBBERS SIGN,PARITY,HALFCARRY,B,C,DE,HL
GX_ORIF:
    LD   HL,GT_ORIF
    LD   B,6
GX_SHORT:
    CALL EM_BYTES
    CALL EM_JR
    JR   GX_PUTJR

;@ROUTINE OUT A,CARRY,ZERO CLOBBERS SIGN,PARITY,HALFCARRY,B,C,DE,HL
GX_JOIN:
    CALL GX_GETJR
    JP   EM_LAND

;@ROUTINE OUT A,CARRY,ZERO CLOBBERS SIGN,PARITY,HALFCARRY,B,C,DE,HL,IX,IY
GX_EXIT:
    LD   A,(GX_BCNT)
    OR   A
    JP   NZ,GX_BADOP
    CALL EM_LEAVE
    JP   EM_DONE

; Entry point used by the typed-expression proof.
GX_BEG:

GT_LDIR: DB   $ED,$B0              ; LDIR
