# 2. Design constraints


## 2.1 Scope

This chapter records three kinds of constraint: properties preserved by the Baton 1.0 language design, acceptance gates for the first handwritten Z80 compiler, and evidence required before a provisional feature enters the language. Later chapters define the source language and its semantics. The separate Z80 runtime and backend contract defines the direct target obligations.

The implementation gates in this chapter apply to the first compiler project. They are not language-conformance requirements for every Baton compiler. A compiler may conform to Baton 1.0 on another host without using Z80 code, banked memory, or the same internal architecture.

Baton 1.0 is one language. Measurements may change the draft before it is frozen, but they do not create language levels, implementation-selected syntax profiles, or optional dialects. Each candidate is either admitted to the single language or omitted.

## 2.2 Language-shaping constraints

Baton is a safe, practical, general-purpose structured language designed to remain viable on small Z80 systems. Its minimum programming model includes `u8`, `u16`, and Boolean values; scalar and aggregate constants; formal arguments, including capacity-polymorphic bounded-string parameters; named scalar local variables; routines with no result or one typed result; fixed-layout records; checked fixed arrays; bounded strings with length and checked byte indexing; complete positional static initializers; assignment and calls; `if`/`elseif`/`else`; `while`; counted `for`; `return`; and the unlabeled, innermost-loop forms of `exit` and `continue`. Silently removing one of these requirements does not make an oversized compiler acceptable. If a faithful implementation cannot fit, that result requires compiler-architecture redesign or rejection of the architecture hypothesis.

The language design uses deterministic parsing with canonical forms, minimal lookahead, and no backtracking. A smaller production count is useful only when it preserves the required programming model. Grammar terseness is not an independent design goal.

A conforming compiler must perform every source-safety check for which compilation provides sufficient information. Safety conditions that depend on runtime values must produce defined traps. Source code has no raw pointer arithmetic or unchecked reinterpretation. Later chapters define the checks, traps, and source types.

Every implementation capacity must have an explicit limit and a diagnostic for excess. Exhausting a symbol table, input limit, nesting limit, or other bounded resource must not alter program meaning or produce silently incorrect output.

## 2.3 Compiler-core gate

Project acceptance requires the first compiler's executable core and every immutable table or constant required while compiling to fit together in one 16 KiB bank. Placing required code or immutable data in another bank does not satisfy this gate.

For each tested configuration, the compiler-core total includes the front end, the direct-Z80 emitter, and all immutable data that either component requires. The report identifies the resident configuration and includes every shared or required component.

The first implementation may use a flat 64 KiB address-space model as its initial abstraction. This model does not bind Baton source semantics to a particular operating system, monitor, or memory map. Additional memory or banks may hold separately budgeted components, but they are not a fallback for an oversized core.

## 2.4 Separate resource accounts

Resources outside the compiler-core gate may use other RAM or banks where the platform permits, but they remain bounded, measured, and reported. Separate accounting does not make a resource free or unlimited.

| Account                     | Required report                                                                                                            |
| --------------------------- | -------------------------------------------------------------------------------------------------------------------------- |
| Compiler core               | Executable code and required immutable data for the tested front end and active emitter, measured against the 16 KiB gate. |
| Writable compiler workspace | Peak live bytes, including lexical, parsing, name, type, lowering, diagnostic, and emission state.                         |
| Generated output            | Emitted Z80 program and static-data bytes, separate from compiler storage.                                                 |
| Target runtime              | Shared helpers, service adapter, trap machinery, immutable data, writable state, and relevant execution cost.              |
| Execution                   | A stated measure, such as instruction count or cycles, for representative emitted programs.                                |

Project accounting counts each shared component once and assigns it to an identified account. Reports distinguish resident components, overlays, and mutually exclusive configurations. Peak workspace is the maximum simultaneously live storage, not the sum of buffers whose lifetimes do not overlap.

## 2.5 Streaming compilation model

Bulk storage may be available but slow. The compiler consumes the ordered multipart compilation stream defined by Chapter 4 and emits one logical Z80 program and static-data output. A platform may materialize either stream in external storage. Physical source discovery, ordering, and transport do not require the compiler to retain the whole program in memory.

The first compiler is handwritten Z80 and uses streaming, single-pass compilation wherever the language semantics permit it. Declarations precede use. An explicit forward routine signature supplies the necessary exception without requiring a later whole-program pass. Because that declaration is the sole signature, the compiler retains its parameter names until the abbreviated body begins and performs no body-signature comparison. Its compiler-core and workspace effects remain unmeasured.

The architecture excludes an abstract syntax tree, global type inference, whole-program optimization, and unbounded buffering from the first compiler. The compiler may retain bounded state required for declarations, scopes, forward signatures, control-flow fixups, and emission, provided each capacity is explicit and measured.

## 2.6 Semantic operations and direct emission

Compiler size has priority over compilation speed. The front end records a compact vocabulary of checked semantic operations and the backend turns those operations into Z80 machine code. The operation transcript is a private, bounded compiler representation rather than a portable target or execution format.

Structured control lowers to ordinary comparisons, branches, calls, and checked runtime operations. The first direct backend uses fixed, proof-driven templates and bounded fixups before adding register allocation, branch shortening, whole-program optimization, or peephole optimization. Each increment measures compiler code, immutable data, workspace, generated output, target runtime, and execution cost.

The companion Z80 runtime and backend contract fixes packed data layout, stable service and trap codes, call obligations, and generated-code integrity. Physical register allocation, helper organization, fixup representation, and calling-convention details remain measured implementation choices where that contract leaves them open.

## 2.7 System boundary and portability

The initial system boundary contains only services that Baton programs demonstrably require: input, output, termination, trap reporting, and bulk-storage access. Each additional service requires measured need.

The semantic-operation boundary may support later direct backends for other Z80 variants or other targets where target neutrality has no material cost against the compiler-core gate and other bounded accounts. Portability does not justify growth that causes the first compiler to fail its core gate.

Baton 1.0 defines no interrupt routine, interrupt or restart vector declaration, interrupt-reentrant calling convention, or interrupt-safe service guarantee. The compiler emits no interrupt vector table. A target may interrupt a Baton program only through a handler outside the language that preserves the program's machine state and does not enter a Baton routine or service.

A target may assign ordered source parts to banked target regions without changing manifest order, declaration visibility, or source identity. Banking introduces no source construct, address value, or alternate return convention. The target-system specification and Z80 runtime contract define bank placement and may diagnose references that their banked representation cannot preserve safely; such a target restriction does not make the source program invalid under this specification.

## 2.8 Evidence and feature admission

Project reports assign every size, storage, or performance claim one of these evidence classes:

- **Measured:** obtained from an identified build or run with the method recorded.
- **Projected:** calculated from measured components under stated assumptions.
- **Hypothesis:** an expectation not yet tested by an implementation.

A candidate's admission record reports its incremental compiler-core code, required immutable data, peak writable workspace, target-runtime cost, effect on emitted programs, and total-system trade. Source-line count, host executable size, and an instruction sketch are not substitutes for target measurements. Before Baton 1.0 is frozen, the project either admits the candidate to the one normative language or omits it.

Baton 1.0 admits the explicit recoverable-error mechanism in Chapter 14. The implementation ledger still records its compiler-core, immutable-data, workspace, emitted-code, and runtime costs. General exceptions, stack unwinding, destructors, `finally`, and `defer` remain excluded.

Baton 1.0 admits recursive routine calls. The current compiler implements direct, main, and mutual recursion with a published activation-depth bound. Chapter 13 defines the source semantics, and Chapter 15 defines activation-capacity failure.

Several source-preserving economies belong in the implementation rather than in language variants. The compiler uses one precedence-driven loop for binary expressions and classifies a completed call expression before admitting `else fail`; it does not duplicate the precedence ladder or branch on a routine signature before parsing the call. It uses interned type ordinals naming compact structural metadata. The direct backend may continue to measure shared tails, table dispatch, helper calls, fall-through layout, and width-specific target sequences. None of these choices may change accepted source, arithmetic width, required diagnostics, array aliases, or observable behavior.

## 2.9 Decision boundary and failure conditions

An architecture decision requires measurements from an identified compiler configuration and representative accepted and rejected source. The report includes the complete compiler-core total, immutable-data contribution, peak writable workspace, target-runtime total, emitted-program size, execution cost under a stated method, capacity limits, and diagnostics produced when those limits are exceeded. Candidate comparisons use equivalent source semantics and accounting boundaries.

The decision record labels every value as Measured, Projected, or Hypothesis and states the assumptions behind projections. Unmeasured values remain open rather than being replaced with invented byte estimates.

The first implementation is not required to compile itself. The project may evaluate self-hosting only after measurements show that the handwritten compiler satisfies its budget and conformance goals. Failure to preserve the minimum programming model, diagnose bounded-resource exhaustion, or keep required compiler code and constants within the one-bank gate rejects the tested architecture; it does not justify a weaker, unnamed language profile.
