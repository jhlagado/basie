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
;  address. When the free memory is full, the blob's bytes are spilled,
;  whole records of them, to NAME.$CD on the streams' drive (BL_SPILL), and
;  read back as the blob is written (BL_RDB); its first record is kept in
;  memory too (BL_REC0), for the prologue's patch (RG_CLOSE). So the log
;  alone bounds a blob, with its 16K. BL_BEGIN
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
;    BL_LIMIT, BL_ENTRY  write the limits and entry records (BLCLOSE.ASM)
;    BL_NAME    write an ordinal's name to the name stream
;    BL_CLOSE   write the trailers and close the streams (BLCLOSE.ASM)
;
;  The opening and closing code each run once, so they are not resident:
;  BLOPEN.ASM is part of the START overlay and BLCLOSE.ASM of CHAIN,
;  which also writes the entry and limits records (RG_END, BL_LIMIT).
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
BL_EBACK EQU  -BL_ELEN         ; From an entry to the next, lower.
BL_TJUMP EQU  4                ; A reference's form 0 after JP or JP cc (BL_SHORT).
BL_TREFS EQU  8                ; First bytes below are references': the form, plus BL_TJUMP.
BL_TLINE EQU  $FF              ; A line entry's first byte.
BL_TLIT EQU  $FE               ; A string literal's (GENAGGR.ASM, GA_LIT).
BL_TLOW EQU  $FD               ; A select label's low value (ACTSEL.ASM).
BL_THIGH EQU  $FC              ; Its high value, the entry after.
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
BL_SPILL EQU  BL_HIGH+2        ; Word: the blob's bytes spilled to NAME.$CD, whole records.
BL_RREC EQU  BL_SPILL+2        ; Byte: the record read back into EM_LTAB (BL_RDB).
BL_LASTB EQU  BL_RREC+1        ; Byte: the byte last appended.
BL_SFCB EQU  BL_LASTB+1        ; 36 bytes: NAME.$CD's FCB.
BL_REC0 EQU  BL_SFCB+36        ; 128 bytes: the first record, once spilled.
BL_DR EQU  BL_REC0+128         ; The directory stream's record.
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
    LD   (BL_SPILL),HL             ; none spilled,
    LD   (BL_LLAST),HL             ; no line entry,
    LD   (BL_RCNT),HL              ; no references,
    LD   (BL_LCNT),HL              ; no line entries.
    LD   HL,BL_NONE                ; No jump is short until BL_SHORT
    LD   (BL_JUMPS),HL             ; says so: the table is
    LD   (BL_JPEND),HL             ; its sentinel alone.
    RET                            ; The blob is ready for its bytes.

;@ROUTINE IN A CLOBBERS CARRY,ZERO,SIGN,PARITY,HALFCARRY
; Append A to the blob's bytes, below its log (spilling them, BL_SPILL,
; then MM_FULL) and its 16K (BL_OVER). Every register but F is kept.

BL_BYTE:                       ; A is the byte.
    PUSH HL                        ; Keep the caller's HL
    PUSH DE                        ; and DE.
.AGAIN:                        ; Is there room?
    LD   HL,(BL_LEN)               ; One byte
    INC  HL                        ; more,
    BIT  6,H                       ; below 16K
    JP   NZ,BL_OVER                ; (BL_PAST's bit),
    LD   DE,(BL_CBASE)             ; ends
    ADD  HL,DE                     ; at or
    EX   DE,HL                     ; below
    LD   HL,(BL_LBOT)              ; the log's
    SBC  HL,DE                     ; bottom (carry is clear),
    JR   C,.FULL                   ; else the bytes spill.
    DEC  DE                        ; Its address:
    LD   (DE),A                    ; stored,
    LD   (BL_LASTB),A              ; the last;
    LD   HL,(BL_LEN)               ; it is
    INC  HL                        ; counted.
    LD   (BL_LEN),HL               ; Done.
    POP  DE                        ; Restore DE
    POP  HL                        ; and HL.
    RET                            ; The byte is in the blob.
.FULL:                         ; No room:
    PUSH AF                        ; (the byte kept)
    CALL BL_FLUSH                  ; spill the bytes,
    JP   C,MM_FULL                 ; if any (DG_ROOM),
    POP  AF                        ; and try
    JR   .AGAIN                    ; again.

;@ROUTINE IN A,DE,HL CLOBBERS A,BC,DE,HL,CARRY,ZERO,SIGN,PARITY,HALFCARRY
; Append a reference of form A to target HL with addend DE at the blob's
; current offset, then its zero placeholder: a word, or a byte for LO8 and
; HI8. It is kept as given until BL_END encodes it, an entry of the log:
; the form, plus BL_TJUMP for a word after JP or JP cc, the offset, the
; target, then the addend, whose word is therefore the log's bottom's last
; until another entry is added (EM_SELF).

BL_REF:                        ; A is the form, HL the target, DE the addend.
    LD   C,A                       ; C is the form.
    PUSH DE                        ; The addend
    PUSH HL                        ; and target kept.
    OR   A                         ; A word's address
    JR   NZ,.LOG                   ; after
    LD   A,(BL_LASTB)              ; JP,
    CP   $C3                       ; or
    JR   Z,.JUMP                   ; JP NZ,
    AND  $E7                       ; Z, NC
    CP   $C2                       ; or C,
    LD   A,0                       ; is
    JR   NZ,.LOG                   ; a jump
.JUMP:                         ; that may
    LD   A,BL_TJUMP                ; shrink (BL_SHORT).
.LOG:                          ; A is the entry's first byte:
    CALL BL_LOG                    ; the form,
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
    CALL WD_GET                    ; DE is the line, A the
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
    CALL WD_GET                    ; its offset, in DE;
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
; bytes (spilling them, then MM_FULL), its first byte A: HL returns past
; that byte. A and BC are kept.

BL_LOG:                        ; A is the entry's first byte.
    PUSH BC                        ; Keep BC
    PUSH AF                        ; and A.
.AGAIN:                        ; Is there room?
    CALL BL_SPAN                   ; HL is the bytes' end, DE the log's bottom.
    EX   DE,HL                     ; An entry
    LD   BC,BL_EBACK               ; lower
    ADD  HL,BC                     ; is
    PUSH HL                        ; (kept)
    OR   A                         ; at or above
    SBC  HL,DE                     ; the bytes'
    POP  HL                        ; end,
    JR   C,.FULL                   ; else they spill.
    LD   (BL_LBOT),HL              ; It is the bottom.
    POP  AF                        ; The first
    LD   (HL),A                    ; byte;
    INC  HL                        ; HL is past it.
    POP  BC                        ; Restore BC.
    RET                            ; Done.
.FULL:                         ; No room:
    CALL BL_FLUSH                  ; spill the bytes,
    JP   C,MM_FULL                 ; if any (DG_ROOM),
    JR   .AGAIN                    ; and try again.
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

;@ROUTINE IN HL OUT A,HL,CARRY CLOBBERS SIGN,PARITY,HALFCARRY,ZERO,DE
; Step from the log's entry HL, or from the name heap's bottom, to the
; next entry in the order given, the one below it: carry when there is
; none, else A its first byte: a reference's form, below BL_TREFS, or
; BL_TLINE, BL_TLIT, BL_TLOW or BL_THIGH. The compiler adds the last
; three for a routine's string literals and its selects' labels; BL_END
; passes over them.

BL_NEXT:                       ; HL is an entry.
    LD   DE,BL_EBACK               ; The one
    ADD  HL,DE                     ; below it,
    LD   DE,(BL_LBOT)              ; at or above
    CALL CP_HLDE                   ; the bottom: carry when it is not.
    RET  C                         ; None: done.
    LD   A,(HL)                    ; Its first byte.
    RET                            ; Done.

;@ROUTINE OUT CARRY CLOBBERS A,ZERO,SIGN,PARITY,HALFCARRY
; Spill the blob's bytes held in memory, all their whole records, to
; NAME.$CD (made at the first, its first record kept in BL_REC0 too), and
; move the rest to where they began: BL_CBASE moves down by the bytes
; spilled. Carry when no blob is built or none of its records is whole;
; a full disk is OUT_FAIL. BC, DE, HL, IX and IY are kept.

BL_FLUSH:                      ; The free memory is full.
    PUSH BC                        ; Keep
    PUSH DE                        ; the
    PUSH HL                        ; registers
    PUSH IX                        ; but A.
    LD   A,(BL_CBASE+1)            ; Is a blob
    OR   A                         ; built?
    SCF                            ; If not,
    JP   Z,.DONE                   ; nothing spills.
    LD   HL,(BL_LEN)               ; Its bytes
    LD   DE,(BL_SPILL)             ; in
    OR   A                         ; memory,
    SBC  HL,DE                     ; in whole
    ADD  HL,HL                     ; records,
    LD   A,H                       ; A;
    CP   1                         ; carry
    JP   C,.DONE                   ; when none.
    LD   B,A                       ; B is their count.
    LD   A,D                       ; Are some
    OR   E                         ; on the disk
    JR   NZ,.MADE                  ; already?
    PUSH BC                        ; If not,
    LD   HL,(BL_CBASE)             ; the first
    LD   DE,BL_REC0                ; record
    LD   BC,128                    ; is kept
    LDIR                           ; in memory,
    LD   HL,(BL_NAMEP)             ; and NAME.$CD
    LD   DE,BL_SFCB                ; is made:
    LD   BC,9                      ; the drive
    LDIR                           ; and name,
    LD   HL,.TYPE                  ; the
    LD   C,3                       ; type,
    LDIR                           ; then
    LD   B,24                      ; zeros.
.ZERO:                         ; B remain.
    LD   (DE),A                    ; A is zero.
    INC  DE                        ; The next.
    DJNZ .ZERO                     ; Until all are.
    LD   DE,BL_SFCB                ; An old
    LD   C,BD_DEL                  ; one
    CALL BL_BDOS                   ; goes;
    LD   DE,BL_SFCB                ; a new
    LD   C,BD_MAKE                 ; one
    CALL BL_BDOS                   ; is made,
    INC  A                         ; or the directory
    JP   Z,OUT_FAIL                ; is full.
    POP  BC                        ; B is the count.
.MADE:                         ; The file is open for writing.
    LD   HL,(BL_CBASE)             ; The bytes
    LD   DE,(BL_SPILL)             ; in memory
    ADD  HL,DE                     ; begin here.
    PUSH HL                        ; Kept.
.RECORD:                       ; HL is a record, B remain.
    PUSH BC                        ; Keep the count
    PUSH HL                        ; and the record.
    EX   DE,HL                     ; It is
    LD   C,BD_DMA                  ; written
    CALL BL_BDOS                   ; from
    LD   DE,BL_SFCB                ; where
    LD   C,BD_WRITE                ; it is,
    CALL BL_BDOS                   ; or the disk
    OR   A                         ; is
    JP   NZ,OUT_FAIL               ; full.
    POP  HL                        ; The next
    LD   DE,128                    ; record
    ADD  HL,DE                     ; on;
    POP  BC                        ; one fewer.
    DJNZ .RECORD                   ; Until all are written.
    LD   DE,(BL_CBASE)             ; HL is the first not spilled.
    PUSH HL                        ; The bytes spilled,
    OR   A                         ; past
    SBC  HL,DE                     ; the base,
    LD   DE,(BL_SPILL)             ; less those spilled before,
    SBC  HL,DE                     ; are BC;
    LD   B,H                       ; the base
    LD   C,L                       ; moves down
    LD   HL,(BL_CBASE)             ; by them,
    SBC  HL,BC                     ; and those spilled
    LD   (BL_CBASE),HL             ; grow
    EX   DE,HL                     ; by
    ADD  HL,BC                     ; them.
    LD   (BL_SPILL),HL             ; HL is the bytes spilled.
    LD   DE,(BL_LEN)               ; The rest,
    EX   DE,HL                     ; from their
    SBC  HL,DE                     ; length,
    LD   B,H                       ; BC of
    LD   C,L                       ; them,
    POP  HL                        ; move from the first not spilled
    POP  DE                        ; to where the bytes began.
    LD   A,B                       ; (none:
    OR   C                         ; none
    JR   Z,.DONE                   ; moved; carry is clear)
    LDIR                           ; Moved: carry is clear.
.DONE:                         ; Carry says whether any spilled.
    POP  IX                        ; Restore
    POP  HL                        ; the
    POP  DE                        ; registers
    POP  BC                        ; but A.
    RET                            ; Done.
.TYPE:                         ; The spill file's type.
    DB   "$CD"                     ; NAME.$CD.

;@ROUTINE IN DE OUT A CLOBBERS CARRY,ZERO,SIGN,PARITY,HALFCARRY
; A is the blob's byte at offset DE, read in order as BL_END writes it:
; from memory, or from the record of NAME.$CD read back into EM_LTAB
; (BL_RBACK opened it), the first from BL_REC0. BC, DE, HL and IX are
; kept.

BL_RDB:                        ; DE is the offset.
    PUSH HL                        ; Keep HL.
    LD   HL,(BL_SPILL)             ; Is it
    SCF                            ; below
    SBC  HL,DE                     ; those spilled?
    JR   NC,.DISK                  ; Then it is on the disk.
    LD   HL,(BL_CBASE)             ; In memory:
    ADD  HL,DE                     ; its
    LD   A,(HL)                    ; byte.
    POP  HL                        ; HL again.
    RET                            ; Done.
.DISK:                         ; Its record,
    LD   A,E                       ; DE
    RLA                            ; over
    LD   A,D                       ; 128,
    RLA                            ; A:
    OR   A                         ; the first
    LD   HL,BL_REC0                ; is kept
    JR   Z,.AT                     ; in memory.
    PUSH BC                        ; Keep BC.
    LD   C,A                       ; C is the record.
.READ:                         ; Is it the one read?
    LD   A,(BL_RREC)               ; The record read
    CP   C                         ; is it,
    JR   NC,.HELD                  ; or the next is read:
    INC  A                         ; the next
    LD   (BL_RREC),A               ; record
    CALL BL_RNEXT                  ; into EM_LTAB.
    JR   .READ                     ; Until it is.
.HELD:                         ; EM_LTAB holds it.
    POP  BC                        ; BC again.
    LD   HL,EM_LTAB                ; Its bytes.
.AT:                           ; HL is the record.
    LD   A,E                       ; The byte
    AND  $7F                       ; in it,
    ADD  A,L                       ; at
    LD   L,A                       ; HL
    JR   NC,.BYTE                  ; (a carry
    INC  H                         ; is the page's).
.BYTE:                         ; HL is the byte.
    LD   A,(HL)                    ; A is it.
    POP  HL                        ; HL again.
    RET                            ; Done.

;@ROUTINE CLOBBERS A,CARRY,ZERO,SIGN,PARITY,HALFCARRY
; Read NAME.$CD's next record into EM_LTAB (BL_RDB); the end of the file
; is OUT_FAIL. BC, DE, HL, IX and IY are kept.

BL_RNEXT:                      ; The next record is wanted.
    PUSH BC                        ; Keep
    PUSH DE                        ; the
    PUSH HL                        ; registers.
    LD   DE,EM_LTAB                ; Into
    LD   C,BD_DMA                  ; the label
    CALL BL_BDOS                   ; table,
    LD   DE,BL_SFCB                ; the
    LD   C,BD_READ                 ; next
    CALL BL_BDOS                   ; record,
    OR   A                         ; or
    JP   NZ,OUT_FAIL               ; the file is short.
    POP  HL                        ; Restore
    POP  DE                        ; the
    POP  BC                        ; registers.
    RET                            ; Done.

;@ROUTINE CLOBBERS A,BC,DE,HL,CARRY,ZERO,SIGN,PARITY,HALFCARRY
; NAME.$CD, written, is read back from its start (BL_RDB): closed, opened
; again, its first record read, which BL_REC0 replaces.

BL_RBACK:                      ; The blob's bytes spilled.
    LD   DE,BL_SFCB                ; Close
    LD   C,BD_CLOSE                ; the
    CALL BL_BDOS                   ; file,
    CALL .RESET                    ; open it
    LD   C,BD_OPEN                 ; again,
    CALL BL_BDOS                   ; from
    CALL .RESET                    ; its start,
    XOR  A                         ; and read
    LD   (BL_RREC),A               ; its first
    JR   BL_RNEXT                  ; record; return.
.RESET:                        ; The extent and record are zero.
    XOR  A                         ; Zero:
    LD   (BL_SFCB+12),A            ; the extent,
    LD   (BL_SFCB+14),A            ; its high byte,
    LD   (BL_SFCB+32),A            ; the current record.
    LD   DE,BL_SFCB                ; DE is the FCB.
    RET                            ; Done.

;@ROUTINE IN C,DE OUT A CLOBBERS BC,DE,HL,CARRY,ZERO,SIGN,PARITY,HALFCARRY
; Call BDOS function C with DE (OUT_BDOS), keeping IX and IY, which an
; owner descriptor's walk (OW_ROOT) holds while its bytes are appended.

BL_BDOS:                       ; C is the function, DE its argument.
    PUSH IY                        ; Keep IY;
    CALL OUT_BDOS                  ; IX is kept there.
    POP  IY                        ; IY again.
    RET                            ; A is the status.

;@ROUTINE IN HL OUT DE,HL
; DE is the word at HL, low byte first; HL returns past it. A, BC and the
; flags are kept.

WD_GET:                        ; HL addresses a word.
    LD   E,(HL)                    ; Its low byte,
    INC  HL                        ; then
    LD   D,(HL)                    ; its high byte.
    INC  HL                        ; HL is past it.
    RET                            ; DE is the word.

;@ROUTINE IN DE,HL OUT CARRY,ZERO,SIGN,PARITY CLOBBERS HALFCARRY
; Compare HL with DE, unsigned: carry when HL is below DE, zero when they
; are equal, the sign and overflow as HL less DE sets them. HL is kept.

CP_HLDE:                       ; HL and DE are compared.
    OR   A                         ; Carry clear,
    SBC  HL,DE                     ; HL less DE: zero, sign and overflow;
    ADD  HL,DE                     ; HL again, and carry the borrow.
    RET                            ; Done.

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

