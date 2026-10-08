# Test report

Roadmap step 69: large-program tests and stress tests. This report records
what the test suite proves about the toolchain at the end of step 69, how it
is run, and the limits it found. The capacity figures themselves are in the
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
| Native compiler against the reference (`native_equivalence_test.ts`) | 747 | Every claimed program (the `CLAIMED` groups, 229 programs and parts, including `ADVENT.BSI` and the standard library's) compiles to the reference's directory, byte, line and name streams byte for byte; each is linked by `BLINK.COM` and run, its output, return code and files equal to the reference build's. 514 refusal cases are refused by both compilers with the same diagnostic number, line and column. Random statements, expressions, `select` arms and `f32` statements compile alike. |
| Large programs and stress (`stress_test.ts`) | 13 | A program at each capacity minimum of the specification compiles as the reference's; random whole programs compile alike; a large program in many parts links and runs alike (§3). |
| The native shell (`basie_native_test.ts`) | 30 | Options, the library check, the stamp, chaining to `BLINK`, overlays, diagnostics, memory and nesting bounds. |
| The book's examples (`book_test.ts`) | 1 | Every example program of Programming Basie (debug80-docs, roadmap step 71) compiles with `BASIE.COM` to the reference's four streams, names included. |
| The native linker (`blink_test.ts`) | 47 | `BLINK.COM` links what the reference linker links, to the same image, and refuses alike. |
| The conformance corpus (`conformance_test.ts`, `conformance_triptych_test.ts`) | 6 | 174 programs run on the reference toolchain with their recorded results, 106 of them on real CP/M 2.2. |
| The reference toolchain | the rest | The lexer, grammar, source loader, object formats, linker, helper table, `f32` constants, messages and publishing. |

The whole suite, 943 tests, passes.

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
- Parts that include one another in a chain are all held while they load:
  sixteen parts of 1.5K in a chain do not fit, where the same parts
  included from the main part do.
- A routine is bounded by its log, about 20 bytes a statement, beside its
  part's source: 413 one-line statements beside a 7.6K part.
