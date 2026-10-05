; Prove the compact descriptor and flat append-only compiler sink end to end.

            .include "target-memory-map.asmi"
SegmentedOutput       .equ 1
TargetStreamingOutput .equ 1
            .include "loop-compiler-state.asmi"
            .include "aggregate-call-state.asmi"
            .include "target-output-state.asmi"
            .include "loop-z80-state.asmi"

            .org CompilerCoreBase
CompilerCodeStart:
LegacyCompilerSlices .equ 0
AggregateCallSlices  .equ 1
Stage7LL1            .equ 1
SourceAdapterCodeStart:
            .include "source-adapter.asm"
SourceAdapterCodeEnd:
TokenizerCodeStart:
            .include "loop-tokenizer.asm"
TokenizerCodeEnd:
SemanticSinkCodeStart:
            .include "loop-semantic-sink.asm"
SemanticSinkCodeEnd:
SymbolCodeStart:
            .include "loop-symbols.asm"
SymbolCodeEnd:
ParserCodeStart:
            .include "loop-parser.asm"
ParserCodeEnd:
CompilerCommonCodeEnd:
SinkCodeStart:
LegacyEncoders .equ 0
            .include "loop-z80-sink.asm"
            .include "target-output.asm"
TypedSinkCodeStart:
            .include "typed-expression-z80.asm"
            .include "aggregate-z80.asm"
TypedSinkCodeEnd:
SinkCodeEnd:
CompilerCodeEnd:
CompilerImmutableStart:
            .include "loop-keywords.asmi"
CompilerImmutableEnd:
CompilerCoreEnd:

            .org SourceBase
FlatTargetSource:
            .db "var value as u16 = 3",10
            .db "var cleared as u8",10
            .db "sub main()",10
            .db "value = value * 2",10
            .db "end",10
FlatTargetSourceEnd:

FlatTargetParts:
            .db 1
            .dw FlatTargetSource,FlatTargetSourceEnd
FlatTargetPartBanks: .db 0

FlatTargetTrapSource:
            .db "var divisor as u8",10
            .db "sub main()",10
            .db "var value as u8 = 1 / divisor",10
            .db "end",10
FlatTargetTrapSourceEnd:
FlatTargetTrapParts:
            .db 1
            .dw FlatTargetTrapSource,FlatTargetTrapSourceEnd

FlatTargetUnhandledSource:
            .db "sub failer() fails",10
            .db "fail 7",10
            .db "end",10
            .db "sub main() fails",10
            .db "failer() else fail",10
            .db "end",10
FlatTargetUnhandledSourceEnd:
FlatTargetUnhandledParts:
            .db 1
            .dw FlatTargetUnhandledSource,FlatTargetUnhandledSourceEnd

BankedTargetLibrarySource:
            .db "record Box",10
            .db "value as u8",10
            .db "end",10
            .db "var shared as Box = (4)",10
            .db "var countdown as u8 = 1",10
            .db "var result as u8",10
            ; The first constant byte is a proof-only far-jump destination.
            .db "const Lookup as u8[2] = [$76, 5]",10
            .db "sub recursive()",10
            .db "if countdown = 0",10
            .db "return",10
            .db "end",10
            .db "countdown = countdown - 1",10
            .db "recursive()",10
            .db "end",10
            .db "sub readBox(box as Box, add as u8) as u8",10
            .db "return box.value + add",10
            .db "end",10
            .db "sub failRemote() fails",10
            .db "fail 7",10
            .db "end",10
BankedTargetLibrarySourceEnd:
BankedTargetMainSource:
            .db "sub main() fails",10
            .db "var code as u8",10
            .db "recursive()",10
            .db "result = readBox(shared, 1)",10
            .db "failRemote() handle code",10
            .db "result = result + code",10
            .db "end",10
            .db "end",10
BankedTargetMainSourceEnd:
BankedTargetParts:
            .db 1
            .dw BankedTargetLibrarySource,BankedTargetLibrarySourceEnd
            .db 2
            .dw BankedTargetMainSource,BankedTargetMainSourceEnd
BankedTargetPartBanks: .db 1,0
BankedTargetEntry1Source:
            .db "var result as u8",10
            .db "sub main()",10
            .db "result = 12",10
            .db "end",10
BankedTargetEntry1SourceEnd:
BankedTargetEntry1Parts:
            .db 1
            .dw BankedTargetEntry1Source,BankedTargetEntry1SourceEnd
BankedTargetEntry1PartBanks: .db 1

BankedConstantFailurePart1:
            .db "const Bytes as u8[2] = [1, 2]",10
            .db "sub take(value as u8[2])",10
            .db "end",10
BankedConstantFailurePart1End:
BankedConstantFailurePart2:
            .db "sub main()",10
            .db "take(Bytes)",10
            .db "end",10
BankedConstantFailurePart2End:
BankedConstantFailureParts:
            .db 1
            .dw BankedConstantFailurePart1,BankedConstantFailurePart1End
            .db 2
            .dw BankedConstantFailurePart2,BankedConstantFailurePart2End

BankedParameterFailurePart1:
            .db "record Box",10,"value as u8",10,"end",10
            .db "sub take(first as Box, second as Box)",10,"end",10
BankedParameterFailurePart1End:
BankedParameterFailurePart2:
            .db "var shared as Box = (1)",10
            .db "sub give() as Box",10,"return shared",10,"end",10
            .db "sub main()",10,"take(shared, give())",10,"end",10
BankedParameterFailurePart2End:
BankedParameterFailureParts:
            .db 1
            .dw BankedParameterFailurePart1,BankedParameterFailurePart1End
            .db 2
            .dw BankedParameterFailurePart2,BankedParameterFailurePart2End

BankedResultFailurePart1:
            .db "record Box",10,"value as u8",10,"end",10
            .db "var shared as Box = (1)",10
            .db "sub give() as Box",10,"return shared",10,"end",10
BankedResultFailurePart1End:
BankedResultFailurePart2:
            .db "var output as Box",10
            .db "sub main()",10
            .db "output = give()",10
            .db "end",10
BankedResultFailurePart2End:
BankedResultFailureParts:
            .db 1
            .dw BankedResultFailurePart1,BankedResultFailurePart1End
            .db 2
            .dw BankedResultFailurePart2,BankedResultFailurePart2End

BankedForwardFailurePart1:
            .db "forward sub later()",10
BankedForwardFailurePart1End:
BankedForwardFailurePart2:
            .db "sub later",10,"return",10,"end",10
            .db "sub main()",10,"later()",10,"end",10
BankedForwardFailurePart2End:
BankedForwardFailureParts:
            .db 1
            .dw BankedForwardFailurePart1,BankedForwardFailurePart1End
            .db 2
            .dw BankedForwardFailurePart2,BankedForwardFailurePart2End
BankedTrapPart1:
            .db "var result as u8",10
            .db "sub trapRemote(divisor as u8)",10
            .db "result = 1 / divisor",10
            .db "end",10
BankedTrapPart1End:
BankedTrapPart2:
            .db "sub main()",10
            .db "trapRemote(0)",10
            .db "end",10
BankedTrapPart2End:
BankedTrapParts:
            .db 1
            .dw BankedTrapPart1,BankedTrapPart1End
            .db 2
            .dw BankedTrapPart2,BankedTrapPart2End
BankedLargePart1:
            .db "const First as string[253] = ",34,34,10
            .db "const Second as string[253] = ",34,34,10
BankedLargePart1End:
BankedLargePart2:
            .db "sub main()",10,"end",10
BankedLargePart2End:
BankedLargeParts:
            .db 1
            .dw BankedLargePart1,BankedLargePart1End
            .db 2
            .dw BankedLargePart2,BankedLargePart2End
BankedFailurePartBanks: .db 1,0
BankedInvalidPartBanks: .db 2,0

FlatTargetDescriptor:
            .dw NucleusRuntimeIdentity
            .dw $8000,$1000
            .dw $4000,$1000
            .db 1
            .db 1,0
            .dw FlatTargetPartBanks
FlatTargetLoadedDescriptor:
            .dw NucleusRuntimeIdentity
            .dw $8000,$2000
            .dw $9000,$1000
            .db 0
            .db 1,0
            .dw FlatTargetPartBanks
FlatTargetEarlyWritableDescriptor:
            .dw NucleusRuntimeIdentity
            .dw $8000,$2000
            .dw $8100,$1000
            .db 0
            .db 1,0
            .dw FlatTargetPartBanks
FlatTargetBadFlagsDescriptor:
            .dw NucleusRuntimeIdentity
            .dw $8000,$1000
            .dw $4000,$1000
            .db 2
            .db 1,0
            .dw FlatTargetPartBanks
FlatTargetStackExactDescriptor:
            .dw NucleusRuntimeIdentity
            .dw $8000,$1000
            .dw $4000,$0F4B
            .db 1
            .db 1,0
            .dw FlatTargetPartBanks
FlatTargetStackOverflowDescriptor:
            .dw NucleusRuntimeIdentity
            .dw $8000,$1000
            .dw $4000,$0F4A
            .db 1
            .db 1,0
            .dw FlatTargetPartBanks
BankedTargetDescriptor:
            .dw NucleusRuntimeIdentity
            .dw $8000,$1000
            .dw $4000,$1000
            .db 1
            .db 2,0
            .dw BankedTargetPartBanks
BankedTargetEntry1Descriptor:
            .dw NucleusRuntimeIdentity
            .dw $8000,$1000
            .dw $4000,$1000
            .db 1
            .db 2,1
            .dw BankedTargetEntry1PartBanks
BankedFailureDescriptor:
            .dw NucleusRuntimeIdentity
            .dw $8000,$1000
            .dw $4000,$1000
            .db 1
            .db 2,0
            .dw BankedFailurePartBanks
BankedWrongEntryDescriptor:
            .dw NucleusRuntimeIdentity
            .dw $8000,$1000
            .dw $4000,$1000
            .db 1
            .db 2,1
            .dw BankedTargetPartBanks
BankedInvalidPartDescriptor:
            .dw NucleusRuntimeIdentity
            .dw $8000,$1000
            .dw $4000,$1000
            .db 1
            .db 2,0
            .dw BankedInvalidPartBanks
BankedEntryOverflowDescriptor:
            .dw NucleusRuntimeIdentity
            .dw $8000,$02BC
            .dw $4000,$1000
            .db 1
            .db 2,0
            .dw BankedTargetPartBanks
BankedOtherOverflowDescriptor:
            .dw NucleusRuntimeIdentity
            .dw $8000,$0352
            .dw $4000,$1000
            .db 1
            .db 2,0
            .dw BankedFailurePartBanks

; The accepted multipart program from Chapter 21.1 is compiled through the
; production target entry and executed only from its committed NOBJ image.
; Its source occupies part of the address space released by retiring the old
; complete-image staging buffer.
            .org ReleasedGeneratedStagingBase
Chapter21TargetPart1:
            .db "record Cell",10
            .db "    value as u8",10
            .db "end",10
            .db 10
            .db "var template as Cell = (1)",10
            .db "var cells as Cell[4] = [(0), (0), (0), (0)]",10
            .db 10
Chapter21TargetPart1End:
Chapter21TargetPart2:
            .db "sub cellAt(index as u8) as Cell",10
            .db "    return cells[index]",10
            .db "end",10
            .db 10
            .db "sub setCell(cell as Cell, value as u8)",10
            .db "    cell.value = value",10
            .db "end",10
            .db 10
            .db "sub main()",10
            .db "    var index as u8",10
            .db "    var code as u8",10
            .db 10
            .db "    for index = 0 until 4",10
            .db "        cells[index] = template",10
            .db "        setCell(template, index + 1)",10
            .db "    end",10
            .db 10
            .db "    cells[0].value = cellAt(0).value",10
            .db "    if cells[0].value = 1",10
            .db "        writeOutputByte('Y') handle code",10
            .db "            return",10
            .db "        end",10
            .db "    elseif cells[0].value = 0",10
            .db "        writeOutputByte('N') handle code",10
            .db "            return",10
            .db "        end",10
            .db "    end",10
            .db "end",10
Chapter21TargetPart2End:
Chapter21TargetParts:
            .db 1
            .dw Chapter21TargetPart1,Chapter21TargetPart1End
            .db 2
            .dw Chapter21TargetPart2,Chapter21TargetPart2End
Chapter21TargetPartBanks: .db 0,0
Chapter21TargetDescriptor:
            .dw NucleusRuntimeIdentity
            .dw $8000,$1000
            .dw $4000,$1000
            .db 1
            .db 1,0
            .dw Chapter21TargetPartBanks

            .org TargetRuntimeBase
RuntimeCodeStart:
            .include "proof-z80-runtime.asm"
RuntimeCodeEnd:

            .org ProofBase
.routine out carry,zero clobbers sign,parity,halfCarry,A,BC,DE,HL,IX,IY
ProofStart:
            LD   SP,StackTop
            XOR  A
            LD   (ProofStatus),A
            LD   (ProofCase),A
            LD   (AdapterCommitted),A
            LD   (AdapterAborted),A
            LD   (AdapterMapFailure),A
            LD   (AdapterCommitFailure),A
            LD   HL,AdapterLogBase
            LD   (AdapterCursor),HL
            LD   HL,$F000
            LD   DE,$1000
            LD   A,10
            LD   (ProofCase),A
            CALL ProofCallTargetValidateRegion
            JP   C,ProofRegionFailure
            LD   HL,$FFFF
            LD   (EmitCursor),HL
            LD   HL,1
            LD   (EmitLimit),HL
            LD   DE,1
            LD   A,46
            LD   (ProofCase),A
            CALL TargetConsumeExtent
            JP   C,ProofRegionFailure
            LD   HL,(EmitCursor)
            LD   A,H
            OR   L
            JP   NZ,ProofRegionFailure
            LD   HL,(EmitLimit)
            LD   A,H
            OR   L
            JP   NZ,ProofRegionFailure
            LD   HL,$F001
            LD   DE,$1000
            LD   A,11
            LD   (ProofCase),A
            CALL ProofCallTargetValidateRegion
            JP   NC,ProofRegionFailure
            LD   A,(DiagnosticCode)
            CP   DiagnosticTargetCapacity
            JP   NZ,ProofRegionFailure
            LD   HL,$8000
            LD   A,12
            LD   (ProofCase),A
            LD   (TargetImageBase),HL
            LD   HL,$1000
            LD   (TargetImageCapacity),HL
            LD   HL,$8F00
            LD   (TargetWritableBase),HL
            LD   HL,$0200
            LD   (TargetWritableCapacity),HL
            CALL ProofCallTargetClassifyFlatLayout
            JP   NC,ProofRegionFailure
            LD   A,(DiagnosticCode)
            CP   DiagnosticTargetConfiguration
            JP   NZ,ProofRegionFailure
            LD   HL,$2000
            LD   A,13
            LD   (ProofCase),A
            LD   (TargetImageCapacity),HL
            LD   HL,$9000
            LD   (TargetWritableBase),HL
            LD   HL,$0100
            LD   (TargetWritableCapacity),HL
            CALL ProofCallTargetClassifyFlatLayout
            JP   C,ProofRegionFailure
            LD   A,(TargetLayoutMode)
            OR   A
            JP   NZ,ProofRegionFailure
            LD   A,14
            LD   (ProofCase),A
            LD   A,1
            LD   HL,FlatTargetParts
            LD   IX,FlatTargetEarlyWritableDescriptor
            CALL CompileTargetAggregateCallParts
            JP   NC,ProofLoadedFailure
            CALL ProofCompilerStackExact
            JP   NZ,ProofLoadedFailure
            LD   A,(DiagnosticCode)
            CP   DiagnosticTargetCapacity
            JP   NZ,ProofLoadedFailure
            LD   A,15
            LD   (ProofCase),A
            XOR  A
            LD   (AdapterCommitted),A
            LD   (AdapterAborted),A
            LD   A,61
            LD   (AdapterFailureCountdown),A
            LD   HL,AdapterLogBase
            LD   (AdapterCursor),HL
            LD   A,1
            LD   HL,FlatTargetParts
            LD   IX,FlatTargetLoadedDescriptor
            CALL CompileTargetAggregateCallParts
            JP   NC,ProofLoadedFailure
            LD   A,(DiagnosticCode)
            CP   DiagnosticTargetOutput
            JP   NZ,ProofLoadedFailure
            LD   A,(AdapterCommitted)
            OR   A
            JP   NZ,ProofLoadedFailure
            LD   A,(AdapterAborted)
            CP   1
            JP   NZ,ProofLoadedFailure
            LD   A,16
            LD   (ProofCase),A
            XOR  A
            LD   (AdapterCommitted),A
            LD   (AdapterAborted),A
            LD   (AdapterFailureCountdown),A
            LD   HL,AdapterLogBase
            LD   (AdapterCursor),HL
            LD   A,1
            LD   HL,FlatTargetParts
            LD   IX,FlatTargetLoadedDescriptor
            CALL CompileTargetAggregateCallParts
            JP   C,ProofLoadedFailure
            CALL ProofCompilerStackExact
            JP   NZ,ProofLoadedFailure
            LD   A,(TargetLayoutMode)
            OR   A
            JP   NZ,ProofLoadedFailure
            LD   HL,(AdapterCapturedContext+$0E)
            LD   DE,$8192
            OR   A
            SBC  HL,DE
            JP   NZ,ProofLoadedFailure
            LD   HL,(AdapterCapturedMap+$03)
            LD   DE,$1048
            OR   A
            SBC  HL,DE
            JP   NZ,ProofLoadedFailure
            LD   HL,(AdapterCapturedMap+$05)
            LD   A,H
            OR   L
            JP   NZ,ProofLoadedFailure
            LD   HL,(AdapterCapturedMap+$09)
            LD   DE,$8192
            OR   A
            SBC  HL,DE
            JP   NZ,ProofLoadedFailure
            LD   HL,(AdapterCapturedMap+TargetMapWritableBase-TargetFlatMapBase)
            LD   DE,$9000
            OR   A
            SBC  HL,DE
            JP   NZ,ProofLoadedFailure
            LD   HL,(AdapterCapturedMap+TargetMapInitializedLength-TargetFlatMapBase)
            LD   DE,72
            OR   A
            SBC  HL,DE
            JP   NZ,ProofLoadedFailure
            LD   HL,(AdapterCapturedMap+TargetMapDataLoadAddress-TargetFlatMapBase)
            LD   DE,$9000
            OR   A
            SBC  HL,DE
            JP   NZ,ProofLoadedFailure
            LD   HL,(AdapterCapturedMap+TargetMapAggregateBase-TargetFlatMapBase)
            LD   A,H
            OR   L
            JP   NZ,ProofLoadedFailure
            LD   HL,(AdapterCursor)
            LD   DE,AdapterLogBase
            OR   A
            SBC  HL,DE
            LD   (AdapterLoadedLogLength),HL
            LD   B,H
            LD   C,L
            LD   HL,AdapterLogBase
            LD   DE,AdapterLoadedLogBase
            LDIR
            LD   A,17
            LD   (ProofCase),A
            LD   A,1
            LD   HL,FlatTargetParts
            LD   IX,FlatTargetBadFlagsDescriptor
            CALL CompileTargetAggregateCallParts
            JP   NC,ProofConfigurationFailure
            CALL ProofCompilerStackExact
            JP   NZ,ProofConfigurationFailure
            LD   A,(DiagnosticCode)
            LD   (AdapterSavedDiagnostic),A
            LD   A,(AdapterAborted)
            OR   A
            JP   NZ,ProofConfigurationFailure
            LD   A,18
            LD   (ProofCase),A
            LD   A,1
            LD   HL,FlatTargetParts
            LD   IX,FlatTargetStackExactDescriptor
            CALL CompileTargetAggregateCallParts
            JP   C,ProofRegionFailure
            LD   A,19
            LD   (ProofCase),A
            LD   A,1
            LD   HL,FlatTargetParts
            LD   IX,FlatTargetStackOverflowDescriptor
            CALL CompileTargetAggregateCallParts
            JP   NC,ProofRegionFailure
            LD   A,(DiagnosticCode)
            CP   DiagnosticTargetCapacity
            JP   NZ,ProofRegionFailure
            XOR  A
            LD   (AdapterCommitted),A
            LD   (AdapterAborted),A
            LD   A,20
            LD   (ProofCase),A
            LD   (AdapterFailureCountdown),A
            LD   A,1
            LD   HL,FlatTargetParts
            LD   IX,FlatTargetDescriptor
            CALL CompileTargetAggregateCallParts
            JP   NC,ProofAtomicFailure
            CALL ProofCompilerStackExact
            JP   NZ,ProofAtomicFailure
            LD   A,21
            LD   (ProofCase),A
            LD   A,(DiagnosticCode)
            CP   DiagnosticTargetOutput
            JP   NZ,ProofAtomicFailure
            LD   A,22
            LD   (ProofCase),A
            LD   A,(AdapterCommitted)
            OR   A
            JP   NZ,ProofAtomicFailure
            LD   A,23
            LD   (ProofCase),A
            LD   A,(AdapterAborted)
            CP   1
            JP   NZ,ProofAtomicFailure
            LD   A,24
            LD   (ProofCase),A
            LD   HL,(AdapterCursor)
            LD   DE,AdapterLogBase
            OR   A
            SBC  HL,DE
            LD   A,H
            OR   L
            JP   Z,ProofAtomicFailure
            LD   A,30
            LD   (ProofCase),A
            XOR  A
            LD   (AdapterCommitted),A
            LD   (AdapterAborted),A
            LD   (AdapterFailureCountdown),A
            INC  A
            LD   (AdapterMapFailure),A
            LD   HL,AdapterLogBase
            LD   (AdapterCursor),HL
            LD   A,1
            LD   HL,FlatTargetTrapParts
            LD   IX,FlatTargetDescriptor
            CALL CompileTargetAggregateCallParts
            JP   NC,ProofAtomicFailure
            CALL ProofCompilerStackExact
            JP   NZ,ProofAtomicFailure
            LD   A,(DiagnosticCode)
            CP   DiagnosticTargetOutput
            JP   NZ,ProofAtomicFailure
            LD   A,(AdapterCommitted)
            OR   A
            JP   NZ,ProofAtomicFailure
            LD   A,(AdapterAborted)
            CP   1
            JP   NZ,ProofAtomicFailure
            LD   HL,(AdapterCursor)
            LD   DE,AdapterLogBase
            OR   A
            SBC  HL,DE
            LD   (AdapterFailedLogLength),HL
            LD   B,H
            LD   C,L
            LD   HL,AdapterLogBase
            LD   DE,AdapterFailedLogBase
            LDIR

            ; COMMIT fails after the target bank selector has closed. The
            ; local late-output path must abort once; the synthetic diagnostic
            ; continuation must observe the closed selector and not abort
            ; again.
            LD   A,31
            LD   (ProofCase),A
            XOR  A
            LD   (AdapterCommitted),A
            LD   (AdapterAborted),A
            LD   (AdapterMapFailure),A
            INC  A
            LD   (AdapterCommitFailure),A
            LD   HL,AdapterLogBase
            LD   (AdapterCursor),HL
            LD   A,1
            LD   HL,FlatTargetTrapParts
            LD   IX,FlatTargetDescriptor
            CALL CompileTargetAggregateCallParts
            JP   NC,ProofAtomicFailure
            CALL ProofCompilerStackExact
            JP   NZ,ProofAtomicFailure
            LD   A,(DiagnosticCode)
            CP   DiagnosticTargetOutput
            JP   NZ,ProofAtomicFailure
            LD   A,(AdapterCommitted)
            OR   A
            JP   NZ,ProofAtomicFailure
            LD   A,(AdapterAborted)
            CP   1
            JP   NZ,ProofAtomicFailure
            LD   A,25
            LD   (ProofCase),A
            XOR  A
            LD   (AdapterCommitted),A
            LD   (AdapterAborted),A
            LD   (AdapterFailureCountdown),A
            LD   (AdapterMapFailure),A
            LD   (AdapterCommitFailure),A
            LD   HL,AdapterLogBase
            LD   (AdapterCursor),HL
            LD   A,1
            LD   HL,FlatTargetParts
            LD   IX,FlatTargetDescriptor
            CALL CompileTargetAggregateCallParts
            JP   C,ProofCompileFailure
            LD   A,(AdapterCommitted)
            CP   1
            JP   NZ,ProofCommitFailure
            LD   A,(AdapterAborted)
            OR   A
            JP   NZ,ProofCommitFailure
            LD   HL,(AdapterCapturedBegin+TargetDescriptorImageBase)
            LD   DE,$8000
            OR   A
            SBC  HL,DE
            JP   NZ,ProofBeginFailure
            LD   A,(TargetLayoutMode)
            CP   TargetLayoutRom
            JP   NZ,ProofRegionFailure
            LD   HL,(AdapterCapturedContext+$00)
            LD   DE,$8003
            OR   A
            SBC  HL,DE
            JP   NZ,ProofContextFailure
            LD   HL,(AdapterCapturedContext+$06)
            LD   DE,$4021
            OR   A
            SBC  HL,DE
            JP   NZ,ProofContextFailure
            LD   HL,(AdapterCapturedMap+$01)
            LD   DE,$8000
            OR   A
            SBC  HL,DE
            JP   NZ,ProofMapFailure
            LD   HL,(AdapterCapturedMap+$05)
            LD   DE,$81AA
            OR   A
            SBC  HL,DE
            JP   NZ,ProofMapFailure
            LD   HL,(AdapterCapturedMap+TargetMapWritableBase-TargetFlatMapBase)
            LD   DE,$4000
            OR   A
            SBC  HL,DE
            JP   NZ,ProofMapFailure
            LD   HL,(AdapterCapturedMap+TargetMapVectorLength-TargetFlatMapBase)
            LD   DE,NucleusRuntimeVectorLength
            OR   A
            SBC  HL,DE
            JP   NZ,ProofMapFailure
            LD   HL,(AdapterCapturedMap+TargetMapInitializedLength-TargetFlatMapBase)
            LD   DE,72
            OR   A
            SBC  HL,DE
            JP   NZ,ProofMapFailure
            LD   HL,(AdapterCapturedMap+TargetMapBssBase-TargetFlatMapBase)
            LD   DE,$4048
            OR   A
            SBC  HL,DE
            JP   NZ,ProofMapFailure
            LD   HL,(AdapterCapturedMap+TargetMapStackRequirement-TargetFlatMapBase)
            LD   DE,TargetStackRequirement
            OR   A
            SBC  HL,DE
            JP   NZ,ProofMapFailure
            LD   HL,(AdapterCapturedMap+TargetMapDataLoadAddress-TargetFlatMapBase)
            LD   DE,$81AA
            OR   A
            SBC  HL,DE
            JP   NZ,ProofMapFailure
            LD   HL,(AdapterCursor)
            LD   DE,AdapterLogBase
            OR   A
            SBC  HL,DE
            LD   (AdapterLogLength),HL
            LD   A,H
            OR   L
            JP   Z,ProofLogFailure
            LD   B,H
            LD   C,L
            LD   HL,AdapterLogBase
            LD   DE,AdapterSuccessLogBase
            LDIR
            LD   HL,AdapterCapturedMap
            LD   DE,AdapterSuccessMap
            LD   BC,TargetMapSize
            LDIR

            XOR  A
            LD   (AdapterCommitted),A
            LD   (AdapterAborted),A
            LD   (AdapterFailureCountdown),A
            LD   HL,AdapterLogBase
            LD   (AdapterCursor),HL
            LD   A,1
            LD   HL,FlatTargetTrapParts
            LD   IX,FlatTargetDescriptor
            CALL CompileTargetAggregateCallParts
            JP   C,ProofCompileFailure
            LD   HL,(AdapterCursor)
            LD   DE,AdapterLogBase
            OR   A
            SBC  HL,DE
            LD   (AdapterTrapLogLength),HL
            LD   B,H
            LD   C,L
            LD   HL,AdapterLogBase
            LD   DE,AdapterTrapLogBase
            LDIR
            LD   HL,AdapterCapturedMap
            LD   DE,AdapterTrapMap
            LD   BC,TargetMapSize
            LDIR

            XOR  A
            LD   (AdapterCommitted),A
            LD   (AdapterAborted),A
            LD   (AdapterFailureCountdown),A
            LD   HL,AdapterLogBase
            LD   (AdapterCursor),HL
            LD   A,1
            LD   HL,FlatTargetUnhandledParts
            LD   IX,FlatTargetDescriptor
            CALL CompileTargetAggregateCallParts
            JP   C,ProofCompileFailure
            LD   HL,(AdapterCursor)
            LD   DE,AdapterLogBase
            OR   A
            SBC  HL,DE
            LD   (AdapterUnhandledLogLength),HL
            LD   B,H
            LD   C,L
            LD   HL,AdapterLogBase
            LD   DE,AdapterUnhandledLogBase
            LDIR
            LD   HL,AdapterCapturedMap
            LD   DE,AdapterUnhandledMap
            LD   BC,TargetMapSize
            LDIR

            LD   A,(DiagnosticCode)
            LD   (AdapterSavedDiagnostic),A

            LD   A,40
            LD   (ProofCase),A
            LD   A,2
            LD   HL,BankedTargetParts
            LD   IX,BankedInvalidPartDescriptor
            CALL CompileTargetAggregateCallParts
            JP   NC,ProofConfigurationFailure
            LD   A,(DiagnosticCode)
            CP   DiagnosticTargetConfiguration
            JP   NZ,ProofConfigurationFailure

            LD   A,41
            LD   (ProofCase),A
            LD   A,2
            LD   HL,BankedTargetParts
            LD   IX,BankedWrongEntryDescriptor
            CALL CompileTargetAggregateCallParts
            JP   NC,ProofConfigurationFailure
            LD   A,(DiagnosticCode)
            CP   DiagnosticTargetConfiguration
            JP   NZ,ProofConfigurationFailure

            LD   A,42
            LD   (ProofCase),A
            LD   A,2
            LD   HL,BankedConstantFailureParts
            LD   IX,BankedFailureDescriptor
            CALL CompileTargetAggregateCallParts
            JP   NC,ProofConfigurationFailure
            LD   A,(DiagnosticCode)
            CP   DiagnosticTargetConfiguration
            JP   NZ,ProofConfigurationFailure

            LD   A,43
            LD   (ProofCase),A
            XOR  A
            LD   (AdapterCommitted),A
            LD   (AdapterAborted),A
            LD   (AdapterFailureCountdown),A
            LD   HL,AdapterLogBase
            LD   (AdapterCursor),HL
            LD   A,2
            LD   HL,BankedTargetParts
            LD   IX,BankedEntryOverflowDescriptor
            CALL CompileTargetAggregateCallParts
            JP   NC,ProofConfigurationFailure
            LD   A,(DiagnosticCode)
            CP   DiagnosticTargetCapacity
            JP   NZ,ProofConfigurationFailure
            LD   A,(AdapterAborted)
            DEC  A
            JP   NZ,ProofAtomicFailure
            LD   A,(AdapterCommitted)
            OR   A
            JP   NZ,ProofAtomicFailure

            LD   A,44
            LD   (ProofCase),A
            XOR  A
            LD   (AdapterCommitted),A
            LD   (AdapterAborted),A
            LD   (AdapterFailureCountdown),A
            LD   HL,AdapterLogBase
            LD   (AdapterCursor),HL
            LD   A,2
            LD   HL,BankedLargeParts
            LD   IX,BankedOtherOverflowDescriptor
            CALL CompileTargetAggregateCallParts
            JP   NC,ProofConfigurationFailure
            LD   A,(DiagnosticCode)
            CP   DiagnosticTargetCapacity
            JP   NZ,ProofFail
            LD   A,(AdapterAborted)
            DEC  A
            JP   NZ,ProofAtomicFailure
            LD   A,(AdapterCommitted)
            OR   A
            JP   NZ,ProofAtomicFailure

            LD   A,45
            LD   (ProofCase),A
            XOR  A
            LD   (AdapterAborted),A
            LD   (AdapterFailureCountdown),A
            LD   HL,AdapterLogBase
            LD   (AdapterCursor),HL
            LD   A,2
            LD   HL,BankedParameterFailureParts
            LD   IX,BankedFailureDescriptor
            CALL CompileTargetAggregateCallParts
            JP   NC,ProofConfigurationFailure
            CALL ProofCompilerStackExact
            JP   NZ,ProofConfigurationFailure
            LD   A,(DiagnosticCode)
            CP   DiagnosticTargetConfiguration
            JP   NZ,ProofFail
            LD   A,(AdapterAborted)
            OR   A
            JP   NZ,ProofAtomicFailure

            LD   A,46
            LD   (ProofCase),A
            XOR  A
            LD   (AdapterAborted),A
            LD   (AdapterFailureCountdown),A
            LD   HL,AdapterLogBase
            LD   (AdapterCursor),HL
            LD   A,2
            LD   HL,BankedResultFailureParts
            LD   IX,BankedFailureDescriptor
            CALL CompileTargetAggregateCallParts
            JP   NC,ProofConfigurationFailure
            LD   A,(DiagnosticCode)
            CP   DiagnosticTargetConfiguration
            JP   NZ,ProofFail

            LD   A,47
            LD   (ProofCase),A
            XOR  A
            LD   (AdapterAborted),A
            LD   (AdapterFailureCountdown),A
            LD   HL,AdapterLogBase
            LD   (AdapterCursor),HL
            LD   A,2
            LD   HL,BankedForwardFailureParts
            LD   IX,BankedFailureDescriptor
            CALL CompileTargetAggregateCallParts
            JP   NC,ProofConfigurationFailure
            LD   A,(DiagnosticCode)
            CP   DiagnosticTargetConfiguration
            JP   NZ,ProofFail

            XOR  A
            LD   (AdapterCommitted),A
            LD   (AdapterAborted),A
            LD   (AdapterFailureCountdown),A
            LD   HL,AdapterBankedTrapLogBase
            LD   (AdapterCursor),HL
            LD   A,2
            LD   HL,BankedTrapParts
            LD   IX,BankedTargetDescriptor
            CALL CompileTargetAggregateCallParts
            JP   C,ProofCompileFailure
            LD   HL,(AdapterCursor)
            LD   DE,AdapterBankedTrapLogBase
            OR   A
            SBC  HL,DE
            LD   (AdapterBankedTrapLogLength),HL

            XOR  A
            LD   (AdapterCommitted),A
            LD   (AdapterAborted),A
            LD   (AdapterFailureCountdown),A
            LD   HL,AdapterEntry1LogBase
            LD   (AdapterCursor),HL
            LD   A,1
            LD   HL,BankedTargetEntry1Parts
            LD   IX,BankedTargetEntry1Descriptor
            CALL CompileTargetAggregateCallParts
            JR   C,ProofCompileFailure
            LD   HL,(AdapterCursor)
            LD   DE,AdapterEntry1LogBase
            OR   A
            SBC  HL,DE
            LD   (AdapterEntry1LogLength),HL

            XOR  A
            LD   (AdapterCommitted),A
            LD   (AdapterAborted),A
            LD   (AdapterFailureCountdown),A
            LD   HL,AdapterLogBase
            LD   (AdapterCursor),HL
            LD   A,2
            LD   HL,BankedTargetParts
            LD   IX,BankedTargetDescriptor
            CALL CompileTargetAggregateCallParts
            JR   C,ProofCompileFailure
            LD   HL,(AdapterCursor)
            LD   DE,AdapterLogBase
            OR   A
            SBC  HL,DE
            LD   (AdapterBankedLogLength),HL

            XOR  A
            LD   (AdapterCommitted),A
            LD   (AdapterAborted),A
            LD   (AdapterFailureCountdown),A
            LD   HL,AdapterChapter21LogBase
            LD   (AdapterCursor),HL
            LD   A,2
            LD   HL,Chapter21TargetParts
            LD   IX,Chapter21TargetDescriptor
            CALL CompileTargetAggregateCallParts
            JR   C,ProofCompileFailure
            LD   HL,(AdapterCursor)
            LD   DE,AdapterChapter21LogBase
            OR   A
            SBC  HL,DE
            LD   (AdapterChapter21LogLength),HL
            LD   A,(AdapterSavedDiagnostic)
            LD   (DiagnosticCode),A
            LD   A,$A5
            LD   (ProofStatus),A
            XOR  A
            LD   (ProofCase),A
            HALT

ProofCompileFailure: LD A,1
            JR   ProofFail
ProofCommitFailure:  LD A,2
            JR   ProofFail
ProofBeginFailure:   LD A,3
            JR   ProofFail
ProofContextFailure: LD A,4
            JR   ProofFail
ProofMapFailure:     LD A,5
            JR   ProofFail
ProofLogFailure:     LD A,6
            JR   ProofFail
ProofRegionFailure:  LD A,(ProofCase)
            JR   ProofFail
ProofLoadedFailure:  LD A,(ProofCase)
            JR   ProofFail
ProofAtomicFailure:  LD A,(ProofCase)
            JR   ProofFail
ProofConfigurationFailure: LD A,(ProofCase)
ProofFail:
            LD   (ProofCase),A
            LD   A,$E1
            LD   (ProofStatus),A
            HALT

; Reserve A bytes atomically in the bounded proof-only operation log.
.routine in A out A,IY,carry,zero clobbers sign,parity,halfCarry,DE,HL
AdapterReserve:
            LD   E,A
            LD   A,(AdapterFailureCountdown)
            OR   A
            JR   Z,AdapterReserveCapacity
            DEC  A
            LD   (AdapterFailureCountdown),A
            JR   NZ,AdapterReserveCapacity
            LD   A,DiagnosticTargetOutput
            SCF
            RET
AdapterReserveCapacity:
            LD   A,E
            LD   D,0
            LD   IY,(AdapterCursor)
            PUSH IY
            POP  HL
            ADD  HL,DE
            LD   DE,AdapterLogLimit
            OR   A
            SBC  HL,DE
            JR   C,AdapterReserveReady
            JR   Z,AdapterReserveReady
            LD   A,DiagnosticTargetOutput
            SCF
            RET
AdapterReserveReady:
            ADD  HL,DE
            LD   (AdapterCursor),HL
            OR   A
            RET

.routine in IX out A,carry,zero clobbers sign,parity,halfCarry,BC,DE,HL,IY
TargetSinkBegin:
            LD   HL,AdapterCapturedBegin
            LD   B,TargetDescriptorSize
TargetSinkBeginCopy:
            LD   A,(IX+0)
            LD   (HL),A
            INC  IX
            INC  HL
            DJNZ TargetSinkBeginCopy
            LD   A,1
            LD   (AdapterOpen),A
            OR   A
            RET

.routine in A,C,HL out A,carry,zero clobbers sign,parity,halfCarry,DE
TargetSinkImageByte:
            PUSH IY
            PUSH AF
            PUSH BC
            PUSH HL
            LD   A,7
            CALL AdapterReserve
            JR   C,TargetSinkImageByteReserveFailure
            POP  HL
            POP  BC
            POP  AF
.if DebugHooks
            OUT  (DebugTraceImageBytePort),A
.endif
            LD   (IY+0),1
            LD   (IY+1),C
            LD   (IY+2),L
            LD   (IY+3),H
            LD   (IY+4),1
            LD   (IY+5),0
            LD   (IY+6),A
            POP  IY
            OR   A
            RET
TargetSinkImageByteFailure:
            POP  IY
            RET
TargetSinkImageByteReserveFailure:
            LD   E,A
            POP  HL
            POP  BC
            POP  AF
            POP  IY
            LD   A,E
            SCF
            RET

.routine in A,BC,DE,HL,IX out A,carry,zero clobbers sign,parity,halfCarry,BC,DE,HL,IX,IY
TargetSinkRuntimeImage:
            PUSH AF
            LD   A,3
            LD   (AdapterRuntimeKind),A
            POP  AF
            JR   TargetSinkRuntimeSelected
.routine in A,BC,DE,HL,IX out A,carry,zero clobbers sign,parity,halfCarry,BC,DE,HL,IX,IY
TargetSinkRuntimeInitialImage:
            PUSH AF
            LD   A,4
            LD   (AdapterRuntimeKind),A
            POP  AF
TargetSinkRuntimeSelected:
            LD   (AdapterRuntimeBank),A
            LD   (AdapterRuntimeLength),BC
            LD   (AdapterRuntimeIdentity),DE
            LD   (AdapterRuntimeAddress),HL
            LD   (AdapterRuntimeContext),IX
            LD   A,8+TargetContextSize
            CALL AdapterReserve
            RET  C
            LD   A,(AdapterRuntimeBank)
            LD   BC,(AdapterRuntimeLength)
            LD   DE,(AdapterRuntimeIdentity)
            LD   HL,(AdapterRuntimeAddress)
            LD   IX,(AdapterRuntimeContext)
            LD   A,(AdapterRuntimeKind)
            LD   (IY+0),A
            LD   A,(AdapterRuntimeBank)
            LD   (IY+1),A
            LD   (IY+2),L
            LD   (IY+3),H
            LD   (IY+4),C
            LD   (IY+5),B
            LD   (IY+6),E
            LD   (IY+7),D
            LD   (AdapterRuntimeLog),IY
            PUSH IY
            POP  HL
            LD   DE,8
            ADD  HL,DE
            EX   DE,HL
            PUSH IX
            POP  HL
            LD   BC,TargetContextSize
            LDIR
            LD   IY,(AdapterRuntimeLog)
            PUSH IY
            POP  HL
            LD   DE,8
            ADD  HL,DE
            LD   DE,AdapterCapturedContext
            LD   BC,TargetContextSize
            LDIR
            LD   IY,(AdapterRuntimeLog)
            OR   A
            RET

.routine in A,C,HL out A,carry,zero clobbers sign,parity,halfCarry,DE
TargetSinkPatchByte:
            PUSH IY
            PUSH AF
            PUSH BC
            PUSH HL
            LD   A,7
            CALL AdapterReserve
            JR   C,TargetSinkPatchByteReserveFailure
            POP  HL
            POP  BC
            POP  AF
            LD   (IY+0),2
            LD   (IY+1),C
            LD   (IY+2),L
            LD   (IY+3),H
            LD   (IY+4),1
            LD   (IY+5),0
            LD   (IY+6),A
            POP  IY
            OR   A
            RET
TargetSinkPatchByteFailure:
            POP  IY
            RET
TargetSinkPatchByteReserveFailure:
            LD   E,A
            POP  HL
            POP  BC
            POP  AF
            POP  IY
            LD   A,E
            SCF
            RET

.routine in C,DE,HL out A,carry,zero clobbers sign,parity,halfCarry
TargetSinkPatchWord:
            PUSH IY
            PUSH BC
            PUSH DE
            PUSH HL
            LD   A,8
            CALL AdapterReserve
            POP  HL
            POP  DE
            POP  BC
            JR   C,TargetSinkPatchWordFailure
            LD   (IY+0),2
            LD   (IY+1),C
            LD   (IY+2),E
            LD   (IY+3),D
            LD   (IY+4),2
            LD   (IY+5),0
            LD   (IY+6),L
            LD   (IY+7),H
            POP  IY
            OR   A
            RET
TargetSinkPatchWordFailure:
            POP  IY
            RET

.routine in IX out A,carry,zero clobbers sign,parity,halfCarry,BC,DE,HL,IY
TargetSinkMapFlat:
            LD   A,(AdapterMapFailure)
            OR   A
            JR   Z,TargetSinkMapReady
            LD   A,DiagnosticTargetOutput
            SCF
            RET
TargetSinkMapReady:
            LD   HL,AdapterCapturedMap
            LD   B,TargetMapSize
TargetSinkMapCopy:
            LD   A,(IX+0)
            LD   (HL),A
            INC  IX
            INC  HL
            DJNZ TargetSinkMapCopy
            OR   A
            RET

.routine in HL,IX,IY out A,carry,zero clobbers sign,parity,halfCarry,BC,DE,HL,IX,IY
TargetSinkMapBanked:
            LD   (AdapterMapRoPointer),HL
            LD   A,(IX+TargetDescriptorBankCount)
            LD   B,A
            LD   C,A
            LD   HL,AdapterCapturedBankCursors
            LD   DE,AdapterCapturedBankRemaining
TargetSinkMapBankedCursorLoop:
            LD   A,(IY+0)
            LD   (HL),A
            INC  HL
            LD   A,(IY+1)
            LD   (HL),A
            INC  HL
            LD   A,(IY+2)
            LD   (DE),A
            INC  DE
            LD   A,(IY+3)
            LD   (DE),A
            INC  DE
            PUSH DE
            LD   DE,TargetBankStateSize
            ADD  IY,DE
            POP  DE
            DJNZ TargetSinkMapBankedCursorLoop
            LD   HL,(AdapterMapRoPointer)
            LD   DE,AdapterCapturedBankRoLengths
            LD   A,C
            ADD  A,A
            LD   B,A
TargetSinkMapBankedRoLoop:
            LD   A,(HL)
            LD   (DE),A
            INC  HL
            INC  DE
            DJNZ TargetSinkMapBankedRoLoop
            OR   A
            RET

.routine out A,carry,zero clobbers sign,parity,halfCarry
TargetSinkCommit:
            LD   A,(AdapterCommitFailure)
            OR   A
            JR   Z,TargetSinkCommitReady
            LD   A,DiagnosticTargetOutput
            SCF
            RET
TargetSinkCommitReady:
            LD   A,1
            LD   (AdapterCommitted),A
            OR   A
            RET

.routine out A,carry,zero clobbers sign,parity,halfCarry
TargetSinkAbort:
            LD   A,(AdapterAborted)
            INC  A
            LD   (AdapterAborted),A
            OR   A
            RET

; Direct proof calls do not enter through the public compiler boundary. These
; wrappers plant their ordinary CALL continuation as the diagnostic return SP,
; so both success and a nonlocal diagnostic return to the same proof site.
.routine in DE,HL out A,carry,zero clobbers sign,parity,halfCarry,HL
ProofCallTargetValidateRegion:
            LD   (CompilerAbortSp),SP
            JP   TargetValidateRegion

.routine out A,carry,zero clobbers sign,parity,halfCarry,BC,DE,HL
ProofCallTargetClassifyFlatLayout:
            LD   (CompilerAbortSp),SP
            JP   TargetClassifyFlatLayout

; Called only while ProofStart owns StackTop. The helper's return address is
; the sole expected two-byte displacement from that root stack pointer.
.routine out A,BC,DE,HL,carry,zero clobbers sign,parity,halfCarry
ProofCompilerStackExact:
            LD   HL,0
            ADD  HL,SP
            LD   DE,StackTop-2
            OR   A
            SBC  HL,DE
            RET

ProofStatus: .db 0
ProofCase:   .db 0
AdapterOpen: .db 0
AdapterCommitted: .db 0
AdapterAborted:   .db 0
AdapterCursor:    .dw 0
AdapterLogLength: .dw 0
AdapterLoadedLogLength: .dw 0
AdapterTrapLogLength: .dw 0
AdapterUnhandledLogLength: .dw 0
AdapterBankedLogLength: .dw 0
AdapterEntry1LogLength: .dw 0
AdapterBankedTrapLogLength: .dw 0
AdapterChapter21LogLength: .dw 0
AdapterFailedLogLength: .dw 0
AdapterFailureCountdown: .db 0
AdapterMapFailure:       .db 0
AdapterCommitFailure:    .db 0
AdapterSavedDiagnostic:  .db 0
AdapterCapturedBegin:   .ds TargetDescriptorSize
AdapterCapturedContext: .ds TargetContextSize
AdapterCapturedBankCursors: .ds TargetBankCapacity*2
AdapterCapturedBank0Cursor .equ AdapterCapturedBankCursors
AdapterCapturedBank1Cursor .equ AdapterCapturedBankCursors+2
AdapterCapturedBankRemaining: .ds TargetBankCapacity*2
AdapterCapturedBank0Remaining .equ AdapterCapturedBankRemaining
AdapterCapturedBank1Remaining .equ AdapterCapturedBankRemaining+2
AdapterCapturedBankRoLengths: .ds TargetBankCapacity*2
AdapterCapturedBank0RoLength .equ AdapterCapturedBankRoLengths
AdapterCapturedBank1RoLength .equ AdapterCapturedBankRoLengths+2
AdapterMapRoPointer: .dw 0
AdapterCapturedMap:     .ds TargetMapSize
AdapterCapturedBankedMapLength: .dw 0
AdapterCapturedBankedMap: .ds 1
AdapterSuccessMap:      .ds TargetMapSize
AdapterTrapMap:         .ds TargetMapSize
AdapterUnhandledMap:    .ds TargetMapSize
AdapterTrapUsedLength       .equ AdapterTrapMap+$03
AdapterTrapCodeLength       .equ AdapterTrapMap+$0B
AdapterUnhandledUsedLength  .equ AdapterUnhandledMap+$03
AdapterUnhandledCodeLength  .equ AdapterUnhandledMap+$0B
AdapterCapturedRuntimeBase .equ AdapterCapturedContext+$00
AdapterCapturedStateBase   .equ AdapterCapturedContext+$06
AdapterCapturedUsedLength  .equ AdapterCapturedMap+$03
AdapterCapturedCodeLength  .equ AdapterCapturedMap+$0B
AdapterRuntimeBank:     .db 0
AdapterRuntimeKind:     .db 0
AdapterRuntimeLength:   .dw 0
AdapterRuntimeIdentity: .dw 0
AdapterRuntimeAddress:  .dw 0
AdapterRuntimeContext:  .dw 0
AdapterRuntimeLog:      .dw 0
AdapterRuntimeContextPointer .equ AdapterRuntimeContext
ProofEnd:

AdapterLoadedLogBase    .equ $99F0
AdapterSuccessLogBase   .equ $9CF0
AdapterTrapLogBase      .equ $A0C0
AdapterUnhandledLogBase .equ $A5C0
AdapterBankedTrapLogBase .equ $ACC0
AdapterLogBase          .equ $B4C0
AdapterFailedLogBase    .equ $C6C0
AdapterEntry1LogBase    .equ $CBC0
AdapterChapter21LogBase .equ $D0C0
AdapterLogLimit         .equ $F000
