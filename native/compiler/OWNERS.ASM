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
;  for its blobs' writing (BL_END), which is resident.
;
;  Entries, a jump table at the overlay's start (OW_TAB):
;    OW_FWD    ForwardPool: `forward pool NAME`
;    OW_REC    the PoolRecord island: the record after `as`
;    OW_CMT    CommitPool: declare or complete the pool, write its blobs
;    OW_ENDP   a part's or the program's end: forward pools completed
;  A routine's body's actions for handles, once here, are resident
;  (OWNBODY.ASM).

; Entries, a jump each at the overlay's start (OV_PCALL, OVERLAY.ASM).

OW_TAB:                        ; Entry 0:
    JP   OW_FWD                    ; ForwardPool;
    JP   OW_REC                    ; 3: PoolRecord;
    JP   OW_CMT                    ; 6: CommitPool;
    JP   OW_ENDP                   ; 9: a part's or the program's end.

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
