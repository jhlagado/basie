; Buffered files over CP/M's random-record calls.
;
; A file descriptor (FD) is an FCB followed by a record buffer. Every read and
; write uses the random calls (BDOS 33 and 34) with the FD's own record
; number, so seeking and sequential access mix freely: after a random read,
; CP/M's sequential read would read the same record again.
;
; Routines take the FD in IX and preserve it.

FD_FCB  EQU     0               ; the FCB (36 bytes; r0-r2 at +33)
FD_POS  EQU     36              ; next byte in the buffer, 0 to 128
FD_FLG  EQU     37              ; bit 0 writing
FD_PAD  EQU     38              ; the byte that pads a written file's last record
FD_REC  EQU     39              ; the buffered record (3 bytes)
FD_BUF  EQU     42              ; the record (128 bytes)
FDSIZE  EQU     170

; Set up the FD's FCB: A = drive (0 the current one, 1 A:), HL = the 8-byte
; name, DE = the 3-byte type, both space-padded.
F_INIT: PUSH    HL
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

; Point CP/M's DMA at the FD's buffer.
F_DMA:  PUSH    IX
        POP     HL
        LD      DE,FD_BUF
        ADD     HL,DE
        EX      DE,HL
        LD      C,26
        JP      BDOS

; Open an existing file for reading. Carry if it doesn't exist.
F_OPEN: PUSH    IX
        POP     DE
        LD      C,15
        CALL    BDOS
        INC     A
        SCF
        RET     Z
        LD      (IX+FD_POS),128
        LD      (IX+FD_FLG),0
        LD      A,$FF           ; no record buffered: the next is record 0
        LD      (IX+FD_REC),A
        LD      (IX+FD_REC+1),A
        LD      (IX+FD_REC+2),A
        OR      A
        RET

; Read record FD_REC into the buffer. Carry past the end of the file.
F_RREC: CALL    F_DMA
        CALL    F_RSET
        PUSH    IX
        POP     DE
        LD      C,33
        CALL    BDOS
        OR      A
        RET     Z
        SCF
        RET

; Copy FD_REC to the FCB's random-record field.
F_RSET: LD      A,(IX+FD_REC)
        LD      (IX+FD_FCB+33),A
        LD      A,(IX+FD_REC+1)
        LD      (IX+FD_FCB+34),A
        LD      A,(IX+FD_REC+2)
        LD      (IX+FD_FCB+35),A
        RET

; FD_REC += 1.
F_RINC: INC     (IX+FD_REC)
        RET     NZ
        INC     (IX+FD_REC+1)
        RET     NZ
        INC     (IX+FD_REC+2)
        RET

; A = the next byte. Carry at the end of the file. Uses BC, DE, HL.
F_GETB: LD      A,(IX+FD_POS)
        CP      128
        JR      C,.HAVE
        CALL    F_RINC
        CALL    F_RREC
        RET     C
        XOR     A
        LD      (IX+FD_POS),A
.HAVE:  LD      E,A
        LD      D,0
        PUSH    IX
        POP     HL
        ADD     HL,DE
        LD      DE,FD_BUF
        ADD     HL,DE
        LD      A,(HL)
        INC     (IX+FD_POS)
        OR      A               ; clears carry, keeps A
        RET

; HL = the next two bytes, low first. Carry at the end of the file.
F_GETW: CALL    F_GETB
        RET     C
        PUSH    AF
        CALL    F_GETB
        JR      C,.END
        LD      H,A
        POP     AF
        LD      L,A
        OR      A
        RET
.END:   POP     AF
        SCF
        RET

; Go to byte offset A:HL (A the high byte) for reading. Carry if that is past
; the end of the file.
F_SEEK: PUSH    HL
        LD      B,A             ; record = offset >> 7, as B:H:L shifted
        ADD     HL,HL
        RL      B
        LD      A,0
        ADC     A,0             ; the bit shifted out of B
        LD      (IX+FD_REC+2),A
        LD      (IX+FD_REC),H
        LD      (IX+FD_REC+1),B
        CALL    F_RREC
        POP     HL
        RET     C
        LD      A,L
        AND     $7F
        LD      (IX+FD_POS),A
        OR      A
        RET

; Create a file for writing, replacing any of the same name (toolchain §3.2).
; A = the byte that pads the last record. Carry if the directory is full.
F_MAKE: LD      (IX+FD_PAD),A
        CALL    F_DEL
        PUSH    IX
        POP     DE
        LD      C,22
        CALL    BDOS
        INC     A
        SCF
        RET     Z
        XOR     A
        LD      (IX+FD_POS),A
        LD      (IX+FD_REC),A
        LD      (IX+FD_REC+1),A
        LD      (IX+FD_REC+2),A
        LD      (IX+FD_FLG),1
        OR      A
        RET

; Write A. Carry if the disk is full. Uses BC, DE, HL.
F_PUTB: LD      C,A
        LD      E,(IX+FD_POS)
        LD      D,0
        PUSH    IX
        POP     HL
        ADD     HL,DE
        LD      DE,FD_BUF
        ADD     HL,DE
        LD      (HL),C
        INC     (IX+FD_POS)
        LD      A,(IX+FD_POS)
        CP      128
        CCF
        RET     NC              ; room left: carry clear
; Write the buffer as record FD_REC and start the next. Carry if the disk or
; directory is full.
F_WREC: CALL    F_DMA
        CALL    F_RSET
        PUSH    IX
        POP     DE
        LD      C,34
        CALL    BDOS
        OR      A
        SCF
        RET     NZ
        CALL    F_RINC
        XOR     A
        LD      (IX+FD_POS),A
        RET

; Close the file, padding a written file's last record. Carry on failure.
F_CLOSE:
        BIT     0,(IX+FD_FLG)
        JR      Z,.SHUT
        LD      A,(IX+FD_POS)
        OR      A
        JR      Z,.SHUT
.PAD:   LD      A,(IX+FD_PAD)
        CALL    F_PUTB
        RET     C
        LD      A,(IX+FD_POS)
        OR      A
        JR      NZ,.PAD
.SHUT:  PUSH    IX
        POP     DE
        LD      C,16
        CALL    BDOS
        INC     A
        SCF
        RET     Z
        OR      A
        RET

; Delete the file, if it exists.
F_DEL:  PUSH    IX
        POP     DE
        LD      C,19
        JP      BDOS

; Rename the FD's file to the name in the FD at IY. Carry on failure.
F_REN:  PUSH    IY
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
        PUSH    IX
        POP     DE
        LD      C,23
        CALL    BDOS
        INC     A
        SCF
        RET     Z
        OR      A
        RET
