;==========================================================================
;  Nucleus runtime state
;==========================================================================
;
;  The layout of the runtime's writable state, which follows its jump
;  vectors in the target's writable memory (RTIDENT.ASM). Generated code
;  reads and writes these bytes by absolute address: a generator passes
;  NAME-RT_BASE to TG_VAR, which adds the state base of the linked target,
;  so RT_BASE's own value is only an origin for the offsets.
;
;    +$00 RT_RUN    run state: RT_OK or RT_TRAP once the program ends
;    +$01 RT_TNUM   trap number
;    +$02 RT_TSUB   routine that trapped
;    +$03 RT_TPOS   source offset of the trap (word)
;    +$05 RT_TERR   unhandled error code
;    +$06 RT_DEPTH  active routine count, checked by RT_CLAIM
;    +$07           activation limit, read only by the runtime
;    +$08           scalar slot, unused by this compiler
;    +$09 RT_ARENA  activation arena, RT_ACAP bytes
;    +$11 RT_SP     stack pointer saved before main allocates its frame
;    +$13 RT_IX     frame pointer saved with it
;    +$15           far-return arena, sixteen bytes, to RT_SLEN
;
;  The startup's terminal dispatch (TG_BOOT) and the trap sites (EM_TRAP,
;  EM_STOP, EM_STRAY) write the run state and trap record; GX_SAVE and
;  GX_RESET emit the saves and restores of RT_SP and RT_IX.

RT_BASE EQU  MM_XBASE          ; Origin of the offsets below.
RT_RUN EQU  RT_BASE+$00        ; Run state byte.
RT_TNUM EQU  RT_BASE+$01       ; Trap number byte.
RT_TSUB EQU  RT_BASE+$02       ; Trapping routine byte.
RT_TPOS EQU  RT_BASE+$03       ; Trap source offset word.
RT_TERR EQU  RT_BASE+$05       ; Unhandled error code byte.
RT_DEPTH EQU  RT_BASE+$06      ; Active routine count byte.
RT_ARENA EQU  RT_BASE+$09      ; Activation arena.
RT_ACAP EQU  8                 ; Bytes in the activation arena.
RT_SP EQU  RT_ARENA+RT_ACAP    ; Saved root stack pointer word.
RT_IX EQU  RT_SP+2             ; Saved root frame pointer word.

RT_OK EQU  2                   ; Run state: the program succeeded.
RT_TRAP EQU  3                 ; Run state: the program trapped.
