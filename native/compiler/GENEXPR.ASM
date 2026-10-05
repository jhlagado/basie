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
;  Principal entries:
;    GX_LOAD   load a program variable of type A from blob BC
;    GX_STORE  store the registers into a program variable of type A
;    GX_TOREG  bring a result into the registers at a destination's type
;    GX_WIDEN  widen a u8 in A to a u16 in HL

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
    CALL EM_BYTE                   ; The opcode.
    LD   H,B                       ; HL is the target,
    LD   L,C                       ; the variable's blob.
    LD   DE,0                      ; With no addend:
    JP   EM_REF                    ; its address, and return.

;@ROUTINE IN A,BC CLOBBERS A,BC,DE,HL,CARRY,ZERO,SIGN,PARITY,HALFCARRY
; Store the registers into the program variable at blob BC, of scalar type
; A: LD (nn),A for a u8 or Boolean, LD (nn),HL for a u16.

GX_STORE:                      ; A is the type, BC the variable's ordinal.
    CP   SY_U16                    ; A word?
    LD   A,$32                     ; LD (nn),A for a byte.
    JR   NZ,GX_ABS                 ; A byte it is.
    LD   A,$22                     ; LD (nn),HL for a word.
    JR   GX_ABS                    ; Append it and return.

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
    LD   A,$3E                     ; LD A,n.
    CALL EM_BYTE                   ; The opcode.
    LD   A,L                       ; The value's low byte
    JP   EM_BYTE                   ; is its operand.
.WORD:                         ; A u16 destination.
    LD   A,$21                     ; LD HL,nn.
    CALL EM_BYTE                   ; The opcode.
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
