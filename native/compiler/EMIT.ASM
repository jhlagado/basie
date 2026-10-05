;==========================================================================
;  Emitter primitives
;==========================================================================
;
;  The lowest layer of code generation. The generators (GENEXPR.ASM and
;  GENCALL.ASM) write the routine being parsed into the blob writer's
;  buffer (BLOB.ASM) through these primitives, as the reference compiler's
;  Blob does (ref/compile/emit.ts): bytes, words, references to other
;  blobs, calls to runtime helpers and labels within the routine. They
;  also keep the frame accounting of the reference's RoutineState: the
;  bytes pushed as temporaries, the deepest frame reached and the largest
;  stack figure of a helper called, from which the routine's frame and
;  need words are computed when it ends.
;
;  Quiet code. While EX_QUIET is nonzero the parser is in the right arm of
;  an `and` or `or` whose constant left operand decides it, which the
;  reference compiles and then discards (Compiler.suppress). Every
;  primitive that writes to the blob writes nothing then; the frame
;  accounting still runs, as the reference's does.
;
;  Labels. A label is an offset in the routine, EM_NONE until defined. An
;  operand naming a defined label is a self-reference: an ABS16 reference
;  to the routine's own ordinal with the label's offset as the addend. An
;  operand naming a label not yet defined is written the same way with a
;  placeholder addend, $FFFF, which is nonzero so that the encoded
;  reference has room for its addend word; the label keeps a chain of the
;  addresses of those addend words in BL_REFS, each word holding the next
;  link until EM_LDEF writes the label's offset into all of them. So the
;  references come out in offset order, as the reference compiler sorts
;  them, and pending operands cost no table space.
;
;  Principal entries:
;    EM_OPEN   start the frame accounting and labels of a routine
;    EM_QUIET  NZ while code is being discarded
;    EM_BYTE   append the byte in A (EM_OP: the inline byte after the CALL)
;    EM_WORD   append the word in HL
;    EM_SEQ    append the inline counted byte sequence after the CALL
;    EM_REF    append an ABS16 reference to blob HL with addend DE
;    EM_TRAP   append CALL cc to a trap reporter
;    EM_HELP   append CALL helper, the inline ordinal and stack figure
;    EM_JPH    append JP helper likewise
;    EM_PUSH   count A bytes pushed; EM_POP counts them popped (EM_POP2: two)
;    EM_LNEW   allocate a label
;    EM_LREF   append the operand naming a label
;    EM_LDEF   define a label at the current offset
;    EM_JUMP   append JP or JP cc to a label
;    EM_LFREE  free the last label allocated
;    EM_ALLOC  allocate a frame slot (allocLocal)
;    EM_LINE   mark the line of the statement at the lookahead
;
;  Workspace (STATE.ASM): EM_FRAME to EM_LLIM. A full label table raises
;  DG_LABEL; a blob too large for its buffers raises DG_BLOB (BL_OVER).

;@ROUTINE CLOBBERS A,B,HL,CARRY,ZERO,SIGN,PARITY,HALFCARRY
; Start a routine: no frame, nothing pushed, no helper or callee stack, no
; labels.

EM_OPEN:                       ; A routine's blob has begun.
    LD   HL,EM_FRAME               ; The accounting words and the label count
    LD   B,EM_LTAB-EM_FRAME        ; lie together before the labels.
    XOR  A                         ; Every one starts at zero.
.LOOP:                         ; B bytes remain to clear.
    LD   (HL),A                    ; Clear one.
    INC  HL                        ; Move to the next.
    DJNZ .LOOP                     ; Until the label count is clear too.
    RET                            ; The routine owns nothing yet.

;@ROUTINE OUT ZERO
; NZ while the parser is in a discarded arm (EX_QUIET nonzero), when
; nothing may be written to the blob. Every register but F is kept.

EM_QUIET:                      ; Is code being discarded?
    PUSH HL                        ; Keep the caller's HL.
    LD   HL,EX_QUIET               ; The count of discarded arms open.
    INC  (HL)                      ; INC then DEC leaves it unchanged
    DEC  (HL)                      ; and sets Z only when it is zero.
    POP  HL                        ; Restore HL; POP keeps the flags.
    RET                            ; NZ: discard.

;@ROUTINE CLOBBERS A,CARRY,ZERO,SIGN,PARITY,HALFCARRY
; Append the byte that follows the CALL and return past it. HL is kept.

EM_OP:                         ; The inline byte is one opcode.
    EX   (SP),HL                   ; HL addresses it; the caller's HL waits.
    LD   A,(HL)                    ; Fetch it.
    INC  HL                        ; Step over it: the return address,
    EX   (SP),HL                   ; and HL is restored.

;@ROUTINE IN A CLOBBERS CARRY,ZERO,SIGN,PARITY,HALFCARRY
; Append the byte in A to the routine's blob, unless code is being
; discarded. Every register but F is kept.

EM_BYTE:                       ; A is the byte.
    CALL EM_QUIET                  ; Is code being discarded?
    RET  NZ                        ; Then write nothing.
    JP   BL_BYTE                   ; Append it; BL_BYTE keeps A, BC, DE, HL.

;@ROUTINE IN HL CLOBBERS A,CARRY,ZERO,SIGN,PARITY,HALFCARRY
; Append the word in HL, low byte first.

EM_WORD:                       ; HL is the word.
    LD   A,L                       ; The low byte first.
    CALL EM_BYTE                   ; Append it.
    LD   A,H                       ; Then the high byte.
    JR   EM_BYTE                   ; Append it and return.

;@ROUTINE CLOBBERS A,B,CARRY,ZERO,SIGN,PARITY,HALFCARRY
; Append the sequence that follows the CALL: a count byte, then that many
; bytes. Return past it. HL is kept.

EM_SEQ:                        ; The inline count and bytes follow.
    EX   (SP),HL                   ; HL addresses them; the caller's HL waits.
    LD   B,(HL)                    ; B is the count.
.LOOP:                         ; B bytes remain.
    INC  HL                        ; Step to the next.
    LD   A,(HL)                    ; Fetch it.
    CALL EM_BYTE                   ; Append it.
    DJNZ .LOOP                     ; Until the sequence is written.
    INC  HL                        ; HL is past the sequence,
    EX   (SP),HL                   ; the return address; HL is restored.
    RET                            ; Continue after the sequence.

;@ROUTINE IN A,L CLOBBERS A,BC,DE,HL,CARRY,ZERO,SIGN,PARITY,HALFCARRY
; Append a trap site, CALL cc to a trap reporter (emit.ts callBlobIf): the
; opcode A, then an ABS16 reference to helper L. A trap site counts no
; stack figure, as the reference's counts none.

EM_TRAP:                       ; A is CALL cc, L the trap's ordinal.
    CALL EM_BYTE                   ; The opcode.
    LD   H,0                       ; HL is the helper's ordinal,
    LD   D,H                       ; with no
    LD   E,H                       ; addend; fall into EM_REF.

;@ROUTINE IN DE,HL CLOBBERS A,BC,DE,HL,CARRY,ZERO,SIGN,PARITY,HALFCARRY
; Append an ABS16 reference to blob HL with addend DE and its placeholder,
; unless code is being discarded.

EM_REF:                        ; HL is the target, DE the addend.
    CALL EM_QUIET                  ; Is code being discarded?
    RET  NZ                        ; Then write nothing.
    XOR  A                         ; Form ABS16.
    JP   BL_REF                    ; Append it and return.

;@ROUTINE CLOBBERS A,BC,DE,HL,CARRY,ZERO,SIGN,PARITY,HALFCARRY
; Append JP helper, as EM_HELP appends its CALL: the routine exit through
; RETN.

EM_JPH:                        ; The ordinal and figure follow the CALL.
    LD   C,$C3                     ; JP nn.
    JR   EM_HCALL                  ; As a CALL is appended.

;@ROUTINE CLOBBERS A,BC,DE,HL,CARRY,ZERO,SIGN,PARITY,HALFCARRY
; Append CALL helper, where the CALL is followed by its HP_ word (HELPERS.ASM):
; the helper's ordinal (below $100) and its stack figure, the bytes a
; returning call uses (helper table). The figure raises EM_STACK, as the reference's
; callHelper does, even in discarded code.

EM_HELP:                       ; The ordinal and figure follow the CALL.
    LD   C,$CD                     ; CALL nn.
EM_HCALL:                      ; C is the opcode.
    POP  HL                        ; HL addresses them.
    LD   E,(HL)                    ; E is the ordinal.
    INC  HL                        ; Then
    LD   A,(HL)                    ; the stack figure.
    INC  HL                        ; Return past both.
    PUSH HL                        ; The return address.
    LD   HL,EM_STACK               ; The largest figure so far (a byte).
    CP   (HL)                      ; Is this one larger?
    JR   C,.SMALLER                ; No: keep the old one.
    LD   (HL),A                    ; Yes: it is the largest.
.SMALLER:                      ; EM_STACK is up to date.
    LD   A,C                       ; The opcode,
    CALL EM_BYTE                   ; appended.
    LD   L,E                       ; HL is the helper's ordinal
    LD   H,0                       ; as a word.
    LD   D,H                       ; With no addend:
    LD   E,H                       ; DE is zero.
    JR   EM_REF                    ; Append the reference and return.

;@ROUTINE IN A CLOBBERS A,DE,HL,CARRY,ZERO,SIGN,PARITY,HALFCARRY
; Count A bytes pushed as temporaries, and raise EM_DEEP to the frame and
; pushes now reached if that is deeper (the reference's push).

EM_PUSH:                       ; A is the bytes pushed.
    LD   HL,(EM_TEMPS)             ; The bytes already pushed.
    LD   E,A                       ; DE is the bytes
    LD   D,0                       ; just pushed.
    ADD  HL,DE                     ; The new total.
    LD   (EM_TEMPS),HL             ; Keep it.
    LD   DE,(EM_FRAME)             ; With the locals' bytes,
    ADD  HL,DE                     ; HL is the depth reached.
    EX   DE,HL                     ; DE is the depth.
    LD   HL,(EM_DEEP)              ; Is it deeper than any before?
    OR   A                         ; Clear carry.
    SBC  HL,DE                     ; Carry if DE is deeper.
    RET  NC                        ; No: nothing changes.
    LD   (EM_DEEP),DE              ; Yes: it is the deepest.
    RET                            ; The frame word will cover it.

;@ROUTINE CLOBBERS A,DE,HL,CARRY,ZERO,SIGN,PARITY,HALFCARRY
; Count the two bytes of a byte or word temporary popped.

EM_POP2:                       ; A temporary of two bytes was popped.
    LD   A,2                       ; Two bytes; fall into EM_POP.

;@ROUTINE IN A CLOBBERS A,DE,HL,CARRY,ZERO,SIGN,PARITY,HALFCARRY
; Count A bytes popped (the reference's pop).

EM_POP:                        ; A is the bytes popped.
    LD   HL,(EM_TEMPS)             ; The bytes pushed.
    LD   E,A                       ; DE is the bytes
    LD   D,0                       ; just popped.
    OR   A                         ; Clear carry.
    SBC  HL,DE                     ; Fewer remain.
    LD   (EM_TEMPS),HL             ; Keep the count.
    RET                            ; The deepest point stays recorded.

;@ROUTINE OUT A,HL CLOBBERS CARRY,ZERO,SIGN,PARITY,HALFCARRY
; Allocate a label, undefined and with no operand waiting: A is its
; number and HL its entry. DG_LABEL when the routine has used them all.

EM_LNEW:                       ; A label is wanted.
    LD   HL,EM_LCNT                ; The labels used so far.
    LD   A,(HL)                    ; A is the new label's number.
    CP   EM_LCAP                   ; Is there one left?
    JR   NC,.FULL                  ; No: refuse the routine.
    INC  (HL)                      ; Count it.
    CALL EM_LAT                    ; HL is its entry; A is kept.
    PUSH HL                        ; Keep the entry.
    LD   (HL),EM_NONE&$FF          ; The offset is EM_NONE:
    INC  HL                        ; undefined,
    LD   (HL),EM_NONE/$100         ; both bytes.
    INC  HL                        ; The chain head
    LD   (HL),0                    ; is zero:
    INC  HL                        ; no operand
    LD   (HL),0                    ; waits.
    POP  HL                        ; HL is the entry again.
    RET                            ; A is the label.
.FULL:                         ; Every label is in use.
    CALL DG_RAISE                  ; Report it; no return.
    DB   DG_LABEL                  ; Labels exhausted.

;@ROUTINE IN A OUT HL CLOBBERS CARRY,ZERO,SIGN,PARITY,HALFCARRY
; HL addresses label A's entry, EM_LTAB plus four times A. A is kept.

EM_LAT:                        ; A is a label.
    LD   L,A                       ; HL is the label
    LD   H,0                       ; as a word,
    ADD  HL,HL                     ; times two,
    ADD  HL,HL                     ; times four, the entry's size.
    PUSH DE                        ; Keep the caller's DE.
    LD   DE,EM_LTAB                ; The table's base
    ADD  HL,DE                     ; plus the offset.
    POP  DE                        ; Restore DE.
    RET                            ; HL is the entry.

;@ROUTINE IN A CLOBBERS A,BC,DE,HL,CARRY,ZERO,SIGN,PARITY,HALFCARRY
; Append the 16-bit operand naming label A (emit.ts labelOperand): a
; self-reference to its offset when it is defined, otherwise a reference
; with a placeholder addend added to the label's chain.

EM_LREF:                       ; A is the label.
    CALL EM_QUIET                  ; Is code being discarded?
    RET  NZ                        ; Then write nothing.
    CALL EM_LAT                    ; HL is its entry.
    LD   E,(HL)                    ; DE is
    INC  HL                        ; its offset,
    LD   D,(HL)                    ; EM_NONE if undefined.
    INC  HL                        ; HL is the chain head.
    LD   A,D                       ; Is the offset EM_NONE?
    AND  E                         ; Both bytes $FF
    INC  A                         ; make zero here.
    JR   Z,.PENDING                ; Undefined: chain the operand.
    LD   HL,(BL_ORD)               ; Defined: the routine itself,
    JP   EM_REF                    ; with the offset as the addend.
.PENDING:                      ; DE is EM_NONE, a nonzero placeholder.
    PUSH HL                        ; Keep the chain head's address.
    LD   HL,(BL_ORD)               ; The routine itself.
    CALL EM_REF                    ; The reference, with its addend word.
    POP  HL                        ; HL is the chain head.
    LD   DE,(BL_RPTR)              ; The addend word is the last two bytes
    DEC  DE                        ; of the encoded references:
    DEC  DE                        ; DE addresses it.
    LD   A,(HL)                    ; The old head's low byte
    LD   (DE),A                    ; becomes the link,
    LD   (HL),E                    ; and the addend word the head.
    INC  HL                        ; Then
    INC  DE                        ; the high bytes:
    LD   A,(HL)                    ; the old head's
    LD   (DE),A                    ; into the link,
    DEC  DE                        ; and the word's address
    LD   (HL),D                    ; into the head.
    RET                            ; The operand waits for EM_LDEF.

;@ROUTINE IN A CLOBBERS A,BC,DE,HL,CARRY,ZERO,SIGN,PARITY,HALFCARRY
; Define label A at the blob's current offset (emit.ts defineLabel): write
; the offset into the addend word of every operand waiting on its chain.

EM_LDEF:                       ; A is the label.
    CALL EM_LAT                    ; HL is its entry.
    LD   DE,(BL_LEN)               ; DE is the current offset.
    LD   (HL),E                    ; It is the label's offset,
    INC  HL                        ; low byte
    LD   (HL),D                    ; and high byte.
    INC  HL                        ; HL is the chain head.
    LD   C,(HL)                    ; BC is the first
    INC  HL                        ; waiting addend word,
    LD   B,(HL)                    ; zero when none waits.
.WALK:                         ; BC is the next word, or zero.
    LD   A,B                       ; Is the chain at its end?
    OR   C                         ; A zero link ends it.
    RET  Z                         ; Every operand has its offset.
    LD   L,C                       ; HL is
    LD   H,B                       ; the addend word.
    LD   C,(HL)                    ; BC is the next link,
    LD   (HL),E                    ; and the word becomes
    INC  HL                        ; the label's
    LD   B,(HL)                    ; offset,
    LD   (HL),D                    ; both bytes.
    JR   .WALK                     ; Resolve the next.

;@ROUTINE IN A,C CLOBBERS A,BC,DE,HL,CARRY,ZERO,SIGN,PARITY,HALFCARRY
; Append the jump C, JP ($C3) or JP cc, to label A (emit.ts jp, jpIf).

EM_JUMP:                       ; A is the label, C the opcode.
    PUSH AF                        ; Keep the label.
    LD   A,C                       ; The opcode,
    CALL EM_BYTE                   ; appended.
    POP  AF                        ; The label
    JP   EM_LREF                   ; is its operand; return.

;@ROUTINE IN A CLOBBERS A,HL,CARRY,ZERO,SIGN,PARITY,HALFCARRY
; Label A is defined and nothing will name it again: free it if it is
; the last allocated, so that labels are bounded by nesting, not by the
; routine's length.

EM_LFREE:                      ; A is the label.
    LD   HL,EM_LCNT                ; The labels in use.
    INC  A                         ; Was it
    CP   (HL)                      ; the last?
    RET  NZ                        ; No: a later one is still in use.
    DEC  (HL)                      ; Yes: it is free.
    RET                            ; Done.

;@ROUTINE IN A OUT HL CLOBBERS A,DE,CARRY,ZERO,SIGN,PARITY,HALFCARRY
; Allocate A bytes in the frame (allocLocal): the frame grows, may be the
; deepest yet, and HL returns the new slot's offset from IX, negative.

EM_ALLOC:                      ; A is the size.
    LD   HL,(EM_FRAME)             ; The locals' bytes
    LD   E,A                       ; grow
    LD   D,0                       ; by
    ADD  HL,DE                     ; the size.
    LD   (EM_FRAME),HL             ; The frame holds the slot.
    PUSH HL                        ; Keep the size.
    XOR  A                         ; Nothing is pushed, but the frame
    CALL EM_PUSH                   ; may now be the deepest yet.
    POP  DE                        ; The frame's size,
    LD   HL,0                      ; negated,
    OR   A                         ; is the slot's
    SBC  HL,DE                     ; offset.
    RET                            ; HL is the offset.

;@ROUTINE IN A OUT A CLOBBERS BC,DE,HL,CARRY,ZERO,SIGN,PARITY,HALFCARRY
; A statement begins: the code from the blob's current offset belongs to
; the line of the lookahead token, its first (Compiler.statement). The
; LL(1) engine calls this as it expands the statement nonterminal. A is
; kept.

EM_LINE:                       ; A statement is about to be parsed.
    PUSH AF                        ; Keep the caller's A.
    CALL PR_PEEK                   ; The statement's first token is read:
    LD   A,(SRC_ID)                ; its part, counted from one,
    DEC  A                         ; is the line stream's part, from zero,
    LD   HL,(TK_LINE)              ; and its line.
    CALL BL_LINE                   ; Mark it.
    POP  AF                        ; Restore A.
    RET                            ; Parse the statement.
