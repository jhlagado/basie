;==========================================================================
;  Control code generation
;==========================================================================
;
;  Lower the transcript's control operations to Z80 code: labels, jumps,
;  conditional jumps and the counted loop. The control parser numbers the
;  labels (CT_ALLOT). When GX_WALK replays OP_LABEL, the label's output
;  address is recorded. A jump is emitted with a zero absolute operand and
;  the operand is recorded in the fixup table, because most targets are
;  still ahead. GC_PATCH fills every recorded operand once the whole
;  transcript has been replayed, before the target is closed. GENEXPR's
;  routine entry and GENCALL's calls and returns use the same labels.
;
;  Principal entries, from GX_WALK's dispatch table:
;    GC_LABEL  OP_LABEL: the label is here
;    GC_IFNOT  OP_IFNOT: pop a condition, jump to the label when false
;    GC_JUMP   OP_JUMP: jump to the label
;    GC_FOR    OP_FOR: set the counter, keep the bound on the stack
;    GC_TEST   OP_TEST: leave the loop when the counter is past the bound
;    GC_NEXT   OP_NEXT: leave if one more step overshoots, else step and
;              jump back to the test
;    GC_DROP   OP_CLEAN: discard the bound at the loop's exit
;  and for the other generators:
;    GC_PLACE  record label C at the current output address
;    GC_OPREF  emit opcode A with an absolute operand for label C
;              (GC_OPFAR: the label may be in another bank)
;    GC_PATCH  write every label address into its recorded operands
;    EM_LDDE   emit LD DE,nn
;
;  Tables (STATE.ASM, in workspace the control parser no longer needs):
;    GC_VALID  GC_LCAP (32) bytes, one per label: zero until the label is
;              placed, then its output bank plus one
;    GC_LADDR  GC_LCAP words: each placed label's output address
;    GC_FTAB   GC_FCAP (32) records of GC_FLEN (3) bytes: a flags byte
;              (bit 7 far, bits 5..6 the operand's bank, bits 0..4 the
;              label), then the operand's address; GC_FCNT counts them
;
;  A counted loop is replayed as
;    OP_FOR   counter,mode
;    OP_LABEL top
;    OP_TEST  counter,mode,exit
;    ...      the body
;    OP_LABEL continue
;    OP_NEXT  top,exit,counter,mode,step,source offset
;    OP_LABEL exit
;    OP_CLEAN
;  The counter is a local, given by its byte offset n in the frame; its
;  low byte is at (IX-n-1) and a u16 counter's high byte at (IX-n-2). In
;  the mode byte, bit 0 is set for an inclusive bound (to) and clear for
;  an exclusive one (until), bit 1 is set for a downward step and bit 2
;  for a u16 counter. The step is a nonzero magnitude. The bound stays on
;  the machine stack from OP_FOR to OP_CLEAN. GC_NEXT keeps its operands
;  in the dead emitter scratch words named below.

GC_COUNT EQU  EM_ORG           ; GC_NEXT: the counter's frame offset.
GC_MODE EQU  EM_ORG+1          ; GC_NEXT: the loop's mode byte.
GC_STEP EQU  EM_HEAD           ; GC_NEXT: the step magnitude, a word.
GC_POS EQU  EM_XFIX            ; GC_NEXT: the loop's source offset, for a trap.
GC_TOP EQU  EM_FFIX            ; GC_NEXT: the label of the loop's test.
GC_EXIT EQU  EM_FFIX+1         ; GC_TEST, GC_NEXT: the loop's exit label.

;@ROUTINE IN C,DE OUT CARRY CLOBBERS A,HL,SIGN,PARITY,HALFCARRY,ZERO
; Record the absolute operand at DE for label C, with C's bit 7 set when
; the label may be in another bank. The record keeps the bank receiving
; output in bits 5..6. A full table raises DG_FIXUP.

GC_PEND:                       ; C is the label, DE the operand's address.
    LD   A,C                       ; Take the label ordinal.
    AND  $1F                       ; Drop the far flag, and bits 5..6 with it.
    CP   GC_LCAP                   ; Below 32 after the mask, so this always passes.
    JP   NC,CT_ELABS               ; Never taken; callers keep labels below GC_LCAP.
    LD   A,(GC_FCNT)               ; A counts the recorded operands.
    CP   GC_FCAP                   ; Is the fixup table full?
    JR   NC,.FULL                  ; Then this operand cannot be recorded.
    PUSH BC                        ; Keep the label while BC is the table base.
    LD   L,A                       ; Keep the count for the multiply.
    LD   H,0                       ; The record offset is below 256.
    ADD  A,A                       ; Twice the count.
    ADD  A,L                       ; Three times: one GC_FLEN record each.
    LD   L,A                       ; L is the new record's offset.
    LD   H,0                       ; Form it as a word.
    LD   BC,GC_FTAB                ; Base of the fixup table.
    ADD  HL,BC                     ; HL addresses the new record.
    POP  BC                        ; C is the label again.
    LD   A,(TG_OBANK)              ; Fetch the bank receiving output, 0 to 3.
    RLCA                           ; Move the bank from bits 0..1.
    RLCA                           ; One place per rotation.
    RLCA                           ; Three.
    RLCA                           ; Four.
    RLCA                           ; Five: the bank is in bits 5..6.
    OR   C                         ; Merge the far flag and the label.
    LD   (HL),A                    ; Store the record's flags byte.
    INC  HL                        ; Then the operand's address.
    LD   (HL),E                    ; Its low byte.
    INC  HL                        ; And its high byte.
    LD   (HL),D                    ; The record is complete.
    LD   HL,GC_FCNT                ; Address the count.
    INC  (HL)                      ; Publish the record.
    XOR  A                         ; Report success with carry clear.
    RET                            ; The operand waits for GC_PATCH.
.FULL:                         ; Every fixup record is in use.
    CALL DG_RAISE                  ; Report the capacity limit.
    DB   DG_FIXUP                  ; Diagnostic: too many forward references.

;@ROUTINE IN A,C OUT CARRY CLOBBERS A,C,HL,DE,SIGN,PARITY,HALFCARRY,ZERO
; As GC_OPREF, for a label that may be in another bank: GC_PATCH then
; accepts the label wherever it is placed. Calls to routines use this.

GC_OPFAR:                      ; A is the opcode, C the label.
    SET  7,C                       ; Mark the operand as far.

;@ROUTINE IN A,C OUT CARRY CLOBBERS A,HL,DE,SIGN,PARITY,HALFCARRY,ZERO
; Emit opcode A with a zero word operand and record that operand for
; label C, so that GC_PATCH writes the label's address into it.

GC_OPREF:                      ; A is the opcode, C the label.
    PUSH BC                        ; EM_BYTE clobbers B.
    CALL EM_BYTE                   ; Emit the opcode.
    POP  BC                        ; Recover the label.
    LD   DE,(EM_PTR)               ; DE is where the operand goes.
    PUSH BC                        ; Keep the label across EM_WORD.
    PUSH DE                        ; And the operand's address.
    LD   HL,0                      ; A placeholder until the label is known.
    CALL EM_WORD                   ; Emit the operand.
    POP  DE                        ; Recover the operand's address.
    POP  BC                        ; And the label.
    JR   GC_PEND                   ; Record the operand for GC_PATCH.

;@ROUTINE OUT CARRY CLOBBERS A,BC,DE,HL,SIGN,PARITY,HALFCARRY,ZERO
; OP_LABEL: read the label operand and place it here.

GC_LABEL:                      ; The operand is a label number.
    CALL EM_READB                  ; Read it.
    LD   C,A                       ; GC_PLACE takes the label in C.

;@ROUTINE IN C OUT CARRY CLOBBERS A,BC,DE,HL,SIGN,PARITY,HALFCARRY,ZERO
; Record the current output address and bank as label C's. A label placed
; twice is a compiler fault (GX_BADOP).

GC_PLACE:                      ; C is the label.
    LD   A,C                       ; Take the label ordinal.
    CP   GC_LCAP                   ; Is it a label the tables can hold?
    JP   NC,CT_ELABS               ; No: too many labels.
    LD   B,0                       ; Form the ordinal as a word.
    LD   HL,GC_VALID               ; Base of the placed flags.
    ADD  HL,BC                     ; HL addresses this label's flag.
    LD   A,(HL)                    ; Fetch it.
    OR   A                         ; Has the label been placed already?
    JP   NZ,GX_BADOP               ; A second placement is a compiler fault.
    LD   A,(TG_OBANK)              ; Fetch the bank receiving output.
    INC  A                         ; Bank plus one, so that zero means unplaced.
    LD   (HL),A                    ; Mark the label placed in this bank.
    LD   L,C                       ; Form the label ordinal as a word.
    LD   H,0                       ; For the address table.
    ADD  HL,HL                     ; Two bytes per address.
    LD   BC,GC_LADDR               ; Base of the label addresses.
    ADD  HL,BC                     ; HL addresses this label's entry.
    LD   DE,(EM_PTR)               ; DE is the current output address.
    LD   (HL),E                    ; Store its low byte.
    INC  HL                        ; Then.
    LD   (HL),D                    ; Its high byte.
    XOR  A                         ; Report success with carry clear.
    RET                            ; Jumps to the label now resolve here.

;@ROUTINE OUT CARRY CLOBBERS A,C,DE,HL,SIGN,PARITY,HALFCARRY,ZERO
; OP_IFNOT label: emit code that pops the condition and jumps to the
; label when it is false: POP HL / LD A,L / OR A / JP Z,label.

GC_IFNOT:                      ; The operand is the false branch's label.
    CALL EM_READB                  ; Read it.
    LD   C,A                       ; GC_OPREF takes the label in C.
    PUSH BC                        ; EM_THREE clobbers B.
    LD   HL,GT_ANDIF               ; POP HL / LD A,L / OR A: test the condition.
    CALL EM_THREE                  ; Emit the three bytes.
    POP  BC                        ; Recover the label.
    LD   A,$CA                     ; JP Z,nn: skip the branch when the condition is false.
    JR   GC_OPREF                  ; Emit the jump with its recorded operand.

;@ROUTINE OUT CARRY CLOBBERS A,C,DE,HL,SIGN,PARITY,HALFCARRY,ZERO
; OP_JUMP label: emit JP label.

GC_JUMP:                       ; The operand is the target label.
    CALL EM_READB                  ; Read it.
    LD   C,A                       ; GC_OPREF takes the label in C.
    LD   A,$C3                     ; JP nn.
    JR   GC_OPREF                  ; Emit the jump with its recorded operand.

;@ROUTINE OUT CARRY CLOBBERS A,BC,DE,HL,IX,SIGN,PARITY,HALFCARRY,ZERO
; Write each placed label's address into every operand recorded for it.
; A near operand must be in its label's bank. An unplaced label or a bank
; mismatch is a compiler fault. Ends with no output bank selected.

GC_PATCH:                      ; Every label is now placed.
    CALL TG_SAVE                   ; Save the selected bank's output cursor.
    LD   A,(GC_FCNT)               ; A counts the recorded operands.
    OR   A                         ; Are there any?
    RET  Z                         ; No: nothing to resolve.
    LD   B,A                       ; B counts the records left.
    LD   IX,GC_FTAB                ; IX walks the fixup records.
.NEXT:                         ; IX addresses the next record.
    LD   C,(IX+0)                  ; C is its flags byte.
    LD   A,C                       ; Extract the operand's bank.
    RLCA                           ; Move bits 5..6 round to bits 0..1.
    RLCA                           ; Bit 7, the far flag, moves to bit 2.
    RLCA                           ; Three rotations complete the move.
    AND  $03                       ; A is the operand's bank.
    LD   E,(IX+1)                  ; DE is the operand's address.
    LD   D,(IX+2)                  ; Its high byte.
    PUSH BC                        ; Keep the count and the flags byte.
    PUSH DE                        ; Keep the operand's address.
    LD   E,A                       ; E is the operand's bank.
    LD   D,C                       ; D's bit 7 is the far flag.
    LD   A,C                       ; Extract the label.
    AND  $1F                       ; Bits 0..4.
    LD   C,A                       ; C is the label ordinal.
    LD   A,E                       ; The operand's bank.
    LD   (TG_OBANK),A              ; Direct the patch to that bank.
    LD   A,C                       ; Take the label ordinal.
    LD   B,0                       ; Form it as a word.
    LD   HL,GC_VALID               ; Base of the placed flags.
    ADD  HL,BC                     ; HL addresses this label's flag.
    LD   A,(HL)                    ; Fetch its bank plus one.
    OR   A                         ; Was the label ever placed?
    JR   Z,.UNWIND                 ; No: a compiler fault.
    DEC  A                         ; A is the label's bank.
    BIT  7,D                       ; May the operand reach another bank?
    JR   NZ,.BANKOK                ; Yes: any bank will do.
    CP   E                         ; A near operand must share the label's bank.
    JR   NZ,.UNWIND                ; It does not: a compiler fault.
.BANKOK:                       ; The label is reachable from the operand.
    LD   H,0                       ; Form the label ordinal as a word.
    LD   L,C                       ; For the address table.
    ADD  HL,HL                     ; Two bytes per address.
    LD   BC,GC_LADDR               ; Base of the label addresses.
    ADD  HL,BC                     ; HL addresses this label's entry.
    LD   C,(HL)                    ; Fetch the address's low byte.
    INC  HL                        ; Then.
    LD   H,(HL)                    ; Its high byte.
    LD   L,C                       ; HL is the label's address.
    POP  DE                        ; DE is the operand's address.
    CALL EM_FIXW                   ; Write the address into the operand.
    POP  BC                        ; Recover the count.
    INC  IX                        ; Step to the next record.
    INC  IX                        ; One byte at a time.
    INC  IX                        ; GC_FLEN bytes in all.
    DJNZ .NEXT                     ; Resolve every record.
    LD   A,TG_OFF                  ; No bank is selected now.
    LD   (TG_OBANK),A              ; Close output until the target is finished.
    XOR  A                         ; Report success with carry clear.
    RET                            ; Every operand holds its label's address.
.UNWIND:                       ; Drop the saved record state.
    POP  DE                        ; The operand's address.
    POP  BC                        ; The count and flags.
.BAD:                          ; An operand cannot be resolved.
    JP   GX_BADOP                  ; Report a compiler fault.

;@ROUTINE IN A,C OUT CARRY CLOBBERS A,BC,DE,HL,SIGN,PARITY,HALFCARRY,ZERO
; Emit a load of the counter at frame offset C into HL, leaving the
; expression stack alone: LD L,(IX+d), then LD H,0 or, when bit 2 of the
; mode in A marks a u16 counter, LD H,(IX+d-1).

GC_LOAD:                       ; A is the loop mode, C the counter's offset.
    LD   D,A                       ; Keep the mode.
    LD   A,C                       ; Turn the offset n into a displacement.
    CPL                            ; A = -n-1, the low byte's displacement.
    LD   C,A                       ; C is the displacement from IX.
    PUSH BC                        ; EM_IDIOM keeps C, but not B.
    PUSH DE                        ; And it clobbers DE.
    CALL EM_IDIOM                  ; Emit the inline idiom.
    DB   EP_LDLO                   ; LD L,(IX+d).
    POP  DE                        ; Recover the mode.
    POP  BC                        ; Recover the displacement.
    LD   A,C                       ; The displacement byte follows the opcode.
    PUSH DE                        ; Keep the mode across EM_BYTE.
    CALL EM_BYTE                   ; Emit d.
    POP  DE                        ; Recover the mode.
    BIT  2,D                       ; Is the counter a u16?
    JR   NZ,.UPPER                 ; Then load its high byte too.
    LD   HL,GT_ZEROH               ; LD H,0: a u8 counter widens to a carrier.
    JP   EM_PAIR                   ; Emit it and return.
.UPPER:                        ; A u16 counter's high byte lies below.
    DEC  C                         ; The high byte's displacement is one less.
    PUSH BC                        ; Keep it across EM_IDIOM.
    CALL EM_IDIOM                  ; Emit the inline idiom.
    DB   EP_LDHI                   ; LD H,(IX+d).
    POP  BC                        ; Recover the displacement.
    LD   A,C                       ; It follows the opcode.
    JP   EM_BYTE                   ; Emit d and return.

;@ROUTINE IN A,C OUT CARRY CLOBBERS A,BC,DE,HL,SIGN,PARITY,HALFCARRY,ZERO
; Emit a store of HL to the counter at frame offset C: LD (IX+d),L and,
; when bit 2 of the mode in A marks a u16 counter, LD (IX+d-1),H.

GC_STORE:                      ; A is the loop mode, C the counter's offset.
    LD   D,A                       ; Keep the mode.
    LD   A,C                       ; Turn the offset n into a displacement.
    CPL                            ; A = -n-1, the low byte's displacement.
    LD   C,A                       ; C is the displacement from IX.
    PUSH BC                        ; EM_IDIOM keeps C, but not B.
    PUSH DE                        ; And it clobbers DE.
    CALL EM_IDIOM                  ; Emit the inline idiom.
    DB   EP_STLO                   ; LD (IX+d),L.
    POP  DE                        ; Recover the mode.
    POP  BC                        ; Recover the displacement.
    LD   A,C                       ; The displacement byte follows the opcode.
    PUSH BC                        ; Keep the displacement.
    PUSH DE                        ; And the mode.
    CALL EM_BYTE                   ; Emit d.
    POP  DE                        ; Recover the mode.
    POP  BC                        ; Recover the displacement.
    BIT  2,D                       ; Is the counter a u16?
    RET  Z                         ; No: the low byte is the whole counter.
    DEC  C                         ; The high byte's displacement is one less.
    PUSH BC                        ; Keep it across EM_IDIOM.
    CALL EM_IDIOM                  ; Emit the inline idiom.
    DB   EP_STHI                   ; LD (IX+d),H.
    POP  BC                        ; Recover the displacement.
    LD   A,C                       ; It follows the opcode.
    JP   EM_BYTE                   ; Emit d and return.

;@ROUTINE OUT CARRY CLOBBERS A,BC,DE,HL,SIGN,PARITY,HALFCARRY,ZERO
; OP_FOR counter,mode. The initial value and then the bound are on the
; stack. Emit POP DE / POP HL, a store of HL to the counter, and PUSH DE,
; which keeps the bound on the stack for the life of the loop.

GC_FOR:                        ; The operands are the counter and the mode.
    CALL EM_READB                  ; Read the counter's frame offset.
    LD   C,A                       ; GC_STORE takes it in C.
    CALL EM_READB                  ; Read the mode.
    LD   B,A                       ; Keep it in B.
    PUSH BC                        ; EM_IDIOM clobbers B.
    CALL EM_IDIOM                  ; Emit the inline idiom.
    DB   EP_ARGS                   ; POP DE / POP HL: DE the bound, HL the start.
    POP  BC                        ; Recover the counter and the mode.
    LD   A,B                       ; GC_STORE takes the mode in A.
    CALL GC_STORE                  ; Emit the store of the start to the counter.
    CALL EM_ENDOP                  ; Emit the inline byte and return.
    DB   $D5                       ; PUSH DE: the bound stays on the stack.

;@ROUTINE OUT CARRY CLOBBERS A,BC,DE,HL,SIGN,PARITY,HALFCARRY,ZERO
; OP_TEST counter,mode,exit, at the loop's top. Emit code that compares
; the counter with the bound (< or <= upward, > or >= downward, as mode
; bits 0..1 say) and jumps to the exit label when the result is false.

GC_TEST:                       ; The operands are counter, mode and exit label.
    CALL EM_READB                  ; Read the counter's frame offset.
    LD   C,A                       ; C is the counter's frame offset.
    CALL EM_READB                  ; Read the mode.
    LD   B,A                       ; B is the mode.
    CALL EM_READB                  ; Read the exit label.
    LD   D,A                       ; D is the exit label.
    LD   (GC_EXIT),A               ; Keep the label past GX_TEST.
    PUSH BC                        ; EM_IDIOM clobbers B.
    PUSH DE                        ; And DE.
    CALL EM_IDIOM                  ; Emit the inline idiom.
    DB   EP_TOPDE                  ; POP DE / PUSH DE: DE is the bound.
    POP  DE                        ; Recover the exit label.
    POP  BC                        ; Recover the counter and the mode.
    PUSH BC                        ; Keep them across GC_LOAD.
    PUSH DE                        ; And the exit label.
    LD   A,B                       ; GC_LOAD takes the mode in A.
    CALL GC_LOAD                   ; Emit the load of the counter into HL.
    POP  DE                        ; Recover the exit label.
    POP  BC                        ; Recover the counter and the mode.
    BIT  1,B                       ; Does the loop count down?
    JR   NZ,.DOWN                  ; Then the counter must stay above the bound.
    BIT  0,B                       ; Upward: is the bound inclusive?
    LD   A,EX_LT                   ; Until: continue while counter < bound.
    JR   Z,.COMPARE                ; An exclusive bound uses <.
    LD   A,EX_LE                   ; To: continue while counter <= bound.
    JR   .COMPARE                  ; Emit the comparison.
.DOWN:                         ; The loop counts down.
    BIT  0,B                       ; Is the bound inclusive?
    LD   A,EX_GT                   ; Until: continue while counter > bound.
    JR   Z,.COMPARE                ; An exclusive bound uses >.
    LD   A,EX_GE                   ; To: continue while counter >= bound.
.COMPARE:                      ; A is the relation to test.
    CALL GX_TEST                   ; Emit LD A,rel / CALL the compare helper: HL = 0 or 1.
    LD   A,(GC_EXIT)               ; Recover the exit label.
    LD   C,A                       ; GC_OPREF takes it in C.
    CALL EM_IDIOM                  ; Emit the inline idiom.
    DB   EP_TESTL                  ; LD A,L / OR A: zero when the loop is over.
    LD   A,$CA                     ; JP Z,nn.
    JP   GC_OPREF                  ; Emit JP Z,exit with its recorded operand.

;@ROUTINE IN DE OUT CARRY CLOBBERS A,BC,HL,SIGN,PARITY,HALFCARRY,ZERO
; Emit LD DE,nn for the word in DE.

EM_LDDE:                       ; DE is the value to load at run time.
    LD   A,$11                     ; LD DE,nn.
    PUSH DE                        ; EM_BYTE clobbers HL, not DE; keep it all the same.
    CALL EM_BYTE                   ; Emit the opcode.
    POP  DE                        ; Recover the value.
    LD   H,D                       ; EM_WORD takes the operand in HL.
    LD   L,E                       ; Low byte too.
    JP   EM_WORD                   ; Emit it and return.

;@ROUTINE OUT CARRY CLOBBERS A,BC,DE,HL,SIGN,PARITY,HALFCARRY,ZERO
; OP_NEXT top,exit,counter,mode,step,offset, at the loop's end. Emit code
; that leaves when the distance left to the bound is less than one step
; (to) or no more than one step (until), and otherwise steps the counter,
; stores it and jumps back to the test.

GC_NEXT:                       ; Six operands follow, eight bytes in all.
    CALL EM_READB                  ; Read the test's label.
    LD   (GC_TOP),A                ; Keep it for the closing jump.
    CALL EM_READB                  ; Read the exit label.
    LD   (GC_EXIT),A               ; Keep it for the leaving jump.
    CALL EM_READB                  ; Read the counter's frame offset.
    LD   (GC_COUNT),A              ; Keep it for the load and the store.
    CALL EM_READB                  ; Read the mode.
    LD   (GC_MODE),A               ; Keep it; every step below tests it.
    CALL EM_READW                  ; Read the step magnitude.
    LD   (GC_STEP),DE              ; Keep it for the test and the step.
    CALL EM_READW                  ; Read the loop's source offset.
    LD   (GC_POS),DE               ; Keep it for a range trap.
    XOR  A                         ; EM_IDIOM reads no A; this has no effect.
    CALL EM_IDIOM                  ; Emit the inline idiom.
    DB   EP_TOPDE                  ; POP DE / PUSH DE: DE is the bound.
    LD   A,(GC_COUNT)              ; Fetch the counter's offset.
    LD   C,A                       ; GC_LOAD takes it in C.
    LD   A,(GC_MODE)               ; And the mode in A.
    CALL GC_LOAD                   ; Emit the load of the counter into HL.
    CALL EM_OP                     ; Emit the inline opcode.
    DB   $E5                       ; PUSH HL: keep the counter for the step.
    LD   A,(GC_MODE)               ; Fetch the mode.
    BIT  1,A                       ; Does the loop count down?
    JR   NZ,.DOWN                  ; Downward, counter minus bound is the distance.
    CALL EM_OP                     ; Emit the inline opcode.
    DB   $EB                       ; EX DE,HL: upward, the distance is bound - counter.
.DOWN:                         ; Both directions: HL and DE are now ordered.
    LD   HL,GT_SUBDE               ; OR A / SBC HL,DE.
    CALL EM_THREE                  ; Emit HL = the distance left to the bound.
    LD   DE,(GC_STEP)              ; Fetch the step.
    CALL EM_LDDE                   ; Emit LD DE,step.
    LD   A,(GC_MODE)               ; Fetch the mode.
    AND  1                         ; Is the bound inclusive?
    LD   A,EX_LT                   ; To: leave when distance < step.
    JR   NZ,.COMPARE               ; An inclusive bound uses <.
; Until leaves when distance <= step, to when distance < step.
    LD   A,(GC_MODE)               ; Fetch the mode again.
    BIT  0,A                       ; Bit 0 is known clear here; this test never branches.
    LD   A,EX_LT                   ; Overwritten below.
    JR   NZ,.COMPARE               ; Not taken.
    LD   A,EX_LE                   ; Until: leave when distance <= step.
.COMPARE:                      ; A is the relation that means leave.
    CALL GX_TEST                   ; Emit LD A,rel / CALL the compare helper: HL = 0 or 1.
    LD   HL,GT_PROBE               ; LD A,L / OR A / POP HL.
    CALL EM_THREE                  ; Emit the test and recover the counter.
    LD   A,(GC_EXIT)               ; Fetch the exit label.
    LD   C,A                       ; GC_OPREF takes it in C.
    LD   A,$C2                     ; JP NZ,nn: leave through the exit label.
    CALL GC_OPREF                  ; Emit the jump with its recorded operand.
    LD   DE,(GC_STEP)              ; Fetch the step.
    CALL EM_LDDE                   ; Emit LD DE,step.
    LD   A,(GC_MODE)               ; Fetch the mode.
    BIT  1,A                       ; Does the loop count down?
    JR   NZ,.MINUS                 ; Then subtract the step.
    LD   A,$19                     ; ADD HL,DE.
    CALL EM_BYTE                   ; Emit the upward step.
    JR   .CHECK                    ; A u8 counter may now exceed 255.
.MINUS:                        ; The loop counts down.
    LD   HL,GT_SUBDE               ; OR A / SBC HL,DE.
    CALL EM_THREE                  ; Emit the downward step.
.CHECK:                        ; HL is the stepped counter at run time.
    LD   A,(GC_MODE)               ; Fetch the mode.
    BIT  2,A                       ; Is the counter a u16?
    JR   NZ,.STORE                 ; It cannot pass the u16 bound.
    BIT  1,A                       ; Does a u8 counter count down?
    JR   NZ,.STORE                 ; It cannot pass the bound, which is at least 0.
    CALL EM_IDIOM                  ; Emit the inline idiom.
    DB   EP_TESTH                  ; LD A,H / OR A: zero when the counter fits.
    CALL EM_OP                     ; Emit the inline opcode.
    DB   $CA                       ; JP Z,nn: skip the trap when the counter fits.
    LD   HL,(EM_PTR)               ; HL is where its operand goes.
    LD   (EM_UFIX),HL              ; Keep it to patch past the trap.
    LD   HL,0                      ; A placeholder until the trap is emitted.
    CALL EM_WORD                   ; Emit the operand.
    LD   HL,(GC_POS)               ; The loop's source offset.
    LD   A,4                       ; Trap 4: the counter left its range.
    CALL GX_RAISE                  ; Emit the trap body.
    LD   DE,(EM_UFIX)              ; DE is the JP Z operand.
    LD   HL,(EM_PTR)               ; The fit path continues here.
    CALL EM_FIXW                   ; Point the jump past the trap.
.STORE:                        ; The stepped counter fits.
    LD   A,(GC_COUNT)              ; Fetch the counter's offset.
    LD   C,A                       ; GC_STORE takes it in C.
    LD   A,(GC_MODE)               ; And the mode in A.
    CALL GC_STORE                  ; Emit the store of HL to the counter.
    LD   A,(GC_TOP)                ; Fetch the test's label.
    LD   C,A                       ; GC_OPREF takes it in C.
    LD   A,$C3                     ; JP nn.
    JP   GC_OPREF                  ; Emit JP top with its recorded operand.

;@ROUTINE OUT CARRY CLOBBERS A,B,HL,SIGN,PARITY,HALFCARRY,ZERO
; OP_CLEAN, at the loop's exit label: emit POP DE to discard the bound.

GC_DROP:                       ; Every exit from the loop arrives here.
    CALL EM_ENDOP                  ; Emit the inline byte and return.
    DB   $D1                       ; POP DE: the bound is no longer needed.

GT_SUBDE: DB   $B7,$ED,$52     ; OR A / SBC HL,DE: HL minus DE.
GT_PROBE: DB   $7D,$B7,$E1     ; LD A,L / OR A / POP HL: test, then restore.
