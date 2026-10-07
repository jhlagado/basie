;==========================================================================
;  Source parts
;==========================================================================
;
;  Present the program's source to the tokenizer as one ordered stream of
;  bytes, drawn from the parts in stream order: each part after the parts
;  it includes (spec 4.3.2). The PARTS overlay (PARTS.ASM) has read every
;  part and described it in the part table before compilation begins; the
;  table stays until it finishes, but a part's bytes are loaded again, at
;  MM_SRC, as it becomes current (SRC_BODY, SRC_LOAD), over the part before,
;  so the source area holds the largest part rather than all of them. The
;  adapter keeps a pointer into the current part, its end and the position
;  counters that diagnostics report.
;
;  Principal entries:
;    SRC_PART  address a part's entry in the part table
;    SRC_FIND  find the part with a given number in the stream
;    SRC_OPEN  begin the compilation at the stream's first part
;    SRC_BODY make the stream's part A current, at its body
;    SRC_LOAD  load a part's bytes again, at MM_SRC
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
; Begin a compilation at the stream's first part, owing no line end, the
; name heap starting below the part table.

SRC_OPEN:
    LD   A,(SRC_PCNT)              ; The part table's
    DEC  A                         ; last entry,
    CALL SRC_PART                  ; its bottom,
    LD   (NH_PTR),HL               ; begins the name heap (TK_KEEP).
    XOR  A                         ; No boundary line end
    LD   (SRC_OWE),A               ; is owed; part zero of the stream
                                   ; is current; fall into SRC_BODY.

;@ROUTINE IN A OUT A,CARRY,ZERO CLOBBERS SIGN,PARITY,HALFCARRY,BC,DE,HL
; Make the stream's part A current at its body: the bytes after its
; include lines, at the offset and line where they begin, in column one,
; its bytes loaded first unless they are (SRC_LOAD); no constant waits
; after them yet (RG_PEND). The tokenizer's line state starts afresh: no
; token yet on the line and no open brackets.

SRC_BODY:                      ; A is the part's number.
    LD   (SRC_NUM),A               ; It is current.
    CALL SRC_FIND                  ; HL is its PT_NUM, B its index.
    LD   A,(SRC_RES)               ; Are its bytes
    CP   B                         ; the ones loaded?
    JR   Z,.HERE                   ; Yes.
    LD   A,B                       ; Otherwise
    CALL SRC_LOAD                  ; they are loaded,
    LD   A,(SRC_NUM)               ; and its entry
    CALL SRC_FIND                  ; found again.
.HERE:                         ; HL is its PT_NUM, B its index.
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
    LD   HL,(SRC_END)              ; Nothing waits
    LD   (RG_PEND),HL              ; after its end.
    LD   HL,1                      ; The body
    LD   (SRC_COL),HL              ; begins in column one,
    DEC  HL                        ; with no token on its line (TK_LIVE)
    LD   (TK_LIVE),HL              ; and no bracket open (TK_NEST, after it).
    XOR  A                         ; A is zero;
    RET                            ; carry clear.

;@ROUTINE IN A CLOBBERS A,BC,DE,HL,CARRY,ZERO,SIGN,PARITY,HALFCARRY
; Load part table entry A again, at MM_SRC below the name heap
; (SH_AGAIN). DG_ROOM if its records do not fit. IX and IY are kept.

SRC_LOAD:                      ; A is the entry.
    PUSH IX                        ; Keep IX
    PUSH IY                        ; and IY.
    LD   HL,(NH_PTR)               ; Below the heap
    CALL SH_AGAIN                  ; it is read.
    POP  IY                        ; IY
    POP  IX                        ; and IX again.
    RET  NC                        ; The part is loaded,
    CALL DG_RAISE                  ; or too large
    DB   DG_ROOM                   ; for the memory.

;@ROUTINE IN A,HL OUT CARRY CLOBBERS A,BC,DE,HL,IX,IY,ZERO,SIGN,PARITY,HALFCARRY
; Load part table entry A again, at MM_SRC, its whole records below the
; limit HL, and make it the one loaded (SRC_RES): its length is its end
; less its start, which become MM_SRC and MM_SRC plus the length. Carry if
; its records would cross the limit: nothing is read, SRC_RES and the bytes
; at MM_SRC are kept, but the entry names MM_SRC. A part no longer on the
; disk, or one CP/M can't read, does not return (SH_AGERR). Resident, so
; that a part is loaded again without displacing an overlay.

SH_AGAIN:                      ; A is the entry, HL the limit.
    PUSH AF                        ; Keep the entry
    PUSH HL                        ; and the limit.
    CALL SRC_PART                  ; HL is the entry,
    LD   (SH_CUR),HL               ; named if it can't be read.
    CALL SH_BLANK                  ; A clear FCB
    LD   DE,SH_FCB                 ; takes
    LD   BC,SH_SLOT                ; its drive
    LDIR                           ; and name; HL is at its PT_START.
    LD   DE,MM_SRC                 ; It loads at the base:
    LD   C,(HL)                    ; its start,
    LD   (HL),E                    ; BC,
    INC  HL                        ; becomes
    LD   B,(HL)                    ; the
    LD   (HL),D                    ; base;
    INC  HL                        ; its end
    LD   A,(HL)                    ; less
    SUB  C                         ; its
    LD   C,A                       ; start
    INC  HL                        ; is
    LD   A,(HL)                    ; its
    SBC  A,B                       ; length,
    LD   B,A                       ; BC,
    EX   DE,HL                     ; and the
    ADD  HL,BC                     ; base plus it
    EX   DE,HL                     ; its
    LD   (HL),D                    ; new
    DEC  HL                        ; end,
    LD   (HL),E                    ; DE.
    LD   HL,127                    ; Its whole
    ADD  HL,BC                     ; records'
    LD   A,L                       ; bytes,
    AND  $80                       ; rounded
    LD   L,A                       ; up,
    LD   B,H                       ; are
    LD   C,L                       ; BC;
    LD   DE,MM_SRC                 ; from
    ADD  HL,DE                     ; the base
    EX   DE,HL                     ; they end
    POP  HL                        ; at or
    OR   A                         ; below
    SBC  HL,DE                     ; the limit,
    POP  DE                        ; (the entry, D)
    RET  C                         ; or there is no room.
    PUSH DE                        ; The entry, kept.
    LD   A,C                       ; The records
    RLA                            ; are their
    LD   A,B                       ; bytes over
    RLA                            ; 128,
    PUSH AF                        ; kept.
    LD   DE,SH_FCB                 ; Open
    LD   C,SH_OPEN                 ; the
    CALL SH_BDOS                   ; part;
    INC  A                         ; Not on the disk ($FF):
    JR   Z,SH_AGERR                ; L-MISSING.
    POP  BC                        ; B records
    LD   HL,MM_SRC                 ; to the base.
.READ:                         ; HL is the next record's place.
    LD   A,B                       ; None
    OR   A                         ; left:
    JR   Z,.READ0                  ; loaded.
    PUSH BC                        ; Keep the count
    PUSH HL                        ; and the place.
    EX   DE,HL                     ; The record
    LD   C,SH_DMA                  ; is read
    CALL SH_BDOS                   ; there,
    LD   DE,SH_FCB                 ; the
    LD   C,SH_READ                 ; next
    CALL SH_BDOS                   ; of the part.
    POP  HL                        ; The place
    POP  BC                        ; and the count.
    OR   A                         ; Unread, or the file shorter:
    JR   NZ,SH_AGERR               ; L-IO.
    LD   DE,128                    ; The next
    ADD  HL,DE                     ; place,
    DEC  B                         ; one fewer
    JR   .READ                     ; to read.
.READ0:                        ; The part is loaded:
    POP  AF                        ; the entry (D)
    LD   (SRC_RES),A               ; is the one loaded.
    OR   A                         ; Carry clear.
    RET                            ; Done.

;@ROUTINE IN A NORETURN
; Report the part SH_AGAIN could not load again (SH_CUR): A zero, not on
; the disk (L-MISSING), else unreadable (L-IO). The PARTS overlay, loaded
; for it, names the part (SH_GONE).

SH_AGERR:                      ; A is zero if the part is missing.
    PUSH AF                        ; Keep it.
    LD   A,OV_PARTS                ; The parts'
    CALL OV_LOAD                   ; overlay
    POP  AF                        ; reports
    JP   OV_AREA+3                 ; it (SH_GONE).

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
    SCF                            ; Carry reports the end of the part,
    RET  Z                         ; with A as the caller left it.
    LD   A,(HL)                    ; A byte remains: fetch it without advancing.
    OR   A                         ; Clear carry; zero marks a NUL byte.
    RET                            ; Return the byte.

;@ROUTINE OUT A,CARRY,ZERO CLOBBERS SIGN,PARITY,HALFCARRY,DE,HL
; Consume one byte, returning it as SRC_PEEK does, and advance the byte
; offset and column. Line breaks are counted separately by SRC_EOL because
; LF and CRLF each end one logical line. BC is preserved.

SRC_TAKE:
    CALL SRC_PEEK                  ; Fetch the byte or detect the end; HL is the pointer.
    RET  C                         ; Nothing to consume at the end of a part.
    INC  HL                        ; Consume the byte; A and the flags are kept.
    LD   (SRC_PTR),HL              ; Publish the advanced pointer.
    LD   HL,(SRC_POS)              ; Fetch the part offset.
    INC  HL                        ; One more byte has been consumed.
    LD   (SRC_POS),HL              ; Publish the advanced offset.
    LD   HL,(SRC_COL)              ; Fetch the column.
    INC  HL                        ; Columns count bytes, not characters.
    LD   (SRC_COL),HL              ; Publish the advanced column.
    RET                            ; A and the flags are SRC_PEEK's.

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
