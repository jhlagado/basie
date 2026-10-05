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
;    AC_LOCAL, AC_INIT, AC_LINIT, AC_ZERO, AC_ADOPT, AC_BIND  local declarations
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
; SaveLocalType: declare a local of the current type, a scalar or an
; aggregate (an open string cannot be one: DG_CLASH), provisionally so
; that its initializer cannot use it, and expect an initializer of its
; type. Its offset from IX is the frame's size once it is allocated,
; negated (allocLocal); the frame grows only when the local is committed
; (AC_BIND), after its initializer, as the reference's does.

AC_LOCAL:
    LD   A,(AG_CTYPE)              ; The local's type.
    CP   AG_VIEW                   ; An open string
    JP   Z,EX_ETYPE                ; is a parameter type only.
    LD   D,SY_AGGR+SY_LOCAL        ; An aggregate local's class,
    CP   AG_FIRST                  ; unless
    JR   NC,.CLASS                 ; it is a scalar:
    OR   SY_LOCAL                  ; then its type with class local.
    LD   D,A                       ; D is its information byte.
.CLASS:                        ; D is the information byte.
    LD   A,D                       ; It is
    LD   (AC_DINFO),A              ; the declaration's.
    LD   A,(AG_CTYPE)              ; The type's
    CALL AG_SIZE                   ; size, HL,
    LD   BC,(EM_FRAME)             ; with the frame's size
    ADD  HL,BC                     ; added,
    XOR  A                         ; negated:
    SUB  L                         ; the low byte,
    LD   C,A                       ; then
    SBC  A,A                       ; the high byte
    SUB  H                         ; with the borrow.
    LD   B,A                       ; BC is the local's offset,
    LD   (AC_DVAL),BC              ; its payload.
    LD   A,(AC_DINFO)              ; D is its
    LD   D,A                       ; information byte.
    CALL EX_PREP                   ; Write the provisional symbol.

;@ROUTINE OUT A,CARRY,ZERO CLOBBERS SIGN,PARITY,HALFCARRY
; Expect an expression of the declaration's type (AC_DINFO).

AC_TOVAR:
    CALL EX_DTYPE                  ; The declaration's type.
    JP   AC_WANT                   ; Expect it.

AC_INIT EQU  AC_TOVAR          ; BeginLocalInitializer: expect the local's type.

;@ROUTINE OUT A,CARRY,ZERO CLOBBERS SIGN,PARITY,HALFCARRY,BC,DE,HL,IX,IY
; Island LocalInitializer: a scalar local's is a run-time expression
; (AC_EXPR), a File's a File value (AC_FILE). An aggregate's is a static
; initializer when it begins with a parenthesis, a bracket or a string
; literal, staged as a program variable's is (AC_IMAGE), its bytes stored
; into the frame when the local is committed, which AC_STAGE in EX_RMETA
; tells AC_BIND; otherwise a path or call of the local's type (DG_CLASH),
; its address in HL, copied into the frame when it is committed
; (AC_LCOPY).

AC_LINIT:
    LD   A,(AG_CTYPE)              ; The local's type.
    CP   AG_FIRST                  ; A scalar?
    JP   C,AC_EXPR                 ; A run-time expression.
    CP   AG_FILE                   ; A File?
    JR   Z,AC_FILE                 ; Its value.
    CALL PR_PEEK                   ; How does it begin?
    CP   TK_LPAR                   ; A record's fields,
    JR   Z,.IMAGE                  ; or
    CP   TK_LBRAC                  ; an array's elements,
    JR   Z,.IMAGE                  ; or
    CP   TK_TEXT                   ; a string literal
    JR   Z,.IMAGE                  ; is static.
    CALL RO_AGGR                   ; A path or call: A is its type.
    LD   B,A                       ; It must be
    LD   A,(AG_CTYPE)              ; the local's
    CP   B                         ; type,
    JP   NZ,EX_EFIT                ; else DG_CLASH at it.
    LD   A,AC_LCOPY                ; Its address is in HL,
    JR   .KIND                     ; copied when the local is committed.
.IMAGE:                        ; A static initializer.
    LD   A,(AC_DINFO)              ; Keep the local's class:
    PUSH AF                        ; AC_OBJ and AC_IMAGE use AC_DINFO.
    LD   A,(AG_CTYPE)              ; The local's type:
    CALL AC_OBJ                    ; size and zero the staging,
    CALL AC_IMAGE                  ; parse the initializer into it,
    CALL AC_EXACT                  ; which must fill it.
    POP  AF                        ; The local's class
    LD   (AC_DINFO),A              ; again.
    LD   A,AC_STAGE                ; Its bytes are staged.
.KIND:                         ; A says what the initializer was.
    LD   (EX_RMETA),A              ; AC_BIND reads it.
    RET                            ; Back to the engine.

;@ROUTINE OUT A,CARRY,ZERO CLOBBERS SIGN,PARITY,HALFCARRY,BC,DE,HL,IX,IY
; A File local's initializer: a File value in DEHL (RO_FVAL), stored when
; the local is committed, which AC_LFILE in EX_RMETA tells AC_BIND.

AC_FILE:
    CALL RO_FVAL                   ; The value in DEHL.
    LD   A,AC_LFILE                ; It is stored
    LD   (EX_RMETA),A              ; when the local is committed.
    RET                            ; Back to the engine.

;@ROUTINE OUT A,CARRY,ZERO CLOBBERS SIGN,PARITY,HALFCARRY,BC,DE,HL,IX,IY
; Island InferredInitializer: a local declared without `as` (localVar)
; takes its initializer's type (D21). A name may root one (AC_ROOT): a
; File value is generated into DEHL; a path or call that roots an
; aggregate is parsed first, and an aggregate's address goes into HL,
; copied when the local is committed (AC_LCOPY), but an open string
; cannot be a local (DG_CLASH), while a scalar it selects is loaded and
; becomes the first primary (EX_PRIME) of the expression that follows.
; Anything else is a run-time expression with no type expected, which
; must have a type of its own: an exact value has none (no-definite-type),
; unless it is one character literal alone, which is a u8 (EX_CHR). Then
; the local is declared as SaveLocalType declares it, and it is committed
; as a typed local is.

AC_INFER:
    CALL PR_PEEK                   ; A string literal
    CP   TK_TEXT                   ; has no definite type:
    LD   A,DG_INFER                ; no-definite-type,
    JP   Z,DG_ISSUE                ; at it.
    CALL PR_PEEK                   ; A name
    CP   TK_NAME                   ; may root
    JR   NZ,.SCALAR                ; a File or a path.
    CALL AC_ROOT                   ; A is the type it roots:
    CP   AG_FILE                   ; a File,
    JR   Z,.FILE                   ; whose value is taken,
    CP   AG_FIRST                  ; or an aggregate, whose path is
    JR   C,.SCALAR                 ; parsed; anything else is a scalar.
    XOR  A                         ; Nothing is expected,
    CALL EX_INIT                   ; as of an expression.
    LD   HL,TK_POS                 ; The name is the first
    LD   DE,EX_VPOS                ; primary's position.
    CALL PR_COPY                   ; Copy the six bytes.
    CALL RO_PART                   ; Parse the path; A is its type.
    CP   AG_FIRST                  ; An aggregate?
    JR   C,.SELECT                 ; No: a scalar it selects.
    CP   AG_VIEW                   ; An open string
    JP   Z,EX_EFIT                 ; is no local's type (DG_CLASH).
    PUSH AF                        ; Keep the type.
    CALL GA_ADDR                   ; Its address into HL,
    LD   A,AC_LCOPY                ; copied into the local
    JR   .COPIED                   ; when it is committed.
.FILE:                         ; A File value.
    CALL RO_FVAL                   ; It is generated into DEHL,
    LD   A,AG_FILE                 ; the local a File,
    PUSH AF                        ; (kept)
    LD   A,AC_LFILE                ; stored when it is committed.
.COPIED:                       ; A tells AC_BIND; the type is kept.
    LD   (EX_RMETA),A              ; AC_BIND reads it.
    POP  AF                        ; The local's type.
    JR   .DECLARE                  ; Declare it.
.SELECT:                       ; A is a scalar's type.
    CALL RO_LOAD                   ; Load it.
    LD   (EX_PRIME),A              ; It is the first primary
    LD   A,2                       ; (no lone character)
    LD   (EX_CHR),A                ; of the expression
    LD   HL,(EX_START)             ; that begins
    CALL EX_PFROM                  ; at the path.
    JR   .TYPED                    ; A and HL describe it.
.SCALAR:                       ; A run-time expression.
    XOR  A                         ; Nothing is expected of it.
    CALL EX_RUN                    ; A and HL describe it.
.TYPED:                        ; A and HL describe the initializer.
    CALL AC_STASH                  ; Keep them for AC_ADOPT and AC_BIND.
    AND  SY_TMASK                  ; Its type:
    JR   NZ,.DECLARE               ; an exact value has none,
    LD   A,(EX_CHR)                ; unless it is
    DEC  A                         ; a character literal alone,
    LD   A,SY_U8                   ; which is a u8;
    JR   Z,.DECLARE                ; otherwise
    LD   A,DG_INFER                ; no-definite-type,
    JP   EX_EVAL                   ; at it.
.DECLARE:                      ; A is the local's type.
    LD   (AG_CTYPE),A              ; It is the declaration's.
    JP   AC_LOCAL                  ; Declare the local; return.

;@ROUTINE OUT A CLOBBERS BC,DE,HL,CARRY,ZERO,SIGN,PARITY,HALFCARRY
; The type the current NAME roots, for an inferred local: a predeclared
; constant's (a File for console and printer), a service's result's, a
; routine's result's, an aggregate symbol's; zero for main or a scalar
; symbol. An undeclared name raises DG_UNDEF, as the expression parser
; would.

AC_ROOT:
    CALL RO_LIB                    ; A predeclared name?
    JR   NC,.ROUTINE               ; No.
    AND  $7F                       ; A constant's type or a service's result.
    RET                            ; A is it.
.ROUTINE:                      ; Not predeclared.
    CALL RO_FIND                   ; A routine?
    JR   NZ,.SYMBOL                ; No: a symbol.
    CP   RO_MAIN                   ; Main has
    JR   Z,.NONE                   ; no result.
    CALL RO_SUBAT                  ; Its record:
    LD   DE,RO_RTYPE               ; its result
    ADD  HL,DE                     ; type
    LD   A,(HL)                    ; is A.
    RET                            ; A is the type.
.SYMBOL:                       ; A symbol.
    CALL RO_SYM                    ; A is its aggregate type, D its class.
    BIT  7,D                       ; SY_AGGR: an aggregate
    RET  NZ                        ; roots its type;
.NONE:                         ; a scalar
    XOR  A                         ; roots nothing.
    RET                            ; A is zero.

;@ROUTINE OUT A CLOBBERS CARRY,ZERO,SIGN,PARITY,HALFCARRY
; DefaultLocalInitializer: without an initializer a local is zeroed in
; the frame (zeroFrame), which AC_NONE in EX_RMETA tells AC_BIND.

AC_ZERO:
    LD   A,AC_NONE                 ; No value was parsed:
    LD   (EX_RMETA),A              ; the local starts at zero.
    RET                            ; Back to the engine.

;@ROUTINE OUT A,CARRY,ZERO CLOBBERS SIGN,PARITY,HALFCARRY,BC,DE,HL
; FinishLocalInitializer: a scalar's value must fit the local's type. A
; pending failure must be followed by `else fail`; without one, a
; following else raises DG_LEAK.

AC_ADOPT:
    LD   A,(AG_CTYPE)              ; A scalar local's
    CP   AG_FIRST                  ; value
    CALL C,AC_FIT                  ; must fit its type.
    LD   A,(RO_PEND)               ; Is a failure pending?
    OR   A                         ; Zero means none.
    JP   NZ,AC_RELAY               ; Require `else fail`.
    CALL PR_PEEK                   ; What follows?
    CP   TK_ELSE                   ; An else, with nothing to handle,
    LD   A,DG_SAFE                 ; is not-failable,
    LD   HL,AC_DPOS                ; at the local's name.
    JP   Z,DG_AT                   ; No return.
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
; initial value there, a scalar brought into the registers at its type
; and a File from DEHL (ixStoreDEHL), or zero it when it has no
; initializer (zeroFrame); an aggregate's staged bytes are stored
; (storeBytesToFrame) or its source copied (copyToFrame). Commit its
; symbol, an aggregate's or a File's with its type.

AC_BIND:
    LD   A,(AG_CTYPE)              ; The local's type
    CALL AG_SIZE                   ; is HL bytes long.
    PUSH HL                        ; Keep the size.
    EX   DE,HL                     ; The frame
    CALL EM_ALLOW                  ; holds the local.
    LD   (RO_PADD),HL              ; Its place, for an aggregate:
    LD   A,GA_FRAME                ; in the frame
    LD   (RO_PKIND),A              ; at its offset.
    POP  BC                        ; BC is its size.
    LD   A,(EX_RMETA)              ; How is it initialized?
    CP   AC_NONE                   ; Not at all?
    JR   Z,.ZERO                   ; Zero it.
    CP   AC_STAGE                  ; Staged bytes?
    JR   Z,.IMAGE                  ; Store them.
    CP   AC_LCOPY                  ; A source's address?
    JR   Z,.COPY                   ; Copy it.
    CP   AC_LFILE                  ; A File in DEHL?
    JR   Z,.FILE                   ; Store it.
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
.ZERO:                         ; BC is the local's size.
    CALL GA_ZERO                   ; Zero its bytes.
    JR   .COMMIT                   ; Commit it.
.IMAGE:                        ; BC is the local's size.
    CALL GA_FILL                   ; Store the staged bytes.
    JR   .COMMIT                   ; Commit it.
.COPY:                         ; BC is the local's size.
    CALL GA_COPY                   ; Copy the source into it.
    JR   .COMMIT                   ; Commit it.
.FILE:                         ; The local's place is set.
    CALL GA_STF                    ; Store DEHL there.
.COMMIT:                       ; The local holds its value.
    LD   A,(AG_CTYPE)              ; Its type:
    CP   AG_FIRST                  ; a scalar's symbol
    JP   C,SY_CMT                  ; is committed,
    JP   SY_TAG                    ; an aggregate's with its type.

; -------------------------------------------------------------- statements

;@ROUTINE OUT A,CARRY,ZERO CLOBBERS SIGN,PARITY,HALFCARRY,BC,DE,HL,IX,IY
; Island NameStatement: a statement that begins with a name. A routine or
; a service is called with its result discarded; an aggregate or File
; path is assigned through RO_LET; otherwise the name is a scalar variable
; (DG_CLASH for a constant, DG_INUSE for an active counter) and `=`
; and an expression of its type follow; its value is stored, and then
; what follows the statement is checked for failure handling (AC_ROUTE).

AC_STMT:
    CALL PR_TAKE                   ; Consume the name.
    LD   HL,(TK_POS)               ; The statement's offset,
    LD   (AC_SPOS),HL              ; where its failure handling is reported.
    CALL RO_LIB                    ; A predeclared name?
    JR   NC,.ORDINARY              ; No.
    JP   M,.CLASS                  ; A constant can't start a statement.
    CALL RO_SVC                    ; A service: parse and generate the call.
    JP   AC_ROUTE                  ; Attach its failure handling.
.ORDINARY:                     ; Not predeclared.
    CALL RO_FIND                   ; A routine?
    JR   NZ,.ASSIGN                ; No: an assignment.
    CALL RO_CALL                   ; Parse and generate the call.
    JP   AC_ROUTE                  ; Attach its failure handling.
.ASSIGN:                       ; The name is a variable.
    CALL AC_FIND                   ; A is its class and type, BC its payload.
    AND  SY_AGGR                   ; An aggregate?
    JP   NZ,RO_LET                 ; Assign to its path.
    LD   A,D                       ; The class and type.
    CALL EX_CLASS                  ; A scalar? A is its class.
    CP   SY_LOCAL                  ; A local?
    JR   NZ,.CHECKED               ; Only a local can be a counter.
    CALL CT_GUARD                  ; Reject an active for counter (C, its offset).
.CHECKED:                      ; The variable may be written.
    LD   A,(AC_DINFO)              ; The class...
    AND  SY_CMASK                  ; ...is zero for a constant...
    JR   NZ,.WRITE                 ; ...which can't start a statement.
.CLASS:                        ; The name is current:
    CALL DG_RNAME                  ; raise the diagnostic below, named:
    DB   DG_CLASS                  ; wrong-class.
.WRITE:                        ; A variable.
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
; address is generated into HL, its type going to RO_OTYPE and whether its
; root is in the frame to RO_ESC.

AC_YIELD:
    LD   A,(RO_CTYPE)              ; The routine's result type.
    OR   A                         ; None?
    JP   Z,EX_EFLOW                ; A value cannot be returned: raise DG_FLOW.
    CP   AG_FIRST                  ; An aggregate?
    JR   NC,.AGGR                  ; Parse a path.
    CALL EX_RUN                    ; Parse and emit the scalar value.
    JP   AC_STASH                  ; Keep it for AC_RETOP.
.AGGR:                         ; The result is an aggregate.
    JP   RO_AGGR                   ; Parse its path; RO_OTYPE is its type.

;@ROUTINE OUT A,CARRY,ZERO CLOBBERS SIGN,PARITY,HALFCARRY,BC,DE,HL
; CommitReturn (emitReturn): check the value against the result type
; (DG_CLASH) with no failure pending and bring a scalar into A or HL at
; that type; an aggregate's address is in HL already, and its path may
; not be rooted in the frame, a local or a parameter, whose storage would
; escape (RO_ESC; DG_CLASH for the reference's alias-escapes, there being
; no `from` here). Then the success
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
    CP   D                         ; ...must be the same type,
    JP   NZ,EX_EFIT                ; else DG_CLASH at the value.
    LD   A,(RO_ESC)                ; Is its root in the frame?
    OR   A                         ; Its storage would escape:
    LD   A,DG_ALIAS                ; alias-escapes,
    JP   NZ,EX_EVAL                ; at the value.
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
; BeginFor, with the counter as the current NAME: it must be a declared,
; non-Boolean local (loop-counter) not already counting an open loop
; (not-writable). Keep its offset and width for the loop, and expect the
; initial value at its type.

AC_FOR:
    CALL SY_FIND                   ; An undeclared counter
    JP   NC,CT_EVAR                ; is no local: loop-counter.
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
; ForTo, ForUntil: one routine for two actions, A being GR_TO or
; GR_UNTIL; to adds CT_MINC to the mode. Check the initial value
; against the counter (with no failure pending) and store it there, then
; expect the bound at the counter's type.

AC_FORTO:
    SUB  GR_TO                     ; Zero for to,
    SUB  1                         ; which alone borrows:
    SBC  A,A                       ; $FF for to, zero for until,
    AND  CT_MINC                   ; CT_MINC for to.
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
    JR   Z,.MIXED                  ; is no bound for a number.
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
.MIXED:                        ; A Boolean bound for a number:
    LD   A,DG_MIXED                ; mixed-operands,
    JP   EX_EVAL                   ; at the bound.

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
    CALL GX_PUSHW                  ; PUSH HL, the counter, two bytes pushed.
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
    DB   2,$7C,$B7                 ; then
    LD   A,$C4                     ; CALL NZ
    LD   L,HP_LOOP&$FF             ; to the loop-range trap;
    CALL EM_TRAP                   ; append it.
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
