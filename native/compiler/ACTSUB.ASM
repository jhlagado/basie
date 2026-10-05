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
;  gathered in RO_CPIDX, RO_CPCNT, RO_CTYPE and RO_CFLAG, and AC_PUB
;  copies it into the routine's record, which makes the routine visible to
;  calls, its own body included. A routine's label is RO_LBASE plus its
;  index; main's is RO_MDEST. RO_FOPEN in a routine's flags marks a
;  forward whose body is still to come, and main's flags live in
;  RO_MFLAG. A body is written as a blob while it is parsed: AC_BEGIN and
;  AC_ENTRY open it (RG_OPEN) and AC_END closes it (RG_CLOSE). Forward
;  routines and parameters are refused (DG_NYI) until calls are compiled.
;
;  Failure. A call to a failable routine or service leaves RO_PEND set and
;  RO_MODEP addressing three handling bytes that end its OP_CALL: the mode
;  (RO_MPASS or RO_MTRAP), a handler label and RO_KEPT, the carriers kept
;  beneath the call. The statement must then end with `else fail`, which
;  propagates the failure out of a failable routine, or be followed by a
;  handler; any other continuation raises DG_LEAK.
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
; RequireMain, at the end of the program: main must have a body (DG_TOP,
; or DG_UNMET for a forward main without one), and no forward routine may
; be left without its body (DG_UNMET).

AC_MAIN:
    LD   A,(RO_CUR)                ; Was main's body the last thing parsed?
    INC  A                         ; $FF becomes zero.
    JR   Z,.FORWARDS               ; Yes: check the forwards.
    LD   A,(RO_MFLAG)              ; No main body. Was main declared forward?
    AND  RO_FOPEN                  ; Test its open flag.
    JR   NZ,.PARTIAL               ; Yes: raise DG_UNMET.
    JR   .NOMAIN                   ; No: there is no main at all.
.FORWARDS:                     ; Check every routine for a missing body.
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
; Start a signature with no parameters and no result. Returns A zero.

AC_CLEAR:
    XOR  A                         ; Zero...
    LD   (RO_CPCNT),A              ; ...parameters...
    LD   (RO_CTYPE),A              ; ...and no result type.
    RET                            ; A is zero.

;@ROUTINE OUT A,CARRY,ZERO CLOBBERS SIGN,PARITY,HALFCARRY,BC,DE,HL,IX
; BeginSub: open a routine signature. For main, check the entry bank and
; that main was not declared forward (DG_DUP), and make RO_CUR $FF. For
; another routine, check the table has room (DG_PROCS) and the name is new
; (DG_DUP), and start its record: name and first parameter index.

AC_SIG:
    CALL AC_RESUB                  ; The routine's name is current again.
    CALL AC_EARLY                  ; Nothing may follow main.
    CALL EX_MAIN                   ; Is the name `main`?
    JR   C,.MAIN                   ; Yes: open main.
    LD   A,(RO_RCNT)               ; The routines so far.
    CP   RO_RCAP                   ; Room for another?
    JR   NC,.FULL                  ; No: raise DG_PROCS.
    CALL RO_FRESH                  ; Reject a name already in use.
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
    LD   A,(RO_MFLAG)              ; Was main declared forward?
    AND  RO_FOPEN                  ; Then its body uses the short form.
    JP   NZ,EX_EDUP                ; A second signature is a duplicate.
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
; BeginForward: build the signature as AC_SIG does and mark it open: its
; body comes later, in the short form `sub NAME`. Refused for now (DG_NYI):
; a forward takes its ordinal at the declaration and its body's prologue
; checks the stack, which come with calls (native compiler plan 65.4 e).

AC_PROTO:
    CALL TR_OPER                   ; Refuse the forward declaration.
    CALL AC_SIG                    ; Build the signature.
    LD   A,(RO_CFLAG)              ; Its flags.
    OR   RO_FOPEN                  ; Waiting for a body.
    LD   (RO_CFLAG),A              ; Keep them.
    OR   A                         ; Clear carry.
    RET                            ; Back to the engine.

;@ROUTINE OUT A,CARRY,ZERO CLOBBERS SIGN,PARITY,HALFCARRY,DE,HL
; CommitForward: publish a forward routine's signature, or keep a forward
; main's flags in RO_MFLAG and release RO_CUR so that declarations may
; continue. No code is emitted.

AC_SEAL:
    LD   A,(RO_CUR)                ; The routine declared.
    INC  A                         ; Is it main?
    JR   Z,.MAIN                   ; Yes.
    DEC  A                         ; Recover its index.
    CALL AC_PUB                    ; Publish the signature.
    XOR  A                         ; Clear carry.
    RET                            ; Back to the engine.
.MAIN:                         ; A forward main.
    LD   A,(RO_CFLAG)              ; Its flags, open...
    LD   (RO_MFLAG),A              ; ...are main's.
    XOR  A                         ; Main is no longer being declared.
    LD   (RO_CUR),A                ; Later declarations are allowed.
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
; open forward, recovering the signature and parameter names it stored.
; An undeclared name raises DG_UNDEF, one whose body exists DG_DUP.

AC_IMPL:
    CALL AC_RESUB                  ; The routine's name is current again.
    CALL AC_EARLY                  ; Nothing may follow main.
    CALL EX_MAIN                   ; Is the name `main`?
    JR   C,.MAIN                   ; Yes: open a forward main.
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
    INC  HL                        ; Step to RO_RDEST.
    LD   A,(HL)                    ; Its label.
    LD   (RO_DEST),A               ; Recover it.
    INC  HL                        ; Step to RO_RFLAG.
    LD   A,(HL)                    ; Its flags.
    BIT  2,A                       ; RO_FOPEN: still waiting for a body?
    JP   Z,EX_EDUP                 ; No: a second body is a duplicate.
    AND  $FB                       ; Clear RO_FOPEN: the body is here.
    LD   (HL),A                    ; In the record...
    LD   (RO_CFLAG),A              ; ...and the signature.
    JR   AC_BEGIN                  ; Open the body.
.MAIN:                         ; The body of a forward main.
    LD   A,(RO_MFLAG)              ; Main's flags.
    BIT  2,A                       ; Was main declared forward?
    JR   Z,.MISSING                ; No: the short form needs a forward.
    AND  $FB                       ; Clear RO_FOPEN.
    LD   (RO_CFLAG),A              ; Main's flags...
    LD   (RO_MFLAG),A              ; ...in both places.
    CALL AC_CLEAR                  ; No parameters or result; A is zero.
    DEC  A                         ; $FF...
    LD   (RO_CUR),A                ; ...marks main as current.
    JP   AC_ENTRY                  ; Open main's body.
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
    DEC  A                         ; Recover its index.
    CALL AC_PUB                    ; Publish the signature.
    JR   AC_BEGIN                  ; Open the body.

;@ROUTINE IN A OUT A CLOBBERS CARRY,ZERO,SIGN,PARITY,HALFCARRY,DE,HL
; Copy the signature into routine A's record, with label RO_LBASE plus
; RO_CUR (also left in RO_DEST), and count the routine as declared.

AC_PUB:
    CALL RO_SUBAT                  ; HL addresses the record.
    LD   DE,RO_RPCNT               ; Skip the name and first parameter...
    ADD  HL,DE                     ; ...to RO_RPCNT.
    LD   A,(RO_CPCNT)              ; The parameter count.
    LD   (HL),A                    ; Store it.
    INC  HL                        ; Step to RO_RTYPE.
    LD   A,(RO_CTYPE)              ; The result type.
    LD   (HL),A                    ; Store it.
    INC  HL                        ; Step to RO_RDEST.
    LD   A,(RO_CUR)                ; The routine's index...
    ADD  A,RO_LBASE                ; ...gives its label.
    LD   (HL),A                    ; Store it...
    LD   (RO_DEST),A               ; ...and keep it for the body.
    INC  HL                        ; Step to RO_RFLAG.
    LD   A,(RO_CFLAG)              ; The flags.
    LD   (HL),A                    ; Store them.
    LD   HL,RO_RCNT                ; Count the routine...
    INC  (HL)                      ; ...so that RO_FIND sees it.
    RET                            ; The routine is published.

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
; Open a routine's body: begin its blob, named from its record (RG_OPEN),
; make its start reachable and bind each parameter to its frame slot
; (RO_BIND), which refuses it for now.

AC_BEGIN:
    CALL AC_SCOPE                  ; Enter the body's scope.
    LD   A,(RO_CUR)                ; The routine's record
    CALL RO_SUBAT                  ; is at HL; its name comes first:
    LD   E,(HL)                    ; the spelling's
    INC  HL                        ; address
    LD   D,(HL)                    ; in DE,
    INC  HL                        ; then
    LD   B,(HL)                    ; its length.
    EX   DE,HL                     ; HL is the name.
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
    CALL RO_BIND                   ; Install the parameter and emit its copy.
    POP  BC                        ; Recover the count.
    POP  DE                        ; Recover the indices.
    INC  D                         ; Next parameter entry.
    INC  E                         ; Next argument.
    DEC  B                         ; One fewer.
    JR   .BINDLOOP                 ; Bind it.

;@ROUTINE OUT A,CARRY,ZERO CLOBBERS SIGN,PARITY,HALFCARRY,BC,DE,HL
; Open main's body: keep its flags, enter the scope, begin its blob and
; keep its ordinal for the entry record, and make the body reachable.
; Main has no result.

AC_ENTRY:
    LD   A,(RO_CFLAG)              ; Main's flags...
    LD   (RO_MFLAG),A              ; ...are kept.
    CALL AC_SCOPE                  ; Enter the scope; A is zero.
    LD   (RO_CTYPE),A              ; Main has no result type.
    LD   HL,KW_MAIN                ; Its name,
    LD   B,4                       ; four characters.
    CALL RG_OPEN                   ; Begin main's blob.
    LD   HL,(BL_ORD)               ; Its ordinal
    LD   (RG_MAIN),HL              ; is the program's entry; fall into AC_LIVE.

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
; need for the limits record and discard the routine's parameters and
; locals.

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
    JR   NZ,.SCOPE                 ; No: its need is not the program's.
    LD   (RG_NEED),HL              ; Main's need sets the stack reserve.
.SCOPE:                        ; Leave the routine's scope.
    LD   A,(RO_GLOBS)              ; Keep only the global symbols.
    LD   (SY_CNT),A                ; Parameters and locals go out of scope.
    RET                            ; Back to the engine.

; ----------------------------------------------------------------- failure

;@ROUTINE OUT A,CARRY,ZERO CLOBBERS SIGN,PARITY,HALFCARRY,HL
; BeginFail: only a failable routine may fail (DG_LEAK). Keep the
; statement's source offset and expect a u8 error code.

AC_FAIL:
    LD   A,(RO_CFLAG)              ; The routine's flags.
    AND  RO_FFAIL                  ; Failable?
    JR   Z,AC_ELEAK                ; No: raise DG_LEAK.
    LD   HL,(TK_POS)               ; The fail statement's offset...
    LD   (RO_FPOS),HL              ; ...is reported by the failure.
    LD   A,SY_U8                   ; The code is a u8.
    JP   AC_WANT                   ; Expect it.

;@ROUTINE OUT A,CARRY,ZERO CLOBBERS SIGN,PARITY,HALFCARRY,B,DE,HL
; CommitFail: check the u8 code, emit OP_FAIL offset and mark the code
; that follows unreachable.

AC_THROW:
    LD   E,SY_U8                   ; The code must be a u8...
    CALL AC_VALOK                  ; ...with no failure pending.
    LD   A,OP_FAIL                 ; Fail the routine.
    CALL TR_OPER                   ; Append it.
    LD   HL,(RO_FPOS)              ; Its operand is the source offset.
    LD   A,L                       ; Low byte...
    CALL TR_PUTHL                  ; ...appended.
    LD   A,H                       ; High byte...
    CALL TR_PUT                    ; ...appended; fall into AC_DEAD.

;@ROUTINE OUT A,CARRY,ZERO CLOBBERS SIGN,PARITY,HALFCARRY
; Control cannot reach this point. Returns A zero.

AC_DEAD:
    XOR  A                         ; Unreachable.
    LD   (CT_FALLS),A              ; Record it.
    RET                            ; Back to the engine.

;@ROUTINE IN E OUT A,CARRY,ZERO CLOBBERS SIGN,PARITY,HALFCARRY,D,HL
; Check that the expression just parsed fits type E (EX_FITS) and that no
; failure is left pending inside it (AC_SAFE).

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
; follow (DG_LEAK otherwise). AC_PASS is the same for a caller that has
; already seen `else`.

AC_RELAY:
    CALL PR_PEEK                   ; What follows the initializer?
    CP   TK_ELSE                   ; `else fail`?
    JR   NZ,AC_ELEAK               ; No: the failure is unhandled.

;@ROUTINE OUT A,CARRY,ZERO CLOBBERS SIGN,PARITY,HALFCARRY,BC,DE,HL
; `else fail` follows a pending failure: the routine must be failable
; (DG_LEAK), and nothing more may handle the failure. Set the call's mode
; to RO_MPASS, record the kept carriers and clear the pending state.

AC_PASS:
    LD   A,(RO_CFLAG)              ; The routine's flags.
    AND  RO_FFAIL                  ; Can it pass a failure on?
    JR   Z,AC_ELEAK                ; No: raise DG_LEAK.
    CALL PR_TAKE                   ; Consume `else`.
    LD   E,TK_FAIL                 ; It must be `else fail`.
    CALL PR_NEED                   ; Consume `fail`.
    CALL PR_PEEK                   ; What follows?
    CP   TK_HANDL                  ; A handler as well?
    JR   Z,AC_ELEAK                ; Would have nothing to handle.
    CP   TK_ELSE                   ; Another else?
    JR   Z,AC_ELEAK                ; Likewise.
    LD   A,RO_MPASS                ; Propagate the failure.
    LD   HL,(RO_MODEP)             ; The call's handling bytes.
    LD   (HL),A                    ; Its mode.
    INC  HL                        ; Skip the handler label,...
    INC  HL                        ; ...which propagation does not use.
    LD   A,(RO_KEPT)               ; The carriers kept beneath the call.
    LD   (HL),A                    ; Record them; fall into AC_DROP.

;@ROUTINE OUT A,CARRY,ZERO CLOBBERS SIGN,PARITY,HALFCARRY
; The pending failure is handled. Returns A zero.

AC_DROP:
    XOR  A                         ; Zero...
    LD   (RO_PEND),A               ; ...nothing pending...
    LD   (RO_KEPT),A               ; ...and nothing kept.
    RET                            ; Back to the engine.

;@ROUTINE OUT A,CARRY,ZERO CLOBBERS SIGN,PARITY,HALFCARRY,BC,DE,HL
; After a name statement, attach what follows to a pending failure:
; `else fail` (AC_PASS) or a handler, for which a CT_KTRAP frame is opened
; with its body label and exit, and the call's mode is set to RO_MTRAP
; with that label. A handler or else with nothing pending, or a pending
; failure with neither, raises DG_LEAK.

AC_ROUTE:
    LD   A,(RO_PEND)               ; Is a failure pending?
    OR   A                         ; Zero means none.
    JR   NZ,.PENDING               ; Attach its handling.
    LD   (RO_KEPT),A               ; Nothing kept.
    CALL PR_PEEK                   ; What follows the statement?
    CP   TK_ELSE                   ; `else fail`...
    JR   Z,AC_ELEAK                ; ...with nothing to pass on.
    CP   TK_HANDL                  ; A handler...
    JR   Z,AC_ELEAK                ; ...with nothing to handle.
    OR   A                         ; Clear carry.
    RET                            ; Back to the engine.
.PENDING:                      ; A failable call needs handling.
    CALL PR_PEEK                   ; What follows the statement?
    CP   TK_ELSE                   ; `else fail`?
    JR   Z,AC_PASS                 ; Propagate the failure.
    CP   TK_HANDL                  ; A handler?
    JR   NZ,AC_ELEAK               ; No: the failure is unhandled.
    LD   B,CT_KTRAP                ; Open a handler frame...
    CALL CT_OPEN                   ; ...with its body label in CT_FDEST...
    CALL CT_EXIT                   ; ...and its exit label.
    LD   HL,(RO_MODEP)             ; The call's handling bytes.
    LD   (HL),RO_MTRAP             ; Mode: jump to the handler.
    LD   B,CT_FDEST                ; The handler's body label.
    CALL CT_FIELD                  ; HL addresses it.
    LD   C,(HL)                    ; Fetch it.
    LD   HL,(RO_MODEP)             ; The handling bytes again.
    INC  HL                        ; Step to the label byte.
    LD   (HL),C                    ; The failure jumps there.
    INC  HL                        ; Step to the kept count.
    LD   A,(RO_KEPT)               ; The carriers kept beneath the call.
    LD   (HL),A                    ; Record them.
    JR   AC_DROP                   ; The failure is handled.

;@ROUTINE OUT A,BC,D,CARRY,ZERO CLOBBERS SIGN,PARITY,HALFCARRY,E,HL
; Look up the current NAME (DG_UNDEF if absent): its class and type go to
; AC_DINFO and are returned in A and D, its payload to AC_DVAL and BC.

AC_FIND:
    CALL SY_GET                    ; A is the class and type, BC the payload.
    LD   (AC_DINFO),A              ; Record them...
    LD   (AC_DVAL),BC              ; ...for the action's later steps.
    LD   D,A                       ; Return the class and type in D too.
    RET                            ; Back to the caller.

;@ROUTINE OUT A,CARRY,ZERO CLOBBERS SIGN,PARITY,HALFCARRY,BC,DE,HL
; BeginHandle, with the handler's variable as the current NAME: it must be
; a u8 variable (DG_CLASH) and not an active for counter (DG_INUSE). Emit
; OP_HSKIP exit, by which success skips the handler, then OP_HOPEN label,
; info, place, where a failure stores its code: a frame offset byte for a
; local or parameter, an address word for a program variable.

AC_ONERR:
    CALL AC_FIND                   ; The variable's class and type, and payload.
    CALL EX_CLASS                  ; A scalar? A is its class, Z for a constant.
    JP   Z,EX_ETYPE                ; A constant cannot receive the code.
    CP   SY_LOCAL                  ; A local?
    JR   NZ,.CHECKED               ; Only a local can be a counter.
    CALL CT_GUARD                  ; Reject an active for counter (C, its offset).
.CHECKED:                      ; The variable may be written.
    CALL EX_DTYPE                  ; Its type.
    CP   SY_U8                     ; Error codes are u8.
    JP   NZ,EX_ETYPE               ; Anything else raises DG_CLASH.
    LD   B,CT_FEXIT                ; The handler frame's exit label.
    CALL CT_FIELD                  ; HL addresses it.
    LD   C,(HL)                    ; Fetch it.
    LD   A,OP_HSKIP                ; On success, skip the handler.
    CALL AC_EMITC                  ; Append it with the exit label.
    LD   B,CT_FDEST                ; The handler's body label.
    CALL CT_FIELD                  ; HL addresses it.
    LD   C,(HL)                    ; Fetch it.
    LD   A,OP_HOPEN                ; The handler starts here.
    CALL AC_EMITC                  ; Append it with the label.
    LD   A,(AC_DINFO)              ; The variable's class and type.
    CALL TR_PUT                    ; Append them; A keeps them.
    AND  SY_CMASK                  ; Its class.
    CP   SY_GLOB                   ; A program variable?
    LD   HL,(AC_DVAL)              ; Its payload.
    JR   Z,.GLOBAL                 ; Has an address word.
    LD   A,L                       ; A local or parameter has a frame offset...
    CALL TR_PUT                    ; ...appended as one byte.
    JR   .DONE                     ; The handler is open.
.GLOBAL:                       ; HL is the variable's address.
    CALL RO_EMITW                  ; Append it as a word.
.DONE:                         ; The handler's body is reachable.
    JP   AC_LIVE                   ; Record it and return.

;@ROUTINE IN A,C OUT A,CARRY,ZERO CLOBBERS SIGN,PARITY,HALFCARRY,B,DE,HL
; Append operation A with the operand byte C. TR_OPER leaves C alone.

AC_EMITC:
    CALL TR_OPER                   ; Append and count the operation.
    LD   A,C                       ; The operand.
    JP   TR_PUT                    ; Append it and return.

;@ROUTINE OUT A,CARRY,ZERO CLOBBERS SIGN,PARITY,HALFCARRY,BC,DE,HL
; EndHandle: emit OP_HDONE exit, where the handler and the skip meet, and
; close the frame. Control always reaches the end of a handle statement.

AC_NOERR:
    LD   B,CT_FEXIT                ; The handler frame's exit label.
    CALL CT_FIELD                  ; HL addresses it.
    LD   C,(HL)                    ; Fetch it.
    LD   A,OP_HDONE                ; The handler ends here.
    CALL AC_EMITC                  ; Append it with the label.
    LD   A,1                       ; The statement falls through.
    JP   AC_MERGE                  ; Close the frame.

;@ROUTINE OUT A,CARRY,ZERO CLOBBERS SIGN,PARITY,HALFCARRY
; Raise DG_LEAK if a failable call's failure is still pending.

AC_SAFE:
    LD   A,(RO_PEND)               ; Is a failure pending?
    OR   A                         ; Zero means none.
    RET  Z                         ; Nothing to handle.
    JP   AC_ELEAK                  ; Raise DG_LEAK.
