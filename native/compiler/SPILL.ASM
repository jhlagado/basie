;==========================================================================
;  The blob writer's spill
;==========================================================================
;
;  The SPILL overlay (OVERLAY.ASM), which only a routine too large for the
;  free memory needs: writing the blob's whole records to NAME.$CD as the
;  memory fills (SP_WRITE, for BL_FLUSH), and opening it again to read
;  them back as the blob is written (SP_RBACK, for BL_RBACK). It loads
;  above NAMES, and OV_SCALL loads again the overlay it replaced, whose
;  code may be the one emitting, before it returns.
;
;  Principal entries:
;    SP_WRITE  spill L whole records, at OV_AREA (above NAMES)
;    SP_RBACK  open NAME.$CD again and read its first record, at +3

;@ROUTINE IN L OUT CARRY CLOBBERS A,BC,DE,HL,IX,ZERO,SIGN,PARITY,HALFCARRY
; The overlay's entries: SP_WRITE here, SP_RBACK three bytes on.

SP_ENTRY:                      ; L is the count of records.
    JR   SP_WRITE                  ; Spill them.
    DB   0                         ; (padding)
    JP   SP_RBACK                  ; At +3.

;@ROUTINE IN L OUT CARRY CLOBBERS A,BC,DE,HL,IX,ZERO,SIGN,PARITY,HALFCARRY
; Spill L whole records of the blob's bytes in memory to NAME.$CD (made
; at the first, its first record kept in BL_REC0 too), and move the rest
; to where they began: BL_CBASE moves down by the bytes spilled. Carry is
; clear; a full disk is OUT_FAIL.

SP_WRITE:                      ; L is the count.
    LD   B,L                       ; B is their count.
    LD   DE,(BL_SPILL)             ; Those spilled before.
    LD   A,D                       ; Are some
    OR   E                         ; on the disk
    JR   NZ,.MADE                  ; already?
    PUSH BC                        ; If not,
    LD   HL,(BL_CBASE)             ; the first
    LD   DE,BL_REC0                ; record
    LD   BC,128                    ; is kept
    LDIR                           ; in memory,
    LD   HL,(BL_NAMEP)             ; and NAME.$CD
    LD   DE,BL_SFCB                ; is made:
    LD   BC,9                      ; the drive
    LDIR                           ; and name,
    LD   HL,.TYPE                  ; the
    LD   C,3                       ; type,
    LDIR                           ; then
    LD   B,24                      ; zeros.
.ZERO:                         ; B remain.
    LD   (DE),A                    ; A is zero.
    INC  DE                        ; The next.
    DJNZ .ZERO                     ; Until all are.
    LD   DE,BL_SFCB                ; An old
    LD   C,BD_DEL                  ; one
    CALL BL_BDOS                   ; goes;
    LD   DE,BL_SFCB                ; a new
    LD   C,BD_MAKE                 ; one
    CALL BL_BDOS                   ; is made,
    INC  A                         ; or the directory
    JP   Z,OUT_FAIL                ; is full.
    POP  BC                        ; B is the count.
.MADE:                         ; The file is open for writing.
    LD   HL,(BL_CBASE)             ; The bytes
    LD   DE,(BL_SPILL)             ; in memory
    ADD  HL,DE                     ; begin here.
    PUSH HL                        ; Kept.
.RECORD:                       ; HL is a record, B remain.
    PUSH BC                        ; Keep the count
    PUSH HL                        ; and the record.
    EX   DE,HL                     ; It is
    LD   C,BD_DMA                  ; written
    CALL BL_BDOS                   ; from
    LD   DE,BL_SFCB                ; where
    LD   C,BD_WRITE                ; it is,
    CALL BL_BDOS                   ; or the disk
    OR   A                         ; is
    JP   NZ,OUT_FAIL               ; full.
    POP  HL                        ; The next
    LD   DE,128                    ; record
    ADD  HL,DE                     ; on;
    POP  BC                        ; one fewer.
    DJNZ .RECORD                   ; Until all are written.
    LD   DE,(BL_CBASE)             ; HL is the first not spilled.
    PUSH HL                        ; The bytes spilled,
    OR   A                         ; past
    SBC  HL,DE                     ; the base,
    LD   DE,(BL_SPILL)             ; less those spilled before,
    SBC  HL,DE                     ; are BC;
    LD   B,H                       ; the base
    LD   C,L                       ; moves down
    LD   HL,(BL_CBASE)             ; by them,
    SBC  HL,BC                     ; and those spilled
    LD   (BL_CBASE),HL             ; grow
    EX   DE,HL                     ; by
    ADD  HL,BC                     ; them.
    LD   (BL_SPILL),HL             ; HL is the bytes spilled.
    LD   DE,(BL_LEN)               ; The rest,
    EX   DE,HL                     ; from their
    SBC  HL,DE                     ; length,
    LD   B,H                       ; BC of
    LD   C,L                       ; them,
    POP  HL                        ; move from the first not spilled
    POP  DE                        ; to where the bytes began.
    LD   A,B                       ; (none:
    OR   C                         ; none
    JR   Z,.DONE                   ; moved; carry is clear)
    LDIR                           ; Moved: carry is clear.
.DONE:                         ; Carry is clear.
    RET                            ; Done.
.TYPE:                         ; The spill file's type.
    DB   "$CD"                     ; NAME.$CD.

;@ROUTINE CLOBBERS A,BC,DE,HL,CARRY,ZERO,SIGN,PARITY,HALFCARRY
; NAME.$CD, written, is read back from its start (BL_RDB): closed, opened
; again, its first record read, which BL_REC0 replaces.

SP_RBACK:                      ; At SPILL's entry +3.
    LD   DE,BL_SFCB                ; Close
    LD   C,BD_CLOSE                ; the
    CALL BL_BDOS                   ; file,
    CALL .RESET                    ; open it
    LD   C,BD_OPEN                 ; again,
    CALL BL_BDOS                   ; from
    CALL .RESET                    ; its start,
    XOR  A                         ; and read
    LD   (BL_RREC),A               ; its first
    JP   BL_RNEXT                  ; record; return.
.RESET:                        ; The extent and record are zero.
    XOR  A                         ; Zero:
    LD   (BL_SFCB+12),A            ; the extent,
    LD   (BL_SFCB+14),A            ; its high byte,
    LD   (BL_SFCB+32),A            ; the current record.
    LD   DE,BL_SFCB                ; DE is the FCB.
    RET                            ; Done.
