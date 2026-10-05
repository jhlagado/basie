;==========================================================================
;  Keyword and punctuation tables
;==========================================================================
;
;  The compiler's immutable data: the tables the tokenizer and the parsers
;  search by spelling. This file opens the compiler's immutable data, so it
;  carries the image markers that end the compiler code; the predeclared
;  names (PREDEF.ASM) follow it, and the CP/M shell's first line ends the
;  core.
;
;  Tables:
;    KW_TAB    reserved words, searched by TK_WORD
;    KW_PUNCT  single-character punctuators, searched by TK_NEXT
;    KW_MAIN   the spelling `main`, compared by EX_MAIN
;    KW_LEN    the spelling `length`, compared by the field parser
;    KW_CAP    the spelling `capacity`, likewise
;    KW_ID     the spelling `id`, which no routine may take (AC_SIG)
;    KW_FILE   the spelling `File`, the type of files (AC_NAMED)
;    KW_FROM   the spelling `from`, which begins a result's from clause
;
;  KW_TAB holds length-prefixed spellings: a length byte, the bytes of the
;  word and the token kind. Matching is exact and case-sensitive. A word
;  that matches no KW_TAB entry is a NAME, so `main`, `length`, `File` and
;  the predeclared names reach the parser as NAME tokens and are
;  recognised there. The counts (KW_CNT, KW_PCNT) must be kept equal to the
;  number of entries by hand.

MM_CEND:                       ; End of compiler code (marker).
MM_IBEG:                       ; Start of compiler immutable data (marker).

; Reserved words: length, spelling, token kind. A type keyword's kind
; byte is KW_TYPE plus its type ID: it is a TK_TYPE token whose payload
; is the type. The search is linear, so order affects only speed.

KW_TAB:
    DB   3,"var",TK_VAR            ; Program or local variable declaration.
    DB   2,"as",TK_AS              ; Introduces a type.
    DB   2,"u8",KW_TYPE+SY_U8      ; Unsigned byte type.
    DB   3,"u16",KW_TYPE+SY_U16    ; Unsigned word type.
    DB   7,"boolean",KW_TYPE+SY_BOOL ; Boolean type.
    DB   2,"i8",KW_TYPE+SY_I8      ; Signed byte type.
    DB   3,"i16",KW_TYPE+SY_I16    ; Signed word type.
    DB   3,"u32",KW_TYPE+SY_U32    ; Unsigned long type.
    DB   3,"i32",KW_TYPE+SY_I32    ; Signed long type.
    DB   3,"f32",KW_TYPE+SY_F32    ; Floating-point type, not yet compiled.
    DB   4,"true",TK_TRUE          ; Boolean literal.
    DB   5,"false",TK_FALSE        ; Boolean literal.
    DB   5,"const",TK_CONST        ; Constant declaration.
    DB   2,"or",TK_OR              ; Logical or bitwise or.
    DB   3,"xor",TK_XOR            ; Bitwise exclusive or.
    DB   3,"mod",TK_MOD            ; Remainder operator.
    DB   3,"shl",TK_SHL            ; Shift left.
    DB   3,"shr",TK_SHR            ; Shift right.
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
    DB   7,"private",TK_PRIV       ; A declaration its part alone sees.
    DB   7,"include",TK_INCL       ; A part a part depends on.
KW_CNT EQU  42                 ; Entries in KW_TAB.
KW_TYPE EQU  $80               ; A type keyword's kind byte: this plus its type.

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
    DB   "$",$89                   ; Hexadecimal prefix: at most eight digits.
    DB   "%",$A1                   ; Binary prefix: at most 32 digits.
KW_PCNT EQU  9                 ; Entries in KW_PUNCT.

; Spellings compared against the current NAME token by length-checked
; matches, so none needs a length byte.

KW_MAIN: DB   "main"           ; The program's entry routine, four bytes.
KW_LEN: DB   "length"          ; The string length field, six bytes.
KW_CAP: DB   "capacity"        ; An open string's capacity field, eight bytes.
KW_ID: DB   "id"               ; The conversion no routine may be named.
KW_FILE: DB   "File"           ; The File type, four bytes.
KW_FROM: DB   "from"           ; A result's from clause, four bytes.
