# 20. Feature ledger


## 20.1 Required Baton 1.0 language

The following mechanisms are required in the single Baton 1.0 language:

| Area         | Required forms and rules                                                                                                                                                                                                                                                                                                                         |
| ------------ | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| Source       | Ordered multipart compilation input with stable part identities and part-relative diagnostics; flat ordered build manifest; ASCII-compatible bytes, `//` comments, logical newlines, case-sensitive preserved names, lowercase keywords, decimal, hexadecimal, and binary integers, byte characters, bounded string literals, fixed punctuation. |
| Structure    | One program scope and ordered declaration sequence across source parts, declaration before use, sole-signature forwards with abbreviated bodies, fixed `main()` entry, no executable top level.                                                                                                                                                  |
| Types        | `u8`, `u16`, `boolean`, nominal fixed records, checked fixed arrays, mutable bounded `string[N]` with current length and byte indexing, parameter-only `string[]` views, exact aggregate aliases, and exact-type aggregate copying.                                                                                                              |
| Declarations | Inferred scalar constants, explicitly typed aggregate constants with read-only direct roots, compile-time assertions, program variables, complete positional recursive static initializers, record fields, formal parameters, contiguous scalar locals, routine definitions and forwards.                                                        |
| Expressions  | Calls, checked array and bounded-string indexing, field selection and string `.length`, explicit integer conversions, unary `+`/`-`, arithmetic including quotient and remainder, one scalar comparison, `not`, `and`, `or`, and integer-only `xor`.                                                                                             |
| Statements   | Scalar assignment, exact-type aggregate assignment, name-led calls, `return`, `fail`, `exit`, and `continue`.                                                                                                                                                                                                                                    |
| Control      | Flat `if`/`elseif`/`else`, pre-test `while`, counted `for` over a read-only scalar-local counter with `to` or `until` and optional constant `step`.                                                                                                                                                                                              |
| Routines     | Formal arguments including capacity-polymorphic `string[]`, named scalar locals, no result or one typed result, early return, direct and mutual recursion, and one complete forward signature whose parameter names bind its abbreviated body.                                                                                                   |
| Failure      | Explicit `fails`, `fail`, same-line `else fail`, and immediate `handle NAME ... end`; success-only `return` and required safety traps remain separate.                                                                                                                                                                                           |
| System       | Baton System Services 0.1 with deterministic initial cursors and output writes, normal entry return, unhandled-error termination, and stable trap reasons.                                                                                                                                                                                     |

No conforming compiler may expose a standard profile that omits one of these mechanisms.

## 20.2 Implementation-defined limits

An implementation selects and documents capacities, not syntax or semantics. Permitted limits include complete source length, source-part count and metadata length, identifier length, symbol and type counts, record fields, array and string storage capacity below a target's available resources, parameters, scalar locals, nesting, fixups, structured-initializer depth and elements, emitted code size, total emitted image size, simultaneous activation depth, and activation-storage consumption. Every limit must be high enough to compile and execute the complete accepted Chapter 21 programs under their stated inputs. A compile-time excess above that floor produces a capacity diagnostic; runtime activation-capacity excess above that floor traps at runtime.

Diagnostic wording, private compiler representations, generated-code organization, service transport, and the external presentation of status are implementation-defined where earlier chapters leave them to the Z80 runtime and backend contract. These choices must preserve the source rules.

## 20.3 Post-0.1 candidates

These forms are omitted from 0.1 and may be reconsidered only by a future language revision after measured admission:

The maintainer of this language specification owns source-language admission. The maintainer of the Z80 runtime and backend contract co-owns decisions that change the target representation or System Services interface.

| Candidate                                                               | Required decision evidence and owner                                                                                                                             |
| ----------------------------------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Dense nonnegative selection                                             | Compiler cost versus emitted jump-table savings on representative programs; language-specification maintainer in a future revision.                              |
| Routine-local aggregate objects or fixed local aggregate aliases        | Representative-program need, declaration and initialization rules, recursion effects, compiler-core cost, and activation cost; language maintainer.              |
| Open arrays, slices, or views other than parameter-only `string[]`      | Source typing, carrier, lifetime, call/result ABI, compiler and target-runtime cost; language and runtime-contract maintainers in a coordinated future revision. |
| Bounded-string growth, resize, append, and capacity-changing operations | Typed contract, alias effects, emitted cost, and reusable-program evidence; language-specification maintainer in a future revision.                              |
| Additional system services                                              | Portable typed contract and complete compiler, runtime, and target cost; System Services maintainer in a future service revision.                                |

These candidates are not provisional 0.1 syntax. Extensions may prototype them only under Section 1.7.

## 20.4 Excluded mechanisms

Baton 1.0 excludes language levels and compiler-selected profiles; modules, imports, namespaces, macros, and textual includes; raw pointers, address arithmetic, memory or port access, inline assembly, arbitrary machine-code calls, interrupt routines, vector declarations, source-visible bank selection, and unrestricted casts; enumeration, subrange, set, union, variant, overlaid, generic, heap, resizable, open-array, slice, and dynamic types; transitive immutability or const-qualified alias types, routine-local aggregate declarations, activation-lifetime owned aggregates, general aggregate expressions or constructors, partial or named-field initializers, destructuring, inferred variable declarations, nested routines, overloads, routine values, callbacks, indirect calls, parameter modes, and multiple results.

It also excludes assignment expressions, chained comparisons, conditional expressions, general expression statements, `call` and `then` keywords, `select`/`case`, pattern matching, repeat/do loops, `for in`, omitted counted-loop operands, counted-loop counters drawn from program variables or parameters, source assignment to an active counter, nested reuse of an active counter, labels, goto, labelled exit, exceptions, throw/catch, unwinding, destructors, `finally`, `defer`, resumable traps, and runtime type tags.

Implementation alternatives such as register allocation, helper organization, hardware-stack use, fixup representation, and physical calling convention are not source features. The Z80 runtime and backend contract records the selected target obligations, and project decisions use measurements without creating Baton dialects.
