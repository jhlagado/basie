;==========================================================================
;  Blob writer test
;==========================================================================
;
;  A CP/M program that writes HELLO.$DR, $BY, $LN and $NM through the blob
;  writer, describing the same program as the reference compiler's
;  compilation of tests/conformance/basics/hello.bsi: one code blob, main,
;  with a reference to itself and one to the library's BDOS helper, two
;  line entries, the entry and limits records, and main's name.
;  tests/blob_writer_test.ts compares the four streams with the reference's.

%INCLUDE "BLOBMEM.ASM"
%INCLUDE "../../native/compiler/OUT.ASM"
%INCLUDE "../../native/compiler/BLOB.ASM"
%INCLUDE "../../native/compiler/BLEND.ASM"
%INCLUDE "../../native/compiler/BLOPEN.ASM"
%INCLUDE "../../native/compiler/BLCLOSE.ASM"
%INCLUDE "../../native/compiler/SPILL.ASM"

;@ROUTINE NORETURN
; Write the four streams and warm boot.

BT_START:                      ; Entered from the jump at $0100.
    LD   SP,($0006)                ; The stack below the BDOS entry.
    LD   HL,BT_HEAD                ; The directory header,
    LD   DE,BT_NAME                ; the streams' drive and name,
    LD   A,BL_LNOUT|BL_NMOUT       ; and all four streams.
    CALL BL_OPEN                   ; Open them.
    XOR  A                         ; Part 0
    LD   HL,BT_PART                ; is HELLO.BSI,
    LD   B,9                       ; nine characters.
    CALL BL_PART                   ; Name it.
    LD   HL,$0400                  ; Main is the first program ordinal,
    XOR  A                         ; a code blob, not a root.
    CALL BL_BEGIN                  ; Start it.
    XOR  A                         ; Part 0,
    LD   HL,BT_L6                  ; 6:5: the routine's name.
    CALL BL_LINE                   ; Mark it.
    LD   HL,BT_CODE                ; The bytes,
    LD   B,13                      ; up to the first statement.
    CALL .BYTES                    ; Append them.
    PUSH HL                        ; Keep the place across the line entry.
    XOR  A                         ; Part 0,
    LD   HL,BT_L7                  ; 7:5: writeText.
    CALL BL_LINE                   ; Mark it.
    POP  HL                        ; The bytes again,
    LD   B,13                      ; up to the self-reference.
    CALL .BYTES                    ; Append them.
    INC  HL                        ; The placeholder's two bytes
    INC  HL                        ; come from BL_REF.
    PUSH HL                        ; Keep the place.
    XOR  A                         ; ABS16
    LD   HL,$0400                  ; to main itself,
    LD   DE,46                     ; at its literal, offset 46.
    CALL BL_REF                    ; Append the reference.
    POP  HL                        ; The bytes again,
    LD   B,2                       ; two of them.
    CALL .BYTES                    ; Append them.
    INC  HL                        ; Skip the next placeholder.
    INC  HL                        ; Both bytes.
    PUSH HL                        ; Keep the place.
    XOR  A                         ; ABS16
    LD   HL,32                     ; to library ordinal 32,
    LD   DE,0                      ; without an addend.
    CALL BL_REF                    ; Append the reference.
    POP  HL                        ; The rest of the bytes,
    LD   B,23                      ; to the end of the literal.
    CALL .BYTES                    ; Append them.
    CALL BL_END                    ; Write the blob.
    LD   HL,$0400                  ; The program starts at main.
    CALL BL_ENTRY                  ; Record it.
    LD   HL,106                    ; Stack reserve 106,
    LD   DE,8                      ; largest frame 8,
    XOR  A                         ; no flags.
    CALL BL_LIMIT                  ; Record them.
    LD   HL,$0400                  ; Main's
    LD   DE,BT_MAIN                ; name,
    LD   B,4                       ; four characters.
    CALL BL_NAME                   ; Record it.
    CALL BL_CLOSE                  ; Write the trailers.
    JP   0                         ; Warm boot.

;@ROUTINE IN B,HL OUT HL CLOBBERS A,B,CARRY,ZERO,SIGN,PARITY,HALFCARRY
; Append the B bytes at HL to the blob.

.BYTES:                        ; HL is the next byte.
    LD   A,(HL)                    ; Append it
    CALL BL_BYTE                   ; to the blob.
    INC  HL                        ; Move to the next.
    DJNZ .BYTES                    ; Until B are done.
    RET                            ; HL is after them.

;@ROUTINE IN A,HL OUT CARRY CLOBBERS A,BC,DE,HL,IX,ZERO,SIGN,PARITY,HALFCARRY
; The SPILL overlay's entry A, here in the image: SP_WRITE or SP_RBACK.

OV_SCALL:                      ; A is the entry.
    OR   A                         ; Zero:
    JP   Z,SP_WRITE                ; the spill;
    JP   SP_RBACK                  ; three: reading it back.

;@ROUTINE NORETURN
; A full disk or an overflowing blob: print F or O and warm boot.

OUT_FAIL:                      ; The disk or directory is full.
    LD   E,'F'                     ; Report it.
    JR   BT_STOP                   ; And stop.
BL_OVER:                       ; A blob reached 16K,
MM_FULL:                       ; or the free memory is full.
    LD   E,'O'                     ; Report it.
BT_STOP:                       ; E is the report.
    LD   C,2                       ; Console output.
    CALL $0005                     ; Print it.
    JP   0                         ; Warm boot.

BT_HEAD:                       ; The program directory's header.
    DB   "BSIP",1,0                ; Magic, version 1.0.
    DW   1,1,1,$5524,1,$0400       ; Stamp, runtime, helpers, key, profile, base.
    DB   0,0                       ; Flags and padding.
BT_NAME:                       ; The streams' drive and name.
    DB   0,"HELLO   "              ; The current drive.
BT_PART:                       ; Part 0's name.
    DB   "HELLO.BSI"               ; As the reference names it.
BT_MAIN:                       ; Main's name.
    DB   "main"                    ; As the reference spells it.
BT_CODE:                       ; Main's bytes, with zero placeholders.
    DB   $DD,$E5,$DD,$21,$00,$00,$DD,$39,$21,$F8,$FF,$39,$F9
    DB   $21,$01,$00,$11,$00,$00,$D5,$E5,$11,$07,$00,$D5,$21
    DB   $00,$00,$E5,$CD,$00,$00,$38,$03,$B7,$18,$00,$DD,$F9
    DB   $DD,$E1,$C9,$08,$00,$2A,$00,$07,$48,$65,$6C,$6C,$6F
    DB   $0D,$0A,$00
BT_L6:                         ; Line 6, column 5: main's name.
    DW   6,5                       ; As a position's line and column.
BT_L7:                         ; Line 7, column 5: writeText.
    DW   7,5                       ; As a position's line and column.
