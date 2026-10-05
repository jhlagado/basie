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
;    ACTIONS.ASM  islands, types, constants, assertions, program variables
;                 and records
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
;    AC_REC, AC_FIELD, AC_PLACE, AC_RECOK  record declarations
;
;  A declaration's name is retained (AC_NAME, AC_SUB: spelling in AC_DNAME,
;  position in AC_DPOS) while the rest is parsed; its class and type build
;  up in AC_DINFO and its payload in AC_DVAL. EX_PREP then writes the
;  symbol provisionally and SY_CMT or SY_TAG commits it, so a declaration
;  cannot refer to itself. The current type is AG_CTYPE: 1..3 for the
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
AC_MODE EQU  AG_IBUF           ; Byte: the for loop's mode (CT_MINC...).
AC_INDEX EQU  AC_MODE+1        ; Word: the counter's offset from IX.
AC_BOUND EQU  AC_INDEX+2       ; Word: the bound's offset from IX.
AC_DELTA EQU  AC_BOUND+2       ; Word: the step's magnitude.
AC_WEND EQU  AC_DELTA+2        ; End of the action scratch (marker).

; --------------------------------------------------------------- islands

;@ROUTINE OUT A,HL,CARRY,ZERO CLOBBERS SIGN,PARITY,HALFCARRY,BC,DE,IX,IY
; Island ConstantExpression: parse an expression that must fold to a
; constant, without emitting it. The result is left in EX_RMETA/EX_RVAL.

AC_FOLD:
    LD   A,SY_EXACT                ; Expect an untyped exact value.
    CALL EX_CONST                  ; Parse with emission off: A metadata, HL value.
    JR   AC_STASH                  ; Keep the result for the next action.

;@ROUTINE OUT A,HL,CARRY,ZERO CLOBBERS SIGN,PARITY,HALFCARRY,BC,DE,IX,IY
; Island RuntimeExpression: parse an expression of the type in EX_WANT,
; emitting its operations, and leave its result in EX_RMETA/EX_RVAL.

AC_EXPR:
    LD   A,(EX_WANT)               ; The type the preceding action expects.
    CALL EX_RUN                    ; Parse and emit: A metadata, HL value if known.

;@ROUTINE IN A,HL OUT A,CARRY,ZERO CLOBBERS SIGN,PARITY,HALFCARRY
; Keep expression result A (metadata) and HL (value) for the action that
; checks or uses it.

AC_STASH:
    LD   (EX_RMETA),A              ; The result's type and known flag.
    LD   (EX_RVAL),HL              ; Its value, meaningful when known.
    OR   A                         ; Clear carry.
    RET                            ; Back to the engine.

;@ROUTINE OUT A,B,DE,CARRY,ZERO CLOBBERS SIGN,PARITY,HALFCARRY,C,HL
; Island StepConstant: parse a for loop's step (CT_STEP), adding its
; direction bit, CT_MDOWN, to AC_MODE and keeping its magnitude in
; AC_DELTA.

AC_BY:
    CALL CT_STEP                   ; B is the direction bit, DE the magnitude.
    LD   A,(AC_MODE)               ; The mode so far (the bound's kind).
    OR   B                         ; Add the downward bit.
    LD   (AC_MODE),A               ; Keep the complete mode.
    LD   (AC_DELTA),DE             ; Keep the step.
    OR   A                         ; Clear carry.
    RET                            ; Back to the engine.

;@ROUTINE OUT A,CARRY,ZERO CLOBBERS SIGN,PARITY,HALFCARRY,B,DE,HL,IX,IY
; Island StaticInitializer: parse the initializer of the object being
; declared, whose type is in AC_DINFO, into the staging buffer (AG_PARSE).
; AC_DINFO is preserved across the parse.

AC_IMAGE:
    LD   A,(AC_DINFO)              ; The object's type ID.
    LD   B,A                       ; Keep it across the parse.
    PUSH BC                        ; AG_PARSE may reuse AC_DINFO.
    CALL AG_PARSE                  ; Stage the initializer for type A.
    POP  BC                        ; Recover the type ID.
    LD   A,B                       ; Restore it...
    LD   (AC_DINFO),A              ; ...for AC_EXACT and AC_ALLOC.
    OR   A                         ; Clear carry.
    RET                            ; Back to the engine.

;@ROUTINE NORETURN
; Island StrayClause: a routine body begins with else or elseif, which
; belongs to no if. Raise DG_END, end expected.

AC_STRAY:
    CALL DG_RAISE                  ; Abandon the build.
    DB   DG_END                    ; Expected `end`.

; ----------------------------------------------------------------- types

;@ROUTINE IN A OUT A,CARRY,ZERO CLOBBERS SIGN,PARITY,HALFCARRY
; TypeU8, TypeU16, TypeBoolean: one routine for three contiguous actions.
; Ordinal A less GR_U8-1 is the type ID 1, 2 or 3 (SY_U8, SY_U16, SY_BOOL).

AC_TYPE:
    SUB  GR_U8-1                   ; Map the action ordinal to the scalar's type ID.

;@ROUTINE IN A OUT A,CARRY,ZERO CLOBBERS SIGN,PARITY,HALFCARRY
; Make type ID A the current type.

AC_USE:
    LD   (AG_CTYPE),A              ; The type the declaration will use.
    OR   A                         ; Clear carry.
    RET                            ; Back to the engine.

;@ROUTINE OUT A,BC,CARRY,ZERO CLOBBERS SIGN,PARITY,HALFCARRY,DE,HL
; ResolveRecordType: the current NAME must be a record type, which becomes
; the current type. Anything else raises DG_BOUND. AC_DINFO and AC_DVAL
; receive the name's symbol information.

AC_NAMED:
    CALL SY_GET                    ; A is the name's class and type, BC its payload.
    LD   D,A                       ; Keep the class and type.
    LD   (AC_DINFO),A              ; Record them.
    LD   (AC_DVAL),BC              ; Record the payload: the record's type ID.
    AND  SY_TYPE+SY_AGGR           ; Keep the type-name and aggregate flags.
    CP   SY_TYPE                   ; A type name, not an aggregate object?
    JP   NZ,AG_EFORM               ; No: raise DG_BOUND.
    LD   A,C                       ; The record's type ID.
    JR   AC_USE                    ; Make it current.

;@ROUTINE OUT A,HL,CARRY,ZERO CLOBBERS SIGN,PARITY,HALFCARRY,DE
; Return in HL the constant bound just parsed: it must be known, fit a u16
; and be nonzero, or DG_BOUND (DG_RANGE for a value too wide) is raised.

AC_COUNT:
    LD   A,(EX_RMETA)              ; The bound's metadata.
    LD   D,A                       ; Keep it.
    AND  SY_KNOWN                  ; Was it folded to a constant?
    JP   Z,AG_EFORM                ; No: raise DG_BOUND.
    LD   E,SY_U16                  ; It must fit a u16.
    LD   A,D                       ; Recover the metadata.
    CALL EX_FITS                   ; Check the value against u16.
    LD   HL,(EX_RVAL)              ; The bound's value.
    LD   A,H                       ; Is it zero?
    OR   L                         ; Test both bytes.
    JP   Z,AG_EFORM                ; A zero bound is not allowed.
    RET                            ; HL is the bound.

;@ROUTINE OUT A,CARRY,ZERO CLOBBERS SIGN,PARITY,HALFCARRY,BC,DE,HL
; MakeStringType: `string[N]`. N must be below 254, else DG_SIZE. The
; string type of capacity N, N+2 bytes, becomes the current type, shared
; with an identical one already declared.

AC_STR:
    CALL AC_COUNT                  ; HL is the capacity N.
    LD   A,H                       ; Over 255?
    OR   A                         ; Test the high byte.
    JP   NZ,AG_ESTR                ; Raise DG_SIZE.
    LD   A,L                       ; The capacity.
    CP   254                       ; The length byte must count N+1 bytes.
    JP   NC,AG_ESTR                ; Raise DG_SIZE.
    LD   A,L                       ; The capacity again.
    LD   (AG_NAUX),A               ; The candidate's capacity byte.
    LD   (AG_NDIM),HL              ; And its capacity word.
    LD   A,AG_KSTR                 ; A bounded string.
    LD   (AG_NKIND),A              ; The candidate's kind.
    INC  HL                        ; Add the length byte...
    INC  HL                        ; ...and the terminator.
    LD   (AG_NSIZE),HL             ; The candidate's extent.

;@ROUTINE OUT A,CARRY,ZERO CLOBBERS SIGN,PARITY,HALFCARRY,BC,DE,HL
; Intern the candidate descriptor and make it the current type.

AC_REUSE:
    CALL AG_REUSE                  ; A is the type's ID, new or shared.
    JR   AC_USE                    ; Make it current.

;@ROUTINE OUT A,CARRY,ZERO CLOBBERS SIGN,PARITY,HALFCARRY
; MakeOpenStringType: `string[]`, a parameter-only view of a string of any
; capacity rather than a type with its own descriptor.

AC_OPEN:
    LD   A,AG_VIEW                 ; The open-string view.
    JR   AC_USE                    ; Make it current.

;@ROUTINE OUT A,CARRY,ZERO CLOBBERS SIGN,PARITY,HALFCARRY,DE,HL
; SaveArrayBound: keep an array dimension's bound (AC_COUNT) until the
; type is complete; at most AG_DCAP (DG_BOUND).

AC_DIM:
    CALL AC_COUNT                  ; HL is the bound.
    EX   DE,HL                     ; Keep it in DE.
    LD   HL,AG_DCNT                ; The bounds waiting:
    LD   A,(HL)                    ; is there room
    CP   AG_DCAP                   ; for another?
    JP   NC,AG_EFORM               ; No: raise DG_BOUND.
    INC  (HL)                      ; Count it.
    ADD  A,A                       ; Its word
    LD   L,A                       ; in
    LD   H,0                       ; the stack
    PUSH DE                        ; (the bound kept)
    LD   DE,AG_DSTK                ; of
    ADD  HL,DE                     ; bounds.
    POP  DE                        ; The bound
    LD   (HL),E                    ; goes
    INC  HL                        ; there.
    LD   (HL),D                    ; Both bytes.
    RET                            ; Back to the engine.

;@ROUTINE OUT A,CARRY,ZERO CLOBBERS SIGN,PARITY,HALFCARRY,BC,DE,HL
; MakeArrayTypes: once a type's dimensions are parsed, build its arrays
; from the innermost, the last bound kept, out (parseType): each an array
; of its bound's elements of the current type, interned and made current.
; The element may not be a view (DG_BOUND); the extent must fit the 1 KiB
; data image (DG_DATA). Nothing is done without dimensions.

AC_ARRAY:
    LD   HL,AG_DCNT                ; Any bounds
    LD   A,(HL)                    ; waiting?
    OR   A                         ; None:
    RET  Z                         ; the type is complete.
    DEC  (HL)                      ; The last one is used:
    DEC  A                         ; its index,
    ADD  A,A                       ; and its word
    LD   L,A                       ; in
    LD   H,0                       ; the stack
    LD   DE,AG_DSTK                ; of
    ADD  HL,DE                     ; bounds:
    LD   C,(HL)                    ; BC is
    INC  HL                        ; the
    LD   B,(HL)                    ; count.
    LD   (AG_NDIM),BC              ; The candidate's count.
    LD   A,(AG_CTYPE)              ; The element type.
    CP   AG_VIEW                   ; An open string?
    JP   Z,AG_EFORM                ; Has no fixed size: raise DG_BOUND.
    LD   (AG_NAUX),A               ; The candidate's element type.
    CALL AG_SIZE                   ; HL is one element's extent.
    LD   D,H                       ; Keep it...
    LD   E,L                       ; ...in DE.
    LD   HL,0                      ; Sum the extent from zero.
.SIZELOOP:                     ; Add one element per iteration.
    ADD  HL,DE                     ; One more element.
    JP   C,AG_EDATA                ; Past 64K: raise DG_DATA.
    CALL AG_FITRW                  ; Past 1 KiB: raise DG_DATA.
    DEC  BC                        ; One element fewer to add.
    LD   A,B                       ; Any left?
    OR   C                         ; Test both bytes.
    JR   NZ,.SIZELOOP              ; Add the next.
    LD   (AG_NSIZE),HL             ; The candidate's extent.
    LD   A,AG_KARR                 ; An array.
    LD   (AG_NKIND),A              ; The candidate's kind.
    CALL AC_REUSE                  ; Intern it and make it current.
    JR   AC_ARRAY                  ; The next dimension out.

; -------------------------------------------------------- scalar constants

AC_NAME EQU  EX_DECL           ; RetainDeclarationName: check and keep it.

;@ROUTINE IN A OUT A
; Set the type the next run-time expression is expected to have. AC_IDLE,
; its RET, is the action BeginTypeBound, which needs nothing done.

AC_WANT:
    LD   (EX_WANT),A               ; AC_EXPR reads it.
AC_IDLE:                       ; BeginTypeBound: AC_FOLD sets its own type.
    RET                            ; Back to the engine.

;@ROUTINE OUT A,HL,CARRY,ZERO CLOBBERS SIGN,PARITY,HALFCARRY,D
; FinishConstantExpression: the constant's value must be known (DG_CLASH
; otherwise). A Boolean stays Boolean; any number becomes an exact,
; untyped constant. The type goes to AC_DINFO, the value to AC_DVAL.

AC_VALUE:
    LD   HL,(EX_RVAL)              ; The value (reloaded below).
    LD   A,(EX_RMETA)              ; The metadata.
    LD   D,A                       ; Keep it.
    AND  SY_KNOWN                  ; Did it fold?
    JP   Z,EX_ETYPE                ; No: raise DG_CLASH.
    LD   A,D                       ; Recover the metadata.
    AND  SY_TMASK                  ; Its type.
    CP   SY_BOOL                   ; Boolean?
    LD   A,SY_EXACT                ; A number is declared exact.
    JR   NZ,.TYPEOK                ; Keep that for a number.
    LD   A,SY_BOOL                 ; A Boolean keeps its type.
.TYPEOK:                       ; A is the constant's type.
    LD   (AC_DINFO),A              ; Class constant (zero) with that type.
    LD   HL,(EX_RVAL)              ; The value.
    LD   (AC_DVAL),HL              ; Becomes the symbol's payload.
    OR   A                         ; Clear carry.
    RET                            ; Back to the engine.

;@ROUTINE OUT A,CARRY,ZERO CLOBBERS SIGN,PARITY,HALFCARRY,BC,D,HL
; CommitConstant: declare the scalar constant.

AC_CONST:
    LD   A,(AC_DINFO)              ; Its type.
    OR   SY_CONST                  ; Class constant.
    LD   D,A                       ; The symbol's class and type.
    LD   BC,(AC_DVAL)              ; Its value.
    CALL EX_PREP                   ; Write the provisional symbol.
    JP   SY_CMT                    ; Commit it and return.

;@ROUTINE OUT A,CARRY,ZERO CLOBBERS SIGN,PARITY,HALFCARRY,BC,DE,HL
; CommitAggregateConstant: write the staged object as a rodata blob and
; declare the constant, whose payload is the blob's ordinal.

AC_ROCMT:
    LD   A,BL_KRO                  ; Read-only data.
    CALL RG_DATA                   ; Write it; BC is its ordinal.
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
    AND  SY_KNOWN+SY_TMASK         ; Its known flag and type.
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
    LD   A,(AG_CTYPE)              ; The declared type; fall into AC_OBJ.

;@ROUTINE IN A OUT A,CARRY,ZERO CLOBBERS SIGN,PARITY,HALFCARRY,BC,DE,HL
; Begin an object of type A: not a view (DG_BOUND). Its type goes to
; AC_DINFO; the staging buffer is sized to it and zeroed, ready for an
; optional initializer.

AC_OBJ:
    CP   AG_VIEW                   ; An open string?
    JP   Z,AG_EFORM                ; Cannot be an object: raise DG_BOUND.
    LD   (AC_DINFO),A              ; The object's type ID.
    CALL AG_SIZE                   ; HL is its extent.
    LD   (AG_OSIZE),HL             ; The object's size...
    LD   (AG_OEND),HL              ; ...and where its initializer must end.
    LD   HL,0                      ; Stage from the first byte.
    LD   (AG_OPOS),HL              ; The staging cursor.
    CALL AG_ZERO                   ; Zero the whole object.
    XOR  A                         ; Zero...
    LD   (AG_LEVEL),A              ; ...initializer nesting...
    LD   (AG_GIVEN),A              ; ...and no initializer yet.
    RET                            ; Back to the engine.

;@ROUTINE OUT A,CARRY,ZERO CLOBBERS SIGN,PARITY,HALFCARRY,BC,DE,HL
; SaveAggregateConstantType: begin an aggregate constant. Only aggregate
; types may be declared with `as`; a scalar raises DG_CLASH.

AC_ROOBJ:
    LD   A,(AG_CTYPE)              ; The declared type.
    CP   AG_FIRST                  ; A scalar?
    JP   C,EX_ETYPE                ; Raise DG_CLASH.
    JR   AC_OBJ                    ; Begin the object.

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
    OR   A                         ; Clear carry.
    RET                            ; Back to the engine.

;@ROUTINE OUT A,CARRY,ZERO CLOBBERS SIGN,PARITY,HALFCARRY,BC,DE,HL
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
    CP   AG_FIRST                  ; A scalar?
    LD   D,SY_AGLOB                ; Assume an aggregate program variable.
    JR   NC,.PREPARE               ; It is one.
    OR   SY_GLOB                   ; A scalar: class program variable,
    LD   D,A                       ; with its type.
.PREPARE:                      ; D is the information byte, BC the ordinal.
    CALL EX_PREP                   ; Write the provisional symbol.
    LD   A,(AC_DINFO)              ; The type ID.
    JP   SY_TAG                    ; Record it and commit the symbol.

; ------------------------------------------------------------- records

;@ROUTINE OUT A,CARRY,ZERO CLOBBERS SIGN,PARITY,HALFCARRY,BC,DE,HL
; BeginRecord: keep the record's name, check that the type and record
; tables have room (DG_META), and start an empty field list.

AC_REC:
    CALL EX_DECL                   ; Check and keep the record's name.
    LD   A,(AG_TCNT)               ; Types so far.
    CP   AG_TCAP                   ; Room for another?
    JP   NC,AG_EMETA               ; No: raise DG_META.
    LD   A,(AG_RCNT)               ; Records so far.
    CP   AG_RCAP                   ; Room for another?
    JP   NC,AG_EMETA               ; No: raise DG_META.
    LD   A,(AG_FCNT)               ; The next free field entry...
    LD   (AG_CFIDX),A              ; ...is the record's first.
    XOR  A                         ; No fields yet...
    LD   (AG_CFCNT),A              ; ...counted...
    LD   H,A                       ; ...and no...
    LD   L,A                       ; ...bytes...
    LD   (AG_CSIZE),HL             ; ...in the record.
    RET                            ; Back to the engine.

;@ROUTINE OUT A,CARRY,ZERO CLOBBERS SIGN,PARITY,HALFCARRY,BC,DE,HL
; BeginRecordField: the field name must be new in this record (DG_DUP) and
; the field table must have room (DG_META). The name goes into the
; field's entry.

AC_FIELD:
    CALL AG_FRESH                  ; Reject a repeated field name.
    LD   A,(AG_FCNT)               ; Fields of earlier records...
    LD   B,A                       ; ...held in B...
    LD   A,(AG_CFCNT)              ; ...plus this record's so far...
    ADD  A,B                       ; ...is the new field's index.
    CP   AG_FCAP                   ; Is there an entry for it?
    JP   NC,AG_EMETA               ; No: raise DG_META.
    PUSH AF                        ; Keep the index.
    CALL AG_FIELD                  ; HL addresses the entry.
    CALL TK_KEEP                   ; Record the name's spelling there.
    POP  AF                        ; Recover the index.
    OR   A                         ; Clear carry.
    RET                            ; Back to the engine.

;@ROUTINE OUT A,CARRY,ZERO CLOBBERS SIGN,PARITY,HALFCARRY,B,DE,HL
; CommitRecordField: give the field its type (not a view, DG_BOUND) and
; its offset, the record's size so far, then grow the record by the
; field's extent within 1 KiB (DG_DATA).

AC_PLACE:
    LD   A,(AG_CTYPE)              ; The field's type.
    CP   AG_VIEW                   ; An open string?
    JP   Z,AG_EFORM                ; Has no size: raise DG_BOUND.
    LD   A,(AG_FCNT)               ; The field's index...
    LD   B,A                       ; ...is the earlier fields...
    LD   A,(AG_CFCNT)              ; ...plus this record's...
    ADD  A,B                       ; ...so far.
    CALL AG_FIELD                  ; HL addresses its entry.
    INC  HL                        ; Skip the spelling's...
    INC  HL                        ; ...address...
    INC  HL                        ; ...and length.
    LD   A,(AG_CTYPE)              ; The field's type...
    LD   (HL),A                    ; ...into AG_FTYPE.
    INC  HL                        ; Step to AG_FPOS.
    LD   DE,(AG_CSIZE)             ; The record's size so far...
    LD   (HL),E                    ; ...is the field's offset...
    INC  HL                        ; ...low byte first...
    LD   (HL),D                    ; ...then high.
    LD   A,(AG_CTYPE)              ; The field's type.
    PUSH DE                        ; Keep its offset.
    CALL AG_SIZE                   ; HL is its extent.
    POP  DE                        ; Recover the offset.
    ADD  HL,DE                     ; The record's new size.
    JP   C,AG_EDATA                ; Past 64K: raise DG_DATA.
    CALL AG_FITRW                  ; Past 1 KiB: raise DG_DATA.
    LD   (AG_CSIZE),HL             ; Commit it.
    LD   HL,AG_CFCNT               ; Count...
    INC  (HL)                      ; ...the field.
    XOR  A                         ; Clear carry.
    RET                            ; Back to the engine.

;@ROUTINE OUT A,CARRY,ZERO CLOBBERS SIGN,PARITY,HALFCARRY,BC,DE,HL
; CommitRecord: a record needs a field (DG_EMPTY). Append its descriptor
; as a new type (records are never shared), fill its record entry and
; declare its name as a record type whose payload is the type ID.

AC_RECOK:
    LD   A,(AG_CFCNT)              ; Any fields?
    OR   A                         ; Zero means none.
    JP   Z,AG_EVOID                ; Raise DG_EMPTY.
    LD   A,AG_KREC                 ; A record.
    LD   (AG_NKIND),A              ; The candidate's kind.
    LD   A,(AG_RCNT)               ; The record's ordinal.
    LD   (AG_NAUX),A               ; Its auxiliary byte.
    LD   HL,0                      ; A record has no length word.
    LD   (AG_NDIM),HL              ; Clear it.
    LD   HL,(AG_CSIZE)             ; The record's size...
    LD   (AG_NSIZE),HL             ; ...is the candidate's extent.
    CALL AG_ADD                    ; A is the new type's ID.
    LD   (AG_CTYPE),A              ; Keep it.
    LD   A,(AG_RCNT)               ; The record's ordinal...
    ADD  A,A                       ; ...times the entry size...
    LD   E,A                       ; ...widened...
    LD   D,0                       ; ...to DE...
    LD   HL,AG_RTAB                ; ...indexes the record table.
    ADD  HL,DE                     ; HL addresses the record's entry.
    LD   A,(AG_CFIDX)              ; Its first field...
    LD   (HL),A                    ; ...into AG_RFIDX.
    INC  HL                        ; Step to AG_RFCNT.
    LD   A,(AG_CFCNT)              ; Its field count...
    LD   (HL),A                    ; ...into AG_RFCNT.
    LD   D,SY_RTYPE                ; The name is a record type...
    LD   A,(AG_CTYPE)              ; ...whose payload...
    LD   C,A                       ; ...is its...
    LD   B,0                       ; ...type ID.
    CALL EX_PREP                   ; Write the provisional symbol.
    CALL SY_CMT                    ; Commit it.
    LD   A,(AG_CFCNT)              ; The record's fields...
    LD   HL,AG_FCNT                ; ...join...
    ADD  A,(HL)                    ; ...the fields...
    LD   (HL),A                    ; ...in use.
    LD   HL,AG_RCNT                ; Count...
    INC  (HL)                      ; ...the record.
    XOR  A                         ; Clear carry.
    RET                            ; Back to the engine.
