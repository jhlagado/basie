;==========================================================================
;  Owner descriptors
;==========================================================================
;
;  Overlay OWNERS, loaded above NAMES when a pool's record needs its owner
;  descriptor (OV_OWNER, OVERLAY.ASM), so that it and FLOAT share the
;  area's top: each is loaded again when it is next needed, FLOAT keeping
;  its workspace resident. It writes the descriptor of an owning record
;  (memory safety 5.10) as the reference's descriptorOf and owningEntries
;  make it: a rodata blob named TYPE.owners, its entries' count, then per
;  owning handle a flag byte, its offset and, for one inside an array, the
;  array's stride and element count. An array inside an array takes one
;  entry per outer element, after the entries of its element: only the
;  innermost array strides. Its scratch is POOLS.ASM's, in AG_IBUF.
;
;  Entry, the overlay's first byte:
;    OW_DESC   write the descriptor of table type A, ordinal HL

;@ROUTINE IN A,HL CLOBBERS A,BC,DE,HL,IX,CARRY,ZERO,SIGN,PARITY,HALFCARRY
; Write the owner descriptor of table type A, whose ordinal HL is, as a
; rodata blob named TYPE.owners: its entries' count (capacity, "types",
; beyond 255), then the entries (OW_WALK).

OW_DESC:                       ; A is the type, HL its ordinal.
    LD   (PL_NSTOR),HL             ; The blob's ordinal, for its name.
    LD   (PL_WTYPE),A              ; The type, kept.
    LD   HL,0                      ; Count
    LD   (PL_WCNT),HL              ; the entries:
    XOR  A                         ; a counting
    LD   (PL_WEMIT),A              ; walk.
    CALL OW_ROOT                   ; The entries counted.
    LD   HL,(PL_WCNT)              ; At most
    LD   A,H                       ; 255:
    OR   A                         ; more is
    JR   NZ,.MANY                  ; capacity.
    LD   HL,(PL_NSTOR)             ; The blob,
    LD   A,BL_KRO                  ; read-only,
    CALL BL_BEGIN                  ; begun.
    LD   A,(PL_WCNT)               ; The count,
    CALL BL_BYTE                   ; first.
    LD   A,1                       ; An emitting
    LD   (PL_WEMIT),A              ; walk:
    CALL OW_ROOT                   ; the entries.
    CALL BL_END                    ; Written.
    LD   A,(PL_WTYPE)              ; Its name: the type's,
    CALL OW_TNAME                  ; at HL, B bytes,
    LD   C,B                       ; C of them,
    LD   DE,OW_SUFX                ; then .owners:
    PUSH DE                        ; the suffix.
    JP   PL_NAMEC                  ; Named; return.
.MANY:                         ; More than 255 entries:
    CALL PR_PEEK                   ; at the token after the line's end,
    LD   A,DG_META                 ; capacity,
    JP   DG_ISSUE                  ; types.

;@ROUTINE CLOBBERS A,BC,DE,HL,CARRY,ZERO,SIGN,PARITY,HALFCARRY
; Walk PL_WTYPE from offset zero under the root frame, whose length is
; zero. IY is kept.

OW_ROOT:                       ; The type is PL_WTYPE.
    PUSH IY                        ; The caller's IY, kept.
    LD   HL,0                      ; The root frame:
    PUSH HL                        ; a length of zero.
    LD   IY,0                      ; IY
    ADD  IY,SP                     ; addresses it.
    LD   A,(PL_WTYPE)              ; The type,
    CALL OW_WALK                   ; at offset zero, walked.
    POP  HL                        ; The root frame dropped.
    POP  IY                        ; The caller's IY.
    RET                            ; Done.

;@ROUTINE IN A,HL,IY CLOBBERS A,BC,DE,HL,CARRY,ZERO,SIGN,PARITY,HALFCARRY
; Visit the owning handles of type A at offset HL within the innermost
; enclosing array's element, whose frame IY addresses: each is an entry
; (OW_ENT) as the reference's owningEntries makes it. An array pushes a
; frame of four words (IY+0 its length, +2 its stride, +4 its offset, +6
; the frame outside it) and walks its element from offset zero. IY is kept.

OW_WALK:                       ; A is the type.
    CALL PL_ISHND                  ; A handle? If not,
    JR   NC,.TABLE                 ; perhaps a table type.
    AND  AG_HID                    ; An identifier
    RET  NZ                        ; owns nothing; an owner (A zero,
    JP   OW_ENT                    ; unstrided) is an entry; return.
.TABLE:                        ; A table type, or no aggregate.
    CP   AG_FIRST                  ; Below the table:
    RET  C                         ; a scalar.
    CP   AG_FIRST+AG_TCAP          ; Past it:
    RET  NC                        ; an open view or a File.
    PUSH HL                        ; The offset
    PUSH AF                        ; and the type, kept.
    CALL PL_OWNS                   ; Owning?
    JR   C,.OWNS                   ; Then visit it.
    POP  AF                        ; Not:
    POP  HL                        ; nothing to visit.
    RET                            ; Done.
.OWNS:                         ; An owning record or array.
    POP  AF                        ; The type; the offset stays.
    CALL AG_DESC                   ; Its descriptor, HL.
    LD   A,(HL)                    ; Its kind:
    CP   AG_KREC                   ; a record?
    INC  HL                        ; Its auxiliary byte,
    LD   A,(HL)                    ; the record's ordinal or the element type.
    INC  HL                        ; Its
    LD   C,(HL)                    ; count,
    INC  HL                        ; for
    LD   B,(HL)                    ; an array.
    JR   NZ,.ARRAY                 ; Not a record: an array.
    CALL AG_RENT                   ; A is the record's ordinal: its entry,
    LD   A,(HL)                    ; its first field,
    INC  HL                        ; and
    LD   B,(HL)                    ; its count, B,
    LD   C,A                       ; the next field's index, C.
.FIELD:                        ; The record's offset is on the stack.
    LD   A,B                       ; Any field
    OR   A                         ; left?
    JR   Z,.FIELDS                 ; No.
    PUSH BC                        ; The loop, kept.
    LD   A,C                       ; The field's
    CALL AG_FIELD                  ; entry:
    INC  HL                        ; past
    INC  HL                        ; its
    INC  HL                        ; name,
    LD   A,(HL)                    ; its type,
    INC  HL                        ; and
    LD   E,(HL)                    ; its
    INC  HL                        ; offset,
    LD   D,(HL)                    ; DE.
    LD   HL,2                      ; The record's offset,
    ADD  HL,SP                     ; under the loop:
    PUSH AF                        ; (the type kept)
    LD   A,(HL)                    ; its
    INC  HL                        ; low and
    LD   H,(HL)                    ; high
    LD   L,A                       ; bytes,
    ADD  HL,DE                     ; plus the field's: the field's offset.
    POP  AF                        ; The type.
    CALL OW_WALK                   ; The field visited.
    POP  BC                        ; The loop:
    INC  C                         ; the next field,
    DEC  B                         ; one fewer.
    JR   .FIELD                    ; Until all are.
.FIELDS:                       ; Every field is visited.
    POP  HL                        ; The offset, dropped.
    RET                            ; Done.
.ARRAY:                        ; A is the element, BC the element count.
    LD   (PL_WELEM),A              ; The element type,
    LD   (PL_WLEN),BC              ; and its count, kept.
    POP  HL                        ; The array's offset.
    PUSH IY                        ; The frame outside,
    PUSH HL                        ; the offset,
    CALL AG_SIZE                   ; the element's size,
    PUSH HL                        ; the stride,
    LD   HL,(PL_WLEN)              ; and the
    PUSH HL                        ; length:
    LD   IY,0                      ; the array's
    ADD  IY,SP                     ; frame.
    LD   A,(PL_WELEM)              ; Its element
    LD   HL,0                      ; from offset zero,
    CALL OW_WALK                   ; visited.
    POP  HL                        ; The
    POP  HL                        ; frame
    POP  HL                        ; dropped,
    POP  IY                        ; the one outside restored.
    RET                            ; Done.

;@ROUTINE IN A,BC,DE,HL,IY CLOBBERS A,BC,DE,HL,CARRY,ZERO,SIGN,PARITY,HALFCARRY
; An owning handle at offset HL in the element of frame IY: unstrided when
; A is zero, else strided by BC with DE elements. In an array's frame an
; unstrided entry takes the array's stride and length, and a strided one
; becomes one entry for each of its elements, each passed to the frame
; outside; in the root frame the entry is counted (PL_WEMIT zero, in
; PL_WCNT) or appended to the blob. IY is kept.

OW_ENT:                        ; A is the flag.
    PUSH AF                        ; Kept.
    LD   A,(IY+0)                  ; The root
    OR   (IY+1)                    ; frame?
    JR   Z,.ROOT                   ; Then the entry is made.
    PUSH DE                        ; (the count kept)
    LD   E,(IY+4)                  ; The offset
    LD   D,(IY+5)                  ; of the array
    ADD  HL,DE                     ; is added.
    POP  DE                        ; The count.
    POP  AF                        ; Strided?
    OR   A                         ; Then
    JR   NZ,.EXPAND                ; one for each element.
    LD   C,(IY+2)                  ; The array's
    LD   B,(IY+3)                  ; stride
    LD   E,(IY+0)                  ; and
    LD   D,(IY+1)                  ; length
    INC  A                         ; stride it,
    JR   .OUTER                    ; passed outward; return.
.EXPAND:                       ; DE elements of BC bytes, each:
    PUSH DE                        ; the count
    PUSH BC                        ; and stride kept,
    LD   C,(IY+0)                  ; this
    LD   B,(IY+1)                  ; array's length,
    LD   E,(IY+2)                  ; and its
    LD   D,(IY+3)                  ; stride.
.STEP:                         ; HL the element's entry, BC elements left.
    PUSH DE                        ; The array's stride,
    PUSH BC                        ; the elements left,
    PUSH HL                        ; and the offset kept.
    LD   HL,6                      ; The entry's
    ADD  HL,SP                     ; stride
    LD   C,(HL)                    ; and
    INC  HL                        ; count,
    LD   B,(HL)                    ; under
    INC  HL                        ; them,
    LD   E,(HL)                    ; read
    INC  HL                        ; back.
    LD   D,(HL)                    ; The same
    POP  HL                        ; offset,
    PUSH HL                        ; strided,
    LD   A,1                       ; passed
    CALL .OUTER                    ; outward.
    POP  HL                        ; The offset,
    POP  BC                        ; the elements left
    POP  DE                        ; and the stride:
    ADD  HL,DE                     ; the next element's.
    DEC  BC                        ; One fewer.
    LD   A,B                       ; Until
    OR   C                         ; all
    JR   NZ,.STEP                  ; are.
    POP  BC                        ; The entry's stride
    POP  DE                        ; and count dropped.
    RET                            ; Done.
.OUTER:                        ; Pass the entry to the frame outside.
    PUSH IY                        ; This frame, kept.
    PUSH HL                        ; (the offset kept)
    LD   L,(IY+6)                  ; The frame
    LD   H,(IY+7)                  ; outside
    PUSH HL                        ; becomes
    POP  IY                        ; IY.
    POP  HL                        ; The offset.
    CALL OW_ENT                    ; The entry made there.
    POP  IY                        ; This frame again.
    RET                            ; Back.
.ROOT:                         ; The entry itself.
    LD   A,(PL_WEMIT)              ; Counting?
    OR   A                         ; Then
    JR   NZ,.WRITE                 ; count it:
    POP  AF                        ; (the flag dropped)
    LD   HL,(PL_WCNT)              ; one
    INC  HL                        ; more
    LD   (PL_WCNT),HL              ; entry.
    RET                            ; Done.
.WRITE:                        ; Append it.
    POP  AF                        ; The flag,
    CALL BL_BYTE                   ; first;
    PUSH AF                        ; (kept)
    CALL PL_WORD                   ; the offset;
    POP  AF                        ; strided?
    OR   A                         ; If not,
    RET  Z                         ; no more.
    LD   H,B                       ; The
    LD   L,C                       ; stride
    CALL PL_WORD                   ; and
    EX   DE,HL                     ; the
    JP   PL_WORD                   ; count; return.

;@ROUTINE IN A OUT HL,B CLOBBERS A,C,DE,CARRY,ZERO,SIGN,PARITY,HALFCARRY
; The name of table type A, a record's: the symbol of class SY_RTYPE whose
; payload is A. HL returns its spelling and B its length.

OW_TNAME:                      ; A is the type.
    LD   C,A                       ; Kept.
    LD   A,(SY_CNT)                ; The symbols:
    LD   B,A                       ; each,
.LOOK:                         ; from the last.
    LD   A,B                       ; Symbol
    DEC  A                         ; B-1:
    CALL SY_AT                     ; its record.
    PUSH HL                        ; Kept.
    INC  HL                        ; Its
    INC  HL                        ; class
    INC  HL                        ; byte:
    LD   A,(HL)                    ; a record
    CP   SY_RTYPE                  ; type
    JR   NZ,.NEXT                  ; whose
    INC  HL                        ; payload
    LD   A,(HL)                    ; is
    CP   C                         ; the type?
    JR   NZ,.NEXT                  ; No.
    POP  HL                        ; The record:
    LD   E,(HL)                    ; its
    INC  HL                        ; spelling's
    LD   D,(HL)                    ; address
    INC  HL                        ; and
    LD   B,(HL)                    ; length.
    EX   DE,HL                     ; HL is the spelling.
    RET                            ; Done.
.NEXT:                         ; Not it.
    POP  HL                        ; Dropped.
    DJNZ .LOOK                     ; The one before.
    LD   B,0                       ; None: no name.
    RET                            ; HL is anything.

OW_SUFX: DB  ".owners",0       ; An owner descriptor's name suffix.
