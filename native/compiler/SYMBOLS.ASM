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
;  A record is seven bytes (SY_RECB), and the table holds SY_CAP (96):
;
;    +0  word  address of the name's spelling in the resident source
;    +2  byte  length of the spelling
;    +3  byte  class and type: SY_TMASK type, SY_CMASK storage class,
;              SY_TYPE for a type name, SY_AGGR for an aggregate
;    +4  word  payload: a constant's value, the blob ordinal of a program
;              variable or aggregate constant, a local's or parameter's
;              offset from IX (negative for a local)
;    +6  byte  an aggregate's type ordinal (SY_TAG)
;
;  The source stays resident through compilation, so a record points at the
;  spelling instead of copying it. A declaration is written in two steps:
;  SY_NEW fills the record at index SY_CNT, which SY_FIND does not see, and
;  SY_CMT (or SY_TAG) makes it visible only once the declaration's
;  initializer has been accepted. A failed declaration therefore never
;  leaves a half-made symbol behind.

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

;@ROUTINE IN A OUT HL CLOBBERS CARRY,ZERO,SIGN,PARITY,HALFCARRY
; Address record A in HL: SY_BASE plus seven times A. A, BC and DE are
; kept.

SY_AT:
    PUSH DE                        ; Keep the caller's DE.
    LD   L,A                       ; HL is the index
    LD   H,0                       ; as a word,
    LD   D,H                       ; and so
    LD   E,L                       ; is DE.
    ADD  HL,HL                     ; Times two,
    ADD  HL,HL                     ; four,
    ADD  HL,HL                     ; eight; carry is clear.
    SBC  HL,DE                     ; Less one: times seven, the record size.
    LD   DE,SY_BASE                ; The table's base
    ADD  HL,DE                     ; plus the offset.
    POP  DE                        ; Restore DE.
    RET                            ; HL is the record.

;@ROUTINE IN D,BC OUT A,CARRY,HL CLOBBERS SIGN,PARITY,HALFCARRY,ZERO
; Write a provisional record for the current NAME token with class/type D
; and payload word BC. A name already a symbol raises DG_DUP, or DG_HIDE
; when a local or parameter would hide a symbol of another class (the
; reference's scopes: a local hides a parameter or a program-wide name),
; and a full table raises DG_SYMS; none returns. The record stays
; invisible until SY_CMT.

SY_NEW:
    PUSH BC                        ; Keep the payload across the lookup.
    PUSH DE                        ; Keep the class/type across it too.
    CALL SY_FIND                   ; Is the name already an ordinary symbol?
    POP  DE                        ; Restore the class/type in D.
    POP  BC                        ; Restore the payload.
    JR   C,.TAKEN                  ; Then it is a duplicate or hidden.
    LD   A,(SY_CNT)                ; The provisional slot follows the committed.
    CP   SY_CAP                    ; Is there a free slot for it?
    JR   NC,.FULL                  ; No: the table is full.
    CALL SY_AT                     ; HL addresses the provisional record.
    PUSH BC                        ; TK_KEEP takes BC for the spelling.
    CALL TK_KEEP                   ; Record the spelling; HL at the length.
    POP  BC                        ; Restore the payload.
    INC  HL                        ; Step to the class/type byte.
    LD   (HL),D                    ; Record the class and type.
    INC  HL                        ; Step to the payload word.
    LD   (HL),C                    ; Record its low byte.
    INC  HL                        ; Step to the high byte.
    LD   (HL),B                    ; Record its high byte.
    OR   A                         ; Report success with carry clear.
    RET                            ; The record awaits SY_CMT.
.FULL:                         ; Every slot is in use.
    LD   A,DG_SYMS                 ; Diagnostic: too many symbols.
    JR   DG_ISSUE                  ; Report it; no return.
.TAKEN:                        ; HL is the symbol of that name.
    INC  HL                        ; Its class
    INC  HL                        ; and type
    INC  HL                        ; follow the name.
    LD   A,(HL)                    ; Of the same class
    XOR  D                         ; as the new one,
    AND  SY_CMASK                  ; it is
    LD   A,DG_DUP                  ; a duplicate;
    JR   Z,.NAMED                  ; so is any
    LD   A,D                       ; program-wide
    AND  SY_CMASK                  ; name's,
    CP   SY_LOCAL                  ; but a local's or parameter's
    LD   A,DG_HIDE                 ; would hide
    JR   NC,.NAMED                 ; another's,
    LD   A,DG_DUP                  ; a duplicate otherwise.
.NAMED:                        ; A is the diagnostic.
    JR   DG_NAMED                  ; Name it; no return.

;@ROUTINE IN A OUT A,CARRY,ZERO CLOBBERS SIGN,PARITY,HALFCARRY,DE,HL
; Record A as the aggregate type ordinal of the provisional symbol, then
; commit the symbol through SY_CMT. BC, the caller's prepared payload, is
; preserved.

SY_TAG:
    LD   E,A                       ; Keep the type ordinal.
    LD   A,(SY_CNT)                ; The provisional symbol's index.
    CALL SY_AT                     ; HL addresses its record.
    LD   A,E                       ; The type ordinal
    LD   DE,SY_AGT                 ; goes in the record's last byte.
    ADD  HL,DE                     ; HL addresses it.
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
; carry clear; HL is left at the payload's high byte. An unknown name raises
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

; Report the current NAME as undefined, naming it. This is the last line
; of the file: it falls into DG_NAMED, the first routine of PARSER.ASM, so
; the include order in BASIE.ASM must keep PARSER.ASM next.

SY_UNDEF:
    LD   A,DG_UNDEF                ; Diagnostic: undefined name; DG_NAMED follows.
