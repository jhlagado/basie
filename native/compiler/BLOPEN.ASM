;==========================================================================
;  Opening the streams
;==========================================================================
;
;  The blob writer's (BLOB.ASM) and the output streams' (OUT.ASM) opening
;  code, which runs once, when the parts are loaded and before anything is
;  compiled. It is part of the START overlay (OVERLAY.ASM), with
;  LIBRARY.ASM, whose LB_OPEN calls it, so the resident image does not
;  carry it.
;
;  Principal entries:
;    BL_OPEN    open the streams and write their headers
;    BL_PART    name a source part in the line stream
;    OUT_OPEN   delete any old file of the name, make it and reset the stream
;    BL_TDR     the directory stream's type, which LB_STAMP also reads

;@ROUTINE IN A,DE,HL CLOBBERS A,BC,DE,HL,CARRY,ZERO,SIGN,PARITY,HALFCARRY
; Open the streams named by DE, nine bytes of FCB drive and name, and write
; their headers. HL is the program directory's 20-byte header (object format
; §4.1), magic included, whose stamp and ordinal base the other headers and
; the implicit ordinals follow. A holds BL_LNOUT and BL_NMOUT.

BL_OPEN:                       ; HL is the header, DE the name, A the flags.
    OR   BL_BYOUT                  ; The byte stream is always written.
    LD   (BL_FLAGS),A              ; Keep the flags for the other routines.
    LD   (BL_NAMEP),DE             ; Keep the name for each stream.
    PUSH IX                        ; Keep the caller's IX.
    PUSH HL                        ; Keep the header for the copy.
    LD   DE,6                      ; The stamp is at offset 6.
    ADD  HL,DE                     ; HL addresses it.
    LD   E,(HL)                    ; DE is the stamp,
    INC  HL                        ; low byte first.
    LD   D,(HL)                    ; Every stream carries it.
    LD   (BL_STAMP),DE             ; Keep it for the other headers.
    LD   DE,9                      ; The ordinal base is at offset 16,
    ADD  HL,DE                     ; nine bytes on.
    LD   E,(HL)                    ; DE is the base:
    INC  HL                        ; the first blob's implicit ordinal.
    LD   D,(HL)                    ; A record numbers itself implicitly
    DEC  DE                        ; when it follows the previous one,
    LD   (BL_PREV),DE              ; so the first follows base less one.
    LD   HL,0                      ; No blob is written yet:
    LD   (BL_COUNT),HL             ; no records,
    LD   (BL_HIGH),HL              ; and no highest ordinal.
    DEC  L                         ; The entry before every blob's
    LD   (BL_GUARD+2),HL           ; first line entry has the part $FF.
    LD   IX,BL_DR                  ; The directory stream first.
    LD   HL,BL_TDR                 ; Type $DR.
    CALL .OPEN                     ; Make the file.
    POP  HL                        ; HL is the header.
    LD   B,20                      ; Twenty bytes, magic to padding.
    CALL .COPY                     ; Copy them to the directory stream.
    LD   HL,BL_STAB                ; Then each stream of the table.
.STREAM:                       ; HL is the next table entry.
    LD   A,(HL)                    ; Its flag; zero ends the table.
    OR   A                         ; Is the table done?
    JR   Z,.DONE                   ; Every stream wanted is open.
    LD   C,A                       ; C is the flag.
    INC  HL                        ; The stream's record follows.
    LD   E,(HL)                    ; Its low byte,
    INC  HL                        ; then
    LD   D,(HL)                    ; its high byte.
    INC  HL                        ; HL is the type, then the magic.
    LD   A,(BL_FLAGS)              ; Is this stream wanted?
    AND  C                         ; Test its flag.
    JR   Z,.SKIP                   ; Options leave it out.
    PUSH DE                        ; IX is the stream's record.
    POP  IX                        ; Every OUT_ call takes it there.
    PUSH HL                        ; Keep the type's address.
    CALL .OPEN                     ; Make the file.
    POP  HL                        ; The magic follows the type:
    INC  HL                        ; three bytes
    INC  HL                        ; on
    INC  HL                        ; from it.
    LD   B,4                       ; Four bytes of magic.
    CALL .COPY                     ; Copy them.
    PUSH HL                        ; Keep the table's place.
    LD   HL,1                      ; Version 1.0: major 1,
    CALL OUT_WORD                  ; then minor 0.
    LD   HL,(BL_STAMP)             ; The compilation stamp ties
    CALL OUT_WORD                  ; the streams together.
    POP  HL                        ; HL is the next entry.
    JR   .STREAM                   ; Open it.
.SKIP:                         ; HL is the type of a stream not wanted.
    LD   DE,7                      ; Step over its type and magic.
    ADD  HL,DE                     ; HL is the next entry.
    JR   .STREAM                   ; Consider it.
.DONE:                         ; Every stream wanted is open.
    POP  IX                        ; Restore the caller's IX.
    RET                            ; Blobs may now be written.

;@ROUTINE IN HL,IX CLOBBERS A,BC,DE,HL,CARRY,ZERO,SIGN,PARITY,HALFCARRY
; Open the stream at IX with the program's name and the type at HL.

.OPEN:                         ; HL is the three-character type.
    LD   DE,(BL_NAMEP)             ; DE is the drive and name.
    JP   OUT_OPEN                  ; Make the file and return.

;@ROUTINE IN B,HL,IX OUT HL CLOBBERS A,B,CARRY,ZERO,SIGN,PARITY,HALFCARRY
; Append the B bytes at HL to the stream at IX; HL is left after them.

.COPY:                         ; HL is the next byte.
    LD   A,(HL)                    ; Copy it
    CALL OUT_BYTE                  ; to the stream.
    INC  HL                        ; Move to the next.
    DJNZ .COPY                     ; Until B are done.
    RET                            ; HL is after them.

;@ROUTINE IN A,B,HL CLOBBERS A,B,C,HL,CARRY,ZERO,SIGN,PARITY,HALFCARRY
; Name source part A (0-based) as the B characters at HL, in a part record
; of the line stream (object format §8). Nothing is written without one.

BL_PART:                       ; A is the part's index.
    LD   C,A                       ; Keep the index.
    LD   A,(BL_FLAGS)              ; Is there a line stream?
    AND  BL_LNOUT                  ; Option N leaves it out.
    RET  Z                         ; Then there is nothing to name.
    PUSH IX                        ; Keep the caller's IX.
    LD   IX,BL_LN                  ; Write to the line stream.
    LD   A,1                       ; Tag 1: a part record.
    CALL OUT_BYTE                  ; Append it.
    LD   A,C                       ; The part's index.
    CALL OUT_BYTE                  ; Append it.
    LD   A,B                       ; The name's length.
    CALL OUT_BYTE                  ; Append it.
.NAME:                         ; B characters of the name remain.
    LD   A,(HL)                    ; Copy the next one
    CALL OUT_BYTE                  ; to the stream.
    INC  HL                        ; Move to the next.
    DJNZ .NAME                     ; Until the name is written.
    POP  IX                        ; Restore the caller's IX.
    RET                            ; The part may now be cited.

;@ROUTINE IN IX,DE,HL CLOBBERS A,BC,DE,HL,IY,CARRY,ZERO,SIGN,PARITY,HALFCARRY
; Open the stream at IX as a new file. DE is nine bytes, an FCB drive byte
; and an eight-character name; HL is a three-character type. Any old file
; of the name is deleted first: CP/M's make does not check for one, and a
; crashed build could otherwise leave two entries with one name (toolchain
; §3.2).

OUT_OPEN:                      ; IX is the stream, DE the drive and name.
    PUSH HL                        ; Keep the type until the name is in.
    PUSH IX                        ; Copy the drive and name to the FCB:
    POP  HL                        ; HL is the FCB.
    EX   DE,HL                     ; DE is the FCB, HL the drive and name.
    LD   BC,9                      ; Nine bytes.
    LDIR                           ; DE is now the FCB's type field.
    POP  HL                        ; HL is the type.
    LD   C,3                       ; Three bytes; B is still zero.
    LDIR                           ; DE is now the first byte after the type.
    LD   B,OUT_FCBN-12             ; The extent, map and record bytes,
    XOR  A                         ; all zero, as make expects.
.CLEAR:                        ; B bytes of FCB remain to clear.
    LD   (DE),A                    ; Clear this one.
    INC  DE                        ; Move to the next.
    DJNZ .CLEAR                    ; Through the random record number.
    LD   (IX+OUT_POS),A            ; The buffer is empty.
    LD   (IX+OUT_CNT),A            ; Nothing has been written:
    LD   (IX+OUT_CNT+1),A          ; the count is zero
    LD   (IX+OUT_CNT+2),A          ; in all
    LD   (IX+OUT_CNT+3),A          ; four bytes.
    DEC  A                         ; A is $FF.
    LD   (IX+OUT_SUM),A            ; The CRC starts at $FFFF,
    LD   (IX+OUT_SUM+1),A          ; both bytes.
    LD   C,BD_DEL                  ; Delete any old file of the name;
    CALL OUT_FCB                   ; an absent file is only a status.
    LD   C,BD_MAKE                 ; Make the new file.
    CALL OUT_FCB                   ; A is $FF if the directory is full.
    INC  A                         ; $FF becomes zero.
    RET  NZ                        ; The file is open and empty.
    JP   OUT_FAIL                  ; No directory entry: the build cannot go on.

; Stream types and magic numbers. BL_STAB lists the streams after the
; directory: each entry is the flag that wants it, its record, its type and
; its magic; a zero flag ends the table.

BL_TDR: DB   "$DR"             ; The directory stream's type.
BL_STAB:                       ; The other streams, in the order they open.
    DB   BL_BYOUT                  ; The byte stream, always.
    DW   BL_BY                     ; Its record.
    DB   "$BYBSIB"                 ; Its type and magic.
    DB   BL_LNOUT                  ; The line stream, unless option N.
    DW   BL_LN                     ; Its record.
    DB   "$LNBSIL"                 ; Its type and magic.
    DB   BL_NMOUT                  ; The name stream, with option M or Y.
    DW   BL_NM                     ; Its record.
    DB   "$NMBSIN"                 ; Its type and magic.
    DB   0                         ; The end of the table.
