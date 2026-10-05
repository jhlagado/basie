; Predictive aggregate paths, bounded routine signatures, forwards, and the
; predefined Stage 8 service surface. Runtime carriers are never entered in
; the source symbol model as integers.

.routine in A out A,HL,carry,zero clobbers sign,parity,halfCarry,DE
Stage7RoutineAddress:
            LD   L,A
            LD   H,0
            ADD  HL,HL
            ADD  HL,HL
            ADD  HL,HL
            LD   DE,Stage7RoutineTableBase
            ADD  HL,DE
            OR   A
            RET

.routine in A out A,HL,carry,zero clobbers sign,parity,halfCarry,DE
Stage7ParameterAddress:
            LD   L,A
            LD   H,0
            ADD  HL,HL
            ADD  HL,HL
            LD   DE,Stage7ParameterTableBase
            ADD  HL,DE
            OR   A
            RET

; Z returns one exact routine match and A its table index. NZ means that the
; current name is not a retained routine; it is not itself a diagnostic.
.routine out A,carry,zero clobbers sign,parity,halfCarry,B,C,D,DE,HL
Stage7FindRoutineCurrent:
            LD   A,(Stage7RoutineCount)
            OR   A
            JR   Z,Stage7FindRoutineMissing
            LD   C,A
            LD   B,0
Stage7FindRoutineLoop:
            LD   A,B
            CALL Stage7RoutineAddress
            CALL TokenNameRecordEquals
            JR   C,Stage7FindRoutineFound
            INC  B
            DEC  C
            JR   NZ,Stage7FindRoutineLoop
Stage7FindRoutineMissing:
            LD   A,(Stage8ForwardMainFlags)
            AND  Stage7RoutineMain
            JR   Z,Stage7FindRoutineAbsent
            CALL TypedNameEqualsMain
            JR   NC,Stage7FindRoutineAbsent
            LD   A,Stage7MainRoutine
            CP   A
            RET
Stage7FindRoutineAbsent:
            LD   A,$FF
            OR   A
            RET
Stage7FindRoutineFound:
            LD   A,B
            CP   A
            RET

Stage7CurrentNameMatchesAtHL .equ TokenNameRecordEquals

; Carry identifies a predefined service or error constant and A returns its
; dense ordinal. No match returns carry clear.
.routine out A,carry,zero clobbers sign,parity,halfCarry,B,C,D,DE,HL
Stage8MatchPredefinedCurrent:
            LD   HL,Stage8PredefinedTable
            LD   C,Stage8PredefinedCount
Stage8MatchPredefinedLoop:
            LD   B,(HL)
            INC  HL
            LD   A,(TokenLength)
            CP   B
            JR   NZ,Stage8MatchPredefinedSkip
            LD   DE,(TokenLexemePointer)
Stage8MatchPredefinedByte:
            LD   A,(DE)
            CP   (HL)
            JR   NZ,Stage8MatchPredefinedSkip
            INC  DE
            INC  HL
            DJNZ Stage8MatchPredefinedByte
            LD   A,Stage8PredefinedCount
            SUB  C
            SCF
            RET
Stage8MatchPredefinedSkip:
            LD   E,B
            LD   D,0
            ADD  HL,DE
            DEC  C
            JR   NZ,Stage8MatchPredefinedLoop
            OR   A
            RET

.if TargetStreamingOutput
; Compile one multipart source stream and publish one append-only object.
; IX points at the stable compact target descriptor; A/HL retain the existing
; bounded source-part descriptor ABI.
.routine in A,HL,IX out A,carry,zero clobbers sign,parity,halfCarry,BC,DE,HL,IX,IY
CompileTargetAggregateCallParts:
            LD   (CompilerAbortSp),SP
            LD   (TargetDescriptorPointer),IX
            PUSH AF
            PUSH HL
            CALL CompileSliceResetState
            POP  HL
            POP  AF
            PUSH AF
            CALL SourceInitializeParts
            POP  BC
.if CompilerDiagnosticReturns
            RET  C
.endif
            LD   A,B
            ; Validate every bank-bearing descriptor field before source
            ; semantics can retain a bank ordinal. A is the bounded part count.
            LD   B,A
            LD   IX,(TargetDescriptorPointer)
            LD   A,(IX+TargetDescriptorBankCount)
            OR   A
            JR   Z,TargetValidateCompileFailure
            CP   TargetBankCapacity+1
            JR   NC,TargetValidateCompileFailure
            LD   (TargetDescriptorBankCountValue),A
            LD   C,A
            LD   A,(IX+TargetDescriptorEntryBank)
            CP   C
            JR   NC,TargetValidateCompileFailure
            LD   (TargetDescriptorEntryBankValue),A
            LD   L,(IX+TargetDescriptorPartBanksPointer)
            LD   H,(IX+TargetDescriptorPartBanksPointer+1)
TargetValidatePartBankLoop:
            LD   A,(HL)
            CP   C
            JR   NC,TargetValidateCompileFailure
            INC  HL
            DJNZ TargetValidatePartBankLoop
            LD   HL,TargetBankRoLengthBase
            LD   B,TargetBankRoLengthLimit-TargetBankRoLengthBase
            XOR  A
TargetResetBankRoLengthLoop:
            LD   (HL),A
            INC  HL
            DJNZ TargetResetBankRoLengthLoop
            CALL CompileAggregateCallReady
.if CompilerDiagnosticReturns
            RET  C
.endif
            ; A diagnostic during generation restores this synthetic frame and
            ; returns directly through the one target-output abort path. A
            ; successful generation returns normally and discards the frame.
            LD   HL,AbortTargetProgram
            PUSH HL
            LD   (CompilerAbortSp),SP
            CALL EncodeAggregateProgram
            POP  HL
            RET
TargetValidateCompileFailure:
            JP   TargetConfigurationFailure

; Return the bank mapped to the current manifest source-part ordinal.
.routine out A,carry,zero clobbers sign,parity,halfCarry,D,DE,HL,IX
TargetCurrentSourceBank:
            LD   A,(SourcePartsRemaining)
            AND  SourcePartOrdinalMask
            RRCA
            RRCA
            RRCA
            LD   E,A
            LD   D,0
            LD   IX,(TargetDescriptorPointer)
            LD   L,(IX+TargetDescriptorPartBanksPointer)
            LD   H,(IX+TargetDescriptorPartBanksPointer+1)
            ADD  HL,DE
            LD   A,(HL)
            OR   A
            RET

; Add the current source bank to flag byte A without disturbing low flags.
.routine in A out A,carry,zero clobbers sign,parity,halfCarry,B,D,DE,HL,IX
TargetPackCurrentBank:
            LD   B,A
            CALL TargetCurrentSourceBank
            RLCA
            RLCA
            RLCA
            RLCA
            OR   B
            RET

; Extract the target bank stored in flag bits 4..5. The final rotate shifts a
; known zero bit through carry, so success returns carry clear.
.routine in A out A,carry,zero clobbers sign,parity,halfCarry
TargetUnpackBank:
            AND  TargetBankMask
            RRCA
            RRCA
            RRCA
            RRCA
            RET

.routine in A out A,HL,carry,zero clobbers sign,parity,halfCarry,D,DE
TargetBankRoLengthAddress:
            LD   L,A
            LD   H,0
            ADD  HL,HL
            LD   DE,TargetBankRoLengthBase
            ADD  HL,DE
            OR   A
            RET

; Compare packed bank bits in D with the current source-part bank.
.routine in D out A,carry,zero clobbers sign,parity,halfCarry,B,D,DE,HL,IX
TargetCurrentBankMatches:
            LD   B,D
            CALL TargetCurrentSourceBank
            RLCA
            RLCA
            RLCA
            RLCA
            XOR  B
            AND  TargetBankMask
            RET
.routine in D out A,carry,zero clobbers sign,parity,halfCarry,B,C,D,DE,HL,IX,IY
TargetRequireCurrentBank:
            CALL TargetCurrentBankMatches
            RET  Z
            JP   TargetConfigurationFailure

.routine out A,carry,zero clobbers sign,parity,halfCarry,B,C,D,DE,HL,IX,IY
TargetRequireEntrySourceBank:
            CALL TargetCurrentSourceBank
            LD   D,A
            LD   A,(TargetDescriptorEntryBankValue)
            CP   D
            RET  Z
            JP   TargetConfigurationFailure
.endif

.if TargetStreamingOutput
            ; The target entry initializes parts and calls the shared body.
.else
.routine in A,HL out A,carry,zero clobbers sign,parity,halfCarry,BC,DE,HL,IX,IY
CompileAggregateCallParts:
            PUSH AF
            PUSH HL
            CALL CompileSliceResetState
            POP  HL
            POP  AF
            CALL SourceInitializeParts
.if CompilerDiagnosticReturns
            RET  C
.endif
            JR   CompileAggregateCallReady
.routine in A,DE,HL out A,carry,zero clobbers sign,parity,halfCarry,BC,DE,HL,IX,IY
CompileAggregateCallSlice:
            CALL CompileSliceInitialize
.endif
.routine out A,carry,zero clobbers sign,parity,halfCarry,BC,DE,HL,IX,IY
CompileAggregateCallReady:
            INC  A
            LD   (AggregateMode),A
            LD   HL,Stage7StateBase
            LD   B,Stage7CompilerWorkspaceEnd-Stage7StateBase
            XOR  A
CompileAggregateCallResetLoop:
            LD   (HL),A
            INC  HL
            DJNZ CompileAggregateCallResetLoop
            LD   (ControlNextLabel),A
.if Stage7LL1
            CALL HybridLL1Parse
.else
            CALL Stage7ParseTopLevel
.endif
.if CompilerDiagnosticReturns
            RET  C
.endif
            JP   SemanticSinkFinish

; Reject a routine name that collides with an ordinary name or an earlier
; routine. The current token remains the name being checked.
.routine out A,carry,zero clobbers sign,parity,halfCarry,B,C,D,DE,HL
Stage7RejectCurrentDeclarationName:
            CALL SymbolFindCurrent
            JP   C,TypedDuplicateNameFailure
            CALL Stage7FindRoutineCurrent
            JP   Z,TypedDuplicateNameFailure
            CALL Stage8MatchPredefinedCurrent
            JP   C,TypedDuplicateNameFailure
            OR   A
            RET

.if HybridLL1Full
.else
.routine out A,carry,zero clobbers sign,parity,halfCarry,B,C,D,DE,HL
Stage7ParseTopLevel:
            CALL ParserPeek
.if CompilerDiagnosticReturns
            RET  C
.endif
            CP   TokenRecord
            JR   Z,Stage7TopLevelRecord
            CP   TokenVar
            JR   Z,Stage7TopLevelVar
            CP   TokenConst
            JR   Z,Stage7TopLevelConst
            CP   TokenSub
            JR   Z,Stage7TopLevelRoutine
            CALL SetDiagInline
            .db  DiagnosticExpectedTopLevel
Stage7TopLevelRecord:
            CALL ParserTake
.if CompilerDiagnosticReturns
            RET  C
.endif
            JP   AggregateParseRecordAfterTake
Stage7TopLevelVar:
            CALL ParserTake
.if CompilerDiagnosticReturns
            RET  C
.endif
            LD   E,TokenName
            CALL ParserExpect
.if CompilerDiagnosticReturns
            RET  C
.endif
            JP   AggregateParseProgramAfterVar
Stage7TopLevelConst:
            CALL ParserTake
.if CompilerDiagnosticReturns
            RET  C
.endif
            CALL TypedParseTopLevelConstAfterTake
.if CompilerDiagnosticReturns
            RET  C
.endif
            JP   Stage7ParseTopLevel
Stage7TopLevelRoutine:
            CALL ParserTake
.if CompilerDiagnosticReturns
            RET  C
.endif
            LD   E,TokenName
            CALL ParserExpect
.if CompilerDiagnosticReturns
            RET  C
.endif
            LD   HL,NameMain
            LD   B,4
            CALL TokenNameEquals
            JP   C,Stage7ParseMainAfterName
            JP   Stage7ParseRoutineAfterName
.endif

; Check the current parameter name against the current signature prefix.
.routine out A,carry,zero clobbers sign,parity,halfCarry,B,C,D,DE,HL
Stage7CheckParameterDuplicate:
            LD   A,(Stage7CurrentParameterCount)
            OR   A
            RET  Z
            LD   C,A
            LD   A,(Stage7CurrentParameterStart)
            LD   B,A
Stage7CheckParameterLoop:
            LD   A,B
            CALL Stage7ParameterAddress
            CALL TokenNameRecordEquals
            JP   C,TypedDuplicateNameFailure
            INC  B
            DEC  C
            JR   NZ,Stage7CheckParameterLoop
            OR   A
            RET

; Reject a parameter name that collides with an ordinary declaration, an
; earlier routine, the routine whose signature is being parsed, or an earlier
; parameter in that signature.
.routine out A,carry,zero clobbers sign,parity,halfCarry,B,C,D,DE,HL
Stage7CheckParameterDeclarationName:
            CALL TypedRejectCurrentOrdinaryName
.if CompilerDiagnosticReturns
            RET  C
.endif
            CALL Stage7RejectCurrentDeclarationName
.if CompilerDiagnosticReturns
            RET  C
.endif
            LD   A,(Stage7CurrentRoutine)
            CALL Stage7RoutineAddress
            LD   E,(HL)
            INC  HL
            LD   D,(HL)
            INC  HL
            LD   A,(HL)
            LD   B,A
            EX   DE,HL
            CALL TokenNameEquals
            JP   C,TypedDuplicateNameFailure
            JR   Stage7CheckParameterDuplicate

; Append the current parameter name and its parsed type A.
.routine in A out A,carry,zero clobbers sign,parity,halfCarry,B,C,D,DE,HL
Stage7AppendParameter:
            LD   (Stage7PathType),A
            LD   A,(Stage7ParameterCount)
            CP   Stage7ParameterCapacity
            JR   NC,Stage7ParameterCapacityFailure
            CALL Stage7ParameterAddress
            CALL TokenRetainNameAtHL
            INC  HL
            LD   A,(Stage7PathType)
            LD   (HL),A
            LD   HL,Stage7ParameterCount
            INC  (HL)
            LD   HL,Stage7CurrentParameterCount
            INC  (HL)
            LD   A,(Stage7PathType)
            OR   A
            RET
Stage7ParameterCapacityFailure:
            CALL SetDiagInline
            .db  DiagnosticParameterCapacity

; Parse the parameter list and optional result of the provisional routine.
.if HybridLL1Full
.else
.routine out A,carry,zero clobbers sign,parity,halfCarry,B,C,D,DE,HL,IX,IY
Stage7ParseSignature:
            CALL ParserExpectLeft
.if CompilerDiagnosticReturns
            RET  C
.endif
            CALL ParserPeek
.if CompilerDiagnosticReturns
            RET  C
.endif
            CP   TokenRightParen
            JR   Z,Stage7SignatureClose
Stage7SignatureParameter:
            LD   E,TokenName
            CALL ParserExpect
.if CompilerDiagnosticReturns
            RET  C
.endif
            CALL Stage7CheckParameterDeclarationName
.if CompilerDiagnosticReturns
            RET  C
.endif
            PUSH HL
            LD   HL,(TokenLexemePointer)
            LD   (DeclarationNamePointer),HL
            LD   A,(TokenLength)
            LD   (DeclarationNameLength),A
            POP  HL
            CALL ParserExpectAs
.if CompilerDiagnosticReturns
            RET  C
.endif
            CALL AggregateParseType
.if CompilerDiagnosticReturns
            RET  C
.endif
            PUSH AF
            CALL TypedRestoreDeclarationToken
            POP  AF
            CALL Stage7AppendParameter
.if CompilerDiagnosticReturns
            RET  C
.endif
            CALL ParserPeek
.if CompilerDiagnosticReturns
            RET  C
.endif
            CP   TokenComma
            JR   NZ,Stage7SignatureClose
            CALL ParserTake
.if CompilerDiagnosticReturns
            RET  C
.endif
            JR   Stage7SignatureParameter
Stage7SignatureClose:
            CALL ParserExpectRight
.if CompilerDiagnosticReturns
            RET  C
.endif
            XOR  A
            LD   (Stage7CurrentResultType),A
            CALL ParserPeek
.if CompilerDiagnosticReturns
            RET  C
.endif
            CP   TokenAs
            JR   NZ,Stage7SignatureLine
            CALL ParserTake
.if CompilerDiagnosticReturns
            RET  C
.endif
            CALL AggregateParseType
.if CompilerDiagnosticReturns
            RET  C
.endif
            LD   (Stage7CurrentResultType),A
Stage7SignatureLine:
            JP   ParserExpectLine
.endif

; Install one retained parameter as an activation symbol and emit the copy
; from its caller-stack carrier into the routine's negative IX frame.
.routine in A,C out A,carry,zero clobbers sign,parity,halfCarry,B,C,D,DE,HL,IX,IY
Stage7InstallParameter:
            LD   (Stage7CurrentParameterStart),A
            LD   A,C
            LD   (Stage7ArgumentIndex),A
            LD   A,(Stage7CurrentParameterStart)
            CALL Stage7ParameterAddress
            LD   E,(HL)
            INC  HL
            LD   D,(HL)
            INC  HL
            LD   B,(HL)
            INC  HL
            LD   A,(HL)
            LD   (Stage7PathType),A
            LD   (TokenLexemePointer),DE
            LD   A,B
            LD   (TokenLength),A
            LD   A,(NextLocalSlot)
            LD   (Stage7PathOffset),A
            LD   C,A
            LD   B,0
            LD   A,(Stage7PathType)
            CP   AggregateFirstDynamicTypeId
            LD   D,SymbolAggregateFlag+SymbolClassParameter
            JR   NC,Stage7InstallParameterSymbol
Stage7InstallScalarParameter:
            OR   SymbolClassParameter
            LD   D,A
Stage7InstallParameterSymbol:
            CALL SymbolPrepareCurrentWord
.if CompilerDiagnosticReturns
            RET  C
.endif
            LD   A,(Stage7PathType)
            CALL SymbolCommitTyped
.if CompilerDiagnosticReturns
            RET  C
.endif
            LD   A,(Stage7PathType)
            LD   C,A
            LD   A,SemanticBindParameter
            CALL ParserEmitOperationC
.if CompilerDiagnosticReturns
            RET  C
.endif
            LD   A,(Stage7PathOffset)
            CALL SemanticSinkPut
.if CompilerDiagnosticReturns
            RET  C
.endif
            LD   A,(Stage7ArgumentIndex)
            CALL SemanticSinkPut
.if CompilerDiagnosticReturns
            RET  C
.endif
            LD   A,(Stage7PathType)
            CP   AggregateFirstDynamicTypeId
            JR   C,Stage7InstallScalarParameterWidth
            CP   AggregateOpenStringTypeId
            LD   A,3
            SBC  A,0
            JR   Stage7InstallParameterWidth
Stage7InstallScalarParameterWidth:
            CALL TypedTypeWidth
Stage7InstallParameterWidth:
            LD   HL,NextLocalSlot
            ADD  A,(HL)
            LD   (HL),A
            OR   A
            RET

; Current token is a non-main routine name.
.if HybridLL1Full
.else
.routine out A,carry,zero clobbers sign,parity,halfCarry,B,C,D,DE,HL,IX,IY
Stage7ParseRoutineAfterName:
            LD   A,(Stage7RoutineCount)
            CP   Stage7RoutineCapacity
            JP   NC,Stage7RoutineCapacityFailure
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
            XOR  A
            LD   (Stage7CurrentParameterCount),A
            CALL Stage7ParseSignature
.if CompilerDiagnosticReturns
            RET  C
.endif
            LD   A,(Stage7CurrentRoutine)
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
            LD   HL,Stage7RoutineCount
            INC  (HL)
            LD   A,(SymbolCount)
            LD   (Stage7GlobalSymbolCount),A
            XOR  A
            LD   (NextLocalSlot),A
            CALL ControlReset
            LD   A,(Stage7CurrentResultType)
            OR   A
            LD   A,ControlRoutineValue
            JR   NZ,Stage7RoutineKindReady
            XOR  A
Stage7RoutineKindReady:
            LD   (ControlRoutineKind),A
            LD   A,(Stage7CurrentResultType)
            LD   (ControlResultType),A
            LD   A,1
            LD   (ControlSequenceFallsThrough),A
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
            LD   B,A
            LD   A,(Stage7CurrentParameterStart)
            LD   D,A
            XOR  A
            LD   E,A
Stage7RoutineParameterLoop:
            LD   A,B
            OR   A
            JR   Z,Stage7RoutineLocals
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
            JR   Stage7RoutineParameterLoop

Stage7RoutineLocals:
            CALL TypedParseLocalRun
.if CompilerDiagnosticReturns
            RET  C
.endif
Stage7RoutineStatements:
            CALL TypedParseStatements
.if CompilerDiagnosticReturns
            RET  C
.endif
            LD   A,(Stage7CurrentResultType)
            OR   A
            JR   Z,Stage7RoutineEndToken
            LD   A,(ControlSequenceFallsThrough)
            OR   A
            JP   NZ,TypedRoutineFlowFailure
Stage7RoutineEndToken:
            LD   E,TokenEnd
            CALL ParserExpect
.if CompilerDiagnosticReturns
            RET  C
.endif
            CALL ParserExpectLine
.if CompilerDiagnosticReturns
            RET  C
.endif
            LD   A,SemanticEndGeneralRoutine
            CALL SemanticSinkOperation
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
            JP   Stage7ParseTopLevel
Stage7RoutineCapacityFailure:
            CALL SetDiagInline
            .db  DiagnosticRoutineCapacity

; Main is the final declaration in this increment. `fails` is accepted but
; its full call/failure surface remains Stage 8.
.routine out A,carry,zero clobbers sign,parity,halfCarry,B,C,D,DE,HL,IX,IY
Stage7ParseMainAfterName:
            CALL Stage7RejectCurrentDeclarationName
.if CompilerDiagnosticReturns
            RET  C
.endif
            CALL ParserExpectLeft
.if CompilerDiagnosticReturns
            RET  C
.endif
            CALL ParserExpectRight
.if CompilerDiagnosticReturns
            RET  C
.endif
            CALL ParserPeek
.if CompilerDiagnosticReturns
            RET  C
.endif
            CP   TokenFails
            JR   NZ,Stage7MainLine
            CALL ParserTake
.if CompilerDiagnosticReturns
            RET  C
.endif
Stage7MainLine:
            CALL ParserExpectLine
.if CompilerDiagnosticReturns
            RET  C
.endif
            LD   A,SemanticBeginMain
            CALL SemanticSinkOperation
.if CompilerDiagnosticReturns
            RET  C
.endif
            LD   A,(SymbolCount)
            LD   (Stage7GlobalSymbolCount),A
            XOR  A
            LD   (NextLocalSlot),A
            LD   (Stage7CurrentResultType),A
            LD   (ControlRoutineKind),A
            CALL ControlReset
            LD   A,1
            LD   (ControlSequenceFallsThrough),A
Stage7MainLocals:
            CALL TypedParseLocalRun
.if CompilerDiagnosticReturns
            RET  C
.endif
Stage7MainStatements:
            CALL TypedParseStatements
.if CompilerDiagnosticReturns
            RET  C
.endif
            LD   E,TokenEnd
            CALL ParserExpect
.if CompilerDiagnosticReturns
            RET  C
.endif
            CALL ParserExpectLine
.if CompilerDiagnosticReturns
            RET  C
.endif
            LD   A,SemanticEndMain
            CALL SemanticSinkOperation
.if CompilerDiagnosticReturns
            RET  C
.endif
            LD   E,TokenEof
            JP   ParserExpect
.endif

; Return the positive IX displacement of the current source argument. Every
; later source parameter contributes one address/scalar word; each later open
; string contributes its hidden capacity word as well.
.routine in B,D out A,B,C,D,E,carry,zero clobbers sign,parity,halfCarry,HL
Stage7ParameterSourceOffset:
            PUSH BC
            PUSH DE
            LD   A,B
            ADD  A,A
            ADD  A,2
            LD   C,A
            DEC  B
            JR   Z,_parameterSourceOffsetDone
            LD   A,D
            INC  A
            CALL Stage7ParameterAddress
_parameterSourceOffsetLoop:
            INC  HL
            INC  HL
            INC  HL
            LD   A,(HL)
            CP   AggregateOpenStringTypeId
            JR   NZ,_parameterSourceOffsetNext
            INC  C
            INC  C
_parameterSourceOffsetNext:
            INC  HL                      ; next four-byte parameter entry
            DJNZ _parameterSourceOffsetLoop
_parameterSourceOffsetDone:
            LD   A,C
            POP  DE
            POP  BC
            LD   C,A
            OR   A
            RET

; Return aggregate symbol info in D, byte payload in BC, and exact type ID in
; A. The ordinary symbol-table address determines the parallel type entry.
.routine out A,BC,D,carry,zero clobbers sign,parity,halfCarry,E,HL
Stage7LookupAggregateCurrent:
            CALL SymbolFindCurrent
            JP   NC,SymbolLookupMissing
            PUSH HL
            INC  HL
            INC  HL
            INC  HL
            LD   D,(HL)
            LD   A,D
            LD   (Stage7ArgumentCount),A
            INC  HL
            LD   C,(HL)
            INC  HL
            LD   B,(HL)
            POP  HL
            LD   DE,SymbolTableBase
            OR   A
            SBC  HL,DE
            LD   A,L
            LD   E,0
Stage7SymbolIndexLoop:
            CP   SymbolEntrySize
            JR   C,Stage7SymbolIndexReady
            SUB  SymbolEntrySize
            INC  E
            JR   Stage7SymbolIndexLoop
Stage7SymbolIndexReady:
            LD   A,E
            LD   E,A
            LD   H,0
            LD   L,E
            LD   DE,AggregateSymbolTypeBase
            ADD  HL,DE
            LD   A,(HL)
            LD   E,A
            LD   A,(Stage7ArgumentCount)
            LD   D,A
            LD   A,E
            OR   A
            RET

; Stage 7 structural operands are emitted whenever their owning operation is
; emitted. They are not expression values and therefore do not consult the
; constant-folding emission flag used by TypedEmitWord.
.routine in HL out A,carry,zero clobbers sign,parity,halfCarry,B,DE,HL
Stage7EmitWord:
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
            JP   SemanticSinkPut

; D is the symbol class and BC its byte offset. Emit its opaque root carrier
; and return the exact aggregate type in A.
.routine out A,carry,zero clobbers sign,parity,halfCarry,B,C,D,DE,HL,IX,IY
Stage7EmitAggregateSymbolRoot:
            CALL Stage7LookupAggregateCurrent
.if CompilerDiagnosticReturns
            RET  C
.endif
            LD   (Stage7PathType),A
            CP   AggregateOpenStringTypeId
            JR   NZ,Stage7EmitAggregateRootClass
            LD   A,C
            INC  A
            INC  A
            LD   (Stage7OpenStringCapacityOffset),A
Stage7EmitAggregateRootClass:
            LD   A,D
            AND  SymbolClassMask
            JR   Z,Stage7EmitAggregateRootReadOnly
            CP   SymbolClassProgram
            JR   NZ,Stage7EmitAggregateRootParameter
            LD   A,SemanticLoadProgramAlias
Stage7EmitAggregateRootAddress:
            PUSH BC
            CALL SemanticSinkOperation
            POP  HL
.if CompilerDiagnosticReturns
            RET  C
.endif
            CALL Stage7EmitWord
            JR   Stage7EmitAggregateRootReady
Stage7EmitAggregateRootReadOnly:
.if TargetStreamingOutput
            PUSH BC
            CALL TargetRequireCurrentBank
            POP  BC
.if CompilerDiagnosticReturns
            RET  C
.endif
.endif
            LD   A,SemanticLoadReadOnlyAlias
            JR   Stage7EmitAggregateRootAddress
Stage7EmitAggregateRootParameter:
            CP   SymbolClassParameter
            JP   NZ,TypedTypeFailure
            LD   A,SemanticLoadParameterAlias
Stage7EmitAggregateRootSelected:
            CALL ParserEmitOperationC
Stage7EmitAggregateRootReady:
.if CompilerDiagnosticReturns
            RET  C
.endif
            LD   A,(Stage7PathType)
            OR   A
            RET

; Emit one checked postfix chain. A is the current aggregate type and one
; carrier is live on the generated evaluation stack. D returns zero for an
; address path or one when `.length` has already produced a scalar value.
.routine in A out A,D,carry,zero clobbers sign,parity,halfCarry,B,C,E,HL,IX,IY
Stage7ParsePathSuffix:
            LD   D,0
Stage7PathSuffixLoop:
            PUSH AF
            CALL ParserPeek
.if CompilerDiagnosticBranches
            JP   C,Stage7PathSuffixFailure
.endif
            CP   TokenDot
            JR   Z,Stage7PathFieldComposition
            CP   TokenLeftBracket
            JP   Z,Stage7PathIndexComposition
            POP  AF
            LD   D,0
            OR   A
            RET
Stage7PathFieldComposition:
            POP  AF
            LD   (Stage7PathType),A
            CALL Stage8RequireNoPendingFailure
.if CompilerDiagnosticReturns
            RET  C
.endif
            LD   A,(Stage7PathType)
            PUSH AF
Stage7PathField:
            CALL ParserTake
.if CompilerDiagnosticBranches
            JP   C,Stage7PathSuffixFailure
.endif
            LD   E,TokenName
            CALL ParserExpect
.if CompilerDiagnosticBranches
            JP   C,Stage7PathSuffixFailure
.endif
            POP  AF
            PUSH AF
            CP   AggregateFirstDynamicTypeId
.if CompilerDiagnosticBranches
            JP   C,Stage7PathFieldTypeFailure
.endif
            CP   AggregateOpenStringTypeId
            JR   Z,Stage7PathStringField
            CALL AggregateTypeAddress
            LD   A,(HL)
            CP   AggregateTypeKindString
            JR   NZ,Stage7PathRecordField
Stage7PathStringField:
            LD   HL,NameLength
            LD   B,6
            CALL TokenNameEquals
            JP   NC,Stage7PathFieldTypeFailure
            LD   A,(Stage7PathType)
            CP   AggregateOpenStringTypeId
            JR   Z,Stage7PathOpenStringField
            CALL AggregateTypeAddress
            INC  HL
            LD   C,(HL)                  ; capacity for L <= N validation
            LD   A,SemanticStringLength
            JR   Stage7PathStringLengthReady
Stage7PathOpenStringField:
            LD   A,(Stage7OpenStringCapacityOffset)
            LD   C,A
            LD   A,SemanticOpenStringLength
Stage7PathStringLengthReady:
            CALL ParserEmitOperationC
.if CompilerDiagnosticBranches
            JP   C,Stage7PathSuffixFailure
.endif
            LD   HL,(TokenStartOffset)
            CALL Stage7EmitWord
.if CompilerDiagnosticBranches
            JP   C,Stage7PathSuffixFailure
.endif
            POP  AF
            LD   A,ScalarTypeU8
            LD   D,1
            OR   A
            RET
Stage7FieldMissing:
            CALL SetDiagInline
            .db  DiagnosticUnknownName
Stage7PathRecordField:
            POP  AF
            CALL AggregateTypeAddress
            LD   A,(HL)
            CP   AggregateTypeKindRecord
            JP   NZ,TypedTypeFailure
            INC  HL
            LD   A,(HL)
            ADD  A,A
            LD   E,A
            LD   D,0
            LD   HL,AggregateRecordTableBase
            ADD  HL,DE
            LD   B,(HL)
            INC  HL
            LD   D,(HL)
Stage7PathRecordFieldLoop:
            LD   A,D
            OR   A
            JR   Z,Stage7FieldMissing
            LD   A,B
            CALL AggregateFieldAddress
            PUSH DE
            CALL TokenNameRecordEquals
            POP  DE
            JR   C,Stage7PathRecordFieldFound
            INC  B
            DEC  D
            JR   Stage7PathRecordFieldLoop
Stage7PathRecordFieldFound:
            LD   A,B
            CALL AggregateFieldAddress
            LD   DE,AggregateFieldTypeId
            ADD  HL,DE
            LD   A,(HL)
            INC  HL
            LD   E,(HL)
            INC  HL
            LD   D,(HL)
            OR   A
            PUSH AF
            LD   (Stage7PathOffset),DE
            LD   A,SemanticSelectField
            CALL SemanticSinkOperation
.if CompilerDiagnosticBranches
            JP   C,Stage7PathSuffixFailure
.endif
            LD   HL,(Stage7PathOffset)
            CALL Stage7EmitWord
.if CompilerDiagnosticBranches
            JP   C,Stage7PathSuffixFailure
.endif
            POP  AF
            JP   Stage7PathSuffixLoop
Stage7PathIndexComposition:
            POP  AF
            LD   (Stage7PathType),A
            CALL Stage8RequireNoPendingFailure
.if CompilerDiagnosticReturns
            RET  C
.endif
            LD   A,(Stage7OpenStringCapacityOffset)
            PUSH AF
            LD   A,(Stage7PathType)
            PUSH AF
Stage7PathIndex:
            LD   HL,(TokenStartOffset)
            PUSH HL
            CALL ParserTake
.if CompilerDiagnosticBranches
            JP   C,Stage7PathIndexFailure
.endif
            LD   A,(ExpressionExpectedType)
            PUSH AF
            LD   A,(ExpressionEmitEnabled)
            PUSH AF
            LD   A,1
            LD   (ExpressionEmitEnabled),A
            LD   A,ScalarTypeU16
            LD   (ExpressionExpectedType),A
            CALL TypedParseOr
.if CompilerDiagnosticBranches
            JP   C,Stage7PathIndexExpressionFailure
.endif
            CALL TypedRequireComposable
.if CompilerDiagnosticBranches
            JP   C,Stage7PathIndexExpressionFailure
.endif
            LD   (ExpressionRightMeta),A
            LD   (ExpressionRightValue),HL
            POP  AF
            LD   (ExpressionEmitEnabled),A
            POP  AF
            LD   (ExpressionExpectedType),A
            LD   A,(ExpressionRightMeta)
            AND  ScalarMetaTypeMask
            CP   ScalarTypeBoolean
            JP   Z,Stage7PathIndexTypeFailure
            LD   E,TokenRightBracket
            CALL ParserExpect
.if CompilerDiagnosticBranches
            JP   C,Stage7PathIndexFailure
.endif
            POP  HL
            LD   (Stage7CallOffset),HL
            POP  AF
            LD   E,A
            POP  BC
            LD   A,B
            LD   (Stage7OpenStringCapacityOffset),A
            LD   A,E
            CP   AggregateFirstDynamicTypeId
            JP   C,TypedTypeFailure
            PUSH AF
            CP   AggregateOpenStringTypeId
            JR   Z,Stage7PathOpenStringIndex
            CALL AggregateTypeAddress
            LD   A,(HL)
            CP   AggregateTypeKindString
            JR   Z,Stage7PathStringIndex
            CP   AggregateTypeKindArray
            JP   NZ,Stage7PathFieldTypeFailure
            INC  HL
            LD   A,(HL)                  ; element type
            LD   (Stage7PathType),A
            INC  HL
            LD   C,(HL)                  ; fixed length
            INC  HL
            LD   B,(HL)
            LD   A,(ExpressionRightMeta)
            AND  ScalarMetaConstant
            JR   Z,Stage7PathIndexDynamic
            LD   HL,(ExpressionRightValue)
            OR   A
            SBC  HL,BC
            JR   NC,Stage7PathIndexRangeFailure
Stage7PathIndexDynamic:
            LD   (Stage7PathOffset),BC
            LD   A,(Stage7PathType)
            CALL AggregateGetExtent
            LD   (Stage7PathExtent),HL
            LD   A,SemanticSelectIndex
            CALL SemanticSinkOperation
.if CompilerDiagnosticBranches
            JR   C,Stage7PathSuffixFailure
.endif
            LD   HL,(Stage7PathOffset)
            CALL Stage7EmitWord
.if CompilerDiagnosticBranches
            JR   C,Stage7PathSuffixFailure
.endif
            LD   HL,(Stage7PathExtent)
            CALL Stage7EmitWord
.if CompilerDiagnosticBranches
            JR   C,Stage7PathSuffixFailure
.endif
            LD   HL,(Stage7CallOffset)
            CALL Stage7EmitWord
.if CompilerDiagnosticBranches
            JR   C,Stage7PathSuffixFailure
.endif
            POP  AF
            CALL AggregateTypeAddress
            INC  HL
            LD   A,(HL)
            JP   Stage7PathSuffixLoop
Stage7PathStringIndex:
            INC  HL
            LD   C,(HL)                  ; capacity
            LD   A,SemanticStringIndex
            JR   Stage7PathStringIndexReady
Stage7PathOpenStringIndex:
            LD   A,(Stage7OpenStringCapacityOffset)
            LD   C,A
            LD   A,SemanticOpenStringIndex
Stage7PathStringIndexReady:
            CALL ParserEmitOperationC
.if CompilerDiagnosticBranches
            JR   C,Stage7PathSuffixFailure
.endif
            LD   HL,(Stage7CallOffset)
            CALL Stage7EmitWord
.if CompilerDiagnosticBranches
            JR   C,Stage7PathSuffixFailure
.endif
            POP  AF
            LD   A,ScalarTypeU8
            JP   Stage7PathSuffixLoop
.if CompilerDiagnosticBranches
Stage7PathSuffixFailure:
            POP  AF
            SCF
            RET
.endif
Stage7PathIndexTypeFailure:
            POP  HL
            POP  AF
            POP  BC
            JP   TypedTypeFailure
.if CompilerDiagnosticBranches
Stage7PathIndexFailure:
            POP  HL
            POP  AF
            POP  BC
            SCF
            RET
Stage7PathIndexExpressionFailure:
            POP  AF
            LD   (ExpressionEmitEnabled),A
            POP  AF
            LD   (ExpressionExpectedType),A
            JR   Stage7PathIndexFailure
.endif
Stage7PathIndexRangeFailure:
            LD   A,(ExpressionSuppressFault)
            OR   A
            JR   NZ,Stage7PathIndexDynamic
            LD   HL,(Stage7CallOffset)
            LD   (TokenStartOffset),HL
            POP  AF
            JP   TypedRangeFailure
Stage7PathFieldTypeFailure:
            POP  AF
            JP   TypedTypeFailure

; Address one bounded nested-call frame. Eight bytes retain the source-call
; metadata that nested argument calls may overwrite. The scalar parser keeps
; only its balanced expression context, a source frame keeps its result flag,
; and a service keeps only its source offset temporarily on the compiler
; hardware stack.
.routine in A out A,HL,carry,zero clobbers sign,parity,halfCarry,D,DE
Stage7CallFrameAddress:
            LD   L,A
            LD   H,0
            ADD  HL,HL
            ADD  HL,HL
            ADD  HL,HL
            LD   DE,Stage7CallFrameBase
            ADD  HL,DE
            OR   A
            RET

.routine out A,HL,carry,zero clobbers sign,parity,halfCarry,D,DE
Stage7CurrentCallFrame:
            LD   A,(Stage7CallDepth)
            DEC  A
            JR   Stage7CallFrameAddress

; Parse and validate one scalar argument against the expected type in A while
; preserving the enclosing expression context across nested calls.
.routine in A out A,HL,carry,zero clobbers sign,parity,halfCarry,B,C,D,DE,IX,IY
Stage7ParseScalarArgument:
            LD   D,A
            LD   A,(ExpressionExpectedType)
            LD   B,A
            LD   A,(ExpressionEmitEnabled)
            LD   C,A
            PUSH BC
            PUSH DE
            LD   A,D
            LD   (ExpressionExpectedType),A
            LD   A,1
            LD   (ExpressionEmitEnabled),A
            CALL TypedParseOr
.if CompilerDiagnosticBranches
            JR   C,Stage7ScalarArgumentFailure
.endif
            LD   (Stage7PathType),A
            LD   (ExpressionRightValue),HL
            POP  DE
            POP  BC
            LD   A,C
            LD   (ExpressionEmitEnabled),A
            LD   A,B
            LD   (ExpressionExpectedType),A
            LD   E,D
            LD   A,(Stage7PathType)
            LD   HL,(ExpressionRightValue)
            CALL TypedCheckAssignable
.if CompilerDiagnosticReturns
            RET  C
.endif
            JP   Stage8RequireNoPendingFailure
.if CompilerDiagnosticBranches
Stage7ScalarArgumentFailure:
            LD   L,A
            POP  DE
            POP  BC
            LD   A,C
            LD   (ExpressionEmitEnabled),A
            LD   A,B
            LD   (ExpressionExpectedType),A
            LD   A,L
            SCF
            RET
.endif

; Parse one call to a retained routine. A is the routine-table index and C is
; zero when the result is discarded or one when its carrier remains live.
.routine in A,C out A,carry,zero clobbers sign,parity,halfCarry,B,C,D,DE,HL,IX,IY
Stage7ParseCall:
            LD   B,A
            LD   A,(Stage7CallDepth)
            CP   Stage7CallFrameCapacity
            JR   C,Stage7PushCallFrameSpace
            CALL SetDiagInline
            .db  DiagnosticExpressionCapacity
Stage7PushCallFrameSpace:
            CALL Stage7CallFrameAddress
            LD   A,C
            PUSH AF
            PUSH HL
            LD   A,B
            CP   Stage7MainRoutine
            JR   Z,Stage7PushMainCallFrame
            CALL Stage7RoutineAddress
            INC  HL
            INC  HL
            INC  HL
            LD   D,(HL)                  ; parameter start
            INC  HL
            LD   E,(HL)                  ; parameter count
            INC  HL
            LD   B,(HL)                  ; result
            INC  HL
            LD   A,(HL)                  ; label
            INC  HL
            LD   C,(HL)                  ; failure flags
            JR   Stage7PushCallFrameReady
Stage7PushMainCallFrame:
            LD   D,0                     ; parameter start
            LD   E,0                     ; parameter count
            LD   B,0                     ; result-free
            LD   A,(Stage8ForwardMainFlags)
            LD   C,A
            LD   A,Stage7MainLabel
Stage7PushCallFrameReady:
            POP  HL
            LD   (HL),A
            POP  AF
            OR   A
            JR   Z,Stage7PushCallFrameLabelReady
            SET  6,(HL)
Stage7PushCallFrameLabelReady:
            INC  HL
            LD   (HL),B
            INC  HL
            LD   (HL),D
            INC  HL
            LD   (HL),E
            INC  HL
            LD   (HL),E                  ; original argument count
            INC  HL
            LD   DE,(TokenStartOffset)
            LD   (HL),E
            INC  HL
            LD   (HL),D
            INC  HL
            LD   (HL),C
            LD   HL,Stage7CallDepth
            INC  (HL)
            CALL ParserExpectLeft
.if CompilerDiagnosticBranches
            JP   C,Stage7CallFailure
.endif
Stage7CallArgumentLoop:
            CALL Stage7CurrentCallFrame
            INC  HL
            INC  HL
            INC  HL
            LD   A,(HL)
            OR   A
            JP   Z,Stage7CallArgumentsDone
            DEC  HL
            LD   A,(HL)                  ; current parameter table index
            CALL Stage7ParameterAddress
            INC  HL
            INC  HL
            INC  HL
            LD   A,(HL)
            LD   D,A
            XOR  A
            LD   (Stage8DirectFailable),A
            LD   A,D
            CP   AggregateFirstDynamicTypeId
            JR   NC,Stage7CallAggregateArgument
            CALL Stage7ParseScalarArgument
.if CompilerDiagnosticBranches
            JP   C,Stage7CallFailure
.endif
            JR   Stage7CallArgumentReady
Stage7CallAggregateArgument:
            CALL Stage7ParseAggregateValue
.if CompilerDiagnosticBranches
            JP   C,Stage7CallFailure
.endif
            PUSH AF
            CALL Stage7CurrentCallFrame
            INC  HL
            INC  HL
            LD   A,(HL)
            CALL Stage7ParameterAddress
            INC  HL
            INC  HL
            INC  HL
            LD   D,(HL)
            POP  AF
            LD   (Stage7PathType),A
            LD   A,D
            LD   (Stage7CallResultType),A
            CP   AggregateOpenStringTypeId
            JR   Z,Stage7CallOpenStringType
            LD   A,(Stage7PathType)
            CP   D
            JP   NZ,Stage7CallTypeFailure
            JR   Stage7CallAggregateTypeReady
Stage7CallOpenStringType:
            LD   A,(Stage7PathType)
            CP   AggregateOpenStringTypeId
            JR   Z,Stage7CallAggregateTypeReady
            CALL Stage7StringCapacity
.if CompilerDiagnosticBranches
            JP   C,Stage7CallFailure
.endif
Stage7CallAggregateTypeReady:
.if TargetStreamingOutput
            ; A cross-bank aggregate parameter must originate at a direct
            ; program root. Diagnose through the ordinary call-frame unwind.
            CALL Stage7CurrentCallFrame
            LD   DE,Stage7CallFrameFlags
            ADD  HL,DE
            LD   D,(HL)
            CALL TargetCurrentBankMatches
            JR   Z,Stage7CallAggregateBankReady
            LD   A,C
            OR   A
            JR   NZ,Stage7CallAggregateBankReady
            LD   A,DiagnosticTargetConfiguration
            CALL CompilerSetDiagnostic
.if CompilerDiagnosticBranches
            JP   Stage7CallFailure
.endif
Stage7CallAggregateBankReady:
.endif
            CALL Stage8RequireNoPendingFailure
.if CompilerDiagnosticBranches
            JP   C,Stage7CallFailure
.endif
            LD   A,(Stage7CallResultType)
            CP   AggregateOpenStringTypeId
            JR   NZ,Stage7CallArgumentReady
            CALL Stage7PrepareOpenStringArgument
.if CompilerDiagnosticBranches
            JP   C,Stage7CallFailure
.endif
Stage7CallArgumentReady:
            CALL Stage7CurrentCallFrame
            INC  HL
            INC  HL
            INC  (HL)
            INC  HL
            DEC  (HL)
            JR   Z,Stage7CallArgumentsDone
            LD   E,TokenComma
            CALL ParserExpect
.if TargetStreamingOutput
.if CompilerDiagnosticBranches
            JP   C,Stage7CallFailure
.endif
.else
.if CompilerDiagnosticBranches
            JP   C,Stage7CallFailure
.endif
.endif
            JP   Stage7CallArgumentLoop

; Convert one concrete or already-open bounded-string carrier into the two-word
; internal call form: actual capacity below the ordinary address carrier.
.routine out A,carry,zero clobbers sign,parity,halfCarry,B,C,D,DE,HL,IX,IY
Stage7PrepareOpenStringArgument:
            LD   A,(Stage7PathType)
            CP   AggregateOpenStringTypeId
            JR   Z,Stage7PrepareForwardedOpenString
            CALL Stage7StringCapacity
.if CompilerDiagnosticReturns
            RET  C
.endif
            LD   (Stage7ArgumentCount),A
            XOR  A
            JR   Stage7PrepareOpenStringReady
Stage7PrepareForwardedOpenString:
            LD   A,(Stage7OpenStringCapacityOffset)
            LD   (Stage7ArgumentCount),A
            LD   A,1
Stage7PrepareOpenStringReady:
            LD   C,A
            LD   A,SemanticPrepareOpenArgument
            CALL ParserEmitOperationC
.if CompilerDiagnosticReturns
            RET  C
.endif
            LD   A,(Stage7ArgumentCount)
            CALL SemanticSinkPut
.if CompilerDiagnosticReturns
            RET  C
.endif
            CALL Stage7CurrentCallFrame
            LD   DE,Stage7CallFrameArgumentCount
            ADD  HL,DE
            INC  (HL)
            OR   A
            RET
Stage7CallArgumentsDone:
            CALL ParserExpectRight
.if TargetStreamingOutput
.if CompilerDiagnosticBranches
            JP   C,Stage7CallFailure
.endif
.else
.if CompilerDiagnosticBranches
            JR   C,Stage7CallFailure
.endif
.endif
            CALL Stage7CurrentCallFrame
            LD   A,(HL)
            LD   (Stage7CallLabel),A
            INC  HL
            LD   A,(HL)
            LD   (Stage7CallResultType),A
            INC  HL
            INC  HL
            INC  HL
            LD   A,(HL)
            LD   (Stage7ArgumentCount),A
            INC  HL
            LD   E,(HL)
            INC  HL
            LD   D,(HL)
            LD   (Stage7CallOffset),DE
            INC  HL
            LD   A,(HL)
            LD   (Stage8CallFlags),A
            LD   HL,Stage7CallDepth
            DEC  (HL)
.if TargetStreamingOutput
            LD   A,(Stage7CallResultType)
            CP   AggregateFirstDynamicTypeId
            JR   C,Stage7CallResultBankReady
            LD   A,(Stage8CallFlags)
            LD   D,A
            CALL TargetRequireCurrentBank
.if CompilerDiagnosticReturns
            RET  C
.endif
Stage7CallResultBankReady:
.endif
            LD   A,(Stage8CallFlags)
            AND  Stage7RoutineFails
            JR   Z,Stage7CallFailureClassReady
            LD   A,(Stage7CallDepth)
            OR   A
            JP   NZ,HybridLL1FailureContext
Stage7CallFailureClassReady:
; Publish one completed call description. Stage7CallLabel contains the packed
; target, kind, and keep-result choice. Target-specific signature fields are
; present only for source routines.
Stage7PublishCallable:
            LD   A,SemanticCallGeneral
            CALL SemanticSinkOperation
.if CompilerDiagnosticReturns
            RET  C
.endif
            LD   A,(Stage7CallLabel)
            CALL SemanticSinkPut
.if CompilerDiagnosticReturns
            RET  C
.endif
            AND  Stage8CallableServiceFlag
            JR   NZ,Stage7PublishCallableCommon
            LD   A,(Stage7ArgumentCount)
            CALL SemanticSinkPut
.if CompilerDiagnosticReturns
            RET  C
.endif
            LD   A,(Stage7CallResultType)
            CALL SemanticSinkPut
.if CompilerDiagnosticReturns
            RET  C
.endif
            LD   A,(Stage8CallFlags)
            CALL SemanticSinkPut
.if CompilerDiagnosticReturns
            RET  C
.endif
Stage7PublishCallableCommon:
            LD   HL,(Stage7CallOffset)
            CALL Stage7EmitWord
.if CompilerDiagnosticReturns
            RET  C
.endif
            CALL Stage8EmitFailurePlaceholders
.if CompilerDiagnosticReturns
            RET  C
.endif
            LD   A,(Stage8CallFlags)
            AND  Stage7RoutineFails
            LD   (Stage8DirectFailable),A
            LD   A,(Stage7CallResultType)
            OR   A
            RET
Stage7CallTypeFailure:
            LD   HL,Stage7CallDepth
            DEC  (HL)
            JP   TypedTypeFailure
.if CompilerDiagnosticBranches
Stage7CallFailure:
            LD   HL,Stage7CallDepth
            DEC  (HL)
            SCF
            RET
.endif

; Parse a name-rooted aggregate path or aggregate-returning call. The result
; must still be an address path; scalar selection is rejected by this entry.
.if TargetStreamingOutput
.routine out A,C,carry,zero clobbers sign,parity,halfCarry,B,D,DE,HL,IX,IY
.else
.routine out A,carry,zero clobbers sign,parity,halfCarry,B,C,D,DE,HL,IX,IY
.endif
Stage7ParseAggregateValue:
            LD   E,TokenName
            CALL ParserExpect
.if CompilerDiagnosticReturns
            RET  C
.endif
            CALL Stage7FindRoutineCurrent
            JR   NZ,Stage7AggregateValueSymbol
            LD   C,1
            CALL Stage7ParseCall
.if CompilerDiagnosticReturns
            RET  C
.endif
            CP   AggregateFirstDynamicTypeId
            JP   C,TypedTypeFailure
.if TargetStreamingOutput
            LD   C,0
.endif
            JR   Stage7AggregateValueSuffix
Stage7AggregateValueSymbol:
            CALL Stage7LookupAggregateCurrent
.if CompilerDiagnosticReturns
            RET  C
.endif
            LD   A,D
            AND  SymbolAggregateFlag
            JP   Z,TypedTypeFailure
.if TargetStreamingOutput
            LD   A,D
            AND  SymbolClassMask
            LD   C,0
            CP   SymbolClassProgram
            JR   NZ,Stage7AggregateValueRootReady
            INC  C
Stage7AggregateValueRootReady:
            PUSH BC
            CALL Stage7EmitAggregateSymbolRoot
.if CompilerDiagnosticBranches
            JR   C,Stage7AggregateValueRootFailure
.endif
            POP  BC
            LD   A,(Stage7PathType)
            JR   Stage7AggregateValueSuffix
.if CompilerDiagnosticBranches
Stage7AggregateValueRootFailure:
            POP  BC
            SCF
            RET
.endif
.else
            CALL Stage7EmitAggregateSymbolRoot
.if CompilerDiagnosticReturns
            RET  C
.endif
.endif
Stage7AggregateValueSuffix:
.if TargetStreamingOutput
            PUSH BC
            CALL Stage7ParsePathSuffix
.if CompilerDiagnosticBranches
            JR   C,Stage7AggregateValueSuffixFailure
.endif
            POP  BC
.else
            CALL Stage7ParsePathSuffix
.if CompilerDiagnosticReturns
            RET  C
.endif
.endif
            LD   E,A
            LD   A,D
            OR   A
            JP   NZ,TypedTypeFailure
            LD   A,E
            CP   AggregateFirstDynamicTypeId
            JP   C,TypedTypeFailure
            OR   A
            RET
.if TargetStreamingOutput
.if CompilerDiagnosticBranches
Stage7AggregateValueSuffixFailure:
            POP  BC
            SCF
            RET
.endif
.endif

; Convert a scalar address path to an ordinary typed expression carrier.
.routine in A,D out A,carry,zero clobbers sign,parity,halfCarry,B,C,D,DE,HL
Stage7FinishScalarPath:
            CP   AggregateFirstDynamicTypeId
            JP   NC,TypedTypeFailure
            LD   (Stage7PathType),A
            LD   A,D
            LD   (Stage7ArgumentCount),A
            OR   A
            JR   NZ,Stage7ScalarPathReady
            LD   A,(Stage7PathType)
            CP   ScalarTypeU16
            LD   A,SemanticLoadIndirect8
            JR   NZ,Stage7ScalarPathEmit
            LD   A,SemanticLoadIndirect16
Stage7ScalarPathEmit:
            CALL SemanticSinkOperation
.if CompilerDiagnosticBranches
            JR   C,Stage7ScalarPathFailure
.endif
Stage7ScalarPathReady:
            LD   A,(Stage7PathType)
            OR   A
            RET
.if CompilerDiagnosticBranches
Stage7ScalarPathFailure:
            SCF
            RET
.endif

; Hooks entered by the scalar primary parser after it has consumed the NAME.
Stage7TypedPrimaryRoutine:
            LD   C,1
            CALL Stage7ParseCall
.if CompilerDiagnosticReturns
            RET  C
.endif
            OR   A
            JP   Z,TypedTypeFailure
            CP   AggregateFirstDynamicTypeId
            JR   NC,Stage7TypedPrimaryRoutineAggregate
            OR   A
            RET
Stage7TypedPrimaryRoutineAggregate:
            CALL Stage7ParsePathSuffix
.if CompilerDiagnosticReturns
            RET  C
.endif
            JR   Stage7FinishScalarPath

.routine in A out A,carry,zero clobbers sign,parity,halfCarry,B,C,D,DE,HL,IX,IY
Stage8TypedPrimaryService:
            LD   HL,(TokenStartOffset)
            LD   (Stage7CallOffset),HL
            LD   C,1
            JR   Stage8ParseServiceCall

.routine in A out A,B,HL,carry,zero clobbers sign,parity,halfCarry,C,D,DE,IX,IY
Stage8TypedPrimaryConstant:
            SUB  Stage8PredefinedConstantBase-1
            LD   L,A
            LD   H,0
            LD   B,ScalarMetaConstant+ScalarTypeU8
            JP   TypedPrimaryEmitTypedConstant

; A is the dense service ID and C says whether a successful u8 result is kept.
.routine in A,C out A,carry,zero clobbers sign,parity,halfCarry,B,C,D,DE,HL,IX,IY
Stage8ParseServiceCall:
            LD   E,A
            LD   D,0
            LD   HL,Stage8ServiceSignatureTable
            ADD  HL,DE
            LD   A,(HL)
            DEC  C
            JR   NZ,Stage8ServiceDescriptorReady
            OR   Stage8CallableKeepFlag
Stage8ServiceDescriptorReady:
            LD   (Stage8ServiceId),A
            CALL ParserExpectLeft
.if CompilerDiagnosticReturns
            RET  C
.endif
            LD   A,(Stage8ServiceId)
            RRCA
            RRCA
            RRCA
            AND  $03
            JR   Z,Stage8ServiceExpectRight
            LD   D,A
Stage8ServiceArgument:
            LD   HL,(Stage7CallOffset)
            PUSH HL
            LD   A,D
            CALL Stage7ParseScalarArgument
            POP  HL
            LD   (Stage7CallOffset),HL
.if CompilerDiagnosticReturns
            RET  C
.endif
Stage8ServiceExpectRight:
            CALL ParserExpectRight
.if CompilerDiagnosticReturns
            RET  C
.endif
            LD   A,(Stage8ServiceId)
            LD   (Stage7CallLabel),A
            AND  Stage8ServiceResultU8
            RLCA
            RLCA
            RLCA
Stage8ServiceResultTypeReady:
            LD   (Stage7CallResultType),A
            LD   A,Stage7RoutineFails
            LD   (Stage8CallFlags),A
            JP   Stage7PublishCallable

; Return the declared byte capacity of a bounded-string type ordinal.
.routine in A out A,carry,zero clobbers sign,parity,halfCarry,DE,HL
Stage7StringCapacity:
            CALL AggregateTypeAddress
            LD   A,(HL)
            CP   AggregateTypeKindString
            JP   NZ,TypedTypeFailure
            INC  HL
            LD   A,(HL)
            OR   A
            RET

.routine out A,BC,DE,HL,carry,zero clobbers sign,parity,halfCarry
Stage8EmitFailurePlaceholders:
            LD   HL,(SinkCursor)
            LD   (Stage8CallModePointer),HL
            LD   C,3
            XOR  A
Stage8FailurePlaceholderLoop:
            CALL SemanticSinkPut
.if CompilerDiagnosticReturns
            RET  C
.endif
            DEC  C
            JR   NZ,Stage8FailurePlaceholderLoop
            RET

Stage7TypedPrimaryAggregateSymbol:
            CALL Stage7EmitAggregateSymbolRoot
.if CompilerDiagnosticReturns
            RET  C
.endif
            JP   Stage7TypedPrimaryRoutineAggregate

; Current routine name has already been consumed as a complete statement.
.if HybridLL1Full
.else
Stage7ParseCallStatement:
            LD   C,0
            CALL Stage7ParseCall
.if CompilerDiagnosticReturns
            RET  C
.endif
            CALL ParserExpectLine
.if CompilerDiagnosticReturns
            RET  C
.endif
            JP   TypedParseStatementsContinue

; Return one exact aggregate alias and mark the structured path non-fallthrough.
Stage7ParseAggregateReturn:
            LD   A,(Stage7CurrentResultType)
            PUSH AF
            CALL Stage7ParseAggregateValue
.if CompilerDiagnosticBranches
            JR   C,Stage7AggregateReturnFailure
.endif
            LD   D,A
            POP  AF
            CP   D
            JP   NZ,TypedTypeFailure
            CALL ParserExpectLine
.if CompilerDiagnosticReturns
            RET  C
.endif
            LD   A,SemanticReturnAggregate
            CALL SemanticSinkOperation
.if CompilerDiagnosticReturns
            RET  C
.endif
            XOR  A
            LD   (ControlSequenceFallsThrough),A
            JP   TypedParseStatementsContinue
.if CompilerDiagnosticBranches
Stage7AggregateReturnFailure:
            POP  AF
            SCF
            RET
.endif
.endif

; D contains the aggregate symbol info and DeclarationPayload its root offset.
Stage7ParseAggregateAssignment:
            LD   A,D
            AND  SymbolClassMask
            JR   NZ,Stage7AggregateAssignmentWritable
            CALL SetDiagInline
            .db  DiagnosticReadOnlyAssignment
Stage7AggregateAssignmentWritable:
            CALL Stage7EmitAggregateSymbolRoot
.if CompilerDiagnosticReturns
            RET  C
.endif
            CALL Stage7ParsePathSuffix
.if CompilerDiagnosticReturns
            RET  C
.endif
            LD   E,A
            LD   A,D
            OR   A
            JP   NZ,TypedTypeFailure
            LD   A,E
            LD   (Stage7PathType),A
            CALL ParserExpectEqual
.if CompilerDiagnosticReturns
            RET  C
.endif
            LD   HL,(TokenStartOffset)
            LD   (Stage7CallOffset),HL
            LD   A,(Stage7PathType)
            CP   AggregateFirstDynamicTypeId
            JR   NC,Stage7AggregateCopyAssignment
            LD   E,A
            CALL TypedExpressionBeginRuntime
.if CompilerDiagnosticReturns
            RET  C
.endif
            LD   D,A
            LD   A,(Stage7PathType)
            LD   E,A
            LD   A,D
            CALL TypedCheckAssignable
.if CompilerDiagnosticReturns
            RET  C
.endif
            LD   A,1
            LD   (Stage8RetainedCarriers),A
            CALL Stage8SelectFailureConsumer
.if CompilerDiagnosticReturns
            RET  C
.endif
            LD   A,(Stage7PathType)
            CP   ScalarTypeU16
            LD   A,SemanticStoreIndirect8
            JR   NZ,Stage7ScalarAssignmentEmit
            LD   A,SemanticStoreIndirect16
Stage7ScalarAssignmentEmit:
            CALL SemanticSinkOperation
.if CompilerDiagnosticReturns
            RET  C
.endif
.if Stage7LL1
            RET
.else
            JP   ParserExpectLine
.endif
Stage7AggregateCopyAssignment:
            PUSH AF
            CALL Stage7ParseAggregateValue
.if CompilerDiagnosticBranches
            JR   C,Stage7AggregateCopyFailure
.endif
            LD   D,A
            POP  AF
            CP   AggregateOpenStringTypeId
            JP   Z,TypedTypeFailure
            CP   D
            JP   NZ,TypedTypeFailure
            CALL AggregateGetExtent
            LD   (Stage7PathExtent),HL
            LD   A,1
            LD   (Stage8RetainedCarriers),A
            CALL Stage8SelectFailureConsumer
.if CompilerDiagnosticReturns
            RET  C
.endif
            LD   A,SemanticCopyAggregate
            CALL SemanticSinkOperation
.if CompilerDiagnosticReturns
            RET  C
.endif
            LD   HL,(Stage7PathExtent)
            CALL Stage7EmitWord
.if CompilerDiagnosticReturns
            RET  C
.endif
            LD   HL,(Stage7CallOffset)
            CALL Stage7EmitWord
.if CompilerDiagnosticReturns
            RET  C
.endif
.if Stage7LL1
            RET
.else
            JP   ParserExpectLine
.endif
.if CompilerDiagnosticBranches
Stage7AggregateCopyFailure:
            POP  AF
            SCF
            RET
.endif

.if Stage7LL1
            .include "stage7-ll1-parser.asm"
            .include "stage7-ll1-actions.asm"
.endif
