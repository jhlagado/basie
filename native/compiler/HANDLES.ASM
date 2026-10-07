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
    JR   Z,.ARITY                  ; arity.
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
    CALL HN_OWN0                   ; The value,
    JP   HN_TAIL                   ; ending there; return.

HN_OWN0:                       ; E is the handle's type.
    PUSH DE                        ; Kept.
    CALL HN_PLACE                  ; The value's kind, C, and place, HL.
    POP  DE                        ; (the type)
    PUSH HL                        ; The place, kept.
    LD   A,C                       ; The kind:
    CP   TK_NONE                   ; none?
    JR   Z,.NONE                   ; LD HL,0.
    CP   TK_NAME                   ; A routine's
    JR   Z,.CALL                   ; result?
    CP   TK_MOVE                   ; move?
    JR   Z,.MOVE                   ; Its handle.
    CP   TK_NEW                    ; new?
    JR   Z,.NEW                    ; Its handle.
    XOR  A                         ; Anything else
    CALL EX_RUN                    ; is an expression,
    JR   .CLASH                    ; but no handle.
.CALL:                         ; A name:
    PUSH DE                        ; (the type kept)
    CALL HN_IDQ                    ; id(...) is
    JR   C,.IDEX                   ; no owner;
    CALL HN_SCAL                   ; a scalar's expression neither;
    JR   C,.OTHER                  ; else
    CALL PR_TAKE                   ; taken,
    CALL RO_FIND                   ; a routine's
    JR   Z,.ROUTINE                ; result;
    CALL SY_FIND                   ; anything else
    JP   NC,SY_UNDEF               ; undeclared is no name;
    CALL RO_NAMED                  ; a path's value:
    CALL PL_ISHND                  ; an owner's
    JR   NC,.OTHER                 ; is moved,
    BIT  1,A                       ; not copied
    JR   NZ,.OTHER                 ; (needs-move),
    CALL HN_TAIL                   ; unless an operand;
    POP  DE                        ; (the type)
    POP  HL                        ; at the
    LD   A,DG_NMOVE                ; value.
    JP   DG_HERE                   ; No return.
.IDEX:                         ; id(...):
    CALL HN_IDEX                   ; an identifier,
    JR   .OTHER                    ; no owner.
.ROUTINE:                      ; A is the routine.
    CALL HN_VOIDQ                  ; It has a result (no-value),
    CALL RO_CALL                   ; called: A its result,
    CALL PL_ISHND                  ; an owning
    JR   NC,.OTHER                 ; handle,
    BIT  1,A                       ; fresh;
    JR   Z,.FRESH                  ; checked as new's is.
.OTHER:                        ; Any other result
    POP  DE                        ; is no
    JR   .CLASH                    ; owner's value.
.MOVE:                         ; move:
    PUSH DE                        ; (the type kept)
    CALL HN_MOVE                   ; the handle moved, A its type.
    JR   .FRESH                    ; Checked as new's is.
.NEW:                          ; new.
    PUSH DE                        ; The type, kept.
    CALL HN_NEW                    ; The new handle, A its type.
.FRESH:                        ; A fresh handle of type A.
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
    LD   A,FW_VALUE                ; A value
    LD   (HN_VKIND),A              ; it is.
    RET                            ; HL holds the handle.
.NONE:                         ; none:
    BIT  0,E                       ; an optional
    JR   Z,.CLASH                  ; target only.
    POP  HL                        ; (dropped)
    LD   A,FW_NONE                 ; None
    LD   (HN_VKIND),A              ; it is.
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
    JP   NZ,HN_IDLET               ; is a value.
    LD   A,(RO_PKIND)              ; A computed
    CP   GA_HELD                   ; place?
    JR   NZ,.PLACED                ; No.
    CALL GX_PUSHW                  ; PUSH HL: its address.
    CALL .VALUE                    ; The value,
    CALL HN_RECK                   ; its identifier rechecked,
    CALL GA_POPDE                  ; POP DE: the place.
    JR   HN_OWNS                   ; Stored; return (not the root alone).
.PLACED:                       ; Static, in the frame or an alias.
    CALL .VALUE                    ; The value,
    CALL GX_PUSHW                  ; PUSH HL,
    CALL GA_ADDR                   ; the place's address,
    CALL EM_OP                     ; EX DE,HL,
    DB   $EB                       ; then
    CALL EM_OP                     ; POP HL:
    DB   $E1                       ; the value,
    CALL EM_POP2                   ; two bytes fewer pushed.
    CALL HN_OWNS                   ; Stored;
    LD   A,(HN_VKIND)              ; the root alone, tracked,
    JP   FW_SET                    ; holds it now; return.
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
    LD   E,A                       ; an identifier's
    BIT  1,A                       ; value
    JR   Z,.OWNER                  ; in DEHL,
    CALL HN_IDV                    ; or
    JR   .BOUND                    ; an
.OWNER:                        ; owner's
    CALL HN_OWNV                   ; in HL.
.BOUND:                        ; The value is read.
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
    CP   TK_MOVE                   ; or new
    JR   Z,.MOVE                   ; makes
    CP   TK_NEW                    ; the type;
    JR   Z,.NEW                    ; so does
    CP   TK_NAME                   ; a routine's
    JR   NZ,.NOT                   ; name
    CALL HN_IDQ                    ; (or id(...),
    JR   C,.ID                     ; an identifier)
    CALL RO_FIND                   ; whose
    JR   NZ,.NOT                   ; result
    CALL AC_ROOT                   ; is a handle:
    CALL PL_ISHND                  ; its
    JR   NC,.NOT                   ; result's
    PUSH AF                        ; (or a variable's,
    LD   E,A                       ; whose value
    CALL HN_OWNV                   ; waits):
    POP  AF                        ; the value's type.
    JR   .TYPED                    ; The local's.
.NOT:                          ; Anything else
    OR   A                         ; is not
    RET                            ; a handle (carry clear).
.MOVE:                         ; move:
    CALL HN_MOVE                   ; the handle moved,
    JR   .TYPED                    ; A its type.
.ID:                           ; id(...), `id` taken:
    CALL HN_IDEX                   ; the identifier made,
    JR   .TYPED                    ; A its type.
.NEW:                          ; new:
    CALL HN_NEW                    ; the handle, A its type,
.TYPED:                        ; the local's,
    CALL HN_TAIL                   ; ending there,
    LD   (AG_CTYPE),A              ; a value.
    LD   A,FW_VALUE                ; Its
    LD   (HN_VKIND),A              ; state.
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
    LD   A,(AG_CTYPE)              ; An identifier
    BIT  1,A                       ; is stored,
    LD   A,SY_U32                  ; its four bytes
    JP   NZ,GX_FPUT                ; (DEHL); return.
    PUSH HL                        ; Kept.
    LD   A,(HN_VKIND)              ; Its state:
    CALL HN_STAT                   ; a value or none.
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
    EX   DE,HL                     ; HL is it;
    LD   A,FW_NONE                 ; its state none until bound.

;@ROUTINE IN A CLOBBERS DE,CARRY,ZERO,SIGN,PARITY,HALFCARRY
; The provisional symbol's flow state is A. HL is kept.

HN_STAT:                       ; A is the state.
    PUSH HL                        ; Kept.
    PUSH AF                        ; (the state)
    LD   A,(SY_CNT)                ; The provisional
    CALL SY_AT                     ; symbol's
    LD   DE,FW_STATE               ; state
    ADD  HL,DE                     ; byte
    POP  AF                        ; takes
    LD   (HL),A                    ; it.
    POP  HL                        ; HL.
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

;@ROUTINE OUT CARRY CLOBBERS A,BC,DE,HL,ZERO,SIGN,PARITY,HALFCARRY
; Carry if the path in hand's root, the routine's own owning local, is the
; subject of an enclosing select's some arm that leases it, as the
; reference's counting subject is.

HN_LEASD:                      ; The root is RO_PROOT.
    CALL HN_SIDX                   ; Its symbol's index,
    LD   C,A                       ; C,
    LD   A,(CT_DEPTH)              ; from the innermost frame; fall into HN_SCAN.

;@ROUTINE IN A,C OUT A,HL,CARRY CLOBBERS DE,ZERO,SIGN,PARITY,HALFCARRY
; Find the next frame below frame A, inward to outward, whose some arm
; leases symbol C (mode bits 7, 6 and 3, its subject's index in byte 17):
; carry, A its index and HL its mode's address; no carry if none. BC is
; kept.

HN_SCAN:                       ; A frames to look below.
    OR   A                         ; None
    RET  Z                         ; (carry clear).
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
    CP   C                         ; symbol?
    LD   DE,CT_FMODE-17            ; (back to
    ADD  HL,DE                     ; its mode)
    JR   NZ,.NEXT                  ; No.
    POP  AF                        ; A is its index.
    SCF                            ; Found.
    RET                            ; HL is its mode.
.NEXT:                         ; Not this frame.
    POP  AF                        ; The one
    JR   HN_SCAN                   ; outside.

;@ROUTINE IN A OUT A CLOBBERS BC,DE,HL,CARRY,ZERO,SIGN,PARITY,HALFCARRY
; An assignment's target of type A, parsed (assign): a tracked owner
; assigned as a whole is moved in this statement, at its name; any other
; path through one uses it directly (noteMove, noteDirect). A is kept.

HN_NOTE:                       ; A is the target's type.
    PUSH AF                        ; Kept.
    LD   HL,(EX_START)             ; At the
    LD   (FW_PLACE),HL             ; root's name:
    CALL FW_ALONE                  ; the root alone
    JR   NZ,.DIRECT                ; is moved,
    CALL FW_MOVE                   ; if tracked;
    JR   .DONE                     ; any other path
.DIRECT:                       ; through one
    CALL FW_SEEN                 ; uses it.
.DONE:                         ; Noted.
    POP  AF                        ; A.
    RET                            ; Back.

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
    LD   C,1                       ; Usable, a dereference
    CALL FW_USEC                   ; (checkUsable).
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
    RET  NC                        ; an ordinary name;
    CALL HN_PAREN                  ; with `(`
    JP   Z,TR_OPER                 ; it waits.
    RET                            ; Back.

;@ROUTINE IN A OUT A CLOBBERS HL,CARRY,ZERO,SIGN,PARITY,HALFCARRY
; A parameter's type (CommitParameter): an owning handle, not var, is a
; value in the frame; a var one an optional owner (a slot-holder,
; var-parameter otherwise); an identifier waits (DG_NYI). An aggregate is
; accepted, but a var owning one that is no record, whose owner word is
; not yet passed, waits. A is kept; HL is not.

HN_PTYPE:                      ; A is the type.
    CALL PL_ISHND                  ; A handle?
    JR   C,.HANDLE                 ; Not:
    LD   HL,RO_VARP                ; a value
    INC  (HL)                      ; aggregate
    DEC  (HL)                      ; is
    RET  Z                         ; accepted;
    PUSH AF                        ; (the type
    PUSH DE                        ; and DE kept)
    CALL PL_OWNS                   ; a var one, if owning,
    JR   NC,.KEEP                  ; must be
    POP  DE                        ; a record
    POP  AF                        ; (an owning
    PUSH AF                        ; array
    PUSH DE                        ; waits).
    CALL AG_DESC                   ; Its
    LD   A,(HL)                    ; kind:
    CP   AG_KREC                   ; a record?
    JP   NZ,TR_OPER                ; If not, it waits.
.KEEP:                         ; Accepted.
    POP  DE                        ; DE
    POP  AF                        ; and the type.
    RET                            ; Back.
.HANDLE:                       ; A handle:
    LD   HL,RO_VARP                ; A var handle,
    INC  (HL)                      ; a slot-holder,
    DEC  (HL)                      ; must be
    JR   Z,.VALUE                  ; an optional
    BIT  1,A                       ; owner
    JR   NZ,.EVAR                  ; (var-parameter,
    BIT  0,A                       ; at the
    RET  NZ                        ; name).
.EVAR:                         ; var on another handle:
    LD   A,DG_VARP                 ; var-parameter,
    JP   DG_KEPT                   ; at its name.
.VALUE:                        ; A value:
    BIT  1,A                       ; an identifier
    JP   NZ,TR_OPER                ; waits.
    RET                            ; Accepted.

;@ROUTINE IN A OUT A CLOBBERS CARRY,ZERO,SIGN,PARITY,HALFCARRY
; A result's type (SaveSubResult): an owning handle is returned in HL; an
; identifier waits, as does an owning aggregate (DG_NYI). A is kept.

HN_RTYPE:                      ; A is the type.
    CALL PL_ISHND                  ; Not a handle:
    JP   NC,PL_LATER               ; no owning aggregate yet; return.
    BIT  1,A                       ; An identifier
    JP   NZ,TR_OPER                ; waits.
    RET                            ; Accepted.

;@ROUTINE CLOBBERS A,BC,DE,HL,CARRY,ZERO,SIGN,PARITY,HALFCARRY
; The routine's end, after its body's frees: when control reaches it,
; its parameters' owners are freed (emitReturn's frees of the routine's
; scope, without a result).

HN_PEND:                       ; The body has ended.
    LD   A,(CT_FALLS)              ; Unreachable:
    OR   A                         ; nothing
    RET  Z                         ; to free.
    LD   A,(RO_BODY)               ; The parameters,
    DEC  A                         ; before
    LD   C,A                       ; the body,
    LD   A,(RO_GLOBS)              ; from
    LD   B,A                       ; the first.
    JR   HN_SEG                    ; Freed; return.

;@ROUTINE IN A CLOBBERS A,BC,DE,HL,IX,IY,CARRY,ZERO,SIGN,PARITY,HALFCARRY
; An argument for an owning handle parameter of type A (argument): an
; owning value (HN_OWNV), then CALL LINK0; the caller pushes HL. Only a
; statement's call takes one, and not a call nested in its arguments,
; where the reference's rules for move in expressions apply (DG_NYI).

HN_ARG:                        ; A is the parameter's type.
    OR   A                         ; A slot-holder
    JP   M,HN_SLARG                ; takes a location.
    LD   E,A                       ; Kept.
    LD   A,(HN_SCALL)              ; A statement's
    OR   A                         ; call,
    JP   Z,TR_OPER                 ; at
    LD   A,(RO_DEPTH)              ; its
    DEC  A                         ; own
    JP   NZ,TR_OPER                ; depth?
    CALL HN_OWNV                   ; The value, in HL,
    CALL EM_HELP                   ; CALL
    DW   HP_LINK0                  ; LINK0.
    RET                            ; Pushed by the caller.

;@ROUTINE IN A OUT A CLOBBERS BC,DE,HL,IX,IY,CARRY,ZERO,SIGN,PARITY,HALFCARRY
; BeginReturnValue of a routine whose result is an owning handle of type
; A: its value is read here (HN_OWNV, then CALL LINK0, emitReturn), before
; the engine predicts the return's form, which a `new`, `none` or `move`
; would not begin; the bare return's action (AC_BARE) then ends it as the
; return of a value (HN_RETF).

HN_RETV:                       ; A is the result's type.
    PUSH AF                        ; (kept)
    CALL PR_PEEK                   ; A bare return
    CP   TK_EOL                    ; is AC_BARE's
    POP  DE                        ; (D the type)
    RET  Z                         ; (return-form).
    LD   E,D                       ; An owning
    CALL HN_OWNV                   ; value, in HL,
    CALL EM_HELP                   ; CALL
    DW   HP_LINK0                  ; LINK0;
    LD   A,1                       ; the return
    LD   (HN_RETF),A               ; has its value.
    RET                            ; Back to the engine.

;@ROUTINE IN A OUT A CLOBBERS BC,DE,HL,CARRY,ZERO,SIGN,PARITY,HALFCARRY
; Routine A, its name current, is called for a value: one without a result
; (or main) has none (no-value, naming it, at it). A is kept.

HN_VOIDQ:                      ; A is the routine.
    CP   RO_MAIN                   ; Main
    JP   Z,RO_EVOID                ; has none;
    PUSH AF                        ; (kept)
    CALL RO_SUBAT                  ; another's
    LD   DE,RO_RTYPE               ; result
    ADD  HL,DE                     ; type:
    LD   A,(HL)                    ; none?
    OR   A                         ; Then
    JP   Z,RO_EVOID                ; no-value.
    POP  AF                        ; The routine.
    RET                            ; Back.

;@ROUTINE IN A CLOBBERS A,BC,DE,HL,CARRY,ZERO,SIGN,PARITY,HALFCARRY
; A statement's call returned A: an owning handle it discards is freed
; (discard): LD A,H, OR L, CALL NZ,POOL_DEL.

HN_DISC:                       ; A is the result's type.
    CALL PL_ISHND                  ; An owning
    RET  NC                        ; handle
    AND  AG_HID                    ; result?
    RET  NZ                        ; (An identifier is not.)

;@ROUTINE CLOBBERS A,BC,DE,HL,CARRY,ZERO,SIGN,PARITY,HALFCARRY
; Free the owning handle in HL at run time: LD A,H, OR L, CALL NZ,POOL_DEL,
; its stack figure counted.

HN_DELHL:                      ; The handle is in HL.
    CALL EM_SEQ                    ; LD A,H, OR L,
    DB   2,$7C,$B5                 ; then
    LD   C,$C4                     ; CALL NZ
    LD   DE,HP_PDEL                ; POOL_DEL,
    LD   A,D                       ; its stack figure
    JP   EM_HWORD                  ; counted; return.

;@ROUTINE OUT C,HL CLOBBERS A,B,DE,CARRY,ZERO,SIGN,PARITY,HALFCARRY
; The next token's kind, C, and where a mismatch of the value it begins
; is reported, HL: HN_AT when an assignment set it (its target), else the
; value's start. HN_AT is then zero.

HN_PLACE:                      ; A value is next.
    CALL PR_SPOT                   ; Its kind, A, and start, HL,
    LD   C,A                       ; (the kind kept)
    LD   DE,(HN_AT)                ; unless
    LD   A,D                       ; an assignment
    OR   E                         ; gave its
    JR   Z,.AT                     ; target's
    EX   DE,HL                     ; place.
.AT:                           ; HL is where a mismatch is reported.
    LD   DE,0                      ; HN_AT is
    LD   (HN_AT),DE                ; used once.
    RET                            ; Done.

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
    OR   SY_PARAM-SY_LOCAL         ; local's or
    LD   C,A                       ; parameter's, var
    AND  $FF-SY_PVAR-SY_PFROM      ; or from too,
    CP   SY_AGGR+SY_PARAM          ; but no lease's?
    JR   NZ,.NEXT                  ; No.
    INC  HL                        ; Its
    LD   E,(HL)                    ; offset,
    INC  HL                        ; DE,
    LD   D,(HL)                    ; and
    INC  HL                        ; its
    LD   A,(HL)                    ; type:
    CALL PL_ISHND                  ; a handle
    JR   NC,.AGGR                  ; that
    AND  AG_HID                    ; owns?
    JR   NZ,.NEXT                  ; Not an identifier.
    BIT  1,C                       ; A slot-holder (SY_PVAR)
    JR   NZ,.HOLDER                ; is counted, never freed.
    LD   HL,HN_SEEN                ; One
    LD   (HL),H                    ; is seen (H nonzero).
    LD   A,(HN_MODE)               ; Only
    OR   A                         ; looking?
    JR   NZ,.NEXT                  ; Then nothing is written.
    PUSH DE                        ; The offset, kept.
    EX   DE,HL                     ; The handle
    LD   A,SY_U16                  ; into
    CALL GX_FLOAD                  ; HL,
    CALL HN_DELHL                  ; freed if a slot;
    LD   HL,0                      ; LD HL,0,
    CALL GX_LDHL                   ; then
    POP  HL                        ; the slot
    LD   A,SY_U16                  ; is
    CALL GX_FPUT                   ; none.
    JR   .NEXT                     ; Done.
.AGGR:                         ; An aggregate: if owning, a
    CALL PL_OWNS                   ; parameter (owning locals wait)
    JR   NC,.NEXT                  ; counted, never freed.
.HOLDER:                       ; A slot-holder: an owner a return
    LD   A,(HN_MODE)               ; counts (hasOwners) when
    LD   (HN_SEEN),A               ; looking; none to free.
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
    JR   HN_SEG                    ; Freed; return.

;@ROUTINE CLOBBERS A,BC,DE,HL,CARRY,ZERO,SIGN,PARITY,HALFCARRY
; The body ends: the frees of its scope, from RO_BODY less one to SY_CNT.

HN_ENDR:                       ; The body's block ends.
    LD   A,(RO_BODY)               ; Its first symbol
    DEC  A                         ; is
    LD   B,A                       ; B,
    LD   A,(SY_CNT)                ; to the
    LD   C,A                       ; last.
    JR   HN_SEG                    ; Freed; return.

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
    CALL HN_ANY                    ; An owner in any scope?
    POP  HL                        ; The size.
    RET  Z                         ; None: nothing to free.
    LD   A,H                       ; A size
    OR   A                         ; past
    JR   NZ,HN_ALL                 ; 255 is not kept.
    LD   A,L                       ; One,
    LD   HL,HN_KEEP1               ; two
    DEC  A                         ; or
    JR   Z,.KEEP                   ; four
    LD   HL,HN_KEEP2               ; bytes
    DEC  A                         ; are
    JR   Z,.KEEP                   ; kept;
    LD   HL,HN_KEEP4               ; any
    SUB  2                         ; other
    JR   NZ,HN_ALL                 ; is not.
.KEEP:                         ; HL is the push, the pop after it.
    CALL EM_RUN                    ; The push;
    PUSH HL                        ; (the pop kept)
    CALL HN_ALL                    ; the frees;
    POP  HL                        ; the
    JP   EM_RUN                    ; pop; return.

;@ROUTINE OUT A,ZERO CLOBBERS BC,DE,HL,CARRY,SIGN,PARITY,HALFCARRY
; NZ if any scope of the routine holds an owner a return frees (the
; reference's hasOwners): HN_ALL run only looking.

HN_ANY:                        ; Every scope of the routine.
    LD   A,1                       ; Look
    LD   (HN_MODE),A               ; for
    XOR  A                         ; an
    LD   (HN_SEEN),A               ; owner
    CALL HN_ALL                    ; in every scope.
    XOR  A                         ; Write
    LD   (HN_MODE),A               ; again.
    LD   A,(HN_SEEN)               ; NZ if
    OR   A                         ; one is
    RET                            ; seen.

;@ROUTINE CLOBBERS A,BC,DE,HL,CARRY,ZERO,SIGN,PARITY,HALFCARRY
; `else fail` passes a failure on (RO_FAILS): with no owner in scope, JP
; C to the exit; with owners, which leave the routine, JP NC past, PUSH AF,
; every owner freed, POP AF, JP to the exit, as a fail statement frees
; them. A and carry reach the exit as the call left them.

HN_RELAY:                      ; A failable call has returned.
    CALL HN_ANY                    ; Owners?
    LD   C,$DA                     ; If not,
    LD   A,RG_EXIT                 ; JP C,exit;
    JP   Z,EM_JUMP                 ; return.
    LD   C,$D2                     ; JP NC
    CALL EM_FWD                    ; past them:
    PUSH AF                        ; (its label kept)
    CALL HN_FAIL                   ; PUSH AF, the frees, POP AF,
    LD   C,$C3                     ; JP
    LD   A,RG_EXIT                 ; to the
    CALL EM_JUMP                   ; exit.
    POP  AF                        ; The label
    JP   EM_LDONE                  ; is here; return.

; The result's push and pop, each a count and its bytes.

HN_KEEP1: DB  1,$F5,1,$F1      ; PUSH AF; POP AF.
HN_KEEP2: DB  1,$E5,1,$E1      ; PUSH HL; POP HL.
HN_KEEP4: DB  2,$D5,$E5,2,$E1,$D1 ; PUSH DE, PUSH HL; POP HL, POP DE.
