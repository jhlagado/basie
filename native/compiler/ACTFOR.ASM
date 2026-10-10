;==========================================================================
;  Grammar actions: the counted for loop
;==========================================================================
;
;  The actions of the counted for loop, split from ACTSTMT.ASM, which it
;  follows in BASIE.ASM: its header, step, bound and body. The calling
;  convention is that of ACTIONS.ASM; the control frames and labels are
;  CONTROL.ASM's.
;
;  Principal entries:
;    AC_FOR, AC_FORTO, AC_STEP, AC_BYONE, AC_FORDO, AC_NEXT  for

; ---------------------------------------------------------- counted loop

;@ROUTINE OUT A,CARRY,ZERO CLOBBERS SIGN,PARITY,HALFCARRY,BC,DE,HL
; BeginFor, with the counter as the current NAME: it must be a declared,
; integer local (loop-counter) not already counting an open loop
; (not-writable). Keep its offset, and its width and sign as the mode's
; CT_MWORD, CT_MLONG and CT_MSIGN, and expect the initial value at its
; type.

AC_FOR:
    CALL SY_FIND                   ; An undeclared counter
    JP   NC,CT_EVAR                ; is no local: loop-counter.
    CALL AC_FIND                   ; D is its class and type, BC its offset.
    AND  SY_CMASK                  ; Its class.
    CP   SY_LOCAL                  ; A local?
    JP   NZ,CT_EVAR                ; No: raise DG_COUNT.
    CALL EX_DTYPE                  ; Decode the counter type.
    CP   SY_F32+1
    JP   NC,CT_EVAR                ; Nominal enums cannot count.
    CP   SY_BOOL                   ; Is its type Boolean?
    JP   Z,CT_EVAR                 ; Cannot count: raise DG_COUNT.
    CP   SY_F32                    ; Nor can
    JP   Z,CT_EVAR                 ; an f32.
    CALL GX_PROP                   ; Its size and sign:
    LD   E,A                       ; a word's size, 2,
    AND  2                         ; doubled,
    ADD  A,A                       ; is CT_MWORD;
    BIT  2,E                       ; a long's
    JR   Z,.SIGN                   ; is
    OR   CT_MLONG                  ; CT_MLONG;
.SIGN:                         ; and
    BIT  7,E                       ; a signed type's
    JR   Z,.MODE                   ; sign
    OR   CT_MSIGN                  ; is CT_MSIGN.
.MODE:                         ; A is the mode so far.
    LD   (AC_MODE),A               ; Kept.
    LD   (AC_INDEX),BC             ; The counter's offset.
    CALL CT_GUARD                  ; Reject an active counter.
    JP   AC_TOVAR                  ; Expect the counter's type.

;@ROUTINE OUT A CLOBBERS CARRY,ZERO,SIGN,PARITY,HALFCARRY
; Return in A the counter's type from AC_MODE (CT_TYPE).

AC_CTYPE:
    LD   A,(AC_MODE)               ; The mode's
    JP   CT_TYPE                   ; type; return.

;@ROUTINE IN A OUT A,CARRY,ZERO CLOBBERS SIGN,PARITY,HALFCARRY,BC,DE,HL
; ForTo, ForUntil: one routine for two actions, A being GR_TO or
; GR_UNTIL; to adds CT_MINC to the mode. Check the initial value
; against the counter (with no failure pending) and store it there, then
; expect the bound at the counter's type.

AC_FORTO:
    SUB  GR_TO                     ; Zero for to,
    SUB  1                         ; which alone borrows:
    SBC  A,A                       ; $FF for to, zero for until,
    AND  CT_MINC                   ; CT_MINC for to.
    LD   HL,AC_MODE                ; Add the bit
    OR   (HL)                      ; to the mode.
    LD   (HL),A                    ; Keep it.
    CALL AC_CTYPE                  ; The counter's type
    LD   E,A                       ; is the value's destination.
    CALL AC_VALOK                  ; Check it; D is its metadata, HL its value.
    CALL GX_TOREG                  ; Bring it into the registers.
    CALL AC_CTYPE                  ; The counter's type
    LD   HL,(AC_INDEX)             ; and offset:
    CALL GX_FPUT                   ; store it.
    CALL AC_CTYPE                  ; The bound is expected
    JP   AC_WANT                   ; at the counter's type.

;@ROUTINE OUT A,CARRY,ZERO CLOBBERS SIGN,PARITY,HALFCARRY,BC,DE,HL
; DefaultForStep: the step is one, upward.

AC_BYONE:
    LD   HL,1                      ; Step by one,
    LD   (AC_DELTA),HL             ; four bytes:
    DEC  HL                        ; a zero
    LD   (AC_DELTA+2),HL           ; high word; fall into AC_STEP.

;@ROUTINE OUT A,CARRY,ZERO CLOBBERS SIGN,PARITY,HALFCARRY,BC,DE,HL
; SaveForStep (forStatement): the step must fit the counter (DG_STEP).
; The bound just parsed (no failure pending) decides the comparison's
; type: a typed bound's and the counter's common type (mixed-operands
; when they have none, or for a Boolean; a long one is not yet compiled);
; an exact bound's is the counter's, but for a byte counter a bound it
; does not fit makes it the word of the counter's sign, or else i16, or
; else u16. The bound takes a new frame slot of two bytes for the whole
; loop, stored as a word of the comparison's sign (storeBound), and
; CT_MCMPS marks a signed comparison. An exact bound beyond even that
; type is not stored: the loop runs until the counter leaves its type
; (CT_MALL) when the step goes towards it, and never (CT_MNONE) when it
; goes away.

AC_STEP:
    CALL AC_CTYPE                  ; The counter's type:
    LD   C,A                       ; C keeps it.
    CALL GX_PROP                   ; Its largest value: a long's
    LD   B,A                       ; (B its properties)
    LD   HL,(AC_DELTA+2)           ; any, or below 2^31 signed;
    BIT  2,B                       ; a byte's and a word's need
    JR   NZ,.WORD                  ; a zero
    LD   A,H                       ; high
    OR   L                         ; word,
    JP   NZ,CT_ESTEP               ; else DG_STEP;
    LD   HL,(AC_DELTA)             ; a word's 65535
    BIT  1,B                       ; or 32767 signed;
    JR   NZ,.WORD                  ; a byte's 255
    LD   A,H                       ; or
    OR   A                         ; 127
    JP   NZ,CT_ESTEP               ; signed.
    LD   H,L                       ; A byte's top bit is L's.
.WORD:                         ; H holds the step's top bit.
    BIT  7,B                       ; A signed counter's step
    JR   Z,.FITS                   ; must have it clear.
    BIT  7,H                       ; Is it set?
    JP   NZ,CT_ESTEP               ; Then DG_STEP.
.FITS:                         ; The step fits the counter.
    CALL AC_SAFE                   ; No failure may be pending.
    PUSH BC                        ; (the counter's type kept)
    CALL EX_RTOK                   ; The bound: D its metadata, A too.
    POP  BC                        ; C is the counter's type.
    AND  EX_TMASK                  ; Its type:
    LD   E,C                       ; (the counter's in E)
    JR   Z,.EXACT                  ; exact, or
    CALL .COMMON                   ; the common type of a typed one.
    JR   .ALLOC                    ; Allocate the slot.
.EXACT:                        ; The comparison is the counter's type,
    LD   A,C                       ; unless the counter is a byte
    CALL GX_SIZE                   ; and the bound does not fit it.
    JR   NC,.ALLOC                 ; A word counter: its type.
    LD   A,C                       ; The counter's own type?
    CALL .TRY                      ; Then it.
    JR   NC,.ALLOC                 ; It fits.
    LD   A,C                       ; The word of the counter's sign,
    INC  A                         ; u16 or i16?
    CALL .TRY                      ; Then it.
    JR   NC,.ALLOC                 ; It fits.
    LD   A,SY_I16                  ; i16?
    CALL .TRY                      ; Then it.
    JR   NC,.ALLOC                 ; It fits.
    LD   A,SY_U16                  ; u16, or else
    CALL .TRY                      ; the counter's.
.ALLOC:                        ; E is the comparison's type, D the metadata.
    PUSH DE                        ; Keep them.
    LD   A,E                       ; A signed
    CALL GX_PROP                   ; comparison
    RLA                            ; is
    SBC  A,A                       ; CT_MCMPS
    AND  CT_MCMPS                  ; in
    CALL .MARK                     ; the mode.
    LD   A,(AC_MODE)               ; Two bytes,
    AND  CT_MLONG                  ; or four
    LD   A,2                       ; for
    JR   Z,.SIZE                   ; a long
    LD   A,4                       ; counter,
.SIZE:                         ; A is the slot's size,
    CALL EM_ALLOC                  ; in the frame for the bound;
    LD   (AC_BOUND),HL             ; their offset.
    POP  DE                        ; The type and the metadata.
    LD   A,D                       ; A typed bound
    AND  SY_TMASK                  ; is stored;
    JR   NZ,.STORE                 ; an exact one
    LD   A,E                       ; only if it fits
    CALL .TRY                      ; the comparison's type.
    JR   NC,.STORE                 ; It does.
    LD   A,(EX_KVAL+4)             ; Beyond: $FF below the type, 0 above.
    AND  CT_MDOWN                  ; Below, as the bit
    LD   HL,AC_MODE                ; of a step down:
    XOR  (HL)                      ; equal to the step's direction
    AND  CT_MDOWN                  ; when the step goes towards it,
    LD   A,CT_MALL                 ; and the loop runs on;
    JR   Z,.MARK                   ; otherwise
    LD   A,CT_MNONE                ; it never starts.
.MARK:                         ; Add the bits A to the mode.
    LD   HL,AC_MODE                ; The mode
    OR   (HL)                      ; takes
    LD   (HL),A                    ; them.
    RET                            ; Kept.
.STORE:                        ; E is the comparison's type, D the metadata.
    PUSH DE                        ; Keep them.
    CALL EX_RTOK                   ; The bound again, HL its value,
    POP  DE                        ; (the type)
    PUSH DE                        ; (kept)
    CALL GX_TOREG                  ; in the registers at that type.
    POP  DE                        ; E is the type.
    LD   A,E                       ; A byte
    CALL GX_SIZE                   ; is widened
    JR   NC,.SLOT                  ; to the word
    LD   D,E                       ; of its sign
    INC  E                         ; (u8 to u16, i8 to i16)
    CALL GX_WIDEN                  ; first.
.SLOT:                         ; A word or a long is in the registers:
    LD   A,E                       ; at its type
    LD   HL,(AC_BOUND)             ; it goes to its slot
    JP   GX_FPUT                   ; (storeBound); return.

;@ROUTINE IN A,E OUT E CLOBBERS A,B,CARRY,ZERO,SIGN,PARITY,HALFCARRY,HL
; A is a typed bound's type, E the counter's: return their common type
; in E, the type the other widens to (commonType); none, or f32, raises
; mixed-operands at the bound, as is a long one for a narrower counter
; (D58); one not a scalar, an enum, is type-mismatch there.

.COMMON:                       ; A is the bound's type.
    CP   AG_FIRST                  ; Not a scalar:
    JP   NC,EX_EFIT                ; type-mismatch.
    LD   B,A                       ; Keep it.
    CP   E                         ; The same as the counter's,
    JR   Z,.LONG                   ; or
    CALL EX_WIDEN                  ; widening to it,
    JR   C,.LONG                   ; is the counter's;
    LD   A,E                       ; the counter's
    LD   E,B                       ; widening to the bound's
    CALL EX_WIDEN                  ; is
    JR   NC,.MIXED                 ; the bound's,
    LD   A,E                       ; unless
    CP   SY_F32                    ; it is
    JR   NZ,.LONG                  ; an f32.
.MIXED:                        ; Neither, or f32:
    LD   A,DG_MIXED                ; mixed-operands,
    JP   EX_EVAL                   ; at the bound.
.LONG:                         ; E is the common type.
    LD   A,(AC_MODE)               ; A long counter
    AND  CT_MLONG                  ; takes
    RET  NZ                        ; any;
    LD   A,E                       ; a narrower one
    CALL GX_PROP                   ; no long
    AND  4                         ; comparison
    JR   NZ,.MIXED                 ; (D58).
    RET                            ; E is it.

;@ROUTINE IN A OUT E,CARRY CLOBBERS A,HL,ZERO,SIGN,PARITY,HALFCARRY
; Carry when the exact bound (EX_KVAL) does not fit type A; when it
; does, E becomes A. BC and D are kept.

.TRY:                          ; A is the type tried.
    PUSH DE                        ; Keep DE.
    PUSH AF                        ; And the type.
    LD   HL,EX_KVAL                ; Does the bound
    CALL VL_FITS                   ; fit it? BC is kept.
    POP  HL                        ; H is the type.
    POP  DE                        ; DE again.
    RET  C                         ; It does not.
    LD   E,H                       ; It does: E is it.
    RET                            ; Carry is clear.

;@ROUTINE OUT A,CARRY,ZERO CLOBBERS SIGN,PARITY,HALFCARRY,BC,DE,HL
; BeginForBody: open a for frame with its mode, counter, bound and step,
; and its exit, next-value and body labels. The first test compares the
; counter, widened to a word (CT_WIDE), with the bound, signed when the
; comparison is (compare16ToFlags): a step up goes on when the counter is
; below the bound, or equal to it for to; a step down stops when it is
; below, or equal for until. With no bound in reach the loop never
; starts (JP exit) or always does. The body is reachable.

AC_FORDO:
    LD   B,CT_KFOR                 ; A for frame.
    CALL CT_PUSH                   ; Open it; HL addresses it.
    LD   DE,CT_FMODE               ; Its mode, counter, bound and step
    ADD  HL,DE                     ; are copied
    EX   DE,HL                     ; from the scratch,
    LD   HL,AC_MODE                ; laid out
    LD   BC,AC_WEND-AC_MODE        ; alike.
    LDIR                           ; Copy them.
    LD   B,CT_FEXIT                ; The exit,
    CALL CT_NEW                    ; allocated.
    LD   B,CT_FCONT                ; The next value,
    CALL CT_NEW                    ; allocated.
    LD   B,CT_FDEST                ; The body,
    CALL CT_NEW                    ; allocated.
    LD   A,(AC_MODE)               ; No bound in reach:
    BIT  6,A                       ; CT_MNONE,
    LD   BC,CT_FEXIT*256+$C3       ; a JP to the exit,
    JR   NZ,.LAST                  ; or
    BIT  5,A                       ; CT_MALL,
    JR   NZ,.BODY                  ; no test at all.
    CALL CT_TEST                   ; Compare the counter with the bound.
    BIT  1,A                       ; CT_MDOWN: a step down
    JR   NZ,.DOWN                  ; stops below the bound.
    RRCA                           ; CT_MINC into carry.
    LD   BC,CT_FEXIT*256+$D2       ; until: JP NC to the exit.
    JR   NC,.LAST                  ; That is all.
    LD   BC,CT_FDEST*256+$DA       ; to: JP C
    CALL CT_GO                     ; to the body,
    LD   BC,CT_FDEST*256+$CA       ; JP Z
    CALL CT_GO                     ; to the body,
    LD   BC,CT_FEXIT*256+$C3       ; and JP to the exit.
.LAST:                         ; BC is the last jump.
    CALL CT_GO                     ; Append it.
    JR   .BODY                     ; The body follows.
.DOWN:                         ; A is the mode.
    CALL CT_PAST                   ; JP C, and for until JP Z, to the exit.
.BODY:                         ; The body starts here,
    CALL FW_ENTRY                  ; from the state now,
    JP   AC_ENTER                  ; reachable; return.

;@ROUTINE OUT A,CARRY,ZERO CLOBBERS SIGN,PARITY,HALFCARRY,BC,DE,HL
; EndFor: the body's block ends; the next value is computed where continue
; goes. With the bound in reach the counter passed the test, so its
; distance to the bound in the loop's direction is never negative; the
; loop goes on only if a step fits in it, and only then is the next value
; stored, so nothing wraps. The step is added to the counter as a word,
; or subtracted; a byte counter traps (loop-range) if the next value
; leaves its type (checkFitsCounter), and so does a word counter with no
; bound in reach, its carry or overflow (CALL C or CALL PE); a signed
; one's step up then adds with ADC, which sets the overflow. Then jump to
; the body, define the exit and close the frame.

AC_NEXT:
    CALL CT_BLOCK                  ; The body's block ends;
    CALL FW_LOOP                   ; its back edge, the paths met.
    LD   B,CT_FCONT                ; The next value
    CALL CT_DEF                    ; starts here.
    CALL CT_MODE                   ; A long counter
    BIT  7,A                       ; (CT_MLONG)
    JP   NZ,AC_LNEXT               ; is stepped through the runtime.
    CALL CT_WIDE                   ; HL is the counter; A the mode.
    PUSH AF                        ; Keep the mode.
    AND  CT_MALL+CT_MNONE          ; The bound in reach?
    JR   NZ,.STEP                  ; No: no distance.
    CALL GX_PUSHW                  ; PUSH HL, the counter, two bytes pushed.
    CALL CT_BOUND                  ; DE is the bound.
    POP  AF                        ; The mode.
    PUSH AF                        ; Kept.
    AND  CT_MDOWN                  ; A step up measures
    LD   A,$EB                     ; bound less counter:
    CALL Z,EM_BYTE                 ; EX DE,HL.
    CALL EM_SEQ                    ; OR A, SBC HL,DE: the distance;
    DB   4,$B7,$ED,$52,$11         ; LD DE,step.
    CALL CT_MAGW                   ; The magnitude.
    CALL EM_SEQ                    ; OR A, SBC HL,DE: carry if it
    DB   4,$B7,$ED,$52,$E1         ; does not fit; POP HL, the counter.
    CALL EM_POP2                   ; Popped.
    POP  AF                        ; The mode.
    PUSH AF                        ; Kept.
    CALL CT_PAST                   ; JP C, and for until JP Z, to the exit.
.STEP:                         ; HL is the counter.
    CALL EM_OP                     ; LD DE,step.
    DB   $11                       ; The opcode.
    CALL CT_MAGW                   ; The magnitude.
    POP  AF                        ; The mode.
    PUSH AF                        ; Kept.
    BIT  1,A                       ; CT_MDOWN:
    JR   NZ,.DOWN                  ; down subtracts.
    LD   C,A                       ; A signed word counter
    AND  CT_MWORD+CT_MSIGN         ; with
    CP   CT_MWORD+CT_MSIGN         ; no bound
    JR   NZ,.ADD                   ; in reach
    LD   A,C                       ; adds with ADC,
    AND  CT_MALL+CT_MNONE          ; whose overflow a trap tests;
    JR   Z,.ADD                    ; anything else adds with ADD.
.ADC:                          ; ADC.
    CALL EM_SEQ                    ; OR A, ADC HL,DE.
    DB   3,$B7,$ED,$5A             ; Appended.
    JR   .ADDED                    ; Added.
.ADD:                          ; ADD HL,DE.
    CALL EM_OP                     ; Appended.
    DB   $19                       ; The next value.
    JR   .ADDED                    ; Added.
.DOWN:                         ; OR A, SBC HL,DE.
    CALL GX_MINUS                  ; The next value.
.ADDED:                        ; HL is the next value.
    POP  AF                        ; The mode.
    PUSH AF                        ; Kept.
    BIT  2,A                       ; CT_MWORD: a word counter
    JR   NZ,.WORD                  ; may trap, then is stored.
    BIT  3,A                       ; CT_MSIGN: a byte's next value
    JR   NZ,.SIGNED                ; must fit it:
    CALL EM_SEQ                    ; unsigned, LD A,H, OR A
    DB   2,$7C,$B7                 ; with
    JR   .TRAP                     ; CALL NZ.
.SIGNED:                       ; Signed: H must be L's sign,
    CALL EM_SEQ                    ; LD A,L, RLCA, SBC A,A, XOR H,
    DB   4,$7D,$07,$9F,$AC         ; with
.TRAP:                         ; CALL NZ
    LD   A,$C4                     ; to the
    LD   L,HP_LOOP&$FF             ; loop-range trap;
    CALL EM_TRAP                   ; append it.
    CALL EM_OP                     ; LD A,L,
    DB   $7D                       ; the byte,
    POP  AF                        ; stored at
    CALL CT_TYPE                   ; the counter's type.
    JR   .STORE                    ; Store it.
.WORD:                         ; A word counter.
    BIT  5,A                       ; CT_MALL: no bound in reach,
    JR   Z,.KEEP                   ; so it may leave its type:
    BIT  3,A                       ; a signed one's overflow,
    LD   A,$EC                     ; CALL PE,
    JR   NZ,.LEAVE                 ; or
    LD   A,$DC                     ; an unsigned one's carry, CALL C,
.LEAVE:                        ; to
    LD   L,HP_LOOP&$FF             ; the loop-range trap.
    CALL EM_TRAP                   ; Append it.
.KEEP:                         ; Store the word.
    POP  AF                        ; The mode:
    CALL CT_TYPE                   ; the counter's type.
.STORE:                        ; A is the counter's type.
AC_ADV:                        ; Store the next value and go on (AC_LNEXT).
    PUSH AF                        ; Keep it.
    LD   B,CT_FVAR                 ; The counter's offset
    CALL CT_FWORD                  ; is HL.
    POP  AF                        ; The type.
    CALL GX_FPUT                   ; Store the next value.
    LD   BC,CT_FDEST*256+$C3       ; JP
    CALL CT_GO                     ; to the body.
    JP   AC_LEAVE                  ; Define the exit and close the frame.
;@ROUTINE IN A OUT A,CARRY,ZERO CLOBBERS SIGN,PARITY,HALFCARRY,BC,DE,HL
; EndFor of a long counter, A the mode (forStatement, big): with the bound
; in reach, the distance to it in the loop's direction, through SUB32,
; against the step's magnitude, through CMP32U, leaves the loop when the
; step does not fit (or fills it exactly, for until); with none, the
; counter, its sign bit flipped when signed, is compared with the last
; value a step can leave in the type, ~step going up and step going down,
; and traps (loop-range) beyond it. Then ADD32 or SUB32 makes the next
; value, stored, and the loop goes on.

AC_LNEXT:
    PUSH AF                        ; Keep the mode.
    AND  CT_MALL+CT_MNONE          ; The bound in reach?
    JR   NZ,.LIMIT                 ; No: the type's limit.
    POP  AF                        ; The mode:
    PUSH AF                        ; (kept)
    LD   BC,CT_FBND*256+CT_FVAR    ; up, the bound less the counter,
    AND  CT_MDOWN                  ; or
    JR   Z,.ORDER                  ; down,
    LD   BC,CT_FVAR*256+CT_FBND    ; the counter less the bound.
.ORDER:                        ; B is the minuend's field, C the other's.
    PUSH BC                        ; Keep them.
    CALL CT_LLOAD                  ; The minuend into DEHL,
    CALL CT_EXX                    ; then to the alternates
    POP  BC                        ; while
    LD   B,C                       ; the subtrahend
    CALL CT_LLOAD                  ; loads,
    CALL CT_EXX                    ; and back.
    CALL EM_HELP                   ; CALL SUB32: the distance,
    DW   HP_LSUB                   ; never negative.
    LD   B,0                       ; The step's magnitude
    CALL CT_ALTK                   ; in the alternates,
    CALL EM_HELP                   ; CALL CMP32U: carry if the step
    DW   HP_LCMPU                  ; does not fit.
    POP  AF                        ; The mode.
    PUSH AF                        ; Kept.
    CALL CT_PAST                   ; JP C, and for until JP Z, to the exit.
    JR   .STEP                     ; Then the next value.
.LIMIT:                        ; No bound in reach.
    LD   B,CT_FVAR                 ; The counter,
    CALL CT_LFLIP                  ; flipped if signed,
    POP  AF                        ; against
    PUSH AF                        ; the last value
    AND  CT_MDOWN                  ; a step
    SUB  1                         ; can leave,
    SBC  A,A                       ; complemented
    LD   B,A                       ; going up,
    CALL CT_ALTK                   ; in the alternates:
    CALL EM_HELP                   ; CALL CMP32U.
    DW   HP_LCMPU                  ; Then
    POP  AF                        ; going
    PUSH AF                        ; down
    AND  CT_MDOWN                  ; a borrow
    JR   NZ,.DOWN                  ; traps;
    LD   C,$DA                     ; going up, JP C to a new label past the trap,
    CALL EM_FWD                    ; A the label, kept by EM_JUMP;
    LD   C,$CA                     ; JP Z
    CALL EM_JUMP                   ; to it,
    PUSH AF                        ; (kept)
    CALL EM_HELP                   ; else CALL TRAP_LOO,
    DW   HP_LOOP                   ; its figure counted;
    POP  AF                        ; the label is here,
    CALL EM_LDONE                  ; and free again.
    JR   .STEP                     ; Then the next value.
.DOWN:                         ; CALL C,TRAP_LOO.
    LD   A,$DC                     ; The site's opcode,
    LD   L,HP_LOOP&$FF             ; the loop-range trap.
    CALL EM_TRAP                   ; Appended.
.STEP:                         ; The next value:
    LD   B,CT_FVAR                 ; the counter
    CALL CT_LLOAD                  ; in DEHL,
    LD   B,0                       ; the step
    CALL CT_ALTK                   ; in the alternates,
    POP  AF                        ; and
    PUSH AF                        ; by
    AND  CT_MDOWN                  ; the direction
    LD   DE,HP_LADD                ; ADD32
    JR   Z,.ADD                    ; or
    LD   DE,HP_LSUB                ; SUB32,
.ADD:                          ; called.
    CALL EM_HELPD                  ; DEHL is the next value,
    POP  AF                        ; stored at
    CALL CT_TYPE                   ; the counter's type.
    JP   AC_ADV                    ; Then on to the body.

AC_CEND:                       ; End of the grammar actions' code (marker).
