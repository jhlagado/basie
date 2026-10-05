;==========================================================================
;  Grammar actions: types and declarations
;==========================================================================
;
;  The semantic actions of the grammar. The LL(1) engine calls one when it
;  pops an action symbol, through GR_ACTX, with the action's ordinal in A
;  (LL1.ASM). Actions never choose productions. They check what has just
;  been parsed, record it in the symbol, type and routine tables, append
;  operations to the semantic transcript, and at the grammar's islands
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
;    AC_TYPE, AC_NAMED, AC_STR, AC_OPEN, AC_ARRAY  set the current type
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
;  Workspace. The for-loop and fallthrough scratch below overlays the
;  first thirteen bytes of AG_IBUF, the initializer staging buffer, which
;  is used only by top-level declarations and is dead inside a routine.

AC_MODE EQU  AG_IBUF           ; Byte: the for loop's mode bits.
AC_DELTA EQU  AC_MODE+1        ; Word: the for loop's step magnitude.
AC_WHERE EQU  AC_DELTA+2       ; Word: the for statement's source offset.
AC_FLOWS EQU  AC_WHERE+2       ; CT_FCAP bytes: saved CT_FALLS per depth.
AC_WEND EQU  AC_FLOWS+CT_FCAP  ; End of the action scratch (marker).

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
; direction bit to AC_MODE and keeping its magnitude in AC_DELTA.

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

;@ROUTINE OUT A,CARRY,ZERO CLOBBERS SIGN,PARITY,HALFCARRY
; BeginTypeBound: expect a u16 for a string capacity or array length.
; AC_FOLD, which follows, sets its own expected type, so this has no lasting
; effect; AC_COUNT does the u16 check.

AC_BOUND:
AC_U16:                        ; Also used to expect a for loop's bound.
    LD   A,SY_U16                  ; Expect a u16.
    JP   AC_WANT                   ; Record it.

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

;@ROUTINE OUT A,CARRY,ZERO CLOBBERS SIGN,PARITY,HALFCARRY,BC,DE,HL
; MakeArrayType: an array of N elements of the current type. The element
; may not be a view (DG_BOUND) or an array (DG_BOUND); the extent must fit
; the 1 KiB data image (DG_DATA).

AC_ARRAY:
    LD   A,(AG_CTYPE)              ; The element type.
    CP   AG_VIEW                   ; An open string?
    JP   Z,AG_EFORM                ; Has no fixed size: raise DG_BOUND.
    CP   AG_FIRST                  ; A scalar?
    JR   C,.ELEMENT                ; Any scalar is a valid element.
    PUSH AF                        ; Keep the element's ID.
    CALL AG_DESC                   ; HL addresses its descriptor.
    LD   A,(HL)                    ; Its kind.
    CP   AG_KARR                   ; Another array?
    JP   Z,AG_ENEST                ; Raise DG_BOUND, dropping the saved ID.
    POP  AF                        ; Recover the element's ID.
.ELEMENT:                      ; A is a valid element type.
    LD   (AG_NAUX),A               ; The candidate's element type.
    CALL AC_COUNT                  ; HL is the element count.
    LD   (AG_NDIM),HL              ; The candidate's count.
    LD   B,H                       ; Count the elements...
    LD   C,L                       ; ...in BC.
    LD   A,(AG_NAUX)               ; The element type.
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
    JR   AC_REUSE                  ; Intern it and make it current.

; -------------------------------------------------------- scalar constants

AC_NAME EQU  EX_DECL           ; RetainDeclarationName: check and keep it.

;@ROUTINE IN A OUT A,CARRY,ZERO CLOBBERS SIGN,PARITY,HALFCARRY
; Set the type the next run-time expression is expected to have.

AC_WANT:
    LD   (EX_WANT),A               ; AC_EXPR reads it.
    OR   A                         ; Clear carry.
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

;@ROUTINE OUT A,CARRY,ZERO CLOBBERS SIGN,PARITY,HALFCARRY,BC,DE,HL,IX
; CommitAggregateConstant: append the staged object to the read-only data
; and declare the constant, whose payload is its offset in that segment.
; The read-only data follows the initialised data in AG_DATA; together
; they must fit 1 KiB (DG_ROCAP).

AC_ROCMT:
    CALL TG_HOME                   ; A is the current part's bank (always 0).
    LD   (AC_DINFO),A              ; Hold it briefly.
    CALL TG_LENAT                  ; HL addresses that bank's read-only length.
    PUSH HL                        ; Keep the address.
    LD   C,(HL)                    ; BC is the length so far...
    INC  HL                        ; ...low byte first...
    LD   B,(HL)                    ; ...then high.
    LD   (AC_DVAL),BC              ; The constant's offset in the segment.
    LD   HL,(AG_OSIZE)             ; The object's extent.
    ADD  HL,BC                     ; The bank's new read-only length.
    LD   E,L                       ; Move it...
    LD   D,H                       ; ...to DE.
    POP  HL                        ; Recover the length's address.
    LD   (HL),E                    ; Store the new length...
    INC  HL                        ; ...low byte first...
    LD   (HL),D                    ; ...then high.
    LD   A,(AC_DINFO)              ; The bank.
    RLCA                           ; Move it...
    RLCA                           ; ...to bits...
    RLCA                           ; ...4 and...
    RLCA                           ; ...5.
    OR   SY_AGGR+SY_CONST          ; An aggregate constant in that bank.
    LD   (AC_DINFO),A              ; The symbol's information byte.
    LD   BC,(AG_ROLEN)             ; Dead: BC is reloaded below.
    LD   D,SY_AGGR+SY_CONST        ; Dead: D is reloaded below.
    LD   A,(AC_DINFO)              ; The information byte.
    LD   D,A                       ; For EX_PREP.
    LD   BC,(AC_DVAL)              ; The payload: the segment offset.
    CALL EX_PREP                   ; Write the provisional symbol.
    LD   BC,(AG_ROLEN)             ; The read-only bytes so far.
    LD   HL,(AG_OSIZE)             ; Plus this object...
    ADD  HL,BC                     ; ...is the new read-only length...
    LD   DE,(AG_DLEN)              ; ...and with the initialised data...
    ADD  HL,DE                     ; ...the whole image.
    CALL AG_FITRO                  ; Past 1 KiB: raise DG_ROCAP.
    OR   A                         ; Clear carry for the subtraction.
    SBC  HL,DE                     ; Remove the initialised data again.
    LD   (AG_ROLEN),HL             ; The new read-only length.
    LD   HL,AG_DATA                ; The image...
    ADD  HL,DE                     ; ...past the initialised data...
    ADD  HL,BC                     ; ...past the earlier constants.
    EX   DE,HL                     ; DE is where the object goes.
    LD   HL,AG_IBUF                ; The staged object.
    LD   BC,(AG_OSIZE)             ; Its extent.
    LDIR                           ; Append it to the read-only data.
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
; CommitProgramVariable: place the object in initialised data if it had an
; initializer, otherwise in bss, and declare it.

AC_ALLOC:
    LD   A,(AG_GIVEN)              ; Was an initializer given?
    OR   A                         ; Zero means none.
    JR   Z,.BSS                    ; Place it in bss.
    JR   AC_DATA                   ; Place it in initialised data.
.BSS:                          ; No initializer.
    JR   AC_BSS                    ; Place it in bss.

;@ROUTINE IN BC OUT A,CARRY,ZERO CLOBBERS SIGN,PARITY,HALFCARRY,DE,HL
; Declare the program variable with payload BC, its offset in its segment.
; A scalar's information byte is its type with class SY_GLOB; an aggregate
; is SY_AGLOB, its type ID kept by SY_TAG.

AC_ENTER:
    PUSH BC                        ; Keep the payload.
    LD   A,(AC_DINFO)              ; The object's type ID.
    CP   AG_FIRST                  ; A scalar?
    JR   C,.SCALAR                 ; Its type is its information.
    LD   D,SY_AGLOB                ; An aggregate program variable.
    JR   .PREPARE                  ; Write the symbol.
.SCALAR:                       ; A is the scalar type.
    OR   SY_GLOB                   ; Class program variable.
    LD   D,A                       ; The information byte.
.PREPARE:                      ; D is the information byte.
    CALL EX_PREP                   ; Write the provisional symbol.
    POP  BC                        ; Recover the payload.
    LD   A,(AC_DINFO)              ; The type ID.
    CALL SY_TAG                    ; Record it and commit the symbol.
    OR   A                         ; Clear carry.
    RET                            ; Back to the engine.

;@ROUTINE OUT A,CARRY,ZERO CLOBBERS SIGN,PARITY,HALFCARRY,BC,DE,HL
; Place an initialised object. The data image AG_DATA holds the
; initialised data and then the read-only constants, so the constants are
; first moved up by the object's size; their offsets count from the start
; of their own segment and do not change. The staged bytes are then copied
; in, and BC, the payload, is the object's data offset with bit 15 clear.

AC_DATA:
    LD   DE,(AG_DLEN)              ; The object goes at the end of the data.
    CALL AC_GROW                   ; AG_OPOS is its offset, HL the new data length.
    PUSH HL                        ; Keep the new length.
    LD   DE,(AG_ROLEN)             ; With the read-only data after it...
    ADD  HL,DE                     ; ...the image's new length...
    CALL AG_FITRW                  ; ...must fit 1 KiB (DG_DATA).
    POP  HL                        ; Recover the new data length.
    LD   (AG_DLEN),HL              ; Commit it.
    LD   BC,(AG_ROLEN)             ; How many read-only bytes to move?
    LD   A,B                       ; None?
    OR   C                         ; Test both bytes.
    JR   Z,.SHIFTED                ; Nothing to move.
    LD   HL,AG_DATA                ; The image...
    LD   DE,(AG_OPOS)              ; ...past the old data...
    ADD  HL,DE                     ; ...is where the constants start...
    ADD  HL,BC                     ; ...and past them...
    DEC  HL                        ; ...their last byte.
    LD   DE,(AG_OSIZE)             ; The distance to move them.
    PUSH HL                        ; Keep the source end.
    ADD  HL,DE                     ; The destination end.
    EX   DE,HL                     ; DE is the destination end.
    POP  HL                        ; HL is the source end.
    LDDR                           ; Move the constants up, last byte first.
.SHIFTED:                      ; The object's place is free.
    LD   A,(AC_DINFO)              ; The object's type ID.
    CALL AG_SIZE                   ; HL is its extent.
    LD   B,H                       ; Count it...
    LD   C,L                       ; ...in BC.
    LD   HL,AG_IBUF                ; The staged object.
    LD   DE,(AG_OPOS)              ; Its data offset.
    PUSH HL                        ; Keep the source.
    LD   HL,AG_DATA                ; The image...
    ADD  HL,DE                     ; ...at that offset.
    EX   DE,HL                     ; DE is the destination.
    POP  HL                        ; HL is the staged object.
    LDIR                           ; Copy it into the data.
    LD   BC,(AG_OPOS)              ; The payload: the data offset, bit 15 clear.
    OR   A                         ; Clear carry.
    JR   AC_ENTER                  ; Declare the variable.

;@ROUTINE OUT A,CARRY,ZERO CLOBBERS SIGN,PARITY,HALFCARRY,BC,DE,HL
; Place an object without an initializer in bss. BC, the payload, is its
; bss offset with bit 15 set.

AC_BSS:
    LD   DE,(PR_BSS)               ; The object goes at the end of bss.
    CALL AC_GROW                   ; DE is its offset, HL the new bss length.
    LD   (PR_BSS),HL               ; Commit it.
    LD   B,D                       ; The payload...
    LD   C,E                       ; ...is the offset...
    SET  7,B                       ; ...marked as bss.
    OR   A                         ; Clear carry.
    JP   AC_ENTER                  ; Declare the variable.

;@ROUTINE IN DE OUT A,DE,HL,CARRY,ZERO CLOBBERS SIGN,PARITY,HALFCARRY
; Place the current object at offset DE of a segment: AG_OPOS and DE
; return DE, HL the segment's new length. Data and bss each have the same
; 1 KiB limit as an aggregate object (DG_DATA).

AC_GROW:
    LD   (AG_OPOS),DE              ; The object's offset.
    LD   A,(AC_DINFO)              ; Its type ID.
    CALL AG_SIZE                   ; HL is its extent.
    LD   DE,(AG_OPOS)              ; Recover the offset.
    ADD  HL,DE                     ; The segment's new length.
    JP   AG_FITRW                  ; Must fit 1 KiB.

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
