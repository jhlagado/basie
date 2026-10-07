;==========================================================================
;  Branch shrinking
;==========================================================================
;
;  Choose which of a routine's jumps to its own labels become JR, as the
;  reference compiler's Blob.finish does (ref/compile/emit.ts
;  shrinkJumps), once the whole routine is in the blob writer's buffers;
;  BL_END then writes it shrunk, every offset moved by BL_MAP.
;
;  The candidates are the jumps the reference records: JP and JP NZ, Z,
;  NC or C to a label of the routine. Every such operand is a reference
;  to the routine itself (EM_LREF), its addend the label's offset, and no
;  other self-reference follows one of those five opcodes (the others are
;  LD HL,(need) and LD HL,literal), so the candidates are found among the
;  kept references rather than recorded as they are written.
;
;  The rule is the reference's: every candidate starts short, and each
;  pass drops those whose JR would not reach, until a pass drops none.
;  Dropping one only lengthens the distances of the others, so the fixed
;  point does not depend on the order of the drops, and each is dropped
;  as soon as it is found.
;
;  Principal entry:
;    BL_SHORT  choose the routine's short jumps
;
;  The short jumps are a table in the free memory between the blob's bytes
;  and its log (its start BL_JUMPS, its end BL_JPEND, in the blob writer's
;  workspace): four
;  bytes each, the jump's offset and its target's, in offset order, then
;  a sentinel whose offset, BL_PAST, is past every routine's and has bit
;  14 set, which no jump's offset has.

;@ROUTINE CLOBBERS A,BC,DE,HL,CARRY,ZERO,SIGN,PARITY,HALFCARRY
; Choose the short jumps of the routine the blob writer is building,
; building their table in the free memory between its bytes and its log
; (BL_SPAN; DG_ROOM when it does not fit there).

BL_SHORT:                      ; The routine is complete.
    CALL BL_SPAN                   ; HL is free memory, DE its end.
    LD   (BL_JUMPS),HL             ; The table starts there; until it
    LD   (BL_JPEND),DE             ; is built, its end is the memory's.
    PUSH HL                        ; Its next entry.
    LD   HL,(NH_PTR)               ; From the log's first entry.
.SCAN:                         ; HL is an entry, or the heap.
    CALL BL_NEXT                   ; The next:
    JR   C,.SCANNED                ; none, and the table is complete;
    JR   Z,.SCAN                   ; a line entry, passed over.
    PUSH HL                        ; A reference: kept.
    INC  HL                        ; Past its form,
    LD   E,(HL)                    ; DE
    INC  HL                        ; is
    LD   D,(HL)                    ; its
    INC  HL                        ; offset.
    LD   A,(BL_ORD)                ; Is its target
    CP   (HL)                      ; the routine
    JR   NZ,.NEXT                  ; itself?
    INC  HL                        ; Both
    LD   A,(BL_ORD+1)              ; bytes
    CP   (HL)                      ; must
    JR   NZ,.NEXT                  ; match.
    INC  HL                        ; BC
    LD   C,(HL)                    ; is its
    INC  HL                        ; addend:
    LD   B,(HL)                    ; the label's offset.
    LD   HL,(BL_CBASE)             ; The byte
    DEC  HL                        ; before
    ADD  HL,DE                     ; the operand
    LD   A,(HL)                    ; is the opcode:
    CP   $C3                       ; JP,
    JR   Z,.JUMP                   ; or
    AND  $E7                       ; JP NZ, Z, NC or C, $C2 with
    CP   $C2                       ; the condition in bits 3 and 4?
    JR   NZ,.NEXT                  ; Any other: not a jump.
.JUMP:                         ; DE is the operand's offset, BC the target's.
    DEC  DE                        ; The jump's own offset.
    POP  HL                        ; The reference,
    EX   (SP),HL                   ; kept; HL is the table's next entry.
    CALL .ENTER                    ; The jump's offset,
    LD   D,B                       ; then
    LD   E,C                       ; its target's.
    CALL .ENTER                    ; The entry is made.
    EX   (SP),HL                   ; The table's next kept,
    JR   .SCAN                     ; the next entry.
.NEXT:                         ; Not a jump of the routine.
    POP  HL                        ; The reference;
    JR   .SCAN                     ; the next entry.
.SCANNED:                      ; Every candidate is in the table.
    POP  HL                        ; The table's next entry
    LD   DE,BL_PAST                ; is the sentinel:
    CALL .ENTER                    ; its offset; its target is not read.
    DEC  HL                        ; HL is the
    DEC  HL                        ; sentinel's entry,
    LD   (BL_JPEND),HL             ; the table's end.
.PASS:                         ; Every short jump is tested.
    PUSH HL                        ; The end before the pass.
    LD   HL,(BL_JUMPS)             ; From the first entry.
.TEST:                         ; HL is an entry.
    LD   E,(HL)                    ; DE
    INC  HL                        ; is
    LD   D,(HL)                    ; the jump's
    INC  HL                        ; offset.
    BIT  6,D                       ; The sentinel's?
    JR   NZ,.PASSED                ; Then the pass is over.
    LD   A,(HL)                    ; HL
    INC  HL                        ; is
    PUSH HL                        ; (the entry's last byte kept)
    LD   H,(HL)                    ; its target's
    LD   L,A                       ; offset.
    CALL BL_MAP                    ; Where the target moves to,
    EX   DE,HL                     ; kept in DE, and
    CALL BL_MAP                    ; where the jump moves to.
    EX   DE,HL                     ; The distance from it,
    SBC  HL,DE                     ; less (carry is clear)
    LD   DE,128-2                  ; the JR's two bytes, plus 128,
    ADD  HL,DE                     ; is below 256 only when
    LD   A,H                       ; a JR reaches:
    OR   A                         ; a zero high byte.
    POP  HL                        ; The entry's last byte;
    INC  HL                        ; the next entry.
    JR   Z,.TEST                   ; It reaches: test the next.
    PUSH HL                        ; It does not: it is dropped,
    LD   BC,-4                     ; and the entries after it
    ADD  HL,BC                     ; move down
    EX   DE,HL                     ; to it.
    LD   HL,(BL_JPEND)             ; The table
    ADD  HL,BC                     ; ends four bytes
    LD   (BL_JPEND),HL             ; sooner.
    INC  HL                        ; The bytes to move run
    INC  HL                        ; to the sentinel's offset's end:
    OR   A                         ; the new end plus two,
    SBC  HL,DE                     ; less
    LD   B,H                       ; the dropped
    LD   C,L                       ; entry.
    POP  HL                        ; From the next entry
    PUSH DE                        ; (the dropped one's place kept)
    LDIR                           ; to the dropped one's.
    POP  HL                        ; Test the entry
    JR   .TEST                     ; now there.
.PASSED:                       ; HL is the sentinel's entry, plus two.
    DEC  HL                        ; HL is
    DEC  HL                        ; the end after the pass.
    POP  DE                        ; The end before it.
    OR   A                         ; If the pass
    SBC  HL,DE                     ; dropped any,
    ADD  HL,DE                     ; (HL restored)
    JR   NZ,.PASS                  ; test them all again.
    RET                            ; Every short jump reaches.

;@ROUTINE IN DE,HL OUT HL CLOBBERS A,CARRY,ZERO,SIGN,PARITY,HALFCARRY
; Append the word DE to the table at HL, unless it would reach the free
; memory's end, BL_JPEND while the table is built (DG_ROOM). HL returns
; past it. BC and DE are kept.

.ENTER:                        ; DE is the word, HL where it goes.
    PUSH HL                        ; Keep the place.
    INC  HL                        ; Its second byte
    PUSH DE                        ; (the word kept)
    LD   DE,(BL_JPEND)             ; must be below
    OR   A                         ; the end:
    SBC  HL,DE                     ; carry if it is.
    POP  DE                        ; The word.
    POP  HL                        ; The place.
    JP   NC,MM_FULL                ; No room for the table.
    LD   (HL),E                    ; Low byte,
    INC  HL                        ; then
    LD   (HL),D                    ; high byte.
    INC  HL                        ; HL is past it.
    RET                            ; Done.
