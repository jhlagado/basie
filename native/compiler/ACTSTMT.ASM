;==========================================================================
;  Grammar actions: locals, statements and structured flow
;==========================================================================
;
;  The actions for local declarations, name statements (calls and
;  assignments), return, exit and continue, if, while and the counted for
;  loop. The calling convention is that of ACTIONS.ASM; the control frames
;  and labels are CONTROL.ASM's.
;
;  Principal entries:
;    AC_LOCAL, AC_INIT, AC_ZERO, AC_ADOPT, AC_BIND  local declarations
;    AC_STMT   island NameStatement: a call or an assignment
;    AC_RET, AC_YIELD, AC_RETOP, AC_BARE  return statements
;    AC_GOTO   exit and continue
;    AC_IF, AC_THEN, AC_ELIF, AC_ELSE, AC_TOTAL, AC_PART, AC_ENDIF  if
;    AC_WHILE, AC_DO, AC_LOOP  while
;    AC_FOR, AC_FORTO, AC_STEP, AC_BYONE, AC_FORDO, AC_NEXT  for
;    AC_NEST, AC_MERGE, AC_OUTER  fallthrough across nested statements
;
;  Fallthrough. CT_FALLS says whether control can reach the current point.
;  Opening a frame saves the enclosing value in AC_FLOWS, indexed by depth
;  (AC_NEST). Closing a while or for restores it, since a loop can always
;  finish; closing an if or a handler combines it with whether the
;  statement itself can complete (AC_MERGE). A routine with a result uses
;  this to reject a path that ends without return (AC_END). exit and
;  continue do not clear CT_FALLS, so the check is conservative.

; ------------------------------------------------------------------ locals

;@ROUTINE OUT A,CARRY,ZERO CLOBBERS SIGN,PARITY,HALFCARRY,BC,DE,HL
; SaveLocalType: declare a scalar local of the current type at the next
; frame slot, provisionally so that its initializer cannot use it. Emit
; its OP_LOC8 or OP_LOC16 and expect an initializer of its type.

AC_LOCAL:
    LD   A,(AG_CTYPE)              ; The local's scalar type...
    OR   SY_LOCAL                  ; ...with class local...
    LD   (AC_DINFO),A              ; ...is its information byte.
    LD   A,(SY_LSLOT)              ; The next free frame slot...
    LD   C,A                       ; ...widened...
    LD   B,0                       ; ...to BC...
    LD   (AC_DVAL),BC              ; ...is its payload.
    PUSH BC                        ; Keep it.
    LD   A,(AC_DINFO)              ; The information byte.
    LD   D,A                       ; For EX_PREP.
    CALL EX_PREP                   ; Write the provisional symbol.
    POP  BC                        ; Recover the payload.
    CALL EX_DTYPE                  ; The local's type.
    CALL EX_LOCAL                  ; Emit its declaration at SY_LSLOT.

;@ROUTINE OUT A,CARRY,ZERO CLOBBERS SIGN,PARITY,HALFCARRY
; Expect an expression of the declaration's type (AC_DINFO).

AC_TOVAR:
    CALL EX_DTYPE                  ; The declaration's type.
    JP   AC_WANT                   ; Expect it.

;@ROUTINE OUT A,CARRY,ZERO CLOBBERS SIGN,PARITY,HALFCARRY
; BeginLocalInitializer: expect the local's type. Same code as AC_TOVAR.

AC_INIT:
    CALL EX_DTYPE                  ; The local's type.
    JP   AC_WANT                   ; Expect it.

;@ROUTINE OUT A,CARRY,ZERO CLOBBERS SIGN,PARITY,HALFCARRY,B,DE,HL
; DefaultLocalInitializer: without an initializer a local starts at zero.
; Emit a literal zero and present it as a known value of the local's type.

AC_ZERO:
    LD   A,1                       ; Emit even if a constant parse...
    LD   (EX_LIVE),A               ; ...left emission off.
    LD   A,OP_LIT16                ; A literal word...
    CALL EX_EMIT                   ; ...appended...
    LD   HL,0                      ; ...with value...
    CALL EX_EMITW                  ; ...zero.
    CALL EX_DTYPE                  ; The local's type...
    OR   SY_KNOWN                  ; ...known at compile time...
    LD   (EX_RMETA),A              ; ...is the result's metadata.
    LD   HL,0                      ; Its value...
    LD   (EX_RVAL),HL              ; ...is zero.
    OR   A                         ; Clear carry.
    RET                            ; Back to the engine.

;@ROUTINE OUT A,CARRY,ZERO CLOBBERS SIGN,PARITY,HALFCARRY,BC,DE,HL
; FinishLocalInitializer: the value must fit the local's type. A pending
; failure must be followed by `else fail`; without one, a following else
; raises DG_LEAK.

AC_ADOPT:
    CALL AC_FIT                    ; Check the value against the local's type.
    LD   A,(RO_PEND)               ; Is a failure pending?
    OR   A                         ; Zero means none.
    JP   NZ,AC_RELAY               ; Require `else fail`.
    CALL PR_PEEK                   ; What follows?
    CP   TK_ELSE                   ; An else...
    JP   Z,AC_ELEAK                ; ...with nothing to handle.
    OR   A                         ; Clear carry.
    RET                            ; Back to the engine.

;@ROUTINE OUT A,CARRY,ZERO CLOBBERS SIGN,PARITY,HALFCARRY,DE,HL
; Check the expression just parsed against the declaration's type.

AC_FIT:
    CALL EX_DTYPE                  ; The declaration's type...
    LD   E,A                       ; ...is the destination; fall into AC_FITTO.

;@ROUTINE IN E OUT A,CARRY,ZERO CLOBBERS SIGN,PARITY,HALFCARRY,D,HL
; Check the expression just parsed (EX_RMETA, EX_RVAL) against type E;
; a mismatch raises DG_CLASH or DG_RANGE.

AC_FITTO:
    LD   HL,(EX_RVAL)              ; The value.
    LD   A,(EX_RMETA)              ; Its metadata.
    JP   EX_FITS                   ; Check it and return.

;@ROUTINE OUT A,CARRY,ZERO CLOBBERS SIGN,PARITY,HALFCARRY,BC,DE,HL
; CommitLocal: emit the store of the initial value, commit the local's
; symbol and advance the frame slot past it.

AC_BIND:
    LD   A,(AC_DINFO)              ; The local's information byte.
    LD   D,A                       ; For EX_STORE.
    LD   A,(AC_DVAL)               ; Its frame offset.
    LD   C,A                       ; For EX_STORE.
    CALL EX_STORE                  ; Emit the store of the initializer.
    CALL SY_CMT                    ; The local is now in scope.
    CALL EX_DTYPE                  ; Its type...
    CALL EX_WIDTH                  ; ...is one or two bytes wide.
    LD   HL,SY_LSLOT               ; Advance...
    ADD  A,(HL)                    ; ...the next free slot...
    LD   (HL),A                    ; ...past it.
    OR   A                         ; Clear carry.
    RET                            ; Back to the engine.

; -------------------------------------------------------------- statements

;@ROUTINE OUT A,CARRY,ZERO CLOBBERS SIGN,PARITY,HALFCARRY,BC,DE,HL,IX,IY
; Island NameStatement: a statement that begins with a name. A service
; or routine is called with its result discarded; an aggregate path is
; assigned through RO_LET; otherwise the name is a scalar variable
; (DG_CLASH for a constant, DG_INUSE for an active counter) and `=`
; and an expression of its type follow. Handling of a pending failure is
; attached (AC_ROUTE) before the store is emitted.

AC_STMT:
    CALL PR_TAKE                   ; Consume the name.
    LD   HL,(TK_POS)               ; Its source offset...
    LD   (EX_CPOS),HL              ; ...into EX_CPOS, which nothing reads,...
    LD   (RO_DPOS),HL              ; ...and into RO_DPOS for a call.
    CALL RO_LIB                    ; A predefined name?
    JR   NC,.ORDINARY              ; No.
    CP   RO_ERRS                   ; An error constant...
    JP   NC,EX_ETYPE               ; ...is not a statement: raise DG_CLASH.
    LD   C,0                       ; Discard the service's result.
    CALL RO_SERVE                  ; Parse the call.
    JP   AC_ROUTE                  ; Attach its failure handling.
.ORDINARY:                     ; Not predefined.
    CALL RO_FIND                   ; A routine?
    JR   NZ,.ASSIGN                ; No: an assignment.
    LD   C,0                       ; Discard the routine's result.
    CALL RO_CALL                   ; Parse the call.
    JP   AC_ROUTE                  ; Attach its failure handling.
.ASSIGN:                       ; The name is a variable.
    CALL AC_FIND                   ; A is its class and type, BC its payload.
    AND  SY_AGGR                   ; An aggregate?
    JP   NZ,RO_LET                 ; Assign through its path.
    LD   A,D                       ; The class and type.
    CALL EX_CLASS                  ; A scalar? A is its class.
    CP   SY_LOCAL                  ; A local?
    JR   NZ,.CHECKED               ; Only a local can be a counter.
    CALL CT_GUARD                  ; Reject an active for counter (C, its offset).
.CHECKED:                      ; D is the class and type.
    LD   A,D                       ; The class...
    AND  SY_CMASK                  ; ...is zero for a constant...
    JP   Z,EX_ETYPE                ; ...which cannot be assigned.
    CALL PR_EQUAL                  ; Require "=".
    CALL EX_DTYPE                  ; The variable's type...
    CALL EX_RUN                    ; ...is expected of the value; A is its metadata.
    LD   D,A                       ; Keep the metadata.
    CALL EX_DTYPE                  ; The variable's type...
    LD   E,A                       ; ...is the destination.
    LD   A,D                       ; The metadata, with HL the value.
    CALL EX_FITS                   ; Check the value against the variable.
    CALL AC_ROUTE                  ; Attach any failure handling.
    LD   BC,(AC_DVAL)              ; The variable's address or offset.
    LD   A,(AC_DINFO)              ; Its class and type.
    LD   D,A                       ; For EX_STORE.
    JP   EX_STORE                  ; Emit the store and return.

;@ROUTINE OUT A,CARRY,ZERO CLOBBERS SIGN,PARITY,HALFCARRY
; BeginReturnValue: for a scalar result, expect its type. An aggregate
; result is parsed by RO_AGGR and needs no expected type.

AC_RET:
    LD   A,(RO_CTYPE)              ; The routine's result type.
    OR   A                         ; None?
    RET  Z                         ; AC_YIELD will reject a value.
    CP   AG_FIRST                  ; An aggregate?
    RET  NC                        ; Parsed by type, not expected type.
    JP   AC_WANT                   ; Expect the scalar type.

;@ROUTINE OUT A,CARRY,ZERO CLOBBERS SIGN,PARITY,HALFCARRY,BC,DE,HL,IX,IY
; Island ReturnValue: a routine without a result may not return a value
; (DG_FLOW). Parse a scalar expression, or an aggregate path or call whose
; type goes to RO_OTYPE.

AC_YIELD:
    LD   A,(RO_CTYPE)              ; The routine's result type.
    OR   A                         ; None?
    JP   Z,EX_EFLOW                ; A value cannot be returned: raise DG_FLOW.
    CP   AG_FIRST                  ; An aggregate?
    JR   NC,.AGGR                  ; Parse a path.
    CALL EX_RUN                    ; Parse and emit the scalar value.
    JP   AC_STASH                  ; Keep it for AC_RETOP.
.AGGR:                         ; The result is an aggregate.
    CALL RO_AGGR                   ; Parse its path; A is its type.
    LD   (RO_OTYPE),A              ; Keep it for AC_RETOP.
    OR   A                         ; Clear carry.
    RET                            ; Back to the engine.

;@ROUTINE OUT A,CARRY,ZERO CLOBBERS SIGN,PARITY,HALFCARRY,B,DE,HL
; CommitReturn: check the value against the result type (DG_CLASH) with no
; failure pending, emit OP_RET or OP_RETA (OP_RETF or OP_RETAF in a
; failable routine) and mark what follows unreachable.

AC_RETOP:
    LD   A,(RO_CTYPE)              ; The routine's result type.
    OR   A                         ; None?
    JP   Z,EX_EFLOW                ; Raise DG_FLOW.
    CP   AG_FIRST                  ; An aggregate?
    JR   NC,.AGGR                  ; Check its type.
    LD   E,A                       ; The scalar result type.
    CALL AC_VALOK                  ; Check the value, with nothing pending.
    LD   A,(RO_CFLAG)              ; The routine's flags.
    AND  RO_FFAIL                  ; Failable?
    LD   A,OP_RET                  ; Assume not.
    JR   Z,.SCALAR                 ; It is not.
    LD   A,OP_RETF                 ; It is: the failable form.
.SCALAR:                       ; A is the return operation.
    CALL TR_OPER                   ; Append it.
    JR   AC_RETOK                  ; Nothing follows the return.
.AGGR:                         ; A is the aggregate result type.
    LD   D,A                       ; Keep it.
    LD   A,(RO_OTYPE)              ; The value's type...
    CP   D                         ; ...must be the same type.
    JP   NZ,EX_ETYPE               ; Raise DG_CLASH.
    CALL AC_SAFE                   ; No failure may be pending.
    LD   A,(RO_CFLAG)              ; The routine's flags.
    AND  RO_FFAIL                  ; Failable?
    LD   A,OP_RETA                 ; Assume not.
    JR   Z,.AGGROP                 ; It is not.
    LD   A,OP_RETAF                ; It is.
.AGGROP:                       ; A is the return operation.
    CALL TR_OPER                   ; Append it; fall into AC_RETOK.

;@ROUTINE OUT A,CARRY,ZERO CLOBBERS SIGN,PARITY,HALFCARRY
; A return was emitted: what follows is unreachable.

AC_RETOK:
    JP   AC_DEAD                   ; Mark it.

;@ROUTINE OUT A,CARRY,ZERO CLOBBERS SIGN,PARITY,HALFCARRY,BC,DE,HL
; CommitBareReturn: `return` without a value, allowed only without a
; result (DG_FLOW). It is the success return (RG_RET), as falling off the
; end would be.

AC_BARE:
    LD   A,(RO_CTYPE)              ; The routine's result type.
    OR   A                         ; None?
    JP   NZ,EX_EFLOW               ; A value is required: raise DG_FLOW.
    CALL RG_RET                    ; OR A if it can fail, then JP exit.
    JR   AC_RETOK                  ; Nothing follows the return.

;@ROUTINE IN A OUT A,CARRY,ZERO CLOBBERS SIGN,PARITY,HALFCARRY,BC,DE,HL
; EmitExit, EmitContinue: one routine for two contiguous actions. Ordinal A
; less one is the statement's token, TK_EXIT or TK_CONT. Jump to the
; innermost loop's exit or continue label (DG_LOOP outside a loop).

AC_GOTO:
    DEC  A                         ; GR_EXIT-1 is TK_EXIT, GR_CONT-1 TK_CONT.
    LD   (AC_DINFO),A              ; Keep the token across CT_LOOP.
    CALL CT_LOOP                   ; HL addresses the innermost loop's frame.
    LD   DE,CT_FEXIT               ; Assume exit.
    LD   A,(AC_DINFO)              ; The statement's token.
    CP   TK_EXIT                   ; exit?
    JR   Z,.PICKED                 ; Yes: the exit label.
    LD   DE,CT_FCONT               ; continue: the continue label.
.PICKED:                       ; DE is the label's field.
    ADD  HL,DE                     ; HL addresses it.
    LD   C,(HL)                    ; Fetch the label.
    JP   CT_JUMP                   ; Append the jump and return.

; ------------------------------------------------------- structured flow

;@ROUTINE IN B OUT A,DE,HL,CARRY,ZERO CLOBBERS SIGN,PARITY,HALFCARRY,B
; Save the enclosing fallthrough state in AC_FLOWS at the current depth,
; then open a frame of kind B (CT_PUSH). A ninth frame raises DG_NEST
; before AC_FLOWS is indexed past its end.

AC_NEST:
    LD   A,(CT_DEPTH)              ; The new frame's depth.
    CP   CT_FCAP                   ; Room for it?
    JP   NC,CT_EDEEP               ; No: raise DG_NEST.
    CALL AC_FLOW                   ; HL addresses the depth's saved state.
    LD   A,(CT_FALLS)              ; The enclosing fallthrough...
    LD   (HL),A                    ; ...saved.
    LD   A,B                       ; The frame's kind.
    JP   CT_PUSH                   ; Open it and return.

;@ROUTINE OUT A,DE,HL CLOBBERS CARRY,HALFCARRY
; Address in HL the AC_FLOWS byte for the current depth, also in A.

AC_FLOW:
    LD   A,(CT_DEPTH)              ; The depth...
    LD   E,A                       ; ...widened...
    LD   D,0                       ; ...to DE...
    LD   HL,AC_FLOWS               ; ...indexes the saved states.
    ADD  HL,DE                     ; HL addresses this depth's.
    RET                            ; Back to the caller.

;@ROUTINE OUT A,DE,HL,CARRY,ZERO CLOBBERS SIGN,PARITY,HALFCARRY
; After a frame has been closed, restore the fallthrough state saved when
; it was opened.

AC_OUTER:
    CALL AC_FLOW                   ; HL addresses the closed frame's saved state.
    LD   A,(HL)                    ; Fetch it.
    LD   (CT_FALLS),A              ; Restore it.
    OR   A                         ; Clear carry.
    RET                            ; Back to the engine.

;@ROUTINE IN A OUT A,DE,HL,CARRY,ZERO CLOBBERS SIGN,PARITY,HALFCARRY,B
; Close the innermost frame. A is whether the compound statement can
; complete; control reaches what follows only if it could also reach the
; statement.

AC_MERGE:
    LD   B,A                       ; Keep the statement's own fallthrough.
    CALL CT_POP                    ; Close the frame.
    CALL AC_FLOW                   ; HL addresses its saved state.
    LD   A,(HL)                    ; Could control reach the statement?
    AND  B                         ; And can the statement complete?
    LD   (CT_FALLS),A              ; Then control reaches what follows.
    OR   A                         ; Clear carry.
    RET                            ; Back to the engine.

;@ROUTINE OUT A,CARRY,ZERO CLOBBERS SIGN,PARITY,HALFCARRY,DE,HL
; Check that the condition just parsed is a Boolean, with no failure
; pending.

AC_BOOL:
    LD   E,SY_BOOL                 ; A condition is a Boolean; fall into AC_CHECK.

;@ROUTINE IN E OUT A,CARRY,ZERO CLOBBERS SIGN,PARITY,HALFCARRY,D,HL
; Check that the expression just parsed fits type E, with no failure
; pending.

AC_CHECK:
    CALL AC_SAFE                   ; No failure may be pending.
    JP   AC_FITTO                  ; Check the type and return.

;@ROUTINE OUT A,CARRY,ZERO CLOBBERS SIGN,PARITY,HALFCARRY,BC,DE,HL
; BeginIf: open an if frame with its exit label and the label of the first
; condition's false branch. CT_FVAR starts at 1: no arm falls through yet.
; Expect a Boolean condition.

AC_IF:
    LD   B,CT_KIF                  ; An if frame...
    CALL AC_NEST                   ; ...opened, saving the fallthrough state.
    CALL CT_EXIT                   ; Number its exit label.
    CALL CT_LABEL                  ; Number the false branch; HL addresses CT_FDEST.
    LD   DE,CT_FVAR-CT_FDEST       ; Step from CT_FDEST...
    ADD  HL,DE                     ; ...to CT_FVAR.
    LD   (HL),1                    ; No arm has fallen through yet.

;@ROUTINE OUT A,CARRY,ZERO CLOBBERS SIGN,PARITY,HALFCARRY
; Expect a Boolean condition.

AC_COND:
    LD   A,SY_BOOL                 ; A condition is a Boolean.
    JP   AC_WANT                   ; Expect it.

;@ROUTINE OUT A,CARRY,ZERO CLOBBERS SIGN,PARITY,HALFCARRY,BC,DE,HL
; BeginIfBody: check the condition and branch to the false label when it
; is false.

AC_THEN:
    CALL AC_BOOL                   ; Check the condition.
    LD   B,CT_FDEST                ; Its false branch goes to CT_FDEST.

;@ROUTINE IN B OUT A,CARRY,ZERO CLOBBERS SIGN,PARITY,HALFCARRY,BC,DE,HL
; Append OP_IFNOT to the label in field B of the innermost frame; the
; body that follows is reachable.

AC_TEST:
    CALL CT_FIELD                  ; HL addresses the label.
    LD   C,(HL)                    ; Fetch it.
    CALL CT_IFNOT                  ; Branch there when the condition is false.

;@ROUTINE OUT A,CARRY,ZERO CLOBBERS SIGN,PARITY,HALFCARRY
; Control can reach this point.

AC_LIVEN:
    JP   AC_LIVE                   ; Record it.

;@ROUTINE OUT A,CARRY,ZERO CLOBBERS SIGN,PARITY,HALFCARRY,BC,DE,HL
; End an arm before elseif or else: note whether it falls through, jump to
; the exit and place the false label, where the next arm begins.

AC_ARM:
    CALL CT_NOTE                   ; Record whether the arm falls through.
    LD   B,CT_FEXIT                ; The if's exit label.
    CALL CT_FIELD                  ; HL addresses it.
    LD   C,(HL)                    ; Fetch it.
    CALL CT_JUMP                   ; The arm ends by jumping there.
    CALL CT_TOP                    ; HL addresses the if frame.
    INC  HL                        ; Step to CT_FDEST.
    LD   C,(HL)                    ; The false branch label.
    JP   CT_PLACE                  ; The next arm starts here.

;@ROUTINE OUT A,CARRY,ZERO CLOBBERS SIGN,PARITY,HALFCARRY,BC,DE,HL
; BeginElseIf: end the arm, number a new false label for the next
; condition and expect it.

AC_ELIF:
    CALL AC_ARM                    ; End the previous arm.
    CALL CT_LABEL                  ; A new false label in CT_FDEST.
    JR   AC_COND                   ; Expect a Boolean condition.

;@ROUTINE OUT A,CARRY,ZERO CLOBBERS SIGN,PARITY,HALFCARRY,BC,DE,HL
; BeginElse: end the arm; the else arm is reachable.

AC_ELSE:
    CALL AC_ARM                    ; End the previous arm.
    JR   AC_LIVEN                  ; The else arm is reachable.

;@ROUTINE OUT A,CARRY,ZERO CLOBBERS SIGN,PARITY,HALFCARRY,B,DE,HL
; FinishElse: note whether the else arm falls through, and record that the
; if has an else, so that it can fail to complete. Returns A zero.

AC_TOTAL:
    CALL CT_NOTE                   ; Record whether the arm falls through.
    LD   B,CT_FMODE                ; The if's else flag.
    CALL CT_FIELD                  ; HL addresses it.
    LD   (HL),1                    ; Every case is covered by an arm.
    XOR  A                         ; Clear carry.
    RET                            ; Back to the engine.

;@ROUTINE OUT A,CARRY,ZERO CLOBBERS SIGN,PARITY,HALFCARRY,BC,DE,HL
; FinishIfClauses: `end` with no else. Note the last arm and place its
; false label, which leads straight to the end.

AC_PART:
    CALL CT_NOTE                   ; Record whether the arm falls through.
    CALL CT_TOP                    ; HL addresses the if frame.
    INC  HL                        ; Step to CT_FDEST.
    LD   C,(HL)                    ; The last false label.
    JP   CT_PLACE                  ; It lands at the end.

;@ROUTINE IN B OUT A,CARRY,ZERO CLOBBERS SIGN,PARITY,HALFCARRY,BC,DE,HL
; Place the label in field B of the innermost frame. Every caller is
; inside that frame.

AC_LABEL:
    CALL CT_FIELD                  ; HL addresses the label.
    LD   C,(HL)                    ; Fetch it.
    JP   CT_PLACE                  ; Place it and return.

;@ROUTINE OUT A,CARRY,ZERO CLOBBERS SIGN,PARITY,HALFCARRY,BC,DE,HL
; EndIf: place the exit label and close the frame. The if completes unless
; it has an else and no arm falls through.

AC_ENDIF:
    LD   B,CT_FEXIT                ; The exit label...
    CALL AC_LABEL                  ; ...is here.
    CALL CT_TOP                    ; HL addresses the if frame.
    PUSH HL                        ; Keep it.
    LD   DE,CT_FVAR                ; Its flag: 1 if no arm falls through.
    ADD  HL,DE                     ; HL addresses it.
    LD   A,(HL)                    ; Fetch it.
    POP  HL                        ; Recover the frame.
    LD   DE,CT_FMODE               ; Its flag: 1 if there is an else.
    ADD  HL,DE                     ; HL addresses it.
    AND  (HL)                      ; 1 if the if cannot complete.
    XOR  1                         ; 1 if it can.
    JP   AC_MERGE                  ; Close the frame.

;@ROUTINE OUT A,CARRY,ZERO CLOBBERS SIGN,PARITY,HALFCARRY,BC,DE,HL
; BeginWhile: open a while frame whose test label is also its continue
; label, number its exit, place the test label and expect the condition.

AC_WHILE:
    LD   B,CT_KLOOP                ; A while frame...
    CALL CT_OPEN                   ; ...opened with its test label in C.
    INC  HL                        ; Step to CT_FCONT.
    LD   (HL),C                    ; continue goes back to the test.
    CALL CT_EXIT                   ; Number the exit label.
    CALL CT_TOP                    ; HL addresses the frame.
    INC  HL                        ; Step to CT_FDEST.
    LD   C,(HL)                    ; The test label...
    CALL CT_PLACE                  ; ...is here.
    JP   AC_COND                   ; Expect a Boolean condition.

;@ROUTINE OUT A,CARRY,ZERO CLOBBERS SIGN,PARITY,HALFCARRY,BC,DE,HL
; BeginWhileBody: check the condition and leave the loop when it is false.

AC_DO:
    CALL AC_BOOL                   ; Check the condition.
    LD   B,CT_FEXIT                ; When false, go to the exit.
    JP   AC_TEST                   ; Append the branch; the body is reachable.

;@ROUTINE OUT A,CARRY,ZERO CLOBBERS SIGN,PARITY,HALFCARRY,BC,DE,HL
; EndWhile: jump back to the test, place the exit label and close the
; frame.

AC_LOOP:
    LD   B,CT_FCONT                ; The test label.
    CALL CT_FIELD                  ; HL addresses it.
    LD   C,(HL)                    ; Fetch it.
    CALL CT_JUMP                   ; Loop back.
    LD   B,CT_FEXIT                ; The exit label...
    CALL AC_LABEL                  ; ...is here.

;@ROUTINE OUT A,CARRY,ZERO CLOBBERS SIGN,PARITY,HALFCARRY,DE,HL
; Close a loop's frame. A loop can always finish, so the fallthrough state
; is the one before it.

AC_LEAVE:
    CALL CT_POP                    ; Close the frame.
    JP   AC_OUTER                  ; Restore the enclosing fallthrough.

; ---------------------------------------------------------- counted loop

;@ROUTINE OUT A,CARRY,ZERO CLOBBERS SIGN,PARITY,HALFCARRY,BC,DE,HL
; BeginFor, with the counter as the current NAME: keep the statement's
; offset for the overflow trap. The counter must be a non-Boolean local
; (DG_COUNT) not already counting an open loop (DG_INUSE). Expect the
; initial value in its type.

AC_FOR:
    LD   HL,(TK_POS)               ; The counter's source offset...
    LD   (AC_WHERE),HL             ; ...is reported by an overflow trap.
    CALL AC_FIND                   ; A is its class and type, BC its offset.
    AND  SY_CMASK                  ; Its class.
    CP   SY_LOCAL                  ; A local?
    JP   NZ,CT_EVAR                ; No: raise DG_COUNT.
    LD   A,D                       ; The class and type.
    AND  SY_TMASK                  ; Its type.
    CP   SY_BOOL                   ; Boolean?
    JP   Z,CT_EVAR                 ; Cannot count: raise DG_COUNT.
    CALL CT_GUARD                  ; Reject an active counter (C, its offset).
    JP   AC_TOVAR                  ; Expect the counter's type.

.INITIAL:                      ; Unreferenced: these bytes are dead.
    CALL AC_FIT                    ; Check against the declaration's type.
    JP   AC_SAFE                   ; Reject a pending failure.

;@ROUTINE IN A OUT A,CARRY,ZERO CLOBBERS SIGN,PARITY,HALFCARRY,BC,DE,HL
; ForTo, ForUntil: one routine for two contiguous actions. Bit 0 of the
; ordinal is 1 for to (inclusive) and 0 for until, the start of AC_MODE.
; Check the initial value and expect a u16 bound.

AC_FORTO:
    AND  1                         ; GR_TO is odd, GR_UNTIL even.
    LD   (AC_MODE),A               ; The mode's inclusive bit.
    CALL AC_ADOPT                  ; Check the initial value against the counter.
    JP   AC_U16                    ; Expect a u16 bound.

;@ROUTINE OUT A,CARRY,ZERO CLOBBERS SIGN,PARITY,HALFCARRY,DE,HL
; Check that the bound just parsed fits a u16, with no failure pending.

AC_LIMIT:
    LD   E,SY_U16                  ; The bound is a u16.
    JP   AC_CHECK                  ; Check it and return.

AC_STEP EQU  AC_LIMIT          ; SaveForStep: the bound is still the result.

;@ROUTINE OUT A,CARRY,ZERO CLOBBERS SIGN,PARITY,HALFCARRY,DE,HL
; DefaultForStep: check the bound; without `step`, the step is one.

AC_BYONE:
    CALL AC_LIMIT                  ; Check the bound.
    LD   DE,1                      ; Step by one...
    LD   (AC_DELTA),DE             ; ...upward (AC_MODE has no downward bit).
    XOR  A                         ; Clear carry.
    RET                            ; Back to the engine.

;@ROUTINE OUT A,CARRY,ZERO CLOBBERS SIGN,PARITY,HALFCARRY,BC,DE,HL
; BeginForBody: open a for frame with test, continue and exit labels and
; fill its counter, mode (bit 2 for a u16 counter), step and trap offset.
; Emit OP_FOR, place the test label and emit OP_TEST; the body is
; reachable.

AC_FORDO:
    LD   B,CT_KFOR                 ; A for frame...
    CALL CT_OPEN                   ; ...opened with its test label.
    LD   B,CT_FCONT                ; Number...
    CALL CT_ALLOT                  ; ...its continue label...
    CALL CT_EXIT                   ; ...and its exit label.
    LD   B,CT_FVAR                 ; The counter field.
    CALL CT_FIELD                  ; HL addresses it.
    LD   A,(AC_DVAL)               ; The counter's frame offset...
    LD   (HL),A                    ; ...into CT_FVAR.
    INC  HL                        ; Step to CT_FMODE.
    CALL EX_DTYPE                  ; The counter's type.
    CP   SY_U16                    ; A word?
    LD   A,(AC_MODE)               ; The mode so far.
    JR   NZ,.MODEOK                ; A u8 counter adds nothing.
    SET  2,A                       ; Mark a u16 counter.
.MODEOK:                       ; A is the complete mode.
    LD   (HL),A                    ; Into CT_FMODE.
    INC  HL                        ; Step to CT_FSTEP.
    LD   DE,(AC_DELTA)             ; The step...
    LD   (HL),E                    ; ...low byte...
    INC  HL                        ; ...then...
    LD   (HL),D                    ; ...high.
    INC  HL                        ; Step to CT_FTRAP.
    LD   DE,(AC_WHERE)             ; The source offset...
    LD   (HL),E                    ; ...low byte...
    INC  HL                        ; ...then...
    LD   (HL),D                    ; ...high.
    CALL CT_TOP                    ; HL addresses the frame.
    CALL CT_SETUP                  ; Append OP_FOR counter,mode.
    CALL CT_TOP                    ; HL addresses the frame.
    INC  HL                        ; Step to CT_FDEST.
    LD   C,(HL)                    ; The test label...
    CALL CT_PLACE                  ; ...is here.
    CALL CT_TEST                   ; Append OP_TEST counter,mode,exit.
    JP   AC_LIVEN                  ; The body is reachable.

;@ROUTINE OUT A,CARRY,ZERO CLOBBERS SIGN,PARITY,HALFCARRY,BC,DE,HL
; EndFor: place the continue label, emit OP_NEXT, place the exit label,
; emit OP_CLEAN to drop the bound, and close the frame.

AC_NEXT:
    LD   B,CT_FCONT                ; The continue label...
    CALL AC_LABEL                  ; ...is here.
    CALL CT_AGAIN                  ; Append OP_NEXT.
    LD   B,CT_FEXIT                ; The exit label...
    CALL AC_LABEL                  ; ...is here.
    LD   A,OP_CLEAN                ; Drop the bound...
    CALL TR_OPER                   ; ...from the machine stack.
    JP   AC_LEAVE                  ; Close the frame.

AC_CEND:                       ; End of the grammar actions' code (marker).
