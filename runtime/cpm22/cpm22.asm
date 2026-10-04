; Baton runtime for CP/M 2.2: the minimal library (roadmap step 31).
;
; Built into CPM22.BRL by tools/brl.ts. Each blob starts at a "; @blob" line:
;
;   ; @blob ORDINAL KIND NAME [align=N] [helper=CC] [since=V]
;
; and runs to the next one. Labels: a blob's entry is the only global label it
; needs, written AREA_WHAT with an underscore; everything internal is a private
; .label, which ATOM scopes to the enclosing global. A blob refers to another by its first label, and
; to the linker's pseudo-objects by the names the tool defines: MAIN, IMAGE,
; BSS, FREE, REQUIRED, DATA, DATACOPY, OPTIONS, FILES and FILECNT, and the
; sizes IMAGELEN, BSSLEN, DATALEN, COPYLEN and FILESLEN. Only whole 16-bit
; references are allowed; a jump relative to another blob is an error.
;
; @library CPM22 runtime=1 helpers=1 profile=1
; @profile class=1 kinds=7 base=$0100 limit=$DC00 top=$E406 ccp=$0800
; @profile guard=64 options=3 rst=0 debugger=8192 file=176

BDOS    EQU     $0005
CCPSIZE EQU     $0800
GUARD   EQU     64              ; the profile's guard band
CONSOLE EQU     1               ; the fixed File values
PRINTER EQU     2

; @blob $001 startup STARTUP
; cpm-target §4. The first byte is LD C, never RET.
STARTUP:
        LD      C,26
        LD      DE,DMA_BUF
        CALL    BDOS            ; 1. DMA away from the command tail
        LD      HL,OPTIONS
        LD      A,L
        LD      HL,($0006)      ; 2. usable top
        AND     1
        JR      Z,.TOP
        LD      DE,-(6+CCPSIZE)
        ADD     HL,DE           ; keep-CCP: the CCP base
.TOP:   LD      DE,REQUIRED
        OR      A
        SBC     HL,DE
        JR      C,.NOMEM        ; 3. not enough memory
        ADD     HL,DE
        LD      IX,0
        ADD     IX,SP           ; 4. entry SP, kept while BSS is zeroed
        LD      SP,HL           ; 5. stack at the top
        LD      BC,BSSLEN       ; 6. zero BSS
        LD      A,B
        OR      C
        JR      Z,.NOBSS
        LD      HL,BSS
        LD      (HL),0
        DEC     BC
        LD      A,B
        OR      C
        JR      Z,.NOBSS
        LD      D,H
        LD      E,L
        INC     DE
        LDIR
.NOBSS: LD      (ENTRY_SP),IX
        LD      HL,OPTIONS      ; 7. restore DATA when re-runnable
        BIT     1,L
        JR      Z,.RUN
        LD      BC,COPYLEN
        LD      A,B
        OR      C
        JR      Z,.RUN
        LD      HL,DATACOPY
        LD      DE,DATA
        LDIR
.RUN:   CALL    MAIN            ; 8. main
        JR      C,.FAILED
        LD      DE,$0000
        JP      EXIT            ; 9. exit
.FAILED:                        ; main failed: A = the code (cpm-target §5)
        PUSH    AF
        LD      DE,.FAIL
        CALL    PUTS
        POP     AF
        CALL    PUT_DEC
        LD      DE,.CRLF
        CALL    PUTS
        LD      DE,$FF01
        JP      EXIT
.FAIL:  DB      "FAIL $"
.CRLF:  DB      "\r\n$"
.NOMEM: LD      C,9
        LD      DE,.MSG
        CALL    BDOS
        LD      DE,$FF03
        LD      C,108
        CALL    BDOS
        RET                     ; still on the CCP's stack
.MSG:   DB      "Not enough memory\r\n$"

; @blob $002 code EXIT
; cpm-target §5. DE = return code.
EXIT:   LD      C,108
        CALL    BDOS
        LD      HL,OPTIONS
        BIT     0,L
        JR      NZ,.CCP
        RST     0
.CCP:   LD      SP,(ENTRY_SP)
        RET

; @blob $003 bss ENTRY_SP
ENTRY_SP:
        DS      2

; @blob $004 bss DMA_BUF
DMA_BUF: DS      128

; @blob $005 code TRAP
; cpm-target §10. DE = the reason, $-terminated; the site's return address is
; on top of the stack. Prints "TRAP reason at XXXX" and exits with $FF02.
TRAP:   PUSH    DE
        LD      DE,.HEAD
        CALL    PUTS
        POP     DE
        CALL    PUTS
        LD      DE,.AT
        CALL    PUTS
        POP     HL
        DEC     HL
        DEC     HL
        DEC     HL
        LD      A,H
        CALL    .HEX2
        LD      A,L
        CALL    .HEX2
        LD      DE,.EOL
        CALL    PUTS
        LD      DE,$FF02
        JP      EXIT
.HEX2:  PUSH    AF
        RRCA
        RRCA
        RRCA
        RRCA
        CALL    .HEX1
        POP     AF
.HEX1:  AND     $0F
        ADD     A,$90
        DAA
        ADC     A,$40
        DAA
        JP      CON_OUT
.HEAD:  DB      "TRAP $"
.AT:    DB      " at $"
.EOL:   DB      "\r\n$"

; @blob $006 code PUTS
; Write the $-terminated text at DE.
PUTS:   LD      A,(DE)
        CP      '$'
        RET     Z
        PUSH    DE
        CALL    CON_OUT
        POP     DE
        INC     DE
        JR      PUTS

; @blob $007 code CON_OUT helper=1
; Write the byte in A to the console unchanged (services §3.1). BDOS 6 reads
; $FF as a request for input, so that byte goes to the BIOS's CON_OUT.
; Preserves HL.
CON_OUT: CP      $FF
        JR      Z,.BIOS
        PUSH    HL
        LD      E,A
        LD      C,6
        CALL    BDOS
        POP     HL
        RET
.BIOS:  PUSH    HL
        LD      C,A
        LD      HL,(1)
        LD      DE,9
        ADD     HL,DE
        LD      DE,.BACK
        PUSH    DE
        JP      (HL)
.BACK:  POP     HL
        RET

; @blob $008 code TRAP_BND helper=2
; The bounds reporter. Entered by CALL from a trap site.
TRAP_BND:
        LD      DE,.WHY
        JP      TRAP
.WHY:   DB      "bounds$"

; @blob $009 code RETN helper=2
; The shared epilogue (code generation §3). IY = bytes of arguments to drop.
; Preserves A, F, HL and DE: results and the failure flag.
RETN:   EX      AF,AF'
        LD      SP,IX
        POP     IX
        EXX
        POP     DE              ; the return address
        PUSH    IY
        POP     BC              ; the argument bytes
        LD      HL,0
        ADD     HL,SP
        ADD     HL,BC
        LD      SP,HL
        PUSH    DE
        EXX
        EX      AF,AF'
        RET

; @blob $00A code STK_CHK helper=2
; The activation-capacity check (code generation §7). HL = need(R).
; Traps if SP - need - GUARD would fall below FREE. The site reported is the
; CALL STK_CHK in the routine's prologue.
STK_CHK: EX      DE,HL
        LD      HL,0
        ADD     HL,SP
        OR      A
        SBC     HL,DE
        JR      C,.TRAP
        LD      DE,GUARD
        SBC     HL,DE
        JR      C,.TRAP
        LD      DE,FREE
        SBC     HL,DE
        RET     NC
.TRAP:  JP      TRAP_ACT

; @blob $00B code TRAP_NAR helper=2
TRAP_NAR:
        LD      DE,.WHY
        JP      TRAP
.WHY:   DB      "narrowing$"

; @blob $00C code TRAP_DIV helper=2
TRAP_DIV:
        LD      DE,.WHY
        JP      TRAP
.WHY:   DB      "division-by-zero$"

; @blob $00D code TRAP_FOV helper=2
TRAP_FOV:
        LD      DE,.WHY
        JP      TRAP
.WHY:   DB      "float-overflow$"

; @blob $00E code TRAP_FIN helper=2
TRAP_FIN:
        LD      DE,.WHY
        JP      TRAP
.WHY:   DB      "float-invalid$"

; @blob $00F code TRAP_LOO helper=2
TRAP_LOO:
        LD      DE,.WHY
        JP      TRAP
.WHY:   DB      "loop-range$"

; @blob $010 code TRAP_ACT helper=2
TRAP_ACT:
        LD      DE,.WHY
        JP      TRAP
.WHY:   DB      "activation-capacity$"

; @blob $011 code TRAP_STA helper=2
TRAP_STA:
        LD      DE,.WHY
        JP      TRAP
.WHY:   DB      "stale-handle$"

; @blob $012 code TRAP_CYC helper=2
TRAP_CYC:
        LD      DE,.WHY
        JP      TRAP
.WHY:   DB      "ownership-cycle$"

; @blob $013 code TRAP_POO helper=2
TRAP_POO:
        LD      DE,.WHY
        JP      TRAP
.WHY:   DB      "pool-full$"

; @blob $014 code TRAP_AST helper=2
TRAP_AST:
        LD      DE,.WHY
        JP      TRAP
.WHY:   DB      "assertion$"

; @blob $015 code PUT_DEC helper=2
; Print A in decimal without leading zeros. CON_OUT preserves only HL, so
; the remainder lives in L and the printed-a-digit flag in H.
PUT_DEC: LD      H,0
        LD      B,100
        CALL    .DIGIT
        LD      B,10
        CALL    .DIGIT
        ADD     A,'0'
        JP      CON_OUT
.DIGIT: LD      D,'0'-1
.LOOP:  INC     D
        SUB     B
        JR      NC,.LOOP
        ADD     A,B             ; the remainder
        LD      L,A
        LD      A,D
        CP      '0'
        JR      NZ,.SHOW
        LD      A,H
        OR      A
        LD      A,L
        RET     Z               ; a leading zero: skip it
        LD      A,D
.SHOW:  LD      H,1
        CALL    CON_OUT
        LD      A,L
        RET

; @blob $020 code WR_TEXT helper=1
; writeText(f as File, s as string[]) fails. Stack: IX+4 s address, IX+6
; its capacity, IX+8 f's table address, IX+10 f's generation.
WR_TEXT: PUSH    IX
        LD      IX,0
        ADD     IX,SP
        LD      A,(IX+8)
        LD      H,(IX+9)
        OR      H
        JR      Z,.CLOSED
        LD      A,(IX+8)
        CP      CONSOLE
        JR      NZ,.NOTAV       ; only the console exists yet
        LD      L,(IX+4)
        LD      H,(IX+5)
        LD      B,(HL)          ; the length
        INC     HL
.NEXT:  LD      A,B
        OR      A
        JR      Z,.DONE
        LD      A,(HL)
        PUSH    BC
        PUSH    HL
        CALL    CON_OUT
        POP     HL
        POP     BC
        INC     HL
        DEC     B
        JR      .NEXT
.DONE:  OR      A               ; success: carry clear
        LD      IY,8
        JP      RETN
.CLOSED:
        LD      A,9             ; fileClosed
        JR      .FAIL
.NOTAV: LD      A,15            ; notAvailable
.FAIL:  SCF
        LD      IY,8
        JP      RETN

; @blob $021 code WR_BYTE helper=1
; writeByte(f as File, b as u8) fails. Stack: IX+4 b, IX+6 f address,
; IX+8 f generation.
WR_BYTE: PUSH    IX
        LD      IX,0
        ADD     IX,SP
        LD      A,(IX+6)
        LD      H,(IX+7)
        OR      H
        JR      Z,.CLOSED
        LD      A,(IX+6)
        CP      CONSOLE
        JR      NZ,.NOTAV
        LD      A,(IX+4)
        CALL    CON_OUT
        OR      A
        LD      IY,6
        JP      RETN
.CLOSED:
        LD      A,9
        JR      .FAIL
.NOTAV: LD      A,15
.FAIL:  SCF
        LD      IY,6
        JP      RETN

; @blob $022 code WR_OUT helper=1
; writeOutputByte(b as u8) fails: Nucleus's shorthand for writeByte(console, b).
WR_OUT: PUSH    IX
        LD      IX,0
        ADD     IX,SP
        LD      A,(IX+4)
        CALL    CON_OUT
        OR      A
        LD      IY,2
        JP      RETN
