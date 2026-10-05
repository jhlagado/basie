;==========================================================================
;  Routine, call and source-part workspace
;==========================================================================
;
;  The second part of the compiler workspace, which continues STATE.ASM's
;  at AG_WEND, and the constants of routines, calls, services and the
;  multipart source. TGTWORK.ASM continues the workspace from SRC_WEND.
;  Offsets are from MM_WBASE ($4800).
;
;    Offset  Size  Block
;    +$D31     30  routine state: counts, the signature being parsed, the
;                  path and the call being checked (RO_BASE)
;                  emit phase: RG_FLAGS..RG_KEPT over its first five bytes
;    +$D4F     32  routine table: four records of eight bytes (RO_RTAB)
;    +$D6F     64  parameter table: sixteen records of four bytes (RO_PTAB)
;    +$DAF     32  call frames: four records of eight bytes (RO_NTAB)
;    +$DCF      3  multipart source cursor (SRC_DESC, SRC_LEFT)
;    +$DD2         SRC_WEND, where TGTWORK.ASM begins
;
;  PR_PARSE clears RO_BASE..RO_WEND before parsing. ACTIONS.ASM writes the
;  signature, body and failure-routing fields as the grammar's actions
;  run; ROUTINES.ASM writes the tables and the path and call fields;
;  EXPR.ASM clears RO_PEND and RO_KEPT for each expression. Source names
;  stay resident, so a record keeps a name as its address and length.
;
;  A routine record (RO_RLEN bytes), one per declared routine other than
;  main, in declaration order:
;    +0 word  RO_RNAME  address of the name in the source
;    +2 byte  RO_RNLEN  length of the name
;    +3 byte  RO_RPIDX  parameter record of its first parameter
;    +4 byte  RO_RPCNT  number of parameters
;    +5 byte  RO_RTYPE  result type ordinal, zero for none
;    +6 byte  RO_RDEST  label of its body: RO_LBASE plus its index
;    +7 byte  RO_RFLAG  RO_FFAIL, RO_FOPEN and the bank in bits 4..5
;  AC_SIG writes the name and the first parameter when a signature begins;
;  AC_PUB writes the rest and counts the record in RO_RCNT. A forward is
;  published with RO_FOPEN set, and AC_IMPL clears it when the body comes.
;  RO_FIND, RO_VET and RO_CALL read the records through RO_SUBAT.
;
;  A parameter record (RO_PLEN bytes); every signature's parameters are
;  appended in order, so a routine's are RO_RPCNT records from RO_RPIDX:
;    +0 word  RO_PNAME  address of the name in the source
;    +2 byte  RO_PNLEN  length of the name
;    +3 byte  RO_PTYPE  type ordinal
;  RO_ENROL appends one; RO_BIND, RO_DISP and RO_CALL read them through
;  RO_PARAM.
;
;  A call frame (RO_NLEN bytes) holds one call whose arguments are being
;  parsed, so that a call inside an argument cannot overwrite the state of
;  the call around it. RO_CALL pushes it and RO_DEPTH counts the frames:
;    +0 byte  RO_NDEST  callee label, plus RO_FKEEP when its result is kept
;    +1 byte  RO_NTYPE  result type ordinal
;    +2 byte  RO_NPIDX  parameter record of the next argument
;    +3 byte  RO_NLEFT  arguments still to parse
;    +4 byte  RO_NACNT  argument carriers: one each, two for an open string
;    +5 word  RO_NPOS   source offset of the call
;    +7 byte  RO_NFLAG  callee flags
;  When the arguments end, RO_CALL copies the top frame into RO_DEST,
;  RO_DTYPE, RO_ACNT, RO_DPOS and RO_DFLAG, pops it and publishes OP_CALL.
;
;  In the emit phase the tables and counts are dead. GENCALL.ASM keeps a
;  call's flags and handling bytes in RG_FLAGS, RG_MODE, RG_HDEST and
;  RG_KEPT over the first five bytes, and reuses the scratch fields
;  RO_OTYPE..RO_DPOS by their own names, as parsing left nothing in them.
;
;  The multipart cursor belongs to SOURCE.ASM: SRC_LOAD keeps the address
;  of the next part's descriptor in SRC_DESC, SRC_OPEN sets SRC_LEFT, the
;  tokenizer's TK_ATEND advances it at each part boundary and TG_HOME reads
;  the current part's ordinal from it. SRC_LEFT packs three fields:
;    bits 0..2  parts still to come (SRC_CNT)
;    bits 3..5  manifest ordinal of the current part (SRC_ORD)
;    bit 7      the line end owed at the part boundary has been returned
;  With SRC_CAP 8, the count and the ordinal each fit three bits exactly.

RO_BASE EQU  AG_WEND           ; First byte of the routine state.
RO_RCNT EQU  RO_BASE+$00       ; Byte: routine records completed (AC_PUB).
RO_PCNT EQU  RO_BASE+$01       ; Byte: parameter records used (RO_ENROL).
RO_CUR EQU  RO_BASE+$02        ; Byte: index of the routine being compiled, $FF for main.
RO_CTYPE EQU  RO_BASE+$03      ; Byte: its result type ordinal, zero for none.
RO_CPIDX EQU  RO_BASE+$04      ; Byte: its first parameter record; RO_BIND's current one.
RO_CPCNT EQU  RO_BASE+$05      ; Byte: its parameters so far.
RO_GLOBS EQU  RO_BASE+$06      ; Byte: SY_CNT as a body opens; AC_END drops locals to it.
RO_OTYPE EQU  RO_BASE+$07      ; Byte: type of the path, operand or parameter in hand.
RO_OSIZE EQU  RO_BASE+$08      ; Word: element or aggregate size of the path in hand.
RO_OPOS EQU  RO_BASE+$0A       ; Word: field offset or array length; a parameter's slot.
RO_AIDX EQU  RO_BASE+$0C       ; Byte: argument index (RO_BIND) or displacement (RG_BIND).
RO_ACNT EQU  RO_BASE+$0D       ; Byte: a completed call's argument carriers; scratch.
RO_DTYPE EQU  RO_BASE+$0E      ; Byte: a completed call's result type ordinal.
RO_DEST EQU  RO_BASE+$0F       ; Byte: a completed call's selector; a body's label.
RO_DPOS EQU  RO_BASE+$10       ; Word: source offset of the call, index or statement.
RO_DEPTH EQU  RO_BASE+$12      ; Byte: call frames in use in RO_NTAB.
RO_CFLAG EQU  RO_BASE+$13      ; Byte: flags of the routine being compiled.
RO_FPOS EQU  RO_BASE+$14       ; Word: source offset of the fail statement (AC_FAIL).
RO_PEND EQU  RO_BASE+$16       ; Byte: nonzero while a call's failure is unrouted.
RO_MODEP EQU  RO_BASE+$17      ; Word: transcript address of a call's handling bytes.
RO_MFLAG EQU  RO_BASE+$19      ; Byte: main's flags, as main has no routine record.
; A statement may hold carriers below a failable result, such as an
; assignment's destination address. The handling bytes record their count
; so that the jump to a handler can discard them first.
RO_KEPT EQU  RO_BASE+$1A       ; Byte: carriers held below a failable result.
RO_IO EQU  RO_BASE+$1B         ; Byte: selector of the service call being parsed.
RO_DFLAG EQU  RO_BASE+$1C      ; Byte: a completed call's callee flags.
RO_VCAP EQU  RO_BASE+$1D       ; Byte: frame slot of an open string's capacity word.
RO_STEND EQU  RO_BASE+$1E      ; End of the routine state; the tables follow.

RO_RTAB EQU  RO_STEND          ; Routine table: RO_RCAP records.
RO_RLEN EQU  8                 ; Bytes in one routine record.
RO_RCAP EQU  4                 ; Routines besides main; DG_PROCS beyond.
RO_RLIM EQU  RO_RTAB+RO_RLEN*RO_RCAP ; Exclusive end of the routine table.
RO_RNAME EQU  0                ; Word: address of the routine's name.
RO_RNLEN EQU  2                ; Byte: length of the name.
RO_RPIDX EQU  3                ; Byte: its first parameter record.
RO_RPCNT EQU  4                ; Byte: its number of parameters.
RO_RTYPE EQU  5                ; Byte: its result type ordinal, zero for none.
RO_RDEST EQU  6                ; Byte: the label of its body.
RO_RFLAG EQU  7                ; Byte: its flags and bank.

RO_PTAB EQU  RO_RLIM           ; Parameter table: RO_PCAP records.
RO_PLEN EQU  4                 ; Bytes in one parameter record.
RO_PCAP EQU  16                ; Parameters of all routines; DG_PARAM beyond.
RO_PLIM EQU  RO_PTAB+RO_PLEN*RO_PCAP ; Exclusive end of the parameter table.
RO_PNAME EQU  0                ; Word: address of the parameter's name.
RO_PNLEN EQU  2                ; Byte: length of the name.
RO_PTYPE EQU  3                ; Byte: its type ordinal.

RO_NTAB EQU  RO_PLIM           ; Call frames: RO_NCAP records.
RO_NLEN EQU  8                 ; Bytes in one call frame.
RO_NCAP EQU  4                 ; Calls nested in arguments; DG_DEEP beyond.
RO_NLIM EQU  RO_NTAB+RO_NLEN*RO_NCAP ; Exclusive end of the call frames.
RO_NDEST EQU  0                ; Byte: callee label and RO_FKEEP.
RO_NTYPE EQU  1                ; Byte: callee result type ordinal.
RO_NPIDX EQU  2                ; Byte: parameter record of the next argument.
RO_NLEFT EQU  3                ; Byte: arguments still to parse.
RO_NACNT EQU  4                ; Byte: argument carriers pushed by the call.
RO_NPOS EQU  5                 ; Word: source offset of the call.
RO_NFLAG EQU  7                ; Byte: callee flags.

RO_WEND EQU  RO_NLIM           ; End of the routine workspace; PR_PARSE clears to here.

; The shell's descriptor table and the source bytes stay outside the
; compiler workspace, so the adapter keeps only these three bytes.
SRC_DESC EQU  RO_WEND          ; Word: address of the next part's descriptor.
SRC_LEFT EQU  SRC_DESC+2       ; Byte: parts to come, current ordinal, boundary flag.
SRC_WEND EQU  SRC_LEFT+1       ; End of the source cursor; TGTWORK.ASM begins.
SRC_DLEN EQU  5                ; Bytes in one part descriptor: identity, start, end.
SRC_CAP EQU  8                 ; Source parts a compilation accepts; DG_FILES beyond.
SRC_CNT EQU  $07               ; SRC_LEFT bits 0..2: parts still to come.
SRC_STEP EQU  8                ; One ordinal step; TK_ATEND adds SRC_STEP-1.
SRC_ORD EQU  $38               ; SRC_LEFT bits 3..5: ordinal of the current part.

; The emit phase begins only after parsing has closed the transcript, so
; GENCALL's call fields overlay the dead routine counts.
RG_BASE EQU  RO_BASE           ; Emit phase: call state over RO_RCNT..RO_CPIDX.
RG_FLAGS EQU  RG_BASE+$00      ; Byte: callee flags (RG_CALL), or a handler's class.
RG_TYPE EQU  RG_BASE+$01       ; Byte: unused; nothing reads or writes it.
RG_MODE EQU  RG_BASE+$02       ; Byte: handling mode of the call (RG_RULES).
RG_HDEST EQU  RG_BASE+$03      ; Byte: label of the call's handler.
RG_KEPT EQU  RG_BASE+$04       ; Byte: carriers held below the call's result.

; Labels: control flow takes 0 to CT_LLIM-1, main's body RO_MDEST, and
; routine n's body RO_LBASE+n, up to 31, the last of GC_LCAP.
RO_LBASE EQU  28               ; Label of the first routine record's body.
; The startup wrapper calls main's body like any routine.
RO_MDEST EQU  27               ; Label of main's callable body.
CT_LLIM EQU  RO_MDEST          ; Labels for control flow; CT_ALLOT stops here.
RO_MAIN EQU  $FE               ; RO_FIND's index for main, which has no record.
RO_FFAIL EQU  1                ; Routine flag: it can fail.
RO_FMAIN EQU  2                ; Routine flag: it is main.
RO_FOPEN EQU  4                ; Routine flag: a forward still awaiting its body.
; A routine's flags and an aggregate constant's symbol class carry the bank
; of the source part that declared it in bits 4..5. Banks matter only when
; the target descriptor names more than one.
TG_BCAP EQU  4                 ; Banks a target descriptor may name.
TG_BMASK EQU  $30              ; Bank field: bits 4..5 (TG_PACK, TG_SPLIT).

; A failable call's handling mode, the first of its three handling bytes.
; Zero means none was attached, which the parser never allows.
RO_MPASS EQU  1                ; Handling: propagate the failure (else fail).
RO_MTRAP EQU  3                ; Handling: jump to the statement's handler.

; Operation codes of routines, calls, aggregates and failure, continuing
; the dense range of GX_OPTAB (GENEXPR.ASM). Each comment names the parser
; routine that writes it and the handler that replays it.
OP_PROC EQU  82                ; AC_BEGIN: open a routine; RG_ENTER.
OP_BIND EQU  83                ; RO_BIND: copy an argument into the frame; RG_BIND.
OP_CALL EQU  84                ; RO_PUB: call a routine or service; RG_CALL.
OP_RETA EQU  85                ; AC_RETOP: return an aggregate; RG_RET.
OP_ENDP EQU  86                ; AC_ENDOP: end a routine that cannot fail; RG_CLOSE.
OP_REFG EQU  87                ; RO_ROOT: push a global's address; RG_GLOB.
OP_REFP EQU  88                ; RO_BYREF: push a parameter's address; RG_PARAM.
OP_FIELD EQU  89               ; RO_FIELD: add a field offset; RG_FIELD.
OP_INDEX EQU  90               ; RO_ITEM: checked element address; RG_INDEX.
OP_LDX8 EQU  91                ; RO_LOAD: load a byte through an address; RG_GET8.
OP_LDX16 EQU  92               ; RO_LOAD: load a word through an address; RG_GET16.
OP_STX8 EQU  93                ; RO_LET: store a byte through an address; RG_PUT8.
OP_STX16 EQU  94               ; RO_LET: store a word through an address; RG_PUT16.
OP_COPY EQU  95                ; RO_LET: checked aggregate copy; RG_COPY.
OP_LEN EQU  96                 ; RO_SEL: a bounded string's length; RG_LEN.
OP_CHAR EQU  97                ; RO_CHAR: checked string character; RG_CHAR.
OP_FAIL EQU  98                ; AC_THROW: fail with an error code; RG_FAIL.
OP_ABORT EQU  99               ; Written by nothing; its slot dispatches to RG_FATAL.
OP_RETF EQU  100               ; AC_RETOP: succeed from a failable routine; RG_RETOK.
OP_RETAF EQU  101              ; AC_RETOP: succeed with an aggregate; RG_RETOK.
OP_ENDF EQU  102               ; AC_ENDOP: end a failable routine; RG_ENDOK.
OP_HSKIP EQU  103              ; AC_ONERR: jump over a handler; RG_SKIP.
OP_HOPEN EQU  104              ; AC_ONERR: enter a handler; RG_CATCH.
OP_HDONE EQU  105              ; AC_NOERR: place the label after it; RG_JOIN.
OP_ENTRY EQU  106              ; AC_ENTRY: the startup wrapper around main; RG_MAIN.
OP_REFRO EQU  107              ; RO_FIXED: push a constant's address; RG_CONST.
OP_VLEN EQU  108               ; RO_SEL: an open string's length; OS_LEN.
OP_VCHAR EQU  109              ; RO_OSIDX: an open string's character; OS_CHAR.
OP_VIEW EQU  110               ; RO_CALL: pass an open-string argument; OS_ARG.
; Predefined names in KW_NAMES order: six services, then error constants.
; Service n calls RAM vector n.
RO_READ EQU  0                 ; Service readInputByte.
RO_WRITE EQU  1                ; Service writeOutputByte.
RO_FETCH EQU  2                ; Service readStorageByte.
RO_RESET EQU  3                ; Service rewindStorageInput.
RO_STORE EQU  4                ; Service writeStorageByte.
RO_SEEK EQU  5                 ; Service seekStorageOutput.
RO_ERRS EQU  6                 ; First error constant; constant n has value n-5.

; A call selector, the first operand of OP_CALL, names the target kind,
; whether a successful result is kept and the target. Routine labels are
; 27 to 31 and service ordinals 0 to 5, so one byte holds either.
RO_FIO EQU  $80                ; Selector bit 7: the target is a service.
RO_FKEEP EQU  $40              ; Selector bit 6: the result is kept.
RO_LMASK EQU  $3F              ; A routine selector's label field.
RO_SMASK EQU  $07              ; A service selector's ordinal field.

; A service selector (KW_SIGS) also holds the service's fixed signature in
; bits 3..5. Every service can fail.
RO_AMASK EQU  $18              ; Argument field, bits 3..4: type ordinal times 8.
RO_ARG16 EQU  $10              ; Argument field of a u16 argument.
RO_RES8 EQU  $20               ; Bit 5: success returns a u8.

DG_PROCS EQU  84               ; Diagnostic: more than RO_RCAP routines (AC_SIG).
DG_PARAM EQU  85               ; Diagnostic: more than RO_PCAP parameters (RO_ENROL).
DG_LEAK EQU  87                ; Diagnostic: a call's failure is not handled.
DG_FILES EQU  88               ; Diagnostic: part count outside 1 to SRC_CAP.
