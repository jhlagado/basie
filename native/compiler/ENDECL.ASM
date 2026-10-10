;==========================================================================
;  Enum declarations
;==========================================================================
;
;  Overlay ENUMS, loaded above NAMES in FLOAT's place when a program
;  declares an enum (EN_DECL, ENUMS.ASM, through OV_XCALL), which a program
;  does once per type, at top level. Its members live in the name heap
;  (ENUMS.ASM): a node of six bytes each, the spelling's word and length,
;  the ordinal and the next node, newest first; their names are qualified
;  and never enter the hash chains. Its scratch, EN_HEAD and EN_COUNT, is
;  the initializers' (AG_IBUF), unused while it runs. An f32 literal read
;  here loads FLOAT over it, and OV_XCALL loads it again before returning.
;
;  Principal entry:
;    ED_RUN    the EnumDeclaration island, at the overlay's start

;@ROUTINE OUT A,CARRY,ZERO CLOBBERS BC,DE,HL,SIGN,PARITY,HALFCARRY
; Island EnumDeclaration: the name, retained and declared (EX_DECL), its
; line's end, then member lines until `end`, each a name not yet a member
; (duplicate-name at it) and at most 256 (capacity at it), then `end` and
; its line's end. No member is empty-enum at the declaration. The type is
; a new descriptor (AG_KENUM, its count, zero for 256, and its member list)
; and its name a type symbol (SY_TYPE) of the new ID.

ED_RUN:                        ; After `enum`.
    CALL RO_NAME                   ; The name,
    CALL EX_DECL                   ; retained and checked,
    LD   E,TK_EOL                  ; then
    CALL PR_NEED                   ; its line's end.
    LD   HL,0                      ; No member
    LD   (EN_HEAD),HL              ; yet,
    LD   (EN_COUNT),HL             ; none counted.
.MEMBER:                       ; A member's line, or `end`.
    CALL PR_PEEK                   ; `end`
    CP   TK_END                    ; ends
    JR   Z,.END                    ; them.
    CALL RO_NAME                   ; A name:
    LD   HL,(EN_HEAD)              ; already
    CALL EN_FIND                   ; a member?
    LD   A,DG_DUP                  ; Then
    JP   C,DG_NAMED                ; duplicate-name.
    LD   A,(EN_COUNT+1)            ; 256 already
    OR   A                         ; counted?
    LD   A,DG_EMEM                 ; Then capacity,
    JP   NZ,DG_ISSUE               ; enum members.
    LD   BC,6                      ; Its node,
    CALL NH_ALLOC                  ; in the name heap:
    PUSH DE                        ; (kept)
    EX   DE,HL                     ; its
    CALL TK_KEEP                   ; spelling,
    INC  HL                        ; its
    LD   DE,(EN_COUNT)             ; ordinal,
    LD   (HL),E                    ; the count
    INC  DE                        ; before
    LD   (EN_COUNT),DE             ; it;
    INC  HL                        ; then
    LD   DE,(EN_HEAD)              ; the
    LD   (HL),E                    ; newest
    INC  HL                        ; before
    LD   (HL),D                    ; it.
    POP  HL                        ; It is
    LD   (EN_HEAD),HL              ; the newest.
    LD   E,TK_EOL                  ; Its
    CALL PR_NEED                   ; line's end.
    JR   .MEMBER                   ; The next.
.END:                          ; `end`:
    LD   HL,(EN_COUNT)             ; with
    LD   A,H                       ; no
    OR   L                         ; member,
    LD   A,DG_EENUM                ; empty-enum
    JR   NZ,.NONEMPTY              ; at the
    LD   HL,AC_DPOS                ; declaration.
    JP   DG_AT                     ; No return.
.NONEMPTY:                     ; The type:
    LD   A,L                       ; its count, zero for
    LD   (AG_NAUX),A               ; the full 256,
    LD   A,AG_KENUM                ; its
    LD   (AG_NKIND),A              ; kind
    LD   HL,(EN_HEAD)              ; and
    LD   (AG_NDIM),HL              ; members,
    LD   HL,1                      ; a byte
    LD   (AG_NSIZE),HL             ; each,
    CALL AG_ADD                    ; is a new ID, A;
    LD   C,A                       ; its name
    LD   B,0                       ; a type
    LD   D,SY_TYPE                 ; symbol
    CALL EX_PREP                   ; of it,
    CALL SY_CMT                    ; committed.
    CALL PR_TAKE                   ; `end`,
    LD   E,TK_EOL                  ; then its
    JP   PR_NEED                   ; line's end; return.
