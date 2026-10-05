;==========================================================================
;  Structured control: frames, labels, conditions and counted loops
;==========================================================================
;
;  The support the grammar actions use to compile if, while, for, exit,
;  continue and handle in the reference compiler's templates (ref/compile/
;  compiler.ts: ifStatement, whileStatement, forStatement, condition,
;  exitStatement, nameStatementTail). Each open construct has a control
;  frame holding its routine labels (EMIT.ASM) and what its block must
;  restore when it ends.
;
;  Principal entries:
;    CT_PUSH   open a frame of a given kind
;    CT_POP    close the innermost frame, restoring its labels and frame
;    CT_BLOCK  end a block: the routine's frame shrinks back (block)
;    CT_TOP    address the innermost frame
;    CT_FIELD  address one field of the innermost frame
;    CT_NEW    allocate a label into a field of the innermost frame
;    CT_DEF    define the label in a field here
;    CT_GO     jump to the label in a field
;    CT_IFNOT  branch to the label in a field when the condition is false
;    CT_LOOP   find the innermost while or for frame
;    CT_GUARD  reject a write to an active for counter
;    CT_NOTE   record that the current if arm falls through
;    CT_STEP   parse a for loop's constant step
;    CT_TYPE   a for loop's counter's type from its mode
;    CT_TEST   compare a for loop's counter with its bound
;    CT_WIDE   load a for loop's counter widened to a word
;    CT_BOUND  load a for loop's bound into DE
;    CT_PAST   leave a for loop when the last comparison says so
;
;  Frames (STATE.ASM). CT_DEPTH counts the open frames, at most CT_FCAP
;  (8); frame n is the CT_FLEN (16) bytes at CT_FTAB+16n. The fields are:
;    CT_FKIND  +0  CT_KIF, CT_KLOOP (while), CT_KFOR or CT_KTRAP (handle)
;    CT_FDEST  +1  label: an if's next arm, a for's body, a handler's
;                  failure entry
;    CT_FCONT  +2  label: where continue goes, a while's test or a for's
;                  next value
;    CT_FEXIT  +3  label: an if's end, a loop's exit, a handler's skip
;    CT_FLCNT  +4  EM_LCNT as the frame opened: its labels and any
;                  allocated inside it are free again when it closes
;    CT_FSIZE  +5  word: EM_FRAME as the frame opened, the size its block
;                  restores (a for loop's bound stays allocated until the
;                  enclosing block ends, as the reference's allocLocal does)
;    CT_FMODE  +7  if: bit 0 an arm falls through, bit 1 it has an else;
;                  for: CT_MINC to (inclusive), CT_MDOWN a negative step,
;                  CT_MWORD a word counter, CT_MSIGN a signed one,
;                  CT_MCMPS a signed comparison, CT_MALL and CT_MNONE an
;                  exact bound beyond the comparison's type; handle: the
;                  temporaries' bytes pushed beneath the failing call
;    CT_FVAR   +8  for: word, the counter's offset from IX
;    CT_FBND   +10 for: word, the bound's offset from IX
;    CT_FSTEP  +12 for: word, the step's magnitude
;    CT_FSYMS  +14 SY_CNT as the frame opened: the first symbol of each of
;                  its blocks, whose symbols go out of scope as it ends
;  The for fields from CT_FMODE are copied from the actions' scratch
;  AC_MODE..AC_DELTA, laid out alike.

;@ROUTINE IN A OUT A,DE,HL,CARRY,ZERO CLOBBERS SIGN,PARITY,HALFCARRY
; Return in HL the address of frame A, CT_FTAB+16A. A is unchanged.

CT_FRAME:
    LD   L,A                       ; Widen the frame index
    LD   H,0                       ; into HL.
    ADD  HL,HL                     ; Times two,
    ADD  HL,HL                     ; four,
    ADD  HL,HL                     ; eight,
    ADD  HL,HL                     ; sixteen: the frame's offset.
    LD   DE,CT_FTAB                ; The frame table.
    ADD  HL,DE                     ; HL addresses frame A.
    RET                            ; A is still the index; carry clear.

;@ROUTINE IN B OUT A,DE,HL,CARRY,ZERO CLOBBERS SIGN,PARITY,HALFCARRY
; Open a frame of kind B and return its address in HL: it keeps the label
; count, the frame's size and the symbol count to restore when it or its
; blocks end, and its mode is clear. A ninth frame raises DG_NEST.

CT_PUSH:
    LD   A,(CT_DEPTH)              ; The new frame's index is the depth.
    CP   CT_FCAP                   ; Are all frames in use?
    JR   NC,CT_EDEEP               ; Raise DG_NEST.
    INC  A                         ; One more frame
    LD   (CT_DEPTH),A              ; is open.
    DEC  A                         ; Its index again.
    CALL CT_FRAME                  ; HL addresses it.
    PUSH HL                        ; Keep it to return.
    LD   (HL),B                    ; The kind.
    LD   DE,CT_FLCNT               ; Step past the labels,
    ADD  HL,DE                     ; which are set as they are allocated.
    LD   A,(EM_LCNT)               ; The labels in use
    LD   (HL),A                    ; are kept;
    INC  HL                        ; then
    LD   DE,(EM_FRAME)             ; the frame's size,
    LD   (HL),E                    ; low byte
    INC  HL                        ; and
    LD   (HL),D                    ; high byte;
    INC  HL                        ; then
    LD   (HL),0                    ; the mode, clear;
    LD   DE,CT_FSYMS-CT_FMODE      ; then
    ADD  HL,DE                     ; the symbols
    LD   A,(SY_CNT)                ; in scope,
    LD   (HL),A                    ; kept.
    POP  HL                        ; HL is the frame.
    RET                            ; The construct may fill it.

;@ROUTINE NORETURN
; Raise DG_NEST: constructs are nested more than CT_FCAP deep.

CT_EDEEP:
    CALL DG_RAISE                  ; Abandon the build.
    DB   DG_NEST                   ; Nesting too deep.

;@ROUTINE OUT A,DE,HL,CARRY,ZERO CLOBBERS SIGN,PARITY,HALFCARRY,B
; Close the innermost frame: its block ends (CT_BLOCK), and the labels
; allocated since it opened are free again.

CT_POP:
    CALL CT_BLOCK                  ; The block ends; HL is the frame.
    INC  HL                        ; Its
    INC  HL                        ; labels
    INC  HL                        ; in use
    INC  HL                        ; before,
    LD   A,(HL)                    ; CT_FLCNT:
    LD   (EM_LCNT),A               ; the rest are free.
    LD   HL,CT_DEPTH               ; One frame
    DEC  (HL)                      ; fewer is open.
    RET                            ; The enclosing frame is innermost.

;@ROUTINE OUT DE,HL CLOBBERS A,B,CARRY,ZERO,SIGN,PARITY,HALFCARRY
; A block ends (the reference's block): the routine's frame shrinks back
; to its size when the innermost frame opened, freeing the block's locals
; and what nested for loops allocated for their bounds, and the symbols
; declared since go out of scope. HL returns the frame's address.

CT_BLOCK:
    LD   B,CT_FSYMS                ; The symbols in scope
    CALL CT_FIELD                  ; when the frame opened
    LD   A,(HL)                    ; are
    LD   (SY_CNT),A                ; again;
    LD   DE,CT_FSIZE-CT_FSYMS      ; and so is
    ADD  HL,DE                     ; the size
    LD   E,(HL)                    ; of the
    INC  HL                        ; frame,
    LD   D,(HL)                    ; DE,
    LD   (EM_FRAME),DE             ; then.
    LD   DE,-CT_FSIZE-1            ; HL is
    ADD  HL,DE                     ; the frame.
    RET                            ; Its block has ended.

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
; frame. BC is kept.

CT_FIELD:
    CALL CT_TOP                    ; HL addresses the innermost frame.
    LD   E,B                       ; Widen the field offset
    LD   D,0                       ; into DE.
    ADD  HL,DE                     ; HL addresses the field.
    RET                            ; Carry clear.

;@ROUTINE IN B OUT A,HL CLOBBERS CARRY,ZERO,SIGN,PARITY,HALFCARRY,DE
; Allocate a routine label (EM_LNEW) into field B of the innermost frame;
; A returns it and HL addresses the field.

CT_NEW:
    CALL EM_LNEW                   ; A is a new label.
    PUSH AF                        ; Keep it.
    CALL CT_FIELD                  ; HL addresses field B.
    POP  AF                        ; The label
    LD   (HL),A                    ; goes there.
    RET                            ; A is the label.

;@ROUTINE IN B CLOBBERS A,BC,DE,HL,CARRY,ZERO,SIGN,PARITY,HALFCARRY
; Define the label in field B of the innermost frame here.

CT_DEF:
    CALL CT_FIELD                  ; HL addresses the field.
    LD   A,(HL)                    ; The label
    JP   EM_LDEF                   ; is defined here; return.

;@ROUTINE IN B,C CLOBBERS A,BC,DE,HL,CARRY,ZERO,SIGN,PARITY,HALFCARRY
; Append the jump C (JP $C3 or JP cc) to the label in field B of the
; innermost frame.

CT_GO:
    CALL CT_FIELD                  ; HL addresses the field; C is kept.
    LD   A,(HL)                    ; The label
    JP   EM_JUMP                   ; is the jump's operand; return.

;@ROUTINE IN B CLOBBERS A,BC,DE,HL,CARRY,ZERO,SIGN,PARITY,HALFCARRY
; The condition just parsed (EX_RMETA, EX_RVAL), a Boolean, goes to the
; label in field B of the innermost frame when it is false (the
; reference's condition): a known false jumps there, a known true needs
; no code, and a computed one is tested, OR A and JP Z.

CT_IFNOT:
    LD   A,(EX_RMETA)              ; Is the condition known?
    RLCA                           ; SY_KNOWN into carry.
    JR   NC,.TEST                  ; No: test it at run time.
    LD   A,(EX_RVAL)               ; Its value, 0 or 1.
    OR   A                         ; True?
    RET  NZ                        ; Then nothing branches.
    LD   C,$C3                     ; False: JP.
    JR   CT_GO                     ; Always to the label.
.TEST:                         ; The Boolean is in A at run time.
    CALL EM_OP                     ; OR A sets Z
    DB   $B7                       ; when it is false.
    LD   C,$CA                     ; JP Z.
    JR   CT_GO                     ; To the label; return.

;@ROUTINE NORETURN
; Raise DG_LOOP: exit or continue outside any loop, or no frame open.

CT_ELOOP:
    CALL DG_RAISE                  ; Abandon the build.
    DB   DG_LOOP                   ; Not inside a loop.

;@ROUTINE OUT A,DE,HL,CARRY,ZERO CLOBBERS SIGN,PARITY,HALFCARRY
; Return in HL the innermost while or for frame, skipping if and handle
; frames (the reference's loops stack). Outside every loop this raises
; DG_LOOP.

CT_LOOP:
    LD   A,(CT_DEPTH)              ; How many frames are open?
.NEXT:                         ; Try the frame below index A.
    OR   A                         ; Was that the outermost?
    JR   Z,CT_ELOOP                ; Then no loop encloses the statement.
    DEC  A                         ; A is the next frame outward.
    CALL CT_FRAME                  ; HL addresses frame A.
    LD   E,(HL)                    ; Its kind:
    DEC  E                         ; CT_KIF is 1,
    JR   Z,.NEXT                   ; not a loop;
    DEC  E                         ; CT_KLOOP 2
    RET  Z                         ; and
    DEC  E                         ; CT_KFOR 3
    RET  Z                         ; are loops;
    JR   .NEXT                     ; CT_KTRAP is not.

;@ROUTINE IN BC CLOBBERS A,DE,HL,CARRY,ZERO,SIGN,PARITY,HALFCARRY
; BC is the offset from IX of a local, the current name. Raise
; not-writable, naming it, if that local is the counter of any open for
; loop, so the body can neither assign it nor count with it again (the
; reference's counting).

CT_GUARD:
    CALL CT_COUNT                  ; Carry if the local counts a loop.
    RET  NC                        ; It doesn't.
    LD   A,DG_CONST                ; not-writable,
    JP   DG_NAMED                  ; naming it.

;@ROUTINE IN BC OUT CARRY CLOBBERS A,DE,HL,ZERO,SIGN,PARITY,HALFCARRY
; Carry if the local at offset BC from IX is the counter of an open for
; loop.

CT_COUNT:
    LD   A,(CT_DEPTH)              ; How many frames are open?
.NEXT:                         ; Check the frame below index A.
    OR   A                         ; Was that the outermost?
    RET  Z                         ; Then the local is free; carry is clear.
    DEC  A                         ; A is the next frame outward.
    PUSH AF                        ; Keep the index.
    CALL CT_FRAME                  ; HL addresses frame A.
    LD   A,(HL)                    ; Its kind:
    CP   CT_KFOR                   ; only for frames have counters.
    JR   NZ,.SKIP                  ; Skip any other kind.
    LD   DE,CT_FVAR                ; Step
    ADD  HL,DE                     ; to the counter's offset.
    LD   A,(HL)                    ; Its low byte:
    CP   C                         ; is it this local's?
    JR   NZ,.SKIP                  ; No.
    INC  HL                        ; The high byte:
    LD   A,(HL)                    ; this local's
    CP   B                         ; too?
    JR   Z,.ACTIVE                 ; Yes: the local is counting.
.SKIP:                         ; This frame does not hold the local.
    POP  AF                        ; The index again.
    JR   .NEXT                     ; Check further out.
.ACTIVE:                       ; The local counts an open loop.
    POP  AF                        ; The index is not needed.
    SCF                            ; Report it.
    RET                            ; Carry.

;@ROUTINE OUT A,DE,HL,CARRY,ZERO CLOBBERS SIGN,PARITY,HALFCARRY,B
; If the arm just ended can complete (CT_FALLS), mark the innermost frame,
; an if, so that the if as a whole can.

CT_NOTE:
    LD   A,(CT_FALLS)              ; Can control reach the end of this arm?
    OR   A                         ; Zero means the arm ends in a transfer.
    RET  Z                         ; Then the mark stands.
    LD   B,CT_FMODE                ; Select the if's mode.
    CALL CT_FIELD                  ; HL addresses it.
    SET  0,(HL)                    ; Some arm falls through.
    RET                            ; The mark is made.

;@ROUTINE OUT A,B,DE,CARRY,ZERO CLOBBERS SIGN,PARITY,HALFCARRY,C,HL
; Parse a for loop's step: an optional sign, then a number, an integer
; constant, exact or typed, or a predeclared constant, which must be
; nonzero. Return the magnitude in DE and
; in B the mode bit CT_MDOWN for a negative step. Anything else raises
; DG_STEP.

CT_STEP:
    CALL PR_PEEK                   ; Look for a sign.
    LD   B,0                       ; Assume an upward step.
    CP   TK_PLUS                   ; An explicit plus?
    JR   Z,.PLUS                   ; Consume it.
    CP   TK_MINUS                  ; A minus?
    JR   NZ,.AMOUNT                ; No sign: read the amount.
    LD   B,CT_MDOWN                ; A downward step.
.PLUS:                         ; A sign is next.
    PUSH BC                        ; Keep the direction.
    CALL PR_TAKE                   ; Consume it.
    POP  BC                        ; The direction.
.AMOUNT:                       ; The step's value is next.
    PUSH BC                        ; Keep the direction.
    CALL PR_TAKE                   ; A is its kind, BC its payload.
    CP   TK_NUM                    ; A literal number?
    JR   Z,.LITERAL                ; Its value is in BC.
    CP   TK_NAME                   ; A name?
    JR   NZ,CT_ESTEP               ; Anything else is not a step.
    CALL RO_LIB                    ; Is it a predeclared name?
    JR   NC,.CONST                 ; No: it must be a declared constant.
    JP   P,CT_ESTEP                ; A service is not a value.
    CP   SY_KNOWN+SY_EXACT         ; A File
    JR   NZ,CT_ESTEP               ; is no step.
    INC  HL                        ; Its value,
    LD   E,(HL)                    ; a byte,
    LD   D,0                       ; widened into DE,
    JR   .NONZERO                  ; must not be zero.
.CONST:                        ; The name must be an integer constant.
    CALL SY_GET                    ; A is its class and type, BC its value.
    LD   D,A                       ; Keep them.
    AND  SY_TYPE+SY_AGGR+SY_CMASK  ; A constant has none of these:
    JR   NZ,CT_ESTEP               ; a type, aggregate or variable.
    LD   A,D                       ; Its type
    AND  SY_TMASK                  ; is an integer's,
    CP   SY_BOOL                   ; not Boolean.
    JR   Z,CT_ESTEP                ; A Boolean is no step.
    INC  HL                        ; Its value's high bytes (SY_VHI):
    LD   A,(HL)                    ; any
    INC  HL                        ; is
    OR   (HL)                      ; beyond
    INC  HL                        ; any counter
    OR   (HL)                      ; here, or negative,
    JR   NZ,CT_ESTEP               ; no step.
    JR   .NUMBER                   ; BC is the value.
.LITERAL:                      ; A number:
    LD   HL,(TK_NHI)               ; beyond sixteen bits
    LD   A,H                       ; it fits
    OR   L                         ; no counter here,
    JR   NZ,CT_ESTEP               ; no step.
.NUMBER:                       ; BC holds the value.
    LD   D,B                       ; Move it
    LD   E,C                       ; to DE.
.NONZERO:                      ; DE is the magnitude.
    POP  BC                        ; B is the direction.
    LD   A,D                       ; Is it zero?
    OR   E                         ; A zero step would never finish.
    RET  NZ                        ; DE is the magnitude.

;@ROUTINE NORETURN
; Raise DG_STEP: the step is not a nonzero constant that fits the counter.

CT_ESTEP:
    CALL DG_RAISE                  ; Abandon the build.
    DB   DG_STEP                   ; Bad step.

;@ROUTINE NORETURN
; Raise DG_COUNT: a for counter must be a non-Boolean scalar local.

CT_EVAR:
    CALL DG_RAISE                  ; Abandon the build.
    DB   DG_COUNT                  ; Bad counter.

;@ROUTINE IN A OUT A CLOBBERS CARRY,ZERO,SIGN,PARITY,HALFCARRY
; Return in A the counter's type from for mode A, its CT_MWORD and
; CT_MSIGN: u8, u16, i8 or i16. HL is kept.

CT_TYPE:
    PUSH HL                        ; Keep HL.
    AND  CT_MWORD+CT_MSIGN         ; The two bits,
    RRCA                           ; as
    RRCA                           ; an index,
    LD   HL,.TABLE                 ; into
    ADD  A,L                       ; the
    LD   L,A                       ; types
    ADC  A,H                       ; by
    SUB  L                         ; mode,
    LD   H,A                       ; select
    LD   A,(HL)                    ; one.
    POP  HL                        ; Restore HL.
    RET                            ; A is it.
.TABLE:                        ; By CT_MWORD and CT_MSIGN:
    DB   SY_U8,SY_U16,SY_I8,SY_I16 ; byte, word, signed byte, signed word.

;@ROUTINE OUT A CLOBBERS BC,DE,HL,CARRY,ZERO,SIGN,PARITY,HALFCARRY
; Compare the counter of the innermost frame, a for loop, with its bound
; (CT_WIDE, CT_BOUND), leaving carry when the counter is below and zero
; when they are equal (compare16ToFlags): a signed comparison (CT_MCMPS)
; flips both sign bits first, LD A,H, XOR $80, LD H,A, LD A,D, XOR $80,
; LD D,A; then OR A, SBC HL,DE. A returns the frame's mode.

CT_TEST:
    CALL CT_WIDE                   ; HL is the counter, A the mode.
    PUSH AF                        ; Keep the mode.
    CALL CT_BOUND                  ; DE is the bound.
    POP  AF                        ; The mode:
    PUSH AF                        ; (kept)
    AND  CT_MCMPS                  ; a signed comparison?
    JR   Z,.SBC                    ; No.
    CALL EM_SEQ                    ; Flip both sign bits:
    DB   8,$7C,$EE,$80,$67,$7A,$EE,$80,$57 ; H's and D's.
.SBC:                          ; Then subtract:
    CALL EM_SEQ                    ; OR A, SBC HL,DE: carry when the
    DB   3,$B7,$ED,$52             ; counter is below, zero when equal.
    POP  AF                        ; The mode.
    RET                            ; Compared.

;@ROUTINE OUT A CLOBBERS BC,DE,HL,CARRY,ZERO,SIGN,PARITY,HALFCARRY
; Load the counter of the innermost frame, a for loop, into HL widened to
; a word (loadCounterWide): a word is loaded; a byte is loaded, LD L,A,
; then sign-extended, LD A,L, RLCA, SBC A,A, LD H,A, or not, LD H,0. A
; returns the frame's mode.

CT_WIDE:
    LD   B,CT_FMODE                ; The mode, then the counter's offset.
    CALL CT_FIELD                  ; HL addresses the mode.
    LD   A,(HL)                    ; Fetch it.
    INC  HL                        ; DE is
    LD   E,(HL)                    ; the
    INC  HL                        ; counter's
    LD   D,(HL)                    ; offset.
    PUSH AF                        ; Keep the mode to return.
    EX   DE,HL                     ; HL is the offset.
    CALL CT_TYPE                   ; The counter's type:
    PUSH AF                        ; (kept)
    CALL GX_FLOAD                  ; loaded, a byte into A.
    POP  AF                        ; A word
    CALL GX_SIZE                   ; is
    JR   NC,.DONE                  ; in HL;
    CALL EM_OP                     ; a byte
    DB   $6F                       ; LD L,A,
    POP  AF                        ; then
    PUSH AF                        ; by its
    AND  CT_MSIGN                  ; sign:
    JR   NZ,.SIGNED                ; extended,
    CALL EM_SEQ                    ; or
    DB   2,$26,0                   ; LD H,0.
    JR   .DONE                     ; Loaded.
.SIGNED:                       ; LD A,L, RLCA, SBC A,A, LD H,A:
    CALL EM_SEQ                    ; the sign
    DB   4,$7D,$07,$9F,$67         ; in H.
.DONE:                         ; HL is the counter.
    POP  AF                        ; The mode.
    RET                            ; Done.

;@ROUTINE CLOBBERS A,BC,DE,HL,CARRY,ZERO,SIGN,PARITY,HALFCARRY
; Load the bound of the innermost frame, a for loop, into DE (ixWord to
; DE), keeping HL.

CT_BOUND:
    LD   B,CT_FBND                 ; The bound's offset.
    CALL CT_FIELD                  ; HL addresses it.
    LD   E,(HL)                    ; Fetch
    INC  HL                        ; the
    LD   D,(HL)                    ; offset,
    EX   DE,HL                     ; into HL.
    LD   DE,GX_DLDDE               ; DE = (IX+d).
    JP   GX_FACC                   ; Load it and return.

;@ROUTINE IN A CLOBBERS A,BC,DE,HL,CARRY,ZERO,SIGN,PARITY,HALFCARRY
; After a comparison of the innermost for loop's counter, or of its
; distance, A being the loop's mode: JP C to its exit, and for until also
; JP Z.

CT_PAST:
    PUSH AF                        ; Keep the mode.
    LD   BC,CT_FEXIT*256+$DA       ; JP C,
    CALL CT_GO                     ; to the exit.
    POP  AF                        ; The mode.
    RRCA                           ; CT_MINC into carry:
    RET  C                         ; to (inclusive) stops there.
    LD   BC,CT_FEXIT*256+$CA       ; JP Z,
    JP   CT_GO                     ; to the exit; return.
