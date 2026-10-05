;==========================================================================
;  Compiler workspace and shared constants
;==========================================================================
;
;  The first part of the compiler's workspace, from MM_WBASE ($4800), and
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
;    +$01B    154  emitter and routine generation: frame accounting, the
;                  routine's labels, ordinals and the program's limits
;    +$0B5      3  parser lookahead
;    +$0B8    673  symbol table: count, 96 records of seven bytes
;    +$359    240  expression state and the operand stack
;    +$449    130  control: depth, fallthrough, eight frames of sixteen bytes
;    +$4CB   1527  aggregate types, records, fields, array bounds, the
;                  initializer staging
;    +$AC2         AG_WEND = PR_WEND, where CALLWORK.ASM begins
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
; failed compilation. DG_POS..DG_COL is a copy of the token's position.

DG_CODE EQU  PR_BASE+$16       ; Byte: diagnostic number, zero for none.
DG_PART EQU  PR_BASE+$17       ; Byte: SRC_ID of the part at fault.
DG_POS EQU  PR_BASE+$18        ; Word: offset of the token at fault.
DG_LINE EQU  PR_BASE+$1A       ; Word: its line.
DG_COL EQU  PR_BASE+$1C        ; Word: its column.

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
GX_IMMV EQU  RG_FWD+1          ; Byte: the immediate of a frame byte's store (GX_DSTN).
EM_WEND EQU  GX_IMMV+1         ; End of the emitter's state.

; The predictive expression path keeps one token of lookahead. $FF denotes an
; empty lookahead cell; token ordinals occupy the low half of the byte range.
PR_LKIND EQU  EM_WEND+$00      ; Byte: buffered token kind, or $FF.
PR_LVAL EQU  EM_WEND+$01       ; Word: the buffered token's payload.

; Source bytes remain resident through compilation, so a scalar symbol keeps
; the exact spelling as a pointer and length instead of copying name bytes.
; The entry at SY_CNT is provisional until the declaration initializer
; succeeds; lookup sees only the committed prefix. Records are laid out in
; SYMBOLS.ASM. Globals, and the parameters and locals of the routine being
; compiled, share the table.
SY_CNT EQU  EM_WEND+$03        ; Byte: committed symbols.
SY_BASE EQU  EM_WEND+$04       ; First symbol record.
SY_RECB EQU  7                 ; Bytes in one symbol record.
SY_AGT EQU  6                  ; Record offset of an aggregate's type ordinal.
SY_CAP EQU  96                 ; Symbol records in the table; DG_SYMS beyond.
SY_LIM EQU  SY_BASE+SY_RECB*SY_CAP ; Exclusive end of the symbol table.

; Expression state (EXPR.ASM). An expression returns metadata in A (type
; in SY_TMASK, SY_KNOWN when the value is exact) and an exact value in HL.
; A bounded stack retains the left operand of each pending binary operator.
; An entry is thirteen bytes: metadata, value word, EX_QUIET, operator,
; operator offset word and the six-byte position of the left value.
EX_WANT EQU  SY_LIM+$00        ; Byte: type the context expects.
EX_QUIET EQU  SY_LIM+$01       ; Byte: nonzero while faults fold to values.
EX_DEPTH EQU  SY_LIM+$02       ; Byte: entries on the operand stack.
EX_RMETA EQU  SY_LIM+$03       ; Byte: right operand's metadata.
EX_RVAL EQU  SY_LIM+$04        ; Word: right operand's exact value.
EX_LMETA EQU  SY_LIM+$06       ; Byte: left operand's metadata.
EX_LVAL EQU  SY_LIM+$07        ; Word: left operand's exact value.
EX_OPER EQU  SY_LIM+$09        ; Byte: pending relation code or operator.
EX_OPPOS EQU  SY_LIM+$0A       ; Word: source offset for its trap.

; The declaration being parsed (ACTIONS.ASM), restored as the current name
; when its symbol is finally written.
AC_DINFO EQU  SY_LIM+$0C       ; Byte: class and type of the new symbol.
AC_DVAL EQU  SY_LIM+$0D        ; Word: its payload, value or offset.
AC_DNAME EQU  SY_LIM+$0F       ; Word: spelling, kept by TK_KEEP.
AC_DLEN EQU  SY_LIM+$11        ; Byte: length of the spelling.
AC_DPOS EQU  SY_LIM+$12        ; Six bytes: the declared name's position.
EX_VPOS EQU  SY_LIM+$18        ; Six bytes: the latest value's position.
EX_LPOSP EQU  SY_LIM+$1E       ; Word: popped left value's position record.
EX_STACK EQU  SY_LIM+$20       ; First operand-stack entry.
EX_STCAP EQU  16               ; Entries; DG_DEEP when exceeded.
EX_STLEN EQU  13               ; Bytes in one entry.
EX_STLIM EQU  EX_STACK+EX_STCAP*EX_STLEN ; Exclusive end of the stack.

; Structured control (CONTROL.ASM) keeps a sixteen-byte frame for each
; open if, while, for and handler; the fields are laid out there.
CT_BASE EQU  EX_STLIM          ; First byte of the control block.
CT_DEPTH EQU  CT_BASE+$00      ; Byte: open control frames.
CT_FALLS EQU  CT_BASE+$01      ; Byte: nonzero while control can reach this point.
CT_FTAB EQU  CT_BASE+$02       ; First control frame.
CT_FLEN EQU  16                ; Bytes in one frame.
CT_FCAP EQU  8                 ; Frames; DG_NEST when exceeded.
CT_FLIM EQU  CT_FTAB+CT_FLEN*CT_FCAP ; Exclusive end of the frames.

CT_KIF EQU  1                  ; Frame kind: if, elseif, else.
CT_KLOOP EQU  2                ; Frame kind: while loop.
CT_KFOR EQU  3                 ; Frame kind: counted for loop.
CT_KTRAP EQU  4                ; Frame kind: failure handler.
CT_FKIND EQU  0                ; Frame field: kind.
CT_FDEST EQU  1                ; Frame field: next arm, body or failure label.
CT_FCONT EQU  2                ; Frame field: continue label.
CT_FEXIT EQU  3                ; Frame field: end, exit or skip label.
CT_FLCNT EQU  4                ; Frame field: labels in use as it opened.
CT_FSIZE EQU  5                ; Frame field: the frame's size as it opened (word).
CT_FMODE EQU  7                ; Frame field: if flags, for mode, kept bytes.
CT_FVAR EQU  8                 ; Frame field: the counter's offset (word).
CT_FBND EQU  10                ; Frame field: the bound's offset (word).
CT_FSTEP EQU  12               ; Frame field: the step's magnitude (word).
CT_MINC EQU  1                 ; For mode: to, the bound is inclusive.
CT_MDOWN EQU  2                ; For mode: the step is negative.
CT_MWORD EQU  4                ; For mode: the counter is a u16.

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
AG_CTYPE EQU  AG_BASE+$06      ; Byte: type ID of the current object.
AG_CFIDX EQU  AG_BASE+$07      ; Byte: first field of the current record.
AG_CFCNT EQU  AG_BASE+$08      ; Byte: fields of the current record.
AG_CSIZE EQU  AG_BASE+$09      ; Word: extent of the current record.
AG_OPOS EQU  AG_BASE+$0B       ; Word: offset reached in the object.
AG_OSIZE EQU  AG_BASE+$0D      ; Word: extent of the current object.
AG_NKIND EQU  AG_BASE+$0F      ; Byte: candidate descriptor's kind.
AG_NAUX EQU  AG_BASE+$10       ; Byte: its element type or capacity.
AG_NDIM EQU  AG_BASE+$11       ; Word: its element count or length.
AG_NSIZE EQU  AG_BASE+$13      ; Word: its extent in bytes.
AG_OEND EQU  AG_BASE+$15       ; Word: end of the current object.
; The bounds of a type's array dimensions, outermost first, kept until the
; type is complete and built from the innermost (AC_DIM, AC_ARRAY).
AG_DSTK EQU  AG_BASE+$17       ; AG_DCAP words: the bounds.
AG_DCAP EQU  8                 ; Dimensions of one array type; DG_BOUND beyond.
AG_STEND EQU  AG_DSTK+2*AG_DCAP ; End of the aggregate scalars.

; The type table: one four-byte descriptor per aggregate type, interned so
; that equal types share an ID. AG_NKIND..AG_NDIM is built in the same
; shape and compared or copied as a block.
AG_TTAB EQU  AG_STEND          ; First type descriptor.
AG_TLEN EQU  4                 ; Bytes in one descriptor.
AG_TCAP EQU  24                ; Descriptors; DG_META when exceeded.
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
AG_RCAP EQU  16                ; Record types; DG_META when exceeded.
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
; ordinals, so they stay below $40. The spellings are in KEYWORDS.ASM.

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
TK_OR EQU  10                  ; Keyword or.
TK_FAIL EQU  11                ; Keyword fail.
TK_END EQU  12                 ; Keyword end.
TK_VAR EQU  13                 ; Keyword var.
TK_AS EQU  14                  ; Keyword as.
TK_U8 EQU  15                  ; Keyword u8.
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
TK_STAR EQU  26                ; Asterisk: multiplication.
TK_U16 EQU  27                 ; Keyword u16.
TK_BOOL EQU  28                ; Keyword boolean.
TK_TRUE EQU  29                ; Keyword true.
TK_FALSE EQU  30               ; Keyword false.
TK_CONST EQU  31               ; Keyword const.
TK_SLASH EQU  32               ; Slash: division.
TK_LT EQU  33                  ; Less than.
TK_LE EQU  34                  ; Less than or equal.
TK_GT EQU  35                  ; Greater than.
TK_GE EQU  36                  ; Greater than or equal.
TK_NE EQU  37                  ; Not equal.
TK_NOT EQU  38                 ; Keyword not.
TK_AND EQU  39                 ; Keyword and.
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
TK_DOT EQU  50                 ; Full stop: field selection.
TK_HANDL EQU  51               ; Keyword handle.
; Ordinal 52 is intentionally unused so later token ordinals remain stable.
TK_XOR EQU  53                 ; Keyword xor.
TK_MOD EQU  54                 ; Keyword mod.
TK_ASSRT EQU  55               ; Keyword assert.

; Diagnostic numbers, as DG_CODE reports them and the shell prints them.
; Only the numbers some path raises are named; the gaps are Nucleus
; diagnostics this compiler cannot produce.

DG_LEX EQU  1                  ; A byte or literal the tokenizer refuses.
DG_INUSE EQU  36               ; An active loop counter written or reused.
DG_TOP EQU  37                 ; No main, or not a top-level declaration.
DG_SINK EQU  40                ; The transcript is full.
DG_REACH EQU  41               ; A relative branch out of range.
DG_UNMET EQU  54               ; A forward routine never defined.
DG_DUP EQU  55                 ; A name declared twice.
DG_SYMS EQU  56                ; The symbol table is full.
DG_UNDEF EQU  57               ; A name not declared.
DG_VALUE EQU  58               ; A scalar value expected.
DG_TYPE EQU  59                ; A type expected.
DG_CLASH EQU  60               ; Operand types do not agree.
DG_RANGE EQU  61               ; An exact value outside its type.
DG_ZERO EQU  62                ; Division by an exact zero.
DG_TRUNC EQU  63               ; An exact u8(...) that loses bits.
DG_CHAIN EQU  64               ; Comparisons chained without and/or.
DG_DEEP EQU  65                ; Expressions or calls nested too deep.
DG_ANDOR EQU  66               ; and/or nested too deep.
DG_BUG EQU  67                 ; An internal inconsistency.
DG_NEST EQU  68                ; Control statements nested too deep.
DG_LABEL EQU  69               ; Control labels exhausted.
DG_FIXUP EQU  70               ; The branch fixup table is full.
DG_LOOP EQU  72                ; exit or continue outside a loop.
DG_COUNT EQU  73               ; An invalid for-loop counter.
DG_STEP EQU  74                ; An invalid for-loop step.
DG_FLOW EQU  75                ; A value routine can end without return.
DG_META EQU  76                ; Type, record or field tables full.
DG_INITS EQU  77               ; Initializers nested too deep.
DG_SHAPE EQU  78               ; An initializer of the wrong shape.
DG_ITEMS EQU  79               ; Too many or too few initializer items.
DG_LONG EQU  80                ; A string literal longer than its type.
DG_DATA EQU  81                ; An object larger than the initializer staging.
; Bounded string capacity is at most 253; use u8[N] plus a scalar length for
; an unterminated, caller-managed buffer.
DG_SIZE EQU  90                ; A string capacity above 253.
DG_FALSE EQU  91               ; An assert that is exactly false.
DG_CONST EQU  94               ; Assignment to a read-only object.
DG_EMPTY EQU  82               ; A record with no fields.
DG_NYI EQU  95                 ; A construct this compiler does not yet compile.
DG_BLOB EQU  96                ; A routine or object too large for the blob buffers.
DG_BOUND EQU  83               ; An array or string bound out of range.

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

; Scalar types and symbol information. An expression's metadata byte and a
; symbol's class/type byte share the low bits: the type in SY_TMASK. The
; symbol byte adds its storage class in SY_CMASK and the flags SY_TYPE and
; SY_AGGR; the metadata byte uses bit 7 as SY_KNOWN instead.

SY_EXACT EQU  0                ; Type: an exact constant not yet typed.
SY_U8 EQU  1                   ; Type: u8.
SY_U16 EQU  2                  ; Type: u16.
SY_BOOL EQU  3                 ; Type: boolean.
SY_TMASK EQU  $03              ; Mask of the type bits.
SY_KNOWN EQU  $80              ; Metadata flag: the value is exact, in HL.
SY_CONST EQU  $00              ; Class: a constant.
SY_GLOB EQU  $04               ; Class: a program variable.
SY_LOCAL EQU  $08              ; Class: a local of the current routine.
SY_PARAM EQU  $0C              ; Class: a parameter of the current routine.
SY_CMASK EQU  $0C              ; Mask of the class bits.
SY_TYPE EQU  $40               ; Symbol flag: the name is a record type.
SY_AGGR EQU  $80               ; Symbol flag: the object is an aggregate.
SY_RTYPE EQU  SY_TYPE          ; Information byte of a record type name.
SY_AGLOB EQU  SY_AGGR+SY_GLOB  ; Information byte of an aggregate variable.

AG_U16 EQU  SY_U16             ; Type ID of u16; IDs 1..3 are the scalars.
AG_FIRST EQU  4                ; First type ID of the type table.
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
AG_VBUF EQU  $7B               ; Type ID of a var u8[] parameter (services).
AG_VIEW EQU  $7C               ; Type ID of an open string parameter.
AG_VVIEW EQU  $7D              ; Type ID of a var string[] parameter (services).

; Relation codes: EXPR.ASM keeps the pending comparison as one of them in
; EX_OPER, and the comparison templates (GENEXPR.ASM) select by it.

EX_EQ EQU  0                   ; Equal.
EX_NE EQU  1                   ; Not equal.
EX_LT EQU  2                   ; Less than.
EX_LE EQU  3                   ; Less than or equal.
EX_GT EQU  4                   ; Greater than.
EX_GE EQU  5                   ; Greater than or equal.
