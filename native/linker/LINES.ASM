;==========================================================================
;  The line table
;==========================================================================
;
;  The line table (linker §7.7; object format §11), NAME.$LT on the output
;  drive, written during Phase D from the line stream NAME.$LN, unless
;  option N. Publication renames it to NAME.LIN.
;
;  Principal entries:
;    LN_OPEN   open the stream and the table, and write the table's header
;    LN_BLOB   write the entries for a blob as Phase D meets it
;    LN_CLOSE  check the stream's trailer and write the table's
;
;  Line stream: BSIL, version, stamp; then part records (tag 1: part, name
;  length, name) and blob-lines records (tag 2: ordinal, count, entries);
;  then tag $FF and a CRC. Each entry is a control byte (bit 7: a part byte
;  follows; bits 0-6 the offset's delta from the last, or 127 for an
;  absolute offset word), the part if given, the line and the column.
;
;  Line table: BSIT, version, part count, an output name and a library name
;  (both empty here), the part names, then 6-byte entries in address order
;  (address, part, line, column; or address, $FF, ordinal, 0 for a blob's
;  start), then $FF x 6, the entry count, the image's CRC and the table's
;  CRC. Both are version 2.0, whose entries have columns (D47).
;
;  The stream is read once, forward, in step with the directory: Phase D's
;  TEXT passes meet the program's code blobs in directory order, and the
;  stream holds a record for each, in the same order. The part names are
;  copied from the part records, which may come anywhere, in any order.

LN_FD:                         ; The FD that reads NAME.$LN.
    DS   FD_SIZE                   ; Phase E reuses it for NAME.$NM.
LN_TYPE:                       ; The line stream's type.
    DB   "$LN"                     ; Three characters.
LN_TEXT:                       ; Its name as text, for diagnostics.
    DS   13                        ; NAME.$LN and a zero.
LT_FD:                         ; The FD that writes NAME.$LT.
    DS   FD_SIZE                   ; Phase E reuses it for the library's names.
LT_TYPE:                       ; The line table's type until publication.
    DB   "$LT"                     ; Three characters.
LT_TEXT:                       ; Its name as text, for diagnostics.
    DS   13                        ; NAME.$LT and a zero.
LN_ON:                         ; 1 while a line table is being written.
    DB   0                         ; 0 under option N.
LN_TAG:                        ; The tag of the next line-stream record.
    DB   0                         ; 2 for a blob's lines, $FF at the trailer.
LN_CRC:                        ; The line stream's CRC, as read.
    DW   0                         ; Checked against its trailer.
LT_CRC:                        ; The line table's CRC, as written.
    DW   0                         ; Written in its trailer.
IMG_CRC:                       ; The image's CRC, as written by OUT_RAW.
    DW   0                         ; Written in the line table's trailer.
LT_CNT:                        ; The entries written.
    DW   0                         ; Written in the line table's trailer.
LN_POS:                        ; An entry's offset in its blob.
    DW   0                         ; Deltas add to it; 0 at each blob.
LN_PART:                       ; And its part.
    DB   0                         ; Kept until an entry names another.
LN_COL:                        ; And its column.
    DB   0                         ; Read with its line.
LN_MODE:                       ; 0: the line table; 1: the position table.
    DB   0                         ; 1 only during PT_RUN, in Phase C.
PT_BEG:                        ; The position table, made in free memory:
    DW   0                         ; its first byte, above the program table,
PT_PTR:                        ; and the next.
    DW   0                         ; It must stay below the edge lists.
PT_ADDR:                       ; Its address in the image, after COPY.
    DW   0                         ; LINES; 0 without D.
PT_SIZE:                       ; Its bytes.
    DW   0                         ; LINES's size; 0 without D.
PT_LA:                         ; The last entry encoded: its address,
    DW   0                         ; 0 to start;
PT_LP:                         ; its part,
    DB   0                         ; 0;
PT_LL:                         ; and its line.
    DW   0                         ; 0.
PT_A:                          ; The entry being written: its address,
    DW   0                         ; set by LN_BLOB,
PT_P:                          ; its part ($FF for a blob's start),
    DB   0                         ; its
PT_L:                          ; line (a start's ordinal)
    DW   0                         ; and
PT_C:                          ; its column.
    DB   0                         ; Then LT_ENT.
POS_REP EQU  $08F              ; The library's position reporter, TRAPLN.

;@ROUTINE OUT A CLOBBERS CARRY,ZERO,SIGN,PARITY,HALFCARRY
; Read the next byte of the line stream into A, adding it to LN_CRC and
; keeping every other register. L-TRUNCATED if the stream ends.

LN_BYTE:                       ; LN_FD is open.
    PUSH IX                        ; Keep the caller's FD.
    LD   IX,LN_FD                  ; The line stream.
    CALL FIL_GETB                  ; A is the next byte; carry at the end.
    POP  IX                        ; Recover IX.
    JR   C,.SHORT                  ; The stream ended early.
    PUSH HL                        ; Keep HL.
    LD   HL,LN_CRC                 ; The stream's CRC,
    CALL CRC_FOLD                  ; with A added.
    POP  HL                        ; Recover HL.
    RET                            ; A is the byte.
.SHORT:                        ; The stream ended.
    LD   HL,LN_TEXT                ; Name the stream
    LD   (RD_NAME),HL              ; in the diagnostic.
    JP   DG_SHORT                  ; L-TRUNCATED.

;@ROUTINE OUT A,HL CLOBBERS CARRY,ZERO,SIGN,PARITY,HALFCARRY
; Read the next word of the line stream into HL, low byte first.

LN_WORD:                       ; LN_FD is open.
    CALL LN_BYTE                   ; The low byte.
    LD   L,A                       ; Into L.
    CALL LN_BYTE                   ; The high byte.
    LD   H,A                       ; Into H.
    RET                            ; HL is the word.

;@ROUTINE IN A CLOBBERS CARRY,ZERO,SIGN,PARITY,HALFCARRY
; Write A to the line table, adding it to LT_CRC. Keeps A, BC, DE and HL;
; L-IO if the disk is full.

LT_BYTE:                       ; A is a byte of the table.
    PUSH HL                        ; Keep HL.
    LD   HL,LT_CRC                 ; The table's CRC,
    CALL CRC_FOLD                  ; with A added.
    POP  HL                        ; Recover HL.
    PUSH AF                        ; Keep the byte.
    PUSH IX                        ; Keep the caller's FD.
    LD   IX,LT_FD                  ; The line table.
    CALL FIL_PUTB                  ; Write A; carry if the disk is full.
    POP  IX                        ; Recover IX.
    JR   C,.FULL                   ; The disk is full.
    POP  AF                        ; A is the byte.
    RET                            ; Written.
.FULL:                         ; The byte is on the stack.
    POP  AF                        ; Drop it.
    LD   HL,LT_TEXT                ; Name the table
    LD   (RD_NAME),HL              ; in the diagnostic.
    JP   DG_DISK                   ; L-IO.

;@ROUTINE IN HL CLOBBERS A,CARRY,ZERO,SIGN,PARITY,HALFCARRY
; Write HL to the line table, low byte first.

LT_WORD:                       ; HL is the word.
    LD   A,L                       ; The low byte,
    CALL LT_BYTE                   ; written.
    LD   A,H                       ; The high byte,
    JR   LT_BYTE                   ; written; return.

;@ROUTINE CLOBBERS A,BC,DE,HL,IX,CARRY,ZERO,SIGN,PARITY,HALFCARRY
; Open the line stream and the line table, and write the table's header:
; the part names, from the stream's part records, one pass for each part,
; since they may come in any order and among the blob-lines records. Leave
; LN_TAG holding the tag of the first blob-lines record, or $FF. Nothing
; under option N.

LN_OPEN:                       ; Called by Phase D before the first section.
    LD   A,(OP_FLAGS)              ; Option N:
    AND  OF_N                      ; no line table.
    RET  NZ                        ; LN_ON stays 0.
    LD   A,1                       ; A line table is written,
    LD   (LN_ON),A                 ; so LN_BLOB and LN_CLOSE act.
    LD   IX,LN_FD                  ; NAME.$LN,
    LD   A,(DIR_FD+FD_FCB)         ; on the directory's drive.
    LD   HL,CMD_NAME               ; NAME,
    LD   DE,LN_TYPE                ; type $LN,
    LD   BC,LN_TEXT                ; named in LN_TEXT.
    CALL FIL_NAME                  ; Set up the FCB.
    CALL FIL_NEED                  ; Open it, or L-MISSING.
    CALL .HEAD                     ; Check the stream's header and stamp.
    LD   BC,0                      ; First pass: count the parts in BC.
.COUNT:                        ; LN_FD is at a record's tag.
    CALL LN_BYTE                   ; The tag.
    CP   $FF                       ; The trailer?
    JR   Z,.COUNTED                ; Every record is seen.
    CP   1                         ; A part record?
    JR   Z,.ONEPART                ; Count it.
    CP   2                         ; A blob-lines record?
    JP   NZ,.BAD                   ; Any other tag is malformed.
    PUSH BC                        ; Keep the count.
    CALL .SKIPREC                  ; A blob-lines record.
    POP  BC                        ; Recover the count.
    JR   .COUNT                    ; The next record.
.ONEPART:                      ; A part record.
    INC  BC                        ; One more part.
    CALL LN_BYTE                   ; The part's number.
    CALL LN_BYTE                   ; Its name's length.
    LD   D,A                       ; D counts the name's characters.
    CALL LN_SKIP                   ; Skip the name.
    JR   .COUNT                    ; The next record.
.COUNTED:                      ; BC is the number of parts.
    PUSH BC                        ; Keep it for the header.
    LD   A,(LN_MODE)               ; The position table's
    OR   A                         ; header, under PT_RUN,
    JR   NZ,.PTHEAD                ; differs.
    LD   IX,LT_FD                  ; The line table, NAME.$LT on the output drive:
    CALL OUT_PICK                  ; HL is the output's name, A its drive.
    LD   DE,LT_TYPE                ; Type $LT,
    LD   BC,LT_TEXT                ; named in LT_TEXT.
    CALL FIL_NAME                  ; Set up the FCB.
    XOR  A                         ; Pad the last record with zeros.
    CALL FIL_MAKE                  ; Create it; carry if the directory is full.
    JP   C,DG_DISK                 ; L-IO.
    LD   A,1                       ; NAME.$LT exists now,
    LD   (LT_MADE),A               ; so a failure deletes it.
    LD   HL,$FFFF                  ; The table's CRC
    LD   (LT_CRC),HL               ; starts.
    LD   HL,0                      ; No entries
    LD   (LT_CNT),HL               ; yet.
    LD   HL,.MAGIC                 ; The table's magic,
    LD   B,4                       ; four bytes.
.PUTMAGIC:                     ; HL walks the magic.
    LD   A,(HL)                    ; A magic byte,
    CALL LT_BYTE                   ; written.
    INC  HL                        ; The next.
    DJNZ .PUTMAGIC                 ; Until all four are written.
    LD   A,2                       ; Version 2.0:
    CALL LT_BYTE                   ; major 2,
    XOR  A                         ; minor
    CALL LT_BYTE                   ; 0.
    POP  BC                        ; BC is the part count.
    LD   A,C                       ; The part count,
    CALL LT_BYTE                   ; one byte.
    XOR  A                         ; No output name, no library name:
    CALL LT_BYTE                   ; two empty
    CALL LT_BYTE                   ; names.
    JR   .COUNTB                   ; Then the parts.
.PTHEAD:                       ; The position table's header:
    CALL PT_REP                    ; the reporter's
    LD   DE,E_ADDR                 ; address
    ADD  HL,DE                     ; (from
    LD   A,(HL)                    ; its
    INC  HL                        ; entry),
    LD   H,(HL)                    ; then
    LD   L,A                       ; the
    CALL PT_WORD                   ; parts'
    POP  BC                        ; count,
    LD   A,C                       ; one
    CALL PT_BYTE                   ; byte.
    XOR  A                         ; (A zero.)
.COUNTB:                       ; A is zero.
    LD   B,C                       ; B is the count,
    LD   C,A                       ; C the part sought, from 0.
.PARTS:                        ; A pass for each part, in part order.
    LD   A,C                       ; Every part
    CP   B                         ; written?
    JR   Z,.FIRST                  ; Then the blob-lines records.
    PUSH BC                        ; Keep the count and the part.
    CALL .HEAD                     ; From the start again.
.FIND:                         ; Find part C's record.
    CALL LN_BYTE                   ; A record's tag.
    CP   1                         ; A part record?
    JR   Z,.PART                   ; Is it the one?
    INC  A                         ; The trailer, $FF:
    JR   Z,.BAD                    ; the part is missing or repeated.
    CALL .SKIPREC                  ; A blob-lines record.
    JR   .FIND                     ; The next.
.PART:                         ; A part record.
    CALL LN_BYTE                   ; The part's number,
    LD   E,A                       ; in E.
    CALL LN_BYTE                   ; The name's length,
    LD   D,A                       ; counted in D.
    POP  BC                        ; C is the part sought,
    PUSH BC                        ; still kept.
    LD   A,E                       ; Is this
    CP   C                         ; its record?
    JR   Z,.COPY                   ; Copy its name.
    CALL LN_SKIP                   ; Skip the name.
    JR   .FIND                     ; The next record.
.COPY:                         ; D is the name's length.
    LD   A,(LN_MODE)               ; The length, before
    OR   A                         ; the name in
    LD   A,D                       ; the line table,
    CALL Z,LT_BYTE                 ; written.
.NAME:                         ; Copy the name.
    LD   A,D                       ; Any left?
    OR   A                         ; Zero when done.
    JR   Z,.COPIED                 ; The part is written.
    CALL LN_BYTE                   ; A character,
    CALL LN_PUT                    ; copied.
    DEC  D                         ; One fewer.
    JR   .NAME                     ; Go on.
.COPIED:                       ; The name is copied:
    LD   A,(LN_MODE)               ; in the position table
    OR   A                         ; a zero
    CALL NZ,PT_ZERO                ; ends it.
    POP  BC                        ; The count and the part,
    INC  C                         ; the next part.
    JR   .PARTS                    ; Find it.
.FIRST:                        ; Every part is written.
    CALL .HEAD                     ; From the start again,
    JP   LN_NEXT                   ; to the first blob-lines record; return.

;@ROUTINE CLOBBERS A,B,DE,HL,IX,CARRY,ZERO,SIGN,PARITY,HALFCARRY
; Go to the stream's start and check its header and stamp, starting
; LN_CRC. L-FORMAT or L-STAMP otherwise.

.HEAD:                         ; Called before each pass.
    LD   IX,LN_FD                  ; The stream,
    XOR  A                         ; at offset
    LD   HL,0                      ; 0.
    CALL FIL_SEEK                  ; Go there.
    JP   C,DG_SHORT                ; An empty file.
    LD   HL,$FFFF                  ; The stream's CRC
    LD   (LN_CRC),HL               ; starts.
    LD   HL,.SRCMAGIC              ; Compare the magic
    LD   B,4                       ; over four bytes.
.GETMAGIC:                     ; HL walks the magic.
    CALL LN_BYTE                   ; The next byte.
    CP   (HL)                      ; Does it match?
    JR   NZ,.BAD                   ; Not a line stream.
    INC  HL                        ; The next.
    DJNZ .GETMAGIC                 ; Until all four match.
    CALL LN_BYTE                   ; The major version
    CP   2                         ; must be 2.
    JR   NZ,.BAD                   ; Unknown.
    CALL LN_BYTE                   ; The minor version
    OR   A                         ; must be 0.
    JR   NZ,.BAD                   ; Higher.
    CALL LN_WORD                   ; The stamp
    JP   RD_STAMP                  ; must be the directory's; return.
.BAD:                          ; A malformed stream.
    LD   HL,LN_TEXT                ; Name the stream
    LD   (RD_NAME),HL              ; in the diagnostic.
    LD   HL,200                    ; L-FORMAT.
    JP   DG_FILE                   ; Report it.
.MAGIC:                        ; The line table's magic.
    DB   "BSIT"                    ; Basie line table.
.SRCMAGIC:                     ; The line stream's magic.
    DB   "BSIL"                    ; Basie line stream.

;@ROUTINE CLOBBERS A,B,DE,HL,CARRY,ZERO,SIGN,PARITY,HALFCARRY
; Skip the rest of a blob-lines record, after its tag.

.SKIPREC:                      ; LN_FD is at the record's ordinal.
    CALL LN_WORD                   ; The ordinal.
    CALL LN_WORD                   ; The entry count.
.NEXT:                         ; HL entries remain.
    LD   A,H                       ; Any left?
    OR   L                         ; Zero when done.
    RET  Z                         ; The record is skipped.
    PUSH HL                        ; Keep the count.
    CALL LN_ENTRY                  ; Read an entry.
    POP  HL                        ; Recover the count.
    DEC  HL                        ; One fewer.
    JR   .NEXT                     ; Go on.

;@ROUTINE OUT A,HL CLOBBERS B,DE,CARRY,ZERO,SIGN,PARITY,HALFCARRY
; Read one entry of a blob-lines record into LN_POS, LN_PART and LN_COL,
; returning HL = its line.

LN_ENTRY:                      ; LN_FD is at an entry's control byte.
    CALL LN_BYTE                   ; Control.
    LD   B,A                       ; Keep it for bit 7.
    AND  $7F                       ; The delta,
    CP   127                       ; or 127 for an absolute offset.
    JR   NZ,.DELTA                 ; A delta.
    CALL LN_WORD                   ; An absolute offset.
    JR   .OFF                      ; Use it.
.DELTA:                        ; A is the delta.
    LD   L,A                       ; HL is the delta,
    LD   H,0                       ; zero-extended.
    LD   DE,(LN_POS)               ; Added to
    ADD  HL,DE                     ; the last offset.
.OFF:                          ; HL is the entry's offset.
    LD   (LN_POS),HL               ; Keep it.
    BIT  7,B                       ; Does a part byte follow?
    JR   Z,.SRC                    ; No: the part is unchanged.
    CALL LN_BYTE                   ; The part.
    LD   (LN_PART),A               ; Keep it.
.SRC:                          ; The line follows,
    CALL LN_WORD                   ; HL,
    PUSH HL                        ; kept,
    CALL LN_BYTE                   ; then the column,
    LD   (LN_COL),A                ; kept.
    POP  HL                        ; HL is the line.
    RET                            ; Done.

;@ROUTINE IN A,DE CLOBBERS A,BC,DE,HL,CARRY,ZERO,SIGN,PARITY,HALFCARRY
; Write the line-table entries for the blob being emitted, at address DE:
; one per statement for a program code blob whose record begins at offset
; 0, else a start entry ($FF, the ordinal) and then any statements. Called
; in every TEXT pass for each program code blob, emitted or not, so the
; line stream stays in step with the directory; A = 1 when the blob is
; emitted.

LN_BLOB:                       ; RD_PREV, WK_OWN and WK_KIND are the blob's.
    LD   (.EMITTED),A              ; Keep whether it is emitted,
    LD   (.ADDR),DE                ; and its address.
    LD   A,(LN_ON)                 ; Is a line table being written?
    OR   A                         ; Not under option N.
    RET  Z                         ; Nothing to do.
    LD   A,(WK_OWN)                ; A program code blob has a record.
    OR   A                         ; The library's?
    JR   Z,.START                  ; A start entry only.
    LD   A,(WK_KIND)               ; Code?
    CP   K_CODE                    ; Only code has a record.
    JR   NZ,.START                 ; A start entry only.
    CALL .RECORD                   ; HL = its entry count.
    LD   (.LEFT),HL                ; Entries to read.
    LD   HL,0                      ; Offsets start
    LD   (LN_POS),HL               ; from 0.
    LD   A,(.EMITTED)              ; Emitted?
    OR   A                         ; Zero if not.
    JR   Z,.SKIPALL                ; A dead blob: read past its entries.
    LD   HL,(.LEFT)                ; Any entries?
    LD   A,H                       ; Test the count
    OR   L                         ; for zero.
    JR   Z,.ONLY                   ; None: a start entry only.
    CALL LN_ENTRY                  ; The first entry: at offset 0?
    PUSH HL                        ; Keep its source.
    LD   HL,(LN_POS)               ; Its offset.
    LD   A,H                       ; Is it
    OR   L                         ; zero?
    JR   Z,.ATZERO                 ; The entry starts the blob itself.
    CALL .STARTER                  ; Otherwise a start entry first.
.ATZERO:                       ; The first entry's source is on the stack.
    POP  HL                        ; HL is its source.
    CALL .ENTRY                    ; Write it.
.MORE:                         ; .LEFT counts the entries left, this one included.
    LD   HL,(.LEFT)                ; One fewer
    DEC  HL                        ; to
    LD   (.LEFT),HL                ; read.
    LD   A,H                       ; Any left?
    OR   L                         ; Zero when done.
    JR   Z,.DONE                   ; The record is read.
    CALL LN_ENTRY                  ; The next entry.
    CALL .ENTRY                    ; Write it.
    JR   .MORE                     ; Go on.
.DONE:                         ; Every entry is written.
    JR   LN_NEXT                   ; Read the next record's tag; return.
.SKIPALL:                      ; A dead blob's entries.
    LD   HL,(.LEFT)                ; HL counts them.
.SKIP:                         ; HL entries remain.
    LD   A,H                       ; Any left?
    OR   L                         ; Zero when done.
    JR   Z,LN_NEXT                 ; Read the next record's tag; return.
    PUSH HL                        ; Keep the count.
    CALL LN_ENTRY                  ; Read past an entry.
    POP  HL                        ; Recover the count.
    DEC  HL                        ; One fewer.
    JR   .SKIP                     ; Go on.
.ONLY:                         ; An emitted code blob with no statements.
    CALL .STARTER                  ; A start entry.
    JR   LN_NEXT                   ; Read the next record's tag; return.
.START:                        ; Any other blob: no record.
    LD   A,(.EMITTED)              ; Any other emitted blob: a start entry.
    OR   A                         ; Emitted?
    RET  Z                         ; No: nothing.

;@ROUTINE CLOBBERS A,BC,DE,HL,CARRY,ZERO,SIGN,PARITY,HALFCARRY
; Write a start entry: the blob's address, $FF, its ordinal, column 0.

.STARTER:                      ; .ADDR and RD_PREV are the blob's.
    LD   HL,(.ADDR)                ; The address,
    LD   (PT_A),HL                 ; kept;
    LD   A,$FF                     ; $FF marks a start entry,
    LD   (PT_P),A                  ; in place of the part;
    LD   HL,(RD_PREV)              ; the blob's ordinal,
    LD   (PT_L),HL                 ; in place of the line,
    XOR  A                         ; and no
    JR   .COLUMN                   ; column.

;@ROUTINE IN HL CLOBBERS A,BC,DE,HL,CARRY,ZERO,SIGN,PARITY,HALFCARRY
; Write an entry: address = the blob's + LN_POS, part, line HL, column.

.ENTRY:                        ; HL is the source offset.
    LD   (PT_L),HL                 ; The line, kept;
    LD   HL,(.ADDR)                ; the blob's address
    LD   DE,(LN_POS)               ; plus the entry's offset
    ADD  HL,DE                     ; is the statement's address,
    LD   (PT_A),HL                 ; kept;
    LD   A,(LN_PART)               ; the part,
    LD   (PT_P),A                  ; kept,
    LD   A,(LN_COL)                ; then the column.
.COLUMN:                       ; A is the column.
    LD   (PT_C),A                  ; Kept:
    JP   LT_ENT                    ; the entry written; return.

.EMITTED:                      ; Nonzero when the blob is emitted.
    DB   0                         ; Set by LN_BLOB.
.ADDR:                         ; The blob's address.
    DW   0                         ; Set by LN_BLOB.
.LEFT:                         ; The entries left to read.
    DW   0                         ; Counted down by LN_BLOB.

;@ROUTINE OUT A,HL CLOBBERS DE,CARRY,ZERO,SIGN,PARITY,HALFCARRY
; The next blob-lines record must be the current blob's: return HL = its
; entry count. L-TRUNCATED otherwise: the stream is out of step.

.RECORD:                       ; LN_TAG is the next record's tag.
    LD   A,(LN_TAG)                ; A blob-lines record?
    CP   2                         ; Tag 2.
    JR   NZ,LN_FAIL                ; Out of step.
    CALL LN_WORD                   ; Its ordinal
    LD   DE,(RD_PREV)              ; must be the blob's.
    OR   A                         ; Clear carry for the subtraction.
    SBC  HL,DE                     ; Equal?
    JR   NZ,LN_FAIL                ; Out of step.
    JP   LN_WORD                   ; HL is its entry count; return.

;@ROUTINE NORETURN
; The line stream is out of step with the directory, or damaged: report
; L-TRUNCATED for it and end the link.

LN_FAIL:                       ; Reached from LN_BLOB and LN_CLOSE.
    LD   HL,LN_TEXT                ; Name the stream
    LD   (RD_NAME),HL              ; in the diagnostic.
    LD   HL,214                    ; L-TRUNCATED.
    JP   DG_FILE                   ; Report it.

;@ROUTINE CLOBBERS A,D,CARRY,ZERO,SIGN,PARITY,HALFCARRY
; Read the next record's tag into LN_TAG, skipping part records.

LN_NEXT:                       ; LN_FD is at a record's tag.
    CALL LN_BYTE                   ; The tag.
    CP   1                         ; A part record?
    JR   NZ,.SET                   ; No: keep the tag.
    CALL LN_BYTE                   ; Its part number,
    CALL LN_BYTE                   ; and its name's length,
    LD   D,A                       ; counted in D.
    CALL LN_SKIP                   ; Skip the name.
    JR   LN_NEXT                   ; The next record.
.SET:                          ; A is a blob-lines tag or $FF.
    LD   (LN_TAG),A                ; Kept for LN_BLOB or LN_CLOSE.
    RET                            ; Done.

;@ROUTINE IN D CLOBBERS A,D,CARRY,ZERO,SIGN,PARITY,HALFCARRY
; Skip D bytes of the line stream: a part record's name.

LN_SKIP:                       ; D is the count.
    LD   A,D                       ; Any left?
    OR   A                         ; Zero when done.
    RET  Z                         ; Skipped.
    CALL LN_BYTE                   ; Skip a byte.
    DEC  D                         ; One fewer.
    JR   LN_SKIP                   ; Go on.

;@ROUTINE CLOBBERS A,B,DE,HL,IX,CARRY,ZERO,SIGN,PARITY,HALFCARRY
; Finish the line table: the stream must be at its trailer, whose CRC is
; checked; then write the table's trailer, with the image's CRC, and close
; it. Nothing under option N.

LN_CLOSE:                      ; Called at the end of Phase D.
    LD   A,(LN_ON)                 ; Is a line table being written?
    OR   A                         ; Not under option N.
    RET  Z                         ; Nothing to do.
    LD   A,(LN_TAG)                ; The stream must be at its trailer:
    CP   $FF                       ; every record read.
    JR   NZ,LN_FAIL                ; Records are left over.
    LD   HL,(LN_CRC)               ; The stored CRC, read without adding it,
    PUSH HL                        ; against the CRC computed.
    LD   IX,LN_FD                  ; The stream.
    CALL RD_RAW                    ; The stored CRC's low byte,
    LD   E,A                       ; in E,
    CALL RD_RAW                    ; and its high byte,
    LD   D,A                       ; in D.
    POP  HL                        ; HL is the computed CRC.
    OR   A                         ; Clear carry for the subtraction.
    SBC  HL,DE                     ; Equal?
    JR   NZ,LN_FAIL                ; The stream is damaged.
    LD   A,(LN_MODE)               ; The position table
    OR   A                         ; ends with
    JR   Z,.LT                     ; a long entry
    CALL PT_ZERO                   ; at $FFFF,
    DEC  A                         ; part $FF,
    CALL PT_BYTE                   ; line 0,
    CALL PT_BYTE                   ; column 0:
    CALL PT_BYTE                   ; 0, $FF, $FF, $FF,
    INC  A                         ; 0, 0
    CALL PT_BYTE                   ; and
    CALL PT_BYTE                   ; 0.
    JP   PT_BYTE                   ; Complete; return.
.LT:                           ; The line table's
    LD   B,6                       ; trailer: $FF x 6,
.MARK:                         ; B counts them.
    LD   A,$FF                     ; One $FF,
    CALL LT_BYTE                   ; written.
    DJNZ .MARK                     ; Until six are written.
    LD   HL,(LT_CNT)               ; The entry count,
    CALL LT_WORD                   ; written.
    LD   HL,(IMG_CRC)              ; The image's CRC,
    CALL LT_WORD                   ; written.
    LD   HL,(LT_CRC)               ; The table's own CRC,
    CALL LT_WORD                   ; written last.
    LD   IX,LT_FD                  ; Close the table.
    CALL FIL_SHUT                  ; Carry on failure.
    RET  NC                        ; Closed.
    LD   HL,LT_TEXT                ; Name the table
    LD   (RD_NAME),HL              ; in the diagnostic.
    JP   DG_DISK                   ; L-IO.

; ---- the position table (option D, object format §11.1) ---------------------

;@ROUTINE IN A CLOBBERS CARRY,ZERO,SIGN,PARITY,HALFCARRY
; Write header byte A: to the line table, or under PT_RUN to the position
; table. Keeps every register.

LN_PUT:                        ; A is the byte.
    PUSH AF                        ; (kept)
    LD   A,(LN_MODE)               ; Which
    OR   A                         ; table?
    JR   NZ,.PT                    ; The position table.
    POP  AF                        ; The line
    JP   LT_BYTE                   ; table's.
.PT:                           ; The position table's.
    POP  AF                        ; The byte;
                                   ; fall into PT_BYTE.

;@ROUTINE IN A CLOBBERS CARRY,ZERO,SIGN,PARITY,HALFCARRY
; Append A to the position table in free memory. Keeps A, BC, DE and HL;
; L-CAP-TABLES if it reaches the edge lists.

PT_BYTE:                       ; A is a byte of the table.
    PUSH HL                        ; Keep HL
    PUSH DE                        ; and DE.
    LD   HL,(PT_PTR)               ; The next place
    LD   (HL),A                    ; takes it,
    INC  HL                        ; and the one
    LD   (PT_PTR),HL               ; after is next;
    LD   DE,(EDGE_PTR)             ; it must stay
    PUSH AF                        ; (the byte)
    OR   A                         ; below the
    SBC  HL,DE                     ; edge lists.
    JP   NC,DG_CAP                 ; L-CAP-TABLES.
    POP  AF                        ; The byte,
    POP  DE                        ; DE
    POP  HL                        ; and HL again.
    RET                            ; Appended.

;@ROUTINE OUT A CLOBBERS CARRY,ZERO,SIGN,PARITY,HALFCARRY
; Append a zero byte to the position table; A returns zero.

PT_ZERO:                       ; A zero:
    XOR  A                         ; it,
    JR   PT_BYTE                   ; appended; return.

;@ROUTINE IN HL CLOBBERS A,CARRY,ZERO,SIGN,PARITY,HALFCARRY
; Append HL to the position table, low byte first.

PT_WORD:                       ; HL is the word.
    LD   A,L                       ; The low byte,
    CALL PT_BYTE                   ; appended;
    LD   A,H                       ; the high,
    JR   PT_BYTE                   ; appended; return.

;@ROUTINE OUT CARRY,HL CLOBBERS A,DE,ZERO,SIGN,PARITY,HALFCARRY
; Return in HL the entry of the library's position reporter, POS_REP:
; carry if the library has no code blob there.

PT_REP:                        ; Phase A has read the library.
    LD   HL,(LIB_CNT)              ; Its entries
    LD   DE,POS_REP+1              ; must reach
    OR   A                         ; past the
    SBC  HL,DE                     ; reporter's:
    RET  C                         ; not so far.
    LD   HL,POS_REP                ; Its
    CALL TAB_AT                    ; entry,
    LD   A,(HL)                    ; defined, no alias,
    AND  EF_DEF+EF_ALIAS+7         ; and code
    CP   EF_DEF                    ; (kind 0)?
    SCF                            ; Carry
    RET  NZ                        ; if not.
    OR   A                         ; Clear carry:
    RET                            ; it is.

;@ROUTINE CLOBBERS A,BC,DE,HL,CARRY,ZERO,SIGN,PARITY,HALFCARRY
; Write the entry at PT_A, PT_P, PT_L and PT_C: six bytes to the line
; table, counted (LT_CNT), or under PT_RUN encoded in the position table
; from the last one encoded: three bytes, the address's rise, the line's
; change and the column, when the part is the last's, the rise 1 to 255
; and the change -128 to 127; else 0, the address, the part, the line and
; the column.

LT_ENT:                        ; The entry is in PT_A..PT_C.
    LD   A,(LN_MODE)               ; The position table?
    OR   A                         ; Under PT_RUN.
    JR   NZ,.PT                    ; Encode it.
    LD   HL,(PT_A)                 ; The address,
    CALL LT_WORD                   ; written;
    LD   A,(PT_P)                  ; the part,
    CALL LT_BYTE                   ; written;
    LD   HL,(PT_L)                 ; the line,
    CALL LT_WORD                   ; written;
    LD   A,(PT_C)                  ; the column,
    CALL LT_BYTE                   ; written.
    LD   HL,(LT_CNT)               ; One more
    INC  HL                        ; entry
    LD   (LT_CNT),HL               ; in the table.
    RET                            ; Done.
.PT:                           ; Encode it.
    LD   A,(PT_P)                  ; The part
    LD   HL,PT_LP                  ; must be
    CP   (HL)                      ; the last one's,
    JR   NZ,.LONG                  ; for a short entry;
    LD   HL,(PT_A)                 ; the address's
    LD   DE,(PT_LA)                ; rise
    OR   A                         ; from the
    SBC  HL,DE                     ; last,
    LD   A,H                       ; below
    OR   A                         ; 256,
    JR   NZ,.LONG                  ; and
    LD   A,L                       ; above
    OR   A                         ; 0;
    JR   Z,.LONG                   ; the
    LD   C,A                       ; rise, C;
    LD   HL,(PT_L)                 ; the line's
    LD   DE,(PT_LL)                ; change
    OR   A                         ; from
    SBC  HL,DE                     ; the last,
    LD   A,L                       ; a signed
    RLA                            ; byte: H
    SBC  A,A                       ; is L's
    CP   H                         ; sign
    JR   NZ,.LONG                  ; extended.
    LD   A,C                       ; The rise,
    CALL PT_BYTE                   ; appended;
    LD   A,L                       ; the change,
    CALL PT_BYTE                   ; appended;
    JR   .COL                      ; then the column.
.LONG:                         ; A long entry:
    CALL PT_ZERO                   ; 0,
    LD   HL,(PT_A)                 ; the address,
    CALL PT_WORD                   ; appended,
    LD   A,(PT_P)                  ; the part,
    CALL PT_BYTE                   ; appended,
    LD   HL,(PT_L)                 ; the line,
    CALL PT_WORD                   ; appended.
.COL:                          ; The column,
    LD   A,(PT_C)                  ; appended
    CALL PT_BYTE                   ; last.
    LD   HL,(PT_A)                 ; This entry
    LD   (PT_LA),HL                ; is the
    LD   A,(PT_P)                  ; last
    LD   (PT_LP),A                 ; encoded:
    LD   HL,(PT_L)                 ; its address,
    LD   (PT_LL),HL                ; part and line.
    RET                            ; Done.

;@ROUTINE CLOBBERS A,BC,DE,HL,IX,CARRY,ZERO,SIGN,PARITY,HALFCARRY
; Option D, in Phase C once START, TEXT and DATA are placed: make the
; position table in free memory, above the program table (PT_BEG), from
; the line stream, as Phase D will make the line table: its header, the
; reporter's address and the parts' names, then an entry for each line
; table entry in address order, then the end. It follows the image (its
; address PT_ADDR, its size PT_SIZE: LINES). Nothing without D.

PT_RUN:                        ; IMG_END is the image's end.
    LD   A,(OP_SEEN)               ; Option D?
    AND  OX_D                      ; If not,
    RET  Z                         ; no table.
    LD   HL,(PRG_END)              ; The table is made
    LD   (PT_BEG),HL               ; above the
    LD   (PT_PTR),HL               ; program table,
    LD   HL,(IMG_END)              ; for the image's
    LD   (PT_ADDR),HL              ; end.
    LD   A,1                       ; The position table
    LD   (LN_MODE),A               ; is written:
    CALL LN_OPEN                   ; its header,
    LD   A,S_START                 ; START's
    CALL .PASS                     ; entries,
    LD   A,S_TEXT                  ; TEXT's
    CALL .PASS                     ; and
    LD   A,S_DATA                  ; DATA's,
    CALL .PASS                     ; as Phase D meets them,
    CALL LN_CLOSE                  ; and its end.
    XOR  A                         ; The line table
    LD   (LN_MODE),A               ; again, for
    LD   (LN_ON),A                 ; Phase D.
    LD   HL,(PT_PTR)               ; Its size:
    LD   DE,(PT_BEG)               ; the bytes
    OR   A                         ; made.
    SBC  HL,DE                     ; (HL)
    LD   (PT_SIZE),HL              ; Kept.
    RET                            ; Done.
.PASS:                         ; A is the section.
    LD   HL,PT_BLOB                ; Each blob
    JP   WK_PASS                   ; met; return.

;@ROUTINE CLOBBERS A,BC,DE,HL,IX,CARRY,ZERO,SIGN,PARITY,HALFCARRY
; PT_RUN's callback for each blob of a pass: as Phase D's (PD_BLOB), its
; entries if it is in the pass, at its address, else a program code
; blob's line record read past in TEXT's class-0 pass; then its
; references skipped.

PT_BLOB:                       ; A walk's callback.
    CALL WK_MATCH                  ; Z if the blob is in the pass.
    JR   Z,.SEL                    ; Its entries.
    LD   A,(WK_SEC)                ; Not in the pass; a program code
    CP   S_TEXT                    ; blob's line record is read past
    JP   NZ,REF_SKIP               ; in TEXT's class-0 pass.
    LD   A,(WK_CLASS)              ; Class 0?
    OR   A                         ; If not,
    JP   NZ,REF_SKIP               ; nothing.
    LD   A,(WK_OWN)                ; The program's?
    OR   A                         ; If not,
    JP   Z,REF_SKIP                ; nothing.
    LD   A,(WK_KIND)               ; Code?
    CP   K_CODE                    ; If not,
    JP   NZ,REF_SKIP               ; nothing.
    XOR  A                         ; Not emitted:
    CALL LN_BLOB                   ; its record read past.
    JP   REF_SKIP                  ; Its references skipped; return.
.SEL:                          ; In the pass:
    LD   HL,(WK_ENTRY)             ; its
    LD   DE,E_ADDR                 ; address,
    ADD  HL,DE                     ; DE,
    LD   E,(HL)                    ; from
    INC  HL                        ; its
    LD   D,(HL)                    ; entry;
    LD   A,1                       ; emitted:
    CALL LN_BLOB                   ; its entries,
    JP   REF_SKIP                  ; its references skipped; return.
