;==========================================================================
;  Library check and compilation stamp
;==========================================================================
;
;  Before any source is read, BASIE.COM reads the blob library a build
;  will link with, NAME.BRL (option P, CPM22 by default), as far as its
;  header, profile block and key table, and refuses one it is not built
;  for (toolchain §3.1; object format §7, §10), by the rules the linker
;  applies: the magic BSIR and version 1.0, a helper-table version no older
;  than the compiler's (HP_VER), and the key of that version equal to the
;  compiler's (HP_KEY). The library's runtime and profile identities go
;  into the program directory's header (SH_HEAD), as the reference
;  compiler takes them from its library. Then, before the streams are
;  made, the compilation stamp is chosen (object format §4.1).
;
;  Principal entries, in the START overlay, which SH_BEGIN (PARTS.ASM)
;  enters:
;    LB_CHECK  find, read and check the library
;    LB_STAMP  choose the compilation stamp
;
;  The library is looked for on option L's drive, else the first part's,
;  then on A: (toolchain §7.3). Failure, which does not return, is
;  reported as BLINK reports it, by the reference's numbers and with the
;  library's name as the argument (MS_FAIL): L-MISSING (`Error 225:
;  CPM22.BRL not found`), L-FORMAT for bad magic or version, L-TRUNCATED
;  for a library that ends too soon, L-COMPAT, which names nothing, and
;  L-IO for a read error. A record is read into the blob writer's
;  buffer, which is not in use until the streams open.

LB_BUF EQU  BL_CODE            ; A record read from the library or an old directory.
LB_RAND EQU  33                ; BDOS read random: the record number is in the FCB.
LB_NFORM EQU  200              ; L-FORMAT: bad magic or version.
LB_NCOMP EQU  201              ; L-COMPAT: another helper table.
LB_NTRUN EQU  214              ; L-TRUNCATED: the library ends too soon.

;@ROUTINE CLOBBERS A,BC,DE,HL,IX,IY,CARRY,ZERO,SIGN,PARITY,HALFCARRY
; Find the library and read its first record and the record of its key
; table, checking that the compiler is built for it; take its runtime and
; profile identities for the directory's header.

LB_CHECK:                      ; CL_LIB is the library's name.
    LD   A,(CL_SEEN+CL_IL)         ; Option L's drive,
    OR   A                         ; if given,
    JR   NZ,.FIRST                 ; is the first place to look;
    LD   A,(SH_NAMES)              ; else the first part's drive.
.FIRST:                        ; A is the first drive to try.
    CALL .TRY                      ; Open it there.
    JR   NC,.FOUND                 ; Found.
    LD   A,1                       ; Then A:.
    CALL .TRY                      ; Open it there.
    JR   NC,.FOUND                 ; Found.
    LD   HL,SH_NMISS               ; NAME.BRL not found (L-MISSING).
    JP   LB_FAIL                   ; Fail.
.FOUND:                        ; The FCB is open.
    LD   DE,LB_BUF                 ; Records are read
    LD   C,SH_DMA                  ; into the buffer.
    CALL SH_BDOS                   ; Set the DMA address.
    LD   DE,SH_FCB                 ; The first record:
    LD   C,SH_READ                 ; the header and the profile block.
    CALL LB_READ                   ; Read it; failures do not return.
    LD   HL,LB_BUF                 ; Compare the magic,
    LD   DE,LB_MAGIC               ; BSIR,
    LD   B,4                       ; four bytes.
.MAGIC:                        ; HL walks the header, DE the magic.
    LD   A,(DE)                    ; A magic byte.
    CP   (HL)                      ; Does the header match?
    JR   NZ,.FORMAT                ; Not a library.
    INC  HL                        ; The next header byte.
    INC  DE                        ; The next magic byte.
    DJNZ .MAGIC                    ; Until all four match.
    LD   A,(HL)                    ; Version 1.0:
    DEC  A                         ; major 1,
    JR   NZ,.FORMAT                ; else unknown;
    INC  HL                        ; minor 0,
    OR   (HL)                      ; else higher.
    JR   NZ,.FORMAT                ; Either is refused.
    LD   HL,(LB_BUF+6)             ; The runtime identity
    LD   (SH_HEAD+8),HL            ; goes into the directory's header,
    LD   HL,(LB_BUF+10)            ; and so does
    LD   (SH_HEAD+14),HL           ; the profile identity.
    LD   HL,(LB_BUF+8)             ; The library's helper-table version
    LD   DE,HP_VER                 ; may not be older
    OR   A                         ; than
    SBC  HL,DE                     ; the compiler's.
    JR   C,.COMPAT                 ; It is.
    LD   HL,(LB_BUF+33)            ; The key table's offset, a multiple of 128:
    LD   A,(LB_BUF+32)             ; its record is the offset's bits 7 to 30,
    RLA                            ; bit 7 into carry,
    ADC  HL,HL                     ; bits 7 to 22 into HL,
    LD   (SH_FCB+33),HL            ; the random record's low bytes,
    LD   A,(LB_BUF+35)             ; and bits 23 to 30
    RLA                            ; into A,
    LD   (SH_FCB+35),A             ; its high byte.
    LD   DE,SH_FCB                 ; Read that record:
    LD   C,LB_RAND                 ; the key table.
    CALL LB_READ                   ; Failures do not return.
    LD   HL,(LB_BUF)               ; Its count of keys
    LD   DE,HP_VER                 ; must reach
    OR   A                         ; the compiler's
    SBC  HL,DE                     ; version,
    JR   C,.COMPAT                 ; else it lacks the key;
    LD   HL,(LB_BUF+2*HP_VER)      ; and that version's key
    LD   DE,HP_KEY                 ; must be
    OR   A                         ; the compiler's
    SBC  HL,DE                     ; own.
    RET  Z                         ; The library suits the compiler.
.COMPAT:                       ; The helper tables differ.
    LD   HL,LB_NCOMP               ; L-COMPAT, which names nothing.
    JP   MS_FAIL                   ; Fail.
.FORMAT:                       ; Bad magic or version.
    LD   HL,LB_NFORM               ; NAME.BRL: L-FORMAT.
    JP   LB_FAIL                   ; Fail.

;@ROUTINE IN A OUT CARRY CLOBBERS A,BC,DE,HL,IX,IY,ZERO,SIGN,PARITY,HALFCARRY
; Open the library on drive A (0 the current one). Carry if it isn't there.

.TRY:                          ; A is the drive.
    PUSH AF                        ; Keep it across the clearing.
    CALL SH_BLANK                  ; A clear FCB.
    POP  AF                        ; The drive
    LD   (SH_FCB),A                ; is the FCB's.
    LD   HL,CL_LIB                 ; The library's name,
    LD   DE,SH_FCB+1               ; into the name field,
    LD   BC,8                      ; eight characters,
    LDIR                           ; then
    LD   HL,LB_TYPE+1              ; its type,
    LD   C,3                       ; BRL,
    LDIR                           ; into the type field.
    LD   DE,SH_FCB                 ; DE is the FCB for BDOS.
    LD   C,SH_OPEN                 ; Open it;
    CALL SH_BDOS                   ; A is $FF if it is absent,
    ADD  A,1                       ; which alone sets carry.
    RET                            ; Carry if not there.

;@ROUTINE IN C,DE CLOBBERS A,BC,DE,HL,IX,IY,CARRY,ZERO,SIGN,PARITY,HALFCARRY
; Read a record of the library with BDOS function C and FCB DE. A record
; read returns; the end of the file reports the library truncated
; (L-TRUNCATED), and any other status a read error, a disk's, neither of
; which returns.

LB_READ:                       ; C is the read, DE the FCB.
    CALL SH_BDOS                   ; Read the record; A is the status.
    OR   A                         ; Zero: read.
    RET  Z                         ; The record is in LB_BUF.
    DEC  A                         ; For the end of the file,
    LD   HL,LB_NTRUN               ; NAME.BRL: L-TRUNCATED.
    JR   Z,LB_FAIL                 ; Fail.
    LD   A,SH_RDISK                ; Otherwise a disk error's
    LD   (SH_RLOW),A               ; return code,
    LD   HL,SH_NIO                 ; and NAME.BRL: L-IO.

;@ROUTINE IN HL NORETURN
; Report diagnostic HL, its argument the library's file name, NAME.BRL,
; without padding or drive, as BLINK names it in its diagnostics, and
; fail.

LB_FAIL:                       ; HL is the message number.
    LD   DE,DG_ABUF                ; The name is spelled here:
    LD   (DG_ARG1),DE              ; argument 1.
    PUSH HL                        ; Keep the number.
    LD   HL,CL_LIB                 ; Its eight characters,
    LD   B,8                       ; less their padding.
.CHAR:                         ; B characters remain at HL.
    LD   A,(HL)                    ; The next.
    INC  HL                        ; Move on.
    CP   ' '                       ; Padding
    JR   Z,.PAD                    ; is left out.
    LD   (DE),A                    ; Anything else is kept.
    INC  DE                        ; The next place.
.PAD:                          ; The character is done.
    DJNZ .CHAR                     ; Until the name is spelled.
    LD   HL,LB_TYPE                ; Then the type, with its dot
    LD   BC,5                      ; and terminator.
    LDIR                           ; Spelled.
    POP  HL                        ; The number.
    JP   MS_FAIL                   ; Print it and fail.

;@ROUTINE CLOBBERS A,BC,DE,HL,IX,IY,CARRY,ZERO,SIGN,PARITY,HALFCARRY
; Choose the compilation stamp (object format §4.1) and write it into the
; directory's header. A program directory that an earlier compilation
; left, NAME.$DR on the spool drive, gives its stamp plus one; without
; one, the stamp is the CRC of the first part's first record, its text up
; to its $1A, with the R register folded into its low byte. Zero is
; skipped: no stream may carry it.

LB_STAMP:                      ; The parts are loaded; the streams are not open.
    CALL SH_BLANK                  ; A clear FCB.
    LD   HL,SH_SNAME               ; The streams' drive and name,
    LD   DE,SH_FCB                 ; nine bytes,
    LD   BC,9                      ; then
    LDIR                           ; the type
    LD   HL,BL_TDR                 ; $DR:
    LD   C,3                       ; the old directory,
    LDIR                           ; if there is one.
    LD   DE,LB_BUF                 ; Its first record
    LD   C,SH_DMA                  ; is read
    CALL SH_BDOS                   ; into the buffer.
    LD   DE,SH_FCB                 ; Open it;
    LD   C,SH_OPEN                 ; A is $FF
    CALL SH_BDOS                   ; if it is absent.
    INC  A                         ; $FF becomes zero:
    JR   Z,.NEW                    ; no earlier directory.
    LD   DE,SH_FCB                 ; Read
    LD   C,SH_READ                 ; its
    CALL SH_BDOS                   ; header.
    OR   A                         ; An empty file
    JR   NZ,.NEW                   ; has none.
    LD   HL,LB_BUF                 ; Its magic
    LD   DE,SH_HEAD                ; must be BSIP,
    LD   B,4                       ; the header's own.
.MAGIC:                        ; HL walks the old header, DE the new.
    LD   A,(DE)                    ; A magic byte.
    CP   (HL)                      ; Does it match?
    JR   NZ,.NEW                   ; Not a directory.
    INC  HL                        ; The next
    INC  DE                        ; bytes.
    DJNZ .MAGIC                    ; Until all four match.
    LD   HL,(LB_BUF+6)             ; Its stamp,
    JR   .NEXT                     ; plus one.
.NEW:                          ; No earlier directory: a CRC.
    LD   HL,$FFFF                  ; The CRC starts at $FFFF,
    LD   (SH_HEAD+6),HL            ; where the stamp goes.
    LD   DE,(SH_PARTS+1)           ; DE walks the first part,
    LD   C,128                     ; one record at most.
.BYTE:                         ; DE is the next byte, C bytes remain.
    LD   HL,(SH_PARTS+3)           ; The part's end:
    OR   A                         ; is DE
    SBC  HL,DE                     ; at it?
    JR   Z,.MIX                    ; The part is shorter than a record.
    LD   A,(DE)                    ; The byte
    LD   HL,SH_HEAD+6              ; joins
    CALL OUT_UPD                   ; the CRC.
    INC  DE                        ; The next byte.
    DEC  C                         ; One fewer.
    JR   NZ,.BYTE                  ; Until a record is done.
.MIX:                          ; The CRC is complete.
    LD   HL,(SH_HEAD+6)            ; Fold the R register,
    LD   A,R                       ; as good a source of change
    XOR  L                         ; as CP/M 2.2 has,
    LD   L,A                       ; into its low byte;
    DEC  HL                        ; then the step below restores it.
.NEXT:                         ; HL is one less than the stamp.
    INC  HL                        ; The stamp,
    LD   A,H                       ; unless
    OR   L                         ; that is zero,
    JR   NZ,.SET                   ; which no stream may carry:
    INC  HL                        ; then one.
.SET:                          ; HL is the stamp.
    LD   (SH_HEAD+6),HL            ; The header carries it to every stream.
    RET                            ; Chosen.

; ---- data -------------------------------------------------------------------

LB_MAGIC:                      ; A library's magic.
    DB   "BSIR"                    ; Basie runtime library.
LB_TYPE:                       ; The library's type, after its name.
    DB   ".BRL",0                  ; Spelled with the dot; copied without it.
