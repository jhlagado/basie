;==========================================================================
;  Aggregate types and static initializers
;==========================================================================
;
;  Keep the table of aggregate types (records, bounded strings and arrays)
;  and parse the type-directed initializer of a program variable or an
;  aggregate constant into a staged image of the object's bytes. The
;  grammar actions (ACTIONS.ASM) build each type's candidate descriptor and
;  intern it here; at a declaration they size and zero the object, call
;  AG_PARSE, and write the staged bytes as the object's blob (RG_DATA).
;
;  Principal entries:
;    AG_REUSE  intern a string or array descriptor, sharing an identical one
;    AG_ADD    append a descriptor; records always get a new identity
;    AG_DESC   address the descriptor of a type ID
;    AG_SIZE   return the extent in bytes of any type ID
;    AG_FIELD  address a record field's entry
;    AG_FRESH  reject a field name already used in the record being declared
;    AG_FITRW  check one extent against the 1 KiB initializer staging
;    AG_ZERO   zero the object being initialized
;    AG_PARSE  parse one initializer for a type at the staging cursor
;
;  Type IDs are one byte. IDs 1..3 are the scalars u8, u16 and Boolean
;  (AG_U8, AG_U16, AG_BOOL, equal to the SY_ type codes); IDs from AG_FIRST
;  index the type table AG_TTAB, 24 four-byte descriptors (AG_TCAP):
;
;    +0  byte  kind: AG_KREC, AG_KSTR or AG_KARR
;    +1  byte  record ordinal, string capacity or array element type
;    +2  word  zero for a record, the string capacity or the element count
;
;  A parallel table AG_XTAB holds each type's extent as a word. A string of
;  capacity N occupies N+2 bytes: its length, N payload bytes and a zero
;  terminator. AG_RTAB gives each record its first field index and field
;  count; AG_FTAB holds six-byte field entries: the name's source address
;  and length, the field type and the field's byte offset in the record.
;
;  Initializer bytes are staged in AG_IBUF at the cursor AG_OPOS. The object
;  is zeroed first, so an initializer writes only what it supplies and a
;  string's padding and terminator need no writes. Nested initializers are
;  bounded at four levels (AG_LCAP). Every extent is bounded at 1024 bytes,
;  the size of the staging buffer.

;@ROUTINE IN A OUT A,HL CLOBBERS CARRY,ZERO,SIGN,PARITY,HALFCARRY,DE
; Address the four-byte descriptor of dynamic type ID A in HL. A returns the
; table index (the ID less AG_FIRST). A File has no descriptor, no fields
; and no elements: it raises DG_CLASH.

AG_DESC:
    CP   AG_FILE                   ; A File?
    JP   Z,EX_ETYPE                ; Has neither fields nor elements: DG_CLASH.
    SUB  AG_FIRST                  ; Dynamic IDs begin at AG_FIRST.
    LD   L,A                       ; Widen the table index to a word.
    LD   H,0                       ; Clear the high byte.
    ADD  HL,HL                     ; Index times two.
    ADD  HL,HL                     ; Index times four, the descriptor stride.
    LD   DE,AG_TTAB                ; Fetch the type table base.
    ADD  HL,DE                     ; Address the descriptor.
    RET                            ; Return it in HL.

;@ROUTINE IN A OUT A,HL CLOBBERS CARRY,ZERO,SIGN,PARITY,HALFCARRY,DE
; Address the extent word of dynamic type ID A in HL. A returns twice the
; table index.

AG_SIZEP:
    SUB  AG_FIRST                  ; Dynamic IDs begin at AG_FIRST.
    ADD  A,A                       ; Each extent is a word.
    LD   E,A                       ; Widen the offset in DE.
    LD   D,0                       ; Clear the high byte.
    LD   HL,AG_XTAB                ; Fetch the extent table base.
    ADD  HL,DE                     ; Address the extent word.
    RET                            ; Return it in HL.

;@ROUTINE IN A OUT HL,CARRY,ZERO CLOBBERS SIGN,PARITY,HALFCARRY,A,DE
; Return in HL the extent in bytes of type ID A, with carry clear: one for
; u8 and Boolean, two for u16, four for a File, the recorded extent for a
; dynamic type.

AG_SIZE:
    LD   HL,4                      ; A File takes four bytes.
    CP   AG_FILE                   ; Is it one?
    RET  Z                         ; Carry is clear.
    CP   AG_FIRST                  ; Is this a table type?
    JR   NC,.DYNAMIC               ; Yes: read its recorded extent.
    LD   HL,1                      ; u8 and Boolean take one byte.
    CP   AG_U16                    ; Is it the word type?
    JR   Z,.WORD                   ; Yes: it takes two.
    OR   A                         ; Clear carry for success.
    RET                            ; Return one.
.WORD:                         ; A u16 scalar.
    INC  L                         ; Two bytes.
    OR   A                         ; Clear carry for success.
    RET                            ; Return two.
.DYNAMIC:                      ; A record, string or array.
    CALL AG_SIZEP                  ; Address its extent word.
    LD   E,(HL)                    ; Fetch the low byte.
    INC  HL                        ; Step to the high byte.
    LD   D,(HL)                    ; DE now holds the extent.
    EX   DE,HL                     ; Return it in HL.
    OR   A                         ; Clear carry for success.
    RET                            ; Return the extent.

;@ROUTINE OUT A,CARRY,ZERO CLOBBERS SIGN,PARITY,HALFCARRY,BC,DE,HL
; Append the candidate descriptor (AG_NKIND, AG_NAUX, AG_NDIM) and its
; extent AG_NSIZE as a new type, returning its ID in A with carry clear. No
; existing type is searched, so each record declared gets its own identity.
; A full type table raises DG_META.

AG_ADD:
    LD   A,(AG_TCNT)               ; Fetch the number of table types.
    CP   AG_TCAP                   ; Is there room for one more?
    JR   NC,AG_EMETA               ; No: the type table is full.
    ADD  A,AG_FIRST                ; Form the new type's ID.
    CALL AG_DESC                   ; Address its descriptor slot.
    LD   D,H                       ; The slot is the copy's destination.
    LD   E,L                       ; Complete DE.
    LD   HL,AG_NKIND               ; The candidate's four bytes are the source.
    LD   BC,AG_TLEN                ; Copy one descriptor.
    LDIR                           ; Kind, auxiliary byte and dimension word.
    LD   A,(AG_TCNT)               ; Recover the new slot's index.
    ADD  A,AG_FIRST                ; Form its ID again.
    LD   C,A                       ; Keep the ID for the return.
    CALL AG_SIZEP                  ; Address its extent word.
    LD   DE,(AG_NSIZE)             ; Fetch the candidate's extent.
    LD   (HL),E                    ; Record its low byte.
    INC  HL                        ; Step to the high byte.
    LD   (HL),D                    ; Record its high byte.
    LD   HL,AG_TCNT                ; Address the type count.
    INC  (HL)                      ; Publish the new type.
    LD   A,C                       ; Return its ID.
    OR   A                         ; Clear carry; the ID is nonzero.
    RET                            ; Return to the type action.
AG_EMETA:                      ; A type, record or field table is full.
    CALL DG_RAISE                  ; Report it; no return.
    DB   DG_META                   ; Diagnostic: too much type metadata.

;@ROUTINE OUT A,CARRY,ZERO CLOBBERS SIGN,PARITY,HALFCARRY,BC,DE,HL
; Intern the candidate string or array descriptor: return the ID of an
; identical existing descriptor, or append the candidate through AG_ADD.
; The candidate's four bytes and extent must already be complete.

AG_REUSE:
    LD   A,(AG_TCNT)               ; Fetch the number of table types.
    OR   A                         ; With none, nothing can match.
    JR   Z,AG_ADD                  ; Append the first type.
    LD   B,A                       ; B counts the types left to compare.
    LD   C,AG_FIRST                ; C is the ID being compared.
.TYPELOOP:                     ; Compare one descriptor per iteration.
    LD   A,C                       ; Select this type.
    CALL AG_DESC                   ; Address its descriptor.
    LD   DE,AG_NKIND               ; Compare it with the candidate.
    PUSH BC                        ; Keep the count and ID; B counts bytes.
    LD   B,AG_TLEN                 ; Compare all four bytes.
.BYTELOOP:                     ; Compare one descriptor byte.
    LD   A,(DE)                    ; Fetch the candidate's byte.
    CP   (HL)                      ; Does the table byte agree?
    JR   NZ,.DIFFER                ; No: try the next type.
    INC  DE                        ; Step through the candidate.
    INC  HL                        ; Step through the descriptor.
    DJNZ .BYTELOOP                 ; Continue through the four bytes.
    POP  BC                        ; Restore the ID of the match.
    JR   .FOUND                    ; Share the existing type.
.DIFFER:                       ; This type differs from the candidate.
    POP  BC                        ; Restore the count and ID.
    INC  C                         ; Step to the next ID.
    DJNZ .TYPELOOP                 ; Continue through the table.
    JR   AG_ADD                    ; No match: append the candidate.
.FOUND:                        ; An identical type exists.
    LD   A,C                       ; Return its ID.
    OR   A                         ; Clear carry; the ID is nonzero.
    RET                            ; Return to the type action.

;@ROUTINE IN HL OUT A,HL,CARRY,ZERO CLOBBERS SIGN,PARITY,HALFCARRY
; Accept an extent HL of at most 1024 bytes ($0400), the size of the
; initializer staging (AG_ICAP), with carry clear; a larger one raises
; DG_DATA. Used for one object, array or record.

AG_FITRW:
    LD   A,H                       ; Judge the extent by its high byte first.
    CP   4                         ; Below $0400 always fits.
    JR   C,.OK                     ; Accept it.
    JR   NZ,.FULL                  ; Above $04FF never fits.
    LD   A,L                       ; Between them only $0400 itself fits.
    OR   A                         ; Is the low byte zero?
    JR   NZ,.FULL                  ; No: it exceeds the staging.
.OK:                           ; The extent fits.
    OR   A                         ; Clear carry for success.
    RET                            ; Return the extent unchanged.
.FULL:                         ; The extent exceeds the staging.
    CALL DG_RAISE                  ; Report it; no return.
    DB   DG_DATA                   ; Diagnostic: program data too large.

; Failure exits shared with the type and declaration actions. None returns.

AG_EVIEW:                      ; An open string where it can't be.
    CALL DG_RAISE                  ; Report it.
    DB   DG_CLASH                  ; Diagnostic: a parameter type only.
AG_EWIDE:                      ; An extent past 65,535 bytes.
    CALL DG_RAISE                  ; Report it.
    DB   DG_RANGE                  ; Diagnostic: out-of-range.
AG_EBND:                       ; A bound out of range, or not a constant:
    LD   A,DG_RANGE                ; out-of-range,
AG_EVAL:                       ; or A,
    JP   EX_EVAL                   ; at the bound's first token.

;@ROUTINE IN A OUT A,HL CLOBBERS CARRY,ZERO,SIGN,PARITY,HALFCARRY,DE
; Address the six-byte entry of record field index A in HL. A is preserved.

AG_FIELD:
    LD   E,A                       ; Widen the field index in DE.
    LD   D,0                       ; Clear the high byte.
    LD   H,D                       ; Copy the index into HL as well.
    LD   L,E                       ; HL = index.
    ADD  HL,HL                     ; HL = index times two.
    ADD  HL,DE                     ; HL = index times three.
    ADD  HL,HL                     ; HL = index times six, the entry stride.
    LD   DE,AG_FTAB                ; Fetch the field table base.
    ADD  HL,DE                     ; Address the entry.
    RET                            ; Return it in HL.

;@ROUTINE OUT A,CARRY,ZERO CLOBBERS SIGN,PARITY,HALFCARRY,BC,DE,HL
; Compare the current NAME token with the fields already declared in the
; record being declared (AG_CFCNT fields from index AG_CFIDX). A repeated
; field name raises DG_DUP; otherwise return carry clear.

AG_FRESH:
    LD   A,(AG_CFCNT)              ; Fetch this record's field count so far.
    OR   A                         ; The first field cannot repeat.
    RET  Z                         ; Return carry clear from the OR.
    LD   C,A                       ; C counts the fields left to compare.
    LD   A,(AG_CFIDX)              ; A is the record's first field index.
.LOOP:                         ; Compare one field per iteration.
    PUSH AF                        ; Keep the field index.
    PUSH BC                        ; Keep the count; TK_SAME needs no BC.
    CALL AG_FIELD                  ; Address this field's entry.
    CALL TK_SAME                   ; Is its name the token's spelling?
    JR   C,.UNWIND                 ; Yes: the name repeats.
    POP  BC                        ; Restore the count.
    POP  AF                        ; Restore the field index.
    INC  A                         ; Step to the next field.
    DEC  C                         ; One fewer field to compare.
    JR   NZ,.LOOP                  ; Continue through the record's fields.
    OR   A                         ; Report no repeat with carry clear.
    RET                            ; Return to the field action.
.UNWIND:                       ; A field of this name already exists.
    POP  BC                        ; Balance the stack.
    POP  AF                        ; Balance the stack.
    JP   EX_EDUP                   ; Report the duplicate name.

; Further failure exits. Neither returns.

AG_EVOID:                      ; A record type with no fields.
    CALL DG_RAISE                  ; Report it.
    DB   DG_EMPTY                  ; Diagnostic: empty record.

AG_EDEEP:                      ; Initializers nested beyond AG_LCAP.
    CALL DG_RAISE                  ; Report it.
    DB   DG_INITS                  ; Diagnostic: initializers nested too deeply.

;@ROUTINE OUT CARRY CLOBBERS SIGN,PARITY,HALFCARRY,ZERO,HL
; Close one level of initializer nesting. A is preserved.

AG_LEAVE:
    LD   HL,AG_LEVEL               ; Address the nesting depth.
    DEC  (HL)                      ; One level fewer is open.
    OR   A                         ; Clear carry for success.
    RET                            ; Return to the initializer parser.

;@ROUTINE IN A OUT A,CARRY,ZERO CLOBBERS SIGN,PARITY,HALFCARRY,B,DE,HL
; Store byte A at the staging cursor and advance the cursor. The object's
; extent has passed AG_FITRW, so the cursor stays inside AG_IBUF.

AG_PUT:
    LD   B,A                       ; Keep the byte while addressing.
    LD   HL,(AG_OPOS)              ; Fetch the cursor offset.
    LD   DE,AG_IBUF                ; Fetch the staging buffer base.
    ADD  HL,DE                     ; Address the cursor byte.
    LD   A,B                       ; Recover the byte.
    LD   (HL),A                    ; Stage it.
    LD   HL,(AG_OPOS)              ; Fetch the cursor offset again.
    INC  HL                        ; Advance past the byte.
    LD   (AG_OPOS),HL              ; Publish the advanced cursor.
    OR   A                         ; Clear carry for success.
    RET                            ; Return the byte in A.

;@ROUTINE IN B OUT A,B,CARRY,ZERO CLOBBERS SIGN,PARITY,HALFCARRY,C,DE,HL
; Stage the current string literal as a bounded string of capacity B: the
; length byte, then the payload decoded straight from the resident source
; (AG_CHAR). TK_LEN is the decoded length and TK_PTR addresses the opening
; quote. The object is already zero, so the cursor simply skips the
; padding and the terminator.

AG_TEXT:
    LD   A,(TK_LEN)                ; Fetch the decoded length.
    LD   C,A                       ; C counts the characters to decode.
    PUSH BC                        ; Keep capacity and count across the put.
    CALL AG_PUT                    ; Stage the length byte.
    POP  BC                        ; Restore capacity and count.
    LD   A,B                       ; Start from the capacity.
    SUB  C                         ; Less the length gives the padding.
    LD   B,A                       ; B is the padding byte count.
    LD   HL,(TK_PTR)               ; Address the opening quote.
    INC  HL                        ; Step to the first character.
.LOOP:                         ; Decode one character per iteration.
    LD   A,C                       ; Are characters left?
    OR   A                         ; Test the count.
    JR   Z,.PAD                    ; No: skip the padding.
    CALL AG_CHAR                   ; A is the next byte, decoded.
    PUSH BC                        ; Keep padding and count across the put.
    PUSH HL                        ; Keep the source pointer.
    CALL AG_PUT                    ; Stage the byte.
    POP  HL                        ; Restore the source pointer.
    POP  BC                        ; Restore padding and count.
    DEC  C                         ; One character fewer to decode.
    JR   .LOOP                     ; Continue with the next.
.PAD:                          ; The payload is staged.
    LD   E,B                       ; Widen the padding count in DE.
    LD   D,0                       ; Clear the high byte.
    INC  DE                        ; Add the terminator at capacity plus one.
    LD   HL,(AG_OPOS)              ; Fetch the cursor.
    ADD  HL,DE                     ; Skip the zeroed padding and terminator.
    LD   (AG_OPOS),HL              ; Publish the cursor past the string.
    OR   A                         ; Clear carry for success.
    RET                            ; Return to the initializer parser.

;@ROUTINE IN HL OUT A,HL CLOBBERS CARRY,ZERO,SIGN,PARITY,HALFCARRY
; Decode the string literal's character at HL, which the tokenizer has
; checked, into A, and step HL past it. Escapes are \xHH, \0, \n, \r and
; \t; any other escaped character stands for itself. BC and DE are kept.

AG_CHAR:                       ; HL is the source.
    LD   A,(HL)                    ; Fetch a source character.
    INC  HL                        ; Consume it.
    CP   '\\'                      ; Does a backslash begin an escape?
    RET  NZ                        ; No: it is the byte.
    LD   A,(HL)                    ; Fetch the escape letter.
    INC  HL                        ; Consume it.
    CP   'x'                       ; Two hexadecimal digits follow?
    JR   Z,.HEX                    ; Decode them.
    PUSH BC                        ; Keep the caller's BC.
    LD   C,0                       ; \0 is a NUL byte,
    CP   '0'                       ; if it is one;
    JR   Z,.CODE                   ; return it.
    LD   C,10                      ; \n is a line feed,
    CP   'n'                       ; if it is one;
    JR   Z,.CODE                   ; return it.
    LD   C,13                      ; \r is a carriage return,
    CP   'r'                       ; if it is one;
    JR   Z,.CODE                   ; return it.
    LD   C,9                       ; \t is a tab,
    CP   't'                       ; if it is one;
    JR   NZ,.SAME                  ; otherwise the letter stands for itself.
.CODE:                         ; C is the byte.
    LD   A,C                       ; Return it.
.SAME:                         ; A is the byte.
    POP  BC                        ; Restore BC.
    RET                            ; Done.
.HEX:                          ; \xHH: two digits follow.
    PUSH DE                        ; Keep the caller's DE.
    LD   A,(HL)                    ; Fetch the high digit.
    INC  HL                        ; Consume it.
    CALL TK_HEX                    ; Convert it to a nibble.
    ADD  A,A                       ; Shift it up one bit.
    ADD  A,A                       ; Two bits.
    ADD  A,A                       ; Three bits.
    ADD  A,A                       ; Into the high nibble.
    LD   D,A                       ; Keep the high nibble.
    LD   A,(HL)                    ; Fetch the low digit.
    INC  HL                        ; Consume it.
    CALL TK_HEX                    ; Convert it to a nibble.
    OR   D                         ; Combine the two nibbles.
    POP  DE                        ; Restore DE.
    RET                            ; A is the byte.

; Initializer and literal failures, reported as the reference's
; staticInitializer reports them. None returns.

AG_ELONG:                      ; A string literal longer than its string.
    CALL DG_RAISE                  ; Report it.
    DB   DG_RANGE                  ; Diagnostic: out-of-range.
AG_ECNT:                       ; Anything but a comma between two items.
    CALL DG_RAISE                  ; Report it: the comma
    DB   DG_COMMA                  ; is expected (syntax).

;@ROUTINE OUT A,CARRY,ZERO CLOBBERS SIGN,PARITY,HALFCARRY,D,DE,HL
; Peek at the next token kind, preserving BC for the item loops.

AG_PEEK:
    PUSH BC                        ; Keep the caller's loop state.
    CALL PR_PEEK                   ; Fetch the next token kind.
    POP  BC                        ; Discard the token value; restore BC.
    RET                            ; Return the kind in A.

;@ROUTINE OUT A,CARRY,ZERO CLOBBERS SIGN,PARITY,HALFCARRY,D,DE,HL
; Consume the next token, preserving BC for the item loops.

AG_TAKE:
    PUSH BC                        ; Keep the caller's loop state.
    CALL PR_TAKE                   ; Consume the token.
    POP  BC                        ; Discard the token value; restore BC.
    RET                            ; Return the kind in A.

;@ROUTINE OUT A,CARRY,ZERO CLOBBERS SIGN,PARITY,HALFCARRY,D,DE,HL
; Consume the comma between two items: anything else, a close before the
; last item among them, is syntax, the comma expected. BC is preserved.

AG_COMMA:
    CALL AG_PEEK                   ; The token after the item.
    CP   TK_COMMA                  ; Does a comma separate the items?
    JR   NZ,AG_ECNT                ; No: one is expected.
    JR   AG_TAKE                   ; Consume the comma.

;@ROUTINE IN A OUT A,CARRY,ZERO CLOBBERS SIGN,PARITY,HALFCARRY,B,C,D,DE,HL,IX,IY
; Parse one initializer for type ID A at the staging cursor, advancing the
; cursor by the type's extent. A scalar takes a constant expression that
; fits the type; a string a string literal; a record a parenthesized list
; of its fields; an array a bracketed list of its elements.

AG_PARSE:
    CP   AG_FIRST                  ; Is this a scalar type?
    JR   C,.SCALAR                 ; Yes: parse a constant.
    PUSH AF                        ; Keep the type ID.
    CALL AG_DESC                   ; Address its descriptor.
    LD   A,(HL)                    ; Fetch the kind.
    POP  DE                        ; D is the type ID.
    LD   E,D                       ; Move it to E.
    LD   D,0                       ; DE is the type ID for the kind handler.
    CP   AG_KSTR                   ; A bounded string?
    JR   Z,.STRING                 ; Parse a string literal.
    CP   AG_KREC                   ; A record?
    JR   Z,AG_REC                  ; Parse its field list.
    CP   AG_KARR                   ; An array?
    JP   Z,AG_ARRAY                ; Parse its element list.
    CALL DG_RAISE                  ; Defensive: no other kind is interned.
    DB   DG_BUG                    ; Diagnostic: internal.

.SCALAR:                       ; u8, u16 or Boolean.
    LD   E,A                       ; E is the destination type for EX_FITS.
    PUSH DE                        ; Keep it across the expression.
    CALL EX_CONST                  ; Parse a constant expression of type A.
    POP  DE                        ; Restore the destination type.
    CALL EX_FITS                   ; Check assignment compatibility.
    AND  SY_KNOWN                  ; Was the value known at compile time?
    LD   A,DG_KNOWN                ; No: a static initializer must be,
    JP   Z,EX_EVAL                 ; reported at the value (not-constant).
    LD   A,L                       ; Fetch the value's low byte.
    PUSH DE                        ; Keep the type across the put.
    PUSH HL                        ; Keep the value.
    CALL AG_PUT                    ; Stage the low byte.
    POP  HL                        ; Restore the value.
    POP  DE                        ; Restore the type.
    LD   A,E                       ; Is it the word type?
    CP   AG_U16                    ; Only u16 has a second byte.
    JR   Z,.UPPER                  ; Stage the high byte too.
    OR   A                         ; Clear carry for success.
    RET                            ; One byte staged.
.UPPER:                        ; Second byte of a u16.
    LD   A,H                       ; Fetch the high byte.
    JP   AG_PUT                    ; Stage it and return.

.STRING:                       ; A bounded string.
    EX   DE,HL                     ; Bring the type ID into L.
    LD   A,L                       ; Select it again.
    CALL AG_DESC                   ; Address its descriptor.
    INC  HL                        ; Step to the auxiliary byte.
    LD   B,(HL)                    ; B is the string's capacity.
    PUSH BC                        ; Keep it across the token check.
    LD   E,TK_TEXT                 ; A string literal must follow.
    CALL PR_NEED                   ; Consume it or report the token.
    POP  BC                        ; Restore the capacity.
    LD   A,(TK_LEN)                ; Fetch the literal's decoded length.
    CP   B                         ; Compare it with the capacity.
    JR   C,.DECODE                 ; Shorter fits.
    JR   Z,.DECODE                 ; Exactly full fits.
    JR   AG_ELONG                  ; Longer does not; report it.
.DECODE:                       ; The literal fits.
; AG_ZERO has already zeroed the whole object, so decoding need write only
; the length and payload bytes.
    JP   AG_TEXT                   ; Stage it and return.

;@ROUTINE IN A OUT A,CARRY,ZERO CLOBBERS SIGN,PARITY,HALFCARRY,D,DE,HL
; Consume the opening bracket A of a record or array initializer and open
; one nesting level. Any other token is syntax, the bracket expected; a
; fifth level raises DG_INITS. BC is preserved.

AG_ENTER:
    PUSH AF                        ; Keep the expected bracket.
    CALL AG_PEEK                   ; Fetch the next token kind.
    POP  DE                        ; D is the expected bracket.
    CP   D                         ; Does the initializer open with it?
    JR   NZ,AG_EWANT               ; No: the bracket is expected.
    CALL AG_TAKE                   ; Consume the bracket.
    LD   A,(AG_LEVEL)              ; Fetch the nesting depth.
    CP   AG_LCAP                   ; Is another level allowed?
    JP   NC,AG_EDEEP               ; No: nested too deeply.
    INC  A                         ; Open one more level.
    LD   (AG_LEVEL),A              ; Publish the depth.
    OR   A                         ; Clear carry for success.
    RET                            ; Return to the list parser.

; Parse a record initializer, ( field, field, ... ), with one item for each
; field in declaration order. DE is the record's type ID. Entered by jump
; from AG_PARSE and returns through AG_CLOSE.

AG_REC:
    EX   DE,HL                     ; Bring the type ID into L.
    LD   A,L                       ; Select it again.
    CALL AG_DESC                   ; Address its descriptor.
    INC  HL                        ; Step to the record ordinal.
    LD   A,(HL)                    ; Fetch it.
    ADD  A,A                       ; AG_RTAB entries are two bytes.
    LD   E,A                       ; Widen the offset in DE.
    LD   D,0                       ; Clear the high byte.
    LD   HL,AG_RTAB                ; Fetch the record table base.
    ADD  HL,DE                     ; Address the record's entry.
    LD   B,(HL)                    ; B is the first field index.
    INC  HL                        ; Step to the field count.
    LD   C,(HL)                    ; C counts the fields to initialize.
    LD   A,TK_LPAR                 ; A record initializer opens with '('.
    CALL AG_ENTER                  ; Consume it and nest one level.
.LOOP:                         ; Parse one field's initializer.
    PUSH BC                        ; Keep the field index and count.
    LD   A,B                       ; Select the field.
    CALL AG_FIELD                  ; Address its entry.
    INC  HL                        ; Skip the name's address low byte.
    INC  HL                        ; Skip its high byte.
    INC  HL                        ; Skip the length; HL at the field type.
    LD   A,(HL)                    ; Fetch the field's type.
    CALL AG_PARSE                  ; Parse its initializer recursively.
    POP  BC                        ; Restore the field index and count.
    INC  B                         ; Step to the next field.
    DEC  C                         ; One fewer field to initialize.
    JR   Z,.CLOSE                  ; All fields done: expect the close.
    CALL AG_COMMA                  ; Require and consume a comma.
    JR   .LOOP                     ; Parse the next field.
.CLOSE:                        ; Every field has its item.
    LD   D,TK_RPAR                 ; Expect ')'.
    JR   AG_CLOSE                  ; Close the list and return.

; Parse an array initializer, [ item, item, ... ], with exactly one item for
; each element. DE is the array's type ID. Entered by jump from AG_PARSE;
; falls into AG_CLOSE.

AG_ARRAY:
    EX   DE,HL                     ; Bring the type ID into L.
    LD   A,L                       ; Select it again.
    CALL AG_DESC                   ; Address its descriptor.
    INC  HL                        ; Step to the element type.
    LD   C,(HL)                    ; C is the element type.
    INC  HL                        ; Step to the element count.
    LD   E,(HL)                    ; Fetch its low byte.
    INC  HL                        ; Step to the high byte.
    LD   D,(HL)                    ; DE counts the elements to initialize.
    PUSH BC                        ; Keep the element type.
    PUSH DE                        ; Keep the count.
    LD   A,TK_LBRAC                ; An array initializer opens with '['.
    CALL AG_ENTER                  ; Consume it and nest one level.
    POP  DE                        ; Restore the count.
    POP  BC                        ; Restore the element type.
.LOOP:                         ; Parse one element's initializer.
    PUSH BC                        ; Keep the element type.
    PUSH DE                        ; Keep the count.
    LD   A,C                       ; Select the element type.
    CALL AG_PARSE                  ; Parse its initializer recursively.
    POP  DE                        ; Restore the count.
    POP  BC                        ; Restore the element type.
    DEC  DE                        ; One fewer element to initialize.
    LD   A,D                       ; Is the count exhausted?
    OR   E                         ; Test both bytes.
    JR   Z,.CLOSE                  ; Yes: expect the close.
    PUSH DE                        ; AG_COMMA clobbers DE.
    CALL AG_COMMA                  ; Require and consume a comma.
    POP  DE                        ; Restore the count.
    JR   .LOOP                     ; Parse the next element.
.CLOSE:                        ; Every element has its item.
    LD   D,TK_RBRAC                ; Expect ']'.

;@ROUTINE IN D OUT CARRY CLOBBERS SIGN,PARITY,HALFCARRY,ZERO,A,BC,DE,HL
; Close an initializer list: D is the closing bracket, which must follow
; the last item; anything else, another item among them, is syntax, the
; bracket expected. Closes one nesting level.

AG_CLOSE:
    PUSH DE                        ; Keep the bracket.
    CALL AG_PEEK                   ; Fetch the token after the last item.
    POP  DE                        ; D is the bracket.
    CP   D                         ; Is it the expected close?
    JR   NZ,AG_EWANT               ; No: it is expected.
    CALL PR_TAKE                   ; Consume the bracket.
    JP   AG_LEAVE                  ; Close the nesting level and return.

;@ROUTINE IN D NORETURN
; Raise syntax at the current token: token kind D expected.

AG_EWANT:
    LD   A,D                       ; The kind
    OR   DG_TOKEN                  ; expected,
    JP   DG_ISSUE                  ; at the token.

;@ROUTINE OUT A,CARRY,ZERO CLOBBERS SIGN,PARITY,HALFCARRY,BC,DE,HL
; Zero the AG_OSIZE bytes of the object at the staging cursor before an
; explicit initializer is applied. This also makes every byte of an object
; with no initializer defined. Returns A zero with carry clear.

AG_ZERO:
    LD   HL,(AG_OPOS)              ; Fetch the cursor offset.
    LD   DE,AG_IBUF                ; Fetch the staging buffer base.
    ADD  HL,DE                     ; Address the object's first byte.
    LD   BC,(AG_OSIZE)             ; BC counts the object's bytes.
.LOOP:                         ; Zero one byte per iteration.
    LD   A,B                       ; Are bytes left?
    OR   C                         ; Test both bytes of the count.
    RET  Z                         ; No: return A zero, carry clear.
    XOR  A                         ; Form zero.
    LD   (HL),A                    ; Zero this byte.
    INC  HL                        ; Step to the next.
    DEC  BC                        ; One fewer byte to zero.
    JR   .LOOP                     ; Continue through the object.
