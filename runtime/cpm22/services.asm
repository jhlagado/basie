; ---------------------------------------------------------------------------
; Basie services for CP/M 2.2 (docs/services.md, revision 2).
;
; Services are called like Basie routines (code generation §3): arguments on
; the stack, a frame in IX, results in A, HL or DEHL, and on failure carry
; set with the code in A. A File is 4 bytes: an entry address and its
; generation; console is 1 and printer is 2, recognised before the table.
;
; The file table (FILES, FILECNT entries) is allocated by the linker only
; when a program opens files. Each entry is ENTSZ bytes:
;   +0  generation (2)       +2  state: 0 free, 1 read, 2 write, 3 append,
;   +3  mode: 0 text, 1 binary        4 update
;   +4  FCB (36): +4 drive, +5 name, +13 type, +16 ex, +36 cr, +37 r0-r2
;   +40 position in the buffer, 0 to 128
;   +41 flags: bit 0 dirty, 1 loaded, 2 end of text, 3 last byte read was
;       CR, 4 a CR waits to be written, 7 poisoned by a full disk
;   +42 the buffered record (3)    +45 high-water mark in records (3)
;   +48 the target's type, for openWrite (3)    +51 the entry's index
;   +56 the record buffer (128)
; File-layer routines take the entry in IY and preserve it.
; ---------------------------------------------------------------------------

ENTSZ   EQU     184
EBUF    EQU     56
TEXTM   EQU     0
E_EOF   EQU     1
E_STORE EQU     4
E_NOTFN EQU     5
E_EXIST EQU     6
E_NAME  EQU     7
E_MANY  EQU     8
E_CLOSD EQU     9
E_DFULL EQU     10
E_DIRFL EQU     11
E_RO    EQU     12
E_SEEK  EQU     13
E_LONG  EQU     14
E_NOTAV EQU     15
E_BUSY  EQU     16
E_NOSRC EQU     17
E_MODE  EQU     18
E_INVAL EQU     254
CTRLZ   EQU     $1A

; @blob $045 bss FL_VAR
; +0 a search is in progress  +1 the output kind  +2 count  +3 capacity
; +4 flags  +5 wildcards allowed  +6 the FCB being parsed (2)  +8 pointer (2)
FL_VAR: DS      12

; @blob $046 bss FL_FCB
; Scratch FCBs for directory services: +0 the first, +36 the second.
FL_FCB: DS      72

; @blob $047 bss CON_VAR
; +0 a key is held  +1 the held key  +2 console input has ended
CON_VAR:
        DS      3

; @blob $048 bss CON_BUF
; BDOS 10's buffer: maximum, count, up to 253 characters.
CON_BUF:
        DS      256

; ---- the console ----------------------------------------------------------

; @blob $049 code CON_KEY
; Wait for one key, without echo: the held key first. Returns A.
CON_KEY:
        LD      A,(CON_VAR)
        OR      A
        JR      Z,.POLL
        XOR     A
        LD      (CON_VAR),A
        LD      A,(CON_VAR+1)
        RET
.POLL:  LD      C,6
        LD      E,$FF
        CALL    BDOS
        OR      A
        JR      Z,.POLL
        RET

; @blob $04A code CON_GET
; readByte on the console: one key, echoed. Control-Z ends console input,
; for the rest of the run. Returns A, or carry with endOfInput.
CON_GET:
        LD      A,(CON_VAR+2)
        OR      A
        JR      NZ,.EOF
        CALL    CON_KEY
        CP      CTRLZ
        JR      Z,.SET
        PUSH    AF
        CALL    CON_OUT
        POP     AF
        OR      A
        RET
.SET:   LD      (CON_VAR+2),A
.EOF:   LD      A,E_EOF
        SCF
        RET

; @blob $04B code PRN_OUT
; Write A to the printer (BDOS 5). Preserves HL.
PRN_OUT:
        PUSH    HL
        LD      E,A
        LD      C,5
        CALL    BDOS
        POP     HL
        OR      A
        RET

; ---- the file layer -------------------------------------------------------

; @blob $04C code FL_FILE
; HL = a File's address, DE = its generation. Returns A = 1 console,
; 2 printer, or 3 with IY = the entry; carry with fileClosed otherwise.
FL_FILE:
        LD      A,H
        OR      A
        JR      NZ,.ENTRY
        LD      A,L
        CP      1
        RET     Z
        CP      2
        RET     Z
.CLOSED:
        LD      A,E_CLOSD
        SCF
        RET
.ENTRY: PUSH    HL
        POP     IY
        LD      A,(IY+0)
        CP      E
        JR      NZ,.CLOSED
        LD      A,(IY+1)
        CP      D
        JR      NZ,.CLOSED
        LD      A,(IY+2)
        OR      A
        JR      Z,.CLOSED
        LD      A,3
        OR      A
        RET

; @blob $04D code FL_IO
; Call BDOS function C on the entry's FCB with the DMA at its buffer, then
; restore the runtime's DMA and end any directory search. Returns A.
FL_IO:  PUSH    BC
        PUSH    IY
        POP     HL
        LD      DE,EBUF
        ADD     HL,DE
        EX      DE,HL
        LD      C,26
        CALL    BDOS
        POP     BC
        PUSH    IY
        POP     HL
        INC     HL
        INC     HL
        INC     HL
        INC     HL
        EX      DE,HL
        CALL    BDOS
        PUSH    AF
        LD      DE,DMA_BUF
        LD      C,26
        CALL    BDOS
        XOR     A
        LD      (FL_VAR),A
        POP     AF
        RET

; @blob $04E code BDOS_DE
; Call BDOS function C with DE, ending any directory search. Returns A.
BDOS_DE:
        PUSH    BC
        XOR     A
        LD      (FL_VAR),A
        POP     BC
        JP      BDOS

; @blob $04F code FL_SETR
; Copy the buffered record number into the FCB's random-record field.
FL_SETR:
        LD      A,(IY+42)
        LD      (IY+37),A
        LD      A,(IY+43)
        LD      (IY+38),A
        LD      A,(IY+44)
        LD      (IY+39),A
        RET

; @blob $050 code FL_FILL
; Read the buffered record. Returns carry with endOfInput past the end of
; the file, or storageFailure.
FL_FILL:
        CALL    FL_SETR
        LD      C,33
        CALL    FL_IO
        OR      A
        JR      Z,.OK
        CP      1
        JR      Z,.EOF
        CP      4
        JR      Z,.EOF
        LD      A,E_STORE
        SCF
        RET
.EOF:   LD      A,E_EOF
        SCF
        RET
.OK:    SET     1,(IY+41)
        OR      A
        RET

; @blob $051 code FL_FIL
; Fill the buffer with A and mark it loaded.
FL_FIL: PUSH    IY
        POP     HL
        LD      DE,EBUF
        ADD     HL,DE
        LD      B,128
.LOOP:  LD      (HL),A
        INC     HL
        DJNZ    .LOOP
        SET     1,(IY+41)
        RET

; @blob $052 code FL_FLUSH
; Write the buffer if it holds unwritten bytes, and raise the high-water
; mark. A full disk poisons an openWrite file.
FL_FLUSH:
        BIT     0,(IY+41)
        RET     Z
        CALL    FL_SETR
        LD      C,34
        CALL    FL_IO
        OR      A
        JR      Z,.OK
        CP      5
        LD      A,E_DIRFL
        JR      Z,.FAIL
        LD      A,E_DFULL
.FAIL:  SET     7,(IY+41)
        SCF
        RET
.OK:    RES     0,(IY+41)
        LD      L,(IY+42)
        LD      H,(IY+43)
        LD      A,(IY+44)
        INC     L
        JR      NZ,.CMP
        INC     H
        JR      NZ,.CMP
        INC     A
.CMP:   CP      (IY+47)
        JR      C,.DONE
        JR      NZ,.SET
        LD      B,A
        LD      A,H
        CP      (IY+46)
        LD      A,B
        JR      C,.DONE
        JR      NZ,.SET
        LD      B,A
        LD      A,L
        CP      (IY+45)
        LD      A,B
        JR      C,.DONE
        JR      Z,.DONE
.SET:   LD      (IY+45),L
        LD      (IY+46),H
        LD      (IY+47),A
.DONE:  OR      A
        RET

; @blob $053 code FL_NEXT
; Move to the next record, not yet loaded.
FL_NEXT:
        INC     (IY+42)
        JR      NZ,.DONE
        INC     (IY+43)
        JR      NZ,.DONE
        INC     (IY+44)
.DONE:  LD      (IY+40),0
        RES     1,(IY+41)
        RET

; @blob $054 code FL_GETB
; The next byte of the file in A; carry with endOfInput or storageFailure.
FL_GETB:
        BIT     1,(IY+41)
        JR      Z,.LOAD
        LD      A,(IY+40)
        CP      128
        JR      C,.TAKE
        CALL    FL_FLUSH
        RET     C
        CALL    FL_NEXT
.LOAD:  CALL    FL_FILL
        RET     C
.TAKE:  LD      E,(IY+40)
        INC     (IY+40)
        LD      D,0
        PUSH    IY
        POP     HL
        ADD     HL,DE
        LD      DE,EBUF
        ADD     HL,DE
        LD      A,(HL)
        OR      A
        RET

; @blob $055 code FL_PUTB
; Write the byte in A. A new record of a new file starts filled with
; Control-Z in text mode and zero in binary mode, so the last record is
; already padded. Carry with the code on failure.
FL_PUTB:
        BIT     7,(IY+41)
        JR      Z,.OPEN
        LD      A,E_DFULL
        SCF
        RET
.OPEN:  LD      C,A
        PUSH    BC
        BIT     1,(IY+41)
        JR      Z,.LOAD
        LD      A,(IY+40)
        CP      128
        JR      C,.PUT
        CALL    FL_FLUSH
        JR      C,.FAIL
        CALL    FL_NEXT
.LOAD:  LD      A,(IY+2)
        CP      2
        JR      Z,.FRESH
        CALL    FL_FILL
        JR      NC,.PUT
        CP      E_EOF
        JR      NZ,.FAIL
.FRESH: LD      A,(IY+3)
        OR      A
        LD      A,0
        JR      NZ,.ZERO
        LD      A,CTRLZ
.ZERO:  CALL    FL_FIL
.PUT:   POP     BC
        LD      E,(IY+40)
        INC     (IY+40)
        LD      D,0
        PUSH    IY
        POP     HL
        ADD     HL,DE
        LD      DE,EBUF
        ADD     HL,DE
        LD      (HL),C
        SET     0,(IY+41)
        OR      A
        RET
.FAIL:  POP     BC
        SCF
        RET

; @blob $056 code FL_TGET
; The next text byte: CR LF, lone LF and lone CR each give 10, and
; Control-Z or the physical end ends the text, for good.
FL_TGET:
        BIT     2,(IY+41)
        JR      NZ,.EOF
.AGAIN: CALL    FL_GETB
        JR      C,.ERR
        CP      CTRLZ
        JR      Z,.SET
        CP      13
        JR      Z,.CR
        CP      10
        JR      Z,.LF
        RES     3,(IY+41)
        OR      A
        RET
.CR:    SET     3,(IY+41)
        LD      A,10
        OR      A
        RET
.LF:    BIT     3,(IY+41)
        RES     3,(IY+41)
        JR      NZ,.AGAIN
        LD      A,10
        OR      A
        RET
.ERR:   CP      E_EOF
        JR      Z,.SET
        SCF
        RET
.SET:   SET     2,(IY+41)
.EOF:   LD      A,E_EOF
        SCF
        RET

; @blob $057 code FL_TPUT
; Write a text byte: 10 becomes CR LF, and a CR written just before 10 is
; absorbed into it.
FL_TPUT:
        CP      13
        JR      NZ,.NOTCR
        BIT     4,(IY+41)
        JR      Z,.HOLD
        LD      A,13
        CALL    FL_PUTB
        RET     C
.HOLD:  SET     4,(IY+41)
        OR      A
        RET
.NOTCR: CP      10
        JR      NZ,.PLAIN
        RES     4,(IY+41)
        LD      A,13
        CALL    FL_PUTB
        RET     C
        LD      A,10
        JP      FL_PUTB
.PLAIN: BIT     4,(IY+41)
        JP      Z,FL_PUTB
        PUSH    AF
        RES     4,(IY+41)
        LD      A,13
        CALL    FL_PUTB
        POP     BC
        RET     C
        LD      A,B
        JP      FL_PUTB

; @blob $058 code FL_RD
; Read one byte of a file in its mode. Only read and update files.
FL_RD:  LD      A,(IY+2)
        CP      1
        JR      Z,.OK
        CP      4
        JR      Z,.OK
        LD      A,E_MODE
        SCF
        RET
.OK:    LD      A,(IY+3)
        OR      A
        JP      Z,FL_TGET
        JP      FL_GETB

; @blob $059 code FL_WR
; Write the byte in A to a file in its mode. Not read files.
FL_WR:  LD      C,A
        LD      A,(IY+2)
        CP      1
        JR      NZ,.OK
        LD      A,E_MODE
        SCF
        RET
.OK:    LD      A,(IY+3)
        OR      A
        LD      A,C
        JP      Z,FL_TPUT
        JP      FL_PUTB

; @blob $05A code OUT_ANY
; Write A to the File kind in FL_VAR+1 (1 console, 2 printer, 3 IY's file).
OUT_ANY:
        LD      C,A
        LD      A,(FL_VAR+1)
        CP      3
        LD      A,C
        JP      Z,FL_WR
        LD      B,A
        LD      A,(FL_VAR+1)
        CP      2
        LD      A,B
        JP      Z,PRN_OUT
        CALL    CON_OUT
        OR      A
        RET

; @blob $05B code FL_FREE
; Release an entry: state free, generation advanced (saturating), so the
; old File value no longer matches.
FL_FREE:
        LD      (IY+2),0
        LD      L,(IY+0)
        LD      H,(IY+1)
        INC     HL
        LD      A,H
        OR      L
        RET     Z
        LD      (IY+0),L
        LD      (IY+1),H
        RET

; @blob $05C code FL_ALLOC
; Find a free entry: IY = the entry, cleared, with its index; carry with
; tooManyFiles. Nothing is committed until the caller sets the state.
FL_ALLOC:
        LD      HL,FILECNT
        LD      A,L
        OR      A
        JR      Z,.FULL
        LD      B,A
        LD      C,0
        LD      IY,FILES
.SCAN:  LD      A,(IY+2)
        OR      A
        JR      Z,.FOUND
        LD      DE,ENTSZ
        ADD     IY,DE
        INC     C
        DJNZ    .SCAN
.FULL:  LD      A,E_MANY
        SCF
        RET
.FOUND: PUSH    IY
        POP     HL
        INC     HL
        INC     HL
        LD      B,54
.CLEAR: LD      (HL),0
        INC     HL
        DJNZ    .CLEAR
        LD      (IY+51),C
        LD      A,(IY+0)
        OR      (IY+1)
        JR      NZ,.HOOK
        LD      (IY+0),1
.HOOK:  LD      HL,FL_END
        LD      (EXIT_HK),HL
        OR      A
        RET

; @blob $05D code FL_RES
; Return the entry as a File in DEHL, carry clear.
FL_RES:
        PUSH    IY
        POP     HL
        LD      E,(IY+0)
        LD      D,(IY+1)
        OR      A
        RET

; @blob $05E code FL_SIZE
; The file's size in records into the high-water mark (BDOS 35).
FL_SIZE:
        LD      C,35
        CALL    FL_IO
        LD      A,(IY+37)
        LD      (IY+45),A
        LD      A,(IY+38)
        LD      (IY+46),A
        LD      A,(IY+39)
        LD      (IY+47),A
        RET

; @blob $05F code FL_PARSE
; Parse the string at HL into the FCB at DE (services §4.1): an optional
; drive letter and colon, a name of 1 to 8 characters, an optional dot and
; type of up to 3. Lower case becomes upper case. FL_VAR+5 nonzero allows ?
; and *. A missing drive becomes the current one, so equal names compare
; equal. Carry with badName.
FL_PARSE:
        LD      (FL_VAR+6),DE
        PUSH    HL
        LD      H,D
        LD      L,E
        LD      B,36
.ZERO:  LD      (HL),0
        INC     HL
        DJNZ    .ZERO
        LD      H,D
        LD      L,E
        INC     HL
        LD      B,11
.SPACE: LD      (HL),' '
        INC     HL
        DJNZ    .SPACE
        POP     HL
        LD      C,(HL)          ; C = characters left
        INC     HL
        LD      A,C
        CP      2
        JR      C,.NODRV
        INC     HL
        LD      A,(HL)
        DEC     HL
        CP      ':'
        JR      NZ,.NODRV
        LD      A,(HL)
        CALL    .UPPER
        SUB     'A'
        CP      16
        JP      NC,.BAD
        INC     A
        LD      DE,(FL_VAR+6)
        LD      (DE),A
        INC     HL
        INC     HL
        DEC     C
        DEC     C
        JR      .NAME
.NODRV: PUSH    HL
        PUSH    BC
        LD      C,25
        CALL    BDOS
        POP     BC
        POP     HL
        INC     A
        LD      DE,(FL_VAR+6)
        LD      (DE),A
.NAME:  LD      DE,(FL_VAR+6)
        INC     DE
        LD      B,8
        CALL    .FIELD
        JP      C,.BAD
        OR      A
        JP      Z,.BAD          ; an empty name
        LD      A,C
        OR      A
        RET     Z               ; no type: carry clear
        LD      A,(HL)
        CP      '.'
        JP      NZ,.BAD
        INC     HL
        DEC     C
        LD      DE,(FL_VAR+6)
        LD      A,9
        ADD     A,E
        LD      E,A
        JR      NC,.TYPE
        INC     D
.TYPE:  LD      B,3
        CALL    .FIELD
        JP      C,.BAD
        LD      A,C
        OR      A
        JP      NZ,.BAD         ; characters left over
        LD      DE,(FL_VAR+6)
        LD      HL,9
        ADD     HL,DE
        LD      A,(HL)
        CP      '$'
        JP      Z,.BAD          ; types beginning $ are reserved
        OR      A
        RET
.BAD:   LD      A,E_NAME
        SCF
        RET
; Copy up to B characters from HL (C left) to DE until a dot or the end.
; Returns A = the number copied, carry if a character is invalid or the
; part is too long.
.FIELD: PUSH    BC
        LD      A,B
        LD      (FL_VAR+2),A
        POP     BC
        LD      B,0             ; B = copied
.CHAR:  LD      A,C
        OR      A
        JR      Z,.END
        LD      A,(HL)
        CP      '.'
        JR      Z,.END
        LD      A,(FL_VAR+2)
        CP      B
        JR      Z,.LONG
        LD      A,(HL)
        CP      '*'
        JR      Z,.STAR
        CP      '?'
        JR      Z,.WILD
        CALL    .UPPER
        CALL    .VALID
        JR      C,.LONG
.STORE: LD      (DE),A
        INC     DE
        INC     HL
        DEC     C
        INC     B
        JR      .CHAR
.WILD:  LD      A,(FL_VAR+5)
        OR      A
        JR      Z,.LONG
        LD      A,'?'
        JR      .STORE
.STAR:  LD      A,(FL_VAR+5)
        OR      A
        JR      Z,.LONG
        INC     HL              ; consume the star
        DEC     C
.FILL:  LD      A,(FL_VAR+2)
        CP      B
        JR      Z,.END
        LD      A,'?'
        LD      (DE),A
        INC     DE
        INC     B
        JR      .FILL
.END:   LD      A,B
        OR      A
        RET
.LONG:  SCF
        RET
.UPPER: CP      'a'
        RET     C
        CP      'z'+1
        RET     NC
        SUB     $20
        RET
; Carry unless A is a letter, a digit or one of ! # $ % & ' ( ) - @ ^ _ ` { } ~
.VALID: CP      '0'
        JR      C,.PUNCT
        CP      '9'+1
        JR      C,.OK
        CP      'A'
        JR      C,.PUNCT
        CP      'Z'+1
        JR      C,.OK
.PUNCT: PUSH    HL
        PUSH    BC
        LD      HL,.SET
        LD      B,17
.SCAN:  CP      (HL)
        JR      Z,.FOUND
        INC     HL
        DJNZ    .SCAN
        POP     BC
        POP     HL
        SCF
        RET
.FOUND: POP     BC
        POP     HL
.OK:    OR      A
        RET
.SET:   DB      "!#$%&'()-@^_`{}~"
        DB      0

; @blob $060 code FL_RO
; Carry with readOnly when the drive of the FCB at DE (1 = A) is read-only
; (BDOS 29), carry clear otherwise. Preserves DE.
FL_RO:  LD      A,(DE)
        PUSH    DE
        PUSH    AF
        LD      C,29
        CALL    BDOS
        POP     AF
        POP     DE
        DEC     A
        JR      Z,.TEST
        LD      B,A
.SHIFT: SRL     H
        RR      L
        DJNZ    .SHIFT
.TEST:  LD      A,L
        AND     1               ; clears carry
        RET     Z
        LD      A,E_RO
        SCF
        RET

; @blob $061 code FL_FIND
; Search for the FCB at DE (BDOS 17). Returns A = FF if absent; otherwise
; carry with readOnly if the file has the read-only attribute.
FL_FIND:
        LD      C,17
        CALL    BDOS_DE
        CP      $FF
        RET     Z
        PUSH    AF
        ADD     A,A
        ADD     A,A
        ADD     A,A
        ADD     A,A
        ADD     A,A             ; the entry's offset, A * 32
        LD      E,A
        LD      D,0
        LD      HL,DMA_BUF+9
        ADD     HL,DE
        POP     AF
        BIT     7,(HL)
        JR      NZ,.RO
        OR      A
        RET
.RO:    LD      A,E_RO
        SCF
        RET

; @blob $062 code FL_BUSY
; Carry with fileBusy if a file named like the 12 bytes at HL (drive, name,
; type) is open.
FL_BUSY:
        LD      (FL_VAR+8),HL
        LD      HL,FILECNT
        LD      A,L
        OR      A
        RET     Z
        LD      B,A
        PUSH    IY
        LD      IY,FILES
.EACH:  LD      A,(IY+2)
        OR      A
        JR      Z,.NEXT
        PUSH    BC
        PUSH    IY
        POP     DE
        INC     DE
        INC     DE
        INC     DE
        INC     DE              ; DE = the entry's FCB
        LD      HL,(FL_VAR+8)
        LD      B,12
.CMP:   LD      A,(DE)
        AND     $7F
        CP      (HL)
        JR      NZ,.DIFF
        INC     DE
        INC     HL
        DJNZ    .CMP
        POP     BC
        POP     IY
        LD      A,E_BUSY
        SCF
        RET
.DIFF:  POP     BC
.NEXT:  LD      DE,ENTSZ
        ADD     IY,DE
        DJNZ    .EACH
        POP     IY
        OR      A
        RET

; @blob $063 code FL_TEMP
; Give the entry's FCB its temporary type: $ and the index in hex.
FL_TEMP:
        LD      (IY+13),'$'
        LD      A,(IY+51)
        RRCA
        RRCA
        RRCA
        RRCA
        CALL    .HEX
        LD      (IY+14),A
        LD      A,(IY+51)
        CALL    .HEX
        LD      (IY+15),A
        RET
.HEX:   AND     $0F
        ADD     A,$90
        DAA
        ADC     A,$40
        DAA
        RET

; @blob $064 code FL_RMTMP
; Close and delete an openWrite file's temporary.
FL_RMTMP:
        LD      C,16
        CALL    FL_IO
        LD      C,19
        JP      FL_IO

; @blob $065 code FL_REPL
; At close of an openWrite file: delete the target and rename the temporary
; to it (services §4.6). Carry with fileBusy or storageFailure.
FL_REPL:
        ; FL_FCB+36: the target's name, for the busy check and the delete
        PUSH    IY
        POP     HL
        INC     HL
        INC     HL
        INC     HL
        INC     HL
        LD      DE,FL_FCB+36
        LD      BC,12
        LDIR
        LD      A,(IY+48)
        LD      (FL_FCB+36+9),A
        LD      A,(IY+49)
        LD      (FL_FCB+36+10),A
        LD      A,(IY+50)
        LD      (FL_FCB+36+11),A
        LD      HL,FL_FCB+36
        CALL    FL_BUSY
        RET     C
        XOR     A
        LD      (FL_FCB+36+12),A
        LD      DE,FL_FCB+36
        LD      C,19
        CALL    BDOS_DE         ; delete the old file, if any
        ; FL_FCB: the temporary's name, then the target's at +16
        LD      HL,FL_FCB
        LD      B,36
.ZERO:  LD      (HL),0
        INC     HL
        DJNZ    .ZERO
        PUSH    IY
        POP     HL
        INC     HL
        INC     HL
        INC     HL
        INC     HL
        LD      DE,FL_FCB
        LD      BC,12
        LDIR
        LD      HL,FL_FCB+36
        LD      DE,FL_FCB+16
        LD      BC,12
        LDIR
        LD      DE,FL_FCB
        LD      C,23
        CALL    BDOS_DE
        INC     A
        JR      Z,.FAIL
        OR      A
        RET
.FAIL:  LD      A,E_STORE
        SCF
        RET

; @blob $066 code FL_CLOSE
; Close an entry: write what is held, close the FCB, replace the target of
; an openWrite file. The entry is always released (services §4.2).
FL_CLOSE:
        LD      A,(IY+2)
        CP      1
        JP      Z,.DONE
        BIT     7,(IY+41)
        LD      A,E_DFULL
        JR      NZ,.FAIL
        BIT     4,(IY+41)
        JR      Z,.NOCR
        RES     4,(IY+41)
        LD      A,13
        CALL    FL_PUTB
        JR      C,.FAIL
.NOCR:  CALL    FL_FLUSH
        JR      C,.FAIL
        LD      C,16
        CALL    FL_IO
        INC     A
        LD      A,E_STORE
        JR      Z,.FAIL
        LD      A,(IY+2)
        CP      2
        JR      NZ,.DONE
        CALL    FL_REPL
        JR      C,.FAIL
.DONE:  CALL    FL_FREE
        OR      A
        RET
.FAIL:  PUSH    AF
        LD      A,(IY+2)
        CP      2
        CALL    Z,FL_RMTMP
        CALL    FL_FREE
        POP     AF
        SCF
        RET

; @blob $067 code FL_ABORT
; Abort an entry: an openWrite file's temporary is deleted; any other file
; is closed without writing what is held.
FL_ABORT:
        LD      A,(IY+2)
        CP      2
        JR      NZ,.OTHER
        CALL    FL_RMTMP
        JP      FL_FREE
.OTHER: CP      1
        JP      Z,FL_FREE
        LD      C,16
        CALL    FL_IO
        JP      FL_FREE

; @blob $068 code FL_END
; At the end of the run (services §7): A = 0 after a normal return, nonzero
; after a failure or trap. Closes every file, or aborts openWrite files and
; closes the rest.
FL_END: LD      (FL_VAR+4),A
        LD      HL,FILECNT
        LD      A,L
        OR      A
        RET     Z
        LD      B,A
        LD      IY,FILES
.EACH:  PUSH    BC
        LD      A,(IY+2)
        OR      A
        JR      Z,.NEXT
        LD      A,(FL_VAR+4)
        OR      A
        JR      Z,.CLOSE
        LD      A,(IY+2)
        CP      2
        JR      NZ,.CLOSE
        CALL    FL_ABORT
        JR      .NEXT
.CLOSE: CALL    FL_CLOSE
.NEXT:  LD      DE,ENTSZ
        ADD     IY,DE
        POP     BC
        DJNZ    .EACH
        RET

; @blob $069 code FL_OPEN
; The common start of the open services: IY = a free entry with the name
; at HL parsed into its FCB. Carry with tooManyFiles or badName.
FL_OPEN:
        PUSH    HL
        CALL    FL_ALLOC
        POP     HL
        RET     C
        XOR     A
        LD      (FL_VAR+5),A
        PUSH    IY
        POP     DE
        INC     DE
        INC     DE
        INC     DE
        INC     DE
        JP      FL_PARSE

; @blob $06A code FL_WRCHK
; For the services that write or delete: carry with readOnly if the FCB at
; DE is on a read-only drive or is a read-only file. Returns A = FF if the
; file does not exist.
FL_WRCHK:
        CALL    FL_RO
        RET     C
        JP      FL_FIND

; @blob $06B code FL_MODE
; Carry with badMode unless A is textMode or binaryMode.
FL_MODE:
        CP      2
        CCF
        RET     NC
        LD      A,E_MODE
        RET

; @blob $06C code FL_DNAME
; Copy the directory entry A of the DMA buffer, as NAME.TYP, into the
; string at HL, clearing the rest of it. B = its capacity.
FL_DNAME:
        PUSH    HL
        PUSH    AF
        LD      C,B
        INC     HL
.CLR:   LD      (HL),0
        INC     HL
        DJNZ    .CLR
        POP     AF
        ADD     A,A
        ADD     A,A
        ADD     A,A
        ADD     A,A
        ADD     A,A
        LD      E,A
        LD      D,0
        LD      HL,DMA_BUF+1
        ADD     HL,DE           ; HL = the entry's name
        POP     DE              ; DE = the string
        PUSH    DE
        INC     DE
        LD      C,0             ; C = the length
        LD      B,8
.NAME:  LD      A,(HL)
        AND     $7F
        CP      ' '
        JR      Z,.SKIPN
        LD      (DE),A
        INC     DE
        INC     C
.SKIPN: INC     HL
        DJNZ    .NAME
        LD      A,(HL)
        AND     $7F
        CP      ' '
        JR      Z,.DONE
        LD      A,'.'
        LD      (DE),A
        INC     DE
        INC     C
        LD      B,3
.TYPE:  LD      A,(HL)
        AND     $7F
        CP      ' '
        JR      Z,.SKIPT
        LD      (DE),A
        INC     DE
        INC     C
.SKIPT: INC     HL
        DJNZ    .TYPE
.DONE:  POP     HL
        LD      (HL),C
        RET

; ---- the services ---------------------------------------------------------

; @blob $020 code WR_TEXT helper=1
; writeText(f as File, text as string[]) fails.
; IX+4 text, IX+6 its capacity, IX+8 f, IX+10 its generation.
WR_TEXT:
        PUSH    IX
        LD      IX,0
        ADD     IX,SP
        LD      L,(IX+8)
        LD      H,(IX+9)
        LD      E,(IX+10)
        LD      D,(IX+11)
        CALL    FL_FILE
        JR      C,.DONE
        LD      (FL_VAR+1),A
        LD      L,(IX+4)
        LD      H,(IX+5)
        LD      B,(HL)
        INC     HL
.NEXT:  LD      A,B
        OR      A
        JR      Z,.DONE
        LD      A,(HL)
        PUSH    HL
        PUSH    BC
        CALL    OUT_ANY
        POP     BC
        POP     HL
        JR      C,.DONE
        INC     HL
        DEC     B
        JR      .NEXT
.DONE:  LD      IY,8
        JP      RETN

; @blob $021 code WR_BYTE helper=1
; writeByte(f as File, b as u8) fails. IX+4 b, IX+6 f, IX+8 its generation.
WR_BYTE:
        PUSH    IX
        LD      IX,0
        ADD     IX,SP
        LD      L,(IX+6)
        LD      H,(IX+7)
        LD      E,(IX+8)
        LD      D,(IX+9)
        CALL    FL_FILE
        JR      C,.DONE
        LD      (FL_VAR+1),A
        LD      A,(IX+4)
        CALL    OUT_ANY
.DONE:  LD      IY,6
        JP      RETN

; @blob $022 code WR_OUT helper=1
; writeOutputByte(b as u8) fails: writeByte(console, b).
WR_OUT: PUSH    IX
        LD      IX,0
        ADD     IX,SP
        LD      A,(IX+4)
        CALL    CON_OUT
        OR      A
        LD      IY,2
        JP      RETN

; @blob $06D code RD_BYTE helper=1
; readByte(f as File) as u8 fails. IX+4 f, IX+6 its generation.
RD_BYTE:
        PUSH    IX
        LD      IX,0
        ADD     IX,SP
        LD      L,(IX+4)
        LD      H,(IX+5)
        LD      E,(IX+6)
        LD      D,(IX+7)
        CALL    FL_FILE
        JR      C,.DONE
        CP      3
        JR      Z,.FILE
        CP      1
        LD      A,E_NOTAV
        SCF
        JR      NZ,.DONE
        CALL    CON_GET
        JR      .DONE
.FILE:  CALL    FL_RD
.DONE:  LD      IY,4
        JP      RETN

; @blob $06E code RD_IN helper=1
; readInputByte() as u8 fails: readByte(console).
RD_IN:  JP      CON_GET

; @blob $06F code RD_KEY helper=1
; readKey() as u8: wait for one key, without echo.
RD_KEY: JP      CON_KEY

; @blob $070 code KEY_RDY helper=1
; keyReady() as boolean: whether a key is waiting; it is held for the next
; read.
KEY_RDY:
        LD      A,(CON_VAR)
        OR      A
        JR      NZ,.YES
        LD      C,6
        LD      E,$FF
        CALL    BDOS
        OR      A
        RET     Z
        LD      (CON_VAR+1),A
        LD      A,1
        LD      (CON_VAR),A
        RET
.YES:   LD      A,1
        RET

; @blob $071 code RD_LINE helper=1
; readLine(f as File, var line as string[]) fails.
; IX+4 line, IX+6 its capacity, IX+8 f, IX+10 its generation.
RD_LINE:
        PUSH    IX
        LD      IX,0
        ADD     IX,SP
        LD      L,(IX+4)        ; clear the line
        LD      H,(IX+5)
        LD      B,(IX+6)
        LD      (HL),0
        INC     HL
        LD      A,B
        OR      A
        JR      Z,.CLEAR
.CLR:   LD      (HL),0
        INC     HL
        DJNZ    .CLR
.CLEAR: LD      L,(IX+8)
        LD      H,(IX+9)
        LD      E,(IX+10)
        LD      D,(IX+11)
        CALL    FL_FILE
        JP      C,.DONE
        CP      3
        JP      Z,.FILE
        CP      1
        LD      A,E_NOTAV
        SCF
        JP      NZ,.DONE
        ; the console: BDOS 10 with CP/M's line editing (services §3.3)
        LD      A,(CON_VAR+2)
        OR      A
        JP      NZ,.EOF
        LD      A,(IX+6)
        CP      254
        JR      C,.MAX
        LD      A,253
.MAX:   LD      (CON_BUF),A
        LD      DE,CON_BUF
        LD      C,10
        CALL    BDOS
        LD      A,(CON_BUF+1)
        OR      A
        JR      Z,.COPY
        LD      A,(CON_BUF+2)
        CP      CTRLZ
        JR      NZ,.COPY
        LD      (CON_VAR+2),A
        JP      .EOF
.COPY:  LD      A,(CON_BUF+1)
        LD      L,(IX+4)
        LD      H,(IX+5)
        LD      (HL),A
        OR      A
        JP      Z,.OK
        LD      C,A
        LD      B,0
        INC     HL
        EX      DE,HL
        LD      HL,CON_BUF+2
        LDIR
        JP      .OK
.FILE:  LD      A,(IY+3)
        OR      A
        LD      A,E_MODE
        SCF
        JP      NZ,.DONE        ; a text-mode operation
        XOR     A
        LD      (FL_VAR+2),A    ; count
        LD      (FL_VAR+4),A    ; bit 0 something read, bit 1 too long
.NEXT:  CALL    FL_RD
        JR      C,.END
        LD      C,A
        LD      A,(FL_VAR+4)
        OR      1
        LD      (FL_VAR+4),A
        LD      A,C
        CP      10
        JR      Z,.LINE
        LD      A,(FL_VAR+2)
        CP      (IX+6)
        JR      C,.ROOM
        LD      A,(FL_VAR+4)
        OR      2
        LD      (FL_VAR+4),A
        JR      .NEXT
.ROOM:  LD      E,A
        INC     A
        LD      (FL_VAR+2),A
        LD      L,(IX+4)
        LD      H,(IX+5)
        LD      (HL),A
        LD      D,0
        INC     HL
        ADD     HL,DE
        LD      (HL),C
        JR      .NEXT
.END:   CP      E_EOF
        SCF
        JR      NZ,.DONE
        LD      A,(FL_VAR+4)
        BIT     0,A
        JR      Z,.EOF
.LINE:  LD      A,(FL_VAR+4)
        BIT     1,A
        JR      Z,.OK
        LD      A,E_LONG
        SCF
        JR      .DONE
.OK:    OR      A
        JR      .DONE
.EOF:   LD      A,E_EOF
        SCF
.DONE:  LD      IY,8
        JP      RETN

; @blob $072 code OP_READ helper=1
; openRead(name as string[], mode as u8) as File fails.
; IX+4 mode, IX+6 name, IX+8 its capacity.
OP_READ:
        PUSH    IX
        LD      IX,0
        ADD     IX,SP
        LD      A,(IX+4)
        CALL    FL_MODE
        JR      C,.DONE
        LD      L,(IX+6)
        LD      H,(IX+7)
        CALL    FL_OPEN
        JR      C,.DONE
        LD      C,15
        CALL    FL_IO
        INC     A
        LD      A,E_NOTFN
        SCF
        JR      Z,.DONE
        CALL    FL_SIZE
        LD      A,(IX+4)
        LD      (IY+3),A
        LD      (IY+2),1
        CALL    FL_RES
.DONE:  LD      IY,6
        JP      RETN

; @blob $073 code OP_WRITE helper=1
; openWrite(name as string[], mode as u8) as File fails: a temporary that
; replaces the file at close (services §4.6).
OP_WRITE:
        PUSH    IX
        LD      IX,0
        ADD     IX,SP
        LD      A,(IX+4)
        CALL    FL_MODE
        JR      C,.DONE
        LD      L,(IX+6)
        LD      H,(IX+7)
        CALL    FL_OPEN
        JR      C,.DONE
        PUSH    IY
        POP     DE
        INC     DE
        INC     DE
        INC     DE
        INC     DE
        CALL    FL_WRCHK
        JR      C,.DONE
        LD      A,(IY+13)
        LD      (IY+48),A
        LD      A,(IY+14)
        LD      (IY+49),A
        LD      A,(IY+15)
        LD      (IY+50),A
        CALL    FL_TEMP
        LD      C,19
        CALL    FL_IO           ; a temporary left by an interrupted run
        LD      C,22
        CALL    FL_IO
        INC     A
        LD      A,E_DIRFL
        SCF
        JR      Z,.DONE
        LD      A,(IX+4)
        LD      (IY+3),A
        LD      (IY+2),2
        CALL    FL_RES
.DONE:  LD      IY,6
        JP      RETN

; @blob $074 code OP_APPND helper=1
; openAppend(name as string[], mode as u8) as File fails: positioned at
; the end; in text mode, at the first Control-Z of the last record.
OP_APPND:
        PUSH    IX
        LD      IX,0
        ADD     IX,SP
        LD      A,(IX+4)
        CALL    FL_MODE
        JP      C,.DONE
        LD      L,(IX+6)
        LD      H,(IX+7)
        CALL    FL_OPEN
        JP      C,.DONE
        PUSH    IY
        POP     DE
        INC     DE
        INC     DE
        INC     DE
        INC     DE
        CALL    FL_WRCHK
        JP      C,.DONE
        LD      C,15
        CALL    FL_IO
        INC     A
        JR      NZ,.OPENED
        LD      C,22
        CALL    FL_IO
        INC     A
        LD      A,E_DIRFL
        SCF
        JP      Z,.DONE
.OPENED:
        CALL    FL_SIZE
        LD      A,(IX+4)
        LD      (IY+3),A
        LD      (IY+2),3
        LD      A,(IY+45)       ; the end: record = high-water mark
        LD      (IY+42),A
        LD      A,(IY+46)
        LD      (IY+43),A
        LD      A,(IY+47)
        LD      (IY+44),A
        LD      A,(IY+3)
        OR      A
        JR      NZ,.RESULT      ; binary: at the end
        LD      A,(IY+45)
        OR      (IY+46)
        OR      (IY+47)
        JR      Z,.RESULT       ; an empty file
        ; text: back one record, and find its Control-Z
        LD      A,(IY+42)
        SUB     1
        LD      (IY+42),A
        LD      A,(IY+43)
        SBC     A,0
        LD      (IY+43),A
        LD      A,(IY+44)
        SBC     A,0
        LD      (IY+44),A
        CALL    FL_FILL
        JR      C,.RESULT
        PUSH    IY
        POP     HL
        LD      DE,EBUF
        ADD     HL,DE
        LD      B,0
.SCAN:  LD      A,(HL)
        CP      CTRLZ
        JR      Z,.FOUND
        INC     HL
        INC     B
        LD      A,B
        CP      128
        JR      NZ,.SCAN
        CALL    FL_NEXT         ; no Control-Z: start a new record
        JR      .RESULT
.FOUND: LD      (IY+40),B
.RESULT:
        CALL    FL_RES
.DONE:  LD      IY,6
        JP      RETN

; @blob $075 code OP_UPDT helper=1
; openUpdate(name as string[]) as File fails: an existing file, binary,
; read and written anywhere. IX+4 name, IX+6 its capacity.
OP_UPDT:
        PUSH    IX
        LD      IX,0
        ADD     IX,SP
        LD      L,(IX+4)
        LD      H,(IX+5)
        CALL    FL_OPEN
        JR      C,.DONE
        PUSH    IY
        POP     DE
        INC     DE
        INC     DE
        INC     DE
        INC     DE
        CALL    FL_WRCHK
        JR      C,.DONE
        LD      C,15
        CALL    FL_IO
        INC     A
        LD      A,E_NOTFN
        SCF
        JR      Z,.DONE
        CALL    FL_SIZE
        LD      (IY+3),1
        LD      (IY+2),4
        CALL    FL_RES
.DONE:  LD      IY,4
        JP      RETN

; @blob $076 code FS_CLOSE helper=1
; close(f as File) fails. IX+4 f, IX+6 its generation.
FS_CLOSE:
        PUSH    IX
        LD      IX,0
        ADD     IX,SP
        LD      L,(IX+4)
        LD      H,(IX+5)
        LD      E,(IX+6)
        LD      D,(IX+7)
        CALL    FL_FILE
        JR      C,.DONE
        CP      3
        LD      A,E_NOTAV
        SCF
        JR      NZ,.DONE
        CALL    FL_CLOSE
.DONE:  LD      IY,4
        JP      RETN

; @blob $077 code FS_ABORT helper=1
; abort(f as File).
FS_ABORT:
        PUSH    IX
        LD      IX,0
        ADD     IX,SP
        LD      L,(IX+4)
        LD      H,(IX+5)
        LD      E,(IX+6)
        LD      D,(IX+7)
        CALL    FL_FILE
        JR      C,.DONE
        CP      3
        CALL    Z,FL_ABORT
.DONE:  LD      IY,4
        JP      RETN

; @blob $078 code FS_FLUSH helper=1
; flush(f as File) fails: write what is held and the directory entry.
FS_FLUSH:
        PUSH    IX
        LD      IX,0
        ADD     IX,SP
        LD      L,(IX+4)
        LD      H,(IX+5)
        LD      E,(IX+6)
        LD      D,(IX+7)
        CALL    FL_FILE
        JR      C,.DONE
        CP      3
        JR      NZ,.OK
        LD      A,(IY+2)
        CP      1
        JR      Z,.OK
        CALL    FL_FLUSH
        JR      C,.DONE
        LD      C,16
        CALL    FL_IO
.OK:    OR      A
.DONE:  LD      IY,4
        JP      RETN

; @blob $079 code RD_BLOCK helper=1
; readBlock(f as File, var buf as u8[], count as u16) as u16 fails: up to
; count bytes, never more than buf.length; 0 only at the end.
; IX+4 count, IX+6 buf, IX+8 its length, IX+10 f, IX+12 its generation.
RD_BLOCK:
        PUSH    IX
        LD      IX,0
        ADD     IX,SP
        LD      L,(IX+10)
        LD      H,(IX+11)
        LD      E,(IX+12)
        LD      D,(IX+13)
        CALL    FL_FILE
        JR      C,.DONE
        CP      3
        LD      A,E_NOTAV
        SCF
        JR      NZ,.DONE
        LD      A,(IY+3)
        OR      A
        LD      A,E_MODE
        SCF
        JR      Z,.DONE         ; a binary operation
        LD      HL,0            ; HL = bytes read
.NEXT:  LD      A,L             ; stop at count or the length
        CP      (IX+4)
        JR      NZ,.MORE
        LD      A,H
        CP      (IX+5)
        JR      Z,.OK
.MORE:  LD      A,L
        CP      (IX+8)
        JR      NZ,.READ
        LD      A,H
        CP      (IX+9)
        JR      Z,.OK
.READ:  PUSH    HL
        CALL    FL_RD
        POP     HL
        JR      C,.END
        LD      E,(IX+6)
        LD      D,(IX+7)
        EX      DE,HL
        ADD     HL,DE
        LD      (HL),A
        EX      DE,HL
        INC     HL
        JR      .NEXT
.END:   LD      C,A
        LD      A,H
        OR      L
        JR      NZ,.OK          ; report the error on the next call
        LD      A,C
        CP      E_EOF
        JR      Z,.OK           ; 0: the end
        SCF
        JR      .DONE
.OK:    OR      A
.DONE:  LD      IY,10
        JP      RETN

; @blob $07A code WR_BLOCK helper=1
; writeBlock(f as File, buf as u8[], count as u16) fails. A count above
; buf.length traps with bounds before anything is written.
; IX+4 count, IX+6 buf, IX+8 its length, IX+10 f, IX+12 its generation.
WR_BLOCK:
        PUSH    IX
        LD      IX,0
        ADD     IX,SP
        LD      L,(IX+8)
        LD      H,(IX+9)
        LD      E,(IX+4)
        LD      D,(IX+5)
        OR      A
        SBC     HL,DE
        JR      NC,.FITS
        LD      SP,IX           ; trap with the program's call on top
        POP     IX
        JP      TRAP_BND
.FITS:  LD      L,(IX+10)
        LD      H,(IX+11)
        LD      E,(IX+12)
        LD      D,(IX+13)
        CALL    FL_FILE
        JR      C,.DONE
        CP      3
        LD      A,E_NOTAV
        SCF
        JR      NZ,.DONE
        LD      A,(IY+3)
        OR      A
        LD      A,E_MODE
        SCF
        JR      Z,.DONE
        LD      HL,0
.NEXT:  LD      A,L
        CP      (IX+4)
        JR      NZ,.WRITE
        LD      A,H
        CP      (IX+5)
        JR      Z,.OK
.WRITE: PUSH    HL
        LD      E,(IX+6)
        LD      D,(IX+7)
        ADD     HL,DE
        LD      A,(HL)
        CALL    FL_WR
        POP     HL
        JR      C,.DONE
        INC     HL
        JR      .NEXT
.OK:    OR      A
.DONE:  LD      IY,10
        JP      RETN

; @blob $07B code FS_SEEK helper=1
; seek(f as File, position as u32) fails: binary read, append and update
; files. IX+4 position (low word), IX+6 (high word), IX+8 f, IX+10 its
; generation.
FS_SEEK:
        PUSH    IX
        LD      IX,0
        ADD     IX,SP
        LD      L,(IX+8)
        LD      H,(IX+9)
        LD      E,(IX+10)
        LD      D,(IX+11)
        CALL    FL_FILE
        JP      C,.DONE
        CP      3
        LD      A,E_NOTAV
        SCF
        JP      NZ,.DONE
        LD      A,(IY+2)
        CP      2
        LD      A,E_MODE
        SCF
        JP      Z,.DONE         ; not openWrite files
        LD      A,(IY+2)
        CP      1
        JR      NZ,.KIND
        LD      A,(IY+3)
        OR      A
        LD      A,E_MODE
        SCF
        JP      Z,.DONE         ; not text read files
.KIND:  LD      A,(IX+7)        ; below 8,388,608
        OR      A
        JR      NZ,.FAIL
        BIT     7,(IX+6)
        JR      NZ,.FAIL
        LD      A,(IY+2)
        CP      4
        JR      Z,.MOVE         ; update: anywhere below the limit
        ; read and append: no further than the size, HIW * 128
        LD      L,(IY+45)
        LD      H,(IY+46)
        LD      A,(IY+47)
        LD      B,7
.SHIFT: ADD     HL,HL
        RLA
        DJNZ    .SHIFT          ; A:H:L = the size's bits 8 to 31 and 0 to 15
        LD      C,A             ; size = C:H:L as bits 16-23 : 8-15 : 0-7
        LD      A,(IX+6)
        CP      C
        JR      C,.MOVE
        JR      NZ,.FAIL
        LD      A,(IX+5)
        CP      H
        JR      C,.MOVE
        JR      NZ,.FAIL
        LD      A,(IX+4)
        CP      L
        JR      C,.MOVE
        JR      Z,.MOVE
.FAIL:  LD      A,E_SEEK
        SCF
        JR      .DONE
.MOVE:  CALL    FL_FLUSH
        JR      C,.DONE
        LD      A,(IX+4)        ; the record: position >> 7
        RLA
        LD      A,(IX+5)
        RLA
        LD      (IY+42),A
        LD      A,(IX+6)
        RLA
        LD      (IY+43),A
        LD      (IY+44),0
        LD      A,(IX+4)
        AND     $7F
        LD      (IY+40),A
        LD      A,(IY+41)
        AND     $E1             ; clear loaded, end of text, CR flags
        LD      (IY+41),A
        OR      A
.DONE:  LD      IY,8
        JP      RETN

; @blob $07C code FS_POS helper=1
; position(f as File) as u32 fails: the record times 128 plus the position.
FS_POS: PUSH    IX
        LD      IX,0
        ADD     IX,SP
        LD      L,(IX+4)
        LD      H,(IX+5)
        LD      E,(IX+6)
        LD      D,(IX+7)
        CALL    FL_FILE
        JR      C,.DONE
        CP      3
        LD      A,E_NOTAV
        SCF
        JR      NZ,.DONE
        LD      L,(IY+42)
        LD      H,(IY+43)
        LD      E,(IY+44)
        LD      D,0
        LD      B,7
.SHIFT: ADD     HL,HL
        RL      E
        RL      D
        DJNZ    .SHIFT
        LD      C,(IY+40)
        LD      B,0
        ADD     HL,BC
        JR      NC,.OK
        INC     DE
.OK:    OR      A
.DONE:  LD      IY,4
        JP      RETN

; @blob $07D code FS_SIZE helper=1
; size(f as File) as u32 fails: the high-water mark times 128.
FS_SIZE:
        PUSH    IX
        LD      IX,0
        ADD     IX,SP
        LD      L,(IX+4)
        LD      H,(IX+5)
        LD      E,(IX+6)
        LD      D,(IX+7)
        CALL    FL_FILE
        JR      C,.DONE
        CP      3
        LD      A,E_NOTAV
        SCF
        JR      NZ,.DONE
        BIT     0,(IY+41)       ; held bytes count towards the size
        JR      Z,.SIZE
        CALL    FL_FLUSH
        JR      C,.DONE
.SIZE:
        LD      L,(IY+45)
        LD      H,(IY+46)
        LD      E,(IY+47)
        LD      D,0
        LD      B,7
.SHIFT: ADD     HL,HL
        RL      E
        RL      D
        DJNZ    .SHIFT
        OR      A
.DONE:  LD      IY,4
        JP      RETN

; @blob $07E code FS_EXIST helper=1
; exists(name as string[]) as boolean fails. IX+4 name, IX+6 its capacity.
FS_EXIST:
        PUSH    IX
        LD      IX,0
        ADD     IX,SP
        XOR     A
        LD      (FL_VAR+5),A
        LD      L,(IX+4)
        LD      H,(IX+5)
        LD      DE,FL_FCB
        CALL    FL_PARSE
        JR      C,.DONE
        LD      DE,FL_FCB
        LD      C,17
        CALL    BDOS_DE
        INC     A
        JR      Z,.DONE         ; A = 0: false, carry clear
        LD      A,1
        OR      A
.DONE:  LD      IY,4
        JP      RETN

; @blob $07F code FS_DEL helper=1
; delete(name as string[]) fails.
FS_DEL:
        PUSH    IX
        LD      IX,0
        ADD     IX,SP
        XOR     A
        LD      (FL_VAR+5),A
        LD      L,(IX+4)
        LD      H,(IX+5)
        LD      DE,FL_FCB
        CALL    FL_PARSE
        JR      C,.DONE
        LD      HL,FL_FCB
        CALL    FL_BUSY
        JR      C,.DONE
        LD      DE,FL_FCB
        CALL    FL_WRCHK
        JR      C,.DONE
        CP      $FF
        LD      A,E_NOTFN
        SCF
        JR      Z,.DONE
        LD      DE,FL_FCB
        LD      C,19
        CALL    BDOS_DE
        OR      A
.DONE:  LD      IY,4
        JP      RETN

; @blob $080 code FS_REN helper=1
; rename(oldName as string[], newName as string[]) fails: within a drive.
; IX+4 newName, IX+6 its capacity, IX+8 oldName, IX+10 its capacity.
FS_REN:
        PUSH    IX
        LD      IX,0
        ADD     IX,SP
        XOR     A
        LD      (FL_VAR+5),A
        LD      L,(IX+4)
        LD      H,(IX+5)
        LD      DE,FL_FCB+36
        CALL    FL_PARSE
        JP      C,.DONE
        LD      L,(IX+8)
        LD      H,(IX+9)
        LD      DE,FL_FCB
        CALL    FL_PARSE
        JP      C,.DONE
        LD      A,(FL_FCB)
        LD      HL,FL_FCB+36
        CP      (HL)
        LD      A,E_NAME
        SCF
        JP      NZ,.DONE        ; a different drive
        LD      HL,FL_FCB
        CALL    FL_BUSY
        JR      C,.DONE
        LD      DE,FL_FCB+36    ; the new name must be free
        LD      C,17
        CALL    BDOS_DE
        INC     A
        LD      A,E_EXIST
        SCF
        JR      NZ,.DONE
        LD      DE,FL_FCB
        CALL    FL_WRCHK
        JR      C,.DONE
        CP      $FF
        LD      A,E_NOTFN
        SCF
        JR      Z,.DONE
        LD      HL,FL_FCB+36
        LD      DE,FL_FCB+16
        LD      BC,12
        LDIR
        LD      DE,FL_FCB
        LD      C,23
        CALL    BDOS_DE
        OR      A
.DONE:  LD      IY,8
        JP      RETN

; @blob $081 code FS_FIND1 helper=1
; findFirst(pattern as string[], var name as string[]) as boolean fails.
; IX+4 name, IX+6 its capacity, IX+8 pattern, IX+10 its capacity.
FS_FIND1:
        PUSH    IX
        LD      IX,0
        ADD     IX,SP
        LD      A,(IX+6)
        CP      14
        LD      A,E_LONG
        JR      C,.DONE
        LD      A,1
        LD      (FL_VAR+5),A
        LD      L,(IX+8)
        LD      H,(IX+9)
        LD      DE,FL_FCB
        CALL    FL_PARSE
        JR      C,.DONE
        LD      DE,FL_FCB
        LD      C,17
        CALL    BDOS_DE
        CALL    FL_FOUND
.DONE:  LD      IY,8
        JP      RETN

; @blob $082 code FS_FINDN helper=1
; findNext(var name as string[]) as boolean fails. IX+4 name, IX+6 its
; capacity.
FS_FINDN:
        PUSH    IX
        LD      IX,0
        ADD     IX,SP
        LD      A,(FL_VAR)
        OR      A
        LD      A,E_NOSRC
        SCF
        JR      Z,.DONE
        LD      A,(IX+6)
        CP      14
        LD      A,E_LONG
        JR      C,.DONE
        LD      DE,FL_FCB
        LD      C,18
        CALL    BDOS_DE
        CALL    FL_FOUND
.DONE:  LD      IY,4
        JP      RETN

; @blob $083 code FL_FOUND
; For findFirst and findNext, in their frame (IX+4 the name, IX+6 its
; capacity): A = the BDOS result. Copies the name and returns A = 1 (true),
; or ends the search and returns A = 0. Carry clear.
FL_FOUND:
        CP      $FF
        JR      NZ,.NAME
        XOR     A
        LD      (FL_VAR),A
        RET
.NAME:  LD      L,(IX+4)
        LD      H,(IX+5)
        LD      B,(IX+6)
        CALL    FL_DNAME
        LD      A,1
        LD      (FL_VAR),A
        OR      A
        RET

; @blob $084 code CMD_TAIL helper=1
; commandTail(var text as string[]): the command tail as typed, without its
; leading separator, truncated to the capacity. IX+4 text, IX+6 capacity.
CMD_TAIL:
        PUSH    IX
        LD      IX,0
        ADD     IX,SP
        LD      L,(IX+4)
        LD      H,(IX+5)
        LD      B,(IX+6)
        PUSH    HL
        LD      (HL),0
        INC     HL
.CLR:   LD      (HL),0
        INC     HL
        DJNZ    .CLR
        LD      HL,$0080
        LD      C,(HL)          ; C = the tail's length
        INC     HL
        LD      A,C
        OR      A
        JR      Z,.SET
        LD      A,(HL)
        CP      ' '
        JR      NZ,.SET
        INC     HL
        DEC     C
.SET:   LD      A,C
        CP      (IX+6)
        JR      C,.FITS
        LD      C,(IX+6)
.FITS:  POP     DE
        LD      A,C
        LD      (DE),A
        INC     DE
        OR      A
        JR      Z,.DONE
        LD      B,0
        LDIR
.DONE:  LD      IY,4
        JP      RETN

; @blob $085 code M_RESET helper=1
; resetDisks(): BDOS 13, which also moves the DMA; it is moved back.
M_RESET:
        LD      C,13
        CALL    BDOS_DE
        LD      DE,DMA_BUF
        LD      C,26
        JP      BDOS

; @blob $086 code M_RESETD helper=1
; resetDrive(drive as u8): BDOS 37. IX+4 drive.
M_RESETD:
        PUSH    IX
        LD      IX,0
        ADD     IX,SP
        LD      B,(IX+4)
        LD      HL,1
        INC     B
        JR      .TEST
.SHIFT: ADD     HL,HL
.TEST:  DJNZ    .SHIFT
        EX      DE,HL
        LD      C,37
        CALL    BDOS_DE
        LD      IY,2
        JP      RETN

; @blob $087 code M_DRIVE helper=1
; currentDrive() as u8: BDOS 25.
M_DRIVE:
        LD      C,25
        JP      BDOS

; @blob $088 code M_SELECT helper=1
; selectDrive(drive as u8) fails: drives 0 to 15 (BDOS 14).
M_SELECT:
        PUSH    IX
        LD      IX,0
        ADD     IX,SP
        LD      A,(IX+4)
        CP      16
        LD      A,E_NOTAV
        CCF
        JR      C,.DONE
        LD      E,(IX+4)
        LD      C,14
        CALL    BDOS_DE
        OR      A
.DONE:  LD      IY,2
        JP      RETN

; @blob $089 code M_USER helper=1
; currentUser() as u8: BDOS 32.
M_USER: LD      E,$FF
        LD      C,32
        JP      BDOS

; @blob $08A code M_SETU helper=1
; setUser(user as u8) fails: users 0 to 15.
M_SETU: PUSH    IX
        LD      IX,0
        ADD     IX,SP
        LD      A,(IX+4)
        CP      16
        LD      A,E_INVAL
        CCF
        JR      C,.DONE
        LD      E,(IX+4)
        LD      C,32
        CALL    BDOS
        OR      A
.DONE:  LD      IY,2
        JP      RETN

; @blob $08B code M_RODRV helper=1
; driveReadOnly(drive as u8) as boolean: BDOS 29.
M_RODRV:
        PUSH    IX
        LD      IX,0
        ADD     IX,SP
        LD      C,29
        CALL    BDOS
        LD      B,(IX+4)
        INC     B
        JR      .TEST
.SHIFT: SRL     H
        RR      L
.TEST:  DJNZ    .SHIFT
        LD      A,L
        AND     1
        LD      IY,2
        JP      RETN

; @blob $08C code M_FREE helper=1
; freeMemory() as u16: the bytes between FREE and the stack.
M_FREE: LD      HL,0
        ADD     HL,SP
        LD      DE,FREE
        OR      A
        SBC     HL,DE
        RET
