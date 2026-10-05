;==========================================================================
;  Phase A: reading the directories
;==========================================================================
;
;  Phase A (linker §4) reads the library's directory and the program's,
;  NAME.$DR, into the tables of linker §2.1, checking each record as it
;  comes. CHECKS.ASM holds the program directory's header and the checks
;  made once both are read; PHASEB.ASM marks what is live.
;
;  Principal entries:
;    PA_RUN    lay out the tables, read both directories and check them
;    RD_BYTE   read a directory byte into the CRC (RD_WORD a word, RD_RAW
;              without the CRC)
;    TAB_FIND  the table entry of an ordinal, growing the program table
;    EDGE_ADD  push a word onto the edge lists
;    DG_FILE, DG_PLAIN, DG_ORD, DG_SHORT, DG_CAP, DG_REF, DG_SPARE
;              report a diagnostic and end the link
;
;  Table entry, 8 bytes, one per ordinal (the E_ offsets):
;    +0 flags: bits 0-2 kind, 3 defined, 4 referenced, 5 live, 6 alias,
;       7 root (the EF_ bits)
;    +1 size (an alias: its offset)   +3 address (an alias: its base ordinal)
;    +5 edges: the address of the lowest of its distinct targets, or 0
;    +7 layout: the alignment code
;
;  Memory, from FREEMEM up: the library table, indexed by ordinal from 0,
;  then the program table, which grows, indexed by ordinal - $0400. The edge
;  lists grow down from EDGE_TOP, TAB_ROOM bytes below the stack. A blob
;  with references has a $0000 terminator with its distinct targets below
;  it, and its edges field points at the lowest. The two must not meet.
;
;  Failure: every check that fails reports its diagnostic and ends the link
;  through LK_FAIL, so a routine here that returns has succeeded.

E_FLAGS EQU  0                 ; Entry: the flags byte, kind and EF_ bits.
E_SIZE EQU  1                  ; Entry: the size word; an alias's offset until Phase C.
E_ADDR EQU  3                  ; Entry: the address word; an alias's base until Phase C.
E_EDGES EQU  5                 ; Entry: the address of the lowest edge, or 0.
E_LAYOUT EQU  7                ; Entry: the alignment code, 0 to 7.
EF_DEF EQU  $08                ; Flag: defined by a blob or alias record.
EF_REF EQU  $10                ; Flag: referenced, so it must be defined.
EF_LIVE EQU  $20               ; Flag: live, marked in Phase B.
EF_ALIAS EQU  $40              ; Flag: an alias of another blob.
EF_ROOT EQU  $80               ; Flag: a root, live whatever refers to it.
K_CODE EQU  0                  ; Kind: code, in TEXT.
K_DATA EQU  2                  ; Kind: data, in TEXT or, under option R, DATA.
K_BSS EQU  3                   ; Kind: bss, uninitialised, with no bytes.
K_START EQU  4                 ; Kind: startup, the library's first record.
PS_MAIN EQU  $FFE0             ; Pseudo-object MAIN: the program's entry routine.
PS_FILES EQU  $FFE8            ; Pseudo-object FILES: the file table.
PS_COUNT EQU  $FFE9            ; Pseudo-object FILECOUNT: its entries.
TAB_ROOM EQU  $0300            ; Kept below the stack for calls and messages.

LIB_HEAD:                      ; The library's header and profile block.
    DS   64                        ; Read by LIB_READ; the PF_ fields are within.
DIR_HEAD:                      ; The program directory's header.
    DS   20                        ; Read by DIR_OPEN.
LIB_TAB:                       ; The library table's base: FREEMEM.
    DW   0                         ; Set by PA_RUN.
LIB_CNT:                       ; The library's entries: its highest ordinal + 1.
    DW   0                         ; Set by PA_RUN from the header.
PRG_TAB:                       ; The program table's base, after the library's.
    DW   0                         ; Set by PA_RUN.
PRG_CNT:                       ; The program's entries so far.
    DW   0                         ; Grown by TAB_FIND.
PRG_END:                       ; The end of the program table.
    DW   0                         ; Grown by TAB_FIND; the mark stack starts here.
EDGE_PTR:                      ; The lowest word of the edge lists.
    DW   0                         ; Moves down as EDGE_ADD pushes.
EDGE_TOP:                      ; The top of the edge lists.
    DW   0                         ; Set by PA_RUN and not read again.
PA_MAIN:                       ; The ordinal the ENTRY record names: MAIN.
    DW   0                         ; Checked by PA_CHECK, followed in Phase B.
PA_ENTRY:                      ; Nonzero once the ENTRY record is read.
    DB   0                         ; There must be exactly one.
PA_LIMIT:                      ; The LIMITS record: stack reserve, largest frame, flags.
    DS   5                         ; Copied as read.
PA_LIMOK:                      ; Nonzero once the LIMITS record is read.
    DB   0                         ; There must be exactly one.
PA_FIRST:                      ; The kind of the library's first record.
    DB   $FF                       ; $FF until it is read; $FE for a control record.
PB_FILES:                      ; Nonzero when a live blob refers to FILES.
    DB   0                         ; Set by Phase B; the program then uses files.
RD_NAME:                       ; The file being read as text, for diagnostics.
    DW   0                         ; Argument 1 of DG_FILE and DG_SHORT.

RD_OWNER:                      ; The directory being read: 0 library, 1 program.
    DB   0                         ; Library ordinals may refer only to the library.
RD_PREV:                       ; The last ordinal read: the current blob's.
    DW   0                         ; The next implicit ordinal is one more.
.HASPREV:                      ; Unused.
    DB   0                         ; A spare byte.
RD_FIRST:                      ; The lowest ordinal this directory may define.
    DW   0                         ; $0001 for the library, $0400 for the program.
RD_LAST:                       ; The highest ordinal this directory may define.
    DW   0                         ; $03FF for the library, $FFDF for the program.
RD_TOTAL:                      ; The byte stream the records account for so far.
    DW   0                         ; The sum of the sizes of every blob but bss.
RD_LIMIT:                      ; Nonzero once this directory's LIMITS is read.
    DB   0                         ; Copied to RD_AFTER by each blob record.
RD_AFTER:                      ; Nonzero once a blob follows LIMITS.
    DB   0                         ; LIMITS must follow the last blob.
RD_COUNT:                      ; The blob records read.
    DW   0                         ; Checked against the trailer.
RD_SIZE:                       ; The current blob's size.
    DW   0                         ; References must lie within it.
RD_ENTRY:                      ; The current blob's table entry.
    DW   0                         ; Its edges field is set after its references.
EDGE_END:                      ; The current blob's terminator in the edge lists.
    DW   0                         ; Where the search for a repeated target stops.
REF_LAST:                      ; The current reference's offset in its blob.
    DW   0                         ; Deltas are added to it.
REF_ANY:                       ; Nonzero once the blob has had a reference.
    DB   0                         ; The first offset is not a delta.
REF_END:                       ; The end of the previous reference.
    DW   0                         ; In Phase D, the bytes of the blob copied.
REF_FORM:                      ; The current reference's form, 0 to 3.
    DB   0                         ; ABS16, LO8, HI8, SIZE16.
RD_HEAD:                       ; The current record's header byte.
    DB   0                         ; Kind, explicit ordinal, root, alignment.
RD_ORD:                        ; The ordinal the current record defines.
    DW   0                         ; For diagnostics and the table.
REF_CNT:                       ; The current blob's references still to read.
    DW   0                         ; Counted down as they are read.
DG_HEX:                        ; An ordinal argument as text.
    DS   8                         ; "$HHHH" and a zero.

; ---- reading ---------------------------------------------------------------

;@ROUTINE IN IX OUT A CLOBBERS CARRY,ZERO,SIGN,PARITY,HALFCARRY
; Read the next byte of the file at IX into A, adding it to CRC_VAL while
; RD_CRC is set, and keeping BC, DE and HL. A file that ends early is
; reported as L-TRUNCATED, and the link ends.

RD_BYTE:                       ; IX is a directory being read.
    CALL RD_RAW                    ; A is the byte; the end of file doesn't return.
    PUSH HL                        ; The CRC is checked in Phase A only.
    LD   HL,RD_CRC                 ; Is it still being computed?
    INC  (HL)                      ; Test the flag
    DEC  (HL)                      ; for zero, keeping it.
    POP  HL                        ; Recover HL; the flags remain.
    RET  Z                         ; Phases C to E read without the CRC.
    JP   CRC_ADD                   ; Add A to the CRC, which returns to the caller.

RD_CRC:                        ; Nonzero while the bytes read go into CRC_VAL.
    DB   1                         ; Cleared once Phase A has checked the CRCs.

;@ROUTINE IN IX OUT A CLOBBERS CARRY,ZERO,SIGN,PARITY,HALFCARRY
; Read the next byte of the file at IX into A without the CRC, keeping BC,
; DE and HL. A file that ends early is L-TRUNCATED.

RD_RAW:                        ; IX is a file being read.
    CALL FIL_GETB                  ; A is the byte, or carry at the end.
    RET  NC                        ; A byte was read.

;@ROUTINE NORETURN
; Report L-TRUNCATED for the file being read, and end the link.

DG_SHORT:                      ; RD_NAME is the file.
    LD   HL,214                    ; L-TRUNCATED.
    JR   DG_FILE                   ; With the file's name as argument 1.

;@ROUTINE IN IX OUT A,HL CLOBBERS CARRY,ZERO,SIGN,PARITY,HALFCARRY
; Read the next word into HL, low byte first, keeping BC and DE.

RD_WORD:                       ; IX is a directory being read.
    CALL RD_BYTE                   ; The low byte.
    LD   L,A                       ; L is the low byte.
    CALL RD_BYTE                   ; The high byte.
    LD   H,A                       ; H is the high byte.
    RET                            ; HL is the word.

;@ROUTINE NORETURN
; Report message HL with the file being read, RD_NAME, as argument 1, and
; end the link.

DG_FILE:                       ; HL is the message number.
    PUSH HL                        ; Keep it while the argument is set.
    LD   HL,(RD_NAME)              ; The file's name as text
    LD   (DG_ARG1),HL              ; is argument 1.
    POP  HL                        ; HL is the message number.
    CALL DG_ERROR                  ; Report it.
    JP   LK_FAIL                   ; End the link.

;@ROUTINE NORETURN
; Report message HL with no argument, and end the link.

DG_PLAIN:                      ; HL is the message number.
    CALL DG_ERROR                  ; Report it.
    JP   LK_FAIL                   ; End the link.

;@ROUTINE NORETURN
; Report message HL with the ordinal in DE as "$HHHH", and end the link.

DG_ORD:                        ; HL is the message number, DE the ordinal.
    PUSH HL                        ; Keep the number while the text is made.
    LD   HL,DG_HEX                 ; The argument's text.
    LD   (HL),'$'                  ; A dollar sign first,
    INC  HL                        ; then the digits.
    LD   A,D                       ; The high byte,
    CALL .HEX2                     ; in two digits,
    LD   A,E                       ; then the low byte,
    CALL .HEX2                     ; in two digits.
    LD   (HL),0                    ; Terminate the text.
    LD   HL,DG_HEX                 ; The text
    LD   (DG_ARG1),HL              ; is argument 1.
    POP  HL                        ; HL is the message number.
    CALL DG_ERROR                  ; Report it.
    JP   LK_FAIL                   ; End the link.

;@ROUTINE IN A,HL OUT HL CLOBBERS A,CARRY,ZERO,SIGN,PARITY,HALFCARRY
; Store A as two hex digits at HL, high first, advancing HL.

.HEX2:                         ; A is the byte, HL the place.
    PUSH AF                        ; Keep the low digit for later.
    RRCA                           ; Bring the high four bits
    RRCA                           ; down
    RRCA                           ; to the
    RRCA                           ; low four.
    CALL .HEX1                     ; Store the high digit.
    POP  AF                        ; A is the byte again; store its low digit.

;@ROUTINE IN A,HL OUT HL CLOBBERS A,CARRY,ZERO,SIGN,PARITY,HALFCARRY
; Store the hex digit for A's low four bits at HL, advancing HL.

.HEX1:                         ; A's low four bits are the digit.
    CALL LK_DIGIT                  ; A is its character.
    LD   (HL),A                    ; Store it.
    INC  HL                        ; The next place.
    RET                            ; HL is past the digit.

;@ROUTINE IN A OUT A CLOBBERS CARRY,ZERO,SIGN,PARITY,HALFCARRY
; Return in A the ASCII hex digit for A's low four bits, 0-9 or A-F.

LK_DIGIT:                      ; Used for ordinals, Intel HEX and the map.
    AND  $0F                       ; Keep the low four bits.
    ADD  A,$90                     ; $90-$99 for 0-9, $9A-$9F for 10-15.
    DAA                            ; $90-$99, or $00-$05 with carry.
    ADC  A,$40                     ; $D0-$D9, or $41-$46.
    DAA                            ; '0'-'9' ($30-$39), or 'A'-'F'.
    RET                            ; A is the digit's character.

; ---- tables ------------------------------------------------------------------

;@ROUTINE IN HL OUT HL,CARRY CLOBBERS A,DE,ZERO,SIGN,PARITY,HALFCARRY
; Return in HL the entry of ordinal HL, growing the program table, zeroed,
; to cover it. Carry if the ordinal has no entry: a pseudo-object, or a
; library ordinal beyond the library's highest. Program tables that would
; pass $FFFF or meet the edge lists report L-CAP-TABLES.

TAB_FIND:                      ; HL is an ordinal.
    LD   A,H                       ; Is it $FFxx?
    CP   $FF                       ; Only there are pseudo-objects.
    JR   NZ,.REAL                  ; Not a pseudo-object.
    LD   A,L                       ; $FFE0 and above are pseudo-objects.
    CP   $E0                       ; Carry below $FFE0,
    CCF                            ; inverted: carry for a pseudo-object.
    RET  C                         ; $FFE0 and above: pseudo, no entry.
.REAL:                         ; HL is a library or program ordinal.
    LD   A,H                       ; Program ordinals start at $0400.
    CP   $04                       ; Is it below that?
    JR   NC,.PROG                  ; A program ordinal.
    LD   DE,(LIB_CNT)              ; The library's entries.
    OR   A                         ; Clear carry for the subtraction.
    SBC  HL,DE                     ; Carry while the ordinal is within them,
    CCF                            ; inverted: carry beyond them.
    RET  C                         ; Beyond the library.
    ADD  HL,DE                     ; HL is the ordinal again.
    ADD  HL,HL                     ; Eight bytes
    ADD  HL,HL                     ; per
    ADD  HL,HL                     ; entry.
    LD   DE,(LIB_TAB)              ; From the library table's base.
    ADD  HL,DE                     ; HL is the entry.
    OR   A                         ; Clear carry: found.
    RET                            ; A library entry.
.PROG:                         ; HL is $0400 or above.
    LD   DE,$0400                  ; The program table starts at $0400.
    OR   A                         ; Clear carry for the subtraction.
    SBC  HL,DE                     ; HL = index.
    PUSH HL                        ; Keep the index for the address.
    LD   DE,(PRG_CNT)              ; The entries so far.
    OR   A                         ; Clear carry for the subtraction.
    SBC  HL,DE                     ; Carry if the index is within them.
    JR   C,.HAVE                   ; The entry exists.
    POP  HL                        ; Grow to index + 1, zeroing the new entries:
    PUSH HL                        ; HL is the index, still kept.
    INC  HL                        ; The new count.
    LD   (PRG_CNT),HL              ; Record it.
    LD   A,H                       ; 8K entries or more
    AND  $E0                       ; would take 64K:
    JR   NZ,DG_CAP                 ; L-CAP-TABLES.
    ADD  HL,HL                     ; Eight bytes
    ADD  HL,HL                     ; per
    ADD  HL,HL                     ; entry.
    LD   DE,(PRG_TAB)              ; From the program table's base,
    ADD  HL,DE                     ; the new end,
    JR   C,DG_CAP                  ; which may not pass $FFFF.
    EX   DE,HL                     ; DE is the new end.
    LD   HL,(EDGE_PTR)             ; It may not pass the edge lists.
    OR   A                         ; Clear carry for the subtraction.
    SBC  HL,DE                     ; Carry if the end passes EDGE_PTR.
    JR   C,DG_CAP                  ; It meets the edge lists.
    LD   HL,(PRG_END)              ; Zero from the old end.
.ZERO:                         ; HL walks up to DE.
    LD   A,L                       ; Has HL reached
    CP   E                         ; the new end?
    JR   NZ,.ZEROONE               ; Not yet.
    LD   A,H                       ; Compare
    CP   D                         ; the high bytes.
    JR   Z,.ZEROED                 ; The new entries are clear.
.ZEROONE:                      ; HL is below the new end.
    LD   (HL),0                    ; Clear one byte.
    INC  HL                        ; The next.
    JR   .ZERO                     ; Until the new end.
.ZEROED:                       ; The table covers the index.
    LD   (PRG_END),DE              ; Its new end.
.HAVE:                         ; The index is on the stack.
    POP  HL                        ; HL is the index.
    ADD  HL,HL                     ; Eight bytes
    ADD  HL,HL                     ; per
    ADD  HL,HL                     ; entry.
    LD   DE,(PRG_TAB)              ; From the program table's base.
    ADD  HL,DE                     ; HL is the entry.
    OR   A                         ; Clear carry: found.
    RET                            ; A program entry.

;@ROUTINE NORETURN
; Report L-CAP-TABLES: the tables don't fit in memory.

DG_CAP:                        ; The program table and edge lists met.
    LD   HL,215                    ; L-CAP-TABLES.
    JP   DG_PLAIN                  ; Report it and end the link.

;@ROUTINE IN DE CLOBBERS A,HL,CARRY,ZERO,SIGN,PARITY,HALFCARRY
; Push the word DE onto the edge lists, keeping BC and DE. L-CAP-TABLES if
; the lists would meet the program table.

EDGE_ADD:                      ; DE is a target ordinal, or 0 for a terminator.
    LD   HL,(EDGE_PTR)             ; The lowest word so far.
    DEC  HL                        ; Two bytes
    DEC  HL                        ; below it.
    LD   (EDGE_PTR),HL             ; The lists' new bottom.
    PUSH HL                        ; Keep the place,
    PUSH DE                        ; and the word.
    LD   DE,(PRG_END)              ; The program table's end.
    OR   A                         ; Clear carry for the subtraction.
    SBC  HL,DE                     ; Carry if the place is below it.
    POP  DE                        ; Recover the word,
    POP  HL                        ; and the place.
    JR   C,DG_CAP                  ; The lists meet the table.
    LD   (HL),E                    ; Store the word,
    INC  HL                        ; low byte
    LD   (HL),D                    ; first.
    RET                            ; HL is the word's high byte.

; ---- Phase A -----------------------------------------------------------------

;@ROUTINE CLOBBERS A,BC,DE,HL,IX,CARRY,ZERO,SIGN,PARITY,HALFCARRY
; Phase A: lay out the tables, read and check the library's directory and
; then the program's, and make the closing checks of linker §4.3.

PA_RUN:                        ; The library's header is in LIB_HEAD.
    LD   HL,(LIB_HEAD+36)          ; The library's highest ordinal.
    INC  HL                        ; Its entries: one per ordinal from 0.
    LD   (LIB_CNT),HL              ; The library table's length in entries.
    ADD  HL,HL                     ; Eight bytes
    ADD  HL,HL                     ; per
    ADD  HL,HL                     ; entry.
    LD   B,H                       ; BC = the library table's bytes,
    LD   C,L                       ; to clear and to skip.
    LD   HL,FREEMEM                ; The tables start above the program.
    LD   (LIB_TAB),HL              ; The library table first,
    ADD  HL,BC                     ; then
    LD   (PRG_TAB),HL              ; the program table,
    LD   (PRG_END),HL              ; empty to begin with.
    LD   HL,0                      ; The edge lists lie below the stack:
    ADD  HL,SP                     ; HL is the stack pointer,
    LD   DE,TAB_ROOM               ; less the room the stack needs
    OR   A                         ; for calls and messages.
    SBC  HL,DE                     ; HL is the lists' top.
    LD   (EDGE_TOP),HL             ; Record it,
    LD   (EDGE_PTR),HL             ; and start the lists empty there.
    LD   DE,(PRG_TAB)              ; The library table must fit below it.
    OR   A                         ; Clear carry for the subtraction.
    SBC  HL,DE                     ; Carry if the top is below the program table.
    JR   C,DG_CAP                  ; Not even the library's table fits.
    LD   HL,(LIB_TAB)              ; Zero the library table.
.CLR:                          ; HL walks the table, BC counts down.
    LD   A,B                       ; Is BC zero?
    OR   C                         ; Then the table is clear.
    JR   Z,.LIB                    ; Read the library's directory.
    LD   (HL),0                    ; Clear one byte.
    INC  HL                        ; The next.
    DEC  BC                        ; One fewer.
    JR   .CLR                      ; Until all are clear.
.LIB:                          ; The library's directory, its CRC from its start.
    LD   IX,LIB_FD                 ; Read the library.
    LD   HL,LIB_TEXT               ; Its name
    LD   (RD_NAME),HL              ; for diagnostics.
    LD   A,(LIB_HEAD+14)           ; The directory's offset in the file,
    LD   HL,(LIB_HEAD+12)          ; 24 bits.
    CALL FIL_SEEK                  ; Go there.
    JP   C,DG_SHORT                ; The file is shorter than its header says.
    CALL CRC_NEW                   ; The directory's CRC starts here.
    XOR  A                         ; The library is
    LD   (RD_OWNER),A              ; owner 0.
    LD   HL,1                      ; Its ordinals run from $0001
    LD   (RD_FIRST),HL             ; (0 is never a blob)
    LD   HL,$03FF                  ; to $03FF.
    LD   (RD_LAST),HL              ; Program ordinals follow.
    LD   HL,0                      ; The implicit first ordinal: $0001 - 1.
    CALL .READDIR                  ; Read its records and trailer.
    LD   HL,(RD_BYTES)             ; The trailer must agree with the header:
    LD   DE,(LIB_HEAD+20)          ; the byte section's length
    OR   A                         ; (16 bits; the trailer's high word is 0),
    SBC  HL,DE                     ; compared.
    JP   NZ,DG_SHORT               ; They disagree.
    LD   HL,(RD_HIGH)              ; And the highest ordinal,
    LD   DE,(LIB_HEAD+36)          ; which sized the table,
    OR   A                         ; compared.
    SBC  HL,DE                     ; Equal?
    JP   NZ,DG_SHORT               ; They disagree.
    CALL DIR_OPEN                  ; The program's directory: open it, check its header.
    LD   A,1                       ; The program is
    LD   (RD_OWNER),A              ; owner 1.
    LD   HL,$0400                  ; Its ordinals run from $0400
    LD   (RD_FIRST),HL             ; to
    LD   HL,$FFDF                  ; $FFDF, below the pseudo-objects.
    LD   (RD_LAST),HL              ; The range for its records.
    LD   HL,(DIR_HEAD+16)          ; The ordinal base, the first implicit ordinal,
    DEC  HL                        ; less one.
    CALL .READDIR                  ; Read its records and trailer.
    JP   PA_CHECK                  ; The checks once both are read.

;@ROUTINE IN HL,IX CLOBBERS A,BC,DE,HL,CARRY,ZERO,SIGN,PARITY,HALFCARRY
; Read records from the directory at IX until the trailer, which is checked.
; HL is the implicit ordinal before the first record.

.READDIR:                      ; RD_OWNER, RD_FIRST and RD_LAST are set.
    LD   (RD_PREV),HL              ; The first implicit ordinal is one more.
    LD   HL,0                      ; No bytes,
    LD   (RD_TOTAL),HL             ; accounted for yet,
    LD   (RD_COUNT),HL             ; and no blobs.
    XOR  A                         ; No LIMITS yet,
    LD   (RD_LIMIT),A              ; in this directory,
    LD   (RD_AFTER),A              ; nor a blob after it; fall into PA_NEXT.

;@ROUTINE CLOBBERS A,BC,DE,HL,CARRY,ZERO,SIGN,PARITY,HALFCARRY
; Read and check the directory's next record, enter it in the table, and
; go on to the next until the trailer, whose RET returns to .READDIR's
; caller. Control records go to PA_CTRL, which jumps back here.

PA_NEXT:                       ; IX is at a record's header byte.
    CALL RD_BYTE                   ; A is the header byte.
    CP   $FF                       ; $FF begins the trailer.
    JP   Z,PA_TRAIL                ; Check the trailer and return.
    LD   (RD_HEAD),A               ; Keep the header byte.
    AND  7                         ; The kind.
    CP   6                         ; Kind 6 is a control record.
    JP   Z,PA_CTRL                 ; Alias, entry, bank or limits.
    CP   5                         ; Kinds 5 and 7 are reserved.
    JP   NC,DG_SPARE               ; L-RESERVED.
    LD   A,(RD_LIMIT)              ; A blob after LIMITS
    LD   (RD_AFTER),A              ; is reported at the trailer.
    LD   A,(RD_HEAD)               ; The ordinal: explicit, or one more than the last.
    BIT  3,A                       ; Bit 3: an explicit ordinal follows.
    JR   Z,.IMPL                   ; Implicit.
    CALL RD_WORD                   ; HL is the explicit ordinal.
    JR   .ORD                      ; Use it.
.IMPL:                         ; The ordinal after the last.
    LD   HL,(RD_PREV)              ; The last ordinal,
    INC  HL                        ; plus one.
.ORD:                          ; HL is the record's ordinal.
    LD   (RD_ORD),HL               ; The ordinal defined,
    LD   (RD_PREV),HL              ; and the next implicit one's base.
    CALL PA_RANGE                  ; Carry unless it is in this owner's range.
    LD   HL,205                    ; L-ORDINAL: outside its range.
    LD   DE,(RD_ORD)               ; The ordinal is the argument.
    JP   C,DG_ORD                  ; Report it.
    CALL RD_WORD                   ; HL is the blob's size.
    LD   (RD_SIZE),HL              ; Keep it.
    LD   A,H                       ; Is it zero?
    OR   L                         ; A blob has at least one byte.
    LD   HL,207                    ; L-BLOB: a blob of size 0.
    JP   Z,DG_PLAIN                ; Report it.
    CALL RD_BYTE                   ; The reference count, or 255 for a word.
    LD   L,A                       ; HL is the count,
    LD   H,0                       ; zero-extended.
    CP   255                       ; The escape?
    JR   NZ,.COUNT                 ; A count below 255.
    CALL RD_WORD                   ; The count as a word; one below 255 is not refused.
.COUNT:                        ; HL is the reference count.
    LD   (REF_CNT),HL              ; Keep it for PA_REFS.
    LD   A,(RD_HEAD)               ; Checks on the kind.
    AND  7                         ; The kind,
    LD   C,A                       ; C = kind.
    CP   K_CODE                    ; Code may not be aligned.
    JR   Z,.NOALIGN                ; Check its alignment.
    CP   K_START                   ; Startup may not be aligned,
    JR   NZ,.ALIGNOK               ; nor be in the program.
    LD   A,(RD_OWNER)              ; Is this the program?
    OR   A                         ; Owner 1.
    LD   HL,207                    ; L-BLOB: startup in the program.
    JP   NZ,DG_PLAIN               ; Report it.
.NOALIGN:                      ; Code or startup.
    LD   A,(RD_HEAD)               ; Bits 5-7: the alignment.
    AND  $E0                       ; Must be zero.
    LD   HL,207                    ; L-BLOB: aligned code or startup.
    JP   NZ,DG_PLAIN               ; Report it.
.ALIGNOK:                      ; C is the kind.
    LD   A,C                       ; A bss blob has no bytes,
    CP   K_BSS                     ; so nothing to patch.
    JR   NZ,.NOTBSS                ; Not bss.
    LD   HL,(REF_CNT)              ; Does it have references?
    LD   A,H                       ; Test the count
    OR   L                         ; for zero.
    LD   HL,207                    ; L-BLOB: bss with references.
    JP   NZ,DG_PLAIN               ; Report it.
.NOTBSS:                       ; The library's first record.
    LD   A,(RD_OWNER)              ; Only the library's first record is noted.
    OR   A                         ; The program?
    JR   NZ,.ENTRY                 ; Nothing to note.
    LD   A,(PA_FIRST)              ; $FF until the first record is read.
    INC  A                         ; Was it $FF?
    JR   NZ,.ENTRY                 ; Already noted.
    LD   A,C                       ; The first record's kind,
    LD   (PA_FIRST),A              ; which must be startup.
.ENTRY:                        ; Enter the blob in its table.
    LD   HL,(RD_ORD)               ; Its ordinal.
    CALL TAB_FIND                  ; HL is its entry; carry if it has none.
    LD   (RD_ENTRY),HL             ; Keep the entry.
    LD   DE,(RD_ORD)               ; The ordinal is the argument.
    LD   HL,205                    ; L-ORDINAL: beyond the library's highest.
    JP   C,DG_ORD                  ; Report it.
    LD   HL,(RD_ENTRY)             ; Is it defined already?
    BIT  3,(HL)                    ; EF_DEF.
    LD   HL,205                    ; L-ORDINAL: defined twice.
    JP   NZ,DG_ORD                 ; Report it.
    LD   HL,(RD_ENTRY)             ; Fill the entry.
    LD   A,(RD_HEAD)               ; The flags: the kind,
    AND  7                         ; bits 0-2,
    OR   EF_DEF                    ; and defined,
    LD   B,A                       ; kept in B.
    LD   A,(RD_HEAD)               ; The header's root bit,
    AND  $10                       ; bit 4,
    RLCA                           ; moves
    RLCA                           ; to
    RLCA                           ; bit 7, EF_ROOT.
    OR   B                         ; With the kind and defined.
    LD   (HL),A                    ; E_FLAGS.
    INC  HL                        ; E_SIZE:
    LD   DE,(RD_SIZE)              ; the blob's size,
    LD   (HL),E                    ; low byte,
    INC  HL                        ; then
    LD   (HL),D                    ; high byte.
    INC  HL                        ; E_ADDR:
    LD   (HL),0                    ; no address
    INC  HL                        ; until
    LD   (HL),0                    ; Phase C.
    INC  HL                        ; E_EDGES:
    LD   (HL),0                    ; none
    INC  HL                        ; until its
    LD   (HL),0                    ; references are read.
    INC  HL                        ; E_LAYOUT:
    LD   A,(RD_HEAD)               ; the header's bits 5-7,
    RLCA                           ; rotated
    RLCA                           ; to
    RLCA                           ; bits 0-2,
    AND  7                         ; alone.
    LD   (HL),A                    ; Layout: the alignment code.
    LD   A,C                       ; The byte stream holds every kind but bss.
    CP   K_BSS                     ; Is it bss?
    JR   Z,.REFS                   ; No bytes in the stream.
    LD   HL,(RD_TOTAL)             ; The stream so far,
    LD   DE,(RD_SIZE)              ; plus this blob,
    ADD  HL,DE                     ; must stay within 64K.
    JP   C,DG_SHORT                ; It doesn't: the trailer can't agree.
    LD   (RD_TOTAL),HL             ; The stream so far.
.REFS:                         ; Count the blob and read its references.
    LD   HL,(RD_COUNT)             ; One more
    INC  HL                        ; blob
    LD   (RD_COUNT),HL             ; record.
    CALL PA_REFS                   ; Read, check and record its references.
    JP   PA_NEXT                   ; The next record.

;@ROUTINE IN HL OUT CARRY CLOBBERS DE,HL,ZERO,SIGN,PARITY,HALFCARRY
; Carry unless ordinal HL lies in RD_FIRST..RD_LAST.

PA_RANGE:                      ; HL is an ordinal.
    LD   DE,(RD_FIRST)             ; The lowest allowed.
    OR   A                         ; Clear carry for the subtraction.
    SBC  HL,DE                     ; Carry if below it.
    RET  C                         ; Out of range.
    ADD  HL,DE                     ; HL is the ordinal again.
    EX   DE,HL                     ; DE is the ordinal.
    LD   HL,(RD_LAST)              ; The highest allowed.
    OR   A                         ; Clear carry for the subtraction.
    SBC  HL,DE                     ; Carry if ordinal > last.
    RET                            ; Carry reports it out of range.

;@ROUTINE NORETURN
; Report L-RESERVED: a reserved kind, form or record, and end the link.

DG_SPARE:                      ; Something version 1.0 reserves.
    LD   HL,206                    ; L-RESERVED.
    JP   DG_PLAIN                  ; Report it and end the link.

;@ROUTINE CLOBBERS A,BC,DE,HL,CARRY,ZERO,SIGN,PARITY,HALFCARRY
; Read the references of the blob just read, REF_CNT of them, checking each
; and adding its distinct targets to the blob's edges at RD_ENTRY.

PA_REFS:                       ; IX is at the blob's first reference.
    LD   HL,(REF_CNT)              ; Are there any?
    LD   A,H                       ; Test the count
    OR   L                         ; for zero.
    RET  Z                         ; None: the edges field stays 0.
    LD   DE,0                      ; The blob's terminator,
    CALL EDGE_ADD                  ; pushed first, above its targets.
    LD   HL,(EDGE_PTR)             ; Where it is,
    LD   (EDGE_END),HL             ; for the search for repeats.
    XOR  A                         ; No reference read yet,
    LD   (REF_ANY),A               ; so the first offset is absolute.
    LD   HL,0                      ; And nothing before it
    LD   (REF_END),HL              ; to overlap.
.NEXT:                         ; IX is at a reference's control byte.
    CALL RD_BYTE                   ; Control: bit 7 form, bit 6 addend, 0-5 delta.
    LD   B,A                       ; Keep it for its bits.
    AND  $3F                       ; The delta,
    CP   63                        ; or 63 for an absolute offset.
    JR   NZ,.DELTA                 ; A delta.
    CALL RD_WORD                   ; An absolute offset.
    LD   A,(REF_ANY)               ; After the first reference
    OR   A                         ; it must be beyond the last.
    JR   Z,.OFF                    ; The first: any offset.
    PUSH HL                        ; Keep the offset.
    LD   DE,(REF_LAST)             ; The last offset.
    EX   DE,HL                     ; HL is the last, DE the new.
    OR   A                         ; Clear carry for the subtraction.
    SBC  HL,DE                     ; Last - offset: no carry means not increasing.
    POP  HL                        ; HL is the offset.
    JP   NC,DG_REF                 ; Offsets must strictly increase.
    JR   .OFF                      ; Use it.
.DELTA:                        ; A is the delta, 0 to 62.
    LD   L,A                       ; HL is the delta,
    LD   H,0                       ; zero-extended.
    LD   A,(REF_ANY)               ; For the first reference
    OR   A                         ; it is the offset itself.
    JR   Z,.OFF                    ; The first.
    LD   A,L                       ; After that,
    OR   A                         ; a zero delta
    JR   Z,DG_REF                  ; would repeat the offset.
    LD   DE,(REF_LAST)             ; Add the delta
    ADD  HL,DE                     ; to the last offset.
.OFF:                          ; HL is the reference's offset.
    LD   (REF_LAST),HL             ; Keep it.
    LD   A,1                       ; A reference has been read,
    LD   (REF_ANY),A               ; so later ones are deltas or must increase.
    XOR  A                         ; The form: ABS16 unless given.
    BIT  7,B                       ; Bit 7: a form byte follows.
    JR   Z,.FORM                   ; ABS16.
    CALL RD_BYTE                   ; The form byte.
    OR   A                         ; A form byte of 0 is reserved.
    JR   Z,DG_SPARE                ; Form byte 0.
.FORM:                         ; A is the form.
    LD   (REF_FORM),A              ; Keep it.
    CP   4                         ; ABS16, LO8, HI8 and SIZE16 only.
    JR   NC,DG_SPARE               ; BANK8 and beyond.
    LD   E,2                       ; The width: ABS16 and SIZE16 2 bytes,
    CP   1                         ; LO8
    JR   Z,.NARROW                 ; and
    CP   2                         ; HI8
    JR   NZ,.WIDTH                 ; 1.
.NARROW:                       ; A byte-wide form.
    LD   E,1                       ; One byte.
.WIDTH:                        ; E is the width.
    LD   D,0                       ; DE = width.
    PUSH BC                        ; Keep the control byte.
    LD   HL,(REF_LAST)             ; The offset
    LD   BC,(REF_END)              ; may not be inside the previous reference.
    OR   A                         ; Clear carry for the subtraction.
    SBC  HL,BC                     ; Carry if it starts before that one ends.
    POP  BC                        ; B is the control byte.
    JR   C,DG_REF                  ; Overlaps the previous reference.
    LD   HL,(REF_LAST)             ; The offset
    ADD  HL,DE                     ; plus the width
    LD   (REF_END),HL              ; is this reference's end.
    EX   DE,HL                     ; DE is the end.
    LD   HL,(RD_SIZE)              ; It may not pass the blob's end.
    OR   A                         ; Clear carry for the subtraction.
    SBC  HL,DE                     ; Carry if the end is beyond the size.
    JR   C,DG_REF                  ; Leaves the blob.
    CALL RD_WORD                   ; The target.
    PUSH HL                        ; Keep it.
    BIT  6,B                       ; Bit 6: an addend follows.
    JR   Z,.NOADD                  ; No addend.
    CALL RD_WORD                   ; The addend: not needed until Phase D.
.NOADD:                        ; The target is on the stack.
    POP  HL                        ; HL is the target.
    CALL PA_TGT                    ; Check it and add it to the edges.
    LD   HL,(REF_CNT)              ; One fewer
    DEC  HL                        ; reference
    LD   (REF_CNT),HL              ; to read.
    LD   A,H                       ; Any left?
    OR   L                         ; Zero when done.
    JP   NZ,.NEXT                  ; The next reference.
    LD   HL,(RD_ENTRY)             ; The blob's edges field: its lowest target.
    LD   DE,E_EDGES                ; The field's offset.
    ADD  HL,DE                     ; HL is the field.
    LD   DE,(EDGE_PTR)             ; The last target pushed is the lowest.
    LD   (HL),E                    ; Store it,
    INC  HL                        ; low byte
    LD   (HL),D                    ; first.
    RET                            ; The blob's references are recorded.

;@ROUTINE NORETURN
; Report L-REFERENCE: a malformed reference, and end the link.

DG_REF:                        ; A bad offset, target or form.
    LD   HL,208                    ; L-REFERENCE.
    JP   DG_PLAIN                  ; Report it and end the link.

;@ROUTINE IN HL CLOBBERS A,DE,HL,CARRY,ZERO,SIGN,PARITY,HALFCARRY
; Check the target HL of a reference, mark it referenced, and add it to the
; blob's edges unless it is already among them.

PA_TGT:                        ; HL is the target ordinal.
    LD   A,H                       ; Ordinal 0
    OR   L                         ; is never a blob.
    JR   Z,DG_REF                  ; Ordinal 0.
    LD   A,H                       ; Is it $FFxx?
    CP   $FF                       ; Only there are pseudo-objects.
    JR   NZ,.REAL                  ; Not a pseudo-object.
    LD   A,L                       ; $FFE0 and above
    CP   $E0                       ; are pseudo-objects.
    JR   C,.REAL                   ; Below: an ordinary ordinal.
    CP   $EA                       ; Ten are defined, $FFE0 to $FFE9.
    JR   NC,DG_REF                 ; An undefined pseudo-object.
    JR   .ADD                      ; A pseudo-object is an edge, without an entry.
.REAL:                         ; HL is a blob or alias ordinal.
    LD   A,(RD_OWNER)              ; The library refers only to itself.
    OR   A                         ; The program may refer to either.
    JR   NZ,.MARK                  ; The program's reference.
    LD   A,H                       ; A library reference
    CP   $04                       ; to a program ordinal
    JR   NC,DG_REF                 ; is refused.
    PUSH HL                        ; Keep the target.
    LD   DE,(LIB_HEAD+36)          ; The library's highest ordinal.
    EX   DE,HL                     ; HL is the highest, DE the target.
    OR   A                         ; Clear carry for the subtraction.
    SBC  HL,DE                     ; Highest - target.
    POP  HL                        ; HL is the target.
    JR   C,DG_REF                  ; Above the library's highest.
.MARK:                         ; Mark the target referenced.
    PUSH HL                        ; Keep the target.
    CALL TAB_FIND                  ; Referenced; carry: beyond the library.
    JR   C,.UNDEF                  ; A library ordinal with no entry.
    LD   A,(REF_FORM)              ; SIZE16 of a known alias.
    CP   3                         ; Is the form SIZE16?
    JR   NZ,.SETREF                ; Other forms may name an alias.
    BIT  6,(HL)                    ; Is the target an alias already read?
    JR   NZ,DG_REF                 ; SIZE16 may not name one.
.SETREF:                       ; HL is the target's entry.
    SET  4,(HL)                    ; EF_REF: it must be defined.
    POP  HL                        ; HL is the target.
.ADD:                          ; Add the target unless it is a repeat.
    EX   DE,HL                     ; DE = the target.
    LD   HL,(EDGE_PTR)             ; Already among this blob's edges?
.SCAN:                         ; HL walks up from the lowest edge to EDGE_END.
    PUSH DE                        ; Keep the target.
    LD   DE,(EDGE_END)             ; The blob's terminator.
    LD   A,L                       ; Has HL reached it?
    CP   E                         ; Compare the low bytes,
    JR   NZ,.CMP                   ; different;
    LD   A,H                       ; compare
    CP   D                         ; the high bytes.
.CMP:                          ; Z if HL is the terminator.
    POP  DE                        ; DE is the target.
    JR   Z,.NEW                    ; Not found among the edges.
    LD   A,(HL)                    ; An edge's low byte.
    INC  HL                        ; Its high byte.
    CP   E                         ; Does the low byte match?
    JR   NZ,.SKIP                  ; No.
    LD   A,(HL)                    ; The high byte.
    CP   D                         ; Does it match?
    RET  Z                         ; A repeat: already an edge.
.SKIP:                         ; HL is the edge's high byte.
    INC  HL                        ; The next edge.
    JR   .SCAN                     ; Go on.
.NEW:                          ; DE is a new target.
    JP   EDGE_ADD                  ; Push it, and return to the caller.
.UNDEF:                        ; The target is on the stack.
    POP  DE                        ; DE is the target, the argument.
    LD   HL,213                    ; L-UNDEFINED.
    JP   DG_ORD                    ; Report it and end the link.

;@ROUTINE CLOBBERS A,BC,DE,HL,CARRY,ZERO,SIGN,PARITY,HALFCARRY
; Read a control record: an alias, the entry, a bank or the limits. Each
; is checked and recorded, then reading goes on at PA_NEXT.

PA_CTRL:                       ; RD_HEAD is the record's header byte.
    LD   A,(RD_OWNER)              ; The library's first record isn't startup
    OR   A                         ; if it is a control record.
    JR   NZ,.KIND                  ; The program's.
    LD   A,(PA_FIRST)              ; $FF until the library's first record.
    INC  A                         ; Was it $FF?
    JR   NZ,.KIND                  ; Already noted.
    LD   A,$FE                     ; A control record came first,
    LD   (PA_FIRST),A              ; which is not startup.
.KIND:                         ; The subtype is in bits 3-7.
    LD   A,(RD_HEAD)               ; The header byte,
    RRCA                           ; shifted
    RRCA                           ; down
    RRCA                           ; three bits,
    AND  $1F                       ; is the subtype.
    JR   Z,.ALIAS                  ; 0: ALIAS.
    DEC  A                         ; 1:
    JR   Z,.ENTRY                  ; ENTRY.
    DEC  A                         ; 2:
    JP   Z,DG_SPARE                ; BANK is reserved in 1.0.
    DEC  A                         ; 3 is LIMITS;
    JP   NZ,DG_SPARE               ; others are reserved.
    LD   A,(RD_OWNER)              ; LIMITS, once, in the program.
    OR   A                         ; The library?
    JR   Z,.BADLIM                 ; The library has no LIMITS.
    LD   A,(PA_LIMOK)              ; Already read?
    OR   A                         ; Nonzero if so.
    JR   NZ,.BADLIM                ; A second LIMITS.
    INC  A                         ; A = 1:
    LD   (PA_LIMOK),A              ; LIMITS has been read,
    LD   (RD_LIMIT),A              ; in this directory.
    LD   HL,PA_LIMIT               ; Copy its five bytes
    LD   B,5                       ; as they are.
.LIM:                          ; HL walks PA_LIMIT.
    CALL RD_BYTE                   ; The next byte.
    LD   (HL),A                    ; Store it.
    INC  HL                        ; The next place.
    DJNZ .LIM                      ; Until all five are copied.
    JP   PA_NEXT                   ; The next record.
.BADLIM:                       ; LIMITS in the library, or twice.
    LD   HL,211                    ; L-LIMITS.
    JP   DG_PLAIN                  ; Report it and end the link.

.ENTRY:                        ; ENTRY: the ordinal of MAIN.
    CALL RD_WORD                   ; HL is the entry ordinal.
    LD   A,(RD_OWNER)              ; Only the program has one.
    OR   A                         ; The library?
    JR   Z,.BADENTRY               ; The library has no ENTRY.
    LD   A,(PA_ENTRY)              ; Already read?
    OR   A                         ; Nonzero if so.
    JR   NZ,.BADENTRY              ; A second ENTRY.
    INC  A                         ; A = 1:
    LD   (PA_ENTRY),A              ; ENTRY has been read.
    LD   (PA_MAIN),HL              ; Its ordinal is checked by PA_CHECK.
    JP   PA_NEXT                   ; The next record.
.BADENTRY:                     ; ENTRY in the library, or twice.
    LD   HL,210                    ; L-ENTRY.
    JP   DG_PLAIN                  ; Report it and end the link.

.ALIAS:                        ; ALIAS: alias, base, offset.
    CALL RD_WORD                   ; The alias.
    LD   (RD_ORD),HL               ; The ordinal it defines.
    CALL PA_RANGE                  ; Carry unless it is in this owner's range.
    LD   DE,(RD_ORD)               ; The ordinal is the argument.
    LD   HL,209                    ; L-ALIAS: outside its range.
    JP   C,DG_ORD                  ; Report it.
    LD   HL,(RD_ORD)               ; Its entry,
    CALL TAB_FIND                  ; which a library ordinal may lack.
    LD   (RD_ENTRY),HL             ; Keep it.
    LD   DE,(RD_ORD)               ; The ordinal is the argument.
    LD   HL,205                    ; L-ORDINAL: beyond the library's highest.
    JP   C,DG_ORD                  ; Report it.
    LD   HL,(RD_ENTRY)             ; Is it defined already?
    BIT  3,(HL)                    ; EF_DEF.
    LD   HL,205                    ; L-ORDINAL: defined twice.
    JP   NZ,DG_ORD                 ; Report it.
    CALL RD_WORD                   ; The base.
    PUSH HL                        ; Keep it.
    CALL RD_WORD                   ; The offset.
    EX   DE,HL                     ; DE = offset.
    POP  BC                        ; BC = base.
    LD   HL,(RD_ENTRY)             ; Fill the alias's entry.
    LD   (HL),EF_DEF+EF_ALIAS      ; E_FLAGS: a defined alias, kind 0.
    INC  HL                        ; E_SIZE holds the offset
    LD   (HL),E                    ; until Phase C,
    INC  HL                        ; low byte
    LD   (HL),D                    ; first.
    INC  HL                        ; E_ADDR holds the base
    LD   (HL),C                    ; until Phase C,
    INC  HL                        ; low byte
    LD   (HL),B                    ; first.
    LD   H,B                       ; The base is referenced:
    LD   L,C                       ; HL is the base.
    PUSH BC                        ; Keep it as the argument.
    CALL TAB_FIND                  ; HL is its entry; carry if it has none.
    POP  DE                        ; DE is the base.
    LD   HL,209                    ; L-ALIAS: a bad base.
    JP   C,DG_ORD                  ; Report it.
    SET  4,(HL)                    ; EF_REF: the base must be defined.
    JP   PA_NEXT                   ; The next record.

RD_BYTES:                      ; The trailer's byte-stream length.
    DW   0                         ; The library's is checked against its header.
RD_HIGH:                       ; The trailer's highest ordinal.
    DW   0                         ; Checked for the library only.

;@ROUTINE CLOBBERS A,DE,HL,CARRY,ZERO,SIGN,PARITY,HALFCARRY
; Read and check the trailer: the blob count, the byte stream's length, the
; highest ordinal, a reserved byte, then the CRC of everything before the
; CRC. Its RET returns to .READDIR's caller.

PA_TRAIL:                      ; The $FF that begins the trailer is read.
    CALL RD_WORD                   ; The blob count.
    LD   DE,(RD_COUNT)             ; The blob records read.
    OR   A                         ; Clear carry for the subtraction.
    SBC  HL,DE                     ; Equal?
    JP   NZ,DG_SHORT               ; A record is missing or extra.
    CALL RD_WORD                   ; The byte stream's length, low then high.
    LD   (RD_BYTES),HL             ; The low word.
    CALL RD_WORD                   ; The high word.
    LD   A,H                       ; It must be zero:
    OR   L                         ; the stream is at most 64K.
    JP   NZ,DG_SHORT               ; At most 64K.
    CALL RD_WORD                   ; The highest ordinal.
    LD   (RD_HIGH),HL              ; PA_RUN compares the library's.
    CALL RD_BYTE                   ; Reserved.
    LD   HL,(CRC_VAL)              ; The CRC of everything so far,
    PUSH HL                        ; kept.
    CALL RD_RAW                    ; The stored CRC's low byte,
    LD   E,A                       ; read without adding it,
    CALL RD_RAW                    ; and its high byte.
    LD   D,A                       ; DE is the stored CRC.
    POP  HL                        ; HL is the computed CRC.
    OR   A                         ; Clear carry for the subtraction.
    SBC  HL,DE                     ; Equal?
    JP   NZ,DG_SHORT               ; The CRC.
    LD   HL,(RD_TOTAL)             ; The records account for the stream:
    LD   DE,(RD_BYTES)             ; the sum of their sizes is its length.
    OR   A                         ; Clear carry for the subtraction.
    SBC  HL,DE                     ; Equal?
    JP   NZ,DG_SHORT               ; They don't.
    LD   A,(RD_AFTER)              ; Did a blob follow LIMITS?
    OR   A                         ; Nonzero if so.
    LD   HL,211                    ; L-LIMITS: blobs after LIMITS.
    JP   NZ,DG_PLAIN               ; Report it.
    RET                            ; The directory is read: to .READDIR's caller.
