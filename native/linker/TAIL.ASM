;==========================================================================
;  Command tail
;==========================================================================
;
;  The command line (toolchain §5): the first part's name, any further
;  parts, then options in brackets. BLINK takes the options that concern
;  linking, and ignores the parts after the first, whose intermediate files
;  the compiler has already merged.
;
;      BLINK MAIN [M,F=6]
;
;  Principal entry:
;    CMD_READ  parse the tail into the fields below
;
;  The tail is copied, upper-cased and zero-terminated, to CMD_BUF and
;  parsed there. CMD_BUF and CMD_BAD, the text of a bad word for its
;  diagnostic, lie in two of Phase D's FDs (PHASED.ASM), which are unused
;  until long after parsing. Each option may be given once: OP_SEEN keeps a
;  bit for each option with a value, OP_FLAGS and OP_EXTRA one for each flag.
;
;  Failure: a malformed word reports L-COMMAND with the word as argument 1,
;  and CMD_READ returns carry.

CMD_DISK:                      ; The first part's drive: 0 the current one, 1 A:.
    DB   0                         ; Its intermediate files are read from there.
CMD_NAME:                      ; The first part's name, which names every file.
    DS   8,' '                     ; Eight characters, space-padded.
OP_FLAGS:                      ; The option flags, as OF_ below.
    DB   0                         ; No option is given until parsed.
LIB_FILE:                      ; P=: the library's name.
    DB   "CPM22   "                ; The CP/M 2.2 profile's library by default.
LIB_DISK:                      ; L=: the library's drive, 1 A:, or 0.
    DB   0                         ; 0: the first part's drive, then A:.
OP_SPOOL:                      ; S=: the spool drive for intermediates, or 0.
    DB   0                         ; 0: the first part's drive.
OUT_DISK:                      ; O=: the output's drive, or 0.
    DB   0                         ; 0: the first part's drive.
OUT_NAME:                      ; O=: the output's name.
    DS   8,' '                     ; Used only when OUT_SET is 1.
OUT_TYPE:                      ; O=: the output's type, which names its kind.
    DB   "COM"                     ; A .COM file by default.
OUT_SET:                       ; 1 when O= was given.
    DB   0                         ; Otherwise the output is named after the part.
OUT_KIND:                      ; The output kind: 1 .COM, 2 .BIN, 4 .HEX.
    DB   1                         ; The bit the profile's kinds are tested with.
OP_FILES:                      ; F=: the file table's entries, or 0.
    DB   0                         ; 0: the default, four (Phase C).
OP_STACK:                      ; STACK=: the stack reserve in bytes, or 0.
    DW   0                         ; 0: the compiler's reserve alone.
OP_SEEN:                       ; One bit per option with a value, to refuse repeats.
    DW   0                         ; Bit 8 P=, 9 L=, 10 S=, 11 O=, 12 F=, 15 STACK=.
OP_EXTRA:                      ; More flags: OX_W.
    DB   0                         ; No more room in OP_FLAGS.

OF_K EQU  $01                  ; K: keep the intermediate files.
OF_M EQU  $02                  ; M: write the map.
OF_Y EQU  $04                  ; Y: write the symbol file.
OF_N EQU  $08                  ; N: no line table.
OF_R EQU  $10                  ; R: a re-runnable image, DATA copied to COPY.
OF_B EQU  $20                  ; B: keep the CCP resident.
OF_Z EQU  $40                  ; Z: no .BAK of the old output.
OF_V EQU  $80                  ; V: verify placeholders and the library's CRC.
OX_W EQU  $01                  ; W: write the link tables to NAME.$TB, for testing.

FN_DISK:                       ; A parsed file name's drive, 1 A:, or 0.
    DB   0                         ; Set by .FILENAME.
FN_NAME:                       ; Its name, space-padded.
    DS   8                         ; Followed directly by the type.
FN_TYPE:                       ; Its type, space-padded.
    DS   3                         ; .OUTPUT copies it straight after the name.
FN_TYPED:                      ; 1 when a type was given.
    DB   0                         ; A library name may not have one.

;@ROUTINE OUT A,CARRY CLOBBERS BC,DE,HL,IX,ZERO,SIGN,PARITY,HALFCARRY
; Parse the command tail. Return A = 0 and carry clear when it is empty;
; A = 1 and carry clear when it parsed; carry after printing a diagnostic.

CMD_READ:                      ; Called first, before any file is open.
    LD   HL,CPM_TAIL               ; The tail's length byte.
    LD   B,(HL)                    ; B is the length.
    INC  HL                        ; HL is the first character.
    LD   DE,CMD_BUF                ; The copy goes to CMD_BUF.
    LD   A,B                       ; Is the tail empty?
    OR   A                         ; Zero length means no name.
    JR   Z,.COPIED                 ; Just terminate the copy.
.COPY:                         ; HL walks the tail, DE the copy, B counts.
    LD   A,(HL)                    ; A is the next character.
    CP   'a'                       ; Below 'a'?
    JR   C,.KEEP                   ; Not a lower-case letter.
    CP   'z'+1                     ; Above 'z'?
    JR   NC,.KEEP                  ; Not a lower-case letter.
    SUB  32                        ; Upper-case it.
.KEEP:                         ; A is the character to copy.
    LD   (DE),A                    ; Store it.
    INC  HL                        ; The next tail character.
    INC  DE                        ; The next place in the copy.
    DJNZ .COPY                     ; Until the whole tail is copied.
.COPIED:                       ; DE is just past the copy.
    XOR  A                         ; A zero
    LD   (DE),A                    ; terminates it.
    LD   HL,CMD_BUF                ; Parse from the start.
    CALL .SKIP                     ; Past leading spaces.
    LD   A,(HL)                    ; Is anything there?
    OR   A                         ; Zero is the end.
    RET  Z                         ; Empty: A = 0, carry clear.
    CALL .PART                     ; The first part's name.
    RET  C                         ; Malformed: reported.
    LD   A,(FN_DISK)               ; The first part's drive
    LD   (CMD_DISK),A              ; is where its files are.
    PUSH HL                        ; Keep the parse position.
    LD   HL,FN_NAME                ; Its name
    LD   DE,CMD_NAME               ; names every file of the link.
    LD   BC,8                      ; Eight characters.
    LDIR                           ; Copy them.
    POP  HL                        ; HL is after the name.
.PARTS:                        ; Further parts: the linker doesn't need them.
    CALL .SKIP                     ; Past spaces.
    LD   A,(HL)                    ; A is the next character.
    CP   ','                       ; Does another part follow?
    JR   NZ,.OPTSTART              ; No: options or the end.
    INC  HL                        ; Past the comma.
    CALL .SKIP                     ; Past spaces.
    CALL .PART                     ; Check the part's name, and drop it.
    RET  C                         ; Malformed: reported.
    JR   .PARTS                    ; Any more parts.
.OPTSTART:                     ; A is the character after the parts.
    OR   A                         ; The end of the tail?
    JR   Z,.DONE                   ; No options were given.
    CP   '['                       ; Only an option list may follow.
    JP   NZ,.BADWORD               ; Anything else is a bad word.
    INC  HL                        ; Past the bracket.
.OPTLOOP:                      ; HL is at an option.
    CALL .SKIP                     ; Past spaces.
    CALL .OPTION                   ; Parse one option.
    RET  C                         ; Malformed: reported.
    CALL .SKIP                     ; Past spaces.
    LD   A,(HL)                    ; A is the character after the option.
    INC  HL                        ; Step past it.
    CP   ','                       ; Does another option follow?
    JR   Z,.OPTLOOP                ; Parse it.
    CP   ']'                       ; Otherwise the list must close.
    JP   NZ,.BRACKET               ; Report the misplaced or missing bracket.
    CALL .SKIP                     ; Past spaces.
    LD   A,(HL)                    ; Nothing may follow the list.
    OR   A                         ; Only the end.
    JP   NZ,.BADWORD               ; Report the stray word.
.DONE:                         ; The tail parsed.
    LD   A,1                       ; A = 1: a name was given.
    OR   A                         ; Clear carry.
    RET                            ; Parsed.

;@ROUTINE IN HL OUT HL,CARRY CLOBBERS A,BC,DE,ZERO,SIGN,PARITY,HALFCARRY
; Parse a part's file name at HL into the FN_ fields; carry after a
; diagnostic that names the part.

.PART:                         ; HL is the part's first character.
    LD   (.AT),HL                  ; Keep it for the diagnostic.
    CALL .FILENAME                 ; Parse the name; carry if malformed.
    RET  NC                        ; HL is after the name.
    LD   HL,(.AT)                  ; Report from the part's start.
    JP   .REPORT                   ; L-COMMAND, returning carry.
.AT:                           ; The part being parsed.
    DW   0                         ; Its first character's address.

;@ROUTINE IN HL OUT A,HL CLOBBERS CARRY,ZERO,SIGN,PARITY,HALFCARRY
; Skip spaces at HL, leaving A the first other character and HL its address.

.SKIP:                         ; HL is in the zero-terminated copy.
    LD   A,(HL)                    ; Read the next character.
    CP   ' '                       ; Is it a space?
    RET  NZ                        ; No: A and HL locate it.
    INC  HL                        ; Skip the space.
    JR   .SKIP                     ; The terminator ends the scan.

;@ROUTINE IN HL OUT HL,CARRY CLOBBERS A,BC,DE,ZERO,SIGN,PARITY,HALFCARRY
; Parse one option at HL into its OP_, OUT_ or LIB_ field, leaving HL after
; it. Carry after a diagnostic: an unknown or repeated option, or a bad value.

.OPTION:                       ; HL is the option's first character.
    LD   (.START),HL               ; Keep it for the diagnostic.
    LD   A,(HL)                    ; A is the option's letter.
    INC  HL                        ; HL is the character after it.
    LD   C,A                       ; C = the option's letter.
    LD   A,(HL)                    ; Is a value given?
    CP   '='                       ; A letter and '=' take a value.
    JR   Z,.VALUE                  ; Parse the value.
    CP   'T'                       ; STACK= is the only longer option.
    JR   NZ,.NOVALUE               ; A letter alone is a flag.
    LD   A,C                       ; ST may begin STACK=.
    CP   'S'                       ; Is the letter S?
    JR   NZ,.NOVALUE               ; Then it is a flag letter, to be refused.
    LD   DE,.STACKW                ; The rest of the word,
    LD   B,5                       ; five characters, "TACK=".
.SPELL:                        ; DE walks the word, HL the tail.
    LD   A,(DE)                    ; The next character of STACK=.
    CP   (HL)                      ; Does the tail match?
    JP   NZ,.BAD                   ; Not STACK=.
    INC  DE                        ; The next character of the word.
    INC  HL                        ; And of the tail.
    DJNZ .SPELL                    ; Until "TACK=" is matched.
    LD   A,15                      ; STACK= is option 15 in OP_SEEN.
    CALL .ONCE                     ; Refuse it if repeated.
    RET  C                         ; Repeated: reported.
    CALL .DECIMAL                  ; DE is the number of bytes.
    JP   C,.BAD                    ; Not a number from 1 to 65535.
    LD   (OP_STACK),DE             ; The requested stack reserve.
    OR   A                         ; Clear carry.
    RET                            ; Parsed.
.NOVALUE:                      ; C is a flag letter.
    LD   A,C                       ; W has its own byte.
    CP   'W'                       ; Is it W?
    JR   NZ,.TABLE                 ; Others are in the table.
    LD   A,(OP_EXTRA)              ; W: write the tables, for testing.
    AND  OX_W                      ; Already given?
    JP   NZ,.BAD                   ; A repeated flag is refused.
    LD   A,OX_W                    ; Set W,
    LD   (OP_EXTRA),A              ; the only bit in OP_EXTRA.
    OR   A                         ; Clear carry.
    RET                            ; Parsed.
.TABLE:                        ; Look the letter up in .FLAGS.
    LD   DE,.FLAGS                 ; Letter, then its flag bit.
    LD   B,8                       ; Eight flag letters.
.LOOKFLAG:                     ; DE walks the pairs.
    LD   A,(DE)                    ; A is a flag letter.
    CP   C                         ; Is it this option's?
    JR   Z,.SETFLAG                ; Found.
    INC  DE                        ; Past the letter
    INC  DE                        ; and its bit.
    DJNZ .LOOKFLAG                 ; Try the next pair.
    JP   .BAD                      ; An unknown option.
.SETFLAG:                      ; DE is the matching letter.
    INC  DE                        ; DE is its bit.
    LD   A,(DE)                    ; A is the bit,
    LD   B,A                       ; kept in B.
    LD   A,(OP_FLAGS)              ; The flags given so far.
    AND  B                         ; Was this one given already?
    JP   NZ,.BAD                   ; Repeated.
    LD   A,(OP_FLAGS)              ; Add the flag
    OR   B                         ; to those given,
    LD   (OP_FLAGS),A              ; and keep them.
    OR   A                         ; Clear carry.
    RET                            ; Parsed.
.VALUE:                        ; HL is at the '='.
    INC  HL                        ; Past '='.
    LD   A,C                       ; Which option takes the value?
    CP   'P'                       ; P=: the library's name.
    JR   Z,.LIBRARY                ; Parse a name.
    CP   'L'                       ; L=: the library's drive.
    JR   Z,.LIBDISK                ; Parse a drive.
    CP   'S'                       ; S=: the spool drive.
    JR   Z,.SPOOL                  ; Parse a drive.
    CP   'O'                       ; O=: the output's name.
    JR   Z,.OUTPUT                 ; Parse a file name.
    CP   'F'                       ; F=: the file table's entries.
    JP   Z,.FILES                  ; Parse a number.
    JP   .BAD                      ; No other option takes a value.
.LIBRARY:                      ; P=NAME.
    LD   A,8                       ; P= is option 8 in OP_SEEN.
    CALL .ONCE                     ; Refuse it if repeated.
    RET  C                         ; Repeated: reported.
    CALL .FILENAME                 ; Parse the name into FN_.
    JP   C,.BAD                    ; Malformed.
    LD   A,(FN_DISK)               ; A library name has no drive or type:
    LD   B,A                       ; the drive is option L's,
    LD   A,(FN_TYPED)              ; and the type is always BRL.
    OR   B                         ; Either given?
    JP   NZ,.BAD                   ; Refused.
    PUSH HL                        ; Keep the parse position.
    LD   HL,FN_NAME                ; The name
    LD   DE,LIB_FILE               ; replaces CPM22.
    LD   BC,8                      ; Eight characters.
    LDIR                           ; Copy them.
    POP  HL                        ; HL is after the name.
    OR   A                         ; Clear carry.
    RET                            ; Parsed.
.LIBDISK:                      ; L=D.
    LD   A,9                       ; L= is option 9 in OP_SEEN.
    LD   DE,LIB_DISK               ; The drive goes to LIB_DISK.
    JR   .DRIVE                    ; Parse it.
.SPOOL:                        ; S=D.
    LD   A,10                      ; S= is option 10 in OP_SEEN.
    LD   DE,OP_SPOOL               ; The drive goes to OP_SPOOL.
.DRIVE:                        ; A is the option's number, DE its field.
    CALL .ONCE                     ; Refuse it if repeated.
    RET  C                         ; Repeated: reported.
    LD   A,(HL)                    ; A is the drive letter.
    SUB  'A'                       ; 0 for A:.
    JP   C,.BAD                    ; Below A.
    CP   16                        ; Drives run from A: to P:.
    JP   NC,.BAD                   ; Above P.
    INC  A                         ; The FCB counts A: as 1.
    LD   (DE),A                    ; Store the drive.
    INC  HL                        ; Past the letter.
    OR   A                         ; Clear carry.
    RET                            ; Parsed.
.OUTPUT:                       ; O=[D:]NAME[.TYPE].
    LD   A,11                      ; O= is option 11 in OP_SEEN.
    CALL .ONCE                     ; Refuse it if repeated.
    RET  C                         ; Repeated: reported.
    CALL .FILENAME                 ; Parse the name into FN_.
    JP   C,.BAD                    ; Malformed.
    LD   A,1                       ; The output is named by O=,
    LD   (OUT_SET),A               ; not after the part.
    LD   A,(FN_DISK)               ; Its drive,
    LD   (OUT_DISK),A              ; or 0.
    PUSH HL                        ; Keep the parse position.
    LD   HL,FN_NAME                ; Its name
    LD   DE,OUT_NAME               ; into OUT_NAME.
    LD   BC,8                      ; Eight characters.
    LDIR                           ; Copy them; HL is FN_TYPE.
    LD   A,(FN_TYPED)              ; Was a type given?
    OR   A                         ; Zero if not.
    JR   Z,.TYPED                  ; Keep the type COM.
    LD   BC,3                      ; HL = FN_TYPE, just after FN_NAME.
    LD   DE,OUT_TYPE               ; The given type
    LDIR                           ; replaces COM.
.TYPED:                        ; The type names the kind; others are bad.
    LD   HL,.KINDS                 ; The types the linker writes.
    LD   C,1                       ; C is the kind of the first: 1 .COM.
.KIND:                         ; HL is a type in .KINDS, C its kind bit.
    PUSH HL                        ; Keep it to step to the next.
    LD   DE,OUT_TYPE               ; Compare the output's type
    LD   B,3                       ; over three characters.
.TYPECHAR:                     ; DE and HL walk the two types.
    LD   A,(DE)                    ; A character of the output's type.
    CP   (HL)                      ; Does it match?
    INC  DE                        ; Step both,
    INC  HL                        ; keeping the flags.
    JR   NZ,.NEXTKIND              ; A mismatch: try the next type.
    DJNZ .TYPECHAR                 ; Until all three match.
    POP  HL                        ; Drop the type's address.
    LD   A,C                       ; C is the matching kind,
    LD   (OUT_KIND),A              ; the output's kind.
    POP  HL                        ; HL is the parse position again.
    OR   A                         ; Clear carry.
    RET                            ; Parsed.
.NEXTKIND:                     ; The type didn't match.
    POP  HL                        ; HL is the type tried.
    INC  HL                        ; Step over
    INC  HL                        ; its three
    INC  HL                        ; characters.
    SLA  C                         ; The next kind bit: 2, then 4.
    BIT  3,C                       ; Past .HEX's bit, 4?
    JR   Z,.KIND                   ; Try the next type.
    POP  HL                        ; Drop the parse position.
    JR   .BAD                      ; No such output kind.
.KINDS:                        ; The output types, in kind-bit order.
    DB   "COMBINHEX"               ; 1 .COM, 2 .BIN, 4 .HEX.
.FILES:                        ; F=N.
    LD   A,12                      ; F= is option 12 in OP_SEEN.
    CALL .ONCE                     ; Refuse it if repeated.
    RET  C                         ; Repeated: reported.
    CALL .DECIMAL                  ; DE is the number of entries.
    JR   C,.BAD                    ; Not a number from 1 to 65535.
    LD   A,D                       ; At most 255.
    OR   A                         ; A high byte?
    JR   NZ,.BAD                   ; Too many.
    LD   A,E                       ; The number of entries
    LD   (OP_FILES),A              ; for Phase C's file table.
    OR   A                         ; Clear carry.
    RET                            ; Parsed.

;@ROUTINE IN A OUT CARRY CLOBBERS A,B,ZERO,SIGN,PARITY,HALFCARRY
; Mark option number A seen in OP_SEEN, keeping HL and DE. If it already
; was, report it and return carry to .OPTION's caller instead.

.ONCE:                         ; A is the option's bit number, 8 to 15.
    PUSH HL                        ; Keep the parse position.
    PUSH DE                        ; Keep a drive option's field.
    LD   HL,1                      ; HL = 1 << A,
    OR   A                         ; for which A = 0 needs no shift.
    JR   Z,.MASK                   ; Never so, but kept general.
.SHIFT:                        ; Shift HL left A times.
    ADD  HL,HL                     ; One place.
    DEC  A                         ; One fewer to go.
    JR   NZ,.SHIFT                 ; Until A is 0.
.MASK:                         ; HL is the option's bit.
    EX   DE,HL                     ; DE is the bit.
    LD   HL,(OP_SEEN)              ; The options seen so far.
    LD   A,H                       ; Test the high bytes
    AND  D                         ; for the bit,
    LD   B,A                       ; keeping the result,
    LD   A,L                       ; and the low bytes,
    AND  E                         ; likewise,
    OR   B                         ; together.
    JR   NZ,.TWICE                 ; Already seen.
    LD   A,H                       ; Add the bit:
    OR   D                         ; the high byte,
    LD   H,A                       ; set,
    LD   A,L                       ; and the low byte,
    OR   E                         ; set.
    LD   L,A                       ; HL is the options seen, this one included.
    LD   (OP_SEEN),HL              ; Keep them.
    POP  DE                        ; Recover DE,
    POP  HL                        ; and the parse position.
    OR   A                         ; Clear carry.
    RET                            ; The option is new.
.TWICE:                        ; A repeated option.
    POP  DE                        ; Recover DE,
    POP  HL                        ; and the parse position.
    POP  BC                        ; Drop .ONCE's return: leave the option parser.
.BAD:                          ; A bad option, reported from its start.
    LD   HL,(.START)               ; The option's first character.
    JP   .REPORT                   ; L-COMMAND, returning carry to the caller.
.START:                        ; The option being parsed.
    DW   0                         ; Its first character's address.
.STACKW:                       ; The rest of STACK= after the S.
    DB   "TACK="                   ; Five characters, matched by .SPELL.
.FLAGS:                        ; Each flag's letter, then its bit in OP_FLAGS.
    DB   'K',OF_K,'M',OF_M,'Y',OF_Y,'N',OF_N ; Keep, map, symbols, no line table.
    DB   'R',OF_R,'B',OF_B,'Z',OF_Z,'V',OF_V ; Re-runnable, CCP, no .BAK, verify.

;@ROUTINE IN HL OUT HL,CARRY CLOBBERS A,BC,DE,ZERO,SIGN,PARITY,HALFCARRY
; Parse a file name, [d:]name[.type], at HL into FN_DISK, FN_NAME, FN_TYPE
; and FN_TYPED, leaving HL after it. Carry if it is malformed.

.FILENAME:                     ; HL is the name's first character.
    XOR  A                         ; No drive yet,
    LD   (FN_DISK),A               ; so the current one,
    LD   (FN_TYPED),A              ; and no type.
    PUSH HL                        ; Keep the parse position.
    LD   HL,FN_NAME                ; Blank the name and the type,
    LD   B,11                      ; eleven characters.
.BLANK:                        ; HL walks FN_NAME and FN_TYPE.
    LD   (HL),' '                  ; A space.
    INC  HL                        ; The next character.
    DJNZ .BLANK                    ; Until all eleven are blank.
    POP  HL                        ; HL is the name again.
    INC  HL                        ; Peek at the second character.
    LD   A,(HL)                    ; A colon there means a drive came first.
    DEC  HL                        ; HL is back at the first character.
    CP   ':'                       ; Is a drive named?
    JR   NZ,.NAME                  ; No: the name starts at HL.
    LD   A,(HL)                    ; A is the drive letter.
    SUB  'A'                       ; 0 for A:.
    RET  C                         ; Below A: malformed.
    CP   16                        ; Drives run from A: to P:;
    CCF                            ; carry above P.
    RET  C                         ; Malformed.
    INC  A                         ; The FCB counts A: as 1.
    LD   (FN_DISK),A               ; The name's drive.
    INC  HL                        ; Step over the letter
    INC  HL                        ; and the colon.
.NAME:                         ; HL is the name proper.
    LD   DE,FN_NAME                ; Copy it to FN_NAME,
    LD   B,8                       ; at most eight characters.
    CALL .FIELD                    ; A is the number copied; carry if too long.
    RET  C                         ; Too long.
    OR   A                         ; Was the name empty?
    SCF                            ; Then it is malformed,
    RET  Z                         ; an empty name.
    LD   A,(HL)                    ; Does a type follow?
    CP   '.'                       ; A dot introduces it.
    JR   NZ,.ENDNAME               ; No type.
    INC  HL                        ; Past the dot.
    LD   A,1                       ; A type was given,
    LD   (FN_TYPED),A              ; even if it turns out bad.
    LD   DE,FN_TYPE                ; Copy it to FN_TYPE,
    LD   B,3                       ; at most three characters.
    CALL .FIELD                    ; A is the number copied; carry if too long.
    RET  C                         ; Too long.
    OR   A                         ; Was the type empty?
    SCF                            ; Then it is malformed,
    RET  Z                         ; an empty type.
.ENDNAME:                      ; The name parsed.
    OR   A                         ; Clear carry.
    RET                            ; HL is after the name.

;@ROUTINE IN B,DE,HL OUT A,DE,HL,CARRY CLOBBERS C,ZERO,SIGN,PARITY,HALFCARRY
; Copy up to B name characters from HL to DE, stopping at the first that
; may not appear in a name. A is the number copied; carry if there are more
; than B.

.FIELD:                        ; B is the field's size.
    LD   C,0                       ; C counts the characters copied.
.CHAR:                         ; HL is the next character.
    LD   A,(HL)                    ; Fetch it.
    CALL .NAMECHAR                 ; Carry unless it may be in a name.
    JR   C,.STOP                   ; The field ends here.
    LD   A,C                       ; Is the field already full?
    CP   B                         ; Carry while C < B,
    CCF                            ; inverted: carry when full.
    RET  C                         ; Too long.
    LD   A,(HL)                    ; The character again.
    LD   (DE),A                    ; Store it.
    INC  HL                        ; The next character.
    INC  DE                        ; The next place.
    INC  C                         ; One more copied.
    JR   .CHAR                     ; Go on.
.STOP:                         ; HL is the first character after the field.
    LD   A,C                       ; A is the count.
    OR   A                         ; Carry clear.
    RET                            ; Z if the field is empty.

;@ROUTINE IN A OUT CARRY CLOBBERS ZERO,SIGN,PARITY,HALFCARRY
; Carry unless A may appear in a CP/M name (services §4.1): a letter, a
; digit or one of sixteen marks.

.NAMECHAR:                     ; A is an upper-cased character.
    CP   'A'                       ; Below the letters?
    JR   C,.OTHER                  ; Then a digit or a mark.
    CP   'Z'+1                     ; Carry for a letter,
    CCF                            ; inverted:
    RET  NC                        ; a letter may be in a name.
.OTHER:                        ; Not a letter.
    CP   '0'                       ; Below the digits?
    JR   C,.PUNCT                  ; Then perhaps a mark.
    CP   '9'+1                     ; Carry for a digit,
    CCF                            ; inverted:
    RET  NC                        ; a digit may be in a name.
.PUNCT:                        ; Neither a letter nor a digit.
    PUSH HL                        ; Keep the caller's HL,
    PUSH BC                        ; and BC.
    LD   HL,.SET                   ; Search the marks.
    LD   B,16                      ; The characters in .SET.
.LOOK:                         ; HL walks the marks.
    CP   (HL)                      ; Is it this mark?
    JR   Z,.YES                    ; Allowed.
    INC  HL                        ; The next mark.
    DJNZ .LOOK                     ; Until all sixteen are tried.
    POP  BC                        ; Recover BC,
    POP  HL                        ; and HL.
    SCF                            ; Carry: not allowed in a name.
    RET                            ; A is unchanged.
.YES:                          ; A is one of the marks.
    POP  BC                        ; Recover BC,
    POP  HL                        ; and HL.
    OR   A                         ; Clear carry: allowed.
    RET                            ; A is unchanged.
.SET:                          ; The marks a CP/M name may contain.
    DB   "!#$%&'()-@^_`{}~"        ; Sixteen, the count .LOOK searches.

;@ROUTINE IN HL OUT DE,HL,CARRY CLOBBERS A,BC,ZERO,SIGN,PARITY,HALFCARRY
; DE = a decimal number of 1 to 5 digits at HL, 1 to 65535, leaving HL after
; it. Carry if it is malformed or out of range.

.DECIMAL:                      ; HL is the number's first character.
    LD   DE,0                      ; DE is the value so far.
    LD   B,0                       ; B counts the digits.
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

;@ROUTINE IN HL OUT CARRY CLOBBERS A,BC,DE,HL,IX,ZERO,SIGN,PARITY,HALFCARRY
; Report L-COMMAND for the word at HL (to the next comma, bracket or the
; end), then return carry.

.BADWORD:                      ; HL is the stray word.
    JR   .REPORT                   ; The same report; a spare jump.

;@ROUTINE IN HL OUT CARRY CLOBBERS A,BC,DE,HL,IX,ZERO,SIGN,PARITY,HALFCARRY
; The same for a missing or misplaced bracket at HL - 1.

.BRACKET:                      ; HL is just past the offending character.
    DEC  HL                        ; Report from that character.
.REPORT:                       ; HL is the start of the bad word.
    LD   DE,CMD_BAD                ; Copy the word for the diagnostic,
    LD   B,30                      ; at most 30 characters.
.COPYWORD:                     ; HL walks the word, DE the copy.
    LD   A,(HL)                    ; The next character.
    OR   A                         ; The end of the tail?
    JR   Z,.ENDWORD                ; The word ends.
    CP   ','                       ; A comma?
    JR   Z,.ENDWORD                ; The word ends.
    CP   ']'                       ; A closing bracket?
    JR   Z,.ENDWORD                ; The word ends.
    LD   (DE),A                    ; Copy the character.
    INC  HL                        ; The next character.
    INC  DE                        ; The next place.
    DJNZ .COPYWORD                 ; Until 30 are copied.
.ENDWORD:                      ; DE is just past the copy.
    XOR  A                         ; A zero
    LD   (DE),A                    ; terminates it.
    LD   HL,CMD_BAD                ; The word is argument 1.
    LD   (DG_ARG1),HL              ; For ^1 in the text.
    LD   HL,224                    ; L-COMMAND.
    CALL DG_ERROR                  ; Report it.
    SCF                            ; Carry: the tail is malformed.
    RET                            ; To CMD_READ's caller, or .OPTION's.
