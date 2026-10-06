;==========================================================================
;  Closing the streams
;==========================================================================
;
;  The blob writer's (BLOB.ASM) and the output streams' (OUT.ASM) closing
;  code, which runs once, after the compilation has succeeded. It is part
;  of the CHAIN overlay (OVERLAY.ASM), with CHAIN.ASM, whose CH_DONE calls
;  it, so the resident image does not carry it.
;
;  Principal entries:
;    BL_CLOSE   write the trailers and close the streams
;    OUT_CRC    append the stream's CRC, low byte first
;    OUT_END    pad the last record with zeros, write it and close the file

;@ROUTINE CLOBBERS A,BC,DE,HL,CARRY,ZERO,SIGN,PARITY,HALFCARRY
; Write the streams' trailers and close them: the directory's blob count,
; byte stream length, highest ordinal and CRC; the line stream's end tag and
; CRC; the name stream's zero ordinal and CRC.

BL_CLOSE:                      ; Every blob is written.
    PUSH IX                        ; Keep the caller's IX.
    LD   IX,BL_DR                  ; The directory's trailer.
    LD   A,$FF                     ; Its marker.
    CALL OUT_BYTE                  ; Append it.
    LD   HL,(BL_COUNT)             ; The number of blob records.
    CALL OUT_WORD                  ; Append it.
    LD   HL,(BL_BY+OUT_CNT)        ; The byte stream's length, without its
    LD   DE,-8                     ; eight-byte header: the low word,
    ADD  HL,DE                     ; less 8, carry clear on a borrow.
    PUSH HL                        ; Keep it; the carry must reach the high word.
    LD   HL,(BL_BY+OUT_CNT+2)      ; The high word,
    LD   DE,$FFFF                  ; less the borrow:
    ADC  HL,DE                     ; adding $FFFF and the carry does it.
    EX   (SP),HL                   ; HL is the low word; the high word waits.
    CALL OUT_WORD                  ; Append the low word.
    POP  HL                        ; HL is the high word.
    CALL OUT_WORD                  ; Append it.
    LD   HL,(BL_HIGH)              ; The highest ordinal.
    CALL OUT_WORD                  ; Append it.
    XOR  A                         ; A reserved zero byte.
    CALL OUT_BYTE                  ; Append it.
    CALL OUT_CRC                   ; The CRC of the whole stream.
    CALL OUT_END                   ; Close the directory.
    LD   IX,BL_BY                  ; The byte stream has no trailer.
    CALL OUT_END                   ; Close it.
    LD   A,(BL_FLAGS)              ; Is there a line stream?
    AND  BL_LNOUT                  ; Option N leaves it out.
    JR   Z,.NOLINES                ; Then skip it.
    LD   IX,BL_LN                  ; The line stream.
    LD   A,$FF                     ; Its end tag.
    CALL OUT_BYTE                  ; Append it.
    CALL OUT_CRC                   ; Its CRC.
    CALL OUT_END                   ; Close it.
.NOLINES:                      ; The line stream is closed if it was open.
    LD   A,(BL_FLAGS)              ; Is there a name stream?
    AND  BL_NMOUT                  ; Only options M and Y need one.
    JR   Z,.DONE                   ; Then skip it.
    LD   IX,BL_NM                  ; The name stream.
    LD   HL,0                      ; Ordinal zero ends it.
    CALL OUT_WORD                  ; Append it.
    CALL OUT_CRC                   ; Its CRC.
    CALL OUT_END                   ; Close it.
.DONE:                         ; Every stream is closed.
    POP  IX                        ; Restore the caller's IX.
    RET                            ; The linker may read them.

;@ROUTINE IN IX CLOBBERS A,CARRY,ZERO,SIGN,PARITY,HALFCARRY
; Append the stream's CRC of everything written so far, low byte first, as
; the line, name and directory streams end (object format §7, §8, §9).

OUT_CRC:                       ; IX is the stream.
    PUSH HL                        ; Keep the caller's HL.
    LD   L,(IX+OUT_SUM)            ; HL is the CRC
    LD   H,(IX+OUT_SUM+1)          ; of the bytes before it.
    CALL OUT_WORD                  ; Append it; the CRC changes, but is not used again.
    POP  HL                        ; Restore HL.
    RET                            ; The stream is complete.

;@ROUTINE IN IX CLOBBERS A,BC,DE,HL,IY,CARRY,ZERO,SIGN,PARITY,HALFCARRY
; Finish the stream at IX: pad a partly filled record with zeros, write it,
; and close the file. Readers find each stream's end from its contents.

OUT_END:                       ; IX is the stream.
    LD   A,(IX+OUT_POS)            ; Is a record partly filled?
    OR   A                         ; Zero means the last record was written.
    JR   Z,.SHUT                   ; Then only the close remains.
.PAD:                          ; The buffer holds part of a record.
    XOR  A                         ; Pad with zeros,
    CALL OUT_BYTE                  ; which also counts them; no reader uses the count after this.
    LD   A,(IX+OUT_POS)            ; OUT_BYTE writes the record when it fills,
    OR   A                         ; leaving the buffer empty.
    JR   NZ,.PAD                   ; Until then, pad again.
.SHUT:                         ; Every record is written.
    LD   C,BD_CLOSE                ; Close the file, recording its extent.
    CALL OUT_FCB                   ; A is $FF if the close failed.
    INC  A                         ; $FF becomes zero.
    RET  NZ                        ; The file is closed.
    JP   OUT_FAIL                  ; A failed close loses the file.

