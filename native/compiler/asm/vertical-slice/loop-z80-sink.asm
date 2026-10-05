; Streaming direct-Z80 encoder for the counted-loop semantic stream.

.routine in A out A,carry,zero clobbers sign,parity,halfCarry,B,DE,HL
EmitByte:
.if TargetStreamingOutput
            LD   B,A
            LD   HL,(EmitLimit)
            LD   A,H
            OR   L
            JP   Z,TargetCapacityFailure
            DEC  HL
            LD   (EmitLimit),HL
            LD   HL,(EmitCursor)
            PUSH BC
            LD   A,(TargetOutputBank)
            LD   C,A
            LD   A,B
            PUSH HL
            CALL TargetSinkImageByte
            POP  HL
            POP  BC
            JP   C,TargetOutputFailure
            INC  HL
            LD   (EmitCursor),HL
            OR   A
            RET
.else
            LD   B,A
            LD   HL,(EmitCursor)
            LD   DE,(EmitLimit)
            OR   A
            SBC  HL,DE
            ADD  HL,DE
            JP   Z,SemanticSinkPutFull
EmitByteRoom:
            LD   A,B
            LD   (HL),A
            INC  HL
            LD   (EmitCursor),HL
            OR   A
            RET
.endif

.routine noreturn
EmitByteInline:
            POP  HL
            LD   A,(HL)
            JR   EmitByte

.routine noreturn
EmitByteInlineChecked:
            POP  HL
            LD   A,(HL)
            INC  HL
            PUSH HL
.if CompilerDiagnosticReturns
            CALL EmitByte
            RET  NC
            POP  HL
            RET
.else
            JR   EmitByte
.endif

.routine noreturn
EmitPairIndexedInline:
            POP  HL
            LD   A,(HL)
            INC  HL
            PUSH HL
            ADD  A,A
            LD   L,A
            LD   H,0
            LD   DE,EmitPairInlineTable
            ADD  HL,DE
.if TargetStreamingOutput
            JR   EmitPair
.else
            JP   EmitPair
.endif

EmitPairDecSp2          .equ 0
EmitPairLoadIXL         .equ 1
EmitPairLoadIXH         .equ 2
EmitPairStoreIXL        .equ 3
EmitPairStoreIXH        .equ 4
EmitPairPopDEHL         .equ 5
EmitPairPopDEPushDE     .equ 6
EmitPairTestL           .equ 7
EmitPairTestH           .equ 8
EmitPairPopHLToA        .equ 9
EmitPairPopHLLoadDE     .equ 10
EmitPairPopHLDE         .equ 11
EmitPairZeroH           .equ 12
EmitPairLDIR            .equ 13
EmitPairInlineTable:
            .db  $3B,$3B                 ; DEC SP / DEC SP
            .db  $DD,$6E                 ; LD L,(IX+n)
            .db  $DD,$66                 ; LD H,(IX+n)
            .db  $DD,$75                 ; LD (IX+n),L
            .db  $DD,$74                 ; LD (IX+n),H
            .db  $D1,$E1                 ; POP DE / POP HL
            .db  $D1,$D5                 ; POP DE / PUSH DE
            .db  $7D,$B7                 ; LD A,L / OR A
            .db  $7C,$B7                 ; LD A,H / OR A
            .db  $E1,$7D                 ; POP HL / LD A,L
            .db  $E1,$11                 ; POP HL / LD DE,nn
            .db  $E1,$D1                 ; POP HL / POP DE
            .db  $26,$00                 ; LD H,0
            .db  $ED,$B0                 ; LDIR

.routine in HL out A,carry,zero clobbers sign,parity,halfCarry,B,C,DE,HL
EmitWord:
            LD   C,H
            LD   A,L
            CALL EmitByte
.if CompilerDiagnosticReturns
            RET  C
.endif
            LD   A,C
            JR   EmitByte

; Copy B retained opcode bytes. Shared fixed sequences are cheaper as data
; once two or more encoder paths need four or more emitted bytes.
.routine in B,HL out A,carry,zero clobbers sign,parity,halfCarry,B,C,DE,HL
EmitBytes:
.if TargetStreamingOutput
            PUSH BC
            LD   C,B
            LD   B,0
            CALL EmitBlock
            POP  BC
            RET
.else
            LD   A,(HL)
            INC  HL
            PUSH BC
            PUSH HL
            CALL EmitByte
            POP  HL
            POP  BC
.if CompilerDiagnosticReturns
            RET  C
.endif
            DJNZ EmitBytes
            OR   A
            RET
.endif

.if TargetStreamingOutput
; Copy the complete BC-byte region through the checked output sink.
.routine in BC,HL out A,carry,zero clobbers sign,parity,halfCarry,B,C,DE,HL
EmitBlock:
            LD   A,B
            OR   C
            RET  Z
            LD   A,(HL)
            INC  HL
            PUSH BC
            PUSH HL
            CALL EmitByte
            POP  HL
            POP  BC
.if CompilerDiagnosticReturns
            RET  C
.endif
            DEC  BC
            JR   EmitBlock
.endif

.routine in HL out A,carry,zero clobbers sign,parity,halfCarry,B,C,DE,HL
EmitEight:
            LD   B,8
            JR   EmitGo
.routine in HL out A,carry,zero clobbers sign,parity,halfCarry,B,C,DE,HL
EmitFive:
            LD   B,5
            JR   EmitGo
.routine in HL out A,carry,zero clobbers sign,parity,halfCarry,B,C,DE,HL
EmitFour:
            LD   B,4
            JR   EmitGo
.routine in HL out A,carry,zero clobbers sign,parity,halfCarry,B,C,DE,HL
EmitThree:
            LD   B,3
            JR   EmitGo
.routine in HL out A,carry,zero clobbers sign,parity,halfCarry,B,C,DE,HL
EmitPair:
            LD   B,2
.routine in B,HL out A,carry,zero clobbers sign,parity,halfCarry,B,C,DE,HL
EmitGo:
            JR   EmitBytes

; Patch one Z80 relative displacement. DE is the operand and HL the target.
.routine in DE,HL out A,carry,zero clobbers sign,parity,halfCarry,B,C,DE,HL,IX,IY
PatchRelative:
            LD   (EmitPatchAddress),DE
            INC  DE
            OR   A
            SBC  HL,DE
            LD   C,L
            LD   A,C
            ADD  A,A
            SBC  A,A
            CP   H
            JR   NZ,PatchInvalid
PatchStore:
.if TargetStreamingOutput
            LD   B,C
            LD   HL,(EmitPatchAddress)
            LD   A,(TargetOutputBank)
            LD   C,A
            LD   A,B
            CALL TargetSinkPatchByte
            JP   C,TargetOutputFailure
            OR   A
            RET
.else
            LD   DE,(EmitPatchAddress)
            LD   A,C
            LD   (DE),A
            OR   A
            RET
.endif
PatchInvalid:
            CALL SetDiagInline
            .db  DiagnosticFixupRange

.if TargetStreamingOutput
.else
.routine in HL out A,carry,zero clobbers sign,parity,halfCarry,BC,DE,HL
BeginProgram:
            LD   (EmitLimit),HL
            LD   BC,(GeneratedSize)
            LD   (PublishedSize),BC
            LD   A,B
            OR   C
            JR   Z,BeginProgramReady
            LD   HL,GeneratedBase
            LD   DE,BackupBase
            LDIR
BeginProgramReady:
            LD   HL,GeneratedBase
            LD   (EmitCursor),HL
            OR   A
            RET

.routine out A,carry,zero clobbers sign,parity,halfCarry,BC,DE,HL
AbortProgram:
            LD   BC,(PublishedSize)
            LD   A,B
            OR   C
            JR   Z,AbortProgramSize
            LD   HL,BackupBase
            LD   DE,GeneratedBase
            LDIR
AbortProgramSize:
            LD   HL,(PublishedSize)
            LD   (GeneratedSize),HL
            SCF
            RET
.endif

.if AggregateCallSlices
.if TargetStreamingOutput
.else
; Initialize the fixed adapter table, retain all previously published segment
; sizes, and back up both image-bearing segments before tentative emission.
.routine in HL out A,carry,zero clobbers sign,parity,halfCarry,BC,DE,HL,IX,IY
BeginSegmentedProgram:
            PUSH HL
            LD   HL,GeneratedSize
            LD   DE,PublishedSize
            LD   BC,8
            LDIR
            LD   BC,(GeneratedSize)
            LD   HL,GeneratedCodeBase
            LD   DE,BackupBase
            CALL SegmentCopyIfAny
            LD   BC,(GeneratedRoDataSize)
            LD   HL,GeneratedRoDataBase
            LD   DE,BackupBase+(GeneratedRoDataBase-GeneratedBase)
            CALL SegmentCopyIfAny
            LD   HL,SegmentInitialTable
            LD   DE,SegmentTableBase
            LD   BC,SegmentEntrySize*SegmentCapacity
            LDIR
            POP  HL
            LD   (SegmentCodeEntry+SegmentEntryLimit),HL

            CALL ValidateSegmentTable
.if CompilerDiagnosticReturns
            RET  C
.endif
            XOR  A
            RET

SegmentInitialTable:
            .dw GeneratedCodeBase,GeneratedCodeLimit
            .dw GeneratedRoDataBase,GeneratedRoDataLimit
            .dw ProgramDataBase,ProgramDataLimit
            .dw ProgramBssBase,ProgramBssLimit

.routine in BC,DE,HL out A,carry,zero clobbers sign,parity,halfCarry,BC,DE,HL
SegmentCopyIfAny:
            LD   A,B
            OR   C
            RET  Z
            LDIR
            OR   A
            RET

; Only the two image-bearing segments are selectable by the byte emitter. A is
; an internal SegmentCode/SegmentRoData ordinal supplied at the two call sites.
; Their current cursors remain cached in EmitCursor/EmitLimit and are written
; back to the bounded table at each segment switch and at publication.
.routine in A out A,carry,zero clobbers sign,parity,halfCarry,BC,DE,HL,IX,IY
SelectOutputSegment:
            OR   A
            JR   NZ,SelectOutputSegmentRoData
            LD   DE,(EmitCursor)
            LD   (SegmentRoDataCursor),DE
            LD   HL,SegmentCodeEntry
            JR   SelectOutputSegmentReady
SelectOutputSegmentRoData:
            LD   HL,SegmentRoDataEntry
SelectOutputSegmentReady:
            LD   E,(HL)
            INC  HL
            LD   D,(HL)
            LD   (EmitCursor),DE
            INC  HL
            LD   E,(HL)
            INC  HL
            LD   D,(HL)
            LD   (EmitLimit),DE
            OR   A
            RET

; The adapter owns two ordered ROM-image segments and two ordered RAM
; segments. Reject malformed or overlapping target maps before one byte can
; be published.
.routine out A,carry,zero clobbers sign,parity,halfCarry,BC,DE,HL,IX,IY
ValidateSegmentTable:
            LD   IX,SegmentTableBase
            LD   B,SegmentCapacity
ValidateSegmentEntryLoop:
            LD   L,(IX+SegmentEntryBase)
            LD   H,(IX+SegmentEntryBase+1)
            LD   E,(IX+SegmentEntryLimit)
            LD   D,(IX+SegmentEntryLimit+1)
            OR   A
            SBC  HL,DE
            JR   NC,SegmentTableFailure
            LD   DE,SegmentEntrySize
            ADD  IX,DE
            DJNZ ValidateSegmentEntryLoop
            LD   HL,(SegmentCodeEntry+SegmentEntryLimit)
            LD   DE,(SegmentRoDataEntry+SegmentEntryBase)
            CALL SegmentRequireOrder
.if CompilerDiagnosticReturns
            RET  C
.endif
            LD   HL,(SegmentDataEntry+SegmentEntryLimit)
            LD   DE,(SegmentBssEntry+SegmentEntryBase)
.routine in DE,HL out A,carry,zero clobbers sign,parity,halfCarry,BC,DE,HL,IX,IY
SegmentRequireOrder:
            OR   A
            SBC  HL,DE
            JR   C,SegmentOrderReady
            RET  Z
            JR   SegmentTableFailure
SegmentOrderReady:
            OR   A
            RET
SegmentTableFailure:
            CALL SetDiagInline
            .db  DiagnosticOutputSegment

.routine out A,carry,zero clobbers sign,parity,halfCarry,BC,DE,HL
AbortSegmentedProgram:
            LD   BC,(PublishedSize)
            LD   HL,BackupBase
            LD   DE,GeneratedCodeBase
            CALL SegmentCopyIfAny
            LD   BC,(PublishedRoDataSize)
            LD   HL,BackupBase+(GeneratedRoDataBase-GeneratedBase)
            LD   DE,GeneratedRoDataBase
            CALL SegmentCopyIfAny
            LD   HL,PublishedSize
            LD   DE,GeneratedSize
            LD   BC,8
            LDIR
            SCF
            RET

.routine out A,carry,zero clobbers sign,parity,halfCarry,DE,HL
FinishSegmentedProgram:
            LD   HL,(EmitCursor)
            LD   DE,GeneratedCodeBase
            OR   A
            SBC  HL,DE
            LD   (GeneratedSize),HL
            LD   HL,(SegmentRoDataCursor)
            LD   DE,GeneratedRoDataBase
            OR   A
            SBC  HL,DE
            LD   (GeneratedRoDataSize),HL
            LD   HL,(StaticImageLength)
            LD   (GeneratedDataSize),HL
            LD   HL,(ProgramBssLength)
            LD   (GeneratedBssSize),HL
            OR   A
            RET
.endif
.endif

.if LegacyEncoders
.routine out A,carry,zero clobbers sign,parity,halfCarry,BC,DE,HL,IX,IY
EncodeLoopProgram:
            CALL EncodeLoopProgramBody
            JR   EncodeProgramResult
.routine out A,carry,zero clobbers sign,parity,halfCarry,BC,DE,HL,IX,IY
EncodeCallProgram:
            CALL EncodeCallProgramBody
            JR   EncodeProgramResult
.routine out A,carry,zero clobbers sign,parity,halfCarry,BC,DE,HL,IX,IY
EncodeExpressionProgram:
            CALL EncodeExpressionProgramBody
            JR   EncodeProgramResult
.routine out A,carry,zero clobbers sign,parity,halfCarry,BC,DE,HL,IX,IY
EncodeArrayProgram:
            LD   HL,GeneratedLimit
            JR   EncodeArrayProgramWithinLimit
.routine in HL out A,carry,zero clobbers sign,parity,halfCarry,BC,DE,HL,IX,IY
EncodeArrayProgramWithinLimit:
            CALL EncodeArrayProgramBody
EncodeProgramResult:
            RET  NC
            JP   AbortProgram

.routine out A,carry,zero clobbers sign,parity,halfCarry,BC,DE,HL,IX,IY
EncodeLoopProgramBody:
            LD   HL,GeneratedLimit
            CALL BeginProgram

            LD   A,(SemanticBufferBase+2)
            CALL EmitLoadDImmediate
.if CompilerDiagnosticReturns
            RET  C
.endif
            LD   A,(SemanticBufferBase+4)
            CALL EmitLoadDImmediate
.if CompilerDiagnosticReturns
            RET  C
.endif

            LD   HL,(EmitCursor)
            LD   (EmitLoopHead),HL
            CALL EmitByteInlineChecked
            .db  $7A
.if CompilerDiagnosticReturns
            RET  C
.endif
            LD   A,(SemanticBufferBase+5)
            CALL EmitCompareImmediate
.if CompilerDiagnosticReturns
            RET  C
.endif
            CALL EmitJrNcPlaceholder
.if CompilerDiagnosticReturns
            RET  C
.endif
            LD   (EmitExitFixup),DE

            LD   A,(SemanticBufferBase+7)
            CALL EmitLoadAImmediate
.if CompilerDiagnosticReturns
            RET  C
.endif
            LD   HL,WriteOutputByte
            CALL EmitCall
.if CompilerDiagnosticReturns
            RET  C
.endif
            LD   A,$38
            CALL EmitRelativePlaceholder
.if CompilerDiagnosticReturns
            RET  C
.endif
            LD   (EmitFailureFixup),DE
            CALL EmitByteInlineChecked
            .db  $7A
.if CompilerDiagnosticReturns
            RET  C
.endif
            LD   A,(SemanticBufferBase+5)
            DEC  A
            CALL EmitCompareImmediate
.if CompilerDiagnosticReturns
            RET  C
.endif
            CALL EmitJrNcPlaceholder
.if CompilerDiagnosticReturns
            RET  C
.endif
            LD   (EmitUpdateExitFixup),DE
            CALL EmitByteInlineChecked
            .db  $14
.if CompilerDiagnosticReturns
            RET  C
.endif
            CALL EmitJrPlaceholder
.if CompilerDiagnosticReturns
            RET  C
.endif
            LD   HL,(EmitLoopHead)
            CALL PatchRelative
.if CompilerDiagnosticReturns
            RET  C
.endif

            LD   DE,(EmitExitFixup)
            CALL PatchHere
.if CompilerDiagnosticReturns
            RET  C
.endif
            LD   DE,(EmitUpdateExitFixup)
            CALL PatchHere
.if CompilerDiagnosticReturns
            RET  C
.endif
            CALL EmitSuccessReturn
.if CompilerDiagnosticReturns
            RET  C
.endif

            LD   DE,(EmitFailureFixup)
            CALL PatchHere
.if CompilerDiagnosticReturns
            RET  C
.endif
            LD   HL,LoopFailureOffset
            CALL EmitLoadHl
.if CompilerDiagnosticReturns
            RET  C
.endif
            CALL EmitUnhandledTrapPrefix
.if CompilerDiagnosticReturns
            RET  C
.endif
            CALL EmitTrapEnding
.if CompilerDiagnosticReturns
            RET  C
.endif

            JP   FinishProgram
.endif

; Small instruction emitters shared by the direct back end. Multiple entry
; points share the opcode-plus-operand tails rather than repeating them in
; every semantic operation.
.routine in A,HL out A,carry,zero clobbers sign,parity,halfCarry,B,C,DE,HL
EmitOpcodeWord:
            PUSH HL
            CALL EmitByte
            POP  HL
.if CompilerDiagnosticReturns
            RET  C
.endif
.if TargetStreamingOutput
            JR   EmitWord
.else
            JP   EmitWord
.endif

.routine in HL out A,carry,zero clobbers sign,parity,halfCarry,B,C,DE,HL
EmitCall:
            LD   A,$CD
            JR   EmitOpcodeWord

.routine in HL out A,carry,zero clobbers sign,parity,halfCarry,B,C,DE,HL
EmitLoadHl:
            LD   A,$21
            JR   EmitOpcodeWord

.routine in HL out A,carry,zero clobbers sign,parity,halfCarry,B,C,DE,HL
EmitLoadBcImmediate:
            LD   A,$01
            JR   EmitOpcodeWord

.routine in HL out A,carry,zero clobbers sign,parity,halfCarry,B,C,DE,HL
EmitStoreA:
            LD   A,$32
            JR   EmitOpcodeWord

.if TargetStreamingOutput
; Emit LD (state-base+DE),A through the target-linked writable-state address.
.routine in DE out A,carry,zero clobbers sign,parity,halfCarry,B,C,DE,HL
EmitStoreTargetStateA:
            CALL TargetStateAddress
            JR   EmitStoreA
.endif

.routine in A,C out A,carry,zero clobbers sign,parity,halfCarry,B,DE,HL
EmitOpcodeByte:
            CALL EmitByte
.if CompilerDiagnosticReturns
            RET  C
.endif
            LD   A,C
            JP   EmitByte

.routine in A out A,carry,zero clobbers sign,parity,halfCarry,B,C,DE,HL
EmitLoadAImmediate:
            LD   C,A
            LD   A,$3E
            JR   EmitOpcodeByte

.if LegacyEncoders
.routine in A out A,carry,zero clobbers sign,parity,halfCarry,B,C,DE,HL
EmitLoadDImmediate:
            LD   C,A
            LD   A,$16
            JP   EmitOpcodeByte

.routine in A out A,carry,zero clobbers sign,parity,halfCarry,B,C,DE,HL
EmitCompareImmediate:
            LD   C,A
            LD   A,$FE
            JP   EmitOpcodeByte
.endif

.if LegacyEncoders
.routine out A,carry,zero clobbers sign,parity,halfCarry,B,C,DE,HL
EmitLoadScalar:
            LD   HL,ScalarSlot
            LD   A,$3A
            JP   EmitOpcodeWord

.routine out A,carry,zero clobbers sign,parity,halfCarry,B,C,DE,HL
EmitRestoreAfterCall:
            CALL EmitByteInlineChecked
            .db  $F5
.if CompilerDiagnosticReturns
            RET  C
.endif
            LD   HL,ActivationPop
            CALL EmitCall
.if CompilerDiagnosticReturns
            RET  C
.endif
            LD   A,$F1
            JP   EmitByte
.endif

.routine out A,carry,zero clobbers sign,parity,halfCarry,B,C,DE,HL
EmitSuccessReturn:
            LD   A,RunSucceeded
            JR   EmitRunEnding

; At runtime A carries the trap number and HL carries the source offset.
.routine out A,carry,zero clobbers sign,parity,halfCarry,B,C,DE,HL
EmitTrapEnding:
.if TargetStreamingOutput
            LD   DE,TrapNumber-StateBase
            CALL EmitStoreTargetStateA
.else
            LD   HL,TrapNumber
            CALL EmitStoreA
.endif
.if CompilerDiagnosticReturns
            RET  C
.endif
            CALL EmitByteInlineChecked
            .db  $AF
.if CompilerDiagnosticReturns
            RET  C
.endif
.if TargetStreamingOutput
            LD   DE,TrapRoutine-StateBase
            CALL EmitStoreTargetStateA
.else
            LD   HL,TrapRoutine
            CALL EmitStoreA
.endif
.if CompilerDiagnosticReturns
            RET  C
.endif
.if TargetStreamingOutput
            LD   DE,TrapOffset-StateBase
            CALL TargetStateAddress
.else
            LD   HL,TrapOffset
.endif
            LD   A,$22
            CALL EmitOpcodeWord
.if CompilerDiagnosticReturns
            RET  C
.endif
            LD   A,RunTrapped
.routine in A out A,carry,zero clobbers sign,parity,halfCarry,B,C,DE,HL
EmitRunEnding:
            CALL EmitLoadAImmediate
.if CompilerDiagnosticReturns
            RET  C
.endif
.if TargetStreamingOutput
            LD   DE,RunState-StateBase
            CALL EmitStoreTargetStateA
.else
            LD   HL,RunState
            CALL EmitStoreA
.endif
.if CompilerDiagnosticReturns
            RET  C
.endif
.if TargetStreamingOutput
            LD   A,(TargetDescriptorEntryBankValue)
            LD   D,A
            LD   A,(TargetOutputBank)
            CP   D
            JR   Z,EmitRunEndingLocal
            LD   A,D
            CALL EmitLoadAImmediate
.if CompilerDiagnosticReturns
            RET  C
.endif
            LD   HL,(TargetTerminalAddress)
            CALL EmitLoadHl
.if CompilerDiagnosticReturns
            RET  C
.endif
            LD   A,10                     ; far-jump vector ordinal
            JP   EmitTargetVectorJump
EmitRunEndingLocal:
            LD   HL,(TargetTerminalAddress)
            LD   A,$C3
            JR   EmitOpcodeWord
.else
            LD   A,$C9
            JP   EmitByte
.endif

; At runtime A carries an unhandled error and HL the failing source offset.
.routine out A,carry,zero clobbers sign,parity,halfCarry,B,C,DE,HL
EmitUnhandledTrapPrefix:
.if TargetStreamingOutput
            LD   DE,TrapError-StateBase
            CALL EmitStoreTargetStateA
.else
            LD   HL,TrapError
            CALL EmitStoreA
.endif
.if CompilerDiagnosticReturns
            RET  C
.endif
            LD   A,6
            JR   EmitLoadAImmediate

.routine out A,carry,zero,DE clobbers sign,parity,halfCarry,B,HL
EmitJrPlaceholder:
            LD   A,$18
            JR   EmitRelativePlaceholder
.routine out A,carry,zero,DE clobbers sign,parity,halfCarry,B,HL
EmitJrNcPlaceholder:
            LD   A,$30
.routine in A out A,carry,zero,DE clobbers sign,parity,halfCarry,B,HL
EmitRelativePlaceholder:
            CALL EmitByte
.if CompilerDiagnosticReturns
            RET  C
.endif
            LD   HL,(EmitCursor)
            PUSH HL
            XOR  A
            CALL EmitByte
            POP  DE
            RET

.if LegacyEncoders
.routine out A,carry,zero,DE clobbers sign,parity,halfCarry,B,HL
EmitJrCPlaceholder:
            LD   A,$38
            JP   EmitRelativePlaceholder
.endif

.routine in DE,HL out A,carry,zero clobbers sign,parity,halfCarry,DE,HL
PatchWord:
.if TargetStreamingOutput
            PUSH BC
            LD   A,(TargetOutputBank)
            LD   C,A
            CALL TargetSinkPatchWord
            POP  BC
            JP   C,TargetOutputFailure
            OR   A
            RET
.else
            LD   A,L
            LD   (DE),A
            INC  DE
            LD   A,H
            LD   (DE),A
            OR   A
            RET
.endif

; Patch a stored displacement to the current output position.
.routine in DE out A,carry,zero clobbers sign,parity,halfCarry,B,C,DE,HL,IX,IY
PatchHere:
            LD   HL,(EmitCursor)
            JP   PatchRelative

.if TargetStreamingOutput
.else
.routine out A,carry,zero clobbers sign,parity,halfCarry,DE,HL
FinishProgram:
            LD   HL,(EmitCursor)
            LD   DE,GeneratedBase
            OR   A
            SBC  HL,DE
            LD   (GeneratedSize),HL
            OR   A
            RET
.endif

; Read one operand from the checked semantic transcript. The operation count
; bounds dispatch; individual handlers know the fixed width of their operands.
CallBackendStart:
.routine out A,carry,zero clobbers sign,parity,halfCarry,HL
NextSemanticByte:
            LD   HL,(SemanticReadCursor)
            LD   A,(HL)
            INC  HL
            LD   (SemanticReadCursor),HL
            OR   A
            RET

.routine out A,DE,carry,zero clobbers sign,parity,halfCarry,HL
ReadSemanticWord:
            CALL NextSemanticByte
            LD   E,A
            CALL NextSemanticByte
            LD   D,A
            RET

; Dense ordinal dispatcher for the first non-positional backend. A pushed
; continuation turns the Z80's JP (HL) into a compact indirect call. This
; entry is post-parse only: SemanticSinkFinish must have published the complete
; transcript before emitter scratch overlays the retained forward signature.
.if LegacyEncoders
.routine out A,carry,zero clobbers sign,parity,halfCarry,B,C,DE,HL,IX,IY
DispatchCallOperations:
            LD   HL,SemanticPayloadBase
            LD   (SemanticReadCursor),HL
            LD   A,(SemanticBufferBase)
            OR   A
            RET  Z
            LD   B,A
DispatchCallNext:
            PUSH BC
            CALL NextSemanticByte
            SUB  SemanticCallLiteralU8
            CP   CallOperationCount
            JR   NC,DispatchCallInvalid
            ADD  A,A
            LD   E,A
            LD   D,0
            LD   HL,CallOperationTable
            ADD  HL,DE
            LD   E,(HL)
            INC  HL
            LD   D,(HL)
            EX   DE,HL
            LD   DE,DispatchCallReturn
            PUSH DE
            JP   (HL)
DispatchCallReturn:
            POP  BC
.if CompilerDiagnosticReturns
            RET  C
.endif
            DJNZ DispatchCallNext
            OR   A
            RET
DispatchCallInvalid:
            POP  BC
            CALL SetDiagInline
            .db  DiagnosticSinkCapacity

CallOperationTable:
            .dw CallLiteral
            .dw CallWriteLocal
            .dw CallBeginForward
            .dw CallIfParameterZero
            .dw CallReturnParameter
            .dw CallEndIf
            .dw CallReturnSelfMinus
            .dw CallEndRoutine
CallOperationCount .equ 8

.routine out A,carry,zero clobbers sign,parity,halfCarry,B,C,DE,HL,IX,IY
CallLiteral:
            CALL NextSemanticByte
            CALL NextSemanticByte
            CALL EmitLoadAImmediate
.if CompilerDiagnosticReturns
            RET  C
.endif
            LD   HL,ActivationPush
            CALL EmitCall
.if CompilerDiagnosticReturns
            RET  C
.endif
            CALL EmitJrCPlaceholder
.if CompilerDiagnosticReturns
            RET  C
.endif
            LD   (EmitExitFixup),DE
            CALL EmitByteInlineChecked
            .db  $CD
.if CompilerDiagnosticReturns
            RET  C
.endif
            LD   HL,(EmitCursor)
            LD   (EmitRoutineCallFixup),HL
            LD   HL,0
            CALL EmitWord
.if CompilerDiagnosticReturns
            RET  C
.endif
            CALL EmitRestoreAfterCall
.if CompilerDiagnosticReturns
            RET  C
.endif
            LD   DE,(EmitExitFixup)
            CALL PatchHere
.if CompilerDiagnosticReturns
            RET  C
.endif
            CALL EmitJrCPlaceholder
.if CompilerDiagnosticReturns
            RET  C
.endif
            LD   (EmitUpdateExitFixup),DE
            RET

.routine out A,carry,zero clobbers sign,parity,halfCarry,B,C,DE,HL
CallWriteLocal:
            LD   HL,WriteOutputByte
            CALL EmitCall
.if CompilerDiagnosticReturns
            RET  C
.endif
            CALL EmitJrCPlaceholder
.if CompilerDiagnosticReturns
            RET  C
.endif
            LD   (EmitFailureFixup),DE
            RET

.routine out A,carry,zero clobbers sign,parity,halfCarry,B,C,DE,HL
CallBeginForward:
            CALL NextSemanticByte
            LD   HL,(EmitCursor)
            LD   (EmitRoutineAddress),HL
            LD   DE,(EmitRoutineCallFixup)
            JP   PatchWord

.routine out A,carry,zero clobbers sign,parity,halfCarry,B,C,DE,HL
CallIfParameterZero:
            CALL NextSemanticByte
            CALL EmitLoadScalar
.if CompilerDiagnosticReturns
            RET  C
.endif
            CALL EmitByteInlineChecked
            .db  $B7
.if CompilerDiagnosticReturns
            RET  C
.endif
            LD   A,$20
            CALL EmitRelativePlaceholder
.if CompilerDiagnosticReturns
            RET  C
.endif
            LD   (EmitIfFixup),DE
            RET

.routine out A,carry,zero clobbers sign,parity,halfCarry,B,C,DE,HL
CallReturnParameter:
            CALL EmitLoadScalar
.if CompilerDiagnosticReturns
            RET  C
.endif
            LD   A,$C9
            JP   EmitByte

.routine out A,carry,zero clobbers sign,parity,halfCarry,B,C,DE,HL,IX,IY
CallEndIf:
            LD   DE,(EmitIfFixup)
            JP   PatchHere

.routine out A,carry,zero clobbers sign,parity,halfCarry,B,C,DE,HL
CallReturnSelfMinus:
            CALL NextSemanticByte
            CALL NextSemanticByte
            LD   C,A
            PUSH BC
            CALL EmitLoadScalar
            POP  BC
.if CompilerDiagnosticReturns
            RET  C
.endif
            LD   A,$D6
            CALL EmitOpcodeByte
.if CompilerDiagnosticReturns
            RET  C
.endif
            LD   HL,ActivationPush
            CALL EmitCall
.if CompilerDiagnosticReturns
            RET  C
.endif
            CALL EmitByteInlineChecked
            .db  $D8
.if CompilerDiagnosticReturns
            RET  C
.endif
            LD   HL,(EmitRoutineAddress)
            CALL EmitCall
.if CompilerDiagnosticReturns
            RET  C
.endif
            CALL EmitRestoreAfterCall
.if CompilerDiagnosticReturns
            RET  C
.endif
            LD   A,$C9
            JP   EmitByte

.routine out A,carry,zero clobbers sign,parity,halfCarry,B,C,DE,HL,IX,IY
CallEndRoutine:
            LD   HL,(EmitRoutineAddress)
            LD   A,H
            OR   L
            RET  NZ
            CALL EmitSuccessReturn
.if CompilerDiagnosticReturns
            RET  C
.endif
            LD   DE,(EmitUpdateExitFixup)
            CALL PatchHere
.if CompilerDiagnosticReturns
            RET  C
.endif
            LD   HL,CallCapacityOffset
            CALL EmitLoadHl
.if CompilerDiagnosticReturns
            RET  C
.endif
            CALL EmitTrapEnding
.if CompilerDiagnosticReturns
            RET  C
.endif
            LD   DE,(EmitFailureFixup)
            CALL PatchHere
.if CompilerDiagnosticReturns
            RET  C
.endif
            LD   HL,CallFailureOffset
            CALL EmitLoadHl
.if CompilerDiagnosticReturns
            RET  C
.endif
            CALL EmitUnhandledTrapPrefix
.if CompilerDiagnosticReturns
            RET  C
.endif
            JP   EmitTrapEnding

; Compile the routine slice from its variable-width semantic stream.
.routine out A,carry,zero clobbers sign,parity,halfCarry,BC,DE,HL,IX,IY
EncodeCallProgramBody:
            LD   HL,GeneratedLimit
            CALL BeginProgram
            LD   HL,0
            LD   (EmitRoutineAddress),HL
            CALL DispatchCallOperations
.if CompilerDiagnosticReturns
            RET  C
.endif
            JP   FinishProgram
CallBackendEnd:
.endif

; Dense postfix-expression backend. Program data follows an initial JP, so its
; address is known before the code entry is patched. Scalar locals use an IX
; frame and therefore remain per activation; the evaluation stack lies below
; that frame and is empty at every statement boundary.
.if LegacyEncoders
ExpressionBackendStart:
.routine out A,carry,zero clobbers sign,parity,halfCarry,B,C,DE,HL,IX,IY
DispatchExpressionOperations:
            LD   HL,SemanticPayloadBase
            LD   (SemanticReadCursor),HL
            LD   A,(SemanticBufferBase)
            OR   A
            RET  Z
            LD   B,A
DispatchExpressionNext:
            PUSH BC
            CALL NextSemanticByte
            SUB  SemanticDefineProgramU8
            CP   ExpressionOperationCount
            JR   NC,DispatchExpressionInvalid
            ADD  A,A
            LD   E,A
            LD   D,0
            LD   HL,ExpressionOperationTable
            ADD  HL,DE
            LD   E,(HL)
            INC  HL
            LD   D,(HL)
            EX   DE,HL
            LD   DE,DispatchExpressionReturn
            PUSH DE
            JP   (HL)
DispatchExpressionReturn:
            POP  BC
.if CompilerDiagnosticReturns
            RET  C
.endif
            DJNZ DispatchExpressionNext
            OR   A
            RET
DispatchExpressionInvalid:
            POP  BC
            CALL SetDiagInline
            .db  DiagnosticSinkCapacity

ExpressionOperationTable:
            .dw ExpressionDefineProgram
            .dw ExpressionBeginMain
            .dw ExpressionDeclareLocal
            .dw ExpressionLiteral
            .dw ExpressionLoadProgram
            .dw ExpressionLoadLocal
            .dw ExpressionMultiply
            .dw ExpressionAdd
            .dw ExpressionStoreProgram
            .dw ExpressionStoreLocal
            .dw ExpressionWrite
            .dw ExpressionEndMain
ExpressionOperationCount .equ 12
.endif

.routine out A,HL,carry,zero clobbers sign,parity,halfCarry,B,C,D,E,IX,IY
ExpressionProgramAddress:
.if AggregateCallSlices
            CALL ReadSemanticWord
.if TargetStreamingOutput
            BIT  7,D
            JR   Z,ExpressionTargetDataAddress
            RES  7,D
            LD   HL,(TargetBssBase)
            JR   ExpressionTargetAddressReady
ExpressionTargetDataAddress:
            LD   HL,(TargetContextDataBase)
ExpressionTargetAddressReady:
            ADD  HL,DE
            OR   A
            RET
.else
            LD   H,D
            LD   L,E
            OR   A
            RET
.endif
.else
            CALL NextSemanticByte
            LD   E,A
            LD   D,0
            LD   HL,GeneratedBase+3
            ADD  HL,DE
            RET
.endif

.if LegacyEncoders
.routine out A,carry,zero clobbers sign,parity,halfCarry,B,DE,HL
ExpressionDefineProgram:
            CALL NextSemanticByte
            CALL NextSemanticByte
            JP   EmitByte

.routine out A,carry,zero clobbers sign,parity,halfCarry,B,C,DE,HL
ExpressionBeginMain:
            LD   DE,(EmitDataFixup)
            LD   HL,(EmitCursor)
            CALL PatchWord
            LD   HL,ExpressionFrameBytes
            JP   EmitEight

.routine out A,carry,zero clobbers sign,parity,halfCarry,B,DE,HL
ExpressionDeclareLocal:
            CALL NextSemanticByte
            LD   A,$3B
            JP   EmitByte

.routine out A,carry,zero clobbers sign,parity,halfCarry,B,C,DE,HL
ExpressionLiteral:
            CALL NextSemanticByte
            CALL EmitLoadAImmediate
.if CompilerDiagnosticReturns
            RET  C
.endif
.routine out A,carry,zero clobbers sign,parity,halfCarry,B,DE,HL
ExpressionPushA:
            LD   A,$F5
            JP   EmitByte

.routine out A,carry,zero clobbers sign,parity,halfCarry,B,C,D,DE,HL
ExpressionLoadProgram:
            CALL NextSemanticByte
            CALL ExpressionProgramAddress
            LD   A,$3A
            CALL EmitOpcodeWord
.if CompilerDiagnosticReturns
            RET  C
.endif
            JP   ExpressionPushA

.routine out A,carry,zero clobbers sign,parity,halfCarry,B,C,DE,HL
ExpressionLoadLocal:
            CALL NextSemanticByte
            CPL
            LD   C,A
            CALL EmitByteInlineChecked
            .db  $DD
.if CompilerDiagnosticReturns
            RET  C
.endif
            LD   A,$7E
            CALL EmitOpcodeByte
.if CompilerDiagnosticReturns
            RET  C
.endif
            JP   ExpressionPushA

.routine out A,carry,zero clobbers sign,parity,halfCarry,B,C,DE,HL
ExpressionMultiply:
            CALL EmitByteInlineChecked
            .db  $C1
.if CompilerDiagnosticReturns
            RET  C
.endif
            CALL EmitByteInlineChecked
            .db  $F1
.if CompilerDiagnosticReturns
            RET  C
.endif
            LD   HL,MultiplyU8
            CALL EmitCall
.if CompilerDiagnosticReturns
            RET  C
.endif
            LD   A,$F5
            JP   EmitByte

.routine out A,carry,zero clobbers sign,parity,halfCarry,B,DE,HL
ExpressionAdd:
            LD   HL,ExpressionAddBytes
            JP   EmitFour

.routine out A,carry,zero clobbers sign,parity,halfCarry,B,C,D,DE,HL
ExpressionStoreProgram:
            CALL NextSemanticByte
            CALL ExpressionProgramAddress
            PUSH HL
            LD   A,$F1
            CALL EmitByte
            POP  HL
.if CompilerDiagnosticReturns
            RET  C
.endif
            LD   A,$32
            JP   EmitOpcodeWord

.routine out A,carry,zero clobbers sign,parity,halfCarry,B,C,DE,HL
ExpressionStoreLocal:
            CALL NextSemanticByte
            CPL
            LD   C,A
            CALL EmitByteInlineChecked
            .db  $F1
.if CompilerDiagnosticReturns
            RET  C
.endif
            CALL EmitByteInlineChecked
            .db  $DD
.if CompilerDiagnosticReturns
            RET  C
.endif
            LD   A,$77
            JP   EmitOpcodeByte

.routine out A,carry,zero clobbers sign,parity,halfCarry,B,C,DE,HL
ExpressionWrite:
            CALL NextSemanticByte
            LD   C,A
            CALL NextSemanticByte
            LD   H,A
            LD   L,C
            LD   (EmitLoopHead),HL
            CALL EmitByteInlineChecked
            .db  $F1
.if CompilerDiagnosticReturns
            RET  C
.endif
            LD   HL,WriteOutputByte
            CALL EmitCall
.if CompilerDiagnosticReturns
            RET  C
.endif
            CALL EmitJrCPlaceholder
.if CompilerDiagnosticReturns
            RET  C
.endif
            LD   (EmitFailureFixup),DE
            RET
.endif

.routine out A,carry,zero clobbers sign,parity,halfCarry,B,DE,HL
ExpressionRestoreFrame:
            LD   HL,ExpressionRestoreBytes
            JP   EmitFour

.if LegacyEncoders
.routine out A,carry,zero clobbers sign,parity,halfCarry,B,C,DE,HL
ExpressionEndMain:
            CALL ExpressionRestoreFrame
.if CompilerDiagnosticReturns
            RET  C
.endif
            CALL EmitSuccessReturn
.if CompilerDiagnosticReturns
            RET  C
.endif
            LD   DE,(EmitFailureFixup)
            CALL PatchHere
.if CompilerDiagnosticReturns
            RET  C
.endif
            CALL ExpressionRestoreFrame
.if CompilerDiagnosticReturns
            RET  C
.endif
            LD   HL,(EmitLoopHead)
            CALL EmitLoadHl
.if CompilerDiagnosticReturns
            RET  C
.endif
            CALL EmitUnhandledTrapPrefix
.if CompilerDiagnosticReturns
            RET  C
.endif
            JP   EmitTrapEnding

.routine out A,carry,zero clobbers sign,parity,halfCarry,BC,DE,HL,IX,IY
EncodeExpressionProgramBody:
            LD   HL,GeneratedLimit
            CALL BeginProgram
            CALL EmitByteInlineChecked
            .db  $C3
.if CompilerDiagnosticReturns
            RET  C
.endif
            LD   HL,(EmitCursor)
            LD   (EmitDataFixup),HL
            LD   HL,0
            CALL EmitWord
.if CompilerDiagnosticReturns
            RET  C
.endif
            CALL DispatchExpressionOperations
.if CompilerDiagnosticReturns
            RET  C
.endif
            JP   FinishProgram
.endif
ExpressionFrameBytes:
            .db $DD,$E5,$DD,$21,$00,$00,$DD,$39
.if LegacyEncoders
ExpressionAddBytes:
            .db $C1,$F1,$80,$F5
.endif
ExpressionRestoreBytes:
            .db $DD,$F9,$DD,$E1
.if LegacyEncoders
ExpressionBackendEnd:

; Default entry and proof-only bounded entry for the checked-array program.
.routine in HL out A,carry,zero clobbers sign,parity,halfCarry,BC,DE,HL,IX,IY
EncodeArrayProgramBody:
            CALL BeginProgram

            LD   HL,ReadInputByte
            CALL EmitCall
.if CompilerDiagnosticReturns
            RET  C
.endif
            CALL EmitJrNcPlaceholder
.if CompilerDiagnosticReturns
            RET  C
.endif
            LD   (EmitExitFixup),DE
            LD   HL,ArrayInputFailureOffset
            CALL EmitLoadHl
.if CompilerDiagnosticReturns
            RET  C
.endif
            CALL EmitJrPlaceholder
.if CompilerDiagnosticReturns
            RET  C
.endif
            LD   (EmitFailureFixup),DE

            LD   DE,(EmitExitFixup)
            CALL PatchHere
.if CompilerDiagnosticReturns
            RET  C
.endif
            LD   A,(SemanticBufferBase+2)
            CALL EmitCompareImmediate
.if CompilerDiagnosticReturns
            RET  C
.endif
            CALL EmitJrNcPlaceholder
.if CompilerDiagnosticReturns
            RET  C
.endif
            LD   (EmitUpdateExitFixup),DE
            CALL EmitByteInlineChecked
            .db  $5F
.if CompilerDiagnosticReturns
            RET  C
.endif
            XOR  A
            CALL EmitLoadDImmediate
.if CompilerDiagnosticReturns
            RET  C
.endif
            CALL EmitByteInlineChecked
            .db  $21
.if CompilerDiagnosticReturns
            RET  C
.endif
            LD   HL,(EmitCursor)
            LD   (EmitDataFixup),HL
            LD   HL,0
            CALL EmitWord
.if CompilerDiagnosticReturns
            RET  C
.endif
            CALL EmitByteInlineChecked
            .db  $19
.if CompilerDiagnosticReturns
            RET  C
.endif
            CALL EmitByteInlineChecked
            .db  $7E
.if CompilerDiagnosticReturns
            RET  C
.endif
            LD   HL,WriteOutputByte
            CALL EmitCall
.if CompilerDiagnosticReturns
            RET  C
.endif
            CALL EmitJrNcPlaceholder
.if CompilerDiagnosticReturns
            RET  C
.endif
            LD   (EmitLoopHead),DE
            LD   HL,ArrayOutputFailureOffset
            CALL EmitLoadHl
.if CompilerDiagnosticReturns
            RET  C
.endif
            CALL EmitJrPlaceholder
.if CompilerDiagnosticReturns
            RET  C
.endif
            LD   (EmitCodeStart),DE

            LD   DE,(EmitLoopHead)
            CALL PatchHere
.if CompilerDiagnosticReturns
            RET  C
.endif
            CALL EmitSuccessReturn
.if CompilerDiagnosticReturns
            RET  C
.endif

            LD   DE,(EmitUpdateExitFixup)
            CALL PatchHere
.if CompilerDiagnosticReturns
            RET  C
.endif
            LD   HL,ArrayBoundsOffset
            CALL EmitLoadHl
.if CompilerDiagnosticReturns
            RET  C
.endif
            CALL EmitByteInlineChecked
            .db  $AF
.if CompilerDiagnosticReturns
            RET  C
.endif
            LD   HL,TrapError
            CALL EmitStoreA
.if CompilerDiagnosticReturns
            RET  C
.endif
            LD   A,1
            CALL EmitLoadAImmediate
.if CompilerDiagnosticReturns
            RET  C
.endif
            CALL EmitJrPlaceholder
.if CompilerDiagnosticReturns
            RET  C
.endif
            LD   (EmitExitFixup),DE

            LD   DE,(EmitFailureFixup)
            CALL PatchHere
.if CompilerDiagnosticReturns
            RET  C
.endif
            LD   DE,(EmitCodeStart)
            CALL PatchHere
.if CompilerDiagnosticReturns
            RET  C
.endif
            CALL EmitUnhandledTrapPrefix
.if CompilerDiagnosticReturns
            RET  C
.endif
            LD   DE,(EmitExitFixup)
            CALL PatchHere
.if CompilerDiagnosticReturns
            RET  C
.endif
            CALL EmitTrapEnding
.if CompilerDiagnosticReturns
            RET  C
.endif

            LD   HL,(EmitCursor)
            LD   DE,(EmitDataFixup)
            CALL PatchWord
            LD   HL,SemanticBufferBase+3
            LD   C,4
EmitArrayData:
            LD   A,(HL)
            PUSH HL
            CALL EmitByte
            POP  HL
.if CompilerDiagnosticReturns
            RET  C
.endif
            INC  HL
            DEC  C
            JR   NZ,EmitArrayData
            JP   FinishProgram
.endif
