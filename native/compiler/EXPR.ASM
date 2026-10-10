;==========================================================================
;  Expression parser
;==========================================================================
;
;  Parse one scalar expression, check its types, fold it when its operands
;  are known, and generate the code of the rest as each step is reached,
;  in the reference compiler's templates (GENEXPR.ASM, design decision
;  D45). The grammar actions call EX_RUN for a run-time expression and
;  EX_CONST for a compile-time one; the module also holds the
;  declaration-name checks, assignment compatibility, variable stores and
;  the failure exits that the parser's other modules share.
;
;  The module spans three files, consecutive in the image, because ATOM
;  limits one source file to 64K bytes: this one (names, the operand stack,
;  failure exits and the reduction of arithmetic), EXTERM.ASM (primaries
;  and unary operators) and EXOPER.ASM (binary operators and the entries
;  the grammar actions call).
;
;  Principal entries in this file:
;    EX_DECL   check and retain a declaration's name
;    EX_PREP   restore a retained name and write its provisional symbol
;    EX_FRESH  check a routine-local name against symbols and `main`
;    EX_MAIN   test whether the current name is `main`
;    EX_SAVE   push a result as a pending left operand
;    EX_POP    pop the left operand beneath a right one
;    EX_STASH  keep the expression just parsed (EX_RMETA, EX_RVAL)
;    EX_RTOK   make it the latest result again
;    EX_WIDEN  whether one scalar type widens to another
;    EX_UNIFY  resolve the type of a binary integer operation
;    EX_FOLD   return a folded value, checked or wrapped
;    EX_ARITH  reduce an arithmetic or bitwise operator
;    EX_SHIFT  reduce a shift
;    EX_TIMES  multiply two words, reporting overflow
;
;  Principal entries elsewhere: EX_RUN and EX_CONST parse an expression
;  for a grammar action, EX_FITS checks it against a destination and
;  EX_STORE stores it (EXOPER.ASM); EX_LIT returns a literal (EXTERM.ASM).
;
;  Precedence, loosest first: `or` and `xor`; `and`; `not`; the six
;  comparisons, which do not associate; `+` and `-`; `*`, `/` and `mod`;
;  unary `+` and `-`; primaries. `and` and `or` short-circuit when their
;  left operand is Boolean and are bitwise on integers; `xor` is bitwise.
;
;  A result is metadata in A and, when it is known, its value: the low
;  word in HL and the whole of it, five bytes, in EX_KVAL (VALUE.ASM). The
;  low four bits of the metadata are the type: SY_U8, SY_U16, SY_BOOL,
;  SY_I8, SY_I16 (SY_U32 and SY_I32 to come), or SY_EXACT for an untyped
;  value that takes the type of its typed peer or of its destination.
;  SY_KNOWN (bit 7) marks a value known at compile time; it generates no
;  code until something needs it in the registers. A value not known is in
;  the registers when the parser returns it: A for a byte or a Boolean, HL
;  for a word, as in the reference compiler.
;
;  Folding follows the reference: a typed operation wraps at its type, and
;  two exact operands give an exact result, which must lie from -2^31 to
;  2^32-1 (foldExact). A diagnostic about an operand is reported at its
;  first token, the reference's leftAt or rightAt (EX_LAT, EX_RAT).
;
;  A binary operator keeps its left operand on EX_STACK while the right is
;  parsed: 32 entries (EX_STCAP) of sixteen bytes (EX_STLEN):
;
;    +0  byte  left operand's metadata
;    +1  five  left operand's value; for a computed Boolean left of `and`
;              or `or`, its low byte is the label its short circuit jumps
;              to
;    +6  byte  EX_QUIET at the time of the push
;    +7  byte  EX_OPER, the pending operator
;    +8  word  EX_OPPOS, the operator's source offset
;    +10 word  EX_LAT, the left operand's first offset
;    +12 word  EX_RAT, the right operand's first offset
;    +14 word  unused
;
;  A computed left operand is also pushed on the machine stack (GX_PUSH)
;  while the right is computed, and popped beneath it.
;
;  EX_QUIET is nonzero inside the right arm of a short circuit whose
;  constant left operand decides it. The reference compiles that arm and
;  discards its code; here the emitter writes nothing while EX_QUIET is
;  nonzero (EM_QUIET). Each stack entry saves and restores it.
;
;  Every diagnostic is raised through DG_RAISE or DG_ISSUE, which restore
;  the parse driver's stack (PR_SP) and do not return: the routines here
;  return only on success.

;@ROUTINE OUT CARRY CLOBBERS SIGN,PARITY,HALFCARRY,ZERO,A,B,DE,HL
; Carry if the current NAME token is `main`, which names the program's main
; body and may not be declared as anything else.

EX_MAIN:
    LD   HL,KW_MAIN                ; Address the spelling "main".
    LD   B,4                       ; It has four characters.
    JP   TK_MATCH                  ; Carry if the token spells it.

;@ROUTINE OUT CARRY CLOBBERS SIGN,PARITY,HALFCARRY,ZERO,A,BC,DE,HL
; Retain a declaration's NAME token, its spelling in AC_DNAME and its
; position in AC_DPOS, for the symbol written once the declaration is
; complete, which is checked then (EX_PREP). `main` is a name like any
; other until main is declared.

EX_DECL:
EX_KEEP:                       ; Retain the name.
    LD   HL,AC_DNAME               ; Address the retained-name record.
    CALL TK_KEEP                   ; Keep the spelling's address and length.
    LD   HL,TK_POS                 ; The token's offset, line and column...
    LD   DE,AC_DPOS                ; ...become the declaration's position.
    CALL PR_COPY                   ; Copy the six bytes.
    OR   A                         ; Clear carry for success.
    RET                            ; Return to the declaration action.

EX_EDUP:                       ; A name that is already declared.
    CALL DG_RNAME                  ; Report it, named; no return.
    DB   DG_DUP                    ; Diagnostic: duplicate name.

;@ROUTINE OUT A,HL
; Make the retained declaration name (AC_DNAME) the current NAME token
; again, so that the symbol table and the name checks can read it. A
; returns its length and HL its address. Flags are preserved.

EX_RENEW:
    LD   HL,(AC_DNAME)             ; Fetch the retained spelling's address.
    LD   (TK_PTR),HL               ; Make it the token's spelling.
    LD   A,(AC_DLEN)               ; Fetch the retained length.
    LD   (TK_LEN),A                ; Make it the token's length.
    RET                            ; Return with the name current.

;@ROUTINE IN D,BC OUT A,CARRY,HL CLOBBERS SIGN,PARITY,HALFCARRY,ZERO
; Write the provisional symbol for the retained declaration name, with
; class/type D and payload BC. The name is checked against routines and
; services (RO_FRESH: a duplicate at top level, hidden by a local or local
; constant in a body) and symbols (SY_NEW), with its declaration position
; as the diagnostic's. BC and DE are preserved.

EX_PREP:
    CALL EX_RENEW                  ; Make the declared name current again.
    PUSH BC                        ; Keep the payload across the checks.
    PUSH DE                        ; Keep the class/type too.
    LD   HL,AC_DPOS                ; A collision is reported where the...
    LD   DE,TK_POS                 ; ...name was declared.
    CALL PR_COPY                   ; Copy the six-byte position.
    LD   A,(SY_BODY+1)             ; In a body
    OR   A                         ; a declaration
    LD   A,DG_HIDE                 ; would hide
    JR   NZ,.CHECK                 ; a routine's or a service's name;
    LD   A,DG_DUP                  ; at top level it would repeat it.
.CHECK:                        ; A is the diagnostic.
    CALL RO_FRESH                  ; Raise it for a routine or a service.
    POP  DE                        ; Restore the class/type in D.
    POP  BC                        ; Restore the payload.
    JP   SY_NEW                    ; Write the provisional symbol.

;@ROUTINE IN A OUT HL CLOBBERS SIGN,PARITY,HALFCARRY,ZERO,CARRY,A,DE
; Address operand-stack entry A in HL: EX_STACK plus sixteen times A.

EX_SLOT:
    ADD  A,A                       ; Index times two,
    ADD  A,A                       ; four,
    ADD  A,A                       ; eight,
    LD   L,A                       ; and as a word,
    LD   H,0                       ; sixteen entries' offsets passing a byte,
    ADD  HL,HL                     ; sixteen: the entry stride.
    LD   DE,EX_STACK               ; Fetch the stack base.
    ADD  HL,DE                     ; Address the entry.
    RET                            ; Return it in HL.

;@ROUTINE OUT A,CARRY CLOBBERS SIGN,PARITY,HALFCARRY,ZERO,BC,DE,HL
; Push the pending left operand and its context (EX_LMETA, EX_LVAL,
; EX_QUIET, EX_OPER, EX_OPPOS, EX_LAT and EX_RAT) onto the operand stack. The
; operator's offset must be kept because a nested operation replaces
; EX_OPPOS before the outer one is reduced. A full stack raises DG_DEEP.

EX_PUSH:
    LD   A,(EX_DEPTH)              ; Fetch the stack depth.
    CP   EX_STCAP                  ; Is there room for one more entry?
    JR   NC,.FULL                  ; No: the expression nests too deeply.
    CALL EX_SLOT                   ; Address the free entry.
    EX   DE,HL                     ; It is the copy's destination.
    LD   HL,EX_LMETA               ; The left's metadata and value, the
    LD   BC,EX_CTX                 ; quiet count, the operator, its offset
    LDIR                           ; and the operands' offsets are saved.
    LD   HL,EX_DEPTH               ; Count
    INC  (HL)                      ; the new entry.
    OR   A                         ; Clear carry for success.
    RET                            ; Pushed.

.FULL:                         ; EX_STCAP operators are already pending.
    CALL DG_RAISE                  ; Report it; no return.
    DB   DG_DEEP                   ; Diagnostic: expression too deep.

;@ROUTINE IN A,HL OUT A,CARRY CLOBBERS SIGN,PARITY,HALFCARRY,ZERO,BC,DE,HL
; Make result A/HL the pending left operand, the high bytes of a known
; value from EX_KVAL, and push it with its context.

EX_SAVE:
    LD   (EX_LMETA),A              ; The result becomes the left metadata.
    LD   DE,EX_LVAL                ; And its value:
    CALL EX_VKEEP                  ; HL, then EX_KVAL's high bytes.
    JR   EX_PUSH                   ; Push them with the operator context.

;@ROUTINE IN DE,HL CLOBBERS BC,DE,HL
; Store a result's value at DE: the word HL, then the three high bytes of
; EX_KVAL, which hold a known value's (EX_LIT). A and flags are kept.

EX_VKEEP:                      ; DE is the cell, HL the low word.
    EX   DE,HL                     ; HL is the cell.
    LD   (HL),E                    ; The low
    INC  HL                        ; word,
    LD   (HL),D                    ; then
    INC  HL                        ; the high bytes
    EX   DE,HL                     ; follow it,
    LD   HL,EX_KVAL+2              ; from
    LD   BC,3                      ; EX_KVAL.
    LDIR                           ; Copied.
    RET                            ; The value is kept.

;@ROUTINE IN A,HL OUT CARRY CLOBBERS SIGN,PARITY,HALFCARRY,ZERO,A,DE,HL
; Make result A/HL the right operand (EX_RMETA, EX_RVAL) and pop the most
; recent left operand and its context, its first offset and its right
; operand's again in EX_LAT and EX_RAT, where a diagnostic about either is
; reported (the reference's leftAt and rightAt). BC is preserved.

EX_POP:
    PUSH BC                        ; Keep BC.
    CALL EX_STASH                  ; The result is the right operand.
; Every reduction follows EX_SAVE. Keep the defensive test so a future
; parser change cannot turn a broken invariant into a wrapped address
; beyond PR_WEND.
    LD   A,(EX_DEPTH)              ; Fetch the stack depth.
    OR   A                         ; Is anything there to pop?
    JR   Z,EX_EPOP                 ; No: an internal invariant has failed.
    DEC  A                         ; Remove the top entry.
    LD   (EX_DEPTH),A              ; Publish the depth.
    CALL EX_SLOT                   ; Address the removed entry.
    LD   DE,EX_LMETA               ; The left's context is restored,
    LD   BC,EX_CTX                 ; the quiet count with it, ending
    LDIR                           ; a quiet right arm.
    POP  BC                        ; Restore BC.
    OR   A                         ; Clear carry for success.
    RET                            ; Return with both operands in place.
EX_EPOP:                       ; A pop with nothing pushed.
    CALL DG_RAISE                  ; Report it; no return.
    DB   DG_BUG                    ; Diagnostic: internal compiler error.

;@ROUTINE IN A,HL OUT A,CARRY,ZERO CLOBBERS SIGN,PARITY,HALFCARRY,BC,DE,HL
; Keep result A/HL as the right operand or the expression just parsed:
; EX_RMETA, and EX_RVAL with a known value's high bytes from EX_KVAL.
; A is returned with carry clear.

EX_STASH:
    LD   (EX_RMETA),A              ; The result's type and known flag.
    LD   DE,EX_RVAL                ; Its value,
    CALL EX_VKEEP                  ; meaningful when known.
    OR   A                         ; Clear carry.
    RET                            ; Kept.

;@ROUTINE OUT A,D,HL CLOBBERS BC,DE
; Make the expression kept by EX_STASH the latest result again: its
; value to EX_KVAL, its low word in HL, its metadata in A and D, as
; EX_FITS and GX_TOREG take it. Flags are kept.

EX_RTOK:
    LD   HL,EX_RVAL                ; The kept value
    LD   DE,EX_KVAL                ; is the latest's,
    LD   BC,5                      ; five bytes.
    LDIR                           ; Copied.
    LD   HL,(EX_RVAL)              ; Its low word.
    LD   A,(EX_RMETA)              ; Its metadata,
    LD   D,A                       ; in D too.
    RET                            ; A, D and HL describe it.

; Range and type failure exits. None returns. A fault inside the discarded
; arm of a constant short circuit is reported too, as the reference
; compiler reports it.

EX_EBOOL:                      ; A: the operands' metadata, ORed.
    CP   AG_FIRST                  ; A right operand not Boolean:
    LD   A,DG_CLASH                ; type-mismatch if either is known
    JR   NC,EX_EROP                ; or not a scalar, else conversion-required (the
    LD   A,DG_CONV                 ; reference's toRegisters), at the
    DB   $01                       ; right: LD BC,nn passes EX_ERNG's LD.
EX_ERNG:                       ; The right operand is out of range.
    LD   A,DG_RANGE                ; out-of-range,
EX_EROP:                       ; Diagnostic A at the right operand.
    LD   HL,EX_RAT                 ; At its first token.
    JR   EX_EPOSA                  ; Report it there.
EX_ELEFT:                      ; The left operand is out of range.
    LD   A,DG_RANGE                ; out-of-range,
EX_ELOP:                       ; Diagnostic A at the left operand.
    LD   HL,EX_LAT                 ; At its first token.
EX_EPOSA:                      ; Diagnostic A at the offset in the word at HL.
    JP   DG_AT                     ; Reported; no return.
EX_ETYPE:                      ; An operand of the wrong type.
    CALL DG_RAISE                  ; Report it.
    DB   DG_CLASH                  ; Diagnostic: type mismatch.

;@ROUTINE OUT A,ZERO CLOBBERS SIGN,PARITY,HALFCARRY,CARRY
; Zero if the pending left operand is Boolean. A returns its type.

EX_LBOOL:
    LD   A,(EX_LMETA)              ; Fetch the left metadata.
    JR   EX_TBOOL                  ; Test its type.

;@ROUTINE IN D OUT A,ZERO CLOBBERS SIGN,PARITY,HALFCARRY,CARRY
; Zero if metadata D is a Boolean's. A returns its type.

EX_DBOOL:
    LD   A,D                       ; The metadata; fall into EX_TBOOL.

;@ROUTINE IN A OUT A,ZERO CLOBBERS SIGN,PARITY,HALFCARRY,CARRY
; Zero if metadata A is a Boolean's. A returns its type.

EX_TBOOL:
    AND  EX_TMASK                  ; Keep its type.
    CP   SY_BOOL                   ; Is it Boolean?
    RET                            ; Return the comparison in zero.

;@ROUTINE OUT A CLOBBERS CARRY,ZERO,SIGN,PARITY,HALFCARRY
; Return in A the type of the declaration in progress (AC_DINFO).

EX_DTYPE:
    LD   A,(AC_DINFO)              ; Fetch the declaration's class and type.
    AND  SY_TMASK                  ; Keep the packed type.
    CP   SY_ENUM                   ; A nominal scalar?
    RET  NZ                        ; Built-in type.
    LD   A,(AG_CTYPE)              ; Its retained full ID.
    RET                            ; Return it.

;@ROUTINE IN A,E OUT CARRY CLOBBERS A,ZERO,SIGN,PARITY,HALFCARRY
; Carry if scalar type A widens implicitly to scalar type E, another
; (widens, spec 6.4): u8 to u16, i16, u32, i32 and f32; i8 to i16, i32
; and f32; u16 to u32, i32 and f32; i16 to i32 and f32. BC, DE and HL
; are kept.

EX_WIDEN:                      ; A is the source, E the target.
    PUSH AF
    OR   E                        ; Either nominal ID forbids numeric widening.
    CP   AG_FIRST
    JR   NC,.NOMINAL
    POP  AF                       ; Built-ins have IDs 0..8.
    PUSH HL                        ; Keep HL
    PUSH BC                        ; and BC.
    LD   HL,.TABLE                 ; The source's
    LD   C,A                       ; row
    LD   B,0                       ; of
    ADD  HL,BC                     ; targets,
    LD   A,(HL)                    ; a bit for each, bit 0 for type 1.
    OR   A                         ; Carry clear.
    LD   B,E                       ; Rotate the target's bit
    INC  B                         ; into carry: E rotations,
    DEC  B                         ; none for
    JR   Z,.DONE                   ; SY_EXACT (carry clear).
.ROLL:                         ; B rotations remain.
    RRCA                           ; The next bit into carry.
    DJNZ .ROLL                     ; Until the target's.
.DONE:                         ; Carry is the answer.
    POP  BC                        ; Restore BC
    POP  HL                        ; and HL.
    RET                            ; Carry if it widens.
.NOMINAL:
    POP  AF
    OR   A
    RET
.TABLE:                        ; By source: the types it widens to.
    DB   0,$F2,$E0,0               ; Exact, u8, u16, boolean,
    DB   $D0,$C0,0,0,0             ; i8, i16, u32, i32, f32.

;@ROUTINE OUT C,CARRY CLOBBERS SIGN,PARITY,HALFCARRY,ZERO,A,B,DE,HL
; Resolve the type of a binary numeric operation from both operands in
; EX_LMETA/EX_LVAL and EX_RMETA/EX_RVAL, returning it in C with carry
; clear: SY_EXACT when both are exact (the reference's foldExact). A
; Boolean operand raises DG_CLASH. An exact operand adopts its typed
; peer's type and must fit it (DG_RANGE); two typed ones take the one the
; other widens to (commonType), or raise DG_MIXED (mixed-operands). At
; f32 a known integer operand becomes an f32, which must be it exactly
; (coerceConst; DG_RANGE where a misfit is blamed).

EX_UNIFY:
    CALL .PAIR                     ; C is the type.
    LD   A,C                       ; Not f32:
    XOR  SY_F32                    ; done,
    RET  NZ                        ; carry clear.
    LD   HL,EX_LMETA               ; A known left
    LD   DE,EX_LVAL                ; becomes an f32,
    CALL .FLOAT                    ; exactly,
    JR   C,EX_ELEFT                ; or is out of range.
    LD   HL,EX_RMETA               ; So does
    LD   DE,EX_RVAL                ; a known
    CALL .FLOAT                    ; right,
    LD   C,SY_F32                  ; (the type again)
    RET  NC                        ; blamed when inexact
    JR   .BLAME                    ; as a misfit is.

;@ROUTINE IN DE,HL OUT CARRY CLOBBERS A,BC,DE,HL,ZERO,SIGN,PARITY,HALFCARRY
; The operand with metadata at HL and value at DE, when known and not an
; f32, becomes an f32 (OV_ITOF): carry when that is not its value
; exactly.

.FLOAT:                        ; HL is the metadata, DE the value.
    LD   A,(HL)                    ; Computed?
    RLCA                           ; Then
    RET  NC                        ; nothing; carry clear.
    RRCA                           ; Its type:
    AND  EX_TMASK                  ; an f32
    CP   SY_F32                    ; already?
    RET  Z                         ; Carry clear.
    LD   (HL),SY_KNOWN+SY_F32      ; It is one now:
    EX   DE,HL                     ; its value
    JP   OV_ITOF                   ; rounded; carry if inexact.

;@ROUTINE OUT C,CARRY CLOBBERS SIGN,PARITY,HALFCARRY,ZERO,A,B,DE,HL
; EX_UNIFY's resolution of the type, before an f32's operands convert.

.PAIR:                         ; The operands are popped.
    CALL EX_LBOOL                  ; Fetch the left type (no
    LD   D,A                       ; Boolean: EX_LBOK); D is it.
    LD   A,(EX_RMETA)              ; Fetch the right metadata.
    CALL EX_TBOOL                  ; Is its type Boolean?
    LD   C,A                       ; C is the right type.
    LD   A,DG_CLASH                ; Booleans have no arithmetic:
    JP   Z,EX_EROP                 ; type-mismatch at the right.
    LD   A,C
    CP   AG_FIRST
    LD   A,DG_CLASH
    JP   NC,EX_EROP                ; Right nominal operand is not numeric.
    LD   A,D                       ; Is the left operand typed?
    OR   A                         ; Test for SY_EXACT.
    JR   NZ,.LTYPE                 ; Yes: resolve from the left type.
    OR   C                         ; Both exact, then:
    RET  Z                         ; C is exact, carry clear.
    LD   HL,EX_LVAL                ; The exact left
    CALL .FITS                     ; must fit the right's type.
    JP   C,EX_ELEFT                ; It does not: out of range.
    RET                            ; C is the type; carry is clear.
.LTYPE:                        ; A typed left: D is it, C the right's.
    LD   A,C                       ; Is the right exact?
    OR   A                         ; Then it adopts
    LD   C,D                       ; the left's type
    JR   NZ,.BOTH                  ; and
    LD   HL,EX_RVAL                ; must fit it.
    CALL .FITS                     ; Does it?
    RET  NC                        ; Yes: C is the type, carry clear.
.BLAME:                        ; The right is out of range:
    LD   A,(EX_LMETA)              ; blamed at the left
    RLCA                           ; after a known left,
    JP   C,EX_ELEFT                ; at the right
    JP   EX_ERNG                   ; after a computed one.
.BOTH:                         ; A is the right's type, D the left's.
    CP   D                         ; The same?
    RET  Z                         ; Then that one, in C, carry clear.
    LD   C,A                       ; C is the right's.
    LD   E,D                       ; Does the right
    CALL EX_WIDEN                  ; widen to the left?
    JR   C,.LEFT                   ; Then the left's.
    LD   A,D                       ; Does the left
    LD   E,C                       ; widen to
    CALL EX_WIDEN                  ; the right?
    CCF                            ; Then the right's,
    RET  NC                        ; in C, carry clear.
    LD   A,DG_MIXED                ; Neither: mixed-operands,
    JP   EX_EROP                   ; at the right operand.
.LEFT:                         ; The right widens to the left.
    LD   C,D                       ; The left's type,
    OR   A                         ; carry clear.
    RET                            ; C is the type.

;@ROUTINE IN C,HL OUT CARRY CLOBBERS A,DE
; Carry when the value at HL does not fit type C. BC and HL are kept.

.FITS:                         ; C is the type.
    LD   A,C                       ; The type
    JP   VL_FITS                   ; checked; carry if it does not fit.

;@ROUTINE OUT A,ZERO CLOBBERS SIGN,PARITY,HALFCARRY,CARRY
; Nonzero when both operands are known at compile time; zero otherwise.

EX_KNOWN:
    LD   A,(EX_LMETA)              ; Is the left operand known?
    AND  SY_KNOWN                  ; Test its flag.
    RET  Z                         ; No: the operation is run-time.
    LD   A,(EX_RMETA)              ; Is the right operand known?
    AND  SY_KNOWN                  ; Test its flag.
    RET                            ; Nonzero only if both are.

;@ROUTINE IN C OUT A,HL,CARRY CLOBBERS SIGN,PARITY,HALFCARRY,ZERO,DE
; Return the folded value in EX_KVAL as a known result of type C: an
; exact one must lie in the exact range (DG_RANGE at the left operand,
; foldExact), a typed one is wrapped to its type (foldTyped). A is the
; metadata, HL the value's low word. BC is kept.

EX_FOLD:
    PUSH BC                        ; Keep the type.
    LD   HL,EX_KVAL                ; The value:
    LD   A,C                       ; exact,
    OR   A                         ; or
    JR   NZ,.WRAP                  ; typed?
    CALL VL_RANGE                  ; Exact: in range?
    JP   C,EX_ELEFT                ; No: out of range.
    JR   .DONE                     ; It is.
.WRAP:                         ; Typed: wrapped
    CALL VL_WRAP                   ; to its type.
.DONE:                         ; The value is the result.
    POP  BC                        ; C is the type.
    LD   HL,(EX_KVAL)              ; Its low word.
    LD   A,C                       ; Its type,
    OR   SY_KNOWN                  ; known; carry is clear.
    RET                            ; The result.

;@ROUTINE OUT A,HL,CARRY CLOBBERS SIGN,PARITY,HALFCARRY,ZERO,BC,DE
; Reduce the integer operation EX_OPER (the token of +, -, *, /, mod,
; and, or, xor, shl or shr) on the popped operands at the unified type
; (binary). Known operands fold (VALUE.ASM): exact ones exactly, refused
; outside the exact range, typed ones wrapping at their type; a known zero
; divisor raises DG_ZERO, at the right after a computed left, as the
; reference reports it. Otherwise the reference's code for the operation
; is generated (GX_BINOP). Shifts are EX_SHIFT's.

EX_ARITH:
    LD   A,(EX_OPER)               ; A shift?
    CP   TK_SHL                    ; shl
    JP   Z,EX_SHIFT                ; and
    CP   TK_SHR                    ; shr
    JP   Z,EX_SHIFT                ; take their own rules.
    CALL EX_UNIFY                  ; Check the operands; C is the type.
    LD   A,C                       ; At f32
    CP   SY_F32                    ; only +, -, *
    LD   A,(EX_OPER)               ; and / are
    JR   NZ,.WHOLE                 ; defined:
    CP   TK_AND                    ; `and`, `xor`
    JR   NC,.UNDEF                 ; and mod (TK_AND on),
    CP   TK_OR                     ; and `or`,
    JR   NZ,.WHOLE                 ; are not, but
.UNDEF:                        ; type-mismatch,
    LD   A,(EX_LMETA)              ; at a known left
    RLCA                           ; (foldTyped,
    LD   A,DG_CLASH                ; emitBinaryConstLeft),
    JP   C,EX_ELOP                 ; or else
    LD   A,(EX_OPER)               ; at the right, mod's
    CP   TK_MOD                    ; known zero divisor
    CALL Z,.NOZERO                 ; first.
    LD   A,DG_CLASH                ; type-mismatch
    JP   EX_EROP                   ; at the right.
.WHOLE:                        ; Integers: A is the operator.
    CP   TK_SLASH                  ; Division?
    JR   Z,.DIVIDES                ; Its divisor may not be a known zero.
    CP   TK_MOD                    ; Remainder?
    JR   NZ,.CHECKED               ; Anything else divides by nothing.
.DIVIDES:                      ; A division or remainder.
    CALL .NOZERO                   ; Its divisor is no known zero.
.CHECKED:                      ; The operands are acceptable.
    CALL EX_KNOWN                  ; Are both known?
    JR   NZ,.FOLD                  ; Then fold them.
    PUSH BC                        ; Keep the type.
    CALL GX_BINOP                  ; Generate the operation.
    POP  BC                        ; C is the type.
    LD   A,C                       ; A run-time result of that type.
    OR   A                         ; Clear carry.
    RET                            ; Return it.
.FOLD:                         ; Both are known: compute the result.
    LD   A,C                       ; At f32
    CP   SY_F32                    ; the overlay
    JR   NZ,.INTS                  ; folds it
    CALL OV_FOLD                   ; (foldTyped),
    LD   A,DG_FOVER                ; float-overflow
    JP   C,EX_ELOP                 ; at the left past f32.
    LD   C,SY_F32                  ; The type,
    JR   EX_FOLD                   ; not wrapped; return.
.INTS:                         ; Integers.
    PUSH BC                        ; Keep the type.
    LD   A,(EX_OPER)               ; The operator:
    LD   C,A                       ; kept in C.
    CP   TK_PLUS                   ; Addition?
    JR   Z,.PLUS                   ; Fold it.
    CP   TK_MINUS                  ; Subtraction?
    JR   Z,.MINUS                  ; Fold it.
    CP   TK_STAR                   ; Multiplication?
    JR   Z,.TIMES                  ; Fold it.
    CP   TK_SLASH                  ; Division?
    JR   Z,.DIVMOD                 ; Fold it.
    CP   TK_MOD                    ; Remainder?
    JR   Z,.DIVMOD                 ; Fold it.
    POP  DE                        ; Bitwise: the type
    PUSH DE                        ; is E.
    LD   A,E                       ; Exact operands
    OR   A                         ; must be
    JR   NZ,.BITS                  ; from 0 to 2^32-1:
    LD   A,(EX_LVAL+4)             ; both
    LD   HL,EX_RVAL+4              ; top
    OR   (HL)                      ; bytes
    JP   NZ,EX_ELEFT               ; zero (out-of-range).
.BITS:                         ; C is the operator.
    CALL VL_BITS                   ; Combined.
    JR   .DONE                     ; The result.
.PLUS:                         ; Addition.
    CALL VL_ADD                    ; r = a + b.
    JR   .DONE                     ; The result.
.MINUS:                        ; Subtraction.
    CALL VL_SUB                    ; r = a - b.
    JR   .DONE                     ; The result.
.TIMES:                        ; Multiplication.
    CALL VL_MUL                    ; r = a times b, carry past 32 bits.
    POP  BC                        ; The type.
    PUSH BC                        ; Kept.
    JR   NC,.DONE                  ; No carry: the product.
    LD   A,C                       ; An exact product
    OR   A                         ; that carried
    JP   Z,EX_ELEFT                ; is out of range.
    JR   .DONE                     ; A typed one wraps.
.DIVMOD:                       ; Division and remainder.
    CALL VL_DIV                    ; r = a / b, or a mod b.
.DONE:                         ; EX_KVAL is the result.
    POP  BC                        ; C is the type.
    JP   EX_FOLD                   ; Check or wrap it; return.

;@ROUTINE IN C CLOBBERS A,B,HL,CARRY,ZERO,SIGN,PARITY,HALFCARRY
; Raise DG_ZERO when the divisor, at type C, is a known zero (an f32's
; sign aside: -0 is zero too), at the left when that is known, as the
; reference folds it, otherwise at the divisor. C is kept.

.NOZERO:                       ; C is the type.
    LD   A,(EX_RMETA)              ; Is the divisor known?
    AND  SY_KNOWN                  ; Test its flag.
    RET  Z                         ; No: the helper checks it at run time.
    LD   HL,EX_RVAL+3              ; Its fourth byte,
    LD   A,C                       ; without
    SUB  SY_F32                    ; an f32's
    LD   A,(HL)                    ; sign
    JR   NZ,.FIFTH                 ; bit,
    ADD  A,A                       ; and
.FIFTH:                        ; its fifth,
    INC  HL                        ; with
    OR   (HL)                      ; its
    LD   HL,EX_RVAL                ; first
    LD   B,3                       ; three,
.ZERO:                         ; ored
    OR   (HL)                      ; together,
    INC  HL                        ; are zero
    DJNZ .ZERO                     ; for zero.
    RET  NZ                        ; It is not.
    LD   A,(EX_LMETA)              ; A known left
    RLCA                           ; folds, blamed
    LD   A,DG_ZERO                 ; at the left;
    JP   C,EX_ELOP                 ; a computed one
    JP   EX_EROP                   ; at the divisor.

;@ROUTINE OUT A,HL,CARRY CLOBBERS SIGN,PARITY,HALFCARRY,ZERO,BC,DE
; Reduce shl or shr (EX_OPER) on the popped operands, the left's type the
; result's (binary, emitShift): an exact left with an exact count folds
; exactly (a negative count, or a result outside the exact range, is
; out-of-range), and with any other count has no definite type; a typed
; known left with a known count folds at its type (a negative count is
; type-mismatch); a computed left was pushed, and is shifted by a known
; count, which must be an unsigned integer (GX_SHBY, at most the width),
; or by a computed one, an unsigned integer (GX_SHVAR). Each diagnostic
; blames the left operand.

EX_SHIFT:
    LD   A,(EX_RMETA)
    AND  EX_TMASK
    CP   AG_FIRST
    JP   NC,.MISMATCH
    CALL EX_LBOOL                  ; The left's type:
    JP   Z,.MISMATCH               ; a Boolean is no number,
    CP   AG_FIRST
    JP   NC,.MISMATCH
    CP   SY_F32                    ; and an f32
    JP   Z,.MISMATCH               ; no integer (emitShift).
    LD   C,A                       ; C is the left's type.
    LD   A,(EX_LMETA)              ; Is the left
    RLCA                           ; known?
    JR   NC,.EMIT                  ; No: the code shifts it.
    LD   A,(EX_RMETA)              ; A known left:
    RLCA                           ; the count must be known.
    JP   NC,.NOTYPE                ; It is not.
    LD   A,C                       ; Exact,
    OR   A                         ; or typed?
    JR   NZ,.TYPED                 ; Typed: foldTyped.
    LD   A,(EX_RMETA)              ; Exact: an exact count
    AND  EX_TMASK                  ; too,
    JP   NZ,.NOTYPE                ; or no definite type.
    CALL .COUNT                    ; B is the count, below zero raises
    JP   C,EX_ELEFT                ; out-of-range.
    JR   .FOLD                     ; Fold it.
.TYPED:                        ; A typed left with a known count.
    LD   A,(EX_RMETA)              ; An f32 count
    AND  EX_TMASK                  ; is
    CP   SY_F32                    ; no
    JR   Z,.MISMATCH               ; integer.
    CALL .COUNT                    ; B is the count; below zero
    JR   C,.MISMATCH               ; is a type mismatch.
.FOLD:                         ; B is the count, at most 40; C the type.
    PUSH BC                        ; Keep them.
    CALL VL_LTOK                   ; r = a.
    POP  BC                        ; The count and the type.
    INC  B                         ; Plus one, for the loop's test.
.BIT:                          ; B bits remain, plus one.
    DEC  B                         ; Any?
    JP   Z,EX_FOLD                 ; No: the result; return.
    PUSH BC                        ; Keep the count and the type.
    LD   A,(EX_OPER)               ; shl?
    CP   TK_SHL                    ; Then
    JR   NZ,.HALVE                 ; a doubling,
    CALL VL_SHL                    ; r times two:
    LD   A,C                       ; exact,
    OR   A                         ; it must stay
    JR   NZ,.NEXT                  ; in range at every step.
    LD   HL,EX_KVAL                ; Does it?
    CALL VL_RANGE                  ; No:
    JP   C,EX_ELEFT                ; out-of-range.
    JR   .NEXT                     ; The next bit.
.HALVE:                        ; shr: r halved, rounding down.
    CALL VL_SAR                    ; As floor division by two.
.NEXT:                         ; One bit is done.
    POP  BC                        ; The count and the type.
    JR   .BIT                      ; The next.
.EMIT:                         ; A computed left, pushed.
    LD   A,(EX_RMETA)              ; The count:
    LD   D,A                       ; its metadata.
    AND  EX_TMASK                  ; Its type,
    LD   E,A                       ; in E,
    CP   SY_BOOL                   ; not a Boolean,
    JR   Z,.MISMATCH               ; and
    CALL GX_PROP                   ; unsigned
    RLCA                           ; (an exact count
    JR   C,.MISMATCH               ; has no sign).
    BIT  7,D                       ; A known count?
    JR   Z,.VARIABLE               ; No: shifted in a loop.
    PUSH BC                        ; Keep the type.
    LD   A,C                       ; The left
    CALL GX_POPV                   ; is popped.
    CALL .COUNT                    ; B is the count; below zero
    JR   C,.MISMATCH               ; is a type mismatch.
    POP  DE                        ; E is the type.
    PUSH DE                        ; Kept.
    LD   A,E                       ; The width
    CALL GX_PROP                   ; in bits:
    AND  7                         ; eight
    ADD  A,A                       ; times
    ADD  A,A                       ; the
    ADD  A,A                       ; size.
    CP   B                         ; Below the count?
    JR   NC,.SHIFT                 ; No: the count.
    LD   B,A                       ; Yes: the width.
.SHIFT:                        ; B is the count to shift by.
    POP  DE                        ; E is the type.
    PUSH DE                        ; Kept.
    LD   A,B                       ; The count,
    LD   C,E                       ; the type:
    CALL GX_SHBY                   ; shifted.
    JR   .TYPE                     ; The result.
.VARIABLE:                     ; A computed count.
    PUSH BC                        ; Keep the type.
    CALL GX_SHVAR                  ; Shifted in a loop.
.TYPE:                         ; The result is the left's type.
    POP  BC                        ; C is it.
    LD   A,C                       ; A run-time result.
    OR   A                         ; Clear carry.
    RET                            ; Return it.
.MISMATCH:                     ; A count or a left of the wrong type:
    LD   A,DG_CLASH                ; type-mismatch,
    JP   EX_ELOP                   ; at the left.
.NOTYPE:                       ; An exact left needs a type:
    LD   A,DG_INFER                ; no-definite-type,
    JP   EX_ELOP                   ; at the left.

;@ROUTINE OUT B,CARRY CLOBBERS A,HL
; The known count in EX_RVAL, for a fold or a shift: carry when it is
; negative, otherwise B, at most 40, beyond which every shift is the same.

.COUNT:                        ; The count is EX_RVAL.
    LD   HL,EX_RVAL+4              ; Its top byte:
    LD   A,(HL)                    ; negative?
    ADD  A,A                       ; Then (nothing shifted in)
    RET  C                         ; carry.
    LD   B,40                      ; At most 40:
    DEC  HL                        ; any of
    OR   (HL)                      ; its three
    DEC  HL                        ; higher
    OR   (HL)                      ; bytes
    DEC  HL                        ; makes
    OR   (HL)                      ; it more,
    RET  NZ                        ; carry clear.
    DEC  HL                        ; Otherwise its low byte
    LD   A,(HL)                    ; is it,
    CP   B                         ; unless
    RET  NC                        ; more than 40.
    LD   B,A                       ; B is the count;
    OR   A                         ; carry clear.
    RET                            ; Done.

;@ROUTINE IN DE,HL OUT HL,CARRY CLOBBERS A,BC,DE,ZERO,SIGN,PARITY,HALFCARRY
; Multiply HL by DE modulo 65536, with carry when the true product does
; not fit sixteen bits. Each of the sixteen steps doubles the product and
; adds HL when the multiplier's next bit, highest first, is set; a carry
; out of either is shifted into the bottom of DE as the multiplier's bits
; leave its top, so DE ends nonzero exactly when the product overflowed.

EX_TIMES:
    LD   B,H                       ; BC is the multiplicand.
    LD   C,L                       ; Complete it.
    LD   HL,0                      ; The product starts at zero.
    LD   A,16                      ; One step per multiplier bit.
.LOOP:                         ; Consider the next bit.
    ADD  HL,HL                     ; Double the product; carry is an overflow.
    RL   E                         ; The overflow enters DE's bottom,
    RL   D                         ; and the multiplier's top bit leaves.
    JR   NC,.NEXT                  ; A clear bit adds nothing.
    ADD  HL,BC                     ; Add the multiplicand.
    JR   NC,.NEXT                  ; Without a carry nothing overflowed.
    SET  0,E                       ; Record the overflow.
.NEXT:                         ; The step is done.
    DEC  A                         ; One fewer.
    JR   NZ,.LOOP                  ; Through all sixteen.
    LD   A,D                       ; Any overflow recorded?
    OR   E                         ; Zero if none.
    ADD  A,$FF                     ; Carry unless A was zero.
    RET                            ; HL is the product.
