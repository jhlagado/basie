;==========================================================================
;  Handles: select and move
;==========================================================================
;
;  `select` on a handle (the reference compiler's selectHandle) and the
;  move of an owning handle (moveExpression, emitMove), split from
;  HANDLES.ASM. A handle select keeps its subject in a frame slot of its
;  own and tests it in each arm; `some(x)` binds a lease for the routine's
;  own owning local, an owner for `select move`, an identifier otherwise.
;
;  Principal entries:
;    HN_SEL    a select's handle subject: its slot, the frame opened
;    HN_ARM    an arm's some or none, read before the engine predicts it
;    HN_TAKEN  a some arm's binding
;    HN_ELSE   case else
;    HN_ENDA   an arm ends: a lease of its subject ends
;    HN_MOVE   `move PATH` (HN_EMOV generates the move)


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
    CALL HN_REC                    ; The pool's record:
    LD   A,DG_PINC                 ; pool-incomplete
    JR   Z,.FAULT                  ; without one.
    LD   A,(AC_MODE)               ; `select move`
    OR   A                         ; has its own
    JR   Z,.MOVE                   ; checks.
    LD   A,(AC_BOUND)              ; An owning
    AND  3                         ; handle that is
    LD   A,DG_CLASH                ; not optional
    JR   NZ,.OWNER                 ; is type-mismatch.
.FAULT:                        ; A is the diagnostic,
    LD   HL,(EX_START)             ; at the
    JP   DG_HERE                   ; subject.
.OWNER:                        ; The subject's kind:
    LD   HL,(EX_START)             ; used,
    LD   (FW_PLACE),HL             ; at its name:
    LD   A,(AC_BOUND)              ; an owner
    BIT  1,A                       ; directly
    CALL Z,FW_SEEN               ; (noteDirect),
    CALL FW_USE                    ; then checkUsable.
    LD   C,8                       ; A handle select,
    CALL FW_ALONE                  ; a lease
    JR   NZ,.LOAD                  ; for the root alone,
    CALL FW_ROOT                   ; the routine's own owning local
    JR   NC,.LOAD                  ; (a tracked owner):
    LD   C,8+64                    ; bit 6.
.LOAD:                         ; C is the mode.
    PUSH BC                        ; Kept.
    CALL HN_WIDE                   ; A word or a long:
    LD   (RO_OTYPE),A              ; the handle
    PUSH AF                        ; (the type kept)
    CALL GA_LOAD                   ; loaded.
.SLOT:                         ; The handle is in the registers.
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
.MOVE:                         ; `select move`: an optional owner,
    LD   A,(AC_BOUND)              ; writable,
    AND  3                         ; or syntax
    DEC  A                         ; at `select`.
    LD   HL,RO_PRO                 ; (AG_HOPT
    OR   (HL)                      ; alone
    LD   A,DG_STMT                 ; and not
    LD   HL,AC_DELTA+2             ; read-only)
    JP   NZ,DG_AT                  ; No return.
    LD   HL,(EX_START)             ; Moved,
    LD   (FW_PLACE),HL             ; at its name,
    CALL FW_MOVE                   ; in this statement;
    CALL HN_EMOV                   ; moved out, in HL.
    LD   C,8+16                    ; A handle select, bit 4 move;
    PUSH BC                        ; kept;
    LD   A,SY_U16                  ; the slot
    PUSH AF                        ; a word.
    JR   .SLOT                     ; Kept there.

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
    BIT  4,A                       ; A move's
    JR   NZ,.MOVED                 ; binds an owner.
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
.MOVED:                        ; `select move`'s some arm:
    LD   B,CT_FBND                 ; the
    CALL CT_FBYTE                  ; type,
    LD   (AC_BOUND),A              ; staged.
    LD   A,2                       ; Two bytes
    CALL EM_ALLOC                  ; of its own,
    PUSH HL                        ; kept;
    LD   B,CT_FVAR                 ; the
    CALL CT_FWORD                  ; slot's
    LD   A,SY_U16                  ; handle
    CALL GX_FLOAD                  ; loaded,
    CALL EM_HELP                   ; CALL LINK0,
    DW   HP_LINK0                  ; then
    POP  HL                        ; stored
    PUSH HL                        ; there
    LD   A,SY_U16                  ; (LD (IX+d),L,
    CALL GX_FPUT                   ; LD (IX+d+1),H).
    POP  BC                        ; Its offset,
    CALL EX_RENEW                  ; the name's
    LD   D,SY_AGGR+SY_LOCAL        ; payload,
    CALL EX_PREP                   ; declared,
    LD   A,FW_VALUE                ; a value,
    CALL HN_STAT                   ; an owner
    LD   A,(AC_BOUND)              ; not
    AND  $FE                       ; optional.
    JR   .TAG                      ; Committed.

;@ROUTINE OUT A CLOBBERS BC,DE,HL,IX,IY,CARRY,ZERO,SIGN,PARITY,HALFCARRY
; Parse `move PATH`, `move` next, and generate it (moveExpression): the
; path an owning handle location (not-owner) that may be written
; (not-writable), each at `move`; usable (checkUsable) and moved in this
; statement (noteMove, at `move`); the handle into HL and none left in
; its place (emitMove): through an address, LD E,(HL), LD (HL),0, INC HL,
; LD D,(HL), LD (HL),0, EX DE,HL; at a static or frame place, its load,
; PUSH HL, LD HL,0, its store, POP HL. A tracked owner, the root alone, is
; then none if optional, else maybe. A returns the handle's type.

HN_MOVE:                       ; `move` is next.
    CALL PR_SPOT                   ; Its offset,
    PUSH HL                        ; kept,
    CALL PR_TAKE                   ; taken;
    LD   E,TK_NAME                 ; the path's
    CALL PR_NEED                   ; root's name:
    CALL SY_FIND                   ; a symbol?
    JR   C,.SYMBOL                 ; If not, a routine
    CALL RO_FIND                   ; is
    JR   Z,.CLASS                  ; wrong-class; else undeclared.
.PATH:                         ; The path:
    CALL RO_NAMED                  ; A its type.
.SCALAR:                       ; A is the type.
    POP  HL                        ; At `move`:
    PUSH AF                        ; (the type kept)
    LD   (HN_AT),HL                ; (kept),
    CALL PL_ISHND                  ; an owning
    JR   NC,.OWNER                 ; handle
    AND  AG_HID                    ; location,
    JR   Z,.WRITE                  ; or not-owner.
.OWNER:                        ; Not one:
    LD   A,DG_OWNER                ; not-owner,
    JR   .FAULT                    ; at `move`.
.WRITE:                        ; Writable?
    LD   A,(RO_PRO)                ; If not,
    OR   A                         ; not-writable
    LD   A,DG_CONST                ; at
    JR   NZ,.FAULT                 ; `move`.
    LD   HL,(EX_START)             ; Usable,
    LD   (FW_PLACE),HL             ; at its name;
    CALL FW_USE                    ; then
    LD   HL,(HN_AT)                ; moved,
    LD   (FW_PLACE),HL             ; at
    CALL FW_MOVE                   ; `move`.
    LD   HL,0                      ; (HN_AT
    LD   (HN_AT),HL                ; used.)
    CALL HN_EMOV                   ; The handle moved out.
    POP  AF                        ; The type:
    PUSH AF                        ; the root alone,
    RRA                            ; tracked, is none
    LD   A,FW_NONE                 ; if optional,
    JR   C,.STATE                  ; else
    LD   A,FW_MAYBE                ; maybe.
.STATE:                        ; A is its state.
    CALL FW_SET                    ; Set (RO_OTYPE is the type).
    POP  AF                        ; The type.
    RET                            ; HL holds the handle.
.FAULT:                        ; A is the diagnostic,
    LD   HL,(HN_AT)                ; at
    JP   DG_HERE                   ; `move`.
.SYMBOL:                       ; A symbol, HL its record:
    INC  HL                        ; its
    INC  HL                        ; class
    INC  HL                        ; byte.
    LD   A,(HL)                    ; A type's name
    AND  SY_TYPE                   ; is no
    JR   NZ,.CLASS                 ; variable;
    BIT  7,(HL)                    ; an aggregate's path is
    JR   NZ,.PATH                  ; parsed (a constant's too);
    LD   A,(HL)                    ; a scalar
    AND  SY_CMASK                  ; constant is
    JR   Z,.CLASS                  ; no variable;
    CALL PR_PEEK                   ; a scalar has
    CP   TK_DOT                    ; no fields
    LD   A,DG_FIELD                ; (no-such-field
    JP   Z,DG_ISSUE                ; at the dot),
    CALL PR_PEEK                   ; no
    CP   TK_LBRAC                  ; elements
    LD   A,DG_NOIDX                ; (not-indexable,
    JP   Z,DG_ISSUE                ; at the bracket),
    XOR  A                         ; and is no owner.
    JR   .SCALAR                   ; (not-owner)
.CLASS:                        ; Not a variable:
    LD   A,DG_CLASS                ; wrong-class,
    JP   DG_NAMED                  ; naming it.

;@ROUTINE CLOBBERS A,BC,DE,HL,CARRY,ZERO,SIGN,PARITY,HALFCARRY
; Move the owning handle at the path in hand into HL, leaving none
; (emitMove). RO_OTYPE is kept.

HN_EMOV:                       ; The path is an owning handle's.
    LD   A,(RO_PKIND)              ; Through an
    CP   GA_ALIAS                  ; address
    JR   C,.PLACED                 ; (alias or computed)?
    CALL GA_ADDR                   ; Its address,
    CALL EM_SEQ                    ; LD E,(HL), LD (HL),0, INC HL,
    DB   8,$5E,$36,0,$23,$56,$36,0,$EB ; LD D,(HL), LD (HL),0, EX DE,HL.
    RET                            ; Done.
.PLACED:                       ; Static or in the frame:
    LD   A,(RO_OTYPE)              ; the type
    PUSH AF                        ; (kept),
    LD   A,SY_U16                  ; a word
    LD   (RO_OTYPE),A              ; loaded,
    CALL GA_LOAD                   ; LD HL,(nn) or (IX+d);
    CALL EM_SEQ                    ; PUSH HL,
    DB   4,$E5,$21,0,0             ; LD HL,0,
    CALL GA_STORE                  ; stored,
    CALL EM_OP                     ; POP HL.
    DB   $E1                       ; Then
    POP  AF                        ; the type
    LD   (RO_OTYPE),A              ; again.
    RET                            ; Done.

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
    DEC  A                         ; outside it
.FRAME:                        ; that leases it
    CALL HN_SCAN                   ; too
    RET  NC                        ; (none left)
    RES  7,(HL)                    ; leases it no longer.
    JR   .FRAME                    ; The next.
