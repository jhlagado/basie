; Predictive parser for the counted-loop and checked-array proof programs.

; Only the Stage 7 packed parser selects the complete grammar overlay. Nesting the
; Stage7LL1 reference keeps every older proof source independent of that flag.

;@ROUTINE NORETURN
DG_ISSUE:
    LD   (DG_CODE),A
    LD   A,(SRC_ID)
    LD   (DG_PART),A
    LD   HL,TK_POS
    LD   DE,DG_POS
    PUSH BC
    CALL PR_COPY
    POP  BC
    LD   SP,(PR_SP)
    SCF
    RET

;@ROUTINE NORETURN
DG_RAISE:
    POP  HL
    LD   A,(HL)
    JR   DG_ISSUE

; Copy one complete offset/line/column record from HL to DE. LDIR preserves
; carry, allowing diagnostic callers to establish failure after the copy.
;@ROUTINE IN DE,HL OUT BC,DE,HL CLOBBERS PARITY,HALFCARRY
PR_COPY:
    LD   BC,6
    LDIR
    RET

; E is the expected token ordinal. An ordinary mismatch reports the token
; ordinal with DG_TOKEN set.
;@ROUTINE IN E OUT A,C,CARRY,ZERO CLOBBERS SIGN,PARITY,HALFCARRY,B,D,DE,HL
PR_NEED:
    PUSH DE
    CALL PR_TAKE
    POP  DE
    CP   E
    RET  Z
    LD   A,E
    OR   DG_TOKEN
    JR   DG_ISSUE

; The expression parser needs one token of lookahead. Token metadata remains
; current until another tokenizer request, so buffering kind and word payload
; is sufficient for names, positions, numbers, and characters.
;@ROUTINE OUT A,BC,CARRY,ZERO CLOBBERS SIGN,PARITY,HALFCARRY,D,DE,HL
PR_PEEK:
    LD   A,(PR_LKIND)
    CP   $FF
    JR   NZ,.BUFFERED
    CALL TK_NEXT
    LD   (PR_LKIND),A
    LD   (PR_LVAL),BC
    LD   A,(PR_LKIND)
    RET
.BUFFERED:
    LD   BC,(PR_LVAL)
    LD   A,(PR_LKIND)
    OR   A
    RET

;@ROUTINE OUT A,BC,CARRY,ZERO CLOBBERS SIGN,PARITY,HALFCARRY,D,DE,HL
PR_TAKE:
    CALL PR_PEEK
    LD   D,A
    LD   A,$FF
    LD   (PR_LKIND),A
    LD   A,D
    OR   A
    RET

; Frequent token checks enter the common PR_NEED tail. These wrappers
; trade one shared seven-byte body for each repeated eight-byte inline check.
;@ROUTINE OUT A,CARRY,ZERO CLOBBERS SIGN,PARITY,HALFCARRY,B,C,D,DE,HL
.NEEDEOL:
    LD   E,TK_EOL
    JR   PR_NEED
;@ROUTINE OUT A,CARRY,ZERO CLOBBERS SIGN,PARITY,HALFCARRY,B,C,D,DE,HL
PR_LEFT:
    LD   E,TK_LPAR
    JR   PR_NEED
;@ROUTINE OUT A,CARRY,ZERO CLOBBERS SIGN,PARITY,HALFCARRY,B,C,D,DE,HL
PR_RIGHT:
    LD   E,TK_RPAR
    JR   PR_NEED
;@ROUTINE OUT A,CARRY,ZERO CLOBBERS SIGN,PARITY,HALFCARRY,B,C,D,DE,HL
.NEEDAS:
    LD   E,TK_AS
    JR   PR_NEED

;@ROUTINE OUT A,CARRY,ZERO CLOBBERS SIGN,PARITY,HALFCARRY,B,C,D,DE,HL
PR_EQUAL:
    LD   E,TK_EQ
    JR   PR_NEED

; Append one operation followed by the byte in C. The helper preserves the
; operand across the sink's internal cursor work.
;@ROUTINE IN A,C OUT A,CARRY,ZERO CLOBBERS SIGN,PARITY,HALFCARRY,B,D,DE,HL
PR_EMITC:
    PUSH BC
    CALL TR_OPER
    POP  BC
    LD   A,C
    JP   TR_PUT

PR_ETERM:
    LD   A,DG_VALUE
; The legacy proof layouts put this target outside JR range.
    JR   DG_ISSUE

; Packed actions consume the active `else fail` grammar.

; The first general scalar path admits bounded program variables and scalar
; locals, then parses a main body as assignment and output statements. The
; current token is the program variable's name on entry.

; The older array slice is selected by the bracketed type suffix. Its body is
; still deliberately fixed; this split only keeps scalar names unrestricted.

; Parse the first general routine-call slice. It deliberately admits one
; retained forward signature while exercising exact completion and parameter
; lookup, scalar call/result flow, and direct recursion.

; A is the stable source-part identity; HL..DE is the half-open byte range.
;@ROUTINE IN A,DE,HL OUT A,CARRY,ZERO CLOBBERS SIGN,PARITY,HALFCARRY,BC,DE,HL,IX,IY
.START:
    PUSH AF
    XOR  A
    LD   (SRC_LEFT),A
    POP  AF
    CALL SRC_INIT
;@ROUTINE OUT A,CARRY,ZERO CLOBBERS SIGN,PARITY,HALFCARRY,BC,DE,HL,IX,IY
PR_RESET:
    XOR  A
    LD   (DG_CODE),A
    LD   (DG_PART),A
    LD   HL,TR_BODY
    LD   (TR_PTR),HL
    LD   (TR_CNT),A
    LD   (TR_BASE),A
    LD   A,$FF
    LD   (PR_LKIND),A
    XOR  A
    LD   (SY_CNT),A
    LD   (SY_LSLOT),A
    LD   (SY_GSLOT),A
    XOR  A
    LD   HL,AG_MODE
    LD   B,AG_GIVEN-AG_MODE+1
.LOOP:
    LD   (HL),A
    INC  HL
    DJNZ .LOOP
    LD   (AG_DLEN),A
    LD   (AG_DLEN+1),A
    LD   (AG_ROLEN),A
    LD   (AG_ROLEN+1),A
    LD   (PR_BSS),A
    LD   (PR_BSS+1),A
    LD   (PR_FDONE),A
    LD   (PR_FORD),A
    RET

; The typed scalar increment is kept in a separate source unit while it is
; correctness-first and under review. The compression pass may fold shared
; tails back into this parser after the rules are stable.
