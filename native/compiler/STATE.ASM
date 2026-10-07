;==========================================================================
;  Compiler workspace and shared constants
;==========================================================================
;
;  The first part of the compiler's workspace, from MM_WBASE ($5800), and
;  the constants that every phase shares: token kinds, diagnostic numbers,
;  symbol classes, aggregate type ordinals and relation codes. CALLWORK.ASM
;  continues the workspace to LL_WEND. Nothing here is initialised by the
;  image: PR_RESET and the routine entries clear what each needs.
;
;  The compiler makes one pass. The parser reads the source and the code
;  generators write each routine and top-level declaration as a blob while
;  it is parsed (BLOB.ASM, design decision D45), so parser and generator
;  state are live together and nothing here overlays anything else, except
;  the diagnostic position, which ends the compilation.
;
;    Offset  Size  Block
;    +$000     27  source cursor, current token, diagnostic (PR_BASE)
;    +$01B    160  emitter and routine generation: frame accounting, the
;                  routine's labels, ordinals, its waiting constants and
;                  the program's limits
;    +$0BB      3  parser lookahead
;    +$0BE     72  symbol table: its base, three marks and 32 hash chains
;                  (the records are above the largest part, SYMBOLS.ASM)
;    +$106    330  expression state, the folding scratch and the operand
;                  stack
;    +$250    162  control: depth, fallthrough, eight frames of twenty
;                  bytes
;    +$2F2   1530  aggregate types, records, fields, array bounds, the
;                  initializer staging
;    +$8EC         AG_WEND = PR_WEND, where CALLWORK.ASM begins
;
;  Writers: SOURCE.ASM owns SRC_*; TOKEN.ASM the TK_ fields (the parser
;  restores TK_PTR, TK_LEN and TK_POS when it revisits a retained name);
;  PARSER.ASM DG_* and PR_*; EMIT.ASM EM_*; GENCALL.ASM RG_*; SYMBOLS.ASM,
;  ACTIONS.ASM and ROUTINES.ASM the symbol table; EXPR.ASM EX_*; ACTIONS.ASM
;  AC_*; CONTROL.ASM and ACTIONS.ASM CT_*; AGGR.ASM and ACTIONS.ASM AG_*.

PR_BASE EQU  MM_WBASE          ; First byte of the compiler workspace.

; Source cursor (SOURCE.ASM) and line state (TOKEN.ASM).

SRC_ID EQU  PR_BASE+$00        ; Byte: identity of the current part.
SRC_PTR EQU  PR_BASE+$01       ; Word: address of the next source byte.
SRC_END EQU  PR_BASE+$03       ; Word: exclusive end of the current part.
SRC_POS EQU  PR_BASE+$05       ; Word: byte offset within the part.
SRC_LINE EQU  PR_BASE+$07      ; Word: line number, from one.
SRC_COL EQU  PR_BASE+$09       ; Word: column number, from one.
TK_LIVE EQU  PR_BASE+$0B       ; Byte: nonzero once this line has a token.
TK_NEST EQU  PR_BASE+$0C       ; Byte: open brackets, so line ends are blank.

; The current token (TOKEN.ASM). TK_POS..TK_COL is a six-byte position
; record of offset, line and column, which PR_COPY moves as a unit.

TK_POS EQU  PR_BASE+$0D        ; Word: offset where the token starts.
TK_LINE EQU  PR_BASE+$0F       ; Word: line where the token starts.
TK_COL EQU  PR_BASE+$11        ; Word: column where the token starts.
TK_PTR EQU  PR_BASE+$13        ; Word: address of a name's first byte.
TK_LEN EQU  PR_BASE+$15        ; Byte: length of a name or decoded string.

; The diagnostic (PARSER.ASM, DG_ISSUE). The shell prints it after a
; failed compilation, counting its line and column from DG_POS.

DG_CODE EQU  PR_BASE+$16       ; Byte: diagnostic number, zero for none.
DG_PART EQU  PR_BASE+$17       ; Byte: SRC_ID of the part at fault.
DG_POS EQU  PR_BASE+$18        ; Word: the offset in the part of the fault.

PR_STEND EQU  PR_BASE+$1B      ; End of the first block.


; The emitter's state (EMIT.ASM) for the routine being written: its frame
; accounting, as the reference compiler's RoutineState keeps it, and its
; labels. A label is four bytes: the offset it marks, EM_NONE while it is
; undefined, then the head of its chain of pending operands, zero when
; none waits (EM_LDEF). EM_OPEN starts both afresh for each routine.
EM_BASE EQU  PR_STEND          ; First byte of the emitter's state.
EM_FRAME EQU  EM_BASE+$00      ; Word: bytes of the frame given to locals.
EM_TEMPS EQU  EM_BASE+$02      ; Word: bytes pushed as expression temporaries.
EM_DEEP EQU  EM_BASE+$04       ; Word: the deepest frame and pushes reached.
EM_STACK EQU  EM_BASE+$06      ; Word: the largest stack figure of a helper called.
EM_NEED EQU  EM_BASE+$08       ; Word: the largest need of a routine called.
EM_LCNT EQU  EM_BASE+$0A       ; Byte: labels allocated in this routine.
EM_LTAB EQU  EM_BASE+$0B       ; EM_LCAP labels of EM_LLEN bytes.
EM_LLEN EQU  4                 ; Bytes in one label.
EM_LCAP EQU  32                ; Labels in one routine; DG_LABEL beyond.
EM_LLIM EQU  EM_LTAB+EM_LLEN*EM_LCAP ; Exclusive end of the labels.
EM_NONE EQU  $FFFF             ; The offset of a label not yet defined.
; A diagnostic's argument text (DG_NAMED, MESSAGE.ASM), over the
; emitter's labels, which no failed compilation needs; DG_ARG1 and
; DG_ARG2 (SHELL.ASM) point at the arguments.
DG_ABUF EQU  EM_LTAB           ; DG_ALEN bytes: a zero-terminated argument.
DG_ALEN EQU  33                ; A name is cut to 32 characters.
; Routine generation (GENCALL.ASM): ordinals and what the program's entry
; and limits records need, kept for the whole compilation.
RG_ORD EQU  EM_LLIM            ; Word: the next ordinal to give a blob.
RG_MAIN EQU  RG_ORD+2          ; Word: main's ordinal, for the entry record.
RG_NEED EQU  RG_MAIN+2         ; Word: main's need, for the stack reserve.
RG_LARGE EQU  RG_NEED+2        ; Word: the largest frame of any routine.
RG_PATCH EQU  RG_LARGE+2       ; Word: the offset of the prologue's frame operand.
RG_NAME EQU  RG_PATCH+2        ; Word: the routine's name, for the name stream.
RG_NLEN EQU  RG_NAME+2         ; Byte: its length.
RG_FWD EQU  RG_NLEN+1          ; Byte: nonzero once a routine is declared forward.
RG_PEND EQU  RG_FWD+1          ; Word: the end of the routine's waiting constants.
NH_PTR EQU  RG_PEND+2          ; Word: the name heap's bottom, which grows down.
RG_CBEG EQU  NH_PTR+2          ; Word: the start of the routine's waiting constants.
GX_IMMV EQU  RG_CBEG+2         ; Byte: the immediate of a frame byte's store (GX_DSTN).
TK_NBEG EQU  GX_IMMV+1         ; Word: the first digit of a decimal number (TOKEN.ASM).
GX_PTO EQU  TK_NBEG+2          ; Byte: a narrowing's target's properties (GX_TRIM).
EM_WEND EQU  GX_PTO+1          ; End of the emitter's state.

; The predictive expression path keeps one token of lookahead. $FF denotes an
; empty lookahead cell; token ordinals occupy the low half of the byte range.
PR_LKIND EQU  EM_WEND+$00      ; Byte: buffered token kind, or $FF.
PR_LVAL EQU  EM_WEND+$01       ; Word: the buffered token's payload.

; Source bytes remain resident through compilation, so a scalar symbol keeps
; the exact spelling as a pointer and length instead of copying name bytes.
; The record at SY_TOP is provisional until the declaration initializer
; succeeds; lookup sees only the committed records below it. Records are
; laid out in SYMBOLS.ASM. Globals, and the parameters and locals of the
; routine being compiled, share the table. A scope is marked by the
; address of its first record, never by a count.
SY_TOP EQU  EM_WEND+$03        ; Word: the provisional record, past the committed.
SY_GTOP EQU  EM_WEND+$05       ; Word: SY_TOP as a body opens; AC_END drops locals to it.
SY_BODY EQU  EM_WEND+$07       ; Word: the body's first record, zero outside one.
SY_BTM EQU  EM_WEND+$09        ; Word: the first record, above the largest part.
SY_RECB EQU  12                ; Bytes in one symbol record.
SY_FLAGS EQU  9                ; Record offset of its flags.
SY_LINK EQU  10                ; Record offset of the next record in its chain.
SY_FPRIV EQU  1                ; Flag: declared private (AC_PRIV).
SY_AGT EQU  6                  ; Record offset of an aggregate's type ordinal.
SY_VHI EQU  6                  ; Record offset of a constant's value's high bytes.
SY_HTAB EQU  SY_BTM+2          ; SY_HCAP words: each hash chain's newest record.
SY_HCAP EQU  32                ; Hash chains, a power of two.
SY_LIM EQU  SY_HTAB+2*SY_HCAP  ; End of the symbol table's marks and chains.

; Expression state (EXPR.ASM). An expression returns metadata in A (type
; in SY_TMASK, SY_KNOWN when the value is exact) and, when it is known,
; the low word of its value in HL and the whole of it in EX_KVAL: five
; bytes, the value in two's complement (VALUE.ASM), as wide as an exact
; value's range of -2^31 to 2^32-1 needs. A bounded stack retains the
; left operand of each pending binary operator. An entry is sixteen
; bytes: metadata, the five value bytes, EX_QUIET, operator, operator
; offset word and the six-byte position of the left value.
EX_WANT EQU  SY_LIM+$00        ; Byte: type the context expects.
EX_QUIET EQU  SY_LIM+$01       ; Byte: nonzero while faults fold to values.
EX_DEPTH EQU  SY_LIM+$02       ; Byte: entries on the operand stack.
EX_RMETA EQU  SY_LIM+$03       ; Byte: right operand's metadata.
EX_RVAL EQU  SY_LIM+$04        ; Five bytes: right operand's exact value.
EX_LMETA EQU  SY_LIM+$09       ; Byte: left operand's metadata.
EX_LVAL EQU  SY_LIM+$0A        ; Five bytes: left operand's exact value.
EX_OPER EQU  SY_LIM+$0F        ; Byte: pending relation code or operator.
EX_OPPOS EQU  SY_LIM+$10       ; Word: source offset for its trap.

; The declaration being parsed (ACTIONS.ASM), restored as the current name
; when its symbol is finally written.
AC_DINFO EQU  SY_LIM+$12       ; Byte: class and type of the new symbol.
AC_DVAL EQU  SY_LIM+$13        ; Five bytes: its payload, value or offset.
AC_DNAME EQU  SY_LIM+$18       ; Word: spelling, kept by TK_KEEP.
AC_DLEN EQU  SY_LIM+$1A        ; Byte: length of the spelling.
AC_DPOS EQU  SY_LIM+$1B        ; Six bytes: the declared name's position.
EX_LAT EQU  SY_LIM+$21         ; Word: the left operand's first offset (leftAt).
EX_RAT EQU  SY_LIM+$23         ; Word: the right operand's first offset (rightAt).
EX_MINB EQU  SY_LIM+$25        ; Byte: the innermost EX_CLIMB's minimum precedence.
EX_START EQU  SY_LIM+$29       ; Word: the offset of the last expression's first token.
TK_ENDP EQU  SY_LIM+$2B        ; Word: the offset of the last `end` (TOKEN.ASM).
AC_SPOS EQU  SY_LIM+$2D        ; Word: the offset of the name statement's first token.
EX_CHR EQU  SY_LIM+$2F         ; Byte: 1 while the only primary is a character literal.
EX_PRIME EQU  SY_LIM+$30       ; Byte: a first primary's type, parsed already, or zero.
EX_KVAL EQU  SY_LIM+$31        ; Five bytes: the latest known result's value.
VL_TA EQU  SY_LIM+$36          ; Five bytes: VALUE.ASM's first scratch operand.
VL_TB EQU  SY_LIM+$3B          ; Five bytes: its second.
VL_TR EQU  SY_LIM+$40          ; Five bytes: its remainder.
TK_NLO EQU  SY_LIM+$45         ; Word: a number's low word as it is scanned (TOKEN.ASM).
TK_NHI EQU  SY_LIM+$47         ; Word: a number token's high word.
TK_WIDE EQU  SY_LIM+$49        ; Byte: nonzero once a decimal number passes 32
                               ; bits; then SY_F32 for a floating-point literal.
EX_STACK EQU  SY_LIM+$4A       ; First operand-stack entry.
EX_STCAP EQU  16               ; Entries; DG_DEEP when exceeded.
EX_SPARE EQU  192              ; Stack kept below a nested expression's start (EX_INNER).
EX_STLEN EQU  16               ; Bytes in one entry.
EX_STLIM EQU  EX_STACK+EX_STCAP*EX_STLEN ; Exclusive end of the stack.

; Structured control (CONTROL.ASM) keeps an eighteen-byte frame for each
; open if, while, for and handler; the fields are laid out there.
CT_BASE EQU  EX_STLIM          ; First byte of the control block.
CT_DEPTH EQU  CT_BASE+$00      ; Byte: open control frames.
CT_FALLS EQU  CT_BASE+$01      ; Byte: nonzero while control can reach this point.
CT_FTAB EQU  CT_BASE+$02       ; First control frame.
CT_FLEN EQU  20                ; Bytes in one frame.
CT_FCAP EQU  8                 ; Frames; DG_NEST when exceeded.
CT_FLIM EQU  CT_FTAB+CT_FLEN*CT_FCAP ; Exclusive end of the frames.

CT_KIF EQU  1                  ; Frame kind: if, elseif, else.
CT_KLOOP EQU  2                ; Frame kind: while loop.
CT_KFOR EQU  3                 ; Frame kind: counted for loop.
CT_KTRAP EQU  4                ; Frame kind: failure handler.
CT_KSEL EQU  5                 ; Frame kind: select.
CT_FKIND EQU  0                ; Frame field: kind.
CT_FDEST EQU  1                ; Frame field: next arm, body or failure label.
CT_FCONT EQU  2                ; Frame field: continue label.
CT_FEXIT EQU  3                ; Frame field: end, exit or skip label.
CT_FLCNT EQU  4                ; Frame field: labels in use as it opened.
CT_FSIZE EQU  5                ; Frame field: the frame's size as it opened (word).
CT_FMODE EQU  7                ; Frame field: if flags, for mode, kept bytes.
CT_FVAR EQU  8                 ; Frame field: the counter's offset (word).
CT_FBND EQU  10                ; Frame field: the bound's offset (word).
CT_FSTEP EQU  12               ; Frame field: the step's magnitude (four bytes).
CT_FSYMS EQU  16               ; Frame field: SY_TOP as it opened, its blocks' first record (word).
CT_FSUBJ EQU  18               ; Frame field: a handle select's subject's record (word).
CT_MINC EQU  1                 ; For mode: to, the bound is inclusive.
CT_MDOWN EQU  2                ; For mode: the step is negative.
CT_MWORD EQU  4                ; For mode: the counter is a word.
CT_MSIGN EQU  8                ; For mode: the counter is signed.
CT_MCMPS EQU  $10              ; For mode: the comparison with the bound is signed.
CT_MALL EQU  $20               ; For mode: no bound in reach; it runs until it traps.
CT_MNONE EQU  $40              ; For mode: no bound in reach; it never starts.
CT_MLONG EQU  $80              ; For mode: the counter is a long.

; Aggregate type and layout metadata lasts the whole compilation. Type IDs
; 1..3 are the predefined scalars; IDs 4 and above name bounded four-byte
; descriptors. Record field offsets stay live for field selection.
AG_BASE EQU  CT_FLIM           ; First byte of the aggregate block.
AG_DCNT EQU  AG_BASE+$00       ; Byte: array bounds waiting in AG_DSTK.
AG_TCNT EQU  AG_BASE+$01       ; Byte: descriptors in the type table.
AG_RCNT EQU  AG_BASE+$02       ; Byte: records in the record table.
AG_FCNT EQU  AG_BASE+$03       ; Byte: fields in the field table.
AG_LEVEL EQU  AG_BASE+$04      ; Byte: initializer nesting depth.
; Nonzero once an explicit initializer has supplied at least one value. The
; value is a Boolean allocation choice, not a retained element count.
AG_GIVEN EQU  AG_BASE+$05      ; Byte: an initializer value was given.
AG_OPENF EQU  AG_BASE+$06      ; Byte: nonzero once a type's `[]` is read.
AG_CTYPE EQU  AG_BASE+$07      ; Byte: type ID of the current object.
AG_CFIDX EQU  AG_BASE+$08      ; Byte: first field of the current record.
AG_CFCNT EQU  AG_BASE+$09      ; Byte: fields of the current record.
AG_CSIZE EQU  AG_BASE+$0A      ; Word: extent of the current record.
AG_OPOS EQU  AG_BASE+$0C       ; Word: offset reached in the object.
AG_OSIZE EQU  AG_BASE+$0E      ; Word: extent of the current object.
AG_NKIND EQU  AG_BASE+$10      ; Byte: candidate descriptor's kind.
AG_NAUX EQU  AG_BASE+$11       ; Byte: its element type or capacity.
AG_NDIM EQU  AG_BASE+$12       ; Word: its element count or length.
AG_NSIZE EQU  AG_BASE+$14      ; Word: its extent in bytes.
AG_OEND EQU  AG_BASE+$16       ; Word: end of the current object.
AG_TPOS EQU  AG_BASE+$18       ; Word: the offset of the type's first token.
; The bounds of a type's array dimensions, outermost first, kept until the
; type is complete and built from the innermost (AC_DIM, AC_ARRAY).
AG_DSTK EQU  AG_BASE+$1A       ; AG_DCAP words: the bounds.
AG_DCAP EQU  8                 ; Dimensions of one array type; DG_BOUND beyond.
AG_STEND EQU  AG_DSTK+2*AG_DCAP ; End of the aggregate scalars.

; The type table: one four-byte descriptor per aggregate type, interned so
; that equal types share an ID. AG_NKIND..AG_NDIM is built in the same
; shape and compared or copied as a block.
AG_TTAB EQU  AG_STEND          ; First type descriptor.
AG_TLEN EQU  4                 ; Bytes in one descriptor.
AG_TCAP EQU  48                ; Descriptors, IDs below AG_OPEN; DG_META when exceeded.
AG_TLIM EQU  AG_TTAB+AG_TLEN*AG_TCAP ; Exclusive end of the type table.
AG_TKIND EQU  0                ; Descriptor field: AG_KREC, KSTR or KARR.
AG_TAUX EQU  1                 ; Descriptor field: element type or capacity.
AG_TDIM EQU  2                 ; Descriptor field: length, a word.
; Every dynamic type retains its complete nonzero extent as a word. Strings
; remain byte-capacity values, while arrays and records may occupy the complete
; selected program-data region.
AG_XTAB EQU  AG_TLIM           ; Words: each type's extent in bytes.
AG_XLIM EQU  AG_XTAB+2*AG_TCAP ; Exclusive end of the extents.

; The record table: where each record type's fields lie in the field table.
AG_RTAB EQU  AG_XLIM           ; First record entry.
AG_RLEN EQU  2                 ; Bytes in one record entry.
AG_RCAP EQU  48                ; Record types; DG_META when exceeded.
AG_RLIM EQU  AG_RTAB+AG_RLEN*AG_RCAP ; Exclusive end of the record table.
AG_RFIDX EQU  0                ; Record field: index of its first field.
AG_RFCNT EQU  1                ; Record field: number of fields.

; The field table: every record's fields, in declaration order.
AG_FTAB EQU  AG_RLIM           ; First field entry.
AG_FLEN EQU  6                 ; Bytes in one field entry.
AG_FCAP EQU  48                ; Fields in all; DG_META when exceeded.
AG_FLIM EQU  AG_FTAB+AG_FLEN*AG_FCAP ; Exclusive end of the field table.
AG_FNAME EQU  0                ; Field entry: spelling, a word.
AG_FNLEN EQU  2                ; Field entry: spelling length.
AG_FTYPE EQU  3                ; Field entry: type ID.
AG_FPOS EQU  4                 ; Field entry: byte offset, a word.

; One object's initializer is staged here, then written as its blob.
AG_IBUF EQU  AG_FLIM           ; One object's initializer, built here.
AG_ICAP EQU  1024              ; Bytes of initializer staging; DG_DATA beyond.
AG_WEND EQU  AG_IBUF+AG_ICAP   ; End of the aggregate block.
PR_WEND EQU  AG_WEND           ; End of this file's workspace.

AG_LCAP EQU  4                 ; Initializer nesting levels; DG_INITS beyond.

; Token kinds, as TK_NEXT returns them in A. Grammar terminals use the same
; ordinals, so they stay below $40 (LL1.ASM), and a kind the grammar
; expects stays below 62, so that DG_TOKEN plus it is a syntax diagnostic
; (below 190). Only the grammar's terminals and the pseudo-kinds need those
; ordinals: a token only the expression island reads, or that the parser
; never sees, takes a kind from $40 on (below). The spellings are in
; KEYWORDS.ASM. Free below 62: 28, 32 to 37, 39, 50, 53 and 54;
; 63 too, for a terminal never expected alone (as `select` is).

TK_EOF EQU  0                  ; End of the last source part.
TK_EOL EQU  1                  ; End of a line that produced a token.
TK_NAME EQU  2                 ; Name: TK_PTR and TK_LEN.
TK_CHAR EQU  3                 ; Character literal: code in BC.
TK_NUM EQU  4                  ; Number: value in BC.
TK_LPAR EQU  5                 ; Left parenthesis.
TK_RPAR EQU  6                 ; Right parenthesis.
TK_EQ EQU  7                   ; Equals sign: assignment or equality.
TK_SUB EQU  8                  ; Keyword sub.
TK_FAILS EQU  9                ; Keyword fails.
TK_POOL EQU  10                ; Keyword pool.
TK_FAIL EQU  11                ; Keyword fail.
TK_END EQU  12                 ; Keyword end.
TK_VAR EQU  13                 ; Keyword var.
TK_AS EQU  14                  ; Keyword as.
TK_TYPE EQU  15                ; A type keyword: u8, i8, u16, i16, u32, i32, f32
                               ; or boolean, its type ID in C (SY_U8...).
TK_FOR EQU  16                 ; Keyword for.
TK_UNTIL EQU  17               ; Keyword until.
TK_LBRAC EQU  18               ; Left bracket.
TK_RBRAC EQU  19               ; Right bracket.
TK_COMMA EQU  20               ; Comma.
TK_FORW EQU  21                ; Keyword forward.
TK_RET EQU  22                 ; Keyword return.
TK_IF EQU  23                  ; Keyword if.
TK_MINUS EQU  24               ; Minus sign.
TK_PLUS EQU  25                ; Plus sign.
TK_QUEST EQU  26               ; Question mark: an optional handle, new?.
TK_TRUE EQU  29                ; Keyword true.
TK_FALSE EQU  30               ; Keyword false.
TK_CONST EQU  31               ; Keyword const.
TK_NOT EQU  38                 ; Keyword not.
TK_ELSIF EQU  40               ; Keyword elseif.
TK_ELSE EQU  41                ; Keyword else.
TK_WHILE EQU  42               ; Keyword while.
TK_TO EQU  43                  ; Keyword to.
TK_STEP EQU  44                ; Keyword step.
TK_EXIT EQU  45                ; Keyword exit.
TK_CONT EQU  46                ; Keyword continue.
TK_TEXT EQU  47                ; String literal: TK_PTR, decoded TK_LEN.
TK_REC EQU  48                 ; Keyword record.
TK_STR EQU  49                 ; Keyword string.
TK_HANDL EQU  51               ; Keyword handle.
TK_PRIV EQU  52                ; Keyword private.
TK_ASSRT EQU  55               ; Keyword assert.
TK_CASE EQU  61                ; Keyword case: a select's arm.
TK_SEL EQU  62                 ; Keyword select, never expected alone (DG_TOKEN+62 is 190).
; Keywords the grammar never names, so their kinds may pass $3F: include,
; read by the loader, and the handle selection's words, which an integer
; select refuses where it meets them.
TK_SOME EQU  $40               ; Keyword some.
TK_NONE EQU  $41               ; Keyword none.
TK_MOVE EQU  $42               ; Keyword move.
TK_INCL EQU  $43               ; Keyword include.
; The operators, read only inside the expression island (EXPR.ASM,
; EXOPER.ASM) and the path parser (CALLS.ASM), never by the grammar; the
; orders of TK_STAR to TK_SHR, TK_SLASH to TK_NE and TK_XOR to TK_MOD
; are kept, and TK_AND, TK_XOR and TK_MOD, with TK_OR, are the only
; arithmetic operators from TK_AND on (EX_ARITH's f32 test).
TK_OR EQU  $44                 ; Keyword or.
TK_STAR EQU  $45               ; Asterisk: multiplication.
TK_SHL EQU  $46                ; Keyword shl.
TK_SHR EQU  $47                ; Keyword shr.
TK_SLASH EQU  $48              ; Slash: division.
TK_LT EQU  $49                 ; Less than.
TK_LE EQU  $4A                 ; Less than or equal.
TK_GT EQU  $4B                 ; Greater than.
TK_GE EQU  $4C                 ; Greater than or equal.
TK_NE EQU  $4D                 ; Not equal.
TK_AND EQU  $4E                ; Keyword and.
TK_DOT EQU  $4F                ; Full stop: field selection.
TK_XOR EQU  $50                ; Keyword xor.
TK_MOD EQU  $51                ; Keyword mod.
TK_NEW EQU  $52                ; Keyword new, a slot allocated.

; Diagnostic codes, as DG_CODE reports them. Below DG_TOKEN and from 190
; to 199 a code is the reference compiler's number for the diagnostic
; (ref/compile/messages.ts, docs/diagnostics.md), printed with its text
; from BASIE.MSG (MESSAGE.ASM); the comment gives the reference's code.
; DG_TOKEN plus a token kind, or a pseudo-kind for a phrase, is `syntax`,
; naming what was expected; DG_CAP plus an index is `capacity`, naming
; the limit this compiler reached.

DG_LEXB EQU  1                 ; bad-byte: a byte the source may not hold.
DG_CR EQU  2                   ; lone-cr.
DG_LEX EQU  3                  ; bad-character: a byte no token begins with.
DG_FORM EQU  4                 ; malformed-number.
DG_ESC EQU  5                  ; bad-escape.
DG_NONE EQU  6                 ; empty-character.
DG_LONGC EQU  7                ; long-character.
DG_OPEN EQU  8                 ; unterminated-literal.
DG_SHUT EQU  9                 ; unmatched-delimiter.
DG_AJAR EQU  11                ; open-delimiter.
DG_LATE EQU  21                ; include-position: an include after a declaration.
DG_CYCLE EQU  22               ; include-cycle.
DG_LOST EQU  23                ; include-missing.
DG_INCL EQU  24                ; include-syntax.
DG_MAIN EQU  25                ; missing-main.
DG_UNDEF EQU  27               ; undeclared-name.
DG_BADMN EQU  26               ; bad-main.
DG_DUP EQU  28                 ; duplicate-name.
DG_HIDE EQU  29                ; shadowed-name: a local or parameter hides a name.
DG_CLASS EQU  30               ; wrong-class: a name of the wrong kind.
DG_RECUR EQU  31               ; recursion-needs-forward.
DG_FWDNO EQU  32               ; forward-mismatch.
DG_UNMET EQU  33               ; forward-incomplete.
DG_CONV EQU  40                ; conversion-required.
DG_CLASH EQU  41               ; type-mismatch.
DG_RANGE EQU  42               ; out-of-range: a value or bound outside its type.
DG_PNREC EQU  46               ; pool-needs-record.
DG_HOPT EQU  47                ; handle-must-be-optional.
DG_UNTYP EQU  43               ; constant-needs-type: an untyped constant's value.
DG_INFER EQU  44               ; no-definite-type: an initializer to infer from.
DG_FALSE EQU  45               ; assertion-false.
DG_EMPTY EQU  48               ; empty-record.
DG_SINIT EQU  49               ; static-initializer.
DG_NEEDI EQU  50               ; needs-initializer: a non-optional handle local.
DG_PINC EQU  52                ; pool-incomplete.
DG_OPTH EQU  105               ; optional-handle: tested with select before use.
DG_MOVED EQU  102              ; use-after-move.
DG_SRULE EQU  103              ; statement-rule.
DG_OWNER EQU  106              ; not-owner.
DG_LEASE EQU  107              ; lease: not the routine's own owner.
DG_HOLDR EQU  108              ; slot-holder: a location that can't be one.
DG_LMOVE EQU  109              ; loop-moves-owner.
DG_NMOVE EQU  100              ; needs-move: an owning handle is moved, not copied.
DG_OCOPY EQU  101              ; owning-copy: an owning object copied.
DG_KNOWN EQU  51               ; not-constant.
DG_NOCVT EQU  53               ; conversion-unavailable.
DG_VARP EQU  54                ; var-parameter: var on a scalar or File.
DG_FROM EQU  55                ; from-clause: no aggregate parameter.
DG_MIXED EQU  70               ; mixed-operands.
DG_CHAIN EQU  71               ; chained-comparison.
DG_INDEX EQU  72               ; index-type.
DG_ZERO EQU  73                ; division-by-zero.
DG_FOVER EQU  80               ; float-overflow: an f32 fold past the largest.
DG_CONST EQU  74               ; not-writable.
DG_FIELD EQU  76               ; no-such-field.
DG_NOIDX EQU  77               ; not-indexable.
DG_VOID EQU  78                ; no-value: a routine without a result.
DG_TRUNC EQU  79               ; narrowing: an exact u8() that loses bits.
DG_PAST EQU  81                ; bounds: a constant index out of range.
DG_LOOP EQU  82                ; outside-loop.
DG_COUNT EQU  83               ; loop-counter.
DG_STEP EQU  84                ; loop-step.
DG_FLOW EQU  85                ; missing-return.
DG_RFORM EQU  86               ; return-form: a value where none goes, or none where one does.
DG_ALIAS EQU  104              ; alias-escapes: a result rooted in the frame.
DG_ARITY EQU  111              ; arity: too many arguments.
DG_SAFE EQU  112               ; not-failable.
DG_LEAK EQU  113               ; failure-unconsumed.
DG_OVERL EQU  75               ; duplicate-case: a select's labels overlap.
DG_DEST EQU  114               ; handle-destination.
DG_NYI EQU  191                ; native-unsupported: not yet compiled natively.
DG_BUG EQU  199                ; internal.

; Ordinary token mismatches encode the token ordinal directly. Named-value
; mismatches retain their context-specific diagnostic codes above.
DG_TOKEN EQU  $80              ; PR_NEED raises DG_TOKEN plus the kind expected.
DG_EOF EQU  DG_TOKEN+TK_EOF    ; End of source expected.
DG_EOL EQU  DG_TOKEN+TK_EOL    ; End of line expected.
DG_LPAR EQU  DG_TOKEN+TK_LPAR  ; Left parenthesis expected.
DG_RPAR EQU  DG_TOKEN+TK_RPAR  ; Right parenthesis expected.
DG_EQ EQU  DG_TOKEN+TK_EQ      ; Equals sign expected.
DG_SUB EQU  DG_TOKEN+TK_SUB    ; sub expected.
DG_KFAIL EQU  DG_TOKEN+TK_FAIL ; fail expected.
DG_END EQU  DG_TOKEN+TK_END    ; end expected.
DG_VAR EQU  DG_TOKEN+TK_VAR    ; var expected.
DG_FOR EQU  DG_TOKEN+TK_FOR    ; for expected.
DG_FORW EQU  DG_TOKEN+TK_FORW  ; forward expected.
DG_RET EQU  DG_TOKEN+TK_RET    ; return expected.
DG_IF EQU  DG_TOKEN+TK_IF      ; if expected.
DG_COMMA EQU  DG_TOKEN+TK_COMMA ; A comma expected.
DG_NAME EQU  DG_TOKEN+TK_NAME  ; A name expected.

; Pseudo-kinds, above the token kinds the grammar names and below
; DG_CAP-DG_TOKEN: what a syntax diagnostic expected that is no single
; token (MESSAGE.ASM's phrases, the reference compiler's words). TK_CASE
; follows them, the last kind whose DG_TOKEN code is a syntax diagnostic.
TK_XEXPR EQU  56               ; An expression.
TK_XTYPE EQU  57               ; A type.
TK_XDECL EQU  58               ; A declaration.
TK_XSTMT EQU  59               ; A statement.
TK_XUPTO EQU  60               ; to or until.
DG_VALUE EQU  DG_TOKEN+TK_XEXPR ; Expected an expression.
DG_TYPE EQU  DG_TOKEN+TK_XTYPE ; Expected a type.
DG_DECL EQU  DG_TOKEN+TK_XDECL ; Expected a declaration.
DG_STMT EQU  DG_TOKEN+TK_XSTMT ; Expected a statement.
DG_UPTO EQU  DG_TOKEN+TK_XUPTO ; Expected to or until.
DG_CASE EQU  DG_TOKEN+TK_CASE  ; Expected case.

; The limits of this compiler: `capacity`, with the limit's name
; (MS_CAPS, in this order) as its argument.
DG_CAP EQU  200                ; The first.
DG_SYMS EQU  DG_CAP+0          ; The symbol table (SY_CAP).
DG_PROCS EQU  DG_CAP+1         ; The routine records (RO_RCAP).
DG_PARAM EQU  DG_CAP+2         ; One routine's parameters (RO_PCAP).
DG_LITS EQU  DG_CAP+3          ; One routine's string literals (RO_LCAP).
DG_META EQU  DG_CAP+4          ; Types, records and fields.
DG_NEST EQU  DG_CAP+5          ; Control statements open at once (CT_FCAP).
DG_DEEP EQU  DG_CAP+6          ; The operand stack, or calls inside calls.
DG_LABEL EQU  DG_CAP+7         ; One routine's labels (EM_LCAP).
DG_INITS EQU  DG_CAP+8         ; Nested initializers (AG_LCAP).
DG_DATA EQU  DG_CAP+9          ; The initializer staging (AG_ICAP).
DG_BLOB EQU  DG_CAP+10         ; The blob writer's buffers.
DG_LLCAP EQU  DG_CAP+11        ; The grammar stack (LL_CAP).
DG_PARTS EQU  DG_CAP+12        ; Source parts: 255, the line stream's limit.
DG_ROOM EQU  DG_CAP+13         ; Memory for the source.
DG_INEST EQU  DG_CAP+14        ; Includes open at once (SH_ICAP).
DG_FDIG EQU  DG_CAP+15         ; An f32 literal's digits (FLOAT.ASM, FL_NB).
DG_POOLS EQU  DG_CAP+16        ; Pools (PL_CAP).
DG_OWNRS EQU  DG_CAP+17        ; Owners in scope (FW_CAP).


; Scalar types and symbol information. An expression's metadata byte and a
; symbol's class/type byte share the low four bits: the type in SY_TMASK.
; The symbol byte adds its storage class in SY_CMASK and the flags SY_TYPE
; and SY_AGGR; the metadata byte uses bit 7 as SY_KNOWN instead. Each
; scalar type's size and signedness are in GX_PROP (GENEXPR.ASM).

SY_EXACT EQU  0                ; Type: an exact constant not yet typed.
SY_U8 EQU  1                   ; Type: u8.
SY_U16 EQU  2                  ; Type: u16.
SY_BOOL EQU  3                 ; Type: boolean.
SY_I8 EQU  4                   ; Type: i8.
SY_I16 EQU  5                  ; Type: i16.
SY_U32 EQU  6                  ; Type: u32.
SY_I32 EQU  7                  ; Type: i32.
SY_F32 EQU  8                  ; Type: f32, a known value its IEEE single bits.
SY_TMASK EQU  $0F              ; Mask of the type bits.
SY_KNOWN EQU  $80              ; Metadata flag: the value is exact, in HL.
SY_CONST EQU  $00              ; Class: a constant.
SY_GLOB EQU  $10               ; Class: a program variable.
SY_LOCAL EQU  $20              ; Class: a local of the current routine.
SY_PARAM EQU  $30              ; Class: a parameter of the current routine.
SY_CMASK EQU  $30              ; Mask of the class bits.
SY_TYPE EQU  $40               ; Symbol flag: the name is a record type.
SY_AGGR EQU  $80               ; Symbol flag: the object is an aggregate.
SY_PFROM EQU  1                ; Aggregate parameter flag: named in from.
SY_PVAR EQU  2                 ; Aggregate parameter flag: var, writable.
SY_LEASE EQU  4                ; Aggregate parameter flag: a lease, its slot word.
SY_RTYPE EQU  SY_TYPE          ; Information byte of a record type name.
SY_AGLOB EQU  SY_AGGR+SY_GLOB  ; Information byte of an aggregate variable.

AG_U16 EQU  SY_U16             ; Type ID of u16; IDs 1..8 are the scalars.
AG_FIRST EQU  16               ; First type ID of the type table.
AG_KREC EQU  4                 ; Descriptor kind: record.
AG_KSTR EQU  5                 ; Descriptor kind: bounded string.
AG_KARR EQU  6                 ; Descriptor kind: array.
; Types outside the type table, so outside its compact ordinals. A File
; is four bytes, held as a value as the reference's is: a program variable,
; local or parameter, never a field or element. The views are parameter
; types only, and the u8[] and var forms only the services': bit 0 is var,
; and with it clear the ID is AG_VIEW for a string, AG_BUF for a u8 array.
AG_FILE EQU  $79               ; Type ID of File.
AG_BUF EQU  $7A                ; Type ID of a u8[] parameter (services).
AG_VIEW EQU  $7C               ; Type ID of an open string parameter.
; An open array, T[], a parameter type only, is AG_OPEN plus its element's
; ID, $41 to $67. A parameter's type, a routine's or a service's, has bit
; 7 (AG_VAR) set for a var parameter.
AG_OPEN EQU  $40               ; Type ID of an open array of no element.
AG_OLIM EQU  $68               ; Exclusive end of the open arrays' IDs.
; A handle type is AG_HND plus four times its pool's index (POOLS.ASM)
; plus its form: AG_HOPT for P? and AG_HID for id P, both for id P?. An
; owning handle is two bytes, an identifier four: its slot and generation.
AG_HND EQU  $68                ; Type ID of an owning handle of pool 0.
AG_HOPT EQU  1                 ; Handle form bit: optional, may be none.
AG_HID EQU  2                  ; Handle form bit: an identifier, not an owner.
PL_CAP EQU  4                  ; Pools; DG_POOLS beyond.
AG_HEND EQU  AG_HND+4*PL_CAP   ; Exclusive end of the handle IDs.
AG_VAR EQU  $80                ; Parameter type flag: var.

; Relation codes: EXPR.ASM keeps the pending comparison as one of them in
; EX_OPER, and the comparison templates (GENEXPR.ASM) select by it.

EX_EQ EQU  0                   ; Equal.
EX_NE EQU  1                   ; Not equal.
EX_LT EQU  2                   ; Less than.
EX_LE EQU  3                   ; Less than or equal.
EX_GT EQU  4                   ; Greater than.
EX_GE EQU  5                   ; Greater than or equal.
