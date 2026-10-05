;==========================================================================
;  Diagnostic messages
;==========================================================================
;
;  BASIE.COM's diagnostics by number, with their text read from BASIE.MSG
;  (design decision D39; toolchain §7.3; docs/diagnostics.md), printed as
;  the reference toolchain prints them: the DIAG overlay of BASIE.OVL
;  (OVERLAY.ASM), with PARTNAME.ASM. A compiler diagnostic is printed as
;  `NAME.BSI LINE:COLUMN: N: text`, as tools/basie.ts prints the reference
;  compiler's; one that names no part, and the toolchain's own (the command
;  line, the library, BLINK.COM), as `Error N: text`, as BLINK prints its
;  diagnostics. The text may hold ^1 and ^2, replaced by the arguments at
;  DG_ARG1 and DG_ARG2, each a zero-terminated string or zero, outside the
;  overlay area; a missing one prints as "?". Without the file, or without
;  the message, the text is "Message N" and the arguments, as BLINK prints
;  it, so no diagnostic is lost. The line is left for the shell to end.
;
;  Principal entries:
;    MS_SHOWE  at OV_AREA: "Error N: text" for diagnostic HL (MS_FAIL's)
;    MS_SHOWD  at OV_AREA+3: the compiler's diagnostic, DG_CODE in DG_PART
;              at DG_POS (SH_DIAG's and SH_OVER's)
;
;  The compiler's codes (DG_ in STATE.ASM) are the reference's numbers,
;  below DG_TOKEN and from 190 to 199, and two families MS_DIAG maps:
;  DG_TOKEN plus a token kind, or a pseudo-kind for a phrase, is `syntax`
;  (20), whose argument is what was expected, a keyword or punctuator in
;  quotes or a phrase from MS_PHR; DG_CAP plus a limit's index is
;  `capacity` (190), whose argument names the limit, from MS_CAPS.
;
;  BASIE.MSG is magic BSIM, a version, a u16 count, a u16 offset per
;  message number (0 for none), then each message as a length byte and its
;  text. It is read a record at a time with BDOS random reads into MS_BUF,
;  through the shell's FCB, MS_REC holding the number of the record there.
;  It is looked for on option L's drive, else the current drive, then A:.
;  Every routine here may change every register: each BDOS call may.

MS_BUF EQU  AG_IBUF            ; A record of BASIE.MSG: no compilation is running.
MS_RAND EQU  33                ; BDOS read random: the record is in the FCB.
MS_NONE EQU  $FF               ; MS_REC when no record is held.
MS_NSYN EQU  20                ; The reference's syntax.
MS_NCAP EQU  190               ; The reference's capacity.

;@ROUTINE IN HL CLOBBERS A,BC,DE,HL,IX,IY,CARRY,ZERO,SIGN,PARITY,HALFCARRY
; The overlay's entries: OV_AREA, MS_SHOWE, prints "Error N: text" for
; diagnostic HL, as BLINK prints its own; OV_AREA+3, MS_SHOWD, the
; compiler's diagnostic. Neither ends the line.

MS_ENTRY:                      ; At OV_AREA: HL is the number.
    JP   MS_SHOWE                  ; MS_SHOWD follows at +3.

;@ROUTINE CLOBBERS A,BC,DE,HL,IX,IY,CARRY,ZERO,SIGN,PARITY,HALFCARRY
; Print the compiler's diagnostic, DG_CODE in DG_PART at DG_POS, as the
; reference toolchain prints one, NAME.TYP LINE:COLUMN: N: text, the line
; and column counted from the offset in the resident source, or as
; Error N: text when it names no part. The line is not ended.

MS_SHOWD:                      ; At OV_AREA+3.
    LD   A,(DG_PART)               ; A is the failing part's 1-based id.
    OR   A                         ; Zero means that no part was current:
    LD   HL,MS_ERR                 ; then "Error ",
    JR   Z,.NUMBER                 ; as BLINK prints a diagnostic.
    DEC  A                         ; The id less one is the index of its saved name.
    PUSH AF                        ; Keep it for the position.
    LD   DE,SH_TEXT                ; Spell it as D:NAME.TYP
    CALL SH_SPELL                  ; there,
    CALL SH_PRINT                  ; and print it.
    LD   A,' '                     ; A space separates the name from the position.
    CALL SH_CHAR                   ; Print it.
    POP  AF                        ; The part's index:
    LD   L,A                       ; its descriptor
    LD   H,0                       ; is
    LD   D,H                       ; five
    LD   E,L                       ; times
    ADD  HL,HL                     ; the
    ADD  HL,HL                     ; index
    ADD  HL,DE                     ; on from SH_PARTS,
    LD   DE,SH_PARTS+1             ; and its start
    ADD  HL,DE                     ; follows the id:
    LD   E,(HL)                    ; DE is
    INC  HL                        ; where the part
    LD   D,(HL)                    ; begins.
    LD   HL,(DG_POS)               ; The fault's offset in it
    ADD  HL,DE                     ; gives its address.
    EX   DE,HL                     ; HL walks the part, DE is the fault.
    LD   BC,1                      ; BC counts lines from 1;
    PUSH HL                        ; the line begins
    POP  IX                        ; at the part's start.
.SCAN:                         ; HL is at or below DE.
    LD   A,L                       ; Has the walk
    CP   E                         ; reached
    JR   NZ,.BYTE                  ; the fault?
    LD   A,H                       ; Compare
    CP   D                         ; the high bytes.
    JR   Z,.FOUND                  ; It has.
.BYTE:                         ; HL is a byte before the fault.
    LD   A,(HL)                    ; The byte,
    INC  HL                        ; passed.
    CP   10                        ; A line feed
    JR   NZ,.SCAN                  ; ends a line:
    INC  BC                        ; one more,
    PUSH HL                        ; beginning
    POP  IX                        ; after it.
    JR   .SCAN                     ; Go on.
.FOUND:                        ; BC is the line, IX its start.
    PUSH IX                        ; The column is the fault
    POP  HL                        ; less the line's start,
    EX   DE,HL                     ; counted
    OR   A                         ; from
    SBC  HL,DE                     ; one,
    INC  HL                        ; HL.
    PUSH HL                        ; Keep it.
    LD   L,C                       ; The line,
    LD   H,B                       ; HL,
    CALL SH_NUM                    ; is printed,
    LD   A,':'                     ; a colon separating it
    CALL SH_CHAR                   ; from the column.
    POP  HL                        ; The column
    CALL SH_NUM                    ; is printed.
    LD   HL,MS_SEP                 ; ": " separates the position from the number.
.NUMBER:                       ; HL is the text before the number.
    CALL SH_PRINT                  ; Print it; fall into MS_DIAG.

;@ROUTINE CLOBBERS A,BC,DE,HL,IX,IY,CARRY,ZERO,SIGN,PARITY,HALFCARRY
; Print the compiler's diagnostic DG_CODE as its message number, ": " and
; its text, taking the argument of a syntax or capacity diagnostic.

MS_DIAG:                       ; DG_CODE is set and DG_ARG1 is its argument, if any.
    LD   A,(DG_CODE)               ; The compiler's code.
    LD   L,A                       ; HL is it,
    LD   H,0                       ; for a number that needs no mapping.
    SUB  DG_CAP                    ; A capacity?
    JR   C,.NOTCAP                 ; No.
    LD   HL,MS_CAPS                ; Its name is the A'th
    OR   A                         ; of the zero-terminated names:
    JR   Z,.NAMED                  ; the first,
    LD   B,A                       ; or after B others.
.SCAN:                         ; HL is in a name to pass over.
    LD   A,(HL)                    ; Its next byte.
    INC  HL                        ; Move on.
    OR   A                         ; Until its terminator.
    JR   NZ,.SCAN                  ; Then
    DJNZ .SCAN                     ; the next, until B are passed.
.NAMED:                        ; HL is the limit's name.
    LD   (DG_ARG1),HL              ; It is argument 1.
    LD   HL,MS_NCAP                ; capacity.
    JR   MS_SAY                    ; Print the number and text.
.NOTCAP:                       ; HL is the code.
    LD   A,L                       ; Below DG_TOKEN
    SUB  DG_TOKEN                  ; it is the reference's number,
    JR   C,MS_SAY                  ; printed as it is,
    CP   MS_NCAP-DG_TOKEN          ; and so is one from 190 on.
    JR   NC,MS_SAY                 ; Print it.
    CALL MS_KIND                   ; Otherwise argument 1 is what was expected,
    LD   HL,MS_NSYN                ; in syntax.

;@ROUTINE IN HL CLOBBERS A,BC,DE,HL,IX,IY,CARRY,ZERO,SIGN,PARITY,HALFCARRY
; Print message number HL, ": " and its text.

MS_SAY:                        ; HL is the number.
    PUSH HL                        ; Keep it while it prints.
    CALL SH_NUM                    ; Print it.
    LD   HL,MS_SEP                 ; ": "
    CALL SH_PRINT                  ; before the text.
    POP  HL                        ; The number again.
    JR   MS_TEXT                   ; Print its text, and return.

;@ROUTINE IN HL CLOBBERS A,BC,DE,HL,IX,IY,CARRY,ZERO,SIGN,PARITY,HALFCARRY
; Print "Error N: text" for diagnostic HL, as BLINK prints its own.

MS_SHOWE:                      ; HL is the number.
    PUSH HL                        ; Keep it while the word prints.
    LD   HL,MS_ERR                 ; "Error "
    CALL SH_PRINT                  ; before the number.
    POP  HL                        ; The number again.
    JR   MS_SAY                    ; Print it and its text.

;@ROUTINE IN A CLOBBERS A,BC,DE,HL,CARRY,ZERO,SIGN,PARITY,HALFCARRY
; Set argument 1 to what a syntax diagnostic expected, token kind or
; pseudo-kind A: a phrase from MS_PHR, or a keyword or punctuator in
; quotes. A kind that has neither leaves argument 1 zero.

MS_KIND:                       ; A is the kind.
    LD   C,A                       ; Keep it.
    LD   HL,MS_PHR                 ; First the phrases: a kind, then its text.
.PHRASE:                       ; HL is an entry or the end.
    LD   A,(HL)                    ; Its kind,
    INC  HL                        ; then its text.
    CP   C                         ; Is it the kind expected?
    JR   Z,.FOUND                  ; HL is the phrase.
    INC  A                         ; The end of the table is $FF.
    JR   Z,.WORDS                  ; Try the keywords.
.PASS:                         ; Pass over the phrase.
    LD   A,(HL)                    ; Its next byte.
    INC  HL                        ; Move on.
    OR   A                         ; Until its terminator.
    JR   NZ,.PASS                  ; Then the next entry.
    JR   .PHRASE                   ; Compare it.
.FOUND:                        ; HL is a phrase.
    LD   (DG_ARG1),HL              ; It is argument 1.
    RET                            ; Done.
.WORDS:                        ; The keywords: a length, the spelling, the kind.
    LD   HL,KW_TAB                 ; The first.
    LD   B,KW_CNT                  ; Each of them.
.KEY:                          ; HL is an entry.
    LD   A,(HL)                    ; Its length.
    INC  HL                        ; HL is its spelling.
    LD   E,L                       ; DE keeps
    LD   D,H                       ; the spelling.
    ADD  A,L                       ; HL becomes
    LD   L,A                       ; the spelling's end,
    ADC  A,H                       ; carrying
    SUB  L                         ; into
    LD   H,A                       ; the high byte: its kind.
    LD   A,(HL)                    ; Is it
    CP   C                         ; the kind expected?
    JR   Z,.QUOTE                  ; Quote the spelling, DE to HL.
    INC  HL                        ; The next entry.
    DJNZ .KEY                      ; Until the keywords are done.
    LD   HL,KW_PUNCT               ; Then the punctuators: a character, a kind.
    LD   B,KW_PCNT                 ; Each of them.
.PUNCT:                        ; HL is an entry.
    LD   E,L                       ; DE keeps
    LD   D,H                       ; the character.
    INC  HL                        ; Its kind,
    LD   A,(HL)                    ; which ends the spelling.
    CP   C                         ; Is it the kind expected?
    JR   Z,.QUOTE                  ; Quote the character.
    INC  HL                        ; The next entry.
    DJNZ .PUNCT                    ; Until the punctuators are done.
    RET                            ; No spelling: argument 1 stays zero.
.QUOTE:                        ; DE is a spelling, HL its end.
    EX   DE,HL                     ; HL walks it, DE is its end.
    LD   BC,DG_ABUF                ; Argument 1 is built here:
    LD   A,$27                     ; a quote,
.COPY:                         ; A is the next byte of the argument.
    LD   (BC),A                    ; Store it.
    INC  BC                        ; The next place.
    LD   A,L                       ; Is the spelling done?
    CP   E                         ; It is shorter than 256 bytes.
    LD   A,(HL)                    ; Its next character,
    INC  HL                        ; if any.
    JR   NZ,.COPY                  ; Copy it.
    LD   A,$27                     ; Then the closing quote
    LD   (BC),A                    ; is stored,
    INC  BC                        ; and
    XOR  A                         ; the
    LD   (BC),A                    ; terminator.
    LD   HL,DG_ABUF                ; That is
    JR   .FOUND                    ; argument 1.

;@ROUTINE IN HL CLOBBERS A,BC,DE,HL,IX,IY,CARRY,ZERO,SIGN,PARITY,HALFCARRY
; Print message HL's text from BASIE.MSG with its arguments, or, when the
; file or the message is missing, "Message N" and the arguments.

MS_TEXT:                       ; HL is the message number.
    PUSH HL                        ; Keep it across the open.
    CALL .OPEN                     ; Open BASIE.MSG; carry if it can't be used.
    POP  HL                        ; HL is the number again.
    JR   C,.BARE                   ; Without the file, print the number instead.
    PUSH HL                        ; Keep the number across the count's read.
    LD   HL,6                      ; The count is at offset 6,
    CALL .WORD                     ; after the magic and the version.
    EX   DE,HL                     ; DE is the count.
    POP  HL                        ; HL is the number.
    JR   C,.BARE                   ; A truncated file gives the bare message.
    PUSH HL                        ; Keep the number across the comparison.
    SBC  HL,DE                     ; Carry is clear: carry if it is in the table.
    POP  HL                        ; HL is the number.
    JR   NC,.BARE                  ; Beyond the table.
    PUSH HL                        ; Keep the number in case there is no text.
    INC  HL                        ; The table follows the 8-byte header,
    INC  HL                        ; so the entry is at
    INC  HL                        ; twice the number
    INC  HL                        ; plus four,
    ADD  HL,HL                     ; doubled.
    CALL .WORD                     ; HL is the text's offset, or 0.
    JR   C,.NONE                   ; A truncated table gives the bare message.
    LD   A,H                       ; Is the offset 0?
    OR   L                         ; That means no message.
    JR   Z,.NONE                   ; No message has this number.
    CALL .BYTE                     ; A is its length; HL is the text.
    JR   C,.NONE                   ; A truncated file gives the bare message.
    POP  DE                        ; The number is no longer needed.
    LD   B,A                       ; B = the bytes left.
.TEXT:                         ; B counts the text bytes still to read.
    LD   A,B                       ; Are any left?
    OR   A                         ; Zero means the text is done.
    RET  Z                         ; The message is printed.
    CALL .BYTE                     ; A is the next byte.
    RET  C                         ; A truncated text simply stops.
    DEC  B                         ; One byte fewer to read.
    CP   '^'                       ; Does an argument marker begin here?
    JR   NZ,.PUT                   ; Any other byte is printed as it is.
    LD   A,B                       ; A marker needs a byte after it.
    OR   A                         ; Is the marker the last byte?
    LD   A,'^'                     ; Then it is printed as itself.
    JR   Z,.PUT                    ; Print the lone '^'.
    CALL .BYTE                     ; A is the byte after the marker.
    RET  C                         ; A truncated text simply stops.
    DEC  B                         ; One byte fewer to read.
    PUSH HL                        ; Keep the file offset.
    LD   HL,(DG_ARG1)              ; ^1 stands for argument 1.
    CP   '1'                       ; Is it ^1?
    JR   Z,.ARGUMENT               ; Print argument 1.
    LD   HL,(DG_ARG2)              ; ^2 stands for argument 2.
    CP   '2'                       ; Is it ^2?
    JR   Z,.ARGUMENT               ; Print argument 2.
    POP  HL                        ; Any other pair is printed as it is:
    PUSH AF                        ; the byte after the marker is kept
    LD   A,'^'                     ; while the marker
    CALL SH_CHAR                   ; is printed.
    POP  AF                        ; Then the byte after it.
.PUT:                          ; A is a byte of text.
    CALL SH_CHAR                   ; Print it.
    JR   .TEXT                     ; And go on with the text.
.ARGUMENT:                     ; HL is an argument, or 0; the offset is stacked.
    CALL .PUTARG                   ; Print it, or "?"; B, the bytes left, is kept.
    POP  HL                        ; The file offset.
    JR   .TEXT                     ; And go on with the text.
.NONE:                         ; The number is on the stack.
    POP  HL                        ; HL is the number; fall into the bare form.

;@ROUTINE IN HL CLOBBERS A,BC,DE,HL,IX,IY,CARRY,ZERO,SIGN,PARITY,HALFCARRY
; Without the text: print "Message N", then ": " and argument 1 and ", "
; and argument 2, as far as they are given.

.BARE:                         ; HL is the message number.
    PUSH HL                        ; Keep it while the word prints.
    LD   HL,MS_WORD                ; "Message ".
    CALL SH_PRINT                  ; Print it.
    POP  HL                        ; HL is the number.
    CALL SH_NUM                    ; Print the number.
    LD   HL,(DG_ARG1)              ; Is there an argument 1?
    LD   A,H                       ; Test its address
    OR   L                         ; for zero.
    RET  Z                         ; No arguments: the line is done.
    PUSH HL                        ; Keep argument 1 while the separator prints.
    LD   HL,MS_SEP                 ; ": " before the arguments.
    CALL SH_PRINT                  ; Print it.
    POP  HL                        ; HL is argument 1.
    CALL SH_PRINT                  ; Print it.
    LD   HL,(DG_ARG2)              ; Is there an argument 2?
    LD   A,H                       ; Test its address
    OR   L                         ; for zero.
    RET  Z                         ; Only one argument.
    PUSH HL                        ; Keep argument 2 while the comma prints.
    LD   HL,MS_JOIN                ; ", " between the arguments.
    CALL SH_PRINT                  ; Print it.
    POP  HL                        ; HL is argument 2.
    JP   SH_PRINT                  ; Print it, and return to the caller.

;@ROUTINE IN HL CLOBBERS A,HL,IX,IY,CARRY,ZERO,SIGN,PARITY,HALFCARRY
; Print the argument at HL, or "?" when HL is 0.

.PUTARG:                       ; HL is an argument's address, or 0.
    LD   A,H                       ; Test the address
    OR   L                         ; for zero.
    JP   NZ,SH_PRINT               ; Print the argument's text.
    LD   A,'?'                     ; A missing argument shows as "?".
    JP   SH_CHAR                   ; Print it, and return to the caller.

;@ROUTINE OUT CARRY CLOBBERS A,BC,DE,HL,IX,IY,ZERO,SIGN,PARITY,HALFCARRY
; Open BASIE.MSG and check its magic: on option L's drive if given, else
; the current drive, then on A: (toolchain §7.3). Carry if it can't be
; used.

.OPEN:                         ; SH_FCB is free: no other file is open for reading.
    LD   A,(CL_SEEN+CL_IL)         ; Option L's drive, or 0 for the current one.
    CALL .TRY                      ; Open the file there and check it.
    RET  NC                        ; Found and sound.
    LD   A,1                       ; Then try drive A:.

;@ROUTINE IN A OUT CARRY CLOBBERS A,BC,DE,HL,IX,IY,ZERO,SIGN,PARITY,HALFCARRY
; Open BASIE.MSG on drive A (0 the current drive) and check its magic,
; BSIM. Carry if it is missing or isn't a message file.

.TRY:                          ; A is the drive.
    PUSH AF                        ; Keep it across the clearing.
    CALL SH_BLANK                  ; A clear FCB, its random record zero.
    POP  AF                        ; The drive
    LD   (SH_FCB),A                ; is the FCB's.
    LD   HL,MS_NAME                ; BASIE.MSG's name and type
    LD   DE,SH_FCB+1               ; into the name field,
    LD   BC,SH_NLEN                ; eleven characters.
    LDIR                           ; The FCB names it.
    LD   A,MS_NONE                 ; No record
    LD   (MS_REC),A                ; is held yet.
    LD   DE,SH_FCB                 ; DE is the FCB for BDOS.
    LD   C,SH_OPEN                 ; Open it;
    CALL SH_BDOS                   ; A is $FF if it is absent,
    ADD  A,1                       ; which alone sets carry.
    RET  C                         ; Not on this drive.
    LD   HL,0                      ; Compare the first four bytes
.CHECK:                        ; HL is the next offset.
    CALL .BYTE                     ; A is the file's byte there; HL moves on.
    RET  C                         ; Too short to be a message file.
    PUSH HL                        ; Keep the offset.
    LD   DE,MS_MAGIC-1             ; with the magic:
    ADD  HL,DE                     ; HL is the magic's byte,
    CP   (HL)                      ; which must match.
    POP  HL                        ; The offset again.
    SCF                            ; If it differs, report the file as unusable,
    RET  NZ                        ; with carry.
    LD   A,L                       ; Until
    CP   4                         ; all four match.
    JR   C,.CHECK                  ; The next.
    RET                            ; Carry is clear: the file is usable.

;@ROUTINE IN HL OUT HL CLOBBERS A,E,CARRY,ZERO,SIGN,PARITY,HALFCARRY
; HL = the word at offset HL of BASIE.MSG. Carry if it can't be read.

.WORD:                         ; HL is the offset.
    CALL .BYTE                     ; The low byte; HL moves on.
    RET  C                         ; Unreadable.
    LD   E,A                       ; Keep it.
    CALL .BYTE                     ; The high byte.
    LD   H,A                       ; HL is
    LD   L,E                       ; the word.
    RET                            ; Carry from the second read.

;@ROUTINE IN HL OUT A,HL,CARRY CLOBBERS ZERO,SIGN,PARITY,HALFCARRY
; A = the byte at offset HL of BASIE.MSG, reading its record into MS_BUF
; unless it is the one held, and HL one more. Carry if it can't be read.
; BC and DE are kept. The file is below 32K.

.BYTE:                         ; HL is the offset.
    PUSH BC                        ; Keep BC
    PUSH DE                        ; and DE across the BDOS calls.
    PUSH HL                        ; And the offset.
    LD   A,L                       ; The record is the offset
    RLA                            ; over 128:
    LD   A,H                       ; bit 7 of the low byte
    RLA                            ; joins the high byte's bits.
    LD   HL,MS_REC                 ; Is it
    CP   (HL)                      ; the record held?
    JR   Z,.HELD                   ; Then it is in MS_BUF.
    LD   (HL),A                    ; It will be.
    LD   (SH_FCB+33),A             ; The random record; its high bytes are zero.
    LD   DE,MS_BUF                 ; Read it
    LD   C,SH_DMA                  ; into
    CALL SH_BDOS                   ; the buffer.
    LD   DE,SH_FCB                 ; Read
    LD   C,MS_RAND                 ; the record.
    CALL SH_BDOS                   ; A is zero if it was read.
    OR   A                         ; Was it?
    JR   Z,.HELD                   ; Yes.
    LD   A,MS_NONE                 ; No record
    LD   (MS_REC),A                ; is held,
    SCF                            ; and the byte can't be read.
    JR   .OUT                      ; Return carry.
.HELD:                         ; The record is in MS_BUF.
    POP  HL                        ; The offset
    PUSH HL                        ; is kept.
    LD   A,L                       ; Its place
    AND  $7F                       ; in the record
    LD   E,A                       ; is
    LD   D,0                       ; DE,
    LD   HL,MS_BUF                 ; and the byte
    ADD  HL,DE                     ; is there; no carry.
    LD   A,(HL)                    ; A is the byte.
.OUT:                          ; Carry is set for a failure.
    POP  HL                        ; The offset
    INC  HL                        ; moves on.
    POP  DE                        ; Restore DE
    POP  BC                        ; and BC.
    RET                            ; A is the byte, unless carry.

; ---- data ------------------------------------------------------------------

MS_NAME:                       ; The message file's name, as an FCB holds it.
    DB   "BASIE   MSG"             ; Eight characters, space-padded, and the type.
MS_MAGIC:                      ; The message file's magic.
    DB   "BSIM"                    ; Basie message file (toolchain §7.3).
MS_ERR:                        ; Begins a diagnostic that names no part.
    DB   "Error ",0                ; The number follows.
MS_SEP:                        ; Separates the number from the text or arguments.
    DB   ": ",0                    ; As the reference toolchain prints it.
MS_WORD:                       ; Stands for a message whose text is missing.
    DB   "Message ",0              ; The number follows, then the arguments.
MS_JOIN:                       ; Separates the arguments of a bare message.
    DB   ", ",0                    ; Between argument 1 and argument 2.

; What a syntax diagnostic expected, for the kinds KW_TAB and KW_PUNCT do
; not spell and the pseudo-kinds (STATE.ASM): the kind, then the phrase
; the reference compiler's message gives.
MS_PHR:                        ; Each entry: a kind, a zero-terminated phrase.
    DB   TK_EOL,"the end of the line",0 ; As expectNewline says.
    DB   TK_NAME,"a name",0        ; As expectName says.
    DB   TK_LPAR,"'('",0           ; The brackets are not in KW_PUNCT.
    DB   TK_RPAR,"')'",0           ; Nor the closing one.
    DB   TK_LBRAC,"'['",0          ; Nor the square ones.
    DB   TK_RBRAC,"']'",0          ; Nor the closing one.
    DB   TK_TEXT,"a string literal",0 ; A string's initializer.
    DB   TK_XEXPR,"an expression",0 ; A value: DG_VALUE.
    DB   TK_XTYPE,"a type",0       ; A type: DG_TYPE.
    DB   TK_XDECL,"a declaration",0 ; A top-level declaration: DG_DECL.
    DB   TK_XSTMT,"a statement",0  ; A statement: DG_STMT.
    DB   TK_XUPTO,"'to' or 'until'",0 ; A for loop's bound: DG_UPTO.
    DB   $FF                       ; The end of the table.

; The limits a capacity diagnostic names, in the order of DG_CAP's family.
MS_CAPS:                       ; Each a zero-terminated name.
    DB   "symbols",0               ; DG_SYMS: the symbol table.
    DB   "routines",0              ; DG_PROCS: the routine records.
    DB   "parameters",0            ; DG_PARAM: one routine's parameters.
    DB   "literals",0              ; DG_LITS: one routine's string literals.
    DB   "types",0                 ; DG_META: types, records and fields.
    DB   "nesting",0               ; DG_NEST: control statements.
    DB   "expression depth",0      ; DG_DEEP: the operand stack and calls.
    DB   "labels",0                ; DG_LABEL: one routine's labels.
    DB   "initializer depth",0     ; DG_INITS: nested initializers.
    DB   "object size",0           ; DG_DATA: 1K, the initializer staging.
    DB   "routine size",0          ; DG_BLOB: the blob writer's buffers.
    DB   "grammar stack",0         ; DG_LLCAP: the LL(1) stack.
    DB   "source parts",0          ; DG_PARTS: the part table.
    DB   "source size",0           ; DG_ROOM: memory for the source.
