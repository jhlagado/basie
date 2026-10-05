;==========================================================================
;  Phase A: the program's header and the closing checks
;==========================================================================
;
;  The rest of Phase A (linker §4.3): opening the program's directory,
;  NAME.$DR, and checking its header against the library and the options
;  against the library's profile; then, once both directories are read,
;  the checks that need the whole table.
;
;  Principal entries:
;    DIR_OPEN  open NAME.$DR on the spool drive and check its header
;    FIL_TEXT  write a file's name as text, for diagnostics
;    PA_CHECK  the closing checks: ENTRY, LIMITS, startup, undefined
;              references and aliases
;    TAB_AT    the entry at a table position (TAB_ORD its ordinal)
;    EDGE_HAS  whether an entry has a given edge
;
;  A table position runs over both tables as one: the library's ordinals 0
;  to LIB_CNT - 1, then the program's from $0400. The tables are contiguous,
;  so the position times eight is the entry's offset from LIB_TAB.
;
;  Failure: a failed check reports its diagnostic and ends the link.

DIR_FD:                        ; The FD that reads NAME.$DR.
    DS   FD_SIZE                   ; Kept open for the walks of Phases C to E.
DIR_TYPE:                      ; The program directory's type.
    DB   "$DR"                     ; Three characters.
DIR_TEXT:                      ; Its name as text, for diagnostics.
    DS   13                        ; NAME.$DR and a zero.

;@ROUTINE OUT IX CLOBBERS A,BC,DE,HL,CARRY,ZERO,SIGN,PARITY,HALFCARRY
; Open NAME.$DR on the spool drive, read its header into DIR_HEAD and check
; it against the library (linker §4.3; object format §10), then check the
; options against the profile. IX is left on the directory's first record,
; with CRC_VAL counting from the file's start.

DIR_OPEN:                      ; Called once the library's directory is read.
    LD   IX,DIR_FD                 ; The directory's own FD.
    LD   A,(OP_SPOOL)              ; The spool drive, if S= gave one,
    OR   A                         ; is where the intermediates are;
    JR   NZ,.DRV                   ; it was given.
    LD   A,(CMD_DISK)              ; Otherwise the first part's drive.
.DRV:                          ; A is the drive.
    LD   HL,CMD_NAME               ; NAME,
    LD   DE,DIR_TYPE               ; type $DR.
    CALL FIL_INIT                  ; Set up the FCB.
    LD   HL,CMD_NAME               ; Its name as text,
    LD   DE,DIR_TEXT               ; into DIR_TEXT,
    LD   BC,DIR_TYPE               ; with its type.
    CALL FIL_TEXT                  ; NAME.$DR.
    LD   HL,DIR_TEXT               ; The file being read,
    LD   (RD_NAME),HL              ; for diagnostics.
    CALL FIL_OPEN                  ; Open it; carry if it doesn't exist.
    LD   HL,225                    ; L-MISSING.
    JP   C,DG_FILE                 ; Report it with the name.
    CALL CRC_NEW                   ; The directory's CRC covers its header.
    LD   HL,DIR_HEAD               ; Read the 20-byte header
    LD   B,20                      ; into DIR_HEAD.
.HEAD:                         ; HL walks DIR_HEAD.
    CALL RD_BYTE                   ; The next byte, into the CRC.
    LD   (HL),A                    ; Store it.
    INC  HL                        ; The next place.
    DJNZ .HEAD                     ; Until all 20 are read.
    LD   HL,DIR_HEAD               ; Magic and version.
    LD   DE,.MAGIC                 ; Compare the magic
    LD   B,4                       ; over four bytes.
.COMPARE:                      ; HL walks the header, DE the magic.
    LD   A,(DE)                    ; A magic byte.
    CP   (HL)                      ; Does the header match?
    JR   NZ,.BADMAG                ; Not a program directory.
    INC  HL                        ; The next header byte.
    INC  DE                        ; The next magic byte.
    DJNZ .COMPARE                  ; Until all four match.
    LD   A,(DIR_HEAD+4)            ; The major version
    CP   1                         ; must be 1.
    LD   HL,200                    ; L-FORMAT.
    JP   NZ,DG_FILE                ; An unknown major version.
    LD   A,(DIR_HEAD+5)            ; The minor version
    OR   A                         ; must be 0.
    JP   NZ,DG_FILE                ; A higher minor version: L-FORMAT.
    LD   HL,(DIR_HEAD+8)           ; Compatibility: the runtime's identity
    LD   DE,(LIB_HEAD+6)           ; must be the library's.
    OR   A                         ; Clear carry for the subtraction.
    SBC  HL,DE                     ; Equal?
    JR   NZ,.COMPAT                ; Incompatible.
    LD   HL,(DIR_HEAD+14)          ; The profile's identity
    LD   DE,(LIB_HEAD+10)          ; must be the library's.
    OR   A                         ; Clear carry for the subtraction.
    SBC  HL,DE                     ; Equal?
    JR   NZ,.COMPAT                ; Incompatible.
    LD   HL,(LIB_HEAD+8)           ; The library's helper-table version
    LD   DE,(DIR_HEAD+10)          ; must be at least the program's.
    OR   A                         ; Clear carry for the subtraction.
    SBC  HL,DE                     ; Carry if it is lower.
    JR   C,.COMPAT                 ; The library is too old.
    LD   HL,(DIR_HEAD+12)          ; The program's key, unless 0,
    LD   A,H                       ; must match the library's key
    OR   L                         ; for the program's version.
    JR   Z,.STAMP                  ; 0: no key to check.
    CALL .LIBKEY                   ; HL is the library's key.
    LD   DE,(DIR_HEAD+12)          ; The program's.
    OR   A                         ; Clear carry for the subtraction.
    SBC  HL,DE                     ; Equal?
    JR   NZ,.COMPAT                ; Incompatible.
.STAMP:                        ; The compilation stamp.
    LD   HL,(DIR_HEAD+6)           ; Phase D checks the streams carry it.
    LD   A,H                       ; It may not
    OR   L                         ; be zero.
    LD   HL,202                    ; L-STAMP: stamp 0.
    JP   Z,DG_PLAIN                ; Report it.
    JR   .PROFILE                  ; Check the options against the profile.
.COMPAT:                       ; The program was built for another library.
    LD   HL,201                    ; L-COMPAT.
    JP   DG_PLAIN                  ; Report it.
.BADMAG:                       ; Not a program directory.
    LD   HL,200                    ; L-FORMAT.
    JP   DG_FILE                   ; Report it with the name.
.MAGIC:                        ; The program directory's magic.
    DB   "BSIP"                    ; Basie program directory.

;@ROUTINE CLOBBERS A,DE,HL,CARRY,ZERO,SIGN,PARITY,HALFCARRY
; Check the options and the output kind against the profile (linker §3).
; ROM targets, class 3 and above, are not implemented: L-RESERVED.

.PROFILE:                      ; The profile block is LIB_HEAD+42 on.
    LD   HL,206                    ; L-RESERVED.
    LD   A,(LIB_HEAD+42)           ; The target class.
    CP   3                         ; 3 and above are ROM targets.
    JP   NC,DG_PLAIN               ; Not implemented.
    LD   HL,203                    ; L-OPTION.
    LD   A,(OP_FLAGS)              ; Option B, keep the CCP,
    AND  OF_B                      ; needs the profile's support.
    JR   Z,.BCHECKED               ; Not given.
    LD   A,(LIB_HEAD+58)           ; Option support: bit 0 keep the CCP.
    RRA                            ; Bit 0 to carry.
    JP   NC,DG_PLAIN               ; Not supported.
.BCHECKED:                     ; HL is still L-OPTION.
    LD   A,(OP_FLAGS)              ; Option R, re-runnable,
    AND  OF_R                      ; likewise.
    JR   Z,.RCHECKED               ; Not given.
    LD   A,(LIB_HEAD+58)           ; Bit 1 re-runnable.
    AND  2                         ; Supported?
    JP   Z,DG_PLAIN                ; Not supported.
.RCHECKED:                     ; The options are supported.
    INC  HL                        ; L-OUTPUT.
    LD   A,(LIB_HEAD+43)           ; The output kinds the profile allows.
    LD   DE,OUT_KIND               ; The kind asked for,
    EX   DE,HL                     ; addressed by HL,
    AND  (HL)                      ; tested against them.
    EX   DE,HL                     ; HL is L-OUTPUT, DE the kind.
    JP   Z,DG_PLAIN                ; Not allowed.
    LD   A,(DE)                    ; .COM needs image base $0100.
    DEC  A                         ; Kind 1 is .COM.
    RET  NZ                        ; .BIN and .HEX may start anywhere.
    LD   DE,(LIB_HEAD+44)          ; The profile's image base.
    DEC  D                         ; $0100 less $0100
    LD   A,D                       ; is zero
    OR   E                         ; only for $0100.
    RET  Z                         ; A .COM at $0100.
    JP   DG_PLAIN                  ; L-OUTPUT: not a .COM base.

;@ROUTINE OUT HL CLOBBERS A,BC,DE,CARRY,ZERO,SIGN,PARITY,HALFCARRY
; Return in HL the library's key for the program's helper-table version.
; The key table is a count, then a key per version. The library's
; directory has been read, so LIB_FD itself is moved to the table; IX is
; kept for the program's directory. A truncated table is L-TRUNCATED for
; the library; RD_NAME names NAME.$DR again afterwards.

.LIBKEY:                       ; DIR_HEAD+10 is the program's version.
    LD   HL,LIB_TEXT               ; The file being read,
    LD   (RD_NAME),HL              ; for diagnostics.
    PUSH IX                        ; Keep the program directory's FD.
    LD   IX,LIB_FD                 ; Read the library.
    LD   A,(LIB_HEAD+34)           ; The key table's offset,
    LD   HL,(LIB_HEAD+32)          ; 24 bits.
    CALL FIL_SEEK                  ; Go there.
    JP   C,DG_SHORT                ; The file is too short.
    CALL RD_RAW                    ; The count's low byte,
    LD   L,A                       ; read without the CRC,
    CALL RD_RAW                    ; and its high byte.
    LD   H,A                       ; HL = the count.
    LD   DE,(DIR_HEAD+10)          ; The program's version, 1 to count.
    LD   A,D                       ; Version 0
    OR   E                         ; has no key.
    JR   Z,.NONE                   ; Incompatible.
    OR   A                         ; Clear carry for the subtraction.
    SBC  HL,DE                     ; Carry if the version is beyond the count.
    JR   C,.NONE                   ; Incompatible.
    LD   B,D                       ; BC is the version,
    LD   C,E                       ; counted down to its key.
.SKIP:                         ; Skip the keys before the version's.
    DEC  BC                        ; One fewer to skip.
    LD   A,B                       ; Is it the version's key?
    OR   C                         ; BC reaches zero there.
    JR   Z,.KEY                    ; Read it.
    CALL RD_RAW                    ; Skip a key's
    CALL RD_RAW                    ; two bytes.
    JR   .SKIP                     ; The next.
.KEY:                          ; IX is at the version's key.
    CALL RD_RAW                    ; Its low byte,
    LD   L,A                       ; into L,
    CALL RD_RAW                    ; and its high byte,
    LD   H,A                       ; into H.
    POP  IX                        ; IX is the program's directory again,
    LD   DE,DIR_TEXT               ; as the file
    LD   (RD_NAME),DE              ; being read.
    RET                            ; HL is the key.
.NONE:                         ; The library has no key for the version.
    POP  IX                        ; Recover IX.
    LD   HL,201                    ; L-COMPAT.
    JP   DG_PLAIN                  ; Report it.

;@ROUTINE IN BC,DE,HL OUT DE CLOBBERS A,BC,HL,CARRY,ZERO,SIGN,PARITY,HALFCARRY
; Write the file name NAME.TYP as zero-terminated text at DE: HL is the
; space-padded 8-character name, BC the 3-character type. DE is left at
; the zero.

FIL_TEXT:                      ; DE has room for 13 bytes.
    PUSH BC                        ; Keep the type's address.
    LD   B,8                       ; At most eight name characters.
.NAME:                         ; HL walks the name, DE the text.
    LD   A,(HL)                    ; The next name character.
    CP   ' '                       ; Padding ends the name.
    JR   Z,.DOT                    ; The name is done.
    LD   (DE),A                    ; Copy it.
    INC  HL                        ; The next character.
    INC  DE                        ; The next place.
    DJNZ .NAME                     ; Until eight are copied.
.DOT:                          ; DE is after the name.
    LD   A,'.'                     ; The dot
    LD   (DE),A                    ; before the type.
    INC  DE                        ; The type follows.
    POP  HL                        ; HL is the type.
    LD   BC,3                      ; Three characters,
    LDIR                           ; copied.
    XOR  A                         ; A zero
    LD   (DE),A                    ; terminates the text.
    RET                            ; DE is the zero.

; ---- the checks at the end of Phase A (linker §4.3) ---------------------------

;@ROUTINE CLOBBERS A,BC,DE,HL,CARRY,ZERO,SIGN,PARITY,HALFCARRY
; The checks once both directories are read: ENTRY names a program code
; blob, LIMITS was given, the library's first record is its one startup
; blob and refers to MAIN, every referenced ordinal is defined, and every
; alias is sound.

PA_CHECK:                      ; Both tables are complete.
    LD   A,(PA_ENTRY)              ; ENTRY names a program code blob.
    OR   A                         ; Was ENTRY given?
    JR   Z,.NOENTRY                ; No ENTRY record.
    LD   HL,(PA_MAIN)              ; The ordinal it names.
    LD   A,H                       ; It must be the program's:
    CP   $04                       ; $0400 or above.
    JR   C,.NOENTRY                ; A library ordinal.
    CALL TAB_FIND                  ; HL is its entry; carry for a pseudo-object.
    JR   C,.NOENTRY                ; Not a blob.
    LD   A,(HL)                    ; Its flags:
    AND  EF_DEF+EF_ALIAS+7         ; defined, not an alias,
    CP   EF_DEF+K_CODE             ; and of kind code.
    JR   NZ,.NOENTRY               ; Anything else is refused.
    LD   A,(PA_LIMOK)              ; LIMITS was given?
    OR   A                         ; Nonzero if so.
    LD   HL,211                    ; L-LIMITS: missing.
    JP   Z,DG_PLAIN                ; Report it.
    LD   A,(PA_FIRST)              ; Startup is the library's first record.
    CP   K_START                   ; Was it?
    JR   NZ,.NOSTART               ; No.
    LD   B,0                       ; Scan every entry: B counts startups seen.
    LD   HL,0                      ; HL is the table position.
.SCAN:                         ; HL is the position.
    PUSH HL                        ; Keep it.
    PUSH BC                        ; Keep the count.
    CALL TAB_AT                    ; HL = the entry, carry past the end.
    POP  BC                        ; B is the count.
    JR   C,.END                    ; Every entry is checked.
    LD   A,(HL)                    ; Its flags.
    BIT  3,A                       ; Defined?
    JR   NZ,.DEF                   ; Check what it is.
    BIT  4,A                       ; Referenced?
    JR   Z,.NEXT                   ; Neither: an unused ordinal.
    POP  HL                        ; Referenced but never defined.
    CALL TAB_ORD                   ; HL is its ordinal.
    EX   DE,HL                     ; DE is the argument.
    LD   HL,213                    ; L-UNDEFINED.
    JP   DG_ORD                    ; Report it.
.DEF:                          ; A defined entry.
    BIT  6,A                       ; An alias?
    JR   NZ,.ALIAS                 ; Check it.
    AND  7                         ; The kind.
    CP   K_START                   ; Startup?
    JR   NZ,.NEXT                  ; Other kinds need nothing more.
    INC  B                         ; One more startup.
    PUSH HL                        ; Startup must refer to MAIN.
    PUSH BC                        ; Keep the count.
    LD   DE,PS_MAIN                ; MAIN's pseudo-ordinal.
    CALL EDGE_HAS                  ; Carry unless it is an edge.
    POP  BC                        ; B is the count.
    POP  HL                        ; HL is the entry.
    JR   NC,.NEXT                  ; It refers to MAIN.
    POP  HL                        ; Drop the position.
    JR   .NOSTART                  ; L-STARTUP.
.ALIAS:                        ; HL is an alias entry.
    PUSH BC                        ; Keep the count.
    CALL PA_ALIAS                  ; Check it; a bad alias doesn't return.
    POP  BC                        ; B is the count.
.NEXT:                         ; The position is on the stack.
    POP  HL                        ; HL is the position.
    INC  HL                        ; The next.
    JR   .SCAN                     ; Go on.
.END:                          ; The position is on the stack.
    POP  HL                        ; Drop it.
    LD   A,B                       ; Exactly one startup?
    CP   1                         ; The library has one.
    JR   NZ,.NOSTART               ; None, or more than one.
    RET                            ; Phase A is complete.
.NOENTRY:                      ; ENTRY is missing or names no code blob.
    LD   HL,210                    ; L-ENTRY.
    JP   DG_PLAIN                  ; Report it.
.NOSTART:                      ; Startup is missing, misplaced or wrong.
    LD   HL,212                    ; L-STARTUP.
    JP   DG_PLAIN                  ; Report it.

;@ROUTINE IN HL OUT HL CLOBBERS DE,CARRY,ZERO,SIGN,PARITY,HALFCARRY
; Return in HL the ordinal at table position HL, keeping BC.

TAB_ORD:                       ; HL is a table position.
    LD   DE,(LIB_CNT)              ; The library's entries come first.
    OR   A                         ; Clear carry for the subtraction.
    SBC  HL,DE                     ; Carry if the position is the library's.
    JR   C,.LIB                    ; A library ordinal.
    LD   DE,$0400                  ; Program positions follow,
    ADD  HL,DE                     ; from ordinal $0400.
    RET                            ; HL is the program ordinal.
.LIB:                          ; The position is the ordinal.
    ADD  HL,DE                     ; HL is the position again.
    RET                            ; A library ordinal.

;@ROUTINE IN HL OUT HL,CARRY CLOBBERS DE,ZERO,SIGN,PARITY,HALFCARRY
; Return in HL the entry for table position HL: the library's ordinals 0
; to LIB_CNT - 1, then the program's. Carry past the end.

TAB_AT:                        ; HL is a table position.
    LD   DE,(LIB_CNT)              ; The library's entries.
    OR   A                         ; Clear carry for the subtraction.
    SBC  HL,DE                     ; No carry beyond the library.
    JR   NC,.PROG                  ; A program position.
    ADD  HL,DE                     ; HL is the position again.
    JR   .ADDR                     ; Address its entry.
.PROG:                         ; HL is the program index.
    LD   DE,(PRG_CNT)              ; The program's entries.
    OR   A                         ; Clear carry for the subtraction.
    SBC  HL,DE                     ; Carry while within them,
    CCF                            ; inverted: carry past the end.
    RET  C                         ; Past the end.
    ADD  HL,DE                     ; HL is the program index,
    LD   DE,(LIB_CNT)              ; plus the library's entries,
    ADD  HL,DE                     ; position again.
.ADDR:                         ; HL is the position.
    ADD  HL,HL                     ; Eight bytes
    ADD  HL,HL                     ; per
    ADD  HL,HL                     ; entry.
    LD   DE,(LIB_TAB)              ; The two tables are contiguous.
    ADD  HL,DE                     ; HL is the entry.
    OR   A                         ; Clear carry.
    RET                            ; Found.

;@ROUTINE IN DE,HL OUT CARRY CLOBBERS A,BC,HL,ZERO,SIGN,PARITY,HALFCARRY
; Carry unless the entry at HL has DE among its edges.

EDGE_HAS:                      ; HL is an entry, DE an ordinal.
    PUSH DE                        ; Keep the ordinal.
    LD   DE,E_EDGES                ; The edges field.
    ADD  HL,DE                     ; HL addresses it.
    LD   E,(HL)                    ; Its low byte,
    INC  HL                        ; then
    LD   D,(HL)                    ; its high byte.
    EX   DE,HL                     ; HL = the lowest edge, or 0.
    POP  DE                        ; DE is the ordinal.
    LD   A,H                       ; No edges?
    OR   L                         ; Then it is not among them,
    SCF                            ; with carry.
    RET  Z                         ; No references at all.
.LOOP:                         ; HL walks up the blob's edges.
    LD   A,(HL)                    ; An edge's low byte,
    INC  HL                        ; then
    LD   C,(HL)                    ; its high byte, in C.
    INC  HL                        ; The next edge.
    LD   B,A                       ; B is the low byte.
    OR   C                         ; $0000 is the terminator.
    SCF                            ; Not found,
    RET  Z                         ; the terminator.
    LD   A,B                       ; Does the low byte
    CP   E                         ; match?
    JR   NZ,.LOOP                  ; No.
    LD   A,C                       ; Does the high byte
    CP   D                         ; match?
    JR   NZ,.LOOP                  ; No.
    OR   A                         ; Clear carry: found.
    RET                            ; DE is an edge.

;@ROUTINE IN HL CLOBBERS A,BC,DE,HL,CARRY,ZERO,SIGN,PARITY,HALFCARRY
; Check the alias entry at HL: its base is defined, not an alias, of the
; same owner, and longer than the alias's offset (linker §4.3). L-ALIAS
; otherwise.

PA_ALIAS:                      ; HL is an alias entry.
    PUSH HL                        ; Keep it.
    LD   DE,E_ADDR                 ; Until Phase C its address field
    ADD  HL,DE                     ; holds its base.
    LD   E,(HL)                    ; The base's low byte,
    INC  HL                        ; then
    LD   D,(HL)                    ; DE = the base ordinal.
    EX   DE,HL                     ; HL is the base.
    CALL TAB_FIND                  ; HL is its entry; carry if it has none.
    POP  DE                        ; DE = the alias entry.
    JR   C,.BAD                    ; No entry.
    LD   A,(HL)                    ; The base's flags:
    AND  EF_DEF+EF_ALIAS           ; defined
    CP   EF_DEF                    ; and not an alias.
    JR   NZ,.BAD                   ; Undefined, or an alias.
    PUSH HL                        ; The same owner: both below PRG_TAB,
    PUSH DE                        ; or both above.
    LD   BC,(PRG_TAB)              ; The program table's base.
    OR   A                         ; Clear carry for the subtraction.
    SBC  HL,BC                     ; Carry if the base is the library's.
    LD   A,0                       ; A takes the carry:
    RLA                            ; 1: the base is the library's.
    EX   DE,HL                     ; HL is the alias entry.
    OR   A                         ; Clear carry for the subtraction.
    SBC  HL,BC                     ; Carry if the alias is the library's.
    LD   B,A                       ; B is the base's owner bit.
    LD   A,0                       ; A takes the carry:
    RLA                            ; 1: the alias is the library's.
    CP   B                         ; The same owner?
    POP  DE                        ; DE is the alias entry.
    POP  HL                        ; HL is the base's entry.
    JR   NZ,.BAD                   ; In the other directory.
    INC  HL                        ; The base's size against the offset.
    LD   C,(HL)                    ; The base's size,
    INC  HL                        ; low byte
    LD   B,(HL)                    ; then high.
    EX   DE,HL                     ; HL is the alias entry.
    INC  HL                        ; Its size field holds the offset:
    LD   E,(HL)                    ; low byte,
    INC  HL                        ; then
    LD   D,(HL)                    ; DE = the offset, BC = the base's size.
    LD   H,B                       ; HL is
    LD   L,C                       ; the base's size.
    OR   A                         ; Clear carry for the subtraction.
    SBC  HL,DE                     ; Size - offset.
    JR   C,.BAD                    ; The offset is beyond the base,
    JR   Z,.BAD                    ; or at its end.
    RET                            ; A sound alias.
.BAD:                          ; Any failed check.
    LD   HL,209                    ; L-ALIAS.
    JP   DG_PLAIN                  ; Report it.
