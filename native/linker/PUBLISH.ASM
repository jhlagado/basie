; Publication and clean-up (toolchain §6). After a successful link the new
; image and line table replace the old outputs; after a failure the outputs
; are left untouched and only the temporaries go. Either way the
; intermediate files are deleted unless option K.

TMP_FD: DS      FDSIZE          ; a scratch FD for names
TMP2_FD EQU     LIBB_FD         ; Phase D's, finished with
OUT_MADE: DB    0               ; 1 once NAME.$$$ exists
LT_MADE: DB     0               ; 1 once NAME.$LT exists
BAK_TY: DB      "BAK"
LIN_TY: DB      "LIN"
INTERS: DB      "$DR$BY$LN$NM$RF"

; Publish (toolchain §6.1): back up or drop the old output, rename the new
; image over it, replace the line table, and clean up.
PUBLISH:
        ; the target: NAME.COM (or option O's name and type)
        LD      IX,TMP_FD
        CALL    OUTNAME
        LD      DE,O_OTYP
        CALL    F_INIT
        CALL    F_OPEN          ; does it exist?
        JR      C,.RENAME
        LD      A,(O_FLAGS)
        AND     OF_Z
        JR      Z,.BACKUP
        CALL    F_DEL           ; option Z: no backup
        JR      .RENAME
.BACKUP:
        LD      IX,TMP2_FD      ; delete NAME.BAK, then rename to it
        CALL    OUTNAME
        LD      DE,BAK_TY
        CALL    F_INIT
        CALL    F_DEL
        LD      IX,TMP_FD
        LD      IY,TMP2_FD
        CALL    F_REN
.RENAME:
        LD      IX,TMP_FD       ; NAME.$$$ becomes the target
        CALL    OUTNAME
        LD      DE,O_OTYP
        CALL    F_INIT
        LD      IX,OUT_FD
        LD      IY,TMP_FD
        CALL    F_REN
        JP      C,DISKERR
        XOR     A
        LD      (OUT_MADE),A
        ; the line table: the old one always goes, so trap lookup never
        ; uses a table from an earlier build
        LD      IX,TMP_FD
        CALL    OUTNAME
        LD      DE,LIN_TY
        CALL    F_INIT
        CALL    F_DEL
        LD      A,(LT_MADE)
        OR      A
        JR      Z,.CLEAN
        LD      IX,LT_FD
        LD      IY,TMP_FD
        CALL    F_REN
        JP      C,DISKERR
        XOR     A
        LD      (LT_MADE),A
.CLEAN: RET                     ; the caller cleans up after the reports

; After a failure: delete NAME.$$$ and NAME.$LT if they were made, then the
; intermediates unless K.
ABANDON:
        LD      A,(OUT_MADE)
        OR      A
        JR      Z,.LT
        LD      IX,OUT_FD
        CALL    F_DEL
.LT:    LD      A,(LT_MADE)
        OR      A
        JR      Z,CLEANUP
        LD      IX,LT_FD
        CALL    F_DEL
; Delete the intermediate files on the spool drive, unless option K.
CLEANUP:
        LD      A,(O_FLAGS)
        AND     OF_K
        RET     NZ
        LD      DE,INTERS
        LD      B,5
.EACH:  PUSH    BC
        PUSH    DE
        LD      IX,TMP_FD
        LD      A,(O_SDRV)
        OR      A
        JR      NZ,.DRV
        LD      A,(O_DRV)
.DRV:   LD      HL,O_NAME
        CALL    F_INIT
        CALL    F_DEL
        POP     DE
        INC     DE
        INC     DE
        INC     DE
        POP     BC
        DJNZ    .EACH
        RET
