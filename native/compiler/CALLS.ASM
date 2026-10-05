;==========================================================================
;  Calls, services and aggregate paths
;==========================================================================
;
;  Parse calls to source routines and to the predefined services, and the
;  access paths into aggregates: record fields, array elements, string
;  length and characters, and assignment to a path. Each is checked
;  against the routine and parameter tables (ROUTINES.ASM) and the
;  aggregate types (AGGR.ASM), then written to the semantic transcript for
;  GENCALL.ASM. The grammar actions call in for statements; the expression
;  parser enters through RO_FUNC, RO_OBJ, RO_QUERY and RO_CAUSE when a name
;  in an expression is a routine, an aggregate, a service or an error
;  constant.
;
;  Principal entries:
;    RO_CALL   parse a call to a source routine and write OP_CALL
;    RO_SERVE  parse a call to a service and write OP_CALL
;    RO_AGGR   parse a path or call whose value is an aggregate
;    RO_LET    parse an assignment to an aggregate path
;    RO_FUNC   expression hook: a routine call as a value
;    RO_OBJ    expression hook: a scalar selected from an aggregate
;    RO_QUERY  expression hook: a service's u8 result
;    RO_CAUSE  expression hook: an error constant's code
;    RO_EMITW  write an operand word of a structural operation
;
;  A call being parsed has a frame in RO_NTAB, four deep, because an
;  argument may itself be a call:
;
;    +0  byte  call selector: the label, plus RO_FKEEP if the result is kept
;    +1  byte  result type
;    +2  byte  index of the next parameter to match
;    +3  byte  arguments still to parse
;    +4  byte  carriers to drop after the call (an open string is two)
;    +5  word  source offset of the call
;    +7  byte  the callee's flags
;
;  A call selector (RO_DEST) has RO_FIO clear for a source routine, with
;  the label in its low six bits. For a service RO_FIO is set, with the
;  service in bits 0..2, its argument type in bits 3..4 and RO_RES8 for a
;  u8 result (KW_SIGS). Every OP_CALL ends with three handling bytes
;  (RO_PAD) that the statement's `else fail` or handler fills in later.
;  A path pushes an address and refines it with OP_FIELD, OP_INDEX or a
;  character operation; RO_LOAD turns a scalar path into a value.

;@ROUTINE OUT A,BC,D,CARRY,ZERO CLOBBERS SIGN,PARITY,HALFCARRY,E,HL
; Look up the current NAME as a symbol: D returns its class, BC its payload
; and A its type from AG_SYTAB, indexed by the record's position. An
; undefined name raises DG_UNDEF, which does not return.

RO_SYM:
    CALL SY_FIND                   ; HL addresses the record.
    JP   NC,SY_UNDEF               ; Raise DG_UNDEF.
    PUSH HL                        ; Keep the record's address.
    INC  HL                        ; Skip the spelling's address.
    INC  HL                        ; Skip its high byte.
    INC  HL                        ; Skip the length to reach the class.
    LD   D,(HL)                    ; Read the class.
    LD   A,D                       ; Keep the class in RO_ACNT.
    LD   (RO_ACNT),A               ; D is reused for the type-table index.
    INC  HL                        ; The payload follows.
    LD   C,(HL)                    ; Low byte.
    INC  HL                        ; High byte.
    LD   B,(HL)                    ; BC is the payload.
    POP  HL                        ; Recover the record's address.
    LD   DE,SY_BASE                ; Find its offset in the table.
    OR   A                         ; Clear carry for the subtraction.
    SBC  HL,DE                     ; The table is under 256 bytes.
    LD   A,L                       ; A is the offset.
    LD   E,0                       ; E counts whole records.
.IDXLOOP:                      ; Divide the offset by SY_RECB.
    CP   SY_RECB                   ; Is a whole record left?
    JR   C,.INDEXED                ; No: E is the index.
    SUB  SY_RECB                   ; Take one record away.
    INC  E                         ; Count it.
    JR   .IDXLOOP                  ; Continue.
.INDEXED:                      ; E is the symbol's index.
    LD   A,E                       ; Move the index through A.
    LD   E,A                       ; E still holds it.
    LD   H,0                       ; Form the index as a word.
    LD   L,E                       ; One type byte per symbol.
    LD   DE,AG_SYTAB               ; Index the parallel type table.
    ADD  HL,DE                     ; HL addresses the symbol's type.
    LD   A,(HL)                    ; Read the type.
    LD   E,A                       ; Keep it while D is restored.
    LD   A,(RO_ACNT)               ; Recover the class.
    LD   D,A                       ; Return it in D.
    LD   A,E                       ; Return the type in A.
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

;@ROUTINE OUT A,CARRY,ZERO CLOBBERS SIGN,PARITY,HALFCARRY,BC,DE,HL,IX,IY
; Write the operation that pushes the current NAME's address, the root of
; an aggregate path: OP_REFRO for a constant, OP_REFG for a program
; variable, OP_REFP for a parameter. A returns the exact aggregate type,
; also kept in RO_OTYPE; an open string's capacity slot goes to RO_VCAP.

RO_ROOT:
    CALL RO_SYM                    ; A is the type, D the class, BC the payload.
    LD   (RO_OTYPE),A              ; Keep the type for the return.
    CP   AG_VIEW                   ; Is it an open-string parameter?
    JR   NZ,.CLASS                 ; Other types have their capacity declared.
    LD   A,C                       ; The parameter's slot.
    INC  A                         ; The capacity byte follows the address word.
    INC  A                         ; Slot + 2 is the capacity's slot.
    LD   (RO_VCAP),A               ; OP_VLEN, OP_VCHAR and OP_VIEW carry it.
.CLASS:                        ; Choose the root by storage class.
    LD   A,D                       ; The class byte.
    AND  SY_CMASK                  ; Keep the storage class.
    JR   Z,RO_FIXED                ; SY_CONST: an aggregate constant.
    CP   SY_GLOB                   ; A program variable?
    JR   NZ,RO_BYREF               ; Otherwise it must be a parameter.
    LD   A,OP_REFG                 ; Push a program variable's address.

;@ROUTINE IN A,BC OUT A,CARRY,ZERO CLOBBERS SIGN,PARITY,HALFCARRY,BC,DE,HL
; Write operation A with offset word BC, then return the type in RO_OTYPE.

RO_ALIAS:
    PUSH BC                        ; Keep the offset.
    CALL TR_OPER                   ; Write the operation.
    POP  HL                        ; The offset is the operand.
    CALL RO_EMITW                  ; Write it.
    JR   RO_TYPED                  ; Return the type.

;@ROUTINE IN BC,D OUT A,CARRY,ZERO CLOBBERS SIGN,PARITY,HALFCARRY,BC,DE,HL,IX
; Root a path at an aggregate constant, which must be in the current bank.

RO_FIXED:
    PUSH BC                        ; Keep the offset.
    CALL TG_MUST                   ; The constant must be in this bank.
    POP  BC                        ; Recover the offset.
    LD   A,OP_REFRO                ; Push a constant's address.
    JR   RO_ALIAS                  ; Write it with the offset.

;@ROUTINE IN A,C OUT A,CARRY,ZERO CLOBBERS SIGN,PARITY,HALFCARRY,B,DE,HL
; Root a path at a parameter (class A): OP_REFP with slot C. A local is
; never an aggregate, so any other class raises DG_CLASH.

RO_BYREF:
    CP   SY_PARAM                  ; Is it a parameter?
    JP   NZ,EX_ETYPE               ; Raise DG_CLASH.
    LD   A,OP_REFP                 ; Push the parameter's address word.
.EMIT:                         ; Write it with the slot.
    CALL PR_EMITC                  ; Write OP_REFP and slot C.

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
    LD   (RO_OTYPE),A              ; Keep it across AC_SAFE.
    CALL AC_SAFE                   ; A failable call cannot be selected from.
    LD   A,(RO_OTYPE)              ; Recover the type.
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
    POP  AF                        ; Recover the type.
    LD   (RO_OTYPE),A              ; Keep it across AC_SAFE.
    CALL AC_SAFE                   ; A failable call cannot be indexed.
    LD   A,(RO_VCAP)               ; The index may hold another open string.
    PUSH AF                        ; So keep this path's capacity slot.
    LD   A,(RO_OTYPE)              ; Keep the type too.
    PUSH AF                        ; Below the slot.
.OPERAND:                      ; Parse the index expression.
    LD   HL,(TK_POS)               ; The offset of the bracket.
    PUSH HL                        ; Traps report it.
    CALL PR_TAKE                   ; Consume the bracket.
    LD   A,(EX_WANT)               ; Keep the enclosing expression's wanted type.
    PUSH AF                        ; Push it.
    LD   A,(EX_LIVE)               ; Keep its emission state.
    PUSH AF                        ; Push that too.
    LD   A,1                       ; The index is evaluated at run time.
    LD   (EX_LIVE),A               ; Emit its code.
    LD   A,SY_U16                  ; An index is a u16.
    LD   (EX_WANT),A               ; Ask for one.
    CALL EX_PARSE                  ; A and HL describe the index.
    CALL EX_PURE                   ; A failable call cannot be an index.
    LD   (EX_RMETA),A              ; Keep the index's metadata.
    LD   (EX_RVAL),HL              ; Keep its constant value.
    POP  AF                        ; Recover the enclosing emission state.
    LD   (EX_LIVE),A               ; Restore it.
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

;@ROUTINE IN A OUT A,HL,CARRY,ZERO CLOBBERS SIGN,PARITY,HALFCARRY,DE
; Return in HL the address of call frame A in RO_NTAB. A frame keeps a
; call's description while its arguments, which may be calls, are parsed.

RO_FRAME:
    LD   L,A                       ; Form the depth as a word.
    LD   H,0                       ; At most RO_NCAP frames.
    ADD  HL,HL                     ; Times two.
    ADD  HL,HL                     ; Times four.
    ADD  HL,HL                     ; Times eight, the frame size.
    LD   DE,RO_NTAB                ; The frames' base.
    ADD  HL,DE                     ; HL addresses the frame.
    OR   A                         ; Carry clear.
    RET                            ; A still holds the depth.

;@ROUTINE OUT A,HL,CARRY,ZERO CLOBBERS SIGN,PARITY,HALFCARRY,DE
; Return in HL the frame of the innermost call being parsed.

RO_TOP:
    LD   A,(RO_DEPTH)              ; Calls being parsed.
    DEC  A                         ; The innermost is one below.
    JR   RO_FRAME                  ; Address it.

;@ROUTINE IN A OUT CARRY CLOBBERS A,BC,DE,HL,IX,IY,SIGN,PARITY,HALFCARRY,ZERO
; Parse one scalar argument of expected type A and check that it fits,
; keeping the enclosing expression's wanted type and emission state. A
; failable call cannot be an argument.

RO_ARG:
    LD   D,A                       ; Keep the expected type.
    LD   A,(EX_WANT)               ; Keep the enclosing expression's wanted type.
    LD   B,A                       ; Hold it in B.
    LD   A,(EX_LIVE)               ; Keep its emission state.
    LD   C,A                       ; Hold it in C.
    PUSH BC                        ; Across the nested parse.
    PUSH DE                        ; With the expected type.
    LD   A,D                       ; Ask for the expected type.
    LD   (EX_WANT),A               ; The argument's wanted type.
    LD   A,1                       ; The argument is evaluated at run time.
    LD   (EX_LIVE),A               ; Emit its code.
    CALL EX_PARSE                  ; A and HL describe the argument.
    LD   (RO_OTYPE),A              ; Keep the argument's metadata.
    LD   (EX_RVAL),HL              ; Keep its constant value.
    POP  DE                        ; Recover the expected type.
    POP  BC                        ; Recover the enclosing state.
    LD   A,C                       ; Recover the enclosing emission state.
    LD   (EX_LIVE),A               ; Restore it.
    LD   A,B                       ; Recover the enclosing wanted type.
    LD   (EX_WANT),A               ; Restore it.
    LD   E,D                       ; EX_FITS takes the destination in E.
    LD   A,(RO_OTYPE)              ; The argument's metadata.
    LD   HL,(EX_RVAL)              ; Its constant value.
    CALL EX_FITS                   ; Check it against the parameter's type.
    JP   AC_SAFE                   ; Reject a pending failure and return.

;@ROUTINE IN A,C OUT A,CARRY,ZERO CLOBBERS SIGN,PARITY,HALFCARRY,BC,DE,HL,IX,IY
; Parse a call to routine A, or main if A is RO_MAIN, whose name has been
; read; C is one if its result is kept, zero if discarded. Match each
; argument to its parameter, write OP_CALL and return the result type in A.

RO_CALL:
    LD   B,A                       ; Keep the routine index.
    LD   A,(RO_DEPTH)              ; Calls already being parsed.
    CP   RO_NCAP                   ; Is there a free frame?
    JR   C,.ROOM                   ; Use it.
    CALL DG_RAISE                  ; Raise the diagnostic below.
    DB   DG_DEEP                   ; Calls nested too deeply.
.ROOM:                         ; Fill the next frame.
    CALL RO_FRAME                  ; HL addresses frame A, the depth.
    LD   A,C                       ; Move the keep flag into A.
    PUSH AF                        ; Keep it for the selector.
    PUSH HL                        ; Keep the frame's address.
    LD   A,B                       ; The routine index.
    CP   RO_MAIN                   ; Is the callee main?
    JR   Z,.MAIN                   ; Main has no table entry.
    CALL RO_SUBAT                  ; HL addresses the routine's entry.
    INC  HL                        ; Skip the spelling's address.
    INC  HL                        ; Skip its high byte.
    INC  HL                        ; Skip the length to reach the signature.
    LD   D,(HL)                    ; D is the first parameter's index.
    INC  HL                        ; Next field.
    LD   E,(HL)                    ; E is the parameter count.
    INC  HL                        ; Next field.
    LD   B,(HL)                    ; B is the result type.
    INC  HL                        ; Next field.
    LD   A,(HL)                    ; A is the label ordinal.
    INC  HL                        ; Next field.
    LD   C,(HL)                    ; C is the callee's flags.
    JR   .FILL                     ; Fill the frame.
.MAIN:                         ; Main's signature is fixed.
    LD   D,0                       ; Main has no parameters to match.
    LD   E,0                       ; And takes no arguments.
    LD   B,0                       ; Main has no result.
    LD   A,(RO_MFLAG)              ; Main's flags.
    LD   C,A                       ; As the callee flags.
    LD   A,RO_MDEST                ; Main's body label.
.FILL:                         ; Write the frame.
    POP  HL                        ; Recover the frame's address.
    LD   (HL),A                    ; The selector starts as the label.
    POP  AF                        ; Is the result kept?
    OR   A                         ; Test the keep flag.
    JR   Z,.LABEL                  ; A discarded result keeps bit 6 clear.
    SET  6,(HL)                    ; RO_FKEEP.
.LABEL:                        ; Fill the remaining fields.
    INC  HL                        ; Field +1.
    LD   (HL),B                    ; The result type.
    INC  HL                        ; Field +2.
    LD   (HL),D                    ; The next parameter to match.
    INC  HL                        ; Field +3.
    LD   (HL),E                    ; The arguments left to parse.
    INC  HL                        ; Field +4.
    LD   (HL),E                    ; The carriers to drop: one per argument at first.
    INC  HL                        ; Field +5.
    LD   DE,(TK_POS)               ; The offset of the routine's name.
    LD   (HL),E                    ; Store the offset's low byte.
    INC  HL                        ; Advance to its high byte.
    LD   (HL),D                    ; Store the high byte.
    INC  HL                        ; Field +7.
    LD   (HL),C                    ; The callee's flags.
    LD   HL,RO_DEPTH               ; The frame is now in use.
    INC  (HL)                      ; One call deeper.
    CALL PR_LEFT                   ; Consume the opening parenthesis.
.ARGLOOP:                      ; Parse one argument.
    CALL RO_TOP                    ; HL addresses this call's frame.
    INC  HL                        ; Skip the selector.
    INC  HL                        ; Skip the result type.
    INC  HL                        ; HL addresses the arguments left.
    LD   A,(HL)                    ; Read the count.
    OR   A                         ; Are any left?
    JP   Z,.ARGSDONE               ; Close the call.
    DEC  HL                        ; Back to the next parameter's index.
    LD   A,(HL)                    ; Read the next parameter's index.
    CALL RO_PARAM                  ; HL addresses the parameter.
    INC  HL                        ; Skip the spelling's address.
    INC  HL                        ; Skip its high byte.
    INC  HL                        ; Skip the length to reach the type.
    LD   A,(HL)                    ; Read the parameter's type.
    LD   D,A                       ; Keep it.
    XOR  A                         ; No failure is pending yet.
    LD   (RO_PEND),A               ; Clear RO_PEND before the argument.
    LD   A,D                       ; The parameter's type.
    CP   AG_FIRST                  ; Is it an aggregate?
    JR   NC,.AGGRARG               ; Parse an aggregate path.
    CALL RO_ARG                    ; Parse a scalar of that type.
    JR   .ARGOK                    ; Move to the next argument.
.AGGRARG:                      ; Parse an aggregate argument.
    CALL RO_AGGR                   ; A is its type, C one for a global root.
    PUSH AF                        ; Keep the argument's type.
    CALL RO_TOP                    ; Nested calls may have used frames: find ours.
    INC  HL                        ; Skip the selector.
    INC  HL                        ; Skip the result type to the next parameter.
    LD   A,(HL)                    ; The parameter's index.
    CALL RO_PARAM                  ; HL addresses the parameter.
    INC  HL                        ; Skip the spelling's address.
    INC  HL                        ; Skip its high byte.
    INC  HL                        ; Skip the length to reach the type.
    LD   D,(HL)                    ; D is the parameter's type.
    POP  AF                        ; Recover the argument's type.
    LD   (RO_OTYPE),A              ; Keep it.
    LD   A,D                       ; Keep the parameter's type.
    LD   (RO_DTYPE),A              ; .OPENARG reads it from RO_DTYPE.
    CP   AG_VIEW                   ; Is the parameter an open string?
    JR   Z,.OPENSTR                ; Any string fits it.
    LD   A,(RO_OTYPE)              ; The argument's type.
    CP   D                         ; It must equal the parameter's type.
    JP   NZ,RO_EARG                ; Raise DG_CLASH.
    JR   .TYPEOK                   ; The argument fits.
.OPENSTR:                      ; Check an argument for an open string.
    LD   A,(RO_OTYPE)              ; The argument's type.
    CP   AG_VIEW                   ; An open string passes its own view on.
    JR   Z,.TYPEOK                 ; It fits.
    CALL RO_CAP                    ; Raise DG_CLASH unless it is a string.
.TYPEOK:                       ; Check the argument's bank.
; A cross-bank aggregate parameter must originate at a direct
; program root. Diagnose through the ordinary call-frame unwind.
    CALL RO_TOP                    ; HL addresses this call's frame.
    LD   DE,RO_NFLAG               ; The callee's flags hold its bank.
    ADD  HL,DE                     ; HL addresses them.
    LD   D,(HL)                    ; Read them.
    CALL TG_SAME                   ; Is the callee in this bank?
    JR   Z,.BANKOK                 ; Then any address reaches it.
    LD   A,C                       ; Is the path rooted at a program variable?
    OR   A                         ; RO_AGGR returned that in C.
    JR   NZ,.BANKOK                ; Program data is reachable from any bank.
    LD   A,DG_CFG                  ; Anything else is not.
    CALL DG_ISSUE                  ; Raise DG_CFG.
.BANKOK:                       ; The argument is acceptable.
    CALL AC_SAFE                   ; A failable call cannot be an argument.
    LD   A,(RO_DTYPE)              ; The parameter's type.
    CP   AG_VIEW                   ; Is it an open string?
    JR   NZ,.ARGOK                 ; Other arguments are one address.
    CALL .OPENARG                  ; Add the capacity word.
.ARGOK:                        ; Move to the next parameter.
    CALL RO_TOP                    ; HL addresses this call's frame.
    INC  HL                        ; Skip the selector.
    INC  HL                        ; Skip the result type.
    INC  (HL)                      ; Advance to the next parameter.
    INC  HL                        ; Address the arguments left.
    DEC  (HL)                      ; One fewer to parse.
    JR   Z,.ARGSDONE               ; That was the last.
    LD   E,TK_COMMA                ; A comma separates arguments.
    CALL PR_NEED                   ; Consume it.
    JP   .ARGLOOP                  ; Parse the next argument.

;@ROUTINE OUT A,CARRY,ZERO CLOBBERS SIGN,PARITY,HALFCARRY,BC,DE,HL,IX,IY
; Write OP_VIEW, turning the string argument just parsed into an open-string
; argument with its capacity beneath it: a declared capacity (mode zero) or
; the capacity slot of an open-string parameter passed on (mode one).

.OPENARG:
    LD   A,(RO_OTYPE)              ; The argument's type.
    CP   AG_VIEW                   ; Is it an open string itself?
    JR   Z,.FORWARD                ; Pass its capacity on.
    CALL RO_CAP                    ; A is the declared capacity.
    LD   (RO_ACNT),A               ; OP_VIEW's value.
    XOR  A                         ; Mode zero: a constant capacity.
    JR   .OPENOK                   ; Write it.
.FORWARD:                      ; Pass an open string's capacity on.
    LD   A,(RO_VCAP)               ; The slot of its capacity byte.
    LD   (RO_ACNT),A               ; OP_VIEW's value.
    LD   A,1                       ; Mode one: copy it from the frame.
.OPENOK:                       ; Write OP_VIEW.
    LD   C,A                       ; The mode follows the operation.
    LD   A,OP_VIEW                 ; Form an open-string argument.
    CALL PR_EMITC                  ; Write the operation and the mode.
    LD   A,(RO_ACNT)               ; The capacity or its slot.
    CALL TR_PUT                    ; Write it.
    CALL RO_TOP                    ; HL addresses this call's frame.
    LD   DE,RO_NACNT               ; Address the carriers to drop.
    ADD  HL,DE                     ; HL addresses the count.
    INC  (HL)                      ; The capacity word is one carrier more.
    OR   A                         ; Carry clear.
    RET                            ; The argument is complete.
.ARGSDONE:                     ; Close the call and publish it.
    CALL PR_RIGHT                  ; Consume the closing parenthesis.
    CALL RO_TOP                    ; HL addresses this call's frame.
    LD   A,(HL)                    ; +0: the selector.
    LD   (RO_DEST),A               ; RO_PUB writes it.
    INC  HL                        ; Field +1.
    LD   A,(HL)                    ; Read the result type.
    LD   (RO_DTYPE),A              ; RO_PUB writes and returns it.
    INC  HL                        ; Skip the next parameter's index.
    INC  HL                        ; Skip the arguments left.
    INC  HL                        ; Field +4.
    LD   A,(HL)                    ; Read the carriers to drop.
    LD   (RO_ACNT),A               ; RO_PUB writes it.
    INC  HL                        ; Field +5.
    LD   E,(HL)                    ; Read the call's offset, low byte.
    INC  HL                        ; Then its high byte.
    LD   D,(HL)                    ; DE is the offset.
    LD   (RO_DPOS),DE              ; RO_PUB writes it.
    INC  HL                        ; Field +7.
    LD   A,(HL)                    ; Read the callee's flags.
    LD   (RO_DFLAG),A              ; RO_PUB writes them.
    LD   HL,RO_DEPTH               ; Release the frame.
    DEC  (HL)                      ; One call shallower.
    LD   A,(RO_DTYPE)              ; Does the call return an aggregate?
    CP   AG_FIRST                  ; Compare with the first aggregate type.
    JR   C,.RESULTOK               ; A scalar result is in HL.
    LD   A,(RO_DFLAG)              ; An aggregate's address lies in the callee's bank.
    LD   D,A                       ; D holds the callee's flags.
    CALL TG_MUST                   ; That bank must be this one.
.RESULTOK:                     ; Check the use of a failable call.
    LD   A,(RO_DFLAG)              ; Can the callee fail?
    AND  RO_FFAIL                  ; Test its failable flag.
    JR   Z,.FAILOK                 ; A call that cannot fail goes anywhere.
    LD   A,(RO_DEPTH)              ; Is this call an argument of another?
    OR   A                         ; Test the depth.
    JP   NZ,AC_ELEAK               ; Raise DG_LEAK: its failure is unhandled.
.FAILOK:                       ; Publish the call.

;@ROUTINE OUT A,CARRY,ZERO CLOBBERS SIGN,PARITY,HALFCARRY,B,DE,HL
; Write OP_CALL from RO_DEST, RO_ACNT, RO_DTYPE, RO_DFLAG and RO_DPOS,
; reserve its handling bytes, set RO_PEND if it can fail and return the
; result type in A.

RO_PUB:
    LD   A,OP_CALL                 ; Call a routine or service.
    CALL TR_OPER                   ; Write the operation.
    LD   A,(RO_DEST)               ; The selector.
    CALL TR_PUT                    ; Write it.
    AND  RO_FIO                    ; Is the callee a service?
    JR   NZ,.COMMON                ; Its selector holds its signature.
    LD   A,(RO_ACNT)               ; The carriers to drop.
    CALL TR_PUT                    ; Write them.
    LD   A,(RO_DTYPE)              ; The result type.
    CALL TR_PUT                    ; Write it.
    LD   A,(RO_DFLAG)              ; The callee's flags.
    CALL TR_PUT                    ; Write them.
.COMMON:                       ; Write the operands every call has.
    LD   HL,(RO_DPOS)              ; The call's offset.
    CALL RO_EMITW                  ; Write it.
    CALL RO_PAD                    ; Reserve the handling bytes.
    LD   A,(RO_DFLAG)              ; Can the callee fail?
    AND  RO_FFAIL                  ; Keep the failable flag.
    LD   (RO_PEND),A               ; The statement must handle a pending failure.
    LD   A,(RO_DTYPE)              ; Return the result type.
    OR   A                         ; Carry clear.
    RET                            ; A is the result type.

; Raise DG_CLASH for an aggregate argument of the wrong type, releasing
; the call's frame.

RO_EARG:
    LD   HL,RO_DEPTH               ; Release the frame.
    DEC  (HL)                      ; One call shallower.
    JP   EX_ETYPE                  ; Raise DG_CLASH.

;@ROUTINE OUT A,C,CARRY,ZERO CLOBBERS SIGN,PARITY,HALFCARRY,B,DE,HL,IX,IY
; Parse a name-rooted aggregate path or a call returning an aggregate. The
; result must be an aggregate address: A returns its type, and C is one if
; the path is rooted at a program variable, zero otherwise.

RO_AGGR:
    LD   E,TK_NAME                 ; A path starts with a name.
    CALL PR_NEED                   ; Consume it.
    CALL RO_FIND                   ; Is it a routine?
    JR   NZ,.SYMBOL                ; Otherwise it is a symbol.
    LD   C,1                       ; The call's result is kept.
    CALL RO_CALL                   ; A is the result type.
    CP   AG_FIRST                  ; It must be an aggregate.
    JP   C,EX_ETYPE                ; Raise DG_CLASH.
    LD   C,0                       ; A call result is no program variable.
    JR   .SUFFIX                   ; Parse the rest of the path.
.SYMBOL:                       ; Root the path at a symbol.
    CALL RO_SYM                    ; D is the symbol's class.
    LD   A,D                       ; It must be an aggregate.
    AND  SY_AGGR                   ; Test the aggregate flag.
    JP   Z,EX_ETYPE                ; Raise DG_CLASH.
    LD   A,D                       ; The class byte.
    AND  SY_CMASK                  ; Keep the storage class.
    LD   C,0                       ; Assume no program-variable root.
    CP   SY_GLOB                   ; Is it a program variable?
    JR   NZ,.ROOTED                ; No.
    INC  C                         ; Yes: C is one.
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
    RET                            ; A is the type, C the root flag.

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
    LD   C,1                       ; The result is kept.
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

;@ROUTINE IN A OUT A,CARRY,ZERO CLOBBERS SIGN,PARITY,HALFCARRY,BC,DE,HL,IX,IY
; The expression parser's hook for a service with a result (read input or
; storage), A: call it at the current offset, keeping its u8 result.

RO_QUERY:
    LD   HL,(TK_POS)               ; The service name's offset.
    LD   (RO_DPOS),HL              ; The call carries it.
    LD   C,1                       ; The result is kept.
    JR   RO_SERVE                  ; Parse the call.

;@ROUTINE IN A OUT A,B,HL,CARRY,ZERO CLOBBERS SIGN,PARITY,HALFCARRY,C,DE,IX,IY
; The expression parser's hook for an error constant, ordinal A from
; RO_LIB: its value is the error code 1..4, written as a known u8 literal.

RO_CAUSE:
    SUB  RO_ERRS-1                 ; The first constant is code one.
    LD   L,A                       ; Form the code as a word.
    LD   H,0                       ; HL is the literal's value.
    LD   B,SY_KNOWN+SY_U8          ; A known u8 constant.
    JP   EX_LIT                    ; Write it and return its metadata.

;@ROUTINE IN A,C OUT A,CARRY,ZERO CLOBBERS SIGN,PARITY,HALFCARRY,BC,DE,HL,IX,IY
; Parse a call to service A, whose name has been read; C is one if its
; result is kept. Parse its one optional scalar argument, write OP_CALL
; and return the result type in A. Every service can fail.

RO_SERVE:
    LD   E,A                       ; Form the service as a word.
    LD   D,0                       ; One selector byte per service.
    LD   HL,KW_SIGS                ; Index the selector table.
    ADD  HL,DE                     ; HL addresses its selector.
    LD   A,(HL)                    ; Read it.
    DEC  C                         ; Is the result kept?
    JR   NZ,.DESC                  ; No.
    OR   RO_FKEEP                  ; Yes: mark the selector.
.DESC:                         ; Keep the selector.
    LD   (RO_IO),A                 ; An argument's call may change RO_DEST.
    CALL PR_LEFT                   ; Consume the opening parenthesis.
    LD   A,(RO_IO)                 ; The selector.
    RRCA                           ; Shift the argument type down one bit.
    RRCA                           ; And another.
    RRCA                           ; And another, from bits 3..4.
    AND  $03                       ; Keep it.
    JR   Z,.CLOSE                  ; No argument.
    LD   D,A                       ; Keep the argument's type.
.ARG:                          ; Parse the argument.
    LD   HL,(RO_DPOS)              ; A nested call changes RO_DPOS.
    PUSH HL                        ; So keep this call's offset.
    LD   A,D                       ; The expected type.
    CALL RO_ARG                    ; Parse and check the argument.
    POP  HL                        ; Recover the offset.
    LD   (RO_DPOS),HL              ; Restore it.
.CLOSE:                        ; Close the call and publish it.
    CALL PR_RIGHT                  ; Consume the closing parenthesis.
    LD   A,(RO_IO)                 ; The selector.
    LD   (RO_DEST),A               ; RO_PUB writes it.
    AND  RO_RES8                   ; Keep the u8-result bit, bit 5.
    RLCA                           ; Rotate it toward bit 0.
    RLCA                           ; Bit 7 now.
    RLCA                           ; Bit 0: SY_U8 or zero.
.RESULT:                       ; Describe the result and failure.
    LD   (RO_DTYPE),A              ; RO_PUB writes and returns it.
    LD   A,RO_FFAIL                ; Every service can fail.
    LD   (RO_DFLAG),A              ; RO_PUB marks the failure pending.
    JP   RO_PUB                    ; Write OP_CALL and return.

;@ROUTINE IN A OUT A,CARRY,ZERO CLOBBERS SIGN,PARITY,HALFCARRY,DE,HL
; Return the declared capacity of bounded-string type A. Any other type
; raises DG_CLASH, which does not return.

RO_CAP:
    CALL AG_DESC                   ; HL addresses the type's descriptor.
    LD   A,(HL)                    ; Read its kind.
    CP   AG_KSTR                   ; Is it a bounded string?
    JP   NZ,EX_ETYPE               ; Raise DG_CLASH.
    INC  HL                        ; The capacity follows the kind.
    LD   A,(HL)                    ; Read it.
    OR   A                         ; Carry clear.
    RET                            ; A is the capacity.

;@ROUTINE OUT CARRY CLOBBERS A,BC,DE,HL,SIGN,PARITY,HALFCARRY,ZERO
; Write a call's three handling bytes as zeros and keep their address in
; RO_MODEP. The statement's `else fail` or handler sets them afterwards:
; the mode, the handler's label and the carriers kept beneath the call.

RO_PAD:
    LD   HL,(TR_PTR)               ; The handling bytes start here.
    LD   (RO_MODEP),HL             ; The actions patch them through this.
    LD   C,3                       ; Three bytes.
    XOR  A                         ; Mode zero (no handling) until the statement says more.
.LOOP:                         ; Write one byte.
    CALL TR_PUT                    ; Write zero; A is kept.
    DEC  C                         ; One fewer.
    JR   NZ,.LOOP                  ; Write all three.
    RET                            ; The bytes are reserved.

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
    LD   A,1                       ; The target's address is one carrier.
    LD   (RO_KEPT),A               ; It lies beneath a failable value.
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
    LD   A,1                       ; The target's address is one carrier.
    LD   (RO_KEPT),A               ; It lies beneath a failable source.
    CALL AC_ROUTE                  ; Attach any failure handling.
    LD   A,OP_COPY                 ; Copy the source onto the target.
    CALL TR_OPER                   ; Write the operation.
    LD   HL,(RO_OSIZE)             ; The size.
    CALL RO_EMITW                  ; Write it.
    LD   HL,(RO_DPOS)              ; The assignment's offset.
    CALL RO_EMITW                  ; Write it.
    RET                            ; The assignment is complete.
