# Basie stretch goals

Date: 2026-10-06, plan decided 2026-10-10
Status: plan for the language after Basie 1.0, not a language amendment

The Basie 1.0 specification remains authoritative and its feature list remains frozen. Each change below still needs a design decision, specification text, conformance tests and a measurement against the compiler budget (D43) before the native compiler admits it.

## Criteria for each item

An item stays only if it does at least one of these:

1. It prevents a real bug that compiles today and then runs wrongly without a trap.
2. It removes friction from code that is written constantly, measured in real Basie code.
3. It makes possible a program that can't reasonably be written today.

It must then be worth its compiler bytes, with about 1.2K free under the 28K limit, and worth the extra thing every reader has to learn. "Nice to have" is not a reason.

The evidence comes from the code that does real work: the standard library, the example programs and the book's examples, 37 files and about 1,900 lines. The tests were left out, because they are written to exercise the compiler, not to show how programs are written. A larger application could change the counts. The deferred items are the ones most likely to move.

## Plan

1. Finish the post-roadmap work on the native compiler.
2. The next language version: the five changes below, in their order. `try`, `var` at the call site and `:` touch nearly every source file, so they are made as one rewrite of the library, tests and book.
3. A compression pass, if the budget needs it.
4. Version 2: precompiled libraries with module interfaces, then plain enumerations with typed failure codes.

## Next language version

Adopted 2026-10-10, in order of importance. The design decisions are D48 to D52.

| Rank | Change | Justification | Design to settle | Cost |
| --- | --- | --- | --- | --- |
| 1 | `try` in place of `else fail` (D48) | Friction: 146 `else fail` in about 1,900 lines of real code, one line in eight, and 1,172 in all. The commonest way of handling a failure is the longest. | one `try` per call, and whether `try` may appear inside a larger expression. | Small: the same jump `else fail` emits, marked before the call. 1,172 uses change mechanically. |
| 2 | `var` at the call site (D49) | Bug and friction: about 280 calls change the caller's data with no sign at the call. The book spends a section warning that `var` in a declaration is easy to miss. | required for every `var` parameter (recommended), the form for leases (`bump(var h)`), `var` results passed on (`touch(var pick(items, 2))`), and a diagnostic for a missing or unexpected `var`. | Tiny: one optional token in the argument parser and a check against the parameter's mode. Every existing call to a `var` parameter in the library, tests and book needs the marker. |
| 3 | `for … in` over arrays and strings (D50) | Bug: a counted loop can drift from its array without a trap. The library has about nine whole-array or whole-string traversals written with a counter. | scalar elements bound as copies or aliases (the same thing for reading), open arrays and strings (bytes), the index's type, and that the array can't be resized or released during the loop, which pools already guarantee by leasing. | Small: a hidden `u16` index, the length the compiler already knows or the open-array length already passed, and one element address per pass. No new run-time check, since the index is always in range. |
| 4 | `case else` required for value selections (D51) | Bug in principle: a value that matches no case runs nothing, the same silent gap that checked conversions close. The real code has one value `select`, which already has `case else`, so its payoff comes with enumerations. | whether `case else` may be empty, and whether a handle selection may still omit its second arm (recommend it must have both `some` and `none` or `else`). | Small: label coverage is already computed to reject overlaps. A full-coverage check is needed only for `u8`, `i8` and `boolean`, and is otherwise just the presence of `case else`. |
| 5 | `:` in place of `as` for types (D52) | Readability: `total: u32` and `distance(a: Point, b: Point): u16` are shorter and familiar from TypeScript, Pascal, Go, Rust and Zig. Kept by decision on 2026-10-10. Done in the same rewrite as `try` and call-site `var`, so the churn is paid once. | Every place `as` appears today: declarations, parameters, results (`as var T`), record fields and pool declarations (`pool jobs as Job[1]`). D14 chose `as` because it reads as a phrase where modifiers stack up (`var list as nodes?`). Colon has no token in Basie 1.0 (§3). | Small in both compilers: the lexer gains a `:` token and the declaration parsers accept it where they now expect `as`. Name-first order and single-pass parsing are unchanged. The same source-wide edit as above applies. |

## Version 2

| Rank | Change | Justification | Cost |
| --- | --- | --- | --- |
| 1 | Precompiled libraries and module interfaces | Capability: the route to programs larger than one compilation can hold, already the main version 2 aim. Namespaced includes (`include "STRINGS.BSI" as strings`) belong here, so that the library can grow while shadowing stays refused. | Precompiled libraries have an unmeasured 1–2K estimate. This is not a measured module-system cost. Namespaces: 300–600 bytes more. |
| 2 | Nominal enumerations, without payloads | Bug: 26 constants and 11 failure codes are integer groups the compiler can't tell apart, so a code can be mixed up with a count. Enumerations also give required `case else` its full use. | Plain enumerations alone about 0.5–1K, unmeasured. No separate measured estimate. The feature inventory estimates enums and variants together at 1.7–2.7K. |
| 3 | Typed failure codes | Bug: the 11 failure codes sit in three number ranges kept apart by convention only. | The inventory estimates enum-named failure codes at 0.1K. This does not estimate rich errors with payloads. |

## Deferred

Kept on file because a larger program could justify them. Each needs a real program that suffers without it.

| Change | Why deferred | Cost |
| --- | --- | --- |
| Named record initialisers | 4 of 14 records have two fields of the same type, so a reordered declaration could silently change an initialiser, but the real code has only about six positional initialisers. | 150–250 bytes |
| Tagged unions | A real capability, but no example program needs one, and it is the most complex item: ownership of whichever alternative is stored. Comes after enumerations. | The same combined 1.7–2.7K estimate, unmeasured. |
| Checked slices | The only real case is `copyFrom(dest, src, start, count)`. | No measured estimate. Include descriptor handling, range checks, parameter binding and generated code. |

## Cut

Decided 2026-10-10. These fail the test above.

| Change | Reason |
| --- | --- |
| `else` with a value | 1 of 11 `handle` blocks in the real code only sets a default, and `handle` already covers it. |
| `defer` | 3 file opens in the real code, and the runtime closes every file when `main` ends. A leak needs a long-running program that recovers from a failure and keeps opening files. The riskiest change for a rare case. |
| Default field values | No initialiser in the real code repeats a non-zero value. |
| Block comments | 9 runs of three or more `//` lines, which an editor comments in one keystroke. |
| `fn` in place of `sub` | Cosmetic, with a rewrite of every file and the book and the loss of the BASIC character. |
| Limited type parameters | No algorithm in the real code is duplicated for different element types. 1–2K, and it needs routine values before a sort works. |
| Routine values | No callback or comparator need in the real code. Its main use was generic sorting. |
| Enumeration-indexed arrays | A Pascal convenience that a constant index already provides. |
| Shadowing | Withdrawn 2026-10-10 in favour of keeping §5.6, as Zig does. |
| `?` or `!` in place of `else fail` | `?` clashes with optional types, and a trailing `!` is easy to miss and reads as "can't fail" to TypeScript, Kotlin and Swift programmers. `try` was chosen. |
| `mut` in place of `var` on parameters | Declined 2026-10-09. `var` stays, as D17 decided. |

## Establish the capacity first

Complete the existing native language work and capacity corrections before spending the remaining budget on extensions. Measure the resident image, overlay area, writable workspace and stack separately. Account for generated program bytes, runtime helpers and disk latency as well as compiler size. Spare COM bytes alone do not establish spare RAM or acceptable performance.

## Safety arguments for enums and slices

### Named alternatives and payloads

Enumerations prevent mixing unrelated numeric codes. Tagged unions additionally tie each alternative to its permitted data. A command represented by a numeric tag and unrelated record fields permits combinations such as a quit command with an item payload. A checked variant permits construction and access only for the selected alternative. Exhaustive selection can expose omitted cases when the type changes.

Evaluate plain enums separately from payload-bearing variants and enum-indexed arrays. Variants need rules for replacing an active payload, transferring owners, releasing owned descendants and preventing access to an inactive payload. Their storage can be a tag plus space for the largest alternative, so variants do not inherently require heap allocation. Payloads may still contain allocated objects. Basie's existing optional handles and checked failure handling remain useful mechanisms without general variants.

### A portion of an existing array

Open array parameters already let one routine process complete fixed arrays of different lengths. A checked slice would extend that capability to a contiguous portion, for example the occupied prefix of a fixed-capacity input buffer or a range of records being sorted. Today a buffer plus offset and count leaves more of the range relationship to application code. A slice would bind the starting location and extent as one checked argument.

Keep three quantities separate: reserved capacity, logical number of occupied elements and extent available through a particular view. Variable logical length can use fixed storage plus a count. It does not require a growable heap vector. A slice provides access to storage whose ownership remains elsewhere.

A bounded first design could allow slices only as routine arguments with call-length validity. Check range construction and indexing, preserve read-only or writable parameter permissions and prohibit a view escaping its storage lifetime. Specify empty ranges, endpoint conventions, nesting and arithmetic overflow. A descriptor must be constructible only from valid storage and a checked extent.

Writable slices require an explicit alias policy. Basie's current read-only aliases restrict writes through that path but do not globally freeze the object. Rust's prohibition on overlapping mutable borrows must not be assumed to exist in Basie. Evaluate whether existing alias semantics suffice or whether stronger exclusion is required for the proposed operation. A split into provably disjoint writable ranges is a separate candidate with its own checking and representation costs.

Use a fixed-buffer utility as the first comparison: process an occupied prefix, produce output in caller-provided storage and report the number of elements written. Compare the current buffer/offset/count interface with checked views at equivalent behaviour. Measure compiler bytes, descriptor workspace, generated bounds checks and runtime cost. Growable vectors, stored references, closures and general type parameters are separate extensions.

These proposals record capabilities for future evaluation, not an implementation commitment.

## Audit implementation restrictions separately

A temporary compiler table size must not become a language restriction by default. The existing capacity audit already records replacements and acceptance minima. Complete that work regardless of whether stretch features are admitted.

At the observed commit c1384bc, examples reach the 16-literals-per-routine table and the 2,048-byte routine blob buffer. Other audit entries include the shared 96-entry symbol table, 32 routine records, 64 parameters across the program, 48 fields across records, eight control frames and sixteen expression-stack entries. These are implementation capacities to review against current contracts, not suggested language limits.

For semantic restrictions, review the current rationale rather than presuming it: the 253-byte string capacity, unsigned indexing, constant loop steps, restricted failure-call positions, non-storable aggregate aliases and lack of routine values. Some protect the lifetime model or single-pass checking. Others may be representation conveniences. Changing one requires evidence and explicit design work. Preserve type safety, memory safety and defined behaviour throughout.

## Required result of an evaluation

Use one representative application or library and compare equivalent behaviour. Report the capability gained, compiler and program costs, overlay traffic, remaining capacities and safety proof obligations. Record a recommendation to adopt, defer or reject the candidate. Do not present the inventory's estimates as measured costs or use a new feature to postpone capacity defects.

References: [feature inventory](feature-inventory.md), [design decisions](design-decisions.md), [capacity audit](capacity-audit.md), [limits](limits.md) and [specification authority](../spec/01-status-and-conformance.md).

The [language capability discussion](language-capability-gaps.md) develops the everyday programming restrictions behind these candidates, including checked slices, aggregate value returns and composition of failing calls.
