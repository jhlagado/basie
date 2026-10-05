; Compact target descriptor retained by pointer across source parsing. The
; part-bank array remains adapter-owned and stable for the compilation.
; The descriptor itself belongs to the operating adapter and remains stable.

TG_DRT EQU  0                      ; word
TG_DIMG EQU  2                     ; word
TG_DICAP EQU  4                    ; word
TG_DRAM EQU  6                     ; word
TG_DRCAP EQU  8                    ; word
TG_DFLAG EQU  10                   ; byte
TG_DBCNT EQU  11                   ; byte
TG_DEB EQU  12                     ; byte
TG_DPART EQU  13                   ; word
TG_DSIZE EQU  15
TG_FSP EQU  1
TG_STACK EQU  3840

; Target-only parse-time aggregate-constant lengths reuse dead post-fixup
; workspace at the same addresses as the historical segmented proof fields.
; They do not depend on generated-image publication metadata.
TG_ROTAB EQU  GC_FLIM+2
TG_ROLIM EQU  TG_ROTAB+2*TG_BCAP
TG_BTAB EQU  GC_FLIM+16
TG_BLEN EQU  4
TG_BPTR EQU  0                     ; word
TG_BLEFT EQU  2                    ; word
TG_BLIM EQU  TG_BTAB+TG_BLEN*TG_BCAP

TG_DESC EQU  SRC_WEND              ; word
TG_WEND EQU  TG_DESC+2

; Parsing has completed before these values become live. They reuse the dead
; LL(1) parser stack beginning at TG_WEND.
TG_LBASE EQU  TG_WEND
TG_OBANK EQU  TG_LBASE+$00
TG_IMAGE EQU  TG_LBASE+$01         ; word
TG_ICAP EQU  TG_LBASE+$03          ; word
TG_RT EQU  TG_LBASE+$05            ; word
TG_RO EQU  TG_LBASE+$07            ; word
TG_ROLEN EQU  TG_LBASE+$09         ; word
TG_CODE EQU  TG_LBASE+$0B          ; word
TG_CLEN EQU  TG_LBASE+$0D          ; word
TG_CCAP EQU  TG_LBASE+$0F          ; word
; During lowering these flat-publication fields are otherwise dead and retain
; the selected bank's aggregate-constant bounds. Banked MAP publication uses
; the per-bank tables, so the overlay does not destroy required state.
TG_ROCAP EQU  TG_CLEN
TG_ROPOS EQU  TG_CCAP
TG_RW EQU  TG_LBASE+$11            ; word
TG_RCAP EQU  TG_LBASE+$13          ; word
TG_BSS EQU  TG_LBASE+$15           ; word
TG_LMODE EQU  TG_LBASE+$17
TG_SMODE EQU  TG_LBASE+$18
TG_ILEN EQU  TG_LBASE+$19          ; word
TG_TERM EQU  TG_LBASE+$1B          ; word
TG_CBASE EQU  TG_LBASE+$1D
TG_CRT EQU  TG_CBASE+$00           ; word
TG_CRAM EQU  TG_CBASE+$02          ; word
TG_CRCAP EQU  TG_CBASE+$04         ; word
TG_CRUN EQU  TG_CBASE+$06          ; word
TG_CVEC EQU  TG_CBASE+$08          ; word
TG_CDATA EQU  TG_CBASE+$0A         ; word
TG_CDCAP EQU  TG_CBASE+$0C         ; word
TG_CRO EQU  TG_CBASE+$0E           ; word
TG_COCAP EQU  TG_CBASE+$10         ; word
TG_CSIZE EQU  $12
; Finalization begins only after startup/code emission and any loaded-mode
; provider request. The complete map therefore reuses dead startup, terminal,
; and runtime-link-context storage without increasing compiler workspace.
TG_MAP EQU  TG_ILEN
TG_MEB EQU  TG_MAP+$00
TG_MEXEC EQU  TG_MAP+$01           ; word
TG_MUSED EQU  TG_MAP+$03           ; word
TG_MRO EQU  TG_MAP+$05             ; word
TG_MRLEN EQU  TG_MAP+$07           ; word
TG_MCODE EQU  TG_MAP+$09           ; word
TG_MCLEN EQU  TG_MAP+$0B           ; word
TG_MRAM EQU  TG_MAP+$0D            ; word
TG_MRCAP EQU  TG_MAP+$0F           ; word
TG_MVEC EQU  TG_MAP+$11            ; word
TG_MVLEN EQU  TG_MAP+$13           ; word
TG_MINIT EQU  TG_MAP+$15           ; word
TG_MILEN EQU  TG_MAP+$17           ; word
TG_MBSS EQU  TG_MAP+$19            ; word
TG_MBLEN EQU  TG_MAP+$1B           ; word
TG_MSLEN EQU  TG_MAP+$1D           ; word
TG_MDB EQU  TG_MAP+$1F
TG_MDATA EQU  TG_MAP+$20           ; word
TG_MDLEN EQU  TG_MAP+$22           ; word
TG_MAGG EQU  TG_MAP+$24            ; word
TG_MALEN EQU  TG_MAP+$26           ; word
TG_MSIZE EQU  $28
TG_LEND EQU  TG_MAP+TG_MSIZE
; The retained descriptor bytes remain live during both parsing and lowering,
; so they follow the shared 64-byte parser-stack/post-parse-layout overlay.
TG_BCNT EQU  TG_LEND               ; byte
TG_EBANK EQU  TG_BCNT+1            ; byte
; The production compiler retains the caller's hardware stack pointer across
; parsing and replaces it with an output-abort continuation during generation.
; Its lifetime spans both sides of the parser-stack/target-layout overlay.
PR_SP EQU  TG_EBANK+1              ; word
TG_END EQU  PR_SP+2

DG_CFG EQU  95
DG_IMAGE EQU  96
DG_OUT EQU  97

TG_LLOAD EQU  0
TG_LROM EQU  1
TG_OFF EQU  $FF
