;==========================================================================
;  CP/M file names
;==========================================================================
;
;  The parse of a CP/M file name, [d:]name[.type], into the shell's FCB
;  (SH_FCB), with the characters services §4.1 allows. No resident code
;  needs it, so this file is assembled into each overlay that does
;  (build.ts): COMMAND, for the parts and the output named on the command
;  line, and START, for the parts an include names.
;
;  Principal entries:
;    CL_NAME   parse a file name into a clear FCB
;    CL_FIELD  copy a name's characters into one of the FCB's fields

;@ROUTINE IN HL OUT HL,CARRY CLOBBERS A,B,DE,ZERO,SIGN,PARITY,HALFCARRY
; Parse a file name, [d:]name[.type], at HL into a clear FCB (SH_BLANK)
; on the current drive unless it names one, its type blank unless one is
; given; HL is left after it. Carry if it is malformed: a drive outside A
; to P, an empty or long name, or a dot with no type or a long one.

CL_NAME:                       ; HL is the name's first character.
    CALL SH_BLANK                  ; The current drive and a blank name; HL kept.
    INC  HL                        ; Peek at the second character.
    LD   A,(HL)                    ; A colon there means a drive letter came first.
    DEC  HL                        ; HL is back at the first character.
    CP   ':'                       ; Is a drive named?
    JR   NZ,.NAME                  ; No: the name starts at HL.
    LD   A,(HL)                    ; A is the drive letter.
    SUB  'A'-1                     ; The FCB counts A: as 1; a byte below '@' wraps high.
    JR   Z,.BAD                    ; '@' names no drive.
    CP   17                        ; Drives run from A: to P:, 1 to 16.
    JR   NC,.BAD                   ; Reject any other byte.
    LD   (SH_FCB),A                ; Select the named drive.
    INC  HL                        ; Step over the drive letter
    INC  HL                        ; and the colon.
.NAME:                         ; HL is at the name.
    LD   DE,SH_FCB+1               ; The name field follows the drive byte.
    LD   B,8                       ; A name has at most eight characters.
    CALL CL_FIELD                  ; Copy it; carry if it is too long.
    RET  C                         ; Malformed.
    LD   A,(SH_FCB+1)              ; A is the name's first byte.
    CP   ' '                       ; Is it still blank?
    JR   Z,.BAD                    ; An empty name is malformed.
    LD   A,(HL)                    ; A is the character that ended the name.
    CP   '.'                       ; Does a type follow?
    JR   NZ,.DONE                  ; No: the type stays blank.
    INC  HL                        ; Step over the dot.
    LD   DE,SH_FCB+9               ; The type field follows the name.
    LD   B,3                       ; A type has at most three characters.
    CALL CL_FIELD                  ; Copy it; carry if it is too long.
    RET  C                         ; Malformed.
    LD   A,(SH_FCB+9)              ; A is the type's first byte.
    CP   ' '                       ; A dot with no type after it
    JR   NZ,.DONE                  ; is malformed.
.BAD:                          ; The name is malformed.
    SCF                            ; Report it with carry.
    RET                            ; HL is somewhere in it.
.DONE:                         ; The name is complete.
    OR   A                         ; Clear carry.
    RET                            ; HL is after it.

;@ROUTINE IN B,DE,HL OUT HL,CARRY CLOBBERS A,B,DE,ZERO,SIGN,PARITY,HALFCARRY
; Copy name characters from HL to DE, at most B of them; HL stops at the
; first character that may not be in a name. Carry if a name character
; finds no room: the field is too long.

CL_FIELD:                      ; B is the room left in the field.
    LD   A,(HL)                    ; A is the next tail character.
    CALL .CHAR                     ; May it appear in a CP/M name?
    CCF                            ; Carry clear: no, so the field ends at HL,
    RET  NC                        ; with carry clear.
    INC  B                         ; Test B for zero without changing it.
    DEC  B                         ; Zero means the field is full:
    SCF                            ; a name character with no room
    RET  Z                         ; makes it too long.
    LD   (DE),A                    ; Store it in the FCB.
    INC  DE                        ; Move to the next field byte.
    INC  HL                        ; Move to the next tail character.
    DEC  B                         ; One byte less room.
    JR   CL_FIELD                  ; Copy the rest.

;@ROUTINE IN A OUT CARRY CLOBBERS ZERO,SIGN,PARITY,HALFCARRY
; Carry unless A may appear in a CP/M name (services §4.1): A to Z, 0 to 9
; and the sixteen marks of CL_MARKS. The zero terminator is rejected.

.CHAR:                         ; A is the character to classify.
    CP   'A'                       ; Below 'A' it may be a digit or a mark.
    JR   C,.DIGIT                  ; Test for those.
    CP   'Z'+1                     ; Carry if A is a letter.
    CCF                            ; Invert carry, so that a letter returns it clear.
    RET  NC                        ; A letter is a name character.
.DIGIT:                        ; A is not a letter.
    CP   '0'                       ; Below '0' it can only be a mark.
    JR   C,.PUNCT                  ; Search the marks.
    CP   '9'+1                     ; Carry if A is a digit.
    CCF                            ; Invert carry, so that a digit returns it clear.
    RET  NC                        ; A digit is a name character.
.PUNCT:                        ; A is neither a letter nor a digit.
    PUSH HL                        ; The tail position survives the search.
    PUSH BC                        ; So does the caller's field count.
    LD   HL,CL_MARKS               ; HL is the marks allowed in names.
    LD   BC,16                     ; BC counts all sixteen of them.
    CPIR                           ; Zero if A is one of them.
    POP  BC                        ; Restore the field count.
    POP  HL                        ; Restore the tail position; the flags survive.
    SCF                            ; Set carry to reject A.
    RET  NZ                        ; Return with it if A is not a mark.
    CCF                            ; It is one: clear carry to accept it.
    RET                            ; A is a name character.

; ---- data -------------------------------------------------------------------

CL_MARKS:                      ; The marks a CP/M name may contain (services §4.1).
    DB   "!#$%&'()-@^_`{}~"        ; Sixteen, the count .CHAR's CPIR searches.
