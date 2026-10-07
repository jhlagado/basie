;==========================================================================
;  Grammar actions: routines, failure and handlers
;==========================================================================
;
;  The actions for routine signatures, forward declarations, routine and
;  main bodies, recoverable failure (fail, `else fail`) and local handlers
;  (`handle`). The calling convention and the declaration state are those
;  of ACTIONS.ASM.
;
;  Principal entries:
;    AC_MAIN   main must exist and every forward must be completed
;    AC_SIG, AC_PROTO, AC_SEAL  routine and forward signatures (RetainSubName
;              is EX_KEEP: the name is checked later)
;    AC_PARAM, AC_JOIN, AC_GIVES, AC_GIVEN, AC_FAILS  signature parts
;    AC_BODY, AC_IMPL, AC_END  open and close a routine or main body
;    AC_FAIL, AC_THROW  the fail statement
;    AC_ROUTE, AC_RELAY  attach `else fail` or a handler to a failable call
;    AC_ONERR  open a handler (AC_NOERR, in ACTSTMT.ASM, closes it)
;    AC_SAFE, AC_ELEAK  reject an unhandled failure
;    AC_LIVE, AC_DEAD  set the fallthrough state
;
;  Routines. The routine being declared is RO_CUR: an index into the
;  routine table RO_RTAB (CALLWORK.ASM), or $FF for main. Its signature is
;  gathered in RO_CPIDX, RO_CPCNT, RO_CTYPE, RO_CFLAG and RO_CARGS, and
;  AC_PUB copies it into the routine's record with the routine's ordinal,
;  which makes the routine visible to calls, its own body included. A
;  forward routine (RO_FFWD) is published where it is declared, so it
;  takes its ordinal there, as the reference's does; RO_FOPEN marks it
;  until its body comes. A forward main is refused (DG_NYI). Main's flags
;  live in RO_MFLAG. A body is written as a blob while it is parsed:
;  AC_BEGIN and AC_ENTRY open it (RG_OPEN) and AC_END closes it (RG_CLOSE)
;  and records its need.
;
;  Failure (the reference's failure model, D41). A routine fails by
;  returning with carry set and the code in A. A call to a failable
;  routine decides at once how its failure is consumed (RO_FAILS): before
;  `else fail` it writes JP C,exit, and before `handle` JP C to a new
;  label; anything else raises DG_LEAK. RO_PEND then holds $80 plus that
;  label (RG_EXIT for `else fail`) until the statement's end consumes it
;  (AC_ROUTE, AC_RELAY), and RO_KEPT the temporaries' bytes pushed beneath
;  the call, which a handler drops.
;
;  Fallthrough. CT_FALLS is nonzero while control can reach the current
;  point. A routine with a result may not fall off its end (DG_FLOW).

; ------------------------------------------------------- routines and main

; ------------------------------------------------------ parts and visibility

;@ROUTINE OUT A,CARRY,ZERO CLOBBERS SIGN,PARITY,HALFCARRY,BC,DE,HL
; BeginTopLevel: a top-level declaration begins, public unless marked
; (MarkPrivate). Its first token is the lookahead, so SRC_ID is its part:
; when that is not the last declaration's part (AC_DPART), the part has
; ended (AC_ENDP), as the reference's compile loop finds before each
; declaration.

AC_TOP:
    XOR  A                         ; Public
    LD   (AC_PRIV),A               ; unless marked.
    LD   A,(SRC_ID)                ; The declaration's part:
    LD   HL,AC_DPART               ; is it
    CP   (HL)                      ; the last one's?
    RET  Z                         ; Yes: nothing has ended.
    LD   C,(HL)                    ; The part that ended,
    LD   (HL),A                    ; this one now,
    LD   A,C                       ; or none
    OR   A                         ; before the first
    RET  Z                         ; declaration; fall into AC_ENDP.

;@ROUTINE CLOBBERS A,BC,DE,HL,CARRY,ZERO,SIGN,PARITY,HALFCARRY
; A part has ended (the reference's endPart), or the program has: a
; private forward of it not completed is forward-incomplete, at its
; `forward` (the reference's declaredAt), found back from its name over
; `sub` and the spaces between (a declaration's tokens are on one line);
; then its private routines' and symbols' names go out of scope, cut to
; no characters, which no name matches. The privates of earlier parts
; were complete when they ended, and are cut already.

AC_ENDP:
    LD   A,(RO_RCNT)               ; The routines,
    LD   C,A                       ; C of them,
    LD   B,0                       ; from the first.
.ROUTINE:                      ; B is the next, C remain.
    LD   A,C                       ; Any left?
    OR   A                         ; If not,
    JR   Z,.SYMBOLS                ; the symbols.
    LD   A,B                       ; Its
    CALL RO_SUBAT                  ; record, HL:
    PUSH HL                        ; kept.
    LD   DE,RO_RFLAG               ; Its
    ADD  HL,DE                     ; flags,
    LD   A,(HL)                    ; A.
    POP  HL                        ; The record.
    BIT  5,A                       ; RO_FPRIV: a public one
    JR   Z,.PUBLIC                 ; stays;
    AND  RO_FOPEN                  ; a private one still open
    JR   NZ,.OPEN                  ; is incomplete;
    INC  HL                        ; any other's
    INC  HL                        ; name
    LD   (HL),A                    ; is cut (A is zero).
.PUBLIC:                       ; Routine B is done.
    INC  B                         ; The next.
    DEC  C                         ; One fewer.
    JR   .ROUTINE                  ; Until all are.
.SYMBOLS:                      ; The symbols, all the program's.
    CALL PL_ENDP                   ; Forward pools must be complete.
    LD   HL,(SY_BTM)               ; Each symbol:
.SYMBOL:                       ; HL is the next record.
    LD   DE,(SY_TOP)               ; past
    OR   A                         ; the
    SBC  HL,DE                     ; last,
    ADD  HL,DE                     ; the part's
    RET  Z                         ; private names are gone.
    PUSH HL                        ; (the record)
    LD   DE,SY_FLAGS               ; Its flags:
    ADD  HL,DE                     ; private?
    LD   A,(HL)                    ; (cleared, for
    LD   (HL),0                    ; a later part's)
    POP  HL                        ; The record.
    RRA                            ; SY_FPRIV:
    JR   NC,.SHOWN                 ; a public one stays;
    INC  HL                        ; a private
    INC  HL                        ; one's name
    LD   (HL),0                    ; is cut.
    DEC  HL                        ; The
    DEC  HL                        ; record.
.SHOWN:                        ; HL is done.
    LD   DE,SY_RECB                ; The
    ADD  HL,DE                     ; next.
    JR   .SYMBOL                   ; Until all are.
.OPEN:                         ; HL is the record.
    LD   DE,RO_RPART               ; Its part
    ADD  HL,DE                     ; and the offset
    LD   D,(HL)                    ; of its
    INC  HL                        ; `forward`
    LD   A,(HL)                    ; (AC_SIG),
    INC  HL                        ; where
    LD   H,(HL)                    ; it is
    LD   L,A                       ; reported:
    LD   E,DG_UNMET                ; forward-incomplete.
    JP   DG_PLACE                  ; No return.

;@ROUTINE IN HL OUT HL CLOBBERS A,DE,CARRY,ZERO,SIGN,PARITY,HALFCARRY
; The offset in the current part of `forward` before `sub` and the routine's
; name, at offset HL (a declaration's tokens are on one line): back from
; the name over the spaces and tabs to `sub`, then to `forward`. BC is
; kept.

AC_FWDAT:                      ; HL is the name's offset.
    PUSH HL                        ; (kept)
    LD   A,(SRC_ID)                ; The part's
    DEC  A                         ; entry,
    CALL SRC_PART                  ; its
    LD   DE,PT_START               ; first
    ADD  HL,DE                     ; byte,
    LD   E,(HL)                    ; DE;
    INC  HL                        ; plus
    LD   D,(HL)                    ; the
    POP  HL                        ; offset,
    ADD  HL,DE                     ; the name's address.
    PUSH DE                        ; (the start kept)
    CALL .BACK                     ; Back over the spaces to `sub`'s b,
    DEC  HL                        ; back
    DEC  HL                        ; to its s,
    CALL .BACK                     ; over the spaces to `forward`'s d,
    LD   DE,1-7                    ; back
    ADD  HL,DE                     ; to its f,
    POP  DE                        ; less
    OR   A                         ; the part's
    SBC  HL,DE                     ; start.
    RET                            ; HL is its offset.
.BACK:                         ; HL is after spaces and tabs.
    DEC  HL                        ; The byte before:
    LD   A,(HL)                    ; a space
    CP   ' '                       ; or
    JR   Z,.BACK                   ; a tab
    CP   9                         ; is passed;
    JR   Z,.BACK                   ; anything else
    RET                            ; ends a word.

;@ROUTINE OUT A
; MarkPrivate: the declaration that follows is private (D33).

AC_MARK:
    LD   A,1                       ; Mark it.
    LD   (AC_PRIV),A               ; SY_CMT and AC_VIS read it.
    RET                            ; Back to the engine.

;@ROUTINE OUT A,CARRY,ZERO CLOBBERS SIGN,PARITY,HALFCARRY,HL
; Take the declaration's visibility for a routine: A returns RO_FPRIV if
; it is private, else zero, and AC_PRIV is cleared, so the routine's
; parameters and locals are not private symbols.

AC_VIS:
    LD   HL,AC_PRIV                ; The mark
    LD   A,(HL)                    ; is taken
    LD   (HL),0                    ; and cleared:
    OR   A                         ; a public routine
    RET  Z                         ; has no flag,
    LD   A,RO_FPRIV                ; a private one
    RET                            ; RO_FPRIV.

;@ROUTINE NORETURN
; EndTopLevel: a declaration must end in the part where it began (spec
; 4.3.1): if the part of its last token, its line's end, is not, raise
; syntax there, as the reference's topLevel does.

AC_SPLIT:
    LD   A,(AC_DPART)              ; The part it began in:
    LD   HL,SRC_ID                 ; is it
    CP   (HL)                      ; the part it ends in?
    RET  Z                         ; Yes.
    CALL DG_RAISE                  ; No: syntax,
    DB   DG_DECL                   ; at its last token.

; ------------------------------------------------------- routines and main

;@ROUTINE OUT A,CARRY,ZERO CLOBBERS SIGN,PARITY,HALFCARRY,BC,DE,HL
; RequireMain, at the end of the program, as the reference's compile ends
; it: the last part ends (its private forwards complete, AC_ENDP), no
; forward routine may be left without its body (forward-incomplete, at its
; name), and main must have a body (missing-main).

AC_MAIN:
    CALL AC_ENDP                   ; The last part ends, and the program.
    LD   A,(RO_RCNT)               ; The routines declared.
    LD   B,A                       ; Count them in B.
    XOR  A                         ; Start at index zero...
    LD   C,A                       ; ...in C.
.LOOP:                         ; Check routine C.
    LD   A,B                       ; Any left?
    OR   A                         ; Zero means all are complete.
    JR   Z,.ENTRY                  ; Every forward has its body.
    LD   A,C                       ; The routine's index.
    CALL RO_SUBAT                  ; HL addresses its record.
    LD   DE,RO_RFLAG               ; Address its flags.
    ADD  HL,DE                     ; HL addresses RO_RFLAG.
    LD   A,(HL)                    ; Fetch them.
    AND  RO_FOPEN                  ; Still waiting for a body?
    JR   NZ,.PARTIAL               ; Yes: raise DG_UNMET.
    INC  C                         ; Next routine.
    DEC  B                         ; One fewer to check.
    JR   .LOOP                     ; Check it.
.ENTRY:                        ; Every forward is complete.
    LD   A,(RO_MFLAG)              ; Main's flags
    AND  RO_FMAIN                  ; say whether it was declared.
    RET  NZ                        ; It was.
    CALL DG_RAISE                  ; The program has no main:
    DB   DG_MAIN                   ; missing-main, at its end.
.PARTIAL:                      ; A forward has no body.
    LD   A,C                       ; Its record:
    CALL RO_SUBAT                  ; HL.
    LD   A,DG_UNMET                ; forward-incomplete,
    CALL DG_SETN                   ; naming it,
    LD   A,C                       ; at
    CALL RO_SUBAT                  ; its
    LD   DE,RO_RPART               ; name,
    ADD  HL,DE                     ; in
    LD   D,(HL)                    ; its part,
    INC  HL                        ; which
    LD   A,(HL)                    ; may be
    INC  HL                        ; another,
    LD   H,(HL)                    ; at its
    LD   L,A                       ; offset:
    LD   E,DG_UNMET                ; forward-incomplete.
    JP   DG_PLACE                  ; No return.

;@ROUTINE OUT A,CARRY,ZERO CLOBBERS SIGN,PARITY,HALFCARRY,BC,DE,HL
; Make the retained name the current token again, at its own position, so
; that checks and diagnostics refer to it.

AC_RESUB:
    CALL EX_RENEW                  ; Restore the retained spelling as the token.
    LD   HL,AC_DPOS                ; Restore its position...
    LD   DE,TK_POS                 ; ...as the token's.
    CALL PR_COPY                   ; Copy offset, line and column.
    OR   A                         ; Clear carry.
    RET                            ; The name is current.

;@ROUTINE OUT A,CARRY,ZERO CLOBBERS SIGN,PARITY,HALFCARRY
; Start a signature with no parameters, no argument bytes and no result.
; Returns A zero.

AC_CLEAR:
    XOR  A                         ; Zero...
    LD   (RO_CPCNT),A              ; ...parameters,
    LD   (RO_CARGS),A              ; ...argument bytes
    LD   (RO_CTYPE),A              ; ...and no result type.
    RET                            ; A is zero.

;@ROUTINE OUT A,CARRY,ZERO CLOBBERS SIGN,PARITY,HALFCARRY,BC,DE,HL,IX
; BeginSub: open a routine signature. For main, check the name is new
; (DG_DUP) and make RO_CUR $FF. For another routine, check the table has
; room (DG_PROCS), the name is new (DG_DUP) and not `id` (DG_CLASH), and
; start its record: name and first parameter index.

AC_SIG:
    CALL AC_RESUB                  ; The routine's name is current again.
    CALL .FRESH                    ; Reject a name already in use.
    CALL EX_MAIN                   ; Is the name `main`?
    JR   C,.MAIN                   ; Yes: open main.
    LD   A,(RO_RCNT)               ; The routines so far.
    CP   RO_RCAP                   ; Room for another?
    JR   NC,.FULL                  ; No: raise DG_PROCS.
    LD   HL,KW_ID                  ; `id (` is always the conversion
    LD   B,2                       ; (spec 3.5), so no routine
    CALL TK_MATCH                  ; may be named id:
    LD   A,DG_CLASS                ; raise wrong-class,
    JP   C,DG_NAMED                ; naming it.
    LD   A,(RO_RCNT)               ; The new routine's index.
    LD   (RO_CUR),A                ; It is the routine being declared.
    CALL RO_SUBAT                  ; HL addresses its record.
    CALL TK_KEEP                   ; Record its name; HL addresses the length.
    INC  HL                        ; Step to RO_RPIDX.
    LD   A,(RO_PCNT)               ; The next free parameter entry...
    LD   (HL),A                    ; ...is its first parameter...
    LD   (RO_CPIDX),A              ; ...in the record and the signature.
    CALL AC_CLEAR                  ; No parameters or result yet.
    CALL AC_VIS                    ; The routine's flags: private, or none,
    LD   (RO_CFLAG),A              ; yet.
    LD   A,(RO_CUR)                ; Its record:
    CALL RO_SUBAT                  ; the part
    LD   DE,RO_RPART               ; and offset
    ADD  HL,DE                     ; where a forward
    LD   A,(SRC_ID)                ; left open is
    LD   (HL),A                    ; reported when
    INC  HL                        ; its part may
    PUSH HL                        ; be gone (AC_ENDP):
    LD   HL,(AC_DPOS)              ; its name,
    LD   A,(RO_CFLAG)              ; or for
    BIT  5,A                       ; a private one (RO_FPRIV)
    CALL NZ,AC_FWDAT               ; its `forward`.
    EX   DE,HL                     ; The offset,
    POP  HL                        ; in
    LD   (HL),E                    ; the
    INC  HL                        ; record.
    LD   (HL),D                    ; Kept.
    RET                            ; Back to the engine.
.MAIN:                         ; Open main's signature.
    LD   A,(AC_PRIV)               ; Main can't be private:
    OR   A                         ; bad-main,
    JP   NZ,AC_EMAIN               ; at its name.
    LD   A,$FF                     ; Main is being declared.
    LD   (RO_CUR),A                ; Mark it.
    CALL AC_CLEAR                  ; No parameters or result.
    LD   A,RO_FMAIN                ; Main's flag...
    LD   (RO_CFLAG),A              ; ...begins its flags.
    RET                            ; Back to the engine.
.FULL:                         ; The routine table is full.
    CALL DG_RAISE                  ; Abandon the build.
    DB   DG_PROCS                  ; Too many routines.

;@ROUTINE CLOBBERS A,BC,DE,HL,CARRY,ZERO,SIGN,PARITY,HALFCARRY
; Reject the current name, a routine's being declared, if it is already
; taken, naming it: a forward still awaiting its body is completed by
; `sub NAME` alone (DG_FWDNO); any other routine, main, a program-wide
; symbol or a predeclared name is a duplicate (DG_DUP).

.FRESH:                        ; The routine's name is current.
    CALL SY_FIND                   ; A program-wide symbol?
    JP   C,EX_EDUP                 ; A duplicate.
    CALL RO_FIND                   ; A routine?
    JR   Z,.ROUTINE                ; Yes: which?
    LD   A,DG_DUP                  ; If not, a duplicate
    JP   RO_FRESH                  ; of a predeclared name, or free.
.ROUTINE:                      ; A is the routine's index.
    CP   RO_MAIN                   ; Main, declared already,
    JP   Z,EX_EDUP                 ; is a duplicate.
    CALL RO_SUBAT                  ; HL is the routine's record.
    LD   DE,RO_RFLAG               ; Its flags:
    ADD  HL,DE                     ; a forward still open
    BIT  2,(HL)                    ; (RO_FOPEN)
    JP   Z,EX_EDUP                 ; is completed by `sub NAME` alone;
    LD   A,DG_FWDNO                ; another, a duplicate.
    JP   DG_NAMED                  ; Raise it, named.

;@ROUTINE OUT A,CARRY,ZERO CLOBBERS SIGN,PARITY,HALFCARRY,BC,DE,HL,IX
; BeginForward: build the signature as AC_SIG does and mark it forward and
; open: its body comes later, in the short form `sub NAME`, and its
; prologue checks the stack (RG_OPEN). The program's limits record says it
; has a forward routine. A forward main is refused (DG_NYI).

AC_PROTO:
    CALL AC_SIG                    ; Build the signature.
    LD   A,(RO_CUR)                ; Is it main's?
    INC  A                         ; $FF becomes zero.
    JP   Z,TR_OPER                 ; Refused.
    LD   (RG_FWD),A                ; Nonzero: a routine is forward.
    LD   A,(RO_CFLAG)              ; Its flags.
    OR   RO_FOPEN+RO_FFWD          ; Waiting for a body; checked.
    LD   (RO_CFLAG),A              ; Keep them.
    RET                            ; Back to the engine.

;@ROUTINE CLOBBERS A,BC,DE,HL,CARRY,ZERO,SIGN,PARITY,HALFCARRY
; RetainParameter: main takes no parameters (DG_RPAR). Otherwise the name
; must not collide (RO_VET) and is kept in AC_DNAME until its type is
; known, its offset in AC_SPOS.

AC_PARAM:
    LD   A,(RO_CUR)                ; The routine declared.
    INC  A                         ; Is it main?
    JR   Z,.MAIN                   ; Yes: no parameters.
    CALL RO_VET                    ; Reject a colliding parameter name.
    LD   HL,(TK_POS)               ; Its offset
    LD   (AC_SPOS),HL              ; for AC_JOIN.
    LD   HL,AC_DNAME               ; Keep the name...
    CALL TK_KEEP                   ; ...for AC_JOIN.
    RET                            ; Back to the engine.
.MAIN:                         ; Main has a parameter.
    JR   AC_EMAIN                  ; Raise bad-main.

;@ROUTINE OUT A,CARRY,ZERO CLOBBERS SIGN,PARITY,HALFCARRY,HL
; MarkVarParameter: the parameter being parsed is var.

AC_VARP:
    LD   A,1                       ; Nonzero
    LD   (RO_VARP),A               ; until AC_JOIN.
    RET                            ; Back to the engine.

;@ROUTINE OUT A,CARRY,ZERO CLOBBERS SIGN,PARITY,HALFCARRY,BC,DE,HL
; CommitParameter: append the retained name with the current type, a var
; parameter's with AG_VAR: only an aggregate may be var (var-parameter,
; at the name).

AC_JOIN:
    CALL EX_RENEW                  ; The parameter's name is current again.
    LD   A,(AG_CTYPE)              ; Its type:
    CALL HN_PTYPE                  ; an owning handle, not var; no owning type yet.
    LD   HL,RO_VARP                ; Is it var?
    DEC  (HL)                      ; Zero if it was,
    LD   (HL),0                    ; (cleared)
    JP   NZ,RO_ENROL               ; else append it; return.
    CP   AG_FIRST                  ; A scalar
    JR   C,.EVAR                   ; or
    CP   AG_FILE                   ; a File
    JR   Z,.EVAR                   ; is never var.
    OR   AG_VAR                    ; Marked var,
    JP   RO_ENROL                  ; it is appended; return.
.EVAR:                         ; var on a scalar or a File:
    LD   A,DG_VARP                 ; var-parameter,
    JP   DG_KEPT                   ; at its name. No return.

;@ROUTINE OUT A CLOBBERS ZERO,SIGN,PARITY,HALFCARRY
; AllowSubResult: main has no result (bad-main).

AC_GIVES:
    LD   A,(RO_CUR)                ; The routine declared.
    INC  A                         ; Is it main?
    RET  NZ                        ; Another routine may return a value.

;@ROUTINE NORETURN
; Raise bad-main at main's name (AC_DPOS): main takes no parameters and
; returns nothing.

AC_EMAIN:
    LD   A,DG_BADMN                ; bad-main,
    LD   HL,AC_DPOS                ; at main's name.
    JP   DG_AT                     ; No return.

;@ROUTINE OUT A,CARRY,ZERO CLOBBERS SIGN,PARITY,HALFCARRY,HL
; MarkVarResult: the routine's aggregate result is writable (RO_FVRES).

AC_VARR:
    LD   HL,RO_CFLAG               ; The routine's flags
    SET  4,(HL)                    ; gain RO_FVRES.
    RET                            ; Back to the engine.

;@ROUTINE OUT A CLOBBERS CARRY,ZERO,SIGN,PARITY,HALFCARRY
; SaveSubResult: the current type is the result type; not a view
; (DG_CLASH), nor yet a File (DG_NYI).

AC_GIVEN:
    CALL AC_ITEM                   ; The result type: not a view, nor yet a File,
    CALL HN_RTYPE                  ; an owning handle, not yet another or owning.
    LD   (RO_CTYPE),A              ; The routine's result type.
    RET                            ; Back to the engine.

;@ROUTINE OUT A,CARRY,ZERO CLOBBERS SIGN,PARITY,HALFCARRY,BC,DE,HL
; FromClause: after a result type, `from` and the names of aggregate
; parameters in which the result may be rooted (from-clause otherwise,
; naming it), each marked in RO_FROM; a name other than `from` is the
; line's end expected, at it.

AC_FROM:
    CALL PR_PEEK                   ; A name next?
    CP   TK_NAME                   ; If not,
    RET  NZ                        ; there is no from clause.
    CALL PR_TAKE                   ; Take it:
    LD   HL,KW_FROM                ; it must
    LD   B,4                       ; be
    CALL TK_MATCH                  ; `from`,
    JR   NC,.EOL                   ; else the line should end.
.NEXT:                         ; A parameter's name follows.
    CALL RO_NAME                   ; Consume it.
    CALL RO_PFIND                  ; A parameter of the signature,
    JR   NC,.EFROM                 ; B its index, HL its record?
    LD   DE,RO_PTYPE               ; Its type
    ADD  HL,DE                     ; less
    LD   A,(HL)                    ; AG_VAR
    AND  $7F                       ; must be
    CALL PL_ISHND                  ; an aggregate,
    JR   C,.EFROM                  ; not a handle,
    CP   AG_FIRST                  ; nor
    JR   C,.EFROM                  ; a scalar
    CP   AG_FILE                   ; nor
    JR   Z,.EFROM                  ; a File.
    LD   A,B                       ; Its bit
    LD   HL,RO_FROM                ; in RO_FROM
    CALL SY_BITAT                  ; is
    OR   (HL)                      ; set.
    LD   (HL),A                    ; Kept.
    CALL PR_PEEK                   ; A comma
    CP   TK_COMMA                  ; brings
    RET  NZ                        ; another;
    CALL PR_TAKE                   ; take it,
    JR   .NEXT                     ; and the name.
.EOL:                          ; Not `from`:
    CALL DG_RAISE                  ; the line's end
    DB   DG_EOL                    ; expected, at the name.
.EFROM:                        ; No aggregate parameter of the name:
    CALL DG_RNAME                  ; from-clause,
    DB   DG_FROM                   ; naming it.

;@ROUTINE CLOBBERS HL
; MarkSubFails: the routine can fail.

AC_FAILS:
    LD   HL,RO_CFLAG               ; The routine's flags
    SET  0,(HL)                    ; gain RO_FFAIL.
    RET                            ; Back to the engine.

;@ROUTINE OUT A,CARRY,ZERO CLOBBERS SIGN,PARITY,HALFCARRY,BC,DE,HL,IX
; BeginForwardBody: `sub NAME` without a signature opens the body of an
; open forward, recovering the signature it stored. A name that is no
; routine, main, a routine whose body exists, or a completion whose
; visibility is not the forward's, raises forward-mismatch.

AC_IMPL:
    CALL AC_RESUB                  ; The routine's name is current again.
    CALL RO_FIND                   ; Z, and A its index, if declared.
    JR   NZ,.MISSING               ; Not declared: no forward.
    CP   RO_MAIN                   ; Main is never forward.
    JR   Z,.MISSING                ; Raise forward-mismatch.
    LD   (RO_CUR),A                ; It is the routine being defined.
    CALL RO_SUBAT                  ; HL addresses its record.
    LD   DE,RO_RPIDX               ; Skip the name...
    ADD  HL,DE                     ; ...to the signature.
    LD   A,(HL)                    ; Its first parameter...
    LD   (RO_CPIDX),A              ; ...for the body.
    INC  HL                        ; Step to RO_RPCNT.
    LD   A,(HL)                    ; Its parameter count.
    LD   (RO_CPCNT),A              ; Recover it.
    INC  HL                        ; Step to RO_RTYPE.
    LD   A,(HL)                    ; Its result type.
    LD   (RO_CTYPE),A              ; Recover it.
    INC  HL                        ; Step to RO_RFLAG.
    BIT  2,(HL)                    ; RO_FOPEN: still waiting for a body?
    JR   Z,.MISSING                ; No: no forward is incomplete.
    PUSH HL                        ; Keep the flags' place.
    CALL AC_VIS                    ; The completion's visibility
    POP  HL                        ; and
    XOR  (HL)                      ; the forward's
    AND  RO_FPRIV                  ; must agree.
    JR   NZ,.MISSING               ; They differ.
    LD   A,(HL)                    ; Its flags.
    AND  $FF-RO_FOPEN              ; The body is here.
    LD   (HL),A                    ; In the record...
    LD   (RO_CFLAG),A              ; ...and the signature.
    LD   DE,RO_RARGS-RO_RFLAG      ; Then the argument bytes:
    ADD  HL,DE                     ; HL addresses them.
    LD   A,(HL)                    ; Recover
    LD   (RO_CARGS),A              ; them.
    JR   AC_BEGIN                  ; Open the body.
.MISSING:                      ; No forward to complete.
    CALL DG_RNAME                  ; Abandon the build, naming it:
    DB   DG_FWDNO                  ; forward-mismatch.

;@ROUTINE OUT A,CARRY,ZERO CLOBBERS SIGN,PARITY,HALFCARRY,BC,DE,HL
; BeginSubBody: after a full signature, open main's body, or publish the
; routine (making it callable from its own body) and open its body.

AC_BODY:
    LD   A,(RO_CUR)                ; The routine declared.
    INC  A                         ; Is it main?
    JR   Z,AC_ENTRY                ; Yes: open main's body.
    CALL AC_PUB                    ; Publish the signature.
    JR   AC_BEGIN                  ; Open the body.

;@ROUTINE OUT A CLOBBERS CARRY,ZERO,SIGN,PARITY,HALFCARRY,DE,HL
; Copy the signature into the record of the routine declared, RO_CUR,
; with the routine's ordinal, the next (RG_ADD), and a need of zero until
; its body is complete, and count the routine as declared.

AC_PUB:
    LD   A,(RO_CUR)                ; The routine declared:
    CALL RO_SUBAT                  ; HL addresses its record.
    LD   DE,RO_RPCNT               ; Skip the name and first parameter...
    ADD  HL,DE                     ; ...to RO_RPCNT.
    LD   A,(RO_CPCNT)              ; The parameter count.
    LD   (HL),A                    ; Store it.
    INC  HL                        ; Step to RO_RTYPE.
    LD   A,(RO_CTYPE)              ; The result type.
    LD   (HL),A                    ; Store it.
    INC  HL                        ; Step to RO_RFLAG.
    LD   A,(RO_CFLAG)              ; The flags.
    LD   (HL),A                    ; Store them.
    INC  HL                        ; Step to RO_RORD.
    PUSH HL                        ; Keep the place.
    CALL RG_ADD                    ; HL is the routine's ordinal.
    EX   DE,HL                     ; DE is the ordinal.
    POP  HL                        ; The place.
    LD   (HL),E                    ; The ordinal,
    INC  HL                        ; low byte
    LD   (HL),D                    ; and high byte.
    XOR  A                         ; The need is zero
    INC  HL                        ; until the body
    LD   (HL),A                    ; is complete,
    INC  HL                        ; both
    LD   (HL),A                    ; bytes.
    INC  HL                        ; Step to RO_RARGS.
    LD   A,(RO_CARGS)              ; The argument bytes.
    LD   (HL),A                    ; Store them.
    LD   HL,RO_RCNT                ; Count the routine...
    INC  (HL)                      ; ...so that RO_FIND sees it.
    RET                            ; The routine is published.

AC_SEAL EQU  AC_PUB            ; CommitForward: publish, taking the ordinal.

;@ROUTINE OUT A,CARRY,ZERO CLOBBERS SIGN,PARITY,HALFCARRY
; Enter a body's scope: remember how many symbols are global and close
; every control frame. Returns A zero.

AC_SCOPE:
    PUSH HL                        ; Keep HL.
    LD   HL,(SY_TOP)               ; Symbols so far are all global.
    LD   (SY_GTOP),HL              ; AC_END discards the rest.
    POP  HL                        ; HL again.
    XOR  A                         ; No control
    LD   (CT_DEPTH),A              ; frames are open.
    RET                            ; A is zero.

;@ROUTINE OUT A,CARRY,ZERO CLOBBERS SIGN,PARITY,HALFCARRY,BC,DE,HL
; Open a routine's body: begin its blob, with the name and ordinal of its
; record (RG_OPEN), make its start reachable and bind each parameter to
; its argument's offset from IX (RO_BIND).

AC_BEGIN:
    CALL AC_SCOPE                  ; Enter the body's scope.
    LD   A,(RO_CUR)                ; The routine's record
    CALL RO_SUBAT                  ; is at HL; its name comes first:
    LD   C,(HL)                    ; the spelling's
    INC  HL                        ; address
    LD   B,(HL)                    ; in BC,
    INC  HL                        ; then,
    PUSH BC                        ; keeping it,
    LD   B,(HL)                    ; its length in B.
    LD   DE,RO_RORD-RO_RNLEN       ; Its ordinal
    ADD  HL,DE                     ; follows the flags:
    LD   E,(HL)                    ; DE is
    INC  HL                        ; the
    LD   D,(HL)                    ; ordinal.
    POP  HL                        ; HL is the name.
    CALL RG_OPEN                   ; Begin the routine's blob.
    CALL AC_LIVE                   ; The body's start is reachable.
    LD   A,(RO_CPCNT)              ; Bind each parameter:
    LD   B,A                       ; B counts those left,
    LD   A,(RO_CPIDX)              ; D is the parameter entry,
    LD   D,A                       ; ...from the first,
    XOR  A                         ; E is the argument index,
    LD   E,A                       ; ...from zero.
.BINDLOOP:                     ; Bind one parameter.
    LD   A,B                       ; Any left?
    OR   A                         ; Zero means all are bound:
    JR   Z,AC_BLOCK                ; the body's block opens.
    CALL RO_DISP                   ; C is the argument's displacement.
    LD   A,D                       ; The parameter entry.
    PUSH DE                        ; Keep the indices.
    PUSH BC                        ; Keep the count.
    CALL RO_BIND                   ; Make it a symbol at that offset.
    POP  BC                        ; Recover the count.
    POP  DE                        ; Recover the indices.
    INC  D                         ; Next parameter entry.
    INC  E                         ; Next argument.
    DEC  B                         ; One fewer.
    JR   .BINDLOOP                 ; Bind it.

;@ROUTINE OUT A,CARRY,ZERO CLOBBERS SIGN,PARITY,HALFCARRY,BC,DE,HL
; Open main's body: keep its flags, enter the scope, take its ordinal and
; begin its blob, keep the ordinal for the entry record, and make the body
; reachable. Main has no result.

AC_ENTRY:
    LD   A,(RO_CFLAG)              ; Main's flags...
    LD   (RO_MFLAG),A              ; ...are kept.
    CALL AC_SCOPE                  ; Enter the scope; A is zero.
    LD   (RO_CTYPE),A              ; Main has no result type.
    CALL RG_ADD                    ; HL is main's ordinal,
    LD   (RG_MAIN),HL              ; the program's entry.
    EX   DE,HL                     ; DE is the ordinal.
    LD   HL,KW_MAIN                ; Its name,
    LD   B,4                       ; four characters.
    CALL RG_OPEN                   ; Begin main's blob; fall into AC_BLOCK.

;@ROUTINE OUT A,CARRY,ZERO CLOBBERS SIGN,PARITY,HALFCARRY
; The body's block opens after the parameters (the reference's block in
; the routine's scope): its symbols are those from SY_TOP on, and
; SY_BODY holds that record's address until the body ends (SY_HERE), and
; RO_TBASE the types so far, which outlive it. Its start is reachable.

AC_BLOCK:
    PUSH HL                        ; Keep HL.
    LD   HL,(SY_TOP)               ; The first record of the block,
    LD   (SY_BODY),HL              ; never zero, marks a body as open;
    POP  HL                        ; and the types
    LD   A,(AG_TCNT)               ; so far outlive it, those it makes
    LD   (RO_TBASE),A              ; not (AG_SCOPE); fall into AC_LIVE.

;@ROUTINE OUT A,CARRY,ZERO CLOBBERS SIGN,PARITY,HALFCARRY
; Control can reach this point.

AC_LIVE:
    LD   A,1                       ; Reachable.
    LD   (CT_FALLS),A              ; Record it.
    OR   A                         ; Clear carry.
    RET                            ; Back to the engine.

;@ROUTINE OUT A,CARRY,ZERO CLOBBERS SIGN,PARITY,HALFCARRY,BC,DE,HL,IX
; EndSub: close main's body, or close a routine's: one with a result may
; not fall off its end (DG_FLOW). Write the blob (RG_CLOSE), keep main's
; need for the limits record or the routine's in its record, and discard
; the routine's parameters and locals.

AC_END:
    LD   A,(RO_CUR)                ; The routine closed.
    INC  A                         ; Is it main?
    JR   Z,.CLOSE                  ; Main has no result.
    LD   A,(RO_CTYPE)              ; Does it return a value?
    OR   A                         ; Zero means no result.
    JR   Z,.CLOSE                  ; Then falling off the end is a return.
    LD   A,(CT_FALLS)              ; Can control reach the end?
    OR   A                         ; Zero means every path returned.
    JR   NZ,.FLOW                  ; Then a path returns no value.
.CLOSE:                        ; Close the routine.
    CALL HN_ENDR                   ; Its body's owners freed, its parameters'
    CALL HN_PEND                   ; when it falls off its end.
    CALL RG_CLOSE                  ; Write its blob; HL is its need.
    LD   A,(RO_CUR)                ; Was it main?
    INC  A                         ; $FF becomes zero.
    JR   NZ,.NEED                  ; No: the need goes in its record.
    LD   (RG_NEED),HL              ; Main's need sets the stack reserve.
    JR   .SCOPE                    ; Leave the scope.
.NEED:                         ; A routine's need.
    LD   B,H                       ; BC is
    LD   C,L                       ; the need.
    DEC  A                         ; The routine's index:
    CALL RO_SUBAT                  ; HL addresses its record.
    LD   DE,RO_RNEED               ; Its need
    ADD  HL,DE                     ; is
    LD   (HL),C                    ; complete,
    INC  HL                        ; both
    LD   (HL),B                    ; bytes.
.SCOPE:                        ; Leave the routine's scope.
    LD   HL,(SY_GTOP)              ; Keep only the global symbols:
    CALL SY_CUT                    ; parameters and locals go out of scope,
    CALL AG_SCOPE                  ; and the types the body made.
    LD   HL,0                      ; No body
    LD   (SY_BODY),HL              ; is open.
    XOR  A                         ; A is zero.
    RET                            ; Back to the engine.
.FLOW:                         ; missing-return, at the routine's end
    LD   A,(RO_CUR)                ; naming
    CALL RO_SUBAT                  ; the routine,
    LD   A,DG_FLOW                 ; whose record's name
    CALL DG_SETN                   ; is argument 1.
    LD   HL,TK_ENDP                ; Its closing end
    JP   DG_AT                     ; is where.

; ----------------------------------------------------------------- failure

;@ROUTINE OUT A,CARRY,ZERO CLOBBERS SIGN,PARITY,HALFCARRY
; BeginFail: only a failable routine may fail (DG_LEAK). Expect a u8
; error code.

AC_FAIL:
    LD   A,(RO_CFLAG)              ; The routine's flags.
    AND  RO_FFAIL                  ; Failable?
    JR   Z,AC_ESAFE                ; No: raise not-failable at `fail`.
    LD   A,SY_U8                   ; The code is a u8.
    JP   AC_WANT                   ; Expect it.

;@ROUTINE OUT A,CARRY,ZERO CLOBBERS SIGN,PARITY,HALFCARRY,BC,DE,HL
; CommitFail (failStatement): check the u8 code, with no failure pending,
; and bring it into A; then PUSH AF and POP AF around the frees (none in
; this subset), SCF, carry set for failure, and JP to the exit. The code
; that follows is unreachable.

AC_THROW:
    LD   E,SY_U8                   ; The code must be a u8
    CALL AC_VALOK                  ; with no failure pending.
    CALL GX_TOREG                  ; The code in A.
    CALL HN_FAIL                   ; PUSH AF, the frees, POP AF,
    CALL EM_OP                     ; SCF:
    DB   $37                       ; the routine fails.
    LD   C,$C3                     ; JP
    LD   A,RG_EXIT                 ; to the exit.
    CALL EM_JUMP                   ; Append it; fall into AC_DEAD.

;@ROUTINE OUT A,CARRY,ZERO CLOBBERS SIGN,PARITY,HALFCARRY
; Control cannot reach this point. Returns A zero.

AC_DEAD:
    XOR  A                         ; Unreachable.
    LD   (CT_FALLS),A              ; Record it.
    RET                            ; Back to the engine.

;@ROUTINE IN E OUT A,D,HL,CARRY,ZERO CLOBBERS SIGN,PARITY,HALFCARRY
; Check that the expression just parsed fits type E (EX_FITS) and that no
; failure is left pending after it (AC_SAFE). D returns its metadata and
; HL its value, for GX_TOREG.

AC_VALOK:
    CALL AC_FITTO                  ; Check it against E.
    JP   AC_SAFE                   ; Reject a pending failure.

;@ROUTINE NORETURN
; Raise not-failable at the current token: fail where nothing can fail.

AC_ESAFE:
    CALL DG_RAISE                  ; Abandon the build.
    DB   DG_SAFE                   ; not-failable.

;@ROUTINE NORETURN
; Raise syntax, the end of the line expected: what follows a pending
; failure that no `else fail` or handler can consume where it stands, as
; the reference finds the statement's end there.

AC_ELINE:
    CALL DG_RAISE                  ; Abandon the build.
    DB   DG_EOL                    ; Expected the end of the line.

;@ROUTINE NORETURN
; Raise not-failable at the statement's start (AC_SPOS): `else fail` or a
; handler after a statement whose calls cannot fail.

AC_EMOOT:
    LD   A,DG_SAFE                 ; not-failable,
    JP   DG_KEPT                   ; at the statement. No return.

;@ROUTINE OUT A,CARRY,ZERO CLOBBERS SIGN,PARITY,HALFCARRY,BC,DE,HL
; A failure is pending after a local initializer: only `else fail` may
; follow (DG_LEAK otherwise; a handler would leave the local without a
; value).

AC_RELAY:
    CALL PR_PEEK                   ; What follows the initializer?
    CP   TK_ELSE                   ; `else fail`?
    JR   NZ,AC_ELINE               ; No: the declaration should have ended.

;@ROUTINE OUT A,CARRY,ZERO CLOBBERS SIGN,PARITY,HALFCARRY,BC,DE,HL
; `else fail` follows a call whose failure goes to the exit (RO_FAILS has
; written JP C,exit): consume it, and nothing more may handle the failure
; (DG_LEAK).

AC_PASS:
    CALL PR_TAKE                   ; Consume `else`.
    LD   E,TK_FAIL                 ; It must be `else fail`.
    CALL PR_NEED                   ; Consume `fail`.
    CALL PR_PEEK                   ; What follows?
    CP   TK_HANDL                  ; A handler as well?
    JR   Z,AC_ELINE                ; The statement should have ended.
    CP   TK_ELSE                   ; Another else?
    JR   Z,AC_ELINE                ; Likewise; fall into AC_DROP.

;@ROUTINE OUT A,CARRY,ZERO CLOBBERS SIGN,PARITY,HALFCARRY
; The pending failure is handled. Returns A zero.

AC_DROP:
    XOR  A                         ; Nothing
    LD   (RO_PEND),A               ; is pending.
    RET                            ; Back to the engine.

;@ROUTINE OUT A,CARRY,ZERO CLOBBERS SIGN,PARITY,HALFCARRY,BC,DE,HL
; After a name statement, attach what follows to a pending failure
; (nameStatementTail): `else fail` (AC_PASS), or a handler: open a
; CT_KTRAP frame holding the failure's label, which it frees with its own
; when it closes, and the temporaries the failure leaves on the stack, and
; jump over the handler to its skip label on success. A handler or else
; with nothing pending, or a pending failure with neither, raises DG_LEAK.

AC_ROUTE:
    LD   A,(RO_PEND)               ; Is a failure pending?
    OR   A                         ; Zero means none.
    JR   NZ,.PENDING               ; Attach its handling.
    CALL PR_PEEK                   ; What follows the statement?
    CP   TK_ELSE                   ; `else fail`
    JR   Z,AC_EMOOT                ; with nothing to pass on,
    CP   TK_HANDL                  ; or a handler
    JR   Z,AC_EMOOT                ; with nothing to handle.
    RET                            ; Back to the engine.
.PENDING:                      ; A is $80 and the failure's label.
    AND  $7F                       ; The label:
    JR   Z,AC_PASS                 ; RG_EXIT for `else fail`.
    PUSH AF                        ; A handler's: keep it.
    LD   B,CT_KTRAP                ; Open a handler's frame;
    CALL CT_PUSH                   ; HL addresses it.
    POP  AF                        ; The failure's label
    INC  HL                        ; is
    LD   (HL),A                    ; CT_FDEST.
    INC  HL                        ; Step
    INC  HL                        ; to
    INC  HL                        ; CT_FLCNT:
    DEC  (HL)                      ; the closing frees that label too.
    LD   DE,CT_FMODE-CT_FLCNT      ; Step
    ADD  HL,DE                     ; to CT_FMODE:
    LD   A,(RO_KEPT)               ; the temporaries' bytes
    LD   (HL),A                    ; beneath the call.
    LD   B,CT_FEXIT                ; The skip label,
    CALL CT_NEW                    ; allocated:
    LD   C,$C3                     ; success jumps
    CALL EM_JUMP                   ; over the handler.
    JR   AC_DROP                   ; The failure is handled.

;@ROUTINE OUT A,BC,D,CARRY,ZERO CLOBBERS SIGN,PARITY,HALFCARRY,E,HL
; Look up the current NAME (DG_UNDEF if absent): its class and type go to
; AC_DINFO and are returned in A and D, its payload to AC_DVAL and BC.

AC_FIND:
    CALL SY_GET                    ; A is the class and type, BC the payload.
    LD   (AC_DINFO),A              ; Record them
    LD   (AC_DVAL),BC              ; for the action's later steps.
    LD   D,A                       ; Return the class and type in D too.
    RET                            ; Back to the caller.

;@ROUTINE OUT A,CARRY,ZERO CLOBBERS SIGN,PARITY,HALFCARRY,BC,DE,HL
; BeginHandle, with the handler's variable as the current NAME: it must be
; a u8 variable (DG_CLASH) and not an active for counter (DG_INUSE). The
; failure lands here: the temporaries it left are dropped, POP DE for each
; two bytes, and its code, in A, is stored in the variable. The handler's
; body is reachable.

AC_ONERR:
    CALL AC_FIND                   ; The variable's class and type, and payload.
    AND  SY_TYPE+SY_AGGR           ; A type name or an aggregate,
    JR   NZ,.DEST                  ; or
    LD   A,D                       ; a
    AND  SY_CMASK                  ; constant
    JR   Z,.DEST                   ; cannot receive the code.
    CP   SY_LOCAL                  ; A local
    JR   NZ,.TYPE                  ; that counts
    CALL CT_COUNT                  ; a for loop,
    JR   C,.DEST                   ; neither.
.TYPE:                         ; A variable.
    CALL EX_DTYPE                  ; Its type.
    CP   SY_U8                     ; Error codes are u8.
    JR   Z,.U8                     ; Anything else is no destination.
.DEST:                         ; Not a writable u8 variable.
    CALL DG_RAISE                  ; Raise the diagnostic below:
    DB   DG_DEST                   ; handle-destination.
.U8:                           ; The variable takes the code.
    LD   B,CT_FDEST                ; The failure
    CALL CT_DEF                    ; lands here.
    CALL CT_MODE                   ; The temporaries it left:
    LD   B,A                       ; their bytes.
    SRL  B                         ; One POP for two.
    JR   Z,.STORE                  ; None.
.DROP:                         ; B pops remain.
    CALL EM_OP                     ; POP DE
    DB   $D1                       ; drops one, keeping A.
    DJNZ .DROP                     ; Until all are dropped.
.STORE:                        ; The code is in A.
    CALL AC_STORE                  ; Store the code in the variable.
    JP   AC_LIVE                   ; The handler's body is reachable.

;@ROUTINE OUT A,CARRY,ZERO CLOBBERS SIGN,PARITY,HALFCARRY
; Raise DG_LEAK if a failable call's failure is still pending.

AC_SAFE:
    LD   A,(RO_PEND)               ; Is a failure pending?
    OR   A                         ; Zero means none.
    RET  Z                         ; Nothing to handle.
    JP   AC_ELINE                  ; The statement should have ended.
