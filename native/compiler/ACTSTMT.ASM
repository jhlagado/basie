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
;
;  Fallthrough. CT_FALLS says whether control can reach the current point,
;  as the reference's fallsThrough does: every block starts reachable;
;  return, fail, exit and continue end that; an if completes when an arm
;  falls through or it has no else; a loop and a handle statement always
;  complete. A routine with a result may not reach its end (AC_END), and
;  one without gets the success return only when it can (RG_CLOSE).

; ------------------------------------------------------------------ locals

;@ROUTINE OUT A,CARRY,ZERO CLOBBERS SIGN,PARITY,HALFCARRY,BC,DE,HL
; SaveLocalType: declare a scalar local of the current type, provisionally
; so that its initializer cannot use it, and expect an initializer of its
; type. Its offset from IX is the frame's size once it is allocated,
; negated (allocLocal); the frame grows only when the local is committed
; (AC_BIND), after its initializer, as the reference's does.

AC_LOCAL:
    LD   A,(AG_CTYPE)              ; The local's scalar type,
    LD   E,A                       ; kept,
    OR   SY_LOCAL                  ; with class local,
    LD   (AC_DINFO),A              ; is its information byte,
    LD   D,A                       ; for EX_PREP.
    LD   A,E                       ; Its type
    CALL EX_WIDTH                  ; is one or two bytes wide.
    LD   C,A                       ; BC is
    LD   B,0                       ; its size.
    LD   HL,(EM_FRAME)             ; The frame's size
    ADD  HL,BC                     ; with the local in it,
    XOR  A                         ; negated:
    SUB  L                         ; the low byte,
    LD   C,A                       ; then
    SBC  A,A                       ; the high byte
    SUB  H                         ; with the borrow.
    LD   B,A                       ; BC is the local's offset,
    LD   (AC_DVAL),BC              ; its payload.
    CALL EX_PREP                   ; Write the provisional symbol.

;@ROUTINE OUT A,CARRY,ZERO CLOBBERS SIGN,PARITY,HALFCARRY
; Expect an expression of the declaration's type (AC_DINFO).

AC_TOVAR:
    CALL EX_DTYPE                  ; The declaration's type.
    JP   AC_WANT                   ; Expect it.

AC_INIT EQU  AC_TOVAR          ; BeginLocalInitializer: expect the local's type.

;@ROUTINE OUT A CLOBBERS CARRY,ZERO,SIGN,PARITY,HALFCARRY
; DefaultLocalInitializer: without an initializer a local is zeroed in
; the frame (zeroFrame), which AC_NONE in EX_RMETA tells AC_BIND.

AC_ZERO:
    LD   A,AC_NONE                 ; No value was parsed:
    LD   (EX_RMETA),A              ; the local starts at zero.
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
; CommitLocal: allocate the local in the frame (allocLocal), then store its
; initial value there, brought into the registers at its type, or zero it
; when it has no initializer; commit its symbol.

AC_BIND:
    CALL EX_DTYPE                  ; The local's type
    CALL EX_WIDTH                  ; is A bytes wide.
    PUSH AF                        ; Keep the size.
    CALL EM_ALLOC                  ; The frame holds the local.
    POP  BC                        ; B is the size.
    LD   A,(EX_RMETA)              ; Was there an initializer?
    CP   AC_NONE                   ; Not when the default was taken.
    JR   Z,.ZERO                   ; Zero the local.
    LD   D,A                       ; D is the value's metadata,
    CALL EX_DTYPE                  ; E the local's type,
    LD   E,A                       ; HL a known
    LD   HL,(EX_RVAL)              ; value.
    CALL GX_TOREG                  ; The value in A or HL at that type.
    LD   A,(AC_DINFO)              ; The local's class and type
    LD   D,A                       ; for EX_STORE,
    LD   BC,(AC_DVAL)              ; and its offset.
    CALL EX_STORE                  ; Store the value.
    JP   SY_CMT                    ; The local is now in scope.
.ZERO:                         ; B is the local's size.
    LD   HL,(AC_DVAL)              ; Its offset.
    CALL GX_FZERO                  ; Zero its bytes.
    JP   SY_CMT                    ; The local is now in scope.

; -------------------------------------------------------------- statements

;@ROUTINE OUT A,CARRY,ZERO CLOBBERS SIGN,PARITY,HALFCARRY,BC,DE,HL,IX,IY
; Island NameStatement: a statement that begins with a name. A routine is
; called with its result discarded (a service is refused for now, 65.4 i);
; an aggregate path is
; assigned through RO_LET; otherwise the name is a scalar variable
; (DG_CLASH for a constant, DG_INUSE for an active counter) and `=`
; and an expression of its type follow; its value is stored, and then
; what follows the statement is checked for failure handling (AC_ROUTE).

AC_STMT:
    CALL PR_TAKE                   ; Consume the name.
    CALL RO_LIB                    ; A predefined name?
    JR   NC,.ORDINARY              ; No.
    CP   RO_ERRS                   ; An error constant...
    JP   NC,EX_ETYPE               ; ...is not a statement: raise DG_CLASH.
    JP   TR_OPER                   ; A service: refused for now (65.4 i).
.ORDINARY:                     ; Not predefined.
    CALL RO_FIND                   ; A routine?
    JR   NZ,.ASSIGN                ; No: an assignment.
    CALL RO_CALL                   ; Parse and generate the call.
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
.CHECKED:                      ; The variable may be written.
    LD   A,(AC_DINFO)              ; The class...
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
    CALL GX_TOREG                  ; Bring it into A or HL at that type.
    LD   BC,(AC_DVAL)              ; The variable's ordinal or offset.
    LD   A,(AC_DINFO)              ; Its class and type.
    LD   D,A                       ; For EX_STORE.
    CALL EX_STORE                  ; Store it.
    JP   AC_ROUTE                  ; Attach any failure handling and return.

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
; address is generated into HL, its type going to RO_OTYPE and whether it
; is rooted at a parameter to RO_ACNT.

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
    LD   (RO_OTYPE),A              ; Keep it for AC_RETOP,
    LD   A,C                       ; with whether a parameter
    LD   (RO_ACNT),A               ; roots it.
    RET                            ; Back to the engine.

;@ROUTINE OUT A,CARRY,ZERO CLOBBERS SIGN,PARITY,HALFCARRY,BC,DE,HL
; CommitReturn (emitReturn): check the value against the result type
; (DG_CLASH) with no failure pending and bring a scalar into A or HL at
; that type; an aggregate's address is in HL already, and may not be
; rooted at a parameter, whose storage would escape (DG_CLASH; the
; reference's alias-escapes, there being no `from` here). Then the success
; return (RG_RET), and what follows is unreachable.

AC_RETOP:
    LD   A,(RO_CTYPE)              ; The routine's result type.
    OR   A                         ; None?
    JP   Z,EX_EFLOW                ; Raise DG_FLOW.
    CP   AG_FIRST                  ; An aggregate?
    JR   NC,.AGGR                  ; Check its type.
    LD   E,A                       ; The scalar result type.
    CALL AC_VALOK                  ; Check the value, with nothing pending.
    CALL GX_TOREG                  ; The value in A or HL at that type.
    JR   .RETURN                   ; Return it.
.AGGR:                         ; A is the aggregate result type.
    LD   D,A                       ; Keep it.
    LD   A,(RO_OTYPE)              ; The value's type...
    CP   D                         ; ...must be the same type.
    JP   NZ,EX_ETYPE               ; Raise DG_CLASH.
    LD   A,(RO_ACNT)               ; Is it rooted at a parameter?
    OR   A                         ; Its storage is the caller's:
    JP   NZ,EX_ETYPE               ; raise DG_CLASH.
    CALL AC_SAFE                   ; No failure may be pending.
.RETURN:                       ; The result is in the registers.
    CALL RG_RET                    ; OR A if it can fail, then JP exit.

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
; EmitExit, EmitContinue: one routine for two contiguous actions, A being
; GR_EXIT or GR_CONT. Jump to the innermost loop's exit or continue label
; (DG_LOOP outside a loop, exitStatement); what follows is unreachable.

AC_GOTO:
    LD   E,CT_FEXIT                ; Assume exit.
    CP   GR_EXIT                   ; Is it?
    JR   Z,.PICKED                 ; Yes: the exit label.
    LD   E,CT_FCONT                ; continue: the continue label.
.PICKED:                       ; E is the label's field.
    PUSH DE                        ; Keep it.
    CALL CT_LOOP                   ; HL addresses the innermost loop's frame.
    POP  DE                        ; The field,
    LD   D,0                       ; widened,
    ADD  HL,DE                     ; is addressed.
    LD   A,(HL)                    ; The label.
    LD   C,$C3                     ; JP to it.
    CALL EM_JUMP                   ; Append it.
    JP   AC_DEAD                   ; Nothing after it is reachable.

; ------------------------------------------------------- structured flow

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
; BeginIf: open an if frame with its end label and the label of the
; first condition's false branch, and expect a Boolean condition.

AC_IF:
    LD   B,CT_KIF                  ; An if frame.
    CALL CT_PUSH                   ; Open it.
    LD   B,CT_FEXIT                ; Its end.
    CALL CT_NEW                    ; Allocate it.

;@ROUTINE OUT A,CARRY,ZERO CLOBBERS SIGN,PARITY,HALFCARRY,BC,DE,HL
; A new false-branch label for the next condition, which is expected.

AC_ARMS:
    LD   B,CT_FDEST                ; The next arm's label.
    CALL CT_NEW                    ; Allocate it; fall into AC_COND.

;@ROUTINE OUT A,CARRY,ZERO CLOBBERS SIGN,PARITY,HALFCARRY
; Expect a Boolean condition.

AC_COND:
    LD   A,SY_BOOL                 ; A condition is a Boolean.
    JP   AC_WANT                   ; Expect it.

;@ROUTINE OUT A,CARRY,ZERO CLOBBERS SIGN,PARITY,HALFCARRY,BC,DE,HL
; BeginIfBody: check the condition and branch to the next arm when it is
; false; the arm is reachable.

AC_THEN:
    LD   B,CT_FDEST                ; The next arm, when false.

;@ROUTINE IN B OUT A,CARRY,ZERO CLOBBERS SIGN,PARITY,HALFCARRY,BC,DE,HL
; Check the condition and branch to the label in field B when it is false
; (condition); the block that follows is reachable.

AC_TEST:
    CALL AC_BOOL                   ; Check the condition; B is kept.
    CALL CT_IFNOT                  ; Branch there when it is false.
    JP   AC_LIVE                   ; The block starts reachable.

;@ROUTINE OUT A,CARRY,ZERO CLOBBERS SIGN,PARITY,HALFCARRY,BC,DE,HL
; End an if or elseif arm, FinishIfClauses too: note whether it falls
; through, end its block, and jump to the if's end.

AC_ARM:
    CALL CT_NOTE                   ; Record whether the arm falls through.
    CALL CT_BLOCK                  ; The arm's block ends.
    LD   BC,CT_FEXIT*256+$C3       ; JP
    JP   CT_GO                     ; to the end; return.

AC_PART EQU  AC_ARM            ; FinishIfClauses: the last arm ends as any other.

;@ROUTINE OUT A,CARRY,ZERO CLOBBERS SIGN,PARITY,HALFCARRY,BC,DE,HL
; End an arm before elseif or else, whose arm starts at the false label.

AC_SHIFT:
    CALL AC_ARM                    ; End the arm.
    LD   B,CT_FDEST                ; The false label
    JP   CT_DEF                    ; is here; return.

;@ROUTINE OUT A,CARRY,ZERO CLOBBERS SIGN,PARITY,HALFCARRY,BC,DE,HL
; BeginElseIf: end the arm, then a new false label for the next condition,
; which is expected.

AC_ELIF:
    CALL AC_SHIFT                  ; End the previous arm.
    JR   AC_ARMS                   ; A new false label; expect the condition.

;@ROUTINE OUT A,CARRY,ZERO CLOBBERS SIGN,PARITY,HALFCARRY,BC,DE,HL
; BeginElse: end the arm and take a new false label, defined at the end
; as the reference's is; the else arm is reachable.

AC_ELSE:
    CALL AC_SHIFT                  ; End the previous arm.
    LD   B,CT_FDEST                ; A label for the end,
    CALL CT_NEW                    ; never named.
    JP   AC_LIVE                   ; The else arm is reachable.

;@ROUTINE OUT A,CARRY,ZERO CLOBBERS SIGN,PARITY,HALFCARRY,B,DE,HL
; FinishElse: note whether the else arm falls through, and record that the
; if has an else, so that it can fail to complete.

AC_TOTAL:
    CALL CT_NOTE                   ; Record whether the arm falls through.
    LD   B,CT_FMODE                ; The if's flags.
    CALL CT_FIELD                  ; HL addresses them.
    SET  1,(HL)                    ; Every case has an arm.
    RET                            ; Back to the engine.

;@ROUTINE OUT A,CARRY,ZERO CLOBBERS SIGN,PARITY,HALFCARRY,BC,DE,HL
; EndIf: define the last false label and the end, and close the frame.
; The if completes when an arm falls through or it has no else.

AC_ENDIF:
    LD   B,CT_FDEST                ; The last false label
    CALL CT_DEF                    ; is here,
    LD   B,CT_FEXIT                ; and so is
    CALL CT_DEF                    ; the end.
    LD   B,CT_FMODE                ; The flags:
    CALL CT_FIELD                  ; bit 0 an arm falls through,
    LD   A,(HL)                    ; bit 1 an else.
    XOR  2                         ; Bit 1 now says there is none;
    AND  3                         ; nonzero if the if completes.
    LD   (CT_FALLS),A              ; Record it.
    JP   CT_POP                    ; Close the frame and return.

;@ROUTINE OUT A,CARRY,ZERO CLOBBERS SIGN,PARITY,HALFCARRY,BC,DE,HL
; BeginWhile: open a while frame whose test label, defined here, is its
; continue label, with its exit, and expect the condition.

AC_WHILE:
    LD   B,CT_KLOOP                ; A while frame.
    CALL CT_PUSH                   ; Open it.
    LD   B,CT_FCONT                ; The test,
    CALL CT_NEW                    ; allocated,
    CALL EM_LDEF                   ; is here.
    LD   B,CT_FEXIT                ; The exit.
    CALL CT_NEW                    ; Allocate it.
    JR   AC_COND                   ; Expect a Boolean condition.

;@ROUTINE OUT A,CARRY,ZERO CLOBBERS SIGN,PARITY,HALFCARRY,BC,DE,HL
; BeginWhileBody: check the condition and leave the loop when it is false.

AC_DO:
    LD   B,CT_FEXIT                ; When false, go to the exit.
    JR   AC_TEST                   ; The body is reachable.

;@ROUTINE OUT A,CARRY,ZERO CLOBBERS SIGN,PARITY,HALFCARRY,BC,DE,HL
; EndWhile: jump back to the test, define the exit and close the frame.
; A loop can always finish.

AC_LOOP:
    LD   BC,CT_FCONT*256+$C3       ; JP
    CALL CT_GO                     ; back to the test.

;@ROUTINE OUT A,CARRY,ZERO CLOBBERS SIGN,PARITY,HALFCARRY,BC,DE,HL
; Define the loop's exit here and close its frame; what follows is
; reachable.

AC_LEAVE:
    LD   B,CT_FEXIT                ; The exit
    CALL CT_DEF                    ; is here.
    CALL CT_POP                    ; Close the frame.
    JP   AC_LIVE                   ; The loop can finish.

; ---------------------------------------------------------- counted loop

;@ROUTINE OUT A,CARRY,ZERO CLOBBERS SIGN,PARITY,HALFCARRY,BC,DE,HL
; BeginFor, with the counter as the current NAME: it must be a
; non-Boolean local (DG_COUNT) not already counting an open loop
; (DG_INUSE). Keep its offset and width for the loop, and expect the
; initial value at its type.

AC_FOR:
    CALL AC_FIND                   ; D is its class and type, BC its offset.
    AND  SY_CMASK                  ; Its class.
    CP   SY_LOCAL                  ; A local?
    JP   NZ,CT_EVAR                ; No: raise DG_COUNT.
    LD   A,D                       ; The class and type.
    AND  SY_TMASK                  ; Its type.
    CP   SY_BOOL                   ; Boolean?
    JP   Z,CT_EVAR                 ; Cannot count: raise DG_COUNT.
    DEC  A                         ; A u16, 1,
    ADD  A,A                       ; becomes
    ADD  A,A                       ; CT_MWORD.
    LD   (AC_MODE),A               ; The mode so far.
    LD   (AC_INDEX),BC             ; The counter's offset.
    CALL CT_GUARD                  ; Reject an active counter.
    JP   AC_TOVAR                  ; Expect the counter's type.

;@ROUTINE OUT A CLOBBERS CARRY,ZERO,SIGN,PARITY,HALFCARRY
; Return in A the counter's type from AC_MODE: SY_U16 or SY_U8.

AC_CTYPE:
    LD   A,(AC_MODE)               ; The mode.
    AND  CT_MWORD                  ; A u16 counter?
    LD   A,SY_U8                   ; Assume a u8.
    RET  Z                         ; It is one.
    INC  A                         ; A u16.
    RET                            ; A is the type.

;@ROUTINE IN A OUT A,CARRY,ZERO CLOBBERS SIGN,PARITY,HALFCARRY,BC,DE,HL
; ForTo, ForUntil: one routine for two contiguous actions. Bit 0 of the
; ordinal is 1 for to (CT_MINC) and 0 for until. Check the initial value
; against the counter (with no failure pending) and store it there, then
; expect the bound at the counter's type.

AC_FORTO:
    AND  CT_MINC                   ; GR_TO is odd, GR_UNTIL even.
    LD   HL,AC_MODE                ; Add the bit
    OR   (HL)                      ; to the mode.
    LD   (HL),A                    ; Keep it.
    CALL AC_CTYPE                  ; The counter's type
    LD   E,A                       ; is the value's destination.
    CALL AC_VALOK                  ; Check it; D is its metadata, HL its value.
    CALL GX_TOREG                  ; Bring it into A or HL.
    CALL AC_CTYPE                  ; The counter's type
    LD   HL,(AC_INDEX)             ; and offset:
    CALL GX_FPUT                   ; store it.
    CALL AC_CTYPE                  ; The bound is expected
    JP   AC_WANT                   ; at the counter's type.

;@ROUTINE OUT A,CARRY,ZERO CLOBBERS SIGN,PARITY,HALFCARRY,BC,DE,HL
; DefaultForStep: the step is one, upward.

AC_BYONE:
    LD   HL,1                      ; Step by one.
    LD   (AC_DELTA),HL             ; Keep it; fall into AC_STEP.

;@ROUTINE OUT A,CARRY,ZERO CLOBBERS SIGN,PARITY,HALFCARRY,BC,DE,HL
; SaveForStep: the step must fit the counter (DG_STEP). The bound just
; parsed (no failure pending, not a Boolean) is kept in a new frame slot
; of two bytes for the whole loop, at the wider of its type and the
; counter's; an exact bound is a u8 when it fits one. It is stored widened
; to a word (storeBound).

AC_STEP:
    CALL AC_CTYPE                  ; The counter's type:
    DEC  A                         ; a u8 counter
    LD   A,(AC_DELTA+1)            ; takes only a step
    JR   NZ,.FITS                  ; below 256.
    OR   A                         ; Is it?
    JP   NZ,CT_ESTEP               ; No: raise DG_STEP.
.FITS:                         ; The step fits the counter.
    CALL AC_SAFE                   ; No failure may be pending.
    LD   HL,(EX_RVAL)              ; The bound's value, if known,
    LD   A,(EX_RMETA)              ; and its metadata.
    LD   D,A                       ; Keep it.
    AND  SY_TMASK                  ; Its type.
    CP   SY_BOOL                   ; A Boolean
    JP   Z,EX_ETYPE                ; is no bound: raise DG_CLASH.
    OR   A                         ; Typed?
    JR   NZ,.TYPED                 ; Its type stands.
    LD   A,H                       ; An exact value: does it
    OR   A                         ; fit a byte?
    LD   A,SY_U8                   ; Then it is a u8,
    JR   Z,.TYPED                  ; and otherwise
    INC  A                         ; a u16.
.TYPED:                        ; A is the bound's type.
    LD   E,A                       ; Keep it.
    CALL AC_CTYPE                  ; The counter's.
    CP   E                         ; The wider of the two
    JR   C,.WIDER                  ; is the bound's,
    LD   E,A                       ; or the counter's.
.WIDER:                        ; E is the comparison type.
    PUSH DE                        ; Keep the metadata and type
    PUSH HL                        ; and the value.
    LD   A,2                       ; Two bytes
    CALL EM_ALLOC                  ; in the frame for the bound;
    LD   (AC_BOUND),HL             ; their offset.
    POP  HL                        ; The value,
    POP  DE                        ; metadata and type.
    CALL GX_TOREG                  ; The bound in A or HL at type E.
    LD   A,E                       ; A u8 bound
    CP   SY_U8                     ; is widened
    CALL Z,GX_WIDEN                ; to a word.
    LD   A,SY_U16                  ; The word
    LD   HL,(AC_BOUND)             ; goes to its slot.
    JP   GX_FPUT                   ; Store it and return.

;@ROUTINE OUT A,CARRY,ZERO CLOBBERS SIGN,PARITY,HALFCARRY,BC,DE,HL
; BeginForBody: open a for frame with its mode, counter, bound and step,
; and its exit, next-value and body labels. The first test compares the
; counter with the bound: a step up goes on when the counter is below the
; bound, or equal to it for to; a step down stops when it is below, or
; equal for until. The body is reachable.

AC_FORDO:
    LD   B,CT_KFOR                 ; A for frame.
    CALL CT_PUSH                   ; Open it; HL addresses it.
    LD   DE,CT_FMODE               ; Its mode, counter, bound and step
    ADD  HL,DE                     ; are copied
    EX   DE,HL                     ; from the scratch,
    LD   HL,AC_MODE                ; laid out
    LD   BC,7                      ; alike.
    LDIR                           ; Copy them.
    LD   B,CT_FEXIT                ; The exit,
    CALL CT_NEW                    ; allocated.
    LD   B,CT_FCONT                ; The next value,
    CALL CT_NEW                    ; allocated.
    LD   B,CT_FDEST                ; The body,
    CALL CT_NEW                    ; allocated.
    CALL CT_WIDE                   ; HL is the counter; A the mode.
    PUSH AF                        ; Keep the mode.
    CALL CT_BOUND                  ; DE is the bound.
    CALL EM_SEQ                    ; OR A, SBC HL,DE: carry when the
    DB   3,$B7,$ED,$52             ; counter is below, zero when equal.
    POP  AF                        ; The mode.
    BIT  1,A                       ; CT_MDOWN: a step down
    JR   NZ,.DOWN                  ; stops below the bound.
    RRCA                           ; CT_MINC into carry.
    LD   BC,CT_FEXIT*256+$D2       ; until: JP NC to the exit.
    JR   NC,.LAST                  ; That is all.
    LD   BC,CT_FDEST*256+$DA       ; to: JP C
    CALL CT_GO                     ; to the body,
    LD   BC,CT_FDEST*256+$CA       ; JP Z
    CALL CT_GO                     ; to the body,
    LD   BC,CT_FEXIT*256+$C3       ; and JP to the exit.
.LAST:                         ; BC is the last jump.
    CALL CT_GO                     ; Append it.
    JR   .BODY                     ; The body follows.
.DOWN:                         ; A is the mode.
    CALL CT_PAST                   ; JP C, and for until JP Z, to the exit.
.BODY:                         ; The body starts here.
    LD   B,CT_FDEST                ; Its label
    CALL CT_DEF                    ; is defined.
    JP   AC_LIVE                   ; The body is reachable.

;@ROUTINE OUT A,CARRY,ZERO CLOBBERS SIGN,PARITY,HALFCARRY,BC,DE,HL
; EndFor: the body's block ends; the next value is computed where continue
; goes. The counter passed the test, so its distance to the bound in the
; loop's direction is never negative; the loop goes on only if a step fits
; in it, and only then is the next value stored, so nothing wraps. A u8
; counter traps (loop-range) if the next value leaves its type. Then jump
; to the body, define the exit and close the frame.

AC_NEXT:
    CALL CT_BLOCK                  ; The body's block ends.
    LD   B,CT_FCONT                ; The next value
    CALL CT_DEF                    ; starts here.
    CALL CT_WIDE                   ; HL is the counter; A the mode.
    PUSH AF                        ; Keep the mode.
    CALL EM_OP                     ; PUSH HL,
    DB   $E5                       ; the counter,
    LD   A,2                       ; two bytes
    CALL EM_PUSH                   ; of temporaries.
    CALL CT_BOUND                  ; DE is the bound.
    POP  AF                        ; The mode.
    PUSH AF                        ; Kept.
    AND  CT_MDOWN                  ; A step up measures
    LD   A,$EB                     ; bound less counter:
    CALL Z,EM_BYTE                 ; EX DE,HL.
    CALL EM_SEQ                    ; OR A, SBC HL,DE: the distance;
    DB   4,$B7,$ED,$52,$11         ; LD DE,step.
    CALL .STEP                     ; The magnitude.
    CALL EM_SEQ                    ; OR A, SBC HL,DE: carry if it
    DB   4,$B7,$ED,$52,$E1         ; does not fit; POP HL, the counter.
    CALL EM_POP2                   ; Popped.
    POP  AF                        ; The mode.
    PUSH AF                        ; Kept.
    CALL CT_PAST                   ; JP C, and for until JP Z, to the exit.
    CALL EM_OP                     ; LD DE,step.
    DB   $11                       ; The opcode.
    CALL .STEP                     ; The magnitude.
    POP  AF                        ; The mode.
    PUSH AF                        ; Kept.
    AND  CT_MDOWN                  ; Up: ADD HL,DE.
    LD   A,$19                     ; The opcode.
    JR   Z,.ADD                    ; Append it.
    CALL EM_SEQ                    ; Down: OR A,
    DB   2,$B7,$ED                 ; then SBC HL,DE.
    LD   A,$52                     ; Its last byte.
.ADD:                          ; A is the last byte.
    CALL EM_BYTE                   ; Append it.
    POP  AF                        ; The mode.
    AND  CT_MWORD                  ; A u16 counter
    LD   A,SY_U16                  ; is stored as it is.
    JR   NZ,.STORE                 ; It is one.
    CALL EM_SEQ                    ; A u8: LD A,H, OR A,
    DB   3,$7C,$B7,$C4             ; CALL NZ to
    LD   HL,$000F                  ; the loop-range trap,
    LD   DE,0                      ; with no addend,
    CALL EM_REF                    ; its address;
    CALL EM_OP                     ; LD A,L,
    DB   $7D                       ; the byte.
    LD   A,SY_U8                   ; Store a byte.
.STORE:                        ; A is the counter's type.
    PUSH AF                        ; Keep it.
    LD   B,CT_FVAR                 ; The counter's
    CALL CT_FIELD                  ; offset
    LD   E,(HL)                    ; is
    INC  HL                        ; in
    LD   D,(HL)                    ; DE.
    EX   DE,HL                     ; HL is the offset.
    POP  AF                        ; The type.
    CALL GX_FPUT                   ; Store the next value.
    LD   BC,CT_FDEST*256+$C3       ; JP
    CALL CT_GO                     ; to the body.
    JP   AC_LEAVE                  ; Define the exit and close the frame.
.STEP:                         ; Append the step's magnitude.
    LD   B,CT_FSTEP                ; The step
    CALL CT_FIELD                  ; is
    LD   E,(HL)                    ; in
    INC  HL                        ; the
    LD   D,(HL)                    ; frame.
    EX   DE,HL                     ; HL is the magnitude,
    JP   EM_WORD                   ; appended; return.

AC_CEND:                       ; End of the grammar actions' code (marker).
