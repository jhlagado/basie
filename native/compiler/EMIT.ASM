;==========================================================================
;  Emitter primitives
;==========================================================================
;
;  The lowest layer of the emit phase. Once the parser has closed the
;  semantic transcript, GX_WALK replays it one operation at a time, and the
;  generators (GX_, GC_, RG_, GA_) build Z80 code from these primitives:
;  append a byte, a word, an opcode with its operand, a fixed byte
;  sequence or a two-byte idiom; patch a displacement or a word written
;  earlier; and read operands back from the transcript.
;
;  Every byte passes through EM_BYTE. It checks the capacity left in the
;  output region (EM_LIM), hands the byte, its target address (EM_PTR) and
;  the output bank (TG_OBANK) to the sink PUB_BYTE, and advances EM_PTR.
;  Patches go to PUB_FIXB and PUB_FIXW. The sinks are SHELL.ASM's stubs,
;  which discard the placed output until blob output replaces it (65.3,
;  65.4). A full region or a failing sink raises a diagnostic, which
;  unwinds to the compile entry, so every primitive that returns has
;  succeeded and returns carry clear.
;
;  EM_BYTE keeps A, C and DE, which lets EM_WORD and EM_OPB hold the
;  second byte in C across the first call. EM_OP, EM_ENDOP and EM_IDIOM
;  take their operand from the byte after the CALL, which costs one byte
;  at each call site instead of a register load.
;
;  Principal entries:
;    EM_BYTE   append the byte in A
;    EM_WORD   append the word in HL, low byte first
;    EM_OPW    append opcode A and the word in HL (EM_CALL, EM_LDHL,
;              EM_LDBC and EM_PUTA fix the opcode)
;    EM_OPB    append opcode A and the byte in C (EM_LDA: LD A,n)
;    EM_OP     append the inline byte after the CALL, return past it
;    EM_ENDOP  append the inline byte, return to the caller's caller
;    EM_IDIOM  append the two-byte idiom whose EP_ index follows the CALL
;    EM_BYTES  copy B template bytes from HL (EM_PAIR, EM_THREE, EM_FOUR,
;              EM_FIVE and EM_EIGHT fix the count); EM_BLOCK copies BC
;    EM_JRCC   append JR opcode A with a zero displacement (EM_JR, EM_JRNC)
;    EM_FIXJR  patch the displacement at DE to reach HL (EM_LAND: to here)
;    EM_FIXW   patch the word at DE with HL
;    EM_TOVAR  append LD (nn),A for the runtime-state offset in DE
;    EM_TRAP   append the trap record and the terminal jump (EM_STOP,
;              EM_DONE; EM_STRAY sets up an unhandled-error trap)
;    EM_READB  read the next transcript byte (EM_READW a word, EM_READA
;              a global's target address)
;    EM_LEAVE  append the frame epilogue; GT_ENTER holds the prologue
;
;  Workspace (STATE.ASM): EM_PTR is the target address of the next byte,
;  EM_LIM the bytes left in the output region, EM_FIXAT EM_FIXJR's operand
;  address and EM_READP the transcript read pointer. All of them overlay
;  parser state that is dead once the transcript is closed.

;@ROUTINE IN A OUT CARRY CLOBBERS B,HL,SIGN,PARITY,HALFCARRY,ZERO
; Append the byte in A at EM_PTR through the output sink. A full output
; region raises DG_IMAGE and a sink failure an output diagnostic; neither
; returns.

EM_BYTE:                       ; A is the byte for address EM_PTR.
    LD   B,A                       ; Keep the byte while A tests the capacity.
    LD   HL,(EM_LIM)               ; HL counts the bytes the region can still take.
    LD   A,H                       ; Test the count for zero.
    OR   L                         ; Is the region already full?
    JP   Z,TG_FULL                 ; Then the image cannot hold the program.
    DEC  HL                        ; This byte takes one place.
    LD   (EM_LIM),HL               ; Publish the reduced capacity.
    LD   HL,(EM_PTR)               ; HL is the byte's target address.
    PUSH BC                        ; Keep the byte and the caller's C across the sink.
    LD   A,(TG_OBANK)              ; Fetch the bank that receives output.
    LD   C,A                       ; The sink takes the bank in C.
    LD   A,B                       ; And the byte in A.
    PUSH HL                        ; Keep the target address across the sink.
    CALL PUB_BYTE                  ; Write the byte; carry reports a sink failure.
    POP  HL                        ; Recover the byte's target address.
    POP  BC                        ; Recover the byte and the caller's C.
    JP   C,TG_FAIL                 ; A failed sink ends the compilation.
    INC  HL                        ; The next byte goes one address higher.
    LD   (EM_PTR),HL               ; Advance the output cursor.
    OR   A                         ; Report success with carry clear.
    RET                            ; A still holds the byte.

;@ROUTINE NORETURN
; Append the byte that follows the CALL and return to the caller's caller,
; so that CALL EM_ENDOP and its DB end a generator in four bytes. Clobbers
; B and HL as EM_BYTE does, with A holding the byte and carry clear.

EM_ENDOP:                      ; The inline byte is the generator's last.
    POP  HL                        ; HL addresses the inline byte; it is not pushed back.
    LD   A,(HL)                    ; Fetch the byte to emit.
    JR   EM_BYTE                   ; EM_BYTE's RET goes to the caller's caller.

;@ROUTINE NORETURN
; Append the byte that follows the CALL and return past it. Clobbers B
; and HL as EM_BYTE does, with A holding the byte and carry clear.

EM_OP:                         ; The inline byte is one opcode to emit.
    POP  HL                        ; HL addresses the inline byte.
    LD   A,(HL)                    ; Fetch the byte to emit.
    INC  HL                        ; Step over it.
    PUSH HL                        ; Return to the instruction after the byte.
    JR   EM_BYTE                   ; Emit it and return through EM_BYTE.

;@ROUTINE NORETURN
; Append the two-byte idiom whose EP_ index is the byte after the CALL,
; and return past that byte. Clobbers A, B, DE and HL with carry clear; C
; is kept, so a caller may hold a displacement there.

EM_IDIOM:                      ; The inline byte is an EP_ index.
    POP  HL                        ; HL addresses the inline index.
    LD   A,(HL)                    ; Fetch the idiom's index.
    INC  HL                        ; Step over it.
    PUSH HL                        ; Return to the instruction after the index.
    ADD  A,A                       ; Each idiom is two bytes.
    LD   L,A                       ; Form the byte offset as a word.
    LD   H,0                       ; The largest offset is 26.
    LD   DE,.IDIOMS                ; Base of the idiom table.
    ADD  HL,DE                     ; HL addresses the idiom's first byte.
    JR   EM_PAIR                   ; Emit both bytes and return.

EP_DECSP EQU  0                ; DEC SP twice: reserve a two-byte local.
EP_LDLO EQU  1                 ; LD L,(IX+d); the caller emits d.
EP_LDHI EQU  2                 ; LD H,(IX+d); the caller emits d.
EP_STLO EQU  3                 ; LD (IX+d),L; the caller emits d.
EP_STHI EQU  4                 ; LD (IX+d),H; the caller emits d.
EP_ARGS EQU  5                 ; Pop the right operand to DE and the left to HL.
EP_TOPDE EQU  6                ; Copy the stack top into DE and keep it.
EP_TESTL EQU  7                ; Zero flag from L: a canonical boolean.
EP_TESTH EQU  8                ; Zero flag from H: the value fits a byte.
EP_POPA EQU  9                 ; Pop a carrier and take its low byte in A.
EP_FIELD EQU  10               ; Pop the base to HL, then LD DE,nn; caller emits nn.
EP_ARGSX EQU  11               ; Pop the top to HL and the next to DE.
EP_ZEROH EQU  12               ; LD H,0: widen a byte in L.
EP_LDIR EQU  13                ; LDIR: copy BC bytes from HL to DE.
.IDIOMS:                       ; Fourteen two-byte idioms, in EP_ order.
    DB   $3B,$3B                   ; DEC SP / DEC SP: room for a u16 local.
    DB   $DD,$6E                   ; LD L,(IX+d): low byte of a local.
    DB   $DD,$66                   ; LD H,(IX+d): high byte of a local.
    DB   $DD,$75                   ; LD (IX+d),L: store a local's low byte.
    DB   $DD,$74                   ; LD (IX+d),H: store a local's high byte.
    DB   $D1,$E1                   ; POP DE / POP HL: both binary operands.
    DB   $D1,$D5                   ; POP DE / PUSH DE: read the top without popping.
    DB   $7D,$B7                   ; LD A,L / OR A: test a boolean for false.
    DB   $7C,$B7                   ; LD A,H / OR A: test for a zero high byte.
    DB   $E1,$7D                   ; POP HL / LD A,L: a u8 value into A.
    DB   $E1,$11                   ; POP HL / LD DE,nn: an offset to add.
    DB   $E1,$D1                   ; POP HL / POP DE: operands in the other order.
    DB   $26,$00                   ; LD H,0: zero-extend L.
    DB   $ED,$B0                   ; LDIR: block copy.

;@ROUTINE IN HL OUT CARRY CLOBBERS A,B,C,HL,SIGN,PARITY,HALFCARRY,ZERO
; Append the word in HL, low byte first, as a Z80 operand is stored.

EM_WORD:                       ; HL is the word to emit.
    LD   C,H                       ; EM_BYTE keeps C, so park the high byte there.
    LD   A,L                       ; The low byte comes first.
    CALL EM_BYTE                   ; Emit the low byte.
    LD   A,C                       ; Then the high byte.
    JR   EM_BYTE                   ; Emit it and return.

;@ROUTINE IN B,HL OUT CARRY CLOBBERS A,HL,SIGN,PARITY,HALFCARRY,ZERO
; Copy B template bytes from HL. A fixed sequence is cheaper as data once
; two or more generators need four or more of the same bytes.

EM_BYTES:                      ; B counts the bytes at HL.
    PUSH BC                        ; Keep the caller's BC.
    LD   C,B                       ; Widen the count to BC.
    LD   B,0                       ; At most 255 bytes.
    CALL EM_BLOCK                  ; Copy them through EM_BYTE.
    POP  BC                        ; Restore the caller's BC.
    RET                            ; HL now addresses the byte after the template.

;@ROUTINE IN BC,HL OUT CARRY CLOBBERS A,BC,HL,SIGN,PARITY,HALFCARRY,ZERO
; Copy the BC bytes at HL through the checked output sink.

EM_BLOCK:                      ; BC counts the bytes left to copy from HL.
    LD   A,B                       ; Test the remaining count.
    OR   C                         ; Is the copy complete?
    RET  Z                         ; Then return with carry clear.
    LD   A,(HL)                    ; Fetch the next source byte.
    INC  HL                        ; Step the source pointer.
    PUSH BC                        ; EM_BYTE clobbers B.
    PUSH HL                        ; And HL.
    CALL EM_BYTE                   ; Append the byte.
    POP  HL                        ; Recover the source pointer.
    POP  BC                        ; Recover the count.
    DEC  BC                        ; One byte fewer to copy.
    JR   EM_BLOCK                  ; Continue until BC is zero.

; Fixed-count entries for EM_BYTES: copy 8, 5, 4, 3 or 2 template bytes
; from HL. Each sets B to its count and shares the jump in EM_TAIL.

;@ROUTINE IN HL OUT CARRY CLOBBERS A,B,HL,SIGN,PARITY,HALFCARRY,ZERO
; Copy the eight template bytes at HL.

EM_EIGHT:                      ; HL addresses an eight-byte template.
    LD   B,8                       ; Eight bytes: the frame prologue.
    JR   EM_TAIL                   ; Copy them.

;@ROUTINE IN HL OUT CARRY CLOBBERS A,B,HL,SIGN,PARITY,HALFCARRY,ZERO
; Copy the five template bytes at HL.

EM_FIVE:                       ; HL addresses a five-byte template.
    LD   B,5                       ; Five bytes.
    JR   EM_TAIL                   ; Copy them.

;@ROUTINE IN HL OUT CARRY CLOBBERS A,B,HL,SIGN,PARITY,HALFCARRY,ZERO
; Copy the four template bytes at HL.

EM_FOUR:                       ; HL addresses a four-byte template.
    LD   B,4                       ; Four bytes.
    JR   EM_TAIL                   ; Copy them.

;@ROUTINE IN HL OUT CARRY CLOBBERS A,B,HL,SIGN,PARITY,HALFCARRY,ZERO
; Copy the three template bytes at HL.

EM_THREE:                      ; HL addresses a three-byte template.
    LD   B,3                       ; Three bytes.
    JR   EM_TAIL                   ; Copy them.

;@ROUTINE IN HL OUT CARRY CLOBBERS A,B,HL,SIGN,PARITY,HALFCARRY,ZERO
; Copy the two template bytes at HL. EM_IDIOM ends here.

EM_PAIR:                       ; HL addresses a two-byte template.
    LD   B,2                       ; Two bytes: one idiom.

;@ROUTINE IN B,HL OUT CARRY CLOBBERS A,HL,SIGN,PARITY,HALFCARRY,ZERO
; The fixed-count entries' shared jump to EM_BYTES.

EM_TAIL:                       ; B is the count for EM_BYTES.
    JR   EM_BYTES                  ; Copy B bytes from HL.

;@ROUTINE IN DE,HL OUT CARRY CLOBBERS A,BC,DE,HL,SIGN,PARITY,HALFCARRY,ZERO
; Patch the JR displacement byte at DE so that the jump reaches HL. The
; displacement counts from the byte after it, the end of the JR. A target
; out of reach raises DG_REACH and does not return.

EM_FIXJR:                      ; DE is the displacement byte, HL the target.
    LD   (EM_FIXAT),DE             ; Keep the operand address for the sink.
    INC  DE                        ; The CPU adds the displacement to the next address.
    OR   A                         ; Clear carry for the subtraction.
    SBC  HL,DE                     ; HL is the signed distance to the target.
    LD   C,L                       ; Keep the candidate displacement.
    LD   A,C                       ; Take its sign bit.
    ADD  A,A                       ; Carry is bit 7 of the displacement.
    SBC  A,A                       ; A is its sign extension: $00 or $FF.
    CP   H                         ; A distance in -128..127 has exactly that high byte.
    JR   NZ,.TOOFAR                ; Any other distance is out of JR's reach.
.STORE:                        ; The displacement fits in one byte.
    LD   B,C                       ; Keep the displacement while A fetches the bank.
    LD   HL,(EM_FIXAT)             ; HL is the operand address for the sink.
    LD   A,(TG_OBANK)              ; Fetch the bank that holds the operand.
    LD   C,A                       ; The sink takes the bank in C.
    LD   A,B                       ; And the byte in A.
    CALL PUB_FIXB                  ; Rewrite the operand; carry reports a sink failure.
    JP   C,TG_FAIL                 ; A failed sink ends the compilation.
    OR   A                         ; Report success with carry clear.
    RET                            ; The branch now lands on its target.
.TOOFAR:                       ; The generated JR cannot reach its target.
    CALL DG_RAISE                  ; Report the code-size limit of a short branch.
    DB   DG_REACH                  ; Diagnostic: branch target out of reach.

; Small instruction emitters shared by the generators. The entries share
; one opcode-and-operand tail instead of repeating it in every semantic
; operation.

;@ROUTINE IN A,HL OUT CARRY CLOBBERS A,B,C,HL,SIGN,PARITY,HALFCARRY,ZERO
; Append opcode A followed by the word operand in HL.

EM_OPW:                        ; A is the opcode, HL its word operand.
    PUSH HL                        ; EM_BYTE clobbers HL.
    CALL EM_BYTE                   ; Emit the opcode.
    POP  HL                        ; Recover the operand.
    JR   EM_WORD                   ; Emit it, low byte first.

;@ROUTINE IN HL OUT CARRY CLOBBERS A,B,C,HL,SIGN,PARITY,HALFCARRY,ZERO
; Append CALL nn for the address in HL.

EM_CALL:                       ; HL is the routine to call.
    LD   A,$CD                     ; CALL nn.
    JR   EM_OPW                    ; Emit it with HL as nn.

;@ROUTINE IN HL OUT CARRY CLOBBERS A,B,C,HL,SIGN,PARITY,HALFCARRY,ZERO
; Append LD HL,nn for the word in HL.

EM_LDHL:                       ; HL is the value to load at run time.
    LD   A,$21                     ; LD HL,nn.
    JR   EM_OPW                    ; Emit it with HL as nn.

;@ROUTINE IN HL OUT CARRY CLOBBERS A,B,C,HL,SIGN,PARITY,HALFCARRY,ZERO
; Append LD BC,nn for the word in HL.

EM_LDBC:                       ; HL is the value to load at run time.
    LD   A,$01                     ; LD BC,nn.
    JR   EM_OPW                    ; Emit it with HL as nn.

;@ROUTINE IN HL OUT CARRY CLOBBERS A,B,C,HL,SIGN,PARITY,HALFCARRY,ZERO
; Append LD (nn),A for the address in HL.

EM_PUTA:                       ; HL is the address to store A into.
    LD   A,$32                     ; LD (nn),A.
    JR   EM_OPW                    ; Emit it with HL as nn.

;@ROUTINE IN DE OUT CARRY CLOBBERS A,B,C,HL,SIGN,PARITY,HALFCARRY,ZERO
; Append LD (nn),A where nn is the runtime-state byte at offset DE from
; RT_BASE, at the address the linked runtime gives it.

EM_TOVAR:                      ; DE is an offset into the runtime state.
    CALL TG_VAR                    ; HL is that state byte's target address.
    JR   EM_PUTA                   ; Emit the store into it.

;@ROUTINE IN A,C OUT CARRY CLOBBERS A,B,HL,SIGN,PARITY,HALFCARRY,ZERO
; Append opcode A followed by the byte operand in C.

EM_OPB:                        ; A is the opcode, C its byte operand.
    CALL EM_BYTE                   ; Emit the opcode; EM_BYTE keeps C.
    LD   A,C                       ; Then the operand.
    JP   EM_BYTE                   ; Emit it and return.

;@ROUTINE IN A OUT CARRY CLOBBERS A,B,C,HL,SIGN,PARITY,HALFCARRY,ZERO
; Append LD A,n for the byte in A.

EM_LDA:                        ; A is the value to load at run time.
    LD   C,A                       ; It becomes the operand.
    LD   A,$3E                     ; LD A,n.
    JR   EM_OPB                    ; Emit the pair.

;@ROUTINE OUT CARRY CLOBBERS A,BC,DE,HL,SIGN,PARITY,HALFCARRY,ZERO
; Append the normal end of the program: set the run state to RT_OK and
; jump to the startup code's terminal dispatch.

EM_DONE:                       ; The program has completed.
    LD   A,RT_OK                   ; Run state for normal completion.
    JR   EM_STOP                   ; Record it and leave through the terminal.

;@ROUTINE OUT CARRY CLOBBERS A,BC,DE,HL,SIGN,PARITY,HALFCARRY,ZERO
; Append the common trap record and terminal jump. At run time A carries
; the trap number and HL the source offset of the failing operation.

EM_TRAP:                       ; The generated code reaches here with A and HL set.
    LD   DE,RT_TNUM-RT_BASE        ; Address the trap-number byte.
    CALL EM_TOVAR                  ; Emit LD (RT_TNUM),A.
    CALL EM_OP                     ; Emit the inline opcode.
    DB   $AF                       ; XOR A: no trap subcode.
    LD   DE,RT_TSUB-RT_BASE        ; Address the subcode byte.
    CALL EM_TOVAR                  ; Emit LD (RT_TSUB),A.
    LD   DE,RT_TPOS-RT_BASE        ; Address the source-offset word.
    CALL TG_VAR                    ; HL is its target address.
    LD   A,$22                     ; LD (nn),HL.
    CALL EM_OPW                    ; Emit the store of the source offset.
    LD   A,RT_TRAP                 ; The run state that marks a trap.

;@ROUTINE IN A OUT CARRY CLOBBERS A,BC,DE,HL,SIGN,PARITY,HALFCARRY,ZERO
; Append the end of a run: store run state A in RT_RUN and jump to the
; terminal dispatch, through the far-jump vector when the code being
; emitted is not in the entry bank. BASIE.COM's target has one bank.

EM_STOP:                       ; A is the run state to record.
    CALL EM_LDA                    ; Emit LD A,state.
    LD   DE,RT_RUN-RT_BASE         ; Address the run-state byte.
    CALL EM_TOVAR                  ; Emit LD (RT_RUN),A.
    LD   A,(TG_EBANK)              ; Fetch the bank that holds the startup code.
    LD   D,A                       ; Keep it for the comparison.
    LD   A,(TG_OBANK)              ; Fetch the bank receiving this code.
    CP   D                         ; Is the terminal dispatch in the same bank?
    JR   Z,.NEAR                   ; Then a plain JP reaches it.
    LD   A,D                       ; The far jump needs the entry bank.
    CALL EM_LDA                    ; Emit LD A,bank.
    LD   HL,(TG_TERM)              ; HL is the terminal dispatch's address.
    CALL EM_LDHL                   ; Emit LD HL,terminal.
    LD   A,10                      ; Vector 10 jumps into another bank.
    JP   EM_JUMPV                  ; Emit JP through the runtime vector.
.NEAR:                         ; Same bank as the startup code.
    LD   HL,(TG_TERM)              ; HL is the terminal dispatch's address.
    LD   A,$C3                     ; JP nn.
    JR   EM_OPW                    ; Emit JP terminal.

;@ROUTINE OUT CARRY CLOBBERS A,BC,DE,HL,SIGN,PARITY,HALFCARRY,ZERO
; Set up an unhandled-error trap: at run time A carries the error a
; routine returned and HL the failing source offset. The caller then
; emits the trap body, which sees the trap number this loads into A.

EM_STRAY:                      ; A holds the error at run time.
    LD   DE,RT_TERR-RT_BASE        ; Address the unhandled-error byte.
    CALL EM_TOVAR                  ; Emit LD (RT_TERR),A.
    LD   A,6                       ; Trap number 6: unhandled error.
    JR   EM_LDA                    ; Emit LD A,6 for the trap body.

;@ROUTINE OUT DE,CARRY CLOBBERS A,B,HL,SIGN,PARITY,HALFCARRY,ZERO
; Append JR with a zero displacement; DE returns its address for EM_LAND.

EM_JR:                         ; An unconditional short branch.
    LD   A,$18                     ; JR e.
    JR   EM_JRCC                   ; Emit it with a placeholder.

;@ROUTINE OUT DE,CARRY CLOBBERS A,B,HL,SIGN,PARITY,HALFCARRY,ZERO
; Append JR NC with a zero displacement; DE returns its address. Runtime
; helpers report failure in carry, so this skips a failure path.

EM_JRNC:                       ; Branch when the helper succeeded.
    LD   A,$30                     ; JR NC,e.

;@ROUTINE IN A OUT DE,CARRY CLOBBERS A,B,HL,SIGN,PARITY,HALFCARRY,ZERO
; Append JR opcode A with a zero displacement and return its address in
; DE, for EM_LAND or EM_FIXJR to patch once the target is known.

EM_JRCC:                       ; A is a JR or JR cc opcode.
    CALL EM_BYTE                   ; Emit the opcode.
    LD   HL,(EM_PTR)               ; HL is where the displacement goes.
    PUSH HL                        ; Keep it for the caller.
    XOR  A                         ; A placeholder displacement.
    CALL EM_BYTE                   ; Emit it.
    POP  DE                        ; DE returns the displacement's address.
    RET                            ; Carry is clear from EM_BYTE.

;@ROUTINE IN DE,HL OUT CARRY CLOBBERS A,SIGN,PARITY,HALFCARRY,ZERO
; Patch the word operand at address DE with the value in HL.

EM_FIXW:                       ; DE is the operand, HL its value.
    PUSH BC                        ; Keep the caller's BC across the sink.
    LD   A,(TG_OBANK)              ; Fetch the bank that holds the operand.
    LD   C,A                       ; The sink takes the bank in C.
    CALL PUB_FIXW                  ; Rewrite the word; carry reports a sink failure.
    POP  BC                        ; Restore the caller's BC.
    JP   C,TG_FAIL                 ; A failed sink ends the compilation.
    OR   A                         ; Report success with carry clear.
    RET                            ; The operand now holds HL.

;@ROUTINE IN DE OUT CARRY CLOBBERS A,BC,DE,HL,SIGN,PARITY,HALFCARRY,ZERO
; Patch the JR displacement at DE to land at the current output position.

EM_LAND:                       ; DE is a JR displacement emitted earlier.
    LD   HL,(EM_PTR)               ; The target is the next byte to be emitted.
    JP   EM_FIXJR                  ; Patch the displacement to reach it.

; Read operands from the semantic transcript, which TR_CLOSE has closed.
; EM_READP overlays the retained forward signature (PR_FNAME), so reading
; may begin only after parsing. The operation count bounds the dispatch;
; each handler knows the fixed width of its operands.

RG_BEG:                        ; A Nucleus extent marker that nothing reads.

;@ROUTINE OUT A,CARRY,ZERO CLOBBERS HL,SIGN,PARITY,HALFCARRY
; Return the next transcript byte in A, with zero set when it is zero.

EM_READB:                      ; EM_READP addresses the next operand byte.
    LD   HL,(EM_READP)             ; HL is the read position.
    LD   A,(HL)                    ; Fetch the byte.
    INC  HL                        ; Advance past it.
    LD   (EM_READP),HL             ; Publish the new read position.
    OR   A                         ; Zero flag for callers testing a flag operand.
    RET                            ; Carry is clear.

;@ROUTINE OUT DE,CARRY CLOBBERS A,HL,SIGN,PARITY,HALFCARRY,ZERO
; Return the next transcript word in DE; words are stored low byte first.

EM_READW:                      ; The next two operand bytes form a word.
    CALL EM_READB                  ; Read the low byte.
    LD   E,A                       ; It is the word's low half.
    CALL EM_READB                  ; Read the high byte.
    LD   D,A                       ; DE is the word.
    RET                            ; Carry is clear from EM_READB.

; A global's word operand has bit 15 set for zero-initialised storage
; (bss) and its offset from the region's base in the low 15 bits. Both
; bases are fixed when the target opens, before any code is emitted, so
; the address is final. Scalar locals use the IX frame instead (GT_ENTER).

;@ROUTINE OUT HL,CARRY CLOBBERS A,DE,SIGN,PARITY,HALFCARRY,ZERO
; Read a global's tagged word operand and return its target address in HL.

EM_READA:                      ; The next word is a global's tagged offset.
    CALL EM_READW                  ; DE is the tagged offset.
    BIT  7,D                       ; Is it in zero-initialised storage?
    JR   Z,.DATA                   ; No: it is initialised data.
    RES  7,D                       ; Strip the tag; DE is the offset into bss.
    LD   HL,(TG_BSS)               ; HL is the bss base.
    JR   .OFFSET                   ; Add the offset.
.DATA:                         ; An initialised global.
    LD   HL,(TG_CDATA)             ; HL is the initialised-data base.
.OFFSET:                       ; HL is the region base, DE the offset.
    ADD  HL,DE                     ; HL is the global's target address.
    OR   A                         ; Report success with carry clear.
    RET                            ; The caller emits an access to HL.

;@ROUTINE OUT CARRY CLOBBERS A,B,HL,SIGN,PARITY,HALFCARRY,ZERO
; Append the frame epilogue GT_LEAVE: drop the locals and restore the
; caller's IX. The caller emits the RET that follows.

EM_LEAVE:                      ; The routine is returning.
    LD   HL,GT_LEAVE               ; The four-byte epilogue.
    JP   EM_FOUR                   ; Emit it.

; The routine frame. GT_ENTER saves the caller's IX and points IX at the
; new frame; locals are then reserved below IX and addressed at negative
; displacements, so they stay per activation. The expression stack lies
; below the locals and is empty at every statement boundary.

GT_ENTER:                      ; Eight bytes: the frame prologue.
    DB   $DD,$E5,$DD,$21,$00,$00,$DD,$39 ; PUSH IX / LD IX,0 / ADD IX,SP: IX = frame.
GT_LEAVE:                      ; Four bytes: the frame epilogue.
    DB   $DD,$F9,$DD,$E1           ; LD SP,IX / POP IX: drop locals, restore IX.
