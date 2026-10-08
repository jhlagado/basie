;==========================================================================
;  Record and pool declarations and owner descriptors
;==========================================================================
;
;  Overlay OWNERS, loaded above NAMES when a record or a pool is declared
;  (OV_PCALL, OVERLAY.ASM), so that it and FLOAT share the area's top: each
;  is loaded again when it is next needed, FLOAT keeping its workspace
;  resident. It holds the actions of declarations a program makes once, at
;  top level: a record's, its fields', and a pool's, which a program meets
;  rarely: `forward pool`, the record a pool holds, the pool's commit with
;  its slots and information blobs, and the forward pools checked at a
;  part's or the program's end. The commit writes an owning record's owner
;  descriptor (memory safety 5.10) as the reference's descriptorOf and
;  owningEntries make it: a rodata blob named TYPE.owners, its entries'
;  count, then per owning handle a flag byte, its offset and, for one
;  inside an array, the array's stride and element count. An array inside
;  an array takes one entry per outer element, after the entries of its
;  element: only the innermost array strides. Its scratch is POOLS.ASM's,
;  in AG_IBUF. Nothing here may load another overlay while it runs, but
;  for its blobs' writing (BL_END), which is resident.
;
;  Entries, a jump table at the overlay's start (OW_TAB):
;    OW_FWD    ForwardPool: `forward pool NAME`
;    OW_REC    the PoolRecord island: the record after `as`
;    OW_CMT    CommitPool: declare or complete the pool, write its blobs
;    OW_ENDP   a part's or the program's end: forward pools completed
;    OW_LDESC  the owner descriptor of a local owning array being freed,
;              waiting until its routine's blob is written
;    OW_RBEG, OW_FIELD, OW_PLACE, OW_RECOK  a record's declaration:
;              BeginRecord, each field's begin and commit, CommitRecord
;              (AC_REC, AC_FIELD, AC_PLACE, AC_RECOK reach them)
;  A routine's body's actions for handles, once here, are resident
;  (OWNBODY.ASM).

; Entries, a jump each at the overlay's start (OV_PCALL, OVERLAY.ASM).

OW_TAB:                        ; Entry 0:
    JP   OW_FWD                    ; ForwardPool;
    JP   OW_REC                    ; 3: PoolRecord;
    JP   OW_CMT                    ; 6: CommitPool;
    JP   OW_ENDP                   ; 9: a part's or the program's end;
    JP   OW_LDESC                  ; 12: a local owning array's descriptor;
    JP   OW_RBEG                   ; 15: BeginRecord;
    JP   OW_FIELD                  ; 18: BeginRecordField;
    JP   OW_PLACE                  ; 21: CommitRecordField;
    JP   OW_RECOK                  ; 24: CommitRecord.

;@ROUTINE CLOBBERS A,BC,DE,HL,CARRY,ZERO,SIGN,PARITY,HALFCARRY
; ForwardPool: `forward pool NAME`, its line ended. The pool takes its
; ordinal now, and its name is declared (duplicate-name otherwise); it is
; completed later.

OW_FWD:                        ; The name is retained (BeginPool).
    CALL EX_RENEW                  ; The NAME is current again.

;@ROUTINE OUT A CLOBBERS BC,DE,HL,CARRY,ZERO,SIGN,PARITY,HALFCARRY
; Declare the current NAME a pool: a new entry (OW_NEW) and its symbol,
; whose payload is its index (duplicate-name if the name is taken). A
; returns the index.

OW_DECL:                       ; The NAME is current.
    CALL OW_NEW                    ; A new entry and its ordinal: A its index.
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

OW_NEW:                        ; The name is retained.
    LD   A,(PL_CNT)                ; The pools so far:
    CP   PL_CAP                    ; is there room?
    LD   A,DG_POOLS                ; No: capacity,
    JP   NC,DG_ISSUE               ; pools.
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
    LD   DE,(AC_DNAME)             ; spelling,
    LD   (HL),E                    ; its
    INC  HL                        ; address
    LD   (HL),D                    ; and
    INC  HL                        ; length,
    LD   A,(AC_DLEN)               ; and its
    LD   (HL),A                    ; offset,
    INC  HL                        ; for
    LD   DE,(AC_DPOS)              ; diagnostics
    LD   (HL),E                    ; when its
    INC  HL                        ; part may
    LD   (HL),D                    ; be gone.
    LD   HL,PL_CNT                 ; One
    INC  (HL)                      ; more pool.
    POP  AF                        ; A is its index.
    RET                            ; Done.


;@ROUTINE OUT A,CARRY,ZERO CLOBBERS SIGN,PARITY,HALFCARRY,BC,DE,HL
; Island PoolRecord: the record a pool holds. Anything but a record's name
; is pool-needs-record, at it (the reference's poolDeclaration).

OW_REC:                        ; After `as`.
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

;@ROUTINE CLOBBERS A,BC,DE,HL,IX,IY,CARRY,ZERO,SIGN,PARITY,HALFCARRY
; CommitPool: declare the pool, or complete its forward declaration
; (forward-mismatch if their visibilities differ; forward-incomplete if a
; private one is completed in another part); the pool may not exceed
; 65,535 bytes (out-of-range at its name); then write its slots (bss,
; NAME.slots), its information blob and, the first time an owning record
; needs it, the record's owner descriptor (TYPE.owners).

OW_CMT:                        ; The declaration is parsed.
    XOR  A                         ; The pool's words are written,
    LD   (PL_WEMIT),A              ; never staged (OW_OUT).
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
    CALL OW_DECL                   ; declared; A its index.
.WRITE:                        ; A is the pool's index.
    CALL PL_AT                     ; Its entry, HL.
    PUSH HL                        ; Kept.
    LD   A,(PL_NREC)               ; Its record
    INC  HL                        ; is
    INC  HL                        ; set: it is
    LD   (HL),A                    ; complete.
    CALL AG_SIZE                   ; The record's size,
    LD   DE,PL_SLOT                ; plus a slot's header,
    ADD  HL,DE                     ; is the slot size,
    JP   C,.WIDE                   ; within 65,535.
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
    LD   HL,OW_SLOTS               ; NAME.slots
    CALL OW_NAMED                  ; names it.
    CALL OW_DREF                   ; The record's descriptor, if it owns: DE, or 0.
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
    CALL OW_WORD                   ; a word.
    LD   HL,(PL_NCAP)              ; The capacity,
    CALL OW_WORD                   ; a word.
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
    CALL OW_WORD                   ; a zero word.
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
    JP   OW_DESC                   ; written; return.
.WIDE:                         ; Past 65,535 bytes:
    LD   A,DG_RANGE                ; out-of-range,
    JP   .ATNAME                   ; at the name.

;@ROUTINE IN HL CLOBBERS A,CARRY,ZERO,SIGN,PARITY,HALFCARRY
; Append the word HL to the blob, low byte first.

OW_WORD:                       ; HL is the word.
    LD   A,L                       ; Its low byte,
    CALL OW_OUT                    ; then
    LD   A,H                       ; its high
    JP   OW_OUT                    ; byte; return.

;@ROUTINE IN A CLOBBERS CARRY,ZERO,SIGN,PARITY,HALFCARRY
; Append byte A to the blob, or, in a staging walk (PL_WEMIT two), stage
; it at the cursor (AG_PUT). Every register but F is kept. OW_LDESC's
; walk alone stages; a pool's words and every other walk are written.

OW_OUT:                        ; A is the byte.
    PUSH AF                        ; Kept.
    LD   A,(PL_WEMIT)              ; Only a staging
    CP   2                         ; walk's
    JR   Z,.STAGE                  ; is staged; any other
    POP  AF                        ; goes to the
    JP   BL_BYTE                   ; blob; return.
.STAGE:                        ; A staging walk's:
    POP  AF                        ; the byte
    PUSH DE                        ; (DE kept)
    CALL AG_PUT                    ; is staged.
    POP  DE                        ; DE again.
    RET                            ; Done.

;@ROUTINE IN HL CLOBBERS A,BC,DE,HL,IX,CARRY,ZERO,SIGN,PARITY,HALFCARRY
; Name the blob just written, whose ordinal is PL_NSTOR, as the retained
; declaration name followed by the zero-terminated suffix at HL (.slots).

OW_NAMED:                      ; HL is the suffix.
    PUSH HL                        ; Kept.
    LD   HL,(AC_DNAME)             ; The name's
    LD   A,(AC_DLEN)               ; spelling
    LD   C,A                       ; and length.

;@ROUTINE IN C,HL CLOBBERS A,BC,DE,HL,IX,CARRY,ZERO,SIGN,PARITY,HALFCARRY
; Name the blob PL_NSTOR as the C bytes at HL followed by the
; zero-terminated suffix whose address is on the stack, above the return.

OW_NAMEC:                      ; HL and C are the name; the suffix pushed.
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

OW_SLOTS: DB  ".slots",0       ; A pool's slots' name suffix.

;@ROUTINE OUT DE CLOBBERS A,BC,HL,CARRY,ZERO,SIGN,PARITY,HALFCARRY
; The owner descriptor of the pool's record (PL_NREC), if it owns: DE
; returns its ordinal, taking the next one the first time (PL_DNEW
; nonzero then, for OW_CMT to write it after the pool's information blob,
; where the reference's descriptorOf makes it); zero when it owns nothing.

OW_DREF:                       ; The record is PL_NREC.
    XOR  A                         ; No descriptor
    LD   (PL_DNEW),A               ; to write yet.
    LD   D,A                       ; None,
    LD   E,A                       ; DE zero,
    LD   A,(PL_NREC)               ; when the record
    CALL PL_OWNS                   ; owns
    RET  NC                        ; nothing.
    LD   A,(PL_NREC)               ; The record's
    CALL OW_DSLOT                  ; cache word, HL.
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

OW_DSLOT:                      ; A is a table type's ID.
    SUB  AG_FIRST                  ; Its index,
    ADD  A,A                       ; times two,
    LD   E,A                       ; as
    LD   D,0                       ; a word,
    LD   HL,PL_DESC                ; from
    ADD  HL,DE                     ; the cache.
    RET                            ; HL is the word.

;@ROUTINE CLOBBERS A,BC,DE,HL,CARRY,ZERO,SIGN,PARITY,HALFCARRY
; At a part's end (only its private pools) or the program's (every pool):
; a forward pool still without its declaration is forward-incomplete,
; naming it, at its name, the first in their order as the reference's
; endPart finds it. The program has ended when the next token is the
; end of the source (RequireMain, before TokenEof). Includes
; come before declarations, so a part's end meets only pools of parts that
; have ended (their private forwards reported then) and of its own.

OW_ENDP:                       ; A part or the program has ended.
    CALL PR_PEEK                   ; The next token: C is
    LD   C,A                       ; zero (TK_EOF) at the program's end.
    LD   A,(PL_CNT)                ; The pools,
    OR   A                         ; any?
    RET  Z                         ; None.
    LD   B,A                       ; B of them,
.POOL:                         ; from the first.
    LD   A,(PL_CNT)                ; Pool
    SUB  B                         ; PL_CNT-B:
    CALL PL_AT                     ; its entry.
    INC  HL                        ; Its
    INC  HL                        ; record:
    LD   A,(HL)                    ; complete?
    OR   A                         ; Then
    JR   NZ,.NEXT                  ; it is done.
    LD   A,C                       ; At the program's end
    OR   A                         ; every forward
    JR   Z,.OPEN                   ; is incomplete;
    INC  HL                        ; at a part's end
    LD   A,(HL)                    ; only a private
    OR   A                         ; one, of the
    JR   Z,.NEXT                   ; part that ended.
    DEC  HL                        ; (back to the record byte)
.OPEN:                         ; The pool is incomplete.
    INC  HL                        ; Past
    INC  HL                        ; its visibility,
    LD   A,(HL)                    ; its part
    PUSH AF                        ; (kept);
    INC  HL                        ; its name's
    PUSH HL                        ; spelling,
    LD   A,DG_UNMET                ; forward-incomplete,
    CALL DG_SETN                   ; naming it;
    POP  HL                        ; then
    LD   DE,PL_EOFF-PL_ENAME       ; its
    ADD  HL,DE                     ; offset
    LD   A,(HL)                    ; in
    INC  HL                        ; its
    LD   H,(HL)                    ; part,
    LD   L,A                       ; HL,
    POP  DE                        ; D the part:
    LD   E,DG_UNMET                ; forward-incomplete.
    JP   DG_PLACE                  ; No return.
.NEXT:                         ; The pool is done.
    DJNZ .POOL                     ; The one after.
    RET                            ; Every pool is complete.

;@ROUTINE IN A,HL CLOBBERS A,BC,DE,HL,IX,IY,CARRY,ZERO,SIGN,PARITY,HALFCARRY
; Write the owner descriptor of table type A, whose ordinal HL is, as a
; rodata blob named TYPE.owners: its entries' count (capacity, "types",
; beyond 255), then the entries (OW_WALK).

OW_DESC:                       ; A is the type, HL its ordinal.
    LD   (PL_NSTOR),HL             ; The blob's ordinal, for its name.
    LD   (PL_WTYPE),A              ; The type, kept.
    LD   HL,0                      ; Count
    LD   (PL_WCNT),HL              ; the entries:
    XOR  A                         ; a counting
    LD   (PL_WEMIT),A              ; walk.
    CALL OW_ROOT                   ; The entries counted.
    LD   HL,(PL_WCNT)              ; At most
    LD   A,H                       ; 255:
    OR   A                         ; more is
    JR   NZ,.MANY                  ; capacity.
    LD   HL,(PL_NSTOR)             ; The blob,
    LD   A,BL_KRO                  ; read-only,
    CALL BL_BEGIN                  ; begun.
    LD   A,(PL_WCNT)               ; The count,
    CALL BL_BYTE                   ; first.
    LD   A,1                       ; An emitting
    LD   (PL_WEMIT),A              ; walk:
    CALL OW_ROOT                   ; the entries.
    CALL BL_END                    ; Written.
    LD   A,(PL_WTYPE)              ; Its name: the type's,
    CALL OW_TNAME                  ; at HL, B bytes,
    LD   C,B                       ; C of them,
    LD   DE,OW_SUFX                ; then .owners:
    PUSH DE                        ; the suffix.
    JP   OW_NAMEC                  ; Named; return.
.MANY:                         ; More than 255 entries:
    CALL PR_PEEK                   ; at the token after the line's end,
    LD   A,DG_META                 ; capacity,
    JP   DG_ISSUE                  ; types.

;@ROUTINE CLOBBERS A,BC,DE,HL,CARRY,ZERO,SIGN,PARITY,HALFCARRY
; Walk PL_WTYPE from offset zero under the root frame, whose length is
; zero. IY is kept.

OW_ROOT:                       ; The type is PL_WTYPE.
    PUSH IY                        ; The caller's IY, kept.
    LD   HL,0                      ; The root frame:
    PUSH HL                        ; a length of zero.
    LD   IY,0                      ; IY
    ADD  IY,SP                     ; addresses it.
    LD   A,(PL_WTYPE)              ; The type,
    CALL OW_WALK                   ; at offset zero, walked.
    POP  HL                        ; The root frame dropped.
    POP  IY                        ; The caller's IY.
    RET                            ; Done.

;@ROUTINE IN A,HL,IY CLOBBERS A,BC,DE,HL,CARRY,ZERO,SIGN,PARITY,HALFCARRY
; Visit the owning handles of type A at offset HL within the innermost
; enclosing array's element, whose frame IY addresses: each is an entry
; (OW_ENT) as the reference's owningEntries makes it. An array pushes a
; frame of four words (IY+0 its length, +2 its stride, +4 its offset, +6
; the frame outside it) and walks its element from offset zero. IY is kept.

OW_WALK:                       ; A is the type.
    CALL PL_ISHND                  ; A handle? If not,
    JR   NC,.TABLE                 ; perhaps a table type.
    AND  AG_HID                    ; An identifier
    RET  NZ                        ; owns nothing; an owner (A zero,
    JP   OW_ENT                    ; unstrided) is an entry; return.
.TABLE:                        ; A table type, or no aggregate.
    CP   AG_FIRST                  ; Below the table:
    RET  C                         ; a scalar.
    CP   AG_FIRST+AG_TCAP          ; Past it:
    RET  NC                        ; an open view or a File.
    PUSH HL                        ; The offset
    PUSH AF                        ; and the type, kept.
    CALL PL_OWNS                   ; Owning?
    JR   C,.OWNS                   ; Then visit it.
    POP  AF                        ; Not:
    POP  HL                        ; nothing to visit.
    RET                            ; Done.
.OWNS:                         ; An owning record or array.
    POP  AF                        ; The type; the offset stays.
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
.FIELD:                        ; The record's offset is on the stack.
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
    LD   HL,2                      ; The record's offset,
    ADD  HL,SP                     ; under the loop:
    PUSH AF                        ; (the type kept)
    LD   A,(HL)                    ; its
    INC  HL                        ; low and
    LD   H,(HL)                    ; high
    LD   L,A                       ; bytes,
    ADD  HL,DE                     ; plus the field's: the field's offset.
    POP  AF                        ; The type.
    CALL OW_WALK                   ; The field visited.
    POP  BC                        ; The loop:
    INC  C                         ; the next field,
    DEC  B                         ; one fewer.
    JR   .FIELD                    ; Until all are.
.FIELDS:                       ; Every field is visited.
    POP  HL                        ; The offset, dropped.
    RET                            ; Done.
.ARRAY:                        ; A is the element, BC the element count.
    LD   (PL_WELEM),A              ; The element type,
    LD   (PL_WLEN),BC              ; and its count, kept.
    POP  HL                        ; The array's offset.
    PUSH IY                        ; The frame outside,
    PUSH HL                        ; the offset,
    CALL AG_SIZE                   ; the element's size,
    PUSH HL                        ; the stride,
    LD   HL,(PL_WLEN)              ; and the
    PUSH HL                        ; length:
    LD   IY,0                      ; the array's
    ADD  IY,SP                     ; frame.
    LD   A,(PL_WELEM)              ; Its element
    LD   HL,0                      ; from offset zero,
    CALL OW_WALK                   ; visited.
    POP  HL                        ; The
    POP  HL                        ; frame
    POP  HL                        ; dropped,
    POP  IY                        ; the one outside restored.
    RET                            ; Done.

;@ROUTINE IN A,BC,DE,HL,IY CLOBBERS A,BC,DE,HL,CARRY,ZERO,SIGN,PARITY,HALFCARRY
; An owning handle at offset HL in the element of frame IY: unstrided when
; A is zero, else strided by BC with DE elements. In an array's frame an
; unstrided entry takes the array's stride and length, and a strided one
; becomes one entry for each of its elements, each passed to the frame
; outside; in the root frame the entry is counted (PL_WEMIT zero, in
; PL_WCNT) or appended to the blob. IY is kept.

OW_ENT:                        ; A is the flag.
    PUSH AF                        ; Kept.
    LD   A,(IY+0)                  ; The root
    OR   (IY+1)                    ; frame?
    JR   Z,.ROOT                   ; Then the entry is made.
    PUSH DE                        ; (the count kept)
    LD   E,(IY+4)                  ; The offset
    LD   D,(IY+5)                  ; of the array
    ADD  HL,DE                     ; is added.
    POP  DE                        ; The count.
    POP  AF                        ; Strided?
    OR   A                         ; Then
    JR   NZ,.EXPAND                ; one for each element.
    LD   C,(IY+2)                  ; The array's
    LD   B,(IY+3)                  ; stride
    LD   E,(IY+0)                  ; and
    LD   D,(IY+1)                  ; length
    INC  A                         ; stride it,
    JR   .OUTER                    ; passed outward; return.
.EXPAND:                       ; DE elements of BC bytes, each:
    PUSH DE                        ; the count
    PUSH BC                        ; and stride kept,
    LD   C,(IY+0)                  ; this
    LD   B,(IY+1)                  ; array's length,
    LD   E,(IY+2)                  ; and its
    LD   D,(IY+3)                  ; stride.
.STEP:                         ; HL the element's entry, BC elements left.
    PUSH DE                        ; The array's stride,
    PUSH BC                        ; the elements left,
    PUSH HL                        ; and the offset kept.
    LD   HL,6                      ; The entry's
    ADD  HL,SP                     ; stride
    LD   C,(HL)                    ; and
    INC  HL                        ; count,
    LD   B,(HL)                    ; under
    INC  HL                        ; them,
    LD   E,(HL)                    ; read
    INC  HL                        ; back.
    LD   D,(HL)                    ; The same
    POP  HL                        ; offset,
    PUSH HL                        ; strided,
    LD   A,1                       ; passed
    CALL .OUTER                    ; outward.
    POP  HL                        ; The offset,
    POP  BC                        ; the elements left
    POP  DE                        ; and the stride:
    ADD  HL,DE                     ; the next element's.
    DEC  BC                        ; One fewer.
    LD   A,B                       ; Until
    OR   C                         ; all
    JR   NZ,.STEP                  ; are.
    POP  BC                        ; The entry's stride
    POP  DE                        ; and count dropped.
    RET                            ; Done.
.OUTER:                        ; Pass the entry to the frame outside.
    PUSH IY                        ; This frame, kept.
    PUSH HL                        ; (the offset kept)
    LD   L,(IY+6)                  ; The frame
    LD   H,(IY+7)                  ; outside
    PUSH HL                        ; becomes
    POP  IY                        ; IY.
    POP  HL                        ; The offset.
    CALL OW_ENT                    ; The entry made there.
    POP  IY                        ; This frame again.
    RET                            ; Back.
.ROOT:                         ; The entry itself.
    LD   A,(PL_WEMIT)              ; Counting?
    OR   A                         ; Then
    JR   NZ,.WRITE                 ; count it:
    POP  AF                        ; (the flag dropped)
    LD   HL,(PL_WCNT)              ; one
    INC  HL                        ; more
    LD   (PL_WCNT),HL              ; entry.
    RET                            ; Done.
.WRITE:                        ; Append it.
    POP  AF                        ; The flag,
    CALL OW_OUT                    ; first;
    PUSH AF                        ; (kept)
    CALL OW_WORD                   ; the offset;
    POP  AF                        ; strided?
    OR   A                         ; If not,
    RET  Z                         ; no more.
    LD   H,B                       ; The
    LD   L,C                       ; stride
    CALL OW_WORD                   ; and
    EX   DE,HL                     ; the
    JP   OW_WORD                   ; count; return.

OW_NCAP EQU  31                ; Bytes of a name the name stream keeps.
OW_SOFF EQU  64                ; A staged descriptor's offset in AG_IBUF, past PL_TEXT.
OW_SCAP EQU  136               ; Entries a staged descriptor may hold, seven bytes each.

;@ROUTINE OUT HL CLOBBERS A,BC,DE,IX,IY,CARRY,ZERO,SIGN,PARITY,HALFCARRY
; The owner descriptor of a local owning array of type PL_WTYPE, which is
; being freed (emitFrees): as the reference's, a new one at each free, named
; TYPE.owners. Its entries are counted (capacity, "types", beyond 255;
; "object size" beyond what the staging holds), staged after the walk's
; own bytes in AG_IBUF (OW_SOFF), then moved to its start and kept until
; the routine's blob is written (RG_DEFER), named from the name heap. HL
; returns its ordinal.

OW_LDESC:                      ; PL_WTYPE is the type.
    LD   HL,0                      ; Count
    LD   (PL_WCNT),HL              ; the
    XOR  A                         ; entries:
    LD   (PL_WEMIT),A              ; a counting
    CALL OW_ROOT                   ; walk.
    LD   HL,(PL_WCNT)              ; At most
    LD   A,H                       ; 255
    OR   A                         ; (types
    JR   NZ,.MANY                  ; beyond),
    LD   A,L                       ; and as many
    CP   OW_SCAP+1                 ; as the staging holds
    JP   NC,AG_EDATA               ; (object size beyond).
    LD   HL,AG_IBUF                ; The bytes
    LD   (AG_IBASE),HL             ; are staged
    LD   HL,OW_SOFF                ; in the buffer,
    LD   (AG_OPOS),HL              ; after the walk's:
    LD   A,(PL_WCNT)               ; the count
    CALL AG_PUT                    ; first,
    LD   A,2                       ; then
    LD   (PL_WEMIT),A              ; a staging
    CALL OW_ROOT                   ; walk,
    XOR  A                         ; after which
    LD   (PL_WEMIT),A              ; nothing is staged.
    LD   DE,PL_TEXT                ; The name:
    LD   A,(PL_WTYPE)              ; the type's,
    CALL OW_TYNAM                  ; then
    LD   HL,OW_SUFX                ; .owners,
.SUFFIX:                       ; DE is past the name so far.
    LD   A,(HL)                    ; Its
    OR   A                         ; end?
    JR   Z,.NAMED                  ; Then it is made.
    LD   (DE),A                    ; The
    INC  HL                        ; next
    INC  DE                        ; byte.
    JR   .SUFFIX                   ; Until the end.
.NAMED:                        ; DE is the name's end.
    LD   A,E                       ; Its
    SUB  LOW(PL_TEXT)              ; length,
    LD   C,A                       ; C,
    LD   B,0                       ; is kept
    CALL NH_ALLOC                  ; below the heap, at DE,
    PUSH BC                        ; (kept)
    PUSH DE                        ; where it stays
    LD   HL,PL_TEXT                ; while
    LDIR                           ; the descriptor waits.
    LD   HL,(AC_DNAME)             ; The declaration's
    LD   A,(AC_DLEN)               ; name,
    POP  DE                        ; kept,
    POP  BC                        ; gives way
    PUSH HL                        ; to the
    PUSH AF                        ; descriptor's
    LD   (AC_DNAME),DE             ; for
    LD   A,C                       ; RG_DEFER.
    LD   (AC_DLEN),A               ; The bytes
    LD   HL,(AG_OPOS)              ; staged,
    LD   DE,OW_SOFF                ; after
    OR   A                         ; the walk's,
    SBC  HL,DE                     ; HL of them,
    LD   (AG_OSIZE),HL             ; are the object,
    LD   B,H                       ; moved
    LD   C,L                       ; to the
    LD   HL,AG_IBUF+OW_SOFF        ; staging's
    LD   DE,AG_IBUF                ; start;
    LDIR                           ; then
    CALL RG_DEFER                  ; kept: BC is its ordinal.
    POP  AF                        ; The declaration's
    LD   (AC_DLEN),A               ; name
    POP  HL                        ; again.
    LD   (AC_DNAME),HL             ; HL is
    LD   H,B                       ; the
    LD   L,C                       ; ordinal.
    RET                            ; Done.
.MANY:                         ; More than 255 entries:
    CALL DG_RAISE                  ; capacity,
    DB   DG_META                   ; types.

;@ROUTINE IN A,DE OUT DE CLOBBERS A,BC,HL,CARRY,ZERO,SIGN,PARITY,HALFCARRY
; Write the name of type A at DE, as the reference's typeName: a scalar's
; keyword, a handle's pool with `id ` before and `?` after as its form
; has them, a record's name, string[N], or an array's element's then [N];
; DE returns past it. Bytes past OW_NCAP from PL_TEXT are not written, as
; the name stream keeps only 31.

OW_TYNAM:                      ; A is the type.
    CP   AG_HND                    ; A handle?
    JR   NC,.HANDLE                ; Its pool's.
    CP   AG_FIRST                  ; A table type?
    JR   NC,.TABLE                 ; Its descriptor says.
    ADD  A,KW_TYPE                 ; A scalar: the keyword
    LD   C,A                       ; whose kind it is,
    LD   HL,KW_TAB                 ; from the first.
.KEY:                          ; HL is an entry.
    PUSH HL                        ; Its spelling, kept.
.SKIP:                         ; Past
    BIT  7,(HL)                    ; the
    INC  HL                        ; spelling
    JR   Z,.SKIP                   ; to its kind:
    LD   A,(HL)                    ; is it
    INC  HL                        ; the type's?
    CP   C                         ; If so,
    JR   Z,.WORD                   ; its spelling;
    POP  AF                        ; if not,
    JR   .KEY                      ; the next.
.WORD:                         ; The spelling:
    POP  HL                        ; HL.
.SPELL:                        ; Each byte,
    LD   A,(HL)                    ; the last
    AND  $7F                       ; without its bit 7,
    CALL OW_PUTC                   ; written,
    BIT  7,(HL)                    ; until
    INC  HL                        ; the
    JR   Z,.SPELL                  ; last.
    RET                            ; Done.
.HANDLE:                       ; A handle: its form
    SUB  AG_HND                    ; and pool,
    LD   C,A                       ; C.
    AND  AG_HID                    ; An identifier
    JR   Z,.OWNER                  ; has
    LD   HL,OW_IDS                 ; `id `
    CALL OW_STR                    ; first.
.OWNER:                        ; Then the pool's name:
    PUSH DE                        ; (the cursor kept)
    LD   A,C                       ; its
    RRCA                           ; index,
    RRCA                           ; times
    AND  $3F                       ; PL_LEN,
    LD   L,A                       ; ten,
    LD   H,0                       ; from
    ADD  HL,HL                     ; PL_TAB's
    LD   D,H                       ; name
    LD   E,L                       ; field:
    ADD  HL,HL                     ; HL
    ADD  HL,HL                     ; addresses
    ADD  HL,DE                     ; its
    LD   DE,PL_TAB+PL_ENAME        ; address,
    ADD  HL,DE                     ; then
    CALL WD_GET                    ; its
    LD   B,(HL)                    ; length:
    EX   DE,HL                     ; HL the spelling,
    POP  DE                        ; DE the cursor.
.PNAME:                        ; B bytes,
    LD   A,(HL)                    ; each
    CALL OW_PUTC                   ; written;
    INC  HL                        ; the
    DJNZ .PNAME                    ; next.
    LD   A,C                       ; An optional
    AND  AG_HOPT                   ; one
    RET  Z                         ; has
    LD   A,'?'                     ; `?`
    JP   OW_PUTC                   ; after; return.
.TABLE:                        ; A table type:
    PUSH AF                        ; (the type kept)
    PUSH DE                        ; (the cursor kept)
    CALL AG_DESC                   ; its descriptor, HL.
    POP  DE                        ; The cursor.
    LD   A,(HL)                    ; Its kind:
    CP   AG_KREC                   ; a record's
    JR   Z,.RECORD                 ; name;
    LD   B,A                       ; (kept)
    POP  AF                        ; (the type dropped)
    LD   A,B                       ; a
    CP   AG_KSTR                   ; string's
    JR   Z,.STRING                 ; capacity;
    INC  HL                        ; an array's
    LD   A,(HL)                    ; element,
    INC  HL                        ; and
    LD   C,(HL)                    ; its
    INC  HL                        ; length,
    LD   B,(HL)                    ; kept,
    PUSH BC                        ; the element's
    CALL OW_TYNAM                  ; name first.
    POP  HL                        ; The length
    JR   .BOUND                    ; follows.
.STRING:                       ; A string:
    INC  HL                        ; its
    LD   L,(HL)                    ; capacity,
    LD   H,0                       ; kept,
    PUSH HL                        ; after
    LD   HL,OW_STRS                ; `string`.
    CALL OW_STR                    ; Written;
    POP  HL                        ; then the capacity.
.BOUND:                        ; HL is the bound:
    LD   A,'['                     ; in
    CALL OW_PUTC                   ; brackets,
    CALL OW_DEC                    ; in
    LD   A,']'                     ; decimal.
    JP   OW_PUTC                   ; Return.
.RECORD:                       ; A record:
    POP  AF                        ; its type,
    PUSH DE                        ; (the cursor kept)
    CALL OW_TNAME                  ; its name, B bytes at HL.
    POP  DE                        ; The cursor.
    INC  B                         ; None
    DEC  B                         ; is
    RET  Z                         ; nothing.
.RNAME:                        ; Each byte
    LD   A,(HL)                    ; is
    CALL OW_PUTC                   ; written;
    INC  HL                        ; the
    DJNZ .RNAME                    ; next.
    RET                            ; Done.

;@ROUTINE IN A,DE OUT DE CLOBBERS CARRY,ZERO,SIGN,PARITY,HALFCARRY
; Write byte A at DE and step past it, unless DE has reached OW_NCAP bytes
; from PL_TEXT. Every other register is kept.

OW_PUTC:                       ; A is the byte.
    PUSH HL                        ; Keep HL
    PUSH AF                        ; and the byte.
    LD   HL,PL_TEXT+OW_NCAP        ; Below
    LD   A,E                       ; the
    SUB  L                         ; name's
    LD   A,D                       ; cap?
    SBC  A,H                       ; (carry)
    JR   NC,.FULL                  ; Not then.
    POP  AF                        ; The byte
    LD   (DE),A                    ; is written,
    INC  DE                        ; DE past it.
    POP  HL                        ; HL again.
    RET                            ; Done.
.FULL:                         ; Past the cap:
    POP  AF                        ; nothing
    POP  HL                        ; is
    RET                            ; written.

;@ROUTINE IN DE,HL OUT DE,HL CLOBBERS A,CARRY,ZERO,SIGN,PARITY,HALFCARRY
; Write the zero-terminated bytes at HL at DE (OW_PUTC). BC is kept.

OW_STR:                        ; HL is the text.
    LD   A,(HL)                    ; Its
    OR   A                         ; end?
    RET  Z                         ; Done.
    CALL OW_PUTC                   ; Written;
    INC  HL                        ; the
    JR   OW_STR                    ; next.

;@ROUTINE IN DE,HL OUT DE CLOBBERS A,BC,HL,CARRY,ZERO,SIGN,PARITY,HALFCARRY
; Write HL in decimal at DE (OW_PUTC), without leading zeros.

OW_DEC:                        ; HL is the value.
    LD   C,0                       ; Digits so far.
.DIV:                          ; HL over ten:
    XOR  A                         ; the remainder in A,
    LD   B,16                      ; a bit
.BIT:                          ; at a time,
    ADD  HL,HL                     ; from
    RLA                            ; the top;
    CP   10                        ; the quotient's
    JR   C,.LOW                    ; bit
    SUB  10                        ; is one
    INC  L                         ; when ten fits.
.LOW:                          ; Then the next bit.
    DJNZ .BIT                      ; HL is the quotient.
    PUSH AF                        ; The digit, kept,
    INC  C                         ; counted,
    LD   A,H                       ; until
    OR   L                         ; none
    JR   NZ,.DIV                   ; is left.
.DIGIT:                        ; The digits, from the first:
    POP  AF                        ; each
    ADD  A,'0'                     ; in ASCII,
    CALL OW_PUTC                   ; written,
    DEC  C                         ; until
    JR   NZ,.DIGIT                 ; all are.
    RET                            ; Done.

; ------------------------------------------------------- record declarations

;@ROUTINE OUT A,CARRY,ZERO CLOBBERS SIGN,PARITY,HALFCARRY,BC,DE,HL
; BeginRecord: keep the record's name, check that the type and record
; tables have room (DG_META), and start an empty field list.

OW_RBEG:
    CALL EX_DECL                   ; Check and keep the record's name.
    LD   A,(AG_TCNT)               ; Types so far.
    CP   AG_TCAP                   ; Room for another?
    JP   NC,AG_EMETA               ; No: raise DG_META.
    LD   A,(AG_RCNT)               ; Records so far.
    CP   AG_RCAP                   ; Room for another?
    JP   NC,AG_EMETA               ; No: raise DG_META.
    LD   A,(AG_FCNT)               ; The next free field index...
    LD   (AG_CFIDX),A              ; ...is the record's first,
    LD   HL,(SY_TOP)               ; ...its entry the provisional
    LD   (AG_CFADR),HL             ; ...symbol record.
    XOR  A                         ; No fields yet...
    LD   (AG_CWIDE),A              ; ...nor 64K passed,
    LD   (AG_CFCNT),A              ; ...counted...
    LD   H,A                       ; ...and no...
    LD   L,A                       ; ...bytes...
    LD   (AG_CSIZE),HL             ; ...in the record.
    RET                            ; Back to the engine.

;@ROUTINE OUT A,HL CLOBBERS CARRY,ZERO,SIGN,PARITY,HALFCARRY
; A is the index of the record's next field: its fields so far
; (AG_CFCNT) and the earlier records', AG_FCNT, which HL addresses.

OW_FIDX:                       ; The fields in use.
    LD   A,(AG_CFCNT)              ; This record's fields so far,
    LD   HL,AG_FCNT                ; plus those of earlier records,
    ADD  A,(HL)                    ; are the next field's index.
    RET                            ; A is it.

;@ROUTINE CLOBBERS A,BC,DE,HL,CARRY,ZERO,SIGN,PARITY,HALFCARRY
; BeginRecordField: the field indices must have room (DG_META). The name
; goes into the field's entry, the provisional symbol record; OW_PLACE
; checks that it is new.

OW_FIELD:
    CALL OW_FIDX                   ; The new field's index,
    JP   C,AG_EMETA                ; past 255 (DG_META),
    CP   AG_FCAP                   ; or 255 itself?
    JP   NC,AG_EMETA               ; No: raise DG_META.
    CALL AG_FIELD                  ; HL addresses the entry.
    LD   DE,(TK_POS)               ; Its position,
    LD   (AC_SPOS),DE              ; for a repeat (OW_FRESH);
    JP   TK_KEEP                   ; its spelling recorded there; return.

;@ROUTINE CLOBBERS A,BC,DE,HL,CARRY,ZERO,SIGN,PARITY,HALFCARRY
; CommitRecordField: give the field its type (not a view, DG_BOUND, nor
; here a File, DG_NYI; a handle optional, DG_HOPT; then its name new,
; DG_DUP, in the reference's order) and its offset, the record's size so
; far, then grow the record by the field's extent, noting a size past 64K
; for CommitRecord (AG_CWIDE).

OW_PLACE:
    CALL AC_ITEM                   ; The field's type: not a view, nor a File.
    LD   HL,AG_TPOS                ; A handle field
    CALL PL_NEEDO                  ; must be optional, at its type.
    CALL OW_FOWN                   ; An owning field makes its record owning.
    PUSH AF                        ; Keep the type.
    CALL OW_FIDX                   ; The field's index:
    CALL AG_FIELD                  ; its entry,
    CALL OW_FRESH                  ; its name not a repeat.
    POP  AF                        ; The type,
    LD   C,A                       ; kept.
    CALL OW_FIDX                   ; The field's index.
    CALL AG_FIELD                  ; HL addresses its entry.
    INC  HL                        ; Skip the spelling's...
    INC  HL                        ; ...address...
    INC  HL                        ; ...and length.
    LD   (HL),C                    ; The field's type into AG_FTYPE.
    INC  HL                        ; Step to AG_FPOS.
    LD   DE,(AG_CSIZE)             ; The record's size so far...
    LD   (HL),E                    ; ...is the field's offset...
    INC  HL                        ; ...low byte first...
    LD   (HL),D                    ; ...then high.
    LD   A,C                       ; The field's type.
    PUSH DE                        ; Keep its offset.
    CALL AG_SIZE                   ; HL is its extent.
    POP  DE                        ; Recover the offset.
    ADD  HL,DE                     ; The record's new size,
    JR   NC,.SIZED                 ; past 64K
    LD   A,1                       ; noted for
    LD   (AG_CWIDE),A              ; CommitRecord.
.SIZED:                        ; The size so far:
    LD   (AG_CSIZE),HL             ; commit it.
    LD   HL,AG_CFCNT               ; Count...
    INC  (HL)                      ; ...the field,
    JP   SY_SKIP                   ; ...its record kept; return.

;@ROUTINE CLOBBERS A,BC,DE,HL,CARRY,ZERO,SIGN,PARITY,HALFCARRY
; CommitRecord: a record needs a field (DG_EMPTY), and is at most 64K
; (out-of-range at its name, as the reference checks it). Append its descriptor
; as a new type (records are never shared), fill its record entry and
; declare its name as a record type whose payload is the type ID.

OW_RECOK:
    LD   A,(AG_CFCNT)              ; Any fields?
    OR   A                         ; Zero means none.
    JP   Z,OW_EVOID                ; Raise DG_EMPTY.
    LD   A,(AG_CWIDE)              ; Past 64K
    OR   A                         ; is out-of-range
    LD   A,DG_RANGE                ; at the
    LD   HL,AC_DPOS                ; record's
    JP   NZ,DG_AT                  ; name.
    LD   A,(AG_RCNT)               ; The record's ordinal
    LD   H,A                       ; is the auxiliary byte, AG_NAUX,
    LD   L,AG_KREC                 ; after the kind, a record's,
    LD   (AG_NKIND),HL             ; in the candidate.
    LD   HL,0                      ; A record has no length word.
    LD   (AG_NDIM),HL              ; Clear it.
    LD   HL,(AG_CSIZE)             ; The record's size...
    LD   (AG_NSIZE),HL             ; ...is the candidate's extent.
    CALL AG_ADD                    ; A is the new type's ID.
    CALL PL_RMARK                  ; Owning, if a field owns.
    LD   (AG_CTYPE),A              ; Keep it,
    LD   C,A                       ; the name's payload below.
    LD   A,(AG_RCNT)               ; The record's ordinal...
    CALL AG_RENT                   ; HL addresses the record's entry in AG_RTAB.
    LD   DE,(AG_CFIDX)             ; Its first field, then AG_CFCNT, its count,
    LD   (HL),E                    ; into AG_RFIDX
    INC  HL                        ; and
    LD   (HL),D                    ; AG_RFCNT,
    INC  HL                        ; then
    LD   DE,(AG_CFADR)             ; where they
    LD   (HL),E                    ; lie,
    INC  HL                        ; AG_RFADR.
    LD   (HL),D                    ; (High byte.)
    LD   D,SY_RTYPE                ; The name is a record type
    LD   B,0                       ; whose payload, C, is its type ID.
    CALL EX_PREP                   ; Write the provisional symbol.
    CALL SY_CMT                    ; Commit it.
    CALL OW_FIDX                   ; The record's fields join
    LD   (HL),A                    ; the fields in use.
    LD   HL,AG_RCNT                ; Count...
    INC  (HL)                      ; ...the record.
    RET                            ; Back to the engine.


;@ROUTINE OUT A,CARRY,ZERO CLOBBERS SIGN,PARITY,HALFCARRY,BC,DE,HL
; Compare the name of the field entry at HL, made the current NAME, with
; the fields already declared in the record being declared (AG_CFCNT fields
; from index AG_CFIDX). A repeated field name raises DG_DUP, naming it, at
; it, after its type's checks as the reference makes them; otherwise
; return carry clear, the current token's TK_PTR and TK_LEN restored.

OW_FRESH:                      ; HL is the new field's entry.
    LD   DE,(TK_PTR)               ; The current
    PUSH DE                        ; token's
    LD   A,(TK_LEN)                ; spelling,
    PUSH AF                        ; kept.
    CALL WD_GET                    ; Its name's spelling and
    LD   A,(HL)                    ; length
    LD   (TK_PTR),DE               ; are the
    LD   (TK_LEN),A                ; current NAME.
    LD   A,(AG_CFCNT)              ; Fetch this record's field count so far.
    OR   A                         ; The first field cannot repeat.
    JR   Z,.FRESH                  ; Carry clear from the OR.
    LD   B,A                       ; B counts the fields left to compare.
    LD   A,(AG_CFIDX)              ; A is the record's first field index.
.LOOP:                         ; Compare one field per iteration.
    PUSH AF                        ; Keep the field index.
    PUSH BC                        ; Keep the count; TK_SAME needs no BC.
    CALL AG_FIELD                  ; Address this field's entry.
    CALL TK_SAME                   ; Is its name the token's spelling?
    JR   C,.DUP                    ; Yes: report the duplicate.
    POP  BC                        ; Restore the count.
    POP  AF                        ; Restore the field index.
    INC  A                         ; Step to the next field.
    DJNZ .LOOP                     ; Continue through the record's fields.
.FRESH:                        ; No repeat:
    POP  AF                        ; the current
    LD   (TK_LEN),A                ; token's
    POP  DE                        ; spelling
    LD   (TK_PTR),DE               ; again,
    OR   A                         ; with carry clear.
    RET                            ; Return to the field action.
.DUP:                          ; The name repeats a field's.
    LD   HL,TK_PTR                 ; It
    LD   A,DG_DUP                  ; is named
    CALL DG_SETN                   ; by duplicate-name,
    JP   DG_KEPT                   ; at it (OW_FIELD); no return.

; A further failure exit. It does not return.

OW_EVOID:                      ; A record type with no fields.
    CALL DG_RAISE                  ; Report it.
    DB   DG_EMPTY                  ; Diagnostic: empty record.

;@ROUTINE IN A OUT A CLOBBERS DE,HL,CARRY,ZERO,SIGN,PARITY,HALFCARRY
; A field of type A is committed: if it owns, its record will (PL_ROWN).

OW_FOWN:                       ; A is the field's type.
    PUSH AF                        ; Kept.
    CALL PL_OWNS                   ; Owning?
    JR   NC,.KEPT                  ; No.
    LD   A,1                       ; Its record
    LD   (PL_ROWN),A               ; owns.
.KEPT:                         ; Done.
    POP  AF                        ; The type.
    RET                            ; Back.

OW_IDS: DB  "id ",0            ; An identifier's prefix.
OW_STRS: DB  "string",0        ; A bounded string's name.
OW_SUFX: DB  ".owners",0       ; An owner descriptor's name suffix.
