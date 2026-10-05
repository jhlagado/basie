;==========================================================================
;  Publication and clean-up
;==========================================================================
;
;  Publication and clean-up (toolchain §6). After a successful link the new
;  image and line table replace the old outputs; after a failure the
;  outputs are left untouched and only the temporaries go. Either way the
;  intermediate files are deleted unless option K.
;
;  Principal entries:
;    PUB_RUN   publish NAME.$$$ and NAME.$LT under their final names
;    PUB_UNDO  after a failure: delete what the link made, then tidy
;    PUB_TIDY  delete the intermediate files, unless option K
;
;  OUT_MADE and LT_MADE record which temporaries exist, so a failure at any
;  point deletes exactly those. Publication clears them as it renames, so a
;  failure in Phase E leaves the published program alone.

PUB_FD:                        ; A scratch FD for names.
    DS   FD_SIZE                   ; Set up afresh for each file.
PUB_ALT EQU  SRC_LIB           ; A second, Phase D's, finished with.
OUT_MADE:                      ; 1 once NAME.$$$ exists.
    DB   0                         ; Cleared once it is published.
LT_MADE:                       ; 1 once NAME.$LT exists.
    DB   0                         ; Cleared once it is published.
PUB_BAK:                       ; The old output's backup type.
    DB   "BAK"                     ; Three characters.
PUB_LIN:                       ; The published line table's type.
    DB   "LIN"                     ; Three characters.
PUB_TEMP:                      ; The intermediate files' types, three bytes each.
    DB   "$DR$BY$LN$NM$RF"         ; Five types, deleted unless option K.

;@ROUTINE CLOBBERS A,BC,DE,HL,IX,IY,CARRY,ZERO,SIGN,PARITY,HALFCARRY
; Publish (toolchain §6.1): back up or drop the old output, rename the new
; image over it, and replace the line table. The caller cleans up after
; Phase E's reports. L-IO if a rename fails.

PUB_RUN:                       ; NAME.$$$ and NAME.$LT are closed.
    LD   IX,PUB_FD                 ; The target: NAME.COM (or option O's
    CALL OUT_PICK                  ; name and type); HL and A name it.
    LD   DE,OUT_TYPE               ; Its type.
    CALL FIL_INIT                  ; Set up the FCB.
    CALL FIL_OPEN                  ; Does it exist?
    JR   C,.RENAME                 ; No old output.
    LD   A,(OP_FLAGS)              ; Option Z:
    AND  OF_Z                      ; no backup.
    JR   Z,.BACKUP                 ; Keep the old output as NAME.BAK.
    CALL FIL_DEL                   ; Option Z: drop it.
    JR   .RENAME                   ; Publish the new one.
.BACKUP:                       ; Delete NAME.BAK, then rename to it.
    LD   IX,PUB_ALT                ; The backup's FD.
    CALL OUT_PICK                  ; The output's name and drive,
    LD   DE,PUB_BAK                ; type BAK.
    CALL FIL_INIT                  ; Set up the FCB.
    CALL FIL_DEL                   ; Delete any older backup.
    LD   IX,PUB_FD                 ; The old output
    LD   IY,PUB_ALT                ; becomes NAME.BAK;
    CALL FIL_REN                   ; a failure here is not checked.
.RENAME:                       ; The target's name is free.
    LD   IX,PUB_FD                 ; NAME.$$$ becomes the target:
    CALL OUT_PICK                  ; the output's name and drive,
    LD   DE,OUT_TYPE               ; and its type.
    CALL FIL_INIT                  ; Set up the FCB.
    LD   IX,OUT_FD                 ; NAME.$$$
    LD   IY,PUB_FD                 ; takes the target's name.
    CALL FIL_REN                   ; Carry on failure.
    JP   C,DG_DISK                 ; L-IO.
    XOR  A                         ; NAME.$$$ is gone:
    LD   (OUT_MADE),A              ; nothing to delete now.
    LD   IX,PUB_FD                 ; The line table: the old one always goes,
    CALL OUT_PICK                  ; so trap lookup never uses a table
    LD   DE,PUB_LIN                ; from an earlier build.
    CALL FIL_INIT                  ; NAME.LIN.
    CALL FIL_DEL                   ; Deleted.
    LD   A,(LT_MADE)               ; Was a new table written?
    OR   A                         ; Not under option N.
    JR   Z,.CLEAN                  ; None to publish.
    LD   IX,LT_FD                  ; NAME.$LT
    LD   IY,PUB_FD                 ; becomes NAME.LIN.
    CALL FIL_REN                   ; Carry on failure.
    JP   C,DG_DISK                 ; L-IO.
    XOR  A                         ; NAME.$LT is gone:
    LD   (LT_MADE),A               ; nothing to delete now.
.CLEAN:                        ; Published.
    RET                            ; The caller cleans up after the reports.

;@ROUTINE CLOBBERS A,BC,DE,HL,IX,CARRY,ZERO,SIGN,PARITY,HALFCARRY
; After a failure: delete NAME.$$$ and NAME.$LT if they were made, then the
; intermediates unless option K.

PUB_UNDO:                      ; Called from LK_FAIL and DG_DISK.
    LD   A,(OUT_MADE)              ; Was NAME.$$$ made?
    OR   A                         ; Nonzero if so.
    JR   Z,.LT                     ; No.
    LD   IX,OUT_FD                 ; Delete it.
    CALL FIL_DEL                   ; The old output is untouched.
.LT:                           ; The line table.
    LD   A,(LT_MADE)               ; Was NAME.$LT made?
    OR   A                         ; Nonzero if so.
    JR   Z,PUB_TIDY                ; No: tidy up.
    LD   IX,LT_FD                  ; Delete it,
    CALL FIL_DEL                   ; then tidy up.

;@ROUTINE CLOBBERS A,BC,DE,HL,IX,CARRY,ZERO,SIGN,PARITY,HALFCARRY
; Delete the intermediate files on the spool drive, unless option K.

PUB_TIDY:                      ; At the end of every run that got this far.
    LD   A,(OP_FLAGS)              ; Option K:
    AND  OF_K                      ; keep the intermediates.
    RET  NZ                        ; Nothing to delete.
    LD   DE,PUB_TEMP               ; The intermediates' types,
    LD   B,5                       ; five of them.
.EACH:                         ; DE is a type, B counts down.
    PUSH BC                        ; Keep the count,
    PUSH DE                        ; and the type.
    LD   IX,PUB_FD                 ; The scratch FD.
    LD   A,(OP_SPOOL)              ; The spool drive,
    OR   A                         ; if S= gave one;
    JR   NZ,.DRV                   ; it did.
    LD   A,(CMD_DISK)              ; Else the first part's drive.
.DRV:                          ; A is the drive.
    LD   HL,CMD_NAME               ; NAME, with the type at DE.
    CALL FIL_INIT                  ; Set up the FCB.
    CALL FIL_DEL                   ; Delete it, if it exists.
    POP  DE                        ; The type.
    INC  DE                        ; The next
    INC  DE                        ; type,
    INC  DE                        ; three bytes on.
    POP  BC                        ; The count.
    DJNZ .EACH                     ; Until all five are deleted.
    RET                            ; Tidied.
