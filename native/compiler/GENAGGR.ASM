;==========================================================================
;  Aggregate code generation
;==========================================================================
;
;  The reference compiler's templates for paths into records, arrays and
;  strings (ref/compile/compiler.ts: emitAddress, loadDesignator, indexArray,
;  indexString, boundsCheck, scaleHL, addConst) and for its string
;  literals, which follow the routine's need word (compileBody). CALLS.ASM
;  parses a path and keeps its place in RO_PLACE (CALLWORK.ASM); these
;  routines write its code.
;
;  A place says where the object a path names is, as the reference's Place
;  does:
;    GA_BLOB   static: RO_PADD bytes into blob RO_PBASE (a program
;              variable or an aggregate constant)
;    GA_FRAME  in the frame, at IX+RO_PADD (a local, or an open string's
;              capacity word)
;    GA_ALIAS  RO_PADD bytes on from the address in the word at
;              IX+RO_PBASE (an aggregate parameter)
;    GA_HELD   computed: the address is in HL
;  The reference writes a path's code when the path is used. Here each
;  step's code is written as soon as it is parsed. Nothing comes between
;  the end of a path and its use (the reference's arguments compute the
;  address first, too), so the bytes come out in the same order, and only
;  the place in hand is kept.
;
;  Literals. A string literal is an object of its own that follows the
;  routine's need word, in the order the literals were made. Each has an
;  entry in the blob writer's log (BL_TLIT, BLOB.ASM), after its operand's
;  reference, whose addend word is written when the literal is placed: the
;  source address of its opening quote, its decoded length and the bytes
;  it occupies: its length byte, its characters, then zeros, as many as
;  its string's capacity and terminator need.
;
;  Principal entries:
;    GA_ADDR   leave the place's address in HL (emitAddress)
;    GA_SLOT   a frame slot's address into HL
;    GA_VIA    the address an alias place names into HL
;    GA_ADDC   add a constant to HL (addConst)
;    GA_MOVE   move the place on by a field's or element's offset
;    GA_LOAD   load the scalar at the place (loadDesignator)
;    GA_STORE  store the registers into the scalar at the place
;    GA_LDF    load the File at the place into DEHL
;    GA_STF    store DEHL into the File at the place
;    GA_PLACE  a static or frame place's access through a GENEXPR routine
;    GA_ITEM   address an array element at a run-time index
;    GA_CHAR   address a string's character, checked against its length
;    GA_ZERO   zero a local (zeroFrame)
;    GA_FILL   store a local's staged initializer (storeBytesToFrame)
;    GA_COPY   copy an aggregate into a local (copyToFrame)
;    GA_LDIR   LD BC,n and LDIR
;    GA_LIT    LD HL, a string literal
;    GA_LITS   place the routine's literals

;@ROUTINE CLOBBERS A,BC,DE,HL,CARRY,ZERO,SIGN,PARITY,HALFCARRY
; Leave the address of the place in hand in HL (emitAddress): LD HL,nn for a
; static place; PUSH IX, POP HL and the offset for a frame place; the
; address word for an alias, and the bytes on from it; nothing when it is
; computed already. The place is computed afterwards.

GA_ADDR:                       ; RO_PLACE is the place.
    LD   HL,RO_PKIND               ; Its kind,
    LD   A,(HL)                    ; read,
    LD   (HL),GA_HELD              ; becomes computed.
    LD   HL,(RO_PADD)              ; The bytes on from the base.
    OR   A                         ; Static?
    JR   Z,.STATIC                 ; LD HL,nn.
    DEC  A                         ; The frame?
    JR   Z,GA_SLOT                 ; PUSH IX, POP HL, the offset.
    DEC  A                         ; An alias?
    JR   Z,GA_VIA                  ; Its address word, and the bytes on.
    RET                            ; No: computed, in HL already.
.STATIC:                       ; HL is the offset into the blob,
    LD   BC,(RO_PBASE)             ; the addend of a reference to it,
    LD   A,$21                     ; the operand of LD HL,nn.
    JP   GX_ABSH                   ; Append them and return.

;@ROUTINE IN HL CLOBBERS A,B,CARRY,ZERO,SIGN,PARITY,HALFCARRY
; Leave in HL at run time the address of the frame slot at IX+HL
; (ixAddress): PUSH IX, POP HL, then LD DE,offset and ADD HL,DE unless
; the offset is zero (addSigned).

GA_SLOT:                       ; HL is the offset from IX.
    CALL EM_SEQ                    ; HL = IX:
    DB   3,$DD,$E5,$E1             ; PUSH IX, POP HL.
    JR   GA_ADDS                   ; Then the offset; return.

;@ROUTINE CLOBBERS A,BC,DE,HL,CARRY,ZERO,SIGN,PARITY,HALFCARRY
; Leave in HL the address an alias place names: LD L,(IX+n), LD H,(IX+n+1)
; for its address word, at IX+RO_PBASE (ixWord), then its bytes on,
; RO_PADD, added (GA_ADDC).

GA_VIA:                        ; The place is an alias.
    LD   HL,(RO_PBASE)             ; The address word's offset from IX,
    LD   A,SY_U16                  ; a word,
    CALL GX_FLOAD                  ; loaded into HL (ixWord).
    LD   HL,(RO_PADD)              ; The bytes on; fall into GA_ADDC.

;@ROUTINE IN HL CLOBBERS A,B,HL,CARRY,ZERO,SIGN,PARITY,HALFCARRY
; Add the constant HL to the address in HL at run time (addConst): INC HL
; for each of one to three, LD DE,n and ADD HL,DE above that, nothing for
; zero.

GA_ADDC:                       ; HL is the constant.
    LD   A,H                       ; Above 255?
    OR   A                         ; Then
    JR   NZ,GA_ADDS                ; through DE.
    LD   A,L                       ; Above three?
    CP   4                         ; Then
    JR   NC,GA_ADDS                ; through DE.
    OR   A                         ; Zero?
    RET  Z                         ; Nothing to add.
    LD   B,A                       ; One INC HL each.
.STEP:                         ; B remain.
    CALL EM_OP                     ; INC HL.
    DB   $23                       ; Append it.
    DJNZ .STEP                     ; Until each is added.
    RET                            ; HL is moved on.

;@ROUTINE IN HL CLOBBERS A,CARRY,ZERO,SIGN,PARITY,HALFCARRY
; Add the constant HL to the address in HL at run time through DE
; (addSigned): LD DE,n and ADD HL,DE, nothing for zero.

GA_ADDS:                       ; HL is the constant.
    LD   A,H                       ; Zero?
    OR   L                         ; Then
    RET  Z                         ; nothing is added.
    CALL GA_LDDE                   ; LD DE,n.
    CALL EM_OPX                    ; ADD HL,DE.
    DB   $19                       ; Append it and return.

;@ROUTINE IN HL CLOBBERS A,CARRY,ZERO,SIGN,PARITY,HALFCARRY
; Append LD DE,n, n in HL.

GA_LDDE:                       ; HL is n.
    CALL EM_OP                     ; LD DE,n:
    DB   $11                       ; the opcode,
    JP   EM_WORD                   ; and n; return.

;@ROUTINE IN HL CLOBBERS A,B,DE,HL,CARRY,ZERO,SIGN,PARITY,HALFCARRY
; Move the place in hand on by HL bytes, a field's or an element's offset
; (offsetPlace): a computed place adds them to HL at run time; any other
; keeps them in RO_PADD.

GA_MOVE:                       ; HL is the offset.
    LD   A,(RO_PKIND)              ; Is the place computed?
    CP   GA_HELD                   ; Then the code adds it,
    JR   Z,GA_ADDC                 ; and returns.
    LD   DE,(RO_PADD)              ; Otherwise the bytes on
    ADD  HL,DE                     ; grow
    LD   (RO_PADD),HL              ; by it.
    RET                            ; The place has moved.

;@ROUTINE CLOBBERS A,BC,DE,HL,CARRY,ZERO,SIGN,PARITY,HALFCARRY
; Load the scalar of type RO_OTYPE at the place into the registers
; (loadDesignator): from a static place LD A,(nn), LD HL,(nn), or for a
; long LD HL,(nn) and LD DE,(nn+2) (GX_LOADD); from the frame (IX+d) near
; or far (GX_FLOAD); through an alias or a computed address LD A,(HL), or
; LD E,(HL), INC HL, LD D,(HL), EX DE,HL for a word, and for a long
; LD E,(HL), INC HL, LD D,(HL), INC HL, PUSH DE, LD E,(HL), INC HL,
; LD D,(HL), POP HL (loadRegistersIndirect).

GA_LOAD:                       ; RO_PLACE is the place.
    LD   A,(RO_PKIND)              ; Static or in the frame?
    CP   GA_ALIAS                  ; Otherwise
    JR   NC,.ADDR                  ; through the address.
    LD   A,(RO_OTYPE)              ; The type is loaded
    LD   HL,GX_LOADD               ; from the blob
    LD   DE,GX_FLOAD               ; or the frame,
    JR   GA_PLACE                  ; at the place; return.
.ADDR:                         ; An alias or a computed place.
    CALL GA_ADDR                   ; Its address into HL.
    LD   A,(RO_OTYPE)              ; The type's
    CALL GX_SIZE                   ; size:
    LD   A,$7E                     ; LD A,(HL)
    JP   C,EM_BYTE                 ; for a byte; return.
    JR   NZ,.LONG                  ; A long's two words.
    CALL EM_SEQX                   ; A word through HL:
    DB   4,$5E,$23,$56,$EB         ; LD E,(HL), INC HL, LD D,(HL), EX DE,HL.
.LONG:                         ; Four bytes:
    CALL EM_SEQX                   ; LD E,(HL), INC HL, LD D,(HL), INC HL,
    DB   9,$5E,$23,$56,$23,$D5,$5E,$23,$56,$E1 ; PUSH DE, the high word, POP HL.

;@ROUTINE CLOBBERS A,BC,DE,HL,CARRY,ZERO,SIGN,PARITY,HALFCARRY
; Store the registers, of type RO_OTYPE, into the scalar at a place that
; is not computed (storeRegisters): LD (nn),A, LD (nn),HL, or LD (nn),HL
; and LD (nn+2),DE for a static place (GX_STORD), (IX+d) near or far for
; the frame (GX_FPUT); through an alias, GA_STAL. A computed place takes
; the address first (RO_LET).

GA_STORE:                      ; RO_PLACE is the place.
    LD   A,(RO_PKIND)              ; Through
    CP   GA_ALIAS                  ; an alias?
    JR   Z,GA_STAL                 ; Its address word first.
    LD   A,(RO_OTYPE)              ; The type is stored
    LD   HL,GX_STORD               ; into the blob
    LD   DE,GX_FPUT                ; or the frame,
    JR   GA_PLACE                  ; at the place; return.

;@ROUTINE CLOBBERS A,BC,DE,HL,CARRY,ZERO,SIGN,PARITY,HALFCARRY
; Load the File at the place, static or in the frame (a File is never
; reached through an address), into DEHL (loadRegisters, four bytes): LD
; HL,(nn) and LD DE,(nn+2), or the frame's two words into HL and then DE,
; each near or far (ixWord): a long's load.

GA_LDF:                        ; RO_PLACE is the place.
    LD   HL,GX_LOADD               ; From the blob
    LD   DE,GX_FLOAD               ; or the frame,
    JR   GA_FILE                   ; a long's load.

;@ROUTINE CLOBBERS A,BC,DE,HL,CARRY,ZERO,SIGN,PARITY,HALFCARRY
; Store DEHL into the File at the place, static or in the frame
; (storeRegisters, four bytes): LD (nn),HL and LD (nn+2),DE, or the
; frame's four bytes in one access, near or far (ixStoreDEHL): a long's
; store.

GA_STF:                        ; RO_PLACE is the place.
    LD   HL,GX_STORD               ; Into the blob
    LD   DE,GX_FPUT                ; or the frame; fall into GA_FILE.

;@ROUTINE IN DE,HL CLOBBERS A,BC,DE,HL,CARRY,ZERO,SIGN,PARITY,HALFCARRY
; GA_PLACE for a File's four bytes, the size of a long.

GA_FILE:                       ; HL and DE are the routines.
    LD   A,SY_U32                  ; A long's access; fall into GA_PLACE.

;@ROUTINE IN A,DE,HL CLOBBERS A,BC,DE,HL,CARRY,ZERO,SIGN,PARITY,HALFCARRY
; Access the scalar of type A at a static or frame place: routine HL
; (GX_LOADD or GX_STORD) for a static place, given its blob in BC and its
; bytes on in HL; routine DE (GX_FLOAD or GX_FPUT) for a frame place,
; given its offset from IX in HL. The routine returns to the caller.

GA_PLACE:                      ; A is the type, HL and DE the routines.
    PUSH AF                        ; Keep the type.
    LD   A,(RO_PKIND)              ; Is the place
    OR   A                         ; static?
    JR   NZ,.FRAME                 ; No: routine DE.
    EX   DE,HL                     ; Yes: routine HL.
.FRAME:                        ; DE is the routine.
    POP  AF                        ; The type.
    PUSH DE                        ; The routine, entered by the RET.
    LD   HL,(RO_PADD)              ; The bytes on or the offset,
    LD   BC,(RO_PBASE)             ; and the blob for a static place.
    RET                            ; Enter the routine.

;@ROUTINE CLOBBERS A,BC,DE,HL,CARRY,ZERO,SIGN,PARITY,HALFCARRY
; Store the registers, of type RO_OTYPE, through an alias place
; (storeRegisters): the value is kept while the address word is loaded,
; LD L,(IX+n), LD H,(IX+n+1), and the bytes on are added (GA_ADDC): a
; byte, then LD (HL),A; a word, EX DE,HL first, then LD (HL),E, INC HL,
; LD (HL),D, or with more than three bytes on, which go through DE, PUSH
; HL first and POP DE before; a long, PUSH DE, PUSH HL first, then POP DE
; and the low word, INC HL, POP DE and the high word.

GA_STAL:                       ; The value is in the registers.
    LD   A,(RO_OTYPE)              ; Its size:
    CALL GX_SIZE                   ; a byte
    JR   NC,.WIDER                 ; is in A:
    CALL GA_VIA                    ; the address, the alias's word and the
    CALL EM_OPX                    ; bytes on, then LD (HL),A.
    DB   $77                       ; Appended; return.
.WIDER:                        ; A word or a long.
    JR   NZ,.LONG                  ; A word
    LD   HL,(RO_PADD)              ; with
    LD   A,H                       ; at most
    OR   A                         ; three
    JR   NZ,.FAR                   ; bytes
    LD   A,L                       ; on
    CP   4                         ; goes
    JR   NC,.FAR                   ; to DE:
    CALL EM_OP                     ; EX DE,HL;
    DB   $EB                       ; then
    CALL GA_VIA                    ; the address,
    CALL EM_SEQX                   ; LD (HL),E, INC HL, LD (HL),D.
    DB   3,$73,$23,$72             ; Stored.
.FAR:                          ; A word beyond:
    CALL GX_PUSHW                  ; PUSH HL, two bytes pushed;
    CALL GA_VIA                    ; the address,
    CALL EM_SEQ                    ; POP DE, LD (HL),E, INC HL, LD (HL),D,
    DB   4,$D1,$73,$23,$72         ; stored;
    JP   EM_POP2                   ; two bytes popped; return.
.LONG:                         ; Four bytes:
    LD   A,(RO_OTYPE)              ; PUSH DE, PUSH HL,
    CALL GX_PUSH                   ; four bytes pushed;
    CALL GA_VIA                    ; the address, then the low word,
    CALL EM_SEQ                    ; INC HL, POP DE, the high word:
    DB   9,$D1,$73,$23,$72,$23,$D1,$73,$23,$72 ; POP DE, LD (HL),E, INC HL...
    LD   A,4                       ; four bytes
    JP   EM_POP                    ; popped; return.


;@ROUTINE IN D,HL CLOBBERS A,BC,DE,HL,CARRY,ZERO,SIGN,PARITY,HALFCARRY
; Address an element of the array RO_OTYPE at a run-time index
; (indexArray): the index, metadata D and value HL, into HL as a u16;
; LD DE,length, or an open array's word, LD E,(IX+n+2), LD D,(IX+n+3),
; then OR A, SBC HL,DE, CALL NC,TRAP_BND, ADD HL,DE (boundsCheck);
; the index scaled by the element's size (GA_SCALE); then the base's
; address, pushed already when RO_PPUSH says so, otherwise addressed now
; with the scaled index pushed meanwhile; POP DE, ADD HL,DE. The place is
; computed afterwards.

GA_ITEM:                       ; D and HL are the index.
    LD   E,SY_U16                  ; The index
    CALL GX_TOREG                  ; into HL as a word.
    LD   A,(RO_OTYPE)              ; An open array's
    SUB  AG_OPEN                   ; element
    JR   C,.FIXED                  ; is its ID's
    PUSH AF                        ; rest:
    LD   HL,(RO_PBASE)             ; its word
    INC  HL                        ; above
    INC  HL                        ; its address,
    LD   DE,GX_DLDDE               ; into DE
    CALL GX_FACC                   ; (ixWord).
    JR   .CHECK                    ; Check the index.
.FIXED:                        ; An array's
    ADD  A,AG_OPEN                 ; type's
    CALL AG_DESC                   ; descriptor:
    INC  HL                        ; its element type
    LD   A,(HL)                    ; is kept,
    PUSH AF                        ; for the stride.
    INC  HL                        ; Then its length:
    LD   E,(HL)                    ; low byte
    INC  HL                        ; and
    LD   D,(HL)                    ; high byte.
    EX   DE,HL                     ; The length:
    CALL GA_LDDE                   ; LD DE,length.
.CHECK:                        ; DE is the bound; the element type stacked.
    CALL GX_MINUS                  ; OR A, SBC HL,DE: no borrow when past,
    LD   A,$D4                     ; so CALL NC
    CALL GA_BOUND                  ; to the bounds trap.
    CALL EM_OP                     ; ADD HL,DE: the index again.
    DB   $19                       ; Append it.
    POP  AF                        ; The element type
    LD   (RO_OTYPE),A              ; is the path's next,
    CALL AG_SIZE                   ; and its size, HL,
    CALL GA_SCALE                  ; multiplies the index.
    LD   A,(RO_PPUSH)              ; Is the base pushed?
    RRCA                           ; Then pop it:
    JR   C,.POP                    ; POP DE.
    CALL GX_PUSHW                  ; Otherwise keep the offset: PUSH HL,
    CALL GA_ADDR                   ; while the base is addressed.
.POP:                          ; The other operand is pushed.
    CALL GA_POPDE                  ; POP DE, two bytes fewer pushed.
    CALL EM_OPX                    ; ADD HL,DE: the element's address.
    DB   $19                       ; Append it and return.

;@ROUTINE CLOBBERS A,DE,HL,CARRY,ZERO,SIGN,PARITY,HALFCARRY
; Append POP DE and count two bytes popped (pop). BC is kept.

GA_POPDE:                      ; A temporary goes to DE.
    CALL EM_OP                     ; POP DE.
    DB   $D1                       ; Append it.
    JP   EM_POP2                   ; Two bytes fewer pushed; return.

;@ROUTINE CLOBBERS A,B,DE,HL,CARRY,ZERO,SIGN,PARITY,HALFCARRY
; Append EX DE,HL and POP HL, and count two bytes popped: the address just
; computed goes to DE and the one pushed before it comes back to HL. C is
; kept.

GA_SWAP:                       ; HL was pushed, then an address computed.
    CALL EM_SEQ                    ; EX DE,HL, POP HL:
    DB   2,$EB,$E1                 ; the two swap places.
    JP   EM_POP2                   ; Two bytes fewer pushed; return.

;@ROUTINE IN D,HL CLOBBERS A,BC,DE,HL,CARRY,ZERO,SIGN,PARITY,HALFCARRY
; Address a character of the string at the place (indexString): the index,
; metadata D and value HL, into HL as a u16; the string's address into HL
; and the index into DE, whether the base was pushed (RO_PPUSH) or is
; addressed now; trap unless the index is below the length byte at (HL),
; with a zero high byte; then the character's address. The place is
; computed afterwards.

GA_CHAR:                       ; D and HL are the index.
    LD   E,SY_U16                  ; The index
    CALL GX_TOREG                  ; into HL as a word.
    LD   A,SY_U8                   ; A character
    LD   (RO_OTYPE),A              ; is a u8.
    LD   A,(RO_PPUSH)              ; Is the string's address pushed?
    RRCA                           ; Then
    JR   NC,.BASE                  ; it is popped:
    CALL GA_SWAP                   ; EX DE,HL, POP HL; the index in DE.
    JR   .CHECK                    ; Check it.
.BASE:                         ; The string is addressed now.
    CALL GX_PUSHW                  ; PUSH HL: the index waits,
    CALL GA_ADDR                   ; while the string is addressed,
    CALL GA_POPDE                  ; then POP DE brings it back.
.CHECK:                        ; HL is the string, DE the index.
    CALL EM_SEQ                    ; LD A,E, CP (HL):
    DB   2,$7B,$BE                 ; carry when the index is below the length;
    LD   A,$D4                     ; CALL NC
    CALL GA_BOUND                  ; to the bounds trap.
    CALL EM_SEQ                    ; LD A,D, OR A:
    DB   2,$7A,$B7                 ; a high byte is out of range too;
    LD   A,$C4                     ; CALL NZ
    CALL GA_BOUND                  ; to the bounds trap.
    CALL EM_SEQX                   ; INC HL, ADD HL,DE.
    DB   2,$23,$19                 ; Past the length byte, the index on.

;@ROUTINE IN A CLOBBERS A,BC,DE,HL,CARRY,ZERO,SIGN,PARITY,HALFCARRY
; Append the trap site CALL cc,TRAP_BND whose opcode is A (boundsCheck).

GA_BOUND:                      ; A is CALL cc.
    LD   L,HP_BOUND&$FF            ; The bounds trap.
    JP   EM_TRAP                   ; Append the site and return.

;@ROUTINE IN HL CLOBBERS A,DE,HL,CARRY,ZERO,SIGN,PARITY,HALFCARRY
; Multiply the index in HL at run time by the stride HL (scaleHL): nothing
; for one, ADD HL,HL for each halving of a power of two, otherwise a
; shift-and-add from a copy in DE: LD D,H, LD E,L, LD HL,0, then for each
; bit from the lowest ADD HL,DE when it is set and EX DE,HL, ADD HL,HL, EX
; DE,HL while bits remain above it.

GA_SCALE:                      ; HL is the stride.
    LD   D,H                       ; DE is
    LD   E,L                       ; the stride
    DEC  DE                        ; less one,
    LD   A,D                       ; which shares
    AND  H                         ; no bit
    LD   D,A                       ; with it
    LD   A,E                       ; when it is
    AND  L                         ; a power
    OR   D                         ; of two.
    JR   NZ,.GENERAL               ; It is not.
.DOUBLE:                       ; HL is a power of two.
    SRL  H                         ; Halve
    RR   L                         ; it.
    LD   A,H                       ; Was it one?
    OR   L                         ; Then
    RET  Z                         ; every doubling is written.
    CALL EM_OP                     ; ADD HL,HL
    DB   $29                       ; doubles the index.
    JR   .DOUBLE                   ; Until the stride is one.
.GENERAL:                      ; Shift and add.
    CALL EM_SEQ                    ; LD D,H, LD E,L, LD HL,0:
    DB   5,$54,$5D,$21,0,0         ; DE is the index, HL the product.
.BIT:                          ; HL is the stride's bits left.
    SRL  H                         ; The lowest
    RR   L                         ; into carry.
    LD   A,$19                     ; ADD HL,DE
    CALL C,EM_BYTE                 ; when it is set.
    LD   A,H                       ; Any bits left?
    OR   L                         ; Zero when none.
    RET  Z                         ; The product is in HL.
    CALL EM_SEQ                    ; EX DE,HL, ADD HL,HL, EX DE,HL:
    DB   3,$EB,$29,$EB             ; DE doubles.
    JR   .BIT                      ; The next bit.

;@ROUTINE IN BC CLOBBERS A,BC,DE,HL,CARRY,ZERO,SIGN,PARITY,HALFCARRY
; Zero the BC bytes of a local at the frame place in hand (zeroFrame):
; four or fewer one at a time (ixStoreImm); more with LD (HL),0 at its
; address, then LD D,H, LD E,L, INC DE, LD BC,size-1, LDIR.

GA_ZERO:                       ; BC is the size.
    LD   A,B                       ; Four bytes
    OR   A                         ; or fewer?
    JR   NZ,.MANY                  ; More.
    LD   A,C                       ; The size
    CP   5                         ; is below five:
    JR   NC,.MANY                  ; no, more.
    LD   B,C                       ; B bytes
    LD   HL,(RO_PADD)              ; from the local's offset
    JP   GX_FZERO                  ; are zeroed; return.
.MANY:                         ; More than four bytes.
    DEC  BC                        ; The first is zeroed alone.
    PUSH BC                        ; Keep the rest's count.
    CALL GA_ADDR                   ; The local's address,
    CALL EM_SEQ                    ; then LD (HL),0, LD D,H, LD E,L, INC DE:
    DB   5,$36,0,$54,$5D,$13       ; each byte copies the one before.
    POP  HL                        ; The rest's count.
    JR   GA_LDIR                   ; LD BC,count, LDIR; return.

;@ROUTINE IN BC CLOBBERS A,BC,DE,HL,CARRY,ZERO,SIGN,PARITY,HALFCARRY
; Store the BC bytes staged in AG_IBUF into a local at the frame place in
; hand, one LD (IX+d),n each, near or far (storeBytesToFrame).

GA_FILL:                       ; BC is the size.
    LD   HL,(RO_PADD)              ; The local's first byte.
    LD   DE,AG_IBUF                ; The staged bytes.
.BYTE:                         ; BC bytes remain.
    LD   A,(DE)                    ; The next byte
    LD   (GX_IMMV),A               ; is the immediate.
    PUSH BC                        ; Keep the count,
    PUSH DE                        ; the source
    PUSH HL                        ; and the offset.
    LD   DE,GX_DSTN                ; LD (IX+d),n.
    CALL GX_FACC                   ; Store this byte.
    POP  HL                        ; The offset
    INC  HL                        ; of the next byte,
    POP  DE                        ; and
    INC  DE                        ; its source.
    POP  BC                        ; One byte
    DEC  BC                        ; fewer.
    LD   A,B                       ; Any left?
    OR   C                         ; Zero when none.
    JR   NZ,.BYTE                  ; Store the next.
    RET                            ; The local holds its initializer.

;@ROUTINE IN BC CLOBBERS A,BC,DE,HL,CARRY,ZERO,SIGN,PARITY,HALFCARRY
; Copy the BC bytes at the address in HL into a local at the frame place
; in hand (copyToFrame): PUSH HL, the local's address, EX DE,HL, POP HL,
; LD BC,size, LDIR.

GA_COPY:                       ; BC is the size; the source is in HL.
    PUSH BC                        ; Keep the size.
    CALL GX_PUSHW                  ; PUSH HL: the source waits,
    CALL GA_ADDR                   ; while the local is addressed.
    CALL GA_SWAP                   ; DE is the local, HL the source.
    POP  HL                        ; The size.

;@ROUTINE IN HL CLOBBERS A,B,CARRY,ZERO,SIGN,PARITY,HALFCARRY
; Append LD BC,n and LDIR: copy n bytes from HL to DE at run time.

GA_LDIR:                       ; HL is the count.
    CALL EM_OP                     ; LD BC,n:
    DB   $01                       ; the opcode,
    CALL EM_WORD                   ; and n.
    CALL EM_SEQX                   ; LDIR.
    DB   2,$ED,$B0                 ; Append it.

;@ROUTINE IN B CLOBBERS A,BC,DE,HL,CARRY,ZERO,SIGN,PARITY,HALFCARRY
; Append LD HL,literal for the string literal just read (TK_PTR, TK_LEN),
; which occupies B bytes after the routine's need word: an operand naming
; the routine itself, its addend written when the literal is placed
; (GA_LITS). In discarded code nothing is written and no literal is made,
; as the reference discards it. The literal is an entry of the blob's log
; (BL_TLIT) after its operand's reference: its quote, its length and its
; size.

GA_LIT:                        ; B is the literal's size.
    CALL EM_OP                     ; LD HL,nn.
    DB   $21                       ; The opcode.
    CALL EM_QUIET                  ; Is the code discarded?
    RET  NZ                        ; Then so is the literal.
    PUSH BC                        ; Keep the size.
    LD   DE,EM_NONE                ; The routine itself, a placeholder
    CALL EM_SELF                   ; addend, the log's last entry;
    LD   A,BL_TLIT                 ; then the literal's,
    CALL BL_LOG                    ; after it:
    LD   DE,(TK_PTR)               ; the opening quote's
    CALL BL_PUTD                   ; address,
    LD   A,(TK_LEN)                ; the decoded
    LD   (HL),A                    ; length,
    INC  HL                        ; then
    POP  BC                        ; the size
    LD   (HL),B                    ; it occupies.
    RET                            ; Placed when the routine closes.

;@ROUTINE CLOBBERS A,BC,DE,HL,CARRY,ZERO,SIGN,PARITY,HALFCARRY
; Place the routine's literals after its need word, in the order they were
; made: each one's offset into the addend word of its operand, then its
; length byte, its characters decoded from the source (AG_CHAR) and zeros
; to its size.

GA_LITS:                       ; The need word is written.
    LD   HL,(NH_PTR)               ; From the log's first entry,
.NEXT:                         ; HL is an entry, or the heap.
    CALL BL_NEXT                   ; the next:
    RET  C                         ; none, and every literal is placed;
    CP   BL_TLIT                   ; any but a literal's
    JR   NZ,.NEXT                  ; passed over.
    PUSH HL                        ; A literal's, kept.
    LD   DE,BL_ELEN+5              ; Its operand's addend word,
    ADD  HL,DE                     ; in the entry before,
    LD   DE,(BL_LEN)               ; takes the offset
    LD   (HL),E                    ; where the
    INC  HL                        ; literal
    LD   (HL),D                    ; begins.
    POP  HL                        ; The entry:
    PUSH HL                        ; (kept)
    INC  HL                        ; DE is
    CALL WD_GET                    ; the opening quote, C
    LD   C,(HL)                    ; the length,
    INC  HL                        ; B
    LD   B,(HL)                    ; the size.
    LD   A,C                       ; The length byte
    CALL EM_BYTE                   ; first.
    DEC  B                         ; One fewer to come.
    EX   DE,HL                     ; HL is the quote.
    INC  HL                        ; The first character.
.CHAR:                         ; C characters remain.
    LD   A,C                       ; Any left?
    OR   A                         ; Zero when none.
    JR   Z,.ZERO                   ; Then the zeros.
    CALL AG_CHAR                   ; A is the next, decoded.
    CALL EM_BYTE                   ; Append it.
    DEC  B                         ; One fewer to come,
    DEC  C                         ; and one fewer character.
    JR   .CHAR                     ; The next.
.ZERO:                         ; B zeros remain.
    XOR  A                         ; Zero.
    CALL EM_BYTE                   ; Append it.
    DJNZ .ZERO                     ; At least the terminator.
    POP  HL                        ; The entry;
    JR   .NEXT                     ; the next literal.
