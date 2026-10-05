;==========================================================================
;  Phase E: the map and the symbol file
;==========================================================================
;
;  Phase E (linker §8): the map (option M) and the symbol file (option
;  Y), written after publication. A report that can't be written is
;  deleted and reported; the published program stands. REPORT.ASM holds
;  the workspace, the text output and the name readers.
;
;  Principal entries:
;    PE_RUN    open the names and the reports, write them and close them
;    SY_ROW    write a symbol row
;    SY_ALIAS  write the symbol file's rows for live named aliases
;    MAP_DEAD  write the map's removed blobs and its totals
;
;  The map is a summary (.SUMMARY), the live blobs in address order, made
;  by the passes of Phases C and D, then the removed blobs in directory
;  order and the totals. The symbol file has a row for each live named
;  blob, from the same passes, then one for each live named alias.

; ---- Phase E -----------------------------------------------------------------

;@ROUTINE CLOBBERS A,BC,DE,HL,IX,CARRY,ZERO,SIGN,PARITY,HALFCARRY
; Phase E: write the map and the symbol file the options ask for.

PE_RUN:                        ; Called after publication.
    LD   A,(OP_FLAGS)              ; Option M:
    AND  OF_M                      ; the map.
    LD   (MAP_ON),A                ; Nonzero when it is written.
    LD   A,(OP_FLAGS)              ; Option Y:
    AND  OF_Y                      ; the symbol file.
    LD   (SY_ON),A                 ; Nonzero when it is written.
    LD   A,(MAP_ON)                ; Is either written?
    LD   B,A                       ; The map's bit,
    LD   A,(SY_ON)                 ; with the symbol file's,
    OR   B                         ; together.
    RET  Z                         ; Neither: Phase E has nothing to do.
    LD   (WK_NAMES),A              ; Walks reset the name readers.
    LD   IX,NM_FD                  ; The names: NAME.$NM if it exists,
    LD   A,(DIR_FD+FD_FCB)         ; on the directory's drive,
    LD   HL,CMD_NAME               ; NAME,
    LD   DE,NM_TYPE                ; type $NM.
    CALL FIL_INIT                  ; Set up the FCB.
    CALL FIL_OPEN                  ; Open it; carry if it doesn't exist.
    LD   A,0                       ; 0: no program names,
    JR   C,.NONAMES                ; since it doesn't exist;
    INC  A                         ; 1: it does.
.NONAMES:                      ; A says whether NAME.$NM is open.
    LD   (NM_OPEN),A               ; For NM_RESET.
    LD   IX,NM_LIB                 ; And the library's name section,
    LD   A,(LIB_FD+FD_FCB)         ; through a further FD on the library,
    LD   HL,LIB_FILE               ; on the drive it was found on.
    LD   DE,LIB_TYPE               ; Type BRL.
    CALL FIL_INIT                  ; Set up the FCB.
    CALL FIL_OPEN                  ; Open it; a failure is not checked.
    LD   A,(MAP_ON)                ; The reports:
    OR   A                         ; the map,
    JR   Z,.NOMAP                  ; if asked for,
    LD   IX,MAP_FD                 ; NAME.MAP.
    LD   DE,MAP_TYPE               ; Its type.
    CALL .CREATE                   ; Create it.
.NOMAP:                        ; The symbol file,
    LD   A,(SY_ON)                 ; if asked for,
    OR   A                         ; is NAME.SYM.
    JR   Z,.NOSYM                  ; Not asked for.
    LD   IX,SY_FD                  ; Its FD.
    LD   DE,SY_TYPE                ; Its type.
    CALL .CREATE                   ; Create it.
.NOSYM:                        ; The map starts with its summary.
    LD   A,(MAP_ON)                ; Is the map written?
    OR   A                         ; Nonzero if so.
    CALL NZ,.SUMMARY               ; Write the summary.
    LD   A,(MAP_ON)                ; The live blobs, in address order:
    OR   A                         ; the map's heading,
    JR   Z,.LISTING                ; if it is written.
    LD   HL,MAP_FD                 ; Write to the map.
    LD   (REP_FD),HL               ; The report.
    CALL REP_LIT                   ; The heading follows.
    DB   "LIVE BLOBS",13,10        ; The section's title,
    DB   "Address  Size  Kind     Pad  Ordinal  Name",13,10,0 ; and the columns.
.LISTING:                      ; List the live blobs.
    LD   HL,(PF_BASE)              ; The first blob's padding counts
    LD   (MAP_PREV),HL             ; from the image's base.
    LD   HL,0                      ; No symbol rows
    LD   (SY_COUNT),HL             ; yet.
    LD   A,S_START                 ; START,
    CALL .LIVE                     ; listed;
    LD   A,S_TEXT                  ; TEXT,
    CALL .LIVE                     ; listed;
    LD   A,S_DATA                  ; DATA,
    CALL .LIVE                     ; listed.
    LD   HL,(IMG_END)              ; BSS's padding counts from the image's
    LD   (MAP_PREV),HL             ; end, past COPY.
    LD   A,S_BSS                   ; BSS,
    CALL .LIVE                     ; listed.
    LD   A,(MAP_ON)                ; The map's removed blobs and totals,
    OR   A                         ; if it is written.
    CALL NZ,MAP_DEAD               ; Write them.
    LD   A,(SY_ON)                 ; The symbol file's aliases,
    OR   A                         ; if it is written.
    JR   Z,.CLOSE                  ; Not written.
    LD   HL,SY_FD                  ; Write to the symbol file.
    LD   (REP_FD),HL               ; The report.
    CALL SY_ALIAS                  ; The alias rows.
    LD   HL,(SY_COUNT)             ; No rows: one empty line.
    LD   A,H                       ; Test the count
    OR   L                         ; for zero.
    CALL Z,REP_CRLF                ; An empty line.
    LD   A,$1A                     ; Control-Z ends the text,
    CALL REP_BYTE                  ; written.
    LD   IX,SY_FD                  ; Close the symbol file,
    CALL FIL_SHUT                  ; padding with Control-Z.
    JP   C,REP_FAIL                ; L-IO.
.CLOSE:                        ; The map, if written.
    LD   A,(MAP_ON)                ; Is the map written?
    OR   A                         ; Nonzero if so.
    RET  Z                         ; Phase E is done.
    LD   HL,MAP_FD                 ; A failure deletes
    LD   (REP_FD),HL               ; the map.
    LD   IX,MAP_FD                 ; Close the map,
    CALL FIL_SHUT                  ; padding with Control-Z.
    JP   C,REP_FAIL                ; L-IO.
    RET                            ; Phase E is done.

;@ROUTINE IN A CLOBBERS A,BC,DE,HL,IX,CARRY,ZERO,SIGN,PARITY,HALFCARRY
; The live passes of section A.

.LIVE:                         ; A is an S_ value.
    LD   HL,.LIVEBLOB              ; The callback for each blob.
    JP   WK_PASS                   ; Make the passes, and return.

;@ROUTINE IN DE,IX CLOBBERS A,BC,DE,HL,CARRY,ZERO,SIGN,PARITY,HALFCARRY
; Create report IX of type DE, NAME.TYP on the output drive, with its name
; as text in REP_TEXT. L-IO if the directory is full.

.CREATE:                       ; IX is MAP_FD or SY_FD, DE its type.
    PUSH DE                        ; Keep the type.
    CALL OUT_PICK                  ; HL is the output's name, A its drive.
    POP  DE                        ; DE is the type,
    PUSH DE                        ; still kept.
    CALL FIL_INIT                  ; Set up the FCB.
    CALL OUT_PICK                  ; HL is the name again.
    POP  BC                        ; BC is the type.
    LD   DE,REP_TEXT               ; The report's name as text,
    CALL FIL_TEXT                  ; replacing the last report's.
    LD   (REP_FD),IX               ; A failure now deletes this report.
    LD   A,$1A                     ; A text file's last record: Control-Z.
    CALL FIL_MAKE                  ; Create it; carry if the directory is full.
    JP   C,REP_FAIL                ; L-IO.
    RET                            ; Created.

;@ROUTINE CLOBBERS A,BC,DE,HL,IX,CARRY,ZERO,SIGN,PARITY,HALFCARRY
; Write the map's summary (linker §8.1).

.SUMMARY:                      ; The map is open.
    LD   HL,MAP_FD                 ; Write to the map.
    LD   (REP_FD),HL               ; The report.
    CALL REP_LIT                   ; The title follows.
    DB   "BASIE LINK MAP: ",0      ; Then the program's name.
    LD   HL,CMD_NAME               ; The first part's name,
    LD   B,8                       ; at most eight characters.
.NAME:                         ; HL walks the name.
    LD   A,(HL)                    ; The next character.
    CP   ' '                       ; Padding ends the name.
    JR   Z,.NAMED                  ; Done.
    CALL REP_BYTE                  ; Write the character.
    INC  HL                        ; The next.
    DJNZ .NAME                     ; Until eight are written.
.NAMED:                        ; The title line is complete.
    CALL REP_CRLF                  ; End it.
    CALL REP_LINE                  ; The label follows.
    DB   "Library",0               ; The library's file name.
    LD   HL,LIB_TEXT               ; NAME.BRL.
    CALL REP_STR                   ; Written.
    CALL REP_LINE                  ; The label follows.
    DB   "Runtime, profile",0      ; The library's identities.
    LD   HL,(LIB_HEAD+6)           ; The runtime's identity,
    CALL REP_NUM                   ; in decimal.
    CALL REP_LIT                   ; A separator follows.
    DB   ", ",0                    ; Between the two.
    LD   HL,(LIB_HEAD+10)          ; The profile's identity,
    CALL REP_NUM                   ; in decimal.
    CALL REP_LINE                  ; The label follows.
    DB   "Output",0                ; The output kind.
    LD   A,'.'                     ; A dot,
    CALL REP_BYTE                  ; written,
    LD   HL,OUT_TYPE               ; then the output's type,
    LD   B,3                       ; three characters.
.TYPE:                         ; HL walks the type.
    LD   A,(HL)                    ; The next character,
    CALL REP_BYTE                  ; written.
    INC  HL                        ; The next.
    DJNZ .TYPE                     ; Until three are written.
    CALL REP_LINE                  ; The label follows.
    DB   "Image",0                 ; The image's extent.
    LD   HL,(PF_BASE)              ; From the base,
    CALL REP_HEX                   ; in hex,
    CALL REP_LIT                   ; to
    DB   " to ",0                  ; the
    LD   HL,(IMG_END)              ; image's end,
    CALL REP_HEX                   ; in hex,
    CALL REP_LIT                   ; then
    DB   ", ",0                    ; its
    LD   HL,(IMG_END)              ; length:
    LD   DE,(PF_BASE)              ; the end
    OR   A                         ; less
    SBC  HL,DE                     ; the base,
    CALL REP_NUM                   ; in decimal,
    CALL REP_LIT                   ; in
    DB   " bytes",0                ; bytes.
    CALL REP_LINE                  ; The label follows.
    DB   "BSS",0                   ; BSS's extent, from its pseudo-object.
    LD   HL,(PS_TAB+8)             ; BSS's row: its address,
    CALL REP_HEX                   ; in hex,
    CALL REP_LIT                   ; then
    DB   ", ",0                    ; its
    LD   HL,(PS_TAB+10)            ; size, the file table included,
    CALL REP_NUM                   ; in decimal,
    CALL REP_LIT                   ; in
    DB   " bytes",0                ; bytes.
    CALL REP_LINE                  ; The label follows.
    DB   "Stack reserve",0         ; The reserve and the largest frame.
    LD   HL,(PC_STACK)             ; The reserve,
    CALL REP_NUM                   ; in decimal,
    CALL REP_LIT                   ; then
    DB   " bytes; largest frame ",0 ; the largest frame,
    LD   HL,(PA_LIMIT+2)           ; from LIMITS,
    CALL REP_NUM                   ; in decimal.
    LD   A,(PA_LIMIT+4)            ; LIMITS's flags: bit 0,
    AND  1                         ; recursion.
    JR   Z,.NOREC                  ; None.
    CALL REP_LIT                   ; Say so.
    DB   "; recursion present",0   ; The reserve is the compiler's estimate.
.NOREC:                        ; The required top.
    CALL REP_LINE                  ; The label follows.
    DB   "Required top",0          ; FREE plus the reserve.
    CALL .REQUIRED                 ; A:HL.
    CALL REP_HEX                   ; Its low 16 bits, as the reference prints.
    CALL REP_LINE                  ; The label follows.
    DB   "Image limit",0           ; The CCP's base.
    LD   HL,(PF_LIMIT)             ; The limit,
    CALL REP_HEX                   ; in hex,
    CALL REP_LIT                   ; then
    DB   ", margin ",0             ; the margin:
    LD   HL,(PF_LIMIT)             ; the limit
    LD   DE,(IMG_END)              ; less the image's end,
    XOR  A                         ; as a 24-bit
    SBC  HL,DE                     ; signed
    SBC  A,0                       ; value.
    CALL REP_SIGN                  ; In decimal.
    CALL REP_LINE                  ; The label follows.
    DB   "Nominal top",0           ; The profile's nominal top of memory.
    LD   HL,(PF_TOP)               ; The top,
    CALL REP_HEX                   ; in hex,
    CALL REP_LIT                   ; then
    DB   ", margin ",0             ; the margin:
    LD   HL,(PF_TOP)               ; Nominal top - required, 24-bit:
    XOR  A                         ; the top is 0:HL.
    CALL .MINUSREQ                 ; A:HL.
    CALL REP_SIGN                  ; In decimal.
    CALL REP_LINE                  ; The label follows.
    DB   "Under a debugger",0      ; The margin a debugger leaves.
    CALL REP_LIT                   ; The value follows.
    DB   "margin ",0               ; Only the margin.
    LD   HL,(PF_TOP)               ; The nominal top
    LD   DE,(PF_BLOCK+18)          ; less the debugger margin,
    XOR  A                         ; as a 24-bit
    SBC  HL,DE                     ; value: A is $FF
    SBC  A,A                       ; if it is negative;
    CALL .MINUSREQ                 ; less required, 24-bit.
    CALL REP_SIGN                  ; In decimal.
    CALL REP_CRLF                  ; End the line,
    JP   REP_CRLF                  ; and leave an empty one; return.

;@ROUTINE IN A,HL OUT A,HL CLOBBERS BC,DE,CARRY,ZERO,SIGN,PARITY,HALFCARRY
; Return A:HL = A:HL - REQUIRED, as a 24-bit signed value.

.MINUSREQ:                     ; A:HL is a top of memory.
    LD   B,A                       ; Keep its high byte,
    PUSH HL                        ; and its low word.
    CALL .REQUIRED                 ; A:HL is REQUIRED.
    LD   C,A                       ; C:DE = required:
    EX   DE,HL                     ; its low word in DE.
    POP  HL                        ; B:HL is the top.
    LD   A,B                       ; A:HL is the top,
    OR   A                         ; less C:DE,
    SBC  HL,DE                     ; 24
    SBC  A,C                       ; bits.
    RET                            ; A:HL is the margin.

;@ROUTINE OUT A,HL CLOBBERS DE,CARRY,ZERO,SIGN,PARITY,HALFCARRY
; Return A:HL = REQUIRED: FREE plus the stack reserve, which may reach
; $10000.

.REQUIRED:                     ; Phase C has set both.
    LD   HL,(PC_FREE)              ; FREE,
    LD   DE,(PC_STACK)             ; plus the reserve,
    XOR  A                         ; with the carry
    ADD  HL,DE                     ; going
    ADC  A,0                       ; into A.
    RET                            ; A:HL is REQUIRED.

;@ROUTINE CLOBBERS A,BC,DE,HL,CARRY,ZERO,SIGN,PARITY,HALFCARRY
; A blob of a live pass: keep the names in step, and list it if it is in
; the pass, in the map and, when it is named, in the symbol file.

.LIVEBLOB:                     ; A walk's callback.
    CALL NM_GET                    ; NM_BUF is its name, or empty.
    CALL WK_MATCH                  ; Z if it is in the pass.
    JP   NZ,REF_SKIP               ; Not in it: skip its references.
    LD   HL,(WK_ENTRY)             ; Its address:
    LD   DE,E_ADDR                 ; the entry's
    ADD  HL,DE                     ; address field,
    LD   E,(HL)                    ; low byte,
    INC  HL                        ; then
    LD   D,(HL)                    ; DE = the address.
    LD   (.BLOBADDR),DE            ; Kept.
    LD   A,(MAP_ON)                ; Is the map written?
    OR   A                         ; Nonzero if so.
    JR   Z,.SYM                    ; No: the symbol file only.
    LD   HL,MAP_FD                 ; Write to the map.
    LD   (REP_FD),HL               ; The report.
    LD   HL,(.BLOBADDR)            ; Address,
    CALL REP_HEX                   ; in hex.
    CALL REP_GAP                   ; A gap.
    LD   HL,(RD_SIZE)              ; Size,
    LD   B,5                       ; in five columns,
    CALL REP_PAD                   ; right-aligned.
    CALL REP_GAP                   ; A gap.
    LD   A,(WK_KIND)               ; Kind,
    CALL REP_KIND                  ; padded to seven.
    CALL REP_GAP                   ; A gap.
    LD   HL,(.BLOBADDR)            ; The padding paid:
    LD   DE,(MAP_PREV)             ; the address less the previous end,
    OR   A                         ; clear carry,
    SBC  HL,DE                     ; subtracted,
    LD   B,3                       ; in three columns,
    CALL REP_PAD                   ; right-aligned.
    CALL REP_GAP                   ; A gap.
    LD   HL,(RD_PREV)              ; Ordinal,
    CALL REP_HEX                   ; in hex.
    CALL REP_GAP                   ; Two gaps,
    CALL REP_GAP                   ; under the heading.
    LD   HL,NM_BUF                 ; Name,
    CALL REP_STR                   ; or nothing.
    CALL REP_CRLF                  ; The row is done.
.SYM:                          ; The next padding counts from this blob's end.
    LD   HL,(.BLOBADDR)            ; Its address
    LD   DE,(RD_SIZE)              ; plus its size
    ADD  HL,DE                     ; is its end,
    LD   (MAP_PREV),HL             ; kept.
    LD   A,(SY_ON)                 ; Is the symbol file written?
    OR   A                         ; Nonzero if so.
    JP   Z,REF_SKIP                ; No: skip the references.
    LD   A,(NM_BUF)                ; Is the blob named?
    OR   A                         ; An empty name means not.
    JP   Z,REF_SKIP                ; Unnamed: no row.
    LD   HL,SY_FD                  ; Write to the symbol file.
    LD   (REP_FD),HL               ; The report.
    LD   HL,(.BLOBADDR)            ; Its address,
    CALL SY_ROW                    ; and its name.
    JP   REF_SKIP                  ; Skip the references.

.BLOBADDR:                     ; The listed blob's address.
    DW   0                         ; Set by .LIVEBLOB.

;@ROUTINE IN HL CLOBBERS A,B,HL,CARRY,ZERO,SIGN,PARITY,HALFCARRY
; Write a symbol row: address HL in four hex digits, a space, and the name
; in NM_BUF to 16 characters.

SY_ROW:                        ; HL is the address.
    CALL REP_WORD                  ; Four hex digits.
    LD   A,' '                     ; A space,
    CALL REP_BYTE                  ; written.
    LD   HL,NM_BUF                 ; The name,
    LD   B,16                      ; at most 16 characters.
.CH:                           ; HL walks the name.
    LD   A,(HL)                    ; The next character.
    OR   A                         ; The end?
    JR   Z,.END                    ; The name is written.
    CALL REP_BYTE                  ; Write it.
    INC  HL                        ; The next.
    DJNZ .CH                       ; Until 16 are written.
.END:                          ; The row is done.
    CALL REP_CRLF                  ; End it.
    LD   HL,(SY_COUNT)             ; One more
    INC  HL                        ; row
    LD   (SY_COUNT),HL             ; written.
    RET                            ; Done.

;@ROUTINE CLOBBERS A,BC,DE,HL,IX,CARRY,ZERO,SIGN,PARITY,HALFCARRY
; Write the symbol file's alias rows: each live named alias, in address
; order, and at one address in ordinal order. Aliases are rare, so each
; round scans the table for the lowest live alias, writes it and clears its
; live bit; its name is found by a scan of its owner's names.

SY_ALIAS:                      ; The symbol file is the report.
    LD   HL,0                      ; None found yet:
    LD   (.POS),HL                 ; position 0 is never an alias.
.SCAN:                         ; HL walks every position.
    PUSH HL                        ; Keep it.
    CALL TAB_AT                    ; HL is its entry; carry past the end.
    JR   C,.SCANNED                ; Every entry is seen.
    LD   A,(HL)                    ; Its flags:
    AND  EF_ALIAS+EF_LIVE          ; an alias that Phase C placed
    CP   EF_ALIAS+EF_LIVE          ; and that is not yet written?
    JR   NZ,.NEXT                  ; No.
    INC  HL                        ; Its address,
    INC  HL                        ; three
    INC  HL                        ; bytes on:
    LD   E,(HL)                    ; low byte,
    INC  HL                        ; then
    LD   D,(HL)                    ; DE = its address.
    LD   HL,(.POS)                 ; The first found
    LD   A,H                       ; is the best
    OR   L                         ; so far.
    JR   Z,.BEST                   ; The first.
    LD   HL,(.ADDR)                ; Is it below the best so far?
    OR   A                         ; Clear carry for the subtraction.
    SBC  HL,DE                     ; Carry or zero if not:
    JR   C,.NEXT                   ; above it,
    JR   Z,.NEXT                   ; or at it, after it in the table.
.BEST:                         ; The best so far.
    LD   (.ADDR),DE                ; Its address,
    POP  HL                        ; and its position,
    PUSH HL                        ; still kept,
    LD   (.POS),HL                 ; for its name.
.NEXT:                         ; The position is on the stack.
    POP  HL                        ; HL is the position.
    INC  HL                        ; The next.
    JR   .SCAN                     ; Go on.
.SCANNED:                      ; The position is on the stack.
    POP  HL                        ; Drop it.
    LD   HL,(.POS)                 ; Was an alias found?
    LD   A,H                       ; Position 0
    OR   L                         ; if not.
    RET  Z                         ; Every alias is written.
    PUSH HL                        ; Keep the position.
    CALL TAB_AT                    ; HL is its entry.
    RES  5,(HL)                    ; Written: no longer live.
    POP  HL                        ; Its name, by a scan of its owner's names:
    CALL TAB_ORD                   ; HL is its ordinal,
    LD   (RD_PREV),HL              ; which NM_GET matches.
    LD   A,H                       ; Its owner:
    CP   $04                       ; below $0400,
    LD   A,0                       ; the library,
    JR   C,.OWN                    ; 0;
    INC  A                         ; else the program, 1.
.OWN:                          ; A is the owner.
    LD   (WK_OWN),A                ; NM_GET reads its names.
    CALL NM_RESET                  ; From the first record.
.FIND:                         ; Scan the owner's names.
    CALL NM_GET                    ; NM_BUF is the name if the record matches.
    LD   A,(NM_BUF)                ; Found?
    OR   A                         ; A name is nonempty.
    JR   NZ,.ROW                   ; Write the row.
    CALL NM_FLAG                   ; Not this record: the next, until the end.
    LD   A,(HL)                    ; Names left?
    OR   A                         ; Zero at the end.
    JR   Z,SY_ALIAS                ; An unnamed alias: no row.
    CALL NM_READ                   ; The next record.
    JR   .FIND                     ; Try it.
.ROW:                          ; NM_BUF is the alias's name.
    LD   HL,(.ADDR)                ; Its address,
    CALL SY_ROW                    ; and its name.
    JR   SY_ALIAS                  ; The next alias.

.ADDR:                         ; The lowest address found in this round.
    DW   0                         ; Valid once .POS is set.
.POS:                          ; Its table position.
    DW   0                         ; 0 until an alias is found.

;@ROUTINE CLOBBERS A,BC,DE,HL,IX,CARRY,ZERO,SIGN,PARITY,HALFCARRY
; Write the map's removed blobs, in directory order, then the totals.

MAP_DEAD:                      ; The map is open.
    LD   HL,MAP_FD                 ; Write to the map.
    LD   (REP_FD),HL               ; The report.
    CALL REP_LIT                   ; The heading follows.
    DB   13,10,"REMOVED BLOBS",13,10 ; An empty line, the section's title,
    DB   "Ordinal  Size  Kind     Name",13,10,0 ; and the columns.
    LD   HL,LIB_KEPT               ; The four totals
    LD   B,12                      ; start at zero,
.ZERO:                         ; HL walks their twelve bytes.
    LD   (HL),0                    ; Clear one.
    INC  HL                        ; The next.
    DJNZ .ZERO                     ; Until all are clear.
    LD   HL,MAP_ADD                ; Each blob,
    LD   (WK_EACH),HL              ; live or not,
    CALL WK_BOTH                   ; in directory order.
    CALL REP_LIT                   ; The totals follow.
    DB   13,10,"TOTALS",13,10      ; An empty line, the title,
    DB   "Program   kept ",0       ; and the program's.
    LD   HL,PRG_KEPT               ; Kept bytes,
    CALL .TOTAL                    ; in decimal.
    CALL REP_LIT                   ; Then
    DB   ", removed ",0            ; removed
    LD   HL,PRG_GONE               ; bytes,
    CALL .TOTAL                    ; in decimal.
    CALL REP_LIT                   ; The library's line.
    DB   13,10,"Library   kept ",0 ; Its kept bytes,
    LD   HL,LIB_KEPT               ; the total,
    CALL .TOTAL                    ; in decimal.
    CALL REP_LIT                   ; Then
    DB   ", removed ",0            ; removed
    LD   HL,LIB_GONE               ; bytes,
    CALL .TOTAL                    ; in decimal.
    JP   REP_CRLF                  ; End the line; return.

;@ROUTINE IN HL CLOBBERS A,BC,DE,HL,CARRY,ZERO,SIGN,PARITY,HALFCARRY
; Write the 24-bit total at HL in decimal.

.TOTAL:                        ; HL is LIB_KEPT, LIB_GONE, PRG_KEPT or PRG_GONE.
    LD   E,(HL)                    ; Its low byte,
    INC  HL                        ; then
    LD   D,(HL)                    ; its middle byte,
    INC  HL                        ; then
    LD   A,(HL)                    ; its high byte, in A.
    EX   DE,HL                     ; A:HL is the total,
    JP   REP_SIGN                  ; written; return.

LIB_KEPT:                      ; The library's live bytes.
    DS   3                         ; 24 bits.
LIB_GONE:                      ; The library's removed bytes.
    DS   3                         ; 24 bits.
PRG_KEPT:                      ; The program's live bytes; six bytes on.
    DS   3                         ; 24 bits.
PRG_GONE:                      ; The program's removed bytes.
    DS   3                         ; 24 bits.

;@ROUTINE CLOBBERS A,BC,DE,HL,CARRY,ZERO,SIGN,PARITY,HALFCARRY
; A blob of the removed pass: add its size to its owner's kept or removed
; total, and list it when it is not live.

MAP_ADD:                       ; A walk's callback.
    CALL NM_GET                    ; NM_BUF is its name, or empty.
    LD   HL,(WK_ENTRY)             ; Is it live?
    BIT  5,(HL)                    ; EF_LIVE.
    LD   HL,LIB_KEPT               ; The right total: owner, kept or removed.
    JR   NZ,.KEPT                  ; Live: kept.
    LD   HL,LIB_GONE               ; Dead: removed.
.KEPT:                         ; HL is the library's total of that fate.
    LD   A,(WK_OWN)                ; The program's?
    OR   A                         ; Owner 1.
    JR   Z,.ADD                    ; The library's.
    LD   DE,6                      ; PRG_KEPT and PRG_GONE follow LIB_KEPT
    ADD  HL,DE                     ; and LIB_GONE by six bytes.
.ADD:                          ; HL is the total, 24 bits.
    LD   DE,(RD_SIZE)              ; The blob's size,
    LD   A,(HL)                    ; added
    ADD  A,E                       ; to the low byte,
    LD   (HL),A                    ; kept;
    INC  HL                        ; then
    LD   A,(HL)                    ; to the middle byte,
    ADC  A,D                       ; with the carry,
    LD   (HL),A                    ; kept;
    INC  HL                        ; and the carry
    LD   A,(HL)                    ; into
    ADC  A,0                       ; the high byte,
    LD   (HL),A                    ; kept.
    LD   HL,(WK_ENTRY)             ; Live?
    BIT  5,(HL)                    ; EF_LIVE.
    JP   NZ,REF_SKIP               ; A live blob isn't listed here.
    LD   HL,(RD_PREV)              ; Ordinal,
    CALL REP_HEX                   ; in hex.
    CALL REP_GAP                   ; A gap.
    LD   HL,(RD_SIZE)              ; Size,
    LD   B,5                       ; in five columns,
    CALL REP_PAD                   ; right-aligned.
    CALL REP_GAP                   ; A gap.
    LD   A,(WK_KIND)               ; Kind,
    CALL REP_KIND                  ; padded to seven.
    CALL REP_GAP                   ; A gap.
    LD   HL,NM_BUF                 ; Name,
    CALL REP_STR                   ; or nothing.
    CALL REP_CRLF                  ; The row is done.
    JP   REF_SKIP                  ; Skip the references.
