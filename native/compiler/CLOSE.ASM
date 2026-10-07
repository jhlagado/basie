;==========================================================================
;  A routine ended
;==========================================================================
;
;  The end of a routine (RG_CLOSE): its exit, its frame and need, then its
;  blob written by the blob writer's end (BLEND.ASM, BL_END), with branch
;  shrinking (SHRINK.ASM). Resident: every routine ends here, and every
;  blob is written by BL_END, so as an overlay it was loaded again after
;  each use of FLOAT or OWNERS, which shared its place.
;
;  Principal entry:
;    RG_CLOSE  end the routine and write it

;@ROUTINE OUT HL CLOBBERS A,BC,DE,IX,CARRY,ZERO,SIGN,PARITY,HALFCARRY
; End the routine: the success return if its end is reachable (CT_FALLS),
; the exit sequence, the frame patched into the prologue, the frame and
; need words, then write the blob and its name, and after it the blobs of
; its waiting aggregate constants (RG_DEFER). HL returns the need.

RG_CLOSE:                      ; The routine's `end` has been parsed.
    LD   A,(CT_FALLS)              ; Can control reach the end?
    OR   A                         ; Zero if every path has left.
    CALL NZ,RG_RET                 ; Falling off the end is success.
    LD   A,RG_EXIT                 ; The exit sequence starts here.
    CALL EM_LDEF                   ; Every return jumps to it.
    LD   A,(RO_CARGS)              ; Has the routine arguments to remove?
    OR   A                         ; Zero if it has none.
    JR   NZ,.RETN                  ; Then RETN removes them.
    CALL EM_SEQ                    ; With no arguments to remove:
    DB   5,$DD,$F9,$DD,$E1,$C9     ; LD SP,IX, POP IX, RET.
    JR   .EXITED                   ; The exit is written.
.RETN:                         ; A is the arguments' bytes.
    LD   L,A                       ; HL is the bytes
    LD   H,0                       ; as a word.
    CALL EM_SEQ                    ; LD IY,n:
    DB   2,$FD,$21                 ; the opcode,
    CALL EM_WORD                   ; and the bytes as its operand.
    CALL EM_JPH                    ; JP RETN, which removes them,
    DW   HP_RETN                   ; its ordinal and stack figure.
.EXITED:                       ; The frame and need words follow.
    LD   HL,(EM_DEEP)              ; The frame: the deepest point reached.
    LD   DE,(RG_LARGE)             ; Is it the largest of any routine?
    OR   A                         ; Clear carry.
    SBC  HL,DE                     ; Carry if it is not.
    ADD  HL,DE                     ; HL is the frame again.
    JR   C,.SMALLER                ; Keep the larger one.
    LD   (RG_LARGE),HL             ; It is the largest frame.
.SMALLER:                      ; HL is the frame.
    XOR  A                         ; Negate it:
    SUB  L                         ; zero less the low byte,
    LD   E,A                       ; with a borrow
    SBC  A,A                       ; unless it was zero,
    SUB  H                         ; less the high byte:
    LD   D,A                       ; DE is the prologue's operand.
    PUSH HL                        ; Keep the frame for its word.
    LD   HL,(RG_PATCH)             ; Its offset in the blob,
    LD   BC,BL_CODE                ; plus the buffer's address,
    ADD  HL,BC                     ; is where it goes.
    LD   (HL),E                    ; Low byte,
    INC  HL                        ; then
    LD   (HL),D                    ; high byte.
    POP  HL                        ; HL is the frame.
    PUSH HL                        ; Keep it for the need.
    CALL EM_WORD                   ; The frame word.
    LD   A,RG_PAIR                 ; The need word follows it,
    CALL EM_LDEF                   ; where the pair label points.
    POP  HL                        ; The need: the frame,
    LD   DE,(EM_STACK)             ; the largest helper's stack,
    ADD  HL,DE                     ; added,
    LD   DE,(EM_NEED)              ; the largest callee's need,
    ADD  HL,DE                     ; added,
    LD   DE,4                      ; and four bytes for IX and the
    ADD  HL,DE                     ; return address.
    PUSH HL                        ; Keep it to return.
    CALL EM_WORD                   ; The need word.
    CALL GA_LITS                   ; The string literals follow it.
    CALL RG_SPAN                   ; DE is the free memory's end,
    LD   HL,(RG_PEND)              ; after the waiting constants:
    CALL BL_SHORT                  ; room to shrink its jumps.
    CALL BL_END                    ; Write the blob.
    LD   HL,(BL_ORD)               ; Its ordinal.
    LD   DE,(RG_NAME)              ; Its name,
    LD   A,(RG_NLEN)               ; of this
    LD   B,A                       ; length.
    CALL BL_NAME                   ; Record it.
    CALL RG_SPAN                   ; Then the waiting constants,
.NEXT:                         ; from HL:
    LD   DE,(RG_PEND)              ; any
    OR   A                         ; left
    SBC  HL,DE                     ; before
    ADD  HL,DE                     ; the end?
    JR   Z,.DONE                   ; No: done.
    LD   E,(HL)                    ; DE is
    INC  HL                        ; its
    LD   D,(HL)                    ; ordinal,
    INC  HL                        ; kept
    PUSH DE                        ; for its name;
    LD   C,(HL)                    ; BC is
    INC  HL                        ; its
    LD   B,(HL)                    ; size.
    INC  HL                        ; Its bytes follow:
    PUSH HL                        ; kept.
    EX   DE,HL                     ; HL is the ordinal:
    LD   A,BL_KRO                  ; read-only data
    CALL BL_BEGIN                  ; begins; BC is kept.
    POP  HL                        ; BC bytes at HL
    CALL RG_WRITE                  ; are appended and the blob written.
    LD   E,(HL)                    ; DE is
    INC  HL                        ; its
    LD   D,(HL)                    ; name,
    INC  HL                        ; B
    LD   B,(HL)                    ; its
    INC  HL                        ; length.
    EX   (SP),HL                   ; HL is the ordinal, the next kept.
    CALL BL_NAME                   ; The name is recorded.
    POP  HL                        ; The next.
    JR   .NEXT                     ; Write it.
.DONE:                         ; Every constant is written.
    POP  HL                        ; HL is the need.
    RET                            ; The routine is written.
