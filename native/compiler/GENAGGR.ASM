;==========================================================================
;  Code generation driver and the static data image
;==========================================================================
;
;  Run the emit phase once parsing has published the semantic transcript.
;  GA_BUILD opens the target through TG_OPEN, which writes the entry jump,
;  the linked runtime and the startup code. It then appends the program's
;  static image, replays the transcript into code through GX_WALK and closes
;  the target with TG_SHUT. PR_BUILD calls it with a continuation on the
;  stack that aborts the output if a diagnostic is raised during emission.
;
;  Principal entries:
;    GA_BUILD  open the target, place the static image, emit all code, close
;    GA_PLACE  emit every aggregate constant in declaration order (banked)
;
;  AG_DATA holds the complete static image built by the parser: AG_DLEN
;  bytes of initialised program data followed by AG_ROLEN bytes of
;  aggregate constants. In a ROM layout both parts follow the runtime's
;  vector and state image, and startup copies the writable parts to RAM;
;  the constants stay in the image and are read in place. In a loaded
;  layout only the constants go here; TG_SHUT writes the writable image at
;  its RAM address after the code. BASIE.COM's shell describes a one-bank
;  ROM layout; output goes to its stub sinks until the blob writer (65.3).
;  At 65.4 this module becomes one blob per declaration.

;@ROUTINE OUT A,CARRY,ZERO CLOBBERS SIGN,PARITY,HALFCARRY,BC,DE,HL,IX,IY
; Emit the bytes of every aggregate constant once, in declaration order,
; each into the bank its symbol records. Only TG_OPENB, the banked open,
; reaches this, so BASIE.COM's one-bank target never runs it.

GA_PLACE:
    LD   A,(SY_CNT)                ; Count the committed symbols.
    OR   A                         ; Are there any at all?
    RET  Z                         ; No symbols means no constants to place.
    LD   B,A                       ; B counts the symbol records left to scan.
    LD   C,0                       ; C is the symbol index for AG_SYTAB.
    LD   IX,SY_BASE                ; IX walks the symbol records.
    LD   IY,AG_DATA                ; IY walks the staged static image.
    LD   DE,(AG_DLEN)              ; Skip the initialised-data prefix.
    ADD  IY,DE                     ; IY now addresses the first constant byte.
.SYMLOOP:                      ; Examine one symbol record.
    LD   A,(IX+3)                  ; Read the record's class byte.
    LD   D,A                       ; Keep it for its bank bits.
    AND  SY_AGGR+SY_CMASK          ; Keep the aggregate flag and storage class.
    CP   SY_AGGR+SY_CONST          ; Is this an aggregate constant?
    JR   NZ,.NEXT                  ; Other symbols own no constant bytes.
    LD   A,D                       ; Recover the class byte.
    CALL TG_SPLIT                  ; Extract the bank the constant belongs to.
    PUSH BC                        ; TG_PICK clobbers the loop counters.
    CALL TG_PICK                   ; Direct the following bytes to that bank.
    POP  BC                        ; Restore the count and the symbol index.
    LD   H,0                       ; Form the symbol index as a word.
    LD   L,C                       ; One type byte per symbol.
    LD   DE,AG_SYTAB               ; Index the parallel symbol-type table.
    ADD  HL,DE                     ; HL addresses this symbol's type ordinal.
    LD   A,(HL)                    ; Read the constant's aggregate type.
    CALL AG_SIZE                   ; HL is its size in bytes.
    EX   DE,HL                     ; DE counts the bytes still to emit.
.BYTELOOP:                     ; Emit one byte of the constant.
    LD   A,D                       ; Test the remaining count.
    OR   E                         ; Has the whole constant been emitted?
    JR   Z,.NEXT                   ; Then move on to the next symbol.
    LD   A,(IY+0)                  ; Read the next staged constant byte.
    INC  IY                        ; Constants are staged in declaration order.
    PUSH BC                        ; EM_BYTE clobbers B.
    PUSH DE                        ; EM_BYTE clobbers DE.
    CALL EM_BYTE                   ; Append the byte to the selected bank.
    POP  DE                        ; Restore the remaining count.
    POP  BC                        ; Restore the loop counters.
    DEC  DE                        ; One byte fewer to emit.
    JR   .BYTELOOP                 ; Continue with the rest of the constant.
.NEXT:                         ; Advance to the next symbol record.
    LD   DE,SY_RECB                ; Load the symbol-record stride.
    ADD  IX,DE                     ; Step IX to the next record.
    INC  C                         ; Keep the symbol index in step.
    DJNZ .SYMLOOP                  ; Scan every committed symbol.
    OR   A                         ; Report success with carry clear.
    RET                            ; Every constant has been emitted.

;@ROUTINE OUT A,CARRY,ZERO CLOBBERS SIGN,PARITY,HALFCARRY,BC,DE,HL,IX,IY
; Run the emit phase: open the target described at TG_DESC, place the static
; image, replay the transcript into code and close the target. A diagnostic
; unwinds through PR_SP; success returns carry clear from TG_SHUT.

GA_BUILD:
    LD   IX,(TG_DESC)              ; Recover the caller's target descriptor.
    CALL TG_OPEN                   ; Validate it and emit runtime and startup.
    LD   A,(TG_BCNT)               ; Read the target's bank count.
    CP   1                         ; A flat target has exactly one bank.
    JR   NZ,.CODE                  ; TG_OPENB has placed a banked image.
; TG_OPEN already selected the first read-only byte.
    LD   A,(TG_LMODE)              ; Read the layout: zero means loaded.
    OR   A                         ; Is the image loaded into RAM?
    JR   Z,.LOADED                 ; Then only the constants belong here.
    LD   HL,(EM_PTR)               ; The writable image's load address.
    CALL TG_RAM                    ; Append the runtime's vector/state image.
    JR   .ALL                      ; Data and constants follow it.
.LOADED:                       ; Place only the aggregate constants.
    LD   HL,AG_DATA                ; Start of the staged static image.
    LD   DE,(AG_DLEN)              ; Skip the initialised-data prefix.
    ADD  HL,DE                     ; HL addresses the first constant byte.
    LD   BC,(AG_ROLEN)             ; Copy exactly the constant suffix.
    JR   .COPY                     ; Emit it in one block.
.ALL:                          ; Place initialised data and constants.
    LD   HL,(AG_ROLEN)             ; Constant bytes.
    LD   BC,(AG_DLEN)              ; Plus initialised-data bytes.
    ADD  HL,BC                     ; Give the whole staged image length.
    LD   B,H                       ; Move the length to BC.
    LD   C,L                       ; EM_BLOCK takes its count in BC.
    LD   HL,AG_DATA                ; Copy from the start of the image.
.COPY:                         ; Emit BC bytes from HL.
    CALL EM_BLOCK                  ; Append the static image to the output.
.CODE:                         ; Record where generated code begins.
    LD   A,(TG_BCNT)               ; Banked targets keep per-bank cursors.
    CP   1                         ; Is this the flat target?
    JR   NZ,.BOUNDS                ; Banked code starts where TG_OPENB left it.
    LD   HL,(EM_PTR)               ; Code begins after the static image.
    LD   (TG_CODE),HL              ; Keep it for the code-length report.
    LD   A,(TG_LMODE)              ; A loaded layout must stop short of RAM.
    OR   A                         ; Is the layout loaded?
    JR   NZ,.BOUNDS                ; A ROM layout keeps TG_OPEN's limit.
    LD   HL,(TG_CCAP)              ; The code capacity up to the RAM region.
    LD   (EM_LIM),HL               ; Stop emission before the writable image.
.BOUNDS:                       ; Publish the constant region to generators.
    LD   A,(TG_BCNT)               ; Banked targets set bounds per bank.
    CP   1                         ; Is this the flat target?
    JR   NZ,.GENERATE              ; TG_PICK supplies banked bounds.
    LD   HL,(TG_CRO)               ; Run address of the constant region.
    LD   (TG_ROPOS),HL             ; Base for constant references and checks.
    LD   HL,(TG_COCAP)             ; Length of the constant region.
    LD   (TG_ROCAP),HL             ; Capacity passed to region checks.
.GENERATE:                     ; Replay the transcript into code.
    CALL GX_WALK                   ; Dispatch every semantic operation.
    JP   TG_SHUT                   ; Resolve fixups and close the output.
