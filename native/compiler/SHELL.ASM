;==========================================================================
;  CP/M shell
;==========================================================================
;
;  The CP/M shell of BASIE.COM (toolchain §2, §4, §5). The CCP loads the
;  image at $0100, whose first instruction jumps to SH_START. The shell
;  reads the command line (COMMAND.ASM), checks the blob library and
;  chooses the compilation stamp (LIBRARY.ASM), loads each source part
;  into memory above the compiler's workspace, opens the intermediate
;  streams NAME.$DR, $BY, $LN and $NM on the spool drive and with the first
;  part's name (toolchain §3.2), names each part in the line stream, and
;  hands the parts to PR_BUILD, which compiles them into blobs; it then
;  closes the streams and runs BLINK.COM to link them (CHAIN.ASM), unless
;  option C compiles only; option X runs BLINK at once. A diagnostic is
;  printed as NAME.BSI LINE:COLUMN Error N, with the forked compiler's
;  number, until the message file replaces it (step 66). The stack and the
;  source occupy the CCP's memory, so every exit is a warm boot through
;  $0000 or the chain to BLINK.
;
;  Principal entries:
;    SH_START  the program entry, reached from the jump at $0100
;    SH_USAGE  report a malformed command line and fail
;    SH_FAIL   print a message and fail
;    OUT_FAIL  the output streams' failure: a full disk or directory
;
;  Failure: a malformed command line, an unusable library, a missing part,
;  more than SRC_CAP parts, source too large for memory, a full disk or a
;  compiler diagnostic prints one line, sets the CP/M 3 return code
;  (toolchain §5.4: $FF13 for a disk that filled or failed, $FF11 for
;  anything else) and then deletes A:$$$.SUB, which stops a running SUBMIT
;  job under CP/M 2.2. A compiler diagnostic or a full disk, which come
;  once the streams are open, also deletes the four streams, unless option
;  K keeps them (toolchain §6.2).
;
;  Memory: SP starts at the BDOS entry. The parts are packed upward from
;  MM_SRC, each ending at its first $1A, and must stay MM_STACK bytes below
;  the BDOS entry, which leaves that much for the stack. The workspace,
;  SH_WBEG to SH_WEND below MM_BLOB, holds the load state, one FCB, the part
;  descriptors PR_BUILD reads (five bytes each: the part's 1-based id, its
;  start and its exclusive end), each part's 11-character CP/M name for
;  diagnostics and the line stream, the part name being written, the
;  streams' drive and name, and the options (COMMAND.ASM).
;
;  Registers: every BDOS call is taken to change every register, IX and IY
;  included. SH_CHAR saves AF, BC, DE and HL around its call.

MM_IEND:                       ; End of compiler immutable data (marker).
MM_REND:                       ; End of the compiler core (marker).
SH_CBEG:                       ; Start of the CP/M shell's code (marker).

SH_BDOS EQU  $0005             ; BDOS entry; the word at $0006 is the top of memory.
SH_TAIL EQU  $0080             ; Command tail: a length byte, then the text.
SH_COUT EQU  2                 ; BDOS console output: E is the character.
SH_OPEN EQU  15                ; BDOS open file: A is $FF when the file is absent.
SH_ERASE EQU  19               ; BDOS delete file: an absent file is only a status.
SH_READ EQU  20                ; BDOS read sequential: A is nonzero at end of file.
SH_DMA EQU  26                 ; BDOS set DMA address: DE receives the next record.
SH_RCODE EQU  108              ; BDOS set return code (CP/M 3): DE is the code.
SH_FLEN EQU  36                ; FCB bytes, through the random record number.
SH_NLEN EQU  11                ; FCB name and type bytes, padded with spaces.
SH_SLOT EQU  12                ; A saved part name: the FCB's drive, name and type.
SH_KEEP EQU  $40               ; BL_FLAGS bit: option K, keep the streams on failure.
SH_RSRC EQU  $11               ; Return code's low byte: a source error, $FF11.
SH_RDISK EQU  $13              ; Return code's low byte: a disk error, $FF13.

; The command line's options (COMMAND.ASM): each one's byte in CL_SEEN,
; and the kinds of value they take.
CL_IK EQU  0                   ; CL_SEEN byte of K: keep the intermediate files.
CL_IC EQU  1                   ; Of C, compile only, or X, link only.
CL_IM EQU  3                   ; Of M: the map.
CL_IY EQU  4                   ; Of Y: the symbol file.
CL_IN EQU  5                   ; Of N: no line stream or line table.
CL_IL EQU  11                  ; Of L: the library's drive.
CL_IS EQU  12                  ; Of S: the spool drive.
CL_IT EQU  15                  ; Of T: trap lookup.
CL_ISTK EQU  16                ; Of STACK.
CL_NOPT EQU  17                ; Bytes in CL_SEEN.
CL_KDRV EQU  1                 ; Option kind: a drive, L= or S=.
CL_KLIB EQU  2                 ; Option kind: a library's name, P=.
CL_KOUT EQU  3                 ; Option kind: an output file, O=.
CL_KNUM EQU  4                 ; Option kind: a count of 1 to 255, F=.
CL_KHEX EQU  5                 ; Option kind: an address, T=.

; The shell's workspace, after the compiler's and below the blob writer's.
SH_LIMIT EQU  SH_WBEG          ; Word: the source must end at or below here.
SH_LOADP EQU  SH_LIMIT+2       ; Word: the next free source byte, the load point.
SH_PBEG EQU  SH_LOADP+2        ; Word: the start of the part being loaded.
SH_PCNT EQU  SH_PBEG+2         ; Byte: parts named on the command line.
SH_PIDX EQU  SH_PCNT+1         ; Byte: the index of the part being loaded.
SH_FCB EQU  SH_PIDX+1          ; SH_FLEN bytes: the FCB of every BDOS file call.
SH_PARTS EQU  SH_FCB+SH_FLEN   ; SRC_CAP descriptors of 5 bytes: id, start, end.
SH_NAMES EQU  SH_PARTS+SRC_CAP*5 ; SRC_CAP slots of SH_SLOT bytes, by index.
SH_TEXT EQU  SH_NAMES+SRC_CAP*SH_SLOT ; 12 bytes: a part's name as NAME.TYP.
SH_SNAME EQU  SH_TEXT+12       ; 9 bytes: the streams' drive and name.
SH_RLOW EQU  SH_SNAME+9        ; Byte: a failure's return code, low byte.
CL_POS EQU  SH_RLOW+1          ; Word: the option being parsed (COMMAND.ASM).
CL_TPOS EQU  CL_POS+2          ; Word: where option T began.
CL_LIB EQU  CL_TPOS+2          ; 8 bytes: the library's name, option P's.
CL_SEEN EQU  CL_LIB+8          ; CL_NOPT bytes: each option given, or zero.
SH_WEND EQU  CL_SEEN+CL_NOPT   ; The build checks this is at or below MM_BLOB.

;@ROUTINE NORETURN
; Read the command line, check the library, load the parts it names,
; compile them and warm boot, after reporting a diagnostic if there is one.

SH_START:                      ; Entered from the jump at $0100.
    LD   HL,(SH_BDOS+1)            ; HL is the BDOS entry, the top of memory.
    LD   SP,HL                     ; The stack grows down from there, over the CCP.
    LD   DE,-MM_STACK              ; Keep MM_STACK bytes below it for the stack.
    ADD  HL,DE                     ; HL is the first byte the source may not use.
    LD   (SH_LIMIT),HL             ; Each record read is checked against it.
    LD   HL,MM_SRC                 ; The first part loads at the base of the source.
    LD   (SH_LOADP),HL             ; Start the load point there.
    LD   A,SH_RSRC                 ; A failure is a source error
    LD   (SH_RLOW),A               ; unless a disk fails.
    CALL CL_READ                   ; The parts and options; errors do not return.
    LD   A,(CL_SEEN+CL_IT)         ; Option T, trap lookup,
    OR   A                         ; is not yet
    JP   NZ,SH_TRAP                ; available.
    LD   A,(CL_SEEN+CL_IC)         ; Option X
    CP   'X'                       ; links only:
    JP   Z,CH_RUN                  ; run BLINK, compiling nothing.
    CALL LB_CHECK                  ; The library must suit the compiler.
    XOR  A                         ; Load the parts in order,
.LOADS:                        ; A is the next one's index.
    LD   (SH_PIDX),A               ; It is being loaded.
    CALL SH_LOAD                   ; Load it and add its descriptor.
    LD   A,(SH_PIDX)               ; The next part.
    INC  A                         ; Its index.
    LD   HL,SH_PCNT                ; Is there one?
    CP   (HL)                      ; The count ends them.
    JR   C,.LOADS                  ; Load it.
    CALL LB_STAMP                  ; Choose the compilation stamp.
    LD   C,BL_LNOUT                ; By default a line stream and no names.
    LD   A,(CL_SEEN+CL_IN)         ; Option N:
    OR   A                         ; no line stream.
    JR   Z,.LINES                  ; Not given.
    LD   C,0                       ; None.
.LINES:                        ; C holds the line stream's flag.
    LD   HL,CL_SEEN+CL_IM          ; Option M
    LD   A,(CL_SEEN+CL_IY)         ; or Y
    OR   (HL)                      ; wants
    JR   Z,.NAMES                  ; the name stream.
    SET  1,C                       ; Set BL_NMOUT.
.NAMES:                        ; C holds the stream flags.
    LD   A,(CL_SEEN+CL_IK)         ; Option K:
    OR   A                         ; keep the streams
    JR   Z,.KEPT                   ; after a failure.
    SET  6,C                       ; Set SH_KEEP.
.KEPT:                         ; C is complete.
    LD   A,C                       ; The streams the options want.
    LD   HL,SH_HEAD                ; The directory's header,
    LD   DE,SH_SNAME               ; and the streams' drive and name.
    CALL BL_OPEN                   ; Open the streams.
    XOR  A                         ; Name each part in the line stream,
.PARTS:                        ; A is the next part's index.
    PUSH AF                        ; Keep it.
    CALL SH_TYPED                  ; HL is its name as NAME.TYP, B the length.
    POP  AF                        ; A is the index.
    PUSH AF                        ; Keep it.
    CALL BL_PART                   ; Write its part record.
    POP  AF                        ; The index again.
    INC  A                         ; The next part.
    LD   HL,SH_PCNT                ; Is there one?
    CP   (HL)                      ; The count ends them.
    JR   C,.PARTS                  ; Name it.
    LD   HL,SH_PARTS               ; PR_BUILD takes the count in A, descriptors at HL.
    CALL PR_BUILD                  ; Compile; carry reports a diagnostic in DG_CODE.
    JP   C,SH_DIAG                 ; Print it and fail.
    CALL BL_CLOSE                  ; Write the trailers and close the streams.
    LD   A,(CL_SEEN+CL_IC)         ; Option C
    CP   'C'                       ; compiles only: success,
    JP   Z,0                       ; a warm boot, and a SUBMIT job runs on.
    JP   CH_RUN                    ; Otherwise BLINK links the streams.

;@ROUTINE CLOBBERS A,BC,DE,HL,IX,IY,CARRY,ZERO,SIGN,PARITY,HALFCARRY
; Load part SH_PIDX, whose name CL_READ saved, after the parts already
; loaded: end it at its first $1A and append its descriptor. Errors leave
; by SH_MISS, SH_RERR and SH_LARGE.

SH_LOAD:                       ; SH_PIDX is the part's index.
    CALL SH_BLANK                  ; A clear FCB.
    LD   A,(SH_PIDX)               ; The part's saved name:
    CALL SH_PNAME                  ; HL is its drive, name and type.
    LD   DE,SH_FCB                 ; The FCB takes them.
    LD   BC,SH_SLOT                ; Twelve bytes.
    LDIR                           ; The FCB names the part.
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
    LD   A,(SH_PIDX)               ; Build the descriptor: id, start, end.
    LD   L,A                       ; L keeps this part's index.
    INC  A                         ; A is its 1-based id, which DG_PART reports.
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

;@ROUTINE IN A OUT B,HL CLOBBERS A,DE,CARRY,ZERO,SIGN,PARITY,HALFCARRY
; Spell the name of part A (0-based) as the reference compiler names a part
; in the line stream, NAME.TYP without padding or drive, at SH_TEXT: HL
; addresses it and B is its length.

SH_TYPED:                      ; A is a part index.
    CALL SH_PNAME                  ; HL is its saved drive, name and type.
    INC  HL                        ; Skip the drive.
    LD   DE,SH_TEXT                ; The spelling is built here.
    LD   B,8                       ; The name's eight characters,
    CALL .FIELD                    ; less their padding.
    LD   A,'.'                     ; A dot
    LD   (DE),A                    ; separates it
    INC  DE                        ; from the type.
    LD   B,3                       ; The type's three characters,
    CALL .FIELD                    ; less their padding.
    EX   DE,HL                     ; HL is the spelling's end.
    LD   DE,SH_TEXT                ; Its start.
    OR   A                         ; Clear carry.
    SBC  HL,DE                     ; HL is its length,
    LD   B,L                       ; at most twelve.
    EX   DE,HL                     ; HL is the spelling.
    RET                            ; B is its length.

;@ROUTINE IN B,DE,HL OUT DE,HL CLOBBERS A,B,CARRY,ZERO,SIGN,PARITY,HALFCARRY
; Copy the B characters at HL to DE, leaving out the spaces that pad them.

.FIELD:                        ; B characters remain at HL.
    LD   A,(HL)                    ; The next one.
    INC  HL                        ; HL moves on whether or not it is kept.
    CP   ' '                       ; Spaces are padding.
    JR   Z,.PAD                    ; Leave it out.
    LD   (DE),A                    ; Keep anything else.
    INC  DE                        ; Move on.
.PAD:                          ; The character is done.
    DJNZ .FIELD                    ; Until the field is copied.
    RET                            ; DE is after the copy.

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
    CALL SH_SHOW                   ; Print it as D:NAME.TYP.
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
    CALL SH_SCRUB                  ; Delete the streams.
    JR   SH_QUIT                   ; End the line and fail.

;@ROUTINE NORETURN
; Report that the part SH_LOAD failed to open is not on the disk, as
; D:NAME.TYP not found.

SH_MISS:                       ; SH_PIDX is the part.
    LD   DE,SH_FMSG                ; The text after the name.
    JR   SH_NAMED                  ; Print the name, then the text.

;@ROUTINE NORETURN
; Report a part that CP/M could not read, as D:NAME.TYP read error: a disk
; error.

SH_RERR:                       ; SH_LOAD had a read status other than 0 or 1.
    LD   A,SH_RDISK                ; A disk error's
    LD   (SH_RLOW),A               ; return code.
    LD   DE,SH_RMSG                ; The text after the name.

;@ROUTINE IN DE NORETURN
; Print the name of the part being loaded, then the text at DE, and fail.

SH_NAMED:                      ; DE is the message that follows the name.
    PUSH DE                        ; Keep it across the name.
    LD   A,(SH_PIDX)               ; The part being loaded.
    CALL SH_SHOW                   ; Print it as D:NAME.TYP.
    POP  HL                        ; HL is the message.
    JR   SH_FAIL                   ; Print it and fail.

;@ROUTINE NORETURN
; Report a part beyond the SRC_CAP the descriptor table holds.

SH_MANY:                       ; CL_PART found the table full.
    LD   HL,SH_PMSG                ; The too-many-parts message.
    JR   SH_FAIL                   ; Print it and fail.

;@ROUTINE NORETURN
; Report a part whose next record would cross SH_LIMIT.

SH_LARGE:                      ; SH_LOAD found no room for a record.
    LD   HL,SH_LMSG                ; The source-too-large message.
    JR   SH_FAIL                   ; Print it and fail.

;@ROUTINE NORETURN
; Report option T, trap lookup (toolchain §8), as not yet available.

SH_TRAP:                       ; CL_READ accepted it.
    LD   HL,SH_TMSG                ; Not yet available.
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
; End the message line, set the CP/M 3 return code (SH_RLOW, BDOS 108,
; which CP/M 2.2 ignores), delete A:$$$.SUB and warm boot. CP/M 2.2 has no
; return codes, so deleting the job file is how a failed build stops a
; running SUBMIT job (toolchain §5.4).

SH_QUIT:                       ; Every failure ends here, its message printed.
    LD   A,13                      ; A carriage return begins the line end.
    CALL SH_CHAR                   ; Print it.
    LD   A,10                      ; A line feed ends the message line.
    CALL SH_CHAR                   ; Print it.
    LD   A,(SH_RLOW)               ; The return code is $FF
    LD   E,A                       ; and the low byte
    LD   D,$FF                     ; for the failure.
    LD   C,SH_RCODE                ; Set it;
    CALL SH_BDOS                   ; CP/M 2.2 does nothing.
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

;@ROUTINE IN A CLOBBERS A,B,DE,HL,IX,IY,CARRY,ZERO,SIGN,PARITY,HALFCARRY
; Print the saved name of part A (0-based) as D:NAME.TYP, without padding,
; and without the drive when the part was on the current drive.

SH_SHOW:                       ; A is a part's index.
    PUSH AF                        ; Keep it for the name.
    CALL SH_PNAME                  ; HL is its saved drive, name and type.
    LD   A,(HL)                    ; A is the drive: 0 current, 1 for A:.
    OR   A                         ; Was a drive named?
    JR   Z,.NAME                   ; No: print the name alone.
    ADD  A,'A'-1                   ; Make the drive a letter.
    CALL SH_CHAR                   ; Print it.
    LD   A,':'                     ; Then the colon.
    CALL SH_CHAR                   ; Print it.
.NAME:                         ; The drive is printed if there was one.
    POP  AF                        ; A is the index.
    CALL SH_TYPED                  ; HL is NAME.TYP, B its length.
.CHARS:                        ; B characters remain at HL.
    LD   A,(HL)                    ; Print
    CALL SH_CHAR                   ; the next.
    INC  HL                        ; Move on.
    DJNZ .CHARS                    ; Until the name is printed.
    RET                            ; The caller prints what follows.

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

;@ROUTINE NORETURN
; The output streams' failure (OUT.ASM): the disk or its directory is full.
; Report it and fail.

OUT_FAIL:                      ; A stream could not be written or made.
    LD   A,SH_RDISK                ; A disk error's
    LD   (SH_RLOW),A               ; return code.
    CALL SH_SCRUB                  ; Delete the streams.
    LD   HL,SH_DMSG                ; The disk-full message.
    JP   SH_FAIL                   ; Print it and fail.

;@ROUTINE CLOBBERS A,BC,DE,HL,IX,IY,CARRY,ZERO,SIGN,PARITY,HALFCARRY
; Delete the four streams, NAME.$DR, $BY, $LN and $NM on the spool drive,
; after a failure, unless option K keeps them (toolchain §6.2). A stream
; never made is only a status from BDOS.

SH_SCRUB:                      ; The streams were opened by BL_OPEN.
    LD   A,(BL_FLAGS)              ; Did option K
    AND  SH_KEEP                   ; ask to keep them?
    RET  NZ                        ; Then they stay.
    LD   HL,SH_STYPE               ; The streams' types, two letters each.
    LD   B,4                       ; Four streams.
.LOOP:                         ; HL is the next type.
    PUSH BC                        ; Keep the count.
    CALL SH_BLANK                  ; A clear FCB; HL is kept.
    PUSH HL                        ; Keep the type.
    LD   HL,SH_SNAME               ; The streams' drive and name,
    LD   DE,SH_FCB                 ; into the FCB:
    LD   BC,9                      ; nine bytes.
    LDIR                           ; DE is the FCB's type.
    LD   A,'$'                     ; Each type begins with a dollar,
    LD   (DE),A                    ; then
    INC  DE                        ; its
    POP  HL                        ; two
    LDI                            ; letters.
    LDI                            ; HL is the next type.
    PUSH HL                        ; Keep it.
    LD   DE,SH_FCB                 ; DE is the FCB for BDOS.
    LD   C,SH_ERASE                ; Delete the stream;
    CALL SH_BDOS                   ; an absent one is only a status.
    POP  HL                        ; The next type.
    POP  BC                        ; The count.
    DJNZ .LOOP                     ; Until all four are deleted.
    RET                            ; The streams are gone.

; ---- data -------------------------------------------------------------------

SH_HEAD:                       ; The program directory's header (object format §4.1).
    DB   "BSIP",1,0                ; Magic, version 1.0.
    DW   0,0                       ; The stamp and the runtime (LIBRARY.ASM),
    DW   HP_VER,HP_KEY             ; the helper table compiled in,
    DW   0,$0400                   ; the profile (LIBRARY.ASM), the ordinal base.
    DB   0,0                       ; No flags; padding.
SH_STYPE:                      ; The streams' types after their dollar.
    DB   "DRBYLNNM"                ; $DR, $BY, $LN and $NM.
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
SH_DMSG:                       ; A stream could not be written.
    DB   "Disk full",0             ; Or the directory: either ends the build.
SH_LMSG:                       ; The parts would reach the stack's reserve.
    DB   "Source too large",0      ; The source's end may not pass SH_LIMIT.
SH_UMSG:                       ; Any malformed command line.
    DB   "Usage: BASIE PART[,PART...] [OPTIONS]",0 ; The command's grammar.
SH_TMSG:                       ; Option T.
    DB   "Trap lookup is not yet available",0 ; Toolchain §8, still to come.
