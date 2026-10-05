;==========================================================================
;  Phase E: report text and the name readers
;==========================================================================
;
;  Phase E (linker §8, PHASEE.ASM) writes the map (option M) and the symbol
;  file (option Y) after publication. This part holds Phase E's workspace,
;  the routines that write report text, and the name readers.
;
;  Principal entries:
;    REP_BYTE  write a byte to the report at REP_FD (REP_STR a string,
;              REP_LIT the string after the CALL, REP_CRLF a line end)
;    REP_LINE  start a line of the map's summary with its padded label
;    REP_HEX   write "$" and four hex digits (REP_WORD without the "$")
;    REP_NUM, REP_PAD, REP_SIGN, REP_DEC  write a number in decimal
;    REP_KIND  write a blob kind's name
;    REP_FAIL  delete a report that can't be written, report L-IO and stop
;    NM_RESET  restart an owner's name reader; NM_GET the current blob's name
;
;  Names come from the program's name stream, NAME.$NM, and the library's
;  name section, each read forward in step with its directory: both hold
;  one record per named blob, in directory order (object format §9). Each
;  owner's reader holds one pending record, its ordinal in NM_ORD and its
;  name in NM_PEND; a blob takes the pending name when the ordinals match,
;  and the reader moves on. The readers check neither the header's magic
;  and stamp nor the trailer's CRC.
;
;  Memory: the reports' FDs share memory with Phase D's, which are finished
;  with by publication: the library's byte section, the byte stream, the
;  line stream and the line table (publication leaves LT_MADE clear). The
;  name buffers and the digits lie in Phase D's output FD.

MAP_FD EQU  SRC_LIB            ; The map, NAME.MAP.
MAP_TYPE:                      ; Its type.
    DB   "MAP"                     ; Three characters.
SY_FD EQU  SRC_PROG            ; The symbol file, NAME.SYM.
SY_TYPE:                       ; Its type.
    DB   "SYM"                     ; Three characters.
NM_FD EQU  LN_FD               ; The program's name stream, NAME.$NM.
NM_TYPE:                       ; Its type.
    DB   "$NM"                     ; Three characters.
NM_LIB EQU  LT_FD              ; The library again, for its name section.
REP_FD:                        ; The report being written: MAP_FD or SY_FD.
    DW   0                         ; Set before each piece of output.
MAP_ON:                        ; Nonzero when the map is written (option M).
    DB   0                         ; OF_M's bit.
SY_ON:                         ; Nonzero when the symbol file is written (Y).
    DB   0                         ; OF_Y's bit.
SY_COUNT:                      ; The symbol file's rows.
    DW   0                         ; None: one empty line instead.
MAP_PREV:                      ; The end of the last live blob listed.
    DW   0                         ; The next blob's padding is counted from it.
NM_HAVE:                       ; Per owner: 1 while names remain.
    DS   2                         ; Library, then program.
NM_ORD:                        ; Per owner: the pending record's ordinal.
    DS   4                         ; Library, then program.
NM_PEND EQU  OUT_FD            ; Per owner: its name, zero-terminated (2 x 32).
NM_BUF EQU  OUT_FD+64          ; The current blob's name, or empty (33).
REP_BUF EQU  OUT_FD+97         ; A number's digits (10); all three in Phase D's
                               ; output FD, free after publication.
KIND_TAB:                      ; The kinds' names, seven characters each.
    DB   "code   rodata data   bss    startup" ; Kinds 0 to 4, space-padded.

; ---- writing text ------------------------------------------------------------

;@ROUTINE IN A CLOBBERS CARRY,ZERO,SIGN,PARITY,HALFCARRY
; Write A to the report being written, keeping every register. A full disk
; ends the run through REP_FAIL.

REP_BYTE:                      ; REP_FD is the report.
    PUSH IX                        ; Keep the caller's FD.
    LD   IX,(REP_FD)               ; The report.
    CALL FIL_PUTB                  ; Write A; carry if the disk is full.
    POP  IX                        ; Recover IX.
    RET  NC                        ; Written.
    JP   REP_FAIL                  ; Delete the report and stop.

;@ROUTINE IN HL OUT HL CLOBBERS A,CARRY,ZERO,SIGN,PARITY,HALFCARRY
; Write the zero-terminated string at HL, leaving HL at its zero. Keeps BC
; and DE.

REP_STR:                       ; HL is the string.
    LD   A,(HL)                    ; The next character.
    OR   A                         ; The terminator?
    RET  Z                         ; HL is at the zero.
    CALL REP_BYTE                  ; Write the character.
    INC  HL                        ; The next.
    JR   REP_STR                   ; Go on.

;@ROUTINE CLOBBERS A,CARRY,ZERO,SIGN,PARITY,HALFCARRY
; Write the zero-terminated string that follows the CALL, and return past
; it. Keeps BC, DE and HL.

REP_LIT:                       ; The string follows the CALL.
    EX   (SP),HL                   ; HL is the string; the caller's HL is kept.
    CALL REP_STR                   ; Write it; HL is at its zero.
    INC  HL                        ; Past the zero: the return address.
    EX   (SP),HL                   ; Return there, recovering HL.
    RET                            ; Past the string.

;@ROUTINE CLOBBERS A,B,CARRY,ZERO,SIGN,PARITY,HALFCARRY
; Start a line of the summary: CR LF, then the zero-terminated label that
; follows the CALL, padded with spaces to 19 columns. Keeps HL.

REP_LINE:                      ; The label follows the CALL.
    CALL REP_CRLF                  ; End the previous line.
    EX   (SP),HL                   ; HL is the label; the caller's HL is kept.
    LD   B,19                      ; The column width.
.CH:                           ; HL walks the label, B counts columns left.
    LD   A,(HL)                    ; The next character.
    INC  HL                        ; Past it, the zero included.
    OR   A                         ; The end of the label?
    JR   Z,.PAD                    ; Pad the rest.
    CALL REP_BYTE                  ; Write the character.
    DEC  B                         ; One column fewer; labels are under 19.
    JR   .CH                       ; Go on.
.PAD:                          ; B columns are left.
    LD   A,' '                     ; A space,
    CALL REP_BYTE                  ; written.
    DJNZ .PAD                      ; Until column 19.
    EX   (SP),HL                   ; Return past the label, recovering HL.
    RET                            ; The value follows on the line.

;@ROUTINE CLOBBERS A,CARRY,ZERO,SIGN,PARITY,HALFCARRY
; Write two spaces, between the columns of a blob's row.

REP_GAP:                       ; Between two columns.
    CALL REP_LIT                   ; The spaces follow.
    DB   "  ",0                    ; Two spaces.
    RET                            ; Written.

;@ROUTINE CLOBBERS A,CARRY,ZERO,SIGN,PARITY,HALFCARRY
; End the report's line with CR LF.

REP_CRLF:                      ; At the end of each line.
    LD   A,13                      ; A carriage return,
    CALL REP_BYTE                  ; written.
    LD   A,10                      ; A line feed,
    JR   REP_BYTE                  ; written; return.

;@ROUTINE IN HL CLOBBERS A,CARRY,ZERO,SIGN,PARITY,HALFCARRY
; Write "$" and HL in four hex digits.

REP_HEX:                       ; HL is an address or ordinal.
    LD   A,'$'                     ; The hex sign,
    CALL REP_BYTE                  ; written; fall into REP_WORD.

;@ROUTINE IN HL CLOBBERS A,CARRY,ZERO,SIGN,PARITY,HALFCARRY
; Write HL in four hex digits.

REP_WORD:                      ; HL is the value.
    LD   A,H                       ; The high byte,
    CALL .HEX2                     ; in two digits.
    LD   A,L                       ; The low byte, in two digits.

;@ROUTINE IN A CLOBBERS A,CARRY,ZERO,SIGN,PARITY,HALFCARRY
; Write A in two hex digits.

.HEX2:                         ; A is the byte.
    PUSH AF                        ; Keep it for the low digit.
    RRCA                           ; Bring the high four bits
    RRCA                           ; down
    RRCA                           ; to the
    RRCA                           ; low four.
    CALL .HEX1                     ; Write the high digit.
    POP  AF                        ; The byte again; write its low digit.

;@ROUTINE IN A CLOBBERS A,CARRY,ZERO,SIGN,PARITY,HALFCARRY
; Write the hex digit for A's low four bits.

.HEX1:                         ; A's low four bits are the digit.
    CALL LK_DIGIT                  ; A is its character.
    JR   REP_BYTE                  ; Written; return.

;@ROUTINE IN HL CLOBBERS A,BC,DE,HL,CARRY,ZERO,SIGN,PARITY,HALFCARRY
; Write the unsigned value HL in decimal, unpadded.

REP_NUM:                       ; HL is the value.
    LD   B,0                       ; No padding; fall into REP_PAD.

;@ROUTINE IN B,HL CLOBBERS A,BC,DE,HL,CARRY,ZERO,SIGN,PARITY,HALFCARRY
; Write the unsigned value HL in decimal, right-aligned in B columns.

REP_PAD:                       ; B is the width.
    XOR  A                         ; A:HL is HL, unsigned.
    JR   REP_DEC                   ; Write it.

;@ROUTINE IN A,HL CLOBBERS A,BC,DE,HL,CARRY,ZERO,SIGN,PARITY,HALFCARRY
; Write the signed value A:HL, as REP_DEC does, unpadded.

REP_SIGN:                      ; A:HL is the value.
    LD   B,0                       ; No padding; fall into REP_DEC.

;@ROUTINE IN A,B,HL CLOBBERS A,BC,DE,HL,CARRY,ZERO,SIGN,PARITY,HALFCARRY
; Write the 24-bit two's-complement value A:HL in decimal, right-aligned
; in B columns (0: no padding). Keeps IX.

REP_DEC:                       ; A:HL is the value, B the width.
    PUSH IX                        ; .DIGITS walks the powers with IX.
    CALL .DIGITS                   ; Write the number.
    POP  IX                        ; Recover IX.
    RET                            ; Written.

;@ROUTINE IN A,B,HL CLOBBERS A,BC,DE,HL,IX,CARRY,ZERO,SIGN,PARITY,HALFCARRY
; REP_DEC without keeping IX: build the digits in REP_BUF, then write them
; after any padding. Magnitudes of a million or more, which no report
; prints, would give a first digit past '9'.

.DIGITS:                       ; A:HL is the value, B the width.
    PUSH BC                        ; Keep the width.
    LD   DE,REP_BUF                ; DE builds the text.
    BIT  7,A                       ; Negative?
    JR   Z,.POS                    ; No.
    LD   C,A                       ; Negate A:HL:
    LD   A,L                       ; complement
    CPL                            ; the low byte,
    LD   L,A                       ; L,
    LD   A,H                       ; the middle
    CPL                            ; byte,
    LD   H,A                       ; H,
    LD   A,C                       ; and the high
    CPL                            ; byte, A;
    LD   BC,1                      ; then add one,
    ADD  HL,BC                     ; to HL,
    ADC  A,0                       ; carrying into A.
    PUSH AF                        ; Keep the high byte.
    LD   A,'-'                     ; A minus sign
    LD   (DE),A                    ; begins the text.
    INC  DE                        ; The digits follow.
    POP  AF                        ; A is the high byte.
.POS:                          ; A:HL is the magnitude.
    LD   C,A                       ; C:HL = the magnitude.
    LD   IX,.POWERS                ; The powers of ten, largest first.
    LD   B,0                       ; B = 1 once a digit has been written.
.POW:                          ; IX is a power, three bytes.
    LD   A,(IX+0)                  ; Is it the zero
    OR   (IX+1)                    ; that ends
    OR   (IX+2)                    ; the table?
    JR   Z,.LAST                   ; Then only the units remain.
    PUSH DE                        ; Keep the text pointer.
    LD   E,'0'-1                   ; E counts the subtractions, as a character.
.SUB:                          ; Subtract the power until C:HL goes negative.
    INC  E                         ; One more subtraction.
    LD   A,L                       ; The low byte,
    SUB  (IX+0)                    ; less the power's,
    LD   L,A                       ; kept;
    LD   A,H                       ; the middle byte,
    SBC  A,(IX+1)                  ; less the power's with the borrow,
    LD   H,A                       ; kept;
    LD   A,C                       ; the high byte,
    SBC  A,(IX+2)                  ; less the power's with the borrow,
    LD   C,A                       ; kept.
    JR   NC,.SUB                   ; While C:HL stays at or above zero.
    LD   A,L                       ; Add the power back:
    ADD  A,(IX+0)                  ; the low byte,
    LD   L,A                       ; kept;
    LD   A,H                       ; the middle byte,
    ADC  A,(IX+1)                  ; with the carry,
    LD   H,A                       ; kept;
    LD   A,C                       ; the high byte,
    ADC  A,(IX+2)                  ; with the carry,
    LD   C,A                       ; kept.
    LD   A,E                       ; A is the digit.
    POP  DE                        ; DE is the text pointer.
    CP   '0'                       ; A zero?
    JR   NZ,.DIGIT                 ; Other digits are always written.
    INC  B                         ; Test B for zero,
    DEC  B                         ; keeping it.
    JR   Z,.NEXT                   ; A leading zero.
.DIGIT:                        ; A is a digit to write.
    LD   (DE),A                    ; Into the text.
    INC  DE                        ; The next place.
    LD   B,1                       ; From here every zero is written.
.NEXT:                         ; The next power.
    INC  IX                        ; Three bytes
    INC  IX                        ; per
    INC  IX                        ; power.
    JR   .POW                      ; Go on.
.LAST:                         ; L is the units, 0 to 9.
    LD   A,L                       ; Its character:
    ADD  A,'0'                     ; always written.
    LD   (DE),A                    ; Into the text.
    INC  DE                        ; The next place.
    XOR  A                         ; A zero
    LD   (DE),A                    ; ends the text.
    POP  BC                        ; B = the width: pad on the left.
    LD   HL,REP_BUF                ; Measure the text.
    PUSH HL                        ; Keep its start.
    LD   C,0                       ; C is the length.
.LEN:                          ; HL walks the text.
    LD   A,(HL)                    ; The next character.
    OR   A                         ; The end?
    JR   Z,.PAD                    ; C is the length.
    INC  C                         ; One more.
    INC  HL                        ; The next.
    JR   .LEN                      ; Go on.
.PAD:                          ; Pad while C is below the width.
    LD   A,C                       ; The length so far.
    CP   B                         ; Below the width?
    JR   NC,.TEXT                  ; No: write the text.
    LD   A,' '                     ; A space,
    CALL REP_BYTE                  ; written.
    INC  C                         ; One column more.
    JR   .PAD                      ; Go on.
.TEXT:                         ; The text's start is on the stack.
    POP  HL                        ; HL is the text.
    JP   REP_STR                   ; Write it; return.
.POWERS:                       ; Three-byte powers of ten, low byte first.
    DB   $A0,$86,$01               ; 100000.
    DB   $10,$27,$00               ; 10000.
    DB   $E8,$03,$00               ; 1000.
    DB   $64,$00,$00               ; 100.
    DB   $0A,$00,$00               ; 10.
    DB   0,0,0                     ; The end of the table.

;@ROUTINE IN A CLOBBERS A,B,DE,HL,CARRY,ZERO,SIGN,PARITY,HALFCARRY
; Write the name of kind A, padded to 7 characters.

REP_KIND:                      ; A is a kind, 0 to 4.
    LD   L,A                       ; Keep the kind.
    ADD  A,A                       ; Times 2,
    ADD  A,A                       ; times 4,
    ADD  A,A                       ; times 8,
    SUB  L                         ; less one: A * 7.
    LD   E,A                       ; DE is the name's offset,
    LD   D,0                       ; zero-extended.
    LD   HL,KIND_TAB               ; From the names' start,
    ADD  HL,DE                     ; HL is the name.
    LD   B,7                       ; Seven characters, padding included.
.CH:                           ; HL walks the name.
    LD   A,(HL)                    ; The next character,
    CALL REP_BYTE                  ; written.
    INC  HL                        ; The next.
    DJNZ .CH                       ; Until seven are written.
    RET                            ; Written.

;@ROUTINE NORETURN
; A report could not be written: delete it, report L-IO, delete the
; intermediates and end the run with RC_DISK. The published program stands.
; REP_TEXT names the report opened last, which is not always the one that
; failed, and the other report, if open, is left unclosed.

REP_FAIL:                      ; REP_FD is the report that failed.
    LD   IX,(REP_FD)               ; Its FD.
    CALL FIL_DEL                   ; Delete it.
    LD   HL,222                    ; L-IO.
    LD   DE,REP_TEXT               ; The report's name
    LD   (DG_ARG1),DE              ; is argument 1.
    CALL DG_ERROR                  ; Report it.
    CALL PUB_TIDY                  ; Delete the intermediates, unless K.
    LD   DE,RC_DISK                ; A disk failure's return code.
    JP   CPM_EXIT                  ; End the run.
REP_TEXT:                      ; A report's name as text.
    DS   13                        ; Written by each .CREATE in turn.

; ---- names -------------------------------------------------------------------

;@ROUTINE IN A CLOBBERS A,B,DE,HL,IX,CARRY,ZERO,SIGN,PARITY,HALFCARRY
; Point the name reader of owner A (0 library, 1 program) at its first
; record, if it has names at all, and read that record.

NM_RESET:                      ; Called at the start of each walk in Phase E.
    LD   (NM_OWN),A                ; The owner.
    CALL NM_FLAG                   ; HL = its have flag.
    LD   (HL),0                    ; No names until the header is read.
    LD   A,(NM_OWN)                ; Which owner?
    OR   A                         ; 0 is the library.
    JR   NZ,.PROG                  ; The program's.
    LD   HL,(LIB_HEAD+24)          ; The library's name section, or 0:
    LD   A,(LIB_HEAD+26)           ; a 24-bit offset,
    LD   B,A                       ; whose high byte is kept in B.
    OR   H                         ; Is it zero?
    OR   L                         ; Then the library has no names.
    RET  Z                         ; No names.
    LD   A,B                       ; A:HL is the offset.
    LD   IX,NM_LIB                 ; The library's second FD.
    JR   .SEEK                     ; Go there.
.PROG:                         ; The program's names.
    LD   A,(NM_OPEN)               ; Was NAME.$NM found?
    OR   A                         ; Zero if not.
    RET  Z                         ; No names.
    LD   IX,NM_FD                  ; NAME.$NM,
    XOR  A                         ; from
    LD   HL,0                      ; its start.
.SEEK:                         ; A:HL is the names' offset in IX's file.
    CALL FIL_SEEK                  ; Go there.
    RET  C                         ; Beyond the file: no names.
    LD   B,8                       ; The header: magic, version, stamp,
.HEAD:                         ; skipped unchecked.
    CALL FIL_GETB                  ; A header byte.
    RET  C                         ; Too short: no names.
    DJNZ .HEAD                     ; Until all eight are skipped.
    CALL NM_FLAG                   ; HL is the have flag.
    LD   (HL),1                    ; Names remain.
    JR   NM_READ                   ; Read the first record; return.

NM_OWN:                        ; The owner whose reader is in use.
    DB   0                         ; 0 library, 1 program.
NM_OPEN:                       ; 1 when NAME.$NM was found.
    DB   0                         ; The program may have no names.

;@ROUTINE OUT HL CLOBBERS A,CARRY,ZERO,SIGN,PARITY,HALFCARRY
; Return HL = the have flag of NM_OWN.

NM_FLAG:                       ; NM_OWN is 0 or 1.
    LD   HL,NM_HAVE                ; The flags' start,
    LD   A,(NM_OWN)                ; plus the owner,
    ADD  A,L                       ; added
    LD   L,A                       ; to L,
    RET  NC                        ; with any carry
    INC  H                         ; into H.
    RET                            ; HL is the flag.

;@ROUTINE OUT IX CLOBBERS A,CARRY,ZERO,SIGN,PARITY,HALFCARRY
; Return IX = the FD of NM_OWN's names.

NM_PICK:                       ; NM_OWN is 0 or 1.
    LD   IX,NM_LIB                 ; The library's,
    LD   A,(NM_OWN)                ; for owner
    OR   A                         ; 0.
    RET  Z                         ; The library.
    LD   IX,NM_FD                  ; The program's.
    RET                            ; NAME.$NM.

;@ROUTINE CLOBBERS A,B,DE,HL,IX,CARRY,ZERO,SIGN,PARITY,HALFCARRY
; Read NM_OWN's next record into its pending slot; at the end (ordinal 0)
; or at the end of the file, its have flag clears. A name longer than its
; 31-byte slot is not refused.

NM_READ:                       ; NM_OWN's reader is at a record.
    CALL NM_PICK                   ; IX is its file.
    CALL FIL_GETW                  ; The record's ordinal.
    JR   C,.END                    ; The file ended.
    LD   A,H                       ; Ordinal 0
    OR   L                         ; begins the trailer.
    JR   Z,.END                    ; No more names.
    PUSH HL                        ; The ordinal into NM_ORD + owner * 2.
    LD   A,(NM_OWN)                ; The owner,
    ADD  A,A                       ; times two,
    LD   E,A                       ; is the offset,
    LD   D,0                       ; zero-extended.
    LD   HL,NM_ORD                 ; From the ordinals' start,
    ADD  HL,DE                     ; HL is the owner's.
    POP  DE                        ; DE is the ordinal.
    LD   (HL),E                    ; Keep it,
    INC  HL                        ; low byte
    LD   (HL),D                    ; first.
    CALL NM_SLOT                   ; HL = the name buffer.
    CALL NM_PICK                   ; IX is the file again.
    CALL FIL_GETB                  ; The length.
    JR   C,.END                    ; The file ended.
    LD   B,A                       ; B counts the characters.
.CH:                           ; HL walks the slot.
    LD   A,B                       ; Any left?
    OR   A                         ; Zero when done.
    JR   Z,.DONE                   ; The name is read.
    CALL FIL_GETB                  ; A character.
    JR   C,.END                    ; The file ended.
    LD   (HL),A                    ; Store it.
    INC  HL                        ; The next place.
    DEC  B                         ; One fewer.
    JR   .CH                       ; Go on.
.DONE:                         ; HL is past the name.
    LD   (HL),0                    ; Terminate it.
    RET                            ; A record is pending.
.END:                          ; No more names for this owner.
    CALL NM_FLAG                   ; Its have flag
    LD   (HL),0                    ; clears.
    RET                            ; Its blobs have no names.

;@ROUTINE OUT HL CLOBBERS A,DE,CARRY,ZERO,SIGN,PARITY,HALFCARRY
; Return HL = NM_OWN's pending name buffer.

NM_SLOT:                       ; NM_OWN is 0 or 1.
    LD   HL,NM_PEND                ; The library's slot,
    LD   A,(NM_OWN)                ; for owner
    OR   A                         ; 0.
    RET  Z                         ; The library's.
    LD   DE,32                     ; The program's is
    ADD  HL,DE                     ; 32 bytes on.
    RET                            ; HL is the slot.

;@ROUTINE CLOBBERS A,B,DE,HL,CARRY,ZERO,SIGN,PARITY,HALFCARRY
; Set NM_BUF to the name of the blob just read (RD_PREV) of owner WK_OWN,
; taken from its reader if the pending record is this blob's, else empty.
; The reader moves on past a match, and past an alias's record, which the
; walks never meet; any other record waits for its blob.

NM_GET:                        ; A walk's callback keeps IX on its directory.
    PUSH IX                        ; Keep it.
    CALL .FETCH                    ; Fetch the name.
    POP  IX                        ; Recover it.
    RET                            ; NM_BUF is the name, or empty.

;@ROUTINE CLOBBERS A,B,DE,HL,IX,CARRY,ZERO,SIGN,PARITY,HALFCARRY
; NM_GET without keeping IX.

.FETCH:                        ; RD_PREV and WK_OWN are the blob's.
    LD   A,(WK_OWN)                ; The blob's owner
    LD   (NM_OWN),A                ; selects the reader.
    XOR  A                         ; No name
    LD   (NM_BUF),A                ; unless one is found.
    CALL NM_FLAG                   ; Does the owner have names left?
    LD   A,(HL)                    ; Its have flag.
    OR   A                         ; Zero if not.
    RET  Z                         ; No names.
    LD   A,(NM_OWN)                ; The pending ordinal:
    ADD  A,A                       ; NM_ORD
    LD   E,A                       ; plus the
    LD   D,0                       ; owner
    LD   HL,NM_ORD                 ; times
    ADD  HL,DE                     ; two.
    LD   E,(HL)                    ; Its low byte,
    INC  HL                        ; then
    LD   D,(HL)                    ; DE is the ordinal.
    LD   HL,(RD_PREV)              ; The blob's ordinal.
    OR   A                         ; Clear carry for the subtraction.
    SBC  HL,DE                     ; Are they the same?
    JR   Z,.MINE                   ; This blob's name.
    EX   DE,HL                     ; HL is the pending ordinal.
    CALL TAB_FIND                  ; Its entry; carry if it has none.
    RET  C                         ; Not a blob's or an alias's.
    BIT  6,(HL)                    ; An alias's name?
    RET  Z                         ; A later blob's: it waits.
    CALL NM_READ                   ; Pass it: the walks skip ALIAS records.
    JR   .FETCH                    ; Try the next.
.MINE:                         ; The pending record is this blob's.
    CALL NM_SLOT                   ; HL is the pending name.
    LD   DE,NM_BUF                 ; Copy it to NM_BUF.
.COPY:                         ; HL walks the slot, DE the buffer.
    LD   A,(HL)                    ; A character,
    LD   (DE),A                    ; copied,
    INC  HL                        ; the next
    INC  DE                        ; places,
    OR   A                         ; until the zero
    JR   NZ,.COPY                  ; is copied.
    JP   NM_READ                   ; Read the next record; return.
