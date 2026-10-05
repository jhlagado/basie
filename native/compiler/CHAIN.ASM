;==========================================================================
;  Chaining to BLINK
;==========================================================================
;
;  When a compilation succeeds, and when option X asks for a link alone,
;  BASIE.COM runs BLINK.COM (toolchain §2, §4 phase 3). CP/M 2.2 has no
;  call that runs another program, so, as Turbo Pascal's Execute did,
;  BASIE writes the command tail BLINK is to read at $0080, opens
;  BLINK.COM, copies a small loader and the open FCB to the top of memory,
;  below the BDOS entry, and enters it. The loader reads BLINK.COM to $0100
;  a record at a time, sets the DMA address back to $0080, as the CCP
;  leaves it, and starts BLINK, which takes its stack from $0006.
;
;  Principal entry, the CHAIN overlay's (OVERLAY.ASM):
;    CH_RUN    run BLINK.COM with the build's tail, at OV_AREA
;
;  The tail: the first part's name as the command line gave it, drive and
;  type included, then the options as given, less X, which BLINK does not
;  take, and less the spaces in the list; BLINK takes every other, since
;  CL_READ checked them all and C and T never chain. It is never longer
;  than the tail it comes from. BLINK.COM is looked for on option L's
;  drive, else the current one, then on A: (§7.3). If it is not there,
;  BASIE reports it as L-MISSING and fails with $FF12, a link error,
;  leaving the streams for a later BLINK.
;
;  The loader refers to nothing of BASIE's, which BLINK overwrites, and to
;  itself only by relative jumps, so it runs wherever it is copied. A read
;  error warm boots: BLINK is not whole.

CH_RLINK EQU  $12              ; Return code's low byte: a link error, $FF12.
CH_TAIL EQU  BL_CODE           ; The new tail is built here before it moves.

;@ROUTINE NORETURN
; The overlay's entry, at OV_AREA: run BLINK.COM (CH_RUN).

CH_ENTRY:                      ; At OV_AREA.
    JP   CH_RUN                    ; Run BLINK.

;@ROUTINE IN DE,HL NORETURN
; The loader: read the file whose open FCB is DE to HL, $0100, and start
; it there. It is copied to the top of memory, with the FCB after it.

CH_LOAD:                       ; HL is the load address, DE the FCB.
    PUSH HL                        ; Keep the load address
    PUSH DE                        ; and the FCB across the calls.
    EX   DE,HL                     ; The next record
    LD   C,SH_DMA                  ; goes to
    CALL SH_BDOS                   ; the load address.
    POP  DE                        ; The FCB:
    PUSH DE                        ; read
    LD   C,SH_READ                 ; the next
    CALL SH_BDOS                   ; record.
    POP  DE                        ; The FCB
    POP  HL                        ; and the load address.
    OR   A                         ; Was a record read?
    JR   NZ,.LOADED                ; No: the end of the file, or an error.
    LD   BC,128                    ; The next record
    ADD  HL,BC                     ; goes after it.
    JR   CH_LOAD                   ; Read it.
.LOADED:                       ; A is 1 at the end of the file.
    DEC  A                         ; A read error
    JP   NZ,0                      ; leaves BLINK in pieces: warm boot.
    LD   DE,SH_TAIL                ; The default DMA address,
    LD   C,SH_DMA                  ; $0080,
    CALL SH_BDOS                   ; as the CCP leaves it.
    JP   $0100                     ; Start BLINK.
CH_FCB:                        ; Where the FCB follows the loader.
CH_LEN EQU  CH_FCB-CH_LOAD+SH_FLEN ; The loader's bytes at the top of memory.

;@ROUTINE NORETURN
; Run BLINK.COM with the tail that describes the build.

CH_RUN:                        ; The streams are closed, or X was given.
    LD   A,(CL_SEEN+CL_IL)         ; Option L's drive, or the current one,
    CALL .TRY                      ; first;
    JR   NC,.FOUND                 ; found there.
    LD   A,1                       ; Then A:.
    CALL .TRY                      ; Open it there.
    JR   NC,.FOUND                 ; Found.
    LD   A,CH_RLINK                ; A link
    LD   (SH_RLOW),A               ; error's code,
    LD   HL,CH_NAME                ; and BLINK.COM,
    LD   DE,DG_ABUF                ; copied out of the overlay area,
    LD   (DG_ARG1),DE              ; which the diagnostics' overlay takes,
    LD   BC,10                     ; with its terminator,
    LDIR                           ; not found
    LD   HL,SH_NMISS               ; (L-MISSING).
    JP   MS_FAIL                   ; Fail.
.FOUND:                        ; SH_FCB holds BLINK.COM, open.
    LD   HL,SH_TAIL+1              ; The old tail, upper-cased and ended.
    LD   DE,CH_TAIL+1              ; The new one begins
    LD   A,' '                     ; with the space
    LD   (DE),A                    ; the CCP puts first,
    INC  DE                        ; then the first part,
    CALL .SKIP                     ; after the spaces before it.
.PART:                         ; HL walks it, DE the new tail.
    LD   A,(HL)                    ; Its characters
    OR   A                         ; up to the end,
    JR   Z,.ENDED                  ; or
    CP   ' '                       ; a space,
    JR   Z,.OPTS                   ; or
    CP   ','                       ; a comma,
    JR   Z,.OPTS                   ; or
    CP   '['                       ; the options,
    JR   Z,.OPTS                   ; which end it,
    LD   (DE),A                    ; are copied.
    INC  HL                        ; The next
    INC  DE                        ; character.
    JR   .PART                     ; Until the part ends.
.OPTS:                         ; HL is after the part.
    LD   A,(HL)                    ; Find
    INC  HL                        ; the bracket
    OR   A                         ; or
    JR   Z,.ENDED                  ; the end.
    CP   '['                       ; The options?
    JR   NZ,.OPTS                  ; Look on.
    LD   C,'['                     ; The first option copied follows a bracket.
.OPTION:                       ; HL is after '[' or a comma.
    CALL .SKIP                     ; A is the option's first character.
    SUB  'X'                       ; X is left out:
    LD   B,A                       ; B is zero for it.
    JR   Z,.CHAR                   ; Pass over it.
    LD   A,C                       ; Any other follows a bracket,
    LD   (DE),A                    ; or a comma
    INC  DE                        ; after another,
    LD   C,','                     ; as later ones do.
.CHAR:                         ; HL walks the option.
    LD   A,(HL)                    ; Its next character.
    CP   ','                       ; A comma
    JR   Z,.NEXT                   ; or
    CP   ']'                       ; the bracket
    JR   Z,.NEXT                   ; ends it.
    INC  HL                        ; Past the character.
    CP   ' '                       ; Spaces
    JR   Z,.CHAR                   ; are left out,
    INC  B                         ; and so is X:
    DEC  B                         ; B is zero
    JR   Z,.CHAR                   ; for it.
    LD   (DE),A                    ; Copy the character.
    INC  DE                        ; The next place.
    JR   .CHAR                     ; Until the option ends.
.NEXT:                         ; A is a comma or the bracket.
    INC  HL                        ; Past it.
    CP   ','                       ; Another option?
    JR   Z,.OPTION                 ; Copy it.
    LD   A,C                       ; Was any option copied?
    CP   ','                       ; Then C is a comma,
    JR   NZ,.ENDED                 ; else the list is left out.
    LD   A,']'                     ; The list
    LD   (DE),A                    ; closes.
    INC  DE                        ; DE is past the new tail.
.ENDED:                        ; DE is past the new tail.
    LD   HL,-CH_TAIL-1             ; Its length
    ADD  HL,DE                     ; is DE less the text's start,
    LD   A,L                       ; at most 127:
    LD   (CH_TAIL),A               ; its length byte.
    INC  A                         ; With the length byte,
    LD   C,A                       ; C bytes
    LD   B,0                       ; move
    LD   HL,CH_TAIL                ; to
    LD   DE,SH_TAIL                ; $0080,
    LDIR                           ; where BLINK reads it.
    LD   HL,(SH_BDOS+1)            ; The top of memory, the BDOS entry,
    LD   DE,-CH_LEN                ; less the loader and its FCB,
    ADD  HL,DE                     ; is where the loader goes,
    LD   SP,HL                     ; with the stack below it.
    PUSH HL                        ; Its address, which the RET below enters.
    EX   DE,HL                     ; DE is the destination,
    LD   HL,CH_LOAD                ; the loader
    LD   BC,CH_FCB-CH_LOAD         ; the source:
    LDIR                           ; copied; DE is where its FCB goes.
    PUSH DE                        ; Keep that.
    LD   HL,SH_FCB                 ; The open FCB
    LD   C,SH_FLEN                 ; follows the loader.
    LDIR                           ; Copied.
    POP  DE                        ; DE is the FCB's copy,
    LD   HL,$0100                  ; HL where BLINK loads;
    RET                            ; the loader runs.

;@ROUTINE IN HL OUT A,HL CLOBBERS CARRY,ZERO,SIGN,PARITY,HALFCARRY
; Skip spaces in the tail at HL: A is the first other character, at HL.
; (COMMAND.ASM's CL_SKIP, which this overlay does not hold.)

.SKIP:                         ; HL is in the zero-terminated tail.
    LD   A,(HL)                    ; The next character.
    CP   ' '                       ; A space?
    RET  NZ                        ; No: it is at HL.
    INC  HL                        ; Pass it.
    JR   .SKIP                     ; The terminator ends the scan.

;@ROUTINE IN A OUT CARRY CLOBBERS A,BC,DE,HL,IX,IY,ZERO,SIGN,PARITY,HALFCARRY
; Open BLINK.COM on drive A (0 the current one) in SH_FCB. Carry if it
; isn't there.

.TRY:                          ; A is the drive.
    PUSH AF                        ; Keep it across the clearing.
    CALL SH_BLANK                  ; A clear FCB.
    POP  AF                        ; The drive
    LD   (SH_FCB),A                ; is the FCB's.
    LD   HL,CH_NAME                ; BLINK
    LD   DE,SH_FCB+1               ; into the name field,
    LD   BC,5                      ; five characters;
    LDIR                           ; then, after the dot,
    INC  HL                        ; COM
    LD   DE,SH_FCB+9               ; into the type field,
    LD   C,3                       ; three.
    LDIR                           ; The FCB names BLINK.COM.
    LD   DE,SH_FCB                 ; DE is the FCB for BDOS.
    LD   C,SH_OPEN                 ; Open it;
    CALL SH_BDOS                   ; A is $FF if it is absent,
    ADD  A,1                       ; which alone sets carry.
    RET                            ; Carry if not there.

CH_NAME:                       ; BLINK.COM's name.
    DB   "BLINK.COM",0             ; Printed whole; copied without the dot.
