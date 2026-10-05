; Stage 7 direct-Z80 lowering for opaque aggregate carriers. Every source
; scalar and alias carrier occupies one canonical word on the evaluation
; stack; declared storage widths remain unchanged.

;@ROUTINE OUT A,CARRY,ZERO CLOBBERS SIGN,PARITY,HALFCARRY,B,C,D,DE,HL,IX
RG_ENTER:
    CALL EM_READB
    LD   C,A
    CALL EM_READB                  ; retained parameter count
    CALL EM_READB                  ; target bank
    PUSH BC
    CALL TG_PICK
    POP  BC
RG_FRAME:
    CALL GC_PLACE
    LD   HL,GT_ENTER
    JP   EM_EIGHT

; Operands are exact type, negative-frame byte offset, and positive caller
; displacement. The prologue copies one canonical argument into this
; activation before any body statement runs.
;@ROUTINE OUT A,CARRY,ZERO CLOBBERS SIGN,PARITY,HALFCARRY,B,C,D,DE,HL
RG_BIND:
    CALL EM_READB
    LD   (RO_OTYPE),A
    CALL EM_READB
    CPL
    LD   (RO_OPOS),A               ; -(destination + 1)
    CALL EM_READB
    LD   (RO_AIDX),A               ; positive source displacement
    LD   A,(RO_OTYPE)
    CP   AG_VIEW
    JR   Z,.OPEN
    CP   AG_FIRST
    JR   NC,.WORD
    CP   SY_U16
    JR   Z,.WORD
    CALL EM_OP
    DB   $3B                       ; DEC SP
    LD   HL,GT_LDLO
    CALL .FROMARG
    LD   HL,GT_STLO
    JR   .TOLOCAL
.OPEN:
    CALL EM_OP
    DB   $3B                       ; third activation byte
.WORD:
    CALL EM_IDIOM
    DB   EP_DECSP
    LD   HL,GT_LDLO
    CALL .FROMARG
    CALL EM_IDIOM
    DB   EP_LDHI
    LD   A,(RO_AIDX)
    INC  A
    CALL EM_BYTE
    LD   HL,GT_STLO
    CALL .TOLOCAL
    CALL EM_IDIOM
    DB   EP_STHI
    LD   A,(RO_OPOS)
    DEC  A
    CALL EM_BYTE
    LD   A,(RO_OTYPE)
    CP   AG_VIEW
    JR   Z,.CAPACITY
    OR   A
    RET
.CAPACITY:
    CALL EM_IDIOM
    DB   EP_LDLO
    LD   A,(RO_AIDX)
    INC  A
    INC  A
    CALL EM_BYTE
    CALL EM_IDIOM
    DB   EP_STLO
    LD   A,(RO_OPOS)
    DEC  A
    DEC  A
    JP   EM_BYTE

;@ROUTINE IN HL OUT A,CARRY,ZERO CLOBBERS SIGN,PARITY,HALFCARRY,B,C,DE,HL
.FROMARG:
    CALL EM_PAIR
    LD   A,(RO_AIDX)
    JP   EM_BYTE

;@ROUTINE IN HL OUT A,CARRY,ZERO CLOBBERS SIGN,PARITY,HALFCARRY,B,C,DE,HL
.TOLOCAL:
    CALL EM_PAIR
    LD   A,(RO_OPOS)
    JP   EM_BYTE

; Emit a bounds trap after a target helper has returned carry. The branch
; around the trap is patched before normal lowering continues.
;@ROUTINE OUT A,CARRY,ZERO CLOBBERS SIGN,PARITY,HALFCARRY,B,C,D,DE,HL
RG_GUARD:
    CALL EM_JRNC
    LD   (EM_FFIX),DE
    LD   HL,(RO_DPOS)
    LD   A,1
    CALL GX_RAISE
    LD   DE,(EM_FFIX)
    JP   EM_LAND

;@ROUTINE OUT A,DE,HL,CARRY,ZERO CLOBBERS SIGN,PARITY,HALFCARRY
RG_NOTE:
    CALL EM_READW
    LD   (RO_DPOS),DE
    RET

;@ROUTINE OUT A,CARRY,ZERO CLOBBERS SIGN,PARITY,HALFCARRY,B,DE,HL
RG_RULES:
    LD   DE,RG_MODE
    LD   B,3
.LOOP:
    CALL EM_READB                  ; mode, handler, retained carriers
    LD   (DE),A
    INC  DE
    DJNZ .LOOP
    RET

; Retain the source position of a propagated failure. The root wrapper uses
; the last propagation site when failure finally leaves callable main.
;@ROUTINE OUT A,CARRY,ZERO CLOBBERS SIGN,PARITY,HALFCARRY,B,C,DE,HL
RG_MARK:
    LD   HL,(RO_DPOS)
    CALL EM_LDHL
    LD   DE,RT_TPOS-RT_BASE
    CALL TG_VAR
    LD   A,$22                     ; LD (nn),HL
    JP   EM_OPW

;@ROUTINE OUT A,CARRY,ZERO CLOBBERS SIGN,PARITY,HALFCARRY,B,C,D,DE,HL,IX,IY
RG_CALL:
    CALL EM_READB
    LD   (RO_DEST),A
    AND  RO_FIO
    JR   NZ,.SERVICE
    CALL EM_READB
    LD   (RO_ACNT),A
    CALL EM_READB
    LD   (RO_DTYPE),A
    CALL EM_READB
    LD   (RG_FLAGS),A
    JR   .COMMON
.SERVICE:
    LD   A,(RO_DEST)
    AND  RO_RES8
    RLCA
    RLCA
    RLCA
    LD   (RO_DTYPE),A
.COMMON:
    CALL RG_NOTE
    CALL RG_RULES
    LD   A,(RO_DEST)
    AND  RO_FIO
    JP   NZ,RG_SERVE
    LD   DE,RT_CLAIM
    CALL GX_TRY
    LD   (EM_XFIX),DE
    LD   HL,(RO_DPOS)
    LD   A,5
    CALL GX_RAISE
    LD   DE,(EM_XFIX)
    CALL EM_LAND
    LD   A,(RO_DEST)
    AND  RO_LMASK
    LD   C,A
    CALL .ROUTINE
    LD   A,(RG_FLAGS)
    AND  RO_FFAIL
    JR   NZ,.CANFAIL
    LD   DE,RT_FREE
    CALL EM_HELP
    JR   RG_AFTER

; Emit an ordinary local CALL when the target routine shares the current bank.
; A cross-bank call supplies destination bank A and address HL to vector 9;
; the adapter switches, calls, restores the caller bank, and preserves the
; ordinary source-routine result/failure ABI.
;@ROUTINE IN C OUT A,CARRY,ZERO CLOBBERS SIGN,PARITY,HALFCARRY,B,C,D,DE,HL,IX,IY
.ROUTINE:
    LD   A,(RG_FLAGS)
    CALL TG_SPLIT
    LD   D,A
    LD   A,(TG_OBANK)
    CP   D
    JR   NZ,.FAR
    LD   A,$CD
    JP   GC_OPREF
.FAR:
    PUSH BC
    PUSH DE
    LD   C,D
    LD   A,$3E                     ; LD A,destination bank
    CALL EM_OPB
    POP  DE
    POP  BC
    LD   A,$21                     ; LD HL,target address
    CALL GC_OPFAR
    LD   A,9                       ; far-call vector ordinal
    JP   EM_CALLV
.CANFAIL:
    CALL EM_OP
    DB   $F5                       ; PUSH AF result discriminant/code
    LD   DE,RT_FREE
    CALL EM_HELP
    CALL EM_OP
    DB   $F1                       ; POP AF
RG_FORK:
    CALL EM_JRNC
    LD   (EM_XFIX),DE
    CALL RG_ONERR
.JOIN:
    LD   DE,(EM_XFIX)
    CALL EM_LAND
RG_AFTER:
    LD   A,(RO_ACNT)
    LD   C,A
    CALL RG_DROP
    LD   A,(RO_DTYPE)
    OR   A
    RET  Z
    LD   A,(RO_DEST)
    AND  RO_FKEEP
    RET  Z
    LD   A,(RO_DEST)
    AND  RO_FIO
    JR   NZ,.SERVICE
    CALL EM_ENDOP
    DB   $E5                       ; PUSH HL result carrier
.SERVICE:
    LD   HL,GT_ATOHL
    JP   EM_FOUR

;@ROUTINE IN C OUT A,C,CARRY,ZERO CLOBBERS SIGN,PARITY,HALFCARRY,B,D,DE,HL
RG_DROP:
    LD   A,C
    OR   A
    RET  Z
.DISCARD:
    CALL EM_OP
    DB   $D1                       ; POP DE carrier
    DEC  C
    JR   RG_DROP

RG_RET EQU  GX_RET

; Failable completion uses carry plus A privately: carry clear denotes success;
; carry set carries one u8 error code in A. Source code cannot inspect this ABI.
;@ROUTINE OUT A,CARRY,ZERO CLOBBERS SIGN,PARITY,HALFCARRY,B,C,D,DE,HL,IX,IY
RG_FAIL:
    CALL RG_NOTE
    CALL RG_MARK
    CALL EM_IDIOM
    DB   EP_POPA
    JR   RG_BAIL

;@ROUTINE OUT A,CARRY,ZERO CLOBBERS SIGN,PARITY,HALFCARRY,B,C,D,DE,HL
RG_FATAL:
    CALL RG_NOTE
    CALL EM_IDIOM
    DB   EP_POPA
    LD   HL,(RO_DPOS)
    CALL EM_LDHL
    CALL EM_STRAY
    JP   GX_ABORT

;@ROUTINE OUT A,CARRY,ZERO CLOBBERS SIGN,PARITY,HALFCARRY,B,C,D,DE,HL,IX,IY
RG_RETOK:
    CALL GX_POP                    ; result carrier
    JR   RG_PASS

;@ROUTINE OUT A,CARRY,ZERO CLOBBERS SIGN,PARITY,HALFCARRY,B,C,D,DE,HL
RG_ENDOK:
    CALL EM_READB
    OR   A
    RET  NZ
RG_PASS:
    CALL EM_LEAVE
    LD   HL,GT_PASS
    JP   EM_PAIR

;@ROUTINE OUT A,CARRY,ZERO CLOBBERS SIGN,PARITY,HALFCARRY,B,C,D,DE,HL
RG_SKIP:
    CALL EM_READB
    LD   C,A
    LD   A,$C3
    JP   GC_OPREF

;@ROUTINE OUT A,CARRY,ZERO CLOBBERS SIGN,PARITY,HALFCARRY,B,C,D,DE,HL,IX,IY
RG_CATCH:
    CALL EM_READB
    LD   C,A
    CALL GC_PLACE
    CALL EM_READB
    LD   (RG_FLAGS),A
    LD   HL,GT_ATOHL
    CALL EM_FOUR
    LD   A,(RG_FLAGS)
    AND  SY_CMASK
    CP   SY_GLOB
    JP   Z,GX_ST8
    JP   GX_STX8

;@ROUTINE OUT A,CARRY,ZERO CLOBBERS SIGN,PARITY,HALFCARRY,B,C,D,DE,HL
RG_JOIN:
    CALL EM_READB
    LD   C,A
    JP   GC_PLACE

;@ROUTINE OUT A,CARRY,ZERO CLOBBERS SIGN,PARITY,HALFCARRY,B,C,D,DE,HL,IX,IY
RG_ONERR:
    LD   A,(RG_MODE)
    OR   A
    JP   Z,GX_BADOP
    CP   RO_MTRAP
    JR   Z,RG_THROW
    CALL RG_MARK
RG_BAIL:
    CALL EM_LEAVE
    LD   HL,GT_BAIL
    JP   EM_PAIR
RG_THROW:
    CALL EM_OP
    DB   $4F                       ; LD C,A error code
    LD   A,(RO_ACNT)
    LD   HL,RG_KEPT
    ADD  A,(HL)
    LD   C,A
    CALL RG_DROP
    CALL EM_OP
    DB   $79                       ; LD A,C
    LD   A,(RG_HDEST)
    LD   C,A
    LD   A,$C3
    JP   GC_OPREF

;@ROUTINE OUT A,CARRY,ZERO CLOBBERS SIGN,PARITY,HALFCARRY,B,C,D,DE,HL,IX,IY
RG_SERVE:
    LD   A,(RO_DEST)
    AND  RO_AMASK
    JR   Z,.VECTOR
    CP   RO_ARG16
    JR   Z,.WORD
    CALL EM_IDIOM
    DB   EP_POPA
    JR   .VECTOR
.WORD:
    CALL GX_POP                    ; offset
.VECTOR:
    LD   A,(RO_DEST)
    AND  RO_SMASK
    CALL EM_CALLV
    XOR  A
.NOARG:
    LD   (RO_ACNT),A
    JP   RG_FORK

; Startup is a terminal wrapper around main's ordinary callable body. The
; source body therefore has the same frame, return, recursion, and failure ABI
; as every other result-free routine; only this wrapper converts final failure
; into unhandled-error and final success into host completion.
;@ROUTINE OUT A,CARRY,ZERO CLOBBERS SIGN,PARITY,HALFCARRY,B,C,D,DE,HL,IX,IY
RG_MAIN:
    CALL EM_READB
    LD   (RG_FLAGS),A
    CALL EM_READB
    CALL TG_PICK
    CALL GX_START
    LD   C,RO_MDEST
    LD   A,$CD
    CALL GC_OPREF
    LD   A,(RG_FLAGS)
    AND  RO_FFAIL
    JR   Z,.PASS
    CALL EM_JRNC
    LD   (EM_XFIX),DE
    CALL EM_OP
    DB   $F5                       ; PUSH AF
    LD   DE,RT_TPOS-RT_BASE
    CALL TG_VAR
    LD   A,$2A                     ; LD HL,(nn)
    CALL EM_OPW
    LD   A,$F1                     ; POP AF
    CALL EM_BYTE
    CALL EM_STRAY
    CALL GX_ABORT
    LD   DE,(EM_XFIX)
    CALL EM_LAND
.PASS:
    CALL GX_RESET
    CALL EM_DONE
    LD   C,RO_MDEST
    JP   RG_FRAME

;@ROUTINE OUT A,CARRY,ZERO CLOBBERS SIGN,PARITY,HALFCARRY,B,C,D,DE,HL
RG_CLOSE:
    CALL EM_READB
    OR   A
    RET  NZ
    CALL EM_LEAVE
    CALL EM_ENDOP
    DB   $C9

;@ROUTINE OUT A,CARRY,ZERO CLOBBERS SIGN,PARITY,HALFCARRY,B,C,D,DE,HL,IX,IY
RG_GLOB:
    CALL EM_READA
    JR   RG_REF

;@ROUTINE OUT A,CARRY,ZERO CLOBBERS SIGN,PARITY,HALFCARRY,B,C,D,DE,HL,IX,IY
RG_CONST:
    CALL EM_READW
    LD   HL,(TG_ROPOS)
    ADD  HL,DE
RG_REF:
    LD   A,$21                     ; LD HL,nn
    JP   GX_FETCH

RG_PARAM EQU  GX_LDX16

;@ROUTINE OUT A,CARRY,ZERO CLOBBERS SIGN,PARITY,HALFCARRY,B,C,D,DE,HL
RG_FIELD:
    CALL EM_READW
    LD   (RO_OPOS),DE
    CALL EM_IDIOM
    DB   EP_FIELD
    LD   HL,(RO_OPOS)
    CALL EM_WORD
    LD   HL,GT_ADDDE
    JP   EM_PAIR

;@ROUTINE OUT A,CARRY,ZERO CLOBBERS SIGN,PARITY,HALFCARRY,B,C,D,DE,HL
RG_INDEX:
    CALL EM_READW
    LD   (RO_OPOS),DE              ; length
    CALL RG_SPAN                   ; stride and source position
    CALL EM_IDIOM
    DB   EP_ARGS
    LD   HL,(RO_OPOS)
    CALL EM_LDBC
    LD   DE,RT_IDXOK
    CALL EM_HELP
    CALL RG_GUARD
    CALL EM_OP
    DB   $E5                       ; retain base
    LD   HL,(RO_OSIZE)
    LD   A,$21                     ; LD HL,nn stride
    CALL EM_OPW
    LD   DE,RT_MUL16
    CALL EM_HELP
    LD   HL,GT_INDEX
    JP   EM_THREE

;@ROUTINE OUT A,CARRY,ZERO CLOBBERS SIGN,PARITY,HALFCARRY,B,C,D,DE,HL
RG_GET8:
    LD   HL,GT_GETA
    LD   B,6
    JP   EM_BYTES
;@ROUTINE OUT A,CARRY,ZERO CLOBBERS SIGN,PARITY,HALFCARRY,B,C,D,DE,HL
RG_GET16:
    LD   HL,GT_GET16
    JP   EM_FIVE
;@ROUTINE OUT A,CARRY,ZERO CLOBBERS SIGN,PARITY,HALFCARRY,B,C,D,DE,HL
RG_PUT8:
    LD   HL,GT_PUT8
    JP   EM_THREE
;@ROUTINE OUT A,CARRY,ZERO CLOBBERS SIGN,PARITY,HALFCARRY,B,C,D,DE,HL
RG_PUT16:
    LD   HL,GT_PUT16
    JP   EM_FIVE

; Both full-region calls complete before LDIR is emitted. A failed first or
; second check reaches bounds with the destination still untouched.
;@ROUTINE OUT A,CARRY,ZERO CLOBBERS SIGN,PARITY,HALFCARRY,B,C,D,DE,HL,IX,IY
RG_COPY:
    CALL RG_SPAN
    LD   HL,GT_ARGS
    CALL EM_FOUR
    CALL RG_FIT
    CALL RG_HOLD
    CALL EM_IDIOM
    DB   EP_ARGSX
    LD   HL,(RO_OSIZE)
    CALL EM_LDBC
    LD   HL,GT_BLOCK
    JP   EM_PAIR

;@ROUTINE OUT A,DE,HL,CARRY,ZERO CLOBBERS SIGN,PARITY,HALFCARRY
RG_SPAN:
    CALL EM_READW
    LD   (RO_OSIZE),DE
    JP   RG_NOTE

;@ROUTINE OUT A,CARRY,ZERO CLOBBERS SIGN,PARITY,HALFCARRY,B,C,D,DE,HL
RG_HOLD:
    CALL GX_POP                    ; source
    CALL EM_OP
    DB   $E5                       ; retain source

;@ROUTINE OUT A,CARRY,ZERO CLOBBERS SIGN,PARITY,HALFCARRY,B,C,D,DE,HL
RG_FIT:
    CALL RG_FENCE
    LD   HL,(RO_OSIZE)
    CALL EM_LDBC
    JR   RG_DOFIT

;@ROUTINE OUT A,CARRY,ZERO CLOBBERS SIGN,PARITY,HALFCARRY,B,C,D,DE,HL
RG_FENCE:
    LD   DE,(TG_ROPOS)
    CALL EM_LDDE
    LD   HL,(TG_ROCAP)
    PUSH HL
    LD   A,$FD
    CALL EM_BYTE
    POP  HL
    LD   A,$21
    CALL EM_OPW
    RET

;@ROUTINE OUT A,CARRY,ZERO CLOBBERS SIGN,PARITY,HALFCARRY,B,C,D,DE,HL
RG_DOFIT:
    LD   DE,RT_RNGOK
    CALL EM_HELP
    JP   RG_GUARD

;@ROUTINE OUT A,DE,CARRY,ZERO CLOBBERS SIGN,PARITY,HALFCARRY,HL
RG_STROP:
    CALL EM_READB
    LD   (RO_ACNT),A
    LD   L,A
    LD   H,0
    INC  HL
    INC  HL
    LD   (RO_OSIZE),HL
    JP   RG_NOTE

;@ROUTINE OUT A,CARRY,ZERO CLOBBERS SIGN,PARITY,HALFCARRY,B,C,D,DE,HL
RG_LEN:
    CALL RG_STROP
    CALL RG_HOLD
    CALL GX_POP                    ; carrier
    LD   DE,RT_LENOK
    JP   RG_CHECK

;@ROUTINE OUT A,CARRY,ZERO CLOBBERS SIGN,PARITY,HALFCARRY,B,C,D,DE,HL
RG_CHAR:
    CALL RG_STROP
    CALL RG_SWAP
    CALL RG_FIT
    CALL EM_IDIOM
    DB   EP_ARGSX
    LD   DE,RT_CHROK
    JP   RG_CHECK

;@ROUTINE OUT A,CARRY,ZERO CLOBBERS SIGN,PARITY,HALFCARRY,B,C,D,DE,HL
RG_SWAP:
    CALL EM_IDIOM
    DB   EP_ARGS
    LD   HL,GT_SWAP
    JP   EM_PAIR

; Open string operations read the caller-supplied concrete capacity from the
; hidden activation byte. The ordinary source value remains one address path.
;@ROUTINE OUT A,DE,CARRY,ZERO CLOBBERS SIGN,PARITY,HALFCARRY,HL
OS_READ:
    CALL EM_READB
    LD   (RO_ACNT),A
    JP   RG_NOTE

;@ROUTINE OUT A,CARRY,ZERO CLOBBERS SIGN,PARITY,HALFCARRY,B,C,D,DE,HL
OS_LEN:
    CALL OS_READ
    CALL GX_POP
    CALL EM_OP
    DB   $E5                       ; retain carrier
    CALL OS_FIT
    CALL GX_POP
    LD   DE,RT_LENOK
    JR   OS_CHECK

;@ROUTINE OUT A,CARRY,ZERO CLOBBERS SIGN,PARITY,HALFCARRY,B,C,D,DE,HL
OS_CHAR:
    CALL OS_READ
    CALL RG_SWAP
    CALL OS_FIT
    CALL EM_IDIOM
    DB   EP_ARGSX
    LD   DE,RT_CHROK

;@ROUTINE IN DE OUT A,CARRY,ZERO CLOBBERS SIGN,PARITY,HALFCARRY,B,C,D,DE,HL
OS_CHECK:
    PUSH DE
    CALL OS_CAP
    POP  DE
    JR   RG_PROVE

;@ROUTINE IN DE OUT A,CARRY,ZERO CLOBBERS SIGN,PARITY,HALFCARRY,B,C,D,DE,HL
RG_PROVE:
    CALL EM_HELP
    CALL RG_GUARD
    CALL EM_ENDOP
    DB   $E5                       ; push length or addressed byte

; Emit BC = hidden concrete capacity + two representation bytes, then perform
; the ordinary complete-region guard before a generic string may be touched.
;@ROUTINE OUT A,CARRY,ZERO CLOBBERS SIGN,PARITY,HALFCARRY,B,C,D,DE,HL
OS_FIT:
    CALL RG_FENCE
    CALL OS_CAP
    LD   HL,GT_PLUS2
    CALL EM_FOUR
    JP   RG_DOFIT

;@ROUTINE OUT A,CARRY,ZERO CLOBBERS SIGN,PARITY,HALFCARRY,B,C,D,DE,HL
OS_CAP:
    LD   HL,GT_LDCIX
    JR   OS_CAPIX

;@ROUTINE IN HL OUT A,CARRY,ZERO CLOBBERS SIGN,PARITY,HALFCARRY,B,C,D,DE,HL
OS_CAPIX:
    CALL EM_PAIR
    LD   A,(RO_ACNT)
    CPL
    JP   EM_BYTE

; Convert a just-evaluated address carrier into the internal open-argument
; pair. Mode zero carries a static capacity; mode one forwards a hidden local.
;@ROUTINE OUT A,CARRY,ZERO CLOBBERS SIGN,PARITY,HALFCARRY,B,C,D,DE,HL,IX,IY
OS_ARG:
    CALL EM_READB
    LD   (RO_AIDX),A
    CALL EM_READB
    LD   (RO_ACNT),A
    CALL EM_OP
    DB   $D1                       ; POP DE address carrier
    LD   A,(RO_AIDX)
    OR   A
    JR   NZ,.FORWARD
    LD   A,(RO_ACNT)
    LD   L,A
    LD   H,0
    CALL EM_LDHL
    JR   .PAIR
.FORWARD:
    LD   HL,GT_LDLO
    CALL OS_CAPIX
    CALL EM_IDIOM
    DB   EP_ZEROH
.PAIR:
    LD   HL,GT_ARGS+2
    JP   EM_PAIR

;@ROUTINE IN DE OUT A,CARRY,ZERO CLOBBERS SIGN,PARITY,HALFCARRY,B,C,D,DE,HL
RG_CHECK:
    PUSH DE
    LD   A,(RO_ACNT)
    LD   C,A
    LD   A,$0E                     ; LD C,n capacity
    CALL EM_OPB
    POP  DE
    JR   RG_PROVE

.LDBN: DB   $06
GT_ADDA: DB   $5F,$16,$00,$19,$E5

GT_GET16: DB   $E1,$5E,$23,$56,$D5
GT_PUT16: DB   $D1,$E1,$73,$23,$72

GT_INDEX: DB   $D1,$19,$E5
GT_SWAP: DB   $D5,$E5

GT_LDCIX: DB   $DD,$4E

GT_PLUS2: DB   $06,$00,$03,$03
GT_BLOCK EQU  GT_LDIR

GT_ADDDE EQU  GT_ADDA+3

GT_PUT8 EQU  GT_PUT16
; POP HL / LD A,L prefix
GT_BAIL: DB   $37,$C9              ; SCF / RET
GT_PASS: DB   $B7,$C9              ; OR A / RET
; LD L,A / LD H,0 / PUSH HL
