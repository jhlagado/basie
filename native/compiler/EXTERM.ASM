;==========================================================================
;  Expression primaries and unary operators
;==========================================================================
;
;  The second of the expression parser's three files (EXPR.ASM describes
;  the module, its result convention and its operand stack). Parse the
;  operands of the binary operators: literals, names, parenthesized
;  expressions, conversions and the unary signs, folding constants and
;  generating the code of the rest (GENEXPR.ASM).
;
;  Principal entries:
;    EX_TERM   parse one primary
;    EX_LIT    return a literal as a known result
;    EX_LITK   return EX_KVAL as a known result
;    EX_CAST   parse a conversion's parenthesized operand
;    EX_INT    require an integer result
;    EX_UNARY  parse a primary preceded by any signs

;@ROUTINE OUT A,HL,CARRY CLOBBERS SIGN,PARITY,HALFCARRY,ZERO,BC,DE,IX,IY
; Parse one primary: a number, character, `true` or `false`, a name, a
; parenthesized expression or a conversion, a type's name and its
; parenthesized operand. Any other token raises DG_VALUE. A primary
; parsed already (EX_PRIME, a computed scalar of that type) is returned
; instead, once. EX_CHR records whether the primaries so far are one
; character literal (1), which an inferred local takes as a u8, as the
; reference's char flag does.

EX_TERM:
    LD   HL,EX_PRIME               ; A primary parsed already
    LD   A,(HL)                    ; is the first operand,
    LD   (HL),0                    ; once:
    OR   A                         ; its type, computed,
    RET  NZ                        ; with carry clear.
    CALL PR_TAKE                   ; Consume the token; BC is its value.
    LD   E,A                       ; Keep its kind.
    CP   TK_LPAR                   ; A parenthesis is no primary
    JR   Z,.KIND                   ; of its own.
    LD   HL,EX_CHR                 ; Is this the first primary
    SUB  TK_CHAR                   ; and a character?
    OR   (HL)                      ; Zero only then:
    LD   (HL),2                    ; otherwise more than one, or not one;
    JR   NZ,.KIND                  ; a lone character
    DEC  (HL)                      ; is one.
.KIND:                         ; E is the token's kind.
    LD   A,E                       ; Restore it.
    CP   TK_NUM                    ; A number?
    JR   Z,.NUMBER                 ; An exact literal.
    CP   TK_CHAR                   ; A character?
    JR   Z,.CHAR                   ; A u8 literal.
    CP   TK_TRUE                   ; `true`?
    JR   Z,.TRUE                   ; A Boolean literal.
    CP   TK_FALSE                  ; `false`?
    JR   Z,.FALSE                  ; A Boolean literal.
    CP   TK_NAME                   ; A name?
    JR   Z,EX_NAME                 ; Resolve it.
    CP   TK_LPAR                   ; A parenthesis?
    JP   Z,EX_PAREN                ; Parse the enclosed expression.
    CP   TK_TYPE                   ; A type's name?
    JP   Z,EX_CONV                 ; A conversion, C the type.
    JP   PR_ETERM                  ; Anything else: a value was expected.
.NUMBER:                       ; BC and TK_NHI are the number's value.
    LD   H,B                       ; Its low word
    LD   L,C                       ; in HL,
    LD   A,(TK_WIDE)               ; a known value of no type yet,
    OR   SY_KNOWN                  ; or an f32's bits
    LD   B,A                       ; (TK_WIDE SY_F32),
    CALL EX_LIT                    ; with a zero high word,
    LD   HL,(TK_NHI)               ; but for
    LD   (EX_KVAL+2),HL            ; the token's.
    JR   EX_LITK                   ; Return it.
.CHAR:                         ; C is the character code.
    LD   H,0                       ; A byte value,
    LD   L,C                       ; exact like a number (spec 9.7).
    LD   B,SY_KNOWN+SY_EXACT       ; A known value of no type yet.
    JR   EX_LIT                    ; Return it.
.TRUE:                         ; `true` is one.
    LD   HL,1                      ; Form one.
    JR   .BOOL                     ; A known Boolean.
.FALSE:                        ; `false` is zero.
    LD   HL,0                      ; Form zero.
.BOOL:                         ; HL is a Boolean value.
    LD   B,SY_KNOWN+SY_BOOL        ; A known Boolean; fall into EX_LIT.

;@ROUTINE IN B,HL OUT A,HL,CARRY CLOBBERS SIGN,PARITY,HALFCARRY,ZERO
; Return the known value HL, a word from 0 to 65535, with metadata B: it
; is EX_KVAL, its high bytes zero. A constant generates no code until
; something needs it in the registers (GX_TOREG and the operator
; templates), as in the reference compiler. BC and DE are preserved.

EX_LIT:
    LD   (EX_KVAL),HL              ; The low word,
    PUSH HL                        ; kept,
    LD   HL,0                      ; and zero
    LD   (EX_KVAL+2),HL            ; above it,
    LD   A,H                       ; three
    LD   (EX_KVAL+4),A             ; bytes.
    POP  HL                        ; HL is the value; fall into EX_LITK.

;@ROUTINE IN B OUT A,HL,CARRY CLOBBERS SIGN,PARITY,HALFCARRY,ZERO
; Return the known value in EX_KVAL with metadata B, its low word in HL.
; BC and DE are preserved.

EX_LITK:
    LD   HL,(EX_KVAL)              ; The low word.
    LD   A,B                       ; The metadata.
    OR   A                         ; Clear carry for success.
    RET                            ; Return the known result.

; Resolve a NAME primary, already consumed: a predeclared constant (exact,
; as the reference's are; console and printer are Files, no scalar values:
; DG_CLASH) or a call to a service, a routine call, an aggregate object
; path, a scalar constant (emitted as a literal) or a scalar variable
; (emitted as a load).

EX_NAME:
    CALL RO_LIB                    ; A predeclared name?
    JR   NC,.ORDINARY              ; No: an ordinary name.
    JP   M,.PREDEF                 ; A constant: its value.
    OR   A                         ; A service without a result
    JP   Z,RO_EVOID                ; has no value (no-value).
    CALL RO_SVC                    ; A service: call it;
    JP   RO_VALUE                  ; its result is the value.
.PREDEF:                       ; A is SY_KNOWN and the constant's type.
    LD   B,A                       ; Its metadata:
    CP   SY_KNOWN+SY_EXACT         ; a File
    JP   NZ,EX_ETYPE               ; is no scalar value (DG_CLASH).
    INC  HL                        ; Its value,
    LD   L,(HL)                    ; a byte,
    LD   H,0                       ; widened.
    JR   EX_LIT                    ; Return it.
.ORDINARY:                     ; A routine or an ordinary symbol.
    CALL RO_FIND                   ; Is it a routine?
    JP   Z,RO_FUNC                 ; Yes: parse a call for its result.
    CALL SY_GET                    ; Fetch class/type and payload, or fail.
    LD   D,A                       ; Keep the symbol info.
    AND  SY_AGGR                   ; An aggregate?
    JP   NZ,RO_OBJ                 ; Yes: parse its field or element path.
    LD   A,D                       ; A scalar: D is its info, BC its payload.
    CALL EX_CLASS                  ; Reject a type name; zero for a constant.
    JR   Z,.CONST                  ; A constant folds to a literal.
    LD   A,D                       ; Recover the symbol info.
    AND  SY_TMASK                  ; Keep the type.
    LD   E,A                       ; E is the variable's type.
    LD   A,D                       ; Recover the symbol info.
    AND  SY_CMASK                  ; Keep the storage class.
    SUB  SY_GLOB                   ; A program variable?
    LD   (RO_ESC),A                ; Nonzero when it is in the frame.
    LD   A,E                       ; Its type.
    PUSH DE                        ; Keep it.
    JR   Z,.GLOBAL                 ; A program variable loads by address.
    LD   H,B                       ; A local or parameter:
    LD   L,C                       ; HL is its offset from IX.
    CALL GX_FLOAD                  ; Load it into the registers.
    JR   .LOADED                   ; Return its type.
.GLOBAL:                       ; A program variable, blob BC.
    CALL GX_LOAD                   ; Load it into the registers.
.LOADED:                       ; The value is in the registers.
    POP  DE                        ; Recover the type.
    LD   A,E                       ; A run-time result of that type.
    OR   A                         ; Clear carry for success.
    RET                            ; Return it.
.CONST:                        ; A scalar constant: BC its value's low word,
    LD   (EX_KVAL),BC              ; and HL its record's payload, whose
    INC  HL                        ; high bytes follow it
    PUSH DE                        ; (the info kept)
    LD   DE,EX_KVAL+2              ; in the record
    LD   BC,3                      ; (SY_VHI).
    LDIR                           ; The value is EX_KVAL.
    POP  BC                        ; B is the constant's type,
    SET  7,B                       ; known (SY_KNOWN).
    JR   EX_LITK                   ; Return it.

;@ROUTINE OUT A,HL,CARRY CLOBBERS SIGN,PARITY,HALFCARRY,ZERO,BC,DE,IX,IY
; Parse a parenthesized expression after its '(' and require the ')'.

EX_PAREN:
    CALL EX_INNER                  ; Parse the enclosed expression.
    JR   EX_RPAR                   ; Require the closing parenthesis.

;@ROUTINE OUT A,HL,CARRY CLOBBERS SIGN,PARITY,HALFCARRY,ZERO,BC,DE,IX,IY
; Parse the parenthesized operand of an explicit conversion, with no type
; expected inside it, as the reference parses it. The enclosing expected
; type is restored before returning the operand in A/HL.

EX_CAST:
    CALL PR_LEFT                   ; Require the opening parenthesis.
    XOR  A                         ; Nothing is expected inside the conversion.
    CALL EX_SUB                    ; Parse the operand; the type is restored.

;@ROUTINE IN A,HL OUT A,HL,CARRY CLOBBERS SIGN,PARITY,HALFCARRY,ZERO,BC,DE
; Require the closing parenthesis after the operand A/HL, and return the
; operand with its flags as they came.

EX_RPAR:                       ; A/HL is the operand.
    PUSH AF                        ; Save its metadata and flags,
    PUSH HL                        ; and its value.
    CALL PR_RIGHT                  ; Require the closing parenthesis.
    POP  HL                        ; Recover the value.
    POP  AF                        ; Recover the metadata.
    RET                            ; Return the operand.

;@ROUTINE IN C OUT A,HL,CARRY CLOBBERS SIGN,PARITY,HALFCARRY,ZERO,BC,DE,IX,IY
; Parse a conversion to type C, its type's name read (conversion): its
; operand, a number, is parenthesized. There is no conversion to Boolean,
; nor from one (conversion-unavailable, at the parenthesis). A known
; operand becomes an f32 rounded to nearest (OV_ITOF), or an integer
; truncated from an f32 (OV_FTOI), and must fit the type (narrowing, at
; the parenthesis); a computed one widens to the type (GX_WIDEN), or
; narrows with a check (GX_TRIM), an f32's through the runtime.

EX_CONV:                       ; C is the target type.
    PUSH BC                        ; Keep the target.
    CALL PR_SPOT                   ; The parenthesis's offset,
    PUSH HL                        ; where the conversion's faults are.
    CALL EX_CAST                   ; The operand: A and HL.
    POP  HL                        ; The parenthesis.
    POP  BC                        ; C is the target.
    LD   D,A                       ; D is the operand's metadata.
    LD   A,C                       ; There is
    CP   SY_BOOL                   ; no conversion
    JR   Z,.NONE                   ; to Boolean,
    CALL EX_DBOOL                  ; nor from one.
    JR   Z,.NONE                   ; (conversion-unavailable)
    BIT  7,D                       ; A known operand?
    JR   Z,.COMPUTED               ; No: converted at run time.
    PUSH HL                        ; Keep the parenthesis.
    PUSH BC                        ; (and the target)
    LD   HL,EX_KVAL                ; The value:
    LD   A,D                       ; from
    AND  SY_TMASK                  ; an f32
    CP   SY_F32                    ; to an integer
    JR   NZ,.FROMINT               ; it is truncated,
    LD   A,C                       ; to an f32
    CP   SY_F32                    ; kept;
    CALL NZ,OV_FTOI                ; (Math.trunc)
    JR   .FIT                      ; then checked.
.FROMINT:                      ; From an integer: to an f32
    LD   A,C                       ; it is rounded
    CP   SY_F32                    ; to nearest,
    CALL Z,OV_ITOF                 ; (Math.fround) which fits.
.FIT:                          ; EX_KVAL is the value at the type.
    POP  BC                        ; The target.
    LD   A,C                       ; The value
    LD   HL,EX_KVAL                ; must fit
    CALL VL_FITS                   ; the type (the target kept),
    POP  HL                        ; (the parenthesis)
    LD   A,DG_TRUNC                ; else narrowing,
    JP   C,DG_HERE                 ; at the parenthesis.
    LD   B,C                       ; The same value,
    SET  7,B                       ; known, of the type.
    JP   EX_LITK                   ; Return it.
.COMPUTED:                     ; A computed operand of type A.
    PUSH BC                        ; Keep the target.
    LD   E,C                       ; From its type
    LD   D,A                       ; to the target:
    CP   E                         ; the same?
    JR   Z,.DONE                   ; Nothing to do.
    CALL EX_WIDEN                  ; A widening?
    JR   NC,.NARROW                ; No: a checked narrowing.
    CALL GX_WIDEN                  ; Widen it.
    JR   .DONE                     ; Converted.
.NARROW:                       ; D does not widen to E.
    CALL GX_TRIM                   ; Narrow it, checked.
.DONE:                         ; The value is converted.
    POP  BC                        ; C is the target,
    LD   A,C                       ; a run-time result.
    OR   A                         ; Clear carry.
    RET                            ; Return it.
.NONE:                         ; A Boolean on either side:
    LD   A,DG_NOCVT                ; conversion-unavailable,
    JP   DG_HERE                   ; at the parenthesis.

;@ROUTINE IN A OUT A,D,CARRY CLOBBERS SIGN,PARITY,HALFCARRY,ZERO
; Require result metadata A to be an integer; a Boolean raises DG_CLASH.
; Returns the metadata in A and D with carry clear.

EX_INT:
    LD   D,A                       ; Keep the metadata.
    CALL EX_TBOOL                  ; Is its type Boolean?
    JP   Z,EX_ETYPE                ; Yes: an integer is required.
    LD   A,D                       ; Recover the metadata.
    OR   A                         ; Clear carry.
    RET                            ; Return it.

;@ROUTINE OUT A,HL,CARRY CLOBBERS SIGN,PARITY,HALFCARRY,ZERO,BC,DE,IX,IY
; Parse a unary expression: a primary preceded by any number of signs,
; or the primary parsed already (EX_PRIME). Unary + and - bind above the
; multiplicative operators.

EX_UNARY:
    LD   A,(EX_PRIME)              ; A primary parsed already
    OR   A                         ; takes no sign:
    JR   NZ,.TERM                  ; it is the operand.
    CALL PR_PEEK                   ; Look at the next token.
    CP   TK_PLUS                   ; A unary plus?
    JR   Z,EX_PLUS                 ; Parse its operand.
    CP   TK_MINUS                  ; A unary minus?
    JR   Z,EX_MINUS                ; Parse and negate its operand.
.TERM:                         ; No sign, or the primary parsed.
    JP   EX_TERM                   ; Otherwise parse a primary.

;@ROUTINE OUT A,HL,CARRY CLOBBERS SIGN,PARITY,HALFCARRY,ZERO,BC,DE,IX,IY
; Consume a sign and parse its integer operand, which unary plus returns
; unchanged. EX_MINUS uses it to parse its own operand.

EX_PLUS:
    CALL PR_TAKE                   ; Consume the sign.
    CALL EX_UNARY                  ; Parse its operand, signs included.
    JR   EX_INT                    ; It must be an integer; return it.

;@ROUTINE OUT A,HL,CARRY CLOBBERS SIGN,PARITY,HALFCARRY,ZERO,BC,DE,IX,IY
; Parse unary minus (negate): an exact operand is negated exactly, and
; stays exact until its context types it; a typed known one is negated
; and wrapped at its type, an f32 by its sign bit; a computed one is
; negated in the registers (GX_NEG).

EX_MINUS:
    CALL EX_PLUS                   ; Consume '-' and parse the operand.
    BIT  7,A                       ; SY_KNOWN: is it known?
    JR   NZ,.FOLD                  ; Yes: fold it.
    LD   D,A                       ; Its type
    PUSH DE                        ; is kept,
    CALL GX_NEG                    ; and the value negated.
    POP  AF                        ; A run-time result
    OR   A                         ; of its type; carry clear.
    RET                            ; Return it.
.FOLD:                         ; EX_KVAL is the known value.
    LD   B,A                       ; An f32's
    AND  SY_TMASK                  ; sign
    CP   SY_F32                    ; bit
    LD   A,B                       ; (the metadata)
    JR   NZ,.WHOLE                 ; flips,
    LD   HL,EX_KVAL+3              ; zero
    LD   A,(HL)                    ; becoming
    XOR  $80                       ; -0,
    LD   (HL),A                    ; as the reference's
    JP   EX_LITK                   ; does; return it.
.WHOLE:                        ; An integer.
    PUSH AF                        ; Keep the metadata.
    LD   HL,EX_KVAL                ; The value
    CALL VL_NEG                    ; negated.
    POP  BC                        ; B is the metadata,
    LD   A,B                       ; its type
    AND  SY_TMASK                  ; alone:
    LD   C,A                       ; exact or typed,
    JP   NZ,EX_FOLD                ; a typed one wrapped; return.
    JP   EX_LITK                   ; An exact one as it is.
