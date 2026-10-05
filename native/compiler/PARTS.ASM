;==========================================================================
;  Source parts and streams
;==========================================================================
;
;  The start of a build, after the command line: the START overlay of
;  BASIE.OVL (OVERLAY.ASM), with LIBRARY.ASM and PARTNAME.ASM. SH_BEGIN,
;  at the overlay area's start, checks the library (LB_CHECK), loads each
;  part named on the command line into memory above the compiler's
;  workspace, chooses the compilation stamp (LB_STAMP), opens the streams
;  NAME.$DR, $BY, $LN and $NM on the spool drive with the first part's
;  name (toolchain §3.2) and names each part in the line stream, and
;  returns to the shell, which compiles them.
;
;  Principal entry:
;    SH_BEGIN  everything before the compilation, at OV_AREA
;
;  Failure, which does not return: a part not found (L-MISSING), one CP/M
;  could not read (L-IO) and source too large for memory (capacity), each
;  through the DIAG overlay, which replaces this one.

;@ROUTINE CLOBBERS A,BC,DE,HL,IX,IY,CARRY,ZERO,SIGN,PARITY,HALFCARRY
; Check the library, load the parts, choose the stamp, open the streams
; and name the parts in the line stream.

SH_BEGIN:                      ; At OV_AREA.
    CALL LB_CHECK                  ; The library must suit the compiler.
    XOR  A                         ; Load the parts in order,
.LOADS:                        ; A is the next one's index.
    LD   (SH_PIDX),A               ; It is being loaded.
    CALL SH_LOAD                   ; Load it and add its descriptor.
    LD   A,(SH_PIDX)               ; The next part.
    INC  A                         ; Its index.
    LD   HL,SH_PCNT                ; Is there one?
    CP   (HL)                      ; The count ends them.
    JR   C,.LOADS                  ; Load it.
    CALL LB_STAMP                  ; Choose the compilation stamp.
    LD   C,BL_LNOUT                ; By default a line stream and no names.
    LD   A,(CL_SEEN+CL_IN)         ; Option N:
    OR   A                         ; no line stream.
    JR   Z,.LINES                  ; Not given.
    LD   C,0                       ; None.
.LINES:                        ; C holds the line stream's flag.
    LD   HL,CL_SEEN+CL_IM          ; Option M
    LD   A,(CL_SEEN+CL_IY)         ; or Y
    OR   (HL)                      ; wants
    JR   Z,.NAMES                  ; the name stream.
    SET  1,C                       ; Set BL_NMOUT.
.NAMES:                        ; C holds the stream flags.
    LD   A,(CL_SEEN+CL_IK)         ; Option K:
    OR   A                         ; keep the streams
    JR   Z,.KEPT                   ; after a failure.
    SET  6,C                       ; Set SH_KEEP.
.KEPT:                         ; C is complete.
    LD   A,C                       ; The streams the options want.
    LD   HL,SH_HEAD                ; The directory's header,
    LD   DE,SH_SNAME               ; and the streams' drive and name.
    CALL BL_OPEN                   ; Open the streams.
    XOR  A                         ; Name each part in the line stream,
.PARTS:                        ; A is the next part's index.
    PUSH AF                        ; Keep it.
    CALL SH_TYPED                  ; HL is its name as NAME.TYP, B the length.
    POP  AF                        ; A is the index.
    PUSH AF                        ; Keep it.
    CALL BL_PART                   ; Write its part record.
    POP  AF                        ; The index again.
    INC  A                         ; The next part.
    LD   HL,SH_PCNT                ; Is there one?
    CP   (HL)                      ; The count ends them.
    JR   C,.PARTS                  ; Name it.
    RET                            ; The streams are open.

;@ROUTINE CLOBBERS A,BC,DE,HL,IX,IY,CARRY,ZERO,SIGN,PARITY,HALFCARRY
; Load part SH_PIDX, whose name CL_READ saved, after the parts already
; loaded: end it at its first $1A and append its descriptor. Errors leave
; by SH_MISS, SH_RERR and SH_LARGE.

SH_LOAD:                       ; SH_PIDX is the part's index.
    CALL SH_BLANK                  ; A clear FCB.
    LD   A,(SH_PIDX)               ; The part's saved name:
    CALL SH_PNAME                  ; HL is its drive, name and type.
    LD   DE,SH_FCB                 ; The FCB takes them.
    LD   BC,SH_SLOT                ; Twelve bytes.
    LDIR                           ; The FCB names the part.
    LD   DE,SH_FCB                 ; DE is the FCB for BDOS.
    LD   C,SH_OPEN                 ; Open the part for reading.
    CALL SH_BDOS                   ; A is $FF if the file is not on the disk.
    INC  A                         ; $FF becomes zero.
    JP   Z,SH_MISS                 ; Report the missing part by name.
    LD   HL,(SH_LOADP)             ; The part starts at the load point.
    LD   (SH_PBEG),HL              ; Keep its start for the trim and the descriptor.
.RECORD:                       ; SH_LOADP is where the next record goes.
    LD   HL,(SH_LOADP)             ; The load point may be up to one record past the
    LD   DE,-128                   ; limit before the read that finds the end of the
    ADD  HL,DE                     ; file, which writes nothing; HL is it less 128.
    EX   DE,HL                     ; DE is the load point less one record.
    CALL .ROOM                     ; Carry if even that is past the limit.
    JP   C,SH_LARGE                ; Records land at most 256 bytes past the limit, in
                                   ; the stack's reserve; .FOUND checks the true end.
    LD   DE,(SH_LOADP)             ; DE is the load point.
    LD   C,SH_DMA                  ; The record is read straight to it.
    CALL SH_BDOS                   ; Set the DMA address to DE.
    LD   DE,SH_FCB                 ; DE is the open part's FCB.
    LD   C,SH_READ                 ; Read its next record.
    CALL SH_BDOS                   ; A is zero if a record was read.
    OR   A                         ; Was one read?
    JR   Z,.ADVANCE                ; Yes: move past it.
    DEC  A                         ; Status 1 is the end of the file.
    JR   Z,.LOADED                 ; The part is complete.
    JP   SH_RERR                   ; Any other status is a read error (toolchain §6.2).
.ADVANCE:                      ; A record was read at SH_LOADP.
    LD   HL,(SH_LOADP)             ; Advance the load point past the record.
    LD   DE,128                    ; A record is 128 bytes.
    ADD  HL,DE                     ; HL is the next load point.
    LD   (SH_LOADP),HL             ; The next record goes there.
    JR   .RECORD                   ; Read until the end of the file.
.LOADED:                       ; The file is in memory from SH_PBEG to SH_LOADP.
    LD   HL,(SH_PBEG)              ; Scan from the part's start for its first $1A.
    LD   DE,(SH_LOADP)             ; DE is the end of the last record.
.TRIM:                         ; HL is the next byte to test, below or at DE.
    LD   A,L                       ; Has the scan reached DE?
    CP   E                         ; Compare the low bytes.
    JR   NZ,.BYTE                  ; They differ: test the byte at HL.
    LD   A,H                       ; Compare the high bytes.
    CP   D                         ; Equal means the end of the records.
    JR   Z,.FOUND                  ; A part without $1A ends there.
.BYTE:                         ; HL is inside the loaded records.
    LD   A,(HL)                    ; Read the next source byte.
    CP   $1A                       ; CP/M ends a text file with $1A in its last record.
    JR   Z,.FOUND                  ; The part ends at the first one.
    INC  HL                        ; Not yet: test the next byte.
    JR   .TRIM                     ; Continue the scan.
.FOUND:                        ; HL is the part's exclusive end.
    EX   DE,HL                     ; DE is the end.
    CALL .ROOM                     ; Carry if the part ends past the limit.
    JP   C,SH_LARGE                ; The part does not fit below the stack's reserve.
    LD   (SH_LOADP),DE             ; The next part loads here, over the $1A and padding.
    LD   A,(SH_PIDX)               ; Build the descriptor: id, start, end.
    LD   L,A                       ; L keeps this part's index.
    INC  A                         ; A is its 1-based id, which DG_PART reports.
    LD   H,0                       ; HL is the index.
    LD   B,H                       ; B is zero, the index's high byte.
    LD   C,L                       ; BC is the index, added back below.
    ADD  HL,HL                     ; HL = 2 * index.
    ADD  HL,HL                     ; HL = 4 * index.
    ADD  HL,BC                     ; HL = 5 * index, the descriptor's offset.
    LD   BC,SH_PARTS               ; BC is the table's base.
    ADD  HL,BC                     ; HL is this part's descriptor.
    LD   (HL),A                    ; Byte 0 is the id, which becomes SRC_ID.
    INC  HL                        ; Bytes 1 and 2 hold the start.
    LD   BC,(SH_PBEG)              ; BC is where the part began.
    LD   (HL),C                    ; Store the start's low byte.
    INC  HL                        ; Move to its high byte.
    LD   (HL),B                    ; Store the start's high byte.
    INC  HL                        ; Bytes 3 and 4 hold the exclusive end.
    LD   (HL),E                    ; Store the end's low byte.
    INC  HL                        ; Move to its high byte.
    LD   (HL),D                    ; Store the end's high byte.
    RET                            ; The part is loaded and described.

;@ROUTINE IN DE OUT CARRY CLOBBERS HL,ZERO,SIGN,PARITY,HALFCARRY
; Carry if the address DE is past SH_LIMIT, the first byte the source may
; not use.

.ROOM:                         ; DE is an address in the source area.
    LD   HL,(SH_LIMIT)             ; HL is the limit.
    OR   A                         ; Clear carry for the subtraction.
    SBC  HL,DE                     ; Carry if DE is above it.
    RET                            ; The caller tests carry.

;@ROUTINE NORETURN
; Report that the part SH_LOAD failed to open is not on the disk: L-MISSING,
; its argument the part's name.

SH_MISS:                       ; SH_PIDX is the part.
    LD   HL,SH_NMISS               ; L-MISSING.
    JR   SH_NAMED                  ; Name the part in it.

;@ROUTINE NORETURN
; Report a part that CP/M could not read: L-IO, its argument the part's
; name, and a disk error's return code.

SH_RERR:                       ; SH_LOAD had a read status other than 0 or 1.
    LD   A,SH_RDISK                ; A disk error's
    LD   (SH_RLOW),A               ; return code.
    LD   HL,SH_NIO                 ; L-IO.

;@ROUTINE IN HL NORETURN
; Report diagnostic HL with the name of the part being loaded as its
; argument, and fail.

SH_NAMED:                      ; HL is the message number.
    PUSH HL                        ; Keep it across the spelling.
    LD   A,(SH_PIDX)               ; The part being loaded.
    LD   DE,DG_ABUF                ; Its name, D:NAME.TYP,
    CALL SH_SPELL                  ; spelled there,
    LD   (DG_ARG1),HL              ; is argument 1.
    POP  HL                        ; The number.
    JP   MS_FAIL                   ; Print it and fail.

;@ROUTINE NORETURN
; Report a part whose next record would cross SH_LIMIT.

SH_LARGE:                      ; SH_LOAD found no room for a record.
    LD   A,DG_ROOM                 ; The source's capacity:
    JP   SH_OVER                   ; report it and fail.

