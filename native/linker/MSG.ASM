;==========================================================================
;  Diagnostics
;==========================================================================
;
;  Diagnostics by number, with their text read from BASIE.MSG (toolchain
;  §7.3; docs/diagnostics.md). A diagnostic is printed as "Error N: text"
;  or "Warning N: text" on a line of its own. The text may hold ^1 and ^2,
;  which stand for the zero-terminated arguments at DG_ARG1 and DG_ARG2.
;
;  Principal entries:
;    DG_ERROR  print error HL
;    DG_WARN   print warning HL
;    DG_ARG1, DG_ARG2  the arguments, each a string's address or 0
;
;  BASIE.MSG is magic BSIM, a version (2 bytes), a u16 count, a u16 offset
;  per message number (0 for none), then each message as a length byte and
;  its text. The file is opened afresh for each diagnostic through MSG_FD,
;  on the library's drive (option L) if given, else the current drive, then
;  A:. Without the file, or without the message, "Message N" and the
;  arguments are printed instead, so no diagnostic is lost.
;
;  Registers: the diagnostic routines change every register, IX included,
;  since MSG_FD becomes the current FD. Every caller but one ends the link
;  afterwards; the warning in Phase C is followed by Phase D, which sets IX.

DG_ARG1:                       ; Argument 1: a zero-terminated string, or 0.
    DW   0                         ; Callers set it before reporting.
DG_ARG2:                       ; Argument 2, likewise; no diagnostic sets it yet.
    DW   0                         ; Zero: no second argument.
MSG_FD:                        ; The FD that reads BASIE.MSG.
    DS   FD_SIZE                   ; Set up afresh for each diagnostic.

MSG_NAME:                      ; The message file's name, as an FCB holds it.
    DB   "BASIE   "                ; Eight characters, space-padded.
MSG_TYPE:                      ; And its type.
    DB   "MSG"                     ; Three characters.
MSG_ERR:                       ; Begins an error.
    CSTR "Error "                  ; The number follows.
MSG_WARN:                      ; Begins a warning.
    CSTR "Warning "                ; The number follows.
MSG_SEP:                       ; Separates the number from the text or arguments.
    CSTR ": "                      ; As the reference compiler prints it.
MSG_WORD:                      ; Stands for a message whose text is missing.
    CSTR "Message "                ; The number follows, then the arguments.
MSG_JOIN:                      ; Separates the arguments of a bare message.
    CSTR ", "                      ; Between argument 1 and argument 2.

;@ROUTINE IN HL CLOBBERS A,BC,DE,HL,IX,CARRY,ZERO,SIGN,PARITY,HALFCARRY
; Print "Error N: text" and a line end, where HL is the message number N.

DG_ERROR:                      ; HL is the message number.
    PUSH HL                        ; DG_SAY takes the number from the stack.
    LD   HL,MSG_ERR                ; And the kind of diagnostic in HL.
    JR   DG_SAY                    ; Print it.

;@ROUTINE IN HL CLOBBERS A,BC,DE,HL,IX,CARRY,ZERO,SIGN,PARITY,HALFCARRY
; Print "Warning N: text" and a line end, where HL is the message number N.

DG_WARN:                       ; HL is the message number.
    PUSH HL                        ; DG_SAY takes the number from the stack.
    LD   HL,MSG_WARN               ; And the kind of diagnostic in HL.

;@ROUTINE IN HL CLOBBERS A,BC,DE,HL,IX,CARRY,ZERO,SIGN,PARITY,HALFCARRY
; Print the kind at HL, the number on the stack, ": ", the message's text
; and a line end. The number is taken off the stack.

DG_SAY:                        ; HL is "Error " or "Warning ".
    CALL CON_STR                   ; Print the kind.
    POP  HL                        ; HL is the number.
    CALL CON_DEC                   ; Print it; CON_DEC keeps HL.
    PUSH HL                        ; Keep the number while the separator prints.
    LD   HL,MSG_SEP                ; ": " between the number and the text.
    CALL CON_STR                   ; Print it.
    POP  HL                        ; HL is the number again.
    CALL .MESSAGE                  ; Print its text with its arguments.
    JP   CON_CRLF                  ; End the line, and return to the caller.

;@ROUTINE IN HL CLOBBERS A,BC,DE,HL,IX,CARRY,ZERO,SIGN,PARITY,HALFCARRY
; Print message HL's text from BASIE.MSG with its arguments, or, when the
; file or the message is missing, "Message N" and the arguments.

.MESSAGE:                      ; HL is the message number.
    PUSH HL                        ; Keep it across the open.
    CALL .OPEN                     ; Open BASIE.MSG; carry if it can't be used.
    POP  HL                        ; HL is the number again.
    JR   C,.BARE                   ; Without the file, print the number instead.
    PUSH HL                        ; Keep the number across the count's read.
    LD   IX,MSG_FD                 ; Read from the message file.
    XOR  A                         ; The count is at offset 6:
    LD   HL,6                      ; after the magic and the version.
    CALL FIL_SEEK                  ; Go there; carry if the file is too short.
    CALL NC,FIL_GETW               ; HL = the count.
    EX   DE,HL                     ; DE is the count.
    POP  HL                        ; HL is the number.
    JR   C,.BARE                   ; A truncated file gives the bare message.
    PUSH HL                        ; Keep the number across the comparison.
    OR   A                         ; Clear carry for the subtraction.
    SBC  HL,DE                     ; Number minus count: carry if it is in the table.
    POP  HL                        ; HL is the number.
    JR   NC,.BARE                  ; Beyond the table.
    PUSH HL                        ; Keep the number in case there is no text.
    ADD  HL,HL                     ; Each offset entry is two bytes,
    LD   DE,8                      ; and the table follows the 8-byte header.
    ADD  HL,DE                     ; HL is the entry's offset in the file.
    XOR  A                         ; A small offset: its high byte is 0.
    CALL FIL_SEEK                  ; The message's offset entry.
    CALL NC,FIL_GETW               ; HL is the text's offset, or 0.
    JR   C,.NONE                   ; A truncated table gives the bare message.
    LD   A,H                       ; Is the offset 0?
    OR   L                         ; That means no message.
    JR   Z,.NONE                   ; No message has this number.
    XOR  A                         ; The text is within the first 64K.
    CALL FIL_SEEK                  ; Go to the message.
    CALL NC,FIL_GETB               ; A is its length.
    JR   C,.NONE                   ; A truncated file gives the bare message.
    POP  DE                        ; The number is no longer needed.
    LD   B,A                       ; B = the bytes left.
.TEXT:                         ; B counts the text bytes still to read.
    LD   A,B                       ; Are any left?
    OR   A                         ; Zero means the text is done.
    RET  Z                         ; The message is printed.
    CALL FIL_GETB                  ; A is the next byte.
    RET  C                         ; A truncated text simply stops.
    DEC  B                         ; One byte fewer to read.
    CP   '^'                       ; Does an argument marker begin here?
    JR   NZ,.PUT                   ; Any other byte is printed as it is.
    LD   A,B                       ; A marker needs a byte after it.
    OR   A                         ; Is the marker the last byte?
    LD   A,'^'                     ; Then it is printed as itself.
    JR   Z,.PUT                    ; Print the lone '^'.
    CALL FIL_GETB                  ; A is the byte after the marker.
    RET  C                         ; A truncated text simply stops.
    DEC  B                         ; One byte fewer to read.
    LD   HL,(DG_ARG1)              ; ^1 stands for argument 1.
    CP   '1'                       ; Is it ^1?
    JR   Z,.ARGUMENT               ; Print argument 1.
    LD   HL,(DG_ARG2)              ; ^2 stands for argument 2.
    CP   '2'                       ; Is it ^2?
    JR   Z,.ARGUMENT               ; Print argument 2.
    PUSH AF                        ; Any other pair is printed as it is:
    LD   A,'^'                     ; first the marker,
    CALL CON_CHAR                  ; printed,
    POP  AF                        ; then the byte after it.
.PUT:                          ; A is a byte of text.
    CALL CON_CHAR                  ; Print it.
    JR   .TEXT                     ; And go on with the text.
.ARGUMENT:                     ; HL is an argument, or 0.
    PUSH BC                        ; Keep B, the bytes left (CON_STR keeps it too).
    CALL .PUTARG                   ; Print the argument, or "?".
    POP  BC                        ; B is the bytes left.
    JR   .TEXT                     ; And go on with the text.
.NONE:                         ; The number is on the stack.
    POP  HL                        ; HL is the number; fall into the bare form.

;@ROUTINE IN HL OUT HL CLOBBERS A,CARRY,ZERO,SIGN,PARITY,HALFCARRY
; Without the text: print "Message N", then ": " and argument 1 and ", " and
; argument 2, as far as they are given.

.BARE:                         ; HL is the message number.
    PUSH HL                        ; Keep it while the word prints.
    LD   HL,MSG_WORD               ; "Message ".
    CALL CON_STR                   ; Print it.
    POP  HL                        ; HL is the number.
    CALL CON_DEC                   ; Print the number.
    LD   HL,(DG_ARG1)              ; Is there an argument 1?
    LD   A,H                       ; Test its address
    OR   L                         ; for zero.
    RET  Z                         ; No arguments: the line is done.
    PUSH HL                        ; Keep argument 1 while the separator prints.
    LD   HL,MSG_SEP                ; ": " before the arguments.
    CALL CON_STR                   ; Print it.
    POP  HL                        ; HL is argument 1.
    CALL CON_STR                   ; Print it.
    LD   HL,(DG_ARG2)              ; Is there an argument 2?
    LD   A,H                       ; Test its address
    OR   L                         ; for zero.
    RET  Z                         ; Only one argument.
    PUSH HL                        ; Keep argument 2 while the comma prints.
    LD   HL,MSG_JOIN               ; ", " between the arguments.
    CALL CON_STR                   ; Print it.
    POP  HL                        ; HL is argument 2.
    JP   CON_STR                   ; Print it, and return to the caller.

;@ROUTINE IN HL CLOBBERS A,HL,CARRY,ZERO,SIGN,PARITY,HALFCARRY
; Print the argument at HL, or "?" when HL is 0.

.PUTARG:                       ; HL is an argument's address, or 0.
    LD   A,H                       ; Test the address
    OR   L                         ; for zero.
    JP   NZ,CON_STR                ; Print the argument's text.
    LD   A,'?'                     ; A missing argument shows as "?".
    JP   CON_CHAR                  ; Print it, and return to the caller.

;@ROUTINE OUT IX,CARRY CLOBBERS A,BC,DE,HL,ZERO,SIGN,PARITY,HALFCARRY
; Open BASIE.MSG and check its magic: on the library drive (option L) if
; given, else the current drive, then A:. Carry if it can't be used.

.OPEN:                         ; IX becomes the message file's FD.
    LD   IX,MSG_FD                 ; The message file has its own FD.
    LD   A,(LIB_DISK)              ; Option L's drive, or 0 for the current one.
    CALL .TRY                      ; Open the file there and check it.
    RET  NC                        ; Found and sound.
    LD   A,(LIB_DISK)              ; Was a drive given with option L?
    OR   A                         ; Nonzero if so.
    SCF                            ; Report the file as unusable,
    RET  NZ                        ; since option L names the only place to look.
    LD   A,1                       ; Otherwise try drive A:.

;@ROUTINE IN A,IX OUT CARRY CLOBBERS A,BC,DE,HL,ZERO,SIGN,PARITY,HALFCARRY
; Open BASIE.MSG on drive A (0 the current drive) and check its magic,
; BSIM. Carry if it is missing or isn't a message file.

.TRY:                          ; A is the drive.
    LD   HL,MSG_NAME               ; The name BASIE,
    LD   DE,MSG_TYPE               ; and the type MSG.
    CALL FIL_INIT                  ; Set up the FCB.
    CALL FIL_OPEN                  ; Open it; carry if it doesn't exist.
    RET  C                         ; Not on this drive.
    LD   HL,.MAGIC                 ; Compare the first four bytes
    LD   B,4                       ; with the magic.
.CHECK:                        ; HL walks the magic, B counts down.
    CALL FIL_GETB                  ; A is the file's next byte.
    RET  C                         ; Too short to be a message file.
    CP   (HL)                      ; Does it match?
    SCF                            ; If not, report the file as unusable,
    RET  NZ                        ; with carry.
    INC  HL                        ; The next magic byte.
    DJNZ .CHECK                    ; Until all four match.
    OR   A                         ; Clear carry: the file is usable.
    RET                            ; IX is left on the opened file.
.MAGIC:                        ; The message file's magic.
    DB   "BSIM"                    ; Basie message file (toolchain §7.3).
