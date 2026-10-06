;==========================================================================
;  Floating-point constants
;==========================================================================
;
;  Overlay FLOAT, loaded above NAMES the first time a compilation meets an
;  f32 constant and kept for the rest of it (OVERLAY.ASM): the conversion
;  of a decimal literal to f32, as the reference's parseF32 does it, and
;  the folding of f32 constants, as its foldTyped does it with
;  Math.fround, round to nearest with ties to even and a result below the
;  smallest normal flushed to zero (design decision D7), with the
;  conversions between integer and f32 constants.
;
;  Every result is formed exactly and rounded once: its value is N / D
;  times 2^E, N and D integers of FL_NB bytes, least significant first,
;  and FL_PACK rounds it. A decimal literal is its digits over a power of
;  ten, or times one; a sum the two significands aligned at the smaller
;  exponent; a product the significands' product; a quotient the
;  significands over each other. FL_NB bytes take any sum of two f32
;  values (278 bits) and a literal of about 95 significant digits; a
;  literal that needs more is refused (capacity, `f32 digits`).
;
;  Two rounding rules, FL_MODE: a literal is rounded to 24 bits and then
;  flushed to zero below 2^-126, as parseF32 does; a folded result is
;  rounded as Math.fround rounds it, at the denormals' spacing below
;  2^-126, and then flushed, so that only 2^-126 itself survives from
;  below. Every zero a fold makes is +0, the reference's flush making
;  -0 so too; a literal is never negative.
;
;  Entries, a jump each at the overlay's start (VL_FCALL calls them with
;  their argument in HL):
;    +0  FL_SCAN   the decimal literal whose digits begin at TK_NBEG,
;                  the integer ones consumed: its f32 in TK_NLO and TK_NHI
;    +3  FL_ITOF   the integer at HL (five bytes) to f32 in place; carry
;                  when it was rounded
;    +6  FL_FTOI   the f32 at HL truncated to an integer in place, a top
;                  byte of $40 when it is 2^32 or more in magnitude
;    +9  FL_ARITH  EX_LVAL op EX_RVAL, f32 values, op EX_OPER's +, -, *
;                  or /, to EX_KVAL; carry when it exceeds f32
;
;  An f32 constant is kept as its IEEE single bits in the first four bytes
;  of a five-byte value, the fifth zero (EXPR.ASM).


FL_BEG:                        ; The overlay's start: its entries.
    JP   FL_SCAN                   ; +0: a decimal literal.
    JP   FL_ITOF                   ; +3: an integer to f32.
    JP   FL_FTOI                   ; +6: an f32 to an integer.
                                   ; +9: an operation; fall into FL_ARITH.

;@ROUTINE OUT CARRY CLOBBERS A,BC,DE,HL,IX,IY,ZERO,SIGN,PARITY,HALFCARRY
; EX_KVAL = EX_LVAL op EX_RVAL, both f32 values (foldTyped): op is the
; token in EX_OPER, +, -, * or /, the divisor not zero. Carry when the
; result exceeds f32 (float-overflow).

FL_ARITH:                      ; The operands are EX_LVAL and EX_RVAL.
    CALL FL_INIT                   ; N zero, D one, E zero, folding.
    LD   HL,EX_LVAL                ; a's sign, exponent
    LD   DE,FL_A                   ; and significand,
    CALL FL_OPEN                   ; unpacked;
    LD   HL,EX_RVAL                ; b's
    LD   DE,FL_B                   ; likewise.
    CALL FL_OPEN                   ; Both are unpacked.
    LD   A,(EX_OPER)               ; The operation:
    CP   TK_STAR                   ; a product,
    JP   Z,.TIMES                  ; or
    CP   TK_SLASH                  ; a quotient,
    JP   Z,.OVER                   ; or
    CP   TK_MINUS                  ; a difference, a sum
    JR   NZ,.PLUS                  ; with b's
    LD   HL,FL_B                   ; sign
    LD   A,(HL)                    ; flipped,
    XOR  $80                       ; or
    LD   (HL),A                    ; a sum.
.PLUS:                         ; a + b.
    LD   A,(FL_A+1)                ; Order them:
    LD   HL,FL_B+1                 ; a's exponent
    CP   (HL)                      ; at least
    JR   NC,.ORDERED               ; b's,
    LD   HL,FL_A                   ; or else
    LD   DE,FL_B                   ; they
    LD   B,5                       ; change
.SWAP:                         ; places,
    LD   C,(HL)                    ; byte
    LD   A,(DE)                    ; by
    LD   (HL),A                    ; byte.
    LD   A,C                       ; (each
    LD   (DE),A                    ; exchanged)
    INC  HL                        ; The
    INC  DE                        ; next.
    DJNZ .SWAP                     ; All five.
.ORDERED:                      ; a's exponent is the larger.
    LD   HL,FL_A                   ; N is a's
    CALL FL_NSIG                   ; significand,
    LD   A,(FL_A+1)                ; shifted
    LD   HL,FL_B+1                 ; left by
    SUB  (HL)                      ; the exponents'
    LD   E,A                       ; difference,
    LD   D,0                       ; so that both
    LD   HL,FL_N                   ; count from
    CALL FL_SHLN                   ; b's.
    LD   A,(FL_B+1)                ; E is
    LD   HL,-150                   ; b's exponent
    CALL FL_ESET                   ; of its units.
    LD   HL,FL_B                   ; D is b's
    LD   DE,FL_D                   ; significand
    CALL FL_SIGTO                  ; for now.
    LD   A,(FL_A)                  ; The same
    LD   HL,FL_B                   ; signs?
    XOR  (HL)                      ; Then
    JP   M,.UNLIKE                 ; the magnitudes add:
    LD   HL,FL_N                   ; N
    LD   DE,FL_D                   ; plus
    LD   B,FL_NB                   ; b's,
    CALL VL_ADDN                   ; with a's sign.
    JR   .SUMMED                   ; The sum.
.UNLIKE:                       ; Unlike signs: the larger less the smaller.
    LD   DE,FL_N                   ; N less
    LD   HL,FL_D                   ; b's
    LD   B,FL_NB                   ; significand,
    CALL VL_SUBN                   ; which is a's sign's
    JR   NC,.SUMMED                ; when it does not borrow.
    LD   HL,FL_N                   ; It did: b's is the larger,
    CALL FL_NEGN                   ; the difference negated,
    LD   A,(FL_B)                  ; with
    LD   (FL_A),A                  ; b's sign.
.SUMMED:                       ; N is the sum's magnitude, FL_A its sign.
    LD   HL,FL_N                   ; A sum
    CALL FL_NZ                     ; of zero
    JP   Z,.ZERO                   ; is +0;
    CALL FL_UNIT                   ; any other is N over one,
    JR   .ROUND                    ; rounded.
.TIMES:                        ; a * b.
    CALL .SIGNS                    ; The signs' product; zero if either is.
    LD   HL,FL_A                   ; D is
    LD   DE,FL_D                   ; a's significand for now
    CALL FL_SIGTO                  ; (one again after); N, zero,
    LD   C,24                      ; takes it for each of b's 24 bits
.BIT:                          ; that is set, from the top:
    LD   HL,FL_N                   ; the product
    LD   B,FL_NB                   ; doubles,
    CALL VL_DBLN                   ; and
    LD   HL,FL_B+2                 ; b's next bit
    LD   B,3                       ; leaves
    CALL VL_DBLN                   ; its top:
    JR   NC,.NOADD                 ; when set,
    LD   HL,FL_N                   ; a's
    LD   DE,FL_D                   ; significand
    LD   B,FL_NB                   ; is
    CALL VL_ADDN                   ; added.
.NOADD:                        ; The next bit.
    DEC  C                         ; Until
    JR   NZ,.BIT                   ; all 24.
    CALL FL_UNIT                   ; D is one again.
    LD   A,(FL_A+1)                ; E is
    LD   HL,-300                   ; a's exponent
    CALL FL_ESET                   ; plus
    LD   A,(FL_B+1)                ; b's, less 300:
    CALL FL_EADD                   ; their units multiplied.
    JR   .ROUND                    ; Round the product.
.OVER:                         ; a / b, b not zero.
    CALL .SIGNS                    ; The signs' quotient; zero if a is.
    LD   HL,FL_A                   ; N is
    CALL FL_NSIG                   ; a's significand,
    LD   HL,FL_B                   ; D
    LD   DE,FL_D                   ; b's.
    CALL FL_SIGTO                  ; (the units cancel)
    LD   A,(FL_A+1)                ; E is
    LD   HL,0                      ; a's exponent
    CALL FL_ESET                   ; less
    LD   A,(FL_B+1)                ; b's.
    LD   E,A                       ; As
    LD   D,0                       ; a
    LD   HL,(FL_E)                 ; word,
    OR   A                         ; subtracted.
    SBC  HL,DE                     ; E is
    LD   (FL_E),HL                 ; it.
.ROUND:                        ; N / D times 2^E, its sign FL_A's.
    LD   A,(FL_A)                  ; The sign
    LD   (FL_SIGN),A               ; for FL_PACK.
    CALL FL_PACK                   ; Rounded:
    RET  C                         ; past f32, carry.
    LD   HL,FL_Q                   ; Its bits
    LD   DE,EX_KVAL                ; are the result,
    LD   BC,4                      ; four bytes,
    LDIR                           ; then
    XOR  A                         ; a zero fifth;
    LD   (DE),A                    ; carry clear.
    RET                            ; Done.
.ZERO:                         ; A zero result is +0, whatever
    LD   HL,EX_KVAL                ; the signs, as the reference's
    OR   A                         ; flush makes it; carry clear.
    JP   FL_CLR5                   ; Written.

;@ROUTINE CLOBBERS A,HL,CARRY,ZERO,SIGN,PARITY,HALFCARRY
; For * and /: FL_A's sign becomes a's times b's, and a zero a (or b for a
; product) makes the result +0, which returns to FL_ARITH's caller.

.SIGNS:                        ; Both unpacked.
    LD   A,(FL_A)                  ; The signs'
    LD   HL,FL_B                   ; product:
    XOR  (HL)                      ; unlike
    LD   (FL_A),A                  ; is negative.
    LD   A,(FL_A+1)                ; A zero a
    OR   A                         ; (exponent zero)
    JR   Z,.ZEROED                 ; makes zero;
    LD   A,(EX_OPER)               ; so does
    CP   TK_STAR                   ; a zero b
    RET  NZ                        ; in a product.
    LD   A,(FL_B+1)                ; b's exponent:
    OR   A                         ; not zero,
    RET  NZ                        ; and the operation goes on.
.ZEROED:                       ; The result is zero.
    POP  HL                        ; (FL_ARITH's place dropped)
    JR   .ZERO                     ; Returned.

;@ROUTINE IN HL CLOBBERS A,BC,DE,HL,IX,IY,CARRY,ZERO,SIGN,PARITY,HALFCARRY
; The integer at HL, five bytes, two's complement, to f32 in place, with a
; zero fifth byte. Carry when the f32 is not the integer exactly (it was
; rounded, to nearest with ties to even).

FL_ITOF:                       ; HL is the integer.
    PUSH HL                        ; Keep its place.
    CALL FL_INIT                   ; N zero, D one, E zero, folding.
    POP  HL                        ; Its
    PUSH HL                        ; magnitude
    LD   DE,FL_N                   ; is N's low bytes,
    CALL VL_ABS                    ; A its top byte:
    AND  $80                       ; its sign
    LD   (FL_SIGN),A               ; the f32's.
    LD   HL,FL_N                   ; Zero
    CALL FL_NZ                     ; is
    POP  DE                        ; (the place)
    EX   DE,HL                     ; +0,
    JP   Z,FL_CLR5                 ; and exact.
    PUSH HL                        ; Keep the place.
    CALL FL_PACK                   ; Rounded (never past f32).
    POP  DE                        ; The place
    LD   HL,FL_Q                   ; takes
    LD   BC,4                      ; the bits,
    LDIR                           ; four bytes,
    XOR  A                         ; and a zero
    LD   (DE),A                    ; fifth.
    LD   A,(FL_LOST)               ; Rounded,
    ADD  A,$FF                     ; carry.
    RET                            ; Done.

;@ROUTINE IN HL CLOBBERS A,BC,DE,HL,CARRY,ZERO,SIGN,PARITY,HALFCARRY
; The f32 at HL truncated toward zero to an integer in place, five bytes,
; two's complement (Math.trunc), or with a top byte of $40, which no
; integer type takes, when its magnitude is 2^32 or more.

FL_FTOI:                       ; HL is the f32.
    PUSH HL                        ; Keep its place.
    LD   DE,FL_A                   ; Its sign, exponent
    CALL FL_OPEN                   ; and significand.
    POP  HL                        ; The place
    PUSH HL                        ; is cleared:
    CALL FL_CLR5                   ; a zero to begin with.
    POP  HL                        ; (kept)
    LD   A,(FL_A+1)                ; The exponent,
    SUB  127                       ; unbiased:
    JR   C,.SIGN                   ; below one is zero.
    CP   32                        ; From 2^32 on
    JR   C,.FITS                   ; no integer
    INC  HL                        ; takes it:
    INC  HL                        ; a top
    INC  HL                        ; byte
    INC  HL                        ; of
    LD   (HL),$40                  ; $40.
    RET                            ; Done.
.FITS:                         ; A is the exponent, 0 to 31.
    PUSH HL                        ; Keep the place.
    EX   DE,HL                     ; DE is it:
    LD   HL,FL_A+2                 ; the significand's
    LD   BC,3                      ; three bytes
    LDIR                           ; are its low ones.
    POP  HL                        ; The place.
    SUB  23                        ; Exponent less 23:
    JR   C,.RIGHT                  ; below, shifted right;
    JR   Z,.SIGN                   ; at it, as it is;
    LD   C,A                       ; above, left
.LEFT:                         ; C times.
    PUSH HL                        ; Keep the place.
    LD   B,5                       ; Five bytes
    CALL VL_DBLN                   ; doubled.
    POP  HL                        ; The place.
    DEC  C                         ; Until
    JR   NZ,.LEFT                  ; done.
    JR   .SIGN                     ; Then its sign.
.RIGHT:                        ; A is minus the shift.
    NEG                            ; The shift,
    LD   C,A                       ; C times:
.HALVE:                        ; three bytes halved.
    INC  HL                        ; From
    INC  HL                        ; the top
    SRL  (HL)                      ; byte
    DEC  HL                        ; down:
    RR   (HL)                      ; the bits
    DEC  HL                        ; falling
    RR   (HL)                      ; off the bottom.
    DEC  C                         ; Until
    JR   NZ,.HALVE                 ; done.
.SIGN:                         ; HL is the magnitude.
    LD   A,(FL_A)                  ; Negative?
    OR   A                         ; Then
    JP   M,VL_NEG                  ; negated; return.
    RET                            ; Done.

;@ROUTINE CLOBBERS A,BC,DE,HL,IX,IY,CARRY,ZERO,SIGN,PARITY,HALFCARRY
; The decimal literal whose first digit is at TK_NBEG and whose integer
; digits the tokenizer has consumed: its fraction and exponent are
; consumed here, and its f32 (parseF32) is left in TK_NLO and TK_NHI and
; TK_WIDE made SY_F32. An exponent without digits, a name byte after the
; literal, or a value beyond the largest f32 is malformed-number.

FL_SCAN:                       ; The cursor is after the integer digits.
    CALL FL_INIT                   ; N zero, D one, E zero,
    INC  A                         ; and literal
    LD   (FL_MODE),A               ; rounding.
    LD   HL,0                      ; No
    LD   (FL_TEN),HL               ; power of ten
    LD   (FL_SIG),HL               ; nor significant digit yet.
    LD   HL,(TK_NBEG)              ; From the first digit
.INT:                          ; up to the cursor:
    LD   DE,(SRC_PTR)              ; the integer
    OR   A                         ; digits,
    SBC  HL,DE                     ; consumed
    ADD  HL,DE                     ; already,
    JR   Z,.POINT                  ; are read again.
    LD   A,(HL)                    ; A digit:
    INC  HL                        ; the next
    PUSH HL                        ; kept,
    CALL .DIGIT                    ; this one
    POP  HL                        ; taken
    JR   .INT                      ; into N.
.POINT:                        ; A fraction?
    CALL SRC_PEEK                  ; The byte at the cursor
    JR   C,.EXPO                   ; (none at the part's end):
    CP   '.'                       ; a point
    JR   NZ,.EXPO                  ; (with a digit after it, TK_TRAIL saw).
    CALL SRC_TAKE                  ; Past it.
.FRAC:                         ; Each fraction digit
    CALL .NEXT                     ; is taken,
    JR   C,.EXPO                   ; until a non-digit,
    LD   HL,(FL_TEN)               ; and moves
    DEC  HL                        ; the point
    LD   (FL_TEN),HL               ; one place.
    JR   .FRAC                     ; The next.
.EXPO:                         ; An exponent?
    CALL SRC_PEEK                  ; e or E
    JR   C,.SCALE                  ; at the cursor,
    OR   $20                       ; in either
    CP   'e'                       ; case.
    JR   NZ,.TAIL                  ; Not one.
    CALL SRC_TAKE                  ; Past it.
    CALL SRC_PEEK                  ; Its sign:
    LD   C,0                       ; positive
    CP   '+'                       ; with a plus,
    JR   Z,.SIGNED                 ; or none,
    CP   '-'                       ; negative
    JR   NZ,.UNSIGNED              ; with a minus.
    DEC  C                         ; C is $FF.
.SIGNED:                       ; A sign
    CALL SRC_TAKE                  ; is consumed.
.UNSIGNED:                     ; C is the sign.
    LD   HL,0                      ; The exponent's value,
    LD   B,H                       ; no digit yet.
.EXP:                          ; Each digit:
    PUSH HL                        ; (the value kept)
    CALL SRC_PEEK                  ; the next byte
    POP  HL                        ; (the value)
    JR   C,.EXPD                   ; (the part's end),
    SUB  '0'                       ; a digit
    CP   10                        ; or
    JR   NC,.EXPD                  ; not.
    LD   B,1                       ; There is one,
    PUSH BC                        ; (the sign and the flag)
    LD   C,A                       ; and it is
    LD   A,H                       ; added
    CP   3                         ; to a value
    JR   NC,.CAPPED                ; kept below 7,690,
    LD   D,H                       ; ten
    LD   E,L                       ; times
    ADD  HL,HL                     ; it
    ADD  HL,HL                     ; plus
    ADD  HL,DE                     ; the
    ADD  HL,HL                     ; digit,
    LD   B,0                       ; which
    ADD  HL,BC                     ; is enough to
.CAPPED:                       ; settle any literal.
    PUSH HL                        ; (the value kept)
    CALL SRC_TAKE                  ; Past it.
    POP  HL                        ; The value,
    POP  BC                        ; the sign and the flag.
    JR   .EXP                      ; The next.
.EXPD:                         ; The exponent's digits are read.
    INC  B                         ; Without
    DEC  B                         ; any
    JP   Z,TK_ENUM                 ; it is malformed.
    INC  C                         ; Negative?
    JR   NZ,.ADDEXP                ; Then
    EX   DE,HL                     ; it
    LD   HL,0                      ; is
    OR   A                         ; negated,
    SBC  HL,DE                     ; zero less it.
.ADDEXP:                       ; HL is the exponent.
    LD   DE,(FL_TEN)               ; It moves
    ADD  HL,DE                     ; the point
    LD   (FL_TEN),HL               ; further.
.TAIL:                         ; No name byte may follow.
    CALL SRC_PEEK                  ; The next byte
    JR   C,.SCALE                  ; (none at the part's end)
    CALL TK_ALNUM                  ; is a name's?
    JP   C,TK_ENUM                 ; Then malformed.
.SCALE:                        ; N times 10^FL_TEN is the value.
    LD   HL,FL_N                   ; Zero
    CALL FL_NZ                     ; is
    JR   Z,.ZERO                   ; +0.
    LD   HL,(FL_SIG)               ; Its decimal magnitude,
    LD   DE,(FL_TEN)               ; the significant digits
    ADD  HL,DE                     ; and the power:
    LD   DE,40                     ; from 10^39
    OR   A                         ; it is past
    SBC  HL,DE                     ; the largest f32,
    JP   P,TK_ENUM                 ; malformed;
    LD   DE,-40-46                 ; below 10^-46
    OR   A                         ; it
    SBC  HL,DE                     ; is
    JP   M,.ZERO                   ; zero.
    LD   DE,(FL_TEN)               ; The power of ten:
    LD   HL,FL_N                   ; N's
    BIT  7,D                       ; when positive,
    JR   Z,.TENS                   ; D's
    XOR  A                         ; when negative,
    SUB  E                         ; its
    LD   E,A                       ; magnitude
    SBC  A,A                       ; as
    SUB  D                         ; a
    LD   D,A                       ; count.
    LD   HL,FL_D                   ; D's.
.TENS:                         ; DE times, HL times ten.
    LD   A,D                       ; Any
    OR   E                         ; left?
    JR   Z,.PACK                   ; No.
    XOR  A                         ; Ten times,
    PUSH HL                        ; (the number kept)
    PUSH DE                        ; (and the count)
    CALL FL_MULT                   ; plus zero.
    POP  DE                        ; The count
    POP  HL                        ; and the number.
    DEC  DE                        ; One fewer.
    JR   .TENS                     ; The next.
.PACK:                         ; N / D is the value.
    CALL FL_PACK                   ; Rounded to f32:
    JP   C,TK_ENUM                 ; past it, malformed.
.WRITE:                        ; FL_Q is the f32.
    LD   HL,FL_Q                   ; Its bits
    LD   DE,TK_NLO                 ; are the token's value,
    LD   BC,4                      ; TK_NLO
    LDIR                           ; and TK_NHI,
    LD   A,SY_F32                  ; an f32
    LD   (TK_WIDE),A               ; literal.
    RET                            ; Done.
.ZERO:                         ; Too small: +0.
    LD   HL,FL_Q                   ; FL_Q
    CALL FL_CLR5                   ; zero
    JR   .WRITE                    ; is written.

;@ROUTINE OUT CARRY CLOBBERS A,BC,DE,HL,ZERO,SIGN,PARITY,HALFCARRY
; Take the digit at the cursor into N (.DIGIT); carry, with nothing
; consumed, when the cursor is at no digit.

.NEXT:                         ; The cursor's byte:
    CALL SRC_PEEK                  ; at the part's end
    RET  C                         ; there is none;
    CP   '0'                       ; below '0'
    RET  C                         ; and
    CP   '9'+1                     ; above '9'
    CCF                            ; neither.
    RET  C                         ; Not a digit.
    PUSH AF                        ; A digit:
    CALL SRC_TAKE                  ; consumed,
    POP  AF                        ; and taken; fall into .DIGIT.

;@ROUTINE IN A OUT CARRY CLOBBERS A,BC,DE,HL,ZERO,SIGN,PARITY,HALFCARRY
; N = N times ten plus the digit A, an ASCII digit, counted in FL_SIG once
; N is not zero (the significant digits). Carry returns clear.

.DIGIT:                        ; A is the digit.
    SUB  '0'                       ; Its value
    LD   HL,FL_N                   ; joins
    CALL FL_MULT                   ; N.
    LD   HL,FL_N                   ; Leading
    CALL FL_NZ                     ; zeros
    RET  Z                         ; count for nothing.
    LD   HL,(FL_SIG)               ; A significant
    INC  HL                        ; digit
    LD   (FL_SIG),HL               ; more.
    OR   A                         ; Carry clear.
    RET                            ; Done.

;@ROUTINE OUT A,CARRY CLOBBERS BC,DE,HL,IX,IY,ZERO,SIGN,PARITY,HALFCARRY
; Round N / D times 2^E, N and D not zero, with the sign FL_SIGN, to f32
; under FL_MODE's rule, its bits to FL_Q. FL_LOST returns nonzero when
; the f32 is not the value exactly. Carry when the value is past the
; largest f32. N and D are destroyed.
;
; N and D are first scaled so that N / D lies in 2^25 to 2^27, and the
; quotient q, 26 or 27 bits, is found by long division, the remainder's
; being nonzero kept as FL_LOST, the sticky bit. q is halved, the bits it
; loses kept in FL_LOST too, until it has 25: 24 for the significand and
; one more, the rounding bit, its lowest bit's weight 2^E.

FL_PACK:                       ; N / D times 2^E.
    LD   HL,FL_D                   ; Their
    CALL FL_BITS                   ; lengths
    PUSH DE                        ; in bits:
    LD   HL,FL_N                   ; D's kept,
    CALL FL_BITS                   ; N's in DE.
    POP  HL                        ; The shift
    LD   BC,26                     ; is 26
    ADD  HL,BC                     ; plus D's
    OR   A                         ; less
    SBC  HL,DE                     ; N's,
    EX   DE,HL                     ; DE,
    LD   HL,(FL_E)                 ; taken
    OR   A                         ; from
    SBC  HL,DE                     ; the
    LD   (FL_E),HL                 ; exponent.
    LD   HL,FL_N                   ; N is shifted left
    BIT  7,D                       ; by a positive one,
    JR   Z,.SCALE                  ; D by
    XOR  A                         ; a
    SUB  E                         ; negative
    LD   E,A                       ; one's
    SBC  A,A                       ; magnitude.
    SUB  D                         ; (DE
    LD   D,A                       ; negated)
    LD   HL,FL_D                   ; D.
.SCALE:                        ; HL is shifted DE times.
    CALL FL_SHLN                   ; N / D is from 2^25 to 2^27.
    LD   HL,FL_D                   ; D times
    LD   DE,26                     ; 2^26
    CALL FL_SHLN                   ; starts the division.
    LD   HL,FL_Q                   ; q
    CALL FL_CLR5                   ; starts at zero.
    LD   C,27                      ; 27 quotient bits:
.STEP:                         ; one a step.
    LD   HL,FL_Q                   ; q
    CALL VL_DBL4                   ; doubles.
    LD   DE,FL_N                   ; N less
    LD   HL,FL_D                   ; D
    LD   B,FL_NB                   ; where
    CALL VL_SUBN                   ; it fits:
    JR   NC,.FIT                   ; no borrow.
    LD   HL,FL_N                   ; Otherwise
    LD   DE,FL_D                   ; D is
    LD   B,FL_NB                   ; added
    CALL VL_ADDN                   ; back,
    JR   .HALF                     ; a zero bit.
.FIT:                          ; A one.
    LD   HL,FL_Q                   ; It is
    INC  (HL)                      ; q's lowest bit.
.HALF:                         ; D halves for the next.
    LD   HL,FL_D                   ; D
    CALL FL_SHR                    ; halved.
    DEC  C                         ; Until
    JR   NZ,.STEP                  ; every bit is found.
    LD   HL,FL_N                   ; The remainder:
    CALL FL_NZ                     ; nonzero,
    LD   (FL_LOST),A               ; the sticky bit.
.NARROW:                       ; q to 25 bits:
    LD   A,(FL_Q+3)                ; bits 25
    CP   2                         ; and 26
    JR   C,.FLOOR                  ; clear.
    CALL .QHALF                    ; Halved, the bit lost kept,
    CALL .EUP                      ; its weight doubled.
    JR   .NARROW                   ; Again.
.FLOOR:                        ; q is 25 bits, bit 0's weight 2^E.
    LD   HL,(FL_E)                 ; Its top bit's
    LD   DE,151                    ; exponent, E plus 24,
    ADD  HL,DE                     ; plus 127:
    BIT  7,H                       ; below zero,
    JP   NZ,FL_FLUSH               ; below 2^-127: zero.
    LD   A,H                       ; At zero,
    OR   L                         ; from 2^-127
    JR   NZ,.ROUND                 ; to 2^-126:
    LD   A,(FL_MODE)               ; a literal
    OR   A                         ; rounds as any other;
    JR   NZ,.ROUND                 ; a fold, at the denormals'
    LD   HL,(FL_Q)                 ; spacing,
    LD   DE,$FFFE                  ; is 2^-126
    OR   A                         ; when q is
    SBC  HL,DE                     ; 2^25-2
    LD   A,(FL_Q+2)                ; or more
    SBC  A,$FF                     ; (its third byte
    JP   C,FL_FLUSH                ; and bit 24): else zero.
    LD   HL,0                      ; Then
    LD   (FL_Q),HL                 ; 2^-126,
    LD   HL,$0080                  ; its significand's
    LD   (FL_Q+2),HL               ; leading bit alone,
    JR   .TOP                      ; with its sign.
.ROUND:                        ; Round to 24 bits.
    LD   A,(FL_LOST)               ; The sticky bit,
    LD   C,A                       ; kept;
    CALL .QHALF                    ; the rounding bit in carry,
    CALL .EUP                      ; q's weight doubled.
    JR   NC,.BIASED                ; Below a half, q.
    INC  C                         ; Above a half
    DEC  C                         ; (sticky)
    JR   NZ,.INCR                  ; rounds up;
    LD   A,(FL_Q)                  ; a half,
    RRCA                           ; to an even q:
    JR   NC,.BIASED                ; up when odd.
.INCR:                         ; Rounded up:
    LD   HL,FL_Q                   ; q
    LD   B,4                       ; plus
.UP:                           ; one,
    INC  (HL)                      ; the carry
    JR   NZ,.CARRIED               ; rippling
    INC  HL                        ; up.
    DJNZ .UP                       ; At most
.CARRIED:                      ; four bytes.
    LD   A,(FL_Q+3)                ; Past
    OR   A                         ; 24 bits?
    JR   Z,.BIASED                 ; No.
    CALL .QHALF                    ; Then 2^23 again,
    CALL .EUP                      ; its weight doubled.
.BIASED:                       ; q is 24 bits, bit 0's weight 2^E.
    LD   HL,(FL_E)                 ; The biased
    LD   DE,150                    ; exponent,
    ADD  HL,DE                     ; E plus 23 plus 127:
    BIT  7,H                       ; below one,
    JR   NZ,FL_FLUSH               ; zero;
    LD   A,H                       ; zero,
    OR   L                         ; also
    JR   Z,FL_FLUSH                ; zero;
    LD   A,H                       ; above
    OR   A                         ; 254,
    SCF                            ; past
    RET  NZ                        ; the largest
    LD   A,L                       ; f32:
    CP   255                       ; carry.
    CCF                            ; (from 255)
    RET  C                         ; Done.
    LD   HL,FL_Q+2                 ; Its low bit
    RRA                            ; tops
    RL   (HL)                      ; the significand's
    RRC  (HL)                      ; third byte,
    INC  HL                        ; the rest
    LD   (HL),A                    ; the fourth's.
.TOP:                          ; With the sign.
    LD   A,(FL_SIGN)               ; Its bit 7
    LD   HL,FL_Q+3                 ; tops
    OR   (HL)                      ; the
    LD   (HL),A                    ; f32;
    OR   A                         ; carry clear.
    RET                            ; Done.

;@ROUTINE OUT CARRY CLOBBERS A,B,HL,ZERO,SIGN,PARITY,HALFCARRY
; Halve q, four bytes; the bit lost leaves in carry and joins FL_LOST.

.QHALF:                        ; q is FL_Q.
    LD   HL,FL_Q+3                 ; From
    LD   B,4                       ; the top
    OR   A                         ; down,
.QBYTE:                        ; each byte
    RR   (HL)                      ; takes
    DEC  HL                        ; the bit
    DJNZ .QBYTE                    ; above.
    RET  NC                        ; Nothing lost,
    LD   HL,FL_LOST                ; or
    LD   (HL),1                    ; something:
    RET                            ; carry.

;@ROUTINE CLOBBERS DE,HL
; E plus one: the weight of q's bit 0 doubles. Flags are kept.

.EUP:                          ; q was halved.
    LD   HL,(FL_E)                 ; E
    INC  HL                        ; plus
    LD   (FL_E),HL                 ; one.
    RET                            ; Done.

;@ROUTINE OUT CARRY CLOBBERS A,HL,ZERO,SIGN,PARITY,HALFCARRY
; FL_PACK's result below the smallest normal: +0, as the reference flushes
; it, with FL_LOST set. Carry returns clear.

FL_FLUSH:                      ; Too small.
    LD   HL,FL_LOST                ; Not
    LD   (HL),1                    ; exact.
    LD   HL,FL_Q                   ; +0,
    OR   A                         ; carry clear.
    JR   FL_CLR5                   ; Written.

;@ROUTINE OUT A CLOBBERS B,HL,CARRY,ZERO,SIGN,PARITY,HALFCARRY
; Begin a result: N zero, D one, E zero, the sign positive, FL_LOST and
; FL_MODE zero (a fold's rounding). A returns zero.

FL_INIT:                       ; A fresh value.
    LD   HL,FL_N                   ; N
    CALL FL_ZERO                   ; is zero;
    LD   HL,0                      ; E
    LD   (FL_E),HL                 ; is zero,
    LD   (FL_SIGN),HL              ; the sign positive
    LD   (FL_LOST),HL              ; and nothing lost
    XOR  A                         ; (A zero);
                                   ; fall into FL_UNIT.

;@ROUTINE CLOBBERS B,HL,ZERO,SIGN,PARITY,HALFCARRY
; D = 1. A and carry are kept.

FL_UNIT:                       ; D is to be one.
    LD   HL,FL_D                   ; D
    CALL FL_ZERO                   ; is zero,
    INC  (HL)                      ; plus one.
    RET                            ; Done.

;@ROUTINE IN HL OUT HL CLOBBERS B
; Zero the FL_NB bytes at HL; HL returns their first. A and the flags are
; kept.

FL_ZERO:                       ; HL is a number.
    LD   B,FL_NB                   ; Its bytes.
    JR   FL_CLRN                   ; Cleared.

;@ROUTINE IN HL OUT HL CLOBBERS B
; Zero the five bytes at HL; HL returns their first. A and the flags are
; kept.

FL_CLR5:                       ; HL is a value.
    LD   B,5                       ; Its bytes; fall into FL_CLRN.

;@ROUTINE IN B,HL OUT HL CLOBBERS B
; Zero the B bytes at HL; HL returns their first. A and the flags are
; kept.

FL_CLRN:                       ; B bytes at HL.
    PUSH HL                        ; Keep the first.
.LOOP:                         ; Each
    LD   (HL),0                    ; is zero.
    INC  HL                        ; The next.
    DJNZ .LOOP                     ; All of them.
    POP  HL                        ; The first.
    RET                            ; Done.

;@ROUTINE IN HL OUT A,ZERO CLOBBERS B,HL,CARRY,SIGN,PARITY,HALFCARRY
; NZ when the FL_NB-byte number at HL is not zero; A is then nonzero.

FL_NZ:                         ; HL is a number.
    LD   B,FL_NB                   ; Its bytes
    XOR  A                         ; ored
.LOOP:                         ; together:
    OR   (HL)                      ; zero
    INC  HL                        ; only
    DJNZ .LOOP                     ; when it is.
    OR   A                         ; Z when zero.
    RET                            ; A is nonzero otherwise.

;@ROUTINE IN HL OUT DE CLOBBERS A,B,HL,CARRY,ZERO,SIGN,PARITY,HALFCARRY
; DE is the length in bits of the FL_NB-byte number at HL, zero for zero.

FL_BITS:                       ; HL is a number.
    LD   DE,FL_NB-1                ; Its top
    ADD  HL,DE                     ; byte,
    LD   B,FL_NB                   ; then down
.SCAN:                         ; to the first
    LD   A,(HL)                    ; that is
    OR   A                         ; not
    JR   NZ,.FOUND                 ; zero.
    DEC  HL                        ; The next
    DJNZ .SCAN                     ; down.
    LD   D,B                       ; None:
    LD   E,B                       ; zero bits.
    RET                            ; Done.
.FOUND:                        ; B is the byte's place plus one, A it.
    LD   L,B                       ; Eight bits
    LD   H,0                       ; for each
    DEC  HL                        ; byte
    ADD  HL,HL                     ; below
    ADD  HL,HL                     ; this
    ADD  HL,HL                     ; one,
.BIT:                          ; then one for each
    INC  HL                        ; bit up to
    SRL  A                         ; its highest
    JR   NZ,.BIT                   ; set.
    EX   DE,HL                     ; DE is the length.
    RET                            ; Done.

;@ROUTINE IN DE,HL CLOBBERS A,B,DE,CARRY,ZERO,SIGN,PARITY,HALFCARRY
; Shift the FL_NB-byte number at HL left DE bits (capacity past FL_NB
; bytes). HL is kept.

FL_SHLN:                       ; HL is the number, DE the count.
    LD   A,D                       ; Any
    OR   E                         ; left?
    RET  Z                         ; No: done.
    PUSH HL                        ; Keep the number,
    LD   B,FL_NB                   ; its bytes
    CALL VL_DBLN                   ; doubled:
    POP  HL                        ; (kept)
    JR   C,FL_FULL                 ; past them, refused.
    DEC  DE                        ; One fewer.
    JR   FL_SHLN                   ; The next.

;@ROUTINE NORETURN
; A literal too long for FL_NB bytes: capacity, `f32 digits`.

FL_FULL:                       ; FL_N or FL_D overflowed.
    CALL DG_RAISE                  ; Refused:
    DB   DG_FDIG                   ; the literal's digits.

;@ROUTINE IN HL OUT CARRY CLOBBERS A,B,DE,HL,ZERO,SIGN,PARITY,HALFCARRY
; Halve the FL_NB-byte number at HL; the bit lost leaves in carry.

FL_SHR:                        ; HL is the number.
    LD   DE,FL_NB-1                ; Its top
    ADD  HL,DE                     ; byte,
    LD   B,FL_NB                   ; then down,
    OR   A                         ; a zero entering the top:
.LOOP:                         ; each byte
    RR   (HL)                      ; takes
    DEC  HL                        ; the bit
    DJNZ .LOOP                     ; above.
    RET                            ; Carry is the bit lost.

;@ROUTINE IN HL CLOBBERS A,B,HL,CARRY,ZERO,SIGN,PARITY,HALFCARRY
; Negate the FL_NB-byte number at HL.

FL_NEGN:                       ; HL is the number.
    LD   B,FL_NB                   ; Its bytes,
    OR   A                         ; no borrow in:
.LOOP:                         ; each
    LD   A,0                       ; zero less
    SBC  A,(HL)                    ; it and the borrow
    LD   (HL),A                    ; in place.
    INC  HL                        ; The next.
    DJNZ .LOOP                     ; All of them.
    RET                            ; Done.

;@ROUTINE IN A,HL CLOBBERS A,BC,DE,HL,CARRY,ZERO,SIGN,PARITY,HALFCARRY
; The FL_NB-byte number at HL times ten plus A (capacity past FL_NB
; bytes).

FL_MULT:                       ; HL is the number, A the digit.
    LD   C,A                       ; C carries into each byte.
    LD   B,FL_NB                   ; Its bytes,
.LOOP:                         ; from the lowest:
    PUSH HL                        ; (its place)
    LD   E,(HL)                    ; the byte
    LD   D,0                       ; as a word,
    LD   H,D                       ; HL
    LD   L,E                       ; too:
    ADD  HL,HL                     ; twice,
    ADD  HL,HL                     ; four times,
    ADD  HL,DE                     ; five,
    ADD  HL,HL                     ; ten times,
    LD   E,C                       ; plus
    ADD  HL,DE                     ; the carry.
    LD   C,H                       ; Its high byte carries on;
    LD   A,L                       ; its low byte
    POP  HL                        ; is
    LD   (HL),A                    ; the new one.
    INC  HL                        ; The next.
    DJNZ .LOOP                     ; All of them.
    INC  C                         ; Anything
    DEC  C                         ; left over
    RET  Z                         ; is past them:
    JR   FL_FULL                   ; refused.

;@ROUTINE IN DE,HL CLOBBERS A,B,DE,HL,CARRY,ZERO,SIGN,PARITY,HALFCARRY
; Unpack the f32 at HL into the five bytes at DE: its sign (bit 7), its
; biased exponent, and its significand, three bytes with the leading bit,
; zero when the exponent is.

FL_OPEN:                       ; HL is the f32, DE the place.
    INC  HL                        ; Its
    INC  HL                        ; third
    LD   B,(HL)                    ; byte
    INC  HL                        ; and
    LD   A,(HL)                    ; fourth:
    AND  $80                       ; the sign
    LD   (DE),A                    ; first;
    INC  DE                        ; then
    LD   A,B                       ; the exponent,
    RLA                            ; its low bit
    LD   A,(HL)                    ; and
    RLA                            ; its seven others,
    LD   (DE),A                    ; second.
    DEC  HL                        ; The
    DEC  HL                        ; significand's
    DEC  HL                        ; first byte:
    OR   A                         ; a zero exponent
    JR   NZ,.SIGNIF                ; makes it
    EX   DE,HL                     ; zero,
    INC  HL                        ; three
    LD   B,3                       ; bytes.
    JP   FL_CLRN                   ; Done.
.SIGNIF:                       ; Otherwise its three bytes:
    INC  DE                        ; copied
    LD   BC,3                      ; with
    LDIR                           ; the leading
    DEC  DE                        ; bit
    EX   DE,HL                     ; set
    SET  7,(HL)                    ; in the third.
    RET                            ; Done.

;@ROUTINE IN HL CLOBBERS A,BC,DE,HL,CARRY,ZERO,SIGN,PARITY,HALFCARRY
; N = the significand of the unpacked f32 at HL (FL_OPEN's form); FL_SIGTO
; copies it to the zeroed FL_NB-byte number at DE instead.

FL_NSIG:                       ; HL is unpacked.
    LD   DE,FL_N                   ; Into N.
FL_SIGTO:                      ; Into DE.
    PUSH HL                        ; Keep the source.
    EX   DE,HL                     ; The number
    CALL FL_ZERO                   ; is zero,
    EX   DE,HL                     ; then
    POP  HL                        ; the
    INC  HL                        ; significand's
    INC  HL                        ; three bytes
    LD   BC,3                      ; are its
    LDIR                           ; lowest.
    RET                            ; Done.

;@ROUTINE IN A,HL CLOBBERS A,DE,HL,CARRY,ZERO,SIGN,PARITY,HALFCARRY
; E = HL plus A, A unsigned (FL_ESET); FL_EADD adds A to E.

FL_EADD:                       ; E plus A.
    LD   HL,(FL_E)                 ; From E.
FL_ESET:                       ; HL plus A.
    LD   E,A                       ; A
    LD   D,0                       ; as a word,
    ADD  HL,DE                     ; added,
    LD   (FL_E),HL                 ; is E.
    RET                            ; Done.

FL_CEND:                       ; End of the overlay's code (marker).

; The overlay's workspace, FL_WBEG to FL_WEND, is resident (MEMORY.ASM),
; so that it takes no records of the overlay area.

FL_END:                        ; End of the overlay (marker).
