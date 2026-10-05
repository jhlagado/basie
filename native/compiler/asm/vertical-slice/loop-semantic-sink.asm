; Checked semantic-operation buffer for the counted-loop and array slices.

.if AggregateCallSlices
.else
.routine out carry,zero clobbers sign,parity,halfCarry,A,HL
SemanticSinkReset:
            LD   HL,SemanticPayloadBase
            LD   (SinkCursor),HL
            XOR  A
            LD   (SinkOperationCount),A
            LD   (SemanticBufferBase),A
            RET
.endif

.routine in A out A,carry,zero clobbers sign,parity,halfCarry,B,DE,HL
SemanticSinkPut:
            LD   B,A
            LD   HL,(SinkCursor)
            LD   DE,SemanticBufferLimit
            OR   A
            SBC  HL,DE
            ADD  HL,DE
            JR   Z,SemanticSinkPutFull
SemanticSinkPutRoom:
            LD   A,B
            LD   (HL),A
            INC  HL
            LD   (SinkCursor),HL
            OR   A
            RET
SemanticSinkPutFull:
            CALL SetDiagInline
            .db  DiagnosticSinkCapacity

.if TargetStreamingOutput
.routine in A,HL out A,HL,carry,zero clobbers sign,parity,halfCarry,B,DE
SemanticSinkPutPreserveHL:
            PUSH HL
            CALL SemanticSinkPut
            POP  HL
            RET
.endif

.routine in A out A,carry,zero clobbers sign,parity,halfCarry,B,DE,HL
SemanticSinkOperation:
            LD   B,A
            LD   A,(SinkOperationCount)
            CP   255
            JR   Z,SemanticSinkPutFull
            LD   A,B
            CALL SemanticSinkPut
            RET  C
            LD   HL,SinkOperationCount
            INC  (HL)
            XOR  A
            RET

.routine out A,carry,zero clobbers sign,parity,halfCarry
SemanticSinkFinish:
            LD   A,(SinkOperationCount)
            LD   (SemanticBufferBase),A
            OR   A
            RET
