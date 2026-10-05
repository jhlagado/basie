;==========================================================================
;  Command line
;==========================================================================
;
;  BASIE.COM's command line (toolchain §5): the source parts, then the
;  options in brackets, read from the raw tail at $0080, which is
;  upper-cased in place first, so that names and options are
;  case-insensitive under CP/M 3 too (§5.1).
;
;      BASIE MAIN, UTIL [M,S=B,O=C:PROG.HEX]
;
;  Principal entry:
;    CL_READ   parse the tail: the parts' names into SH_NAMES, the options
;              into CL_SEEN and CL_LIB, the streams' name into SH_SNAME
;
;  Options (§5.2, §5.3). Each option has a byte in CL_SEEN, zero until it
;  is given: a flag's holds its letter, L's and S's the drive (1 for A:),
;  the others a nonzero mark; P's name goes to CL_LIB. C and X share a
;  byte, so that only one of them may be given, and the byte says which.
;  An option may be given once. The values are checked as BLINK checks
;  them: P a name without drive or type, L and S a drive letter, O a file
;  name whose type is COM, BIN or HEX, F a number from 1 to 255, STACK one
;  from 1 to 65535, T a hexadecimal number of one to four digits; T may be
;  combined only with L. W is BLINK's alone.
;
;  Failure. A malformed part list prints the usage line (CL_USAGE). An
;  unknown, repeated or malformed option is reported as BLINK reports it,
;  L-COMMAND with the option as its argument, from its first character to
;  the next comma, bracket or the end: `Error 224: S=Q: a bad or repeated
;  option`. Neither returns. The option bytes' equates (CL_I...) and the kinds
;  (CL_K...) are with the shell's workspace, in SHELL.ASM.

;@ROUTINE CLOBBERS A,BC,DE,HL,CARRY,ZERO,SIGN,PARITY,HALFCARRY
; Parse the command tail: upper-case it, then read the parts, each
; [d:]name[.type], of type BSI when it names none, with spaces allowed
; around the commas; then the options, if any. Set the streams' drive and
; name (SH_SNAME): option S's drive, else the first part's, and its name.

CL_READ:                       ; The tail is at SH_TAIL.
    XOR  A                         ; Zero:
    LD   (SH_PCNT),A               ; no part is named yet,
    LD   HL,CL_SEEN                ; and no option is given,
    LD   B,CL_NOPT                 ; in every byte
.CLEAR:                        ; of CL_SEEN.
    LD   (HL),A                    ; Clear this one.
    INC  HL                        ; The next.
    DJNZ .CLEAR                    ; Until all are clear.
    LD   HL,CL_DLIB                ; The library is CPM22
    LD   DE,CL_LIB                 ; unless option P
    LD   BC,8                      ; names another:
    LDIR                           ; eight characters.
    LD   HL,SH_TAIL                ; The tail's length byte.
    LD   B,(HL)                    ; B is the length.
    INC  HL                        ; HL is the first character.
    PUSH HL                        ; Keep it for the parse.
    INC  B                         ; Count the terminator in.
.UPPER:                        ; B less one characters remain.
    DEC  B                         ; Any left?
    JR   Z,.ENDED                  ; No: terminate the tail.
    LD   A,(HL)                    ; The next character.
    CP   'a'                       ; Below the small letters?
    JR   C,.KEEP                   ; Keep it.
    CP   'z'+1                     ; Above them?
    JR   NC,.KEEP                  ; Keep it.
    SUB  'a'-'A'                   ; A small letter becomes a capital.
    LD   (HL),A                    ; In place.
.KEEP:                         ; The character is done.
    INC  HL                        ; The next.
    JR   .UPPER                    ; Until the tail is done.
.ENDED:                        ; HL is past the last character; B is zero.
    LD   (HL),B                    ; Terminate it; a full tail ends on the spent jump.
    POP  HL                        ; Parse from the first character.
.NEXTPART:                     ; HL is at the start of the tail or after a comma.
    CALL CL_SKIP                   ; A is the next character that is not a space.
    OR   A                         ; Is this the end of the tail?
    JR   Z,.TAILDONE               ; Then the parts are complete.
    CP   '['                       ; Do the options begin here?
    JR   Z,.TAILDONE               ; With no part before them: a usage error below.
.PART:                         ; HL is at a part's first character.
    CALL CL_PART                   ; Parse the name and keep it.
    CALL CL_SKIP                   ; A is the character after the name and any spaces.
    INC  HL                        ; Step past it, in case it is a comma.
    CP   ','                       ; Does another part follow?
    JR   NZ,.NOCOMMA               ; No: only the end or the options may follow.
    CALL CL_SKIP                   ; A is the first character after the comma.
    OR   A                         ; A comma must be followed by a part,
    JP   Z,CL_USAGE                ; not by the end of the tail
    CP   '['                       ; or by the options.
    JR   NZ,.PART                  ; Parse the next part.
    JP   CL_USAGE                  ; A trailing comma is a malformed command line.
.NOCOMMA:                      ; A is the byte after the part and any spaces.
    OR   A                         ; Is this the end of the tail?
    JR   Z,.TAILDONE               ; Then the parts are complete.
    CP   '['                       ; Otherwise only the options may follow.
    JP   NZ,CL_USAGE               ; Anything else is a malformed command line.
.TAILDONE:                     ; A is '[' with HL after it, or the end.
    LD   C,A                       ; Keep it.
    LD   A,(SH_PCNT)               ; Was any part named?
    OR   A                         ; A command line needs at least one,
    JP   Z,CL_USAGE                ; before any options.
    LD   A,C                       ; Are there options?
    OR   A                         ; '[' if so, zero if not:
    CALL NZ,CL_OPTS                ; read them.
    LD   HL,SH_NAMES               ; The first part's drive and name
    LD   DE,SH_SNAME               ; name the streams,
    LD   BC,9                      ; nine bytes,
    LDIR                           ; on its drive
    LD   A,(CL_SEEN+CL_IS)         ; unless option S
    OR   A                         ; gives
    JR   Z,.SPOOL                  ; the spool drive:
    LD   (SH_SNAME),A              ; then they go there.
.SPOOL:                        ; The streams are named.
    LD   A,(CL_SEEN+CL_IT)         ; Option T, trap lookup,
    OR   A                         ; is not yet
    RET  Z                         ; available.

;@ROUTINE NORETURN
; Report option T, trap lookup (toolchain §8), as not yet available.

CL_TRAP:                       ; CL_READ accepted it.
    LD   HL,CL_TMSG                ; Not yet available.
    JP   SH_FAIL                   ; Print it and fail.

;@ROUTINE NORETURN
; Report a malformed command line with the usage line.

CL_USAGE:                      ; Reached from the parse of the tail.
    LD   HL,CL_UMSG                ; The usage message,
    JP   SH_FAIL                   ; printed by SH_FAIL.

;@ROUTINE NORETURN
; Report a part beyond the SRC_CAP the descriptor table holds.

CL_MANY:                       ; CL_PART found the table full.
    LD   A,DG_PARTS                ; The part table's capacity.
    JP   SH_OVER                   ; Report it and fail.

;@ROUTINE IN HL OUT HL CLOBBERS A,BC,DE,CARRY,ZERO,SIGN,PARITY,HALFCARRY
; Parse a part's name, [d:]name[.type], at HL, of type BSI when it names
; none, and keep it as the next part's (SH_PNAME); HL is left after it.
; More than SRC_CAP parts (SH_MANY), and a malformed name or one followed
; by anything but a space, a comma, a bracket or the end (CL_USAGE), do
; not return.

CL_PART:                       ; HL is at the part's first character.
    LD   A,(SH_PCNT)               ; The parts named so far.
    CP   SRC_CAP                   ; Is the descriptor table already full?
    JP   NC,CL_MANY                ; Then this part is one too many.
    CALL CL_NAME                   ; Parse the name into the FCB.
    JP   C,CL_USAGE                ; A malformed name.
    LD   A,(SH_FCB+9)              ; Was a type given?
    CP   ' '                       ; Blank if not.
    JR   NZ,.TYPED                 ; It was.
    PUSH HL                        ; Keep the tail position.
    LD   HL,CL_TBSI                ; HL is the default type's text.
    LD   DE,SH_FCB+9               ; DE is the FCB's type field.
    LD   BC,3                      ; A type is three bytes.
    LDIR                           ; The FCB names NAME.BSI.
    POP  HL                        ; HL is back after the name.
.TYPED:                        ; HL is just after the part's name.
    LD   A,(HL)                    ; A is the byte that ended the name.
    OR   A                         ; Is it the end of the tail?
    JR   Z,.SAVE                   ; Then the name is complete.
    CP   ' '                       ; A space comes before a comma or the options.
    JR   Z,.SAVE                   ; The caller skips it.
    CP   ','                       ; A comma comes before another part.
    JR   Z,.SAVE                   ; The caller steps over it.
    CP   '['                       ; A bracket opens the options.
    JP   NZ,CL_USAGE               ; Any other byte, such as ';', cannot end a name.
.SAVE:                         ; The FCB names the part.
    PUSH HL                        ; Keep the tail position.
    LD   HL,SH_PCNT                ; The part's index
    LD   A,(HL)                    ; is the count so far,
    INC  (HL)                      ; which counts it.
    CALL SH_PNAME                  ; HL is its name's slot.
    EX   DE,HL                     ; DE is the slot.
    LD   HL,SH_FCB                 ; The FCB's drive, name and type,
    LD   BC,SH_SLOT                ; twelve bytes,
    LDIR                           ; name the part for loading and diagnostics.
    POP  HL                        ; HL is after the name.
    RET                            ; The part is named.

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

;@ROUTINE IN HL OUT A,HL CLOBBERS CARRY,ZERO,SIGN,PARITY,HALFCARRY
; Skip the spaces at HL. A is the first other byte and HL its address; the
; callers test A, not the flags.

CL_SKIP:                       ; HL is in the zero-terminated tail.
    LD   A,(HL)                    ; Read the next tail byte.
    CP   ' '                       ; Is it a space?
    RET  NZ                        ; No: A and HL locate it.
    INC  HL                        ; Skip the space.
    JR   CL_SKIP                   ; The terminator ends the scan.

;@ROUTINE IN HL OUT HL CLOBBERS A,BC,DE,CARRY,ZERO,SIGN,PARITY,HALFCARRY
; Parse one option at HL into CL_SEEN, leaving HL after it, which must be
; followed by a space, a comma, a bracket or the end. An unknown, repeated
; or malformed option is reported (CL_EOPT) and does not return.

CL_OPT:                        ; HL is the option's first character.
    LD   (CL_POS),HL               ; Keep it for a report.
    CALL .PARSE                    ; Parse it; HL is after it.
    LD   A,(HL)                    ; What ends it:
    OR   A                         ; the end,
    RET  Z                         ; or
    CP   ' '                       ; a space,
    RET  Z                         ; or
    CP   ','                       ; a comma,
    RET  Z                         ; or
    CP   ']'                       ; the bracket.
    RET  Z                         ; Anything else
    JR   .BAD                      ; makes it malformed.

;@ROUTINE IN HL OUT HL CLOBBERS A,BC,DE,CARRY,ZERO,SIGN,PARITY,HALFCARRY
; Parse the option at HL: STACK= and its number, or a letter, then for an
; option with a value '=' and the value, by its kind in CL_TAB.

.PARSE:                        ; HL is the option's first character.
    LD   C,(HL)                    ; C is its letter.
    INC  HL                        ; What follows it?
    LD   A,(HL)                    ; An equals sign
    LD   B,1                       ; gives a value:
    CP   '='                       ; B is 1
    JR   Z,.EQUAL                  ; for one,
    DEC  B                         ; 0 for a flag,
    CP   'T'                       ; unless S and T
    JR   NZ,.FIND                  ; begin
    LD   A,C                       ; STACK=.
    CP   'S'                       ; Is the letter S?
    JR   NZ,.FIND                  ; Then the option is a flag.
    LD   DE,CL_STACK               ; The rest of STACK=,
    LD   B,5                       ; five characters.
.SPELL:                        ; DE walks the word, HL the tail.
    LD   A,(DE)                    ; The next character of TACK=.
    CP   (HL)                      ; Does the tail match?
    JR   NZ,.BAD                   ; Not STACK=.
    INC  DE                        ; The next character of the word,
    INC  HL                        ; and of the tail.
    DJNZ .SPELL                    ; Until TACK= is matched.
    LD   A,CL_ISTK                 ; STACK=, once.
    CALL CL_ONCE                   ; Mark it.
    CALL CL_DEC                    ; A number from 1 to 65535.
    RET  NC                        ; HL is after it.
    JR   .BAD                      ; Malformed.
.EQUAL:                        ; HL is at the equals sign.
    INC  HL                        ; The value follows.
.FIND:                         ; C is the letter, B 1 if a value is given.
    PUSH HL                        ; Keep the parse position.
    LD   HL,CL_TAB                 ; Each option's letter and kind.
    LD   E,0                       ; E counts them: the option's byte.
.LOOK:                         ; HL is the next entry.
    LD   A,(HL)                    ; Its letter,
    OR   A                         ; zero after the last:
    JR   Z,.BAD                    ; an unknown option.
    CP   C                         ; Is it this option's?
    INC  HL                        ; HL is the kind.
    JR   Z,.FOUND                  ; It is.
    INC  HL                        ; The next entry,
    INC  E                         ; the next byte.
    JR   .LOOK                     ; Try it.
.FOUND:                        ; HL is the option's kind.
    LD   D,(HL)                    ; D is the kind.
    POP  HL                        ; HL is after the letter or the sign.
    LD   A,D                       ; A flag's kind is zero:
    CP   1                         ; carry for a flag,
    SBC  A,A                       ; $FF for one, 0 for a value,
    INC  A                         ; then 0 or 1,
    CP   B                         ; which must be what was given.
    JR   NZ,.BAD                   ; A flag with a value, or a value without one.
    LD   A,E                       ; The option's byte,
    CP   CL_IC+1                   ; but X
    JR   NZ,.SLOT                  ; shares
    DEC  A                         ; C's.
.SLOT:                         ; A is the option's byte.
    CALL CL_ONCE                   ; Mark it; BC addresses it.
    LD   A,D                       ; By its kind:
    OR   A                         ; a flag
    RET  Z                         ; is complete,
    DEC  A                         ; a drive
    JR   Z,.DRIVE                  ; is a letter,
    DEC  A                         ; the library
    JR   Z,.LIBRARY                ; a name,
    DEC  A                         ; the output
    JR   Z,.OUTPUT                 ; a file name,
    DEC  A                         ; F
    JR   Z,.FILES                  ; a count,
    LD   DE,(CL_POS)               ; and T an address;
    LD   (CL_TPOS),DE              ; it is reported if another joins it.
    CALL CL_HEX                    ; One to four hexadecimal digits.
    RET  NC                        ; HL is after them.
.BAD:                          ; The option is malformed:
    JP   CL_EOPT                   ; report it.
.DRIVE:                        ; BC is the option's byte.
    LD   A,(HL)                    ; The drive letter:
    SUB  'A'                       ; 0 for A:,
    JR   C,.BAD                    ; nothing below,
    CP   16                        ; and P: the last.
    JR   NC,.BAD                   ; Above it is malformed.
    INC  A                         ; The FCB counts A: as 1:
    LD   (BC),A                    ; the byte holds the drive.
    INC  HL                        ; Past the letter.
    RET                            ; HL is after it.
.LIBRARY:                      ; A name, with no drive or type.
    PUSH HL                        ; Keep the parse position.
    LD   HL,CL_LIB                 ; Blank
    LD   B,8                       ; the eight characters
.BLANK:                        ; of the name
    LD   (HL),' '                  ; option P
    INC  HL                        ; gives.
    DJNZ .BLANK                    ; Until all eight are.
    POP  HL                        ; HL is the name.
    LD   DE,CL_LIB                 ; It goes to CL_LIB,
    LD   B,8                       ; at most eight characters.
    CALL CL_FIELD                  ; Copy it; carry if too long.
    JR   C,.BAD                    ; Malformed.
    LD   A,(CL_LIB)                ; An empty name
    CP   ' '                       ; is malformed too;
    RET  NZ                        ; a drive or type ends it, which CL_OPT refuses.
    JR   .BAD                      ; Report it.
.OUTPUT:                       ; A file name of a kind BLINK writes.
    CALL CL_NAME                   ; Parse it into the FCB.
    JR   C,.BAD                    ; Malformed.
    PUSH HL                        ; Keep the parse position.
    LD   HL,CL_KINDS               ; The types allowed, blank first.
    LD   C,4                       ; Four of them.
.KIND:                         ; HL is a type, C those left.
    PUSH HL                        ; Keep it to step to the next.
    LD   DE,SH_FCB+9               ; Compare the output's type
    LD   B,3                       ; over three characters.
.TYPE:                         ; DE and HL walk the two types.
    LD   A,(DE)                    ; A character of the output's type.
    CP   (HL)                      ; Does it match?
    INC  DE                        ; Step both,
    INC  HL                        ; keeping the flags.
    JR   NZ,.NEXTKIND              ; A mismatch: try the next type.
    DJNZ .TYPE                     ; Until all three match.
    POP  HL                        ; Drop the type's address.
    POP  HL                        ; HL is the parse position again.
    RET                            ; The output's kind is known.
.NEXTKIND:                     ; The type didn't match.
    POP  HL                        ; HL is the type tried.
    INC  HL                        ; Step over
    INC  HL                        ; its three
    INC  HL                        ; characters.
    DEC  C                         ; Any more?
    JR   NZ,.KIND                  ; Try the next.
    JR   .BAD                      ; No such output kind.
.FILES:                        ; F=N, the file table's entries.
    CALL CL_DEC                    ; DE is the number.
    JR   C,.BAD                    ; Not a number from 1 to 65535.
    LD   A,D                       ; At most 255:
    OR   A                         ; a high byte
    RET  Z                         ; is too many.
    JR   .BAD                      ; Report it.

;@ROUTINE NORETURN
; Report the option being parsed (CL_POS) as bad or repeated.

CL_EOPT:                       ; CL_POS is the option's first character.
    LD   HL,(CL_POS)               ; Report from there.

;@ROUTINE IN HL NORETURN
; Report the word at HL, to the next comma, bracket or the end, as a bad
; or repeated option (L-COMMAND), and fail.

CL_EBAD:                       ; HL is the word's first character.
    LD   (DG_ARG1),HL              ; The word is argument 1.
.SCAN:                         ; HL walks the word.
    LD   A,(HL)                    ; The next character.
    OR   A                         ; The end of the tail,
    JR   Z,.ENDWORD                ; or
    CP   ','                       ; a comma,
    JR   Z,.ENDWORD                ; or
    CP   ']'                       ; a bracket
    JR   Z,.ENDWORD                ; ends the word.
    INC  HL                        ; The next.
    JR   .SCAN                     ; Until the word ends.
.ENDWORD:                      ; HL is just past the word.
    LD   (HL),0                    ; End it there: the tail is not read again.
    LD   HL,CL_NBAD                ; L-COMMAND,
    JP   MS_FAIL                   ; and fail.

;@ROUTINE IN HL CLOBBERS A,BC,DE,HL,CARRY,ZERO,SIGN,PARITY,HALFCARRY
; Parse the options at HL, just after '[': options separated by commas,
; with spaces around them, then ']' and nothing more but spaces. Option T
; may be combined only with L.

CL_OPTS:                       ; HL is after '[' or a comma.
    CALL CL_SKIP                   ; Past spaces.
    CALL CL_OPT                    ; One option; HL is after it.
    CALL CL_SKIP                   ; A is what follows it.
    INC  HL                        ; Step past it.
    CP   ','                       ; Does another option follow?
    JR   Z,CL_OPTS                 ; Parse it.
    CP   ']'                       ; Otherwise the list must close.
    JR   NZ,.BRACKET               ; Report what stands in its place.
    CALL CL_SKIP                   ; Nothing may follow it
    OR   A                         ; but the end;
    JR   NZ,CL_EBAD                ; report a stray word.
    LD   A,(CL_SEEN+CL_IT)         ; Was option T given?
    OR   A                         ; Then only L
    RET  Z                         ; may be given with it.
    LD   HL,CL_SEEN                ; Count the options given:
    LD   BC,CL_NOPT*256            ; B bytes to look at, C counting.
.COUNT:                        ; HL is the next byte.
    LD   A,(HL)                    ; Is its option given?
    OR   A                         ; Zero if not.
    JR   Z,.ABSENT                 ; Not counted.
    INC  C                         ; Counted.
.ABSENT:                       ; The byte is looked at.
    INC  HL                        ; The next.
    DJNZ .COUNT                    ; Until all are.
    LD   A,(CL_SEEN+CL_IL)         ; Less L,
    OR   A                         ; if given,
    JR   Z,.TALONE                 ; and
    DEC  C                         ; less
.TALONE:                       ; T itself,
    DEC  C                         ; nothing may remain.
    RET  Z                         ; T stands alone, or with L.
    LD   HL,(CL_TPOS)              ; Report T,
    JR   CL_EBAD                   ; which another option joins.
.BRACKET:                      ; HL is just past what stands in its place.
    DEC  HL                        ; Report from that character.
    JR   CL_EBAD                   ; It is no comma or bracket.

;@ROUTINE IN A,C OUT BC CLOBBERS A,CARRY,ZERO,SIGN,PARITY,HALFCARRY
; Mark byte A of CL_SEEN given, holding the option's letter C, and return
; its address in BC. A byte given already, a repeated option, is reported
; (CL_EOPT). HL and DE are kept.

CL_ONCE:                       ; A is the option's byte.
    PUSH HL                        ; Keep the parse position.
    LD   HL,CL_SEEN                ; The byte
    ADD  A,L                       ; is A
    LD   L,A                       ; bytes
    ADC  A,H                       ; into
    SUB  L                         ; CL_SEEN,
    LD   H,A                       ; at HL.
    LD   A,(HL)                    ; Given already?
    OR   A                         ; Then the option
    JR   NZ,CL_EOPT                ; is repeated.
    LD   (HL),C                    ; The letter marks it given.
    LD   B,H                       ; BC
    LD   C,L                       ; addresses it.
    POP  HL                        ; The parse position.
    RET                            ; Marked.

;@ROUTINE IN HL OUT DE,HL,CARRY CLOBBERS A,BC,ZERO,SIGN,PARITY,HALFCARRY
; DE = a decimal number of 1 to 5 digits at HL, 1 to 65535, leaving HL
; after it. Carry if it is malformed or out of range.

CL_DEC:                        ; HL is the number's first character.
    LD   DE,0                      ; DE is the value so far.
    LD   B,D                       ; B counts the digits.
.DIGIT:                        ; HL is the next character.
    LD   A,(HL)                    ; Fetch it.
    SUB  '0'                       ; Its value, if a digit.
    JR   C,.ENDNUM                 ; Below '0': the number ends.
    CP   10                        ; Above '9'?
    JR   NC,.ENDNUM                ; The number ends.
    INC  B                         ; One more digit.
    LD   C,A                       ; C is the digit's value.
    PUSH HL                        ; Keep the parse position.
    LD   H,D                       ; HL is the value
    LD   L,E                       ; so far.
    ADD  HL,HL                     ; Times 2;
    JR   C,.OVER                   ; past 65535?
    ADD  HL,HL                     ; times 4;
    JR   C,.OVER                   ; past 65535?
    ADD  HL,DE                     ; times 5;
    JR   C,.OVER                   ; past 65535?
    ADD  HL,HL                     ; times 10;
    JR   C,.OVER                   ; past 65535?
    LD   E,C                       ; DE is the digit,
    LD   D,0                       ; zero-extended.
    ADD  HL,DE                     ; Add it.
    JR   C,.OVER                   ; Past 65535?
    EX   DE,HL                     ; DE is the new value.
    POP  HL                        ; HL is the parse position.
    INC  HL                        ; Past the digit.
    JR   .DIGIT                    ; The next.
.OVER:                         ; The value passed 65535.
    POP  HL                        ; Recover the parse position.
    SCF                            ; Carry: out of range.
    RET                            ; Malformed.
.ENDNUM:                       ; The number has ended.
    LD   A,B                       ; How many digits?
    OR   A                         ; None?
    SCF                            ; Then it is malformed,
    RET  Z                         ; no digits.
    CP   6                         ; Six or more,
    CCF                            ; even with leading zeros,
    RET  C                         ; are too many.
    LD   A,D                       ; Is the value zero?
    OR   E                         ; Then it is out of range,
    SCF                            ; with carry,
    RET  Z                         ; zero.
    OR   A                         ; Clear carry.
    RET                            ; DE is the number.

;@ROUTINE IN HL OUT HL,CARRY CLOBBERS A,B,ZERO,SIGN,PARITY,HALFCARRY
; Step HL over one to four hexadecimal digits. Carry if there are none or
; more than four.

CL_HEX:                        ; HL is the first digit.
    LD   B,0                       ; B counts the digits.
.DIGIT:                        ; HL is the next character.
    LD   A,(HL)                    ; Fetch it.
    CP   '0'                       ; Below the digits?
    JR   C,.END                    ; It ends the number.
    CP   '9'+1                     ; A decimal digit?
    JR   C,.MORE                   ; Count it.
    CP   'A'                       ; Between the digits and the letters?
    JR   C,.END                    ; It ends the number.
    CP   'F'+1                     ; A letter A to F?
    JR   NC,.END                   ; Anything above ends the number.
.MORE:                         ; A hexadecimal digit.
    INC  B                         ; Count it.
    INC  HL                        ; The next.
    JR   .DIGIT                    ; Go on.
.END:                          ; B digits were read.
    LD   A,B                       ; One to four,
    DEC  A                         ; 0 to 3,
    CP   4                         ; set carry:
    CCF                            ; none, or five or more,
    RET                            ; clear it.

; ---- data -------------------------------------------------------------------

CL_TAB:                        ; Each option's letter and kind; its byte is its place.
    DB   'K',0,'C',0,'X',0         ; Keep the intermediates, compile or link only,
    DB   'M',0,'Y',0,'N',0         ; the map, the symbol file, no line stream,
    DB   'R',0,'B',0,'Z',0,'V',0   ; re-runnable, keep the CCP, no .BAK, verify;
    DB   'P',CL_KLIB               ; the library,
    DB   'L',CL_KDRV,'S',CL_KDRV   ; its drive, the spool drive,
    DB   'O',CL_KOUT               ; the output,
    DB   'F',CL_KNUM,'T',CL_KHEX   ; the file table, trap lookup;
    DB   0                         ; the end of the table.
CL_STACK:                      ; The rest of STACK= after the S.
    DB   "TACK="                   ; Five characters, matched by .SPELL.
CL_KINDS:                      ; The output's types: blank, which is .COM, or one named.
    DB   "   COMBINHEX"            ; The kinds BLINK writes.
CL_DLIB:                       ; The library a build uses unless option P names one.
    DB   "CPM22   "                ; The CP/M 2.2 profile's.
CL_TBSI:                       ; The type of a part that names none.
    DB   "BSI"                     ; Copied into the FCB's type field.
CL_MARKS:                      ; The marks a CP/M name may contain (services §4.1).
    DB   "!#$%&'()-@^_`{}~"        ; Sixteen, the count .CHAR's CPIR searches.
CL_UMSG:                       ; Any malformed command line.
    DB   "Usage: BASIE PART[,PART...] [OPTIONS]",0 ; The command's grammar.
CL_TMSG:                       ; Option T.
    DB   "Trap lookup is not yet available",0 ; Toolchain §8, still to come.
