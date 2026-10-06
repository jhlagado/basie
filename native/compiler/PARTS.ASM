;==========================================================================
;  Source parts and streams
;==========================================================================
;
;  The loading of the source parts: the PARTS overlay of BASIE.OVL
;  (OVERLAY.ASM), with FILENAME.ASM and PARTNAME.ASM, which the shell runs
;  between the START overlay's library check and its streams (LIBRARY.ASM).
;  SH_BEGIN, at the overlay area's start, loads each part named on the
;  command line and every part it includes into memory above the
;  compiler's workspace and describes them in the part table (SOURCE.ASM).
;
;  Principal entry:
;    SH_BEGIN  load the parts, at OV_AREA
;
;  Includes (spec 4.3.2, D33). A part's include lines are read with the
;  tokenizer as the part is loaded: `include "NAME.TYP"`, then the line's
;  end, the name a CP/M name with its type and perhaps a drive (CL_NAME).
;  Without a drive the part is looked for on the including part's drive,
;  then on option L's, or A: without it (toolchain §5.3); with one, there.
;  A part already loaded is not loaded again, and one whose include lines
;  are still being read is a cycle. Each included part is loaded, its own
;  includes first, before the including part's next include line, and a
;  part takes its number in the stream once its includes are loaded, so
;  every part follows the parts it includes. A part's body, where its
;  compilation begins, follows its last include line. While an included
;  part loads, the tokenizer's state for the including one is kept on the
;  stack, at most SH_ICAP deep. An include after a declaration is not read
;  here: the compilation finds it (LL1.ASM).
;
;  Memory. Each part's bytes are loaded at SH_LOADP, upward, and its entry
;  in the part table is made at SH_LIMIT, which then moves down to it, so
;  the table and the bytes grow towards each other; a record must fit
;  below the table before it is read.
;
;  Failure. A part named on the command line that is not on the disk
;  (L-MISSING) or one CP/M can't read (L-IO), and source too large for
;  memory (capacity), do not return; each is printed by the DIAG overlay,
;  which replaces this one. A diagnostic of an include line or a token read
;  here, or the capacity of the parts or the includes, returns from
;  SH_BEGIN with carry set (DG_ISSUE unwinds to PR_SP), and the shell
;  prints it as it prints the compilation's. Each record is read into the
;  blob writer's buffer (BL_CODE), not yet in use, and copied below the
;  table, so the read that finds a part's end needs no room.

SH_STATE EQU  14               ; Bytes of the tokenizer's state, SRC_ID to TK_NEST.

;@ROUTINE OUT CARRY CLOBBERS A,BC,DE,HL,IX,IY,ZERO,SIGN,PARITY,HALFCARRY
; Load the parts the command line names and every part they include, and
; describe them in the part table. Carry reports a diagnostic in DG_CODE,
; DG_PART and DG_POS.

SH_BEGIN:                      ; At OV_AREA.
    LD   (PR_SP),SP                ; A diagnostic returns from here.
    LD   C,SH_DISK                 ; The current drive,
    CALL SH_BDOS                   ; 0 for A:,
    INC  A                         ; as an FCB
    LD   (SH_CURDR),A              ; names it.
    LD   HL,(SH_LIMIT)             ; The part table
    LD   (SRC_PTAB),HL             ; grows down from the limit.
    XOR  A                         ; No part
    LD   (SH_LCNT),A               ; is loaded,
    LD   (SH_SNUM),A               ; none numbered
    LD   (SH_DEPTH),A              ; and no include open;
    LD   (SRC_OWE),A               ; while the parts load,
    DEC  A                         ; each is the last
    LD   (SRC_PCNT),A              ; part of the stream
    DEC  A                         ; to the tokenizer
    LD   (SRC_NUM),A               ; (TK_ATEND).
    XOR  A                         ; The command line's parts in order,
.ROOTS:                        ; A is the next one's index.
    LD   (SH_PIDX),A               ; It is being loaded,
    CALL SH_PNAME                  ; HL its name,
    CALL SH_KNOWN                  ; unless an earlier part included it
    JR   C,.NEXT                   ; (spec 4.3.2, rule 4).
    CALL SH_BLANK                  ; A clear FCB.
    LD   A,(SH_PIDX)               ; The part's saved name:
    CALL SH_PNAME                  ; HL is its drive, name and type.
    PUSH HL                        ; Keep it.
    LD   DE,SH_FCB                 ; The FCB takes them.
    LD   BC,SH_SLOT                ; Twelve bytes.
    LDIR                           ; The FCB names the part.
    LD   DE,SH_FCB                 ; DE is the FCB for BDOS.
    LD   C,SH_OPEN                 ; Open the part for reading.
    CALL SH_BDOS                   ; A is $FF if the file is not on the disk.
    INC  A                         ; $FF becomes zero.
    POP  HL                        ; The name.
    JP   Z,SH_MISS                 ; Report the missing part by name.
    CALL SH_LOAD                   ; Load it and its includes.
.NEXT:                         ; The part is loaded.
    LD   A,(SH_PIDX)               ; The next part.
    INC  A                         ; Its index.
    LD   HL,SH_PCNT                ; Is there one?
    CP   (HL)                      ; The count ends them.
    JR   C,.ROOTS                  ; Load it.
    LD   A,(SH_LCNT)               ; The parts loaded
    LD   (SRC_PCNT),A              ; are the stream's.
    OR   A                         ; Carry clear: loaded.
    RET                            ; The part table is complete.

;@ROUTINE IN HL OUT CARRY,HL CLOBBERS A,BC,DE,ZERO,SIGN,PARITY,HALFCARRY
; Carry if a part loaded already has the drive and name at HL: HL then
; addresses its entry. The drive the current one is, 0 or its number,
; is the same drive.

SH_KNOWN:                      ; HL is a drive and name.
    LD   A,(SH_LCNT)               ; The parts loaded:
    LD   B,A                       ; B of them,
    OR   A                         ; if any.
    RET  Z                         ; None: carry is clear.
.LOOP:                         ; Entry B-1 is next.
    PUSH HL                        ; Keep the name.
    LD   A,B                       ; Its entry
    DEC  A                         ; is
    CALL SRC_PART                  ; HL; BC is kept.
    EX   DE,HL                     ; DE is the entry,
    POP  HL                        ; HL the name.
    PUSH BC                        ; Keep the count.
    PUSH HL                        ; Keep the name.
    PUSH DE                        ; Keep the entry.
    LD   A,(DE)                    ; Its drive
    CALL .DRIVE                    ; as a number,
    LD   C,A                       ; and
    LD   A,(HL)                    ; the name's,
    CALL .DRIVE                    ; are they
    CP   C                         ; the same?
    JR   NZ,.DIFFER                ; No.
    LD   B,SH_NLEN                 ; Then the name and type:
.BYTE:                         ; B bytes remain.
    INC  HL                        ; The next
    INC  DE                        ; of each.
    LD   A,(DE)                    ; Are they
    CP   (HL)                      ; the same?
    JR   NZ,.DIFFER                ; No.
    DJNZ .BYTE                     ; Until all are compared.
    POP  HL                        ; The entry,
    POP  DE                        ; the name,
    POP  BC                        ; the count.
    SCF                            ; It is the same part.
    RET                            ; HL is its entry.
.DIFFER:                       ; Not this part.
    POP  DE                        ; The entry,
    POP  HL                        ; the name,
    POP  BC                        ; the count.
    DJNZ .LOOP                     ; Try the one before.
    OR   A                         ; None: carry clear.
    RET                            ; Not loaded.
.DRIVE:                        ; A is an FCB's drive:
    OR   A                         ; a drive named
    RET  NZ                        ; is itself;
    LD   A,(SH_CURDR)              ; none is the current one.
    RET                            ; A is the drive's number.

;@ROUTINE IN HL CLOBBERS A,BC,DE,HL,IX,IY,CARRY,ZERO,SIGN,PARITY,HALFCARRY
; Load the part whose drive and name are at HL, open in SH_FCB, after the
; parts already loaded: make its entry, read it to its first $1A, read its
; include lines, loading each part they name that is not loaded yet, and
; give it the next number in the stream. Errors leave by SH_RERR and
; SH_LARGE, or as diagnostics (DG_ISSUE).

SH_LOAD:                       ; HL is the part's name.
    PUSH HL                        ; Keep it.
    LD   A,(SH_LCNT)               ; The new entry's index:
    INC  A                         ; the line stream numbers 255 parts
    LD   A,DG_PARTS                ; at most
    JP   Z,DG_ISSUE                ; (capacity, at the include).
    LD   A,(SH_LCNT)               ; Its entry
    CALL SRC_PART                  ; is HL,
    LD   (SH_CUR),HL               ; the part being loaded's;
    LD   (SH_LIMIT),HL             ; the source must stay below it,
    LD   DE,(SH_LOADP)             ; where it
    CALL .ROOM                     ; is already.
    JP   C,SH_LARGE                ; No room: the source is too large.
    LD   DE,(SH_CUR)               ; DE is the entry,
    POP  HL                        ; HL the name,
    LD   BC,SH_SLOT                ; twelve bytes,
    LDIR                           ; its first field; DE is PT_START.
    LD   HL,PT_NUM-PT_START        ; Its number
    ADD  HL,DE                     ; is
    LD   (HL),PT_OPEN              ; open until its includes are loaded.
    LD   HL,SH_LCNT                ; It is
    INC  (HL)                      ; counted.
    LD   HL,(SH_LOADP)             ; The part starts at the load point.
    LD   (SH_PBEG),HL              ; Keep its start for the trim and the entry.
    LD   DE,BL_CODE                ; Each record is read into a buffer,
    LD   C,SH_DMA                  ; the blob writer's, not yet in use,
    CALL SH_BDOS                   ; so the read that finds the end needs no room.
.RECORD:                       ; SH_LOADP is where the next record goes.
    LD   DE,SH_FCB                 ; DE is the open part's FCB.
    LD   C,SH_READ                 ; Read its next record.
    CALL SH_BDOS                   ; A is zero if a record was read.
    OR   A                         ; Was one read?
    JR   Z,.ADVANCE                ; Yes: move past it.
    DEC  A                         ; Status 1 is the end of the file.
    JR   Z,.LOADED                 ; The part is complete.
    JP   SH_RERR                   ; Any other status is a read error (toolchain §6.2).
.ADVANCE:                      ; A record was read into the buffer.
    LD   HL,(SH_LOADP)             ; It must end
    LD   DE,128                    ; below
    ADD  HL,DE                     ; the table
    EX   DE,HL                     ; at the load point,
    CALL .ROOM                     ; else
    JP   C,SH_LARGE                ; the source is too large.
    LD   HL,BL_CODE                ; It is
    LD   DE,(SH_LOADP)             ; copied
    LD   BC,128                    ; there,
    LDIR                           ; and the next
    LD   (SH_LOADP),DE             ; goes after it.
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
    LD   (SH_LOADP),HL             ; The next part loads here, over the $1A and padding.
    EX   DE,HL                     ; DE is the end.
    LD   HL,(SH_CUR)               ; The entry's
    LD   BC,PT_START               ; start
    ADD  HL,BC                     ; and end:
    LD   BC,(SH_PBEG)              ; BC is where the part began.
    LD   (HL),C                    ; Store the start's low byte.
    INC  HL                        ; Move to its high byte.
    LD   (HL),B                    ; Store the start's high byte.
    INC  HL                        ; The exclusive end follows.
    LD   (HL),E                    ; Store the end's low byte.
    INC  HL                        ; Move to its high byte.
    LD   (HL),D                    ; Store the end's high byte.
    LD   HL,(SH_PBEG)              ; Its bytes, [HL,DE),
    LD   A,(SH_LCNT)               ; with its index plus one,
    CALL SRC_INIT                  ; are the tokenizer's.
.LINE:                         ; A line begins: perhaps an include's.
    LD   HL,(SH_CUR)               ; Unless an include follows,
    LD   BC,PT_BODY                ; the part's body
    ADD  HL,BC                     ; begins here:
    LD   BC,(SRC_POS)              ; at this offset,
    LD   (HL),C                    ; low byte
    INC  HL                        ; and
    LD   (HL),B                    ; high byte,
    INC  HL                        ; and on
    LD   BC,(SRC_LINE)             ; this line,
    LD   (HL),C                    ; low byte
    INC  HL                        ; and
    LD   (HL),B                    ; high byte.
    CALL TK_NEXT                   ; The line's first token:
    CP   TK_INCL                   ; an include?
    JP   NZ,.DONE                  ; No: the include lines are over.
    LD   HL,(TK_POS)               ; Its offset,
    LD   (SH_IPOS),HL              ; where a missing name is reported.
    CALL TK_NEXT                   ; The name:
    CP   TK_TEXT                   ; a string literal,
    JR   NZ,.SYNTAX                ; else include-syntax at the include.
    LD   HL,(TK_POS)               ; Its offset,
    LD   (SH_IPOS),HL              ; where the rest are reported.
    LD   HL,(TK_PTR)               ; Its source
    LD   A,(TK_LEN)                ; and its length
    PUSH HL                        ; are kept
    PUSH AF                        ; across
    CALL TK_NEXT                   ; the next token,
    CP   TK_EOL                    ; which must end the line,
    LD   A,DG_INCL                 ; else include-syntax
    JP   NZ,DG_ISSUE               ; at it.
    POP  AF                        ; The literal's length
    POP  HL                        ; and source:
    CALL SH_INAME                  ; the FCB names the part.
    CALL SH_SEEK                   ; Find it.
    LD   A,DG_LOST                 ; Not found:
    JR   NC,.NAMED                 ; include-missing.
    LD   HL,SH_FCB                 ; Is it
    CALL SH_KNOWN                  ; loaded already?
    JR   NC,.NEW                   ; No: load it.
    LD   DE,PT_NUM                 ; Then its
    ADD  HL,DE                     ; number
    LD   A,(HL)                    ; is set,
    INC  A                         ; and the include does nothing,
    JP   NZ,.LINE                  ; unless its includes are being read:
    LD   A,DG_CYCLE                ; then it is a cycle.
.NAMED:                        ; A is the diagnostic, at the name, naming it.
    PUSH AF                        ; Keep it.
    LD   HL,SH_FCB+1               ; The part's name
    LD   DE,DG_ABUF                ; is spelled
    LD   (DG_ARG1),DE              ; as argument 1,
    CALL SH_NTYPE                  ; NAME.TYP,
    XOR  A                         ; and
    LD   (DE),A                    ; terminated.
    POP  AF                        ; The diagnostic
.REPORT:                       ; A is reported
    LD   HL,(SH_IPOS)              ; at the include's
    JP   DG_HERE                   ; name; no return.
.SYNTAX:                       ; No name after `include`:
    LD   A,DG_INCL                 ; include-syntax,
    JR   .REPORT                   ; at the include.
.NEW:                          ; The part is to be loaded.
    LD   HL,SH_DEPTH               ; One more
    LD   A,(HL)                    ; include
    INC  (HL)                      ; is open,
    CP   SH_ICAP                   ; within
    LD   A,DG_INEST                ; the capacity
    JR   NC,.REPORT                ; of includes open at once.
    LD   HL,(SH_CUR)               ; Keep this part's entry
    PUSH HL                        ; and
    LD   HL,-SH_STATE              ; the tokenizer's
    ADD  HL,SP                     ; state
    LD   SP,HL                     ; on the stack,
    EX   DE,HL                     ; copied
    LD   HL,PR_BASE                ; from
    LD   BC,SH_STATE               ; SRC_ID
    LDIR                           ; on.
    LD   HL,SH_FCB                 ; Load the part
    CALL SH_LOAD                   ; the include names.
    LD   HL,0                      ; The state
    ADD  HL,SP                     ; is
    LD   DE,PR_BASE                ; copied
    LD   BC,SH_STATE               ; back,
    LDIR                           ; and
    LD   SP,HL                     ; dropped.
    POP  HL                        ; This part's
    LD   (SH_CUR),HL               ; entry again.
    LD   HL,SH_DEPTH               ; One include
    DEC  (HL)                      ; fewer is open.
    JP   .LINE                     ; The next line.
.DONE:                         ; The include lines are over.
    LD   HL,(SH_CUR)               ; The part's
    LD   DE,PT_NUM                 ; number
    ADD  HL,DE                     ; in the stream
    LD   A,(SH_SNUM)               ; is
    LD   (HL),A                    ; the next;
    INC  A                         ; and the one after
    LD   (SH_SNUM),A               ; follows it.
    RET                            ; The part is loaded.

;@ROUTINE IN DE OUT CARRY CLOBBERS HL,ZERO,SIGN,PARITY,HALFCARRY
; Carry if the address DE is past SH_LIMIT, the first byte the source may
; not use.

.ROOM:                         ; DE is an address in the source area.
    LD   HL,(SH_LIMIT)             ; HL is the limit.
    OR   A                         ; Clear carry for the subtraction.
    SBC  HL,DE                     ; Carry if DE is above it.
    RET                            ; The caller tests carry.


;@ROUTINE IN A,HL CLOBBERS A,BC,DE,HL,CARRY,ZERO,SIGN,PARITY,HALFCARRY
; Make the include's string literal, A bytes decoded from the source at
; HL (its opening quote), upper-cased, the name in SH_FCB: a CP/M name
; with its type and perhaps a drive (CL_NAME). Anything else raises
; include-syntax at the name (SH_IPOS).

SH_INAME:                      ; HL is the quote, A the length.
    CP   15                        ; P:NAMEXXXX.TYP is fourteen at most;
    JR   NC,.BAD                   ; a longer one is malformed,
    OR   A                         ; and so is
    JR   Z,.BAD                    ; an empty one.
    LD   B,A                       ; B counts the characters.
    INC  HL                        ; The first.
    LD   DE,SH_TEXT                ; They are decoded there.
.CHAR:                         ; B characters remain at HL.
    CALL AG_CHAR                   ; A is the next, decoded.
    OR   A                         ; A NUL
    JR   Z,.BAD                    ; is in no name.
    CP   'a'                       ; A small letter
    JR   C,.UPPER                  ; becomes
    CP   'z'+1                     ; a capital,
    JR   NC,.UPPER                 ; as the reference
    SUB  'a'-'A'                   ; upper-cases the name.
.UPPER:                        ; A is the character.
    LD   (DE),A                    ; Keep it.
    INC  DE                        ; The next.
    DJNZ .CHAR                     ; Until all are decoded.
    XOR  A                         ; Terminate
    LD   (DE),A                    ; the text.
    LD   HL,SH_TEXT                ; Parse it
    CALL CL_NAME                   ; into the FCB:
    JR   C,.BAD                    ; a malformed name,
    LD   A,(HL)                    ; or anything after it,
    OR   A                         ; is
    JR   NZ,.BAD                   ; refused;
    LD   A,(SH_FCB+9)              ; so is
    CP   ' '                       ; a name without a type.
    RET  NZ                        ; The FCB names the part.
.BAD:                          ; Not a CP/M name with its type:
    LD   A,DG_INCL                 ; include-syntax,
    LD   HL,(SH_IPOS)              ; at the name;
    JP   DG_HERE                   ; no return.

;@ROUTINE OUT CARRY CLOBBERS A,BC,DE,HL,IX,IY,ZERO,SIGN,PARITY,HALFCARRY
; Open the part SH_FCB names: on its drive if it names one; otherwise on
; the including part's (SH_CUR), then on option L's drive or A:. Carry if
; it is found, SH_FCB open with the drive it was found on.

SH_SEEK:                       ; SH_FCB names the part.
    LD   A,(SH_FCB)                ; A drive named
    OR   A                         ; is the only
    JR   NZ,SH_TRY                 ; place to look.
    LD   HL,(SH_CUR)               ; The including part's
    LD   A,(HL)                    ; drive
    CALL SH_TRY                    ; is the first;
    RET  C                         ; found there.
    LD   A,(CL_SEEN+CL_IL)         ; Then option L's,
    OR   A                         ; if given,
    JR   NZ,SH_TRY                 ; or else
    INC  A                         ; A:; fall into SH_TRY.

;@ROUTINE IN A OUT CARRY CLOBBERS A,BC,DE,HL,IX,IY,ZERO,SIGN,PARITY,HALFCARRY
; Open the part SH_FCB names on drive A (0 the current one). Carry if it
; is there.

SH_TRY:                        ; A is the drive.
    LD   (SH_FCB),A                ; Look on it,
    LD   HL,SH_FCB+SH_NLEN+1       ; the extent,
    LD   B,SH_FLEN-SH_NLEN-1       ; the map and
    XOR  A                         ; the records
.CLEAR:                        ; cleared,
    LD   (HL),A                    ; a byte
    INC  HL                        ; at a
    DJNZ .CLEAR                    ; time.
    LD   DE,SH_FCB                 ; Open
    LD   C,SH_OPEN                 ; the
    CALL SH_BDOS                   ; part:
    CP   $FF                       ; carry unless it is absent ($FF).
    RET                            ; Carry if it is open.

;@ROUTINE IN HL NORETURN
; Report that the part named on the command line at HL, which SH_BEGIN
; failed to open, is not on the disk: L-MISSING, its argument the part's
; name.

SH_MISS:                       ; HL is the part's drive and name.
    EX   DE,HL                     ; DE is the name.
    LD   HL,SH_NMISS               ; L-MISSING.
    JR   SH_NAMED                  ; Name the part in it.

;@ROUTINE NORETURN
; Report a part that CP/M could not read: L-IO, its argument the part's
; name, and a disk error's return code.

SH_RERR:                       ; SH_LOAD had a read status other than 0 or 1.
    LD   A,SH_RDISK                ; A disk error's
    LD   (SH_RLOW),A               ; return code.
    LD   DE,(SH_CUR)               ; The part being loaded,
    LD   HL,SH_NIO                 ; L-IO.

;@ROUTINE IN DE,HL NORETURN
; Report diagnostic HL with the part whose drive and name are at DE as its
; argument, and fail.

SH_NAMED:                      ; HL is the message number.
    PUSH HL                        ; Keep it across the spelling.
    EX   DE,HL                     ; The part's name,
    LD   DE,DG_ABUF                ; D:NAME.TYP,
    CALL SH_SPELL                  ; spelled there,
    LD   (DG_ARG1),HL              ; is argument 1.
    POP  HL                        ; The number.
    JP   MS_FAIL                   ; Print it and fail.

;@ROUTINE NORETURN
; Report a part whose next record would cross SH_LIMIT.

SH_LARGE:                      ; SH_LOAD found no room for a record.
    LD   A,DG_ROOM                 ; The source's capacity:
    JP   SH_OVER                   ; report it and fail.

;@ROUTINE IN A,DE,HL OUT A,CARRY,ZERO CLOBBERS SIGN,PARITY,HALFCARRY,DE,HL
; Make the bytes [HL,DE) the current part, with identity A, and restart the
; position counters at offset zero, line one, column one. The tokenizer's
; line state starts afresh: no token yet on the line and no open brackets.

SRC_INIT:
    LD   (SRC_ID),A                ; Record the part identity for diagnostics.
    LD   (SRC_PTR),HL              ; The next byte is the part's first.
    EX   DE,HL                     ; Bring the exclusive end into HL.
    LD   (SRC_END),HL              ; Bound the part for SRC_PEEK.
    LD   HL,0                      ; Form offset zero.
    LD   (SRC_POS),HL              ; Offsets count from the part's start.
    INC  HL                        ; Lines and columns count from one.
    LD   (SRC_LINE),HL             ; Begin on the part's first line.
    LD   (SRC_COL),HL              ; Begin in its first column.
    XOR  A                         ; Form zero and clear carry for success.
    LD   (TK_LIVE),A               ; No token has been seen on this line yet.
    LD   (TK_NEST),A               ; No bracket is open across a line break.
    RET                            ; Return success with A zero.

