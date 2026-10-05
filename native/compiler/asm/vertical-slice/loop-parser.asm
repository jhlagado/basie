; Predictive parser for the counted-loop and checked-array proof programs.

; Only the Stage 7 packed parser selects the complete grammar overlay. Nesting the
; Stage7LL1 reference keeps every older proof source independent of that flag.
.if AggregateCallSlices
.if Stage7LL1
HybridLL1Full .equ 1
.else
HybridLL1Full .equ 0
.endif
.else
HybridLL1Full .equ 0
.endif

.if AggregateCallSlices
.if TargetStreamingOutput
CompilerNonlocalDiagnostics .equ 1
.else
CompilerNonlocalDiagnostics .equ 0
.endif
.else
CompilerNonlocalDiagnostics .equ 0
.endif

.if CompilerNonlocalDiagnostics
CompilerDiagnosticReturns .equ 0
CompilerDiagnosticBranches .equ 0
.else
CompilerDiagnosticReturns .equ 1
CompilerDiagnosticBranches .equ 1
.endif

.if CompilerNonlocalDiagnostics
.routine noreturn
.else
.routine in A out A,carry clobbers zero,sign,parity,halfCarry,DE,HL
.endif
CompilerSetDiagnostic:
            LD   (DiagnosticCode),A
            LD   A,(SourcePartId)
            LD   (DiagnosticPartId),A
            LD   HL,TokenStartOffset
            LD   DE,DiagnosticOffset
            PUSH BC
            CALL CompilerCopyPosition
            POP  BC
.if CompilerNonlocalDiagnostics
            LD   SP,(CompilerAbortSp)
.endif
            SCF
            RET

.routine noreturn
SetDiagInline:
            POP  HL
            LD   A,(HL)
            JR   CompilerSetDiagnostic

; Copy one complete offset/line/column record from HL to DE. LDIR preserves
; carry, allowing diagnostic callers to establish failure after the copy.
.routine in DE,HL out BC,DE,HL clobbers parity,halfCarry
CompilerCopyPosition:
            LD   BC,6
            LDIR
            RET

; E is the expected token ordinal. An ordinary mismatch reports the token
; ordinal with DiagnosticExpectedTokenBase set.
.routine in E out A,C,carry,zero clobbers sign,parity,halfCarry,B,D,DE,HL
ParserExpect:
            PUSH DE
            CALL ParserTake
            POP  DE
.if CompilerDiagnosticReturns
            RET  C
.endif
            CP   E
            RET  Z
            LD   A,E
            OR   DiagnosticExpectedTokenBase
            JR   CompilerSetDiagnostic

; The expression parser needs one token of lookahead. Token metadata remains
; current until another tokenizer request, so buffering kind and word payload
; is sufficient for names, positions, numbers, and characters.
.routine out A,BC,carry,zero clobbers sign,parity,halfCarry,D,DE,HL
ParserPeek:
            LD   A,(ParserLookaheadKind)
            CP   $FF
            JR   NZ,ParserPeekBuffered
            CALL TokenizerNext
.if CompilerDiagnosticReturns
            RET  C
.endif
            LD   (ParserLookaheadKind),A
            LD   (ParserLookaheadValue),BC
            LD   A,(ParserLookaheadKind)
            RET
ParserPeekBuffered:
            LD   BC,(ParserLookaheadValue)
            LD   A,(ParserLookaheadKind)
            OR   A
            RET

.routine out A,BC,carry,zero clobbers sign,parity,halfCarry,D,DE,HL
ParserTake:
            CALL ParserPeek
.if CompilerDiagnosticReturns
            RET  C
.endif
            LD   D,A
            LD   A,$FF
            LD   (ParserLookaheadKind),A
            LD   A,D
            OR   A
            RET

; Frequent token checks enter the common ParserExpect tail. These wrappers
; trade one shared seven-byte body for each repeated eight-byte inline check.
.routine out A,carry,zero clobbers sign,parity,halfCarry,B,C,D,DE,HL
ParserExpectLine:
            LD   E,TokenNewline
            JR   ParserExpect
.routine out A,carry,zero clobbers sign,parity,halfCarry,B,C,D,DE,HL
ParserExpectLeft:
            LD   E,TokenLeftParen
            JR   ParserExpect
.routine out A,carry,zero clobbers sign,parity,halfCarry,B,C,D,DE,HL
ParserExpectRight:
            LD   E,TokenRightParen
            JR   ParserExpect
.routine out A,carry,zero clobbers sign,parity,halfCarry,B,C,D,DE,HL
ParserExpectAs:
            LD   E,TokenAs
            JR   ParserExpect
.if LegacyCompilerSlices
.routine out A,carry,zero clobbers sign,parity,halfCarry,B,C,D,DE,HL
ParserExpectU8:
            LD   E,TokenU8
            JP   ParserExpect

.routine out A,carry,zero clobbers sign,parity,halfCarry,B,C,D,DE,HL
ParserExpectAsU8:
            CALL ParserExpectAs
.if CompilerDiagnosticReturns
            RET  C
.endif
            JP   ParserExpectU8
.endif

.routine out A,carry,zero clobbers sign,parity,halfCarry,B,C,D,DE,HL
ParserExpectEqual:
            LD   E,TokenEquals
            JR   ParserExpect
.if LegacyCompilerSlices
.routine out A,carry,zero clobbers sign,parity,halfCarry,B,C,D,DE,HL
ParserExpectSub:
            LD   E,TokenSub
            JP   ParserExpect
.routine out A,carry,zero clobbers sign,parity,halfCarry,B,C,D,DE,HL
ParserExpectLeftBracket:
            LD   E,TokenLeftBracket
            JP   ParserExpect
.routine out A,carry,zero clobbers sign,parity,halfCarry,B,C,D,DE,HL
ParserExpectRightBracket:
            LD   E,TokenRightBracket
            JP   ParserExpect
.endif
.if HybridLL1Full
.else
.routine in B,D,HL out A,carry,zero clobbers sign,parity,halfCarry,B,C,D,DE,HL
ParserExpectNamed:
            PUSH BC
            PUSH DE
            PUSH HL
            LD   E,TokenName
            CALL ParserExpect
            POP  HL
            POP  DE
            POP  BC
.if CompilerDiagnosticReturns
            RET  C
.endif
            CALL TokenNameEquals
            JR   NC,ParserExpectNamedNo
            OR   A
            RET
ParserExpectNamedNo:
            LD   A,D
            JP   CompilerSetDiagnostic

.if LegacyCompilerSlices
.routine out A,carry,zero clobbers sign,parity,halfCarry,B,C,D,DE,HL
ParserExpectIndex:
            LD   D,DiagnosticExpectedIndex
            LD   HL,NameIndex
            LD   B,5
            JP   ParserExpectNamed

.routine out A,carry,zero clobbers sign,parity,halfCarry,B,C,D,DE,HL
ParserExpectBytes:
            LD   D,DiagnosticExpectedBytes
            LD   HL,NameBytes
            LD   B,5
            JP   ParserExpectNamed

.routine out A,carry,zero clobbers sign,parity,halfCarry,B,C,D,DE,HL
ParserExpectResult:
            LD   D,DiagnosticExpectedResult
            LD   HL,NameResult
            LD   B,6
            JP   ParserExpectNamed
.endif

; Compare the current name token with the one retained by the forward.
.routine in D out A,carry,zero clobbers sign,parity,halfCarry,B,D,DE,HL
ParserCurrentNameIsForward:
            PUSH DE
            LD   HL,(ForwardNamePointer)
            LD   A,(ForwardNameLength)
            LD   B,A
            CALL TokenNameEquals
            POP  DE
            JR   NC,ParserCurrentNameNotForward
            OR   A
            RET
ParserCurrentNameNotForward .equ ParserExpectNamedNo

.routine in D out A,carry,zero clobbers sign,parity,halfCarry,B,D,DE,HL
ParserExpectForwardName:
            PUSH DE
            LD   E,TokenName
            CALL ParserExpect
            POP  DE
.if CompilerDiagnosticReturns
            RET  C
.endif
            JP   ParserCurrentNameIsForward

; Retain the current name token as the one complete forward signature.
.routine out A,carry,zero clobbers sign,parity,halfCarry,HL
ParserRetainForwardName:
            LD   HL,(TokenLexemePointer)
            LD   (ForwardNamePointer),HL
            LD   A,(TokenLength)
            LD   (ForwardNameLength),A
            OR   A
            RET

.routine out A,carry,zero clobbers sign,parity,halfCarry,HL
ParserRetainForwardParameter:
            LD   HL,(TokenLexemePointer)
            LD   (ForwardParameterPointer),HL
            LD   A,(TokenLength)
            LD   (ForwardParameterLength),A
            OR   A
            RET
.endif

.if LegacyCompilerSlices
.routine in D out A,carry,zero clobbers sign,parity,halfCarry,B,D,DE,HL
ParserExpectForwardParameter:
            PUSH DE
            LD   E,TokenName
            CALL ParserExpect
            POP  DE
.if CompilerDiagnosticReturns
            RET  C
.endif
            LD   HL,(ForwardParameterPointer)
            LD   A,(ForwardParameterLength)
            LD   B,A
            PUSH DE
            CALL TokenNameEquals
            POP  DE
            JR   NC,ParserForwardParameterNo
            OR   A
            RET
ParserForwardParameterNo:
            LD   A,D
            JP   CompilerSetDiagnostic
.endif

.if LegacyCompilerSlices
.routine out A,carry,zero clobbers sign,parity,halfCarry,B,C,D,DE,HL
ParserExpectWrite:
            LD   E,TokenName
            CALL ParserExpect
.if CompilerDiagnosticReturns
            RET  C
.endif
            LD   HL,NameWriteOutputByte
            LD   B,15
            CALL TokenNameEquals
            JR   C,ParserExpectWriteYes
            LD   HL,NameIndex
            LD   B,5
            CALL TokenNameEquals
            JR   C,ParserActiveCounter
            CALL SetDiagInline
            .db  DiagnosticExpectedWrite
ParserActiveCounter:
            CALL SetDiagInline
            .db  DiagnosticActiveCounter
ParserExpectWriteYes:
            OR   A
            RET
.endif

.if LegacyCompilerSlices
.routine out A,C,carry,zero clobbers sign,parity,halfCarry,B,D,DE,HL
ParserExpectNumber:
            LD   E,TokenNumber
            CALL ParserExpect
.if CompilerDiagnosticReturns
            RET  C
.endif
            LD   A,C
            OR   A
            RET
.endif

; Append one operation followed by the byte in C. The helper preserves the
; operand across the sink's internal cursor work.
.routine in A,C out A,carry,zero clobbers sign,parity,halfCarry,B,D,DE,HL
ParserEmitOperationC:
            PUSH BC
            CALL SemanticSinkOperation
            POP  BC
.if CompilerDiagnosticReturns
            RET  C
.endif
            LD   A,C
            JP   SemanticSinkPut

.if LegacyCompilerSlices
; A resolved scalar symbol is represented by its class in A and its storage
; ordinal in C. Expressions emit postfix operations, leaving evaluation order
; independent of either backend's register choices.
.routine in A,C out A,carry,zero clobbers sign,parity,halfCarry,B,D,DE,HL
ParserEmitSymbolLoad:
            CP   SymbolInfoProgramU8
            JR   Z,ParserEmitProgramLoad
            CP   SymbolInfoLocalU8
            JR   NZ,ParserExpectedScalar
            LD   A,SemanticLoadLocalU8
            JP   ParserEmitOperationC
ParserEmitProgramLoad:
            LD   A,SemanticLoadProgramU8
            JP   ParserEmitOperationC

.routine in A,C out A,carry,zero clobbers sign,parity,halfCarry,B,D,DE,HL
ParserEmitSymbolStore:
            CP   SymbolInfoProgramU8
            JR   Z,ParserEmitProgramStore
            CP   SymbolInfoLocalU8
            JR   NZ,ParserExpectedScalar
            LD   A,SemanticStoreLocalU8
            JP   ParserEmitOperationC
ParserEmitProgramStore:
            LD   A,SemanticStoreProgramU8
            JP   ParserEmitOperationC
.endif

ParserExpectedScalar:
            LD   A,DiagnosticExpectedScalar
            ; The legacy proof layouts put this target outside JR range.
.if AggregateCallSlices
            JR   CompilerSetDiagnostic
.else
            JP   CompilerSetDiagnostic
.endif

.if LegacyCompilerSlices
.routine out A,carry,zero clobbers sign,parity,halfCarry,B,C,D,DE,HL
ParserParseScalarPrimary:
            CALL ParserTake
.if CompilerDiagnosticReturns
            RET  C
.endif
            CP   TokenNumber
            JR   Z,ParserParseScalarLiteral
            CP   TokenName
            JR   NZ,ParserExpectedScalar
            CALL SymbolLookupCurrent
.if CompilerDiagnosticReturns
            RET  C
.endif
            JP   ParserEmitSymbolLoad
ParserParseScalarLiteral:
            LD   A,SemanticLiteralU8
            JP   ParserEmitOperationC

; Precedence climbing uses one loop for both admitted operators. B is the
; minimum precedence; recursive calls only represent nested precedence, not a
; separate parser routine per grammar level.
.routine in B out A,carry,zero clobbers sign,parity,halfCarry,B,C,D,DE,HL
ParserParseScalarExpressionMin:
            PUSH BC
            CALL ParserParseScalarPrimary
            POP  BC
.if CompilerDiagnosticReturns
            RET  C
.endif
ParserParseScalarExpressionLoop:
            PUSH BC
            CALL ParserPeek
            POP  BC
.if CompilerDiagnosticReturns
            RET  C
.endif
            CP   TokenPlus
            JR   Z,ParserScalarPlus
            CP   TokenStar
            JR   NZ,ParserScalarExpressionDone
            LD   C,2
            LD   D,SemanticMultiplyU8
            JR   ParserScalarOperator
ParserScalarPlus:
            LD   C,1
            LD   D,SemanticAddU8
ParserScalarOperator:
            LD   A,C
            CP   B
            JR   C,ParserScalarExpressionDone
            PUSH BC
            PUSH DE
            CALL ParserTake
            POP  DE
            POP  BC
.if CompilerDiagnosticReturns
            RET  C
.endif
            PUSH BC
            PUSH DE
            LD   B,C
            INC  B
            CALL ParserParseScalarExpressionMin
            POP  DE
            POP  BC
.if CompilerDiagnosticReturns
            RET  C
.endif
            LD   A,D
            PUSH BC
            CALL SemanticSinkOperation
            POP  BC
.if CompilerDiagnosticReturns
            RET  C
.endif
            JR   ParserParseScalarExpressionLoop
ParserScalarExpressionDone:
            OR   A
            RET

.routine out A,carry,zero clobbers sign,parity,halfCarry,B,C,D,DE,HL
ParserParseScalarExpression:
            LD   B,1
            JP   ParserParseScalarExpressionMin
.endif

.if HybridLL1Full
.else
.routine out A,carry,zero clobbers sign,parity,halfCarry,B,C,D,DE,HL
ParserExpectRoutineHeader:
            LD   D,DiagnosticExpectedMain
            LD   HL,NameMain
            LD   B,4
            CALL ParserExpectNamed
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
            LD   E,TokenFails
            CALL ParserExpect
.if CompilerDiagnosticReturns
            RET  C
.endif
            JP   ParserExpectLine
.endif

.if LegacyCompilerSlices
.routine out A,carry,zero clobbers sign,parity,halfCarry,B,C,D,DE,HL
ParserExpectIndexDeclaration:
            LD   E,TokenVar
            CALL ParserExpect
.if CompilerDiagnosticReturns
            RET  C
.endif
            CALL ParserExpectIndex
.if CompilerDiagnosticReturns
            RET  C
.endif
            CALL ParserExpectAs
.if CompilerDiagnosticReturns
            RET  C
.endif
            CALL ParserExpectU8
.if CompilerDiagnosticReturns
            RET  C
.endif
            JP   ParserExpectEqual
.endif

.if HybridLL1Full
            ; Packed actions consume the active `else fail` grammar.
.else
.routine out A,carry,zero clobbers sign,parity,halfCarry,B,C,D,DE,HL
ParserExpectElseFailLine:
            CALL ParserExpectElseFail
.if CompilerDiagnosticReturns
            RET  C
.endif
            ; The legacy proof layouts put this target outside JR range.
.if AggregateCallSlices
            JR   ParserExpectLine
.else
            JP   ParserExpectLine
.endif

.routine out A,carry,zero clobbers sign,parity,halfCarry,B,C,D,DE,HL
ParserExpectElseFail:
            LD   E,TokenElse
            CALL ParserExpect
.if CompilerDiagnosticReturns
            RET  C
.endif
            LD   E,TokenFail
            ; The legacy proof layouts put this target outside JR range.
.if AggregateCallSlices
            JR   ParserExpect
.else
            JP   ParserExpect
.endif
.endif

.if LegacyCompilerSlices
.routine out A,carry,zero clobbers sign,parity,halfCarry,B,C,D,DE,HL
ParserExpectPropagateLine:
            CALL ParserExpectElseFailLine
.if CompilerDiagnosticReturns
            RET  C
.endif
            LD   A,SemanticPropagate
            JP   SemanticSinkOperation

.routine out A,carry,zero clobbers sign,parity,halfCarry,B,C,D,DE,HL
ParserExpectEndLine:
            LD   E,TokenEnd
            CALL ParserExpect
.if CompilerDiagnosticReturns
            RET  C
.endif
            JP   ParserExpectLine

.routine out A,carry,zero clobbers sign,parity,halfCarry,B,C,D,DE,HL
ParserParseLoopProgramAfterSub:
            CALL ParserExpectRoutineHeader
.if CompilerDiagnosticReturns
            RET  C
.endif

            CALL ParserExpectIndexDeclaration
.if CompilerDiagnosticReturns
            RET  C
.endif
            LD   A,SemanticDeclareU8
            CALL SemanticSinkOperation
.if CompilerDiagnosticReturns
            RET  C
.endif
            CALL ParserExpectNumber
.if CompilerDiagnosticReturns
            RET  C
.endif
            CALL SemanticSinkPut
.if CompilerDiagnosticReturns
            RET  C
.endif
            CALL ParserExpectLine
.if CompilerDiagnosticReturns
            RET  C
.endif

            LD   E,TokenFor
            CALL ParserExpect
.if CompilerDiagnosticReturns
            RET  C
.endif
            CALL ParserExpectIndex
.if CompilerDiagnosticReturns
            RET  C
.endif
            CALL ParserExpectEqual
.if CompilerDiagnosticReturns
            RET  C
.endif
            LD   A,SemanticForUntilU8
            CALL SemanticSinkOperation
.if CompilerDiagnosticReturns
            RET  C
.endif
            CALL ParserExpectNumber
.if CompilerDiagnosticReturns
            RET  C
.endif
            CALL SemanticSinkPut
.if CompilerDiagnosticReturns
            RET  C
.endif
            LD   E,TokenUntil
            CALL ParserExpect
.if CompilerDiagnosticReturns
            RET  C
.endif
            CALL ParserExpectNumber
.if CompilerDiagnosticReturns
            RET  C
.endif
            CALL SemanticSinkPut
.if CompilerDiagnosticReturns
            RET  C
.endif
            CALL ParserExpectLine
.if CompilerDiagnosticReturns
            RET  C
.endif

            CALL ParserExpectWrite
.if CompilerDiagnosticReturns
            RET  C
.endif
            CALL ParserExpectLeft
.if CompilerDiagnosticReturns
            RET  C
.endif
            LD   A,SemanticWriteOutputByte
            CALL SemanticSinkOperation
.if CompilerDiagnosticReturns
            RET  C
.endif
            LD   E,TokenCharacter
            CALL ParserExpect
.if CompilerDiagnosticReturns
            RET  C
.endif
            LD   A,C
            CALL SemanticSinkPut
.if CompilerDiagnosticReturns
            RET  C
.endif
            CALL ParserExpectRight
.if CompilerDiagnosticReturns
            RET  C
.endif
            CALL ParserExpectPropagateLine
.if CompilerDiagnosticReturns
            RET  C
.endif

            CALL ParserExpectEndLine
.if CompilerDiagnosticReturns
            RET  C
.endif
            LD   A,SemanticEndLoop
            CALL SemanticSinkOperation
.if CompilerDiagnosticReturns
            RET  C
.endif
            JP   ParserFinishRoutine
.endif

; The first general scalar path admits bounded program variables and scalar
; locals, then parses a main body as assignment and output statements. The
; current token is the program variable's name on entry.
.if LegacyCompilerSlices
.routine out A,carry,zero clobbers sign,parity,halfCarry,B,C,D,DE,HL
ParserParseScalarProgramDeclaration:
            LD   A,(NextProgramSlot)
            LD   E,A
            LD   D,SymbolInfoProgramU8
            CALL SymbolPrepareCurrent
.if CompilerDiagnosticReturns
            RET  C
.endif
            JP   ParserParseScalarProgramDeclarationAfterPrepare
.routine out A,carry,zero clobbers sign,parity,halfCarry,B,C,D,DE,HL
ParserParseScalarProgramDeclarationAfterPrepare:
            CALL ParserExpectAsU8
.if CompilerDiagnosticReturns
            RET  C
.endif
            JP   ParserParseScalarProgramDeclarationAfterU8
.routine out A,carry,zero clobbers sign,parity,halfCarry,B,C,D,DE,HL
ParserParseScalarProgramDeclarationAfterU8:
            CALL ParserExpectEqual
.if CompilerDiagnosticReturns
            RET  C
.endif
            CALL ParserExpectNumber
.if CompilerDiagnosticReturns
            RET  C
.endif
            LD   B,0
            PUSH BC
            LD   A,SemanticDefineProgramU8
            CALL SemanticSinkOperation
.if CompilerDiagnosticBranches
            JR   C,ParserScalarProgramOperandFailure
.endif
            LD   A,(NextProgramSlot)
            CALL SemanticSinkPut
.if CompilerDiagnosticBranches
            JR   C,ParserScalarProgramOperandFailure
.endif
            POP  BC
            LD   A,C
            CALL SemanticSinkPut
.if CompilerDiagnosticReturns
            RET  C
.endif
            CALL ParserExpectLine
.if CompilerDiagnosticReturns
            RET  C
.endif
            CALL SymbolCommit
            LD   HL,NextProgramSlot
            INC  (HL)
            XOR  A
            RET
.if CompilerDiagnosticBranches
ParserScalarProgramOperandFailure:
            POP  BC
            RET
.endif

.routine out A,carry,zero clobbers sign,parity,halfCarry,B,C,D,DE,HL
ParserParseScalarLocalDeclaration:
            LD   E,TokenName
            CALL ParserExpect
.if CompilerDiagnosticReturns
            RET  C
.endif
            LD   A,(NextLocalSlot)
            LD   E,A
            LD   D,SymbolInfoLocalU8
            CALL SymbolPrepareCurrent
.if CompilerDiagnosticReturns
            RET  C
.endif
            CALL ParserExpectAsU8
.if CompilerDiagnosticReturns
            RET  C
.endif
            CALL ParserExpectEqual
.if CompilerDiagnosticReturns
            RET  C
.endif
            LD   A,(NextLocalSlot)
            LD   C,A
            LD   A,SemanticDeclareLocalU8
            CALL ParserEmitOperationC
.if CompilerDiagnosticReturns
            RET  C
.endif
            CALL ParserParseScalarExpression
.if CompilerDiagnosticReturns
            RET  C
.endif
            LD   A,(NextLocalSlot)
            LD   C,A
            LD   A,SemanticStoreLocalU8
            CALL ParserEmitOperationC
.if CompilerDiagnosticReturns
            RET  C
.endif
            CALL ParserExpectLine
.if CompilerDiagnosticReturns
            RET  C
.endif
            CALL SymbolCommit
            LD   HL,NextLocalSlot
            INC  (HL)
            XOR  A
            RET

.routine out A,carry,zero clobbers sign,parity,halfCarry,B,C,D,DE,HL
ParserParseScalarAssignment:
            CALL SymbolLookupCurrent
.if CompilerDiagnosticReturns
            RET  C
.endif
            LD   B,A
            PUSH BC
            CALL ParserExpectEqual
.if CompilerDiagnosticBranches
            JR   C,ParserScalarAssignmentFailure
.endif
            CALL ParserParseScalarExpression
.if CompilerDiagnosticBranches
            JR   C,ParserScalarAssignmentFailure
.endif
            POP  BC
            LD   A,B
            CALL ParserEmitSymbolStore
.if CompilerDiagnosticReturns
            RET  C
.endif
            JP   ParserExpectLine
.if CompilerDiagnosticBranches
ParserScalarAssignmentFailure:
            POP  BC
            RET
.endif

.routine out A,carry,zero clobbers sign,parity,halfCarry,B,C,D,DE,HL
ParserParseScalarWrite:
            LD   HL,(TokenStartOffset)
            PUSH HL
            CALL ParserExpectLeft
.if CompilerDiagnosticBranches
            JR   C,ParserScalarWriteFailure
.endif
            CALL ParserParseScalarExpression
.if CompilerDiagnosticBranches
            JR   C,ParserScalarWriteFailure
.endif
            CALL ParserExpectRight
.if CompilerDiagnosticBranches
            JR   C,ParserScalarWriteFailure
.endif
            LD   A,SemanticWriteValueU8
            CALL SemanticSinkOperation
.if CompilerDiagnosticBranches
            JR   C,ParserScalarWriteFailure
.endif
            POP  HL
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
            JP   ParserExpectElseFailLine
.if CompilerDiagnosticBranches
ParserScalarWriteFailure:
            POP  HL
            RET
.endif

.routine out A,carry,zero clobbers sign,parity,halfCarry,B,C,D,DE,HL
ParserParseScalarStatements:
            CALL ParserPeek
.if CompilerDiagnosticReturns
            RET  C
.endif
            CP   TokenEnd
            JR   Z,ParserParseScalarEnd
            CP   TokenName
            JP   NZ,ParserExpectedScalar
            CALL ParserTake
.if CompilerDiagnosticReturns
            RET  C
.endif
            LD   HL,NameWriteOutputByte
            LD   B,15
            CALL TokenNameEquals
            JR   NC,ParserParseScalarAssignmentStatement
            CALL ParserParseScalarWrite
.if CompilerDiagnosticReturns
            RET  C
.endif
            JR   ParserParseScalarStatements
ParserParseScalarAssignmentStatement:
            CALL ParserParseScalarAssignment
.if CompilerDiagnosticReturns
            RET  C
.endif
            JR   ParserParseScalarStatements
ParserParseScalarEnd:
            CALL ParserTake
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

.routine out A,carry,zero clobbers sign,parity,halfCarry,B,C,D,DE,HL
ParserParseScalarTopLevel:
            CALL ParserPeek
.if CompilerDiagnosticReturns
            RET  C
.endif
            CP   TokenVar
            JR   NZ,ParserParseScalarMain
            CALL ParserTake
.if CompilerDiagnosticReturns
            RET  C
.endif
            LD   E,TokenName
            CALL ParserExpect
.if CompilerDiagnosticReturns
            RET  C
.endif
            CALL ParserParseScalarProgramDeclaration
.if CompilerDiagnosticReturns
            RET  C
.endif
            JR   ParserParseScalarTopLevel
ParserParseScalarMain:
            CP   TokenSub
            JR   NZ,ParserScalarExpectedTopLevel
            CALL ParserTake
.if CompilerDiagnosticReturns
            RET  C
.endif
            CALL ParserExpectRoutineHeader
.if CompilerDiagnosticReturns
            RET  C
.endif
            LD   A,SemanticBeginMain
            CALL SemanticSinkOperation
.if CompilerDiagnosticReturns
            RET  C
.endif
ParserParseScalarLocals:
            CALL ParserPeek
.if CompilerDiagnosticReturns
            RET  C
.endif
            CP   TokenVar
            JR   NZ,ParserParseScalarStatements
            CALL ParserTake
.if CompilerDiagnosticReturns
            RET  C
.endif
            CALL ParserParseScalarLocalDeclaration
.if CompilerDiagnosticReturns
            RET  C
.endif
            JR   ParserParseScalarLocals
ParserScalarExpectedTopLevel:
            CALL SetDiagInline
            .db  DiagnosticExpectedTopLevel
.endif

.if HybridLL1Full
.else
.routine out A,carry,zero clobbers sign,parity,halfCarry,B,C,D,DE,HL,IX,IY
ParserParseProgramAfterVar:
            LD   E,TokenName
            CALL ParserExpect
.if CompilerDiagnosticReturns
            RET  C
.endif
            JP   TypedParseProgramAfterVar
.endif

; The older array slice is selected by the bracketed type suffix. Its body is
; still deliberately fixed; this split only keeps scalar names unrestricted.
.if LegacyCompilerSlices
.routine out A,carry,zero clobbers sign,parity,halfCarry,B,C,D,DE,HL
ParserParseArrayProgramAfterU8:
            CALL ParserExpectLeftBracket
.if CompilerDiagnosticReturns
            RET  C
.endif
            LD   A,SemanticStaticU8Array
            CALL SemanticSinkOperation
.if CompilerDiagnosticReturns
            RET  C
.endif
            CALL ParserExpectNumber
.if CompilerDiagnosticReturns
            RET  C
.endif
            CP   4
            JR   Z,ParserArrayLengthYes
            CALL SetDiagInline
            .db  DiagnosticExpectedArrayLength
ParserArrayLengthYes:
            CALL SemanticSinkPut
.if CompilerDiagnosticReturns
            RET  C
.endif
            CALL ParserExpectRightBracket
.if CompilerDiagnosticReturns
            RET  C
.endif
            CALL ParserExpectEqual
.if CompilerDiagnosticReturns
            RET  C
.endif
            CALL ParserExpectLeftBracket
.if CompilerDiagnosticReturns
            RET  C
.endif
            LD   C,4
ParserArrayInitializer:
            PUSH BC
            CALL ParserExpectNumber
            POP  BC
.if CompilerDiagnosticReturns
            RET  C
.endif
            CALL SemanticSinkPut
.if CompilerDiagnosticReturns
            RET  C
.endif
            DEC  C
            JR   Z,ParserArrayInitializerDone
            PUSH BC
            LD   E,TokenComma
            CALL ParserExpect
            POP  BC
.if CompilerDiagnosticReturns
            RET  C
.endif
            JR   ParserArrayInitializer
ParserArrayInitializerDone:
            CALL ParserExpectRightBracket
.if CompilerDiagnosticReturns
            RET  C
.endif
            CALL ParserExpectLine
.if CompilerDiagnosticReturns
            RET  C
.endif

            LD   E,TokenSub
            CALL ParserExpect
.if CompilerDiagnosticReturns
            RET  C
.endif
            CALL ParserExpectRoutineHeader
.if CompilerDiagnosticReturns
            RET  C
.endif

            CALL ParserExpectIndexDeclaration
.if CompilerDiagnosticReturns
            RET  C
.endif
            LD   D,DiagnosticExpectedRead
            LD   HL,NameReadInputByte
            LD   B,13
            CALL ParserExpectNamed
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
            LD   A,SemanticReadInputByte
            CALL SemanticSinkOperation
.if CompilerDiagnosticReturns
            RET  C
.endif
            CALL ParserExpectPropagateLine
.if CompilerDiagnosticReturns
            RET  C
.endif
            LD   A,SemanticStoreResultU8
            CALL SemanticSinkOperation
.if CompilerDiagnosticReturns
            RET  C
.endif

            CALL ParserExpectWrite
.if CompilerDiagnosticReturns
            RET  C
.endif
            CALL ParserExpectLeft
.if CompilerDiagnosticReturns
            RET  C
.endif
            CALL ParserExpectBytes
.if CompilerDiagnosticReturns
            RET  C
.endif
            CALL ParserExpectLeftBracket
.if CompilerDiagnosticReturns
            RET  C
.endif
            CALL ParserExpectIndex
.if CompilerDiagnosticReturns
            RET  C
.endif
            CALL ParserExpectRightBracket
.if CompilerDiagnosticReturns
            RET  C
.endif
            CALL ParserExpectRight
.if CompilerDiagnosticReturns
            RET  C
.endif
            LD   A,SemanticLoadArrayU8
            CALL SemanticSinkOperation
.if CompilerDiagnosticReturns
            RET  C
.endif
            LD   A,SemanticWriteOutputU8
            CALL SemanticSinkOperation
.if CompilerDiagnosticReturns
            RET  C
.endif
            CALL ParserExpectPropagateLine
.if CompilerDiagnosticReturns
            RET  C
.endif
.routine out A,carry,zero clobbers sign,parity,halfCarry,B,C,D,DE,HL
ParserFinishRoutine:
            CALL ParserExpectEndLine
.if CompilerDiagnosticReturns
            RET  C
.endif
            LD   A,SemanticReturn
            CALL SemanticSinkOperation
.if CompilerDiagnosticReturns
            RET  C
.endif
            LD   E,TokenEof
            JP   ParserExpect
.endif

; Parse the first general routine-call slice. It deliberately admits one
; retained forward signature while exercising exact completion and parameter
; lookup, scalar call/result flow, and direct recursion.
.if LegacyCompilerSlices
.routine out A,carry,zero clobbers sign,parity,halfCarry,B,C,D,DE,HL
ParserParseCallProgramAfterForward:
            CALL ParserExpectSub
.if CompilerDiagnosticReturns
            RET  C
.endif
            LD   E,TokenName
            CALL ParserExpect
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
            CALL ParserRetainForwardParameter
            CALL ParserExpectAsU8
.if CompilerDiagnosticReturns
            RET  C
.endif
            CALL ParserExpectRight
.if CompilerDiagnosticReturns
            RET  C
.endif
            CALL ParserExpectAsU8
.if CompilerDiagnosticReturns
            RET  C
.endif
            CALL ParserExpectLine
.if CompilerDiagnosticReturns
            RET  C
.endif
            LD   A,1
            LD   (ForwardOrdinal),A
            CALL ParserExpectSub
.if CompilerDiagnosticReturns
            RET  C
.endif
            CALL ParserExpectRoutineHeader
.if CompilerDiagnosticReturns
            RET  C
.endif
            LD   E,TokenVar
            CALL ParserExpect
.if CompilerDiagnosticReturns
            RET  C
.endif
            CALL ParserExpectResult
.if CompilerDiagnosticReturns
            RET  C
.endif
            CALL ParserExpectAsU8
.if CompilerDiagnosticReturns
            RET  C
.endif
            CALL ParserExpectEqual
.if CompilerDiagnosticReturns
            RET  C
.endif
            LD   D,DiagnosticForwardMismatch
            CALL ParserExpectForwardName
.if CompilerDiagnosticReturns
            RET  C
.endif
            CALL ParserExpectLeft
.if CompilerDiagnosticReturns
            RET  C
.endif
            LD   A,SemanticCallLiteralU8
            CALL SemanticSinkOperation
.if CompilerDiagnosticReturns
            RET  C
.endif
            LD   A,(ForwardOrdinal)
            CALL SemanticSinkPut
.if CompilerDiagnosticReturns
            RET  C
.endif
            CALL ParserExpectNumber
.if CompilerDiagnosticReturns
            RET  C
.endif
            CALL SemanticSinkPut
.if CompilerDiagnosticReturns
            RET  C
.endif
            CALL ParserExpectRight
.if CompilerDiagnosticReturns
            RET  C
.endif
            CALL ParserExpectLine
.if CompilerDiagnosticReturns
            RET  C
.endif

            CALL ParserExpectWrite
.if CompilerDiagnosticReturns
            RET  C
.endif
            CALL ParserExpectLeft
.if CompilerDiagnosticReturns
            RET  C
.endif
            CALL ParserExpectResult
.if CompilerDiagnosticReturns
            RET  C
.endif
            CALL ParserExpectRight
.if CompilerDiagnosticReturns
            RET  C
.endif
            LD   A,SemanticWriteLocalU8
            CALL SemanticSinkOperation
.if CompilerDiagnosticReturns
            RET  C
.endif
            CALL ParserExpectElseFailLine
.if CompilerDiagnosticReturns
            RET  C
.endif
            CALL ParserExpectEndLine
.if CompilerDiagnosticReturns
            RET  C
.endif
            LD   A,SemanticEndRoutine
            CALL SemanticSinkOperation
.if CompilerDiagnosticReturns
            RET  C
.endif

            CALL ParserExpectSub
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
            LD   A,1
            LD   (ForwardCompleted),A
            LD   A,SemanticBeginForwardU8
            CALL SemanticSinkOperation
.if CompilerDiagnosticReturns
            RET  C
.endif
            LD   A,(ForwardOrdinal)
            CALL SemanticSinkPut
.if CompilerDiagnosticReturns
            RET  C
.endif

            LD   E,TokenIf
            CALL ParserExpect
.if CompilerDiagnosticReturns
            RET  C
.endif
            LD   D,DiagnosticExpectedValue
            CALL ParserExpectForwardParameter
.if CompilerDiagnosticReturns
            RET  C
.endif
            CALL ParserExpectEqual
.if CompilerDiagnosticReturns
            RET  C
.endif
            LD   A,SemanticIfParameterZero
            CALL SemanticSinkOperation
.if CompilerDiagnosticReturns
            RET  C
.endif
            CALL ParserExpectNumber
.if CompilerDiagnosticReturns
            RET  C
.endif
            OR   A
            JP   NZ,ParserExpectedZero
            CALL SemanticSinkPut
.if CompilerDiagnosticReturns
            RET  C
.endif
            CALL ParserExpectLine
.if CompilerDiagnosticReturns
            RET  C
.endif

            LD   E,TokenReturn
            CALL ParserExpect
.if CompilerDiagnosticReturns
            RET  C
.endif
            LD   D,DiagnosticExpectedValue
            CALL ParserExpectForwardParameter
.if CompilerDiagnosticReturns
            RET  C
.endif
            CALL ParserExpectLine
.if CompilerDiagnosticReturns
            RET  C
.endif
            LD   A,SemanticReturnParameter
            CALL SemanticSinkOperation
.if CompilerDiagnosticReturns
            RET  C
.endif
            CALL ParserExpectEndLine
.if CompilerDiagnosticReturns
            RET  C
.endif
            LD   A,SemanticEndIf
            CALL SemanticSinkOperation
.if CompilerDiagnosticReturns
            RET  C
.endif

            LD   E,TokenReturn
            CALL ParserExpect
.if CompilerDiagnosticReturns
            RET  C
.endif
            LD   D,DiagnosticForwardMismatch
            CALL ParserExpectForwardName
.if CompilerDiagnosticReturns
            RET  C
.endif
            CALL ParserExpectLeft
.if CompilerDiagnosticReturns
            RET  C
.endif
            LD   D,DiagnosticExpectedValue
            CALL ParserExpectForwardParameter
.if CompilerDiagnosticReturns
            RET  C
.endif
            LD   E,TokenMinus
            CALL ParserExpect
.if CompilerDiagnosticReturns
            RET  C
.endif
            LD   A,SemanticReturnSelfMinus
            CALL SemanticSinkOperation
.if CompilerDiagnosticReturns
            RET  C
.endif
            LD   A,(ForwardOrdinal)
            CALL SemanticSinkPut
.if CompilerDiagnosticReturns
            RET  C
.endif
            CALL ParserExpectNumber
.if CompilerDiagnosticReturns
            RET  C
.endif
            CALL SemanticSinkPut
.if CompilerDiagnosticReturns
            RET  C
.endif
            CALL ParserExpectRight
.if CompilerDiagnosticReturns
            RET  C
.endif
            CALL ParserExpectLine
.if CompilerDiagnosticReturns
            RET  C
.endif
            CALL ParserExpectEndLine
.if CompilerDiagnosticReturns
            RET  C
.endif
            LD   A,SemanticEndRoutine
            CALL SemanticSinkOperation
.if CompilerDiagnosticReturns
            RET  C
.endif
            LD   A,(ForwardCompleted)
            OR   A
            JR   Z,ParserForwardIncomplete
            LD   E,TokenEof
            JP   ParserExpect
ParserExpectedZero:
            CALL SetDiagInline
            .db  DiagnosticExpectedNumber
ParserForwardIncomplete:
            CALL SetDiagInline
            .db  DiagnosticForwardIncomplete
.endif

.if HybridLL1Full
.else
.routine out A,carry,zero clobbers sign,parity,halfCarry,B,C,D,DE,HL,IX,IY
ParserParseProgram:
            CALL ParserTake
.if CompilerDiagnosticReturns
            RET  C
.endif
            CP   TokenSub
            JP   Z,TypedParseMainAfterTake
            CP   TokenVar
            JP   Z,ParserParseProgramAfterVar
            CP   TokenForward
            JP   Z,TypedParseForwardAfterTake
            CP   TokenConst
            JP   Z,TypedParseTopLevelConstAfterTake
            CP   TokenRecord
            JP   Z,AggregateParseRecordAfterTake
            CALL SetDiagInline
            .db  DiagnosticExpectedTopLevel
.endif

; A is the stable source-part identity; HL..DE is the half-open byte range.
.if LegacyCompilerSlices
.routine in A,DE,HL out A,carry,zero clobbers sign,parity,halfCarry,BC,DE,HL,IX,IY
CompileLoopSlice:
            CALL CompileSliceInitialize
            CALL ParserTake
.if CompilerDiagnosticReturns
            RET  C
.endif
            CP   TokenSub
            JP   NZ,ParserScalarExpectedTopLevel
            CALL ParserParseLoopProgramAfterSub
.if CompilerDiagnosticReturns
            RET  C
.endif
            JP   SemanticSinkFinish
.routine in A,DE,HL out A,carry,zero clobbers sign,parity,halfCarry,BC,DE,HL,IX,IY
CompileCallSlice:
            CALL CompileSliceInitialize
            CALL ParserTake
.if CompilerDiagnosticReturns
            RET  C
.endif
            CP   TokenForward
            JP   NZ,ParserScalarExpectedTopLevel
            CALL ParserParseCallProgramAfterForward
.if CompilerDiagnosticReturns
            RET  C
.endif
            JP   SemanticSinkFinish
.endif
.if AggregateCallSlices
.else
            .routine in A,DE,HL out A,carry,zero clobbers sign,parity,halfCarry,BC,DE,HL,IX,IY
CompileSlice:
            CALL CompileSliceInitialize
.if HybridLL1Full
            XOR  A
            LD   (Stage7CurrentRoutine),A
            CALL HybridLL1Parse
.else
            CALL ParserParseProgram
.endif
.if CompilerDiagnosticReturns
            RET  C
.endif
            JP   SemanticSinkFinish
.endif
.routine in A,DE,HL out A,carry,zero clobbers sign,parity,halfCarry,BC,DE,HL,IX,IY
CompileSliceInitialize:
.if AggregateCallSlices
            PUSH AF
            XOR  A
            LD   (SourcePartsRemaining),A
            POP  AF
.endif
            CALL SourceInitialize
.routine out A,carry,zero clobbers sign,parity,halfCarry,BC,DE,HL,IX,IY
CompileSliceResetState:
            XOR  A
            LD   (DiagnosticCode),A
            LD   (DiagnosticPartId),A
.if AggregateCallSlices
            LD   HL,SemanticPayloadBase
            LD   (SinkCursor),HL
            LD   (SinkOperationCount),A
            LD   (SemanticBufferBase),A
.else
            CALL SemanticSinkReset
.endif
            LD   A,$FF
            LD   (ParserLookaheadKind),A
.if AggregateCallSlices
            XOR  A
            LD   (SymbolCount),A
            LD   (NextLocalSlot),A
            LD   (NextProgramSlot),A
.else
            CALL SymbolReset
.endif
            XOR  A
            LD   HL,AggregateMode
            LD   B,AggregateHasInitializer-AggregateMode+1
CompileSliceResetAggregateLoop:
            LD   (HL),A
            INC  HL
            DJNZ CompileSliceResetAggregateLoop
            LD   (StaticImageLength),A
            LD   (StaticImageLength+1),A
.if SegmentedOutput
            LD   (ReadOnlyImageLength),A
            LD   (ReadOnlyImageLength+1),A
.endif
.if AggregateCallSlices
            LD   (ProgramBssLength),A
            LD   (ProgramBssLength+1),A
.endif
            LD   (ForwardCompleted),A
            LD   (ForwardOrdinal),A
            RET

; The typed scalar increment is kept in a separate source unit while it is
; correctness-first and under review. The compression pass may fold shared
; tails back into this parser after the rules are stable.
            .include "typed-expression-parser.asm"
            .include "aggregate-parser.asm"
.if AggregateCallSlices
            .include "aggregate-call-parser.asm"
.endif
