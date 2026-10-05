; Bounded exact-name table for the first general scalar slice.

.if AggregateCallSlices
.else
.routine out A,carry,zero clobbers sign,parity,halfCarry
SymbolReset:
            XOR  A
            LD   (SymbolCount),A
            LD   (NextLocalSlot),A
            LD   (NextProgramSlot),A
            RET
.endif

; Compare the current NAME token with committed entries. Carry returns a
; matching entry in HL. The provisional entry at SymbolCount is invisible.
.routine out A,carry,zero,HL clobbers sign,parity,halfCarry,B,C,D,DE
SymbolFindCurrent:
            LD   A,(SymbolCount)
            OR   A
            RET  Z
            LD   C,A
            LD   HL,SymbolTableBase
SymbolFindCurrentLoop:
            CALL TokenNameRecordEquals
            RET  C
            LD   DE,SymbolEntrySize
            ADD  HL,DE
            DEC  C
            JR   NZ,SymbolFindCurrentLoop
            OR   A
            RET

; Compatibility entry for the older slices: D is class/type information and E
; is a byte-sized payload. New typed declarations call the word entry below.
.if LegacyCompilerSlices
.routine in D,E out A,carry,zero,HL clobbers sign,parity,halfCarry,B,C,D,DE
SymbolPrepareCurrent:
            LD   B,0
            LD   C,E
.endif
.routine in D,BC out A,carry,zero,HL clobbers sign,parity,halfCarry,B,C,D,DE
SymbolPrepareCurrentWord:
            PUSH BC
            PUSH DE
            CALL SymbolFindCurrent
            POP  DE
            POP  BC
            JP   C,TypedDuplicateNameFailure
            LD   A,(SymbolCount)
            CP   SymbolCapacity
            JR   NC,SymbolPrepareFull
            PUSH BC
            LD   C,A
            LD   B,0
            LD   H,0
            LD   L,C
            ADD  HL,HL
            ADD  HL,HL
            ADD  HL,BC
            ADD  HL,BC
            LD   BC,SymbolTableBase
            ADD  HL,BC
            CALL TokenRetainNameAtHL
            INC  HL
            LD   (HL),D
            INC  HL
            POP  BC
            LD   (HL),C
            INC  HL
            LD   (HL),B
            OR   A
            RET
SymbolPrepareFull:
            LD   A,DiagnosticSymbolCapacity
            JR   CompilerSetDiagnostic

; Retain A as the aggregate-type ordinal for the symbol about to be committed.
; BC remains the caller's prepared symbol payload.
.routine in A,BC out A,BC,carry,zero clobbers sign,parity,halfCarry,DE,HL
SymbolCommitTyped:
            PUSH AF
            LD   A,(SymbolCount)
            LD   E,A
            LD   D,0
            LD   HL,AggregateSymbolTypeBase
            ADD  HL,DE
            POP  AF
            LD   (HL),A
.routine out A,carry,zero clobbers sign,parity,halfCarry,HL
SymbolCommit:
            LD   HL,SymbolCount
            INC  (HL)
            XOR  A
            RET

; Return the current name's class/type in A and word payload in BC.
.routine out A,BC,carry,zero clobbers sign,parity,halfCarry,D,DE,HL
SymbolLookupCurrent:
            CALL SymbolFindCurrent
            JR   NC,SymbolLookupMissing
            INC  HL
            INC  HL
            INC  HL
            LD   A,(HL)
            INC  HL
            LD   C,(HL)
            INC  HL
            LD   B,(HL)
            OR   A
            RET
SymbolLookupMissing:
            LD   A,DiagnosticUnknownName
