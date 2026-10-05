;==========================================================================
;  Semantic transcript
;==========================================================================
;
;  Nucleus's parser appended every operation to a semantic transcript that
;  a later phase replayed into code. BASIE.COM generates each construct's
;  code as it parses it, writing blobs in the reference compiler's
;  templates (design decision D45, native compiler plan 65.4), and moves the
;  constructs across stage by stage. The parsers of the constructs not yet
;  moved still append their operations here, and each append refuses the
;  program with DG_NYI: a program the native compiler cannot yet compile is
;  refused rather than miscompiled.
;
;  Principal entries:
;    TR_OPER   append an operation: refuse the program
;    TR_PUT    append an operand byte: refuse the program
;    TR_PUTHL  the same, for callers that keep HL

;@ROUTINE NORETURN
; Refuse the construct being parsed: its code generation is still to come.

TR_OPER:                       ; An operation the parser would append.
TR_PUT:                        ; An operand byte of one.
TR_PUTHL:                      ; The same with HL kept.
    CALL DG_RAISE                  ; Report the construct; parsing ends.
    DB   DG_NYI                    ; Not yet compiled.
