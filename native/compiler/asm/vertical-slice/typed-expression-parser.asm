; Correctness-first typed scalar declarations and expressions.
;
; Expression results return metadata in A and, when constant, a value in HL.
; The low two metadata bits are ScalarType*, and ScalarMetaConstant marks an
; exact compile-time value. Runtime expressions are emitted as a checked
; postfix stream of 16-bit carriers; u8 and boolean carriers have a zero high
; byte. The declared type, not the carrier, controls width and compatibility.

.routine out A,B,HL,carry,zero clobbers sign,parity,halfCarry,C,DE
TypedMatchForwardName:
            LD   A,(ForwardOrdinal)
            OR   A
            RET  Z
            LD   HL,ForwardNamePointer
            JP   TokenNameRecordEquals

.routine out A,carry,zero clobbers sign,parity,halfCarry,B,DE,HL
TypedNameEqualsMain:
            LD   HL,NameMain
            LD   B,4
            JP   TokenNameEquals

.routine out A,BC,DE,HL,carry,zero clobbers sign,parity,halfCarry,IX,IY
TypedRetainDeclarationName:
            CALL TypedNameEqualsMain
            JR   C,TypedDuplicateNameFailure
            CALL TypedMatchForwardName
            JR   C,TypedDuplicateNameFailure
TypedRetainDeclarationNameReady:
            LD   HL,DeclarationNamePointer
            CALL TokenRetainNameAtHL
            LD   HL,TokenStartOffset
            LD   DE,DeclarationNamePosition
            CALL CompilerCopyPosition
            OR   A
            RET

TypedDuplicateNameFailure:
            CALL SetDiagInline
            .db  DiagnosticDuplicateName

.routine out A,carry,zero clobbers sign,parity,halfCarry,B,C,D,DE,HL
TypedRejectCurrentOrdinaryName:
            CALL SymbolFindCurrent
            JR   C,TypedDuplicateNameFailure
            CALL TypedNameEqualsMain
            JR   C,TypedDuplicateNameFailure
            OR   A
            RET

; Restore the retained declaration spelling as the current name token.
.routine out A,HL
TypedRestoreDeclarationToken:
            LD   HL,(DeclarationNamePointer)
            LD   (TokenLexemePointer),HL
            LD   A,(DeclarationNameLength)
            LD   (TokenLength),A
            RET

.routine out A,BC,DE,HL,carry,zero clobbers sign,parity,halfCarry,IX,IY
TypedPrepareCurrentWord:
            CALL TypedRestoreDeclarationToken
            PUSH BC
            PUSH DE
            LD   HL,DeclarationNamePosition
            LD   DE,TokenStartOffset
            CALL CompilerCopyPosition
.if AggregateCallSlices
.if TargetStreamingOutput
.if DebugHooks
            OUT  (DebugTraceDeclarationPort),A
.endif
.endif
.endif
.if AggregateCallSlices
            CALL Stage7RejectCurrentDeclarationName
            JR   NC,TypedPrepareCurrentRoutineClear
            POP  DE
            POP  BC
            RET
TypedPrepareCurrentRoutineClear:
.endif
            POP  DE
            POP  BC
            JP   SymbolPrepareCurrentWord

; Expression-only sink wrappers allow the same parser to evaluate static
; constant initializers without emitting runtime operations.
.routine out A,BC,DE,HL,carry,zero clobbers sign,parity,halfCarry,IX,IY
TypedEmitOperation:
            LD   D,A
            LD   A,(ExpressionEmitEnabled)
            OR   A
            LD   A,D
            RET  Z
            JP   SemanticSinkOperation

.routine out A,BC,DE,HL,carry,zero clobbers sign,parity,halfCarry,IX,IY
TypedEmitByte:
            LD   D,A
            LD   A,(ExpressionEmitEnabled)
            OR   A
            LD   A,D
            RET  Z
            JP   SemanticSinkPut

.routine out A,BC,DE,HL,carry,zero clobbers sign,parity,halfCarry,IX,IY
TypedEmitWord:
            PUSH HL
            LD   A,L
            CALL TypedEmitByte
            POP  HL
.if CompilerDiagnosticReturns
            RET  C
.endif
            LD   A,H
            JR   TypedEmitByte

; Emit one expression operation followed by a complete program address.
.if AggregateCallSlices
.routine in A,BC out A,carry,zero clobbers sign,parity,halfCarry,B,C,D,DE,HL,IX,IY
TypedEmitOperationBC:
            PUSH BC
            CALL TypedEmitOperation
            POP  HL
.if CompilerDiagnosticReturns
            RET  C
.endif
            JR   TypedEmitWord
.endif

; Push one pending binary-expression context into the bounded compiler stack.
; Retaining the operator source offset is necessary because a nested operation
; may replace the global offset before the outer operation is reduced.
.routine in A out A,HL,carry,zero clobbers sign,parity,halfCarry,B,C,DE,IX,IY
TypedExpressionAddress:
            LD   E,A
            ADD  A,A
            ADD  A,E
            ADD  A,A
            ADD  A,A
            ADD  A,E
            LD   E,A
            LD   D,0
            LD   HL,ExpressionStackBase
            ADD  HL,DE
            RET

TypedExpressionPush:
            LD   A,(ExpressionStackDepth)
            CP   ExpressionStackCapacity
            JR   NC,TypedExpressionStackFull
            CALL TypedExpressionAddress
            LD   A,(ExpressionLeftMeta)
            LD   (HL),A
            INC  HL
            LD   DE,(ExpressionLeftValue)
            LD   (HL),E
            INC  HL
            LD   (HL),D
            INC  HL
            LD   A,(ExpressionSuppressFault)
            LD   (HL),A
            INC  HL
            LD   A,(ExpressionOperator)
            LD   (HL),A
            INC  HL
            LD   DE,(ExpressionOperatorOffset)
            LD   (HL),E
            INC  HL
            LD   (HL),D
            INC  HL
            EX   DE,HL
            LD   HL,ExpressionValuePosition
            CALL CompilerCopyPosition
            LD   A,(ExpressionStackDepth)
            INC  A
            LD   (ExpressionStackDepth),A
            OR   A
            RET

TypedExpressionStackFull:
            CALL SetDiagInline
            .db  DiagnosticExpressionCapacity

; Store A/HL as the pending left result before pushing it.
.routine out A,BC,DE,HL,carry,zero clobbers sign,parity,halfCarry,IX,IY
TypedSaveLeft:
            LD   (ExpressionLeftMeta),A
            LD   (ExpressionLeftValue),HL
            JR   TypedExpressionPush

; Save the right result, then restore the most recent left result.
.routine out A,BC,DE,HL,carry,zero clobbers sign,parity,halfCarry,IX,IY
TypedRestoreOperands:
            LD   (ExpressionRightMeta),A
            LD   (ExpressionRightValue),HL
            ; Every reduction follows TypedSaveLeft. Keep the defensive test so
            ; a future parser change cannot turn a broken invariant into a
            ; wrapped address beyond CompilerWorkspaceEnd.
            LD   A,(ExpressionStackDepth)
            OR   A
            JR   Z,TypedExpressionStackUnderflow
            DEC  A
            LD   (ExpressionStackDepth),A
            CALL TypedExpressionAddress
            LD   A,(HL)
            LD   (ExpressionLeftMeta),A
            INC  HL
            LD   E,(HL)
            INC  HL
            LD   D,(HL)
            LD   (ExpressionLeftValue),DE
            INC  HL
            LD   A,(HL)
            LD   (ExpressionSuppressFault),A
            INC  HL
            LD   A,(HL)
            LD   (ExpressionOperator),A
            INC  HL
            LD   E,(HL)
            INC  HL
            LD   D,(HL)
            LD   (ExpressionOperatorOffset),DE
            INC  HL
            LD   (ExpressionLeftPositionPointer),HL
            OR   A
            RET
TypedExpressionStackUnderflow:
            CALL SetDiagInline
            .db  DiagnosticInternalOperation

TypedValueRangeFailure:
            LD   HL,ExpressionValuePosition
            JR   TypedRangeFailureAtPosition
TypedLeftRangeFailure:
            LD   HL,(ExpressionLeftPositionPointer)
TypedRangeFailureAtPosition:
            LD   DE,TokenStartOffset
            CALL CompilerCopyPosition
TypedRangeFailure:
            CALL SetDiagInline
            .db  DiagnosticIntegerRange
TypedTypeFailure:
            CALL SetDiagInline
            .db  DiagnosticTypeMismatch
TypedDivisionFailure:
            LD   B,C                     ; statically selected divide width
            LD   C,DiagnosticDivisionZero
            JR   TypedCheckedFault
TypedNarrowFailure:
            LD   B,ScalarTypeU8           ; u8(...) always has u8 result type
            LD   C,DiagnosticNarrowing
TypedCheckedFault:
            LD   A,(ExpressionSuppressFault)
            OR   A
            JR   NZ,TypedSuppressedFault
            LD   A,C
            JP   CompilerSetDiagnostic
TypedSuppressedFault:
            LD   A,B
            LD   HL,0
            OR   ScalarMetaConstant
            RET

; Resolve two integer operands. The four source metadata/value cells are live.
; C returns u8 or u16. Exact constants adopt the typed peer or expected type.
.routine out A,carry,zero clobbers sign,parity,halfCarry
TypedLeftTypeIsBoolean:
            LD   A,(ExpressionLeftMeta)
            AND  ScalarMetaTypeMask
            CP   ScalarTypeBoolean
            RET

.routine out A,carry,zero clobbers sign,parity,halfCarry
TypedDeclarationScalarType:
            LD   A,(DeclarationInfo)
            AND  ScalarMetaTypeMask
            RET

.routine out A,BC,DE,HL,carry,zero clobbers sign,parity,halfCarry,IX,IY
TypedResolveIntegerPair:
            CALL TypedLeftTypeIsBoolean
            JR   Z,TypedTypeFailure
            LD   D,A
            LD   A,(ExpressionRightMeta)
            AND  ScalarMetaTypeMask
            CP   ScalarTypeBoolean
            JR   Z,TypedTypeFailure
            LD   E,A
            LD   A,D
            OR   A
            JR   NZ,TypedResolveLeftTyped
            LD   A,E
            OR   A
            JR   NZ,TypedResolveUseRight
            LD   A,(ExpressionExpectedType)
            CP   ScalarTypeU8
            JR   Z,TypedResolveBothExactU8
            LD   C,ScalarTypeU16
            OR   A
            RET
TypedResolveBothExactU8:
            LD   HL,(ExpressionLeftValue)
            LD   A,H
            OR   A
            JR   NZ,TypedLeftRangeFailure
            LD   HL,(ExpressionRightValue)
            LD   A,H
            OR   A
            JR   NZ,TypedValueRangeFailure
            LD   C,ScalarTypeU8
            OR   A
            RET
TypedResolveUseRight:
            LD   C,E
            CP   ScalarTypeU8
            JR   NZ,TypedResolveDone
            LD   HL,(ExpressionLeftValue)
            LD   A,H
            OR   A
            JR   NZ,TypedLeftRangeFailure
TypedResolveDone:
            OR   A
            RET
TypedResolveLeftTyped:
            LD   A,E
            OR   A
            JR   NZ,TypedResolveBothTyped
            LD   C,D
            LD   A,D
            CP   ScalarTypeU8
            JR   NZ,TypedResolveDone
            LD   HL,(ExpressionRightValue)
            LD   A,H
            OR   A
            JP   NZ,TypedValueRangeFailure
            JR   TypedResolveDone
TypedResolveBothTyped:
            LD   A,D
            CP   ScalarTypeU16
            JR   Z,TypedResolveU16
            LD   A,E
            CP   ScalarTypeU16
            JR   Z,TypedResolveU16
            LD   C,ScalarTypeU8
            OR   A
            RET
TypedResolveU16:
            LD   C,ScalarTypeU16
            OR   A
            RET

.routine in A,D out A,D,carry,zero clobbers sign,parity,halfCarry
TypedRequireScalarSymbolClass:
            AND  SymbolRecordTypeFlag+SymbolAggregateFlag
            JP   NZ,TypedTypeFailure
            LD   A,D
            AND  SymbolClassMask
            RET

; Return constant in A when both operands are constant.
.routine out A,BC,DE,HL,carry,zero clobbers sign,parity,halfCarry,IX,IY
TypedBothConstant:
            LD   A,(ExpressionLeftMeta)
            AND  ScalarMetaConstant
            RET  Z
            LD   A,(ExpressionRightMeta)
            AND  ScalarMetaConstant
            RET

.routine out A,BC,DE,HL,carry,zero clobbers sign,parity,halfCarry,IX,IY
TypedMaskResultWidth:
            LD   A,C
            CP   ScalarTypeU8
            RET  NZ
            LD   H,0
            RET

; Emit a width-selected binary operation. D=u8 ordinal, E=u16 ordinal.
.routine out A,BC,DE,HL,carry,zero clobbers sign,parity,halfCarry,IX,IY
TypedEmitWidthOperation:
            LD   A,C
            CP   ScalarTypeU8
            LD   A,D
            JR   Z,TypedEmitWidthSelected
            LD   A,E
TypedEmitWidthSelected:
            JP   TypedEmitOperation

; Emit the selected operation, then retain both values only when the pair is
; compile-time constant. Carry reports emission failure; zero reports dynamic.
.routine in C,D,E out A,BC,DE,HL,carry,zero clobbers sign,parity,halfCarry,IX,IY
TypedPrepareConstantBinary:
            CALL TypedEmitWidthOperation
.if CompilerDiagnosticReturns
            RET  C
.endif
            CALL TypedBothConstant
            RET  Z
            LD   HL,(ExpressionLeftValue)
            LD   DE,(ExpressionRightValue)
            RET

; Reduce +, -, *, /, integer and, or, xor. ExpressionOperator holds the token.
.routine out A,BC,DE,HL,carry,zero clobbers sign,parity,halfCarry,IX,IY
TypedReduceIntegerBinary:
            CALL TypedResolveIntegerPair
.if CompilerDiagnosticReturns
            RET  C
.endif
            LD   A,(ExpressionOperator)
            CP   TokenPlus
            JR   Z,TypedReduceAdd
            CP   TokenMinus
            JR   Z,TypedReduceSubtract
            CP   TokenStar
            JR   Z,TypedReduceMultiply
            CP   TokenSlash
            JP   Z,TypedReduceDivide
            CP   TokenMod
            JP   Z,TypedReduceModulo
            CP   TokenAnd
            JR   Z,TypedReduceAnd
            CP   TokenXor
            JR   Z,TypedReduceXor
TypedReduceOr:
            LD   DE,SemanticOr8*$100+SemanticOr16
            CALL TypedPrepareConstantBinary
.if CompilerDiagnosticReturns
            RET  C
.endif
            LD   A,C
            RET  Z
            LD   A,L
            OR   E
            LD   L,A
            LD   A,H
            OR   D
            LD   H,A
            JP   TypedReduceIntegerConstantDone
TypedReduceXor:
            LD   DE,SemanticXor8*$100+SemanticXor16
            CALL TypedPrepareConstantBinary
.if CompilerDiagnosticReturns
            RET  C
.endif
            LD   A,C
            RET  Z
            LD   A,L
            XOR  E
            LD   L,A
            LD   A,H
            XOR  D
            LD   H,A
            JP   TypedReduceIntegerConstantDone
TypedReduceAnd:
            LD   DE,SemanticAnd8*$100+SemanticAnd16
            CALL TypedPrepareConstantBinary
.if CompilerDiagnosticReturns
            RET  C
.endif
            LD   A,C
            RET  Z
            LD   A,L
            AND  E
            LD   L,A
            LD   A,H
            AND  D
            LD   H,A
            JP   TypedReduceIntegerConstantDone
TypedReduceAdd:
            LD   D,SemanticAdd8
            LD   E,SemanticAdd16
            CALL TypedPrepareConstantBinary
.if CompilerDiagnosticReturns
            RET  C
.endif
            JP   Z,TypedReduceIntegerMeta
            ADD  HL,DE
            JR   TypedReduceIntegerConstantDone
TypedReduceSubtract:
            LD   D,SemanticSubtract8
            LD   E,SemanticSubtract16
            CALL TypedPrepareConstantBinary
.if CompilerDiagnosticReturns
            RET  C
.endif
            JR   Z,TypedReduceIntegerMeta
            OR   A
            SBC  HL,DE
            JR   TypedReduceIntegerConstantDone
TypedReduceMultiply:
            LD   D,SemanticMultiply8
            LD   E,SemanticMultiply16
            CALL TypedPrepareConstantBinary
.if CompilerDiagnosticReturns
            RET  C
.endif
            JR   Z,TypedReduceIntegerMeta
            ; Constant multiplication modulo 65536, using sixteen shift/add
            ; steps.
            PUSH BC
            LD   BC,0
            LD   A,16
TypedReduceMultiplyLoop:
            SRL  D
            RR   E
            JR   NC,TypedReduceMultiplySkip
            PUSH HL
            ADD  HL,BC
            LD   B,H
            LD   C,L
            POP  HL
TypedReduceMultiplySkip:
            ADD  HL,HL
            DEC  A
            JR   NZ,TypedReduceMultiplyLoop
            LD   H,B
            LD   L,C
            POP  BC
            JR   TypedReduceIntegerConstantDone
TypedReduceDivide:
            LD   DE,SemanticDivide8*$100+SemanticDivide16
            JR   TypedReduceDivision
TypedReduceModulo:
            LD   DE,SemanticModulo8*$100+SemanticModulo16
TypedReduceDivision:
            CALL TypedEmitWidthOperation
.if CompilerDiagnosticReturns
            RET  C
.endif
            LD   HL,(ExpressionOperatorOffset)
            CALL TypedEmitWord
.if CompilerDiagnosticReturns
            RET  C
.endif
            ; A divisor known to be zero is invalid even when the dividend is
            ; dynamic. The fault helper also implements constant short-circuit
            ; suppression, so the unevaluated Boolean arm remains admissible.
            LD   A,(ExpressionRightMeta)
            AND  ScalarMetaConstant
            JR   Z,TypedReduceDivideFold
            LD   HL,(ExpressionRightValue)
            LD   A,H
            OR   L
            JP   Z,TypedDivisionFailure
TypedReduceDivideFold:
            CALL TypedBothConstant
            JR   Z,TypedReduceIntegerMeta
            ; The earlier exact-divisor check proves DE is nonzero here.
            ; Constant unsigned division uses a bounded subtraction loop.
            LD   DE,(ExpressionRightValue)
            LD   HL,(ExpressionLeftValue)
            PUSH BC
            LD   BC,0
TypedReduceDivideLoop:
            OR   A
            SBC  HL,DE
            JR   C,TypedReduceDivideDone
            INC  BC
            JR   TypedReduceDivideLoop
TypedReduceDivideDone:
            ADD  HL,DE
            LD   A,(ExpressionOperator)
            CP   TokenMod
            JR   Z,TypedReduceDivideResultReady
            LD   H,B
            LD   L,C
TypedReduceDivideResultReady:
            POP  BC
            OR   A
TypedReduceIntegerConstantDone:
            CALL TypedMaskResultWidth
            LD   A,C
            OR   ScalarMetaConstant
            RET
TypedReduceIntegerMeta:
            LD   A,C
            OR   A
            RET

; Primary expressions.
TypedParsePrimary:
            CALL ParserTake
.if CompilerDiagnosticReturns
            RET  C
.endif
            PUSH AF
            PUSH BC
            LD   HL,TokenStartOffset
            LD   DE,ExpressionValuePosition
            CALL CompilerCopyPosition
            POP  BC
            POP  AF
            CP   TokenNumber
            JR   Z,TypedPrimaryNumber
            CP   TokenCharacter
            JR   Z,TypedPrimaryCharacter
            CP   TokenTrue
            JR   Z,TypedPrimaryTrue
            CP   TokenFalse
            JR   Z,TypedPrimaryFalse
            CP   TokenName
            JR   Z,TypedPrimaryName
            CP   TokenLeftParen
            JP   Z,TypedPrimaryParen
            CP   TokenU8
            JP   Z,TypedPrimaryNarrow
            CP   TokenU16
            JP   Z,TypedPrimaryWiden
            JP   ParserExpectedScalar
TypedPrimaryNumber:
            LD   H,B
            LD   L,C
            LD   B,ScalarMetaConstant+ScalarTypeExact
            JR   TypedPrimaryEmitTypedConstant
TypedPrimaryCharacter:
            LD   H,0
            LD   L,C
            JR   TypedPrimaryU8Constant
TypedPrimaryTrue:
            LD   HL,1
            JR   TypedPrimaryBooleanConstant
TypedPrimaryFalse:
            LD   HL,0
TypedPrimaryBooleanConstant:
            LD   B,ScalarMetaConstant+ScalarTypeBoolean
            JR   TypedPrimaryEmitTypedConstant
TypedPrimaryU8Constant:
            LD   B,ScalarMetaConstant+ScalarTypeU8
TypedPrimaryEmitTypedConstant:
            PUSH BC
            PUSH HL
            LD   A,SemanticLiteral16
            CALL TypedEmitOperation
            POP  HL
.if CompilerDiagnosticBranches
            JR   C,TypedPrimaryEmitTypedConstantFailure
.endif
            PUSH HL
            CALL TypedEmitWord
            POP  HL
            POP  BC
.if CompilerDiagnosticReturns
            RET  C
.endif
            LD   A,B
            OR   A
            RET
.if CompilerDiagnosticBranches
TypedPrimaryEmitTypedConstantFailure:
            POP  BC
            RET
.endif
TypedPrimaryName:
.if AggregateCallSlices
            CALL Stage8MatchPredefinedCurrent
            JR   NC,TypedPrimaryOrdinaryName
            CP   Stage8PredefinedConstantBase
            JP   NC,Stage8TypedPrimaryConstant
            LD   B,A
            AND  $FD                     ; readInput/readStorage map to zero
            JP   NZ,TypedTypeFailure
            LD   A,B
            JP   Stage8TypedPrimaryService
TypedPrimaryOrdinaryName:
            CALL Stage7FindRoutineCurrent
            JP   Z,Stage7TypedPrimaryRoutine
            CALL SymbolLookupCurrent
.if CompilerDiagnosticReturns
            RET  C
.endif
            LD   D,A
            AND  SymbolAggregateFlag
            JP   NZ,Stage7TypedPrimaryAggregateSymbol
            LD   A,D
            JR   TypedPrimaryNameResolved
.endif
.if AggregateCallSlices
            ; The retained routine table handles scalar calls above.
.else
            CALL TypedMatchForwardName
            JR   C,TypedPrimaryScalarCall
.endif
TypedPrimaryVariableName:
            CALL SymbolLookupCurrent
.if CompilerDiagnosticReturns
            RET  C
.endif
            LD   D,A
TypedPrimaryNameResolved:
            CALL TypedRequireScalarSymbolClass
.if CompilerDiagnosticReturns
            RET  C
.endif
            JR   Z,TypedPrimaryConstantName
            LD   A,D
            AND  ScalarMetaTypeMask
            LD   E,A
            LD   A,D
            AND  SymbolClassMask
            CP   SymbolClassProgram
            JR   Z,TypedPrimaryProgramName
            CP   SymbolClassParameter
            JR   Z,TypedPrimaryParameterName
            LD   A,E
            CP   ScalarTypeU16
            LD   A,SemanticLoadLocalU8
            JR   NZ,TypedPrimaryEmitLoad
            LD   A,SemanticLoadLocal16
            JR   TypedPrimaryEmitLoad
TypedPrimaryProgramName:
            LD   A,E
            CP   ScalarTypeU16
            LD   A,SemanticLoadProgramU8
            JR   NZ,TypedPrimaryProgramSelected
            LD   A,SemanticLoadProgram16
.if AggregateCallSlices
TypedPrimaryProgramSelected:
            PUSH DE
            CALL TypedEmitOperationBC
            POP  DE
.if CompilerDiagnosticReturns
            RET  C
.endif
            LD   A,E
            OR   A
            RET
.else
TypedPrimaryProgramSelected:
            JR   TypedPrimaryEmitLoad
.endif
TypedPrimaryParameterName:
            LD   A,E
            CP   ScalarTypeU16
            LD   A,SemanticLoadParameter8
            JR   NZ,TypedPrimaryEmitLoad
            LD   A,SemanticLoadParameter16
TypedPrimaryEmitLoad:
            PUSH DE
            PUSH BC
            CALL TypedEmitOperation
            POP  BC
            POP  DE
.if CompilerDiagnosticReturns
            RET  C
.endif
            LD   A,C
            PUSH DE
            CALL TypedEmitByte
            POP  DE
.if CompilerDiagnosticReturns
            RET  C
.endif
            LD   A,E
            OR   A
            RET
TypedPrimaryConstantName:
            LD   H,B
            LD   L,C
            LD   B,D
            SET  7,B
.if AggregateCallSlices
            JP   TypedPrimaryEmitTypedConstant
.else
            JR   TypedPrimaryEmitTypedConstant
.endif

; Parse one call to the retained scalar forward. The outer call position stays
; on the compiler stack while a nested argument call is parsed.
.if AggregateCallSlices
            ; Kept only for the pre-aggregate expression proof layouts.
.else
.routine out A,BC,DE,HL,carry,zero clobbers sign,parity,halfCarry,IX,IY
TypedPrimaryScalarCall:
            LD   HL,(TokenStartOffset)
            PUSH HL
            CALL ParserExpectLeft
.if CompilerDiagnosticBranches
            JR   C,TypedPrimaryCallFailure
.endif
            LD   A,(ExpressionExpectedType)
            LD   B,A
            LD   A,(ForwardParameterType)
            LD   C,A
            PUSH BC
            LD   (ExpressionExpectedType),A
            CALL TypedParseOr
.if CompilerDiagnosticBranches
            JR   C,TypedPrimaryCallContextFailure
.endif
            LD   D,A
            PUSH DE
            PUSH HL
            CALL ParserExpectRight
.if CompilerDiagnosticBranches
            JR   C,TypedPrimaryCallRightFailure
.endif
            POP  HL
            POP  DE
            POP  BC
            LD   A,B
            LD   (ExpressionExpectedType),A
            LD   A,C
            LD   E,A
            LD   A,D
            CALL TypedCheckAssignable
.if CompilerDiagnosticBranches
            JR   C,TypedPrimaryCallFailure
.endif
            POP  HL
            PUSH HL
            LD   A,SemanticCallScalar
            CALL TypedEmitOperation
.if CompilerDiagnosticBranches
            JR   C,TypedPrimaryCallEmitFailure
.endif
            LD   A,(ForwardOrdinal)
            CALL TypedEmitByte
.if CompilerDiagnosticBranches
            JR   C,TypedPrimaryCallEmitFailure
.endif
            LD   A,(ForwardResultType)
            CALL TypedEmitByte
.if CompilerDiagnosticBranches
            JR   C,TypedPrimaryCallEmitFailure
.endif
            POP  HL
            PUSH HL
            CALL TypedEmitWord
.if CompilerDiagnosticBranches
            JR   C,TypedPrimaryCallEmitFailure
.endif
            POP  HL
            LD   A,(ForwardResultType)
            OR   A
            RET
TypedPrimaryCallEmitFailure:
            POP  HL
            SCF
            RET
TypedPrimaryCallRightFailure:
            POP  HL
            POP  DE
TypedPrimaryCallContextFailure:
            POP  BC
            LD   A,B
            LD   (ExpressionExpectedType),A
TypedPrimaryCallFailure:
            POP  HL
            SCF
            RET
.endif
.if AggregateCallSlices
; A failable invocation remains consumable only while it is the complete,
; untouched expression. Preserve the expression result while checking that no
; pending direct failure is being enclosed by another expression form.
.routine in A,HL out A,HL,carry,zero clobbers sign,parity,halfCarry,BC,DE,IX,IY
TypedRequireComposable:
            LD   C,A
            LD   A,(Stage8DirectFailable)
            OR   A
            JP   NZ,HybridLL1FailureContext
            LD   A,C
            RET

.routine in A,HL out A,BC,DE,HL,carry,zero clobbers sign,parity,halfCarry,IX,IY
TypedComposableSaveLeft:
            CALL TypedRequireComposable
.if CompilerDiagnosticReturns
            RET  C
.endif
            JP   TypedSaveLeft

.routine in A,HL out A,BC,DE,HL,carry,zero clobbers sign,parity,halfCarry,IX,IY
TypedComposableRestoreOperands:
            CALL TypedRequireComposable
.if CompilerDiagnosticReturns
            RET  C
.endif
            JP   TypedRestoreOperands
.endif
TypedPrimaryParen:
            CALL TypedParseOr
.if CompilerDiagnosticReturns
            RET  C
.endif
            PUSH AF
            PUSH HL
            CALL ParserExpectRight
.if CompilerDiagnosticBranches
            JR   C,TypedPrimaryParenFailure
.endif
            POP  HL
            POP  AF
.if AggregateCallSlices
            JR   TypedRequireComposable
.else
            RET
.endif
.if CompilerDiagnosticBranches
TypedPrimaryParenFailure:
            POP  HL
            POP  AF
            SCF
            RET
.endif

; Parse the parenthesized operand of an explicit conversion under the
; conversion's own expected type. The enclosing expected type is restored on
; every exit; A/HL return the checked operand on success.
.routine out A,BC,DE,HL,carry,zero clobbers sign,parity,halfCarry,IX,IY
TypedParseConversionOperand:
            LD   C,A
            LD   A,(ExpressionExpectedType)
            LD   B,A
            PUSH BC
            LD   A,C
            LD   (ExpressionExpectedType),A
            CALL ParserExpectLeft
.if CompilerDiagnosticBranches
            JR   C,TypedParseConversionFailure
.endif
            CALL TypedParseOr
.if CompilerDiagnosticBranches
            JR   C,TypedParseConversionFailure
.endif
            LD   D,A
            PUSH DE
            PUSH HL
            CALL ParserExpectRight
.if CompilerDiagnosticBranches
            JR   C,TypedParseConversionRightFailure
.endif
            POP  HL
            POP  DE
            POP  BC
            LD   A,B
            LD   (ExpressionExpectedType),A
            LD   A,D
.if AggregateCallSlices
            CALL TypedRequireComposable
.if CompilerDiagnosticReturns
            RET  C
.endif
.endif
            OR   A
            RET
.if CompilerDiagnosticBranches
TypedParseConversionRightFailure:
            POP  HL
            POP  DE
TypedParseConversionFailure:
            POP  BC
            LD   A,B
            LD   (ExpressionExpectedType),A
            SCF
            RET
.endif

TypedPrimaryNarrow:
            LD   HL,(TokenStartOffset)
            LD   (ExpressionOperatorOffset),HL
            PUSH HL                       ; this conversion's trap position
            LD   A,ScalarTypeU8
            CALL TypedParseConversionOperand
.if CompilerDiagnosticBranches
            JR   C,TypedPrimaryNarrowContextFailure
.endif
            ; Restore the enclosing context while keeping this conversion's
            ; value and source offset live for the checked narrowing below.
            LD   D,A
            LD   B,H
            LD   C,L
            POP  HL
            LD   (ExpressionOperatorOffset),HL
            LD   H,B
            LD   L,C
            LD   A,D
            CALL TypedRequireIntegerMeta
.if CompilerDiagnosticReturns
            RET  C
.endif
            AND  ScalarMetaConstant
            JR   Z,TypedPrimaryDynamicNarrow
            LD   A,H
            OR   A
            JP   NZ,TypedNarrowFailure
            LD   A,ScalarMetaConstant+ScalarTypeU8
            OR   A
            RET
TypedPrimaryDynamicNarrow:
            LD   A,SemanticNarrowU8
            CALL TypedEmitOperation
.if CompilerDiagnosticReturns
            RET  C
.endif
            LD   HL,(ExpressionOperatorOffset)
            CALL TypedEmitWord
.if CompilerDiagnosticReturns
            RET  C
.endif
            LD   A,ScalarTypeU8
            OR   A
            RET
.if CompilerDiagnosticBranches
TypedPrimaryNarrowContextFailure:
            POP  HL
            SCF
            RET
.endif

.routine in A out A,D,carry,zero clobbers sign,parity,halfCarry
TypedRequireIntegerMeta:
            LD   D,A
            AND  ScalarMetaTypeMask
            CP   ScalarTypeBoolean
            JP   Z,TypedTypeFailure
            LD   A,D
            CCF                            ; valid scalar types compare below Boolean
            RET

TypedPrimaryWiden:
            LD   A,ScalarTypeU16
            CALL TypedParseConversionOperand
.if CompilerDiagnosticReturns
            RET  C
.endif
            CALL TypedRequireIntegerMeta
.if CompilerDiagnosticReturns
            RET  C
.endif
            AND  ScalarMetaConstant
            LD   A,ScalarTypeU16
            RET  Z
            OR   ScalarMetaConstant
            RET

; Unary + and - bind above multiplicative operators.
.routine out A,BC,DE,HL,carry,zero clobbers sign,parity,halfCarry,IX,IY
TypedParseUnary:
            CALL ParserPeek
.if CompilerDiagnosticReturns
            RET  C
.endif
            CP   TokenPlus
            JR   Z,TypedUnaryPlus
            CP   TokenMinus
            JR   Z,TypedUnaryMinus
            JP   TypedParsePrimary
.routine out A,BC,DE,HL,carry,zero clobbers sign,parity,halfCarry,IX,IY
TypedUnaryPlus:
            CALL ParserTake
.if CompilerDiagnosticReturns
            RET  C
.endif
            CALL TypedParseUnary
.if CompilerDiagnosticReturns
            RET  C
.endif
.if AggregateCallSlices
            CALL TypedRequireComposable
.if CompilerDiagnosticReturns
            RET  C
.endif
.endif
            CALL TypedRequireIntegerMeta
.if CompilerDiagnosticReturns
            RET  C
.endif
            OR   A
            RET
TypedUnaryMinus:
            CALL TypedUnaryPlus
.if CompilerDiagnosticReturns
            RET  C
.endif
            LD   D,A
            AND  ScalarMetaTypeMask
            JR   NZ,TypedUnaryMinusTyped
            LD   A,(ExpressionExpectedType)
            CP   ScalarTypeU8
            JR   Z,TypedUnaryMinusU8
            LD   A,ScalarTypeU16
            JR   TypedUnaryMinusResolved
TypedUnaryMinusTyped:
            LD   A,D
            AND  ScalarMetaTypeMask
TypedUnaryMinusResolved:
            LD   C,A
            CP   ScalarTypeU8
            LD   A,SemanticNegate8
            JR   Z,TypedUnaryMinusEmit
            LD   A,SemanticNegate16
TypedUnaryMinusEmit:
            CALL TypedEmitUnaryOperation
.if CompilerDiagnosticReturns
            RET  C
.endif
            LD   A,D
            AND  ScalarMetaConstant
            LD   A,C
            RET  Z
            XOR  A
            SUB  L
            LD   L,A
            LD   A,0
            SBC  A,H
            LD   H,A
            CALL TypedMaskResultWidth
            LD   A,C
            OR   ScalarMetaConstant
            RET

.routine in A,BC,DE,HL out A,BC,DE,HL,carry,zero clobbers sign,parity,halfCarry,IX,IY
TypedEmitUnaryOperation:
            PUSH BC
            PUSH DE
            PUSH HL
            CALL TypedEmitOperation
            POP  HL
            POP  DE
            POP  BC
            RET
TypedUnaryMinusU8:
            ; Width selection must not destroy evidence that the exact literal
            ; itself exceeded u8 before negation applies modulo 256.
            LD   A,D
            AND  ScalarMetaConstant
            JR   Z,TypedUnaryMinusU8Ready
            LD   A,H
            OR   A
            JP   NZ,TypedValueRangeFailure
TypedUnaryMinusU8Ready:
            LD   A,ScalarTypeU8
            JR   TypedUnaryMinusResolved

; Integer * / mod bind tighter than + -, which bind tighter than
; comparisons. B is the minimum precedence: 0 comparison, 1 additive, 2
; multiplicative, 3 a right operand that must not accept any of them.
; Comparison enums occupy ExpressionOperator values 0..5; token operators
; are all larger, so the reduce path can tell them apart. Comparisons are
; non-associative: a second relation after a reduce is DiagnosticComparisonChain.
.routine out A,BC,DE,HL,carry,zero clobbers sign,parity,halfCarry,IX,IY
TypedParseComparison:
            LD   B,0
.routine out A,BC,DE,HL,carry,zero clobbers sign,parity,halfCarry,IX,IY
TypedParseIntegerClimb:
            PUSH BC
            CALL TypedParseUnary
            POP  BC
.if CompilerDiagnosticReturns
            RET  C
.endif
TypedIntegerClimbLoop:
            PUSH AF
            PUSH HL
            LD   A,B
            CP   3
            JR   C,TypedIntegerClimbPeek
TypedIntegerClimbDonePrec:
            POP  HL
            POP  AF
            RET
TypedIntegerClimbDone:
            POP  BC
            JR   TypedIntegerClimbDonePrec
.if CompilerDiagnosticBranches
TypedIntegerClimbPeekFailure:
            POP  BC
            POP  HL
            POP  AF
            SCF
            RET
.endif
TypedIntegerClimbPeek:
            PUSH BC
            CALL ParserPeek
.if CompilerDiagnosticBranches
            JR   C,TypedIntegerClimbPeekFailure
.endif
            CP   TokenMinus
            JR   Z,TypedIntegerClimbAdd
            CP   TokenPlus
            JR   Z,TypedIntegerClimbAdd
            CP   TokenStar
            JR   Z,TypedIntegerClimbMul
            CP   TokenSlash
            JR   Z,TypedIntegerClimbMul
            CP   TokenMod
            JR   Z,TypedIntegerClimbMul
            POP  BC
            LD   D,A
            LD   A,B
            OR   A
            JR   NZ,TypedIntegerClimbDonePrec
            LD   A,D
            PUSH BC
            CALL TypedComparisonToken
            JR   NC,TypedIntegerClimbDone
            LD   A,C
            LD   (ExpressionOperator),A
            LD   C,0
            JR   TypedIntegerClimbGotPrec
TypedIntegerClimbMul:
            LD   C,2
            JR   TypedIntegerClimbGot
TypedIntegerClimbAdd:
            LD   C,1
TypedIntegerClimbGot:
            LD   (ExpressionOperator),A
TypedIntegerClimbGotPrec:
            LD   A,C
            POP  BC
            CP   B
            JR   C,TypedIntegerClimbDonePrec
            INC  A
            LD   C,A
            PUSH BC
            CALL ParserTake
.if CompilerDiagnosticBranches
            JR   C,TypedIntegerClimbTakeFailurePacked
.endif
            LD   HL,(TokenStartOffset)
            LD   (ExpressionOperatorOffset),HL
            POP  DE
            POP  HL
            POP  AF
            PUSH DE
.if AggregateCallSlices
            CALL TypedComposableSaveLeft
.else
            CALL TypedSaveLeft
.endif
.if CompilerDiagnosticReturns
            JR   NC,TypedIntegerClimbSaved
            POP  BC
            RET
TypedIntegerClimbSaved:
.endif
            POP  BC
            PUSH BC
            LD   B,C
            CALL TypedParseIntegerClimb
.if CompilerDiagnosticReturns
            JR   NC,TypedIntegerClimbRight
            POP  BC
            RET
.endif
TypedIntegerClimbRight:
.if AggregateCallSlices
            CALL TypedComposableRestoreOperands
.else
            CALL TypedRestoreOperands
.endif
.if CompilerDiagnosticReturns
            JR   NC,TypedIntegerClimbDispatch
            POP  BC
            RET
TypedIntegerClimbDispatch:
.endif
            LD   A,(ExpressionOperator)
            CP   6
            JR   C,TypedIntegerClimbCompare
            CALL TypedReduceIntegerBinary
.if CompilerDiagnosticReturns
            JR   NC,TypedIntegerClimbReduced
            POP  BC
            RET
TypedIntegerClimbReduced:
.endif
            POP  BC
            JP   TypedIntegerClimbLoop
TypedIntegerClimbCompare:
            CALL TypedReduceComparison
.if CompilerDiagnosticReturns
            JR   NC,TypedIntegerClimbCompared
            POP  BC
            RET
TypedIntegerClimbCompared:
.endif
            POP  BC
            PUSH AF
            PUSH HL
            CALL ParserPeek
.if CompilerDiagnosticBranches
            JR   C,TypedComparisonStackFailure
.endif
            CALL TypedComparisonToken
            JR   C,TypedComparisonChained
            POP  HL
            POP  AF
            RET
.if CompilerDiagnosticBranches
TypedIntegerClimbTakeFailurePacked:
            POP  DE
            POP  HL
            POP  AF
            SCF
            RET
.endif

.routine out A,BC,DE,HL,carry,zero clobbers sign,parity,halfCarry,IX,IY
TypedComparisonToken:
            LD   HL,TypedComparisonTokens
            LD   B,6
TypedComparisonTokenNext:
            CP   (HL)
            JR   Z,TypedComparisonTokenYes
            INC  HL
            INC  HL
            DJNZ TypedComparisonTokenNext
            OR   A
            RET
TypedComparisonTokenYes:
            INC  HL
            LD   C,(HL)
            SCF
            RET
TypedComparisonTokens:
            .db TokenEquals,ComparisonEqual
            .db TokenNotEqual,ComparisonNotEqual
            .db TokenLess,ComparisonLess
            .db TokenLessEqual,ComparisonLessEqual
            .db TokenGreater,ComparisonGreater
            .db TokenGreaterEqual,ComparisonGreaterEqual

.if CompilerDiagnosticBranches
TypedComparisonStackFailure:
            POP  HL
            POP  AF
            SCF
            RET
.endif
TypedComparisonChained:
            POP  HL
            POP  AF
            CALL SetDiagInline
            .db  DiagnosticComparisonChain
.routine out A,BC,DE,HL,carry,zero clobbers sign,parity,halfCarry,IX,IY
TypedReduceComparison:
            LD   A,(ExpressionLeftMeta)
            AND  ScalarMetaTypeMask
            LD   D,A
            LD   A,(ExpressionRightMeta)
            AND  ScalarMetaTypeMask
            LD   E,A
            LD   A,D
            CP   ScalarTypeBoolean
            JR   NZ,TypedComparisonInteger
            LD   A,E
            CP   ScalarTypeBoolean
            JP   NZ,TypedTypeFailure
            LD   A,(ExpressionOperator)
            CP   ComparisonNotEqual+1
            JP   NC,TypedTypeFailure
            LD   A,SemanticCompareBoolean
            JR   TypedComparisonEmit
TypedComparisonInteger:
            CALL TypedResolveIntegerPair
.if CompilerDiagnosticReturns
            RET  C
.endif
            LD   A,C
            CP   ScalarTypeU8
            LD   A,SemanticCompare8
            JR   Z,TypedComparisonEmit
            LD   A,SemanticCompare16
TypedComparisonEmit:
            CALL TypedEmitOperation
.if CompilerDiagnosticReturns
            RET  C
.endif
            LD   A,(ExpressionOperator)
            CALL TypedEmitByte
.if CompilerDiagnosticReturns
            RET  C
.endif
            CALL TypedBothConstant
            LD   A,ScalarTypeBoolean
            RET  Z
            LD   HL,(ExpressionLeftValue)
            LD   DE,(ExpressionRightValue)
            OR   A
            SBC  HL,DE
            LD   A,(ExpressionOperator)
            JR   Z,TypedComparisonWasEqual
            JR   C,TypedComparisonWasLess
            LD   C,1
            JR   TypedComparisonSelect
TypedComparisonWasEqual:
            LD   C,0
            JR   TypedComparisonSelect
TypedComparisonWasLess:
            LD   C,$FF
TypedComparisonSelect:
            ; C is -1, 0, or 1. Map the requested relation to a Boolean.
            LD   B,A
            LD   HL,0
            LD   A,B
            CP   ComparisonEqual
            JR   Z,TypedComparisonSelectEqual
            CP   ComparisonNotEqual
            JR   Z,TypedComparisonSelectNotEqual
            CP   ComparisonLess
            JR   Z,TypedComparisonSelectLess
            CP   ComparisonLessEqual
            JR   Z,TypedComparisonSelectLessEqual
            CP   ComparisonGreater
            JR   Z,TypedComparisonSelectGreater
            LD   A,C
            CP   $FF
            JR   Z,TypedComparisonConstantDone
            INC  L
            JR   TypedComparisonConstantDone
TypedComparisonSelectEqual:
            LD   A,C
            OR   A
            JR   NZ,TypedComparisonConstantDone
            INC  L
            JR   TypedComparisonConstantDone
TypedComparisonSelectNotEqual:
            LD   A,C
            OR   A
            JR   Z,TypedComparisonConstantDone
            INC  L
            JR   TypedComparisonConstantDone
TypedComparisonSelectLess:
            LD   A,C
            CP   $FF
            JR   NZ,TypedComparisonConstantDone
            INC  L
            JR   TypedComparisonConstantDone
TypedComparisonSelectLessEqual:
            LD   A,C
            CP   1
            JR   Z,TypedComparisonConstantDone
            INC  L
            JR   TypedComparisonConstantDone
TypedComparisonSelectGreater:
            LD   A,C
            CP   1
            JR   NZ,TypedComparisonConstantDone
            INC  L
TypedComparisonConstantDone:
            LD   A,ScalarMetaConstant+ScalarTypeBoolean
            OR   A
            RET

; `not` binds below comparisons and above `and`.
.routine out A,BC,DE,HL,carry,zero clobbers sign,parity,halfCarry,IX,IY
TypedParseNot:
            CALL ParserPeek
.if CompilerDiagnosticReturns
            RET  C
.endif
            CP   TokenNot
            JP   NZ,TypedParseComparison
            CALL ParserTake
.if CompilerDiagnosticReturns
            RET  C
.endif
            CALL TypedParseNot
.if CompilerDiagnosticReturns
            RET  C
.endif
.if AggregateCallSlices
            CALL TypedRequireComposable
.if CompilerDiagnosticReturns
            RET  C
.endif
.endif
            LD   D,A
            AND  ScalarMetaTypeMask
            CP   ScalarTypeBoolean
            LD   C,ScalarTypeBoolean
            LD   A,SemanticNotBoolean
            JR   Z,TypedNotEmit
            LD   A,D
            AND  ScalarMetaTypeMask
            JR   NZ,TypedNotTypedInteger
            LD   A,(ExpressionExpectedType)
            CP   ScalarTypeU8
            JR   Z,TypedNotExactU8
            LD   C,ScalarTypeU16
            LD   A,SemanticNot16
            JR   TypedNotEmit
TypedNotExactU8:
            ; As with unary minus, validate the exact operand before applying
            ; the width-specific complement and masking the result.
            LD   A,D
            AND  ScalarMetaConstant
            JR   Z,TypedNotExactU8Ready
            LD   A,H
            OR   A
            JP   NZ,TypedValueRangeFailure
TypedNotExactU8Ready:
            LD   C,ScalarTypeU8
            LD   A,SemanticNot8
            JR   TypedNotEmit
TypedNotTypedInteger:
            LD   A,D
            AND  ScalarMetaTypeMask
            LD   C,A
            CP   ScalarTypeU8
            LD   A,SemanticNot8
            JR   Z,TypedNotEmit
            LD   A,SemanticNot16
TypedNotEmit:
            CALL TypedEmitUnaryOperation
.if CompilerDiagnosticReturns
            RET  C
.endif
            LD   A,D
            AND  ScalarMetaConstant
            LD   A,C
            RET  Z
            CP   ScalarTypeBoolean
            JR   NZ,TypedNotIntegerConstant
            LD   A,L
            XOR  1
            LD   L,A
            LD   H,0
            JR   TypedNotConstantDone
TypedNotIntegerConstant:
            LD   A,L
            CPL
            LD   L,A
            LD   A,H
            CPL
            LD   H,A
            CALL TypedMaskResultWidth
TypedNotConstantDone:
            LD   A,C
            OR   ScalarMetaConstant
            RET

; Boolean short circuit is represented by prefix/suffix operations so the
; Z80 backend can branch around the right operand. Integer and/or use the
; ordinary postfix reduction.
.routine out A,BC,DE,HL,carry,zero clobbers sign,parity,halfCarry,IX,IY
TypedParseAnd:
            CALL TypedParseNot
.if CompilerDiagnosticReturns
            RET  C
.endif
TypedAndLoop:
            PUSH AF
            PUSH HL
            CALL ParserPeek
.if CompilerDiagnosticBranches
            JP   C,TypedBooleanPeekFailure
.endif
            CP   TokenAnd
            JP   NZ,TypedBooleanDone
            LD   (ExpressionOperator),A
            CALL ParserTake
.if CompilerDiagnosticBranches
            JP   C,TypedBooleanPeekFailure
.endif
            POP  HL
            POP  AF
.if AggregateCallSlices
            CALL TypedComposableSaveLeft
.else
            CALL TypedSaveLeft
.endif
.if CompilerDiagnosticReturns
            RET  C
.endif
            CALL TypedLeftTypeIsBoolean
            JR   NZ,TypedAndParseRight
            LD   A,SemanticBeginBooleanAnd
            CALL TypedEmitOperation
.if CompilerDiagnosticReturns
            RET  C
.endif
            LD   C,0
            CALL TypedBeginSuppression
TypedAndParseRight:
            CALL TypedParseNot
.if CompilerDiagnosticReturns
            RET  C
.endif
.if AggregateCallSlices
            CALL TypedComposableRestoreOperands
.else
            CALL TypedRestoreOperands
.endif
.if CompilerDiagnosticReturns
            RET  C
.endif
            CALL TypedLeftTypeIsBoolean
            JR   NZ,TypedAndInteger
            CALL TypedReduceBoolean
.if CompilerDiagnosticReturns
            RET  C
.endif
            JR   TypedAndLoop
TypedAndInteger:
            CALL TypedReduceIntegerBinary
.if CompilerDiagnosticReturns
            RET  C
.endif
            JR   TypedAndLoop

.routine out A,BC,DE,HL,carry,zero clobbers sign,parity,halfCarry,IX,IY
TypedParseOr:
            CALL TypedParseAnd
.if CompilerDiagnosticReturns
            RET  C
.endif
TypedOrLoop:
            PUSH AF
            PUSH HL
            CALL ParserPeek
.if CompilerDiagnosticBranches
            JR   C,TypedBooleanPeekFailure
.endif
            CP   TokenXor
            JR   Z,TypedOrOperator
            CP   TokenOr
            JR   NZ,TypedBooleanDone
.if AggregateCallSlices
            LD   A,(Stage8DirectFailable)
            OR   A
            JR   NZ,TypedOrFailureContext
            LD   A,TokenOr
.endif
TypedOrOperator:
            LD   (ExpressionOperator),A
            CALL ParserTake
.if CompilerDiagnosticBranches
            JR   C,TypedBooleanPeekFailure
.endif
            POP  HL
            POP  AF
            CALL TypedSaveLeft
.if CompilerDiagnosticReturns
            RET  C
.endif
            LD   A,(ExpressionOperator)
            CP   TokenXor
            JR   NZ,TypedOrBooleanLeft
            CALL TypedLeftTypeIsBoolean
            JP   Z,TypedTypeFailure
            JR   TypedOrParseRight
TypedOrBooleanLeft:
            CALL TypedLeftTypeIsBoolean
            JR   NZ,TypedOrParseRight
            LD   A,SemanticBeginBooleanOr
            CALL TypedEmitOperation
.if CompilerDiagnosticReturns
            RET  C
.endif
            LD   C,1
            CALL TypedBeginSuppression
TypedOrParseRight:
            CALL TypedParseAnd
.if CompilerDiagnosticReturns
            RET  C
.endif
.if AggregateCallSlices
            CALL TypedComposableRestoreOperands
.else
            CALL TypedRestoreOperands
.endif
.if CompilerDiagnosticReturns
            RET  C
.endif
            CALL TypedLeftTypeIsBoolean
            JR   NZ,TypedOrInteger
            CALL TypedReduceBoolean
.if CompilerDiagnosticReturns
            RET  C
.endif
            JR   TypedOrLoop
TypedBooleanDone:
            POP  HL
            POP  AF
            RET
.if AggregateCallSlices
TypedOrFailureContext:
            CALL HybridLL1FailureContext
.endif
.if CompilerDiagnosticBranches
TypedBooleanPeekFailure:
            POP  HL
            POP  AF
            SCF
            RET
.endif
TypedOrInteger:
            CALL TypedReduceIntegerBinary
.if CompilerDiagnosticReturns
            RET  C
.endif
            JR   TypedOrLoop

.routine in C out A,BC,DE,HL,carry,zero clobbers sign,parity,halfCarry,IX,IY
TypedBeginSuppression:
            LD   A,(ExpressionLeftMeta)
            AND  ScalarMetaConstant
            RET  Z
            LD   HL,(ExpressionLeftValue)
            LD   A,L
            XOR  C
            RET  NZ
            LD   HL,ExpressionSuppressFault
            INC  (HL)
            RET
.routine out A,BC,DE,HL,carry,zero clobbers sign,parity,halfCarry,IX,IY
TypedReduceBoolean:
            LD   A,(ExpressionRightMeta)
            AND  ScalarMetaTypeMask
            CP   ScalarTypeBoolean
            JP   NZ,TypedTypeFailure
            LD   A,SemanticEndBoolean
            CALL TypedEmitOperation
.if CompilerDiagnosticReturns
            RET  C
.endif
            CALL TypedBothConstant
            LD   A,ScalarTypeBoolean
            RET  Z
            LD   HL,(ExpressionLeftValue)
            LD   A,L
            OR   H
            LD   C,A
            LD   A,(ExpressionOperator)
            CP   TokenAnd
            JR   Z,TypedBooleanAndSelect
            LD   A,C
            OR   A
            JR   NZ,TypedBooleanTrue
            JR   TypedBooleanRight
TypedBooleanAndSelect:
            LD   A,C
            OR   A
            JR   Z,TypedBooleanFalse
TypedBooleanRight:
            LD   HL,(ExpressionRightValue)
            JR   TypedBooleanConstant
TypedBooleanFalse:
            LD   HL,0
            JR   TypedBooleanConstant
TypedBooleanTrue:
            LD   HL,1
TypedBooleanConstant:
            LD   A,ScalarMetaConstant+ScalarTypeBoolean
            OR   A
            RET

; Assignment compatibility resolves exact constants and the sole implicit
; widening. A/HL is the expression; E is the destination type.
.routine out A,BC,DE,HL,carry,zero clobbers sign,parity,halfCarry,IX,IY
TypedCheckAssignable:
            LD   D,A
            AND  ScalarMetaTypeMask
            JR   NZ,TypedAssignableTyped
            LD   A,E
            CP   ScalarTypeBoolean
            JP   Z,TypedTypeFailure
            CP   ScalarTypeU8
            JR   NZ,TypedAssignableExactDone
            LD   A,H
            OR   A
            JP   NZ,TypedValueRangeFailure
TypedAssignableExactDone:
            LD   A,D
            AND  ScalarMetaConstant
            OR   E
            RET
TypedAssignableTyped:
            CP   E
            JR   Z,TypedAssignableSame
            CP   ScalarTypeU8
            JP   NZ,TypedTypeFailure
            LD   A,E
            CP   ScalarTypeU16
            JP   NZ,TypedTypeFailure
TypedAssignableSame:
            LD   A,D
            AND  ScalarMetaConstant
            OR   E
            RET

.routine out A,BC,DE,HL,carry,zero clobbers sign,parity,halfCarry,IX,IY
TypedExpressionBeginRuntime:
            LD   (ExpressionExpectedType),A
.if AggregateCallSlices
            XOR  A
            LD   (Stage8DirectFailable),A
            LD   (Stage8RetainedCarriers),A
.endif
            LD   A,1
            LD   (ExpressionEmitEnabled),A
            XOR  A
            LD   (ExpressionSuppressFault),A
            LD   (ExpressionStackDepth),A
            JP   TypedParseOr
.routine out A,BC,DE,HL,carry,zero clobbers sign,parity,halfCarry,IX,IY
TypedExpressionBeginConstant:
            LD   (ExpressionExpectedType),A
            XOR  A
            LD   (ExpressionEmitEnabled),A
            LD   (ExpressionSuppressFault),A
            LD   (ExpressionStackDepth),A
            JP   TypedParseOr

; Parse u8, u16, or boolean and return ScalarType* in A.
.if HybridLL1Full
.else
.routine out A,BC,DE,HL,carry,zero clobbers sign,parity,halfCarry,IX,IY
TypedParseType:
            CALL ParserTake
.if CompilerDiagnosticReturns
            RET  C
.endif
            CP   TokenU8
            JR   Z,TypedTypeU8
            CP   TokenU16
            JR   Z,TypedTypeU16
            CP   TokenBoolean
            JR   Z,TypedTypeBoolean
            CALL SetDiagInline
            .db  DiagnosticExpectedType
TypedTypeU8:       LD A,ScalarTypeU8
                   OR A
                   RET
TypedTypeU16:      LD A,ScalarTypeU16
                   OR A
                   RET
TypedTypeBoolean:  LD A,ScalarTypeBoolean
                   OR A
                   RET
.endif

.routine out A,BC,DE,HL,carry,zero clobbers sign,parity,halfCarry,IX,IY
TypedTypeWidth:
            CP   ScalarTypeU16
            LD   A,1
            RET  NZ
            INC  A
            RET

; Emit a typed static program object. D=type, BC=offset, HL=value.
.if HybridLL1Full
.else
.routine out A,BC,DE,HL,carry,zero clobbers sign,parity,halfCarry,IX,IY
TypedEmitProgramDefinition:
            LD   A,D
            CP   ScalarTypeU16
            LD   A,SemanticDefineProgramU8
            JR   NZ,TypedEmitProgramDefinitionOp
            LD   A,SemanticDefineProgram16
TypedEmitProgramDefinitionOp:
            PUSH BC
            PUSH DE
            PUSH HL
            CALL SemanticSinkOperation
            POP  HL
            POP  DE
            POP  BC
.if CompilerDiagnosticReturns
            RET  C
.endif
            PUSH BC
            PUSH DE
.if CompilerDiagnosticReturns
            PUSH HL
            LD   A,C
            CALL SemanticSinkPut
            POP  HL
.else
            LD   A,C
            CALL SemanticSinkPutPreserveHL
.endif
            POP  DE
            POP  BC
.if CompilerDiagnosticReturns
            RET  C
.endif
            PUSH DE
            LD   A,L
.if CompilerDiagnosticReturns
            PUSH HL
            CALL SemanticSinkPut
            POP  HL
.else
            CALL SemanticSinkPutPreserveHL
.endif
            POP  DE
.if CompilerDiagnosticReturns
            RET  C
.endif
            LD   A,D
            CP   ScalarTypeU16
            JR   Z,TypedEmitProgramDefinitionHigh
            OR   A
            RET
TypedEmitProgramDefinitionHigh:
            LD   A,H
            JP   SemanticSinkPut

.routine out A,BC,DE,HL,carry,zero clobbers sign,parity,halfCarry,IX,IY
TypedParseConstantAfterName:
            CALL TypedRetainDeclarationName
.if CompilerDiagnosticReturns
            RET  C
.endif
            CALL ParserExpectEqual
.if CompilerDiagnosticReturns
            RET  C
.endif
            LD   A,ScalarTypeExact
            CALL TypedExpressionBeginConstant
.if CompilerDiagnosticReturns
            RET  C
.endif
            CALL TypedRetainInferredConstantExpression
.if CompilerDiagnosticReturns
            RET  C
.endif
            LD   A,(DeclarationInfo)
            OR   SymbolClassConstant
            LD   D,A
            LD   BC,(DeclarationPayload)
            CALL TypedPrepareCurrentWord
.if CompilerDiagnosticReturns
            RET  C
.endif
            JP   SymbolCommit

.routine in A,HL out A,BC,DE,HL,carry,zero clobbers sign,parity,halfCarry,IX,IY
TypedRetainConstantExpression:
            LD   D,A
            LD   A,(DeclarationInfo)
            LD   E,A
            LD   A,D
            CALL TypedCheckAssignable
.if CompilerDiagnosticReturns
            RET  C
.endif
            AND  ScalarMetaConstant
            JP   Z,TypedTypeFailure
            LD   (DeclarationPayload),HL
            JP   ParserExpectLine

.routine in A,HL out A,BC,DE,HL,carry,zero clobbers sign,parity,halfCarry,IX,IY
TypedRetainInferredConstantExpression:
            LD   D,A
            AND  ScalarMetaConstant
            JP   Z,TypedTypeFailure
            LD   A,D
            AND  ScalarMetaTypeMask
            CP   ScalarTypeBoolean
            LD   A,ScalarTypeExact
            JR   NZ,TypedRetainConstantTypeReady
            LD   A,ScalarTypeBoolean
TypedRetainConstantTypeReady:
            LD   (DeclarationInfo),A
            LD   (DeclarationPayload),HL
            JP   ParserExpectLine

; Current token is the variable name.
.routine out A,BC,DE,HL,carry,zero clobbers sign,parity,halfCarry,IX,IY
TypedParseProgramAfterVar:
            LD   A,(AggregateMode)
            OR   A
            JP   NZ,AggregateParseProgramAfterVar
            CALL TypedRetainDeclarationName
.if CompilerDiagnosticReturns
            RET  C
.endif
            CALL ParserExpectAs
.if CompilerDiagnosticReturns
            RET  C
.endif
            CALL TypedParseType
.if CompilerDiagnosticReturns
            RET  C
.endif
            LD   (DeclarationInfo),A
.if LegacyCompilerSlices
            ; Preserve the legacy initialized-array proof behind u8[...].
            CP   ScalarTypeU8
            JR   NZ,TypedProgramScalar
            CALL ParserPeek
.if CompilerDiagnosticReturns
            RET  C
.endif
            CP   TokenLeftBracket
            JR   NZ,TypedProgramScalar
            LD   A,(NextProgramSlot)
            LD   C,A
            LD   B,0
            LD   D,SymbolInfoProgramU8
            CALL TypedPrepareCurrentWord
.if CompilerDiagnosticReturns
            RET  C
.endif
            JP   ParserParseArrayProgramAfterU8
.endif
TypedProgramScalar:
            CALL ParserPeek
.if CompilerDiagnosticReturns
            RET  C
.endif
            CP   TokenEquals
            JR   Z,TypedProgramExplicit
            LD   HL,0
            LD   A,(DeclarationInfo)
            OR   ScalarMetaConstant
            JR   TypedProgramHaveExpression
TypedProgramExplicit:
            CALL ParserTake
.if CompilerDiagnosticReturns
            RET  C
.endif
            LD   A,(DeclarationInfo)
            CALL TypedExpressionBeginConstant
.if CompilerDiagnosticReturns
            RET  C
.endif
TypedProgramHaveExpression:
            CALL TypedRetainConstantExpression
.if CompilerDiagnosticReturns
            RET  C
.endif
            LD   A,(NextProgramSlot)
            LD   C,A
            LD   B,0
            LD   (ExpressionLeftValue),BC
            PUSH BC
            LD   A,(DeclarationInfo)
            OR   SymbolClassProgram
            LD   D,A
            CALL TypedPrepareCurrentWord
            POP  BC
.if CompilerDiagnosticReturns
            RET  C
.endif
            CALL SymbolCommit
.if CompilerDiagnosticReturns
            RET  C
.endif
            LD   BC,(ExpressionLeftValue)
            LD   HL,(DeclarationPayload)
            LD   A,(DeclarationInfo)
            LD   D,A
            CALL TypedEmitProgramDefinition
.if CompilerDiagnosticReturns
            RET  C
.endif
            LD   A,(DeclarationInfo)
            CALL TypedTypeWidth
            LD   HL,NextProgramSlot
            ADD  A,(HL)
            LD   (HL),A
            JP   TypedParseTopLevel

TypedParseTopLevel:
            CALL ParserPeek
.if CompilerDiagnosticReturns
            RET  C
.endif
            CP   TokenVar
            JR   Z,TypedTopLevelVar
            CP   TokenConst
            JR   Z,TypedTopLevelConst
            CP   TokenForward
            JR   Z,TypedTopLevelForward
            CP   TokenSub
            JP   Z,TypedParseMain
            CP   TokenRecord
            JR   Z,TypedTopLevelRecord
            CALL SetDiagInline
            .db  DiagnosticExpectedTopLevel
TypedTopLevelVar:
            CALL ParserTake
.if CompilerDiagnosticReturns
            RET  C
.endif
            LD   E,TokenName
            CALL ParserExpect
.if CompilerDiagnosticReturns
            RET  C
.endif
            JP   TypedParseProgramAfterVar
TypedTopLevelConst:
            CALL ParserTake
.if CompilerDiagnosticReturns
            RET  C
.endif
            LD   E,TokenName
            CALL ParserExpect
.if CompilerDiagnosticReturns
            RET  C
.endif
            CALL TypedParseConstantAfterName
.if CompilerDiagnosticReturns
            RET  C
.endif
            JR   TypedParseTopLevel
TypedTopLevelForward:
            CALL ParserTake
.if CompilerDiagnosticReturns
            RET  C
.endif
            JP   TypedParseForwardAfterTake
TypedTopLevelRecord:
            CALL ParserTake
.if CompilerDiagnosticReturns
            RET  C
.endif
            JP   AggregateParseRecordAfterTake
.routine out A,BC,DE,HL,carry,zero clobbers sign,parity,halfCarry,IX,IY
TypedParseTopLevelConstAfterTake:
            LD   E,TokenName
            CALL ParserExpect
.if CompilerDiagnosticReturns
            RET  C
.endif
            CALL TypedParseConstantAfterName
.if CompilerDiagnosticReturns
            RET  C
.endif
            JP   TypedParseTopLevel

; TokenForward has already been consumed. Nucleus 0.1 permits a bounded
; retained signature; this first Z80 increment supports one scalar
; parameter and one scalar result, with exact completion after main.
.routine out A,BC,DE,HL,carry,zero clobbers sign,parity,halfCarry,IX,IY
TypedParseForwardAfterTake:
            LD   E,TokenSub
            CALL ParserExpect
.if CompilerDiagnosticReturns
            RET  C
.endif
            LD   E,TokenName
            CALL ParserExpect
.if CompilerDiagnosticReturns
            RET  C
.endif
            LD   A,(ForwardOrdinal)
            OR   A
            JP   NZ,TypedDuplicateNameFailure
            CALL TypedRejectCurrentOrdinaryName
.if CompilerDiagnosticReturns
            RET  C
.endif
            CALL ParserRetainForwardName
            CALL ParserExpectLeft
.if CompilerDiagnosticReturns
            RET  C
.endif
            LD   E,TokenName
            CALL ParserExpect
.if CompilerDiagnosticReturns
            RET  C
.endif
            LD   HL,(ForwardNamePointer)
            LD   A,(ForwardNameLength)
            LD   B,A
            CALL TokenNameEquals
            JP   C,TypedDuplicateNameFailure
            CALL TypedRejectCurrentOrdinaryName
.if CompilerDiagnosticReturns
            RET  C
.endif
            CALL ParserRetainForwardParameter
            CALL ParserExpectAs
.if CompilerDiagnosticReturns
            RET  C
.endif
            CALL TypedParseType
.if CompilerDiagnosticReturns
            RET  C
.endif
            LD   (ForwardParameterType),A
            CALL ParserExpectRight
.if CompilerDiagnosticReturns
            RET  C
.endif
            CALL ParserExpectAs
.if CompilerDiagnosticReturns
            RET  C
.endif
            CALL TypedParseType
.if CompilerDiagnosticReturns
            RET  C
.endif
            LD   (ForwardResultType),A
            CALL ParserExpectLine
.if CompilerDiagnosticReturns
            RET  C
.endif
            LD   A,1
            LD   (ForwardOrdinal),A
            XOR  A
            LD   (ForwardCompleted),A
            JP   TypedParseTopLevel

TypedParseMain:
            CALL ParserTake
.if CompilerDiagnosticReturns
            RET  C
.endif
TypedParseMainAfterTake:
            CALL ParserExpectRoutineHeader
.if CompilerDiagnosticReturns
            RET  C
.endif
            LD   A,SemanticBeginMain
            CALL SemanticSinkOperation
.if CompilerDiagnosticReturns
            RET  C
.endif
            CALL ControlReset
            LD   A,(SymbolCount)
            LD   (ControlGlobalSymbolCount),A
            XOR  A
            LD   (ControlRoutineKind),A
TypedParseLocals:
            CALL TypedParseLocalRun
.if CompilerDiagnosticReturns
            RET  C
.endif
TypedParseMainStatements:
            CALL TypedParseStatements
.if CompilerDiagnosticReturns
            RET  C
.endif
            JP   TypedParseEndMain

.routine out A,BC,DE,HL,carry,zero clobbers sign,parity,halfCarry,IX,IY
TypedParseLocalDeclaration:
            LD   E,TokenName
            CALL ParserExpect
.if CompilerDiagnosticReturns
            RET  C
.endif
            CALL TypedRetainDeclarationName
.if CompilerDiagnosticReturns
            RET  C
.endif
            CALL ParserExpectAs
.if CompilerDiagnosticReturns
            RET  C
.endif
            CALL TypedParseType
.if CompilerDiagnosticReturns
            RET  C
.endif
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
            LD   A,(DeclarationInfo)
            AND  ScalarMetaTypeMask
            CALL TypedEmitLocalDeclare
.if CompilerDiagnosticReturns
            RET  C
.endif
            CALL ParserPeek
.if CompilerDiagnosticReturns
            RET  C
.endif
            CP   TokenEquals
            JR   Z,TypedLocalExplicit
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
            LD   A,(DeclarationInfo)
            AND  ScalarMetaTypeMask
            OR   ScalarMetaConstant
            JR   TypedLocalHaveExpression
TypedLocalExplicit:
            CALL ParserTake
.if CompilerDiagnosticReturns
            RET  C
.endif
            LD   A,(DeclarationInfo)
            AND  ScalarMetaTypeMask
            CALL TypedExpressionBeginRuntime
.if CompilerDiagnosticReturns
            RET  C
.endif
TypedLocalHaveExpression:
            LD   D,A
            LD   A,(DeclarationInfo)
            AND  ScalarMetaTypeMask
            LD   E,A
            LD   A,D
            CALL TypedCheckAssignable
.if CompilerDiagnosticReturns
            RET  C
.endif
            CALL ParserExpectLine
.if CompilerDiagnosticReturns
            RET  C
.endif
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
            LD   A,(DeclarationInfo)
            AND  ScalarMetaTypeMask
            CALL TypedTypeWidth
            LD   HL,NextLocalSlot
            ADD  A,(HL)
            LD   (HL),A
            OR   A
            RET

.routine out A,BC,DE,HL,carry,zero clobbers sign,parity,halfCarry,IX,IY
TypedParseLocalRun:
            CALL ParserPeek
.if CompilerDiagnosticReturns
            RET  C
.endif
            CP   TokenVar
            JR   Z,TypedParseLocalRunTake
            OR   A
            RET
TypedParseLocalRunTake:
            CALL ParserTake
.if CompilerDiagnosticReturns
            RET  C
.endif
            CALL TypedParseLocalDeclaration
.if CompilerDiagnosticReturns
            RET  C
.endif
            JR   TypedParseLocalRun
.endif

.routine out A,BC,DE,HL,carry,zero clobbers sign,parity,halfCarry,IX,IY
TypedEmitLocalDeclare:
            CP   ScalarTypeU16
            LD   A,SemanticDeclareLocalU8
            JR   NZ,TypedEmitLocalDeclareSelected
            LD   A,SemanticDeclareLocal16
TypedEmitLocalDeclareSelected:
            CALL SemanticSinkOperation
.if CompilerDiagnosticReturns
            RET  C
.endif
            LD   A,(NextLocalSlot)
            JP   SemanticSinkPut

; D is symbol info and C its byte offset.
.routine out A,BC,DE,HL,carry,zero clobbers sign,parity,halfCarry,IX,IY
TypedEmitStoreByInfo:
            LD   A,D
            AND  SymbolClassMask
            CP   SymbolClassProgram
            JR   Z,TypedStoreProgram
            CP   SymbolClassLocal
            JR   Z,TypedStoreLocal
            CP   SymbolClassParameter
            JP   NZ,TypedTypeFailure
            LD   A,D
            AND  ScalarMetaTypeMask
            CP   ScalarTypeU16
            LD   A,SemanticStoreParameter8
            JR   NZ,TypedStoreSelected
            LD   A,SemanticStoreParameter16
            JR   TypedStoreSelected
TypedStoreLocal:
            LD   A,D
            AND  ScalarMetaTypeMask
            CP   ScalarTypeU16
            LD   A,SemanticStoreLocalU8
            JR   NZ,TypedStoreSelected
            LD   A,SemanticStoreLocal16
            JR   TypedStoreSelected
TypedStoreProgram:
            LD   A,D
            AND  ScalarMetaTypeMask
            CP   ScalarTypeU16
            LD   A,SemanticStoreProgramU8
            JR   NZ,TypedStoreProgramSelected
            LD   A,SemanticStoreProgram16
TypedStoreProgramSelected:
.if AggregateCallSlices
            JP   TypedEmitOperationBC
.endif
TypedStoreSelected:
            JP   ParserEmitOperationC

.if HybridLL1Full
.else
.routine out A,BC,DE,HL,carry,zero clobbers sign,parity,halfCarry,IX,IY
TypedParseStatements:
            LD   A,1
            LD   (ControlSequenceFallsThrough),A
TypedParseStatementsContinue:
            CALL ParserPeek
.if CompilerDiagnosticReturns
            RET  C
.endif
            CP   TokenEnd
            RET  Z
            CP   TokenElseIf
            RET  Z
            CP   TokenElse
            RET  Z
            CP   TokenReturn
            JR   Z,TypedStatementReturn
            LD   C,A
TypedStatementDispatch:
            LD   A,C
            CP   TokenIf
            JR   Z,TypedStatementIf
            CP   TokenWhile
            JR   Z,TypedStatementWhile
            CP   TokenFor
            JR   Z,TypedStatementFor
            CP   TokenExit
            JP   Z,TypedStatementTransfer
            CP   TokenContinue
            JP   Z,TypedStatementTransfer
            CP   TokenName
            JP   NZ,ParserExpectedScalar
            CALL ParserTake
.if CompilerDiagnosticReturns
            RET  C
.endif
            LD   HL,NameWriteOutputByte
            LD   B,15
            CALL TokenNameEquals
            JP   C,TypedParseWrite
.if AggregateCallSlices
            CALL Stage7FindRoutineCurrent
            JP   Z,Stage7ParseCallStatement
.endif
            CALL TypedParseAssignment
.if CompilerDiagnosticReturns
            RET  C
.endif
            JP   TypedParseStatementsContinue
TypedStatementIf:
            CALL ParserTake
.if CompilerDiagnosticReturns
            RET  C
.endif
            LD   A,(ControlSequenceFallsThrough)
            PUSH AF
            CALL StructuredParseIf
.if CompilerDiagnosticBranches
            JR   C,TypedStatementControlFailure
.endif
            LD   C,A
            POP  AF
            AND  C
            LD   (ControlSequenceFallsThrough),A
            JP   TypedParseStatementsContinue
TypedStatementWhile:
            CALL ParserTake
.if CompilerDiagnosticReturns
            RET  C
.endif
            LD   A,(ControlSequenceFallsThrough)
            PUSH AF
            CALL StructuredParseWhile
            JR   TypedStatementLoopComplete
TypedStatementFor:
            CALL ParserTake
.if CompilerDiagnosticReturns
            RET  C
.endif
            LD   A,(ControlSequenceFallsThrough)
            PUSH AF
            CALL StructuredParseFor
TypedStatementLoopComplete:
.if CompilerDiagnosticBranches
            JR   C,TypedStatementControlFailure
.endif
            POP  AF
            LD   (ControlSequenceFallsThrough),A
            JP   TypedParseStatementsContinue
.if CompilerDiagnosticBranches
TypedStatementControlFailure:
            POP  AF
            SCF
            RET
.endif
TypedStatementReturn:
            CALL ParserTake
.if CompilerDiagnosticReturns
            RET  C
.endif
.if AggregateCallSlices
            LD   A,(Stage7CurrentResultType)
            CP   AggregateFirstDynamicTypeId
            JP   NC,Stage7ParseAggregateReturn
.endif
            LD   A,(ControlRoutineKind)
            CP   ControlRoutineValue
            JR   NZ,TypedRoutineFlowFailure
            LD   A,(ControlResultType)
            CALL TypedExpressionBeginRuntime
.if CompilerDiagnosticReturns
            RET  C
.endif
            LD   D,A
            LD   A,(ControlResultType)
            LD   E,A
            LD   A,D
            CALL TypedCheckAssignable
.if CompilerDiagnosticReturns
            RET  C
.endif
            CALL ParserExpectLine
.if CompilerDiagnosticReturns
            RET  C
.endif
            LD   A,SemanticReturnScalar
            CALL SemanticSinkOperation
.if CompilerDiagnosticReturns
            RET  C
.endif
            XOR  A
            LD   (ControlSequenceFallsThrough),A
            JP   TypedParseStatementsContinue
.endif
TypedRoutineFlowFailure:
            CALL SetDiagInline
            .db  DiagnosticRoutineFlow
.if HybridLL1Full
.else
TypedStatementTransfer:
            LD   (DeclarationInfo),A
            CALL ParserTake
.if CompilerDiagnosticReturns
            RET  C
.endif
            LD   A,(DeclarationInfo)
            CALL StructuredParseLoopTransfer
.if CompilerDiagnosticReturns
            RET  C
.endif
            JP   TypedParseStatementsContinue
TypedParseWrite:
            LD   HL,(TokenStartOffset)
            LD   (ExpressionCallOffset),HL
            CALL ParserExpectLeft
.if CompilerDiagnosticReturns
            RET  C
.endif
            LD   A,ScalarTypeU8
            CALL TypedExpressionBeginRuntime
.if CompilerDiagnosticReturns
            RET  C
.endif
            LD   E,ScalarTypeU8
            CALL TypedCheckAssignable
.if CompilerDiagnosticReturns
            RET  C
.endif
            CALL ParserExpectRight
.if CompilerDiagnosticReturns
            RET  C
.endif
            LD   A,SemanticWriteValueU8
            CALL SemanticSinkOperation
.if CompilerDiagnosticReturns
            RET  C
.endif
            LD   HL,(ExpressionCallOffset)
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
            CALL ParserExpectElseFailLine
.if CompilerDiagnosticReturns
            RET  C
.endif
            JP   TypedParseStatementsContinue

.routine out A,BC,DE,HL,carry,zero clobbers sign,parity,halfCarry,IX,IY
TypedParseAssignment:
            CALL SymbolLookupCurrent
.if CompilerDiagnosticReturns
            RET  C
.endif
            LD   (DeclarationInfo),A
            LD   (DeclarationPayload),BC
            LD   D,A
.if AggregateCallSlices
            AND  SymbolAggregateFlag
            JP   NZ,Stage7ParseAggregateAssignment
            LD   A,D
.endif
            AND  SymbolRecordTypeFlag+SymbolAggregateFlag
            JP   NZ,TypedTypeFailure
            LD   A,D
            AND  SymbolClassMask
            CP   SymbolClassLocal
            JR   NZ,TypedAssignmentCounterChecked
            CALL ControlCheckActiveCounter
.if CompilerDiagnosticReturns
            RET  C
.endif
TypedAssignmentCounterChecked:
            LD   A,D
            AND  SymbolClassMask
            JP   Z,TypedTypeFailure
            CALL ParserExpectEqual
.if CompilerDiagnosticReturns
            RET  C
.endif
            LD   A,(DeclarationInfo)
            AND  ScalarMetaTypeMask
            CALL TypedExpressionBeginRuntime
.if CompilerDiagnosticReturns
            RET  C
.endif
            LD   D,A
            LD   A,(DeclarationInfo)
            AND  ScalarMetaTypeMask
            LD   E,A
            LD   A,D
            CALL TypedCheckAssignable
.if CompilerDiagnosticReturns
            RET  C
.endif
            LD   BC,(DeclarationPayload)
            LD   A,(DeclarationInfo)
            LD   D,A
            CALL TypedEmitStoreByInfo
.if CompilerDiagnosticReturns
            RET  C
.endif
            JP   ParserExpectLine

TypedParseEndMain:
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
            LD   A,(ForwardOrdinal)
            OR   A
            JR   NZ,TypedParseForwardCompletion
            LD   E,TokenEof
            JP   ParserExpect

.routine out A,BC,DE,HL,carry,zero clobbers sign,parity,halfCarry,IX,IY
TypedParseForwardCompletion:
            CALL ParserPeek
.if CompilerDiagnosticReturns
            RET  C
.endif
            CP   TokenSub
            JP   NZ,TypedForwardIncomplete
            CALL ParserTake
.if CompilerDiagnosticReturns
            RET  C
.endif
            LD   D,DiagnosticForwardMismatch
            CALL ParserExpectForwardName
.if CompilerDiagnosticReturns
            RET  C
.endif
            CALL ParserExpectLine
.if CompilerDiagnosticReturns
            RET  C
.endif
            LD   A,(ControlGlobalSymbolCount)
            LD   (SymbolCount),A
            XOR  A
            LD   (NextLocalSlot),A
            LD   HL,(ForwardParameterPointer)
            LD   (TokenLexemePointer),HL
            LD   A,(ForwardParameterLength)
            LD   (TokenLength),A
            LD   A,(ForwardParameterType)
            OR   SymbolClassParameter
            LD   D,A
            LD   BC,0
            CALL SymbolPrepareCurrentWord
.if CompilerDiagnosticReturns
            RET  C
.endif
            CALL SymbolCommit
.if CompilerDiagnosticReturns
            RET  C
.endif
            LD   A,(ForwardParameterType)
            CALL TypedTypeWidth
            LD   (NextLocalSlot),A
            LD   A,ControlRoutineValue
            LD   (ControlRoutineKind),A
            LD   A,(ForwardResultType)
            LD   (ControlResultType),A
            LD   A,1
            LD   (ControlSequenceFallsThrough),A
            LD   A,SemanticBeginRoutine
            CALL SemanticSinkOperation
.if CompilerDiagnosticReturns
            RET  C
.endif
            LD   A,(ForwardOrdinal)
            CALL SemanticSinkPut
.if CompilerDiagnosticReturns
            RET  C
.endif
            LD   A,(ForwardParameterType)
            CALL SemanticSinkPut
.if CompilerDiagnosticReturns
            RET  C
.endif
TypedParseRoutineLocals:
            CALL TypedParseLocalRun
.if CompilerDiagnosticReturns
            RET  C
.endif
TypedParseRoutineStatements:
            CALL TypedParseStatements
.if CompilerDiagnosticReturns
            RET  C
.endif
            LD   A,(ControlSequenceFallsThrough)
            OR   A
            JP   NZ,TypedRoutineFlowFailure
            LD   E,TokenEnd
            CALL ParserExpect
.if CompilerDiagnosticReturns
            RET  C
.endif
            CALL ParserExpectLine
.if CompilerDiagnosticReturns
            RET  C
.endif
            LD   A,SemanticEndTypedRoutine
            CALL SemanticSinkOperation
.if CompilerDiagnosticReturns
            RET  C
.endif
            LD   A,1
            LD   (ForwardCompleted),A
            LD   E,TokenEof
            JP   ParserExpect
.endif
TypedForwardIncomplete:
            CALL SetDiagInline
            .db  DiagnosticForwardIncomplete

            .include "structured-control-parser.asm"
