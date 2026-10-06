;==========================================================================
;  Source parts
;==========================================================================
;
;  Present the program's source to the tokenizer as one ordered stream of
;  bytes, drawn from the resident parts in stream order: each part after
;  the parts it includes (spec 4.3.2). The START overlay (PARTS.ASM) has
;  read every part into memory and described it in the part table before
;  compilation begins, and the parts and the table stay resident until it
;  finishes, so the adapter keeps only a pointer into the current part,
;  its end and the position counters that diagnostics report.
;
;  Principal entries:
;    SRC_PART  address a part's entry in the part table
;    SRC_FIND  find the part with a given number in the stream
;    SRC_OPEN  begin the compilation at the stream's first part
;    SRC_BODY make the stream's part A current, at its body
;    SRC_INIT  make the byte range [HL,DE) the current part with identity A
;              (in PARTS.ASM, the PARTS overlay: only the loader uses it)
;    SRC_PEEK  return the current byte without consuming it
;    SRC_TAKE  consume one byte, advancing the offset and column
;    SRC_EOL   advance the line counter for one logical line break
;
;  The part table grows down from SRC_PTAB, the top of the source area, to
;  meet the parts' bytes, which are loaded up from MM_SRC: entry L, for
;  the L'th part the loader reached, is the PT_LEN bytes at SRC_PTAB
;  less PT_LEN times L+1. There are SRC_PCNT entries, at most 255, the
;  line stream's limit. An entry is:
;
;    +0   SH_SLOT bytes  the part's drive and name, as an FCB holds them
;    +12  word           PT_START: its first byte's address
;    +14  word           PT_END: its exclusive end
;    +16  word           PT_BODY: the offset of its body, after its
;                        include lines, where its compilation begins
;    +18  word           PT_LINE: the line the body begins on
;    +20  byte           PT_NUM: its number in the stream, PT_OPEN
;                        while its includes are being loaded
;
;  The current part is SRC_ID, SRC_PTR and SRC_END. SRC_ID is the part's
;  entry plus one, which diagnostics name (DG_PART); SRC_NUM is its number
;  in the stream, which the line stream records. SRC_POS is the byte
;  offset within the part; SRC_LINE and SRC_COL count from one. The
;  tokenizer copies them into TK_POS when a token starts, and a diagnostic
;  copies TK_POS together with SRC_ID. The tokenizer steps to the next part
;  (TK_ATEND) through SRC_BODY.

PT_LEN EQU  21                 ; Bytes in one part table entry.
PT_START EQU  12               ; Entry field: the part's first byte (word).
PT_END EQU  14                 ; Entry field: its exclusive end (word).
PT_BODY EQU  16                ; Entry field: its body's offset (word).
PT_LINE EQU  18                ; Entry field: its body's first line (word).
PT_NUM EQU  20                 ; Entry field: its number in the stream.
PT_OPEN EQU  $FF               ; PT_NUM of a part whose includes are loading.

;@ROUTINE IN A OUT HL CLOBBERS A,DE,CARRY,ZERO,SIGN,PARITY,HALFCARRY
; Address in HL the part table's entry A: SRC_PTAB less PT_LEN times A+1.
; BC is kept.

SRC_PART:                      ; A is the entry's index.
    LD   L,A                       ; HL is the
    LD   H,0                       ; index
    INC  HL                        ; plus one,
    LD   D,H                       ; and so
    LD   E,L                       ; is DE.
    ADD  HL,HL                     ; Times two,
    ADD  HL,HL                     ; four,
    ADD  HL,DE                     ; five,
    ADD  HL,HL                     ; ten,
    ADD  HL,HL                     ; twenty,
    ADD  HL,DE                     ; twenty-one: PT_LEN.
    EX   DE,HL                     ; DE is the distance down
    LD   HL,(SRC_PTAB)             ; from the table's top.
    OR   A                         ; Clear carry.
    SBC  HL,DE                     ; HL is the entry.
    RET                            ; Addressed.

;@ROUTINE IN A OUT B,HL CLOBBERS A,C,DE,CARRY,ZERO,SIGN,PARITY,HALFCARRY
; Find the part numbered A in the stream: HL addresses its entry's
; PT_NUM byte and B is its index. The part is in the table.

SRC_FIND:                      ; A is the number.
    LD   C,A                       ; Keep it.
    LD   B,0                       ; From the first entry.
.LOOP:                         ; B is the entry to try.
    LD   A,B                       ; Address
    CALL SRC_PART                  ; it,
    LD   DE,PT_NUM                 ; its number:
    ADD  HL,DE                     ; is it
    LD   A,(HL)                    ; the one
    CP   C                         ; sought?
    RET  Z                         ; Yes.
    INC  B                         ; No: the next entry.
    JR   .LOOP                     ; Try it.

;@ROUTINE OUT A,CARRY,ZERO CLOBBERS SIGN,PARITY,HALFCARRY,BC,DE,HL
; Begin a compilation at the stream's first part, owing no line end.

SRC_OPEN:
    XOR  A                         ; No boundary line end
    LD   (SRC_OWE),A               ; is owed; part zero of the stream
                                   ; is current; fall into SRC_BODY.

;@ROUTINE IN A OUT A,CARRY,ZERO CLOBBERS SIGN,PARITY,HALFCARRY,BC,DE,HL
; Make the stream's part A current at its body: the bytes after its
; include lines, at the offset and line where they begin, in column one.
; The tokenizer's line state starts afresh: no token yet on the line and
; no open brackets.

SRC_BODY:                      ; A is the part's number.
    LD   (SRC_NUM),A               ; It is current.
    CALL SRC_FIND                  ; HL is its PT_NUM, B its index.
    INC  B                         ; Its index plus one
    LD   A,B                       ; is its identity
    LD   (SRC_ID),A                ; for diagnostics.
    DEC  HL                        ; The entry's start, end, body offset
    LD   DE,SRC_LINE+1             ; and line, the four words below its
    LD   BC,8                      ; number, are SRC_PTR, SRC_END, SRC_POS
    LDDR                           ; and SRC_LINE, copied from the top down.
    LD   HL,(SRC_PTR)              ; The start
    LD   DE,(SRC_POS)              ; and the body's offset
    ADD  HL,DE                     ; give
    LD   (SRC_PTR),HL              ; the body's first byte.
    LD   HL,1                      ; The body
    LD   (SRC_COL),HL              ; begins in column one,
    XOR  A                         ; no token
    LD   (TK_LIVE),A               ; on its line
    LD   (TK_NEST),A               ; and no bracket open.
    RET                            ; A is zero; carry clear.

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
.BYTE:                         ; A byte is available.
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
.EOF:                          ; The part is exhausted.
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
