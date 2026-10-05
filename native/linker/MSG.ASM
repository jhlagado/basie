; Diagnostics by number, with their text read from BASIE.MSG (toolchain
; §7.3; docs/diagnostics.md). The file is magic BSIM, version (2 bytes), a
; u16 count, a u16 offset per message number (0 for none), then each message
; as a length byte and text, in which ^1 and ^2 stand for the arguments.
; Without the file, the number and its arguments are printed instead, so no
; diagnostic is lost.

DG_ARG1: DW      0              ; zero-terminated arguments, or 0
DG_ARG2: DW      0
MSG_FD:   DS      FD_SIZE

MSG_NAME: DB      "BASIE   "
MSG_TYPE: DB      "MSG"
MSG_ERR:  CSTR    "Error "
MSG_WARN: CSTR    "Warning "
MSG_SEP:  CSTR    ": "
MSG_WORD:  CSTR    "Message "
MSG_JOIN:
        CSTR    ", "

; Print "Error N: text" and a line end. HL = the message number.
DG_ERROR:  PUSH    HL
        LD      HL,MSG_ERR
        JR      DG_SAY
; Print "Warning N: text" and a line end. HL = the message number.
DG_WARN:
        PUSH    HL
        LD      HL,MSG_WARN
DG_SAY:
        CALL    CON_STR
        POP     HL
        CALL    CON_DEC
        PUSH    HL
        LD      HL,MSG_SEP
        CALL    CON_STR
        POP     HL
        CALL    .MESSAGE
        JP      CON_CRLF

; Print message HL's text with its arguments.
.MESSAGE:    PUSH    HL
        CALL    .OPEN
        POP     HL
        JR      C,.BARE
        PUSH    HL
        LD      IX,MSG_FD
        XOR     A
        LD      HL,6
        CALL    FIL_SEEK
        CALL    NC,FIL_GETW     ; HL = the count
        EX      DE,HL
        POP     HL
        JR      C,.BARE
        PUSH    HL
        OR      A
        SBC     HL,DE
        POP     HL
        JR      NC,.BARE        ; beyond the table
        PUSH    HL
        ADD     HL,HL
        LD      DE,8
        ADD     HL,DE
        XOR     A
        CALL    FIL_SEEK        ; the message's offset entry
        CALL    NC,FIL_GETW
        JR      C,.NONE
        LD      A,H
        OR      L
        JR      Z,.NONE         ; no message has this number
        XOR     A
        CALL    FIL_SEEK
        CALL    NC,FIL_GETB
        JR      C,.NONE
        POP     DE              ; the number is no longer needed
        LD      B,A             ; B = the bytes left
.TEXT:  LD      A,B
        OR      A
        RET     Z
        CALL    FIL_GETB
        RET     C
        DEC     B
        CP      '^'
        JR      NZ,.PUT
        LD      A,B
        OR      A
        LD      A,'^'
        JR      Z,.PUT
        CALL    FIL_GETB
        RET     C
        DEC     B
        LD      HL,(DG_ARG1)
        CP      '1'
        JR      Z,.ARGUMENT
        LD      HL,(DG_ARG2)
        CP      '2'
        JR      Z,.ARGUMENT
        PUSH    AF
        LD      A,'^'
        CALL    CON_CHAR
        POP     AF
.PUT:   CALL    CON_CHAR
        JR      .TEXT
.ARGUMENT:   PUSH    BC
        CALL    .PUTARG
        POP     BC
        JR      .TEXT
.NONE:  POP     HL
; Without the text: "Message N" and the arguments.
.BARE: PUSH    HL
        LD      HL,MSG_WORD
        CALL    CON_STR
        POP     HL
        CALL    CON_DEC
        LD      HL,(DG_ARG1)
        LD      A,H
        OR      L
        RET     Z
        PUSH    HL
        LD      HL,MSG_SEP
        CALL    CON_STR
        POP     HL
        CALL    CON_STR
        LD      HL,(DG_ARG2)
        LD      A,H
        OR      L
        RET     Z
        PUSH    HL
        LD      HL,MSG_JOIN
        CALL    CON_STR
        POP     HL
        JP      CON_STR

; Print the argument at HL, or "?" when there is none.
.PUTARG: LD      A,H
        OR      L
        JP      NZ,CON_STR
        LD      A,'?'
        JP      CON_CHAR

; Open BASIE.MSG and check its magic: on the library drive (option L) if
; given, else the current drive, then A:. Carry if it can't be used.
.OPEN: LD      IX,MSG_FD
        LD      A,(LIB_DISK)
        CALL    .TRY
        RET     NC
        LD      A,(LIB_DISK)
        OR      A
        SCF
        RET     NZ              ; option L names the only place to look
        LD      A,1
.TRY:   LD      HL,MSG_NAME
        LD      DE,MSG_TYPE
        CALL    FIL_INIT
        CALL    FIL_OPEN
        RET     C
        LD      HL,.MAGIC
        LD      B,4
.CHECK: CALL    FIL_GETB
        RET     C
        CP      (HL)
        SCF
        RET     NZ
        INC     HL
        DJNZ    .CHECK
        OR      A
        RET
.MAGIC: DB      "BSIM"
