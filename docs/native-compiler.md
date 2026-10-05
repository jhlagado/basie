# The native compiler: from the Nucleus fork to `BASIE.COM`

- Status: working plan for roadmap steps 65 to 67
- Date: 2026-10-05
- Related: [implementation plan](implementation-plan.md) Phase 6,
  [roadmap](roadmap.md) M7, [code generation](code-generation.md) (D41),
  [object format](object-format.md), [toolchain](toolchain.md),
  [capacity audit](capacity-audit.md) §4, D43 (budget)

## 1. What was forked

At step 64, `native/compiler/asm/vertical-slice/` holds the Nucleus compiler
from Nucleus commit `8d1ed07`. Its core measures 15,286 bytes. A compilation
runs in three phases that never overlap:

1. **Parse.** The LL(1) engine parses every source part and appends
   operations to a semantic transcript.
2. **Close.** The transcript is published.
3. **Emit.** The transcript is replayed through a dispatch table into placed
   Z80 code. Forward operands go to a global fixup table that is resolved at
   the end.

Because the phases are disjoint, the workspace overlays them: the emit state
reuses the parser's stacks. The workspace is 3,609 bytes, about 2K of it the
static-image staging.

| Module | Bytes (est.) | Fate |
| --- | ---: | --- |
| Source adapter (resident, multipart) | 141 | Rewritten: CP/M records, a name heap |
| Tokenizer and keyword tables | 870 + 393 | Kept, widened for Basie's keywords |
| Semantic sink (transcript) | 58 | Kept, flushed once per routine |
| Symbols (16 linear entries) | 106 | Rewritten: hashed, scoped, name heap |
| Parser group: engine, tables, actions, expressions, aggregates, routines, control | about 8,730 | Kept and extended; tables regenerated |
| `EmitByte` and patching | 397 | Kept, writing into the routine buffer |
| Placed output (`target-output.asm`) | 1,436 | Deleted |
| Expression code generation | 1,156 | Kept inside expressions; edges to D41 |
| Control code generation | 639 | Kept; labels made per routine |
| Routine and call code generation | 1,177 | Rewritten to D41 |
| Aggregate image publication | 190 | Rewritten: one blob per declaration |

The output adapter that frames Nucleus's object records lives in the proof
harness. It is not counted in the 15,286 bytes.

## 2. Where it differs from Basie

**Output.** Nucleus is its own linker: it lays out the runtime, startup code
and program at final addresses. Basie emits blobs: one per routine, variable
and constant, with ordinals and references that `BLINK` resolves. Every site
that computes an absolute address today becomes a reference:

| Address kind | Nucleus | Basie |
| --- | --- | --- |
| Program variable | data base + offset | `ABS16` to the variable's ordinal, plus an addend |
| Aggregate constant | read-only base + offset | `ABS16` to a `rodata` ordinal |
| Runtime helper | runtime base + identity offset | `ABS16` to the helper's ordinal |
| Routine | 5-bit label ordinal | 16-bit ordinal from `$0400` |
| Branch inside a routine | global absolute fixup | self-reference `ABS16` with the offset as addend, or `JR` after shrinking |
| Startup, data copy, `bss` clear | emitted by the compiler | the library's startup blob and the `ENTRY` record |

One primitive, `EmitRef(form, ordinal, addend)`, replaces them all. It writes a
zero placeholder and appends the reference to the routine's in-order buffer.

**Routines.** The fork keeps frames on the hardware stack with `IX`, as D41
does. It differs in these ways:

- It copies parameters into the frame.
- It evaluates as a pure stack machine.
- The caller pops arguments.
- It counts activations against an arena of 8.
- Each trap site takes about 37 inline bytes.

D41 instead says:

- Parameters are used in place.
- The callee removes arguments, through `RETN`.
- Results come back in `A`, `HL` or `DEHL`.
- A trap is `CALL cc,TRAP_x`.
- A routine ends with `frame` and `need` words.

D41 fixes only the edges. So the expression templates may keep their stack
discipline inside a statement, provided every push is counted into `frame`.
Replacing the fat trap sites and the parameter copying should shrink the
compiler.

**Streaming.** One transcript for the whole program caps a program at 255
operations. Basie flushes the transcript at the end of each routine and each
top-level declaration. The routine is then replayed into a 2K-to-4K routine
buffer, and written out as one `$BY` run and one `$DR` record. The record's
size and reference count must come before its references, which is why the
routine is buffered. Every workspace overlay of §1 has to be re-checked under
streaming, because parse and emit state now coexist.

**Tables.** Every Nucleus table is proof-sized
([capacity audit](capacity-audit.md) §4). The worst are the 16-entry symbol
table and the 511-byte transcript. Each is replaced at the stage that first
needs it, and the audit and the limits register are updated in the same commit.

**Grammar encoding.** The packed LL(1) tables give terminals `$00` to `$3F`:
64 kinds. Basie has 55 keywords, 17 punctuators and 7 other token kinds, 79 in
all. The plan is to fold token classes so that the grammar never needs the
widening:

- one terminal for every type keyword, with the type in the token's value;
- one terminal each for the multiplicative, additive and relational operator
  classes, read inside the expression island.

That brings the count to about 60. The decision is made when the tables are
regenerated (step 67), with the count recorded.

## 3. Step 65 in increments

Each increment keeps a working, tested compiler. Each follows the D43 cycle
(increment, correctness review, compression pass, census in the commit).

| # | Increment | Checked by |
| --- | --- | --- |
| 65.0 | Convert the fork to ATOM source (D44): stage 1, mechanical, byte-identical, with 8.3 file names, the conditionals resolved and temporary names; stage 2, module by module, names under the label convention and line-by-line commentary, byte-identical | The ATOM image equals the AZM image; then each curated module leaves it unchanged |
| 65.1 | ~~Move `BLINK`'s CP/M core to a shared directory~~ Withdrawn: `BLINK` is written for ATOM and the compiler in AZM syntax, so sharing source would need a second translation, and it saves no bytes, the programs being separate. The shell takes `BLINK`'s algorithms (name characters, record I/O) in the compiler's dialect | — |
| 65.2 | The `BASIE.COM` shell: a second composition, `asm/basie/basie.asm`, of the forked modules at `$0100` behind a CP/M shell that reads the parts named on the command line into memory, compiles them, prints a diagnostic as `NAME.BSI LINE:COLUMN Error N`, and deletes `A:$$$.SUB` on failure. Output goes to stub sinks. The proof composition stays as the front end's regression oracle (done: `tests/basie_native_test.ts`; `BASIE.COM` 16,075 bytes, the shell 634 bytes of code and 152 of data) | `BASIE.COM` under the CP/M harness compiles programs of one and several parts from files and reports diagnostics with their part, line and column |
| 65.2b | The library header and key check and the compilation stamp (toolchain §3.1); options in brackets | Refused libraries and options as the reference toolchain refuses them |
| 65.3 | The blob writer: routine buffer, in-order reference buffer spilling to `$RF`, and the `$DR`, `$BY`, `$LN` and `$NM` writers with headers, trailers and CRCs | Unit programs whose streams the reference linker accepts and links |
| 65.4 | Placed output replaced: ordinals at declarations, `EmitRef` at every address site, D41 edges, `frame` and `need` words, helpers and services by the compiled-in helper table, per-routine transcript flush | Programs in the Nucleus subset, written in Basie's spelling, link with the reference linker and behave as the reference compiler's |
| 65.5 | Chaining: the loader at the top of memory runs `BLINK.COM` with the build's tail | `BASIE HELLO` under the harness produces a `HELLO.COM` that runs |

The language at the end of step 65 is the Nucleus subset of Basie. Test
programs are therefore valid Basie, and the reference compiler is the oracle,
comparing behaviour rather than bytes. Byte comparison waits until the native
code generator follows the reference's templates (step 67).

## 4. Budget

| Stage | Change | Projected size |
| --- | --- | ---: |
| Fork (step 64) | measured | 15.3K |
| Step 65 | −2.3K placed output, banking, startup and trap endings; +1.9K CP/M core; +0.45K chain, stamp and library check; +0.9K blob, line and name writers; +0.3K `frame`/`need` and helper stack table; +0.3K table widening | 17.0–17.6K |
| Step 66 | message file and overlay loader | about 18K |
| Step 67 | the Basie features of the [feature inventory](feature-inventory.md) not yet present | about 27K |

That exceeds the 26K target, so these levers are planned from the start:

1. **Overlays for one-shot code.** Three groups never run at the same time:
   - command-line parsing and the library check, at the start;
   - decimal-to-`f32` conversion, during compilation;
   - the chain loader, at the end.

   Sharing one overlay area saves about 1.3K of resident code.
2. **Compression passes,** after every increment. Nucleus's history shows 3% to
   5% per pass.
3. **Removing Nucleus-only machinery early:**
   - the region-check helpers;
   - the banked paths;
   - activation counting;
   - the root-frame save.

The census figure is recorded in every commit that touches the compiler. A
commit that crosses the 28K limit is not made: compression comes first (D43).
