; Fixed compiler state for the scalar-local, counted-loop, and array slice.

PR_BASE EQU  MM_WBASE

SRC_ID EQU  PR_BASE+$00
SRC_PTR EQU  PR_BASE+$01
SRC_END EQU  PR_BASE+$03
SRC_POS EQU  PR_BASE+$05
SRC_LINE EQU  PR_BASE+$07
SRC_COL EQU  PR_BASE+$09
TK_LIVE EQU  PR_BASE+$0B
TK_NEST EQU  PR_BASE+$0C

TK_POS EQU  PR_BASE+$0D
TK_LINE EQU  PR_BASE+$0F
TK_COL EQU  PR_BASE+$11
TK_PTR EQU  PR_BASE+$13
TK_LEN EQU  PR_BASE+$15

DG_CODE EQU  PR_BASE+$16
DG_PART EQU  PR_BASE+$17
DG_POS EQU  PR_BASE+$18
DG_LINE EQU  PR_BASE+$1A
DG_COL EQU  PR_BASE+$1C

; A diagnostic ends parsing, so the live semantic sink may reuse the eventual
; offset and line fields. DG_CODE and DG_PART remain clear on
; successful compilation; an error overwrites all reused bytes before return.
; The high byte of DG_LINE and both bytes of DG_COL extend
; past PR_STEND into the dead semantic buffer. The diagnostic is
; terminal, so no semantic byte remains live.
TR_PTR EQU  PR_BASE+$18
TR_CNT EQU  PR_BASE+$1A

; Emission begins only after parsing succeeds. Its scratch words therefore
; overlay dead source, token, diagnostic, and sink fields. SRC_ID and
; TK_POS..TK_COL remain intact for an emitter diagnostic.
EM_PTR EQU  PR_BASE+$03
EM_ORG EQU  PR_BASE+$05
EM_HEAD EQU  PR_BASE+$07
EM_XFIX EQU  PR_BASE+$09
EM_FFIX EQU  PR_BASE+$0B
EM_UFIX EQU  PR_BASE+$19
EM_FIXAT EQU  PR_BASE+$13
EM_LIM EQU  PR_BASE+$15
EM_DFIX EQU  PR_BASE+$17

PR_STEND EQU  PR_BASE+$1B
TR_BASE EQU  PR_STEND
TR_BODY EQU  TR_BASE+1
; The leading byte is an operation count and the remaining 511 bytes are a
; bounded variable-width transcript. Word aggregate operands must not make the
; complete Chapter 21 program depend on the retired byte-extent encoding.
TR_LIM EQU  TR_BASE+$200

; Host-only source-map trace ports. Every instruction that uses these equates
; is conditionally absent unless the target compiler sets DebugHooks to one.
; OUT (n),A exposes the full port as (A << 8) | n; hosts classify the low byte.
DT_SRC EQU  $D8
DT_DECL EQU  $D9
DT_PUSH EQU  $DA
DT_POP EQU  $DB
DT_SUB EQU  $DC
DT_BEGIN EQU  $DD
DT_DONE EQU  $DE
DT_BYTE EQU  $DF

; One retained forward signature is enough for the first routine-call slice.
; The source bytes remain stable, so exact names are retained as pointer/length
; pairs rather than copied into another buffer.
PR_FNAME EQU  TR_LIM+$00
PR_FNLEN EQU  TR_LIM+$02
PR_FARG EQU  TR_LIM+$03
PR_FALEN EQU  TR_LIM+$05
PR_FORD EQU  TR_LIM+$06
PR_FDONE EQU  TR_LIM+$07
PR_FTYPE EQU  TR_LIM+$08
PR_FRES EQU  TR_LIM+$09

; The predictive expression path keeps one token of lookahead. $FF denotes an
; empty lookahead cell; token ordinals occupy the low half of the byte range.
PR_LKIND EQU  TR_LIM+$0A
PR_LVAL EQU  TR_LIM+$0B

; Source bytes remain resident through compilation, so a scalar symbol keeps
; the exact spelling as a pointer and length instead of copying name bytes.
; The entry at SY_CNT is provisional until the declaration initializer
; succeeds; lookup sees only the committed prefix.
SY_CNT EQU  TR_LIM+$0D
SY_LSLOT EQU  TR_LIM+$0E
SY_GSLOT EQU  TR_LIM+$0F
SY_BASE EQU  TR_LIM+$10
SY_RECB EQU  6
SY_CAP EQU  16
SY_LIM EQU  SY_BASE+SY_RECB*SY_CAP

; Expression metadata is deliberately explicit in the correctness build.
; A bounded stack retains the left operand of recursive expression parses;
; each entry is metadata plus a constant value word. The later compression
; pass may overlay this state once its liveness has been measured.
EX_WANT EQU  SY_LIM+$00
EX_LIVE EQU  SY_LIM+$01
EX_QUIET EQU  SY_LIM+$02
EX_DEPTH EQU  SY_LIM+$03
EX_RMETA EQU  SY_LIM+$04
EX_RVAL EQU  SY_LIM+$05
EX_LMETA EQU  SY_LIM+$07
EX_LVAL EQU  SY_LIM+$08
EX_OPER EQU  SY_LIM+$0A
EX_OPPOS EQU  SY_LIM+$0B
AC_DINFO EQU  SY_LIM+$0D
AC_DVAL EQU  SY_LIM+$0E
AC_DNAME EQU  SY_LIM+$10
AC_DLEN EQU  SY_LIM+$12
EX_CPOS EQU  SY_LIM+$13
AC_DPOS EQU  SY_LIM+$15            ; offset, line, column
EX_VPOS EQU  SY_LIM+$1B            ; offset, line, column
EX_LPOSP EQU  SY_LIM+$21
EX_STACK EQU  SY_LIM+$23
EX_STCAP EQU  16
EX_STLEN EQU  13
EX_STLIM EQU  EX_STACK+EX_STCAP*EX_STLEN

; Boolean short-circuit emission retains one forward patch per nesting level.
GX_BCNT EQU  EX_STLIM+$00
GX_BBASE EQU  EX_STLIM+$01
GX_BCAP EQU  16
GX_BLIM EQU  GX_BBASE+GX_BCAP*2

; Structured-control parsing and Z80 emission occur in disjoint phases.
; The parser uses bounded ten-byte control frames; after successful parsing the
; Z80 backend reuses the same region for absolute labels and branch fixups.
CT_BASE EQU  GX_BLIM
CT_DEPTH EQU  CT_BASE+$00
CT_LABNO EQU  CT_BASE+$01
CT_GLOBS EQU  CT_BASE+$02
CT_RKIND EQU  CT_BASE+$03
CT_RTYPE EQU  CT_BASE+$04
CT_FALLS EQU  CT_BASE+$05
CT_FTAB EQU  CT_BASE+$08
CT_FLEN EQU  10
CT_FCAP EQU  8
CT_FLIM EQU  CT_FTAB+CT_FLEN*CT_FCAP

CT_KIF EQU  1
CT_KLOOP EQU  2
CT_KFOR EQU  3
CT_KTRAP EQU  4
CT_RNONE EQU  0
CT_RVAL EQU  1
CT_RDEST EQU  31
CT_FKIND EQU  0
CT_FDEST EQU  1
CT_FCONT EQU  2
CT_FEXIT EQU  3
CT_FVAR EQU  4
CT_FMODE EQU  5
CT_FSTEP EQU  6
CT_FTRAP EQU  8
CT_NOVAR EQU  $FF

GC_FCNT EQU  CT_BASE+$00
GC_VALID EQU  CT_BASE+$01
GC_LCAP EQU  32
GC_LADDR EQU  GC_VALID+GC_LCAP
GC_FTAB EQU  GC_LADDR+GC_LCAP*2
GC_FLEN EQU  3
GC_FCAP EQU  32
GC_FLIM EQU  GC_FTAB+GC_FLEN*GC_FCAP
; Published program metadata must survive source parsing. It therefore cannot
; overlay SRC_PTR as the earlier non-atomic slices did.
EM_GCODE EQU  GC_FLIM
; Four target-adapter segments. Each retained entry is base then exclusive
; limit. Code and rodata have published image bytes;
; data and bss describe runtime storage initialized by the generated startup.
EM_GRO EQU  EM_GCODE+2
EM_GDATA EQU  EM_GRO+2
EM_GBSS EQU  EM_GDATA+2
EM_PCODE EQU  EM_GBSS+2
EM_PRO EQU  EM_PCODE+2
EM_PDATA EQU  EM_PRO+2
EM_PBSS EQU  EM_PDATA+2
EM_STAB EQU  EM_PBSS+2
EM_STLEN EQU  4
EM_STCAP EQU  4
EM_STLIM EQU  EM_STAB+EM_STLEN*EM_STCAP
EM_SLO EQU  0
EM_SHI EQU  2
EM_SCODE EQU  0
EM_SRO EQU  1
EM_SDATA EQU  2
EM_SBSS EQU  3
EM_ECODE EQU  EM_STAB+EM_STLEN*EM_SCODE
EM_ERO EQU  EM_STAB+EM_STLEN*EM_SRO
EM_EDATA EQU  EM_STAB+EM_STLEN*EM_SDATA
EM_EBSS EQU  EM_STAB+EM_STLEN*EM_SBSS
EM_ROPTR EQU  EM_STLIM             ; word
PR_BSS EQU  EM_ROPTR+2             ; word
EM_WEND EQU  PR_BSS+2

; Stage 6 retains aggregate type and layout metadata for the complete
; compilation. Type IDs 1..3 are the predefined scalars; IDs 4 and above name
; bounded four-byte descriptors. Record field offsets remain live for the
; later selection stage, while the complete static image survives into Z80
; emission.
AG_BASE EQU  EM_WEND
AG_MODE EQU  AG_BASE+$00
AG_TCNT EQU  AG_BASE+$01
AG_RCNT EQU  AG_BASE+$02
AG_FCNT EQU  AG_BASE+$03
AG_LEVEL EQU  AG_BASE+$04
; Nonzero once an explicit initializer has supplied at least one value. The
; value is a Boolean allocation choice, not a retained element count.
AG_GIVEN EQU  AG_BASE+$05
AG_CTYPE EQU  AG_BASE+$06
AG_CFIDX EQU  AG_BASE+$07
AG_CFCNT EQU  AG_BASE+$08
AG_CSIZE EQU  AG_BASE+$09          ; word
AG_OPOS EQU  AG_BASE+$0B           ; word
AG_OSIZE EQU  AG_BASE+$0D          ; word
AG_NKIND EQU  AG_BASE+$0F
AG_NAUX EQU  AG_BASE+$10
AG_NDIM EQU  AG_BASE+$11           ; word
AG_NSIZE EQU  AG_BASE+$13          ; word
AG_OEND EQU  AG_BASE+$15           ; word
AG_STEND EQU  AG_BASE+$17

AG_TTAB EQU  AG_STEND
AG_TLEN EQU  4
AG_TCAP EQU  8
AG_TLIM EQU  AG_TTAB+AG_TLEN*AG_TCAP
AG_TKIND EQU  0
AG_TAUX EQU  1
AG_TDIM EQU  2                     ; word
; Every dynamic type retains its complete nonzero extent as a word. Strings
; remain byte-capacity values, while arrays and records may occupy the complete
; selected program-data region.
AG_XTAB EQU  AG_TLIM
AG_XLIM EQU  AG_XTAB+2*AG_TCAP

AG_RTAB EQU  AG_XLIM
AG_RLEN EQU  2
AG_RCAP EQU  5
AG_RLIM EQU  AG_RTAB+AG_RLEN*AG_RCAP
AG_RFIDX EQU  0
AG_RFCNT EQU  1

AG_FTAB EQU  AG_RLIM
AG_FLEN EQU  6
AG_FCAP EQU  12
AG_FLIM EQU  AG_FTAB+AG_FLEN*AG_FCAP
AG_FNAME EQU  0
AG_FNLEN EQU  2
AG_FTYPE EQU  3
AG_FPOS EQU  4                     ; word

; One type ID per ordinary symbol is enough because the ordinary symbol table
; owns name identity and the payload word owns the program-data offset.
AG_SYTAB EQU  AG_FLIM
AG_SYLIM EQU  AG_SYTAB+SY_CAP

AG_DLEN EQU  AG_SYLIM              ; word
AG_ROLEN EQU  AG_DLEN+2            ; word
; One complete object is built in scratch. Published rodata keeps initialized
; data first and aggregate-constant bytes in a read-only suffix.
AG_IBUF EQU  AG_ROLEN+2
AG_ICAP EQU  1024
AG_DATA EQU  AG_IBUF+AG_ICAP
AG_DCAP EQU  1024
AG_DLIM EQU  AG_DATA+AG_DCAP
AG_WEND EQU  AG_DLIM
PR_WEND EQU  AG_WEND

AG_LCAP EQU  4

; Emission follows successful parsing and may overlay the retained forward.
EM_READP EQU  PR_FNAME
EM_ENTRY EQU  PR_FARG
EM_CFIX EQU  PR_FALEN
EM_IFIX EQU  PR_FORD

TK_EOF EQU  0
TK_EOL EQU  1
TK_NAME EQU  2
TK_CHAR EQU  3
TK_NUM EQU  4
TK_LPAR EQU  5
TK_RPAR EQU  6
TK_EQ EQU  7
TK_SUB EQU  8
TK_FAILS EQU  9
TK_OR EQU  10
TK_FAIL EQU  11
TK_END EQU  12
TK_VAR EQU  13
TK_AS EQU  14
TK_U8 EQU  15
TK_FOR EQU  16
TK_UNTIL EQU  17
TK_LBRAC EQU  18
TK_RBRAC EQU  19
TK_COMMA EQU  20
TK_FORW EQU  21
TK_RET EQU  22
TK_IF EQU  23
TK_MINUS EQU  24
TK_PLUS EQU  25
TK_STAR EQU  26
TK_U16 EQU  27
TK_BOOL EQU  28
TK_TRUE EQU  29
TK_FALSE EQU  30
TK_CONST EQU  31
TK_SLASH EQU  32
TK_LT EQU  33
TK_LE EQU  34
TK_GT EQU  35
TK_GE EQU  36
TK_NE EQU  37
TK_NOT EQU  38
TK_AND EQU  39
TK_ELSIF EQU  40
TK_ELSE EQU  41
TK_WHILE EQU  42
TK_TO EQU  43
TK_STEP EQU  44
TK_EXIT EQU  45
TK_CONT EQU  46
TK_TEXT EQU  47
TK_REC EQU  48
TK_STR EQU  49
TK_DOT EQU  50
TK_HANDL EQU  51
; Ordinal 52 is intentionally unused so later token ordinals remain stable.
TK_XOR EQU  53
TK_MOD EQU  54
TK_ASSRT EQU  55

DG_NONE EQU  0
DG_LEX EQU  1
DG_MAIN EQU  17
DG_WRITE EQU  22
DG_INDEX EQU  29
DG_INUSE EQU  36
DG_TOP EQU  37
DG_BYTES EQU  38
DG_DIM EQU  39
DG_SINK EQU  40
DG_REACH EQU  41
DG_READ EQU  45
DG_DATUM EQU  51
DG_RTYPE EQU  52
DG_PROTO EQU  53
DG_UNMET EQU  54
DG_DUP EQU  55
DG_SYMS EQU  56
DG_UNDEF EQU  57
DG_VALUE EQU  58
DG_TYPE EQU  59
DG_CLASH EQU  60
DG_RANGE EQU  61
DG_ZERO EQU  62
DG_TRUNC EQU  63
DG_CHAIN EQU  64
DG_DEEP EQU  65
DG_ANDOR EQU  66
DG_BUG EQU  67
DG_NEST EQU  68
DG_LABEL EQU  69
DG_FIXUP EQU  70
DG_BOOL EQU  71
DG_LOOP EQU  72
DG_COUNT EQU  73
DG_STEP EQU  74
DG_FLOW EQU  75
DG_META EQU  76
DG_INITS EQU  77
DG_SHAPE EQU  78
DG_ITEMS EQU  79
DG_LONG EQU  80
DG_DATA EQU  81
; Bounded string capacity is at most 253; use u8[N] plus a scalar length for
; an unterminated, caller-managed buffer.
DG_SIZE EQU  90
DG_FALSE EQU  91
DG_SEG EQU  92
DG_ROCAP EQU  93
DG_CONST EQU  94
DG_EMPTY EQU  82
DG_BOUND EQU  83

; Ordinary token mismatches encode the token ordinal directly. Named-value
; mismatches retain their context-specific diagnostic codes above.
DG_TOKEN EQU  $80
DG_EOF EQU  DG_TOKEN+TK_EOF
DG_NAME EQU  DG_TOKEN+TK_NAME
DG_EOL EQU  DG_TOKEN+TK_EOL
DG_CHAR EQU  DG_TOKEN+TK_CHAR
DG_NUM EQU  DG_TOKEN+TK_NUM
DG_LPAR EQU  DG_TOKEN+TK_LPAR
DG_RPAR EQU  DG_TOKEN+TK_RPAR
DG_EQ EQU  DG_TOKEN+TK_EQ
DG_SUB EQU  DG_TOKEN+TK_SUB
DG_FAILS EQU  DG_TOKEN+TK_FAILS
DG_OR EQU  DG_TOKEN+TK_OR
DG_KFAIL EQU  DG_TOKEN+TK_FAIL
DG_END EQU  DG_TOKEN+TK_END
DG_VAR EQU  DG_TOKEN+TK_VAR
DG_AS EQU  DG_TOKEN+TK_AS
DG_U8 EQU  DG_TOKEN+TK_U8
DG_FOR EQU  DG_TOKEN+TK_FOR
DG_UNTIL EQU  DG_TOKEN+TK_UNTIL
DG_LBRAC EQU  DG_TOKEN+TK_LBRAC
DG_RBRAC EQU  DG_TOKEN+TK_RBRAC
DG_COMMA EQU  DG_TOKEN+TK_COMMA
DG_FORW EQU  DG_TOKEN+TK_FORW
DG_RET EQU  DG_TOKEN+TK_RET
DG_IF EQU  DG_TOKEN+TK_IF
DG_MINUS EQU  DG_TOKEN+TK_MINUS
DG_PLUS EQU  DG_TOKEN+TK_PLUS
DG_STAR EQU  DG_TOKEN+TK_STAR
DG_TEXT EQU  DG_TOKEN+TK_TEXT

SY_EXACT EQU  0
SY_U8 EQU  1
SY_U16 EQU  2
SY_BOOL EQU  3
SY_TMASK EQU  $03
SY_KNOWN EQU  $80
SY_CONST EQU  $00
SY_GLOB EQU  $04
SY_LOCAL EQU  $08
SY_PARAM EQU  $0C
SY_CMASK EQU  $0C
SY_TYPE EQU  $40
SY_AGGR EQU  $80
SY_RTYPE EQU  SY_TYPE
SY_AGLOB EQU  SY_AGGR+SY_GLOB

AG_U8 EQU  SY_U8
AG_U16 EQU  SY_U16
AG_BOOL EQU  SY_BOOL
AG_FIRST EQU  4
AG_KREC EQU  4
AG_KSTR EQU  5
AG_KARR EQU  6
; Parameter-only open bounded-string view. It is never interned in the
; aggregate type table and therefore remains outside its compact ordinals.
AG_VIEW EQU  $7C

SY_CU8 EQU  SY_CONST+SY_U8
SY_C16 EQU  SY_CONST+SY_U16
SY_CBOOL EQU  SY_CONST+SY_BOOL
SY_GU8 EQU  SY_GLOB+SY_U8
SY_G16 EQU  SY_GLOB+SY_U16
SY_GBOOL EQU  SY_GLOB+SY_BOOL
SY_LU8 EQU  SY_LOCAL+SY_U8
SY_L16 EQU  SY_LOCAL+SY_U16
SY_LBOOL EQU  SY_LOCAL+SY_BOOL

OP_VAR8 EQU  1
OP_UNTIL EQU  2
OP_WRITE EQU  3
OP_RAISE EQU  4
OP_LOOP EQU  5
OP_LEAVE EQU  6
OP_ARRAY EQU  7
OP_READ EQU  8
OP_RES8 EQU  9
OP_ELEM8 EQU  10
OP_WRU8 EQU  11
OP_LCALL EQU  12
OP_WRLOC EQU  13
OP_BODY8 EQU  14
OP_IFZ EQU  15
OP_RETP EQU  16
OP_ENDIF EQU  17
OP_RECUR EQU  18
OP_CLOSE EQU  19
OP_DEF8 EQU  20
OP_MAIN EQU  21
OP_LOC8 EQU  22
OP_LIT8 EQU  23
OP_LDG8 EQU  24
OP_LDL8 EQU  25
OP_TIMES EQU  26
OP_PLUS EQU  27
OP_STG8 EQU  28
OP_STL8 EQU  29
OP_WRVAL EQU  30
OP_HALT EQU  31
OP_DEF16 EQU  32
OP_LOC16 EQU  33
OP_LIT16 EQU  34
OP_LDG16 EQU  35
OP_LDL16 EQU  36
OP_ADD8 EQU  37
OP_ADD16 EQU  38
OP_SUB8 EQU  39
OP_SUB16 EQU  40
OP_MUL8 EQU  41
OP_MUL16 EQU  42
OP_DIV8 EQU  43
OP_DIV16 EQU  44
OP_NEG8 EQU  45
OP_NEG16 EQU  46
OP_NOT8 EQU  47
OP_NOT16 EQU  48
OP_LNOT EQU  49
OP_AND8 EQU  50
OP_AND16 EQU  51
OP_OR8 EQU  52
OP_OR16 EQU  53
OP_XOR8 EQU  54
OP_XOR16 EQU  55
OP_MOD8 EQU  56
OP_MOD16 EQU  57
OP_CMP8 EQU  58
OP_CMP16 EQU  59
OP_LCMP EQU  60
OP_TRUNC EQU  61
OP_STG16 EQU  62
OP_STL16 EQU  63
OP_CAND EQU  64
OP_COR EQU  65
OP_JOIN EQU  66
OP_LABEL EQU  67
OP_IFNOT EQU  68
OP_JUMP EQU  69
OP_FOR EQU  70
OP_TEST EQU  71
OP_NEXT EQU  72
OP_CLEAN EQU  73
OP_FUNC EQU  74
OP_LDP8 EQU  75
OP_LDP16 EQU  76
OP_FCALL EQU  77
OP_RET EQU  78
OP_STP8 EQU  79
OP_STP16 EQU  80
OP_ENDFN EQU  81

EX_EQ EQU  0
EX_NE EQU  1
EX_LT EQU  2
EX_LE EQU  3
EX_GT EQU  4
EX_GE EQU  5
