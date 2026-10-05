MM_CEND:
MM_IBEG:
; Compact variable-length keyword table followed by parser-only names.

KW_TAB:
    DB   3,"var",TK_VAR
    DB   2,"as",TK_AS
    DB   2,"u8",TK_U8
    DB   3,"u16",TK_U16
    DB   7,"boolean",TK_BOOL
    DB   4,"true",TK_TRUE
    DB   5,"false",TK_FALSE
    DB   5,"const",TK_CONST
    DB   2,"or",TK_OR
    DB   3,"xor",TK_XOR
    DB   3,"mod",TK_MOD
    DB   6,"assert",TK_ASSRT
    DB   3,"and",TK_AND
    DB   3,"not",TK_NOT
    DB   4,"fail",TK_FAIL
    DB   3,"end",TK_END
    DB   3,"sub",TK_SUB
    DB   5,"fails",TK_FAILS
    DB   3,"for",TK_FOR
    DB   5,"until",TK_UNTIL
    DB   7,"forward",TK_FORW
    DB   6,"return",TK_RET
    DB   2,"if",TK_IF
    DB   6,"elseif",TK_ELSIF
    DB   4,"else",TK_ELSE
    DB   5,"while",TK_WHILE
    DB   2,"to",TK_TO
    DB   4,"step",TK_STEP
    DB   4,"exit",TK_EXIT
    DB   8,"continue",TK_CONT
    DB   6,"record",TK_REC
    DB   6,"string",TK_STR
    DB   6,"handle",TK_HANDL
KW_CNT EQU  33

KW_PUNCT:
    DB   "=",TK_EQ
    DB   ",",TK_COMMA
    DB   "-",TK_MINUS
    DB   "+",TK_PLUS
    DB   "*",TK_STAR
    DB   "/",TK_SLASH
; High-bit descriptors route numeric prefixes to the based-number
; scanner; the low seven bits retain its one-past digit count.
    DB   ".",TK_DOT
    DB   "$",$85
    DB   "%",$91
KW_PCNT EQU  9

KW_MAIN: DB   "main"
KW_LEN: DB   "length"

; Predefined services and error constants remain ordinary names to the
; tokenizer. The packed table gives the parser one namespace and dispatch
; authority without installing source-visible symbol entries.
KW_NAMES:
    DB   13
.READ:
    DB   "readInputByte"
    DB   15
.WRITE:
    DB   "writeOutputByte"
    DB   15,"readStorageByte"
    DB   18,"rewindStorageInput"
    DB   16,"writeStorageByte"
    DB   17,"seekStorageOutput"
    DB   10,"endOfInput"
    DB   12,"inputFailure"
    DB   13,"outputFailure"
    DB   14,"storageFailure"
KW_NCNT EQU  10

; Complete service selectors: target ID in bits 0..2, argument type in bits
; 3..4, successful u8 result in bit 5, and service kind in bit 7.
KW_SIGS:
    DB   RO_FIO+RO_RES8+RO_READ
    DB   RO_FIO+(SY_U8*8)+RO_WRITE
    DB   RO_FIO+RO_RES8+RO_FETCH
    DB   RO_FIO+RO_RESET
    DB   RO_FIO+(SY_U8*8)+RO_STORE
    DB   RO_FIO+(SY_U16*8)+RO_SEEK

MM_IEND:
MM_REND:
SH_CBEG:
