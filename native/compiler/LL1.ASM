;==========================================================================
;  LL(1) engine
;==========================================================================
;
;  A table-driven predictive parser. A stack of grammar symbols starts as
;  the start symbol; the engine pops one symbol at a time until the stack
;  is empty, by which point the whole program has been read and its blobs
;  written. The tables are in GRAMMAR.ASM; the actions
;  they name are in ACTIONS.ASM.
;
;  Principal entry:
;    LL_PARSE  parse the whole program from the start symbol
;
;  A grammar symbol is one byte:
;    $00..$3F  a terminal: the token kind that must come next (TK_)
;    $40..$7F  a nonterminal: prediction row (symbol - $40) of GR_ROWX
;    $80..$FE  an action: entry (symbol - $80) of GR_ACTX
;
;  A terminal is consumed with PR_NEED, which raises DG_TOKEN+kind on a
;  mismatch. A nonterminal peeks at the next token and searches its row
;  for the production that token predicts; if none does, the row's own
;  diagnostic is raised. The chosen production's right side is pushed in
;  one copy: bodies are stored reversed, so the copy leaves the leftmost
;  symbol on top. An action is called with its ordinal in A; it consumes
;  any tokens it needs, generates code or records what it has parsed and
;  returns, or raises a diagnostic, which abandons the build (PARSER.ASM).
;
;  Workspace: LL_DEPTH, a byte counting the symbols on the stack, then
;  LL_STACK, LL_CAP bytes with the top of stack at LL_STACK+LL_DEPTH-1,
;  after PR_SP (CALLWORK.ASM). LL_WEND marks the end of the whole compiler
;  workspace for the build's boundary check.

LL_CAP EQU  64                 ; Grammar stack capacity in symbols.
LL_DEPTH EQU  PR_SP+2          ; Symbols on the stack (byte).
LL_STACK EQU  LL_DEPTH+1       ; The stack; LL_STACK+0 is the bottom.
LL_WEND EQU  LL_STACK+LL_CAP   ; End of compiler workspace (marker).

;@ROUTINE OUT A,BC,DE,HL,CARRY,ZERO CLOBBERS SIGN,PARITY,HALFCARRY,IX,IY
; Parse the program: push GR_START and expand, match and act until the
; stack is empty. Returns A zero with Z set and carry clear; every error
; leaves through DG_ISSUE instead.

LL_PARSE:
    LD   H,GR_START                ; The compilation unit
    LD   L,1                       ; is the one symbol:
    LD   (LL_DEPTH),HL             ; the depth, then LL_STACK's bottom.
.LOOP:                         ; Pop and process one symbol.
    LD   A,(LL_DEPTH)              ; How many symbols remain?
    OR   A                         ; An empty stack means the program is complete.
    RET  Z                         ; Return with A zero, Z set and carry clear.
    DEC  A                         ; The top symbol is at depth minus one.
    LD   (LL_DEPTH),A              ; Remove it from the count.
    LD   L,A                       ; Form its slot...
    LD   H,0                       ; ...from the new depth...
    LD   DE,LL_STACK               ; ...plus the stack base.
    ADD  HL,DE                     ; HL addresses the symbol.
    LD   A,(HL)                    ; A is the symbol on top, now removed.
    CP   $40                       ; Below $40 is a terminal.
    JR   C,.TERMINAL               ; Consume the token it names.
    CP   $80                       ; $40..$7F is a nonterminal.
    JR   C,.NONTERM                ; Predict and push one of its productions.

; An action. Call it through GR_ACTX with its zero-based ordinal in A, so
; one routine can serve a family of actions (AC_TYPE, AC_GOTO, AC_FORTO).

    SUB  $80                       ; A is the action ordinal.
    LD   L,A                       ; Index the directory...
    LD   H,0                       ; ...as a word offset.
    ADD  HL,HL                     ; Two bytes per routine address.
    LD   DE,GR_ACTX                ; The action directory.
    ADD  HL,DE                     ; HL addresses this action's entry.
    LD   E,(HL)                    ; Fetch the routine address...
    INC  HL                        ; ...low byte first...
    LD   D,(HL)                    ; ...then the high byte.
    EX   DE,HL                     ; HL is the action routine.
    CALL .RUN                      ; Run it with A still the ordinal.
    JR   .LOOP                     ; Process the next symbol.
.RUN:                          ; HL is the action routine.
    JP   (HL)                      ; Its RET returns to the loop.

.TERMINAL:                     ; A is the token kind the grammar requires.
    LD   E,A                       ; PR_NEED expects it in E.
    CALL PR_NEED                   ; Consume it or raise DG_TOKEN+kind.
    JR   .LOOP                     ; Process the next symbol.

; A nonterminal. Its GR_ROWX entry is the row's offset from GR_ROWS and
; the diagnostic for a token the row does not predict. A row is a list of
; alternatives, each a production byte and then the token kinds that
; select it; bit 7 marks the last token of an alternative and, on the
; production byte, the last alternative of the row.

.NONTERM:                      ; A is $40 plus the row number.
    CP   GR_STMT                   ; A statement, a local's declaration
    CALL Z,EM_LINE                 ; included, starts on the lookahead's line.
    SUB  $40                       ; A is the row number.
    LD   L,A                       ; Index the row directory...
    LD   H,0                       ; ...as a word offset.
    ADD  HL,HL                     ; Two bytes per row.
    LD   DE,GR_ROWX                ; The row directory.
    ADD  HL,DE                     ; HL addresses this row's entry.
    LD   E,(HL)                    ; E is the row's offset from GR_ROWS.
    INC  HL                        ; Step to the row's diagnostic.
    LD   A,(HL)                    ; Fetch it.
    PUSH AF                        ; Keep it until a production is chosen.
    LD   D,0                       ; Widen the offset.
    LD   HL,GR_ROWS                ; The rows' common base.
    ADD  HL,DE                     ; HL addresses the row's first alternative.
    PUSH HL                        ; PR_PEEK clobbers HL.
    CALL PR_PEEK                   ; A is the lookahead token's kind.
    POP  HL                        ; Recover the row pointer.
    LD   C,A                       ; C is the kind to look for.
.NEXTALT:                      ; HL addresses an alternative's production byte.
    LD   B,(HL)                    ; B is the production, bit 7 if it is the last alternative.
    INC  HL                        ; Step to its first predicting token.
.TOKEN:                        ; Test one predicting token.
    LD   A,(HL)                    ; Fetch it with its end-of-list bit.
    LD   E,A                       ; Keep the end-of-list bit.
    AND  $7F                       ; Strip it to a token kind.
    CP   C                         ; Does this token predict the production?
    JR   Z,.MATCH                  ; Yes: expand it.
    INC  HL                        ; No: step past it.
    BIT  7,E                       ; Was it the alternative's last token?
    JR   Z,.TOKEN                  ; No: test the next one.
    BIT  7,B                       ; Was this the row's last alternative?
    JR   NZ,.NOMATCH               ; Yes: nothing predicts the lookahead.
    JR   .NEXTALT                  ; No: try the next alternative.
.NOMATCH:                      ; No production fits the lookahead.
    POP  AF                        ; A is the row's diagnostic.
    LD   B,A                       ; Keep it.
    LD   A,C                       ; An include here
    CP   TK_INCL                   ; follows a declaration
    LD   A,B                       ; (include-position: the loader
    JR   NZ,.REPORT                ; read those before any).
    LD   A,DG_LATE                 ; Report it.
.REPORT:                       ; A is the diagnostic.
    JP   DG_ISSUE                  ; Report it at the lookahead token.
.MATCH:                        ; B selects the production.
    POP  AF                        ; Discard the row's diagnostic.
    LD   A,B                       ; Fetch the production byte.
    AND  $7F                       ; Strip the last-alternative bit.
    CALL .EXPAND                   ; Push its right side.
    JR   .LOOP                     ; Process the symbol now on top.

;@ROUTINE IN A OUT A,BC,DE,HL,CARRY,ZERO CLOBBERS SIGN,PARITY,HALFCARRY
; Push the right side of production A. Its body lies between two adjacent
; directory offsets. Productions below GR_SPLIT use GR_ALTX and GR_ALTS,
; the rest GR_ALTXH and GR_ALTHI, which keeps every offset within a byte.
; An empty body pushes nothing. Overflow raises DG_LLCAP.

.EXPAND:
    CP   GR_SPLIT                  ; Is the production in the low half?
    LD   DE,GR_ALTS                ; Low half: bodies from GR_ALTS...
    LD   HL,GR_ALTX                ; ...located by GR_ALTX.
    JR   C,.LOCATED                ; Keep them for a low production.
    SUB  GR_SPLIT                  ; High half: renumber from zero.
    LD   DE,GR_ALTHI               ; Bodies from GR_ALTHI...
    LD   HL,GR_ALTXH               ; ...located by GR_ALTXH.
.LOCATED:                      ; DE is the body base, HL the directory.
    LD   C,A                       ; Index the directory...
    LD   B,0                       ; ...one byte per production.
    ADD  HL,BC                     ; HL addresses the production's offset.
    LD   C,(HL)                    ; C is the start of its body.
    INC  HL                        ; The next entry is the end of the body.
    LD   A,(HL)                    ; Fetch that end offset.
    SUB  C                         ; A is the body's length.
    LD   B,A                       ; Keep the length in B.
    LD   L,C                       ; Form the body's address from its start offset...
    LD   H,0                       ; ...widened...
    ADD  HL,DE                     ; ...plus the base.
    LD   A,B                       ; Is the body empty?
    OR   A                         ; Zero length derives the empty string.
    RET  Z                         ; Push nothing.
    LD   A,(LL_DEPTH)              ; Fetch the current depth.
    LD   C,A                       ; Keep it as the copy's starting slot.
    ADD  A,B                       ; A is the depth after the push.
    JR   C,.FULL                   ; Past 255 symbols the stack is certainly full.
    CP   LL_CAP+1                  ; More than LL_CAP symbols?
    JR   NC,.FULL                  ; Raise DG_LLCAP.
    LD   (LL_DEPTH),A              ; Commit the new depth.
    PUSH HL                        ; Keep the body's address.
    LD   E,C                       ; Form the first free slot from the old depth...
    LD   D,0                       ; ...widened...
    LD   HL,LL_STACK               ; ...plus the stack base.
    ADD  HL,DE                     ; HL is the first free slot.
    EX   DE,HL                     ; DE is the copy destination.
    POP  HL                        ; HL is the body.
    LD   C,B                       ; Copy the body's length...
    LD   B,0                       ; ...as a word count.
    LDIR                           ; Push the reversed body; its leftmost symbol lands on top.
    XOR  A                         ; Report success with carry clear.
    RET                            ; The stack holds the right side.

.FULL:                         ; The grammar stack cannot take the push.
    CALL DG_RAISE                  ; Abandon the build.
    DB   DG_LLCAP                  ; Grammar stack overflow.

LL_CEND:                       ; End of the LL(1) engine's code (marker).
