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
;    +$ACA     44  routine state: counts, the signature being parsed, the
;                  body's block, the declaration's part and visibility,
;                  the private symbols, the call being checked and the
;                  path in hand (RO_BASE)
;    +$AF6    384  routine table: 32 records of twelve bytes (RO_RTAB)
;    +$C76    256  parameter table: 64 records of four bytes (RO_PTAB)
;    +$D76     96  the routine's string literals: 16 of six bytes (RO_LTAB)
;    +$DD6      5  the source cursor's part state (SRC_PTAB, SRC_PCNT,
;                  SRC_NUM, SRC_OWE)
;    +$DDB      2  PR_SP, the stack DG_ISSUE restores
;    +$DDD     65  the LL(1) stack (LL_DEPTH, LL_STACK)
;    +$E1E         LL_WEND, the end of the compiler workspace, 3,614 bytes
;
;  PR_PARSE clears RO_BASE..RO_STEND before parsing; the tables are written
;  before they are read. ACTIONS.ASM writes the signature, body and
;  failure-routing fields as the grammar's actions run; ROUTINES.ASM writes
;  the tables; CALLS.ASM the path in hand (RO_PLACE), which GENAGGR.ASM
;  moves on, and RO_ESC, which EXTERM.ASM's names set too; GENAGGR.ASM the
;  literals, which RG_OPEN clears for each routine; EXPR.ASM clears RO_PEND
;  for each expression and RO_FAILS (CALLS.ASM) sets it and RO_KEPT. Source
;  names stay resident, so a record keeps a name as its address and length.
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
;  The source cursor's part state belongs to SOURCE.ASM: the part table's
;  top (SRC_PTAB) and count (SRC_PCNT), which the START overlay sets, the
;  current part's number in the stream (SRC_NUM) and whether the line end
;  owed at a part boundary has been returned (SRC_OWE). The tokenizer's
;  TK_ATEND steps to the next part.
;
;  Visibility (ACTSUB.ASM, D33): AC_DPART is the part of the declaration
;  being parsed, AC_PRIV nonzero while a private one is, and SY_PRIV a bit
;  for each private symbol, whose name its part's end hides.

RO_BASE EQU  AG_WEND           ; First byte of the routine state.
RO_RCNT EQU  RO_BASE+$00       ; Byte: routine records completed (AC_PUB).
RO_PCNT EQU  RO_BASE+$01       ; Byte: parameter records used (RO_ENROL).
RO_CUR EQU  RO_BASE+$02        ; Byte: index of the routine being compiled, $FF for main.
RO_CTYPE EQU  RO_BASE+$03      ; Byte: its result type ordinal, zero for none.
RO_CPIDX EQU  RO_BASE+$04      ; Byte: its first parameter record.
RO_CPCNT EQU  RO_BASE+$05      ; Byte: its parameters so far.
RO_GLOBS EQU  RO_BASE+$06      ; Byte: SY_CNT as a body opens; AC_END drops locals to it.
RO_DEPTH EQU  RO_BASE+$07      ; Byte: calls whose arguments are being parsed.
RO_CFLAG EQU  RO_BASE+$08      ; Byte: flags of the routine being compiled.
RO_PEND EQU  RO_BASE+$09       ; Byte: $80 and a failure's label while it is unconsumed.
RO_KEPT EQU  RO_BASE+$0A       ; Byte: temporaries' bytes beneath a handled call.
RO_MFLAG EQU  RO_BASE+$0B      ; Byte: main's flags, as main has no routine record.
RO_CARGS EQU  RO_BASE+$0C      ; Byte: the routine's argument bytes, removed by RETN.
RO_ESC EQU  RO_BASE+$0D        ; Byte: nonzero when the last path's root is in the frame.
RO_LCNT EQU  RO_BASE+$0E       ; Byte: string literals of the routine (RO_LTAB).
RO_CALLP EQU  RO_BASE+$0F      ; Word: the offset of the call just parsed (RO_FAILS).
RO_BODY EQU  RO_BASE+$11       ; Byte: the body's first symbol plus one, zero outside one.
AC_DPART EQU  RO_BASE+$12      ; Byte: SRC_ID of the top-level declaration being parsed.
AC_PRIV EQU  RO_BASE+$13       ; Byte: nonzero while a private declaration is parsed.
SY_PRIV EQU  RO_BASE+$14       ; SY_CAP/8 bytes: a bit for each private symbol.
; The path in hand (GENAGGR.ASM): its place and type, as the reference's
; Designator holds them, and the position of the index being parsed. The
; fourteen bytes are kept on the machine stack across a nested parse.
RO_PLACE EQU  SY_PRIV+SY_CAP/8 ; First byte of the path's block.
RO_PKIND EQU  RO_PLACE+0       ; Byte: GA_BLOB, GA_FRAME, GA_ALIAS or GA_HELD.
RO_PRO EQU  RO_PLACE+1         ; Byte: nonzero when the path is read-only.
RO_PBASE EQU  RO_PLACE+2       ; Word: a static place's blob, an alias's word at IX+n.
RO_PADD EQU  RO_PLACE+4        ; Word: bytes on from the base, or a frame place's offset.
RO_OTYPE EQU  RO_PLACE+6       ; Byte: type of the path, operand or parameter in hand.
RO_PPUSH EQU  RO_PLACE+7       ; Byte: nonzero when an index's computed base is pushed.
RO_IPOS EQU  RO_PLACE+8        ; Word: the offset of the index's first token.
RO_PROOT EQU  RO_PLACE+10      ; Word: the root's symbol record, for its name.
RO_PWORD EQU  6                ; Words in the block, RO_PLACE to RO_STEND.
RO_STEND EQU  RO_PLACE+12      ; End of the routine state; the tables follow.
GA_BLOB EQU  0                 ; Place: static, in a blob.
GA_FRAME EQU  1                ; Place: the frame, at IX+offset.
GA_ALIAS EQU  2                ; Place: through an address word in the frame.
GA_HELD EQU  3                 ; Place: computed, in HL.

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

; The string literals of the routine being compiled (GENAGGR.ASM), placed
; after its need word when it closes. An entry is six bytes: the address of
; its operand's addend word among the references, the source address of
; its opening quote, its decoded length and the bytes it occupies.
RO_LTAB EQU  RO_PLIM           ; Literal table: RO_LCAP entries.
RO_LLEN EQU  6                 ; Bytes in one literal entry.
RO_LCAP EQU  16                ; Literals in one routine; DG_LITS beyond.
RO_LLIM EQU  RO_LTAB+RO_LLEN*RO_LCAP ; Exclusive end of the literal table.
RO_WEND EQU  RO_LLIM           ; End of the routine workspace.

; The part table and the source bytes stay outside the compiler workspace,
; at the top and the base of the source area, so the cursor keeps only
; these five bytes (SOURCE.ASM).
SRC_PTAB EQU  RO_WEND          ; Word: the part table's top, above part 0.
SRC_PCNT EQU  SRC_PTAB+2       ; Byte: the parts in the table.
SRC_NUM EQU  SRC_PCNT+1        ; Byte: the current part's number in the stream.
SRC_OWE EQU  SRC_NUM+1         ; Byte: nonzero once a part's last line end is returned.
SRC_WEND EQU  SRC_OWE+1        ; End of the source cursor.
; PR_BUILD saves the caller's SP here, so that a diagnostic (DG_ISSUE)
; returns straight to the caller from any depth of the parse; the START
; overlay does the same while it loads the parts.
PR_SP EQU  SRC_WEND            ; Word: SP that DG_ISSUE restores.

RO_MAIN EQU  $FE               ; RO_FIND's index for main, which has no record.
RO_FFAIL EQU  1                ; Routine flag: it can fail.
RO_FMAIN EQU  2                ; Routine flag: it is main.
RO_FOPEN EQU  4                ; Routine flag: a forward still awaiting its body.
RO_FFWD EQU  8                 ; Routine flag: declared forward; it checks the stack.
RO_FWIDE EQU  $10              ; Service flag: a u32 makes it one not yet called.
RO_FPRIV EQU  $20              ; Routine flag: private, hidden when its part ends.

