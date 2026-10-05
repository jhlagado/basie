;==========================================================================
;  Nucleus runtime identity
;==========================================================================
;
;  The forked compiler links its programs against the Nucleus runtime: a
;  fixed helper image of RT_SIZE bytes, followed in writable memory by a
;  table of RT_VECS three-byte jump vectors and RT_SLEN bytes of state.
;  RT_IDENT names one exact runtime source, private ABI and helper layout;
;  TG_OPEN refuses a target descriptor that names another, because every
;  offset below is valid only for this identity. The output adapter
;  (PUB_RT, PUB_INIT) supplies the helper and vector images themselves.
;
;  Generated code calls a helper as CALL base+offset (EM_HELP) and reaches a
;  vector as CALL or JP to its slot (EM_CALLV, EM_JUMPV). The vectors the
;  compiler uses are 6 (success), 7 (unhandled failure), 8 (trap) and 10
;  (far jump). Only the offsets the code generators call are kept here.
;  Basie's library replaces all of this at step 65.4, when helpers become
;  references that BLINK resolves.

RT_IDENT EQU  $0004            ; The one runtime identity accepted.
RT_SIZE EQU  364               ; Bytes in the linked helper image.

RT_VECS EQU  11                ; Jump vectors in writable memory.
RT_VLEN EQU  RT_VECS*3         ; Each vector is a three-byte JP.
RT_SLEN EQU  37                ; Writable state after the vectors.

; Helper entry offsets from the start of the linked helper image.

RT_CLAIM EQU  43               ; Claim an activation; carry when full.
RT_FREE EQU  68                ; Release an activation, keeping HL.
RT_IDXOK EQU  77               ; Check index DE below length BC.
RT_LENOK EQU  85               ; Check string HL against capacity C.
RT_CHROK EQU  95               ; Check index DE; HL = its byte's address.
RT_RNGOK EQU  115              ; Check an aggregate region's bounds.
RT_BSS EQU  160                ; Zero BC bytes at HL before main.
RT_MUL16 EQU  182              ; HL = HL*DE modulo 65536.
RT_DIV16 EQU  228              ; HL = HL/DE unsigned; carry if DE is zero.
RT_MOD16 EQU  236              ; HL = HL mod DE; carry if DE is zero.
RT_CMP16 EQU  289              ; HL = HL rel DE as 0/1; A is the relation.
