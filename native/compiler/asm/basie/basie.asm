; BASIE.COM: the forked compiler inside its CP/M shell (native compiler
; plan, 65.2). The module list is the shipping composition's
; (vertical-slice/flat-target-z80-slice-body.asm); the proof cases and
; their adapter are replaced by the shell.

DebugHooks .equ 0
            .include "basie-memory-map.asmi"
SegmentedOutput       .equ 1
TargetStreamingOutput .equ 1
            .include "../vertical-slice/loop-compiler-state.asmi"
            .include "../vertical-slice/aggregate-call-state.asmi"
            .include "../vertical-slice/target-output-state.asmi"
            .include "../vertical-slice/loop-z80-state.asmi"
            .include "../vertical-slice/nucleus-runtime-identity.asmi"

            .org $0100
BasieImageStart:
            JP   BasieStart

            .org CompilerCoreBase
CompilerCodeStart:
LegacyCompilerSlices .equ 0
AggregateCallSlices  .equ 1
Stage7LL1            .equ 1
            .include "../vertical-slice/source-adapter.asm"
            .include "../vertical-slice/loop-tokenizer.asm"
            .include "../vertical-slice/loop-semantic-sink.asm"
            .include "../vertical-slice/loop-symbols.asm"
            .include "../vertical-slice/loop-parser.asm"
LegacyEncoders .equ 0
            .include "../vertical-slice/loop-z80-sink.asm"
            .include "../vertical-slice/target-output.asm"
            .include "../vertical-slice/typed-expression-z80.asm"
            .include "../vertical-slice/aggregate-z80.asm"
CompilerCodeEnd:
CompilerImmutableStart:
            .include "../vertical-slice/loop-keywords.asmi"
CompilerImmutableEnd:
CompilerCoreEnd:
ShellCodeStart:
            .include "basie-shell.asm"
ShellCodeEnd:
BasieImageEnd:
