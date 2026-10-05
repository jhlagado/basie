;==========================================================================
;  Grammar tables
;==========================================================================
;
;  The LL(1) tables that LL1.ASM interprets. This file was generated from
;  Nucleus's grammar (grammar/stage7-grammar.json) by a generator that wrote
;  AZM; the conversion to ATOM translated it, and the generator was retired.
;  Step 67 brings a generator for Basie's grammar that writes this layout
;  under the same names. Until then the file is edited only by hand, and
;  every offset and count below must be kept consistent with the data.
;
;  Grammar symbols are bytes: $00..$3F a token kind, $40..$7F nonterminal
;  (row) n-$40, $80..$FE action n-$80 (LL1.ASM).
;
;  GR_ROWX   two bytes per nonterminal: the offset of its row from GR_ROWS,
;            then the diagnostic raised when no production of the row is
;            predicted by the next token.
;  GR_ROWS   the rows. A row is a list of alternatives: a production byte,
;            then the token kinds that predict it. Bit 7 marks the last
;            token of each alternative and, on the production byte, the
;            row's last alternative.
;  GR_ALTX   one byte per production below GR_SPLIT: the offset of its body
;            from GR_ALTS, then one entry more that ends the last body. The
;            length of a body is the next entry minus its own.
;  GR_ALTXH  the same for productions GR_SPLIT and up, renumbered from zero,
;            with bodies from GR_ALTHI. Splitting the bodies in two keeps
;            every offset within a byte.
;  GR_ALTS   production bodies, each stored right to left so that the engine
;            pushes it in one copy and its leftmost symbol ends on top.
;  GR_ACTX   one word per action: the routine LL1.ASM calls, with the
;            action ordinal in A.
;
;  Names. GR_ROWn is row n (nonterminal $40+n) and GR_ALTn production n.
;  An X suffix names a directory (GR_ROWX, GR_ALTX, GR_ALTXH, GR_ACTX), an S
;  the base its offsets count from (GR_ROWS, GR_ALTS; GR_ALTHI for the high
;  half), _N a count, and _E or XE an end. The directories hold numbers, not
;  label differences, because ATOM takes a forward reference only as one
;  symbol with a small addend; each entry's comment gives the difference it
;  stands for and the nonterminal. The row and body labels are kept for
;  those comments and for listings; nothing references them.
;
;  Comments on GR_ACTX name the grammar's action: a: is a semantic action,
;  x: an island where a hand-written parser (expressions, initializers,
;  steps, name statements) takes over. A parameter is the value the shared
;  routine derives from the ordinal: the token kind for exit and continue,
;  1 for to and 0 for until, the scalar type for u8, u16 and boolean.

GR_ROW_N EQU  42                   ; Nonterminals, one row each.
GR_ALT_N EQU  69                   ; Productions.
GR_SPLIT EQU  35                   ; First production in the high directory.
GR_ACT_N EQU  76                   ; Actions in GR_ACTX.
GR_START EQU  $40                  ; Start symbol: compilation-unit, row 0.
GR_STMT EQU  $40+25                ; The statement nonterminal, row 25.
GR_LOCAL EQU  $40+22               ; The local-declaration nonterminal, row 22.
GR_EXIT EQU  46                    ; Action ordinal of EmitExit (AC_GOTO).
GR_CONT EQU  47                    ; Action ordinal of EmitContinue (AC_GOTO).
GR_TO EQU  61                      ; Action ordinal of ForTo (AC_FORTO).
GR_UNTIL EQU  62                   ; Action ordinal of ForUntil (AC_FORTO).
GR_U8 EQU  71                      ; Action ordinal of TypeU8 (AC_TYPE).
GR_U16 EQU  72                     ; Action ordinal of TypeU16 (AC_TYPE).
GR_BOOL EQU  73                    ; Action ordinal of TypeBoolean (AC_TYPE).

; Row directory: offset from GR_ROWS, diagnostic when nothing is predicted.

GR_ROWX:
    DB   0,DG_TOP                  ; GR_ROW0-GR_ROWS; compilation-unit
    DB   8,DG_TOP                  ; GR_ROW1-GR_ROWS; top-level-list
    DB   17,DG_TOP                 ; GR_ROW2-GR_ROWS; top-level-declaration
    DB   29,DG_TOP                 ; GR_ROW3-GR_ROWS; const-declaration
    DB   31,DG_EQ                  ; GR_ROW4-GR_ROWS; const-declaration-tail
    DB   35,DG_TOP                 ; GR_ROW5-GR_ROWS; assert-declaration
    DB   37,DG_TOP                 ; GR_ROW6-GR_ROWS; program-var-declaration
    DB   39,DG_EQ                  ; GR_ROW7-GR_ROWS; program-initializer-opt
    DB   43,DG_TOP                 ; GR_ROW8-GR_ROWS; record-declaration
    DB   45,DG_EMPTY               ; GR_ROW9-GR_ROWS; record-fields
    DB   47,DG_VALUE               ; GR_ROW10-GR_ROWS; record-field-tail
    DB   51,DG_VALUE               ; GR_ROW11-GR_ROWS; record-field
    DB   53,DG_FORW                ; GR_ROW12-GR_ROWS; forward-declaration
    DB   55,DG_SUB                 ; GR_ROW13-GR_ROWS; sub-definition
    DB   57,DG_LPAR                ; GR_ROW14-GR_ROWS; sub-definition-tail
    DB   61,DG_RPAR                ; GR_ROW15-GR_ROWS; parameter-list
    DB   65,DG_RPAR                ; GR_ROW16-GR_ROWS; parameter-tail
    DB   69,DG_VALUE               ; GR_ROW17-GR_ROWS; parameter
    DB   71,DG_EOL                 ; GR_ROW18-GR_ROWS; result-opt
    DB   76,DG_EOL                 ; GR_ROW19-GR_ROWS; fails-opt
    DB   80,DG_VALUE               ; GR_ROW20-GR_ROWS; routine-body
    DB   94,DG_VALUE               ; GR_ROW21-GR_ROWS; local-list
    DB   106,DG_VAR                ; GR_ROW22-GR_ROWS; local-declaration
    DB   108,DG_EOL                ; GR_ROW23-GR_ROWS; local-initializer-opt
    DB   112,DG_VALUE              ; GR_ROW24-GR_ROWS; statement-sequence
    DB   125,DG_VALUE              ; GR_ROW25-GR_ROWS; statement
    DB   140,DG_RET                ; GR_ROW26-GR_ROWS; return-statement
    DB   142,DG_EOL                ; GR_ROW27-GR_ROWS; return-value-opt
    DB   156,DG_KFAIL              ; GR_ROW28-GR_ROWS; fail-statement
    DB   158,DG_LEAK               ; GR_ROW29-GR_ROWS; name-statement-tail
    DB   162,DG_LOOP               ; GR_ROW30-GR_ROWS; transfer-statement
    DB   166,DG_IF                 ; GR_ROW31-GR_ROWS; if-statement
    DB   168,DG_VALUE              ; GR_ROW32-GR_ROWS; if-tail
    DB   174,DG_VALUE              ; GR_ROW33-GR_ROWS; while-statement
    DB   176,DG_FOR                ; GR_ROW34-GR_ROWS; for-statement
    DB   178,DG_VALUE              ; GR_ROW35-GR_ROWS; for-bound
    DB   182,DG_EOL                ; GR_ROW36-GR_ROWS; for-step-opt
    DB   186,DG_TYPE               ; GR_ROW37-GR_ROWS; type
    DB   192,DG_TYPE               ; GR_ROW38-GR_ROWS; type-atom
    DB   200,DG_VALUE              ; GR_ROW39-GR_ROWS; string-capacity
    DB   214,DG_VALUE              ; GR_ROW40-GR_ROWS; type-array-opt
    DB   222,DG_TYPE               ; GR_ROW41-GR_ROWS; scalar-type
GR_ROWXE:                          ; End of the row directory.

; Rows: alternatives of production byte and predicting token kinds.

GR_ROWS:                           ; Base of the row offsets.
GR_ROW0:                           ; compilation-unit
    DB   0+$80
    DB   TK_ASSRT
    DB   TK_CONST
    DB   TK_EOF
    DB   TK_FORW
    DB   TK_REC
    DB   TK_SUB
    DB   TK_VAR+$80
GR_ROW1:                           ; top-level-list
    DB   1
    DB   TK_ASSRT
    DB   TK_CONST
    DB   TK_FORW
    DB   TK_REC
    DB   TK_SUB
    DB   TK_VAR+$80
    DB   2+$80
    DB   TK_EOF+$80
GR_ROW2:                           ; top-level-declaration
    DB   3
    DB   TK_CONST+$80
    DB   4
    DB   TK_ASSRT+$80
    DB   5
    DB   TK_VAR+$80
    DB   6
    DB   TK_REC+$80
    DB   7
    DB   TK_FORW+$80
    DB   8+$80
    DB   TK_SUB+$80
GR_ROW3:                           ; const-declaration
    DB   9+$80
    DB   TK_CONST+$80
GR_ROW4:                           ; const-declaration-tail
    DB   10
    DB   TK_EQ+$80
    DB   11+$80
    DB   TK_AS+$80
GR_ROW5:                           ; assert-declaration
    DB   12+$80
    DB   TK_ASSRT+$80
GR_ROW6:                           ; program-var-declaration
    DB   13+$80
    DB   TK_VAR+$80
GR_ROW7:                           ; program-initializer-opt
    DB   14
    DB   TK_EQ+$80
    DB   2+$80
    DB   TK_EOL+$80
GR_ROW8:                           ; record-declaration
    DB   15+$80
    DB   TK_REC+$80
GR_ROW9:                           ; record-fields
    DB   16+$80
    DB   TK_NAME+$80
GR_ROW10:                          ; record-field-tail
    DB   16
    DB   TK_NAME+$80
    DB   2+$80
    DB   TK_END+$80
GR_ROW11:                          ; record-field
    DB   17+$80
    DB   TK_NAME+$80
GR_ROW12:                          ; forward-declaration
    DB   18+$80
    DB   TK_FORW+$80
GR_ROW13:                          ; sub-definition
    DB   19+$80
    DB   TK_SUB+$80
GR_ROW14:                          ; sub-definition-tail
    DB   20
    DB   TK_LPAR+$80
    DB   21+$80
    DB   TK_EOL+$80
GR_ROW15:                          ; parameter-list
    DB   22
    DB   TK_NAME+$80
    DB   2+$80
    DB   TK_RPAR+$80
GR_ROW16:                          ; parameter-tail
    DB   23
    DB   TK_COMMA+$80
    DB   2+$80
    DB   TK_RPAR+$80
GR_ROW17:                          ; parameter
    DB   24+$80
    DB   TK_NAME+$80
GR_ROW18:                          ; result-opt
    DB   25
    DB   TK_AS+$80
    DB   2+$80
    DB   TK_FAILS
    DB   TK_EOL+$80
GR_ROW19:                          ; fails-opt
    DB   26
    DB   TK_FAILS+$80
    DB   2+$80
    DB   TK_EOL+$80
GR_ROW20:                          ; routine-body
    DB   27
    DB   TK_CONT
    DB   TK_END
    DB   TK_EXIT
    DB   TK_FAIL
    DB   TK_FOR
    DB   TK_IF
    DB   TK_NAME
    DB   TK_RET
    DB   TK_VAR
    DB   TK_WHILE+$80
    DB   28+$80
    DB   TK_ELSE
    DB   TK_ELSIF+$80
GR_ROW21:                          ; local-list
    DB   29
    DB   TK_VAR+$80
    DB   2+$80
    DB   TK_CONT
    DB   TK_END
    DB   TK_EXIT
    DB   TK_FAIL
    DB   TK_FOR
    DB   TK_IF
    DB   TK_NAME
    DB   TK_RET
    DB   TK_WHILE+$80
GR_ROW22:                          ; local-declaration
    DB   30+$80
    DB   TK_VAR+$80
GR_ROW23:                          ; local-initializer-opt
    DB   31
    DB   TK_EQ+$80
    DB   32+$80
    DB   TK_EOL+$80
GR_ROW24:                          ; statement-sequence
    DB   33
    DB   TK_CONT
    DB   TK_EXIT
    DB   TK_FAIL
    DB   TK_FOR
    DB   TK_IF
    DB   TK_NAME
    DB   TK_RET
    DB   TK_WHILE+$80
    DB   2+$80
    DB   TK_ELSE
    DB   TK_ELSIF
    DB   TK_END+$80
GR_ROW25:                          ; statement
    DB   34
    DB   TK_NAME+$80
    DB   35
    DB   TK_RET+$80
    DB   36
    DB   TK_FAIL+$80
    DB   37
    DB   TK_CONT
    DB   TK_EXIT+$80
    DB   38
    DB   TK_IF+$80
    DB   39
    DB   TK_WHILE+$80
    DB   40+$80
    DB   TK_FOR+$80
GR_ROW26:                          ; return-statement
    DB   41+$80
    DB   TK_RET+$80
GR_ROW27:                          ; return-value-opt
    DB   42
    DB   TK_CHAR
    DB   TK_FALSE
    DB   TK_LPAR
    DB   TK_MINUS
    DB   TK_NAME
    DB   TK_NOT
    DB   TK_NUM
    DB   TK_PLUS
    DB   TK_TRUE
    DB   TK_U16
    DB   TK_U8+$80
    DB   43+$80
    DB   TK_EOL+$80
GR_ROW28:                          ; fail-statement
    DB   44+$80
    DB   TK_FAIL+$80
GR_ROW29:                          ; name-statement-tail
    DB   45
    DB   TK_EOL+$80
    DB   46+$80
    DB   TK_HANDL+$80
GR_ROW30:                          ; transfer-statement
    DB   47
    DB   TK_EXIT+$80
    DB   48+$80
    DB   TK_CONT+$80
GR_ROW31:                          ; if-statement
    DB   49+$80
    DB   TK_IF+$80
GR_ROW32:                          ; if-tail
    DB   50
    DB   TK_ELSIF+$80
    DB   51
    DB   TK_ELSE+$80
    DB   52+$80
    DB   TK_END+$80
GR_ROW33:                          ; while-statement
    DB   53+$80
    DB   TK_WHILE+$80
GR_ROW34:                          ; for-statement
    DB   54+$80
    DB   TK_FOR+$80
GR_ROW35:                          ; for-bound
    DB   55
    DB   TK_TO+$80
    DB   56+$80
    DB   TK_UNTIL+$80
GR_ROW36:                          ; for-step-opt
    DB   57
    DB   TK_STEP+$80
    DB   58+$80
    DB   TK_EOL+$80
GR_ROW37:                          ; type
    DB   59+$80
    DB   TK_BOOL
    DB   TK_NAME
    DB   TK_STR
    DB   TK_U16
    DB   TK_U8+$80
GR_ROW38:                          ; type-atom
    DB   60
    DB   TK_BOOL
    DB   TK_U16
    DB   TK_U8+$80
    DB   61
    DB   TK_NAME+$80
    DB   62+$80
    DB   TK_STR+$80
GR_ROW39:                          ; string-capacity
    DB   63
    DB   TK_CHAR
    DB   TK_FALSE
    DB   TK_LPAR
    DB   TK_MINUS
    DB   TK_NAME
    DB   TK_NOT
    DB   TK_NUM
    DB   TK_PLUS
    DB   TK_TRUE
    DB   TK_U16
    DB   TK_U8+$80
    DB   64+$80
    DB   TK_RBRAC+$80
GR_ROW40:                          ; type-array-opt
    DB   65
    DB   TK_LBRAC+$80
    DB   2+$80
    DB   TK_COMMA
    DB   TK_EQ
    DB   TK_FAILS
    DB   TK_EOL
    DB   TK_RPAR+$80
GR_ROW41:                          ; scalar-type
    DB   66
    DB   TK_U8+$80
    DB   67
    DB   TK_U16+$80
    DB   68+$80
    DB   TK_BOOL+$80
GR_ROW_E:                          ; End of the rows.

; Production directories: body offsets, each list closed by an end entry.

GR_ALTX:
    DB   0                         ; GR_ALT0-GR_ALTS; compilation-unit
    DB   3                         ; GR_ALT1-GR_ALTS; top-level-list
    DB   5                         ; GR_ALT2-GR_ALTS; top-level-list
    DB   5                         ; GR_ALT3-GR_ALTS; top-level-declaration
    DB   6                         ; GR_ALT4-GR_ALTS; top-level-declaration
    DB   7                         ; GR_ALT5-GR_ALTS; top-level-declaration
    DB   8                         ; GR_ALT6-GR_ALTS; top-level-declaration
    DB   9                         ; GR_ALT7-GR_ALTS; top-level-declaration
    DB   10                        ; GR_ALT8-GR_ALTS; top-level-declaration
    DB   11                        ; GR_ALT9-GR_ALTS; const-declaration
    DB   16                        ; GR_ALT10-GR_ALTS; const-declaration-tail
    DB   21                        ; GR_ALT11-GR_ALTS; const-declaration-tail
    DB   29                        ; GR_ALT12-GR_ALTS; assert-declaration
    DB   35                        ; GR_ALT13-GR_ALTS; program-var-declaration
    DB   45                        ; GR_ALT14-GR_ALTS; program-initializer-opt
    DB   48                        ; GR_ALT15-GR_ALTS; record-declaration
    DB   57                        ; GR_ALT16-GR_ALTS; record-fields
    DB   59                        ; GR_ALT17-GR_ALTS; record-field
    DB   65                        ; GR_ALT18-GR_ALTS; forward-declaration
    DB   77                        ; GR_ALT19-GR_ALTS; sub-definition
    DB   81                        ; GR_ALT20-GR_ALTS; sub-definition-tail
    DB   91                        ; GR_ALT21-GR_ALTS; sub-definition-tail
    DB   95                        ; GR_ALT22-GR_ALTS; parameter-list
    DB   97                        ; GR_ALT23-GR_ALTS; parameter-tail
    DB   100                       ; GR_ALT24-GR_ALTS; parameter
    DB   105                       ; GR_ALT25-GR_ALTS; result-opt
    DB   109                       ; GR_ALT26-GR_ALTS; fails-opt
    DB   111                       ; GR_ALT27-GR_ALTS; routine-body
    DB   115                       ; GR_ALT28-GR_ALTS; routine-body
    DB   116                       ; GR_ALT29-GR_ALTS; local-list
    DB   118                       ; GR_ALT30-GR_ALTS; local-declaration
    DB   127                       ; GR_ALT31-GR_ALTS; local-initializer-opt
    DB   131                       ; GR_ALT32-GR_ALTS; local-initializer-opt
    DB   132                       ; GR_ALT33-GR_ALTS; statement-sequence
    DB   134                       ; GR_ALT34-GR_ALTS; statement
    DB   136                       ; GR_ALTHI-GR_ALTS
GR_ALTXH:
    DB   0                         ; GR_ALT35-GR_ALTHI; statement
    DB   2                         ; GR_ALT36-GR_ALTHI; statement
    DB   4                         ; GR_ALT37-GR_ALTHI; statement
    DB   6                         ; GR_ALT38-GR_ALTHI; statement
    DB   7                         ; GR_ALT39-GR_ALTHI; statement
    DB   8                         ; GR_ALT40-GR_ALTHI; statement
    DB   9                         ; GR_ALT41-GR_ALTHI; return-statement
    DB   12                        ; GR_ALT42-GR_ALTHI; return-value-opt
    DB   14                        ; GR_ALT43-GR_ALTHI; return-value-opt
    DB   15                        ; GR_ALT44-GR_ALTHI; fail-statement
    DB   19                        ; GR_ALT45-GR_ALTHI; name-statement-tail
    DB   20                        ; GR_ALT46-GR_ALTHI; name-statement-tail
    DB   28                        ; GR_ALT47-GR_ALTHI; transfer-statement
    DB   30                        ; GR_ALT48-GR_ALTHI; transfer-statement
    DB   32                        ; GR_ALT49-GR_ALTHI; if-statement
    DB   42                        ; GR_ALT50-GR_ALTHI; if-tail
    DB   49                        ; GR_ALT51-GR_ALTHI; if-tail
    DB   54                        ; GR_ALT52-GR_ALTHI; if-tail
    DB   55                        ; GR_ALT53-GR_ALTHI; while-statement
    DB   64                        ; GR_ALT54-GR_ALTHI; for-statement
    DB   78                        ; GR_ALT55-GR_ALTHI; for-bound
    DB   80                        ; GR_ALT56-GR_ALTHI; for-bound
    DB   82                        ; GR_ALT57-GR_ALTHI; for-step-opt
    DB   85                        ; GR_ALT58-GR_ALTHI; for-step-opt
    DB   86                        ; GR_ALT59-GR_ALTHI; type
    DB   89                        ; GR_ALT60-GR_ALTHI; type-atom
    DB   90                        ; GR_ALT61-GR_ALTHI; type-atom
    DB   92                        ; GR_ALT62-GR_ALTHI; type-atom
    DB   96                        ; GR_ALT63-GR_ALTHI; string-capacity
    DB   99                        ; GR_ALT64-GR_ALTHI; string-capacity
    DB   100                       ; GR_ALT65-GR_ALTHI; type-array-opt
    DB   106                       ; GR_ALT66-GR_ALTHI; scalar-type
    DB   108                       ; GR_ALT67-GR_ALTHI; scalar-type
    DB   110                       ; GR_ALT68-GR_ALTHI; scalar-type
    DB   112                       ; GR_ALT_E-GR_ALTHI
GR_ALTXE:                          ; End of the production directories.

; Production bodies, each right side stored right to left.

GR_ALTS:                           ; Base of the low productions' offsets.
GR_ALT0:                           ; compilation-unit
    DB   TK_EOF,$80,$41
GR_ALT1:                           ; top-level-list
    DB   $41,$42
GR_ALT2:                           ; top-level-list
GR_ALT3:                           ; top-level-declaration
    DB   $43
GR_ALT4:                           ; top-level-declaration
    DB   $45
GR_ALT5:                           ; top-level-declaration
    DB   $46
GR_ALT6:                           ; top-level-declaration
    DB   $48
GR_ALT7:                           ; top-level-declaration
    DB   $4c
GR_ALT8:                           ; top-level-declaration
    DB   $4d
GR_ALT9:                           ; const-declaration
    DB   $44,$82,TK_NAME,TK_CONST,$81
GR_ALT10:                          ; const-declaration-tail
    DB   $85,TK_EOL,$84,$83,TK_EQ
GR_ALT11:                          ; const-declaration-tail
    DB   $89,TK_EOL,$88,$87,TK_EQ,$86,$65,TK_AS
GR_ALT12:                          ; assert-declaration
    DB   $8b,TK_EOL,$83,TK_ASSRT,$8a,$81
GR_ALT13:                          ; program-var-declaration
    DB   $8d,TK_EOL,$47,$8c,$65,TK_AS,$82,TK_NAME,TK_VAR,$81
GR_ALT14:                          ; program-initializer-opt
    DB   $88,$87,TK_EQ
GR_ALT15:                          ; record-declaration
    DB   $8f,TK_EOL,TK_END,$49,TK_EOL,$8e,TK_NAME,TK_REC,$81
GR_ALT16:                          ; record-fields
    DB   $4a,$4b
GR_ALT17:                          ; record-field
    DB   $91,TK_EOL,$65,TK_AS,$90,TK_NAME
GR_ALT18:                          ; forward-declaration
    DB   $94,TK_EOL,$53,$52,TK_RPAR,$4f,TK_LPAR,$93,$92,TK_NAME,TK_SUB,TK_FORW
GR_ALT19:                          ; sub-definition
    DB   $4e,$92,TK_NAME,TK_SUB
GR_ALT20:                          ; sub-definition-tail
    DB   $97,$54,$96,TK_EOL,$53,$52,TK_RPAR,$4f,TK_LPAR,$95
GR_ALT21:                          ; sub-definition-tail
    DB   $97,$54,TK_EOL,$98
GR_ALT22:                          ; parameter-list
    DB   $50,$51
GR_ALT23:                          ; parameter-tail
    DB   $50,$51,TK_COMMA
GR_ALT24:                          ; parameter
    DB   $9a,$65,TK_AS,$99,TK_NAME
GR_ALT25:                          ; result-opt
    DB   $9c,$65,$9b,TK_AS
GR_ALT26:                          ; fails-opt
    DB   $9d,TK_FAILS
GR_ALT27:                          ; routine-body
    DB   TK_EOL,TK_END,$58,$55
GR_ALT28:                          ; routine-body
    DB   $9e
GR_ALT29:                          ; local-list
    DB   $55,$56
GR_ALT30:                          ; local-declaration
    DB   $a0,TK_EOL,$57,$9f,$65,TK_AS,$82,TK_NAME,TK_VAR
GR_ALT31:                          ; local-initializer-opt
    DB   $a3,$cb,$a1,TK_EQ
GR_ALT32:                          ; local-initializer-opt
    DB   $a4
GR_ALT33:                          ; statement-sequence
    DB   $58,$59
GR_ALT34:                          ; statement
    DB   $5d,$a5
GR_ALTHI:                          ; Base of the high productions' offsets.
GR_ALT35:                          ; statement
    DB   TK_EOL,$5a
GR_ALT36:                          ; statement
    DB   TK_EOL,$5c
GR_ALT37:                          ; statement
    DB   TK_EOL,$5e
GR_ALT38:                          ; statement
    DB   $5f
GR_ALT39:                          ; statement
    DB   $61
GR_ALT40:                          ; statement
    DB   $62
GR_ALT41:                          ; return-statement
    DB   $5b,$a6,TK_RET
GR_ALT42:                          ; return-value-opt
    DB   $a8,$a7
GR_ALT43:                          ; return-value-opt
    DB   $a9
GR_ALT44:                          ; fail-statement
    DB   $ab,$a2,$aa,TK_FAIL
GR_ALT45:                          ; name-statement-tail
    DB   TK_EOL
GR_ALT46:                          ; name-statement-tail
    DB   $ad,TK_EOL,TK_END,$58,TK_EOL,$ac,TK_NAME,TK_HANDL
GR_ALT47:                          ; transfer-statement
    DB   $ae,TK_EXIT
GR_ALT48:                          ; transfer-statement
    DB   $af,TK_CONT
GR_ALT49:                          ; if-statement
    DB   $b2,TK_EOL,TK_END,$60,$58,$b1,TK_EOL,$a2,$b0,TK_IF
GR_ALT50:                          ; if-tail
    DB   $60,$58,$b1,TK_EOL,$a2,$b3,TK_ELSIF
GR_ALT51:                          ; if-tail
    DB   $b5,$58,TK_EOL,$b4,TK_ELSE
GR_ALT52:                          ; if-tail
    DB   $b6
GR_ALT53:                          ; while-statement
    DB   $b9,TK_EOL,TK_END,$58,$b8,TK_EOL,$a2,$b7,TK_WHILE
GR_ALT54:                          ; for-statement
    DB   $bc,TK_EOL,TK_END,$58,$bb,TK_EOL,$64,$a2,$63,$a2,TK_EQ,$ba,TK_NAME,TK_FOR
GR_ALT55:                          ; for-bound
    DB   $bd,TK_TO
GR_ALT56:                          ; for-bound
    DB   $be,TK_UNTIL
GR_ALT57:                          ; for-step-opt
    DB   $c0,$bf,TK_STEP
GR_ALT58:                          ; for-step-opt
    DB   $c1
GR_ALT59:                          ; type
    DB   $ca,$68,$66
GR_ALT60:                          ; type-atom
    DB   $69
GR_ALT61:                          ; type-atom
    DB   $c2,TK_NAME
GR_ALT62:                          ; type-atom
    DB   TK_RBRAC,$67,TK_LBRAC,TK_STR
GR_ALT63:                          ; string-capacity
    DB   $c4,$83,$c3
GR_ALT64:                          ; string-capacity
    DB   $c5
GR_ALT65:                          ; type-array-opt
    DB   $68,$c6,TK_RBRAC,$83,$c3,TK_LBRAC
GR_ALT66:                          ; scalar-type
    DB   $c7,TK_U8
GR_ALT67:                          ; scalar-type
    DB   $c8,TK_U16
GR_ALT68:                          ; scalar-type
    DB   $c9,TK_BOOL
GR_ALT_E:                          ; End of the production bodies.

; Action directory: the routine for each action ordinal.

GR_ACTX:
    DW   AC_MAIN                   ; a:RequireMain
    DW   AC_EARLY                  ; a:RequireBeforeMain
    DW   AC_NAME                   ; a:RetainDeclarationName
    DW   AC_FOLD                   ; x:ConstantExpression
    DW   AC_VALUE                  ; a:FinishConstantExpression
    DW   AC_CONST                  ; a:CommitConstant
    DW   AC_ROOBJ                  ; a:SaveAggregateConstantType
    DW   AC_IMAGE                  ; x:StaticInitializer
    DW   AC_EXACT                  ; a:FinishProgramInitializer
    DW   AC_ROCMT                  ; a:CommitAggregateConstant
    DW   AC_CLAIM                  ; a:BeginAssert
    DW   AC_PROVE                  ; a:CommitAssert
    DW   AC_VAR                    ; a:SaveProgramType
    DW   AC_ALLOC                  ; a:CommitProgramVariable
    DW   AC_REC                    ; a:BeginRecord
    DW   AC_RECOK                  ; a:CommitRecord
    DW   AC_FIELD                  ; a:BeginRecordField
    DW   AC_PLACE                  ; a:CommitRecordField
    DW   AC_SUB                    ; a:RetainSubName
    DW   AC_PROTO                  ; a:BeginForward
    DW   AC_SEAL                   ; a:CommitForward
    DW   AC_SIG                    ; a:BeginSub
    DW   AC_BODY                   ; a:BeginSubBody
    DW   AC_END                    ; a:EndSub
    DW   AC_IMPL                   ; a:BeginForwardBody
    DW   AC_PARAM                  ; a:RetainParameter
    DW   AC_JOIN                   ; a:CommitParameter
    DW   AC_GIVES                  ; a:AllowSubResult
    DW   AC_GIVEN                  ; a:SaveSubResult
    DW   AC_FAILS                  ; a:MarkSubFails
    DW   AC_STRAY                  ; x:StrayClause
    DW   AC_LOCAL                  ; a:SaveLocalType
    DW   AC_BIND                   ; a:CommitLocal
    DW   AC_INIT                   ; a:BeginLocalInitializer
    DW   AC_EXPR                   ; x:RuntimeExpression
    DW   AC_ADOPT                  ; a:FinishLocalInitializer
    DW   AC_ZERO                   ; a:DefaultLocalInitializer
    DW   AC_STMT                   ; x:NameStatement
    DW   AC_RET                    ; a:BeginReturnValue
    DW   AC_YIELD                  ; x:ReturnValue
    DW   AC_RETOP                  ; a:CommitReturn
    DW   AC_BARE                   ; a:CommitBareReturn
    DW   AC_FAIL                   ; a:BeginFail
    DW   AC_THROW                  ; a:CommitFail
    DW   AC_ONERR                  ; a:BeginHandle
    DW   AC_NOERR                  ; a:EndHandle
    DW   AC_GOTO                   ; a:EmitExit, parameter 45
    DW   AC_GOTO                   ; a:EmitContinue, parameter 46
    DW   AC_IF                     ; a:BeginIf
    DW   AC_THEN                   ; a:BeginIfBody
    DW   AC_ENDIF                  ; a:EndIf
    DW   AC_ELIF                   ; a:BeginElseIf
    DW   AC_ELSE                   ; a:BeginElse
    DW   AC_TOTAL                  ; a:FinishElse
    DW   AC_PART                   ; a:FinishIfClauses
    DW   AC_WHILE                  ; a:BeginWhile
    DW   AC_DO                     ; a:BeginWhileBody
    DW   AC_LOOP                   ; a:EndWhile
    DW   AC_FOR                    ; a:BeginFor
    DW   AC_FORDO                  ; a:BeginForBody
    DW   AC_NEXT                   ; a:EndFor
    DW   AC_FORTO                  ; a:ForTo, parameter 1
    DW   AC_FORTO                  ; a:ForUntil, parameter 0
    DW   AC_BY                     ; x:StepConstant
    DW   AC_STEP                   ; a:SaveForStep
    DW   AC_BYONE                  ; a:DefaultForStep
    DW   AC_NAMED                  ; a:ResolveRecordType
    DW   AC_IDLE                   ; a:BeginTypeBound
    DW   AC_STR                    ; a:MakeStringType
    DW   AC_OPEN                   ; a:MakeOpenStringType
    DW   AC_DIM                    ; a:SaveArrayBound
    DW   AC_TYPE                   ; a:TypeU8, parameter 1
    DW   AC_TYPE                   ; a:TypeU16, parameter 2
    DW   AC_TYPE                   ; a:TypeBoolean, parameter 3
    DW   AC_ARRAY                  ; a:MakeArrayTypes
    DW   AC_LINIT                  ; x:LocalInitializer
GR_ACTXE:                          ; End of the action directory.

GR_TAB_E:                          ; End of the generated tables (marker).

GR_END:                            ; End of the grammar tables (marker).
