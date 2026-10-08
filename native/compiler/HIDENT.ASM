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
    JP   OW_IDREC                  ; OWNBODY.ASM); return.
.OWNER:                        ; Anything else is not-owner,
    LD   A,DG_OWNER                ; at
    JP   DG_HERE                   ; `id`.

;@ROUTINE IN E CLOBBERS A,BC,DE,HL,IX,IY,CARRY,ZERO,SIGN,PARITY,HALFCARRY
; Parse an identifier's value for a location of type E into DEHL
; (toRegisters): none, LD HL,0, LD DE,0, for an optional one; id(...); an
; identifier's path, loaded; each of the same pool, an optional value only
; for an optional location; anything else type-mismatch, at HN_AT when an
; assignment set it, else at the value; a routine's identifier result, in
; DEHL from its call. A path from an aggregate result waits (DG_NYI).

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
    CP   TK_NEW                    ; A fresh owner
    JR   Z,.CLASH                  ; is no identifier (7.9),
    CP   TK_MOVE                   ; nor is a moved
    JR   Z,.CLASH                  ; one;
    XOR  A                         ; anything else
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
    CALL RO_FIND                   ; result,
    JR   Z,.CALL                   ; an identifier's;
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
    JR   .CHECK                    ; Checked.
.CALL:                         ; HL is the routine:
    CALL HN_VOIDQ                  ; it has a result (no-value),
    CALL RO_CALL                   ; called: A its result,
    CALL PL_ISHND                  ; an identifier's in DEHL;
    JP   NC,TR_OPER                ; any other's path waits;
    BIT  1,A                       ; an owner's
    JR   Z,.CLASH                  ; is none.
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
    JR   NZ,HN_DEZ                 ; a run-time index,
    LD   HL,(RO_POWN)              ; else the place's
    LD   A,H                       ; slot word,
    OR   L                         ; if
    JR   Z,HN_DEZ                  ; it has one:
    LD   DE,GX_DLDDE               ; LD E,(IX+n),
    CALL GX_FACC                   ; LD D,(IX+n+1);
    JR   HN_PSHDE                  ; or none; then PUSH DE.

;@ROUTINE CLOBBERS A,B,DE,HL,CARRY,ZERO,SIGN,PARITY,HALFCARRY
; Append LD DE,0, then PUSH DE, counted as two bytes pushed (HN_PSHDE).

HN_DEZ:                        ; No word:
    CALL EM_SEQ                    ; LD DE,0;
    DB   3,$11,0,0                 ; fall into HN_PSHDE.

;@ROUTINE CLOBBERS A,DE,HL,CARRY,ZERO,SIGN,PARITY,HALFCARRY
; Append PUSH DE, counted as two bytes pushed. BC is kept.

HN_PSHDE:                      ; DE is set:
    LD   A,$D5                     ; PUSH DE,
    JP   GX_PUSHA                  ; two bytes; return.

;@ROUTINE IN A,HL CLOBBERS C,DE,HL,ZERO,SIGN,PARITY,HALFCARRY
; `and` or `or`, A, is next: a move since its chain or its expression
; began (the baseline at HL, EX_ANDB or EX_ORB) is move-position at it,
; in an operand of it (10.8). A is kept.

HN_LOGIC:                      ; A is the operator.
    LD   C,A                       ; (kept)
    LD   A,(HN_MOVES)              ; The moves
    CP   (HL)                      ; since the baseline:
    LD   A,C                       ; none,
    RET  Z                         ; as it should be.
    CP   TK_OR                     ; Otherwise
    LD   A,1                       ; `or` is phrase 1,
    JR   Z,.PHRASE                 ; an operand of or,
    INC  A                         ; and `and` 2.
.PHRASE:                       ; A is the phrase:
    PUSH AF                        ; (kept)
    CALL PR_SPOT                   ; at the operator,
    POP  AF                        ; move-position.

;@ROUTINE IN A,HL NORETURN
; move-position (DG_MPOS) at offset HL, naming phrase A: 1 an operand of
; or, 2 of and, 3 a while condition, 4 an assert condition (HN_NOMV).

HN_MPOS:                       ; A the phrase, HL the offset.
    PUSH HL                        ; The offset kept;
    LD   E,A                       ; phrase E
    LD   HL,HN_PHRS                ; of the list,
.SKIP:                         ; past E-1
    DEC  E                         ; terminators.
    JR   Z,.FOUND                  ; There.
    XOR  A                         ; Past the
    LD   B,A                       ; next
    LD   C,A                       ; zero
    CPIR                           ; byte.
    JR   .SKIP                     ; The next.
.FOUND:                        ; HL is the phrase:
    LD   (DG_ARG1),HL              ; argument 1.
    POP  HL                        ; At the offset,
    LD   A,DG_MPOS                 ; move-position;
    JP   DG_HERE                   ; no return.

;@ROUTINE IN C,DE OUT A,HL,CARRY CLOBBERS SIGN,PARITY,HALFCARRY,ZERO,BC,DE,IX,IY
; Run the parse at DE where no move may be, phrase C (HN_NOMV), as the
; reference's withoutMove; the enclosing phrase is restored after it. A,
; HL and the flags are the parse's.

HN_NOMOV:                      ; C the phrase, DE the parse.
    LD   HL,HN_NOMV                ; The phrase
    LD   B,(HL)                    ; replaces
    LD   (HL),C                    ; the enclosing one,
    PUSH BC                        ; which is kept,
    CALL .RUN                      ; while the parse runs.
    POP  BC                        ; The enclosing
    LD   C,A                       ; (A kept)
    LD   A,B                       ; phrase
    LD   (HN_NOMV),A               ; again.
    LD   A,C                       ; (The flags are the parse's.)
    RET                            ; Done.
.RUN:                          ; DE is the parse.
    PUSH DE                        ; Jumped to;
    RET                            ; it returns above.

HN_PHRS:                       ; HN_NOMV's phrases, by code from one.
    DB   "an operand of or",0      ; 1: or's right operand;
    DB   "an operand of and",0     ; 2: and's;
    DB   "a while condition",0     ; 3: a while's condition;
    DB   "an assert condition",0   ; 4: an assert's.

;@ROUTINE CLOBBERS A,DE,HL,CARRY,ZERO,SIGN,PARITY,HALFCARRY
; An aggregate argument for a value parameter reached through an
; identifier (RO_PPUSH bit 4), its address in HL at run time, is passed
; as a copy (passCopy), unless it owns (owning-copy, at the argument), in
; a frame temporary of its type's size: PUSH HL,
; HL = IX+temp, EX DE,HL, POP HL, PUSH DE, LD BC,size, LDIR, POP HL.
; BC is kept.

HN_COPY:                       ; The address is made.
    LD   A,(RO_PPUSH)              ; Through
    AND  $10                       ; an identifier?
    RET  Z                         ; If not, itself.
    PUSH BC                        ; (kept)
    LD   A,(RO_OTYPE)              ; Not
    CALL PL_OWNS                   ; an owning
    LD   A,DG_OCOPY                ; object
    JP   C,EX_EVAL                 ; (owning-copy);
    LD   A,(RO_OTYPE)              ; its type's
    CALL AG_SIZE                   ; size,
    PUSH HL                        ; kept,
    EX   DE,HL                     ; in the frame
    CALL EM_ALLOW                  ; (allocLocal);
    PUSH HL                        ; the slot kept;
    CALL GX_PUSHW                  ; PUSH HL, counted,
    POP  HL                        ; HL = IX+slot,
    CALL GA_SLOT                   ; then
    CALL EM_SEQ                    ; EX DE,HL, POP HL,
    DB   4,$EB,$E1,$D5,$01         ; PUSH DE, LD BC,
    POP  HL                        ; the size,
    CALL EM_WORD                   ; then
    CALL EM_SEQ                    ; LDIR,
    DB   3,$ED,$B0,$E1             ; POP HL: the copy,
    POP  BC                        ; (BC)
    JP   EM_POP2                   ; popped; return.

;@ROUTINE IN A CLOBBERS A,BC,DE,HL,IX,IY,CARRY,ZERO,SIGN,PARITY,HALFCARRY
; RO_LOAD's handle path, of type A, in an expression: an identifier's four
; bytes loaded into DEHL and compared (HN_EQ); an owner's waits (DG_NYI).

HN_IDLD:                       ; A is the handle's type.
    BIT  1,A                       ; An owner
    JP   Z,TR_OPER                 ; waits;
    PUSH AF                        ; an identifier
    LD   A,SY_U32                  ; has its
    LD   (RO_OTYPE),A              ; four bytes
    CALL GA_LOAD                   ; loaded,
    POP  AF                        ; then
    JR   HN_EQ                     ; compared.

;@ROUTINE CLOBBERS A,BC,DE,HL,IX,IY,CARRY,ZERO,SIGN,PARITY,HALFCARRY
; console or printer in an expression, its predeclared entry at HL: its
; value in DEHL (RO_FCON), compared (HN_EQ).

HN_FCON:                       ; HL is the entry.
    LD   DE,(TK_POS)               ; The value
    LD   (EX_START),DE             ; is here;
    CALL RO_FCON                   ; its value in DEHL,
    LD   A,AG_FILE                 ; a File's,
    JR   HN_EQ                     ; compared.

;@ROUTINE CLOBBERS A,BC,DE,HL,IX,IY,CARRY,ZERO,SIGN,PARITY,HALFCARRY
; RO_LOAD's File path in an expression: loaded into DEHL (GA_LDF) and
; compared (HN_EQ).

HN_FLD:                        ; The path is a File's.
    CALL GA_LDF                    ; Its value in DEHL;
    LD   A,AG_FILE                 ; fall into HN_EQ.

;@ROUTINE IN A OUT A,CARRY CLOBBERS BC,DE,HL,IX,IY,ZERO,SIGN,PARITY,HALFCARRY
; An identifier or File value of type A, in DEHL, compares with `=` or
; `<>` only (9.11, 16.3): PUSH DE, PUSH HL, the right operand of the same
; type (an identifier's widened to optional) in DEHL, EXX, POP HL, POP
; DE, CALL CMP32U, LD A,0, JP NZ,skip, INC A, skip: and XOR 1 for `<>`.
; Without either, an identifier waits (DG_NYI) and a File is no scalar
; (type-mismatch at the value). A returns a computed Boolean.

HN_EQ:                         ; A is the type.
    LD   C,A                       ; Kept.
    PUSH BC                        ; (on the stack)
    CALL PR_PEEK                   ; `=`
    POP  BC                        ; or
    LD   B,A                       ; `<>`
    CP   TK_EQ                     ; next?
    JR   Z,.CMP                    ; Then compared;
    CP   TK_NE                     ; otherwise
    JR   Z,.CMP                    ; an identifier
    LD   A,C                       ; waits, and
    CP   AG_FILE                   ; a File is
    JP   NZ,TR_OPER                ; no scalar
    JP   EX_EFIT                   ; (type-mismatch).
.CMP:                          ; B is the operator, C the type.
    LD   A,(EX_MINB)               ; Only a comparison's
    OR   A                         ; left operand compares
    JP   NZ,TR_OPER                ; (another waits).
    PUSH BC                        ; Both kept.
    CALL PR_TAKE                   ; It is taken.
    LD   A,$D5                     ; PUSH DE,
    CALL GX_PUSHA                  ; PUSH HL,
    CALL GX_PUSHW                  ; four bytes.
    POP  BC                        ; The type:
    PUSH BC                        ; a File's
    LD   A,C                       ; right operand
    CP   AG_FILE                   ; is a File's
    JR   NZ,.ID                    ; value (in
    CALL PR_PEEK                   ; parentheses
    CP   TK_LPAR                   ; it
    JP   Z,TR_OPER                 ; waits),
    CALL RO_FVAL                   ; or
    JR   .GOT                      ; an
.ID:                           ; identifier's
    OR   AG_HOPT                   ; of the type
    LD   E,A                       ; made optional,
    LD   HL,0                      ; reported at
    LD   (HN_AT),HL                ; the value;
    CALL HN_IDV0                   ; in DEHL.
.GOT:                          ; Then EXX,
    CALL EM_SEQ                    ; POP HL,
    DB   3,$D9,$E1,$D1             ; POP DE,
    LD   A,4                       ; four bytes
    CALL EM_POP                    ; popped;
    CALL EM_HELP                   ; CALL
    DW   HP_LCMPU                  ; CMP32U;
    CALL EM_SEQ                    ; LD A,0,
    DB   2,$3E,0                   ; then
    LD   C,$C2                     ; JP NZ
    CALL EM_FWD                    ; past
    PUSH AF                        ; INC A
    CALL EM_OP                     ; (true when
    DB   $3C                       ; equal).
    POP  AF                        ; The label
    CALL EM_LDONE                  ; is here.
    POP  BC                        ; For `<>`,
    LD   A,B                       ; XOR 1
    CP   TK_NE                     ; makes
    JR   NZ,.BOOL                  ; it
    CALL EM_SEQ                    ; true
    DB   2,$EE,1                   ; when not.
.BOOL:                         ; A computed Boolean,
    CALL HN_NOCMP                  ; compared no further,
    LD   A,SY_BOOL                 ; its metadata,
    OR   A                         ; carry clear.
    RET                            ; The value.

;@ROUTINE CLOBBERS A,BC,DE,HL,CARRY,ZERO,SIGN,PARITY,HALFCARRY
; The next token is no comparison operator: one after a comparison of
; identifiers or Files, or after a File local's value, waits (DG_NYI).

HN_NOCMP:                      ; What follows?
    CALL PR_PEEK                   ; `=`
    CP   TK_EQ                     ; waits,
    JP   Z,TR_OPER                 ; as does
    SUB  TK_LT                     ; any of
    CP   TK_NE-TK_LT+1             ; `<` to `<>`;
    JP   C,TR_OPER                 ; anything
    RET                            ; else ends it.

;@ROUTINE IN A OUT HL,ZERO CLOBBERS A,DE,CARRY,SIGN,PARITY,HALFCARRY
; The ordinal of table type A's owner descriptor (PL_DESC) in HL, zero
; (Z) while none is written.

HN_DESC:                       ; A is a table type.
    SUB  AG_FIRST                  ; Its
    ADD  A,A                       ; word
    LD   E,A                       ; in
    LD   D,0                       ; the
    LD   HL,PL_DESC                ; cache:
    ADD  HL,DE                     ; the
    LD   A,(HL)                    ; ordinal,
    INC  HL                        ; HL,
    LD   H,(HL)                    ; or
    LD   L,A                       ; zero
    OR   H                         ; (Z).
    RET                            ; Back.

;@ROUTINE IN A OUT A CLOBBERS CARRY,ZERO,SIGN,PARITY,HALFCARRY
; A local's type A, not a handle: an owning record waits (DG_NYI) unless
; its owner descriptor is written already (a pool's record), which its
; free names (HN_OFREE); an owning array's is made at each free. A, DE
; and HL are kept.

HN_LOCTY:                      ; A is the type.
    PUSH HL                        ; HL,
    PUSH DE                        ; DE
    PUSH AF                        ; and A kept.
    CALL PL_OWNS                   ; Owning?
    JR   NC,.KEEP                  ; No.
    POP  AF                        ; Then
    PUSH AF                        ; an array,
    CALL HN_ARRAY                  ; or a record
    JR   Z,.KEEP                   ; whose descriptor
    POP  AF                        ; is
    PUSH AF                        ; written
    CALL HN_DESC                   ; (a pool's);
    JP   Z,TR_OPER                 ; another waits.
.KEEP:                         ; Accepted.
    POP  AF                        ; A,
    POP  DE                        ; DE
    POP  HL                        ; and HL.
    RET                            ; Back.

;@ROUTINE IN A OUT ZERO CLOBBERS A,CARRY,SIGN,PARITY,HALFCARRY
; Zero if type A is an array type (AG_KARR). Every other register is kept.

HN_ARRAY:                      ; A is the type.
    CP   AG_FIRST                  ; A table
    JR   C,.NOT                    ; type,
    CP   AG_OPEN                   ; below the
    JR   NC,.NOT                   ; open arrays?
    PUSH HL                        ; Keep HL
    PUSH DE                        ; and DE.
    CALL AG_DESC                   ; Its
    LD   A,(HL)                    ; kind
    POP  DE                        ; (DE
    POP  HL                        ; and HL again)
    CP   AG_KARR                   ; an array's?
    RET                            ; Zero if so.
.NOT:                          ; No table type:
    OR   $FF                       ; not zero.
    RET                            ; Done.

;@ROUTINE IN A,DE CLOBBERS A,BC,DE,HL,CARRY,ZERO,SIGN,PARITY,HALFCARRY
; Free the owning local of type A at IX+DE (emitFrees): HL = IX+DE, LD
; DE,descriptor, CALL OBJ_FREE; an array's descriptor a new one, made by
; the OWNERS overlay and written after the routine (OW_LDESC), a record's
; its pool's.

HN_OFREE:                      ; A is the type, DE the offset.
    PUSH AF                        ; (kept)
    EX   DE,HL                     ; HL = IX+offset
    CALL GA_SLOT                   ; (ixAddress),
    CALL EM_OP                     ; then
    DB   $11                       ; LD DE,
    POP  AF                        ; the type's
    PUSH AF                        ; descriptor:
    CALL HN_ARRAY                  ; an array's
    JR   NZ,.RECORD                ; is made
    POP  AF                        ; now, for
    LD   (PL_WTYPE),A              ; its type,
    LD   A,12                      ; by OWNERS
    CALL OV_PCALL                  ; (OW_LDESC);
    JR   .MADE                     ; HL is its ordinal.
.RECORD:                       ; A record's
    POP  AF                        ; is its pool's,
    CALL HN_DESC                   ; HL.
.MADE:                         ; HL is the descriptor:
    LD   DE,0                      ; an
    CALL EM_REF                    ; address;
    CALL EM_HELP                   ; CALL
    DW   HP_OFREE                  ; OBJ_FREE.
    RET                            ; Done.
