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
;    DG_AT     the same at the offset in the word at HL
;    DG_HERE   the same at the offset HL
;    DG_NAMED  DG_ISSUE with argument 1 the current name's spelling
;    DG_RAISE  DG_ISSUE with the code in the byte after the CALL
;    DG_RNAME  DG_NAMED with the code in the byte after the CALL
;    DG_SETN   make argument 1 the name of a name record
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
;  current token's offset in DG_POS, then reloads SP from PR_SP and returns
;  carry set; the shell counts the line and column from the offset. A
;  diagnostic therefore unwinds every nested parse at once, back to
;  PR_BUILD's caller. No routine returns
;  failure to its caller, so the carry outputs in the contracts of the
;  parsing routines are always clear when they return.
;
;  Lookahead. PR_LKIND holds the kind of a token read by PR_PEEK and not
;  yet taken, or $FF when the cell is empty; PR_LVAL holds its BC payload.
;  The tokenizer's position and spelling fields (TK_POS, TK_PTR, TK_LEN)
;  stay those of the most recently read token until the next TK_NEXT, so
;  one buffered kind and word are enough for names, numbers and positions.
;
;  A diagnostic's code is the reference compiler's number for it, or one
;  of the families MESSAGE.ASM maps (DG_ in STATE.ASM): DG_TOKEN ($80)
;  plus a token kind reports that token as expected.

;@ROUTINE IN A NORETURN
; DG_ISSUE, with argument 1 the current name's spelling (TK_PTR, TK_LEN),
; cut to DG_ALEN-1 bytes, for a message such as "^1 is not declared".
; SY_UNDEF, the last line of SYMBOLS.ASM, falls into it, so the include
; order in BASIE.ASM must keep this file next.

DG_NAMED:
    LD   HL,TK_PTR                 ; The current name's record: its spelling and
    CALL DG_SETN                   ; length; argument 1 is it. Fall into DG_ISSUE.

;@ROUTINE IN A NORETURN
; Record diagnostic A at the current token and abandon the build: SP is
; reloaded from PR_SP and the RET leaves PR_BUILD with carry set.

DG_ISSUE:
    LD   HL,TK_POS                 ; The current token's offset, line and column.

;@ROUTINE IN A,HL NORETURN
; Record diagnostic A at the position whose offset is the word at HL (a
; position record's first word), in the current part, and abandon the
; build as DG_ISSUE does.

DG_AT:
    LD   E,(HL)                    ; The offset's low byte,
    INC  HL                        ; then
    LD   D,(HL)                    ; its high byte.
    EX   DE,HL                     ; HL is the offset; fall into DG_HERE.

;@ROUTINE IN A,HL NORETURN
; Record diagnostic A at offset HL of the current part and abandon the
; build. The shell counts the line and column from the offset.

DG_HERE:
    LD   E,A                       ; E is the code,
    LD   A,(SRC_ID)                ; D the 1-based id
    LD   D,A                       ; of the part being read.

;@ROUTINE IN D,E,HL NORETURN
; Record diagnostic E at offset HL of part D and abandon the build: SP is
; reloaded from PR_SP and the RET leaves PR_BUILD with carry set.

DG_PLACE:
    LD   (DG_POS),HL               ; Where it is,
    LD   (DG_CODE),DE              ; its code and, after it, DG_PART.
    LD   SP,(PR_SP)                ; Discard every frame above PR_BUILD's.
    SCF                            ; Carry reports the failure.
    RET                            ; Return from PR_BUILD.

;@ROUTINE NORETURN
; Raise the diagnostic whose code is the byte after the CALL: `CALL DG_RAISE`
; then `DB code` costs four bytes at each failure site.

DG_RAISE:
    POP  HL                        ; The return address points at the inline code.
    LD   A,(HL)                    ; Fetch the diagnostic's code.
    JR   DG_ISSUE                  ; Record it and abandon the build.

;@ROUTINE IN A NORETURN
; Record diagnostic A at the offset kept in AC_SPOS (a name statement's,
; a select label's or an assert's first token) and abandon the build.

DG_KEPT:                       ; A is the diagnostic.
    LD   HL,(AC_SPOS)              ; The kept offset.
    JR   DG_HERE                   ; Record it there.

;@ROUTINE NORETURN
; DG_RAISE for a message that names the current name (DG_NAMED).

DG_RNAME:
    POP  HL                        ; The return address points at the inline code.
    LD   A,(HL)                    ; Fetch the diagnostic's code.
    JR   DG_NAMED                  ; Name it, record it and abandon the build.

;@ROUTINE IN A,HL CLOBBERS BC,DE,HL,CARRY,ZERO,SIGN,PARITY,HALFCARRY
; Make argument 1 the name at offset HL of the current part, its letters,
; digits and underscores, through TK_PTR and TK_LEN (DG_SETN); with none
; there it stays zero. A is kept.

DG_WORD:
    PUSH AF                        ; Keep the code.
    EX   DE,HL                     ; DE is the offset.
    LD   HL,(SRC_PTR)              ; The next byte's address
    LD   BC,(SRC_POS)              ; less its offset
    OR   A                         ; is the
    SBC  HL,BC                     ; part's start,
    ADD  HL,DE                     ; and the name is at the offset.
    LD   (TK_PTR),HL               ; It becomes the current name,
    LD   B,0                       ; of B bytes:
.LENGTH:                       ; HL is the next byte.
    LD   A,(HL)                    ; Does it
    CALL TK_ALNUM                  ; continue a name?
    JR   NC,.ENDED                 ; No.
    INC  HL                        ; Yes: one
    INC  B                         ; more.
    JR   .LENGTH                   ; Go on.
.ENDED:                        ; B is the name's length.
    LD   A,B                       ; It is
    LD   (TK_LEN),A                ; the current name's.
    POP  AF                        ; The code.
    INC  B                         ; Is there
    DEC  B                         ; a name?
    RET  Z                         ; No: no argument.
    LD   HL,TK_PTR                 ; Yes: it is argument 1;
                                   ; fall into DG_SETN.

;@ROUTINE IN HL CLOBBERS BC,DE,HL
; Make argument 1 the name of the record at HL, a spelling's address and
; its length (a symbol's, a routine's, TK_PTR and TK_LEN), copied to
; DG_ABUF, cut to DG_ALEN-1 bytes and zero-terminated. A and the flags
; are kept.

DG_SETN:
    PUSH AF                        ; Keep the code.
    LD   E,(HL)                    ; DE is
    INC  HL                        ; the
    LD   D,(HL)                    ; spelling,
    INC  HL                        ; A its
    LD   A,(HL)                    ; length,
    CP   DG_ALEN                   ; if it fits the buffer
    JR   C,.FITS                   ; with its terminator;
    LD   A,DG_ALEN-1               ; else as much as does.
.FITS:                         ; A is the bytes to copy, at least one.
    LD   B,A                       ; Count them in B.
    EX   DE,HL                     ; HL walks the spelling.
    LD   DE,DG_ABUF                ; Its copy is argument 1.
    LD   (DG_ARG1),DE              ; Point argument 1 at it.
.COPY:                         ; B bytes remain.
    LD   A,(HL)                    ; The next byte
    LD   (DE),A                    ; is copied.
    INC  HL                        ; Move
    INC  DE                        ; on.
    DJNZ .COPY                     ; Until the name is copied.
    XOR  A                         ; Terminate
    LD   (DE),A                    ; the copy.
    POP  AF                        ; The code again.
    RET                            ; Argument 1 is set.

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
    JP   DG_ISSUE                  ; Abandon the build.

;@ROUTINE OUT A,BC,HL,CARRY,ZERO CLOBBERS SIGN,PARITY,HALFCARRY,DE
; Peek at the next token (PR_PEEK) and return in HL the offset where it
; starts, where a diagnostic about what it begins is reported.

PR_SPOT:                       ; The next token is wanted, and its place.
    CALL PR_PEEK                   ; Its kind and payload;
    LD   HL,(TK_POS)               ; its offset.
    RET                            ; Done.

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
    RET                            ; Return it, with TK_NEXT's flags.
.BUFFERED:                     ; A holds the buffered kind.
    LD   BC,(PR_LVAL)              ; Return the buffered payload.
    OR   A                         ; Clear carry; Z reports TK_EOF.
    RET                            ; Leave the token buffered.

;@ROUTINE OUT A,BC,CARRY,ZERO CLOBBERS SIGN,PARITY,HALFCARRY,DE,HL
; Consume the next token: return its kind in A (Z for TK_EOF) and payload
; in BC, and empty the lookahead cell.

PR_TAKE:
    CALL PR_PEEK                   ; Fetch the token, buffered or fresh.
    LD   HL,PR_LKIND               ; Mark the lookahead cell
    LD   (HL),$FF                  ; empty: the token is consumed.
    RET                            ; A, BC and the flags are PR_PEEK's.

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
    JP   DG_ISSUE                  ; Abandon the build.

;@ROUTINE OUT A,CARRY,ZERO CLOBBERS SIGN,PARITY,HALFCARRY,B,HL
; Clear the state one compilation accumulates: the diagnostic, the
; lookahead, the symbol table, the forward flag, the aggregate counters,
; the next ordinal (the program's base, $0400) and the largest frame.
; Returns A zero.

PR_RESET:
    XOR  A                         ; Zero for every cleared field.
    LD   H,A                       ; HL is zero
    LD   L,A                       ; for the word fields.
    LD   (DG_CODE),HL              ; No diagnostic yet, and no failing part (DG_PART).
    LD   (RG_LARGE),HL             ; No frame yet: the largest is zero.
    LD   (SY_BODY),HL              ; No body is open,
    LD   HL,SY_BASE                ; and no symbols:
    LD   (SY_TOP),HL               ; the first record is provisional.
    LD   (RG_FWD),A                ; No forward routines.
    LD   (EX_PRIME),A              ; No primary parsed ahead.
    LD   HL,AG_DCNT                ; The aggregate counters, AG_DCNT..AG_OPENF.
    LD   B,AG_OPENF-AG_DCNT+1      ; Their byte count.
.LOOP:                         ; Clear one aggregate counter.
    LD   (HL),A                    ; Zero it.
    INC  HL                        ; Step to the next.
    DJNZ .LOOP                     ; Until all are clear.
    LD   HL,$0400                  ; The first blob takes the
    LD   (RG_ORD),HL               ; program's ordinal base, $0400.
    DEC  A                         ; The empty-lookahead marker, $FF:
    LD   (PR_LKIND),A              ; no token is buffered.
    XOR  A                         ; Return A zero.
    RET                            ; The compilation starts clean.
