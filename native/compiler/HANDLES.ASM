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
    LD   HL,(HN_RCK)               ; An assignment's recheck,
    EX   (SP),HL                   ; kept under the return
    PUSH HL                        ; (HN_DONE restores it);
    PUSH BC                        ; the form kept.
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
    POP  HL                        ; The return;
    EX   (SP),HL                   ; the outer
    LD   (HN_RCK),HL               ; recheck restored.
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
; else type-mismatch, at HN_AT when an assignment set it (its target),
; else at the value. A name's value waits (DG_NYI); anything else is
; parsed as an expression, then type-mismatch.

HN_OWNV:                       ; E is the handle's type.
    PUSH DE                        ; Kept.
    CALL PR_SPOT                   ; The value's kind, A, and start, HL,
    LD   C,A                       ; (the kind kept)
    LD   DE,(HN_AT)                ; unless
    LD   A,D                       ; an assignment
    OR   E                         ; gave its
    JR   Z,.AT                     ; target's
    EX   DE,HL                     ; place.
.AT:                           ; HL is where a mismatch is reported.
    LD   DE,0                      ; HN_AT is
    LD   (HN_AT),DE                ; used once.
    POP  DE                        ; (the type)
    PUSH HL                        ; The place, kept.
    LD   A,C                       ; The kind:
    CP   TK_NONE                   ; none?
    JR   Z,.NONE                   ; LD HL,0.
    CP   TK_NAME                   ; A name's value
    JP   Z,TR_OPER                 ; waits (DG_NYI).
    CP   TK_NEW                    ; new?
    JR   Z,.NEW                    ; Its handle.
    XOR  A                         ; Anything else
    CALL EX_RUN                    ; is an expression,
    JR   .CLASH                    ; but no handle.
.NEW:                          ; new.
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
    CALL HN_RECK                   ; its identifier rechecked,
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
    LD   A,(RO_PPUSH)              ; An element at a run-time
    AND  8                         ; index has
    JR   NZ,.ZERO                  ; none (HN_ITEM).
    LD   A,(RO_PPUSH)              ; Through an identifier,
    AND  $10                       ; the slot word's
    JR   NZ,.CHECK                 ; owner is checked.
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
.CHECK:                        ; An identifier's slot word:
    LD   HL,(RO_POWN)              ; LD C,(IX+t),
    LD   DE,HN_LDBC                ; LD B,(IX+t+1),
    CALL GX_FACC                   ; then
    CALL EM_HELP                   ; CALL OWN_SETC.
    DW   HP_OWNC                   ; Appended.
    RET                            ; Done.

;@ROUTINE IN D,HL CLOBBERS A,BC,DE,HL,CARRY,ZERO,SIGN,PARITY,HALFCARRY
; An element at a run-time index (GA_ITEM): its place has no slot word
; for an owning store (bit 3 of RO_PPUSH), as the reference's indexArray
; leaves its designator none.

HN_ITEM:                       ; D and HL are the index.
    LD   A,(RO_PPUSH)              ; No
    OR   8                         ; slot
    LD   (RO_PPUSH),A              ; word;
    JP   GA_ITEM                   ; the element; return.

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
    POP  HL                        ; The slot
    LD   A,SY_U16                  ; holds
    JP   GX_FPUT                   ; the handle; return.

;@ROUTINE IN HL OUT HL CLOBBERS A,DE,CARRY,ZERO,SIGN,PARITY,HALFCARRY
; A local is allocated at offset HL after its initializer, whose
; temporaries come before it (localVar): HL is its payload (AC_DVAL) and
; the provisional symbol's. HL is kept.

HN_PAYL:                       ; HL is the local's offset.
    LD   (AC_DVAL),HL              ; Its payload,
    PUSH HL                        ; kept,
    LD   A,(SY_CNT)                ; the provisional
    CALL SY_AT                     ; symbol's,
    LD   DE,4                      ; after its spelling
    ADD  HL,DE                     ; and class:
    POP  DE                        ; the
    LD   (HL),E                    ; offset,
    INC  HL                        ; both
    LD   (HL),D                    ; bytes.
    EX   DE,HL                     ; HL is it.
    RET                            ; Done.

;@ROUTINE IN B CLOBBERS A,DE,HL,CARRY,ZERO,SIGN,PARITY,HALFCARRY
; A condition is parsed (if, elseif, while): its temporaries stay
; allocated until the enclosing block ends, as the reference's do, so the
; innermost frame's size as it opened takes them. B is kept.

HN_KEEPF:                      ; The condition is parsed.
    PUSH BC                        ; B kept.
    LD   B,CT_FSIZE                ; The frame's
    CALL CT_FIELD                  ; size as it opened
    LD   DE,(EM_FRAME)             ; is the frame's
    LD   (HL),E                    ; size
    INC  HL                        ; now.
    LD   (HL),D                    ; Both bytes.
    POP  BC                        ; B.
    RET                            ; Done.

;@ROUTINE CLOBBERS A,B,DE,HL,CARRY,ZERO,SIGN,PARITY,HALFCARRY
; An initializer rooted at the current NAME (AC_ROOT): `id`, declared as
; no symbol, begins id(...), which waits (DG_NYI).

HN_IDNM:                       ; The NAME is current.
    LD   HL,KW_ID                  ; `id`
    LD   B,2                       ; (two bytes)?
    CALL TK_MATCH                  ; If not,
    RET  NC                        ; an ordinary name.
    CALL SY_FIND                   ; A symbol named id
    RET  C                         ; is one; else
    JP   TR_OPER                   ; id(...) waits.

;@ROUTINE IN A,B OUT A CLOBBERS DE,HL,CARRY,ZERO,SIGN,PARITY,HALFCARRY
; An aggregate argument for parameter type B (AG_VAR for var), its path
; in hand, of type A: through an identifier (RO_PPUSH bit 4) it is
; not-writable for a var parameter, at the path, and its copy for any
; other waits (DG_NYI); through an owner (bit 5) it passes no owner word.
; A and BC are kept.

HN_ARGCK:                      ; The path is parsed.
    PUSH AF                        ; Kept.
    LD   A,(RO_PPUSH)              ; Through
    BIT  5,A                       ; a handle?
    JR   Z,.DONE                   ; No.
    BIT  4,A                       ; An identifier?
    JR   NZ,.ID                    ; Then refused.
    LD   HL,0                      ; An owner's:
    LD   (RO_POWN),HL              ; no owner word.
.DONE:                         ; Checked.
    POP  AF                        ; A.
    RET                            ; Back.
.ID:                           ; Through an identifier:
    BIT  7,B                       ; a value's copy
    JP   Z,TR_OPER                 ; waits;
    LD   A,DG_CONST                ; a var parameter's
    JP   EX_EVAL                   ; is not-writable, at the path.

;@ROUTINE CLOBBERS A,BC,DE,HL,CARRY,ZERO,SIGN,PARITY,HALFCARRY
; A handle assigned (RO_LET): the routine's own owning local, the subject
; of an enclosing select's some arm that leases it (mode bits 3, 6 and 7,
; its symbol's index in byte 17 of the frame), is not-writable, naming
; it, at it, as the reference's counting subject is.

HN_GUARD:                      ; The target is parsed.
    LD   A,(RO_PKIND)              ; Only a local
    CP   GA_FRAME                  ; can be
    RET  NZ                        ; leased.
    CALL HN_SIDX                   ; Its symbol's index,
    LD   C,A                       ; C.
    LD   A,(CT_DEPTH)              ; Each frame,
.FRAME:                        ; from the innermost:
    OR   A                         ; none
    RET  Z                         ; leases it.
    DEC  A                         ; Frame A:
    PUSH AF                        ; (kept)
    CALL CT_FRAME                  ; a select's
    LD   DE,CT_FMODE               ; some arm
    ADD  HL,DE                     ; leasing
    LD   A,(HL)                    ; its subject?
    AND  $C8                       ; (bits 7, 6
    CP   $C8                       ; and 3)
    JR   NZ,.NEXT                  ; No.
    LD   DE,17-CT_FMODE            ; Its subject's
    ADD  HL,DE                     ; index:
    LD   A,(HL)                    ; this
    CP   C                         ; local?
    JR   Z,.LEASED                 ; Then it is leased.
.NEXT:                         ; Not this frame.
    POP  AF                        ; The one
    JR   .FRAME                    ; outside.
.LEASED:                       ; not-writable,
    LD   HL,(RO_PROOT)             ; naming
    LD   A,DG_CONST                ; the
    CALL DG_SETN                   ; local,
    LD   HL,(EX_START)             ; at
    JP   DG_HERE                   ; it.

;@ROUTINE CLOBBERS A,BC,DE,HL,CARRY,ZERO,SIGN,PARITY,HALFCARRY
; A select's arm ends (EndCase): when it leased its subject, the subject
; is no longer leased by any enclosing arm either, as the reference's
; one counting flag a symbol has says (bit 7 of their modes cleared).

HN_ENDA:                       ; The innermost frame's arm ends.
    CALL CT_MODE                   ; A lease's
    AND  $C8                       ; arm
    CP   $C8                       ; (bits 7, 6 and 3)?
    RET  NZ                        ; No.
    LD   B,17                      ; Its subject's
    CALL CT_FBYTE                  ; index,
    LD   C,A                       ; C.
    LD   A,(CT_DEPTH)              ; Each frame
    DEC  A                         ; outside it:
.FRAME:                        ; frame A-1 next.
    OR   A                         ; None
    RET  Z                         ; left.
    DEC  A                         ; Frame A:
    PUSH AF                        ; (kept)
    CALL CT_FRAME                  ; its
    LD   DE,17                     ; subject,
    ADD  HL,DE                     ; if it
    LD   A,(HL)                    ; is this
    CP   C                         ; one,
    JR   NZ,.NEXT                  ; is
    LD   DE,CT_FMODE-17            ; leased
    ADD  HL,DE                     ; no
    RES  7,(HL)                    ; longer.
.NEXT:                         ; The one
    POP  AF                        ; outside.
    JR   .FRAME                    ; Next.

;@ROUTINE OUT A CLOBBERS DE,HL,CARRY,ZERO,SIGN,PARITY,HALFCARRY
; The index of the path's root symbol (RO_PROOT).

HN_SIDX:                       ; RO_PROOT is a record.
    LD   HL,(RO_PROOT)             ; Its
    LD   DE,-SY_BASE               ; offset
    ADD  HL,DE                     ; in the table,
    LD   DE,-SY_RECB               ; over the
    LD   A,$FF                     ; records'
.COUNT:                        ; size:
    INC  A                         ; one more
    ADD  HL,DE                     ; while
    JR   C,.COUNT                  ; it lasts.
    RET                            ; A is the index.

;@ROUTINE IN A OUT A CLOBBERS BC,DE,HL,CARRY,ZERO,SIGN,PARITY,HALFCARRY
; A is the next token's kind in a path (RO_PATH). A field selected
; through a handle (RO_OTYPE) goes through its slot (suffixes): an
; optional handle is optional-handle, at the dot, and a forward pool's
; pool-incomplete; the handle, a local's, is loaded and kept in a
; two-byte frame temporary, LD L,(IX+d), LD H,(IX+d+1), LD (IX+t),L,
; LD (IX+t+1),H, and the path goes on from the record at that address,
; computed, the temporary its slot word, an identifier's checked (ID_CHK)
; and kept with its generation. A handle is not indexed (not-indexable,
; at the bracket). A is kept.

RO_HSEL:                       ; A is the next token's kind.
    PUSH AF                        ; Kept.
    LD   A,(RO_OTYPE)              ; Through
    CALL PL_ISHND                  ; a handle?
    JR   NC,.KIND                  ; No.
    POP  AF                        ; The kind:
    PUSH AF                        ; a handle
    CP   TK_LBRAC                  ; is not indexed
    LD   A,DG_NOIDX                ; (not-indexable,
    JP   Z,DG_ISSUE                ; at the bracket);
    POP  AF                        ; a field
    PUSH AF                        ; (the kind again)
    CP   TK_DOT                    ; goes
    JR   NZ,.KIND                  ; through
    CALL HN_DEREF                  ; the slot.
.KIND:                         ; Done.
    POP  AF                        ; The kind.
    RET                            ; Back.

;@ROUTINE CLOBBERS A,BC,DE,HL,CARRY,ZERO,SIGN,PARITY,HALFCARRY
; The path in hand, a handle local, goes through its slot (RO_HSEL).

HN_DEREF:                      ; A dot follows the handle.
    LD   A,(RO_OTYPE)              ; The handle:
    RRA                            ; optional?
    LD   A,DG_OPTH                 ; Then
    JP   C,DG_ISSUE                ; tested first.
    LD   A,(RO_PKIND)              ; A place not
    CP   GA_FRAME                  ; in the frame waits
    JP   NZ,TR_OPER                ; (DG_NYI).
    LD   A,(RO_OTYPE)              ; The pool's
    CALL HN_REC                    ; record, if it has one
    PUSH AF                        ; (kept),
    LD   A,DG_PINC                 ; else pool-incomplete
    JP   Z,DG_ISSUE                ; when it is only forward.
    LD   A,(RO_OTYPE)              ; An identifier's
    BIT  1,A                       ; slot is
    LD   A,2                       ; checked:
    JR   Z,.SLOT                   ; four bytes,
    ADD  A,A                       ; its address and generation.
.SLOT:                         ; A is the temporary's size.
    CALL EM_ALLOC                  ; The temporary,
    LD   (RO_POWN),HL              ; the slot word.
    CALL HN_WIDT                   ; The handle,
    LD   HL,(RO_PADD)              ; the local's,
    CALL GX_FLOAD                  ; loaded;
    LD   A,(RO_OTYPE)              ; an identifier
    BIT  1,A                       ; is
    JR   Z,.KEEP                   ; checked,
    CALL EM_HELP                   ; CALL
    DW   HP_IDCHK                  ; ID_CHK.
.KEEP:                         ; HL is the slot's address:
    LD   HL,(RO_POWN)              ; it is
    PUSH HL                        ; (the temporary)
    LD   A,SY_U16                  ; kept,
    CALL GX_FPUT                   ; LD (IX+t),L, LD (IX+t+1),H;
    POP  HL                        ; an identifier's
    LD   A,(RO_OTYPE)              ; generation,
    BIT  1,A                       ; DE,
    LD   A,0                       ; (an owner's slot)
    JR   Z,.PLACE                  ; beside it:
    INC  HL                        ; EX DE,HL,
    INC  HL                        ; LD (IX+t+2),L,
    PUSH HL                        ; LD (IX+t+3),H,
    CALL EM_OP                     ; EX DE,HL.
    DB   $EB                       ; The
    POP  HL                        ; place
    LD   A,SY_U16                  ; is
    CALL GX_FPUT                   ; an
    CALL EM_OP                     ; identifier's
    DB   $EB                       ; slot:
    LD   A,$10                     ; bit 4.
.PLACE:                        ; A is the slot's kind,
    OR   $20                       ; through a handle (bit 5),
    LD   (RO_PPUSH),A              ; with nothing pushed.
    POP  AF                        ; The record
    LD   (RO_OTYPE),A              ; at that address
    LD   HL,GA_HELD                ; is the place,
    LD   (RO_PKIND),HL             ; computed and writable,
    LD   HL,0                      ; nothing on
    LD   (RO_PADD),HL              ; from it.
    RET                            ; Done.

;@ROUTINE OUT A CLOBBERS CARRY,ZERO,SIGN,PARITY,HALFCARRY
; The scalar type that holds handle RO_OTYPE (HN_WIDE's).

HN_WIDT:                       ; RO_OTYPE is a handle.
    LD   A,(RO_OTYPE)              ; Its type:
    JP   HN_WIDA                   ; its width.

;@ROUTINE IN A OUT A CLOBBERS HL,CARRY,ZERO,SIGN,PARITY,HALFCARRY
; RO_ASGN begins: the target's identifier slot, when it reaches its
; record through one (bit 4 of RO_PPUSH), is rechecked before the store
; (HN_RCK), else nothing. A is kept.

HN_RSET:                       ; A is the target's type.
    LD   HL,0                      ; None,
    PUSH AF                        ; (kept)
    LD   A,(RO_PPUSH)              ; unless
    AND  $10                       ; through
    JR   Z,.SET                    ; an identifier:
    LD   HL,(RO_POWN)              ; its slot.
.SET:                          ; HL is the slot or zero.
    LD   (HN_RCK),HL               ; Kept.
    POP  AF                        ; The type.
    RET                            ; Back.

;@ROUTINE CLOBBERS A,BC,DE,HL,CARRY,ZERO,SIGN,PARITY,HALFCARRY
; Recheck the target's identifier after the value and before the store
; (recheck): PUSH AF, PUSH HL, PUSH DE, its slot's address and generation,
; LD L,(IX+t), LD H,(IX+t+1), LD E,(IX+t+2), LD D,(IX+t+3), CALL ID_CHK,
; POP DE, POP HL, POP AF; nothing without one (HN_RCK zero).

HN_RECK:                       ; The value is in the registers.
    LD   HL,(HN_RCK)               ; The slot,
    LD   A,H                       ; if
    OR   L                         ; there
    RET  Z                         ; is one.
    PUSH HL                        ; Kept.
    CALL EM_SEQ                    ; PUSH AF, PUSH HL,
    DB   3,$F5,$E5,$D5             ; PUSH DE,
    LD   A,6                       ; six bytes
    CALL EM_PUSH                   ; pushed;
    POP  HL                        ; the
    PUSH HL                        ; slot's
    LD   A,SY_U16                  ; address
    CALL GX_FLOAD                  ; in HL,
    POP  HL                        ; its
    INC  HL                        ; generation
    INC  HL                        ; in DE,
    LD   DE,GX_DLDDE               ; HL
    CALL GX_FACC                   ; kept;
    CALL EM_HELP                   ; CALL
    DW   HP_IDCHK                  ; ID_CHK;
    CALL EM_SEQ                    ; POP DE, POP HL,
    DB   3,$D1,$E1,$F1             ; POP AF,
    LD   A,6                       ; six bytes
    JP   EM_POP                    ; popped; return.

;@ROUTINE IN A NORETURN
; No primary begins with token kind A, consumed: new, none and move
; begin handle values, which wait in an expression (DG_NYI); anything
; else is syntax, a value expected (PR_ETERM).

HN_ETERM:                      ; A is the token's kind.
    CP   TK_NEW                    ; new,
    JP   Z,TR_OPER                 ; none
    CP   TK_NONE                   ; and
    JP   Z,TR_OPER                 ; move
    CP   TK_MOVE                   ; wait;
    JP   Z,TR_OPER                 ; anything
    JP   PR_ETERM                  ; else is syntax.

;@ROUTINE CLOBBERS A,B,DE,HL,CARRY,ZERO,SIGN,PARITY,HALFCARRY
; The current NAME is a primary: `id(`, an identifier made, waits (DG_NYI).
; The NAME is kept.

HN_ISID:                       ; The NAME is current.
    LD   HL,KW_ID                  ; `id`
    LD   B,2                       ; (two bytes)?
    CALL TK_MATCH                  ; If not,
    RET  NC                        ; an ordinary name.
    LD   HL,(TK_PTR)               ; The NAME's
    PUSH HL                        ; spelling,
    LD   A,(TK_LEN)                ; kept across
    PUSH AF                        ; the peek.
    CALL PR_PEEK                   ; `(`
    CP   TK_LPAR                   ; follows?
    JP   Z,TR_OPER                 ; Then id(...) waits.
    POP  AF                        ; The NAME
    LD   (TK_LEN),A                ; is
    POP  HL                        ; current
    LD   (TK_PTR),HL               ; again.
    RET                            ; Back.

;-------------------------------------------------------------- select

;@ROUTINE IN A OUT A CLOBBERS BC,DE,HL,IX,IY,CARRY,ZERO,SIGN,PARITY,HALFCARRY
; SelectSubject's handle, of type A, the path in hand (selectHandle): its
; pool complete (pool-incomplete) and, owning, optional (type-mismatch),
; each at the subject; `select move` waits (DG_NYI). The handle, two bytes
; or an identifier's four, is loaded into a frame slot of its own, which
; the arms test, and the select's frame opens (AC_SOPEN) with mode bit 3
; set, and bit 6 when the subject is the routine's own owning local,
; whose `some` arm binds a lease.

HN_SEL:                        ; A is the handle's type.
    LD   (AC_BOUND),A              ; Kept for the frame.
    LD   A,(AC_MODE)               ; `select move`
    OR   A                         ; waits
    JP   Z,TR_OPER                 ; (DG_NYI).
    LD   A,(AC_BOUND)              ; The pool's
    CALL HN_REC                    ; record:
    LD   A,DG_PINC                 ; pool-incomplete
    JR   Z,.FAULT                  ; without one.
    LD   A,(AC_BOUND)              ; An owning
    AND  3                         ; handle that is
    LD   A,DG_CLASH                ; not optional
    JR   NZ,.OWNER                 ; is type-mismatch.
.FAULT:                        ; A is the diagnostic,
    LD   HL,(EX_START)             ; at the
    JP   DG_HERE                   ; subject.
.OWNER:                        ; The subject's kind:
    LD   C,8                       ; a handle select,
    LD   A,(AC_BOUND)              ; an
    BIT  1,A                       ; identifier
    JR   NZ,.LOAD                  ; no lease;
    LD   A,(RO_PKIND)              ; an owner's lease
    CP   GA_FRAME                  ; needs the frame,
    JR   NZ,.LOAD                  ; and
    LD   HL,(RO_PROOT)             ; the root,
    INC  HL                        ; a
    INC  HL                        ; local
    INC  HL                        ; aggregate's
    LD   A,(HL)                    ; class,
    CP   SY_AGGR+SY_LOCAL          ; alone
    JR   NZ,.LOAD                  ; (the path
    INC  HL                        ; of the
    INC  HL                        ; root's
    INC  HL                        ; own
    LD   A,(AC_BOUND)              ; type,
    CP   (HL)                      ; with no
    JR   NZ,.LOAD                  ; selection).
    LD   C,8+64                    ; Bit 6: a lease.
.LOAD:                         ; C is the mode.
    PUSH BC                        ; Kept.
    CALL HN_WIDE                   ; A word or a long:
    LD   (RO_OTYPE),A              ; the handle
    PUSH AF                        ; (the type kept)
    CALL GA_LOAD                   ; loaded.
    POP  AF                        ; Its
    PUSH AF                        ; size
    CALL GX_PROP                   ; in
    AND  7                         ; a slot
    CALL EM_ALLOC                  ; of its own,
    LD   (AC_INDEX),HL             ; for the frame,
    POP  AF                        ; which
    CALL GX_FPUT                   ; takes it.
    CALL HN_SIDX                   ; The subject's symbol,
    PUSH AF                        ; kept
    CALL AC_SOPEN                  ; as the select's frame opens.
    CALL CT_FLAGS                  ; Its mode
    POP  DE                        ; (D the subject)
    POP  BC                        ; takes
    LD   A,C                       ; the
    OR   (HL)                      ; subject's
    LD   (HL),A                    ; kind;
    LD   BC,17-CT_FMODE            ; its byte 17
    ADD  HL,BC                     ; the subject's
    LD   (HL),D                    ; index.
    RET                            ; Back to the engine.

;@ROUTINE IN A OUT A,ZERO CLOBBERS DE,HL,CARRY,SIGN,PARITY,HALFCARRY
; The record of the pool of handle type A, zero (Z) while it is only
; forward.

HN_REC:                        ; A is a handle's type.
    SUB  AG_HND                    ; The pool's
    RRCA                           ; index,
    RRCA                           ; a quarter
    AND  $3F                       ; of the offset:
    CALL PL_AT                     ; its entry's
    INC  HL                        ; record
    INC  HL                        ; byte,
    LD   A,(HL)                    ; zero if
    OR   A                         ; forward.
    RET                            ; A is it.

;@ROUTINE OUT A CLOBBERS DE,HL,CARRY,ZERO,SIGN,PARITY,HALFCARRY
; The scalar type that holds the innermost select's handle (CT_FBND): u16
; for an owner, u32 for an identifier's four bytes.

HN_WIDE:                       ; The select's handle.
    LD   A,(AC_BOUND)              ; Staged; fall into HN_WIDA.

;@ROUTINE IN A OUT A CLOBBERS CARRY,ZERO,SIGN,PARITY,HALFCARRY
; The scalar type that holds a handle of type A.

HN_WIDA:                       ; A is a handle's type:
    BIT  1,A                       ; an identifier?
    LD   A,SY_U16                  ; An owner
    RET  Z                         ; is a word,
    LD   A,SY_U32                  ; an identifier
    RET                            ; a long.

;@ROUTINE OUT A CLOBBERS BC,DE,HL,IX,IY,CARRY,ZERO,SIGN,PARITY,HALFCARRY
; CaseLabels of a handle select: `some(NAME)`, at most once, or `none`,
; at most once with case else (syntax at `case`, AC_SPOS); the subject
; tested, JP Z to the next arm for some, JP NZ for none. Mode bit 2 is
; some seen, bit 1 none or else, bit 7 that this arm is some.

HN_ARM:                        ; After `case`.
    CALL PR_PEEK                   ; some
    CP   TK_SOME                   ; or
    JR   Z,.SOME                   ; none?
    CP   TK_NONE                   ; Anything else:
    LD   A,DG_TOKEN+TK_ELSE        ; `else`
    JP   NZ,DG_ISSUE               ; expected.
    CALL PR_TAKE                   ; `none`:
    LD   C,2                       ; bit 1,
    CALL HN_ONCE                   ; once,
    RES  7,(HL)                    ; not some;
    LD   C,$C2                     ; JP NZ
    JR   HN_TEST                   ; on; return.
.SOME:                         ; `some`:
    CALL PR_TAKE                   ; taken,
    LD   C,4                       ; bit 2,
    CALL HN_ONCE                   ; once,
    SET  7,(HL)                    ; some.
    CALL PR_LEFT                   ; `(`,
    LD   E,TK_NAME                 ; the name
    CALL PR_NEED                   ; to bind,
    CALL EX_DECL                   ; retained,
    CALL PR_RIGHT                  ; `)`.
    LD   C,$CA                     ; JP Z on.

;@ROUTINE IN C CLOBBERS A,BC,DE,HL,CARRY,ZERO,SIGN,PARITY,HALFCARRY
; Test the select's handle in its slot, LD A,H, OR L for an owner, CALL
; ID_TEST for an identifier, and append the jump C to the next arm.

HN_TEST:                       ; C is JP Z or JP NZ.
    PUSH BC                        ; Kept.
    LD   B,CT_FVAR                 ; The slot,
    CALL CT_FWORD                  ; HL:
    LD   B,CT_FBND                 ; the type
    PUSH HL                        ; (the slot kept)
    CALL CT_FBYTE                  ; of the handle,
    LD   (AC_BOUND),A              ; staged,
    CALL HN_WIDE                   ; its width:
    POP  HL                        ; loaded
    PUSH AF                        ; (kept)
    CALL GX_FLOAD                  ; from the slot.
    POP  AF                        ; An owner
    CP   SY_U16                    ; is tested
    JR   NZ,.ID                    ; LD A,H, OR L,
    CALL EM_SEQ                    ; an identifier
    DB   2,$7C,$B5                 ; by
    JR   .JUMP                     ; the runtime:
.ID:                           ; CALL
    CALL EM_HELP                   ; ID_TEST.
    DW   HP_IDTST                  ; Then
.JUMP:                         ; the jump
    POP  BC                        ; C
    LD   B,CT_FCONT                ; to the next
    JP   CT_GO                     ; arm; return.

;@ROUTINE IN C OUT HL CLOBBERS A,B,DE,CARRY,ZERO,SIGN,PARITY,HALFCARRY
; Mode bit C of the select is set once: a second some, or a second none
; or case else, is syntax at `case` (AC_SPOS). HL returns the mode's
; address.

HN_ONCE:                       ; C is the bit.
    CALL CT_FLAGS                  ; The mode:
    LD   A,(HL)                    ; the bit
    AND  C                         ; already
    LD   A,DG_STMT                 ; set
    JR   NZ,.TWICE                 ; is syntax;
    LD   A,(HL)                    ; else
    OR   C                         ; it is
    LD   (HL),A                    ; set.
    RET                            ; HL is the mode.
.TWICE:                        ; At `case`:
    LD   HL,AC_SPOS                ; syntax.
    JP   DG_AT                     ; No return.

;@ROUTINE OUT A CLOBBERS BC,DE,HL,IX,IY,CARRY,ZERO,SIGN,PARITY,HALFCARRY
; CaseElse of a handle select: once, with none (syntax at `case`), the
; subject tested, JP NZ to the next arm; the arm is reachable.

HN_ELSE:                       ; After `case else`.
    LD   C,2                       ; Bit 1,
    CALL HN_ONCE                   ; once,
    RES  7,(HL)                    ; not some.
    LD   C,$C2                     ; JP NZ
    CALL HN_TEST                   ; on.
    JP   AC_LIVE                   ; Reachable; return.

;@ROUTINE OUT A CLOBBERS BC,DE,HL,CARRY,ZERO,SIGN,PARITY,HALFCARRY
; CaseBody of a handle select: a some arm binds its name, retained
; (EX_DECL), at the start of its block: to the routine's own owning local
; (mode bit 6), a lease, an alias through the subject's slot (SY_LEASE),
; of the pool's record; otherwise an identifier, non-optional, in four
; bytes of its own, LD the slot, CALL ID_MAKE for an owner, then stored.
; The arm is reachable.

HN_TAKEN:                      ; The arm's body begins.
    BIT  7,A                       ; A some arm?
    JP   Z,AC_LIVE                 ; No: nothing to bind.
    PUSH AF                        ; The mode, kept.
    LD   B,CT_FBND                 ; The handle's
    CALL CT_FBYTE                  ; type,
    LD   (AC_BOUND),A              ; staged.
    LD   B,CT_FVAR                 ; The
    CALL CT_FWORD                  ; slot,
    POP  AF                        ; HL. The mode:
    BIT  6,A                       ; a lease?
    JR   Z,.ID                     ; No: an identifier.
    LD   B,H                       ; The slot is
    LD   C,L                       ; the payload,
    CALL EX_RENEW                  ; the name
    LD   D,SY_AGGR+SY_PARAM+SY_PVAR+SY_LEASE ; a writable lease,
    CALL EX_PREP                   ; declared;
    LD   A,(AC_BOUND)              ; its type
    CALL HN_REC                    ; the record.
    JR   .TAG                      ; Committed.
.ID:                           ; HL is the slot.
    PUSH HL                        ; Kept.
    LD   A,4                       ; Four bytes
    CALL EM_ALLOC                  ; of its own,
    EX   (SP),HL                   ; kept; the slot:
    CALL HN_WIDE                   ; the handle
    PUSH AF                        ; (its width)
    CALL GX_FLOAD                  ; loaded;
    POP  AF                        ; an owner's
    CP   SY_U16                    ; identifier
    JR   NZ,.STORE                 ; is made,
    CALL EM_HELP                   ; CALL
    DW   HP_IDMK                   ; ID_MAKE;
.STORE:                        ; DEHL is the identifier,
    POP  HL                        ; stored
    PUSH HL                        ; (the place kept)
    LD   A,SY_U32                  ; in its
    CALL GX_FPUT                   ; four bytes.
    POP  BC                        ; Its offset,
    CALL EX_RENEW                  ; the name's
    LD   D,SY_AGGR+SY_LOCAL        ; payload,
    CALL EX_PREP                   ; declared;
    LD   A,(AC_BOUND)              ; its type
    AND  $FE                       ; an identifier,
    OR   AG_HID                    ; not optional.
.TAG:                          ; A is the type.
    CALL SY_TAG                    ; Committed.
    JP   AC_LIVE                   ; Reachable; return.

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
