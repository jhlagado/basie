;==========================================================================
;  Grammar actions: types and declarations
;==========================================================================
;
;  The semantic actions of the grammar. The LL(1) engine calls one when it
;  pops an action symbol, through GR_ACTX, with the action's ordinal in A
;  (LL1.ASM). Actions never choose productions. They check what has just
;  been parsed, record it in the symbol, type and routine tables, generate
;  its code or write its blob (GENCALL.ASM), and at the grammar's islands
;  (x: in GR_ACTX) hand over to a hand-written parser for an expression,
;  an initializer, a for step or a name statement. An action reports an
;  error through DG_ISSUE, which abandons the build, so actions return
;  only on success and the engine ignores their flags.
;
;  The actions are in three files, consecutive in BASIE.ASM:
;    ACTIONS.ASM  islands, types, constants, assertions and program
;                 variables; a record's declaration is in the OWNERS
;                 overlay (OWNERS.ASM), reached through POOLS.ASM
;    ACTSUB.ASM   routines and main, failure and handlers
;    ACTSTMT.ASM  locals, statements, structured flow and the for loop
;
;  Principal entries here, in GR_ACTX order of use:
;    AC_FOLD, AC_EXPR, AC_IMAGE, AC_BY  islands: constant expression,
;              run-time expression, static initializer, for step
;    AC_TYPE, AC_NAMED, AC_STR, AC_OPEN  set the current type
;    AC_DIM, AC_ARRAY  keep array bounds, then build the arrays from them
;    AC_VALUE, AC_CONST  scalar constant declarations
;    AC_ROOBJ, AC_ROCMT  aggregate constant declarations
;    AC_PROVE  compile-time assertions
;    AC_VAR, AC_EXACT, AC_ALLOC  program variable declarations
;
;  A declaration's name is retained (AC_NAME, EX_KEEP: spelling in AC_DNAME,
;  position in AC_DPOS) while the rest is parsed; its class and type build
;  up in AC_DINFO and its payload in AC_DVAL. EX_PREP then writes the
;  symbol provisionally and SY_CMT or SY_TAG commits it, so a declaration
;  cannot refer to itself. The current type is AG_CTYPE: 1..8 for the
;  scalars, a type-table ID from AG_FIRST, or AG_VIEW for `string[]`.
;
;  Workspace. The for loop's scratch below overlays the first seven bytes
;  of AG_IBUF, the initializer staging buffer, which holds a declaration's
;  static initializer only from its parse to its commit, and a for loop's
;  header is never inside one. It is laid out as a for frame's fields from
;  CT_FMODE, to which AC_FORDO copies it.

AC_NONE EQU  $FF               ; EX_RMETA of a local without an initializer.
AC_STAGE EQU  $FE              ; EX_RMETA of an aggregate local's static initializer.
AC_LCOPY EQU  $FD              ; EX_RMETA of an aggregate local copied from a source.
AC_LFILE EQU  $FC              ; EX_RMETA of a File local, its value in DEHL.
AC_LHND EQU  $FB               ; EX_RMETA of a handle local, its value in HL.
AC_MODE EQU  AG_IBUF           ; Byte: the for loop's mode (CT_MINC...).
AC_INDEX EQU  AC_MODE+1        ; Word: the counter's offset from IX.
AC_BOUND EQU  AC_INDEX+2       ; Word: the bound's offset from IX.
AC_DELTA EQU  AC_BOUND+2       ; Four bytes: the step's magnitude.
AC_WEND EQU  AC_DELTA+4        ; End of the for loop's scratch, which its frame copies.
AC_RVAL EQU  AC_WEND           ; Eight bytes: a select label's low and high values.
AC_RWID EQU  AC_RVAL+8         ; Byte: their width in the log, two or four.

; --------------------------------------------------------------- islands

;@ROUTINE OUT A,HL,CARRY,ZERO CLOBBERS SIGN,PARITY,HALFCARRY,BC,DE,IX,IY
; Island ConstantExpression: parse an expression that must fold to a
; constant, without emitting it. The result is left in EX_RMETA/EX_RVAL.

AC_FOLD:
    LD   A,SY_EXACT                ; Expect an untyped exact value.
    CALL EX_CONST                  ; Parse with emission off: A metadata, HL value.
    JP   EX_STASH                  ; Keep the result for the next action.

;@ROUTINE OUT A,HL,CARRY,ZERO CLOBBERS SIGN,PARITY,HALFCARRY,BC,DE,IX,IY
; Island RuntimeExpression: parse an expression of the type in EX_WANT,
; emitting its operations, and leave its result in EX_RMETA/EX_RVAL.

AC_EXPR:
    LD   A,(EX_WANT)               ; The type the preceding action expects.
    CALL EX_RUN                    ; Parse and emit: A metadata, HL value if known.
    JP   EX_STASH                  ; Keep it for the action that checks it.

;@ROUTINE OUT A,B,DE CLOBBERS CARRY,ZERO,SIGN,PARITY,HALFCARRY,C,HL
; Island StepConstant: parse a for loop's step (CT_STEP), adding its
; direction bit, CT_MDOWN, to AC_MODE and keeping its magnitude in
; AC_DELTA.

AC_BY:
    CALL CT_STEP                   ; B is the direction bit, HLDE the magnitude.
    LD   A,(AC_MODE)               ; The mode so far (the bound's kind).
    OR   B                         ; Add the downward bit.
    LD   (AC_MODE),A               ; Keep the complete mode.
    LD   (AC_DELTA),DE             ; Keep the step,
    LD   (AC_DELTA+2),HL           ; four bytes.
    RET                            ; Back to the engine.

;@ROUTINE OUT A CLOBBERS CARRY,ZERO,SIGN,PARITY,HALFCARRY,BC,DE,HL,IX,IY
; Island StaticInitializer: parse the initializer of the object being
; declared, whose type is in AC_DINFO (AG_PARSE): staged, zeroed first, up
; to 1K; streamed into its blob, at top level, below 16K (AG_ZERO). AC_DINFO
; is preserved across the parse. A File's initializer is not yet compiled (DG_NYI).

AC_IMAGE:
    LD   A,(AC_DINFO)              ; The object's type ID.
    CP   AG_FILE                   ; A File's
    JP   Z,TR_OPER                 ; is refused for now.
    CALL AG_ZERO                   ; The staging, zeroed;
    LD   A,(AC_DINFO)              ; the type again.
    PUSH AF                        ; Keep it: AG_PARSE may reuse AC_DINFO.
    CALL AG_PARSE                  ; Stage the initializer for type A.
    POP  AF                        ; Restore the type ID...
    LD   (AC_DINFO),A              ; ...for AC_EXACT and AC_ALLOC.
    RET                            ; Back to the engine.

;@ROUTINE NORETURN
; Island StrayClause: a routine body begins with else or elseif, which
; belongs to no if: a statement was expected, as the reference says.

AC_STRAY:
    CALL DG_RAISE                  ; Abandon the build.
    DB   DG_STMT                   ; Expected a statement.

; ----------------------------------------------------------------- types

;@ROUTINE OUT A
; TypeScalar: the type keyword just matched, its type ID the token's
; payload (PR_LVAL, KEYWORDS.ASM), is the current type.

AC_TYPE:
    LD   A,(PR_LVAL)               ; The keyword's type ID; fall into AC_USE.

;@ROUTINE IN A OUT A
; Make type ID A the current type.

AC_USE:
    LD   (AG_CTYPE),A              ; The type the declaration will use.
    RET                            ; Back to the engine.

;@ROUTINE OUT A,BC CLOBBERS CARRY,ZERO,SIGN,PARITY,HALFCARRY,DE,HL
; ResolveRecordType: the current NAME must be `id` and a pool, a pool,
; File (services 2), which is no symbol, as the reference's parseType has
; it, or a record type, which becomes the current type. Anything else raises DG_BOUND. AC_DINFO and
; AC_DVAL receive a record type's symbol information.

AC_NAMED:
    CALL PL_TYPE                   ; A pool's handle, or `id P`?
    RET  C                         ; Then it is the current type.
    LD   HL,KW_FILE                ; The spelling "File",
    LD   B,4                       ; four bytes:
    CALL TK_MATCH                  ; is the name the File type?
    LD   A,AG_FILE                 ; Then File
    JR   C,AC_USE                  ; is the current type.
    CALL AC_FIND                   ; Its class and type, its payload the type ID, recorded.
    AND  SY_TYPE+SY_AGGR           ; Keep the type-name and aggregate flags.
    CP   SY_TYPE                   ; A type name, not an aggregate object?
    LD   A,DG_CLASS                ; No: wrong-class,
    JP   NZ,DG_NAMED               ; naming it.
    LD   A,C                       ; The record's type ID.
    JR   AC_USE                    ; Make it current.

;@ROUTINE OUT A,HL,CARRY,ZERO CLOBBERS SIGN,PARITY,HALFCARRY,BC,DE
; Return in HL the constant bound just parsed: it must be known
; (not-constant), fit a u16 and be nonzero (out-of-range), each reported
; at the bound.

AC_COUNT:
    CALL AC_CNT0                   ; The bound, HL:
    LD   A,H                       ; is it zero?
    OR   L                         ; Test both bytes.
    JP   Z,AG_EBND                 ; A zero bound is out of range.
    RET                            ; HL is the bound.

;@ROUTINE OUT A,HL CLOBBERS CARRY,ZERO,SIGN,PARITY,HALFCARRY,BC,DE,IX,IY
; AC_COUNT without the zero bound's check: HL is a known constant that
; fits a u16 (not-constant, or out-of-range by EX_FITS, at the bound).

AC_CNT0:
    CALL EX_RTOK                   ; The bound: A its metadata, HL its value.
    AND  SY_KNOWN                  ; Was it folded to a constant?
    LD   A,DG_KNOWN                ; No: not-constant,
    JP   Z,AG_EVAL                 ; at the bound.
    LD   E,SY_U16                  ; It must fit a u16.
    LD   A,D                       ; Recover the metadata.
    JP   EX_FITS                   ; Check the value against u16; return.

;@ROUTINE OUT A CLOBBERS CARRY,ZERO,SIGN,PARITY,HALFCARRY,BC,DE,HL
; MakeStringType: `string[N]`. N must be 1 to 253, else out-of-range at
; the type's first token, `string`, as the reference reports it. The
; string type of capacity N, N+2 bytes, becomes the current type, shared
; with an identical one already declared.

AC_STR:
    CALL AC_CNT0                   ; HL is the capacity N:
    DEC  HL                        ; N less one
    LD   A,H                       ; must be
    OR   A                         ; below
    JR   NZ,AC_ERNG                ; 253,
    LD   A,L                       ; as the length
    CP   253                       ; byte counts
    JR   NC,AC_ERNG                ; N+1 bytes.
    INC  HL                        ; N again.
    LD   A,L                       ; The capacity.
    LD   (AG_NAUX),A               ; The candidate's capacity byte, A.
    LD   (AG_NDIM),HL              ; And its capacity word.
    LD   A,AG_KSTR                 ; A bounded string.
    LD   (AG_NKIND),A              ; The candidate's kind.
    INC  HL                        ; Add the length byte...
    INC  HL                        ; ...and the terminator.
    LD   (AG_NSIZE),HL             ; The candidate's extent.
    JR   AC_REUSE                  ; Interned and current; return.

;@ROUTINE NORETURN
; A string's capacity, or an array's extent past 64K, is out-of-range at
; the type's first token (AG_TPOS), as the reference reports both.

AC_ERNG:                       ; Out of range,
    LD   A,DG_RANGE                ; at the type's
    LD   HL,AG_TPOS                ; first token.
    JP   DG_AT                     ; No return.

;@ROUTINE OUT A CLOBBERS CARRY,ZERO,SIGN,PARITY,HALFCARRY,BC,DE,HL
; Intern the candidate descriptor and make it the current type.

AC_REUSE:
    CALL AG_REUSE                  ; A is the type's ID, new or shared.
    JR   AC_USE                    ; Make it current.

;@ROUTINE OUT A
; MakeOpenStringType: `string[]`, a parameter-only view of a string of any
; capacity rather than a type with its own descriptor.

AC_OPEN:
    LD   A,AG_VIEW                 ; The open-string view.
    JR   AC_USE                    ; Make it current.

;@ROUTINE OUT A,CARRY,ZERO CLOBBERS SIGN,PARITY,HALFCARRY,HL
; BeginType: keep the offset of the type's first token (AG_TPOS), where a
; view out of place or an open dimension inside is reported.

AC_TYPE0:
    LD   HL,(TK_POS)               ; The type's first token,
    LD   (AG_TPOS),HL              ; kept.
    RET                            ; Back to the engine.

;@ROUTINE OUT A,CARRY,ZERO CLOBBERS SIGN,PARITY,HALFCARRY,HL
; MakeOpenArrayType: `[]`, the outermost dimension open (AG_OPENF), the
; type an open array of what the dimensions after it make (parseType).
; One after a bound is syntax at the type's start; a second, an expression
; expected at its `]`.

AC_OPENA:
    LD   A,(AG_DCNT)               ; A bound before it?
    OR   A                         ; Then it is not
    JR   NZ,.INNER                 ; the outermost.
    LD   HL,AG_OPENF               ; Open
    OR   (HL)                      ; already?
    JR   NZ,.TWICE                 ; A bound was expected.
    INC  (HL)                      ; Open now.
    RET                            ; Back to the engine.
.INNER:                        ; Only the outermost may be open:
    LD   A,DG_TYPE                 ; syntax,
    LD   HL,AG_TPOS                ; at the type.
    JP   DG_AT                     ; No return.
.TWICE:                        ; `[]` again:
    CALL DG_RAISE                  ; an expression
    DB   DG_VALUE                  ; expected, at the `]`.

;@ROUTINE OUT A,CARRY,ZERO CLOBBERS SIGN,PARITY,HALFCARRY,BC,DE,HL
; SaveArrayBound: keep an array dimension's bound (AC_COUNT) until the
; type is complete; at most AG_DCAP (DG_BOUND).

AC_DIM:
    CALL AC_COUNT                  ; HL is the bound.
    EX   DE,HL                     ; Keep it in DE.
    LD   HL,AG_DCNT                ; The bounds waiting:
    LD   A,(HL)                    ; is there room
    CP   AG_DCAP                   ; for another?
    JP   NC,AG_EMETA               ; No: the capacity of a type.
    INC  (HL)                      ; Count it.
    ADD  A,A                       ; Its word
    ADD  A,AG_DSTK-AG_DCNT         ; in the stack
    LD   C,A                       ; of bounds,
    LD   B,0                       ; on from
    ADD  HL,BC                     ; AG_DCNT.
    LD   (HL),E                    ; The bound goes
    INC  HL                        ; there.
    LD   (HL),D                    ; Both bytes.
    RET                            ; Back to the engine.

;@ROUTINE OUT A,CARRY,ZERO CLOBBERS SIGN,PARITY,HALFCARRY,BC,DE,HL
; MakeArrayTypes: once a type's dimensions are parsed, build its arrays
; from the innermost, the last bound kept, out (parseType): each an array
; of its bound's elements of the current type, interned and made current.
; The element may not be a view (DG_CLASH); the
; extent must fit 64K (out-of-range). Then an open outermost
; dimension makes the type an open array of them, AG_OPEN plus the
; element's ID. Nothing is done without dimensions.

AC_ARRAY:
    LD   HL,AG_DCNT                ; Any bounds
    LD   A,(HL)                    ; waiting?
    OR   A                         ; None:
    JR   Z,.OPEN                   ; perhaps an open array.
    DEC  (HL)                      ; The last one is used:
    DEC  A                         ; its index,
    ADD  A,A                       ; and its word
    ADD  A,AG_DSTK-AG_DCNT         ; in the stack
    LD   E,A                       ; of bounds,
    LD   D,0                       ; on from
    ADD  HL,DE                     ; AG_DCNT:
    LD   C,(HL)                    ; BC is
    INC  HL                        ; the
    LD   B,(HL)                    ; count.
    LD   (AG_NDIM),BC              ; The candidate's count.
    CALL AC_ITEM                   ; The element type, A.
    LD   (AG_NAUX),A               ; The candidate's element type.
    CALL AG_SIZE                   ; HL is one element's extent.
    LD   D,H                       ; Keep it...
    LD   E,L                       ; ...in DE.
    LD   HL,0                      ; Sum the extent from zero.
.SIZELOOP:                     ; Add one element per iteration.
    ADD  HL,DE                     ; One more element.
    JR   C,AC_ERNG                 ; Past 64K: out of range, at the type.
    DEC  BC                        ; One element fewer to add.
    LD   A,B                       ; Any left?
    OR   C                         ; Test both bytes.
    JR   NZ,.SIZELOOP              ; Add the next.
    LD   (AG_NSIZE),HL             ; The candidate's extent.
    LD   A,AG_KARR                 ; An array.
    LD   (AG_NKIND),A              ; The candidate's kind.
    CALL AC_REUSE                  ; Intern it and make it current.
    CALL PL_AMARK                  ; Owning, if its element owns.
    JR   AC_ARRAY                  ; The next dimension out.
.OPEN:                         ; Every bound is built.
    LD   HL,AG_OPENF               ; Was the outermost open?
    OR   (HL)                      ; (A is zero.)
    RET  Z                         ; No: the type is complete.
    LD   (HL),0                    ; Yes, this once:
    CALL AC_ITEM                   ; the element type,
    CP   AG_FILE                   ; a File's
    JP   Z,TR_OPER                 ; waiting (DG_NYI), and a handle's,
    CALL PL_ISHND                  ; whose IDs an open array's cannot
    JP   C,TR_OPER                 ; hold (AG_HND), waiting too,
    CP   AG_OLIM-AG_OPEN           ; one an open array's ID can hold
    JP   NC,AG_EMETA               ; (DG_META, types, beyond),
    ADD  A,AG_OPEN                 ; makes the open array's ID,
    LD   (AG_CTYPE),A              ; the current type.
    RET                            ; Back to the engine.

;@ROUTINE OUT A,CARRY,ZERO CLOBBERS SIGN,PARITY,HALFCARRY
; The current type (AG_CTYPE) as an element, a field or a result: not a
; view (DG_CLASH, AG_NOVW). A returns it.

AC_ITEM:                       ; The current type as an element:
    LD   A,(AG_CTYPE)              ; not
    JP   AG_NOVW                   ; a view; A is it.

; -------------------------------------------------------- scalar constants

AC_NAME EQU  EX_DECL           ; RetainDeclarationName: check and keep it.

;@ROUTINE IN A OUT A
; Set the type the next run-time expression is expected to have. AC_IDLE,
; its RET, is the action BeginTypeBound, which needs nothing done.

AC_WANT:
    LD   (EX_WANT),A               ; AC_EXPR reads it.
AC_IDLE:                       ; BeginTypeBound: AC_FOLD sets its own type.
    RET                            ; Back to the engine.

;@ROUTINE OUT A,HL,CARRY,ZERO CLOBBERS SIGN,PARITY,HALFCARRY,BC,DE
; FinishConstantExpression: the constant's value must be known
; (not-constant otherwise). A Boolean stays Boolean; an exact value or a
; u8 becomes an exact, untyped constant, and any other type needs the
; constant typed (constant-needs-type), as the reference's
; constDeclaration has it. The type goes to AC_DINFO, the value's five
; bytes to AC_DVAL.

AC_VALUE:
    LD   A,(EX_RMETA)              ; The metadata.
    LD   D,A                       ; Keep it.
    AND  SY_KNOWN                  ; Did it fold?
    LD   A,DG_KNOWN                ; No: not-constant,
    JP   Z,EX_EVAL                 ; at the value.
    LD   A,D                       ; Recover the metadata.
    AND  EX_TMASK                  ; Its type:
    CP   SY_U8                     ; a u8
    JR   Z,.EXACT                  ; becomes exact,
    CP   AG_FIRST                  ; Enums retain their nominal type.
    JR   NC,.TYPEOK                ; Expression types above this are enums.
    CP   SY_BOOL                   ; a Boolean
    JR   Z,.TYPEOK                 ; stays one,
    OR   A                         ; and any other
    LD   A,DG_UNTYP                ; needs the constant typed,
    JP   NZ,EX_EVAL                ; at the value.
.EXACT:                        ; An exact constant.
    XOR  A                         ; No type.
.TYPEOK:                       ; A is the constant's type.
    LD   (AC_DINFO),A              ; Class constant (zero) with that type.
    LD   HL,EX_RVAL                ; The value's five bytes
    LD   DE,AC_DVAL                ; become the symbol's payload.
    LD   BC,5                      ; Copied.
    LDIR                           ; Carry is clear.
    RET                            ; Back to the engine.

;@ROUTINE OUT A,CARRY,ZERO CLOBBERS SIGN,PARITY,HALFCARRY,BC,DE,HL
; CommitConstant: declare the scalar constant, at top level or in a block,
; of type AC_DINFO, exact or typed, and value AC_DVAL: its low word is
; the symbol's payload and its three high bytes follow it (SY_VHI).

AC_CONST:
    LD   A,(AC_DINFO)              ; Its type, class constant (SY_CONST, zero),
    LD   D,SY_CONST                ; Storage class constant.
    CALL SY_KIND                   ; Encode the nominal type when needed.
    LD   BC,(AC_DVAL)              ; Its value's low word.
    CALL EX_PREP                   ; Write the provisional symbol.
    INC  HL                        ; HL is its payload's high byte: next,
    EX   DE,HL                     ; SY_VHI,
    LD   HL,AC_DVAL+2              ; takes the value's
    LD   BC,3                      ; three high bytes.
    LDIR                           ; Copied.
    LD   A,(AC_DINFO)              ; Its full type,
    CP   AG_FIRST                  ; a nominal enum needs its tag.
    JP   NC,SY_TAG                 ; Tag and commit it.
    JP   SY_CMT                    ; Commit a builtin scalar.

;@ROUTINE OUT A,CARRY,ZERO CLOBBERS SIGN,PARITY,HALFCARRY,BC,DE,HL,IX
; CommitAggregateConstant: a typed scalar constant (D20) is declared with
; its type and the value staged, its bytes read back as the number they
; are at the type (VL_WRAP: a signed type's sign extended). An
; aggregate's staged object is written as a rodata blob and the constant
; declared, its payload the blob's ordinal.

AC_ROCMT:
    LD   A,(AG_CTYPE)              ; The constant's type,
    CALL AG_SCAL                 ; a scalar, including enums,
    JR   NC,.BLOB                  ; or an aggregate.
    LD   HL,(AG_IBASE)             ; The staged bytes,
    LD   DE,AC_DVAL                ; four of them,
    LD   BC,4                      ; are
    LDIR                           ; the value's,
    LD   A,(AG_CTYPE)              ; Keep the full nominal type.
    LD   (AC_DINFO),A              ; AC_CONST consumes it.
    CP   AG_FIRST                  ; Enum payloads are unsigned bytes.
    JR   C,.PHYSICAL               ; A builtin retains its storage type.
    LD   A,SY_U8                   ; Enum ordinal.
.PHYSICAL:
    LD   HL,AC_DVAL                ; read as
    CALL VL_WRAP                   ; the type's number.
    JR   AC_CONST                  ; Declare it.
.BLOB:                         ; An aggregate constant:
    LD   A,(SY_BODY+1)             ; in a routine's body
    OR   A                         ; it waits
    JR   Z,.TOP                    ; for the routine's blob,
    CALL RG_DEFER                  ; BC its ordinal;
    JR   .SYM                      ; otherwise
.TOP:                          ; it is written,
    LD   A,BL_KRO                  ; read-only data.
    CALL RG_DATA                   ; Write it; BC is its ordinal.
.SYM:                          ; BC is the ordinal.
    LD   D,SY_AGGR+SY_CONST        ; An aggregate constant.
    CALL EX_PREP                   ; Write the provisional symbol.
    LD   A,(AG_CTYPE)              ; The constant's type ID.
    JP   SY_TAG                    ; Record it and commit the symbol.

AC_CLAIM EQU  EX_KEEP          ; BeginAssert: keep `assert`'s position.

;@ROUTINE OUT A,CARRY,ZERO CLOBBERS SIGN,PARITY,HALFCARRY,BC,DE,HL
; CommitAssert: the constant expression must be a known Boolean (DG_CLASH)
; and true (DG_FALSE). Either diagnostic is reported at `assert`.

AC_PROVE:
    CALL AC_RESUB                  ; Report at the retained `assert` token.
    LD   A,(EX_RMETA)              ; The expression's metadata.
    CP   SY_KNOWN+SY_BOOL          ; A known Boolean?
    JR   NZ,.BADTYPE               ; No: raise DG_CLASH.
    LD   A,(EX_RVAL)               ; Its value.
    OR   A                         ; True?
    RET  NZ                        ; The assertion holds.
    CALL DG_RAISE                  ; It is false: abandon the build.
    DB   DG_FALSE                  ; Assertion failed.
.BADTYPE:                      ; Not a compile-time Boolean.
    CALL DG_RAISE                  ; Abandon the build.
    DB   DG_CLASH                  ; Type mismatch.

; ----------------------------------------------------- program variables

;@ROUTINE OUT A,CARRY,ZERO CLOBBERS SIGN,PARITY,HALFCARRY,BC,DE,HL
; SaveProgramType: begin a program variable of the current type.

AC_VAR:
    LD   A,(AG_CTYPE)              ; The declared type:
    LD   HL,AC_DPOS                ; a handle variable must be optional,
    CALL PL_NEEDO                  ; at its name; fall into AC_OBJ.

;@ROUTINE IN A OUT A,CARRY,ZERO CLOBBERS SIGN,PARITY,HALFCARRY,BC,DE,HL
; Begin an object of type A: not a view (DG_BOUND). Its type goes to
; AC_DINFO and its size to AG_OSIZE, ready for an optional initializer,
; which stages it (AC_IMAGE).

AC_OBJ:
    CALL AG_NOVW                   ; Not a view.
    LD   (AC_DINFO),A              ; The object's type ID.
    CALL AG_SIZE                   ; HL is its extent.
    LD   (AG_OSIZE),HL             ; The object's size...
    LD   (AG_OEND),HL              ; ...and where its initializer must end.
    XOR  A                         ; A is zero:
    LD   (AG_LEVEL),A              ; no initializer nesting...
    LD   (AG_GIVEN),A              ; ...and no initializer yet.
    RET                            ; Back to the engine.

; SaveAggregateConstantType: begin a typed constant, at top level or in a
; routine's body: its value is staged as an object's initializer is.

AC_ROOBJ EQU  AC_VAR           ; SaveAggregateConstantType: as an object.

;@ROUTINE OUT A,CARRY,ZERO CLOBBERS SIGN,PARITY,HALFCARRY,DE,HL
; FinishProgramInitializer: an initializer was given, and it must have
; filled the object exactly (DG_ITEMS otherwise).

AC_EXACT:
    LD   A,1                       ; An initializer was given.
    LD   (AG_GIVEN),A              ; AC_ALLOC places the object in data.
    LD   HL,(AG_OPOS)              ; Where the initializer stopped.
    LD   DE,(AG_OEND)              ; Where the object ends.
    OR   A                         ; Clear carry for the comparison.
    SBC  HL,DE                     ; Equal?
    JP   NZ,AG_ECNT                ; No: raise DG_ITEMS.
    RET                            ; Back to the engine.

;@ROUTINE OUT A,CARRY,ZERO CLOBBERS SIGN,PARITY,HALFCARRY,BC,DE,HL,IX
; CommitProgramVariable: write the object as a data blob if it had an
; initializer, otherwise as a bss blob, and declare it with the blob's
; ordinal as its payload. A scalar's information byte is its type with
; class SY_GLOB; an aggregate is SY_AGLOB, its type ID kept by SY_TAG.

AC_ALLOC:
    LD   A,(AG_GIVEN)              ; Was an initializer given?
    OR   A                         ; Zero means none.
    LD   A,BL_KDATA                ; Initialised data.
    JR   Z,.BSS                    ; None: bss.
    CALL RG_DATA                   ; The staged bytes; BC is the ordinal.
    JR   .DECLARE                  ; Declare it.
.BSS:                          ; No initializer.
    CALL RG_BSS                    ; Its size only; BC is the ordinal.
.DECLARE:                      ; BC is the blob's ordinal.
    LD   A,(AC_DINFO)              ; The object's type ID.
    LD   D,SY_GLOB                 ; Storage class program variable.
    CALL SY_KIND                   ; Encode scalar, enum or aggregate.
.PREPARE:                      ; D is the information byte, BC the ordinal.
    CALL EX_PREP                   ; Write the provisional symbol.
    LD   A,(AC_DINFO)              ; The type ID.
    JP   SY_TAG                    ; Record it and commit the symbol.
