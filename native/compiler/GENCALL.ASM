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
;    RG_BSS    write a bss blob of the staged object's size
;    RG_END    write the entry and limits records
;    BL_OVER   the blob writer's overflow: refuse the routine or object

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
; the routine was declared forward (RO_CFLAG). Code may then be written.

RG_OPEN:                       ; HL is the name, B its length, DE the ordinal.
    LD   (RG_NAME),HL              ; Keep the name for the name stream.
    LD   A,B                       ; And its length.
    LD   (RG_NLEN),A               ; Keep it.
    EX   DE,HL                     ; HL is the routine's ordinal.
    XOR  A                         ; Kind code, no root flag, no alignment.
    CALL BL_BEGIN                  ; Start the blob.
    CALL EM_OPEN                   ; No frame, temporaries or labels yet.
    LD   A,(SRC_ID)                ; The part, counted from one,
    DEC  A                         ; is the line stream's part, from zero.
    LD   HL,(AC_DPOS+2)            ; The line of the routine's name.
    CALL BL_LINE                   ; The blob starts on it.
    CALL EM_LNEW                   ; Label 0, RG_EXIT.
    CALL EM_LNEW                   ; Label 1, RG_PAIR.
    LD   A,(RO_CFLAG)              ; Was the routine declared forward?
    AND  RO_FFWD                   ; Then recursion may reach it:
    JR   Z,.FRAME                  ; check its need against the stack.
    CALL EM_OP                     ; LD HL,(need):
    DB   $2A                       ; the opcode,
    LD   A,RG_PAIR                 ; and the need word's address,
    CALL EM_LREF                   ; through the pair label.
    CALL EM_HELP                   ; CALL STK_CHK,
    DB   $0A,2                     ; ordinal $0A, two bytes of stack.
.FRAME:                        ; The frame is built.
    CALL EM_SEQ                    ; The frame pointer, then LD HL,nn:
    DB   9,$DD,$E5,$DD,$21,0,0,$DD,$39,$21 ; PUSH IX, LD IX,0, ADD IX,SP.
    LD   HL,(BL_LEN)               ; The operand is the frame, negated,
    LD   (RG_PATCH),HL             ; patched when the routine ends.
    CALL EM_SEQ                    ; Its placeholder,
    DB   4,0,0,$39,$F9             ; then ADD HL,SP and LD SP,HL.
    RET                            ; The body follows.

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

;@ROUTINE OUT HL CLOBBERS A,BC,DE,CARRY,ZERO,SIGN,PARITY,HALFCARRY
; End the routine: the success return if its end is reachable (CT_FALLS),
; the exit sequence, the frame patched into the prologue, the frame and
; need words, then write the blob and its name. HL returns the need.

RG_CLOSE:                      ; The routine's `end` has been parsed.
    LD   A,(CT_FALLS)              ; Can control reach the end?
    OR   A                         ; Zero if every path has left.
    CALL NZ,RG_RET                 ; Falling off the end is success.
    LD   A,RG_EXIT                 ; The exit sequence starts here.
    CALL EM_LDEF                   ; Every return jumps to it.
    LD   A,(RO_CARGS)              ; Has the routine arguments to remove?
    OR   A                         ; Zero if it has none.
    JR   NZ,.RETN                  ; Then RETN removes them.
    CALL EM_SEQ                    ; With no arguments to remove:
    DB   5,$DD,$F9,$DD,$E1,$C9     ; LD SP,IX, POP IX, RET.
    JR   .EXITED                   ; The exit is written.
.RETN:                         ; A is the arguments' bytes.
    LD   L,A                       ; HL is the bytes
    LD   H,0                       ; as a word.
    CALL EM_SEQ                    ; LD IY,n:
    DB   2,$FD,$21                 ; the opcode,
    CALL EM_WORD                   ; and the bytes as its operand.
    CALL EM_JPH                    ; JP RETN, which removes them,
    DB   $09,2                     ; ordinal $09, two bytes of stack.
.EXITED:                       ; The frame and need words follow.
    LD   HL,(EM_DEEP)              ; The frame: the deepest point reached.
    LD   DE,(RG_LARGE)             ; Is it the largest of any routine?
    OR   A                         ; Clear carry.
    SBC  HL,DE                     ; Carry if it is not.
    ADD  HL,DE                     ; HL is the frame again.
    JR   C,.SMALLER                ; Keep the larger one.
    LD   (RG_LARGE),HL             ; It is the largest frame.
.SMALLER:                      ; HL is the frame.
    PUSH HL                        ; Keep it for the frame word.
    EX   DE,HL                     ; DE is the frame.
    LD   HL,0                      ; Negate it:
    OR   A                         ; zero less the frame
    SBC  HL,DE                     ; is the prologue's operand.
    EX   DE,HL                     ; DE is the operand.
    LD   HL,(RG_PATCH)             ; Its offset in the blob,
    LD   BC,BL_CODE                ; plus the buffer's address,
    ADD  HL,BC                     ; is where it goes.
    LD   (HL),E                    ; Low byte,
    INC  HL                        ; then
    LD   (HL),D                    ; high byte.
    POP  HL                        ; HL is the frame.
    PUSH HL                        ; Keep it for the need.
    CALL EM_WORD                   ; The frame word.
    LD   A,RG_PAIR                 ; The need word follows it,
    CALL EM_LDEF                   ; where the pair label points.
    POP  HL                        ; The need: the frame,
    LD   DE,(EM_STACK)             ; the largest helper's stack,
    ADD  HL,DE                     ; added,
    LD   DE,(EM_NEED)              ; the largest callee's need,
    ADD  HL,DE                     ; added,
    LD   DE,4                      ; and four bytes for IX and the
    ADD  HL,DE                     ; return address.
    PUSH HL                        ; Keep it to return.
    CALL EM_WORD                   ; The need word.
    CALL BL_END                    ; Write the blob.
    LD   HL,(BL_ORD)               ; Its ordinal.
    LD   DE,(RG_NAME)              ; Its name,
    LD   A,(RG_NLEN)               ; of this
    LD   B,A                       ; length.
    CALL BL_NAME                   ; Record it.
    POP  HL                        ; HL is the need.
    RET                            ; The routine is written.

;@ROUTINE IN A OUT BC CLOBBERS A,DE,HL,CARRY,ZERO,SIGN,PARITY,HALFCARRY
; Write the object staged in AG_IBUF, AG_OSIZE bytes, as a blob of kind A
; (BL_KDATA or BL_KRO), named by the retained declaration name. BC returns
; its ordinal.

RG_DATA:                       ; A is the kind.
    CALL RG_ADD                    ; HL is the ordinal.
    PUSH HL                        ; Keep it.
    CALL BL_BEGIN                  ; Start the blob; no root, no alignment.
    LD   HL,AG_IBUF                ; The staged bytes,
    LD   BC,(AG_OSIZE)             ; all of them.
.LOOP:                         ; BC bytes remain at HL.
    LD   A,(HL)                    ; Append the next
    CALL BL_BYTE                   ; to the blob.
    INC  HL                        ; Move to the next.
    DEC  BC                        ; One fewer.
    LD   A,B                       ; Any left?
    OR   C                         ; Zero when all are written.
    JR   NZ,.LOOP                  ; Append the rest.
    CALL BL_END                    ; Write the blob.
    JR   RG_NAMED                  ; Name it and return its ordinal.

;@ROUTINE OUT BC CLOBBERS A,DE,HL,CARRY,ZERO,SIGN,PARITY,HALFCARRY
; Write a bss blob of the staged object's size, AG_OSIZE, named by the
; retained declaration name. BC returns its ordinal.

RG_BSS:                        ; A program variable without initializer.
    CALL RG_ADD                    ; HL is the ordinal.
    PUSH HL                        ; Keep it.
    LD   DE,(AG_OSIZE)             ; Its size.
    LD   A,BL_KBSS                 ; Kind bss, no root, no alignment.
    CALL BL_BSS                    ; Write its record.

;@ROUTINE OUT BC CLOBBERS A,DE,HL,CARRY,ZERO,SIGN,PARITY,HALFCARRY
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

;@ROUTINE CLOBBERS A,DE,HL,CARRY,ZERO,SIGN,PARITY,HALFCARRY
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
    OR   A                         ; (the limits record's recursion flag):
    JR   Z,.FLAGS                  ; zero when none is,
    LD   A,1                       ; else one.
.FLAGS:                        ; A is the flags.
    JP   BL_LIMIT                  ; Record them and return.

;@ROUTINE NORETURN
; The blob writer's overflow (BLOB.ASM): a routine or object larger than
; its buffers is refused with DG_BLOB at the current token.

BL_OVER:                       ; A buffer of the blob writer is full.
    CALL DG_RAISE                  ; Report it; parsing ends.
    DB   DG_BLOB                   ; Too large for the blob buffers.
