%INCLUDE "HEAD.ASM"
%INCLUDE "CPM.ASM"
%INCLUDE "FILE.ASM"
%INCLUDE "CRC.ASM"
%INCLUDE "MSG.ASM"
%INCLUDE "TAIL.ASM"
%INCLUDE "PHASEA.ASM"
%INCLUDE "CHECKS.ASM"
%INCLUDE "PHASEB.ASM"
%INCLUDE "PHASEC.ASM"
%INCLUDE "PHASED.ASM"
%INCLUDE "LINES.ASM"
%INCLUDE "PUBLISH.ASM"
%INCLUDE "REPORT.ASM"
%INCLUDE "PHASEE.ASM"

;==========================================================================
;  BLINK: the driver
;==========================================================================
;
;  BLINK links a compiled Basie program (docs/linker.md; toolchain §5):
;
;      BLINK NAME [options]
;
;  It reads the command tail, opens the blob library and checks its header
;  and, with option V, its whole-file CRC, then runs the phases in turn: A
;  reads and checks the directories, B marks what is live, C places it, D
;  writes the image and the line table, publication renames them into
;  place, and E writes the map and the symbol file.
;
;  The modules are included above in image order, since ATOM assembles each
;  included file before its includer; this driver comes last, and FREEMEM,
;  at its end, is where the tables begin.
;
;  Principal entries:
;    LK_START  the program entry, reached from the jump at $0100
;    LK_FAIL   end a failed link with RC_LINK, deleting what it made
;    LIB_ARG   make the library's name argument 1 of a diagnostic
;
;  Failure: every diagnostic that ends the link leaves through LK_FAIL,
;  which deletes the new outputs and the intermediates once linking has
;  begun (toolchain §6.2), and returns RC_LINK; a disk failure returns
;  RC_DISK. The stack starts at the BDOS entry, over the CCP, so every exit
;  is a warm boot.

LIB_FD:                        ; The FD that reads the library, NAME.BRL.
    DS   FD_SIZE                   ; Kept on its directory for the walks.
LIB_TYPE:                      ; The library's type.
    DB   "BRL"                     ; Three characters.
LIB_TEXT:                      ; The library's name as text, for messages.
    DS   13                        ; Written by LIB_ARG.
LIB_LEN:                       ; The library's length, from its header.
    DS   3                         ; 24 bits, for LIB_CHK.

;@ROUTINE NORETURN
; Parse the tail, open and check the library, run the phases and end the
; run with RC_OK.

LK_START:                      ; Entered from the jump at $0100.
    LD   HL,(CPM_TOP)              ; The BDOS entry, the top of memory.
    LD   SP,HL                     ; The stack grows down from there, over the CCP.
    CALL CMD_READ                  ; Parse the tail; carry after a diagnostic.
    JR   C,LK_FAIL                 ; A malformed tail.
    OR   A                         ; A = 0: an empty tail.
    JR   NZ,.NAMED                 ; A name was given.
    LD   HL,223                    ; L-USAGE.
    CALL DG_ERROR                  ; Report it.
    JR   LK_FAIL                   ; End the run.
.NAMED:                        ; The tail parsed.
    LD   A,1                       ; From here a failure cleans up (toolchain §6.2).
    LD   (LK_BUSY),A               ; LK_FAIL then deletes what the link made.
    CALL LIB_OPEN                  ; Open the library; carry after a diagnostic.
    JR   C,LK_FAIL                 ; L-MISSING.
    CALL LIB_READ                  ; Read and check its header.
    JR   C,LK_FAIL                 ; L-FORMAT or L-TRUNCATED.
    LD   A,(OP_FLAGS)              ; Option V:
    AND  OF_V                      ; check the whole file's CRC.
    JR   Z,.DONE                   ; Not given.
    CALL LIB_CHK                   ; Check it; carry after a diagnostic.
    JR   C,LK_FAIL                 ; L-TRUNCATED.
.DONE:                         ; The library is sound.
    CALL LIB_ARG                   ; The library's name, for messages.
    CALL PA_RUN                    ; Phase A: read and check the directories,
    CALL NM_CHECK                  ; and the names, for options M and Y.
    CALL PB_RUN                    ; Phase B: mark what is live.
    LD   A,(OP_EXTRA)              ; Option W:
    AND  OX_W                      ; dump the tables,
    CALL NZ,TB_WRITE               ; for testing.
    CALL PC_RUN                    ; Phase C: place.
    CALL PD_RUN                    ; Phase D: write the image and line table.
    CALL PUB_RUN                   ; Publish them.
    CALL PE_RUN                    ; Phase E: the map and the symbol file.
    CALL PUB_TIDY                  ; Delete the intermediates, unless K.
    LD   DE,RC_OK                  ; Success.
    JP   CPM_EXIT                  ; End the run.

;@ROUTINE NORETURN
; End a failed link: once linking has begun, delete the new outputs and the
; intermediates; then end the run with RC_LINK.

LK_FAIL:                       ; A diagnostic has been printed.
    LD   A,(LK_BUSY)               ; Has linking begun?
    OR   A                         ; Not while parsing the tail.
    CALL NZ,PUB_UNDO               ; Delete what the link made.
    LD   DE,RC_LINK                ; A failed link's return code.
    JP   CPM_EXIT                  ; End the run.

LK_BUSY:                       ; Nonzero once linking has begun.
    DB   0                         ; Set after the tail parses.

;@ROUTINE OUT CARRY CLOBBERS A,BC,DE,HL,IX,ZERO,SIGN,PARITY,HALFCARRY
; Open NAME.BRL: on the drive option L gives, else the first part's drive,
; then A: (toolchain §5.3). Carry after a diagnostic.

LIB_OPEN:                      ; LIB_FILE is the library's name.
    LD   IX,LIB_FD                 ; The library's FD.
    LD   A,(LIB_DISK)              ; Option L's drive,
    OR   A                         ; if given,
    JR   NZ,.ONLY                  ; is the only place to look.
    LD   A,(CMD_DISK)              ; The first part's drive.
    CALL .TRY                      ; Open it there.
    RET  NC                        ; Found.
    LD   A,1                       ; Then A:.
.ONLY:                         ; A is the last drive to try.
    CALL .TRY                      ; Open it there.
    RET  NC                        ; Found.
    CALL LIB_ARG                   ; The library's name is argument 1.
    LD   HL,225                    ; L-MISSING.
    CALL DG_ERROR                  ; Report it.
    SCF                            ; Carry: not found.
    RET                            ; To LK_START.

;@ROUTINE IN A,IX OUT CARRY CLOBBERS A,BC,DE,HL,ZERO,SIGN,PARITY,HALFCARRY
; Open the library on drive A. Carry if it isn't there.

.TRY:                          ; A is the drive.
    LD   HL,LIB_FILE               ; The library's name,
    LD   DE,LIB_TYPE               ; type BRL.
    CALL FIL_INIT                  ; Set up the FCB.
    JP   FIL_OPEN                  ; Open it; carry if it doesn't exist.

;@ROUTINE IN IX OUT CARRY CLOBBERS A,B,DE,HL,ZERO,SIGN,PARITY,HALFCARRY
; Read the library's header into LIB_HEAD and check its magic and version,
; keeping its length in LIB_LEN. Carry after a diagnostic.

LIB_READ:                      ; IX is the library, just opened.
    LD   HL,LIB_HEAD               ; The header and the profile block,
    LD   B,64                      ; 64 bytes.
.READ:                         ; HL walks LIB_HEAD.
    CALL FIL_GETB                  ; The next byte; carry at the end.
    JR   C,.SHORT                  ; Too short for a header.
    LD   (HL),A                    ; Store it.
    INC  HL                        ; The next place.
    DJNZ .READ                     ; Until all 64 are read.
    LD   HL,LIB_HEAD               ; Compare the magic,
    LD   DE,.MAGIC                 ; BSIR,
    LD   B,4                       ; four bytes.
.CHECK:                        ; HL walks the header, DE the magic.
    LD   A,(DE)                    ; A magic byte.
    CP   (HL)                      ; Does the header match?
    JR   NZ,.BAD                   ; Not a library.
    INC  HL                        ; The next header byte.
    INC  DE                        ; The next magic byte.
    DJNZ .CHECK                    ; Until all four match.
    LD   A,(LIB_HEAD+4)            ; Version 1.0:
    CP   1                         ; major 1,
    JR   NZ,.BAD                   ; else unknown;
    LD   A,(LIB_HEAD+5)            ; minor
    OR   A                         ; 0,
    JR   NZ,.BAD                   ; else higher.
    LD   HL,(LIB_HEAD+28)          ; The file length,
    LD   (LIB_LEN),HL              ; its low word,
    LD   A,(LIB_HEAD+30)           ; and its third byte,
    LD   (LIB_LEN+2),A             ; for LIB_CHK.
    OR   A                         ; Clear carry.
    RET                            ; The header is sound.
.BAD:                          ; Bad magic or version.
    LD   HL,200                    ; L-FORMAT.
    JR   .SAY                      ; Report it.
.SHORT:                        ; The file ended in the header.
    LD   HL,214                    ; L-TRUNCATED.
.SAY:                          ; HL is the message.
    PUSH HL                        ; Keep it.
    CALL LIB_ARG                   ; The library's name is argument 1.
    POP  HL                        ; HL is the message.
    CALL DG_ERROR                  ; Report it.
    SCF                            ; Carry: the library can't be used.
    RET                            ; To LK_START.
.MAGIC:                        ; The library's magic.
    DB   "BSIR"                    ; Basie runtime library.

;@ROUTINE IN IX OUT CARRY CLOBBERS A,BC,DE,HL,ZERO,SIGN,PARITY,HALFCARRY
; Check the CRC of the library's first LIB_LEN - 2 bytes against its last
; two (object format §7.6). Carry after a diagnostic.

LIB_CHK:                       ; Option V.
    XOR  A                         ; From the file's
    LD   HL,0                      ; first byte.
    CALL FIL_SEEK                  ; Go there.
    JR   C,.BAD                    ; An empty file.
    CALL CRC_NEW                   ; Start the CRC.
    LD   HL,(LIB_LEN)              ; The length,
    LD   A,(LIB_LEN+2)             ; 24 bits,
    LD   C,A                       ; C:HL = the bytes to add,
    LD   DE,2                      ; less the two
    OR   A                         ; that hold
    SBC  HL,DE                     ; the CRC,
    JR   NC,.LOOP                  ; with the borrow
    DEC  C                         ; into C.
.LOOP:                         ; C:HL bytes remain.
    LD   A,H                       ; Is C:HL
    OR   L                         ; zero?
    OR   C                         ; Then the CRC is next.
    JR   Z,.STORED                 ; Compare it.
    CALL FIL_GETB                  ; The next byte; carry at the end.
    JR   C,.BAD                    ; The file is shorter than its header says.
    CALL CRC_ADD                   ; Add it to the CRC.
    LD   A,L                       ; Count it off C:HL:
    SUB  1                         ; the low byte,
    LD   L,A                       ; less one;
    JR   NC,.LOOP                  ; no borrow: go on.
    DEC  H                         ; Borrow from H;
    LD   A,H                       ; did H
    CP   $FF                       ; wrap?
    JR   NZ,.LOOP                  ; No: go on.
    DEC  C                         ; Borrow from C.
    JR   .LOOP                     ; Go on.
.STORED:                       ; The file is at its CRC.
    CALL FIL_GETW                  ; HL is the stored CRC.
    JR   C,.BAD                    ; The file ended.
    LD   DE,(CRC_VAL)              ; The computed CRC.
    OR   A                         ; Clear carry for the subtraction.
    SBC  HL,DE                     ; Equal?
    RET  Z                         ; The library is intact.
.BAD:                          ; Short, or a bad CRC.
    CALL LIB_ARG                   ; The library's name is argument 1.
    LD   HL,214                    ; L-TRUNCATED.
    CALL DG_ERROR                  ; Report it.
    SCF                            ; Carry: the library can't be used.
    RET                            ; To LK_START.

;@ROUTINE CLOBBERS A,BC,DE,HL,CARRY,ZERO,SIGN,PARITY,HALFCARRY
; Write the library's file name as text into LIB_TEXT and make it
; argument 1.

LIB_ARG:                       ; LIB_FILE is the library's name.
    LD   DE,LIB_TEXT               ; The text,
    LD   HL,LIB_FILE               ; from the name,
    LD   B,8                       ; at most eight characters.
.NAME:                         ; HL walks the name, DE the text.
    LD   A,(HL)                    ; The next character.
    CP   ' '                       ; Padding ends the name.
    JR   Z,.TYPE                   ; The type follows.
    LD   (DE),A                    ; Copy it.
    INC  HL                        ; The next character.
    INC  DE                        ; The next place.
    DJNZ .NAME                     ; Until eight are copied.
.TYPE:                         ; DE is after the name.
    LD   HL,.EXT                   ; ".BRL" and the zero,
    LD   BC,5                      ; five bytes,
    LDIR                           ; copied.
    LD   HL,LIB_TEXT               ; The text
    LD   (DG_ARG1),HL              ; is argument 1.
    RET                            ; Done.
.EXT:                          ; The library's type as text.
    DB   ".BRL",0                  ; With its terminator.

FREEMEM:                       ; The end of the image: the tables start here.
