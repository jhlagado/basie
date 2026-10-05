;==========================================================================
;  CP/M calls and console output
;==========================================================================
;
;  The linker's only contact with CP/M: the BDOS call, console output for
;  diagnostics, and the exit with a return code.
;
;  Principal entries:
;    CPM_CALL  call BDOS function C with DE, keeping IX and IY
;    CON_CHAR  write the character in A, keeping every register
;    CON_STR   write a zero-terminated string
;    CON_CRLF  end a console line
;    CON_DEC   write HL in decimal
;    CPM_EXIT  end the run with a return code
;
;  Registers: every BDOS call goes through CPM_CALL, which keeps IX and IY.
;  CP/M 2.2 doesn't promise to preserve them, and some BIOSes use them
;  (cpm-target §9), while the linker keeps a file descriptor in IX across
;  its calls.

CPM_BDOS EQU  $0005            ; The BDOS entry jump.
CPM_TAIL EQU  $0080            ; The command tail: a length, then the text.
CPM_TOP EQU  $0006             ; The BDOS entry's address: the top of usable memory.

RC_OK EQU  $0000               ; Return code of a link that succeeded (toolchain §5.4).
RC_LINK EQU  $FF12             ; Return code of a link that failed with a diagnostic.
RC_DISK EQU  $FF13             ; Return code of a disk that filled or failed.

;@ROUTINE IN C,DE OUT A,HL CLOBBERS BC,DE,CARRY,ZERO,SIGN,PARITY,HALFCARRY
; Call BDOS function C with DE, and return what BDOS returns, with IX and IY
; as they were.

CPM_CALL:                      ; C is the function, DE its argument.
    PUSH IX                        ; The BDOS may use IX, which holds a caller's FD.
    PUSH IY                        ; And IY, which holds a second FD in a rename.
    CALL CPM_BDOS                  ; A and HL return the BDOS's result.
    POP  IY                        ; Recover the caller's IY.
    POP  IX                        ; Recover the caller's IX.
    RET                            ; A and HL are as the BDOS left them.

;@ROUTINE IN A CLOBBERS CARRY,ZERO,SIGN,PARITY,HALFCARRY
; Write the character in A to the console, keeping every register but F.

CON_CHAR:                      ; A is the character.
    PUSH AF                        ; Keep the character for the caller.
    PUSH BC                        ; The BDOS call changes every register.
    PUSH DE                        ; So keep DE,
    PUSH HL                        ; and HL.
    LD   E,A                       ; BDOS 2 takes the character in E.
    LD   C,2                       ; BDOS 2: console output.
    CALL CPM_CALL                  ; Write it.
    POP  HL                        ; Recover HL,
    POP  DE                        ; DE,
    POP  BC                        ; BC,
    POP  AF                        ; and the character.
    RET                            ; Only the flags may differ.

;@ROUTINE IN HL OUT HL CLOBBERS A,CARRY,ZERO,SIGN,PARITY,HALFCARRY
; Write the zero-terminated string at HL, leaving HL just past its zero.

CON_STR:                       ; HL is the next character of the string.
    LD   A,(HL)                    ; Fetch it.
    INC  HL                        ; Step past it, the zero included.
    OR   A                         ; Is it the terminator?
    RET  Z                         ; Then the string is written.
    CALL CON_CHAR                  ; Write the character.
    JR   CON_STR                   ; And go on to the next.

;@ROUTINE CLOBBERS A,CARRY,ZERO,SIGN,PARITY,HALFCARRY
; End the console line with a carriage return and a line feed.

CON_CRLF:                      ; Called at the end of every diagnostic.
    LD   A,13                      ; A carriage return,
    CALL CON_CHAR                  ; written.
    LD   A,10                      ; Then a line feed,
    JR   CON_CHAR                  ; whose RET returns to the caller.

;@ROUTINE IN HL CLOBBERS A,CARRY,ZERO,SIGN,PARITY,HALFCARRY
; Write HL in decimal, without leading zeros, keeping HL, BC and DE.

CON_DEC:                       ; HL is the number, 0 to 65535.
    PUSH HL                        ; The digits are found by subtracting from HL.
    PUSH DE                        ; DE holds each power of ten.
    PUSH BC                        ; B records whether a digit has been written.
    LD   B,0                       ; B = 1 once a digit has been written.
    LD   DE,10000                  ; The ten-thousands digit,
    CALL .DIGIT                    ; written unless it is a leading zero.
    LD   DE,1000                   ; The thousands digit,
    CALL .DIGIT                    ; likewise.
    LD   DE,100                    ; The hundreds digit,
    CALL .DIGIT                    ; likewise.
    LD   DE,10                     ; The tens digit,
    CALL .DIGIT                    ; likewise.
    LD   A,L                       ; L is the units, 0 to 9.
    ADD  A,'0'                     ; Its character.
    CALL CON_CHAR                  ; The units digit is always written.
    POP  BC                        ; Recover BC,
    POP  DE                        ; DE,
    POP  HL                        ; and the number.
    RET                            ; HL is unchanged.

;@ROUTINE IN B,DE,HL OUT B,HL CLOBBERS A,CARRY,ZERO,SIGN,PARITY,HALFCARRY
; Write the digit of HL for the power of ten in DE, and leave HL below DE.
; B is nonzero once a digit has been written, so leading zeros are skipped.

.DIGIT:                        ; DE is the power, HL less than ten times it.
    LD   A,'0'-1                   ; A counts the subtractions, as a character.
.SUB:                          ; Subtract until HL goes below zero.
    INC  A                         ; One more subtraction.
    OR   A                         ; Clear carry for the subtraction.
    SBC  HL,DE                     ; Take off one power.
    JR   NC,.SUB                   ; While HL stays at or above zero.
    ADD  HL,DE                     ; Undo the subtraction that went below zero.
    CP   '0'                       ; Is the digit zero?
    JR   NZ,.SHOW                  ; A nonzero digit is always written.
    INC  B                         ; Test B for zero,
    DEC  B                         ; keeping it.
    RET  Z                         ; A leading zero is not written.
.SHOW:                         ; A is a digit to write.
    LD   B,1                       ; From here every zero is written.
    JR   CON_CHAR                  ; Write it; CON_CHAR returns to the caller.

;@ROUTINE NORETURN
; End the run with the return code in DE (BDOS 108, which CP/M 2.2 ignores),
; then warm boot.

CPM_EXIT:                      ; DE is RC_OK, RC_LINK or RC_DISK.
    LD   C,108                     ; BDOS 108: set the program return code.
    CALL CPM_CALL                  ; CP/M 2.2 returns without doing anything.
    JP   0                         ; Warm boot: the stack overwrote the CCP.
