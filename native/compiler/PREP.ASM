;==========================================================================
;  Preparing a compilation
;==========================================================================
;
;  The PREP overlay (OVERLAY.ASM): the state a compilation begins with,
;  made once, after the start-up has loaded the parts and opened the
;  streams and before NAMES takes the overlay area for the parse. It runs
;  inside PR_BUILD (ROUTINES.ASM), whose saved SP a diagnostic returns to,
;  so the memory's check may raise DG_ROOM here as anywhere in the parse.
;
;  Principal entries:
;    PP_RUN    clear the parse state and place the tables, at OV_AREA

;@ROUTINE CLOBBERS A,BC,DE,HL,CARRY,ZERO,SIGN,PARITY,HALFCARRY
; Clear the state one compilation accumulates: the diagnostic, the
; lookahead, the symbol table's chains, the forward flag, the aggregate
; counters, the next ordinal (the program's base, $0400) and the largest
; frame. Then place the tables, owing no line end: the name heap starts
; below the part table, the symbol table above the largest part in whole
; records, where each part is loaded (SY_BTM), and no constant waits above
; that (RG_CBEG, RG_PEND); DG_ROOM if they meet. Last, clear the pools'
; table, the owner descriptors' ordinals and the routine state; the tables
; are written before they are read.

PP_RUN:                        ; At OV_AREA.
    XOR  A                         ; Zero for every cleared field.
    LD   H,A                       ; HL is zero
    LD   L,A                       ; for the word fields.
    LD   (DG_CODE),HL              ; No diagnostic yet, and no failing part (DG_PART).
    LD   (RG_LARGE),HL             ; No frame yet: the largest is zero.
    LD   (SY_BODY),HL              ; No body is open.
    LD   (RG_FWD),A                ; No forward routines.
    LD   (EX_PRIME),A              ; No primary parsed ahead.
    LD   HL,$0400                  ; The first blob takes the
    LD   (RG_ORD),HL               ; program's ordinal base, $0400.
    LD   HL,SY_HTAB                ; No chain
    LD   B,2*SY_HCAP               ; has a record:
    CALL .WIPE                     ; each head is zero.
    LD   HL,AG_DCNT                ; The aggregate counters,
    LD   B,AG_OPENF-AG_DCNT+1      ; AG_DCNT..AG_OPENF,
    CALL .WIPE                     ; zeroed.
    DEC  A                         ; The empty-lookahead marker, $FF:
    LD   (PR_LKIND),A              ; no token is buffered.
    LD   A,(SRC_PCNT)              ; The part table's
    DEC  A                         ; last entry,
    CALL SRC_PART                  ; its bottom,
    LD   (NH_PTR),HL               ; begins the name heap (TK_KEEP).
    LD   BC,0                      ; The largest part's length, BC,
    LD   A,(SRC_PCNT)              ; of every part:
.LARGE:                        ; A entries remain.
    DEC  A                         ; Entry A,
    PUSH AF                        ; (kept)
    CALL SRC_PART                  ; HL; BC is kept:
    LD   DE,PT_START               ; its
    ADD  HL,DE                     ; start,
    CALL WD_GET                    ; DE, and its end,
    LD   A,(HL)                    ; HL,
    INC  HL                        ; give
    LD   H,(HL)                    ; its
    LD   L,A                       ; length,
    OR   A                         ; HL;
    SBC  HL,DE                     ; is it
    PUSH HL                        ; longer
    SBC  HL,BC                     ; than
    POP  HL                        ; BC?
    JR   C,.SHORT                  ; No.
    LD   B,H                       ; Then it is
    LD   C,L                       ; the longest yet.
.SHORT:                        ; The next.
    POP  AF                        ; Until
    JR   NZ,.LARGE                 ; entry zero.
    LD   HL,127                    ; Its whole
    ADD  HL,BC                     ; records'
    LD   A,L                       ; bytes
    AND  $80                       ; above
    LD   L,A                       ; the
    LD   DE,MM_SRC                 ; base
    ADD  HL,DE                     ; are where
    LD   (SY_BTM),HL               ; the symbol table
    LD   (SY_TOP),HL               ; begins;
    LD   DE,SY_RECB                ; past its
    ADD  HL,DE                     ; provisional record
    LD   (RG_CBEG),HL              ; no constant
    LD   (RG_PEND),HL              ; waits,
    EX   DE,HL                     ; all below
    LD   HL,(NH_PTR)               ; the name
    OR   A                         ; heap,
    SBC  HL,DE                     ; else
    JR   NC,.FITS                  ; DG_ROOM,
    XOR  A                         ; naming
    LD   (SRC_ID),A                ; no part:
    JP   MM_FULL                   ; the memory is full.
.FITS:                         ; The tables are ready.
    XOR  A                         ; No boundary line end
    LD   (SRC_OWE),A               ; is owed.
    LD   HL,PL_CNT                 ; Clear the pools,
    LD   B,FW_TAB-PL_CNT           ; their table (a frame's flows are
                                   ; cleared as it opens, FW_OPEN),
    CALL .WIPE                     ; zeroed;
    LD   HL,PL_DESC                ; the owner descriptors'
    LD   B,2*AG_TCAP               ; ordinals,
    CALL .WIPE                     ; none yet;
    LD   HL,RO_BASE                ; and the routine state:
    LD   B,RO_SPAR-RO_BASE         ; its counts, fields, hash chains and
                                   ; record; fall into .WIPE and return.
.WIPE:                         ; Clear B bytes at HL; A is zero after.
    XOR  A                         ; zero
.ZERO:                         ; each
    LD   (HL),A                    ; byte
    INC  HL                        ; in
    DJNZ .ZERO                     ; turn.
    RET                            ; Done.
