; Phases A and B (linker §4, §5): read the library and program directories
; into the tables of linker §2.1, check them, and mark what is live.
;
; Table entry, 8 bytes, one per ordinal:
;   +0 flags: bits 0-2 kind, 3 defined, 4 referenced, 5 live, 6 alias, 7 root
;   +1 size (an alias: its offset)   +3 address (an alias: its base ordinal)
;   +5 edges: the lowest of its distinct targets, or 0   +7 layout (alignment)
; The library table is indexed by ordinal from 0; the program table, which
; grows, by ordinal - $0400. Edge lists grow down from EDGE_TOP, each blob's a
; $0000 terminator with its targets below it.
;
; Every check that fails reports its diagnostic and ends the link (FAILED).

E_FLAGS EQU     0
E_SIZE  EQU     1
E_ADDR  EQU     3
E_EDGES EQU     5
E_LAYOUT EQU    7
EF_DEF   EQU     $08
EF_REF   EQU     $10
EF_LIVE  EQU     $20
EF_ALIAS EQU     $40
EF_ROOT  EQU     $80
K_CODE  EQU     0
K_DATA  EQU     2
K_BSS   EQU     3
K_START EQU     4
PS_MAIN  EQU     $FFE0
PS_FILES EQU     $FFE8
PS_COUNT  EQU     $FFE9
TAB_ROOM EQU   $0300          ; kept below the stack for calls and messages

LIB_HEAD:   DS      64          ; the library header and profile block
DIR_HEAD:   DS      20          ; the program directory's header
LIB_TAB: DW     0
LIB_CNT: DW    0
PRG_TAB: DW     0
PRG_CNT: DW    0
PRG_END: DW      0
EDGE_PTR: DW      0
EDGE_TOP: DW      0
PA_MAIN: DW   0
PA_ENTRY: DB  0
PA_LIMIT: DS      5             ; stack reserve, largest frame, flags
PA_LIMOK: DB    0
PA_FIRST: DB   $FF             ; the kind of the library's first record
PB_FILES: DB  0
RD_NAME: DW      0              ; the file being read, for messages

RD_OWNER: DB     0              ; 0 library, 1 program
RD_PREV: DW      0
.HASPREV: DB   0
RD_FIRST: DW     0
RD_LAST: DW      0
RD_TOTAL: DW    0
RD_LIMIT: DB    0
RD_AFTER: DB     0
RD_COUNT: DW     0
RD_SIZE: DW      0
RD_ENTRY: DW     0
EDGE_END: DW      0
REF_LAST: DW   0
REF_ANY: DB  0
REF_END: DW    0
REF_FORM: DB      0
RD_HEAD: DB    0
RD_ORD:  DW      0
REF_CNT: DW     0
DG_HEX: DS      8               ; "$HHHH" and a zero, for ordinal arguments

; ---- reading ---------------------------------------------------------------

; A = the next byte of the file at IX, added to the CRC. Preserves BC, DE,
; HL. A file that ends early is L-TRUNCATED.
RD_BYTE:   CALL    RD_RAW
        PUSH    HL              ; the CRC is checked in Phase A only
        LD      HL,RD_CRC
        INC     (HL)
        DEC     (HL)
        POP     HL
        RET     Z
        JP      CRC_ADD

RD_CRC: DB      1               ; cleared once Phase A has checked the CRCs

; The same without the CRC.
RD_RAW:  CALL    FIL_GETB
        RET     NC
DG_SHORT:
        LD      HL,214          ; L-TRUNCATED
        JR      DG_FILE

; HL = the next word. Preserves BC and DE.
RD_WORD:  CALL    RD_BYTE
        LD      L,A
        CALL    RD_BYTE
        LD      H,A
        RET

; Report message HL with the file being read as argument 1, and fail.
DG_FILE:
        PUSH    HL
        LD      HL,(RD_NAME)
        LD      (DG_ARG1),HL
        POP     HL
        CALL    DG_ERROR
        JP      LK_FAIL

; Report message HL with no argument, and fail.
DG_PLAIN:
        CALL    DG_ERROR
        JP      LK_FAIL

; Report message HL with the ordinal in DE as "$HHHH", and fail.
DG_ORD: PUSH    HL
        LD      HL,DG_HEX
        LD      (HL),'$'
        INC     HL
        LD      A,D
        CALL    .HEX2
        LD      A,E
        CALL    .HEX2
        LD      (HL),0
        LD      HL,DG_HEX
        LD      (DG_ARG1),HL
        POP     HL
        CALL    DG_ERROR
        JP      LK_FAIL
.HEX2:  PUSH    AF
        RRCA
        RRCA
        RRCA
        RRCA
        CALL    .HEX1
        POP     AF
.HEX1:  CALL    LK_DIGIT
        LD      (HL),A
        INC     HL
        RET

; A = the hex digit for A's low four bits, in ASCII.
LK_DIGIT: AND     $0F
        ADD     A,$90
        DAA
        ADC     A,$40
        DAA
        RET

; ---- tables ------------------------------------------------------------------

; HL = the entry of ordinal HL, creating program entries as needed. Carry if
; the ordinal has no entry: a pseudo-object, or a library ordinal beyond the
; library's highest.
TAB_FIND:
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
        LD      DE,(LIB_CNT)
        OR      A
        SBC     HL,DE
        CCF
        RET     C               ; beyond the library
        ADD     HL,DE
        ADD     HL,HL
        ADD     HL,HL
        ADD     HL,HL
        LD      DE,(LIB_TAB)
        ADD     HL,DE
        OR      A
        RET
.PROG:  LD      DE,$0400
        OR      A
        SBC     HL,DE           ; HL = index
        PUSH    HL
        LD      DE,(PRG_CNT)
        OR      A
        SBC     HL,DE
        JR      C,.HAVE
        ; grow to index + 1, zeroing the new entries
        POP     HL
        PUSH    HL
        INC     HL
        LD      (PRG_CNT),HL
        ADD     HL,HL
        ADD     HL,HL
        ADD     HL,HL
        LD      DE,(PRG_TAB)
        ADD     HL,DE           ; the new end
        EX      DE,HL
        LD      HL,(EDGE_PTR)
        OR      A
        SBC     HL,DE
        JR      C,DG_CAP        ; it meets the edge lists
        LD      HL,(PRG_END)
.ZERO:  LD      A,L
        CP      E
        JR      NZ,.ZEROONE
        LD      A,H
        CP      D
        JR      Z,.ZEROED
.ZEROONE:    LD      (HL),0
        INC     HL
        JR      .ZERO
.ZEROED: LD      (PRG_END),DE
.HAVE:  POP     HL
        ADD     HL,HL
        ADD     HL,HL
        ADD     HL,HL
        LD      DE,(PRG_TAB)
        ADD     HL,DE
        OR      A
        RET

DG_CAP:
        LD      HL,215          ; L-CAP-TABLES
        JP      DG_PLAIN

; Push word DE onto the edge lists. Preserves BC and DE.
EDGE_ADD:
        LD      HL,(EDGE_PTR)
        DEC     HL
        DEC     HL
        LD      (EDGE_PTR),HL
        PUSH    HL
        PUSH    DE
        LD      DE,(PRG_END)
        OR      A
        SBC     HL,DE
        POP     DE
        POP     HL
        JR      C,DG_CAP
        LD      (HL),E
        INC     HL
        LD      (HL),D
        RET

; ---- Phase A -----------------------------------------------------------------

PA_RUN: ; the tables start above the program and the edge lists below the stack
        LD      HL,(LIB_HEAD+36) ; the library's highest ordinal
        INC     HL
        LD      (LIB_CNT),HL
        ADD     HL,HL
        ADD     HL,HL
        ADD     HL,HL
        LD      B,H
        LD      C,L             ; BC = the library table's bytes
        LD      HL,FREEMEM
        LD      (LIB_TAB),HL
        ADD     HL,BC
        LD      (PRG_TAB),HL
        LD      (PRG_END),HL
        LD      HL,0
        ADD     HL,SP
        LD      DE,TAB_ROOM
        OR      A
        SBC     HL,DE
        LD      (EDGE_TOP),HL
        LD      (EDGE_PTR),HL
        LD      DE,(PRG_TAB)
        OR      A
        SBC     HL,DE
        JR      C,DG_CAP
        LD      HL,(LIB_TAB)    ; zero the library table
.CLR:   LD      A,B
        OR      C
        JR      Z,.LIB
        LD      (HL),0
        INC     HL
        DEC     BC
        JR      .CLR
        ; the library's directory, its CRC from the directory's start
.LIB:   LD      IX,LIB_FD
        LD      HL,LIB_TEXT
        LD      (RD_NAME),HL
        LD      A,(LIB_HEAD+14)
        LD      HL,(LIB_HEAD+12)
        CALL    FIL_SEEK
        JP      C,DG_SHORT
        CALL    CRC_NEW
        XOR     A
        LD      (RD_OWNER),A
        LD      HL,1
        LD      (RD_FIRST),HL
        LD      HL,$03FF
        LD      (RD_LAST),HL
        LD      HL,0            ; the implicit first ordinal: $0001 - 1
        CALL    .READDIR
        ; the trailer must agree with the header
        LD      HL,(RD_BYTES)
        LD      DE,(LIB_HEAD+20)
        OR      A
        SBC     HL,DE
        JP      NZ,DG_SHORT
        LD      HL,(RD_HIGH)
        LD      DE,(LIB_HEAD+36)
        OR      A
        SBC     HL,DE
        JP      NZ,DG_SHORT
        ; the program's directory
        CALL    DIR_OPEN
        LD      A,1
        LD      (RD_OWNER),A
        LD      HL,$0400
        LD      (RD_FIRST),HL
        LD      HL,$FFDF
        LD      (RD_LAST),HL
        LD      HL,(DIR_HEAD+16) ; the ordinal base
        DEC     HL
        CALL    .READDIR
        JP      PA_CHECK

; Read records from the file at IX until the trailer. HL = the implicit
; ordinal before the first.
.READDIR:
        LD      (RD_PREV),HL
        LD      HL,0
        LD      (RD_TOTAL),HL
        LD      (RD_COUNT),HL
        XOR     A
        LD      (RD_LIMIT),A
        LD      (RD_AFTER),A
PA_NEXT: CALL    RD_BYTE
        CP      $FF
        JP      Z,PA_TRAIL
        LD      (RD_HEAD),A
        AND     7
        CP      6
        JP      Z,PA_CTRL
        CP      5
        JP      NC,DG_SPARE
        LD      A,(RD_LIMIT)
        LD      (RD_AFTER),A
        ; the ordinal: explicit, or one more than the last
        LD      A,(RD_HEAD)
        BIT     3,A
        JR      Z,.IMPL
        CALL    RD_WORD
        JR      .ORD
.IMPL:  LD      HL,(RD_PREV)
        INC     HL
.ORD:   LD      (RD_ORD),HL
        LD      (RD_PREV),HL
        CALL    PA_RANGE
        LD      HL,205          ; L-ORDINAL: outside its range
        LD      DE,(RD_ORD)
        JP      C,DG_ORD
        CALL    RD_WORD
        LD      (RD_SIZE),HL
        LD      A,H
        OR      L
        LD      HL,207          ; L-BLOB: a blob of size 0
        JP      Z,DG_PLAIN
        CALL    RD_BYTE
        LD      L,A
        LD      H,0
        CP      255
        JR      NZ,.COUNT
        CALL    RD_WORD
.COUNT: LD      (REF_CNT),HL
        ; checks on the kind
        LD      A,(RD_HEAD)
        AND     7
        LD      C,A             ; C = kind
        CP      K_CODE
        JR      Z,.NOALIGN
        CP      K_START
        JR      NZ,.ALIGNOK
        LD      A,(RD_OWNER)
        OR      A
        LD      HL,207          ; L-BLOB: startup in the program
        JP      NZ,DG_PLAIN
.NOALIGN:
        LD      A,(RD_HEAD)
        AND     $E0
        LD      HL,207          ; L-BLOB: aligned code or startup
        JP      NZ,DG_PLAIN
.ALIGNOK:
        LD      A,C
        CP      K_BSS
        JR      NZ,.NOTBSS
        LD      HL,(REF_CNT)
        LD      A,H
        OR      L
        LD      HL,207          ; L-BLOB: bss with references
        JP      NZ,DG_PLAIN
.NOTBSS:
        LD      A,(RD_OWNER)    ; the library's first record
        OR      A
        JR      NZ,.ENTRY
        LD      A,(PA_FIRST)
        INC     A
        JR      NZ,.ENTRY
        LD      A,C
        LD      (PA_FIRST),A
.ENTRY: LD      HL,(RD_ORD)
        CALL    TAB_FIND
        LD      (RD_ENTRY),HL
        LD      DE,(RD_ORD)
        LD      HL,205          ; L-ORDINAL: beyond the library's highest
        JP      C,DG_ORD
        LD      HL,(RD_ENTRY)
        BIT     3,(HL)
        LD      HL,205          ; L-ORDINAL: defined twice
        JP      NZ,DG_ORD
        LD      HL,(RD_ENTRY)
        LD      A,(RD_HEAD)
        AND     7
        OR      EF_DEF
        LD      B,A
        LD      A,(RD_HEAD)
        AND     $10             ; root
        RLCA
        RLCA
        RLCA                    ; to bit 7
        OR      B
        LD      (HL),A
        INC     HL
        LD      DE,(RD_SIZE)
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
        LD      A,(RD_HEAD)
        RLCA
        RLCA
        RLCA
        AND     7
        LD      (HL),A          ; layout: the alignment code
        ; the byte stream: every kind but bss
        LD      A,C
        CP      K_BSS
        JR      Z,.REFS
        LD      HL,(RD_TOTAL)
        LD      DE,(RD_SIZE)
        ADD     HL,DE
        JP      C,DG_SHORT
        LD      (RD_TOTAL),HL
.REFS:  LD      HL,(RD_COUNT)
        INC     HL
        LD      (RD_COUNT),HL
        CALL    PA_REFS
        JP      PA_NEXT

; Carry unless ordinal HL lies in RD_FIRST..D_LAST.
PA_RANGE:
        LD      DE,(RD_FIRST)
        OR      A
        SBC     HL,DE
        RET     C
        ADD     HL,DE
        EX      DE,HL
        LD      HL,(RD_LAST)
        OR      A
        SBC     HL,DE           ; carry if ordinal > last
        RET

DG_SPARE:
        LD      HL,206          ; L-RESERVED
        JP      DG_PLAIN

; The references of the blob just read: REF_CNT of them, at RD_ENTRY.
PA_REFS:   LD      HL,(REF_CNT)
        LD      A,H
        OR      L
        RET     Z
        LD      DE,0            ; the blob's terminator
        CALL    EDGE_ADD
        LD      HL,(EDGE_PTR)
        LD      (EDGE_END),HL
        XOR     A
        LD      (REF_ANY),A
        LD      HL,0
        LD      (REF_END),HL
.NEXT:  CALL    RD_BYTE         ; control
        LD      B,A
        AND     $3F
        CP      63
        JR      NZ,.DELTA
        CALL    RD_WORD         ; an absolute offset
        LD      A,(REF_ANY)
        OR      A
        JR      Z,.OFF
        PUSH    HL
        LD      DE,(REF_LAST)
        EX      DE,HL
        OR      A
        SBC     HL,DE           ; last - offset: no carry means not increasing
        POP     HL
        JP      NC,DG_REF
        JR      .OFF
.DELTA: LD      L,A
        LD      H,0
        LD      A,(REF_ANY)
        OR      A
        JR      Z,.OFF
        LD      A,L
        OR      A
        JR      Z,DG_REF        ; a zero delta
        LD      DE,(REF_LAST)
        ADD     HL,DE
.OFF:   LD      (REF_LAST),HL
        LD      A,1
        LD      (REF_ANY),A
        ; the form
        XOR     A
        BIT     7,B
        JR      Z,.FORM
        CALL    RD_BYTE
        OR      A
        JR      Z,DG_SPARE      ; form byte 0
.FORM:  LD      (REF_FORM),A
        CP      4
        JR      NC,DG_SPARE     ; BANK8 and beyond
        ; the width: ABS16 and SIZE16 2 bytes, LO8 and HI8 1
        LD      E,2
        CP      1
        JR      Z,.NARROW
        CP      2
        JR      NZ,.WIDTH
.NARROW:    LD      E,1
.WIDTH: LD      D,0             ; DE = width
        PUSH    BC
        LD      HL,(REF_LAST)
        LD      BC,(REF_END)
        OR      A
        SBC     HL,BC
        POP     BC
        JR      C,DG_REF        ; overlaps the previous reference
        LD      HL,(REF_LAST)
        ADD     HL,DE
        LD      (REF_END),HL
        EX      DE,HL
        LD      HL,(RD_SIZE)
        OR      A
        SBC     HL,DE
        JR      C,DG_REF        ; leaves the blob
        ; the target
        CALL    RD_WORD
        PUSH    HL
        BIT     6,B
        JR      Z,.NOADD
        CALL    RD_WORD         ; the addend: not needed until Phase D
.NOADD: POP     HL
        CALL    PA_TGT
        LD      HL,(REF_CNT)
        DEC     HL
        LD      (REF_CNT),HL
        LD      A,H
        OR      L
        JP      NZ,.NEXT
        ; the blob's edges field: its lowest target
        LD      HL,(RD_ENTRY)
        LD      DE,E_EDGES
        ADD     HL,DE
        LD      DE,(EDGE_PTR)
        LD      (HL),E
        INC     HL
        LD      (HL),D
        RET

DG_REF: LD      HL,208          ; L-REFERENCE
        JP      DG_PLAIN

; Check target HL of a reference and add it to the blob's edges if new.
PA_TGT: LD      A,H
        OR      L
        JR      Z,DG_REF        ; ordinal 0
        LD      A,H
        CP      $FF
        JR      NZ,.REAL
        LD      A,L
        CP      $E0
        JR      C,.REAL
        CP      $EA
        JR      NC,DG_REF       ; an undefined pseudo-object
        JR      .ADD
.REAL:  LD      A,(RD_OWNER)    ; the library refers only to itself
        OR      A
        JR      NZ,.MARK
        LD      A,H
        CP      $04
        JR      NC,DG_REF
        PUSH    HL
        LD      DE,(LIB_HEAD+36)
        EX      DE,HL
        OR      A
        SBC     HL,DE           ; highest - target
        POP     HL
        JR      C,DG_REF
.MARK:  PUSH    HL
        CALL    TAB_FIND        ; referenced; carry: beyond the library
        JR      C,.UNDEF
        LD      A,(REF_FORM)    ; SIZE16 of a known alias
        CP      3
        JR      NZ,.SETREF
        BIT     6,(HL)
        JR      NZ,DG_REF
.SETREF:
        SET     4,(HL)
        POP     HL
.ADD:   EX      DE,HL           ; DE = the target
        LD      HL,(EDGE_PTR)   ; already among this blob's edges?
.SCAN:  PUSH    DE
        LD      DE,(EDGE_END)
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
.NEW:   JP      EDGE_ADD
.UNDEF: POP     DE
        LD      HL,213          ; L-UNDEFINED
        JP      DG_ORD

; A control record: alias, entry, bank or limits.
PA_CTRL:
        LD      A,(RD_OWNER)    ; the library's first record isn't startup
        OR      A
        JR      NZ,.KIND
        LD      A,(PA_FIRST)
        INC     A
        JR      NZ,.KIND
        LD      A,$FE
        LD      (PA_FIRST),A
.KIND:  LD      A,(RD_HEAD)
        RRCA
        RRCA
        RRCA
        AND     $1F
        JR      Z,.ALIAS
        DEC     A
        JR      Z,.ENTRY
        DEC     A
        JP      Z,DG_SPARE      ; BANK is reserved in 1.0
        DEC     A
        JP      NZ,DG_SPARE
        ; LIMITS, once, in the program
        LD      A,(RD_OWNER)
        OR      A
        JR      Z,.BADLIM
        LD      A,(PA_LIMOK)
        OR      A
        JR      NZ,.BADLIM
        INC     A
        LD      (PA_LIMOK),A
        LD      (RD_LIMIT),A
        LD      HL,PA_LIMIT
        LD      B,5
.LIM:   CALL    RD_BYTE
        LD      (HL),A
        INC     HL
        DJNZ    .LIM
        JP      PA_NEXT
.BADLIM:
        LD      HL,211          ; L-LIMITS
        JP      DG_PLAIN

.ENTRY:
        CALL    RD_WORD
        LD      A,(RD_OWNER)
        OR      A
        JR      Z,.BADENTRY
        LD      A,(PA_ENTRY)
        OR      A
        JR      NZ,.BADENTRY
        INC     A
        LD      (PA_ENTRY),A
        LD      (PA_MAIN),HL
        JP      PA_NEXT
.BADENTRY:   LD      HL,210     ; L-ENTRY
        JP      DG_PLAIN

.ALIAS:  CALL    RD_WORD        ; the alias
        LD      (RD_ORD),HL
        CALL    PA_RANGE
        LD      DE,(RD_ORD)
        LD      HL,209          ; L-ALIAS: outside its range
        JP      C,DG_ORD
        LD      HL,(RD_ORD)
        CALL    TAB_FIND
        LD      (RD_ENTRY),HL
        LD      DE,(RD_ORD)
        LD      HL,205
        JP      C,DG_ORD
        LD      HL,(RD_ENTRY)
        BIT     3,(HL)
        LD      HL,205          ; L-ORDINAL: defined twice
        JP      NZ,DG_ORD
        CALL    RD_WORD         ; the base
        PUSH    HL
        CALL    RD_WORD         ; the offset
        EX      DE,HL           ; DE = offset
        POP     BC              ; BC = base
        LD      HL,(RD_ENTRY)
        LD      (HL),EF_DEF+EF_ALIAS
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
        CALL    TAB_FIND
        POP     DE
        LD      HL,209          ; L-ALIAS: a bad base
        JP      C,DG_ORD
        SET     4,(HL)
        JP      PA_NEXT

; The trailer: counts, then the CRC of everything before the CRC.
RD_BYTES: DW   0
RD_HIGH: DW    0
PA_TRAIL:
        CALL    RD_WORD         ; the blob count
        LD      DE,(RD_COUNT)
        OR      A
        SBC     HL,DE
        JP      NZ,DG_SHORT
        CALL    RD_WORD         ; the byte stream's length, low then high
        LD      (RD_BYTES),HL
        CALL    RD_WORD
        LD      A,H
        OR      L
        JP      NZ,DG_SHORT     ; at most 64K
        CALL    RD_WORD
        LD      (RD_HIGH),HL
        CALL    RD_BYTE         ; reserved
        LD      HL,(CRC_VAL)
        PUSH    HL
        CALL    RD_RAW
        LD      E,A
        CALL    RD_RAW
        LD      D,A
        POP     HL
        OR      A
        SBC     HL,DE
        JP      NZ,DG_SHORT     ; the CRC
        LD      HL,(RD_TOTAL)   ; the records account for the stream
        LD      DE,(RD_BYTES)
        OR      A
        SBC     HL,DE
        JP      NZ,DG_SHORT
        LD      A,(RD_AFTER)
        OR      A
        LD      HL,211          ; L-LIMITS: blobs after LIMITS
        JP      NZ,DG_PLAIN
        RET

; Open NAME.$DR on the spool drive and check its header against the library
; (linker §4.3; object format §10).
DIR_FD:  DS      FD_SIZE
DIR_TYPE:  DB      "$DR"
DIR_TEXT: DS      13
DIR_OPEN:
        LD      IX,DIR_FD
        LD      A,(OP_SPOOL)
        OR      A
        JR      NZ,.DRV
        LD      A,(CMD_DISK)
.DRV:   LD      HL,CMD_NAME
        LD      DE,DIR_TYPE
        CALL    FIL_INIT
        LD      HL,CMD_NAME     ; its name as text
        LD      DE,DIR_TEXT
        LD      BC,DIR_TYPE
        CALL    FIL_TEXT
        LD      HL,DIR_TEXT
        LD      (RD_NAME),HL
        CALL    FIL_OPEN
        LD      HL,225          ; L-MISSING
        JP      C,DG_FILE
        CALL    CRC_NEW
        LD      HL,DIR_HEAD
        LD      B,20
.HEAD:  CALL    RD_BYTE
        LD      (HL),A
        INC     HL
        DJNZ    .HEAD
        LD      HL,DIR_HEAD     ; magic and version
        LD      DE,.MAGIC
        LD      B,4
.COMPARE:   LD      A,(DE)
        CP      (HL)
        JR      NZ,.BADMAG
        INC     HL
        INC     DE
        DJNZ    .COMPARE
        LD      A,(DIR_HEAD+4)
        CP      1
        LD      HL,200          ; L-FORMAT
        JP      NZ,DG_FILE
        LD      A,(DIR_HEAD+5)
        OR      A
        JP      NZ,DG_FILE
        ; compatibility: runtime and profile identities, helper table
        LD      HL,(DIR_HEAD+8)
        LD      DE,(LIB_HEAD+6)
        OR      A
        SBC     HL,DE
        JR      NZ,.COMPAT
        LD      HL,(DIR_HEAD+14)
        LD      DE,(LIB_HEAD+10)
        OR      A
        SBC     HL,DE
        JR      NZ,.COMPAT
        LD      HL,(LIB_HEAD+8) ; the library's version, at least the program's
        LD      DE,(DIR_HEAD+10)
        OR      A
        SBC     HL,DE
        JR      C,.COMPAT
        LD      HL,(DIR_HEAD+12) ; the program's key, unless 0
        LD      A,H
        OR      L
        JR      Z,.STAMP
        CALL    .LIBKEY
        LD      DE,(DIR_HEAD+12)
        OR      A
        SBC     HL,DE
        JR      NZ,.COMPAT
.STAMP: LD      HL,(DIR_HEAD+6)
        LD      A,H
        OR      L
        LD      HL,202          ; L-STAMP: stamp 0
        JP      Z,DG_PLAIN
        JR      .PROFILE
.COMPAT:
        LD      HL,201          ; L-COMPAT
        JP      DG_PLAIN
.BADMAG:
        LD      HL,200          ; L-FORMAT
        JP      DG_FILE
.MAGIC: DB      "BSIP"

; Check the options and output kind against the profile (linker §3). ROM
; targets, class 3 and above, are not implemented: L-RESERVED.
.PROFILE:
        LD      HL,206          ; L-RESERVED
        LD      A,(LIB_HEAD+42) ; the target class
        CP      3
        JP      NC,DG_PLAIN
        LD      HL,203          ; L-OPTION
        LD      A,(OP_FLAGS)
        AND     OF_B
        JR      Z,.BCHECKED
        LD      A,(LIB_HEAD+58) ; option support: bit 0 keep the CCP
        RRA
        JP      NC,DG_PLAIN
.BCHECKED:   LD      A,(OP_FLAGS)
        AND     OF_R
        JR      Z,.RCHECKED
        LD      A,(LIB_HEAD+58) ; bit 1 re-runnable
        AND     2
        JP      Z,DG_PLAIN
.RCHECKED:   INC     HL         ; L-OUTPUT
        LD      A,(LIB_HEAD+43) ; the output kinds
        LD      DE,OUT_KIND
        EX      DE,HL
        AND     (HL)
        EX      DE,HL
        JP      Z,DG_PLAIN
        LD      A,(DE)          ; .COM needs image base $0100
        DEC     A
        RET     NZ
        LD      DE,(LIB_HEAD+44)
        DEC     D
        LD      A,D
        OR      E
        RET     Z
        JP      DG_PLAIN

; HL = the library's key for the program's helper-table version. The key
; table is a count, then a key per version. The library file stays at IX's
; position for the program, so a second FD is not needed: the library's FD
; is used and left at the key table.
.LIBKEY: PUSH    IX
        LD      IX,LIB_FD
        LD      A,(LIB_HEAD+34)
        LD      HL,(LIB_HEAD+32)
        CALL    FIL_SEEK
        JP      C,DG_SHORT
        CALL    RD_RAW
        LD      L,A
        CALL    RD_RAW
        LD      H,A             ; HL = the count
        LD      DE,(DIR_HEAD+10) ; the program's version, 1 to count
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
        CALL    RD_RAW
        CALL    RD_RAW
        JR      .SKIP
.KEY:   CALL    RD_RAW
        LD      L,A
        CALL    RD_RAW
        LD      H,A
        POP     IX
        RET
.NONE:  POP     IX
        LD      HL,201          ; L-COMPAT
        JP      DG_PLAIN

; Write the file name NAME.TYP as text at DE: HL = the 8-character name,
; BC = the 3-character type.
FIL_TEXT:
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

PA_CHECK: LD      A,(PA_ENTRY) ; ENTRY names a program code blob
        OR      A
        JR      Z,.NOENTRY
        LD      HL,(PA_MAIN)
        LD      A,H
        CP      $04
        JR      C,.NOENTRY
        CALL    TAB_FIND
        JR      C,.NOENTRY
        LD      A,(HL)
        AND     EF_DEF+EF_ALIAS+7
        CP      EF_DEF+K_CODE
        JR      NZ,.NOENTRY
        LD      A,(PA_LIMOK)
        OR      A
        LD      HL,211          ; L-LIMITS: missing
        JP      Z,DG_PLAIN
        LD      A,(PA_FIRST)   ; startup is the library's first record
        CP      K_START
        JR      NZ,.NOSTART
        ; scan every entry: one startup, references defined, aliases sound
        LD      B,0             ; startups seen
        LD      HL,0            ; the ordinal
.SCAN:  PUSH    HL
        PUSH    BC
        CALL    TAB_AT          ; HL = the entry, carry past the end
        POP     BC
        JR      C,.END
        LD      A,(HL)
        BIT     3,A
        JR      NZ,.DEF
        BIT     4,A
        JR      Z,.NEXT
        POP     HL              ; referenced but never defined
        CALL    TAB_ORD
        EX      DE,HL
        LD      HL,213          ; L-UNDEFINED
        JP      DG_ORD
.DEF:   BIT     6,A
        JR      NZ,.ALIAS
        AND     7
        CP      K_START
        JR      NZ,.NEXT
        INC     B
        PUSH    HL              ; startup must refer to MAIN
        PUSH    BC
        LD      DE,PS_MAIN
        CALL    EDGE_HAS
        POP     BC
        POP     HL
        JR      NC,.NEXT
        POP     HL
        JR      .NOSTART
.ALIAS: PUSH    BC
        CALL    PA_ALIAS
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
        JP      DG_PLAIN
.NOSTART:
        LD      HL,212          ; L-STARTUP
        JP      DG_PLAIN

; HL = the ordinal at table position HL. Preserves BC.
TAB_ORD:
        LD      DE,(LIB_CNT)
        OR      A
        SBC     HL,DE
        JR      C,.LIB
        LD      DE,$0400
        ADD     HL,DE
        RET
.LIB:   ADD     HL,DE
        RET

; HL = the entry for table position HL: the library's ordinals 0 to
; LIB_CNT - 1, then the program's. Carry past the end.
TAB_AT:
        LD      DE,(LIB_CNT)
        OR      A
        SBC     HL,DE
        JR      NC,.PROG
        ADD     HL,DE
        JR      .ADDR
.PROG:  LD      DE,(PRG_CNT)
        OR      A
        SBC     HL,DE
        CCF
        RET     C
        ADD     HL,DE
        LD      DE,(LIB_CNT)
        ADD     HL,DE           ; position again
.ADDR:  ADD     HL,HL
        ADD     HL,HL
        ADD     HL,HL
        LD      DE,(LIB_TAB)    ; the two tables are contiguous
        ADD     HL,DE
        OR      A
        RET

; Carry unless the entry at HL has DE among its edges.
EDGE_HAS:
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
PA_ALIAS:
        PUSH    HL
        LD      DE,E_ADDR
        ADD     HL,DE
        LD      E,(HL)
        INC     HL
        LD      D,(HL)          ; DE = the base ordinal
        EX      DE,HL
        CALL    TAB_FIND
        POP     DE              ; DE = the alias entry
        JR      C,.BAD
        LD      A,(HL)
        AND     EF_DEF+EF_ALIAS
        CP      EF_DEF
        JR      NZ,.BAD
        ; the same owner: both below PRG_TAB, or both above
        PUSH    HL
        PUSH    DE
        LD      BC,(PRG_TAB)
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
        JP      DG_PLAIN

; ---- Phase B: mark (linker §5) ---------------------------------------------------

; The mark stack lives between the program table and the edge lists.
PB_STACK: DW      0
PB_CLASS: DB     0              ; bit n: a live blob of alignment class n
PB_RUN: LD      HL,(PRG_END)
        LD      (PB_STACK),HL
        LD      HL,0            ; the roots
.ROOTS: PUSH    HL
        CALL    TAB_AT
        JR      C,.WORK
        LD      A,(HL)
        AND     EF_ROOT+EF_ALIAS+EF_DEF
        CP      EF_ROOT+EF_DEF
        CALL    Z,.MARK
        POP     HL
        INC     HL
        JR      .ROOTS
.WORK:  POP     HL
.POP:   LD      HL,(PB_STACK)   ; pop an entry
        LD      DE,(PRG_END)
        OR      A
        SBC     HL,DE
        RET     Z
        LD      HL,(PB_STACK)
        DEC     HL
        LD      D,(HL)
        DEC     HL
        LD      E,(HL)
        LD      (PB_STACK),HL
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
        CALL    .FOLLOW
        POP     HL
        JR      .EDGE

; Follow edge DE: MAIN is the entry routine, FILES and FILECOUNT mean the
; program uses files, other pseudo-objects are not blobs, and an alias
; marks its base.
.FOLLOW: LD      A,D
        CP      $FF
        JR      NZ,.REAL
        LD      A,E
        CP      PS_FILES & $FF
        JR      Z,.FILES
        CP      PS_COUNT & $FF
        JR      Z,.FILES
        CP      PS_MAIN & $FF
        RET     NZ
        LD      DE,(PA_MAIN)
        JR      .REAL
.FILES: LD      A,1
        LD      (PB_FILES),A
        RET
.REAL:  EX      DE,HL
        CALL    TAB_FIND
        RET     C
        BIT     6,(HL)
        JR      Z,.MARK
        LD      DE,E_ADDR       ; an alias: its base
        ADD     HL,DE
        LD      E,(HL)
        INC     HL
        LD      D,(HL)
        EX      DE,HL
        CALL    TAB_FIND
        RET     C
; Mark the entry at HL live and push it, unless it already is, noting its
; alignment class among those present.
.MARK:   BIT     5,(HL)
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
        LD      HL,PB_CLASS
        OR      (HL)
        LD      (HL),A
        POP     HL
        EX      DE,HL
        LD      HL,(PB_STACK)
        LD      (HL),E
        INC     HL
        LD      (HL),D
        INC     HL
        LD      (PB_STACK),HL
        LD      BC,(EDGE_PTR)   ; the stack must stay below the edge lists
        OR      A
        SBC     HL,BC
        JP      NC,DG_CAP
        RET

; ---- the table dump (option W) ------------------------------------------------

; NAME.$TB: for each defined entry, the ordinal, its flags and its size;
; then $FFFF and whether the program uses files. For testing the linker
; against the reference.
TB_TYPE:  DB      "$TB"
TB_WRITE:   LD      IX,TB_FD
        LD      A,(CMD_DISK)
        LD      HL,CMD_NAME
        LD      DE,TB_TYPE
        CALL    FIL_INIT
        XOR     A
        CALL    FIL_MAKE
        JR      C,DG_DISK
        LD      HL,0            ; the position
.EACH:  PUSH    HL
        CALL    TAB_AT
        JR      C,.END
        BIT     3,(HL)
        JR      Z,.NEXT
        POP     DE              ; the position, as an ordinal
        PUSH    DE
        PUSH    HL
        EX      DE,HL
        CALL    TAB_ORD
        CALL    .PUTW
        POP     HL
        LD      A,(HL)
        PUSH    HL
        CALL    .PUTB
        POP     HL
        INC     HL
        LD      E,(HL)
        INC     HL
        LD      D,(HL)
        EX      DE,HL
        CALL    .PUTW
.NEXT:  POP     HL
        INC     HL
        JR      .EACH
.END:   POP     HL
        LD      HL,$FFFF
        CALL    .PUTW
        LD      A,(PB_FILES)
        CALL    .PUTB
        CALL    FIL_SHUT
        JR      C,DG_DISK
        RET

; Write HL, low byte first, then A, to the file at IX.
.PUTW:   LD      A,L
        CALL    .PUTB
        LD      A,H
.PUTB:   CALL    FIL_PUTB
        RET     NC
DG_DISK:
        LD      HL,222          ; L-IO
        LD      DE,(RD_NAME)
        LD      (DG_ARG1),DE
        CALL    DG_ERROR
        CALL    PUB_UNDO
        LD      DE,RC_DISK
        JP      CPM_EXIT
