;==========================================================================
;  Routine names, signatures and the compile entry
;==========================================================================
;
;  Keep the tables of routines and parameters that the grammar actions
;  (ACTIONS.ASM) fill as they parse routine declarations: look names up,
;  reject names already in use, enrol parameters and bind each one as a
;  symbol of the routine's frame. CALLS.ASM parses the calls and the
;  aggregate paths that use these tables.
;
;  The module also holds the compile entry PR_BUILD, which parses the
;  program, writing its blobs as it goes, then its entry and limits.
;
;  Principal entries:
;    PR_BUILD  compile the source parts
;    PR_PARSE  clear the routine workspace and parse the whole program
;    RO_FIND   find the current name among the routines, or main
;    RO_LIB    find the current name among the predeclared names
;    RO_FRESH  reject a routine name that is already in use
;    RO_VET    reject a parameter name that is already in use
;    RO_ENROL  append a parameter to the parameter table
;    RO_DISP   give a parameter's argument displacement in the frame
;    RO_BIND   make a parameter a symbol at its argument's offset
;
;  The routine table (RO_RTAB) holds 32 routines of twelve bytes, laid out
;  in CALLWORK.ASM: the name, the parameters, the result type, the flags
;  (RO_FFAIL, RO_FOPEN while a forward awaits its body, RO_FFWD for one
;  declared forward), the blob's ordinal, the need once the body is
;  complete and the bytes of the arguments.
;
;  The parameter table (RO_PTAB) holds 64 parameters of four bytes: the
;  spelling's address and length, then the type, AG_VIEW for an open
;  string. A routine's parameters are consecutive entries.

;@ROUTINE IN A OUT HL CLOBBERS CARRY,HALFCARRY,DE
; Return in HL the address of routine-table entry A, RO_RTAB plus twelve
; times A. A, BC and the zero flag are preserved.

RO_SUBAT:
    LD   L,A                       ; Form the routine index as a word.
    LD   H,0                       ; At most RO_RCAP entries.
    ADD  HL,HL                     ; Times two.
    LD   D,H                       ; Keep
    LD   E,L                       ; twice the index.
    ADD  HL,HL                     ; Times four,
    ADD  HL,DE                     ; six,
    ADD  HL,HL                     ; twelve, the entry size.
    LD   DE,RO_RTAB                ; The table's base.
    ADD  HL,DE                     ; HL addresses the entry.
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

;@ROUTINE OUT A,HL,CARRY,SIGN CLOBBERS PARITY,HALFCARRY,ZERO,BC,DE
; Find the current NAME among the predeclared names (HP_NAMES, PREDEF.ASM).
; Carry returns HL addressing its payload and A the payload's first byte,
; with the sign set for a constant (SY_KNOWN and its type) and clear for a
; service (its result type). Carry clear means neither.

RO_LIB:
    LD   HL,HP_NAMES               ; Entries: a length byte and spelling.
    LD   C,HP_NCNT                 ; C counts the entries left.
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
    JR   NZ,.SKIP                  ; HL + B is still the spelling's end.
    INC  DE                        ; Advance in the token.
    INC  HL                        ; Advance in the entry.
    DJNZ .BYTELOOP                 ; Compare every character.
    LD   A,(HL)                    ; The payload's first byte,
    OR   A                         ; negative for a constant.
    SCF                            ; Report a match.
    RET                            ; A and HL describe it.
.SKIP:                         ; B characters remain at HL.
    LD   E,B                       ; The characters not yet passed,
    LD   D,0                       ; as a word,
    ADD  HL,DE                     ; bring HL to the payload.
    LD   E,2                       ; A constant's is two bytes:
    BIT  7,(HL)                    ; is this one?
    JR   NZ,.NEXT                  ; Then step over them.
    LD   E,7                       ; A service's eighth byte
    ADD  HL,DE                     ; is its parameters' count,
    LD   E,(HL)                    ; their types
    INC  HL                        ; following it.
.NEXT:                         ; DE bytes remain in the entry.
    ADD  HL,DE                     ; HL addresses the next entry.
    DEC  C                         ; One entry fewer.
    JR   NZ,.LOOP                  ; Continue through the table.
    OR   A                         ; Report no match.
    RET                            ; Carry is clear.

;@ROUTINE IN A,HL OUT CARRY CLOBBERS A,BC,DE,HL,IX,IY,SIGN,PARITY,HALFCARRY,ZERO
; Compile A source parts, described at HL, into the blob writer's streams,
; which the caller has opened (BL_OPEN): every blob, then the entry and
; limits records. Carry clear reports success. A diagnostic returns carry
; set, with DG_CODE, DG_PART and DG_POS describing it.

PR_BUILD:
    LD   (PR_SP),SP                ; A diagnostic returns from here.
    PUSH AF                        ; Keep the part count.
    PUSH HL                        ; Keep the part descriptors.
    CALL PR_RESET                  ; Clear the parser's state.
    POP  HL                        ; Recover the part descriptors.
    POP  AF                        ; Recover the part count.
    CALL SRC_OPEN                  ; Open the first part.
    CALL PR_PARSE                  ; Parse every part, writing its blobs.
    CALL RG_END                    ; The entry and limits records.
    OR   A                         ; Carry clear: success.
    RET                            ; The caller closes the streams.

;@ROUTINE OUT A,CARRY,ZERO CLOBBERS SIGN,PARITY,HALFCARRY,BC,DE,HL,IX,IY
; Clear the routine state and run the LL(1) parser
; over every source part. The tables are written before they are read.

PR_PARSE:
    LD   HL,RO_BASE                ; Clear the routine state:
    LD   B,RO_STEND-RO_BASE        ; its counts and fields.
    XOR  A                         ; Zero each byte.
.WIPE:                         ; Clear one byte.
    LD   (HL),A                    ; Store zero.
    INC  HL                        ; Next byte.
    DJNZ .WIPE                     ; Clear the whole workspace.
    JP   LL_PARSE                  ; Parse the program and return.

;@ROUTINE IN A OUT A,CARRY,ZERO CLOBBERS SIGN,PARITY,HALFCARRY,BC,DE,HL
; Reject the current name if it is a routine's or a predeclared name, as
; diagnostic A, which names it: DG_DUP for a declaration of the program's,
; DG_HIDE for a local or parameter. Neither returns. A is kept.

RO_FRESH:
    PUSH AF                        ; Keep the diagnostic.
    CALL RO_FIND                   ; Is it a routine already?
    JR   Z,.TAKEN                  ; Then it is taken.
    CALL RO_LIB                    ; Is it a predeclared name?
    JR   C,.TAKEN                  ; Then it is taken.
    POP  AF                        ; The diagnostic, not raised.
    OR   A                         ; Report success with carry clear.
    RET                            ; The name is free.
.TAKEN:                        ; The diagnostic is on the stack.
    POP  AF                        ; Raise it,
    JP   DG_NAMED                  ; naming the name.

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
    JP   C,EX_EDUP                 ; Raise DG_DUP, naming it.
    INC  B                         ; Next entry.
    DEC  C                         ; One entry fewer.
    JR   NZ,.LOOP                  ; Continue through the signature.
    OR   A                         ; Report success with carry clear.
    RET                            ; The name is new to the signature.

;@ROUTINE OUT A,CARRY,ZERO CLOBBERS SIGN,PARITY,HALFCARRY,BC,DE,HL
; Reject a parameter name that would hide a program-wide name, a routine,
; a predeclared name or the routine whose signature is being parsed
; (DG_HIDE), or that repeats an earlier parameter of that signature
; (DG_DUP). Both name it.

RO_VET:
    CALL SY_FIND                   ; A program-wide symbol?
    LD   A,DG_HIDE                 ; Then the parameter would hide it.
    JP   C,DG_NAMED                ; Raise it, named.
    CALL RO_FRESH                  ; Not a routine or a predeclared name.
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
    LD   A,DG_HIDE                 ; Then it would hide it:
    JP   C,DG_NAMED                ; raise it, named.
    JR   RO_NODUP                  ; Check the earlier parameters.

;@ROUTINE IN A OUT A,CARRY,ZERO CLOBBERS SIGN,PARITY,HALFCARRY,BC,DE,HL
; Append the current NAME as a parameter of type A to the parameter table
; and the signature, and count its argument's bytes into RO_CARGS: a word,
; or two for an open string's view or a File (parameterWords). A full
; table, or arguments beyond 255 bytes, raise DG_PARAM, which does not
; return.

RO_ENROL:
    LD   (RO_OTYPE),A              ; Keep the type.
    CALL RO_WORDS                  ; B is the argument's bytes.
    LD   HL,RO_CARGS               ; The signature's argument bytes
    LD   A,(HL)                    ; grow
    ADD  A,B                       ; by them,
    JR   C,.FULL                   ; within the byte LD IY,n is given;
    LD   (HL),A                    ; keep them.
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

;@ROUTINE IN A OUT B CLOBBERS CARRY,ZERO,SIGN,PARITY,HALFCARRY
; Return in B the bytes an argument of type A takes (parameterWords): four
; for an open string's view or a File, two for anything else. A is kept.

RO_WORDS:
    LD   B,4                       ; Two words
    CP   AG_VIEW                   ; for a view
    RET  Z                         ; of a string,
    CP   AG_FILE                   ; or a File;
    RET  Z                         ; otherwise
    LD   B,2                       ; one.
    RET                            ; B is the bytes.

;@ROUTINE IN A,C OUT A,CARRY,ZERO CLOBBERS SIGN,PARITY,HALFCARRY,BC,DE,HL
; Make parameter A, whose argument is at displacement C from IX, a symbol
; whose payload is that offset: the argument is used in place (design
; decision D41). The current token is replaced by the parameter's name.

RO_BIND:
    CALL RO_PARAM                  ; HL addresses the parameter's entry.
    LD   E,(HL)                    ; Read the address of its spelling.
    INC  HL                        ; High byte.
    LD   D,(HL)                    ; DE addresses the spelling.
    INC  HL                        ; Then its length.
    LD   B,(HL)                    ; B is the length.
    INC  HL                        ; Then its type.
    LD   A,(HL)                    ; Read the type.
    LD   (TK_PTR),DE               ; SY_NEW names the symbol from the token,
    LD   E,A                       ; so, keeping the type,
    LD   A,B                       ; the parameter's spelling
    LD   (TK_LEN),A                ; becomes the token.
    LD   B,0                       ; BC is the displacement, the payload.
    LD   A,E                       ; Classify the parameter.
    CP   AG_FIRST                  ; Is it an aggregate?
    LD   D,SY_AGGR+SY_PARAM        ; An aggregate parameter's class.
    JR   NC,.SYMBOL                ; Use it.
    OR   SY_PARAM                  ; A scalar's: its type, class parameter.
    LD   D,A                       ; The symbol's class byte.
.SYMBOL:                       ; D is the class, E the type.
    CALL SY_NEW                    ; Write the record; DE is kept.
    LD   A,E                       ; Record the symbol's aggregate type;
    JP   SY_TAG                    ; SY_TAG also commits the symbol.

;@ROUTINE IN B,D OUT A,C,CARRY,ZERO CLOBBERS SIGN,PARITY,HALFCARRY,HL
; Return in A and C the IX displacement of parameter D's argument, where B
; counts the parameters from D to the last. The last argument is at IX+4;
; each later parameter adds its argument's bytes (RO_WORDS). B, D and E
; are preserved.

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
    PUSH BC                        ; Keep the count.
    CALL RO_WORDS                  ; B is its argument's bytes.
    LD   A,B                       ; Less the word
    SUB  2                         ; already counted,
    POP  BC                        ; (the count again)
    ADD  A,C                       ; the bytes above this argument
    LD   C,A                       ; grow by the rest.
    INC  HL                        ; Step to the next four-byte entry.
    DJNZ .LOOP                     ; Look at every later parameter.
.DONE:                         ; Return the displacement.
    LD   A,C                       ; Keep it across the restores.
    POP  DE                        ; Restore the parameter index.
    POP  BC                        ; Restore the count.
    LD   C,A                       ; Return it in C as well.
    OR   A                         ; With carry clear.
    RET                            ; A and C are the displacement.
