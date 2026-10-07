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
;  after PR_SP (CALLWORK.ASM). LL_STACK starts the first page after PR_SP,
;  so a slot's address is the page and the depth. LL_WEND marks the end of
;  the whole compiler workspace for the build's boundary check.

; The FLOAT overlay's workspace, after the pools' bytes and below the
; stack's page, resident so that it takes no records of the overlay area.
FL_NB EQU  64                  ; Bytes of FL_N and FL_D.
FL_WBEG EQU  PL_WEND           ; The workspace's start.
FL_N EQU  FL_WBEG              ; N, the dividend, FL_NB bytes.
FL_D EQU  FL_N+FL_NB           ; D, the divisor, FL_NB bytes.
FL_Q EQU  FL_D+FL_NB           ; q, the quotient, then the f32's bits: 5 bytes.
FL_E EQU  FL_Q+5               ; E, q's lowest bit's exponent: a word.
FL_SIGN EQU  FL_E+2            ; The result's sign, bit 7.
FL_LOST EQU  FL_SIGN+1         ; Nonzero when bits were lost in rounding.
FL_MODE EQU  FL_LOST+1         ; Nonzero for a literal's rounding.
FL_TEN EQU  FL_MODE+1          ; A literal's power of ten: a word.
FL_SIG EQU  FL_TEN+2           ; Its significant digits: a word.
FL_A EQU  FL_SIG+2             ; a unpacked: sign, exponent, significand.
FL_B EQU  FL_A+5               ; b unpacked.
FL_ZRUN EQU  FL_B+5            ; Zeros pending after a significant digit: a word.
FL_WEND EQU  FL_ZRUN+2         ; The workspace's end.
LL_CAP EQU  254                ; Grammar stack capacity in symbols.
LL_STACK EQU  (FL_WEND+$100)&$FF00 ; The stack, from a page's start past FLOAT's bytes.
LL_DEPTH EQU  LL_STACK-1       ; Symbols on the stack (byte), just below it.
; The select statements' labels follow the stack (ACTSEL.ASM): CT_RTOP,
; the next free entry, then CT_RCAP ranges of eight bytes, the low and the
; high value of a label at the subject's type, its sign bit flipped.
CT_RTOP EQU  LL_STACK+LL_CAP   ; Word: the next free label range.
CT_RTAB EQU  CT_RTOP+2         ; The label ranges of the open selects.
CT_RCAP EQU  63                ; Ranges; DG_LABEL beyond.
CT_RLIM EQU  CT_RTAB+8*CT_RCAP ; Exclusive end of the ranges.
PL_DESC EQU  CT_RLIM           ; AG_TCAP words: a type's owner descriptor, 0 until written.
LL_WEND EQU  PL_DESC+2*AG_TCAP ; End of compiler workspace (marker).

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
    LD   HL,.LOOP                  ; Each symbol's work
    PUSH HL                        ; returns to the loop.
    DEC  A                         ; The top symbol is at depth minus one.
    LD   (LL_DEPTH),A              ; Remove it from the count.
    LD   L,A                       ; Its slot is the new depth
    LD   H,HIGH(LL_STACK)          ; in the stack's page.
    LD   A,(HL)                    ; A is the symbol on top, now removed.
    CP   $40                       ; Below $40 is a terminal.
    JR   C,.TERMINAL               ; Consume the token it names.
    CP   $80                       ; $40..$7F is a nonterminal.
    JR   C,.NONTERM                ; Predict and push one of its productions.

; An action. Call it through GR_ACTX with its zero-based ordinal in A, so
; one routine can serve a family of actions (AC_TYPE, AC_GOTO, AC_FORTO).

    SUB  $80                       ; A is the action ordinal.
    LD   DE,GR_ACTX                ; The action directory's
    CALL .ENTRY                    ; entry A is the routine's address.
    EX   DE,HL                     ; HL is the action routine.
    JP   (HL)                      ; Run it with A the ordinal; its RET loops.

;@ROUTINE IN A,DE OUT DE CLOBBERS HL,CARRY
; DE becomes word A of the table at DE. A is kept.

.ENTRY:                        ; A is the index, DE the table.
    LD   L,A                       ; Index the table
    LD   H,0                       ; as a word offset:
    ADD  HL,HL                     ; two bytes an entry.
    ADD  HL,DE                     ; HL addresses entry A.
    LD   E,(HL)                    ; Fetch it,
    INC  HL                        ; low byte first,
    LD   D,(HL)                    ; then the high byte.
    RET                            ; DE is the entry.

.TERMINAL:                     ; A is the token kind the grammar requires.
    LD   E,A                       ; PR_NEED expects it in E,
    JP   PR_NEED                   ; consumes it or raises DG_TOKEN+kind, and loops.

; A nonterminal. Its GR_ROWX entry is the row's offset from GR_ROWS, or
; from GR_ROWS+256 for a row from GR_RHIGH on, and the diagnostic for a
; token the row does not predict. A row is a list of
; alternatives, each a production byte and then the token kinds that
; select it; bit 7 marks the last token of an alternative and, on the
; production byte, the last alternative of the row.

.NONTERM:                      ; A is $40 plus the row number.
    CP   GR_STMT                   ; A statement, a local's declaration
    CALL Z,EM_LINE                 ; included, starts on the lookahead's line.
    SUB  $40                       ; A is the row number.
    LD   DE,GR_ROWX                ; The row directory's entry: E is the row's
    CALL .ENTRY                    ; offset from GR_ROWS, D its diagnostic,
    PUSH DE                        ; kept until a production is chosen.
    LD   D,0                       ; Widen the offset: a row
    CP   GR_RHIGH                  ; from GR_RHIGH on (A is kept)
    JR   C,.LOW                    ; counts from the page
    INC  D                         ; after GR_ROWS.
.LOW:                          ; DE is the row's offset.
    LD   HL,GR_ROWS                ; The rows' common base.
    ADD  HL,DE                     ; HL addresses the row's first alternative.
    PUSH HL                        ; PR_PEEK clobbers HL.
    CALL PR_PEEK                   ; A is the lookahead token's kind.
    POP  HL                        ; Recover the row pointer.
    LD   C,A                       ; C is the kind to look for, below $40.
.NEXTALT:                      ; HL addresses an alternative's production byte.
    LD   B,(HL)                    ; B is the production, bit 7 if it is the last alternative.
    INC  HL                        ; Step to its first predicting token.
.TOKEN:                        ; Test one predicting token.
    LD   A,(HL)                    ; Fetch it with its end-of-list bit,
    INC  HL                        ; and step past it.
    XOR  C                         ; Bits 0-6 are zero if it predicts the production,
    ADD  A,A                       ; and carry is the end-of-list bit.
    JR   Z,.MATCH                  ; It does: expand the production.
    JR   NC,.TOKEN                 ; The alternative has more tokens to test.
    BIT  7,B                       ; Was this the row's last alternative?
    JR   Z,.NEXTALT                ; No: try the next alternative.
    POP  DE                        ; Nothing predicts the lookahead: D is the row's diagnostic.
    LD   A,C                       ; An include here
    CP   TK_INCL                   ; follows a declaration
    LD   A,D                       ; (include-position: the loader
    JR   NZ,.REPORT                ; read those before any).
    LD   A,DG_LATE                 ; Report it.
.REPORT:                       ; A is the diagnostic.
    JP   DG_ISSUE                  ; Report it at the lookahead token.
.MATCH:                        ; B selects the production.
    POP  AF                        ; Discard the row's diagnostic.
    LD   A,B                       ; Fetch the production byte.
    AND  $7F                       ; Strip the last-alternative bit;
                                   ; fall into .EXPAND, which returns to the loop.

;@ROUTINE IN A CLOBBERS A,BC,DE,HL,CARRY,ZERO,SIGN,PARITY,HALFCARRY
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
    LD   E,A                       ; It is the first free slot's offset.
    ADD  A,B                       ; A is the depth after the push.
    JR   C,.FULL                   ; Past 255 symbols the stack is certainly full.
    CP   LL_CAP+1                  ; More than LL_CAP symbols?
    JR   NC,.FULL                  ; Raise DG_LLCAP.
    LD   (LL_DEPTH),A              ; Commit the new depth.
    LD   D,HIGH(LL_STACK)          ; DE is the first free slot, in the stack's page.
    LD   C,B                       ; Copy the body's length...
    LD   B,0                       ; ...as a word count.
    LDIR                           ; Push the reversed body; its leftmost symbol lands on top.
    RET                            ; The stack holds the right side.

.FULL:                         ; The grammar stack cannot take the push.
    CALL DG_RAISE                  ; Abandon the build.
    DB   DG_LLCAP                  ; Grammar stack overflow.

LL_CEND:                       ; End of the LL(1) engine's code (marker).
