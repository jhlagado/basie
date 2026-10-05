;==========================================================================
;  CP/M shell
;==========================================================================
;
;  The CP/M shell of BASIE.COM (toolchain §2, §5). The CCP loads the image at
;  $0100, whose first instruction jumps to SH_START. The shell reads the
;  command tail at $0080, loads each source part it names into memory
;  above the compiler's workspace, and hands the parts to PR_BUILD, which
;  parses them into the semantic transcript, closes it and replays it into
;  placed Z80 code. A diagnostic is printed as NAME.BSI LINE:COLUMN Error N,
;  with the forked compiler's number, until the message file replaces it
;  (step 66). The stack and the source occupy the CCP's memory, so every
;  exit is a warm boot through $0000.
;
;  Command line: PART[,PART...] [OPTIONS]. A part is [d:]name[.type], of
;  type BSI when it names none, and spaces may surround the commas. Options
;  in brackets are accepted and not yet read.
;
;  Principal entries:
;    SH_START  the program entry, reached from the jump at $0100
;    PUB_*     the output sinks the forked compiler calls; they discard
;              placed output until blob output replaces them (65.4)
;
;  Failure: a malformed command line, a missing part, more than SRC_CAP
;  parts, source too large for memory, or a compiler diagnostic prints one
;  line and then deletes A:$$$.SUB, which stops a running SUBMIT job under
;  CP/M 2.2 (toolchain §5.4). The CP/M 3 return code is not yet set.
;
;  Memory: SP starts at the BDOS entry. The parts are packed upward from
;  MM_SRC, each ending at its first $1A, and must stay MM_STACK bytes below
;  the BDOS entry, which leaves that much for the stack. The workspace,
;  SH_WBEG to SH_WEND below MM_SRC, holds the load state, one FCB, the part
;  descriptors PR_BUILD reads (five bytes each: the part's 1-based id, its
;  start and its exclusive end) and each part's 11-character CP/M name for
;  diagnostics.
;
;  Registers: every BDOS call is taken to change every register, IX and IY
;  included. SH_CHAR saves AF, BC, DE and HL around its call.

SH_BDOS EQU  $0005             ; BDOS entry; the word at $0006 is the top of memory.
SH_TAIL EQU  $0080             ; Command tail: a length byte, then the text.
SH_COUT EQU  2                 ; BDOS console output: E is the character.
SH_OPEN EQU  15                ; BDOS open file: A is $FF when the file is absent.
SH_ERASE EQU  19               ; BDOS delete file: an absent file is only a status.
SH_READ EQU  20                ; BDOS read sequential: A is nonzero at end of file.
SH_DMA EQU  26                 ; BDOS set DMA address: DE receives the next record.
SH_FLEN EQU  36                ; FCB bytes, through the random record number.
SH_NLEN EQU  11                ; FCB name and type bytes, padded with spaces.
SH_SLOT EQU  12                ; A saved part name: the FCB's drive, name and type.

; The shell's workspace, after the compiler's and below the source.
SH_LIMIT EQU  SH_WBEG          ; Word: the source must end at or below here.
SH_LOADP EQU  SH_LIMIT+2       ; Word: the next free source byte, the load point.
SH_PBEG EQU  SH_LOADP+2        ; Word: the start of the part being loaded.
SH_PCNT EQU  SH_PBEG+2         ; Byte: parts loaded, so the next part's index.
SH_FCB EQU  SH_PCNT+1          ; SH_FLEN bytes: the FCB of every BDOS file call.
SH_PARTS EQU  SH_FCB+SH_FLEN   ; SRC_CAP descriptors of 5 bytes: id, start, end.
SH_NAMES EQU  SH_PARTS+SRC_CAP*5 ; SRC_CAP slots of SH_SLOT bytes, by index.
SH_WEND EQU  SH_NAMES+SRC_CAP*SH_SLOT ; The build checks this is at or below MM_SRC.

;@ROUTINE NORETURN
; Load the parts the command tail names, compile them and warm boot, after
; reporting a diagnostic if there is one.

SH_START:                      ; Entered from the jump at $0100.
    LD   HL,(SH_BDOS+1)            ; HL is the BDOS entry, the top of memory.
    LD   SP,HL                     ; The stack grows down from there, over the CCP.
    LD   DE,-MM_STACK              ; Keep MM_STACK bytes below it for the stack.
    ADD  HL,DE                     ; HL is the first byte the source may not use.
    LD   (SH_LIMIT),HL             ; Each record read is checked against it.
    LD   HL,MM_SRC                 ; The first part loads at the base of the source.
    LD   (SH_LOADP),HL             ; Start the load point there.
    XOR  A                         ; No part is loaded yet.
    LD   (SH_PCNT),A               ; The part count starts at zero.
    LD   HL,SH_TAIL                ; Point at the tail's length byte.
    LD   E,(HL)                    ; E is the tail length.
    LD   D,A                       ; Zero-extend it: DE is the length.
    INC  HL                        ; HL is the first tail character.
    PUSH HL                        ; Keep it for the parse.
    ADD  HL,DE                     ; HL is just past the last character.
    LD   (HL),D                    ; Zero-terminate the tail; a full one ends on the spent jump.
    POP  HL                        ; Parse from the first character.
.NEXTPART:                     ; HL is at the start of the tail or after a comma.
    CALL .SPACES                   ; A is the next character that is not a space.
    OR   A                         ; Is this the end of the tail?
    JR   Z,.TAILDONE               ; Then the parts are complete.
    CP   '['                       ; Do the options begin here?
    JR   Z,.TAILDONE               ; They are not yet read, so the parts are complete.
.PART:                         ; HL is at a part's first character.
    CALL .LOAD                     ; Parse the name, load the part, add its descriptor.
    CALL .SPACES                   ; A is the character after the name and any spaces.
    INC  HL                        ; Step past it, in case it is a comma.
    CP   ','                       ; Does another part follow?
    JR   NZ,.NOCOMMA               ; No: only the end or the options may follow.
    CALL .SPACES                   ; A is the first character after the comma.
    OR   A                         ; A comma must be followed by a part,
    JP   Z,SH_USAGE                ; not by the end of the tail
    CP   '['                       ; or by the options.
    JR   NZ,.PART                  ; Parse the next part.
    JP   SH_USAGE                  ; A trailing comma is a malformed command line.
.NOCOMMA:                      ; A is the byte after the part and any spaces.
    OR   A                         ; Is this the end of the tail?
    JR   Z,.TAILDONE               ; Then the parts are complete.
    CP   '['                       ; Otherwise only the options may follow.
    JP   NZ,SH_USAGE               ; Anything else is a malformed command line.
.TAILDONE:                     ; Every part named has been loaded.
    LD   A,(SH_PCNT)               ; A is the number of parts.
    OR   A                         ; Was any part named?
    JP   Z,SH_USAGE                ; A command line needs at least one.
    LD   HL,SH_PARTS               ; PR_BUILD takes the count in A, descriptors at HL.
    LD   IX,SH_DESC                ; IX is the forked compiler's target descriptor.
    CALL PR_BUILD                  ; Compile; carry reports a diagnostic in DG_CODE.
    JP   C,SH_DIAG                 ; Print it and fail.
    JP   0                         ; Success: warm boot, and a SUBMIT job runs on.

;@ROUTINE IN HL OUT A,HL CLOBBERS CARRY,ZERO,SIGN,PARITY,HALFCARRY
; Skip the spaces at HL. A is the first other byte and HL its address; the
; callers test A, not the flags.

.SPACES:                       ; HL is in the zero-terminated tail.
    LD   A,(HL)                    ; Read the next tail byte.
    CP   ' '                       ; Is it a space?
    RET  NZ                        ; No: A and HL locate it.
    INC  HL                        ; Skip the space.
    JR   .SPACES                   ; The terminator ends the scan.

;@ROUTINE IN HL OUT HL CLOBBERS A,BC,DE,IX,IY,CARRY,ZERO,SIGN,PARITY,HALFCARRY
; Parse [d:]name[.type] at HL into the FCB, load the part after the parts
; already loaded, end it at its first $1A and append its descriptor. HL is
; left after the name. Errors leave by SH_MANY, SH_USAGE, SH_MISS, SH_RERR
; and SH_LARGE.

.LOAD:                         ; HL is at the part's first character.
    LD   A,(SH_PCNT)               ; A is the number of parts loaded so far.
    CP   SRC_CAP                   ; Is the descriptor table already full?
    JP   NC,SH_MANY                ; Then this part is one too many.
    CALL SH_BLANK                  ; Start from the current drive and a blank name.
    INC  HL                        ; Peek at the second character.
    LD   A,(HL)                    ; A colon there means a drive letter came first.
    DEC  HL                        ; HL is back at the first character.
    CP   ':'                       ; Is a drive named?
    JR   NZ,.NAME                  ; No: the name starts at HL, on the current drive.
    LD   A,(HL)                    ; A is the drive letter.
    SUB  'A'-1                     ; The FCB counts A: as 1; a byte below '@' wraps high.
    JP   Z,SH_USAGE                ; '@' names no drive.
    CP   17                        ; Drives run from A: to P:, 1 to 16.
    JP   NC,SH_USAGE               ; Reject any other byte.
    LD   (SH_FCB),A                ; Select the named drive.
    INC  HL                        ; Step over the drive letter.
    INC  HL                        ; Step over the colon.
.NAME:                         ; HL is at the name.
    LD   DE,SH_FCB+1               ; The name field follows the drive byte.
    LD   B,8                       ; A name has at most eight characters.
    CALL SH_FIELD                  ; Copy it; HL stops at the first other character.
    LD   A,(SH_FCB+1)              ; A is the name's first byte.
    CP   ' '                       ; Is it still blank?
    JP   Z,SH_USAGE                ; An empty name is a usage error.
    LD   A,(HL)                    ; A is the character that ended the name.
    CP   '.'                       ; Does a type follow?
    JR   NZ,.DEFTYPE               ; No: the part has the default type.
    INC  HL                        ; Step over the dot.
    LD   DE,SH_FCB+9               ; The type field follows the name.
    LD   B,3                       ; A type has at most three characters.
    CALL SH_FIELD                  ; Copy it; HL stops at the first other character.
    LD   A,(SH_FCB+9)              ; A is the type's first byte.
    CP   ' '                       ; A dot with no type after it
    JP   Z,SH_USAGE                ; is a usage error.
    JR   .OPEN                     ; Check what ends the part.
.DEFTYPE:                      ; No dot, so the type is BSI.
    PUSH HL                        ; Keep the tail position across the copy.
    LD   HL,SH_TYPE                ; HL is the default type's text.
    LD   DE,SH_FCB+9               ; DE is the FCB's type field.
    LD   BC,3                      ; A type is three bytes.
    LDIR                           ; The FCB names NAME.BSI.
    POP  HL                        ; HL is back after the name.
.OPEN:                         ; HL is just after the part's name.
    LD   A,(HL)                    ; A is the byte that ended the name.
    OR   A                         ; Is it the end of the tail?
    JR   Z,.NAMEEND                ; Then the name is complete.
    CP   ' '                       ; A space comes before a comma or the options.
    JR   Z,.NAMEEND                ; The caller skips it.
    CP   ','                       ; A comma comes before another part.
    JR   Z,.NAMEEND                ; The caller steps over it.
    CP   '['                       ; A bracket opens the options.
    JP   NZ,SH_USAGE               ; Any other byte, such as ';', cannot end a name.
.NAMEEND:                      ; The FCB names the part.
    PUSH HL                        ; Keep the tail position until the part is loaded.
    LD   A,(SH_PCNT)               ; Keep the name for diagnostics: A is the index.
    CALL SH_PNAME                  ; HL is the name slot of this part's index.
    EX   DE,HL                     ; DE is the slot.
    LD   HL,SH_FCB                 ; Copy the FCB's drive, name and type to the slot.
    LD   BC,SH_SLOT                ; Twelve bytes, so diagnostics can name the drive.
    LDIR                           ; SH_MISS and SH_DIAG print the name from here.
    LD   DE,SH_FCB                 ; DE is the FCB for BDOS.
    LD   C,SH_OPEN                 ; Open the part for reading.
    CALL SH_BDOS                   ; A is $FF if the file is not on the disk.
    INC  A                         ; $FF becomes zero.
    JP   Z,SH_MISS                 ; Report the missing part by name.
    LD   HL,(SH_LOADP)             ; The part starts at the load point.
    LD   (SH_PBEG),HL              ; Keep its start for the trim and the descriptor.
.RECORD:                       ; SH_LOADP is where the next record goes.
    LD   HL,(SH_LOADP)             ; The load point may be up to one record past the
    LD   DE,-128                   ; limit before the read that finds the end of the
    ADD  HL,DE                     ; file, which writes nothing; HL is it less 128.
    EX   DE,HL                     ; DE is the load point less one record.
    CALL .ROOM                     ; Carry if even that is past the limit.
    JP   C,SH_LARGE                ; Records land at most 256 bytes past the limit, in
                                   ; the stack's reserve; .FOUND checks the true end.
    LD   DE,(SH_LOADP)             ; DE is the load point.
    LD   C,SH_DMA                  ; The record is read straight to it.
    CALL SH_BDOS                   ; Set the DMA address to DE.
    LD   DE,SH_FCB                 ; DE is the open part's FCB.
    LD   C,SH_READ                 ; Read its next record.
    CALL SH_BDOS                   ; A is zero if a record was read.
    OR   A                         ; Was one read?
    JR   Z,.ADVANCE                ; Yes: move past it.
    DEC  A                         ; Status 1 is the end of the file.
    JR   Z,.LOADED                 ; The part is complete.
    JP   SH_RERR                   ; Any other status is a read error (toolchain §6.2).
.ADVANCE:                      ; A record was read at SH_LOADP.
    LD   HL,(SH_LOADP)             ; Advance the load point past the record.
    LD   DE,128                    ; A record is 128 bytes.
    ADD  HL,DE                     ; HL is the next load point.
    LD   (SH_LOADP),HL             ; The next record goes there.
    JR   .RECORD                   ; Read until the end of the file.
.LOADED:                       ; The file is in memory from SH_PBEG to SH_LOADP.
    LD   HL,(SH_PBEG)              ; Scan from the part's start for its first $1A.
    LD   DE,(SH_LOADP)             ; DE is the end of the last record.
.TRIM:                         ; HL is the next byte to test, below or at DE.
    LD   A,L                       ; Has the scan reached DE?
    CP   E                         ; Compare the low bytes.
    JR   NZ,.BYTE                  ; They differ: test the byte at HL.
    LD   A,H                       ; Compare the high bytes.
    CP   D                         ; Equal means the end of the records.
    JR   Z,.FOUND                  ; A part without $1A ends there.
.BYTE:                         ; HL is inside the loaded records.
    LD   A,(HL)                    ; Read the next source byte.
    CP   $1A                       ; CP/M ends a text file with $1A in its last record.
    JR   Z,.FOUND                  ; The part ends at the first one.
    INC  HL                        ; Not yet: test the next byte.
    JR   .TRIM                     ; Continue the scan.
.FOUND:                        ; HL is the part's exclusive end.
    EX   DE,HL                     ; DE is the end.
    CALL .ROOM                     ; Carry if the part ends past the limit.
    JP   C,SH_LARGE                ; The part does not fit below the stack's reserve.
    LD   (SH_LOADP),DE             ; The next part loads here, over the $1A and padding.
    LD   A,(SH_PCNT)               ; Build the descriptor: id, start, end.
    LD   L,A                       ; L keeps this part's index.
    INC  A                         ; A is its 1-based id, which DG_PART reports.
    LD   (SH_PCNT),A               ; It is also the new count of parts.
    LD   H,0                       ; HL is the index.
    LD   B,H                       ; B is zero, the index's high byte.
    LD   C,L                       ; BC is the index, added back below.
    ADD  HL,HL                     ; HL = 2 * index.
    ADD  HL,HL                     ; HL = 4 * index.
    ADD  HL,BC                     ; HL = 5 * index, the descriptor's offset.
    LD   BC,SH_PARTS               ; BC is the table's base.
    ADD  HL,BC                     ; HL is this part's descriptor.
    LD   (HL),A                    ; Byte 0 is the id, which becomes SRC_ID.
    INC  HL                        ; Bytes 1 and 2 hold the start.
    LD   BC,(SH_PBEG)              ; BC is where the part began.
    LD   (HL),C                    ; Store the start's low byte.
    INC  HL                        ; Move to its high byte.
    LD   (HL),B                    ; Store the start's high byte.
    INC  HL                        ; Bytes 3 and 4 hold the exclusive end.
    LD   (HL),E                    ; Store the end's low byte.
    INC  HL                        ; Move to its high byte.
    LD   (HL),D                    ; Store the end's high byte.
    POP  HL                        ; HL is back in the tail, just after the name.
    RET                            ; The part is loaded and described.

;@ROUTINE IN DE OUT CARRY CLOBBERS HL,ZERO,SIGN,PARITY,HALFCARRY
; Carry if the address DE is past SH_LIMIT, the first byte the source may
; not use.

.ROOM:                         ; DE is an address in the source area.
    LD   HL,(SH_LIMIT)             ; HL is the limit.
    OR   A                         ; Clear carry for the subtraction.
    SBC  HL,DE                     ; Carry if DE is above it.
    RET                            ; The caller tests carry.

;@ROUTINE CLOBBERS A,B,DE,CARRY,ZERO,SIGN,PARITY,HALFCARRY
; Set the FCB to the current drive, a blank name and type, and zeros in the
; rest, as BDOS open and delete expect. Preserves HL.

SH_BLANK:                      ; Called for each part and for A:$$$.SUB.
    LD   DE,SH_FCB                 ; DE walks the FCB.
    XOR  A                         ; Drive byte zero selects the current drive.
    LD   (DE),A                    ; Store the drive byte.
    INC  DE                        ; DE is the name field.
    LD   B,SH_NLEN                 ; Blank the name and the type.
.NAMELOOP:                     ; B bytes of name and type remain to blank.
    LD   A,' '                     ; CP/M pads names with spaces.
    LD   (DE),A                    ; Blank this byte.
    INC  DE                        ; Move to the next one.
    DJNZ .NAMELOOP                 ; Until the type is blank too.
    LD   B,SH_FLEN-SH_NLEN-1       ; Count the extent, map and record bytes.
    XOR  A                         ; Each of them starts at zero.
.RESTLOOP:                     ; B bytes remain to clear.
    LD   (DE),A                    ; Clear this byte.
    INC  DE                        ; Move to the next one.
    DJNZ .RESTLOOP                 ; Through the random record number.
    RET                            ; The FCB is ready to be named.

;@ROUTINE IN B,DE,HL OUT HL CLOBBERS A,B,DE,CARRY,ZERO,SIGN,PARITY,HALFCARRY
; Copy name characters from HL to DE, at most B of them. HL stops at the
; first character that may not be in a name. A name character beyond the
; B allowed makes the command line malformed.

SH_FIELD:                      ; B is the room left in the field.
    LD   A,(HL)                    ; A is the next tail character.
    CALL .CHAR                     ; May it appear in a CP/M name?
    RET  C                         ; No: the field ends at HL.
    INC  B                         ; Test B for zero without changing it.
    DEC  B                         ; Zero means the field is full.
    JP   Z,SH_USAGE                ; A name character with no room: too long.
    LD   (DE),A                    ; Store it in the FCB.
    INC  DE                        ; Move to the next field byte.
    INC  HL                        ; Move to the next tail character.
    DEC  B                         ; One byte less room.
    JR   SH_FIELD                  ; Copy the rest.

;@ROUTINE IN A OUT CARRY CLOBBERS ZERO,SIGN,PARITY,HALFCARRY
; Carry unless A may appear in a CP/M name (services §4.1): A to Z, 0 to 9
; and the sixteen marks of SH_VALID. The zero terminator is rejected.

.CHAR:                         ; A is the character to classify.
    CP   'A'                       ; Below 'A' it may be a digit or a mark.
    JR   C,.DIGIT                  ; Test for those.
    CP   'Z'+1                     ; Carry if A is a letter.
    CCF                            ; Invert carry, so that a letter returns it clear.
    RET  NC                        ; A letter is a name character.
.DIGIT:                        ; A is not a letter.
    CP   '0'                       ; Below '0' it can only be a mark.
    JR   C,.PUNCT                  ; Search the marks.
    CP   '9'+1                     ; Carry if A is a digit.
    CCF                            ; Invert carry, so that a digit returns it clear.
    RET  NC                        ; A digit is a name character.
.PUNCT:                        ; A is neither a letter nor a digit.
    PUSH HL                        ; The tail position survives the search.
    PUSH BC                        ; So does the caller's field count.
    LD   HL,SH_VALID               ; HL is the marks allowed in names.
    LD   BC,16                     ; BC counts all sixteen of them.
    CPIR                           ; Zero if A is one of them.
    POP  BC                        ; Restore the field count.
    POP  HL                        ; Restore the tail position; the flags survive.
    SCF                            ; Set carry to reject A.
    RET  NZ                        ; Return with it if A is not a mark.
    CCF                            ; It is one: clear carry to accept it.
    RET                            ; A is a name character.

;@ROUTINE IN A OUT HL CLOBBERS DE,CARRY,HALFCARRY
; HL = the saved drive and name of the part whose index is A (0-based),
; at SH_NAMES + SH_SLOT * A.

SH_PNAME:                      ; A is a part index below SRC_CAP.
    LD   L,A                       ; L is the index.
    LD   H,0                       ; Zero-extend it into HL.
    ADD  HL,HL                     ; HL = 2 * index.
    ADD  HL,HL                     ; HL = 4 * index.
    LD   D,H                       ; DE = 4 * index, added back below.
    LD   E,L                       ; Its low byte.
    ADD  HL,HL                     ; HL = 8 * index.
    ADD  HL,DE                     ; HL = 12 * index, the slot's offset.
    LD   DE,SH_NAMES               ; DE is the base of the saved names.
    ADD  HL,DE                     ; HL is the name slot.
    RET                            ; Return the slot in HL.

; ---- diagnostics and failure ------------------------------------------------

;@ROUTINE NORETURN
; Print the diagnostic PR_BUILD left in DG_PART, DG_LINE, DG_COL and DG_CODE
; as NAME.TYP LINE:COLUMN Error N, or as Error N when it names no part, and
; fail.

SH_DIAG:                       ; Reached on carry from PR_BUILD.
    LD   A,(DG_PART)               ; A is the failing part's 1-based id.
    OR   A                         ; Zero means that no part was current.
    JR   Z,.NUMBER                 ; Then print only the number.
    DEC  A                         ; The id less one is the index of its saved name.
    CALL SH_PNAME                  ; HL is that name.
    CALL SH_SHOW                   ; Print it as NAME.TYP.
    LD   A,' '                     ; A space separates the name from the position.
    CALL SH_CHAR                   ; Print it.
    LD   HL,(DG_LINE)              ; The line, counted from 1.
    CALL SH_NUM                    ; Print it.
    LD   A,':'                     ; A colon separates the line from the column.
    CALL SH_CHAR                   ; Print it.
    LD   HL,(DG_COL)               ; The column, counted from 1.
    CALL SH_NUM                    ; Print it.
    LD   A,' '                     ; A space separates the position from the message.
    CALL SH_CHAR                   ; Print it.
.NUMBER:                       ; Print the message and its number.
    LD   HL,SH_EMSG                ; The text before the number.
    CALL SH_PRINT                  ; Print it.
    LD   A,(DG_CODE)               ; A is the forked compiler's diagnostic number.
    LD   L,A                       ; L is the number.
    LD   H,0                       ; Zero-extend it into HL for SH_NUM.
    CALL SH_NUM                    ; Print it.
    JR   SH_QUIT                   ; End the line and fail.

;@ROUTINE NORETURN
; Report that the part .LOAD failed to open is not on the disk, as
; D:NAME.TYP not found.

SH_MISS:                       ; .LOAD saved the part's name before the open.
    LD   DE,SH_FMSG                ; The text after the name.
    JR   SH_NAMED                  ; Print the name, then the text.

;@ROUTINE NORETURN
; Report a part that CP/M could not read, as D:NAME.TYP read error.

SH_RERR:                       ; .LOAD had a read status other than 0 or 1.
    LD   DE,SH_RMSG                ; The text after the name.

;@ROUTINE IN DE NORETURN
; Print the name of the part being loaded, then the text at DE, and fail.

SH_NAMED:                      ; DE is the message that follows the name.
    PUSH DE                        ; Keep it across the name.
    LD   A,(SH_PCNT)               ; The count is still this part's index.
    CALL SH_PNAME                  ; HL is its saved name.
    CALL SH_SHOW                   ; Print it as D:NAME.TYP.
    POP  HL                        ; HL is the message.
    JR   SH_FAIL                   ; Print it and fail.

;@ROUTINE NORETURN
; Report a part beyond the SRC_CAP the descriptor table holds.

SH_MANY:                       ; .LOAD found the table full.
    LD   HL,SH_PMSG                ; The too-many-parts message.
    JR   SH_FAIL                   ; Print it and fail.

;@ROUTINE NORETURN
; Report a part whose next record would cross SH_LIMIT.

SH_LARGE:                      ; .LOAD found no room for a record.
    LD   HL,SH_LMSG                ; The source-too-large message.
    JR   SH_FAIL                   ; Print it and fail.

;@ROUTINE NORETURN
; Report a malformed command line with the usage line.

SH_USAGE:                      ; Reached from the parse of the tail.
    LD   HL,SH_UMSG                ; The usage message, printed by SH_FAIL.

;@ROUTINE NORETURN
; Print the message at HL, then fail as SH_QUIT does.

SH_FAIL:                       ; HL is a zero-terminated message.
    CALL SH_PRINT                  ; Print it.

;@ROUTINE NORETURN
; End the message line, delete A:$$$.SUB and warm boot. CP/M 2.2 has no
; return codes, so deleting the job file is how a failed build stops a
; running SUBMIT job (toolchain §5.4).

SH_QUIT:                       ; Every failure ends here, its message printed.
    LD   A,13                      ; A carriage return begins the line end.
    CALL SH_CHAR                   ; Print it.
    LD   A,10                      ; A line feed ends the message line.
    CALL SH_CHAR                   ; Print it.
    CALL SH_BLANK                  ; Clear the FCB of any part it named.
    LD   HL,SH_JOB                 ; HL is the job file's drive, name and type.
    LD   DE,SH_FCB                 ; DE is the FCB.
    LD   BC,SH_NLEN+1              ; Twelve bytes in all.
    LDIR                           ; The FCB names A:$$$.SUB.
    LD   DE,SH_FCB                 ; DE is the FCB for BDOS.
    LD   C,SH_ERASE                ; Delete the job file.
    CALL SH_BDOS                   ; Without a SUBMIT job there is none: ignore the status.
    JP   0                         ; Warm boot: the CCP is reloaded over the source.

; ---- console ----------------------------------------------------------------

;@ROUTINE IN HL CLOBBERS A,B,HL,IX,IY,CARRY,ZERO,SIGN,PARITY,HALFCARRY
; Print the saved drive and name at HL as D:NAME.TYP, without padding, and
; without the drive when the part was on the current drive.

SH_SHOW:                       ; HL is a saved slot: drive byte, name, type.
    LD   A,(HL)                    ; A is the drive: 0 current, 1 for A:.
    INC  HL                        ; HL is the name.
    OR   A                         ; Was a drive named?
    JR   Z,.NAME                   ; No: print the name alone.
    ADD  A,'A'-1                   ; Make the drive a letter.
    CALL SH_CHAR                   ; Print it.
    LD   A,':'                     ; Then the colon.
    CALL SH_CHAR                   ; Print it.
.NAME:                         ; HL is the eight-character name.
    LD   B,8                       ; The name field has eight characters.
    CALL .CHARS                    ; Print them; HL moves to the type.
    LD   A,'.'                     ; An FCB stores no dot.
    CALL SH_CHAR                   ; Print one between the name and the type.
    LD   B,3                       ; The type field has three characters.

;@ROUTINE IN B,HL OUT HL CLOBBERS A,B,IX,IY,CARRY,ZERO,SIGN,PARITY,HALFCARRY
; Print the B characters at HL, skipping the spaces that pad them, and
; leave HL after them. SH_SHOW calls it for the name and falls in for the
; type.

.CHARS:                        ; B characters of the field remain.
    LD   A,(HL)                    ; A is the next character.
    INC  HL                        ; HL moves on whether or not it prints.
    CP   ' '                       ; Spaces are padding.
    CALL NZ,SH_CHAR                ; Print anything else.
    DJNZ .CHARS                    ; Until the field is done.
    RET                            ; After the type, this returns from SH_SHOW.

;@ROUTINE IN HL CLOBBERS A,HL,IX,IY,CARRY,ZERO,SIGN,PARITY,HALFCARRY
; Print the zero-terminated text at HL.

SH_PRINT:                      ; HL is in the text.
    LD   A,(HL)                    ; A is the next character.
    OR   A                         ; Is it the terminator?
    RET  Z                         ; Yes: the text is printed.
    CALL SH_CHAR                   ; No: print it.
    INC  HL                        ; Move to the next character.
    JR   SH_PRINT                  ; Print the rest.

;@ROUTINE IN HL CLOBBERS A,B,DE,HL,IX,IY,CARRY,ZERO,SIGN,PARITY,HALFCARRY
; Print HL in decimal, without leading zeros.

SH_NUM:                        ; HL is an unsigned word.
    LD   B,0                       ; B becomes nonzero once a digit is printed.
    LD   DE,10000                  ; A word has at most five digits.
    CALL .DIGIT                    ; Print the ten thousands; HL keeps the rest.
    LD   DE,1000                   ; Then the thousands.
    CALL .DIGIT                    ; The rest is below 1000.
    LD   DE,100                    ; Then the hundreds.
    CALL .DIGIT                    ; The rest is below 100.
    LD   DE,10                     ; Then the tens.
    CALL .DIGIT                    ; The units are left in L.
    LD   A,L                       ; A is the units digit, below ten.
    ADD  A,'0'                     ; Make it a character.
    JR   SH_CHAR                   ; Always print it, so zero prints as 0.

;@ROUTINE IN B,DE,HL OUT B,HL CLOBBERS A,IX,IY,CARRY,ZERO,SIGN,PARITY,HALFCARRY
; Print the digit of HL for the power of ten DE, unless it is a leading zero,
; and leave the remainder in HL. B becomes nonzero once a digit is printed.

.DIGIT:                        ; HL is below ten times DE.
    LD   A,'0'-1                   ; A counts the powers that fit, as a digit character.
.COUNT:                        ; A is one less than the digit so far.
    INC  A                         ; Count one more power.
    OR   A                         ; Clear carry; A is a digit character, never zero.
    SBC  HL,DE                     ; Take one power away.
    JR   NC,.COUNT                 ; It fitted: try another.
    ADD  HL,DE                     ; It did not: put it back, leaving the remainder.
    CP   '0'                       ; Is the digit zero?
    JR   NZ,.PRINT                 ; A nonzero digit always prints.
    INC  B                         ; Test B for zero without changing it.
    DEC  B                         ; Zero means no digit has been printed.
    RET  Z                         ; This zero is leading, so skip it.
.PRINT:                        ; A is a digit to print.
    LD   B,1                       ; From now on zeros print; fall into SH_CHAR.

;@ROUTINE IN A CLOBBERS IX,IY
; Print A on the console, keeping AF, BC, DE and HL across the BDOS call.

SH_CHAR:                       ; A is the character.
    PUSH AF                        ; BDOS returns its status in A.
    PUSH BC                        ; It may change any other register.
    PUSH DE                        ; Keep DE for the callers.
    PUSH HL                        ; Keep HL for the callers.
    LD   E,A                       ; BDOS takes the character in E.
    LD   C,SH_COUT                 ; Console output.
    CALL SH_BDOS                   ; Print it.
    POP  HL                        ; Restore the caller's HL.
    POP  DE                        ; Restore DE.
    POP  BC                        ; Restore BC.
    POP  AF                        ; Restore A and the flags.
    RET                            ; The character is printed.

; ---- output ----------------------------------------------------------------

;@ROUTINE OUT CARRY CLOBBERS ZERO,SIGN,PARITY,HALFCARRY
; The forked compiler's output sinks. EM_BYTE, EM_FIXJR and EM_FIXW call
; PUB_BYTE, PUB_FIXB and PUB_FIXW for each placed byte and patch, and TARGET
; calls the rest. Placed output is discarded until blob output replaces it
; (native compiler plan, 65.4): every call succeeds, carry clear, A kept.

PUB_OPEN:                      ; Open a generation for the descriptor at IX.
PUB_BYTE:                      ; Place byte A at address HL in bank C.
PUB_FIXB:                      ; Patch byte A at address HL in bank C.
PUB_FIXW:                      ; Patch word DE at address HL in bank C.
PUB_RT:                        ; Place the BC-byte runtime of identity DE at HL.
PUB_INIT:                      ; Place the initialized vectors and state at HL.
PUB_FLAT:                      ; Accept the map of single-bank output at IX.
PUB_BANK:                      ; Banked output's tables; SH_DESC has only one bank.
PUB_CMT:                       ; Commit the generation.
PUB_UNDO:                      ; Abandon the generation after a failure.
    OR   A                         ; Clear carry: the sink reports success.
    RET                            ; A is unchanged for callers that test it.

; ---- data -------------------------------------------------------------------

SH_DESC:                       ; The forked compiler's target (TG_D*), until 65.4.
    DW   RT_IDENT                  ; TG_DRT: the runtime identity TG_OPEN requires.
    DW   $8000,$1000               ; TG_DIMG, TG_DICAP: a 4K image at $8000.
    DW   $4000,$1000               ; TG_DRAM, TG_DRCAP: 4K writable at $4000, apart from the image.
    DB   1                         ; TG_DFLAG: TG_FSP, the program selects its own stack.
    DB   1,0                       ; TG_DBCNT, TG_DEB: one bank, the entry in bank 0.
    DW   .BANKS                    ; TG_DPART: the bank of each part.
.BANKS:                        ; One entry for each of SRC_CAP parts.
    DB   0,0,0,0,0,0,0,0           ; Every part is in bank 0, the only bank.
SH_VALID:                      ; The marks a CP/M name may contain (services §4.1).
    DB   "!#$%&'()-@^_`{}~"        ; Sixteen, the count .CHAR's CPIR searches.
SH_TYPE:                       ; The type of a part that names none.
    DB   "BSI"                     ; Copied into the FCB's type field.
SH_JOB:                        ; The SUBMIT job file a failed build deletes.
    DB   1,"$$$     SUB"           ; Drive A:, then name and type as an FCB holds them.
SH_EMSG:                       ; Begins a diagnostic's message.
    DB   "Error ",0                ; The forked compiler's number follows.
SH_FMSG:                       ; Follows the name of a missing part.
    DB   " not found",0            ; The part's file is not on its drive.
SH_RMSG:                       ; Follows the name of a part CP/M could not read.
    DB   " read error",0           ; A disk error, not the end of the file.
SH_PMSG:                       ; A ninth part was named.
    DB   "More than 8 source parts",0 ; 8 is SRC_CAP.
SH_LMSG:                       ; The parts would reach the stack's reserve.
    DB   "Source too large",0      ; The source's end may not pass SH_LIMIT.
SH_UMSG:                       ; Any malformed command line.
    DB   "Usage: BASIE PART[,PART...] [OPTIONS]",0 ; The command's grammar.

SH_CEND:                       ; End of the shell, which the build measures from SH_CBEG.
MM_END:                        ; End of BASIE.COM; the build checks it does not pass MM_WBASE.
