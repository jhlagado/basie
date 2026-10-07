;==========================================================================
;  The blob writer's end
;==========================================================================
;
;  Write a blob held in the blob writer's buffers (BL_END): its directory
;  record, its bytes and its line record, its short jumps shrunk (BL_MAP)
;  and its references and line entries encoded (BL_CTRL). Part of the
;  CLOSE overlay (CLOSE.ASM), reached from the resident BL_END. Split from
;  BLOB.ASM.

;@ROUTINE IN HL OUT BC,HL CLOBBERS A,CARRY,ZERO,SIGN,PARITY,HALFCARRY
; Map offset HL of the blob to its offset once its short jumps have
; shrunk (BL_SHORT): one byte less for each short jump whose third byte,
; the one dropped, comes before it. BC returns the offset of that third
; byte of the first short jump whose third byte does not come before it,
; plus one (BL_PAST plus two when there is none): HL plus one exactly
; when the jump's operand starts at HL. Carry returns clear. DE is kept.

BL_MAP:                        ; HL is an offset.
    PUSH DE                        ; Keep the caller's DE.
    EX   DE,HL                     ; DE is the offset.
    LD   HL,(BL_JUMPS)             ; From the first short jump,
.WALK:                         ; HL is an entry.
    LD   C,(HL)                    ; BC is
    INC  HL                        ; its
    LD   B,(HL)                    ; offset;
    INC  HL                        ; HL is past
    INC  HL                        ; the entry
    INC  HL                        ; when the
    INC  BC                        ; dropped byte,
    INC  BC                        ; two on,
    LD   A,C                       ; is before
    SUB  E                         ; the offset:
    LD   A,B                       ; carry
    SBC  A,D                       ; then.
    JR   C,.WALK                   ; Count it, and go on.
    PUSH BC                        ; Keep the first not counted.
    LD   BC,(BL_JUMPS)             ; Four bytes an entry, and
    SBC  HL,BC                     ; four more for the one that
    SRL  H                         ; ended the walk:
    RR   L                         ; the count
    SRL  H                         ; plus
    RR   L                         ; one.
    EX   DE,HL                     ; The offset,
    INC  HL                        ; plus one,
    SBC  HL,DE                     ; less it (carry is clear),
    POP  BC                        ; is the new offset.
    POP  DE                        ; Restore DE.
    RET                            ; HL is it.

;@ROUTINE IN B,E,HL,IX CLOBBERS A,DE,HL,CARRY,ZERO,SIGN,PARITY,HALFCARRY
; Write to the stream at IX the control byte of a reference or line entry
; at offset HL (object format §5.2, §8): its delta from the entry last
; encoded (BL_LAST) with the flag bits B when the delta is below E, else
; E with the flags, then the offset as a word. The offset becomes the
; last. BC is kept.

BL_CTRL:                       ; HL is the offset, E the escape, B the flags.
    PUSH HL                        ; Keep the offset for the escape's word.
    LD   A,E                       ; Keep the escape: DE is needed.
    LD   DE,(BL_LAST)              ; The last offset, zero for the first;
    LD   (BL_LAST),HL              ; this one is the next's.
    AND  A                         ; Clear carry; A is kept.
    SBC  HL,DE                     ; HL is the delta.
    LD   E,A                       ; E is the escape again.
    LD   A,H                       ; Does the delta fit the control byte?
    OR   A                         ; Not if it is above 255,
    JR   NZ,.FAR                   ; nor if it is E or more.
    LD   A,L                       ; A is the delta.
    CP   E                         ; Is it E or more?
    JR   NC,.FAR                   ; Then the offset goes in a word.
    OR   B                         ; Combine the delta with the flags.
    POP  HL                        ; (the offset is not needed)
    JP   OUT_BYTE                  ; The control byte, and return.
.FAR:                          ; The delta needs a word.
    LD   A,E                       ; The escape,
    OR   B                         ; with the flags,
    CALL OUT_BYTE                  ; is the control byte.
    POP  HL                        ; The offset
    JP   OUT_WORD                  ; follows it; return.

;@ROUTINE CLOBBERS A,BC,DE,HL,IX,CARRY,ZERO,SIGN,PARITY,HALFCARRY
; Write the blob: its directory record with its references, its bytes to
; the byte stream and, for code, its line record, its short jumps shrunk
; (BL_SHORT): every offset and every addend naming the blob itself mapped
; (BL_MAP), each short jump written as a JR and its reference dropped.
; References and line entries are encoded here (object format §5.2, §8):
; a control byte with the offset's delta from the last one, 63 (for a
; reference) or 127 (for a line entry) escaping to an absolute word; a
; reference's control has bit 6 when an addend follows and bit 7 when a
; form does, then the form, the target and the addend; a line entry's
; has bit 7 when its part changes, then the part, then the line. No blob
; is built after it (BL_CBASE), until BL_BEGIN.

BL_END:                        ; The blob is complete in memory.
    CALL BL_WRITE                  ; Write it;
    XOR  A                         ; none is
    LD   (BL_CBASE+1),A            ; built
    RET                            ; now.

;@ROUTINE CLOBBERS A,BC,DE,HL,IX,CARRY,ZERO,SIGN,PARITY,HALFCARRY
; Write the blob, as BL_END says, and leave it built.

BL_WRITE:                      ; The blob is complete in memory.
    LD   HL,(BL_LEN)               ; The size once the jumps shrink
    LD   D,H                       ; is the end's
    LD   E,L                       ; new
    CALL BL_MAP                    ; offset.
    PUSH HL                        ; Keep it for the record.
    EX   DE,HL                     ; The old size less the new
    SBC  HL,DE                     ; is the jumps shrunk (carry is clear),
    EX   DE,HL                     ; whose references are
    LD   HL,(BL_RCNT)              ; dropped
    SBC  HL,DE                     ; from the count.
    EX   DE,HL                     ; DE is the count,
    POP  HL                        ; HL the size.
    CALL BL_REC                    ; Write the header, ordinal, size and count.
    LD   HL,0                      ; The first reference's delta
    LD   (BL_LAST),HL              ; is its offset.
    LD   HL,(NH_PTR)               ; From the log's first entry.
.REF:                          ; HL is an entry, or the heap.
    CALL BL_NEXT                   ; The next:
    JR   C,.BYTES                  ; none, and the bytes follow;
    JR   Z,.REF                    ; a line entry, passed over.
    PUSH HL                        ; A reference: kept.
    LD   C,(HL)                    ; C is its form.
    INC  HL                        ; DE
    LD   E,(HL)                    ; is
    INC  HL                        ; its
    LD   D,(HL)                    ; offset.
    INC  HL                        ; HL is its target,
    PUSH HL                        ; kept.
    EX   DE,HL                     ; HL is the offset,
    LD   D,H                       ; DE
    LD   E,L                       ; too.
    PUSH BC                        ; Keep the form.
    CALL BL_MAP                    ; HL is the new offset.
    INC  DE                        ; Is the jump whose operand
    EX   DE,HL                     ; starts here short:
    SBC  HL,BC                     ; is BC the offset plus one?
    EX   DE,HL                     ; HL is the new offset.
    POP  BC                        ; C is the form.
    POP  DE                        ; DE is the target.
    JR   Z,.RNEXT                  ; A short jump's: dropped.
    PUSH DE                        ; Keep the target.
    LD   A,C                       ; Bit 7 when the form
    ADD  A,$FF                     ; is not ABS16, so that
    SBC  A,A                       ; a form byte
    AND  $80                       ; follows,
    LD   B,A                       ; in B.
    EX   DE,HL                     ; HL is the target,
    INC  HL                        ; the
    INC  HL                        ; addend
    LD   A,(HL)                    ; after it:
    INC  HL                        ; is it
    OR   (HL)                      ; zero?
    EX   DE,HL                     ; HL is the new offset.
    JR   Z,.CONTROL                ; An addend of zero is left out.
    SET  6,B                       ; Bit 6: an addend follows.
.CONTROL:                      ; B holds the flags.
    LD   E,63                      ; A reference's escape.
    CALL BL_CTRL                   ; The control byte and any offset.
    LD   A,C                       ; Any form but ABS16
    OR   A                         ; follows
    CALL NZ,OUT_BYTE               ; it.
    POP  HL                        ; The target:
    LD   E,(HL)                    ; DE
    INC  HL                        ; is
    LD   D,(HL)                    ; the
    INC  HL                        ; ordinal,
    EX   DE,HL                     ; HL;
    CALL OUT_WORD                  ; its word.
    PUSH DE                        ; Keep the addend's place.
    LD   DE,(BL_ORD)               ; Is the target
    OR   A                         ; the blob
    SBC  HL,DE                     ; itself?
    POP  HL                        ; The addend
    LD   E,(HL)                    ; is
    INC  HL                        ; DE,
    LD   D,(HL)                    ; its word.
    JR   NZ,.ADDEND                ; Another blob's addend is kept;
    EX   DE,HL                     ; the blob's own,
    PUSH BC                        ; (the flags kept)
    CALL BL_MAP                    ; an offset in it,
    POP  BC                        ; moves as
    EX   DE,HL                     ; the code does.
.ADDEND:                       ; DE is the addend.
    BIT  6,B                       ; Is there one?
    JR   Z,.RNEXT                  ; No: the next reference.
    EX   DE,HL                     ; Yes:
    CALL OUT_WORD                  ; its word.
.RNEXT:                        ; The reference is written, or dropped.
    POP  HL                        ; The entry;
    JR   .REF                      ; the next.
.BYTES:                        ; The bytes go to the byte stream.
    LD   IX,BL_BY                  ; The byte stream.
    LD   HL,(BL_JUMPS)             ; The first short jump
    PUSH HL                        ; is the next to be met.
    LD   DE,0                      ; From the first byte.
.BYTE:                         ; DE is the next byte's old offset.
    LD   HL,(BL_LEN)               ; Is it past
    OR   A                         ; the
    SBC  HL,DE                     ; end?
    JR   Z,.LINES                  ; Then the line record.
    POP  HL                        ; Is the next short jump
    PUSH HL                        ; (kept)
    LD   A,(HL)                    ; here?
    CP   E                         ; Its offset's low
    JR   NZ,.COPY                  ; byte,
    INC  HL                        ; and its
    LD   A,(HL)                    ; high
    CP   D                         ; byte.
    JR   Z,.SHORT                  ; It is.
.COPY:                         ; The byte is written as it is.
    LD   HL,(BL_CBASE)             ; Its address
    ADD  HL,DE                     ; in the blob.
    LD   A,(HL)                    ; Append
    CALL OUT_BYTE                  ; it.
    INC  DE                        ; The next.
    JR   .BYTE                     ; Go on.
.SHORT:                        ; HL is the short jump's entry, plus one.
    INC  HL                        ; BC
    LD   C,(HL)                    ; is
    INC  HL                        ; its
    LD   B,(HL)                    ; target.
    INC  HL                        ; HL is the next entry,
    EX   (SP),HL                   ; the next to be met.
    LD   HL,(BL_CBASE)             ; The JP's
    ADD  HL,DE                     ; opcode:
    LD   A,(HL)                    ; JP, $C3, has bit 0
    RRCA                           ; set, and
    LD   A,$18                     ; becomes JR, $18;
    JR   C,.OPCODE                 ; JP cc becomes
    LD   A,(HL)                    ; JR cc, $20
    AND  $18                       ; with the same
    OR   $20                       ; condition bits.
.OPCODE:                       ; A is the JR's opcode.
    CALL OUT_BYTE                  ; Append it.
    LD   H,B                       ; The target
    LD   L,C                       ; moves
    CALL BL_MAP                    ; as the code does,
    PUSH HL                        ; kept;
    LD   H,D                       ; and so
    LD   L,E                       ; does
    CALL BL_MAP                    ; the jump.
    POP  BC                        ; The displacement: the target
    LD   A,C                       ; less the JR's own two bytes'
    SUB  L                         ; end, a byte
    SUB  2                         ; either way.
    CALL OUT_BYTE                  ; Append it.
    INC  DE                        ; The JP's
    INC  DE                        ; three bytes
    INC  DE                        ; are written.
    JR   .BYTE                     ; Go on.
.LINES:                        ; The bytes are written.
    POP  HL                        ; (the next short jump)
    LD   A,(BL_HEAD)               ; Only routines have line records.
    AND  BL_KMASK                  ; Is this code?
    RET  NZ                        ; Data has no lines.
    LD   A,(BL_FLAGS)              ; Is there a line stream?
    AND  BL_LNOUT                  ; Option N leaves it out.
    RET  Z                         ; Then there is nowhere to write them.
    LD   IX,BL_LN                  ; The line stream.
    LD   A,2                       ; Tag 2: a blob's line record.
    CALL OUT_BYTE                  ; Append it.
    LD   HL,(BL_ORD)               ; The blob's ordinal.
    CALL OUT_WORD                  ; Append it.
    LD   HL,(BL_LCNT)              ; The number of entries.
    CALL OUT_WORD                  ; Append it.
    LD   HL,0                      ; The first entry's delta
    LD   (BL_LAST),HL              ; is its offset, and it
    LD   A,$FF                     ; names its part: none
    LD   (BL_LPART),A              ; is $FF.
    LD   HL,(NH_PTR)               ; From the log's first entry.
.LINE:                         ; HL is an entry, or the heap.
    CALL BL_NEXT                   ; The next:
    RET  C                         ; none, and the blob is written;
    JR   NZ,.LINE                  ; a reference, passed over.
    PUSH HL                        ; A line entry: kept.
    INC  HL                        ; Past its tag,
    LD   E,(HL)                    ; DE
    INC  HL                        ; is
    LD   D,(HL)                    ; its
    INC  HL                        ; offset,
    LD   C,(HL)                    ; C its
    INC  HL                        ; part;
    PUSH HL                        ; its line's word is kept.
    EX   DE,HL                     ; The offset
    PUSH BC                        ; (the part kept)
    CALL BL_MAP                    ; moves as the code does.
    POP  BC                        ; C is the part.
    LD   B,0                       ; No flag, unless
    LD   A,(BL_LPART)              ; the part
    CP   C                         ; differs from
    JR   Z,.SAME                   ; the last entry's:
    LD   A,C                       ; then it is
    LD   (BL_LPART),A              ; the last,
    LD   B,$80                     ; and bit 7 says it follows.
.SAME:                         ; B holds the flag.
    LD   E,127                     ; A line entry's escape.
    CALL BL_CTRL                   ; The control byte and any offset.
    LD   A,C                       ; The part,
    BIT  7,B                       ; if it changed,
    CALL NZ,OUT_BYTE               ; follows.
    POP  HL                        ; The line's
    LD   E,(HL)                    ; word
    INC  HL                        ; is
    LD   D,(HL)                    ; DE,
    INC  HL                        ; and HL the next entry.
    EX   DE,HL                     ; Append
    CALL OUT_WORD                  ; the line.
    EX   DE,HL                     ; HL is its column,
    LD   A,(HL)                    ; appended.
    CALL OUT_BYTE                  ; The entry
    POP  HL                        ; is written;
    JR   .LINE                     ; the next.
