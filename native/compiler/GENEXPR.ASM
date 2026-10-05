;==========================================================================
;  Expression code generation
;==========================================================================
;
;  The reference compiler's templates for scalar values (ref/compile/
;  compiler.ts: loadRegisters, storeRegisters, toRegisters), written as the
;  expression parser (EXPR, EXTERM, EXOPER) and the statement actions reach
;  each step. A value is in A when it is a u8 or a Boolean and in HL when
;  it is a u16; a constant is not loaded until something needs it in the
;  registers, and then at the type that needs it.
;
;  Frames. A local or parameter is addressed from IX, the frame pointer: a
;  local at a negative offset, a parameter at a positive one (design
;  decision D41). The reference's ixByte, ixWord, ixStoreA, ixStoreHL and
;  ixStoreImm reach a slot within IX-128..IX+127 as (IX+d); a slot beyond
;  that, in a frame larger than 128 bytes, through its computed address,
;  with the registers the access must keep pushed around it and counted
;  into the frame (GX_FACC). Each access is described by a table entry:
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
;    GX_LOAD   load a program variable of type A from blob BC
;    GX_STORE  store the registers into a program variable of type A
;    GX_FLOAD  load the local or parameter of type A at IX+HL
;    GX_FPUT   store the registers into the one of type A at IX+HL
;    GX_FZERO  zero B bytes of the frame from IX+HL
;    GX_TOREG  bring a result into the registers at a destination's type
;    GX_WIDEN  widen a u8 in A to a u16 in HL
;    GX_PUSH   push a left operand while the right is computed
;    GX_PUSHW  PUSH HL, counted

;@ROUTINE IN A,BC CLOBBERS A,BC,DE,HL,CARRY,ZERO,SIGN,PARITY,HALFCARRY
; Load the program variable at blob BC, of scalar type A: LD A,(nn) for a
; u8 or Boolean, LD HL,(nn) for a u16.

GX_LOAD:                       ; A is the type, BC the variable's ordinal.
    CP   SY_U16                    ; A word?
    LD   A,$3A                     ; LD A,(nn) for a byte.
    JR   NZ,GX_ABS                 ; A byte it is.
    LD   A,$2A                     ; LD HL,(nn) for a word.

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
; A: LD (nn),A for a u8 or Boolean, LD (nn),HL for a u16.

GX_STORE:                      ; A is the type, BC the variable's ordinal.
    CP   SY_U16                    ; A word?
    LD   A,$32                     ; LD (nn),A for a byte.
    JR   NZ,GX_ABS                 ; A byte it is.
    LD   A,$22                     ; LD (nn),HL for a word.
    JR   GX_ABS                    ; Append it and return.

;@ROUTINE IN A,HL CLOBBERS A,BC,DE,HL,CARRY,ZERO,SIGN,PARITY,HALFCARRY
; Load the local or parameter of scalar type A at IX+HL: A for a u8 or
; Boolean (ixByte), HL for a u16 (ixWord).

GX_FLOAD:                      ; A is the type, HL the offset.
    LD   DE,GX_DLDA                ; A byte into A.
    CP   SY_U16                    ; A word?
    JR   NZ,GX_FACC                ; No: load the byte.
    LD   DE,GX_DLDHL               ; A word into HL.
    JR   GX_FACC                   ; Load it and return.

;@ROUTINE IN A,HL CLOBBERS A,BC,DE,HL,CARRY,ZERO,SIGN,PARITY,HALFCARRY
; Store the registers into the local or parameter of scalar type A at
; IX+HL: A for a u8 or Boolean (ixStoreA), HL for a u16 (ixStoreHL).

GX_FPUT:                       ; A is the type, HL the offset.
    LD   DE,GX_DSTA                ; A byte from A.
    CP   SY_U16                    ; A word?
    JR   NZ,GX_FACC                ; No: store the byte.
    LD   DE,GX_DSTHL               ; A word from HL.
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

;@ROUTINE IN D,E,HL CLOBBERS A,CARRY,ZERO,SIGN,PARITY,HALFCARRY
; Bring the result with metadata D and value HL into the registers as type
; E, which EX_FITS has accepted for it (toRegisters): a known value is
; loaded at type E, LD A,n or LD HL,nn; a u8 in A becomes a u16 in HL
; when E is u16; anything else is already in place.

GX_TOREG:                      ; D is the metadata, E the type, HL a known value.
    BIT  7,D                       ; SY_KNOWN: is the value known?
    JR   Z,.HELD                   ; No: it is in the registers.
    LD   A,E                       ; Load it at the destination's type.
    CP   SY_U16                    ; A word?
    JR   Z,.WORD                   ; LD HL,nn.
    CALL EM_OP                     ; LD A,n.
    DB   $3E                       ; The opcode.
    LD   A,L                       ; The value's low byte
    JP   EM_BYTE                   ; is its operand.
.WORD:                         ; A u16 destination.
    CALL EM_OP                     ; LD HL,nn.
    DB   $21                       ; The opcode.
    JP   EM_WORD                   ; The value, and return.
.HELD:                         ; The value is in A or HL.
    LD   A,D                       ; Its type
    AND  SY_TMASK                  ; alone.
    CP   E                         ; The destination's?
    RET  Z                         ; Nothing to do.

;@ROUTINE CLOBBERS A,B,CARRY,ZERO,SIGN,PARITY,HALFCARRY
; Widen the u8 in A to a u16 in HL: LD L,A / LD H,0.

GX_WIDEN:                      ; A u8 must become a u16.
    CALL EM_SEQ                    ; The zero extension:
    DB   3,$6F,$26,0               ; LD L,A, LD H,0.
    RET                            ; The value is in HL.

;@ROUTINE IN A CLOBBERS A,DE,HL,CARRY,ZERO,SIGN,PARITY,HALFCARRY
; Keep a left operand with metadata A while its right operand is computed
; (the reference's pushValue): a value in the registers is pushed, PUSH HL
; for a u16 and PUSH AF for a u8 or Boolean, and counted as two bytes of
; temporaries; a known value stays in the parser and costs nothing.

GX_PUSH:                       ; A is the left operand's metadata.
    BIT  7,A                       ; SY_KNOWN: a constant?
    RET  NZ                        ; It needs no code.
    AND  SY_TMASK                  ; Its type.
    CP   SY_U16                    ; A word?
    LD   A,$F5                     ; PUSH AF: a byte is in A.
    JR   NZ,GX_PUSHA               ; A byte it is.

;@ROUTINE CLOBBERS A,DE,HL,CARRY,ZERO,SIGN,PARITY,HALFCARRY
; Append PUSH HL and count its two bytes as temporaries (pushValue). BC
; is kept.

GX_PUSHW:                      ; A word in HL waits.
    LD   A,$E5                     ; PUSH HL.
GX_PUSHA:                      ; A is the push.
    CALL EM_BYTE                   ; Append it.
    LD   A,2                       ; Two bytes of temporaries.
    JP   EM_PUSH                   ; Count them and return.

;@ROUTINE IN C CLOBBERS A,BC,DE,HL,CARRY,ZERO,SIGN,PARITY,HALFCARRY
; Generate the binary operator EX_OPER (a token, or a relation code below
; 6) of width C on the operands EX_LMETA/EX_LVAL and EX_RMETA/EX_RVAL, not
; both known, as the reference's binary does. A known left operand is used
; as an immediate after the right is computed (emitBinaryConstLeft); a left
; operand in the registers was pushed (GX_PUSH) and is popped beneath a
; known right (emitBinaryImmediate) or a computed one (the register form).
; The result is in A or HL.

GX_BINOP:                      ; C is the width, u8 or u16.
    LD   A,(EX_LMETA)              ; Is the left operand known?
    RLCA                           ; SY_KNOWN into carry.
    JR   C,.LEFT                   ; Yes: it becomes an immediate.
    LD   A,(EX_RMETA)              ; The left was pushed. The right?
    RLCA                           ; SY_KNOWN into carry.
    JR   C,.RIGHT                  ; Known: pop the left beneath it.
    CALL .RWIDEN                   ; Both computed: the right at the width,
    LD   A,C                       ; then the left back.
    CP   SY_U16                    ; Words?
    JR   Z,.WORDS                  ; Then the right goes to DE.
    CALL EM_SEQ                    ; Bytes: the right to E,
    DB   2,$5F,$F1                 ; LD E,A, then the left: POP AF.
    JR   .POPPED                   ; Operate.
.WORDS:                        ; The right is in HL.
    CALL EM_OP                     ; EX DE,HL: the right to DE.
    DB   $EB                       ; Append it.
    CALL .POPL                     ; The left back into HL.
.POPPED:                       ; The left is back.
    CALL EM_POP2                   ; Two bytes fewer pushed.
    JP   GX_REGS                   ; Operate on the registers and return.
.RIGHT:                        ; A known right beneath a pushed left.
    CALL .POPL                     ; The left back, at the width.
    CALL EM_POP2                   ; Two bytes fewer pushed.
    LD   HL,(EX_RVAL)              ; The right's value
    JP   GX_IMM                    ; is the immediate.
.LEFT:                         ; A known left; the right is computed.
    CALL .RWIDEN                   ; The right at the width.
    LD   HL,(EX_LVAL)              ; The left's value.
    LD   A,(EX_OPER)               ; Does the operator commute?
    CP   EX_NE+1                   ; = and <> do,
    JP   C,GX_IMM                  ; so the left is the immediate.
    CP   TK_STAR                   ; So do *,
    JP   Z,GX_IMM                  ; and
    CP   TK_PLUS                   ; +,
    JP   Z,GX_IMM                  ; and the
    CP   TK_MINUS                  ; bitwise operators, but not -:
    JR   Z,.SWAP                   ; it moves the right aside.
    CALL GX_ALU                    ; The bitwise ones
    JP   NC,GX_IMM                 ; take the left as the immediate.
.SWAP:                         ; The right moves aside.
    LD   A,C                       ; Words?
    CP   SY_U16                    ; EX DE,HL then LD HL,nn.
    JR   Z,.SWAPW                  ; Words.
    CALL EM_SEQ                    ; Bytes: LD E,A,
    DB   2,$5F,$3E                 ; then LD A,n.
    LD   A,L                       ; The left
    CALL EM_BYTE                   ; is n.
    JP   GX_REGS                   ; Operate on the registers and return.
.SWAPW:                        ; Words.
    CALL EM_SEQ                    ; EX DE,HL,
    DB   2,$EB,$21                 ; then LD HL,nn.
    CALL EM_WORD                   ; The left is nn.
    JP   GX_REGS                   ; Operate on the registers and return.

;@ROUTINE IN C CLOBBERS A,B,CARRY,ZERO,SIGN,PARITY,HALFCARRY
; Widen the computed right operand, a u8 in A, when the width C is u16.

.RWIDEN:                       ; C is the width.
    LD   A,(EX_RMETA)              ; The right's type.
    JR   .WIDEN                    ; Widen it if the width needs it.

;@ROUTINE IN C CLOBBERS A,B,CARRY,ZERO,SIGN,PARITY,HALFCARRY
; Pop the left operand, POP HL for a u16 and POP AF otherwise, and widen
; it when it is a u8 and the width C is u16.

.POPL:                         ; C is the width.
    LD   A,(EX_LMETA)              ; The left's type.
    AND  SY_TMASK                  ; Alone.
    CP   SY_U16                    ; A word?
    LD   A,$E1                     ; POP HL.
    JR   Z,.POP                    ; It is in HL.
    LD   A,$F1                     ; POP AF.
.POP:                          ; A is the pop.
    CALL EM_BYTE                   ; Append it.
    LD   A,(EX_LMETA)              ; The left's type.
.WIDEN:                        ; A is an operand's metadata.
    AND  SY_TMASK                  ; Its type.
    CP   C                         ; The width's?
    RET  Z                         ; Then it is in place.
    LD   A,C                       ; Only a u16 width
    CP   SY_U16                    ; widens it.
    RET  NZ                        ; A u8 width never does.
    JP   GX_WIDEN                  ; LD L,A, LD H,0, and return.

;@ROUTINE IN C,HL CLOBBERS A,BC,DE,HL,CARRY,ZERO,SIGN,PARITY,HALFCARRY
; The operator EX_OPER of width C with the immediate HL as its right
; operand and the other in A or HL (emitBinaryImmediate): ADD, SUB, AND, OR
; and XOR take a byte immediate; anything else loads it into E or DE and
; operates on the registers.

GX_IMM:                        ; C is the width, HL the immediate.
    LD   A,C                       ; Words?
    CP   SY_U16                    ; Then LD DE,nn.
    JR   Z,.WORD                   ; Load it.
    LD   A,(EX_OPER)               ; A byte: is it an ALU operator?
    CALL GX_ALU                    ; A is its register form.
    JR   C,.LOADE                  ; No: LD E,n.
    AND  $38                       ; The operation's bits,
    OR   $C6                       ; as an immediate: ADD A,n and so on.
    CALL EM_BYTE                   ; Append it.
    LD   A,L                       ; Its operand
    JP   EM_BYTE                   ; is the immediate, and return.
.LOADE:                        ; Through E.
    CALL EM_OP                     ; LD E,n.
    DB   $1E                       ; Append it.
    LD   A,L                       ; Its operand
    CALL EM_BYTE                   ; is the immediate.
    JP   GX_REGS                   ; Operate on the registers and return.
.WORD:                         ; Through DE.
    CALL EM_OP                     ; LD DE,nn.
    DB   $11                       ; Append it.
    CALL EM_WORD                   ; Its operand is the immediate.

;@ROUTINE IN C CLOBBERS A,BC,DE,HL,CARRY,ZERO,SIGN,PARITY,HALFCARRY
; The operator EX_OPER of width C on the registers (emitBinaryRegisters):
; the left in A or HL, the right in E or DE. Arithmetic leaves its result
; there; a relation leaves a Boolean in A.

GX_REGS:                       ; C is the width.
    LD   A,(EX_OPER)               ; The operator.
    CP   EX_GE+1                   ; A relation code?
    JR   C,GX_REL                  ; Compare.
    CALL GX_ALU                    ; An ALU operator?
    JR   C,.MULDIV                 ; No: *, / or mod.
    LD   B,A                       ; B is its register form, on E.
    LD   A,C                       ; Words?
    CP   SY_U16                    ; Then a word sequence.
    LD   A,B                       ; A byte: the one instruction,
    JP   NZ,EM_BYTE                ; ADD A,E and so on; return.
    LD   C,B                       ; C is the operation from here.
    CP   $83                       ; Word addition?
    LD   A,$19                     ; ADD HL,DE.
    JP   Z,EM_BYTE                 ; Append it and return.
    LD   A,C                       ; Word subtraction?
    CP   $93                       ; SUB E is its byte form.
    JR   Z,.SUBW                   ; OR A then SBC HL,DE.
    CALL EM_OP                     ; Bitwise: LD A,H,
    DB   $7C                       ; then
    LD   A,C                       ; the operation
    DEC  A                         ; on D,
    CALL EM_BYTE                   ; then
    CALL EM_SEQ                    ; LD H,A
    DB   2,$67,$7D                 ; and LD A,L,
    LD   A,C                       ; the operation
    CALL EM_BYTE                   ; on E,
    LD   A,$6F                     ; then LD L,A.
    JP   EM_BYTE                   ; Append it and return.
.SUBW:                         ; Word subtraction.
    CALL EM_SEQ                    ; OR A, SBC HL,DE.
    DB   3,$B7,$ED,$52             ; Carry clear, then subtract.
    RET                            ; The difference is in HL.
.MULDIV:                       ; A is *, / or mod.
    LD   B,A                       ; B is the operator, C the width;
    PUSH BC                        ; keep both across the code.
    LD   A,C                       ; Bytes?
    CP   SY_U16                    ; Words go straight to the helper.
    JR   Z,.HELPER                 ; Call it.
    CALL EM_SEQ                    ; Bytes widen to words first:
    DB   5,$6F,$26,0,$16,0         ; LD L,A, LD H,0, LD D,0.
.HELPER:                       ; The operator and width are pushed.
    POP  BC                        ; B is the operator.
    PUSH BC                        ; Keep it for the result.
    LD   A,B                       ; Multiplication?
    CP   TK_STAR                   ; It has its own helper.
    JR   NZ,.DIVIDE                ; Division and remainder share one.
    CALL EM_HELP                   ; CALL MUL16,
    DW   HP_MUL16                  ; its ordinal and stack figure.
    JR   .CALLED                   ; Then the result.
.DIVIDE:                       ; / or mod.
    CALL EM_HELP                   ; CALL DIV16,
    DW   HP_DIV16                  ; its ordinal and stack figure.
.CALLED:                       ; HL is the quotient, DE the remainder.
    POP  BC                        ; B is the operator, C the width.
    LD   A,C                       ; Bytes?
    CP   SY_U16                    ; Words want only the remainder moved.
    JR   Z,.WORDS                  ; Words.
    LD   A,B                       ; A byte result:
    CP   TK_MOD                    ; the remainder
    LD   A,$7B                     ; is LD A,E,
    JP   Z,EM_BYTE                 ; and return;
    LD   A,$7D                     ; the quotient LD A,L.
    JP   EM_BYTE                   ; Append it and return.
.WORDS:                        ; A word result.
    LD   A,B                       ; The remainder?
    CP   TK_MOD                    ; Then EX DE,HL brings it to HL.
    RET  NZ                        ; The quotient is already there.
    LD   A,$EB                     ; EX DE,HL.
    JP   EM_BYTE                   ; Append it and return.

;@ROUTINE IN A,C CLOBBERS A,BC,CARRY,ZERO,SIGN,PARITY,HALFCARRY
; The relation A (EX_EQ..EX_GE) of width C, the left in A or HL and the
; right in E or DE, as a Boolean in A: a comparison that leaves carry when
; the left is less, or when they are equal, then SBC A,A and AND 1 for =,
; < and > or INC A for <>, >= and <=.

GX_REL:                        ; A is the relation, C the width.
    LD   B,A                       ; Keep it.
    LD   A,C                       ; Words?
    CP   SY_U16                    ; They compare in HL.
    LD   C,B                       ; C is the relation from here.
    JR   Z,.WORDS                  ; Compare words.
    LD   A,C                       ; Bytes: an equality?
    CP   EX_LT                     ; = and <> are below <.
    JR   NC,.ORDER                 ; No: an order.
    CALL EM_SEQ                    ; SUB E, then SUB 1 sets carry
    DB   3,$93,$D6,1               ; only when they were equal.
    JR   .TAIL                     ; Make the Boolean.
.ORDER:                        ; < <= > >= on bytes.
    CALL .SWAP                     ; Z if the operands swap (<= and >).
    JR   NZ,.CPE                   ; < and >= compare as they are.
    CALL EM_SEQ                    ; LD D,A, LD A,E, LD E,D:
    DB   3,$57,$7B,$5A             ; the right is now the left.
.CPE:                          ; Compare A with E.
    CALL EM_OP                     ; CP E: carry if A is less.
    DB   $BB                       ; Append it.
    JR   .TAIL                     ; Make the Boolean.
.WORDS:                        ; Words in HL and DE.
    CALL .SWAP                     ; <= and > swap them.
    LD   A,$EB                     ; EX DE,HL.
    CALL Z,EM_BYTE                 ; Swap them.
    CALL EM_SEQ                    ; OR A, SBC HL,DE:
    DB   3,$B7,$ED,$52             ; carry if HL is less.
    LD   A,C                       ; An equality?
    CP   EX_LT                     ; = and <> are below <.
    JR   NC,.TAIL                  ; No: carry decides.
    CALL EM_SEQ                    ; LD A,H, OR L, SUB 1: carry
    DB   4,$7C,$B5,$D6,1           ; only when they were equal.
.TAIL:                         ; Carry holds the answer, or its inverse.
    CALL EM_OP                     ; SBC A,A: $FF when carry.
    DB   $9F                       ; Append it.
    BIT  0,C                       ; <>, <= and >= are odd.
    LD   A,$3C                     ; INC A: 0 when carry, 1 otherwise.
    JP   NZ,EM_BYTE                ; Append it and return.
    CALL EM_SEQ                    ; AND 1: 1 when carry.
    DB   2,$E6,1                   ; The Boolean.
    RET                            ; It is in A.

;@ROUTINE IN C OUT ZERO CLOBBERS A
; Z when relation C swaps its operands: <= and >, which compare the right
; with the left.

.SWAP:                         ; C is the relation.
    LD   A,C                       ; Is it
    CP   EX_LE                     ; <=,
    RET  Z                         ; which swaps,
    CP   EX_GT                     ; or >?
    RET                            ; Z if it swaps.

;@ROUTINE IN A OUT A,CARRY CLOBBERS ZERO,SIGN,PARITY,HALFCARRY
; Carry clear if token A is +, -, `and`, `or` or `xor`, with A its byte
; operation on E: ADD A,E, SUB E, AND E, OR E or XOR E. Carry otherwise.

GX_ALU:                        ; A is an operator token.
    PUSH HL                        ; Keep the caller's HL.
    PUSH BC                        ; And BC.
    LD   HL,.TABLE                 ; Token and operation pairs.
    LD   B,5                       ; Five of them.
.SCAN:                         ; HL is the next pair.
    CP   (HL)                      ; This token?
    INC  HL                        ; Its operation follows.
    JR   Z,.FOUND                  ; Found.
    INC  HL                        ; The next pair.
    DJNZ .SCAN                     ; Until the table ends.
    SCF                            ; Not an ALU operator.
    JR   .DONE                     ; Return carry.
.FOUND:                        ; HL is the operation.
    LD   A,(HL)                    ; A is it; carry is clear.
.DONE:                         ; Restore the caller's registers.
    POP  BC                        ; BC
    POP  HL                        ; and HL.
    RET                            ; Carry says which.
.TABLE:                        ; The ALU operators on E.
    DB   TK_PLUS,$83               ; + is ADD A,E.
    DB   TK_MINUS,$93              ; - is SUB E.
    DB   TK_AND,$A3                ; `and` is AND E.
    DB   TK_OR,$B3                 ; `or` is OR E.
    DB   TK_XOR,$AB                ; `xor` is XOR E.

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

;@ROUTINE IN D CLOBBERS A,B,CARRY,ZERO,SIGN,PARITY,HALFCARRY
; Negate the computed value of type D in place: NEG for a u8; for a u16,
; EX DE,HL, LD HL,0, OR A, SBC HL,DE.

GX_NEG:                        ; D is the type, u8 or u16.
    LD   A,D                       ; Words?
    CP   SY_U16                    ; Then subtract from zero.
    JR   Z,.WORD                   ; Negate HL.
    CALL EM_SEQ                    ; NEG.
    DB   2,$ED,$44                 ; A is negated.
    RET                            ; Done.
.WORD:                         ; HL.
    CALL EM_SEQ                    ; EX DE,HL, LD HL,0, OR A, SBC HL,DE.
    DB   7,$EB,$21,0,0,$B7,$ED,$52 ; HL is zero less the value.
    RET                            ; Done.

;@ROUTINE IN C CLOBBERS A,B,CARRY,ZERO,SIGN,PARITY,HALFCARRY
; Complement the computed value of type C in place: XOR 1 for a Boolean,
; CPL for a u8, and each byte of HL for a u16.

GX_NOT:                        ; C is the type.
    LD   A,C                       ; A Boolean?
    CP   SY_BOOL                   ; It flips.
    JR   Z,.FLIP                   ; XOR 1.
    CP   SY_U8                     ; A byte?
    LD   A,$2F                     ; CPL.
    JP   Z,EM_BYTE                 ; Append it and return.
    CALL EM_SEQ                    ; A word: LD A,H, CPL, LD H,A,
    DB   6,$7C,$2F,$67,$7D,$2F,$6F ; LD A,L, CPL, LD L,A.
    RET                            ; Done.
.FLIP:                         ; A Boolean.
    CALL EM_SEQ                    ; XOR 1.
    DB   2,$EE,1                   ; It flips.
    RET                            ; Done.

;@ROUTINE CLOBBERS A,BC,DE,HL,CARRY,ZERO,SIGN,PARITY,HALFCARRY
; u8(...) of a computed u16 (checkedNarrow): trap unless the high byte is
; zero, then take the low byte: LD A,H, OR A, CALL NZ,TRAP_NAR, LD A,L.

GX_BYTE:                       ; The value is in HL.
    CALL EM_SEQ                    ; LD A,H, OR A,
    DB   2,$7C,$B7                 ; then
    LD   A,$C4                     ; CALL NZ
    LD   L,HP_TRUNC&$FF            ; to the narrowing trap.
    CALL EM_TRAP                   ; Append it.
    LD   A,$7D                     ; LD A,L.
    JP   EM_BYTE                   ; Append it and return.

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
