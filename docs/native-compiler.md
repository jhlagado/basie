# The native compiler: `BASIE.COM` in stages

- Status: working plan for roadmap steps 65 to 67
- Date: 2026-10-05
- Related: [implementation plan](implementation-plan.md) Phase 6,
  [roadmap](roadmap.md) M7, [code generation](code-generation.md) (D41),
  [object format](object-format.md), [toolchain](toolchain.md),
  [capacity audit](capacity-audit.md) §4, D43 (budget)

## 1. The starting core

At step 64, `native/compiler/` held a working compiler core for the base
language, in AZM syntax; at step 65.0 it became ATOM source (D44), with the
file names below. The core measured 15,286 bytes. A compilation ran in
three phases that never overlapped:

1. **Parse.** The LL(1) engine parsed every source part and appended
   operations to a semantic transcript.
2. **Close.** The transcript was published.
3. **Emit.** The transcript was replayed through a dispatch table into placed
   Z80 code. Forward operands went to a global fixup table that was resolved
   at the end.

Because the phases were disjoint, the workspace overlaid them: the emit state
reused the parser's stacks. The workspace was 3,609 bytes, about 2K of it the
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

## 2. From the starting core to Basie's design

**Output.** The starting core was its own linker: it laid out the runtime,
startup code and program at final addresses. Basie emits blobs: one per
routine, variable and constant, with ordinals and references that `BLINK`
resolves. Every site that computed an absolute address became a reference:

| Address kind | Starting core | Basie |
| --- | --- | --- |
| Program variable | data base + offset | `ABS16` to the variable's ordinal, plus an addend |
| Aggregate constant | read-only base + offset | `ABS16` to a `rodata` ordinal |
| Runtime helper | runtime base + identity offset | `ABS16` to the helper's ordinal |
| Routine | 5-bit label ordinal | 16-bit ordinal from `$0400` |
| Branch inside a routine | global absolute fixup | self-reference `ABS16` with the offset as addend, or `JR` after shrinking |
| Startup, data copy, `bss` clear | emitted by the compiler | the library's startup blob and the `ENTRY` record |

One primitive, `EmitRef(form, ordinal, addend)`, replaces them all. It writes a
zero placeholder and appends the reference to the routine's in-order buffer.

**Routines.** The starting core kept frames on the hardware stack with `IX`,
as D41 does. It differed in these ways:

- It copied parameters into the frame.
- It evaluated as a pure stack machine.
- The caller popped arguments.
- It counted activations against an arena of 8.
- Each trap site took about 37 inline bytes.

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

**Tables.** Every table of the starting core was proof-sized
([capacity audit](capacity-audit.md) §4); the worst were a 16-entry symbol
table and the 511-byte transcript. Each is replaced at the stage that first
needs it, and the audit and the limits register are updated in the same commit.

**Source.** The parts stay resident for the whole compilation. At 67a, which brought `include` and so many more parts, the
choice between keeping them resident and streaming them with a name heap
was made for keeping them, for now: every record that names something
(symbols, routines, parameters, fields, string literals) points at its
spelling in the source, and a diagnostic's line and column are counted
from the source; streaming would need a heap for every name and a
diagnostic that reads the part again. The source area is about 29.75K on
a 62K system and the whole standard library 17.4K, so programs that
include all of it still fit. The move is planned with the capacity tables
(67h), whose hashed symbol table needs the name heap anyway, and before
the image's growth toward the 26K target moves the workspace up and the
source area shrinks toward 22K.

**Grammar encoding.** The packed LL(1) tables give terminals `$00` to `$3F`:
64 kinds. Basie has 55 keywords, 17 punctuators and 7 other token kinds, 79 in
all. The plan is to fold token classes so that the grammar never needs the
widening:

- one terminal for every type keyword, with the type in the token's value;
- one terminal each for the multiplicative, additive and relational operator
  classes, read inside the expression island.

That brings the count to about 60. The generator (67a.1, `tools/llgen.ts`)
writes ATOM under the label convention ([naming](naming.md)): `GR_ROWn` prediction
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
the grammar names 44 (`private` the newest) of the 57 token kinds; the type
keywords still have one terminal each. At 67b the type keywords were folded
into one terminal, `TK_TYPE`, whose payload is the type, as planned: five
more terminals would have fitted the 64, but the expression islands' FIRST
sets take every terminal that begins a conversion, and the prediction rows
passed the 255 bytes their one-byte offsets reach. The grammar now names 42
terminals; the count is recorded in `tests/llgen_test.ts`, which fails past
64. At 67e the rows were full again: a result's `from` clause is an island
(`FromClause`) whose FIRST set lists `Empty`, so that it may consume
nothing, rather than two rows of its own. At 67d `select` and `case` took
the last two kinds below `$40` (61 and 62: a kind's syntax diagnostic is
`DG_TOKEN` plus it, below 190, and `select` is never expected alone), and
`include`, `some`, `none` and `move`, which the grammar never names, moved
above them; the rows passed 256 bytes again (276), so the generator now
lays out the rows from the first that starts 256 bytes or more from
`GR_ROWS` on (`GR_RHIGH`) at offsets from the page after it, which costs
the engine five bytes. The grammar names 44 terminals.

**Decided before 67f.** Every kind below 62 was then taken, by 43 of the
terminals (`select`, never expected alone, has 62), the five pseudo-kinds
of the syntax diagnostics and the 14 tokens only the expression island
and the path parser read, and stage 67g needs `pool`,
`new` and the handles' words. Three ways were weighed: folding more token
classes into one terminal with the class in the token's value (the
relational, additive and multiplicative operators), which would change
how the expression parser reads them; widening the encoding to two bytes
a symbol, which would grow the tables and the engine; and taking the
island-only tokens out of the grammar's ordinals, which the decision at
67a already allowed. The last was chosen, the smallest coherent change:
`or`, `*`, `shl`, `shr`, `/`, the five orders and `<>`, `and`, `.`, `xor`
and `mod` took kinds `$44` to `$51` (keeping the runs the code relies on,
`*` to `shr`, `/` to `<>` and `xor` to `mod`), which no byte of the image
depends on beyond the kinds themselves: the image kept its size, 17,963
bytes. Fourteen kinds below 62 are free (10, 26 to 28, 32 to 37, 39, 50,
53 and 54), and 63 for a terminal never expected alone;
`tests/llgen_test.ts` checks that no other token takes a grammar ordinal
and counts the free ones. The relational, additive and multiplicative
folding stays available should 67g need more.

## 3. Step 65 in increments

Each increment keeps a working, tested compiler. Each follows the D43 cycle
(increment, correctness review, compression pass, census in the commit).

| # | Increment | Checked by |
| --- | --- | --- |
| 65.0 | Convert the compiler to ATOM source (D44). Stage 1 (done): 29 files with 8.3 names, the conditionals resolved and every one of 2,094 names given an ATOM name under the label convention ([naming](naming.md)), byte-identical to the AZM build; the AZM tree, its translation layer and the proof harness removed. Stage 2: line-by-line commentary, module by module, byte-identical | The ATOM image equals the AZM image; then each commented module leaves it unchanged |
| 65.1 | ~~Move `BLINK`'s CP/M core to a shared directory~~ Withdrawn: `BLINK` is written for ATOM and the compiler in AZM syntax, so sharing source would need a second translation, and it saves no bytes, the programs being separate. The shell takes `BLINK`'s algorithms (name characters, record I/O) in the compiler's dialect | — |
| 65.2 | The `BASIE.COM` shell: a second composition of the compiler's modules (now `BASIE.ASM` and `SHELL.ASM`) at `$0100` behind a CP/M shell that reads the parts named on the command line into memory, compiles them, prints a diagnostic as `NAME.BSI LINE:COLUMN Error N`, and deletes `A:$$$.SUB` on failure. Output goes to stub sinks. (done: `tests/basie_native_test.ts`; `BASIE.COM` 16,075 bytes, the shell 634 bytes of code and 152 of data) | `BASIE.COM` under the CP/M harness compiles programs of one and several parts from files and reports diagnostics with their part, line and column |
| 65.2b | The library header and key check and the compilation stamp (toolchain §3.1); options in brackets. **Done:** the shell reads the whole command line first (`COMMAND.ASM`): the tail is upper-cased in place (§5.1), the parts' names are parsed into their slots, and every option of §5.3 is read, each at most once, its value checked as `BLINK` checks it (`P` a name, `L` and `S` a drive, `O` a file name of type `COM`, `BIN` or `HEX`, `F` 1 to 255, `STACK` 1 to 65,535, `T` one to four hexadecimal digits and only with `L`; `C` and `X` exclude each other, and `W` is `BLINK`'s alone); a bad, repeated or misplaced option is printed with the reference's text for `L-COMMAND`, as `BLINK` prints it. Then, before any source is read, the library (`LIBRARY.ASM`), option `P`'s or `CPM22.BRL`, is looked for on option `L`'s drive, else the first part's, then on `A:` (§7.3), and its first record and the record of its key table are read: bad magic or version (`L-FORMAT`), an older helper table or another key for the compiler's version (`L-COMPAT`), a file that ends too soon (`L-TRUNCATED`) or none at all (`L-MISSING`) is refused with the reference's text. The directory's header takes the library's runtime and profile identities, as the reference's does, and the helper-table version and key compiled in (`HP_VER`, `HP_KEY`, generated into `HELPERS.ASM`). The stamp follows object format §4.1: an earlier directory's stamp plus one, skipping zero, else the CRC of the first part's first record, its text up to its `$1A`, with `R` folded into its low byte. The reference always writes 1, which §4.1 does not allow, so the equivalence test gives the reference the stamp the native run chose (`CompileOptions.stamp`) and still compares the streams whole, CRCs included. The streams go to the spool drive (`S`) with the first part's name; a failure sets the CP/M 3 return code (`$FF11`, or `$FF13` for a disk). Option `T`'s lookup (§8) is refused as not yet available, and `X` compiles nothing (65.5 chains it). The CP/M harness gained drives (a file on `B:` is keyed `B:NAME.TYP`), and `BLINK`, which had looked for the library and `BASIE.MSG` on `L`'s drive alone, looks on `A:` after it, as §7.3 says (10,876 bytes). `BASIE.COM` 15,897 bytes | Refused libraries and options as the reference toolchain refuses them (`tests/basie_native_test.ts`) |
| 65.3 | The blob writer: routine buffer, in-order reference buffer spilling to `$RF`, and the `$DR`, `$BY`, `$LN` and `$NM` writers with headers, trailers and CRCs (done without the spill: `OUT.ASM`, 236 bytes, and `BLOB.ASM`, 929 bytes, not yet in `BASIE.COM`; `tests/blob_writer_test.ts` writes hello's streams byte-identical to the reference's, links them with `BLINK` and runs the program, and covers every escape, form and line rule against the reference's writers) | Unit programs whose streams the reference linker accepts and links |
| 65.4 | Placed output replaced by blob output whose streams equal the reference compiler's (D45). In stages, each a program set that must match: (a) `sub main()` with an empty body, through BLOB.ASM, with ordinals, the entry and limits records and the D41 prologue and epilogue; (b) top-level variables and constants as data, rodata and bss blobs, with references; (c) 16-bit expressions and assignment in the reference's templates; (d) locals and frames; (e) routine calls, parameters, results and `RETN`; (f) `if`, `while`, `for`, `exit`, `continue`; (g) failure, `fail`, `else fail`, `handle`; (h) records, arrays and strings; (i) services through the compiled-in helper table. Code is generated as it is parsed, not replayed (§2, Streaming); `TARGET.ASM` and the placed runtime's identity go. **(a) done:** the shell opens the four streams on the first part's drive and name (options `N`, `M` and `Y` read), names the parts, and closes them; routines without parameters become code blobs with the D41 prologue, success return, exit sequence and frame and need words, and bare `return`; declarations are written as data and bss blobs; the entry and limits records end the directory. `TARGET.ASM`, `TGTWORK.ASM`, `RTSTATE.ASM`, `RTIDENT.ASM`, `GENEXPR.ASM`, `GENCTRL.ASM`, `GENTMPL.ASM`, `GENAGGR.ASM` and the old emitter were deleted, with the shell's output stubs and the bank checks; everything else reaching the transcript is refused (Error 95). Claimed: `EMPTY`, `FAILS`, `SUBS`. `BASIE.COM` 12,379 bytes. **(b) done:** program variables become data or bss blobs and aggregate constants rodata blobs, in declaration order, named in the name stream; a variable's symbol holds its blob's ordinal; constants generate no code until a value is needed, and then load at the destination's type (`GX_TOREG`); assignment loads, widens and stores program variables through `ABS16` references (`GENEXPR.ASM`); a character literal is exact, as spec 9.7 says, where it had been a `u8`. Claimed: `DECLS`, `REFS`. `BASIE.COM` 12,381 bytes. **(c) done:** the expression parser generates the reference's code as it reduces: a computed left operand is pushed while the right is computed (`PUSH HL`, or `PUSH AF` for a byte, counted into the frame), and popped beneath a known right (the immediate forms) or a computed one; a known left becomes the immediate after the right (swapped for `-`, `/`, `mod` and the orders); `*`, `/` and `mod` call `MUL16` and `DIV16`, bytes through words; the six relations at both widths and on Booleans; `and` and `or` short-circuit through a routine label after a computed Boolean, and a deciding constant discards the right arm's code (`EX_QUIET`, `EM_QUIET`) while its frame accounting runs, as the reference's `suppress` does; `not`, unary minus, `u8()` with its `TRAP_NAR` check and `u16()`; folding follows the reference (typed results wrap, exact ones stay exact), and an exact value the native compiler cannot represent (below zero or above 65,535) is refused rather than folded differently. Claimed: `WORDS`, `BYTES`, `MIXED`, `COMPARE`, `LOGIC`, `FOLD`, `TRAP`; `TRAP` links with `BLINK` and traps where the reference's build does. Randomly generated assignments (300 in the test, 2,400 more in development) compile to the reference's streams or are refused by both compilers. `BASIE.COM` 12,647 bytes. **(d) done:** a local takes its offset below IX when it is declared, the frame's size with it in, and the frame grows when it is committed, after its initializer, as the reference's `allocLocal` does, so that the initializer's pushes are counted against the frame before it; its value is stored at its type or, without an initializer, its bytes are zeroed (`zeroFrame`); locals and parameters are read and written through the reference's `ixByte`, `ixWord`, `ixStoreA`, `ixStoreHL` and `ixStoreImm`, near as `(IX+d)` and, beyond IX−128..IX+127, through the computed address with the registers kept pushed and counted into the frame (`GX_FACC`, one table entry per access); a local declaration marks its line, as a statement does (`GR_LOCAL`). The symbol table holds 96 records of seven bytes, the aggregate type in the record (the parallel `AG_SYTAB` gone); the dead `EX_LIVE`, `EX_CPOS`, `SY_LSLOT` and `SY_GSLOT` went. Claimed: `LOCALS`, `FARFRAME` (a 144-byte frame with every far form); the random assignments alternate between program variables and locals (3,000 more in development). `BASIE.COM` 12,724 bytes. **(e) done:** a call pushes its arguments left to right, a scalar brought into the registers at its parameter's type and a u8 or Boolean widened to a word, an aggregate as its address (`RO_ROOT` generates a path's root: `LD HL,nn` for program storage and constants, the parameter's word for a parameter); `CALL` the routine, whose exit removes the arguments (`LD IY,n` / `JP RETN`), so the pushes are counted out; the callee's need joins the caller's (`noteCall`); a parameter is used in place at its argument's offset from IX; results come back in `A` or `HL` (an aggregate's address in `HL`, not one rooted at a parameter). Each routine's record (twelve bytes) holds its ordinal, its need once its body is complete, and its argument bytes. A forward routine is published where it is declared, so it takes its ordinal there and its blob where its body is, as the reference's does: `BLOB.ASM` writes each blob when it ends, which is where the reference's list puts it, so no buffering is needed; its prologue checks the stack through its pair label (`LD HL,(need)` / `CALL STK_CHK`), it counts zero in its callers' needs until complete, only it may call itself (`DG_UNMET` otherwise), and the limits record's flag says the program has one. The call frames of `RO_NTAB` became the machine stack; the starting core's own services, whose calls were refused, are now refused where they are named, with their parser and signature table removed. Refused for now: calls to main, a forward main, failable callees (g) and open-string arguments (h). Claimed: `CALLS`, `FORWARD`, `AGGARGS`, `WIDE` (64 parameters, the first beyond IX+127), `RECURSE` (run with `BLINK`: it reaches its final trap only when its results are right), and from the conformance suite `narrowing-traps` and `division-by-zero-traps` (run); the random assignments also go to parameters; ten programs both compilers refuse, among them `no-routine-named-id`, which the native compiler had accepted (a routine may not be named `id`). `BASIE.COM` 12,452 bytes. After (e), a compiler diagnostic or a full disk deletes the four streams, as toolchain §6.2 requires, unless option `K` keeps them (`SH_SCRUB`, 70 bytes of shell; `tests/basie_native_test.ts`). `BASIE.COM` 12,522 bytes. **(f) done:** `if`, `elseif` and `else`, `while`, the counted `for` and `exit` and `continue` generate the reference's code: a condition is `OR A` / `JP Z` to the next arm or the exit, a known false one a `JP`, a known true one nothing; every arm but an else ends in `JP end`, and the last false label and the end are defined together; a while's test is its continue label; a for loop stores its start, keeps its bound in a new two-byte frame slot (at the wider of its type and the counter's, an exact bound a u8 when it fits) that stays allocated until the enclosing block ends, tests the counter against it, and at its next value, where continue goes, goes on only if a step fits in the distance to the bound before storing the new value, a u8 counter trapping `loop-range` if it leaves its type (the native subset has no signed or 32-bit counters, so the reference's `always` and `never` modes cannot arise). Each construct has a sixteen-byte control frame (`CONTROL.ASM`) holding its routine labels, the label count and frame size it restores when it closes (a block frees the bound slots of loops inside it, as the reference's `block` does), and a for loop's mode, counter, bound and step; labels are freed by nesting, and `and` and `or` free theirs when they join (`EM_LFREE`), so the 32 labels of `EM_LCAP` are 32 in use at once. Fallthrough is the reference's: a block starts reachable, `return`, `fail`, `exit` and `continue` end that, an if completes when an arm falls through or it has no else, and loops and handlers always complete; the saved fallthrough per depth (`AC_FLOWS`) went. The program-wide control labels (`CT_LABNO`, `CT_LLIM`) and the transcript operations of control flow went. A loop counter is checked by its full 16-bit offset (`CT_GUARD`). **(g) done:** `fail n` (`PUSH AF` / `POP AF` / `SCF` / `JP exit`), and a call to a failable routine, which decides at once, as the reference does, from the token after it: before `else` (fail) `JP C,exit`, before `handle` `JP C` to a new label, otherwise `DG_LEAK` (`RO_FAILS`); so a failable call may be a right operand or under `not`, and the checks that it be the whole expression (`EX_PURE`) went. `handle NAME` jumps over the handler on success, drops the temporaries the failure left beneath the call (`POP DE` each, a fault fixed in the reference first), stores the code in the u8 variable and closes as a block. Claimed: `IFS`, `LOOPS`, `FORS`, `FLOW`, `FAILURE`, `RUNFLOW` and from the conformance suite `loop-range-traps` (`LOOPTRAP`); `LOOPS`, `FORS`, `FAILURE`, `RUNFLOW` and `LOOPTRAP` are linked with `BLINK` and run; every fifth random assignment sits in an `if` or a `while`; 32 more programs both compilers refuse. `BASIE.COM` 12,585 bytes. **(h) done:** the runtime helpers' ordinals and stack figures come from the helper table (`HELPERS.ASM`, generated with the reference's by `deno task helpers` and checked by `tests/helper_table_test.ts`), trap sites through `EM_TRAP`. A path is parsed as the reference's designator: a root (a program variable or aggregate constant static, a local in the frame, a parameter an alias through its word, a call's result computed in `HL`), then fields, elements, characters, `length` and an open string's `capacity`; its place is kept (`RO_PLACE`), and each step's code is written as it is parsed (`GENAGGR.ASM`), which the reference's order (fixed first, §5) makes byte-identical: a field or a constant index moves a static, frame or alias place on, or adds to a computed address (`addConst`); a run-time index is brought into `HL`, checked (`CALL NC,TRAP_BND`), scaled and added to the base, which, when computed, is pushed before the index is parsed; a string's character is checked against its length byte and the index's high byte. Scalars are loaded and stored at the place (through a computed address pushed while the value is computed), aggregates copied with `LDIR`, string literals copied into strings and passed to `string[]` parameters, each placed after the need word (16 per routine), open strings passed as their address and capacity word, and aggregate results' fields and elements read; a result may not be rooted in the frame, tracked as the reference's `lastAddressRoot` is (`RO_ESC`). A local may be a record, array or string (the grammar's `local-declaration` takes any type and its initializer is the `LocalInitializer` island): zeroed one byte at a time up to four bytes and with `LDIR` above (`zeroFrame`), given a static initializer stored one `LD (IX+d),n` at a time (`storeBytesToFrame`, the immediate from `GX_IMMV`), or copied from a path or call of its type (`copyToFrame`). An array type takes any number of dimensions, outermost first, built from the innermost once the type is complete (`SaveArrayBound`, `MakeArrayTypes`, eight at most). The type table holds 24 types, 16 records and 48 fields. The rest of the transcript's operations went (`PR_EMITC`, `TR_PUT`, every `OP_` code), with `EX_WIDTH`. Claimed: `PATHS`, `COPIES`, `VIEWS`, `FARPATH` (a record and an open string beyond IX+127), `RUNPATHS` (run: it reaches its last statement's bounds trap only when its results are right), `LOCALAGG`, `GRID` (arrays of arrays, a frame of over a kilobyte), `DISCARD` (paths, literals and short circuits in discarded arms) and the conformance programs `trap-bounds` (`BOUNDS`), `inner-bound-traps` (`INNERBND`) and `recursion-traps` (`RECTRAP`), all three run; the random assignments take fields, elements and characters as operands and targets, the aggregates program variables or locals (6,000 more in development); 32 more programs both compilers refuse. `BASIE.COM` 13,514 bytes. **(i) done:** the predeclared names are the reference's (`ref/compile/helpers.ts`): its 22 constants, exact as the reference's are (its four error constants had been `u8`), `console` and `printer`, and its 34 services with their signatures, ordinals and stack figures, generated with the helper table into `PREDEF.ASM` (`HP_NAMES`, by `deno task helpers`; `tests/helper_table_test.ts` checks it is current), which `RO_LIB` searches, so no program may declare one of them. A service is called as a routine is (`RO_SVC`, `RO_ARGS`): its entry is laid out as a routine record from `RO_RTYPE`, its parameters' types a byte apart, and its stack figure is its need. Its arguments are the reference's: a `File`'s four bytes (`PUSH DE`, `PUSH HL`), a string literal or a string for `string[]`, an array of `u8` for `u8[]` with its length as the view's word, and for the `var` forms a writable path (`DG_CONST` otherwise). `File` is a type (`AG_FILE`, four bytes, outside the type table): a program variable, local or parameter, held as a value (a parameter in the frame, writable), loaded into `DEHL` and stored from it at a static or frame place, near or far (`GA_LDF`, `GA_STF`, `GX_DSTQ`); a File value is `console`, `printer`, a service's result or a File variable (`RO_FVAL`), taken only where a File is expected: an argument, an assignment, a File local's initializer. A local may be declared without `as`, taking its initializer's type (the grammar's new row `local-shape` and the island `InferredInitializer`, `AC_INFER`); an exact initializer has no type and is refused, as the reference refuses it. Refused for now (`DG_NYI`): the services with a `u32` parameter or result (`seek`, `position`, `size`), and `File` fields, elements, results and initializers of program variables; a File as an operand, as in a comparison, is `DG_CLASH`. Claimed: `SERVICES`, `FILES` (a File local beyond IX−128, a File parameter written) and twelve conformance programs, `basics/hello`, `services/command-tail`, `console-read-line`, `append-text`, `end-of-run-close`, `end-of-run-abort` and `write-block-bounds`, `expressions/discarded-arm-leaves-no-jumps` and `discarded-arm-leaves-no-literal`, `types/arrays-of-arrays` and `computed-indexes-in-turn`, and `scopes/recursion-with-forward`, all linked with `BLINK` and run with their console input, command tail and files beside the reference's builds, output, return code and files compared; the random assignments take predeclared constants as operands, and a fifth head declares its locals by inference, one from a service's result (6,000 more in development); 28 more programs both compilers refuse, among them a routine, variable, local, parameter, record or constant named after a service or predeclared constant, which the native compiler had accepted. The markers that end the compiler core moved to the top of `SHELL.ASM`. `BASIE.COM` 14,749 bytes | Each stage's programs compile to the reference's streams (shrinking off), link with `BLINK` and run (`tests/native_equivalence_test.ts`) |
| 65.5 | Chaining: the loader at the top of memory runs `BLINK.COM` with the build's tail. **Done** (`CHAIN.ASM`): after a compilation that succeeds, unless option `C` asks for none, and at once for option `X`, the shell writes `BLINK`'s tail at `$0080`, the first part's name as given and the options as given less `X` (never longer than the tail it comes from; `C` and `T` never chain, and `W` is refused), opens `BLINK.COM` on option `L`'s drive or the current one, then on `A:`, and copies a loader of 41 bytes with the open FCB, 77 bytes in all, to the top of memory, below the BDOS entry, with the stack under it. The loader, which refers only to itself and by relative jumps, reads `BLINK.COM` to `$0100` a record at a time (a read error warm boots), restores the DMA address to `$0080` and starts it; `BLINK` takes its stack from `$0006` and sets the final return code. A missing `BLINK.COM` is reported with `L-MISSING`'s text and `$FF12`, the streams kept for a later link. The CP/M harness needed nothing more than its drives: the loader reads `BLINK.COM` through the BDOS as it would on CP/M. `BASIE HELLO` makes `HELLO.COM`, which prints Hello, and `HELLO.LIN`, and deletes the streams; a failing build never chains; `K`, `Z`, `M`, `Y`, `N`, `S` and `O=` reach `BLINK`; `C` then `X` compiles and links in two runs (`tests/basie_native_test.ts`); and the same build runs on real CP/M 2.2 on the Triptych machine (`tests/conformance_triptych_test.ts`). `BASIE.COM` 16,171 bytes | `BASIE HELLO` under the harness produces a `HELLO.COM` that runs |
| 66 | The message file and the overlays. **Done.** (a) Every diagnostic is by the reference's number (`ref/compile/messages.ts`), mapped site by site from the earlier codes, at the reference's position, and named where the reference names the name at it (`DG_NAMED`, `DG_SETN`, `DG_WORD`); it is printed as the reference toolchain prints one, `MAIN.BSI 12:5: 27: count is not declared`, the line and column counted from the offset in the resident source, the text from `BASIE.MSG` with its arguments (`MESSAGE.ASM`), or `Message N` and the arguments without it (D39); the toolchain's own diagnostics as `BLINK` prints them, `Error 225: CPM22.BRL not found`. Native refusals of programs the reference accepts are `native-unsupported` (191: constructs not yet compiled, declarations after `main`, locals inside blocks, floating-point literals) and `native-exact` (192: exact values beyond 0..65,535), and native limits `capacity` (190) naming the limit. The 87 collision is gone. The equivalence test compares number, code, position and arguments for all 100 programs both compilers refuse. Nine faults of the reference's positions were fixed, each with a conformance program. (b) The overlays (`OVERLAY.ASM`, `native/compiler/build.ts`): five in `BASIE.OVL`, each assembled at its load address against the resident image's symbols and loaded into the area after the image when first needed: `COMMAND` (986 bytes), `START` (727: the library check, the parts, the stamp and the streams), `NAMES` (947: the predeclared names, loaded before the compilation and kept for all of it, so that every name lookup reads them where they are, as fast as from the resident image; the f32 conversion is to load above them), `CHAIN` (285) and `DIAG` (969). The area is 1,024 bytes. `BASIE.COM` 13,895 bytes | Diagnostics match the reference's (`tests/native_equivalence_test.ts`); `BASIE HELLO` under the harness and on real CP/M 2.2 with `BASIE.OVL` beside `BASIE.COM` |

### Step 67 in stages

Step 67 brings the reference compiler's roadmap steps 38 to 48 across, a
stage at a time, each a set of claimed programs whose streams must equal
the reference's (D45) and the D43 cycle for every increment. The order
follows what the programs need: the library parts (`lib/`) and most of
the conformance suite include `FORMAT.BSI`, which needs the numeric types
and `f32`, so those come early.

| # | Stage | State |
| --- | --- | --- |
| 67a | The reference's step 40 and D33: declarations anywhere and block scope (D28), typed and local constants and inference from typed initialisers (D20, D21), `include` and `private` | **Done.** **67a.1:** the grammar generator, `tools/llgen.ts`, which writes `GRAMMAR.ASM` from `grammar/grammar.json` under the `GR_` scheme (the hand-kept tables reproduced byte for byte first). **67a.2:** a local or a constant may be declared at any statement position (`statement` predicts `var` and `const`; the old `local-list` is gone, and `EM_LINE` marks the line once, for the statement); each block's names follow its enclosing block's in the symbol table and its end cuts the table back, as its frame shrinks back (`CT_FSYMS`, `CT_BLOCK`), so sibling blocks reuse names and slots as the reference's `block` does; a name in the current block is a duplicate and one visible from outside it is hidden (`SY_HERE`, `RO_BODY`). Declarations may follow `main` (`AC_EARLY` gone; `AC_MAIN` asks `RO_MFLAG`); a second `main`, `sub main` and a forward's full redeclaration are diagnosed as the reference does them, and a completed forward redeclared is a duplicate (the earlier check read a record by the wrong index). A scalar constant may be typed (`const k as u8 = 200`), its value staged as an initializer is and its type kept, so it folds and wraps at its type; an untyped constant of a `u16` value needs a type (`constant-needs-type`); a typed integer constant may be a loop's step. Inference follows the reference: a character literal alone is a `u8` (`EX_CHR`), a typed constant gives its type, an aggregate variable, constant or routine result is copied into the local, and a scalar a path selects is loaded as the first primary of the expression that goes on (`EX_PRIME`, `EX_PFROM`). Refused for now: an aggregate constant in a routine's body (its rodata blob would begin inside the routine's) and `assert` statements. A loop's undeclared counter is `loop-counter`, as the reference has it. Claimed: `SCOPES`, `CONSTS`, `INFER`, `LATER` and the conformance programs `declare-anywhere`, `local-constant`, `sibling-blocks-reuse` and `services/keys`, all linked and run; 22 more programs both compilers refuse; the random assignments gain typed constants as operands, locals declared after a statement, and a local in each block of the if and the while (3,000 more in development). `BASIE.COM` 14,098 bytes. **67a.3:** `include` and `private` (D33). The parts are loaded by a new overlay, `PARTS` (`PARTS.ASM`), between the library check and the streams, which stay in `START` (`LIBRARY.ASM`, entered twice): each part the command line names, unless a part loaded already included it, and, depth first, every part it includes. A part is read whole, through the blob writer's buffer, then its include lines with the tokenizer: `include`, a string that decodes to a CP/M name with its type (`CL_NAME`, moved to `FILENAME.ASM` for both overlays that need it), and the line's end; the name is looked for on the including part's drive, then on option L's or `A:`, or on its own drive alone; a part already loaded is not loaded again, and one whose include lines are still being read is a cycle; the tokenizer's state is kept on the stack while an included part loads, 16 deep. A part takes its number in the stream once its includes are loaded, so it follows them, and its body, where its compilation begins, follows its last include line. The parts are described in a part table (`SOURCE.ASM`) of 21-byte entries, growing down from the top of the source area as the parts' bytes grow up: the part's name, its bytes, its body's offset and line, and its number; the eight-part table and the packed `SRC_LEFT` went, so a compilation takes 255 parts while memory lasts. `SRC_ID` is a part's entry, which diagnostics name, and `SRC_NUM` its number, which the line stream records; `TK_ATEND` steps to the next number (`SRC_BODY`), and `DG_SRC` finds a part by its address in any order. An `include` the compilation meets is `include-position` (`LL1.ASM`): the loader read those before the first declaration. `private` marks a top-level declaration: a bit for each symbol (`SY_PRIV`) and a flag in each routine record (`RO_FPRIV`); at each declaration (`AC_TOP`) a part that has ended has its private forwards checked, an open one being `forward-incomplete` at its `forward`, and its private names cut to no characters (`AC_ENDP`); a declaration must end in the part it began in (`AC_SPLIT`); a completion's visibility must be its forward's, and `main` can't be private. `var` parameters and `assert` statements are refused by the grammar (191). The reference accepted a wildcard in an include's name, which spec 4.3.2 calls `include-syntax`, and named no argument for `include-missing` and `include-cycle`: both fixed, with conformance programs. Claimed: `INCMAIN` (three parts, one included twice, privates of the same name in two, a forward one part declares and another completes) and the conformance programs `include-once`, `private-across-parts` and `private-is-part-local`; 13 more programs both compilers refuse, the part of the diagnostic compared too. The programs of the suite that include the library are not yet in reach: `STRINGS.BSI` has `var` parameters (67e) and `FORMAT.BSI` the numeric types and `f32` (67b, 67f). `BASIE.COM` 14,439 bytes |
| 67b | Numeric types: `i8`, `i16`, `u32`, `i32`, the conversions and shifts, 32-bit folding (the 16-bit exact range goes) | **Done.** **67b.1:** the numeric types' foundation and the signed bytes and words. The type keywords are one token, `TK_TYPE`, its payload the type (`KW_TYPE`), and one grammar terminal; `shl` and `shr` are tokens the expression island reads. A scalar type is four bits (`SY_TMASK`, IDs 1 to 8: u8, u16, Boolean, i8, i16, u32, i32, f32; aggregate IDs from 16), the storage class two (`SY_CMASK`), and each type's size and sign are in `GX_PROP`. A known value is five bytes, two's complement (`VALUE.ASM`): its low word in HL and the whole in `EX_KVAL`, as wide as the exact range of −2^31 to 2^32−1 needs and any one operation's intermediate result; the operand stack's entries are sixteen bytes, and a scalar constant's symbol record nine, its value's high bytes after its payload. Numbers are scanned to 32 bits (eight hexadecimal digits, 32 binary ones; a decimal one beyond is `malformed-number`, after a float is recognised). Folding is the reference's: exact operations checked against the exact range (`foldExact`: products through the magnitudes' 32-bit product, truncated division and the dividend's sign for `mod`, bitwise operands from 0 to 2^32−1, shifts as products and floor divisions, a negative count refused), typed ones wrapped at their type (`foldTyped`); `native-exact` (192) is no longer raised. The rules: an exact operand adopts its typed peer's type and must fit it, two typed ones take the type one widens to (spec 6.4, `EX_WIDEN`) or are `mixed-operands`; `EX_FITS` is the reference's `toRegisters` and `coerceConst` (a known Boolean for a number is `type-mismatch`, a computed one `conversion-required`). Code: values widen sign-extended or not (`GX_WIDEN`), the signed orders flip both sign bits (`compare16ToFlags`), `/` and `mod` on signed types call `DIV16S`, conversions are `checkedNarrow` (`GX_TRIM`, every 8-, 16- and 32-bit case), shifts by a known count a bit at a time or the whole width, by a computed one clamped to the width and looped (`GX_SHBY`, `GX_SHVAR`), and a shift's exact left operand takes the expected type unless its count is certainly exact, a typed constant one loading first unless its count is certainly constant (`peekExactOperand`, `peekConstOperand`: `EX_SHAPE`). Counted loops take i8 and i16 counters and the reference's comparison type (`CT_MCMPS`), its exact bounds beyond a byte counter compared as a word, and exact bounds beyond every type (`CT_MALL`, `CT_MNONE`). Diagnostics about an operand are reported at its first token, the reference's leftAt and rightAt (`EX_LAT`, `EX_RAT`, kept on the operand stack). The 32-bit code templates (`GX_LOP`, the long loads and stores) were written, `u32` and `i32` refused (191) until 67b.2. The workspace grew to 3,892 bytes and moved, with everything above it, 2K up (`MM_WBASE` `$5000`), so the source area starts at `$7400`. One fault of the reference: `u16()` of an i8 was neither checked nor widened (conformance program `byte-to-word-conversion`). Claimed: `SIGNED`, `SHIFTS`, `EXACT`, `CONVERT`, `SLOOPS`, `RUNNUM` (run: it traps at its end only when every result is right) and the conformance programs `negative-index-conversion-traps`, `negative-to-unsigned-traps` and `byte-to-word-conversion`, all run; 24 more programs both compilers refuse; the random assignments take i8 and i16 variables, fields and elements, signed and wide exact constants, shifts and every conversion, and every program both compilers refuse must be refused with the same diagnostic at the same place (9,000 more in development, and 3,600 random loops). `BASIE.COM` 17,048 bytes. **67b.2:** `u32` and `i32`: variables, locals, parameters, results, fields and elements of four bytes in `DEHL`, pushed `PUSH DE`, `PUSH HL`; their operators through the 32-bit helpers (`ADD32` to `SHR32S`, `CMP32U` and `CMP32S`, `MUL32`, `DIV32U` and `DIV32S`, `NEG32`), their conversions `checkedNarrow32`. A 32-bit counter (`CT_MLONG`) keeps a four-byte bound slot and step (a control frame is eighteen bytes); its test is `CMP32U` on the counter and bound, each with its sign bit flipped when signed; its next value is `ADD32` or `SUB32` after the distance to the bound (`SUB32`) is compared with the step (`CMP32U`), or, with no bound in reach, after the counter is compared with the last value a step can leave in the type, trapping `loop-range` beyond it (`AC_LNEXT`). A narrower counter with a 32-bit bound or step is the reference's `NotImplemented` and refused (191). The services with a `u32` parameter or result, `seek`, `position` and `size`, are called (`RO_FWIDE` gone). The workspace is 3,908 bytes. One fault of the reference: a conversion of a 32-bit value to its own type, `u32(l)` or `i32(m)`, zeroed or sign-extended its high word from its low (`widen` of a type to itself; conformance program `same-type-conversion`). One fault of 67b.1 found on the way: a conversion from a 32-bit type to a narrower one read the target's properties through a stale pointer (`GX_TRIM`). Claimed: `LONGS`, `LLOOPS`, `RUNLONG` and `LSEEK` (both run: they trap at their end only when every result is right) and the conformance programs `same-type-conversion` and `loop-range-traps-32`, all linked and run; 7 more programs both compilers refuse; the random assignments take u32 and i32 variables, parameters, fields and typed constants and conversions to both (6,000 more in development, with 6,000 random 32-bit assignments and 3,000 random 32-bit loops, codes and positions compared). The conformance programs using `FORMAT.BSI` or `PARSE.BSI` wait for `f32` (67f), and those using `STRINGS.BSI` or `TEXTIO.BSI` for `var` parameters (67e). `BASIE.COM` 17,367 bytes |
| 67c | Branch shrinking: forward jumps to `JR`, so the equivalence test compiles the reference with shrinking on | **Done.** Every routine's jumps shrink as the reference's `Blob.finish` shrinks them (`shrinkJumps`, its step 47): the candidates are the jumps it records, `JP` and `JP NZ`, `Z`, `NC` and `C` to a label of the routine, found among the routine's references (a self-reference after one of those five opcodes; the only other self-references are `LD HL,(need)` and `LD HL,literal`), so nothing is recorded as code is written. Every candidate starts short and each pass drops those a `JR` would not reach until a pass drops none; dropping one only lengthens the others' distances, so the fixed point does not depend on the order and a candidate is dropped as soon as it fails (`SHRINK.ASM`, `BL_SHORT`). The short jumps are a table of four-byte entries in the free memory above the source and the routine's waiting constants (`source size`, Error 190, if it does not fit), ended by a sentinel. To make the rewrite cheap the blob writer changed its representation: references (seven bytes) and line entries (five) are kept as given while a blob is built and encoded into the streams' delta form only when `BL_END` writes it, through `BL_MAP`, which moves an offset back by the short jumps before it, so the record's size and count, every reference's offset, a self-reference's addend (labels, the need word, string literals), every line entry's offset and each short jump's displacement come out as the reference's; a short jump's reference is dropped and its `JP` written as a `JR`. A blob without short jumps (every data blob) maps every offset to itself (`BL_NONE`). The in-place rewrite tried first, which decoded and re-encoded the delta-encoded buffers, took 622 bytes; this takes about 330, the encoders moving from `BL_REF` and `BL_LINE` to `BL_END`. The limits it touched: a routine's references are 146 (`BL_RCAP`, 1,022 bytes) and its line entries 128 (`BL_LCAP`, 640), where the encoded 512-byte buffers held about 100 and 120 (`ADVENT.BSI`'s `main` has 132 references); its string literals 48 (`RO_LCAP`, from 16, in the workspace's spare bytes below the LL(1) stack; `ADVENT.BSI`'s `main` has 24). The blob writer's workspace grew from 3,789 bytes to 4,432, so the source area starts at `$7580` and is 384 bytes smaller (about 26.4K on a 62K system); the 2,048-byte code buffer stays, every routine of the corpus being below 1,700 bytes. The equivalence test compares every claimed program with the reference's default build, its jumps shrunk; the toolchain has no option to turn shrinking off, so no comparison without it is kept. Claimed: `SHRINK` (jumps on either side of a `JR`'s reach, forward and back, jumps that reach only once those inside them shrink, string literals after shrunk code) and `ADVENT.BSI`, linked and run. `BASIE.COM` 17,142 bytes |
| 67d | `select` | **Done** for integers, characters and ranges (the reference's step 41; handle selections wait for the pools, 67g). The reference tests every label in turn, a jump table never (`emitLabelTest`), so the native compiler does: the subject, stored in a frame slot of its own size, allocated before the select's control frame opens so that it stays allocated until the enclosing block ends, as `allocLocal` leaves it, is reloaded for each label, its sign bit flipped when signed, and compared unsigned: a byte with `CP low` and `CP high+1` (or `JP body` when high is `$FF`), a word by `LD DE,low`, `SBC HL,DE` then `LD DE,high-low+1`, `SBC HL,DE` (or `JP body` when high is `$FFFF`), a long through `CMP32U` with low and with high; a single value `JP Z,body` after the first comparison (`LD A,H`, `OR L` for a word). Each arm's labels end with `JP next`; its body with `JP end`. The labels of the open selects are kept as eight-byte ranges, at the subject's type with the sign bit flipped (`CT_RTAB`, 63 of them after the LL(1) stack, `labels`, Error 190, beyond), and each new one is checked against those before it in the same select (`duplicate-case`). The subject follows the reference: a variable's name is a designator alone (`select x + 1` is syntax at `+`), anything else an expression, which must have a type (`no-definite-type`); `move` is syntax at `select`, `some` and `none` type-mismatch, a select without a labelled arm syntax at `select`, anything but `end` after `case else` syntax at it; the arms' flow is the if's: a select completes when an arm falls through or it has no `case else`. `select`, `case`, `some`, `none` and `move` became keywords (the last three refused where an integer select meets them, and as names, as the reference refuses them). The actions are `ACTSEL.ASM` (812 bytes); the grammar gained three rows and seven actions. One fault of the reference: a word range covering every value, `0 to 65535` or `-32768 to 32767`, compared with `hi-lo+1`, which is 65,536 and was written as zero, so the arm was never taken; it now jumps to the body, as a byte range reaching `$FF` does (conformance program `select-whole-word-range`). Claimed: `SELECTS` (every integer type, every kind of subject, nested selects, selects in loops with `exit` and `continue`, a subject beyond IX−128), `RUNSEL` (run: its output is checked), and the conformance programs `select-integers`, `select-signed-range`, `select-32-bit` and `select-whole-word-range`, all linked and run; 27 more programs both compilers refuse, among them `select-overlap`; every fifth random assignment may sit in a select's arm on a random subject with random labels and ranges (3,000 more in development). `BASIE.COM` 18,057 bytes |
| 67e | Local aggregates in full, `var` parameters and results, `assert` | **Done.** **67e.1:** `var` parameters, open arrays, `from` clauses, var results and `assert`. A parameter may be `var` when it is an aggregate (`var-parameter` otherwise, at its name); the parameter table marks it with bit 7 of its type (`AG_VAR`), as the services' var views now are, and its symbol's class with `SY_PVAR`, so its path is writable; a var record's argument is its address after its owner word, zero from storage and passed on from a var record parameter, a field of it or its whole (`RO_POWN`), so its argument takes four bytes. A var argument must be writable (`not-writable` at it). Stores through an alias are the reference's `storeRegisters` (`GA_STAL`). `T[]`, an open array, is a parameter type only (`type-mismatch` at the type elsewhere, `refuseOpenView`), its ID `AG_OPEN` plus its element's: it takes an array of its element type, its length as the view's word, or an open array passed on with its word; `.length` is that word, and its elements are checked against it at run time, a constant index too; the services' `u8[]` takes one. An outermost `[]` only (syntax at the type otherwise). A writable open string's `.length` is set through `STR_SETL`; a view is never assigned whole. A result may be `var` (`RO_FVRES`), so a call's aggregate result may be passed to a var parameter, and may name in `from` the aggregate parameters it may be rooted in (`from-clause` otherwise), which do not escape (`RO_FROM`, `SY_PFROM`). `assert` in a statement: a known condition must be the Boolean true (`assertion-false` at `assert`), a computed one tests `OR A`, `CALL Z,TRAP_AST`. The services' var views in the generated table are `AG_VIEW` and `AG_BUF` with `AG_VAR` (`AG_VVIEW` and `AG_VBUF` went). Claimed: `VARPARM`, `OPENARR`, `ASSERTS`, `RUNVAR` (run: it includes `STRINGS.BSI` and traps at its end only when every result is right) and the conformance programs `from-clause`, `var-parameter-far-field`, `assert-traps`, `library/text-console` and `truncate-refuses` (`TEXTIO.BSI`) and `services/directory` (`STRINGS.BSI`), all linked and run; 32 more programs both compilers refuse; the random assignments gain two heads whose aggregates are var parameters, fixed and open (6,400 more in development). `ADVENT.BSI` now reaches the capacities: its `main` has 24 string literals, more than `RO_LCAP`'s 16, and more code than the 2,048-byte blob buffer; the other examples and the programs that include `FORMAT.BSI` or `PARSE.BSI` wait for `f32` (67f). `BASIE.COM` 18,165 bytes. **67e.2:** an aggregate constant may be declared in a routine's body. It takes its ordinal where it is declared, as the reference's `newBlob` does, and its read-only blob follows its routine's; the blob writer builds one blob at a time, so it waits, its ordinal, size, bytes and name, in the free memory between the source's last part and the part table (`RG_SPAN`, `RG_DEFER`), and the routine's end writes the waiting constants after its own blob (`RG_CLOSE`); `source size` (Error 190) when they do not fit. Claimed: `LCONSTS` (constants in a function, in main's blocks and loops, and in a forward's completion, whose blob keeps its earlier ordinal); 3 more programs both compilers refuse. `BASIE.COM` 18,317 bytes |
| 67f | `f32`: the decimal-to-`f32` overlay above `NAMES` | **Done.** The `f32` type for variables, locals, parameters, results, fields and elements; its literals; conversions to and from the integer types; arithmetic and comparison through the runtime's `f32` helpers; and constant folding exactly as the reference's `foldTyped` does it. The conversion and folding are the `FLOAT` overlay (1,460 bytes, `FLOAT.ASM`, its 155-byte workspace resident between the shell's and the blob writer's, loaded from `NAMES`' last byte), loaded above `NAMES` the first time an `f32` constant is met and kept: every result is formed exactly as a ratio of 64-byte integers and rounded once, a literal as `parseF32` rounds it, a fold as `Math.fround` does, below 2^-126 flushed to zero (D7). The overlay area grew from 1,024 bytes to 2,483. A review found a literal's exponent capped near 768, so that a long fraction with a large exponent folded wrongly, and trailing zeros counted against the digit capacity: exponents are now exact to 30,719 and the power of ten held at ±16,000, where any literal is settled, and trailing zeros are deferred into the power of ten (`FEXPS`, `FZEROS`). `f32` is refused where the reference refuses it: loop counters, bounds and steps, `select` subjects, `mod`, `not`, shifts and mixing with integers. One fault of the reference: an integer zero converted to `f32` could be −0.0 (conformance program `integer-zero-to-f32`). Claimed: `FLOATS`, `FCODE`, `RUNF32`, `examples/DUMP.BSI` and the conformance programs that `f32` and the library's `FORMAT.BSI` and `PARSE.BSI` brought in range, about forty, all linked and run; the random statements take `f32` values. `BASIE.COM` 18,425 bytes, area 2,483, total 20,908 |
| 67g | Pools, handles, flow, leases and ownership | **In progress.** **67g.1a:** pool declarations, `forward pool` and `private pool` (`POOLS.ASM`): a pool takes its ordinal at its first declaration and is written as its slots (bss, `NAME.slots`) and its information blob (the slots' address, the slot size, the capacity and its record's owner descriptor or zero), as the reference writes them. Handle types, `P`, `id P` and either optional (`?`), are type IDs from `$68`, two bytes for an owner and four for an `id`; fields and program variables of them must be optional (`handle-must-be-optional`). A record or array holding an owning handle is owning, and the first pool of an owning record writes its owner descriptor (`TYPE.owners`): an entry for each owning handle, strided by the innermost array, an outer array expanded per element. `pool-needs-record`, a capacity of zero or beyond 65,535 bytes (`out-of-range`), `forward-mismatch` and `forward-incomplete` are reported where the reference reports them. Handle and owning locals, parameters and results, and `new`, wait for 67g.1b (Error 191). The workspace moved 1K up (`MM_WBASE` `$5800`). The descriptor writer is an overlay, `OWNERS` (406 bytes, `OWNERS.ASM`), loaded above `NAMES` in `FLOAT`'s place when a pool's record needs its descriptor, each of the two loaded again when next needed. A review found the descriptor's entries in the wrong order when arrays nest (the outer elements must vary fastest), open-array types read as table types, the capacity diagnostics raised through the wrong entry, initializers on handle and owning program variables accepted, forward pools reported last first, a repeated field name checked before its type, and `forward pool` declared before its line's end; all fixed. A record type's or a pool's name used as a value is `wrong-class`, as the reference has it (it was `type-mismatch`). Claimed: `POOLDECL`, `POOLDSC`, `POOLPRV`, `POOLNEST` and `POOLF32` (`FLOAT` loaded again after `OWNERS`), linked and run; 28 more programs both compilers refuse. `BASIE.COM` 19,455 bytes, area 2,483, total 21,938. **67g.1b (first part):** `new P(fields)` and `new? P(fields)` (`HANDLES.ASM`): `POOL_TRY`, a pool-full trap or none, the slot's address in a frame temporary and each field given assigned through it as a path's is (`RO_ASGN`, split from `RO_LET`, the temporary the place's slot word); `none`; owning handle locals, typed or inferred from `new`, linked by `LINK0`, and a non-optional one without an initializer `needs-initializer`; an owning handle assigned through `OWN_SET`, with the place's slot word or zero; and the frees, `CALL NZ,POOL_DEL` for each owning local, at the end of each block (the while body's and the else arm's before their labels, now) and of the body, and at every return (the result kept around them when any owner is in scope), fail, exit and continue that leaves it, innermost scope first. A record type's or a handle's misuse elsewhere is refused (191) rather than misread. The workspaces and the source area moved another 1K up (`MM_WBASE` `$5C00`). Claimed: `NEWFREE` and the conformance programs `freeing-reuses-slots`, `pool-full-traps` and `sibling-owners`, linked and run; 12 more programs both compilers refuse. A review found every accepted program identical and five diagnostic faults: a handle assignment's type-mismatch is now reported at its target, as the reference's assign has it; `select` on a handle, a handle's value in an expression, and `new`, `none`, `move` and `id(` in an expression are refused (191) rather than reported as syntax or an undeclared name; any other value for a handle is parsed as an expression first. 7 more programs both compilers refuse. `BASIE.COM` 20,430 bytes, area 2,483, total 22,913. **67g.1b (second part):** fields through a handle local, as the reference's suffixes reach them: the handle kept in a frame temporary, an identifier's checked (`ID_CHK`) and kept with its generation, the temporary the place's slot word, an owning store through an identifier by `OWN_SETC`, an element at a run-time index without one (`RO_PPUSH` bits 3 and 4), and an assignment through an identifier rechecked after its value (`HN_RECK`); `select` on a handle: the subject in a slot of its own, `some(x)` and `none` read before the engine predicts the arm (CaseLabels may be empty), a lease bound for the routine's own owning local (an alias through the slot, `SY_LEASE`) and an identifier (`ID_MAKE`) otherwise, `case else`, and the reference's syntax faults. The workspaces and the source area moved $200 up (`MM_WBASE` `$5E00`). Claimed: `HANDSEL`, `HANDPATH` and the conformance programs `new-and-select`, `new-optional-when-full` and `new-trailing-fields`, linked and run; 12 more programs both compilers refuse. `BASIE.COM` 21,162 bytes, area 2,483, total 23,645. A review found a lease's subject assignable in its arm (now not-writable, released when an inner lease of it ends, as the reference's one counting flag is), a var record argument through an owning handle passed the handle's temporary as its owner word (now none) and one through an identifier accepted (now not-writable; a value argument's copy waits, 191), a typed local allocated before its initializer's temporaries, and the temporaries of if, elseif and while conditions freed with the arm's block rather than the enclosing one; all fixed (`HANDARG`, `CONDTMP`, `CONDTMPW`, `LOCTMP`, `LEASEIN`, 7 more refusals). The workspaces moved $100 up (`MM_WBASE` `$5F00`). `BASIE.COM` 21,372 bytes, area 2,483, total 23,855. **Compression after 67g.1b:** the pool declarations' actions (`ForwardPool`, `PoolRecord`, `CommitPool` and the forward pools' check at a part's end) moved into the `OWNERS` overlay with the descriptor writer, reached through a jump table at its start (`OV_PCALL`); the capacity's check stays resident, since a constant's conversion may load `FLOAT`. `BASIE.COM` 20,894 bytes, area 2,483, total 23,377 |
| 67h | The capacity tables: the hashed symbol table with a name heap, the scoped type descriptors, streaming the source | — |

## 4. Budget

| Stage | Change | Projected size |
| --- | --- | ---: |
| Starting core (step 64) | measured | 15.3K |
| Step 65 | −2.3K placed output, banking, startup and trap endings; +1.9K CP/M core; +0.45K chain, stamp and library check; +0.9K blob, line and name writers; +0.3K `frame`/`need` and helper stack table; +0.3K table widening | 17.0–17.6K; measured at its end, 16,171 bytes, of which the command line, the library check and stamp and the chain, for the overlay, take 1.6K (`COMMAND.ASM` 836, `LIBRARY.ASM` 488, `CHAIN.ASM` 266) and the predeclared names 0.9K |
| Step 66 | message file and overlay loader | about 18K; measured, 13,895 bytes resident and a 1,024-byte overlay area: the one-shot code, the diagnostics and the predeclared names left the image |
| Step 67 | the Basie features of the [feature inventory](feature-inventory.md) not yet present | about 27K |

That exceeds the 26K target, so these levers are planned from the start:

1. **Overlays for one-shot code.** Three groups never run at the same time:
   - command-line parsing and the library check, at the start;
   - decimal-to-`f32` conversion, during compilation;
   - the chain loader, at the end.

   Sharing one overlay area saves about 1.3K of resident code.
2. **Compression passes,** after every increment, each expected to save 3%
   to 5%.
3. **Removing machinery Basie does not use, early:**
   - the region-check helpers;
   - the banked paths;
   - activation counting;
   - the root-frame save.

The census figure is recorded in every commit that touches the compiler. A
commit that crosses the 28K limit is not made: compression comes first (D43).

### The compression pass before 67c

The numeric types (67b) cost 2.9K against a 1.6K estimate, so before 67c,
with `f32`, `select`, branch shrinking and the pools still to come, the
whole compiler had a compression pass. It changed no stream and no
diagnostic: every commit passed the equivalence test, the both-refuse
list and the conformance suite with the image pinned. It began with a
census of the listing (bytes by file and routine; repeated instruction
sequences; `JP` within reach of `JR`; `CALL` then `RET`; call and jump
targets) and took the largest structures first.

| Commit | What | Resident bytes |
| --- | --- | ---: |
| Overlays | The streams' opening code (`BL_OPEN`, `BL_PART`, `OUT_OPEN`, the stream table) runs once, before the compilation: `BLOPEN.ASM`, in `START`. Their closing (`BL_CLOSE`, `OUT_CRC`, `OUT_END`) runs once, after it: `BLCLOSE.ASM`, in `CHAIN`, whose new entry `CH_DONE` closes the streams and then runs `BLINK` unless option C. `SRC_INIT`, which only the loader calls, went to `PARTS`; `SH_NUM`, which only diagnostics call, to `DIAG` | −451, and −54 with `OV_TRY`'s count (`LD BC,OV_AREA` / `DEC B`) |
| Expressions and control | 12 `JP`s to `JR`; the precedence chain of `EX_LOOK` became the comparison table's pairs; the Boolean type tests share `EX_LBOOL`'s tail (`EX_DBOOL`, `EX_TBOOL`); `EX_PAREN` and `EX_CAST` share `EX_RPAR`; `CT_TYPE` computes a short counter's type (`CP 2` / `SBC A,$FE`); the dead `EX_EZERO` | −76 |
| Tokenizer, cursor, driver, LL(1) | `TK_WORD` calls `TK_MATCH`; `TK_HEX` by subtraction; `TK_ZERO`, `TK_EOLR` shared; `SRC_TAKE` uses the pointer `SRC_PEEK` returns and keeps A and the flags; `PR_PEEK` and `PR_TAKE` lose reloads; `LL_PARSE` inlines its one-use push and pop | −99 |
| Calls, routines, aggregates, actions | `RO_PATH` pushes itself as each step's return; `RO_ARGS` one loop; `RO_LET` pushes `AC_ROUTE` as its return; shared exits `RO_EFIT`, `RO_TYPE`, `RO_WRITE`; `AG_BRACK`; `RO_BIND` by `LDIR`; the engine reads no action's flags, so carry clears went; `AC_STORE`, `AC_ITEM`, `AC_FIDX`, `AG_RENT`, `RO_ISLEN` | −317 |
| Generators and emitter | `EM_FWD`, `EM_LDONE`, `EM_SELF`, `EM_OPA`, `EM_OPX`, `EM_SEQX` (20 `CALL EM_SEQ` / `DB` / `RET` tails); `EM_LDEF` and `EM_JUMP` keep A; a place's accesses through `GA_PLACE` to the frame and static load and store templates (`GA_ACC`, `GA_QUAD` gone); `GX_MINUS`, `GX_FLIP` shared | −390, and −35 at their remaining callers |
| Blob writer, streams, keywords, second pass | `BL_REF` and `BL_LINE` share `BL_PUT`, `BL_PUTW` and `BL_CTRL`, each buffer's pointer just past its end; `KW_TAB` without length bytes (bit 7 ends a keyword); `LL_STACK` on a page, a slot's address the page and the depth; `VL_FITS` keeps BC; `AC_NOERR` is `AC_LEAVE` | −204 |

The image went from 18,317 bytes to 16,691, 1,626 fewer (8.9%), and the
image with the overlay area from 19,341 to 17,715, 8,909 to the 26K
target. `BASIE.OVL` grew by four records. Two techniques recur and are
worth applying to new code from its first line: a routine that is called
in sequence pushes its continuation instead of being called (`RO_PATH`,
`RO_LET`, `LL_PARSE`), and an inline-operand emitter that ends its caller
(`EM_SEQX`, `EM_OPX`) replaces `CALL` / data / `RET`. One identity proved
useful: after `OR A` / `SBC HL,DE`, `ADD HL,DE` restores HL and recomputes
the borrow as carry, and leaves Z alone, so it replaces `PUSH HL` / `POP HL`
around a comparison whose carry or zero is read.

### The compression pass after 67d

`select` (67d) cost 812 bytes in `ACTSEL.ASM` against a smaller estimate,
and branch shrinking (67c) about 330 in `SHRINK.ASM` and the blob
writer's `BL_MAP`, so before `f32` those and the census's next
candidates had a pass of their own, again with every stream and
diagnostic unchanged. It took 94 bytes, from 18,057 to 17,963 (the
total measured, the rows from the sites' opcode arithmetic):

| What | Resident bytes |
| --- | ---: |
| The control frame's fields: `CT_MODE` (the mode in A, nine sites), `CT_FLAGS` (its address) and `CT_FBYTE` (a field's byte), in place of `LD B,CT_FMODE` / `CALL CT_FIELD` / `LD A,(HL)` | −23 |
| The blob writer keeps IX no longer (`BL_END`, `BL_BSS`, `BL_CWORD`, `BL_NAME`; nothing in the compiler holds IX across them, and their callers' contracts now name it), `BL_BSS` falls into `BL_REC`, whose wide count shares `BL_CWORD`'s tail, and `BL_END` returns where it ends rather than through `.DONE` | −29 |
| `PR_SPOT` (the next token and its offset, six sites) and `DG_KEPT` (a diagnostic at `AC_SPOS`, four) | −18 |
| The words' sign flip of a signed comparison, `GX_SIGNS`, shared by `GX_REL` and the for loop's test; the long's, `GX_DSIGN`, by the for loop and `select` (and, at 67f, an `f32`'s negation) | −12 |
| `ACTSEL.ASM`: the overlap test of two labels through `.PAST`, `move` refused through BC, the subject's first token read once; a select arm's and a for loop's body share `AC_ENTER` | −12 |

`SHRINK.ASM` and `BL_MAP` were already tight: the census found no jump
within `JR`'s reach and no repeated sequence there worth a routine.

**What remains** (projected unless measured):

- **The overlay area.** It is 1,024 bytes because `COMMAND` (978), `DIAG`
  (1,023) and `NAMES` (947) each need eight records. Seven records would
  free 128 bytes, but `DIAG` would have to lose 127 bytes, `COMMAND` 82
  and `NAMES` 51; `NAMES` is generated (`tools/helpertable.ts`), and its
  services' ordinal and stack figure could be bytes rather than words
  (about 2 bytes a service) if `RO_CALL` read them so. Not worth it alone;
  worth checking when `f32`'s overlay is sized.
- **Restart vectors: rejected.** `EM_SEQ` (about 54 call sites), `EM_OP` (41)
  and `DG_RAISE` (about 40) as `RST`s would save about 250 bytes less 10 to
  install each. The vectors stay reserved for the BIOS and CP/M, and Basie's
  own code never takes them for compression (D46; [CP/M target](cpm-target.md)
  §8).
- **Small shared tails** (`POP BC` / `LD A,C` / `OR A` / `RET` at four
  sites, the `CT_FMODE` field fetch at seven): a few bytes each, needing
  restructuring.
- Tables already compact: the grammar (859 bytes, generated), `KW_TAB`,
  `GX_PROP`. A further pass of this kind would probably find 2% to 3% more;
  the larger lever left is the overlay area.

## 5. Findings from the commentary pass

The commentary pass of step 65.0 read every line. It changed no code. These
are what it found, to be dealt with by the step named.

**Suspected faults in the starting core:**

| Where | Fault | When |
| --- | --- | --- |
| `EXOPER.ASM`, `EX_ORS` | `xor` keeps its left operand with `EX_SAVE`, not `EX_HOLD`, so a pending failable call is not checked: `f() xor g()`, with only `f` failable, loses `f`'s failure | fixed at 65.4 (c): `EX_OPEN` keeps every left operand of `and`, `or` and `xor` with `EX_HOLD` |
| `CALLS.ASM`, `RO_SEL` | A `CP AG_FIRST` has no branch after it (its type-error jump sat in a conditional the build configuration removed), so `r.a.x` with `r.a` a `u8` looks up a field in a non-record type | fixed at 65.4 (h): `RO_PATH` raises `DG_CLASH` at the dot for a field of a scalar or an array; and the field search, whose count `AG_FIELD` overwrote, now stops at a name the record lacks (it ran on through the table) |
| `CALLS.ASM`, `RO_ERNG` | A constant index's range error sets only the offset, so it is reported at the closing bracket's line and column | fixed at 65.4 (h): the index's first token's position is kept (`RO_IPOS`) and the error is reported there, as the reference reports it, in a discarded arm too |
| `GENCTRL.ASM`, `GC_PEND` | The label range check `AND $1F` / `CP 32` cannot fail; labels stay below 32 today | gone with `GENCTRL.ASM` (65.4 a); routine labels are checked against `EM_LCAP`, and control flow uses them from 65.4 (f) |
| `LL1.ASM`, `CALLWORK.ASM` | `DG_LLCAP` and `DG_LEAK` share the number 87 | fixed at step 66: every code is the reference's number; `DG_LEAK` is `failure-unconsumed` (113) and `DG_LLCAP` the native capacity `grammar stack` (190) |
| `ACTSTMT.ASM`, `AC_GOTO` | `exit` and `continue` do not clear `CT_FALLS`, so an `if` whose arms all end in `exit` inside a routine with a result may be refused with `DG_FLOW` | fixed at 65.4 (f): `AC_GOTO` ends with `AC_DEAD`, and fallthrough follows the reference's rules (`FLOW`) |
| `ACTIONS.ASM`, `AC_BOUND` | Has no effect: `AC_FOLD`, which always follows, overwrites `EX_WANT`; the bound is checked later by `AC_COUNT` | fixed at 65.4 (f): removed; `BeginTypeBound` is `AC_IDLE`, the `RET` of `AC_WANT` |
| `SHELL.ASM` | The room check refused a part ending within 128 bytes of the limit; a read error ended a part silently; a trailing comma and a blank type were accepted; a part's drive was not printed in diagnostics | fixed after the pass (`BASIE.COM` 16,147 bytes) |

**Found at 65.4 (c).** The starting core typed a character literal as `u8`, where spec
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
names were still the starting core's six services and four error constants, so a
program that names a routine after one of the reference's services or
predeclared constants (`size`, `close`, `console`, `fileNotFound`) was
accepted natively and refused by the reference; the full table came with
the services at 65.4 (i), and the four constants, which had been `u8`,
became exact.

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
At the compression pass before 67c (§4) none of these was left: `PR_FORD`,
`EX_ISFWD`, `AG_MODE` and `SY_GSLOT` had gone, the census found no `CALL`
then `RET` and no jump to the next line, and the one dead routine found,
`EX_EZERO`, which nothing raised, went with it. `GX_TYPES` and `GX_PFROM`
in `STATE.ASM` are now unused workspace (3 bytes, not in the image).

**Contracts.** The commentary agents checked every `;@ROUTINE` line against the
code by hand, and the actions' agent with a register-effect analyser that walks
each path through `PUSH`/`POP` and its callees' contracts. Making that analyser
a tool, run by the tests over every module, is planned with the first
compression pass, so that contracts stay true as code changes. It was
not built for the pass before 67c, which changed many contracts (actions
no longer clear carry for the engine, `EM_LDEF`, `EM_JUMP` and `VL_FITS`
keep more, `TK_MARK`, `BL_LIMIT` and `RO_ISLEN` clobber more) and checked
each against its callers by hand, with the equivalence tests behind them;
it is still worth building before the next.

**Names to revisit,** each a byte-identical rename: tails of routines that are
global only because their code spans several labels (`TK_TRAIL`, `RO_SEL` (gone at 65.4 h),
`RG_FORK` and others), which become private when their routines are made one
scope; names in the wrong area (`EM_LDDE` in `GENCTRL.ASM`, `EX_EFLOW` used by
the actions, `TG_` routines in `ROUTINES.ASM`); vague or figurative words
(`EX_PEAK`, `EX_PURE`, `EX_MUTE`, `AG_FITRW`); look-alike pairs (`AC_LIVE` and
`AC_LIVEN`, `GC_TEST` and `GX_TEST`); and fields reused for several meanings
(`RO_ACNT`, `RO_DEST`).
