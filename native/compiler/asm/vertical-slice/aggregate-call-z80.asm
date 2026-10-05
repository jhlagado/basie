; Stage 7 direct-Z80 lowering for opaque aggregate carriers. Every source
; scalar and alias carrier occupies one canonical word on the evaluation
; stack; declared storage widths remain unchanged.

.routine out A,carry,zero clobbers sign,parity,halfCarry,B,C,D,DE,HL,IX
Stage7BeginRoutine:
            CALL NextSemanticByte
            LD   C,A
            CALL NextSemanticByte     ; retained parameter count
.if TargetStreamingOutput
            CALL NextSemanticByte     ; target bank
            PUSH BC
            CALL TargetSelectOutputBank
            POP  BC
.if CompilerDiagnosticReturns
            RET  C
.endif
.endif
Stage7DefineRoutineFrame:
            CALL StructuredDefineLabel
.if CompilerDiagnosticReturns
            RET  C
.endif
            LD   HL,ExpressionFrameBytes
            JP   EmitEight

; Operands are exact type, negative-frame byte offset, and positive caller
; displacement. The prologue copies one canonical argument into this
; activation before any body statement runs.
.routine out A,carry,zero clobbers sign,parity,halfCarry,B,C,D,DE,HL
Stage7BindParameter:
            CALL NextSemanticByte
            LD   (Stage7PathType),A
            CALL NextSemanticByte
            CPL
            LD   (Stage7PathOffset),A       ; -(destination + 1)
            CALL NextSemanticByte
            LD   (Stage7ArgumentIndex),A    ; positive source displacement
            LD   A,(Stage7PathType)
            CP   AggregateOpenStringTypeId
            JR   Z,Stage7BindOpenString
            CP   AggregateFirstDynamicTypeId
            JR   NC,Stage7BindWord
            CP   ScalarTypeU16
            JR   Z,Stage7BindWord
            CALL EmitByteInlineChecked
            .db  $3B                      ; DEC SP
.if CompilerDiagnosticReturns
            RET  C
.endif
            LD   HL,Stage7LoadIXL
            CALL Stage7EmitPairArgumentIndex
.if CompilerDiagnosticReturns
            RET  C
.endif
            LD   HL,Stage7StoreIXL
            JR   Stage7EmitPairPathOffset
Stage7BindOpenString:
            CALL EmitByteInlineChecked
            .db  $3B                      ; third activation byte
.if CompilerDiagnosticReturns
            RET  C
.endif
Stage7BindWord:
            CALL EmitPairIndexedInline
            .db  EmitPairDecSp2
.if CompilerDiagnosticReturns
            RET  C
.endif
            LD   HL,Stage7LoadIXL
            CALL Stage7EmitPairArgumentIndex
.if CompilerDiagnosticReturns
            RET  C
.endif
            CALL EmitPairIndexedInline
            .db  EmitPairLoadIXH
.if CompilerDiagnosticReturns
            RET  C
.endif
            LD   A,(Stage7ArgumentIndex)
            INC  A
            CALL EmitByte
.if CompilerDiagnosticReturns
            RET  C
.endif
            LD   HL,Stage7StoreIXL
            CALL Stage7EmitPairPathOffset
.if CompilerDiagnosticReturns
            RET  C
.endif
            CALL EmitPairIndexedInline
            .db  EmitPairStoreIXH
.if CompilerDiagnosticReturns
            RET  C
.endif
            LD   A,(Stage7PathOffset)
            DEC  A
            CALL EmitByte
.if CompilerDiagnosticReturns
            RET  C
.endif
            LD   A,(Stage7PathType)
            CP   AggregateOpenStringTypeId
            JR   Z,Stage7BindOpenCapacity
            OR   A
            RET
Stage7BindOpenCapacity:
            CALL EmitPairIndexedInline
            .db  EmitPairLoadIXL
.if CompilerDiagnosticReturns
            RET  C
.endif
            LD   A,(Stage7ArgumentIndex)
            INC  A
            INC  A
            CALL EmitByte
.if CompilerDiagnosticReturns
            RET  C
.endif
            CALL EmitPairIndexedInline
            .db  EmitPairStoreIXL
.if CompilerDiagnosticReturns
            RET  C
.endif
            LD   A,(Stage7PathOffset)
            DEC  A
            DEC  A
            JP   EmitByte

.routine in HL out A,carry,zero clobbers sign,parity,halfCarry,B,C,DE,HL
Stage7EmitPairArgumentIndex:
            CALL EmitPair
.if CompilerDiagnosticReturns
            RET  C
.endif
            LD   A,(Stage7ArgumentIndex)
            JP   EmitByte

.routine in HL out A,carry,zero clobbers sign,parity,halfCarry,B,C,DE,HL
Stage7EmitPairPathOffset:
            CALL EmitPair
.if CompilerDiagnosticReturns
            RET  C
.endif
            LD   A,(Stage7PathOffset)
            JP   EmitByte

; Emit a bounds trap after a target helper has returned carry. The branch
; around the trap is patched before normal lowering continues.
.routine out A,carry,zero clobbers sign,parity,halfCarry,B,C,D,DE,HL
Stage7BoundsGuard:
            CALL EmitJrNcPlaceholder
.if CompilerDiagnosticReturns
            RET  C
.endif
            LD   (EmitFailureFixup),DE
            LD   HL,(Stage7CallOffset)
            LD   A,1
            CALL TypedEmitTrapBody
.if CompilerDiagnosticReturns
            RET  C
.endif
            LD   DE,(EmitFailureFixup)
            JP   PatchHere

.routine out A,DE,HL,carry,zero clobbers sign,parity,halfCarry
Stage7ReadCallOffset:
            CALL ReadSemanticWord
            LD   (Stage7CallOffset),DE
            RET

.routine out A,carry,zero clobbers sign,parity,halfCarry,B,DE,HL
Stage8ReadCallState:
            LD   DE,Stage8EmitCallMode
            LD   B,3
Stage8ReadCallStateLoop:
            CALL NextSemanticByte          ; mode, handler, retained carriers
            LD   (DE),A
            INC  DE
            DJNZ Stage8ReadCallStateLoop
            RET

; Retain the source position of a propagated failure. The root wrapper uses
; the last propagation site when failure finally leaves callable main.
.routine out A,carry,zero clobbers sign,parity,halfCarry,B,C,DE,HL
Stage8EmitFailureOffset:
            LD   HL,(Stage7CallOffset)
            CALL EmitLoadHl
.if CompilerDiagnosticReturns
            RET  C
.endif
.if TargetStreamingOutput
            LD   DE,TrapOffset-StateBase
            CALL TargetStateAddress
.else
            LD   HL,TrapOffset
.endif
            LD   A,$22                    ; LD (nn),HL
            JP   EmitOpcodeWord

.routine out A,carry,zero clobbers sign,parity,halfCarry,B,C,D,DE,HL,IX,IY
Stage7Call:
            CALL NextSemanticByte
            LD   (Stage7CallLabel),A
            AND  Stage8CallableServiceFlag
            JR   NZ,Stage8ReadServiceCall
            CALL NextSemanticByte
            LD   (Stage7ArgumentCount),A
            CALL NextSemanticByte
            LD   (Stage7CallResultType),A
            CALL NextSemanticByte
            LD   (Stage8EmitCallFlags),A
            JR   Stage8ReadCallCommon
Stage8ReadServiceCall:
            LD   A,(Stage7CallLabel)
            AND  Stage8ServiceResultU8
            RLCA
            RLCA
            RLCA
            LD   (Stage7CallResultType),A
Stage8ReadCallCommon:
            CALL Stage7ReadCallOffset
            CALL Stage8ReadCallState
            LD   A,(Stage7CallLabel)
            AND  Stage8CallableServiceFlag
            JP   NZ,Stage8InvokeService
.if TargetStreamingOutput
            LD   DE,NucleusRuntimeActivationClaimOffset
            CALL TypedEmitFailableRuntimeCall
.else
            LD   HL,ActivationClaim
            CALL TypedEmitFailableCall
.endif
.if CompilerDiagnosticReturns
            RET  C
.endif
            LD   (EmitExitFixup),DE
            LD   HL,(Stage7CallOffset)
            LD   A,5
            CALL TypedEmitTrapBody
.if CompilerDiagnosticReturns
            RET  C
.endif
            LD   DE,(EmitExitFixup)
            CALL PatchHere
.if CompilerDiagnosticReturns
            RET  C
.endif
            LD   A,(Stage7CallLabel)
            AND  Stage8CallableSourceMask
            LD   C,A
.if TargetStreamingOutput
            CALL Stage7EmitSourceCall
.else
            LD   A,$CD
            CALL StructuredEmitFixup
.endif
.if CompilerDiagnosticReturns
            RET  C
.endif
            LD   A,(Stage8EmitCallFlags)
            AND  Stage7RoutineFails
            JR   NZ,Stage8CallableSourceFailable
.if TargetStreamingOutput
            LD   DE,NucleusRuntimeActivationReleaseOffset
            CALL EmitRuntimeCall
.else
            LD   HL,ActivationRelease
            CALL EmitCall
.endif
.if CompilerDiagnosticReturns
            RET  C
.endif
            JR   Stage8CallableSuccess

.if TargetStreamingOutput
; Emit an ordinary local CALL when the target routine shares the current bank.
; A cross-bank call supplies destination bank A and address HL to vector 9;
; the adapter switches, calls, restores the caller bank, and preserves the
; ordinary source-routine result/failure ABI.
.routine in C out A,carry,zero clobbers sign,parity,halfCarry,B,C,D,DE,HL,IX,IY
Stage7EmitSourceCall:
            LD   A,(Stage8EmitCallFlags)
            CALL TargetUnpackBank
            LD   D,A
            LD   A,(TargetOutputBank)
            CP   D
            JR   NZ,Stage7EmitFarSourceCall
            LD   A,$CD
            JP   StructuredEmitFixup
Stage7EmitFarSourceCall:
            PUSH BC
            PUSH DE
            LD   C,D
            LD   A,$3E                    ; LD A,destination bank
            CALL EmitOpcodeByte
            POP  DE
            POP  BC
.if CompilerDiagnosticReturns
            RET  C
.endif
            LD   A,$21                    ; LD HL,target address
            CALL StructuredEmitFarFixup
.if CompilerDiagnosticReturns
            RET  C
.endif
            LD   A,9                      ; far-call vector ordinal
            JP   EmitTargetVectorCall
.endif
Stage8CallableSourceFailable:
            CALL EmitByteInlineChecked
            .db  $F5                    ; PUSH AF result discriminant/code
.if CompilerDiagnosticReturns
            RET  C
.endif
.if TargetStreamingOutput
            LD   DE,NucleusRuntimeActivationReleaseOffset
            CALL EmitRuntimeCall
.else
            LD   HL,ActivationRelease
            CALL EmitCall
.endif
.if CompilerDiagnosticReturns
            RET  C
.endif
            CALL EmitByteInlineChecked
            .db  $F1                    ; POP AF
.if CompilerDiagnosticReturns
            RET  C
.endif
Stage8CallableFailable:
            CALL EmitJrNcPlaceholder
.if CompilerDiagnosticReturns
            RET  C
.endif
            LD   (EmitExitFixup),DE
            CALL Stage8EmitFailureOutcome
.if CompilerDiagnosticReturns
            RET  C
.endif
Stage8CallableFailureReady:
            LD   DE,(EmitExitFixup)
            CALL PatchHere
.if CompilerDiagnosticReturns
            RET  C
.endif
Stage8CallableSuccess:
            LD   A,(Stage7ArgumentCount)
            LD   C,A
            CALL Stage8DiscardCarriers
.if CompilerDiagnosticReturns
            RET  C
.endif
            LD   A,(Stage7CallResultType)
            OR   A
            RET  Z
            LD   A,(Stage7CallLabel)
            AND  Stage8CallableKeepFlag
            RET  Z
            LD   A,(Stage7CallLabel)
            AND  Stage8CallableServiceFlag
            JR   NZ,Stage8CallableServiceResult
            CALL EmitByteInline
            .db  $E5                      ; PUSH HL result carrier
Stage8CallableServiceResult:
            LD   HL,Stage8ErrorCarrierBytes
            JP   EmitFour

.routine in C out A,C,carry,zero clobbers sign,parity,halfCarry,B,D,DE,HL
Stage8DiscardCarriers:
            LD   A,C
            OR   A
            RET  Z
Stage8DiscardCarrier:
            CALL EmitByteInlineChecked
            .db  $D1                    ; POP DE carrier
.if CompilerDiagnosticReturns
            RET  C
.endif
            DEC  C
            JR   Stage8DiscardCarriers

Stage7ReturnAggregate .equ TypedReturnScalar

; Failable completion uses carry plus A privately: carry clear denotes success;
; carry set carries one u8 error code in A. Source code cannot inspect this ABI.
.routine out A,carry,zero clobbers sign,parity,halfCarry,B,C,D,DE,HL,IX,IY
Stage8FailRoutine:
            CALL Stage7ReadCallOffset
            CALL Stage8EmitFailureOffset
.if CompilerDiagnosticReturns
            RET  C
.endif
            CALL EmitPairIndexedInline
            .db  EmitPairPopHLToA
.if CompilerDiagnosticReturns
            RET  C
.endif
            JR   Stage8FailureReturnTail

.routine out A,carry,zero clobbers sign,parity,halfCarry,B,C,D,DE,HL
Stage8FailMain:
            CALL Stage7ReadCallOffset
            CALL EmitPairIndexedInline
            .db  EmitPairPopHLToA
.if CompilerDiagnosticReturns
            RET  C
.endif
            LD   HL,(Stage7CallOffset)
            CALL EmitLoadHl
.if CompilerDiagnosticReturns
            RET  C
.endif
            CALL EmitUnhandledTrapPrefix
.if CompilerDiagnosticReturns
            RET  C
.endif
            JP   TypedEmitTrapEnding

.routine out A,carry,zero clobbers sign,parity,halfCarry,B,C,D,DE,HL,IX,IY
Stage8ReturnSuccess:
            CALL TypedEmitPopHL           ; result carrier
.if CompilerDiagnosticReturns
            RET  C
.endif
            JR   Stage8SuccessTail

.routine out A,carry,zero clobbers sign,parity,halfCarry,B,C,D,DE,HL
Stage8EndFailableRoutine:
            CALL NextSemanticByte
            OR   A
            RET  NZ
Stage8SuccessTail:
            CALL ExpressionRestoreFrame
.if CompilerDiagnosticReturns
            RET  C
.endif
            LD   HL,Stage8SuccessReturnBytes
            JP   EmitPair

.routine out A,carry,zero clobbers sign,parity,halfCarry,B,C,D,DE,HL
Stage8SkipHandler:
            CALL NextSemanticByte
            LD   C,A
            LD   A,$C3
            JP   StructuredEmitFixup

.routine out A,carry,zero clobbers sign,parity,halfCarry,B,C,D,DE,HL,IX,IY
Stage8BeginHandler:
            CALL NextSemanticByte
            LD   C,A
            CALL StructuredDefineLabel
.if CompilerDiagnosticReturns
            RET  C
.endif
            CALL NextSemanticByte
            LD   (Stage8EmitCallFlags),A
            LD   HL,Stage8ErrorCarrierBytes
            CALL EmitFour
.if CompilerDiagnosticReturns
            RET  C
.endif
            LD   A,(Stage8EmitCallFlags)
            AND  SymbolClassMask
            CP   SymbolClassProgram
            JP   Z,TypedStoreProgram8
            JP   TypedStoreLocal8

.routine out A,carry,zero clobbers sign,parity,halfCarry,B,C,D,DE,HL
Stage8EndHandler:
            CALL NextSemanticByte
            LD   C,A
            JP   StructuredDefineLabel

.routine out A,carry,zero clobbers sign,parity,halfCarry,B,C,D,DE,HL,IX,IY
Stage8EmitFailureOutcome:
            LD   A,(Stage8EmitCallMode)
            OR   A
            JP   Z,TypedInternalOperation
            CP   Stage8CallModeHandle
            JR   Z,Stage8FailureHandle
            CALL Stage8EmitFailureOffset
.if CompilerDiagnosticReturns
            RET  C
.endif
Stage8FailureReturnTail:
            CALL ExpressionRestoreFrame
.if CompilerDiagnosticReturns
            RET  C
.endif
            LD   HL,Stage8FailureReturnBytes
            JP   EmitPair
Stage8FailureHandle:
            CALL EmitByteInlineChecked
            .db  $4F                    ; LD C,A error code
.if CompilerDiagnosticReturns
            RET  C
.endif
            LD   A,(Stage7ArgumentCount)
            LD   HL,Stage8EmitRetainedCarriers
            ADD  A,(HL)
            LD   C,A
            CALL Stage8DiscardCarriers
.if CompilerDiagnosticReturns
            RET  C
.endif
            CALL EmitByteInlineChecked
            .db  $79                    ; LD A,C
.if CompilerDiagnosticReturns
            RET  C
.endif
            LD   A,(Stage8EmitHandlerLabel)
            LD   C,A
            LD   A,$C3
            JP   StructuredEmitFixup

.routine out A,carry,zero clobbers sign,parity,halfCarry,B,C,D,DE,HL,IX,IY
Stage8InvokeService:
            LD   A,(Stage7CallLabel)
            AND  Stage8ServiceArgumentMask
            JR   Z,Stage8ServiceAddress
            CP   Stage8ServiceArgumentU16
            JR   Z,Stage8ServiceWordArgument
            CALL EmitPairIndexedInline
            .db  EmitPairPopHLToA
.if CompilerDiagnosticReturns
            RET  C
.endif
            JR   Stage8ServiceAddress
Stage8ServiceWordArgument:
            CALL TypedEmitPopHL           ; offset
.if CompilerDiagnosticReturns
            RET  C
.endif
Stage8ServiceAddress:
            LD   A,(Stage7CallLabel)
            AND  Stage8CallableServiceMask
.if TargetStreamingOutput
            CALL EmitTargetVectorCall
.else
            ADD  A,A
            LD   E,A
            LD   D,0
            LD   HL,Stage8ServiceAddressTable
            ADD  HL,DE
            LD   E,(HL)
            INC  HL
            LD   D,(HL)
            EX   DE,HL
            CALL EmitCall
.endif
.if CompilerDiagnosticReturns
            RET  C
.endif
            XOR  A
Stage8NoArgumentFailable:
            LD   (Stage7ArgumentCount),A
            JP   Stage8CallableFailable

.if TargetStreamingOutput
.else
Stage8ServiceAddressTable:
            .dw ReadInputByte
            .dw WriteOutputByte
            .dw ReadStorageByte
            .dw RewindStorageInput
            .dw WriteStorageByte
            .dw SeekStorageOutput
.endif

; Startup is a terminal wrapper around main's ordinary callable body. The
; source body therefore has the same frame, return, recursion, and failure ABI
; as every other result-free routine; only this wrapper converts final failure
; into unhandled-error and final success into host completion.
.routine out A,carry,zero clobbers sign,parity,halfCarry,B,C,D,DE,HL,IX,IY
Stage8BeginCallableMain:
            CALL NextSemanticByte
            LD   (Stage8EmitCallFlags),A
.if TargetStreamingOutput
            CALL NextSemanticByte
            CALL TargetSelectOutputBank
.if CompilerDiagnosticReturns
            RET  C
.endif
.endif
            CALL TypedBeginProgramFrame
.if CompilerDiagnosticReturns
            RET  C
.endif
            LD   C,Stage7MainLabel
            LD   A,$CD
            CALL StructuredEmitFixup
.if CompilerDiagnosticReturns
            RET  C
.endif
            LD   A,(Stage8EmitCallFlags)
            AND  Stage7RoutineFails
            JR   Z,Stage8MainWrapperSuccess
            CALL EmitJrNcPlaceholder
.if CompilerDiagnosticReturns
            RET  C
.endif
            LD   (EmitExitFixup),DE
.if TargetStreamingOutput
            CALL EmitByteInlineChecked
            .db  $F5                    ; PUSH AF
.if CompilerDiagnosticReturns
            RET  C
.endif
            LD   DE,TrapOffset-StateBase
            CALL TargetStateAddress
            LD   A,$2A                    ; LD HL,(nn)
            CALL EmitOpcodeWord
.if CompilerDiagnosticReturns
            RET  C
.endif
            LD   A,$F1                    ; POP AF
            CALL EmitByte
.else
            LD   HL,Stage8ReloadFailureOffsetBytes
            CALL EmitFive
.endif
.if CompilerDiagnosticReturns
            RET  C
.endif
            CALL EmitUnhandledTrapPrefix
.if CompilerDiagnosticReturns
            RET  C
.endif
            CALL TypedEmitTrapEnding
.if CompilerDiagnosticReturns
            RET  C
.endif
            LD   DE,(EmitExitFixup)
            CALL PatchHere
.if CompilerDiagnosticReturns
            RET  C
.endif
Stage8MainWrapperSuccess:
            CALL TypedRestoreRootFrame
.if CompilerDiagnosticReturns
            RET  C
.endif
            CALL EmitSuccessReturn
.if CompilerDiagnosticReturns
            RET  C
.endif
            LD   C,Stage7MainLabel
            JP   Stage7DefineRoutineFrame

.routine out A,carry,zero clobbers sign,parity,halfCarry,B,C,D,DE,HL
Stage7EndRoutine:
            CALL NextSemanticByte
            OR   A
            RET  NZ
            CALL ExpressionRestoreFrame
.if CompilerDiagnosticReturns
            RET  C
.endif
            CALL EmitByteInline
            .db  $C9

.routine out A,carry,zero clobbers sign,parity,halfCarry,B,C,D,DE,HL,IX,IY
Stage7LoadProgramAlias:
            CALL ExpressionProgramAddress
            JR   Stage7LoadAliasReady

.routine out A,carry,zero clobbers sign,parity,halfCarry,B,C,D,DE,HL,IX,IY
Stage7LoadReadOnlyAlias:
            CALL ReadSemanticWord
.if TargetStreamingOutput
            LD   HL,(TargetCurrentRoBase)
            ADD  HL,DE
.else
            LD   HL,(StaticImageLength)
            ADD  HL,DE
            LD   DE,GeneratedRoDataBase
            ADD  HL,DE
.endif
Stage7LoadAliasReady:
            LD   A,$21                    ; LD HL,nn
            JP   TypedEmitOpcodeWordPushHL

Stage7LoadParameterAlias .equ TypedLoadLocal16

.routine out A,carry,zero clobbers sign,parity,halfCarry,B,C,D,DE,HL
Stage7SelectField:
            CALL ReadSemanticWord
            LD   (Stage7PathOffset),DE
            CALL EmitPairIndexedInline
            .db  EmitPairPopHLLoadDE
.if CompilerDiagnosticReturns
            RET  C
.endif
            LD   HL,(Stage7PathOffset)
            CALL EmitWord
.if CompilerDiagnosticReturns
            RET  C
.endif
            LD   HL,Stage7AddDEPush
            JP   EmitPair

.routine out A,carry,zero clobbers sign,parity,halfCarry,B,C,D,DE,HL
Stage7SelectIndex:
            CALL ReadSemanticWord
            LD   (Stage7PathOffset),DE     ; length
            CALL Stage7ReadExtentAndOffset ; stride and source position
            CALL EmitPairIndexedInline
            .db  EmitPairPopDEHL
.if CompilerDiagnosticReturns
            RET  C
.endif
            LD   HL,(Stage7PathOffset)
            CALL EmitLoadBcImmediate
.if CompilerDiagnosticReturns
            RET  C
.endif
.if TargetStreamingOutput
            LD   DE,NucleusRuntimeCheckArrayIndexOffset
            CALL EmitRuntimeCall
.else
            LD   HL,CheckArrayIndex
            CALL EmitCall
.endif
.if CompilerDiagnosticReturns
            RET  C
.endif
            CALL Stage7BoundsGuard
.if CompilerDiagnosticReturns
            RET  C
.endif
            CALL EmitByteInlineChecked
            .db  $E5                    ; retain base
.if CompilerDiagnosticReturns
            RET  C
.endif
            LD   HL,(Stage7PathExtent)
            LD   A,$21                    ; LD HL,nn stride
            CALL EmitOpcodeWord
.if CompilerDiagnosticReturns
            RET  C
.endif
.if TargetStreamingOutput
            LD   DE,NucleusRuntimeMultiplyU16Offset
            CALL EmitRuntimeCall
.else
            LD   HL,MultiplyU16
            CALL EmitCall
.endif
.if CompilerDiagnosticReturns
            RET  C
.endif
            LD   HL,Stage7PopDEAddPush
            JP   EmitThree

.routine out A,carry,zero clobbers sign,parity,halfCarry,B,C,D,DE,HL
Stage7LoadIndirect8:
            LD   HL,Stage7LoadIndirect8Bytes
            LD   B,6
            JP   EmitBytes
.routine out A,carry,zero clobbers sign,parity,halfCarry,B,C,D,DE,HL
Stage7LoadIndirect16:
            LD   HL,Stage7LoadIndirect16Bytes
            JP   EmitFive
.routine out A,carry,zero clobbers sign,parity,halfCarry,B,C,D,DE,HL
Stage7StoreIndirect8:
            LD   HL,Stage7StoreIndirect8Bytes
            JP   EmitThree
.routine out A,carry,zero clobbers sign,parity,halfCarry,B,C,D,DE,HL
Stage7StoreIndirect16:
            LD   HL,Stage7StoreIndirect16Bytes
            JP   EmitFive

; Both full-region calls complete before LDIR is emitted. A failed first or
; second check reaches bounds with the destination still untouched.
.routine out A,carry,zero clobbers sign,parity,halfCarry,B,C,D,DE,HL,IX,IY
Stage7CopyAggregate:
            CALL Stage7ReadExtentAndOffset
            LD   HL,Stage7CopyPrepare
            CALL   EmitFour
.if CompilerDiagnosticReturns
            RET  C
.endif
            CALL Stage7EmitRegionCheck
.if CompilerDiagnosticReturns
            RET  C
.endif
            CALL Stage7PreserveCarrierRegion
.if CompilerDiagnosticReturns
            RET  C
.endif
            CALL EmitPairIndexedInline
            .db  EmitPairPopHLDE
.if CompilerDiagnosticReturns
            RET  C
.endif
            LD   HL,(Stage7PathExtent)
            CALL EmitLoadBcImmediate
.if CompilerDiagnosticReturns
            RET  C
.endif
            LD   HL,Stage7LDIR
            JP   EmitPair

.routine out A,DE,HL,carry,zero clobbers sign,parity,halfCarry
Stage7ReadExtentAndOffset:
            CALL ReadSemanticWord
            LD   (Stage7PathExtent),DE
            JP   Stage7ReadCallOffset

.routine out A,carry,zero clobbers sign,parity,halfCarry,B,C,D,DE,HL
Stage7PreserveCarrierRegion:
            CALL TypedEmitPopHL           ; source
.if CompilerDiagnosticReturns
            RET  C
.endif
            CALL EmitByteInlineChecked
            .db  $E5                    ; retain source
.if CompilerDiagnosticReturns
            RET  C
.endif

.routine out A,carry,zero clobbers sign,parity,halfCarry,B,C,D,DE,HL
Stage7EmitRegionCheck:
            CALL Stage7EmitRegionPrefix
.if CompilerDiagnosticReturns
            RET  C
.endif
            LD   HL,(Stage7PathExtent)
            CALL EmitLoadBcImmediate
.if CompilerDiagnosticReturns
            RET  C
.endif
            JR   Stage7EmitRegionInvoke

.routine out A,carry,zero clobbers sign,parity,halfCarry,B,C,D,DE,HL
Stage7EmitRegionPrefix:
.if TargetStreamingOutput
            LD   DE,(TargetCurrentRoBase)
            CALL EmitLoadDeImmediate
.if CompilerDiagnosticReturns
            RET  C
.endif
            LD   HL,(TargetCurrentRoCapacity)
            PUSH HL
            LD   A,$FD
            CALL EmitByte
            POP  HL
.if CompilerDiagnosticReturns
            RET  C
.endif
            LD   A,$21
            CALL EmitOpcodeWord
.else
            LD   DE,ProgramDataRegionLimit
            CALL EmitLoadDeImmediate
.endif
            RET

.routine out A,carry,zero clobbers sign,parity,halfCarry,B,C,D,DE,HL
Stage7EmitRegionInvoke:
.if TargetStreamingOutput
            LD   DE,NucleusRuntimeCheckAggregateRegionOffset
            CALL EmitRuntimeCall
.else
            LD   HL,CheckAggregateRegion
            CALL EmitCall
.endif
.if CompilerDiagnosticReturns
            RET  C
.endif
            JP   Stage7BoundsGuard

.routine out A,DE,carry,zero clobbers sign,parity,halfCarry,HL
Stage7ReadStringExtent:
            CALL NextSemanticByte
            LD   (Stage7ArgumentCount),A
            LD   L,A
            LD   H,0
            INC  HL
            INC  HL
            LD   (Stage7PathExtent),HL
            JP   Stage7ReadCallOffset

.routine out A,carry,zero clobbers sign,parity,halfCarry,B,C,D,DE,HL
Stage7StringLength:
            CALL Stage7ReadStringExtent
            CALL Stage7PreserveCarrierRegion
.if CompilerDiagnosticReturns
            RET  C
.endif
            CALL TypedEmitPopHL           ; carrier
.if CompilerDiagnosticReturns
            RET  C
.endif
.if TargetStreamingOutput
            LD   DE,NucleusRuntimeCheckStringLengthOffset
.else
            LD   HL,CheckStringLength
.endif
            JP   Stage7EmitStringCheck

.routine out A,carry,zero clobbers sign,parity,halfCarry,B,C,D,DE,HL
Stage7StringIndex:
            CALL Stage7ReadStringExtent
            CALL Stage7EmitStringIndexPrefix
.if CompilerDiagnosticReturns
            RET  C
.endif
            CALL Stage7EmitRegionCheck
.if CompilerDiagnosticReturns
            RET  C
.endif
            CALL EmitPairIndexedInline
            .db  EmitPairPopHLDE
.if CompilerDiagnosticReturns
            RET  C
.endif
.if TargetStreamingOutput
            LD   DE,NucleusRuntimeCheckStringIndexOffset
.else
            LD   HL,CheckStringIndex
.endif
            JP   Stage7EmitStringCheck

.routine out A,carry,zero clobbers sign,parity,halfCarry,B,C,D,DE,HL
Stage7EmitStringIndexPrefix:
            CALL EmitPairIndexedInline
            .db  EmitPairPopDEHL
.if CompilerDiagnosticReturns
            RET  C
.endif
            LD   HL,Stage7PushDEHL
            JP   EmitPair

; Open string operations read the caller-supplied concrete capacity from the
; hidden activation byte. The ordinary source value remains one address path.
.routine out A,DE,carry,zero clobbers sign,parity,halfCarry,HL
Stage7ReadOpenStringOffset:
            CALL NextSemanticByte
            LD   (Stage7ArgumentCount),A
            JP   Stage7ReadCallOffset

.routine out A,carry,zero clobbers sign,parity,halfCarry,B,C,D,DE,HL
Stage7OpenStringLength:
            CALL Stage7ReadOpenStringOffset
            CALL TypedEmitPopHL
.if CompilerDiagnosticReturns
            RET  C
.endif
            CALL EmitByteInlineChecked
            .db  $E5                    ; retain carrier
.if CompilerDiagnosticReturns
            RET  C
.endif
            CALL Stage7EmitOpenRegionCheck
.if CompilerDiagnosticReturns
            RET  C
.endif
            CALL TypedEmitPopHL
.if CompilerDiagnosticReturns
            RET  C
.endif
.if TargetStreamingOutput
            LD   DE,NucleusRuntimeCheckStringLengthOffset
.else
            LD   HL,CheckStringLength
.endif
            JR   Stage7EmitOpenStringCheck

.routine out A,carry,zero clobbers sign,parity,halfCarry,B,C,D,DE,HL
Stage7OpenStringIndex:
            CALL Stage7ReadOpenStringOffset
            CALL Stage7EmitStringIndexPrefix
.if CompilerDiagnosticReturns
            RET  C
.endif
            CALL Stage7EmitOpenRegionCheck
.if CompilerDiagnosticReturns
            RET  C
.endif
            CALL EmitPairIndexedInline
            .db  EmitPairPopHLDE
.if CompilerDiagnosticReturns
            RET  C
.endif
.if TargetStreamingOutput
            LD   DE,NucleusRuntimeCheckStringIndexOffset
.else
            LD   HL,CheckStringIndex
.endif

.if TargetStreamingOutput
.routine in DE out A,carry,zero clobbers sign,parity,halfCarry,B,C,D,DE,HL
.else
.routine in HL out A,carry,zero clobbers sign,parity,halfCarry,B,C,D,DE,HL
.endif
Stage7EmitOpenStringCheck:
.if TargetStreamingOutput
            PUSH DE
.else
            PUSH HL
.endif
            CALL Stage7EmitOpenCapacityC
.if TargetStreamingOutput
            POP  DE
.else
            POP  HL
.endif
            JR   Stage7EmitStringCheckFinish

.if TargetStreamingOutput
.routine in DE out A,carry,zero clobbers sign,parity,halfCarry,B,C,D,DE,HL
.else
.routine in HL out A,carry,zero clobbers sign,parity,halfCarry,B,C,D,DE,HL
.endif
Stage7EmitStringCheckFinish:
.if CompilerDiagnosticReturns
            RET  C
.endif
.if TargetStreamingOutput
            CALL EmitRuntimeCall
.else
            CALL EmitCall
.endif
.if CompilerDiagnosticReturns
            RET  C
.endif
            CALL Stage7BoundsGuard
.if CompilerDiagnosticReturns
            RET  C
.endif
            CALL EmitByteInline
            .db  $E5                      ; push length or addressed byte

; Emit BC = hidden concrete capacity + two representation bytes, then perform
; the ordinary complete-region guard before a generic string may be touched.
.routine out A,carry,zero clobbers sign,parity,halfCarry,B,C,D,DE,HL
Stage7EmitOpenRegionCheck:
            CALL Stage7EmitRegionPrefix
.if CompilerDiagnosticReturns
            RET  C
.endif
            CALL Stage7EmitOpenCapacityC
.if CompilerDiagnosticReturns
            RET  C
.endif
            LD   HL,Stage7OpenExtentBytes
            CALL EmitFour
.if CompilerDiagnosticReturns
            RET  C
.endif
            JP   Stage7EmitRegionInvoke

.routine out A,carry,zero clobbers sign,parity,halfCarry,B,C,D,DE,HL
Stage7EmitOpenCapacityC:
            LD   HL,Stage7LoadIXC
            JR   Stage7EmitOpenDisplacedCapacity

.routine in HL out A,carry,zero clobbers sign,parity,halfCarry,B,C,D,DE,HL
Stage7EmitOpenDisplacedCapacity:
            CALL EmitPair
.if CompilerDiagnosticReturns
            RET  C
.endif
            LD   A,(Stage7ArgumentCount)
            CPL
            JP   EmitByte

; Convert a just-evaluated address carrier into the internal open-argument
; pair. Mode zero carries a static capacity; mode one forwards a hidden local.
.routine out A,carry,zero clobbers sign,parity,halfCarry,B,C,D,DE,HL,IX,IY
Stage7PrepareOpenArgument:
            CALL NextSemanticByte
            LD   (Stage7ArgumentIndex),A
            CALL NextSemanticByte
            LD   (Stage7ArgumentCount),A
            CALL EmitByteInlineChecked
            .db  $D1                    ; POP DE address carrier
.if CompilerDiagnosticReturns
            RET  C
.endif
            LD   A,(Stage7ArgumentIndex)
            OR   A
            JR   NZ,Stage7PrepareForwardedOpenArgument
            LD   A,(Stage7ArgumentCount)
            LD   L,A
            LD   H,0
            CALL EmitLoadHl
            JR   Stage7PrepareOpenArgumentPush
Stage7PrepareForwardedOpenArgument:
            LD   HL,Stage7LoadIXL
            CALL Stage7EmitOpenDisplacedCapacity
.if CompilerDiagnosticReturns
            RET  C
.endif
            CALL EmitPairIndexedInline
            .db  EmitPairZeroH
Stage7PrepareOpenArgumentPush:
.if CompilerDiagnosticReturns
            RET  C
.endif
            LD   HL,Stage7PushHLDE
            JP   EmitPair

.if TargetStreamingOutput
.routine in DE out A,carry,zero clobbers sign,parity,halfCarry,B,C,D,DE,HL
.else
.routine in HL out A,carry,zero clobbers sign,parity,halfCarry,B,C,D,DE,HL
.endif
Stage7EmitStringCheck:
.if TargetStreamingOutput
            PUSH DE
.else
            PUSH HL
.endif
            LD   A,(Stage7ArgumentCount)
            LD   C,A
            LD   A,$0E                    ; LD C,n capacity
            CALL EmitOpcodeByte
.if TargetStreamingOutput
            POP  DE
.else
            POP  HL
.endif
            JR   Stage7EmitStringCheckFinish

Stage7IndexToA            .equ TypedLoadSPPrefix+1
Stage7LoadBImmediate:     .db $06
Stage7OffsetAddress:      .db $5F,$16,$00,$19,$E5
Stage7LoadIndirect8Bytes  .equ Stage7LoadIndirect8Prefix
Stage7LoadIndirect16Bytes:.db $E1,$5E,$23,$56,$D5
Stage7StoreIndirect16Bytes:.db $D1,$E1,$73,$23,$72
Stage7CopyPrepare         .equ TypedPopOperandsBytes
Stage7PopDEAddPush:       .db $D1,$19,$E5
Stage7PushDEHL:           .db $D5,$E5
Stage7PushHLDE            .equ TypedPopOperandsBytes+2
Stage7LoadIXC:            .db $DD,$4E
Stage7ZeroHighBytes       .equ TypedZeroHigh
Stage7OpenExtentBytes:    .db $06,$00,$03,$03
Stage7LDIR                .equ SegmentedCopyBytes

Stage7DecSP2              .equ TypedParameter16Bytes
Stage7LoadIXL             .equ TypedLoadLocalLow
Stage7LoadIXH             .equ TypedLoadLocalHigh
Stage7StoreIXL            .equ TypedStoreLocalLow
Stage7StoreIXH            .equ TypedStoreLocalHigh
Stage7AddDEPush           .equ Stage7OffsetAddress+3
Stage7PopIndexBase        .equ TypedPopOperandsBytes
Stage7StoreIndirect8Bytes .equ Stage7StoreIndirect16Bytes
Stage8PopErrorBytes       .equ TypedNot8Bytes ; POP HL / LD A,L prefix
Stage8FailureReturnBytes: .db $37,$C9      ; SCF / RET
Stage8SuccessReturnBytes: .db $B7,$C9      ; OR A / RET
Stage8ErrorCarrierBytes .equ TypedAtoHL       ; LD L,A / LD H,0 / PUSH HL
.if TargetStreamingOutput
.else
Stage8ReloadFailureOffsetBytes:
            .db $F5,$2A                   ; PUSH AF / LD HL,(nn)
            .dw TrapOffset
            .db $F1                       ; POP AF
.endif
