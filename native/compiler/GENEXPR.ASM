;==========================================================================
;  Expression code generation and the replay loop
;==========================================================================
;
;  The third phase of a compilation. Once the parser has closed the
;  semantic transcript, GX_WALK replays it from TR_BODY one operation at a
;  time. Each operation code selects a handler through GX_OPTAB; the handler
;  reads the operation's fixed operands (EM_READB, EM_READW, EM_READA) and
;  emits placed Z80 code at EM_PTR. The same table dispatches the control
;  handlers (GC_, GENCTRL.ASM) and the routine, call and open-string
;  handlers (RG_ and OS_, GENCALL.ASM). When the last operation is placed,
;  GC_PATCH resolves the absolute label operands left in the fixup table.
;
;  The generated code is a stack machine. Every value is a canonical 16-bit
;  carrier on the Z80 stack, and a u8 or boolean carrier has H zero, while
;  declared storage keeps its width: one byte for u8 and boolean, two for
;  u16. A binary operator pops its right operand into DE and its left into
;  HL, computes into HL and pushes HL. The evaluation stack lies below the
;  IX frame and is empty at every statement boundary.
;
;  A frame is opened by GT_ENTER (EMIT.ASM): PUSH IX; LD IX,0; ADD IX,SP.
;  Each local is then reserved by DEC SP in declaration order. The local at
;  byte offset k keeps its low byte at IX-(k+1) and a u16's high byte one
;  below, at IX-(k+2); GX_LOCAL turns k into the first displacement.
;
;  A failed run-time check jumps to an inline trap body: LD HL,position;
;  LD A,trap; the root SP and IX restored (GX_RESET); the activation count
;  cleared; the trap record written and the program stopped (EM_TRAP). The
;  success path branches over the body. The traps raised here are 2 (value
;  too wide for u8), 3 (division by zero), 5 (no activation left) and 6
;  (unhandled error); GENCALL raises 1 (bounds) and GENCTRL 4 (loop step).
;
;  A fault in the compiler itself never returns: an operation the replay
;  cannot accept, a full branch stack or an output failure raises a
;  diagnostic (DG_RAISE), which unwinds to the stack saved at the compile
;  entry. The generators therefore return carry clear, and no caller tests
;  it. OP_LIT8, OP_TIMES and OP_PLUS are retired and rejected. No parser
;  path writes OP_DEF8, OP_MAIN, OP_WRVAL, OP_HALT, OP_DEF16, OP_FUNC,
;  OP_FCALL or OP_ENDFN any longer; their handlers remain from Nucleus.
;
;  Principal entries:
;    GX_WALK   replay the transcript into code, then resolve label fixups
;    GX_START  patch the startup's call of main and save the root SP and IX
;    GX_FETCH  emit opcode A with word HL, then PUSH HL
;    GX_POP    emit POP HL
;    GX_LDX16  emit the push of a u16 local or parameter
;    GX_ST8    emit the store of a popped u8 into a global
;    GX_STX8   emit the store of a popped u8 into a local
;    GX_TEST   emit a relational comparison through RT_CMP16
;    GX_TRY    emit a helper call and a JR NC over its failure path
;    GX_RAISE  emit a trap body for position HL and trap A
;    GX_ABORT  emit the root-frame restore and the trap record
;    GX_RESET  emit the restore of the root SP and IX
;    GX_RET    emit a value return
;    GX_BADOP  reject a transcript the replay cannot accept
;
;  Workspace: GX_BCNT and GX_BBASE (STATE.ASM) form the stack of open
;  short-circuit branches, one JR operand address per nesting level and at
;  most GX_BCAP. GX_POS and GX_WIDTH borrow emitter scratch words.

; The control generator uses the same two words (GC_COUNT, GC_STEP). Each
; value is live only inside the handler that writes it, and no handler calls
; a routine that writes the other's word, so they share without conflict.
GX_POS EQU  EM_HEAD            ; Source position of the pending trap (word).
GX_WIDTH EQU  EM_ORG           ; Handler mode or operand type (byte).

;@ROUTINE OUT CARRY CLOBBERS A,BC,DE,HL,IX,IY,SIGN,PARITY,HALFCARRY,ZERO
; Replay the closed transcript into Z80 code, then resolve every absolute
; label operand. An empty transcript emits nothing and patches nothing.

GX_WALK:                       ; Entry from GA_IMAGE once the data image is placed.
    LD   HL,TR_BODY                ; The first operation follows the count byte.
    LD   (EM_READP),HL             ; Handlers read their operands from this cursor.
    XOR  A                         ; Zero for the counters and the placed flags.
    LD   (GX_BCNT),A               ; No short-circuit branch is open.
    LD   (GC_FCNT),A               ; No absolute label operand is pending.
    LD   HL,GC_VALID               ; Clear the placed flag of every label ordinal.
    LD   B,GC_LCAP                 ; One flag byte per label.
.CLEAR:                        ; HL walks the flags; B counts those left.
    LD   (HL),A                    ; This label has not been placed.
    INC  HL                        ; Advance to the next ordinal's flag.
    DJNZ .CLEAR                    ; Repeat for all GC_LCAP labels.
    LD   A,(TR_BASE)               ; Operation count published by TR_CLOSE.
    OR   A                         ; Is the transcript empty?
    RET  Z                         ; Nothing to emit; carry is clear.
    LD   B,A                       ; B counts the operations still to replay.
.NEXT:                         ; The read cursor is at an operation code.
    PUSH BC                        ; Handlers clobber B; keep the count.
    CALL EM_READB                  ; A = operation code.
    SUB  OP_DEF8                   ; The table begins at the first generating code.
    CP   GX_OPCNT                  ; Codes below OP_DEF8 wrap high and fail too.
    JR   NC,.BAD                   ; Reject a code outside the table.
    ADD  A,A                       ; Two bytes per entry; 90*2 still fits in A.
    LD   E,A                       ; DE = byte offset of the entry.
    LD   D,0                       ; Complete the 16-bit offset.
    LD   HL,GX_OPTAB               ; Base of the handler table.
    ADD  HL,DE                     ; HL addresses this operation's entry.
    LD   E,(HL)                    ; Handler address, low byte.
    INC  HL                        ; Step to the high byte.
    LD   D,(HL)                    ; DE = handler.
    EX   DE,HL                     ; JP (HL) needs the handler in HL.
    LD   DE,.RETURN                ; The handler's RET must come back here.
    PUSH DE                        ; Push it, turning the jump into a call.
    JP   (HL)                      ; Run the handler for this operation.
.RETURN:                       ; The handler has emitted its code.
    POP  BC                        ; Recover the operation count.
    DJNZ .NEXT                     ; Replay the next operation.
    JP   GC_PATCH                  ; All labels placed: patch their operands.
.BAD:                          ; The operation code is outside the table.
    POP  BC                        ; Balance the count; the diagnostic unwinds anyway.

;@ROUTINE NORETURN
; Reject a transcript the replay cannot accept: an unknown or retired code,
; a label placed twice or never, or unbalanced short-circuit branches.

GX_BADOP:                      ; Reached by jump from every generator.
    JP   EX_EPOP                   ; Raise the internal-error diagnostic (DG_BUG).

;@ROUTINE NORETURN
; Reject a short-circuit expression nested more than GX_BCAP deep.

GX_FULL:                       ; Reached from GX_PUTJR when the stack is full.
    CALL DG_RAISE                  ; Raise the diagnostic in the next byte.
    DB   DG_ANDOR                  ; Too many nested AND and OR operators.

; Handler of each operation code from OP_DEF8 (20) to OP_VIEW (110).
GX_OPTAB:                      ; Indexed by (operation - OP_DEF8) * 2.
    DW   .DATA8                    ; 20 OP_DEF8: one initialised data byte.
    DW   .MAIN                     ; 21 OP_MAIN: main's entry and frame.
    DW   GX_VAR8                   ; 22 OP_LOC8: reserve a u8 local.
    DW   GX_BADOP                  ; 23 OP_LIT8: retired.
    DW   GX_LD8                    ; 24 OP_LDG8: push a u8 global.
    DW   GX_LDX8                   ; 25 OP_LDL8: push a u8 local.
    DW   GX_BADOP                  ; 26 OP_TIMES: retired.
    DW   GX_BADOP                  ; 27 OP_PLUS: retired.
    DW   GX_ST8                    ; 28 OP_STG8: pop into a u8 global.
    DW   GX_STX8                   ; 29 OP_STL8: pop into a u8 local.
    DW   GX_WRITE                  ; 30 OP_WRVAL: write a byte through vector 1.
    DW   GX_EXIT                   ; 31 OP_HALT: leave main with success.
    DW   .DATA16                   ; 32 OP_DEF16: one initialised data word.
    DW   GX_VAR16                  ; 33 OP_LOC16: reserve a u16 local.
    DW   GX_NUM16                  ; 34 OP_LIT16: push a constant.
    DW   GX_LD16                   ; 35 OP_LDG16: push a u16 global.
    DW   GX_LDX16                  ; 36 OP_LDL16: push a u16 local.
    DW   GX_ADD8                   ; 37 OP_ADD8: u8 addition.
    DW   GX_ADD16                  ; 38 OP_ADD16: u16 addition.
    DW   GX_SUB8                   ; 39 OP_SUB8: u8 subtraction.
    DW   GX_SUB16                  ; 40 OP_SUB16: u16 subtraction.
    DW   GX_MUL8                   ; 41 OP_MUL8: u8 multiplication.
    DW   GX_MUL16                  ; 42 OP_MUL16: u16 multiplication.
    DW   GX_DIV8                   ; 43 OP_DIV8: checked u8 division.
    DW   GX_DIV16                  ; 44 OP_DIV16: checked u16 division.
    DW   GX_NEG8                   ; 45 OP_NEG8: u8 negation.
    DW   GX_NEG16                  ; 46 OP_NEG16: u16 negation.
    DW   GX_NOT8                   ; 47 OP_NOT8: u8 complement.
    DW   GX_NOT16                  ; 48 OP_NOT16: u16 complement.
    DW   GX_FLIP                   ; 49 OP_LNOT: boolean NOT.
    DW   GX_AND8                   ; 50 OP_AND8: u8 bitwise AND.
    DW   GX_AND16                  ; 51 OP_AND16: u16 bitwise AND.
    DW   GX_OR8                    ; 52 OP_OR8: u8 bitwise OR.
    DW   GX_OR16                   ; 53 OP_OR16: u16 bitwise OR.
    DW   GX_XOR8                   ; 54 OP_XOR8: u8 exclusive OR.
    DW   GX_XOR16                  ; 55 OP_XOR16: u16 exclusive OR.
    DW   GX_MOD8                   ; 56 OP_MOD8: checked u8 remainder.
    DW   GX_MOD16                  ; 57 OP_MOD16: checked u16 remainder.
    DW   GX_RELOP                  ; 58 OP_CMP8: u8 comparison.
    DW   GX_RELOP                  ; 59 OP_CMP16: u16 comparison.
    DW   GX_RELOP                  ; 60 OP_LCMP: boolean comparison.
    DW   GX_FIT8                   ; 61 OP_TRUNC: narrow to u8 or trap.
    DW   GX_ST16                   ; 62 OP_STG16: pop into a u16 global.
    DW   GX_STX16                  ; 63 OP_STL16: pop into a u16 local.
    DW   GX_ANDIF                  ; 64 OP_CAND: open a short-circuit AND.
    DW   GX_ORIF                   ; 65 OP_COR: open a short-circuit OR.
    DW   GX_JOIN                   ; 66 OP_JOIN: close the innermost AND or OR.
    DW   GC_LABEL                  ; 67 OP_LABEL: place a control label.
    DW   GC_IFNOT                  ; 68 OP_IFNOT: jump to a label when false.
    DW   GC_JUMP                   ; 69 OP_JUMP: jump to a label.
    DW   GC_FOR                    ; 70 OP_FOR: set up a counted loop.
    DW   GC_TEST                   ; 71 OP_TEST: test the loop's entry bound.
    DW   GC_NEXT                   ; 72 OP_NEXT: step the counter and loop.
    DW   GC_DROP                   ; 73 OP_CLEAN: discard the retained bound.
    DW   GX_ENTER                  ; 74 OP_FUNC: open the value routine.
    DW   GX_LDX8                   ; 75 OP_LDP8: push a u8 parameter.
    DW   GX_LDX16                  ; 76 OP_LDP16: push a u16 parameter.
    DW   GX_CALL                   ; 77 OP_FCALL: call the value routine.
    DW   GX_RET                    ; 78 OP_RET: return a value.
    DW   GX_STX8                   ; 79 OP_STP8: pop into a u8 parameter.
    DW   GX_STX16                  ; 80 OP_STP16: pop into a u16 parameter.
    DW   GX_CLOSE                  ; 81 OP_ENDFN: close the value routine.
    DW   RG_ENTER                  ; 82 OP_PROC: open a routine's frame.
    DW   RG_BIND                   ; 83 OP_BIND: copy an argument into the frame.
    DW   RG_CALL                   ; 84 OP_CALL: call a routine or service.
    DW   RG_RET                    ; 85 OP_RETA: return a value.
    DW   RG_CLOSE                  ; 86 OP_ENDP: close a routine.
    DW   RG_GLOB                   ; 87 OP_REFG: push a global's address.
    DW   RG_PARAM                  ; 88 OP_REFP: push a reference parameter.
    DW   RG_FIELD                  ; 89 OP_FIELD: add a field offset.
    DW   RG_INDEX                  ; 90 OP_INDEX: checked element address.
    DW   RG_GET8                   ; 91 OP_LDX8: load a byte through an address.
    DW   RG_GET16                  ; 92 OP_LDX16: load a word through an address.
    DW   RG_PUT8                   ; 93 OP_STX8: store a byte through an address.
    DW   RG_PUT16                  ; 94 OP_STX16: store a word through an address.
    DW   RG_COPY                   ; 95 OP_COPY: checked aggregate copy.
    DW   RG_LEN                    ; 96 OP_LEN: checked string length.
    DW   RG_CHAR                   ; 97 OP_CHAR: checked string character.
    DW   RG_FAIL                   ; 98 OP_FAIL: fail with an error code.
    DW   RG_FATAL                  ; 99 OP_ABORT: stop with an unhandled error.
    DW   RG_RETOK                  ; 100 OP_RETF: succeed from a failable routine.
    DW   RG_RETOK                  ; 101 OP_RETAF: succeed with a value.
    DW   RG_ENDOK                  ; 102 OP_ENDF: close a failable routine.
    DW   RG_SKIP                   ; 103 OP_HSKIP: jump over a handler.
    DW   RG_CATCH                  ; 104 OP_HOPEN: enter a handler.
    DW   RG_JOIN                   ; 105 OP_HDONE: place the label after it.
    DW   RG_MAIN                   ; 106 OP_ENTRY: the root wrapper around main.
    DW   RG_CONST                  ; 107 OP_REFRO: push a constant's address.
    DW   OS_LEN                    ; 108 OP_VLEN: open-string length.
    DW   OS_CHAR                   ; 109 OP_VCHAR: open-string character.
    DW   OS_ARG                    ; 110 OP_VIEW: pass an open-string argument.
GX_OPCNT EQU  91               ; Entries in GX_OPTAB, codes 20 to 110.

;@ROUTINE OUT CARRY CLOBBERS A,B,HL,SIGN,PARITY,HALFCARRY,ZERO
; OP_DEF8: emit one initialised data byte. Data is emitted in offset order,
; so the byte-offset operand is read and dropped.

.DATA8:                        ; Operands: byte offset, value.
    CALL EM_READB                  ; Byte offset, implied by the emission order.
    CALL EM_READB                  ; The initial value.
    JP   EM_BYTE                   ; Place it as data.

;@ROUTINE OUT CARRY CLOBBERS A,B,HL,SIGN,PARITY,HALFCARRY,ZERO
; OP_DEF16: emit one initialised data word, low byte first.

.DATA16:                       ; Operands: byte offset, low, high.
    CALL EM_READB                  ; Byte offset, implied by the emission order.
    CALL EM_READB                  ; Low byte of the initial value.
    CALL EM_BYTE                   ; Place it first, as the Z80 reads words.
    CALL EM_READB                  ; High byte of the initial value.
    JP   EM_BYTE                   ; Place it after the low byte.

;@ROUTINE OUT CARRY CLOBBERS A,BC,DE,HL,SIGN,PARITY,HALFCARRY,ZERO
; OP_MAIN: begin main here and open its frame with PUSH IX; LD IX,0;
; ADD IX,SP.

.MAIN:                         ; No operands.
    CALL GX_START                  ; Point the startup here and save the root frame.
    LD   HL,GT_ENTER               ; Eight-byte frame prologue.
    JP   EM_EIGHT                  ; Open main's frame.

;@ROUTINE OUT CARRY CLOBBERS A,BC,DE,HL,SIGN,PARITY,HALFCARRY,ZERO
; Patch the startup's JP or CALL of main to the current address, then emit
; LD (RT_SP),SP; LD (RT_IX),IX so that every trap can restore this frame.

GX_START:                      ; Called by .MAIN and RG_MAIN.
    LD   DE,(EM_DFIX)              ; Operand of the startup's transfer to main.
    LD   HL,(EM_PTR)               ; Main begins at the next byte.
    CALL EM_FIXW                   ; Resolve the transfer to here.
    JP   GX_SAVE                   ; Record the root SP and IX.

;@ROUTINE OUT CARRY CLOBBERS A,B,HL,SIGN,PARITY,HALFCARRY,ZERO
; OP_LOC8: emit DEC SP to reserve a u8 local. Locals are reserved in
; declaration order, so the slot operand is already implied and is dropped.

GX_VAR8:                       ; Operand: the local's slot.
    CALL EM_READB                  ; The slot, implied by the order of DEC SPs.
    CALL EM_ENDOP                  ; Emit the next byte and return.
    DB   $3B                       ; DEC SP: one byte of frame for the local.

;@ROUTINE OUT CARRY CLOBBERS A,B,HL,SIGN,PARITY,HALFCARRY,ZERO
; OP_LOC16: emit DEC SP; DEC SP to reserve a u16 local.

GX_VAR16:                      ; Operand: the local's slot.
    CALL GX_VAR8                   ; Drop the slot and reserve the low byte.
    CALL EM_ENDOP                  ; Emit the next byte and return.
    DB   $3B                       ; DEC SP: the high byte's frame byte.

;@ROUTINE OUT CARRY CLOBBERS A,BC,HL,SIGN,PARITY,HALFCARRY,ZERO
; OP_LIT16: emit LD HL,nn; PUSH HL for a constant carrier.

GX_NUM16:                      ; Operands: the constant, low byte first.
    CALL EM_READB                  ; Low byte of the constant.
    LD   C,A                       ; Keep it while the high byte is read.
    CALL EM_READB                  ; High byte of the constant.
    LD   H,A                       ; HL = the constant.
    LD   L,C                       ; Complete it with the low byte.
    LD   A,$21                     ; LD HL,nn: load the constant.

;@ROUTINE IN A,HL OUT CARRY CLOBBERS A,BC,HL,SIGN,PARITY,HALFCARRY,ZERO
; Emit opcode A with word operand HL, then PUSH HL: a carrier made by one
; instruction, LD HL,nn or LD HL,(nn). RG_REF shares this tail.

GX_FETCH:                      ; A = opcode, HL = its operand.
    CALL EM_OPW                    ; Emit the instruction that sets HL.
    CALL EM_ENDOP                  ; Emit the next byte and return.
    DB   $E5                       ; PUSH HL: the new carrier.

;@ROUTINE OUT CARRY CLOBBERS A,BC,DE,HL,SIGN,PARITY,HALFCARRY,ZERO
; OP_LDG8: emit LD A,(nn); LD L,A; LD H,0; PUSH HL for a u8 global.

GX_LD8:                        ; Operand: the global's data or bss offset.
    CALL EM_READA                  ; HL = the global's absolute address.
    LD   A,$3A                     ; LD A,(nn): read the global's byte.
    CALL EM_OPW                    ; Emit the byte load.
    LD   HL,GT_ATOHL               ; LD L,A; LD H,0; PUSH HL.
    JP   EM_FOUR                   ; Widen the byte to a carrier and push it.

;@ROUTINE OUT CARRY CLOBBERS A,BC,DE,HL,SIGN,PARITY,HALFCARRY,ZERO
; OP_LDG16: emit LD HL,(nn); PUSH HL for a u16 global.

GX_LD16:                       ; Operand: the global's data or bss offset.
    CALL EM_READA                  ; HL = the global's absolute address.
    LD   A,$2A                     ; LD HL,(nn): read the global's word.
    JR   GX_FETCH                  ; Emit the load and push the carrier.

;@ROUTINE OUT A,C,CARRY CLOBBERS HL,SIGN,PARITY,HALFCARRY,ZERO
; Read a local's byte offset k and return in A and C the displacement of its
; low byte, -(k+1). Carry is clear.

GX_LOCAL:                      ; The read cursor is at the offset operand.
    CALL EM_READB                  ; A = k, the local's byte offset.
    CPL                            ; -k-1: the low byte lies at IX-(k+1).
    LD   C,A                       ; C keeps the displacement for GX_IXOP.
    OR   A                         ; Clear carry for the caller.
    RET                            ; A and C hold the displacement.

;@ROUTINE IN C,HL OUT CARRY CLOBBERS A,B,HL,SIGN,PARITY,HALFCARRY,ZERO
; Emit the IX-indexed instruction whose two opcode bytes are at HL, with
; displacement C. C is preserved for the next byte of a u16.

GX_IXOP:                       ; HL = prefix and opcode, C = displacement.
    LD   B,0                       ; Not needed: B is reloaded before it is read.
    PUSH BC                        ; Keep the displacement across the copy.
    LD   B,2                       ; Two bytes: $DD and the opcode.
    CALL EM_BYTES                  ; Emit the prefix and opcode.
    POP  BC                        ; Recover the displacement.
    LD   A,C                       ; It is the instruction's last byte.
    JP   EM_BYTE                   ; Emit the displacement.

;@ROUTINE OUT CARRY CLOBBERS A,B,HL,SIGN,PARITY,HALFCARRY,ZERO
; Emit POP HL, taking the top carrier into HL. C and DE are preserved.

GX_POP:                        ; Shared by the stores, traps and calls.
    CALL EM_ENDOP                  ; Emit the next byte and return.
    DB   $E1                       ; POP HL: the top carrier.

;@ROUTINE OUT C,CARRY CLOBBERS A,B,HL,SIGN,PARITY,HALFCARRY,ZERO
; Read a local's offset and emit LD L,(IX+d) for its low byte. C returns d
; so the caller can address the high byte at d-1.

GX_GETLO:                      ; The read cursor is at the offset operand.
    CALL GX_LOCAL                  ; C = displacement of the low byte.
    LD   HL,GT_LDLO                ; LD L,(IX+d)
    JR   GX_IXOP                   ; Emit it with displacement C.

;@ROUTINE OUT CARRY CLOBBERS A,BC,HL,SIGN,PARITY,HALFCARRY,ZERO
; OP_LDL8, OP_LDP8: emit LD L,(IX+d); LD H,0; PUSH HL for a u8 local.

GX_LDX8:                       ; Operand: the local's byte offset.
    CALL GX_GETLO                  ; Load the byte into L.
    LD   HL,GT_LTOHL               ; LD H,0; PUSH HL.
    JP   EM_THREE                  ; Make it a carrier and push it.

;@ROUTINE OUT CARRY CLOBBERS A,BC,HL,SIGN,PARITY,HALFCARRY,ZERO
; OP_LDL16, OP_LDP16: emit LD L,(IX+d); LD H,(IX+d-1); PUSH HL for a u16
; local. RG_PARAM uses it to push a reference parameter's address.

GX_LDX16:                      ; Operand: the local's byte offset.
    CALL GX_GETLO                  ; Load the low byte into L; C = its displacement.
    DEC  C                         ; The high byte is stored one byte lower.
    LD   HL,GT_LDHI                ; LD H,(IX+d)
    CALL GX_IXOP                   ; Load the high byte into H.
    CALL EM_ENDOP                  ; Emit the next byte and return.
    DB   $E5                       ; PUSH HL: the u16 carrier.

;@ROUTINE OUT CARRY CLOBBERS A,B,HL,SIGN,PARITY,HALFCARRY,ZERO
; Emit POP DE; POP HL: the right operand into DE, the left into HL.

GX_ARGS:                       ; Shared by every binary operator.
    LD   HL,GT_ARGS                ; POP DE; POP HL.
    JP   EM_PAIR                   ; Emit both pops.

;@ROUTINE OUT CARRY CLOBBERS A,B,HL,SIGN,PARITY,HALFCARRY,ZERO
; Emit PUSH HL, making the result in HL the top carrier.

GX_PUSH:                       ; The common tail of the operators.
    CALL EM_ENDOP                  ; Emit the next byte and return.
    DB   $E5                       ; PUSH HL: the result carrier.

;@ROUTINE IN B,HL OUT CARRY CLOBBERS A,B,HL,SIGN,PARITY,HALFCARRY,ZERO
; Emit POP DE; POP HL, the B-byte operator body at HL, then PUSH HL.

GX_BINOP:                      ; B = body length, HL = body.
    PUSH BC                        ; Keep the length across the pops.
    PUSH HL                        ; Keep the body address.
    CALL GX_ARGS                   ; Pop both operands.
    POP  HL                        ; Recover the body.
    POP  BC                        ; Recover its length.
    CALL EM_BYTES                  ; Emit the operator body.
    JR   GX_PUSH                   ; Push the result.

;@ROUTINE OUT CARRY CLOBBERS A,B,HL,SIGN,PARITY,HALFCARRY,ZERO
; OP_ADD8: emit POP DE; POP HL; LD A,L; ADD A,E; LD L,A; LD H,0; PUSH HL.
; The sum wraps modulo 256.

GX_ADD8:                       ; No operands.
    LD   HL,GT_ADD8                ; The u8 addition body.
    JR   GX_BIN8                   ; Wrap it in the pops and the push.

;@ROUTINE OUT CARRY CLOBBERS A,B,HL,SIGN,PARITY,HALFCARRY,ZERO
; OP_SUB8: emit POP DE; POP HL; LD A,L; SUB E; LD L,A; LD H,0; PUSH HL.

GX_SUB8:                       ; No operands.
    LD   HL,GT_SUB8                ; The u8 subtraction body.
    JR   GX_BIN8                   ; Wrap it in the pops and the push.

;@ROUTINE OUT CARRY CLOBBERS A,B,HL,SIGN,PARITY,HALFCARRY,ZERO
; OP_XOR8: emit POP DE; POP HL; LD A,L; XOR E; LD L,A; LD H,0; PUSH HL.

GX_XOR8:                       ; No operands.
    LD   HL,GT_XOR8                ; The u8 exclusive-OR body.
    JR   GX_BIN8                   ; Wrap it in the pops and the push.

;@ROUTINE OUT CARRY CLOBBERS A,B,HL,SIGN,PARITY,HALFCARRY,ZERO
; OP_AND8: emit POP DE; POP HL; LD A,L; AND E; LD L,A; LD H,0; PUSH HL.

GX_AND8:                       ; No operands.
    LD   HL,GT_AND8                ; The u8 AND body.
    JR   GX_BIN8                   ; Wrap it in the pops and the push.

;@ROUTINE OUT CARRY CLOBBERS A,B,HL,SIGN,PARITY,HALFCARRY,ZERO
; OP_OR8: emit POP DE; POP HL; LD A,L; OR E; LD L,A; LD H,0; PUSH HL.

GX_OR8:                        ; No operands.
    LD   HL,GT_OR8                 ; The u8 OR body, falling into GX_BIN8.

;@ROUTINE IN HL OUT CARRY CLOBBERS A,B,HL,SIGN,PARITY,HALFCARRY,ZERO
; Emit a u8 operator: the five-byte body at HL between the pops and the push.

GX_BIN8:                       ; HL = a five-byte u8 body.
    LD   B,5                       ; LD A,L; op E; LD L,A; LD H,0.
    JR   GX_BINOP                  ; Emit the complete operator.

;@ROUTINE OUT CARRY CLOBBERS A,B,HL,SIGN,PARITY,HALFCARRY,ZERO
; OP_XOR16: emit POP DE; POP HL; LD A,L; XOR E; LD L,A; LD A,H; XOR D;
; LD H,A; PUSH HL.

GX_XOR16:                      ; No operands.
    LD   HL,GT_XOR16               ; The u16 exclusive-OR body.
    JR   GX_BIN16                  ; Wrap it in the pops and the push.

;@ROUTINE OUT CARRY CLOBBERS A,B,HL,SIGN,PARITY,HALFCARRY,ZERO
; OP_AND16: emit POP DE; POP HL; LD A,L; AND E; LD L,A; LD A,H; AND D;
; LD H,A; PUSH HL.

GX_AND16:                      ; No operands.
    LD   HL,GT_AND16               ; The u16 AND body.
    JR   GX_BIN16                  ; Wrap it in the pops and the push.

;@ROUTINE OUT CARRY CLOBBERS A,B,HL,SIGN,PARITY,HALFCARRY,ZERO
; OP_OR16: emit POP DE; POP HL; LD A,L; OR E; LD L,A; LD A,H; OR D;
; LD H,A; PUSH HL.

GX_OR16:                       ; No operands.
    LD   HL,GT_OR16                ; The u16 OR body, falling into GX_BIN16.

;@ROUTINE IN HL OUT CARRY CLOBBERS A,B,HL,SIGN,PARITY,HALFCARRY,ZERO
; Emit a u16 bitwise operator: the six-byte body at HL, byte by byte.

GX_BIN16:                      ; HL = a six-byte u16 body.
    LD   B,6                       ; Low byte with E, then high byte with D.
    JR   GX_BINOP                  ; Emit the complete operator.

;@ROUTINE OUT CARRY CLOBBERS A,B,HL,SIGN,PARITY,HALFCARRY,ZERO
; OP_ADD16: emit POP DE; POP HL; ADD HL,DE; PUSH HL.

GX_ADD16:                      ; No operands.
    LD   HL,GT_ADD16               ; ADD HL,DE, shared with GT_ADDA.
    LD   B,1                       ; A single-byte body.
    JR   GX_BINOP                  ; Wrap it in the pops and the push.

;@ROUTINE OUT CARRY CLOBBERS A,B,HL,SIGN,PARITY,HALFCARRY,ZERO
; OP_SUB16: emit POP DE; POP HL; XOR A; SBC HL,DE; PUSH HL.

GX_SUB16:                      ; No operands.
    LD   HL,GT_SUB16               ; XOR A clears carry for SBC HL,DE.
    LD   B,3                       ; Three-byte body.
    JR   GX_BINOP                  ; Wrap it in the pops and the push.

;@ROUTINE OUT CARRY CLOBBERS A,BC,DE,HL,SIGN,PARITY,HALFCARRY,ZERO
; OP_MUL8: emit POP DE; POP HL; CALL RT_MUL16; LD H,0; PUSH HL. The low
; byte of the 16-bit product is the u8 product modulo 256.

GX_MUL8:                       ; No operands.
    CALL GX_MULOP                  ; Pop both operands and multiply.
    CALL EM_IDIOM                  ; Emit the idiom named by the next byte.
    DB   EP_ZEROH                  ; LD H,0: keep the product's low byte.
    JR   GX_PUSH                   ; Push the product.

;@ROUTINE OUT CARRY CLOBBERS A,BC,DE,HL,SIGN,PARITY,HALFCARRY,ZERO
; OP_MUL16: emit POP DE; POP HL; CALL RT_MUL16; PUSH HL.

GX_MUL16:                      ; No operands.
    CALL GX_MULOP                  ; Pop both operands and multiply.
    JR   GX_PUSH                   ; Push the product modulo 65536.

;@ROUTINE OUT CARRY CLOBBERS A,BC,DE,HL,SIGN,PARITY,HALFCARRY,ZERO
; Emit POP DE; POP HL; CALL RT_MUL16, leaving HL*DE in HL.

GX_MULOP:                      ; Shared by both multiplications.
    CALL GX_ARGS                   ; Operands into HL and DE.
    LD   DE,RT_MUL16               ; The helper's offset in the runtime.
    JP   EM_HELP                   ; Emit the helper call.

;@ROUTINE IN HL OUT DE,CARRY CLOBBERS A,BC,HL,SIGN,PARITY,HALFCARRY,ZERO
; Emit CALL HL; JR NC,e and return in DE the address of e, for the caller to
; patch past a failure path. Unreferenced: GX_TRY serves every caller.

.TRYCALL:                      ; HL = the absolute call target.
    CALL EM_CALL                   ; Emit CALL nn.
    JP   EM_JRNC                   ; Emit JR NC with its operand pending in DE.

;@ROUTINE IN DE OUT DE,CARRY CLOBBERS A,BC,HL,SIGN,PARITY,HALFCARRY,ZERO
; Emit CALL helper DE; JR NC,e. The helper returns carry on failure, so the
; JR skips the failure path that follows; DE returns the address of e.

GX_TRY:                        ; DE = helper offset in the runtime.
    CALL EM_HELP                   ; Emit the helper call.
    JP   EM_JRNC                   ; Emit JR NC; DE = its pending operand.

;@ROUTINE OUT DE,CARRY CLOBBERS A,HL,SIGN,PARITY,HALFCARRY,ZERO
; Read the operation's source position into GX_POS for a later trap.

GX_NOTE:                       ; The read cursor is at a position word.
    CALL EM_READW                  ; DE = source offset of the operator.
    LD   (GX_POS),DE               ; GX_ARM reads it when it emits the trap.
    RET                            ; DE also returns the position.

;@ROUTINE IN DE OUT CARRY CLOBBERS A,BC,HL,SIGN,PARITY,HALFCARRY,ZERO
; Keep the success branch's operand address DE in EM_XFIX for GX_FIRE, and
; emit LD HL,position from GX_POS: the start of an inline trap body.

GX_ARM:                        ; DE = operand of the branch over the trap.
    LD   (EM_XFIX),DE              ; GX_FIRE lands this branch after the trap.
    LD   HL,(GX_POS)               ; The position GX_NOTE retained.
    JP   EM_LDHL                   ; At run time HL carries it into the trap.

;@ROUTINE OUT CARRY CLOBBERS A,BC,DE,HL,SIGN,PARITY,HALFCARRY,ZERO
; OP_DIV8: checked u8 division, the quotient pushed with H zero.

GX_DIV8:                       ; Operand: source position.
    LD   C,1                       ; Mode: quotient, u8 result.
    JR   GX_DIVOP                  ; Emit the checked division.

;@ROUTINE OUT CARRY CLOBBERS A,BC,DE,HL,SIGN,PARITY,HALFCARRY,ZERO
; OP_DIV16: checked u16 division.

GX_DIV16:                      ; Operand: source position.
    LD   C,0                       ; Mode: quotient, u16 result.
    JR   GX_DIVOP                  ; Emit the checked division.

;@ROUTINE OUT CARRY CLOBBERS A,BC,DE,HL,SIGN,PARITY,HALFCARRY,ZERO
; OP_MOD8: checked u8 remainder, pushed with H zero.

GX_MOD8:                       ; Operand: source position.
    LD   C,3                       ; Mode: remainder, u8 result.
    JR   GX_DIVOP                  ; Emit the checked division.

;@ROUTINE OUT CARRY CLOBBERS A,BC,DE,HL,SIGN,PARITY,HALFCARRY,ZERO
; OP_MOD16: checked u16 remainder.

GX_MOD16:                      ; Operand: source position.
    LD   C,2                       ; Mode: remainder, u16 result; fall through.

;@ROUTINE IN C OUT CARRY CLOBBERS A,BC,DE,HL,SIGN,PARITY,HALFCARRY,ZERO
; Emit POP DE; POP HL; CALL RT_DIV16 or RT_MOD16; JR NC,ok; trap 3; ok:
; [LD H,0;] PUSH HL. C bit 1 selects the remainder, bit 0 a u8 result.

GX_DIVOP:                      ; C = mode; the cursor is at the position.
    CALL GX_NOTE                   ; Retain the position for the zero-divisor trap.
    LD   A,C                       ; The mode must survive the emitters.
    LD   (GX_WIDTH),A              ; Keep it in scratch; they clobber C.
    CALL GX_ARGS                   ; Dividend into HL, divisor into DE.
    LD   DE,RT_DIV16               ; Assume a quotient.
    LD   A,(GX_WIDTH)              ; Recover the mode.
    BIT  1,A                       ; Is a remainder wanted?
    JR   Z,.HELPER                 ; No: keep the division helper.
    LD   DE,RT_MOD16               ; Yes: use the remainder helper.
.HELPER:                       ; DE = the chosen helper.
    CALL GX_TRY                    ; CALL it; JR NC past the trap for a nonzero divisor.
    LD   A,3                       ; Trap 3: division by zero.
    CALL GX_TRAP                   ; Emit the trap and land the JR NC after it.
    LD   A,(GX_WIDTH)              ; Recover the mode again.
    AND  1                         ; Is the result a u8?
    JR   Z,.RESULT                 ; No: the u16 result is already canonical.
    CALL EM_IDIOM                  ; Emit the idiom named by the next byte.
    DB   EP_ZEROH                  ; LD H,0: a canonical u8 carrier.
.RESULT:                       ; HL holds the result at run time.
    JP   GX_PUSH                   ; Push it.

;@ROUTINE OUT CARRY CLOBBERS A,B,HL,SIGN,PARITY,HALFCARRY,ZERO
; OP_NEG8: emit POP HL; XOR A; SUB L; LD L,A; LD H,0; PUSH HL.

GX_NEG8:                       ; No operands.
    LD   HL,GT_NEG8                ; The u8 negation, pop included.
    LD   B,6                       ; Six bytes.
    JR   GX_UNARY                  ; Emit it and push the result.

;@ROUTINE OUT CARRY CLOBBERS A,B,HL,SIGN,PARITY,HALFCARRY,ZERO
; OP_NEG16: emit POP HL; XOR A; SUB L; LD L,A; LD A,0; SBC A,H; LD H,A;
; PUSH HL: the two's complement, the borrow carried into the high byte.

GX_NEG16:                      ; No operands.
    LD   HL,GT_NEG16               ; The u16 negation, pop included.
    LD   B,8                       ; Eight bytes.
    JR   GX_UNARY                  ; Emit it and push the result.

;@ROUTINE OUT CARRY CLOBBERS A,B,HL,SIGN,PARITY,HALFCARRY,ZERO
; OP_NOT8: emit POP HL; LD A,L; CPL; LD L,A; LD H,0; PUSH HL.

GX_NOT8:                       ; No operands.
    LD   HL,GT_NOT8                ; The u8 complement, pop included.
    LD   B,6                       ; Six bytes.
    JR   GX_UNARY                  ; Emit it and push the result.

;@ROUTINE OUT CARRY CLOBBERS A,B,HL,SIGN,PARITY,HALFCARRY,ZERO
; OP_NOT16: emit POP HL; LD A,L; CPL; LD L,A; LD A,H; CPL; LD H,A; PUSH HL.

GX_NOT16:                      ; No operands.
    LD   HL,GT_NOT16               ; The u16 complement, pop included.
    LD   B,7                       ; Seven bytes.
    JR   GX_UNARY                  ; Emit it and push the result.

;@ROUTINE OUT CARRY CLOBBERS A,B,HL,SIGN,PARITY,HALFCARRY,ZERO
; OP_LNOT: emit POP HL; LD A,L; XOR 1; LD L,A; LD H,0; PUSH HL, turning
; boolean 0 into 1 and 1 into 0.

GX_FLIP:                       ; No operands.
    LD   HL,GT_FLIP                ; The boolean NOT, pop included.
    LD   B,7                       ; Seven bytes; fall into GX_UNARY.

;@ROUTINE IN B,HL OUT CARRY CLOBBERS A,B,HL,SIGN,PARITY,HALFCARRY,ZERO
; Emit the B-byte unary body at HL, which pops its own operand, then
; PUSH HL.

GX_UNARY:                      ; B = length, HL = body.
    CALL EM_BYTES                  ; Emit the pop and the operation.
    JP   GX_PUSH                   ; Push the result.

;@ROUTINE IN A OUT CARRY CLOBBERS A,BC,DE,HL,SIGN,PARITY,HALFCARRY,ZERO
; Emit LD A,relation; CALL RT_CMP16, leaving HL = 1 when HL relation DE
; holds and 0 otherwise. A is EX_EQ to EX_GE. GENCTRL's loops share it.

GX_TEST:                       ; A = relation code.
    CALL EM_LDA                    ; The helper reads the relation from A.
    LD   DE,RT_CMP16               ; The comparison helper.
    JP   EM_HELP                   ; Emit its call.

;@ROUTINE OUT CARRY CLOBBERS A,BC,DE,HL,SIGN,PARITY,HALFCARRY,ZERO
; OP_CMP8, OP_CMP16, OP_LCMP: emit POP DE; POP HL; LD A,relation;
; CALL RT_CMP16; PUSH HL. Carriers are canonical, so one 16-bit comparison
; serves u8, u16 and boolean operands alike.

GX_RELOP:                      ; Operand: relation code.
    CALL EM_READB                  ; A = relation code.
    LD   C,A                       ; Keep it in C ...
    PUSH BC                        ; ... and on the stack across the pops.
    CALL GX_ARGS                   ; Left into HL, right into DE.
    POP  BC                        ; Recover the relation.
    LD   A,C                       ; GX_TEST takes it in A.
    CALL GX_TEST                   ; HL = the 0/1 result at run time.
    JP   GX_PUSH                   ; Push the boolean carrier.

;@ROUTINE OUT CARRY CLOBBERS A,BC,DE,HL,SIGN,PARITY,HALFCARRY,ZERO
; OP_TRUNC: emit POP HL; LD A,H; OR A; JR Z,ok; trap 2; ok: PUSH HL. A u16
; value narrows to u8 only when its high byte is zero.

GX_FIT8:                       ; Operand: source position.
    CALL GX_NOTE                   ; Retain the position for the trap.
    CALL GX_POP                    ; The value into HL.
    CALL EM_IDIOM                  ; Emit the idiom named by the next byte.
    DB   EP_TESTH                  ; LD A,H; OR A: is the high byte zero?
    LD   A,$28                     ; JR Z: skip the trap when the value fits.
    CALL EM_JRCC                   ; Emit it; DE = its pending operand.
    LD   A,2                       ; Trap 2: the value does not fit a u8.
    CALL GX_TRAP                   ; Emit the trap and land JR Z after it.
    JP   GX_PUSH                   ; Push the value, already canonical.

;@ROUTINE OUT CARRY CLOBBERS A,BC,DE,HL,SIGN,PARITY,HALFCARRY,ZERO
; OP_STG8: emit POP HL; LD A,L; LD (nn),A for a u8 global. RG_CATCH stores
; a caught error code through it.

GX_ST8:                        ; Operand: the global's data or bss offset.
    CALL EM_READA                  ; HL = the global's absolute address.
    PUSH HL                        ; Keep it while the pop is emitted.
    CALL EM_IDIOM                  ; Emit the idiom named by the next byte.
    DB   EP_POPA                   ; POP HL; LD A,L: the value's low byte.
    POP  HL                        ; Recover the address.
    LD   A,$32                     ; LD (nn),A: write the global's byte.
    JP   EM_OPW                    ; Emit the store.

;@ROUTINE OUT CARRY CLOBBERS A,BC,DE,HL,SIGN,PARITY,HALFCARRY,ZERO
; OP_STG16: emit POP HL; LD (nn),HL for a u16 global.

GX_ST16:                       ; Operand: the global's data or bss offset.
    CALL EM_READA                  ; HL = the global's absolute address.
    PUSH HL                        ; Keep it while the pop is emitted.
    CALL GX_POP                    ; The value into HL.
    POP  HL                        ; Recover the address.
    LD   A,$22                     ; LD (nn),HL: write the global's word.
    JP   EM_OPW                    ; Emit the store.

;@ROUTINE OUT C,CARRY CLOBBERS A,B,HL,SIGN,PARITY,HALFCARRY,ZERO
; OP_STL8, OP_STP8: emit POP HL; LD (IX+d),L for a u8 local. C returns d
; for GX_STX16's high byte.

GX_STX8:                       ; Operand: the local's byte offset.
    CALL GX_LOCAL                  ; C = displacement of the low byte.
    CALL GX_POP                    ; The value into HL; C survives.
    LD   HL,GT_STLO                ; LD (IX+d),L
    JP   GX_IXOP                   ; Store the low byte.

;@ROUTINE OUT CARRY CLOBBERS A,BC,HL,SIGN,PARITY,HALFCARRY,ZERO
; OP_STL16, OP_STP16: emit POP HL; LD (IX+d),L; LD (IX+d-1),H for a u16
; local.

GX_STX16:                      ; Operand: the local's byte offset.
    CALL GX_STX8                   ; Pop and store the low byte; C = d.
    DEC  C                         ; The high byte is stored one byte lower.
    LD   HL,GT_STHI                ; LD (IX+d),H
    JP   GX_IXOP                   ; Store the high byte.

;@ROUTINE OUT CARRY CLOBBERS A,BC,DE,HL,SIGN,PARITY,HALFCARRY,ZERO
; OP_WRVAL: emit POP HL; LD A,L; CALL vector 1; JR NC,ok; LD HL,position;
; LD (RT_TERR),A; LD A,6; trap; ok:. A failed write is an unhandled error.

GX_WRITE:                      ; Operand: source position.
    CALL GX_NOTE                   ; Retain the position for the trap.
    CALL EM_IDIOM                  ; Emit the idiom named by the next byte.
    DB   EP_POPA                   ; POP HL; LD A,L: the byte to write.
    LD   A,1                       ; The write service's vector ordinal.
    CALL EM_CALLV                  ; Emit CALL to the vector.
    CALL EM_JRNC                   ; Carry reports failure; DE = JR NC operand.
    CALL GX_ARM                    ; Keep the operand; emit LD HL,position.
    CALL EM_STRAY                  ; Record the error code A; trap 6.
    JR   GX_FIRE                   ; Emit the trap and land JR NC after it.

; Every trap restores the root frame before it writes the trap record, so the
; terminal dispatch runs on the stack the startup left, however deep the trap.
; Without it, that stack would hold local bytes or a saved IX where the
; terminal expects the startup's own words.
;@ROUTINE OUT CARRY CLOBBERS A,BC,DE,HL,SIGN,PARITY,HALFCARRY,ZERO
; Emit the body every trap shares: LD SP,(RT_SP); LD IX,(RT_IX); clear
; RT_DEPTH; record trap A at position HL; stop (EM_TRAP).

GX_ABORT:                      ; At run time A = trap, HL = position.
    CALL GX_RESET                  ; Return to the frame saved before main.
    CALL EM_OP                     ; Emit the next byte and continue.
    DB   $F5                       ; PUSH AF: keep the trap number across the clear.
    CALL EM_OP                     ; Emit the next byte and continue.
    DB   $AF                       ; XOR A: no routine remains active.
    LD   DE,RT_DEPTH-RT_BASE       ; The activation count byte.
    CALL EM_TOVAR                  ; Emit LD (RT_DEPTH),A.
    CALL EM_OP                     ; Emit the next byte and continue.
    DB   $F1                       ; POP AF: the trap number again.
    JP   EM_TRAP                   ; Write the trap record and stop.

;@ROUTINE IN A,HL OUT CARRY CLOBBERS A,BC,DE,HL,SIGN,PARITY,HALFCARRY,ZERO
; Emit LD HL,position; LD A,trap and the shared trap body for source
; position HL and trap A. The caller owns and patches the branch around it.

GX_RAISE:                      ; Called by GENCALL's guards and GC_NEXT.
    PUSH AF                        ; Keep the trap number.
    CALL EM_LDHL                   ; Emit LD HL,position.
    POP  AF                        ; Recover the trap number.
    CALL EM_LDA                    ; Emit LD A,trap.
    JR   GX_ABORT                  ; Emit the shared body.

;@ROUTINE IN A,DE OUT CARRY CLOBBERS A,BC,DE,HL,SIGN,PARITY,HALFCARRY,ZERO
; Emit a trap with number A at the position GX_NOTE retained, then patch the
; success branch whose operand is at DE to land after it.

GX_TRAP:                       ; A = trap, DE = success-branch operand.
    PUSH AF                        ; Keep the trap number.
    CALL GX_ARM                    ; Keep DE; emit LD HL,position.
    POP  AF                        ; Recover the trap number.
    CALL EM_LDA                    ; Emit LD A,trap; fall into GX_FIRE.

;@ROUTINE OUT CARRY CLOBBERS A,BC,DE,HL,SIGN,PARITY,HALFCARRY,ZERO
; Emit the shared trap body, then land the branch kept in EM_XFIX after it.

GX_FIRE:                       ; A and HL are loaded at run time.
    CALL GX_ABORT                  ; Emit the restore, record and stop.
    LD   DE,(EM_XFIX)              ; The success branch GX_ARM kept.
    JP   EM_LAND                   ; It lands on the next instruction.

; Save the outer machine frame before main allocates locals, and restore that
; exact frame on every terminal trap, including a trap inside recursive calls.
;@ROUTINE OUT CARRY CLOBBERS A,BC,DE,HL,SIGN,PARITY,HALFCARRY,ZERO
; Emit LD (RT_SP),SP; LD (RT_IX),IX.

GX_SAVE:                       ; Called by GX_START.
    LD   HL,GT_STSP                ; The two store prefixes.
    JR   GX_ROOT                   ; Emit them with RT_SP and RT_IX.

;@ROUTINE OUT CARRY CLOBBERS A,BC,DE,HL,SIGN,PARITY,HALFCARRY,ZERO
; Emit LD SP,(RT_SP); LD IX,(RT_IX), returning to the frame GX_SAVE kept.

GX_RESET:                      ; Called by every trap and RG_MAIN.
    LD   HL,GT_LDSP                ; The two load prefixes; fall into GX_ROOT.

;@ROUTINE IN HL OUT CARRY CLOBBERS A,BC,DE,HL,SIGN,PARITY,HALFCARRY,ZERO
; Emit the opcode pair at HL with RT_SP's address, then the pair at HL+2
; with RT_IX's address.

GX_ROOT:                       ; HL = GT_STSP or GT_LDSP.
    PUSH HL                        ; Keep the template.
    CALL EM_PAIR                   ; The SP instruction's two opcode bytes.
    POP  HL                        ; Recover the template ...
    PUSH HL                        ; ... and keep it for the IX pair.
    LD   DE,RT_SP-RT_BASE          ; The saved stack pointer word.
    CALL TG_VAR                    ; HL = its address in the target.
    CALL EM_WORD                   ; The SP instruction's operand.
    POP  HL                        ; Recover the template.
    INC  HL                        ; Step past the SP pair ...
    INC  HL                        ; ... to the IX pair.
    CALL EM_PAIR                   ; The IX instruction's two opcode bytes.
    LD   DE,RT_IX-RT_BASE          ; The saved frame pointer word.
    CALL TG_VAR                    ; HL = its address in the target.
    JP   EM_WORD                   ; The IX instruction's operand.

; Begin the single retained value routine. Operand bytes are routine ordinal
; and parameter type. HL carries the copied argument into this entry.
;@ROUTINE OUT CARRY CLOBBERS A,BC,DE,HL,SIGN,PARITY,HALFCARRY,ZERO
; OP_FUNC: place label CT_RDEST, emit the frame prologue, then copy HL into
; the parameter's slot: DEC SP; LD (IX-1),L for a u8, and for a u16 also
; DEC SP; LD (IX-2),H.

GX_ENTER:                      ; Operands: ordinal, parameter type.
    CALL EM_READB                  ; The ordinal; only one such routine exists.
    CALL EM_READB                  ; A = the parameter's type.
    LD   (GX_WIDTH),A              ; Keep it across the label and prologue.
    LD   C,CT_RDEST                ; The value routine's fixed label.
    CALL GC_PLACE                  ; Calls to it resolve to here.
    LD   HL,GT_ENTER               ; PUSH IX; LD IX,0; ADD IX,SP.
    CALL EM_EIGHT                  ; Open the routine's frame.
    LD   A,(GX_WIDTH)              ; Recover the parameter type.
    CP   SY_U16                    ; Does it need two bytes?
    LD   HL,GT_NEW8                ; Assume a u8: reserve and store L.
    LD   B,4                       ; Four bytes.
    JR   NZ,.PARAM                 ; A u8 parameter: emit them.
    LD   HL,GT_NEW16               ; A u16: reserve two and store L and H.
    LD   B,8                       ; Eight bytes.
.PARAM:                        ; HL = copy template, B = its length.
    JP   EM_BYTES                  ; Emit the parameter copy.

; The argument expression has already left its value as one canonical carrier.
; Claim activation capacity before the callee begins, then call the fixed
; forward label. The result returns in HL and becomes the enclosing carrier.
;@ROUTINE OUT CARRY CLOBBERS A,BC,DE,HL,SIGN,PARITY,HALFCARRY,ZERO
; OP_FCALL: emit POP HL; CALL RT_CLAIM; JR NC,ok; trap 5; ok:
; CALL routine; CALL RT_FREE; PUSH HL.

GX_CALL:                       ; Operands: ordinal, result type, position.
    CALL EM_READB                  ; The ordinal; only one value routine exists.
    CALL EM_READB                  ; A = the result type.
    LD   (GX_WIDTH),A              ; Stored but not read: the result is a carrier.
    CALL GX_NOTE                   ; Retain the position for the trap.
    CALL GX_POP                    ; The argument into HL, where the callee expects it.
    LD   DE,RT_CLAIM               ; Claim an activation; carry when none is left.
    CALL GX_TRY                    ; Emit the claim and JR NC past the trap.
    LD   A,5                       ; Trap 5: activation capacity exhausted.
    CALL GX_TRAP                   ; Emit the trap and land JR NC after it.
    LD   C,CT_RDEST                ; The value routine's fixed label.
    LD   A,$CD                     ; CALL nn: enter the value routine.
    CALL GC_OPREF                  ; Emit the call; its operand is fixed up later.
    LD   DE,RT_FREE                ; Release the activation, keeping HL.
    CALL EM_HELP                   ; Emit the release.
    CALL EM_ENDOP                  ; Emit the next byte and return.
    DB   $E5                       ; PUSH HL: the result becomes the carrier.

;@ROUTINE OUT CARRY CLOBBERS A,B,HL,SIGN,PARITY,HALFCARRY,ZERO
; OP_RET, OP_RETA: emit POP HL; LD SP,IX; POP IX; RET, returning the top
; carrier in HL.

GX_RET:                        ; Also RG_RET.
    CALL GX_POP                    ; The result into HL.
    CALL EM_LEAVE                  ; LD SP,IX; POP IX: close the frame.
    CALL EM_ENDOP                  ; Emit the next byte and return.
    DB   $C9                       ; RET: back to the caller with HL.

;@ROUTINE OUT CARRY CLOBBERS A,SIGN,PARITY,HALFCARRY,ZERO
; OP_ENDFN: the value routine always ends in its RET, so nothing is emitted.

GX_CLOSE:                      ; No operands.
    XOR  A                         ; Report success with carry clear.
    RET                            ; Emit nothing.

;@ROUTINE IN DE OUT CARRY CLOBBERS A,BC,HL,SIGN,PARITY,HALFCARRY,ZERO
; Push the pending JR operand address DE onto the short-circuit stack.
; More than GX_BCAP open branches raise DG_ANDOR.

GX_PUTJR:                      ; DE = address of a JR displacement.
    LD   A,(GX_BCNT)               ; Branches already open.
    CP   GX_BCAP                   ; Is the stack full?
    JP   NC,GX_FULL                ; Yes: too deeply nested.
    LD   C,A                       ; BC = index of the free entry.
    LD   B,0                       ; Complete the 16-bit index.
    LD   HL,GX_BBASE               ; Entries are words from GX_BBASE.
    ADD  HL,BC                     ; Add the index twice ...
    ADD  HL,BC                     ; ... for two bytes per entry.
    LD   (HL),E                    ; Store the operand address, low byte.
    INC  HL                        ; Step to the high byte.
    LD   (HL),D                    ; The entry is complete.
    LD   A,(GX_BCNT)               ; Count the new entry.
    INC  A                         ; One more branch open.
    LD   (GX_BCNT),A               ; Publish it.
    OR   A                         ; Clear carry for success.
    RET                            ; DE is unchanged.

;@ROUTINE OUT DE,CARRY CLOBBERS A,BC,HL,SIGN,PARITY,HALFCARRY,ZERO
; Pop the innermost open JR operand address into DE. An empty stack means an
; unbalanced transcript and is rejected.

GX_GETJR:                      ; Called by GX_JOIN.
    LD   A,(GX_BCNT)               ; Branches open.
    OR   A                         ; Is there one to close?
    JP   Z,GX_BADOP                ; No: a JOIN without its AND or OR.
    DEC  A                         ; Remove the innermost entry.
    LD   (GX_BCNT),A               ; Publish the new count.
    LD   C,A                       ; BC = index of the removed entry.
    LD   B,0                       ; Complete the 16-bit index.
    LD   HL,GX_BBASE               ; Entries are words from GX_BBASE.
    ADD  HL,BC                     ; Add the index twice ...
    ADD  HL,BC                     ; ... for two bytes per entry.
    LD   E,(HL)                    ; Operand address, low byte.
    INC  HL                        ; Step to the high byte.
    LD   D,(HL)                    ; DE = the JR operand to patch.
    OR   A                         ; Clear carry for success.
    RET                            ; Return the operand in DE.

;@ROUTINE OUT CARRY CLOBBERS A,BC,DE,HL,SIGN,PARITY,HALFCARRY,ZERO
; OP_CAND: emit POP HL; LD A,L; OR A; JR NZ,+3; PUSH HL; JR join. A true
; left operand is dropped and the right one decides; a false one is the result.

GX_ANDIF:                      ; No operands.
    LD   HL,GT_ANDIF               ; The test that falls through when true.
    LD   B,6                       ; Six bytes before the JR.
    JR   GX_SHORT                  ; Emit them and open the branch.

;@ROUTINE OUT CARRY CLOBBERS A,BC,DE,HL,SIGN,PARITY,HALFCARRY,ZERO
; OP_COR: emit POP HL; LD A,L; OR A; JR Z,+3; PUSH HL; JR join. A false
; left operand is dropped and the right one decides; a true one is the result.

GX_ORIF:                       ; No operands.
    LD   HL,GT_ORIF                ; The test that falls through when false.
    LD   B,6                       ; Six bytes; fall into GX_SHORT.

;@ROUTINE IN B,HL OUT CARRY CLOBBERS A,BC,DE,HL,SIGN,PARITY,HALFCARRY,ZERO
; Emit the B-byte test at HL and a JR to the join, and push the JR's operand
; for GX_JOIN to patch.

GX_SHORT:                      ; B = test length, HL = test.
    CALL EM_BYTES                  ; The test; its JR cc,+3 skips PUSH HL and JR.
    CALL EM_JR                     ; JR join; DE = its pending operand.
    JR   GX_PUTJR                  ; Open the branch until OP_JOIN.

;@ROUTINE OUT CARRY CLOBBERS A,BC,DE,HL,SIGN,PARITY,HALFCARRY,ZERO
; OP_JOIN: land the innermost short-circuit JR here, after the right
; operand's code, where either path has left one carrier on the stack.

GX_JOIN:                       ; No operands.
    CALL GX_GETJR                  ; DE = the innermost open JR operand.
    JP   EM_LAND                   ; Patch it to the current address.

;@ROUTINE OUT CARRY CLOBBERS A,BC,DE,HL,SIGN,PARITY,HALFCARRY,ZERO
; OP_HALT: emit LD SP,IX; POP IX and the success stop (EM_DONE). No
; short-circuit branch may still be open.

GX_EXIT:                       ; No operands.
    LD   A,(GX_BCNT)               ; Branches still open.
    OR   A                         ; Halting inside an expression?
    JP   NZ,GX_BADOP               ; Yes: the transcript is unbalanced.
    CALL EM_LEAVE                  ; Close main's frame.
    JP   EM_DONE                   ; Record success and stop.

; Unreferenced. In Nucleus the typed-expression proof harness entered here;
; the label now only separates the generator's code from its template.
GX_BEG:                        ; Marker between code and data.

GT_LDIR: DB   $ED,$B0          ; LDIR: RG_COPY's block move (GT_BLOCK).
