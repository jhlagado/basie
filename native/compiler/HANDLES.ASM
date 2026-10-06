;==========================================================================
;  Handles: new, owning values, handle locals and frees
;==========================================================================
;
;  The code of the owning handles, as the reference compiler generates it
;  (ref/compile/compiler.ts: newExpression, ownValue, storeOwning,
;  emitFrees, localVar): `new P(fields)` and `new? P(fields)` take a slot
;  from pool P (POOL_TRY), trap when it is full or yield none for new?,
;  keep its address in a frame temporary and assign the fields given, in
;  order, through it, the rest staying zero; `none` is a handle of no
;  slot. An owning handle is stored through OWN_SET, which frees the old
;  value and links the slot to the location, and a local's through LINK0.
;  An owning handle local is freed where its scope ends (POOL_DEL), at
;  the end of its block and at every return, fail, exit and continue that
;  leaves it, the innermost scope first, each scope's locals in the order
;  they were declared (the reference's scopesFrom and emitFrees).
;
;  Scopes. A block's symbols follow its enclosing block's in the symbol
;  table: each control frame keeps the count when it opened (CT_FSYMS),
;  the body's start is RO_BODY less one, and the routine's parameters
;  start at RO_GLOBS. So a scope is a run of symbols, and the scopes from
;  a frame outward are the runs between those marks.
;
;  Principal entries:
;    HN_NEW    parse new or new? and generate it: HL at run time
;    HN_OWNV   parse an owning value for a handle of type E: new or none
;    HN_LET    assign to the handle path in hand (RO_ASGN)
;    HN_LINIT  a handle local's initializer
;    HN_INFER  an inferred local's initializer that begins with new
;    HN_NOINI  a handle local without one: optional or needs-initializer
;    HN_BIND   commit a handle local: LINK0, then its slot
;    HN_ENDB   the frees of the innermost frame's block, as it ends
;    HN_ENDR   the frees of the routine's body, as it ends
;    HN_EXIT   the frees from loop frame A outward to it (exit, continue)
;    HN_FAIL   the frees of every scope, around PUSH AF and POP AF
;    HN_RET    the frees of every scope, the result of type A kept

;@ROUTINE OUT A CLOBBERS BC,DE,HL,IX,IY,CARRY,ZERO,SIGN,PARITY,HALFCARRY
; Parse `new P(fields)` or `new? P(fields)`, `new` the next token, and
; generate it: LD HL,info, CALL POOL_TRY, LD A,H, OR L, then CALL
; Z,TRAP_POO, or for new? JP Z past the fields; the slot's address into a
; two-byte frame temporary; each field given assigned through it (RO_ASGN,
; the temporary its slot word); then the address back in HL. P must be a
; pool (wrong-class, naming it) declared in full (pool-incomplete, naming
; it), and the fields at most the record's (arity). A returns the fresh
; handle's type, optional for new?.

HN_NEW:                        ; `new` is next.
    CALL PR_TAKE                   ; Taken.
    CALL PR_PEEK                   ; A `?`
    LD   C,0                       ; makes
    CP   TK_QUEST                  ; the handle
    JR   NZ,.NAMED                 ; optional.
    PUSH BC                        ; (C kept)
    CALL PR_TAKE                   ; Taken,
    POP  BC                        ; and
    INC  C                         ; AG_HOPT.
.NAMED:                        ; C is the form.
    PUSH BC                        ; Kept.
    LD   E,TK_NAME                 ; The pool's
    CALL PR_NEED                   ; name:
    CALL PL_FIND                   ; a pool?
    POP  BC                        ; (the form)
    JR   C,.POOL                   ; Yes.
    LD   A,DG_CLASS                ; No: wrong-class,
    JP   DG_NAMED                  ; naming it.
.POOL:                         ; A is the pool's index.
    LD   B,A                       ; Kept.
    ADD  A,A                       ; Its handle:
    ADD  A,A                       ; four times the index,
    ADD  A,AG_HND                  ; from the handles' base,
    ADD  A,C                       ; with the form,
    LD   C,A                       ; C.
    LD   A,B                       ; The pool's
    CALL PL_AT                     ; entry:
    LD   E,(HL)                    ; its
    INC  HL                        ; ordinal,
    LD   D,(HL)                    ; DE,
    INC  HL                        ; and its
    LD   A,(HL)                    ; record,
    OR   A                         ; if it has one.
    JP   Z,.FORWARD                ; Only forward: pool-incomplete.
    PUSH BC                        ; The type,
    PUSH AF                        ; the record
    PUSH DE                        ; and the ordinal kept.
    CALL PR_LEFT                   ; `(`.
    CALL EM_OP                     ; LD HL,
    DB   $21                       ; the pool's
    POP  HL                        ; information,
    LD   DE,0                      ; its
    CALL EM_REF                    ; address;
    CALL EM_HELP                   ; CALL POOL_TRY;
    DW   HP_PTRY                   ; then
    CALL EM_SEQ                    ; LD A,H, OR L:
    DB   2,$7C,$B5                 ; a slot?
    POP  AF                        ; The record
    POP  BC                        ; and the type.
    PUSH AF                        ; (the record kept)
    BIT  0,C                       ; new?
    JR   Z,.TRAP                   ; No: pool-full traps.
    PUSH BC                        ; (the type kept)
    LD   C,$CA                     ; JP Z
    CALL EM_FWD                    ; past the fields;
    POP  BC                        ; B is
    LD   B,A                       ; its label.
    JR   .SLOT                     ; The slot.
.TRAP:                         ; new: CALL Z,TRAP_POO.
    PUSH BC                        ; (the type kept)
    LD   A,$CC                     ; CALL Z
    LD   L,HP_PFULL&$FF            ; to the pool-full
    CALL EM_TRAP                   ; trap.
    POP  BC                        ; The type.
.SLOT:                         ; C the type, B new?'s label.
    POP  AF                        ; The record.
    PUSH BC                        ; Kept, with the label.
    PUSH AF                        ; (the record)
    LD   A,2                       ; A two-byte
    CALL EM_ALLOC                  ; temporary, HL:
    PUSH HL                        ; (kept)
    LD   A,SY_U16                  ; the slot's address
    CALL GX_FPUT                   ; stored there.
    POP  DE                        ; The temporary.
    POP  AF                        ; The record's
    PUSH DE                        ; (the temporary kept)
    CALL AG_DESC                   ; descriptor:
    INC  HL                        ; its
    LD   A,(HL)                    ; ordinal,
    CALL AG_RENT                   ; its entry:
    LD   C,(HL)                    ; its first field, C,
    INC  HL                        ; and its
    LD   B,(HL)                    ; count, B.
    PUSH BC                        ; (kept from the peek)
    CALL PR_PEEK                   ; Any
    POP  BC                        ; fields
    CP   TK_RPAR                   ; given?
    JR   Z,.CLOSE                  ; No.
.FIELD:                        ; Field C next, B left.
    LD   A,B                       ; Another
    OR   A                         ; beyond the record's:
    JP   Z,.ARITY                  ; arity.
    PUSH BC                        ; The loop, kept.
    LD   A,C                       ; The field's
    CALL AG_FIELD                  ; entry:
    INC  HL                        ; past
    INC  HL                        ; its
    INC  HL                        ; name,
    LD   A,(HL)                    ; its type
    INC  HL                        ; and
    LD   E,(HL)                    ; its
    INC  HL                        ; offset,
    LD   D,(HL)                    ; DE.
    PUSH AF                        ; (the type kept)
    PUSH DE                        ; (and the offset)
    LD   HL,6                      ; The temporary,
    ADD  HL,SP                     ; under them and the loop:
    LD   E,(HL)                    ; its
    INC  HL                        ; offset,
    LD   D,(HL)                    ; DE,
    EX   DE,HL                     ; HL,
    LD   (RO_POWN),HL              ; the slot word of the field's place.
    LD   A,SY_U16                  ; The slot's address
    CALL GX_FLOAD                  ; loaded,
    POP  HL                        ; the field's offset
    CALL GA_ADDC                   ; added:
    POP  AF                        ; the field's
    LD   (RO_OTYPE),A              ; place,
    LD   HL,GA_HELD                ; computed,
    LD   (RO_PKIND),HL             ; writable (RO_PRO zero),
    XOR  A                         ; with nothing
    LD   (RO_PPUSH),A              ; pushed.
    LD   A,(RO_OTYPE)              ; Its type:
    CALL RO_ASGN                   ; the value assigned.
    POP  BC                        ; The loop:
    INC  C                         ; the next field,
    DEC  B                         ; one fewer.
    PUSH BC                        ; (the loop kept)
    CALL PR_PEEK                   ; Another
    CP   TK_COMMA                  ; after
    JR   NZ,.FIELDS                ; a comma?
    CALL PR_TAKE                   ; The comma
    POP  BC                        ; taken.
    JR   .FIELD                    ; The next field.
.FIELDS:                       ; No comma:
    POP  BC                        ; (dropped)
.CLOSE:                        ; Every field given is assigned.
    CALL PR_RIGHT                  ; `)`.
    POP  HL                        ; The temporary:
    LD   A,SY_U16                  ; the slot's address
    CALL GX_FLOAD                  ; in HL.
    POP  BC                        ; C the type, B the label.
    BIT  0,C                       ; new?
    JR   Z,.DONE                   ; Its label
    PUSH BC                        ; is
    LD   A,B                       ; here:
    CALL EM_LDONE                  ; none, or the slot.
    POP  BC                        ; The type.
.DONE:                         ; The handle is in HL.
    LD   A,C                       ; A is its type.
    RET                            ; Done.
.ARITY:                        ; More fields than the record's:
    CALL PR_PEEK                   ; arity, at the
    CALL DG_RAISE                  ; extra one.
    DB   DG_ARITY                  ; No return.
.FORWARD:                      ; The pool has no record yet:
    LD   A,DG_PINC                 ; pool-incomplete,
    JP   DG_NAMED                  ; naming it.

;@ROUTINE IN E CLOBBERS A,BC,DE,HL,IX,IY,CARRY,ZERO,SIGN,PARITY,HALFCARRY
; Parse an owning value for a handle of type E into HL at run time
; (ownValue): new or new? of its pool, an optional one only for an
; optional handle; none, LD HL,0, only for an optional handle; either
; else type-mismatch, at the value. Anything else is refused for now.

HN_OWNV:                       ; E is the handle's type.
    PUSH DE                        ; Kept.
    CALL PR_SPOT                   ; The value's start, HL:
    POP  DE                        ; (the type)
    PUSH HL                        ; kept.
    CP   TK_NONE                   ; none?
    JR   Z,.NONE                   ; LD HL,0.
    CP   TK_NEW                    ; new?
    JP   NZ,TR_OPER                ; Anything else waits (DG_NYI).
    PUSH DE                        ; The type, kept.
    CALL HN_NEW                    ; The new handle, A its type.
    POP  DE                        ; The target's type, E:
    XOR  E                         ; the same pool
    CP   2                         ; and kind?
    JR   NC,.CLASH                 ; No.
    RRA                            ; The same optionality,
    JR   NC,.SAME                  ; or an optional value
    BIT  0,E                       ; for an optional
    JR   NZ,.SAME                  ; target only.
.CLASH:                        ; Not the target's:
    POP  HL                        ; type-mismatch
    LD   A,DG_CLASH                ; at the
    JP   DG_HERE                   ; value.
.SAME:                         ; It fits.
    POP  HL                        ; (dropped)
    RET                            ; HL holds the handle.
.NONE:                         ; none:
    BIT  0,E                       ; an optional
    JR   Z,.CLASH                  ; target only.
    POP  HL                        ; (dropped)
    CALL PR_TAKE                   ; Taken:
    LD   HL,0                      ; LD HL,0.
    JP   GX_LDHL                   ; Appended; return.

;@ROUTINE IN A CLOBBERS A,BC,DE,HL,IX,IY,CARRY,ZERO,SIGN,PARITY,HALFCARRY
; Assign to the handle path in hand, of type A (assign): an owning handle
; takes an owning value (HN_OWNV); at a computed place its address,
; already in HL, is pushed first, PUSH HL, the value, POP DE; elsewhere
; the value is pushed, PUSH HL, the place's address, EX DE,HL, POP HL
; (storeOwning); then the slot word, LD BC,0 or the place's (RO_POWN),
; and CALL OWN_SET. An identifier is not assigned yet (DG_NYI).

HN_LET:                        ; A is the handle's type.
    BIT  1,A                       ; AG_HID: an identifier
    JP   NZ,TR_OPER                ; waits.
    LD   A,(RO_PKIND)              ; A computed
    CP   GA_HELD                   ; place?
    JR   NZ,.PLACED                ; No.
    CALL GX_PUSHW                  ; PUSH HL: its address.
    CALL .VALUE                    ; The value,
    CALL GA_POPDE                  ; POP DE: the place.
    JR   HN_OWNS                   ; Stored; return.
.PLACED:                       ; Static, in the frame or an alias.
    CALL .VALUE                    ; The value,
    CALL GX_PUSHW                  ; PUSH HL,
    CALL GA_ADDR                   ; the place's address,
    CALL EM_OP                     ; EX DE,HL,
    DB   $EB                       ; then
    CALL EM_OP                     ; POP HL:
    DB   $E1                       ; the value,
    CALL EM_POP2                   ; two bytes fewer pushed.
    JR   HN_OWNS                   ; Stored; return.
.VALUE:                        ; The value, the place kept across it.
    CALL RO_KEEP                   ; The place kept.
    LD   A,(RO_OTYPE)              ; The handle's
    LD   E,A                       ; type:
    CALL HN_OWNV                   ; a value for it, in HL.
    CALL RO_BACK                   ; The place back
    RET                            ; (RO_BACK must be called).

;@ROUTINE CLOBBERS A,BC,DE,HL,CARRY,ZERO,SIGN,PARITY,HALFCARRY
; Store HL at the location DE through OWN_SET, the slot word in BC: the
; place's (RO_POWN, a word at IX+n, ixWord) or LD BC,0.

HN_OWNS:                       ; HL the value, DE the location.
    LD   HL,(RO_POWN)              ; The slot word:
    LD   A,H                       ; is
    OR   L                         ; there one?
    JR   Z,.ZERO                   ; No: zero.
    LD   DE,HN_LDBC                ; LD C,(IX+n), LD B,(IX+n+1),
    CALL GX_FACC                   ; near or far.
    JR   .CALL                     ; Then the call.
.ZERO:                         ; No slot word:
    CALL EM_SEQ                    ; LD BC,0.
    DB   3,$01,0,0                 ; Then
.CALL:                         ; the call:
    CALL EM_HELP                   ; CALL OWN_SET.
    DW   HP_OWN                    ; Appended.
    RET                            ; Done.

; ixWord into BC, in GX_FACC's form (GENEXPR.ASM).

HN_LDBC:                       ; ixWord: BC = (IX+offset).
    DB   1,6                       ; Two bytes; the far form pushes six.
    DB   2,$E5,$D5                 ; PUSH HL, PUSH DE;
    DB   5,$4E,$23,$46,$D1,$E1     ; LD C,(HL), INC HL, LD B,(HL), POP DE, POP HL.
    DB   $4E,$46,0                 ; LD C,(IX+d), LD B,(IX+d+1).

;@ROUTINE OUT A,CARRY,ZERO CLOBBERS SIGN,PARITY,HALFCARRY,BC,DE,HL,IX,IY
; A handle local's initializer, its type AG_CTYPE: an owning value
; (HN_OWNV), committed by HN_BIND (AC_LHND in EX_RMETA). An identifier's
; waits (DG_NYI).

HN_LINIT:                      ; The local's type is a handle.
    LD   A,(AG_CTYPE)              ; Its type:
    BIT  1,A                       ; an identifier
    JP   NZ,TR_OPER                ; waits.
    LD   E,A                       ; An owning
    CALL HN_OWNV                   ; value, in HL.
    LD   A,AC_LHND                 ; The local
    LD   (EX_RMETA),A              ; is bound to it.
    RET                            ; Back to the engine.

;@ROUTINE OUT A,CARRY,ZERO CLOBBERS SIGN,PARITY,HALFCARRY,BC,DE,HL,IX,IY
; An inferred local's initializer that is a handle: new or new? makes the
; local's type (localVar); none has no definite type (no-definite-type, at
; it), and a move waits (DG_NYI). Carry clear when the initializer is
; none of these, A its first token's kind.

HN_INFER:                      ; The initializer's first token:
    CALL PR_PEEK                   ; none?
    CP   TK_NONE                   ; It has
    LD   A,DG_INFER                ; no definite
    JP   Z,DG_ISSUE                ; type.
    CALL PR_PEEK                   ; A move
    CP   TK_MOVE                   ; waits;
    JP   Z,TR_OPER                 ; new
    CP   TK_NEW                    ; makes
    JR   Z,.NEW                    ; the type;
    OR   A                         ; anything else
    RET                            ; is not a handle (carry clear).
.NEW:                          ; new:
    CALL HN_NEW                    ; The handle, A its type,
    LD   (AG_CTYPE),A              ; the local's.
    SCF                            ; A handle.
    RET                            ; Done.

;@ROUTINE OUT A CLOBBERS DE,HL,CARRY,ZERO,SIGN,PARITY,HALFCARRY
; DefaultLocalInitializer for a local of type AG_CTYPE: a handle that is
; not optional needs an initializer (needs-initializer, at the name).

HN_NOINI:                      ; No initializer.
    LD   A,(AG_CTYPE)              ; The type:
    CALL PL_ISHND                  ; a handle
    RET  NC                        ; that is
    RRA                            ; not
    RET  C                         ; optional?
    LD   A,DG_NEEDI                ; needs-initializer,
    LD   HL,AC_DPOS                ; at the
    JP   DG_AT                     ; name.

;@ROUTINE IN HL CLOBBERS A,BC,DE,HL,CARRY,ZERO,SIGN,PARITY,HALFCARRY
; Commit a handle local, its slot at IX+HL just allocated: CALL LINK0,
; then its value stored there, LD (IX+d),L, LD (IX+d+1),H; its symbol
; takes the slot's offset, which a new in its initializer moved on.

HN_BIND:                       ; HL is the slot's offset.
    PUSH HL                        ; Kept.
    CALL EM_HELP                   ; CALL LINK0.
    DW   HP_LINK0                  ; Then
    POP  HL                        ; the slot
    PUSH HL                        ; (kept)
    LD   A,SY_U16                  ; holds
    CALL GX_FPUT                   ; the handle.
    LD   A,(SY_CNT)                ; The provisional
    CALL SY_AT                     ; symbol's
    INC  HL                        ; payload,
    INC  HL                        ; past its
    INC  HL                        ; spelling
    INC  HL                        ; and class,
    POP  DE                        ; is the
    LD   (HL),E                    ; slot's
    INC  HL                        ; offset.
    LD   (HL),D                    ; Both bytes.
    RET                            ; Done.

;@ROUTINE IN A OUT A CLOBBERS CARRY,ZERO,SIGN,PARITY,HALFCARRY
; A is the next token's kind in a path (RO_PATH): a field or an element
; selected through a handle (RO_OTYPE) waits (DG_NYI). A is kept.

RO_HSEL:                       ; A is the next token's kind.
    CP   TK_DOT                    ; A field
    JR   Z,.SELECT                 ; or
    CP   TK_LBRAC                  ; an element
    RET  NZ                        ; selected?
.SELECT:                       ; Yes:
    PUSH AF                        ; (kept)
    LD   A,(RO_OTYPE)              ; through
    CALL PL_ISHND                  ; a handle?
    JP   C,TR_OPER                 ; Not yet.
    POP  AF                        ; The kind.
    RET                            ; Back.

; ---------------------------------------------------------------- frees

;@ROUTINE IN B,C CLOBBERS A,BC,DE,HL,CARRY,ZERO,SIGN,PARITY,HALFCARRY
; The frees of symbols B to C-1, a scope's, in order: each owning handle
; local, LD L,(IX+d), LD H,(IX+d+1), LD A,H, OR L, CALL NZ,POOL_DEL, LD
; HL,0, LD (IX+d),L, LD (IX+d+1),H; or, while HN_MODE is set, nothing
; written, HN_SEEN set if there is one.

HN_SEG:                        ; B the first, C past the last.
    LD   A,B                       ; Any
    CP   C                         ; left?
    RET  NC                        ; No.
    PUSH BC                        ; The run, kept.
    CALL SY_AT                     ; Symbol B's record:
    INC  HL                        ; its
    INC  HL                        ; class
    INC  HL                        ; byte,
    LD   A,(HL)                    ; an aggregate
    CP   SY_AGGR+SY_LOCAL          ; local's?
    JR   NZ,.NEXT                  ; No.
    INC  HL                        ; Its
    LD   E,(HL)                    ; offset,
    INC  HL                        ; DE,
    LD   D,(HL)                    ; and
    INC  HL                        ; its
    LD   A,(HL)                    ; type:
    CALL PL_ISHND                  ; a handle
    JR   NC,.NEXT                  ; that
    AND  AG_HID                    ; owns?
    JR   NZ,.NEXT                  ; Not an identifier.
    LD   HL,HN_SEEN                ; One
    LD   (HL),H                    ; is seen (H nonzero).
    LD   A,(HN_MODE)               ; Only
    OR   A                         ; looking?
    JR   NZ,.NEXT                  ; Then nothing is written.
    PUSH DE                        ; The offset, kept.
    EX   DE,HL                     ; The handle
    LD   A,SY_U16                  ; into
    CALL GX_FLOAD                  ; HL,
    CALL EM_SEQ                    ; LD A,H, OR L:
    DB   2,$7C,$B5                 ; a slot?
    LD   C,$C4                     ; CALL NZ
    LD   DE,HP_PDEL                ; POOL_DEL,
    LD   A,D                       ; its stack
    CALL EM_HWORD                  ; figure counted;
    LD   HL,0                      ; LD HL,0,
    CALL GX_LDHL                   ; then
    POP  HL                        ; the slot
    LD   A,SY_U16                  ; is
    CALL GX_FPUT                   ; none.
.NEXT:                         ; Symbol B is done.
    POP  BC                        ; The run:
    INC  B                         ; the next.
    JR   HN_SEG                    ; Until its end.

;@ROUTINE CLOBBERS A,BC,DE,HL,CARRY,ZERO,SIGN,PARITY,HALFCARRY
; A block ends: the frees of the innermost frame's scope, from the count
; when it opened (CT_FSYMS) to SY_CNT.

HN_ENDB:                       ; The innermost frame's block ends.
    LD   B,CT_FSYMS                ; Its first
    CALL CT_FBYTE                  ; symbol,
    LD   B,A                       ; B,
    LD   A,(SY_CNT)                ; to the
    LD   C,A                       ; last.
    JP   HN_SEG                    ; Freed; return.

;@ROUTINE CLOBBERS A,BC,DE,HL,CARRY,ZERO,SIGN,PARITY,HALFCARRY
; The body ends: the frees of its scope, from RO_BODY less one to SY_CNT.

HN_ENDR:                       ; The body's block ends.
    LD   A,(RO_BODY)               ; Its first symbol
    DEC  A                         ; is
    LD   B,A                       ; B,
    LD   A,(SY_CNT)                ; to the
    LD   C,A                       ; last.
    JP   HN_SEG                    ; Freed; return.

;@ROUTINE IN A CLOBBERS A,BC,DE,HL,CARRY,ZERO,SIGN,PARITY,HALFCARRY
; exit or continue: the frees of the scopes from the innermost frame's to
; loop frame A's, innermost first.

HN_EXIT:                       ; A is the loop's frame.
    LD   C,0                       ; Not the routine's scopes.

;@ROUTINE IN A,C CLOBBERS A,BC,DE,HL,CARRY,ZERO,SIGN,PARITY,HALFCARRY
; The frees of the scopes from the innermost frame's to frame A's,
; innermost first (scopesFrom), and, when C is nonzero, then the body's
; and the parameters'.

HN_FROM:                       ; A the outermost frame, C the routine's too.
    PUSH BC                        ; C kept.
    LD   B,A                       ; B is the outermost.
    LD   A,(SY_CNT)                ; The run's end,
    LD   C,A                       ; C.
    LD   A,(CT_DEPTH)              ; From the innermost frame.
.FRAME:                        ; Frame A-1 next, if not below B.
    CP   B                         ; Below
    JR   Z,.FRAMES                 ; the outermost?
    DEC  A                         ; Frame A:
    PUSH AF                        ; (kept)
    PUSH BC                        ; (with the outermost)
    CALL CT_FRAME                  ; its
    LD   DE,CT_FSYMS               ; first
    ADD  HL,DE                     ; symbol,
    LD   B,(HL)                    ; B.
    PUSH BC                        ; (kept)
    CALL HN_SEG                    ; Its scope freed.
    POP  DE                        ; Its first symbol
    POP  BC                        ; is the next
    LD   C,D                       ; run's end.
    POP  AF                        ; The frame.
    JR   .FRAME                    ; The one outside.
.FRAMES:                       ; C is the end of the next run out.
    POP  DE                        ; The routine's
    LD   A,E                       ; too?
    OR   A                         ; If not,
    RET  Z                         ; done.
    LD   A,(RO_BODY)               ; The body's
    DEC  A                         ; first
    LD   B,A                       ; symbol,
    PUSH BC                        ; (kept)
    CALL HN_SEG                    ; its scope freed;
    POP  BC                        ; then
    LD   C,B                       ; before it
    LD   A,(RO_GLOBS)              ; the
    LD   B,A                       ; parameters'.
    JP   HN_SEG                    ; Freed; return.

;@ROUTINE CLOBBERS A,BC,DE,HL,CARRY,ZERO,SIGN,PARITY,HALFCARRY
; fail: PUSH AF, the frees of every scope, POP AF (failStatement).

HN_FAIL:                       ; The code is in A at run time.
    CALL EM_OP                     ; PUSH AF.
    DB   $F5                       ; Then
    CALL HN_ALL                    ; every owner freed,
    CALL EM_OP                     ; POP AF.
    DB   $F1                       ; Done.
    RET                            ; Back.

;@ROUTINE CLOBBERS A,BC,DE,HL,CARRY,ZERO,SIGN,PARITY,HALFCARRY
; The frees of every scope, the innermost first.

HN_ALL:                        ; Every scope of the routine.
    XOR  A                         ; From frame zero,
    LD   C,1                       ; and the routine's.
    JR   HN_FROM                   ; Freed; return.

;@ROUTINE IN A CLOBBERS A,BC,DE,HL,CARRY,ZERO,SIGN,PARITY,HALFCARRY
; A return of a result of type A, zero for none (emitReturn): when any
; scope has an owner, the result is kept around the frees of every scope,
; PUSH AF, PUSH HL or PUSH DE and PUSH HL as it is one, two or four bytes
; (an aggregate's address is not kept unless its size is one of those, as
; the reference has it), then popped.

HN_RET:                        ; A is the result's type.
    LD   HL,0                      ; No bytes
    OR   A                         ; without
    JR   Z,.SIZED                  ; a result;
    CALL AG_SIZE                   ; else its size.
.SIZED:                        ; HL is the size.
    PUSH HL                        ; Kept.
    LD   A,1                       ; Look
    LD   (HN_MODE),A               ; for
    XOR  A                         ; an
    LD   (HN_SEEN),A               ; owner
    CALL HN_ALL                    ; in every scope.
    XOR  A                         ; Write
    LD   (HN_MODE),A               ; again.
    POP  HL                        ; The size.
    LD   A,(HN_SEEN)               ; None:
    OR   A                         ; nothing
    RET  Z                         ; to free.
    LD   A,H                       ; A size
    OR   A                         ; past
    JP   NZ,HN_ALL                 ; 255 is not kept.
    LD   A,L                       ; One,
    LD   HL,HN_KEEP1               ; two
    DEC  A                         ; or
    JR   Z,.KEEP                   ; four
    LD   HL,HN_KEEP2               ; bytes
    DEC  A                         ; are
    JR   Z,.KEEP                   ; kept;
    LD   HL,HN_KEEP4               ; any
    SUB  2                         ; other
    JP   NZ,HN_ALL                 ; is not.
.KEEP:                         ; HL is the push, the pop after it.
    CALL EM_RUN                    ; The push;
    PUSH HL                        ; (the pop kept)
    CALL HN_ALL                    ; the frees;
    POP  HL                        ; the
    JP   EM_RUN                    ; pop; return.

; The result's push and pop, each a count and its bytes.

HN_KEEP1: DB  1,$F5,1,$F1      ; PUSH AF; POP AF.
HN_KEEP2: DB  1,$E5,1,$E1      ; PUSH HL; POP HL.
HN_KEEP4: DB  2,$D5,$E5,2,$E1,$D1 ; PUSH DE, PUSH HL; POP HL, POP DE.
