;==========================================================================
;  Symbol table
;==========================================================================
;
;  Hold the program's ordinary names: constants, program variables, locals
;  and parameters, scalar and aggregate. Routine names live in the routine
;  table (ROUTINES.ASM) and record fields in the aggregate field table
;  (AGGR.ASM); declarations check all three for collisions. The table is
;  an array that lives for the whole compilation, searched through SY_HCAP
;  hash chains (SY_HTAB): a name's chain is the sum of its length and its
;  bytes, modulo SY_HCAP (SY_HASH), each chain links its records newest
;  first (SY_LINK), and a scope's end unlinks its records from the chains'
;  heads, where they are (SY_CUT). It starts above the largest part, in
;  whole records (SY_BTM, SRC_OPEN), and grows up as names are declared:
;  the routine's waiting constants above it move up a record when it
;  reaches them (RG_LIFT), and the name heap above them is the limit
;  (DG_ROOM, `source size`). Scopes are its prefixes: a routine's
;  parameters and locals follow the program's names, each block's follow
;  its enclosing block's, and a block's end cuts the table back to where
;  it began (CT_BLOCK, AC_END). A scope is marked by the address of its
;  first record (SY_GTOP, SY_BODY, a frame's CT_FSYMS), and SY_TOP is the
;  provisional record past the committed ones. No name may hide a visible
;  one (spec 5.6), so a lookup needs no scope order: the one visible
;  symbol of a name is the one found.
;
;  Principal entries:
;    SY_FIND   find the current NAME token among the committed symbols
;    SY_NEW    write a provisional record for the current NAME token
;    SY_TAG    record an aggregate type for the provisional symbol, commit it
;    SY_CMT    commit the provisional symbol
;    SY_GET    return the current NAME's class/type and payload, or fail
;    SY_CUT    end a scope: its records leave the table and their chains
;
;  A record is twelve bytes (SY_RECB):
;
;    +0  word  address of the name's spelling in the name heap (TK_KEEP)
;    +2  byte  length of the spelling
;    +3  byte  class and type: SY_TMASK type, SY_CMASK storage class,
;              SY_TYPE for a type name, SY_AGGR for an aggregate
;    +4  word  payload: a constant's value, the blob ordinal of a program
;              variable or aggregate constant, a local's or parameter's
;              offset from IX (negative for a local)
;    +6  byte  an aggregate's type ordinal (SY_TAG); for a scalar constant,
;              +6..+8 are its value's three high bytes (SY_VHI), the
;              payload its low word
;    +9  byte  flags (SY_FLAGS): SY_FPRIV for a private declaration
;    +10 word  the next older record in its hash chain, zero for none
;              (SY_LINK)
;
;  A declaration is written in two steps:
;  SY_NEW fills the record at SY_TOP, which SY_FIND does not see, and
;  SY_CMT (or SY_TAG) makes it visible only once the declaration's
;  initializer has been accepted. A failed declaration therefore never
;  leaves a half-made symbol behind.

;@ROUTINE IN HL OUT CARRY CLOBBERS A,B,DE,HL,ZERO,SIGN,PARITY,HALFCARRY
; Carry if the symbol record HL is in the current block: at top level the
; program's names are one block (the reference's program and part scopes),
; in a body the block of the innermost control frame (CT_FSYMS) or else
; the body's own (SY_BODY). A parameter is in neither of a body's blocks.

SY_HERE:                       ; HL is a record found.
    LD   DE,(SY_BODY)              ; The body's first record,
    LD   A,D                       ; zero
    OR   E                         ; outside a body,
    SCF                            ; where every name
    RET  Z                         ; is the block's.
    LD   A,(CT_DEPTH)              ; Unless a control frame
    OR   A                         ; is open,
    JR   Z,.BASE                   ; the body's block's;
    PUSH HL                        ; else the
    LD   B,CT_FSYMS                ; innermost frame's
    CALL CT_FWORD                  ; first record,
    EX   DE,HL                     ; DE,
    POP  HL                        ; kept then.
.BASE:                         ; DE is the block's first record.
    OR   A                         ; Clear carry.
    SBC  HL,DE                     ; No borrow if it is the block's:
    CCF                            ; carry then.
    RET                            ; Carry if in the block.

;@ROUTINE IN A,HL OUT A,HL CLOBBERS CARRY,ZERO,SIGN,PARITY,HALFCARRY
; Address in HL the byte of the bit table at HL that holds bit A, and
; return the bit's mask in A. BC and DE are kept.

SY_BITAT:                      ; A is the bit's index, HL the table.
    PUSH BC                        ; Keep BC
    PUSH DE                        ; and DE.
    LD   C,A                       ; Keep the index.
    AND  7                         ; Its bit
    LD   B,A                       ; in the byte,
    INC  B                         ; plus one,
    LD   A,$80                     ; rotations of bit 7
.SHIFT:                        ; B rotations remain.
    RLCA                           ; to
    DJNZ .SHIFT                    ; bit B.
    LD   B,A                       ; B is the mask.
    LD   A,C                       ; The index
    RRCA                           ; over
    RRCA                           ; eight
    RRCA                           ; is
    AND  $1F                       ; the byte's,
    LD   E,A                       ; DE
    LD   D,0                       ; from
    ADD  HL,DE                     ; the table's start.
    LD   A,B                       ; A is the mask.
    POP  DE                        ; Restore DE
    POP  BC                        ; and BC.
    RET                            ; HL and A locate the bit.

;@ROUTINE OUT CARRY,HL CLOBBERS SIGN,PARITY,HALFCARRY,ZERO,A,C,DE
; Compare the current NAME token with the committed records of its hash
; chain, newest first. Carry returns the matching record in HL; carry
; clear means the name is not an ordinary symbol. The provisional record
; at SY_TOP is in no chain. B is preserved.

SY_FIND:
    PUSH BC                        ; Keep B.
    LD   HL,(TK_PTR)               ; The token's
    LD   A,(TK_LEN)                ; spelling
    LD   B,A                       ; and length:
    CALL SY_HASH                   ; its chain's head.
    POP  BC                        ; B again.
.LOOP:                         ; HL addresses a link: the next record.
    LD   A,(HL)                    ; The
    INC  HL                        ; record,
    LD   H,(HL)                    ; or
    LD   L,A                       ; zero:
    OR   H                         ; none left,
    RET  Z                         ; carry clear (OR).
    CALL TK_SAME                   ; Does its spelling equal the token's?
    RET  C                         ; Return the matching record in HL.
    LD   DE,SY_LINK                ; Its link
    ADD  HL,DE                     ; to the next.
    JR   .LOOP                     ; Continue along the chain.

;@ROUTINE IN B,HL OUT HL CLOBBERS A,B,DE,CARRY,ZERO,SIGN,PARITY,HALFCARRY
; Address in HL the head of the hash chain of the spelling of B bytes, at
; least one, at HL: their sum with B, modulo SY_HCAP, in SY_HTAB, or in
; the table at DE (SY_HASHD: the routines', RO_HTAB). C is kept.

SY_HASH:                       ; HL the spelling, B its length.
    LD   DE,SY_HTAB                ; The symbols' chains.
SY_HASHD:                      ; DE is the table.
    LD   A,B                       ; The length,
.SUM:                          ; plus
    ADD  A,(HL)                    ; each
    INC  HL                        ; byte,
    DJNZ .SUM                      ; modulo
    AND  SY_HCAP-1                 ; SY_HCAP,
    ADD  A,A                       ; is the
    LD   L,A                       ; chain:
    LD   H,0                       ; its head's
    ADD  HL,DE                     ; address, HL.
    RET                            ; Done.

;@ROUTINE IN HL CLOBBERS A,DE,HL,CARRY,ZERO,SIGN,PARITY,HALFCARRY
; End a scope: the records from HL on leave the table (SY_TOP becomes HL)
; and their chains, at whose heads they are, being newer than every
; record before HL. BC is kept.

SY_CUT:                        ; HL is the scope's first record.
    LD   (SY_TOP),HL               ; The table ends there.
    PUSH BC                        ; Keep BC.
    EX   DE,HL                     ; DE is the mark.
    LD   HL,SY_HTAB                ; Each chain's
    LD   B,SY_HCAP                 ; head:
.HEAD:                         ; HL addresses it.
    LD   C,(HL)                    ; Its record,
    INC  HL                        ; A and C,
    LD   A,(HL)                    ; (zero
    DEC  HL                        ; for none)
    PUSH HL                        ; (the head kept)
    LD   H,A                       ; below
    LD   L,C                       ; the
    CALL CP_HLDE                   ; mark, stays, and so
    JR   C,.KEEP                   ; does the chain.
    PUSH DE                        ; (the mark)
    LD   DE,SY_LINK                ; Otherwise
    ADD  HL,DE                     ; the record's
    LD   C,(HL)                    ; next
    INC  HL                        ; is
    LD   A,(HL)                    ; the head:
    POP  DE                        ; (the mark)
    POP  HL                        ; (the head)
    LD   (HL),C                    ; both
    INC  HL                        ; of its
    LD   (HL),A                    ; bytes;
    DEC  HL                        ; then the same
    JR   .HEAD                     ; head again.
.KEEP:                         ; The chain is in scope.
    POP  HL                        ; The head,
    INC  HL                        ; and
    INC  HL                        ; the next
    DJNZ .HEAD                     ; chain's.
    POP  BC                        ; BC again.
    RET                            ; The scope has ended.

;@ROUTINE IN D,BC OUT A,CARRY,HL CLOBBERS SIGN,PARITY,HALFCARRY,ZERO
; Write a provisional record for the current NAME token with class/type D
; and payload word BC. A name already a symbol raises DG_DUP when that
; symbol is in the current block (SY_HERE), or DG_HIDE when the new one
; would hide it; neither returns. The
; record stays invisible until SY_CMT.

SY_NEW:
    PUSH BC                        ; Keep the payload across the lookup.
    PUSH DE                        ; Keep the class/type across it too.
    CALL SY_FIND                   ; Is the name already an ordinary symbol?
    POP  DE                        ; Restore the class/type in D.
    POP  BC                        ; Restore the payload.
    JR   C,.TAKEN                  ; Then it is a duplicate or hidden.
    LD   HL,(SY_TOP)               ; The provisional record, below the
    PUSH BC                        ; waiting constants (SY_CMT); TK_KEEP
                                   ; takes BC for the spelling.
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
.TAKEN:                        ; HL is the symbol of that name.
    CALL SY_HERE                   ; Is it in the current block?
    LD   A,DG_DUP                  ; Then the new one repeats it;
    JR   C,.NAMED                  ; otherwise it
    LD   A,DG_HIDE                 ; would hide it.
.NAMED:                        ; A is the diagnostic.
    JR   DG_NAMED                  ; Name it; no return.

;@ROUTINE IN A OUT A,CARRY,ZERO CLOBBERS SIGN,PARITY,HALFCARRY,DE,HL
; Record A as the aggregate type ordinal of the provisional symbol, then
; commit the symbol through SY_CMT. BC, the caller's prepared payload, is
; preserved.

SY_TAG:
    LD   E,A                       ; Keep the type ordinal.
    LD   HL,(SY_TOP)               ; HL addresses the provisional record.
    LD   A,E                       ; The type ordinal
    LD   DE,SY_AGT                 ; goes in the record's last byte.
    ADD  HL,DE                     ; HL addresses it.
    LD   (HL),A                    ; Record it, then commit below.

;@ROUTINE OUT A,CARRY,ZERO CLOBBERS SIGN,PARITY,HALFCARRY,HL
; Commit the provisional symbol to its hash chain so that SY_FIND sees
; it; a private
; declaration's (AC_PRIV) is marked SY_FPRIV, to be hidden when its part
; ends (AC_ENDP). The next provisional record must end at or below the
; routine's waiting constants, which otherwise move up a record (RG_LIFT,
; DG_ROOM beyond). Returns A zero with carry clear. BC and DE are kept.

SY_CMT:
    PUSH BC                        ; Keep BC
    PUSH DE                        ; and DE.
    LD   HL,(SY_TOP)               ; The provisional record's
    LD   DE,SY_FLAGS               ; flags:
    ADD  HL,DE                     ; is the
    LD   A,(AC_PRIV)               ; declaration
    OR   A                         ; private?
    JR   Z,.FLAG                   ; Not:
    LD   A,SY_FPRIV                ; zero; else SY_FPRIV.
.FLAG:                         ; A is the flags.
    LD   (HL),A                    ; Recorded.
    LD   HL,(SY_TOP)               ; Its spelling
    PUSH HL                        ; (the record kept)
    CALL WD_GET                    ; its name's address, HL its length.
    LD   B,(HL)                    ; its
    EX   DE,HL                     ; hash
    CALL SY_HASH                   ; chain,
    POP  DE                        ; which the record
    LD   A,(HL)                    ; heads,
    LD   (HL),E                    ; linked
    INC  HL                        ; before
    LD   C,(HL)                    ; the
    LD   (HL),D                    ; old head,
    LD   HL,SY_LINK                ; A and C,
    ADD  HL,DE                     ; in its
    LD   (HL),A                    ; link.
    INC  HL                        ; The next
    LD   (HL),C                    ; record
    INC  HL                        ; is the
    LD   (SY_TOP),HL               ; provisional one;
SY_FIT:                        ; HL is SY_TOP; BC and DE are pushed.
    LD   DE,SY_RECB                ; its record
    ADD  HL,DE                     ; must end
    LD   DE,(RG_CBEG)              ; at or below
    OR   A                         ; the waiting
    SBC  HL,DE                     ; constants,
    JR   C,.ROOM                   ; which
    JR   Z,.ROOM                   ; otherwise
    CALL RG_LIFT                   ; move up.
.ROOM:                         ; The next record fits.
    POP  DE                        ; DE
    POP  BC                        ; and BC again.
    XOR  A                         ; Report success with carry clear.
    RET                            ; Return to the declaration.

;@ROUTINE OUT A,CARRY,ZERO CLOBBERS SIGN,PARITY,HALFCARRY,HL
; Keep the provisional record, which is no name (a record's field,
; AC_PLACE): in no chain, its flags zero, the next provisional, as SY_CMT
; makes it. Returns A zero with carry clear. BC and DE are kept.

SY_SKIP:                       ; The provisional record is complete.
    PUSH BC                        ; Keep BC
    PUSH DE                        ; and DE.
    LD   HL,(SY_TOP)               ; Its
    LD   DE,SY_FLAGS               ; flags
    ADD  HL,DE                     ; are
    LD   (HL),0                    ; zero;
    LD   DE,SY_RECB-SY_FLAGS       ; the next
    ADD  HL,DE                     ; record is
    LD   (SY_TOP),HL               ; provisional,
    JR   SY_FIT                    ; below the waiting constants.

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

