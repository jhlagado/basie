;==========================================================================
;  BASIE.COM: the native Basie compiler
;==========================================================================
;
;  The root of the compiler's ATOM source tree (design decision D44). It
;  holds no code of its own: it includes every module, and ATOM assembles
;  each included file before its includer, so the include order below is
;  the order of the image. The compiler was forked from the Nucleus native
;  compiler and runs as a flat CP/M transient at $0100.
;
;  A compilation runs in three phases that never overlap. The parser
;  (PARSER, the LL(1) engine with its grammar and actions, and the
;  expression, control, aggregate and routine parsers) reads the source
;  parts through the tokenizer and appends operations to the semantic
;  transcript. The transcript is then closed and replayed through the
;  dispatch table into placed Z80 code by the code generators (GEN*),
;  which write through the emitter (EMIT) into placed output (TARGET).
;  Forward branches go to a global fixup table that is resolved at the end.
;  Because the phases are disjoint, the workspace overlays their state.
;
;  The first six files define only equates: the memory map, then the
;  workspace layout and the constants every module shares. HEAD.ASM places
;  the first byte at $0100. The shell comes last, so its code and data end
;  the image; KEYWORDS.ASM holds the compiler's immutable tables just
;  before it.

%INCLUDE "MEMORY.ASM"              ; Memory map: image, workspace, source.
%INCLUDE "STATE.ASM"               ; Parser workspace and shared constants.
%INCLUDE "CALLWORK.ASM"            ; Routine and call workspace, source parts.
%INCLUDE "TGTWORK.ASM"             ; Placed-output workspace and descriptor.
%INCLUDE "RTSTATE.ASM"             ; The Nucleus runtime's writable state.
%INCLUDE "RTIDENT.ASM"             ; The Nucleus runtime's identity.
%INCLUDE "HEAD.ASM"                ; The jump to the shell at $0100.
%INCLUDE "SOURCE.ASM"              ; Source parts, read byte by byte.
%INCLUDE "TOKEN.ASM"               ; The tokenizer.
%INCLUDE "TRANSCR.ASM"             ; The semantic transcript.
%INCLUDE "SYMBOLS.ASM"             ; The symbol table.
%INCLUDE "PARSER.ASM"              ; The compile entry and parse driver.
%INCLUDE "EXPR.ASM"                ; The expression parser.
%INCLUDE "CONTROL.ASM"             ; The structured control parser.
%INCLUDE "AGGR.ASM"                ; Records, arrays, strings and constants.
%INCLUDE "ROUTINES.ASM"            ; Routines, parameters, calls, services.
%INCLUDE "LL1.ASM"                 ; The LL(1) engine.
%INCLUDE "GRAMMAR.ASM"             ; The generated grammar tables.
%INCLUDE "ACTIONS.ASM"             ; The grammar's semantic actions.
%INCLUDE "EMIT.ASM"                ; Emitter primitives and fixups.
%INCLUDE "TARGET.ASM"              ; Placed output, until step 65.4.
%INCLUDE "GENEXPR.ASM"             ; Expression code generation.
%INCLUDE "GENCTRL.ASM"             ; Control code generation.
%INCLUDE "GENCALL.ASM"             ; Routine and call code generation.
%INCLUDE "GENTMPL.ASM"             ; Shared code templates.
%INCLUDE "GENAGGR.ASM"             ; Aggregate code and image publication.
%INCLUDE "KEYWORDS.ASM"            ; Keyword and punctuation tables.
%INCLUDE "SHELL.ASM"               ; The CP/M shell, last in the image.
