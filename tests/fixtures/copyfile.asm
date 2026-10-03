; Copy IN.TXT to OUT.TXT record by record, then print the command tail and
; set a CP/M 3 return code. Exercises the harness's file functions.
        ORG     $0100
START:  LD      C,26
        LD      DE,BUFFER
        CALL    $0005           ; DMA to our buffer
        LD      C,15
        LD      DE,INFCB
        CALL    $0005           ; open IN.TXT
        INC     A
        JR      Z,FAIL
        LD      C,22
        LD      DE,OUTFCB
        CALL    $0005           ; make OUT.TXT
LOOP:   LD      C,20
        LD      DE,INFCB
        CALL    $0005           ; read a record
        OR      A
        JR      NZ,DONE
        LD      C,21
        LD      DE,OUTFCB
        CALL    $0005           ; write it
        JR      LOOP
DONE:   LD      C,16
        LD      DE,OUTFCB
        CALL    $0005           ; close OUT.TXT
        LD      HL,$0081        ; echo the command tail
        LD      A,($0080)
        LD      B,A
TAIL:   LD      A,B
        OR      A
        JR      Z,CODE
        LD      E,(HL)
        LD      C,2
        PUSH    HL
        PUSH    BC
        CALL    $0005
        POP     BC
        POP     HL
        INC     HL
        DEC     B
        JR      TAIL
CODE:   LD      C,108
        LD      DE,$0000
        CALL    $0005
        RET
FAIL:   LD      C,108
        LD      DE,$FF01
        CALL    $0005
        RET
INFCB:  DB      0,"IN      TXT"
        DS      24,0
OUTFCB: DB      0,"OUT     TXT"
        DS      24,0
BUFFER: DS      128,0
