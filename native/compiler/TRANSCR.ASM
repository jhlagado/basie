;==========================================================================
;  Semantic transcript
;==========================================================================
;
;  The parser does not generate code. Every grammar action and expression
;  routine appends operations to this transcript instead, and code
;  generation replays it once parsing has succeeded. An operation is one
;  opcode byte (an OP_ ordinal) followed by the operand bytes that opcode
;  defines; the transcript holds no length bytes, so the replay must know
;  each operation's width.
;
;  Principal entries:
;    TR_OPER   append an opcode and count it as one operation
;    TR_PUT    append one operand byte
;    TR_PUTHL  append one operand byte, preserving HL
;    TR_CLOSE  publish the operation count for replay
;
;  Layout (STATE.ASM). TR_BASE is one byte that receives the operation
;  count when the transcript is closed; the 511 bytes from TR_BODY up to
;  TR_LIM hold the operations. TR_PTR is the next free byte and TR_CNT the
;  running count. Both overlay diagnostic fields that are dead until a
;  diagnostic ends the parse, so no live operation survives a diagnostic.
;  PR_RESET empties the transcript before each compilation.
;
;  Capacity is 511 bytes and 255 operations for the whole program; either
;  overflow raises DG_SINK. Streaming the transcript per routine (native
;  compiler plan §2) is what will lift this limit.

;@ROUTINE IN A OUT A,CARRY,ZERO CLOBBERS SIGN,PARITY,HALFCARRY,B,DE,HL
; Append the byte in A at TR_PTR and advance the cursor. On success A still
; holds the byte and carry is clear; a full buffer raises DG_SINK.

TR_PUT:
    LD   B,A                       ; Keep the byte while the cursor is compared.
    LD   HL,(TR_PTR)               ; Fetch the next free transcript byte.
    LD   DE,TR_LIM                 ; The buffer ends at TR_LIM, exclusive.
    OR   A                         ; Clear carry for an exact comparison.
    SBC  HL,DE                     ; Zero when the cursor has reached the end.
    ADD  HL,DE                     ; Restore the cursor; ADD leaves Z untouched.
    JR   Z,TR_FULL                 ; No room for another byte.
    LD   A,B                       ; Recover the byte to append.
    LD   (HL),A                    ; Store it at the cursor.
    INC  HL                        ; Advance past the stored byte.
    LD   (TR_PTR),HL               ; Publish the new cursor.
    OR   A                         ; Report success with carry clear.
    RET                            ; Return with the byte still in A.

;@ROUTINE NORETURN
; Raise DG_SINK: the transcript has no room for another byte or operation.

TR_FULL:
    CALL DG_RAISE                  ; Report the overflow; parsing ends here.
    DB   DG_SINK                   ; Transcript capacity diagnostic.

;@ROUTINE IN A,HL OUT A,CARRY,ZERO CLOBBERS SIGN,PARITY,HALFCARRY,B,DE
; TR_PUT for callers that walk a record with HL: the byte in A is appended
; and HL is preserved.

TR_PUTHL:
    PUSH HL                        ; Save the caller's record pointer.
    CALL TR_PUT                    ; Append the byte in A.
    POP  HL                        ; Restore the record pointer.
    RET                            ; Return with TR_PUT's result.

;@ROUTINE IN A OUT A,CARRY,ZERO CLOBBERS SIGN,PARITY,HALFCARRY,B,DE,HL
; Append opcode A and count one more operation. The count is a byte, so a
; 256th operation raises DG_SINK. Returns A zero and carry clear.

TR_OPER:
    LD   B,A                       ; Keep the opcode while the count is checked.
    LD   A,(TR_CNT)                ; Fetch the operations appended so far.
    CP   255                       ; A byte count cannot record a 256th operation.
    JR   Z,TR_FULL                 ; Raise DG_SINK at the operation limit.
    LD   A,B                       ; Recover the opcode.
    CALL TR_PUT                    ; Append it; a full buffer does not return.
    RET  C                         ; Dead: TR_PUT raises rather than return carry.
    LD   HL,TR_CNT                 ; Address the running operation count.
    INC  (HL)                      ; Count the operation just appended.
    XOR  A                         ; Report success with A zero and carry clear.
    RET                            ; The caller now appends the operands.

;@ROUTINE OUT A,CARRY,ZERO CLOBBERS SIGN,PARITY,HALFCARRY
; Publish the running count in TR_BASE, where the replay reads it. Called
; once, after the whole program has parsed.

TR_CLOSE:
    LD   A,(TR_CNT)                ; Fetch the final operation count.
    LD   (TR_BASE),A               ; Publish it as the transcript's leading byte.
    OR   A                         ; Return carry clear.
    RET                            ; The transcript is ready for replay.
