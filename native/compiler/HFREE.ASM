;==========================================================================
;  Handles: frees
;==========================================================================
;
;  The frees of the owning handles (HANDLES.ASM, whose scopes and order
;  they follow): a scope's owning locals freed where it ends, at the end
;  of its block and at every return, fail, exit and continue that leaves
;  it (the reference's scopesFrom and emitFrees). HANDLES.ASM grew past
;  ATOM's 64K source limit; this is its second half, included after it.
;
;  Principal entries: HN_ENDB, HN_ENDR, HN_EXIT, HN_FAIL and HN_RET, as
;  HANDLES.ASM lists them.

; ---------------------------------------------------------------- frees

;@ROUTINE IN HL,DE CLOBBERS A,BC,DE,HL,CARRY,ZERO,SIGN,PARITY,HALFCARRY
; The frees of the symbol records from HL to DE, a scope's, in order:
; each owning handle
; local, LD L,(IX+d), LD H,(IX+d+1), LD A,H, OR L, CALL NZ,POOL_DEL, LD
; HL,0, LD (IX+d),L, LD (IX+d+1),H; or, while HN_MODE is set, nothing
; written, HN_SEEN set if there is one.

HN_SEG:                        ; HL the first record, DE past the last.
    CALL CP_HLDE                   ; Any left? (HL kept; carry if so)
    RET  NC                        ; No.
    PUSH HL                        ; The record
    PUSH DE                        ; and the end, kept.
    INC  HL                        ; its
    INC  HL                        ; class
    INC  HL                        ; byte,
    LD   A,(HL)                    ; an aggregate
    LD   C,A                       ; local's or
    OR   SY_PARAM-SY_LOCAL         ; parameter's, var
    AND  $FF-SY_PVAR-SY_PFROM      ; or from too,
    CP   SY_AGGR+SY_PARAM          ; but no lease's?
    JR   NZ,.NEXT                  ; No.
    INC  HL                        ; Its
    CALL WD_GET                    ; offset, DE, and its
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
.AGGR:                         ; An aggregate, if owning:
    LD   B,A                       ; (its type)
    PUSH DE                        ; (its offset)
    CALL PL_OWNS                   ; owning?
    POP  DE                        ; (BC kept)
    JR   NC,.NEXT                  ; No.
    LD   HL,HN_SEEN                ; One
    LD   (HL),H                    ; is seen;
    BIT  4,C                       ; a parameter's
    JR   NZ,.NEXT                  ; is never freed;
    LD   A,(HN_MODE)               ; a local's,
    OR   A                         ; unless
    JR   NZ,.NEXT                  ; only looking,
    LD   A,B                       ; is
    CALL HN_OFREE                  ; freed.
    JR   .NEXT                     ; Done.
.HOLDER:                       ; A slot-holder: an owner a return
    LD   A,(HN_MODE)               ; counts (hasOwners) when
    LD   (HN_SEEN),A               ; looking; none to free.
.NEXT:                         ; The record is done.
    POP  DE                        ; The end
    POP  HL                        ; and the record:
    LD   BC,SY_RECB                ; the
    ADD  HL,BC                     ; next.
    JR   HN_SEG                    ; Until its end.

;@ROUTINE CLOBBERS A,BC,DE,HL,CARRY,ZERO,SIGN,PARITY,HALFCARRY
; A block ends: the frees of the innermost frame's scope, from its first
; record when it opened (CT_FSYMS) to SY_TOP.

HN_ENDB:                       ; The innermost frame's block ends.
    LD   B,CT_FSYMS                ; Its first
    CALL CT_FWORD                  ; record, HL,
    LD   DE,(SY_TOP)               ; to the last.
    JR   HN_SEG                    ; Freed; return.

;@ROUTINE CLOBBERS A,BC,DE,HL,CARRY,ZERO,SIGN,PARITY,HALFCARRY
; The body ends: the frees of its scope, from SY_BODY to SY_TOP.

HN_ENDR:                       ; The body's block ends.
    LD   HL,(SY_BODY)              ; Its first record
    LD   DE,(SY_TOP)               ; to the last.
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
    LD   DE,(SY_TOP)               ; The run's end, DE.
    LD   A,(CT_DEPTH)              ; From the innermost frame.
.FRAME:                        ; Frame A-1 next, if not below B.
    CP   B                         ; Below
    JR   Z,.FRAMES                 ; the outermost?
    DEC  A                         ; Frame A:
    PUSH AF                        ; (kept)
    PUSH BC                        ; (with the outermost)
    PUSH DE                        ; (and the run's end)
    CALL CT_FRAME                  ; its
    LD   DE,CT_FSYMS               ; first
    ADD  HL,DE                     ; record,
    LD   E,(HL)                    ; DE,
    INC  HL                        ; then
    LD   D,(HL)                    ; HL,
    EX   DE,HL                     ; to
    POP  DE                        ; the run's end:
    PUSH HL                        ; (the next run's end)
    CALL HN_SEG                    ; its scope freed.
    POP  DE                        ; Its first record ends the next run.
    POP  BC                        ; The outermost,
    POP  AF                        ; the frame.
    JR   .FRAME                    ; The one outside.
.FRAMES:                       ; DE is the end of the next run out.
    POP  BC                        ; The routine's
    LD   A,C                       ; too?
    OR   A                         ; If not,
    RET  Z                         ; done.
    LD   HL,(SY_BODY)              ; The body's first record,
    PUSH HL                        ; (kept)
    CALL HN_SEG                    ; its scope freed;
    POP  DE                        ; then before it
    LD   HL,(SY_GTOP)              ; the parameters'.
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
