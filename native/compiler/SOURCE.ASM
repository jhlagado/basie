;==========================================================================
;  Source parts
;==========================================================================
;
;  Present the program's source to the tokenizer as one ordered stream of
;  bytes, drawn from up to eight resident parts in manifest order. The shell
;  has read every part into memory before compilation begins, and the parts
;  and their descriptor table stay resident until compilation finishes, so
;  the adapter keeps only a pointer into the current part, its end and the
;  position counters that diagnostics report.
;
;  Principal entries:
;    SRC_OPEN  validate the part count and load the first part
;    SRC_LOAD  load the part described at HL and retain the next descriptor
;    SRC_INIT  make the byte range [HL,DE) the current part with identity A
;    SRC_PEEK  return the current byte without consuming it
;    SRC_TAKE  consume one byte, advancing the offset and column
;    SRC_EOL   advance the line counter for one logical line break
;
;  A part descriptor is five bytes (SRC_DLEN): the part's stable identity,
;  then the start and the exclusive end address of its bytes. The table is
;  contiguous, in manifest order.
;
;  SRC_LEFT packs the multipart state in one byte: bits 0..2 count the parts
;  still to come, bits 3..5 hold the current part's manifest ordinal and bit
;  7 records that the line break owed at a part boundary has been delivered.
;  SRC_OPEN sets the count; the tokenizer (TK_ATEND) steps to the next part
;  by adding SRC_STEP-1, one more ordinal and one fewer part to come.
;
;  The current part is SRC_ID, SRC_PTR and SRC_END. SRC_POS is the byte
;  offset within the part; SRC_LINE and SRC_COL count from one. The
;  tokenizer copies them into TK_POS when a token starts, and a diagnostic
;  copies TK_POS together with SRC_ID.

;@ROUTINE IN A,DE,HL OUT A,CARRY,ZERO CLOBBERS SIGN,PARITY,HALFCARRY,DE,HL
; Make the bytes [HL,DE) the current part, with identity A, and restart the
; position counters at offset zero, line one, column one. The tokenizer's
; line state starts afresh: no token yet on the line and no open brackets.

SRC_INIT:
    LD   (SRC_ID),A                ; Record the part identity for diagnostics.
    LD   (SRC_PTR),HL              ; The next byte is the part's first.
    EX   DE,HL                     ; Bring the exclusive end into HL.
    LD   (SRC_END),HL              ; Bound the part for SRC_PEEK.
    LD   HL,0                      ; Form offset zero.
    LD   (SRC_POS),HL              ; Offsets count from the part's start.
    INC  HL                        ; Lines and columns count from one.
    LD   (SRC_LINE),HL             ; Begin on the part's first line.
    LD   (SRC_COL),HL              ; Begin in its first column.
    XOR  A                         ; Form zero and clear carry for success.
    LD   (TK_LIVE),A               ; No token has been seen on this line yet.
    LD   (TK_NEST),A               ; No bracket is open across a line break.
    RET                            ; Return success with A zero.

;@ROUTINE IN A,HL OUT A,CARRY,ZERO CLOBBERS SIGN,PARITY,HALFCARRY,DE,HL
; Begin a compilation of A parts whose descriptors start at HL. One to eight
; parts are accepted (SRC_CAP); any other count reports DG_FILES at part
; zero, line one, column one, and does not return.

SRC_OPEN:
    DEC  A                         ; Count the parts after the first.
    CP   SRC_CAP                   ; Zero parts wrap to 255 and fail here too.
    JR   NC,.FULL                  ; Refuse a count outside one to eight.
    LD   (SRC_LEFT),A              ; Ordinal zero, A parts still to come.
    JR   SRC_LOAD                  ; Load the first descriptor at HL.
.FULL:                             ; Report the part count before any part.
    XOR  A                         ; Form zero for every field below.
    LD   H,A                       ; An empty range at address zero.
    LD   L,A                       ; Clear the start's low byte as well.
    LD   D,A                       ; The end equals the start.
    LD   E,A                       ; Clear the end's low byte as well.
    CALL SRC_INIT                  ; Part zero, offset zero, line and column one.
    CALL TK_MARK                   ; Take that position as the diagnostic's.
    CALL DG_RAISE                  ; Report the bad part count; no return.
    DB   DG_FILES                  ; Diagnostic: too many or too few parts.

;@ROUTINE IN HL OUT A,CARRY,ZERO CLOBBERS SIGN,PARITY,HALFCARRY,DE,HL
; Make the part described at HL current and retain the address of the
; following descriptor in SRC_DESC for the tokenizer's next part step.

SRC_LOAD:
    LD   A,(HL)                    ; Fetch the part's stable identity.
    INC  HL                        ; Step to the start address.
    LD   E,(HL)                    ; Fetch the start's low byte.
    INC  HL                        ; Step to its high byte.
    LD   D,(HL)                    ; DE now holds the part's first byte address.
    INC  HL                        ; Step to the end address.
    PUSH DE                        ; Keep the start while DE takes the end.
    LD   E,(HL)                    ; Fetch the end's low byte.
    INC  HL                        ; Step to its high byte.
    LD   D,(HL)                    ; DE now holds the exclusive end address.
    INC  HL                        ; HL now addresses the next descriptor.
    LD   (SRC_DESC),HL             ; Retain it for the next part boundary.
    POP  HL                        ; HL is the start, as SRC_INIT expects.
    JR   SRC_INIT                  ; Make the range current and return.

;@ROUTINE OUT A,CARRY,ZERO,DE,HL CLOBBERS SIGN,PARITY,HALFCARRY
; Return the current byte in A without consuming it, with carry clear and
; zero set for a NUL byte. At the end of the part, return carry set (the
; separate end event) with A unchanged. HL returns the pointer, DE the end.

SRC_PEEK:
    LD   HL,(SRC_PTR)              ; Address the next unconsumed byte.
    LD   DE,(SRC_END)              ; Fetch the part's exclusive end.
    OR   A                         ; Clear carry for an exact comparison.
    SBC  HL,DE                     ; Zero when the pointer has reached the end.
    ADD  HL,DE                     ; Restore the pointer; zero flag survives.
    JR   NZ,.BYTE                  ; Bytes remain in this part.
    SCF                            ; Report the end of the part.
    RET                            ; Return with A as the caller left it.
.BYTE:                             ; A byte is available.
    LD   A,(HL)                    ; Fetch it without advancing.
    OR   A                         ; Clear carry; zero marks a NUL byte.
    RET                            ; Return the byte.

;@ROUTINE OUT A,CARRY,ZERO CLOBBERS SIGN,PARITY,HALFCARRY,DE,HL
; Consume one byte, returning it as SRC_PEEK does, and advance the byte
; offset and column. Line breaks are counted separately by SRC_EOL because
; LF and CRLF each end one logical line. BC is preserved.

SRC_TAKE:
    PUSH BC                        ; Preserve the caller's BC.
    CALL SRC_PEEK                  ; Fetch the byte or detect the end.
    JR   C,.EOF                    ; Nothing to consume at the end of a part.
    LD   B,A                       ; Keep the byte across the counter updates.
    LD   HL,(SRC_PTR)              ; Fetch the byte pointer.
    INC  HL                        ; Consume the byte.
    LD   (SRC_PTR),HL              ; Publish the advanced pointer.
    LD   HL,(SRC_POS)              ; Fetch the part offset.
    INC  HL                        ; One more byte has been consumed.
    LD   (SRC_POS),HL              ; Publish the advanced offset.
    LD   HL,(SRC_COL)              ; Fetch the column.
    INC  HL                        ; Columns count bytes, not characters.
    LD   (SRC_COL),HL              ; Publish the advanced column.
    LD   A,B                       ; Return the consumed byte.
    POP  BC                        ; Restore the caller's BC.
    OR   A                         ; Clear carry; zero marks a NUL byte.
    RET                            ; Return the byte.
.EOF:                              ; The part is exhausted.
    POP  BC                        ; Restore the caller's BC.
    SCF                            ; Report the end of the part.
    RET                            ; Return with A as SRC_PEEK left it.

;@ROUTINE OUT CARRY CLOBBERS SIGN,PARITY,HALFCARRY,ZERO,HL
; Count one logical line break: the next byte is in column one of the next
; line. The tokenizer calls this once per LF or CRLF. A is preserved.

SRC_EOL:
    LD   HL,(SRC_LINE)             ; Fetch the line counter.
    INC  HL                        ; Move to the next line.
    LD   (SRC_LINE),HL             ; Publish it.
    LD   HL,1                      ; The next byte starts a line.
    LD   (SRC_COL),HL              ; So it is in column one.
    OR   A                         ; Clear carry for success.
    RET                            ; Return to the tokenizer.
