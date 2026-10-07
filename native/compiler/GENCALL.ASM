;==========================================================================
;  Routine and declaration generation
;==========================================================================
;
;  Write each routine and each top-level declaration as a blob while it is
;  parsed, as the reference compiler does (ref/compile/compiler.ts,
;  compileBody, programVar, constDeclaration), and the program's entry and
;  limits records at the end (design decision D41, the code generation
;  contract, and D45).
;
;  Ordinals. Every blob takes the next ordinal from RG_ORD, which starts at
;  the program's ordinal base, $0400, in declaration order: the order of
;  the reference's newBlob. Each blob's name follows its record in the
;  name stream, as the reference names every blob.
;
;  A routine's blob is its prologue, its body, the success return when its
;  end is reachable, the exit sequence, then the frame and need words:
;
;    LD HL,(pair) / CALL STK_CHK         a forward routine checks the stack
;    PUSH IX / LD IX,0 / ADD IX,SP      the frame pointer
;    LD HL,-frame / ADD HL,SP / LD SP,HL  the frame, patched at the end
;    ...                                 the body
;    OR A / JP exit                      falling off the end: success
;  exit:
;    LD SP,IX / POP IX / RET             no arguments to remove, or
;    LD IY,n / JP RETN                   RETN removes n bytes of them
;    DW frame                            the deepest frame and pushes
;  pair:
;    DW need                             frame + 4 + helpers + callees
;
;  An aggregate constant declared in a routine's body takes its ordinal
;  where it is declared, after the routine's, and its blob follows the
;  routine's, as the reference's list has them; the blob writer builds one
;  blob at a time, so the constant waits, staged in the free memory
;  after the symbol table, below the routine's blob (BL_SPAN), until the
;  routine's blob is written (RG_DEFER, RG_CLOSE). Each waiting constant
;  is its ordinal, its size, its bytes, then its name's address and length.
;
;  Labels 0 and 1 of every routine are its exit and its pair (RG_EXIT,
;  RG_PAIR). A routine declared forward may be reached by recursion, so it
;  checks its need against the stack before it builds its frame, as the
;  reference's compileBody does for a routine completing a forward.
;
;  Principal entries:
;    RG_ADD    take the next ordinal
;    RG_OPEN   begin a routine's blob, its line entry and prologue
;    RG_RET    the success return: OR A when it can fail, JP exit
;    RG_CLOSE  end a routine: exit, frame and need, write the blob
;    RG_DATA   write the staged object as a blob of a given kind
;    RG_DEFER  keep a routine's aggregate constant until its blob is written
;    RG_BSS    write a bss blob of the staged object's size
;    RG_END    write the entry and limits records
;    BL_OVER   the blob writer's overflow: refuse a routine or object of 16K

RG_EXIT EQU  0                 ; Label of a routine's exit sequence.
RG_PAIR EQU  1                 ; Label of its need word, after the frame word.
RG_GUARD EQU  64               ; Stack bytes reserved beyond main's need.

;@ROUTINE OUT HL CLOBBERS DE,CARRY,ZERO,SIGN,PARITY,HALFCARRY
; Return in HL the next ordinal, and step RG_ORD past it.

RG_ADD:                        ; A blob is about to begin.
    LD   HL,(RG_ORD)               ; HL is the ordinal it takes.
    LD   D,H                       ; Keep it
    LD   E,L                       ; in DE.
    INC  DE                        ; The next blob takes the one after.
    LD   (RG_ORD),DE               ; Keep that.
    RET                            ; HL is this blob's ordinal.

;@ROUTINE IN B,DE,HL CLOBBERS A,BC,DE,HL,CARRY,ZERO,SIGN,PARITY,HALFCARRY
; Begin the blob of the routine whose name is the B characters at HL and
; whose ordinal is DE: mark its line (the line of its name, AC_DPOS),
; allocate its exit and pair labels and write its prologue, checked when
; the routine was declared forward (RO_CFLAG); no constant waits yet
; (RG_PEND). Code may then be written.

RG_OPEN:                       ; HL is the name, B its length, DE the ordinal.
    LD   (RG_NAME),HL              ; Keep the name for the name stream.
    LD   A,B                       ; And its length.
    LD   (RG_NLEN),A               ; Keep it.
    PUSH DE                        ; (the ordinal kept)
    LD   HL,(SY_TOP)               ; No constant waits yet: they would
    LD   DE,SY_RECB                ; follow the provisional
    ADD  HL,DE                     ; symbol record.
    LD   (RG_CBEG),HL              ; Their start
    LD   (RG_PEND),HL              ; and end.
    POP  HL                        ; HL is the routine's ordinal.
    XOR  A                         ; Kind code, no root flag, no alignment.
    CALL BL_BEGIN                  ; Start the blob.
    CALL EM_OPEN                   ; No frame, temporaries or labels yet.
    LD   A,(SRC_NUM)               ; The part's number in the stream
    LD   HL,AC_DPOS+2              ; and the routine's name's line.
    CALL BL_LINE                   ; The blob starts on it.
    CALL EM_LNEW                   ; Label 0, RG_EXIT.
    CALL EM_LNEW                   ; Label 1, RG_PAIR.
    LD   A,(RO_CFLAG)              ; Was the routine declared forward?
    AND  RO_FFWD                   ; Then recursion may reach it:
    JR   Z,.FRAME                  ; check its need against the stack.
    LD   C,$2A                     ; LD HL,(need): the opcode, and the
    LD   A,RG_PAIR                 ; need word's address, the pair label,
    CALL EM_JUMP                   ; appended as a jump's are.
    CALL EM_HELP                   ; CALL STK_CHK,
    DW   HP_STACK                  ; its ordinal and stack figure.
.FRAME:                        ; The frame is built.
    CALL EM_SEQ                    ; The frame pointer, then LD HL,nn:
    DB   9,$DD,$E5,$DD,$21,0,0,$DD,$39,$21 ; PUSH IX, LD IX,0, ADD IX,SP.
    LD   HL,(BL_LEN)               ; The operand is the frame, negated,
    LD   (RG_PATCH),HL             ; patched when the routine ends.
    CALL EM_SEQX                   ; Its placeholder,
    DB   4,0,0,$39,$F9             ; then ADD HL,SP and LD SP,HL.

;@ROUTINE CLOBBERS A,BC,DE,HL,CARRY,ZERO,SIGN,PARITY,HALFCARRY
; The success return (emitReturn without a result): OR A, carry clear, in
; a routine that can fail and in main, then JP to the exit sequence.

RG_RET:                        ; Control leaves the routine successfully.
    LD   A,(RO_CFLAG)              ; The routine's flags.
    AND  RO_FFAIL+RO_FMAIN         ; Can it fail, or is it main?
    LD   A,$B7                     ; OR A clears carry: success.
    CALL NZ,EM_BYTE                ; Then report success.
    LD   C,$C3                     ; JP
    LD   A,RG_EXIT                 ; to the exit;
    JP   EM_JUMP                   ; return.

;@ROUTINE CLOBBERS A,BC,DE,HL,CARRY,ZERO,SIGN,PARITY,HALFCARRY
; Move the routine's waiting constants, RG_CBEG to RG_PEND, and the blob
; being built after them up by a symbol record, for the symbol table below
; them, which has reached them (SY_CMT); DG_ROOM if they would reach the
; blob's log or the name heap.

RG_LIFT:                       ; A record more is needed below them.
    LD   HL,(RG_CBEG)              ; From their start,
    LD   BC,SY_RECB                ; a record
    CALL MM_LIFT                   ; up;
    LD   HL,(RG_CBEG)              ; they
    ADD  HL,BC                     ; start
    LD   (RG_CBEG),HL              ; higher,

;@ROUTINE IN BC OUT HL CLOBBERS CARRY,ZERO,SIGN,PARITY,HALFCARRY
; The waiting constants end BC bytes higher (RG_PEND); HL returns their
; old end. BC and DE are kept.

RG_PUP:                        ; BC more bytes are theirs.
    LD   HL,(RG_PEND)              ; Their end,
    PUSH HL                        ; (the old kept)
    ADD  HL,BC                     ; higher,
    LD   (RG_PEND),HL              ; is theirs.
    POP  HL                        ; The old.
    RET                            ; Done.

;@ROUTINE IN BC,HL OUT BC CLOBBERS A,DE,HL,CARRY,ZERO,SIGN,PARITY,HALFCARRY
; Open BC bytes at HL, in the waiting constants or at their end: move the
; memory from HL to the free memory's start (BL_SPAN), the constants after
; HL and the blob being built, up by BC, its bytes' address with it
; (BL_CBASE); DG_ROOM if they would pass the free memory's end. BC is
; kept.

MM_LIFT:                       ; HL is the place, BC the bytes.
    PUSH BC                        ; Keep the bytes
    PUSH HL                        ; and the place.
    CALL BL_SPAN                   ; HL is the free memory, DE its end.
    PUSH HL                        ; The moved bytes' end,
    ADD  HL,BC                     ; higher,
    JR   C,MM_FULL                 ; within memory
    EX   DE,HL                     ; and at or below
    SBC  HL,DE                     ; the free memory's
    JR   C,MM_FULL                 ; end, else DG_ROOM.
    POP  HL                        ; Their end,
    POP  BC                        ; less the place,
    PUSH HL                        ; is
    SBC  HL,BC                     ; their
    LD   B,H                       ; count,
    LD   C,L                       ; BC.
    POP  HL                        ; They are moved
    DEC  HL                        ; from the last
    DEC  DE                        ; down
    LD   A,B                       ; (none:
    OR   C                         ; none
    JR   Z,.MOVED                  ; moved).
    LDDR                           ; Moved.
.MOVED:                        ; The blob's bytes, if one is built,
    POP  BC                        ; are BC
    LD   A,(BL_CBASE+1)            ; bytes
    OR   A                         ; higher
    RET  Z                         ; too.
    LD   HL,(BL_CBASE)             ; Its
    ADD  HL,BC                     ; address
    LD   (BL_CBASE),HL             ; follows.
    RET                            ; Done.

;@ROUTINE NORETURN
; The memory is full: DG_ROOM, at the current token.

MM_FULL:                       ; No room:
    CALL DG_RAISE                  ; the memory
    DB   DG_ROOM                   ; is full.

;@ROUTINE OUT BC CLOBBERS A,DE,HL,CARRY,ZERO,SIGN,PARITY,HALFCARRY
; Keep the aggregate constant staged in AG_IBUF, AG_OSIZE bytes, named by
; the retained declaration name, until its routine's blob is written: it
; takes the next ordinal, returned in BC, and waits after the constants
; before it, within the free memory (DG_ROOM beyond).

RG_DEFER:                      ; Declared in a routine's body.
    CALL RG_ADD                    ; HL is the ordinal.
    PUSH HL                        ; Keep it.
    LD   HL,(AG_OSIZE)             ; Its bytes
    LD   BC,7                      ; and seven more:
    ADD  HL,BC                     ; the entry's size,
    LD   B,H                       ; in
    LD   C,L                       ; BC,
    LD   HL,(RG_PEND)              ; are opened
    CALL MM_LIFT                   ; after the others,
    CALL RG_PUP                    ; which end after it: HL is its place.
    POP  BC                        ; The ordinal:
    LD   (HL),C                    ; its
    INC  HL                        ; two
    LD   (HL),B                    ; bytes;
    INC  HL                        ; then
    PUSH BC                        ; (the ordinal kept)
    EX   DE,HL                     ; the size's
    LD   HL,AG_OSIZE               ; two
    LDI                            ; bytes,
    LDI                            ; copied;
    LD   BC,(AG_OSIZE)             ; then the bytes,
    LD   HL,AG_IBUF                ; from the staging;
    LDIR                           ; then the name's
    LD   HL,AC_DNAME               ; address
    LD   BC,3                      ; and length
    LDIR                           ; (AC_DLEN after it).
    POP  BC                        ; BC is the ordinal.
    RET                            ; Done.

;@ROUTINE IN A OUT BC CLOBBERS A,DE,HL,IX,CARRY,ZERO,SIGN,PARITY,HALFCARRY
; Write the object staged in AG_IBUF, AG_OSIZE bytes, as a blob of kind A
; (BL_KDATA or BL_KRO), named by the retained declaration name. BC returns
; its ordinal.

RG_DATA:                       ; A is the kind.
    CALL RG_ADD                    ; HL is the ordinal.
    PUSH HL                        ; Keep it.
    CALL BL_BEGIN                  ; Start the blob; no root, no alignment.
    LD   HL,AG_IBUF                ; The staged bytes,
    LD   BC,(AG_OSIZE)             ; all of them,
    CALL RG_WRITE                  ; appended, and the blob written.
    JR   RG_NAMED                  ; Name it and return its ordinal.

;@ROUTINE IN BC,HL OUT HL CLOBBERS A,BC,DE,IX,CARRY,ZERO,SIGN,PARITY,HALFCARRY
; Append the BC bytes at HL, at least one, to the blob, then write the
; blob (BL_END); HL returns past them.

RG_WRITE:                      ; BC bytes remain at HL.
    LD   A,(HL)                    ; Append the next
    CALL BL_BYTE                   ; to the blob.
    INC  HL                        ; Move to the next.
    DEC  BC                        ; One fewer.
    LD   A,B                       ; Any left?
    OR   C                         ; Zero when all are written.
    JR   NZ,RG_WRITE               ; Append the rest.
    PUSH HL                        ; Keep the end of the bytes
    CALL BL_END                    ; while the blob is written.
    POP  HL                        ; HL is past them.
    RET                            ; Done.

;@ROUTINE OUT BC CLOBBERS A,DE,HL,IX,CARRY,ZERO,SIGN,PARITY,HALFCARRY
; Write a bss blob of the staged object's size, AG_OSIZE, named by the
; retained declaration name. BC returns its ordinal.

RG_BSS:                        ; A program variable without initializer.
    CALL RG_ADD                    ; HL is the ordinal.
    PUSH HL                        ; Keep it.
    LD   DE,(AG_OSIZE)             ; Its size.
    LD   A,BL_KBSS                 ; Kind bss, no root, no alignment.
    CALL BL_BSS                    ; Write its record.

;@ROUTINE OUT BC CLOBBERS A,DE,HL,IX,CARRY,ZERO,SIGN,PARITY,HALFCARRY
; The tail of RG_DATA and RG_BSS, entered with the blob's ordinal pushed:
; name the blob with the retained declaration name (AC_DNAME, AC_DLEN) and
; return the ordinal in BC.

RG_NAMED:                      ; The ordinal is on top of the stack.
    POP  HL                        ; HL is the ordinal.
    PUSH HL                        ; Keep it to return.
    LD   DE,(AC_DNAME)             ; The declared name
    LD   A,(AC_DLEN)               ; and its
    LD   B,A                       ; length.
    CALL BL_NAME                   ; Record it.
    POP  BC                        ; BC is the ordinal.
    RET                            ; The blob is written and named.

;@ROUTINE CLOBBERS A,DE,HL,IX,CARRY,ZERO,SIGN,PARITY,HALFCARRY
; Write the entry record, at main, and the limits record: the stack reserve
; main's need plus the guard band, the largest frame, and the flag that
; says some routine was declared forward.

RG_END:                        ; The whole program is written.
    LD   HL,(RG_MAIN)              ; The program starts at main.
    CALL BL_ENTRY                  ; Record it.
    LD   HL,(RG_NEED)              ; Main's need
    LD   DE,RG_GUARD               ; and the guard band
    ADD  HL,DE                     ; are the stack reserve.
    LD   DE,(RG_LARGE)             ; The largest frame.
    LD   A,(RG_FWD)                ; Flag 1 when a routine is forward
    CP   1                         ; (the limits record's recursion flag):
    SBC  A,A                       ; $FF when none is, else zero,
    INC  A                         ; then zero or one.
    JP   BL_LIMIT                  ; Record them and return.

;@ROUTINE NORETURN
; The blob writer's overflow (BLOB.ASM): a routine or object of 16K is
; refused with DG_BLOB at the current token.

BL_OVER:                       ; A blob has reached 16K.
    CALL DG_RAISE                  ; Report it; parsing ends.
    DB   DG_BLOB                   ; Too large for one blob.
