;==========================================================================
;  CP/M shell
;==========================================================================
;
;  The CP/M shell of BASIE.COM (toolchain §2, §4, §5). The CCP loads the
;  image at $0100, whose first instruction jumps to SH_START. The shell
;  runs the build through its overlays (OVERLAY.ASM): COMMAND reads the
;  command line; START checks the blob library, loads each source part
;  named on it and every part they include into memory above the
;  compiler's workspace, chooses the compilation stamp, opens the
;  intermediate streams NAME.$DR, $BY, $LN and $NM on the spool drive and
;  with the first part's name (toolchain §3.2) and names each part in the
;  line stream; NAMES holds the predeclared names while PR_BUILD compiles
;  the parts into blobs; then CHAIN closes the streams and runs BLINK.COM
;  to link them, unless option C compiles only; option X runs BLINK at
;  once. A diagnostic is printed by the DIAG overlay, by the reference's
;  number with its text from BASIE.MSG. The stack and the source occupy
;  the CCP's memory, so every exit is a warm boot through $0000 or the
;  chain to BLINK.
;
;  Principal entries:
;    SH_START  the program entry, reached from the jump at $0100
;    SH_FAIL   print a message and fail
;    SH_OVER   report one of this compiler's capacities and fail
;    MS_FAIL   report diagnostic HL through the DIAG overlay and fail
;    OUT_FAIL  the output streams' failure: a full disk or directory
;
;  Failure: a malformed command line, an unusable library, a missing part,
;  more than CL_PCAP parts named or 255 in all, source too large for
;  memory, a full disk or a compiler diagnostic prints one line, sets the
;  CP/M 3 return code
;  (toolchain §5.4: $FF13 for a disk that filled or failed, $FF11 for
;  anything else) and then deletes A:$$$.SUB, which stops a running SUBMIT
;  job under CP/M 2.2. A compiler diagnostic or a full disk, which come
;  once the streams are open, also deletes the four streams, unless option
;  K keeps them (toolchain §6.2).
;
;  Memory: SP starts at the BDOS entry. The parts are packed upward from
;  MM_SRC, each ending at its first $1A, and the part table (SOURCE.ASM)
;  grows down to meet them from MM_STACK bytes below the BDOS entry, which
;  leaves that much for the stack. The workspace, SH_WBEG to SH_WEND below
;  MM_BLOB, holds the load state, one FCB, the names of the parts the
;  command line names, the part name being written, the streams' drive
;  and name, and the options (COMMAND.ASM).
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
SH_DISK EQU  25                ; BDOS current disk: A is the drive, 0 for A:.
SH_READ EQU  20                ; BDOS read sequential: A is nonzero at end of file.
SH_DMA EQU  26                 ; BDOS set DMA address: DE receives the next record.
SH_RCODE EQU  108              ; BDOS set return code (CP/M 3): DE is the code.
SH_FLEN EQU  36                ; FCB bytes, through the random record number.
SH_NLEN EQU  11                ; FCB name and type bytes, padded with spaces.
SH_SLOT EQU  12                ; A saved part name: the FCB's drive, name and type.
SH_KEEP EQU  $40               ; BL_FLAGS bit: option K, keep the streams on failure.
CL_PCAP EQU  8                 ; Parts the command line may name; DG_PARTS beyond.
SH_ICAP EQU  16                ; Includes open at once while loading; DG_INEST beyond.
SH_RSRC EQU  $11               ; Return code's low byte: a source error, $FF11.
SH_RDISK EQU  $13              ; Return code's low byte: a disk error, $FF13.
SH_NIO EQU  222                ; L-IO: a part that can't be read.
SH_NMISS EQU  225              ; L-MISSING: a file not found.

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
CL_NBAD EQU  224               ; L-COMMAND: a bad or repeated option.

; The shell's workspace, after the compiler's and below the blob writer's.
SH_LIMIT EQU  SH_WBEG          ; Word: the source must end at or below here.
SH_LOADP EQU  SH_LIMIT+2       ; Word: the next free source byte, the load point.
SH_PBEG EQU  SH_LOADP+2        ; Word: the start of the part being loaded.
SH_PCNT EQU  SH_PBEG+2         ; Byte: parts named on the command line.
SH_PIDX EQU  SH_PCNT+1         ; Byte: the index of the command line's part.
SH_LCNT EQU  SH_PIDX+1         ; Byte: the parts loaded, the part table's entries.
SH_SNUM EQU  SH_LCNT+1         ; Byte: the next part's number in the stream.
SH_DEPTH EQU  SH_SNUM+1        ; Byte: includes open while the parts load.
SH_CURDR EQU  SH_DEPTH+1       ; Byte: the current drive, 1 for A:.
SH_CUR EQU  SH_CURDR+1         ; Word: the table entry of the part being loaded.
SH_IPOS EQU  SH_CUR+2          ; Word: the offset of the include being read.
SH_FCB EQU  SH_IPOS+2          ; SH_FLEN bytes: the FCB of every BDOS file call.
SH_NAMES EQU  SH_FCB+SH_FLEN   ; CL_PCAP slots of SH_SLOT bytes, by index.
SH_TEXT EQU  SH_NAMES+CL_PCAP*SH_SLOT ; 15 bytes: a part's name as D:NAME.TYP.
SH_SNAME EQU  SH_TEXT+15       ; 9 bytes: the streams' drive and name.
SH_RLOW EQU  SH_SNAME+9        ; Byte: a failure's return code, low byte.
CL_POS EQU  SH_RLOW+1          ; Word: the option being parsed (COMMAND.ASM).
CL_TPOS EQU  CL_POS+2          ; Word: where option T began.
CL_LIB EQU  CL_TPOS+2          ; 8 bytes: the library's name, option P's.
CL_SEEN EQU  CL_LIB+8          ; CL_NOPT bytes: each option given, or zero.
DG_ARG1 EQU  CL_SEEN+CL_NOPT   ; Word: a diagnostic's argument 1, or 0 (MESSAGE.ASM).
DG_ARG2 EQU  DG_ARG1+2         ; Word: its argument 2, or 0.
MS_REC EQU  DG_ARG2+2          ; Byte: the record of BASIE.MSG in MS_BUF.
OV_CUR EQU  MS_REC+1           ; Byte: the overlay loaded last, $FF for none (OVERLAY.ASM).
OV_FCB EQU  OV_CUR+1           ; SH_FLEN bytes: BASIE.OVL's FCB, open once loaded.
OV_DIR EQU  OV_FCB+SH_FLEN     ; OV_DCAP entries of four: each overlay's address, records.
OV_DCAP EQU  8                 ; Overlays BASIE.OVL may describe.
SH_WEND EQU  OV_DIR+4*OV_DCAP  ; The build checks this is at or below MM_BLOB.

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
    LD   HL,0                      ; Zero:
    LD   (DG_ARG1),HL              ; no diagnostic has
    LD   (DG_ARG2),HL              ; an argument yet.
    XOR  A                         ; No overlay is loaded,
    LD   (OV_FCB+1),A              ; nor BASIE.OVL opened,
    DEC  A                         ; until
    LD   (OV_CUR),A                ; the first is needed.
    INC  A                         ; The command line's: OV_CMD, zero.
    CALL OV_LOAD                   ; Load it,
    CALL OV_AREA                   ; and read the parts and options (CL_READ).
    LD   HL,OV_AREA                ; CH_RUN, if
    LD   A,(CL_SEEN+CL_IC)         ; option X
    CP   'X'                       ; links only:
    JR   Z,SH_CHAIN                ; run BLINK, compiling nothing.
    LD   A,OV_START                ; The start of a build:
    CALL OV_LOAD                   ; check the library
    CALL OV_AREA                   ; (LB_FIRST);
    LD   A,OV_PARTS                ; load the parts
    CALL OV_LOAD                   ; and their includes
    CALL OV_AREA                   ; (SH_BEGIN),
    JR   C,SH_DIAG                 ; a diagnostic of theirs printed;
    LD   A,OV_START                ; then choose the stamp,
    CALL OV_LOAD                   ; open the streams and name the parts
    CALL OV_AREA+3                 ; (LB_OPEN).
    LD   A,OV_NAMES                ; The predeclared names
    CALL OV_LOAD                   ; are in the overlay area for the compilation.
    CALL PR_BUILD                  ; Compile; carry reports a diagnostic in DG_CODE.
    JR   C,SH_DIAG                 ; Print it and fail.
    LD   HL,OV_AREA+3              ; The chain's overlay closes the streams and runs
                                   ; BLINK unless C (CH_DONE): fall into SH_CHAIN.

;@ROUTINE IN HL NORETURN
; Run the CHAIN overlay's entry HL: CH_RUN, which runs BLINK.COM with the
; build's tail, or CH_DONE, which closes the streams first.

SH_CHAIN:                      ; HL is the entry.
    PUSH HL                        ; Return to it
    LD   A,OV_CHAIN                ; once the chain's overlay
    JP   OV_LOAD                   ; is loaded.

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

; ---- diagnostics and failure ------------------------------------------------

;@ROUTINE NORETURN
; Print the diagnostic PR_BUILD left in DG_PART, DG_POS and DG_CODE (the
; DIAG overlay's MS_SHOWD), delete the streams and fail.

SH_DIAG:                       ; Reached on carry from PR_BUILD.
    CALL SH_TELL                   ; Print the diagnostic.
    CALL SH_SCRUB                  ; Delete the streams.
    JR   SH_QUIT                   ; End the line and fail.

;@ROUTINE IN A NORETURN
; Report the capacity A (DG_CAP's family) as Error 190 with its name, and
; fail. The streams are not yet open.

SH_OVER:                       ; A is the limit's code.
    LD   (DG_CODE),A               ; MS_SHOWD maps it.
    XOR  A                         ; It names
    LD   (DG_PART),A               ; no part.
    CALL SH_TELL                   ; Print it.
    JR   SH_QUIT                   ; End the line and fail.

;@ROUTINE CLOBBERS A,BC,DE,HL,IX,IY,CARRY,ZERO,SIGN,PARITY,HALFCARRY
; Print the compiler's diagnostic DG_CODE, in DG_PART at DG_POS, through
; the DIAG overlay (MS_SHOWD), its line not yet ended.

SH_TELL:                       ; DG_CODE, DG_PART and DG_POS are set.
    LD   A,OV_DIAG                 ; The diagnostics' overlay,
    CALL OV_LOAD                   ; loaded,
    JP   OV_AREA+3                 ; prints it (MS_SHOWD); return.

;@ROUTINE IN HL NORETURN
; Print "Error N: text" for diagnostic HL, its arguments at DG_ARG1 and
; DG_ARG2, through the DIAG overlay (MS_SHOWE), and fail. The arguments
; must lie outside the overlay area, which the DIAG overlay replaces.

MS_FAIL:                       ; HL is the number.
    PUSH HL                        ; Keep it.
    LD   A,OV_DIAG                 ; The diagnostics' overlay,
    CALL OV_LOAD                   ; loaded,
    POP  HL                        ; with the number,
    CALL OV_AREA                   ; prints it (MS_SHOWE).
    JR   SH_QUIT                   ; End the line and fail.

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

;@ROUTINE IN HL CLOBBERS A,HL,IX,IY,CARRY,ZERO,SIGN,PARITY,HALFCARRY
; Print the zero-terminated text at HL.

SH_PRINT:                      ; HL is in the text.
    LD   A,(HL)                    ; A is the next character.
    OR   A                         ; Is it the terminator?
    RET  Z                         ; Yes: the text is printed.
    CALL SH_CHAR                   ; No: print it.
    INC  HL                        ; Move to the next character.
    JR   SH_PRINT                  ; Print the rest.

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
    JR   SH_FAIL                   ; Print it and fail.

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
SH_DMSG:                       ; A stream could not be written.
    DB   "Disk full",0             ; Or the directory: either ends the build.
