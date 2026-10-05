;==========================================================================
;  CRC-16
;==========================================================================
;
;  CRC-16/CCITT-FALSE (object format §7.6): polynomial $1021, initial
;  $FFFF, no reflection, computed a bit at a time. Several CRCs run at once,
;  each a word: CRC_VAL for the directory or library being read, and the
;  line stream's, the line table's and the image's, which LINES.ASM keeps.
;
;  Principal entries:
;    CRC_NEW   start CRC_VAL
;    CRC_ADD   add A to CRC_VAL
;    CRC_FOLD  add A to the CRC word at HL

CRC_VAL:                       ; The CRC of the directory or library being read.
    DW   $FFFF                     ; CRC_NEW sets it before each use.

;@ROUTINE OUT HL
; Start CRC_VAL at the initial value $FFFF.

CRC_NEW:                       ; Called at the start of each checked file part.
    LD   HL,$FFFF                  ; The CRC's initial value.
    LD   (CRC_VAL),HL              ; Start the running CRC.
    RET                            ; HL is $FFFF.

;@ROUTINE IN A
; Add A to CRC_VAL, keeping every register and the flags.

CRC_ADD:                       ; A is the byte just read.
    PUSH HL                        ; Keep the caller's HL.
    LD   HL,CRC_VAL                ; Fold A into the running CRC.
    CALL CRC_FOLD                  ; It keeps A and every other register.
    POP  HL                        ; Recover HL.
    RET                            ; CRC_VAL includes A.

;@ROUTINE IN A,HL
; Add A to the CRC word at HL, keeping every register and the flags.

CRC_FOLD:                      ; HL is a CRC word, A the next byte.
    PUSH AF                        ; The fold uses A and the flags,
    PUSH BC                        ; B as the bit count,
    PUSH DE                        ; DE as the word's address,
    PUSH HL                        ; and HL as the CRC.
    LD   E,(HL)                    ; Fetch the CRC's low byte,
    INC  HL                        ; then
    LD   D,(HL)                    ; its high byte.
    EX   DE,HL                     ; HL is the CRC, DE the word's address + 1.
    XOR  H                         ; The byte enters at the top of the CRC.
    LD   H,A                       ; H is the high byte with the data mixed in.
    LD   B,8                       ; One step per bit, most significant first.
.BIT:                          ; HL is the CRC during the division.
    ADD  HL,HL                     ; Shift it; carry is the bit shifted out.
    JR   NC,.NEXT                  ; A zero bit leaves the remainder alone.
    LD   A,H                       ; A one bit subtracts the polynomial:
    XOR  $10                       ; $1021's high byte
    LD   H,A                       ; from H,
    LD   A,L                       ; and
    XOR  $21                       ; its low byte
    LD   L,A                       ; from L.
.NEXT:                         ; The bit is done.
    DJNZ .BIT                      ; Until all eight are.
    EX   DE,HL                     ; DE is the CRC, HL the word's address + 1.
    LD   (HL),D                    ; Store the high byte,
    DEC  HL                        ; then
    LD   (HL),E                    ; the low byte.
    POP  HL                        ; Recover HL,
    POP  DE                        ; DE,
    POP  BC                        ; BC,
    POP  AF                        ; and A and the flags.
    RET                            ; Only the CRC word has changed.
