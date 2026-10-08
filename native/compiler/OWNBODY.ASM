;==========================================================================
;  Handle selects, leases passed and id() of records
;==========================================================================
;
;  The actions a routine's body takes for a handle select (HSELECT.ASM):
;  its subject (OW_SEL), an arm's some or none (OW_ARM, with OW_TEST and
;  OW_ONCE), case else (OW_ELSE) and a some arm's binding (OW_TAKEN); a
;  lease passed to a record parameter (OW_LEASA, from HN_LEASA); and id()
;  of a record (OW_IDREC, from HIDENT.ASM). Moved from the OWNERS overlay
;  and resident: in a routine's body they took turns with FLOAT, whose
;  place OWNERS shared, at every arm whose code folds an f32 constant.
;
;  Principal entries:
;    OW_SEL    a handle select's subject, AC_BOUND its type
;    OW_ARM    an arm's some or none
;    OW_ELSE   case else
;    OW_TAKEN  a some arm's binding
;    OW_LEASA  a lease passed to a record parameter
;    OW_IDREC  id(...) of a record

; ------------------------------------------------------- handle selects

;@ROUTINE IN A OUT A CLOBBERS BC,DE,HL,IX,IY,CARRY,ZERO,SIGN,PARITY,HALFCARRY
; SelectSubject's handle, of type AC_BOUND, the path in hand (selectHandle): its
; pool complete (pool-incomplete) and, owning, optional (type-mismatch),
; each at the subject; `select move` has its own checks. The handle, two
; bytes or an identifier's four, is loaded into a frame slot of its own
; (a call's identifier, AC_MODE one, is in DEHL already), which
; the arms test, and the select's frame opens (AC_SOPEN) with mode bit 3
; set, and bit 6 when the subject is the routine's own owning local,
; whose `some` arm binds a lease.

OW_SEL:                        ; AC_BOUND is the handle's type.
    LD   A,(AC_BOUND)              ; The type:
    CALL HN_REC                    ; the pool's record:
    LD   A,DG_PINC                 ; pool-incomplete
    JR   Z,.FAULT                  ; without one.
    LD   A,(AC_MODE)               ; `select move`
    OR   A                         ; has its own
    JR   Z,.MOVE                   ; checks;
    DEC  A                         ; a call's identifier
    JR   Z,.VALUE                  ; is in DEHL.
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
    LD   A,(RO_PKIND)              ; a lease for a local or
    CP   GA_FRAME                  ; parameter in the frame (not
    JR   NZ,.LOAD                  ; a slot-holder's location),
    CALL FW_ALONE                  ; for the root alone,
    JR   NZ,.LOAD                  ; and
    CALL FW_ROOT                   ; the routine's own owning local
    JR   NC,.LOAD                  ; (a tracked owner):
    LD   C,8+64                    ; bit 6.
.LOAD:                         ; C is the mode.
    PUSH BC                        ; Kept.
    CALL HN_WIDE                   ; A word or a long:
    LD   (RO_OTYPE),A              ; the handle
    PUSH AF                        ; (the type kept)
    CALL GA_LOAD                   ; loaded.
    JR   .SLOT                     ; Kept.
.VALUE:                        ; A call's identifier:
    LD   C,8                       ; a handle select,
    PUSH BC                        ; the mode kept,
    CALL HN_WIDE                   ; the long
    PUSH AF                        ; (kept) in DEHL.
.SLOT:                         ; The handle is in the registers.
    POP  AF                        ; Its
    PUSH AF                        ; size
    CALL GX_PROP                   ; in
    AND  7                         ; a slot
    CALL EM_ALLOC                  ; of its own,
    LD   (AC_INDEX),HL             ; for the frame,
    POP  AF                        ; which
    CALL GX_FPUT                   ; takes it.
    LD   HL,(RO_PROOT)             ; The subject's symbol,
    PUSH HL                        ; kept
    CALL AC_SOPEN                  ; as the select's frame opens.
    CALL CT_FLAGS                  ; Its mode
    POP  DE                        ; (DE the subject)
    POP  BC                        ; takes
    LD   A,C                       ; the
    OR   (HL)                      ; subject's
    LD   (HL),A                    ; kind;
    LD   BC,CT_FSUBJ-CT_FMODE      ; its CT_FSUBJ
    ADD  HL,BC                     ; the subject's
    LD   (HL),E                    ; record,
    INC  HL                        ; both
    LD   (HL),D                    ; bytes.
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


;@ROUTINE OUT A CLOBBERS BC,DE,HL,IX,IY,CARRY,ZERO,SIGN,PARITY,HALFCARRY
; CaseLabels of a handle select: `some(NAME)`, at most once, or `none`,
; at most once with case else (syntax at `case`, AC_SPOS); the subject
; tested, JP Z to the next arm for some, JP NZ for none. Mode bit 2 is
; some seen, bit 1 none or else, bit 7 that this arm is some.

OW_ARM:                        ; After `case`.
    CALL PR_PEEK                   ; some
    CP   TK_SOME                   ; or
    JR   Z,.SOME                   ; none?
    CP   TK_NONE                   ; Anything else:
    LD   A,DG_TOKEN+TK_ELSE        ; `else`
    JP   NZ,DG_ISSUE               ; expected.
    CALL PR_TAKE                   ; `none`:
    LD   C,2                       ; bit 1,
    CALL OW_ONCE                   ; once,
    RES  7,(HL)                    ; not some;
    LD   C,$C2                     ; JP NZ
    JR   OW_TEST                   ; on; return.
.SOME:                         ; `some`:
    CALL PR_TAKE                   ; taken,
    LD   C,4                       ; bit 2,
    CALL OW_ONCE                   ; once,
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

OW_TEST:                       ; C is JP Z or JP NZ.
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

OW_ONCE:                       ; C is the bit.
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

OW_ELSE:                       ; After `case else`.
    LD   C,2                       ; Bit 1,
    CALL OW_ONCE                   ; once,
    RES  7,(HL)                    ; not some.
    LD   C,$C2                     ; JP NZ
    CALL OW_TEST                   ; on.
    JP   AC_LIVE                   ; Reachable; return.

;@ROUTINE OUT A CLOBBERS BC,DE,HL,CARRY,ZERO,SIGN,PARITY,HALFCARRY
; CaseBody of a handle select: a some arm binds its name, retained
; (EX_DECL), at the start of its block: to the routine's own owning local
; (mode bit 6), a lease, an alias through the subject's slot (SY_LEASE),
; of the pool's record; otherwise an identifier, non-optional, in four
; bytes of its own, LD the slot, CALL ID_MAKE for an owner, then stored.
; The arm is reachable.

OW_TAKEN:                      ; The arm's body begins.
    CALL CT_MODE                   ; The select's mode:
    BIT  7,A                       ; a some arm?
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

;@ROUTINE OUT HL CLOBBERS A,BC,DE,CARRY,ZERO,SIGN,PARITY,HALFCARRY
; An argument for record parameter AC_BOUND (AG_VAR for var) whose path,
; in hand, is handle type RO_OTYPE, a local's or parameter's usable
; (checkUsable): a lease (7.14), an owner neither optional nor an
; identifier of a pool of that record (type-mismatch otherwise), a local
; or parameter (a call's result or an element waits, DG_NYI), the
; routine's own owning local or parameter alone (lease otherwise), each
; at the argument; used directly (noteDirect); its value in HL, and for a
; var parameter PUSH HL first, the owner word being the record itself.

OW_LEASA:                      ; The path is parsed:
    LD   A,(RO_PKIND)              ; a local's or
    CP   GA_FRAME                  ; parameter's
    CALL Z,FW_USE                  ; usable (checkUsable);
    LD   A,(AC_BOUND)              ; the parameter's
    LD   B,A                       ; type, B;
    LD   A,(RO_OTYPE)              ; the path's,
    LD   C,A                       ; C:
    AND  3                         ; An owner, not optional
    JP   NZ,EX_EFIT                ; (type-mismatch otherwise),
    LD   A,C                       ; of a pool
    PUSH BC                        ; whose
    CALL HN_REC                    ; record
    POP  BC                        ; is the
    LD   C,A                       ; parameter's
    LD   A,B                       ; type
    AND  $7F                       ; (type-mismatch
    CP   C                         ; otherwise),
    JP   NZ,EX_EFIT                ; at the argument;
    LD   A,(RO_PKIND)              ; a local or parameter
    CP   GA_FRAME                  ; (a call's result or an
    JP   NZ,TR_OPER                ; element waits),
    PUSH BC                        ; (kept)
    CALL FW_ALONE                  ; the root alone
    JR   NZ,.LEASE                 ; (lease otherwise);
    CALL FW_SEEN                   ; used directly (noteDirect);
    LD   HL,(RO_PBASE)             ; its value,
    LD   A,SY_U16                  ; LD L,(IX+d),
    CALL GX_FLOAD                  ; LD H,(IX+d+1).
    POP  BC                        ; A var parameter
    BIT  7,B                       ; takes it
    RET  Z                         ; as its owner word too:
    LD   A,$E5                     ; PUSH HL,
    JP   GX_PUSHA                  ; two bytes pushed; return.
.LEASE:                        ; Not the routine's own:
    LD   A,DG_LEASE                ; lease, at
    JP   EX_EVAL                   ; the argument.

;@ROUTINE OUT A CLOBBERS BC,DE,HL,CARRY,ZERO,SIGN,PARITY,HALFCARRY
; `id(PATH)` of a record, the path in hand and `id` at AC_BOUND
; (idExpression): a record alone, a lease or a var record parameter (an
; owner word), else not-owner at `id`; of one pool (two or none are
; id-ambiguous at `id`, naming the record). Its identifier when the owner
; word is its address and the slot before it is the pool's, else none:
; LD HL,owner, LD DE,alias, OR A, SBC HL,DE, JP NZ,none, EX DE,HL,
; PUSH HL, DEC HL, LD D,(HL), DEC HL, LD E,(HL), LD HL,info, OR A,
; SBC HL,DE, POP HL, JP NZ,none, CALL ID_MAKE, JP done;
; none: LD HL,0, LD DE,0; done:. A returns its type, an optional
; identifier of that pool.

OW_IDREC:                      ; The path is parsed.
    LD   A,(RO_OTYPE)              ; A record's
    CALL AG_DESC                   ; descriptor
    LD   A,(HL)                    ; (its
    CP   AG_KREC                   ; kind),
    JP   NZ,.OWNER                 ; alone,
    CALL FW_ALONE                  ; with
    JP   NZ,.OWNER                 ; an owner
    LD   HL,(RO_POWN)              ; word (a lease
    LD   A,H                       ; or a var
    OR   L                         ; record
    JP   Z,.OWNER                  ; parameter):
    LD   HL,PL_CNT                 ; its pool,
    LD   B,(HL)                    ; from the last
    LD   C,$FF                     ; declared, none yet:
.EACH:                         ; B pools are left.
    LD   A,B                       ; The
    SUB  1                         ; next
    JR   C,.DONE                   ; (none left),
    LD   B,A                       ; B,
    CALL PL_AT                     ; its
    INC  HL                        ; record
    INC  HL                        ; (PL_EREC):
    LD   A,(RO_OTYPE)              ; this
    CP   (HL)                      ; one?
    JR   NZ,.EACH                  ; No.
    INC  C                         ; A second
    JP   NZ,.AMBIG                 ; is id-ambiguous;
    LD   C,B                       ; the first is kept.
    JR   .EACH                     ; On.
.DONE:                         ; C is the pool, $FF none.
    LD   A,C                       ; None
    INC  A                         ; is
    JR   Z,.AMBIG                  ; too.
    LD   A,C                       ; The pool's
    PUSH AF                        ; index kept,
    CALL PL_AT                     ; and its
    LD   E,(HL)                    ; information's
    INC  HL                        ; ordinal
    LD   D,(HL)                    ; (PL_EORD)
    PUSH DE                        ; too.
    LD   HL,(RO_POWN)              ; LD L,(IX+owner),
    LD   A,SY_U16                  ; LD H,(IX+owner+1);
    CALL GX_FLOAD                  ; then
    LD   HL,(RO_PBASE)             ; LD E,(IX+alias),
    LD   DE,GX_DLDDE               ; LD D,(IX+alias+1);
    CALL GX_FACC                   ; OR A,
    CALL EM_SEQ                    ; SBC HL,DE,
    DB   3,$B7,$ED,$52             ; then
    LD   C,$C2                     ; JP NZ,none,
    CALL EM_FWD                    ; its label
    PUSH AF                        ; kept;
    CALL EM_OP                     ; EX DE,HL,
    DB   $EB                       ; then
    CALL GX_PUSHW                  ; PUSH HL, counted;
    CALL EM_SEQ                    ; DEC HL, LD D,(HL),
    DB   4,$2B,$56,$2B,$5E         ; DEC HL, LD E,(HL);
    CALL EM_OP                     ; LD HL,
    DB   $21                       ; the
    POP  BC                        ; pool's
    POP  HL                        ; information
    PUSH BC                        ; (the label
    LD   DE,0                      ; kept);
    CALL EM_REF                    ; OR A,
    CALL EM_SEQ                    ; SBC HL,DE,
    DB   3,$B7,$ED,$52             ; then
    LD   A,SY_U16                  ; POP HL,
    CALL GX_POPV                   ; popped;
    POP  AF                        ; JP NZ
    PUSH AF                        ; to
    LD   C,$C2                     ; none
    CALL EM_JUMP                   ; again;
    CALL EM_HELP                   ; CALL
    DW   HP_IDMK                   ; ID_MAKE;
    LD   C,$C3                     ; JP
    CALL EM_FWD                    ; done.
    POP  BC                        ; none's label,
    PUSH AF                        ; done's kept:
    LD   A,B                       ; none:
    CALL EM_LDONE                  ; LD HL,0,
    CALL EM_SEQ                    ; LD DE,0;
    DB   6,$21,0,0,$11,0,0         ; then
    POP  AF                        ; done:
    CALL EM_LDONE                  ; here.
    POP  AF                        ; The pool's
    ADD  A,A                       ; optional
    ADD  A,A                       ; identifier's
    ADD  A,AG_HND+AG_HID+AG_HOPT   ; type.
    RET                            ; DEHL holds it.
.AMBIG:                        ; Not of one pool:
    LD   A,(RO_OTYPE)              ; the record's
    CALL OW_TNAME                  ; name,
    LD   (TK_PTR),HL               ; at HL, B bytes,
    LD   A,B                       ; made
    LD   (TK_LEN),A                ; the current
    LD   HL,TK_PTR                 ; name's,
    LD   A,DG_IDAMB                ; names
    CALL DG_SETN                   ; id-ambiguous,
    JR   .AT                       ; at `id`.
.OWNER:                        ; Not an owner's:
    LD   A,DG_OWNER                ; not-owner,
.AT:                           ; A is the diagnostic,
    LD   HL,(AC_BOUND)             ; at
    JP   DG_HERE                   ; `id`.

;@ROUTINE IN A OUT HL,B CLOBBERS A,C,DE,CARRY,ZERO,SIGN,PARITY,HALFCARRY
; The name of table type A, a record's: the symbol of class SY_RTYPE whose
; payload is A. HL returns its spelling and B its length.

OW_TNAME:                      ; A is the type.
    LD   C,A                       ; Kept.
    LD   HL,(SY_TOP)               ; The symbols, each, from the last:
.LOOK:                         ; HL is past the next.
    LD   DE,(SY_BTM)               ; Before
    CALL CP_HLDE                   ; the first? Then
    JR   Z,.NONE                   ; none is.
    LD   DE,-SY_RECB               ; The
    ADD  HL,DE                     ; record before.
    PUSH HL                        ; Kept.
    INC  HL                        ; Its
    INC  HL                        ; class
    INC  HL                        ; byte:
    LD   A,(HL)                    ; a record
    CP   SY_RTYPE                  ; type
    JR   NZ,.NEXT                  ; whose
    INC  HL                        ; payload
    LD   A,(HL)                    ; is
    CP   C                         ; the type?
    JR   NZ,.NEXT                  ; No.
    POP  HL                        ; The record:
    CALL WD_GET                    ; its spelling's address and
    LD   B,(HL)                    ; length.
    EX   DE,HL                     ; HL is the spelling.
    RET                            ; Done.
.NEXT:                         ; Not it.
    POP  HL                        ; The one
    JR   .LOOK                     ; before.
.NONE:                         ; None:
    LD   B,0                       ; no name.
    RET                            ; HL is anything.
