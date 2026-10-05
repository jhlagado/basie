;==========================================================================
;  Source parts' names
;==========================================================================
;
;  The source parts' names: those the command line saved (SH_NAMES, in
;  SHELL.ASM's workspace) and those of the part table (SOURCE.ASM), each
;  a drive and an 11-character name as an FCB holds them, spelled for the
;  line stream and for diagnostics. No resident code needs them, so this
;  file is assembled into each overlay that does: COMMAND, START and DIAG
;  (build.ts).
;
;  Principal entries:
;    SH_PNAME  address the command line's part A's saved drive and name
;    SH_TYPED  spell a part as the line stream names it, NAME.TYP
;    SH_SPELL  spell a part as a diagnostic names it, D:NAME.TYP

;@ROUTINE IN A OUT HL CLOBBERS DE,CARRY,HALFCARRY
; HL = the saved drive and name of the part whose index is A (0-based),
; at SH_NAMES + SH_SLOT * A.

SH_PNAME:                      ; A is a part index below CL_PCAP.
    LD   L,A                       ; L is the index.
    LD   H,0                       ; Zero-extend it into HL.
    ADD  HL,HL                     ; HL = 2 * index.
    ADD  HL,HL                     ; HL = 4 * index.
    LD   D,H                       ; DE = 4 * index, added back below.
    LD   E,L                       ; Its low byte.
    ADD  HL,HL                     ; HL = 8 * index.
    ADD  HL,DE                     ; HL = 12 * index, the slot's offset.
    LD   DE,SH_NAMES               ; DE is the base of the saved names.
    ADD  HL,DE                     ; HL is the name slot.
    RET                            ; Return the slot in HL.

;@ROUTINE IN HL OUT B,HL CLOBBERS A,DE,CARRY,ZERO,SIGN,PARITY,HALFCARRY
; Spell the part whose drive and name are at HL as the reference compiler
; names a part in the line stream, NAME.TYP without padding or drive, at
; SH_TEXT: HL addresses it and B is its length.

SH_TYPED:                      ; HL is the part's drive and name.
    INC  HL                        ; Skip the drive.
    LD   DE,SH_TEXT                ; The spelling is built here.
    CALL SH_NTYPE                  ; NAME.TYP.
    EX   DE,HL                     ; HL is the spelling's end.
    LD   DE,SH_TEXT                ; Its start.
    OR   A                         ; Clear carry.
    SBC  HL,DE                     ; HL is its length,
    LD   B,L                       ; at most twelve.
    EX   DE,HL                     ; HL is the spelling.
    RET                            ; B is its length.

;@ROUTINE IN DE,HL OUT HL CLOBBERS A,B,DE,CARRY,ZERO,SIGN,PARITY,HALFCARRY
; Spell the part whose drive and name are at HL, at DE, as D:NAME.TYP,
; zero-terminated, without padding, and without the drive when the part
; was on the current drive. HL addresses the spelling.

SH_SPELL:                      ; HL is the part's name, DE the place for it.
    PUSH DE                        ; The spelling's start, returned in HL.
    LD   A,(HL)                    ; A is the drive: 0 current, 1 for A:.
    INC  HL                        ; HL is the name.
    OR   A                         ; Was a drive named?
    JR   Z,.NAME                   ; No: the name alone.
    ADD  A,'A'-1                   ; Make the drive a letter,
    LD   (DE),A                    ; spelled
    INC  DE                        ; first,
    LD   A,':'                     ; then the colon.
    LD   (DE),A                    ; Store it.
    INC  DE                        ; The name follows.
.NAME:                         ; HL is the saved name.
    CALL SH_NTYPE                  ; NAME.TYP.
    XOR  A                         ; Terminate
    LD   (DE),A                    ; the spelling.
    POP  HL                        ; HL is its start.
    RET                            ; Spelled.

;@ROUTINE IN DE,HL OUT DE,HL CLOBBERS A,B,CARRY,ZERO,SIGN,PARITY,HALFCARRY
; Copy the saved name and type at HL to DE as NAME.TYP, leaving out the
; spaces that pad them. DE and HL are left after them.

SH_NTYPE:                      ; HL is a saved name, DE the place for it.
    LD   B,8                       ; The name's eight characters,
    CALL .FIELD                    ; less their padding.
    LD   A,'.'                     ; A dot
    LD   (DE),A                    ; separates it
    INC  DE                        ; from the type.
    LD   B,3                       ; The type's three characters,
                                   ; less their padding, fall into .FIELD.

;@ROUTINE IN B,DE,HL OUT DE,HL CLOBBERS A,B,CARRY,ZERO,SIGN,PARITY,HALFCARRY
; Copy the B characters at HL to DE, leaving out the spaces that pad them.

.FIELD:                        ; B characters remain at HL.
    LD   A,(HL)                    ; The next one.
    INC  HL                        ; HL moves on whether or not it is kept.
    CP   ' '                       ; Spaces are padding.
    JR   Z,.PAD                    ; Leave it out.
    LD   (DE),A                    ; Keep anything else.
    INC  DE                        ; Move on.
.PAD:                          ; The character is done.
    DJNZ .FIELD                    ; Until the field is copied.
    RET                            ; DE is after the copy.
