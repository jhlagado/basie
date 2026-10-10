# Test report

Roadmap step 69: large-program tests and stress tests, brought up to date at
the end of step 74 (the current 0.1 line), with plain enum verification
added on 2026-10-10. This report records what the test suite proves
about the toolchain, how it is run, and the limits it found. The capacity figures themselves are in the
[limits register](limits.md) §5.1 and §5.2.

## 1. Running the tests

```
deno task test
```

runs every test under `tests/` against the reference toolchain, the native
compiler `BASIE.COM`, the native linker `BLINK.COM` and the runtime library
`CPM22.BRL`, all built from source. The CP/M programs run on the minimal
CP/M 2.2 harness (`tests/harness/cpm.ts`, BDOS entry at `$E406`); the
conformance corpus and `BASIE HELLO` also run on a real CP/M 2.2 system
under the Triptych emulator. `STRESS_SEEDS=n deno task test` runs `n` random
programs in the stress test rather than 40.

## 2. What the suite covers

| Area | Tests | What they establish |
| --- | ---: | --- |
| Native compiler against the reference (`native_equivalence_test.ts`) | 838 | Every claimed program (the `CLAIMED` groups, 255 programs and parts, including `ADVENT.BSI` and the standard library's) compiles to the reference's directory, byte, line and name streams byte for byte; each is linked by `BLINK.COM` and run, its output, return code and files equal to the reference build's. 579 refusal cases, 17 of them across parts, are refused by both compilers with the same diagnostic number, line and column. Random statements, expressions, `select` arms and `f32` statements compile alike. |
| Large programs and stress (`stress_test.ts`) | 13 | A program at each capacity minimum of the specification compiles as the reference's; random whole programs compile alike; a large program in many parts links and runs alike (§3). |
| The native shell (`basie_native_test.ts`) | 31 | Options, the library check, the stamp, chaining to `BLINK`, overlays, diagnostics, memory and nesting bounds. |
| The book's examples (`book_test.ts`) | 1 | Every example program of Programming Basie (debug80-docs, roadmap step 71) compiles with `BASIE.COM` to the reference's four streams, names included. |
| The native linker (`blink_test.ts`) | 53 | `BLINK.COM` links what the reference linker links, to the same image, and refuses alike. |
| The conformance corpus (`conformance_test.ts`, `conformance_triptych_test.ts`) | 6 | 176 programs run on the reference toolchain with their recorded results, 108 of them on real CP/M 2.2. The native compiler also builds and links the enum fixture under that operating system. |
| The reference toolchain | the rest | The lexer, grammar, source loader, object formats, linker, helper table, `f32` constants, messages and publishing. |

The whole suite, 1,124 tests, passes. Every program of the conformance corpus, the examples, the native test programs and the library that the reference compiles, 250 in all, compiles natively too (a sweep, `tools/_sweep.ts`, at 74.20); the constructs the native compiler still refuses (Error 191) are those the reference refuses too, with another diagnostic, and the open arrays of handles and of `File`s, which wait for version 2 ([limits](limits.md)).

## 3. Large programs and stress tests

### 3.1 The specification's minimums

Each of these compiles natively to the reference's streams byte for byte:

| Minimum (limits §5.1) | Program |
| --- | --- |
| Identifier length 255 bytes | a program variable named by 255 bytes |
| 1,000 top-level names | four parts of 240 variables, five routines and five constants |
| 128 names visible in one routine | 128 initialized locals |
| 32 parameters, 32 arguments | a routine of 32 parameters called with 32 arguments |
| 64 fields per record | a record of 64 fields |
| 128 forward declarations outstanding | 128 forward routines called before their bodies |
| Statement nesting 32 | `if`, `for` and `select` nested 32 deep |
| Expression nesting 32 | `x * k + (...)` 32 deep, an operator pending at each level |
| 256 `select` cases | a select of 256 cases |
| 64 owning locals | 64 `new` handle locals in one routine |
| 255 source parts | a main part including 254 others |

### 3.2 Random programs

`tests/stress_test.ts` generates whole programs from a seed: program
variables of several types, an array and a record, three to eight routines
each calling earlier ones, with parameters, locals and loop counters, and
nested `if`, `else`, `for` and `select`, expressions of every integer
operator, conversions and calls. About 95% are valid programs; the rest
fold a constant out of range, which both compilers refuse alike. Every build
compiles 40 of them; 400 were compiled once at step 69, all alike.

### 3.3 A large program, linked and run

A main part including sixteen parts of twenty variables and ten routines
each, the routines calling one another across the parts, compiles natively
to the reference's streams, links with `BLINK.COM`, and runs with the
output of the reference's build. The claimed programs add larger single
cases: `BIGMAIN.BSI` (four parts, 21K, more than the source area holds at
once), `MANYRTN.BSI` (200 routines), `CASE256.BSI` (a select of 256 cases,
its routine's bytes spilled to disk), `BIGSPILL.BSI` (a 5.4K routine,
spilled) and `BIGDATA.BSI` (a 4K buffer, a record with a 2K field and a
local array of 1,500 words), each linked and run.

## 4. Defects found

Step 69's tests found one capacity below the specification, now fixed:

- An array or record type, or an object, larger than 1K was refused
  (`object size`), even with no initializer, because the 1K initializer
  staging bounded every type. Only an initializer is staged now, so only
  an initialized object is held to 1K; `BIGDATA.BSI` is claimed. Its
  review found two sums that the old bound had kept from wrapping: a
  pool's slot, its record and header, past 64K (now `out-of-range`, as the
  reference refuses it), and a routine's frame past 64K (now `object size`,
  Error 190; the reference has no bound there).

Step 68's measurements found the others (limits §5.1): the operand stack's
16 entries and the 1K stack below 32 nested expressions; `BL_MAP`'s linear
walk and the routines' and keywords' linear searches, which made builds of
large routines and many routines slow.

## 5. Limits that remain

- (Lifted at 74 to 16K at top level.) An initialized object is staged in 1K (`AG_ICAP`): a larger initializer
  is `object size` (Error 190), where the specification has no compiler
  limit. Writing initializers to their blob as they are parsed would lift
  it.
- 255 routines (`RO_RCAP`): the 1,000 top-level names of the
  specification were met only with fewer routines among them. Lifted at
  74: routines are bounded by memory, about 24 bytes each.
- Parts that include one another in a chain were all held while they
  loaded: sixteen parts of 1.5K in a chain did not fit, where the same
  parts included from the main part did. Lifted at 74: a part is dropped
  while a part it includes loads, when that part would not fit above it,
  and read again after.
- A routine is bounded by its log, about 20 bytes a statement, beside its
  part's source: 413 one-line statements beside a 7.6K part.

## 6. Plain enums

Plain nominal enums (D53) are implemented in the reference and CP/M compilers.
`tests/plain_enums_test.ts` checks 79 cases: compile, link and execute enum
variables, constants, record fields, arrays, parameters and results; compare
all four object streams; and reject mixed enum/integer operations and invalid
members. Boundary proofs cover 256/257 members, 48/49 shared type descriptors,
and the last supported native open-array element ID (39) versus ID 40. An
untyped enum constant retains its nominal identity. The Triptych CP/M 2.2 test
also compiles the enum fixture with BASIE, chains to BLINK and runs the result. Existing integer selection
and `as` syntax remain; typed failures and exhaustive selection are separate work.

### Compiler cost and compression

ATOM builds give the following accounting. Workspace is the compiler's writable
region, including the grammar stack, FLOAT scratch and owner descriptors;
it excludes the separately reserved 1,152-byte machine stack and shell/blob
workspace. No runtime helper or linker change is required.

| Component | Before enums | Enums before compression | After compression |
| --- | ---: | ---: | ---: |
| Compiler code | 24,195 | 24,780 | 24,697 |
| Immutable compiler tables | 278 | 282 | 282 |
| Resident image, including shell | 24,927 | 25,516 | 25,433 |
| Reserved overlay window | 2,611 | 2,611 | 2,611 |
| Resident plus overlay window | 27,538 | 28,127 | 28,044 |
| Compiler writable workspace | 4,812 | 4,812 | 4,812 |
| Overlay file | 10,368 | 10,496 | 10,496 |

The compression pass saves 83 resident bytes, primarily by sharing nominal
symbol decoding, removing checks already made by callers, simplifying class
encoding and shortening four branches. Independent reviews checked type identity,
flags, stack balance, diagnostic positions and the packed memory layout. The
net resident cost is 506 bytes, with 628 bytes left below the 28 KiB limit.
The DIAG overlay grows by 13 bytes (one extra disk record); no overlay is added.
Generated object streams remain byte-identical to the reference compiler.

A follow-up review compared 224 probes with the reference and found four native
divergences, now fixed: a pool of enums is pool-needs-record; a pool's name in
an expression is wrong-class without reading past the type table; a computed
enum, handle or `File` beside a Boolean is type-mismatch; and an enum `for`
bound is type-mismatch. The fixes cost 12 resident bytes (25,445; total 28,056,
616 below the 28 KiB limit) and add six refusal checks; 1,136 tests pass.

The source/symbol region begins at `$85EC`, 512 bytes above the pre-enum `$83EC`.
Compression recovers one page from the uncompressed `$86EC` layout, but does not
eliminate the feature's capacity cost. BIGSPLF's 518 lines retain every token
and statement; removing one leading space from each indented line reduces its
source allocation by exactly four CP/M records, restoring its former source-end
address. Its test now requires code-spill writes and reads and a subsequent
FLOAT-overlay reload, as well as all existing stream comparisons and execution
against the reference build. Specification capacity minimums are checked by the
existing stress suite.

### Measured compile paths

These CP/M harness measurements compare the same enum implementation before
and after compression. They count CPU T-states and overlay record reads;
mechanical disk latency is not simulated.

| Source | Before compression T-states | After compression T-states | Overlay records read, both builds |
| --- | ---: | ---: | ---: |
| Empty main | 2,087,802 | 2,082,683 | 35 |
| Enum values fixture, including record/array storage | 8,811,055 | 8,796,573 | 48 |
| Plain enum with a local and equality assertion | 2,382,237 | 2,374,931 | 35 |

Successful compilation reads the same overlay records in the same order.
Thus the compression savings do not depend on additional disk loads. These are
emulator proofs, not measurements on a physical floppy drive.
