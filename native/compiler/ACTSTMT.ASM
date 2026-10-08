;==========================================================================
;  Grammar actions: locals, statements and structured flow
;==========================================================================
;
;  The actions for local declarations, name statements (calls and
;  assignments), return, exit and continue, if and while; the counted for
;  loop's are in ACTFOR.ASM, which follows. The calling convention is
;  that of ACTIONS.ASM; the control frames and labels are CONTROL.ASM's.
;
;  Principal entries:
;    AC_LOCAL, AC_INIT, AC_LINIT, AC_ZERO, AC_ADOPT, AC_BIND  local declarations
;    AC_STORE  store the registers into the variable in progress
;    AC_STMT   island NameStatement: a call or an assignment
;    AC_RET, AC_YIELD, AC_RETOP, AC_BARE  return statements
;    AC_GOTO   exit and continue
;    AC_IF, AC_THEN, AC_ELIF, AC_ELSE, AC_TOTAL, AC_PART, AC_ENDIF  if
;    AC_WHILE, AC_DO, AC_LOOP  while
;    AC_NOERR  close a handler (EndHandle), as AC_LEAVE closes a loop
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
    LD   A,(AG_CTYPE)              ; The local's type:
    CALL AG_NOVW                   ; a view is a parameter's only.
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
    ADD  HL,BC                     ; added, within 64K
    JP   C,AG_EDATA                ; (object size),
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
    CALL PL_ISHND                  ; A handle?
    JP   C,HN_LINIT                ; An owning value.
    CALL PL_OWNS                   ; An owning aggregate's
    JP   C,TR_OPER                 ; initializer waits.
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
    CALL PR_SPOT                   ; A string literal
    CP   TK_TEXT                   ; has no definite type:
    LD   A,DG_INFER                ; no-definite-type,
    JP   Z,DG_ISSUE                ; at it.
    LD   (AC_IPOS),HL              ; The initializer's offset;
    XOR  A                         ; nothing is expected,
    CALL EX_INIT                   ; as of an expression.
    CALL HN_INFER                  ; A new handle?
    JR   C,.HANDLE                 ; Its local; an identifier
    JP   Z,AC_PRIME                ; compared, a Boolean's;
    JR   .OTHER                    ; else another value.
.HANDLE:                       ; A handle local:
    CALL AC_LOCAL                  ; The local, of its type (AG_CTYPE),
    LD   A,AC_LHND                 ; is bound
    LD   (EX_RMETA),A              ; to it.
    RET                            ; Back to the engine.
.OTHER:                        ; Not a handle.
    CALL PR_PEEK                   ; A name
    CP   TK_NAME                   ; may root
    JR   NZ,.SCALAR                ; a File or a path.
    CALL AC_ROOT                   ; A is the type it roots:
    CP   AG_FILE                   ; a File,
    JR   Z,.FILE                   ; whose value is taken,
    CP   AG_FIRST                  ; or an aggregate, whose path is
    JR   C,.SCALAR                 ; parsed; anything else is a scalar.
    CALL RO_PART                   ; Parse the path; A is its type.
    CALL PL_ISHND                  ; A handle's value
    JP   C,HN_INPTH                ; (HN_INPTH).
    CP   AG_FILE                   ; A File's
    JR   Z,.FPATH                  ; is loaded.
    CP   AG_FIRST                  ; An aggregate?
    JR   C,.SELECT                 ; No: a scalar it selects.
    CALL AG_ISVW                   ; A view
    JP   C,EX_EFIT                 ; is no local's type (DG_CLASH).
    PUSH AF                        ; Keep the type:
    CALL PL_OWNS                   ; an owning one's
    JP   C,TR_OPER                 ; copy waits.
    CALL GA_ADDR                   ; Its address into HL,
    LD   A,AC_LCOPY                ; copied into the local
    JR   .COPIED                   ; when it is committed.
.FPATH:                        ; A File path:
    CALL GA_LDF                    ; its value,
    JR   .FVAL                     ; in DEHL.
.FILE:                         ; A File value.
    CALL RO_FVAL                   ; It is generated into DEHL:
.FVAL:                         ; compared,
    LD   A,AG_FILE                 ; a Boolean
    CALL HN_ICMP                   ; the expression's
    JP   Z,AC_PRIME                ; first,
    CALL HN_NOCMP                  ; or (no other comparison)
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
    CALL EX_STASH                  ; Keep them for AC_ADOPT and AC_BIND.
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

;@ROUTINE IN A CLOBBERS A,BC,DE,HL,IX,IY,CARRY,ZERO,SIGN,PARITY,HALFCARRY
; An inferred local's initializer whose first primary, of metadata A, a
; comparison of identifiers or Files, is parsed (HN_ICMP): the rest of
; the expression from it (EX_PFROM, from AC_IPOS), the local a Boolean.

AC_PRIME:                      ; A is the primary's metadata.
    LD   (EX_PRIME),A              ; It is the first primary
    LD   A,2                       ; (no lone
    LD   (EX_CHR),A                ; character)
    LD   HL,(AC_IPOS)              ; of the expression
    CALL EX_PFROM                  ; at the initializer.
    CALL EX_STASH                  ; Kept for AC_BIND;
    AND  SY_TMASK                  ; its type
    LD   (AG_CTYPE),A              ; the local's.
    JP   AC_LOCAL                  ; Declare it; return.

;@ROUTINE OUT A CLOBBERS BC,DE,HL,CARRY,ZERO,SIGN,PARITY,HALFCARRY
; The type the current NAME roots, for an inferred local: a predeclared
; constant's (a File for console and printer), a service's result's, a
; routine's result's, an aggregate symbol's; zero for none or a scalar
; symbol. An undeclared name raises DG_UNDEF, as the expression parser
; would.

AC_ROOT:
    CALL RO_LIB                    ; A predeclared name?
    JR   NC,.ROUTINE               ; No.
    AND  $7F                       ; A constant's type or a service's result.
    RET                            ; A is it.
.ROUTINE:                      ; Not predeclared.
    CALL RO_FIND                   ; A routine?
    JR   NZ,.SYMBOL                ; No: a symbol. Its record:
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
    CALL HN_NOINI                  ; A handle must be optional.
    LD   A,AC_NONE                 ; No value was parsed:
    LD   (EX_RMETA),A              ; the local starts at zero.
    RET                            ; Back to the engine.

;@ROUTINE CLOBBERS A,BC,DE,HL,CARRY,ZERO,SIGN,PARITY,HALFCARRY
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
    RET                            ; Back to the engine.

;@ROUTINE OUT A,CARRY,ZERO CLOBBERS SIGN,PARITY,HALFCARRY,DE,HL
; Check the expression just parsed against the declaration's type.

AC_FIT:
    CALL EX_DTYPE                  ; The declaration's type...
    LD   E,A                       ; ...is the destination; fall into AC_FITTO.

;@ROUTINE IN E OUT A,CARRY,ZERO,D,HL CLOBBERS SIGN,PARITY,HALFCARRY
; Check the expression just parsed (EX_RMETA, EX_RVAL) against type E;
; a mismatch raises DG_CLASH, DG_CONV or DG_RANGE. It is the latest
; result again (EX_RTOK), D its metadata and HL its value, as GX_TOREG
; takes them, and a known value is kept at type E (an integer become an
; f32) in EX_RVAL too, for the store that follows. BC is kept.

AC_FITTO:
    PUSH BC                        ; Keep BC
    PUSH DE                        ; and the type.
    CALL EX_RTOK                   ; The value, A its metadata.
    POP  DE                        ; E is the type.
    CALL EX_FITS                   ; Check it.
    PUSH DE                        ; (D and E kept)
    LD   HL,EX_KVAL                ; The value at the type
    LD   DE,EX_RVAL                ; is the one
    LD   BC,5                      ; kept,
    LDIR                           ; five bytes.
    POP  DE                        ; D and E.
    LD   HL,(EX_KVAL)              ; HL its low word.
    POP  BC                        ; Restore BC.
    RET                            ; D, E and HL describe it.

;@ROUTINE CLOBBERS A,BC,DE,HL,CARRY,ZERO,SIGN,PARITY,HALFCARRY
; Store the value in the registers into the variable of the declaration
; or statement in progress: class and type AC_DINFO, place AC_DVAL
; (EX_STORE).

AC_STORE:                      ; The value is in the registers.
    LD   A,(AC_DINFO)              ; The variable's class and type
    LD   D,A                       ; for EX_STORE,
    LD   BC,(AC_DVAL)              ; and its ordinal or offset.
    JP   EX_STORE                  ; Store it and return.

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
    CALL HN_PAYL                   ; Its offset, after its initializer's temporaries;
    LD   (RO_PADD),HL              ; its place, for an aggregate:
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
    CP   AC_LHND                   ; A handle in HL?
    JR   Z,.HANDLE                 ; Link and store it.
    CALL EX_RTOK                   ; D is the value's metadata, HL a known value,
    CALL EX_DTYPE                  ; E the local's
    LD   E,A                       ; type.
    CALL GX_TOREG                  ; The value in the registers at that type.
    CALL AC_STORE                  ; Store the value in the local.
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
.HANDLE:                       ; The local's slot is RO_PADD.
    LD   HL,(RO_PADD)              ; LINK0, the handle
    CALL HN_BIND                   ; stored, the symbol's offset set.
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
    CALL RO_CALL                   ; Parsed and generated;
    CALL HN_DISC                   ; a handle result is freed.
    JP   AC_ROUTE                  ; Attach its failure handling.
.ASSIGN:                       ; The name is a variable.
    CALL AC_FIND                   ; A is its class and type, BC its payload.
    AND  SY_AGGR                   ; An aggregate?
    JP   NZ,RO_LET                 ; Assign to its path.
    LD   A,D                       ; The class and type.
    CALL EX_CLASS                  ; A scalar? A is its class.
    CP   SY_LOCAL                  ; A local?
    CALL Z,CT_GUARD                ; Only a local can be an active for counter (C, its offset).
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
    CALL AC_STORE                  ; Store it in the variable.
    JP   AC_ROUTE                  ; Attach any failure handling and return.

;@ROUTINE OUT A,CARRY,ZERO CLOBBERS SIGN,PARITY,HALFCARRY
; BeginReturnValue: for a scalar result, expect its type. An aggregate
; result is parsed by RO_AGGR and needs no expected type.

AC_RET:
    LD   HL,(TK_POS)               ; `return`, where its form's
    LD   (AC_SPOS),HL              ; faults are reported.
    LD   A,(RO_CTYPE)              ; The routine's result type.
    OR   A                         ; None?
    RET  Z                         ; AC_YIELD will reject a value.
    CALL PL_ISHND                  ; An owning handle's value
    JP   C,HN_RETV                 ; is read now (AC_BARE ends it),
    CP   AG_FILE                   ; as is
    JP   Z,HN_RETV                 ; a File's.
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
    JP   EX_STASH                  ; Keep it for AC_RETOP.
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
    CALL PL_ISHND                  ; An owning handle
    JR   C,.RETURN                 ; is in HL, A its type,
    CP   AG_FILE                   ; and a File
    JR   Z,.RETURN                 ; in DEHL.
    CP   AG_FIRST                  ; An aggregate?
    JR   NC,.AGGR                  ; Check its type.
    LD   E,A                       ; The scalar result type.
    CALL AC_VALOK                  ; Check the value, with nothing pending.
    CALL GX_TOREG                  ; The value in A or HL at that type.
    LD   A,(RO_CTYPE)              ; The result's type, kept
    JR   .RETURN                   ; around the frees.
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
    LD   A,(RO_CTYPE)              ; The result's type.
.RETURN:                       ; The result is in the registers, A its type.
    CALL HN_RET                    ; The owners freed, the result kept;
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
    LD   HL,HN_RETF                ; An owning handle's value
    LD   A,(HL)                    ; read already
    LD   (HL),0                    ; (HN_RETV)
    OR   A                         ; is
    JR   NZ,AC_RETOP               ; returned.
    LD   A,(RO_CTYPE)              ; The routine's result type.
    OR   A                         ; None?
    JP   NZ,EX_EFLOW               ; A value is required: raise DG_FLOW.
    CALL HN_RET                    ; The owners freed (A zero: no result);
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
    PUSH HL                        ; (kept)
    PUSH AF                        ; The loop's index, kept.
    LD   HL,4                      ; The field,
    ADD  HL,SP                     ; under them:
    LD   A,(HL)                    ; exit's
    CP   CT_FEXIT                  ; (Z) or continue's.
    POP  BC                        ; B is the index;
    LD   A,B                       ; exit's state
    PUSH AF                        ; meets the loop's,
    CALL Z,FW_EXIT                 ; continue's back
    POP  AF                        ; edge is
    PUSH AF                        ; checked
    CALL NZ,FW_CONT                ; (A the index).
    POP  AF                        ; A is the index.
    CALL HN_EXIT                   ; The owners from it in are freed.
    POP  HL                        ; The frame.
    POP  DE                        ; The field,
    LD   D,0                       ; widened,
    ADD  HL,DE                     ; is addressed.
    LD   A,(HL)                    ; The label.
    LD   C,$C3                     ; JP to it.
    CALL EM_JUMP                   ; Append it.
    JP   AC_DEAD                   ; Nothing after it is reachable.

;@ROUTINE OUT A,CARRY,ZERO CLOBBERS SIGN,PARITY,HALFCARRY,BC,DE,HL
; BeginStatementAssert: keep the offset of `assert` (AC_SPOS), where a
; certainly false condition is reported, and expect a Boolean.

AC_ASSRT:
    LD   HL,(TK_POS)               ; The offset of `assert`,
    LD   (AC_SPOS),HL              ; kept.
    LD   A,4                       ; An assert condition:
    JR   AC_NOMOV                  ; expect a Boolean.

;@ROUTINE OUT A,CARRY,ZERO CLOBBERS SIGN,PARITY,HALFCARRY,BC,DE,HL
; CommitStatementAssert (assertStatement): a known condition must be the
; Boolean true, anything else known is assertion-false at `assert`; a
; computed one is checked as a Boolean and tested, OR A, CALL Z,TRAP_AST.

AC_TRUE:
    LD   A,(EX_RMETA)              ; The condition's metadata:
    AND  SY_KNOWN+SY_TMASK         ; known,
    JP   P,.TEST                   ; or computed.
    CP   SY_KNOWN+SY_BOOL          ; A known Boolean
    JR   NZ,.FALSE                 ; that
    LD   A,(EX_RVAL)               ; is
    OR   A                         ; true
    RET  NZ                        ; holds.
.FALSE:                        ; Anything else known:
    LD   A,DG_FALSE                ; assertion-false,
    JP   DG_KEPT                   ; at `assert`. No return.
.TEST:                         ; Computed:
    LD   HL,(AC_SPOS)              ; a Boolean, as the reference
    LD   (EX_START),HL             ; reports it, at `assert`,
    CALL AC_BOOL                   ; with no failure pending,
    CALL EM_OP                     ; OR A,
    DB   $B7                       ; then
    LD   A,$CC                     ; CALL Z
    LD   L,HP_ASSRT&$FF            ; to the assertion trap,
    JP   EM_TRAP                   ; appended; return.

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
    XOR  A                         ; A move may be
    LD   (HN_NOMV),A               ; in the condition.
    LD   B,CT_FDEST                ; The next arm's label.
    CALL CT_NEW                    ; Allocate it; fall into AC_COND.

;@ROUTINE OUT A,CARRY,ZERO CLOBBERS SIGN,PARITY,HALFCARRY
; Expect a Boolean condition.

AC_COND:
    LD   A,SY_BOOL                 ; A condition is a Boolean.
    JP   AC_WANT                   ; Expect it.

;@ROUTINE IN A OUT A,CARRY,ZERO CLOBBERS SIGN,PARITY,HALFCARRY
; A while's (A 3) or an assert's (A 4) condition, where no move may
; appear (10.8, HN_NOMV's phrase). Expect a Boolean.

AC_NOMOV:                      ; The condition is next.
    LD   (HN_NOMV),A               ; No move in it;
    JR   AC_COND                   ; expect it.

;@ROUTINE OUT A,CARRY,ZERO CLOBBERS SIGN,PARITY,HALFCARRY,BC,DE,HL
; BeginIfBody: check the condition and branch to the next arm when it is
; false; the arm is reachable.

AC_THEN:
    LD   B,CT_FDEST                ; The next arm, when false.

;@ROUTINE IN B OUT A,CARRY,ZERO CLOBBERS SIGN,PARITY,HALFCARRY,BC,DE,HL
; Check the condition and branch to the label in field B when it is false
; (condition); the block that follows is reachable.

AC_TEST:
    CALL HN_KEEPF                  ; The condition's temporaries stay,
    PUSH BC                        ; (B kept)
    CALL FW_ENTRY                  ; and the arm starts from the state now.
    POP  BC                        ; B.
    CALL AC_BOOL                   ; Check the condition; B is kept.
    CALL CT_IFNOT                  ; Branch there when it is false.
    JP   AC_LIVE                   ; The block starts reachable.

;@ROUTINE OUT A,CARRY,ZERO CLOBBERS SIGN,PARITY,HALFCARRY,BC,DE,HL
; End an if or elseif arm, FinishIfClauses too: note whether it falls
; through, end its block, and jump to the if's end.

AC_ARM:
    CALL CT_NOTE                   ; Record whether the arm falls through.
    CALL CT_BLOCK                  ; The arm's block ends;
    CALL FW_ARMM                   ; its state met.
    LD   BC,CT_FEXIT*256+$C3       ; JP
    JP   CT_GO                     ; to the end; return.

AC_PART EQU  AC_ARM            ; FinishIfClauses: the last arm ends as any other.

;@ROUTINE OUT A,CARRY,ZERO CLOBBERS SIGN,PARITY,HALFCARRY,BC,DE,HL
; End an arm before elseif or else, whose arm starts at the false label.

AC_SHIFT:
    CALL AC_ARM                    ; End the arm;
    CALL FW_REST                   ; the next starts from the if's state.
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
    CALL CT_BLOCK                  ; Its block ends;
    CALL FW_ARMM                   ; its state met.
    CALL CT_FLAGS                  ; HL addresses the if's flags.
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
    CALL CT_MODE                   ; The flags: bit 0 an arm falls
                                   ; through, bit 1 an else.
    XOR  2                         ; Bit 1 now says there is none;
    AND  3                         ; nonzero if the if completes.
    LD   (CT_FALLS),A              ; Record it.
    CALL FW_JOIN                   ; The arms' states met.
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
    LD   A,3                       ; A while condition:
    JP   AC_NOMOV                  ; expect a Boolean.

;@ROUTINE OUT A,CARRY,ZERO CLOBBERS SIGN,PARITY,HALFCARRY,BC,DE,HL
; BeginWhileBody: check the condition and leave the loop when it is false.

AC_DO:
    LD   B,CT_FEXIT                ; When false, go to the exit.
    JR   AC_TEST                   ; The body is reachable.

;@ROUTINE OUT A,CARRY,ZERO CLOBBERS SIGN,PARITY,HALFCARRY,BC,DE,HL
; EndWhile: jump back to the test, define the exit and close the frame.
; A loop can always finish.

AC_LOOP:
    CALL CT_BLOCK                  ; The body's block ends;
    CALL FW_LOOP                   ; its back edge, the paths met.
    LD   BC,CT_FCONT*256+$C3       ; JP
    CALL CT_GO                     ; back to the test.

;@ROUTINE OUT A,CARRY,ZERO CLOBBERS SIGN,PARITY,HALFCARRY,BC,DE,HL
; Define the loop's exit here and close its frame; what follows is
; reachable. EndHandle (AC_NOERR) is the same: success skips to the
; handler's exit, the frame closes, and control always reaches the end of
; a handle statement.

AC_NOERR:                      ; A handle statement ends.
AC_LEAVE:                      ; A loop ends.
    CALL CT_BLOCK                  ; Its block ends (again, for a loop).
    LD   B,CT_FEXIT                ; The exit
    CALL CT_DEF                    ; is here.
    CALL CT_POP                    ; Close the frame.
    JP   AC_LIVE                   ; The loop can finish.
