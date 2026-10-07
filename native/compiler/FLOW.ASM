;==========================================================================
;  Flow of owning handles
;==========================================================================
;
;  The reference compiler's check of owning handle locals (spec 7.17,
;  10.8, 11.4.1, 12.5.1; ref/compile/compiler.ts: snapshotFlow,
;  restoreFlow, meetFlow, checkBackEdge, checkUsable, noteDirect,
;  noteMove). Each tracked owner, an owning handle local, has a state:
;  none, value, or maybe (moved on some path), kept in byte 7 of its
;  symbol record (FW_STATE) with the statement rule's two bits: used
;  directly (FW_DIR) and moved (FW_MOVED) in the current statement.
;
;  A snapshot packs the states of the tracked owners in scope, two bits
;  each in symbol order, into four bytes (16 owners in scope at most,
;  capacity `owners` beyond); an absent owner is zero. A block's owners
;  follow its enclosing block's, so a snapshot taken deeper has the same
;  owners first. Each control frame has eight bytes in FW_TAB: the state
;  its arms start from (an if's after each condition, a select's after its
;  subject, a loop's at its body's start) and the meet of the states its
;  paths end in, zero while none has: equal states meet as they are,
;  different ones as maybe.
;
;  Principal entries:
;    FW_OPEN   a frame opens: its meet is empty
;    FW_ENTRY  the arms' or the body's starting state is the current one
;    FW_ARM    an arm ends: met if it falls through; the start restored
;    FW_ARMM   the last arm (else) ends: met if it falls through
;    FW_JOIN   an if or select ends: the start met unless it had an else
;              arm, then the meet applied
;    FW_LOOP   a loop's body ends: its back edge, the start met, applied
;    FW_EXIT   exit: the current state met into loop frame A's
;    FW_CONT   continue: loop frame A's back edge, at the keyword
;    FW_STMT   a statement begins: the statement rule's bits cleared
;    FW_USE    a tracked owner used through a path: not maybe, not moved
;    FW_SEEN, FW_MOVE  the statement rule's notes
;    FW_SET    a tracked owner's state set

;  Scratch (CALLWORK.ASM): FW_PTR a snapshot's address for a callee,
;  FW_CB the callee FW_EACH runs, FW_PLACE the offset a diagnostic is
;  reported at, FW_TMP a snapshot being made, FW_TAB the frames' rows.

FW_STATE EQU  7                ; Record byte: the flow state and rule bits.
FW_NONE EQU  1                 ; State: none.
FW_VALUE EQU  2                ; State: a value.
FW_MAYBE EQU  3                ; State: maybe moved.
FW_CAP EQU  16                 ; Tracked owners in scope; DG_OWNRS beyond.

;@ROUTINE IN HL OUT CARRY,HL CLOBBERS A,ZERO,SIGN,PARITY,HALFCARRY
; Carry if the symbol record at HL is a tracked owner, an owning handle
; local or parameter (not var); HL returns at its FW_STATE byte either
; way. BC and DE are kept.

FW_TRK:                        ; HL is a record.
    INC  HL                        ; Its
    INC  HL                        ; class
    INC  HL                        ; byte,
    LD   A,(HL)                    ; kept.
    INC  HL                        ; On
    INC  HL                        ; to
    INC  HL                        ; its type,
    AND  $FF-SY_PVAR               ; an aggregate local's
    OR   SY_PARAM-SY_LOCAL         ; or parameter's,
    CP   SY_AGGR+SY_PARAM          ; a slot-holder's too?
    LD   A,(HL)                    ; (the type)
    INC  HL                        ; (FW_STATE)
    JR   NZ,.NOT                   ; No.
    CALL PL_ISHND                  ; A handle
    JR   NC,.NOT                   ; that
    AND  AG_HID                    ; owns?
    JR   NZ,.NOT                   ; Not an identifier:
    SCF                            ; tracked.
    RET                            ; HL is its state byte.
.NOT:                          ; Not tracked.
    OR   A                         ; Carry clear.
    RET                            ; HL is its state byte.

;@ROUTINE CLOBBERS A,BC,DE,HL,CARRY,ZERO,SIGN,PARITY,HALFCARRY
; Call FW_CB for each tracked owner in scope, in symbol order, with HL at
; its state byte and B its position (0 up); capacity `owners` past FW_CAP.
; The callee may change A, DE and HL.

FW_EACH:                       ; FW_CB is the callee.
    LD   A,(RO_GLOBS)              ; The routine's first symbol
    LD   C,A                       ; is C,
    LD   B,0                       ; the position none yet.
.NEXT:                         ; Symbol C next.
    LD   A,(SY_CNT)                ; Past
    CP   C                         ; the last?
    RET  Z                         ; Done.
    LD   A,C                       ; Its
    CALL SY_AT                     ; record:
    CALL FW_TRK                    ; tracked?
    JR   NC,.SKIP                  ; No.
    LD   A,B                       ; One more
    CP   FW_CAP                    ; than room
    LD   A,DG_OWNRS                ; is capacity,
    JP   NC,DG_ISSUE               ; owners.
    PUSH BC                        ; The loop,
    CALL .CALL                     ; the callee,
    POP  BC                        ; back.
    INC  B                         ; The next position.
.SKIP:                         ; The next
    INC  C                         ; symbol.
    JR   .NEXT                     ; Until the last.
.CALL:                         ; HL is the state:
    PUSH HL                        ; the callee's
    LD   HL,(FW_CB)                ; address
    EX   (SP),HL                   ; is jumped to,
    RET                            ; returning above.

;@ROUTINE IN B OUT C,DE CLOBBERS A,CARRY,ZERO,SIGN,PARITY,HALFCARRY
; Position B's two bits in the snapshot at FW_PTR: DE returns their byte,
; C the bits' shift, twice B mod 4.

FW_PAIR:                       ; B is the position.
    LD   A,B                       ; Its byte,
    RRCA                           ; a quarter
    RRCA                           ; of it,
    AND  3                         ; in the
    LD   DE,(FW_PTR)               ; snapshot:
    ADD  A,E                       ; DE
    LD   E,A                       ; is
    ADC  A,D                       ; its
    SUB  E                         ; address.
    LD   D,A                       ; (Done.)
    LD   A,B                       ; Its place,
    AND  3                         ; twice,
    ADD  A,A                       ; is
    LD   C,A                       ; the shift.
    RET                            ; Done.

;@ROUTINE IN DE CLOBBERS A,BC,DE,HL,CARRY,ZERO,SIGN,PARITY,HALFCARRY
; Snapshot the current states into the four bytes at DE.

FW_TAKE:                       ; DE is the snapshot.
    LD   (FW_PTR),DE               ; For the callee.
    LD   H,D                       ; Its
    LD   L,E                       ; four
    LD   B,4                       ; bytes
.ZERO:                         ; are
    LD   (HL),0                    ; zero
    INC  HL                        ; to
    DJNZ .ZERO                     ; begin.
    LD   HL,.PUT                   ; Each owner's state
    JR   FW_RUN                    ; is put in; return.
.PUT:                          ; HL its state, B its position.
    LD   A,(HL)                    ; The state,
    AND  3                         ; alone,
    PUSH AF                        ; kept.
    CALL FW_PAIR                   ; Its byte and shift:
    POP  AF                        ; the state
    INC  C                         ; shifted
.UP:                           ; up
    DEC  C                         ; C
    JR   Z,.SET                    ; times
    RLCA                           ; into
    JR   .UP                       ; place,
.SET:                          ; then
    EX   DE,HL                     ; in
    OR   (HL)                      ; its
    LD   (HL),A                    ; byte.
    RET                            ; Done.

;@ROUTINE IN HL CLOBBERS A,BC,DE,HL,CARRY,ZERO,SIGN,PARITY,HALFCARRY
; Run callee HL for each tracked owner (FW_EACH).

FW_RUN:                        ; HL is the callee.
    LD   (FW_CB),HL                ; Kept;
    JR   FW_EACH                   ; each owner; return.

;@ROUTINE IN B OUT A CLOBBERS C,DE,CARRY,ZERO,SIGN,PARITY,HALFCARRY
; Position B's state in the snapshot at FW_PTR.

FW_GET:                        ; B is the position.
    CALL FW_PAIR                   ; Its byte and shift:
    LD   A,(DE)                    ; the byte
    INC  C                         ; shifted
.DOWN:                         ; down
    DEC  C                         ; C
    JR   Z,.DONE                   ; times,
    RRCA                           ; to
    JR   .DOWN                     ; the bottom:
.DONE:                         ; the two bits
    AND  3                         ; alone.
    RET                            ; A is the state.

;@ROUTINE IN HL CLOBBERS A,BC,DE,HL,CARRY,ZERO,SIGN,PARITY,HALFCARRY
; Set the current states from the snapshot at HL (restoreFlow): each
; owner whose state there is not zero.

FW_GIVE:                       ; HL is the snapshot.
    LD   (FW_PTR),HL               ; For the callee.
    LD   HL,.GET                   ; Each owner's state
    JR   FW_RUN                    ; is taken from it; return.
.GET:                          ; HL its state, B its position.
    CALL FW_GET                    ; Its state there:
    OR   A                         ; absent?
    RET  Z                         ; Then kept.
    LD   C,A                       ; The state
    LD   A,(HL)                    ; replaces
    AND  $FC                       ; the owner's,
    OR   C                         ; its rule bits
    LD   (HL),A                    ; kept.
    RET                            ; Done.

;@ROUTINE IN DE,HL CLOBBERS A,BC,DE,HL,CARRY,ZERO,SIGN,PARITY,HALFCARRY
; Meet the snapshot at HL into the meet at DE, pair by pair: an absent
; one takes the other's, equal ones stay, different ones are maybe.

FW_MEET:                       ; HL the snapshot, DE the meet.
    LD   B,4                       ; Four bytes,
.BYTE:                         ; each
    LD   C,3                       ; from its lowest pair:
.PAIR:                         ; C masks one.
    LD   A,(HL)                    ; The snapshot's
    AND  C                         ; bits:
    JR   Z,.ON                     ; absent, kept.
    PUSH BC                        ; (kept)
    LD   B,A                       ; Them.
    LD   A,(DE)                    ; The meet's:
    AND  C                         ; absent,
    JR   Z,.TAKE                   ; take them;
    CP   B                         ; the same,
    JR   Z,.SAME                   ; kept;
    LD   B,C                       ; else maybe.
.TAKE:                         ; B is the bits to add.
    LD   A,(DE)                    ; Into
    OR   B                         ; the
    LD   (DE),A                    ; meet.
.SAME:                         ; Done with the pair.
    POP  BC                        ; The counts.
.ON:                           ; The next pair:
    RLC  C                         ; the mask
    RLC  C                         ; on two,
    LD   A,C                       ; until
    CP   3                         ; it comes round.
    JR   NZ,.PAIR                  ; Another.
    INC  HL                        ; The
    INC  DE                        ; next
    DJNZ .BYTE                     ; byte.
    RET                            ; Done.

;@ROUTINE OUT HL CLOBBERS A,DE,CARRY,ZERO,SIGN,PARITY,HALFCARRY
; HL addresses the innermost frame's eight bytes in FW_TAB: its start's
; snapshot, then its meet. FW_ROW does so for frame A.

FW_TOP:                        ; The innermost frame.
    LD   A,(CT_DEPTH)              ; Its
    DEC  A                         ; index.
FW_ROW:                        ; A is a frame's index.
    ADD  A,A                       ; Eight
    ADD  A,A                       ; times
    ADD  A,A                       ; it,
    LD   E,A                       ; as
    LD   D,0                       ; a word,
    LD   HL,FW_TAB                 ; from
    ADD  HL,DE                     ; the table.
    RET                            ; HL is the row.

;@ROUTINE CLOBBERS A,DE,HL,CARRY,ZERO,SIGN,PARITY,HALFCARRY
; A frame opens (CT_PUSH): its start and meet are empty. BC is kept.

FW_OPEN:                       ; The frame is the innermost.
    CALL FW_TOP                    ; Its row,
    LD   E,8                       ; eight
.ZERO:                         ; bytes,
    LD   (HL),0                    ; each
    INC  HL                        ; zero.
    DEC  E                         ; Until
    JR   NZ,.ZERO                  ; all are.
    RET                            ; Done.

;@ROUTINE CLOBBERS A,BC,DE,HL,CARRY,ZERO,SIGN,PARITY,HALFCARRY
; The innermost frame's arms or body start from the current state.

FW_ENTRY:                      ; The state now.
    CALL FW_TOP                    ; The row's
    EX   DE,HL                     ; start
    JP   FW_TAKE                   ; is it; return.

;@ROUTINE CLOBBERS A,BC,DE,HL,CARRY,ZERO,SIGN,PARITY,HALFCARRY
; An arm of the innermost frame ends (after its block): its state is met
; when it falls through (FW_ARMM), then the arms' start is restored.

FW_ARM:                        ; The arm has ended.
    CALL FW_ARMM                   ; Met if it falls through; fall into FW_REST.

;@ROUTINE CLOBBERS A,BC,DE,HL,CARRY,ZERO,SIGN,PARITY,HALFCARRY
; The innermost frame's start is the state again: an if's next arm's, a
; select's every arm's as it begins.

FW_REST:                       ; The start
    CALL FW_TOP                    ; is
    JR   FW_GIVE                   ; restored; return.

;@ROUTINE CLOBBERS A,BC,DE,HL,CARRY,ZERO,SIGN,PARITY,HALFCARRY
; The current state is met into the innermost frame's meet, when control
; falls through (CT_FALLS); FW_MEETA meets it into frame A's always.

FW_ARMM:                       ; An arm has ended.
    LD   A,(CT_FALLS)              ; Unless
    OR   A                         ; it cannot
    RET  Z                         ; complete:
    LD   A,(CT_DEPTH)              ; the innermost
    DEC  A                         ; frame's.
FW_MEETA:                      ; A is the frame.
    CALL FW_ROW                    ; Its row's
    LD   DE,4                      ; meet,
    ADD  HL,DE                     ; kept;
    PUSH HL                        ; the state now,
    LD   DE,FW_TMP                 ; snapshot,
    CALL FW_TAKE                   ; taken;
    POP  DE                        ; then met
    LD   HL,FW_TMP                 ; into
    JR   FW_MEET                   ; it; return.

;@ROUTINE CLOBBERS A,BC,DE,HL,CARRY,ZERO,SIGN,PARITY,HALFCARRY
; An if or a select ends (meetFlow): without an else arm (mode bit 1) its
; start is met, as the path past every arm; then the meet, if any path
; reached the end, is the state.

FW_JOIN:                       ; Before the frame closes.
    CALL CT_MODE                   ; An else arm?
    BIT  1,A                       ; If not,
    CALL Z,FW_START                ; the start is met; fall into FW_APPLY.

;@ROUTINE CLOBBERS A,BC,DE,HL,CARRY,ZERO,SIGN,PARITY,HALFCARRY
; The innermost frame's meet, unless empty, becomes the state.

FW_APPLY:                      ; The paths are met.
    CALL FW_TOP                    ; The row's
    LD   DE,4                      ; meet:
    ADD  HL,DE                     ; empty
    PUSH HL                        ; (kept)
    LD   A,(HL)                    ; while
    INC  HL                        ; no
    OR   (HL)                      ; path
    INC  HL                        ; reached
    OR   (HL)                      ; the
    INC  HL                        ; end
    OR   (HL)                      ; (every byte
    POP  HL                        ; zero).
    RET  Z                         ; Then kept;
    JP   FW_GIVE                   ; else the state; return.

;@ROUTINE CLOBBERS A,BC,DE,HL,CARRY,ZERO,SIGN,PARITY,HALFCARRY
; The innermost frame's start is met into its meet.

FW_START:                      ; The start.
    CALL FW_TOP                    ; The row:
    LD   D,H                       ; its
    LD   E,L                       ; meet,
    INC  DE                        ; four
    INC  DE                        ; bytes
    INC  DE                        ; on,
    INC  DE                        ; takes
    JP   FW_MEET                   ; its start; return.

;@ROUTINE CLOBBERS A,BC,DE,HL,CARRY,ZERO,SIGN,PARITY,HALFCARRY
; A loop's body ends (whileStatement, forStatement, after its block): when
; it can complete, its back edge (at its `end`, TK_ENDP) and its state
; met; then its start met, and the meet the state.

FW_LOOP:                       ; The body has ended.
    LD   A,(CT_FALLS)              ; Can it
    OR   A                         ; complete?
    JR   Z,.JOIN                   ; No.
    LD   HL,(TK_ENDP)              ; At its `end`,
    LD   A,(CT_DEPTH)              ; the innermost
    DEC  A                         ; frame's
    PUSH AF                        ; (kept)
    CALL FW_BACK                   ; back edge,
    POP  AF                        ; then
    CALL FW_MEETA                  ; its state met.
.JOIN:                         ; The start
    CALL FW_START                  ; met,
    JR   FW_APPLY                  ; the state; return.

FW_EXIT EQU  FW_MEETA          ; exit from loop frame A: the state met into its.

;@ROUTINE IN A CLOBBERS A,BC,DE,HL,CARRY,ZERO,SIGN,PARITY,HALFCARRY
; continue in loop frame A: its back edge, at the keyword (TK_POS).

FW_CONT:                       ; A is the loop's frame.
    LD   HL,(TK_POS)               ; At `continue`; fall into FW_BACK.

;@ROUTINE IN A,HL CLOBBERS A,BC,DE,HL,CARRY,ZERO,SIGN,PARITY,HALFCARRY
; The back edge of loop frame A (checkBackEdge): an owner that is not
; optional and held a value at the loop's start must hold one again, or
; it is loop-moves-owner, naming it, at offset HL.

FW_BACK:                       ; A the frame, HL the place.
    LD   (FW_PLACE),HL             ; The place, kept.
    CALL FW_ROW                    ; The loop's
    LD   (FW_PTR),HL               ; start.
    LD   HL,.CHECK                 ; Each owner
    JP   FW_RUN                    ; checked; return.
.CHECK:                        ; HL its state, B its position.
    LD   A,(HL)                    ; Now
    AND  3                         ; a value?
    CP   FW_VALUE                  ; Then
    RET  Z                         ; it holds.
    DEC  HL                        ; Its type:
    BIT  0,(HL)                    ; optional
    INC  HL                        ; (AG_HOPT)
    RET  NZ                        ; owners may lose theirs.
    CALL FW_GET                    ; At the start
    CP   FW_VALUE                  ; a value?
    RET  NZ                        ; If not, nothing lost.
    LD   DE,-FW_STATE              ; The owner's
    ADD  HL,DE                     ; record
    LD   A,DG_LMOVE                ; names it:
    JR   FW_NAME                   ; loop-moves-owner, at the place.

;@ROUTINE CLOBBERS A,BC,DE,HL,CARRY,ZERO,SIGN,PARITY,HALFCARRY
; A statement begins (EM_LINE): no owner is used or moved in it yet.

FW_STMT:                       ; Each symbol in scope:
    LD   A,(RO_BODY)               ; only
    OR   A                         ; in a body.
    RET  Z                         ; (Not.)
    XOR  A                         ; No move, `and`
    LD   (HN_MVLG),A               ; or `or` yet.
    LD   A,(RO_GLOBS)              ; From the routine's first
    LD   C,A                       ; symbol, C,
.NEXT:                         ; to
    LD   A,(SY_CNT)                ; the
    CP   C                         ; last:
    RET  Z                         ; (done)
    LD   A,C                       ; its
    CALL SY_AT                     ; record:
    CALL FW_TRK                    ; a tracked owner's
    JR   NC,.SKIP                  ; (another's byte 7 may be a value's)
    LD   A,(HL)                    ; rule bits
    AND  $F3                       ; are
    LD   (HL),A                    ; cleared.
.SKIP:                         ; Done with it.
    INC  C                         ; The next.
    JR   .NEXT                     ; Until the last.

;@ROUTINE OUT CARRY,HL CLOBBERS A,ZERO,SIGN,PARITY,HALFCARRY
; The path in hand's root, RO_PROOT: carry if it is a tracked owner, HL
; at its state byte.

FW_ROOT:                       ; The path's root.
    LD   HL,(RO_PROOT)             ; Its record:
    JP   FW_TRK                    ; tracked?; return.

;@ROUTINE OUT ZERO CLOBBERS A,DE,HL,CARRY,SIGN,PARITY,HALFCARRY
; Z when the path in hand is its root alone (rootOnly): its type is the
; root symbol's.

FW_ALONE:                      ; The path is parsed.
    LD   HL,(RO_PROOT)             ; The root's
    LD   DE,SY_AGT                 ; type
    ADD  HL,DE                     ; is
    LD   A,(RO_OTYPE)              ; the path's
    CP   (HL)                      ; alone.
    RET                            ; Z if so.

;@ROUTINE CLOBBERS A,DE,HL,CARRY,ZERO,SIGN,PARITY,HALFCARRY
; A path through its root, a tracked owner, at offset FW_PLACE
; (checkUsable: a path's dereference, a select's subject): not maybe moved
; unless optional (use-after-move), nor, beyond the root alone, moved in
; this statement (statement-rule), each naming it, at it.

FW_USE:                        ; The root is RO_PROOT.
    LD   C,0                       ; The root alone may be moved.

;@ROUTINE IN C CLOBBERS A,DE,HL,CARRY,ZERO,SIGN,PARITY,HALFCARRY
; FW_USE, C nonzero for a dereference (suffixes), which is never the root
; alone, so the statement rule always applies. BC is kept.

FW_USEC:                       ; C: a dereference?
    CALL FW_ROOT                   ; Tracked?
    RET  NC                        ; No.
    LD   A,(HL)                    ; Maybe
    AND  3                         ; moved
    CP   FW_MAYBE                  ; and
    JR   NZ,.RULE                  ; not
    DEC  HL                        ; optional:
    BIT  0,(HL)                    ; use-after-move.
    INC  HL                        ; (Optional
    LD   A,DG_MOVED                ; owners
    JR   Z,FW_FAULT                ; may be.)
.RULE:                         ; Moved in this statement?
    BIT  3,(HL)                    ; FW_MOVED:
    RET  Z                         ; no.
    LD   A,DG_SRULE                ; A dereference
    INC  C                         ; always
    DEC  C                         ; breaks
    JR   NZ,FW_FAULT               ; the rule;
    CALL FW_ALONE                  ; the root alone
    RET  Z                         ; is allowed;
    LD   A,DG_SRULE                ; else statement-rule.

;@ROUTINE IN A NORETURN
; Diagnostic A naming the root of the path in hand, at offset FW_PLACE.

FW_FAULT:                      ; A is the diagnostic.
    LD   HL,(RO_PROOT)             ; Its record; fall into FW_NAME.

;@ROUTINE IN A,HL NORETURN
; Diagnostic A naming the symbol whose record is at HL, at FW_PLACE.

FW_NAME:                       ; HL is the record.
    CALL DG_SETN                   ; It is named,
    LD   HL,(FW_PLACE)             ; at
    JP   DG_HERE                   ; the place.

;@ROUTINE CLOBBERS A,DE,HL,CARRY,ZERO,SIGN,PARITY,HALFCARRY
; The path in hand's root, a tracked owner, is used directly in this
; statement (noteDirect): statement-rule if it is moved in it.

FW_SEEN:                     ; The root is RO_PROOT.
    CALL FW_ROOT                   ; Tracked?
    RET  NC                        ; No.
    BIT  3,(HL)                    ; Moved?
    LD   A,DG_SRULE                ; Then
    JR   NZ,FW_FAULT               ; statement-rule.
    SET  2,(HL)                    ; Used.
    RET                            ; Done.

;@ROUTINE CLOBBERS A,BC,DE,HL,CARRY,ZERO,SIGN,PARITY,HALFCARRY
; The path in hand's root, a tracked owner, is moved in this statement
; (noteMove), at offset FW_PLACE: not while leased (not-writable), nor
; if used directly in it (statement-rule).

FW_MOVE:                       ; The root is RO_PROOT.
    CALL FW_ROOT                   ; Tracked?
    RET  NC                        ; No.
    PUSH HL                        ; (kept)
    CALL HN_LEASD                  ; Leased?
    POP  HL                        ; Then
    LD   A,DG_CONST                ; not-writable.
    JR   C,FW_FAULT                ; (No return.)
    BIT  2,(HL)                    ; Used?
    LD   A,DG_SRULE                ; Then
    JR   NZ,FW_FAULT               ; statement-rule.
    SET  3,(HL)                    ; Moved.
    RET                            ; Done.

;@ROUTINE IN A CLOBBERS A,DE,HL,CARRY,ZERO,SIGN,PARITY,HALFCARRY
; The path in hand, its root alone and a tracked owner, now holds state A
; (FW_NONE, FW_VALUE or FW_MAYBE).

FW_SET:                        ; A is the state.
    PUSH AF                        ; Kept.
    CALL FW_ALONE                  ; The root alone,
    JR   NZ,.KEPT                  ; and
    CALL FW_ROOT                   ; tracked?
    JR   NC,.KEPT                  ; No.
    POP  AF                        ; The state
    LD   D,A                       ; replaces
    LD   A,(HL)                    ; its
    AND  $FC                       ; own.
    OR   D                         ; Kept.
    LD   (HL),A                    ; Done.
    RET                            ; Back.
.KEPT:                         ; Not tracked.
    POP  AF                        ; (dropped)
    RET                            ; Back.
