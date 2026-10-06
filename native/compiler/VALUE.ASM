;==========================================================================
;  Exact and typed constant values
;==========================================================================
;
;  The arithmetic the expression parser folds constants with, as the
;  reference compiler's foldExact and foldTyped do. A known value is five
;  bytes, least significant first, in two's complement (EXPR.ASM): wide
;  enough for every exact value, -2^31 to 2^32-1 once checked, and for any
;  intermediate one, which a single operation on two of them cannot carry
;  past 34 bits. A typed value is kept as the number it is, a negative i16
;  as a negative number, so that the same comparisons serve both.
;
;  The binary operations take their operands from EX_LVAL (a) and EX_RVAL
;  (b) and leave the result in EX_KVAL (r); the unary ones work on EX_KVAL
;  in place. Multiplication and division work on the magnitudes, 32 bits
;  each, in VL_TA and VL_TB, the remainder in VL_TR, all five bytes.
;
;  Principal entries:
;    VL_ADD, VL_SUB  r = a + b, a - b
;    VL_MUL    r = a times b, carry when the magnitudes' product passes 32 bits
;    VL_DIV    r = a / b truncated, or a mod b with a's sign
;    VL_BITS   r = a and, or or xor b, byte by byte
;    VL_CMP    order a against b
;    VL_NEG, VL_NOT  r = -r, not r
;    VL_SHL, VL_SAR  r shifted left, or right arithmetically, one bit
;    VL_RANGE  carry when a value is outside the exact range
;    VL_FITS   carry when a value is outside a type's range
;    VL_WRAP   reduce a value to a type's range, as the run time wraps it
;    VL_LTOK   r = a

;@ROUTINE OUT HL CLOBBERS BC,DE
; r = a: copy EX_LVAL to EX_KVAL. HL returns EX_KVAL. A and flags are
; kept.

VL_LTOK:                       ; a becomes r.
    LD   HL,EX_LVAL                ; From a
    LD   DE,EX_KVAL                ; to r,
    LD   BC,5                      ; five bytes.
    LDIR                           ; Copied.
    LD   HL,EX_KVAL                ; HL is r.
    RET                            ; r is a.

;@ROUTINE CLOBBERS A,B,DE,HL,CARRY,ZERO,SIGN,PARITY,HALFCARRY
; r = a + b.

VL_ADD:                        ; r is to be a plus b.
    CALL VL_LTOK                   ; r = a; HL is r.
    LD   DE,EX_RVAL                ; b is added
    LD   B,5                       ; in five bytes; fall into VL_ADDN.

;@ROUTINE IN B,DE,HL OUT CARRY CLOBBERS A,B,DE,HL,ZERO,SIGN,PARITY,HALFCARRY
; Add the B bytes at DE into the B bytes at HL; carry out of the last.

VL_ADDN:                       ; (HL) += (DE), B bytes.
    OR   A                         ; No carry in.
.LOOP:                         ; One byte each pass.
    LD   A,(DE)                    ; Its byte of the addend
    ADC  A,(HL)                    ; and of the sum, with the carry,
    LD   (HL),A                    ; is the sum's.
    INC  HL                        ; The next
    INC  DE                        ; bytes.
    DJNZ .LOOP                     ; Until all are added.
    RET                            ; Carry out of the top.

;@ROUTINE CLOBBERS A,B,DE,HL,CARRY,ZERO,SIGN,PARITY,HALFCARRY
; r = a - b.

VL_SUB:                        ; r is to be a less b.
    CALL VL_LTOK                   ; r = a; HL is r.
    EX   DE,HL                     ; DE is r,
    LD   HL,EX_RVAL                ; HL is b,
    LD   B,5                       ; five bytes; fall into VL_SUBN.

;@ROUTINE IN B,DE,HL OUT CARRY CLOBBERS A,B,DE,HL,ZERO,SIGN,PARITY,HALFCARRY
; Subtract the B bytes at HL from the B bytes at DE; carry is the borrow.

VL_SUBN:                       ; (DE) -= (HL), B bytes.
    OR   A                         ; No borrow in.
.LOOP:                         ; One byte each pass.
    LD   A,(DE)                    ; Its byte of the difference
    SBC  A,(HL)                    ; less the subtrahend's and the borrow
    LD   (DE),A                    ; is the difference's.
    INC  HL                        ; The next
    INC  DE                        ; bytes.
    DJNZ .LOOP                     ; Until all are taken.
    RET                            ; Carry is the borrow out.

;@ROUTINE IN HL CLOBBERS A,B,HL,CARRY,ZERO,SIGN,PARITY,HALFCARRY
; Negate the value at HL in place.

VL_NEG:                        ; HL is the value.
    LD   B,5                       ; Five bytes,
    OR   A                         ; no borrow in.
.LOOP:                         ; One byte each pass.
    LD   A,0                       ; Zero
    SBC  A,(HL)                    ; less the byte and the borrow
    LD   (HL),A                    ; is the negation's.
    INC  HL                        ; The next byte.
    DJNZ .LOOP                     ; Until all are negated.
    RET                            ; The value is negated.

;@ROUTINE CLOBBERS A,B,HL,ZERO,SIGN,PARITY,HALFCARRY
; r = not r: every bit complemented.

VL_NOT:                        ; r is complemented.
    LD   HL,EX_KVAL                ; Its bytes,
    LD   B,5                       ; all five.
.LOOP:                         ; One byte each pass.
    LD   A,(HL)                    ; The byte
    CPL                            ; complemented
    LD   (HL),A                    ; in place.
    INC  HL                        ; The next.
    DJNZ .LOOP                     ; Until all are complemented.
    RET                            ; r is complemented.

;@ROUTINE IN C CLOBBERS A,B,DE,HL,CARRY,ZERO,SIGN,PARITY,HALFCARRY
; r = a and b, a or b or a xor b, by operator token C (TK_AND, TK_OR,
; TK_XOR), on all five bytes.

VL_BITS:                       ; C is the operator.
    PUSH BC                        ; Keep it.
    CALL VL_LTOK                   ; r = a; HL is r.
    POP  BC                        ; C is the operator.
    LD   DE,EX_RVAL                ; b,
    LD   B,5                       ; five bytes.
    LD   A,C                       ; Which operator?
    CP   TK_AND                    ; and,
    JR   Z,.AND                    ; or
    CP   TK_XOR                    ; xor,
    JR   Z,.XOR                    ; or else or.
.OR:                           ; Each byte of r ors b's.
    LD   A,(DE)                    ; b's byte
    OR   (HL)                      ; with r's
    LD   (HL),A                    ; is r's.
    INC  HL                        ; The next
    INC  DE                        ; bytes.
    DJNZ .OR                       ; Until all are combined.
    RET                            ; r is a or b.
.AND:                          ; Each byte of r ands b's.
    LD   A,(DE)                    ; b's byte
    AND  (HL)                      ; with r's
    LD   (HL),A                    ; is r's.
    INC  HL                        ; The next
    INC  DE                        ; bytes.
    DJNZ .AND                      ; Until all are combined.
    RET                            ; r is a and b.
.XOR:                          ; Each byte of r xors b's.
    LD   A,(DE)                    ; b's byte
    XOR  (HL)                      ; with r's
    LD   (HL),A                    ; is r's.
    INC  HL                        ; The next
    INC  DE                        ; bytes.
    DJNZ .XOR                      ; Until all are combined.
    RET                            ; r is a xor b.

;@ROUTINE OUT B CLOBBERS A,DE,HL,CARRY,ZERO,SIGN,PARITY,HALFCARRY
; Order a against b, as the comparisons fold them: B returns 1 when a is
; less, 2 when they are equal and 4 when a is greater. r is their
; difference, which five bytes always hold.

VL_CMP:                        ; a and b are to be ordered.
    CALL VL_SUB                    ; r = a less b.
    LD   HL,EX_KVAL                ; Its bytes:
    LD   B,5                       ; all five
    XOR  A                         ; ored
.ZERO:                         ; together
    OR   (HL)                      ; are
    INC  HL                        ; zero
    DJNZ .ZERO                     ; when a equals b.
    LD   B,2                       ; Equal:
    RET  Z                         ; two.
    DEC  HL                        ; The top byte's
    BIT  7,(HL)                    ; sign:
    LD   B,1                       ; negative,
    RET  NZ                        ; a is less;
    LD   B,4                       ; positive,
    RET                            ; a is greater.

;@ROUTINE OUT CARRY CLOBBERS A,B,HL,ZERO,SIGN,PARITY,HALFCARRY
; Shift r left one bit; carry out of its top.

VL_SHL:                        ; r doubles.
    LD   HL,EX_KVAL                ; Its five bytes
    LD   B,5                       ; from the lowest.
    JR   VL_DBLN                   ; Shift them.

;@ROUTINE IN HL OUT CARRY CLOBBERS A,B,HL,ZERO,SIGN,PARITY,HALFCARRY
; Shift the four bytes at HL left one bit; carry out of the top.

VL_DBL4:                       ; Four bytes at HL.
    LD   B,4                       ; Four of them.

;@ROUTINE IN B,HL OUT CARRY CLOBBERS B,HL,ZERO,SIGN,PARITY,HALFCARRY
; Shift the B bytes at HL left one bit; carry out of the top.

VL_DBLN:                       ; B bytes at HL.
    OR   A                         ; A zero enters the bottom.
.LOOP:                         ; One byte each pass.
    RL   (HL)                      ; Its carry enters the next.
    INC  HL                        ; The next byte.
    DJNZ .LOOP                     ; Until all are shifted.
    RET                            ; Carry left the top.

;@ROUTINE CLOBBERS A,B,HL,CARRY,ZERO,SIGN,PARITY,HALFCARRY
; Shift r right one bit arithmetically: its sign is kept.

VL_SAR:                        ; r halves, rounding down.
    LD   HL,EX_KVAL+4              ; The top byte
    SRA  (HL)                      ; keeps its sign.
    LD   B,4                       ; Then the four below,
.LOOP:                         ; downward,
    DEC  HL                        ; each
    RR   (HL)                      ; taking the bit above.
    DJNZ .LOOP                     ; Until all are shifted.
    RET                            ; r is halved.

;@ROUTINE IN HL,DE OUT A CLOBBERS BC,DE,HL,CARRY,ZERO,SIGN,PARITY,HALFCARRY
; Copy the value at HL to DE and make the copy its magnitude. A returns
; the value's top byte, whose bit 7 is its sign.

VL_ABS:                        ; HL is the value, DE the copy.
    PUSH DE                        ; Keep the copy's address.
    LD   BC,5                      ; Five bytes
    LDIR                           ; copied.
    POP  HL                        ; The copy.
    DEC  DE                        ; Its top byte
    LD   A,(DE)                    ; is the sign's.
    OR   A                         ; Negative?
    RET  P                         ; No: the magnitude.
    PUSH AF                        ; Keep the top byte.
    CALL VL_NEG                    ; The copy negated.
    POP  AF                        ; The top byte.
    RET                            ; A is it.

;@ROUTINE OUT A CLOBBERS BC,DE,HL,CARRY,ZERO,SIGN,PARITY,HALFCARRY
; VL_TA = |a|, VL_TB = |b|; A's bit 7 is set when a and b have opposite
; signs, the sign of their product and quotient.

VL_MAGS:                       ; a and b give their magnitudes.
    LD   HL,EX_LVAL                ; |a|
    LD   DE,VL_TA                  ; into VL_TA,
    CALL VL_ABS                    ; A its sign.
    PUSH AF                        ; Keep it.
    LD   HL,EX_RVAL                ; |b|
    LD   DE,VL_TB                  ; into VL_TB,
    CALL VL_ABS                    ; A its sign.
    POP  BC                        ; B is a's.
    XOR  B                         ; Bit 7: they differ.
    RET                            ; A is the sign.

;@ROUTINE IN HL CLOBBERS A,B,HL
; Zero the five bytes at HL. Flags are kept.

VL_ZERO:                       ; HL is the value.
    LD   B,5                       ; Five bytes,
.LOOP:                         ; each
    LD   (HL),0                    ; zero.
    INC  HL                        ; The next.
    DJNZ .LOOP                     ; Until all are.
    RET                            ; The value is zero.

;@ROUTINE OUT CARRY CLOBBERS A,BC,DE,HL,ZERO,SIGN,PARITY,HALFCARRY
; r = a times b: the product of the magnitudes, modulo 2^32, with the
; sign of a's and b's. Carry when the magnitudes' product reaches 2^32,
; when an exact product is out of range; a typed one is reduced to its
; type afterwards, and the low 32 bits are all it needs.

VL_MUL:                        ; r is to be a times b.
    CALL VL_MAGS                   ; |a| and |b|, A the sign.
    PUSH AF                        ; Keep it.
    LD   HL,EX_KVAL                ; The product
    CALL VL_ZERO                   ; starts at zero; its top byte marks a carry.
    LD   C,32                      ; One step per bit of |b|.
.LOOP:                         ; From its top bit down.
    LD   HL,EX_KVAL                ; The product
    CALL VL_DBL4                   ; doubles,
    CALL C,.OVER                   ; perhaps past 32 bits.
    LD   HL,VL_TB                  ; |b|'s next bit
    CALL VL_DBL4                   ; leaves its top:
    JR   NC,.NEXT                  ; a clear bit adds nothing.
    LD   HL,EX_KVAL                ; |a| is added
    LD   DE,VL_TA                  ; to the product,
    LD   B,4                       ; four bytes,
    CALL VL_ADDN                   ; perhaps
    CALL C,.OVER                   ; past 32 bits.
.NEXT:                         ; The step is done.
    DEC  C                         ; One bit fewer.
    JR   NZ,.LOOP                  ; Through all 32.
    LD   HL,EX_KVAL+4              ; The mark:
    LD   A,(HL)                    ; nonzero if it carried,
    LD   (HL),C                    ; and the top byte zero.
    POP  BC                        ; B is the sign.
    PUSH AF                        ; Keep the mark.
    LD   HL,EX_KVAL                ; The product
    BIT  7,B                       ; is negated
    CALL NZ,VL_NEG                 ; when the signs differ.
    POP  AF                        ; The mark:
    ADD  A,$FF                     ; carry unless zero.
    RET                            ; r is the product.
.OVER:                         ; A carry left 32 bits.
    LD   A,1                       ; Mark it
    LD   (EX_KVAL+4),A             ; in the top byte.
    RET                            ; The steps go on.

;@ROUTINE IN A CLOBBERS A,BC,DE,HL,CARRY,ZERO,SIGN,PARITY,HALFCARRY
; r = a / b, truncated toward zero, or for operator token A TK_MOD the
; remainder, which takes a's sign, as the reference's Math.trunc and %
; give them. b is not zero. The magnitudes are divided, 32 bits by 32,
; one quotient bit a step; the remainder takes five bytes, since doubled
; it may pass 32 bits before |b| is taken from it.

VL_DIV:                        ; A is the operator.
    PUSH AF                        ; Keep it.
    CALL VL_MAGS                   ; |a| and |b|, A the quotient's sign.
    PUSH AF                        ; Keep it.
    LD   HL,VL_TR                  ; The remainder
    CALL VL_ZERO                   ; starts at zero.
    LD   C,32                      ; One step per bit of |a|.
.LOOP:                         ; From its top bit down.
    LD   HL,VL_TA                  ; |a|'s top bit
    CALL VL_DBL4                   ; leaves it
    LD   HL,VL_TR                  ; and enters
    LD   B,5                       ; the remainder's, five bytes for its 33 bits,
.ROLL:                         ; bottom:
    RL   (HL)                      ; each byte
    INC  HL                        ; takes
    DJNZ .ROLL                     ; the carry.
    LD   DE,VL_TR                  ; |b| is taken
    LD   HL,VL_TB                  ; from the remainder
    LD   B,5                       ; if it
    CALL VL_SUBN                   ; fits:
    JR   NC,.FITS                  ; no borrow.
    LD   HL,VL_TR                  ; Otherwise
    LD   DE,VL_TB                  ; it is
    LD   B,5                       ; added
    CALL VL_ADDN                   ; back.
    JR   .NEXT                     ; A zero quotient bit.
.FITS:                         ; A one.
    LD   HL,VL_TA                  ; It enters
    SET  0,(HL)                    ; |a|'s emptied bottom.
.NEXT:                         ; The step is done.
    DEC  C                         ; One bit fewer.
    JR   NZ,.LOOP                  ; Through all 32.
    POP  BC                        ; B is the quotient's sign,
    POP  AF                        ; A the operator.
    LD   HL,VL_TA                  ; The quotient, |a| now,
    CP   TK_MOD                    ; unless
    JR   NZ,.SIGN                  ; the remainder
    LD   A,(EX_LVAL+4)             ; is wanted, with
    LD   B,A                       ; a's sign,
    LD   HL,VL_TR                  ; from VL_TR.
.SIGN:                         ; HL is the magnitude, B's bit 7 its sign.
    LD   DE,EX_KVAL                ; It is r:
    PUSH BC                        ; (the sign kept)
    LD   BC,4                      ; four bytes,
    LDIR                           ; copied,
    XOR  A                         ; and a zero
    LD   (DE),A                    ; top byte.
    POP  BC                        ; The sign:
    BIT  7,B                       ; negative?
    RET  Z                         ; No: r is the result.
    LD   HL,EX_KVAL                ; Then r
    JP   VL_NEG                    ; is negated; return.

;@ROUTINE IN HL OUT CARRY CLOBBERS A,E,ZERO,SIGN,PARITY,HALFCARRY
; Carry when the value at HL is outside the exact range, -2^31 to 2^32-1:
; its top byte must be zero, or $FF with bit 31 set. HL is kept.

VL_RANGE:                      ; HL is the value.
    PUSH HL                        ; Keep it.
    INC  HL                        ; Its
    INC  HL                        ; fourth
    INC  HL                        ; byte
    LD   A,(HL)                    ; holds bit 31,
    INC  HL                        ; and the next
    LD   E,(HL)                    ; is the top byte.
    POP  HL                        ; The value again.
    RLA                            ; Bit 31 into carry.
    LD   A,E                       ; The top byte,
    INC  A                         ; $FF
    JR   Z,.NEG                    ; for a negative value.
    DEC  A                         ; Otherwise only zero
    ADD  A,$FF                     ; is in range: carry if not.
    RET                            ; Carry if out of range.
.NEG:                          ; Carry is bit 31,
    CCF                            ; which must be set.
    RET                            ; Carry if out of range.

;@ROUTINE IN A,HL OUT B,C,HL CLOBBERS A,DE,CARRY,ZERO,SIGN,PARITY,HALFCARRY
; For the value at HL and integer type A, address the top byte of the
; type's size in HL and return in B the byte every byte above it must be
; (its sign's for a signed type, zero otherwise) and in C how many there
; are.

VL_EXT:                        ; A is the type, HL the value.
    CALL GX_PROP                   ; A is its size and sign.
    LD   C,A                       ; Keep them.
    AND  7                         ; The size:
    LD   E,A                       ; bytes
    LD   D,0                       ; from the value's start
    ADD  HL,DE                     ; to past its top,
    DEC  HL                        ; to the top.
    LD   A,5                       ; Five bytes less the size
    SUB  E                         ; are above it.
    BIT  7,C                       ; Signed?
    LD   C,A                       ; C counts them.
    LD   B,0                       ; Unsigned: zeros above.
    RET  Z                         ; Done.
    LD   A,(HL)                    ; Signed: the top byte's
    RLA                            ; sign
    SBC  A,A                       ; as a byte,
    LD   B,A                       ; above.
    RET                            ; HL, B and C.

;@ROUTINE IN A,HL OUT CARRY CLOBBERS A,DE,ZERO,SIGN,PARITY,HALFCARRY
; Carry when the value at HL is outside the range of integer type A, or,
; for SY_EXACT, outside the exact range (fits). An f32's bits always fit
; f32: an integer becomes one through OV_ITOF first. BC and HL are kept.

VL_FITS:                       ; A is the type, HL the value.
    CP   SY_F32                    ; An f32
    RET  Z                         ; fits, carry clear.
    OR   A                         ; Exact?
    JR   Z,VL_RANGE                ; The exact range; it keeps BC.
    PUSH BC                        ; Keep the caller's BC
    PUSH HL                        ; and the value.
    CALL VL_EXT                    ; HL its top byte, B and C those above.
    INC  C                         ; Plus one, for the loop's test.
.LOOP:                         ; C bytes remain to check, plus one.
    DEC  C                         ; Any?
    JR   Z,.DONE                   ; No: it fits, carry clear.
    INC  HL                        ; The next byte up
    LD   A,(HL)                    ; must be
    CP   B                         ; the extension:
    JR   Z,.LOOP                   ; it is.
    SCF                            ; Otherwise it does not fit.
.DONE:                         ; Carry is the answer.
    POP  HL                        ; The value.
    POP  BC                        ; BC again.
    RET                            ; Carry if out of range.

;@ROUTINE CLOBBERS A,B,HL,CARRY,ZERO,SIGN,PARITY,HALFCARRY
; Make the f32 values a and b comparable as five-byte integers, so that
; VL_CMP orders them as the reference compares numbers: each becomes its
; magnitude's bits, negated when its sign is set, so that -0 is 0 too.

VL_FKEYS:                      ; a and b are f32 values.
    LD   HL,EX_LVAL                ; a,
    CALL .KEY                      ; then b.
    LD   HL,EX_RVAL                ; Fall into .KEY for b.
.KEY:                          ; HL is a value.
    PUSH HL                        ; Keep it.
    INC  HL                        ; Its
    INC  HL                        ; top
    INC  HL                        ; byte:
    LD   A,(HL)                    ; the sign
    RES  7,(HL)                    ; leaves it,
    POP  HL                        ; and when it was set
    RLA                            ; the magnitude
    JP   C,VL_NEG                  ; is negated; return.
    RET                            ; Done.

;@ROUTINE IN A,HL CLOBBERS A,BC,DE,CARRY,ZERO,SIGN,PARITY,HALFCARRY
; Reduce the value at HL to integer type A, as the run time wraps it: the
; type's bytes are kept and those above made its sign's, or zero. HL is
; kept. An f32's four bytes are kept as a u32's are, the fifth zero.

VL_WRAP:                       ; A is the type, HL the value.
    CP   SY_F32                    ; An f32
    JR   NZ,.WRAP                  ; is kept
    DEC  A                         ; as
    DEC  A                         ; a u32.
.WRAP:                         ; A is an integer type.
    PUSH HL                        ; Keep the value.
    CALL VL_EXT                    ; HL its top byte, B and C those above.
    INC  C                         ; Plus one, for the loop's test.
.LOOP:                         ; C bytes remain to write, plus one.
    DEC  C                         ; Any?
    JR   Z,.DONE                   ; No: the value is wrapped.
    INC  HL                        ; The next byte up
    LD   (HL),B                    ; is the extension.
    JR   .LOOP                     ; The next.
.DONE:                         ; Every byte is written.
    POP  HL                        ; The value.
    RET                            ; It is reduced.
