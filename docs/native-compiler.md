# The native compiler: from the Nucleus fork to `BASIE.COM`

- Status: working plan for roadmap steps 65 to 67
- Date: 2026-10-05
- Related: [implementation plan](implementation-plan.md) Phase 6,
  [roadmap](roadmap.md) M7, [code generation](code-generation.md) (D41),
  [object format](object-format.md), [toolchain](toolchain.md),
  [capacity audit](capacity-audit.md) §4, D43 (budget)

## 1. What was forked

At step 64, `native/compiler/` held the Nucleus compiler from Nucleus commit
`8d1ed07`, in AZM syntax; at step 65.0 it became ATOM source (D44), with the
file names below. Its core measures 15,286 bytes. A compilation
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
regenerated (step 67), with the count recorded. The new generator writes ATOM
under the naming scheme of the conversion: `GR_ROWn` prediction rows and
`GR_ALTn` productions, directories `GR_ROWX`, `GR_ALTX`, `GR_ALTXH` and
`GR_ACTX`, counts `GR_ROW_N`, `GR_ALT_N` and `GR_ACT_N`, and `GR_START`. It
computes the row and production offsets itself, because ATOM takes a forward
reference only as one symbol and a small addend.

## 3. Step 65 in increments

Each increment keeps a working, tested compiler. Each follows the D43 cycle
(increment, correctness review, compression pass, census in the commit).

| # | Increment | Checked by |
| --- | --- | --- |
| 65.0 | Convert the fork to ATOM source (D44). Stage 1 (done): 29 files with 8.3 names, the conditionals resolved and every one of 2,094 names given an ATOM name under the label convention (`tools/atomize/*.json`), byte-identical to the AZM build; the AZM tree, its translation layer and the proof harness removed. Stage 2: line-by-line commentary, module by module, byte-identical | The ATOM image equals the AZM image; then each commented module leaves it unchanged |
| 65.1 | ~~Move `BLINK`'s CP/M core to a shared directory~~ Withdrawn: `BLINK` is written for ATOM and the compiler in AZM syntax, so sharing source would need a second translation, and it saves no bytes, the programs being separate. The shell takes `BLINK`'s algorithms (name characters, record I/O) in the compiler's dialect | — |
| 65.2 | The `BASIE.COM` shell: a second composition of the forked modules (now `BASIE.ASM` and `SHELL.ASM`) at `$0100` behind a CP/M shell that reads the parts named on the command line into memory, compiles them, prints a diagnostic as `NAME.BSI LINE:COLUMN Error N`, and deletes `A:$$$.SUB` on failure. Output goes to stub sinks. (done: `tests/basie_native_test.ts`; `BASIE.COM` 16,075 bytes, the shell 634 bytes of code and 152 of data) | `BASIE.COM` under the CP/M harness compiles programs of one and several parts from files and reports diagnostics with their part, line and column |
| 65.2b | The library header and key check and the compilation stamp (toolchain §3.1); options in brackets | Refused libraries and options as the reference toolchain refuses them |
| 65.3 | The blob writer: routine buffer, in-order reference buffer spilling to `$RF`, and the `$DR`, `$BY`, `$LN` and `$NM` writers with headers, trailers and CRCs (done without the spill: `OUT.ASM`, 236 bytes, and `BLOB.ASM`, 929 bytes, not yet in `BASIE.COM`; `tests/blob_writer_test.ts` writes hello's streams byte-identical to the reference's, links them with `BLINK` and runs the program, and covers every escape, form and line rule against the reference's writers) | Unit programs whose streams the reference linker accepts and links |
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

## 5. Findings from the commentary pass

The commentary pass of step 65.0 read every line. It changed no code. These
are what it found, to be dealt with by the step named.

**Suspected faults, inherited from Nucleus's shipping configuration:**

| Where | Fault | When |
| --- | --- | --- |
| `EXOPER.ASM`, `EX_ORS` | `xor` keeps its left operand with `EX_SAVE`, not `EX_HOLD`, so a pending failable call is not checked: `f() xor g()`, with only `f` failable, loses `f`'s failure | step 67, with a conformance program |
| `CALLS.ASM`, `RO_SEL` | A `CP AG_FIRST` has no branch after it (Nucleus's type-error jump sat in a conditional this configuration removes), so `r.a.x` with `r.a` a `u8` looks up a field in a non-record type | step 67 |
| `CALLS.ASM`, `RO_ERNG` | A constant index's range error sets only the offset, so it is reported at the closing bracket's line and column | step 67 |
| `GENCTRL.ASM`, `GC_PEND` | The label range check `AND $1F` / `CP 32` cannot fail; labels stay below 32 today | 65.4, when labels become per routine |
| `LL1.ASM`, `CALLWORK.ASM` | `DG_LLCAP` and `DG_LEAK` share the number 87 | step 66, with the message file |
| `ACTSTMT.ASM`, `AC_GOTO` | `exit` and `continue` do not clear `CT_FALLS`, so an `if` whose arms all end in `exit` inside a routine with a result may be refused with `DG_FLOW` | step 67 |
| `ACTIONS.ASM`, `AC_BOUND` | Has no effect: `AC_FOLD`, which always follows, overwrites `EX_WANT`; the bound is checked later by `AC_COUNT` | first compression pass |
| `SHELL.ASM` | The room check refused a part ending within 128 bytes of the limit; a read error ended a part silently; a trailing comma and a blank type were accepted; a part's drive was not printed in diagnostics | fixed after the pass (`BASIE.COM` 16,147 bytes) |

**Dead code and data** (bytes for the compression passes): the forward-signature
test (`PR_FORD` is only cleared, so `EX_ISFWD` never matches); unreachable
labels in `EXTERM.ASM` and `EXOPER.ASM`; handlers for transcript operations no
parser path writes, among them `RG_FATAL`; the banked paths that survive in
`GENAGGR.ASM` and `GENCALL.ASM`; fields written and never read (`EX_CPOS`,
`CT_RKIND`, `CT_RTYPE`, `AG_MODE`, `SY_GSLOT`); a 34-byte block of `STATE.ASM`
that only hosts two target tables; and a score of redundant instructions
(`LD B,A` after `LD A,B`, `CALL` then `RET`, jumps to the next line). Most go
with the placed output at 65.4; the rest are the first compression pass.

**Contracts.** The commentary agents checked every `;@ROUTINE` line against the
code by hand, and the actions' agent with a register-effect analyser that walks
each path through `PUSH`/`POP` and its callees' contracts. Making that analyser
a tool, run by the tests over every module, is planned with the first
compression pass, so that contracts stay true as code changes.

**Names to revisit,** each a byte-identical rename: tails of routines that are
global only because their code spans several labels (`TK_TRAIL`, `RO_SEL`,
`RG_FORK` and others), which become private when their routines are made one
scope; names in the wrong area (`EM_LDDE` in `GENCTRL.ASM`, `EX_EFLOW` used by
the actions, `TG_` routines in `ROUTINES.ASM`); vague or figurative words
(`EX_PEAK`, `EX_PURE`, `EX_MUTE`, `AG_FITRW`); look-alike pairs (`AC_LIVE` and
`AC_LIVEN`, `GC_TEST` and `GX_TEST`); and fields reused for several meanings
(`RO_ACNT`, `RO_DEST`).
