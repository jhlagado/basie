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
;  written until the blob ends. It is built in the free memory of the
;  source area (MEMORY.ASM), which it shares with the symbol table, the
;  routine's waiting constants and the name heap: its bytes from BL_CBASE
;  up, after the waiting constants (RG_PEND), and its log, its references
;  and line entries, BL_ELEN bytes each and in the order given, from the
;  name heap's bottom (NH_PTR) down to BL_LBOT. The memory moves under
;  them: the bytes up as the symbol table and the constants grow (RG_LIFT),
;  the log down as the name heap does (TK_KEEP), so a word that must find
;  an entry again keeps its distance from the heap (BL_FLIP), not its
;  address. A blob is as large as the free memory, below 16K. BL_BEGIN
;  starts one; BL_BYTE, BL_REF and BL_LINE add its bytes, references and
;  line entries; BL_END writes them.
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
;  The program supplies MM_BLOB, the base of this module's workspace,
;  RG_PEND and NH_PTR, the free memory's bounds, and three routines that do
;  not return: OUT_FAIL for a full disk or directory, BL_OVER for a blob of
;  16K, and MM_FULL for a blob the free memory cannot hold. The routines
;  that write to a stream (BL_END, BL_BSS, BL_ENTRY, BL_LIMIT, BL_NAME)
;  leave IX at it; every routine preserves IY.

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

BL_ELEN EQU  7                 ; Bytes of one entry of the log.
BL_TLINE EQU  $FF              ; A line entry's first byte; a reference's is its form.
BL_PAST EQU  $7FFF             ; An offset past every blob's: the jumps' sentinel.

; The workspace, from MM_BLOB.
BL_FLAGS EQU  MM_BLOB          ; Byte: the BL_OPEN flags.
BL_NAMEP EQU  BL_FLAGS+1       ; Word: the streams' drive and name, for BL_OPEN.
BL_STAMP EQU  BL_NAMEP+2       ; Word: the compilation stamp of every header.
BL_ORD EQU  BL_STAMP+2         ; Word: the blob being built.
BL_HEAD EQU  BL_ORD+2          ; Byte: its kind, root and alignment bits.
BL_LEN EQU  BL_HEAD+1          ; Word: its bytes so far.
BL_CBASE EQU  BL_LEN+2         ; Word: its first byte's address; high byte zero when none is built.
BL_LBOT EQU  BL_CBASE+2        ; Word: its log's bottom, its last entry.
BL_LLAST EQU  BL_LBOT+2        ; Word: its last line entry (BL_FLIP), zero when none.
BL_RCNT EQU  BL_LLAST+2        ; Word: its references so far.
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
BL_WEND EQU  BL_NM+OUT_SIZE    ; The end of the workspace.

;@ROUTINE IN A,HL CLOBBERS A,HL,CARRY,ZERO,SIGN,PARITY,HALFCARRY
; Start blob HL. A is its header byte without the explicit-ordinal bit: the
; kind, BL_ROOT if the linker must keep it, and the alignment code in bits
; 5 to 7. The blob starts empty, with no short jump (BL_NONE): its bytes
; after the waiting constants, its log empty below the name heap.

BL_BEGIN:                      ; HL is the ordinal, A the header.
    LD   (BL_ORD),HL               ; Keep the ordinal for the record.
    LD   (BL_HEAD),A               ; Keep the header bits.
    LD   HL,(RG_PEND)              ; Its bytes start
    LD   (BL_CBASE),HL             ; after the waiting constants,
    LD   HL,(NH_PTR)               ; its log
    LD   (BL_LBOT),HL              ; below the name heap.
    LD   HL,0                      ; Nothing is in the blob yet:
    LD   (BL_LEN),HL               ; no bytes,
    LD   (BL_LLAST),HL             ; no line entry,
    LD   (BL_RCNT),HL              ; no references,
    LD   (BL_LCNT),HL              ; no line entries.
    LD   HL,BL_NONE                ; No jump is short until BL_SHORT
    LD   (BL_JUMPS),HL             ; says so: the table is
    LD   (BL_JPEND),HL             ; its sentinel alone.
    RET                            ; The blob is ready for its bytes.

;@ROUTINE IN A CLOBBERS CARRY,ZERO,SIGN,PARITY,HALFCARRY
; Append A to the blob's bytes, below its log (MM_FULL) and its 16K
; (BL_OVER). Every register but F is kept.

BL_BYTE:                       ; A is the byte.
    PUSH HL                        ; Keep the caller's HL
    PUSH DE                        ; and DE.
    LD   HL,(BL_LEN)               ; One byte
    INC  HL                        ; more,
    BIT  6,H                       ; below 16K
    JP   NZ,BL_OVER                ; (BL_PAST's bit),
    LD   (BL_LEN),HL               ; is counted;
    LD   DE,(BL_CBASE)             ; its end
    ADD  HL,DE                     ; must not
    EX   DE,HL                     ; pass
    LD   HL,(BL_LBOT)              ; the log's
    SBC  HL,DE                     ; bottom (carry is clear),
    JP   C,MM_FULL                 ; else DG_ROOM.
    DEC  DE                        ; Its address:
    LD   (DE),A                    ; stored.
    POP  DE                        ; Restore DE
    POP  HL                        ; and HL.
    RET                            ; The byte is in the blob.

;@ROUTINE IN A,DE,HL CLOBBERS A,BC,DE,HL,CARRY,ZERO,SIGN,PARITY,HALFCARRY
; Append a reference of form A to target HL with addend DE at the blob's
; current offset, then its zero placeholder: a word, or a byte for LO8 and
; HI8. It is kept as given until BL_END encodes it, an entry of the log:
; the form, the offset, the target, then the addend, whose word is
; therefore the log's bottom's last until another entry is added (EM_SELF).

BL_REF:                        ; A is the form, HL the target, DE the addend.
    LD   C,A                       ; C is the form.
    PUSH DE                        ; The addend
    PUSH HL                        ; and target kept.
    CALL BL_LOG                    ; The form,
    LD   DE,(BL_LEN)               ; the offset,
    CALL BL_PUTD                   ; this one;
    POP  DE                        ; the target
    CALL BL_PUTD                   ; and
    POP  DE                        ; the
    CALL BL_PUTD                   ; addend.
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
; Record that the code from the blob's current offset belongs to the
; statement at the position whose line word HL addresses, its column word
; after it, in part A (object format §8), A below 255. An entry at the
; same offset and part as the last one replaces its line and column, as a
; statement that produced no code gives way to the next. An entry is kept
; as given until BL_END encodes it, an entry of the log: BL_TLINE, the
; offset, the part, the line and the column, at most 255.

BL_LINE:                       ; A is the part, HL the position's line.
    LD   C,A                       ; C is the part.
    LD   E,(HL)                    ; DE
    INC  HL                        ; is
    LD   D,(HL)                    ; the line,
    INC  HL                        ; A the
    LD   A,(HL)                    ; column,
    INC  HL                        ; or 255
    INC  (HL)                      ; when
    DEC  (HL)                      ; it is
    JR   Z,.COLUMN                 ; any
    LD   A,255                     ; more.
.COLUMN:                       ; A is the column's byte.
    LD   B,A                       ; B is it.
    PUSH DE                        ; Keep the line.
    LD   DE,(BL_LLAST)             ; The last
    LD   A,D                       ; line entry,
    OR   E                         ; if any:
    JR   Z,.NEW                    ; none, a new one.
    CALL BL_FLIP                   ; HL is it,
    INC  HL                        ; past its tag;
    LD   E,(HL)                    ; its
    INC  HL                        ; offset,
    LD   D,(HL)                    ; in
    INC  HL                        ; DE;
    LD   A,(HL)                    ; its part.
    CP   C                         ; The same part (carry clear if so)
    JR   NZ,.NEW                   ; and
    PUSH HL                        ; (kept)
    LD   HL,(BL_LEN)               ; the same
    SBC  HL,DE                     ; offset?
    POP  HL                        ; (its part)
    JR   NZ,.NEW                   ; No: a new entry.
    POP  DE                        ; Yes: its line
    INC  HL                        ; and
    LD   (HL),E                    ; column
    INC  HL                        ; give
    LD   (HL),D                    ; way
    INC  HL                        ; to this
    LD   (HL),B                    ; one's.
    RET                            ; No entry is added.
.NEW:                          ; The entry is new.
    LD   A,BL_TLINE                ; A line entry:
    CALL BL_LOG                    ; its tag,
    LD   D,H                       ; the
    LD   E,L                       ; last
    DEC  DE                        ; line
    PUSH HL                        ; entry
    CALL BL_FLIP                   ; now,
    LD   (BL_LLAST),HL             ; kept;
    POP  HL                        ; then
    LD   DE,(BL_LEN)               ; this offset,
    CALL BL_PUTD                   ; its word;
    LD   (HL),C                    ; the part,
    INC  HL                        ; its byte;
    POP  DE                        ; the line,
    CALL BL_PUTD                   ; its word;
    LD   (HL),B                    ; the column, its byte.
    LD   HL,(BL_LCNT)              ; Count the entry.
    INC  HL                        ; One more.
    LD   (BL_LCNT),HL              ; Keep the count for the line record.
    RET                            ; The statement is marked.

;@ROUTINE IN A OUT HL CLOBBERS DE,CARRY,ZERO,SIGN,PARITY,HALFCARRY
; Add an entry to the blob's log, below its bottom and above the blob's
; bytes (MM_FULL), its first byte A: HL returns past that byte. A and BC
; are kept.

BL_LOG:                        ; A is the entry's first byte.
    PUSH BC                        ; Keep BC
    PUSH AF                        ; and A.
    CALL BL_SPAN                   ; HL is the bytes' end, DE the log's bottom.
    EX   DE,HL                     ; An entry
    LD   BC,-BL_ELEN               ; lower
    ADD  HL,BC                     ; is
    LD   (BL_LBOT),HL              ; the bottom,
    PUSH HL                        ; (kept)
    OR   A                         ; at or above
    SBC  HL,DE                     ; the bytes'
    POP  HL                        ; end,
    JP   C,MM_FULL                 ; else DG_ROOM.
    POP  AF                        ; The first
    LD   (HL),A                    ; byte;
    INC  HL                        ; HL is past it.
    POP  BC                        ; Restore BC.
    RET                            ; Done.
;@ROUTINE IN DE,HL OUT HL CLOBBERS CARRY,ZERO,SIGN,PARITY,HALFCARRY
; Store the word DE at HL, low byte first; HL returns past it.

BL_PUTD:                       ; DE is the word, HL where it goes.
    LD   (HL),E                    ; Low byte,
    INC  HL                        ; then
    LD   (HL),D                    ; high byte.
    INC  HL                        ; HL is past it.
    RET                            ; Done.

;@ROUTINE IN DE OUT HL CLOBBERS CARRY,ZERO,SIGN,PARITY,HALFCARRY
; HL is DE's distance below the name heap's bottom plus 256, the form in
; which a word keeps an entry of the log, which moves with the heap; given
; that form, HL is the entry's address. The form is above 255.

BL_FLIP:                       ; DE is an address or a form.
    LD   HL,(NH_PTR)               ; The heap's
    INC  H                         ; bottom plus 256,
    OR   A                         ; less
    SBC  HL,DE                     ; DE.
    RET                            ; HL is the other.

;@ROUTINE OUT DE,HL CLOBBERS A,CARRY,ZERO,SIGN,PARITY,HALFCARRY
; Return the free memory: from HL, the blob's bytes' end, to DE, its log's
; bottom; with no blob built, from the waiting constants' end (RG_PEND) to
; the name heap's bottom (NH_PTR).

BL_SPAN:                       ; Where is the free memory?
    LD   HL,(RG_PEND)              ; With no blob,
    LD   DE,(NH_PTR)               ; after the constants,
    LD   A,(BL_CBASE+1)            ; below the
    OR   A                         ; heap;
    RET  Z                         ; it is.
    LD   HL,(BL_LEN)               ; Otherwise
    LD   DE,(BL_CBASE)             ; after the
    ADD  HL,DE                     ; blob's bytes,
    LD   DE,(BL_LBOT)              ; below its log.
    RET                            ; Done.

;@ROUTINE IN HL OUT A,HL,CARRY,ZERO CLOBBERS SIGN,PARITY,HALFCARRY,DE
; Step from the log's entry HL, or from the name heap's bottom, to the
; next entry in the order given, the one below it: carry when there is
; none, else A its first byte plus one, zero for a line entry.

BL_NEXT:                       ; HL is an entry.
    LD   DE,-BL_ELEN               ; The one
    ADD  HL,DE                     ; below it,
    LD   DE,(BL_LBOT)              ; at or above
    OR   A                         ; the bottom:
    SBC  HL,DE                     ; carry
    ADD  HL,DE                     ; when it is not.
    RET  C                         ; None: done.
    LD   A,(HL)                    ; Its first byte,
    INC  A                         ; plus one:
    RET                            ; zero for a line entry.

BL_NONE:                       ; The table of a blob with no short jump:
    DW   BL_PAST                   ; its sentinel alone.


;@ROUTINE IN A,DE,HL CLOBBERS A,BC,DE,HL,IX,CARRY,ZERO,SIGN,PARITY,HALFCARRY
; Write the record of bss blob HL, of DE bytes, with header bits A (kind
; BL_KBSS, any root flag and alignment). It has no references and no stored
; bytes (object format §5.1).

BL_BSS:                        ; HL is the ordinal, DE the size, A the header.
    LD   (BL_ORD),HL               ; The record names this ordinal.
    LD   (BL_HEAD),A               ; With these header bits.
    EX   DE,HL                     ; HL is the size.
    LD   DE,0                      ; No references; fall into BL_REC.

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
    LD   A,255                     ; 255 escapes to a word:
    JR   BL_CWORD                  ; both appended; return.

;@ROUTINE IN A,DE,HL CLOBBERS A,HL,IX,CARRY,ZERO,SIGN,PARITY,HALFCARRY
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

;@ROUTINE IN HL CLOBBERS A,IX,CARRY,ZERO,SIGN,PARITY,HALFCARRY
; Write the entry control record: the program starts at blob HL (object
; format §5.3).

BL_ENTRY:                      ; HL is main's ordinal.
    LD   A,$0E                     ; Control kind 6, subtype 1: entry.

;@ROUTINE IN A,HL CLOBBERS A,IX,CARRY,ZERO,SIGN,PARITY,HALFCARRY
; Append the byte A and then the word HL to the directory stream.

BL_CWORD:                      ; A is the byte, HL the word.
    LD   IX,BL_DR                  ; The directory stream.
    CALL OUT_BYTE                  ; Append the byte,
    JP   OUT_WORD                  ; then the word, and return.

;@ROUTINE IN B,DE,HL CLOBBERS A,B,DE,IX,CARRY,ZERO,SIGN,PARITY,HALFCARRY
; Write the name of ordinal HL, the B characters at DE, to the name stream
; (object format §9), keeping at most 31 of them. Nothing is written
; without the stream.

BL_NAME:                       ; HL is the ordinal, DE the name, B its length.
    LD   A,(BL_FLAGS)              ; Is there a name stream?
    AND  BL_NMOUT                  ; Only options M and Y need one.
    RET  Z                         ; Then the name goes nowhere.
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
    RET                            ; The name is recorded.

