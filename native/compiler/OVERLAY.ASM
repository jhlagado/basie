;==========================================================================
;  Overlays
;==========================================================================
;
;  BASIE.COM's one-shot code and its predeclared names are not resident:
;  they are overlays in BASIE.OVL, each loaded into the overlay area,
;  which begins at OV_AREA, the end of the image, when it is first needed
;  (toolchain §7.3). native/compiler/build.ts assembles each overlay at
;  its load address against the resident image's symbols and writes the
;  file; the area is as large as the largest overlay, in whole records.
;
;    OV_BEGIN  COMMAND.ASM  the start-up, loaded once, its entries run in
;              LIBRARY.ASM  turn (BG_TAB at OV_AREA): the command line
;              BLOPEN.ASM   (CL_READ), the library check (LB_FIRST), the
;              PARTS.ASM    parts and their includes (SH_BEGIN), then the
;                           stamp and the streams (LB_OPEN)
;    OV_NAMES  PREDEF.ASM   the predeclared names (HP_NAMES at OV_AREA),
;                           loaded for the whole compilation
;    OV_CHAIN  CHAIN.ASM    the chain to BLINK (CH_RUN at OV_AREA), or the
;                           streams closed first, with BLCLOSE.ASM (CH_DONE
;                           at OV_AREA+3)
;    OV_DIAG   MESSAGE.ASM  diagnostics from BASIE.MSG (MS_SHOWE at
;                           OV_AREA, MS_SHOWD at OV_AREA+3)
;    OV_LOOK   LOOKUP.ASM   option T: a trap's address looked up (LK_RUN at
;                           OV_AREA), which the command line's reading runs
;  PARTNAME.ASM, the parts' names, is assembled into BEGIN and DIAG, which
;  each need it, and FILENAME.ASM, CP/M names, into BEGIN and LOOKUP.
;
;    OV_FLOAT  FLOAT.ASM    f32 constants: decimal literals converted and
;                           f32 operations folded (OV_FSCAN, OV_ITOF,
;                           OV_FTOI and OV_FOLD reach its entries),
;                           loaded above NAMES, at OV_AREA plus NAMES'
;                           records, when first needed and kept
;    OV_OWNS   OWNERS.ASM   pool declarations and owners' descriptors
;                           (OV_PCALL, for POOLS.ASM, reaches its entries),
;                           loaded above NAMES in FLOAT's place
;  A later overlay may load above another in the area, so that both are
;  there at once: FLOAT and OWNERS load after the predeclared names, which
;  stay loaded while they are used, so the area is as large as NAMES'
;  records and the larger of them together. They replace each other, each
;  loaded again when next needed. The end of a routine and the writing of
;  a blob, used by every routine, are resident (CLOSE.ASM, BLEND.ASM).
;
;  BASIE.OVL is magic BSIO, version 1.0, the 16-bit sum of the resident
;  image's bytes from $0100 to OV_AREA, which ties the file to this
;  BASIE.COM, a count, and four bytes per overlay: its load address, its
;  first record and its records; then the overlays, each from a record
;  boundary. It is opened once, at the first load, on the current drive,
;  else on A:: the command line, option L included, is itself an overlay.
;  Its directory is kept in OV_DIR, and the file stays open in OV_FCB for
;  the later loads, which read whole records with BDOS random reads
;  straight to the load address.
;
;  Principal entry:
;    OV_LOAD   load overlay A unless it is the one loaded last
;
;  Failure: without a usable BASIE.OVL, or a record of it that can't be
;  read, nothing can report a diagnostic from BASIE.MSG, so the number and
;  argument are printed, as D39 has it without the message file, and the
;  build fails.

OV_BEGIN EQU  0                ; The start-up: command line, library, parts, streams.
OV_NAMES EQU  1                ; The predeclared names.
OV_CHAIN EQU  2                ; The chain to BLINK.
OV_DIAG EQU  3                 ; Diagnostics from BASIE.MSG.
OV_LOOK EQU  4                 ; Option T: a trap's address looked up.
OV_FLOAT EQU  5                ; f32 constants: literals and folding.
OV_OWNS EQU  6                 ; Owner descriptors.
OV_HEAD EQU  9                 ; Bytes of BASIE.OVL's header before its directory.
OV_RAND EQU  33                ; BDOS read random: the record is in the FCB.

;@ROUTINE IN A CLOBBERS A,BC,DE,HL,IX,IY,CARRY,ZERO,SIGN,PARITY,HALFCARRY
; Load overlay A at its address, unless it was the last loaded, opening
; BASIE.OVL at the first load. Failure does not return.

OV_LOAD:                       ; A is the overlay.
    LD   HL,OV_CUR                 ; The one loaded last:
    CP   (HL)                      ; is it this one?
    RET  Z                         ; Then it is there.
    PUSH AF                        ; Keep it.
    LD   A,(OV_FCB+1)              ; BASIE.OVL's name is in its FCB
    OR   A                         ; once it is open;
    CALL Z,OV_OPEN                 ; open it the first time.
    POP  AF                        ; The overlay
    LD   (OV_CUR),A                ; is the one loaded.
    ADD  A,A                       ; Its four bytes
    ADD  A,A                       ; in the directory:
    LD   E,A                       ; DE is
    LD   D,0                       ; their offset,
    LD   HL,OV_DIR                 ; HL
    ADD  HL,DE                     ; their address.
    CALL WD_GET                    ; DE is its load address, C its
    LD   C,(HL)                    ; first record,
    INC  HL                        ; B its
    LD   B,(HL)                    ; records.
    EX   DE,HL                     ; HL is where they go.
.NEXT:                         ; C is the next record, B those left.
    CALL OV_READ                   ; Read it to HL.
    JP   C,OV_FAIL                 ; It can't be read.
    INC  C                         ; The next record
    LD   DE,128                    ; follows
    ADD  HL,DE                     ; this one.
    DJNZ .NEXT                     ; Until all are read.
    RET                            ; The overlay is there.

;@ROUTINE CLOBBERS A,BC,DE,HL,CARRY,ZERO,SIGN,PARITY,HALFCARRY
; The FLOAT overlay's entries (FLOAT.ASM), each loading it above NAMES
; first, with its argument in HL: OV_FSCAN converts the decimal literal
; being scanned (FL_SCAN), OV_ITOF the integer at HL to f32, with carry
; when it was rounded (FL_ITOF), OV_FTOI the f32 at HL to an integer
; (FL_FTOI), and OV_FOLD folds EX_LVAL op EX_RVAL to EX_KVAL, with carry
; past the largest f32 (FL_ARITH).

OV_FSCAN:                      ; A literal: entry 0.
    XOR  A                         ; Its offset;
    JR   OV_FCALL                  ; called.
OV_ITOF:                       ; An integer to f32: entry 3.
    LD   A,3                       ; Its offset;
    JR   OV_FCALL                  ; called.
OV_FTOI:                       ; An f32 to an integer: entry 6.
    LD   A,6                       ; Its offset;
    JR   OV_FCALL                  ; called.
OV_FOLD:                       ; An operation folded: entry 9.
    LD   A,9                       ; Its offset; fall into OV_FCALL.

;@ROUTINE IN A,HL CLOBBERS A,BC,DE,HL,CARRY,ZERO,SIGN,PARITY,HALFCARRY
; Load the FLOAT overlay unless it is the one loaded last, and run its
; entry at offset A with HL; carry returns as the entry leaves it. IX and
; IY, which loading may change, are kept.

OV_FCALL:                      ; A is the offset, HL the argument.
    PUSH IX                        ; Keep IX
    PUSH IY                        ; and IY,
    PUSH HL                        ; the argument
    PUSH AF                        ; and the offset.
    LD   A,OV_FLOAT                ; The overlay
    CALL OV_LOAD                   ; is loaded, above NAMES.
    POP  AF                        ; The offset
    LD   HL,(OV_DIR+4*OV_FLOAT)    ; from its load address
    ADD  A,L                       ; is
    LD   L,A                       ; the
    ADC  A,H                       ; entry's
    SUB  L                         ; address,
    LD   D,A                       ; DE.
    LD   E,L                       ; (its low byte)
    POP  HL                        ; HL is the argument.
    CALL .RUN                      ; Run the entry.
    POP  IY                        ; IY
    POP  IX                        ; and IX again;
    RET                            ; the flags are the entry's.
.RUN:                          ; DE is the entry.
    PUSH DE                        ; Its address
    RET                            ; is jumped to; it returns above.

;@ROUTINE IN A OUT HL CLOBBERS A,BC,DE,CARRY,ZERO,SIGN,PARITY,HALFCARRY
; Load the OWNERS overlay (OV_PCALL) unless it is the one loaded last,
; and run its entry at offset A; A, HL
; and the flags return as the entry leaves them. IX and IY, which loading
; may change, are kept.

OV_PCALL:                      ; A is the entry's offset.
    LD   B,OV_OWNS                 ; OWNERS'; fall into OV_XCALL.
OV_XCALL:                      ; B is the overlay.
    PUSH IX                        ; Keep IX
    PUSH IY                        ; and IY,
    PUSH AF                        ; and the offset.
    LD   A,B                       ; The overlay
    PUSH AF                        ; (kept)
    CALL OV_LOAD                   ; is loaded, above NAMES.
    POP  AF                        ; Its four
    ADD  A,A                       ; bytes in
    ADD  A,A                       ; the directory,
    LD   E,A                       ; DE
    LD   D,0                       ; from
    LD   HL,OV_DIR                 ; OV_DIR:
    ADD  HL,DE                     ; its load
    LD   E,(HL)                    ; address,
    INC  HL                        ; DE.
    LD   D,(HL)                    ; The offset
    POP  AF                        ; from it
    ADD  A,E                       ; is
    LD   L,A                       ; the
    ADC  A,D                       ; entry's
    SUB  L                         ; address,
    LD   H,A                       ; HL.
    CALL .RUN                      ; Run it.
    POP  IY                        ; IY
    POP  IX                        ; and IX again;
    RET                            ; A and the flags are the entry's.
.RUN:                          ; HL is the entry.
    JP   (HL)                      ; It returns above.

;@ROUTINE IN C,HL OUT CARRY CLOBBERS A,DE,IX,IY,ZERO,SIGN,PARITY,HALFCARRY
; Read record C of BASIE.OVL to HL. Carry if it can't be read. B, C and
; HL are kept.

OV_READ:                       ; C is the record, HL where it goes.
    PUSH BC                        ; Keep the counts
    PUSH HL                        ; and the place.
    LD   A,C                       ; The record
    LD   (OV_FCB+33),A             ; is the random record; its high bytes are zero.
    EX   DE,HL                     ; DE is where it goes:
    LD   C,SH_DMA                  ; the DMA
    CALL SH_BDOS                   ; address.
    LD   DE,OV_FCB                 ; Read
    LD   C,OV_RAND                 ; the record;
    CALL SH_BDOS                   ; A is zero if it was read.
    POP  HL                        ; The place
    POP  BC                        ; and the counts.
    ADD  A,$FF                     ; Carry unless A was zero.
    RET                            ; Carry if it can't be read.

;@ROUTINE CLOBBERS A,BC,DE,HL,IX,IY,CARRY,ZERO,SIGN,PARITY,HALFCARRY
; Open BASIE.OVL, on the current drive, else on A:, and check that it is
; this BASIE.COM's: its magic and version, and its sum of the resident
; image. Its directory goes to OV_DIR. A file that is missing, or not
; this compiler's, does not return.

OV_OPEN:                       ; The overlay area is free: nothing is loaded.
    XOR  A                         ; The current drive,
    CALL OV_TRY                    ; first;
    RET  NC                        ; found and sound.
    LD   A,1                       ; Then A:.
    CALL OV_TRY                    ; Open it there.
    RET  NC                        ; Found and sound; fall into OV_FAIL.

;@ROUTINE NORETURN
; Report BASIE.OVL missing or unusable, L-MISSING with its name, by the
; number and argument alone: the text of BASIE.MSG needs an overlay.

OV_FAIL:                       ; Nothing is loaded that could say more.
    LD   HL,OV_MISS                ; The number and argument
    JP   SH_FAIL                   ; are printed, and the build fails.

;@ROUTINE IN A OUT CARRY CLOBBERS A,BC,DE,HL,IX,IY,ZERO,SIGN,PARITY,HALFCARRY
; Open BASIE.OVL on drive A (0 the current one), read its first record
; into the overlay area and check it; copy its directory to OV_DIR. Carry
; if it can't be used.

OV_TRY:                        ; A is the drive.
    LD   HL,OV_FCB                 ; The FCB
    LD   (HL),A                    ; takes the drive,
    INC  HL                        ; then
    EX   DE,HL                     ; the name
    LD   HL,OV_NAME                ; and type,
    LD   BC,SH_NLEN                ; eleven
    LDIR                           ; characters,
    LD   B,SH_FLEN-SH_NLEN-1       ; then zeros
    XOR  A                         ; through the
.ZERO:                         ; random record.
    LD   (DE),A                    ; Clear
    INC  DE                        ; one
    DJNZ .ZERO                     ; byte.
    LD   DE,OV_FCB                 ; Open
    LD   C,SH_OPEN                 ; it;
    CALL SH_BDOS                   ; A is $FF if it is absent,
    ADD  A,1                       ; which alone sets carry.
    RET  C                         ; Not on this drive.
    LD   C,0                       ; Its first record,
    LD   HL,OV_AREA                ; the header and directory,
    CALL OV_READ                   ; into the area;
    RET  C                         ; unreadable.
    LD   HL,OV_AREA                ; Its magic and version
    LD   DE,OV_MAGIC               ; must be
    LD   B,6                       ; BSIO 1.0:
.CHECK:                        ; HL walks the header, DE the magic.
    LD   A,(DE)                    ; A byte
    CP   (HL)                      ; of it.
    SCF                            ; Any other
    RET  NZ                        ; is unusable.
    INC  HL                        ; The next
    INC  DE                        ; bytes.
    DJNZ .CHECK                    ; Until all six match.
    LD   BC,OV_AREA                ; The resident image's bytes,
    DEC  B                         ; $0100 to OV_AREA, BC of them,
    LD   HL,$0100                  ; from there,
    LD   DE,0                      ; summed in DE.
.SUM:                          ; BC bytes remain at HL.
    LD   A,(HL)                    ; The next
    ADD  A,E                       ; is added
    LD   E,A                       ; to the low byte,
    JR   NC,.NOCARRY               ; carrying
    INC  D                         ; into the high.
.NOCARRY:                      ; The byte is counted.
    INC  HL                        ; The next.
    DEC  BC                        ; One fewer.
    LD   A,B                       ; Any
    OR   C                         ; left?
    JR   NZ,.SUM                   ; Add it.
    LD   HL,(OV_AREA+6)            ; The file's sum
    OR   A                         ; must
    SBC  HL,DE                     ; be this image's,
    SCF                            ; else the file belongs
    RET  NZ                        ; to another BASIE.COM.
    LD   A,(OV_AREA+8)             ; Its overlays: four bytes each
    ADD  A,A                       ; of directory,
    ADD  A,A                       ; at most OV_DCAP of them,
    LD   C,A                       ; and at least one,
    LD   B,0                       ; BC bytes,
    LD   HL,OV_AREA+OV_HEAD        ; after the header,
    LD   DE,OV_DIR                 ; are kept.
    LDIR                           ; Carry stays clear:
    RET                            ; the file is open and sound.

; ---- data ------------------------------------------------------------------

OV_NAME:                       ; BASIE.OVL's name, as an FCB holds it.
    DB   "BASIE   OVL"             ; Eight characters, space-padded, and the type.
OV_MAGIC:                      ; Its magic and version.
    DB   "BSIO",1,0                ; Basie overlays, 1.0.
OV_MISS:                       ; L-MISSING by number and argument (D39).
    DB   "Error 225: Message 225: BASIE.OVL",0 ; As BASIE prints it without BASIE.MSG.
