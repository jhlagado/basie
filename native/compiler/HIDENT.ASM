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
;    HN_ISIDW  carry if the current NAME is `id` and no symbol
;    HN_IDEX   `id(PATH)`
;    HN_IDV    an identifier's value for a location of a given type
;    HN_IDLET  assign to an identifier path
;    HN_INPTH  an inferred local from a handle path

;@ROUTINE OUT CARRY CLOBBERS A,B,DE,HL,ZERO,SIGN,PARITY,HALFCARRY
; Carry if the current NAME is `id`, which no symbol is named: id(...).

HN_ISIDW:                      ; The NAME is current.
    LD   HL,KW_ID                  ; `id`
    LD   B,2                       ; (two bytes)?
    CALL TK_MATCH                  ; If not,
    RET  NC                        ; an ordinary name.
    CALL SY_FIND                   ; No symbol
    CCF                            ; of the name:
    RET                            ; carry.

;@ROUTINE OUT CARRY CLOBBERS A,BC,DE,HL,ZERO,SIGN,PARITY,HALFCARRY
; HN_ISIDW for a NAME taken already, which `(` must follow; the NAME is
; kept.

HN_ISIDP:                      ; The NAME is taken.
    CALL HN_ISIDW                  ; `id`, no symbol?
    RET  NC                        ; No.
    LD   HL,(TK_POS)               ; The NAME's
    PUSH HL                        ; place,
    LD   HL,(TK_PTR)               ; its
    PUSH HL                        ; spelling,
    LD   A,(TK_LEN)                ; kept across
    PUSH AF                        ; the peek:
    CALL PR_PEEK                   ; `(`
    SUB  TK_LPAR                   ; next?
    POP  BC                        ; The NAME
    LD   C,A                       ; (the test kept)
    LD   A,B                       ; is
    LD   (TK_LEN),A                ; current
    POP  HL                        ; again,
    LD   (TK_PTR),HL               ; at
    POP  HL                        ; its
    LD   (TK_POS),HL               ; place. Then
    LD   A,C                       ; carry
    CP   1                         ; if `(`.
    RET                            ; Done.

;@ROUTINE OUT A CLOBBERS BC,DE,HL,IX,IY,CARRY,ZERO,SIGN,PARITY,HALFCARRY
; `id(PATH)`, `id` taken (idExpression): the path an owning handle
; location (not-owner at `id`; a record's identifier waits, DG_NYI), usable
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
    CP   AG_OPEN                   ; waits;
    JP   C,TR_OPER                 ; anything else
.OWNER:                        ; is not-owner,
    LD   A,DG_OWNER                ; at
    JP   DG_HERE                   ; `id`.

;@ROUTINE IN E CLOBBERS A,BC,DE,HL,IX,IY,CARRY,ZERO,SIGN,PARITY,HALFCARRY
; Parse an identifier's value for a location of type E into DEHL
; (toRegisters): none, LD HL,0, LD DE,0, for an optional one; id(...); an
; identifier's path, loaded; each of the same pool, an optional value only
; for an optional location; anything else type-mismatch, at HN_AT when an
; assignment set it, else at the value. A routine's identifier waits.

HN_IDV:                        ; E is the location's type.
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
    CALL PR_TAKE                   ; taken.
    CALL HN_ISIDP                  ; id(...)?
    JR   NC,.PATH                  ; If not, a path.
    CALL HN_IDEX                   ; The identifier, A its type.
    JR   .CHECK                    ; Checked.
.PATH:                         ; A routine's
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
    CALL GA_LOAD                   ; loaded.
    CALL AC_LOCAL                  ; The local,
    LD   A,AC_LHND                 ; bound
    LD   (EX_RMETA),A              ; to it.
    RET                            ; Back to the engine.
