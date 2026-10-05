; Packed aggregate-call and Stage 8 routine state. Four direct routine entries,
; sixteen retained parameter positions, and four nested parser call frames are
; bounded independently. Source bytes remain resident, so names use
; pointer/length pairs. Types are the Stage 6 one-byte ordinals.

RO_BASE EQU  AG_WEND
RO_RCNT EQU  RO_BASE+$00
RO_PCNT EQU  RO_BASE+$01
RO_CUR EQU  RO_BASE+$02
RO_CTYPE EQU  RO_BASE+$03
RO_CPIDX EQU  RO_BASE+$04
RO_CPCNT EQU  RO_BASE+$05
RO_GLOBS EQU  RO_BASE+$06
RO_OTYPE EQU  RO_BASE+$07
RO_OSIZE EQU  RO_BASE+$08          ; word
RO_OPOS EQU  RO_BASE+$0A           ; word
RO_AIDX EQU  RO_BASE+$0C
RO_ACNT EQU  RO_BASE+$0D
RO_DTYPE EQU  RO_BASE+$0E
RO_DEST EQU  RO_BASE+$0F
RO_DPOS EQU  RO_BASE+$10
RO_DEPTH EQU  RO_BASE+$12
RO_CFLAG EQU  RO_BASE+$13
RO_FPOS EQU  RO_BASE+$14
RO_PEND EQU  RO_BASE+$16
RO_MODEP EQU  RO_BASE+$17
RO_MFLAG EQU  RO_BASE+$19
; Number of already-evaluated destination carriers below a failable result.
; A local handler discards these before entering its statement body.
RO_KEPT EQU  RO_BASE+$1A
; These values span expression parsing, so nested calls must not overlay them.
RO_IO EQU  RO_BASE+$1B
RO_DFLAG EQU  RO_BASE+$1C
RO_VCAP EQU  RO_BASE+$1D
RO_STEND EQU  RO_BASE+$1E

RO_RTAB EQU  RO_STEND
RO_RLEN EQU  8
RO_RCAP EQU  4
RO_RLIM EQU  RO_RTAB+RO_RLEN*RO_RCAP
RO_RNAME EQU  0
RO_RNLEN EQU  2
RO_RPIDX EQU  3
RO_RPCNT EQU  4
RO_RTYPE EQU  5
RO_RDEST EQU  6
RO_RFLAG EQU  7

RO_PTAB EQU  RO_RLIM
RO_PLEN EQU  4
RO_PCAP EQU  16
RO_PLIM EQU  RO_PTAB+RO_PLEN*RO_PCAP
RO_PNAME EQU  0
RO_PNLEN EQU  2
RO_PTYPE EQU  3

RO_NTAB EQU  RO_PLIM
RO_NLEN EQU  8
RO_NCAP EQU  4
RO_NLIM EQU  RO_NTAB+RO_NLEN*RO_NCAP
RO_NDEST EQU  0
RO_NTYPE EQU  1
RO_NPIDX EQU  2
RO_NLEFT EQU  3
RO_NACNT EQU  4
RO_NPOS EQU  5
RO_NFLAG EQU  7

RO_WEND EQU  RO_NLIM

; The memory-backed multipart adapter retains only the next external
; descriptor and one packed multipart byte. Bit 7 records a pending boundary
; newline, bits 3..5 retain the current manifest ordinal, and bits 0..2 retain
; the number of later parts. SRC_CAP=8 makes every field exact.
; Source bytes and the descriptor table remain outside compiler workspace.
SRC_DESC EQU  RO_WEND
SRC_LEFT EQU  SRC_DESC+2
SRC_WEND EQU  SRC_LEFT+1
SRC_DLEN EQU  5
SRC_CAP EQU  8
SRC_CNT EQU  $07
SRC_OBIT EQU  3
SRC_STEP EQU  8
SRC_ORD EQU  $38
SRC_PEND EQU  $80

; Emission begins only after parsing has published the semantic transcript, so
; its consecutive call fields overlay the no-longer-live declaration prefix.
RG_BASE EQU  RO_BASE
RG_FLAGS EQU  RG_BASE+$00
RG_TYPE EQU  RG_BASE+$01
RG_MODE EQU  RG_BASE+$02
RG_HDEST EQU  RG_BASE+$03
RG_KEPT EQU  RG_BASE+$04

RO_LBASE EQU  28
; Label 27 is the callable body of main. The startup wrapper calls this label
; just like a source call, while labels 28..31 retain ordinary routines.
RO_MDEST EQU  27
CT_LLIM EQU  RO_MDEST
RO_MAIN EQU  $FE
RO_NONE EQU  0
RO_FFAIL EQU  1
RO_FMAIN EQU  2
RO_FOPEN EQU  4
; Target bank ordinals occupy unused routine/symbol metadata bits. The first
; banked profile is deliberately bounded to four banks.
TG_BCAP EQU  4
TG_BBIT EQU  4
TG_BMASK EQU  $30

RO_MSAFE EQU  0
RO_MPASS EQU  1
RO_MEXIT EQU  2
RO_MTRAP EQU  3

; Stage 7 semantic operations extend the dense production dispatch range.
OP_PROC EQU  82
OP_BIND EQU  83
OP_CALL EQU  84
OP_RETA EQU  85
OP_ENDP EQU  86
OP_REFG EQU  87
OP_REFP EQU  88
OP_FIELD EQU  89
OP_INDEX EQU  90
OP_LDX8 EQU  91
OP_LDX16 EQU  92
OP_STX8 EQU  93
OP_STX16 EQU  94
OP_COPY EQU  95
OP_LEN EQU  96
OP_CHAR EQU  97
OP_FAIL EQU  98
OP_ABORT EQU  99
OP_RETF EQU  100
OP_RETAF EQU  101
OP_ENDF EQU  102
OP_HSKIP EQU  103
OP_HOPEN EQU  104
OP_HDONE EQU  105
OP_ENTRY EQU  106
OP_REFRO EQU  107
OP_VLEN EQU  108
OP_VCHAR EQU  109
OP_VIEW EQU  110
RO_READ EQU  0
RO_WRITE EQU  1
RO_FETCH EQU  2
RO_RESET EQU  3
RO_STORE EQU  4
RO_SEEK EQU  5
RO_ERRS EQU  6

; One completed call selector carries the target kind, successful-result
; retention choice, and dense target ID. Source labels occupy 27..31 and
; service IDs occupy 0..5, so both fit without widening the transcript.
RO_FIO EQU  $80
RO_FKEEP EQU  $40
RO_LMASK EQU  $3F
RO_SMASK EQU  $07

; Service selectors use their otherwise-free middle bits for the fixed
; signature: optional scalar parameter type in bits 3..4 and a successful u8
; result in bit 5. Every service is failable.
RO_AMASK EQU  $18
RO_ARG16 EQU  $10
RO_RES8 EQU  $20

DG_PROCS EQU  84
DG_PARAM EQU  85
DG_ALIAS EQU  86
DG_LEAK EQU  87
DG_FILES EQU  88
