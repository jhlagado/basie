; CP/M calls and console output.
;
; Every BDOS call goes through BDOS, which keeps IX and IY: CP/M 2.2 doesn't
; promise to preserve them, and some BIOSes use them (cpm-target §9).

CPM_BDOS   EQU     $0005
CPM_TAIL    EQU     $0080       ; the command tail: a length, then the text
CPM_TOP     EQU     $0006       ; the BDOS entry: the top of usable memory

RC_OK   EQU     $0000           ; return codes (toolchain §5.4)
RC_LINK EQU     $FF12
RC_DISK EQU     $FF13

; Call BDOS function C with DE. Returns what BDOS returns.
CPM_CALL:   PUSH    IX
        PUSH    IY
        CALL    CPM_BDOS
        POP     IY
        POP     IX
        RET

; Write A to the console. Preserves every register but F.
CON_CHAR:   PUSH    AF
        PUSH    BC
        PUSH    DE
        PUSH    HL
        LD      E,A
        LD      C,2
        CALL    CPM_CALL
        POP     HL
        POP     DE
        POP     BC
        POP     AF
        RET

; Write the zero-terminated string at HL. Returns HL past the zero.
CON_STR:   LD      A,(HL)
        INC     HL
        OR      A
        RET     Z
        CALL    CON_CHAR
        JR      CON_STR

CON_CRLF:
        LD      A,13
        CALL    CON_CHAR
        LD      A,10
        JR      CON_CHAR

; Write HL in decimal, without leading zeros. Preserves HL.
CON_DEC: PUSH    HL
        PUSH    DE
        PUSH    BC
        LD      B,0             ; B = 1 once a digit has been written
        LD      DE,10000
        CALL    .DIGIT
        LD      DE,1000
        CALL    .DIGIT
        LD      DE,100
        CALL    .DIGIT
        LD      DE,10
        CALL    .DIGIT
        LD      A,L
        ADD     A,'0'
        CALL    CON_CHAR
        POP     BC
        POP     DE
        POP     HL
        RET
.DIGIT: LD      A,'0'-1
.SUB:   INC     A
        OR      A
        SBC     HL,DE
        JR      NC,.SUB
        ADD     HL,DE
        CP      '0'
        JR      NZ,.SHOW
        INC     B
        DEC     B
        RET     Z               ; a leading zero
.SHOW:  LD      B,1
        JR      CON_CHAR

; End the run with return code DE (BDOS 108, ignored by CP/M 2.2).
CPM_EXIT: LD      C,108
        CALL    CPM_CALL
        JP      0
