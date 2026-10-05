;==========================================================================
;  Calls, services and aggregate paths
;==========================================================================
;
;  Parse calls to source routines (RO_CALL) and to the services (RO_SVC)
;  and generate their code, and parse the paths into aggregates, as the
;  reference compiler's designator does: a name or a call's aggregate
;  result, then any fields, elements, characters, `length` and
;  `capacity`. Each is checked against the routine and parameter tables
;  (ROUTINES.ASM), the predeclared names (PREDEF.ASM) and the aggregate
;  types (AGGR.ASM). The path in hand is kept as a place (RO_PLACE,
;  GENAGGR.ASM), and the code of each step is written as soon as it is
;  parsed. The grammar actions call in for statements; the expression
;  parser enters through RO_FUNC, RO_VALUE and RO_OBJ when a name in an
;  expression is a routine, a service or an aggregate.
;
;  Files. A File is a value of four bytes, in DEHL, as the reference's is
;  (services 2). The native compiler takes one only where a File is
;  expected (RO_FVAL): an argument, an assignment to a File variable, a
;  File local's initializer; there it is console or printer, a service's
;  result or a File variable, never an operand of an expression.
;
;  Principal entries:
;    RO_CALL   parse and generate a call to a source routine
;    RO_SVC    parse and generate a call to a service
;    RO_FVAL   parse a File value into DEHL
;    RO_ROOT   begin a path at an aggregate symbol
;    RO_PATH   parse a path's selections
;    RO_AGGR   parse a path or call whose value is an aggregate's address
;    RO_LET    parse an assignment to an aggregate path
;    RO_FUNC   expression hook: a routine call as a value
;    RO_VALUE  a call's result as an expression's value
;    RO_OBJ    expression hook: a scalar selected from an aggregate
;    RO_KEEP   push the path's block; RO_BACK pops it back
;
;  Escapes. The reference refuses a result rooted in a local or parameter
;  (alias-escapes) by the root of the last path parsed (lastAddressRoot):
;  every variable named in an expression, scalar or aggregate, sets it, a
;  path restores its root's after its own indexes, and a call clears it.
;  RO_ESC keeps whether that root is in the frame.

;@ROUTINE OUT A,BC,D,CARRY,ZERO CLOBBERS SIGN,PARITY,HALFCARRY,HL
; Look up the current NAME as a symbol: D returns its class, BC its payload
; and A its aggregate type, the record's last byte. An undefined name raises
; DG_UNDEF, which does not return. E is kept.

RO_SYM:
    CALL SY_FIND                   ; HL addresses the record.
    JP   NC,SY_UNDEF               ; Raise DG_UNDEF.
    INC  HL                        ; Skip the spelling's address.
    INC  HL                        ; Skip its high byte.
    INC  HL                        ; Skip the length to reach the class.
    LD   D,(HL)                    ; Read the class.
    INC  HL                        ; The payload follows.
    LD   C,(HL)                    ; Low byte.
    INC  HL                        ; High byte.
    LD   B,(HL)                    ; BC is the payload.
    INC  HL                        ; The aggregate type follows.
    LD   A,(HL)                    ; Read it.
    OR   A                         ; With carry clear.
    RET                            ; D, BC and A describe the symbol.

;@ROUTINE CLOBBERS B,DE,HL,IY
; Push the path's block (RO_PLACE) on the machine stack, for RO_BACK to
; restore, across a nested parse that would overwrite it.

RO_KEEP:                       ; The block is RO_PWORD words.
    LD   HL,RO_PLACE               ; Its first word.
    LD   B,RO_PWORD                ; Its words.
    POP  IY                        ; The return address.
.WORD:                         ; B words remain at HL.
    LD   E,(HL)                    ; DE is
    INC  HL                        ; the next
    LD   D,(HL)                    ; word.
    INC  HL                        ; Step past it.
    PUSH DE                        ; Keep it.
    DJNZ .WORD                     ; Until the block is kept.
    JP   (IY)                      ; Return.

;@ROUTINE CLOBBERS B,DE,HL,IY
; Pop the path's block that RO_KEEP pushed back into RO_PLACE.

RO_BACK:                       ; The block is RO_PWORD words.
    LD   HL,RO_STEND               ; Its end.
    LD   B,RO_PWORD                ; Its words.
    POP  IY                        ; The return address.
.WORD:                         ; B words remain.
    POP  DE                        ; The last word kept
    DEC  HL                        ; goes
    LD   (HL),D                    ; back
    DEC  HL                        ; before
    LD   (HL),E                    ; the ones restored.
    DJNZ .WORD                     ; Until the block is back.
    JP   (IY)                      ; Return.

;@ROUTINE OUT A,CARRY,ZERO CLOBBERS SIGN,PARITY,HALFCARRY,BC,DE,HL
; Begin a path at the current NAME, an aggregate symbol (DG_CLASH for any
; other), as the reference's designator does: a program variable or an
; aggregate constant is static, the constant read-only; a parameter is an
; alias through its word in the frame, read-only (no parameter is var),
; but a File parameter is its value in the frame, as a local is. RO_ESC
; says whether the root is in the frame. A returns the type, also in
; RO_OTYPE.

RO_ROOT:
    CALL RO_SYM                    ; A is the type, D the class, BC the payload.
    LD   (RO_OTYPE),A              ; The path's type.
    LD   (RO_PBASE),BC             ; A blob's ordinal or an offset from IX.
    PUSH BC                        ; Keep the payload.
    LD   BC,1-SY_RECB              ; HL is the record's last byte;
    ADD  HL,BC                     ; its start, the name,
    LD   (RO_PROOT),HL             ; a diagnostic may give.
    POP  BC                        ; The payload again.
    LD   HL,0                      ; Nothing on
    LD   (RO_PADD),HL              ; from it yet.
    BIT  7,D                       ; SY_AGGR: an aggregate?
    JP   Z,EX_ETYPE                ; Raise DG_CLASH.
    LD   A,D                       ; The class
    AND  SY_CMASK                  ; alone:
    LD   E,1                       ; a constant is read-only,
    JR   Z,.STATIC                 ; and static.
    DEC  E                         ; A variable may be written.
    CP   SY_GLOB                   ; A program variable?
    JR   Z,.STATIC                 ; It is static.
    LD   H,1                       ; In the frame: RO_ESC.
    CP   SY_PARAM                  ; A parameter?
    JR   NZ,.LOCAL                 ; No: a local, in the frame.
    LD   A,(RO_OTYPE)              ; A File parameter
    CP   AG_FILE                   ; is a value
    JR   Z,.LOCAL                  ; in the frame too.
    INC  E                         ; Another is read-only,
    LD   A,GA_ALIAS                ; an alias through its word.
    JR   .KIND                     ; Record it.
.LOCAL:                        ; BC is the offset from IX.
    LD   A,GA_FRAME                ; In the frame,
    LD   (RO_PADD),BC              ; at IX plus it.
    JR   .KIND                     ; Record it.
.STATIC:                       ; H is zero: not in the frame.
    XOR  A                         ; GA_BLOB.
.KIND:                         ; A is the kind, E read-only, H RO_ESC.
    LD   (RO_PKIND),A              ; The place's kind.
    LD   A,E                       ; Whether it is
    LD   (RO_PRO),A                ; read-only.
    LD   A,H                       ; Whether its root
    LD   (RO_ESC),A                ; is in the frame.
    LD   A,(RO_OTYPE)              ; The type.
    OR   A                         ; Carry clear.
    RET                            ; The path has begun.

;@ROUTINE OUT A,CARRY,ZERO CLOBBERS SIGN,PARITY,HALFCARRY,BC,DE,HL,IX,IY
; Parse a path rooted at the current NAME and its selections, keeping
; RO_ESC as the root left it (the reference's designator restores its
; root after the suffixes), and leave the root's offset in EX_START, as
; an expression leaves its first token's, for a diagnostic about the
; whole path. RO_PROOT keeps the root's symbol record, whose name a
; diagnostic may give. A returns the path's type.

RO_NAMED:
    LD   HL,(TK_POS)               ; The root's offset,
    PUSH HL                        ; kept across the path.
    CALL RO_ROOT                   ; Begin at the name.
    LD   A,(RO_ESC)                ; Keep the root's
    PUSH AF                        ; escape flag.
    CALL RO_PATH                   ; Parse the selections.
    POP  BC                        ; The root's flag
    LD   C,A                       ; (the type kept)
    LD   A,B                       ; is
    LD   (RO_ESC),A                ; restored.
    POP  HL                        ; The root's offset
    LD   (EX_START),HL             ; is the path's.
    LD   A,C                       ; The type.
    OR   A                         ; Carry clear.
    RET                            ; A is the path's type.

;@ROUTINE IN A OUT A,CARRY,ZERO CLOBBERS SIGN,PARITY,HALFCARRY,BC,DE,HL,IX,IY
; Parse the selections from a call's aggregate result of type A, a path's
; computed, read-only start: its address is in HL. A returns the path's
; type.

RO_START:                      ; A is the result type.
    LD   (RO_OTYPE),A              ; The path's type.
    LD   A,GA_HELD                 ; Its address is in HL:
    LD   (RO_PKIND),A              ; computed,
    LD   (RO_PRO),A                ; and read-only (nonzero); fall into RO_PATH.

;@ROUTINE OUT A,CARRY,ZERO CLOBBERS SIGN,PARITY,HALFCARRY,BC,DE,HL,IX,IY
; Parse a path's selections (the reference's suffixes) after its start, the
; place in RO_PLACE: `.field` of a record, `.length` of a string or open
; string, `.capacity` of an open string, `[index]` of an array or string.
; Each step's code is written as it is parsed. A returns the final type.

RO_PATH:
    CALL PR_PEEK                   ; Look at the next token.
    CP   TK_DOT                    ; A field, length or capacity?
    JR   Z,.DOT                    ; Select it.
    CP   TK_LBRAC                  ; An index?
    JP   Z,RO_INDEX                ; Select the element or character.
    LD   A,(RO_OTYPE)              ; The path ends here: its type.
    OR   A                         ; Carry clear.
    RET                            ; A is the type.
.DOT:                          ; Select by name.
    CALL PR_TAKE                   ; Consume the dot.
    LD   A,(RO_OTYPE)              ; The type selected from:
    CP   AG_FIRST                  ; a scalar has no fields,
    JR   C,.NONE                   ; reported at the dot,
    CP   AG_FILE                   ; nor has a File.
    JR   Z,.NONE                   ; (no-such-field).
    CP   AG_VIEW                   ; An open string?
    JR   Z,.STRING                 ; Its length or capacity.
    CALL AG_DESC                   ; HL addresses the descriptor.
    LD   A,(HL)                    ; Its kind.
    CP   AG_KREC                   ; A record?
    JR   Z,RO_FIELD                ; Find the field.
    CP   AG_KSTR                   ; A string?
    JR   Z,.STRING                 ; Its length.
.NONE:                         ; An array has no fields either.
    CALL DG_RAISE                  ; Raise the diagnostic below
    DB   DG_FIELD                  ; at the dot: no-such-field.
.STRING:                       ; A string's length, an open string's capacity.
    CALL RO_NAME                   ; Consume the name.
    LD   HL,KW_LEN                 ; The spelling "length".
    LD   B,6                       ; Its length.
    CALL TK_MATCH                  ; Is the name length?
    JR   C,.LENGTH                 ; The length byte.
    LD   A,(RO_OTYPE)              ; Only an open string
    CP   AG_VIEW                   ; has a capacity.
    JR   NZ,RO_ENAME               ; Raise DG_UNDEF.
    LD   HL,KW_CAP                 ; The spelling "capacity".
    LD   B,8                       ; Its length.
    CALL TK_MATCH                  ; Is the name capacity?
    JR   NC,RO_ENAME               ; Raise DG_UNDEF.
    LD   HL,(RO_PBASE)             ; The view's capacity word
    INC  HL                        ; lies above
    INC  HL                        ; its address word:
    LD   (RO_PADD),HL              ; its low byte, in the frame.
    LD   A,GA_FRAME                ; A frame
    LD   (RO_PKIND),A              ; place.
.LENGTH:                       ; The length is the string's first byte.
    LD   A,SY_U8                   ; A u8,
    LD   (RO_OTYPE),A              ; at the same place,
    LD   (RO_PRO),A                ; and read-only: nonzero.
    JR   RO_PATH                   ; Continue the path.

; Raise DG_FIELD at the selected name, which is no field of the type,
; naming it.

RO_ENAME:
    CALL DG_RNAME                  ; Raise the diagnostic below, named.
    DB   DG_FIELD                  ; No field of that name.

;@ROUTINE OUT A,BC,CARRY,ZERO CLOBBERS SIGN,PARITY,HALFCARRY,E,HL
; Consume a NAME token, or raise DG_TOKEN+TK_NAME.

RO_NAME:
    LD   E,TK_NAME                 ; A name.
    JP   PR_NEED                   ; Consume it and return.

; Select a record field, HL its descriptor: find the field by name, move
; the place on by its offset and continue the path with its type.

RO_FIELD:
    INC  HL                        ; The record's index follows the kind.
    LD   A,(HL)                    ; Read it.
    ADD  A,A                       ; Records take two bytes in AG_RTAB.
    LD   E,A                       ; Form the offset as a word.
    LD   D,0                       ; The table is small.
    LD   HL,AG_RTAB                ; Index the record table.
    ADD  HL,DE                     ; HL addresses the record's entry.
    LD   B,(HL)                    ; B is the first field's index.
    INC  HL                        ; Then the field count.
    LD   D,(HL)                    ; D counts the fields left.
    PUSH BC                        ; Keep the first field
    PUSH DE                        ; and the count.
    CALL RO_NAME                   ; Consume the field's name.
    POP  DE                        ; The count
    POP  BC                        ; and the first field.
.LOOP:                         ; Compare one field's name.
    LD   A,D                       ; Any fields left?
    OR   A                         ; Test the count.
    JR   Z,RO_ENAME                ; Raise DG_UNDEF.
    PUSH DE                        ; AG_FIELD and TK_SAME clobber the count.
    LD   A,B                       ; Select field B.
    CALL AG_FIELD                  ; HL addresses it; the name comes first.
    CALL TK_SAME                   ; Does its spelling match the token?
    POP  DE                        ; Recover the count.
    JR   C,.FOUND                  ; Select this field.
    INC  B                         ; Next field.
    DEC  D                         ; One fewer.
    JR   .LOOP                     ; Continue through the record.
.FOUND:                        ; HL addresses the field.
    LD   DE,AG_FTYPE               ; Skip the field's name.
    ADD  HL,DE                     ; HL addresses the field's type.
    LD   A,(HL)                    ; The field's type
    LD   (RO_OTYPE),A              ; is the path's.
    INC  HL                        ; Its offset follows.
    LD   E,(HL)                    ; Low byte.
    INC  HL                        ; High byte.
    LD   D,(HL)                    ; DE is the field's offset.
    EX   DE,HL                     ; HL is the offset:
    CALL GA_MOVE                   ; the place moves on by it.
    JP   RO_PATH                   ; Continue the path.

; Select an array element or a string character (indexArray,
; indexString). A computed base is pushed before its index is parsed, so
; that the index cannot overwrite it; the path's block and the index's
; position are kept across the index, a u16 expression. A constant index
; into an array is checked now, at the index (DG_RANGE), and moves the
; place on; anything else is checked at run time (GENAGGR.ASM).

RO_INDEX:
    CALL PR_TAKE                   ; Consume the bracket.
    LD   A,(RO_OTYPE)              ; The type indexed:
    CP   AG_FIRST                  ; a scalar
    JR   C,.NOINDEX                ; cannot be indexed,
    CP   AG_FILE                   ; nor can a File.
    JR   Z,.NOINDEX                ; (not-indexable).
    LD   C,2                       ; Bit 1 of RO_PPUSH: a string.
    CP   AG_VIEW                   ; An open string
    JR   Z,.BASE                   ; is one.
    CALL AG_DESC                   ; HL addresses the descriptor.
    LD   A,(HL)                    ; Its kind:
    CP   AG_KREC                   ; a record
    JR   Z,.NOINDEX                ; cannot be indexed;
    CP   AG_KSTR                   ; a string
    JR   Z,.BASE                   ; is one,
    LD   C,0                       ; an array is not.
    JR   .BASE                     ; Index it.
.NOINDEX:                      ; At the bracket.
    CALL DG_RAISE                  ; Raise the diagnostic below:
    DB   DG_NOIDX                  ; not-indexable.
.BASE:                         ; C says which.
    LD   A,(RO_PKIND)              ; Is the base computed?
    CP   GA_HELD                   ; Then its address waits pushed.
    JR   NZ,.KEEP                  ; Otherwise it is addressed later.
    CALL GX_PUSHW                  ; PUSH HL, two bytes pushed; C is kept.
    INC  C                         ; Bit 0 of RO_PPUSH: the base is pushed.
.KEEP:                         ; C holds the two flags.
    LD   A,C                       ; Record
    LD   (RO_PPUSH),A              ; them.
    CALL PR_PEEK                   ; The index's first token:
    LD   HL,(TK_POS)               ; its offset
    LD   (RO_IPOS),HL              ; is where an index out of range is reported.
    CALL RO_KEEP                   ; Keep the path's block across the index.
    LD   A,SY_U16                  ; An index is a u16.
    CALL EX_SUB                    ; A and HL describe it.
    LD   (EX_RMETA),A              ; Keep its metadata
    LD   (EX_RVAL),HL              ; and value.
    CALL RO_BACK                   ; The path's block comes back.
    LD   A,(EX_RMETA)              ; The index's metadata:
    AND  SY_TMASK                  ; a Boolean
    CP   SY_BOOL                   ; is no index:
    JR   Z,.EINDEX                 ; DG_CLASH at the index.
    LD   E,TK_RBRAC                ; The closing bracket.
    CALL PR_NEED                   ; Consume it.
    LD   A,(EX_RMETA)              ; D is the index's
    LD   D,A                       ; metadata,
    LD   HL,(EX_RVAL)              ; HL its value.
    LD   A,(RO_PPUSH)              ; A string's characters
    AND  2                         ; are checked against its length
    JR   NZ,.CHAR                  ; at run time.
    BIT  7,D                       ; SY_KNOWN: a constant index?
    JR   Z,.ITEM                   ; No: checked at run time too.
    PUSH HL                        ; Keep it.
    LD   A,(RO_OTYPE)              ; The array's
    CALL AG_DESC                   ; descriptor:
    INC  HL                        ; its element type,
    LD   A,(HL)                    ; the path's next,
    INC  HL                        ; then
    LD   E,(HL)                    ; its
    INC  HL                        ; length,
    LD   D,(HL)                    ; DE.
    POP  HL                        ; The index
    PUSH HL                        ; (kept)
    OR   A                         ; must be
    SBC  HL,DE                     ; below the length:
    POP  HL                        ; (the index again)
    JR   NC,.ERANGE                ; DG_RANGE at the index.
    LD   (RO_OTYPE),A              ; The element's type.
    PUSH HL                        ; Keep the index.
    CALL AG_SIZE                   ; HL is the element's size,
    POP  DE                        ; DE the index:
    CALL EX_TIMES                  ; the element's offset.
    LD   A,(RO_PPUSH)              ; Is the base pushed?
    RRCA                           ; Then
    JR   NC,.MOVE                  ; it comes back:
    PUSH HL                        ; (the offset kept)
    CALL EM_OP                     ; POP HL,
    DB   $E1                       ; appended,
    CALL EM_POP2                   ; two bytes fewer pushed.
    POP  HL                        ; The offset.
.MOVE:                         ; HL is the element's offset.
    CALL GA_MOVE                   ; The place moves on by it.
    JP   RO_PATH                   ; Continue the path.
.ITEM:                         ; A run-time index, D and HL.
    CALL GA_ITEM                   ; The element's address.
    JP   RO_PATH                   ; Continue the path.
.CHAR:                         ; A string's character.
    CALL GA_CHAR                   ; Its address.
    JP   RO_PATH                   ; Continue the path.
.EINDEX:                       ; A Boolean index.
    LD   A,DG_INDEX                ; index-type,
    JR   .ATINDEX                  ; at the index.
.ERANGE:                       ; A constant index past the end.
    LD   A,DG_PAST                 ; bounds,
.ATINDEX:                      ; A is the diagnostic.
    LD   HL,RO_IPOS                ; Reported at the index.
    JP   DG_AT                     ; No return.
;@ROUTINE IN A OUT D,E,HL CLOBBERS A,BC,IX,IY,CARRY,ZERO,SIGN,PARITY,HALFCARRY
; Parse one scalar argument of expected type A and check that it fits,
; keeping the enclosing expression's wanted type. A failable call cannot be
; an argument. D returns its metadata, E the type and HL a known value, as
; GX_TOREG takes them.

RO_ARG:
    PUSH AF                        ; Keep the expected type.
    CALL EX_SUB                    ; A and HL describe the argument.
    POP  DE                        ; D is the expected type,
    LD   E,D                       ; EX_FITS's destination.
    JP   EX_FITS                   ; Check it against the parameter's type.

;@ROUTINE IN A OUT A,CARRY,ZERO CLOBBERS SIGN,PARITY,HALFCARRY,BC,DE,HL,IX,IY
; Parse a call to routine A, RO_FIND's index, whose name has been read, as
; the reference's call does (RO_ARGS); only a routine declared forward may
; call itself (DG_UNMET otherwise). A returns the result type, zero for
; none. A call to main is refused for now (DG_NYI).

RO_CALL:
    CP   RO_MAIN                   ; Is the callee main?
    JP   Z,TR_OPER                 ; Refused for now.
    LD   C,A                       ; C is the callee.
    LD   A,(RO_CUR)                ; The routine being compiled.
    CP   C                         ; Does it call itself?
    LD   A,C                       ; The callee again.
    CALL RO_SUBAT                  ; HL is its record; the flags survive.
    JR   NZ,.OTHER                 ; Another routine: any may be called.
    PUSH HL                        ; Keep the record.
    LD   DE,RO_RFLAG               ; Its flags:
    ADD  HL,DE                     ; was it
    BIT  3,(HL)                    ; declared forward (RO_FFWD)?
    POP  HL                        ; The record again.
    JR   Z,.NEEDFWD                ; No: it cannot call itself.
.OTHER:                        ; HL is the callee's record.
    INC  HL                        ; Skip the name's
    INC  HL                        ; address
    INC  HL                        ; and length.
    LD   A,(HL)                    ; A is the first parameter,
    INC  HL                        ; B the number
    LD   B,(HL)                    ; of them.
    INC  HL                        ; The record from RO_RTYPE
    PUSH HL                        ; is read when the call closes.
    CALL RO_PARAM                  ; HL is the first parameter's record,
    LD   DE,RO_PTYPE               ; and its type
    ADD  HL,DE                     ; is at HL,
    LD   E,B                       ; E of them,
    LD   D,RO_PLEN                 ; a record apart.
    JR   RO_ARGS                   ; Parse the arguments.
.NEEDFWD:                      ; A routine calls itself without a forward.
    CALL DG_RNAME                  ; Abandon the build, naming it:
    DB   DG_RECUR                  ; recursion-needs-forward.

;@ROUTINE IN HL OUT A,CARRY,ZERO CLOBBERS SIGN,PARITY,HALFCARRY,BC,DE,HL,IX,IY
; Parse a call to the service whose payload in HP_NAMES is at HL, its name
; read, as RO_CALL parses a call to a routine: the payload is laid out as
; a routine record from RO_RTYPE, then the parameters' count and their
; types, a byte apart. A service with a u32 parameter or result is refused
; for now (DG_NYI). A returns the result type, zero for none.

RO_SVC:
    PUSH HL                        ; The record, read when the call closes.
    INC  HL                        ; Its flags:
    BIT  4,(HL)                    ; RO_FWIDE, a u32?
    JP   NZ,TR_OPER                ; Refused for now.
    LD   DE,RO_RARGS-RO_RFLAG+1    ; After the argument bytes
    ADD  HL,DE                     ; is the count:
    LD   E,(HL)                    ; E of them,
    INC  HL                        ; the types after it,
    LD   D,1                       ; a byte apart; fall into RO_ARGS.

;@ROUTINE IN D,E,HL OUT A,CARRY,ZERO CLOBBERS SIGN,PARITY,HALFCARRY,BC,DE,HL,IX,IY
; The arguments of a call and the call (the reference's call), the
; callee's record from RO_RTYPE pushed beneath the return address: E
; parameters whose types are at HL, D bytes apart. Each argument is
; evaluated, left to right, and pushed: a scalar in the registers at its
; parameter's type (a u8 or Boolean widened to a word), a File's four
; bytes (RO_FVAL), an aggregate as its address, a view as its word then
; its address (RO_VIEW). Then CALL the callee, whose exit removes the
; arguments (RETN, or the service's own), so the pushes are counted out
; again. The callee's need joins the largest of this routine's callees
; (noteCall): a routine whose body is not complete has need zero in its
; record, and a service's need is its stack figure. A failable callee's
; failure is consumed at once (RO_FAILS). A call leaves no path's root
; behind (RO_ESC). A returns the result type, zero for none.

RO_ARGS:
    LD   BC,(TK_POS)               ; The callee's name is current: its offset
    PUSH BC                        ; is kept for a failure's diagnostics.
    LD   A,(RO_DEPTH)              ; Calls already being parsed.
    CP   RO_NCAP                   ; Room for another?
    JP   NC,.DEEP                  ; No: raise DG_DEEP.
    INC  A                         ; One more
    LD   (RO_DEPTH),A              ; is being parsed.
    PUSH HL                        ; Keep the types
    PUSH DE                        ; and their spacing and count.
    CALL PR_LEFT                   ; Consume the opening parenthesis.
    POP  DE                        ; E parameters are left,
    POP  HL                        ; the next one's type at HL.
.ARG:                          ; Parse the next argument, if any.
    LD   A,E                       ; Any left?
    OR   A                         ; Zero when every one is parsed.
    JR   Z,.CLOSE                  ; Then the call closes.
    PUSH HL                        ; Keep the types
    PUSH DE                        ; and the count across the peek.
    CALL PR_PEEK                   ; Does the call close
    POP  DE                        ; where
    POP  HL                        ; an argument
    CP   TK_RPAR                   ; is due?
    JR   Z,.ARITY                  ; Too few arguments.
    PUSH HL                        ; Keep the types
    PUSH DE                        ; and the count across the argument.
    LD   A,(HL)                    ; The parameter's type.
    CP   AG_FIRST                  ; An aggregate?
    JR   NC,.AGGR                  ; Its address is passed.
    CALL RO_ARG                    ; D, E and HL describe the argument.
    CALL GX_TOREG                  ; The value in A or HL at the type E.
    LD   A,E                       ; A word
    CP   SY_U16                    ; is pushed as it is;
    JR   Z,.PUSH                   ; a byte widens first:
    CALL EM_SEQ                    ; LD L,A, LD H,0.
    DB   3,$6F,$26,0               ; Append them.
    JR   .PUSH                     ; Push the word.
.AGGR:                         ; A is the parameter's aggregate type.
    CP   AG_FILE                   ; A File?
    JR   Z,.FILE                   ; Its value is passed.
    JR   C,.ADDRESS                ; Below it, an aggregate's address.
    CALL RO_VIEW                   ; A view: its word is pushed.
    JR   .PUSH                     ; Then the address.
.FILE:                         ; A File argument.
    CALL RO_FVAL                   ; Its value in DEHL.
    LD   A,$D5                     ; PUSH DE, the high word,
    CALL GX_PUSHA                  ; two bytes pushed.
    JR   .PUSH                     ; Then the low word.
.ADDRESS:                      ; An aggregate of type A.
    PUSH AF                        ; Keep the type.
    CALL RO_AGGR                   ; A is the argument's type, HL its address.
    POP  BC                        ; B is the parameter's.
    CP   B                         ; The types must be the same,
    JP   NZ,EX_EFIT                ; else DG_CLASH at the argument.
.PUSH:                         ; The argument is in HL.
    CALL GX_PUSHW                  ; PUSH HL, pushed until the call returns.
    POP  DE                        ; The spacing and count.
    POP  HL                        ; The parameter's type:
    LD   C,D                       ; the next
    LD   B,0                       ; is D bytes
    ADD  HL,BC                     ; on.
    DEC  E                         ; One fewer to parse.
    JR   Z,.CLOSE                  ; That was the last.
    PUSH HL                        ; Keep the types
    PUSH DE                        ; and the count.
    LD   E,TK_COMMA                ; A comma separates arguments.
    CALL PR_NEED                   ; Consume it.
    POP  DE                        ; The count
    POP  HL                        ; and the types again.
    JR   .ARG                      ; Parse the next argument.
.ARITY:                        ; Too few or too many arguments.
    CALL DG_RAISE                  ; Abandon the build, at the token:
    DB   DG_ARITY                  ; arity.
.CLOSE:                        ; Every argument is pushed.
    CALL PR_PEEK                   ; The call must close here,
    CP   TK_RPAR                   ; or it has too many arguments.
    JR   NZ,.ARITY                 ; Raise arity.
    CALL PR_TAKE                   ; Consume the closing parenthesis.
    LD   HL,RO_DEPTH               ; This call
    DEC  (HL)                      ; is parsed.
    POP  HL                        ; The callee's name's offset
    LD   (RO_CALLP),HL             ; for RO_FAILS.
    POP  HL                        ; The callee's record from RO_RTYPE.
    LD   A,(HL)                    ; Its result type
    PUSH AF                        ; is returned, so keep it.
    INC  HL                        ; Then its flags,
    LD   A,(HL)                    ; whether it can fail,
    PUSH AF                        ; are kept too.
    INC  HL                        ; Its ordinal.
    LD   E,(HL)                    ; DE is
    INC  HL                        ; the ordinal,
    LD   D,(HL)                    ; the call's target.
    INC  HL                        ; Its need follows.
    PUSH HL                        ; Keep the place.
    CALL EM_OP                     ; CALL nn,
    DB   $CD                       ; the callee.
    EX   DE,HL                     ; HL is the ordinal;
    LD   DE,0                      ; with no addend,
    CALL EM_REF                    ; refer to it.
    POP  HL                        ; The need,
    LD   E,(HL)                    ; low byte
    INC  HL                        ; and
    LD   D,(HL)                    ; high byte.
    INC  HL                        ; Then the argument bytes,
    LD   A,(HL)                    ; which the exit removed:
    PUSH DE                        ; keeping the need,
    CALL EM_POP                    ; they are no longer pushed.
    POP  DE                        ; DE is the callee's need.
    LD   HL,(EM_NEED)              ; The largest callee's need so far.
    OR   A                         ; Clear carry.
    SBC  HL,DE                     ; Carry if this one is larger.
    JR   NC,.SMALLER               ; Keep the larger one.
    LD   (EM_NEED),DE              ; It is the largest.
.SMALLER:                      ; The need is accounted.
    XOR  A                         ; No path's root
    LD   (RO_ESC),A                ; survives the call.
    POP  AF                        ; The callee's flags:
    AND  RO_FFAIL                  ; can it fail?
    CALL NZ,RO_FAILS               ; Then its failure is consumed.
    POP  AF                        ; A is the result type.
    OR   A                         ; Carry clear.
    RET                            ; The result is in A or HL.
.DEEP:                         ; Calls nest too deeply in arguments.
    CALL DG_RAISE                  ; Abandon the build.
    DB   DG_DEEP                   ; Nested too deeply.

;@ROUTINE CLOBBERS A,BC,DE,HL,CARRY,ZERO,SIGN,PARITY,HALFCARRY
; A failable routine has just been called: its failure is consumed by
; what follows the call directly, as the reference's call decides it.
; Before `else` (fail) the routine must be failable itself (not-failable),
; and JP C goes to its exit, A holding the code; before `handle`, JP C
; goes to a new label, and the temporaries pushed beneath the call are
; kept in RO_KEPT for the handler to drop. Anything else is
; failure-unconsumed. Both are reported at the call, RO_CALLP, the first
; naming the callee. RO_PEND is $80 plus the label, which the statement's
; end consumes.

RO_FAILS:
    CALL PR_PEEK                   ; What follows the call?
    CP   TK_HANDL                  ; A handler?
    JR   Z,.TRAP                   ; Jump to it on failure.
    CP   TK_ELSE                   ; `else fail`?
    LD   A,DG_LEAK                 ; Neither: the failure is lost,
    JR   NZ,.LOST                  ; failure-unconsumed.
    LD   A,(RO_CFLAG)              ; Passing it on needs
    AND  RO_FFAIL                  ; a failable routine;
    LD   A,DG_SAFE                 ; this one is not:
    JR   Z,.AT                     ; not-failable.
    LD   A,RG_EXIT                 ; To the exit, A the code.
    JR   .JUMP                     ; Write the jump.
.TRAP:                         ; A handler follows.
    LD   A,(EM_TEMPS)              ; The temporaries
    LD   (RO_KEPT),A               ; beneath the call.
    CALL EM_LNEW                   ; A is the handler's label.
.JUMP:                         ; A is the failure's label.
    PUSH AF                        ; Keep it.
    LD   C,$DA                     ; JP C,
    CALL EM_JUMP                   ; to it on failure.
    POP  AF                        ; The label,
    OR   $80                       ; marked,
    LD   (RO_PEND),A               ; is pending.
    RET                            ; The expression goes on.
.LOST:                         ; A is DG_LEAK.
    LD   HL,(RO_CALLP)             ; The callee's name,
    CALL DG_WORD                   ; at the call, is argument 1.
.AT:                           ; A is the diagnostic.
    LD   HL,(RO_CALLP)             ; At the call.
    JP   DG_HERE                   ; No return.


;@ROUTINE IN A CLOBBERS A,BC,DE,HL,IX,IY,CARRY,ZERO,SIGN,PARITY,HALFCARRY
; A view argument of type A (argument): AG_VIEW or AG_VVIEW for a string,
; AG_BUF or AG_VBUF for an array of u8, the second of each var. A string
; literal, for a string[] that is not var: LD DE,its length, PUSH DE, LD
; HL,literal. Otherwise a path, rooted at a variable or constant (not a
; call), and writable for a var view (DG_CONST): a string's, its address
; into HL, then its capacity, LD DE,n for a declared string or the word of
; an open string passed on, and PUSH DE; an array of u8's, its address
; and LD DE,its length, PUSH DE. The address is pushed by the caller. A
; literal holds at most 253 bytes (DG_LONG); a literal for any other view
; is read-only (DG_CONST), and a path of another type raises DG_CLASH.

RO_VIEW:
    PUSH AF                        ; Keep the view's type.
    CALL PR_PEEK                   ; A literal?
    CP   TK_TEXT                   ; A string literal is one.
    JR   NZ,.PATH                  ; Otherwise a path.
    POP  AF                        ; Only a string[]
    CP   AG_VIEW                   ; that is not var
    JP   NZ,RO_EREAD               ; takes one: raise DG_CONST at it.
    CALL PR_TAKE                   ; Consume it.
    LD   A,(TK_LEN)                ; Its length:
    CP   254                       ; at most 253 bytes,
    JP   NC,AG_ELONG               ; else out of range.
    LD   L,A                       ; HL is
    LD   H,0                       ; the length.
    ADD  A,2                       ; With its length byte and terminator
    LD   B,A                       ; it occupies B bytes.
    PUSH BC                        ; Keep them.
    CALL GA_LDDE                   ; LD DE,length,
    CALL .PUSHDE                   ; pushed.
    POP  BC                        ; The literal's size.
    JP   GA_LIT                    ; LD HL,literal; return.
.PATH:                         ; A path names the object.
    CALL RO_NAME                   ; Its root's name.
    CALL RO_FIND                   ; A routine
    JR   Z,.CLASS                  ; is no variable: wrong-class.
    CALL RO_NAMED                  ; Parse the path; A is its type.
    POP  BC                        ; B is the view's type.
    LD   C,A                       ; C is the path's.
    BIT  0,B                       ; A var view?
    JR   Z,.READ                   ; No: any path will do.
    LD   A,(RO_PRO)                ; A read-only path
    OR   A                         ; cannot be passed:
    LD   A,DG_CONST                ; not-writable,
    JP   NZ,EX_EVAL                ; at the path.
.READ:                         ; B is the view, C the path's type.
    RES  0,B                       ; The view without var:
    LD   A,B                       ; a string's
    CP   AG_VIEW                   ; or an array's?
    LD   A,C                       ; The path's type.
    JR   NZ,.BUFFER                ; An array of u8.
    CP   AG_VIEW                   ; An open string passed on?
    JR   Z,.PASS                   ; Its capacity word.
    CP   AG_FIRST                  ; A scalar
    JP   C,EX_EFIT                 ; is no string: DG_CLASH at the path.
    CALL AG_DESC                   ; HL addresses the descriptor.
    LD   A,(HL)                    ; Its kind
    CP   AG_KSTR                   ; must be a string,
    JP   NZ,EX_EFIT                ; else DG_CLASH at the path.
    INC  HL                        ; Its capacity
    LD   L,(HL)                    ; is
    LD   H,0                       ; HL.
    JR   .WORD                     ; Pass it.
.BUFFER:                       ; A is the path's type.
    CP   AG_FIRST                  ; A scalar,
    JP   C,EX_EFIT                 ; a File
    CP   AG_FILE                   ; or a view
    JP   NC,EX_EFIT                ; is no array: DG_CLASH at the path.
    CALL AG_DESC                   ; HL addresses the descriptor.
    LD   A,(HL)                    ; Its kind
    CP   AG_KARR                   ; must be an array
    JP   NZ,EX_EFIT                ; (DG_CLASH),
    INC  HL                        ; and its element
    LD   A,(HL)                    ; type
    CP   SY_U8                     ; u8 (DG_CLASH).
    JP   NZ,EX_EFIT                ; Its length
    INC  HL                        ; is
    LD   E,(HL)                    ; the
    INC  HL                        ; view's
    LD   D,(HL)                    ; word,
    EX   DE,HL                     ; HL.
.WORD:                         ; HL is the view's word.
    PUSH HL                        ; Keep it.
    CALL GA_ADDR                   ; The address first.
    POP  HL                        ; The word:
    CALL GA_LDDE                   ; LD DE,word,
    JR   .PUSHDE                   ; pushed; return.
.PASS:                         ; The view's address word is at IX+RO_PBASE.
    LD   HL,(RO_PBASE)             ; Its capacity word
    INC  HL                        ; lies
    INC  HL                        ; above it.
    PUSH HL                        ; Keep its offset.
    CALL GA_ADDR                   ; The address first.
    POP  HL                        ; The capacity word
    LD   DE,GX_DLDDE               ; into DE, HL kept (ixWord).
    CALL GX_FACC                   ; Append it.
.PUSHDE:                       ; The view's word is in DE.
    LD   A,$D5                     ; PUSH DE,
    JP   GX_PUSHA                  ; two bytes pushed; return.
.CLASS:                        ; A routine's name where a variable is due.
    CALL DG_RNAME                  ; Raise the diagnostic below, named:
    DB   DG_CLASS                  ; wrong-class.

;@ROUTINE NORETURN
; Raise DG_CONST: a literal, at the current token, where a writable object
; is required.

RO_EREAD:
    CALL DG_RAISE                  ; Raise the diagnostic below.
    DB   DG_CONST                  ; It cannot be written.

;@ROUTINE NORETURN
; Raise DG_CONST at the path just parsed (EX_START), a read-only target,
; naming its root (RO_PROOT): `k is read-only`.

RO_EROOT:
    LD   HL,(RO_PROOT)             ; The root's name
    LD   A,DG_CONST                ; is not writable:
    CALL DG_SETN                   ; argument 1;
    JP   EX_EVAL                   ; at the path's start.

;@ROUTINE CLOBBERS A,BC,DE,HL,IX,IY,CARRY,ZERO,SIGN,PARITY,HALFCARRY
; Parse a File value and generate it into DEHL (the reference's expression
; and toRegisters for a File): console or printer, LD HL,n and LD DE,0; a
; call to a service whose result is a File; or a File variable, local or
; parameter, loaded at its place (GA_LDF). Anything else raises DG_CLASH:
; the native compiler takes a File only as a name or such a call.

RO_FVAL:
    CALL PR_TAKE                   ; A name begins it;
    CP   TK_NAME                   ; anything else is
    JP   NZ,EX_ETYPE               ; no File value (DG_CLASH).
    CALL RO_LIB                    ; A predeclared name?
    JR   NC,.VARIABLE              ; No: a variable.
    JP   P,.SERVICE                ; Not a constant: a service.
    CP   SY_KNOWN+AG_FILE          ; The constant must be a File,
    JP   NZ,EX_ETYPE               ; else DG_CLASH.
    INC  HL                        ; Its value,
    LD   L,(HL)                    ; the runtime's
    LD   H,0                       ; fixed File:
    CALL EM_OP                     ; LD HL,n,
    DB   $21                       ; the opcode,
    CALL EM_WORD                   ; and n;
    CALL EM_SEQ                    ; then LD DE,0,
    DB   3,$11,0,0                 ; the high word.
    RET                            ; DEHL is the File.
.SERVICE:                      ; HL is the service's payload.
    CALL RO_SVC                    ; A is its result type,
.FILE:                         ; or the variable's.
    CP   AG_FILE                   ; A File
    RET  Z                         ; is in DEHL, or to be loaded.
    JP   EX_ETYPE                  ; Anything else raises DG_CLASH.
.VARIABLE:                     ; A variable, or nothing.
    CALL RO_NAMED                  ; Parse it; A is its type.
    CALL .FILE                     ; It must be a File,
    JP   GA_LDF                    ; loaded at its place; return.

;@ROUTINE OUT A,CARRY,ZERO CLOBBERS SIGN,PARITY,HALFCARRY,BC,DE,HL,IX,IY
; Parse a path or a call whose value is an aggregate, and generate its
; address into HL. A returns its type.

RO_AGGR:
    CALL RO_NAME                   ; A path starts with a name.
    CALL RO_FIND                   ; Is it a routine?
    JR   NZ,.SYMBOL                ; Otherwise it is a symbol.
    LD   HL,(TK_POS)               ; The call's offset,
    PUSH HL                        ; kept across it.
    CALL RO_CALL                   ; A is the result type, HL the address.
    CP   AG_FIRST                  ; It must be an aggregate.
    JP   C,EX_ETYPE                ; Raise DG_CLASH.
    CALL RO_START                  ; Parse the rest of the path.
    POP  HL                        ; The call's offset
    LD   (EX_START),HL             ; is the value's.
    JR   .ADDRESS                  ; Generate its address.
.SYMBOL:                       ; Root the path at a symbol.
    CALL RO_NAMED                  ; Parse the path.
.ADDRESS:                      ; A is the path's type.
    CP   AG_FIRST                  ; It must be an aggregate:
    JP   C,EX_EFIT                 ; `.length` and elements are not.
    CALL GA_ADDR                   ; Its address into HL.
    LD   A,(RO_OTYPE)              ; A is its type.
    OR   A                         ; Carry clear.
    RET                            ; The address is in HL.

;@ROUTINE IN A OUT A,CARRY,ZERO CLOBBERS SIGN,PARITY,HALFCARRY,BC,DE,HL
; Make the scalar path of type A an expression value (loadDesignator); an
; aggregate is no value here (DG_CLASH). A returns its type.

RO_LOAD:
    CP   AG_FIRST                  ; An aggregate is not a scalar value:
    JP   NC,EX_EFIT                ; DG_CLASH at the path.
    CALL GA_LOAD                   ; Load it into A or HL.
    LD   A,(RO_OTYPE)              ; The scalar's type.
    OR   A                         ; Carry clear.
    RET                            ; A is the type.

;@ROUTINE IN A OUT A,CARRY,ZERO CLOBBERS SIGN,PARITY,HALFCARRY,BC,DE,HL,IX,IY
; The expression parser's hook for a routine name, read already: parse
; the call to routine A and make its result, or a scalar selected from an
; aggregate result, the expression's value of type A. RO_VALUE does the
; same for a call already parsed, its result type A: a service's.

RO_FUNC:
    CP   RO_MAIN                   ; Main returns nothing.
    JR   Z,RO_EVOID                ; Raise no-value.
    PUSH AF                        ; Keep the routine.
    CALL RO_SUBAT                  ; HL is its record:
    LD   DE,RO_RTYPE               ; a routine
    ADD  HL,DE                     ; without a result
    LD   A,(HL)                    ; has no value,
    OR   A                         ; reported
    JR   Z,RO_EVOID                ; at its name.
    POP  AF                        ; The routine.
    CALL RO_CALL                   ; A is the result type.
RO_VALUE:                      ; A call's result type is A, never zero.
    CP   AG_FIRST                  ; Is the result an aggregate?
    RET  C                         ; No: A is the scalar result type.
    CALL RO_START                  ; Parse the selections.
    JR   RO_LOAD                   ; Load the scalar they select.

;@ROUTINE NORETURN
; Raise no-value at the current name, a routine or service without a
; result used as a value, naming it.

RO_EVOID:
    CALL DG_RNAME                  ; Raise the diagnostic below, named:
    DB   DG_VOID                   ; no-value.

;@ROUTINE OUT A,CARRY,ZERO CLOBBERS SIGN,PARITY,HALFCARRY,BC,DE,HL,IX,IY
; The expression parser's hook for an aggregate symbol, the current NAME:
; parse the path and load the scalar it selects.

RO_OBJ:
    CALL RO_NAMED                  ; Parse the path; A is its type.
    JR   RO_LOAD                   ; Load the scalar it selects.

;@ROUTINE OUT A,CARRY,ZERO CLOBBERS SIGN,PARITY,HALFCARRY,BC,DE,HL,IX,IY
; Parse an assignment whose target is a path rooted at the current NAME,
; an aggregate symbol (assign): a read-only target raises DG_CONST. An
; aggregate is copied: its address pushed, the source's address, POP DE,
; LD BC,size, LDIR, the source a path or call of the same type or, for a
; string, a literal within its capacity (DG_LONG), which takes the whole
; string's bytes. A scalar's value is checked against its type and stored:
; through its address, computed first and pushed while the value is,
; then POP DE and LD (DE),A or EX DE,HL, LD (HL),E, INC HL, LD (HL),D; or
; at a static or frame place directly. A File is a value (RO_FVAL),
; stored at its static or frame place. Then any failure handling.

RO_LET:
    CALL RO_NAMED                  ; Parse the target; A is its type.
    PUSH AF                        ; Keep it.
    CALL PR_EQUAL                  ; Consume the equals sign.
    LD   A,(RO_PRO)                ; A read-only target
    OR   A                         ; cannot be
    JP   NZ,RO_EROOT               ; assigned: raise DG_CONST at it.
    POP  AF                        ; The target's type.
    CP   AG_FILE                   ; A File?
    JR   Z,.FILE                   ; Its value is stored.
    CP   AG_FIRST                  ; An aggregate?
    JR   NC,.COPY                  ; Copy it whole.
    LD   A,(RO_PKIND)              ; A computed place?
    CP   GA_HELD                   ; Its address
    CALL Z,GX_PUSHW                ; is in HL: PUSH HL, two bytes pushed.
    CALL RO_KEEP                   ; Keep the place across the value.
    LD   A,(RO_OTYPE)              ; The target's type
    CALL EX_RUN                    ; is wanted of the value.
    LD   (EX_RMETA),A              ; Keep its metadata
    LD   (EX_RVAL),HL              ; and a known value.
    CALL RO_BACK                   ; The place comes back.
    LD   A,(RO_OTYPE)              ; The target's type
    LD   E,A                       ; is the value's destination:
    CALL AC_FITTO                  ; it must fit; D, E and HL describe it,
    CALL GX_TOREG                  ; brought into A or HL.
    LD   A,(RO_PKIND)              ; A computed place?
    CP   GA_HELD                   ; Its address is pushed:
    JR   Z,.THROUGH                ; store through it.
    CALL GA_STORE                  ; Store at the place.
    JP   AC_ROUTE                  ; Any failure handling; return.
.THROUGH:                      ; The address is pushed.
    CALL GA_POPDE                  ; POP DE, two bytes fewer pushed.
    LD   A,(RO_OTYPE)              ; A word?
    CP   SY_U16                    ; Then four bytes.
    LD   A,$12                     ; LD (DE),A for a byte.
    JR   NZ,.STORE                 ; A byte.
    CALL EM_SEQ                    ; EX DE,HL, LD (HL),E, INC HL:
    DB   3,$EB,$73,$23             ; the low byte,
    LD   A,$72                     ; then LD (HL),D.
.STORE:                        ; A is the last byte.
    CALL EM_BYTE                   ; Append it.
    JP   AC_ROUTE                  ; Any failure handling; return.
.FILE:                         ; A File variable.
    CALL RO_KEEP                   ; Keep its place across the value.
    CALL RO_FVAL                   ; The value into DEHL.
    CALL RO_BACK                   ; The place comes back.
    CALL GA_STF                    ; Store the value there.
    JP   AC_ROUTE                  ; Any failure handling; return.
.COPY:                         ; Copy an aggregate of type A.
    PUSH AF                        ; Keep the type.
    CALL GA_ADDR                   ; The target's address,
    CALL GX_PUSHW                  ; PUSH HL, two bytes pushed.
    POP  AF                        ; The target's type.
    PUSH AF                        ; Kept.
    CALL PR_PEEK                   ; A string literal?
    CP   TK_TEXT                   ; Then
    JR   Z,.TEXT                   ; it is copied in.
    CALL RO_AGGR                   ; Parse the source; A is its type.
    POP  DE                        ; D is the target's type.
    CP   D                         ; The types must be the same,
    JP   NZ,EX_EFIT                ; else DG_CLASH at the source.
.COPIED:                       ; A is the type; the source is in HL.
    PUSH AF                        ; Keep the type.
    CALL GA_POPDE                  ; POP DE, the target.
    POP  AF                        ; The type's
    CALL AG_SIZE                   ; size, HL:
    CALL GA_LDIR                   ; LD BC,size, LDIR.
    JP   AC_ROUTE                  ; Any failure handling; return.
.TEXT:                         ; A literal into a string.
    POP  AF                        ; The target's type.
    PUSH AF                        ; Kept.
    CALL AG_DESC                   ; HL addresses the descriptor.
    LD   A,(HL)                    ; Its kind
    CP   AG_KSTR                   ; must be a string,
    JP   NZ,EX_ETYPE               ; else DG_CLASH.
    INC  HL                        ; Its capacity.
    LD   B,(HL)                    ; B is it.
    PUSH BC                        ; Keep it.
    CALL PR_TAKE                   ; Consume the literal.
    POP  BC                        ; The capacity.
    LD   A,(TK_LEN)                ; The literal's length
    CP   B                         ; must not exceed it:
    JR   Z,.FITS                   ; equal fits,
    JP   NC,AG_ELONG               ; longer is out of range.
.FITS:                         ; B is the capacity.
    INC  B                         ; The string takes it
    INC  B                         ; and two bytes more.
    CALL GA_LIT                    ; LD HL,literal.
    POP  AF                        ; The string's type.
    JR   .COPIED                   ; Copy it.
