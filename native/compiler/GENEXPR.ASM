;==========================================================================
;  Expression code generation: values
;==========================================================================
;
;  The reference compiler's templates for scalar values (ref/compile/
;  compiler.ts: loadRegisters, storeRegisters, toRegisters, widen,
;  checkedNarrow), written as the expression parser (EXPR, EXTERM, EXOPER)
;  and the statement actions reach each step; the operators' templates
;  are in GENOPER.ASM. A value is in A when it is a byte (u8, i8 or a
;  Boolean), in HL when it is a word (u16 or i16) and in DEHL, HL low,
;  when it is a long (u32 or i32); a constant is not loaded until
;  something needs it in the registers, and then at the type that needs
;  it.
;
;  Frames. A local or parameter is addressed from IX, the frame pointer: a
;  local at a negative offset, a parameter at a positive one (design
;  decision D41). The reference's ixByte, ixWord, ixStoreA, ixStoreHL,
;  ixStoreDEHL and ixStoreImm reach a slot within IX-128..IX+127 as
;  (IX+d); a slot beyond that, in a frame larger than 128 bytes, through
;  its computed address, with the registers the access must keep pushed
;  around it and counted into the frame (GX_FACC). Each access is
;  described by a table entry:
;
;    +0  byte  its size less one
;    +1  byte  the bytes the far form pushes
;    +2  count and bytes: the far form's code before the address
;    then count and bytes: its code after the address, HL = IX+offset
;    then the near form's operations on (IX+d), (IX+d+1), ended by zero
;
;  An immediate store, LD (HL),n or LD (IX+d),n, takes n from GX_IMMV.
;
;  Principal entries:
;    GX_PROP   a scalar type's size and signedness
;    GX_LOAD   load a program variable of type A from blob BC
;    GX_STORE  store the registers into a program variable of type A
;    GX_FLOAD  load the local or parameter of type A at IX+HL
;    GX_FPUT   store the registers into the one of type A at IX+HL
;    GX_FZERO  zero B bytes of the frame from IX+HL
;    GX_TOREG  bring a result into the registers at a destination's type
;    GX_WIDEN  widen the registers from one type to another
;    GX_ZEXT   widen a byte in A to a word in HL with a zero high byte
;    GX_TRIM convert the registers with the checks of a narrowing
;    GX_PUSH   push a left operand while the right is computed
;    GX_POPV   pop it again
;    GX_PUSHW  PUSH HL, counted

;@ROUTINE IN A OUT A CLOBBERS CARRY,ZERO,SIGN,PARITY,HALFCARRY
; The properties of scalar type A (SY_EXACT..SY_F32, GX_PTAB): its size in
; bytes in bits 0 to 2, bit 6 for a Boolean or an f32, bit 7 for a signed
; type. Every other register is kept.

GX_PROP:                       ; A is the type.
    PUSH HL                        ; Keep HL.
    LD   HL,GX_PTAB                ; The table
    ADD  A,L                       ; indexed
    LD   L,A                       ; by
    ADC  A,H                       ; the
    SUB  L                         ; type
    LD   H,A                       ; is
    LD   A,(HL)                    ; its entry.
    POP  HL                        ; Restore HL.
    RET                            ; A is the properties.
GX_PTAB:                       ; Size, $40 not an integer, $80 signed.
    DB   0,1,2,$41                 ; Exact, u8, u16, boolean,
    DB   $81,$82,4,$84,$C4         ; i8, i16, u32, i32, f32.

;@ROUTINE IN A OUT A,CARRY,ZERO CLOBBERS SIGN,PARITY,HALFCARRY
; The size in bytes of scalar type A: 1, 2 or 4, compared with 2, so that
; carry means a byte and zero a word. Every other register is kept.

GX_SIZE:                       ; A is the type.
    CALL GX_PROP                   ; Its properties.
    AND  7                         ; Its size,
    CP   2                         ; compared with a word's.
    RET                            ; Carry: a byte; zero: a word.

;@ROUTINE IN A,BC CLOBBERS A,BC,DE,HL,CARRY,ZERO,SIGN,PARITY,HALFCARRY
; Load the program variable at blob BC, of scalar type A: LD A,(nn) for a
; byte, LD HL,(nn) for a word, LD HL,(nn) and LD DE,(nn+2) for a long.

GX_LOAD:                       ; A is the type, BC the variable's ordinal.
    CALL GX_SIZE                   ; Its size.
    LD   A,$3A                     ; LD A,(nn) for a byte.
    JR   C,GX_ABS                  ; A byte it is.
    LD   A,$2A                     ; LD HL,(nn) for a word.
    JR   Z,GX_ABS                  ; A word it is.
    LD   E,$5B                     ; A long: then LD DE,(nn+2).

;@ROUTINE IN A,BC,E CLOBBERS A,BC,DE,HL,CARRY,ZERO,SIGN,PARITY,HALFCARRY
; Append opcode A referring to blob BC, then $ED and opcode E referring to
; it two bytes on: a long's two words.

GX_LONG:                       ; A and E are the opcodes, BC the blob.
    LD   D,E                       ; Keep the second opcode
    PUSH DE                        ; in D,
    PUSH BC                        ; and the blob.
    CALL GX_ABS                    ; The low word's access.
    CALL EM_OP                     ; The prefix
    DB   $ED                       ; of the second.
    POP  BC                        ; The blob,
    POP  AF                        ; its opcode,
    LD   DE,2                      ; two bytes on.
    JR   GX_ABSD                   ; Append it and return.

;@ROUTINE IN A,BC CLOBBERS A,BC,DE,HL,CARRY,ZERO,SIGN,PARITY,HALFCARRY
; Append opcode A and an ABS16 operand referring to blob BC.

GX_ABS:                        ; A is the opcode, BC the target.
    LD   DE,0                      ; No addend; fall into GX_ABSD.

;@ROUTINE IN A,BC,DE CLOBBERS A,BC,DE,HL,CARRY,ZERO,SIGN,PARITY,HALFCARRY
; Append opcode A and an ABS16 operand referring to blob BC, DE bytes on.

GX_ABSD:                       ; A is the opcode, BC the target, DE the addend.
    CALL EM_BYTE                   ; The opcode.
    LD   H,B                       ; HL is the target,
    LD   L,C                       ; the variable's blob.
    JP   EM_REF                    ; Its address, and return.

;@ROUTINE IN A,BC CLOBBERS A,BC,DE,HL,CARRY,ZERO,SIGN,PARITY,HALFCARRY
; Store the registers into the program variable at blob BC, of scalar type
; A: LD (nn),A for a byte, LD (nn),HL for a word, LD (nn),HL and
; LD (nn+2),DE for a long.

GX_STORE:                      ; A is the type, BC the variable's ordinal.
    CALL GX_SIZE                   ; Its size.
    LD   A,$32                     ; LD (nn),A for a byte.
    JR   C,GX_ABS                  ; A byte it is.
    LD   A,$22                     ; LD (nn),HL for a word.
    JR   Z,GX_ABS                  ; A word it is.
    LD   E,$53                     ; A long: then LD (nn+2),DE.
    JR   GX_LONG                   ; Append both and return.

;@ROUTINE IN A,HL CLOBBERS A,BC,DE,HL,CARRY,ZERO,SIGN,PARITY,HALFCARRY
; Load the local or parameter of scalar type A at IX+HL: A for a byte
; (ixByte), HL for a word (ixWord), HL then DE for a long.

GX_FLOAD:                      ; A is the type, HL the offset.
    CALL GX_SIZE                   ; Its size.
    LD   DE,GX_DLDA                ; A byte into A.
    JR   C,GX_FACC                 ; A byte it is.
    LD   DE,GX_DLDHL               ; A word into HL.
    JR   Z,GX_FACC                 ; A word it is.
    PUSH HL                        ; A long: keep the offset.
    CALL GX_FACC                   ; Its low word into HL,
    POP  HL                        ; then,
    INC  HL                        ; two
    INC  HL                        ; bytes on,
    LD   DE,GX_DLDDE               ; its high word into DE.
    JR   GX_FACC                   ; Load it and return.

;@ROUTINE IN A,HL CLOBBERS A,BC,DE,HL,CARRY,ZERO,SIGN,PARITY,HALFCARRY
; Store the registers into the local or parameter of scalar type A at
; IX+HL: A for a byte (ixStoreA), HL for a word (ixStoreHL), DEHL for a
; long (ixStoreDEHL).

GX_FPUT:                       ; A is the type, HL the offset.
    CALL GX_SIZE                   ; Its size.
    LD   DE,GX_DSTA                ; A byte from A.
    JR   C,GX_FACC                 ; A byte it is.
    LD   DE,GX_DSTHL               ; A word from HL.
    JR   Z,GX_FACC                 ; A word it is.
    LD   DE,GX_DSTQ                ; A long from DEHL.
    JR   GX_FACC                   ; Store it and return.

;@ROUTINE IN B,HL CLOBBERS A,BC,DE,HL,CARRY,ZERO,SIGN,PARITY,HALFCARRY
; Zero the B bytes of the frame from IX+HL, one at a time (zeroFrame, for
; a local of four bytes or fewer without an initializer, through
; ixStoreImm).

GX_FZERO:                      ; B bytes from offset HL.
    XOR  A                         ; The immediate
    LD   (GX_IMMV),A               ; is zero.
.BYTE:                         ; B bytes remain from offset HL.
    PUSH BC                        ; Keep the count
    PUSH HL                        ; and the offset.
    LD   DE,GX_DSTN                ; LD (IX+d),0.
    CALL GX_FACC                   ; Zero this byte.
    POP  HL                        ; The offset
    INC  HL                        ; of the next byte.
    POP  BC                        ; The count.
    DJNZ .BYTE                     ; Until every byte is zero.
    RET                            ; The local is clear.

;@ROUTINE IN DE,HL CLOBBERS A,BC,DE,HL,CARRY,ZERO,SIGN,PARITY,HALFCARRY
; Append the frame access that entry DE describes (the module header) for
; the slot at IX+HL: its near form when every byte of the slot is within
; reach of (IX+d), its far form otherwise.

GX_FACC:                       ; DE is the entry, HL the offset.
    LD   A,(DE)                    ; C is the slot's size less one.
    LD   C,A                       ; Keep it for the test.
    INC  DE                        ; DE is the far form's push count.
    CALL .FAR                      ; Is any byte out of reach?
    JR   C,.FARFORM                ; Then compute the address.
    INC  DE                        ; Skip the push count,
    CALL .SKIP                     ; the code before the address
    CALL .SKIP                     ; and the code after it.
.NEAR:                         ; DE is the next operation, L its d.
    LD   A,(DE)                    ; The operation on (IX+d),
    OR   A                         ; zero after the last.
    RET  Z                         ; The access is written.
    CALL EM_OP                     ; Its IX prefix.
    DB   $DD                       ; Append it.
    LD   A,(DE)                    ; The operation.
    CALL EM_BYTE                   ; Append it.
    LD   A,L                       ; The displacement
    CALL EM_BYTE                   ; follows it.
    LD   A,(DE)                    ; Was it LD (IX+d),n?
    CP   $36                       ; Its immediate
    LD   A,(GX_IMMV)               ; is GX_IMMV.
    CALL Z,EM_BYTE                 ; Append it.
    INC  L                         ; The next byte of the slot.
    INC  DE                        ; The next operation.
    JR   .NEAR                     ; Append it.
.FARFORM:                      ; DE is the push count.
    LD   A,(DE)                    ; The bytes pushed around the address.
    INC  DE                        ; DE is the code before it.
    PUSH AF                        ; Keep the count.
    CALL .COPY                     ; Append the pushes.
    POP  AF                        ; The count,
    PUSH AF                        ; kept for the pop.
    PUSH DE                        ; Keep the code after the address
    PUSH HL                        ; and the offset.
    CALL EM_PUSH                   ; Count the pushes into the frame.
    POP  HL                        ; HL is the offset.
    CALL EM_SEQ                    ; HL = IX+offset (ixAddress):
    DB   4,$DD,$E5,$E1,$11         ; PUSH IX, POP HL, LD DE,offset,
    CALL EM_WORD                   ; the offset,
    CALL EM_OP                     ; then
    DB   $19                       ; ADD HL,DE.
    POP  DE                        ; DE is the code after the address.
    CALL .COPY                     ; Append it.
    POP  AF                        ; The pushes
    JP   EM_POP                    ; are popped again; return.

;@ROUTINE IN C,HL OUT CARRY CLOBBERS A,ZERO,SIGN,PARITY,HALFCARRY
; Carry unless the slot of C+1 bytes at IX+HL lies within IX-128..IX+127
; (the reference's ixNear): HL must be a sign-extended byte, and the slot's
; last byte no further than +127.

.FAR:                          ; HL is the offset, C the size less one.
    LD   A,L                       ; The low byte's sign
    RLA                            ; into carry,
    SBC  A,A                       ; then $00 or $FF:
    CP   H                         ; the high byte of a byte offset.
    SCF                            ; Out of reach
    RET  NZ                        ; when it is not one.
    LD   A,L                       ; The offset plus 128,
    XOR  $80                       ; from 0 for -128,
    ADD  A,C                       ; to the last byte: carry past +127.
    RET                            ; Carry if out of reach.

;@ROUTINE IN DE OUT DE CLOBBERS A,CARRY,ZERO,SIGN,PARITY,HALFCARRY
; Step DE over a count byte and that many bytes.

.SKIP:                         ; DE is the count.
    LD   A,(DE)                    ; The count,
    INC  DE                        ; then the bytes:
    ADD  A,E                       ; DE plus the count
    LD   E,A                       ; is past them,
    ADC  A,D                       ; with the carry
    SUB  E                         ; into the
    LD   D,A                       ; high byte.
    RET                            ; DE is after them.

;@ROUTINE IN DE OUT DE CLOBBERS A,B,CARRY,ZERO,SIGN,PARITY,HALFCARRY
; Append the count byte's bytes at DE, at least one; DE is left after them.
; LD (HL),n takes its immediate from GX_IMMV.

.COPY:                         ; DE is the count.
    LD   A,(DE)                    ; B is
    LD   B,A                       ; the count.
.BYTE:                         ; B bytes remain.
    INC  DE                        ; The next
    LD   A,(DE)                    ; byte.
    CALL EM_BYTE                   ; Append it; A is kept.
    CP   $36                       ; LD (HL),n?
    JR   NZ,.NEXT                  ; No.
    LD   A,(GX_IMMV)               ; Its immediate
    CALL EM_BYTE                   ; follows it.
.NEXT:                         ; The byte is written.
    DJNZ .BYTE                     ; Until the count is done.
    INC  DE                        ; DE is after them.
    RET                            ; The code is appended.

; The frame accesses, in GX_FACC's form (the module header).

GX_DLDA:                       ; ixByte: A = (IX+offset).
    DB   0,6                       ; One byte; the far form pushes six.
    DB   2,$E5,$D5                 ; PUSH HL, PUSH DE;
    DB   3,$7E,$D1,$E1             ; LD A,(HL), POP DE, POP HL.
    DB   $7E,0                     ; LD A,(IX+d).
GX_DLDHL:                      ; ixWord: HL = (IX+offset).
    DB   1,4                       ; Two bytes; the far form pushes four.
    DB   1,$D5                     ; PUSH DE;
    DB   5,$5E,$23,$56,$EB,$D1     ; LD E,(HL), INC HL, LD D,(HL), EX DE,HL, POP DE.
    DB   $6E,$66,0                 ; LD L,(IX+d), LD H,(IX+d+1).
GX_DLDDE:                      ; ixWord to DE: DE = (IX+offset), HL kept.
    DB   1,4                       ; Two bytes; the far form pushes four.
    DB   1,$E5                     ; PUSH HL;
    DB   4,$5E,$23,$56,$E1         ; LD E,(HL), INC HL, LD D,(HL), POP HL.
    DB   $5E,$56,0                 ; LD E,(IX+d), LD D,(IX+d+1).
GX_DSTA:                       ; ixStoreA: (IX+offset) = A.
    DB   0,6                       ; One byte; the far form pushes six.
    DB   2,$E5,$D5                 ; PUSH HL, PUSH DE;
    DB   3,$77,$D1,$E1             ; LD (HL),A, POP DE, POP HL.
    DB   $77,0                     ; LD (IX+d),A.
GX_DSTHL:                      ; ixStoreHL: (IX+offset) = HL.
    DB   1,6                       ; Two bytes; the far form pushes six.
    DB   2,$D5,$E5                 ; PUSH DE, PUSH HL;
    DB   6,$D1,$73,$23,$72,$EB,$D1 ; POP DE, LD (HL),E, INC HL, LD (HL),D, EX DE,HL, POP DE.
    DB   $75,$74,0                 ; LD (IX+d),L, LD (IX+d+1),H.
GX_DSTQ:                       ; ixStoreDEHL: (IX+offset) = DEHL, HL low.
    DB   3,10                      ; Four bytes; the far form pushes ten.
    DB   4,$D5,$E5,$D5,$E5         ; PUSH DE, PUSH HL, PUSH DE, PUSH HL;
    DB   11,$D1,$73,$23,$72,$23    ; POP DE, LD (HL),E, INC HL, LD (HL),D, INC HL,
    DB   $D1,$73,$23,$72,$E1,$D1   ; POP DE, the high word likewise, POP HL, POP DE.
    DB   $75,$74,$73,$72,0         ; LD (IX+d),L, H, E and D in turn.
GX_DSTN:                       ; ixStoreImm: (IX+offset) = GX_IMMV.
    DB   0,6                       ; One byte; the far form pushes six.
    DB   2,$E5,$D5                 ; PUSH HL, PUSH DE;
    DB   3,$36,$D1,$E1             ; LD (HL),n, POP DE, POP HL.
    DB   $36,0                     ; LD (IX+d),n.


;@ROUTINE IN D,E,HL CLOBBERS A,BC,CARRY,ZERO,SIGN,PARITY,HALFCARRY
; Bring the result with metadata D into the registers as type E, which
; EX_FITS has accepted for it (toRegisters): a known value, its low word
; in HL and the whole in EX_KVAL, is loaded at type E, LD A,n, LD HL,nn,
; or LD HL,nn and LD DE,nn for a long; a computed one is widened to E
; when its type is narrower (GX_WIDEN). DE and HL are kept.

GX_TOREG:                      ; D is the metadata, E the type, HL a known value.
    BIT  7,D                       ; SY_KNOWN: is the value known?
    JR   Z,.HELD                   ; No: it is in the registers.
    LD   A,E                       ; Load it at the destination's type:
    CALL GX_SIZE                   ; its size.
    JR   Z,GX_LDHL                 ; LD HL,nn for a word.
    JR   NC,.LONG                  ; A long takes two.
    CALL EM_OP                     ; LD A,n.
    DB   $3E                       ; The opcode.
    LD   A,L                       ; The value's low byte
    JP   EM_BYTE                   ; is its operand.
.LONG:                         ; A long destination.
    CALL GX_LDHL                   ; LD HL,low word,
    PUSH HL                        ; (HL kept)
    LD   HL,(EX_KVAL+2)            ; then the high word
    CALL GA_LDDE                   ; as LD DE,nn.
    POP  HL                        ; HL is the low word again.
    RET                            ; DEHL is the value.
.HELD:                         ; The value is in the registers.
    LD   A,D                       ; Its type
    AND  SY_TMASK                  ; alone.
    CP   E                         ; The destination's?
    RET  Z                         ; Nothing to do.
    PUSH DE                        ; Keep the metadata and the type.
    LD   D,A                       ; From its type
    CALL GX_WIDEN                  ; to E.
    POP  DE                        ; The metadata and the type.
    RET                            ; The value is in place.

;@ROUTINE IN HL CLOBBERS A,CARRY,ZERO,SIGN,PARITY,HALFCARRY
; Append LD HL,nn, nn in HL.

GX_LDHL:                       ; HL is nn.
    CALL EM_OP                     ; LD HL,nn:
    DB   $21                       ; the opcode,
    JP   EM_WORD                   ; and nn; return.

;@ROUTINE IN D,E CLOBBERS A,BC,CARRY,ZERO,SIGN,PARITY,HALFCARRY
; Widen the value in the registers from type D to type E, which it widens
; to (widen): a byte into HL, sign-extended (LD L,A, RLCA, SBC A,A,
; LD H,A) or not (LD L,A, LD H,0); then, for a long, HL into DEHL
; (LD A,H, RLCA, SBC A,A, LD D,A, LD E,A, or LD DE,0). D's signedness
; decides both. DE and HL are kept.

GX_WIDEN:                      ; D is the type, E the type it becomes.
    LD   A,D                       ; The source's
    CALL GX_PROP                   ; properties:
    LD   C,A                       ; C keeps them.
    AND  7                         ; A byte?
    DEC  A                         ; Then
    JR   NZ,.WORD                  ; it widens to a word first.
    BIT  7,C                       ; Signed?
    JR   Z,.ZERO                   ; No: a zero high byte.
    CALL EM_SEQ                    ; LD L,A, RLCA, SBC A,A, LD H,A:
    DB   4,$6F,$07,$9F,$67         ; the sign in H.
    JR   .WORD                     ; Then perhaps a long.
.ZERO:                         ; Unsigned.
    CALL GX_ZEXT                   ; LD L,A, LD H,0.
.WORD:                         ; The value is a word in HL.
    LD   A,E                       ; Is the destination
    CALL GX_SIZE                   ; a long?
    RET  C                         ; A byte: nothing more,
    RET  Z                         ; nor for a word.
    BIT  7,C                       ; Signed?
    JR   Z,.UNSIGNED               ; No: a zero high word.
    CALL EM_SEQ                    ; LD A,H, RLCA, SBC A,A, LD D,A, LD E,A:
    DB   5,$7C,$07,$9F,$57,$5F     ; the sign in DE.
    RET                            ; DEHL is the value.
.UNSIGNED:                     ; A zero high word:
    CALL EM_SEQ                    ; LD DE,0.
    DB   3,$11,0,0                 ; Append it.
    RET                            ; DEHL is the value.

;@ROUTINE CLOBBERS A,B,CARRY,ZERO,SIGN,PARITY,HALFCARRY
; Widen the byte in A to a word in HL with a zero high byte: LD L,A,
; LD H,0. DE and HL are kept.

GX_ZEXT:                       ; A byte becomes a word.
    CALL EM_SEQ                    ; The zero extension:
    DB   3,$6F,$26,0               ; LD L,A, LD H,0.
    RET                            ; The value is in HL.

;@ROUTINE IN A CLOBBERS A,DE,HL,CARRY,ZERO,SIGN,PARITY,HALFCARRY
; Keep a left operand with metadata A while its right operand is computed
; (the reference's pushValue): a value in the registers is pushed, PUSH AF
; for a byte, PUSH HL for a word, counted as two bytes of temporaries,
; and PUSH DE, PUSH HL for a long, counted as four; a known value stays in
; the parser and costs nothing. BC is kept.

GX_PUSH:                       ; A is the left operand's metadata.
    BIT  7,A                       ; SY_KNOWN: a constant?
    RET  NZ                        ; It needs no code.
    AND  SY_TMASK                  ; Its type:
    CALL GX_SIZE                   ; its size.
    LD   A,$F5                     ; PUSH AF: a byte is in A.
    JR   C,GX_PUSHA                ; A byte it is.
    JR   Z,GX_PUSHW                ; PUSH HL for a word.
    CALL EM_OP                     ; A long: PUSH DE
    DB   $D5                       ; first, the high word,
    CALL GX_PUSHW                  ; then PUSH HL,
    LD   A,2                       ; and two more bytes
    JP   EM_PUSH                   ; counted; return.

;@ROUTINE CLOBBERS A,DE,HL,CARRY,ZERO,SIGN,PARITY,HALFCARRY
; Append PUSH HL and count its two bytes as temporaries (pushValue). BC
; is kept.

GX_PUSHW:                      ; A word in HL waits.
    LD   A,$E5                     ; PUSH HL.
GX_PUSHA:                      ; A is the push.
    CALL EM_BYTE                   ; Append it.
    LD   A,2                       ; Two bytes of temporaries.
    JP   EM_PUSH                   ; Count them and return.

;@ROUTINE IN A CLOBBERS A,DE,HL,CARRY,ZERO,SIGN,PARITY,HALFCARRY
; Pop a value of type A that GX_PUSH pushed (popValue): POP AF for a byte,
; POP HL for a word, POP HL and POP DE for a long, and count it popped.
; BC is kept.

GX_POPV:                       ; A is the value's type.
    CALL GX_SIZE                   ; Its size.
    LD   A,$F1                     ; POP AF for a byte.
    JR   C,.WORD                   ; A byte it is.
    LD   A,$E1                     ; POP HL for a word.
    JR   Z,.WORD                   ; A word it is.
    CALL EM_BYTE                   ; A long: POP HL,
    LD   A,$D1                     ; then POP DE,
    CALL EM_BYTE                   ; appended,
    LD   A,4                       ; and four bytes
    JP   EM_POP                    ; popped; return.
.WORD:                         ; A is the pop.
    CALL EM_BYTE                   ; Append it.
    JP   EM_POP2                   ; Two bytes popped; return.

;@ROUTINE IN D,E CLOBBERS A,BC,DE,HL,CARRY,ZERO,SIGN,PARITY,HALFCARRY
; Convert the registers from integer type D to integer type E, which D
; does not widen to, with the checks of a narrowing (checkedNarrow,
; checkedNarrow32): a call to TRAP_NAR unless the value fits E, then the
; value at E's size. The reference's i8 to u16, which it left unchecked
; and unwidened, is checked and zero-extended (a fault fixed there too).

GX_TRIM:                       ; D is the source's type, E the target's.
    LD   (GX_TYPES),DE             ; Keep the types.
    LD   A,D                       ; The source's
    CALL GX_PROP                   ; properties
    LD   (GX_PFROM),A              ; are kept,
    LD   B,A                       ; and the
    LD   A,E                       ; target's
    CALL GX_PROP                   ; too.
    LD   (GX_PTO),A                ; Kept.
    OR   B                         ; Is either
    AND  4                         ; a long?
            JR   NZ,.WIDE          ; Then the 32-bit checks.
    LD   A,B                       ; Is the source
    AND  7                         ; a byte?
    DEC  A                         ; Then
            JR   Z,.BYTE           ; to a byte or a word.
    CALL .TOBYTE                   ; A word: to a word?
            JR   NZ,.WORDS         ; Then u16 to i16, or i16 to u16.
    LD   A,(GX_PFROM)              ; A word to a byte:
    AND  (HL)                      ; both signed? (HL is GX_PTO)
    RLA                            ; Then
            JR   C,.SIGNS          ; H must be L's sign.
    CALL .HZERO                    ; Otherwise H must be zero,
    LD   A,(GX_PTO)                ; and for
    RLA                            ; an i8
            JR   NC,.LOW           ; target
    CALL EM_SEQ                    ; L's top bit clear:
    DB   2,$7D,$07                 ; LD A,L, RLCA,
    CALL .IFC                      ; CALL C,TRAP_NAR.
            JR   .LOW              ; Then the low byte.
.SIGNS:                        ; i16 to i8.
    CALL EM_SEQ                    ; LD A,L, RLCA, SBC A,A, XOR H:
    DB   4,$7D,$07,$9F,$AC         ; zero when H is L's sign;
    CALL .IFNZ                     ; CALL NZ,TRAP_NAR.
.LOW:                          ; The value is a byte:
    LD   A,$7D                     ; LD A,L.
    JP   EM_BYTE                   ; Append it and return.
.BYTE:                         ; From a byte.
    CALL EM_OP                     ; OR A: its sign
    DB   $B7                       ; must be clear,
    LD   A,$FC                     ; CALL M,TRAP_NAR,
    CALL .TRAP                     ; for u8 to i8 and back;
    CALL .TOBYTE                   ; and for i8 to u16
    RET  Z                         ; it is
    JP   GX_ZEXT                   ; zero-extended.
.WORDS:                        ; u16 to i16 and back:
    CALL EM_SEQ                    ; H's sign must be clear,
    DB   2,$7C,$B7                 ; LD A,H, OR A,
    LD   A,$FC                     ; CALL M,TRAP_NAR.
    JP   .TRAP                     ; Append it and return.
.WIDE:                         ; A long is the source or the target.
    LD   A,(GX_PFROM)              ; Both
    AND  (HL)                      ; longs?
    AND  4                         ; (HL is GX_PTO)
            JR   Z,.ONE            ; No.
    CALL EM_SEQ                    ; u32 and i32: D's top bit clear:
    DB   2,$7A,$17                 ; LD A,D, RLA,
    JP   .IFC                      ; CALL C,TRAP_NAR; return.
.ONE:                          ; Just one is a long.
    LD   A,(GX_PFROM)              ; The source?
    AND  4                         ; Then
            JR   Z,.TOLONG         ; narrower to a long.
    LD   A,(GX_PFROM)              ; A long to narrower:
    AND  (HL)                      ; both signed?
    RLA                            ; Then DE must be
            JR   NC,.DEZERO        ; H's sign,
    CALL EM_SEQ                    ; LD A,H, RLA, SBC A,A, CP E,
    DB   4,$7C,$17,$9F,$BB         ; CALL NZ,TRAP_NAR,
    CALL .IFNZ                     ; then
    CALL EM_OP                     ; CP D,
    DB   $BA                       ; CALL NZ,TRAP_NAR;
    CALL .IFNZ                     ; and for a byte
    CALL .TOBYTE                   ; H must be L's sign:
            JR   NZ,.LOWEST        ; LD A,L, RLA,
    CALL EM_SEQ                    ; SBC A,A,
    DB   4,$7D,$17,$9F,$BC         ; CP H,
    CALL .IFNZ                     ; CALL NZ,TRAP_NAR.
            JR   .LOWEST           ; Then the low byte, if a byte.
.DEZERO:                       ; Otherwise DE must be zero:
    CALL EM_SEQ                    ; LD A,D, OR E,
    DB   2,$7A,$B3                 ; CALL NZ,TRAP_NAR;
    CALL .IFNZ                     ; for a byte,
    CALL .TOBYTE                   ; H too:
    CALL Z,.HZERO                  ; LD A,H, OR A, CALL NZ,TRAP_NAR.
    LD   A,(GX_PTO)                ; A signed target
    RLA                            ; needs its own top bit
            JR   NC,.LOWEST        ; clear:
    CALL .TOBYTE                   ; L's for a byte,
    LD   A,$7D                     ; LD A,L,
            JR   Z,.TOP            ; or
    LD   A,$7C                     ; LD A,H for a word,
.TOP:                          ; A is the load.
    CALL EM_BYTE                   ; Append it,
    CALL EM_OP                     ; then RLA,
    DB   $17                       ; and
    CALL .IFC                      ; CALL C,TRAP_NAR.
.LOWEST:                       ; A byte target is in L:
    CALL .TOBYTE                   ; LD A,L;
    RET  NZ                        ; a word is in HL.
    JP   .LOW                      ; Append it and return.
.TOLONG:                       ; A byte or a word to a long:
    LD   A,(GX_PFROM)              ; signed to unsigned
    RLA                            ; needs the sign clear;
            JR   C,.CLEAR          ; anything else widens.
    LD   DE,(GX_TYPES)             ; The types again:
    JP   GX_WIDEN                  ; widened; return.
.CLEAR:                        ; i8 or i16 to u32.
    LD   A,(GX_PFROM)              ; A byte's top bit is A's,
    AND  7                         ; a word's H's:
    DEC  A                         ; LD A,A
    LD   A,$7F                     ; for a byte,
            JR   Z,.SIGN           ; or
    LD   A,$7C                     ; LD A,H.
.SIGN:                         ; A is the load.
    CALL EM_BYTE                   ; Append it,
    CALL EM_OP                     ; then RLA,
    DB   $17                       ; and
    CALL .IFC                      ; CALL C,TRAP_NAR.
    LD   A,(GX_PFROM)              ; A byte
    AND  7                         ; is
    DEC  A                         ; zero-extended
    CALL Z,GX_ZEXT                 ; to a word,
    CALL EM_SEQ                    ; and the high word
    DB   3,$11,0,0                 ; is LD DE,0.
    RET                            ; DEHL is the value.

;@ROUTINE OUT HL,ZERO CLOBBERS A,CARRY,SIGN,PARITY,HALFCARRY
; Z when the narrowing's target is a byte; HL addresses GX_PTO.

.TOBYTE:                       ; Is the target a byte?
    LD   HL,GX_PTO                 ; Its properties:
    LD   A,(HL)                    ; its size
    AND  7                         ; less
    DEC  A                         ; one.
    RET                            ; Z for a byte.

;@ROUTINE CLOBBERS A,BC,DE,HL,CARRY,ZERO,SIGN,PARITY,HALFCARRY
; Append LD A,H, OR A and CALL NZ,TRAP_NAR: H must be zero.

.HZERO:                        ; H must be zero.
    CALL EM_SEQ                    ; LD A,H, OR A,
    DB   2,$7C,$B7                 ; then CALL NZ.

;@ROUTINE CLOBBERS A,BC,DE,HL,CARRY,ZERO,SIGN,PARITY,HALFCARRY
; Append CALL NZ,TRAP_NAR (.IFNZ), CALL C,TRAP_NAR (.IFC), or the trap
; site whose CALL cc opcode is A (.TRAP).

.IFNZ:                         ; CALL NZ.
    LD   A,$C4                     ; Its opcode.
            JR   .TRAP             ; Append it.
.IFC:                          ; CALL C.
    LD   A,$DC                     ; Its opcode.
.TRAP:                         ; A is the opcode.
    LD   L,HP_TRUNC&$FF            ; The narrowing trap.
    JP   EM_TRAP                   ; Append the site and return.

;@ROUTINE IN A CLOBBERS A,BC,DE,HL,CARRY,ZERO,SIGN,PARITY,HALFCARRY
; Compare two Booleans for = or <>, relation A, not both known: the left
; known or pushed, the right in A or known (the reference's Boolean
; comparison). XOR leaves 1 when they differ; = then flips it.

GX_BOOL:                       ; A is EX_EQ or EX_NE.
    LD   C,A                       ; Keep the relation.
    LD   A,(EX_LMETA)              ; Is the left known?
    RLCA                           ; SY_KNOWN into carry.
    JR   NC,.PUSHED                ; No: it was pushed.
    CALL EM_OP                     ; XOR n with the left's value.
    DB   $EE                       ; Append it.
    LD   A,(EX_LVAL)               ; The left, 0 or 1,
    CALL EM_BYTE                   ; is n.
    JR   .EQUAL                    ; Then = flips it.
.PUSHED:                       ; The left is on the stack.
    LD   A,(EX_RMETA)              ; Is the right known?
    RLCA                           ; SY_KNOWN into carry.
    JR   NC,.HELD                  ; No: it is in A.
    CALL EM_OP                     ; LD A,n: load it.
    DB   $3E                       ; Append it.
    LD   A,(EX_RVAL)               ; The right, 0 or 1,
    CALL EM_BYTE                   ; is n.
.HELD:                         ; The right is in A.
    CALL EM_SEQ                    ; LD E,A, POP AF, XOR E:
    DB   3,$5F,$F1,$AB             ; 1 when they differ.
    CALL EM_POP2                   ; Two bytes are no longer pushed.
.EQUAL:                        ; A is 1 when they differ.
    DEC  C                         ; Was it <> (EX_NE, one)?
    RET  Z                         ; Then that is the answer.
    CALL EM_SEQ                    ; = flips it:
    DB   2,$EE,1                   ; XOR 1.
    RET                            ; The Boolean is in A.

;@ROUTINE IN D CLOBBERS A,BC,DE,HL,CARRY,ZERO,SIGN,PARITY,HALFCARRY
; Negate the computed value of type D in place (negate): NEG for a byte;
; for a word, EX DE,HL, LD HL,0, OR A, SBC HL,DE; for a long, NEG32.

GX_NEG:                        ; D is the type.
    LD   A,D                       ; Its size.
    CALL GX_SIZE                   ; A byte?
    JR   Z,.WORD                   ; A word.
    JR   NC,.LONG                  ; A long.
    CALL EM_SEQ                    ; NEG.
    DB   2,$ED,$44                 ; A is negated.
    RET                            ; Done.
.WORD:                         ; HL.
    CALL EM_SEQ                    ; EX DE,HL, LD HL,0, OR A, SBC HL,DE.
    DB   7,$EB,$21,0,0,$B7,$ED,$52 ; HL is zero less the value.
    RET                            ; Done.
.LONG:                         ; DEHL, through the runtime:
    CALL EM_HELP                   ; CALL NEG32,
    DW   HP_LNEG                   ; its ordinal and stack figure.
    RET                            ; Done.

;@ROUTINE IN C CLOBBERS A,B,CARRY,ZERO,SIGN,PARITY,HALFCARRY
; Complement the computed value of type C in place (unaryNot): XOR 1 for
; a Boolean, CPL for a byte, and each byte of HL, then of DE, for a word
; or a long.

GX_NOT:                        ; C is the type.
    LD   A,C                       ; A Boolean?
    CP   SY_BOOL                   ; It flips.
    JR   Z,.FLIP                   ; XOR 1.
    CALL GX_SIZE                   ; A byte?
    LD   A,$2F                     ; CPL.
    JP   C,EM_BYTE                 ; Append it and return.
    PUSH AF                        ; Keep the size's flags.
    CALL EM_SEQ                    ; A word: LD A,H, CPL, LD H,A,
    DB   6,$7C,$2F,$67,$7D,$2F,$6F ; LD A,L, CPL, LD L,A.
    POP  AF                        ; A long
    RET  Z                         ; has DE too:
    CALL EM_SEQ                    ; LD A,D, CPL, LD D,A,
    DB   6,$7A,$2F,$57,$7B,$2F,$5F ; LD A,E, CPL, LD E,A.
    RET                            ; Done.
.FLIP:                         ; A Boolean.
    CALL EM_SEQ                    ; XOR 1.
    DB   2,$EE,1                   ; It flips.
    RET                            ; Done.

;@ROUTINE IN A OUT A CLOBBERS BC,DE,HL,CARRY,ZERO,SIGN,PARITY,HALFCARRY
; Open the short circuit of `and` (A is TK_AND) or `or` after a computed
; Boolean left operand: OR A, then JP Z (and) or JP NZ (or) to a new label,
; whose number is returned in A. The right operand follows.

GX_SKIP:                       ; A is the operator.
    CP   TK_AND                    ; `and` skips when false.
    LD   A,$CA                     ; JP Z.
    JR   Z,.CHOSEN                 ; It is `and`.
    LD   A,$C2                     ; JP NZ for `or`.
.CHOSEN:                       ; A is the jump.
    PUSH AF                        ; Keep it.
    CALL EM_OP                     ; OR A sets Z from the left.
    DB   $B7                       ; Append it.
    POP  AF                        ; The jump.
    CALL EM_BYTE                   ; Append it.
    CALL EM_LNEW                   ; A is the label it skips to.
    PUSH AF                        ; Keep it.
    CALL EM_LREF                   ; Its operand.
    POP  AF                        ; A is the label.
    RET                            ; The right operand follows.
