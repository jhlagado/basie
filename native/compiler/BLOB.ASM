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
;  References and line entries are encoded as they arrive, in the stream's
;  own delta form, because each arrives at a higher offset than the last.
;
;  Principal entries:
;    BL_OPEN    open the streams and write their headers
;    BL_PART    name a source part in the line stream
;    BL_BEGIN   start a blob: ordinal, kind, root flag and alignment
;    BL_BYTE    append a byte to the blob
;    BL_REF     append a reference and its zero placeholder
;    BL_LINE    mark the start of a statement's code
;    BL_END     write the blob's record, bytes and line record
;    BL_BSS     write a bss blob's record: it has a size and nothing else
;    BL_ENTRY   write the entry control record
;    BL_LIMIT  write the limits control record
;    BL_NAME    write an ordinal's name to the name stream
;    BL_CLOSE   write the trailers and close the streams
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
BL_RCAP EQU  512               ; Bytes of encoded references for one blob.
BL_LCAP EQU  512               ; Bytes of encoded line entries for one blob.

; The workspace, from MM_BLOB.
BL_FLAGS EQU  MM_BLOB          ; Byte: the BL_OPEN flags.
BL_NAMEP EQU  BL_FLAGS+1       ; Word: the streams' drive and name, for BL_OPEN.
BL_STAMP EQU  BL_NAMEP+2       ; Word: the compilation stamp of every header.
BL_ORD EQU  BL_STAMP+2         ; Word: the blob being built.
BL_HEAD EQU  BL_ORD+2          ; Byte: its kind, root and alignment bits.
BL_LEN EQU  BL_HEAD+1          ; Word: its bytes so far.
BL_RPTR EQU  BL_LEN+2          ; Word: the next free byte of BL_REFS.
BL_RCNT EQU  BL_RPTR+2         ; Word: its references so far.
BL_RLAST EQU  BL_RCNT+2        ; Word: the offset of its last reference.
BL_LPTR EQU  BL_RLAST+2        ; Word: the next free byte of BL_LINES.
BL_LCNT EQU  BL_LPTR+2         ; Word: its line entries so far.
BL_LLAST EQU  BL_LCNT+2        ; Word: the offset of its last line entry.
BL_LPART EQU  BL_LLAST+2       ; Byte: the part of its last line entry.
BL_LSRC EQU  BL_LPART+1        ; Word: where the last entry's line number is.
BL_PREV EQU  BL_LSRC+2         ; Word: the ordinal of the last blob record.
BL_COUNT EQU  BL_PREV+2        ; Word: blob records written.
BL_HIGH EQU  BL_COUNT+2        ; Word: the highest ordinal written.
BL_DR EQU  BL_HIGH+2           ; The directory stream's record.
BL_BY EQU  BL_DR+OUT_SIZE      ; The byte stream's record.
BL_LN EQU  BL_BY+OUT_SIZE      ; The line stream's record.
BL_NM EQU  BL_LN+OUT_SIZE      ; The name stream's record.
BL_CODE EQU  BL_NM+OUT_SIZE    ; BL_CCAP bytes: the blob's bytes.
BL_REFS EQU  BL_CODE+BL_CCAP   ; BL_RCAP bytes: its encoded references.
BL_LINES EQU  BL_REFS+BL_RCAP  ; BL_LCAP bytes: its encoded line entries.
BL_WEND EQU  BL_LINES+BL_LCAP  ; The end of the workspace.

;@ROUTINE IN A,DE,HL CLOBBERS A,BC,DE,HL,CARRY,ZERO,SIGN,PARITY,HALFCARRY
; Open the streams named by DE, nine bytes of FCB drive and name, and write
; their headers. HL is the program directory's 20-byte header (object format
; §4.1), magic included, whose stamp and ordinal base the other headers and
; the implicit ordinals follow. A holds BL_LNOUT and BL_NMOUT.

BL_OPEN:                       ; HL is the header, DE the name, A the flags.
    OR   BL_BYOUT                  ; The byte stream is always written.
    LD   (BL_FLAGS),A              ; Keep the flags for the other routines.
    LD   (BL_NAMEP),DE             ; Keep the name for each stream.
    PUSH IX                        ; Keep the caller's IX.
    PUSH HL                        ; Keep the header for the copy.
    LD   DE,6                      ; The stamp is at offset 6.
    ADD  HL,DE                     ; HL addresses it.
    LD   E,(HL)                    ; DE is the stamp,
    INC  HL                        ; low byte first.
    LD   D,(HL)                    ; Every stream carries it.
    LD   (BL_STAMP),DE             ; Keep it for the other headers.
    LD   DE,9                      ; The ordinal base is at offset 16,
    ADD  HL,DE                     ; nine bytes on.
    LD   E,(HL)                    ; DE is the base:
    INC  HL                        ; the first blob's implicit ordinal.
    LD   D,(HL)                    ; A record numbers itself implicitly
    DEC  DE                        ; when it follows the previous one,
    LD   (BL_PREV),DE              ; so the first follows base less one.
    LD   HL,0                      ; No blob is written yet:
    LD   (BL_COUNT),HL             ; no records,
    LD   (BL_HIGH),HL              ; and no highest ordinal.
    LD   IX,BL_DR                  ; The directory stream first.
    LD   HL,BL_TDR                 ; Type $DR.
    CALL .OPEN                     ; Make the file.
    POP  HL                        ; HL is the header.
    LD   B,20                      ; Twenty bytes, magic to padding.
    CALL .COPY                     ; Copy them to the directory stream.
    LD   HL,BL_STAB                ; Then each stream of the table.
.STREAM:                       ; HL is the next table entry.
    LD   A,(HL)                    ; Its flag; zero ends the table.
    OR   A                         ; Is the table done?
    JR   Z,.DONE                   ; Every stream wanted is open.
    LD   C,A                       ; C is the flag.
    INC  HL                        ; The stream's record follows.
    LD   E,(HL)                    ; Its low byte,
    INC  HL                        ; then
    LD   D,(HL)                    ; its high byte.
    INC  HL                        ; HL is the type, then the magic.
    LD   A,(BL_FLAGS)              ; Is this stream wanted?
    AND  C                         ; Test its flag.
    JR   Z,.SKIP                   ; Options leave it out.
    PUSH DE                        ; IX is the stream's record.
    POP  IX                        ; Every OUT_ call takes it there.
    PUSH HL                        ; Keep the type's address.
    CALL .OPEN                     ; Make the file.
    POP  HL                        ; The magic follows the type:
    INC  HL                        ; three bytes
    INC  HL                        ; on
    INC  HL                        ; from it.
    LD   B,4                       ; Four bytes of magic.
    CALL .COPY                     ; Copy them.
    PUSH HL                        ; Keep the table's place.
    LD   HL,1                      ; Version 1.0: major 1,
    CALL OUT_WORD                  ; then minor 0.
    LD   HL,(BL_STAMP)             ; The compilation stamp ties
    CALL OUT_WORD                  ; the streams together.
    POP  HL                        ; HL is the next entry.
    JR   .STREAM                   ; Open it.
.SKIP:                         ; HL is the type of a stream not wanted.
    LD   DE,7                      ; Step over its type and magic.
    ADD  HL,DE                     ; HL is the next entry.
    JR   .STREAM                   ; Consider it.
.DONE:                         ; Every stream wanted is open.
    POP  IX                        ; Restore the caller's IX.
    RET                            ; Blobs may now be written.

;@ROUTINE IN HL,IX CLOBBERS A,BC,DE,HL,CARRY,ZERO,SIGN,PARITY,HALFCARRY
; Open the stream at IX with the program's name and the type at HL.

.OPEN:                         ; HL is the three-character type.
    LD   DE,(BL_NAMEP)             ; DE is the drive and name.
    JP   OUT_OPEN                  ; Make the file and return.

;@ROUTINE IN B,HL,IX OUT HL CLOBBERS A,B,CARRY,ZERO,SIGN,PARITY,HALFCARRY
; Append the B bytes at HL to the stream at IX; HL is left after them.

.COPY:                         ; HL is the next byte.
    LD   A,(HL)                    ; Copy it
    CALL OUT_BYTE                  ; to the stream.
    INC  HL                        ; Move to the next.
    DJNZ .COPY                     ; Until B are done.
    RET                            ; HL is after them.

;@ROUTINE IN A,B,HL CLOBBERS A,B,C,HL,CARRY,ZERO,SIGN,PARITY,HALFCARRY
; Name source part A (0-based) as the B characters at HL, in a part record
; of the line stream (object format §8). Nothing is written without one.

BL_PART:                       ; A is the part's index.
    LD   C,A                       ; Keep the index.
    LD   A,(BL_FLAGS)              ; Is there a line stream?
    AND  BL_LNOUT                  ; Option N leaves it out.
    RET  Z                         ; Then there is nothing to name.
    PUSH IX                        ; Keep the caller's IX.
    LD   IX,BL_LN                  ; Write to the line stream.
    LD   A,1                       ; Tag 1: a part record.
    CALL OUT_BYTE                  ; Append it.
    LD   A,C                       ; The part's index.
    CALL OUT_BYTE                  ; Append it.
    LD   A,B                       ; The name's length.
    CALL OUT_BYTE                  ; Append it.
.NAME:                         ; B characters of the name remain.
    LD   A,(HL)                    ; Copy the next one
    CALL OUT_BYTE                  ; to the stream.
    INC  HL                        ; Move to the next.
    DJNZ .NAME                     ; Until the name is written.
    POP  IX                        ; Restore the caller's IX.
    RET                            ; The part may now be cited.

;@ROUTINE IN A,HL CLOBBERS A,HL,CARRY,ZERO,SIGN,PARITY,HALFCARRY
; Start blob HL. A is its header byte without the explicit-ordinal bit: the
; kind, BL_ROOT if the linker must keep it, and the alignment code in bits
; 5 to 7. The blob starts empty.

BL_BEGIN:                      ; HL is the ordinal, A the header.
    LD   (BL_ORD),HL               ; Keep the ordinal for the record.
    LD   (BL_HEAD),A               ; Keep the header bits.
    LD   HL,0                      ; Nothing is in the blob yet:
    LD   (BL_LEN),HL               ; no bytes,
    LD   (BL_RCNT),HL              ; no references,
    LD   (BL_LCNT),HL              ; no line entries.
    LD   HL,BL_REFS                ; Both encodings start
    LD   (BL_RPTR),HL              ; at the start of their buffers.
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
; HI8. The reference is encoded as the directory record carries it (object
; format §5.2): a control byte with the offset's delta from the previous
; reference (63 escapes to an absolute word), bit 6 when an addend follows
; and bit 7 when a form follows, then the form, the target and the addend.

BL_REF:                        ; A is the form, HL the target, DE the addend.
    PUSH AF                        ; Keep the form for the placeholder.
    PUSH HL                        ; Keep the target for its word.
    LD   C,A                       ; C is the form.
    LD   B,0                       ; B gathers the control's flag bits.
    OR   A                         ; ABS16 is form 0 and needs no form byte.
    JR   Z,.NOFORM                 ; Any other form does.
    SET  7,B                       ; Bit 7: a form byte follows.
.NOFORM:                       ; C is the form, B its flag.
    LD   A,D                       ; Is the addend zero?
    OR   E                         ; An addend of zero is left out.
    JR   Z,.NOADD                  ; Then bit 6 stays clear.
    SET  6,B                       ; Bit 6: an addend follows.
.NOADD:                        ; B holds the flags.
    PUSH DE                        ; Keep the addend for its word.
    LD   HL,(BL_RCNT)              ; Is this the blob's first reference?
    LD   A,H                       ; Its delta counts from offset zero,
    OR   L                         ; not from a previous reference.
    LD   HL,(BL_LEN)               ; HL is this reference's offset.
    PUSH HL                        ; Keep it to become the last offset.
    JR   Z,.FIRST                  ; The first: the delta is the offset itself.
    LD   DE,(BL_RLAST)             ; Subtract the last reference's offset.
    OR   A                         ; Clear carry.
    SBC  HL,DE                     ; HL is the delta, at least 1.
.FIRST:                        ; HL is the delta.
    LD   A,H                       ; Does it fit the control byte?
    OR   A                         ; A delta above 255 does not,
    JR   NZ,.ESCAPE                ; nor does one above 62.
    LD   A,L                       ; A is the delta.
    CP   63                        ; Is it 63 or more?
    JR   NC,.ESCAPE                ; Then the offset goes in a word.
    OR   B                         ; Combine the delta with the flags.
    CALL .PUT                      ; The control byte.
    POP  HL                        ; HL is the offset; nothing more to say of it.
    JR   .TAIL                     ; Then the form, target and addend.
.ESCAPE:                       ; The delta needs a word.
    LD   A,63                      ; Control 63: an absolute offset follows.
    OR   B                         ; With the flags.
    CALL .PUT                      ; The control byte.
    POP  HL                        ; HL is the absolute offset.
    CALL .PUTW                     ; Its word.
.TAIL:                         ; The control and any offset are encoded.
    LD   HL,(BL_LEN)               ; This offset becomes the last one.
    LD   (BL_RLAST),HL             ; The next reference's delta counts from it.
    LD   HL,(BL_RCNT)              ; Count the reference.
    INC  HL                        ; One more.
    LD   (BL_RCNT),HL              ; Keep the count for the record.
    BIT  7,B                       ; Is there a form byte?
    LD   A,C                       ; A is the form.
    CALL NZ,.PUT                   ; Append it when nonzero.
    POP  DE                        ; DE is the addend.
    POP  HL                        ; HL is the target.
    CALL .PUTW                     ; The target's ordinal.
    EX   DE,HL                     ; HL is the addend.
    BIT  6,B                       ; Is there an addend?
    CALL NZ,.PUTW                  ; Append it when nonzero.
    POP  AF                        ; A is the form again.
    XOR  A                         ; The placeholder is zero.
    CALL BL_BYTE                   ; Its first byte.
    LD   A,C                       ; LO8 and HI8 take one byte;
    DEC  A                         ; forms 1 and 2
    CP   2                         ; fall below 2 after the decrement.
    RET  C                         ; One byte is enough.
    XOR  A                         ; ABS16 and SIZE16 take a word:
    JP   BL_BYTE                   ; the second byte, and return.

;@ROUTINE IN HL CLOBBERS A,CARRY,ZERO,SIGN,PARITY,HALFCARRY
; Append the word HL to the reference encoding, low byte first.

.PUTW:                         ; HL is the word.
    LD   A,L                       ; The low byte first.
    CALL .PUT                      ; Append it.
    LD   A,H                       ; Then the high byte.

;@ROUTINE IN A CLOBBERS CARRY,ZERO,SIGN,PARITY,HALFCARRY
; Append A to the reference encoding.

.PUT:                          ; A is the byte.
    PUSH HL                        ; Keep the caller's HL.
    PUSH DE                        ; And DE.
    LD   HL,(BL_RPTR)              ; HL is the next free byte.
    LD   DE,BL_REFS+BL_RCAP        ; Is the buffer full?
    OR   A                         ; Clear carry; A is kept.
    SBC  HL,DE                     ; No carry at the buffer's end.
    JP   NC,BL_OVER                ; Too many references for one blob.
    ADD  HL,DE                     ; HL is the free byte again.
    LD   (HL),A                    ; Store the byte.
    INC  HL                        ; The next byte is free.
    LD   (BL_RPTR),HL              ; Keep it.
    POP  DE                        ; Restore DE
    POP  HL                        ; and HL.
    RET                            ; The byte is encoded.

;@ROUTINE IN A,HL CLOBBERS A,BC,DE,HL,CARRY,ZERO,SIGN,PARITY,HALFCARRY
; Record that the code from the blob's current offset belongs to line HL of
; part A (object format §8). An entry at the same offset and part as the
; last one replaces its line, as a statement that produced no code gives way
; to the next. Each entry is a control byte, the offset's delta from the
; last entry with 127 escaping to an absolute word and bit 7 when the part
; changes, then the part if it changed, then the line.

BL_LINE:                       ; A is the part, HL the line.
    LD   C,A                       ; C is the part.
    EX   DE,HL                     ; DE is the line.
    LD   HL,(BL_LCNT)              ; Is this the blob's first entry?
    LD   A,H                       ; With none before it, the part
    OR   L                         ; always changes and the delta is the offset.
    LD   HL,(BL_LEN)               ; HL is the entry's offset.
    JR   Z,.NEW                    ; The first entry is new.
    PUSH DE                        ; Keep the line across the comparison.
    LD   DE,(BL_LLAST)             ; DE is the last entry's offset.
    OR   A                         ; Clear carry.
    SBC  HL,DE                     ; HL is the delta.
    POP  DE                        ; DE is the line again.
    JR   NZ,.DELTA                 ; Code has been added since the last entry.
    LD   A,(BL_LPART)              ; Same offset: the same part as well?
    CP   C                         ; Two entries at one offset need two parts.
    JR   NZ,.DELTA                 ; Different parts: a new entry.
    LD   HL,(BL_LSRC)              ; Same part: the last entry's line
    LD   (HL),E                    ; gives way to this one,
    INC  HL                        ; low byte
    LD   (HL),D                    ; and high byte.
    RET                            ; No entry is added.
.NEW:                          ; HL is the delta, the whole offset.
    LD   B,$80                     ; The first entry names its part.
    JR   .CONTROL                  ; Encode it.
.DELTA:                        ; HL is the delta from the last entry.
    LD   B,0                       ; Bit 7 only if the part changes.
    LD   A,(BL_LPART)              ; Does it?
    CP   C                         ; Compare the parts.
    JR   Z,.CONTROL                ; The same part: no part byte.
    LD   B,$80                     ; A new part: bit 7 and a part byte.
.CONTROL:                      ; HL is the delta, B the part flag.
    PUSH DE                        ; Keep the line for the end.
    LD   A,H                       ; Does the delta fit the control byte?
    OR   A                         ; Not if it is above 255,
    JR   NZ,.FAR                   ; nor if it is above 126.
    LD   A,L                       ; A is the delta.
    CP   127                       ; Is it 127 or more?
    JR   NC,.FAR                   ; Then the offset goes in a word.
    OR   B                         ; Combine it with the part flag.
    CALL .PUT                      ; The control byte.
    JR   .PART                     ; Then the part, if any.
.FAR:                          ; The delta needs a word.
    LD   A,127                     ; Control 127: an absolute offset follows.
    OR   B                         ; With the part flag.
    CALL .PUT                      ; The control byte.
    LD   HL,(BL_LEN)               ; HL is the absolute offset.
    CALL .PUTW                     ; Its word.
.PART:                         ; The control and any offset are encoded.
    BIT  7,B                       ; Has the part changed?
    LD   A,C                       ; A is the part.
    CALL NZ,.PUT                   ; Name it when it has.
    LD   (BL_LPART),A              ; It is now the last entry's part.
    LD   HL,(BL_LEN)               ; This offset is now the last entry's.
    LD   (BL_LLAST),HL             ; The next delta counts from it.
    LD   HL,(BL_LPTR)              ; The line number goes here:
    LD   (BL_LSRC),HL              ; a later entry at this offset may replace it.
    POP  HL                        ; HL is the line.
    CALL .PUTW                     ; Its word.
    LD   HL,(BL_LCNT)              ; Count the entry.
    INC  HL                        ; One more.
    LD   (BL_LCNT),HL              ; Keep the count for the line record.
    RET                            ; The statement is marked.

;@ROUTINE IN HL CLOBBERS A,CARRY,ZERO,SIGN,PARITY,HALFCARRY
; Append the word HL to the line encoding, low byte first.

.PUTW:                         ; HL is the word.
    LD   A,L                       ; The low byte first.
    CALL .PUT                      ; Append it.
    LD   A,H                       ; Then the high byte.

;@ROUTINE IN A CLOBBERS CARRY,ZERO,SIGN,PARITY,HALFCARRY
; Append A to the line encoding.

.PUT:                          ; A is the byte.
    PUSH HL                        ; Keep the caller's HL.
    PUSH DE                        ; And DE.
    LD   HL,(BL_LPTR)              ; HL is the next free byte.
    LD   DE,BL_LINES+BL_LCAP       ; Is the buffer full?
    OR   A                         ; Clear carry; A is kept.
    SBC  HL,DE                     ; No carry at the buffer's end.
    JP   NC,BL_OVER                ; Too many statements for one blob.
    ADD  HL,DE                     ; HL is the free byte again.
    LD   (HL),A                    ; Store the byte.
    INC  HL                        ; The next byte is free.
    LD   (BL_LPTR),HL              ; Keep it.
    POP  DE                        ; Restore DE
    POP  HL                        ; and HL.
    RET                            ; The byte is encoded.

;@ROUTINE CLOBBERS A,BC,DE,HL,CARRY,ZERO,SIGN,PARITY,HALFCARRY
; Write the blob: its directory record with its references, its bytes to
; the byte stream and, for code, its line record.

BL_END:                        ; The blob is complete in memory.
    PUSH IX                        ; Keep the caller's IX.
    LD   HL,(BL_LEN)               ; The record gives the blob's size.
    LD   DE,(BL_RCNT)              ; And its reference count.
    CALL BL_REC                    ; Write the header, ordinal, size and count.
    LD   HL,BL_REFS                ; Then the references,
    LD   DE,(BL_RPTR)              ; as encoded,
    CALL .COPY                     ; to the directory stream.
    LD   IX,BL_BY                  ; The bytes go to the byte stream.
    LD   HL,BL_CODE                ; From the buffer's start
    LD   DE,(BL_LEN)               ; for the blob's length:
    ADD  HL,DE                     ; HL is the end,
    EX   DE,HL                     ; DE the end,
    LD   HL,BL_CODE                ; HL the start.
    CALL .COPY                     ; Append them.
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
    LD   HL,BL_LINES               ; Then the entries,
    LD   DE,(BL_LPTR)              ; as encoded.
    CALL .COPY                     ; Append them.
.DONE:                         ; The blob is written.
    POP  IX                        ; Restore the caller's IX.
    RET                            ; The next blob may begin.

;@ROUTINE IN DE,HL,IX CLOBBERS A,HL,CARRY,ZERO,SIGN,PARITY,HALFCARRY
; Append the bytes from HL up to DE to the stream at IX.

.COPY:                         ; HL is the first byte, DE the end.
    LD   A,L                       ; Has HL reached DE?
    CP   E                         ; Compare the low bytes,
    JR   NZ,.MORE                  ; then the high bytes.
    LD   A,H                       ; Equal low bytes:
    CP   D                         ; the high bytes decide.
    RET  Z                         ; Every byte is appended.
.MORE:                         ; HL is below DE.
    LD   A,(HL)                    ; Append the byte
    CALL OUT_BYTE                  ; to the stream.
    INC  HL                        ; Move to the next.
    JR   .COPY                     ; Until DE.

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

;@ROUTINE IN HL CLOBBERS A,CARRY,ZERO,SIGN,PARITY,HALFCARRY
; Write the entry control record: the program starts at blob HL (object
; format §5.3).

BL_ENTRY:                      ; HL is main's ordinal.
    PUSH IX                        ; Keep the caller's IX.
    LD   IX,BL_DR                  ; The directory stream.
    LD   A,$0E                     ; Control kind 6, subtype 1: entry.
    CALL OUT_BYTE                  ; Append it.
    CALL OUT_WORD                  ; The entry's ordinal.
    POP  IX                        ; Restore the caller's IX.
    RET                            ; The entry is recorded.

;@ROUTINE IN A,DE,HL CLOBBERS A,CARRY,ZERO,SIGN,PARITY,HALFCARRY
; Write the limits control record: stack reserve HL, largest frame DE and
; flags A (object format §5.3).

BL_LIMIT:                      ; HL is the reserve, DE the frame, A the flags.
    PUSH IX                        ; Keep the caller's IX.
    LD   IX,BL_DR                  ; The directory stream.
    PUSH AF                        ; Keep the flags for last.
    LD   A,$1E                     ; Control kind 6, subtype 3: limits.
    CALL OUT_BYTE                  ; Append it.
    CALL OUT_WORD                  ; The stack reserve.
    EX   DE,HL                     ; HL is the largest frame.
    CALL OUT_WORD                  ; Append it.
    EX   DE,HL                     ; Restore HL.
    POP  AF                        ; A is the flags.
    CALL OUT_BYTE                  ; Append them.
    POP  IX                        ; Restore the caller's IX.
    RET                            ; The limits are recorded.

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
    LD   A,B                       ; A is the length.
    CP   32                        ; Is it above 31?
    JR   C,.SHORT                  ; No: it is kept whole.
    LD   B,31                      ; Yes: only 31 characters are kept.
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

;@ROUTINE CLOBBERS A,BC,DE,HL,CARRY,ZERO,SIGN,PARITY,HALFCARRY
; Write the streams' trailers and close them: the directory's blob count,
; byte stream length, highest ordinal and CRC; the line stream's end tag and
; CRC; the name stream's zero ordinal and CRC.

BL_CLOSE:                      ; Every blob is written.
    PUSH IX                        ; Keep the caller's IX.
    LD   IX,BL_DR                  ; The directory's trailer.
    LD   A,$FF                     ; Its marker.
    CALL OUT_BYTE                  ; Append it.
    LD   HL,(BL_COUNT)             ; The number of blob records.
    CALL OUT_WORD                  ; Append it.
    LD   HL,(BL_BY+OUT_CNT)        ; The byte stream's length, without its
    LD   DE,-8                     ; eight-byte header: the low word,
    ADD  HL,DE                     ; less 8, carry clear on a borrow.
    PUSH HL                        ; Keep it; the carry must reach the high word.
    LD   HL,(BL_BY+OUT_CNT+2)      ; The high word,
    LD   DE,$FFFF                  ; less the borrow:
    ADC  HL,DE                     ; adding $FFFF and the carry does it.
    EX   (SP),HL                   ; HL is the low word; the high word waits.
    CALL OUT_WORD                  ; Append the low word.
    POP  HL                        ; HL is the high word.
    CALL OUT_WORD                  ; Append it.
    LD   HL,(BL_HIGH)              ; The highest ordinal.
    CALL OUT_WORD                  ; Append it.
    XOR  A                         ; A reserved zero byte.
    CALL OUT_BYTE                  ; Append it.
    CALL OUT_CRC                   ; The CRC of the whole stream.
    CALL OUT_END                   ; Close the directory.
    LD   IX,BL_BY                  ; The byte stream has no trailer.
    CALL OUT_END                   ; Close it.
    LD   A,(BL_FLAGS)              ; Is there a line stream?
    AND  BL_LNOUT                  ; Option N leaves it out.
    JR   Z,.NOLINES                ; Then skip it.
    LD   IX,BL_LN                  ; The line stream.
    LD   A,$FF                     ; Its end tag.
    CALL OUT_BYTE                  ; Append it.
    CALL OUT_CRC                   ; Its CRC.
    CALL OUT_END                   ; Close it.
.NOLINES:                      ; The line stream is closed if it was open.
    LD   A,(BL_FLAGS)              ; Is there a name stream?
    AND  BL_NMOUT                  ; Only options M and Y need one.
    JR   Z,.DONE                   ; Then skip it.
    LD   IX,BL_NM                  ; The name stream.
    LD   HL,0                      ; Ordinal zero ends it.
    CALL OUT_WORD                  ; Append it.
    CALL OUT_CRC                   ; Its CRC.
    CALL OUT_END                   ; Close it.
.DONE:                         ; Every stream is closed.
    POP  IX                        ; Restore the caller's IX.
    RET                            ; The linker may read them.

; Stream types and magic numbers. BL_STAB lists the streams after the
; directory: each entry is the flag that wants it, its record, its type and
; its magic; a zero flag ends the table.

BL_TDR: DB   "$DR"             ; The directory stream's type.
BL_STAB:                       ; The other streams, in the order they open.
    DB   BL_BYOUT                  ; The byte stream, always.
    DW   BL_BY                     ; Its record.
    DB   "$BYBSIB"                 ; Its type and magic.
    DB   BL_LNOUT                  ; The line stream, unless option N.
    DW   BL_LN                     ; Its record.
    DB   "$LNBSIL"                 ; Its type and magic.
    DB   BL_NMOUT                  ; The name stream, with option M or Y.
    DW   BL_NM                     ; Its record.
    DB   "$NMBSIN"                 ; Its type and magic.
    DB   0                         ; The end of the table.
