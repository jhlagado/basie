; The CP/M shell (toolchain §2, §5): read the source parts named on the
; command line into memory, compile them, and report a diagnostic. Options
; in brackets are accepted and not yet read. A diagnostic is printed as
; NAME.BSI LINE:COLUMN Error N, with the forked compiler's number, until the
; message file replaces it (step 66).

SH_BDOS EQU  $0005
SH_TAIL EQU  $0080
SH_COUT EQU  2
SH_OPEN EQU  15
SH_ERASE EQU  19
SH_READ EQU  20
SH_DMA EQU  26
SH_FLEN EQU  36
SH_NLEN EQU  11

; The shell's workspace, after the compiler's and below the source.
SH_LIMIT EQU  SH_WBEG
SH_LOADP EQU  SH_LIMIT+2
SH_PBEG EQU  SH_LOADP+2
SH_PCNT EQU  SH_PBEG+2
SH_FCB EQU  SH_PCNT+1
SH_PARTS EQU  SH_FCB+SH_FLEN
SH_NAMES EQU  SH_PARTS+SRC_CAP*5
SH_WEND EQU  SH_NAMES+SRC_CAP*SH_NLEN

SH_START:
    LD   HL,(SH_BDOS+1)
    LD   SP,HL
    LD   DE,-MM_STACK
    ADD  HL,DE
    LD   (SH_LIMIT),HL
    LD   HL,MM_SRC
    LD   (SH_LOADP),HL
    XOR  A
    LD   (SH_PCNT),A
    LD   HL,SH_TAIL                ; zero-terminate the tail
    LD   E,(HL)
    LD   D,A
    INC  HL
    PUSH HL
    ADD  HL,DE
    LD   (HL),D
    POP  HL
.NEXTPART:
    CALL .SPACES
    OR   A
    JR   Z,.TAILDONE
    CP   '['
    JR   Z,.TAILDONE
    CALL .LOAD
    CALL .SPACES
    INC  HL
    CP   ','
    JR   Z,.NEXTPART
    OR   A
    JR   Z,.TAILDONE
    CP   '['
    JP   NZ,SH_USAGE
.TAILDONE:
    LD   A,(SH_PCNT)
    OR   A
    JP   Z,SH_USAGE
    LD   HL,SH_PARTS
    LD   IX,SH_DESC
    CALL PR_BUILD
    JP   C,SH_DIAG
    JP   0

; A = the byte at HL, after skipping spaces.
;@ROUTINE IN HL OUT A,HL
.SPACES:
    LD   A,(HL)
    CP   ' '
    RET  NZ
    INC  HL
    JR   .SPACES

; Parse [d:]name[.type] at HL into the FCB, load the part after the parts
; already loaded, and append its descriptor. HL is left after the name.
;@ROUTINE IN HL OUT HL CLOBBERS A,BC,DE,IX,IY
.LOAD:
    LD   A,(SH_PCNT)
    CP   SRC_CAP
    JP   NC,SH_MANY
    CALL SH_BLANK
    INC  HL
    LD   A,(HL)
    DEC  HL
    CP   ':'
    JR   NZ,.NAME
    LD   A,(HL)
    SUB  'A'-1                     ; A: is 1
    JP   Z,SH_USAGE
    CP   17
    JP   NC,SH_USAGE
    LD   (SH_FCB),A
    INC  HL
    INC  HL
.NAME:
    LD   DE,SH_FCB+1
    LD   B,8
    CALL SH_FIELD
    LD   A,(SH_FCB+1)
    CP   ' '
    JP   Z,SH_USAGE
    LD   A,(HL)
    CP   '.'
    JR   NZ,.DEFTYPE
    INC  HL
    LD   DE,SH_FCB+9
    LD   B,3
    CALL SH_FIELD
    JR   .OPEN
.DEFTYPE:
    PUSH HL
    LD   HL,SH_TYPE
    LD   DE,SH_FCB+9
    LD   BC,3
    LDIR
    POP  HL
.OPEN:
    LD   A,(HL)                    ; the name ends the part
    OR   A
    JR   Z,.NAMEEND
    CP   ' '
    JR   Z,.NAMEEND
    CP   ','
    JR   Z,.NAMEEND
    CP   '['
    JP   NZ,SH_USAGE
.NAMEEND:
    PUSH HL
    LD   A,(SH_PCNT)               ; keep the name for diagnostics
    CALL SH_PNAME
    EX   DE,HL
    LD   HL,SH_FCB+1
    LD   BC,SH_NLEN
    LDIR
    LD   DE,SH_FCB
    LD   C,SH_OPEN
    CALL SH_BDOS
    INC  A
    JP   Z,SH_MISS
    LD   HL,(SH_LOADP)
    LD   (SH_PBEG),HL
.RECORD:
    LD   HL,(SH_LOADP)             ; room for another record?
    LD   DE,128
    ADD  HL,DE
    EX   DE,HL
    LD   HL,(SH_LIMIT)
    OR   A
    SBC  HL,DE
    JP   C,SH_LARGE
    LD   DE,(SH_LOADP)
    LD   C,SH_DMA
    CALL SH_BDOS
    LD   DE,SH_FCB
    LD   C,SH_READ
    CALL SH_BDOS
    OR   A
    JR   NZ,.LOADED
    LD   HL,(SH_LOADP)
    LD   DE,128
    ADD  HL,DE
    LD   (SH_LOADP),HL
    JR   .RECORD
.LOADED:
    LD   HL,(SH_PBEG)              ; the part ends at its first $1A
    LD   DE,(SH_LOADP)
SH_TRIM:
    LD   A,L
    CP   E
    JR   NZ,.BYTE
    LD   A,H
    CP   D
    JR   Z,.FOUND
.BYTE:
    LD   A,(HL)
    CP   $1A
    JR   Z,.FOUND
    INC  HL
    JR   SH_TRIM
.FOUND:
    LD   (SH_LOADP),HL
    EX   DE,HL
    LD   A,(SH_PCNT)               ; the descriptor: id, start, end
    LD   L,A
    INC  A
    LD   (SH_PCNT),A
    LD   H,0
    LD   B,H
    LD   C,L
    ADD  HL,HL
    ADD  HL,HL
    ADD  HL,BC
    LD   BC,SH_PARTS
    ADD  HL,BC
    LD   (HL),A
    INC  HL
    LD   BC,(SH_PBEG)
    LD   (HL),C
    INC  HL
    LD   (HL),B
    INC  HL
    LD   (HL),E
    INC  HL
    LD   (HL),D
    POP  HL
    RET

; Set the FCB to the current drive, a blank name and zeros. Preserves HL.
;@ROUTINE CLOBBERS A,B,DE
SH_BLANK:
    LD   DE,SH_FCB
    XOR  A
    LD   (DE),A
    INC  DE
    LD   B,SH_NLEN
.NAMELOOP:
    LD   A,' '
    LD   (DE),A
    INC  DE
    DJNZ .NAMELOOP
    LD   B,SH_FLEN-SH_NLEN-1
    XOR  A
.RESTLOOP:
    LD   (DE),A
    INC  DE
    DJNZ .RESTLOOP
    RET

; Copy name characters from HL to DE, at most B of them.
;@ROUTINE IN B,DE,HL OUT HL CLOBBERS A,B,DE
SH_FIELD:
    LD   A,(HL)
    CALL .CHAR
    RET  C
    INC  B
    DEC  B
    JP   Z,SH_USAGE
    LD   (DE),A
    INC  DE
    INC  HL
    DEC  B
    JR   SH_FIELD

; Carry unless A may appear in a CP/M name (services §4.1).
;@ROUTINE IN A OUT CARRY
.CHAR:
    CP   'A'
    JR   C,.DIGIT
    CP   'Z'+1
    CCF
    RET  NC
.DIGIT:
    CP   '0'
    JR   C,.PUNCT
    CP   '9'+1
    CCF
    RET  NC
.PUNCT:
    PUSH HL
    PUSH BC
    LD   HL,SH_VALID
    LD   BC,16
    CPIR
    POP  BC
    POP  HL
    SCF
    RET  NZ
    CCF
    RET

; HL = the saved name of part A (0-based).
;@ROUTINE IN A OUT HL CLOBBERS DE
SH_PNAME:
    LD   L,A
    LD   H,0
    LD   D,H
    LD   E,L
    ADD  HL,HL
    ADD  HL,HL
    ADD  HL,DE
    ADD  HL,HL
    ADD  HL,DE
    LD   DE,SH_NAMES
    ADD  HL,DE
    RET

; ---- diagnostics and failure ------------------------------------------------

SH_DIAG:
    LD   A,(DG_PART)
    OR   A
    JR   Z,.NUMBER
    DEC  A
    CALL SH_PNAME
    CALL SH_SHOW
    LD   A,' '
    CALL SH_CHAR
    LD   HL,(DG_LINE)
    CALL SH_NUM
    LD   A,':'
    CALL SH_CHAR
    LD   HL,(DG_COL)
    CALL SH_NUM
    LD   A,' '
    CALL SH_CHAR
.NUMBER:
    LD   HL,SH_EMSG
    CALL SH_PRINT
    LD   A,(DG_CODE)
    LD   L,A
    LD   H,0
    CALL SH_NUM
    JR   SH_QUIT

SH_MISS:
    LD   A,(SH_PCNT)
    CALL SH_PNAME
    CALL SH_SHOW
    LD   HL,SH_FMSG
    JR   SH_FAIL
SH_MANY:
    LD   HL,SH_PMSG
    JR   SH_FAIL
SH_LARGE:
    LD   HL,SH_LMSG
    JR   SH_FAIL
SH_USAGE:
    LD   HL,SH_UMSG
SH_FAIL:
    CALL SH_PRINT
SH_QUIT:
    LD   A,13
    CALL SH_CHAR
    LD   A,10
    CALL SH_CHAR
; A failed build deletes A:$$$.SUB, stopping a SUBMIT job (toolchain §5.4).
    CALL SH_BLANK
    LD   HL,SH_JOB
    LD   DE,SH_FCB
    LD   BC,SH_NLEN+1
    LDIR
    LD   DE,SH_FCB
    LD   C,SH_ERASE
    CALL SH_BDOS
    JP   0

; ---- console ----------------------------------------------------------------

; Print the 11-character name at HL as NAME.TYP, without padding.
;@ROUTINE IN HL CLOBBERS A,B,HL
SH_SHOW:
    LD   B,8
    CALL .CHARS
    LD   A,'.'
    CALL SH_CHAR
    LD   B,3
.CHARS:
    LD   A,(HL)
    INC  HL
    CP   ' '
    CALL NZ,SH_CHAR
    DJNZ .CHARS
    RET

; Print the zero-terminated text at HL.
;@ROUTINE IN HL CLOBBERS A,HL
SH_PRINT:
    LD   A,(HL)
    OR   A
    RET  Z
    CALL SH_CHAR
    INC  HL
    JR   SH_PRINT

; Print HL in decimal, without leading zeros.
;@ROUTINE IN HL CLOBBERS A,B,DE,HL
SH_NUM:
    LD   B,0                       ; nonzero once a digit is printed
    LD   DE,10000
    CALL .DIGIT
    LD   DE,1000
    CALL .DIGIT
    LD   DE,100
    CALL .DIGIT
    LD   DE,10
    CALL .DIGIT
    LD   A,L
    ADD  A,'0'
    JR   SH_CHAR

; Print the digit of HL for the power DE, unless it is a leading zero, and
; leave the remainder in HL.
;@ROUTINE IN B,DE,HL OUT B,HL CLOBBERS A
.DIGIT:
    LD   A,'0'-1
.COUNT:
    INC  A
    OR   A
    SBC  HL,DE
    JR   NC,.COUNT
    ADD  HL,DE
    CP   '0'
    JR   NZ,.PRINT
    INC  B
    DEC  B
    RET  Z
.PRINT:
    LD   B,1
; Print A. Preserves every register but F.
;@ROUTINE IN A
SH_CHAR:
    PUSH AF
    PUSH BC
    PUSH DE
    PUSH HL
    LD   E,A
    LD   C,SH_COUT
    CALL SH_BDOS
    POP  HL
    POP  DE
    POP  BC
    POP  AF
    RET

; ---- output ----------------------------------------------------------------

; The forked compiler's output sinks. Placed output is discarded until blob
; output replaces it (native compiler plan, 65.4): every call succeeds.
;@ROUTINE OUT CARRY
PUB_OPEN:
PUB_BYTE:
PUB_FIXB:
PUB_FIXW:
PUB_RT:
PUB_INIT:
PUB_FLAT:
PUB_BANK:
PUB_CMT:
PUB_UNDO:
    OR   A
    RET

; ---- data -------------------------------------------------------------------

SH_DESC:                           ; the forked flat proof target
    DW   RT_IDENT
    DW   $8000,$1000
    DW   $4000,$1000
    DB   1
    DB   1,0
    DW   .BANKS
.BANKS:
    DB   0,0,0,0,0,0,0,0
SH_VALID:
    DB   "!#$%&'()-@^_`{}~"
SH_TYPE:
    DB   "BSI"
SH_JOB:
    DB   1,"$$$     SUB"
SH_EMSG:
    DB   "Error ",0
SH_FMSG:
    DB   " not found",0
SH_PMSG:
    DB   "More than 8 source parts",0
SH_LMSG:
    DB   "Source too large",0
SH_UMSG:
    DB   "Usage: BASIE PART[,PART...] [OPTIONS]",0

SH_CEND:
MM_END:
