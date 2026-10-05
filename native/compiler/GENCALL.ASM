;==========================================================================
;  Routine, call and aggregate-access code generation
;==========================================================================
;
;  Replay the routine, call, failure and aggregate operations of the
;  semantic transcript into Z80 code. ROUTINES.ASM and the grammar actions
;  wrote them during parsing; GX_WALK dispatches each one here by its
;  operation number. A handler reads its operands with EM_READB/EM_READW
;  and emits through the EMIT primitives.
;
;  Principal entries, with the operation each one handles:
;    RG_ENTER  OP_PROC    place a routine's label and emit its prologue
;    RG_BIND   OP_BIND    copy one argument into the new activation
;    RG_CALL   OP_CALL    call a routine or service, handle failure, drop args
;    RG_RET    OP_RETA    return an aggregate address from a routine
;    RG_RETOK  OP_RETF/OP_RETAF  return a value from a failable routine
;    RG_CLOSE  OP_ENDP    end a routine that cannot fail
;    RG_ENDOK  OP_ENDF    end a failable routine
;    RG_FAIL   OP_FAIL    fail with the u8 code on the evaluation stack
;    RG_FATAL  OP_ABORT   stop the program with an unhandled error
;    RG_SKIP   OP_HSKIP   jump over a handler body on success
;    RG_CATCH  OP_HOPEN   enter a handler: store the error code
;    RG_JOIN   OP_HDONE   place the label after a handler
;    RG_MAIN   OP_ENTRY   emit the startup wrapper and open main's body
;    RG_GLOB   OP_REFG    push a program variable's address
;    RG_CONST  OP_REFRO   push an aggregate constant's address
;    RG_PARAM  OP_REFP    push a parameter's address word
;    RG_FIELD  OP_FIELD   add a record field's offset to an address
;    RG_INDEX  OP_INDEX   check an array index and address the element
;    RG_GET8, RG_GET16    OP_LDX8/OP_LDX16  load a scalar through an address
;    RG_PUT8, RG_PUT16    OP_STX8/OP_STX16  store a scalar through an address
;    RG_COPY   OP_COPY    check and copy one aggregate onto another
;    RG_LEN    OP_LEN     a bounded string's length
;    RG_CHAR   OP_CHAR    check a string index and address the byte
;    OS_LEN    OP_VLEN    RG_LEN for an open-string parameter
;    OS_CHAR   OP_VCHAR   RG_CHAR for an open-string parameter
;    OS_ARG    OP_VIEW    turn a string address into an open-string argument
;
;  Generated code is a stack machine: every value is a 16-bit carrier on
;  the hardware stack, and an aggregate is carried as its address. After
;  the prologue PUSH IX / LD IX,0 / ADD IX,SP an activation is:
;
;    IX+4...  arguments, the last one pushed at IX+4 (RO_DISP)
;    IX+2     return address
;    IX+0     the caller's IX
;    IX-1...  parameter copies and locals: slot s has its low byte at
;             IX-(s+1) and its high byte below it
;    below    the evaluation stack
;
;  A caller pushes arguments left to right. An open-string argument is two
;  words: its capacity, then its address above it. Each call is bracketed
;  by RT_CLAIM, which counts activations against an arena of eight, and
;  RT_FREE. A result comes back in HL (a service's in A); the caller pops
;  its argument carriers. A failable routine returns carry clear on
;  success, or carry set with a u8 error code in A, and the caller's
;  handling bytes (RG_MODE, RG_HDEST, RG_KEPT) choose what follows. A failed
;  run-time check emits an inline terminal trap: LD HL,offset / LD A,trap
;  and GX_ABORT's sequence. Traps are 1 bounds, 5 call depth and 6 an
;  unhandled error.
;
;  At 65.4 the edges change to D41: parameters used in place, the callee
;  removing them, results in A, HL or DEHL, traps as CALL cc,TRAP_x.

;@ROUTINE OUT A,CARRY,ZERO CLOBBERS SIGN,PARITY,HALFCARRY,BC,DE,HL
; OP_PROC: label, parameter count, bank. Select the routine's bank, place its
; label and emit the frame prologue. The parameters arrive as OP_BINDs.

RG_ENTER:
    CALL EM_READB                  ; Read the routine's label ordinal.
    LD   C,A                       ; RG_FRAME places label C.
    CALL EM_READB                  ; The parameter count; the binds follow.
    CALL EM_READB                  ; The bank of the routine's source part.
    PUSH BC                        ; TG_PICK clobbers the label in C.
    CALL TG_PICK                   ; Direct the routine's code to that bank.
    POP  BC                        ; Recover the label.

;@ROUTINE IN C OUT A,CARRY,ZERO CLOBBERS SIGN,PARITY,HALFCARRY,BC,DE,HL
; Place label C at the current address and emit the prologue PUSH IX /
; LD IX,0 / ADD IX,SP. RG_MAIN enters here for main's callable body.

RG_FRAME:
    CALL GC_PLACE                  ; Calls and jumps to label C land here.
    LD   HL,GT_ENTER               ; Select the eight-byte frame prologue.
    JP   EM_EIGHT                  ; Emit it and return.

;@ROUTINE OUT A,CARRY,ZERO CLOBBERS SIGN,PARITY,HALFCARRY,BC,DE,HL
; OP_BIND: exact type, frame slot, argument displacement. Grow the frame by
; the parameter's size and copy its argument from IX+displacement into the
; slot: one byte for u8 and boolean, a word for u16 and an aggregate's
; address, and for an open string the word plus its capacity byte.

RG_BIND:
    CALL EM_READB                  ; Read the parameter's exact type.
    LD   (RO_OTYPE),A              ; Keep it to choose the copy's width.
    CALL EM_READB                  ; Read its frame slot.
    CPL                            ; Make it -(slot+1), the low byte's offset.
    LD   (RO_OPOS),A               ; Keep the slot's low-byte displacement.
    CALL EM_READB                  ; Read the argument's IX displacement.
    LD   (RO_AIDX),A               ; Keep the argument's positive displacement.
    LD   A,(RO_OTYPE)              ; Classify the parameter by its type.
    CP   AG_VIEW                   ; An open string takes three bytes.
    JR   Z,.OPEN                   ; Allocate its capacity byte first.
    CP   AG_FIRST                  ; Any other aggregate is one address word.
    JR   NC,.WORD                  ; Copy it as a word.
    CP   SY_U16                    ; A u16 is a word as well.
    JR   Z,.WORD                   ; Copy it as a word.
    CALL EM_OP                     ; A u8 or boolean takes one frame byte.
    DB   $3B                       ; DEC SP: allocate the byte's slot.
    LD   HL,GT_LDLO                ; LD L,(IX+argument).
    CALL .FROMARG                  ; Load the argument's low byte.
    LD   HL,GT_STLO                ; LD (IX+slot),L.
    JR   .TOLOCAL                  ; Store it in the slot and return.
.OPEN:                         ; Allocate an open string's capacity byte.
    CALL EM_OP                     ; One byte below the address word.
    DB   $3B                       ; DEC SP: allocate the capacity byte.
.WORD:                         ; Copy a word argument.
    CALL EM_IDIOM                  ; Two frame bytes for the word.
    DB   EP_DECSP                  ; DEC SP / DEC SP.
    LD   HL,GT_LDLO                ; LD L,(IX+argument).
    CALL .FROMARG                  ; Load the argument's low byte.
    CALL EM_IDIOM                  ; Load the high byte into H.
    DB   EP_LDHI                   ; LD H,(IX+n).
    LD   A,(RO_AIDX)               ; The high byte sits one above the low.
    INC  A                         ; Form the argument's high displacement.
    CALL EM_BYTE                   ; Emit it as the displacement.
    LD   HL,GT_STLO                ; LD (IX+slot),L.
    CALL .TOLOCAL                  ; Store the low byte in the slot.
    CALL EM_IDIOM                  ; Store the high byte from H.
    DB   EP_STHI                   ; LD (IX+n),H.
    LD   A,(RO_OPOS)               ; The slot's high byte lies one below.
    DEC  A                         ; Form its displacement.
    CALL EM_BYTE                   ; Emit it as the displacement.
    LD   A,(RO_OTYPE)              ; Only an open string has more to copy.
    CP   AG_VIEW                   ; Is this parameter an open string?
    JR   Z,.CAPACITY               ; Then copy its capacity too.
    OR   A                         ; Report success with carry clear.
    RET                            ; The parameter is bound.
.CAPACITY:                     ; Copy the hidden capacity byte.
    CALL EM_IDIOM                  ; The capacity is the word above the address.
    DB   EP_LDLO                   ; LD L,(IX+n).
    LD   A,(RO_AIDX)               ; Address the argument's capacity word.
    INC  A                         ; Skip the address's high byte.
    INC  A                         ; Reach the capacity's low byte.
    CALL EM_BYTE                   ; Emit it as the displacement.
    CALL EM_IDIOM                  ; Store the capacity in the frame.
    DB   EP_STLO                   ; LD (IX+n),L.
    LD   A,(RO_OPOS)               ; The capacity sits below the address word.
    DEC  A                         ; Skip the slot's high byte.
    DEC  A                         ; Reach the capacity byte.
    JP   EM_BYTE                   ; Emit the displacement and return.

;@ROUTINE IN HL OUT A,CARRY,ZERO CLOBBERS SIGN,PARITY,HALFCARRY,BC,DE,HL
; Emit the IX-indexed opcode pair at HL with the argument's displacement.

.FROMARG:
    CALL EM_PAIR                   ; Emit the prefix and the opcode.
    LD   A,(RO_AIDX)               ; The argument's IX displacement.
    JP   EM_BYTE                   ; Complete the instruction.

;@ROUTINE IN HL OUT A,CARRY,ZERO CLOBBERS SIGN,PARITY,HALFCARRY,BC,DE,HL
; Emit the IX-indexed opcode pair at HL with the slot's displacement.

.TOLOCAL:
    CALL EM_PAIR                   ; Emit the prefix and the opcode.
    LD   A,(RO_OPOS)               ; The slot's negative IX displacement.
    JP   EM_BYTE                   ; Complete the instruction.

;@ROUTINE OUT A,CARRY,ZERO CLOBBERS SIGN,PARITY,HALFCARRY,BC,DE,HL
; Emit JR NC over a bounds trap for a run-time helper that has just
; returned carry on failure: LD HL,RO_DPOS / LD A,1 and GX_ABORT's sequence.
; The branch is patched to land after the trap.

RG_GUARD:
    CALL EM_JRNC                   ; Success skips the trap; DE is the operand.
    LD   (EM_FFIX),DE              ; Keep the operand while the trap is emitted.
    LD   HL,(RO_DPOS)              ; The trap reports this source offset.
    LD   A,1                       ; Trap 1 is a bounds failure.
    CALL GX_RAISE                  ; Emit the terminal trap.
    LD   DE,(EM_FFIX)              ; Recover the branch operand.
    JP   EM_LAND                   ; Land the branch after the trap.

;@ROUTINE OUT A,DE,HL,CARRY,ZERO CLOBBERS SIGN,PARITY,HALFCARRY
; Read an operation's source-offset operand into RO_DPOS for its traps.

RG_NOTE:
    CALL EM_READW                  ; Read the offset word.
    LD   (RO_DPOS),DE              ; Keep it for traps and failure marks.
    RET                            ; DE also returns the offset.

;@ROUTINE OUT A,CARRY,ZERO CLOBBERS SIGN,PARITY,HALFCARRY,B,DE,HL
; Read a call's three handling bytes, which RO_PAD reserved and the grammar
; actions filled: the mode, the handler's label and the kept carriers.

RG_RULES:
    LD   DE,RG_MODE                ; RG_MODE, RG_HDEST and RG_KEPT are adjacent.
    LD   B,3                       ; Copy all three bytes.
.LOOP:                         ; Copy one handling byte.
    CALL EM_READB                  ; Read the mode, handler label or kept count.
    LD   (DE),A                    ; Store it in the next field.
    INC  DE                        ; Advance to the following field.
    DJNZ .LOOP                     ; Repeat for all three.
    RET                            ; The call's handling is known.

;@ROUTINE OUT A,CARRY,ZERO CLOBBERS SIGN,PARITY,HALFCARRY,BC,DE,HL
; Emit LD HL,RO_DPOS / LD (RT_TPOS),HL, recording the source position of
; a failure that is propagated. If the failure leaves main, the startup
; wrapper reports the latest propagation site.

RG_MARK:
    LD   HL,(RO_DPOS)              ; The failing call or statement's offset.
    CALL EM_LDHL                   ; Emit LD HL,offset.
    LD   DE,RT_TPOS-RT_BASE        ; The runtime's trap-position word.
    CALL TG_VAR                    ; HL is its address in the target.
    LD   A,$22                     ; LD (nn),HL.
    JP   EM_OPW                    ; Emit the store and return.

;@ROUTINE OUT A,CARRY,ZERO CLOBBERS SIGN,PARITY,HALFCARRY,BC,DE,HL,IX,IY
; OP_CALL: selector, then for a source routine the argument carriers, result
; type and callee flags, then the offset and three handling bytes. Emit the
; call between CALL RT_CLAIM (trap 5 on overflow) and CALL RT_FREE, branch on
; failure, pop the argument carriers and push a kept result.

RG_CALL:
    CALL EM_READB                  ; Read the call selector.
    LD   (RO_DEST),A               ; Keep kind, keep bit and target.
    AND  RO_FIO                    ; Is the target a service?
    JR   NZ,.SERVICE               ; Services carry no signature bytes.
    CALL EM_READB                  ; Read the argument carriers to drop.
    LD   (RO_ACNT),A               ; RG_AFTER pops this many words.
    CALL EM_READB                  ; Read the result type, zero for none.
    LD   (RO_DTYPE),A              ; RG_AFTER pushes a kept result.
    CALL EM_READB                  ; Read the callee's flags and bank.
    LD   (RG_FLAGS),A              ; Keep them for failure and bank tests.
    JR   .COMMON                   ; Join the service path.
.SERVICE:                      ; Derive a service's result type.
    LD   A,(RO_DEST)               ; The selector holds the signature.
    AND  RO_RES8                   ; Keep the u8-result bit, bit 5.
    RLCA                           ; Rotate it toward bit 0.
    RLCA                           ; Bit 7 now.
    RLCA                           ; Bit 0: SY_U8 or zero.
    LD   (RO_DTYPE),A              ; Record the service's result type.
.COMMON:                       ; Read the operands every call carries.
    CALL RG_NOTE                   ; The call's source offset.
    CALL RG_RULES                  ; Its handling mode, handler and kept count.
    LD   A,(RO_DEST)               ; Recover the selector.
    AND  RO_FIO                    ; Is the target a service?
    JP   NZ,RG_SERVE               ; Services call a RAM vector instead.
    LD   DE,RT_CLAIM               ; Claim an activation before the call.
    CALL GX_TRY                    ; CALL RT_CLAIM / JR NC,claimed.
    LD   (EM_XFIX),DE              ; Keep the branch operand.
    LD   HL,(RO_DPOS)              ; The trap reports the call's offset.
    LD   A,5                       ; Trap 5: the activation arena is full.
    CALL GX_RAISE                  ; Emit the terminal trap.
    LD   DE,(EM_XFIX)              ; Recover the branch operand.
    CALL EM_LAND                   ; A successful claim lands here.
    LD   A,(RO_DEST)               ; Recover the selector.
    AND  RO_LMASK                  ; Keep the callee's label ordinal.
    LD   C,A                       ; .ROUTINE calls label C.
    CALL .ROUTINE                  ; Emit the call itself.
    LD   A,(RG_FLAGS)              ; Can the callee fail?
    AND  RO_FFAIL                  ; Test its failable flag.
    JR   NZ,.CANFAIL               ; Then keep its carry and A across RT_FREE.
    LD   DE,RT_FREE                ; Release the activation.
    CALL EM_HELP                   ; Emit CALL RT_FREE.
    JR   RG_AFTER                  ; Drop arguments and keep the result.

;@ROUTINE IN C OUT A,CARRY,ZERO CLOBBERS SIGN,PARITY,HALFCARRY,BC,DE,HL,IX,IY
; Emit CALL label C when the callee is in the bank being emitted. A call to
; another bank loads the bank into A and the address into HL and calls
; vector 9, which switches, calls and restores the caller's bank. BASIE.COM's
; target has one bank, so only the near CALL is ever emitted.

.ROUTINE:
    LD   A,(RG_FLAGS)              ; The callee's flags hold its bank.
    CALL TG_SPLIT                  ; Extract the bank.
    LD   D,A                       ; Keep it for the comparison.
    LD   A,(TG_OBANK)              ; The bank receiving this code.
    CP   D                         ; Is the callee in the same bank?
    JR   NZ,.FAR                   ; Otherwise call through the far vector.
    LD   A,$CD                     ; CALL nn.
    JP   GC_OPREF                  ; Emit it with a fixup to label C.
.FAR:                          ; Emit a cross-bank call.
    PUSH BC                        ; EM_OPB clobbers the label in C.
    PUSH DE                        ; Keep the callee's bank in D.
    LD   C,D                       ; The bank is the immediate operand.
    LD   A,$3E                     ; LD A,n: the callee's bank.
    CALL EM_OPB                    ; Emit it.
    POP  DE                        ; Restore the bank.
    POP  BC                        ; Restore the label.
    LD   A,$21                     ; LD HL,nn: the callee's address.
    CALL GC_OPFAR                  ; Emit it with a cross-bank fixup.
    LD   A,9                       ; Vector 9 is the far call.
    JP   EM_CALLV                  ; Emit CALL through the vector.
.CANFAIL:                      ; Release the activation of a failable call.
    CALL EM_OP                     ; RT_FREE clobbers A and the flags.
    DB   $F5                       ; PUSH AF: keep carry and the error code.
    LD   DE,RT_FREE                ; Release the activation.
    CALL EM_HELP                   ; Emit CALL RT_FREE.
    CALL EM_OP                     ; Recover the outcome.
    DB   $F1                       ; POP AF: restore the callee's outcome.

;@ROUTINE OUT A,CARRY,ZERO CLOBBERS SIGN,PARITY,HALFCARRY,BC,DE,HL,IX,IY
; Emit JR NC around the failure path of a failable call, the path itself
; (RG_ONERR) and then RG_AFTER. RG_SERVE enters here for every service.

RG_FORK:
    CALL EM_JRNC                   ; Success skips the failure path.
    LD   (EM_XFIX),DE              ; Keep the branch operand.
    CALL RG_ONERR                  ; Emit the path the handling mode selects.
.JOIN:                         ; Success continues here.
    LD   DE,(EM_XFIX)              ; Recover the branch operand.
    CALL EM_LAND                   ; Land the success branch here.

;@ROUTINE OUT A,CARRY,ZERO CLOBBERS SIGN,PARITY,HALFCARRY,BC,DE,HL
; Emit the call's epilogue: POP DE for each argument carrier, then PUSH HL
; for a kept routine result, or LD L,A / LD H,0 / PUSH HL for a service's.

RG_AFTER:
    LD   A,(RO_ACNT)               ; The caller removes its arguments.
    LD   C,A                       ; RG_DROP pops C carriers.
    CALL RG_DROP                   ; Emit the pops.
    LD   A,(RO_DTYPE)              ; Does the call produce a result?
    OR   A                         ; Zero means none.
    RET  Z                         ; Nothing to keep.
    LD   A,(RO_DEST)               ; Is the result wanted?
    AND  RO_FKEEP                  ; A statement call discards it.
    RET  Z                         ; Leave it unpushed.
    LD   A,(RO_DEST)               ; Where does the result arrive?
    AND  RO_FIO                    ; A service returns it in A.
    JR   NZ,.SERVICE               ; Widen A into a carrier.
    CALL EM_ENDOP                  ; A routine returns it in HL.
    DB   $E5                       ; PUSH HL: keep the routine's result.
.SERVICE:                      ; Push a service's u8 result.
    LD   HL,GT_ATOHL               ; LD L,A / LD H,0 / PUSH HL.
    JP   EM_FOUR                   ; Emit it and return.

;@ROUTINE IN C OUT A,C,CARRY,ZERO CLOBBERS SIGN,PARITY,HALFCARRY,B,DE,HL
; Emit POP DE C times, discarding C evaluation-stack carriers.

RG_DROP:
    LD   A,C                       ; Test the remaining count.
    OR   A                         ; Is anything left to discard?
    RET  Z                         ; Return with C zero.
.DISCARD:                      ; Discard one carrier.
    CALL EM_OP                     ; DE is free at every statement edge.
    DB   $D1                       ; POP DE: discard one carrier.
    DEC  C                         ; One carrier fewer.
    JR   RG_DROP                   ; Continue until C is zero.

RG_RET EQU  GX_RET                 ; OP_RETA: POP HL, leave the frame, RET.

;@ROUTINE OUT A,CARRY,ZERO CLOBBERS SIGN,PARITY,HALFCARRY,BC,DE,HL
; OP_FAIL: offset. Fail the routine with the u8 code on the evaluation
; stack: record the offset in RT_TPOS, POP HL / LD A,L, leave, SCF / RET.
; Failure is carry set with the code in A; source code cannot inspect it.

RG_FAIL:
    CALL RG_NOTE                   ; Read the fail statement's offset.
    CALL RG_MARK                   ; Record it as the propagation site.
    CALL EM_IDIOM                  ; Move the error code into A.
    DB   EP_POPA                   ; POP HL / LD A,L.
    JR   RG_BAIL                   ; Leave the frame with carry set.

;@ROUTINE OUT A,CARRY,ZERO CLOBBERS SIGN,PARITY,HALFCARRY,BC,DE,HL
; OP_ABORT: offset. Stop the program with the code on the evaluation stack
; as an unhandled error (trap 6) at the offset. The grammar has no abort
; statement, so the parser never writes OP_ABORT and this is unreached.

RG_FATAL:
    CALL RG_NOTE                   ; Read the statement's offset.
    CALL EM_IDIOM                  ; Move the error code into A.
    DB   EP_POPA                   ; POP HL / LD A,L.
    LD   HL,(RO_DPOS)              ; The trap reports this offset.
    CALL EM_LDHL                   ; Emit LD HL,offset.
    CALL EM_STRAY                  ; Store the error and select trap 6.
    JP   GX_ABORT                  ; Unwind to the root frame and stop.

;@ROUTINE OUT A,CARRY,ZERO CLOBBERS SIGN,PARITY,HALFCARRY,BC,DE,HL
; OP_RETF and OP_RETAF: return the carrier on the evaluation stack from a
; failable routine: POP HL, leave the frame, OR A / RET for success.

RG_RETOK:
    CALL GX_POP                    ; Emit POP HL: the result into HL.
    JR   RG_PASS                   ; Leave with carry clear.

;@ROUTINE OUT A,CARRY,ZERO CLOBBERS SIGN,PARITY,HALFCARRY,BC,DE,HL
; OP_ENDF: result type. A result-free failable routine succeeds at its end;
; a routine with a result cannot reach its end, so it gets no code.

RG_ENDOK:
    CALL EM_READB                  ; Read the routine's result type.
    OR   A                         ; Does it return a value?
    RET  NZ                        ; Its end is unreachable.

;@ROUTINE OUT A,CARRY,ZERO CLOBBERS SIGN,PARITY,HALFCARRY,BC,DE,HL
; Emit LD SP,IX / POP IX / OR A / RET: leave the frame reporting success.

RG_PASS:
    CALL EM_LEAVE                  ; Emit LD SP,IX / POP IX.
    LD   HL,GT_PASS                ; OR A / RET.
    JP   EM_PAIR                   ; Emit it and return.

;@ROUTINE OUT A,CARRY,ZERO CLOBBERS SIGN,PARITY,HALFCARRY,BC,DE,HL
; OP_HSKIP: label. Emit JP label, taking the success path past a handler.

RG_SKIP:
    CALL EM_READB                  ; Read the label after the handler.
    LD   C,A                       ; GC_OPREF refers to label C.
    LD   A,$C3                     ; JP nn.
    JP   GC_OPREF                  ; Emit it with a fixup and return.

;@ROUTINE OUT A,CARRY,ZERO CLOBBERS SIGN,PARITY,HALFCARRY,BC,DE,HL,IX,IY
; OP_HOPEN: handler label, then the u8 variable's class and its address or
; slot. Place the label RG_THROW jumps to with the code in A, then store the
; code: LD L,A / LD H,0 / PUSH HL and the variable's store.

RG_CATCH:
    CALL EM_READB                  ; Read the handler's label.
    LD   C,A                       ; GC_PLACE defines label C.
    CALL GC_PLACE                  ; The failure path jumps here.
    CALL EM_READB                  ; Read the error variable's class.
    LD   (RG_FLAGS),A              ; Keep it to choose the store.
    LD   HL,GT_ATOHL               ; LD L,A / LD H,0 / PUSH HL.
    CALL EM_FOUR                   ; Push the error code as a carrier.
    LD   A,(RG_FLAGS)              ; Recover the class.
    AND  SY_CMASK                  ; Keep the storage class.
    CP   SY_GLOB                   ; Is the variable a program variable?
    JP   Z,GX_ST8                  ; Store through its absolute address.
    JP   GX_STX8                   ; Otherwise store into its frame slot.

;@ROUTINE OUT A,CARRY,ZERO CLOBBERS SIGN,PARITY,HALFCARRY,BC,DE,HL
; OP_HDONE: label. Place the label that ends a handler.

RG_JOIN:
    CALL EM_READB                  ; Read the label.
    LD   C,A                       ; GC_PLACE defines label C.
    JP   GC_PLACE                  ; Place it here and return.

;@ROUTINE OUT A,CARRY,ZERO CLOBBERS SIGN,PARITY,HALFCARRY,BC,DE,HL
; Emit the failure path of a failable call by its handling mode. RO_MTRAP
; jumps to the statement's handler; RO_MPASS records the site and fails
; the routine in turn. Mode zero means the parser left it unhandled.

RG_ONERR:
    LD   A,(RG_MODE)               ; Read the call's handling mode.
    OR   A                         ; RO_MSAFE: no handling was attached.
    JP   Z,GX_BADOP                ; The parser forbids that.
    CP   RO_MTRAP                  ; Is there a handler?
    JR   Z,RG_THROW                ; Jump to it.
    CALL RG_MARK                   ; Record this call as the propagation site.

;@ROUTINE OUT A,CARRY,ZERO CLOBBERS SIGN,PARITY,HALFCARRY,BC,DE,HL
; Emit LD SP,IX / POP IX / SCF / RET: fail the routine, code in A.

RG_BAIL:
    CALL EM_LEAVE                  ; Emit LD SP,IX / POP IX.
    LD   HL,GT_BAIL                ; SCF / RET.
    JP   EM_PAIR                   ; Emit it and return.

;@ROUTINE OUT A,CARRY,ZERO CLOBBERS SIGN,PARITY,HALFCARRY,BC,DE,HL
; Emit the jump to a handler: save the code in C, pop the call's argument
; carriers and the statement's kept carriers, restore A and JP the handler.

RG_THROW:
    CALL EM_OP                     ; POP DE leaves C intact.
    DB   $4F                       ; LD C,A: keep the error code in C.
    LD   A,(RO_ACNT)               ; The call's argument carriers.
    LD   HL,RG_KEPT                ; Plus the statement's kept carriers.
    ADD  A,(HL)                    ; Give the words above the statement's base.
    LD   C,A                       ; RG_DROP pops C carriers.
    CALL RG_DROP                   ; Emit the pops.
    CALL EM_OP                     ; Restore the code for the handler.
    DB   $79                       ; LD A,C: the handler takes the code in A.
    LD   A,(RG_HDEST)              ; The handler's label.
    LD   C,A                       ; GC_OPREF refers to label C.
    LD   A,$C3                     ; JP nn.
    JP   GC_OPREF                  ; Emit it with a fixup and return.

;@ROUTINE OUT A,CARRY,ZERO CLOBBERS SIGN,PARITY,HALFCARRY,BC,DE,HL,IX,IY
; Emit a service call: move its argument, if any, from the evaluation stack
; to A (u8) or HL (u16), CALL the service's RAM vector and fork on failure.
; Every service is failable; its argument is consumed, so none is dropped.

RG_SERVE:
    LD   A,(RO_DEST)               ; The selector holds the signature.
    AND  RO_AMASK                  ; Keep the argument type, bits 3..4.
    JR   Z,.VECTOR                 ; No argument to move.
    CP   RO_ARG16                  ; Is the argument a u16?
    JR   Z,.WORD                   ; It travels in HL.
    CALL EM_IDIOM                  ; A u8 argument travels in A.
    DB   EP_POPA                   ; POP HL / LD A,L.
    JR   .VECTOR                   ; Then call the service.
.WORD:                         ; Move a u16 argument to HL.
    CALL GX_POP                    ; Emit POP HL: the seek offset into HL.
.VECTOR:                       ; Call the service.
    LD   A,(RO_DEST)               ; Recover the selector.
    AND  RO_SMASK                  ; Service n is RAM vector n.
    CALL EM_CALLV                  ; Emit CALL through the vector.
    XOR  A                         ; No argument carrier remains.
.NOARG:                        ; Record that nothing is left to drop.
    LD   (RO_ACNT),A               ; RG_AFTER and RG_THROW drop none.
    JP   RG_FORK                   ; Branch on the service's outcome.

;@ROUTINE OUT A,CARRY,ZERO CLOBBERS SIGN,PARITY,HALFCARRY,BC,DE,HL,IX,IY
; OP_ENTRY: main's flags and bank. Patch the entry jump to here, save the
; root SP and IX, CALL main's body (label RO_MDEST) and stop the program:
; success, or for a failable main an unhandled error (trap 6) reported at
; RT_TPOS. Then open main's body, which has the same frame and failure ABI
; as any result-free routine.

RG_MAIN:
    CALL EM_READB                  ; Read main's flags.
    LD   (RG_FLAGS),A              ; Keep them for the failable test.
    CALL EM_READB                  ; Read main's bank.
    CALL TG_PICK                   ; Direct the wrapper to that bank.
    CALL GX_START                  ; Patch the entry jump; save SP and IX.
    LD   C,RO_MDEST                ; Main's body is label RO_MDEST.
    LD   A,$CD                     ; CALL nn.
    CALL GC_OPREF                  ; Call the body as any routine is called.
    LD   A,(RG_FLAGS)              ; Can main fail?
    AND  RO_FFAIL                  ; Test its failable flag.
    JR   Z,.PASS                   ; Then the body always returns success.
    CALL EM_JRNC                   ; Success skips the unhandled-error stop.
    LD   (EM_XFIX),DE              ; Keep the branch operand.
    CALL EM_OP                     ; Keep the error code in A.
    DB   $F5                       ; PUSH AF: keep the error code.
    LD   DE,RT_TPOS-RT_BASE        ; The latest propagation site.
    CALL TG_VAR                    ; HL is its address in the target.
    LD   A,$2A                     ; LD HL,(nn).
    CALL EM_OPW                    ; The trap reports that offset.
    LD   A,$F1                     ; POP AF.
    CALL EM_BYTE                   ; Recover the error code.
    CALL EM_STRAY                  ; Store the error and select trap 6.
    CALL GX_ABORT                  ; Unwind to the root frame and stop.
    LD   DE,(EM_XFIX)              ; Recover the branch operand.
    CALL EM_LAND                   ; Success lands here.
.PASS:                         ; Stop the program successfully.
    CALL GX_RESET                  ; Restore the root SP and IX.
    CALL EM_DONE                   ; Set RT_OK and jump to the terminal code.
    LD   C,RO_MDEST                ; Main's body follows.
    JP   RG_FRAME                  ; Place its label and emit its prologue.

;@ROUTINE OUT A,CARRY,ZERO CLOBBERS SIGN,PARITY,HALFCARRY,BC,DE,HL
; OP_ENDP: result type. A result-free routine that cannot fail returns at
; its end: LD SP,IX / POP IX / RET. One with a result cannot reach its end.

RG_CLOSE:
    CALL EM_READB                  ; Read the routine's result type.
    OR   A                         ; Does it return a value?
    RET  NZ                        ; Its end is unreachable.
    CALL EM_LEAVE                  ; Emit LD SP,IX / POP IX.
    CALL EM_ENDOP                  ; Emit RET and return.
    DB   $C9                       ; RET.

;@ROUTINE OUT A,CARRY,ZERO CLOBBERS SIGN,PARITY,HALFCARRY,BC,DE,HL,IX,IY
; OP_REFG: data offset. Push the program variable's address: LD HL,nn /
; PUSH HL.

RG_GLOB:
    CALL EM_READA                  ; HL is the variable's absolute address.
    JR   RG_REF                    ; Push it as a constant.

;@ROUTINE OUT A,CARRY,ZERO CLOBBERS SIGN,PARITY,HALFCARRY,BC,DE,HL,IX,IY
; OP_REFRO: constant-region offset. Push the aggregate constant's address.

RG_CONST:
    CALL EM_READW                  ; DE is the offset in the constant region.
    LD   HL,(TG_ROPOS)             ; The region's run address.
    ADD  HL,DE                     ; HL is the constant's address.

;@ROUTINE IN HL OUT A,CARRY,ZERO CLOBBERS SIGN,PARITY,HALFCARRY,BC,DE,HL
; Emit LD HL,address / PUSH HL.

RG_REF:
    LD   A,$21                     ; LD HL,nn.
    JP   GX_FETCH                  ; Emit it with PUSH HL and return.

RG_PARAM EQU  GX_LDX16             ; OP_REFP: push the slot's address word.

;@ROUTINE OUT A,CARRY,ZERO CLOBBERS SIGN,PARITY,HALFCARRY,BC,DE,HL
; OP_FIELD: field offset. Emit POP HL / LD DE,offset / ADD HL,DE /
; PUSH HL, moving the carried record address to the field.

RG_FIELD:
    CALL EM_READW                  ; Read the field's offset.
    LD   (RO_OPOS),DE              ; EM_IDIOM clobbers DE.
    CALL EM_IDIOM                  ; Take the record address.
    DB   EP_FIELD                  ; POP HL / LD DE,nn.
    LD   HL,(RO_OPOS)              ; The offset is the LD DE operand.
    CALL EM_WORD                   ; Complete the LD DE.
    LD   HL,GT_ADDDE               ; ADD HL,DE / PUSH HL.
    JP   EM_PAIR                   ; Emit it and return.

;@ROUTINE OUT A,CARRY,ZERO CLOBBERS SIGN,PARITY,HALFCARRY,BC,DE,HL
; OP_INDEX: length, stride, offset. Pop the index and array address, check
; the index against the length (trap 1) and push address + index * stride.

RG_INDEX:
    CALL EM_READW                  ; Read the array's element count.
    LD   (RO_OPOS),DE              ; Keep the count for LD BC.
    CALL RG_SPAN                   ; Read the stride and the offset.
    CALL EM_IDIOM                  ; DE is the index, HL the array.
    DB   EP_ARGS                   ; POP DE / POP HL.
    LD   HL,(RO_OPOS)              ; The element count.
    CALL EM_LDBC                   ; Emit LD BC,count.
    LD   DE,RT_IDXOK               ; Carry if DE is not below BC.
    CALL EM_HELP                   ; Emit CALL RT_IDXOK.
    CALL RG_GUARD                  ; Trap an index out of range.
    CALL EM_OP                     ; Keep the array address.
    DB   $E5                       ; PUSH HL: keep the array address.
    LD   HL,(RO_OSIZE)             ; The element size.
    LD   A,$21                     ; LD HL,nn: the stride.
    CALL EM_OPW                    ; Emit it.
    LD   DE,RT_MUL16               ; HL = index * stride.
    CALL EM_HELP                   ; Emit CALL RT_MUL16.
    LD   HL,GT_INDEX               ; POP DE / ADD HL,DE / PUSH HL.
    JP   EM_THREE                  ; Push the element's address and return.

;@ROUTINE OUT A,CARRY,ZERO CLOBBERS SIGN,PARITY,HALFCARRY,BC,DE,HL
; OP_LDX8: POP HL / LD A,(HL) / LD L,A / LD H,0 / PUSH HL. GT_GETA's two
; bytes run on into GT_ATOHL, so GENTMPL must keep the two adjacent.

RG_GET8:
    LD   HL,GT_GETA                ; POP HL / LD A,(HL), then GT_ATOHL.
    LD   B,6                       ; Both templates together.
    JP   EM_BYTES                  ; Emit them and return.

;@ROUTINE OUT A,CARRY,ZERO CLOBBERS SIGN,PARITY,HALFCARRY,BC,DE,HL
; OP_LDX16: POP HL / LD E,(HL) / INC HL / LD D,(HL) / PUSH DE.

RG_GET16:
    LD   HL,GT_GET16               ; Load the word through the address.
    JP   EM_FIVE                   ; Emit it and return.

;@ROUTINE OUT A,CARRY,ZERO CLOBBERS SIGN,PARITY,HALFCARRY,BC,DE,HL
; OP_STX8: POP DE / POP HL / LD (HL),E: store the value through the address
; beneath it.

RG_PUT8:
    LD   HL,GT_PUT8                ; The first three bytes of GT_PUT16.
    JP   EM_THREE                  ; Emit them and return.

;@ROUTINE OUT A,CARRY,ZERO CLOBBERS SIGN,PARITY,HALFCARRY,BC,DE,HL
; OP_STX16: POP DE / POP HL / LD (HL),E / INC HL / LD (HL),D.

RG_PUT16:
    LD   HL,GT_PUT16               ; Store the word through the address.
    JP   EM_FIVE                   ; Emit it and return.

;@ROUTINE OUT A,CARRY,ZERO CLOBBERS SIGN,PARITY,HALFCARRY,BC,DE,HL,IX,IY
; OP_COPY: size, offset. With the destination beneath the source, check
; that each whole region is program data or constants (trap 1), then
; POP HL / POP DE / LD BC,size / LDIR. Both checks complete before LDIR,
; so a failed check leaves the destination untouched.

RG_COPY:
    CALL RG_SPAN                   ; Read the size and the offset.
    LD   HL,GT_ARGS                ; POP DE / POP HL / PUSH HL / PUSH DE.
    CALL EM_FOUR                   ; HL is the destination; both stay pushed.
    CALL RG_FIT                    ; Check the destination region.
    CALL RG_HOLD                   ; Check the source region.
    CALL EM_IDIOM                  ; HL is the source, DE the destination.
    DB   EP_ARGSX                  ; POP HL / POP DE.
    LD   HL,(RO_OSIZE)             ; The aggregate's size.
    CALL EM_LDBC                   ; Emit LD BC,size.
    LD   HL,GT_BLOCK               ; LDIR.
    JP   EM_PAIR                   ; Emit the copy and return.

;@ROUTINE OUT A,DE,HL,CARRY,ZERO CLOBBERS SIGN,PARITY,HALFCARRY
; Read a size word into RO_OSIZE, then the offset word into RO_DPOS.

RG_SPAN:
    CALL EM_READW                  ; Read the size or stride.
    LD   (RO_OSIZE),DE             ; Keep it for LD BC or LD HL.
    JP   RG_NOTE                   ; Read the offset and return.

;@ROUTINE OUT A,CARRY,ZERO CLOBBERS SIGN,PARITY,HALFCARRY,BC,DE,HL
; Emit POP HL / PUSH HL and fall into RG_FIT: check the region of the
; address on top of the evaluation stack, keeping it there.

RG_HOLD:
    CALL GX_POP                    ; Emit POP HL: the address on top.
    CALL EM_OP                     ; Keep it for after the check.
    DB   $E5                       ; PUSH HL: keep it for after the check.

;@ROUTINE OUT A,CARRY,ZERO CLOBBERS SIGN,PARITY,HALFCARRY,BC,DE,HL
; Check that the RO_OSIZE bytes at HL lie wholly in program data or in the
; constant region: RG_FENCE, LD BC,size, then RG_DOFIT.

RG_FIT:
    CALL RG_FENCE                  ; Pass the constant region in DE and IY.
    LD   HL,(RO_OSIZE)             ; The region's length.
    CALL EM_LDBC                   ; Emit LD BC,length.
    JR   RG_DOFIT                  ; Call the check and guard it.

;@ROUTINE OUT A,CARRY,ZERO CLOBBERS SIGN,PARITY,HALFCARRY,BC,DE,HL
; Emit LD DE,base / LD IY,capacity for the constant region, the second
; region RT_RNGOK accepts after program data.

RG_FENCE:
    LD   DE,(TG_ROPOS)             ; The constant region's run address.
    CALL EM_LDDE                   ; Emit LD DE,base.
    LD   HL,(TG_ROCAP)             ; The constant region's length.
    PUSH HL                        ; EM_BYTE clobbers HL.
    LD   A,$FD                     ; The IY prefix.
    CALL EM_BYTE                   ; Emit it.
    POP  HL                        ; Recover the length.
    LD   A,$21                     ; LD IY,nn after the prefix.
    CALL EM_OPW                    ; Emit it.
    RET                            ; The region bounds are loaded.

;@ROUTINE OUT A,CARRY,ZERO CLOBBERS SIGN,PARITY,HALFCARRY,BC,DE,HL
; Emit CALL RT_RNGOK and its bounds trap.

RG_DOFIT:
    LD   DE,RT_RNGOK               ; Carry if the region is out of bounds.
    CALL EM_HELP                   ; Emit CALL RT_RNGOK.
    JP   RG_GUARD                  ; Trap a failed check and return.

;@ROUTINE OUT A,DE,CARRY,ZERO CLOBBERS SIGN,PARITY,HALFCARRY,HL
; Read a string operation's operands: the capacity into RO_ACNT, with the
; string's whole size, capacity + 2, in RO_OSIZE, then the offset.

RG_STROP:
    CALL EM_READB                  ; Read the declared capacity.
    LD   (RO_ACNT),A               ; RG_CHECK loads it into C.
    LD   L,A                       ; Form the capacity as a word.
    LD   H,0                       ; It is at most 255.
    INC  HL                        ; Add the string's first representation byte.
    INC  HL                        ; And its second.
    LD   (RO_OSIZE),HL             ; The region RG_FIT checks.
    JP   RG_NOTE                   ; Read the offset and return.

;@ROUTINE OUT A,CARRY,ZERO CLOBBERS SIGN,PARITY,HALFCARRY,BC,DE,HL
; OP_LEN: capacity, offset. Check the string's region, then replace its
; address with its length: LD C,capacity / CALL RT_LENOK / trap / PUSH HL.

RG_LEN:
    CALL RG_STROP                  ; Read the capacity and the offset.
    CALL RG_HOLD                   ; Check the string's whole region.
    CALL GX_POP                    ; Emit POP HL: the string's address.
    LD   DE,RT_LENOK               ; HL becomes the checked length.
    JP   RG_CHECK                  ; Call it, guard it and push the result.

;@ROUTINE OUT A,CARRY,ZERO CLOBBERS SIGN,PARITY,HALFCARRY,BC,DE,HL
; OP_CHAR: capacity, offset. With the index above the string address,
; check the string's region and push the address of the indexed byte:
; LD C,capacity / CALL RT_CHROK / trap / PUSH HL.

RG_CHAR:
    CALL RG_STROP                  ; Read the capacity and the offset.
    CALL RG_SWAP                   ; Put the string on top; HL is the string.
    CALL RG_FIT                    ; Check the string's whole region.
    CALL EM_IDIOM                  ; HL is the string, DE the index.
    DB   EP_ARGSX                  ; POP HL / POP DE.
    LD   DE,RT_CHROK               ; HL becomes the byte's address.
    JP   RG_CHECK                  ; Call it, guard it and push the result.

;@ROUTINE OUT A,CARRY,ZERO CLOBBERS SIGN,PARITY,HALFCARRY,BC,DE,HL
; Emit POP DE / POP HL / PUSH DE / PUSH HL: put the string address above
; its index, leaving it in HL for the region check.

RG_SWAP:
    CALL EM_IDIOM                  ; DE is the index, HL the string.
    DB   EP_ARGS                   ; POP DE / POP HL.
    LD   HL,GT_SWAP                ; PUSH DE / PUSH HL.
    JP   EM_PAIR                   ; Emit it and return.

;@ROUTINE OUT A,DE,CARRY,ZERO CLOBBERS SIGN,PARITY,HALFCARRY,HL
; Read an open-string operation's operands: the frame slot of the hidden
; capacity byte into RO_ACNT, then the offset. The caller supplies the
; capacity; the address carrier is the ordinary parameter word.

OS_READ:
    CALL EM_READB                  ; Read the capacity byte's slot.
    LD   (RO_ACNT),A               ; OS_CAP addresses it.
    JP   RG_NOTE                   ; Read the offset and return.

;@ROUTINE OUT A,CARRY,ZERO CLOBBERS SIGN,PARITY,HALFCARRY,BC,DE,HL
; OP_VLEN: slot, offset. RG_LEN with the capacity taken from the frame.

OS_LEN:
    CALL OS_READ                   ; Read the slot and the offset.
    CALL GX_POP                    ; POP HL: the string's address.
    CALL EM_OP                     ; Keep it across the region check.
    DB   $E5                       ; PUSH HL: keep it across the check.
    CALL OS_FIT                    ; Check the string's whole region.
    CALL GX_POP                    ; POP HL: the string again.
    LD   DE,RT_LENOK               ; HL becomes the checked length.
    JR   OS_CHECK                  ; Call it, guard it and push the result.

;@ROUTINE OUT A,CARRY,ZERO CLOBBERS SIGN,PARITY,HALFCARRY,BC,DE,HL
; OP_VCHAR: slot, offset. RG_CHAR with the capacity taken from the frame.

OS_CHAR:
    CALL OS_READ                   ; Read the slot and the offset.
    CALL RG_SWAP                   ; Put the string on top; HL is the string.
    CALL OS_FIT                    ; Check the string's whole region.
    CALL EM_IDIOM                  ; HL is the string, DE the index.
    DB   EP_ARGSX                  ; POP HL / POP DE.
    LD   DE,RT_CHROK               ; HL becomes the byte's address.

;@ROUTINE IN DE OUT A,CARRY,ZERO CLOBBERS SIGN,PARITY,HALFCARRY,BC,DE,HL
; Emit LD C,(IX+capacity) and the checked call of helper DE (RG_PROVE).

OS_CHECK:
    PUSH DE                        ; OS_CAP clobbers the helper offset.
    CALL OS_CAP                    ; Emit LD C,(IX+capacity).
    POP  DE                        ; Recover the helper offset.
    JR   RG_PROVE                  ; Call it, guard it and push the result.

;@ROUTINE IN DE OUT A,CARRY,ZERO CLOBBERS SIGN,PARITY,HALFCARRY,BC,DE,HL
; Emit CALL helper DE, its bounds trap and PUSH HL.

RG_PROVE:
    CALL EM_HELP                   ; Emit CALL helper.
    CALL RG_GUARD                  ; Trap a failed check.
    CALL EM_ENDOP                  ; Emit the push and return.
    DB   $E5                       ; PUSH HL: the length or the byte's address.

;@ROUTINE OUT A,CARRY,ZERO CLOBBERS SIGN,PARITY,HALFCARRY,BC,DE,HL
; Check an open string's whole region before it is touched: RG_FENCE, then
; BC = the caller's capacity + 2 representation bytes, then RG_DOFIT.

OS_FIT:
    CALL RG_FENCE                  ; Pass the constant region in DE and IY.
    CALL OS_CAP                    ; Emit LD C,(IX+capacity).
    LD   HL,GT_PLUS2               ; LD B,0 / INC BC / INC BC.
    CALL EM_FOUR                   ; BC is the string's whole size.
    JP   RG_DOFIT                  ; Call the check and guard it.

;@ROUTINE OUT A,CARRY,ZERO CLOBBERS SIGN,PARITY,HALFCARRY,BC,DE,HL
; Emit LD C,(IX+d) for the hidden capacity byte in slot RO_ACNT.

OS_CAP:
    LD   HL,GT_LDCIX               ; LD C,(IX+d).
    JR   OS_CAPIX                  ; Complete it with the slot's displacement.

;@ROUTINE IN HL OUT A,CARRY,ZERO CLOBBERS SIGN,PARITY,HALFCARRY,BC,DE,HL
; Emit the IX-indexed opcode pair at HL for the byte in slot RO_ACNT.

OS_CAPIX:
    CALL EM_PAIR                   ; Emit the prefix and the opcode.
    LD   A,(RO_ACNT)               ; The slot of the capacity byte.
    CPL                            ; Its displacement is -(slot+1).
    JP   EM_BYTE                   ; Complete the instruction.

;@ROUTINE OUT A,CARRY,ZERO CLOBBERS SIGN,PARITY,HALFCARRY,BC,DE,HL,IX,IY
; OP_VIEW: mode, value. Turn the string address on the evaluation stack
; into an open-string argument: the capacity beneath the address. Mode
; zero gives a declared capacity; mode one forwards the capacity byte of
; an open-string parameter from slot value.

OS_ARG:
    CALL EM_READB                  ; Read the mode.
    LD   (RO_AIDX),A               ; Keep it for the branch below.
    CALL EM_READB                  ; Read the capacity or the slot.
    LD   (RO_ACNT),A               ; OS_CAPIX reads a slot from here.
    CALL EM_OP                     ; Take the address off the stack.
    DB   $D1                       ; POP DE: the string's address.
    LD   A,(RO_AIDX)               ; Recover the mode.
    OR   A                         ; Is the capacity a constant?
    JR   NZ,.FORWARD               ; Mode one copies it from the frame.
    LD   A,(RO_ACNT)               ; The declared capacity.
    LD   L,A                       ; Form it as a word.
    LD   H,0                       ; A capacity is at most 255.
    CALL EM_LDHL                   ; Emit LD HL,capacity.
    JR   .PAIR                     ; Push both words.
.FORWARD:                      ; Forward the caller's own capacity.
    LD   HL,GT_LDLO                ; LD L,(IX+d).
    CALL OS_CAPIX                  ; Load the hidden capacity byte.
    CALL EM_IDIOM                  ; Widen it to a word.
    DB   EP_ZEROH                  ; LD H,0.
.PAIR:                         ; Push capacity, then address.
    LD   HL,GT_ARGS+2              ; PUSH HL / PUSH DE.
    JP   EM_PAIR                   ; Emit it and return.

;@ROUTINE IN DE OUT A,CARRY,ZERO CLOBBERS SIGN,PARITY,HALFCARRY,BC,DE,HL
; Emit LD C,capacity from RO_ACNT and the checked call of helper DE.

RG_CHECK:
    PUSH DE                        ; EM_OPB clobbers the helper offset.
    LD   A,(RO_ACNT)               ; The declared capacity.
    LD   C,A                       ; It is the immediate operand.
    LD   A,$0E                     ; LD C,n: the declared capacity.
    CALL EM_OPB                    ; Emit it.
    POP  DE                        ; Recover the helper offset.
    JR   RG_PROVE                  ; Call it, guard it and push the result.

; Code templates. GT_ADDA's first three bytes and the byte before it are
; referenced by nothing: only GT_ADDA+3 is used (GT_ADDDE, GT_ADD16).

    DB   $06                       ; Unreferenced: an LD B,n opcode.
GT_ADDA: DB   $5F,$16,$00,$19,$E5  ; LD E,A / LD D,0 / ADD HL,DE / PUSH HL.

GT_GET16: DB   $E1,$5E,$23,$56,$D5 ; POP HL / LD E,(HL) / INC HL / LD D,(HL) / PUSH DE.
GT_PUT16: DB   $D1,$E1,$73,$23,$72 ; POP DE / POP HL / LD (HL),E / INC HL / LD (HL),D.

GT_INDEX: DB   $D1,$19,$E5         ; POP DE / ADD HL,DE / PUSH HL.
GT_SWAP: DB   $D5,$E5              ; PUSH DE / PUSH HL.

GT_LDCIX: DB   $DD,$4E             ; LD C,(IX+d), displacement emitted after.

GT_PLUS2: DB   $06,$00,$03,$03     ; LD B,0 / INC BC / INC BC.
GT_BLOCK EQU  GT_LDIR              ; LDIR.

GT_ADDDE EQU  GT_ADDA+3            ; ADD HL,DE / PUSH HL.

GT_PUT8 EQU  GT_PUT16              ; POP DE / POP HL / LD (HL),E.
GT_BAIL: DB   $37,$C9              ; SCF / RET.
GT_PASS: DB   $B7,$C9              ; OR A / RET.
