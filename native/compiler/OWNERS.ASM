;==========================================================================
;  Pool declarations and owner descriptors
;==========================================================================
;
;  Overlay OWNERS, loaded above NAMES when a pool is declared (OV_PCALL,
;  OVERLAY.ASM), so that it and FLOAT share the area's top: each is loaded
;  again when it is next needed, FLOAT keeping its workspace resident. It
;  holds the actions a pool's declaration takes, which a program meets
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
;  for its blobs' writing (BL_ENDO), which loads OWNERS again after.
;
;  Entries, a jump table at the overlay's start (OW_TAB):
;    OW_FWD    ForwardPool: `forward pool NAME`
;    OW_REC    the PoolRecord island: the record after `as`
;    OW_CMT    CommitPool: declare or complete the pool, write its blobs
;    OW_ENDP   a part's or the program's end: forward pools completed
;    OW_SEL, OW_ARM, OW_ELSE, OW_TAKEN  a handle select's actions
;              (HSELECT.ASM's stubs), which load no other overlay
;    OW_LEASA  a lease passed to a record parameter
;    OW_IDREC  id(...) of a record (a lease or a var record parameter)

; Entries, a jump each at the overlay's start (OV_PCALL, OVERLAY.ASM).

OW_TAB:                        ; Entry 0:
    JP   OW_FWD                    ; ForwardPool;
    JP   OW_REC                    ; 3: PoolRecord;
    JP   OW_CMT                    ; 6: CommitPool;
    JP   OW_ENDP                   ; 9: a part's or the program's end;
    JP   OW_SEL                    ; 12: a handle select's subject;
    JP   OW_ARM                    ; 15: its arm's some or none;
    JP   OW_ELSE                   ; 18: its case else;
    JP   OW_TAKEN                  ; 21: a some arm's binding;
    JP   OW_LEASA                  ; 24: a lease passed;
    JP   OW_IDREC                  ; 27: id(...) of a record.

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
    CALL BL_ENDO                   ; Written.
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
    CALL BL_BYTE                   ; then
    LD   A,H                       ; its high
    JP   BL_BYTE                   ; byte; return.

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
    CALL BL_ENDO                   ; Written.
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
    CALL BL_BYTE                   ; first;
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

;@ROUTINE IN A OUT HL,B CLOBBERS A,C,DE,CARRY,ZERO,SIGN,PARITY,HALFCARRY
; The name of table type A, a record's: the symbol of class SY_RTYPE whose
; payload is A. HL returns its spelling and B its length.

OW_TNAME:                      ; A is the type.
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

OW_SUFX: DB  ".owners",0       ; An owner descriptor's name suffix.

; ------------------------------------------------------- handle selects

;@ROUTINE IN A OUT A CLOBBERS BC,DE,HL,IX,IY,CARRY,ZERO,SIGN,PARITY,HALFCARRY
; SelectSubject's handle, of type AC_BOUND, the path in hand (selectHandle): its
; pool complete (pool-incomplete) and, owning, optional (type-mismatch),
; each at the subject; `select move` waits (DG_NYI). The handle, two bytes
; or an identifier's four, is loaded into a frame slot of its own, which
; the arms test, and the select's frame opens (AC_SOPEN) with mode bit 3
; set, and bit 6 when the subject is the routine's own owning local,
; whose `some` arm binds a lease.

OW_SEL:                        ; AC_BOUND is the handle's type.
    LD   A,(AC_BOUND)              ; The type:
    CALL HN_REC                    ; the pool's record:
    LD   A,DG_PINC                 ; pool-incomplete
    JR   Z,.FAULT                  ; without one.
    LD   A,(AC_MODE)               ; `select move`
    OR   A                         ; has its own
    JR   Z,.MOVE                   ; checks.
    LD   A,(AC_BOUND)              ; An owning
    AND  3                         ; handle that is
    LD   A,DG_CLASH                ; not optional
    JR   NZ,.OWNER                 ; is type-mismatch.
.FAULT:                        ; A is the diagnostic,
    LD   HL,(EX_START)             ; at the
    JP   DG_HERE                   ; subject.
.OWNER:                        ; The subject's kind:
    LD   HL,(EX_START)             ; used,
    LD   (FW_PLACE),HL             ; at its name:
    LD   A,(AC_BOUND)              ; an owner
    BIT  1,A                       ; directly
    CALL Z,FW_SEEN               ; (noteDirect),
    CALL FW_USE                    ; then checkUsable.
    LD   C,8                       ; A handle select,
    LD   A,(RO_PKIND)              ; a lease for a local or
    CP   GA_FRAME                  ; parameter in the frame (not
    JR   NZ,.LOAD                  ; a slot-holder's location),
    CALL FW_ALONE                  ; for the root alone,
    JR   NZ,.LOAD                  ; and
    CALL FW_ROOT                   ; the routine's own owning local
    JR   NC,.LOAD                  ; (a tracked owner):
    LD   C,8+64                    ; bit 6.
.LOAD:                         ; C is the mode.
    PUSH BC                        ; Kept.
    CALL HN_WIDE                   ; A word or a long:
    LD   (RO_OTYPE),A              ; the handle
    PUSH AF                        ; (the type kept)
    CALL GA_LOAD                   ; loaded.
.SLOT:                         ; The handle is in the registers.
    POP  AF                        ; Its
    PUSH AF                        ; size
    CALL GX_PROP                   ; in
    AND  7                         ; a slot
    CALL EM_ALLOC                  ; of its own,
    LD   (AC_INDEX),HL             ; for the frame,
    POP  AF                        ; which
    CALL GX_FPUT                   ; takes it.
    CALL HN_SIDX                   ; The subject's symbol,
    PUSH AF                        ; kept
    CALL AC_SOPEN                  ; as the select's frame opens.
    CALL CT_FLAGS                  ; Its mode
    POP  DE                        ; (D the subject)
    POP  BC                        ; takes
    LD   A,C                       ; the
    OR   (HL)                      ; subject's
    LD   (HL),A                    ; kind;
    LD   BC,17-CT_FMODE            ; its byte 17
    ADD  HL,BC                     ; the subject's
    LD   (HL),D                    ; index.
    RET                            ; Back to the engine.
.MOVE:                         ; `select move`: an optional owner,
    LD   A,(AC_BOUND)              ; writable,
    AND  3                         ; or syntax
    DEC  A                         ; at `select`.
    LD   HL,RO_PRO                 ; (AG_HOPT
    OR   (HL)                      ; alone
    LD   A,DG_STMT                 ; and not
    LD   HL,AC_DELTA+2             ; read-only)
    JP   NZ,DG_AT                  ; No return.
    LD   HL,(EX_START)             ; Moved,
    LD   (FW_PLACE),HL             ; at its name,
    CALL FW_MOVE                   ; in this statement;
    CALL HN_EMOV                   ; moved out, in HL.
    LD   C,8+16                    ; A handle select, bit 4 move;
    PUSH BC                        ; kept;
    LD   A,SY_U16                  ; the slot
    PUSH AF                        ; a word.
    JR   .SLOT                     ; Kept there.


;@ROUTINE OUT A CLOBBERS BC,DE,HL,IX,IY,CARRY,ZERO,SIGN,PARITY,HALFCARRY
; CaseLabels of a handle select: `some(NAME)`, at most once, or `none`,
; at most once with case else (syntax at `case`, AC_SPOS); the subject
; tested, JP Z to the next arm for some, JP NZ for none. Mode bit 2 is
; some seen, bit 1 none or else, bit 7 that this arm is some.

OW_ARM:                        ; After `case`.
    CALL PR_PEEK                   ; some
    CP   TK_SOME                   ; or
    JR   Z,.SOME                   ; none?
    CP   TK_NONE                   ; Anything else:
    LD   A,DG_TOKEN+TK_ELSE        ; `else`
    JP   NZ,DG_ISSUE               ; expected.
    CALL PR_TAKE                   ; `none`:
    LD   C,2                       ; bit 1,
    CALL OW_ONCE                   ; once,
    RES  7,(HL)                    ; not some;
    LD   C,$C2                     ; JP NZ
    JR   OW_TEST                   ; on; return.
.SOME:                         ; `some`:
    CALL PR_TAKE                   ; taken,
    LD   C,4                       ; bit 2,
    CALL OW_ONCE                   ; once,
    SET  7,(HL)                    ; some.
    CALL PR_LEFT                   ; `(`,
    LD   E,TK_NAME                 ; the name
    CALL PR_NEED                   ; to bind,
    CALL EX_DECL                   ; retained,
    CALL PR_RIGHT                  ; `)`.
    LD   C,$CA                     ; JP Z on.

;@ROUTINE IN C CLOBBERS A,BC,DE,HL,CARRY,ZERO,SIGN,PARITY,HALFCARRY
; Test the select's handle in its slot, LD A,H, OR L for an owner, CALL
; ID_TEST for an identifier, and append the jump C to the next arm.

OW_TEST:                       ; C is JP Z or JP NZ.
    PUSH BC                        ; Kept.
    LD   B,CT_FVAR                 ; The slot,
    CALL CT_FWORD                  ; HL:
    LD   B,CT_FBND                 ; the type
    PUSH HL                        ; (the slot kept)
    CALL CT_FBYTE                  ; of the handle,
    LD   (AC_BOUND),A              ; staged,
    CALL HN_WIDE                   ; its width:
    POP  HL                        ; loaded
    PUSH AF                        ; (kept)
    CALL GX_FLOAD                  ; from the slot.
    POP  AF                        ; An owner
    CP   SY_U16                    ; is tested
    JR   NZ,.ID                    ; LD A,H, OR L,
    CALL EM_SEQ                    ; an identifier
    DB   2,$7C,$B5                 ; by
    JR   .JUMP                     ; the runtime:
.ID:                           ; CALL
    CALL EM_HELP                   ; ID_TEST.
    DW   HP_IDTST                  ; Then
.JUMP:                         ; the jump
    POP  BC                        ; C
    LD   B,CT_FCONT                ; to the next
    JP   CT_GO                     ; arm; return.

;@ROUTINE IN C OUT HL CLOBBERS A,B,DE,CARRY,ZERO,SIGN,PARITY,HALFCARRY
; Mode bit C of the select is set once: a second some, or a second none
; or case else, is syntax at `case` (AC_SPOS). HL returns the mode's
; address.

OW_ONCE:                       ; C is the bit.
    CALL CT_FLAGS                  ; The mode:
    LD   A,(HL)                    ; the bit
    AND  C                         ; already
    LD   A,DG_STMT                 ; set
    JR   NZ,.TWICE                 ; is syntax;
    LD   A,(HL)                    ; else
    OR   C                         ; it is
    LD   (HL),A                    ; set.
    RET                            ; HL is the mode.
.TWICE:                        ; At `case`:
    LD   HL,AC_SPOS                ; syntax.
    JP   DG_AT                     ; No return.

;@ROUTINE OUT A CLOBBERS BC,DE,HL,IX,IY,CARRY,ZERO,SIGN,PARITY,HALFCARRY
; CaseElse of a handle select: once, with none (syntax at `case`), the
; subject tested, JP NZ to the next arm; the arm is reachable.

OW_ELSE:                       ; After `case else`.
    LD   C,2                       ; Bit 1,
    CALL OW_ONCE                   ; once,
    RES  7,(HL)                    ; not some.
    LD   C,$C2                     ; JP NZ
    CALL OW_TEST                   ; on.
    JP   AC_LIVE                   ; Reachable; return.

;@ROUTINE OUT A CLOBBERS BC,DE,HL,CARRY,ZERO,SIGN,PARITY,HALFCARRY
; CaseBody of a handle select: a some arm binds its name, retained
; (EX_DECL), at the start of its block: to the routine's own owning local
; (mode bit 6), a lease, an alias through the subject's slot (SY_LEASE),
; of the pool's record; otherwise an identifier, non-optional, in four
; bytes of its own, LD the slot, CALL ID_MAKE for an owner, then stored.
; The arm is reachable.

OW_TAKEN:                      ; The arm's body begins.
    CALL CT_MODE                   ; The select's mode:
    BIT  7,A                       ; a some arm?
    JP   Z,AC_LIVE                 ; No: nothing to bind.
    BIT  4,A                       ; A move's
    JR   NZ,.MOVED                 ; binds an owner.
    PUSH AF                        ; The mode, kept.
    LD   B,CT_FBND                 ; The handle's
    CALL CT_FBYTE                  ; type,
    LD   (AC_BOUND),A              ; staged.
    LD   B,CT_FVAR                 ; The
    CALL CT_FWORD                  ; slot,
    POP  AF                        ; HL. The mode:
    BIT  6,A                       ; a lease?
    JR   Z,.ID                     ; No: an identifier.
    LD   B,H                       ; The slot is
    LD   C,L                       ; the payload,
    CALL EX_RENEW                  ; the name
    LD   D,SY_AGGR+SY_PARAM+SY_PVAR+SY_LEASE ; a writable lease,
    CALL EX_PREP                   ; declared;
    LD   A,(AC_BOUND)              ; its type
    CALL HN_REC                    ; the record.
    JR   .TAG                      ; Committed.
.ID:                           ; HL is the slot.
    PUSH HL                        ; Kept.
    LD   A,4                       ; Four bytes
    CALL EM_ALLOC                  ; of its own,
    EX   (SP),HL                   ; kept; the slot:
    CALL HN_WIDE                   ; the handle
    PUSH AF                        ; (its width)
    CALL GX_FLOAD                  ; loaded;
    POP  AF                        ; an owner's
    CP   SY_U16                    ; identifier
    JR   NZ,.STORE                 ; is made,
    CALL EM_HELP                   ; CALL
    DW   HP_IDMK                   ; ID_MAKE;
.STORE:                        ; DEHL is the identifier,
    POP  HL                        ; stored
    PUSH HL                        ; (the place kept)
    LD   A,SY_U32                  ; in its
    CALL GX_FPUT                   ; four bytes.
    POP  BC                        ; Its offset,
    CALL EX_RENEW                  ; the name's
    LD   D,SY_AGGR+SY_LOCAL        ; payload,
    CALL EX_PREP                   ; declared;
    LD   A,(AC_BOUND)              ; its type
    AND  $FE                       ; an identifier,
    OR   AG_HID                    ; not optional.
.TAG:                          ; A is the type.
    CALL SY_TAG                    ; Committed.
    JP   AC_LIVE                   ; Reachable; return.
.MOVED:                        ; `select move`'s some arm:
    LD   B,CT_FBND                 ; the
    CALL CT_FBYTE                  ; type,
    LD   (AC_BOUND),A              ; staged.
    LD   A,2                       ; Two bytes
    CALL EM_ALLOC                  ; of its own,
    PUSH HL                        ; kept;
    LD   B,CT_FVAR                 ; the
    CALL CT_FWORD                  ; slot's
    LD   A,SY_U16                  ; handle
    CALL GX_FLOAD                  ; loaded,
    CALL EM_HELP                   ; CALL LINK0,
    DW   HP_LINK0                  ; then
    POP  HL                        ; stored
    PUSH HL                        ; there
    LD   A,SY_U16                  ; (LD (IX+d),L,
    CALL GX_FPUT                   ; LD (IX+d+1),H).
    POP  BC                        ; Its offset,
    CALL EX_RENEW                  ; the name's
    LD   D,SY_AGGR+SY_LOCAL        ; payload,
    CALL EX_PREP                   ; declared,
    LD   A,FW_VALUE                ; a value,
    CALL HN_STAT                   ; an owner
    LD   A,(AC_BOUND)              ; not
    AND  $FE                       ; optional.
    JR   .TAG                      ; Committed.

;@ROUTINE OUT HL CLOBBERS A,BC,DE,CARRY,ZERO,SIGN,PARITY,HALFCARRY
; An argument for record parameter AC_BOUND (AG_VAR for var) whose path,
; in hand, is handle type RO_OTYPE, a local's or parameter's usable
; (checkUsable): a lease (7.14), an owner neither optional nor an
; identifier of a pool of that record (type-mismatch otherwise), a local
; or parameter (a call's result or an element waits, DG_NYI), the
; routine's own owning local or parameter alone (lease otherwise), each
; at the argument; used directly (noteDirect); its value in HL, and for a
; var parameter PUSH HL first, the owner word being the record itself.

OW_LEASA:                      ; The path is parsed:
    LD   A,(RO_PKIND)              ; a local's or
    CP   GA_FRAME                  ; parameter's
    CALL Z,FW_USE                  ; usable (checkUsable);
    LD   A,(AC_BOUND)              ; the parameter's
    LD   B,A                       ; type, B;
    LD   A,(RO_OTYPE)              ; the path's,
    LD   C,A                       ; C:
    AND  3                         ; An owner, not optional
    JP   NZ,EX_EFIT                ; (type-mismatch otherwise),
    LD   A,C                       ; of a pool
    PUSH BC                        ; whose
    CALL HN_REC                    ; record
    POP  BC                        ; is the
    LD   C,A                       ; parameter's
    LD   A,B                       ; type
    AND  $7F                       ; (type-mismatch
    CP   C                         ; otherwise),
    JP   NZ,EX_EFIT                ; at the argument;
    LD   A,(RO_PKIND)              ; a local or parameter
    CP   GA_FRAME                  ; (a call's result or an
    JP   NZ,TR_OPER                ; element waits),
    PUSH BC                        ; (kept)
    CALL FW_ALONE                  ; the root alone
    JR   NZ,.LEASE                 ; (lease otherwise);
    CALL FW_SEEN                   ; used directly (noteDirect);
    LD   HL,(RO_PBASE)             ; its value,
    LD   A,SY_U16                  ; LD L,(IX+d),
    CALL GX_FLOAD                  ; LD H,(IX+d+1).
    POP  BC                        ; A var parameter
    BIT  7,B                       ; takes it
    RET  Z                         ; as its owner word too:
    LD   A,$E5                     ; PUSH HL,
    JP   GX_PUSHA                  ; two bytes pushed; return.
.LEASE:                        ; Not the routine's own:
    LD   A,DG_LEASE                ; lease, at
    JP   EX_EVAL                   ; the argument.

;@ROUTINE OUT A CLOBBERS BC,DE,HL,CARRY,ZERO,SIGN,PARITY,HALFCARRY
; `id(PATH)` of a record, the path in hand and `id` at AC_BOUND
; (idExpression): a record alone, a lease or a var record parameter (an
; owner word), else not-owner at `id`; of one pool (two or none wait,
; DG_NYI). Its identifier when the owner word is its address and the
; slot before it is the pool's, else none: LD HL,owner, LD DE,alias, OR
; A, SBC HL,DE, JP NZ,none, EX DE,HL, PUSH HL, DEC HL, LD D,(HL), DEC
; HL, LD E,(HL), LD HL,info, OR A, SBC HL,DE, POP HL, JP NZ,none, CALL
; ID_MAKE, JP done; none: LD HL,0, LD DE,0; done:. A returns its type,
; an optional identifier of that pool.

OW_IDREC:                      ; The path is parsed.
    LD   A,(RO_OTYPE)              ; A record's
    CALL AG_DESC                   ; descriptor
    LD   A,(HL)                    ; (its
    CP   AG_KREC                   ; kind),
    JP   NZ,.OWNER                 ; alone,
    CALL FW_ALONE                  ; with
    JP   NZ,.OWNER                 ; an owner
    LD   HL,(RO_POWN)              ; word (a lease
    LD   A,H                       ; or a var
    OR   L                         ; record
    JP   Z,.OWNER                  ; parameter):
    LD   HL,PL_CNT                 ; its pool,
    LD   B,(HL)                    ; from the last
    LD   C,$FF                     ; declared, none yet:
.EACH:                         ; B pools are left.
    LD   A,B                       ; The
    SUB  1                         ; next
    JR   C,.DONE                   ; (none left),
    LD   B,A                       ; B,
    CALL PL_AT                     ; its
    INC  HL                        ; record
    INC  HL                        ; (PL_EREC):
    LD   A,(RO_OTYPE)              ; this
    CP   (HL)                      ; one?
    JR   NZ,.EACH                  ; No.
    INC  C                         ; A second
    JP   NZ,TR_OPER                ; waits;
    LD   C,B                       ; the first is kept.
    JR   .EACH                     ; On.
.DONE:                         ; C is the pool, $FF none.
    LD   A,C                       ; None
    INC  A                         ; waits
    JP   Z,TR_OPER                 ; too.
    LD   A,C                       ; The pool's
    PUSH AF                        ; index kept,
    CALL PL_AT                     ; and its
    LD   E,(HL)                    ; information's
    INC  HL                        ; ordinal
    LD   D,(HL)                    ; (PL_EORD)
    PUSH DE                        ; too.
    LD   HL,(RO_POWN)              ; LD L,(IX+owner),
    LD   A,SY_U16                  ; LD H,(IX+owner+1);
    CALL GX_FLOAD                  ; then
    LD   HL,(RO_PBASE)             ; LD E,(IX+alias),
    LD   DE,GX_DLDDE               ; LD D,(IX+alias+1);
    CALL GX_FACC                   ; OR A,
    CALL EM_SEQ                    ; SBC HL,DE,
    DB   3,$B7,$ED,$52             ; then
    LD   C,$C2                     ; JP NZ,none,
    CALL EM_FWD                    ; its label
    PUSH AF                        ; kept;
    CALL EM_OP                     ; EX DE,HL,
    DB   $EB                       ; then
    CALL GX_PUSHW                  ; PUSH HL, counted;
    CALL EM_SEQ                    ; DEC HL, LD D,(HL),
    DB   4,$2B,$56,$2B,$5E         ; DEC HL, LD E,(HL);
    CALL EM_OP                     ; LD HL,
    DB   $21                       ; the
    POP  BC                        ; pool's
    POP  HL                        ; information
    PUSH BC                        ; (the label
    LD   DE,0                      ; kept);
    CALL EM_REF                    ; OR A,
    CALL EM_SEQ                    ; SBC HL,DE,
    DB   3,$B7,$ED,$52             ; then
    LD   A,SY_U16                  ; POP HL,
    CALL GX_POPV                   ; popped;
    POP  AF                        ; JP NZ
    PUSH AF                        ; to
    LD   C,$C2                     ; none
    CALL EM_JUMP                   ; again;
    CALL EM_HELP                   ; CALL
    DW   HP_IDMK                   ; ID_MAKE;
    LD   C,$C3                     ; JP
    CALL EM_FWD                    ; done.
    POP  BC                        ; none's label,
    PUSH AF                        ; done's kept:
    LD   A,B                       ; none:
    CALL EM_LDONE                  ; LD HL,0,
    CALL EM_SEQ                    ; LD DE,0;
    DB   6,$21,0,0,$11,0,0         ; then
    POP  AF                        ; done:
    CALL EM_LDONE                  ; here.
    POP  AF                        ; The pool's
    ADD  A,A                       ; optional
    ADD  A,A                       ; identifier's
    ADD  A,AG_HND+AG_HID+AG_HOPT   ; type.
    RET                            ; DEHL holds it.
.OWNER:                        ; Not an owner's:
    LD   HL,(AC_BOUND)             ; not-owner,
    LD   A,DG_OWNER                ; at
    JP   DG_HERE                   ; `id`.
