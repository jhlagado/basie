# 15. Safety failures and traps


## 15.1 Trap semantics

A **trap** terminates Basie source execution immediately. Source code cannot catch, handle, resume, mask, or convert it to a recoverable error. A trap performs no stack unwinding, frees no pool slot and runs no source cleanup action; the runtime's own end-of-run file handling still applies ([services](../docs/services.md), Section 7).

The implementation reports a stable symbolic trap reason and the best available location for the operation that failed. When source mapping is available, the report must identify the source span. Otherwise, it must identify the generated instruction location. Numeric trap encodings, transport records, monitor integration, and physical output belong to the Z80 runtime and backend contract.

Effects completed before the failing operation remain observable. The failing operation performs no result store unless its rule below says otherwise. No later source operation executes.

## 15.2 Required trap reasons

Basie 1.0 defines these trap reasons:

| Reason | Condition and point |
| --- | --- |
| `bounds` | An array index is outside its dimension's bound, or a bounded-string index is outside zero through the current length minus one. The trap precedes the read, write or alias formation. |
| `narrowing` | A checked conversion's value does not fit the target type, including a negative value converted to an unsigned type and an `f32` value whose truncation does not fit. The trap precedes production of the result. |
| `division-by-zero` | A divisor for `/` or `mod`, integer or `f32`, is zero. The trap precedes production of the result. |
| `float-overflow` | The rounded result of an `f32` operation or conversion exceeds the largest finite `f32`. |
| `float-invalid` | An `f32` operation has no real result, such as the square root of a negative number in the standard library. |
| `loop-range` | A counted loop's next value would continue but does not fit the counter type. The trap precedes the counter store. |
| `activation-capacity` | On entry to a forward-declared routine, its stack bound would reach free memory (Chapter 13, Section 13.9). The trap follows argument evaluation and precedes the routine's locals. |
| `stale-handle` | An access through an identifier whose slot has been freed since the identifier was made (Chapter 7, Section 7.16). The trap precedes the access. |
| `ownership-cycle` | A store of an owning handle would make a slot own itself, directly or through a chain (Chapter 7, Section 7.15). The trap precedes the store. |
| `pool-full` | `new` finds no free slot in its pool (Chapter 7, Section 7.10). The trap precedes evaluation of `new`'s arguments. |
| `assertion` | An `assert` condition is `false` (Chapter 10, Section 10.7). |
| `unhandled-error` | `main` returns failure. The report includes the returned code. |

A conforming implementation may use more detailed internal causes, but it must preserve these public reason identities. It must not report a required reason as another merely because two checks share a helper.

**Reports.** A trap report names the reason and the address of the trap site, the call instruction inside the statement that trapped, as `TRAP bounds at 1A3F` (design decision D11). The line table turns the address into a source position ([toolchain](../docs/toolchain.md), Section 8). An unhandled failure is reported as `FAIL` followed by the code in decimal. The [CP/M target](../docs/cpm-target.md), Sections 5 and 10, defines the exact output and return codes.

## 15.3 Compile-time proof

When the compiler proves a bounds, narrowing, division, `f32` overflow or assertion failure from source constants, the source is invalid and compilation produces a diagnostic. It must not emit an executable whose first relevant action is a guaranteed trap. Counted-loop `loop-range` failure is different: it remains a runtime trap because earlier control flow in the loop body may prevent execution from reaching the increment. When the compiler proves an operation safe, it may omit the runtime check.

If validity depends on runtime data, the program remains conforming and the check is part of its specified execution. Optimization must preserve the trap reason, ordering, and prior observable effects.

## 15.4 Ordering details

Chapter 9's left-to-right rules determine which of several possible failures occurs first. Assignment checks its target path before its right side, and checks each identifier on that path again after it; aggregate assignment validates both complete extents before changing the destination. Calls evaluate every argument before the activation-capacity check. An access through an identifier evaluates its other operands before the generation check. `new` checks for a free slot before evaluating its arguments. A counted loop checks the mathematical next value before storing it. Boolean short-circuiting suppresses every check in an operand that is not evaluated.

A recoverable service error follows Chapter 14 and is not a trap while a source caller can consume it. Only failure reaching the end of `main` becomes `unhandled-error`. A trap raised within a failable routine bypasses its failure channel and every `handle` body.

## 15.5 Host failures

The execution environment must preserve a trap even if its reporting device or output stream is unavailable. It may fall back to a monitor code, halt state, or other documented target mechanism. Reporting failure must not resume the Basie program or replace the original symbolic reason with an unrelated success outcome.
