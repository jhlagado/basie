;==========================================================================
;  Calls, services and aggregate paths
;==========================================================================
;
;  Parse calls to source routines and generate their code (RO_CALL), and
;  parse the access paths into aggregates: record fields, array elements,
;  string length and characters, and assignment to a path. Each is checked
;  against the routine and parameter tables (ROUTINES.ASM) and the
;  aggregate types (AGGR.ASM). A path's root generates its address
;  (RO_ROOT); the selections after it still reach the transcript and are
;  refused (TRANSCR.ASM, 65.4 h). The grammar actions call in for
;  statements; the expression parser enters through RO_FUNC, RO_OBJ and
;  RO_CAUSE when a name in an expression is a routine, an aggregate or an
;  error constant. The predefined services are refused where they are
;  named, until services are compiled (65.4 i).
;
;  Principal entries:
;    RO_CALL   parse and generate a call to a source routine
;    RO_AGGR   parse a path or call whose value is an aggregate
;    RO_LET    parse an assignment to an aggregate path
;    RO_FUNC   expression hook: a routine call as a value
;    RO_OBJ    expression hook: a scalar selected from an aggregate
;    RO_CAUSE  expression hook: an error constant's code
;    RO_EMITW  write an operand word of a structural operation
;
;  A path generates its root's address into HL and refines it with
;  OP_FIELD, OP_INDEX or a character operation; RO_LOAD turns a scalar path
;  into a value.

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

;@ROUTINE IN HL OUT A,CARRY,ZERO CLOBBERS SIGN,PARITY,HALFCARRY,B,DE,HL
; Write HL to the transcript as a little-endian operand word. Structural
; operands are written with their operation, whatever EX_EMITW's
; constant-folding flag says.

RO_EMITW:
    LD   A,L                       ; Low byte first.
    CALL TR_PUTHL                  ; Write it, keeping HL.
    LD   A,H                       ; Then the high byte.
    JP   TR_PUT                    ; Write it and return.

;@ROUTINE OUT A,CARRY,ZERO CLOBBERS SIGN,PARITY,HALFCARRY,BC,DE,HL
; Generate the address of the current NAME, the root of an aggregate path,
; into HL, as the reference's emitAddress does: LD HL,nn referring to the
; blob of a program variable or an aggregate constant, or the address
; word of a parameter, which holds its argument's address (an alias). A
; returns the exact aggregate type, also kept in RO_OTYPE; an open
; string's capacity slot goes to RO_VCAP. A local is never an aggregate.

RO_ROOT:
    CALL RO_SYM                    ; A is the type, D the class, BC the payload.
    LD   (RO_OTYPE),A              ; Keep the type for the return.
    CP   AG_VIEW                   ; Is it an open-string parameter?
    JR   NZ,.CLASS                 ; Other types have their capacity declared.
    LD   A,C                       ; The parameter's offset.
    ADD  A,2                       ; The capacity word lies above the address.
    LD   (RO_VCAP),A               ; OP_VLEN, OP_VCHAR and OP_VIEW carry it.
.CLASS:                        ; Choose the root by storage class.
    LD   A,D                       ; The class byte.
    AND  SY_CMASK                  ; Keep the storage class.
    CP   SY_PARAM                  ; A parameter?
    JR   Z,.PARAM                  ; Its frame word is the address.
    LD   A,$21                     ; LD HL,nn: the blob's address.
    CALL GX_ABS                    ; Refer to blob BC.
    JR   RO_TYPED                  ; Return the type.
.PARAM:                        ; BC is the parameter's offset.
    LD   H,B                       ; HL is
    LD   L,C                       ; the offset.
    LD   A,SY_U16                  ; The address is a word:
    CALL GX_FLOAD                  ; LD L,(IX+d), LD H,(IX+d+1).

;@ROUTINE OUT A,CARRY,ZERO CLOBBERS SIGN,PARITY,HALFCARRY
; Return the path's type from RO_OTYPE, with carry clear.

RO_TYPED:
    LD   A,(RO_OTYPE)              ; The root's exact type.
    OR   A                         ; Carry clear.
    RET                            ; A is the type.

;@ROUTINE IN A OUT A,D,CARRY,ZERO CLOBBERS SIGN,PARITY,HALFCARRY,BC,E,HL,IX,IY
; Parse a path's suffix of `.field`, `[index]` and `.length` after a root
; of type A whose address is on the evaluation stack, writing the checked
; operations. A returns the final type; D returns zero for an address, or
; one when `.length` has produced a scalar value.

RO_PATH:
    LD   D,0                       ; The path is an address so far.

;@ROUTINE IN A OUT A,D,CARRY,ZERO CLOBBERS SIGN,PARITY,HALFCARRY,BC,E,HL,IX,IY
; Continue a path whose current type is A: dispatch on the next token.

RO_SEL:
    PUSH AF                        ; Keep the current type.
    CALL PR_PEEK                   ; Look at the next token.
    CP   TK_DOT                    ; A field or length?
    JR   Z,.DOT                    ; Select it.
    CP   TK_LBRAC                  ; An index?
    JP   Z,RO_INDEX                ; Select the element or character.
    POP  AF                        ; The path ends here: its type.
    LD   D,0                       ; It is an address.
    OR   A                         ; Carry clear.
    RET                            ; A is the type.
.DOT:                          ; Select a field or the length.
    POP  AF                        ; Recover the type.
    PUSH AF                        ; Keep it across the token reads.
.FIELD:                        ; Read the selected name.
    CALL PR_TAKE                   ; Consume the dot.
    LD   E,TK_NAME                 ; A name must follow it.
    CALL PR_NEED                   ; Consume the name.
    POP  AF                        ; Recover the type.
    PUSH AF                        ; Keep it for the field search.
    CP   AG_FIRST                  ; The flags are overwritten: no scalar check.
    CP   AG_VIEW                   ; Is it an open string?
    JR   Z,.STRFIELD               ; Its one field is length.
    CALL AG_DESC                   ; HL addresses the type's descriptor.
    LD   A,(HL)                    ; Read its kind.
    CP   AG_KSTR                   ; Is it a bounded string?
    JR   NZ,RO_FIELD               ; Otherwise look for a record field.
.STRFIELD:                     ; A string's only field is `length`.
    LD   HL,KW_LEN                 ; The spelling "length".
    LD   B,6                       ; Its length.
    CALL TK_MATCH                  ; Is the name length?
    JP   NC,RO_EPATH               ; Raise DG_CLASH.
    LD   A,(RO_OTYPE)              ; Recover the string's type.
    CP   AG_VIEW                   ; Is it an open string?
    JR   Z,.OPENSTR                ; Its capacity comes from the frame.
    CALL AG_DESC                   ; HL addresses the descriptor.
    INC  HL                        ; The capacity follows the kind.
    LD   C,(HL)                    ; Read the capacity for OP_LEN's check.
    LD   A,OP_LEN                  ; The length of a declared string.
    JR   .LENGTH                   ; Write it.
.OPENSTR:                      ; The length of an open string.
    LD   A,(RO_VCAP)               ; The slot of its capacity byte.
    LD   C,A                       ; OP_VLEN's operand.
    LD   A,OP_VLEN                 ; The length of an open string.
.LENGTH:                       ; Write the length operation.
    CALL PR_EMITC                  ; Write the operation and C.
    LD   HL,(TK_POS)               ; The offset of the name `length`.
    CALL RO_EMITW                  ; Its traps report it.
    POP  AF                        ; Discard the string's type.
    LD   A,SY_U8                   ; The length is a u8 value.
    LD   D,1                       ; The path now carries a value.
    OR   A                         ; Carry clear.
    RET                            ; A is u8, D is one.

; Raise DG_UNDEF: the selected name is no field of the record.

RO_ENAME:
    CALL DG_RAISE                  ; Raise the diagnostic below.
    DB   DG_UNDEF                  ; The name is undefined.

; Select a record field by name: write OP_FIELD with its offset and
; continue the path with the field's type. The record's type is pushed.

RO_FIELD:
    POP  AF                        ; Recover the type.
    CALL AG_DESC                   ; HL addresses its descriptor.
    LD   A,(HL)                    ; Read its kind.
    CP   AG_KREC                   ; Is it a record?
    JP   NZ,EX_ETYPE               ; Raise DG_CLASH.
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
.LOOP:                         ; Compare one field's name.
    LD   A,D                       ; Any fields left?
    OR   A                         ; Test the count.
    JR   Z,RO_ENAME                ; Raise DG_UNDEF.
    LD   A,B                       ; Select field B.
    CALL AG_FIELD                  ; HL addresses it; the name comes first.
    PUSH DE                        ; TK_SAME clobbers the count in D.
    CALL TK_SAME                   ; Does its spelling match the token?
    POP  DE                        ; Recover the count.
    JR   C,.FOUND                  ; Select this field.
    INC  B                         ; Next field.
    DEC  D                         ; One fewer.
    JR   .LOOP                     ; Continue through the record.
.FOUND:                        ; Write the field's selection.
    LD   A,B                       ; Select field B again.
    CALL AG_FIELD                  ; HL addresses it.
    LD   DE,AG_FTYPE               ; Skip the field's name.
    ADD  HL,DE                     ; HL addresses the field's type.
    LD   A,(HL)                    ; Read the field's type.
    INC  HL                        ; Its offset follows.
    LD   E,(HL)                    ; Low byte.
    INC  HL                        ; High byte.
    LD   D,(HL)                    ; DE is the field's offset.
    OR   A                         ; Clear carry.
    PUSH AF                        ; Keep the field's type.
    LD   (RO_OPOS),DE              ; Keep the offset across TR_OPER.
    LD   A,OP_FIELD                ; Add the field's offset.
    CALL TR_OPER                   ; Write the operation.
    LD   HL,(RO_OPOS)              ; The offset.
    CALL RO_EMITW                  ; Write it.
    POP  AF                        ; The field's type.
    JP   RO_SEL                    ; Continue the path from it.

; Select an array element or a string character: parse the u16 index,
; check it and write OP_INDEX, OP_CHAR or OP_VCHAR. The type is pushed.

RO_INDEX:
    POP  BC                        ; Recover the type.
    LD   A,(RO_VCAP)               ; The index may hold another open string.
    PUSH AF                        ; So keep this path's capacity slot.
    PUSH BC                        ; Keep the type too, below the slot.
.OPERAND:                      ; Parse the index expression.
    LD   HL,(TK_POS)               ; The offset of the bracket.
    PUSH HL                        ; Traps report it.
    CALL PR_TAKE                   ; Consume the bracket.
    LD   A,(EX_WANT)               ; Keep the enclosing expression's wanted type.
    PUSH AF                        ; Push it.
    LD   A,SY_U16                  ; An index is a u16.
    LD   (EX_WANT),A               ; Ask for one.
    CALL EX_PARSE                  ; A and HL describe the index.
    LD   (EX_RMETA),A              ; Keep the index's metadata.
    LD   (EX_RVAL),HL              ; Keep its constant value.
    POP  AF                        ; Recover the enclosing wanted type.
    LD   (EX_WANT),A               ; Restore it.
    LD   A,(EX_RMETA)              ; The index's metadata.
    AND  SY_TMASK                  ; Keep its type.
    CP   SY_BOOL                   ; A boolean is no index.
    JP   Z,RO_EIDX                 ; Raise DG_CLASH.
    LD   E,TK_RBRAC                ; The closing bracket.
    CALL PR_NEED                   ; Consume it.
    POP  HL                        ; The bracket's offset.
    LD   (RO_DPOS),HL              ; The operation carries it.
    POP  AF                        ; Recover the type.
    LD   E,A                       ; Keep it in E.
    POP  BC                        ; Recover this path's capacity slot.
    LD   A,B                       ; It came back in B.
    LD   (RO_VCAP),A               ; Restore it.
    LD   A,E                       ; The type being indexed.
    CP   AG_FIRST                  ; A scalar cannot be indexed.
    JP   C,EX_ETYPE                ; Raise DG_CLASH.
    PUSH AF                        ; Keep the type.
    CP   AG_VIEW                   ; Is it an open string?
    JR   Z,RO_OSIDX                ; Index it by its frame capacity.
    CALL AG_DESC                   ; HL addresses the descriptor.
    LD   A,(HL)                    ; Read its kind.
    CP   AG_KSTR                   ; Is it a bounded string?
    JR   Z,RO_CHAR                 ; Index its characters.
    CP   AG_KARR                   ; Only arrays remain indexable.
    JP   NZ,RO_EPATH               ; Raise DG_CLASH for a record.
    INC  HL                        ; The element type follows the kind.
    LD   A,(HL)                    ; Read the element type.
    LD   (RO_OTYPE),A              ; Keep it for the size.
    INC  HL                        ; Then the element count.
    LD   C,(HL)                    ; Read the element count's low byte.
    INC  HL                        ; High byte.
    LD   B,(HL)                    ; BC is the element count.
    LD   A,(EX_RMETA)              ; Is the index a known constant?
    AND  SY_KNOWN                  ; Test its metadata.
    JR   Z,RO_ITEM                 ; A run-time index is checked at run time.
    LD   HL,(EX_RVAL)              ; The constant index.
    OR   A                         ; Clear carry for the comparison.
    SBC  HL,BC                     ; Is it below the count?
    JR   NC,RO_ERNG                ; Report it out of range now.

; Write OP_INDEX (count, element size, offset) and continue the path with
; the element type. The array's type is pushed.

RO_ITEM:
    LD   (RO_OPOS),BC              ; Keep the element count.
    LD   A,(RO_OTYPE)              ; The element type.
    CALL AG_SIZE                   ; HL is its size.
    LD   (RO_OSIZE),HL             ; The stride.
    LD   A,OP_INDEX                ; Address the element.
    CALL TR_OPER                   ; Write the operation.
    LD   HL,(RO_OPOS)              ; The element count.
    CALL RO_EMITW                  ; Write it.
    LD   HL,(RO_OSIZE)             ; The stride.
    CALL RO_EMITW                  ; Write it.
    LD   HL,(RO_DPOS)              ; The bracket's offset.
    CALL RO_EMITW                  ; Write it.
    POP  AF                        ; The array's type.
    CALL AG_DESC                   ; HL addresses its descriptor.
    INC  HL                        ; The element type follows the kind.
    LD   A,(HL)                    ; Read it.
    JP   RO_SEL                    ; Continue the path from the element.

; Write OP_CHAR (capacity, offset) for a bounded string at descriptor HL.

RO_CHAR:
    INC  HL                        ; The capacity follows the kind.
    LD   C,(HL)                    ; Read the capacity for OP_CHAR's check.
    LD   A,OP_CHAR                 ; Address a declared string's character.
    JR   RO_IDXOP                  ; Write it.

; Write OP_VCHAR (capacity slot, offset) for an open string.

RO_OSIDX:
    LD   A,(RO_VCAP)               ; The slot of its capacity byte.
    LD   C,A                       ; OP_VCHAR's operand.
    LD   A,OP_VCHAR                ; Address an open string's character.

; Write character operation A with operand C and the offset, and continue
; the path with a u8 address. The string's type is pushed.

RO_IDXOP:
    CALL PR_EMITC                  ; Write the operation and C.
    LD   HL,(RO_DPOS)              ; The bracket's offset.
    CALL RO_EMITW                  ; Write it.
    POP  AF                        ; Discard the string's type.
    LD   A,SY_U8                   ; The character is a u8.
    JP   RO_SEL                    ; Continue the path from it.

; Raise DG_CLASH for a boolean index, discarding RO_INDEX's three pushes.

RO_EIDX:
    POP  HL                        ; The bracket's offset.
    POP  AF                        ; The type.
    POP  BC                        ; The capacity slot.
    JP   EX_ETYPE                  ; Raise DG_CLASH.

; A constant index is out of range: raise DG_RANGE at the bracket, unless
; the expression is parsed quietly, when the run-time check remains.

RO_ERNG:
    LD   A,(EX_QUIET)              ; Is the parse quiet?
    OR   A                         ; Test it.
    JR   NZ,RO_ITEM                ; Leave the check to run time.
    LD   HL,(RO_DPOS)              ; The bracket's offset.
    LD   (TK_POS),HL               ; Report there; line and column stay.
    POP  AF                        ; Discard the type.
    JP   EX_EBIG                   ; Raise DG_RANGE.

; Raise DG_CLASH for a selection the type does not have.

RO_EPATH:
    POP  AF                        ; Discard the type.
    JP   EX_ETYPE                  ; Raise DG_CLASH.

;@ROUTINE IN A OUT D,E,HL CLOBBERS A,BC,IX,IY,CARRY,ZERO,SIGN,PARITY,HALFCARRY
; Parse one scalar argument of expected type A and check that it fits,
; keeping the enclosing expression's wanted type. A failable call cannot be
; an argument. D returns its metadata, E the type and HL a known value, as
; GX_TOREG takes them.

RO_ARG:
    LD   D,A                       ; Keep the expected type.
    LD   A,(EX_WANT)               ; Keep the enclosing expression's wanted type
    LD   B,A                       ; in B,
    PUSH BC                        ; across the nested parse,
    PUSH DE                        ; with the expected type.
    LD   A,D                       ; Ask for the expected type.
    LD   (EX_WANT),A               ; The argument's wanted type.
    CALL EX_PARSE                  ; A and HL describe the argument.
    POP  DE                        ; Recover the expected type.
    POP  BC                        ; Recover the enclosing wanted type
    LD   C,A                       ; (the argument's metadata to C)
    LD   A,B                       ; and restore it.
    LD   (EX_WANT),A               ; The enclosing expression resumes.
    LD   E,D                       ; EX_FITS takes the destination in E,
    LD   A,C                       ; the metadata in A.
    JP   EX_FITS                   ; Check it against the parameter's type.

;@ROUTINE IN A OUT A,CARRY,ZERO CLOBBERS SIGN,PARITY,HALFCARRY,BC,DE,HL,IX,IY
; Parse a call to routine A, RO_FIND's index, whose name has been read, as
; the reference's call does: each argument is evaluated, left to right,
; and pushed, a scalar in the registers at its parameter's type (a u8 or
; Boolean widened to a word) and an aggregate as its address; then CALL
; the routine, whose exit removes the arguments (RETN), so the pushes are
; counted out again. The callee's need joins the largest of this
; routine's callees (noteCall); one whose body is not complete has need
; zero in its record, and only a routine declared forward may call itself
; (DG_UNMET otherwise). A failable callee's failure is consumed at once
; (RO_FAILS). A returns the result type, zero for none. A call to main is
; refused for now (DG_NYI), as is an open-string argument (65.4 h).

RO_CALL:
    CP   RO_MAIN                   ; Is the callee main?
    JP   Z,TR_OPER                 ; Refused for now.
    LD   C,A                       ; C is the callee.
    LD   A,(RO_CUR)                ; The routine being compiled.
    CP   C                         ; Does it call itself?
    LD   A,C                       ; The callee again.
    CALL RO_SUBAT                  ; HL is its record; the flags survive.
    JR   NZ,.DEPTH                 ; Another routine: any may be called.
    PUSH HL                        ; Keep the record.
    LD   DE,RO_RFLAG               ; Its flags:
    ADD  HL,DE                     ; was it
    BIT  3,(HL)                    ; declared forward (RO_FFWD)?
    POP  HL                        ; The record again.
    JP   Z,.NEEDFWD                ; No: it cannot call itself.
.DEPTH:                        ; The call may be parsed.
    LD   A,(RO_DEPTH)              ; Calls already being parsed.
    CP   RO_NCAP                   ; Room for another?
    JP   NC,.DEEP                  ; No: raise DG_DEEP.
    INC  A                         ; One more
    LD   (RO_DEPTH),A              ; is being parsed.
    INC  HL                        ; Skip the name's
    INC  HL                        ; address
    INC  HL                        ; and length.
    LD   D,(HL)                    ; D is the first parameter,
    INC  HL                        ; E the number
    LD   E,(HL)                    ; of arguments.
    PUSH BC                        ; Keep the callee for the end.
    PUSH DE                        ; And the parameters.
    CALL PR_LEFT                   ; Consume the opening parenthesis.
    POP  DE                        ; D is the next parameter, E those left.
.ARG:                          ; Parse the next argument, if any.
    LD   A,E                       ; Any left?
    OR   A                         ; Zero when every one is parsed.
    JR   Z,.CLOSE                  ; Then the call closes.
    PUSH DE                        ; Keep the parameters across the argument.
    LD   A,D                       ; The parameter's entry:
    CALL RO_PARAM                  ; HL addresses it.
    INC  HL                        ; Skip its name's
    INC  HL                        ; address
    INC  HL                        ; and length.
    LD   A,(HL)                    ; Its type.
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
    CP   AG_VIEW                   ; An open string's view
    JP   Z,TR_OPER                 ; is refused for now (65.4 h).
    PUSH AF                        ; Keep the type.
    CALL RO_AGGR                   ; A is the argument's type, HL its address.
    POP  BC                        ; B is the parameter's.
    CP   B                         ; The types must be the same.
    JP   NZ,EX_ETYPE               ; Raise DG_CLASH.
.PUSH:                         ; The argument is in HL.
    CALL EM_OP                     ; PUSH HL.
    DB   $E5                       ; Append it.
    LD   A,2                       ; Two bytes are pushed
    CALL EM_PUSH                   ; until the call returns.
    POP  DE                        ; The parameters.
    INC  D                         ; The next parameter.
    DEC  E                         ; One fewer to parse.
    JR   Z,.CLOSE                  ; That was the last.
    PUSH DE                        ; Keep the parameters.
    LD   E,TK_COMMA                ; A comma separates arguments.
    CALL PR_NEED                   ; Consume it.
    POP  DE                        ; The parameters again.
    JR   .ARG                      ; Parse the next argument.
.CLOSE:                        ; Every argument is pushed.
    CALL PR_RIGHT                  ; Consume the closing parenthesis.
    LD   HL,RO_DEPTH               ; This call
    DEC  (HL)                      ; is parsed.
    POP  BC                        ; C is the callee.
    LD   A,C                       ; Its record:
    CALL RO_SUBAT                  ; HL addresses it.
    LD   DE,RO_RTYPE               ; Its result type
    ADD  HL,DE                     ; is returned,
    LD   A,(HL)                    ; so keep it.
    PUSH AF                        ; Then its flags,
    INC  HL                        ; whether it can fail,
    LD   A,(HL)                    ; are kept
    PUSH AF                        ; too.
    INC  HL                        ; Its ordinal.
    LD   E,(HL)                    ; DE is
    INC  HL                        ; the ordinal,
    LD   D,(HL)                    ; the call's target.
    INC  HL                        ; Its need follows.
    PUSH HL                        ; Keep the place.
    CALL EM_OP                     ; CALL nn,
    DB   $CD                       ; the routine.
    EX   DE,HL                     ; HL is the ordinal;
    LD   DE,0                      ; with no addend,
    CALL EM_REF                    ; refer to it.
    POP  HL                        ; The need,
    LD   E,(HL)                    ; low byte
    INC  HL                        ; and
    LD   D,(HL)                    ; high byte.
    INC  HL                        ; Then the argument bytes,
    LD   A,(HL)                    ; which RETN removed:
    PUSH DE                        ; keeping the need,
    CALL EM_POP                    ; they are no longer pushed.
    POP  DE                        ; DE is the callee's need.
    LD   HL,(EM_NEED)              ; The largest callee's need so far.
    OR   A                         ; Clear carry.
    SBC  HL,DE                     ; Carry if this one is larger.
    JR   NC,.SMALLER               ; Keep the larger one.
    LD   (EM_NEED),DE              ; It is the largest.
.SMALLER:                      ; The need is accounted.
    POP  AF                        ; The callee's flags:
    AND  RO_FFAIL                  ; can it fail?
    CALL NZ,RO_FAILS               ; Then its failure is consumed.
    POP  AF                        ; A is the result type.
    OR   A                         ; Carry clear.
    RET                            ; The result is in A or HL.
.NEEDFWD:                      ; A routine calls itself without a forward.
    CALL DG_RAISE                  ; Abandon the build.
    DB   DG_UNMET                  ; Unmet forward declaration.
.DEEP:                         ; Calls nest too deeply in arguments.
    CALL DG_RAISE                  ; Abandon the build.
    DB   DG_DEEP                   ; Nested too deeply.

;@ROUTINE CLOBBERS A,BC,DE,HL,CARRY,ZERO,SIGN,PARITY,HALFCARRY
; A failable routine has just been called: its failure is consumed by
; what follows the call directly, as the reference's call decides it.
; Before `else` (fail) the routine must be failable itself (DG_LEAK), and
; JP C goes to its exit, A holding the code; before `handle`, JP C goes
; to a new label, and the temporaries pushed beneath the call are kept in
; RO_KEPT for the handler to drop. Anything else raises DG_LEAK. RO_PEND
; is $80 plus the label, which the statement's end consumes.

RO_FAILS:
    CALL PR_PEEK                   ; What follows the call?
    CP   TK_HANDL                  ; A handler?
    JR   Z,.TRAP                   ; Jump to it on failure.
    CP   TK_ELSE                   ; `else fail`?
    JP   NZ,AC_ELEAK               ; Neither: the failure is lost.
    LD   A,(RO_CFLAG)              ; Passing it on needs
    AND  RO_FFAIL                  ; a failable routine.
    JP   Z,AC_ELEAK                ; This one is not.
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

;@ROUTINE OUT A,C,HL,CARRY,ZERO CLOBBERS SIGN,PARITY,HALFCARRY,B,DE,IX,IY
; Parse a name-rooted aggregate path or a call returning an aggregate, its
; address generated into HL. The result must be an aggregate address: A
; returns its type, and C is nonzero if the path is rooted at a parameter,
; whose storage is the caller's (alias rules, spec 7.7).

RO_AGGR:
    LD   E,TK_NAME                 ; A path starts with a name.
    CALL PR_NEED                   ; Consume it.
    CALL RO_FIND                   ; Is it a routine?
    JR   NZ,.SYMBOL                ; Otherwise it is a symbol.
    CALL RO_CALL                   ; A is the result type, HL the address.
    CP   AG_FIRST                  ; It must be an aggregate.
    JP   C,EX_ETYPE                ; Raise DG_CLASH.
    LD   C,0                       ; A call's result is not a parameter's.
    JR   .SUFFIX                   ; Parse the rest of the path.
.SYMBOL:                       ; Root the path at a symbol.
    CALL RO_SYM                    ; D is the symbol's class.
    LD   A,D                       ; It must be an aggregate.
    AND  SY_AGGR                   ; Test the aggregate flag.
    JP   Z,EX_ETYPE                ; Raise DG_CLASH.
    LD   A,D                       ; The class byte.
    AND  SY_CMASK                  ; Keep the storage class.
    XOR  SY_PARAM                  ; Zero for a parameter,
    SUB  1                         ; then carry only for it:
    SBC  A,A                       ; C is nonzero for a parameter.
    LD   C,A                       ; Keep it.
.ROOTED:                       ; Write the root.
    PUSH BC                        ; Keep the root flag.
    CALL RO_ROOT                   ; Write the address of the symbol.
    POP  BC                        ; Recover the root flag.
    LD   A,(RO_OTYPE)              ; The root's type.
    JR   .SUFFIX                   ; Parse the rest of the path.
.SUFFIX:                       ; Parse the selections.
    PUSH BC                        ; Keep the root flag.
    CALL RO_PATH                   ; A is the final type, D its form.
    POP  BC                        ; Recover the root flag.
    LD   E,A                       ; Keep the type.
    LD   A,D                       ; The result must be an address.
    OR   A                         ; `.length` gives a value instead.
    JP   NZ,EX_ETYPE               ; Raise DG_CLASH.
    LD   A,E                       ; The final type.
    CP   AG_FIRST                  ; It must be an aggregate.
    JP   C,EX_ETYPE                ; Raise DG_CLASH.
    OR   A                         ; Carry clear.
    RET                            ; A is the type, C the parameter flag.

;@ROUTINE IN A,D OUT A,CARRY,ZERO CLOBBERS SIGN,PARITY,HALFCARRY,B,DE,HL
; Make the scalar path of type A an ordinary expression value. D is zero
; if the path is an address, so OP_LDX8 or OP_LDX16 loads through it, or
; one if it is already a value.

RO_LOAD:
    CP   AG_FIRST                  ; An aggregate is not a scalar value.
    JP   NC,EX_ETYPE               ; Raise DG_CLASH.
    LD   (RO_OTYPE),A              ; Keep the type.
    LD   A,D                       ; Keep the path's form.
    LD   (RO_ACNT),A               ; RO_ACNT is free while a path is loaded.
    OR   A                         ; Is the path already a value?
    JR   NZ,.READY                 ; Then nothing is loaded.
    LD   A,(RO_OTYPE)              ; The scalar's type.
    CP   SY_U16                    ; Is it a word?
    LD   A,OP_LDX8                 ; A u8 or boolean loads a byte.
    JR   NZ,.EMIT                  ; Write it.
    LD   A,OP_LDX16                ; A u16 loads a word.
.EMIT:                         ; Write the load.
    CALL TR_OPER                   ; Write the operation.
.READY:                        ; Return the value's type.
    LD   A,(RO_OTYPE)              ; The scalar's type.
    OR   A                         ; Carry clear.
    RET                            ; A is the type.

;@ROUTINE IN A OUT A,CARRY,ZERO CLOBBERS SIGN,PARITY,HALFCARRY,BC,DE,HL,IX,IY
; The expression parser's hook for a routine name, read already: parse
; the call to routine A, keeping its result, and make the result, or a
; scalar selected from it, the expression's value of type A.

RO_FUNC:
    CALL RO_CALL                   ; A is the result type.
    OR   A                         ; A routine without a result has no value.
    JP   Z,EX_ETYPE                ; Raise DG_CLASH.
    CP   AG_FIRST                  ; Is the result an aggregate?
    JR   NC,RO_WALK                ; Select a scalar from it.
    OR   A                         ; Carry clear.
    RET                            ; A is the scalar result type.

;@ROUTINE IN A OUT A,CARRY,ZERO CLOBBERS SIGN,PARITY,HALFCARRY,BC,DE,HL,IX,IY
; Parse the suffix of a path of type A and load the scalar it selects.

RO_WALK:
    CALL RO_PATH                   ; A is the final type, D its form.
    JR   RO_LOAD                   ; Make it a value.

;@ROUTINE IN A OUT A,B,HL,CARRY,ZERO CLOBBERS SIGN,PARITY,HALFCARRY,C,DE,IX,IY
; The expression parser's hook for an error constant, ordinal A from
; RO_LIB: its value is the error code 1..4, written as a known u8 literal.

RO_CAUSE:
    SUB  RO_ERRS-1                 ; The first constant is code one.
    LD   L,A                       ; Form the code as a word.
    LD   H,0                       ; HL is the literal's value.
    LD   B,SY_KNOWN+SY_U8          ; A known u8 constant.
    JP   EX_LIT                    ; Write it and return its metadata.

;@ROUTINE OUT A,CARRY,ZERO CLOBBERS SIGN,PARITY,HALFCARRY,BC,DE,HL,IX,IY
; The expression parser's hook for an aggregate symbol, the current NAME:
; write its root, then select and load a scalar from it.

RO_OBJ:
    CALL RO_ROOT                   ; A is the root's type.
    JP   RO_WALK                   ; Select the scalar and load it.

;@ROUTINE IN D OUT A,CARRY,ZERO CLOBBERS SIGN,PARITY,HALFCARRY,BC,DE,HL,IX,IY
; Parse an assignment whose target is a path rooted at the aggregate
; symbol of class D, the current NAME. A scalar target takes OP_STX8 or
; OP_STX16; an aggregate target takes OP_COPY of a source of the same type.

RO_LET:
    LD   A,D                       ; The symbol's class.
    AND  SY_CMASK                  ; A constant has class zero.
    JR   NZ,.WRITABLE              ; Variables and parameters are writable.
    CALL DG_RAISE                  ; Raise the diagnostic below.
    DB   DG_CONST                  ; A constant cannot be assigned.
.WRITABLE:                     ; Parse the target path.
    CALL RO_ROOT                   ; Write the root's address.
    CALL RO_PATH                   ; A is the target's type, D its form.
    LD   E,A                       ; Keep the type.
    LD   A,D                       ; The target must be an address.
    OR   A                         ; `.length` cannot be assigned.
    JP   NZ,EX_ETYPE               ; Raise DG_CLASH.
    LD   A,E                       ; The target's type.
    LD   (RO_OTYPE),A              ; Keep it.
    CALL PR_EQUAL                  ; Consume the equals sign.
    LD   HL,(TK_POS)               ; The assignment's offset.
    LD   (RO_DPOS),HL              ; A copy's traps report it.
    LD   A,(RO_OTYPE)              ; The target's type.
    CP   AG_FIRST                  ; Is it an aggregate?
    JR   NC,.COPY                  ; Copy a whole aggregate.
    LD   E,A                       ; The wanted type.
    CALL EX_RUN                    ; Parse the value.
    LD   D,A                       ; Keep its metadata.
    LD   A,(RO_OTYPE)              ; The target's type.
    LD   E,A                       ; It is the value's destination.
    LD   A,D                       ; The value's metadata.
    CALL EX_FITS                   ; Check that it fits.
    CALL AC_ROUTE                  ; Attach any failure handling.
    LD   A,(RO_OTYPE)              ; The target's type.
    CP   SY_U16                    ; Is it a word?
    LD   A,OP_STX8                 ; A u8 or boolean stores a byte.
    JR   NZ,.EMIT                  ; Write it.
    LD   A,OP_STX16                ; A u16 stores a word.
.EMIT:                         ; Write the store.
    CALL TR_OPER                   ; Write the operation.
    RET                            ; The assignment is complete.
.COPY:                         ; Copy an aggregate.
    PUSH AF                        ; Keep the target's type.
    CALL RO_AGGR                   ; Parse the source; A is its type.
    LD   D,A                       ; Keep it.
    POP  AF                        ; The target's type.
    CP   AG_VIEW                   ; An open string's size is unknown here.
    JP   Z,EX_ETYPE                ; Raise DG_CLASH.
    CP   D                         ; The types must be the same.
    JP   NZ,EX_ETYPE               ; Raise DG_CLASH.
    CALL AG_SIZE                   ; HL is the aggregate's size.
    LD   (RO_OSIZE),HL             ; Keep it for the operand.
    CALL AC_ROUTE                  ; Attach any failure handling.
    LD   A,OP_COPY                 ; Copy the source onto the target.
    CALL TR_OPER                   ; Write the operation.
    LD   HL,(RO_OSIZE)             ; The size.
    CALL RO_EMITW                  ; Write it.
    LD   HL,(RO_DPOS)              ; The assignment's offset.
    CALL RO_EMITW                  ; Write it.
    RET                            ; The assignment is complete.
