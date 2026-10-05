; Diagnostics by number, with their text read from BASIE.MSG (toolchain
; §7.3; docs/diagnostics.md). The file is magic BSIM, version (2 bytes), a
; u16 count, a u16 offset per message number (0 for none), then each message
; as a length byte and text, in which ^1 and ^2 stand for the arguments.
; Without the file, the number and its arguments are printed instead, so no
; diagnostic is lost.

M_ARG1: DW      0               ; zero-terminated arguments, or 0
M_ARG2: DW      0
M_FD:   DS      FDSIZE

M_NAME: DB      "BASIE   "
M_TYPE: DB      "MSG"
M_ERR:  CSTR    "Error "
M_WARN: CSTR    "Warning "
M_SEP:  CSTR    ": "
M_MSG:  CSTR    "Message "
M_COMMA:
        CSTR    ", "

; Print "Error N: text" and a line end. HL = the message number.
ERROR:  PUSH    HL
        LD      HL,M_ERR
        JR      SAYKIND
; Print "Warning N: text" and a line end. HL = the message number.
WARNING:
        PUSH    HL
        LD      HL,M_WARN
SAYKIND:
        CALL    PUTS
        POP     HL
        CALL    PUTDEC
        PUSH    HL
        LD      HL,M_SEP
        CALL    PUTS
        POP     HL
        CALL    SAY
        JP      PUTCRLF

; Print message HL's text with its arguments.
SAY:    PUSH    HL
        CALL    M_OPEN
        POP     HL
        JR      C,M_BARE
        PUSH    HL
        LD      IX,M_FD
        XOR     A
        LD      HL,6
        CALL    F_SEEK
        CALL    NC,F_GETW       ; HL = the count
        EX      DE,HL
        POP     HL
        JR      C,M_BARE
        PUSH    HL
        OR      A
        SBC     HL,DE
        POP     HL
        JR      NC,M_BARE       ; beyond the table
        PUSH    HL
        ADD     HL,HL
        LD      DE,8
        ADD     HL,DE
        XOR     A
        CALL    F_SEEK          ; the message's offset entry
        CALL    NC,F_GETW
        JR      C,.NONE
        LD      A,H
        OR      L
        JR      Z,.NONE         ; no message has this number
        XOR     A
        CALL    F_SEEK
        CALL    NC,F_GETB
        JR      C,.NONE
        POP     DE              ; the number is no longer needed
        LD      B,A             ; B = the bytes left
.TEXT:  LD      A,B
        OR      A
        RET     Z
        CALL    F_GETB
        RET     C
        DEC     B
        CP      '^'
        JR      NZ,.PUT
        LD      A,B
        OR      A
        LD      A,'^'
        JR      Z,.PUT
        CALL    F_GETB
        RET     C
        DEC     B
        LD      HL,(M_ARG1)
        CP      '1'
        JR      Z,.ARG
        LD      HL,(M_ARG2)
        CP      '2'
        JR      Z,.ARG
        PUSH    AF
        LD      A,'^'
        CALL    PUTC
        POP     AF
.PUT:   CALL    PUTC
        JR      .TEXT
.ARG:   PUSH    BC
        CALL    M_PARG
        POP     BC
        JR      .TEXT
.NONE:  POP     HL
; Without the text: "Message N" and the arguments.
M_BARE: PUSH    HL
        LD      HL,M_MSG
        CALL    PUTS
        POP     HL
        CALL    PUTDEC
        LD      HL,(M_ARG1)
        LD      A,H
        OR      L
        RET     Z
        PUSH    HL
        LD      HL,M_SEP
        CALL    PUTS
        POP     HL
        CALL    PUTS
        LD      HL,(M_ARG2)
        LD      A,H
        OR      L
        RET     Z
        PUSH    HL
        LD      HL,M_COMMA
        CALL    PUTS
        POP     HL
        JP      PUTS

; Print the argument at HL, or "?" when there is none.
M_PARG: LD      A,H
        OR      L
        JP      NZ,PUTS
        LD      A,'?'
        JP      PUTC

; Open BASIE.MSG and check its magic: on the library drive (option L) if
; given, else the current drive, then A:. Carry if it can't be used.
M_OPEN: LD      IX,M_FD
        LD      A,(O_LDRV)
        CALL    .TRY
        RET     NC
        LD      A,(O_LDRV)
        OR      A
        SCF
        RET     NZ              ; option L names the only place to look
        LD      A,1
.TRY:   LD      HL,M_NAME
        LD      DE,M_TYPE
        CALL    F_INIT
        CALL    F_OPEN
        RET     C
        LD      HL,.MAGIC
        LD      B,4
.CHECK: CALL    F_GETB
        RET     C
        CP      (HL)
        SCF
        RET     NZ
        INC     HL
        DJNZ    .CHECK
        OR      A
        RET
.MAGIC: DB      "BSIM"
