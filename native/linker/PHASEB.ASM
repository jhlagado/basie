;==========================================================================
;  Phase B: marking, and the table dump
;==========================================================================
;
;  Phase B (linker §5) marks what is live: every root, and everything a
;  live blob refers to, following the edge lists. MAIN is the blob ENTRY
;  names, an alias makes its base live, and a reference to FILES or
;  FILECOUNT means the program uses files. Option W then dumps the table to
;  NAME.$TB, for testing the linker against the reference.
;
;  Principal entries:
;    PB_RUN    mark the live blobs, noting their alignment classes in PB_CLASS
;    TB_WRITE  write NAME.$TB (option W)
;    DG_DISK   report a disk failure and end the run with RC_DISK
;
;  The mark stack holds the entries marked but not yet followed. It grows
;  up from PRG_END, the end of the program table, towards the edge lists;
;  an entry is pushed once, when it is marked, so at most one word per blob.

PB_STACK:                      ; The mark stack's top: the next free word.
    DW   0                         ; It starts at PRG_END.
PB_CLASS:                      ; Bit n: a live blob of alignment class n.
    DB   0                         ; Phases C to E pass over the classes present.

;@ROUTINE CLOBBERS A,BC,DE,HL,CARRY,ZERO,SIGN,PARITY,HALFCARRY
; Phase B: mark every root live, then follow the edges of each live blob
; until the mark stack is empty. L-CAP-TABLES if the stack meets the edge
; lists.

PB_RUN:                        ; The tables are complete and checked.
    LD   HL,(PRG_END)              ; The mark stack starts empty
    LD   (PB_STACK),HL             ; above the program table.
    LD   HL,0                      ; The roots: HL is the table position.
.ROOTS:                        ; HL walks every position.
    PUSH HL                        ; Keep it.
    CALL TAB_AT                    ; HL is its entry; carry past the end.
    JR   C,.WORK                   ; Every root is marked.
    LD   A,(HL)                    ; Its flags:
    AND  EF_ROOT+EF_ALIAS+EF_DEF   ; a defined root
    CP   EF_ROOT+EF_DEF            ; that is not an alias.
    CALL Z,.MARK                   ; Mark it live and push it.
    POP  HL                        ; HL is the position.
    INC  HL                        ; The next.
    JR   .ROOTS                    ; Go on.
.WORK:                         ; The position is on the stack.
    POP  HL                        ; Drop it.
.POP:                          ; Follow the edges of each entry pushed.
    LD   HL,(PB_STACK)             ; Pop an entry:
    LD   DE,(PRG_END)              ; is the stack
    OR   A                         ; empty,
    SBC  HL,DE                     ; back at its base?
    RET  Z                         ; Every live blob is marked.
    LD   HL,(PB_STACK)             ; The top,
    DEC  HL                        ; less one word:
    LD   D,(HL)                    ; the entry's high byte,
    DEC  HL                        ; then
    LD   E,(HL)                    ; its low byte.
    LD   (PB_STACK),HL             ; The stack is one shorter.
    EX   DE,HL                     ; HL = the entry.
    LD   DE,E_EDGES                ; Its edges field.
    ADD  HL,DE                     ; HL addresses it.
    LD   E,(HL)                    ; The low byte,
    INC  HL                        ; then
    LD   D,(HL)                    ; the high byte.
    EX   DE,HL                     ; HL = its lowest edge, or 0.
    LD   A,H                       ; No references?
    OR   L                         ; Then nothing to follow.
    JR   Z,.POP                    ; The next entry.
.EDGE:                         ; HL walks up the entry's edges.
    LD   E,(HL)                    ; An edge's low byte,
    INC  HL                        ; then
    LD   D,(HL)                    ; its high byte.
    INC  HL                        ; The next edge.
    LD   A,D                       ; $0000
    OR   E                         ; ends the list.
    JR   Z,.POP                    ; The terminator.
    PUSH HL                        ; Keep the walk.
    CALL .FOLLOW                   ; Mark the target live.
    POP  HL                        ; Recover the walk.
    JR   .EDGE                     ; The next edge.

;@ROUTINE IN DE CLOBBERS A,BC,DE,HL,CARRY,ZERO,SIGN,PARITY,HALFCARRY
; Follow edge DE: MAIN is the entry routine, FILES and FILECOUNT mean the
; program uses files, other pseudo-objects are not blobs, and an alias
; marks its base.

.FOLLOW:                       ; DE is a target ordinal.
    LD   A,D                       ; Is it $FFxx?
    CP   $FF                       ; Pseudo-objects are there.
    JR   NZ,.REAL                  ; A blob or alias.
    LD   A,E                       ; Which pseudo-object?
    CP   PS_FILES & $FF            ; FILES?
    JR   Z,.FILES                  ; The program uses files.
    CP   PS_COUNT & $FF            ; FILECOUNT?
    JR   Z,.FILES                  ; Likewise.
    CP   PS_MAIN & $FF             ; MAIN?
    RET  NZ                        ; Other pseudo-objects are not blobs.
    LD   DE,(PA_MAIN)              ; MAIN is the blob ENTRY names.
    JR   .REAL                     ; Mark it.
.FILES:                        ; FILES or FILECOUNT.
    LD   A,1                       ; The program uses files,
    LD   (PB_FILES),A              ; so Phase C places the file table.
    RET                            ; Not a blob.
.REAL:                         ; DE is a blob or alias ordinal.
    EX   DE,HL                     ; HL is the ordinal.
    CALL TAB_FIND                  ; HL is its entry.
    RET  C                         ; No entry: nothing to mark.
    BIT  6,(HL)                    ; An alias?
    JR   Z,.MARK                   ; A blob: mark it.
    LD   DE,E_ADDR                 ; An alias: its base,
    ADD  HL,DE                     ; held in its address field
    LD   E,(HL)                    ; until Phase C,
    INC  HL                        ; low byte
    LD   D,(HL)                    ; then high.
    EX   DE,HL                     ; HL is the base.
    CALL TAB_FIND                  ; HL is its entry.
    RET  C                         ; No entry: nothing to mark.

;@ROUTINE IN HL CLOBBERS A,BC,DE,HL,CARRY,ZERO,SIGN,PARITY,HALFCARRY
; Mark the entry at HL live and push it, unless it already is, noting its
; alignment class among those present. L-CAP-TABLES if the stack reaches
; the edge lists.

.MARK:                         ; HL is an entry.
    BIT  5,(HL)                    ; EF_LIVE already?
    RET  NZ                        ; Marked before: nothing to do.
    SET  5,(HL)                    ; Mark it live.
    PUSH HL                        ; Keep the entry.
    LD   DE,E_LAYOUT               ; Its alignment code.
    ADD  HL,DE                     ; HL addresses it.
    LD   B,(HL)                    ; B is the class,
    INC  B                         ; plus one, the rotations needed.
    LD   A,0                       ; A starts clear,
    SCF                            ; with a bit to rotate in.
.BIT:                          ; Rotate the bit to the class's place.
    RLA                            ; A = 1 << class.
    DJNZ .BIT                      ; Class + 1 rotations.
    LD   HL,PB_CLASS               ; Add the class
    OR   (HL)                      ; to those present,
    LD   (HL),A                    ; and keep them.
    POP  HL                        ; HL is the entry.
    EX   DE,HL                     ; DE is the entry.
    LD   HL,(PB_STACK)             ; Push it:
    LD   (HL),E                    ; low byte,
    INC  HL                        ; then
    LD   (HL),D                    ; high byte.
    INC  HL                        ; The stack's new top.
    LD   (PB_STACK),HL             ; Keep it.
    LD   BC,(EDGE_PTR)             ; The stack must stay below the edge lists.
    OR   A                         ; Clear carry for the subtraction.
    SBC  HL,BC                     ; No carry if it has reached them.
    JP   NC,DG_CAP                 ; L-CAP-TABLES.
    RET                            ; The entry is live and pushed.

; ---- the table dump (option W) ------------------------------------------------

TB_TYPE:                       ; The dump's type.
    DB   "$TB"                     ; Three characters.

;@ROUTINE CLOBBERS A,BC,DE,HL,IX,CARRY,ZERO,SIGN,PARITY,HALFCARRY
; Write NAME.$TB on the first part's drive: for each defined entry, its
; ordinal, its flags and its size; then $FFFF and whether the program uses
; files. For testing the linker against the reference.

TB_WRITE:                      ; Called after Phase B, with option W.
    LD   IX,TB_FD                  ; The output FD, unused until Phase D.
    LD   A,(CMD_DISK)              ; The first part's drive,
    LD   HL,CMD_NAME               ; NAME,
    LD   DE,TB_TYPE                ; type $TB.
    CALL FIL_INIT                  ; Set up the FCB.
    XOR  A                         ; Pad the last record with zeros.
    CALL FIL_MAKE                  ; Create it; carry if the directory is full.
    JR   C,DG_DISK                 ; L-IO.
    LD   HL,0                      ; The position.
.EACH:                         ; HL walks every position.
    PUSH HL                        ; Keep it.
    CALL TAB_AT                    ; HL is its entry; carry past the end.
    JR   C,.END                    ; Every entry is written.
    BIT  3,(HL)                    ; Defined?
    JR   Z,.NEXT                   ; Only defined entries are written.
    POP  DE                        ; The position, as an ordinal:
    PUSH DE                        ; still kept.
    PUSH HL                        ; Keep the entry.
    EX   DE,HL                     ; HL is the position.
    CALL TAB_ORD                   ; HL is the ordinal.
    CALL .PUTW                     ; Write it.
    POP  HL                        ; HL is the entry.
    LD   A,(HL)                    ; Its flags.
    PUSH HL                        ; Keep the entry.
    CALL .PUTB                     ; Write them.
    POP  HL                        ; HL is the entry.
    INC  HL                        ; Its size,
    LD   E,(HL)                    ; low byte,
    INC  HL                        ; then
    LD   D,(HL)                    ; high byte.
    EX   DE,HL                     ; HL is the size.
    CALL .PUTW                     ; Write it.
.NEXT:                         ; The position is on the stack.
    POP  HL                        ; HL is the position.
    INC  HL                        ; The next.
    JR   .EACH                     ; Go on.
.END:                          ; The position is on the stack.
    POP  HL                        ; Drop it.
    LD   HL,$FFFF                  ; The end mark.
    CALL .PUTW                     ; Write it.
    LD   A,(PB_FILES)              ; Whether the program uses files.
    CALL .PUTB                     ; Write it.
    CALL FIL_SHUT                  ; Close the dump; carry on failure.
    JR   C,DG_DISK                 ; L-IO.
    RET                            ; The dump is written.

;@ROUTINE IN HL,IX CLOBBERS A,CARRY,ZERO,SIGN,PARITY,HALFCARRY
; Write HL to the file at IX, low byte first. L-IO if the disk is full.

.PUTW:                         ; HL is the word.
    LD   A,L                       ; The low byte,
    CALL .PUTB                     ; written.
    LD   A,H                       ; Then the high byte.

;@ROUTINE IN A,IX CLOBBERS CARRY,ZERO,SIGN,PARITY,HALFCARRY
; Write A to the file at IX. L-IO if the disk is full.

.PUTB:                         ; A is the byte.
    CALL FIL_PUTB                  ; Write it; carry if the disk is full.
    RET  NC                        ; Written.

;@ROUTINE NORETURN
; Report L-IO for the file RD_NAME names, abandon the link's outputs, and
; end the run with RC_DISK. RD_NAME is the file last read, which is not
; always the file that failed.

DG_DISK:                       ; A write, make, close or rename failed.
    LD   HL,222                    ; L-IO.
    LD   DE,(RD_NAME)              ; The file's name as text
    LD   (DG_ARG1),DE              ; is argument 1.
    CALL DG_ERROR                  ; Report it.
    CALL PUB_UNDO                  ; Delete the new output and the intermediates.
    LD   DE,RC_DISK                ; A disk failure's return code.
    JP   CPM_EXIT                  ; End the run.
