;==========================================================================
;  Walking the directories, and Phase C: placement
;==========================================================================
;
;  Phases C and D (linker §6, §7) place the live blobs, then write the
;  image. Neither phase sorts. Each pass re-reads the directories (linker
;  §10) and takes, in directory order, the live blobs of one section and
;  alignment class: library before program, classes from the largest down.
;  That is the reference linker's order. Phase D (PHASED.ASM) makes the
;  same passes, copying each blob from its byte stream and patching its
;  references as they come, and Phase E makes them again for the map.
;
;  With option R, data blobs leave TEXT for a separate DATA section after
;  it, followed by COPY, DATA written again byte for byte (linker §7.3).
;  ROM targets (class 3 and above) are refused in Phase A.
;
;  Principal entries:
;    WK_PASS   make the passes of a section, calling a routine per blob
;    WK_BOTH   walk the library's directory, then the program's
;    WK_MATCH  whether the blob just read belongs to the pass
;    REF_READ  read one reference (REF_SKIP the rest of a blob's, REF_NEW
;              before a blob's first)
;    PC_RUN    Phase C: place the sections, the aliases and the
;              pseudo-objects, and check the fit
;
;  Layout: START, then TEXT, then DATA and COPY (empty without option R),
;  which end the image at IMG_END; then BSS and the file table, after which
;  PC_FREE is the first free address. PS_TAB holds the pseudo-objects'
;  rows, four bytes each (address, size), from MAIN ($FFE0) to FILECOUNT.

PF_BLOCK EQU  LIB_HEAD+42      ; The profile block's fields (object format §5).
PF_CLASS EQU  PF_BLOCK+0       ; Byte: the target class; 3 and up are ROM.
PF_KINDS EQU  PF_BLOCK+1       ; Byte: the output kinds allowed, as OUT_KIND bits.
PF_BASE EQU  PF_BLOCK+2        ; Word: the image's base address.
PF_LIMIT EQU  PF_BLOCK+4       ; Word: the image limit, the CCP's base.
PF_TOP EQU  PF_BLOCK+6         ; Word: the nominal top of memory.
PF_OPTS EQU  PF_BLOCK+16       ; Byte: the options the profile supports.
PF_FILE EQU  PF_BLOCK+20       ; Word: the bytes of one file-table entry.

S_TEXT EQU  2                  ; Section TEXT, for WK_SEC: code, rodata and data.
S_BSS EQU  3                   ; Section BSS: kinds 3 and 4 are their own sections.
S_START EQU  4                 ; Section START: the startup blob.
S_DATA EQU  S_TEXT+OF_R        ; Section DATA: TEXT with OF_R's bit, data under R.

PC_NEXT:                       ; Phase C's cursor: the next free address.
    DW   0                         ; It starts at the profile's base.
WK_SEC:                        ; The pass's section.
    DB   0                         ; An S_ value.
WK_CLASS:                      ; And alignment class.
    DB   0                         ; 7 down to 0.
IMG_END:                       ; The image's end: DATA's end plus COPY.
    DW   0                         ; Set by Phase C.
PC_BEG:                        ; Phase C: the section's start.
    DW   0                         ; Its first blob's address.
PC_BEGUN:                      ; Nonzero once its first blob is placed.
    DB   0                         ; Cleared for each section.
DATA_BEG:                      ; DATA's start: TEXT's end without option R.
    DW   0                         ; Set by Phase C.
DATA_END:                      ; DATA's end, where COPY starts.
    DW   0                         ; Set by Phase C.
BSS_BEG:                       ; BSS's start.
    DW   0                         ; Set by Phase C.
PD_DELTA:                      ; Phase D: COPY's distance from DATA.
    DW   0                         ; Zero until the COPY pass.
PC_FREE:                       ; FREE: the first address after the file table.
    DW   0                         ; Set by Phase C.
PC_STACK:                      ; The stack reserve: the compiler's, or STACK=.
    DW   0                         ; The larger of the two.
FT_ADDR:                       ; The file table's address, after BSS.
    DW   0                         ; Set by Phase C even when it is empty.
FT_SIZE:                       ; The file table's bytes.
    DW   0                         ; 0 when the program uses no files.
FT_COUNT:                      ; The file table's entries: F=, or 4.
    DB   0                         ; Set by Phase C.
OUT_POS:                       ; Phase D: the address written up to.
    DW   0                         ; Padding fills the gap to each blob.
WK_OWN:                        ; The directory being walked: 0 library, 1 program.
    DB   0                         ; Set by each walk.
WK_EACH:                       ; The routine called for each blob.
    DW   0                         ; Set by WK_PASS.
WK_KIND:                       ; The blob's kind.
    DB   0                         ; A K_ value.
WK_NAMES:                      ; Nonzero: walks reset the name readers.
    DB   0                         ; Set by Phase E.
WK_POS:                        ; The blob's byte-stream offset.
    DW   0                         ; Bss blobs take no bytes.
WK_ENTRY:                      ; The blob's entry.
    DW   0                         ; From the table.
SRC_FD:                        ; Phase D: the byte stream being copied.
    DW   0                         ; SRC_LIB or SRC_PROG.
.BASE:                         ; Unused.
    DS   3                         ; Three spare bytes.
PS_TAB:                        ; MAIN to FILECOUNT: address, size.
    DS   40                        ; Ten rows of four bytes.

; ---- walking a directory ---------------------------------------------------

;@ROUTINE CLOBBERS A,BC,DE,HL,IX,CARRY,ZERO,SIGN,PARITY,HALFCARRY
; Walk the library's directory, then the program's, calling WK_EACH for
; each blob.

WK_BOTH:                       ; WK_EACH is set.
    XOR  A                         ; The library first,
    CALL .WALK                     ; walked;
    LD   A,1                       ; then the program; fall into .WALK.

;@ROUTINE IN A CLOBBERS A,BC,DE,HL,IX,CARRY,ZERO,SIGN,PARITY,HALFCARRY
; Walk the library's directory (A = 0) or the program's (A = 1), calling
; WK_EACH for each blob with WK_ENTRY, WK_KIND, RD_SIZE, REF_CNT and WK_POS
; set and the directory at its first reference. The callback consumes the
; references, with REF_SKIP or by copying the blob. In Phase E (WK_NAMES)
; the owner's name reader starts again with each walk.

.WALK:                         ; A is the owner.
    LD   (WK_OWN),A                ; Keep it for the callbacks.
    LD   HL,WK_NAMES               ; Are names being read?
    INC  (HL)                      ; Test the flag
    DEC  (HL)                      ; for zero, keeping A.
    CALL NZ,NM_RESET               ; Phase E: restart the owner's name reader.
    LD   A,(WK_OWN)                ; Which directory?
    OR   A                         ; 0 is the library.
    JR   NZ,.PROG                  ; The program's.
    LD   IX,LIB_FD                 ; The library's directory,
    LD   A,(LIB_HEAD+14)           ; at the offset
    LD   HL,(LIB_HEAD+12)          ; its header gives.
    CALL FIL_SEEK                  ; Go there.
    JP   C,DG_SHORT                ; The file is too short.
    LD   HL,0                      ; The implicit first ordinal: $0001 - 1.
    JR   .GO                       ; Read its records.
.PROG:                         ; The program's directory.
    LD   IX,DIR_FD                 ; NAME.$DR, still open.
    XOR  A                         ; Its records follow
    LD   HL,20                     ; past the program header.
    CALL FIL_SEEK                  ; Go there.
    JP   C,DG_SHORT                ; The file is too short.
    LD   HL,(DIR_HEAD+16)          ; The ordinal base,
    DEC  HL                        ; less one.
.GO:                           ; HL is the implicit ordinal before the first.
    LD   (RD_PREV),HL              ; The next implicit ordinal is one more.
    LD   HL,0                      ; The first blob's bytes
    LD   (WK_POS),HL               ; start the stream.
.REC:                          ; IX is at a record's header byte.
    CALL RD_BYTE                   ; A is the header byte.
    CP   $FF                       ; The trailer?
    RET  Z                         ; The walk is done.
    LD   (RD_HEAD),A               ; Keep the header.
    AND  7                         ; The kind.
    CP   6                         ; A control record?
    JR   Z,.CTRL                   ; Skip it.
    LD   (WK_KIND),A               ; The blob's kind.
    LD   A,(RD_HEAD)               ; Bit 3: an explicit ordinal.
    BIT  3,A                       ; Explicit?
    JR   Z,.IMPL                   ; Implicit.
    CALL RD_WORD                   ; HL is the explicit ordinal.
    JR   .ORD                      ; Use it.
.IMPL:                         ; The ordinal after the last.
    LD   HL,(RD_PREV)              ; The last,
    INC  HL                        ; plus one.
.ORD:                          ; HL is the blob's ordinal.
    LD   (RD_PREV),HL              ; The callbacks name the blob by it.
    CALL TAB_FIND                  ; HL is its entry; Phase A found it.
    LD   (WK_ENTRY),HL             ; Keep it.
    CALL RD_WORD                   ; The blob's size.
    LD   (RD_SIZE),HL              ; Keep it.
    CALL RD_BYTE                   ; The reference count, or 255.
    LD   L,A                       ; HL is the count,
    LD   H,0                       ; zero-extended.
    CP   255                       ; The escape?
    JR   NZ,.CNT                   ; A count below 255.
    CALL RD_WORD                   ; The count as a word.
.CNT:                          ; HL is the reference count.
    LD   (REF_CNT),HL              ; For the callback.
    PUSH IX                        ; The callback may move IX.
    LD   HL,(WK_EACH)              ; The routine for each blob.
    CALL .CALL                     ; Call it.
    POP  IX                        ; IX is the directory again.
    LD   A,(WK_KIND)               ; Bss blobs have no bytes
    CP   K_BSS                     ; in the stream.
    JR   Z,.REC                    ; The next record.
    LD   HL,(WK_POS)               ; The next blob's bytes
    LD   DE,(RD_SIZE)              ; follow this one's
    ADD  HL,DE                     ; in the stream.
    LD   (WK_POS),HL               ; Keep the offset.
    JR   .REC                      ; The next record.
.CALL:                         ; HL is the callback.
    JP   (HL)                      ; Its RET returns from .CALL.
.CTRL:                         ; A control record: skip its body.
    LD   A,(RD_HEAD)               ; The subtype
    RRCA                           ; is in
    RRCA                           ; bits
    RRCA                           ; 3 to 7.
    AND  $1F                       ; Z for an alias.
    LD   B,6                       ; Alias: alias, base, offset.
    JR   Z,.SKIP                   ; Six bytes.
    LD   B,2                       ; Entry: an ordinal.
    DEC  A                         ; Subtype 1?
    JR   Z,.SKIP                   ; Two bytes.
    LD   B,5                       ; Limits (bank never passes Phase A).
.SKIP:                         ; B counts the bytes to skip.
    CALL RD_BYTE                   ; Skip one.
    DJNZ .SKIP                     ; Until all are skipped.
    JR   .REC                      ; The next record.

;@ROUTINE CLOBBERS A,BC,DE,HL,CARRY,ZERO,SIGN,PARITY,HALFCARRY
; Read and discard the current blob's references.

REF_SKIP:                      ; REF_CNT references remain.
    LD   HL,(REF_CNT)              ; HL counts them down.
.NEXT:                         ; HL references remain.
    LD   A,H                       ; Any left?
    OR   L                         ; Zero when done.
    RET  Z                         ; The directory is at the next record.
    PUSH HL                        ; Keep the count.
    CALL REF_READ                  ; Read one.
    POP  HL                        ; Recover the count.
    DEC  HL                        ; One fewer.
    JR   .NEXT                     ; Go on.

;@ROUTINE OUT DE,HL CLOBBERS A,B,CARRY,ZERO,SIGN,PARITY,HALFCARRY
; Read one reference: REF_LAST = its offset, REF_FORM its form, HL its
; target, DE its addend (0 when none). Offsets accumulate from REF_NEW.

REF_READ:                      ; IX is at a reference's control byte.
    CALL RD_BYTE                   ; Control: bit 7 form, bit 6 addend, 0-5 delta.
    LD   B,A                       ; Keep it for its bits.
    AND  $3F                       ; The delta,
    CP   63                        ; or 63 for an absolute offset.
    JR   NZ,.DELTA                 ; A delta.
    CALL RD_WORD                   ; An absolute offset.
    JR   .OFF                      ; Use it.
.DELTA:                        ; A is the delta.
    LD   L,A                       ; HL is the delta,
    LD   H,0                       ; zero-extended.
    LD   A,(REF_ANY)               ; The first reference's delta
    OR   A                         ; is its offset.
    JR   Z,.OFF                    ; The first.
    LD   DE,(REF_LAST)             ; Later ones add
    ADD  HL,DE                     ; to the last offset.
.OFF:                          ; HL is the offset.
    LD   (REF_LAST),HL             ; Keep it.
    LD   A,1                       ; A reference has been read,
    LD   (REF_ANY),A               ; so the next delta adds to it.
    XOR  A                         ; ABS16 unless a form is given.
    BIT  7,B                       ; Bit 7: a form byte follows.
    JR   Z,.FORM                   ; ABS16.
    CALL RD_BYTE                   ; The form byte.
.FORM:                         ; A is the form.
    LD   (REF_FORM),A              ; Keep it.
    CALL RD_WORD                   ; The target.
    PUSH HL                        ; Keep it.
    LD   DE,0                      ; No addend,
    BIT  6,B                       ; unless bit 6
    JR   Z,.NOADD                  ; says one follows.
    CALL RD_WORD                   ; The addend.
    EX   DE,HL                     ; DE is the addend.
.NOADD:                        ; The target is on the stack.
    POP  HL                        ; HL is the target.
    RET                            ; DE is the addend.

;@ROUTINE OUT A CLOBBERS CARRY,ZERO,SIGN,PARITY,HALFCARRY
; Before a blob's references: no previous offset yet.

REF_NEW:                       ; Phase D starts each blob's references here.
    XOR  A                         ; No reference read yet,
    LD   (REF_ANY),A               ; so the first offset is absolute.
    RET                            ; A is 0.

;@ROUTINE OUT ZERO CLOBBERS A,DE,HL,CARRY,SIGN,PARITY,HALFCARRY
; Whether the blob just read belongs to this pass: live, of the pass's
; class, and in its section. Z when it does.

WK_MATCH:                      ; WK_ENTRY and WK_KIND are the blob's.
    LD   HL,(WK_ENTRY)             ; Its entry.
    BIT  5,(HL)                    ; Live?
    JR   Z,.NO                     ; A dead blob is in no pass.
    LD   DE,E_LAYOUT               ; Its alignment class.
    ADD  HL,DE                     ; HL addresses it.
    LD   A,(WK_CLASS)              ; The pass's class.
    CP   (HL)                      ; The same?
    RET  NZ                        ; Another class's pass.
    LD   A,(WK_KIND)               ; The blob's section: code and rodata
    CP   K_DATA                    ; are TEXT; data is TEXT or, under R, DATA.
    JR   NC,.KIND                  ; Data, bss or startup.
    LD   A,S_TEXT                  ; Code and rodata: TEXT, and NZ still.
.KIND:                         ; Z for data; A is the section otherwise.
    JR   NZ,.SEC                   ; Bss and startup are their own sections.
    LD   A,(OP_FLAGS)              ; Data:
    AND  OF_R                      ; TEXT with R's bit,
    OR   S_TEXT                    ; which is DATA under option R.
.SEC:                          ; A is the blob's section.
    LD   HL,WK_SEC                 ; The pass's.
    CP   (HL)                      ; Z if they are the same.
    RET                            ; Z: in the pass.
.NO:                           ; Not live.
    OR   1                         ; NZ.
    RET                            ; Not in the pass.

;@ROUTINE IN A,HL CLOBBERS A,BC,DE,HL,IX,CARRY,ZERO,SIGN,PARITY,HALFCARRY
; Make the passes of section A, calling HL for each blob: for each class
; from 7 down that has a live blob (linker §10), the library's directory
; then the program's. DATA has passes only under option R.

WK_PASS:                       ; A is an S_ value, HL a callback.
    LD   (WK_SEC),A                ; The pass's section.
    LD   (WK_EACH),HL              ; The routine for each blob.
    CP   S_DATA                    ; DATA?
    JR   NZ,.GO                    ; Other sections always have passes.
    LD   A,(OP_FLAGS)              ; Only under option R
    AND  OF_R                      ; does DATA hold blobs.
    RET  Z                         ; Without R it is empty.
.GO:                           ; The classes from 7 down.
    LD   A,7                       ; 256-byte alignment first.
.CLASS:                        ; A is the class.
    LD   (WK_CLASS),A              ; The pass's class.
    CALL .PRESENT                  ; NZ when a live blob has it.
    CALL NZ,WK_BOTH                ; Walk both directories for it.
    LD   A,(WK_CLASS)              ; The class,
    SUB  1                         ; less one;
    JR   NC,.CLASS                 ; down to class 0.
    RET                            ; Every class is done.

;@ROUTINE OUT A,ZERO CLOBBERS B,CARRY,SIGN,PARITY,HALFCARRY
; NZ when alignment class WK_CLASS has a live blob.

.PRESENT:                      ; PB_CLASS has a bit per class present.
    LD   A,(WK_CLASS)              ; The class,
    INC  A                         ; plus one,
    LD   B,A                       ; is the rotation count.
    LD   A,(PB_CLASS)              ; The classes present.
.SHIFT:                        ; Rotate the class's bit past bit 0.
    RRCA                           ; One place right.
    DJNZ .SHIFT                    ; Class + 1 places.
    RLCA                           ; Back one: bit 0 is the class's.
    AND  1                         ; Keep it alone.
    RET                            ; NZ when present.

; ---- Phase C -----------------------------------------------------------------

;@ROUTINE CLOBBERS A,BC,DE,HL,IX,CARRY,ZERO,SIGN,PARITY,HALFCARRY
; Phase C: place START, TEXT, DATA and BSS, then the file table; give live
; aliases their addresses; set the stack reserve and the pseudo-objects;
; and check the fit (linker §6.4). L-FIT-IMAGE and L-FIT-MEMORY end the
; link, as soon as placement passes $FFFF; L-FIT-NOMINAL is a warning.

PC_RUN:                        ; Phase B has marked the live blobs.
    XOR  A                         ; The CRCs were checked in Phase A,
    LD   (RD_CRC),A                ; so the walks read without them.
    LD   HL,(PF_BASE)              ; The image starts at the profile's base.
    LD   (PC_NEXT),HL              ; The cursor starts there.
    LD   A,S_START                 ; START first,
    CALL .PLACESEC                 ; placed,
    LD   A,S_TEXT                  ; then TEXT,
    CALL .PLACESEC                 ; placed.
    LD   A,S_DATA                  ; Empty, at TEXT's end, without R.
    CALL .PLACESEC                 ; HL and DE are DATA's start and end.
    LD   (DATA_BEG),HL             ; Keep them
    LD   (DATA_END),DE             ; for COPY and the pseudo-objects.
    EX   DE,HL                     ; COPY follows DATA: the image ends at
    PUSH HL                        ; DATA's end plus its size.
    OR   A                         ; Clear carry for the subtraction.
    SBC  HL,DE                     ; HL is DATA's size.
    POP  DE                        ; DE is DATA's end.
    ADD  HL,DE                     ; HL is COPY's end,
    JP   C,.WRAP                   ; past $FFFF: L-FIT-IMAGE.
    LD   (IMG_END),HL              ; The image ends there.
    LD   (PC_NEXT),HL              ; BSS follows the image.
    EX   DE,HL                     ; Fit checks (linker §6.4): the image
    LD   HL,(PF_LIMIT)             ; must end at or below the image limit,
    OR   A                         ; checked before BSS is placed, as the
    SBC  HL,DE                     ; reference checks it first.
    LD   HL,216                    ; L-FIT-IMAGE.
    JP   C,DG_PLAIN                ; Report it.
    LD   A,S_BSS                   ; Place BSS.
    CALL .PLACESEC                 ; HL is its start.
    LD   (BSS_BEG),HL              ; Keep it.
    LD   A,(OP_FILES)              ; The file table, after BSS, when the
    OR   A                         ; program uses files: F= entries,
    JR   NZ,.SETCOUNT              ; if given,
    LD   A,4                       ; or four.
.SETCOUNT:                     ; A is the entry count.
    LD   (FT_COUNT),A              ; Keep it.
    LD   HL,(PC_NEXT)              ; The table starts at the cursor,
    LD   (FT_ADDR),HL              ; after BSS.
    LD   HL,0                      ; Its size is 0
    LD   A,(PB_FILES)              ; unless the program uses files.
    OR   A                         ; Does it?
    JR   Z,.NOFILES                ; No: an empty table.
    LD   A,(FT_COUNT)              ; The entries,
    LD   B,A                       ; counted in B,
    LD   DE,(PF_FILE)              ; times the profile's entry size.
.MUL:                          ; HL accumulates the size.
    ADD  HL,DE                     ; One entry more,
    JP   C,.WRAP                   ; past $FFFF: L-FIT-MEMORY.
    DJNZ .MUL                      ; FT_COUNT times.
.NOFILES:                      ; HL is the table's size.
    LD   (FT_SIZE),HL              ; Keep it.
    LD   DE,(PC_NEXT)              ; FREE is the first address
    ADD  HL,DE                     ; after the table,
    JP   C,.WRAP                   ; past $FFFF: L-FIT-MEMORY.
    LD   (PC_FREE),HL              ; Kept.
    LD   HL,0                      ; Aliases of live blobs: their address and size.
.ALIAS:                        ; HL walks every position.
    PUSH HL                        ; Keep it.
    CALL TAB_AT                    ; HL is its entry; carry past the end.
    JR   C,.ADONE                  ; Every alias is placed.
    BIT  6,(HL)                    ; An alias?
    CALL NZ,.SETALIAS              ; Place it if its base is live.
    POP  HL                        ; HL is the position.
    INC  HL                        ; The next.
    JR   .ALIAS                    ; Go on.
.ADONE:                        ; The position is on the stack.
    POP  HL                        ; Drop it.
    LD   HL,(PA_LIMIT)             ; The stack reserve: the compiler's,
    LD   DE,(OP_STACK)             ; or STACK= when larger.
    PUSH HL                        ; Keep the compiler's.
    OR   A                         ; Clear carry for the subtraction.
    SBC  HL,DE                     ; Carry if STACK= is larger.
    POP  HL                        ; HL is the compiler's.
    JR   NC,.RES                   ; It is at least STACK=.
    EX   DE,HL                     ; HL is STACK=.
.RES:                          ; HL is the larger.
    LD   (PC_STACK),HL             ; The reserve.
    CALL .PSEUDOS                  ; The pseudo-objects' rows.
    LD   HL,(PC_FREE)              ; FREE plus the reserve
    LD   DE,(PC_STACK)             ; must stay within
    ADD  HL,DE                     ; the address space.
    LD   HL,217                    ; L-FIT-MEMORY: past $FFFF.
    JP   C,DG_PLAIN                ; Report it.
    LD   HL,(PC_FREE)              ; FREE plus the reserve
    ADD  HL,DE                     ; is REQUIRED,
    EX   DE,HL                     ; DE = the memory needed.
    LD   HL,(PF_TOP)               ; It should be at or below the nominal top,
    LD   A,(OP_FLAGS)              ; or, keeping the CCP,
    AND  OF_B                      ; with option B,
    JR   Z,.TOP                    ; (not given)
    LD   HL,(PF_LIMIT)             ; the image limit.
.TOP:                          ; HL is the top that applies.
    OR   A                         ; Clear carry for the subtraction.
    SBC  HL,DE                     ; Carry if REQUIRED is above it.
    RET  NC                        ; It fits.
    LD   HL,219                    ; L-FIT-NOMINAL: a warning only.
    JP   DG_WARN                   ; Report it; the link goes on.

;@ROUTINE NORETURN
; Placement passed $FFFF: L-FIT-MEMORY in BSS and the file table, which
; follow the image, else L-FIT-IMAGE.

.WRAP:                         ; WK_SEC is the section being placed.
    LD   HL,217                    ; L-FIT-MEMORY,
    LD   A,(WK_SEC)                ; in BSS
    CP   S_BSS                     ; or after it;
    JP   Z,DG_PLAIN                ; report it.
    DEC  HL                        ; L-FIT-IMAGE,
    JP   DG_PLAIN                  ; in the image; report it.

;@ROUTINE IN A OUT DE,HL CLOBBERS A,BC,IX,CARRY,ZERO,SIGN,PARITY,HALFCARRY
; Place section A: return HL = its start and DE = its end. The first blob
; placed is of the largest class present, so the section starts at its
; address, which is the cursor rounded up to that class (linker §6.3).

.PLACESEC:                     ; A is an S_ value.
    LD   HL,(PC_NEXT)              ; An empty section starts
    LD   (PC_BEG),HL               ; at the cursor.
    LD   HL,PC_BEGUN               ; No blob is placed yet:
    LD   (HL),0                    ; the first sets PC_BEG.
    LD   HL,.PLACE                 ; Place each blob of the passes.
    CALL WK_PASS                   ; Make the section's passes.
    LD   HL,(PC_BEG)               ; HL is the section's start,
    LD   DE,(PC_NEXT)              ; DE its end.
    RET                            ; The section is placed.

;@ROUTINE CLOBBERS A,BC,DE,HL,CARRY,ZERO,SIGN,PARITY,HALFCARRY
; Place the blob just read, if it is in the pass, and skip its references.

.PLACE:                        ; A walk's callback.
    CALL WK_MATCH                  ; Z if the blob is in the pass.
    JP   NZ,REF_SKIP               ; Not in it: skip its references.
    LD   HL,(WK_ENTRY)             ; The alignment:
    LD   DE,E_LAYOUT               ; the entry's
    ADD  HL,DE                     ; layout byte,
    LD   A,(HL)                    ; the alignment code.
    CALL .ALIGN                    ; HL = the cursor rounded up.
    LD   A,(PC_BEGUN)              ; The section starts at its first blob.
    OR   A                         ; Is this the first?
    JR   NZ,.SET                   ; No.
    DEC  A                         ; A = $FF:
    LD   (PC_BEGUN),A              ; the first is placed,
    LD   (PC_BEG),HL               ; and starts the section.
.SET:                          ; HL is the blob's address.
    EX   DE,HL                     ; DE = the address.
    LD   HL,(WK_ENTRY)             ; The entry.
    INC  HL                        ; Its size,
    LD   C,(HL)                    ; low byte,
    INC  HL                        ; then
    LD   B,(HL)                    ; BC = the size.
    INC  HL                        ; Its address field
    LD   (HL),E                    ; takes the address,
    INC  HL                        ; low byte
    LD   (HL),D                    ; first.
    EX   DE,HL                     ; HL is the address.
    ADD  HL,BC                     ; Plus the size
    JR   C,.WRAP                   ; may not pass $FFFF;
    LD   (PC_NEXT),HL              ; it is the next free address.
    JP   REF_SKIP                  ; Skip its references.

;@ROUTINE IN A OUT HL CLOBBERS A,B,DE,CARRY,ZERO,SIGN,PARITY,HALFCARRY
; Return HL = PC_NEXT rounded up to alignment code A: 2^A bytes, 256 for 7.

.ALIGN:                        ; A is the alignment code, 0 to 7.
    LD   HL,(PC_NEXT)              ; The cursor.
    OR   A                         ; Code 0:
    RET  Z                         ; no alignment.
    LD   B,A                       ; B is the power of two,
    LD   DE,1                      ; built in DE.
    CP   7                         ; Code 7
    JR   NZ,.POW                   ; is not 2^7
    INC  B                         ; but 256 bytes, 2^8.
.POW:                          ; Double DE B times.
    SLA  E                         ; Shift the low byte,
    RL   D                         ; carrying into the high.
    DJNZ .POW                      ; DE is 2^B.
    DEC  DE                        ; The mask: the low bits.
    ADD  HL,DE                     ; Round up past the boundary,
    JR   C,.WRAP                   ; which may not pass $FFFF,
    LD   A,E                       ; then clear
    CPL                            ; the mask's
    AND  L                         ; bits
    LD   L,A                       ; in L
    LD   A,D                       ; and
    CPL                            ; in
    AND  H                         ; H.
    LD   H,A                       ; HL is aligned.
    RET                            ; The cursor rounded up.

;@ROUTINE IN HL CLOBBERS A,BC,DE,HL,CARRY,ZERO,SIGN,PARITY,HALFCARRY
; The alias entry at HL: when its base is live, its address is the base's
; plus its offset, its size the base's less its offset, and it is marked
; live, which Phase B never does for an alias.

.SETALIAS:                     ; HL is an alias entry.
    PUSH HL                        ; Keep it.
    INC  HL                        ; Its size field holds the offset:
    LD   C,(HL)                    ; low byte,
    INC  HL                        ; then
    LD   B,(HL)                    ; BC = the offset.
    INC  HL                        ; Its address field holds the base:
    LD   E,(HL)                    ; low byte,
    INC  HL                        ; then
    LD   D,(HL)                    ; DE = the base ordinal.
    EX   DE,HL                     ; HL is the base.
    PUSH BC                        ; Keep the offset.
    CALL TAB_FIND                  ; HL is the base's entry.
    POP  BC                        ; BC is the offset.
    POP  DE                        ; DE = the alias entry.
    RET  C                         ; No entry: never so after Phase A.
    BIT  5,(HL)                    ; Is the base live?
    RET  Z                         ; A dead base: the alias stays unplaced.
    INC  HL                        ; The base's size less the offset:
    LD   A,(HL)                    ; the low byte,
    SUB  C                         ; less the offset's,
    LD   (PS_TAB),A                ; kept in PS_TAB as scratch;
    INC  HL                        ; then the high byte,
    LD   A,(HL)                    ; less the offset's
    SBC  A,B                       ; with the borrow,
    PUSH AF                        ; kept on the stack.
    INC  HL                        ; The base's address plus the offset:
    LD   A,(HL)                    ; the low byte,
    ADD  A,C                       ; plus the offset's,
    LD   C,A                       ; in C;
    INC  HL                        ; then the high byte,
    LD   A,(HL)                    ; plus the offset's
    ADC  A,B                       ; with the carry,
    LD   B,A                       ; BC = the alias's address.
    EX   DE,HL                     ; HL = the alias entry.
    SET  5,(HL)                    ; EF_LIVE: placed, for the symbol file.
    INC  HL                        ; Its size field
    LD   A,(PS_TAB)                ; takes the effective size,
    LD   (HL),A                    ; low byte,
    INC  HL                        ; then
    POP  AF                        ; the high byte.
    LD   (HL),A                    ; Stored.
    INC  HL                        ; Its address field
    LD   (HL),C                    ; takes the address,
    INC  HL                        ; low byte
    LD   (HL),B                    ; then high.
    RET                            ; The alias is placed.

;@ROUTINE CLOBBERS A,BC,DE,HL,CARRY,ZERO,SIGN,PARITY,HALFCARRY
; Fill PS_TAB with the pseudo-objects' addresses and sizes (object format
; §3.6), in ordinal order from MAIN ($FFE0) to FILECOUNT ($FFE9).

.PSEUDOS:                      ; Phase C has placed every section.
    LD   HL,PS_TAB                 ; The rows are written in order
    LD   (.ROWPTR),HL              ; from the table's start.
    LD   HL,(PA_MAIN)              ; MAIN: the entry routine's
    CALL TAB_FIND                  ; entry.
    INC  HL                        ; Its size,
    LD   C,(HL)                    ; low byte,
    INC  HL                        ; then
    LD   B,(HL)                    ; high, in BC.
    INC  HL                        ; Its address,
    LD   E,(HL)                    ; low byte,
    INC  HL                        ; then
    LD   D,(HL)                    ; high, in DE.
    CALL .PUT                      ; Address DE, size BC.
    LD   DE,(PF_BASE)              ; IMAGE: from the base
    LD   HL,(IMG_END)              ; to the image's end.
    CALL .SPAN                     ; Its row.
    LD   HL,(FT_ADDR)              ; BSS: to the end of the file table.
    LD   BC,(FT_SIZE)              ; The table's end
    ADD  HL,BC                     ; is FREE.
    LD   DE,(BSS_BEG)              ; From BSS's start.
    CALL .SPAN                     ; Its row.
    LD   DE,(PC_FREE)              ; FREE: an address,
    LD   BC,0                      ; of size 0.
    CALL .PUT                      ; Its row.
    LD   HL,(PC_STACK)             ; REQUIRED: FREE plus the reserve,
    LD   B,H                       ; of the reserve's
    LD   C,L                       ; size.
    ADD  HL,DE                     ; FREE plus the reserve
    EX   DE,HL                     ; is the address.
    CALL .PUT                      ; Its row.
    LD   HL,(DATA_END)             ; DATA, then DATACOPY: COPY, at DATA's
    LD   DE,(DATA_BEG)             ; end, of DATA's size (empty, at TEXT's
    CALL .SPAN                     ; end, without R).
    LD   DE,(DATA_END)             ; DATACOPY's address; BC is still DATA's size.
    CALL .PUT                      ; Its row.
    LD   A,(OP_FLAGS)              ; OPTIONS: 1 keep the CCP (B), 2 re-runnable
    XOR  OF_N                      ; (R), 4 a line table (not N): bits 5, 4
    RRCA                           ; and 3 of the flags, reversed:
    RRCA                           ; rotated down
    RRCA                           ; to bits 2, 1 and 0.
    LD   DE,0                      ; DE collects them,
    LD   B,3                       ; three bits.
.OPT:                          ; Move bit 0 of A into E, reversing the order.
    RRA                            ; The next bit, into carry.
    RL   E                         ; Into E from the right.
    DJNZ .OPT                      ; Line table, then R, then B.
    LD   B,D                       ; BC = 0:
    LD   C,D                       ; OPTIONS has no size.
    CALL .PUT                      ; Its row: the value as an address.
    LD   DE,(FT_ADDR)              ; FILES: the file table,
    LD   BC,(FT_SIZE)              ; and its size.
    CALL .PUT                      ; Its row.
    LD   BC,0                      ; FILECOUNT: a value of size 0,
    LD   D,B                       ; 0
    LD   E,B                       ; unless
    LD   A,(PB_FILES)              ; the program uses files.
    OR   A                         ; Does it?
    JR   Z,.PUT                    ; No: 0.
    LD   A,(FT_COUNT)              ; The entries,
    LD   E,A                       ; as the value; fall into .PUT.

;@ROUTINE IN BC,DE CLOBBERS HL
; Write the next row of PS_TAB: address DE, size BC. Keeps BC and DE.

.PUT:                          ; .ROWPTR is the next row.
    LD   HL,(.ROWPTR)              ; Where it goes.
    LD   (HL),E                    ; The address,
    INC  HL                        ; low byte
    LD   (HL),D                    ; then high.
    INC  HL                        ; The size,
    LD   (HL),C                    ; low byte
    INC  HL                        ; then
    LD   (HL),B                    ; high.
    INC  HL                        ; The next row.
    LD   (.ROWPTR),HL              ; Keep it.
    RET                            ; BC and DE are unchanged.

;@ROUTINE IN DE,HL OUT BC CLOBBERS HL,CARRY,ZERO,SIGN,PARITY,HALFCARRY
; Write the next row of PS_TAB: address DE, size HL - DE.

.SPAN:                         ; HL is the end, DE the start.
    OR   A                         ; Clear carry for the subtraction.
    SBC  HL,DE                     ; HL is the size.
    LD   B,H                       ; BC is
    LD   C,L                       ; the size.
    JR   .PUT                      ; Write the row.

.ROWPTR:                       ; The next row of PS_TAB.
    DW   0                         ; Set by .PSEUDOS.
