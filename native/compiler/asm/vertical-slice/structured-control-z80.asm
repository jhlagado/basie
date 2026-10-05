; Post-parse absolute-label and structured-loop lowering. All generated branch
; operands are compiler-private absolute words and are resolved before the
; generated program is published.

EmitControlCounter      .equ EmitCodeStart
EmitControlMode         .equ EmitCodeStart+1
EmitControlStep         .equ EmitLoopHead
EmitControlTrapOffset   .equ EmitExitFixup
EmitControlTestLabel    .equ EmitFailureFixup
EmitControlExitLabel    .equ EmitFailureFixup+1

; C is a label ordinal and DE is the address of a generated word operand.
.if TargetStreamingOutput
; Bit 7 distinguishes a cross-bank address operand. Bits 5..6 retain the site
; bank and bits 0..4 retain the globally unique label ordinal.
.endif
.routine in C,DE out A,carry,zero clobbers sign,parity,halfCarry,B,C,D,DE,HL
StructuredRecordFixup:
            LD   A,C
.if TargetStreamingOutput
            AND  $1F
.endif
            CP   EmitControlLabelCapacity
            JP   NC,ControlLabelFailure
            LD   A,(EmitControlFixupCount)
            CP   EmitControlFixupCapacity
            JR   NC,StructuredFixupFailure
            PUSH BC
            LD   L,A
            LD   H,0
            ADD  A,A
            ADD  A,L
            LD   L,A
            LD   H,0
            LD   BC,EmitControlFixupBase
            ADD  HL,BC
            POP  BC
.if TargetStreamingOutput
            LD   A,(TargetOutputBank)
            RLCA
            RLCA
            RLCA
            RLCA
            RLCA
            OR   C
            LD   (HL),A
.else
            LD   (HL),C
.endif
            INC  HL
            LD   (HL),E
            INC  HL
            LD   (HL),D
            LD   HL,EmitControlFixupCount
            INC  (HL)
            XOR  A
            RET
StructuredFixupFailure:
            CALL SetDiagInline
            .db  DiagnosticControlFixupCapacity

; Emit opcode A with a zero word operand and retain that operand for label C.
.if TargetStreamingOutput
.routine in A,C out A,carry,zero clobbers sign,parity,halfCarry,B,C,D,DE,HL
StructuredEmitFarFixup:
            SET  7,C
.endif
.routine in A,C out A,carry,zero clobbers sign,parity,halfCarry,B,C,D,DE,HL
StructuredEmitFixup:
            PUSH BC
            CALL EmitByte
            POP  BC
.if CompilerDiagnosticReturns
            RET  C
.endif
            LD   DE,(EmitCursor)
            PUSH BC
            PUSH DE
            LD   HL,0
            CALL EmitWord
            POP  DE
            POP  BC
.if CompilerDiagnosticReturns
            RET  C
.endif
            JR   StructuredRecordFixup

.routine out A,carry,zero clobbers sign,parity,halfCarry,B,C,D,DE,HL
StructuredLabel:
            CALL NextSemanticByte
            LD   C,A
.routine in C out A,carry,zero clobbers sign,parity,halfCarry,B,C,D,DE,HL
StructuredDefineLabel:
            LD   A,C
            CP   EmitControlLabelCapacity
            JP   NC,ControlLabelFailure
            LD   B,0
            LD   HL,EmitControlLabelValidBase
            ADD  HL,BC
            LD   A,(HL)
            OR   A
            JP   NZ,TypedInternalOperation
.if TargetStreamingOutput
            LD   A,(TargetOutputBank)
            INC  A
            LD   (HL),A
.else
            LD   (HL),1
.endif
            LD   L,C
            LD   H,0
            ADD  HL,HL
            LD   BC,EmitControlLabelAddressBase
            ADD  HL,BC
            LD   DE,(EmitCursor)
            LD   (HL),E
            INC  HL
            LD   (HL),D
            XOR  A
            RET

.routine out A,carry,zero clobbers sign,parity,halfCarry,B,C,D,DE,HL
StructuredBranchFalse:
            CALL NextSemanticByte
            LD   C,A
            PUSH BC
            LD   HL,StructuredBranchFalseBytes
            CALL   EmitThree
            POP  BC
.if CompilerDiagnosticReturns
            RET  C
.endif
            LD   A,$CA                    ; JP Z,nn
            JR   StructuredEmitFixup

.routine out A,carry,zero clobbers sign,parity,halfCarry,B,C,D,DE,HL
StructuredJump:
            CALL NextSemanticByte
            LD   C,A
            LD   A,$C3                    ; JP nn
            JR   StructuredEmitFixup

; Resolve every retained absolute operand after all label locations are known.
.routine out A,carry,zero clobbers sign,parity,halfCarry,B,C,D,DE,HL,IX,IY
StructuredResolveFixups:
.if TargetStreamingOutput
            CALL TargetSaveOutputBank
.if CompilerDiagnosticReturns
            RET  C
.endif
.endif
            LD   A,(EmitControlFixupCount)
            OR   A
            RET  Z
            LD   B,A
            LD   IX,EmitControlFixupBase
StructuredResolveNext:
            LD   C,(IX+0)
.if TargetStreamingOutput
            LD   A,C
            RLCA
            RLCA
            RLCA
            AND  $03
.endif
            LD   E,(IX+1)
            LD   D,(IX+2)
.if TargetStreamingOutput
            PUSH BC
            PUSH DE
            LD   E,A
            LD   D,C
            LD   A,C
            AND  $1F
            LD   C,A
            LD   A,E
            LD   (TargetOutputBank),A
.endif
            LD   A,C
.if TargetStreamingOutput
.else
            CP   EmitControlLabelCapacity
            JR   NC,StructuredResolveFailure
            PUSH BC
            PUSH DE
.endif
            LD   B,0
            LD   HL,EmitControlLabelValidBase
            ADD  HL,BC
            LD   A,(HL)
            OR   A
            JR   Z,StructuredResolveUnwind
.if TargetStreamingOutput
            DEC  A
            BIT  7,D
            JR   NZ,StructuredResolveBankReady
            CP   E
            JR   NZ,StructuredResolveUnwind
StructuredResolveBankReady:
.endif
            LD   H,0
            LD   L,C
            ADD  HL,HL
            LD   BC,EmitControlLabelAddressBase
            ADD  HL,BC
            LD   C,(HL)
            INC  HL
            LD   H,(HL)
            LD   L,C
            POP  DE
            CALL PatchWord
            POP  BC
.if CompilerDiagnosticReturns
            RET  C
.endif
            INC  IX
            INC  IX
            INC  IX
            DJNZ StructuredResolveNext
.if TargetStreamingOutput
            LD   A,TargetOutputClosed
            LD   (TargetOutputBank),A
.endif
            XOR  A
            RET
StructuredResolveUnwind:
            POP  DE
            POP  BC
StructuredResolveFailure:
            JP   TypedInternalOperation

; Emit a local load into HL without pushing a new expression carrier.
; C is the byte offset, A bit 2 selects u16.
.routine in A,C out A,carry,zero clobbers sign,parity,halfCarry,B,C,D,DE,HL
StructuredLoadCounter:
            LD   D,A
            LD   A,C
            CPL
            LD   C,A
            PUSH BC
            PUSH DE
            CALL EmitPairIndexedInline
            .db  EmitPairLoadIXL
            POP  DE
            POP  BC
.if CompilerDiagnosticReturns
            RET  C
.endif
            LD   A,C
            PUSH DE
            CALL EmitByte
            POP  DE
.if CompilerDiagnosticReturns
            RET  C
.endif
            BIT  2,D
            JR   NZ,StructuredLoadCounterHigh
            LD   HL,TypedZeroHigh
            JP   EmitPair
StructuredLoadCounterHigh:
            DEC  C
            PUSH BC
            CALL EmitPairIndexedInline
            .db  EmitPairLoadIXH
            POP  BC
.if CompilerDiagnosticReturns
            RET  C
.endif
            LD   A,C
            JP   EmitByte

; Store HL to counter byte offset C; A bit 2 selects u16.
.routine in A,C out A,carry,zero clobbers sign,parity,halfCarry,B,C,D,DE,HL
StructuredStoreCounter:
            LD   D,A
            LD   A,C
            CPL
            LD   C,A
            PUSH BC
            PUSH DE
            CALL EmitPairIndexedInline
            .db  EmitPairStoreIXL
            POP  DE
            POP  BC
.if CompilerDiagnosticReturns
            RET  C
.endif
            LD   A,C
            PUSH BC
            PUSH DE
            CALL EmitByte
            POP  DE
            POP  BC
.if CompilerDiagnosticReturns
            RET  C
.endif
            BIT  2,D
            RET  Z
            DEC  C
            PUSH BC
            CALL EmitPairIndexedInline
            .db  EmitPairStoreIXH
            POP  BC
.if CompilerDiagnosticReturns
            RET  C
.endif
            LD   A,C
            JP   EmitByte

.routine out A,carry,zero clobbers sign,parity,halfCarry,B,C,D,DE,HL
StructuredForSetup:
            CALL NextSemanticByte
            LD   C,A
            CALL NextSemanticByte
            LD   B,A
            PUSH BC
            CALL EmitPairIndexedInline
            .db  EmitPairPopDEHL
            POP  BC
.if CompilerDiagnosticReturns
            RET  C
.endif
            LD   A,B
            CALL StructuredStoreCounter
.if CompilerDiagnosticReturns
            RET  C
.endif
            CALL EmitByteInline
            .db  $D5                      ; PUSH DE, retained bound

.routine out A,carry,zero clobbers sign,parity,halfCarry,B,C,D,DE,HL,IX,IY
StructuredForTest:
            CALL NextSemanticByte
            LD   C,A                      ; counter
            CALL NextSemanticByte
            LD   B,A                      ; mode
            CALL NextSemanticByte
            LD   D,A                      ; exit label
            LD   (EmitControlExitLabel),A
            PUSH BC
            PUSH DE
            CALL EmitPairIndexedInline
            .db  EmitPairPopDEPushDE
            POP  DE
            POP  BC
.if CompilerDiagnosticReturns
            RET  C
.endif
            PUSH BC
            PUSH DE
            LD   A,B
            CALL StructuredLoadCounter
            POP  DE
            POP  BC
.if CompilerDiagnosticReturns
            RET  C
.endif
            BIT  1,B
            JR   NZ,StructuredForTestNegative
            BIT  0,B
            LD   A,ComparisonLess
            JR   Z,StructuredForTestCompare
            LD   A,ComparisonLessEqual
            JR   StructuredForTestCompare
StructuredForTestNegative:
            BIT  0,B
            LD   A,ComparisonGreater
            JR   Z,StructuredForTestCompare
            LD   A,ComparisonGreaterEqual
StructuredForTestCompare:
            CALL TypedEmitCompare
.if CompilerDiagnosticReturns
            RET  C
.endif
            LD   A,(EmitControlExitLabel)
            LD   C,A
            CALL EmitPairIndexedInline
            .db  EmitPairTestL
.if CompilerDiagnosticReturns
            RET  C
.endif
            LD   A,$CA
            JP   StructuredEmitFixup

.routine in DE out A,carry,zero clobbers sign,parity,halfCarry,B,C,D,DE,HL
EmitLoadDeImmediate:
            LD   A,$11                    ; LD DE,nn
            PUSH DE
            CALL EmitByte
            POP  DE
.if CompilerDiagnosticReturns
            RET  C
.endif
            LD   H,D
            LD   L,E
            JP   EmitWord

; Read and retain the fixed-width ForNext operands in emitter scratch.
.routine out A,carry,zero clobbers sign,parity,halfCarry,B,C,D,DE,HL,IX,IY
StructuredForNext:
            CALL NextSemanticByte
            LD   (EmitControlTestLabel),A
            CALL NextSemanticByte
            LD   (EmitControlExitLabel),A
            CALL NextSemanticByte
            LD   (EmitControlCounter),A
            CALL NextSemanticByte
            LD   (EmitControlMode),A
            CALL ReadSemanticWord
            LD   (EmitControlStep),DE
            CALL ReadSemanticWord
            LD   (EmitControlTrapOffset),DE
            XOR  A
            CALL EmitPairIndexedInline
            .db  EmitPairPopDEPushDE
.if CompilerDiagnosticReturns
            RET  C
.endif
            LD   A,(EmitControlCounter)
            LD   C,A
            LD   A,(EmitControlMode)
            CALL StructuredLoadCounter
.if CompilerDiagnosticReturns
            RET  C
.endif
            CALL EmitByteInlineChecked
            .db  $E5                    ; preserve current counter
.if CompilerDiagnosticReturns
            RET  C
.endif
            LD   A,(EmitControlMode)
            BIT  1,A
            JR   NZ,StructuredNegativeDistance
            CALL EmitByteInlineChecked
            .db  $EB                    ; EX DE,HL => bound-current
.if CompilerDiagnosticReturns
            RET  C
.endif
StructuredNegativeDistance:
            LD   HL,StructuredSubtractDE
            CALL   EmitThree
.if CompilerDiagnosticReturns
            RET  C
.endif
            LD   DE,(EmitControlStep)
            CALL EmitLoadDeImmediate
.if CompilerDiagnosticReturns
            RET  C
.endif
            LD   A,(EmitControlMode)
            AND  1
            LD   A,ComparisonLess
            JR   NZ,StructuredDistanceCompare
            ; until exits when distance <= step; to exits when distance < step.
            LD   A,(EmitControlMode)
            BIT  0,A
            LD   A,ComparisonLess
            JR   NZ,StructuredDistanceCompare
            LD   A,ComparisonLessEqual
StructuredDistanceCompare:
            CALL TypedEmitCompare
.if CompilerDiagnosticReturns
            RET  C
.endif
            LD   HL,StructuredTestThenPopCurrent
            CALL   EmitThree
.if CompilerDiagnosticReturns
            RET  C
.endif
            LD   A,(EmitControlExitLabel)
            LD   C,A
            LD   A,$C2                    ; JP NZ,exit cleanup
            CALL StructuredEmitFixup
.if CompilerDiagnosticReturns
            RET  C
.endif
            LD   DE,(EmitControlStep)
            CALL EmitLoadDeImmediate
.if CompilerDiagnosticReturns
            RET  C
.endif
            LD   A,(EmitControlMode)
            BIT  1,A
            JR   NZ,StructuredSubtractStep
            LD   A,$19                    ; ADD HL,DE
            CALL EmitByte
            JR   StructuredForNextFit
StructuredSubtractStep:
            LD   HL,StructuredSubtractDE
            CALL   EmitThree
StructuredForNextFit:
.if CompilerDiagnosticReturns
            RET  C
.endif
            LD   A,(EmitControlMode)
            BIT  2,A
            JR   NZ,StructuredForNextStore
            BIT  1,A
            JR   NZ,StructuredForNextStore
            CALL EmitPairIndexedInline
            .db  EmitPairTestH
.if CompilerDiagnosticReturns
            RET  C
.endif
            CALL EmitByteInlineChecked
            .db  $CA                    ; JP Z,fit
.if CompilerDiagnosticReturns
            RET  C
.endif
            LD   HL,(EmitCursor)
            LD   (EmitUpdateExitFixup),HL
            LD   HL,0
            CALL EmitWord
.if CompilerDiagnosticReturns
            RET  C
.endif
            LD   HL,(EmitControlTrapOffset)
            LD   A,4
            CALL TypedEmitTrapBody
.if CompilerDiagnosticReturns
            RET  C
.endif
            LD   DE,(EmitUpdateExitFixup)
            LD   HL,(EmitCursor)
            CALL PatchWord
StructuredForNextStore:
            LD   A,(EmitControlCounter)
            LD   C,A
            LD   A,(EmitControlMode)
            CALL StructuredStoreCounter
.if CompilerDiagnosticReturns
            RET  C
.endif
            LD   A,(EmitControlTestLabel)
            LD   C,A
            LD   A,$C3
            JP   StructuredEmitFixup

.routine out A,carry,zero clobbers sign,parity,halfCarry,B,DE,HL
StructuredForCleanup:
            CALL EmitByteInline
            .db  $D1                      ; POP DE, discard retained bound

StructuredBranchFalseBytes .equ TypedBeginAndBytes
StructuredPopBoundStart    .equ TypedPopOperandsBytes
StructuredTestHL           .equ TypedBeginAndBytes+1
StructuredSubtractDE:        .db $B7,$ED,$52
StructuredTestThenPopCurrent: .db $7D,$B7,$E1
