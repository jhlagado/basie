; Smallest CP/M program: print a message through BDOS function 9 and
; return to the CCP.
        ORG     $0100
START:  LD      C,9
        LD      DE,MESSAGE
        CALL    $0005
        RET
MESSAGE:
        DB      "HELLO FROM BASIE",13,10,"$"
