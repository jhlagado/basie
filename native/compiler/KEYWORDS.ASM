;==========================================================================
;  Keyword, punctuation and predefined-name tables
;==========================================================================
;
;  The compiler's immutable data: the tables the tokenizer and the routine
;  parser search by spelling. This file closes the compiler core, so it
;  also carries the image markers that separate compiler code, immutable
;  data and the CP/M shell that follows.
;
;  Tables:
;    KW_TAB    reserved words, searched by TK_WORD
;    KW_PUNCT  single-character punctuators, searched by TK_NEXT
;    KW_MAIN   the spelling `main`, compared by EX_MAIN
;    KW_LEN    the spelling `length`, compared by the field parser
;    KW_NAMES  predefined services and error constants, searched by RO_LIB
;    KW_SIGS   the service signatures, indexed by RO_SERVE
;
;  KW_TAB and KW_NAMES are length-prefixed spellings: a length byte, the
;  bytes of the word and, in KW_TAB only, the token kind. Matching is exact
;  and case-sensitive. A word that matches no KW_TAB entry is a NAME, so
;  `main`, `length` and the predefined names reach the parser as NAME
;  tokens and are recognised there. The counts (KW_CNT, KW_PCNT, KW_NCNT)
;  must be kept equal to the number of entries by hand.

MM_CEND:                       ; End of compiler code (marker).
MM_IBEG:                       ; Start of compiler immutable data (marker).

; Reserved words: length, spelling, token kind. The search is linear, so
; order affects only speed.

KW_TAB:
    DB   3,"var",TK_VAR            ; Program or local variable declaration.
    DB   2,"as",TK_AS              ; Introduces a type.
    DB   2,"u8",TK_U8              ; Unsigned byte type.
    DB   3,"u16",TK_U16            ; Unsigned word type.
    DB   7,"boolean",TK_BOOL       ; Boolean type.
    DB   4,"true",TK_TRUE          ; Boolean literal.
    DB   5,"false",TK_FALSE        ; Boolean literal.
    DB   5,"const",TK_CONST        ; Constant declaration.
    DB   2,"or",TK_OR              ; Logical or bitwise or.
    DB   3,"xor",TK_XOR            ; Bitwise exclusive or.
    DB   3,"mod",TK_MOD            ; Remainder operator.
    DB   6,"assert",TK_ASSRT       ; Compile-time assertion.
    DB   3,"and",TK_AND            ; Logical or bitwise and.
    DB   3,"not",TK_NOT            ; Logical or bitwise complement.
    DB   4,"fail",TK_FAIL          ; Raise a recoverable failure; also `else fail`.
    DB   3,"end",TK_END            ; Closes a block.
    DB   3,"sub",TK_SUB            ; Routine definition.
    DB   5,"fails",TK_FAILS        ; Marks a routine that can fail.
    DB   3,"for",TK_FOR            ; Counted loop.
    DB   5,"until",TK_UNTIL        ; Exclusive counted-loop bound.
    DB   7,"forward",TK_FORW       ; Forward routine signature.
    DB   6,"return",TK_RET         ; Return from a routine.
    DB   2,"if",TK_IF              ; Conditional.
    DB   6,"elseif",TK_ELSIF       ; Further conditional arm.
    DB   4,"else",TK_ELSE          ; Final arm; also `else fail`.
    DB   5,"while",TK_WHILE        ; Pre-tested loop.
    DB   2,"to",TK_TO              ; Inclusive counted-loop bound.
    DB   4,"step",TK_STEP          ; Counted-loop step.
    DB   4,"exit",TK_EXIT          ; Leave the innermost loop.
    DB   8,"continue",TK_CONT      ; Next iteration of the innermost loop.
    DB   6,"record",TK_REC         ; Record type declaration.
    DB   6,"string",TK_STR         ; String type.
    DB   6,"handle",TK_HANDL       ; Local failure handler.
KW_CNT EQU  33                 ; Entries in KW_TAB.

; Punctuators found by table search: the character, then a descriptor.
; Below $80 the descriptor is the token kind. With bit 7 set it routes a
; numeric prefix to the based-number scanner, and the low seven bits are
; one more than the most digits that base allows. Characters that start
; longer tokens or nest ( ) [ ] < > / are tested by TK_NEXT before this
; search, so the "/" entry here is never reached.

KW_PUNCT:
    DB   "=",TK_EQ                 ; Assignment and equality.
    DB   ",",TK_COMMA              ; List separator.
    DB   "-",TK_MINUS              ; Subtraction and negation.
    DB   "+",TK_PLUS               ; Addition and unary plus.
    DB   "*",TK_STAR               ; Multiplication.
    DB   "/",TK_SLASH              ; Unreachable: TK_NEXT handles "/" first.
    DB   ".",TK_DOT                ; Field selection.
    DB   "$",$85                   ; Hexadecimal prefix: at most four digits.
    DB   "%",$91                   ; Binary prefix: at most sixteen digits.
KW_PCNT EQU  9                 ; Entries in KW_PUNCT.

; Spellings compared against the current NAME token by length-checked
; matches, so neither needs a length byte.

KW_MAIN: DB   "main"           ; The program's entry routine, four bytes.
KW_LEN: DB   "length"          ; The string length field, six bytes.

; Predefined services and error constants are ordinary NAME tokens to the
; tokenizer. RO_LIB searches this table so the parser can dispatch them
; without installing source-visible symbols. The ordinal of an entry is
; its position: services 0..5 in RO_READ..RO_SEEK order, which also
; indexes KW_SIGS, then error constants from RO_ERRS, whose values are
; 1..4 in table order.

KW_NAMES:
    DB   13,"readInputByte"        ; Service 0, RO_READ.
    DB   15,"writeOutputByte"      ; Service 1, RO_WRITE.
    DB   15,"readStorageByte"      ; Service 2, RO_FETCH.
    DB   18,"rewindStorageInput"   ; Service 3, RO_RESET.
    DB   16,"writeStorageByte"     ; Service 4, RO_STORE.
    DB   17,"seekStorageOutput"    ; Service 5, RO_SEEK.
    DB   10,"endOfInput"           ; Error constant 1.
    DB   12,"inputFailure"         ; Error constant 2.
    DB   13,"outputFailure"        ; Error constant 3.
    DB   14,"storageFailure"       ; Error constant 4.
KW_NCNT EQU  10                ; Entries in KW_NAMES.

; Service selectors, one per service in KW_NAMES order: the service ID in
; bits 0..2, the argument type in bits 3..4 (zero for none), a successful
; u8 result in bit 5 and the file-I/O service kind in bit 7.

KW_SIGS:
    DB   RO_FIO+RO_RES8+RO_READ    ; readInputByte() returns u8.
    DB   RO_FIO+(SY_U8*8)+RO_WRITE ; writeOutputByte(u8).
    DB   RO_FIO+RO_RES8+RO_FETCH   ; readStorageByte() returns u8.
    DB   RO_FIO+RO_RESET           ; rewindStorageInput().
    DB   RO_FIO+(SY_U8*8)+RO_STORE ; writeStorageByte(u8).
    DB   RO_FIO+(SY_U16*8)+RO_SEEK ; seekStorageOutput(u16).

MM_IEND:                       ; End of compiler immutable data (marker).
MM_REND:                       ; End of the compiler core (marker).
SH_CBEG:                       ; Start of the CP/M shell's code (marker).
