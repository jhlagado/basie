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


;@ROUTINE IN B OUT HL CLOBBERS A,BC,DE,CARRY,ZERO,SIGN,PARITY,HALFCARRY
; A lease passed to record parameter B (OW_LEASA, staged in AC_BOUND).

HN_LEASA:                      ; B is the parameter's type,
    LD   A,B                       ; staged;
    LD   (AC_BOUND),A              ; the handle
    CALL HN_TAIL                   ; alone (DG_NYI otherwise):
    LD   A,24                      ; 24.
    JR   HN_OVL                    ; Run.

;@ROUTINE IN A OUT A CLOBBERS BC,DE,HL,CARRY,ZERO,SIGN,PARITY,HALFCARRY
; A handle select's actions, in the OWNERS overlay (OWNERS.ASM), each
; loaded and run through its jump table (OV_PCALL): the subject of type A
; (OW_SEL, A staged in AC_BOUND), an arm's some or none (OW_ARM), its
; binding (OW_TAKEN) and case else (OW_ELSE).

HN_SEL:                        ; A is the subject's type,
    LD   (AC_BOUND),A              ; staged:
    LD   A,12                      ; entry 12.
    JR   HN_OVL                    ; Run.
HN_ARM:                        ; An arm's some or none:
    LD   A,15                      ; entry 15.
    JR   HN_OVL                    ; Run.
HN_ELSE:                       ; case else:
    LD   A,18                      ; entry 18.
    JR   HN_OVL                    ; Run.
HN_TAKEN:                      ; A some arm's binding:
    LD   A,21                      ; entry 21.
HN_OVL:                        ; A is the entry's offset:
    JP   OV_PCALL                  ; run (OVERLAY.ASM); return.

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
; Parse `move PATH`, `move` next, and generate it (moveExpression): the
; path an owning handle location (not-owner) that may be written
; (not-writable), each at `move`; usable (checkUsable) and moved in this
; statement (noteMove, at `move`); the handle into HL and none left in
; its place (emitMove): through an address, LD E,(HL), LD (HL),0, INC HL,
; LD D,(HL), LD (HL),0, EX DE,HL; at a static or frame place, its load,
; PUSH HL, LD HL,0, its store, POP HL. A tracked owner, the root alone, is
; then none if optional, else maybe. A returns the handle's type.

HN_MOVE:                       ; `move` is next:
    LD   HL,HN_MVLG                ; none in a statement
    BIT  1,(HL)                    ; with `and` or `or`, a while's
    JP   NZ,TR_OPER                ; or an assert's condition
    SET  0,(HL)                    ; yet (DG_NYI).
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
