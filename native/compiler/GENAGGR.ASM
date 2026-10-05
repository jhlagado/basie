;==========================================================================
;  Aggregate code generation
;==========================================================================
;
;  The reference compiler's templates for paths into records, arrays and
;  strings (ref/compile/compiler.ts: emitAddress, loadDesignator, indexArray,
;  indexString, boundsCheck, scaleHL, addConst) and for its string
;  literals, which follow the routine's need word (compileBody). CALLS.ASM
;  parses a path and keeps its place in RO_PLACE (CALLWORK.ASM); these
;  routines write its code.
;
;  A place says where the object a path names is, as the reference's Place
;  does:
;    GA_BLOB   static: RO_PADD bytes into blob RO_PBASE (a program
;              variable or an aggregate constant)
;    GA_FRAME  in the frame, at IX+RO_PADD (a local, or an open string's
;              capacity word)
;    GA_ALIAS  RO_PADD bytes on from the address in the word at
;              IX+RO_PBASE (an aggregate parameter)
;    GA_HELD   computed: the address is in HL
;  The reference writes a path's code when the path is used. Here each
;  step's code is written as soon as it is parsed. Nothing comes between
;  the end of a path and its use (the reference's arguments compute the
;  address first, too), so the bytes come out in the same order, and only
;  the place in hand is kept.
;
;  Literals. A string literal is an object of its own that follows the
;  routine's need word, in the order the literals were made. Each has an
;  entry of six bytes in RO_LTAB (CALLWORK.ASM): the address of the addend
;  word of its operand's reference, which is written when the literal is
;  placed, the source address of its opening quote, its decoded length and
;  the bytes it occupies: its length byte, its characters, then zeros, as
;  many as its string's capacity and terminator need.
;
;  Principal entries:
;    GA_ADDR   leave the place's address in HL (emitAddress)
;    GA_ADDC   add a constant to HL (addConst)
;    GA_MOVE   move the place on by a field's or element's offset
;    GA_LOAD   load the scalar at the place (loadDesignator)
;    GA_STORE  store the registers into the scalar at the place
;    GA_ITEM   address an array element at a run-time index
;    GA_CHAR   address a string's character, checked against its length
;    GA_LIT    LD HL, a string literal
;    GA_LITS   place the routine's literals

;@ROUTINE CLOBBERS A,BC,DE,HL,CARRY,ZERO,SIGN,PARITY,HALFCARRY
; Leave the address of the place in hand in HL (emitAddress): LD HL,nn for a
; static place; PUSH IX, POP HL and the offset for a frame place; the
; address word for an alias, and the bytes on from it; nothing when it is
; computed already. The place is computed afterwards.

GA_ADDR:                       ; RO_PLACE is the place.
    LD   HL,RO_PKIND               ; Its kind,
    LD   A,(HL)                    ; read,
    LD   (HL),GA_HELD              ; becomes computed.
    LD   HL,(RO_PADD)              ; The bytes on from the base.
    OR   A                         ; Static?
    JR   Z,.STATIC                 ; LD HL,nn.
    DEC  A                         ; The frame?
    JR   Z,.FRAME                  ; PUSH IX, POP HL.
    DEC  A                         ; An alias?
    RET  NZ                        ; No: computed, in HL already.
    PUSH HL                        ; Keep the bytes on.
    LD   HL,(RO_PBASE)             ; The address word's offset from IX,
    LD   A,SY_U16                  ; a word,
    CALL GX_FLOAD                  ; loaded into HL (ixWord).
    POP  HL                        ; The bytes on
    JR   GA_ADDC                   ; are added; return.
.FRAME:                        ; HL is the offset from IX.
    CALL EM_SEQ                    ; HL = IX:
    DB   3,$DD,$E5,$E1             ; PUSH IX, POP HL.
    JR   GA_ADDS                   ; Then the offset (addSigned); return.
.STATIC:                       ; HL is the offset into the blob.
    EX   DE,HL                     ; It is the addend,
    LD   BC,(RO_PBASE)             ; of a reference to the blob,
    LD   A,$21                     ; the operand of LD HL,nn.
    JP   GX_ABSD                   ; Append them and return.

;@ROUTINE IN HL CLOBBERS A,B,HL,CARRY,ZERO,SIGN,PARITY,HALFCARRY
; Add the constant HL to the address in HL at run time (addConst): INC HL
; for each of one to three, LD DE,n and ADD HL,DE above that, nothing for
; zero.

GA_ADDC:                       ; HL is the constant.
    LD   A,H                       ; Above 255?
    OR   A                         ; Then
    JR   NZ,GA_ADDS                ; through DE.
    LD   A,L                       ; Above three?
    CP   4                         ; Then
    JR   NC,GA_ADDS                ; through DE.
    OR   A                         ; Zero?
    RET  Z                         ; Nothing to add.
    LD   B,A                       ; One INC HL each.
.STEP:                         ; B remain.
    CALL EM_OP                     ; INC HL.
    DB   $23                       ; Append it.
    DJNZ .STEP                     ; Until each is added.
    RET                            ; HL is moved on.

;@ROUTINE IN HL CLOBBERS A,CARRY,ZERO,SIGN,PARITY,HALFCARRY
; Add the constant HL to the address in HL at run time through DE
; (addSigned): LD DE,n and ADD HL,DE, nothing for zero.

GA_ADDS:                       ; HL is the constant.
    LD   A,H                       ; Zero?
    OR   L                         ; Then
    RET  Z                         ; nothing is added.
    CALL EM_OP                     ; LD DE,n,
    DB   $11                       ; the opcode,
    CALL EM_WORD                   ; and n.
    LD   A,$19                     ; ADD HL,DE.
    JP   EM_BYTE                   ; Append it and return.

;@ROUTINE IN HL CLOBBERS A,B,DE,HL,CARRY,ZERO,SIGN,PARITY,HALFCARRY
; Move the place in hand on by HL bytes, a field's or an element's offset
; (offsetPlace): a computed place adds them to HL at run time; any other
; keeps them in RO_PADD.

GA_MOVE:                       ; HL is the offset.
    LD   A,(RO_PKIND)              ; Is the place computed?
    CP   GA_HELD                   ; Then the code adds it,
    JR   Z,GA_ADDC                 ; and returns.
    LD   DE,(RO_PADD)              ; Otherwise the bytes on
    ADD  HL,DE                     ; grow
    LD   (RO_PADD),HL              ; by it.
    RET                            ; The place has moved.

;@ROUTINE CLOBBERS A,BC,DE,HL,CARRY,ZERO,SIGN,PARITY,HALFCARRY
; Load the scalar of type RO_OTYPE at the place into A or HL
; (loadDesignator): from a static place LD A,(nn) or LD HL,(nn); from the
; frame (IX+d) near or far; through an alias or a computed address LD
; A,(HL), or LD E,(HL), INC HL, LD D,(HL), EX DE,HL for a word.

GA_LOAD:                       ; RO_PLACE is the place.
    LD   DE,GX_DLDA                ; A byte for the frame,
    LD   BC,$3A7E                  ; LD A,(nn) or LD A,(HL),
    LD   A,(RO_OTYPE)              ; unless
    CP   SY_U16                    ; it is a word:
    JR   NZ,GA_ACC                 ; then
    LD   DE,GX_DLDHL               ; a word for the frame,
    LD   BC,$2A00                  ; LD HL,(nn), or the sequence.
    CALL GA_ACC                    ; The access: a sequence when C is zero.
    RET  NZ                        ; Written.
    CALL EM_SEQ                    ; A word through HL:
    DB   4,$5E,$23,$56,$EB         ; LD E,(HL), INC HL, LD D,(HL), EX DE,HL.
    RET                            ; HL is the value.

;@ROUTINE CLOBBERS A,BC,DE,HL,CARRY,ZERO,SIGN,PARITY,HALFCARRY
; Store A or HL, of type RO_OTYPE, into the scalar at a place that is not
; computed (storeRegisters): LD (nn),A or LD (nn),HL for a static place,
; (IX+d) near or far for the frame. A computed place takes the address
; first (RO_LET).

GA_STORE:                      ; RO_PLACE is the place.
    LD   DE,GX_DSTA                ; A byte for the frame,
    LD   BC,$3200                  ; or LD (nn),A,
    LD   A,(RO_OTYPE)              ; unless
    CP   SY_U16                    ; it is a word:
    JR   NZ,GA_ACC                 ; then
    LD   DE,GX_DSTHL               ; a word for the frame,
    LD   B,$22                     ; or LD (nn),HL.

;@ROUTINE IN B,C,DE OUT ZERO CLOBBERS A,BC,DE,HL,CARRY,SIGN,PARITY,HALFCARRY
; Append an access to the scalar at the place: opcode B with an operand
; referring to a static place; frame access DE (GENEXPR.ASM) for a frame
; place; otherwise its address into HL, then the byte C if it is nonzero.
; Z returns when C was zero and nothing followed the address.

GA_ACC:                        ; B, C and DE are the three forms.
    LD   A,(RO_PKIND)              ; The place's kind.
    OR   A                         ; Static?
    JR   Z,.STATIC                 ; Opcode B.
    DEC  A                         ; The frame?
    JR   Z,.FRAME                  ; Access DE.
    PUSH BC                        ; Keep the byte C.
    CALL GA_ADDR                   ; The address into HL.
    POP  BC                        ; C is the byte.
    LD   A,C                       ; Is there one?
    OR   A                         ; Zero: the caller writes the rest.
    RET  Z                         ; Return Z.
    JP   EM_BYTE                   ; Append it; NZ returns.
.FRAME:                        ; DE is the access.
    LD   HL,(RO_PADD)              ; The offset from IX.
    CALL GX_FACC                   ; Append the access.
    OR   1                         ; NZ: written.
    RET                            ; Done.
.STATIC:                       ; B is the opcode.
    LD   A,B                       ; The opcode,
    LD   DE,(RO_PADD)              ; with the bytes on as the addend
    LD   BC,(RO_PBASE)             ; of a reference to the blob.
    CALL GX_ABSD                   ; Append them.
    OR   1                         ; NZ: written.
    RET                            ; Done.

;@ROUTINE IN D,HL CLOBBERS A,BC,DE,HL,CARRY,ZERO,SIGN,PARITY,HALFCARRY
; Address an element of the array RO_OTYPE at a run-time index
; (indexArray): the index, metadata D and value HL, into HL as a u16;
; LD DE,length, OR A, SBC HL,DE, CALL NC,TRAP_BND, ADD HL,DE (boundsCheck);
; the index scaled by the element's size (GA_SCALE); then the base's
; address, pushed already when RO_PPUSH says so, otherwise addressed now
; with the scaled index pushed meanwhile; POP DE, ADD HL,DE. The place is
; computed afterwards.

GA_ITEM:                       ; D and HL are the index.
    LD   E,SY_U16                  ; The index
    CALL GX_TOREG                  ; into HL as a word.
    LD   A,(RO_OTYPE)              ; The array's
    CALL AG_DESC                   ; descriptor:
    INC  HL                        ; its element type
    LD   A,(HL)                    ; is kept,
    PUSH AF                        ; for the stride.
    INC  HL                        ; Then its length:
    LD   E,(HL)                    ; low byte
    INC  HL                        ; and
    LD   D,(HL)                    ; high byte.
    CALL EM_OP                     ; LD DE,length:
    DB   $11                       ; the opcode,
    EX   DE,HL                     ; and the length
    CALL EM_WORD                   ; as its operand.
    CALL EM_SEQ                    ; OR A, SBC HL,DE:
    DB   3,$B7,$ED,$52             ; no borrow when the index is past it,
    LD   A,$D4                     ; so CALL NC
    CALL GA_BOUND                  ; to the bounds trap.
    CALL EM_OP                     ; ADD HL,DE: the index again.
    DB   $19                       ; Append it.
    POP  AF                        ; The element type
    LD   (RO_OTYPE),A              ; is the path's next,
    CALL AG_SIZE                   ; and its size, HL,
    CALL GA_SCALE                  ; multiplies the index.
    LD   A,(RO_PPUSH)              ; Is the base pushed?
    RRCA                           ; Then pop it:
    JR   C,.POP                    ; POP DE.
    CALL EM_OP                     ; Otherwise keep the offset:
    DB   $E5                       ; PUSH HL,
    LD   A,2                       ; two bytes
    CALL EM_PUSH                   ; pushed,
    CALL GA_ADDR                   ; while the base is addressed.
.POP:                          ; The other operand is pushed.
    CALL EM_OP                     ; POP DE.
    DB   $D1                       ; Append it.
    CALL EM_POP2                   ; Two bytes fewer pushed.
    LD   A,$19                     ; ADD HL,DE: the element's address.
    JP   EM_BYTE                   ; Append it and return.

;@ROUTINE IN D,HL CLOBBERS A,BC,DE,HL,CARRY,ZERO,SIGN,PARITY,HALFCARRY
; Address a character of the string at the place (indexString): the index,
; metadata D and value HL, into HL as a u16; the string's address into HL
; and the index into DE, whether the base was pushed (RO_PPUSH) or is
; addressed now; trap unless the index is below the length byte at (HL),
; with a zero high byte; then the character's address. The place is
; computed afterwards.

GA_CHAR:                       ; D and HL are the index.
    LD   E,SY_U16                  ; The index
    CALL GX_TOREG                  ; into HL as a word.
    LD   A,SY_U8                   ; A character
    LD   (RO_OTYPE),A              ; is a u8.
    LD   A,(RO_PPUSH)              ; Is the string's address pushed?
    RRCA                           ; Then
    JR   NC,.BASE                  ; it is popped:
    CALL EM_SEQ                    ; EX DE,HL, POP HL.
    DB   2,$EB,$E1                 ; The index is in DE.
    JR   .CHECK                    ; Check it.
.BASE:                         ; The string is addressed now.
    CALL EM_OP                     ; PUSH HL:
    DB   $E5                       ; the index waits,
    LD   A,2                       ; two bytes
    CALL EM_PUSH                   ; pushed,
    CALL GA_ADDR                   ; while the string is addressed,
    CALL EM_OP                     ; then POP DE
    DB   $D1                       ; brings it back.
.CHECK:                        ; HL is the string, DE the index.
    CALL EM_POP2                   ; Two bytes fewer pushed.
    CALL EM_SEQ                    ; LD A,E, CP (HL):
    DB   2,$7B,$BE                 ; carry when the index is below the length;
    LD   A,$D4                     ; CALL NC
    CALL GA_BOUND                  ; to the bounds trap.
    CALL EM_SEQ                    ; LD A,D, OR A:
    DB   2,$7A,$B7                 ; a high byte is out of range too;
    LD   A,$C4                     ; CALL NZ
    CALL GA_BOUND                  ; to the bounds trap.
    CALL EM_SEQ                    ; INC HL, ADD HL,DE.
    DB   2,$23,$19                 ; Past the length byte, the index on.
    RET                            ; HL is the character.

;@ROUTINE IN A CLOBBERS A,DE,HL,CARRY,ZERO,SIGN,PARITY,HALFCARRY
; Append the trap site CALL cc,TRAP_BND whose opcode is A (boundsCheck).

GA_BOUND:                      ; A is CALL cc.
    LD   L,HP_BOUND&$FF            ; The bounds trap.
    JP   EM_TRAP                   ; Append the site and return.

;@ROUTINE IN HL CLOBBERS A,DE,HL,CARRY,ZERO,SIGN,PARITY,HALFCARRY
; Multiply the index in HL at run time by the stride HL (scaleHL): nothing
; for one, ADD HL,HL for each halving of a power of two, otherwise a
; shift-and-add from a copy in DE: LD D,H, LD E,L, LD HL,0, then for each
; bit from the lowest ADD HL,DE when it is set and EX DE,HL, ADD HL,HL, EX
; DE,HL while bits remain above it.

GA_SCALE:                      ; HL is the stride.
    LD   D,H                       ; DE is
    LD   E,L                       ; the stride
    DEC  DE                        ; less one,
    LD   A,D                       ; which shares
    AND  H                         ; no bit
    LD   D,A                       ; with it
    LD   A,E                       ; when it is
    AND  L                         ; a power
    OR   D                         ; of two.
    JR   NZ,.GENERAL               ; It is not.
.DOUBLE:                       ; HL is a power of two.
    SRL  H                         ; Halve
    RR   L                         ; it.
    LD   A,H                       ; Was it one?
    OR   L                         ; Then
    RET  Z                         ; every doubling is written.
    CALL EM_OP                     ; ADD HL,HL
    DB   $29                       ; doubles the index.
    JR   .DOUBLE                   ; Until the stride is one.
.GENERAL:                      ; Shift and add.
    CALL EM_SEQ                    ; LD D,H, LD E,L, LD HL,0:
    DB   5,$54,$5D,$21,0,0         ; DE is the index, HL the product.
.BIT:                          ; HL is the stride's bits left.
    SRL  H                         ; The lowest
    RR   L                         ; into carry.
    LD   A,$19                     ; ADD HL,DE
    CALL C,EM_BYTE                 ; when it is set.
    LD   A,H                       ; Any bits left?
    OR   L                         ; Zero when none.
    RET  Z                         ; The product is in HL.
    CALL EM_SEQ                    ; EX DE,HL, ADD HL,HL, EX DE,HL:
    DB   3,$EB,$29,$EB             ; DE doubles.
    JR   .BIT                      ; The next bit.

;@ROUTINE IN B CLOBBERS A,BC,DE,HL,CARRY,ZERO,SIGN,PARITY,HALFCARRY
; Append LD HL,literal for the string literal just read (TK_PTR, TK_LEN),
; which occupies B bytes after the routine's need word: an operand naming
; the routine itself, its addend written when the literal is placed
; (GA_LITS). In discarded code nothing is written and no literal is made,
; as the reference discards it. DG_LITS when the routine has RO_LCAP.

GA_LIT:                        ; B is the literal's size.
    CALL EM_OP                     ; LD HL,nn.
    DB   $21                       ; The opcode.
    CALL EM_QUIET                  ; Is the code discarded?
    RET  NZ                        ; Then so is the literal.
    LD   HL,RO_LCNT                ; The literals so far.
    LD   A,(HL)                    ; Is there room
    CP   RO_LCAP                   ; for another?
    JR   NC,.FULL                  ; No: refuse the routine.
    INC  (HL)                      ; Count it.
    LD   L,A                       ; HL is its index
    LD   H,0                       ; as a word,
    ADD  HL,HL                     ; times two,
    LD   D,H                       ; kept;
    LD   E,L                       ; times
    ADD  HL,HL                     ; four,
    ADD  HL,DE                     ; six, the entry's size.
    LD   DE,RO_LTAB                ; Plus the table's
    ADD  HL,DE                     ; address.
    PUSH BC                        ; Keep the size
    PUSH HL                        ; and the entry.
    LD   HL,(BL_ORD)               ; The routine itself,
    LD   DE,EM_NONE                ; with a placeholder addend:
    CALL EM_REF                    ; the operand.
    POP  HL                        ; The entry.
    LD   DE,(BL_RPTR)              ; The addend word is the last
    DEC  DE                        ; two bytes of
    DEC  DE                        ; the references:
    LD   (HL),E                    ; it is the
    INC  HL                        ; entry's
    LD   (HL),D                    ; first word.
    INC  HL                        ; Then
    LD   DE,(TK_PTR)               ; the opening quote's
    LD   (HL),E                    ; address,
    INC  HL                        ; low
    LD   (HL),D                    ; and high.
    INC  HL                        ; Then
    LD   A,(TK_LEN)                ; the decoded
    LD   (HL),A                    ; length,
    INC  HL                        ; then
    POP  BC                        ; the size
    LD   (HL),B                    ; it occupies.
    RET                            ; Placed when the routine closes.
.FULL:                         ; Every entry is in use.
    CALL DG_RAISE                  ; Refuse the routine.
    DB   DG_LITS                   ; Too many literals.

;@ROUTINE CLOBBERS A,BC,DE,HL,CARRY,ZERO,SIGN,PARITY,HALFCARRY
; Place the routine's literals after its need word, in the order they were
; made: each one's offset into the addend word of its operand, then its
; length byte, its characters decoded from the source (AG_CHAR) and zeros
; to its size.

GA_LITS:                       ; The need word is written.
    LD   HL,RO_LCNT                ; The literals:
    LD   A,(HL)                    ; how many?
    OR   A                         ; None:
    RET  Z                         ; nothing to place.
    LD   B,A                       ; B remain.
    LD   HL,RO_LTAB                ; The first entry.
.NEXT:                         ; HL is an entry.
    PUSH BC                        ; Keep the count.
    LD   E,(HL)                    ; DE is
    INC  HL                        ; its addend
    LD   D,(HL)                    ; word,
    INC  HL                        ; which takes
    LD   BC,(BL_LEN)               ; the offset
    EX   DE,HL                     ; where the
    LD   (HL),C                    ; literal
    INC  HL                        ; begins.
    LD   (HL),B                    ; Both bytes.
    EX   DE,HL                     ; HL is the entry again.
    LD   E,(HL)                    ; DE is
    INC  HL                        ; the opening
    LD   D,(HL)                    ; quote.
    INC  HL                        ; Then
    LD   C,(HL)                    ; the length,
    INC  HL                        ; and
    LD   B,(HL)                    ; the size.
    INC  HL                        ; The next entry
    PUSH HL                        ; is kept.
    LD   A,C                       ; The length byte
    CALL EM_BYTE                   ; first.
    DEC  B                         ; One fewer to come.
    EX   DE,HL                     ; HL is the quote.
    INC  HL                        ; The first character.
.CHAR:                         ; C characters remain.
    LD   A,C                       ; Any left?
    OR   A                         ; Zero when none.
    JR   Z,.ZERO                   ; Then the zeros.
    CALL AG_CHAR                   ; A is the next, decoded.
    CALL EM_BYTE                   ; Append it.
    DEC  B                         ; One fewer to come,
    DEC  C                         ; and one fewer character.
    JR   .CHAR                     ; The next.
.ZERO:                         ; B zeros remain.
    XOR  A                         ; Zero.
    CALL EM_BYTE                   ; Append it.
    DJNZ .ZERO                     ; At least the terminator.
    POP  HL                        ; The next entry.
    POP  BC                        ; The count.
    DJNZ .NEXT                     ; Until every literal is placed.
    RET                            ; The literals follow the need word.
