;==========================================================================
;  Assignments to aggregate paths
;==========================================================================
;
;  The assignment statement whose target is a path (the reference
;  compiler's assign): its target parsed and checked, its value parsed
;  and stored, a handle's through OWN_SET, an aggregate copied, a string's
;  length set through STR_SETL. Split from CALLS.ASM, which it follows.
;
;  Principal entries:
;    RO_LET    parse an assignment to an aggregate path
;    RO_ASGN   the assignment once its target's path is parsed

;@ROUTINE OUT A,CARRY,ZERO CLOBBERS SIGN,PARITY,HALFCARRY,BC,DE,HL,IX,IY
; Parse an assignment whose target is a path rooted at the current NAME,
; an aggregate symbol (assign): a read-only target raises DG_CONST, as
; does a view as a whole. A writable open string's length is set through
; STR_SETL, which checks and zeroes: the value in A, LD E,A, the capacity's
; low byte, LD A,(IX+n+2), LD D,A, the address, LD L,(IX+n), LD H,(IX+n+1),
; CALL STR_SETL. An aggregate is copied: its address pushed, the source's address, POP DE,
; LD BC,size, LDIR, the source a path or call of the same type or, for a
; string, a literal within its capacity (DG_LONG), which takes the whole
; string's bytes. A scalar's value is checked against its type and stored:
; through its address, computed first and pushed while the value is,
; then POP DE and LD (DE),A or EX DE,HL, LD (HL),E, INC HL, LD (HL),D; or
; at a static or frame place directly. A File is a value (RO_FVAL),
; stored as a long is, at any place. Then any failure handling.

RO_LET:
    LD   HL,AC_ROUTE               ; Any failure handling
    PUSH HL                        ; follows each arm.
    CALL RO_NAMED                  ; Parse the target; A is its type.
    PUSH AF                        ; Keep it.
    CALL PR_EQUAL                  ; Consume the equals sign.
    LD   A,(RO_PRO)                ; A read-only target
    OR   A                         ; cannot be
    JP   NZ,RO_EROOT               ; assigned: raise DG_CONST at it.
    POP  AF                        ; The target's type.
    CALL HN_NOTE                   ; Its root used or moved (flow).
    CALL PL_ISHND                  ; A handle's type-mismatch
    JR   NC,RO_ASGN                ; is reported
    LD   HL,(EX_START)             ; at the target
    LD   (HN_AT),HL                ; (assign's at); fall into RO_ASGN.

;@ROUTINE IN A OUT A,CARRY,ZERO CLOBBERS SIGN,PARITY,HALFCARRY,BC,DE,HL,IX,IY
; Assign to the path in hand (RO_PLACE), of type A, its value parsed: as
; RO_LET does after the equals sign; new's fields too (HN_NEW).

RO_ASGN:                       ; A is the path's type.
    CALL HN_RSET                   ; An identifier's slot to recheck.
    CALL AG_ISVW                   ; A view as a whole
    JR   NC,.KIND                  ; is not writable:
    LD   A,DG_CONST                ; not-writable,
    JP   EX_EVAL                   ; at its start.
.KIND:                         ; A is the target's type.
    CALL PL_ISHND                  ; A handle takes
    JP   C,HN_LET                  ; an owning value.
    CP   AG_FILE                   ; A File?
    JR   Z,.FILE                   ; Its value is stored.
    CP   AG_FIRST                  ; A scalar?
    JR   C,.SCALAR                 ; Its value is stored; an aggregate
.COPY:                         ; is copied whole, of type A.
    PUSH AF                        ; Keep the type.
    CALL PL_OWNS                   ; An owning one
    LD   A,DG_OCOPY                ; is not copied (owning-copy,
    JP   C,EX_EVAL                 ; at the target).
    POP  AF                        ; The type,
    PUSH AF                        ; kept.
    CALL GA_ADDR                   ; The target's address,
    CALL GX_PUSHW                  ; PUSH HL, two bytes pushed.
    CALL PR_PEEK                   ; A string literal?
    CP   TK_TEXT                   ; Then
    JR   Z,.TEXT                   ; it is copied in.
    CALL RO_AGGR                   ; Parse the source; A is its type.
    POP  DE                        ; D is the target's type.
    CP   D                         ; The types must be the same,
    JP   NZ,EX_EFIT                ; else DG_CLASH at the source.
.COPIED:                       ; A is the type; the source is in HL.
    PUSH AF                        ; Keep the type.
    CALL HN_RECK                   ; The target's identifier rechecked;
    CALL GA_POPDE                  ; POP DE, the target.
    POP  AF                        ; The type's
    CALL AG_SIZE                   ; size, HL:
    JP   GA_LDIR                   ; LD BC,size, LDIR; AC_ROUTE.
.TEXT:                         ; A literal into a string.
    POP  AF                        ; The target's type.
    PUSH AF                        ; Kept.
    CALL AG_DESC                   ; HL addresses the descriptor.
    LD   A,(HL)                    ; Its kind
    CP   AG_KSTR                   ; must be a string,
    JP   NZ,EX_ETYPE               ; else DG_CLASH.
    INC  HL                        ; Its capacity.
    LD   B,(HL)                    ; B is it.
    CALL AG_TAKE                   ; Consume the literal; BC is kept.
    LD   A,(TK_LEN)                ; The literal's length
    CP   B                         ; must not exceed it:
    JR   Z,.FITS                   ; equal fits,
    JP   NC,AG_ELONG               ; longer is out of range.
.FITS:                         ; B is the capacity.
    INC  B                         ; The string takes it
    INC  B                         ; and two bytes more.
    CALL GA_LIT                    ; LD HL,literal.
    POP  AF                        ; The string's type.
    JR   .COPIED                   ; Copy it.
.FILE:                         ; A File: four bytes, a long's,
    LD   A,SY_U32                  ; stored
    LD   (RO_OTYPE),A              ; as a long is.
    LD   A,(RO_PKIND)              ; A computed place?
    CP   GA_HELD                   ; Its address
    CALL Z,GX_PUSHW                ; is pushed: PUSH HL.
    CALL RO_KEEP                   ; Keep the place across the value,
    CALL RO_FVAL                   ; into DEHL,
    CALL RO_BACK                   ; and the place comes back.
    JR   .PLACED                   ; Store it.
.SCALAR:                       ; A scalar target.
    LD   A,(RO_PPUSH)              ; A writable open string's
    AND  4                         ; length
    JR   NZ,.SETL                  ; is set through STR_SETL.
    LD   A,(RO_PKIND)              ; A computed place?
    CP   GA_HELD                   ; Its address
    CALL Z,GX_PUSHW                ; is in HL: PUSH HL, two bytes pushed.
    LD   A,(RO_OTYPE)              ; The target's type
    CALL .VALUE                    ; is wanted of the value.
    LD   A,(RO_OTYPE)              ; The target's type
    LD   E,A                       ; is the value's destination:
    CALL AC_FITTO                  ; it must fit; D, E and HL describe it,
    CALL GX_TOREG                  ; brought into A or HL.
.PLACED:                       ; The value is in the registers:
    LD   A,(RO_PKIND)              ; a computed place?
    CP   GA_HELD                   ; Its address is pushed:
    JR   Z,.THROUGH                ; store through it.
    JP   GA_STORE                  ; Store at the place; AC_ROUTE.
.THROUGH:                      ; The address is pushed.
    CALL HN_RECK                   ; Its identifier rechecked.
    LD   A,(RO_OTYPE)              ; A long?
    CALL GX_SIZE                   ; Then
    JR   C,.SHORT                  ; through
    JR   Z,.SHORT                  ; BC:
    CALL EM_SEQ                    ; POP BC, then LD A,L, LD (BC),A,
    DB   12,$C1,$7D,$02,$03,$7C,$02,$03,$7B,$02,$03,$7A,$02 ; INC BC... for H, E, D.
    JP   EM_POP2                   ; Two bytes fewer pushed; AC_ROUTE.
.SHORT:                        ; A byte or a word.
    PUSH AF                        ; Keep the size's flags.
    CALL GA_POPDE                  ; POP DE, two bytes fewer pushed.
    POP  AF                        ; A word?
    LD   A,$12                     ; LD (DE),A for a byte.
    JR   C,.STORE                  ; A byte.
    CALL EM_SEQ                    ; EX DE,HL, LD (HL),E, INC HL:
    DB   3,$EB,$73,$23             ; the low byte,
    LD   A,$72                     ; then LD (HL),D.
.STORE:                        ; A is the last byte.
    JP   EM_BYTE                   ; Append it; AC_ROUTE.
.VALUE:                        ; A value of type A is wanted:
    CALL RO_KEEP                   ; the place kept across it,
    LD   HL,RO_DEPTH               ; the value parsed, nested
    INC  (HL)                      ; in the enclosing expression
    DEC  (HL)                      ; inside a call's arguments
    JR   Z,.TOP                    ; (a field of new there),
    CALL EX_SUB                    ; or
    JR   .GOT                      ; on
.TOP:                          ; its
    CALL EX_RUN                    ; own,
.GOT:                          ; then
    CALL EX_STASH                  ; kept,
    CALL RO_BACK                   ; and the place back.
    RET                            ; D, E and HL describe the value.
.SETL:                         ; The path is s.length:
    LD   A,SY_U8                   ; a u8
    CALL .VALUE                    ; is wanted, its place kept.
    LD   HL,(AC_SPOS)              ; At the statement's root,
    LD   (EX_START),HL             ; where
    LD   E,SY_U8                   ; the value must fit a u8,
    CALL AC_FITTO                  ; brought
    CALL GX_TOREG                  ; into A.
    CALL EM_OP                     ; LD E,A,
    DB   $5F                       ; the length;
    LD   HL,(RO_PBASE)             ; the capacity's
    INC  HL                        ; low byte,
    INC  HL                        ; above the address word:
    LD   DE,GX_DLDA                ; LD A,(IX+n+2),
    CALL GX_FACC                   ; appended;
    CALL EM_OP                     ; LD D,A;
    DB   $57                       ; then
    LD   HL,(RO_PBASE)             ; the string's
    LD   A,SY_U16                  ; address,
    CALL GX_FLOAD                  ; LD L,(IX+n), LD H,(IX+n+1);
    CALL EM_HELP                   ; CALL STR_SETL.
    DW   HP_SETL                   ; Its figure counted.
    RET                            ; AC_ROUTE.
