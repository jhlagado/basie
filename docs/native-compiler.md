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

That brings the count to about 60. The generator (67a.1, `tools/llgen.ts`)
writes ATOM under the naming scheme of the conversion: `GR_ROWn` prediction
rows and `GR_ALTn` productions, directories `GR_ROWX`, `GR_ALTX`, `GR_ALTXH`
and `GR_ACTX`, counts `GR_ROW_N`, `GR_ALT_N` and `GR_ACT_N`, and `GR_START`.
It computes the row and production offsets itself, because ATOM takes a
forward reference only as one symbol and a small addend.

**Decided at 67a.** Only a token the grammar names, as a terminal or in an
island's FIRST set, must be below `$40`; a token read only inside an island
(the operators `*`, `/`, `<` and the rest, read by the expression parser)
or never seen by the parser at all (`include`, whose lines the loader
takes) may have any kind of a byte. So the encoding needs no widening, and
the folding is needed only for the grammar's own terminals. At 67a the
grammar names 44 (`private` the newest) of the 57 token kinds; the type
keywords still have one terminal each. The folding of the type keywords
into one terminal comes with the numeric types (67b), which would add five
more, and the count is recorded in `tests/llgen_test.ts`, which fails past
64.

## 3. Step 65 in increments

Each increment keeps a working, tested compiler. Each follows the D43 cycle
(increment, correctness review, compression pass, census in the commit).

| # | Increment | Checked by |
| --- | --- | --- |
| 65.0 | Convert the fork to ATOM source (D44). Stage 1 (done): 29 files with 8.3 names, the conditionals resolved and every one of 2,094 names given an ATOM name under the label convention (`tools/atomize/*.json`), byte-identical to the AZM build; the AZM tree, its translation layer and the proof harness removed. Stage 2: line-by-line commentary, module by module, byte-identical | The ATOM image equals the AZM image; then each commented module leaves it unchanged |
| 65.1 | ~~Move `BLINK`'s CP/M core to a shared directory~~ Withdrawn: `BLINK` is written for ATOM and the compiler in AZM syntax, so sharing source would need a second translation, and it saves no bytes, the programs being separate. The shell takes `BLINK`'s algorithms (name characters, record I/O) in the compiler's dialect | — |
| 65.2 | The `BASIE.COM` shell: a second composition of the forked modules (now `BASIE.ASM` and `SHELL.ASM`) at `$0100` behind a CP/M shell that reads the parts named on the command line into memory, compiles them, prints a diagnostic as `NAME.BSI LINE:COLUMN Error N`, and deletes `A:$$$.SUB` on failure. Output goes to stub sinks. (done: `tests/basie_native_test.ts`; `BASIE.COM` 16,075 bytes, the shell 634 bytes of code and 152 of data) | `BASIE.COM` under the CP/M harness compiles programs of one and several parts from files and reports diagnostics with their part, line and column |
| 65.2b | The library header and key check and the compilation stamp (toolchain §3.1); options in brackets. **Done:** the shell reads the whole command line first (`COMMAND.ASM`): the tail is upper-cased in place (§5.1), the parts' names are parsed into their slots, and every option of §5.3 is read, each at most once, its value checked as `BLINK` checks it (`P` a name, `L` and `S` a drive, `O` a file name of type `COM`, `BIN` or `HEX`, `F` 1 to 255, `STACK` 1 to 65,535, `T` one to four hexadecimal digits and only with `L`; `C` and `X` exclude each other, and `W` is `BLINK`'s alone); a bad, repeated or misplaced option is printed with the reference's text for `L-COMMAND`, as `BLINK` prints it. Then, before any source is read, the library (`LIBRARY.ASM`), option `P`'s or `CPM22.BRL`, is looked for on option `L`'s drive, else the first part's, then on `A:` (§7.3), and its first record and the record of its key table are read: bad magic or version (`L-FORMAT`), an older helper table or another key for the compiler's version (`L-COMPAT`), a file that ends too soon (`L-TRUNCATED`) or none at all (`L-MISSING`) is refused with the reference's text. The directory's header takes the library's runtime and profile identities, as the reference's does, and the helper-table version and key compiled in (`HP_VER`, `HP_KEY`, generated into `HELPERS.ASM`). The stamp follows object format §4.1: an earlier directory's stamp plus one, skipping zero, else the CRC of the first part's first record, its text up to its `$1A`, with `R` folded into its low byte. The reference always writes 1, which §4.1 does not allow, so the equivalence test gives the reference the stamp the native run chose (`CompileOptions.stamp`) and still compares the streams whole, CRCs included. The streams go to the spool drive (`S`) with the first part's name; a failure sets the CP/M 3 return code (`$FF11`, or `$FF13` for a disk). Option `T`'s lookup (§8) is refused as not yet available, and `X` compiles nothing (65.5 chains it). The CP/M harness gained drives (a file on `B:` is keyed `B:NAME.TYP`), and `BLINK`, which had looked for the library and `BASIE.MSG` on `L`'s drive alone, looks on `A:` after it, as §7.3 says (10,876 bytes). `BASIE.COM` 15,897 bytes | Refused libraries and options as the reference toolchain refuses them (`tests/basie_native_test.ts`) |
| 65.3 | The blob writer: routine buffer, in-order reference buffer spilling to `$RF`, and the `$DR`, `$BY`, `$LN` and `$NM` writers with headers, trailers and CRCs (done without the spill: `OUT.ASM`, 236 bytes, and `BLOB.ASM`, 929 bytes, not yet in `BASIE.COM`; `tests/blob_writer_test.ts` writes hello's streams byte-identical to the reference's, links them with `BLINK` and runs the program, and covers every escape, form and line rule against the reference's writers) | Unit programs whose streams the reference linker accepts and links |
| 65.4 | Placed output replaced by blob output whose streams equal the reference compiler's (D45). In stages, each a program set that must match: (a) `sub main()` with an empty body, through BLOB.ASM, with ordinals, the entry and limits records and the D41 prologue and epilogue; (b) top-level variables and constants as data, rodata and bss blobs, with references; (c) 16-bit expressions and assignment in the reference's templates; (d) locals and frames; (e) routine calls, parameters, results and `RETN`; (f) `if`, `while`, `for`, `exit`, `continue`; (g) failure, `fail`, `else fail`, `handle`; (h) records, arrays and strings; (i) services through the compiled-in helper table. Code is generated as it is parsed, not replayed (§2, Streaming); `TARGET.ASM` and the Nucleus runtime identity go. **(a) done:** the shell opens the four streams on the first part's drive and name (options `N`, `M` and `Y` read), names the parts, and closes them; routines without parameters become code blobs with the D41 prologue, success return, exit sequence and frame and need words, and bare `return`; declarations are written as data and bss blobs; the entry and limits records end the directory. `TARGET.ASM`, `TGTWORK.ASM`, `RTSTATE.ASM`, `RTIDENT.ASM`, `GENEXPR.ASM`, `GENCTRL.ASM`, `GENTMPL.ASM`, `GENAGGR.ASM` and the old emitter were deleted, with the shell's output stubs and the bank checks; everything else reaching the transcript is refused (Error 95). Claimed: `EMPTY`, `FAILS`, `SUBS`. `BASIE.COM` 12,379 bytes. **(b) done:** program variables become data or bss blobs and aggregate constants rodata blobs, in declaration order, named in the name stream; a variable's symbol holds its blob's ordinal; constants generate no code until a value is needed, and then load at the destination's type (`GX_TOREG`); assignment loads, widens and stores program variables through `ABS16` references (`GENEXPR.ASM`); a character literal is exact, as spec 9.7 says, where the fork made it a `u8`. Claimed: `DECLS`, `REFS`. `BASIE.COM` 12,381 bytes. **(c) done:** the expression parser generates the reference's code as it reduces: a computed left operand is pushed while the right is computed (`PUSH HL`, or `PUSH AF` for a byte, counted into the frame), and popped beneath a known right (the immediate forms) or a computed one; a known left becomes the immediate after the right (swapped for `-`, `/`, `mod` and the orders); `*`, `/` and `mod` call `MUL16` and `DIV16`, bytes through words; the six relations at both widths and on Booleans; `and` and `or` short-circuit through a routine label after a computed Boolean, and a deciding constant discards the right arm's code (`EX_QUIET`, `EM_QUIET`) while its frame accounting runs, as the reference's `suppress` does; `not`, unary minus, `u8()` with its `TRAP_NAR` check and `u16()`; folding follows the reference (typed results wrap, exact ones stay exact), and an exact value the native compiler cannot represent (below zero or above 65,535) is refused rather than folded differently. Claimed: `WORDS`, `BYTES`, `MIXED`, `COMPARE`, `LOGIC`, `FOLD`, `TRAP`; `TRAP` links with `BLINK` and traps where the reference's build does. Randomly generated assignments (300 in the test, 2,400 more in development) compile to the reference's streams or are refused by both compilers. `BASIE.COM` 12,647 bytes. **(d) done:** a local takes its offset below IX when it is declared, the frame's size with it in, and the frame grows when it is committed, after its initializer, as the reference's `allocLocal` does, so that the initializer's pushes are counted against the frame before it; its value is stored at its type or, without an initializer, its bytes are zeroed (`zeroFrame`); locals and parameters are read and written through the reference's `ixByte`, `ixWord`, `ixStoreA`, `ixStoreHL` and `ixStoreImm`, near as `(IX+d)` and, beyond IX−128..IX+127, through the computed address with the registers kept pushed and counted into the frame (`GX_FACC`, one table entry per access); a local declaration marks its line, as a statement does (`GR_LOCAL`). The symbol table holds 96 records of seven bytes, the aggregate type in the record (the parallel `AG_SYTAB` gone); the dead `EX_LIVE`, `EX_CPOS`, `SY_LSLOT` and `SY_GSLOT` went. Claimed: `LOCALS`, `FARFRAME` (a 144-byte frame with every far form); the random assignments alternate between program variables and locals (3,000 more in development). `BASIE.COM` 12,724 bytes. **(e) done:** a call pushes its arguments left to right, a scalar brought into the registers at its parameter's type and a u8 or Boolean widened to a word, an aggregate as its address (`RO_ROOT` generates a path's root: `LD HL,nn` for program storage and constants, the parameter's word for a parameter); `CALL` the routine, whose exit removes the arguments (`LD IY,n` / `JP RETN`), so the pushes are counted out; the callee's need joins the caller's (`noteCall`); a parameter is used in place at its argument's offset from IX; results come back in `A` or `HL` (an aggregate's address in `HL`, not one rooted at a parameter). Each routine's record (twelve bytes) holds its ordinal, its need once its body is complete, and its argument bytes. A forward routine is published where it is declared, so it takes its ordinal there and its blob where its body is, as the reference's does: `BLOB.ASM` writes each blob when it ends, which is where the reference's list puts it, so no buffering is needed; its prologue checks the stack through its pair label (`LD HL,(need)` / `CALL STK_CHK`), it counts zero in its callers' needs until complete, only it may call itself (`DG_UNMET` otherwise), and the limits record's flag says the program has one. The call frames of `RO_NTAB` became the machine stack; the Nucleus services, whose calls were refused, are now refused where they are named, with their parser and signature table removed. Refused for now: calls to main, a forward main, failable callees (g) and open-string arguments (h). Claimed: `CALLS`, `FORWARD`, `AGGARGS`, `WIDE` (64 parameters, the first beyond IX+127), `RECURSE` (run with `BLINK`: it reaches its final trap only when its results are right), and from the conformance suite `narrowing-traps` and `division-by-zero-traps` (run); the random assignments also go to parameters; ten programs both compilers refuse, among them `no-routine-named-id`, which the native compiler had accepted (a routine may not be named `id`). `BASIE.COM` 12,452 bytes. After (e), a compiler diagnostic or a full disk deletes the four streams, as toolchain §6.2 requires, unless option `K` keeps them (`SH_SCRUB`, 70 bytes of shell; `tests/basie_native_test.ts`). `BASIE.COM` 12,522 bytes. **(f) done:** `if`, `elseif` and `else`, `while`, the counted `for` and `exit` and `continue` generate the reference's code: a condition is `OR A` / `JP Z` to the next arm or the exit, a known false one a `JP`, a known true one nothing; every arm but an else ends in `JP end`, and the last false label and the end are defined together; a while's test is its continue label; a for loop stores its start, keeps its bound in a new two-byte frame slot (at the wider of its type and the counter's, an exact bound a u8 when it fits) that stays allocated until the enclosing block ends, tests the counter against it, and at its next value, where continue goes, goes on only if a step fits in the distance to the bound before storing the new value, a u8 counter trapping `loop-range` if it leaves its type (the native subset has no signed or 32-bit counters, so the reference's `always` and `never` modes cannot arise). Each construct has a sixteen-byte control frame (`CONTROL.ASM`) holding its routine labels, the label count and frame size it restores when it closes (a block frees the bound slots of loops inside it, as the reference's `block` does), and a for loop's mode, counter, bound and step; labels are freed by nesting, and `and` and `or` free theirs when they join (`EM_LFREE`), so the 32 labels of `EM_LCAP` are 32 in use at once. Fallthrough is the reference's: a block starts reachable, `return`, `fail`, `exit` and `continue` end that, an if completes when an arm falls through or it has no else, and loops and handlers always complete; the saved fallthrough per depth (`AC_FLOWS`) went. The program-wide control labels (`CT_LABNO`, `CT_LLIM`) and the transcript operations of control flow went. A loop counter is checked by its full 16-bit offset (`CT_GUARD`). **(g) done:** `fail n` (`PUSH AF` / `POP AF` / `SCF` / `JP exit`), and a call to a failable routine, which decides at once, as the reference does, from the token after it: before `else` (fail) `JP C,exit`, before `handle` `JP C` to a new label, otherwise `DG_LEAK` (`RO_FAILS`); so a failable call may be a right operand or under `not`, and the checks of the fork that it be the whole expression (`EX_PURE`) went. `handle NAME` jumps over the handler on success, drops the temporaries the failure left beneath the call (`POP DE` each, a fault fixed in the reference first), stores the code in the u8 variable and closes as a block. Claimed: `IFS`, `LOOPS`, `FORS`, `FLOW`, `FAILURE`, `RUNFLOW` and from the conformance suite `loop-range-traps` (`LOOPTRAP`); `LOOPS`, `FORS`, `FAILURE`, `RUNFLOW` and `LOOPTRAP` are linked with `BLINK` and run; every fifth random assignment sits in an `if` or a `while`; 32 more programs both compilers refuse. `BASIE.COM` 12,585 bytes. **(h) done:** the runtime helpers' ordinals and stack figures come from the helper table (`HELPERS.ASM`, generated with the reference's by `deno task helpers` and checked by `tests/helper_table_test.ts`), trap sites through `EM_TRAP`. A path is parsed as the reference's designator: a root (a program variable or aggregate constant static, a local in the frame, a parameter an alias through its word, a call's result computed in `HL`), then fields, elements, characters, `length` and an open string's `capacity`; its place is kept (`RO_PLACE`), and each step's code is written as it is parsed (`GENAGGR.ASM`), which the reference's order (fixed first, §5) makes byte-identical: a field or a constant index moves a static, frame or alias place on, or adds to a computed address (`addConst`); a run-time index is brought into `HL`, checked (`CALL NC,TRAP_BND`), scaled and added to the base, which, when computed, is pushed before the index is parsed; a string's character is checked against its length byte and the index's high byte. Scalars are loaded and stored at the place (through a computed address pushed while the value is computed), aggregates copied with `LDIR`, string literals copied into strings and passed to `string[]` parameters, each placed after the need word (16 per routine), open strings passed as their address and capacity word, and aggregate results' fields and elements read; a result may not be rooted in the frame, tracked as the reference's `lastAddressRoot` is (`RO_ESC`). A local may be a record, array or string (the grammar's `local-declaration` takes any type and its initializer is the `LocalInitializer` island): zeroed one byte at a time up to four bytes and with `LDIR` above (`zeroFrame`), given a static initializer stored one `LD (IX+d),n` at a time (`storeBytesToFrame`, the immediate from `GX_IMMV`), or copied from a path or call of its type (`copyToFrame`). An array type takes any number of dimensions, outermost first, built from the innermost once the type is complete (`SaveArrayBound`, `MakeArrayTypes`, eight at most). The type table holds 24 types, 16 records and 48 fields. The rest of the transcript's operations went (`PR_EMITC`, `TR_PUT`, every `OP_` code), with `EX_WIDTH`. Claimed: `PATHS`, `COPIES`, `VIEWS`, `FARPATH` (a record and an open string beyond IX+127), `RUNPATHS` (run: it reaches its last statement's bounds trap only when its results are right), `LOCALAGG`, `GRID` (arrays of arrays, a frame of over a kilobyte), `DISCARD` (paths, literals and short circuits in discarded arms) and the conformance programs `trap-bounds` (`BOUNDS`), `inner-bound-traps` (`INNERBND`) and `recursion-traps` (`RECTRAP`), all three run; the random assignments take fields, elements and characters as operands and targets, the aggregates program variables or locals (6,000 more in development); 32 more programs both compilers refuse. `BASIE.COM` 13,514 bytes. **(i) done:** the predeclared names are the reference's (`ref/compile/helpers.ts`): its 22 constants, exact as the reference's are (the fork made its four error constants `u8`), `console` and `printer`, and its 34 services with their signatures, ordinals and stack figures, generated with the helper table into `PREDEF.ASM` (`HP_NAMES`, by `deno task helpers`; `tests/helper_table_test.ts` checks it is current), which `RO_LIB` searches, so no program may declare one of them. A service is called as a routine is (`RO_SVC`, `RO_ARGS`): its entry is laid out as a routine record from `RO_RTYPE`, its parameters' types a byte apart, and its stack figure is its need. Its arguments are the reference's: a `File`'s four bytes (`PUSH DE`, `PUSH HL`), a string literal or a string for `string[]`, an array of `u8` for `u8[]` with its length as the view's word, and for the `var` forms a writable path (`DG_CONST` otherwise). `File` is a type (`AG_FILE`, four bytes, outside the type table): a program variable, local or parameter, held as a value (a parameter in the frame, writable), loaded into `DEHL` and stored from it at a static or frame place, near or far (`GA_LDF`, `GA_STF`, `GX_DSTQ`); a File value is `console`, `printer`, a service's result or a File variable (`RO_FVAL`), taken only where a File is expected: an argument, an assignment, a File local's initializer. A local may be declared without `as`, taking its initializer's type (the grammar's new row `local-shape` and the island `InferredInitializer`, `AC_INFER`); an exact initializer has no type and is refused, as the reference refuses it. Refused for now (`DG_NYI`): the services with a `u32` parameter or result (`seek`, `position`, `size`), and `File` fields, elements, results and initializers of program variables; a File as an operand, as in a comparison, is `DG_CLASH`. Claimed: `SERVICES`, `FILES` (a File local beyond IX−128, a File parameter written) and twelve conformance programs, `basics/hello`, `services/command-tail`, `console-read-line`, `append-text`, `end-of-run-close`, `end-of-run-abort` and `write-block-bounds`, `expressions/discarded-arm-leaves-no-jumps` and `discarded-arm-leaves-no-literal`, `types/arrays-of-arrays` and `computed-indexes-in-turn`, and `scopes/recursion-with-forward`, all linked with `BLINK` and run with their console input, command tail and files beside the reference's builds, output, return code and files compared; the random assignments take predeclared constants as operands, and a fifth head declares its locals by inference, one from a service's result (6,000 more in development); 28 more programs both compilers refuse, among them a routine, variable, local, parameter, record or constant named after a service or predeclared constant, which the native compiler had accepted. The markers that end the compiler core moved to the top of `SHELL.ASM`. `BASIE.COM` 14,749 bytes | Each stage's programs compile to the reference's streams (shrinking off), link with `BLINK` and run (`tests/native_equivalence_test.ts`) |
| 65.5 | Chaining: the loader at the top of memory runs `BLINK.COM` with the build's tail. **Done** (`CHAIN.ASM`): after a compilation that succeeds, unless option `C` asks for none, and at once for option `X`, the shell writes `BLINK`'s tail at `$0080`, the first part's name as given and the options as given less `X` (never longer than the tail it comes from; `C` and `T` never chain, and `W` is refused), opens `BLINK.COM` on option `L`'s drive or the current one, then on `A:`, and copies a loader of 41 bytes with the open FCB, 77 bytes in all, to the top of memory, below the BDOS entry, with the stack under it. The loader, which refers only to itself and by relative jumps, reads `BLINK.COM` to `$0100` a record at a time (a read error warm boots), restores the DMA address to `$0080` and starts it; `BLINK` takes its stack from `$0006` and sets the final return code. A missing `BLINK.COM` is reported with `L-MISSING`'s text and `$FF12`, the streams kept for a later link. The CP/M harness needed nothing more than its drives: the loader reads `BLINK.COM` through the BDOS as it would on CP/M. `BASIE HELLO` makes `HELLO.COM`, which prints Hello, and `HELLO.LIN`, and deletes the streams; a failing build never chains; `K`, `Z`, `M`, `Y`, `N`, `S` and `O=` reach `BLINK`; `C` then `X` compiles and links in two runs (`tests/basie_native_test.ts`); and the same build runs on real CP/M 2.2 on the Triptych machine (`tests/conformance_triptych_test.ts`). `BASIE.COM` 16,171 bytes | `BASIE HELLO` under the harness produces a `HELLO.COM` that runs |
| 66 | The message file and the overlays. **Done.** (a) Every diagnostic is by the reference's number (`ref/compile/messages.ts`), mapped site by site from the forked codes, at the reference's position, and named where the reference names the name at it (`DG_NAMED`, `DG_SETN`, `DG_WORD`); it is printed as the reference toolchain prints one, `MAIN.BSI 12:5: 27: count is not declared`, the line and column counted from the offset in the resident source, the text from `BASIE.MSG` with its arguments (`MESSAGE.ASM`), or `Message N` and the arguments without it (D39); the toolchain's own diagnostics as `BLINK` prints them, `Error 225: CPM22.BRL not found`. Native refusals of programs the reference accepts are `native-unsupported` (191: constructs not yet compiled, declarations after `main`, locals inside blocks, floating-point literals) and `native-exact` (192: exact values beyond 0..65,535), and native limits `capacity` (190) naming the limit. The 87 collision is gone. The equivalence test compares number, code, position and arguments for all 100 programs both compilers refuse. Nine faults of the reference's positions were fixed, each with a conformance program. (b) The overlays (`OVERLAY.ASM`, `native/compiler/build.ts`): five in `BASIE.OVL`, each assembled at its load address against the resident image's symbols and loaded into the area after the image when first needed: `COMMAND` (986 bytes), `START` (727: the library check, the parts, the stamp and the streams), `NAMES` (947: the predeclared names, loaded before the compilation and kept for all of it, so that every name lookup reads them where they are, as fast as from the resident image; the f32 conversion is to load above them), `CHAIN` (285) and `DIAG` (969). The area is 1,024 bytes. `BASIE.COM` 13,895 bytes | Diagnostics match the reference's (`tests/native_equivalence_test.ts`); `BASIE HELLO` under the harness and on real CP/M 2.2 with `BASIE.OVL` beside `BASIE.COM` |

### Step 67 in stages

Step 67 brings the reference compiler's roadmap steps 38 to 48 across, a
stage at a time, each a set of claimed programs whose streams must equal
the reference's (D45) and the D43 cycle for every increment. The order
follows what the programs need: the library parts (`lib/`) and most of
the conformance suite include `FORMAT.BSI`, which needs the numeric types
and `f32`, so those come early.

| # | Stage | State |
| --- | --- | --- |
| 67a | The reference's step 40 and D33: declarations anywhere and block scope (D28), typed and local constants and inference from typed initialisers (D20, D21), `include` and `private` | **Done.** **67a.1:** the grammar generator, `tools/llgen.ts`, which writes `GRAMMAR.ASM` from `grammar/grammar.json` under the `GR_` scheme (the hand-kept tables reproduced byte for byte first). **67a.2:** a local or a constant may be declared at any statement position (`statement` predicts `var` and `const`; the forked `local-list` is gone, and `EM_LINE` marks the line once, for the statement); each block's names follow its enclosing block's in the symbol table and its end cuts the table back, as its frame shrinks back (`CT_FSYMS`, `CT_BLOCK`), so sibling blocks reuse names and slots as the reference's `block` does; a name in the current block is a duplicate and one visible from outside it is hidden (`SY_HERE`, `RO_BODY`). Declarations may follow `main` (`AC_EARLY` gone; `AC_MAIN` asks `RO_MFLAG`); a second `main`, `sub main` and a forward's full redeclaration are diagnosed as the reference does them, and a completed forward redeclared is a duplicate (the forked check read a record by the wrong index). A scalar constant may be typed (`const k as u8 = 200`), its value staged as an initializer is and its type kept, so it folds and wraps at its type; an untyped constant of a `u16` value needs a type (`constant-needs-type`); a typed integer constant may be a loop's step. Inference follows the reference: a character literal alone is a `u8` (`EX_CHR`), a typed constant gives its type, an aggregate variable, constant or routine result is copied into the local, and a scalar a path selects is loaded as the first primary of the expression that goes on (`EX_PRIME`, `EX_PFROM`). Refused for now: an aggregate constant in a routine's body (its rodata blob would begin inside the routine's) and `assert` statements. A loop's undeclared counter is `loop-counter`, as the reference has it. Claimed: `SCOPES`, `CONSTS`, `INFER`, `LATER` and the conformance programs `declare-anywhere`, `local-constant`, `sibling-blocks-reuse` and `services/keys`, all linked and run; 22 more programs both compilers refuse; the random assignments gain typed constants as operands, locals declared after a statement, and a local in each block of the if and the while (3,000 more in development). `BASIE.COM` 14,098 bytes. **67a.3:** `include` and `private` (D33). The parts are loaded by a new overlay, `PARTS` (`PARTS.ASM`), between the library check and the streams, which stay in `START` (`LIBRARY.ASM`, entered twice): each part the command line names, unless a part loaded already included it, and, depth first, every part it includes. A part is read whole, through the blob writer's buffer, then its include lines with the tokenizer: `include`, a string that decodes to a CP/M name with its type (`CL_NAME`, moved to `FILENAME.ASM` for both overlays that need it), and the line's end; the name is looked for on the including part's drive, then on option L's or `A:`, or on its own drive alone; a part already loaded is not loaded again, and one whose include lines are still being read is a cycle; the tokenizer's state is kept on the stack while an included part loads, 16 deep. A part takes its number in the stream once its includes are loaded, so it follows them, and its body, where its compilation begins, follows its last include line. The parts are described in a part table (`SOURCE.ASM`) of 21-byte entries, growing down from the top of the source area as the parts' bytes grow up: the part's name, its bytes, its body's offset and line, and its number; the eight-part table and the packed `SRC_LEFT` went, so a compilation takes 255 parts while memory lasts. `SRC_ID` is a part's entry, which diagnostics name, and `SRC_NUM` its number, which the line stream records; `TK_ATEND` steps to the next number (`SRC_BODY`), and `DG_SRC` finds a part by its address in any order. An `include` the compilation meets is `include-position` (`LL1.ASM`): the loader read those before the first declaration. `private` marks a top-level declaration: a bit for each symbol (`SY_PRIV`) and a flag in each routine record (`RO_FPRIV`); at each declaration (`AC_TOP`) a part that has ended has its private forwards checked, an open one being `forward-incomplete` at its `forward`, and its private names cut to no characters (`AC_ENDP`); a declaration must end in the part it began in (`AC_SPLIT`); a completion's visibility must be its forward's, and `main` can't be private. `var` parameters and `assert` statements are refused by the grammar (191). The reference accepted a wildcard in an include's name, which spec 4.3.2 calls `include-syntax`, and named no argument for `include-missing` and `include-cycle`: both fixed, with conformance programs. Claimed: `INCMAIN` (three parts, one included twice, privates of the same name in two, a forward one part declares and another completes) and the conformance programs `include-once`, `private-across-parts` and `private-is-part-local`; 13 more programs both compilers refuse, the part of the diagnostic compared too. The programs of the suite that include the library are not yet in reach: `STRINGS.BSI` has `var` parameters (67e) and `FORMAT.BSI` the numeric types and `f32` (67b, 67f). `BASIE.COM` 14,439 bytes |
| 67b | Numeric types: `i8`, `i16`, `u32`, `i32`, the conversions and shifts, 32-bit folding (the 16-bit exact range goes) | — |
| 67c | Branch shrinking: forward jumps to `JR`, so the equivalence test compiles the reference with shrinking on | — |
| 67d | `select` | — |
| 67e | Local aggregates in full, `var` parameters and results, `assert` | — |
| 67f | `f32`: the decimal-to-`f32` overlay above `NAMES` | — |
| 67g | Pools, handles, flow, leases and ownership | — |
| 67h | The capacity tables: the hashed symbol table with a name heap, the scoped type descriptors, streaming the source | — |

## 4. Budget

| Stage | Change | Projected size |
| --- | --- | ---: |
| Fork (step 64) | measured | 15.3K |
| Step 65 | −2.3K placed output, banking, startup and trap endings; +1.9K CP/M core; +0.45K chain, stamp and library check; +0.9K blob, line and name writers; +0.3K `frame`/`need` and helper stack table; +0.3K table widening | 17.0–17.6K; measured at its end, 16,171 bytes, of which the command line, the library check and stamp and the chain, for the overlay, take 1.6K (`COMMAND.ASM` 836, `LIBRARY.ASM` 488, `CHAIN.ASM` 266) and the predeclared names 0.9K |
| Step 66 | message file and overlay loader | about 18K; measured, 13,895 bytes resident and a 1,024-byte overlay area: the one-shot code, the diagnostics and the predeclared names left the image |
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
| `LL1.ASM`, `CALLWORK.ASM` | `DG_LLCAP` and `DG_LEAK` share the number 87 | fixed at step 66: every code is the reference's number; `DG_LEAK` is `failure-unconsumed` (113) and `DG_LLCAP` the native capacity `grammar stack` (190) |
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
names were still Nucleus's six services and four error constants, so a
program that names a routine after one of the reference's services or
predeclared constants (`size`, `close`, `console`, `fileNotFound`) was
accepted natively and refused by the reference; the full table came with
the services at 65.4 (i), and the four constants, which the fork made
`u8`, became exact.

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
global only because their code spans several labels (`TK_TRAIL`, `RO_SEL` (gone at 65.4 h),
`RG_FORK` and others), which become private when their routines are made one
scope; names in the wrong area (`EM_LDDE` in `GENCTRL.ASM`, `EX_EFLOW` used by
the actions, `TG_` routines in `ROUTINES.ASM`); vague or figurative words
(`EX_PEAK`, `EX_PURE`, `EX_MUTE`, `AG_FITRW`); look-alike pairs (`AC_LIVE` and
`AC_LIVEN`, `GC_TEST` and `GX_TEST`); and fields reused for several meanings
(`RO_ACNT`, `RO_DEST`).
