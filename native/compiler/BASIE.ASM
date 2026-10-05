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
;  A compilation is one pass. The parser (PARSER, the LL(1) engine with
;  its grammar and actions, and the expression, control, aggregate and
;  routine parsers) reads the source parts through the tokenizer, and the
;  code generators (GEN*) write each routine and top-level declaration as
;  a blob while it is parsed, through the emitter (EMIT) and the blob
;  writer (BLOB, OUT), in the reference compiler's templates (design
;  decision D45). Constructs not yet generated this way are refused at
;  the transcript (TRANSCR).
;
;  The first three files define only equates: the memory map, then the
;  workspace layout and the constants every module shares. HEAD.ASM places
;  the first byte at $0100. The shell comes last, so its code and data end
;  the image; KEYWORDS.ASM holds the compiler's immutable tables just
;  before it.

%INCLUDE "MEMORY.ASM"          ; Memory map: image, workspace, source.
%INCLUDE "STATE.ASM"           ; Parser workspace and shared constants.
%INCLUDE "CALLWORK.ASM"        ; Routines, calls, source parts, LL stack.
%INCLUDE "HEAD.ASM"            ; The jump to the shell at $0100.
%INCLUDE "SOURCE.ASM"          ; Source parts, read byte by byte.
%INCLUDE "TOKEN.ASM"           ; The tokenizer.
%INCLUDE "TRANSCR.ASM"         ; Refusal of constructs not yet generated.
%INCLUDE "SYMBOLS.ASM"         ; The symbol table.
%INCLUDE "PARSER.ASM"          ; The compile entry and parse driver.
%INCLUDE "EXPR.ASM"            ; Expressions: names, operand stack, reduction.
%INCLUDE "EXTERM.ASM"          ; Expressions: primaries and unary operators.
%INCLUDE "EXOPER.ASM"          ; Expressions: binary operators and entries.
%INCLUDE "CONTROL.ASM"         ; The structured control parser.
%INCLUDE "AGGR.ASM"            ; Records, arrays, strings and constants.
%INCLUDE "ROUTINES.ASM"        ; Routine names, parameters, compile entry.
%INCLUDE "CALLS.ASM"           ; Calls, services and aggregate paths.
%INCLUDE "LL1.ASM"             ; The LL(1) engine.
%INCLUDE "GRAMMAR.ASM"         ; The generated grammar tables.
%INCLUDE "ACTIONS.ASM"         ; Actions: islands, types and declarations.
%INCLUDE "ACTSUB.ASM"          ; Actions: routines, failure and handlers.
%INCLUDE "ACTSTMT.ASM"         ; Actions: locals, statements and flow.
%INCLUDE "OUT.ASM"             ; Output streams.
%INCLUDE "BLOB.ASM"            ; The blob writer.
%INCLUDE "EMIT.ASM"            ; Emitter primitives and labels.
%INCLUDE "GENCALL.ASM"         ; Routines, declarations and limits.
%INCLUDE "KEYWORDS.ASM"        ; Keyword and punctuation tables.
%INCLUDE "SHELL.ASM"           ; The CP/M shell, last in the image.
