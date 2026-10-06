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
;    PL_FWD    ForwardPool: `forward pool NAME`
;    PL_REC    the PoolRecord island: the record after `as`
;    PL_HOLD   SavePoolCapacity: the capacity, a nonzero u16
;    PL_CMT    CommitPool: declare or complete the pool, write its blobs
;    PL_TYPE   resolve a named type: a pool's handle, or `id P`
;    PL_OPT    MakeOptionalHandle: `?` after a handle type
;    PL_OWNS   carry if a type ID is an owning type
;    PL_MARK   mark a table type as owning
;    PL_ENDP   a part's or the program's end: forward pools completed
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
; Address pool A's entry in PL_TAB in HL. A and BC are kept.

PL_AT:                         ; A is the pool's index.
    LD   L,A                       ; Its index,
    LD   H,0                       ; as a word:
    LD   D,H                       ; seven
    LD   E,L                       ; times
    ADD  HL,HL                     ; it:
    ADD  HL,HL                     ; four,
    ADD  HL,HL                     ; eight,
    OR   A                         ; less
    SBC  HL,DE                     ; one, seven.
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

;@ROUTINE CLOBBERS A,BC,DE,HL,CARRY,ZERO,SIGN,PARITY,HALFCARRY
; ForwardPool: `forward pool NAME`. The pool takes its ordinal now, and its
; name is declared (duplicate-name otherwise); it is completed later.

PL_FWD:                        ; The NAME is current.
    CALL EX_DECL                   ; Keep it and its position.

;@ROUTINE OUT A CLOBBERS BC,DE,HL,CARRY,ZERO,SIGN,PARITY,HALFCARRY
; Declare the current NAME a pool: a new entry (PL_NEW) and its symbol,
; whose payload is its index (duplicate-name if the name is taken). A
; returns the index.

PL_DECL:                       ; The NAME is current.
    CALL PL_NEW                    ; A new entry and its ordinal: A its index.
    PUSH AF                        ; Kept.
    LD   C,A                       ; The index, the symbol's payload.
    LD   B,0                       ; Its high byte.
    LD   D,PL_CLASS                ; A pool's class.
    CALL EX_PREP                   ; The provisional symbol.
    CALL SY_CMT                    ; Committed, private if marked.
    POP  AF                        ; The index.
    RET                            ; Done.

;@ROUTINE OUT A CLOBBERS BC,DE,HL,CARRY,ZERO,SIGN,PARITY,HALFCARRY
; A new pool entry for the retained name (AC_DNAME): its ordinal the next
; (RG_ADD), its record zero, its visibility, part and name. PL_CAP pools
; at most (DG_POOLS). A returns its index.

PL_NEW:                        ; The name is retained.
    LD   A,(PL_CNT)                ; The pools so far:
    CP   PL_CAP                    ; is there room?
    LD   A,DG_POOLS                ; No: capacity,
    JP   NC,DG_RAISE               ; pools.
    LD   A,(PL_CNT)                ; Its index,
    PUSH AF                        ; kept.
    CALL PL_AT                     ; HL is its entry.
    PUSH HL                        ; Kept.
    CALL RG_ADD                    ; HL is its ordinal.
    EX   DE,HL                     ; DE is it.
    POP  HL                        ; The entry:
    LD   (HL),E                    ; the ordinal,
    INC  HL                        ; low byte
    LD   (HL),D                    ; and high;
    INC  HL                        ; no record
    LD   (HL),0                    ; yet;
    INC  HL                        ; its visibility,
    LD   A,(AC_PRIV)               ; private
    LD   (HL),A                    ; or not;
    INC  HL                        ; its part,
    LD   A,(SRC_ID)                ; the one
    LD   (HL),A                    ; it is in;
    INC  HL                        ; its name's
    LD   DE,(AC_DNAME)             ; address in
    LD   (HL),E                    ; the source,
    INC  HL                        ; for
    LD   (HL),D                    ; diagnostics.
    LD   HL,PL_CNT                 ; One
    INC  (HL)                      ; more pool.
    POP  AF                        ; A is its index.
    RET                            ; Done.

;@ROUTINE OUT A,CARRY,ZERO CLOBBERS SIGN,PARITY,HALFCARRY,BC,DE,HL
; Island PoolRecord: the record a pool holds. Anything but a record's name
; is pool-needs-record, at it (the reference's poolDeclaration).

PL_REC:                        ; After `as`.
    CALL PR_PEEK                   ; A name?
    CP   TK_NAME                   ; If not,
    JR   NZ,.NEED                  ; a pool holds records.
    CALL PR_TAKE                   ; Take it.
    CALL SY_FIND                   ; A symbol of the name?
    JR   NC,.NEED                  ; No.
    INC  HL                        ; Its
    INC  HL                        ; class
    INC  HL                        ; byte:
    LD   A,(HL)                    ; a record
    CP   SY_RTYPE                  ; type?
    JR   NZ,.NEED                  ; No.
    INC  HL                        ; Its payload,
    LD   A,(HL)                    ; the record's type ID,
    LD   (PL_NREC),A               ; kept.
    RET                            ; Back to the engine.
.NEED:                         ; Not a record:
    CALL DG_RAISE                  ; pool-needs-record,
    DB   DG_PNREC                  ; at the token.

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

;@ROUTINE CLOBBERS A,BC,DE,HL,IX,CARRY,ZERO,SIGN,PARITY,HALFCARRY
; CommitPool: declare the pool, or complete its forward declaration
; (forward-mismatch if their visibilities differ; forward-incomplete if a
; private one is completed in another part); the pool may not exceed
; 65,535 bytes (out-of-range at its name); then write its slots (bss,
; NAME.slots), its information blob and, the first time an owning record
; needs it, the record's owner descriptor (TYPE.owners).

PL_CMT:                        ; The declaration is parsed.
    CALL EX_RENEW                  ; The name is current again.
    CALL PL_FIND                   ; A pool of the name?
    JR   NC,.NEW                   ; No: a new pool.
    PUSH AF                        ; Its index, kept.
    CALL PL_AT                     ; Its entry.
    INC  HL                        ; Its
    INC  HL                        ; record:
    LD   A,(HL)                    ; complete
    OR   A                         ; already?
    JR   Z,.FORWARD                ; No: this completes it.
    POP  AF                        ; It is
    JR   .NEW                      ; a duplicate, as EX_PREP will say.
.FORWARD:                      ; A forward pool's completion.
    INC  HL                        ; Its visibility
    LD   A,(AC_PRIV)               ; against
    CP   (HL)                      ; this one's:
    LD   A,DG_FWDNO                ; forward-mismatch
    JR   NZ,.ATNAME                ; if they differ.
    LD   A,(HL)                    ; A private one
    INC  HL                        ; must be
    OR   A                         ; completed
    JR   Z,.SHARED                 ; in its part
    LD   A,(SRC_ID)                ; (a public one
    CP   (HL)                      ; anywhere):
    LD   A,DG_UNMET                ; forward-incomplete
    JR   NZ,.ATNAME                ; otherwise.
.SHARED:                       ; The forward is completed here.
    POP  AF                        ; Its index.
    JR   .WRITE                    ; Write it.
.ATNAME:                       ; A is the diagnostic.
    LD   HL,AC_DPOS                ; At the
    JP   DG_AT                     ; pool's name.
.NEW:                          ; A new pool:
    CALL PL_DECL                   ; declared; A its index.
.WRITE:                        ; A is the pool's index.
    CALL PL_AT                     ; Its entry, HL.
    PUSH HL                        ; Kept.
    LD   A,(PL_NREC)               ; Its record
    INC  HL                        ; is
    INC  HL                        ; set: it is
    LD   (HL),A                    ; complete.
    CALL AG_SIZE                   ; The record's size,
    LD   DE,PL_SLOT                ; plus a slot's header,
    ADD  HL,DE                     ; is the slot size.
    LD   (PL_NSLOT),HL             ; Kept.
    LD   B,H                       ; BC is
    LD   C,L                       ; it.
    LD   DE,(PL_NCAP)              ; The capacity,
    LD   HL,PL_SLOT                ; and the pool's header:
.TOTAL:                        ; HL is the bytes so far.
    ADD  HL,BC                     ; A slot more,
    JR   C,.WIDE                   ; within 65,535.
    DEC  DE                        ; One fewer
    LD   A,D                       ; to
    OR   E                         ; count.
    JR   NZ,.TOTAL                 ; Until all are.
    LD   (PL_NSIZE),HL             ; The slots' bytes.
    CALL RG_ADD                    ; The slots' ordinal,
    LD   (PL_NSTOR),HL             ; kept.
    LD   DE,(PL_NSIZE)             ; Its size,
    LD   A,BL_KBSS                 ; bss.
    CALL BL_BSS                    ; Its record.
    LD   HL,PL_SLOTS               ; NAME.slots
    CALL PL_NAMED                  ; names it.
    CALL PL_DREF                   ; The record's descriptor, if it owns: DE, or 0.
    POP  HL                        ; The pool's entry:
    PUSH DE                        ; (the descriptor kept)
    LD   E,(HL)                    ; its
    INC  HL                        ; ordinal,
    LD   D,(HL)                    ; DE.
    EX   DE,HL                     ; HL is it.
    PUSH HL                        ; Kept for the name.
    LD   A,BL_KRO                  ; Read-only data.
    CALL BL_BEGIN                  ; The information blob.
    LD   A,BL_ABS16                ; The slots'
    LD   HL,(PL_NSTOR)             ; address,
    LD   DE,0                      ; a word.
    CALL BL_REF                    ; Referenced.
    LD   HL,(PL_NSLOT)             ; The slot size,
    CALL PL_WORD                   ; a word.
    LD   HL,(PL_NCAP)              ; The capacity,
    CALL PL_WORD                   ; a word.
    POP  BC                        ; The pool's ordinal.
    POP  HL                        ; The descriptor's,
    PUSH BC                        ; (the pool's kept)
    PUSH HL                        ; (and the descriptor's)
    LD   A,H                       ; or zero
    OR   L                         ; when the record
    JR   Z,.NONE                   ; owns nothing.
    LD   A,BL_ABS16                ; Its
    LD   DE,0                      ; address,
    CALL BL_REF                    ; a word.
    JR   .ENDED                    ; The blob is complete.
.NONE:                         ; No descriptor:
    CALL PL_WORD                   ; a zero word.
.ENDED:                        ; The information is complete.
    CALL BL_END                    ; Written.
    POP  DE                        ; The descriptor's ordinal, or zero.
    POP  HL                        ; The pool's ordinal,
    PUSH DE                        ; (the descriptor's kept)
    LD   DE,(AC_DNAME)             ; named
    LD   A,(AC_DLEN)               ; by the
    LD   B,A                       ; pool's
    CALL BL_NAME                   ; name.
    POP  HL                        ; A descriptor
    LD   A,(PL_DNEW)               ; still
    OR   A                         ; to write?
    RET  Z                         ; No.
    LD   A,(PL_NREC)               ; The record's,
    JP   PL_DESCW                  ; written; return.
.WIDE:                         ; Past 65,535 bytes:
    LD   A,DG_RANGE                ; out-of-range,
    JP   .ATNAME                   ; at the name.

;@ROUTINE IN HL CLOBBERS A,CARRY,ZERO,SIGN,PARITY,HALFCARRY
; Append the word HL to the blob, low byte first.

PL_WORD:                       ; HL is the word.
    LD   A,L                       ; Its low byte,
    CALL BL_BYTE                   ; then
    LD   A,H                       ; its high
    JP   BL_BYTE                   ; byte; return.

;@ROUTINE IN HL CLOBBERS A,BC,DE,HL,IX,CARRY,ZERO,SIGN,PARITY,HALFCARRY
; Name the blob just written, whose ordinal is PL_NSTOR, as the retained
; declaration name followed by the zero-terminated suffix at HL (.slots).

PL_NAMED:                      ; HL is the suffix.
    PUSH HL                        ; Kept.
    LD   HL,(AC_DNAME)             ; The name's
    LD   A,(AC_DLEN)               ; spelling
    LD   C,A                       ; and length.

;@ROUTINE IN C,HL CLOBBERS A,BC,DE,HL,IX,CARRY,ZERO,SIGN,PARITY,HALFCARRY
; Name the blob PL_NSTOR as the C bytes at HL followed by the
; zero-terminated suffix whose address is on the stack, above the return.

PL_NAMEC:                      ; HL and C are the name; the suffix pushed.
    LD   B,0                       ; The name is copied
    LD   DE,PL_TEXT                ; to the
    LDIR                           ; buffer,
    POP  HL                        ; then the suffix:
.COPY:                         ; DE is after the name so far.
    LD   A,(HL)                    ; The suffix's next byte:
    OR   A                         ; its end?
    JR   Z,.DONE                   ; Then the name is complete.
    LD   (DE),A                    ; Copied.
    INC  HL                        ; The next
    INC  DE                        ; one.
    JR   .COPY                     ; Until its end.
.DONE:                         ; DE is the name's end.
    LD   A,E                       ; Its length
    SUB  LOW(PL_TEXT)              ; from the buffer's start
    LD   B,A                       ; (under 256).
    LD   HL,(PL_NSTOR)             ; The blob's ordinal.
    LD   DE,PL_TEXT                ; The name.
    JP   BL_NAME                   ; Recorded; return.

PL_SLOTS: DB  ".slots",0       ; A pool's slots' name suffix.
PL_OWNRS: DB  ".owners",0      ; An owner descriptor's name suffix.

;@ROUTINE OUT DE CLOBBERS A,BC,HL,CARRY,ZERO,SIGN,PARITY,HALFCARRY
; The owner descriptor of the pool's record (PL_NREC), if it owns: DE
; returns its ordinal, taking the next one the first time (PL_DNEW
; nonzero then, for PL_CMT to write it after the pool's information blob,
; where the reference's descriptorOf makes it); zero when it owns nothing.

PL_DREF:                       ; The record is PL_NREC.
    XOR  A                         ; No descriptor
    LD   (PL_DNEW),A               ; to write yet.
    LD   D,A                       ; None,
    LD   E,A                       ; DE zero,
    LD   A,(PL_NREC)               ; when the record
    CALL PL_OWNS                   ; owns
    RET  NC                        ; nothing.
    LD   A,(PL_NREC)               ; The record's
    CALL PL_DSLOT                  ; cache word, HL.
    LD   E,(HL)                    ; Written
    INC  HL                        ; already?
    LD   D,(HL)                    ; DE is its ordinal,
    LD   A,D                       ; or
    OR   E                         ; zero
    RET  NZ                        ; when not.
    PUSH HL                        ; The word's high byte.
    CALL RG_ADD                    ; The next ordinal,
    EX   DE,HL                     ; DE, kept
    POP  HL                        ; in
    LD   (HL),D                    ; the
    DEC  HL                        ; cache.
    LD   (HL),E                    ; Both bytes.
    LD   A,1                       ; To be
    LD   (PL_DNEW),A               ; written.
    RET                            ; DE is the ordinal.

;@ROUTINE IN A OUT HL CLOBBERS A,DE,CARRY,ZERO,SIGN,PARITY,HALFCARRY
; Address table type A's word in PL_DESC in HL.

PL_DSLOT:                      ; A is a table type's ID.
    SUB  AG_FIRST                  ; Its index,
    ADD  A,A                       ; times two,
    LD   E,A                       ; as
    LD   D,0                       ; a word,
    LD   HL,PL_DESC                ; from
    ADD  HL,DE                     ; the cache.
    RET                            ; HL is the word.

;@ROUTINE IN A,HL CLOBBERS A,BC,DE,HL,IX,CARRY,ZERO,SIGN,PARITY,HALFCARRY
; Write the owner descriptor of table type A, whose ordinal HL is, as a
; rodata blob named TYPE.owners: its entries' count (capacity, "types",
; beyond 255), then the entries (PL_WALK).

PL_DESCW:                      ; A is the type, HL its ordinal.
    LD   (PL_NSTOR),HL             ; The blob's ordinal, for its name.
    LD   (PL_WTYPE),A              ; The type, kept.
    LD   HL,0                      ; Count
    LD   (PL_WCNT),HL              ; the entries:
    XOR  A                         ; a counting
    LD   (PL_WEMIT),A              ; walk.
    CALL PL_WROOT                  ; The entries counted.
    LD   HL,(PL_WCNT)              ; At most
    LD   A,H                       ; 255:
    OR   A                         ; more is
    LD   A,DG_META                 ; capacity,
    JP   NZ,DG_RAISE               ; types.
    LD   HL,(PL_NSTOR)             ; The blob,
    LD   A,BL_KRO                  ; read-only,
    CALL BL_BEGIN                  ; begun.
    LD   A,(PL_WCNT)               ; The count,
    CALL BL_BYTE                   ; first.
    LD   A,1                       ; An emitting
    LD   (PL_WEMIT),A              ; walk:
    CALL PL_WROOT                  ; the entries.
    CALL BL_END                    ; Written.
    LD   A,(PL_WTYPE)              ; Its name: the type's,
    CALL PL_TNAME                  ; at HL, B bytes,
    LD   C,B                       ; C of them,
    LD   DE,PL_OWNRS               ; then .owners:
    PUSH DE                        ; the suffix.
    JP   PL_NAMEC                  ; Named; return.

;@ROUTINE CLOBBERS A,BC,DE,HL,CARRY,ZERO,SIGN,PARITY,HALFCARRY
; Walk PL_WTYPE from offset zero with no pending array.

PL_WROOT:                      ; The type is PL_WTYPE.
    LD   A,(PL_WTYPE)              ; It,
    LD   HL,0                      ; at offset zero,
    LD   BC,0                      ; no array
    LD   DE,0                      ; pending.

;@ROUTINE IN A,BC,DE,HL CLOBBERS A,BC,DE,HL,CARRY,ZERO,SIGN,PARITY,HALFCARRY
; Visit the owning handles of type A at offset HL. BC and DE are the
; stride and count of the innermost enclosing array not yet given to an
; entry (count zero for none). Each owning handle is an entry: with the
; pending array's stride and count, or unstrided. An array met while one is
; pending expands the pending one, element by element, so only the
; innermost array strides (the reference's owningEntries). In a counting
; walk (PL_WEMIT zero) each entry adds one to PL_WCNT; in an emitting walk
; it is appended to the blob.

PL_WALK:                       ; A is the type.
    CALL PL_ISHND                  ; A handle? If not,
    JR   NC,.TABLE                 ; perhaps a table type.
    AND  AG_HID                    ; An identifier
    RET  NZ                        ; owns nothing.
    LD   A,(PL_WEMIT)              ; Counting?
    OR   A                         ; Then
    JR   Z,.COUNT                  ; count it.
    LD   A,D                       ; A pending
    OR   E                         ; array?
    LD   A,0                       ; Unstrided
    JR   Z,.FLAG                   ; without one,
    INC  A                         ; strided with.
.FLAG:                         ; A is the flag.
    CALL BL_BYTE                   ; The flag,
    CALL PL_WORD                   ; the offset,
    LD   A,D                       ; and
    OR   E                         ; with an array
    RET  Z                         ; pending,
    LD   H,B                       ; its
    LD   L,C                       ; stride
    CALL PL_WORD                   ; and
    EX   DE,HL                     ; its
    JP   PL_WORD                   ; count; return.
.COUNT:                        ; Count the entry.
    LD   HL,(PL_WCNT)              ; One
    INC  HL                        ; more
    LD   (PL_WCNT),HL              ; entry.
    RET                            ; Done.
.TABLE:                        ; A table type, or no aggregate.
    CP   AG_FIRST                  ; Below the table:
    RET  C                         ; a scalar.
    CP   AG_FIRST+AG_TCAP          ; Past it:
    RET  NC                        ; an open view or a File.
    PUSH HL                        ; The offset,
    PUSH BC                        ; the pending
    PUSH DE                        ; array,
    PUSH AF                        ; and the type, kept.
    CALL PL_OWNS                   ; Owning?
    JR   C,.OWNS                   ; Then visit it.
    POP  AF                        ; Not:
    POP  DE                        ; nothing
    POP  BC                        ; to
    POP  HL                        ; visit.
    RET                            ; Done.
.OWNS:                         ; An owning record or array.
    POP  AF                        ; The type; the offset and array stay.
    CALL AG_DESC                   ; Its descriptor, HL.
    LD   A,(HL)                    ; Its kind:
    CP   AG_KREC                   ; a record?
    INC  HL                        ; Its auxiliary byte,
    LD   A,(HL)                    ; the record's ordinal or the element type.
    INC  HL                        ; Its
    LD   C,(HL)                    ; count,
    INC  HL                        ; for
    LD   B,(HL)                    ; an array.
    JR   NZ,.ARRAY                 ; Not a record: an array.
    CALL AG_RENT                   ; A is the record's ordinal: its entry,
    LD   A,(HL)                    ; its first field,
    INC  HL                        ; and
    LD   B,(HL)                    ; its count, B,
    LD   C,A                       ; the next field's index, C.
.FIELD:                        ; The stack: count, stride, offset.
    LD   A,B                       ; Any field
    OR   A                         ; left?
    JR   Z,.FIELDS                 ; No.
    PUSH BC                        ; The loop, kept.
    LD   A,C                       ; The field's
    CALL AG_FIELD                  ; entry:
    INC  HL                        ; past
    INC  HL                        ; its
    INC  HL                        ; name,
    LD   A,(HL)                    ; its type,
    INC  HL                        ; and
    LD   E,(HL)                    ; its
    INC  HL                        ; offset,
    LD   D,(HL)                    ; DE.
    LD   HL,6                      ; The record's offset,
    ADD  HL,SP                     ; under the loop, count and stride:
    PUSH AF                        ; (the type kept)
    LD   A,(HL)                    ; its
    INC  HL                        ; low and
    LD   H,(HL)                    ; high
    LD   L,A                       ; bytes,
    ADD  HL,DE                     ; plus the field's: the field's offset.
    POP  AF                        ; The type.
    PUSH HL                        ; The field's offset, kept.
    LD   HL,4                      ; The pending count and stride,
    ADD  HL,SP                     ; under it and the loop:
    LD   E,(HL)                    ; the
    INC  HL                        ; count,
    LD   D,(HL)                    ; DE,
    INC  HL                        ; and
    LD   C,(HL)                    ; the
    INC  HL                        ; stride,
    LD   B,(HL)                    ; BC.
    POP  HL                        ; The field's offset.
    CALL PL_WALK                   ; The field visited.
    POP  BC                        ; The loop:
    INC  C                         ; the next field,
    DEC  B                         ; one fewer.
    JR   .FIELD                    ; Until all are.
.FIELDS:                       ; Every field is visited.
    POP  DE                        ; The pending
    POP  BC                        ; array and the offset,
    POP  HL                        ; dropped.
    RET                            ; Done.
.ARRAY:                        ; A is the element, BC the element count.
    LD   (PL_WELEM),A              ; The element type,
    LD   (PL_WLEN),BC              ; and its count, kept.
    POP  DE                        ; The pending
    POP  BC                        ; array, and
    POP  HL                        ; the offset.
    LD   A,D                       ; None
    OR   E                         ; pending? Then
    JR   Z,.THIS                   ; it strides; else expand that first.
.STEP:                         ; DE elements of BC bytes pend; each in turn:
    PUSH HL                        ; its offset,
    PUSH BC                        ; the stride
    PUSH DE                        ; and the count kept.
    LD   A,(PL_WELEM)              ; This array
    PUSH AF                        ; (its element
    LD   BC,(PL_WLEN)              ; and count
    PUSH BC                        ; kept across)
    CALL .THIS                     ; visited at HL, no array pending.
    POP  BC                        ; Its
    LD   (PL_WLEN),BC              ; element
    POP  AF                        ; and count
    LD   (PL_WELEM),A              ; restored.
    POP  DE                        ; The count,
    POP  BC                        ; the stride,
    POP  HL                        ; the offset.
    ADD  HL,BC                     ; The next element's offset.
    DEC  DE                        ; One fewer.
    LD   A,D                       ; Until
    OR   E                         ; all
    JR   NZ,.STEP                  ; are.
    RET                            ; Done.
.THIS:                         ; This array at HL, nothing pending.
    LD   A,(PL_WELEM)              ; Its element's
    PUSH HL                        ; (the offset kept)
    CALL AG_SIZE                   ; size,
    LD   B,H                       ; the
    LD   C,L                       ; stride;
    LD   DE,(PL_WLEN)              ; the count.
    POP  HL                        ; The offset.
    LD   A,(PL_WELEM)              ; The element
    JP   PL_WALK                   ; visited; return.

;@ROUTINE IN A OUT HL,B CLOBBERS A,C,DE,CARRY,ZERO,SIGN,PARITY,HALFCARRY
; The name of table type A, a record's: the symbol of class SY_RTYPE whose
; payload is A. HL returns its spelling and B its length.

PL_TNAME:                      ; A is the type.
    LD   C,A                       ; Kept.
    LD   A,(SY_CNT)                ; The symbols:
    LD   B,A                       ; each,
.LOOK:                         ; from the last.
    LD   A,B                       ; Symbol
    DEC  A                         ; B-1:
    CALL SY_AT                     ; its record.
    PUSH HL                        ; Kept.
    INC  HL                        ; Its
    INC  HL                        ; class
    INC  HL                        ; byte:
    LD   A,(HL)                    ; a record
    CP   SY_RTYPE                  ; type
    JR   NZ,.NEXT                  ; whose
    INC  HL                        ; payload
    LD   A,(HL)                    ; is
    CP   C                         ; the type?
    JR   NZ,.NEXT                  ; No.
    POP  HL                        ; The record:
    LD   E,(HL)                    ; its
    INC  HL                        ; spelling's
    LD   D,(HL)                    ; address
    INC  HL                        ; and
    LD   B,(HL)                    ; length.
    EX   DE,HL                     ; HL is the spelling.
    RET                            ; Done.
.NEXT:                         ; Not it.
    POP  HL                        ; Dropped.
    DJNZ .LOOK                     ; The one before.
    LD   B,0                       ; None: no name.
    RET                            ; HL is anything.

;@ROUTINE IN A OUT A CLOBBERS DE,HL,CARRY,ZERO,SIGN,PARITY,HALFCARRY
; A field of type A is committed: if it owns, its record will (PL_ROWN).

PL_FOWN:                       ; A is the field's type.
    PUSH AF                        ; Kept.
    CALL PL_OWNS                   ; Owning?
    JR   NC,.KEPT                  ; No.
    LD   A,1                       ; Its record
    LD   (PL_ROWN),A               ; owns.
.KEPT:                         ; Done.
    POP  AF                        ; The type.
    RET                            ; Back.

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
    JR   C,.NOT                    ; none for a scalar.
    CALL PL_OWNAT                  ; Its bit, A, and byte, HL.
    AND  (HL)                      ; Set?
    RET  Z                         ; No: carry clear.
    SCF                            ; It owns.
    RET                            ; Done.
.NOT:                          ; Not owning.
    OR   A                         ; Carry clear.
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

;@ROUTINE IN A OUT A CLOBBERS CARRY,ZERO,SIGN,PARITY,HALFCARRY
; A is a local's, parameter's or result's type: a handle, or an owning
; aggregate, is refused for now (native-unsupported, DG_NYI). A is kept.

PL_LATER:                     ; A is the type.
    PUSH AF                        ; Kept.
    PUSH DE                        ; (PL_OWNS
    PUSH HL                        ; clobbers these)
    CALL PL_OWNS                   ; Owning,
    POP  HL                        ; or
    POP  DE                        ; a handle
    JR   C,.REFUSE                 ; at all?
    POP  AF                        ; The type:
    CALL PL_ISHND                  ; a handle
    RET  NC                        ; of any form?
    PUSH AF                        ; Then refused.
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

;@ROUTINE CLOBBERS A,BC,DE,HL,CARRY,ZERO,SIGN,PARITY,HALFCARRY
; At a part's end (only its private pools) or the program's (every pool):
; a forward pool still without its declaration is forward-incomplete,
; naming it, at its name. C is nonzero at the program's end. Includes
; come before declarations, so a part's end meets only pools of parts that
; have ended (their private forwards reported then) and of its own.

PL_ENDP:                       ; C: nonzero at the program's end.
    LD   A,(PL_CNT)                ; The pools,
    OR   A                         ; any?
    RET  Z                         ; None.
    LD   B,A                       ; B of them,
.POOL:                         ; from the last.
    LD   A,B                       ; Pool
    DEC  A                         ; B-1:
    CALL PL_AT                     ; its entry.
    INC  HL                        ; Its
    INC  HL                        ; record:
    LD   A,(HL)                    ; complete?
    OR   A                         ; Then
    JR   NZ,.NEXT                  ; it is done.
    LD   A,C                       ; At the program's end
    OR   A                         ; every forward
    JR   NZ,.OPEN                  ; is incomplete;
    INC  HL                        ; at a part's end
    LD   A,(HL)                    ; only a private
    OR   A                         ; one, of the
    JR   Z,.NEXT                   ; part that ended.
    DEC  HL                        ; (back to the record byte)
.OPEN:                         ; Pool B-1 is incomplete.
    INC  HL                        ; Past
    INC  HL                        ; its visibility
    INC  HL                        ; and part,
    LD   E,(HL)                    ; its
    INC  HL                        ; name's
    LD   D,(HL)                    ; address.
    PUSH DE                        ; Kept.
    EX   DE,HL                     ; The name
    CALL PL_ASTOK                 ; is the current token.
    LD   A,DG_UNMET                ; forward-incomplete,
    CALL DG_SETN                   ; naming it,
    POP  HL                        ; at it.
    LD   A,DG_UNMET                ; forward-incomplete.
    JP   DG_SRC                    ; No return.
.NEXT:                         ; Pool B-1 is done.
    DJNZ .POOL                     ; The one before.
    RET                            ; Every pool is complete.

;@ROUTINE IN HL CLOBBERS A,B,C,HL,CARRY,ZERO,SIGN,PARITY,HALFCARRY
; Make the name whose spelling starts at HL the current NAME token: its
; length is counted over name characters.

PL_ASTOK:                     ; HL is the spelling.
    LD   (TK_PTR),HL               ; Its address.
    LD   B,0                       ; Its length so far.
.LEN:                          ; The next character:
    LD   A,(HL)                    ; a name's?
    CALL TK_ALNUM                  ; Carry if so.
    JR   NC,.DONE                  ; No: the name ends.
    INC  HL                        ; The next
    INC  B                         ; one.
    JR   .LEN                      ; Until the name ends.
.DONE:                         ; B is the length.
    LD   A,B                       ; It
    LD   (TK_LEN),A                ; is the token's.
    RET                            ; Done.
