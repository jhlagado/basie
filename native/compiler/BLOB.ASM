;==========================================================================
;  Blob writer
;==========================================================================
;
;  Write the program's objects as the four intermediate streams the linker
;  reads (object format §4 to §9, toolchain §3.2):
;
;    NAME.$DR  directory: header, one record per blob, control records,
;              trailer and CRC
;    NAME.$BY  bytes: header, then every stored blob's bytes in order
;    NAME.$LN  lines: header, part records, a line record per code blob, CRC
;    NAME.$NM  names: header, an ordinal and name per named object, CRC
;
;  A blob is built in memory, then written whole: its directory record gives
;  its size and reference count before its references, so neither can be
;  written until the blob ends. BL_BEGIN starts one; BL_BYTE, BL_REF and
;  BL_LINE add its bytes, references and line entries; BL_END writes them.
;  References and line entries are kept as they are given and encoded in
;  the stream's delta form when the blob is written, so that a routine's
;  jumps can shrink first (SHRINK.ASM): BL_END moves every offset as
;  BL_MAP says, which leaves a blob without short jumps as it is.
;
;  Principal entries:
;    BL_OPEN    open the streams and write their headers (BLOPEN.ASM)
;    BL_PART    name a source part in the line stream (BLOPEN.ASM)
;    BL_BEGIN   start a blob: ordinal, kind, root flag and alignment
;    BL_BYTE    append a byte to the blob
;    BL_REF     append a reference and its zero placeholder
;    BL_LINE    mark the start of a statement's code
;    BL_END     write the blob's record, bytes and line record
;    BL_MAP     an offset in the blob once its short jumps have shrunk
;    BL_BSS     write a bss blob's record: it has a size and nothing else
;    BL_ENTRY   write the entry control record
;    BL_LIMIT  write the limits control record
;    BL_NAME    write an ordinal's name to the name stream
;    BL_CLOSE   write the trailers and close the streams (BLCLOSE.ASM)
;
;  The opening and closing code each run once, so they are not resident:
;  BLOPEN.ASM is part of the START overlay and BLCLOSE.ASM of CHAIN.
;
;  Blob header byte (object format §5.1): bits 0-2 kind, bit 3 explicit
;  ordinal, bit 4 root, bits 5-7 alignment code. Callers pass the kind,
;  root and alignment; BL_END sets bit 3 when the ordinal does not follow
;  the previous blob's.
;
;  The program supplies MM_BLOB, the base of this module's workspace, and
;  two routines that do not return: OUT_FAIL for a full disk or directory,
;  and BL_OVER for a blob that overflows one of its buffers. Every routine
;  preserves IX and IY.

BL_KCODE EQU  0                ; Kind: a routine's code.
BL_KRO EQU  1                  ; Kind: read-only data.
BL_KDATA EQU  2                ; Kind: initialised data.
BL_KBSS EQU  3                 ; Kind: zeroed data, no stored bytes.
BL_KMASK EQU  $07              ; Header bits holding the kind.
BL_EXPL EQU  $08               ; Header bit: an explicit ordinal follows.
BL_ROOT EQU  $10               ; Header bit: the linker keeps the blob.

BL_ABS16 EQU  0                ; Form: the target's address, a word.
BL_LO8 EQU  1                  ; Form: the address's low byte.
BL_HI8 EQU  2                  ; Form: the address's high byte.
BL_SIZE EQU  3                 ; Form: the target's size, a word.

BL_LNOUT EQU  $01              ; BL_OPEN flag: write the line stream.
BL_NMOUT EQU  $02              ; BL_OPEN flag: write the name stream.
BL_BYOUT EQU  $80              ; Set by BL_OPEN: the byte stream is always written.

BL_CCAP EQU  2048              ; Bytes one blob may hold.
BL_RLEN EQU  7                 ; Bytes of one reference as it is kept.
BL_RCAP EQU  BL_RLEN*146       ; Bytes of references: 146 for one blob.
BL_LLEN EQU  5                 ; Bytes of one line entry as it is kept.
BL_LCAP EQU  BL_LLEN*128       ; Bytes of line entries: 128 for one blob.
BL_PAST EQU  $7FFF             ; An offset past every blob's: the jumps' sentinel.

; The workspace, from MM_BLOB.
BL_FLAGS EQU  MM_BLOB          ; Byte: the BL_OPEN flags.
BL_NAMEP EQU  BL_FLAGS+1       ; Word: the streams' drive and name, for BL_OPEN.
BL_STAMP EQU  BL_NAMEP+2       ; Word: the compilation stamp of every header.
BL_ORD EQU  BL_STAMP+2         ; Word: the blob being built.
BL_HEAD EQU  BL_ORD+2          ; Byte: its kind, root and alignment bits.
BL_LEN EQU  BL_HEAD+1          ; Word: its bytes so far.
BL_CUR EQU  BL_LEN+2           ; Word: BL_RPTR or BL_LPTR, where BL_PUT appends.
BL_RCNT EQU  BL_CUR+2          ; Word: its references so far.
BL_LCNT EQU  BL_RCNT+2         ; Word: its line entries so far.
BL_LAST EQU  BL_LCNT+2         ; Word: the offset of the entry last encoded.
BL_LPART EQU  BL_LAST+2        ; Byte: the part of the line entry last encoded.
BL_JUMPS EQU  BL_LPART+1       ; Word: its short jumps' table (SHRINK.ASM).
BL_JPEND EQU  BL_JUMPS+2       ; Word: the table's sentinel; its limit while built.
BL_PREV EQU  BL_JPEND+2        ; Word: the ordinal of the last blob record.
BL_COUNT EQU  BL_PREV+2        ; Word: blob records written.
BL_HIGH EQU  BL_COUNT+2        ; Word: the highest ordinal written.
BL_DR EQU  BL_HIGH+2           ; The directory stream's record.
BL_BY EQU  BL_DR+OUT_SIZE      ; The byte stream's record.
BL_LN EQU  BL_BY+OUT_SIZE      ; The line stream's record.
BL_NM EQU  BL_LN+OUT_SIZE      ; The name stream's record.
BL_CODE EQU  BL_NM+OUT_SIZE    ; BL_CCAP bytes: the blob's bytes.
BL_REFS EQU  BL_CODE+BL_CCAP   ; BL_RCAP bytes: its references.
BL_RPTR EQU  BL_REFS+BL_RCAP   ; Word: their next free byte, just past their end.
BL_GUARD EQU  BL_RPTR+2        ; BL_LLEN bytes: an entry before the first, part $FF.
BL_LINES EQU  BL_GUARD+BL_LLEN ; BL_LCAP bytes: its line entries.
BL_LPTR EQU  BL_LINES+BL_LCAP  ; Word: their next free byte, just past their end.
BL_WEND EQU  BL_LPTR+2         ; The end of the workspace.

;@ROUTINE IN A,HL CLOBBERS A,HL,CARRY,ZERO,SIGN,PARITY,HALFCARRY
; Start blob HL. A is its header byte without the explicit-ordinal bit: the
; kind, BL_ROOT if the linker must keep it, and the alignment code in bits
; 5 to 7. The blob starts empty, with no short jump (BL_NONE).

BL_BEGIN:                      ; HL is the ordinal, A the header.
    LD   (BL_ORD),HL               ; Keep the ordinal for the record.
    LD   (BL_HEAD),A               ; Keep the header bits.
    LD   HL,0                      ; Nothing is in the blob yet:
    LD   (BL_LEN),HL               ; no bytes,
    LD   (BL_RCNT),HL              ; no references,
    LD   (BL_LCNT),HL              ; no line entries.
    LD   HL,BL_NONE                ; No jump is short until BL_SHORT
    LD   (BL_JUMPS),HL             ; says so: the table is
    LD   (BL_JPEND),HL             ; its sentinel alone.
    LD   HL,BL_REFS                ; Both buffers start
    LD   (BL_RPTR),HL              ; empty.
    LD   HL,BL_LINES               ; The line entries
    LD   (BL_LPTR),HL              ; likewise.
    RET                            ; The blob is ready for its bytes.

;@ROUTINE IN A CLOBBERS CARRY,ZERO,SIGN,PARITY,HALFCARRY
; Append A to the blob's bytes. Every register but F is kept.

BL_BYTE:                       ; A is the byte.
    PUSH HL                        ; Keep the caller's HL
    PUSH DE                        ; and DE.
    LD   HL,(BL_LEN)               ; HL is the blob's length so far.
    LD   DE,BL_CCAP                ; Is the buffer full?
    OR   A                         ; Clear carry; A is kept.
    SBC  HL,DE                     ; No carry when the length has reached it.
    JP   NC,BL_OVER                ; A blob too large for the buffer ends the build.
    ADD  HL,DE                     ; HL is the length again.
    INC  HL                        ; Count the new byte
    LD   (BL_LEN),HL               ; in the length.
    DEC  HL                        ; HL is the byte's offset,
    LD   DE,BL_CODE                ; plus the buffer's
    ADD  HL,DE                     ; address.
    LD   (HL),A                    ; Store the byte.
    POP  DE                        ; Restore DE
    POP  HL                        ; and HL.
    RET                            ; The byte is in the blob.

;@ROUTINE IN A,DE,HL CLOBBERS A,BC,DE,HL,CARRY,ZERO,SIGN,PARITY,HALFCARRY
; Append a reference of form A to target HL with addend DE at the blob's
; current offset, then its zero placeholder: a word, or a byte for LO8 and
; HI8. It is kept as given, BL_RLEN bytes, until BL_END encodes it: the
; form, the offset, the target, then the addend, whose word therefore ends
; the references until the next is added (EM_SELF).

BL_REF:                        ; A is the form, HL the target, DE the addend.
    LD   C,A                       ; C is the form.
    PUSH HL                        ; Keep the target.
    LD   HL,BL_RPTR                ; BL_PUT appends
    LD   (BL_CUR),HL               ; to the references:
    CALL BL_PUT                    ; the form,
    LD   HL,(BL_LEN)               ; the offset,
    CALL BL_PUTW                   ; this one;
    POP  HL                        ; the target
    CALL BL_PUTW                   ; and
    EX   DE,HL                     ; the
    CALL BL_PUTW                   ; addend.
    LD   HL,(BL_RCNT)              ; Count the reference.
    INC  HL                        ; One more.
    LD   (BL_RCNT),HL              ; Keep the count for the record.
    XOR  A                         ; The placeholder is zero.
    CALL BL_BYTE                   ; Its first byte.
    LD   A,C                       ; LO8 and HI8 take one byte:
    OR   A                         ; forms 1 and 2 have odd parity,
    RET  PO                        ; so one byte is enough.
    XOR  A                         ; ABS16 and SIZE16 take a word:
    JR   BL_BYTE                   ; the second byte, and return.

;@ROUTINE IN A,HL CLOBBERS A,BC,DE,HL,CARRY,ZERO,SIGN,PARITY,HALFCARRY
; Record that the code from the blob's current offset belongs to line HL of
; part A (object format §8), A below 255. An entry at the same offset and
; part as the last one replaces its line, as a statement that produced no
; code gives way to the next. An entry is kept as given, BL_LLEN bytes,
; until BL_END encodes it: the offset, the part and the line. The entry
; before the first, BL_GUARD, has the part $FF (BL_OPEN), which none has.

BL_LINE:                       ; A is the part, HL the line.
    PUSH HL                        ; Keep the line.
    LD   C,A                       ; C is the part.
    LD   HL,(BL_LPTR)              ; Past the last entry:
    DEC  HL                        ; its line's
    DEC  HL                        ; word,
    PUSH HL                        ; kept in case it gives way;
    DEC  HL                        ; its
    LD   A,(HL)                    ; part;
    DEC  HL                        ; its
    LD   D,(HL)                    ; offset,
    DEC  HL                        ; in
    LD   E,(HL)                    ; DE.
    CP   C                         ; The same part (carry clear if so)
    JR   NZ,.NEW                   ; and
    LD   HL,(BL_LEN)               ; the same
    SBC  HL,DE                     ; offset?
    JR   NZ,.NEW                   ; No: a new entry.
    POP  HL                        ; Yes: the last entry's line
    POP  DE                        ; gives way
    LD   (HL),E                    ; to this
    INC  HL                        ; one,
    LD   (HL),D                    ; both bytes.
    RET                            ; No entry is added.
.NEW:                          ; The entry is new.
    POP  HL                        ; (the last entry's line is kept)
    LD   HL,BL_LPTR                ; BL_PUT appends
    LD   (BL_CUR),HL               ; to the line entries:
    LD   HL,(BL_LEN)               ; this offset,
    CALL BL_PUTW                   ; its word;
    LD   A,C                       ; the part,
    CALL BL_PUT                    ; its byte;
    POP  HL                        ; the line,
    CALL BL_PUTW                   ; its word.
    LD   HL,(BL_LCNT)              ; Count the entry.
    INC  HL                        ; One more.
    LD   (BL_LCNT),HL              ; Keep the count for the line record.
    RET                            ; The statement is marked.

;@ROUTINE IN HL CLOBBERS A,CARRY,ZERO,SIGN,PARITY,HALFCARRY
; Append the word HL to the buffer at BL_CUR, low byte first.

BL_PUTW:                       ; HL is the word.
    LD   A,L                       ; The low byte first.
    CALL BL_PUT                    ; Append it.
    LD   A,H                       ; Then the high byte.

;@ROUTINE IN A CLOBBERS CARRY,ZERO,SIGN,PARITY,HALFCARRY
; Append A to the buffer whose pointer BL_CUR addresses: BL_RPTR or
; BL_LPTR, each just past the end of its buffer, so that it is the limit too.

BL_PUT:                        ; A is the byte.
    PUSH HL                        ; Keep the caller's HL.
    PUSH DE                        ; And DE.
    LD   HL,(BL_CUR)               ; HL addresses the pointer, the buffer's end.
    LD   E,(HL)                    ; DE is
    INC  HL                        ; the next
    LD   D,(HL)                    ; free byte.
    DEC  HL                        ; HL is the end again.
    EX   DE,HL                     ; HL is the free byte, DE the end.
    OR   A                         ; Clear carry; A is kept.
    SBC  HL,DE                     ; No carry at the buffer's end.
    JP   NC,BL_OVER                ; Too many references or statements for one blob.
    ADD  HL,DE                     ; HL is the free byte again.
    LD   (HL),A                    ; Store the byte.
    INC  HL                        ; The next byte is free.
    EX   DE,HL                     ; DE is it, HL the pointer.
    LD   (HL),E                    ; Keep it,
    INC  HL                        ; low byte
    LD   (HL),D                    ; and high byte.
    POP  DE                        ; Restore DE
    POP  HL                        ; and HL.
    RET                            ; The byte is kept.

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

BL_NONE:                       ; The table of a blob with no short jump:
    DW   BL_PAST                   ; its sentinel alone.

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

;@ROUTINE CLOBBERS A,BC,DE,HL,CARRY,ZERO,SIGN,PARITY,HALFCARRY
; Write the blob: its directory record with its references, its bytes to
; the byte stream and, for code, its line record, its short jumps shrunk
; (BL_SHORT): every offset and every addend naming the blob itself mapped
; (BL_MAP), each short jump written as a JR and its reference dropped.
; References and line entries are encoded here (object format §5.2, §8):
; a control byte with the offset's delta from the last one, 63 (for a
; reference) or 127 (for a line entry) escaping to an absolute word; a
; reference's control has bit 6 when an addend follows and bit 7 when a
; form does, then the form, the target and the addend; a line entry's
; has bit 7 when its part changes, then the part, then the line.

BL_END:                        ; The blob is complete in memory.
    PUSH IX                        ; Keep the caller's IX.
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
    LD   HL,BL_REFS                ; From the first reference.
.REF:                          ; HL is a kept reference.
    LD   DE,(BL_RPTR)              ; Is it past the last?
    OR   A                         ; Zero
    SBC  HL,DE                     ; when
    ADD  HL,DE                     ; it is.
    JR   Z,.BYTES                  ; Then the bytes follow.
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
    JR   Z,.DROP                   ; A short jump's: dropped.
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
    LD   D,(HL)                    ; and HL the
    INC  HL                        ; next reference.
    JR   NZ,.ADDEND                ; Another blob's addend is kept;
    EX   DE,HL                     ; the blob's own,
    PUSH BC                        ; (the flags kept)
    CALL BL_MAP                    ; an offset in it,
    POP  BC                        ; moves as
    EX   DE,HL                     ; the code does.
.ADDEND:                       ; DE is the addend.
    BIT  6,B                       ; Is there one?
    JR   Z,.REF                    ; No: the next reference.
    EX   DE,HL                     ; Yes:
    CALL OUT_WORD                  ; its word.
    EX   DE,HL                     ; HL is the next reference.
    JR   .REF                      ; Encode it.
.DROP:                         ; DE is a short jump's reference's target.
    LD   HL,4                      ; Its target and addend
    ADD  HL,DE                     ; are passed over.
    JR   .REF                      ; The next reference.
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
    LD   HL,BL_CODE                ; Its address
    ADD  HL,DE                     ; in the buffer.
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
    LD   HL,BL_CODE                ; The JP's
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
    JR   NZ,.DONE                  ; Data has no lines.
    LD   A,(BL_FLAGS)              ; Is there a line stream?
    AND  BL_LNOUT                  ; Option N leaves it out.
    JR   Z,.DONE                   ; Then there is nowhere to write them.
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
    LD   HL,BL_LINES               ; From the first entry.
.LINE:                         ; HL is a kept entry.
    LD   DE,(BL_LPTR)              ; Is it past the last?
    OR   A                         ; Zero
    SBC  HL,DE                     ; when
    ADD  HL,DE                     ; it is.
    JR   Z,.DONE                   ; Then the blob is written.
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
    EX   DE,HL                     ; HL is the next entry.
    JR   .LINE                     ; Encode it.
.DONE:                         ; The blob is written.
    POP  IX                        ; Restore the caller's IX.
    RET                            ; The next blob may begin.

;@ROUTINE IN DE,HL CLOBBERS A,BC,DE,HL,IX,CARRY,ZERO,SIGN,PARITY,HALFCARRY
; Write the directory record of blob BL_ORD with size HL and DE references:
; the header byte, the ordinal if it does not follow the last record's, the
; size and the count (a byte, or 255 and a word). Leaves IX at BL_DR.

BL_REC:                        ; HL is the size, DE the count.
    LD   IX,BL_DR                  ; The directory stream.
    PUSH DE                        ; Keep the count
    PUSH HL                        ; and the size.
    LD   HL,(BL_PREV)              ; Does the ordinal follow the last one?
    INC  HL                        ; HL is the implicit ordinal.
    LD   DE,(BL_ORD)               ; DE is the blob's.
    OR   A                         ; Clear carry.
    SBC  HL,DE                     ; Zero if they agree.
    LD   A,(BL_HEAD)               ; A is the header bits.
    JR   Z,.IMPLICIT               ; An implicit ordinal needs no word.
    OR   BL_EXPL                   ; Bit 3: the ordinal follows.
.IMPLICIT:                     ; A is the header byte.
    LD   C,A                       ; Keep it: OUT_BYTE does not keep A.
    CALL OUT_BYTE                  ; Append it.
    BIT  3,C                       ; Is the ordinal explicit (BL_EXPL)?
    EX   DE,HL                     ; HL is the ordinal.
    CALL NZ,OUT_WORD               ; Then it follows the header.
    LD   (BL_PREV),HL              ; The next record follows this one.
    EX   DE,HL                     ; DE is the ordinal.
    LD   HL,(BL_HIGH)              ; Is it the highest yet?
    OR   A                         ; Clear carry.
    SBC  HL,DE                     ; Carry if the ordinal is above it.
    JR   NC,.LOWER                 ; Not higher: keep the old one.
    LD   (BL_HIGH),DE              ; It is now the highest.
.LOWER:                        ; The trailer's highest ordinal is current.
    LD   HL,(BL_COUNT)             ; Count the record
    INC  HL                        ; for the trailer.
    LD   (BL_COUNT),HL             ; One more blob.
    POP  HL                        ; HL is the size.
    CALL OUT_WORD                  ; Append it.
    POP  HL                        ; HL is the count.
    LD   A,H                       ; Below 255 it takes one byte.
    OR   A                         ; Not if it is above 255,
    JR   NZ,.WIDE                  ; nor if it is 255.
    LD   A,L                       ; A is the count.
    CP   255                       ; Is it 255?
    JP   C,OUT_BYTE                ; No: one byte, and return.
.WIDE:                         ; The count needs a word.
    LD   A,255                     ; 255 escapes
    CALL OUT_BYTE                  ; to a word.
    JP   OUT_WORD                  ; Append the count and return.

;@ROUTINE IN A,DE,HL CLOBBERS A,BC,DE,HL,CARRY,ZERO,SIGN,PARITY,HALFCARRY
; Write the record of bss blob HL, of DE bytes, with header bits A (kind
; BL_KBSS, any root flag and alignment). It has no references and no stored
; bytes (object format §5.1).

BL_BSS:                        ; HL is the ordinal, DE the size, A the header.
    LD   (BL_ORD),HL               ; The record names this ordinal.
    LD   (BL_HEAD),A               ; With these header bits.
    PUSH IX                        ; Keep the caller's IX.
    EX   DE,HL                     ; HL is the size.
    LD   DE,0                      ; No references.
    CALL BL_REC                    ; Write the record.
    POP  IX                        ; Restore the caller's IX.
    RET                            ; The bss blob is written.

;@ROUTINE IN A,DE,HL CLOBBERS A,HL,CARRY,ZERO,SIGN,PARITY,HALFCARRY
; Write the limits control record: stack reserve HL, largest frame DE and
; flags A (object format §5.3).

BL_LIMIT:                      ; HL is the reserve, DE the frame, A the flags.
    PUSH AF                        ; Keep the flags for last.
    LD   A,$1E                     ; Control kind 6, subtype 3: limits,
    CALL BL_CWORD                  ; then the stack reserve.
    POP  AF                        ; The flags follow the frame's high byte:
    LD   H,A                       ; they are the high byte
    LD   L,D                       ; of a word whose low byte is the frame's,
    LD   A,E                       ; after the frame's low byte.
    JR   BL_CWORD                  ; Append the three, and return.

;@ROUTINE IN HL CLOBBERS A,CARRY,ZERO,SIGN,PARITY,HALFCARRY
; Write the entry control record: the program starts at blob HL (object
; format §5.3).

BL_ENTRY:                      ; HL is main's ordinal.
    LD   A,$0E                     ; Control kind 6, subtype 1: entry.

;@ROUTINE IN A,HL CLOBBERS A,CARRY,ZERO,SIGN,PARITY,HALFCARRY
; Append the byte A and then the word HL to the directory stream.

BL_CWORD:                      ; A is the byte, HL the word.
    PUSH IX                        ; Keep the caller's IX.
    LD   IX,BL_DR                  ; The directory stream.
    CALL OUT_BYTE                  ; Append the byte,
    CALL OUT_WORD                  ; then the word.
    POP  IX                        ; Restore the caller's IX.
    RET                            ; Both are in the stream.

;@ROUTINE IN B,DE,HL CLOBBERS A,B,DE,CARRY,ZERO,SIGN,PARITY,HALFCARRY
; Write the name of ordinal HL, the B characters at DE, to the name stream
; (object format §9), keeping at most 31 of them. Nothing is written
; without the stream.

BL_NAME:                       ; HL is the ordinal, DE the name, B its length.
    LD   A,(BL_FLAGS)              ; Is there a name stream?
    AND  BL_NMOUT                  ; Only options M and Y need one.
    RET  Z                         ; Then the name goes nowhere.
    PUSH IX                        ; Keep the caller's IX.
    LD   IX,BL_NM                  ; The name stream.
    CALL OUT_WORD                  ; The ordinal.
    LD   A,31                      ; Is the length
    CP   B                         ; above 31?
    JR   NC,.SHORT                 ; No: it is kept whole.
    LD   B,A                       ; Yes: only 31 characters are kept.
.SHORT:                        ; B is the length to write.
    LD   A,B                       ; The length byte.
    CALL OUT_BYTE                  ; Append it.
.CHAR:                         ; B characters remain.
    LD   A,(DE)                    ; Copy the next one
    CALL OUT_BYTE                  ; to the stream.
    INC  DE                        ; Move to the next.
    DJNZ .CHAR                     ; Until the name is written.
    POP  IX                        ; Restore the caller's IX.
    RET                            ; The name is recorded.

