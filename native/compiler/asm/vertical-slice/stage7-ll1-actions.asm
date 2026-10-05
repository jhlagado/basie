; Explicit semantic actions for the complete Stage 7 packed LL(1) grammar.
; These routines never select grammar productions. They consume only retained
; expression/type-directed external islands declared by the generated grammar.

; Aggregate initializer staging is dead while a routine body is parsed, so
; the for/flow action scratch safely reuses its first thirteen bytes.
HybridLL1ForMode       .equ AggregateInitializerBase
HybridLL1ForStep       .equ HybridLL1ForMode+1
HybridLL1ForOffset     .equ HybridLL1ForStep+2
HybridLL1FlowStackBase .equ HybridLL1ForOffset+2
HybridLL1ActionStateEnd .equ HybridLL1FlowStackBase+ControlFrameCapacity

; --------------------------------------------------------- retained parsers

.routine out A,BC,DE,HL,carry,zero clobbers sign,parity,halfCarry,IX,IY
HybridLL1ConstantExpression:
            LD   A,ScalarTypeExact
            CALL TypedExpressionBeginConstant
            JR   HybridLL1SaveExpressionResult

.routine out A,BC,DE,HL,carry,zero clobbers sign,parity,halfCarry,IX,IY
HybridLL1RuntimeExpression:
            LD   A,(ExpressionExpectedType)
            CALL TypedExpressionBeginRuntime
HybridLL1SaveExpressionResult:
.if CompilerDiagnosticReturns
            RET  C
.endif
            LD   (ExpressionRightMeta),A
            LD   (ExpressionRightValue),HL
            OR   A
            RET

.routine out A,B,DE,carry,zero clobbers sign,parity,halfCarry,C,HL
HybridLL1StepConstant:
            CALL StructuredParseStep
.if CompilerDiagnosticReturns
            RET  C
.endif
            LD   A,(HybridLL1ForMode)
            OR   B
            LD   (HybridLL1ForMode),A
            LD   (HybridLL1ForStep),DE
            OR   A
            RET

; The declared type has already selected the initializer shape. This external
; island retains the recursive, type-directed aggregate initializer machinery.
.routine out A,carry,zero clobbers sign,parity,halfCarry,B,C,D,DE,HL,IX,IY
HybridLL1StaticInitializer:
            LD   A,(DeclarationInfo)
            LD   B,A
            PUSH BC
            CALL AggregateParseInitializer
            POP  BC
.if CompilerDiagnosticReturns
            RET  C
.endif
            LD   A,B
            LD   (DeclarationInfo),A
            OR   A
            RET

HybridLL1StrayClause:
            CALL SetDiagInline
            .db  DiagnosticExpectedEnd

; --------------------------------------------------------------- type actions

; A is the logical action ordinal for the contiguous u8/u16/Boolean family.
HybridLL1SetScalarTypeAction:
            SUB  HybridLL1ActionOrdinalTypeU8-1
HybridLL1SetCurrentType:
            LD   (AggregateCurrentTypeId),A
            OR   A
            RET

.routine out A,BC,carry,zero clobbers sign,parity,halfCarry,D,DE,HL,IX,IY
HybridLL1ResolveRecordType:
            CALL SymbolLookupCurrent
.if CompilerDiagnosticReturns
            RET  C
.endif
            LD   D,A
            LD   (DeclarationInfo),A
            LD   (DeclarationPayload),BC
            AND  SymbolRecordTypeFlag+SymbolAggregateFlag
            CP   SymbolRecordTypeFlag
            JP   NZ,AggregateTypeShapeFailure
            LD   A,C
            JR   HybridLL1SetCurrentType

HybridLL1BeginTypeBound:
HybridLL1ExpectU16:
            LD   A,ScalarTypeU16
            JP   HybridLL1SaveExpectedType

; Return the checked, positive, byte-sized constant bound in HL.
.routine out A,DE,HL,carry,zero clobbers sign,parity,halfCarry,B,C,IX,IY
HybridLL1CheckedBound:
            LD   A,(ExpressionRightMeta)
            LD   D,A
            AND  ScalarMetaConstant
            JP   Z,AggregateTypeShapeFailure
            LD   E,ScalarTypeU16
            LD   A,D
            CALL TypedCheckAssignable
.if CompilerDiagnosticReturns
            RET  C
.endif
            LD   HL,(ExpressionRightValue)
            LD   A,H
            OR   L
            JP   Z,AggregateTypeShapeFailure
            RET

.routine out A,carry,zero clobbers sign,parity,halfCarry,B,C,D,DE,HL,IX,IY
HybridLL1MakeStringType:
            CALL HybridLL1CheckedBound
.if CompilerDiagnosticReturns
            RET  C
.endif
            LD   A,H
            OR   A
            JP   NZ,AggregateStringCapacityFailure
            LD   A,L
            CP   254
            JP   NC,AggregateStringCapacityFailure
            LD   A,L
            LD   (AggregateCandidateAux),A
            LD   (AggregateCandidateLength),HL
            LD   A,AggregateTypeKindString
            LD   (AggregateCandidateKind),A
            INC  HL
            INC  HL
            LD   (AggregateCandidateExtent),HL
HybridLL1InternCurrentType:
            CALL AggregateInternType
.if CompilerDiagnosticReturns
            RET  C
.endif
            JR   HybridLL1SetCurrentType

; `string[]` is a parameter-only view rather than an interned object type.
HybridLL1MakeOpenStringType:
            LD   A,AggregateOpenStringTypeId
            JR   HybridLL1SetCurrentType

.routine out A,carry,zero clobbers sign,parity,halfCarry,B,C,D,DE,HL,IX,IY
HybridLL1MakeArrayType:
            LD   A,(AggregateCurrentTypeId)
            CP   AggregateOpenStringTypeId
            JP   Z,AggregateTypeShapeFailure
            CP   AggregateFirstDynamicTypeId
            JR   C,HybridLL1ArrayElementReady
            PUSH AF
            CALL AggregateTypeAddress
            LD   A,(HL)
            CP   AggregateTypeKindArray
            JP   Z,AggregateNestedArrayFailure
            POP  AF
HybridLL1ArrayElementReady:
            LD   (AggregateCandidateAux),A
            CALL HybridLL1CheckedBound
.if CompilerDiagnosticReturns
            RET  C
.endif
            LD   (AggregateCandidateLength),HL
            LD   B,H
            LD   C,L
            LD   A,(AggregateCandidateAux)
            CALL AggregateGetExtent
            LD   D,H
            LD   E,L
            LD   HL,0
HybridLL1ArrayExtentLoop:
            ADD  HL,DE
            JP   C,AggregateProgramDataCapacityFailure
            CALL AggregateCheckExtentCapacity
.if CompilerDiagnosticReturns
            RET  C
.endif
            DEC  BC
            LD   A,B
            OR   C
            JR   NZ,HybridLL1ArrayExtentLoop
            LD   (AggregateCandidateExtent),HL
            LD   A,AggregateTypeKindArray
            LD   (AggregateCandidateKind),A
            JR   HybridLL1InternCurrentType

; --------------------------------------------------------- scalar constants

HybridLL1RetainDeclarationName .equ TypedRetainDeclarationName

HybridLL1SaveExpectedType:
            LD   (ExpressionExpectedType),A
            OR   A
            RET

.routine out A,DE,HL,carry,zero clobbers sign,parity,halfCarry,B,C,IX,IY
HybridLL1FinishConstantExpression:
            LD   HL,(ExpressionRightValue)
            LD   A,(ExpressionRightMeta)
            LD   D,A
            AND  ScalarMetaConstant
            JP   Z,TypedTypeFailure
            LD   A,D
            AND  ScalarMetaTypeMask
            CP   ScalarTypeBoolean
            LD   A,ScalarTypeExact
            JR   NZ,HybridLL1ConstantTypeReady
            LD   A,ScalarTypeBoolean
HybridLL1ConstantTypeReady:
            LD   (DeclarationInfo),A
            LD   HL,(ExpressionRightValue)
            LD   (DeclarationPayload),HL
            OR   A
            RET

.routine out A,BC,DE,HL,carry,zero clobbers sign,parity,halfCarry
HybridLL1CommitConstant:
            LD   A,(DeclarationInfo)
            OR   SymbolClassConstant
            LD   D,A
            LD   BC,(DeclarationPayload)
            CALL TypedPrepareCurrentWord
.if CompilerDiagnosticReturns
            RET  C
.endif
            JP   SymbolCommit

.routine out A,BC,DE,HL,carry,zero clobbers sign,parity,halfCarry,IX,IY
HybridLL1CommitAggregateConstant:
.if TargetStreamingOutput
            CALL TargetCurrentSourceBank
            LD   (DeclarationInfo),A
            CALL TargetBankRoLengthAddress
            PUSH HL
            LD   C,(HL)
            INC  HL
            LD   B,(HL)
            LD   (DeclarationPayload),BC
            LD   HL,(AggregateCurrentObjectExtent)
            ADD  HL,BC
            LD   E,L
            LD   D,H
            POP  HL
            LD   (HL),E
            INC  HL
            LD   (HL),D
            LD   A,(DeclarationInfo)
            RLCA
            RLCA
            RLCA
            RLCA
            OR   SymbolAggregateFlag+SymbolClassConstant
            LD   (DeclarationInfo),A
.endif
            LD   BC,(ReadOnlyImageLength)
            LD   D,SymbolAggregateFlag+SymbolClassConstant
.if TargetStreamingOutput
            LD   A,(DeclarationInfo)
            LD   D,A
            LD   BC,(DeclarationPayload)
.endif
            CALL TypedPrepareCurrentWord
.if CompilerDiagnosticReturns
            RET  C
.endif
            LD   BC,(ReadOnlyImageLength)
            LD   HL,(AggregateCurrentObjectExtent)
            ADD  HL,BC
            LD   DE,(StaticImageLength)
            ADD  HL,DE
            CALL AggregateCheckReadOnlyCapacity
.if CompilerDiagnosticReturns
            RET  C
.endif
            OR   A
            SBC  HL,DE
            LD   (ReadOnlyImageLength),HL
            LD   HL,StaticImageBase
            ADD  HL,DE
            ADD  HL,BC
            EX   DE,HL
            LD   HL,AggregateInitializerBase
            LD   BC,(AggregateCurrentObjectExtent)
            LDIR
            LD   A,(AggregateCurrentTypeId)
            JP   SymbolCommitTyped

HybridLL1BeginAssert .equ TypedRetainDeclarationNameReady

.routine out A,BC,DE,HL,carry,zero clobbers sign,parity,halfCarry
HybridLL1CommitAssert:
            CALL HybridLL1RestoreSubName
            LD   A,(ExpressionRightMeta)
            AND  ScalarMetaConstant+ScalarMetaTypeMask
            CP   ScalarMetaConstant+ScalarTypeBoolean
            JR   NZ,HybridLL1AssertTypeFailure
            LD   A,(ExpressionRightValue)
            OR   A
            RET  NZ
            CALL SetDiagInline
            .db  DiagnosticAssertionFailed
HybridLL1AssertTypeFailure:
            CALL SetDiagInline
            .db  DiagnosticTypeMismatch

; ------------------------------------------------------ program declarations

.routine out A,carry,zero clobbers sign,parity,halfCarry,B,C,D,DE,HL
HybridLL1SaveProgramType:
            LD   A,(AggregateCurrentTypeId)
HybridLL1SaveObjectType:
            CP   AggregateOpenStringTypeId
            JP   Z,AggregateTypeShapeFailure
            LD   (DeclarationInfo),A
            CALL AggregateGetExtent
            LD   (AggregateCurrentObjectExtent),HL
            LD   (AggregateCurrentObjectEnd),HL
            LD   HL,0
            LD   (AggregateCurrentObjectOffset),HL
            CALL AggregateZeroCurrentObject
.if CompilerDiagnosticReturns
            RET  C
.endif
            XOR  A
            LD   (AggregateInitializerDepth),A
            LD   (AggregateHasInitializer),A
            RET

.routine out A,carry,zero clobbers sign,parity,halfCarry,B,C,D,DE,HL,IX,IY
HybridLL1SaveAggregateConstantType:
            LD   A,(AggregateCurrentTypeId)
            CP   AggregateFirstDynamicTypeId
            JP   C,TypedTypeFailure
            JR   HybridLL1SaveObjectType

HybridLL1FinishProgramInitializer:
            LD   A,1
            LD   (AggregateHasInitializer),A
            LD   HL,(AggregateCurrentObjectOffset)
            LD   DE,(AggregateCurrentObjectEnd)
            OR   A
            SBC  HL,DE
            JP   NZ,AggregateInitializerCountFailure
            OR   A
            RET

.routine out A,BC,DE,HL,carry,zero clobbers sign,parity,halfCarry,IX,IY
HybridLL1CommitProgramVariable:
            LD   A,(AggregateHasInitializer)
            OR   A
            JR   Z,HybridLL1CommitBssObject
            JR   HybridLL1AllocateDataObject
HybridLL1CommitBssObject:
            JR   HybridLL1AllocateBssObject
HybridLL1CommitObjectReady:
            PUSH BC
            LD   A,(DeclarationInfo)
            CP   AggregateFirstDynamicTypeId
            JR   C,HybridLL1ProgramScalarInfo
            LD   D,SymbolInfoAggregateProgram
            JR   HybridLL1ProgramPrepareSymbol
HybridLL1ProgramScalarInfo:
            OR   SymbolClassProgram
            LD   D,A
HybridLL1ProgramPrepareSymbol:
            CALL TypedPrepareCurrentWord
            POP  BC
.if CompilerDiagnosticReturns
            RET  C
.endif
            LD   A,(DeclarationInfo)
            CALL SymbolCommitTyped
.if CompilerDiagnosticReturns
            RET  C
.endif
            OR   A
            RET

; Return the absolute target address of one initialized program object in BC.
; The complete prepared bytes are appended to the rodata-backed data image.
HybridLL1AllocateDataObject:
            LD   DE,(StaticImageLength)
            CALL HybridLL1AllocateObjectEnd
.if CompilerDiagnosticReturns
            RET  C
.endif
            PUSH HL
            LD   DE,(ReadOnlyImageLength)
            ADD  HL,DE
            CALL AggregateCheckExtentCapacity
            POP  HL
.if CompilerDiagnosticReturns
            RET  C
.endif
            LD   (StaticImageLength),HL
            LD   BC,(ReadOnlyImageLength)
            LD   A,B
            OR   C
            JR   Z,HybridLL1DataShiftReady
            LD   HL,StaticImageBase
            LD   DE,(AggregateCurrentObjectOffset)
            ADD  HL,DE
            ADD  HL,BC
            DEC  HL
            LD   DE,(AggregateCurrentObjectExtent)
            PUSH HL
            ADD  HL,DE
            EX   DE,HL
            POP  HL
            LDDR
HybridLL1DataShiftReady:
            LD   A,(DeclarationInfo)
            CALL AggregateGetExtent
            LD   B,H
            LD   C,L
            LD   HL,AggregateInitializerBase
            LD   DE,(AggregateCurrentObjectOffset)
            PUSH HL
            LD   HL,StaticImageBase
            ADD  HL,DE
            EX   DE,HL
            POP  HL
            LDIR
            LD   BC,(AggregateCurrentObjectOffset)
.if TargetStreamingOutput
            ; Target transcripts retain a segment-relative offset. Bit 15 is
            ; clear for initialized data and set for BSS.
.else
            LD   HL,ProgramDataBase
            ADD  HL,BC
            LD   B,H
            LD   C,L
.endif
            OR   A
            JR   HybridLL1CommitObjectReady

; Return the absolute target address of one default-initialized object in BC.
HybridLL1AllocateBssObject:
            LD   DE,(ProgramBssLength)
            CALL HybridLL1AllocateObjectEnd
.if CompilerDiagnosticReturns
            RET  C
.endif
            LD   (ProgramBssLength),HL
            LD   B,D
            LD   C,E
.if TargetStreamingOutput
            SET  7,B
.else
            LD   HL,ProgramBssBase
            ADD  HL,BC
            LD   B,H
            LD   C,L
.endif
            OR   A
            JP   HybridLL1CommitObjectReady

; Add the current object extent to the selected segment length in DE. Return
; the old offset in DE and the checked mathematical end in HL.
.routine in DE out A,DE,HL,carry,zero clobbers sign,parity,halfCarry
HybridLL1AllocateObjectEnd:
            LD   (AggregateCurrentObjectOffset),DE
            LD   A,(DeclarationInfo)
            CALL AggregateGetExtent
            LD   DE,(AggregateCurrentObjectOffset)
            ADD  HL,DE
HybridLL1CheckProgramSegmentEnd:
; Initialized data and BSS use the same exact 1 KiB extent rule and diagnostic
; as complete aggregate objects.
            JP   AggregateCheckExtentCapacity

; ---------------------------------------------------------- record metadata

.routine out A,carry,zero clobbers sign,parity,halfCarry,B,C,D,DE,HL
HybridLL1BeginRecord:
            CALL TypedRetainDeclarationName
.if CompilerDiagnosticReturns
            RET  C
.endif
            LD   A,(AggregateTypeCount)
            CP   AggregateTypeCapacity
            JP   NC,AggregateTypeCapacityFailure
            LD   A,(AggregateRecordCount)
            CP   AggregateRecordCapacity
            JP   NC,AggregateTypeCapacityFailure
            LD   A,(AggregateFieldCount)
            LD   (AggregateCurrentFieldStart),A
            XOR  A
            LD   (AggregateCurrentFieldCount),A
            LD   H,A
            LD   L,A
            LD   (AggregateCurrentRecordExtent),HL
            RET

.routine out A,carry,zero clobbers sign,parity,halfCarry,B,C,D,DE,HL
HybridLL1BeginRecordField:
            CALL AggregateCheckFieldDuplicate
.if CompilerDiagnosticReturns
            RET  C
.endif
            LD   A,(AggregateFieldCount)
            LD   B,A
            LD   A,(AggregateCurrentFieldCount)
            ADD  A,B
            CP   AggregateFieldCapacity
            JP   NC,AggregateTypeCapacityFailure
            PUSH AF
            CALL AggregateFieldAddress
            CALL TokenRetainNameAtHL
            POP  AF
            OR   A
            RET

.routine out A,carry,zero clobbers sign,parity,halfCarry,B,C,D,DE,HL
HybridLL1CommitRecordField:
            LD   A,(AggregateCurrentTypeId)
            CP   AggregateOpenStringTypeId
            JP   Z,AggregateTypeShapeFailure
            LD   A,(AggregateFieldCount)
            LD   B,A
            LD   A,(AggregateCurrentFieldCount)
            ADD  A,B
            CALL AggregateFieldAddress
            INC  HL
            INC  HL
            INC  HL
            LD   A,(AggregateCurrentTypeId)
            LD   (HL),A
            INC  HL
            LD   DE,(AggregateCurrentRecordExtent)
            LD   (HL),E
            INC  HL
            LD   (HL),D
            LD   A,(AggregateCurrentTypeId)
            PUSH DE
            CALL AggregateGetExtent
            POP  DE
            ADD  HL,DE
            JP   C,AggregateProgramDataCapacityFailure
            CALL AggregateCheckExtentCapacity
.if CompilerDiagnosticReturns
            RET  C
.endif
            LD   (AggregateCurrentRecordExtent),HL
            LD   HL,AggregateCurrentFieldCount
            INC  (HL)
            XOR  A
            RET

.routine out A,BC,DE,HL,carry,zero clobbers sign,parity,halfCarry
HybridLL1CommitRecord:
            LD   A,(AggregateCurrentFieldCount)
            OR   A
            JP   Z,AggregateRecordEmptyFailure
            LD   A,AggregateTypeKindRecord
            LD   (AggregateCandidateKind),A
            LD   A,(AggregateRecordCount)
            LD   (AggregateCandidateAux),A
            LD   HL,0
            LD   (AggregateCandidateLength),HL
            LD   HL,(AggregateCurrentRecordExtent)
            LD   (AggregateCandidateExtent),HL
            CALL AggregateAppendType
.if CompilerDiagnosticReturns
            RET  C
.endif
            LD   (AggregateCurrentTypeId),A
            LD   A,(AggregateRecordCount)
            ADD  A,A
            LD   E,A
            LD   D,0
            LD   HL,AggregateRecordTableBase
            ADD  HL,DE
            LD   A,(AggregateCurrentFieldStart)
            LD   (HL),A
            INC  HL
            LD   A,(AggregateCurrentFieldCount)
            LD   (HL),A
            LD   D,SymbolInfoRecordType
            LD   A,(AggregateCurrentTypeId)
            LD   C,A
            LD   B,0
            CALL TypedPrepareCurrentWord
.if CompilerDiagnosticReturns
            RET  C
.endif
            CALL SymbolCommit
.if CompilerDiagnosticReturns
            RET  C
.endif
            LD   A,(AggregateCurrentFieldCount)
            LD   HL,AggregateFieldCount
            ADD  A,(HL)
            LD   (HL),A
            LD   HL,AggregateRecordCount
            INC  (HL)
            XOR  A
            RET

; ----------------------------------------------------- Stage 7 routines/main

.routine out A,carry,zero clobbers sign,parity,halfCarry,DE,HL
HybridLL1RequireBeforeMain:
            LD   A,(Stage7CurrentRoutine)
            INC  A
            RET  NZ
            CALL SetDiagInline
            .db  DiagnosticExpectedEof

.routine out A,carry,zero clobbers sign,parity,halfCarry,B,C,DE,HL,IX,IY
HybridLL1RequireMain:
            LD   A,(Stage7CurrentRoutine)
            INC  A
            JR   Z,HybridLL1RequireOrdinaryForwards
            LD   A,(Stage8ForwardMainFlags)
            AND  Stage8RoutineIncomplete
            JR   NZ,HybridLL1IncompleteForward
            JR   HybridLL1MissingMain
HybridLL1RequireOrdinaryForwards:
            LD   A,(Stage7RoutineCount)
            LD   B,A
            XOR  A
            LD   C,A
HybridLL1RequireForwardLoop:
            LD   A,B
            OR   A
            RET  Z
            LD   A,C
            CALL Stage7RoutineAddress
            LD   DE,Stage7RoutineFlags
            ADD  HL,DE
            LD   A,(HL)
            AND  Stage8RoutineIncomplete
            JR   NZ,HybridLL1IncompleteForward
            INC  C
            DEC  B
            JR   HybridLL1RequireForwardLoop
HybridLL1MissingMain:
            CALL SetDiagInline
            .db  DiagnosticExpectedTopLevel
HybridLL1IncompleteForward:
            CALL SetDiagInline
            .db  DiagnosticForwardIncomplete

; The grammar deliberately treats the lexeme `main` as the same NAME token as
; ordinary routine names. This action is the one semantic discriminator.
.routine out A,BC,DE,HL,carry,zero clobbers sign,parity,halfCarry,IX,IY
HybridLL1RetainSubName:
            JP   TypedRetainDeclarationNameReady

.routine out A,BC,DE,HL,carry,zero clobbers sign,parity,halfCarry
HybridLL1RestoreSubName:
            CALL TypedRestoreDeclarationToken
            LD   HL,DeclarationNamePosition
            LD   DE,TokenStartOffset
            CALL CompilerCopyPosition
            OR   A
            RET

.routine out A,carry,zero clobbers sign,parity,halfCarry
HybridLL1ResetParametersAndResult:
            XOR  A
            LD   (Stage7CurrentParameterCount),A
            LD   (Stage7CurrentResultType),A
            RET

.routine out A,carry,zero clobbers sign,parity,halfCarry,B,C,D,DE,HL,IX,IY
HybridLL1BeginSub:
            CALL HybridLL1RestoreSubName
            CALL HybridLL1RequireBeforeMain
.if CompilerDiagnosticReturns
            RET  C
.endif
            CALL TypedNameEqualsMain
            JR   C,HybridLL1BeginMainSignature
            LD   A,(Stage7RoutineCount)
            CP   Stage7RoutineCapacity
            JR   NC,HybridLL1RoutineCapacityFailure
            CALL Stage7RejectCurrentDeclarationName
.if CompilerDiagnosticReturns
            RET  C
.endif
            LD   A,(Stage7RoutineCount)
            LD   (Stage7CurrentRoutine),A
            CALL Stage7RoutineAddress
            CALL TokenRetainNameAtHL
            INC  HL
            LD   A,(Stage7ParameterCount)
            LD   (HL),A
            LD   (Stage7CurrentParameterStart),A
            CALL HybridLL1ResetParametersAndResult
.if TargetStreamingOutput
            CALL TargetPackCurrentBank
.endif
            LD   (Stage7CurrentFlags),A
            RET
HybridLL1BeginMainSignature:
.if TargetStreamingOutput
            CALL TargetRequireEntrySourceBank
.if CompilerDiagnosticReturns
            RET  C
.endif
.endif
            LD   A,(Stage8ForwardMainFlags)
            AND  Stage8RoutineIncomplete
            JP   NZ,TypedDuplicateNameFailure
            CALL Stage7RejectCurrentDeclarationName
.if CompilerDiagnosticReturns
            RET  C
.endif
            LD   A,$FF
            LD   (Stage7CurrentRoutine),A
            CALL HybridLL1ResetParametersAndResult
            LD   A,Stage7RoutineMain
.if TargetStreamingOutput
            CALL TargetPackCurrentBank
.endif
            LD   (Stage7CurrentFlags),A
            RET
HybridLL1RoutineCapacityFailure:
            CALL SetDiagInline
            .db  DiagnosticRoutineCapacity

; A forward uses the ordinary signature builder, then publishes that sole
; signature without opening a body or emitting code.
.routine out A,carry,zero clobbers sign,parity,halfCarry,B,C,D,DE,HL,IX,IY
HybridLL1BeginForward:
            CALL HybridLL1BeginSub
.if CompilerDiagnosticReturns
            RET  C
.endif
            LD   A,(Stage7CurrentFlags)
            OR   Stage8RoutineIncomplete
            LD   (Stage7CurrentFlags),A
            OR   A
            RET

.routine out A,carry,zero clobbers sign,parity,halfCarry,B,C,D,DE,HL
HybridLL1CommitForward:
            LD   A,(Stage7CurrentRoutine)
            INC  A
            JR   Z,HybridLL1CommitForwardMain
            DEC  A
            CALL HybridLL1PublishRoutine
            XOR  A
            RET
HybridLL1CommitForwardMain:
            LD   A,(Stage7CurrentFlags)
            LD   (Stage8ForwardMainFlags),A
            XOR  A
            LD   (Stage7CurrentRoutine),A
            RET

.routine out A,carry,zero clobbers sign,parity,halfCarry,B,C,D,DE,HL,IX,IY
HybridLL1RetainParameter:
            LD   A,(Stage7CurrentRoutine)
            INC  A
            JR   Z,HybridLL1MainParameterFailure
            CALL Stage7CheckParameterDeclarationName
.if CompilerDiagnosticReturns
            RET  C
.endif
            LD   HL,DeclarationNamePointer
            CALL TokenRetainNameAtHL
.if TargetStreamingOutput
.if DebugHooks
            OUT  (DebugTraceDeclarationPort),A
.endif
.endif
            OR   A
            RET
HybridLL1MainParameterFailure:
            CALL SetDiagInline
            .db  DiagnosticExpectedRight

.routine out A,carry,zero clobbers sign,parity,halfCarry,B,C,D,DE,HL
HybridLL1CommitParameter:
            CALL TypedRestoreDeclarationToken
            LD   A,(AggregateCurrentTypeId)
            JP   Stage7AppendParameter

HybridLL1AllowSubResult:
            LD   A,(Stage7CurrentRoutine)
            INC  A
            JR   Z,HybridLL1SubSignatureLineFailure
            RET

HybridLL1SaveSubResult:
            LD   A,(AggregateCurrentTypeId)
            CP   AggregateOpenStringTypeId
            JP   Z,AggregateTypeShapeFailure
            LD   (Stage7CurrentResultType),A
            OR   A
            RET

HybridLL1MarkSubFails:
            LD   A,(Stage7CurrentFlags)
            OR   Stage7RoutineFails
            LD   (Stage7CurrentFlags),A
            OR   A
            RET
HybridLL1SubSignatureLineFailure:
            CALL SetDiagInline
            .db  DiagnosticExpectedLine

; Open the abbreviated body of one exact incomplete forward and recover its
; sole stored signature, including the original parameter spellings.
.routine out A,BC,DE,HL,carry,zero clobbers sign,parity,halfCarry,IX,IY
HybridLL1BeginForwardBody:
            CALL HybridLL1RestoreSubName
            CALL HybridLL1RequireBeforeMain
.if CompilerDiagnosticReturns
            RET  C
.endif
            CALL TypedNameEqualsMain
            JR   C,HybridLL1BeginForwardMainBody
            CALL Stage7FindRoutineCurrent
            JR   NZ,HybridLL1ForwardMissing
            LD   (Stage7CurrentRoutine),A
            CALL Stage7RoutineAddress
            LD   DE,Stage7RoutineParameterStart
            ADD  HL,DE
            LD   A,(HL)
            LD   (Stage7CurrentParameterStart),A
            INC  HL
            LD   A,(HL)
            LD   (Stage7CurrentParameterCount),A
            INC  HL
            LD   A,(HL)
            LD   (Stage7CurrentResultType),A
            INC  HL
            LD   A,(HL)
            LD   (Stage7CallLabel),A
            INC  HL
            LD   A,(HL)
            BIT  2,A
            JP   Z,TypedDuplicateNameFailure
.if TargetStreamingOutput
            LD   D,A
            PUSH AF
            PUSH HL
            CALL TargetRequireCurrentBank
.if CompilerDiagnosticBranches
            JR   C,HybridLL1ForwardBankFailure
.endif
            POP  HL
            POP  AF
.endif
            AND  $FB
            LD   (HL),A
            LD   (Stage7CurrentFlags),A
            JR   HybridLL1OpenRoutineBody
.if TargetStreamingOutput
.if CompilerDiagnosticBranches
HybridLL1ForwardBankFailure:
            POP  HL
            POP  AF
            SCF
            RET
.endif
.endif
HybridLL1BeginForwardMainBody:
.if TargetStreamingOutput
            CALL TargetRequireEntrySourceBank
.if CompilerDiagnosticReturns
            RET  C
.endif
.endif
            LD   A,(Stage8ForwardMainFlags)
            BIT  2,A
            JR   Z,HybridLL1ForwardMissing
            AND  $FB
            LD   (Stage7CurrentFlags),A
            LD   (Stage8ForwardMainFlags),A
            CALL HybridLL1ResetParametersAndResult
            DEC  A
            LD   (Stage7CurrentRoutine),A
            JP   HybridLL1BeginMainBody
HybridLL1ForwardMissing:
            CALL SetDiagInline
            .db  DiagnosticUnknownName

.routine out A,BC,DE,HL,carry,zero clobbers sign,parity,halfCarry,IX,IY
HybridLL1BeginSubBody:
            LD   A,(Stage7CurrentRoutine)
            INC  A
            JP   Z,HybridLL1BeginMainBody
            DEC  A
            CALL HybridLL1PublishRoutine
            JR   HybridLL1OpenRoutineBody

.routine in A out A,BC,DE,HL clobbers carry,zero,sign,parity,halfCarry
HybridLL1PublishRoutine:
            CALL Stage7RoutineAddress
            LD   DE,Stage7RoutineParameterCount
            ADD  HL,DE
            LD   A,(Stage7CurrentParameterCount)
            LD   (HL),A
            INC  HL
            LD   A,(Stage7CurrentResultType)
            LD   (HL),A
            INC  HL
            LD   A,(Stage7CurrentRoutine)
            ADD  A,Stage7RoutineLabelBase
            LD   (HL),A
            LD   (Stage7CallLabel),A
            INC  HL
            LD   A,(Stage7CurrentFlags)
            LD   (HL),A
            LD   HL,Stage7RoutineCount
            INC  (HL)
            RET
.routine out A,carry,zero clobbers sign,parity,halfCarry
HybridLL1SaveGlobalsResetLocals:
            LD   A,(SymbolCount)
            LD   (Stage7GlobalSymbolCount),A
            XOR  A
            LD   (NextLocalSlot),A
            LD   (ControlDepth),A
            RET
HybridLL1OpenRoutineBody:
            CALL HybridLL1SaveGlobalsResetLocals
            LD   A,(Stage7CurrentResultType)
            OR   A
            LD   A,ControlRoutineValue
            JR   NZ,HybridLL1RoutineKindReady
            XOR  A
HybridLL1RoutineKindReady:
            LD   (ControlRoutineKind),A
            LD   A,(Stage7CurrentResultType)
            LD   (ControlResultType),A
            LD   A,1
            LD   (ControlSequenceFallsThrough),A
.if TargetStreamingOutput
.if DebugHooks
            OUT  (DebugTraceRoutinePort),A
.endif
.endif
            LD   A,SemanticBeginGeneralRoutine
            CALL SemanticSinkOperation
.if CompilerDiagnosticReturns
            RET  C
.endif
            LD   A,(Stage7CallLabel)
            CALL SemanticSinkPut
.if CompilerDiagnosticReturns
            RET  C
.endif
            LD   A,(Stage7CurrentParameterCount)
            CALL SemanticSinkPut
.if CompilerDiagnosticReturns
            RET  C
.endif
.if TargetStreamingOutput
            LD   A,(Stage7CurrentFlags)
            CALL TargetUnpackBank
            CALL SemanticSinkPut
.if CompilerDiagnosticReturns
            RET  C
.endif
            LD   A,(Stage7CurrentParameterCount)
.endif
            LD   B,A
            LD   A,(Stage7CurrentParameterStart)
            LD   D,A
            XOR  A
            LD   E,A
HybridLL1InstallParameterLoop:
            LD   A,B
            OR   A
            RET  Z
            CALL Stage7ParameterSourceOffset
            LD   A,D
            PUSH DE
            PUSH BC
            CALL Stage7InstallParameter
            POP  BC
            POP  DE
.if CompilerDiagnosticReturns
            RET  C
.endif
            INC  D
            INC  E
            DEC  B
            JR   HybridLL1InstallParameterLoop

HybridLL1BeginMainBody:
            LD   A,(Stage7CurrentFlags)
            LD   (Stage8ForwardMainFlags),A
.if TargetStreamingOutput
.if DebugHooks
            OUT  (DebugTraceRoutinePort),A
.endif
.endif
            LD   A,SemanticBeginCallableMain
            CALL SemanticSinkOperation
.if CompilerDiagnosticReturns
            RET  C
.endif
            LD   A,(Stage7CurrentFlags)
            CALL SemanticSinkPut
.if CompilerDiagnosticReturns
            RET  C
.endif
.if TargetStreamingOutput
            LD   A,(Stage7CurrentFlags)
            CALL TargetUnpackBank
            CALL SemanticSinkPut
.if CompilerDiagnosticReturns
            RET  C
.endif
.endif
            CALL HybridLL1SaveGlobalsResetLocals
            LD   (Stage7CurrentResultType),A
            LD   (ControlRoutineKind),A

.routine out A,carry,zero clobbers sign,parity,halfCarry
HybridLL1SetFallsThrough:
            LD   A,1
            LD   (ControlSequenceFallsThrough),A
            OR   A
            RET

.routine out A,BC,DE,HL,carry,zero clobbers sign,parity,halfCarry,IX,IY
HybridLL1EndSub:
            LD   A,(Stage7CurrentRoutine)
            INC  A
            JR   Z,HybridLL1EndMainBody
            LD   A,(Stage7CurrentResultType)
            OR   A
            JR   Z,HybridLL1EndRoutineEmit
            LD   A,(ControlSequenceFallsThrough)
            OR   A
            JP   NZ,TypedRoutineFlowFailure
HybridLL1EndRoutineEmit:
.if TargetStreamingOutput
.if DebugHooks
            OUT  (DebugTraceContextPopPort),A
.endif
.endif
            CALL HybridLL1EmitRoutineEnd
.if CompilerDiagnosticReturns
            RET  C
.endif
            LD   A,(Stage7CurrentResultType)
            CALL SemanticSinkPut
.if CompilerDiagnosticReturns
            RET  C
.endif
            LD   A,(Stage7GlobalSymbolCount)
            LD   (SymbolCount),A
            XOR  A
            LD   (NextLocalSlot),A
            RET

.routine out A,carry,zero clobbers sign,parity,halfCarry,B,C,D,DE,HL
HybridLL1EmitRoutineEnd:
            LD   A,(Stage7CurrentFlags)
            AND  Stage7RoutineFails
            LD   A,SemanticEndGeneralRoutine
            JR   Z,HybridLL1EmitRoutineEndSelected
            LD   A,SemanticEndFailableRoutine
HybridLL1EmitRoutineEndSelected:
            JP   SemanticSinkOperation
HybridLL1EndMainBody:
.if TargetStreamingOutput
.if DebugHooks
            OUT  (DebugTraceContextPopPort),A
.endif
.endif
            CALL HybridLL1EmitRoutineEnd
.if CompilerDiagnosticReturns
            RET  C
.endif
            XOR  A
            JP   SemanticSinkPut

; ------------------------------------------------------ recoverable failure

.routine out A,carry,zero clobbers sign,parity,halfCarry,BC,DE,HL,IX,IY
HybridLL1BeginFail:
.if TargetStreamingOutput
.if DebugHooks
            OUT  (DebugTraceSourcePort),A
.endif
.endif
            LD   A,(Stage7CurrentFlags)
            AND  Stage7RoutineFails
            JR   Z,HybridLL1FailureContext
            LD   HL,(TokenStartOffset)
            LD   (Stage8FailureOffset),HL
            LD   A,ScalarTypeU8
            JP   HybridLL1SaveExpectedType

.routine out A,BC,DE,HL,carry,zero clobbers sign,parity,halfCarry,IX,IY
HybridLL1CommitFail:
            LD   E,ScalarTypeU8
            CALL HybridLL1CheckFailureResult
.if CompilerDiagnosticReturns
            RET  C
.endif
            LD   A,SemanticFailRoutine
HybridLL1FailOperationReady:
            CALL SemanticSinkOperation
.if CompilerDiagnosticReturns
            RET  C
.endif
            LD   HL,(Stage8FailureOffset)
            LD   A,L
.if CompilerDiagnosticReturns
            PUSH HL
            CALL SemanticSinkPut
            POP  HL
.else
            CALL SemanticSinkPutPreserveHL
.endif
.if CompilerDiagnosticReturns
            RET  C
.endif
            LD   A,H
            CALL SemanticSinkPut
.if CompilerDiagnosticReturns
            RET  C
.endif
HybridLL1NoFallthrough:
            XOR  A
            LD   (ControlSequenceFallsThrough),A
            RET

; Validate one scalar fail/return value and reject an unconsumed nested
; recoverable failure.
.routine in E out A,DE,HL,carry,zero clobbers sign,parity,halfCarry,B,C,IX,IY
HybridLL1CheckFailureResult:
            LD   A,(ExpressionRightMeta)
            LD   HL,(ExpressionRightValue)
            CALL TypedCheckAssignable
.if CompilerDiagnosticReturns
            RET  C
.endif
            JP   Stage8RequireNoPendingFailure
.routine out A,carry,zero clobbers sign,parity,halfCarry,BC,DE,HL,IX,IY
HybridLL1FailureContext:
            CALL SetDiagInline
            .db  DiagnosticFailureContext

.routine out A,BC,DE,HL,carry,zero clobbers sign,parity,halfCarry
; Both callers have already observed a nonzero Stage8DirectFailable. The
; generic entry checks the token; the selected entry reuses its caller's peek.
Stage8ConsumePropagation:
            CALL ParserPeek
.if CompilerDiagnosticReturns
            RET  C
.endif
            CP   TokenElse
            JR   NZ,HybridLL1FailureContext
Stage8ConsumePropagationSelected:
            LD   A,(Stage7CurrentFlags)
            AND  Stage7RoutineFails
            JR   Z,HybridLL1FailureContext
            CALL ParserTake
.if CompilerDiagnosticReturns
            RET  C
.endif
            LD   E,TokenFail
            CALL ParserExpect
.if CompilerDiagnosticReturns
            RET  C
.endif
            CALL ParserPeek
.if CompilerDiagnosticReturns
            RET  C
.endif
            CP   TokenHandle
            JR   Z,HybridLL1FailureContext
            CP   TokenElse
            JR   Z,HybridLL1FailureContext
            LD   A,Stage8CallModePropagateRoutine
Stage8PropagationModeReady:
            LD   HL,(Stage8CallModePointer)
            LD   (HL),A
            INC  HL
            INC  HL
            LD   A,(Stage8RetainedCarriers)
            LD   (HL),A
Stage8ClearPendingFailure:
            XOR  A
            LD   (Stage8DirectFailable),A
            LD   (Stage8RetainedCarriers),A
            RET

.routine out A,BC,DE,HL,carry,zero clobbers sign,parity,halfCarry
Stage8SelectFailureConsumer:
            LD   A,(Stage8DirectFailable)
            OR   A
            JR   NZ,Stage8SelectPendingFailure
            LD   (Stage8RetainedCarriers),A
            CALL ParserPeek
.if CompilerDiagnosticReturns
            RET  C
.endif
            CP   TokenElse
            JR   Z,HybridLL1FailureContext
            CP   TokenHandle
            JR   Z,HybridLL1FailureContext
            OR   A
            RET
Stage8SelectPendingFailure:
            CALL ParserPeek
.if CompilerDiagnosticReturns
            RET  C
.endif
            CP   TokenElse
            JR   Z,Stage8ConsumePropagationSelected
            CP   TokenHandle
            JR   NZ,HybridLL1FailureContext
            LD   B,ControlKindHandler
            CALL HybridLL1PushFlowFrameAndLabelA
.if CompilerDiagnosticReturns
            RET  C
.endif
            CALL ControlAllocateExit
.if CompilerDiagnosticReturns
            RET  C
.endif
            LD   HL,(Stage8CallModePointer)
            LD   (HL),Stage8CallModeHandle
            LD   B,ControlFrameLabelA
            CALL ControlTopFrameField
            LD   C,(HL)
            LD   HL,(Stage8CallModePointer)
            INC  HL
            LD   (HL),C
            INC  HL
            LD   A,(Stage8RetainedCarriers)
            LD   (HL),A
            JR   Stage8ClearPendingFailure

.routine out A,BC,DE,HL,carry,zero clobbers sign,parity,halfCarry,IX,IY
HybridLL1LookupDeclaration:
            CALL SymbolLookupCurrent
.if CompilerDiagnosticReturns
            RET  C
.endif
            LD   (DeclarationInfo),A
            LD   (DeclarationPayload),BC
            LD   D,A
            RET

.routine out A,BC,DE,HL,carry,zero clobbers sign,parity,halfCarry,IX,IY
HybridLL1BeginHandle:
.if TargetStreamingOutput
.if DebugHooks
            OUT  (DebugTraceSourcePort),A
            OUT  (DebugTraceContextPushPort),A
.endif
.endif
            CALL HybridLL1LookupDeclaration
.if CompilerDiagnosticReturns
            RET  C
.endif
            CALL TypedRequireScalarSymbolClass
.if CompilerDiagnosticReturns
            RET  C
.endif
            JP   Z,TypedTypeFailure
            CP   SymbolClassLocal
            JR   NZ,Stage8HandlerCounterReady
            CALL ControlCheckActiveCounter
.if CompilerDiagnosticReturns
            RET  C
.endif
Stage8HandlerCounterReady:
            CALL TypedDeclarationScalarType
            CP   ScalarTypeU8
            JP   NZ,TypedTypeFailure
            LD   B,ControlFrameExit
            CALL ControlTopFrameField
            LD   C,(HL)
            LD   A,SemanticSkipHandler
            CALL Stage8EmitOperationLabel
.if CompilerDiagnosticReturns
            RET  C
.endif
            LD   B,ControlFrameLabelA
            CALL ControlTopFrameField
            LD   C,(HL)
            LD   A,SemanticBeginHandler
            CALL Stage8EmitOperationLabel
.if CompilerDiagnosticReturns
            RET  C
.endif
            LD   A,(DeclarationInfo)
            CALL SemanticSinkPut
.if CompilerDiagnosticReturns
            RET  C
.endif
            AND  SymbolClassMask
            CP   SymbolClassProgram
            LD   HL,(DeclarationPayload)
            JR   Z,HybridLL1BeginHandleProgramPayload
            LD   A,L
            CALL SemanticSinkPut
            JR   HybridLL1BeginHandlePayloadReady
HybridLL1BeginHandleProgramPayload:
            CALL Stage7EmitWord
HybridLL1BeginHandlePayloadReady:
.if CompilerDiagnosticReturns
            RET  C
.endif
            JP   HybridLL1SetFallsThrough

.routine in A,C out A,carry,zero clobbers sign,parity,halfCarry,B,DE,HL
Stage8EmitOperationLabel:
            CALL SemanticSinkOperation
.if CompilerDiagnosticReturns
            RET  C
.endif
            LD   A,C
            JP   SemanticSinkPut

.routine out A,BC,DE,HL,carry,zero clobbers sign,parity,halfCarry,IX,IY
HybridLL1EndHandle:
.if TargetStreamingOutput
.if DebugHooks
            OUT  (DebugTraceContextPopPort),A
.endif
.endif
            LD   B,ControlFrameExit
            CALL ControlTopFrameField
            LD   C,(HL)
            LD   A,SemanticEndHandler
            CALL Stage8EmitOperationLabel
.if CompilerDiagnosticReturns
            RET  C
.endif
            LD   A,1
            JP   HybridLL1CombineFlow

.routine out A,carry,zero clobbers sign,parity,halfCarry,BC,DE,HL,IX,IY
Stage8RequireNoPendingFailure:
            LD   A,(Stage8DirectFailable)
            OR   A
            RET  Z
            JP   HybridLL1FailureContext

; ------------------------------------------------------------- local scalars

.routine out A,BC,DE,HL,carry,zero clobbers sign,parity,halfCarry
HybridLL1SaveLocalType:
.if TargetStreamingOutput
.if DebugHooks
            OUT  (DebugTraceSourcePort),A
.endif
.endif
            LD   A,(AggregateCurrentTypeId)
            OR   SymbolClassLocal
            LD   (DeclarationInfo),A
            LD   A,(NextLocalSlot)
            LD   C,A
            LD   B,0
            LD   (DeclarationPayload),BC
            PUSH BC
            LD   A,(DeclarationInfo)
            LD   D,A
            CALL TypedPrepareCurrentWord
            POP  BC
.if CompilerDiagnosticReturns
            RET  C
.endif
            CALL TypedDeclarationScalarType
            CALL TypedEmitLocalDeclare
HybridLL1SetLocalExpectedType:
.if CompilerDiagnosticReturns
            RET  C
.endif
            CALL TypedDeclarationScalarType
            JP   HybridLL1SaveExpectedType

HybridLL1BeginLocalInitializer:
            CALL TypedDeclarationScalarType
            JP   HybridLL1SaveExpectedType

.routine out A,BC,DE,HL,carry,zero clobbers sign,parity,halfCarry
HybridLL1DefaultLocalInitializer:
            LD   A,1
            LD   (ExpressionEmitEnabled),A
            LD   A,SemanticLiteral16
            CALL TypedEmitOperation
.if CompilerDiagnosticReturns
            RET  C
.endif
            LD   HL,0
            CALL TypedEmitWord
.if CompilerDiagnosticReturns
            RET  C
.endif
            CALL TypedDeclarationScalarType
            OR   ScalarMetaConstant
            LD   (ExpressionRightMeta),A
            LD   HL,0
            LD   (ExpressionRightValue),HL
            OR   A
            RET

.routine out A,DE,HL,carry,zero clobbers sign,parity,halfCarry,B,C,IX,IY
HybridLL1FinishLocalInitializer:
            CALL HybridLL1ValidateDeclarationExpression
.if CompilerDiagnosticReturns
            RET  C
.endif
            LD   A,(Stage8DirectFailable)
            OR   A
            JP   NZ,Stage8ConsumePropagation
            CALL ParserPeek
.if CompilerDiagnosticReturns
            RET  C
.endif
            CP   TokenElse
            JP   Z,HybridLL1FailureContext
            OR   A
            RET

.routine out A,DE,HL,carry,zero clobbers sign,parity,halfCarry,B,C,IX,IY
HybridLL1ValidateDeclarationExpression:
            CALL TypedDeclarationScalarType
            LD   E,A

.routine in E out A,DE,HL,carry,zero clobbers sign,parity,halfCarry,B,C,IX,IY
HybridLL1CheckExpressionAssignable:
            LD   HL,(ExpressionRightValue)
            LD   A,(ExpressionRightMeta)
            JP   TypedCheckAssignable

.routine out A,BC,DE,HL,carry,zero clobbers sign,parity,halfCarry,IX,IY
HybridLL1CommitLocal:
            LD   A,(DeclarationInfo)
            LD   D,A
            LD   A,(DeclarationPayload)
            LD   C,A
            CALL TypedEmitStoreByInfo
.if CompilerDiagnosticReturns
            RET  C
.endif
            CALL SymbolCommit
.if CompilerDiagnosticReturns
            RET  C
.endif
            CALL TypedDeclarationScalarType
            CALL TypedTypeWidth
            LD   HL,NextLocalSlot
            ADD  A,(HL)
            LD   (HL),A
            OR   A
            RET

; ------------------------------------------------------------ simple statements

.routine out A,BC,DE,HL,carry,zero clobbers sign,parity,halfCarry,IX,IY
HybridLL1NameStatement:
.if TargetStreamingOutput
.if DebugHooks
            OUT  (DebugTraceSourcePort),A
.endif
.endif
            CALL ParserTake
.if CompilerDiagnosticReturns
            RET  C
.endif
            LD   HL,(TokenStartOffset)
            LD   (ExpressionCallOffset),HL
            LD   (Stage7CallOffset),HL
            CALL Stage8MatchPredefinedCurrent
            JR   NC,HybridLL1OrdinaryNameStatement
            CP   Stage8PredefinedConstantBase
            JP   NC,TypedTypeFailure
            LD   C,0
            CALL Stage8ParseServiceCall
.if CompilerDiagnosticReturns
            RET  C
.endif
            JP   Stage8SelectFailureConsumer
HybridLL1OrdinaryNameStatement:
            CALL Stage7FindRoutineCurrent
            JR   NZ,HybridLL1ParseAssignment
            LD   C,0
            CALL Stage7ParseCall
.if CompilerDiagnosticReturns
            RET  C
.endif
            JP   Stage8SelectFailureConsumer
HybridLL1ParseAssignment:
            CALL HybridLL1LookupDeclaration
.if CompilerDiagnosticReturns
            RET  C
.endif
            AND  SymbolAggregateFlag
            JP   NZ,Stage7ParseAggregateAssignment
            LD   A,D
            CALL TypedRequireScalarSymbolClass
.if CompilerDiagnosticReturns
            RET  C
.endif
            CP   SymbolClassLocal
            JR   NZ,HybridLL1StatementCounterChecked
            CALL ControlCheckActiveCounter
.if CompilerDiagnosticReturns
            RET  C
.endif
HybridLL1StatementCounterChecked:
            LD   A,D
            AND  SymbolClassMask
            JP   Z,TypedTypeFailure
            CALL ParserExpectEqual
.if CompilerDiagnosticReturns
            RET  C
.endif
            CALL TypedDeclarationScalarType
            CALL TypedExpressionBeginRuntime
.if CompilerDiagnosticReturns
            RET  C
.endif
            LD   D,A
            CALL TypedDeclarationScalarType
            LD   E,A
            LD   A,D
            CALL TypedCheckAssignable
.if CompilerDiagnosticReturns
            RET  C
.endif
            CALL Stage8SelectFailureConsumer
.if CompilerDiagnosticReturns
            RET  C
.endif
            LD   BC,(DeclarationPayload)
            LD   A,(DeclarationInfo)
            LD   D,A
            JP   TypedEmitStoreByInfo
HybridLL1BeginReturnValue:
.if TargetStreamingOutput
.if DebugHooks
            OUT  (DebugTraceSourcePort),A
.endif
.endif
            LD   A,(Stage7CurrentResultType)
            OR   A
            RET  Z
            CP   AggregateFirstDynamicTypeId
            RET  NC
            JP   HybridLL1SaveExpectedType

.routine out A,BC,DE,HL,carry,zero clobbers sign,parity,halfCarry,IX,IY
HybridLL1ReturnValue:
            LD   A,(Stage7CurrentResultType)
            OR   A
            JP   Z,TypedRoutineFlowFailure
            CP   AggregateFirstDynamicTypeId
            JR   NC,HybridLL1ReturnAggregateValue
            CALL TypedExpressionBeginRuntime
            JP   HybridLL1SaveExpressionResult
HybridLL1ReturnAggregateValue:
            CALL Stage7ParseAggregateValue
.if CompilerDiagnosticReturns
            RET  C
.endif
            LD   (Stage7PathType),A
            OR   A
            RET

HybridLL1CommitReturn:
            LD   A,(Stage7CurrentResultType)
            OR   A
            JP   Z,TypedRoutineFlowFailure
            CP   AggregateFirstDynamicTypeId
            JR   NC,HybridLL1CommitAggregateReturn
            LD   E,A
            CALL HybridLL1CheckFailureResult
.if CompilerDiagnosticReturns
            RET  C
.endif
            LD   A,(Stage7CurrentFlags)
            AND  Stage7RoutineFails
            LD   A,SemanticReturnScalar
            JR   Z,HybridLL1ReturnScalarSelected
            LD   A,SemanticReturnFailableScalar
HybridLL1ReturnScalarSelected:
            CALL SemanticSinkOperation
.if CompilerDiagnosticReturns
            RET  C
.endif
            JR   HybridLL1ReturnCommitted
HybridLL1CommitAggregateReturn:
            LD   D,A
            LD   A,(Stage7PathType)
            CP   D
            JP   NZ,TypedTypeFailure
            CALL Stage8RequireNoPendingFailure
.if CompilerDiagnosticReturns
            RET  C
.endif
            LD   A,(Stage7CurrentFlags)
            AND  Stage7RoutineFails
            LD   A,SemanticReturnAggregate
            JR   Z,HybridLL1ReturnAggregateSelected
            LD   A,SemanticReturnFailableAggregate
HybridLL1ReturnAggregateSelected:
            CALL SemanticSinkOperation
.if CompilerDiagnosticReturns
            RET  C
.endif
HybridLL1ReturnCommitted:
            JP   HybridLL1NoFallthrough

.routine out A,BC,DE,HL,carry,zero clobbers sign,parity,halfCarry,IX,IY
HybridLL1CommitBareReturn:
            LD   A,(Stage7CurrentResultType)
            OR   A
            JP   NZ,TypedRoutineFlowFailure
            CALL HybridLL1EmitRoutineEnd
.if CompilerDiagnosticReturns
            RET  C
.endif
            XOR  A
            CALL SemanticSinkPut
.if CompilerDiagnosticReturns
            RET  C
.endif
            JR   HybridLL1ReturnCommitted

; A is the logical action ordinal. The two ordinals and tokens are contiguous.
HybridLL1EmitTransferAction:
.if TargetStreamingOutput
.if DebugHooks
            OUT  (DebugTraceSourcePort),A
.endif
.endif
            DEC  A
HybridLL1EmitTransfer:
            LD   (DeclarationInfo),A
            CALL ControlFindLoop
.if CompilerDiagnosticReturns
            RET  C
.endif
            LD   DE,ControlFrameExit
            LD   A,(DeclarationInfo)
            CP   TokenExit
            JR   Z,HybridLL1TransferSelected
            LD   DE,ControlFrameContinue
HybridLL1TransferSelected:
            ADD  HL,DE
            LD   C,(HL)
            JP   ControlEmitJump

; ---------------------------------------------------------- structured flow

; Save the enclosing statement sequence's fallthrough bit, then push the
; control-frame kind supplied in B.
.routine in B out A,DE,HL,carry,zero clobbers sign,parity,halfCarry,B,C
HybridLL1PushFlowFrame:
            LD   A,(ControlDepth)
            CP   ControlFrameCapacity
            JP   NC,ControlCapacityFailure
            CALL HybridLL1FlowAddress
            LD   A,(ControlSequenceFallsThrough)
            LD   (HL),A
            LD   A,B
            JP   ControlPushFrame

.routine out A,DE,HL clobbers carry,zero,sign,parity,halfCarry
HybridLL1FlowAddress:
            LD   A,(ControlDepth)
            LD   E,A
            LD   D,0
            LD   HL,HybridLL1FlowStackBase
            ADD  HL,DE
            RET

; The frame has already been popped. Restore its enclosing sequence bit.
.routine out A,DE,HL,carry,zero clobbers sign,parity,halfCarry,B,C
HybridLL1RestoreFlow:
            CALL HybridLL1FlowAddress
            LD   A,(HL)
            LD   (ControlSequenceFallsThrough),A
            OR   A
            RET

; A is the completed compound statement's fallthrough bit.
.routine in A out A,DE,HL,carry,zero clobbers sign,parity,halfCarry,B,C
HybridLL1CombineFlow:
            LD   B,A
            CALL ControlPopFrame
.if CompilerDiagnosticReturns
            RET  C
.endif
            CALL HybridLL1FlowAddress
            LD   A,(HL)
            AND  B
            LD   (ControlSequenceFallsThrough),A
            OR   A
            RET

.routine out A,BC,DE,HL,carry,zero clobbers sign,parity,halfCarry,IX,IY
HybridLL1CheckBooleanResult:
            LD   E,ScalarTypeBoolean
HybridLL1CheckTypedResult:
            CALL Stage8RequireNoPendingFailure
.if CompilerDiagnosticReturns
            RET  C
.endif
            JP   HybridLL1CheckExpressionAssignable

.routine out A,BC,DE,HL,carry,zero clobbers sign,parity,halfCarry,IX,IY
HybridLL1BeginIf:
.if TargetStreamingOutput
.if DebugHooks
            OUT  (DebugTraceSourcePort),A
            OUT  (DebugTraceContextPushPort),A
.endif
.endif
            LD   B,ControlKindIf
            CALL HybridLL1PushFlowFrame
.if CompilerDiagnosticReturns
            RET  C
.endif
            CALL ControlAllocateExit
.if CompilerDiagnosticReturns
            RET  C
.endif
            CALL ControlAllocateLabelA
.if CompilerDiagnosticReturns
            RET  C
.endif
            LD   DE,ControlFrameCounter-ControlFrameLabelA
            ADD  HL,DE
            LD   (HL),1
HybridLL1ExpectBoolean:
            LD   A,ScalarTypeBoolean
            JP   HybridLL1SaveExpectedType

.routine out A,BC,DE,HL,carry,zero clobbers sign,parity,halfCarry,IX,IY
HybridLL1BeginIfBody:
            CALL HybridLL1CheckBooleanResult
.if CompilerDiagnosticReturns
            RET  C
.endif
            LD   B,ControlFrameLabelA

.routine in B out A,BC,DE,HL,carry,zero clobbers sign,parity,halfCarry,IX,IY
HybridLL1BeginConditionBody:
            CALL ControlTopFrameField
.if CompilerDiagnosticReturns
            RET  C
.endif
            LD   C,(HL)
            CALL ControlEmitBranchFalse
HybridLL1CheckedSetFallsThrough:
.if CompilerDiagnosticReturns
            RET  C
.endif
            JP   HybridLL1SetFallsThrough

.routine out A,BC,DE,HL,carry,zero clobbers sign,parity,halfCarry,IX,IY
HybridLL1BeginBranchClause:
            CALL StructuredRecordIfClause
.if CompilerDiagnosticReturns
            RET  C
.endif
            LD   B,ControlFrameExit
            CALL ControlTopFrameField
            LD   C,(HL)
            CALL ControlEmitJump
.if CompilerDiagnosticReturns
            RET  C
.endif
            CALL ControlTopFrame
            INC  HL
            LD   C,(HL)
            JP   ControlEmitLabel

.routine out A,BC,DE,HL,carry,zero clobbers sign,parity,halfCarry,IX,IY
HybridLL1BeginElseIf:
.if TargetStreamingOutput
.if DebugHooks
            OUT  (DebugTraceSourcePort),A
.endif
.endif
            CALL HybridLL1BeginBranchClause
.if CompilerDiagnosticReturns
            RET  C
.endif
            CALL ControlAllocateLabelA
.if CompilerDiagnosticReturns
            RET  C
.endif
            JR   HybridLL1ExpectBoolean

.routine out A,BC,DE,HL,carry,zero clobbers sign,parity,halfCarry,IX,IY
HybridLL1BeginElse:
.if TargetStreamingOutput
.if DebugHooks
            OUT  (DebugTraceSourcePort),A
.endif
.endif
            CALL HybridLL1BeginBranchClause
            JR   HybridLL1CheckedSetFallsThrough

.routine out A,DE,HL,carry,zero clobbers sign,parity,halfCarry,B,C
HybridLL1FinishElse:
            CALL StructuredRecordIfClause
.if CompilerDiagnosticReturns
            RET  C
.endif
            LD   B,ControlFrameMode
            CALL ControlTopFrameField
            LD   (HL),1
            XOR  A
            RET

.routine out A,BC,DE,HL,carry,zero clobbers sign,parity,halfCarry,IX,IY
HybridLL1FinishIfClauses:
            CALL StructuredRecordIfClause
.if CompilerDiagnosticReturns
            RET  C
.endif
            CALL ControlTopFrame
            INC  HL
            LD   C,(HL)
            JP   ControlEmitLabel

; B selects a field in the active control frame. All callers have already
; established that frame; the helper preserves their existing precondition.
.routine in B out A,BC,DE,HL,carry,zero clobbers sign,parity,halfCarry,IX,IY
HybridLL1EmitFrameLabel:
            CALL ControlTopFrameField
            LD   C,(HL)
            JP   ControlEmitLabel

.routine out A,BC,DE,HL,carry,zero clobbers sign,parity,halfCarry,IX,IY
HybridLL1EndIf:
.if TargetStreamingOutput
.if DebugHooks
            OUT  (DebugTraceContextPopPort),A
.endif
.endif
            LD   B,ControlFrameExit
            CALL HybridLL1EmitFrameLabel
.if CompilerDiagnosticReturns
            RET  C
.endif
            CALL ControlTopFrame
            PUSH HL
            LD   DE,ControlFrameCounter
            ADD  HL,DE
            LD   A,(HL)
            POP  HL
            LD   DE,ControlFrameMode
            ADD  HL,DE
            AND  (HL)
            XOR  1
            JP   HybridLL1CombineFlow

.routine out A,BC,DE,HL,carry,zero clobbers sign,parity,halfCarry,IX,IY
HybridLL1BeginWhile:
.if TargetStreamingOutput
.if DebugHooks
            OUT  (DebugTraceSourcePort),A
            OUT  (DebugTraceContextPushPort),A
.endif
.endif
            LD   B,ControlKindWhile
            CALL HybridLL1PushFlowFrameAndLabelA
.if CompilerDiagnosticReturns
            RET  C
.endif
            INC  HL
            LD   (HL),C
            CALL ControlAllocateExit
.if CompilerDiagnosticReturns
            RET  C
.endif
            CALL ControlTopFrame
            INC  HL
            LD   C,(HL)
            CALL ControlEmitLabel
.if CompilerDiagnosticReturns
            RET  C
.endif
            JP   HybridLL1ExpectBoolean

.routine out A,BC,DE,HL,carry,zero clobbers sign,parity,halfCarry,IX,IY
HybridLL1BeginWhileBody:
            CALL HybridLL1CheckBooleanResult
.if CompilerDiagnosticReturns
            RET  C
.endif
            LD   B,ControlFrameExit
            JP   HybridLL1BeginConditionBody

.routine out A,BC,DE,HL,carry,zero clobbers sign,parity,halfCarry,IX,IY
HybridLL1EndWhile:
.if TargetStreamingOutput
.if DebugHooks
            OUT  (DebugTraceContextPopPort),A
.endif
.endif
            LD   B,ControlFrameContinue
            CALL ControlTopFrameField
            LD   C,(HL)
            CALL ControlEmitJump
.if CompilerDiagnosticReturns
            RET  C
.endif
            LD   B,ControlFrameExit
            CALL HybridLL1EmitFrameLabel
.if CompilerDiagnosticReturns
            RET  C
.endif
HybridLL1PopAndRestoreFlow:
            CALL ControlPopFrame
.if CompilerDiagnosticReturns
            RET  C
.endif
            JP   HybridLL1RestoreFlow

; -------------------------------------------------------------- counted loop

.routine out A,BC,DE,HL,carry,zero clobbers sign,parity,halfCarry,IX,IY
HybridLL1BeginFor:
.if TargetStreamingOutput
.if DebugHooks
            OUT  (DebugTraceSourcePort),A
            OUT  (DebugTraceContextPushPort),A
.endif
.endif
            LD   HL,(TokenStartOffset)
            LD   (HybridLL1ForOffset),HL
            CALL HybridLL1LookupDeclaration
.if CompilerDiagnosticReturns
            RET  C
.endif
            AND  SymbolClassMask
            CP   SymbolClassLocal
            JP   NZ,StructuredCounterFailure
            LD   A,D
            AND  ScalarMetaTypeMask
            CP   ScalarTypeBoolean
            JP   Z,StructuredCounterFailure
            CALL ControlCheckActiveCounter
            JP   HybridLL1SetLocalExpectedType

HybridLL1CheckForInitial:
            CALL HybridLL1ValidateDeclarationExpression
.if CompilerDiagnosticReturns
            RET  C
.endif
            JP   Stage8RequireNoPendingFailure

; A is the logical action ordinal for the contiguous to/until family.
HybridLL1SelectForBoundAction:
            AND  1
HybridLL1ForBoundSelected:
            LD   (HybridLL1ForMode),A
            CALL HybridLL1FinishLocalInitializer
.if CompilerDiagnosticReturns
            RET  C
.endif
            JP   HybridLL1ExpectU16

.routine out A,DE,HL,carry,zero clobbers sign,parity,halfCarry,B,C,IX,IY
HybridLL1CheckForBound:
            LD   E,ScalarTypeU16
            JP   HybridLL1CheckTypedResult

HybridLL1SaveForStep .equ HybridLL1CheckForBound

HybridLL1DefaultForStep:
            CALL HybridLL1CheckForBound
.if CompilerDiagnosticReturns
            RET  C
.endif
            LD   DE,1
            LD   (HybridLL1ForStep),DE
            XOR  A
            RET

.routine out A,BC,DE,HL,carry,zero clobbers sign,parity,halfCarry,IX,IY
HybridLL1BeginForBody:
            LD   B,ControlKindFor
            CALL HybridLL1PushFlowFrameAndLabelA
.if CompilerDiagnosticReturns
            RET  C
.endif
            LD   B,ControlFrameContinue
            CALL ControlAllocateInto
.if CompilerDiagnosticReturns
            RET  C
.endif
            CALL ControlAllocateExit
.if CompilerDiagnosticReturns
            RET  C
.endif
            LD   B,ControlFrameCounter
            CALL ControlTopFrameField
            LD   A,(DeclarationPayload)
            LD   (HL),A
            INC  HL
            CALL TypedDeclarationScalarType
            CP   ScalarTypeU16
            LD   A,(HybridLL1ForMode)
            JR   NZ,HybridLL1ForModeReady
            SET  2,A
HybridLL1ForModeReady:
            LD   (HL),A
            INC  HL
            LD   DE,(HybridLL1ForStep)
            LD   (HL),E
            INC  HL
            LD   (HL),D
            INC  HL
            LD   DE,(HybridLL1ForOffset)
            LD   (HL),E
            INC  HL
            LD   (HL),D
            CALL ControlTopFrame
            CALL StructuredEmitForSetup
.if CompilerDiagnosticReturns
            RET  C
.endif
            CALL ControlTopFrame
            INC  HL
            LD   C,(HL)
            CALL ControlEmitLabel
.if CompilerDiagnosticReturns
            RET  C
.endif
            CALL StructuredEmitForTest
            JP   HybridLL1CheckedSetFallsThrough

.routine out A,BC,DE,HL,carry,zero clobbers sign,parity,halfCarry,IX,IY
HybridLL1EndFor:
.if TargetStreamingOutput
.if DebugHooks
            OUT  (DebugTraceContextPopPort),A
.endif
.endif
            LD   B,ControlFrameContinue
            CALL HybridLL1EmitFrameLabel
.if CompilerDiagnosticReturns
            RET  C
.endif
            CALL StructuredEmitForNext
.if CompilerDiagnosticReturns
            RET  C
.endif
            LD   B,ControlFrameExit
            CALL HybridLL1EmitFrameLabel
.if CompilerDiagnosticReturns
            RET  C
.endif
            LD   A,SemanticForCleanup
            CALL SemanticSinkOperation
.if CompilerDiagnosticReturns
            RET  C
.endif
            JP   HybridLL1PopAndRestoreFlow
HybridLL1ActionsEnd:
