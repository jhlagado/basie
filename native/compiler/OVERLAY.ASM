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
;                           OV_AREA, MS_SHOWD at OV_AREA+3), and the streams
;                           deleted after a failure (MS_SCRUB at OV_AREA+6)
;    OV_PREP   PREP.ASM     the state a compilation begins with (PP_RUN at
;                           OV_AREA), loaded once by PR_BUILD before NAMES
;    OV_SPILL  SPILL.ASM    the blob writer's spill to NAME.$CD and its
;                           reading back (SP_WRITE, SP_RBACK), above NAMES
;                           as FLOAT is, through OV_SCALL
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
;    OV_OWNS   OWNERS.ASM   record and pool declarations and owners'
;                           descriptors (OV_PCALL, for POOLS.ASM, reaches
;                           its entries),
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
;  boundary. It is opened once, by the start-up before the first load
;  (OV_OPEN, INIT.ASM), on the current drive, else on A:: the command
;  line, option L included, is itself an overlay.
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
OV_PREP EQU  7                 ; A compilation's starting state.
OV_SPILL EQU  8                ; The blob writer's spill to NAME.$CD.
OV_HEAD EQU  9                 ; Bytes of BASIE.OVL's header before its directory.
OV_RAND EQU  33                ; BDOS read random: the record is in the FCB.

;@ROUTINE IN A CLOBBERS A,BC,DE,HL,IX,IY,CARRY,ZERO,SIGN,PARITY,HALFCARRY
; Load overlay A at its address, unless it was the last loaded; the
; start-up opened BASIE.OVL (OV_OPEN, INIT.ASM). Failure does not return.

OV_LOAD:                       ; A is the overlay.
    LD   HL,OV_CUR                 ; The one loaded last:
    CP   (HL)                      ; is it this one?
    RET  Z                         ; Then it is there.
    LD   (OV_CUR),A                ; The overlay is the one loaded.
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

OV_FCALL:                      ; A is the offset, HL the argument.
    LD   B,OV_FLOAT                ; FLOAT's;
    JR   OV_XCALL                  ; called.

;@ROUTINE IN A,HL OUT HL CLOBBERS A,BC,DE,CARRY,ZERO,SIGN,PARITY,HALFCARRY
; Load overlay B (OWNERS for OV_PCALL, FLOAT for OV_FCALL) unless it is
; the one loaded last, and run its entry at offset A with HL; A, HL and
; the flags return as the entry leaves them. IX and IY, which loading may
; change, are kept.

OV_PCALL:                      ; A is the entry's offset.
    LD   B,OV_OWNS                 ; OWNERS'; fall into OV_XCALL.
OV_XCALL:                      ; B is the overlay.
    PUSH IX                        ; Keep IX
    PUSH IY                        ; and IY,
    PUSH HL                        ; the argument
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
    LD   E,A                       ; the
    ADC  A,D                       ; entry's
    SUB  E                         ; address,
    LD   D,A                       ; DE.
    POP  HL                        ; HL is the argument.
    CALL .RUN                      ; Run it.
    POP  IY                        ; IY
    POP  IX                        ; and IX again;
    RET                            ; A, HL and the flags are the entry's.
.RUN:                          ; DE is the entry.
    PUSH DE                        ; Its address
    RET                            ; is jumped to; it returns above.

;@ROUTINE IN A,HL OUT CARRY CLOBBERS A,BC,DE,HL,ZERO,SIGN,PARITY,HALFCARRY
; Run the SPILL overlay's entry A with HL (OV_XCALL), from wherever the
; blob writer was called, OWNERS' or FLOAT's code among them: SPILL loads
; above NAMES, so NAMES stays, and the overlay it replaced is loaded again
; before the return. Carry returns as the entry leaves it; IY is kept
; (OWNERS' descriptor walk holds a frame in it while it emits).

OV_SCALL:                      ; A is the entry, HL its argument.
    LD   B,A                       ; (the entry)
    LD   A,(OV_CUR)                ; The overlay loaded,
    PUSH AF                        ; kept.
    LD   A,B                       ; The entry
    LD   B,OV_SPILL                ; of SPILL
    CALL OV_XCALL                  ; runs.
    POP  BC                        ; B is the overlay it replaced.
    PUSH AF                        ; (the entry's flags)
    LD   A,B                       ; NAMES,
    CP   OV_NAMES                  ; intact below SPILL,
    JR   NZ,.LOAD                  ; is current again
    LD   (OV_CUR),A                ; as it is;
    JR   .BACK                     ; any other
.LOAD:                         ; is loaded
    PUSH IY                        ; again,
    CALL OV_LOAD                   ; IY kept
    POP  IY                        ; (OV_LOAD's BDOS calls may not).
.BACK:                         ; The entry's
    POP  AF                        ; flags.
    RET                            ; Done.

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

;@ROUTINE NORETURN
; Report BASIE.OVL missing or unusable, L-MISSING with its name, by the
; number and argument alone: the text of BASIE.MSG needs an overlay.

OV_FAIL:                       ; Nothing is loaded that could say more.
    LD   HL,OV_MISS                ; The number and argument
    JP   SH_FAIL                   ; are printed, and the build fails.

; ---- data ------------------------------------------------------------------

OV_MISS:                       ; L-MISSING by number and argument (D39).
    DB   "Error 225: Message 225: BASIE.OVL",0 ; As BASIE prints it without BASIE.MSG.
