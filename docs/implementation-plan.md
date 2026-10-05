# Basie implementation plan

- Status: approved (design decision D35)
- Date: 2026-10-04
- Related: [design decisions](design-decisions.md), [feature inventory](feature-inventory.md),
  [build pipeline](build-pipeline.md), [memory safety](memory-safety.md),
  [services](services.md)

## 1. What is being built

Five things, in this order of dependency:

1. **The language specification:** Basie 1.0, forked from the Nucleus 0.1
   specification with decisions D1–D34 applied.
2. **The runtime library:** hand-written Z80 for CP/M 2.2, shipped as a blob
   library (`CPM22.BRL`), including startup, arithmetic helpers, pools, traps
   and the services.
3. **The standard library:** Basie source for strings, formatting, parsing and
   console and file conveniences.
4. **The linker, `BLINK.COM`:** Z80, running on CP/M 2.2.
5. **The compiler, `BASIE.COM`:** Z80, running on CP/M 2.2, within 24K.

## 2. The key decision: how to build it

### 2.1 Recommendation: a reference implementation in TypeScript on Deno, then the native toolchain

**Track A, the reference toolchain:** a compiler and linker written in
TypeScript, run under **Deno** on the development machine. It reads Basie
source and writes exactly the object format and program images the native
toolchain will. It is written in the same single-pass, streaming style as the
native compiler, so that it is an executable model of the native algorithms, not
an unrelated compiler.

**Track B, the native toolchain:** `BASIE.COM` and `BLINK.COM` in Z80 assembly,
assembled with ATOM as development tooling. The compiler starts from a fork of
the Nucleus 12K compiler rewrite, evolved in stages; the linker is new.

**How the two relate:**

- the reference toolchain comes first for each feature, so the specification and
  its conformance tests are settled before any Z80 is written;
- the native **linker** must produce byte-identical images to the reference
  linker for the same inputs, since its algorithm is fully specified; and
- the native **compiler** must produce programs that behave identically to the
  reference compiler's on the whole conformance suite: the same output, the same
  traps at the same source positions, and the same diagnostics. Its code need not
  be byte-identical, which leaves the native backend free to be smaller.

### 2.2 Why

- **Language design is still moving.** Settling a rule in TypeScript takes
  minutes; in Z80 it takes days. Every open question found while writing the
  reference compiler is found before it costs native work.
- **A test oracle.** Every native stage is checked against the reference on the
  same programs. Nucleus had to prove each feature from first principles; Basie
  gets a second implementation to disagree with.
- **Host tooling for free.** The reference compiler doubles as a fast
  cross-compiler for development, and its line tables and maps feed Debug80
  directly.
- **Measured budgets before native work.** Code size per feature can be
  estimated from the reference backend before the native compiler grows.

### 2.3 Alternatives considered

| Alternative | Why not |
| --- | --- |
| **Native only, as Nucleus was built** | Every language question would be answered in Z80. Nucleus showed this works but is slow, and Basie's language is several times larger |
| **TypeScript only, as a cross-compiler** | Fails the project's premise: Basie compiles on the Z80 itself |
| **Native compiler written from scratch** | Throws away the Nucleus rewrite's measured lexer, parser, scopes and code generation, which carry over almost unchanged |
| **A reference compiler with a conventional tree-based design** | Easier to write, but it would not model the native single-pass algorithms, so it couldn't expose single-pass problems early |

### 2.4 Tools

| Need | Tool | Status |
| --- | --- | --- |
| Language for the reference toolchain and tests | TypeScript on **Deno** | Skate already uses Deno for its proofs |
| Z80 execution | `@jhlagado/z80-runtime` | Used by Skate under Deno |
| Assembling native code and the runtime | ATOM, through `atom-z80` | Used by Skate under Deno; development tooling only |
| CP/M 2.2 for running programs and the native toolchain | The CP/M harness used by Skate's and ATOM's proofs | To be shared or adapted |
| Service contracts | `z80-services` (byte gateway, console and storage) | Basie's services adopt them (Section 6) |
| Turning runtime assembly into blobs | A blob output mode in ATOM, or a Deno tool over ATOM's output | To be decided in Phase 2 |

Node is used only where a shared package needs it.

## 3. Repository layout

```text
basie/
  docs/            design documents, reviews, this plan
  spec/            the Basie 1.0 language specification
  ref/             reference compiler and linker (TypeScript, Deno)
  runtime/         runtime library sources (Z80, ATOM) and the CPM22 profile
  lib/             the standard library (Basie source)
  native/          BASIE.COM and BLINK.COM sources (Z80, ATOM)
  tests/           conformance corpus, golden outputs, harnesses
  tools/           blob builder, budget census, CP/M harness glue
  deno.json        tasks: check, test, test:cpm, measure, census
```

## 4. Phases

Each phase ends with a **gate**: what must be true before the next begins. Work
within a phase is committed and pushed in small steps.

### Phase 0: Foundations

- Set up `deno.json`, formatting, linting and tasks.
- Bring the Z80 emulator and CP/M 2.2 harness into the test setup, following
  Skate's `tests/z80.ts`.
- Write the **limits register** (Section 7) and audit every design document
  against it.
- Settle the remaining design questions that block the specification: the
  memory-safety review's findings, and the services review.

**Gate:** a hand-assembled CP/M program runs under the harness from `deno task
test`; the limits register has no unexplained entry.

### Phase 1: The specification

- Fork the Nucleus 0.1 specification into `spec/`.
- Apply D1–D34 chapter by chapter: types and conversions, `select`, local
  aggregates and `from`, arrays of arrays, `var` parameters, pools and handles,
  `private` and `include`, `assert`, services.
- Seed the **conformance corpus**: for each rule, a small program with its
  expected output, trap or diagnostic. Nucleus's conformance examples are the
  starting point.

**Gate:** the specification has no "to be decided" in any version 1 chapter, and
every chapter has conformance programs.

### Phase 2: Object format, linker and blob libraries, in the reference toolchain

- Implement the object format readers and writers in TypeScript.
- Implement the reference linker: Phases A to E, every diagnostic, every output
  kind, the line table and map.
- Build the blob-library tooling: decide between an ATOM blob output mode and a
  Deno tool, and turn a small runtime (startup and a trap reporter) into
  `CPM22.BRL`.
- Test the linker against hand-written object files covering the linker's
  conformance list.

**Gate:** the linker passes its whole conformance list, and an image it links
from a hand-written object runs under CP/M.

### Phase 3: The reference compiler

Built in the order the language is taught, so each step produces programs that
run:

1. The Nucleus core: lexer, declarations, expressions, statements, routines,
   records, arrays, strings, `fails`, traps, writing blobs.
2. Signed and 32-bit integers, shifts, the numeric rules (D31).
3. `f32`, through runtime helpers.
4. `select`, block scope and declarations anywhere, constants and inference.
5. Local aggregates, `from`, `var` parameters, arrays of arrays.
6. Pools, handles, `move`, automatic freeing, the flow check, leases.
7. The stack bound, `private`, `include`, `assert`.
8. Branch shrinking.

Each step adds conformance programs and checks them end to end: compile,
link, run under the CP/M harness, compare output, traps and diagnostics.

**Gate:** the whole version 1 conformance corpus passes on the reference
toolchain.

### Phase 4: Runtime and standard library

- The runtime library in full: arithmetic helpers (16-bit, 32-bit, `f32`), copy
  and bounds helpers, pools (allocation, freeing with descriptors, generations,
  the cycle check), stack checks, trap reporters, startup, and every service.
- The standard library in Basie: strings, number formatting and parsing
  including `f32`, console and file conveniences.
- Measure every helper's size and stack figure, and publish them in the helper
  table.

**Gate:** the conformance corpus and a set of larger example programs pass, and
the helper table is complete.

### Phase 5: The native linker

- Write `BLINK.COM` in Z80, following the linker specification.
- Check it against the reference linker: for every object set in the tests, the
  two must produce byte-identical images, maps and line tables.
- Measure its memory and table capacity against the estimates.

**Gate:** byte-identical output on the whole test set, under the CP/M harness.

### Phase 6: The native compiler

Starting from a fork of the Nucleus 12K rewrite, in stages that each keep a
working compiler:

1. Replace Nucleus's placed output with blob output, and chain to `BLINK`.
2. Add the message file and the overlay mechanism.
3. Add the features in Phase 3's order.

After each stage: the conformance corpus must behave identically to the
reference toolchain, and the **budget census** must show `BASIE.COM` within its
24K and the workspace at least 32K. A stage that breaks the budget stops work
until it is brought back within it (Section 5).

**Gate:** the whole corpus passes natively, within budget.

### Phase 7: Release

- Large programs: the largest the compiler can compile, the largest the linker
  can link, build times on the CP/M harness.
- The book and reference material.
- A release image with `BASIE.COM`, `BASIE.MSG`, `BASIE.OVL`, `BLINK.COM`,
  `CPM22.BRL` and the standard library.

## 5. Budget discipline

- Every feature has an entry in the [feature inventory](feature-inventory.md)
  with its estimated cost, replaced by its measured cost as soon as it exists.
- The native compiler's size and workspace are measured on every commit that
  touches it, as Nucleus's were.
- **Stop rule:** if `BASIE.COM` exceeds 24K or the workspace falls below 32K, no
  further features are added until it is back within budget, by size work or by
  moving a feature to version 2. The feature inventory records which.
- The reference compiler's generated code is measured too, so code-size
  regressions show up before native work.

## 6. Services and the shared service contracts

Basie's [services](services.md) are its language-facing adapter over the
**z80-services** contracts, in the way Skate exposes Scheme ports and Nucleus its
own procedures. Before the runtime's services are written:

- map each Basie service to its z80-services operation (the byte gateway and the
  console and storage contracts), and record any service with no contract yet as
  a gap to raise there; and
- implement the CP/M 2.2 providers in the runtime library to those contracts,
  so their conformance vectors test Basie's services too.

## 7. The limits register

Every limit in Basie is listed in the [limits register](limits.md), with its
value, its reason and its kind: language, format, CP/M, or capacity. **The
rule:** no limit is smaller than memory allows unless the object format, CP/M or
a measured cost requires it, and every limit is published and diagnosed.
Capacity limits carry guaranteed minimums that the native toolchain must meet,
and the register records every small limit from Nucleus's first implementation
that Basie does not inherit.

## 8. Library questions, not language questions

Some open questions concern the standard library and services, not the language.
They don't block the specification or the compiler, and are settled during
Phase 4:

- **Positioning in text files:** whether text-mode files support saving and
  restoring a position. Binary files already have `seek`.
- **Typed results for services:** whether services report richer error values
  once variants exist in version 2. Until then, `u8` codes.

## 9. Risks

| Risk | Mitigation |
| --- | --- |
| The compiler exceeds 24K | Measured on every commit; stop rule; version 2 list; overlays |
| The workspace is too small for real programs | Measure symbol-table cost early in Phase 6; message file and overlays free space |
| The reference and native compilers drift apart | Behavioural comparison on the whole corpus after every native stage |
| Memory-safety rules are harder to implement in one pass than expected | The reference compiler implements them first, in the same single-pass style |
| The blob-library tooling needs ATOM changes | Decide in Phase 2; a Deno tool over ATOM's output is the fallback |
| Two implementations double the work | The reference compiler is smaller and faster to change; it repays itself in Phases 5 and 6 |

## 10. First steps

1. Fix the findings of the final memory-safety review.
2. Review the services draft, and align it with z80-services.
3. Phase 0: `deno.json`, the emulator and CP/M harness, and the limits register.
4. Phase 1: fork the specification.
