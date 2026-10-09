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
;  table: each control frame keeps its first record (CT_FSYMS), the
;  body's start is SY_BODY, and the routine's parameters start at
;  SY_GTOP. So a scope is a run of records, and the scopes from
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
    CALL WD_GET                    ; its ordinal, DE, and its
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
; parsed as an expression, then type-mismatch. The value may be in
; parentheses (HN_OPEN, HN_CLOSE).

HN_OWNV:                       ; E is the handle's type.
    CALL HN_OPEN                   ; Its parentheses, B,
    PUSH BC                        ; (counted)
    CALL HN_OWN0                   ; the value,
    JP   HN_CLOSE                  ; and theirs, ending there; return.

HN_OWN0:                       ; E is the handle's type.
    PUSH DE                        ; Kept.
    CALL HN_PLACE                  ; The value's kind, C, and place, HL.
    POP  DE                        ; (the type)
    PUSH HL                        ; The place, kept.
    LD   A,C                       ; The kind:
    CP   TK_NONE                   ; none?
    JP   Z,.NONE                   ; LD HL,0.
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
    JR   NZ,.IDENT                 ; (needs-move),
    CALL HN_TAIL                   ; unless an operand;
    POP  DE                        ; (the type)
    POP  HL                        ; at the
    LD   A,DG_NMOVE                ; value.
    JP   DG_HERE                   ; No return.
.IDEX:                         ; id(...):
    CALL HN_IDEX                   ; an identifier,
    JR   .OTHER                    ; no owner.
.IDENT:                        ; An identifier's path: an operand
    CALL HN_TAIL                   ; waits (the reference's operator
    JR   .OTHER                    ; reports it); else no owner.
.ROUTINE:                      ; HL is the routine.
    CALL HN_VOIDQ                  ; It has a result (no-value),
    CALL RO_CALL                   ; called: A its result,
    CALL PL_ISHND                  ; an owning
    JR   C,.HND                    ; handle;
    CP   AG_FIRST                  ; an aggregate's
    JP   NC,TR_OPER                ; path waits;
    JR   .OTHER                    ; a scalar is none.
.HND:                          ; A handle,
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
; (HN_OWNV) or an identifier's (HN_IDV), committed by HN_BIND (AC_LHND in
; EX_RMETA).

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
    CALL PR_PEEK                   ; `(`
    CP   TK_LPAR                   ; before new, move
    JR   NZ,HN_INF0                ; or id(...)
    CALL HN_PHND                   ; (the source after it
    JR   NC,HN_INF0                ; says) holds a handle:
    CALL HN_OPEN                   ; its parentheses, B,
    LD   HL,0                      ; (no target: nothing is reported
    LD   (HN_AT),HL                ; at the first `(`)
    PUSH BC                        ; (counted)
    CALL HN_INF0                   ; the value, the local's type,
    POP  BC                        ; then as many
    PUSH AF                        ; (its flags)
    CALL HN_SHUT                   ; closed (DG_NYI else),
    CALL HN_TAIL                   ; the value ending there;
    POP  AF                        ; carry: a handle local.
    RET                            ; Back to AC_INFER.

HN_INF0:                       ; The initializer's first token:
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
    BIT  1,A                       ; waits): an
    JR   Z,.OWNER                  ; identifier's
    CALL HN_IDV0                   ; in DEHL,
    JR   .VALUED                   ; or
.OWNER:                        ; an owner's
    CALL HN_OWNV                   ; in HL:
.VALUED:                       ; read,
    POP  AF                        ; the value's type.
    JR   .TYPED                    ; The local's.
.NOT:                          ; Anything else
    OR   $FF                       ; is not a handle
    RET                            ; (NZ, carry clear).
.MOVE:                         ; move:
    CALL HN_MOVE                   ; the handle moved,
    JR   .TYPED                    ; A its type.
.ID:                           ; id(...), `id` taken:
    CALL HN_IDEX                   ; the identifier made,
    JR   .TYPED                    ; A its type.
.NEW:                          ; new:
    CALL HN_NEW                    ; the handle, A its type,
.TYPED:                        ; the local's, unless
    BIT  1,A                       ; an identifier's
    JR   Z,.LOCAL                  ; is compared,
    CALL HN_ICMP                   ; a Boolean
    RET  Z                         ; (Z, carry clear);
.LOCAL:                        ; the value
    CALL HN_TAIL                   ; ending there,
    LD   (AG_CTYPE),A              ; a value.
    LD   A,FW_VALUE                ; Its
    LD   (HN_VKIND),A              ; state.
    SCF                            ; A handle.
    RET                            ; Done.

;@ROUTINE IN A OUT A,CARRY,ZERO CLOBBERS BC,DE,HL,IX,IY,SIGN,PARITY,HALFCARRY
; An identifier's or a File's value of type A, in DEHL, beginning an
; inferred local's initializer: followed by `=` or `<>`, it is compared
; (HN_EQ), and Z returns A a Boolean's metadata, the expression's first
; primary (AC_PRIME); otherwise NZ returns A the type. Carry is clear.

HN_ICMP:                       ; A is the type.
    PUSH AF                        ; Kept.
    CALL PR_PEEK                   ; `=`
    CP   TK_EQ                     ; or
    JR   Z,.CMP                    ; `<>`
    CP   TK_NE                     ; next?
    JR   Z,.CMP                    ; If not,
    POP  AF                        ; the type,
    OR   A                         ; NZ.
    RET                            ; Back.
.CMP:                          ; A comparison:
    POP  AF                        ; of the type,
    CALL HN_EQ                     ; a Boolean,
    CP   A                         ; Z.
    RET                            ; Back.

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
    LD   HL,(SY_TOP)               ; the provisional
    LD   DE,4                      ; symbol's, after its spelling
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
    LD   HL,(SY_TOP)               ; The provisional symbol's
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
; not-writable for a var parameter, at the path; any other is copied
; once its address is made (HN_COPY). Through
; an owner (bit 5) it passes no owner word. A and BC are kept.

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
    BIT  7,B                       ; a var parameter's
    LD   A,DG_CONST                ; is
    JP   NZ,EX_EVAL                ; not-writable;
    POP  AF                        ; a value's is
    RET                            ; a copy (HN_COPY).

;@ROUTINE OUT CARRY CLOBBERS A,BC,DE,HL,ZERO,SIGN,PARITY,HALFCARRY
; Carry if the path in hand's root, the routine's own owning local, is the
; subject of an enclosing select's some arm that leases it, as the
; reference's counting subject is.

HN_LEASD:                      ; The root is RO_PROOT.
    LD   BC,(RO_PROOT)             ; Its symbol's record, BC,
    LD   A,(CT_DEPTH)              ; from the innermost frame; fall into HN_SCAN.

;@ROUTINE IN A,BC OUT A,HL,CARRY CLOBBERS DE,ZERO,SIGN,PARITY,HALFCARRY
; Find the next frame below frame A, inward to outward, whose some arm
; leases the symbol whose record is BC (mode bits 7, 6 and 3, its
; subject's record in CT_FSUBJ): carry, A its index and HL its mode's
; address; no carry if none. BC is kept.

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
    LD   DE,CT_FSUBJ-CT_FMODE      ; Its subject's
    ADD  HL,DE                     ; record:
    LD   A,(HL)                    ; this
    CP   C                         ; symbol's?
    JR   NZ,.DIFF                  ; (low byte
    INC  HL                        ; then
    LD   A,(HL)                    ; high,
    CP   B                         ; the flags
    DEC  HL                        ; kept)
.DIFF:                         ; Zero if it is.
    LD   DE,CT_FMODE-CT_FSUBJ      ; (back to
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
    CALL GX_FLDDE                  ; HL kept;
    CALL EM_HELP                   ; CALL
    DW   HP_IDCHK                  ; ID_CHK;
    CALL EM_SEQ                    ; POP DE, POP HL,
    DB   3,$D1,$E1,$F1             ; POP AF,
    LD   A,6                       ; six bytes
    JP   EM_POP                    ; popped; return.

;@ROUTINE IN A NORETURN
; No primary begins with token kind A, consumed: new, none and move
; begin handle values, which wait in an expression (DG_NYI), but a move
; where none may be is move-position at it (HN_NOMV), as the reference's
; primary has it; anything else is syntax, a value expected (PR_ETERM).

HN_ETERM:                      ; A is the token's kind.
    CP   TK_NEW                    ; new
    JP   Z,TR_OPER                 ; and
    CP   TK_NONE                   ; none
    JP   Z,TR_OPER                 ; wait;
    CP   TK_MOVE                   ; anything
    JP   NZ,PR_ETERM               ; else is syntax.
    LD   A,(HN_NOMV)               ; A move
    OR   A                         ; may be here:
    JP   Z,TR_OPER                 ; it waits;
    LD   HL,(TK_POS)               ; otherwise, at it,
    JP   HN_MPOS                   ; move-position.

;@ROUTINE CLOBBERS A,B,DE,HL,CARRY,ZERO,SIGN,PARITY,HALFCARRY
; The current NAME is a primary: `id(...)` is an identifier made and
; compared (HN_IDEX, HN_EQ), the primary's value, returned to EX_NAME's
; caller. Any other NAME is kept.

HN_ISID:                       ; The NAME is current.
    CALL TK_ISID                   ; `id` (two bytes)? If not,
    RET  NC                        ; an ordinary name;
    CALL HN_PAREN                  ; with `(`
    RET  NZ                        ; it is id(...),
    CALL EX_KNOT                   ; not constant;
    POP  HL                        ; EX_NAME's value:
    CALL HN_IDEX                   ; made, A its type,
    JP   HN_EQ                     ; compared; return.

;@ROUTINE IN A OUT A CLOBBERS HL,CARRY,ZERO,SIGN,PARITY,HALFCARRY
; A parameter's type (CommitParameter): a handle, not var, is a value in
; the frame, an identifier's four bytes; a var one an optional owner (a
; slot-holder, var-parameter otherwise). An aggregate is accepted. A is
; kept; HL is not.

HN_PTYPE:                      ; A is the type.
    CALL PL_ISHND                  ; A handle?
    RET  NC                        ; An aggregate is accepted.
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
.VALUE:                        ; A value, an owner's
    RET                            ; or an identifier's.

;@ROUTINE CLOBBERS A,BC,DE,HL,CARRY,ZERO,SIGN,PARITY,HALFCARRY
; The routine's end, after its body's frees: when control reaches it,
; its parameters' owners are freed (emitReturn's frees of the routine's
; scope, without a result).

HN_PEND:                       ; The body has ended.
    LD   A,(CT_FALLS)              ; Unreachable:
    OR   A                         ; nothing
    RET  Z                         ; to free.
    LD   DE,(SY_BODY)              ; The parameters, before
    LD   HL,(SY_GTOP)              ; the body, from the first.
    JP   HN_SEG                    ; Freed; return.

;@ROUTINE IN A CLOBBERS A,BC,DE,HL,IX,IY,CARRY,ZERO,SIGN,PARITY,HALFCARRY
; An argument for a handle parameter of type A (argument): for an owner
; an owning value (HN_OWNV), then CALL LINK0; for an identifier its value
; in DEHL and PUSH DE; for a slot-holder a location (HN_SLARG). The caller
; pushes HL.

HN_ARG:                        ; A is the parameter's type.
    OR   A                         ; A slot-holder
    JP   M,HN_SLARG                ; takes a location.
    LD   E,A                       ; Kept.
    BIT  1,A                       ; An identifier's
    JR   NZ,.ID                    ; value, or
    CALL HN_OWNV                   ; The value, in HL,
    CALL EM_HELP                   ; CALL
    DW   HP_LINK0                  ; LINK0.
    RET                            ; Pushed by the caller.
.ID:                           ; an identifier's (toRegisters),
    LD   HL,0                      ; reported at
    LD   (HN_AT),HL                ; the value,
    CALL HN_IDV                    ; in DEHL: PUSH DE, counted;
    JP   HN_PSHDE                  ; the caller pushes HL.

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
    LD   A,D                       ; A File's
    CP   AG_FILE                   ; value,
    JR   Z,.FILE                   ; in DEHL;
    LD   E,D                       ; an identifier's
    BIT  1,D                       ; value,
    JR   Z,.OWNER                  ; in DEHL,
    CALL HN_IDV                    ; as an argument's is;
    JR   .READ                     ; or an owning
.OWNER:                        ; value, in HL,
    CALL HN_OWNV                   ; then
    CALL EM_HELP                   ; CALL
    DW   HP_LINK0                  ; LINK0;
.READ:                         ; The value is read:
    LD   A,1                       ; the return
    LD   (HN_RETF),A               ; has its value.
    RET                            ; Back to the engine.
.FILE:                         ; A File's,
    CALL RO_FVAL                   ; in DEHL, alone
    CALL PR_PEEK                   ; (anything
    CP   TK_EOL                    ; after it
    JP   NZ,TR_OPER                ; waits),
    JR   .READ                     ; is read.

;@ROUTINE IN HL OUT HL CLOBBERS A,DE,CARRY,ZERO,SIGN,PARITY,HALFCARRY
; Routine HL, its name current, is called for a value: one without a
; result, main among them, has none (no-value, naming it, at it). HL is
; kept.

HN_VOIDQ:                      ; HL is the routine.
    PUSH HL                        ; (kept)
    LD   DE,RO_RTYPE               ; Its
    ADD  HL,DE                     ; result
    LD   A,(HL)                    ; type:
    POP  HL                        ; (the routine)
    OR   A                         ; none? Then
    JP   Z,RO_EVOID                ; no-value.
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

;@ROUTINE IN HL OUT A,HL CLOBBERS CARRY,ZERO,SIGN,PARITY,HALFCARRY
; HL past the source's whitespace from HL, A the byte there: spaces, tabs
; and `//` comments, and within brackets (TK_NEST) line ends, as the
; tokenizer passes them. Nothing is consumed (HN_IDQ, HN_PHND).

HN_BLANK:                      ; HL is in the source.
    LD   A,(HL)                    ; A space
    CP   ' '                       ; or
    JR   Z,.ON                     ; a tab
    CP   9                         ; is
    JR   Z,.ON                     ; passed;
    CP   '/'                       ; so is
    JR   NZ,.EOL                   ; a comment,
    INC  HL                        ; `//`,
    CP   (HL)                      ; (one `/`
    DEC  HL                        ; is a token)
    RET  NZ                        ; to its
.NOTE:                         ; line's
    INC  HL                        ; end,
    LD   A,(HL)                    ; a line
    CP   10                        ; feed
    JR   Z,.LINE                   ; or a
    CP   13                        ; carriage
    JR   NZ,.NOTE                  ; return.
.EOL:                          ; A line end
    CP   10                        ; within brackets
    JR   Z,.LINE                   ; is passed
    CP   13                        ; too; anything
    RET  NZ                        ; else is the token.
.LINE:                         ; A line end:
    LD   A,(TK_NEST)               ; outside brackets
    OR   A                         ; it ends
    LD   A,(HL)                    ; the statement
    RET  Z                         ; (A is it).
.ON:                           ; Passed:
    INC  HL                        ; the next
    JR   HN_BLANK                  ; byte.

;@ROUTINE OUT CARRY CLOBBERS A,BC,DE,HL,ZERO,SIGN,PARITY,HALFCARRY
; With `(` peeked, carry when the source after it, past spaces, tabs and
; more `(`, begins `new`, `move` or `id` and no longer name: an inferred
; local's handle in parentheses (HN_INFER). Nothing is consumed.

HN_PHND:                       ; `(` is the next token.
    LD   HL,(SRC_PTR)              ; The bytes after it,
    DEC  HL                        ; from the `(`:
.SKIP:                         ; past it and more `(`
    INC  HL                        ; and whitespace
    CALL HN_BLANK                  ; (HN_BLANK),
    CP   '('                       ; HL is
    JR   Z,.SKIP                   ; the word.
    LD   DE,.WORDS                 ; Each candidate:
.WORD:                         ; DE is one, its length first.
    LD   A,(DE)                    ; Its length,
    OR   A                         ; or zero
    RET  Z                         ; at the end: none (carry clear).
    LD   B,A                       ; B bytes
    PUSH HL                        ; (the word kept)
.BYTE:                         ; compared:
    INC  DE                        ; the next
    LD   A,(DE)                    ; candidate byte
    CP   (HL)                      ; and source
    INC  HL                        ; byte.
    JR   NZ,.MISS                  ; Unequal.
    DJNZ .BYTE                     ; All equal:
    LD   A,(HL)                    ; then the name
    CALL TK_ALNUM                  ; must end, else no other
    POP  HL                        ; candidate begins it either:
    CCF                            ; carry if it ends,
    RET                            ; a handle's word.
.MISS:                         ; Not this one:
    POP  HL                        ; the word again;
.PASS:                         ; DE past this
    INC  DE                        ; byte and the rest,
    DJNZ .PASS                     ; at the next candidate.
    JR   .WORD                     ; Try it.
.WORDS:                        ; Length, then the spelling.
    DB   3,"new",4,"move",2,"id",0 ; The candidates.

;@ROUTINE OUT B CLOBBERS A,C,HL,CARRY,ZERO,SIGN,PARITY,HALFCARRY
; A handle's value may be in parentheses, as the reference's primary
; allows: take each `(` before it, B of them, and unless an assignment
; gave its target (HN_AT), make the first where a mismatch is reported,
; as the value's start. DE is kept.

HN_OPEN:                       ; A value is next.
    PUSH DE                        ; (kept)
    CALL PR_SPOT                   ; Its kind and start:
    LD   B,0                       ; no parentheses
    CP   TK_LPAR                   ; unless
    JR   NZ,.DONE                  ; one is first;
    LD   DE,(HN_AT)                ; then the
    LD   A,D                       ; target,
    OR   E                         ; if any,
    JR   NZ,.TAKE                  ; else the
    LD   (HN_AT),HL                ; first `(`.
.TAKE:                         ; Another `(`:
    INC  B                         ; counted,
    PUSH BC                        ; (kept)
    CALL PR_TAKE                   ; taken;
    CALL PR_PEEK                   ; another
    POP  BC                        ; follows?
    CP   TK_LPAR                   ; Then
    JR   Z,.TAKE                   ; take it too.
.DONE:                         ; B parentheses.
    POP  DE                        ; DE again.
    RET                            ; Done.

;@ROUTINE CLOBBERS BC,DE,HL,CARRY,ZERO,SIGN,PARITY,HALFCARRY
; HN_OWNV's and HN_IDV's end, entered by JP with the count of HN_OPEN's
; parentheses on the stack: each is closed at once (anything else waits,
; DG_NYI), then the value ends (HN_TAIL), which returns to their caller.

HN_CLOSE:                      ; The count is on the stack.
    POP  BC                        ; B parentheses
    CALL HN_SHUT                   ; are closed;
    JP   HN_TAIL                   ; the value ends there.

;@ROUTINE IN B CLOBBERS A,BC,DE,HL,CARRY,ZERO,SIGN,PARITY,HALFCARRY
; Close B parentheses, each a `)` at once (anything else waits, DG_NYI).

HN_SHUT:                       ; B are open.
    INC  B                         ; (B may be zero)
.NEXT:                         ; B, less one, remain:
    DEC  B                         ; none
    RET  Z                         ; left.
    PUSH BC                        ; (counted)
    CALL PR_PEEK                   ; A `)`
    CP   TK_RPAR                   ; next,
    JP   NZ,TR_OPER                ; else it waits;
    CALL PR_TAKE                   ; taken.
    POP  BC                        ; The count.
    JR   .NEXT                     ; The next.

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
