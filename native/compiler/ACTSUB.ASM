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
;    AC_EARLY, AC_MAIN  nothing may follow main; main must exist and every
;              forward must be completed
;    AC_SUB, AC_SIG, AC_PROTO, AC_SEAL  routine and forward signatures
;    AC_PARAM, AC_JOIN, AC_GIVES, AC_GIVEN, AC_FAILS  signature parts
;    AC_BODY, AC_IMPL, AC_END  open and close a routine or main body
;    AC_FAIL, AC_THROW  the fail statement
;    AC_ROUTE, AC_RELAY  attach `else fail` or a handler to a failable call
;    AC_ONERR, AC_NOERR  open and close a handler
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

;@ROUTINE OUT A CLOBBERS ZERO,SIGN,PARITY,HALFCARRY
; RequireBeforeMain: main must be the last declaration. Once its body has
; begun (RO_CUR is $FF), any further declaration raises DG_EOF.

AC_EARLY:
    LD   A,(RO_CUR)                ; The routine being declared.
    INC  A                         ; $FF, main, becomes zero.
    RET  NZ                        ; Not main: the declaration may follow.
    CALL DG_RAISE                  ; Abandon the build.
    DB   DG_EOF                    ; Expected the end of the program.

;@ROUTINE OUT A,CARRY,ZERO CLOBBERS SIGN,PARITY,HALFCARRY,BC,DE,HL
; RequireMain, at the end of the program: main must have a body (DG_TOP),
; and no forward routine may be left without its body (DG_UNMET).

AC_MAIN:
    LD   A,(RO_CUR)                ; Was main's body the last thing parsed?
    INC  A                         ; $FF becomes zero.
    JR   NZ,.NOMAIN                ; No: there is no main.
    LD   A,(RO_RCNT)               ; The routines declared.
    LD   B,A                       ; Count them in B.
    XOR  A                         ; Start at index zero...
    LD   C,A                       ; ...in C.
.LOOP:                         ; Check routine C.
    LD   A,B                       ; Any left?
    OR   A                         ; Zero means all are complete.
    RET  Z                         ; Every forward has its body.
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
.NOMAIN:                       ; The program has no main.
    CALL DG_RAISE                  ; Abandon the build.
    DB   DG_TOP                    ; Expected a declaration.
.PARTIAL:                      ; A forward has no body.
    CALL DG_RAISE                  ; Abandon the build.
    DB   DG_UNMET                  ; Unmet forward declaration.

;@ROUTINE OUT A,CARRY,ZERO CLOBBERS SIGN,PARITY,HALFCARRY,BC,DE,HL
; RetainSubName: keep the routine's name and position unchecked. The grammar
; reads `main` as an ordinary NAME; the actions that follow tell it apart.

AC_SUB:
    JP   EX_KEEP                   ; Keep the name; the checks come later.

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
    CALL AC_EARLY                  ; Nothing may follow main.
    CALL EX_MAIN                   ; Is the name `main`?
    JR   C,.MAIN                   ; Yes: open main.
    LD   A,(RO_RCNT)               ; The routines so far.
    CP   RO_RCAP                   ; Room for another?
    JR   NC,.FULL                  ; No: raise DG_PROCS.
    CALL RO_FRESH                  ; Reject a name already in use.
    LD   HL,KW_ID                  ; `id (` is always the conversion
    LD   B,2                       ; (spec 3.5), so no routine
    CALL TK_MATCH                  ; may be named id:
    JP   C,EX_ETYPE                ; raise DG_CLASH.
    LD   A,(RO_RCNT)               ; The new routine's index.
    LD   (RO_CUR),A                ; It is the routine being declared.
    CALL RO_SUBAT                  ; HL addresses its record.
    CALL TK_KEEP                   ; Record its name; HL addresses the length.
    INC  HL                        ; Step to RO_RPIDX.
    LD   A,(RO_PCNT)               ; The next free parameter entry...
    LD   (HL),A                    ; ...is its first parameter...
    LD   (RO_CPIDX),A              ; ...in the record and the signature.
    CALL AC_CLEAR                  ; No parameters or result yet; A is zero.
    LD   (RO_CFLAG),A              ; The routine's flags: none yet.
    RET                            ; Back to the engine.
.MAIN:                         ; Open main's signature.
    CALL RO_FRESH                  ; Reject a symbol or routine called main.
    LD   A,$FF                     ; Main is being declared.
    LD   (RO_CUR),A                ; Mark it.
    CALL AC_CLEAR                  ; No parameters or result.
    LD   A,RO_FMAIN                ; Main's flag...
    LD   (RO_CFLAG),A              ; ...begins its flags.
    RET                            ; Back to the engine.
.FULL:                         ; The routine table is full.
    CALL DG_RAISE                  ; Abandon the build.
    DB   DG_PROCS                  ; Too many routines.

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

;@ROUTINE OUT A,CARRY,ZERO CLOBBERS SIGN,PARITY,HALFCARRY,BC,DE,HL
; RetainParameter: main takes no parameters (DG_RPAR). Otherwise the name
; must not collide (RO_VET) and is kept in AC_DNAME until its type is known.

AC_PARAM:
    LD   A,(RO_CUR)                ; The routine declared.
    INC  A                         ; Is it main?
    JR   Z,.MAIN                   ; Yes: no parameters.
    CALL RO_VET                    ; Reject a colliding parameter name.
    LD   HL,AC_DNAME               ; Keep the name...
    CALL TK_KEEP                   ; ...for AC_JOIN.
    OR   A                         ; Clear carry.
    RET                            ; Back to the engine.
.MAIN:                         ; Main has a parameter.
    CALL DG_RAISE                  ; Abandon the build.
    DB   DG_RPAR                   ; Expected ")".

;@ROUTINE OUT A,CARRY,ZERO CLOBBERS SIGN,PARITY,HALFCARRY,BC,DE,HL
; CommitParameter: append the retained name with the current type.

AC_JOIN:
    CALL EX_RENEW                  ; The parameter's name is current again.
    LD   A,(AG_CTYPE)              ; Its type.
    JP   RO_ENROL                  ; Append the parameter and return.

;@ROUTINE OUT A CLOBBERS ZERO,SIGN,PARITY,HALFCARRY
; AllowSubResult: main has no result (DG_EOL).

AC_GIVES:
    LD   A,(RO_CUR)                ; The routine declared.
    INC  A                         ; Is it main?
    JR   Z,AC_ELINE                ; Yes: raise DG_EOL.
    RET                            ; Another routine may return a value.

;@ROUTINE OUT A,CARRY,ZERO CLOBBERS SIGN,PARITY,HALFCARRY
; SaveSubResult: the current type is the result type; not a view
; (DG_BOUND).

AC_GIVEN:
    LD   A,(AG_CTYPE)              ; The result type.
    CP   AG_VIEW                   ; An open string?
    JP   Z,AG_EFORM                ; Cannot be returned: raise DG_BOUND.
    LD   (RO_CTYPE),A              ; The routine's result type.
    OR   A                         ; Clear carry.
    RET                            ; Back to the engine.

;@ROUTINE OUT A,CARRY,ZERO CLOBBERS SIGN,PARITY,HALFCARRY
; MarkSubFails: the routine can fail.

AC_FAILS:
    LD   A,(RO_CFLAG)              ; The routine's flags...
    OR   RO_FFAIL                  ; ...gain the failable flag.
    LD   (RO_CFLAG),A              ; Keep them.
    OR   A                         ; Clear carry.
    RET                            ; Back to the engine.

;@ROUTINE NORETURN
; Raise DG_EOL: the signature should have ended.

AC_ELINE:
    CALL DG_RAISE                  ; Abandon the build.
    DB   DG_EOL                    ; Expected the end of the line.

;@ROUTINE OUT A,CARRY,ZERO CLOBBERS SIGN,PARITY,HALFCARRY,BC,DE,HL,IX
; BeginForwardBody: `sub NAME` without a signature opens the body of an
; open forward, recovering the signature it stored. An undeclared name
; raises DG_UNDEF, and one whose body exists DG_DUP. Main is never found:
; nothing may follow its body (AC_EARLY), and it is never forward.

AC_IMPL:
    CALL AC_RESUB                  ; The routine's name is current again.
    CALL AC_EARLY                  ; Nothing may follow main.
    CALL RO_FIND                   ; Z, and A its index, if declared.
    JR   NZ,.MISSING               ; Not declared: raise DG_UNDEF.
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
    LD   A,(HL)                    ; Its flags.
    BIT  2,A                       ; RO_FOPEN: still waiting for a body?
    JP   Z,EX_EDUP                 ; No: a second body is a duplicate.
    AND  $FF-RO_FOPEN              ; The body is here.
    LD   (HL),A                    ; In the record...
    LD   (RO_CFLAG),A              ; ...and the signature.
    LD   DE,RO_RARGS-RO_RFLAG      ; Then the argument bytes:
    ADD  HL,DE                     ; HL addresses them.
    LD   A,(HL)                    ; Recover
    LD   (RO_CARGS),A              ; them.
    JR   AC_BEGIN                  ; Open the body.
.MISSING:                      ; No forward to complete.
    CALL DG_RAISE                  ; Abandon the build.
    DB   DG_UNDEF                  ; Undefined name.

;@ROUTINE OUT A,CARRY,ZERO CLOBBERS SIGN,PARITY,HALFCARRY,BC,DE,HL
; BeginSubBody: after a full signature, open main's body, or publish the
; routine (making it callable from its own body) and open its body.

AC_BODY:
    LD   A,(RO_CUR)                ; The routine declared.
    INC  A                         ; Is it main?
    JP   Z,AC_ENTRY                ; Yes: open main's body.
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
    LD   A,(SY_CNT)                ; Symbols so far are all global.
    LD   (RO_GLOBS),A              ; AC_END discards the rest.
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
    OR   A                         ; Zero means all are bound.
    RET  Z                         ; The body is open.
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
    CALL RG_OPEN                   ; Begin main's blob; fall into AC_LIVE.

;@ROUTINE OUT A,CARRY,ZERO CLOBBERS SIGN,PARITY,HALFCARRY
; Control can reach this point.

AC_LIVE:
    LD   A,1                       ; Reachable.
    LD   (CT_FALLS),A              ; Record it.
    OR   A                         ; Clear carry.
    RET                            ; Back to the engine.

;@ROUTINE OUT A,CARRY,ZERO CLOBBERS SIGN,PARITY,HALFCARRY,BC,DE,HL
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
    JP   NZ,EX_EFLOW               ; Raise DG_FLOW: a path returns no value.
.CLOSE:                        ; Close the routine.
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
    LD   A,(RO_GLOBS)              ; Keep only the global symbols.
    LD   (SY_CNT),A                ; Parameters and locals go out of scope.
    RET                            ; Back to the engine.

; ----------------------------------------------------------------- failure

;@ROUTINE OUT A,CARRY,ZERO CLOBBERS SIGN,PARITY,HALFCARRY
; BeginFail: only a failable routine may fail (DG_LEAK). Expect a u8
; error code.

AC_FAIL:
    LD   A,(RO_CFLAG)              ; The routine's flags.
    AND  RO_FFAIL                  ; Failable?
    JR   Z,AC_ELEAK                ; No: raise DG_LEAK.
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
    CALL EM_SEQ                    ; PUSH AF, POP AF,
    DB   3,$F5,$F1,$37             ; SCF: the routine fails.
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
    LD   A,(EX_RMETA)              ; The result's metadata.
    LD   HL,(EX_RVAL)              ; Its value.
    CALL EX_FITS                   ; Check it against E.
    JP   AC_SAFE                   ; Reject a pending failure.

;@ROUTINE NORETURN
; Raise DG_LEAK: a failure is unhandled, or fail or `else fail` is used
; where nothing can fail.

AC_ELEAK:
    CALL DG_RAISE                  ; Abandon the build.
    DB   DG_LEAK                   ; Failure not handled.

;@ROUTINE OUT A,CARRY,ZERO CLOBBERS SIGN,PARITY,HALFCARRY,BC,DE,HL
; A failure is pending after a local initializer: only `else fail` may
; follow (DG_LEAK otherwise; a handler would leave the local without a
; value).

AC_RELAY:
    CALL PR_PEEK                   ; What follows the initializer?
    CP   TK_ELSE                   ; `else fail`?
    JR   NZ,AC_ELEAK               ; No: the failure is unhandled.

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
    JR   Z,AC_ELEAK                ; Would have nothing to handle.
    CP   TK_ELSE                   ; Another else?
    JR   Z,AC_ELEAK                ; Likewise; fall into AC_DROP.

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
    JR   Z,AC_ELEAK                ; with nothing to pass on,
    CP   TK_HANDL                  ; or a handler
    JR   Z,AC_ELEAK                ; with nothing to handle.
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
    CALL EX_CLASS                  ; A scalar? A is its class, Z for a constant.
    JP   Z,EX_ETYPE                ; A constant cannot receive the code.
    CP   SY_LOCAL                  ; A local?
    CALL Z,CT_GUARD                ; Reject an active for counter (BC).
    CALL EX_DTYPE                  ; Its type.
    CP   SY_U8                     ; Error codes are u8.
    JP   NZ,EX_ETYPE               ; Anything else raises DG_CLASH.
    LD   B,CT_FDEST                ; The failure
    CALL CT_DEF                    ; lands here.
    LD   B,CT_FMODE                ; The temporaries
    CALL CT_FIELD                  ; it left:
    LD   B,(HL)                    ; their bytes.
    SRL  B                         ; One POP for two.
    JR   Z,.STORE                  ; None.
.DROP:                         ; B pops remain.
    CALL EM_OP                     ; POP DE
    DB   $D1                       ; drops one, keeping A.
    DJNZ .DROP                     ; Until all are dropped.
.STORE:                        ; The code is in A.
    LD   A,(AC_DINFO)              ; The variable's class and type
    LD   D,A                       ; for EX_STORE,
    LD   BC,(AC_DVAL)              ; and where it is.
    CALL EX_STORE                  ; Store the code.
    JP   AC_LIVE                   ; The handler's body is reachable.

;@ROUTINE OUT A,CARRY,ZERO CLOBBERS SIGN,PARITY,HALFCARRY,BC,DE,HL
; EndHandle: success skips to here, and the frame closes. Control always
; reaches the end of a handle statement.

AC_NOERR:
    LD   B,CT_FEXIT                ; The skip label
    CALL CT_DEF                    ; is here.
    CALL CT_POP                    ; Close the frame.
    JP   AC_LIVE                   ; What follows is reachable.

;@ROUTINE OUT A,CARRY,ZERO CLOBBERS SIGN,PARITY,HALFCARRY
; Raise DG_LEAK if a failable call's failure is still pending.

AC_SAFE:
    LD   A,(RO_PEND)               ; Is a failure pending?
    OR   A                         ; Zero means none.
    RET  Z                         ; Nothing to handle.
    JP   AC_ELEAK                  ; Raise DG_LEAK.
