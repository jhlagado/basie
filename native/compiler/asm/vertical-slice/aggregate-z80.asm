; Aggregate Z80 publisher. The complete checked initialized-data and constant
; image is emitted after
; the initial JP and before main's first instruction. TypedBeginMain
; patches the JP operand to the first code byte, so source execution cannot
; observe initialization in progress.

.if TargetStreamingOutput
; Emit every aggregate constant exactly once in declaration order. Symbols
; retain per-bank offsets, while IY walks the single declaration-ordered
; compiler backing image. Switching banks never replays source or semantics.
.routine out A,carry,zero clobbers sign,parity,halfCarry,BC,DE,HL,IX,IY
TargetEmitBankedAggregateConstants:
            LD   A,(SymbolCount)
            OR   A
            RET  Z
            LD   B,A
            LD   C,0
            LD   IX,SymbolTableBase
            LD   IY,StaticImageBase
            LD   DE,(StaticImageLength)
            ADD  IY,DE
TargetEmitBankedConstantSymbolLoop:
            LD   A,(IX+3)
            LD   D,A
            AND  SymbolAggregateFlag+SymbolClassMask
            CP   SymbolAggregateFlag+SymbolClassConstant
            JR   NZ,TargetEmitBankedConstantNext
            LD   A,D
            CALL TargetUnpackBank
            PUSH BC
            CALL TargetSelectOutputBank
            POP  BC
.if CompilerDiagnosticReturns
            RET  C
.endif
            LD   H,0
            LD   L,C
            LD   DE,AggregateSymbolTypeBase
            ADD  HL,DE
            LD   A,(HL)
            CALL AggregateGetExtent
            EX   DE,HL
TargetEmitBankedConstantByteLoop:
            LD   A,D
            OR   E
            JR   Z,TargetEmitBankedConstantNext
            LD   A,(IY+0)
            INC  IY
            PUSH BC
            PUSH DE
            CALL EmitByte
            POP  DE
            POP  BC
.if CompilerDiagnosticReturns
            RET  C
.endif
            DEC  DE
            JR   TargetEmitBankedConstantByteLoop
TargetEmitBankedConstantNext:
            LD   DE,SymbolEntrySize
            ADD  IX,DE
            INC  C
            DJNZ TargetEmitBankedConstantSymbolLoop
            OR   A
            RET
.endif

.routine out A,carry,zero clobbers sign,parity,halfCarry,B,C,D,DE,HL,IX,IY
EncodeAggregateProgram:
.if TargetStreamingOutput
            LD   IX,(TargetDescriptorPointer)
            CALL BeginTargetFlatProgram
.if CompilerDiagnosticBranches
            JP   C,AbortTargetProgram
.endif
.else
.if AggregateCallSlices
            LD   HL,GeneratedCodeLimit
.else
            LD   HL,GeneratedLimit
.endif
.endif
.routine in HL out A,carry,zero clobbers sign,parity,halfCarry,B,C,D,DE,HL,IX,IY
EncodeAggregateProgramWithinLimit:
.if TargetStreamingOutput
            LD   A,(TargetDescriptorBankCountValue)
            CP   1
            JR   NZ,AggregateDispatch
            ; BeginTargetFlatProgram already selected the first read-only byte.
            LD   A,(TargetLayoutMode)
            OR   A
            JR   Z,AggregateTargetLoadedRoData
            LD   HL,(EmitCursor)
            CALL TargetEmitRuntimeInitialImage
.if CompilerDiagnosticBranches
            JP   C,AggregateAbortProgram
.endif
            JR   AggregateTargetCopyReady
AggregateTargetLoadedRoData:
            LD   HL,StaticImageBase
            LD   DE,(StaticImageLength)
            ADD  HL,DE
            LD   BC,(ReadOnlyImageLength)
            JR   AggregateTargetCopySelected
AggregateTargetCopyReady:
.else
.if AggregateCallSlices
            CALL BeginSegmentedProgram
            JP   C,AbortSegmentedProgram
            LD   A,SegmentRoData
            CALL SelectOutputSegment
.else
            CALL EncodeProgramHeader
            JP   C,AbortProgram
.endif
.endif
.if SegmentedOutput
            LD   HL,(ReadOnlyImageLength)
            LD   BC,(StaticImageLength)
            ADD  HL,BC
            LD   B,H
            LD   C,L
            LD   HL,StaticImageBase
.else
            LD   HL,StaticImageBase
            LD   BC,(StaticImageLength)
.endif
.if TargetStreamingOutput
AggregateTargetCopySelected:
            CALL EmitBlock
.if CompilerDiagnosticBranches
            JP   C,AggregateAbortProgram
.endif
.else
            LD   A,B
            OR   C
            JR   Z,AggregateDispatch
AggregateCopyLoop:
            LD   A,(HL)
            INC  HL
            PUSH BC
            PUSH HL
            CALL EmitByte
            POP  HL
            POP  BC
            JP   C,AggregateAbortProgram
            DEC  BC
            LD   A,B
            OR   C
            JR   NZ,AggregateCopyLoop
.endif
AggregateDispatch:
.if TargetStreamingOutput
            LD   A,(TargetDescriptorBankCountValue)
            CP   1
            JR   NZ,AggregateTargetCodeReady
            LD   HL,(EmitCursor)
            LD   (TargetCodeBase),HL
            LD   A,(TargetLayoutMode)
            OR   A
            JR   NZ,AggregateTargetCodeReady
            LD   HL,(TargetCodeCapacity)
            LD   (EmitLimit),HL
AggregateTargetCodeReady:
            LD   A,(TargetDescriptorBankCountValue)
            CP   1
            JR   NZ,AggregateTargetBoundsReady
            LD   HL,(TargetContextRoDataBase)
            LD   (TargetCurrentRoBase),HL
            LD   HL,(TargetContextRoDataCapacity)
            LD   (TargetCurrentRoCapacity),HL
AggregateTargetBoundsReady:
.else
.if AggregateCallSlices
            LD   A,SegmentCode
            CALL SelectOutputSegment
            CALL EncodeSegmentedProgramHeader
            JP   C,AbortSegmentedProgram
.endif
.endif
            CALL TypedDispatch
.if CompilerDiagnosticBranches
            JP   C,AggregateAbortProgram
.endif
.if TargetStreamingOutput
            JP   FinishTargetFlatProgram
.else
.if AggregateCallSlices
            JP   FinishSegmentedProgram
.else
            JP   FinishProgram
.endif
.endif

.if TargetStreamingOutput
AggregateAbortProgram .equ AbortTargetProgram
.else
.if AggregateCallSlices
AggregateAbortProgram .equ AbortSegmentedProgram
.else
AggregateAbortProgram .equ AbortProgram
.endif
.endif
