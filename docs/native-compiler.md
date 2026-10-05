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
operations. The plan was to flush the transcript at the end of each routine
and each top-level declaration and replay it into a routine buffer. At 65.4
the native compiler instead generates each construct's code as it parses it,
as the reference compiler does, straight into the blob writer's buffer
(`BLOB.ASM`, 2K): nothing a routine's emitter needs is unknown while it
writes. The frame is patched into the prologue when the routine ends (the
reference patches it the same way), the frame and need words come after the
code, forward jumps are chained through the addend words of their
references and resolved when the label is defined (`EMIT.ASM`), and the
literals of stage (h) will follow the need word as the reference's do. So
there is no transcript and no replay: a second representation of every
construct, and the code to write and read it, would cost bytes and offer
nothing the blob buffer does not. The expression parser's operand stack
already holds what the reference's recursive descent keeps on its call
stack, so the reference's templates map onto its reduction steps (§3,
65.4 c). The parser's transcript entry points remain only as the refusal of
constructs not yet moved (`TRANSCR.ASM`, `DG_NYI`). The routine is still
buffered whole because its record's size and reference count must come
before its references. Parse and emit state now coexist, so the workspace
has no overlays left but the diagnostic position's.

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
| 65.4 | Placed output replaced by blob output whose streams equal the reference compiler's (D45). In stages, each a program set that must match: (a) `sub main()` with an empty body, through BLOB.ASM, with ordinals, the entry and limits records and the D41 prologue and epilogue; (b) top-level variables and constants as data, rodata and bss blobs, with references; (c) 16-bit expressions and assignment in the reference's templates; (d) locals and frames; (e) routine calls, parameters, results and `RETN`; (f) `if`, `while`, `for`, `exit`, `continue`; (g) failure, `fail`, `else fail`, `handle`; (h) records, arrays and strings; (i) services through the compiled-in helper table. Code is generated as it is parsed, not replayed (§2, Streaming); `TARGET.ASM` and the Nucleus runtime identity go. **(a) done:** the shell opens the four streams on the first part's drive and name (options `N`, `M` and `Y` read), names the parts, and closes them; routines without parameters become code blobs with the D41 prologue, success return, exit sequence and frame and need words, and bare `return`; declarations are written as data and bss blobs; the entry and limits records end the directory. `TARGET.ASM`, `TGTWORK.ASM`, `RTSTATE.ASM`, `RTIDENT.ASM`, `GENEXPR.ASM`, `GENCTRL.ASM`, `GENTMPL.ASM`, `GENAGGR.ASM` and the old emitter were deleted, with the shell's output stubs and the bank checks; everything else reaching the transcript is refused (Error 95). Claimed: `EMPTY`, `FAILS`, `SUBS`. `BASIE.COM` 12,379 bytes. **(b) done:** program variables become data or bss blobs and aggregate constants rodata blobs, in declaration order, named in the name stream; a variable's symbol holds its blob's ordinal; constants generate no code until a value is needed, and then load at the destination's type (`GX_TOREG`); assignment loads, widens and stores program variables through `ABS16` references (`GENEXPR.ASM`); a character literal is exact, as spec 9.7 says, where the fork made it a `u8`. Claimed: `DECLS`, `REFS`. `BASIE.COM` 12,381 bytes. **(c) done:** the expression parser generates the reference's code as it reduces: a computed left operand is pushed while the right is computed (`PUSH HL`, or `PUSH AF` for a byte, counted into the frame), and popped beneath a known right (the immediate forms) or a computed one; a known left becomes the immediate after the right (swapped for `-`, `/`, `mod` and the orders); `*`, `/` and `mod` call `MUL16` and `DIV16`, bytes through words; the six relations at both widths and on Booleans; `and` and `or` short-circuit through a routine label after a computed Boolean, and a deciding constant discards the right arm's code (`EX_QUIET`, `EM_QUIET`) while its frame accounting runs, as the reference's `suppress` does; `not`, unary minus, `u8()` with its `TRAP_NAR` check and `u16()`; folding follows the reference (typed results wrap, exact ones stay exact), and an exact value the native compiler cannot represent (below zero or above 65,535) is refused rather than folded differently. Claimed: `WORDS`, `BYTES`, `MIXED`, `COMPARE`, `LOGIC`, `FOLD`, `TRAP`; `TRAP` links with `BLINK` and traps where the reference's build does. Randomly generated assignments (300 in the test, 2,400 more in development) compile to the reference's streams or are refused by both compilers. `BASIE.COM` 12,647 bytes. **(d) done:** a local takes its offset below IX when it is declared, the frame's size with it in, and the frame grows when it is committed, after its initializer, as the reference's `allocLocal` does, so that the initializer's pushes are counted against the frame before it; its value is stored at its type or, without an initializer, its bytes are zeroed (`zeroFrame`); locals and parameters are read and written through the reference's `ixByte`, `ixWord`, `ixStoreA`, `ixStoreHL` and `ixStoreImm`, near as `(IX+d)` and, beyond IX−128..IX+127, through the computed address with the registers kept pushed and counted into the frame (`GX_FACC`, one table entry per access); a local declaration marks its line, as a statement does (`GR_LOCAL`). The symbol table holds 96 records of seven bytes, the aggregate type in the record (the parallel `AG_SYTAB` gone); the dead `EX_LIVE`, `EX_CPOS`, `SY_LSLOT` and `SY_GSLOT` went. Claimed: `LOCALS`, `FARFRAME` (a 144-byte frame with every far form); the random assignments alternate between program variables and locals (3,000 more in development). `BASIE.COM` 12,724 bytes. **(e) done:** a call pushes its arguments left to right, a scalar brought into the registers at its parameter's type and a u8 or Boolean widened to a word, an aggregate as its address (`RO_ROOT` generates a path's root: `LD HL,nn` for program storage and constants, the parameter's word for a parameter); `CALL` the routine, whose exit removes the arguments (`LD IY,n` / `JP RETN`), so the pushes are counted out; the callee's need joins the caller's (`noteCall`); a parameter is used in place at its argument's offset from IX; results come back in `A` or `HL` (an aggregate's address in `HL`, not one rooted at a parameter). Each routine's record (twelve bytes) holds its ordinal, its need once its body is complete, and its argument bytes. A forward routine is published where it is declared, so it takes its ordinal there and its blob where its body is, as the reference's does: `BLOB.ASM` writes each blob when it ends, which is where the reference's list puts it, so no buffering is needed; its prologue checks the stack through its pair label (`LD HL,(need)` / `CALL STK_CHK`), it counts zero in its callers' needs until complete, only it may call itself (`DG_UNMET` otherwise), and the limits record's flag says the program has one. The call frames of `RO_NTAB` became the machine stack; the Nucleus services, whose calls were refused, are now refused where they are named, with their parser and signature table removed. Refused for now: calls to main, a forward main, failable callees (g) and open-string arguments (h). Claimed: `CALLS`, `FORWARD`, `AGGARGS`, `WIDE` (64 parameters, the first beyond IX+127), `RECURSE` (run with `BLINK`: it reaches its final trap only when its results are right), and from the conformance suite `narrowing-traps` and `division-by-zero-traps` (run); the random assignments also go to parameters; ten programs both compilers refuse, among them `no-routine-named-id`, which the native compiler had accepted (a routine may not be named `id`). `BASIE.COM` 12,452 bytes. After (e), a compiler diagnostic or a full disk deletes the four streams, as toolchain §6.2 requires, unless option `K` keeps them (`SH_SCRUB`, 70 bytes of shell; `tests/basie_native_test.ts`). `BASIE.COM` 12,522 bytes. **(f) done:** `if`, `elseif` and `else`, `while`, the counted `for` and `exit` and `continue` generate the reference's code: a condition is `OR A` / `JP Z` to the next arm or the exit, a known false one a `JP`, a known true one nothing; every arm but an else ends in `JP end`, and the last false label and the end are defined together; a while's test is its continue label; a for loop stores its start, keeps its bound in a new two-byte frame slot (at the wider of its type and the counter's, an exact bound a u8 when it fits) that stays allocated until the enclosing block ends, tests the counter against it, and at its next value, where continue goes, goes on only if a step fits in the distance to the bound before storing the new value, a u8 counter trapping `loop-range` if it leaves its type (the native subset has no signed or 32-bit counters, so the reference's `always` and `never` modes cannot arise). Each construct has a sixteen-byte control frame (`CONTROL.ASM`) holding its routine labels, the label count and frame size it restores when it closes (a block frees the bound slots of loops inside it, as the reference's `block` does), and a for loop's mode, counter, bound and step; labels are freed by nesting, and `and` and `or` free theirs when they join (`EM_LFREE`), so the 32 labels of `EM_LCAP` are 32 in use at once. Fallthrough is the reference's: a block starts reachable, `return`, `fail`, `exit` and `continue` end that, an if completes when an arm falls through or it has no else, and loops and handlers always complete; the saved fallthrough per depth (`AC_FLOWS`) went. The program-wide control labels (`CT_LABNO`, `CT_LLIM`) and the transcript operations of control flow went. A loop counter is checked by its full 16-bit offset (`CT_GUARD`). **(g) done:** `fail n` (`PUSH AF` / `POP AF` / `SCF` / `JP exit`), and a call to a failable routine, which decides at once, as the reference does, from the token after it: before `else` (fail) `JP C,exit`, before `handle` `JP C` to a new label, otherwise `DG_LEAK` (`RO_FAILS`); so a failable call may be a right operand or under `not`, and the checks of the fork that it be the whole expression (`EX_PURE`) went. `handle NAME` jumps over the handler on success, drops the temporaries the failure left beneath the call (`POP DE` each, a fault fixed in the reference first), stores the code in the u8 variable and closes as a block. Claimed: `IFS`, `LOOPS`, `FORS`, `FLOW`, `FAILURE`, `RUNFLOW` and from the conformance suite `loop-range-traps` (`LOOPTRAP`); `LOOPS`, `FORS`, `FAILURE`, `RUNFLOW` and `LOOPTRAP` are linked with `BLINK` and run; every fifth random assignment sits in an `if` or a `while`; 32 more programs both compilers refuse. `BASIE.COM` 12,585 bytes. **(h), first part:** the runtime helpers' ordinals and stack figures come from the helper table (`HELPERS.ASM`, generated with the reference's by `deno task helpers` and checked by `tests/helper_table_test.ts`), trap sites through `EM_TRAP`. A path is parsed as the reference's designator: a root (a program variable or aggregate constant static, a parameter an alias through its word, a call's result computed in `HL`), then fields, elements, characters, `length` and an open string's `capacity`; its place is kept (`RO_PLACE`), and each step's code is written as it is parsed (`GENAGGR.ASM`): a field or constant index moves a static, frame or alias place on, or adds to a computed address (`addConst`); a run-time index is brought into `HL`, checked (`CALL NC,TRAP_BND`), scaled and added to the base, which, when computed, is pushed before the index is parsed; a string's character is checked against its length byte and the index's high byte. Scalars are loaded and stored at the place (through a computed address with it pushed while the value is computed), aggregates copied with `LDIR`, string literals copied into strings and passed to `string[]` parameters, each placed after the need word (16 per routine), open strings passed as their address and capacity word, and aggregate results' fields and elements read; a result may not be rooted in the frame, tracked as the reference's `lastAddressRoot` is (`RO_ESC`). The type table holds 24 types, 16 records and 48 fields. The rest of the transcript's operations went (`PR_EMITC`, `TR_PUT`, every `OP_` code). Claimed: `PATHS`, `COPIES`, `VIEWS`, `FARPATH` (a record and an open string beyond IX+127), `RUNPATHS` (run: it reaches its last statement's bounds trap only when its results are right) and the conformance program `trap-bounds` (`BOUNDS`, run); the random assignments take fields, elements and characters as operands and targets (3,000 more in development); 25 more programs both compilers refuse. `BASIE.COM` 13,365 bytes | Each stage's programs compile to the reference's streams (shrinking off), link with `BLINK` and run (`tests/native_equivalence_test.ts`) |
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
| `EXOPER.ASM`, `EX_ORS` | `xor` keeps its left operand with `EX_SAVE`, not `EX_HOLD`, so a pending failable call is not checked: `f() xor g()`, with only `f` failable, loses `f`'s failure | fixed at 65.4 (c): `EX_OPEN` keeps every left operand of `and`, `or` and `xor` with `EX_HOLD` |
| `CALLS.ASM`, `RO_SEL` | A `CP AG_FIRST` has no branch after it (Nucleus's type-error jump sat in a conditional this configuration removes), so `r.a.x` with `r.a` a `u8` looks up a field in a non-record type | fixed at 65.4 (h): `RO_PATH` raises `DG_CLASH` at the dot for a field of a scalar or an array; and the field search, whose count `AG_FIELD` overwrote, now stops at a name the record lacks (it ran on through the table) |
| `CALLS.ASM`, `RO_ERNG` | A constant index's range error sets only the offset, so it is reported at the closing bracket's line and column | fixed at 65.4 (h): the index's first token's position is kept (`RO_IPOS`) and the error is reported there, as the reference reports it, in a discarded arm too |
| `GENCTRL.ASM`, `GC_PEND` | The label range check `AND $1F` / `CP 32` cannot fail; labels stay below 32 today | gone with `GENCTRL.ASM` (65.4 a); routine labels are checked against `EM_LCAP`, and control flow uses them from 65.4 (f) |
| `LL1.ASM`, `CALLWORK.ASM` | `DG_LLCAP` and `DG_LEAK` share the number 87 | step 66, with the message file |
| `ACTSTMT.ASM`, `AC_GOTO` | `exit` and `continue` do not clear `CT_FALLS`, so an `if` whose arms all end in `exit` inside a routine with a result may be refused with `DG_FLOW` | fixed at 65.4 (f): `AC_GOTO` ends with `AC_DEAD`, and fallthrough follows the reference's rules (`FLOW`) |
| `ACTIONS.ASM`, `AC_BOUND` | Has no effect: `AC_FOLD`, which always follows, overwrites `EX_WANT`; the bound is checked later by `AC_COUNT` | fixed at 65.4 (f): removed; `BeginTypeBound` is `AC_IDLE`, the `RET` of `AC_WANT` |
| `SHELL.ASM` | The room check refused a part ending within 128 bytes of the limit; a read error ended a part silently; a trailing comma and a blank type were accepted; a part's drive was not printed in diagnostics | fixed after the pass (`BASIE.COM` 16,147 bytes) |

**Found at 65.4 (c).** The fork typed a character literal as `u8`, where spec
9.7 makes it exact; it folded two exact operands at the expected width, so
`a = 200 + 100` gave 44 where the reference refuses it; it negated or
complemented an exact operand at the expected width; and inside the
unevaluated arm of a constant short circuit it turned a division by zero or
an over-wide `u8()` into a quiet zero, where the reference reports both.
Each now behaves as the reference does, or is refused. One fault is the
reference's: an exact left operand with a computed right is not checked
against the right's type, so `c = 300 + a`, with `a` a `u8`, compiles as
`a + 44` (`emitBinaryConstLeft` encodes the constant with `encodeScalar`,
which truncates); the native compiler refuses it with `DG_RANGE`. It should be
fixed in the reference, with a conformance program, and the native compiler
then claims it.

**Found at 65.4 (f) and (g).** `AC_STMT` kept a variable's class in `D` across `CT_GUARD`, which clobbers `DE` when a for loop is open, so an assignment inside a loop body was refused (`DG_CLASH`); it reads `AC_DINFO` again. The reference compiler let a handled failure leave the temporaries pushed beneath the failing call on the stack, so `x = a + f() handle e` entered the handler with `a` still pushed and a loop that failed on every pass ran the stack down; it now drops them (`POP DE` each), with the conformance program `handle-drops-temporaries`, and the native compiler does the same.

**Found at 65.4 (h).** Five faults of the reference compiler's paths, each
fixed there first with a conformance program: an index applied to a
computed base (an element reached through a computed index, or a call's
aggregate result) was parsed, and its code emitted, before the base's
address, so the inner index overwrote the outer one (`grid[i][j]` read
`grid[j][j]`; `computed-indexes-in-turn`); a `u16` stored through a `var`
parameter into a field beyond its fourth byte lost its value to the
offset's `LD DE` (`var-parameter-far-field`); a slot-holder argument read
its owner word from the frame temporary before the path's code had
written it; a discarded short-circuit arm left its jumps to be shortened,
its labels' chains and its string literals behind, so the default build
rewrote later code as `JR`s and a literal sent the compiler round a
garbage chain until it ran out of memory (`discarded-arm-leaves-no-jumps`,
`discarded-arm-leaves-no-literal`); and an aggregate result of the wrong
type was returned (`aggregate-result-type`). The reference now generates
an open view's address before its capacity word and a slot-holder's
before its owner word, so that no code comes between a path and its use,
which lets the native compiler write each step as it parses it; a string
index lost a dead `LD A,(HL)` / `CP E`. The native compiler's predefined
names are still Nucleus's six services and four error constants, so a
program that names a routine after one of the reference's services or
predeclared constants (`size`, `close`, `console`, `fileNotFound`) is
accepted natively and refused by the reference; the full table comes with
the services at 65.4 (i).

**Dead code and data** (bytes for the compression passes): the forward-signature
test (`PR_FORD` is only cleared, so `EX_ISFWD` never matches); unreachable
labels in `EXTERM.ASM` and `EXOPER.ASM`; handlers for transcript operations no
parser path writes, among them `RG_FATAL` (gone at 65.4 a, with the replay);
the banked paths that survive in `GENAGGR.ASM` and `GENCALL.ASM` (gone at
65.4 a); fields written and never read (`EX_CPOS`, gone at 65.4 d, `CT_RKIND` and `CT_RTYPE`,
gone at 65.4 a, `AG_MODE`, `SY_GSLOT`); a 34-byte block of `STATE.ASM` that
only hosts two target tables (gone at 65.4 a); and a score of redundant instructions
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
