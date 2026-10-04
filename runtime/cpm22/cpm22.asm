; Baton runtime for CP/M 2.2: the minimal library (roadmap step 31).
;
; Built into CPM22.BRL by tools/brl.ts. Each blob starts at a "; @blob" line:
;
;   ; @blob ORDINAL KIND NAME [align=N] [helper=CC] [since=V]
;
; and runs to the next one. A blob refers to another by its first label, and
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

; @blob $001 startup STARTUP
; cpm-target §4. The first byte is LD C, never RET.
STARTUP:
        LD      C,26
        LD      DE,DMABUF
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
.NOBSS: LD      (ENTRYSP),IX
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
        LD      DE,$0000
        JP      EXIT            ; 9. exit
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
.CCP:   LD      SP,(ENTRYSP)
        RET

; @blob $003 bss ENTRYSP
ENTRYSP:
        DS      2

; @blob $004 bss DMABUF
DMABUF: DS      128

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
        JP      CONOUT
.HEAD:  DB      "TRAP $"
.AT:    DB      " at $"
.EOL:   DB      "\r\n$"

; @blob $006 code PUTS
; Write the $-terminated text at DE.
PUTS:   LD      A,(DE)
        CP      '$'
        RET     Z
        PUSH    DE
        CALL    CONOUT
        POP     DE
        INC     DE
        JR      PUTS

; @blob $007 code CONOUT helper=1
; Write the byte in A to the console unchanged (services §3.1). BDOS 6 reads
; $FF as a request for input, so that byte goes to the BIOS's CONOUT.
; Preserves HL.
CONOUT: CP      $FF
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

; @blob $008 code TRAPBND helper=2
; The bounds reporter. Entered by CALL from a trap site.
TRAPBND:
        LD      DE,.WHY
        JP      TRAP
.WHY:   DB      "bounds$"
