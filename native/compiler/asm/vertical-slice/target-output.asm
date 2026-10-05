; Flat append-only target output. The operating adapter owns NOBJ framing,
; service destinations, image fill, CRC, and the two sequential spools.

; Emit entry opcode A followed by one retained zero-word fixup operand.
.routine in A out A,carry,zero clobbers sign,parity,halfCarry,B,C,DE,HL
TargetEmitEntryPlaceholder:
            CALL EmitByte
.if CompilerDiagnosticReturns
            RET  C
.endif
            LD   HL,(EmitCursor)
            LD   (EmitDataFixup),HL
            LD   HL,0
            JP   EmitWord

; Emit one terminal-state byte comparison. DE selects the runtime-state byte
; and C supplies the expected value.
.routine in C,DE out A,carry,zero clobbers sign,parity,halfCarry,B,C,DE,HL
TargetEmitTerminalTest:
            PUSH BC
            CALL TargetStateAddress
            LD   A,$3A                    ; LD A,(nn)
            CALL EmitOpcodeWord
            POP  BC
.if CompilerDiagnosticReturns
            RET  C
.endif
            LD   A,$FE                    ; CP n
            CALL EmitOpcodeByte
.if CompilerDiagnosticReturns
            RET  C
.endif
            LD   HL,TargetTerminalSelectBytes
            JP   EmitPair

; IX points at the stable compact descriptor supplied by the adapter.
.routine in IX out A,carry,zero clobbers sign,parity,halfCarry,BC,DE,HL,IX,IY
BeginTargetFlatProgram:
            LD   A,TargetOutputClosed
            LD   (TargetOutputBank),A
            LD   L,(IX+TargetDescriptorRuntimeIdentity)
            LD   H,(IX+TargetDescriptorRuntimeIdentity+1)
            LD   DE,NucleusRuntimeIdentity
            OR   A
            SBC  HL,DE
            JP   NZ,TargetConfigurationFailure
            LD   A,(IX+TargetDescriptorFlags)
            CP   TargetDescriptorEstablishStack+1
            JP   NC,TargetConfigurationFailure
            LD   (TargetStackMode),A
            LD   L,(IX+TargetDescriptorImageBase)
            LD   H,(IX+TargetDescriptorImageBase+1)
            LD   (TargetImageBase),HL
            LD   E,(IX+TargetDescriptorImageCapacity)
            LD   D,(IX+TargetDescriptorImageCapacity+1)
            LD   (TargetImageCapacity),DE
            CALL TargetValidateRegion
.if CompilerDiagnosticReturns
            RET  C
.endif
            LD   L,(IX+TargetDescriptorWritableBase)
            LD   H,(IX+TargetDescriptorWritableBase+1)
            LD   (TargetWritableBase),HL
            LD   E,(IX+TargetDescriptorWritableCapacity)
            LD   D,(IX+TargetDescriptorWritableCapacity+1)
            LD   (TargetWritableCapacity),DE
            CALL TargetValidateRegion
.if CompilerDiagnosticReturns
            RET  C
.endif
            CALL TargetClassifyFlatLayout
.if CompilerDiagnosticReturns
            RET  C
.endif
            ; Determine the exact startup extent and validate the optional
            ; established stack before the adapter opens a generation.
            LD   HL,26                   ; JP/CALL main plus terminal dispatch
            LD   A,(TargetLayoutMode)
            OR   A
            JR   Z,TargetStartupBss
            LD   DE,11                   ; LD HL/DE/BC plus LDIR
            ADD  HL,DE
TargetStartupBss:
            LD   DE,(ProgramBssLength)
            LD   A,D
            OR   E
            JR   Z,TargetStartupStack
            LD   DE,9                    ; LD HL/BC plus CALL InitializeBss
            ADD  HL,DE
TargetStartupStack:
            LD   A,(TargetStackMode)
            OR   A
            JR   Z,TargetStartupReady
            LD   DE,13                   ; save/select SP plus terminal restore
            ADD  HL,DE
            PUSH HL
            CALL TargetInitializedLength
            JR   C,TargetStartupStackFailure
            LD   DE,(ProgramBssLength)
            ADD  HL,DE
            JR   C,TargetStartupStackFailure
            LD   DE,TargetStackRequirement+2
            ADD  HL,DE
            JR   C,TargetStartupStackFailure
            LD   DE,(TargetWritableCapacity)
            OR   A
            SBC  HL,DE
            JR   C,TargetStartupStackFits
            JR   Z,TargetStartupStackFits
TargetStartupStackFailure:
            POP  HL
            JR   TargetCapacityFailure
TargetStartupStackFits:
            POP  HL
TargetStartupReady:
            LD   (TargetStartupLength),HL
            LD   A,(TargetDescriptorBankCountValue)
            CP   1
            JP   NZ,TargetBeginBankedProgram
            LD   HL,(ReadOnlyImageLength)
            LD   A,(TargetLayoutMode)
            OR   A
            JR   Z,TargetFlatReadOnlyReady
            LD   DE,(StaticImageLength)
            ADD  HL,DE
            JR   C,TargetBeginCapacityFailure
            LD   DE,NucleusRuntimeVectorLength+NucleusRuntimeStateLength
            ADD  HL,DE
            JR   C,TargetBeginCapacityFailure
TargetFlatReadOnlyReady:
            LD   (TargetReadOnlyLength),HL
            LD   DE,NucleusRuntimeExpectedLength+3
            ADD  HL,DE
            JR   C,TargetBeginCapacityFailure
            LD   DE,(TargetStartupLength)
            ADD  HL,DE
            JR   C,TargetBeginCapacityFailure
            EX   DE,HL                    ; DE is fixed prefix length
            LD   HL,(TargetImageCapacity)
            OR   A
            SBC  HL,DE
            JR   C,TargetBeginCapacityFailure
            LD   A,H
            OR   L
            JR   Z,TargetBeginCapacityFailure ; at least one code byte is required
            LD   (EmitLimit),HL           ; remaining code capacity after prefix
            LD   HL,(TargetImageBase)
            ADD  HL,DE
            JR   C,TargetBeginCapacityFailure
            LD   (TargetCodeBase),HL
            LD   HL,(EmitLimit)
            LD   (TargetCodeCapacity),HL
            LD   A,(TargetLayoutMode)
            OR   A
            JR   NZ,TargetCodeCapacityReady
            LD   DE,(TargetCodeBase)
            LD   HL,(TargetWritableBase)
            OR   A
            SBC  HL,DE
            JR   C,TargetBeginCapacityFailure
            JR   Z,TargetBeginCapacityFailure
            LD   (TargetCodeCapacity),HL
            JR   TargetCodeCapacityReady
TargetBeginCapacityFailure:
TargetCapacityFailure:
            CALL SetDiagInline
            .db  DiagnosticTargetCapacity
TargetCodeCapacityReady:

            LD   IX,(TargetDescriptorPointer)
            CALL TargetSinkBegin
            JP   C,TargetOutputFailure
            XOR  A
            LD   (TargetOutputBank),A
            LD   HL,(TargetImageBase)
            LD   (EmitCursor),HL
            LD   HL,(TargetImageCapacity)
            LD   (EmitLimit),HL
            LD   A,$C3
            CALL TargetEmitEntryPlaceholder
.if CompilerDiagnosticReturns
            RET  C
.endif

            LD   HL,(EmitCursor)
            LD   (TargetLinkedRuntimeBase),HL
            LD   DE,NucleusRuntimeExpectedLength
            ADD  HL,DE
            JR   C,TargetCapacityFailure
            LD   DE,(TargetStartupLength)
            ADD  HL,DE
            JR   C,TargetCapacityFailure
            LD   (TargetReadOnlyBase),HL
            CALL TargetPrepareRuntimeContext
.if CompilerDiagnosticReturns
            RET  C
.endif
            LD   HL,(TargetLinkedRuntimeBase)
            XOR  A
            CALL TargetEmitRuntimeImage
.if CompilerDiagnosticReturns
            RET  C
.endif
            JP   TargetEmitStartup

; Address one retained output-bank cursor and exact remaining-capacity word.
.routine in A out A,HL,carry,zero clobbers sign,parity,halfCarry,D,DE
TargetBankStateAddress:
            LD   L,A
            LD   H,0
            ADD  HL,HL
            ADD  HL,HL
            LD   DE,TargetBankStateBase
            ADD  HL,DE
            OR   A
            RET

.routine out A,carry,zero clobbers sign,parity,halfCarry,D,DE,HL
TargetSaveOutputBank:
            LD   A,(TargetOutputBank)
            CP   TargetOutputClosed
            RET  Z
            CALL TargetBankStateAddress
            LD   DE,(EmitCursor)
            LD   (HL),E
            INC  HL
            LD   (HL),D
            INC  HL
            LD   DE,(EmitLimit)
            LD   (HL),E
            INC  HL
            LD   (HL),D
            OR   A
            RET

; Select the bank that receives subsequent generated bytes and derive the
; bank-local aggregate-constant bounds carried by generated region checks.
.routine in A out A,carry,zero clobbers sign,parity,halfCarry,B,C,D,DE,HL
TargetSelectOutputBank:
            LD   C,A
            LD   A,(TargetDescriptorBankCountValue)
            DEC  A
            CP   C
            JP   C,TargetConfigurationFailure
            LD   A,(TargetOutputBank)
            CP   C
            RET  Z
            CALL TargetSaveOutputBank
            LD   A,C
            LD   (TargetOutputBank),A
            CALL TargetBankStateAddress
            LD   E,(HL)
            INC  HL
            LD   D,(HL)
            LD   (EmitCursor),DE
            INC  HL
            LD   E,(HL)
            INC  HL
            LD   D,(HL)
            LD   (EmitLimit),DE
            LD   A,(TargetOutputBank)
            CALL TargetBankRoLengthAddress
            LD   C,(HL)
            INC  HL
            LD   B,(HL)
            LD   (TargetCurrentRoCapacity),BC
            LD   HL,(TargetImageBase)
            LD   DE,NucleusRuntimeExpectedLength+3
            ADD  HL,DE
            LD   A,(TargetOutputBank)
            LD   D,A
            LD   A,(TargetDescriptorEntryBankValue)
            CP   D
            JR   NZ,TargetSelectRoBaseReady
            LD   DE,(TargetStartupLength)
            ADD  HL,DE
            LD   DE,NucleusRuntimeVectorLength+NucleusRuntimeStateLength
            ADD  HL,DE
            LD   DE,(StaticImageLength)
            ADD  HL,DE
TargetSelectRoBaseReady:
            LD   (TargetCurrentRoBase),HL
            OR   A
            RET

; Consume DE bytes from the selected bank after one provider operation.
.routine in DE out A,carry,zero clobbers sign,parity,halfCarry,B,C,HL
TargetConsumeExtent:
            LD   HL,(EmitLimit)
            OR   A
            SBC  HL,DE
            JP   C,TargetCapacityFailure
            LD   B,H
            LD   C,L
            LD   HL,(EmitCursor)
            ADD  HL,DE
            JR   NC,TargetConsumeExtentReady
            LD   A,B
            OR   C
            JP   NZ,TargetCapacityFailure
TargetConsumeExtentReady:
            LD   (EmitCursor),HL
            LD   (EmitLimit),BC
            OR   A
            RET

; Ask the context-sensitive provider for one complete resolved runtime and
; consume its identity-fixed extent from the selected bank.
.routine in A,HL out A,carry,zero clobbers sign,parity,halfCarry,BC,DE,HL,IX,IY
TargetEmitRuntimeImage:
            LD   DE,NucleusRuntimeIdentity
            LD   BC,NucleusRuntimeExpectedLength
            LD   IX,TargetRuntimeContext
            CALL TargetSinkRuntimeImage
            LD   DE,NucleusRuntimeExpectedLength
TargetConsumeProviderExtent:
            JP   C,TargetOutputFailure
            JR   TargetConsumeExtent

; Banked output is always ROM. Initialize one retained cursor/capacity pair
; per bank, emit every uniform runtime, the entry-only startup/initial image,
; and then the declaration-ordered aggregate constants before source code.
.routine out A,carry,zero clobbers sign,parity,halfCarry,BC,DE,HL,IX,IY
TargetBeginBankedProgram:
            LD   A,(TargetLayoutMode)
            OR   A
            JP   Z,TargetConfigurationFailure
            LD   HL,(TargetImageBase)
            LD   DE,3
            ADD  HL,DE
            LD   (TargetLinkedRuntimeBase),HL
            LD   HL,0
            LD   (TargetReadOnlyBase),HL
            CALL TargetPrepareRuntimeContext
.if CompilerDiagnosticReturns
            RET  C
.endif
            LD   IX,(TargetDescriptorPointer)
            CALL TargetSinkBegin
            JP   C,TargetOutputFailure
            LD   A,(TargetDescriptorBankCountValue)
            LD   B,A
            LD   HL,TargetBankStateBase
TargetInitializeBankStateLoop:
            LD   DE,(TargetImageBase)
            LD   (HL),E
            INC  HL
            LD   (HL),D
            INC  HL
            LD   DE,(TargetImageCapacity)
            LD   (HL),E
            INC  HL
            LD   (HL),D
            INC  HL
            DJNZ TargetInitializeBankStateLoop
            LD   A,TargetOutputClosed
            LD   (TargetOutputBank),A
            LD   C,0
TargetEmitBankPrefixLoop:
            LD   A,C
            PUSH BC
            CALL TargetSelectOutputBank
            POP  BC
.if CompilerDiagnosticReturns
            RET  C
.endif
            LD   A,(TargetDescriptorEntryBankValue)
            CP   C
            JR   NZ,TargetEmitBankEmptySlot
            LD   A,$C3
            PUSH BC
            CALL TargetEmitEntryPlaceholder
            POP  BC
.if CompilerDiagnosticReturns
            RET  C
.endif
            JR   TargetEmitBankRuntime
TargetEmitBankEmptySlot:
            LD   DE,3
            PUSH BC
            CALL TargetConsumeExtent
            POP  BC
.if CompilerDiagnosticReturns
            RET  C
.endif
TargetEmitBankRuntime:
            PUSH BC
            LD   A,C
            LD   HL,(TargetLinkedRuntimeBase)
            CALL TargetEmitRuntimeImage
            POP  BC
.if CompilerDiagnosticReturns
            RET  C
.endif
            LD   A,(TargetDescriptorEntryBankValue)
            CP   C
            JR   NZ,TargetEmitBankPrefixNext
            LD   HL,(EmitCursor)
            LD   DE,(TargetStartupLength)
            ADD  HL,DE
            JP   C,TargetCapacityFailure
            LD   (TargetReadOnlyBase),HL
            CALL TargetEmitStartup
.if CompilerDiagnosticReturns
            RET  C
.endif
            LD   HL,(EmitCursor)
            CALL TargetEmitRuntimeInitialImage
.if CompilerDiagnosticReturns
            RET  C
.endif
            PUSH BC
            LD   HL,StaticImageBase
            LD   BC,(StaticImageLength)
            CALL EmitBlock
            POP  BC
.if CompilerDiagnosticReturns
            RET  C
.endif
TargetEmitBankPrefixNext:
            LD   A,(TargetOutputBank)
            LD   C,A
            INC  C
            LD   A,(TargetDescriptorBankCountValue)
            CP   C
            JR   NZ,TargetEmitBankPrefixLoop
            JP   TargetEmitBankedAggregateConstants

; HL is a region base and DE a nonzero capacity. Carry reports every wrapped
; end except the legal exact mathematical end $10000.
.routine in DE,HL out A,carry,zero clobbers sign,parity,halfCarry,HL
TargetValidateRegion:
            LD   A,D
            OR   E
            JP   Z,TargetCapacityFailure
            ADD  HL,DE
            JR   NC,TargetRegionReady
            LD   A,H
            OR   L
            JP   NZ,TargetCapacityFailure
TargetRegionReady:
            OR   A
            RET

; Classify two checked nonempty regions without storing an exclusive $10000
; end in a word. Loaded means writable is wholly inside image; ROM means the
; half-open regions are disjoint. Every partial overlap is rejected.
.routine out A,carry,zero clobbers sign,parity,halfCarry,BC,DE,HL
TargetClassifyFlatLayout:
            LD   HL,(TargetWritableBase)
            LD   DE,(TargetImageBase)
            OR   A
            SBC  HL,DE                    ; writable offset from image base
            JR   C,TargetWritableBeforeImage
            LD   DE,(TargetImageCapacity)
            PUSH HL
            OR   A
            SBC  HL,DE
            POP  BC                       ; BC = writable offset
            JR   NC,TargetFlatRomReady    ; starts at or after image end
            LD   HL,(TargetImageCapacity)
            OR   A
            SBC  HL,BC                    ; remaining image capacity
            LD   DE,(TargetWritableCapacity)
            OR   A
            SBC  HL,DE
            JP   C,TargetConfigurationFailure
            XOR  A
            LD   (TargetLayoutMode),A
            RET
TargetWritableBeforeImage:
            LD   HL,(TargetImageBase)
            LD   DE,(TargetWritableBase)
            OR   A
            SBC  HL,DE                    ; distance to image start
            LD   DE,(TargetWritableCapacity)
            OR   A
            SBC  HL,DE
            JP   C,TargetConfigurationFailure
TargetFlatRomReady:
            LD   A,TargetLayoutRom
            LD   (TargetLayoutMode),A
            OR   A
            RET

; Build the compiler-owned portion of the complete operating-layer link
; context. Service destinations are supplied by the adapter at this call.
.routine out A,carry,zero clobbers sign,parity,halfCarry,BC,DE,HL,IX,IY
TargetPrepareRuntimeContext:
            LD   HL,(TargetLinkedRuntimeBase)
            LD   (TargetContextRuntimeBase),HL
            LD   HL,(TargetWritableBase)
            LD   (TargetContextWritableBase),HL
            LD   DE,(TargetWritableCapacity)
            LD   (TargetContextWritableCapacity),DE
            LD   (TargetContextVectorBase),HL
            LD   DE,NucleusRuntimeVectorLength
            ADD  HL,DE
            JR   C,TargetPrepareCapacityFailure
            LD   (TargetContextStateBase),HL
            LD   DE,NucleusRuntimeStateLength
            ADD  HL,DE
            JR   C,TargetPrepareCapacityFailure
            LD   (TargetContextDataBase),HL
            LD   BC,(StaticImageLength)
            LD   DE,(ProgramBssLength)
            LD   H,B
            LD   L,C
            ADD  HL,DE
            JR   C,TargetPrepareCapacityFailure
            LD   (TargetContextDataCapacity),HL
            LD   HL,(TargetContextDataBase)
            LD   DE,(StaticImageLength)
            ADD  HL,DE
            JR   C,TargetPrepareCapacityFailure
            LD   (TargetBssBase),HL
            LD   A,(TargetDescriptorBankCountValue)
            CP   1
            JR   Z,TargetPrepareFlatRoData
            LD   HL,0
            LD   (TargetContextRoDataBase),HL
            LD   (TargetContextRoDataCapacity),HL
            JR   TargetContextRoDataFinished
TargetPrepareFlatRoData:
            LD   HL,(TargetReadOnlyBase)
            LD   A,(TargetLayoutMode)
            OR   A
            JR   Z,TargetContextRoDataReady
            LD   DE,NucleusRuntimeVectorLength+NucleusRuntimeStateLength
            ADD  HL,DE
            JR   C,TargetPrepareCapacityFailure
            LD   DE,(StaticImageLength)
            ADD  HL,DE
            JR   C,TargetPrepareCapacityFailure
TargetContextRoDataReady:
            LD   (TargetContextRoDataBase),HL
            LD   HL,(ReadOnlyImageLength)
            LD   (TargetContextRoDataCapacity),HL
TargetContextRoDataFinished:
            CALL TargetInitializedLength
            JR   C,TargetPrepareCapacityFailure
            LD   DE,(ProgramBssLength)
            ADD  HL,DE
            JR   C,TargetPrepareCapacityFailure
            LD   DE,(TargetWritableCapacity)
            OR   A
            SBC  HL,DE
            JR   C,TargetWritableAllocationReady
            JR   Z,TargetWritableAllocationReady
TargetPrepareCapacityFailure:
            JP   TargetCapacityFailure
TargetWritableAllocationReady:
            XOR  A
            RET

; Emit a call to one identity-fixed helper in the context-linked runtime.
; DE is the helper offset published by nucleus-runtime-identity.asmi.
.routine in DE out A,carry,zero clobbers sign,parity,halfCarry,B,C,DE,HL
EmitRuntimeCall:
            LD   HL,(TargetLinkedRuntimeBase)
            ADD  HL,DE
            JP   EmitCall

; Resolve one identity-fixed writable-state offset for generated operands.
.routine in DE out A,HL,carry,zero clobbers sign,parity,halfCarry
TargetStateAddress:
            LD   HL,(TargetContextStateBase)
            ADD  HL,DE
            OR   A
            RET

.routine out DE,HL,carry clobbers halfCarry
TargetInitializedLength:
            LD   HL,(StaticImageLength)
            LD   DE,NucleusRuntimeVectorLength+NucleusRuntimeStateLength
            ADD  HL,DE
            RET

; A is the identity-defined RAM-vector ordinal. The generated call reaches the
; writable vector rather than an address in the compiler's proof adapter.
.routine in A out A,carry,zero clobbers sign,parity,halfCarry,B,C,DE,HL
EmitTargetVectorCall:
            CALL TargetVectorAddress
            JP   EmitCall
.routine in A out HL,carry,zero clobbers sign,parity,halfCarry,A,DE
TargetVectorAddress:
            LD   E,A
            ADD  A,A
            ADD  A,E
            LD   E,A
            LD   D,0
            LD   HL,(TargetContextVectorBase)
            ADD  HL,DE
            RET

.routine in A out A,carry,zero clobbers sign,parity,halfCarry,B,C,DE,HL
EmitTargetVectorJump:
            CALL TargetVectorAddress
            LD   A,$C3
            JP   EmitOpcodeWord

; Emit the implicit flat startup at the address already accounted for by
; TargetStartupLength. The entry-slot patch is resolved before source code,
; while the main operand remains the ordinary checked forward fixup.
.routine out A,carry,zero clobbers sign,parity,halfCarry,BC,DE,HL
TargetEmitStartup:
            LD   DE,(EmitDataFixup)
            LD   HL,(EmitCursor)
            CALL PatchWord
.if CompilerDiagnosticReturns
            RET  C
.endif
            LD   A,(TargetStackMode)
            OR   A
            JR   Z,TargetStartupCopy
            LD   HL,0
            CALL EmitLoadHl
.if CompilerDiagnosticReturns
            RET  C
.endif
            CALL EmitByteInlineChecked
            .db  $39                    ; ADD HL,SP
.if CompilerDiagnosticReturns
            RET  C
.endif
            CALL EmitByteInlineChecked
            .db  $EB                    ; EX DE,HL
.if CompilerDiagnosticReturns
            RET  C
.endif
            LD   HL,(TargetWritableBase)
            LD   DE,(TargetWritableCapacity)
            ADD  HL,DE                    ; $0000 denotes mathematical $10000
            CALL EmitLoadHl
.if CompilerDiagnosticReturns
            RET  C
.endif
            CALL EmitByteInlineChecked
            .db  $F9                    ; LD SP,HL
.if CompilerDiagnosticReturns
            RET  C
.endif
            CALL EmitByteInlineChecked
            .db  $D5                    ; PUSH DE, saved incoming SP
.if CompilerDiagnosticReturns
            RET  C
.endif
TargetStartupCopy:
            LD   A,(TargetLayoutMode)
            OR   A
            JR   Z,TargetStartupClear
            LD   HL,(TargetReadOnlyBase)
            CALL EmitLoadHl
.if CompilerDiagnosticReturns
            RET  C
.endif
            LD   DE,(TargetWritableBase)
            CALL EmitLoadDeImmediate
.if CompilerDiagnosticReturns
            RET  C
.endif
            CALL TargetInitializedLength
            CALL EmitLoadBcImmediate
.if CompilerDiagnosticReturns
            RET  C
.endif
            CALL EmitPairIndexedInline
            .db  EmitPairLDIR
.if CompilerDiagnosticReturns
            RET  C
.endif
TargetStartupClear:
            LD   HL,(ProgramBssLength)
            LD   A,H
            OR   L
            JR   Z,TargetStartupEntry
            LD   HL,(TargetBssBase)
            CALL EmitLoadHl
.if CompilerDiagnosticReturns
            RET  C
.endif
            LD   HL,(ProgramBssLength)
            CALL EmitLoadBcImmediate
.if CompilerDiagnosticReturns
            RET  C
.endif
            LD   DE,NucleusRuntimeInitializeBssOffset
            CALL EmitRuntimeCall
.if CompilerDiagnosticReturns
            RET  C
.endif
TargetStartupEntry:
            LD   A,(TargetStackMode)
            OR   A
            LD   A,$C3                    ; JP main when inheriting SP
            JR   Z,TargetStartupEmitEntry
            LD   A,$CD                    ; CALL main before restoring SP
TargetStartupEmitEntry:
            CALL TargetEmitEntryPlaceholder
.if CompilerDiagnosticReturns
            RET  C
.endif
            LD   HL,(EmitCursor)
            LD   (TargetTerminalAddress),HL
            LD   A,(TargetStackMode)
            OR   A
            JR   Z,TargetStartupTerminalState
            LD   HL,TargetStartupRestoreBytes
            LD   B,3
            CALL EmitBytes
.if CompilerDiagnosticReturns
            RET  C
.endif
TargetStartupTerminalState:
            LD   DE,RunState-StateBase
            LD   C,RunSucceeded
            CALL TargetEmitTerminalTest
.if CompilerDiagnosticReturns
            RET  C
.endif
            LD   A,6                      ; success vector
            CALL EmitTargetVectorJump
.if CompilerDiagnosticReturns
            RET  C
.endif
            LD   DE,TrapNumber-StateBase
            LD   C,6                      ; unhandled trap number
            CALL TargetEmitTerminalTest
.if CompilerDiagnosticReturns
            RET  C
.endif
            LD   A,7                      ; unhandled-failure vector
            CALL EmitTargetVectorJump
.if CompilerDiagnosticReturns
            RET  C
.endif
            LD   A,8                      ; trap vector
            JP   EmitTargetVectorJump

; Append the provider-owned initialized vector/state image at its run or load
; address. The same complete context that linked the helper image selects it.
.routine in HL out A,carry,zero clobbers sign,parity,halfCarry,BC,DE,HL,IX,IY
TargetEmitRuntimeInitialImage:
            LD   A,(TargetOutputBank)
            LD   DE,NucleusRuntimeIdentity
            LD   BC,NucleusRuntimeVectorLength+NucleusRuntimeStateLength
            LD   IX,TargetRuntimeContext
            CALL TargetSinkRuntimeInitialImage
            LD   DE,NucleusRuntimeVectorLength+NucleusRuntimeStateLength
            JP   TargetConsumeProviderExtent

.routine out A,carry,zero clobbers sign,parity,halfCarry,BC,DE,HL,IX,IY
FinishTargetFlatProgram:
            LD   A,(TargetDescriptorBankCountValue)
            CP   1
            JP   NZ,FinishTargetBankedProgram
            LD   HL,(EmitCursor)
            LD   DE,(TargetCodeBase)
            OR   A
            SBC  HL,DE
            LD   (TargetCodeLength),HL
            ; Loaded output appends the initialized run image after code. ROM
            ; output already emitted the same bytes before source code.
            LD   A,(TargetLayoutMode)
            OR   A
            JR   NZ,TargetLoadedDataReady
            LD   HL,(TargetWritableBase)
            LD   (EmitCursor),HL
            XOR  A
            LD   (TargetOutputBank),A
            CALL TargetInitializedLength
            LD   (EmitLimit),HL
            LD   HL,(TargetWritableBase)
            CALL TargetEmitRuntimeInitialImage
.if CompilerDiagnosticBranches
            JP   C,AbortTargetProgram
.endif
            LD   HL,StaticImageBase
            LD   BC,(StaticImageLength)
            CALL EmitBlock
.if CompilerDiagnosticBranches
            JP   C,AbortTargetProgram
.endif
TargetLoadedDataReady:
            LD   HL,(ReadOnlyImageLength)
            LD   (TargetMapAggregateLength),HL
            LD   A,H
            OR   L
            LD   HL,0
            JR   Z,TargetMapAggregateReady
            LD   HL,(TargetContextRoDataBase)
TargetMapAggregateReady:
            LD   (TargetMapAggregateBase),HL
            LD   HL,(EmitCursor)
            LD   DE,(TargetImageBase)
            OR   A
            SBC  HL,DE
            LD   (TargetMapUsedLength),HL
            LD   HL,(TargetImageBase)
            LD   (TargetMapEntryAddress),HL
            XOR  A
            LD   (TargetMapEntryBank),A
            LD   HL,(TargetReadOnlyBase)
            LD   DE,(TargetReadOnlyLength)
            LD   A,D
            OR   E
            JR   NZ,TargetMapReadOnlyReady
            LD   HL,0
TargetMapReadOnlyReady:
            LD   (TargetMapReadOnlyBase),HL
            LD   (TargetMapReadOnlyLength),DE
            LD   HL,(TargetCodeBase)
            LD   (TargetMapCodeBase),HL
            LD   HL,(TargetCodeLength)
            LD   (TargetMapCodeLength),HL
            LD   HL,(TargetWritableBase)
            LD   (TargetMapWritableBase),HL
            LD   (TargetMapInitializedBase),HL
            LD   (TargetMapVectorBase),HL
            LD   HL,(TargetWritableCapacity)
            LD   (TargetMapWritableCapacity),HL
            LD   HL,NucleusRuntimeVectorLength
            LD   (TargetMapVectorLength),HL
            CALL TargetInitializedLength
            LD   (TargetMapInitializedLength),HL
            LD   (TargetMapDataLoadLength),HL
            LD   HL,(TargetBssBase)
            LD   (TargetMapBssBase),HL
            LD   HL,(ProgramBssLength)
            LD   (TargetMapBssLength),HL
            LD   HL,TargetStackRequirement
            LD   (TargetMapStackRequirement),HL
            XOR  A
            LD   (TargetMapDataLoadBank),A
            LD   HL,(TargetWritableBase)
            LD   A,(TargetLayoutMode)
            OR   A
            JR   Z,TargetMapDataLoadReady
            LD   HL,(TargetReadOnlyBase)
TargetMapDataLoadReady:
            LD   (TargetMapDataLoadAddress),HL
            LD   IX,TargetFlatMapBase
            CALL TargetSinkMapFlat
TargetFinishMapReady:
            JR   C,TargetFinishOutputFailure
            CALL TargetSinkCommit
            JR   C,TargetFinishOutputFailure
            XOR  A
            RET

; The operating adapter already owns the descriptor, part-bank array, and
; NOBJ encoder. Give it the two compact retained per-bank tables plus the
; common layout state; it deterministically forms and validates the MAP.
.routine out A,carry,zero clobbers sign,parity,halfCarry,BC,DE,HL,IX,IY
FinishTargetBankedProgram:
            CALL TargetSaveOutputBank
            JR   C,TargetFinishOutputFailure
            LD   IX,(TargetDescriptorPointer)
            LD   IY,TargetBankStateBase
            LD   HL,TargetBankRoLengthBase
            CALL TargetSinkMapBanked
            JR   TargetFinishMapReady

.routine in A out A,carry,zero clobbers sign,parity,halfCarry,BC,DE,HL,IX,IY
AbortTargetProgram:
            PUSH AF
            LD   A,(TargetOutputBank)
            INC  A
            CALL NZ,TargetSinkAbort
            POP  AF
            SCF
            RET

TargetConfigurationFailure:
            LD   A,DiagnosticTargetConfiguration
            JR   TargetDiagnosticReady
; Fixup resolution closes the bank selector before MAP/COMMIT, while the sink
; generation remains open. Abort that late phase here; the production
; diagnostic continuation subsequently sees TargetOutputClosed and therefore
; cannot issue a second abort.
TargetFinishOutputFailure:
            PUSH AF
            CALL TargetSinkAbort
            POP  AF
TargetOutputFailure:
            OR   A
            JR   NZ,TargetDiagnosticReady
            LD   A,DiagnosticTargetOutput
TargetDiagnosticReady:
            JP   CompilerSetDiagnostic

TargetStartupRestoreBytes: .db $C1,$E1,$F9 ; discard CALL return / restore SP
TargetTerminalSelectBytes .equ TypedBeginAndBytes+3 ; JR NZ across one JP
