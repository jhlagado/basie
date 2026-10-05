; Publication and clean-up (toolchain §6). After a successful link the new
; image and line table replace the old outputs; after a failure the outputs
; are left untouched and only the temporaries go. Either way the
; intermediate files are deleted unless option K.

PUB_FD: DS      FD_SIZE         ; a scratch FD for names
PUB_ALT EQU     SRC_LIB         ; Phase D's, finished with
OUT_MADE: DB    0               ; 1 once NAME.$$$ exists
LT_MADE: DB     0               ; 1 once NAME.$LT exists
PUB_BAK: DB      "BAK"
PUB_LIN: DB      "LIN"
PUB_TEMP: DB      "$DR$BY$LN$NM$RF"

; Publish (toolchain §6.1): back up or drop the old output, rename the new
; image over it, replace the line table, and clean up.
PUB_RUN:
        ; the target: NAME.COM (or option O's name and type)
        LD      IX,PUB_FD
        CALL    OUT_PICK
        LD      DE,OUT_TYPE
        CALL    FIL_INIT
        CALL    FIL_OPEN        ; does it exist?
        JR      C,.RENAME
        LD      A,(OP_FLAGS)
        AND     OF_Z
        JR      Z,.BACKUP
        CALL    FIL_DEL         ; option Z: no backup
        JR      .RENAME
.BACKUP:
        LD      IX,PUB_ALT      ; delete NAME.BAK, then rename to it
        CALL    OUT_PICK
        LD      DE,PUB_BAK
        CALL    FIL_INIT
        CALL    FIL_DEL
        LD      IX,PUB_FD
        LD      IY,PUB_ALT
        CALL    FIL_REN
.RENAME:
        LD      IX,PUB_FD       ; NAME.$$$ becomes the target
        CALL    OUT_PICK
        LD      DE,OUT_TYPE
        CALL    FIL_INIT
        LD      IX,OUT_FD
        LD      IY,PUB_FD
        CALL    FIL_REN
        JP      C,DG_DISK
        XOR     A
        LD      (OUT_MADE),A
        ; the line table: the old one always goes, so trap lookup never
        ; uses a table from an earlier build
        LD      IX,PUB_FD
        CALL    OUT_PICK
        LD      DE,PUB_LIN
        CALL    FIL_INIT
        CALL    FIL_DEL
        LD      A,(LT_MADE)
        OR      A
        JR      Z,.CLEAN
        LD      IX,LT_FD
        LD      IY,PUB_FD
        CALL    FIL_REN
        JP      C,DG_DISK
        XOR     A
        LD      (LT_MADE),A
.CLEAN: RET                     ; the caller cleans up after the reports

; After a failure: delete NAME.$$$ and NAME.$LT if they were made, then the
; intermediates unless K.
PUB_UNDO:
        LD      A,(OUT_MADE)
        OR      A
        JR      Z,.LT
        LD      IX,OUT_FD
        CALL    FIL_DEL
.LT:    LD      A,(LT_MADE)
        OR      A
        JR      Z,PUB_TIDY
        LD      IX,LT_FD
        CALL    FIL_DEL
; Delete the intermediate files on the spool drive, unless option K.
PUB_TIDY:
        LD      A,(OP_FLAGS)
        AND     OF_K
        RET     NZ
        LD      DE,PUB_TEMP
        LD      B,5
.EACH:  PUSH    BC
        PUSH    DE
        LD      IX,PUB_FD
        LD      A,(OP_SPOOL)
        OR      A
        JR      NZ,.DRV
        LD      A,(CMD_DISK)
.DRV:   LD      HL,CMD_NAME
        CALL    FIL_INIT
        CALL    FIL_DEL
        POP     DE
        INC     DE
        INC     DE
        INC     DE
        POP     BC
        DJNZ    .EACH
        RET
