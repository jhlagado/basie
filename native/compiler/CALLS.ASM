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
;    RO_NAMED  parse a path rooted at an aggregate symbol
;    RO_PATH   parse a path's selections
;    RO_AGGR   parse a path or call whose value is an aggregate's address
;    RO_LET    parse an assignment to an aggregate path (ASSIGN.ASM)
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
; DG_UNDEF, which does not return. E is kept. RO_PROOT keeps the record,
; whose name a diagnostic about a path rooted at it may give.

RO_SYM:
    CALL SY_FIND                   ; HL addresses the record.
    JP   NC,SY_UNDEF               ; Raise DG_UNDEF.
    LD   (RO_PROOT),HL             ; A path's root, for its diagnostics.
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
    CALL WD_GET                    ; DE is the next word. Step past it.
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

;@ROUTINE OUT A,CARRY,ZERO CLOBBERS SIGN,PARITY,HALFCARRY,BC,DE,HL,IX,IY
; Parse a path rooted at the current NAME and its selections, keeping
; RO_ESC as the root left it (the reference's designator restores its
; root after the suffixes), and leave the root's offset in EX_START, as
; an expression leaves its first token's, for a diagnostic about the
; whole path. RO_PROOT keeps the root's symbol record, whose name a
; diagnostic may give. A returns the path's type.
;
; The root is an aggregate symbol (DG_CLASH for any other), begun as the
; reference's designator does: a program variable or an aggregate constant
; is static, the constant read-only; a parameter is an alias through its
; word in the frame, read-only unless var (SY_PVAR), a var record's owner
; word above it (RO_POWN); but a File parameter is its value in the frame,
; as a local is. RO_ESC says whether the root is in the frame, a parameter
; the from clause names (SY_PFROM) counting as outside it.

RO_NAMED:
    LD   HL,(TK_POS)               ; The root's offset,
    LD   (FW_PLACE),HL             ; where a use of it is reported,
    PUSH HL                        ; kept across the path.
    CALL RO_SYM                    ; A is the type, D the class, BC the payload.
    LD   (RO_OTYPE),A              ; The path's type.
    LD   (RO_PBASE),BC             ; A blob's ordinal or an offset from IX.
    LD   HL,0                      ; Nothing on
    LD   (RO_PADD),HL              ; from it yet,
    LD   (RO_POWN),HL              ; no owner word,
    LD   (RO_PPUSH),HL             ; nothing pushed (RO_IPOS's low byte too).
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
    JR   Z,.LOCAL                  ; in the frame too,
    CALL PL_ISHND                  ; as is
    JR   NC,.NOTH                  ; a handle,
    BIT  1,D                       ; but for a slot-holder (var),
    JR   Z,.LOCAL                  ; an alias whose owner word
    PUSH HL                        ; is
    LD   H,B                       ; two
    LD   L,C                       ; bytes
    INC  HL                        ; above
    INC  HL                        ; its
    LD   (RO_POWN),HL              ; word.
    POP  HL                        ; (H is RO_ESC.)
    JR   .ALIAS                    ; Writable.
.NOTH:                         ; Not a handle.
    BIT  0,D                       ; SY_PFROM: named in from,
    JR   Z,.OWNED                  ; its root
    DEC  H                         ; may be returned.
.OWNED:                        ; A is the type.
    BIT  1,D                       ; SY_PVAR?
    JR   NZ,.WRITE                 ; Then writable.
    INC  E                         ; Another is read-only.
    JR   .ALIAS                    ; An alias.
.WRITE:                        ; A var parameter: a record's
    CP   AG_OPEN                   ; owner word
    JR   NC,.ALIAS                 ; (no view is a record)
    PUSH HL                        ; follows
    PUSH DE                        ; its address
    CALL PL_OWORD                  ; word, as an owning array's.
    POP  DE                        ; (E is kept.)
    JR   NZ,.NOOWN                 ; Neither.
    LD   H,B                       ; The payload
    LD   L,C                       ; plus
    BIT  2,D                       ; (a lease's,
    JR   NZ,.LEASE                 ; SY_LEASE, its own)
    INC  HL                        ; two
    INC  HL                        ; is
.LEASE:                        ; HL is the slot word's offset:
    LD   (RO_POWN),HL              ; its offset.
.NOOWN:                        ; RO_POWN is set.
    POP  HL                        ; H is RO_ESC.
.ALIAS:                        ; Through its word.
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
    LD   (RO_ESC),A                ; is in the frame,
    PUSH AF                        ; kept for after the path.
    CALL RO_PATH                   ; Parse the selections; A, carry and zero.
    POP  BC                        ; The root's flag
    LD   HL,RO_ESC                 ; is
    LD   (HL),B                    ; restored.
    POP  HL                        ; The root's offset
    LD   (EX_START),HL             ; is the path's.
    RET                            ; A is the path's type, carry clear.

;@ROUTINE OUT CARRY,ZERO CLOBBERS A,BC,DE,HL,SIGN,PARITY,HALFCARRY
; Consume a name after a dot (RO_NAME) and set carry if it is `length`.

RO_ISLEN:                      ; A name follows the dot.
    CALL RO_NAME                   ; Consume it.
    LD   HL,KW_LEN                 ; The spelling "length",
    LD   B,6                       ; six bytes:
    JP   TK_MATCH                  ; carry if the name is it.

;@ROUTINE IN A OUT A,CARRY,ZERO CLOBBERS SIGN,PARITY,HALFCARRY,BC,DE,HL,IX,IY
; Parse the selections from a call's aggregate result of type A, a path's
; computed start, read-only unless the callee's result is var (RO_CRO):
; its address is in HL. A returns the path's type.

RO_START:                      ; A is the result type.
    LD   (RO_OTYPE),A              ; The path's type.
    LD   A,GA_HELD                 ; Its address is in HL:
    LD   (RO_PKIND),A              ; computed,
    LD   A,(RO_CRO)                ; and read-only
    LD   (RO_PRO),A                ; unless var (RO_FVRES),
    LD   HL,0                      ; with no
    LD   (RO_POWN),HL              ; owner word, nothing pushed nor
    LD   (RO_PPUSH),HL             ; through a handle; fall into RO_PATH.

;@ROUTINE OUT A,CARRY,ZERO CLOBBERS SIGN,PARITY,HALFCARRY,BC,DE,HL,IX,IY
; Parse a path's selections (the reference's suffixes) after its start, the
; place in RO_PLACE: `.field` of a record, `.length` of a string or open
; string, `.capacity` of an open string, `[index]` of an array or string.
; Each step's code is written as it is parsed. A returns the final type.
; RO_PATH is pushed as each step's return, so a step ends with RET or a
; jump to its last callee.

RO_PATH:
    CALL PR_PEEK                   ; Look at the next token.
    LD   HL,RO_PATH                ; Each selection returns
    PUSH HL                        ; to look for the next.
    CALL RO_HSEL                   ; Not through a handle yet.
    CP   TK_DOT                    ; A field, length or capacity?
    JR   Z,.DOT                    ; Select it.
    CP   TK_LBRAC                  ; An index?
    JP   Z,RO_INDEX                ; Select the element or character.
    POP  HL                        ; No selection follows:
    JP   RO_TYPE                   ; the path ends here; A is its type.
.DOT:                          ; Select by name.
    CALL PR_TAKE                   ; Consume the dot.
    LD   A,(RO_OTYPE)              ; The type selected from:
    CP   AG_FIRST                  ; a scalar has no fields,
    JR   C,.NONE                   ; reported at the dot,
    CP   AG_FILE                   ; nor has a File.
    JR   Z,.NONE                   ; (no-such-field).
    CP   AG_VIEW                   ; An open string?
    JR   Z,.STRING                 ; Its length or capacity.
    CP   AG_OPEN                   ; An open array?
    JR   NC,.OPEN                  ; Its length.
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
    CALL RO_ISLEN                  ; Consume the name: is it length?
    JR   C,.LENGTH                 ; The length byte.
    LD   A,(RO_OTYPE)              ; Only an open string
    CP   AG_VIEW                   ; has a capacity.
    JR   NZ,RO_ENAME               ; Raise DG_UNDEF.
    LD   HL,KW_CAP                 ; The spelling "capacity".
    LD   B,8                       ; Its length.
    CALL TK_MATCH                  ; Is the name capacity?
    JR   NC,RO_ENAME               ; Raise DG_UNDEF.
    LD   A,SY_U8                   ; Its low byte, a u8.
.WORD:                         ; A is the type of the view's word:
    LD   HL,(RO_PBASE)             ; the word
    INC  HL                        ; lies above
    INC  HL                        ; its address word,
    LD   (RO_PADD),HL              ; in the frame.
    LD   HL,RO_PKIND               ; A frame
    LD   (HL),GA_FRAME             ; place.
    JR   .FIXED                    ; Read-only.
.LENGTH:                       ; The length is the string's first byte:
    LD   A,(RO_OTYPE)              ; a writable
    CP   AG_VIEW                   ; open string's
    JR   NZ,.BYTE                  ; is
    LD   A,(RO_PRO)                ; set
    OR   A                         ; through STR_SETL
    JR   NZ,.BYTE                  ; (setLength),
    LD   A,4                       ; RO_PPUSH
    LD   (RO_PPUSH),A              ; bit 2;
    LD   A,SY_U8                   ; a u8
    JR   .TYPE                     ; at the same place.
.BYTE:                         ; Any other's
    LD   A,SY_U8                   ; is a u8,
.FIXED:                        ; read-only:
    LD   (RO_PRO),A                ; nonzero,
.TYPE:                         ; at the same place,
    LD   (RO_OTYPE),A              ; type A.
    RET                            ; Continue the path.
.OPEN:                         ; An open array's length:
    LD   HL,(TK_POS)               ; (the dot's offset
    PUSH HL                        ; kept)
    CALL RO_ISLEN                  ; a name, which must be `length`, else
    POP  HL                        ; no-such-field
    LD   A,DG_FIELD                ; at the dot;
    JP   NC,DG_HERE                ; no return.
    LD   A,SY_U16                  ; It is the view's word,
    JR   .WORD                     ; a u16.

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
; the place on by its offset and return to RO_PATH, which RO_PATH pushed,
; to continue the path with its type.

RO_FIELD:
    INC  HL                        ; The record's index follows the kind.
    LD   A,(HL)                    ; Read it,
    PUSH AF                        ; kept across
    CALL RO_NAME                   ; the field's name, consumed.
    POP  AF                        ; The record's index.
    CALL AG_RENT                   ; HL addresses the record's entry in AG_RTAB.
    LD   B,(HL)                    ; B is the first field's index.
    INC  HL                        ; Then the field count.
    LD   D,(HL)                    ; D counts the fields left.
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
    JP   GA_MOVE                   ; the place moves on by it; continue.

; Select an array element or a string character (indexArray,
; indexString), returning to RO_PATH, which RO_PATH pushed. A computed
; base is pushed before its index is parsed, so that the index cannot
; overwrite it; the path's block and the index's position are kept across
; the index, a u16 expression. A constant index into an array is checked
; now, at the index (DG_RANGE), and moves the place on; anything else, an
; open array's constant index too, is checked at run time (GENAGGR.ASM).

RO_INDEX:
    CALL PR_TAKE                   ; Consume the bracket.
    LD   A,(RO_OTYPE)              ; The type indexed:
    CP   AG_FIRST                  ; a scalar
    JR   C,.NOINDEX                ; cannot be indexed,
    CP   AG_FILE                   ; nor can a File
    JR   NZ,.INDEXED               ; (not-indexable).
.NOINDEX:                      ; At the bracket.
    CALL DG_RAISE                  ; Raise the diagnostic below:
    DB   DG_NOIDX                  ; not-indexable.
.INDEXED:                      ; A is the type.
    LD   C,2                       ; Bit 1 of RO_PPUSH: a string.
    CP   AG_VIEW                   ; An open string
    JR   Z,.BASE                   ; is one.
    CP   AG_OPEN                   ; An open array
    JR   NC,.ARRAY                 ; is not.
    CALL AG_DESC                   ; HL addresses the descriptor.
    LD   A,(HL)                    ; Its kind:
    CP   AG_KREC                   ; a record
    JR   Z,.NOINDEX                ; cannot be indexed;
    CP   AG_KSTR                   ; a string
    JR   Z,.BASE                   ; is one,
.ARRAY:                        ; an array
    LD   C,0                       ; is not.
.BASE:                         ; C says which.
    LD   A,(RO_PKIND)              ; Is the base computed?
    CP   GA_HELD                   ; Then its address waits pushed.
    JR   NZ,.KEEP                  ; Otherwise it is addressed later.
    CALL GX_PUSHW                  ; PUSH HL, two bytes pushed; C is kept.
    INC  C                         ; Bit 0 of RO_PPUSH: the base is pushed.
.KEEP:                         ; C holds the two flags.
    LD   A,(RO_PPUSH)              ; Record them,
    AND  $38                       ; with bits 3 to 5
    OR   C                         ; kept (HN_ITEM, HN_DEREF).
    LD   (RO_PPUSH),A              ; Recorded.
    CALL PR_SPOT                   ; The index's first token: its offset
    LD   (RO_IPOS),HL              ; is where an index out of range is reported.
    CALL RO_KEEP                   ; Keep the path's block across the index.
    LD   A,SY_U16                  ; An index is a u16.
    CALL EX_SUB                    ; A and HL describe it.
    CALL EX_STASH                  ; Keep them.
    CALL RO_BACK                   ; The path's block comes back.
    LD   A,(EX_RMETA)              ; The index's metadata:
    AND  SY_TMASK                  ; an exact value
    JR   Z,.EXACT                  ; from 0 to 65535,
    CP   SY_U16+1                  ; or a u8 or u16 (checkIndexType);
    JR   NC,.EINDEX                ; anything else is index-type.
.TYPED:                        ; The index may be used.
    LD   E,TK_RBRAC                ; The closing bracket.
    CALL PR_NEED                   ; Consume it.
    LD   A,(EX_RMETA)              ; D is the index's
    LD   D,A                       ; metadata,
    LD   HL,(EX_RVAL)              ; HL its value.
    LD   A,(RO_PPUSH)              ; A string's characters
    AND  2                         ; are checked against its length
    JP   NZ,GA_CHAR                ; at run time,
    LD   A,(RO_OTYPE)              ; as are
    CP   AG_OPEN                   ; an open array's
    JP   NC,HN_ITEM                ; elements.
    BIT  7,D                       ; SY_KNOWN: a constant index?
    JP   Z,HN_ITEM                 ; No: checked at run time too.
    PUSH HL                        ; Keep it.
    CALL AG_DESC                   ; The array's descriptor (A is its type):
    INC  HL                        ; its element type,
    LD   A,(HL)                    ; the path's next,
    INC  HL                        ; then
    LD   E,(HL)                    ; its
    INC  HL                        ; length,
    LD   D,(HL)                    ; DE.
    POP  HL                        ; The index
    CALL CP_HLDE                   ; must be below the length (the index again, carry kept):
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
.MOVE:                         ; HL is the element's offset:
    JP   GA_MOVE                   ; the place moves on by it; continue.
.EXACT:                        ; An exact index
    LD   A,(EX_RVAL+2)             ; must
    LD   HL,EX_RVAL+3              ; have
    OR   (HL)                      ; no
    INC  HL                        ; bits
    OR   (HL)                      ; above
    JR   Z,.TYPED                  ; sixteen.
.EINDEX:                       ; An index of the wrong type or range:
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

;@ROUTINE IN HL OUT A,CARRY,ZERO CLOBBERS SIGN,PARITY,HALFCARRY,BC,DE,HL,IX,IY
; Parse a call to routine HL, RO_FIND's record, whose name has been read, as
; the reference's call does (RO_ARGS); only a routine declared forward may
; call itself (DG_UNMET otherwise). A returns the result type, zero for
; none. A call to main is refused for now (DG_NYI).

RO_CALL:
    LD   A,H                       ; Is the callee
    OR   L                         ; main?
    JP   Z,TR_OPER                 ; Refused for now.
    LD   DE,(RO_CUR)               ; The routine being compiled:
    CALL CP_HLDE                   ; does it call itself?
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
    CALL WD_GET                    ; DE is the first parameter's record, B the number
    LD   B,(HL)                    ; of them.
    INC  HL                        ; The record from RO_RTYPE
    PUSH HL                        ; is read when the call closes.
    LD   HL,RO_PTYPE               ; The first one's type
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
; types, a byte apart. A returns the result type, zero for none.

RO_SVC:
    PUSH HL                        ; The record, read when the call closes.
    LD   DE,RO_RARGS-RO_RTYPE+1    ; After the argument bytes
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
    LD   A,TK_LPAR                 ; The opening parenthesis first.
.NEXT:                         ; A is the separator before an argument.
    PUSH HL                        ; Keep the types
    PUSH DE                        ; and their spacing and count.
    LD   E,A                       ; Consume
    CALL PR_NEED                   ; the separator.
    POP  DE                        ; E parameters are left,
    POP  HL                        ; the next one's type at HL.
    LD   A,E                       ; Any left?
    OR   A                         ; Zero when every one is parsed.
    JP   Z,.CLOSE                  ; Then the call closes.
    PUSH HL                        ; Keep the types
    PUSH DE                        ; and the count across the argument,
    LD   A,(HL)                    ; and the parameter's type
    PUSH AF                        ; across the peek.
    CALL PR_PEEK                   ; Does the call close
    CP   TK_RPAR                   ; where an argument is due?
    JP   Z,.ARITY                  ; Too few arguments.
    POP  AF                        ; The parameter's type.
    CP   AG_FIRST                  ; An aggregate?
    JR   NC,.AGGR                  ; Its address is passed.
    CALL RO_ARG                    ; D, E and HL describe the argument.
    CALL GX_TOREG                  ; The value in the registers at type E.
    LD   A,E                       ; A word
    CALL GX_SIZE                   ; is pushed as it is;
    JP   Z,.PUSH                   ; a long's high word first,
    JP   NC,.OWNER                 ; PUSH DE, then the low word,
    CALL GX_ZEXT                   ; and a byte widens, LD L,A, LD H,0.
    JP   .PUSH                     ; Push the word.
.AGGR:                         ; A is the parameter's type, AG_VAR for var.
    LD   B,A                       ; Keep it.
    AND  $7F                       ; A handle's
    CALL PL_ISHND                  ; value or
    LD   A,B                       ; slot-holder's
    JR   C,.HANDLE                 ; location.
    AND  $7F                       ; Without AG_VAR:
    CP   AG_FILE                   ; a File?
    JR   Z,.FILE                   ; Its value is passed.
    CP   AG_OPEN                   ; Below the views,
    JR   C,.ADDRESS                ; an aggregate's address.
    LD   A,B                       ; A view:
    CALL RO_VIEW                   ; its word is pushed.
    JR   .PUSH                     ; Then the address.
.HANDLE:                       ; An owning handle:
    CALL HN_ARG                    ; its value in HL, linked,
    JR   .PUSH                     ; pushed.
.FILE:                         ; A File argument.
    CALL RO_FVAL                   ; Its value in DEHL.
    JR   .OWNER                    ; PUSH DE, the high word, then the low.
.ADDRESS:                      ; An aggregate of type A, B with AG_VAR.
    PUSH BC                        ; Keep the parameter's type.
    CALL PR_SPOT                   ; The argument's start, HL:
    CP   TK_LPAR                   ; parenthesized,
    JP   Z,TR_OPER                 ; it waits;
    CP   TK_NAME                   ; a path begins with
    JR   NZ,.VALUE                 ; a name
    PUSH HL                        ; (the start
    CALL TK_ISID                   ; kept) other than `id`;
    POP  HL                        ; any other
    JR   NC,.PATH                  ; value
.VALUE:                        ; is parsed
    PUSH HL                        ; whole
    XOR  A                         ; and is
    CALL EX_RUN                    ; no
    POP  HL                        ; aggregate
    LD   (EX_START),HL             ; (type-mismatch
    JP   EX_EFIT                   ; at its start).
.PATH:                         ; A path:
    CALL RO_PART                   ; A is the argument's type:
    POP  BC                        ; an owning
    CALL PL_ISHND                  ; handle
    JR   NC,.RECORD                ; lends
    CALL HN_LEASA                  ; its record (a lease),
    JR   .PUSH                     ; HL, pushed.
.RECORD:                       ; Otherwise an aggregate:
    PUSH BC                        ; (B kept)
    CALL RO_AGGT                   ; HL its address.
    POP  BC                        ; B is the parameter's,
    LD   C,A                       ; C the argument's:
    LD   A,B                       ; the types,
    AND  $7F                       ; less AG_VAR,
    CP   C                         ; must be the same,
    JP   NZ,EX_EFIT                ; else DG_CLASH at the argument;
    LD   A,C                       ; then through an
    CALL HN_ARGCK                  ; identifier, a value's
    CALL HN_COPY                   ; copy.
    BIT  7,B                       ; A var parameter
    JR   Z,.PUSH                   ; takes
    CALL RO_WRITE                  ; only a writable argument;
    LD   A,C                       ; and a record or an owning
    CALL PL_OWORD                  ; array its owner word
    JR   NZ,.PUSH                  ; first: the root's,
    LD   HL,(RO_POWN)              ; a var record
    LD   A,H                       ; parameter's,
    OR   L                         ; LD E,(IX+n),
    JR   Z,.NOOWN                  ; LD D,(IX+n+1),
    CALL GX_FLDDE                  ; HL kept (ixWord),
    JR   .OWNER                    ; or
.NOOWN:                        ; none: LD DE,0
    CALL HN_DEZ                    ; and PUSH DE;
    JR   .PUSH                     ; then
.OWNER:                        ; PUSH DE,
    LD   A,$D5                     ; two bytes
    CALL GX_PUSHA                  ; pushed.
.PUSH:                         ; The argument is in HL.
    CALL GX_PUSHW                  ; PUSH HL, pushed until the call returns.
    POP  DE                        ; The spacing and count.
    POP  HL                        ; The parameter's type:
    LD   C,D                       ; the next
    LD   B,0                       ; is D bytes
    ADD  HL,BC                     ; on.
    DEC  E                         ; One fewer to parse;
    LD   A,TK_COMMA                ; unless that was the last,
    JP   NZ,.NEXT                  ; a comma comes before the next.
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
    PUSH AF                        ; are kept too,
    AND  RO_FVRES                  ; and whether
    XOR  RO_FVRES                  ; its result
    LD   (RO_CRO),A                ; is read-only.
    INC  HL                        ; Its ordinal.
    CALL WD_GET                    ; DE is the ordinal, the call's target. Its need follows.
    PUSH HL                        ; Keep the place.
    CALL EM_OP                     ; CALL nn,
    DB   $CD                       ; the callee.
    EX   DE,HL                     ; HL is the ordinal;
    LD   DE,0                      ; with no addend,
    CALL EM_REF                    ; refer to it.
    POP  HL                        ; The need,
    CALL WD_GET                    ; low byte and high byte. Then the argument bytes,
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
.ARITY:                        ; Too few or too many arguments.
    CALL DG_RAISE                  ; Abandon the build, at the token:
    DB   DG_ARITY                  ; arity.

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
    CALL HN_RELAY                  ; To the exit, owners freed, A the code.
    LD   A,RG_EXIT                 ; The exit
    JR   .PEND                     ; is pending.
.TRAP:                         ; A handler follows.
    LD   A,(EM_TEMPS)              ; The temporaries
    LD   (RO_KEPT),A               ; beneath the call.
    CALL EM_LNEW                   ; A is the handler's label.
.JUMP:                         ; A is the failure's label.
    LD   C,$DA                     ; JP C,
    CALL EM_JUMP                   ; to it on failure; A is kept.
.PEND:                         ; A is the failure's label:
    OR   $80                       ; the label, marked,
    LD   (RO_PEND),A               ; is pending.
    RET                            ; The expression goes on.
.LOST:                         ; A is DG_LEAK.
    LD   HL,(RO_CALLP)             ; The callee's name,
    CALL DG_WORD                   ; at the call, is argument 1.
.AT:                           ; A is the diagnostic.
    LD   HL,(RO_CALLP)             ; At the call.
    JP   DG_HERE                   ; No return.


;@ROUTINE CLOBBERS A,CARRY,ZERO,SIGN,PARITY,HALFCARRY
; Require the path just parsed to be writable (RO_PRO zero): a read-only
; one, passed where a var parameter or view wants it, raises DG_CONST at
; its start (EX_START).

RO_WRITE:
    LD   A,(RO_PRO)                ; A read-only path
    OR   A                         ; cannot be passed:
    RET  Z                         ; this one can.
    LD   A,DG_CONST                ; Not-writable,
    JP   EX_EVAL                   ; at the path.

;@ROUTINE IN A CLOBBERS A,BC,DE,HL,IX,IY,CARRY,ZERO,SIGN,PARITY,HALFCARRY
; A view argument of type A (argument): AG_VIEW for a string, an open
; array's ID (AG_OPEN plus its element's) or AG_BUF, the services' u8[],
; each with AG_VAR for var. A string literal, for a string[]
; that is not var: LD DE,its length, PUSH DE, LD HL,literal. Otherwise a
; path, rooted at a variable or constant (not a call), and writable for a
; var view (DG_CONST): a string's, its address into HL, then its
; capacity, LD DE,n for a declared string or the word of an open string
; passed on, and PUSH DE; an array's of the view's element type, its
; address and LD DE,its length, or an open array's of that type, passed
; on with its word, PUSH DE. The address is pushed by the caller. A
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
    CALL GA_LDDE                   ; LD DE,length,
    CALL .PUSHDE                   ; pushed (BC is kept).
    JP   GA_LIT                    ; LD HL,literal; return.
.PATH:                         ; A path names the object.
    CALL RO_NAME                   ; Its root's name.
    CALL RO_FIND                   ; A routine
    JR   Z,.CLASS                  ; is no variable: wrong-class.
    CALL RO_NAMED                  ; Parse the path; A is its type.
    POP  BC                        ; B is the view's type.
    CALL HN_ARGCK                  ; (not through an identifier)
    LD   C,A                       ; C is the path's.
    BIT  7,B                       ; A var view takes
    CALL NZ,RO_WRITE               ; only a writable path; any other, any.
    RES  7,B                       ; The view without var:
    LD   A,B                       ; a string's
    CP   AG_VIEW                   ; or an array's?
    LD   A,C                       ; The path's type.
    JR   NZ,.BUFFER                ; An array.
    CP   AG_VIEW                   ; An open string passed on?
    JR   Z,.PASS                   ; Its capacity word.
    CP   AG_FIRST                  ; A scalar
    JR   C,RO_EFIT                 ; is no string: DG_CLASH at the path.
    CALL AG_DESC                   ; HL addresses the descriptor.
    LD   A,(HL)                    ; Its kind
    CP   AG_KSTR                   ; must be a string,
    JR   NZ,RO_EFIT                ; else DG_CLASH at the path.
    INC  HL                        ; Its capacity
    LD   L,(HL)                    ; is
    LD   H,0                       ; HL.
    JR   .WORD                     ; Pass it.
.BUFFER:                       ; A is the path's type, B the view's.
    LD   E,A                       ; Keep it.
    LD   A,B                       ; The services' u8[]
    CP   AG_BUF                    ; is
    JR   NZ,.OPEN                  ; an open
    LD   B,AG_OPEN+SY_U8           ; array of u8.
.OPEN:                         ; B is an open array's ID.
    LD   A,E                       ; The path's type:
    CP   B                         ; the same open array
    JR   Z,.PASS                   ; passes its word on;
    CP   AG_FIRST                  ; a scalar,
    JR   C,RO_EFIT                 ; a File
    CP   AG_OPEN                   ; or a view
    JR   NC,RO_EFIT                ; is no array: DG_CLASH at the path.
    CALL AG_DESC                   ; HL addresses the descriptor.
    LD   A,(HL)                    ; Its kind
    CP   AG_KARR                   ; must be an array
    JR   NZ,RO_EFIT                ; (DG_CLASH),
    INC  HL                        ; and its element
    LD   A,B                       ; the view's
    SUB  AG_OPEN                   ; element
    CP   (HL)                      ; type (DG_CLASH).
    JR   NZ,RO_EFIT                ; Its length
    INC  HL                        ; is
    LD   E,(HL)                    ; the
    INC  HL                        ; view's
    LD   D,(HL)                    ; word,
    EX   DE,HL                     ; HL.
.WORD:                         ; HL is the view's word.
    PUSH HL                        ; Keep it.
    CALL GA_ADDR                   ; The address first,
    CALL HN_COPY                   ; a copy through an identifier.
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
    CALL GX_FLDDE                  ; into DE, HL kept (ixWord). Append it.
.PUSHDE:                       ; The view's word is in DE:
    JP   HN_PSHDE                  ; PUSH DE, counted; return.
.CLASS:                        ; A routine's name where a variable is due.
    CALL DG_RNAME                  ; Raise the diagnostic below, named:
    DB   DG_CLASS                  ; wrong-class.

;@ROUTINE NORETURN
; Raise DG_CLASH at the path or value just parsed (EX_START): EX_EFIT,
; within a relative jump of the routines around it.

RO_EFIT:
    JP   EX_EFIT                   ; No return.

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

;@ROUTINE IN HL CLOBBERS A,HL,CARRY,ZERO,SIGN,PARITY,HALFCARRY
; console or printer, its predeclared entry at HL (RO_LIB), into DEHL:
; LD HL,n, LD DE,0.

RO_FCON:                       ; HL is the entry.
    INC  HL                        ; Its value,
    LD   L,(HL)                    ; the runtime's
    LD   H,0                       ; fixed File:
    CALL EM_OP                     ; LD HL,n,
    DB   $21                       ; the opcode,
    CALL EM_WORD                   ; and n;
    CALL EM_SEQX                   ; then LD DE,0, the high word,
    DB   3,$11,0,0                 ; and return: DEHL is the File.

;@ROUTINE CLOBBERS A,BC,DE,HL,IX,IY,CARRY,ZERO,SIGN,PARITY,HALFCARRY
; Parse a File value and generate it into DEHL (the reference's expression
; and toRegisters for a File): console or printer, LD HL,n and LD DE,0; a
; call to a service or a routine whose result is a File; or a File path, a
; variable, parameter, field or element, loaded at its place (GA_LDF).
; Anything else raises DG_CLASH: the native compiler takes a File only as
; a name, a path or such a call.

RO_FVAL:
    CALL PR_SPOT                   ; Its start,
    LD   (EX_START),HL             ; where a fault is reported,
    PUSH HL                        ; kept across it
    CALL .VALUE                    ; (.BACK),
    POP  HL                        ; dropped.
    RET                            ; Done.
.VALUE:                        ; The value:
    CALL PR_TAKE                   ; a name begins it;
    CP   TK_LPAR                   ; a parenthesized one
    JP   Z,TR_OPER                 ; waits (DG_NYI);
    CP   TK_NAME                   ; anything else is
    JR   NZ,.ETYPE                 ; no File value (DG_CLASH).
    CALL RO_LIB                    ; A predeclared name?
    JR   NC,.VARIABLE              ; No: a variable.
    JP   P,.SERVICE                ; Not a constant: a service.
    CP   SY_KNOWN+AG_FILE          ; The constant must be a File,
    JR   NZ,.ETYPE                 ; else DG_CLASH:
    JR   RO_FCON                   ; DEHL; return.
.SERVICE:                      ; HL is the service's payload.
    CALL RO_SVC                    ; A is its result type,
    CALL .BACK                     ; its start again;
.FILE:                         ; or the variable's.
    CP   AG_FILE                   ; A File
    RET  Z                         ; is in DEHL, or to be loaded.
.ETYPE:                        ; Anything else
    LD   A,DG_CLASH                ; raises DG_CLASH
    JP   EX_EVAL                   ; at its start.
.VARIABLE:                     ; A routine's call,
    CALL RO_FIND                   ; its result
    JR   NZ,.PATH                  ; a File
    CALL HN_VOIDQ                  ; (no-value without one)
    CALL RO_CALL                   ; in DEHL,
    CALL .BACK                     ; its start again;
    CP   AG_FILE                   ; a path
    JR   Z,.FILE                   ; from another
    CP   AG_FIRST                  ; aggregate result
    JR   C,.ETYPE                  ; waits (DG_NYI);
    JP   TR_OPER                   ; or
.PATH:                         ; a path, or nothing:
    CALL RO_NAMED                  ; parsed, A its type.
    CALL .FILE                     ; It must be a File,
    JP   GA_LDF                    ; loaded at its place; return.
.BACK:                         ; The arguments moved EX_START:
    LD   HL,4                      ; the value's start,
    ADD  HL,SP                     ; kept above
    LD   E,(HL)                    ; .VALUE's
    INC  HL                        ; return
    LD   D,(HL)                    ; and this one's,
    LD   (EX_START),DE             ; is it again.
    RET                            ; A is kept.

;@ROUTINE OUT A,CARRY,ZERO CLOBBERS SIGN,PARITY,HALFCARRY,BC,DE,HL,IX,IY
; Parse a path or a call whose value is an aggregate, and generate its
; address into HL. A returns its type.

RO_AGGR:
    CALL RO_PART                   ; Parse it; A is its type:
    CALL PL_ISHND                  ; a handle's value
    JP   C,TR_OPER                 ; waits (DG_NYI).

;@ROUTINE IN A OUT A,CARRY,ZERO CLOBBERS SIGN,PARITY,HALFCARRY,BC,DE,HL,IX,IY
; RO_AGGR after its path, of type A, is parsed and is no handle.

RO_AGGT:                       ; A is the path's type.
    CP   AG_FIRST                  ; It must be an aggregate:
    JP   C,RO_EFIT                 ; `.length` and elements are not.
    CALL GA_ADDR                   ; Its address into HL;
    JR   RO_TYPE                   ; A is its type.

;@ROUTINE OUT A,CARRY,ZERO CLOBBERS SIGN,PARITY,HALFCARRY,BC,DE,HL,IX,IY
; Parse a path rooted at the next NAME, a symbol, or at a call's
; aggregate result, which must be one (DG_CLASH), leaving its place in
; RO_PLACE and its first token's offset in EX_START. A returns its type.

RO_PART:
    CALL RO_NAME                   ; A path starts with a name.
    CALL RO_FIND                   ; Is it a routine?
    JR   Z,.CALL                   ; Otherwise a symbol roots it,
    JP   RO_NAMED                  ; its type A; return.
.CALL:                         ; A routine, HL.
    LD   DE,(TK_POS)               ; The call's offset,
    PUSH DE                        ; kept across it.
    CALL RO_CALL                   ; A is the result type, HL the address.
    CP   AG_FIRST                  ; It must be an aggregate.
    JP   C,EX_ETYPE                ; Raise DG_CLASH.
    CALL RO_START                  ; Parse the rest of the path,
    LD   HL,RO_ESC                 ; whose root is the call's,
    LD   (HL),0                    ; whatever path an index read.
    POP  HL                        ; The call's offset
    LD   (EX_START),HL             ; is the value's.
    RET                            ; A is the type.

;@ROUTINE IN A OUT A,CARRY,ZERO CLOBBERS SIGN,PARITY,HALFCARRY,BC,DE,HL
; Make the scalar path of type A an expression value (loadDesignator); an
; aggregate is no value here (DG_CLASH). A returns its type.

RO_LOAD:
    CALL PL_ISHND                  ; A handle's value is compared
    JP   C,HN_IDLD                 ; (HN_IDLD), as is a File's
    CP   AG_FILE                   ; (HN_FLD);
    JP   Z,HN_FLD                  ; neither is a scalar.
    CP   AG_FIRST                  ; An aggregate is not a scalar value:
    JP   NC,RO_EFIT                ; DG_CLASH at the path.
    CALL GA_LOAD                   ; Load it into A or HL.

;@ROUTINE OUT A,CARRY,ZERO CLOBBERS SIGN,PARITY,HALFCARRY
; Return the path's type, RO_OTYPE, in A with carry clear: the end that
; RO_PATH, RO_AGGR and RO_LOAD share.

RO_TYPE:
    LD   A,(RO_OTYPE)              ; The path's type.
    OR   A                         ; Carry clear.
    RET                            ; A is the type.

;@ROUTINE IN HL OUT A,CARRY,ZERO CLOBBERS SIGN,PARITY,HALFCARRY,BC,DE,HL,IX,IY
; The expression parser's hook for a routine name, read already: parse
; the call to routine HL and make its result, or a scalar selected from an
; aggregate result, the expression's value of type A; a File's or an
; identifier's, in DEHL, is compared (HN_EQ). RO_VALUE does the same for
; a call already parsed, its result type A: a service's.

RO_FUNC:
    CALL HN_VOIDQ                  ; A result (no-value at its name),
    CALL RO_CALL                   ; called: A is the result type.
RO_VALUE:                      ; A call's result type is A, never zero.
    CP   AG_FIRST                  ; Is the result an aggregate?
    RET  C                         ; No: A is the scalar result type.
    CP   AG_FILE                   ; A File, in DEHL,
    JP   Z,HN_EQ                   ; is compared,
    CALL PL_ISHND                  ; as is
    JR   NC,.PATH                  ; an
    BIT  1,A                       ; identifier
    JP   NZ,HN_EQ                  ; in DEHL.
.PATH:                         ; An aggregate:
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
