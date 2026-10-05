# Basie roadmap

- Status: working plan
- Date: 2026-10-04
- Expands: [implementation plan](implementation-plan.md) (D35)

This roadmap breaks the implementation plan into numbered steps. Each step names
what it produces and how it is checked. Steps within a milestone are mostly in
order; milestones overlap where noted. Every step ends with a commit and push.

The **tracks**:

- **Design:** documents and decisions.
- **Spec:** the language specification.
- **Ref:** the TypeScript reference toolchain on Deno.
- **RT:** the runtime library (Z80) and the standard library (Basie).
- **Native:** `BASIE.COM` and `BLINK.COM` (Z80).

## Standing rule: the capacity audit

Every step that introduces a table size, field width, buffer or threshold
updates the [capacity audit](capacity-audit.md) and the
[limits register](limits.md) in the same commit, classifying the limit and
recording its trade-off. Steps 35 (deferred references), 64 (the inherited
Nucleus tables) and 68 (measurement) have specific audit obligations noted
there.

## M0. Close the design

| # | Track | Step | Produces | Checked by |
| ---: | --- | --- | --- | --- |
| 1 | Design | Apply the memory-safety verification pass and freeze revision 5 | Frozen memory-safety design (done: revision 6) | Verification report says ready |
| 2 | Design | Apply the services review; align every service with z80-services; raise contract gaps there | Services revision 2 (done); contract gaps recorded in services §10 | Review findings closed |
| 3 | Design | Write the remaining small decisions: string library contents, `assert` message form, the `F=n` link option and its pseudo-object, message-file format | Decisions D36–D39 (done) | Each referenced from the spec outline |
| 4 | Design | Complete the limits register: audit every document and the Nucleus specification for fixed limits | [Limits register](limits.md), every row justified (done) | No unexplained limit |
| 5 | Design | Freeze the version 1 feature list against the budget | Feature inventory marked frozen (done) | Totals within 24K |

## M1. Foundations

| # | Track | Step | Produces | Checked by |
| ---: | --- | --- | --- | --- |
| 6 | Ref | Deno tasks, formatting, linting, test layout | `deno.json` | `deno task check` (done) |
| 7 | Ref | Minimal CP/M harness on the Z80 runtime | `tests/harness/cpm.ts` | First test (done) |
| 8 | Ref | Extend the minimal harness: file BDOS functions over an in-memory disk, the command tail, return codes, cycle counting | Harness with files | Tests for each BDOS function (done: console, files, search, random records, size, tail, return codes) |
| 9 | Ref | Full-fidelity harness: boot real CP/M 2.2 on the Triptych machine, as Skate does | `tests/harness/triptych.ts` | A `.COM` runs from the CCP prompt (done) |
| 10 | Ref | Golden-output test runner: compile, link, run, compare output, traps and diagnostics | `tests/run-conformance.ts` | Runs the corpus; tests pending until the compiler handles them (done) |
| 11 | Ref | Budget census tool, adapted from Skate's: measures images by module | `tools/census.ts` | Measures a fixture program; `--budget` fails when exceeded (done) |

## M2. The specification

| # | Track | Step | Produces | Checked by |
| ---: | --- | --- | --- | --- |
| 12 | Spec | Fork the Nucleus 0.1 specification into `spec/`, with a change log | `spec/` chapters and change log (done) | Builds as Markdown |
| 13 | Spec | Lexical rules: new literals (`f32`), keywords (`select`, `move`, `pool`, `new`, `shl`, `shr`, `private`, `include`, `assert`), contextual `id` | Chapter 3 (done) | Conformance programs for each token |
| 14 | Spec | Types: eight numeric types, handles, owning types, arrays of arrays | Chapter 6 (done) | Conformance programs |
| 15 | Spec | Storage and lifetime: block scope, activation storage, pools, the memory-safety rules | Chapter 7 (done) | Conformance programs, including rejected programs |
| 16 | Spec | Declarations: typed and local constants, inference, `pool`, `private` | Chapter 8 (done) | Conformance programs |
| 17 | Spec | Expressions: the numeric rules (D31), conversions, shifts, bitwise operators | Chapter 9 (done) | Conformance programs, including edge values |
| 18 | Spec | Statements: declarations anywhere, `select`, `move`, `assert` | Chapters 10 and 11 (done) | Conformance programs |
| 19 | Spec | Routines: `var` parameters, leases, `from`, forward rules for recursion | Chapter 13 (done) | Conformance programs |
| 20 | Spec | Errors and traps: the new traps, named failure constants | Chapters 14 and 15 (done) | Conformance programs |
| 21 | Spec | The system boundary: services and the standard library | Chapter 16 (done) | Conformance programs |
| 22 | Spec | Complete grammar, checked for single-pass parsing | Chapter 17 (done; `tools/grammar.ts` reads §17.2 and checks it against the §17.4 table, Chapter 3 and the lexer) | A grammar check like Nucleus's |
| 23 | Spec | Adversarial review of the specification | Review report and fixes ([report](reviews/2026-10-05-spec-review.md): done; 85 findings, all closed) | Findings closed |

Steps 12 to 23 can run alongside M3 once chapters 3 and 6 exist.

## M3. Object format, linker and blob libraries (reference)

| # | Track | Step | Produces | Checked by |
| ---: | --- | --- | --- | --- |
| 24 | Ref | Object format readers and writers, with CRCs | `ref/object/` | Round-trip tests, including the worked example (done) |
| 25 | Ref | Linker Phase A: tables, deduplication, every Phase A diagnostic | `ref/link/` (done) | One test per diagnostic |
| 26 | Ref | Phases B and C: marking, placement passes, pseudo-objects, fit checks | (done) | Placement tests with aligned blobs |
| 27 | Ref | Phase D: image writing, value checks, `.COM`, `.BIN`, `.HEX`, the line table | (done) | Byte-level tests |
| 28 | Ref | Phase E: map, symbol file, removal report | `ref/link/reports.ts` (done) | Golden files |
| 29 | Ref | Publication and failure handling, temporary names, `.BAK` | `ref/toolchain/` (done) | Tests with injected disk errors |
| 30 | RT | Decide the blob-library build: an ATOM blob output mode or a Deno tool over ATOM's output | `tools/brl.ts`: a Deno tool over three ATOM assemblies (done) | Builds a two-blob library |
| 31 | RT | A minimal `CPM22.BRL`: startup, one trap reporter, `writeOutputByte` | `runtime/cpm22/cpm22.asm` (done) | Linked with a hand-written object, runs under the harness |
| 32 | Ref | The linker's conformance list in full | `tests/link_test.ts` (done) | All pass |

## M4. The reference compiler

Each step adds conformance programs and runs them end to end.

| # | Track | Step | Produces | Checked by |
| ---: | --- | --- | --- | --- |
| 33 | Ref | Lexer and source parts, with `include` | `ref/compile/lexer.ts`, `source.ts` (done) | Token tests |
| 34 | Ref | Declarations, scopes, `private`, forward declarations | `ref/compile/symbols.ts`, `compiler.ts` (done) | Scope tests |
| 35 | Ref | Expressions and statements on `u8`, `u16`, `boolean`: the Nucleus core | `ref/compile/compiler.ts`, `emit.ts`; `hello` runs (done) | Nucleus's conformance examples pass |
| 36 | Ref | Records, arrays, bounded strings, open views, aggregate constants | (done: records, arrays, strings, open views, aggregate constants) | Nucleus examples |
| 37 | Ref | Routines, results, `from`, `fails`, `handle`, traps, the line stream | (done except the stack bound's recursion tests: see step 46) | Nucleus examples |
| 38 | Ref | Signed types, 32-bit types, shifts, bitwise operators, the numeric rules | runtime 32-bit helpers (done; 32-bit loop counters and select subjects still pending) | Edge-value tests |
| 39 | Ref | `f32` through helpers, literal conversion, constant folding | `runtime/cpm22/f32.asm`, verified against IEEE single on 400 vectors (done) | Conversion and rounding tests |
| 40 | Ref | Declarations anywhere, block scope, typed and local constants, inference | (done; `declarations/` and `scopes/` in the corpus) | Scope and inference tests |
| 41 | Ref | `select` on integers, characters and ranges; dispatch shapes | (done: integers, characters, ranges) | Dispatch tests |
| 42 | Ref | Local aggregates, `var` parameters, arrays of arrays, `assert` | (done) | Tests |
| 43 | Ref | Pools, handles, `new`, `new?`, `move`, freeing, temporaries | `ref/compile/compiler.ts`, runtime pool helpers (done) | Memory-safety tests, accepted and rejected |
| 44 | Ref | The flow check and the statement rule | (done) | Rejected-program tests from the reviews |
| 45 | Ref | Leases, slot-holders, owner words, `select` on handles, `select move` | (done; the reviews' counterexamples and examples are conformance programs in `storage/`) | The reviews' counterexamples all rejected or trapped |
| 46 | Ref | The stack bound, prologue figures, activation checks | (done) | Recursion and deep-call tests |
| 47 | Ref | Branch shrinking and the literal buffer | `ref/compile/emit.ts` (done; measured 1.2% smaller images) | Size tests |
| 48 | Ref | Diagnostics by message number, matching the planned message file | `ref/compile/messages.ts`, `tools/msgfile.ts`, `BASIE.MSG` (done) | Diagnostic tests |
| 49 | Ref | The whole conformance corpus | (done for the current corpus: 113 programs; grows with each later step) | Corpus passes |

## M5. Runtime and standard library

M5 starts alongside M4: each compiler step needs its helpers.

| # | Track | Step | Produces | Checked by |
| ---: | --- | --- | --- | --- |
| 50 | RT | 16-bit and 8-bit helpers: multiply, divide, compare, copy, bounds | Runtime blobs (done; `tests/integer_test.ts` checks the multiply and divides against host arithmetic) | Unit tests on the Z80 runtime |
| 51 | RT | 32-bit helpers | (done; `tests/integer_test.ts`: 6,604 edge and random cases against BigInt) | Exhaustive edge tests against host arithmetic |
| 52 | RT | `f32` helpers: add, subtract, multiply, divide, compare, conversions, with flush-to-zero and traps | (done; `tests/f32_test.ts`: 400 cases against host IEEE single) | Tests against host IEEE arithmetic |
| 53 | RT | Pools: allocation, `new?`, freeing with descriptors, the link test, generations, the cycle walk | (done; `storage/` in the corpus, with the reviews' programs, under both harnesses) | Tests including the reviews' programs |
| 54 | RT | Stack checks, trap reporters, startup and exit, the `OPTIONS` word | (done; `tests/brl_test.ts`, the trap programs, and the corpus under real CP/M) | Startup tests under both harnesses |
| 55 | RT | Services: console and printer, then files, then the command line and machine | `runtime/cpm22/services.asm` (done; 16 conformance programs in `services/`) | z80-services conformance vectors; CP/M harness tests |
| 56 | RT | Publish every helper's size and stack figure in the helper table, with interface keys | [Helper table](helper-table.md), `tools/stack.ts`, `tools/helpertable.ts` (done; figures computed and checked by measurement) | Linker compatibility tests |
| 57 | RT | Standard library in Basie: strings, number formatting and parsing, `f32` formatting, console and file conveniences | `lib/`, [standard library](standard-library.md) (done; 8 conformance programs in `library/`) | Library tests |
| 58 | RT | Example programs: a text adventure, a file utility, a game with a pool | `examples/` (done: ADVENT, DUMP, BUGS, played by script under both harnesses; they found the free-list and IX/IY faults) | Run under the full harness |

## M6. The native linker

| # | Track | Step | Produces | Checked by |
| ---: | --- | --- | --- | --- |
| 59 | Native | Skeleton `BLINK.COM`: command tail, file I/O, CRC, message output | `native/linker/` (done: 2.6K; checks the library header and, with V, its CRC; `tests/blink_test.ts`) | Runs under the harness |
| 60 | Native | Phase A and B | `native/linker/PHASEA.ASM` (done; the tables match the reference linker's on the examples and corpus programs) | Same tables as the reference, dumped and compared |
| 61 | Native | Phase C and D, the line table | `native/linker/PHASECD.ASM`, `LINES.ASM` (done for .COM images without option R: image and line table byte-identical to the reference on the examples and corpus programs) | Byte-identical images on the linker suite |
| 62 | Native | Phase E and publication | `native/linker/PUBLISH.ASM`, `PHASEE.ASM` (done: publication, map and symbol file byte-identical to the reference on the examples and corpus programs) | Byte-identical maps and files |
| 63 | Native | Capacity measurement: the largest program it can link | Measured limits (done: about 5,450 blobs, or a full 54K image; [limits](limits.md) §5.2) | Published in the limits register |

## M7. The native compiler

Each stage keeps a working compiler, and the census runs on every commit.

| # | Track | Step | Produces | Checked by |
| ---: | --- | --- | --- | --- |
| 64 | Native | Fork the Nucleus 12K rewrite into `native/compiler/`; build and run its existing proofs | Baseline | Nucleus proofs pass |
| 65 | Native | Replace placed output with blob output; chain to `BLINK` | | Nucleus examples link and run |
| 66 | Native | Message file and overlay mechanism | `BASIE.MSG`, `BASIE.OVL` | Diagnostics match the reference |
| 67 | Native | Steps 38 to 48 in order, each as a native stage | | Corpus behaviour identical to the reference after each stage; census within budget |
| 68 | Native | Capacity measurement: largest compilable program, symbol counts, build times | Measured limits | Published |

## M8. Release

| # | Track | Step | Produces | Checked by |
| ---: | --- | --- | --- | --- |
| 69 | All | Large-program tests and stress tests | Test reports | Pass |
| 70 | All | Release image: `BASIE.COM`, `BASIE.MSG`, `BASIE.OVL`, `BLINK.COM`, `CPM22.BRL`, the library | Disk image | Boots and builds the examples |
| 71 | Design | The Basie book in debug80-docs | Book | Verification script like Nucleus's |
| 72 | All | Version 2 planning: enumerations and variants, expression blocks, routine values | Plan | — |
| 73 | Design | Debug information for source-level debugging: a binary, CP/M-readable format mapping addresses to statements and lines, and routines to their frame layouts and types, building on the line table (`.LIN`) and symbol file (`.SYM`). D8 is the reference point but is not assumed suitable for CP/M. Low priority: no debugger is planned yet, but the format must exist before one is | Format specification; a `D` link option | Round-trip tests; a host tool that lists source for an address |

## Running order

```text
M0 ──► M1 ──► M2 ─────────────┐
              │               │
              └──► M3 ──► M4 ─┴──► M6 ──► M7 ──► M8
                         ▲
                    M5 ──┘ (alongside M4)
```

The reference toolchain is complete at the end of M4 and M5. The native work
then has a full oracle to compare against at every step.
