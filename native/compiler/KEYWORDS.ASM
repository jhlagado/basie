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
;  KW_TAB holds spellings whose last byte has bit 7 set, each followed by
;  its token kind. Matching is exact and case-sensitive. A word
;  that matches no KW_TAB entry is a NAME, so `main`, `length`, `File` and
;  the predeclared names reach the parser as NAME tokens and are
;  recognised there. The counts (KW_CNT, KW_PCNT) must be kept equal to the
;  number of entries by hand.

MM_CEND:                       ; End of compiler code (marker).
MM_IBEG:                       ; Start of compiler immutable data (marker).

; Reserved words: the spelling, its last byte with bit 7 set, then the
; token kind; a zero byte ends the table. A type keyword's kind
; byte is KW_TYPE plus its type ID: it is a TK_TYPE token whose payload
; is the type. The search is linear, so order affects only speed.

KW_TAB:
    DB   "va",'r'+$80,TK_VAR       ; Program or local variable declaration.
    DB   "a",'s'+$80,TK_AS         ; Introduces a type.
    DB   "u",'8'+$80,KW_TYPE+SY_U8 ; Unsigned byte type.
    DB   "u1",'6'+$80,KW_TYPE+SY_U16 ; Unsigned word type.
    DB   "boolea",'n'+$80,KW_TYPE+SY_BOOL ; Boolean type.
    DB   "i",'8'+$80,KW_TYPE+SY_I8 ; Signed byte type.
    DB   "i1",'6'+$80,KW_TYPE+SY_I16 ; Signed word type.
    DB   "u3",'2'+$80,KW_TYPE+SY_U32 ; Unsigned long type.
    DB   "i3",'2'+$80,KW_TYPE+SY_I32 ; Signed long type.
    DB   "f3",'2'+$80,KW_TYPE+SY_F32 ; Floating-point type.
    DB   "tru",'e'+$80,TK_TRUE     ; Boolean literal.
    DB   "fals",'e'+$80,TK_FALSE   ; Boolean literal.
    DB   "cons",'t'+$80,TK_CONST   ; Constant declaration.
    DB   "o",'r'+$80,TK_OR         ; Logical or bitwise or.
    DB   "xo",'r'+$80,TK_XOR       ; Bitwise exclusive or.
    DB   "mo",'d'+$80,TK_MOD       ; Remainder operator.
    DB   "sh",'l'+$80,TK_SHL       ; Shift left.
    DB   "sh",'r'+$80,TK_SHR       ; Shift right.
    DB   "asser",'t'+$80,TK_ASSRT  ; Compile-time assertion.
    DB   "an",'d'+$80,TK_AND       ; Logical or bitwise and.
    DB   "no",'t'+$80,TK_NOT       ; Logical or bitwise complement.
    DB   "fai",'l'+$80,TK_FAIL     ; Raise a recoverable failure; also `else fail`.
    DB   "en",'d'+$80,TK_END       ; Closes a block.
    DB   "su",'b'+$80,TK_SUB       ; Routine definition.
    DB   "fail",'s'+$80,TK_FAILS   ; Marks a routine that can fail.
    DB   "fo",'r'+$80,TK_FOR       ; Counted loop.
    DB   "unti",'l'+$80,TK_UNTIL   ; Exclusive counted-loop bound.
    DB   "forwar",'d'+$80,TK_FORW  ; Forward routine signature.
    DB   "retur",'n'+$80,TK_RET    ; Return from a routine.
    DB   "i",'f'+$80,TK_IF         ; Conditional.
    DB   "elsei",'f'+$80,TK_ELSIF  ; Further conditional arm.
    DB   "els",'e'+$80,TK_ELSE     ; Final arm; also `else fail`.
    DB   "whil",'e'+$80,TK_WHILE   ; Pre-tested loop.
    DB   "t",'o'+$80,TK_TO         ; Inclusive counted-loop bound.
    DB   "ste",'p'+$80,TK_STEP     ; Counted-loop step.
    DB   "exi",'t'+$80,TK_EXIT     ; Leave the innermost loop.
    DB   "continu",'e'+$80,TK_CONT ; Next iteration of the innermost loop.
    DB   "recor",'d'+$80,TK_REC    ; Record type declaration.
    DB   "strin",'g'+$80,TK_STR    ; String type.
    DB   "handl",'e'+$80,TK_HANDL  ; Local failure handler.
    DB   "privat",'e'+$80,TK_PRIV  ; A declaration its part alone sees.
    DB   "includ",'e'+$80,TK_INCL  ; A part a part depends on.
    DB   "selec",'t'+$80,TK_SEL    ; Selection by a subject's value.
    DB   "cas",'e'+$80,TK_CASE     ; A select's arm.
    DB   "som",'e'+$80,TK_SOME     ; A handle selection's arm.
    DB   "non",'e'+$80,TK_NONE     ; A handle selection's arm; no handle.
    DB   "mov",'e'+$80,TK_MOVE     ; A handle moved.
    DB   0                         ; The end of the table: no word starts with zero.
KW_CNT EQU  47                 ; Entries in KW_TAB.
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
