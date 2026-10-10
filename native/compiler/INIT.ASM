;==========================================================================
;  The start-up, in the overlay area
;==========================================================================
;
;  The code that runs once, before the first overlay is loaded: BASIE.COM
;  carries it after OV_AREA, in the overlay area, where CP/M loads it with
;  the rest of the file and the first overlay, BEGIN, replaces it. So it
;  takes no room of its own: the memory the compiler needs is the image to
;  OV_AREA and the area. It sets the stack and the source's bounds, opens
;  BASIE.OVL and checks it, reading its first record into the area's last
;  (OV_HDR), above this code, and goes on in the image (SH_GO). build.ts
;  checks that it ends below OV_HDR.
;
;  Principal entries:
;    SH_START  the program entry, reached from the jump at $0100
;    OV_OPEN   open BASIE.OVL and check that it is this BASIE.COM's

OV_HDR EQU  MM_WBASE-128       ; BASIE.OVL's first record, read by OV_TRY.

SH_CEND:                       ; End of the shell, which the build measures from SH_CBEG.
OV_AREA:                       ; The overlay area: build.ts checks it ends below MM_WBASE.

;@ROUTINE NORETURN
; Set the stack below the BDOS entry and the source's bounds, clear the
; diagnostic's arguments, open BASIE.OVL, and go on in the image (SH_GO).

SH_START:                      ; Entered from the jump at $0100.
    LD   HL,(SH_BDOS+1)            ; HL is the BDOS entry, the top of memory.
    LD   SP,HL                     ; The stack grows down from there, over the CCP.
    LD   DE,-MM_STACK              ; Keep MM_STACK bytes below it for the stack.
    ADD  HL,DE                     ; HL is the first byte the source may not use.
    LD   (SH_LIMIT),HL             ; Each record read is checked against it.
    LD   HL,MM_SRC                 ; The first part loads at the base of the source.
    LD   (SH_LOADP),HL             ; Start the load point there.
    LD   A,SH_RSRC                 ; A failure is a source error
    LD   (SH_RLOW),A               ; unless a disk fails.
    LD   HL,0                      ; Zero:
    LD   (DG_ARG1),HL              ; no diagnostic has
    LD   (DG_ARG2),HL              ; an argument yet,
    XOR  A                         ; nor waits for
    LD   (DG_MODE),A               ; its part's rest (DG_PLACE).
    CALL OV_OPEN                   ; BASIE.OVL is opened and checked;
    LD   HL,$FFFF                  ; no overlay runs
    LD   (OV_RUN),HL               ; or is loaded yet (OV_CUR):
    JP   SH_GO                     ; the start-up goes on there.

;@ROUTINE CLOBBERS A,BC,DE,HL,IX,IY,CARRY,ZERO,SIGN,PARITY,HALFCARRY
; Open BASIE.OVL, on the current drive, else on A:, and check that it is
; this BASIE.COM's: its magic and version, and its sum of the resident
; image. Its directory goes to OV_DIR. A file that is missing, or not
; this compiler's, does not return.

OV_OPEN:                       ; Run from the area, before anything is loaded.
    XOR  A                         ; The current drive,
    CALL OV_TRY                    ; first;
    RET  NC                        ; found and sound.
    LD   A,1                       ; Then A:.
    CALL OV_TRY                    ; Open it there.
    RET  NC                        ; Found and sound;
    JP   OV_FAIL                   ; else L-MISSING.

;@ROUTINE IN A OUT CARRY CLOBBERS A,BC,DE,HL,IX,IY,ZERO,SIGN,PARITY,HALFCARRY
; Open BASIE.OVL on drive A (0 the current one), read its first record
; into the overlay area's last (OV_HDR, above this code) and check it;
; copy its directory to OV_DIR. Carry if it can't be used.

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
    LD   HL,OV_HDR                 ; the header and directory,
    CALL OV_READ                   ; into the area's last;
    RET  C                         ; unreadable.
    LD   HL,OV_HDR                 ; Its magic and version
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
    LD   HL,(OV_HDR+6)             ; The file's sum
    OR   A                         ; must
    SBC  HL,DE                     ; be this image's,
    SCF                            ; else the file belongs
    RET  NZ                        ; to another BASIE.COM.
    LD   A,(OV_HDR+8)              ; Its overlays: four bytes each
    ADD  A,A                       ; of directory,
    ADD  A,A                       ; at most OV_DCAP of them,
    LD   C,A                       ; and at least one,
    LD   B,0                       ; BC bytes,
    LD   HL,OV_HDR+OV_HEAD         ; after the header,
    LD   DE,OV_DIR                 ; are kept.
    LDIR                           ; Carry stays clear:
    RET                            ; the file is open and sound.

; ---- data ------------------------------------------------------------------

OV_NAME:                       ; BASIE.OVL's name, as an FCB holds it.
    DB   "BASIE   OVL"             ; Eight characters, space-padded, and the type.
OV_MAGIC:                      ; Its magic and version.
    DB   "BSIO",1,0                ; Basie overlays, 1.0.

MM_END:                        ; End of BASIE.COM's file, within the overlay area.
