;==========================================================================
;  Buffered files
;==========================================================================
;
;  Buffered files over CP/M's random-record calls. A file descriptor (FD)
;  is an FCB followed by a record buffer. Every read and write uses the
;  random calls (BDOS 33 and 34) with the FD's own record number, so seeking
;  and sequential access mix freely: after a random read, CP/M's sequential
;  read would read the same record again.
;
;  Principal entries:
;    FIL_INIT  set up an FD's FCB from a drive, a name and a type
;    FIL_OPEN  open an existing file for reading
;    FIL_GETB  read the next byte (FIL_GETW the next word, low byte first)
;    FIL_SEEK  go to a 24-bit byte offset for reading
;    FIL_MAKE  create a file for writing, replacing any of the same name
;    FIL_PUTB  write a byte
;    FIL_SHUT  close a file, padding a written file's last record
;    FIL_DEL   delete a file; FIL_REN rename one to another FD's name
;    FIL_TEXT  (CHECKS.ASM) a file's name as text, for diagnostics
;
;  An FD is FD_SIZE bytes, laid out by the FD_ offsets below. FD_POS is the
;  next byte of the buffer, 0 to 127; 128 means the buffer is used up, and
;  129 that the file has just been opened and record 0 is not yet read. The
;  buffer is written back only when it fills, or when FIL_SHUT pads it out.
;
;  Registers: every routine takes the FD in IX and keeps it. Failures are
;  returned as carry for the caller to report.

FD_FCB EQU  0                  ; The FCB, 36 bytes: drive, name, type and the rest.
FD_REC EQU  33                 ; Its random-record field: the record in the buffer.
FD_POS EQU  36                 ; The buffer's next byte, 0 to 128; 129 just opened.
FD_FLAGS EQU  37               ; Bit 0 set when the file is being written.
FD_PAD EQU  38                 ; The byte that pads a written file's last record.
FD_BUF EQU  39                 ; The record buffer, 128 bytes.
FD_SIZE EQU  167               ; Bytes in an FD: FD_BUF and the buffer.

;@ROUTINE IN A,DE,HL,IX OUT A CLOBBERS BC,DE,HL,CARRY,ZERO,SIGN,PARITY,HALFCARRY
; Set up the FD's FCB: A is the drive (0 the current one, 1 A:), HL the
; 8-byte name and DE the 3-byte type, both space-padded. Every other field
; up to the buffer is zero, and FD_POS is 128 until the file is opened.

FIL_INIT:                      ; IX is the FD; A, HL and DE name the file.
    PUSH HL                        ; Keep the name while HL walks the FD.
    PUSH IX                        ; Copy the FD's address
    POP  HL                        ; into HL.
    LD   B,FD_BUF                  ; Clear the FCB and the fields after it.
.ZERO:                         ; HL walks the FD's first FD_BUF bytes.
    LD   (HL),0                    ; Clear one byte.
    INC  HL                        ; Step to the next.
    DJNZ .ZERO                     ; Until the buffer is reached.
    LD   (IX+FD_FCB),A             ; The FCB's first byte is the drive.
    PUSH IX                        ; HL is the FD again,
    POP  HL                        ; which is the FCB's drive byte.
    INC  HL                        ; HL is the FCB's name.
    EX   (SP),HL                   ; HL is the name; the FCB's name is on the stack.
    EX   DE,HL                     ; DE is the name, HL the type.
    EX   (SP),HL                   ; HL is the FCB's name; the type is on the stack.
    EX   DE,HL                     ; DE is the FCB's name, HL the name.
    LD   BC,8                      ; Eight name characters,
    LDIR                           ; copied; DE is now the FCB's type.
    POP  HL                        ; HL is the type.
    LD   BC,3                      ; Three type characters,
    LDIR                           ; copied.
    LD   (IX+FD_POS),128           ; Not yet open: no buffered byte.
    RET                            ; A is still the drive.

;@ROUTINE IN IX OUT CARRY CLOBBERS A,BC,DE,HL,ZERO,SIGN,PARITY,HALFCARRY
; Open an existing file, set up by FIL_INIT, for reading. Carry if it
; doesn't exist.

FIL_OPEN:                      ; IX is an FD set up by FIL_INIT.
    LD   C,15                      ; BDOS 15: open file.
    CALL FIL_CHK                   ; Carry when the BDOS returns $FF: no such file.
    RET  C                         ; Report the missing file.
    LD   (IX+FD_POS),129           ; The first read reads record 0.
    RET                            ; Carry is clear.

;@ROUTINE IN IX OUT A,CARRY CLOBBERS BC,DE,HL,ZERO,SIGN,PARITY,HALFCARRY
; Read record FD_REC into the buffer. Carry past the end of the file.

FIL_READ:                      ; FD_REC is the record to read.
    LD   C,33                      ; BDOS 33: read random; fall into the transfer.

;@ROUTINE IN C,IX OUT A,CARRY CLOBBERS BC,DE,HL,ZERO,SIGN,PARITY,HALFCARRY
; Read or write, as BDOS function C (33 or 34), record FD_REC through the
; buffer. Carry on failure.

FIL_XFER:                      ; C is the BDOS function.
    PUSH BC                        ; Keep the function across the DMA call.
    PUSH IX                        ; The DMA address is the FD's buffer:
    POP  HL                        ; HL is the FD,
    LD   DE,FD_BUF                 ; and the buffer is FD_BUF bytes on.
    ADD  HL,DE                     ; HL is the buffer.
    EX   DE,HL                     ; BDOS 26 takes it in DE.
    LD   C,26                      ; BDOS 26: set the DMA address.
    CALL CPM_CALL                  ; Point CP/M at the buffer.
    POP  BC                        ; C is the read or write function again.
    CALL FIL_BDOS                  ; Transfer the record; A is 0 on success.
    CP   1                         ; Carry when A is 0,
    CCF                            ; so carry when it is not: a failure.
    RET                            ; Carry reports the end of file or a full disk.

;@ROUTINE IN IX CLOBBERS ZERO,SIGN,PARITY,HALFCARRY
; Advance FD_REC, the 24-bit record number, by one.

FIL_NEXT:                      ; FD_REC is three bytes, low first.
    INC  (IX+FD_REC)               ; Add one to the low byte.
    RET  NZ                        ; Done unless it wrapped to zero.
    INC  (IX+FD_REC+1)             ; Carry into the middle byte.
    RET  NZ                        ; Done unless that wrapped too.
    INC  (IX+FD_REC+2)             ; Carry into the high byte.
    RET                            ; The record number is one higher.

;@ROUTINE IN IX OUT A,CARRY CLOBBERS ZERO,SIGN,PARITY,HALFCARRY
; Read the next byte into A, keeping BC, DE and HL. Carry at the end of the
; file.

FIL_GETB:                      ; IX is a file open for reading.
    PUSH BC                        ; Reading a record changes BC,
    PUSH DE                        ; DE,
    PUSH HL                        ; and HL.
    CALL .GET                      ; A is the byte, or carry at the end.
    POP  HL                        ; Recover HL,
    POP  DE                        ; DE,
    POP  BC                        ; and BC.
    RET                            ; A and carry are .GET's.

;@ROUTINE IN IX OUT A,CARRY CLOBBERS BC,DE,HL,ZERO,SIGN,PARITY,HALFCARRY
; FIL_GETB without saving registers: refill the buffer if it is used up,
; then take its next byte.

.GET:                          ; FD_POS says whether the buffer has a byte left.
    LD   A,(IX+FD_POS)             ; A is the next byte's position, or 128 or 129.
    CP   128                       ; Is there a byte left in the buffer?
    JR   C,.HAVE                   ; Then take it.
    CALL Z,FIL_NEXT                ; 128: the buffer is used up, read the next record.
    CALL FIL_READ                  ; 129 reads record 0, just opened.
    RET  C                         ; Carry: the file has ended.
    LD   (IX+FD_POS),0             ; The new record starts at its first byte.
.HAVE:                         ; The buffer holds the next byte.
    CALL FIL_PTR                   ; HL is the byte, and FD_POS moves past it.
    LD   A,(HL)                    ; A is the byte.
    OR   A                         ; Clear carry, keeping A.
    RET                            ; Carry clear: a byte was read.

;@ROUTINE IN IX OUT HL CLOBBERS DE,CARRY,ZERO,SIGN,PARITY,HALFCARRY
; Point HL at the buffer's next byte, and move FD_POS past it.

FIL_PTR:                       ; FD_POS is 0 to 127.
    LD   E,(IX+FD_POS)             ; DE is the position in the buffer,
    LD   D,0                       ; zero-extended.
    PUSH IX                        ; HL is the FD,
    POP  HL                        ; to which the position is added.
    ADD  HL,DE                     ; HL is the FD plus the position.
    LD   DE,FD_BUF                 ; And the buffer's offset in the FD.
    ADD  HL,DE                     ; HL is the byte.
    INC  (IX+FD_POS)               ; The next call takes the byte after it.
    RET                            ; HL addresses the byte.

;@ROUTINE IN IX OUT A,HL,CARRY CLOBBERS ZERO,SIGN,PARITY,HALFCARRY
; Read the next two bytes into HL, low first. Carry at the end of the file.

FIL_GETW:                      ; IX is a file open for reading.
    CALL FIL_GETB                  ; The low byte.
    RET  C                         ; Carry: the file has ended.
    LD   L,A                       ; L is the low byte.
    CALL FIL_GETB                  ; The high byte; carry if the file ended.
    LD   H,A                       ; H is the high byte.
    RET                            ; Carry reports the second read.

;@ROUTINE IN A,HL,IX OUT A,CARRY CLOBBERS B,DE,ZERO,SIGN,PARITY,HALFCARRY
; Go to byte offset A:HL (A the high byte) for reading: read the record that
; holds it and point FD_POS at the byte. Carry if that is past the end of
; the file. HL is kept.

FIL_SEEK:                      ; A:HL is a 24-bit byte offset.
    PUSH HL                        ; Keep the offset's low word for its position.
    LD   B,A                       ; B:H:L is the offset.
    ADD  HL,HL                     ; Shift B:H:L left one bit:
    RL   B                         ; B:H is now the offset >> 7, the record,
    LD   A,0                       ; apart from the bit shifted out of B,
    RLA                            ; which A takes as the record's high byte.
    LD   (IX+FD_REC+2),A           ; Record bits 16 and up.
    LD   (IX+FD_REC),H             ; Record bits 0 to 7.
    LD   (IX+FD_REC+1),B           ; Record bits 8 to 15.
    CALL FIL_READ                  ; Read that record; carry past the end.
    POP  HL                        ; HL is the offset's low word again.
    RET  C                         ; The offset is past the end of the file.
    LD   A,L                       ; The position in the record is
    AND  $7F                       ; the offset's low seven bits; this clears carry.
    LD   (IX+FD_POS),A             ; The next read takes that byte.
    RET                            ; Carry is clear.

;@ROUTINE IN A,IX OUT CARRY CLOBBERS A,BC,DE,HL,ZERO,SIGN,PARITY,HALFCARRY
; Create a file, set up by FIL_INIT, for writing, replacing any of the same
; name (toolchain §3.2). A is the byte that pads the last record. Carry if
; the directory is full.

FIL_MAKE:                      ; IX is an FD set up by FIL_INIT.
    LD   (IX+FD_PAD),A             ; Keep the padding for FIL_SHUT.
    CALL FIL_DEL                   ; Replace any file of the same name.
    LD   C,22                      ; BDOS 22: make file.
    CALL FIL_CHK                   ; Carry when the BDOS returns $FF.
    RET  C                         ; The directory is full.
    LD   (IX+FD_POS),0             ; The buffer is empty; FD_REC is 0.
    LD   (IX+FD_FLAGS),1           ; The file is being written.
    RET                            ; Carry is clear.

;@ROUTINE IN A,IX OUT CARRY CLOBBERS A,ZERO,SIGN,PARITY,HALFCARRY
; Write the byte in A, keeping BC, DE and HL. Carry if the disk is full.

FIL_PUTB:                      ; IX is a file made by FIL_MAKE.
    PUSH BC                        ; Writing a record changes BC,
    PUSH DE                        ; DE,
    PUSH HL                        ; and HL.
    CALL .PUT                      ; Buffer the byte, writing the record if full.
    POP  HL                        ; Recover HL,
    POP  DE                        ; DE,
    POP  BC                        ; and BC.
    RET                            ; Carry is .PUT's.

;@ROUTINE IN A,IX OUT CARRY CLOBBERS A,BC,DE,HL,ZERO,SIGN,PARITY,HALFCARRY
; FIL_PUTB without saving registers: put A in the buffer, and write the
; record when that fills it.

.PUT:                          ; FD_POS is 0 to 127: there is room.
    LD   C,A                       ; Keep the byte while HL is found.
    CALL FIL_PTR                   ; HL is its place, and FD_POS moves past it.
    LD   (HL),C                    ; Store the byte.
    LD   A,(IX+FD_POS)             ; A is the next position.
    CP   128                       ; Carry while the buffer has room,
    CCF                            ; inverted: carry clear while there is room.
    RET  NC                        ; Room left: return with carry clear.

;@ROUTINE IN IX OUT CARRY CLOBBERS A,BC,DE,HL,ZERO,SIGN,PARITY,HALFCARRY
; Write the buffer as record FD_REC and start the next. Carry if the disk or
; the directory is full.

.WRITE:                        ; The buffer is full.
    LD   C,34                      ; BDOS 34: write random.
    CALL FIL_XFER                  ; Write it; carry on failure.
    RET  C                         ; The disk or directory is full.
    CALL FIL_NEXT                  ; The next record follows.
    LD   (IX+FD_POS),0             ; And starts empty.
    RET                            ; Carry is clear.

;@ROUTINE IN IX OUT CARRY CLOBBERS A,BC,DE,HL,ZERO,SIGN,PARITY,HALFCARRY
; Close the file, padding a written file's last record with FD_PAD. Carry on
; failure.

FIL_SHUT:                      ; IX is an open file.
    BIT  0,(IX+FD_FLAGS)           ; Is the file being written?
    JR   Z,.SHUT                   ; A file read needs no padding.
.PAD:                          ; Fill the last record until it is written.
    LD   A,(IX+FD_POS)             ; A is the buffer's next position.
    OR   A                         ; Is the buffer empty?
    JR   Z,.SHUT                   ; Then every record is written.
    LD   A,(IX+FD_PAD)             ; A is the padding byte.
    CALL FIL_PUTB                  ; Add it; the last one writes the record.
    RET  C                         ; The disk is full.
    JR   .PAD                      ; Until FD_POS returns to 0.
.SHUT:                         ; Nothing is left to write.
    LD   C,16                      ; BDOS 16: close file; fall into FIL_CHK.

;@ROUTINE IN C,IX OUT A,CARRY CLOBBERS BC,DE,HL,ZERO,SIGN,PARITY,HALFCARRY
; Call BDOS function C on the FD's FCB, with carry when it returns $FF.

FIL_CHK:                       ; C is an open, close, make or rename function.
    CALL FIL_BDOS                  ; A is the BDOS's result.
    ADD  A,1                       ; $FF, a failure, carries to zero.
    RET                            ; Carry reports the failure.

;@ROUTINE IN IX CLOBBERS A,BC,DE,HL,CARRY,ZERO,SIGN,PARITY,HALFCARRY
; Delete the file, if it exists.

FIL_DEL:                       ; IX is an FD set up by FIL_INIT.
    LD   C,19                      ; BDOS 19: delete file; fall into FIL_BDOS.

;@ROUTINE IN C,IX OUT A CLOBBERS BC,DE,HL,CARRY,ZERO,SIGN,PARITY,HALFCARRY
; Call BDOS function C on the FD's FCB.

FIL_BDOS:                      ; C is the function.
    PUSH IX                        ; The FCB is the FD's first field,
    POP  DE                        ; so DE is the FD.
    JP   CPM_CALL                  ; Call the BDOS, which returns to the caller.

;@ROUTINE IN IX,IY OUT CARRY CLOBBERS A,BC,DE,HL,ZERO,SIGN,PARITY,HALFCARRY
; Rename the FD's file to the name in the FD at IY. Carry on failure.

FIL_REN:                       ; IX names the file, IY its new name.
    PUSH IY                        ; HL is the new name's FCB,
    POP  HL                        ; whose drive, name and type are copied.
    PUSH IX                        ; DE is the old name's FCB,
    POP  DE                        ; whose bytes 16 on take the new name.
    LD   A,E                       ; Add 16 to DE,
    ADD  A,16                      ; low byte first,
    LD   E,A                       ; keeping the carry,
    JR   NC,.COPY                  ; which is rare,
    INC  D                         ; into the high byte.
.COPY:                         ; DE is FCB+16, where BDOS 23 reads the new name.
    LD   BC,12                     ; The drive, eight name and three type bytes.
    LDIR                           ; Copy them.
    LD   C,23                      ; BDOS 23: rename file.
    JR   FIL_CHK                   ; Carry when it returns $FF: no such file.
