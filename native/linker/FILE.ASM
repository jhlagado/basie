; Buffered files over CP/M's random-record calls.
;
; A file descriptor (FD) is an FCB followed by a record buffer. Every read and
; write uses the random calls (BDOS 33 and 34) with the FD's own record
; number, so seeking and sequential access mix freely: after a random read,
; CP/M's sequential read would read the same record again.
;
; Routines take the FD in IX and preserve it.

FD_FCB  EQU     0               ; the FCB (36 bytes)
FD_REC  EQU     33              ; its random-record field: the record buffered
FD_POS  EQU     36              ; next byte in the buffer, 0 to 128; 129 when
                                ; just opened, record 0 not yet read
FD_FLAGS  EQU     37            ; bit 0 writing
FD_PAD  EQU     38              ; the byte that pads a written file's last record
FD_BUF  EQU     39              ; the record (128 bytes)
FD_SIZE  EQU     167

; Set up the FD's FCB: A = drive (0 the current one, 1 A:), HL = the 8-byte
; name, DE = the 3-byte type, both space-padded. Every other field is zero.
FIL_INIT: PUSH    HL
        PUSH    IX
        POP     HL
        LD      B,FD_BUF
.ZERO:  LD      (HL),0
        INC     HL
        DJNZ    .ZERO
        LD      (IX+FD_FCB),A
        PUSH    IX
        POP     HL
        INC     HL              ; HL = the FCB's name
        EX      (SP),HL         ; HL = the name; the FCB's on the stack
        EX      DE,HL           ; DE = the name, HL = the type
        EX      (SP),HL         ; HL = the FCB's name; the type's on the stack
        EX      DE,HL           ; DE = the FCB's name, HL = the name
        LD      BC,8
        LDIR
        POP     HL              ; the type
        LD      BC,3
        LDIR
        LD      (IX+FD_POS),128
        RET

; Open an existing file, set up by FIL_INIT, for reading. Carry if it doesn't
; exist.
FIL_OPEN: LD      C,15
        CALL    FIL_CHK
        RET     C
        LD      (IX+FD_POS),129 ; the first read reads record 0
        RET

; Read record FD_REC into the buffer. Carry past the end of the file.
FIL_READ: LD      C,33
; Read or write (BDOS C) record FD_REC through the buffer. Carry on failure.
FIL_XFER:   PUSH    BC
        PUSH    IX              ; the DMA: the buffer
        POP     HL
        LD      DE,FD_BUF
        ADD     HL,DE
        EX      DE,HL
        LD      C,26
        CALL    CPM_CALL
        POP     BC
        CALL    FIL_BDOS
        CP      1               ; carry when 0
        CCF
        RET

; FD_REC += 1.
FIL_NEXT: INC     (IX+FD_REC)
        RET     NZ
        INC     (IX+FD_REC+1)
        RET     NZ
        INC     (IX+FD_REC+2)
        RET

; A = the next byte. Carry at the end of the file. Preserves BC, DE, HL.
FIL_GETB: PUSH    BC
        PUSH    DE
        PUSH    HL
        CALL    .GET
        POP     HL
        POP     DE
        POP     BC
        RET
.GET:   LD      A,(IX+FD_POS)
        CP      128
        JR      C,.HAVE
        CALL    Z,FIL_NEXT      ; 129: just opened, record 0
        CALL    FIL_READ
        RET     C
        LD      (IX+FD_POS),0
.HAVE:  CALL    FIL_PTR
        LD      A,(HL)
        OR      A               ; clears carry, keeps A
        RET

; HL = the buffer's next byte, and FD_POS moves past it.
FIL_PTR:  LD      E,(IX+FD_POS)
        LD      D,0
        PUSH    IX
        POP     HL
        ADD     HL,DE
        LD      DE,FD_BUF
        ADD     HL,DE
        INC     (IX+FD_POS)
        RET

; HL = the next two bytes, low first. Carry at the end of the file.
FIL_GETW: CALL    FIL_GETB
        RET     C
        LD      L,A
        CALL    FIL_GETB
        LD      H,A
        RET

; Go to byte offset A:HL (A the high byte) for reading. Carry if that is past
; the end of the file.
FIL_SEEK: PUSH    HL
        LD      B,A             ; record = offset >> 7, as B:H:L shifted
        ADD     HL,HL
        RL      B
        LD      A,0
        RLA                     ; the bit shifted out of B
        LD      (IX+FD_REC+2),A
        LD      (IX+FD_REC),H
        LD      (IX+FD_REC+1),B
        CALL    FIL_READ
        POP     HL
        RET     C
        LD      A,L
        AND     $7F             ; clears carry
        LD      (IX+FD_POS),A
        RET

; Create a file, set up by FIL_INIT, for writing, replacing any of the same
; name (toolchain §3.2). A = the byte that pads the last record. Carry if the
; directory is full.
FIL_MAKE: LD      (IX+FD_PAD),A
        CALL    FIL_DEL
        LD      C,22
        CALL    FIL_CHK
        RET     C
        LD      (IX+FD_POS),0
        LD      (IX+FD_FLAGS),1
        RET

; Write A. Carry if the disk is full. Preserves BC, DE, HL.
FIL_PUTB: PUSH    BC
        PUSH    DE
        PUSH    HL
        CALL    .PUT
        POP     HL
        POP     DE
        POP     BC
        RET
.PUT:   LD      C,A
        CALL    FIL_PTR
        LD      (HL),C
        LD      A,(IX+FD_POS)
        CP      128
        CCF
        RET     NC              ; room left: carry clear
; Write the buffer as record FD_REC and start the next. Carry if the disk or
; directory is full.
.WRITE: LD      C,34
        CALL    FIL_XFER
        RET     C
        CALL    FIL_NEXT
        LD      (IX+FD_POS),0
        RET

; Close the file, padding a written file's last record. Carry on failure.
FIL_SHUT:
        BIT     0,(IX+FD_FLAGS)
        JR      Z,.SHUT
.PAD:   LD      A,(IX+FD_POS)
        OR      A
        JR      Z,.SHUT
        LD      A,(IX+FD_PAD)
        CALL    FIL_PUTB
        RET     C
        JR      .PAD
.SHUT:  LD      C,16
; BDOS function C on the FD's FCB, with carry when it returns $FF.
FIL_CHK: CALL    FIL_BDOS
        ADD     A,1
        RET

; Delete the file, if it exists.
FIL_DEL:  LD      C,19
; BDOS function C on the FD's FCB.
FIL_BDOS: PUSH    IX
        POP     DE
        JP      CPM_CALL

; Rename the FD's file to the name in the FD at IY. Carry on failure.
FIL_REN:  PUSH    IY
        POP     HL
        PUSH    IX
        POP     DE
        LD      A,E
        ADD     A,16
        LD      E,A
        JR      NC,.COPY
        INC     D
.COPY:  LD      BC,12
        LDIR
        LD      C,23
        JR      FIL_CHK
