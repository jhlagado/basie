;==========================================================================
;  Blob writer edge cases
;==========================================================================
;
;  Writes EDGE.$DR, $BY, $LN and $NM with the encodings hello does not
;  reach: a reference delta above 62, the LO8, HI8 and SIZE16 forms, two
;  line entries at one offset in different parts, a replaced entry, a line
;  delta above 126, an explicit ordinal, a root data blob with alignment, a
;  bss blob and a name longer than 31 characters. tests/blob_writer_test.ts
;  builds the expected streams with the reference's writers.

%INCLUDE "BLOBMEM.ASM"
%INCLUDE "../../native/compiler/OUT.ASM"
%INCLUDE "../../native/compiler/BLOB.ASM"
%INCLUDE "../../native/compiler/BLEND.ASM"
%INCLUDE "../../native/compiler/BLOPEN.ASM"
%INCLUDE "../../native/compiler/BLCLOSE.ASM"

;@ROUTINE NORETURN
; Write the four streams and warm boot.

BT_START:                      ; Entered from the jump at $0100.
    LD   SP,($0006)                ; The stack below the BDOS entry.
    LD   HL,BE_HEAD                ; The directory header,
    LD   DE,BE_NAME                ; the streams' drive and name,
    LD   A,BL_LNOUT|BL_NMOUT       ; and all four streams.
    CALL BL_OPEN                   ; Open them.
    XOR  A                         ; Part 0
    LD   HL,BE_PARTA               ; is A.BSI.
    LD   B,5                       ; Five characters.
    CALL BL_PART                   ; Name it.
    LD   A,1                       ; Part 1
    LD   HL,BE_PARTB               ; is B.BSI.
    LD   B,5                       ; Five characters.
    CALL BL_PART                   ; Name it.
    LD   HL,$0400                  ; Blob $0400: code.
    XOR  A                         ; Kind 0, no root, no alignment.
    CALL BL_BEGIN                  ; Start it.
    XOR  A                         ; Part 0, line 1, at offset 0.
    LD   HL,BE_L1                  ; The first entry (1:1).
    CALL BL_LINE                   ; Mark it.
    LD   A,1                       ; Part 1, line 2, also at offset 0.
    LD   HL,BE_L2                  ; A second entry: another part (2:2).
    CALL BL_LINE                   ; Mark it.
    LD   A,1                       ; Part 1, line 3, at offset 0 again.
    LD   HL,BE_L3                  ; It replaces line 2 (3:3).
    CALL BL_LINE                   ; Mark it.
    LD   A,BL_LO8                  ; LO8 at offset 0
    LD   HL,$0401                  ; of $0401.
    LD   DE,0                      ; No addend.
    CALL BL_REF                    ; One placeholder byte.
    LD   B,69                      ; Then 69 zeros: offset 70.
    CALL BE_ZEROS                  ; Append them.
    LD   A,BL_HI8                  ; HI8 at offset 70: a delta of 70
    LD   HL,$0401                  ; escapes to an absolute offset.
    LD   DE,5                      ; Addend 5.
    CALL BL_REF                    ; One placeholder byte.
    LD   A,BL_SIZE                 ; SIZE16 at offset 71
    LD   HL,$0402                  ; of $0402.
    LD   DE,0                      ; No addend.
    CALL BL_REF                    ; Two placeholder bytes.
    LD   B,67                      ; Then 67 zeros: offset 140.
    CALL BE_ZEROS                  ; Append them.
    LD   A,1                       ; Part 1, line 9, at offset 140:
    LD   HL,BE_L9                  ; a delta of 140 escapes (9:300).
    CALL BL_LINE                   ; Mark it.
    LD   B,10                      ; Ten more zeros: 150 bytes.
    CALL BE_ZEROS                  ; Append them.
    CALL BL_END                    ; Write the blob.
    LD   HL,$0405                  ; Blob $0405: an explicit ordinal,
    LD   A,BL_KDATA|BL_ROOT|$60    ; root data aligned to 8.
    CALL BL_BEGIN                  ; Start it.
    LD   B,4                       ; Four bytes.
    CALL BE_ZEROS                  ; Append them.
    CALL BL_END                    ; Write it.
    LD   HL,$0406                  ; Blob $0406: bss
    LD   DE,300                    ; of 300 bytes.
    LD   A,BL_KBSS                 ; No root, no alignment.
    CALL BL_BSS                    ; Write its record.
    LD   HL,$0405                  ; Name $0405
    LD   DE,BE_LONG                ; with a 40-character name,
    LD   B,40                      ; of which 31 are kept.
    CALL BL_NAME                   ; Record it.
    CALL BL_CLOSE                  ; Write the trailers.
    JP   0                         ; Warm boot.

;@ROUTINE IN B CLOBBERS A,B,CARRY,ZERO,SIGN,PARITY,HALFCARRY
; Append B zero bytes to the blob.

BE_ZEROS:                      ; B zeros remain.
    XOR  A                         ; A zero byte.
    CALL BL_BYTE                   ; Append it.
    DJNZ BE_ZEROS                  ; Until B are done.
    RET                            ; The blob has grown by B.

;@ROUTINE NORETURN
; A full disk or an overflowing blob: print F or O and warm boot.

OUT_FAIL:                      ; The disk or directory is full.
    LD   E,'F'                     ; Report it.
    JR   BE_STOP                   ; And stop.
BL_OVER:                       ; A blob reached 16K,
MM_FULL:                       ; or the free memory is full.
    LD   E,'O'                     ; Report it.
BE_STOP:                       ; E is the report.
    LD   C,2                       ; Console output.
    CALL $0005                     ; Print it.
    JP   0                         ; Warm boot.

BE_HEAD:                       ; The program directory's header.
    DB   "BSIP",1,0                ; Magic, version 1.0.
    DW   7,1,1,0,1,$0400           ; Stamp 7, runtime, helpers, no key, profile, base.
    DB   0,0                       ; Flags and padding.
BE_NAME:                       ; The streams' drive and name.
    DB   0,"EDGE    "              ; The current drive.
BE_PARTA:                      ; Part 0's name.
    DB   "A.BSI"                   ; Five characters.
BE_PARTB:                      ; Part 1's name.
    DB   "B.BSI"                   ; Five characters.
BE_LONG:                       ; A name longer than the stream keeps.
    DB   "a_name_of_forty_characters_exactly_here_"
BE_L1:                         ; Positions, each a line and a column.
    DW   1,1                       ; 1:1.
BE_L2:                         ; 2:2.
    DW   2,2                       ; Replaced.
BE_L3:                         ; 3:3.
    DW   3,3                       ; Its replacement.
BE_L9:                         ; 9:300, a column past 255,
    DW   9,300                     ; kept as 255.
