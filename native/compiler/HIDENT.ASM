;==========================================================================
;  Handles: identifiers
;==========================================================================
;
;  The identifier values of handles (the reference compiler's
;  idExpression and toRegisters for `id` types): `id(PATH)` of an owning
;  handle location, through ID_MAKE; `none`; an identifier's path, its
;  four bytes loaded into DEHL; and their stores, into a local, a program
;  variable or a field, rechecked through an identifier on the way. Split
;  from HANDLES.ASM.
;
;  Principal entries:
;    HN_IDQ    `id` followed by `(`, taken
;    HN_TAIL   a handle's value ends there
;    HN_IDEX   `id(PATH)`
;    HN_IDV    an identifier's value for a location of a given type
;    HN_IDLET  assign to an identifier path
;    HN_INPTH  an inferred local from a handle path

;@ROUTINE OUT CARRY CLOBBERS A,BC,DE,HL,ZERO,SIGN,PARITY,HALFCARRY
; The next token is a NAME, peeked: `id` is taken, and carry returned when
; `(` follows (id(...), whatever is declared, as the reference's
; nameExpression has it); without `(`, an undeclared `id` is
; undeclared-name at it, a declared one's value waits (DG_NYI). Any other
; name is left, no carry.

HN_IDQ:                        ; A NAME is peeked.
    LD   HL,KW_ID                  ; `id`
    LD   B,2                       ; (two bytes)?
    CALL TK_MATCH                  ; If not,
    RET  NC                        ; another name.
    CALL PR_TAKE                   ; Taken:
    CALL HN_PAREN                  ; `(` next?
    SCF                            ; Then
    RET  Z                         ; id(...).
    CALL SY_FIND                   ; Undeclared,
    JP   NC,SY_UNDEF               ; or declared
    JP   TR_OPER                   ; and waiting.

;@ROUTINE OUT ZERO CLOBBERS A,BC,HL,CARRY,SIGN,PARITY,HALFCARRY
; Z if `(` follows the NAME taken; the NAME, its spelling and place, stay
; current.

HN_PAREN:                      ; The NAME is taken.
    LD   HL,(TK_POS)               ; Its place,
    PUSH HL                        ; kept,
    LD   HL,(TK_PTR)               ; its
    PUSH HL                        ; spelling,
    LD   A,(TK_LEN)                ; kept across
    PUSH AF                        ; the peek:
    CALL PR_PEEK                   ; `(`
    CP   TK_LPAR                   ; next? (Z)
    POP  BC                        ; The NAME
    LD   A,B                       ; is
    LD   (TK_LEN),A                ; current
    POP  HL                        ; again,
    LD   (TK_PTR),HL               ; at
    POP  HL                        ; its
    LD   (TK_POS),HL               ; place.
    RET                            ; Z if `(`.

;@ROUTINE OUT CARRY CLOBBERS A,BC,DE,HL,IX,IY,ZERO,SIGN,PARITY,HALFCARRY
; The next token is a NAME, peeked: a scalar variable's or constant's
; begins an expression, which is parsed whole (carry), as the reference
; parses a value before judging it; any other name is left (no carry).

HN_SCAL:                       ; A NAME is peeked.
    CALL SY_FIND                   ; A symbol? If not,
    RET  NC                        ; left.
    INC  HL                        ; Its
    INC  HL                        ; class
    INC  HL                        ; byte:
    BIT  7,(HL)                    ; an aggregate's
    JR   Z,.SCALAR                 ; is left
    OR   A                         ; (carry
    RET                            ; clear);
.SCALAR:                       ; a scalar's
    XOR  A                         ; (nothing expected)
    CALL EX_RUN                    ; expression
    SCF                            ; is parsed.
    RET                            ; Done.

;@ROUTINE CLOBBERS BC,DE,HL,CARRY,ZERO,SIGN,PARITY,HALFCARRY
; A handle's value ends at the line, a comma, a `)`, `else` or `handle`;
; an operator after it, which would make it an operand, waits (DG_NYI).
; A is kept.

HN_TAIL:                       ; The value is read.
    PUSH AF                        ; Kept.
    CALL PR_PEEK                   ; What follows?
    LD   HL,.ENDS                  ; One of
    LD   BC,5                      ; the ends,
    CPIR                           ; or
    JP   NZ,TR_OPER                ; it waits.
    POP  AF                        ; A.
    RET                            ; Back.
.ENDS:                         ; The tokens a value ends at.
    DB   TK_EOL,TK_COMMA,TK_RPAR,TK_ELSE,TK_HANDL ; Five.

;@ROUTINE OUT A CLOBBERS BC,DE,HL,IX,IY,CARRY,ZERO,SIGN,PARITY,HALFCARRY
; `id(PATH)`, `id` taken (idExpression): the path an owning handle
; location (not-owner at `id`; a record's is OW_IDREC's), usable
; (checkUsable); its handle loaded and CALL ID_MAKE, the identifier in
; DEHL. A returns its type, an identifier of the same pool, optional as
; the handle is.

HN_IDEX:                       ; `id` was the token.
    LD   HL,(TK_POS)               ; Its offset,
    PUSH HL                        ; kept.
    CALL PR_LEFT                   ; `(`,
    LD   E,TK_NAME                 ; the path's
    CALL PR_NEED                   ; root:
    CALL SY_FIND                   ; a scalar
    LD   A,0                       ; variable is
    JR   NC,.PATH                  ; (an undeclared name
    INC  HL                        ; is RO_NAMED's
    INC  HL                        ; to report)
    INC  HL                        ; no
    BIT  7,(HL)                    ; owner;
    JR   Z,.SCALAR                 ; else
.PATH:                         ; the path,
    CALL RO_NAMED                  ; A its type.
.SCALAR:                       ; A is the type,
    PUSH AF                        ; (kept)
    CALL PR_RIGHT                  ; `)`.
    POP  AF                        ; The type:
    POP  HL                        ; (at `id`)
    CALL PL_ISHND                  ; an owning
    JR   NC,.NOT                   ; handle?
    BIT  1,A                       ; Not
    JR   NZ,.NOT                   ; an identifier.
    PUSH AF                        ; Kept.
    LD   HL,(EX_START)             ; Usable,
    LD   (FW_PLACE),HL             ; at its name;
    CALL FW_USE                    ; then
    LD   A,SY_U16                  ; loaded,
    LD   (RO_OTYPE),A              ; a word,
    CALL GA_LOAD                   ; into HL,
    CALL EM_HELP                   ; CALL
    DW   HP_IDMK                   ; ID_MAKE.
    POP  AF                        ; The type
    OR   AG_HID                    ; an identifier's.
    RET                            ; DEHL holds it.
.NOT:                          ; Not an owner:
    CP   AG_FIRST                  ; a record's
    JR   C,.OWNER                  ; identifier
    CP   AG_OPEN                   ; (OW_IDREC,
    JR   NC,.OWNER                 ; `id` staged
    LD   (AC_BOUND),HL             ; in AC_BOUND,
    LD   A,27                      ; entry 27);
    JP   OV_PCALL                  ; return.
.OWNER:                        ; Anything else is not-owner,
    LD   A,DG_OWNER                ; at
    JP   DG_HERE                   ; `id`.

;@ROUTINE IN E CLOBBERS A,BC,DE,HL,IX,IY,CARRY,ZERO,SIGN,PARITY,HALFCARRY
; Parse an identifier's value for a location of type E into DEHL
; (toRegisters): none, LD HL,0, LD DE,0, for an optional one; id(...); an
; identifier's path, loaded; each of the same pool, an optional value only
; for an optional location; anything else type-mismatch, at HN_AT when an
; assignment set it, else at the value. A routine's identifier waits.

HN_IDV:                        ; E is the location's type.
    CALL HN_IDV0                   ; The value,
    JR   HN_TAIL                   ; ending there; return.

HN_IDV0:                       ; E is the location's type.
    PUSH DE                        ; Kept.
    CALL HN_PLACE                  ; The value's kind, C, and place, HL.
    POP  DE                        ; (the type)
    PUSH HL                        ; The place,
    PUSH DE                        ; the type, kept.
    LD   A,C                       ; The kind:
    CP   TK_NONE                   ; none?
    JR   Z,.NONE                   ; LD HL,0, LD DE,0.
    CP   TK_NAME                   ; A name?
    JR   Z,.NAME                   ; Its value.
    XOR  A                         ; Anything else
    CALL EX_RUN                    ; is an expression,
    JR   .CLASH                    ; no identifier.
.NONE:                         ; none:
    POP  DE                        ; (the type)
    PUSH DE                        ; an
    BIT  0,E                       ; optional
    JR   Z,.CLASH                  ; location only.
    CALL PR_TAKE                   ; Taken:
    CALL EM_SEQ                    ; LD HL,0,
    DB   6,$21,0,0,$11,0,0         ; LD DE,0.
    JR   .FIT                      ; Done.
.NAME:                         ; A name:
    CALL HN_IDQ                    ; id(...)?
    JR   NC,.SCALAR                ; If not, a path.
    CALL HN_IDEX                   ; The identifier, A its type.
    JR   .CHECK                    ; Checked.
.SCALAR:                       ; A scalar's
    CALL HN_SCAL                   ; expression
    JR   C,.CLASH                  ; is none;
    CALL PR_TAKE                   ; the name taken:
.PATH:                         ; a routine's
    CALL RO_FIND                   ; identifier
    JP   Z,TR_OPER                 ; waits;
    CALL SY_FIND                   ; anything else
    JP   NC,SY_UNDEF               ; undeclared is no name;
    CALL RO_NAMED                  ; a path, A its type:
    CALL PL_ISHND                  ; an
    JR   NC,.CLASH                 ; identifier's,
    BIT  1,A                       ; or no
    JR   Z,.CLASH                  ; identifier.
    PUSH AF                        ; (kept)
    LD   A,SY_U32                  ; Its four
    LD   (RO_OTYPE),A              ; bytes
    CALL GA_LOAD                   ; loaded.
    POP  AF                        ; The type.
.CHECK:                        ; A is the value's type.
    POP  DE                        ; The location's,
    PUSH DE                        ; E:
    XOR  E                         ; the same pool
    CP   2                         ; and kind?
    JR   NC,.CLASH                 ; No.
    RRA                            ; The same optionality,
    JR   NC,.FIT                   ; or an optional value
    BIT  0,E                       ; for an optional
    JR   NZ,.FIT                   ; location only.
.CLASH:                        ; Not the location's:
    POP  DE                        ; (the type)
    POP  HL                        ; type-mismatch
    LD   A,DG_CLASH                ; at the
    JP   DG_HERE                   ; value.
.FIT:                          ; It fits.
    POP  DE                        ; (dropped)
    POP  HL                        ; (dropped)
    RET                            ; DEHL holds it.

;@ROUTINE IN A CLOBBERS A,BC,DE,HL,IX,IY,CARRY,ZERO,SIGN,PARITY,HALFCARRY
; Assign to the identifier path in hand, of type A (assign): at a computed
; place its address, in HL, is pushed, the value read (HN_IDV), the
; identifier rechecked, then POP BC and its four bytes stored through BC;
; elsewhere the value, then stored (store4).

HN_IDLET:                      ; A is the identifier's type.
    LD   A,(RO_PKIND)              ; A computed
    CP   GA_HELD                   ; place?
    JR   NZ,.PLACED                ; No.
    CALL GX_PUSHW                  ; PUSH HL: its address.
    CALL .VALUE                    ; The value,
    CALL HN_RECK                   ; its identifier rechecked,
    CALL EM_SEQ                    ; POP BC, then LD A,L, LD (BC),A, INC BC,
    DB   12,$C1,$7D,$02,$03,$7C,$02,$03,$7B,$02,$03,$7A,$02 ; H, E and D.
    JP   EM_POP2                   ; Two bytes popped; return.
.PLACED:                       ; Static, in the frame or an alias:
    LD   HL,0                      ; a mismatch is reported
    LD   (HN_AT),HL                ; at the value;
    CALL .VALUE                    ; the value,
    LD   A,SY_U32                  ; four
    LD   (RO_OTYPE),A              ; bytes,
    JP   GA_STORE                  ; stored; return.
.VALUE:                        ; The value, the place kept across it.
    CALL RO_KEEP                   ; The place kept.
    LD   A,(RO_OTYPE)              ; The identifier's
    LD   E,A                       ; type:
    CALL HN_IDV                    ; a value for it, in DEHL.
    CALL RO_BACK                   ; The place back
    RET                            ; (RO_BACK must be called).

;@ROUTINE IN A CLOBBERS A,BC,DE,HL,IX,IY,CARRY,ZERO,SIGN,PARITY,HALFCARRY
; An inferred local's initializer is a path to a handle of type A
; (AC_INFER): an owner's is moved, not copied (needs-move, at the path);
; an identifier's is loaded, DEHL, the local of its type.

HN_INPTH:                      ; A is the handle's type.
    BIT  1,A                       ; An owner's
    LD   HL,(EX_START)             ; needs
    LD   E,A                       ; (the type kept)
    LD   A,DG_NMOVE                ; move,
    JP   Z,DG_HERE                 ; at the path.
    LD   A,E                       ; The identifier's
    LD   (AG_CTYPE),A              ; type is the local's;
    LD   A,SY_U32                  ; its four
    LD   (RO_OTYPE),A              ; bytes
    CALL GA_LOAD                   ; loaded,
    CALL HN_TAIL                   ; ending there.
    CALL AC_LOCAL                  ; The local,
    LD   A,AC_LHND                 ; bound
    LD   (EX_RMETA),A              ; to it.
    RET                            ; Back to the engine.

;@ROUTINE IN A CLOBBERS A,BC,DE,HL,IX,IY,CARRY,ZERO,SIGN,PARITY,HALFCARRY
; An argument for slot-holder parameter A, var (argument): a path to an
; owning location of the parameter's own type, optional (type-mismatch),
; writable (not-writable) and not reached through an identifier
; (slot-holder), each at the argument; used directly (noteDirect); its
; address in HL and its owner word, the place's slot word or zero, LD DE
; and PUSH DE; the caller pushes HL.

HN_SLARG:                      ; A is the parameter's type.
    AND  $7F                       ; Without var,
    LD   C,A                       ; kept.
    PUSH BC                        ; (on the stack)
    CALL PR_SPOT                   ; The argument's
    POP  BC                        ; start,
    PUSH HL                        ; kept.
    PUSH BC                        ; (the type)
    LD   E,TK_NAME                 ; A path:
    CALL PR_NEED                   ; its root, a symbol;
    CALL SY_FIND                   ; a
    JR   C,.PATH                   ; routine's
    CALL RO_FIND                   ; name
    LD   A,DG_CLASS                ; is
    JP   Z,DG_NAMED                ; wrong-class.
.PATH:                         ; Then
    CALL RO_NAMED                  ; the rest, A its type.
    POP  BC                        ; The parameter's:
    POP  HL                        ; (at the argument)
    CP   C                         ; the same
    LD   A,DG_CLASH                ; (type-mismatch
    JP   NZ,DG_HERE                ; otherwise),
    LD   A,(RO_PRO)                ; writable
    OR   A                         ; (not-writable
    LD   A,DG_CONST                ; otherwise),
    JP   NZ,DG_HERE                ; and
    LD   A,(RO_PPUSH)              ; not through an identifier,
    AND  $18                       ; unless a run-time index
    CP   $10                       ; followed it
    LD   A,DG_HOLDR                ; (slot-holder
    JP   Z,DG_HERE                 ; otherwise).
    LD   HL,(EX_START)             ; Used
    LD   (FW_PLACE),HL             ; directly
    CALL FW_SEEN                   ; (noteDirect).
    CALL GA_ADDR                   ; Its address, HL;
    LD   A,(RO_PPUSH)              ; its owner word:
    AND  8                         ; none after
    JR   NZ,.ZERO                  ; a run-time index,
    LD   HL,(RO_POWN)              ; else the place's
    LD   A,H                       ; slot word,
    OR   L                         ; if
    JR   Z,.ZERO                   ; it has one:
    LD   DE,GX_DLDDE               ; LD E,(IX+n),
    CALL GX_FACC                   ; LD D,(IX+n+1);
    JR   .PUSH                     ; or
.ZERO:                         ; none:
    CALL EM_SEQ                    ; LD DE,0.
    DB   3,$11,0,0                 ; Then
.PUSH:                         ; PUSH DE,
    LD   A,$D5                     ; two bytes
    JP   GX_PUSHA                  ; pushed; return.

;@ROUTINE CLOBBERS HL,ZERO,SIGN,PARITY,HALFCARRY
; `and` or `or` is next: a statement with a move inside an expression
; waits (DG_NYI), for the reference's move-position rules (10.8) are not
; yet followed; marked (HN_MVLG bit 1). A and the carry are kept.

HN_LOGIC:                      ; The operator is next.
    LD   HL,HN_MVLG                ; A move
    BIT  0,(HL)                    ; in its statement
    JP   NZ,TR_OPER                ; waits;
    SET  1,(HL)                    ; else marked.
    RET                            ; Back.
