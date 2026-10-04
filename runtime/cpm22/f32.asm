; ---------------------------------------------------------------------------
; f32 (D7, spec §9.9): IEEE single bit patterns in DEHL. D holds the sign and
; the exponent's top 7 bits, E the exponent's low bit and the mantissa's top 7
; bits, HL the mantissa's low 16 bits. Round to nearest, ties to even; flush
; to zero; no infinity or NaN: a result too large traps float-overflow.
;
; Binary helpers take the left operand in DEHL and the right in DE'HL' (code
; generation §4) and return DEHL. Scratch, FP_VAR:
;   +0..+3  M: the working mantissa, the hidden bit at bit 30, guard bits 6..0
;   +4..+7  N: the right operand's mantissa, the same layout
;   +8, +9  the exponents XA, XB        +10, +11  the signs SA, SB (bit 7)
;   +12     the result's sign           +13, +14  the result's exponent, i16
;   +16..+23 a product or quotient work area
; ---------------------------------------------------------------------------

; @blob $036 bss FP_VAR
FP_VAR: DS      24

; @blob $037 code FP_UNPK helper=2
; Unpack DEHL into M, XA, SA and DE'HL' into N, XB, SB. Leaves IY = FP_VAR
; and DEHL intact. Stack: 8.
FP_UNPK:
        LD      IY,FP_VAR
        PUSH    DE
        PUSH    HL
        CALL    .ONE
        LD      (IY+8),A
        LD      (IY+10),C
        LD      (IY+0),L
        LD      (IY+1),H
        LD      (IY+2),E
        LD      (IY+3),D
        EXX
        PUSH    DE
        PUSH    HL
        CALL    .ONE
        LD      (IY+9),A
        LD      (IY+11),C
        LD      (IY+4),L
        LD      (IY+5),H
        LD      (IY+6),E
        LD      (IY+7),D
        POP     HL
        POP     DE
        EXX
        POP     HL
        POP     DE
        RET
; DEHL = a value. Returns A = its exponent, C = its sign bit, DEHL = its
; mantissa with the hidden bit at bit 30, or 0 for a zero exponent.
.ONE:   LD      A,D
        AND     $80
        LD      C,A
        LD      A,D
        ADD     A,A
        LD      B,A
        LD      A,E
        RLA                     ; carry = the exponent's low bit
        LD      A,B
        ADC     A,0             ; A = the exponent
        OR      A
        JR      Z,.ZERO
        SET     7,E             ; the hidden bit
        LD      D,0
        LD      B,7
.SHIFT: ADD     HL,HL
        RL      E
        RL      D
        DJNZ    .SHIFT
        RET
.ZERO:  LD      HL,0
        LD      DE,0
        RET

; @blob $038 code FP_SHR helper=2
; N >>= A, with the bits shifted out gathered into a sticky bit 0. Stack: 2.
FP_SHR: OR      A
        RET     Z
        CP      32
        JR      NC,.ALL
        LD      B,A
.LOOP:  SRL     (IY+7)
        RR      (IY+6)
        RR      (IY+5)
        RR      (IY+4)
        JR      NC,.NEXT
        SET     0,(IY+4)
.NEXT:  DJNZ    .LOOP
        RET
.ALL:   LD      A,(IY+4)
        OR      (IY+5)
        OR      (IY+6)
        OR      (IY+7)
        LD      (IY+7),0
        LD      (IY+6),0
        LD      (IY+5),0
        LD      (IY+4),0
        RET     Z
        LD      (IY+4),1        ; something was there: sticky
        RET

; @blob $039 code FP_PACK helper=2
; Normalize M (shifting left, or once right from bit 31), round to nearest
; even on the guard bits, and pack with the sign at +12 and the exponent at
; +13. Returns DEHL, with carry set when the exponent overflows. Stack: 2.
FP_PACK:
        LD      A,(IY+0)
        OR      (IY+1)
        OR      (IY+2)
        OR      (IY+3)
        JP      Z,.ZERO
        BIT     7,(IY+3)
        JR      Z,.NORM
        SRL     (IY+3)
        RR      (IY+2)
        RR      (IY+1)
        RR      (IY+0)
        JR      NC,.UP1
        SET     0,(IY+0)
.UP1:   INC     (IY+13)
        JR      NZ,.NORM
        INC     (IY+14)
.NORM:  BIT     6,(IY+3)
        JR      NZ,.ROUND
        SLA     (IY+0)
        RL      (IY+1)
        RL      (IY+2)
        RL      (IY+3)
        LD      A,(IY+13)
        SUB     1
        LD      (IY+13),A
        JR      NC,.NORM
        DEC     (IY+14)
        JR      .NORM
.ROUND: LD      A,(IY+0)
        AND     $7F
        CP      $40
        JR      C,.DONE         ; below half
        JR      NZ,.UP          ; above half
        BIT     7,(IY+0)
        JR      Z,.DONE         ; a tie: already even
.UP:    LD      A,(IY+0)
        ADD     A,$80
        LD      (IY+0),A
        JR      NC,.DONE
        INC     (IY+1)
        JR      NZ,.DONE
        INC     (IY+2)
        JR      NZ,.DONE
        INC     (IY+3)
        BIT     7,(IY+3)
        JR      Z,.DONE
        SRL     (IY+3)          ; the mantissa rolled over to a power of two
        RR      (IY+2)
        RR      (IY+1)
        RR      (IY+0)
        INC     (IY+13)
        JR      NZ,.DONE
        INC     (IY+14)
.DONE:  LD      A,(IY+14)
        OR      A
        JP      M,.ZERO         ; a negative exponent: flushed
        JR      NZ,.OVER
        LD      A,(IY+13)
        OR      A
        JR      Z,.ZERO
        CP      $FF
        JR      Z,.OVER
        LD      L,(IY+0)
        LD      H,(IY+1)
        LD      E,(IY+2)
        LD      D,(IY+3)
        LD      B,7
.SHIFT: SRL     D
        RR      E
        RR      H
        RR      L
        DJNZ    .SHIFT
        LD      A,E
        AND     $7F             ; drop the hidden bit
        LD      E,A
        LD      A,(IY+13)
        RRCA                    ; the exponent's low bit into bit 7
        AND     $80
        OR      E
        LD      E,A
        LD      A,(IY+13)
        SRL     A
        OR      (IY+12)
        LD      D,A
        OR      A               ; carry clear
        RET
.ZERO:  LD      HL,0
        LD      E,0
        LD      D,(IY+12)
        OR      A
        RET
.OVER:  SCF
        RET

; @blob $03A code FADD helper=2
; DEHL = DEHL + DE'HL'. Stack: 12.
FADD:   CALL    FP_UNPK
        LD      A,(IY+8)
        OR      A
        JR      NZ,.ANZ
        LD      A,(IY+9)
        OR      A
        JR      NZ,.RIGHT
        LD      A,(IY+10)       ; both zero: negative only when both are
        AND     (IY+11)
        LD      D,A
        LD      E,0
        LD      HL,0
        RET
.RIGHT: EXX                     ; the left is zero: the right, as it is
        PUSH    HL
        PUSH    DE
        EXX
        POP     DE
        POP     HL
        RET
.ANZ:   LD      A,(IY+9)
        OR      A
        RET     Z               ; the right is zero: the left, in DEHL still
        LD      A,(IY+8)
        CP      (IY+9)
        JR      NC,.ORDER
        CALL    .SWAP
.ORDER: LD      A,(IY+8)
        SUB     (IY+9)
        CALL    FP_SHR          ; align the smaller operand
        LD      A,(IY+8)
        LD      (IY+13),A
        LD      (IY+14),0
        LD      A,(IY+10)
        LD      (IY+12),A
        XOR     (IY+11)
        AND     $80
        JR      NZ,.SUB
        LD      L,(IY+0)        ; the same sign: add
        LD      H,(IY+1)
        LD      C,(IY+4)
        LD      B,(IY+5)
        ADD     HL,BC
        LD      (IY+0),L
        LD      (IY+1),H
        LD      L,(IY+2)
        LD      H,(IY+3)
        LD      C,(IY+6)
        LD      B,(IY+7)
        ADC     HL,BC
        LD      (IY+2),L
        LD      (IY+3),H
        JR      .PACK
.SUB:   LD      L,(IY+0)        ; different signs: M - N
        LD      H,(IY+1)
        LD      C,(IY+4)
        LD      B,(IY+5)
        OR      A
        SBC     HL,BC
        LD      (IY+0),L
        LD      (IY+1),H
        LD      L,(IY+2)
        LD      H,(IY+3)
        LD      C,(IY+6)
        LD      B,(IY+7)
        SBC     HL,BC
        LD      (IY+2),L
        LD      (IY+3),H
        JR      NC,.POS
        XOR     A               ; N was larger: negate, take its sign
        SUB     (IY+0)
        LD      (IY+0),A
        LD      A,0
        SBC     A,(IY+1)
        LD      (IY+1),A
        LD      A,0
        SBC     A,(IY+2)
        LD      (IY+2),A
        LD      A,0
        SBC     A,(IY+3)
        LD      (IY+3),A
        LD      A,(IY+11)
        LD      (IY+12),A
.POS:   LD      A,(IY+0)
        OR      (IY+1)
        OR      (IY+2)
        OR      (IY+3)
        JR      NZ,.PACK
        LD      (IY+12),0       ; x - x is +0
.PACK:  CALL    FP_PACK
        JP      C,TRAP_FOV
        RET
; Exchange the two unpacked operands.
.SWAP:  LD      B,4
        PUSH    IY
        POP     HL              ; HL = &M
        LD      D,H
        LD      E,L
        INC     DE
        INC     DE
        INC     DE
        INC     DE              ; DE = &N
.SW:    LD      A,(DE)
        LD      C,(HL)
        LD      (HL),A
        LD      A,C
        LD      (DE),A
        INC     HL
        INC     DE
        DJNZ    .SW
        LD      A,(IY+8)
        LD      C,(IY+9)
        LD      (IY+8),C
        LD      (IY+9),A
        LD      A,(IY+10)
        LD      C,(IY+11)
        LD      (IY+10),C
        LD      (IY+11),A
        RET

; @blob $03B code FSUB helper=2
; DEHL = DEHL - DE'HL': negate the right and add. Stack: 12.
FSUB:   EXX
        LD      A,D
        XOR     $80
        LD      D,A
        EXX
        JP      FADD

; @blob $03C code FMUL helper=2
; DEHL = DEHL * DE'HL'. Stack: 12.
FMUL:   CALL    FP_UNPK
        LD      A,(IY+10)
        XOR     (IY+11)
        LD      (IY+12),A
        LD      A,(IY+8)
        OR      A
        JP      Z,.ZERO
        LD      A,(IY+9)
        OR      A
        JP      Z,.ZERO
        LD      L,(IY+8)        ; exponent = XA + XB - 127
        LD      H,0
        LD      E,(IY+9)
        LD      D,0
        ADD     HL,DE
        LD      DE,-127
        ADD     HL,DE
        LD      (IY+13),L
        LD      (IY+14),H
        LD      A,7             ; a = M >> 7, b = N >> 7: the 24-bit mantissas
        CALL    .SHRM
        LD      A,7
        CALL    FP_SHR
        LD      B,6             ; the 48-bit product P at +16..+21
        PUSH    IY
        POP     HL
        LD      DE,16
        ADD     HL,DE
.CLEAR: LD      (HL),0
        INC     HL
        DJNZ    .CLEAR
        LD      B,24
.LOOP:  CALL    .SHLP           ; P <<= 1
        SLA     (IY+0)          ; a's next bit, from the top
        RL      (IY+1)
        RL      (IY+2)
        JR      NC,.NEXT
        LD      A,(IY+16)       ; P += b
        ADD     A,(IY+4)
        LD      (IY+16),A
        LD      A,(IY+17)
        ADC     A,(IY+5)
        LD      (IY+17),A
        LD      A,(IY+18)
        ADC     A,(IY+6)
        LD      (IY+18),A
        LD      A,(IY+19)
        ADC     A,0
        LD      (IY+19),A
        LD      A,(IY+20)
        ADC     A,0
        LD      (IY+20),A
        LD      A,(IY+21)
        ADC     A,0
        LD      (IY+21),A
.NEXT:  DJNZ    .LOOP
        ; P is in [2^46, 2^48). Bring its top bit to bit 30 of M with the
        ; rest as guard bits: M = P >> 16 (hidden at 46) or P >> 17 (at 47).
        LD      A,16
        BIT     7,(IY+21)
        JR      Z,.ALIGN
        INC     A
        INC     (IY+13)
        JR      NZ,.ALIGN
        INC     (IY+14)
.ALIGN: LD      B,A
        LD      C,0             ; sticky
.SH:    SRL     (IY+21)
        RR      (IY+20)
        RR      (IY+19)
        RR      (IY+18)
        RR      (IY+17)
        RR      (IY+16)
        JR      NC,.SHN
        LD      C,1
.SHN:   DJNZ    .SH
        LD      A,(IY+16)
        OR      C
        LD      (IY+0),A
        LD      A,(IY+17)
        LD      (IY+1),A
        LD      A,(IY+18)
        LD      (IY+2),A
        LD      A,(IY+19)
        LD      (IY+3),A
        CALL    FP_PACK
        JP      C,TRAP_FOV
        RET
.ZERO:  LD      HL,0
        LD      E,0
        LD      D,(IY+12)
        RET
; M >>= A (no sticky needed: the low 7 bits are zero).
.SHRM:  LD      B,A
.SM:    SRL     (IY+3)
        RR      (IY+2)
        RR      (IY+1)
        RR      (IY+0)
        DJNZ    .SM
        RET
.SHLP:  SLA     (IY+16)
        RL      (IY+17)
        RL      (IY+18)
        RL      (IY+19)
        RL      (IY+20)
        RL      (IY+21)
        RET

; @blob $03D code FDIV helper=2
; DEHL = DEHL / DE'HL'. A zero divisor traps division-by-zero. Stack: 12.
FDIV:   CALL    FP_UNPK
        LD      A,(IY+9)
        OR      A
        JP      Z,TRAP_DIV
        LD      A,(IY+10)
        XOR     (IY+11)
        LD      (IY+12),A
        LD      A,(IY+8)
        OR      A
        JP      Z,.ZERO
        LD      L,(IY+8)        ; exponent = XA - XB + 127
        LD      H,0
        LD      E,(IY+9)
        LD      D,0
        OR      A
        SBC     HL,DE
        LD      DE,127
        ADD     HL,DE
        LD      (IY+13),L
        LD      (IY+14),H
        LD      B,7             ; a = M >> 7, b = N >> 7
.SA:    SRL     (IY+3)
        RR      (IY+2)
        RR      (IY+1)
        RR      (IY+0)
        DJNZ    .SA
        LD      A,7
        CALL    FP_SHR
        ; R = a (at +16..+19), Q = 0 (at +20..+23); 27 quotient bits.
        LD      A,(IY+0)
        LD      (IY+16),A
        LD      A,(IY+1)
        LD      (IY+17),A
        LD      A,(IY+2)
        LD      (IY+18),A
        LD      (IY+19),0
        LD      (IY+20),0
        LD      (IY+21),0
        LD      (IY+22),0
        LD      (IY+23),0
        ; The integer bit first: a may already exceed b (both are in
        ; [2^23, 2^24)); then 26 fraction bits.
        LD      B,1
        CALL    .TRY
        LD      B,26
.LOOP:  SLA     (IY+16)         ; R <<= 1
        RL      (IY+17)
        RL      (IY+18)
        RL      (IY+19)
        CALL    .TRY
        DJNZ    .LOOP
        ; Q is a/b * 2^26 with its hidden bit at 26, or at 25 when a < b,
        ; whose true exponent is one less. FP_PACK shifts to bit 30, taking
        ; 4 or 5 from the exponent: add 4 first.
        LD      A,(IY+16)
        OR      (IY+17)
        OR      (IY+18)
        OR      (IY+19)
        JR      Z,.NOSTK
        SET     0,(IY+20)       ; a remainder: the sticky bit
.NOSTK: LD      A,(IY+20)
        LD      (IY+0),A
        LD      A,(IY+21)
        LD      (IY+1),A
        LD      A,(IY+22)
        LD      (IY+2),A
        LD      A,(IY+23)
        LD      (IY+3),A
        LD      L,(IY+13)
        LD      H,(IY+14)
        LD      DE,4
        ADD     HL,DE
        LD      (IY+13),L
        LD      (IY+14),H
        CALL    FP_PACK
        JP      C,TRAP_FOV
        RET
; Q <<= 1; if R >= b then R -= b and Q's low bit is set.
.TRY:   SLA     (IY+20)         ; Q <<= 1
        RL      (IY+21)
        RL      (IY+22)
        RL      (IY+23)
        LD      L,(IY+16)       ; R - b
        LD      H,(IY+17)
        LD      C,(IY+4)
        LD      E,(IY+5)
        LD      D,0
        PUSH    BC
        LD      B,E
        OR      A
        SBC     HL,BC
        POP     BC
        EX      DE,HL           ; DE = low difference
        LD      L,(IY+18)
        LD      H,(IY+19)
        PUSH    BC
        LD      C,(IY+6)
        LD      B,0
        SBC     HL,BC
        POP     BC
        JR      C,.SMALL
        LD      (IY+16),E       ; it fitted: keep the difference, Q bit 1
        LD      (IY+17),D
        LD      (IY+18),L
        LD      (IY+19),H
        SET     0,(IY+20)
.SMALL: RET
.ZERO:  LD      HL,0
        LD      E,0
        LD      D,(IY+12)
        RET

; @blob $03E code FCMP helper=2
; Compare DEHL with DE'HL': carry = left < right, Z = equal. Both zeros are
; equal. Stack: 10.
FCMP:   CALL    .CANON
        EXX
        CALL    .CANON
        EXX
        LD      A,D
        EXX
        XOR     D
        EXX
        JP      M,.DIFF         ; different signs
        LD      A,D
        AND     $80
        JR      NZ,.NEG
        JP      CMP32U          ; both positive: the patterns order them
.NEG:   CALL    CMP32U          ; both negative: the order reverses
        RET     Z
        CCF
        RET
.DIFF:  LD      A,D
        AND     $80
        JR      NZ,.LESS
        OR      1               ; left positive: greater; NZ, carry clear
        RET
.LESS:  SCF                     ; left negative: less; NZ
        RET
.CANON: LD      A,D
        AND     $7F
        OR      E
        OR      H
        OR      L
        RET     NZ
        LD      D,0             ; -0 is +0
        RET

; @blob $03F code I2F helper=2
; DEHL = f32 of the i32 in DEHL, rounded to nearest even. Stack: 8.
I2F:    LD      IY,FP_VAR
        LD      A,D
        AND     $80
        LD      (IY+12),A
        JP      Z,FP_INT
        CALL    NEG32
        JP      FP_INT

; @blob $040 code U2F helper=2
; DEHL = f32 of the u32 in DEHL, rounded to nearest even. Stack: 8.
U2F:    LD      IY,FP_VAR
        LD      (IY+12),0
        JP      FP_INT

; @blob $043 code FP_INT helper=2
; DEHL = a magnitude, the sign at FP_VAR+12: pack it as an f32. Stack: 4.
FP_INT: LD      (IY+0),L
        LD      (IY+1),H
        LD      (IY+2),E
        LD      (IY+3),D
        LD      (IY+13),157     ; the value is M * 2^(exponent - 157)
        LD      (IY+14),0
        JP      FP_PACK         ; cannot overflow

; @blob $041 code F2I helper=2
; DEHL = the i32 of the f32 in DEHL, truncated toward zero; traps narrowing
; when it does not fit. Stack: 6.
F2I:    LD      A,D
        AND     $80
        LD      C,A             ; the sign
        PUSH    BC
        CALL    FP_MAG          ; DEHL = the magnitude, carry = too big for 32 bits
        POP     BC
        JP      C,TRAP_NAR
        LD      A,C
        OR      A
        JR      NZ,.NEG
        BIT     7,D
        JP      NZ,TRAP_NAR     ; positive and 2^31 or more
        RET
.NEG:   BIT     7,D
        JR      Z,.OK
        LD      A,D             ; exactly 2^31 fits as -2^31
        AND     $7F
        OR      E
        OR      H
        OR      L
        JP      NZ,TRAP_NAR
.OK:    JP      NEG32

; @blob $042 code F2U helper=2
; DEHL = the u32 of the f32 in DEHL, truncated toward zero; traps narrowing
; when negative or too large. Stack: 6.
F2U:    LD      A,D
        AND     $80
        JR      Z,.POS
        LD      A,D             ; negative: only -0 converts
        AND     $7F
        OR      E
        OR      H
        OR      L
        JP      NZ,TRAP_NAR
.POS:   CALL    FP_MAG
        JP      C,TRAP_NAR
        RET

; @blob $044 code FP_MAG helper=2
; DEHL = an f32 → DEHL = its magnitude truncated to an integer; carry set
; when it is 2^32 or more. Stack: 2.
FP_MAG: LD      A,D
        ADD     A,A
        LD      B,A
        LD      A,E
        RLA
        LD      A,B
        ADC     A,0             ; A = the exponent
        SUB     127
        JR      NC,.BIG         ; at least 1
        LD      HL,0            ; below 1: 0
        LD      DE,0
        OR      A
        RET
.BIG:   CP      32
        CCF
        RET     C               ; 2^32 or more
        SET     7,E
        LD      D,0             ; DEHL = the 24-bit mantissa; value = m * 2^(exp-150)
        SUB     23              ; the shift: exp - 127 - 23
        JR      Z,.DONE
        JR      C,.RIGHT
        LD      B,A
.L:     ADD     HL,HL
        RL      E
        RL      D
        DJNZ    .L
.DONE:  OR      A
        RET
.RIGHT: NEG
        LD      B,A
.R:     SRL     D
        RR      E
        RR      H
        RR      L
        DJNZ    .R
        OR      A
        RET
