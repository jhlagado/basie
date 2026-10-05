;==========================================================================
;  Symbol table
;==========================================================================
;
;  Hold the program's ordinary names: constants, program variables, locals
;  and parameters, scalar and aggregate. Routine names live in the routine
;  table (ROUTINES.ASM) and record fields in the aggregate field table
;  (AGGR.ASM); declarations check all three for collisions. The table is a
;  bounded array searched linearly by exact spelling, with no hashing and
;  no scopes, and it lives for the whole compilation.
;
;  Principal entries:
;    SY_FIND   find the current NAME token among the committed symbols
;    SY_NEW    write a provisional record for the current NAME token
;    SY_TAG    record an aggregate type for the provisional symbol, commit it
;    SY_CMT    commit the provisional symbol
;    SY_GET    return the current NAME's class/type and payload, or fail
;
;  A record is six bytes (SY_RECB), and the table holds sixteen (SY_CAP):
;
;    +0  word  address of the name's spelling in the resident source
;    +2  byte  length of the spelling
;    +3  byte  class and type: SY_TMASK type, SY_CMASK storage class,
;              SY_TYPE for a type name, SY_AGGR for an aggregate; an
;              aggregate constant keeps its bank in bits 4..5 (TG_BMASK)
;    +4  word  payload: a constant's value or a variable's storage offset
;
;  The source stays resident through compilation, so a record points at the
;  spelling instead of copying it. A declaration is written in two steps:
;  SY_NEW fills the record at index SY_CNT, which SY_FIND does not see, and
;  SY_CMT (or SY_TAG) makes it visible only once the declaration's
;  initializer has been accepted. A failed declaration therefore never
;  leaves a half-made symbol behind. AG_SYTAB, parallel to the table, holds
;  each symbol's aggregate type ordinal.

;@ROUTINE OUT CARRY,HL CLOBBERS SIGN,PARITY,HALFCARRY,ZERO,A,C,DE
; Compare the current NAME token with each committed record. Carry returns
; the matching record in HL; carry clear means the name is not an ordinary
; symbol. The provisional record at SY_CNT is not searched. B is preserved.

SY_FIND:
    LD   A,(SY_CNT)                ; Fetch the number of committed records.
    OR   A                         ; An empty table matches nothing.
    RET  Z                         ; Return carry clear from the OR.
    LD   C,A                       ; C counts the records left to compare.
    LD   HL,SY_BASE                ; Begin with the first record.
.LOOP:                         ; Compare one record per iteration.
    CALL TK_SAME                   ; Does its spelling equal the token's?
    RET  C                         ; Return the matching record in HL.
    LD   DE,SY_RECB                ; Fetch the record stride.
    ADD  HL,DE                     ; Step to the next record.
    DEC  C                         ; One fewer record to compare.
    JR   NZ,.LOOP                  ; Continue through the committed prefix.
    OR   A                         ; Report no match with carry clear.
    RET                            ; Return to the declaration or lookup.

;@ROUTINE IN D,BC OUT A,CARRY,HL CLOBBERS SIGN,PARITY,HALFCARRY,ZERO
; Write a provisional record for the current NAME token with class/type D
; and payload word BC. A duplicate name raises DG_DUP and a full table
; DG_SYMS; neither returns. The record stays invisible until SY_CMT.

SY_NEW:
    PUSH BC                        ; Keep the payload across the lookup.
    PUSH DE                        ; Keep the class/type across it too.
    CALL SY_FIND                   ; Is the name already an ordinary symbol?
    POP  DE                        ; Restore the class/type in D.
    POP  BC                        ; Restore the payload.
    JP   C,EX_EDUP                 ; A second declaration is a duplicate.
    LD   A,(SY_CNT)                ; The provisional slot follows the committed.
    CP   SY_CAP                    ; Is there a free slot for it?
    JR   NC,.FULL                  ; No: the table is full.
    PUSH BC                        ; Keep the payload; BC serves the index.
    LD   C,A                       ; Index the provisional slot.
    LD   B,0                       ; Widen the index to a word.
    LD   H,0                       ; Begin the offset from the index too.
    LD   L,C                       ; HL = index.
    ADD  HL,HL                     ; HL = index times two.
    ADD  HL,HL                     ; HL = index times four.
    ADD  HL,BC                     ; HL = index times five.
    ADD  HL,BC                     ; HL = index times six, the record offset.
    LD   BC,SY_BASE                ; Fetch the table base.
    ADD  HL,BC                     ; Address the provisional record.
    CALL TK_KEEP                   ; Record the spelling; HL at the length.
    INC  HL                        ; Step to the class/type byte.
    LD   (HL),D                    ; Record the class and type.
    INC  HL                        ; Step to the payload word.
    POP  BC                        ; Restore the payload.
    LD   (HL),C                    ; Record its low byte.
    INC  HL                        ; Step to the high byte.
    LD   (HL),B                    ; Record its high byte.
    OR   A                         ; Report success with carry clear.
    RET                            ; The record awaits SY_CMT.
.FULL:                         ; Every slot is in use.
    LD   A,DG_SYMS                 ; Diagnostic: too many symbols.
    JR   DG_ISSUE                  ; Report it; no return.

;@ROUTINE IN A OUT A,CARRY,ZERO CLOBBERS SIGN,PARITY,HALFCARRY,DE,HL
; Record A as the aggregate type ordinal of the provisional symbol, then
; commit the symbol through SY_CMT. BC, the caller's prepared payload, is
; preserved.

SY_TAG:
    PUSH AF                        ; Keep the type ordinal while indexing.
    LD   A,(SY_CNT)                ; The provisional symbol's index.
    LD   E,A                       ; Widen it to a word in DE.
    LD   D,0                       ; Clear the high byte.
    LD   HL,AG_SYTAB               ; The table parallel to the symbols.
    ADD  HL,DE                     ; Address this symbol's type entry.
    POP  AF                        ; Restore the type ordinal.
    LD   (HL),A                    ; Record it, then commit below.

;@ROUTINE OUT A,CARRY,ZERO CLOBBERS SIGN,PARITY,HALFCARRY,HL
; Commit the provisional symbol so that SY_FIND sees it. Returns A zero
; with carry clear.

SY_CMT:
    LD   HL,SY_CNT                 ; Address the committed count.
    INC  (HL)                      ; The provisional record joins the table.
    XOR  A                         ; Report success with carry clear.
    RET                            ; Return to the declaration.

;@ROUTINE OUT A,BC,CARRY,ZERO,HL CLOBBERS SIGN,PARITY,HALFCARRY,DE
; Return the current NAME's class/type in A and payload word in BC, with
; carry clear; HL is left at the record's last byte. An unknown name raises
; DG_UNDEF and does not return.

SY_GET:
    CALL SY_FIND                   ; Look the name up among committed symbols.
    JR   NC,SY_UNDEF               ; An unknown name is undefined.
    INC  HL                        ; Skip the spelling's address low byte.
    INC  HL                        ; Skip its high byte.
    INC  HL                        ; Skip the length; HL at the class/type.
    LD   A,(HL)                    ; Return the class and type.
    INC  HL                        ; Step to the payload word.
    LD   C,(HL)                    ; Fetch the payload's low byte.
    INC  HL                        ; Step to its high byte.
    LD   B,(HL)                    ; BC now holds the payload.
    OR   A                         ; Clear carry for success.
    RET                            ; Return class/type and payload.

; Report the current NAME as undefined. This is the last line of the file:
; it falls into DG_ISSUE, the first routine of PARSER.ASM, so the include
; order in BASIE.ASM must keep PARSER.ASM next.

SY_UNDEF:
    LD   A,DG_UNDEF                ; Diagnostic: undefined name; DG_ISSUE follows.
