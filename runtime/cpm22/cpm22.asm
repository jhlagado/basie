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

; @blob $016 code MUL16 helper=2
; HL = HL * DE modulo 65536. The low 16 bits are the same for signed and
; unsigned operands, so one helper serves every 16-bit multiply (D5).
; Uses A and BC. Stack: 2.
MUL16:  LD      B,H
        LD      C,L             ; BC = the left operand
        LD      HL,0
        LD      A,16
.LOOP:  ADD     HL,HL           ; the product so far, doubled
        EX      DE,HL
        ADD     HL,HL           ; the right operand's next bit into carry
        EX      DE,HL
        JR      NC,.SKIP
        ADD     HL,BC
.SKIP:  DEC     A
        JR      NZ,.LOOP
        RET

; @blob $017 code DIV16 helper=2
; Unsigned: HL = HL / DE, DE = HL mod DE. A zero divisor traps with
; division-by-zero, reporting the program's call (code generation §6).
; Uses A and BC. Stack: 2.
DIV16:  LD      A,D
        OR      E
        JP      Z,TRAP_DIV      ; the stack holds only the return address
        LD      B,D
        LD      C,E             ; BC = the divisor
        EX      DE,HL           ; DE = the dividend, becoming the quotient
        LD      HL,0            ; HL = the remainder
        LD      A,16
.LOOP:  EX      DE,HL
        ADD     HL,HL           ; the dividend's top bit into carry
        EX      DE,HL
        ADC     HL,HL           ; remainder = remainder * 2 + bit
        JR      C,.SUB          ; a 17th bit: the subtraction can't borrow
        SBC     HL,BC           ; carry is clear here
        JR      NC,.SET
        ADD     HL,BC           ; too small: restore, quotient bit 0
        JR      .NEXT
.SUB:   OR      A
        SBC     HL,BC
.SET:   INC     E               ; quotient bit 0 = 1; E is even after the shift
.NEXT:  DEC     A
        JR      NZ,.LOOP
        EX      DE,HL           ; HL = the quotient, DE = the remainder
        RET

; @blob $018 code DIV16S helper=2
; Signed: HL = HL / DE truncating toward zero; DE = the remainder, with the
; dividend's sign (spec §9.8). -32768 / -1 wraps to -32768. Stack: 8.
DIV16S: LD      A,D
        OR      E
        JP      Z,TRAP_DIV      ; before anything is pushed
        LD      A,H
        XOR     D
        PUSH    AF              ; bit 7: the quotient is negative
        LD      A,H
        OR      A               ; LD sets no flags: the sign flag needs OR
        PUSH    AF              ; sign flag: the remainder is negative
        BIT     7,H
        JR      Z,.POSL
        XOR     A
        SUB     L
        LD      L,A
        SBC     A,A
        SUB     H
        LD      H,A
.POSL:  BIT     7,D
        JR      Z,.POSR
        XOR     A
        SUB     E
        LD      E,A
        SBC     A,A
        SUB     D
        LD      D,A
.POSR:  CALL    DIV16
        POP     AF
        JP      P,.REMOK
        XOR     A
        SUB     E
        LD      E,A
        SBC     A,A
        SUB     D
        LD      D,A
.REMOK: POP     AF
        RET     P
        XOR     A
        SUB     L
        LD      L,A
        SBC     A,A
        SUB     H
        LD      H,A
        RET

; @blob $019 code STR_SETL helper=2
; Set a string's length: HL = the string, E = the new length, D = its
; capacity. A length beyond the capacity traps with bounds. Bytes exposed by
; a longer length are zeroed (D25). Uses A, BC, DE. Stack: 4.
STR_SETL:
        LD      A,E
        CP      D
        JR      C,.OK
        JR      Z,.OK
        JP      TRAP_BND
.OK:    LD      C,E             ; the new length
        LD      A,(HL)          ; the old length
        CP      C
        JR      NC,.STORE       ; not growing
        PUSH    HL
        LD      B,A
        LD      A,C
        SUB     B               ; the bytes to zero
        LD      D,0
        LD      E,B
        ADD     HL,DE
        INC     HL              ; the first exposed byte
        LD      B,A
.ZERO:  LD      (HL),0
        INC     HL
        DJNZ    .ZERO
        POP     HL
.STORE: LD      (HL),C
        RET

; ---------------------------------------------------------------------------
; Pools (memory safety §5). A pool has an 8-byte info block in rodata:
;   +0 storage address  +2 slot size  +4 capacity  +6 descriptor, or 0
; and storage in bss:
;   +0 high-water count  +2 free-list head  +4 free-list tail  +6 slots
; Each slot is a 6-byte header, then the record: generation at R-6, the owner
; link at R-4, the pool info at R-2, where R is the record address that a
; handle holds. The free list and the free cascade's work list are threaded
; through the link words. A descriptor lists a record type's owning fields:
;   count (u8), then entries: kind (u8: 0 field, 1 array), offset (u16),
;   and for an array its stride (u16) and count (u16).
; ---------------------------------------------------------------------------

; @blob $01A bss POOL_VAR
; +0 the work list head, +2 array pointer, +4 stride, +6 count.
POOL_VAR:
        DS      8

; @blob $01B code POOL_TRY helper=2
; HL = pool info. Returns HL = a zeroed record, or 0 when the pool is full.
; Takes the oldest free slot, else the next never-used one. Stack: 10.
POOL_TRY:
        PUSH    HL              ; the info
        LD      E,(HL)
        INC     HL
        LD      D,(HL)
        EX      DE,HL           ; HL = storage
        INC     HL
        INC     HL              ; &head
        LD      E,(HL)
        INC     HL
        LD      D,(HL)          ; DE = head, or 0
        LD      A,D
        OR      E
        JR      Z,.FRESH
        PUSH    HL              ; &head+1
        EX      DE,HL           ; HL = R
        PUSH    HL
        DEC     HL
        DEC     HL
        DEC     HL
        DEC     HL              ; &link
        LD      C,(HL)
        INC     HL
        LD      B,(HL)          ; BC = the next free slot
        POP     DE              ; R
        POP     HL              ; &head+1
        LD      (HL),B
        DEC     HL
        LD      (HL),C          ; head = next
        EX      DE,HL           ; HL = R
        POP     DE              ; the info
        JR      .INIT
.FRESH: DEC     HL
        DEC     HL
        DEC     HL              ; HL = storage = &count
        LD      C,(HL)
        INC     HL
        LD      B,(HL)          ; BC = the count used
        POP     DE              ; the info
        PUSH    DE
        PUSH    HL              ; &count+1
        EX      DE,HL           ; HL = info
        INC     HL
        INC     HL
        INC     HL
        INC     HL              ; &capacity
        LD      E,(HL)
        INC     HL
        LD      D,(HL)          ; DE = capacity
        LD      A,B
        CP      D
        JR      NZ,.ROOM
        LD      A,C
        CP      E
        JR      NZ,.ROOM
        POP     HL
        POP     HL
        LD      HL,0            ; full
        RET
.ROOM:  DEC     HL
        DEC     HL
        DEC     HL              ; &slot size
        LD      E,(HL)
        INC     HL
        LD      D,(HL)          ; DE = slot size
        LD      H,B
        LD      L,C
        CALL    MUL16           ; HL = count * slot size
        POP     DE              ; &count+1
        PUSH    HL
        EX      DE,HL
        DEC     HL              ; &count
        INC     (HL)
        JR      NZ,.NOCARRY
        INC     HL
        INC     (HL)
        DEC     HL
.NOCARRY:
        LD      DE,12           ; past the storage header and the slot header
        ADD     HL,DE
        POP     DE
        ADD     HL,DE           ; HL = R
        POP     DE              ; the info
        PUSH    HL
        LD      BC,6
        OR      A
        SBC     HL,BC           ; &generation
        LD      (HL),1
        INC     HL
        LD      (HL),0
        POP     HL
.INIT:  PUSH    HL              ; R; DE = info
        DEC     HL
        DEC     HL
        DEC     HL
        DEC     HL              ; &link
        LD      (HL),0
        INC     HL
        LD      (HL),0
        INC     HL              ; &pool
        LD      (HL),E
        INC     HL
        LD      (HL),D
        EX      DE,HL           ; HL = info
        INC     HL
        INC     HL
        LD      C,(HL)
        INC     HL
        LD      B,(HL)          ; BC = slot size
        LD      HL,-6
        ADD     HL,BC
        LD      B,H
        LD      C,L             ; BC = the record size, at least 1
        POP     HL
        PUSH    HL
        LD      (HL),0
        DEC     BC
        LD      A,B
        OR      C
        JR      Z,.DONE
        LD      D,H
        LD      E,L
        INC     DE
        LDIR
.DONE:  POP     HL
        RET

; @blob $01C code POOL_DEL helper=2
; HL = a record. Frees it and everything it owns, without recursion: a work
; list threaded through the link words (memory safety §5.10). A child is
; freed only when its link names the slot being freed. Uses IY. Stack: 8.
POOL_DEL:
        PUSH    HL
        DEC     HL
        DEC     HL
        DEC     HL
        DEC     HL
        LD      (HL),0
        INC     HL
        LD      (HL),0
        POP     HL
        LD      (POOL_VAR),HL   ; the list: just this record
.NEXT:  LD      HL,(POOL_VAR)
        LD      A,H
        OR      L
        RET     Z
        PUSH    HL
        POP     IY              ; IY = R, the record being freed
        LD      E,(IY-4)
        LD      D,(IY-3)
        LD      (POOL_VAR),DE   ; pop it
        LD      L,(IY-2)
        LD      H,(IY-1)        ; HL = its pool info
        PUSH    HL
        LD      DE,6
        ADD     HL,DE
        LD      E,(HL)
        INC     HL
        LD      D,(HL)          ; DE = descriptor
        LD      A,D
        OR      E
        JP      Z,.RETURN
        EX      DE,HL
        LD      B,(HL)          ; the entry count
        INC     HL
.ENTRY: LD      A,(HL)          ; the kind
        INC     HL
        LD      E,(HL)
        INC     HL
        LD      D,(HL)
        INC     HL              ; DE = offset
        OR      A
        JR      NZ,.ARRAY
        PUSH    HL
        PUSH    BC
        PUSH    IY
        POP     HL
        ADD     HL,DE           ; &field
        CALL    .CHILD
        POP     BC
        POP     HL
        DJNZ    .ENTRY
        JP      .RETURN
.ARRAY: PUSH    HL
        PUSH    IY
        POP     HL
        ADD     HL,DE
        LD      (POOL_VAR+2),HL ; the first element's field
        POP     HL
        LD      E,(HL)
        INC     HL
        LD      D,(HL)
        INC     HL
        LD      (POOL_VAR+4),DE ; the stride
        LD      E,(HL)
        INC     HL
        LD      D,(HL)
        INC     HL
        LD      (POOL_VAR+6),DE ; the count
        PUSH    HL
        PUSH    BC
.EACH:  LD      HL,(POOL_VAR+2)
        CALL    .CHILD
        LD      HL,(POOL_VAR+2)
        LD      DE,(POOL_VAR+4)
        ADD     HL,DE
        LD      (POOL_VAR+2),HL
        LD      HL,(POOL_VAR+6)
        DEC     HL
        LD      (POOL_VAR+6),HL
        LD      A,H
        OR      L
        JR      NZ,.EACH
        POP     BC
        POP     HL
        DJNZ    .ENTRY
.RETURN:
        POP     HL              ; the pool info
        LD      E,(HL)
        INC     HL
        LD      D,(HL)          ; DE = storage
        LD      L,(IY-6)
        LD      H,(IY-5)
        INC     HL              ; the generation advances
        LD      (IY-6),L
        LD      (IY-5),H
        LD      A,H
        AND     L
        INC     A
        JP      Z,.NEXT         ; $FFFF: withdrawn, never reused
        LD      (IY-4),0
        LD      (IY-3),0        ; the slot ends the free list
        EX      DE,HL           ; HL = storage
        INC     HL
        INC     HL              ; &head
        LD      E,(HL)
        INC     HL
        LD      D,(HL)          ; DE = head; HL = &head+1
        LD      A,D
        OR      E
        JR      NZ,.TAIL
        PUSH    IY
        POP     DE
        LD      (HL),D
        DEC     HL
        LD      (HL),E          ; head = R
        INC     HL
        INC     HL
        INC     HL              ; &tail
        LD      (HL),E
        INC     HL
        LD      (HL),D          ; tail = R
        JP      .NEXT
.TAIL:  INC     HL
        LD      E,(HL)
        INC     HL
        LD      D,(HL)          ; DE = tail; HL = &tail+1
        PUSH    HL
        EX      DE,HL           ; HL = the tail record
        DEC     HL
        DEC     HL
        DEC     HL
        DEC     HL              ; &tail.link
        PUSH    IY
        POP     DE
        LD      (HL),E
        INC     HL
        LD      (HL),D          ; tail.link = R
        POP     HL
        LD      (HL),D
        DEC     HL
        LD      (HL),E          ; tail = R
        JP      .NEXT
; HL = &field holding an owning handle. Pushes the child on the work list
; when its link names the record being freed.
.CHILD: LD      E,(HL)
        INC     HL
        LD      D,(HL)
        LD      A,D
        OR      E
        RET     Z
        EX      DE,HL           ; HL = the child
        PUSH    HL
        DEC     HL
        DEC     HL
        DEC     HL
        DEC     HL              ; &child.link
        LD      E,(HL)
        INC     HL
        LD      D,(HL)          ; DE = child.link
        PUSH    IY
        POP     BC
        LD      A,D
        CP      B
        JR      NZ,.NOTOURS
        LD      A,E
        CP      C
        JR      NZ,.NOTOURS
        LD      DE,(POOL_VAR)
        LD      (HL),D
        DEC     HL
        LD      (HL),E          ; child.link = the old head
        POP     HL
        LD      (POOL_VAR),HL   ; head = the child
        RET
.NOTOURS:
        POP     HL
        RET

; @blob $01D code OBJ_FREE helper=2
; HL = an object outside any pool (a local aggregate), DE = its descriptor.
; Frees the handles in its owning fields and stores none in them.
; Stack: 12 (calls POOL_DEL).
OBJ_FREE:
        PUSH    HL
        POP     IY              ; IY = the object
        EX      DE,HL           ; HL = descriptor
        LD      B,(HL)
        INC     HL
.ENTRY: LD      A,(HL)
        INC     HL
        LD      E,(HL)
        INC     HL
        LD      D,(HL)
        INC     HL
        OR      A
        JR      NZ,.ARRAY
        PUSH    HL
        PUSH    BC
        PUSH    IY
        POP     HL
        ADD     HL,DE
        CALL    .FIELD
        POP     BC
        POP     HL
        DJNZ    .ENTRY
        RET
.ARRAY: PUSH    HL
        PUSH    IY
        POP     HL
        ADD     HL,DE
        LD      (POOL_VAR+2),HL
        POP     HL
        LD      E,(HL)
        INC     HL
        LD      D,(HL)
        INC     HL
        LD      (POOL_VAR+4),DE
        LD      E,(HL)
        INC     HL
        LD      D,(HL)
        INC     HL
        LD      (POOL_VAR+6),DE
        PUSH    HL
        PUSH    BC
.EACH:  LD      HL,(POOL_VAR+2)
        CALL    .FIELD
        LD      HL,(POOL_VAR+2)
        LD      DE,(POOL_VAR+4)
        ADD     HL,DE
        LD      (POOL_VAR+2),HL
        LD      HL,(POOL_VAR+6)
        DEC     HL
        LD      (POOL_VAR+6),HL
        LD      A,H
        OR      L
        JR      NZ,.EACH
        POP     BC
        POP     HL
        DJNZ    .ENTRY
        RET
.FIELD: LD      E,(HL)
        INC     HL
        LD      D,(HL)
        LD      A,D
        OR      E
        RET     Z
        LD      (HL),0
        DEC     HL
        LD      (HL),0          ; none
        PUSH    IY
        EX      DE,HL
        CALL    POOL_DEL       ; clobbers IY and the array state
        POP     IY
        RET

; @blob $01E code ID_CHK helper=2
; HL = an identifier's address, DE = its generation. Traps stale-handle
; unless the slot is still that occupant. Preserves HL and DE. Stack: 4.
ID_CHK: LD      A,H
        OR      L
        JP      Z,TRAP_STA
        PUSH    HL
        LD      BC,6
        OR      A
        SBC     HL,BC
        LD      A,(HL)
        CP      E
        JR      NZ,.STALE
        INC     HL
        LD      A,(HL)
        CP      D
        JR      NZ,.STALE
        POP     HL
        RET
.STALE: POP     HL
        JP      TRAP_STA

; @blob $01F code ID_TEST helper=2
; HL = address, DE = generation. Returns Z when the identifier is none or
; stale, NZ when live. Preserves HL and DE. Never traps. Stack: 4.
ID_TEST:
        LD      A,H
        OR      L
        RET     Z
        PUSH    HL
        LD      BC,6
        OR      A
        SBC     HL,BC
        LD      A,(HL)
        CP      E
        JR      NZ,.STALE
        INC     HL
        LD      A,(HL)
        CP      D
        JR      NZ,.STALE
        POP     HL
        OR      1               ; NZ
        RET
.STALE: POP     HL
        XOR     A               ; Z
        RET

; @blob $023 code OWN_SET helper=2
; Store an owning handle: HL = the new value or 0, DE = the location,
; BC = the owning record or 0. Frees the old value first (memory safety
; §5.3), then stores, then sets the new value's link. Stack: 14.
OWN_SET:
        PUSH    HL
        PUSH    DE
        PUSH    BC
        EX      DE,HL
        LD      E,(HL)
        INC     HL
        LD      D,(HL)          ; the old value
        LD      A,D
        OR      E
        JR      Z,.STORE
        EX      DE,HL
        CALL    POOL_DEL
.STORE: POP     BC
        POP     HL              ; the location
        POP     DE              ; the value
        LD      (HL),E
        INC     HL
        LD      (HL),D
        LD      A,D
        OR      E
        RET     Z
        EX      DE,HL           ; HL = the value
        DEC     HL
        DEC     HL
        DEC     HL
        DEC     HL
        LD      (HL),C
        INC     HL
        LD      (HL),B          ; its link = the owner
        RET

; @blob $024 code OWN_SETC helper=2
; As OWN_SET, after the cycle check (memory safety §5.9): the owner BC and
; its owners must not include the value. Traps ownership-cycle before any
; change. Stack: 16.
OWN_SETC:
        LD      A,H
        OR      L
        JP      Z,OWN_SET       ; none makes no cycle
        PUSH    HL
        PUSH    DE
        LD      D,B
        LD      E,C             ; DE walks up from the owner
.WALK:  LD      A,D
        OR      E
        JR      Z,.CLEAR
        LD      A,D
        CP      H
        JR      NZ,.UP
        LD      A,E
        CP      L
        JR      NZ,.UP
        POP     DE
        POP     HL
        JP      TRAP_CYC
.UP:    EX      DE,HL
        DEC     HL
        DEC     HL
        DEC     HL
        DEC     HL
        LD      A,(HL)
        INC     HL
        LD      H,(HL)
        LD      L,A             ; HL = its owner
        EX      DE,HL
        JR      .WALK
.CLEAR: POP     DE
        POP     HL
        JP      OWN_SET

; @blob $025 code LINK0 helper=2
; HL = an owning handle or 0. Clears its owner link: the value is now held
; by a local, a parameter or a temporary (memory safety §5.9). Preserves
; HL and DE. Stack: 4.
LINK0:  LD      A,H
        OR      L
        RET     Z
        PUSH    HL
        DEC     HL
        DEC     HL
        DEC     HL
        DEC     HL
        LD      (HL),0
        INC     HL
        LD      (HL),0
        POP     HL
        RET

; @blob $026 code ID_MAKE helper=2
; HL = an owning handle or 0. Returns the identifier DEHL: DE = the slot's
; generation, or 0 for none. Stack: 4.
ID_MAKE:
        LD      DE,0
        LD      A,H
        OR      L
        RET     Z
        PUSH    HL
        LD      BC,6
        OR      A
        SBC     HL,BC
        LD      E,(HL)
        INC     HL
        LD      D,(HL)
        POP     HL
        RET
