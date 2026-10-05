;==========================================================================
;  Parser driver: diagnostics, lookahead and token expectations
;==========================================================================
;
;  The helpers every parsing module shares. The LL(1) engine (LL1.ASM)
;  drives the parse; the expression, control, aggregate and routine
;  parsers and the grammar actions read tokens through PR_PEEK and
;  PR_TAKE, insist on tokens through PR_NEED and report errors through
;  DG_ISSUE.
;
;  Principal entries:
;    DG_ISSUE  record diagnostic A at the current token and abandon the build
;    DG_RAISE  DG_ISSUE with the code in the byte after the CALL
;    PR_COPY   copy a six-byte offset/line/column position
;    PR_PEEK   return the next token without consuming it
;    PR_TAKE   consume and return the next token
;    PR_NEED   consume the next token, which must be of kind E
;    PR_LEFT, PR_RIGHT, PR_EQUAL  PR_NEED for "(", ")" and "="
;    PR_ETERM  raise DG_VALUE, a missing or malformed value
;    PR_RESET  clear the parse state before a compilation
;
;  Failure. PR_BUILD (ROUTINES.ASM) saves SP in PR_SP before parsing.
;  DG_ISSUE stores the code in DG_CODE, the source part in DG_PART and the
;  current token's position in DG_POS, DG_LINE and DG_COL, then reloads SP
;  from PR_SP and returns carry set. A diagnostic therefore unwinds every
;  nested parse at once, back to PR_BUILD's caller. No routine returns
;  failure to its caller, so the carry outputs in the contracts of the
;  parsing routines are always clear when they return.
;
;  Lookahead. PR_LKIND holds the kind of a token read by PR_PEEK and not
;  yet taken, or $FF when the cell is empty; PR_LVAL holds its BC payload.
;  The tokenizer's position and spelling fields (TK_POS, TK_PTR, TK_LEN)
;  stay those of the most recently read token until the next TK_NEXT, so
;  one buffered kind and word are enough for names, numbers and positions.
;
;  A diagnostic code below $80 is a numbered error (DG_ in STATE.ASM).
;  DG_TOKEN ($80) plus a token kind reports that token as expected.

;@ROUTINE NORETURN
; Record diagnostic A at the current token and abandon the build: SP is
; reloaded from PR_SP and the RET leaves PR_BUILD with carry set.

DG_ISSUE:
    LD   (DG_CODE),A               ; Record the diagnostic number.
    LD   A,(SRC_ID)                ; Fetch the 1-based id of the part being read.
    LD   (DG_PART),A               ; Record it for the shell's NAME prefix.
    LD   HL,TK_POS                 ; Source: the current token's offset, line, column.
    LD   DE,DG_POS                 ; Destination: the diagnostic's position fields.
    PUSH BC                        ; BC survives the copy; no caller now reads it.
    CALL PR_COPY                   ; Record the token's position.
    POP  BC                        ; Restore BC.
    LD   SP,(PR_SP)                ; Discard every frame above PR_BUILD's.
    SCF                            ; Carry reports the failure.
    RET                            ; Return from PR_BUILD.

;@ROUTINE NORETURN
; Raise the diagnostic whose code is the byte after the CALL: `CALL DG_RAISE`
; then `DB code` costs four bytes at each failure site.

DG_RAISE:
    POP  HL                        ; The return address points at the inline code.
    LD   A,(HL)                    ; Fetch the diagnostic number.
    JR   DG_ISSUE                  ; Record it and abandon the build.

;@ROUTINE IN DE,HL OUT BC,DE,HL CLOBBERS PARITY,HALFCARRY
; Copy one six-byte offset/line/column record from HL to DE. LDIR leaves
; carry alone, so a caller can set the failure flag before the copy.

PR_COPY:
    LD   BC,6                      ; Offset, line and column: three words.
    LDIR                           ; Copy them; HL and DE end past the records.
    RET                            ; BC returns zero.

;@ROUTINE IN E OUT A,BC,CARRY,ZERO CLOBBERS SIGN,PARITY,HALFCARRY,HL
; Consume the next token, which must be of kind E. A returns the kind and
; BC its payload, with Z set. Any other kind raises DG_TOKEN+E, naming the
; token that was expected.

PR_NEED:
    PUSH DE                        ; PR_TAKE clobbers DE; keep the expected kind.
    CALL PR_TAKE                   ; A is the next token's kind, now consumed.
    POP  DE                        ; Recover the expected kind in E.
    CP   E                         ; Is it the kind the grammar requires?
    RET  Z                         ; Yes: return the kind and payload.
    LD   A,E                       ; No: report the expected kind...
    OR   DG_TOKEN                  ; ...as a token diagnostic.
    JR   DG_ISSUE                  ; Abandon the build.

;@ROUTINE OUT A,BC,CARRY,ZERO CLOBBERS SIGN,PARITY,HALFCARRY,DE,HL
; Return the next token's kind in A and payload in BC without consuming it.
; The first peek reads the token and buffers it; later peeks and the next
; PR_TAKE return the buffered copy.

PR_PEEK:
    LD   A,(PR_LKIND)              ; Is a token already buffered?
    CP   $FF                       ; $FF marks the lookahead cell empty.
    JR   NZ,.BUFFERED              ; Return the buffered token.
    CALL TK_NEXT                   ; Read a token: kind in A, payload in BC.
    LD   (PR_LKIND),A              ; Buffer its kind...
    LD   (PR_LVAL),BC              ; ...and its payload.
    LD   A,(PR_LKIND)              ; Reload the kind (A already holds it).
    RET                            ; Return the new lookahead.
.BUFFERED:                     ; A holds the buffered kind.
    LD   BC,(PR_LVAL)              ; Return the buffered payload.
    LD   A,(PR_LKIND)              ; And its kind.
    OR   A                         ; Clear carry; Z reports TK_EOF.
    RET                            ; Leave the token buffered.

;@ROUTINE OUT A,BC,CARRY,ZERO CLOBBERS SIGN,PARITY,HALFCARRY,DE,HL
; Consume the next token: return its kind in A (Z for TK_EOF) and payload
; in BC, and empty the lookahead cell.

PR_TAKE:
    CALL PR_PEEK                   ; Fetch the token, buffered or fresh.
    LD   D,A                       ; Keep its kind.
    LD   A,$FF                     ; Mark the lookahead cell empty.
    LD   (PR_LKIND),A              ; The token is now consumed.
    LD   A,D                       ; Return its kind.
    OR   A                         ; Clear carry; Z reports TK_EOF.
    RET                            ; BC still holds the payload.

; Frequent token checks share the PR_NEED tail. Each wrapper is four bytes,
; and each use saves two over an inline `LD E,kind` and `CALL PR_NEED`.

;@ROUTINE OUT A,CARRY,ZERO CLOBBERS SIGN,PARITY,HALFCARRY,BC,E,HL
; Require "(".

PR_LEFT:
    LD   E,TK_LPAR                 ; The expected kind.
    JR   PR_NEED                   ; Consume and check it.

;@ROUTINE OUT A,CARRY,ZERO CLOBBERS SIGN,PARITY,HALFCARRY,BC,E,HL
; Require ")".

PR_RIGHT:
    LD   E,TK_RPAR                 ; The expected kind.
    JR   PR_NEED                   ; Consume and check it.

;@ROUTINE OUT A,CARRY,ZERO CLOBBERS SIGN,PARITY,HALFCARRY,BC,E,HL
; Require "=".

PR_EQUAL:
    LD   E,TK_EQ                   ; The expected kind.
    JR   PR_NEED                   ; Consume and check it.

;@ROUTINE NORETURN
; Raise DG_VALUE: a value was required here.

PR_ETERM:
    LD   A,DG_VALUE                ; The missing-value diagnostic.
    JR   DG_ISSUE                  ; Abandon the build.

;@ROUTINE OUT A,CARRY,ZERO CLOBBERS SIGN,PARITY,HALFCARRY,B,HL
; Clear the state one compilation accumulates: the diagnostic, the
; lookahead, the symbol table, the forward flag, the aggregate counters,
; the next ordinal (the program's base, $0400) and the largest frame.
; Returns A zero.

PR_RESET:
    XOR  A                         ; Zero for every cleared field.
    LD   (DG_CODE),A               ; No diagnostic yet.
    LD   (DG_PART),A               ; And no failing part.
    LD   (SY_CNT),A                ; No symbols.
    LD   (RG_FWD),A                ; No forward routines.
    LD   HL,AG_MODE                ; The aggregate counters, AG_MODE..AG_GIVEN.
    LD   B,AG_GIVEN-AG_MODE+1      ; Their byte count.
.LOOP:                         ; Clear one aggregate counter.
    LD   (HL),A                    ; Zero it.
    INC  HL                        ; Step to the next.
    DJNZ .LOOP                     ; Until all are clear.
    LD   H,A                       ; No frame yet:
    LD   L,A                       ; the largest
    LD   (RG_LARGE),HL             ; is zero.
    LD   H,$04                     ; The first blob takes the
    LD   (RG_ORD),HL               ; program's ordinal base, $0400.
    DEC  A                         ; The empty-lookahead marker, $FF:
    LD   (PR_LKIND),A              ; no token is buffered.
    XOR  A                         ; Return A zero.
    RET                            ; The compilation starts clean.
