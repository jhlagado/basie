;==========================================================================
;  Expression code generation: operators
;==========================================================================
;
;  The reference compiler's templates for the binary operators (ref/
;  compile/compiler.ts: binary, emitBinaryConstLeft, emitBinaryImmediate,
;  emitBinaryRegisters, emitBinary32, emitShift, emitShiftBy), as the
;  expression parser reduces each operator whose operands are not both
;  known (EXPR.ASM). The left operand is the left one, the right the
;  right; the width is the type the operation is done at (EX_UNIFY). A
;  computed left operand was pushed while the right was computed
;  (GX_PUSH); a byte operation leaves A, a word one HL and a long one DEHL,
;  the long's right operand in the alternate registers, as the 32-bit
;  helpers take them. A relation leaves a Boolean in A.
;
;  Principal entries:
;    GX_BINOP  the operator EX_OPER on the two operands
;    GX_IMM    the operator with a known right operand (an immediate)
;    GX_REGS   the operator on the registers
;    GX_SHIFT  a shift whose count or left operand is computed

;@ROUTINE IN C CLOBBERS A,BC,DE,HL,CARRY,ZERO,SIGN,PARITY,HALFCARRY
; Generate the binary operator EX_OPER (a token, or a relation code below
; 6) of width C on the operands EX_LMETA/EX_LVAL and EX_RMETA/EX_RVAL, not
; both known, as the reference's binary does. A known left operand is used
; as an immediate after the right is computed (emitBinaryConstLeft); a left
; operand in the registers was pushed (GX_PUSH) and is popped beneath a
; known right (emitBinaryImmediate) or a computed one (the register form),
; each widened to the width when it is narrower.

GX_BINOP:                      ; C is the width.
    LD   A,(EX_LMETA)              ; Is the left operand known?
    RLCA                           ; SY_KNOWN into carry.
    JR   C,.LEFT                   ; Yes: it becomes an immediate.
    LD   A,(EX_RMETA)              ; The left was pushed. The right?
    RLCA                           ; SY_KNOWN into carry.
    JR   C,.RIGHT                  ; Known: pop the left beneath it.
    CALL .RWIDEN                   ; Both computed: the right at the width,
    LD   A,C                       ; then
    CALL GX_SIZE                   ; the left back:
    LD   A,$EB                     ; words EX DE,HL, the right to DE;
    JR   Z,.ASIDE                  ; (LD keeps the flags)
    LD   A,$D9                     ; longs EXX, to the alternates;
    JR   NC,.ASIDE                 ; or bytes
    LD   A,$5F                     ; LD E,A, then the left: POP AF.
.ASIDE:                        ; A moves the right aside.
    CALL EM_BYTE                   ; Append it.
    CALL .POPL                     ; The left back, popped and widened.
    JP   GX_REGS                   ; Operate on the registers and return.
.RIGHT:                        ; A known right beneath a pushed left.
    CALL .POPL                     ; The left back, at the width.
    LD   HL,EX_RVAL                ; The right's value
    JR   GX_IMM                    ; is the immediate.
.POPL:                         ; Pop the left operand, widened.
    LD   A,(EX_LMETA)              ; The left's
    AND  SY_TMASK                  ; type:
    PUSH AF                        ; kept,
    CALL GX_POPV                   ; its value popped (BC is kept),
    POP  AF                        ; then widened to the width C
    JR   .WIDEN                    ; when narrower; return.
.LEFT:                         ; A known left; the right is computed.
    CALL .RWIDEN                   ; The right at the width.
    LD   HL,EX_LVAL                ; The left's value.
    LD   A,(EX_OPER)               ; Does the operator commute?
    CP   EX_NE+1                   ; = and <> do,
             JR   C,GX_IMM         ; so the left is the immediate.
    CP   TK_STAR                   ; So do *,
             JR   Z,GX_IMM         ; and + and the
    CP   TK_MINUS                  ; bitwise operators, but not -:
    JR   Z,.SWAP                   ; it moves the right aside.
    CALL GX_ALU                    ; + and the bitwise ones (HL is kept)
             JR   NC,GX_IMM        ; take the left as the immediate.
.SWAP:                         ; The right moves aside, the left loads.
    LD   A,C                       ; How wide?
    CALL GX_SIZE                   ; Words,
    JR   Z,.SWAPW                  ; longs
    JR   NC,.SWAPL                 ; or bytes.
    CALL EM_SEQ                    ; Bytes: LD E,A,
    DB   2,$5F,$3E                 ; then LD A,n.
    LD   A,(HL)                    ; The left
    CALL EM_BYTE                   ; is n.
             JR   GX_REGS          ; Operate on the registers and return.
.SWAPW:                        ; Words.
    CALL EM_SEQ                    ; EX DE,HL,
    DB   2,$EB,$21                 ; then LD HL,nn.
    CALL GX_WMEM                   ; The left is nn.
            JR   GX_REGS           ; Operate on the registers and return.
.SWAPL:                        ; Longs: EXX, then LD HL,low word,
    CALL GX_LONGV                  ; LD DE,high word: the left.
            JR   GX_REGS           ; Operate on the registers and return.

;@ROUTINE IN C CLOBBERS A,DE,HL,CARRY,ZERO,SIGN,PARITY,HALFCARRY
; Widen the computed right operand, of type EX_RMETA, to the width C when
; it is narrower; .WIDEN widens from type A. BC is kept.

.RWIDEN:                       ; C is the width.
    LD   A,(EX_RMETA)              ; The right's
    AND  SY_TMASK                  ; type.
.WIDEN:                        ; A is the type to widen from.
    CP   C                         ; Is it the width's?
    RET  Z                         ; nothing to do.
    PUSH BC                        ; Keep the width.
    LD   D,A                       ; From the right's type
    LD   E,C                       ; to the width.
    CALL GX_WIDEN                  ; Widened.
    POP  BC                        ; C is the width.
    RET                            ; The right is at the width.

;@ROUTINE IN HL OUT HL CLOBBERS A,B,CARRY,ZERO,SIGN,PARITY,HALFCARRY
; Append EXX, LD HL and the low word of the value at HL, then LD DE and
; its high word: a long immediate's load, the right operand moved aside
; into the alternates first. HL steps past the value.

GX_LONGV:                      ; HL is the value.
    CALL EM_SEQ                    ; EXX, then LD HL,
    DB   2,$D9,$21                 ; the opcodes,
    CALL GX_WMEM                   ; its low word; fall into GX_DEMEM.

;@ROUTINE IN HL OUT HL CLOBBERS A,CARRY,ZERO,SIGN,PARITY,HALFCARRY
; Append LD DE,nn, nn the word at HL; HL steps past it.

GX_DEMEM:                      ; HL addresses the word.
    CALL EM_OP                     ; LD DE,nn:
    DB   $11                       ; the opcode; fall into GX_WMEM.

;@ROUTINE IN HL OUT HL CLOBBERS A,CARRY,ZERO,SIGN,PARITY,HALFCARRY
; Append the word at HL, low byte first; HL steps past it.

GX_WMEM:                       ; HL addresses the word.
    LD   A,(HL)                    ; Its low byte
    CALL EM_BYTE                   ; first,
    INC  HL                        ; then
    LD   A,(HL)                    ; its high
    CALL EM_BYTE                   ; byte.
    INC  HL                        ; HL is past it.
    RET                            ; Appended.

;@ROUTINE IN C,HL CLOBBERS A,BC,DE,HL,CARRY,ZERO,SIGN,PARITY,HALFCARRY
; The operator EX_OPER of width C with the known value at HL as its right
; operand and the other in the registers (emitBinaryImmediate): a long's
; into the alternates (EXX, LD HL,nn, LD DE,nn, EXX); for a byte, ADD,
; SUB, AND, OR and XOR take it as an immediate; anything else loads it
; into E or DE and operates on the registers.

GX_IMM:                        ; C is the width, HL the value.
    LD   A,C                       ; How wide?
    CALL GX_SIZE                   ; Words
    JR   Z,.WORD                   ; through DE,
    JR   NC,.LONG                  ; longs through the alternates.
    LD   A,(EX_OPER)               ; A byte: is it an ALU operator?
    CALL GX_ALU                    ; A is its register form.
    JR   C,.LOADE                  ; No: LD E,n.
    AND  $38                       ; The operation's bits,
    OR   $C6                       ; as an immediate: ADD A,n and so on.
    CALL EM_BYTE                   ; Append it.
    LD   A,(HL)                    ; Its operand
    JP   EM_BYTE                   ; is the immediate, and return.
.LOADE:                        ; Through E.
    LD   A,(HL)                    ; The immediate
    CALL EM_OPA                    ; is the operand of LD E,n.
    DB   $1E                       ; The opcode.
    JR   GX_REGS                   ; Operate on the registers and return.
.WORD:                         ; Through DE:
    CALL GX_DEMEM                  ; LD DE,nn, the immediate.
    JR   GX_REGS                   ; Operate on the registers and return.
.LONG:                         ; Through the alternates: EXX,
    CALL GX_LONGV                  ; LD HL,low word, LD DE,high word,
    CALL EM_OP                     ; then EXX
    DB   $D9                       ; again; fall into GX_REGS.

;@ROUTINE IN C CLOBBERS A,BC,DE,HL,CARRY,ZERO,SIGN,PARITY,HALFCARRY
; The operator EX_OPER of width C on the registers (emitBinaryRegisters):
; the left in A, HL or DEHL, the right in E, DE or the alternates.
; Arithmetic leaves its result there; a relation leaves a Boolean in A.

GX_REGS:                       ; C is the width.
    LD   A,C                       ; A long
    CALL GX_SIZE                   ; goes through the runtime;
    JR   C,.NARROW                 ; a byte
    JP   NZ,GX_LOP                 ; or a word does not.
.NARROW:                       ; A byte or a word.
    LD   A,(EX_OPER)               ; The operator.
    CP   EX_GE+1                   ; A relation code?
    JP   C,GX_REL                  ; Compare.
    CALL GX_ALU                    ; An ALU operator?
    JR   C,.MULDIV                 ; No: *, / or mod.
    LD   B,A                       ; B is its register form, on E.
    LD   A,C                       ; Words?
    CALL GX_SIZE                   ; Then a word sequence.
    LD   A,B                       ; A byte: the one instruction,
    JP   C,EM_BYTE                 ; ADD A,E and so on; return.
    LD   C,B                       ; C is the operation from here.
    CP   $83                       ; Word addition?
    LD   A,$19                     ; ADD HL,DE.
    JP   Z,EM_BYTE                 ; Append it and return.
    LD   A,C                       ; Word subtraction?
    CP   $93                       ; SUB E is its byte form.
    JR   Z,GX_MINUS                ; OR A then SBC HL,DE; return.
    CALL EM_OP                     ; Bitwise: LD A,H,
    DB   $7C                       ; then
    LD   A,C                       ; the operation
    DEC  A                         ; on D,
    CALL EM_BYTE                   ; then
    CALL EM_SEQ                    ; LD H,A
    DB   2,$67,$7D                 ; and LD A,L,
    LD   A,C                       ; the operation
    CALL EM_BYTE                   ; on E,
    CALL EM_OPX                    ; then LD L,A.
    DB   $6F                       ; Append it and return.
.MULDIV:                       ; A is *, / or mod.
    LD   B,A                       ; B is the operator, C the width;
    PUSH BC                        ; keep both across the code.
    LD   A,C                       ; Bytes?
    CALL GX_PROP                   ; The width's size and sign:
    LD   C,A                       ; kept in C.
    DEC  A                         ; u8?
    JR   Z,.UNSIGNED               ; Zero-extended.
    CP   $80                       ; i8?
    JR   NZ,.HELPER                ; Words go straight to the helper.
    CALL EM_SEQ                    ; i8: both sign-extended,
    DB   8,$6F,$07,$9F,$67,$7B,$07,$9F,$57 ; LD L,A ... LD A,E ... LD D,A.
    JR   .HELPER                   ; Then the helper.
.UNSIGNED:                     ; Bytes widen to words first:
    CALL EM_SEQ                    ; LD L,A, LD H,0,
    DB   5,$6F,$26,0,$16,0         ; LD D,0.
.HELPER:                       ; C is the width's properties.
    POP  DE                        ; D is the operator.
    PUSH DE                        ; Keep it for the result.
    LD   A,D                       ; Multiplication?
    LD   DE,HP_MUL16               ; It has its own helper, MUL16.
    CP   TK_STAR                   ; Division and remainder
    JR   Z,.CALL                   ; share one:
    LD   DE,HP_DIV16               ; DIV16,
    BIT  7,C                       ; or for
    JR   Z,.CALL                   ; a signed division
    LD   DE,HP_SDIV                ; DIV16S.
.CALL:                         ; DE is the helper's word.
    CALL EM_HELPD                  ; CALL it.
    POP  BC                        ; B is the operator, C the width.
    LD   A,C                       ; Bytes?
    CALL GX_SIZE                   ; Words want only the remainder moved.
    LD   A,B                       ; The operator.
    JR   NC,.WORDS                 ; Words.
    CP   TK_MOD                    ; A byte result: the remainder
    LD   A,$7B                     ; is LD A,E,
    JP   Z,EM_BYTE                 ; and return;
    CALL EM_OPX                    ; the quotient LD A,L.
    DB   $7D                       ; Append it and return.
.WORDS:                        ; A word result.
    CP   TK_MOD                    ; The remainder? EX DE,HL brings it to HL.
    RET  NZ                        ; The quotient is already there.
    CALL EM_OPX                    ; EX DE,HL.
    DB   $EB                       ; Append it and return.

;@ROUTINE CLOBBERS A,B,CARRY,ZERO,SIGN,PARITY,HALFCARRY
; Append OR A and SBC HL,DE: HL less DE, with carry when HL is the less.

GX_MINUS:                      ; HL and DE are words.
    CALL EM_SEQX                   ; OR A, SBC HL,DE:
    DB   3,$B7,$ED,$52             ; carry clear, then subtract.

;@ROUTINE IN A,C CLOBBERS A,BC,DE,HL,CARRY,ZERO,SIGN,PARITY,HALFCARRY
; The relation A (EX_EQ..EX_GE) of width C, a byte or a word, the left in
; A or HL and the right in E or DE, as a Boolean in A: a comparison that
; leaves carry when the left is less, or when they are equal, then SBC A,A
; and AND 1 for =, < and > or INC A for <>, >= and <=. <= and > swap the
; operands; a signed order flips both sign bits first (compare16ToFlags).

GX_REL:                        ; A is the relation, C the width.
    LD   B,A                       ; Keep it.
    LD   A,C                       ; The width's
    CALL GX_PROP                   ; size and sign:
    LD   C,B                       ; C is the relation from here,
    LD   B,A                       ; B the properties.
    BIT  1,A                       ; A byte, u8 or i8, not a word?
    JR   NZ,.WORDS                 ; No: compare words.
.BYTES:                        ; Bytes in A and E.
    LD   A,C                       ; An equality?
    CP   EX_LT                     ; = and <> are below <.
    JR   NC,.ORDER                 ; No: an order.
    CALL EM_SEQ                    ; SUB E, then SUB 1 sets carry
    DB   3,$93,$D6,1               ; only when they were equal.
    JR   GX_TAIL                   ; Make the Boolean; return.
.ORDER:                        ; < <= > >= on bytes.
    PUSH BC                        ; Keep the relation and properties.
    CALL GX_SWAP                   ; Z if the operands swap (<= and >).
    JR   NZ,.FLIPB                 ; < and >= compare as they are.
    CALL EM_SEQ                    ; LD D,A, LD A,E, LD E,D:
    DB   3,$57,$7B,$5A             ; the right is now the left.
.FLIPB:                        ; Signed bytes have their sign bits flipped.
    POP  BC                        ; B is the properties.
    BIT  7,B                       ; Signed?
    JR   Z,.CPE                    ; No.
    CALL EM_SEQ                    ; XOR $80, LD D,A, LD A,E, XOR $80,
    DB   8,$EE,$80,$57,$7B,$EE,$80,$5F,$7A ; LD E,A, LD A,D.
.CPE:                          ; Compare A with E.
    CALL EM_OP                     ; CP E: carry if A is less.
    DB   $BB                       ; Append it.
    JR   GX_TAIL                   ; Make the Boolean; return.
.WORDS:                        ; Words in HL and DE.
    CALL GX_SWAP                   ; <= and > swap them.
    LD   A,$EB                     ; EX DE,HL.
    CALL Z,EM_BYTE                 ; Swap them; BC is kept.
    LD   A,C                       ; An equality
    CP   EX_LT                     ; is never
    JR   C,.SBC                    ; flipped;
    BIT  7,B                       ; a signed order is:
    JR   Z,.SBC                    ; LD A,H, XOR $80, LD H,A,
    CALL EM_SEQ                    ; LD A,D, XOR $80, LD D,A.
    DB   8,$7C,$EE,$80,$67,$7A,$EE,$80,$57 ; Both sign bits flipped.
.SBC:                          ; Then subtract.
    CALL GX_MINUS                  ; OR A, SBC HL,DE: carry if HL is less.
    LD   A,C                       ; An equality?
    CP   EX_LT                     ; = and <> are below <.
    JR   NC,GX_TAIL                ; No: carry decides.
    CALL EM_SEQ                    ; LD A,H, OR L, SUB 1: carry
    DB   4,$7C,$B5,$D6,1           ; when equal; fall into GX_TAIL.

;@ROUTINE IN C CLOBBERS A,B,CARRY,ZERO,SIGN,PARITY,HALFCARRY
; Make relation C's Boolean from carry: SBC A,A, then INC A for the odd
; relations, <>, <= and >=, which hold when carry is clear, or AND 1 for
; the even ones, which hold when it is set.

GX_TAIL:                       ; C is the relation.
    CALL EM_OP                     ; SBC A,A: $FF when carry.
    DB   $9F                       ; Append it.
    BIT  0,C                       ; <>, <= and >= are odd.
    LD   A,$3C                     ; INC A: 0 when carry, 1 otherwise.
    JP   NZ,EM_BYTE                ; Append it and return.
    CALL EM_SEQX                   ; AND 1: 1 when carry.
    DB   2,$E6,1                   ; The Boolean.

;@ROUTINE IN C OUT ZERO CLOBBERS A,CARRY,SIGN,PARITY,HALFCARRY
; Z when relation C swaps its operands: <= and >, which compare the right
; with the left.

GX_SWAP:                       ; C is the relation.
    LD   A,C                       ; Is it
    CP   EX_LE                     ; <=,
    RET  Z                         ; which swaps,
    CP   EX_GT                     ; or >?
    RET                            ; Z if it swaps.

;@ROUTINE IN C CLOBBERS A,BC,DE,HL,CARRY,ZERO,SIGN,PARITY,HALFCARRY
; The operator EX_OPER of long width C (emitBinary32), the left in DEHL
; and the right in DE'HL', through the runtime's 32-bit helpers (GX_LTAB):
; a remainder is the alternates' after DIV32 (EXX); = and <> make the
; Boolean from Z (LD A,0, JP NZ or JP Z over INC A), the orders from
; carry, > and <= comparing the right with the left (EXX first).

GX_LOP:                        ; C is the width.
    LD   A,C                       ; Signed?
    CALL GX_PROP                   ; Bit 7
    LD   B,A                       ; of B.
    LD   A,(EX_OPER)               ; The operator
    LD   C,A                       ; is kept.
    CP   EX_GE+1                   ; A relation's row
    JR   NC,.TABLE                 ; is
    XOR  A                         ; EX_EQ's.
.TABLE:                        ; A is the row's key.
    LD   HL,GX_LTAB                ; Unsigned: the table's rows;
    BIT  7,B                       ; signed: GX_STAB's
    JR   Z,.FIND                   ; first, then
    LD   HL,GX_STAB                ; the table's.
.FIND:                         ; HL is a row.
    CP   (HL)                      ; This operator?
    INC  HL                        ; (its helper follows)
    JR   Z,.FOUND                  ; Found.
    INC  HL                        ; Past its
    INC  HL                        ; helper.
    JR   .FIND                     ; The next row.
.FOUND:                        ; HL is the helper's word.
    LD   E,(HL)                    ; DE is
    INC  HL                        ; its ordinal
    LD   D,(HL)                    ; and figure.
    CALL GX_SWAP                   ; > and <= compare the right
    CALL Z,.ALT                    ; with the left: EXX first.
    PUSH BC                        ; Keep the operator.
    CALL EM_HELPD                  ; CALL it.
    POP  BC                        ; C is the operator.
    LD   A,C                       ; The remainder
    CP   TK_MOD                    ; is in the alternates:
    JR   Z,.ALT                    ; EXX; return.
    CP   EX_GE+1                   ; Arithmetic
    RET  NC                        ; is done.
    CP   EX_LT                     ; An order
    JR   NC,GX_TAIL                ; from carry, as the narrower; return.
    CALL EM_SEQ                    ; An equality from Z: LD A,0,
    DB   2,$3E,0                   ; then
    LD   A,C                       ; for = (0)
    ADD  A,A                       ; JP NZ,
    ADD  A,A                       ; for <> (1)
    ADD  A,A                       ; JP Z,
    ADD  A,$C2                     ; eight more,
    LD   C,A                       ; over INC A
    CALL EM_FWD                    ; to a new label.
    PUSH AF                        ; Keep it.
    CALL EM_OP                     ; INC A.
    DB   $3C                       ; Append it.
    POP  AF                        ; The label is here,
    JP   EM_LDONE                  ; and free again; return.
.ALT:                          ; Append EXX.
    CALL EM_OPX                    ; EXX.
    DB   $D9                       ; Append it; return.

; The 32-bit helpers by operator: the token, or EX_EQ for every relation,
; then the helper's word (HELPERS.ASM). A signed operation searches
; GX_STAB's rows first, then GX_LTAB's, which hold the unsigned helpers
; and those that serve both.

GX_STAB:                       ; Operator, signed helper.
    DB   TK_SLASH                  ; /:
    DW   HP_LDIVS                  ; DIV32S.
    DB   TK_MOD                    ; mod:
    DW   HP_LDIVS                  ; the same, the remainder taken.
    DB   EX_EQ                     ; Every relation:
    DW   HP_LCMPS                  ; CMP32S.
GX_LTAB:                       ; Operator, unsigned or either helper.
    DB   TK_PLUS                   ; +:
    DW   HP_LADD                   ; ADD32.
    DB   TK_MINUS                  ; -:
    DW   HP_LSUB                   ; SUB32.
    DB   TK_STAR                   ; *:
    DW   HP_LMUL                   ; MUL32.
    DB   TK_SLASH                  ; /:
    DW   HP_LDIVU                  ; DIV32U.
    DB   TK_MOD                    ; mod:
    DW   HP_LDIVU                  ; the same, the remainder taken.
    DB   TK_AND                    ; and:
    DW   HP_LAND                   ; AND32.
    DB   TK_OR                     ; or:
    DW   HP_LOR                    ; OR32.
    DB   TK_XOR                    ; xor:
    DW   HP_LXOR                   ; XOR32.
    DB   EX_EQ                     ; Every relation:
    DW   HP_LCMPU                  ; CMP32U.

;@ROUTINE IN A OUT A,CARRY CLOBBERS ZERO,SIGN,PARITY,HALFCARRY
; Carry clear if token A is +, -, `and`, `or` or `xor`, with A its byte
; operation on E: ADD A,E, SUB E, AND E, OR E or XOR E. Carry otherwise.

GX_ALU:                        ; A is an operator token.
    PUSH HL                        ; Keep the caller's HL.
    PUSH BC                        ; And BC.
    LD   HL,.TABLE                 ; Token and operation pairs.
    LD   B,5                       ; Five of them.
.SCAN:                         ; HL is the next pair.
    CP   (HL)                      ; This token?
    INC  HL                        ; Its operation follows.
    JR   Z,.FOUND                  ; Found.
    INC  HL                        ; The next pair.
    DJNZ .SCAN                     ; Until the table ends.
    SCF                            ; Not an ALU operator.
    JR   .DONE                     ; Return carry.
.FOUND:                        ; HL is the operation.
    LD   A,(HL)                    ; A is it; carry is clear.
.DONE:                         ; Restore the caller's registers.
    POP  BC                        ; BC
    POP  HL                        ; and HL.
    RET                            ; Carry says which.
.TABLE:                        ; The ALU operators on E.
    DB   TK_PLUS,$83               ; + is ADD A,E.
    DB   TK_MINUS,$93              ; - is SUB E.
    DB   TK_AND,$A3                ; `and` is AND E.
    DB   TK_OR,$B3                 ; `or` is OR E.
    DB   TK_XOR,$AB                ; `xor` is XOR E.

;@ROUTINE IN A,C CLOBBERS A,BC,DE,HL,CARRY,ZERO,SIGN,PARITY,HALFCARRY
; Shift the registers, of integer type C, by the known count A, at most
; the type's width (emitShiftBy), by the operator EX_OPER, shl or shr: a
; long through SHL32, SHR32U or SHR32S with the count in A; a byte or a
; word one ADD A,A, SRA A or SRL A, or ADD HL,HL, SRA H and RR L or SRL H
; and RR L, a bit; a count of the whole width leaves zero, or the sign
; for a signed shr.

GX_SHBY:                       ; A is the count, C the type.
    LD   B,A                       ; B is the count.
    LD   A,C                       ; The type's
    CALL GX_PROP                   ; size and sign
    LD   C,A                       ; are C.
    AND  4                         ; A long?
    JR   Z,.SHORT                  ; No.
    LD   A,B                       ; LD A,count:
    CALL EM_OPA                    ; the opcode and
    DB   $3E                       ; the count;
    JR   GX_LSH                    ; then the helper; return.
.SHORT:                        ; A byte or a word.
    LD   A,C                       ; Its size
    AND  7                         ; in bits:
    ADD  A,A                       ; two,
    ADD  A,A                       ; four,
    ADD  A,A                       ; eight times it.
    DEC  A                         ; The width less one,
    CP   B                         ; below the count?
    JR   C,.WHOLE                  ; The whole width is shifted out.
    INC  B                         ; Plus one, for the loop's test.
.BIT:                          ; B bits remain, plus one.
    DEC  B                         ; Any?
    RET  Z                         ; No: the shift is written.
    PUSH BC                        ; Keep the count and properties.
    CALL GX_SH1                    ; One bit.
    POP  BC                        ; The count and properties.
    JR   .BIT                      ; The next.
.WHOLE:                        ; Every bit shifted out.
    LD   A,(EX_OPER)               ; A signed shr
    CP   TK_SHR                    ; leaves
    JR   NZ,.ZERO                  ; the sign:
    BIT  7,C                       ; for a signed
    JR   Z,.ZERO                   ; type,
    BIT  1,C                       ; a byte's RLCA, SBC A,A,
    JR   NZ,.SIGNW                 ; or a word's.
    CALL EM_SEQX                   ; RLCA, SBC A,A:
    DB   2,$07,$9F                 ; the sign in A.
.SIGNW:                        ; i16: LD A,H, RLCA, SBC A,A,
    CALL EM_SEQX                   ; LD L,A, LD H,A:
    DB   5,$7C,$07,$9F,$6F,$67     ; the sign in HL.
.ZERO:                         ; Zero:
    BIT  1,C                       ; XOR A for a byte,
    LD   A,$AF                     ; or LD HL,0
    JP   Z,EM_BYTE                 ; for a word.
    LD   HL,0                      ; The word zero:
    JP   GX_LDHL                   ; LD HL,0; return.

;@ROUTINE IN C CLOBBERS A,BC,DE,HL,CARRY,ZERO,SIGN,PARITY,HALFCARRY
; Shift a byte in A or a word in HL one bit, the type's properties in C
; and the operator EX_OPER: ADD A,A or ADD HL,HL for shl; for shr, SRA A
; or SRL A, or SRA H or SRL H then RR L.

GX_SH1:                        ; C is the properties: bit 1 for a word.
    LD   A,(EX_OPER)               ; shl?
    CP   TK_SHL                    ; Then a doubling:
    JR   NZ,.RIGHT                 ; shr is not.
    LD   A,$87                     ; A byte:
    BIT  1,C                       ; ADD A,A;
    JR   Z,.DOUBLE                 ; a word: ADD HL,HL.
    LD   A,$29                     ; Append it
.DOUBLE:                       ; A is the doubling.
    JP   EM_BYTE                   ; Append it and return.
.RIGHT:                        ; shr: the top byte shifts,
    CALL EM_OP                     ; CB,
    DB   $CB                       ; then
    LD   A,$2F                     ; SRA A,
    BIT  7,C                       ; signed,
    JR   NZ,.SIGNED                ; or
    LD   A,$3F                     ; SRL A.
.SIGNED:                       ; A is the byte form.
    BIT  1,C                       ; A word shifts H
    JP   Z,EM_BYTE                 ; and then L.
    SUB  3                         ; SRA H or SRL H
    CALL EM_BYTE                   ; is appended,
    CALL EM_SEQX                   ; then RR L.
    DB   2,$CB,$1D                 ; The word is shifted.

;@ROUTINE IN C CLOBBERS A,BC,DE,HL,CARRY,ZERO,SIGN,PARITY,HALFCARRY
; A long's shift through the runtime, its count in A: SHL32 for shl, and
; for shr SHR32S on a signed type, properties C, or SHR32U.

GX_LSH:                        ; C is the properties.
    LD   DE,HP_LSHL                ; shl,
    LD   A,(EX_OPER)               ; unless
    CP   TK_SHL                    ; it is
    JR   Z,.CALL                   ; shr:
    LD   DE,HP_LSHRS               ; signed
    BIT  7,C                       ; or
    JR   NZ,.CALL                  ; unsigned.
    LD   DE,HP_LSHRU               ; The helper.
.CALL:                         ; DE is it.
    JP   EM_HELPD                  ; Call it; return.

;@ROUTINE IN C CLOBBERS A,BC,DE,HL,CARRY,ZERO,SIGN,PARITY,HALFCARRY
; Shift the left operand, of integer type C, pushed, by the count in the
; registers, an unsigned integer of type EX_RMETA (emitShift): the count
; is clamped to the width, a wider count's high bytes making it the width
; (LD A,H, OR D, OR E for a long's, OR A, LD A,L, JP Z over LD A,width),
; then CP width, JP C over LD A,width, LD C,A; the left is popped; a long
; then shifts through the runtime (LD A,C), a byte or a word a bit at a
; time in a loop counted in B (LD B,C), skipped for a zero count.

GX_SHVAR:                      ; C is the left's type.
    PUSH BC                        ; Keep it.
    LD   A,C                       ; The width
    CALL GX_PROP                   ; in bits:
    AND  7                         ; its size
    ADD  A,A                       ; two,
    ADD  A,A                       ; four,
    ADD  A,A                       ; eight times.
    LD   E,A                       ; E is the width.
    LD   A,(EX_RMETA)              ; The count's
    AND  SY_TMASK                  ; type:
    CALL GX_SIZE                   ; a byte needs no clamp from above.
    JR   C,.CLAMP                  ; It is one.
    PUSH AF                        ; Keep the size.
    CALL EM_OP                     ; LD A,H,
    DB   $7C                       ; and
    POP  AF                        ; for
    JR   Z,.HIGH                   ; a long,
    CALL EM_SEQ                    ; OR D, OR E:
    DB   2,$B2,$B3                 ; its high word too.
.HIGH:                         ; Then OR A, LD A,L:
    CALL EM_SEQ                    ; zero
    DB   2,$B7,$7D                 ; when small.
    PUSH DE                        ; Keep the width.
    LD   C,$CA                     ; JP Z
    CALL .AHEAD                    ; over LD A,width.
    POP  DE                        ; E is the width.
.CLAMP:                        ; A is the count, at most a byte's.
    LD   A,E                       ; CP width:
    CALL EM_OPA                    ; within it, carry,
    DB   $FE                       ; so
    LD   C,$DA                     ; JP C
    CALL .AHEAD                    ; over LD A,width.
    CALL EM_OP                     ; LD C,A: the count.
    DB   $4F                       ; Kept in C.
    POP  BC                        ; C is the left's type.
    LD   A,C                       ; The left
    CALL GX_POPV                   ; is popped; BC is kept.
    LD   A,C                       ; Its properties:
    CALL GX_PROP                   ; size and sign,
    LD   C,A                       ; in C.
    AND  4                         ; A long?
    JR   Z,.LOOP                   ; No: a loop.
    CALL EM_OP                     ; LD A,C:
    DB   $79                       ; the count,
    JR   GX_LSH                    ; for the helper; return.
.LOOP:                         ; A loop of one-bit shifts.
    CALL EM_OP                     ; LD B,C: the count.
    DB   $41                       ; Then a test for zero:
    BIT  1,C                       ; a byte keeps its value
    JR   NZ,.TEST                  ; in L meanwhile, LD L,A,
    CALL EM_OP                     ; then
    DB   $6F                       ; LD A,C, OR A, LD A,L;
.TEST:                         ; a word only LD A,C, OR A.
    CALL EM_SEQ                    ; LD A,C,
    DB   2,$79,$B7                 ; OR A;
    BIT  1,C                       ; a byte restores
    LD   A,$7D                     ; its value:
    CALL Z,EM_BYTE                 ; LD A,L.
    PUSH BC                        ; Keep the properties.
    LD   C,$CA                     ; JP Z, for a zero count,
    CALL EM_FWD                    ; to the label past the loop.
    POP  BC                        ; The properties
    PUSH AF                        ; beneath that label,
    PUSH BC                        ; kept.
    CALL EM_LNEW                   ; The loop's label
    CALL EM_LDEF                   ; is here; A is kept.
    POP  BC                        ; The properties.
    PUSH AF                        ; Keep the loop's label.
    CALL GX_SH1                    ; One bit.
    CALL EM_OP                     ; DEC B,
    DB   $05                       ; then
    POP  AF                        ; JP NZ
    LD   C,$C2                     ; to
    CALL EM_JUMP                   ; the loop; A is kept.
    CALL EM_LFREE                  ; The loop's label is free;
    POP  AF                        ; the label past it is here,
    JP   EM_LDONE                  ; and free; return.

;@ROUTINE IN C,E CLOBBERS A,BC,DE,HL,CARRY,ZERO,SIGN,PARITY,HALFCARRY
; Append the jump C to a new label, then LD A,width, the width E, and
; define the label: the clamp's two steps.

.AHEAD:                        ; C is the jump, E the width.
    PUSH DE                        ; Keep the width.
    CALL EM_FWD                    ; A new label, and the jump to it.
    POP  BC                        ; C is the width.
    PUSH AF                        ; Keep the label.
    LD   A,C                       ; LD A,n, n the width:
    CALL EM_OPA                    ; the opcode and
    DB   $3E                       ; the operand.
    POP  AF                        ; The label is here,
    JP   EM_LDONE                  ; and free; return.
