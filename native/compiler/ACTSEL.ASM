;==========================================================================
;  Actions: select
;==========================================================================
;
;  The grammar actions of an integer select (spec 11.7.2), generating the
;  reference compiler's code (ref/compile/compiler.ts selectStatement and
;  emitLabelTest): the subject is stored in a frame slot of its own size,
;  allocated before the select's control frame opens, so that it stays
;  allocated until the enclosing block ends, as the reference's allocLocal
;  leaves it; then each arm's labels are tested in turn against it, a
;  match jumping to the arm's body, and the arm ends with a jump to the
;  select's end. A compiler may choose a jump table or a search (11.7.2);
;  the reference always tests, so this does.
;
;    statement   -> select x:SelectSubject NEWLINE select-arms
;                   a:EndSelect end NEWLINE
;    select-arms -> case a:BeginCase case-arm | (nothing)
;    case-arm    -> else a:CaseElse NEWLINE statement-sequence a:EndCase
;                 | x:CaseLabels NEWLINE a:CaseBody statement-sequence
;                   a:EndCase select-arms
;
;  A label's test, the subject being S, the label low to high, both
;  compared unsigned with a signed type's sign bit flipped:
;    byte  LD A,S [XOR $80]  CP low  JP Z,body   (low = high)
;                            CP low  JP C,skip  CP high+1  JP C,body
;                            (JP body when high is $FF)  skip:
;    word  LD HL,S [flip H]  LD DE,low  OR A  SBC HL,DE
;                            LD A,H  OR L  JP Z,body      (low = high)
;                            JP C,skip  LD DE,high-low+1  OR A  SBC HL,DE
;                            JP C,body  (JP body when high is $FFFF) skip:
;    long  [S compared with low: LD DEHL,S [flip D] EXX LD HL,lo LD DE,hi
;          EXX CALL CMP32U]  JP Z,body                     (low = high)
;          [S with low] JP C,skip  [S with high] JP C,body  JP Z,body  skip:
;
;  The select's control frame (CONTROL.ASM), kind CT_KSEL: CT_FDEST and
;  CT_FCONT the current arm's body and next arm, CT_FEXIT the end; CT_FMODE
;  bit 0 an arm falls through (CT_NOTE), bit 1 case else, bit 2 an arm
;  with labels; CT_FVAR the subject's offset from IX, CT_FBND its type,
;  CT_FSTEP the first of its label ranges, CT_FSTEP+2 the offset of
;  `select`. The ranges (CT_RTAB, LL1.ASM) are every label of the open
;  selects, each select's after its enclosing one's, so that a label is
;  checked against those before it in the same select (duplicate-case).
;
;  Principal entries (actions and islands):
;    AC_PICK   SelectSubject: the subject, stored; the frame opens
;    AC_CASE   BeginCase: an arm's labels
;    AC_LABEL  CaseLabels: the labels, each checked and tested
;    AC_TAKEN  CaseBody: the arm's body begins
;    AC_OTHER  CaseElse: the case else arm begins
;    AC_SHUT EndCase: the arm ends
;    AC_FINAL  EndSelect: the select ends
;
;  Scratch (ACTIONS.ASM): AC_MODE is zero after `move`, then a test's skip
;  label; AC_INDEX to AC_DELTA+3 stage the frame's fields from CT_FVAR (the
;  subject's offset and type, the first range, the offset of `select`),
;  copied when the frame opens; AC_BOUND is then the range being tested;
;  AC_SPOS a label's offset.

;@ROUTINE OUT A,CARRY,ZERO CLOBBERS SIGN,PARITY,HALFCARRY,BC,DE,HL,IX,IY
; Island SelectSubject: the subject (selectStatement). A variable's name
; is a designator alone, its scalar loaded; anything else an expression,
; which must have a type (no-definite-type). `move` is refused, at
; `select`, once the subject is read; the subject must be an integer
; (type-mismatch at it). It is stored in a new frame slot, then the
; select's frame opens with its end label.

AC_PICK:
    LD   HL,(TK_POS)               ; `select`, just consumed, is
    LD   (AC_DELTA+2),HL           ; where its own faults are reported.
    CALL PR_PEEK                   ; Is `move` next?
    SUB  TK_MOVE                   ; Zero if so, kept for .MOVE,
    LD   (AC_MODE),A               ; and then it
    CALL Z,PR_TAKE                 ; is consumed.
    XOR  A                         ; Nothing is expected of
    CALL EX_INIT                   ; the subject.
    CALL PR_PEEK                   ; A variable's name
    CP   TK_NAME                   ; begins a designator,
    JR   Z,.NAME                   ; anything else an expression,
    CP   TK_TEXT                   ; but a string literal
    JR   NZ,.VALUE                 ; is no integer
    LD   A,DG_CLASH                ; (type-mismatch
    JP   DG_ISSUE                  ; at it).
.NAME:                         ; A name.
    CALL SY_FIND                   ; A symbol?
    JR   NC,.VALUE                 ; No: a routine, or undeclared.
    INC  HL                        ; Its
    INC  HL                        ; class,
    INC  HL                        ; past its spelling's
    LD   A,(HL)                    ; address and length:
    AND  SY_CMASK                  ; a constant's or a type's
    JR   Z,.VALUE                  ; is an expression's.
    BIT  7,(HL)                    ; SY_AGGR: a path?
    LD   HL,(TK_POS)               ; The designator
    LD   (EX_START),HL             ; starts here:
    JR   NZ,.PATH                  ; (a path)
    CALL PR_TAKE                   ; the name, then what it selects,
    CALL EX_NAME                   ; loaded as a primary: A is its type.
    JR   .LOADED                   ; It is in the registers.
.PATH:                         ; A path, its root's name next:
    CALL PR_TAKE                   ; taken,
    CALL RO_NAMED                  ; the path parsed: a handle
    CALL PL_ISHND                  ; is selected
    JP   C,HN_SEL                  ; by its arms;
    CALL .MOVE                     ; (no `move` of anything else)
    CALL RO_LOAD                   ; a scalar is loaded.
.LOADED:                       ; A is its type.
    CALL .MOVE                     ; `move` is refused first.
    JR   .TYPED                    ; A is its type.
.VALUE:                        ; An expression,
    XOR  A                         ; nothing expected of it:
    CALL EX_RUN                    ; A is its metadata, HL its value.
    CALL .MOVE                     ; `move` is refused first.
    LD   D,A                       ; Keep the metadata:
    CALL AC_SAFE                   ; no failure may be pending.
    LD   A,D                       ; Its type,
    AND  SY_TMASK                  ; alone,
    LD   E,A                       ; in E.
    BIT  7,D                       ; Known?
    JR   Z,.TYPED                  ; No: it is in the registers.
    OR   A                         ; An exact value has no type:
    LD   A,DG_INFER                ; no-definite-type,
    JP   Z,EX_EVAL                 ; at it.
    CALL GX_TOREG                  ; A typed constant is loaded.
    LD   A,E                       ; Its type.
.TYPED:                        ; A is the subject's type, in the registers.
    CP   SY_BOOL                   ; A Boolean,
    JP   Z,EX_EFIT                 ; or anything
    DEC  A                         ; but the types
    CP   SY_I32                    ; from u8 to i32,
    INC  A                         ; is no integer
    JP   NC,EX_EFIT                ; (type-mismatch at it).
    LD   (AC_BOUND),A              ; Keep the type for the frame.
    CALL GX_PROP                   ; Its size
    AND  7                         ; is the slot's,
    CALL EM_ALLOC                  ; allocated: HL is its offset,
    LD   (AC_INDEX),HL             ; kept for the frame.
    LD   A,(AC_BOUND)              ; The slot
    CALL GX_FPUT                   ; takes the subject.
    JR   AC_SOPEN                  ; The frame opens; return.

;@ROUTINE CLOBBERS BC,ZERO,SIGN,PARITY,HALFCARRY
; Refuse `move` (AC_MODE zero) with syntax at `select`: only a handle may
; be moved. A, HL and carry are kept.

.MOVE:                         ; The subject is read.
    LD   BC,(AC_MODE)              ; C is zero
    INC  C                         ; if `move`
    DEC  C                         ; was given;
    RET  NZ                        ; it was not.
    LD   A,DG_STMT                 ; syntax,
    LD   HL,AC_DELTA+2             ; at `select`.
    JP   DG_AT                     ; No return.


;@ROUTINE CLOBBERS A,BC,DE,HL,CARRY,ZERO,SIGN,PARITY,HALFCARRY
; Open the select's frame, its subject staged: AC_INDEX its slot, AC_BOUND
; its type, AC_DELTA+2 the offset of `select`; the first range is the
; ranges' top. Its end label is allocated. HN_SEL opens a handle's so.

AC_SOPEN:                      ; The subject is in its slot.
    LD   HL,(CT_RTOP)              ; The select's labels start
    LD   (AC_DELTA),HL             ; at the ranges' top.
    LD   B,CT_KSEL                 ; The select's frame
    CALL CT_PUSH                   ; opens: HL is it.
    LD   DE,CT_FVAR                ; Its fields from CT_FVAR
    ADD  HL,DE                     ; are the scratch's from AC_INDEX:
    EX   DE,HL                     ; the subject's offset and type,
    LD   HL,AC_INDEX               ; the first range's place
    LD   BC,8                      ; and the offset
    LDIR                           ; of `select`.
    LD   B,CT_FEXIT                ; Its end
    CALL CT_NEW                    ; label;
    JP   FW_ENTRY                  ; the arms start from the state now.
;@ROUTINE OUT A CLOBBERS BC,DE,HL,CARRY,ZERO,SIGN,PARITY,HALFCARRY
; BeginCase: `some` and `none` select on a handle, not an integer
; (type-mismatch at them); otherwise the arm's body and next labels.

AC_CASE:
    LD   HL,(TK_POS)               ; `case`, where a handle arm's
    LD   (AC_SPOS),HL              ; faults are reported.
    CALL FW_REST                   ; The arm starts from the select's state.
    CALL CT_MODE                   ; A handle select
    BIT  3,A                       ; reads its arm
    JR   NZ,.HANDLE                ; here.
    CALL PR_PEEK                   ; `some` or `none`,
    AND  $FE                       ; TK_SOME and TK_NONE,
    CP   TK_SOME                   ; after `case`?
    LD   A,DG_CLASH                ; type-mismatch,
    JP   Z,DG_ISSUE                ; at it.
    LD   B,CT_FDEST                ; The arm's body
    CALL CT_NEW                    ; label,
    LD   B,CT_FCONT                ; then the next
    JP   CT_NEW                    ; arm's; return.
.HANDLE:                       ; A handle select's arm:
    LD   B,CT_FDEST                ; its labels
    CALL CT_NEW                    ; as
    LD   B,CT_FCONT                ; any
    CALL CT_NEW                    ; arm's;
    CALL PR_PEEK                   ; then, before the engine predicts
    CP   TK_ELSE                   ; it, some or none (OW_ARM),
    JP   NZ,OW_ARM                 ; which CaseLabels finds read;
    RET                            ; case else is the grammar's.

;@ROUTINE OUT A CLOBBERS BC,DE,HL,CARRY,ZERO,SIGN,PARITY,HALFCARRY
; CaseBody: the labels are tested; none matched goes to the next arm,
; and the body, a labelled arm's, starts here, reachable.

AC_TAKEN:
    CALL CT_MODE                   ; A handle select's arm
    BIT  3,A                       ; binds
    JP   NZ,OW_TAKEN               ; its name.
    LD   BC,CT_FCONT*256+$C3       ; JP
    CALL CT_GO                     ; to the next arm.
    LD   A,4                       ; Bit 2: an arm with labels.
    JR   AC_ARMIN                  ; Its body starts here.

;@ROUTINE OUT A CLOBBERS BC,DE,HL,CARRY,ZERO,SIGN,PARITY,HALFCARRY
; CaseElse: the case else arm's body starts here, reachable.

AC_OTHER:
    CALL CT_MODE                   ; A handle select's
    BIT  3,A                       ; case else
    JP   NZ,OW_ELSE                ; tests its subject.
    LD   A,2                       ; Bit 1: case else; fall into AC_ARMIN.

;@ROUTINE IN A OUT A CLOBBERS BC,DE,HL,CARRY,ZERO,SIGN,PARITY,HALFCARRY
; Add the bits A to the select's mode, define the arm's body label here,
; and make it reachable.

AC_ARMIN:
    PUSH AF                        ; Keep the bits.
    CALL CT_FLAGS                  ; The select's mode
    POP  AF                        ; takes
    OR   (HL)                      ; them.
    LD   (HL),A                    ; Kept; fall into AC_ENTER.

;@ROUTINE OUT A CLOBBERS BC,DE,HL,CARRY,ZERO,SIGN,PARITY,HALFCARRY
; Define the innermost frame's body label (CT_FDEST) here, and make it
; reachable: a select arm's body, a for loop's.

AC_ENTER:                      ; The body starts here.
    LD   B,CT_FDEST                ; The body
    CALL CT_DEF                    ; is here.
    JP   AC_LIVE                   ; It is reachable; return.

;@ROUTINE OUT A CLOBBERS BC,DE,HL,CARRY,ZERO,SIGN,PARITY,HALFCARRY
; EndCase: the arm ends as an if's does (AC_ARM: whether it falls
; through, its block, JP to the end); the next arm starts here, and the
; arm's labels are free again.

AC_SHUT:
    CALL HN_ENDA                   ; A lease ends.
    CALL AC_ARM                    ; The arm ends.
    LD   B,CT_FCONT                ; The next arm
    CALL CT_DEF                    ; is here.
    LD   B,CT_FDEST                ; The body's label, the first
    CALL CT_FBYTE                  ; the arm allocated: it and every later one
    LD   (EM_LCNT),A               ; are free.
    RET                            ; Back to the engine.

;@ROUTINE OUT A CLOBBERS BC,DE,HL,CARRY,ZERO,SIGN,PARITY,HALFCARRY
; EndSelect: anything but `end` after case else is syntax, at it, as a
; `case` there is (case else must be last); a select with no labelled arm
; is syntax, at `select`. The end is here, the select's ranges are free,
; and it completes when an arm falls through or it has no case else.

AC_FINAL:
    CALL PR_PEEK                   ; After case else
    CP   TK_END                    ; only `end`:
    LD   A,DG_CASE                 ; anything else, a `case` too,
    JP   NZ,DG_ISSUE               ; is syntax at it.
    CALL CT_MODE                   ; The mode: an arm with labels
    BIT  2,A                       ; is
    JR   Z,.EMPTY                  ; needed.
    XOR  2                         ; Bit 1 now says there is no case else:
    AND  3                         ; nonzero if the select completes.
    LD   (CT_FALLS),A              ; Record it.
    LD   B,CT_FEXIT                ; The end
    CALL CT_DEF                    ; is here.
    LD   B,CT_FSTEP                ; Its ranges
    CALL CT_FWORD                  ; are
    LD   (CT_RTOP),HL              ; free.
    CALL FW_JOIN                   ; The arms' states met.
    JP   CT_POP                    ; Close the frame; return.
.EMPTY:                        ; No arm with labels:
    LD   B,CT_FSTEP+2              ; syntax
    CALL CT_FIELD                  ; at `select`,
    LD   A,DG_CASE                 ; a case
    JP   DG_AT                     ; expected.

;@ROUTINE OUT A CLOBBERS BC,DE,HL,IX,IY,CARRY,ZERO,SIGN,PARITY,HALFCARRY
; Island CaseLabels: each label, a constant or a range of two, at the
; subject's type, low not above high (syntax at the label), overlapping
; none before it in the select (duplicate-case at the label), kept in
; the ranges and tested in turn (emitLabelTest); commas between them.

AC_LABEL:
    CALL CT_MODE                   ; A handle select's
    BIT  3,A                       ; arm is read
    RET  NZ                        ; (AC_CASE).
    CALL PR_SPOT                   ; The label's first token: its offset
    LD   (AC_SPOS),HL              ; is kept.
    LD   HL,(CT_RTOP)              ; Its range goes here,
    LD   DE,CT_RLIM                ; if there
    OR   A                         ; is
    SBC  HL,DE                     ; room
    ADD  HL,DE                     ; (HL restored).
    JR   C,.ROOM                   ; There is.
    CALL DG_RAISE                  ; The ranges are full:
    DB   DG_LABEL                  ; labels.
.ROOM:                         ; HL is the range.
    PUSH HL                        ; Kept.
    EX   DE,HL                     ; Its low value
    CALL .VALUE                    ; comes first.
    CALL PR_PEEK                   ; A range
    CP   TK_TO                     ; has `to`
    JR   NZ,.SINGLE                ; and a high value.
    CALL PR_TAKE                   ; Past `to`,
    CALL .HIGH                     ; the high value's place:
    CALL .VALUE                    ; the high value.
    CALL .HIGH                     ; HL is the low, DE the high:
    CALL .LESS                     ; is high below low?
    LD   A,DG_STMT                 ; Then syntax
    JR   C,.AT                     ; at the label.
    JR   .RANGED                   ; It is a range.
.SINGLE:                       ; One value:
    CALL .HIGH                     ; the high value
    LD   BC,4                      ; is
    LDIR                           ; the low.
.RANGED:                       ; The range is complete.
    LD   B,CT_FSTEP                ; The select's
    CALL CT_FWORD                  ; first range.
.OVER:                         ; HL is a range before it, or it.
    POP  DE                        ; The new range,
    PUSH DE                        ; kept.
    OR   A                         ; Is HL
    SBC  HL,DE                     ; the new
    ADD  HL,DE                     ; one?
    JR   Z,.KEEP                   ; Then none overlaps it.
    PUSH HL                        ; Keep the earlier range,
    PUSH DE                        ; and the new one:
    CALL .PAST                     ; DE is the earlier's high;
    EX   (SP),HL                   ; HL the new one's low (the earlier kept),
    CALL .LESS                     ; below it?
    JR   C,.BEYOND                 ; Then they are apart.
    CALL .PAST                     ; DE is the new one's high,
    POP  HL                        ; HL the earlier's low:
    CALL .LESS                     ; below it?
    JR   C,.APART                  ; Then they are apart.
    LD   A,DG_OVERL                ; They overlap: duplicate-case
.AT:                           ; A is the diagnostic,
    JP   DG_KEPT                   ; at the label. No return.
.BEYOND:                       ; The earlier range is kept twice.
    POP  HL                        ; Once is enough.
.APART:                        ; The earlier range does not overlap.
    POP  HL                        ; The
    LD   DE,8                      ; next
    ADD  HL,DE                     ; range.
    JR   .OVER                     ; Compare it.
.KEEP:                         ; HL is the new range: it is kept.
    LD   DE,8                      ; The next
    ADD  HL,DE                     ; is
    LD   (CT_RTOP),HL              ; after it.
    POP  HL                        ; The range
    CALL .TEST                     ; is tested.
    CALL PR_PEEK                   ; Another label
    CP   TK_COMMA                  ; after a comma?
    RET  NZ                        ; No: the labels are done.
    CALL PR_TAKE                   ; Past the comma.
    JP   AC_LABEL                  ; The next label.

;@ROUTINE OUT DE,HL CLOBBERS CARRY,ZERO,SIGN,PARITY,HALFCARRY
; HL is the range being made, kept on the stack beneath the caller's
; return address, and DE its high value's place.

.HIGH:                         ; The range is on the stack.
    POP  DE                        ; The return address;
    POP  HL                        ; the range,
    PUSH HL                        ; kept,
    PUSH DE                        ; beneath it.

;@ROUTINE IN HL OUT DE CLOBBERS CARRY,ZERO,SIGN,PARITY,HALFCARRY
; DE is HL plus four: a range's high value from its low. HL is kept.

.PAST:                         ; HL is a low value.
    LD   D,H                       ; DE
    LD   E,L                       ; is
    INC  DE                        ; four
    INC  DE                        ; bytes
    INC  DE                        ; on.
    INC  DE                        ; Done.
    RET                            ; DE is the high value.

;@ROUTINE IN DE OUT DE CLOBBERS A,BC,HL,IX,IY,CARRY,ZERO,SIGN,PARITY,HALFCARRY
; Parse a label's value, a constant (not-constant) that fits the
; subject's type (EX_FITS), and keep it at DE as four bytes, unsigned with
; a signed type's sign bit flipped, so that unsigned order is the value's.
; DE returns past them.

.VALUE:                        ; DE is where the value goes.
    PUSH DE                        ; Keep it.
    CALL .TYPE                     ; The subject's type
    PUSH AF                        ; (kept)
    CALL EX_CONST                  ; is expected: A is the metadata.
    LD   D,A                       ; Keep it.
    LD   A,DG_KNOWN                ; It must be known
    BIT  7,D                       ; (not-constant
    JP   Z,EX_EVAL                 ; at it).
    POP  AF                        ; It must fit
    LD   E,A                       ; the subject's
    LD   A,D                       ; type
    CALL EX_FITS                   ; (E is kept).
    LD   A,E                       ; The type's
    CALL GX_PROP                   ; properties,
    POP  DE                        ; (the value's place)
    PUSH AF                        ; kept.
    LD   HL,EX_KVAL                ; Its four
    LD   BC,4                      ; low bytes
    LDIR                           ; are copied.
    POP  AF                        ; The properties
    LD   C,A                       ; in C.
    EX   DE,HL                     ; HL is past them.
    PUSH HL                        ; Kept to return.
    LD   A,C                       ; Those beyond
    AND  7                         ; the type's size
    SUB  4                         ; are zero:
    JR   Z,.SIGN                   ; four less the size
    NEG                            ; of them,
    LD   B,A                       ; from the top.
.CLEAR:                        ; B bytes remain.
    DEC  HL                        ; The next down
    LD   (HL),0                    ; is zero.
    DJNZ .CLEAR                    ; HL is past the type's bytes.
.SIGN:                         ; HL is past the type's top byte.
    BIT  7,C                       ; A signed type's
    JR   Z,.FLIPPED                ; top byte
    DEC  HL                        ; has its
    LD   A,(HL)                    ; sign
    XOR  $80                       ; bit
    LD   (HL),A                    ; flipped.
.FLIPPED:                      ; The value is kept.
    POP  DE                        ; DE is past it.
    RET                            ; Done.

;@ROUTINE OUT ZERO CLOBBERS A,B,DE,HL,CARRY,SIGN,PARITY,HALFCARRY
; Zero if the range being tested is a single value.

.SAME:                         ; AC_BOUND is the range.
    LD   HL,(AC_BOUND)             ; Its low
    CALL .PAST                     ; and high, compared: fall into .LESS.

;@ROUTINE IN DE,HL OUT CARRY,ZERO CLOBBERS A,B,SIGN,PARITY,HALFCARRY
; Compare the four-byte values at DE and HL, unsigned: carry if DE's is
; below HL's, zero if they are equal. DE and HL are kept.

.LESS:                         ; DE and HL address the values.
    PUSH HL                        ; Keep
    PUSH DE                        ; both.
    INC  HL                        ; From
    INC  HL                        ; the
    INC  HL                        ; top
    INC  DE                        ; bytes
    INC  DE                        ; of
    INC  DE                        ; both
    LD   B,4                       ; down.
.DIGIT:                        ; HL and DE address a byte of each.
    LD   A,(DE)                    ; DE's less HL's:
    CP   (HL)                      ; a difference
    JR   NZ,.DECIDED               ; decides.
    DEC  HL                        ; Equal:
    DEC  DE                        ; the next
    DJNZ .DIGIT                    ; bytes down.
.DECIDED:                      ; Carry and zero are the answer.
    POP  DE                        ; Restore
    POP  HL                        ; both.
    RET                            ; Done.

;@ROUTINE OUT A CLOBBERS DE,HL,CARRY,ZERO,SIGN,PARITY,HALFCARRY
; A is the subject's type (CT_FBND).

.TYPE:                         ; The innermost frame is the select's.
    LD   B,CT_FBND                 ; Its type
    CALL CT_FBYTE                  ; field: A.
    RET                            ; Done.

;@ROUTINE IN HL CLOBBERS A,BC,DE,HL,CARRY,ZERO,SIGN,PARITY,HALFCARRY
; Test the subject against the range at HL (emitLabelTest), jumping to
; the arm's body when it lies in it.

.TEST:                         ; HL is the range.
    LD   (AC_BOUND),HL             ; Kept.
    CALL .PROPS                    ; A long
    BIT  2,A                       ; is compared through CMP32U,
    JR   NZ,.LONG                  ; a byte or a word in place:
    CALL .LOAD                     ; loaded,
    CALL .PROPS                    ; then
    BIT  1,A                       ; a word
    LD   HL,(AC_BOUND)             ; less low,
    JR   Z,.CPLOW                  ; a byte compared with it.
    CALL .WORDAT                   ; LD DE,low,
    CALL GA_LDDE                   ; then
    CALL GX_MINUS                  ; OR A, SBC HL,DE.
    JR   .LOWER                    ; Compared.
.CPLOW:                        ; CP low.
    LD   A,(HL)                    ; Its
    CALL EM_OPA                    ; operand,
    DB   $FE                       ; after the opcode.
    JR   .LOWER                    ; Compared.
.LONG:                         ; A long,
    LD   HL,(AC_BOUND)             ; compared
    CALL .CMP32                    ; with low.
.LOWER:                        ; The subject is compared with low.
    CALL .SAME                     ; A single value?
    JR   NZ,.SPAN                  ; No: a span.
    CALL .PROPS                    ; A word's
    BIT  1,A                       ; difference
    JR   Z,.EQUAL                  ; is tested:
    CALL EM_SEQ                    ; LD A,H, OR L,
    DB   2,$7C,$B5                 ; zero when equal.
.EQUAL:                        ; Equal is in.
    LD   C,$CA                     ; JP Z,body.
    JR   .BODY                     ; Return.
.SPAN:                         ; Low to high.
    CALL EM_LNEW                   ; A new skip label,
    LD   (AC_MODE),A               ; kept:
    LD   C,$DA                     ; JP C to it,
    CALL EM_JUMP                   ; below low.
    CALL .PROPS                    ; By size, with HL
    LD   HL,(AC_BOUND)             ; the low value
    CALL .PAST                     ; and DE the high:
    BIT  2,A                       ; a long is
    JR   NZ,.LHIGH                 ; compared with high;
    BIT  1,A                       ; a word
    JR   NZ,.WHIGH                 ; less low, with the span;
    LD   A,(DE)                    ; a byte with high plus one,
    INC  A                         ; zero when high is $FF:
    JR   Z,.ALWAYS                 ; then every value from low is in.
    CALL EM_OPA                    ; CP high+1:
    DB   $FE                       ; below it is in.
    JR   .BELOW                    ; JP C,body.
.WHIGH:                        ; A word.
    CALL .WORDAT                   ; Low
    EX   DE,HL                     ; in DE,
    CALL .WORDAT                   ; high in HL:
    LD   A,H                       ; $FFFF
    AND  L                         ; takes every
    INC  A                         ; value from low.
    JR   Z,.ALWAYS                 ; Otherwise
    SBC  HL,DE                     ; (carry clear) high less low
    INC  HL                        ; plus one,
    CALL GA_LDDE                   ; LD DE,n,
    CALL GX_MINUS                  ; OR A, SBC HL,DE.
.BELOW:                        ; Below it is in:
    LD   C,$DA                     ; JP C,body.
    DB   $21                       ; (LD HL,nn passes over .ALWAYS)
.ALWAYS:                       ; Every value from low is in:
    LD   C,$C3                     ; JP body.
    CALL .BODY                     ; Append it.
.SKIPPED:                      ; The skip label is here.
    LD   A,(AC_MODE)               ; It
    JP   EM_LDONE                  ; is defined and freed; return.
.LHIGH:                        ; A long, compared
    EX   DE,HL                     ; with high:
    CALL .CMP32                    ; below it
    LD   C,$DA                     ; (JP C)
    CALL .BODY                     ; or equal
    LD   C,$CA                     ; (JP Z)
    CALL .BODY                     ; is in.
    JR   .SKIPPED                  ; The skip label is here.

;@ROUTINE IN HL OUT HL CLOBBERS A
; HL is the word at HL.

.WORDAT:                       ; HL addresses a word.
    LD   A,(HL)                    ; Its low byte,
    INC  HL                        ; then
    LD   H,(HL)                    ; its high
    LD   L,A                       ; byte.
    RET                            ; HL is it.

;@ROUTINE IN C CLOBBERS A,BC,DE,HL,CARRY,ZERO,SIGN,PARITY,HALFCARRY
; Append the jump C to the arm's body.

.BODY:                         ; C is the jump.
    LD   B,CT_FDEST                ; The body's label.
    JP   CT_GO                     ; Append it; return.

;@ROUTINE OUT A CLOBBERS B,DE,HL,CARRY,ZERO,SIGN,PARITY,HALFCARRY
; A is the subject's type's properties (GX_PROP): its size in bits 0 to
; 2, bit 7 when it is signed.

.PROPS:                        ; The select's frame is innermost.
    CALL .TYPE                     ; Its type's
    JP   GX_PROP                   ; properties; return.

;@ROUTINE IN HL CLOBBERS A,BC,DE,HL,CARRY,ZERO,SIGN,PARITY,HALFCARRY
; Compare the long subject with the four-byte value at HL through CMP32U:
; LD DEHL,S [LD A,D, XOR $80, LD D,A] EXX, LD HL,low word, LD DE,high
; word, EXX, CALL CMP32U.

.CMP32:                        ; HL is the value.
    PUSH HL                        ; Keep it.
    CALL .LOAD                     ; The subject into DEHL.
    CALL EM_SEQ                    ; EXX, LD HL,
    DB   2,$D9,$21                 ; then
    POP  HL                        ; the value's
    PUSH HL                        ; low
    CALL .WORDAT                   ; word,
    CALL EM_WORD                   ; appended;
    POP  HL                        ; then
    INC  HL                        ; its
    INC  HL                        ; high
    CALL .WORDAT                   ; word
    CALL GA_LDDE                   ; as LD DE,nn;
    CALL EM_OP                     ; then
    DB   $D9                       ; EXX,
    CALL EM_HELP                   ; and CALL CMP32U.
    DW   HP_LCMPU                  ; Its ordinal and stack.
    RET                            ; Done.

;@ROUTINE CLOBBERS A,BC,DE,HL,CARRY,ZERO,SIGN,PARITY,HALFCARRY
; Load the subject from its slot (GX_FLOAD) and flip a signed one's sign
; bit: XOR $80 for a byte in A, through A for H or D.

.LOAD:                         ; The subject is in its slot.
    LD   B,CT_FVAR                 ; Its offset
    CALL CT_FIELD                  ; and type
    LD   E,(HL)                    ; follow
    INC  HL                        ; one
    LD   D,(HL)                    ; another
    INC  HL                        ; in
    LD   A,(HL)                    ; the frame.
    EX   DE,HL                     ; HL is the offset.
    PUSH AF                        ; (the type kept)
    CALL GX_FLOAD                  ; Into A, HL or DEHL.
    POP  AF                        ; The type's
    CALL GX_PROP                   ; properties:
    ADD  A,A                       ; A signed one's sign bit
    RET  NC                        ; is flipped (an unsigned one's not)
    BIT  3,A                       ; where its size, shifted up,
    JR   NZ,.FLIPD                 ; says: a long's in D,
    BIT  2,A                       ; a word's
    JR   NZ,.FLIPH                 ; in H.
    CALL EM_SEQX                   ; A byte, in A:
    DB   2,$EE,$80                 ; XOR $80.
.FLIPD:                        ; A long, in D: LD A,D,
    JP   GX_DSIGN                  ; XOR $80, LD D,A; return.
.FLIPH:                        ; A word, in H:
    CALL EM_SEQX                   ; LD A,H, XOR $80,
    DB   4,$7C,$EE,$80,$67         ; LD H,A.
