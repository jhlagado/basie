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
;  absolute offset word), the part if given, and the source offset.
;
;  Line table: BSIT, version, part count, an output name and a library name
;  (both empty here), the part names, then 5-byte entries in address order
;  (address, part, source; or address, $FF, ordinal for a blob's start),
;  then $FF x 5, the entry count, the image's CRC and the table's CRC.
;
;  The stream is read once, forward, in step with the directory: Phase D's
;  TEXT passes meet the program's code blobs in directory order, and the
;  stream holds a record for each, in the same order. The part names are
;  copied from the part records, which must all come first, in part order.

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
; the part names, from the stream's part records. Leave LN_TAG holding the
; tag of the first blob-lines record, or $FF. Nothing under option N.

LN_OPEN:                       ; Called by Phase D before the first section.
    LD   A,(OP_FLAGS)              ; Option N:
    AND  OF_N                      ; no line table.
    RET  NZ                        ; LN_ON stays 0.
    LD   A,1                       ; A line table is written,
    LD   (LN_ON),A                 ; so LN_BLOB and LN_CLOSE act.
    LD   IX,LN_FD                  ; NAME.$LN,
    LD   A,(DIR_FD+FD_FCB)         ; on the directory's drive.
    LD   HL,CMD_NAME               ; NAME,
    LD   DE,LN_TYPE                ; type $LN.
    CALL FIL_INIT                  ; Set up the FCB.
    LD   HL,CMD_NAME               ; Its name as text,
    LD   DE,LN_TEXT                ; into LN_TEXT,
    LD   BC,LN_TYPE                ; with its type.
    CALL FIL_TEXT                  ; NAME.$LN.
    CALL FIL_OPEN                  ; Open it; carry if it doesn't exist.
    LD   HL,LN_TEXT                ; Name it
    LD   (RD_NAME),HL              ; in the diagnostic.
    LD   HL,225                    ; L-MISSING.
    JP   C,DG_FILE                 ; Report it.
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
.SKIPNAME:                     ; Skip the name.
    LD   A,D                       ; Any left?
    OR   A                         ; Zero when done.
    JR   Z,.COUNT                  ; The next record.
    CALL LN_BYTE                   ; Skip a character.
    DEC  D                         ; One fewer.
    JR   .SKIPNAME                 ; Go on.
.COUNTED:                      ; BC is the number of parts.
    PUSH BC                        ; Keep it for the header.
    LD   IX,LT_FD                  ; The line table, NAME.$LT on the output drive:
    CALL OUT_PICK                  ; HL is the output's name, A its drive.
    LD   DE,LT_TYPE                ; Type $LT.
    CALL FIL_INIT                  ; Set up the FCB.
    CALL OUT_PICK                  ; HL is the name again.
    LD   DE,LT_TEXT                ; Its name as text,
    LD   BC,LT_TYPE                ; with its type,
    CALL FIL_TEXT                  ; into LT_TEXT.
    LD   HL,LT_TEXT                ; The file being written, for diagnostics;
    LD   (RD_NAME),HL              ; Phase D's reads then name it too.
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
    LD   A,1                       ; Version 1.0:
    CALL LT_BYTE                   ; major 1,
    XOR  A                         ; minor
    CALL LT_BYTE                   ; 0.
    POP  BC                        ; BC is the part count.
    LD   A,C                       ; The part count,
    CALL LT_BYTE                   ; one byte.
    XOR  A                         ; No output name, no library name:
    CALL LT_BYTE                   ; two empty
    CALL LT_BYTE                   ; names.
    CALL .HEAD                     ; Second pass: from the start again,
.NAMES:                        ; copying the part names.
    CALL LN_BYTE                   ; A record's tag.
    CP   1                         ; A part record?
    JR   NZ,.FIRST                 ; The parts are done.
    CALL LN_BYTE                   ; The part's number, taken as in order.
    CALL LN_BYTE                   ; The name's length,
    LD   D,A                       ; counted in D,
    CALL LT_BYTE                   ; and written.
.NAME:                         ; Copy the name.
    LD   A,D                       ; Any left?
    OR   A                         ; Zero when done.
    JR   Z,.NAMES                  ; The next record.
    CALL LN_BYTE                   ; A character,
    CALL LT_BYTE                   ; copied.
    DEC  D                         ; One fewer.
    JR   .NAME                     ; Go on.
.FIRST:                        ; A is the first other record's tag.
    LD   (LN_TAG),A                ; LN_BLOB reads its record.
    RET                            ; The header is written.

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
    CP   1                         ; must be 1.
    JR   NZ,.BAD                   ; Unknown.
    CALL LN_BYTE                   ; The minor version
    OR   A                         ; must be 0.
    JR   NZ,.BAD                   ; Higher.
    CALL LN_WORD                   ; The stamp
    LD   DE,(DIR_HEAD+6)           ; must be the directory's.
    OR   A                         ; Clear carry for the subtraction.
    SBC  HL,DE                     ; Equal?
    RET  Z                         ; The stream belongs to the directory.
    LD   HL,202                    ; L-STAMP.
    JP   DG_PLAIN                  ; Report it.
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
; Read one entry of a blob-lines record into LN_POS and LN_PART, returning
; HL = its source offset.

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
.SRC:                          ; The source offset follows.
    JP   LN_WORD                   ; HL is it; return.

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

;@ROUTINE CLOBBERS A,DE,HL,CARRY,ZERO,SIGN,PARITY,HALFCARRY
; Write a start entry: the blob's address, $FF, its ordinal.

.STARTER:                      ; .ADDR and RD_PREV are the blob's.
    LD   HL,(.ADDR)                ; The address,
    CALL LT_WORD                   ; written.
    LD   A,$FF                     ; $FF marks a start entry,
    CALL LT_BYTE                   ; in place of the part.
    LD   HL,(RD_PREV)              ; The blob's ordinal,
    CALL LT_WORD                   ; in place of the source.
    JR   .COUNT                    ; Count the entry.

;@ROUTINE IN HL CLOBBERS A,DE,HL,CARRY,ZERO,SIGN,PARITY,HALFCARRY
; Write an entry: address = the blob's + LN_POS, part, source HL.

.ENTRY:                        ; HL is the source offset.
    PUSH HL                        ; Keep it.
    LD   HL,(.ADDR)                ; The blob's address
    LD   DE,(LN_POS)               ; plus the entry's offset
    ADD  HL,DE                     ; is the statement's address,
    CALL LT_WORD                   ; written.
    LD   A,(LN_PART)               ; The part,
    CALL LT_BYTE                   ; written.
    POP  HL                        ; The source offset,
    CALL LT_WORD                   ; written.
.COUNT:                        ; An entry is written.
    LD   HL,(LT_CNT)               ; One more
    INC  HL                        ; entry
    LD   (LT_CNT),HL               ; in the table.
    RET                            ; Done.

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
    JR   NZ,.BAD                   ; Out of step.
    CALL LN_WORD                   ; Its ordinal
    LD   DE,(RD_PREV)              ; must be the blob's.
    OR   A                         ; Clear carry for the subtraction.
    SBC  HL,DE                     ; Equal?
    JR   NZ,.BAD                   ; Out of step.
    JP   LN_WORD                   ; HL is its entry count; return.
.BAD:                          ; The stream doesn't match the directory.
    JR   LN_FAIL                   ; A spare jump to the report.

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
.NAME:                         ; Skip the name.
    LD   A,D                       ; Any left?
    OR   A                         ; Zero when done.
    JR   Z,LN_NEXT                 ; The next record.
    CALL LN_BYTE                   ; Skip a character.
    DEC  D                         ; One fewer.
    JR   .NAME                     ; Go on.
.SET:                          ; A is a blob-lines tag or $FF.
    LD   (LN_TAG),A                ; Kept for LN_BLOB or LN_CLOSE.
    RET                            ; Done.

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
    LD   B,5                       ; The table's trailer: $FF x 5,
.MARK:                         ; B counts them.
    LD   A,$FF                     ; One $FF,
    CALL LT_BYTE                   ; written.
    DJNZ .MARK                     ; Until five are written.
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
