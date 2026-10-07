;==========================================================================
;  Output streams
;==========================================================================
;
;  Sequential CP/M output files for the compiler's four intermediate streams
;  (toolchain §3.2): the directory, byte, line and name streams. Each stream
;  is a caller-owned record holding an FCB, a 128-byte record buffer, the
;  CRC-16/CCITT-FALSE of every byte written so far and a 32-bit count of
;  them. The streams that end with a CRC write it with OUT_CRC; the byte
;  stream's count gives the directory trailer its length.
;
;  Principal entries:
;    OUT_OPEN   delete any old file of the name, make it and reset the stream
;               (BLOPEN.ASM, in the START overlay)
;    OUT_BYTE   append A, updating the CRC and the count
;    OUT_WORD   append HL, low byte first
;    OUT_CRC    append the stream's CRC, low byte first (BLCLOSE.ASM)
;    OUT_END    pad the last record with zeros, write it and close the file
;               (BLCLOSE.ASM, in the CHAIN overlay)
;    OUT_UPD    fold A into the CRC word at HL
;
;  Stream record (OUT_SIZE bytes, addressed by IX):
;    +0   FCB, 36 bytes: drive, name, type, then zeros
;    +36  OUT_POS  bytes in the record buffer, 0 to 127
;    +37  OUT_SUM  the running CRC, initially $FFFF
;    +39  OUT_CNT  bytes written, 32 bits
;    +43  OUT_BUF  the record buffer, 128 bytes
;
;  A disk or directory that is full ends the compilation: the program
;  supplies OUT_FAIL, which reports it and does not return. Every routine
;  preserves IX, and every one but OUT_OPEN and OUT_END preserves BC, DE
;  and HL. BDOS is taken to change every register.

OUT_POS EQU  36                ; Offset of the count of buffered bytes.
OUT_SUM EQU  37                ; Offset of the running CRC word.
OUT_CNT EQU  39                ; Offset of the 32-bit byte count.
OUT_BUF EQU  43                ; Offset of the 128-byte record buffer.
OUT_SIZE EQU  171              ; Bytes in one stream record.
OUT_FCBN EQU  36               ; Bytes of FCB that OUT_OPEN clears.

BD_ENTRY EQU  $0005            ; BDOS entry.
BD_CLOSE EQU  16               ; BDOS close file.
BD_DEL EQU  19                 ; BDOS delete file.
BD_WRITE EQU  21               ; BDOS write sequential: A is nonzero when full.
BD_MAKE EQU  22                ; BDOS make file: A is $FF when the directory is full.
BD_DMA EQU  26                 ; BDOS set DMA address.

;@ROUTINE IN C,IX OUT A CLOBBERS BC,DE,HL,IY,CARRY,ZERO,SIGN,PARITY,HALFCARRY
; Call BDOS function C on the FCB that starts the stream at IX, keeping IX.

OUT_FCB:                       ; C is the BDOS function.
    PUSH IX                        ; DE is the FCB,
    POP  DE                        ; which starts the stream record.

;@ROUTINE IN C,DE,IX OUT A CLOBBERS BC,DE,HL,IY,CARRY,ZERO,SIGN,PARITY,HALFCARRY
; Call BDOS function C with DE, keeping IX.

OUT_BDOS:                      ; C is the function, DE its argument.
    PUSH IX                        ; BDOS may change IX.
    CALL BD_ENTRY                  ; Perform the call; A is its status.
    POP  IX                        ; Restore the stream.
    RET                            ; The caller tests A.

;@ROUTINE IN HL,IX CLOBBERS A,CARRY,ZERO,SIGN,PARITY,HALFCARRY
; Append the word HL to the stream at IX, low byte first.

OUT_WORD:                      ; HL is the word.
    LD   A,L                       ; The low byte goes first.
    CALL OUT_BYTE                  ; Append it.
    LD   A,H                       ; Then the high byte: append it and return.

;@ROUTINE IN A,IX CLOBBERS A,CARRY,ZERO,SIGN,PARITY,HALFCARRY
; Append A to the stream at IX: fold it into the CRC, count it and buffer
; it, writing the record when the buffer fills.

OUT_BYTE:                      ; A is the byte.
    PUSH HL                        ; Keep the caller's registers.
    PUSH DE                        ; DE and BC survive too.
    PUSH BC                        ; Every caller relies on that.
    PUSH IX                        ; HL is the CRC word's address:
    POP  HL                        ; the stream record,
    LD   DE,OUT_SUM                ; plus the CRC's offset; D stays zero.
    ADD  HL,DE                     ; HL addresses the CRC.
    CALL OUT_UPD                   ; Fold A in; A, DE and HL are kept.
    INC  HL                        ; The count follows the CRC's high byte.
    LD   B,4                       ; It has four bytes.
.COUNT:                        ; HL addresses the byte before the next.
    INC  HL                        ; The count's next byte.
    INC  (HL)                      ; Count the byte in it.
    JR   NZ,.COUNTED               ; Only a wrap carries into the next.
    DJNZ .COUNT                    ; No stream comes near 4G, but the field is exact.
.COUNTED:                      ; A is still the byte, D zero.
    LD   E,(IX+OUT_POS)            ; DE is where it goes in the buffer.
    PUSH IX                        ; HL is the buffer's start:
    POP  HL                        ; the stream record,
    ADD  HL,DE                     ; plus the offset,
    LD   E,OUT_BUF                 ; plus the buffer's
    ADD  HL,DE                     ; offset in the record.
    LD   (HL),A                    ; Buffer the byte.
    INC  (IX+OUT_POS)              ; One more byte is buffered: sign at 128.
    CALL M,.WRITE                  ; A full buffer is written out.
    POP  BC                        ; Restore the caller's registers.
    POP  DE                        ; In the order they were saved.
    POP  HL                        ; HL last.
    RET                            ; The byte is in the stream.

;@ROUTINE IN HL,IX CLOBBERS A,BC,DE,HL,CARRY,ZERO,SIGN,PARITY,HALFCARRY
; Write the buffer as the file's next record and empty it. HL addresses
; the buffer's last byte.

.WRITE:                        ; The buffer holds a whole record.
    PUSH IY                        ; The BIOS may change IY; the caller's is kept.
    LD   DE,-127                   ; The buffer starts
    ADD  HL,DE                     ; 127 bytes before its last.
    EX   DE,HL                     ; DE is the buffer.
    LD   C,BD_DMA                  ; Point the DMA address at it.
    CALL OUT_BDOS                  ; Set the DMA address to DE.
    LD   C,BD_WRITE                ; Write the next record.
    CALL OUT_FCB                   ; A is nonzero if the disk is full.
    OR   A                         ; Was it written?
    JP   NZ,OUT_FAIL               ; No room: the build cannot go on.
    LD   (IX+OUT_POS),A            ; The buffer is empty again.
    POP  IY                        ; Restore the caller's IY.
    RET                            ; The record is on the disk.

;@ROUTINE IN A,HL OUT HL CLOBBERS B,CARRY,ZERO,SIGN,PARITY,HALFCARRY
; Fold A into the CRC-16/CCITT-FALSE word at HL (polynomial $1021, most
; significant bit first). A and HL are kept.

OUT_UPD:                       ; HL addresses the CRC word, low byte first.
    PUSH DE                        ; DE holds the CRC while it is worked.
    PUSH AF                        ; Keep the byte for the caller.
    LD   E,(HL)                    ; DE is the CRC:
    INC  HL                        ; its low byte,
    LD   D,(HL)                    ; then its high byte.
    XOR  D                         ; The byte enters at the top.
    LD   D,A                       ; DE is the CRC with the byte folded in.
    LD   B,8                       ; Shift out eight bits.
.BIT:                          ; DE is the partial remainder.
    SLA  E                         ; Shift the remainder left one bit:
    RL   D                         ; carry is the bit shifted out.
    JR   NC,.NEXT                  ; A zero bit needs no polynomial.
    LD   A,D                       ; A one bit subtracts the polynomial:
    XOR  $10                       ; its high byte
    LD   D,A                       ; into D,
    LD   A,E                       ; its low byte
    XOR  $21                       ; into E.
    LD   E,A                       ; The remainder is reduced.
.NEXT:                         ; One bit is done.
    DJNZ .BIT                      ; Until all eight are.
    LD   (HL),D                    ; Store the CRC's high byte,
    DEC  HL                        ; then step back
    LD   (HL),E                    ; to store its low byte.
    POP  AF                        ; Restore the byte.
    POP  DE                        ; Restore DE.
    RET                            ; HL addresses the CRC again.
