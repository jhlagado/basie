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
;    AG_SCOPE  release the types a routine's body made, at its end
;
;  Type IDs are one byte. IDs 1..8 are the scalars, the SY_ type codes
;  (STATE.ASM): u8, u16, Boolean, i8, i16, u32, i32 and f32; IDs from AG_FIRST
;  index the type table AG_TTAB, 48 four-byte descriptors (AG_TCAP),
;  IDs below the open arrays' (AG_OPEN):
;
;    +0  byte  kind: AG_KREC, AG_KSTR or AG_KARR
;    +1  byte  record ordinal, string capacity or array element type
;    +2  word  zero for a record, the string capacity or the element count
;
;  A parallel table AG_XTAB holds each type's extent as a word. A string of
;  capacity N occupies N+2 bytes: its length, N payload bytes and a zero
;  terminator. AG_RTAB gives each record its first field index and field
;  count and where its fields lie: each field is a record of the symbol
;  table, in no chain, whose first six bytes are the name's address and
;  length, the field type and the field's byte offset in the record.
;
;  Initializer bytes are staged in AG_IBUF at the cursor AG_OPOS. The object
;  is zeroed first, so an initializer writes only what it supplies and a
;  string's padding and terminator need no writes. Nested initializers are
;  bounded at 32 levels (AG_LCAP) and by the machine stack (PR_ROOM). Every
;  extent is bounded at 1024 bytes, the size of the staging buffer.

;@ROUTINE CLOBBERS A,B,DE,HL,CARRY,ZERO,SIGN,PARITY,HALFCARRY
; A routine's body has ended, its blob written: the types its body made
; (from RO_TBASE to AG_TCNT), which only its locals and constants could
; have, are released, their IDs free for the types made next, and their
; owner descriptors' ordinals (PL_DESC) and owning bits (PL_OWNB) cleared
; for those. Records, the types that last, are declared only at top level.

AG_SCOPE:                      ; The body has ended.
    LD   A,(AG_TCNT)               ; The types so far,
    LD   B,A                       ; B of them;
    LD   A,(RO_TBASE)              ; those before the body's
    LD   (AG_TCNT),A               ; stay.
.TYPE:                         ; A is the next index released.
    CP   B                         ; Any
    RET  NC                        ; left?
    PUSH AF                        ; (the index)
    CALL PL_OWNAT                  ; Its owning bit,
    CPL                            ; A, in byte HL,
    AND  (HL)                      ; is
    LD   (HL),A                    ; cleared;
    POP  AF                        ; its
    PUSH AF                        ; descriptor's
    ADD  A,A                       ; ordinal,
    LD   E,A                       ; a
    LD   D,0                       ; word
    LD   HL,PL_DESC                ; of the
    ADD  HL,DE                     ; cache,
    XOR  A                         ; is
    LD   (HL),A                    ; zero
    INC  HL                        ; again.
    LD   (HL),A                    ; (Both bytes.)
    POP  AF                        ; The
    INC  A                         ; next.
    JR   .TYPE                     ; Until all are.

;@ROUTINE IN A OUT HL CLOBBERS A,DE,CARRY,ZERO,SIGN,PARITY,HALFCARRY
; Address in HL the AG_RTAB entry of record ordinal A: its first field's
; index, then its field count, then its first field's record. BC is kept.

AG_RENT:                       ; A is the record's ordinal.
    ADD  A,A                       ; AG_RTAB entries are
    ADD  A,A                       ; four bytes:
    LD   E,A                       ; DE is
    LD   D,0                       ; the offset,
    LD   HL,AG_RTAB                ; from
    ADD  HL,DE                     ; the table's base.
    RET                            ; HL is the entry.

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

;@ROUTINE IN A OUT CARRY CLOBBERS ZERO,SIGN,PARITY,HALFCARRY
; Carry when type A is a view, an open string or an open array, a
; parameter type only. A is kept.

AG_ISVW:                       ; A is the type.
    CP   AG_VIEW                   ; An open string
    SCF                            ; is
    RET  Z                         ; one;
    CP   AG_OPEN                   ; below the open arrays
    CCF                            ; nothing
    RET  NC                        ; is,
    CP   AG_OLIM                   ; nor above them.
    RET                            ; Carry for an open array.

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
; Return in HL the extent in bytes of type ID A, with carry clear: a
; scalar's size (GX_PROP), four for a File, the recorded extent for a
; dynamic type.

AG_SIZE:
    LD   HL,4                      ; A File takes four bytes.
    CP   AG_FILE                   ; Is it one?
    RET  Z                         ; Carry is clear.
    CP   AG_HND                    ; A handle?
    JR   C,.TABLE                  ; Below them.
    CP   AG_HEND                   ; Past
    JR   NC,.TABLE                 ; them.
    BIT  1,A                       ; AG_HID: an identifier
    RET  NZ                        ; takes four bytes,
    LD   L,2                       ; an owner two
    OR   A                         ; (carry clear).
    RET                            ; Return it.
.TABLE:                        ; Not a handle.
    CP   AG_FIRST                  ; Is this a table type?
    JR   NC,.DYNAMIC               ; Yes: read its recorded extent.
    CALL GX_PROP                   ; A scalar: its size
    AND  7                         ; in bytes
    LD   L,A                       ; is HL
    LD   H,0                       ; (carry clear).
    RET                            ; Return it.
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
    ADD  A,AG_FIRST                ; Form the new type's ID,
    PUSH AF                        ; kept across the copy.
    CALL AG_DESC                   ; Address its descriptor slot.
    LD   D,H                       ; The slot is the copy's destination.
    LD   E,L                       ; Complete DE.
    LD   HL,AG_NKIND               ; The candidate's four bytes are the source.
    LD   BC,AG_TLEN                ; Copy one descriptor.
    LDIR                           ; Kind, auxiliary byte and dimension word.
    POP  AF                        ; The new type's ID,
    LD   C,A                       ; kept for the return.
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
    POP  BC                        ; Restore the ID of the match:
    LD   A,C                       ; return it, an identical type.
    OR   A                         ; Clear carry; the ID is nonzero.
    RET                            ; Return to the type action.
.DIFFER:                       ; This type differs from the candidate.
    POP  BC                        ; Restore the count and ID.
    INC  C                         ; Step to the next ID.
    DJNZ .TYPELOOP                 ; Continue through the table.
    JR   AG_ADD                    ; No match: append the candidate.

;@ROUTINE IN HL OUT HL,CARRY CLOBBERS A,ZERO,SIGN,PARITY,HALFCARRY
; Accept an extent HL of at most 1024 bytes ($0400), the size of the
; initializer staging (AG_ICAP), with carry clear; a larger one raises
; DG_DATA. Used for one object, array or record.

AG_FITRW:
    LD   A,L                       ; HL less $0401
    CP   1                         ; borrows
    LD   A,H                       ; exactly when
    SBC  A,4                       ; HL is at most $0400.
    JR   NC,AG_EDATA               ; No borrow: it exceeds the staging.
    CCF                            ; Clear carry for success.
    RET                            ; Return the extent unchanged.

;@ROUTINE NORETURN
; The initializer staging, or a routine's frame, is too large: DG_DATA
; (Error 190, object size).

AG_EDATA:                      ; Too large.
    CALL DG_RAISE                  ; Report it; no return.
    DB   DG_DATA                   ; Diagnostic: program data too large.

;@ROUTINE IN A OUT CARRY,ZERO CLOBBERS SIGN,PARITY,HALFCARRY,HL
; Refuse a view, type A, where only a parameter may have one
; (refuseOpenView): type-mismatch at the type's first token (AG_TPOS). A
; is kept.

AG_NOVW:                       ; A is the type.
    CALL AG_ISVW                   ; A view?
    RET  NC                        ; No; otherwise refused.

; Failure exits shared with the type and declaration actions. None returns.

AG_EVIEW:                      ; A view where it can't be.
    LD   A,DG_CLASH                ; type-mismatch,
    LD   HL,AG_TPOS                ; at the type.
    JP   DG_AT                     ; No return.
AG_EBND:                       ; A bound out of range, or not a constant:
    LD   A,DG_RANGE                ; out-of-range,
AG_EVAL:                       ; or A,
    JP   EX_EVAL                   ; at the bound's first token.

;@ROUTINE IN A OUT A,HL CLOBBERS CARRY,ZERO,SIGN,PARITY,HALFCARRY,DE
; Address the entry of record field index A in HL: in the record whose
; fields' indices hold it (AG_RTAB), or, past the fields of the records
; declared (AG_FCNT), in the record being declared, from AG_CFIDX at
; AG_CFADR; a record's fields are consecutive symbol-table records. A
; and BC are preserved.

AG_FIELD:                      ; A is a field's index.
    PUSH BC                        ; Keep BC.
    LD   C,A                       ; C is the index.
    LD   HL,AG_FCNT                ; A declared
    CP   (HL)                      ; record's?
    JR   C,.DECL                   ; Yes.
    LD   HL,AG_CFIDX               ; The current one's:
    SUB  (HL)                      ; from its first,
    LD   HL,(AG_CFADR)             ; at its first record.
    JR   .AT                       ; There.
.DECL:                         ; Find the record holding it:
    LD   HL,AG_RTAB                ; from the first.
.SCAN:                         ; HL is a record's entry.
    LD   A,C                       ; The index
    SUB  (HL)                      ; less its first field's,
    INC  HL                        ; if not below it,
    JR   C,.NEXT                   ; and
    CP   (HL)                      ; below its count,
    JR   C,.FOUND                  ; is the field's place in it.
.NEXT:                         ; Not this record's:
    INC  HL                        ; the
    INC  HL                        ; next
    INC  HL                        ; entry.
    JR   .SCAN                     ; It is there.
.FOUND:                        ; A is the place, HL at the count.
    INC  HL                        ; Its first
    LD   E,(HL)                    ; field's
    INC  HL                        ; record,
    LD   H,(HL)                    ; HL.
    LD   L,E                       ; (low byte)
.AT:                           ; HL is the first field, A the place.
    PUSH HL                        ; (kept)
    LD   L,A                       ; The place
    LD   H,0                       ; times
    ADD  HL,HL                     ; four,
    ADD  HL,HL                     ; (DE)
    LD   D,H                       ; then
    LD   E,L                       ; eight,
    ADD  HL,HL                     ; then twelve:
    ADD  HL,DE                     ; SY_RECB
    POP  DE                        ; from the first
    ADD  HL,DE                     ; field.
    LD   A,C                       ; A again,
    POP  BC                        ; and BC.
    RET                            ; HL is the entry.

;@ROUTINE OUT A,CARRY,ZERO CLOBBERS SIGN,PARITY,HALFCARRY,BC,DE,HL
; Compare the name of the field entry at HL, made the current NAME, with
; the fields already declared in the record being declared (AG_CFCNT fields
; from index AG_CFIDX). A repeated field name raises DG_DUP, naming it, at
; it, after its type's checks as the reference makes them; otherwise
; return carry clear, the current token's TK_PTR and TK_LEN restored.

AG_FRESH:                      ; HL is the new field's entry.
    LD   DE,(TK_PTR)               ; The current
    PUSH DE                        ; token's
    LD   A,(TK_LEN)                ; spelling,
    PUSH AF                        ; kept.
    CALL WD_GET                    ; Its name's spelling and
    LD   A,(HL)                    ; length
    LD   (TK_PTR),DE               ; are the
    LD   (TK_LEN),A                ; current NAME.
    LD   A,(AG_CFCNT)              ; Fetch this record's field count so far.
    OR   A                         ; The first field cannot repeat.
    JR   Z,.FRESH                  ; Carry clear from the OR.
    LD   B,A                       ; B counts the fields left to compare.
    LD   A,(AG_CFIDX)              ; A is the record's first field index.
.LOOP:                         ; Compare one field per iteration.
    PUSH AF                        ; Keep the field index.
    PUSH BC                        ; Keep the count; TK_SAME needs no BC.
    CALL AG_FIELD                  ; Address this field's entry.
    CALL TK_SAME                   ; Is its name the token's spelling?
    JR   C,.DUP                    ; Yes: report the duplicate.
    POP  BC                        ; Restore the count.
    POP  AF                        ; Restore the field index.
    INC  A                         ; Step to the next field.
    DJNZ .LOOP                     ; Continue through the record's fields.
.FRESH:                        ; No repeat:
    POP  AF                        ; the current
    LD   (TK_LEN),A                ; token's
    POP  DE                        ; spelling
    LD   (TK_PTR),DE               ; again,
    OR   A                         ; with carry clear.
    RET                            ; Return to the field action.
.DUP:                          ; The name repeats a field's.
    LD   HL,TK_PTR                 ; It
    LD   A,DG_DUP                  ; is named
    CALL DG_SETN                   ; by duplicate-name,
    JP   DG_KEPT                   ; at it (AC_FIELD); no return.

; A further failure exit. It does not return.

AG_EVOID:                      ; A record type with no fields.
    CALL DG_RAISE                  ; Report it.
    DB   DG_EMPTY                  ; Diagnostic: empty record.

;@ROUTINE IN A OUT A,CARRY,ZERO CLOBBERS SIGN,PARITY,HALFCARRY,DE
; Store byte A at the staging cursor and advance the cursor. The object's
; extent has passed AG_FITRW, so the cursor stays inside AG_IBUF. BC and
; HL are kept.

AG_PUT:
    PUSH HL                        ; Keep the caller's HL.
    LD   HL,(AG_OPOS)              ; Fetch the cursor offset
    INC  HL                        ; and advance it past the byte:
    LD   (AG_OPOS),HL              ; publish it.
    LD   DE,AG_IBUF-1              ; The byte is the one before it
    ADD  HL,DE                     ; in the staging buffer.
    LD   (HL),A                    ; Stage it.
    POP  HL                        ; The caller's HL.
    OR   A                         ; Clear carry for success.
    RET                            ; Return the byte in A.

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
AG_EWIDE EQU  AG_ELONG         ; An extent past 65,535 bytes, the same.
AG_ECNT:                       ; Anything but a comma between two items:
    LD   D,TK_COMMA                ; the comma is expected (syntax).

;@ROUTINE IN D NORETURN
; Raise syntax at the current token: token kind D expected.

AG_EWANT:
    LD   A,D                       ; The kind
    OR   DG_TOKEN                  ; expected,
    JP   DG_ISSUE                  ; at the token.

;@ROUTINE OUT A,CARRY,ZERO CLOBBERS SIGN,PARITY,HALFCARRY,D,DE,HL
; Peek at the next token kind, preserving BC for the item loops.

AG_PEEK:
    PUSH BC                        ; Keep the caller's loop state.
    CALL PR_PEEK                   ; Fetch the next token kind.
    POP  BC                        ; Discard the token value; restore BC.
    RET                            ; Return the kind in A.

;@ROUTINE OUT A,CARRY,ZERO CLOBBERS SIGN,PARITY,HALFCARRY,D,DE,HL
; Consume the comma between two items: anything else, a close before the
; last item among them, is syntax, the comma expected. BC is preserved.

AG_COMMA:
    LD   A,TK_COMMA                ; A comma separates the items; fall into AG_BRACK.

;@ROUTINE IN A OUT A,CARRY,ZERO CLOBBERS SIGN,PARITY,HALFCARRY,D,DE,HL
; Consume the next token, which must be of kind A: a bracket, a comma or a
; string literal. Any other is syntax, kind A expected (AG_EWANT). BC is
; preserved.

AG_BRACK:
    PUSH AF                        ; Keep the expected kind.
    CALL AG_PEEK                   ; Fetch the next token kind.
    POP  DE                        ; D is the expected kind.
    CP   D                         ; Is it the one?
    JR   NZ,AG_EWANT               ; No: it is expected; else fall into AG_TAKE.

;@ROUTINE OUT A,CARRY,ZERO CLOBBERS SIGN,PARITY,HALFCARRY,D,DE,HL
; Consume the next token, preserving BC for the item loops.

AG_TAKE:
    PUSH BC                        ; Keep the caller's loop state.
    CALL PR_TAKE                   ; Consume the token.
    POP  BC                        ; Discard the token value; restore BC.
    RET                            ; Return the kind in A.

;@ROUTINE IN A OUT A,CARRY,ZERO CLOBBERS SIGN,PARITY,HALFCARRY,B,C,D,DE,HL,IX,IY
; Parse one initializer for type ID A at the staging cursor, advancing the
; cursor by the type's extent. A scalar takes a constant expression that
; fits the type; a string a string literal; a record a parenthesized list
; of its fields; an array a bracketed list of its elements.

AG_PARSE:
    CP   AG_FIRST                  ; Is this a scalar type?
    JR   C,.SCALAR                 ; Yes: parse a constant.
    CALL PL_ISHND                  ; A handle has no
    JR   C,.HANDLE                 ; static initializer.
    CALL AG_DESC                   ; Address its descriptor.
    LD   A,(HL)                    ; Fetch the kind.
    CP   AG_KSTR                   ; A bounded string?
    JR   Z,.STRING                 ; Parse a string literal.
    CP   AG_KREC                   ; A record?
    JR   Z,AG_REC                  ; Parse its field list.
    CP   AG_KARR                   ; An array?
    JP   Z,AG_ARRAY                ; Parse its element list.
    CALL DG_RAISE                  ; Defensive: no other kind is interned.
    DB   DG_BUG                    ; Diagnostic: internal.
.HANDLE:                       ; A handle's initializer:
    CALL PR_PEEK                   ; at its first token,
    CALL DG_RAISE                  ; static-initializer.
    DB   DG_SINIT                  ; No return.

.SCALAR:                       ; u8, u16 or Boolean.
    LD   E,A                       ; E is the destination type for EX_FITS.
    PUSH DE                        ; Keep it across the expression.
    CALL EX_CONST                  ; Parse a constant expression of type A.
    POP  DE                        ; Restore the destination type.
    CALL EX_FITS                   ; Check assignment compatibility.
    AND  SY_KNOWN                  ; Was the value known at compile time?
    LD   A,DG_KNOWN                ; No: a static initializer must be,
    JP   Z,EX_EVAL                 ; reported at the value (not-constant).
    LD   A,E                       ; The type's
    CALL AG_SIZE                   ; size: its bytes
    LD   B,L                       ; of the value
    LD   HL,EX_KVAL                ; from the lowest,
.BYTE:                         ; B bytes remain.
    LD   A,(HL)                    ; The next
    CALL AG_PUT                    ; is staged (encodeScalar), BC and HL kept;
    INC  HL                        ; the next
    DJNZ .BYTE                     ; until all are staged.
    OR   A                         ; Clear carry for success.
    RET                            ; The value is staged.

.STRING:                       ; A bounded string, HL its descriptor.
    INC  HL                        ; Step to the auxiliary byte.
    LD   B,(HL)                    ; B is the string's capacity.
    LD   A,TK_TEXT                 ; A string literal must follow:
    CALL AG_BRACK                  ; consume it or report the token.
    LD   A,(TK_LEN)                ; Fetch the literal's decoded length.
    CP   B                         ; Compare it with the capacity.
    JR   Z,AG_TEXT                 ; Exactly full fits.
    JR   NC,AG_ELONG               ; Longer does not; report it.
; AG_ZERO has already zeroed the whole object, so decoding need write only
; the length and payload bytes: shorter fits, staged by AG_TEXT.

;@ROUTINE IN B OUT A,B,CARRY,ZERO CLOBBERS SIGN,PARITY,HALFCARRY,C,DE,HL
; Stage the current string literal as a bounded string of capacity B: the
; length byte, then the payload decoded straight from the resident source
; (AG_CHAR). TK_LEN is the decoded length and TK_PTR addresses the opening
; quote. The object is already zero, so the cursor simply skips the
; padding and the terminator.

AG_TEXT:
    LD   A,(TK_LEN)                ; Fetch the decoded length.
    LD   C,A                       ; C counts the characters to decode.
    CALL AG_PUT                    ; Stage the length byte; BC is kept.
    LD   A,B                       ; Start from the capacity.
    SUB  C                         ; Less the length gives the padding.
    LD   B,A                       ; B is the padding byte count.
    LD   HL,(TK_PTR)               ; Address the opening quote.
    INC  HL                        ; Step to the first character.
    INC  C                         ; C counts one more, at most 254.
.LOOP:                         ; Decode one character per iteration.
    DEC  C                         ; Are characters left?
    JR   Z,.PAD                    ; No: skip the padding.
    CALL AG_CHAR                   ; A is the next byte, decoded.
    CALL AG_PUT                    ; Stage it; BC and HL are kept.
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

;@ROUTINE IN A OUT A,CARRY,ZERO CLOBBERS SIGN,PARITY,HALFCARRY,D,DE,HL
; Consume the opening bracket A of a record or array initializer and open
; one nesting level. Any other token is syntax, the bracket expected; a
; level past AG_LCAP raises DG_INITS, and one the stack has no room for
; DG_DEEP (PR_ROOM). BC is preserved.

AG_ENTER:
    CALL PR_ROOM                   ; Room on the stack for it,
    CALL AG_BRACK                  ; Consume the bracket.
    LD   A,(AG_LEVEL)              ; Fetch the nesting depth.
    CP   AG_LCAP                   ; Is another level allowed?
    JR   NC,AG_EDEEP               ; No: nested too deeply.
    INC  A                         ; Open one more level.
    LD   (AG_LEVEL),A              ; Publish the depth.
    OR   A                         ; Clear carry for success.
    RET                            ; Return to the list parser.

; A failure exit. It does not return.

AG_EDEEP:                      ; Initializers nested beyond AG_LCAP.
    CALL DG_RAISE                  ; Report it.
    DB   DG_INITS                  ; Diagnostic: initializers nested too deeply.

; Parse a record initializer, ( field, field, ... ), with one item for each
; field in declaration order. HL is the record's descriptor. Entered by
; jump from AG_PARSE and returns through AG_CLOSE.

AG_REC:
    INC  HL                        ; Step to the record ordinal.
    LD   A,(HL)                    ; Fetch it.
    CALL AG_RENT                   ; HL addresses the record's entry in AG_RTAB.
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
    LD   A,TK_RPAR                 ; Expect ')'.
    JR   AG_CLOSE                  ; Close the list and return.

; Parse an array initializer, [ item, item, ... ], with exactly one item for
; each element. HL is the array's descriptor. Entered by jump from
; AG_PARSE; falls into AG_CLOSE.

AG_ARRAY:
    INC  HL                        ; Step to the element type.
    LD   C,(HL)                    ; C is the element type.
    INC  HL                        ; Step to the element count.
    LD   E,(HL)                    ; Fetch its low byte.
    INC  HL                        ; Step to the high byte.
    LD   D,(HL)                    ; DE counts the elements to initialize.
    PUSH DE                        ; Keep the count; AG_ENTER keeps BC.
    LD   A,TK_LBRAC                ; An array initializer opens with '['.
    CALL AG_ENTER                  ; Consume it and nest one level.
    POP  DE                        ; Restore the count.
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
    LD   A,TK_RBRAC                ; Expect ']'.

;@ROUTINE IN A OUT CARRY CLOBBERS SIGN,PARITY,HALFCARRY,ZERO,A,DE,HL
; Close an initializer list: A is the closing bracket, which must follow
; the last item; anything else, another item among them, is syntax, the
; bracket expected. Closes one nesting level (AG_LEAVE). BC is preserved.

AG_CLOSE:
    CALL AG_BRACK                  ; Consume the bracket; fall into AG_LEAVE.

;@ROUTINE OUT CARRY CLOBBERS SIGN,PARITY,HALFCARRY,ZERO,HL
; Close one level of initializer nesting. A is preserved.

AG_LEAVE:
    LD   HL,AG_LEVEL               ; Address the nesting depth.
    DEC  (HL)                      ; One level fewer is open.
    OR   A                         ; Clear carry for success.
    RET                            ; Return to the initializer parser.

;@ROUTINE OUT A,CARRY,ZERO CLOBBERS SIGN,PARITY,HALFCARRY,BC,HL
; Begin staging an object's initializer: the cursor AG_OPOS at the
; buffer's start, and the AG_OSIZE bytes from there, at most the
; buffer's (AG_FITRW, DG_DATA), zeroed before the initializer is applied.
; Returns A zero with carry clear.

AG_ZERO:
    LD   HL,(AG_OSIZE)             ; The object
    CALL AG_FITRW                  ; must fit the staging.
    LD   HL,0                      ; Stage from
    LD   (AG_OPOS),HL              ; the first byte,
    LD   HL,AG_IBUF                ; the buffer's start.
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
