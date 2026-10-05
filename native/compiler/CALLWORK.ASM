;==========================================================================
;  Routine, call and source-part workspace
;==========================================================================
;
;  The second part of the compiler workspace, which continues STATE.ASM's
;  at AG_WEND, and the constants of routines, calls, services and the
;  multipart source, then the parse driver's saved SP and the LL(1) stack
;  (LL1.ASM) to LL_WEND, the end of the compiler workspace. Offsets are
;  from MM_WBASE ($4800).
;
;    Offset  Size  Block
;    +$963     22  routine state: counts, the signature being parsed, the
;                  path and the call being checked (RO_BASE)
;    +$979    384  routine table: 32 records of twelve bytes (RO_RTAB)
;    +$AF9    256  parameter table: 64 records of four bytes (RO_PTAB)
;    +$BF9      3  multipart source cursor (SRC_DESC, SRC_LEFT)
;    +$BFC      2  PR_SP, the stack DG_ISSUE restores
;    +$BFE     65  the LL(1) stack (LL_DEPTH, LL_STACK)
;    +$C3F         LL_WEND, the end of the compiler workspace, 3,135 bytes
;
;  PR_PARSE clears RO_BASE..RO_STEND before parsing; the tables are written
;  before they are read. ACTIONS.ASM writes the signature, body and
;  failure-routing fields as the grammar's actions run; ROUTINES.ASM writes
;  the tables and the path and call fields; EXPR.ASM clears RO_PEND for
;  each expression and RO_FAILS (CALLS.ASM) sets it and RO_KEPT. Source names
;  stay resident, so a record keeps a name as its address and length.
;
;  A routine record (RO_RLEN bytes), one per declared routine other than
;  main, in declaration order:
;    +0  word  RO_RNAME  address of the name in the source
;    +2  byte  RO_RNLEN  length of the name
;    +3  byte  RO_RPIDX  parameter record of its first parameter
;    +4  byte  RO_RPCNT  number of parameters
;    +5  byte  RO_RTYPE  result type ordinal, zero for none
;    +6  byte  RO_RFLAG  RO_FFAIL, RO_FOPEN and RO_FFWD
;    +7  word  RO_RORD   its blob's ordinal
;    +9  word  RO_RNEED  its need, zero until its body is complete
;    +11 byte  RO_RARGS  the bytes of its arguments, which RETN removes
;  AC_SIG writes the name and the first parameter when a signature begins;
;  AC_PUB writes the rest, taking the routine's ordinal, and counts the
;  record in RO_RCNT. A forward is published with RO_FOPEN and RO_FFWD set,
;  so it takes its ordinal where it is declared, and AC_IMPL clears RO_FOPEN
;  when the body comes; AC_END writes the need. RO_FIND, RO_VET and RO_CALL
;  read the records through RO_SUBAT.
;
;  A parameter record (RO_PLEN bytes); every signature's parameters are
;  appended in order, so a routine's are RO_RPCNT records from RO_RPIDX:
;    +0 word  RO_PNAME  address of the name in the source
;    +2 byte  RO_PNLEN  length of the name
;    +3 byte  RO_PTYPE  type ordinal
;  RO_ENROL appends one; RO_BIND, RO_DISP and RO_CALL read them through
;  RO_PARAM.
;
;  A call whose arguments are being parsed keeps its routine and its next
;  parameter on the machine stack, so that a call inside an argument cannot
;  overwrite the call around it; RO_DEPTH counts them, at most RO_NCAP.
;
;  The multipart cursor belongs to SOURCE.ASM: SRC_LOAD keeps the address
;  of the next part's descriptor in SRC_DESC, SRC_OPEN sets SRC_LEFT, the
;  tokenizer's TK_ATEND advances it at each part boundary. SRC_LEFT packs three fields:
;    bits 0..2  parts still to come (SRC_CNT)
;    bits 3..5  manifest ordinal of the current part (SRC_ORD)
;    bit 7      the line end owed at the part boundary has been returned
;  With SRC_CAP 8, the count and the ordinal each fit three bits exactly.

RO_BASE EQU  AG_WEND           ; First byte of the routine state.
RO_RCNT EQU  RO_BASE+$00       ; Byte: routine records completed (AC_PUB).
RO_PCNT EQU  RO_BASE+$01       ; Byte: parameter records used (RO_ENROL).
RO_CUR EQU  RO_BASE+$02        ; Byte: index of the routine being compiled, $FF for main.
RO_CTYPE EQU  RO_BASE+$03      ; Byte: its result type ordinal, zero for none.
RO_CPIDX EQU  RO_BASE+$04      ; Byte: its first parameter record.
RO_CPCNT EQU  RO_BASE+$05      ; Byte: its parameters so far.
RO_GLOBS EQU  RO_BASE+$06      ; Byte: SY_CNT as a body opens; AC_END drops locals to it.
RO_OTYPE EQU  RO_BASE+$07      ; Byte: type of the path, operand or parameter in hand.
RO_OSIZE EQU  RO_BASE+$08      ; Word: element or aggregate size of the path in hand.
RO_OPOS EQU  RO_BASE+$0A       ; Word: a field offset or an array's length.
RO_ACNT EQU  RO_BASE+$0C       ; Byte: scratch for paths and returns.
RO_DPOS EQU  RO_BASE+$0D       ; Word: source offset of an index or statement.
RO_DEPTH EQU  RO_BASE+$0F      ; Byte: calls whose arguments are being parsed.
RO_CFLAG EQU  RO_BASE+$10      ; Byte: flags of the routine being compiled.
RO_PEND EQU  RO_BASE+$11       ; Byte: $80 and a failure's label while it is unconsumed.
RO_KEPT EQU  RO_BASE+$12       ; Byte: temporaries' bytes beneath a handled call.
RO_MFLAG EQU  RO_BASE+$13      ; Byte: main's flags, as main has no routine record.
RO_VCAP EQU  RO_BASE+$14       ; Byte: offset of an open string's capacity word.
RO_CARGS EQU  RO_BASE+$15      ; Byte: the routine's argument bytes, removed by RETN.
RO_STEND EQU  RO_BASE+$16      ; End of the routine state; the tables follow.

RO_RTAB EQU  RO_STEND          ; Routine table: RO_RCAP records.
RO_RLEN EQU  12                ; Bytes in one routine record.
RO_RCAP EQU  32                ; Routines besides main; DG_PROCS beyond.
RO_RLIM EQU  RO_RTAB+RO_RLEN*RO_RCAP ; Exclusive end of the routine table.
RO_RNAME EQU  0                ; Word: address of the routine's name.
RO_RNLEN EQU  2                ; Byte: length of the name.
RO_RPIDX EQU  3                ; Byte: its first parameter record.
RO_RPCNT EQU  4                ; Byte: its number of parameters.
RO_RTYPE EQU  5                ; Byte: its result type ordinal, zero for none.
RO_RFLAG EQU  6                ; Byte: its flags.
RO_RORD EQU  7                 ; Word: its blob's ordinal.
RO_RNEED EQU  9                ; Word: its need once its body is complete.
RO_RARGS EQU  11               ; Byte: its arguments' bytes.

RO_PTAB EQU  RO_RLIM           ; Parameter table: RO_PCAP records.
RO_PLEN EQU  4                 ; Bytes in one parameter record.
RO_PCAP EQU  64                ; Parameters of all routines; DG_PARAM beyond.
RO_PLIM EQU  RO_PTAB+RO_PLEN*RO_PCAP ; Exclusive end of the parameter table.
RO_PNAME EQU  0                ; Word: address of the parameter's name.
RO_PNLEN EQU  2                ; Byte: length of the name.
RO_PTYPE EQU  3                ; Byte: its type ordinal.

RO_NCAP EQU  8                 ; Calls nested in arguments; DG_DEEP beyond.
RO_WEND EQU  RO_PLIM           ; End of the routine workspace.

; The shell's descriptor table and the source bytes stay outside the
; compiler workspace, so the adapter keeps only these three bytes.
SRC_DESC EQU  RO_WEND          ; Word: address of the next part's descriptor.
SRC_LEFT EQU  SRC_DESC+2       ; Byte: parts to come, current ordinal, boundary flag.
SRC_WEND EQU  SRC_LEFT+1       ; End of the source cursor.
; PR_BUILD saves the caller's SP here, so that a diagnostic (DG_ISSUE)
; returns straight to the caller from any depth of the parse.
PR_SP EQU  SRC_WEND            ; Word: SP that DG_ISSUE restores.
SRC_DLEN EQU  5                ; Bytes in one part descriptor: identity, start, end.
SRC_CAP EQU  8                 ; Source parts a compilation accepts; DG_FILES beyond.
SRC_CNT EQU  $07               ; SRC_LEFT bits 0..2: parts still to come.
SRC_STEP EQU  8                ; One ordinal step; TK_ATEND adds SRC_STEP-1.
SRC_ORD EQU  $38               ; SRC_LEFT bits 3..5: ordinal of the current part.

RO_MAIN EQU  $FE               ; RO_FIND's index for main, which has no record.
RO_FFAIL EQU  1                ; Routine flag: it can fail.
RO_FMAIN EQU  2                ; Routine flag: it is main.
RO_FOPEN EQU  4                ; Routine flag: a forward still awaiting its body.
RO_FFWD EQU  8                 ; Routine flag: declared forward; it checks the stack.


; Operation codes of routines, calls, aggregates and failure, continuing
; STATE.ASM's. Each comment names the parser routine that writes it and the
; Nucleus handler that once replayed it; TR_OPER refuses them all (DG_NYI).
OP_FIELD EQU  89               ; RO_FIELD: add a field offset; RG_FIELD.
OP_INDEX EQU  90               ; RO_ITEM: checked element address; RG_INDEX.
OP_LDX8 EQU  91                ; RO_LOAD: load a byte through an address; RG_GET8.
OP_LDX16 EQU  92               ; RO_LOAD: load a word through an address; RG_GET16.
OP_STX8 EQU  93                ; RO_LET: store a byte through an address; RG_PUT8.
OP_STX16 EQU  94               ; RO_LET: store a word through an address; RG_PUT16.
OP_COPY EQU  95                ; RO_LET: checked aggregate copy; RG_COPY.
OP_LEN EQU  96                 ; RO_SEL: a bounded string's length; RG_LEN.
OP_CHAR EQU  97                ; RO_CHAR: checked string character; RG_CHAR.
OP_ABORT EQU  99               ; Written by nothing; its slot dispatches to RG_FATAL.
OP_VLEN EQU  108               ; RO_SEL: an open string's length; OS_LEN.
OP_VCHAR EQU  109              ; RO_OSIDX: an open string's character; OS_CHAR.
; Predefined names in KW_NAMES order: six services, refused for now (65.4
; i), then error constants.
RO_ERRS EQU  6                 ; First error constant; constant n has value n-5.

DG_PROCS EQU  84               ; Diagnostic: more than RO_RCAP routines (AC_SIG).
DG_PARAM EQU  85               ; Diagnostic: more than RO_PCAP parameters (RO_ENROL).
DG_LEAK EQU  87                ; Diagnostic: a call's failure is not handled.
DG_FILES EQU  88               ; Diagnostic: part count outside 1 to SRC_CAP.
