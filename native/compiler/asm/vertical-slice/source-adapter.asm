; Memory-backed implementation of the ordered source-byte adapter.

.routine in A,DE,HL out A,carry,zero clobbers sign,parity,halfCarry,BC,DE,HL
SourceInitialize:
            LD   (SourcePartId),A
            LD   (SourceCursor),HL
            EX   DE,HL
            LD   (SourceEnd),HL
            LD   HL,0
            LD   (SourceOffset),HL
            INC  HL
            LD   (SourceLine),HL
            LD   (SourceColumn),HL
            XOR  A
            LD   (SourceLineHasToken),A
            LD   (SourceDelimiterDepth),A
            RET

.if AggregateCallSlices
; A is a bounded part count and HL points to five-byte descriptors containing
; stable identity, source start, and source end. The source and descriptors
; remain resident until compilation finishes.
.routine in A,HL out A,carry,zero clobbers sign,parity,halfCarry,BC,DE,HL
SourceInitializeParts:
            DEC  A
            CP   SourcePartCapacity
            JR   NC,SourcePartCapacityFailure
            LD   (SourcePartsRemaining),A
            JR   SourceLoadPart
SourcePartCapacityFailure:
            XOR  A
            LD   H,A
            LD   L,A
            LD   D,A
            LD   E,A
            CALL SourceInitialize
            CALL TokenRecordStart
            CALL SetDiagInline
            .db  DiagnosticSourcePartCapacity

; Load the descriptor at HL and retain the address of the following one.
.routine in HL out A,carry,zero clobbers sign,parity,halfCarry,BC,DE,HL
SourceLoadPart:
            LD   A,(HL)
            INC  HL
            LD   E,(HL)
            INC  HL
            LD   D,(HL)
            INC  HL
            PUSH DE
            LD   E,(HL)
            INC  HL
            LD   D,(HL)
            INC  HL
            LD   (SourcePartDescriptorCursor),HL
            POP  HL
            JR   SourceInitialize
.endif

; Return the current source byte in A. Carry denotes the separate EOF event.
.routine out A,carry,zero clobbers sign,parity,halfCarry,DE,HL
SourcePeek:
            LD   HL,(SourceCursor)
            LD   DE,(SourceEnd)
            OR   A
            SBC  HL,DE
            ADD  HL,DE
            JR   NZ,SourcePeekByte
            SCF
            RET
SourcePeekByte:
            LD   A,(HL)
            OR   A
            RET

; Consume one byte and advance byte offset and byte column. Newline handling
; is separate because LF and CRLF each advance the logical line only once.
.routine out A,carry,zero clobbers sign,parity,halfCarry,DE,HL
SourceTake:
            PUSH BC
            CALL SourcePeek
            JR   C,SourceTakeEof
            LD   B,A
            LD   HL,(SourceCursor)
            INC  HL
            LD   (SourceCursor),HL
            LD   HL,(SourceOffset)
            INC  HL
            LD   (SourceOffset),HL
            LD   HL,(SourceColumn)
            INC  HL
            LD   (SourceColumn),HL
            LD   A,B
            POP  BC
            OR   A
            RET
SourceTakeEof:
            POP  BC
            SCF
            RET

.routine out carry,zero clobbers sign,parity,halfCarry,A,HL
SourceFinishLine:
            LD   HL,(SourceLine)
            INC  HL
            LD   (SourceLine),HL
            LD   HL,1
            LD   (SourceColumn),HL
            OR   A
            RET
