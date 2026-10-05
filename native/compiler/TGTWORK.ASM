;==========================================================================
;  Target workspace and descriptor
;==========================================================================
;
;  The last part of the compiler workspace, from SRC_WEND to TG_END, the
;  layout of the target descriptor and the target constants. Nearly all of
;  it serves TARGET.ASM's placed output, which writes the program as a Z80
;  image at its run addresses through the shell's PUB_ sinks. BASIE.COM's
;  sinks discard that output until blob output replaces TARGET.ASM (step
;  65.4). Offsets are from MM_WBASE ($4800).
;
;    Offset  Size  Block
;    +$462      8  TG_ROTAB, in STATE.ASM's dead segment block (GC_FLIM+2)
;    +$470     16  TG_BTAB, in the same block (GC_FLIM+16)
;    +$DD2      2  TG_DESC
;    +$DD4     65  parsing: the LL(1) stack (LL_DEPTH, LL_STACK)
;                  emit phase: the target layout (TG_LBASE..TG_LEND)
;    +$E15      2  TG_BCNT, TG_EBANK
;    +$E17      2  PR_SP
;    +$E19         TG_END = LL_WEND, the end of the compiler workspace,
;                  3,609 bytes, which build.ts checks against SH_WBEG
;
;  The shell supplies the target descriptor (SH_DESC) and PR_BUILD keeps
;  its address in TG_DESC. The descriptor and its part-bank array stay in
;  the shell's memory for the whole compilation:
;    +0  word  TG_DRT    runtime identity, which must be RT_IDENT
;    +2  word  TG_DIMG   base address of the output image
;    +4  word  TG_DICAP  bytes the image may hold
;    +6  word  TG_DRAM   base of the writable region
;    +8  word  TG_DRCAP  bytes in the writable region
;    +10 byte  TG_DFLAG  stack mode: 0 inherits SP, TG_FSP sets it
;    +11 byte  TG_DBCNT  number of banks, 1 to TG_BCAP
;    +12 byte  TG_DEB    bank that holds the entry and the startup
;    +13 word  TG_DPART  address of one byte per source part: its bank
;  PR_BUILD validates the bank fields before parsing and copies the bank
;  count and entry bank to TG_BCNT and TG_EBANK; TG_OPEN validates the rest
;  and copies it into the layout. A target whose writable region lies
;  inside its image has a loaded layout: the program runs where it is
;  placed. One whose regions are apart has a ROM layout (TG_LROM): the
;  startup copies the writable image into RAM. SH_DESC describes one bank
;  with a ROM layout.
;
;  Bank fields matter only when the descriptor names several banks. The
;  paths that use them (TG_OPENB, TG_PICK, TG_SHUTB and GA_PLACE, chosen
;  when TG_BCNT is not 1) are still assembled, though SH_DESC never selects
;  them. TG_ROTAB is a word per bank: the aggregate-constant bytes placed
;  in that bank so far. PR_BUILD clears it, AC_ROCMT advances it as each
;  constant is declared (giving the constant its offset in its bank), and
;  in the emit phase TG_PICK and TG_SHUTB read it. TG_BTAB holds a record
;  per bank (TG_BLEN bytes), set by TG_OPENB and swapped by TG_SAVE and
;  TG_PICK as output moves between banks:
;    +0 word  TG_BPTR   output pointer saved while the bank is deselected
;    +2 word  TG_BLEFT  capacity left in the bank
;  Both tables sit in STATE.ASM's segment block from GC_FLIM, which no code
;  reads any longer.
;
;  Three overlays share bytes between fields that are never live together:
;
;  The target layout (TG_LBASE..TG_LEND) lies over the LL(1) stack.
;  LL_PARSE owns the stack until parsing ends, and nothing reads a layout
;  field before GA_BUILD calls TG_OPEN, whose first store is TG_OBANK.
;
;  TG_ROCAP and TG_ROPOS, the constant region that generated checks use,
;  lie over TG_CLEN and TG_CCAP. GA_BUILD reads TG_CCAP before it sets
;  TG_ROPOS, and TG_SHUT writes TG_CLEN only after code generation, when
;  the constant region is no longer needed. The banked paths set the pair
;  in TG_PICK and never use TG_CLEN or TG_CCAP.
;
;  The output map (TG_MAP) lies over TG_ILEN, TG_TERM and the link context
;  (TG_CBASE). TG_SHUT builds it after code generation and after the last
;  use of the context by TG_RAM; it reads TG_CRO before it writes TG_MVEC
;  and TG_MVLEN over it.
;
;  TG_BCNT, TG_EBANK and PR_SP follow the shared bytes because they live
;  through both phases. TARGET.ASM writes the layout, except that GENAGGR
;  sets TG_CODE, TG_ROCAP and TG_ROPOS for a one-bank target and GENCTRL
;  moves TG_OBANK while it resolves fixups. EMIT, GENCALL and GENCTRL read
;  TG_OBANK, TG_EBANK, TG_TERM, TG_BSS and TG_CDATA as they emit code.

TG_DRT EQU  0                  ; Word: runtime identity, which must be RT_IDENT.
TG_DIMG EQU  2                 ; Word: base address of the output image.
TG_DICAP EQU  4                ; Word: bytes the image may hold.
TG_DRAM EQU  6                 ; Word: base of the writable region.
TG_DRCAP EQU  8                ; Word: bytes in the writable region.
TG_DFLAG EQU  10               ; Byte: stack mode, 0 or TG_FSP.
TG_DBCNT EQU  11               ; Byte: number of banks, 1 to TG_BCAP.
TG_DEB EQU  12                 ; Byte: bank that holds the entry and the startup.
TG_DPART EQU  13               ; Word: address of the part-bank array.
TG_FSP EQU  1                  ; Stack mode: the startup sets SP to the region's end.
TG_STACK EQU  3840             ; Stack bytes the writable region must leave free.

; Per-bank tables in STATE.ASM's dead segment block.
TG_ROTAB EQU  GC_FLIM+2        ; Words: aggregate-constant bytes in each bank.
TG_ROLIM EQU  TG_ROTAB+2*TG_BCAP ; Exclusive end of TG_ROTAB; PR_BUILD clears to here.
TG_BTAB EQU  GC_FLIM+16        ; Output cursors: TG_BCAP records of TG_BLEN bytes.
TG_BLEN EQU  4                 ; Bytes in one TG_BTAB record.
TG_BPTR EQU  0                 ; Word: output pointer saved for the bank.
TG_BLEFT EQU  2                ; Word: capacity left in the bank.
TG_BLIM EQU  TG_BTAB+TG_BLEN*TG_BCAP ; Exclusive end of TG_BTAB.

TG_DESC EQU  SRC_WEND          ; Word: address of the target descriptor (PR_BUILD).
TG_WEND EQU  TG_DESC+2         ; End of the fixed fields; LL_DEPTH starts here.

; Emit phase: the target layout, over the LL(1) stack, which is dead once
; parsing has finished.
TG_LBASE EQU  TG_WEND          ; First byte of the target layout.
TG_OBANK EQU  TG_LBASE+$00     ; Byte: bank receiving output, TG_OFF when closed.
TG_IMAGE EQU  TG_LBASE+$01     ; Word: image base, from TG_DIMG.
TG_ICAP EQU  TG_LBASE+$03      ; Word: image capacity, from TG_DICAP.
TG_RT EQU  TG_LBASE+$05        ; Word: address of the linked runtime.
TG_RO EQU  TG_LBASE+$07        ; Word: read-only section, after runtime and startup.
TG_ROLEN EQU  TG_LBASE+$09     ; Word: its length, with the writable image in ROM.
TG_CODE EQU  TG_LBASE+$0B      ; Word: address where generated code begins.
TG_CLEN EQU  TG_LBASE+$0D      ; Word: generated code length (TG_SHUT).
TG_CCAP EQU  TG_LBASE+$0F      ; Word: code capacity, short of RAM when loaded.
; While code is generated these two hold the bounds of the constant region
; of the bank receiving output.
TG_ROCAP EQU  TG_CLEN          ; Word: length of the constant region.
TG_ROPOS EQU  TG_CCAP          ; Word: run address of the constant region.
TG_RW EQU  TG_LBASE+$11        ; Word: writable region base, from TG_DRAM.
TG_RCAP EQU  TG_LBASE+$13      ; Word: writable region capacity, from TG_DRCAP.
TG_BSS EQU  TG_LBASE+$15       ; Word: run address of zeroed data, after the data.
TG_LMODE EQU  TG_LBASE+$17     ; Byte: layout, zero for loaded or TG_LROM.
TG_SMODE EQU  TG_LBASE+$18     ; Byte: stack mode, from TG_DFLAG.
TG_ILEN EQU  TG_LBASE+$19      ; Word: startup length, sized before it is emitted.
TG_TERM EQU  TG_LBASE+$1B      ; Word: address of the startup's terminal dispatch.
TG_CBASE EQU  TG_LBASE+$1D     ; Link context for PUB_RT and PUB_INIT (TG_SETUP).
TG_CRT EQU  TG_CBASE+$00       ; Word: runtime base.
TG_CRAM EQU  TG_CBASE+$02      ; Word: writable region base.
TG_CRCAP EQU  TG_CBASE+$04     ; Word: writable region capacity.
TG_CRUN EQU  TG_CBASE+$06      ; Word: runtime state base, after the vectors.
TG_CVEC EQU  TG_CBASE+$08      ; Word: RAM vector base, the region's start.
TG_CDATA EQU  TG_CBASE+$0A     ; Word: initialised data base, after the state.
TG_CDCAP EQU  TG_CBASE+$0C     ; Word: bytes of data and zeroed data.
TG_CRO EQU  TG_CBASE+$0E       ; Word: constant region run address; zero if banked.
TG_COCAP EQU  TG_CBASE+$10     ; Word: constant region length; zero if banked.
; TG_SHUT builds the map once the startup length, the terminal address and
; the link context are dead, so it lies over them.
TG_MAP EQU  TG_ILEN            ; Output map for PUB_FLAT (TG_SHUT).
TG_MEB EQU  TG_MAP+$00         ; Byte: entry bank, zero.
TG_MEXEC EQU  TG_MAP+$01       ; Word: entry address, the image base.
TG_MUSED EQU  TG_MAP+$03       ; Word: image bytes used.
TG_MRO EQU  TG_MAP+$05         ; Word: read-only section base, zero if empty.
TG_MRLEN EQU  TG_MAP+$07       ; Word: read-only section length.
TG_MCODE EQU  TG_MAP+$09       ; Word: code base.
TG_MCLEN EQU  TG_MAP+$0B       ; Word: code length.
TG_MRAM EQU  TG_MAP+$0D        ; Word: writable region base.
TG_MRCAP EQU  TG_MAP+$0F       ; Word: writable region capacity.
TG_MVEC EQU  TG_MAP+$11        ; Word: RAM vector base.
TG_MVLEN EQU  TG_MAP+$13       ; Word: RAM vector length.
TG_MINIT EQU  TG_MAP+$15       ; Word: run address of the initialised image.
TG_MILEN EQU  TG_MAP+$17       ; Word: its length: vectors, state and data.
TG_MBSS EQU  TG_MAP+$19        ; Word: zeroed data base.
TG_MBLEN EQU  TG_MAP+$1B       ; Word: zeroed data length.
TG_MSLEN EQU  TG_MAP+$1D       ; Word: stack requirement, TG_STACK.
TG_MDB EQU  TG_MAP+$1F         ; Byte: bank of the initialised image's copy, zero.
TG_MDATA EQU  TG_MAP+$20       ; Word: where that copy is placed in the image.
TG_MDLEN EQU  TG_MAP+$22       ; Word: its length.
TG_MAGG EQU  TG_MAP+$24        ; Word: aggregate-constant base, zero if none.
TG_MALEN EQU  TG_MAP+$26       ; Word: aggregate-constant length.
TG_MSIZE EQU  $28              ; Bytes in the map.
TG_LEND EQU  TG_MAP+TG_MSIZE   ; End of the layout and of the LL(1) stack.
; These live through parsing and code generation, so they follow the bytes
; that the LL(1) stack and the layout share.
TG_BCNT EQU  TG_LEND           ; Byte: number of banks, validated (PR_BUILD).
TG_EBANK EQU  TG_BCNT+1        ; Byte: entry bank, validated (PR_BUILD).
; PR_BUILD saves the caller's SP here for parsing, so that a diagnostic
; (DG_ISSUE) returns straight to the caller. For code generation it saves
; SP with TG_ABORT pushed, so a diagnostic first abandons the output.
PR_SP EQU  TG_EBANK+1          ; Word: SP that DG_ISSUE restores.
TG_END EQU  PR_SP+2            ; End of the compiler workspace (LL_WEND).

DG_CFG EQU  95                 ; Diagnostic: invalid descriptor or bank use.
DG_IMAGE EQU  96               ; Diagnostic: the program does not fit the target.
DG_OUT EQU  97                 ; Diagnostic: an output sink failed.

TG_LROM EQU  1                 ; TG_LMODE of a ROM layout: image and RAM apart.
TG_OFF EQU  $FF                ; TG_OBANK when no bank receives output.
