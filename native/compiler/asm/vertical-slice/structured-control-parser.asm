; Bounded structured-control parser layered over typed scalar expressions.
; Parser frames live only during source checking. Z80 emission reuses their
; workspace after the complete semantic transcript has been published.

.if HybridLL1Full
.else
.routine out A,carry,zero clobbers sign,parity,halfCarry,HL
ControlReset:
            XOR  A
            LD   (ControlDepth),A
.if AggregateCallSlices
            RET
.else
            LD   (ControlNextLabel),A
            RET
.endif
.endif

.routine in A out A,DE,HL,carry,zero clobbers sign,parity,halfCarry
ControlFrameAddress:
            LD   L,A
            LD   H,0
            ADD  HL,HL
            LD   E,L
            LD   D,H
            ADD  HL,HL
            ADD  HL,HL
            ADD  HL,DE
            LD   DE,ControlFrameBase
            ADD  HL,DE
            OR   A
            RET

; A is ControlKind*. Return the new frame base in HL.
.routine in A out A,DE,HL,carry,zero clobbers sign,parity,halfCarry,B,C
ControlPushFrame:
            LD   B,A
            LD   A,(ControlDepth)
            CP   ControlFrameCapacity
            JR   NC,ControlCapacityFailure
            PUSH AF
            CALL ControlFrameAddress
            POP  AF
            INC  A
            LD   (ControlDepth),A
            LD   (HL),B
            INC  HL
            LD   B,ControlFrameSize-1
            XOR  A
ControlClearFrame:
            LD   (HL),A
            INC  HL
            DJNZ ControlClearFrame
            LD   A,(ControlDepth)
            DEC  A
            CALL ControlFrameAddress
            PUSH HL
            LD   DE,ControlFrameCounter
            ADD  HL,DE
            LD   (HL),ControlNoCounter
            POP  HL
            OR   A
            RET
ControlCapacityFailure:
            CALL SetDiagInline
            .db  DiagnosticControlCapacity

.routine out A,DE,HL,carry,zero clobbers sign,parity,halfCarry
ControlTopFrame:
            LD   A,(ControlDepth)
            OR   A
            JR   Z,ControlLoopFailure
            DEC  A
            JR   ControlFrameAddress

.routine in B out A,DE,HL,carry,zero clobbers sign,parity,halfCarry
ControlTopFrameField:
            CALL ControlTopFrame
.if CompilerDiagnosticReturns
            RET  C
.endif
            LD   E,B
            LD   D,0
            ADD  HL,DE
            OR   A
            RET

.routine out A,carry,zero clobbers sign,parity,halfCarry,HL
ControlPopFrame:
            LD   HL,ControlDepth
            LD   A,(HL)
            OR   A
            JR   Z,ControlLoopFailure
            DEC  (HL)
            XOR  A
            RET

.if HybridLL1Full
.routine out A,C,DE,HL,carry,zero clobbers sign,parity,halfCarry,B
ControlAllocateExit:
            LD   B,ControlFrameExit
.endif
.routine in B out A,C,DE,HL,carry,zero clobbers sign,parity,halfCarry
ControlAllocateInto:
            LD   A,(ControlNextLabel)
.if AggregateCallSlices
            CP   Stage7ControlLabelLimit
.else
            ; Ordinal 31 is the retained routine entry.
            CP   ControlRoutineLabel
.endif
            JR   NC,ControlLabelFailure
            LD   C,A
            INC  A
            LD   (ControlNextLabel),A
            CALL ControlTopFrameField
.if CompilerDiagnosticReturns
            RET  C
.endif
            LD   (HL),C
            RET

.if HybridLL1Full
.routine in B out A,C,DE,HL,carry,zero clobbers sign,parity,halfCarry,B
HybridLL1PushFlowFrameAndLabelA:
            CALL HybridLL1PushFlowFrame
.if CompilerDiagnosticReturns
            RET  C
.endif
.routine out A,C,DE,HL,carry,zero clobbers sign,parity,halfCarry,B
ControlAllocateLabelA:
            LD   B,ControlFrameLabelA
.if TargetStreamingOutput
            JR   ControlAllocateInto
.else
            JP   ControlAllocateInto
.endif
.endif

ControlLabelFailure:
            CALL SetDiagInline
            .db  DiagnosticControlLabelCapacity
ControlLoopFailure:
            CALL SetDiagInline
            .db  DiagnosticExpectedLoop

; Emit operation D followed by byte C.
.routine in C,D out A,carry,zero clobbers sign,parity,halfCarry,B,DE,HL
ControlEmitOperationByte:
            LD   A,D
            CALL SemanticSinkOperation
.if CompilerDiagnosticReturns
            RET  C
.endif
            LD   A,C
            JP   SemanticSinkPut

.routine in C out A,carry,zero clobbers sign,parity,halfCarry,B,D,DE,HL
ControlEmitLabel:
            LD   D,SemanticControlLabel
            JR   ControlEmitOperationByte
.routine in C out A,carry,zero clobbers sign,parity,halfCarry,B,D,DE,HL
ControlEmitBranchFalse:
            LD   D,SemanticBranchFalse
            JR   ControlEmitOperationByte
.routine in C out A,carry,zero clobbers sign,parity,halfCarry,B,D,DE,HL
ControlEmitJump:
            LD   D,SemanticJump
            JR   ControlEmitOperationByte

; Return the nearest enclosing while/for frame in HL.
.routine out A,DE,HL,carry,zero clobbers sign,parity,halfCarry,B,C
ControlFindLoop:
            LD   A,(ControlDepth)
            OR   A
            JR   Z,ControlLoopFailure
ControlFindLoopNext:
            DEC  A
            PUSH AF
            CALL ControlFrameAddress
            LD   A,(HL)
            CP   ControlKindWhile
            JR   Z,ControlFindLoopFound
            CP   ControlKindFor
            JR   Z,ControlFindLoopFound
            POP  AF
            OR   A
            JR   NZ,ControlFindLoopNext
            JR   ControlLoopFailure
ControlFindLoopFound:
            POP  AF
            OR   A
            RET

; C is a local byte offset. Reject a source write or nested counter reuse while
; that exact local is the counter of any active counted loop.
.routine in C out A,carry,zero clobbers sign,parity,halfCarry,B,D,DE,HL
ControlCheckActiveCounter:
            LD   A,(ControlDepth)
            OR   A
            RET  Z
ControlCheckCounterNext:
            DEC  A
            PUSH AF
            CALL ControlFrameAddress
            LD   A,(HL)
            CP   ControlKindFor
            JR   NZ,ControlCheckCounterContinue
            LD   DE,ControlFrameCounter
            ADD  HL,DE
            LD   A,(HL)
            CP   C
            JR   Z,ControlActiveCounterFailure
ControlCheckCounterContinue:
            POP  AF
            OR   A
            JR   NZ,ControlCheckCounterNext
            RET
ControlActiveCounterFailure:
            POP  AF
            CALL SetDiagInline
            .db  DiagnosticActiveCounter

.if HybridLL1Full
.else
.routine out A,BC,DE,HL,carry,zero clobbers sign,parity,halfCarry,IX,IY
StructuredParseBooleanHeader:
            LD   A,ScalarTypeBoolean
            CALL TypedExpressionBeginRuntime
.if CompilerDiagnosticReturns
            RET  C
.endif
            LD   E,ScalarTypeBoolean
            CALL TypedCheckAssignable
.if CompilerDiagnosticReturns
            RET  C
.endif
            JP   ParserExpectLine

; Parse an if/elseif/else chain. TokenIf has already been consumed.
.routine out A,BC,DE,HL,carry,zero clobbers sign,parity,halfCarry,IX,IY
StructuredParseIf:
            LD   A,ControlKindIf
            CALL ControlPushFrame
.if CompilerDiagnosticReturns
            RET  C
.endif
            LD   B,ControlFrameExit
            CALL ControlAllocateInto
.if CompilerDiagnosticReturns
            RET  C
.endif
            LD   B,ControlFrameLabelA
            CALL ControlAllocateInto
.if CompilerDiagnosticReturns
            RET  C
.endif
            LD   DE,ControlFrameCounter-1
            ADD  HL,DE
            LD   (HL),1
StructuredParseIfCondition:
            CALL StructuredParseBooleanHeader
.if CompilerDiagnosticReturns
            RET  C
.endif
            CALL ControlTopFrame
            INC  HL
            LD   C,(HL)
            CALL ControlEmitBranchFalse
.if CompilerDiagnosticReturns
            RET  C
.endif
            CALL TypedParseStatements
.if CompilerDiagnosticReturns
            RET  C
.endif
            CALL StructuredRecordIfClause
.if CompilerDiagnosticReturns
            RET  C
.endif
            CALL ParserPeek
.if CompilerDiagnosticReturns
            RET  C
.endif
            CP   TokenElseIf
            JR   Z,StructuredParseElseIf
            CP   TokenElse
            JR   Z,StructuredParseElse
            CP   TokenEnd
            JP   NZ,ParserExpectedScalar
            CALL ControlTopFrame
            INC  HL
            LD   C,(HL)
            CALL ControlEmitLabel
.if CompilerDiagnosticReturns
            RET  C
.endif
            JR   StructuredParseIfEnd
StructuredParseElseIf:
            CALL StructuredEmitFrameExitAndLabel
.if CompilerDiagnosticReturns
            RET  C
.endif
            LD   B,ControlFrameLabelA
            CALL ControlAllocateInto
.if CompilerDiagnosticReturns
            RET  C
.endif
            CALL ParserTake
.if CompilerDiagnosticReturns
            RET  C
.endif
            JR   StructuredParseIfCondition
StructuredParseElse:
            CALL StructuredEmitFrameExitAndLabel
.if CompilerDiagnosticReturns
            RET  C
.endif
            CALL ParserTake
.if CompilerDiagnosticReturns
            RET  C
.endif
            CALL ParserExpectLine
.if CompilerDiagnosticReturns
            RET  C
.endif
            CALL TypedParseStatements
.if CompilerDiagnosticReturns
            RET  C
.endif
            CALL StructuredRecordIfClause
.if CompilerDiagnosticReturns
            RET  C
.endif
            LD   B,ControlFrameMode
            CALL ControlTopFrameField
            LD   (HL),1
            CALL ParserPeek
.if CompilerDiagnosticReturns
            RET  C
.endif
            CP   TokenEnd
            JP   NZ,ParserExpectedScalar
StructuredParseIfEnd:
            CALL ParserTake
.if CompilerDiagnosticReturns
            RET  C
.endif
            CALL ParserExpectLine
.if CompilerDiagnosticReturns
            RET  C
.endif
            LD   B,ControlFrameExit
            CALL ControlTopFrameField
            LD   C,(HL)
            CALL ControlEmitLabel
.if CompilerDiagnosticReturns
            RET  C
.endif
            LD   B,ControlFrameCounter
            CALL ControlTopFrameField
            PUSH HL
            LD   A,(HL)
            POP  HL
            LD   DE,ControlFrameMode-ControlFrameCounter
            ADD  HL,DE
            AND  (HL)
            XOR  1
            PUSH AF
            CALL ControlPopFrame
            POP  AF
            RET

.routine out A,C,DE,HL,carry,zero clobbers sign,parity,halfCarry,B
StructuredEmitFrameExitAndLabel:
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
.endif

.routine out A,DE,HL,carry,zero clobbers sign,parity,halfCarry,B
StructuredRecordIfClause:
            LD   A,(ControlSequenceFallsThrough)
            OR   A
            RET  Z
            LD   B,ControlFrameCounter
            CALL ControlTopFrameField
            LD   (HL),0
            XOR  A
            RET

; TokenWhile has already been consumed.
.if HybridLL1Full
.else
.routine out A,BC,DE,HL,carry,zero clobbers sign,parity,halfCarry,IX,IY
StructuredParseWhile:
            LD   A,ControlKindWhile
            CALL ControlPushFrame
.if CompilerDiagnosticReturns
            RET  C
.endif
            LD   B,ControlFrameLabelA
            CALL ControlAllocateInto
.if CompilerDiagnosticReturns
            RET  C
.endif
            INC  HL
            LD   (HL),C
            LD   B,ControlFrameExit
            CALL ControlAllocateInto
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
            CALL StructuredParseBooleanHeader
.if CompilerDiagnosticReturns
            RET  C
.endif
            LD   B,ControlFrameExit
            CALL ControlTopFrameField
            LD   C,(HL)
            CALL ControlEmitBranchFalse
.if CompilerDiagnosticReturns
            RET  C
.endif
            CALL TypedParseStatements
.if CompilerDiagnosticReturns
            RET  C
.endif
            CALL ParserPeek
.if CompilerDiagnosticReturns
            RET  C
.endif
            CP   TokenEnd
            JP   NZ,ParserExpectedScalar
            LD   B,ControlFrameContinue
            CALL ControlTopFrameField
            LD   C,(HL)
            CALL ControlEmitJump
.if CompilerDiagnosticReturns
            RET  C
.endif
            LD   B,ControlFrameExit
            CALL ControlTopFrameField
            LD   C,(HL)
            CALL ControlEmitLabel
.if CompilerDiagnosticReturns
            RET  C
.endif
StructuredCompleteLoop:
            CALL ParserTake
.if CompilerDiagnosticReturns
            RET  C
.endif
            CALL ParserExpectLine
.if CompilerDiagnosticReturns
            RET  C
.endif
            JP   ControlPopFrame

; Parse bare exit/continue. The token has already been consumed.
.routine in A out A,BC,DE,HL,carry,zero clobbers sign,parity,halfCarry,IX,IY
StructuredParseLoopTransfer:
            LD   (DeclarationInfo),A
            CALL ControlFindLoop
.if CompilerDiagnosticReturns
            RET  C
.endif
            LD   DE,ControlFrameExit
            LD   A,(DeclarationInfo)
            CP   TokenExit
            JR   Z,StructuredLoopTransferSelected
            LD   DE,ControlFrameContinue
StructuredLoopTransferSelected:
            ADD  HL,DE
            LD   C,(HL)
            CALL ControlEmitJump
.if CompilerDiagnosticReturns
            RET  C
.endif
            JP   ParserExpectLine
.endif

; Parse one compile-time step constant. B returns mode bit 1 and DE magnitude.
.routine out A,B,DE,carry,zero clobbers sign,parity,halfCarry,C,HL
StructuredParseStep:
            XOR  A
            LD   (ExpressionLeftMeta),A
            CALL ParserPeek
.if CompilerDiagnosticReturns
            RET  C
.endif
            CP   TokenPlus
            JR   Z,StructuredStepPositive
            CP   TokenMinus
            JR   NZ,StructuredStepMagnitude
            LD   A,2
            LD   (ExpressionLeftMeta),A
StructuredStepPositive:
            CALL ParserTake
.if CompilerDiagnosticReturns
            RET  C
.endif
StructuredStepMagnitude:
            CALL ParserTake
.if CompilerDiagnosticReturns
            RET  C
.endif
            CP   TokenNumber
            JR   Z,StructuredStepNumber
            CP   TokenName
            JR   NZ,StructuredStepFailure
.if AggregateCallSlices
            CALL Stage8MatchPredefinedCurrent
            JR   NC,StructuredStepSourceConstant
            CP   Stage8PredefinedConstantBase
            JR   C,StructuredStepFailure
            SUB  Stage8PredefinedConstantBase-1
            LD   D,0
            LD   E,A
            JR   StructuredStepHaveMagnitude
StructuredStepSourceConstant:
.endif
            CALL SymbolLookupCurrent
.if CompilerDiagnosticReturns
            RET  C
.endif
            LD   D,A
            AND  SymbolRecordTypeFlag+SymbolAggregateFlag
            JR   NZ,StructuredStepFailure
            LD   A,D
            AND  SymbolClassMask
            JR   NZ,StructuredStepFailure
            LD   A,D
            AND  ScalarMetaTypeMask
            CP   ScalarTypeBoolean
            JR   Z,StructuredStepFailure
StructuredStepNumber:
            LD   D,B
            LD   E,C
StructuredStepHaveMagnitude:
            LD   A,D
            OR   E
            JR   Z,StructuredStepFailure
            LD   A,(ExpressionLeftMeta)
            LD   B,A
            OR   A
            RET
StructuredStepFailure:
            CALL SetDiagInline
            .db  DiagnosticLoopStep

; TokenFor has already been consumed.
.if HybridLL1Full
.else
.routine out A,BC,DE,HL,carry,zero clobbers sign,parity,halfCarry,IX,IY
StructuredParseFor:
            LD   E,TokenName
            CALL ParserExpect
.if CompilerDiagnosticReturns
            RET  C
.endif
            LD   HL,(TokenStartOffset)
            LD   (ExpressionCallOffset),HL
            CALL SymbolLookupCurrent
.if CompilerDiagnosticReturns
            RET  C
.endif
            LD   (DeclarationInfo),A
            LD   (DeclarationPayload),BC
            LD   D,A
            AND  SymbolClassMask
            CP   SymbolClassLocal
            JP   NZ,StructuredCounterFailure
            LD   A,D
            AND  ScalarMetaTypeMask
            CP   ScalarTypeBoolean
            JP   Z,StructuredCounterFailure
            CALL ControlCheckActiveCounter
.if CompilerDiagnosticReturns
            RET  C
.endif
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
            CALL ParserTake
.if CompilerDiagnosticReturns
            RET  C
.endif
            CP   TokenTo
            LD   B,1
            JR   Z,StructuredForBound
            CP   TokenUntil
            JP   NZ,StructuredCounterFailure
            LD   B,0
StructuredForBound:
            PUSH BC
            LD   A,ScalarTypeU16
            CALL TypedExpressionBeginRuntime
            POP  BC
.if CompilerDiagnosticReturns
            RET  C
.endif
            PUSH BC
            LD   E,ScalarTypeU16
            CALL TypedCheckAssignable
            POP  BC
.if CompilerDiagnosticReturns
            RET  C
.endif
            LD   DE,1
            PUSH BC
            PUSH DE
            CALL ParserPeek
            POP  DE
            POP  BC
.if CompilerDiagnosticReturns
            RET  C
.endif
            CP   TokenStep
            JR   NZ,StructuredForStepReady
            PUSH BC
            CALL ParserTake
            POP  BC
.if CompilerDiagnosticReturns
            RET  C
.endif
            PUSH BC
            CALL StructuredParseStep
            LD   A,B
            POP  BC
.if CompilerDiagnosticReturns
            RET  C
.endif
            OR   B
            LD   B,A
StructuredForStepReady:
            PUSH BC
            PUSH DE
            CALL ParserExpectLine
            POP  DE
            POP  BC
.if CompilerDiagnosticReturns
            RET  C
.endif
            PUSH BC
            PUSH DE
            LD   A,ControlKindFor
            CALL ControlPushFrame
            POP  DE
            POP  BC
.if CompilerDiagnosticReturns
            RET  C
.endif
            PUSH BC
            PUSH DE
            LD   B,ControlFrameLabelA
            CALL ControlAllocateInto
            POP  DE
            POP  BC
.if CompilerDiagnosticReturns
            RET  C
.endif
            PUSH BC
            PUSH DE
            LD   B,ControlFrameContinue
            CALL ControlAllocateInto
            POP  DE
            POP  BC
.if CompilerDiagnosticReturns
            RET  C
.endif
            PUSH BC
            PUSH DE
            LD   B,ControlFrameExit
            CALL ControlAllocateInto
            POP  DE
            POP  BC
.if CompilerDiagnosticReturns
            RET  C
.endif
            PUSH DE
            CALL ControlTopFrame
            POP  DE
            PUSH HL
            INC  HL
            INC  HL
            INC  HL
            INC  HL
            LD   A,(DeclarationPayload)
            LD   (HL),A
            INC  HL
            LD   A,(DeclarationInfo)
            AND  ScalarMetaTypeMask
            CP   ScalarTypeU16
            LD   A,B
            JR   NZ,StructuredForModeReady
            SET  2,A
StructuredForModeReady:
            LD   (HL),A
            INC  HL
            LD   (HL),E
            INC  HL
            LD   (HL),D
            INC  HL
            LD   DE,(ExpressionCallOffset)
            LD   (HL),E
            INC  HL
            LD   (HL),D
            POP  HL
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
.if CompilerDiagnosticReturns
            RET  C
.endif
            CALL TypedParseStatements
.if CompilerDiagnosticReturns
            RET  C
.endif
            CALL ParserPeek
.if CompilerDiagnosticReturns
            RET  C
.endif
            CP   TokenEnd
            JP   NZ,ParserExpectedScalar
            LD   B,ControlFrameContinue
            CALL ControlTopFrameField
            LD   C,(HL)
            CALL ControlEmitLabel
.if CompilerDiagnosticReturns
            RET  C
.endif
            CALL StructuredEmitForNext
.if CompilerDiagnosticReturns
            RET  C
.endif
            LD   B,ControlFrameExit
            CALL ControlTopFrameField
            LD   C,(HL)
            CALL ControlEmitLabel
.if CompilerDiagnosticReturns
            RET  C
.endif
            LD   A,SemanticForCleanup
            CALL SemanticSinkOperation
.if CompilerDiagnosticReturns
            RET  C
.endif
            JP   StructuredCompleteLoop
.endif
StructuredCounterFailure:
            CALL SetDiagInline
            .db  DiagnosticLoopCounter

; Emit the fixed-width counted-loop records from the current frame.
.routine in A,HL out A,BC,DE,HL,carry,zero clobbers sign,parity,halfCarry,IX,IY
StructuredEmitForPrefix:
            PUSH HL
            CALL SemanticSinkOperation
            POP  HL
.if CompilerDiagnosticReturns
            RET  C
.endif
            LD   DE,ControlFrameCounter
            ADD  HL,DE
            LD   A,(HL)
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
            INC  HL
            RET

.routine in HL out A,BC,DE,HL,carry,zero clobbers sign,parity,halfCarry,IX,IY
StructuredEmitForSetup:
            LD   A,SemanticForSetup
            CALL StructuredEmitForPrefix
.if CompilerDiagnosticReturns
            RET  C
.endif
            LD   A,(HL)
            JP   SemanticSinkPut

.routine out A,BC,DE,HL,carry,zero clobbers sign,parity,halfCarry,IX,IY
StructuredEmitForTest:
            CALL ControlTopFrame
            LD   A,SemanticForTest
            CALL StructuredEmitForPrefix
.if CompilerDiagnosticReturns
            RET  C
.endif
            LD   A,(HL)                  ; mode
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
            LD   B,ControlFrameExit
            CALL ControlTopFrameField
            LD   A,(HL)                  ; exit label
            JP   SemanticSinkPut
StructuredEmitFrameBytes:
            LD   A,(HL)
            PUSH BC
.if CompilerDiagnosticReturns
            PUSH HL
            CALL SemanticSinkPut
            POP  HL
.else
            CALL SemanticSinkPutPreserveHL
.endif
            POP  BC
.if CompilerDiagnosticReturns
            RET  C
.endif
            INC  HL
            DJNZ StructuredEmitFrameBytes
            RET

.routine out A,BC,DE,HL,carry,zero clobbers sign,parity,halfCarry,IX,IY
StructuredEmitForNext:
            CALL ControlTopFrame
            PUSH HL
            LD   A,SemanticForNext
            CALL SemanticSinkOperation
            POP  HL
.if CompilerDiagnosticReturns
            RET  C
.endif
            LD   DE,ControlFrameLabelA
            ADD  HL,DE
            LD   A,(HL)                  ; test label
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
            INC  HL                     ; continue label
            INC  HL                     ; exit label
            LD   A,(HL)
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
            INC  HL                     ; counter
            LD   B,6                    ; counter, mode, step, trap offset
            JR   StructuredEmitFrameBytes
