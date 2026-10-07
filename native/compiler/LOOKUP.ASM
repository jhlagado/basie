;==========================================================================
;  Trap lookup
;==========================================================================
;
;  BASIE NAME [T=hhhh] (toolchain §8, design decision D47): the statement
;  whose code holds address hhhh, from NAME.LIN, the line table, and its
;  source part, as the reference's trapLookup (ref/toolchain/traplookup.ts)
;  prints it. Part of the COMMAND overlay, which reads the command line;
;  nothing is compiled. The table must be version 2.0, whole and its own
;  CRC's; a program file NAME.COM, NAME.BIN or NAME.HEX must be the one it
;  describes (its image CRC). Then the entry with the greatest address not
;  above hhhh names the statement:
;
;      MAIN.BSI 57:9  total = items[index]
;
;  the part, the line and the column, and the line's text from the column
;  on (the part alone when it can't be read); or the address is outside the
;  stored code, or in a blob without source, named by its ordinal.
;
;  Principal entry:
;    LK_RUN    look the address up and print it; no return
;
;  Its workspace is the blob writer's, which a lookup doesn't use.

LK_BUF EQU  MM_BLOB            ; 128 bytes: the record being read.
LK_PTR EQU  LK_BUF+128         ; Word: its next byte.
LK_LEFT EQU  LK_PTR+2          ; Byte: its bytes left.
LK_ADDR EQU  LK_LEFT+1         ; Word: the address looked up.
LK_CRC EQU  LK_ADDR+2          ; Word: a CRC being formed.
LK_ICRC EQU  LK_CRC+2          ; Word: the table's image CRC.
LK_CNT EQU  LK_ICRC+2          ; Word: the table's entries read.
LK_PCNT EQU  LK_CNT+2          ; Byte: its parts.
LK_SEEN EQU  LK_PCNT+1         ; Byte: nonzero once a program file is found.
LK_ENT EQU  LK_SEEN+1          ; 6 bytes: the entry being read.
LK_BEST EQU  LK_ENT+6          ; 6 bytes: the best entry; part $FE if none.
LK_TEXT EQU  LK_BEST+6         ; 256 bytes: the part's name, zero-terminated.

;@ROUTINE NORETURN
; Look the address of option T up (toolchain §8) and print what it finds,
; then end: a failure as SH_FAIL ends, an answer by a warm boot.

LK_RUN:                        ; Option T was given.
    LD   HL,(CL_TPOS)              ; T=hhhh:
    INC  HL                        ; past
    INC  HL                        ; T=,
    CALL LK_HEXV                   ; the address,
    LD   (LK_ADDR),DE              ; kept.
    LD   HL,LK_TLIN                ; NAME.LIN,
    CALL LK_OPEN                   ; open,
    JP   C,LK_NOLIN                ; or not found.
    LD   HL,$FFFF                  ; Its CRC
    LD   (LK_CRC),HL               ; starts.
    CALL LK_HEAD                   ; Its header, to the part names,
    LD   A,(LK_PCNT)               ; past
    CALL LK_NAMES                  ; them all.
    LD   HL,0                      ; No entries
    LD   (LK_CNT),HL               ; yet,
    LD   A,$FE                     ; and no
    LD   (LK_BEST+2),A             ; best one.
.ENTRY:                        ; The next entry, or the trailer.
    LD   HL,LK_ENT                 ; Its
    LD   B,6                       ; six
.BYTE:                         ; bytes,
    CALL LK_TGET                   ; read
    LD   (HL),A                    ; into
    INC  HL                        ; LK_ENT.
    DJNZ .BYTE                     ; Then:
    LD   HL,LK_ENT                 ; six
    LD   B,6                       ; $FF
    LD   A,$FF                     ; bytes
.FF:                           ; are
    AND  (HL)                      ; the
    INC  HL                        ; trailer's
    DJNZ .FF                       ; marker.
    INC  A                         ; Zero
    JR   Z,.TRAIL                  ; if so.
    LD   HL,(LK_CNT)               ; Another
    INC  HL                        ; entry,
    LD   (LK_CNT),HL               ; counted:
    LD   HL,(LK_ADDR)              ; at or
    LD   DE,(LK_ENT)               ; below
    OR   A                         ; the
    SBC  HL,DE                     ; address
    JR   C,.ENTRY                  ; (not past it),
    LD   HL,LK_ENT                 ; the best
    LD   DE,LK_BEST                ; so far,
    LD   BC,6                      ; in
    LDIR                           ; order.
    JR   .ENTRY                    ; The next.
.TRAIL:                        ; The trailer:
    CALL LK_TWORD                  ; the entry count,
    LD   HL,(LK_CNT)               ; which must be
    OR   A                         ; those
    SBC  HL,DE                     ; read;
    JP   NZ,LK_BAD                 ; the image's
    CALL LK_TWORD                  ; CRC,
    LD   (LK_ICRC),DE              ; kept;
    CALL LK_GET                    ; and the table's
    JP   C,LK_BAD                  ; CRC,
    LD   E,A                       ; read
    CALL LK_GET                    ; as it
    JP   C,LK_BAD                  ; is stored,
    LD   D,A                       ; must
    LD   HL,(LK_CRC)               ; be the
    OR   A                         ; one
    SBC  HL,DE                     ; formed.
    JP   NZ,LK_BAD                 ; Else damaged.
    XOR  A                         ; No program
    LD   (LK_SEEN),A               ; file found yet:
    LD   HL,LK_KINDS               ; COM, BIN, HEX
.KIND:                         ; in turn.
    PUSH HL                        ; (kept)
    CALL LK_OPEN                   ; One there?
    JR   C,.OTHER                  ; Not this.
    LD   A,1                       ; Found:
    LD   (LK_SEEN),A               ; its CRC
    LD   HL,$FFFF                  ; over
    LD   (LK_CRC),HL               ; every
.SUM:                          ; byte
    CALL LK_GET                    ; of its
    JR   C,.SUMMED                 ; records,
    LD   HL,LK_CRC                 ; as
    CALL OUT_UPD                   ; stored,
    JR   .SUM                      ; must be
.SUMMED:                       ; the
    LD   HL,(LK_CRC)               ; table's
    LD   DE,(LK_ICRC)              ; image
    OR   A                         ; CRC.
    SBC  HL,DE                     ; The
    JR   Z,.MATCH                  ; one.
.OTHER:                        ; Not this kind:
    POP  HL                        ; the
    INC  HL                        ; next,
    INC  HL                        ; three
    INC  HL                        ; on,
    LD   A,(HL)                    ; until
    OR   A                         ; the
    JR   NZ,.KIND                  ; last.
    LD   A,(LK_SEEN)               ; None matched:
    OR   A                         ; the table is
    JP   NZ,LK_STALE               ; another program's,
    JP   LK_NOCOM                  ; or there is none.
.MATCH:                        ; The program is the table's.
    POP  HL                        ; (dropped)
    LD   A,(LK_BEST+2)             ; The best entry's part:
    CP   $FE                       ; none
    JP   Z,LK_OUT                  ; (outside),
    INC  A                         ; $FF
    JP   Z,LK_BLOB                 ; (a blob without source),
    JP   LK_PART                   ; or a part.

;@ROUTINE CLOBBERS A,BC,DE,HL,CARRY,ZERO,SIGN,PARITY,HALFCARRY
; Read the line table's header from its magic to its part count (LK_PCNT),
; checking its magic and version 2.0 (LK_BAD otherwise), and skip its
; output and library names.

LK_HEAD:                       ; The table is open, at its start.
    LD   HL,LK_MAGIC               ; Its
    LD   B,4                       ; magic,
.MAGIC:                        ; four
    CALL LK_TGET                   ; bytes,
    CP   (HL)                      ; BSIT,
    JP   NZ,LK_BAD                 ; else
    INC  HL                        ; damaged;
    DJNZ .MAGIC                    ; then
    CALL LK_TGET                   ; major
    CP   2                         ; 2
    JP   NZ,LK_BAD                 ; and
    CALL LK_TGET                   ; minor
    OR   A                         ; 0;
    JP   NZ,LK_BAD                 ; the
    CALL LK_TGET                   ; part
    LD   (LK_PCNT),A               ; count;
    LD   A,2                       ; two names
                                   ; skipped; fall into LK_NAMES.

;@ROUTINE IN A CLOBBERS A,BC,DE,HL,CARRY,ZERO,SIGN,PARITY,HALFCARRY
; Skip A of the table's names, each a length and its bytes.

LK_NAMES:                      ; A is the count.
    OR   A                         ; None
    RET  Z                         ; left.
    PUSH AF                        ; (kept)
    CALL LK_TGET                   ; A name's
    LD   B,A                       ; length,
    INC  B                         ; B
.SKIP:                         ; bytes
    DEC  B                         ; skipped.
    JR   Z,.NEXT                   ; Then
    CALL LK_TGET                   ; the
    JR   .SKIP                     ; next
.NEXT:                         ; name.
    POP  AF                        ; One
    DEC  A                         ; fewer.
    JR   LK_NAMES                  ; Go on.

;@ROUTINE NORETURN
; The best entry names a part: print it, its line and its column, and the
; line's text from the column on when the part can be read.

LK_PART:                       ; LK_BEST is the entry.
    LD   HL,LK_TLIN                ; The table
    CALL LK_OPEN                   ; again,
    CALL LK_HEAD                   ; past its header
    LD   A,(LK_BEST+2)             ; and the names
    CALL LK_NAMES                  ; before the part's;
    CALL LK_TGET                   ; its name's
    LD   B,A                       ; length,
    LD   HL,LK_TEXT                ; then
    INC  B                         ; its
.NAME:                         ; bytes,
    DEC  B                         ; to
    JR   Z,.NAMED                  ; LK_TEXT,
    CALL LK_TGET                   ; one
    LD   (HL),A                    ; by
    INC  HL                        ; one,
    JR   .NAME                     ; and
.NAMED:                        ; a zero.
    LD   (HL),B                    ; (B is zero.)
    LD   HL,LK_TEXT                ; PART
    CALL SH_PRINT                  ; LINE:
    LD   A,' '                     ; COLUMN:
    CALL SH_CHAR                   ; the
    LD   HL,(LK_BEST+3)            ; line,
    CALL LK_DEC                    ; a colon,
    LD   A,':'                     ; and
    CALL SH_CHAR                   ; the
    LD   A,(LK_BEST+5)             ; column,
    LD   L,A                       ; in
    LD   H,0                       ; decimal.
    CALL LK_DEC                    ; Then the text:
    LD   HL,LK_TEXT                ; the part,
    CALL CL_NAME                   ; named,
    JR   C,LK_DONE                 ; and
    LD   DE,SH_FCB                 ; opened
    LD   C,SH_OPEN                 ; (else
    CALL SH_BDOS                   ; the
    INC  A                         ; position
    JR   Z,LK_DONE                 ; alone);
    XOR  A                         ; its
    LD   (LK_LEFT),A               ; records
    LD   HL,LK_TWO                 ; from the
    CALL SH_PRINT                  ; start, after two spaces.
    LD   HL,(LK_BEST+3)            ; The line:
.LINE:                         ; HL lines are left.
    DEC  HL                        ; Its
    LD   A,H                       ; start
    OR   L                         ; is
    JR   Z,.COLUMN                 ; after
.FIND:                         ; HL-1
    CALL LK_GET                    ; line
    JR   C,LK_DONE                 ; feeds
    CP   10                        ; (none: it
    JR   NZ,.FIND                  ; is empty).
    JR   .LINE                     ; Then
.COLUMN:                       ; its column:
    LD   A,(LK_BEST+5)             ; column
    LD   B,A                       ; less one
.SPAN:                         ; bytes
    DEC  B                         ; passed,
    JR   Z,.TEXT                   ; unless
    CALL LK_GET                    ; the line
    JR   C,LK_DONE                 ; ends
    CALL LK_EOL                    ; first;
    JR   Z,LK_DONE                 ; then
    JR   .SPAN                     ; the
.TEXT:                         ; text
    CALL LK_GET                    ; to
    JR   C,LK_DONE                 ; the
    CALL LK_EOL                    ; line's
    JR   Z,LK_DONE                 ; end,
    CALL SH_CHAR                   ; printed.
    JR   .TEXT                     ; Done.

;@ROUTINE NORETURN
; End an answer: the line, then a warm boot.

LK_DONE:                       ; The answer is printed.
    LD   HL,LK_EOLS                ; CR LF,
    CALL SH_PRINT                  ; then
    JP   0                         ; a warm boot.

;@ROUTINE NORETURN
; The address is below the first entry: outside the stored code.

LK_OUT:                        ; No entry is at or below it.
    CALL LK_PADDR                  ; hhhh
    LD   HL,LK_MOUT                ; is outside
    CALL SH_PRINT                  ; the stored
    JR   LK_DONE                   ; code.

;@ROUTINE NORETURN
; The address is in a blob without source: its ordinal.

LK_BLOB:                       ; LK_BEST is its start entry.
    CALL LK_PADDR                  ; hhhh
    LD   HL,LK_MBLOB               ; is in blob
    CALL SH_PRINT                  ; oooo,
    LD   HL,(LK_BEST+3)            ; which
    CALL LK_HEX4                   ; has
    LD   HL,LK_MNSRC               ; no
    CALL SH_PRINT                  ; source.
    JR   LK_DONE                   ; Done.

;@ROUTINE CLOBBERS A,B,HL,IX,IY,CARRY,ZERO,SIGN,PARITY,HALFCARRY
; Print the address looked up as four hexadecimal digits.

LK_PADDR:                      ; LK_ADDR is the address.
    LD   HL,(LK_ADDR)              ; The address; fall into LK_HEX4.

;@ROUTINE IN HL CLOBBERS A,B,HL,IX,IY,CARRY,ZERO,SIGN,PARITY,HALFCARRY
; Print HL as four hexadecimal digits, upper-case.

LK_HEX4:                       ; HL is the word.
    LD   B,4                       ; Four digits,
.DIGIT:                        ; from the top:
    XOR  A                         ; the next
    ADD  HL,HL                     ; four bits
    RLA                            ; into
    ADD  HL,HL                     ; A,
    RLA                            ; one
    ADD  HL,HL                     ; by
    RLA                            ; one,
    ADD  HL,HL                     ; as
    RLA                            ; a
    ADD  A,$90                     ; digit
    DAA                            ; or
    ADC  A,$40                     ; letter
    DAA                            ; (the runtime's way),
    CALL SH_CHAR                   ; printed.
    DJNZ .DIGIT                    ; Four.
    RET                            ; Done.

;@ROUTINE IN HL CLOBBERS A,BC,DE,HL,IX,IY,CARRY,ZERO,SIGN,PARITY,HALFCARRY
; Print HL in decimal, without leading zeros.

LK_DEC:                        ; HL is the number.
    LD   DE,LK_TENS                ; The powers of ten,
    LD   C,0                       ; no digit printed yet.
.POWER:                        ; DE is the next.
    PUSH DE                        ; (kept)
    EX   DE,HL                     ; Its
    LD   A,(HL)                    ; value,
    INC  HL                        ; BC
    LD   H,(HL)                    ; would
    LD   L,A                       ; clobber C:
    EX   DE,HL                     ; DE is it.
    LD   B,'0'-1                   ; The digit:
.SUB:                          ; how many
    INC  B                         ; times it
    OR   A                         ; goes
    SBC  HL,DE                     ; into
    JR   NC,.SUB                   ; HL.
    ADD  HL,DE                     ; (the last undone)
    LD   A,B                       ; Printed
    CP   '0'                       ; unless
    JR   NZ,.PRINT                 ; a leading
    INC  C                         ; zero
    DEC  C                         ; (the units'
    JR   NZ,.PRINT                 ; always:
    LD   A,E                       ; DE is
    DEC  A                         ; one
    OR   D                         ; then).
    JR   NZ,.NEXT                  ; Skipped.
    LD   A,B                       ; The digit:
.PRINT:                        ; A is it.
    CALL SH_CHAR                   ; Printed;
    LD   C,1                       ; digits follow.
.NEXT:                         ; The next power,
    POP  DE                        ; two
    INC  DE                        ; bytes
    INC  DE                        ; on,
    LD   A,E                       ; until past
    CP   LOW(LK_TENS+10)           ; the units.
    JR   NZ,.POWER                 ; Go on.
    RET                            ; Done.

;@ROUTINE IN A OUT ZERO CLOBBERS CARRY,SIGN,PARITY,HALFCARRY
; Z when A ends a line: CR, LF or CP/M's end of text ($1A). A is kept.

LK_EOL:                        ; A is a byte of the part.
    CP   13                        ; CR,
    RET  Z                         ; LF
    CP   10                        ; or
    RET  Z                         ; $1A
    CP   $1A                       ; end
    RET                            ; it.

;@ROUTINE IN HL OUT DE,HL CLOBBERS A,ZERO,SIGN,PARITY,HALFCARRY,CARRY
; The hexadecimal number at HL, its digits already checked, in DE; HL past
; it.

LK_HEXV:                       ; HL is its first digit.
    LD   DE,0                      ; None yet.
.NEXT:                         ; The next character:
    LD   A,(HL)                    ; a digit
    SUB  '0'                       ; 0-9
    RET  C                         ; or
    CP   10                        ; A-F
    JR   C,.ADD                    ; adds
    SUB  7                         ; its
    CP   10                        ; value;
    RET  C                         ; anything
    CP   16                        ; else
    RET  NC                        ; ends it.
.ADD:                          ; A is its value.
    EX   DE,HL                     ; The number
    ADD  HL,HL                     ; times
    ADD  HL,HL                     ; sixteen
    ADD  HL,HL                     ; plus
    ADD  HL,HL                     ; it,
    OR   L                         ; in
    LD   L,A                       ; DE.
    EX   DE,HL                     ; The
    INC  HL                        ; next.
    JR   .NEXT                     ; Go on.

;@ROUTINE IN HL OUT CARRY CLOBBERS A,BC,DE,HL,ZERO,SIGN,PARITY,HALFCARRY
; Open NAME.TYP, the command line's first name with the three-letter type
; at HL, on its drive, read from its start; carry if it is not there.

LK_OPEN:                       ; HL is the type.
    PUSH HL                        ; (kept)
    CALL SH_BLANK                  ; A clear FCB,
    LD   HL,SH_NAMES               ; the first name's
    LD   DE,SH_FCB                 ; drive and
    LD   BC,9                      ; name,
    LDIR                           ; then
    POP  HL                        ; the
    LD   BC,3                      ; type.
    LDIR                           ; Open it:
    XOR  A                         ; no bytes
    LD   (LK_LEFT),A               ; read yet.
    LD   DE,SH_FCB                 ; $FF
    LD   C,SH_OPEN                 ; when
    CALL SH_BDOS                   ; it is
    ADD  A,1                       ; absent:
    RET                            ; carry.

;@ROUTINE OUT A,CARRY CLOBBERS ZERO,SIGN,PARITY,HALFCARRY
; The next byte of the file open in SH_FCB, through LK_BUF; carry at its
; end. BC, DE and HL are kept.

LK_GET:                        ; The file is open.
    PUSH BC                        ; Keep
    PUSH DE                        ; the
    PUSH HL                        ; registers.
    LD   A,(LK_LEFT)               ; Bytes left
    OR   A                         ; in the record?
    JR   NZ,.HAVE                  ; If not,
    LD   DE,LK_BUF                 ; the next
    LD   C,SH_DMA                  ; record
    CALL SH_BDOS                   ; is
    LD   DE,SH_FCB                 ; read
    LD   C,SH_READ                 ; there,
    CALL SH_BDOS                   ; or the file
    OR   A                         ; ends
    SCF                            ; (carry).
    JR   NZ,.DONE                  ; A record:
    LD   HL,LK_BUF                 ; from its
    LD   (LK_PTR),HL               ; start,
    LD   A,128                     ; 128 bytes.
.HAVE:                         ; A bytes are left.
    DEC  A                         ; One
    LD   (LK_LEFT),A               ; fewer:
    LD   HL,(LK_PTR)               ; the
    LD   A,(HL)                    ; next,
    INC  HL                        ; and
    LD   (LK_PTR),HL               ; past it.
    OR   A                         ; Carry clear.
.DONE:                         ; Done.
    POP  HL                        ; The
    POP  DE                        ; registers
    POP  BC                        ; again.
    RET                            ; A is the byte.

;@ROUTINE OUT A CLOBBERS CARRY,ZERO,SIGN,PARITY,HALFCARRY
; The next byte of the line table, folded into its CRC (LK_CRC); its end
; is damage (LK_BAD). BC, DE and HL are kept.

LK_TGET:                       ; The table is open.
    CALL LK_GET                    ; The byte,
    JR   C,LK_BAD                  ; or damage.
    PUSH BC                        ; (B and
    PUSH HL                        ; HL kept)
    LD   HL,LK_CRC                 ; Folded
    CALL OUT_UPD                   ; into the CRC.
    POP  HL                        ; HL
    POP  BC                        ; and BC.
    RET                            ; A is the byte.

;@ROUTINE OUT DE CLOBBERS A,CARRY,ZERO,SIGN,PARITY,HALFCARRY
; The next word of the line table, low byte first, in DE.

LK_TWORD:                      ; The table is open.
    CALL LK_TGET                   ; The low
    LD   E,A                       ; byte,
    CALL LK_TGET                   ; the high
    LD   D,A                       ; byte.
    RET                            ; DE is the word.

;@ROUTINE NORETURN
; Failures, each naming NAME.LIN or NAME.COM, then failing as SH_FAIL
; does.

LK_BAD:                        ; The table is damaged.
    LD   DE,LK_MBAD                ; Damaged,
    JR   LK_LIN                    ; after NAME.LIN.
LK_NOLIN:                      ; The table is not there.
    LD   DE,LK_MNF                 ; Not found,
    JR   LK_LIN                    ; after NAME.LIN.
LK_STALE:                      ; The program is not the table's.
    LD   DE,LK_MOLD                ; Not the program's,
LK_LIN:                        ; DE is the message.
    LD   HL,LK_TLIN                ; NAME.LIN,
    JR   LK_FAIL                   ; then it.
LK_NOCOM:                      ; No program file.
    LD   DE,LK_MNF                 ; Not found,
    LD   HL,LK_KINDS               ; after NAME.COM.
LK_FAIL:                       ; HL is a type, DE a message.
    PUSH DE                        ; (kept)
    PUSH HL                        ; (the type)
    LD   HL,SH_NAMES+1             ; The name,
    LD   B,8                       ; to its
.NAME:                         ; first
    LD   A,(HL)                    ; space,
    CP   ' '                       ; or
    JR   Z,.TYPE                   ; all
    CALL SH_CHAR                   ; eight
    INC  HL                        ; characters;
    DJNZ .NAME                     ; then
.TYPE:                         ; a dot
    LD   A,'.'                     ; and
    CALL SH_CHAR                   ; the
    POP  HL                        ; type's
    LD   B,3                       ; three
.LETTER:                       ; letters;
    LD   A,(HL)                    ; then
    CALL SH_CHAR                   ; the
    INC  HL                        ; message,
    DJNZ .LETTER                   ; and
    POP  HL                        ; the
    JP   SH_FAIL                   ; failure.

; ---- data -------------------------------------------------------------------

LK_TLIN: DB  "LIN"             ; The line table's type.
LK_KINDS: DB  "COMBINHEX",0    ; The program's types, in the order tried.
LK_MAGIC: DB  "BSIT"           ; The line table's magic.
LK_TENS: DW  10000,1000,100,10,1 ; Powers of ten for LK_DEC.
LK_TWO: DB  "  ",0             ; Between a position and its text.
LK_EOLS: DB  13,10,0           ; The end of an answer.
LK_MOUT: DB  " is outside the stored code",0
LK_MBLOB: DB  " is in blob ",0
LK_MNSRC: DB  ", which has no source",0
LK_MNF: DB  " not found",0
LK_MBAD: DB  " is damaged",0
LK_MOLD: DB  " doesn't match the program",0
