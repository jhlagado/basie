; Phases A and B (linker §4, §5): read the library and program directories
; into the tables of linker §2.1, check them, and mark what is live.
;
; Table entry, 8 bytes, one per ordinal:
;   +0 flags: bits 0-2 kind, 3 defined, 4 referenced, 5 live, 6 alias, 7 root
;   +1 size (an alias: its offset)   +3 address (an alias: its base ordinal)
;   +5 edges: the lowest of its distinct targets, or 0   +7 layout (alignment)
; The library table is indexed by ordinal from 0; the program table, which
; grows, by ordinal - $0400. Edge lists grow down from EL_TOP, each blob's a
; $0000 terminator with its targets below it.
;
; Every check that fails reports its diagnostic and ends the link (FAILED).

E_FLAGS EQU     0
E_SIZE  EQU     1
E_ADDR  EQU     3
E_EDGES EQU     5
E_LAYOUT EQU    7
F_DEF   EQU     $08
F_REF   EQU     $10
F_LIVE  EQU     $20
F_ALIAS EQU     $40
F_ROOT  EQU     $80
K_CODE  EQU     0
K_BSS   EQU     3
K_START EQU     4
P_MAIN  EQU     $FFE0
P_FILES EQU     $FFE8
P_FCNT  EQU     $FFE9
STKROOM EQU   $0300           ; kept below the stack for calls and messages

LIBH:   DS      64              ; the library header and profile block
PRGH:   DS      20              ; the program directory's header
LT_BASE: DW     0
LT_COUNT: DW    0
PT_BASE: DW     0
PT_COUNT: DW    0
PT_END: DW      0
EL_PTR: DW      0
EL_TOP: DW      0
ENTRYORD: DW   0
HAVE_ENT: DB  0
LIMITS: DS      5               ; stack reserve, largest frame, flags
HAVE_LIM: DB    0
LIBFIRST: DB   $FF             ; the kind of the library's first record
USEFILES: DB  0
R_NAME: DW      0               ; the file being read, for messages

D_OWNER: DB     0               ; 0 library, 1 program
D_PREV: DW      0
D_HASPRV: DB   0
D_FIRST: DW     0
D_LAST: DW      0
D_STREAM: DW    0
D_SAWLIM: DB    0
D_AFTER: DB     0
D_COUNT: DW     0
D_SIZE: DW      0
D_ENTRY: DW     0
D_TERM: DW      0
D_LSTOFF: DW   0
D_HAVLST: DB  0
D_REFEND: DW    0
D_FORM: DB      0
D_HEADER: DB    0
D_ORD:  DW      0
D_NREFS: DW     0
ARGTXT: DS      8               ; "$HHHH" and a zero, for ordinal arguments

; ---- reading ---------------------------------------------------------------

; A = the next byte of the file at IX, added to the CRC. Preserves BC, DE,
; HL. A file that ends early is L-TRUNCATED.
R_U8:   PUSH    BC
        PUSH    DE
        PUSH    HL
        CALL    F_GETB
        POP     HL
        POP     DE
        POP     BC
        JP      C,R_SHORT
        PUSH    AF              ; the CRC is checked in Phase A only
        LD      A,(CRC_ON)
        OR      A
        JR      Z,.NOCRC
        POP     AF
        JP      CRC_ADD8
.NOCRC: POP     AF
        RET

CRC_ON: DB      1               ; cleared once Phase A has checked the CRCs

; The same without the CRC.
R_RAW:  PUSH    BC
        PUSH    DE
        PUSH    HL
        CALL    F_GETB
        POP     HL
        POP     DE
        POP     BC
        RET     NC
R_SHORT:
        LD      HL,214          ; L-TRUNCATED
        JP      ERRFILE

; Add A to the CRC, keeping A.
CRC_ADD8:
        PUSH    AF
        CALL    CRC_ADD
        POP     AF
        RET

; HL = the next word. Preserves BC and DE.
R_U16:  CALL    R_U8
        LD      L,A
        CALL    R_U8
        LD      H,A
        RET

; Report message HL with the file being read as argument 1, and fail.
ERRFILE:
        PUSH    HL
        LD      HL,(R_NAME)
        LD      (M_ARG1),HL
        POP     HL
        CALL    ERROR
        JP      FAILED

; Report message HL with no argument, and fail.
ERRPLAIN:
        CALL    ERROR
        JP      FAILED

; Report message HL with the ordinal in DE as "$HHHH", and fail.
ERRORD: PUSH    HL
        LD      HL,ARGTXT
        LD      (HL),'$'
        INC     HL
        LD      A,D
        CALL    .HEX2
        LD      A,E
        CALL    .HEX2
        LD      (HL),0
        LD      HL,ARGTXT
        LD      (M_ARG1),HL
        POP     HL
        CALL    ERROR
        JP      FAILED
.HEX2:  PUSH    AF
        RRCA
        RRCA
        RRCA
        RRCA
        CALL    .HEX1
        POP     AF
.HEX1:  CALL    HEXDIG
        LD      (HL),A
        INC     HL
        RET

; A = the hex digit for A's low four bits, in ASCII.
HEXDIG: AND     $0F
        ADD     A,$90
        DAA
        ADC     A,$40
        DAA
        RET

; ---- tables ------------------------------------------------------------------

; HL = the entry of ordinal HL, creating program entries as needed. Carry if
; the ordinal has no entry: a pseudo-object, or a library ordinal beyond the
; library's highest.
ENT_MAKE:
        LD      A,H
        CP      $FF
        JR      NZ,.REAL
        LD      A,L
        CP      $E0
        CCF
        RET     C               ; $FFE0 and above: pseudo
.REAL:  LD      A,H
        CP      $04
        JR      NC,.PROG
        LD      DE,(LT_COUNT)
        OR      A
        SBC     HL,DE
        CCF
        RET     C               ; beyond the library
        ADD     HL,DE
        ADD     HL,HL
        ADD     HL,HL
        ADD     HL,HL
        LD      DE,(LT_BASE)
        ADD     HL,DE
        OR      A
        RET
.PROG:  LD      DE,$0400
        OR      A
        SBC     HL,DE           ; HL = index
        PUSH    HL
        LD      DE,(PT_COUNT)
        OR      A
        SBC     HL,DE
        JR      C,.HAVE
        ; grow to index + 1, zeroing the new entries
        POP     HL
        PUSH    HL
        INC     HL
        LD      (PT_COUNT),HL
        ADD     HL,HL
        ADD     HL,HL
        ADD     HL,HL
        LD      DE,(PT_BASE)
        ADD     HL,DE           ; the new end
        EX      DE,HL
        LD      HL,(EL_PTR)
        OR      A
        SBC     HL,DE
        JP      C,CAPFULL       ; it meets the edge lists
        LD      HL,(PT_END)
.ZERO:  LD      A,L
        CP      E
        JR      NZ,.Z1
        LD      A,H
        CP      D
        JR      Z,.ZDONE
.Z1:    LD      (HL),0
        INC     HL
        JR      .ZERO
.ZDONE: LD      (PT_END),DE
.HAVE:  POP     HL
        ADD     HL,HL
        ADD     HL,HL
        ADD     HL,HL
        LD      DE,(PT_BASE)
        ADD     HL,DE
        OR      A
        RET

CAPFULL:
        LD      HL,215          ; L-CAP-TABLES
        JP      ERRPLAIN

; Push word DE onto the edge lists. Preserves BC and DE.
EL_PUSH:
        LD      HL,(EL_PTR)
        DEC     HL
        DEC     HL
        LD      (EL_PTR),HL
        PUSH    HL
        PUSH    DE
        LD      DE,(PT_END)
        OR      A
        SBC     HL,DE
        POP     DE
        POP     HL
        JP      C,CAPFULL
        LD      (HL),E
        INC     HL
        LD      (HL),D
        RET

; ---- Phase A -----------------------------------------------------------------

PHASEA: ; the tables start above the program and the edge lists below the stack
        LD      HL,(LIBH+36)    ; the library's highest ordinal
        INC     HL
        LD      (LT_COUNT),HL
        ADD     HL,HL
        ADD     HL,HL
        ADD     HL,HL
        LD      B,H
        LD      C,L             ; BC = the library table's bytes
        LD      HL,FREEMEM
        LD      (LT_BASE),HL
        ADD     HL,BC
        LD      (PT_BASE),HL
        LD      (PT_END),HL
        LD      HL,0
        ADD     HL,SP
        LD      DE,STKROOM
        OR      A
        SBC     HL,DE
        LD      (EL_TOP),HL
        LD      (EL_PTR),HL
        LD      DE,(PT_BASE)
        OR      A
        SBC     HL,DE
        JP      C,CAPFULL
        LD      HL,(LT_BASE)    ; zero the library table
.CLR:   LD      A,B
        OR      C
        JR      Z,.LIB
        LD      (HL),0
        INC     HL
        DEC     BC
        JR      .CLR
        ; the library's directory, its CRC from the directory's start
.LIB:   LD      IX,LIB_FD
        LD      HL,LIB_TXT
        LD      (R_NAME),HL
        LD      A,(LIBH+14)
        LD      HL,(LIBH+12)
        CALL    F_SEEK
        JP      C,R_SHORT
        CALL    CRC_NEW
        XOR     A
        LD      (D_OWNER),A
        LD      HL,1
        LD      (D_FIRST),HL
        LD      HL,$03FF
        LD      (D_LAST),HL
        LD      HL,0            ; the implicit first ordinal: $0001 - 1
        CALL    READDIR
        ; the trailer must agree with the header
        LD      HL,(D_TRBYTE)
        LD      DE,(LIBH+20)
        OR      A
        SBC     HL,DE
        JP      NZ,R_SHORT
        LD      HL,(D_TRHIGH)
        LD      DE,(LIBH+36)
        OR      A
        SBC     HL,DE
        JP      NZ,R_SHORT
        ; the program's directory
        CALL    OPENDIR
        LD      A,1
        LD      (D_OWNER),A
        LD      HL,$0400
        LD      (D_FIRST),HL
        LD      HL,$FFDF
        LD      (D_LAST),HL
        LD      HL,(PRGH+16)    ; the ordinal base
        DEC     HL
        CALL    READDIR
        JP      CHECKS

; Read records from the file at IX until the trailer. HL = the implicit
; ordinal before the first.
READDIR:
        LD      (D_PREV),HL
        LD      HL,0
        LD      (D_STREAM),HL
        LD      (D_COUNT),HL
        XOR     A
        LD      (D_SAWLIM),A
        LD      (D_AFTER),A
RD_REC: CALL    R_U8
        CP      $FF
        JP      Z,TRAILER
        LD      (D_HEADER),A
        AND     7
        CP      6
        JP      Z,CONTROL
        CP      5
        JP      NC,RESERVED
        LD      A,(D_SAWLIM)
        LD      (D_AFTER),A
        ; the ordinal: explicit, or one more than the last
        LD      A,(D_HEADER)
        BIT     3,A
        JR      Z,.IMPL
        CALL    R_U16
        JR      .ORD
.IMPL:  LD      HL,(D_PREV)
        INC     HL
.ORD:   LD      (D_ORD),HL
        LD      (D_PREV),HL
        CALL    INRANGE
        LD      HL,205          ; L-ORDINAL: outside its range
        LD      DE,(D_ORD)
        JP      C,ERRORD
        CALL    R_U16
        LD      (D_SIZE),HL
        LD      A,H
        OR      L
        LD      HL,207          ; L-BLOB: a blob of size 0
        JP      Z,ERRPLAIN
        CALL    R_U8
        LD      L,A
        LD      H,0
        CP      255
        JR      NZ,.COUNT
        CALL    R_U16
.COUNT: LD      (D_NREFS),HL
        ; checks on the kind
        LD      A,(D_HEADER)
        AND     7
        LD      C,A             ; C = kind
        CP      K_CODE
        JR      Z,.NOALIGN
        CP      K_START
        JR      NZ,.ALIGNOK
        LD      A,(D_OWNER)
        OR      A
        LD      HL,207          ; L-BLOB: startup in the program
        JP      NZ,ERRPLAIN
.NOALIGN:
        LD      A,(D_HEADER)
        AND     $E0
        LD      HL,207          ; L-BLOB: aligned code or startup
        JP      NZ,ERRPLAIN
.ALIGNOK:
        LD      A,C
        CP      K_BSS
        JR      NZ,.NOTBSS
        LD      HL,(D_NREFS)
        LD      A,H
        OR      L
        LD      HL,207          ; L-BLOB: bss with references
        JP      NZ,ERRPLAIN
.NOTBSS:
        LD      A,(D_OWNER)     ; the library's first record
        OR      A
        JR      NZ,.ENTRY
        LD      A,(LIBFIRST)
        INC     A
        JR      NZ,.ENTRY
        LD      A,C
        LD      (LIBFIRST),A
.ENTRY: LD      HL,(D_ORD)
        CALL    ENT_MAKE
        LD      (D_ENTRY),HL
        LD      DE,(D_ORD)
        LD      HL,205          ; L-ORDINAL: beyond the library's highest
        JP      C,ERRORD
        LD      HL,(D_ENTRY)
        BIT     3,(HL)
        LD      HL,205          ; L-ORDINAL: defined twice
        JP      NZ,ERRORD
        LD      HL,(D_ENTRY)
        LD      A,(D_HEADER)
        AND     7
        OR      F_DEF
        LD      B,A
        LD      A,(D_HEADER)
        AND     $10             ; root
        RLCA
        RLCA
        RLCA                    ; to bit 7
        OR      B
        LD      (HL),A
        INC     HL
        LD      DE,(D_SIZE)
        LD      (HL),E
        INC     HL
        LD      (HL),D
        INC     HL
        LD      (HL),0          ; address
        INC     HL
        LD      (HL),0
        INC     HL
        LD      (HL),0          ; edges
        INC     HL
        LD      (HL),0
        INC     HL
        LD      A,(D_HEADER)
        RLCA
        RLCA
        RLCA
        AND     7
        LD      (HL),A          ; layout: the alignment code
        ; the byte stream: every kind but bss
        LD      A,C
        CP      K_BSS
        JR      Z,.REFS
        LD      HL,(D_STREAM)
        LD      DE,(D_SIZE)
        ADD     HL,DE
        JP      C,R_SHORT
        LD      (D_STREAM),HL
.REFS:  LD      HL,(D_COUNT)
        INC     HL
        LD      (D_COUNT),HL
        CALL    REFS
        JP      RD_REC

; Carry unless ordinal HL lies in D_FIRST..D_LAST.
INRANGE:
        LD      DE,(D_FIRST)
        OR      A
        SBC     HL,DE
        RET     C
        ADD     HL,DE
        EX      DE,HL
        LD      HL,(D_LAST)
        OR      A
        SBC     HL,DE           ; carry if ordinal > last
        RET

RESERVED:
        LD      HL,206          ; L-RESERVED
        JP      ERRPLAIN

; The references of the blob just read: D_NREFS of them, at D_ENTRY.
REFS:   LD      HL,(D_NREFS)
        LD      A,H
        OR      L
        RET     Z
        LD      DE,0            ; the blob's terminator
        CALL    EL_PUSH
        LD      HL,(EL_PTR)
        LD      (D_TERM),HL
        XOR     A
        LD      (D_HAVLST),A
        LD      HL,0
        LD      (D_REFEND),HL
.NEXT:  CALL    R_U8            ; control
        LD      B,A
        AND     $3F
        CP      63
        JR      NZ,.DELTA
        CALL    R_U16           ; an absolute offset
        LD      A,(D_HAVLST)
        OR      A
        JR      Z,.OFF
        PUSH    HL
        LD      DE,(D_LSTOFF)
        EX      DE,HL
        OR      A
        SBC     HL,DE           ; last - offset: no carry means not increasing
        POP     HL
        JP      NC,BADREF
        JR      .OFF
.DELTA: LD      L,A
        LD      H,0
        LD      A,(D_HAVLST)
        OR      A
        JR      Z,.OFF
        LD      A,L
        OR      A
        JP      Z,BADREF        ; a zero delta
        LD      DE,(D_LSTOFF)
        ADD     HL,DE
.OFF:   LD      (D_LSTOFF),HL
        LD      A,1
        LD      (D_HAVLST),A
        ; the form
        XOR     A
        BIT     7,B
        JR      Z,.FORM
        CALL    R_U8
        OR      A
        JP      Z,RESERVED      ; form byte 0
.FORM:  LD      (D_FORM),A
        CP      4
        JP      NC,RESERVED     ; BANK8 and beyond
        ; the width: ABS16 and SIZE16 2 bytes, LO8 and HI8 1
        LD      E,2
        CP      1
        JR      Z,.W1
        CP      2
        JR      NZ,.WIDTH
.W1:    LD      E,1
.WIDTH: LD      D,0             ; DE = width
        PUSH    BC
        LD      HL,(D_LSTOFF)
        LD      BC,(D_REFEND)
        OR      A
        SBC     HL,BC
        POP     BC
        JP      C,BADREF        ; overlaps the previous reference
        LD      HL,(D_LSTOFF)
        ADD     HL,DE
        LD      (D_REFEND),HL
        EX      DE,HL
        LD      HL,(D_SIZE)
        OR      A
        SBC     HL,DE
        JP      C,BADREF        ; leaves the blob
        ; the target
        CALL    R_U16
        PUSH    HL
        BIT     6,B
        JR      Z,.NOADD
        CALL    R_U16           ; the addend: not needed until Phase D
.NOADD: POP     HL
        CALL    TARGET
        LD      HL,(D_NREFS)
        DEC     HL
        LD      (D_NREFS),HL
        LD      A,H
        OR      L
        JP      NZ,.NEXT
        ; the blob's edges field: its lowest target
        LD      HL,(D_ENTRY)
        LD      DE,E_EDGES
        ADD     HL,DE
        LD      DE,(EL_PTR)
        LD      (HL),E
        INC     HL
        LD      (HL),D
        RET

BADREF: LD      HL,208          ; L-REFERENCE
        JP      ERRPLAIN

; Check target HL of a reference and add it to the blob's edges if new.
TARGET: LD      A,H
        OR      L
        JP      Z,BADREF        ; ordinal 0
        LD      A,H
        CP      $FF
        JR      NZ,.REAL
        LD      A,L
        CP      $E0
        JR      C,.REAL
        CP      $EA
        JP      NC,BADREF       ; an undefined pseudo-object
        JR      .ADD
.REAL:  LD      A,(D_OWNER)     ; the library refers only to itself
        OR      A
        JR      NZ,.MARK
        LD      A,H
        CP      $04
        JP      NC,BADREF
        PUSH    HL
        LD      DE,(LIBH+36)
        EX      DE,HL
        OR      A
        SBC     HL,DE           ; highest - target
        POP     HL
        JP      C,BADREF
.MARK:  PUSH    HL
        CALL    ENT_MAKE        ; referenced; carry: beyond the library
        JR      C,.UNDEF
        LD      A,(D_FORM)      ; SIZE16 of a known alias
        CP      3
        JR      NZ,.SETREF
        BIT     6,(HL)
        JP      NZ,BADREF
.SETREF:
        SET     4,(HL)
        POP     HL
.ADD:   EX      DE,HL           ; DE = the target
        LD      HL,(EL_PTR)     ; already among this blob's edges?
.SCAN:  PUSH    DE
        LD      DE,(D_TERM)
        LD      A,L
        CP      E
        JR      NZ,.CMP
        LD      A,H
        CP      D
.CMP:   POP     DE
        JR      Z,.NEW
        LD      A,(HL)
        INC     HL
        CP      E
        JR      NZ,.SKIP
        LD      A,(HL)
        CP      D
        RET     Z               ; a repeat
.SKIP:  INC     HL
        JR      .SCAN
.NEW:   JP      EL_PUSH
.UNDEF: POP     DE
        LD      HL,213          ; L-UNDEFINED
        JP      ERRORD

; A control record: alias, entry, bank or limits.
CONTROL:
        LD      A,(D_OWNER)     ; the library's first record isn't startup
        OR      A
        JR      NZ,.KIND
        LD      A,(LIBFIRST)
        INC     A
        JR      NZ,.KIND
        LD      A,$FE
        LD      (LIBFIRST),A
.KIND:  LD      A,(D_HEADER)
        RRCA
        RRCA
        RRCA
        AND     $1F
        JR      Z,ALIAS
        DEC     A
        JR      Z,ENTRYREC
        DEC     A
        JP      Z,RESERVED      ; BANK is reserved in 1.0
        DEC     A
        JP      NZ,RESERVED
        ; LIMITS, once, in the program
        LD      A,(D_OWNER)
        OR      A
        JR      Z,.BADLIM
        LD      A,(HAVE_LIM)
        OR      A
        JR      NZ,.BADLIM
        INC     A
        LD      (HAVE_LIM),A
        LD      (D_SAWLIM),A
        LD      HL,LIMITS
        LD      B,5
.LIM:   CALL    R_U8
        LD      (HL),A
        INC     HL
        DJNZ    .LIM
        JP      RD_REC
.BADLIM:
        LD      HL,211          ; L-LIMITS
        JP      ERRPLAIN

ENTRYREC:
        CALL    R_U16
        LD      A,(D_OWNER)
        OR      A
        JR      Z,.BAD
        LD      A,(HAVE_ENT)
        OR      A
        JR      NZ,.BAD
        INC     A
        LD      (HAVE_ENT),A
        LD      (ENTRYORD),HL
        JP      RD_REC
.BAD:   LD      HL,210          ; L-ENTRY
        JP      ERRPLAIN

ALIAS:  CALL    R_U16           ; the alias
        LD      (D_ORD),HL
        CALL    INRANGE
        LD      DE,(D_ORD)
        LD      HL,209          ; L-ALIAS: outside its range
        JP      C,ERRORD
        LD      HL,(D_ORD)
        CALL    ENT_MAKE
        LD      (D_ENTRY),HL
        LD      DE,(D_ORD)
        LD      HL,205
        JP      C,ERRORD
        LD      HL,(D_ENTRY)
        BIT     3,(HL)
        LD      HL,205          ; L-ORDINAL: defined twice
        JP      NZ,ERRORD
        CALL    R_U16           ; the base
        PUSH    HL
        CALL    R_U16           ; the offset
        EX      DE,HL           ; DE = offset
        POP     BC              ; BC = base
        LD      HL,(D_ENTRY)
        LD      (HL),F_DEF+F_ALIAS
        INC     HL
        LD      (HL),E
        INC     HL
        LD      (HL),D
        INC     HL
        LD      (HL),C
        INC     HL
        LD      (HL),B
        LD      H,B             ; the base is referenced
        LD      L,C
        PUSH    BC
        CALL    ENT_MAKE
        POP     DE
        LD      HL,209          ; L-ALIAS: a bad base
        JP      C,ERRORD
        SET     4,(HL)
        JP      RD_REC

; The trailer: counts, then the CRC of everything before the CRC.
D_TRBYTE: DW   0
D_TRHIGH: DW    0
TRAILER:
        CALL    R_U16           ; the blob count
        LD      DE,(D_COUNT)
        OR      A
        SBC     HL,DE
        JP      NZ,R_SHORT
        CALL    R_U16           ; the byte stream's length, low then high
        LD      (D_TRBYTE),HL
        CALL    R_U16
        LD      A,H
        OR      L
        JP      NZ,R_SHORT      ; at most 64K
        CALL    R_U16
        LD      (D_TRHIGH),HL
        CALL    R_U8            ; reserved
        LD      HL,(CRC_V)
        PUSH    HL
        CALL    R_RAW
        LD      E,A
        CALL    R_RAW
        LD      D,A
        POP     HL
        OR      A
        SBC     HL,DE
        JP      NZ,R_SHORT      ; the CRC
        LD      HL,(D_STREAM)   ; the records account for the stream
        LD      DE,(D_TRBYTE)
        OR      A
        SBC     HL,DE
        JP      NZ,R_SHORT
        LD      A,(D_AFTER)
        OR      A
        LD      HL,211          ; L-LIMITS: blobs after LIMITS
        JP      NZ,ERRPLAIN
        RET

; Open NAME.$DR on the spool drive and check its header against the library
; (linker §4.3; object format §10).
DR_FD:  DS      FDSIZE
DR_TY:  DB      "$DR"
DR_TXT: DS      13
OPENDIR:
        LD      IX,DR_FD
        LD      A,(O_SDRV)
        OR      A
        JR      NZ,.DRV
        LD      A,(O_DRV)
.DRV:   LD      HL,O_NAME
        LD      DE,DR_TY
        CALL    F_INIT
        LD      HL,O_NAME       ; its name as text
        LD      DE,DR_TXT
        LD      BC,DR_TY
        CALL    FILETXT
        LD      HL,DR_TXT
        LD      (R_NAME),HL
        CALL    F_OPEN
        LD      HL,225          ; L-MISSING
        JP      C,ERRFILE
        CALL    CRC_NEW
        LD      HL,PRGH
        LD      B,20
.HEAD:  CALL    R_U8
        LD      (HL),A
        INC     HL
        DJNZ    .HEAD
        LD      HL,PRGH         ; magic and version
        LD      DE,.MAGIC
        LD      B,4
.MAG:   LD      A,(DE)
        CP      (HL)
        JR      NZ,.BADMAG
        INC     HL
        INC     DE
        DJNZ    .MAG
        LD      A,(PRGH+4)
        CP      1
        LD      HL,200          ; L-FORMAT
        JP      NZ,ERRFILE
        LD      A,(PRGH+5)
        OR      A
        JP      NZ,ERRFILE
        ; compatibility: runtime and profile identities, helper table
        LD      HL,(PRGH+8)
        LD      DE,(LIBH+6)
        OR      A
        SBC     HL,DE
        JR      NZ,.COMPAT
        LD      HL,(PRGH+14)
        LD      DE,(LIBH+10)
        OR      A
        SBC     HL,DE
        JR      NZ,.COMPAT
        LD      HL,(LIBH+8)     ; the library's version, at least the program's
        LD      DE,(PRGH+10)
        OR      A
        SBC     HL,DE
        JR      C,.COMPAT
        LD      HL,(PRGH+12)    ; the program's key, unless 0
        LD      A,H
        OR      L
        JR      Z,.STAMP
        CALL    LIBKEY
        LD      DE,(PRGH+12)
        OR      A
        SBC     HL,DE
        JR      NZ,.COMPAT
.STAMP: LD      HL,(PRGH+6)
        LD      A,H
        OR      L
        LD      HL,202          ; L-STAMP: stamp 0
        JP      Z,ERRPLAIN
        JR      PROFCHK
.COMPAT:
        LD      HL,201          ; L-COMPAT
        JP      ERRPLAIN
.BADMAG:
        LD      HL,200          ; L-FORMAT
        JP      ERRFILE
.MAGIC: DB      "BSIP"

; Check the options and output kind against the profile (linker §3).
PROFCHK:
        LD      HL,203          ; L-OPTION
        LD      A,(O_FLAGS)
        AND     OF_B
        JR      Z,.NOB
        LD      A,(LIBH+58)     ; option support: bit 0 keep the CCP
        RRA
        JP      NC,ERRPLAIN
.NOB:   LD      A,(O_FLAGS)
        AND     OF_R
        JR      Z,.NOR
        LD      A,(LIBH+58)     ; bit 1 re-runnable
        AND     2
        JP      Z,ERRPLAIN
.NOR:   INC     HL              ; L-OUTPUT
        LD      A,(LIBH+43)     ; the output kinds
        LD      DE,O_KIND
        EX      DE,HL
        AND     (HL)
        EX      DE,HL
        JP      Z,ERRPLAIN
        LD      A,(DE)          ; .COM needs image base $0100
        DEC     A
        RET     NZ
        LD      DE,(LIBH+44)
        DEC     D
        LD      A,D
        OR      E
        RET     Z
        JP      ERRPLAIN

; HL = the library's key for the program's helper-table version. The key
; table is a count, then a key per version. The library file stays at IX's
; position for the program, so a second FD is not needed: the library's FD
; is used and left at the key table.
LIBKEY: PUSH    IX
        LD      IX,LIB_FD
        LD      A,(LIBH+34)
        LD      HL,(LIBH+32)
        CALL    F_SEEK
        JP      C,R_SHORT
        CALL    R_RAW
        LD      L,A
        CALL    R_RAW
        LD      H,A             ; HL = the count
        LD      DE,(PRGH+10)    ; the program's version, 1 to count
        LD      A,D
        OR      E
        JR      Z,.NONE
        OR      A
        SBC     HL,DE
        JR      C,.NONE
        LD      B,D
        LD      C,E
.SKIP:  DEC     BC
        LD      A,B
        OR      C
        JR      Z,.KEY
        CALL    R_RAW
        CALL    R_RAW
        JR      .SKIP
.KEY:   CALL    R_RAW
        LD      L,A
        CALL    R_RAW
        LD      H,A
        POP     IX
        RET
.NONE:  POP     IX
        LD      HL,201          ; L-COMPAT
        JP      ERRPLAIN

; Write the file name NAME.TYP as text at DE: HL = the 8-character name,
; BC = the 3-character type.
FILETXT:
        PUSH    BC
        LD      B,8
.NAME:  LD      A,(HL)
        CP      ' '
        JR      Z,.DOT
        LD      (DE),A
        INC     HL
        INC     DE
        DJNZ    .NAME
.DOT:   LD      A,'.'
        LD      (DE),A
        INC     DE
        POP     HL
        LD      BC,3
        LDIR
        XOR     A
        LD      (DE),A
        RET

; ---- the checks at the end of Phase A (linker §4.3) ---------------------------

CHECKS: LD      A,(HAVE_ENT)  ; ENTRY names a program code blob
        OR      A
        JR      Z,.NOENTRY
        LD      HL,(ENTRYORD)
        LD      A,H
        CP      $04
        JR      C,.NOENTRY
        CALL    ENT_MAKE
        JR      C,.NOENTRY
        LD      A,(HL)
        AND     F_DEF+F_ALIAS+7
        CP      F_DEF+K_CODE
        JR      NZ,.NOENTRY
        LD      A,(HAVE_LIM)
        OR      A
        LD      HL,211          ; L-LIMITS: missing
        JP      Z,ERRPLAIN
        LD      A,(LIBFIRST)   ; startup is the library's first record
        CP      K_START
        JR      NZ,.NOSTART
        ; scan every entry: one startup, references defined, aliases sound
        LD      B,0             ; startups seen
        LD      HL,0            ; the ordinal
.SCAN:  PUSH    HL
        PUSH    BC
        CALL    ENTRYAT         ; HL = the entry, carry past the end
        POP     BC
        JR      C,.END
        LD      A,(HL)
        BIT     3,A
        JR      NZ,.DEF
        BIT     4,A
        JR      Z,.NEXT
        POP     HL              ; referenced but never defined
        CALL    POS2ORD
        EX      DE,HL
        LD      HL,213          ; L-UNDEFINED
        JP      ERRORD
.DEF:   BIT     6,A
        JR      NZ,.ALIAS
        AND     7
        CP      K_START
        JR      NZ,.NEXT
        INC     B
        PUSH    HL              ; startup must refer to MAIN
        PUSH    BC
        LD      DE,P_MAIN
        CALL    HASEDGE
        POP     BC
        POP     HL
        JR      NC,.NEXT
        POP     HL
        JR      .NOSTART
.ALIAS: PUSH    BC
        CALL    ALIASOK
        POP     BC
.NEXT:  POP     HL
        INC     HL
        JR      .SCAN
.END:   POP     HL
        LD      A,B
        CP      1
        JR      NZ,.NOSTART
        RET
.NOENTRY:
        LD      HL,210          ; L-ENTRY
        JP      ERRPLAIN
.NOSTART:
        LD      HL,212          ; L-STARTUP
        JP      ERRPLAIN

; HL = the ordinal at table position HL. Preserves BC.
POS2ORD:
        LD      DE,(LT_COUNT)
        OR      A
        SBC     HL,DE
        JR      C,.LIB
        LD      DE,$0400
        ADD     HL,DE
        RET
.LIB:   ADD     HL,DE
        RET

; HL = the entry for table position HL: the library's ordinals 0 to
; LT_COUNT - 1, then the program's. Carry past the end.
ENTRYAT:
        LD      DE,(LT_COUNT)
        OR      A
        SBC     HL,DE
        JR      NC,.PROG
        ADD     HL,DE
        JR      .ADDR
.PROG:  LD      DE,(PT_COUNT)
        OR      A
        SBC     HL,DE
        CCF
        RET     C
        ADD     HL,DE
        LD      DE,(LT_COUNT)
        ADD     HL,DE           ; position again
.ADDR:  ADD     HL,HL
        ADD     HL,HL
        ADD     HL,HL
        LD      DE,(LT_BASE)    ; the two tables are contiguous
        ADD     HL,DE
        OR      A
        RET

; Carry unless the entry at HL has DE among its edges.
HASEDGE:
        PUSH    DE
        LD      DE,E_EDGES
        ADD     HL,DE
        LD      E,(HL)
        INC     HL
        LD      D,(HL)
        EX      DE,HL           ; HL = the lowest edge, or 0
        POP     DE
        LD      A,H
        OR      L
        SCF
        RET     Z
.LOOP:  LD      A,(HL)
        INC     HL
        LD      C,(HL)
        INC     HL
        LD      B,A
        OR      C
        SCF
        RET     Z               ; the terminator
        LD      A,B
        CP      E
        JR      NZ,.LOOP
        LD      A,C
        CP      D
        JR      NZ,.LOOP
        OR      A
        RET

; Check the alias entry at HL: its base is defined, not an alias, of the
; same owner, and longer than the alias's offset (linker §4.3).
ALIASOK:
        PUSH    HL
        LD      DE,E_ADDR
        ADD     HL,DE
        LD      E,(HL)
        INC     HL
        LD      D,(HL)          ; DE = the base ordinal
        EX      DE,HL
        CALL    ENT_MAKE
        POP     DE              ; DE = the alias entry
        JR      C,.BAD
        LD      A,(HL)
        AND     F_DEF+F_ALIAS
        CP      F_DEF
        JR      NZ,.BAD
        ; the same owner: both below PT_BASE, or both above
        PUSH    HL
        PUSH    DE
        LD      BC,(PT_BASE)
        OR      A
        SBC     HL,BC
        LD      A,0
        RLA                     ; 1: the base is the library's
        EX      DE,HL
        OR      A
        SBC     HL,BC
        LD      B,A
        LD      A,0
        RLA
        CP      B
        POP     DE
        POP     HL
        JR      NZ,.BAD
        INC     HL              ; the base's size against the offset
        LD      C,(HL)
        INC     HL
        LD      B,(HL)
        EX      DE,HL
        INC     HL
        LD      E,(HL)
        INC     HL
        LD      D,(HL)          ; DE = the offset, BC = the base's size
        LD      H,B
        LD      L,C
        OR      A
        SBC     HL,DE
        JR      C,.BAD
        JR      Z,.BAD
        RET
.BAD:   LD      HL,209          ; L-ALIAS
        JP      ERRPLAIN

; ---- Phase B: mark (linker §5) ---------------------------------------------------

; The mark stack lives between the program table and the edge lists.
MK_PTR: DW      0
CLASSES: DB     0               ; bit n: a live blob of alignment class n
PHASEB: LD      HL,(PT_END)
        LD      (MK_PTR),HL
        LD      HL,0            ; the roots
.ROOTS: PUSH    HL
        CALL    ENTRYAT
        JR      C,.WORK
        LD      A,(HL)
        AND     F_ROOT+F_ALIAS+F_DEF
        CP      F_ROOT+F_DEF
        CALL    Z,MARK
        POP     HL
        INC     HL
        JR      .ROOTS
.WORK:  POP     HL
.POP:   LD      HL,(MK_PTR)     ; pop an entry
        LD      DE,(PT_END)
        OR      A
        SBC     HL,DE
        RET     Z
        LD      HL,(MK_PTR)
        DEC     HL
        LD      D,(HL)
        DEC     HL
        LD      E,(HL)
        LD      (MK_PTR),HL
        EX      DE,HL           ; HL = the entry
        LD      DE,E_EDGES
        ADD     HL,DE
        LD      E,(HL)
        INC     HL
        LD      D,(HL)
        EX      DE,HL           ; HL = its lowest edge, or 0
        LD      A,H
        OR      L
        JR      Z,.POP
.EDGE:  LD      E,(HL)
        INC     HL
        LD      D,(HL)
        INC     HL
        LD      A,D
        OR      E
        JR      Z,.POP          ; the terminator
        PUSH    HL
        CALL    FOLLOW
        POP     HL
        JR      .EDGE

; Follow edge DE: MAIN is the entry routine, FILES and FILECOUNT mean the
; program uses files, other pseudo-objects are not blobs, and an alias
; marks its base.
FOLLOW: LD      A,D
        CP      $FF
        JR      NZ,.REAL
        LD      A,E
        CP      P_FILES & $FF
        JR      Z,.FILES
        CP      P_FCNT & $FF
        JR      Z,.FILES
        CP      P_MAIN & $FF
        RET     NZ
        LD      DE,(ENTRYORD)
        JR      .REAL
.FILES: LD      A,1
        LD      (USEFILES),A
        RET
.REAL:  EX      DE,HL
        CALL    ENT_MAKE
        RET     C
        BIT     6,(HL)
        JR      Z,MARK
        LD      DE,E_ADDR       ; an alias: its base
        ADD     HL,DE
        LD      E,(HL)
        INC     HL
        LD      D,(HL)
        EX      DE,HL
        CALL    ENT_MAKE
        RET     C
; Mark the entry at HL live and push it, unless it already is, noting its
; alignment class among those present.
MARK:   BIT     5,(HL)
        RET     NZ
        SET     5,(HL)
        PUSH    HL
        LD      DE,E_LAYOUT
        ADD     HL,DE
        LD      B,(HL)
        INC     B
        LD      A,0
        SCF
.BIT:   RLA                     ; A = 1 << class
        DJNZ    .BIT
        LD      HL,CLASSES
        OR      (HL)
        LD      (HL),A
        POP     HL
        EX      DE,HL
        LD      HL,(MK_PTR)
        LD      (HL),E
        INC     HL
        LD      (HL),D
        INC     HL
        LD      (MK_PTR),HL
        LD      BC,(EL_PTR)     ; the stack must stay below the edge lists
        OR      A
        SBC     HL,BC
        JP      NC,CAPFULL
        RET

; ---- the table dump (option W) ------------------------------------------------

; NAME.$TB: for each defined entry, the ordinal, its flags and its size;
; then $FFFF and whether the program uses files. For testing the linker
; against the reference.
TB_FD:  DS      FDSIZE
TB_TY:  DB      "$TB"
DUMP:   LD      IX,TB_FD
        LD      A,(O_DRV)
        LD      HL,O_NAME
        LD      DE,TB_TY
        CALL    F_INIT
        XOR     A
        CALL    F_MAKE
        JP      C,DISKERR
        LD      HL,0            ; the position
.EACH:  PUSH    HL
        CALL    ENTRYAT
        JR      C,.END
        BIT     3,(HL)
        JR      Z,.NEXT
        POP     DE              ; the position, as an ordinal
        PUSH    DE
        PUSH    HL
        EX      DE,HL
        CALL    POS2ORD
        CALL    PUTW
        POP     HL
        LD      A,(HL)
        PUSH    HL
        CALL    PUTB
        POP     HL
        INC     HL
        LD      E,(HL)
        INC     HL
        LD      D,(HL)
        EX      DE,HL
        CALL    PUTW
.NEXT:  POP     HL
        INC     HL
        JR      .EACH
.END:   POP     HL
        LD      HL,$FFFF
        CALL    PUTW
        LD      A,(USEFILES)
        CALL    PUTB
        CALL    F_CLOSE
        JP      C,DISKERR
        RET

; Write HL, low byte first, then A, to the file at IX.
PUTW:   PUSH    HL
        LD      A,L
        CALL    PUTB
        POP     HL
        LD      A,H
PUTB:   CALL    F_PUTB
        RET     NC
DISKERR:
        LD      HL,222          ; L-IO
        LD      DE,(R_NAME)
        LD      (M_ARG1),DE
        CALL    ERROR
        CALL    ABANDON
        LD      DE,RC_DISK
        JP      EXITRC
