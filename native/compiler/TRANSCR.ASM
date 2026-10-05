;==========================================================================
;  Semantic transcript
;==========================================================================
;
;  Nucleus's parser appended every operation to a semantic transcript that
;  a later phase replayed into code. BASIE.COM generates each construct's
;  code as it parses it, writing blobs in the reference compiler's
;  templates (design decision D45, native compiler plan 65.4), and moves the
;  constructs across stage by stage. What remains of the transcript is its
;  refusal: the constructs not yet moved (calls to main, a forward main,
;  the services with a u32, File fields, elements, results and
;  initialized program variables) are refused with DG_NYI, so that a
;  program the native compiler cannot yet compile is refused rather than
;  miscompiled.
;
;  Principal entries:
;    TR_OPER   refuse the construct being parsed

;@ROUTINE NORETURN
; Refuse the construct being parsed: its code generation is still to come.

TR_OPER:                       ; A construct not yet compiled.
    CALL DG_RAISE                  ; Report the construct; parsing ends.
    DB   DG_NYI                    ; Not yet compiled.
