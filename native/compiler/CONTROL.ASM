;==========================================================================
;  Structured control: frames, labels and counted-loop records
;==========================================================================
;
;  The support the grammar actions use to parse if, while, for, exit,
;  continue and handle. Each open construct has a control frame; its
;  labels are numbered here and the actions append OP_LABEL, OP_JUMP and
;  OP_IFNOT operations that name them. Their code generation moves to
;  blob output at 65.4 (f); until then the transcript refuses them.
;
;  Principal entries:
;    CT_PUSH   open a frame of a given kind
;    CT_POP    close the innermost frame
;    CT_TOP    address the innermost frame
;    CT_FIELD  address one field of the innermost frame
;    CT_OPEN   open a frame and number its first label (CT_FDEST)
;    CT_ALLOT  number a new label into a frame field (CT_EXIT, CT_LABEL)
;    CT_PLACE, CT_JUMP, CT_IFNOT  append a label, jump or false-branch
;    CT_LOOP   find the innermost while or for frame
;    CT_GUARD  reject a write to an active for counter
;    CT_NOTE   record that the current if arm falls through
;    CT_STEP   parse a for loop's constant step
;    CT_SETUP, CT_TEST, CT_AGAIN  append a for loop's three operations
;
;  Frames (STATE.ASM). CT_DEPTH counts the open frames, at most CT_FCAP
;  (8); frame n is the CT_FLEN (10) bytes at CT_FTAB+10n. The fields are:
;    CT_FKIND  +0  CT_KIF, CT_KLOOP (while), CT_KFOR or CT_KTRAP (handle)
;    CT_FDEST  +1  label: an if's next arm, a loop's test, a handler's body
;    CT_FCONT  +2  label: where continue goes
;    CT_FEXIT  +3  label: the end of the construct
;    CT_FVAR   +4  for: the counter's frame offset; if: 1 while no arm has
;                  fallen through; otherwise CT_NOVAR
;    CT_FMODE  +5  for: bit 0 to (inclusive), bit 1 downward, bit 2 u16;
;                  if: 1 once an else arm has been seen
;    CT_FSTEP  +6  for: the step magnitude (word)
;    CT_FTRAP  +8  for: the source offset reported by an overflow trap
;
;  Labels are numbered from zero in CT_LABNO for the whole program; the
;  routine bodies own labels RO_MDEST (27) to 31, so control flow has
;  labels 0 to 26 (CT_LLIM) and a 28th raises DG_LABEL.

;@ROUTINE IN A OUT A,DE,HL,CARRY,ZERO CLOBBERS SIGN,PARITY,HALFCARRY
; Return in HL the address of frame A, CT_FTAB+10A. A is unchanged.

CT_FRAME:
    LD   L,A                       ; Widen the frame index...
    LD   H,0                       ; ...into HL.
    ADD  HL,HL                     ; HL is 2A.
    LD   E,L                       ; Keep 2A...
    LD   D,H                       ; ...in DE.
    ADD  HL,HL                     ; HL is 4A.
    ADD  HL,HL                     ; HL is 8A.
    ADD  HL,DE                     ; HL is 10A, the frame's offset.
    LD   DE,CT_FTAB                ; The frame table.
    ADD  HL,DE                     ; HL addresses frame A.
    OR   A                         ; Clear carry.
    RET                            ; A is still the index.

;@ROUTINE IN A OUT A,DE,HL,CARRY,ZERO CLOBBERS SIGN,PARITY,HALFCARRY,B
; Open a frame of kind A (CT_K) and return its address in HL. Every field
; is cleared except CT_FVAR, which is CT_NOVAR. A ninth frame raises
; DG_NEST.

CT_PUSH:
    LD   B,A                       ; Keep the kind.
    LD   A,(CT_DEPTH)              ; The new frame's index is the current depth.
    CP   CT_FCAP                   ; Are all frames in use?
    JR   NC,CT_EDEEP               ; Raise DG_NEST.
    PUSH AF                        ; Keep the index.
    CALL CT_FRAME                  ; HL addresses the new frame.
    POP  AF                        ; Recover the index.
    INC  A                         ; One more frame is open.
    LD   (CT_DEPTH),A              ; Commit the depth.
    LD   (HL),B                    ; Store the kind in CT_FKIND.
    INC  HL                        ; Step to the first field after the kind.
    LD   B,CT_FLEN-1               ; Clear the other nine bytes.
    XOR  A                         ; Zero for each of them.
.CLEAR:                        ; Clear one byte of the frame.
    LD   (HL),A                    ; Zero it.
    INC  HL                        ; Step to the next.
    DJNZ .CLEAR                    ; Until the frame is clear.
    LD   A,(CT_DEPTH)              ; Recompute the frame's address...
    DEC  A                         ; ...from its index.
    CALL CT_FRAME                  ; HL addresses the new frame again.
    PUSH HL                        ; Keep it for the caller.
    LD   DE,CT_FVAR                ; Address its counter field.
    ADD  HL,DE                     ; HL addresses CT_FVAR.
    LD   (HL),CT_NOVAR             ; No counter until a for says otherwise.
    POP  HL                        ; Return the frame's address.
    OR   A                         ; Clear carry.
    RET                            ; A is the frame's index.

;@ROUTINE NORETURN
; Raise DG_NEST: constructs are nested more than CT_FCAP deep.

CT_EDEEP:
    CALL DG_RAISE                  ; Abandon the build.
    DB   DG_NEST                   ; Nesting too deep.

;@ROUTINE OUT A,DE,HL,CARRY,ZERO CLOBBERS SIGN,PARITY,HALFCARRY
; Return the innermost frame's address in HL. With no frame open this
; raises DG_LOOP, though every caller runs inside a frame.

CT_TOP:
    LD   A,(CT_DEPTH)              ; How many frames are open?
    OR   A                         ; None?
    JR   Z,CT_ELOOP                ; Raise DG_LOOP.
    DEC  A                         ; The innermost is at depth minus one.
    JR   CT_FRAME                  ; Return its address.

;@ROUTINE IN B OUT A,DE,HL,CARRY,ZERO CLOBBERS SIGN,PARITY,HALFCARRY
; Return in HL the address of field B (a CT_F offset) of the innermost
; frame.

CT_FIELD:
    CALL CT_TOP                    ; HL addresses the innermost frame.
    LD   E,B                       ; Widen the field offset...
    LD   D,0                       ; ...into DE.
    ADD  HL,DE                     ; HL addresses the field.
    OR   A                         ; Clear carry.
    RET                            ; The field is ready to read or write.

;@ROUTINE OUT A,CARRY,ZERO CLOBBERS SIGN,PARITY,HALFCARRY,HL
; Close the innermost frame. With no frame open this raises DG_LOOP.

CT_POP:
    LD   HL,CT_DEPTH               ; Address the frame count.
    LD   A,(HL)                    ; Fetch it.
    OR   A                         ; Is any frame open?
    JR   Z,CT_ELOOP                ; No: raise DG_LOOP.
    DEC  (HL)                      ; Close the innermost frame.
    XOR  A                         ; Report success with carry clear.
    RET                            ; The enclosing frame is now innermost.

;@ROUTINE OUT A,C,DE,HL,CARRY,ZERO CLOBBERS SIGN,PARITY,HALFCARRY,B
; Number a new label as the innermost frame's exit (CT_FEXIT).

CT_EXIT:
    LD   B,CT_FEXIT                ; Select the exit field; fall into CT_ALLOT.

;@ROUTINE IN B OUT A,C,DE,HL,CARRY,ZERO CLOBBERS SIGN,PARITY,HALFCARRY
; Number the next label, store it in field B of the innermost frame and
; return it in C, with HL addressing the field. Past CT_LLIM labels this
; raises DG_LABEL.

CT_ALLOT:
    LD   A,(CT_LABNO)              ; The next free label number.
    CP   CT_LLIM                   ; Labels from RO_MDEST up belong to routines.
    JR   NC,CT_ELABS               ; Raise DG_LABEL.
    LD   C,A                       ; C is the new label.
    INC  A                         ; Advance the label counter.
    LD   (CT_LABNO),A              ; Commit it.
    CALL CT_FIELD                  ; HL addresses field B.
    LD   (HL),C                    ; Store the label there.
    RET                            ; Return the label in C.

;@ROUTINE IN B OUT A,C,DE,HL,CARRY,ZERO CLOBBERS SIGN,PARITY,HALFCARRY,B
; Open a frame of kind B, saving the enclosing fallthrough state (AC_NEST),
; and number its CT_FDEST label.

CT_OPEN:
    CALL AC_NEST                   ; Push the frame; fall into CT_LABEL.

;@ROUTINE OUT A,C,DE,HL,CARRY,ZERO CLOBBERS SIGN,PARITY,HALFCARRY,B
; Number a new label as the innermost frame's CT_FDEST.

CT_LABEL:
    LD   B,CT_FDEST                ; Select the destination field.
    JR   CT_ALLOT                  ; Number the label into it.

;@ROUTINE NORETURN
; Raise DG_LABEL: the program needs more than CT_LLIM control labels.

CT_ELABS:
    CALL DG_RAISE                  ; Abandon the build.
    DB   DG_LABEL                  ; Too many labels.

;@ROUTINE NORETURN
; Raise DG_LOOP: exit or continue outside any loop, or no frame open.

CT_ELOOP:
    CALL DG_RAISE                  ; Abandon the build.
    DB   DG_LOOP                   ; Not inside a loop.

;@ROUTINE IN C,D OUT A,CARRY,ZERO CLOBBERS SIGN,PARITY,HALFCARRY,B,DE,HL
; Append operation D with the label C as its operand.

CT_EMIT:
    LD   A,D                       ; The opcode.
    CALL TR_OPER                   ; Append and count it.
    LD   A,C                       ; The label operand.
    JP   TR_PUT                    ; Append it and return.

;@ROUTINE IN C OUT A,CARRY,ZERO CLOBBERS SIGN,PARITY,HALFCARRY,B,DE,HL
; Append OP_LABEL C: label C is here.

CT_PLACE:
    LD   D,OP_LABEL                ; Place a label.
    JR   CT_EMIT                   ; Append it with C.

;@ROUTINE IN C OUT A,CARRY,ZERO CLOBBERS SIGN,PARITY,HALFCARRY,B,DE,HL
; Append OP_IFNOT C: pop the condition and go to label C when it is false.

CT_IFNOT:
    LD   D,OP_IFNOT                ; Branch when false.
    JR   CT_EMIT                   ; Append it with C.

;@ROUTINE IN C OUT A,CARRY,ZERO CLOBBERS SIGN,PARITY,HALFCARRY,B,DE,HL
; Append OP_JUMP C: go to label C.

CT_JUMP:
    LD   D,OP_JUMP                 ; Unconditional jump.
    JR   CT_EMIT                   ; Append it with C.

;@ROUTINE OUT A,DE,HL,CARRY,ZERO CLOBBERS SIGN,PARITY,HALFCARRY
; Return in HL the innermost while or for frame, skipping if and handle
; frames. Outside every loop this raises DG_LOOP.

CT_LOOP:
    LD   A,(CT_DEPTH)              ; How many frames are open?
    OR   A                         ; None?
    JR   Z,CT_ELOOP                ; Then exit or continue has no loop.
.NEXT:                         ; Try the frame below index A.
    DEC  A                         ; A is the next frame outward.
    PUSH AF                        ; Keep the index.
    CALL CT_FRAME                  ; HL addresses frame A.
    LD   A,(HL)                    ; Fetch its kind.
    CP   CT_KLOOP                  ; A while loop?
    JR   Z,.FOUND                  ; Yes.
    CP   CT_KFOR                   ; A for loop?
    JR   Z,.FOUND                  ; Yes.
    POP  AF                        ; Recover the index.
    OR   A                         ; Was that the outermost frame?
    JR   NZ,.NEXT                  ; No: look further out.
    JR   CT_ELOOP                  ; Yes: no loop encloses the statement.
.FOUND:                        ; HL addresses the loop's frame.
    POP  AF                        ; Discard the index.
    OR   A                         ; Clear carry.
    RET                            ; Return the frame in HL.

;@ROUTINE IN C OUT A,CARRY,ZERO CLOBBERS SIGN,PARITY,HALFCARRY,DE,HL
; C is a local's frame offset. Raise DG_INUSE if that local is the counter
; of any open for loop, so the body can neither assign it nor reuse it as
; a nested counter.

CT_GUARD:
    LD   A,(CT_DEPTH)              ; How many frames are open?
    OR   A                         ; None?
    RET  Z                         ; Then no counter is active.
.NEXT:                         ; Check the frame below index A.
    DEC  A                         ; A is the next frame outward.
    PUSH AF                        ; Keep the index.
    CALL CT_FRAME                  ; HL addresses frame A.
    LD   A,(HL)                    ; Fetch its kind.
    CP   CT_KFOR                   ; Only for frames have counters.
    JR   NZ,.SKIP                  ; Skip any other kind.
    LD   DE,CT_FVAR                ; Address the counter field.
    ADD  HL,DE                     ; HL addresses CT_FVAR.
    LD   A,(HL)                    ; Fetch the counter's offset.
    CP   C                         ; Is it this local?
    JR   Z,.ACTIVE                 ; Yes: the local is in use.
.SKIP:                         ; This frame does not hold the local.
    POP  AF                        ; Recover the index.
    OR   A                         ; Was that the outermost frame?
    JR   NZ,.NEXT                  ; No: check further out.
    RET                            ; The local is free.
.ACTIVE:                       ; The local counts an open loop.
    POP  AF                        ; Balance the stack.
    CALL DG_RAISE                  ; Abandon the build.
    DB   DG_INUSE                  ; Counter in use.

;@ROUTINE OUT A,DE,HL,CARRY,ZERO CLOBBERS SIGN,PARITY,HALFCARRY,B
; If the current if arm falls through (CT_FALLS), clear the innermost
; frame's CT_FVAR, so the if as a whole falls through. Returns A zero.

CT_NOTE:
    LD   A,(CT_FALLS)              ; Can control reach the end of this arm?
    OR   A                         ; Zero means the arm ends in a transfer.
    RET  Z                         ; Then the frame's flag stands.
    LD   B,CT_FVAR                 ; Select the if frame's flag.
    CALL CT_FIELD                  ; HL addresses it.
    LD   (HL),0                    ; Some arm falls through.
    XOR  A                         ; Return A zero with carry clear.
    RET                            ; The flag is updated.

;@ROUTINE OUT A,B,DE,CARRY,ZERO CLOBBERS SIGN,PARITY,HALFCARRY,C,HL
; Parse a for loop's step: an optional sign, then a number, a constant or
; an error constant, which must be nonzero. Return the magnitude in DE and
; in B the mode bits, 2 for a downward step. Anything else raises DG_STEP.

CT_STEP:
    XOR  A                         ; Assume an upward step.
    LD   (EX_LMETA),A              ; EX_LMETA is free scratch for the mode.
    CALL PR_PEEK                   ; Look for a sign.
    CP   TK_PLUS                   ; An explicit plus?
    JR   Z,.PLUS                   ; Consume it.
    CP   TK_MINUS                  ; A minus?
    JR   NZ,.AMOUNT                ; No sign: read the amount.
    LD   A,2                       ; Mode bit 1: a downward step.
    LD   (EX_LMETA),A              ; Record it.
.PLUS:                         ; A sign is next.
    CALL PR_TAKE                   ; Consume it.
.AMOUNT:                       ; The step's value is next.
    CALL PR_TAKE                   ; A is its kind, BC its payload.
    CP   TK_NUM                    ; A literal number?
    JR   Z,.NUMBER                 ; Its value is in BC.
    CP   TK_NAME                   ; A name?
    JR   NZ,.BAD                   ; Anything else is not a step.
    CALL RO_LIB                    ; Is it a predefined name?
    JR   NC,.CONST                 ; No: it must be a declared constant.
    CP   RO_ERRS                   ; A service is not a value.
    JR   C,.BAD                    ; Reject it.
    SUB  RO_ERRS-1                 ; An error constant's value is 1..4.
    LD   D,0                       ; Widen it...
    LD   E,A                       ; ...into DE.
    JR   .NONZERO                  ; It is never zero; share the exit.
.CONST:                        ; The name must be a scalar constant.
    CALL SY_GET                    ; A is its class and type, BC its value.
    LD   D,A                       ; Keep the class and type.
    AND  SY_TYPE+SY_AGGR           ; A type or an aggregate?
    JR   NZ,.BAD                   ; Neither is a step.
    LD   A,D                       ; Recover the class.
    AND  SY_CMASK                  ; A variable has a class; a constant has none.
    JR   NZ,.BAD                   ; Reject a variable.
    LD   A,D                       ; Recover the type.
    AND  SY_TMASK                  ; Isolate it.
    CP   SY_BOOL                   ; A Boolean constant?
    JR   Z,.BAD                    ; Is not a number.
.NUMBER:                       ; BC holds the value.
    LD   D,B                       ; Move it...
    LD   E,C                       ; ...to DE.
.NONZERO:                      ; DE is the magnitude.
    LD   A,D                       ; Is it zero?
    OR   E                         ; A zero step would never finish.
    JR   Z,.BAD                    ; Reject it.
    LD   A,(EX_LMETA)              ; Recover the mode bits.
    LD   B,A                       ; Return them in B.
    OR   A                         ; Clear carry.
    RET                            ; DE is the magnitude.
.BAD:                          ; Not a usable step.
    CALL DG_RAISE                  ; Abandon the build.
    DB   DG_STEP                   ; Bad step.

;@ROUTINE NORETURN
; Raise DG_COUNT: a for counter must be a non-Boolean scalar local.

CT_EVAR:
    CALL DG_RAISE                  ; Abandon the build.
    DB   DG_COUNT                  ; Bad counter.

;@ROUTINE IN A,HL OUT A,HL,CARRY,ZERO CLOBBERS SIGN,PARITY,HALFCARRY,B,DE
; Append opcode A and the counter of the for frame at HL. HL returns
; addressing the frame's CT_FMODE.

CT_FOROP:
    PUSH HL                        ; TR_OPER clobbers HL.
    CALL TR_OPER                   ; Append and count the opcode.
    POP  HL                        ; Recover the frame.
    LD   DE,CT_FVAR                ; Address its counter field.
    ADD  HL,DE                     ; HL addresses CT_FVAR.
    LD   A,(HL)                    ; The counter's frame offset.
    CALL TR_PUTHL                  ; Append it.
    INC  HL                        ; HL addresses CT_FMODE.
    RET                            ; The caller appends from here.

;@ROUTINE IN HL OUT A,CARRY,ZERO CLOBBERS SIGN,PARITY,HALFCARRY,B,DE,HL
; Append OP_FOR counter,mode for the for frame at HL.

CT_SETUP:
    LD   A,OP_FOR                  ; Set up the counted loop.
    CALL CT_FOROP                  ; Append it with the counter.
    LD   A,(HL)                    ; The mode.
    JP   TR_PUT                    ; Append it and return.

;@ROUTINE OUT A,CARRY,ZERO CLOBBERS SIGN,PARITY,HALFCARRY,B,DE,HL
; Append OP_TEST counter,mode,exit for the innermost frame, a for loop.

CT_TEST:
    CALL CT_TOP                    ; HL addresses the for frame.
    LD   A,OP_TEST                 ; Test the bound at the loop's top.
    CALL CT_FOROP                  ; Append it with the counter.
    LD   A,(HL)                    ; The mode.
    CALL TR_PUTHL                  ; Append it.
    LD   B,CT_FEXIT                ; Select the exit label.
    CALL CT_FIELD                  ; HL addresses it.
    LD   A,(HL)                    ; The exit label.
    JP   TR_PUT                    ; Append it and return.

;@ROUTINE IN B,HL OUT A,B,HL,CARRY,ZERO CLOBBERS SIGN,PARITY,HALFCARRY,DE
; Append the B bytes at HL; HL returns past them and B zero.

CT_BYTES:
    LD   A,(HL)                    ; Fetch the next byte.
    PUSH BC                        ; TR_PUTHL clobbers B.
    CALL TR_PUTHL                  ; Append it.
    POP  BC                        ; Recover the count.
    INC  HL                        ; Step to the next byte.
    DJNZ CT_BYTES                  ; Until B bytes are appended.
    RET                            ; HL is past them.

;@ROUTINE OUT A,CARRY,ZERO CLOBBERS SIGN,PARITY,HALFCARRY,B,DE,HL
; Append OP_NEXT top,exit,counter,mode,step,offset for the innermost
; frame, a for loop: eight operand bytes taken from the frame.

CT_AGAIN:
    CALL CT_TOP                    ; HL addresses the for frame.
    PUSH HL                        ; TR_OPER clobbers HL.
    LD   A,OP_NEXT                 ; Step the counter and loop.
    CALL TR_OPER                   ; Append and count it.
    POP  HL                        ; Recover the frame.
    LD   DE,CT_FDEST               ; Address the test label.
    ADD  HL,DE                     ; HL addresses CT_FDEST.
    LD   A,(HL)                    ; The label of the loop's test.
    CALL TR_PUTHL                  ; Append it.
    INC  HL                        ; Skip CT_FCONT, which OP_NEXT does not need.
    INC  HL                        ; HL addresses CT_FEXIT.
    LD   A,(HL)                    ; The exit label.
    CALL TR_PUTHL                  ; Append it.
    INC  HL                        ; HL addresses CT_FVAR.
    LD   B,6                       ; Counter, mode, step word and trap offset word.
    JR   CT_BYTES                  ; Append them and return.
