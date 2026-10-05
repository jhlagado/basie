; Packed LL(1) interpreter for the complete Stage 7 grammar.
; Token ordinals occupy $00..$3F, nonterminals $40..$7F, and explicit
; semantic or retained-expression actions $80..$FE. Productions store their
; right sides in reverse order so one bounded copy pushes a complete rule.

HybridLL1StackCapacity .equ 64
.if AggregateCallSlices
.if TargetStreamingOutput
HybridLL1StackDepth    .equ TargetCompilerWorkspaceEnd
.else
HybridLL1StackDepth    .equ SourceMultipartWorkspaceEnd
.endif
.else
HybridLL1StackDepth    .equ Stage7CompilerWorkspaceEnd
.endif
HybridLL1StackBase     .equ HybridLL1StackDepth+1
.if AggregateCallSlices
.if TargetStreamingOutput
HybridLL1WorkspaceEnd  .equ TargetWorkspaceEnd
.else
HybridLL1WorkspaceEnd  .equ HybridLL1StackBase+HybridLL1StackCapacity
.endif
.else
HybridLL1WorkspaceEnd  .equ HybridLL1StackBase+HybridLL1StackCapacity
.endif
DiagnosticParserCapacity .equ 87

; Push the start symbol and run until the grammar stack is empty. Explicit
; actions return through HybridLL1ActionReturn with carry reporting failure.
.routine out A,BC,DE,HL,carry,zero clobbers sign,parity,halfCarry,IX,IY
HybridLL1Parse:
            XOR  A
            LD   (HybridLL1StackDepth),A
            LD   A,HybridLL1StartSymbol
            CALL HybridLL1PushSymbol
.if CompilerDiagnosticReturns
            RET  C
.endif
HybridLL1Loop:
            LD   A,(HybridLL1StackDepth)
            OR   A
            RET  Z
            CALL HybridLL1PopSymbol
            CP   $40
            JR   C,HybridLL1Terminal
            CP   $80
            JR   C,HybridLL1Nonterminal

            ; Action ordinal -> absolute routine address. A retains the
            ; zero-based ordinal for parameterised physical handlers.
            SUB  $80
            LD   L,A
            LD   H,0
            ADD  HL,HL
            LD   DE,HybridLL1ActionDirectory
            ADD  HL,DE
            LD   E,(HL)
            INC  HL
            LD   D,(HL)
            EX   DE,HL
            LD   DE,HybridLL1ActionReturn
            PUSH DE
            JP   (HL)
HybridLL1ActionReturn:
.if CompilerDiagnosticReturns
            RET  C
.endif
            JR   HybridLL1Loop

HybridLL1Terminal:
            LD   E,A
            CALL ParserExpect
.if CompilerDiagnosticReturns
            RET  C
.endif
            JR   HybridLL1Loop

HybridLL1Nonterminal:
            SUB  $40
            LD   L,A
            LD   H,0
            ADD  HL,HL
            LD   DE,HybridLL1RowDirectory
            ADD  HL,DE
            LD   E,(HL)
            INC  HL
            LD   A,(HL)
            PUSH AF
            LD   D,0
            LD   HL,HybridLL1Rows
            ADD  HL,DE
            PUSH HL
            CALL ParserPeek
            POP  HL
.if CompilerDiagnosticBranches
            JR   C,HybridLL1PredictionPeekFailure
.endif
            LD   C,A
HybridLL1PredictionNext:
            LD   B,(HL)
            INC  HL
HybridLL1PredictionToken:
            LD   A,(HL)
            LD   E,A
            AND  $7F
            CP   C
            JR   Z,HybridLL1PredictionFound
            INC  HL
            BIT  7,E
            JR   Z,HybridLL1PredictionToken
            BIT  7,B
            JR   NZ,HybridLL1PredictionFailure
            JR   HybridLL1PredictionNext
HybridLL1PredictionFailure:
            POP  AF
            JP   CompilerSetDiagnostic
.if CompilerDiagnosticBranches
HybridLL1PredictionPeekFailure:
            POP  BC
            RET
.endif
HybridLL1PredictionFound:
            POP  AF
            LD   A,B
            AND  $7F
            CALL HybridLL1PushProduction
.if CompilerDiagnosticReturns
            RET  C
.endif
            JR   HybridLL1Loop

; A is a production ordinal. Adjacent directory offsets delimit its body.
.routine in A out A,BC,DE,HL,carry,zero clobbers sign,parity,halfCarry
HybridLL1PushProduction:
            CP   HybridLL1ProductionSplit
            LD   DE,HybridLL1Productions
            LD   HL,HybridLL1ProductionDirectory
            JR   C,HybridLL1ProductionBaseReady
            SUB  HybridLL1ProductionSplit
            LD   DE,HybridLL1ProductionsHigh
            LD   HL,HybridLL1ProductionDirectoryHigh
HybridLL1ProductionBaseReady:
            LD   C,A
            LD   B,0
            ADD  HL,BC
            LD   C,(HL)
            INC  HL
            LD   A,(HL)
            SUB  C
            LD   B,A
            LD   A,C
            LD   L,A
            LD   H,0
            ADD  HL,DE
            LD   A,B
            OR   A
            RET  Z
            LD   A,(HybridLL1StackDepth)
            LD   C,A
            ADD  A,B
            JR   C,HybridLL1CapacityFailure
            CP   HybridLL1StackCapacity+1
            JR   NC,HybridLL1CapacityFailure
            LD   (HybridLL1StackDepth),A
            PUSH HL
            LD   A,C
            LD   E,A
            LD   D,0
            LD   HL,HybridLL1StackBase
            ADD  HL,DE
            EX   DE,HL
            POP  HL
            LD   C,B
            LD   B,0
            LDIR
            XOR  A
            RET

.routine in A out A,carry,zero clobbers sign,parity,halfCarry,C,DE,HL
HybridLL1PushSymbol:
            LD   C,A
            LD   A,(HybridLL1StackDepth)
            CP   HybridLL1StackCapacity
            JR   NC,HybridLL1CapacityFailure
            LD   L,A
            LD   H,0
            LD   DE,HybridLL1StackBase
            ADD  HL,DE
            LD   (HL),C
            LD   HL,HybridLL1StackDepth
            INC  (HL)
            XOR  A
            RET

.routine out A,carry,zero clobbers sign,parity,halfCarry,DE,HL
HybridLL1PopSymbol:
            LD   A,(HybridLL1StackDepth)
            DEC  A
            LD   (HybridLL1StackDepth),A
            LD   L,A
            LD   H,0
            LD   DE,HybridLL1StackBase
            ADD  HL,DE
            LD   A,(HL)
            OR   A
            RET

HybridLL1CapacityFailure:
            CALL SetDiagInline
            .db  DiagnosticParserCapacity

HybridLL1EngineEnd:
            .include "../../grammar/stage7-tables.asmi"
HybridLL1TablesEnd:
