; Canonical operating-layer runtime source, private ABI, link-rule, vector and
; helper-layout identity. The same identity may link to different resolved
; bytes when the validated target addresses differ.
RT_IDENT EQU  $0004
RT_SIZE EQU  364

RT_VECS EQU  11
RT_VLEN EQU  RT_VECS*3
RT_SLEN EQU  37
RT_ORUN EQU  0
RT_OLIM EQU  7
; Banked targets use RT_SLOT as the selected-bank byte. The activation and
; far-return arenas retain caller-bank and return-address slots at depth-1.
; General source calls do not use the legacy scalar carrier in this mode.
RT_OBANK EQU  8

RT_PUSH EQU  0
RT_POP EQU  23
RT_CLAIM EQU  43
RT_FREE EQU  68
RT_IDXOK EQU  77
RT_LENOK EQU  85
RT_CHROK EQU  95
RT_RNGOK EQU  115
RT_BSS EQU  160
RT_MUL8 EQU  174
RT_MUL16 EQU  182
RT_DIV16 EQU  228
RT_MOD16 EQU  236
RT_CMP16 EQU  289
