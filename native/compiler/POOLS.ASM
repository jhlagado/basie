;==========================================================================
;  Pools and handle types
;==========================================================================
;
;  Pool declarations, `forward pool`, and the handle types they make, as
;  the reference compiler has them (spec 6.14, 6.15, 7.9, 8.11): a pool
;  is a fixed array of slots of one record type, written as two blobs, its
;  slots (bss, six bytes of header and the record per slot, plus a six-byte
;  pool header) and its information (rodata: the slots' address, the slot
;  size, the capacity and the record's owner descriptor or zero), which the
;  runtime's pool helpers read. The pool's ordinal is its information
;  blob's, taken when the pool is first declared, forward or not.
;
;  Principal entries:
;    PL_FWD    ForwardPool: `forward pool NAME` (OWNERS overlay)
;    PL_REC    the PoolRecord island: the record after `as` (OWNERS)
;    PL_HOLD   SavePoolCapacity: the capacity, a nonzero u16
;    PL_CMT    CommitPool: declare or complete the pool, write its blobs
;              (OWNERS)
;    PL_TYPE   resolve a named type: a pool's handle, or `id P`
;    PL_OPT    MakeOptionalHandle: `?` after a handle type
;    PL_OWNS   carry if a type ID is an owning type
;    PL_MARK   mark a table type as owning
;    PL_ENDP   a part's or the program's end: forward pools completed
;              (OWNERS)
;
;  A pool's entry in PL_TAB (CALLWORK.ASM) holds its ordinal, its record
;  type (zero while it is only forward), its visibility, its part and its
;  name's address. Its name is a symbol of class SY_TYPE+SY_GLOB whose
;  payload is the entry's index. A handle type's ID is AG_HND plus four
;  times that index plus its form, AG_HOPT and AG_HID (STATE.ASM).
;
;  A record type is owning when a field holds an owning handle or an
;  owning type; an array when its element is owning. PL_OWNB has a bit for
;  each table type, set as records and arrays are made (PL_MARK). Each
;  owning type's owner descriptor (memory safety 5.10) is written once, as
;  a rodata blob named TYPE.owners, its ordinal kept in PL_DESC: a count,
;  then per owning handle a flag byte, its offset and, for one inside an
;  array, the array's stride and element count. An array inside an array
;  takes one entry per outer element (the reference's owningEntries).

PL_CLASS EQU  SY_TYPE+SY_GLOB  ; A pool name's class byte.

; Scratch for a pool's declaration and a descriptor's writing, in the
; initializer staging (AG_IBUF), which neither uses.
PL_NSLOT EQU  AG_IBUF          ; Word: the slot size.
PL_NSIZE EQU  PL_NSLOT+2       ; Word: the slots' bytes.
PL_NSTOR EQU  PL_NSIZE+2       ; Word: the ordinal of the blob being named.
PL_DNEW EQU  PL_NSTOR+2        ; Byte: nonzero when the descriptor is new.
PL_WTYPE EQU  PL_DNEW+1        ; Byte: the type a descriptor describes.
PL_WEMIT EQU  PL_WTYPE+1       ; Byte: nonzero for the emitting walk.
PL_WCNT EQU  PL_WEMIT+1        ; Word: the entries counted.
PL_WELEM EQU  PL_WCNT+2        ; Byte: an array's element type in the walk.
PL_WLEN EQU  PL_WELEM+1        ; Word: its element count.
PL_TEXT EQU  PL_WLEN+2         ; 48 bytes: a blob's name being made.
PL_SLOT EQU  6                 ; Bytes of a slot's header, and of a pool's.

;@ROUTINE IN A OUT HL CLOBBERS DE,CARRY,ZERO,SIGN,PARITY,HALFCARRY
; Address pool A's entry in PL_TAB, ten bytes each, in HL. A and BC are
; kept.

PL_AT:                         ; A is the pool's index.
    LD   L,A                       ; Its index,
    LD   H,0                       ; as a word,
    ADD  HL,HL                     ; twice,
    LD   D,H                       ; kept;
    LD   E,L                       ; then
    ADD  HL,HL                     ; four,
    ADD  HL,HL                     ; eight,
    ADD  HL,DE                     ; ten times.
    LD   DE,PL_TAB                 ; From
    ADD  HL,DE                     ; the table.
    RET                            ; HL is the entry.

;@ROUTINE OUT A,CARRY CLOBBERS ZERO,SIGN,PARITY,HALFCARRY,BC,DE,HL
; Carry if the current NAME is a pool: A returns its index.

PL_FIND:                       ; The NAME is current.
    CALL SY_FIND                   ; A symbol of the name?
    RET  NC                        ; No.
    INC  HL                        ; Its
    INC  HL                        ; class
    INC  HL                        ; byte:
    LD   A,(HL)                    ; a pool's?
    CP   PL_CLASS                  ; Then
    SCF                            ; carry
    CCF                            ; is cleared
    RET  NZ                        ; if not.
    INC  HL                        ; Its payload,
    LD   A,(HL)                    ; the pool's index.
    SCF                            ; A pool.
    RET                            ; Done.

PL_BEGIN EQU  EX_DECL          ; BeginPool: keep the pool's name and position.

;@ROUTINE CLOBBERS A,BC,DE,HL,IX,IY,CARRY,ZERO,SIGN,PARITY,HALFCARRY
; The record and pool declarations' actions, in the OWNERS overlay
; (OWNERS.ASM): each loads it, unless it is the one loaded last, and runs
; its entry (OV_PCALL): BeginRecord, BeginRecordField, CommitRecordField
; and CommitRecord, then
; ForwardPool, the PoolRecord island, CommitPool, and a part's or the
; program's end, which has nothing to check without pools.

AC_REC:                        ; BeginRecord:
    LD   A,15                      ; entry 15.
    JR   PL_RUN                    ; Run.
AC_FIELD:                      ; BeginRecordField:
    LD   A,18                      ; entry 18.
    JR   PL_RUN                    ; Run.
AC_PLACE:                      ; CommitRecordField:
    LD   A,21                      ; entry 21.
    JR   PL_RUN                    ; Run.
AC_RECOK:                      ; CommitRecord:
    LD   A,24                      ; entry 24.
    JR   PL_RUN                    ; Run.
PL_FWD:                        ; ForwardPool:
    XOR  A                         ; entry 0.
    JR   PL_RUN                    ; Run.
PL_REC:                        ; PoolRecord:
    LD   A,3                       ; entry 3.
    JR   PL_RUN                    ; Run.
PL_CMT:                        ; CommitPool:
    LD   A,6                       ; entry 6.
    JR   PL_RUN                    ; Run.
PL_ENDP:                       ; A part or the program has ended:
    LD   A,(PL_CNT)                ; without pools
    OR   A                         ; nothing
    RET  Z                         ; to check;
    LD   A,9                       ; else entry 9.
PL_RUN:                        ; A is the entry's offset:
    JP   OV_PCALL                  ; run (OVERLAY.ASM).

;@ROUTINE OUT A,HL,CARRY,ZERO CLOBBERS SIGN,PARITY,HALFCARRY,BC,DE
; SavePoolCapacity: the bound must be known (not-constant) and fit a u16,
; each at the bound; zero is out-of-range at the pool's name, as the
; reference reports it (a pool needs at least one slot).

PL_HOLD:                       ; The bound is parsed.
    CALL EX_RTOK                   ; A its metadata, HL its value.
    AND  SY_KNOWN                  ; Folded to a constant?
    LD   A,DG_KNOWN                ; No: not-constant,
    JP   Z,AG_EVAL                 ; at the bound.
    LD   E,SY_U16                  ; It must fit
    LD   A,D                       ; a u16.
    CALL EX_FITS                   ; Checked at the bound.
    LD   (PL_NCAP),HL              ; The capacity.
    LD   A,H                       ; Zero?
    OR   L                         ; Then
    RET  NZ                        ; out of range,
    LD   A,DG_RANGE                ; at the
    LD   HL,AC_DPOS                ; pool's name.
    JP   DG_AT                     ; No return.

;@ROUTINE IN A OUT A CLOBBERS DE,HL,CARRY,ZERO,SIGN,PARITY,HALFCARRY
; Record type A is made: owning if a field of it owns (PL_ROWN, cleared).

PL_RMARK:                      ; A is the record's type.
    PUSH AF                        ; Kept.
    LD   HL,PL_ROWN                ; Did a field
    LD   A,(HL)                    ; own (one)?
    LD   (HL),0                    ; (cleared for the next record)
    RRA                            ; Carry if so.

;@ROUTINE IN CARRY OUT A CLOBBERS DE,HL,CARRY,ZERO,SIGN,PARITY,HALFCARRY
; The tail of PL_RMARK and PL_AMARK: the type, pushed, is owning if carry.

PL_MARKC:                      ; The type is on the stack.
    JR   NC,.KEPT                  ; Not owning.
    POP  AF                        ; The type
    PUSH AF                        ; is
    CALL PL_MARK                   ; owning.
.KEPT:                         ; Done.
    POP  AF                        ; The type.
    RET                            ; Back.

;@ROUTINE IN A OUT A CLOBBERS DE,HL,CARRY,ZERO,SIGN,PARITY,HALFCARRY
; Array type A is made of AG_NAUX elements: owning if they own.

PL_AMARK:                      ; A is the array's type.
    PUSH AF                        ; Kept.
    LD   A,(AG_NAUX)               ; Its element:
    CALL PL_OWNS                   ; owning?
    JR   PL_MARKC                  ; Then it is.

;@ROUTINE IN A OUT CARRY CLOBBERS A,DE,HL,ZERO,SIGN,PARITY,HALFCARRY
; Carry if type ID A is owning: an owning handle, or a table type marked
; in PL_OWNB. BC is kept.

PL_OWNS:                       ; A is a type ID.
    CP   AG_HND                    ; A handle?
    JR   C,.TABLE                  ; Below the handles.
    CP   AG_HEND                   ; Past
    JR   NC,.NOT                   ; them: a view or a File.
    AND  AG_HID                    ; An owner, not an identifier,
    RET  NZ                        ; owns (carry clear for an identifier).
    SCF                            ; It owns.
    RET                            ; Done.
.TABLE:                        ; A table type?
    SUB  AG_FIRST                  ; Its index,
    JR   C,.NOT                    ; none for a scalar
    CP   AG_TCAP                   ; nor for an
    JR   NC,.NOT                   ; open array.
    CALL PL_OWNAT                  ; Its bit, A, and byte, HL.
    AND  (HL)                      ; Set?
    RET  Z                         ; No: carry clear.
    SCF                            ; It owns.
    RET                            ; Done.
.NOT:                          ; Not owning.
    OR   A                         ; Carry clear.
    RET                            ; Done.

;@ROUTINE IN A OUT ZERO CLOBBERS A,DE,HL,CARRY,SIGN,PARITY,HALFCARRY
; Zero if a var parameter of table type A carries an owner word (the
; reference's ownerOffset): a record's does, as does an owning array's.
; BC is kept.

PL_OWORD:                      ; A is a table type.
    PUSH AF                        ; Kept.
    CALL PL_OWNS                   ; Owning?
    POP  DE                        ; (D the type)
    JR   NC,.KIND                  ; If so,
    XOR  A                         ; zero:
    RET                            ; it does.
.KIND:                         ; Not owning:
    LD   A,D                       ; a record's
    CALL AG_DESC                   ; kind
    LD   A,(HL)                    ; is
    CP   AG_KREC                   ; zero.
    RET                            ; Done.

;@ROUTINE IN A OUT A,HL CLOBBERS DE,CARRY,ZERO,SIGN,PARITY,HALFCARRY
; A is a table type's index: return its bit's mask in A and its byte of
; PL_OWNB in HL.

PL_OWNAT:                      ; A is the index.
    LD   HL,PL_OWNB                ; The bits' bytes:
    JP   SY_BITAT                  ; the mask and the byte; return.

;@ROUTINE IN A CLOBBERS A,DE,HL,CARRY,ZERO,SIGN,PARITY,HALFCARRY
; Mark table type A as owning.

PL_MARK:                       ; A is the type's ID.
    SUB  AG_FIRST                  ; Its index.
    CALL PL_OWNAT                  ; Its bit and byte.
    OR   (HL)                      ; Set,
    LD   (HL),A                    ; kept.
    RET                            ; Done.

;@ROUTINE OUT A,CARRY,ZERO CLOBBERS SIGN,PARITY,HALFCARRY,BC,DE,HL
; Within ResolveRecordType: carry if the current NAME is `id` followed by a
; name, or is a pool, either becoming the current type, a handle: `id P`
; reads the pool's name (wrong-class if it names no pool), `P` is the
; owning handle. Not carry otherwise, for a record type or File.

PL_TYPE:                       ; The NAME is current.
    LD   HL,KW_ID                  ; `id`
    LD   B,2                       ; (two bytes)?
    CALL TK_MATCH                  ; Matched:
    JR   NC,.OWNER                 ; if not, perhaps a pool.
    CALL PR_PEEK                   ; A name
    CP   TK_NAME                   ; follows?
    JR   NZ,.OWNER                 ; No: `id` is an ordinary name.
    CALL PR_TAKE                   ; The pool's name, taken.
    CALL PL_FIND                   ; A pool?
    LD   C,AG_HID                  ; An identifier,
    JR   C,.MAKE                   ; of it.
    LD   A,DG_CLASS                ; Not a pool:
    JP   DG_NAMED                  ; wrong-class, naming it.
.OWNER:                        ; Not `id P`.
    CALL PL_FIND                   ; A pool?
    RET  NC                        ; No.
    LD   C,0                       ; An owner.
.MAKE:                         ; A is the pool, C the form.
    ADD  A,A                       ; Four
    ADD  A,A                       ; times its index,
    ADD  A,AG_HND                  ; past the handles' base,
    ADD  A,C                       ; with the form:
    LD   (AG_CTYPE),A              ; the current type.
    SCF                            ; A handle.
    RET                            ; Done.

;@ROUTINE OUT A,CARRY,ZERO CLOBBERS SIGN,PARITY,HALFCARRY,HL
; MakeOptionalHandle: `?` after a type makes a handle optional; after any
; other type the line's end was expected, at the `?`.

PL_OPT:                        ; `?` is matched.
    LD   HL,AG_CTYPE               ; The current type:
    LD   A,(HL)                    ; a handle?
    CALL PL_ISHND                  ; If
    JR   NC,.NOT                   ; not, refused.
    SET  0,(HL)                    ; AG_HOPT: optional.
    RET                            ; Back to the engine.
.NOT:                          ; Not a handle:
    CALL DG_RAISE                  ; the line's end
    DB   DG_EOL                    ; expected, at the `?`.

;@ROUTINE IN A OUT A CLOBBERS CARRY,ZERO,SIGN,PARITY,HALFCARRY,HL
; A is a field's or program variable's type: a handle must be optional
; (handle-must-be-optional, at HL's position). A is kept.

PL_NEEDO:                      ; A is the type, HL the position.
    CALL PL_ISHND                  ; A handle?
    RET  NC                        ; No.
    BIT  0,A                       ; AG_HOPT:
    RET  NZ                        ; optional.
    LD   A,DG_HOPT                 ; handle-must-be-optional,
    JP   DG_AT                     ; at the position.

;@ROUTINE CLOBBERS A,DE,HL,CARRY,ZERO,SIGN,PARITY,HALFCARRY
; RefuseOwningInitializer: a program variable of a handle or owning type
; (AC_DINFO) has no initializer (static-initializer, at its name).

PL_SINIT:                      ; After `=`.
    LD   A,(AC_DINFO)              ; The variable's type:
    CALL PL_ISHND                  ; a handle
    CALL NC,PL_OWNS                ; or owning?
    RET  NC                        ; Neither.
    LD   A,DG_SINIT                ; static-initializer,
    LD   HL,AC_DPOS                ; at the
    JP   DG_AT                     ; name.

;@ROUTINE IN A OUT A CLOBBERS CARRY,ZERO,SIGN,PARITY,HALFCARRY
; A is a local's, parameter's, result's or open array's element type,
; with or without its var bit: a handle, or an owning aggregate, is
; refused for now (native-unsupported, DG_NYI). A is kept.

PL_LATER:                      ; A is the type.
    PUSH AF                        ; Kept.
    PUSH DE                        ; (PL_OWNS
    PUSH HL                        ; clobbers these)
    AND  $7F                       ; Without the var bit:
    CALL PL_ISHND                  ; a handle
    CALL NC,PL_OWNS                ; or owning?
    POP  HL                        ; (DE and HL
    POP  DE                        ; back)
    JR   C,.REFUSE                 ; Then refused.
    POP  AF                        ; The type.
    RET                            ; Accepted.
.REFUSE:                       ; Not yet compiled.
    POP  AF                        ; The type.
    JP   TR_OPER                   ; native-unsupported.

;@ROUTINE IN A OUT CARRY CLOBBERS ZERO,SIGN,PARITY,HALFCARRY
; Carry if type ID A is a handle, of any form. A is kept.

PL_ISHND:                      ; A is a type ID.
    CP   AG_HND                    ; Below the handles:
    CCF                            ; not
    RET  NC                        ; one.
    CP   AG_HEND                   ; Carry if below their end.
    RET                            ; Done.
