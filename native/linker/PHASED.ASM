;==========================================================================
;  Phase D: writing the image, and Intel HEX
;==========================================================================
;
;  Phase D (linker §7) writes the image to NAME.$$$ on the output drive,
;  under the output's name, making the passes of Phase C again: START,
;  TEXT, DATA, then the DATA passes once more for COPY. Each live blob is
;  copied from its byte stream, the library's byte section or the program's
;  NAME.$BY, with its references patched as they come; gaps between blobs
;  are filled with zeros. The line table (LINES.ASM) is written alongside.
;
;  Principal entries:
;    PD_RUN    write the image, padded to its last record, and the line table
;    OUT_PICK  the output's name and drive
;    OUT_RAW   write a byte to the output file, adding it to IMG_CRC
;    HEX_PUT   add an image byte to the Intel HEX record (HEX_OUT writes it)
;
;  Output kinds: .COM and .BIN are the image's bytes; .HEX is Intel HEX
;  text, sixteen data bytes a record, then the end record and $1A. IMG_CRC,
;  which the line table records, is the CRC of the file as written,
;  padding included.
;
;  Memory: Phase D's FDs are reused. CMD_BUF and CMD_BAD lie in SRC_PROG
;  and SRC_LIB, which are not opened until long after the tail is parsed;
;  TB_FD is OUT_FD, written by option W before Phase D; and publication and
;  Phase E reuse them all once the image is written.

OUT_FD:                        ; The FD that writes NAME.$$$.
    DS   FD_SIZE                   ; Renamed to the output by publication.
TB_FD EQU  OUT_FD              ; Option W's dump, made before Phase D.
OUT_TEMP:                      ; The image's type until publication.
    DB   "$$$"                     ; Three characters.
OUT_TEXT:                      ; The image's name as text, NAME.$$$,
    DS   13                        ; for diagnostics.
SRC_LIB:                       ; The library again, for its byte section.
    DS   FD_SIZE                   ; LIB_FD stays on the directory for the walks.
SRC_PROG:                      ; The program's byte stream, NAME.$BY.
    DS   FD_SIZE                   ; Opened on the directory's drive.
CMD_BUF EQU  SRC_PROG          ; The command tail (130 bytes), and a bad
CMD_BAD EQU  SRC_LIB           ; option's text (32), used only in parsing.
SRC_TYPE:                      ; The byte stream's type.
    DB   "$BY"                     ; Three characters.
SRC_TEXT:                      ; Its name as text, for diagnostics.
    DS   13                        ; NAME.$BY and a zero.

;@ROUTINE CLOBBERS A,BC,DE,HL,IX,CARRY,ZERO,SIGN,PARITY,HALFCARRY
; Phase D: create NAME.$$$, open the library's byte section and NAME.$BY,
; write the image section by section, finish the last record as the output
; kind requires, and close the image and the line table.

PD_RUN:                        ; Phase C has placed everything.
    LD   IX,OUT_FD                 ; NAME.$$$ on the output drive,
    CALL OUT_PICK                  ; HL = name, A = drive,
    LD   DE,OUT_TEMP               ; under the type $$$,
    LD   BC,OUT_TEXT               ; named in OUT_TEXT.
    CALL FIL_NAME                  ; Set up the FCB.
    XOR  A                         ; .COM: the last record padded with zeros.
    CALL FIL_MAKE                  ; Create it; carry if the directory is full.
    JP   C,OUT_FAIL                ; L-IO.
    LD   A,1                       ; NAME.$$$ exists now,
    LD   (OUT_MADE),A              ; so a failure deletes it.
    LD   IX,SRC_LIB                ; The library's byte section, through a second FD,
    LD   A,(LIB_FD+FD_FCB)         ; on the drive the library was found on.
    LD   HL,LIB_FILE               ; Its name,
    LD   DE,LIB_TYPE               ; type BRL,
    LD   BC,LIB_TEXT               ; named in LIB_TEXT.
    CALL FIL_NAME                  ; Set up the FCB.
    CALL FIL_NEED                  ; Open it again, or L-MISSING.
    LD   IX,SRC_PROG               ; The program's byte stream, NAME.$BY,
    LD   A,(DIR_FD+FD_FCB)         ; on the directory's drive.
    LD   HL,CMD_NAME               ; NAME,
    LD   DE,SRC_TYPE               ; type $BY,
    LD   BC,SRC_TEXT               ; named in SRC_TEXT.
    CALL FIL_NAME                  ; Set up the FCB.
    CALL FIL_NEED                  ; Open it, or L-MISSING.
    CALL SRC_HEAD                  ; Check its header and stamp.
    LD   HL,$FFFF                  ; The image's CRC
    LD   (IMG_CRC),HL              ; starts.
    CALL LN_OPEN                   ; Open the line stream and table, unless N.
    LD   HL,(PF_BASE)              ; Writing starts at the image's base,
    LD   (OUT_POS),HL              ; for the padding,
    LD   (HEX_ADDR),HL             ; and the first HEX record's address.
    LD   A,S_START                 ; START,
    CALL .SECTION                  ; written;
    LD   A,S_TEXT                  ; TEXT,
    CALL .SECTION                  ; written;
    LD   A,S_DATA                  ; DATA, under option R,
    CALL .SECTION                  ; written.
    LD   HL,(DATA_END)             ; COPY: the DATA passes again, with the
    LD   DE,(DATA_BEG)             ; output DATA's size further on.
    OR   A                         ; Clear carry for the subtraction.
    SBC  HL,DE                     ; DATA's size,
    LD   (PD_DELTA),HL             ; added to each blob's address.
    LD   A,S_DATA                  ; DATA's blobs again,
    CALL .SECTION                  ; written as COPY.
    LD   HL,(PT_SIZE)              ; Then the position table (option D),
    LD   DE,(PT_BEG)               ; made in Phase C.
.TABLE:                        ; HL bytes remain at DE.
    LD   A,H                       ; Any
    OR   L                         ; left?
    JR   Z,.TABLED                 ; No.
    LD   A,(DE)                    ; The next,
    CALL PD_OUTB                   ; written (DE and HL kept).
    INC  DE                        ; One
    DEC  HL                        ; fewer.
    JR   .TABLE                    ; Go on.
.TABLED:                       ; The image is written.
    LD   A,(OUT_KIND)              ; .COM and .BIN: zeros to the end of the record;
    CP   4                         ; .HEX: the last data record, the end
    LD   C,0                       ; record, then $1A. Padding is in the CRC.
    JR   NZ,.PAD                   ; Not .HEX: pad with zeros.
    CALL HEX_OUT                   ; Write the last data record, if any.
    LD   HL,HEX_END                ; The end record,
    LD   B,13                      ; with its CR LF.
.END:                          ; HL walks the end record.
    LD   A,(HL)                    ; The next character.
    CALL OUT_RAW                   ; Write it.
    INC  HL                        ; The next.
    DJNZ .END                      ; Until all 13 are written.
    LD   C,$1A                     ; A text file pads with Control-Z.
.PAD:                          ; C is the padding byte.
    LD   A,(OUT_FD+FD_POS)         ; Is the last record full?
    OR   A                         ; 0 when the buffer is empty.
    JR   Z,.PADDED                 ; Nothing to pad.
    LD   A,C                       ; Pad,
    CALL OUT_RAW                   ; into the CRC.
    JR   .PAD                      ; Until the record is written.
.PADDED:                       ; The image is complete.
    LD   IX,OUT_FD                 ; Close NAME.$$$;
    CALL FIL_SHUT                  ; nothing is left to pad.
    JP   C,OUT_FAIL                ; L-IO.
    JP   LN_CLOSE                  ; Finish the line table, and return.

;@ROUTINE IN A CLOBBERS A,BC,DE,HL,IX,CARRY,ZERO,SIGN,PARITY,HALFCARRY
; Write section A: its passes, copying each blob in them.

.SECTION:                      ; A is an S_ value.
    LD   HL,PD_BLOB                ; The callback for each blob.
    JP   WK_PASS                   ; Make the passes, and return.

;@ROUTINE OUT A,HL CLOBBERS CARRY,ZERO,SIGN,PARITY,HALFCARRY
; Return HL = the output's 8-character name and A its drive: option O's,
; else the first part's.

OUT_PICK:                      ; For NAME.$$$, NAME.$LT and the published files.
    LD   A,(OUT_SET)               ; Was O= given?
    OR   A                         ; Nonzero if so.
    JR   Z,.PART                   ; Named after the first part.
    LD   HL,OUT_NAME               ; O='s name.
    LD   A,(OUT_DISK)              ; O='s drive,
    OR   A                         ; if it gave one;
    RET  NZ                        ; it did.
    LD   A,(CMD_DISK)              ; Else the first part's drive.
    RET                            ; HL and A name the output.
.PART:                         ; No O=.
    LD   HL,CMD_NAME               ; The first part's name,
    LD   A,(CMD_DISK)              ; and its drive.
    RET                            ; HL and A name the output.

;@ROUTINE IN IX CLOBBERS A,B,DE,HL,CARRY,ZERO,SIGN,PARITY,HALFCARRY
; Check NAME.$BY's header (object format §6): magic BSIB, version 1.0, and
; the directory's compilation stamp. L-FORMAT or L-STAMP otherwise.

SRC_HEAD:                      ; IX is NAME.$BY, just opened.
    LD   HL,.MAGIC                 ; Its magic and version,
    CALL RD_MAGIC                  ; checked without the CRC, off since Phase C;
    JP   RD_STAMP                  ; and its stamp; return.
.MAGIC:                        ; The byte stream's magic.
    DB   "BSIB"                    ; Basie byte stream.

;@ROUTINE CLOBBERS A,BC,DE,HL,CARRY,ZERO,SIGN,PARITY,HALFCARRY
; Copy the blob just read to the output, if it is in the pass, patching its
; references; otherwise skip its references, reading a program code blob's
; line record in the code pass all the same.

PD_BLOB:                       ; A walk's callback.
    CALL WK_MATCH                  ; Z if the blob is in the pass.
    JR   Z,.SEL                    ; Copy it.
    LD   A,(WK_SEC)                ; Not in the pass; but a program code blob's
    CP   S_TEXT                    ; line record is still read in the code
    JP   NZ,REF_SKIP               ; pass, TEXT's class 0, to keep the line
    LD   A,(WK_CLASS)              ; stream in step with the directory.
    OR   A                         ; Class 0?
    JP   NZ,REF_SKIP               ; Another class's pass.
    LD   A,(WK_OWN)                ; The program's?
    OR   A                         ; The library has no line records.
    JP   Z,REF_SKIP                ; The library's.
    LD   A,(WK_KIND)               ; Code?
    CP   K_CODE                    ; Only code has a line record.
    JP   NZ,REF_SKIP               ; Not code.
    XOR  A                         ; A = 0: not emitted, so its record is skipped.
    CALL LN_BLOB                   ; Read past its line record.
    JP   REF_SKIP                  ; Skip its references.
.SEL:                          ; Pad up to the blob's address, or in COPY its copy's.
    LD   HL,(WK_ENTRY)             ; The blob's entry.
    LD   DE,E_ADDR                 ; Its address field.
    ADD  HL,DE                     ; HL addresses it.
    LD   E,(HL)                    ; The low byte,
    INC  HL                        ; then
    LD   D,(HL)                    ; DE = the address.
    LD   HL,(PD_DELTA)             ; COPY's distance, or 0 before COPY.
    LD   A,H                       ; Z when it is 0:
    OR   L                         ; not the COPY pass.
    ADD  HL,DE                     ; Keeps Z: HL is where the bytes go.
    PUSH HL                        ; Keep it.
    LD   A,1                       ; A = 1: the blob is emitted.
    CALL Z,LN_BLOB                 ; Its line-table entries, but not in COPY.
    POP  DE                        ; DE is where the blob goes.
    LD   HL,(OUT_POS)              ; HL is where writing has reached.
.PAD:                          ; Pad with zeros from HL up to DE.
    LD   A,L                       ; Has HL reached
    CP   E                         ; the blob?
    JR   NZ,.ZERO                  ; Not yet.
    LD   A,H                       ; Compare
    CP   D                         ; the high bytes.
    JR   Z,.SOURCE                 ; The blob starts here.
.ZERO:                         ; A gap before the blob.
    XOR  A                         ; A zero,
    CALL PD_OUTB                  ; written.
    INC  HL                        ; One address on.
    JR   .PAD                      ; Until the blob's address.
.SOURCE:                       ; HL is the blob's address.
    LD   BC,(RD_SIZE)              ; The output position moves past the blob.
    ADD  HL,BC                     ; Where writing will reach,
    LD   (OUT_POS),HL              ; once it is copied.
    LD   A,(WK_OWN)                ; The blob's bytes: the library's byte
    OR   A                         ; section or the program's stream.
    JR   NZ,.PROGRAM               ; The program's.
    LD   HL,SRC_LIB                ; The library's byte section,
    LD   (SRC_FD),HL               ; read through SRC_LIB,
    LD   HL,(LIB_HEAD+16)          ; at the offset
    LD   A,(LIB_HEAD+18)           ; its header gives,
    LD   DE,LIB_TEXT               ; named as the library.
    JR   .SEEK                     ; Plus the blob's offset.
.PROGRAM:                      ; NAME.$BY.
    LD   HL,SRC_PROG               ; The program's stream,
    LD   (SRC_FD),HL               ; read through SRC_PROG,
    LD   HL,8                      ; past the stream's header.
    XOR  A                         ; A small offset.
    LD   DE,SRC_TEXT               ; Its name.
.SEEK:                         ; A:HL is the stream's start in its file.
    LD   (RD_NAME),DE              ; The source names a short stream.
    LD   DE,(WK_POS)               ; The blob's offset in the stream,
    ADD  HL,DE                     ; added,
    ADC  A,0                       ; with the carry into the high byte.
    PUSH IX                        ; Keep the directory's FD.
    LD   IX,(SRC_FD)               ; The source's FD.
    CALL FIL_SEEK                  ; Go to the blob's first byte.
    POP  IX                        ; IX is the directory again.
    JP   C,DG_SHORT                ; The source is too short.
    LD   HL,0                      ; HL = the bytes copied so far:
    LD   (REF_END),HL              ; none.
    CALL REF_NEW                   ; No reference read yet.
.REF:                          ; Copy and patch each reference.
    LD   HL,(REF_CNT)              ; Any left?
    LD   A,H                       ; Test the count
    OR   L                         ; for zero.
    JR   Z,.REST                   ; Copy the rest of the blob.
    DEC  HL                        ; One fewer
    LD   (REF_CNT),HL              ; to read.
    CALL REF_READ                  ; HL = target, DE = addend.
    PUSH DE                        ; Keep the addend,
    PUSH HL                        ; and the target.
    LD   HL,(REF_LAST)             ; Copy up to the reference.
    CALL .COPYTO                   ; The bytes before its placeholder.
    POP  HL                        ; HL is the target,
    POP  DE                        ; DE the addend.
    CALL .VALUE                    ; HL = the value.
    CALL .PATCH                    ; Write it over the placeholder.
    JR   .REF                      ; The next reference.
.REST:                         ; Every reference is patched.
    LD   HL,(RD_SIZE)              ; Copy to the blob's end,
    JR   .COPYTO                   ; and return.

;@ROUTINE IN HL CLOBBERS A,DE,CARRY,ZERO,SIGN,PARITY,HALFCARRY
; Copy source bytes to the output until REF_END, the bytes copied, reaches
; HL.

.COPYTO:                       ; HL is the offset to copy up to.
    LD   DE,(REF_END)              ; DE is the offset reached.
.LOOP:                         ; Copy while DE is below HL.
    LD   A,L                       ; Has DE reached
    CP   E                         ; HL?
    JR   NZ,.ONE                   ; Not yet.
    LD   A,H                       ; Compare
    CP   D                         ; the high bytes.
    RET  Z                         ; Copied up to HL.
.ONE:                          ; One more byte.
    CALL .SRCBYTE                  ; A is the source's next byte.
    CALL PD_OUTB                  ; Write it.
    INC  DE                        ; One more copied,
    LD   (REF_END),DE              ; recorded.
    JR   .LOOP                     ; Go on.

;@ROUTINE IN HL CLOBBERS A,DE,HL,CARRY,ZERO,SIGN,PARITY,HALFCARRY
; Write the reference's value HL in its form, in place of its placeholder.

.PATCH:                        ; HL is the value; the source is at the placeholder.
    LD   A,(REF_FORM)              ; The form.
    CP   1                         ; LO8?
    JR   Z,.LO                     ; One byte, the low.
    CP   2                         ; HI8?
    JR   Z,.HI                     ; One byte, the high.
    CALL .SKIP2                    ; ABS16 and SIZE16: two bytes.
    LD   A,L                       ; The low byte,
    CALL PD_OUTB                  ; written,
    LD   A,H                       ; then the high byte,
    CALL PD_OUTB                  ; written.
    RET                            ; The reference is patched.
.LO:                           ; LO8.
    CALL .SKIP1                    ; Pass the placeholder byte.
    LD   A,L                       ; The low byte,
    JP   PD_OUTB                  ; written; return.
.HI:                           ; HI8.
    CALL .SKIP1                    ; Pass the placeholder byte.
    LD   A,H                       ; The high byte,
    JP   PD_OUTB                  ; written; return.

;@ROUTINE CLOBBERS A,DE,CARRY,ZERO,SIGN,PARITY,HALFCARRY
; Pass two placeholder bytes in the source, checking each under option V.

.SKIP2:                        ; A two-byte placeholder.
    CALL .SKIP1                    ; The first; fall into .SKIP1 for the second.

;@ROUTINE CLOBBERS A,DE,CARRY,ZERO,SIGN,PARITY,HALFCARRY
; Pass one placeholder byte in the source. A nonzero placeholder is
; L-PLACEHOLDER under option V.

.SKIP1:                        ; The source is at a placeholder byte.
    CALL .SRCBYTE                  ; The placeholder byte.
    PUSH AF                        ; Keep it.
    LD   DE,(REF_END)              ; One more byte
    INC  DE                        ; of the blob
    LD   (REF_END),DE              ; is passed.
    POP  AF                        ; A is the placeholder.
    OR   A                         ; Zero, as it should be?
    RET  Z                         ; Yes.
    LD   A,(OP_FLAGS)              ; Nonzero: an error under option V,
    AND  OF_V                      ; and ignored without it.
    RET  Z                         ; Not verifying.
    LD   HL,221                    ; L-PLACEHOLDER.
    JP   DG_PLAIN                  ; Report it.

;@ROUTINE IN DE,HL OUT HL CLOBBERS A,BC,DE,CARRY,ZERO,SIGN,PARITY,HALFCARRY
; Return HL = the value of a reference to target HL with addend DE, in
; REF_FORM's form (linker §7.4). The value is the target's address plus the
; addend, signed, and must lie in 0 to $FFFF; a reference to a blob, or to
; MAIN, must also stay within its target: address <= value <= address +
; size. SIZE16 is the target's size plus the addend. L-RANGE otherwise.

.VALUE:                        ; HL is the target, DE the addend.
    LD   A,H                       ; Is it $FFxx?
    CP   $FF                       ; Pseudo-objects are there.
    JR   NZ,.ENT                   ; A blob or alias.
    LD   A,L                       ; $FFE0 and above
    CP   $E0                       ; are pseudo-objects.
    JR   C,.ENT                    ; An ordinary ordinal.
    SUB  $E0                       ; A pseudo-object: its row of PS_TAB.
    PUSH AF                        ; Keep the row number.
    ADD  A,A                       ; Four bytes
    ADD  A,A                       ; per row.
    PUSH DE                        ; Keep the addend.
    LD   E,A                       ; DE is the row's offset,
    LD   D,0                       ; zero-extended.
    LD   HL,PS_TAB                 ; From the table's start,
    ADD  HL,DE                     ; HL is the row.
    POP  DE                        ; DE is the addend.
    LD   C,(HL)                    ; The address,
    INC  HL                        ; low byte
    LD   B,(HL)                    ; then high.
    INC  HL                        ; The size follows.
    PUSH BC                        ; The address.
    LD   C,(HL)                    ; The size,
    INC  HL                        ; low byte
    LD   B,(HL)                    ; BC = the size.
    POP  HL                        ; HL = the address.
    POP  AF                        ; Row 0 is MAIN, the one checked.
    OR   A                         ; MAIN?
    LD   A,1                       ; Checked,
    JR   Z,.FORMS                  ; for MAIN;
    XOR  A                         ; not checked
    JR   .FORMS                    ; for the others.
.ENT:                          ; A blob or an alias.
    PUSH DE                        ; Keep the addend.
    CALL TAB_FIND                  ; HL is its entry.
    POP  DE                        ; DE is the addend.
    INC  HL                        ; Its size,
    LD   C,(HL)                    ; low byte,
    INC  HL                        ; then
    LD   B,(HL)                    ; BC = the size.
    INC  HL                        ; Its address,
    LD   A,(HL)                    ; low byte,
    INC  HL                        ; then
    LD   H,(HL)                    ; high,
    LD   L,A                       ; HL = the address.
    LD   A,1                       ; Checked.
.FORMS:                        ; HL is the address, BC the size.
    LD   (.CHECKED),A              ; Whether the value must stay within it.
    LD   A,(REF_FORM)              ; SIZE16?
    CP   3                         ; Its value is the size.
    JR   Z,.SIZE                   ; Size plus addend.
    LD   A,D                       ; The addend's sign:
    AND  $80                       ; bit 15.
    LD   (.NEGATIVE),A             ; Nonzero for a negative addend.
    ADD  HL,DE                     ; HL = the value.
    LD   A,0                       ; A takes
    RLA                            ; the carry.
    LD   (.CARRY),A                ; Kept.
    LD   A,(.NEGATIVE)             ; A negative addend?
    OR   A                         ; Zero if not.
    JR   Z,.POS                    ; Positive.
    LD   A,(.CARRY)                ; A negative addend: no carry means below 0.
    OR   A                         ; Did the sum carry?
    JR   Z,.RANGE                  ; No: the value is below 0.
    LD   A,(.CHECKED)              ; And below the target when checked.
    OR   A                         ; Checked?
    RET  Z                         ; No: the value stands.
    JR   .RANGE                    ; Checked: below the target's address.
.POS:                          ; A zero or positive addend.
    LD   A,(.CARRY)                ; Carry: past $FFFF.
    OR   A                         ; Did the sum carry?
    JR   NZ,.RANGE                 ; Out of range.
    LD   A,(.CHECKED)              ; Checked?
    OR   A                         ; Zero if not.
    RET  Z                         ; The value stands.
    PUSH HL                        ; Checked: the addend no more than the size.
    LD   H,B                       ; HL is
    LD   L,C                       ; the size.
    OR   A                         ; Clear carry for the subtraction.
    SBC  HL,DE                     ; Carry if the addend exceeds it.
    POP  HL                        ; HL is the value.
    RET  NC                        ; Within the target.
.RANGE:                        ; The value is out of range.
    LD   HL,220                    ; L-RANGE.
    JP   DG_PLAIN                  ; Report it.
.SIZE:                         ; SIZE16: the size plus the addend.
    LD   H,B                       ; HL is
    LD   L,C                       ; the size,
    ADD  HL,DE                     ; plus the addend.
    RET                            ; HL is the value.

.CHECKED:                      ; Nonzero when the value must stay in its target.
    DB   0                         ; Set by .VALUE.
.NEGATIVE:                     ; Nonzero for a negative addend.
    DB   0                         ; Set by .VALUE.
.CARRY:                        ; The carry out of address + addend.
    DB   0                         ; Set by .VALUE.

;@ROUTINE OUT A CLOBBERS CARRY,ZERO,SIGN,PARITY,HALFCARRY
; Read the next byte of the byte stream being copied into A, keeping BC, DE
; and HL. L-TRUNCATED at its end, named by RD_NAME, the source's name.

.SRCBYTE:                      ; SRC_FD is the source.
    PUSH IX                        ; Keep the directory's FD.
    LD   IX,(SRC_FD)               ; The source's FD.
    CALL FIL_GETB                  ; A is the next byte, or carry at the end.
    POP  IX                        ; IX is the directory again.
    JP   C,DG_SHORT                ; The source ended inside the blob.
    RET                            ; A is the byte.

;@ROUTINE IN A CLOBBERS A,CARRY,ZERO,SIGN,PARITY,HALFCARRY
; Write image byte A to the output: as itself, or into a .HEX record.
; Keeps BC, DE, HL and IX.

PD_OUTB:                       ; A is an image byte.
    PUSH HL                        ; Keep HL while the kind is tested.
    LD   HL,OUT_KIND               ; .HEX is kind 4,
    BIT  2,(HL)                    ; bit 2.
    POP  HL                        ; Recover HL; the flags remain.
    JR   NZ,HEX_PUT                ; .HEX: into the record.

;@ROUTINE IN A CLOBBERS CARRY,ZERO,SIGN,PARITY,HALFCARRY
; Write A to the output file, adding it to the image's CRC. Keeps every
; register; L-IO if the disk is full.

OUT_RAW:                       ; A is a byte of the output file.
    PUSH HL                        ; Keep HL.
    LD   HL,IMG_CRC                ; The image's CRC,
    CALL CRC_FOLD                  ; with A added.
    POP  HL                        ; Recover HL.
    PUSH IX                        ; Keep the caller's FD.
    LD   IX,OUT_FD                 ; NAME.$$$.
    CALL FIL_PUTB                  ; Write A; carry if the disk is full.
    POP  IX                        ; Recover IX.
    RET  NC                        ; Written; fall into OUT_FAIL.

;@ROUTINE NORETURN
; The output could not be made, written or closed: L-IO for NAME.$$$.

OUT_FAIL:                      ; A write, make or close of OUT_FD failed.
    LD   HL,OUT_TEXT               ; Name the output
    LD   (RD_NAME),HL              ; in the diagnostic.
    JP   DG_DISK                   ; L-IO.

; ---- Intel HEX (linker §7.6) -------------------------------------------------

HEX_ADDR:                      ; The address of the record being filled.
    DW   0                         ; Starts at the image's base.
HEX_CNT:                       ; Its bytes so far.
    DB   0                         ; 0 to 15; at 16 the record is written.
HEX_BUF:                       ; Its bytes.
    DS   16                        ; Sixteen data bytes a record.
HEX_END:                       ; The end-of-file record, with its line end.
    DB   ":00000001FF",13,10       ; Thirteen bytes.

;@ROUTINE IN A CLOBBERS A,CARRY,ZERO,SIGN,PARITY,HALFCARRY
; Add image byte A to the record, writing it when full. Keeps BC, DE, HL
; and IX.

HEX_PUT:                       ; A is an image byte.
    PUSH HL                        ; Keep HL,
    PUSH DE                        ; and DE.
    LD   HL,HEX_CNT                ; The bytes so far
    LD   E,(HL)                    ; index the buffer,
    INC  (HL)                      ; and count one more.
    LD   D,0                       ; DE is the index.
    LD   HL,HEX_BUF                ; From the buffer's start,
    ADD  HL,DE                     ; HL is the byte's place.
    LD   (HL),A                    ; Store it.
    LD   A,E                       ; A is its index.
    POP  DE                        ; Recover DE,
    POP  HL                        ; and HL.
    CP   15                        ; Was it the sixteenth?
    RET  NZ                        ; Not yet: the record isn't full.

;@ROUTINE CLOBBERS A,CARRY,ZERO,SIGN,PARITY,HALFCARRY
; Write the record, if it has any bytes: colon, count, address, type 00,
; data and checksum in hex, then CR LF. Keeps BC, DE, HL and IX.

HEX_OUT:                       ; HEX_CNT bytes are in the buffer.
    LD   A,(HEX_CNT)               ; Any bytes?
    OR   A                         ; Zero: nothing to write.
    RET  Z                         ; An empty record isn't written.
    PUSH HL                        ; Keep HL,
    PUSH BC                        ; and BC.
    LD   B,A                       ; B is the count.
    LD   A,':'                     ; The record's mark.
    CALL OUT_RAW                   ; Written.
    LD   C,0                       ; The sum of the record's bytes.
    LD   A,B                       ; The count,
    CALL .HEXBYTE                  ; in hex.
    LD   HL,(HEX_ADDR)             ; The address,
    LD   A,H                       ; high byte,
    CALL .HEXBYTE                  ; in hex,
    LD   A,L                       ; then low byte,
    CALL .HEXBYTE                  ; in hex.
    XOR  A                         ; Type 00, data,
    CALL .HEXBYTE                  ; in hex.
    LD   A,L                       ; The next record's address:
    ADD  A,B                       ; this one's plus the count,
    LD   L,A                       ; in L,
    ADC  A,H                       ; with the carry
    SUB  L                         ; into
    LD   H,A                       ; H.
    LD   (HEX_ADDR),HL             ; Kept.
    LD   HL,HEX_BUF                ; The data bytes.
.DATA:                         ; HL walks the buffer, B counts down.
    LD   A,(HL)                    ; The next byte,
    CALL .HEXBYTE                  ; in hex.
    INC  HL                        ; The next.
    DJNZ .DATA                     ; Until the count is written.
    XOR  A                         ; B = 0 now.
    LD   (HEX_CNT),A               ; The buffer is empty.
    SUB  C                         ; The checksum: minus the sum.
    CALL .HEXBYTE                  ; In hex.
    LD   A,13                      ; The line end:
    CALL OUT_RAW                   ; CR,
    LD   A,10                      ; then
    CALL OUT_RAW                   ; LF.
    POP  BC                        ; Recover BC,
    POP  HL                        ; and HL.
    RET                            ; The record is written.

;@ROUTINE IN A,C OUT C CLOBBERS A,CARRY,ZERO,SIGN,PARITY,HALFCARRY
; Write A in two hex digits and add it to the sum in C. Keeps B, DE, HL
; and IX.

.HEXBYTE:                      ; A is a byte of the record.
    PUSH AF                        ; Keep the byte.
    ADD  A,C                       ; Add it
    LD   C,A                       ; to the sum.
    POP  AF                        ; A is the byte again.
    PUSH AF                        ; Keep it for the low digit.
    RRCA                           ; Bring the high four bits
    RRCA                           ; down
    RRCA                           ; to the
    RRCA                           ; low four.
    CALL .NIBBLE                   ; Write the high digit.
    POP  AF                        ; The byte again; write its low digit.

;@ROUTINE IN A CLOBBERS A,CARRY,ZERO,SIGN,PARITY,HALFCARRY
; Write the hex digit for A's low four bits.

.NIBBLE:                       ; A's low four bits are the digit.
    CALL LK_DIGIT                  ; A is its character.
    JP   OUT_RAW                   ; Write it, and return.
