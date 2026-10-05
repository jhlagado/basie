;==========================================================================
;  Routine names, signatures and the compile entry
;==========================================================================
;
;  Keep the tables of routines and parameters that the grammar actions
;  (ACTIONS.ASM) fill as they parse routine declarations: look names up,
;  reject names already in use, enrol parameters and bind each one as a
;  symbol of the routine's frame. CALLS.ASM parses the calls, services and
;  aggregate paths that use these tables. Both write operations to the
;  semantic transcript, which GENCALL.ASM replays into code once parsing
;  is complete.
;
;  The module also holds the compile entry PR_BUILD, which runs the parse
;  and emit phases, and the bank helpers (TG_) of the forked placed target.
;  BASIE.COM's shell describes a single bank, so every bank check passes;
;  the helpers go with placed output at 65.4.
;
;  Principal entries:
;    PR_BUILD  compile the source parts for a target: parse, then emit
;    PR_PARSE  clear the routine workspace and parse the whole program
;    RO_FIND   find the current name among the routines, or main
;    RO_LIB    find the current name among the services and error constants
;    RO_FRESH  reject a routine name that is already in use
;    RO_VET    reject a parameter name that is already in use
;    RO_ENROL  append a parameter to the parameter table
;    RO_DISP   give a parameter's argument displacement in the frame
;    RO_BIND   make a parameter a symbol and write OP_BIND
;
;  The routine table (RO_RTAB) holds four routines of eight bytes:
;
;    +0  word  address of the name's spelling in the resident source
;    +2  byte  length of the spelling
;    +3  byte  index of the first parameter in RO_PTAB
;    +4  byte  parameter count
;    +5  byte  result type: zero, a scalar type or an aggregate type
;    +6  byte  label ordinal, RO_LBASE + index (main's body is RO_MDEST)
;    +7  byte  flags: RO_FFAIL, RO_FMAIN, RO_FOPEN (declared, body not
;              yet seen), and the bank in bits 4..5
;
;  The parameter table (RO_PTAB) holds sixteen parameters of four bytes:
;  the spelling's address and length, then the type, AG_VIEW for an open
;  string. A routine's parameters are consecutive entries.

;@ROUTINE IN A OUT A,HL,CARRY,ZERO CLOBBERS SIGN,PARITY,HALFCARRY,DE
; Return in HL the address of routine-table entry A. A is preserved.

RO_SUBAT:
    LD   L,A                       ; Form the routine index as a word.
    LD   H,0                       ; At most RO_RCAP entries.
    ADD  HL,HL                     ; Times two.
    ADD  HL,HL                     ; Times four.
    ADD  HL,HL                     ; Times eight, the entry size.
    LD   DE,RO_RTAB                ; The table's base.
    ADD  HL,DE                     ; HL addresses the entry.
    OR   A                         ; Return carry clear.
    RET                            ; A still holds the index.

;@ROUTINE IN A OUT A,HL,CARRY,ZERO CLOBBERS SIGN,PARITY,HALFCARRY,DE
; Return in HL the address of parameter-table entry A. A is preserved.

RO_PARAM:
    LD   L,A                       ; Form the parameter index as a word.
    LD   H,0                       ; At most RO_PCAP entries.
    ADD  HL,HL                     ; Times two.
    ADD  HL,HL                     ; Times four, the entry size.
    LD   DE,RO_PTAB                ; The table's base.
    ADD  HL,DE                     ; HL addresses the entry.
    OR   A                         ; Return carry clear.
    RET                            ; A still holds the index.

;@ROUTINE OUT A,CARRY,ZERO CLOBBERS SIGN,PARITY,HALFCARRY,BC,DE,HL
; Find the current NAME among the routines. Z returns the table index in
; A, or RO_MAIN once main has been declared and the name is main. NZ, with
; A = $FF, means the name is not a routine; that is not itself an error.

RO_FIND:
    LD   A,(RO_RCNT)               ; Count the routines in the table.
    OR   A                         ; Is the table empty?
    JR   Z,.MISSING                ; Then only main can match.
    LD   C,A                       ; C counts the entries left.
    LD   B,0                       ; B is the index being compared.
.LOOP:                         ; Compare one routine's name.
    LD   A,B                       ; Select entry B.
    CALL RO_SUBAT                  ; HL addresses it; the name comes first.
    CALL TK_SAME                   ; Does its spelling match the token?
    JR   C,.FOUND                  ; Return its index.
    INC  B                         ; Try the next entry.
    DEC  C                         ; One entry fewer.
    JR   NZ,.LOOP                  ; Continue through the table.
.MISSING:                      ; The name is not in the table.
    LD   A,(RO_MFLAG)              ; Has main been declared?
    AND  RO_FMAIN                  ; Its flags carry RO_FMAIN once it has.
    JR   Z,.ABSENT                 ; No main to call yet.
    CALL EX_MAIN                   ; Is the name main?
    JR   NC,.ABSENT                ; It is no routine at all.
    LD   A,RO_MAIN                 ; Report the main routine.
    CP   A                         ; Set Z with carry clear.
    RET                            ; A identifies main.
.ABSENT:                       ; Report that no routine matched.
    LD   A,$FF                     ; No routine index.
    OR   A                         ; NZ with carry clear.
    RET                            ; The caller tries other kinds of name.
.FOUND:                        ; Report the matching routine.
    LD   A,B                       ; Its table index.
    CP   A                         ; Set Z with carry clear.
    RET                            ; A identifies the routine.

;@ROUTINE OUT A,CARRY,ZERO CLOBBERS SIGN,PARITY,HALFCARRY,BC,DE,HL
; Find the current NAME in KW_NAMES. Carry returns its ordinal in A:
; 0..5 a service, RO_ERRS..9 an error constant. Carry clear means neither.

RO_LIB:
    LD   HL,KW_NAMES               ; Entries are a length byte and spelling.
    LD   C,KW_NCNT                 ; C counts the entries left.
.LOOP:                         ; Compare one entry.
    LD   B,(HL)                    ; Read the entry's length.
    INC  HL                        ; HL addresses its spelling.
    LD   A,(TK_LEN)                ; The token's length.
    CP   B                         ; Do the lengths agree?
    JR   NZ,.SKIP                  ; A different length cannot match.
    LD   DE,(TK_PTR)               ; DE walks the token's spelling.
.BYTELOOP:                     ; Compare one character.
    LD   A,(DE)                    ; Read the token's character.
    CP   (HL)                      ; Compare it with the entry's.
    JR   NZ,.SKIP                  ; HL + B is still the entry's end.
    INC  DE                        ; Advance in the token.
    INC  HL                        ; Advance in the entry.
    DJNZ .BYTELOOP                 ; Compare every character.
    LD   A,KW_NCNT                 ; The ordinal is the count of entries passed:
    SUB  C                         ; KW_NCNT less the entries left.
    SCF                            ; Report a match.
    RET                            ; A is the ordinal.
.SKIP:                         ; Step over the rest of this entry.
    LD   E,B                       ; The characters not yet passed.
    LD   D,0                       ; As a word.
    ADD  HL,DE                     ; HL addresses the next entry.
    DEC  C                         ; One entry fewer.
    JR   NZ,.LOOP                  ; Continue through the table.
    OR   A                         ; Report no match.
    RET                            ; Carry is clear.

;@ROUTINE IN A,HL,IX OUT CARRY CLOBBERS A,BC,DE,HL,IX,IY,SIGN,PARITY,HALFCARRY,ZERO
; Compile A source parts, described at HL, for the target described at IX:
; parse, then emit. Carry clear reports success. A diagnostic in either
; phase returns carry set, with DG_CODE, DG_PART and DG_POS describing it.

PR_BUILD:
    LD   (PR_SP),SP                ; A diagnostic returns from here.
    LD   (TG_DESC),IX              ; Keep the target descriptor.
    PUSH AF                        ; Keep the part count.
    PUSH HL                        ; Keep the part descriptors.
    CALL PR_RESET                  ; Clear the parser's state.
    POP  HL                        ; Recover the part descriptors.
    POP  AF                        ; Recover the part count.
    PUSH AF                        ; Keep the count across SRC_OPEN.
    CALL SRC_OPEN                  ; Open the first part.
    POP  BC                        ; B is the part count.
    LD   A,B                       ; A is the part count.
; Validate every bank-bearing descriptor field before source
; semantics can retain a bank ordinal. A is the bounded part count.
    LD   B,A                       ; B is already the count of parts to check.
    LD   IX,(TG_DESC)              ; Address the target descriptor.
    LD   A,(IX+TG_DBCNT)           ; Read its bank count.
    OR   A                         ; A target needs at least one bank.
    JR   Z,.BADCFG                 ; Reject zero banks.
    CP   TG_BCAP+1                 ; At most TG_BCAP banks are supported.
    JR   NC,.BADCFG                ; Reject more.
    LD   (TG_BCNT),A               ; Keep the bank count.
    LD   C,A                       ; C bounds the bank ordinals.
    LD   A,(IX+TG_DEB)             ; Read the entry bank.
    CP   C                         ; Is it one of the banks?
    JR   NC,.BADCFG                ; Reject an entry bank out of range.
    LD   (TG_EBANK),A              ; Keep the entry bank.
    LD   L,(IX+TG_DPART)           ; Address the parts' bank bytes, one per part.
    LD   H,(IX+TG_DPART+1)         ; High byte of their address.
.BANKLOOP:                     ; Check one part's bank.
    LD   A,(HL)                    ; Read the part's bank.
    CP   C                         ; Is it one of the banks?
    JR   NC,.BADCFG                ; Reject a bank out of range.
    INC  HL                        ; Next part.
    DJNZ .BANKLOOP                 ; Check every part.
    LD   HL,TG_ROTAB               ; Clear the per-bank constant lengths.
    LD   B,TG_ROLIM-TG_ROTAB       ; The table's size in bytes.
    XOR  A                         ; Zero each byte.
.WIPE:                         ; Clear one byte.
    LD   (HL),A                    ; Store zero.
    INC  HL                        ; Next byte.
    DJNZ .WIPE                     ; Clear the whole table.
    CALL PR_PARSE                  ; Parse every part into the transcript.
; A diagnostic during generation restores this synthetic frame and
; returns directly through the one target-output abort path. A
; successful generation returns normally and discards the frame.
    LD   HL,TG_ABORT               ; From here a diagnostic returns to TG_ABORT.
    PUSH HL                        ; TG_ABORT abandons the output, then returns.
    LD   (PR_SP),SP                ; DG_ISSUE restores this stack.
    CALL GA_BUILD                  ; Emit the program.
    POP  HL                        ; Discard the abort continuation.
    RET                            ; Return GA_BUILD's result.
.BADCFG:                       ; The descriptor names an impossible bank.
    JP   TG_DENY                   ; Raise DG_CFG.

;@ROUTINE OUT A,CARRY,ZERO CLOBBERS SIGN,PARITY,HALFCARRY,DE,HL,IX
; Return in A the bank of the source part being parsed, from the
; descriptor's part-bank array.

TG_HOME:
    LD   A,(SRC_LEFT)              ; Bits 3..5 hold the part's ordinal.
    AND  SRC_ORD                   ; Keep the ordinal.
    RRCA                           ; Shift the ordinal down one bit.
    RRCA                           ; And another.
    RRCA                           ; Bits 0..2 now hold it.
    LD   E,A                       ; Form it as a word.
    LD   D,0                       ; At most SRC_CAP parts.
    LD   IX,(TG_DESC)              ; Address the target descriptor.
    LD   L,(IX+TG_DPART)           ; Address the parts' bank bytes.
    LD   H,(IX+TG_DPART+1)         ; One byte per part.
    ADD  HL,DE                     ; HL addresses this part's byte.
    LD   A,(HL)                    ; Read its bank.
    OR   A                         ; Return carry clear.
    RET                            ; A is the bank.

;@ROUTINE IN A OUT A,CARRY,ZERO CLOBBERS SIGN,PARITY,HALFCARRY,B,DE,HL,IX
; Add the current part's bank, in bits 4..5, to flag byte A, whose low
; flag bits are kept.

TG_PACK:
    LD   B,A                       ; Keep the flags.
    CALL TG_HOME                   ; A is the current bank.
    RLCA                           ; Shift the bank up one bit.
    RLCA                           ; And another.
    RLCA                           ; And another.
    RLCA                           ; Bits 4..5, TG_BMASK, now hold it.
    OR   B                         ; Merge it with the flags.
    RET                            ; A is the packed flag byte.

;@ROUTINE IN A OUT A,CARRY,ZERO CLOBBERS SIGN,PARITY,HALFCARRY
; Extract the bank from bits 4..5 of flag byte A. Each rotate moves a zero
; bit into carry, so the result has carry clear.

TG_SPLIT:
    AND  TG_BMASK                  ; Keep the bank bits.
    RRCA                           ; Shift the bank down one bit.
    RRCA                           ; And another.
    RRCA                           ; And another.
    RRCA                           ; Bits 0..1 hold it, and carry is clear.
    RET                            ; A is the bank.

;@ROUTINE IN A OUT A,HL,CARRY,ZERO CLOBBERS SIGN,PARITY,HALFCARRY,DE
; Return in HL the address of bank A's aggregate-constant length word.

TG_LENAT:
    LD   L,A                       ; Form the bank as a word.
    LD   H,0                       ; At most TG_BCAP banks.
    ADD  HL,HL                     ; One word per bank.
    LD   DE,TG_ROTAB               ; The table's base.
    ADD  HL,DE                     ; HL addresses the bank's word.
    OR   A                         ; Return carry clear.
    RET                            ; A still holds the bank.

;@ROUTINE IN D OUT A,ZERO CLOBBERS SIGN,PARITY,HALFCARRY,CARRY,B,DE,HL,IX
; Compare the bank in bits 4..5 of flag byte D with the current part's
; bank: Z if they are the same.

TG_SAME:
    LD   B,D                       ; Keep the flags.
    CALL TG_HOME                   ; A is the current bank.
    RLCA                           ; Shift the bank up one bit.
    RLCA                           ; And another.
    RLCA                           ; And another.
    RLCA                           ; Bits 4..5 now line up with D's.
    XOR  B                         ; Differences show as set bits.
    AND  TG_BMASK                  ; Compare only the bank bits.
    RET                            ; Z if the banks agree.

;@ROUTINE IN D OUT A,ZERO CLOBBERS SIGN,PARITY,HALFCARRY,CARRY,B,DE,HL,IX
; Require the bank in flag byte D to be the current part's; otherwise raise
; DG_CFG, which does not return.

TG_MUST:
    CALL TG_SAME                   ; Are the banks the same?
    RET  Z                         ; Then the reference is reachable.
    JP   TG_DENY                   ; Raise DG_CFG.

;@ROUTINE OUT A,ZERO CLOBBERS SIGN,PARITY,HALFCARRY,CARRY,D,E,HL,IX
; Require the current part to be in the entry bank, as main must be;
; otherwise raise DG_CFG, which does not return.

TG_ENTRY:
    CALL TG_HOME                   ; A is the current bank.
    LD   D,A                       ; Keep it for the comparison.
    LD   A,(TG_EBANK)              ; The bank the program starts in.
    CP   D                         ; Is main's part there?
    RET  Z                         ; Then main is reachable at startup.
    JP   TG_DENY                   ; Raise DG_CFG.

;@ROUTINE IN A OUT A,CARRY,ZERO CLOBBERS SIGN,PARITY,HALFCARRY,BC,DE,HL,IX,IY
; Clear the routine workspace and the control labels, run the LL(1) parser
; over every source part and close the transcript. PR_BUILD calls this with
; A zero; AG_MODE, set to one here, is read nowhere.

PR_PARSE:
    INC  A                         ; One.
    LD   (AG_MODE),A               ; Nothing reads AG_MODE.
    LD   HL,RO_BASE                ; Clear the routine workspace.
    LD   B,RO_WEND-RO_BASE         ; Its tables, frames and fields are all bytes.
    XOR  A                         ; Zero each byte.
.WIPE:                         ; Clear one byte.
    LD   (HL),A                    ; Store zero.
    INC  HL                        ; Next byte.
    DJNZ .WIPE                     ; Clear the whole workspace.
    LD   (CT_LABNO),A              ; Number control labels from zero.
    CALL LL_PARSE                  ; Parse the program.
    JP   TR_CLOSE                  ; Publish the transcript and return.

;@ROUTINE OUT A,CARRY,ZERO CLOBBERS SIGN,PARITY,HALFCARRY,BC,DE,HL
; Reject a routine name that is an ordinary symbol, an earlier routine,
; main or a service or error constant: DG_DUP does not return. The current
; token is the name.

RO_FRESH:
    CALL SY_FIND                   ; Is it an ordinary symbol?
    JP   C,EX_EDUP                 ; Raise DG_DUP.
    CALL RO_FIND                   ; Is it a routine already?
    JP   Z,EX_EDUP                 ; Raise DG_DUP.
    CALL RO_LIB                    ; Is it a predefined name?
    JP   C,EX_EDUP                 ; Raise DG_DUP.
    OR   A                         ; Report success with carry clear.
    RET                            ; The name is free.

;@ROUTINE OUT A,CARRY,ZERO CLOBBERS SIGN,PARITY,HALFCARRY,BC,DE,HL
; Reject the current name if it repeats a parameter already in the
; signature being parsed (RO_CPCNT entries from RO_CPIDX).

RO_NODUP:
    LD   A,(RO_CPCNT)              ; Parameters so far in this signature.
    OR   A                         ; Are there any?
    RET  Z                         ; The first parameter repeats nothing.
    LD   C,A                       ; C counts the entries left.
    LD   A,(RO_CPIDX)              ; The signature's first parameter.
    LD   B,A                       ; B is the index being compared.
.LOOP:                         ; Compare one parameter's name.
    LD   A,B                       ; Select entry B.
    CALL RO_PARAM                  ; HL addresses it; the name comes first.
    CALL TK_SAME                   ; Does its spelling match the token?
    JP   C,EX_EDUP                 ; Raise DG_DUP.
    INC  B                         ; Next entry.
    DEC  C                         ; One entry fewer.
    JR   NZ,.LOOP                  ; Continue through the signature.
    OR   A                         ; Report success with carry clear.
    RET                            ; The name is new to the signature.

;@ROUTINE OUT A,CARRY,ZERO CLOBBERS SIGN,PARITY,HALFCARRY,BC,DE,HL
; Reject a parameter name that collides with an ordinary declaration, a
; routine, main, a predefined name, the routine whose signature is being
; parsed, or an earlier parameter of that signature.

RO_VET:
    CALL EX_FRESH                  ; Not a symbol and not main.
    CALL RO_FRESH                  ; Not a routine or a predefined name.
    LD   A,(RO_CUR)                ; The routine being declared is not counted yet.
    CALL RO_SUBAT                  ; So address its entry and compare it directly.
    LD   E,(HL)                    ; Read the address of its spelling.
    INC  HL                        ; High byte.
    LD   D,(HL)                    ; DE addresses the spelling.
    INC  HL                        ; Then its length.
    LD   A,(HL)                    ; Read the length.
    LD   B,A                       ; TK_MATCH takes it in B.
    EX   DE,HL                     ; And the spelling in HL.
    CALL TK_MATCH                  ; Is the parameter named as the routine?
    JP   C,EX_EDUP                 ; Raise DG_DUP.
    JR   RO_NODUP                  ; Check the earlier parameters.

;@ROUTINE IN A OUT A,CARRY,ZERO CLOBBERS SIGN,PARITY,HALFCARRY,BC,DE,HL
; Append the current NAME as a parameter of type A to the parameter table
; and the signature. A full table raises DG_PARAM, which does not return.

RO_ENROL:
    LD   (RO_OTYPE),A              ; Keep the type.
    LD   A,(RO_PCNT)               ; Parameters in the whole table.
    CP   RO_PCAP                   ; Is it full?
    JR   NC,.FULL                  ; Raise DG_PARAM.
    CALL RO_PARAM                  ; HL addresses the next free entry.
    CALL TK_KEEP                   ; Store the name; HL is at its length.
    INC  HL                        ; The type follows.
    LD   A,(RO_OTYPE)              ; Recover the type.
    LD   (HL),A                    ; Store it.
    LD   HL,RO_PCNT                ; Count the entry in the whole table.
    INC  (HL)                      ; One parameter more for all routines.
    LD   HL,RO_CPCNT               ; And in the current signature.
    INC  (HL)                      ; One parameter more.
    LD   A,(RO_OTYPE)              ; Return the type.
    OR   A                         ; With carry clear.
    RET                            ; The parameter is enrolled.
.FULL:                         ; No room for another parameter.
    CALL DG_RAISE                  ; Raise the diagnostic below.
    DB   DG_PARAM                  ; Too many parameters.

;@ROUTINE IN A,C OUT A,CARRY,ZERO CLOBBERS SIGN,PARITY,HALFCARRY,BC,DE,HL,IX,IY
; Make parameter A, whose argument is at displacement C, a symbol in the
; next frame slot, write OP_BIND (type, slot, displacement) so that the
; prologue copies the argument there, and advance SY_LSLOT past the slot.
; The current token is replaced by the parameter's name.

RO_BIND:
    LD   (RO_CPIDX),A              ; Keep the parameter's index.
    LD   A,C                       ; Keep the argument's displacement.
    LD   (RO_AIDX),A               ; OP_BIND carries it.
    LD   A,(RO_CPIDX)              ; Select the parameter's entry.
    CALL RO_PARAM                  ; HL addresses it.
    LD   E,(HL)                    ; Read the address of its spelling.
    INC  HL                        ; High byte.
    LD   D,(HL)                    ; DE addresses the spelling.
    INC  HL                        ; Then its length.
    LD   B,(HL)                    ; B is the length.
    INC  HL                        ; Then its type.
    LD   A,(HL)                    ; Read the type.
    LD   (RO_OTYPE),A              ; Keep it.
    LD   (TK_PTR),DE               ; SY_NEW names the symbol from the current token.
    LD   A,B                       ; So make the parameter's spelling the token.
    LD   (TK_LEN),A                ; And its length.
    LD   A,(SY_LSLOT)              ; The next free frame slot.
    LD   (RO_OPOS),A               ; OP_BIND carries it.
    LD   C,A                       ; The symbol's payload is the slot.
    LD   B,0                       ; As a word.
    LD   A,(RO_OTYPE)              ; Classify the parameter.
    CP   AG_FIRST                  ; Is it an aggregate?
    LD   D,SY_AGGR+SY_PARAM        ; An aggregate parameter's class.
    JR   NC,.SYMBOL                ; Use it.
.SCALAR:                       ; A scalar parameter's class.
    OR   SY_PARAM                  ; The type with the parameter class.
    LD   D,A                       ; The symbol's class byte.
.SYMBOL:                       ; Make the symbol.
    CALL SY_NEW                    ; Write the record.
    LD   A,(RO_OTYPE)              ; Record the symbol's aggregate type.
    CALL SY_TAG                    ; SY_TAG also commits the symbol.
    LD   A,(RO_OTYPE)              ; OP_BIND's first operand is the type.
    LD   C,A                       ; PR_EMITC writes C after the operation.
    LD   A,OP_BIND                 ; Copy an argument into the frame.
    CALL PR_EMITC                  ; Write OP_BIND and the type.
    LD   A,(RO_OPOS)               ; The slot.
    CALL TR_PUT                    ; Write it.
    LD   A,(RO_AIDX)               ; The argument's displacement.
    CALL TR_PUT                    ; Write it.
    LD   A,(RO_OTYPE)              ; How many slot bytes does it take?
    CP   AG_FIRST                  ; Is it an aggregate?
    JR   C,.SIZE                   ; A scalar takes its width.
    CP   AG_VIEW                   ; An open string takes three bytes.
    LD   A,3                       ; Its address and capacity: three.
    SBC  A,0                       ; Other aggregates take two: carry gives 3 - 1.
    JR   .ADVANCE                  ; Advance the slot.
.SIZE:                         ; A scalar's width.
    CALL EX_WIDTH                  ; One or two bytes.
.ADVANCE:                      ; Move SY_LSLOT past the slot.
    LD   HL,SY_LSLOT               ; The next free slot.
    ADD  A,(HL)                    ; Add the parameter's size.
    LD   (HL),A                    ; Store it.
    OR   A                         ; Return carry clear.
    RET                            ; The parameter is bound.

;@ROUTINE IN B,D OUT A,C,CARRY,ZERO CLOBBERS SIGN,PARITY,HALFCARRY,HL
; Return in A and C the IX displacement of parameter D's argument, where B
; counts the parameters from D to the last. The last argument is at IX+4;
; each later parameter adds a word, and an open string its capacity word
; too. B, D and E are preserved.

RO_DISP:
    PUSH BC                        ; Keep the count.
    PUSH DE                        ; Keep the parameter index.
    LD   A,B                       ; Parameters from this one to the last.
    ADD  A,A                       ; One argument word per remaining parameter.
    ADD  A,2                       ; Plus two words of saved IX and return address.
    LD   C,A                       ; C is the displacement so far.
    DEC  B                         ; Count the later parameters.
    JR   Z,.DONE                   ; The last parameter has none.
    LD   A,D                       ; Start at the next parameter.
    INC  A                         ; Its index.
    CALL RO_PARAM                  ; HL addresses its entry.
.LOOP:                         ; Look at one later parameter.
    INC  HL                        ; Skip the spelling's address.
    INC  HL                        ; Skip its high byte.
    INC  HL                        ; Skip the length to reach the type.
    LD   A,(HL)                    ; Read the type.
    CP   AG_VIEW                   ; Is it an open string?
    JR   NZ,.NEXT                  ; Other parameters are one word.
    INC  C                         ; Its capacity word lies above this argument.
    INC  C                         ; So add a second byte for the word.
.NEXT:                         ; Move to the following parameter.
    INC  HL                        ; Step to the next four-byte entry.
    DJNZ .LOOP                     ; Look at every later parameter.
.DONE:                         ; Return the displacement.
    LD   A,C                       ; Keep it across the restores.
    POP  DE                        ; Restore the parameter index.
    POP  BC                        ; Restore the count.
    LD   C,A                       ; Return it in C as well.
    OR   A                         ; With carry clear.
    RET                            ; A and C are the displacement.
