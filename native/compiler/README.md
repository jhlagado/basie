# The native compiler

`BASIE.COM`, in ATOM source (design decision D44), its names under the label
convention of the [naming guide](../../docs/naming.md). Basie is released under
the GNU General Public License, version 3 ([LICENSE](../../LICENSE)).

```text
deno task build:compiler     build BASIE.COM and BASIE.OVL and report the extents
deno task grammar            generate GRAMMAR.ASM from grammar/grammar.json
deno task census:basie       size by file, against the 26K target and 28K limit,
                             then the overlays and the overlay area
```

## Files

`BASIE.ASM` includes the resident files in image order. ATOM assembles each
included file before its includer, so the list is the layout. `INIT.ASM`
comes last: it marks the shell's and the image's end and the overlay
area's start (`OV_AREA`), then holds the start-up, which BASIE.COM's file
carries into the area and the first overlay replaces, so that it takes no
room of its own.

The overlays are not included: `build.ts` assembles each on its own at its
load address in the overlay area (`OV_AREA`, the image's end), against an
equate for every resident name it uses (`build/ovl/NAME/RESIDENT.ASM`), and
writes `BASIE.OVL` (`OVERLAY.ASM` describes the file and the loader).
Wherever `BASIE.COM` goes, `BASIE.OVL` goes with it: the CP/M harness's
disks in the tests and the Triptych machine's.

| Overlay | Files | Bytes | Loaded |
| --- | --- | ---: | --- |
| `BEGIN` | `COMMAND.ASM`, `LIBRARY.ASM`, `BLOPEN.ASM`, `PARTS.ASM`, `FILENAME.ASM`, `PARTNAME.ASM` | 2,558 | first, once, its entries run in turn: the command line, the library check, the parts and their includes, then the stamp and the streams |
| `PREP` | `PREP.ASM` | 165 | once, by `PR_BUILD`: the parse state cleared and the tables placed above the largest part |
| `NAMES` | `PREDEF.ASM` | 947 | before the parse, for all of it: the predeclared names stay where `RO_LIB` reads them, so lookups are as fast as from the image |
| `FLOAT` | `FLOAT.ASM` | 1,458 | above `NAMES`, when a compilation meets an `f32` constant: decimal literals to `f32` and the folding of `f32` constants |
| `OWNERS` | `OWNERS.ASM` | 1,639 | above `NAMES`, in `FLOAT`'s place: pool and record declarations and owner descriptors |
| `CHAIN` | `CHAIN.ASM`, `BLCLOSE.ASM` | 496 | after a compilation, to write the entry and limits records, close the streams and, unless option C, run `BLINK`; with option X, to run `BLINK` alone |
| `DIAG` | `MESSAGE.ASM`, `PARTNAME.ASM` | 1,110 | to print a diagnostic, and to delete the streams after a failure |
| `LOOKUP` | `LOOKUP.ASM`, `FILENAME.ASM` | 1,063 | with option T, to look up a trap's address |

The overlay area is 2,611 bytes: `NAMES` and `OWNERS` above it, the
largest pair, in whole records. `FLOAT` and `OWNERS` load from `NAMES`'
last byte, taking turns there, and the others at the start. Code that
runs once, before the compilation or after it, or only after a failure,
belongs in an overlay rather than the image: the start-up is `BEGIN`'s,
the compilation's starting state `PREP`'s, the closing records and
streams `CHAIN`'s, and the failure's messages and deletions `DIAG`'s.
Code a routine's parse needs stays resident, since an overlay that took
turns with `OWNERS` or `FLOAT` there would be read again for each routine.

Code is generated as it is parsed, in the reference compiler's templates,
and each routine and top-level declaration is written as a blob (design
decision D45; [native compiler](../../docs/native-compiler.md) §2 and §3,
65.4). `tests/native_equivalence_test.ts` compiles every claimed program in
`tests/native/programs` with both compilers and compares the four streams
byte for byte. A construct not yet generated this way is refused with
`native-unsupported`, 191 (`DG_NYI`).

Diagnostics carry the reference compiler's numbers (`ref/compile/messages.ts`,
docs/diagnostics.md) and are printed as the reference toolchain prints
them, `MAIN.BSI 12:5: 27: count is not declared`, the text read from
`BASIE.MSG` (`MESSAGE.ASM`, design decision D39); without the file the text
is `Message N` and the arguments. The test's both-refuse list checks the
number, code, position and arguments against the reference's.

| File | Area | Contents |
| --- | --- | --- |
| `MEMORY.ASM` | `MM_` | Memory map: the image, workspaces and resident source |
| `STATE.ASM`, `CALLWORK.ASM` | various | Workspace layout, diagnostic numbers, transcript operations, token kinds |
| `HELPERS.ASM` | `HP_` | The runtime helpers the generators call: ordinal and stack figure; the helper-table version and key compiled in; generated with the reference's helper table by `deno task helpers` (`tests/helper_table_test.ts` checks it is current) |
| `HEAD.ASM` | `MM_` | The jump to the shell at `$0100` |
| `SOURCE.ASM` | `SRC_`, `PT_` | Source parts: the part table, in load order, and the cursor that steps through the parts in stream order |
| `TOKEN.ASM` | `TK_` | Tokenizer |
| `TRANSCR.ASM` | `TR_` | The refusal (`DG_NYI`) of constructs whose code generation has not yet moved to blob output |
| `SYMBOLS.ASM` | `SY_` | Symbol table: 96 records of nine bytes, scoped by blocks (its prefixes), with a bit for each private symbol |
| `PARSER.ASM` | `PR_` | Parser driver |
| `EXPR.ASM`, `EXTERM.ASM`, `EXOPER.ASM`, `VALUE.ASM`, `CONTROL.ASM`, `AGGR.ASM`, `ROUTINES.ASM`, `CALLS.ASM` | `EX_`, `VL_`, `CT_`, `AG_`, `RO_` | Expression (three files: ATOM takes at most 64K of source per file; the constants' arithmetic, five-byte values folded as the reference folds them, in `VALUE.ASM`), control (frames, conditions and counted loops), aggregate and routine parsing (routine names and signatures, then calls to routines and services, failable calls, File values and aggregate paths, each kept as a place: static, frame, alias or computed) |
| `LL1.ASM`, `GRAMMAR.ASM`, `ACTIONS.ASM`, `ACTSUB.ASM`, `ACTSTMT.ASM` | `LL_`, `GR_`, `AC_` | The LL(1) engine, its tables and their actions (three files: declarations, then routines and failure, then statements and flow) |
| `ACTSEL.ASM` | `AC_` | The actions of `select` on integers: the subject in a frame slot of its own, each label checked against the select's earlier ones and tested in turn, the arms' labels and flow |
| `OUT.ASM`, `BLOB.ASM` | `OUT_`, `BL_` | Output streams and the blob writer: `NAME.$DR`, `$BY`, `$LN`, `$NM` |
| `SHRINK.ASM` | `BL_` | Branch shrinking: which of a routine's jumps to its own labels become `JR`, as the reference's `Blob.finish` chooses them; `BL_END` then writes the routine shrunk (`BL_MAP`) |
| `BLOPEN.ASM`, `BLCLOSE.ASM` | `BL_`, `OUT_` | The streams' opening (`BL_OPEN`, `BL_PART`, `OUT_OPEN`) and closing (`BL_CLOSE`, `OUT_CRC`, `OUT_END`), which run once each: in the `START` and `CHAIN` overlays |
| `EMIT.ASM` | `EM_` | Emitter primitives: bytes, references, helper calls, labels and jumps, frame accounting |
| `GENEXPR.ASM`, `GENOPER.ASM` | `GX_` | Expression templates: loads and stores of program variables and of frame slots (near and far), constants, widening and checked conversions, negation and complement (`GENEXPR.ASM`); the binary operators, comparisons and shifts, a long's through the 32-bit helpers (`GENOPER.ASM`) |
| `GENAGGR.ASM` | `GA_` | Path templates: a place's address, fields and constant elements, checked elements and characters at run-time indexes, loads and stores at a place (a File's four bytes too), aggregate locals zeroed, initialized and copied, and the routine's string literals, placed after its need word |
| `GENCALL.ASM` | `RG_` | Routine and declaration blobs, ordinals, prologues (checked for a forward routine) and exits (through `RETN` when there are arguments), the entry and limits records |
| `KEYWORDS.ASM` | `KW_` | Keyword and punctuation tables |
| `PREDEF.ASM` | `HP_` | Overlay `NAMES`: the predeclared names: constants, `console` and `printer`, and the services with their signatures, ordinals and stack figures, generated from the reference's helper table and `ref/compile/helpers.ts` by `deno task helpers` (`tests/helper_table_test.ts` checks it is current) |
| `SHELL.ASM` | `SH_` | The CP/M shell: its course through the overlays, the source parts' workspace, streams on the spool drive (deleted after a failure unless option `K`), diagnostics with their part, line and column, and return codes; on success it chains to `BLINK` |
| `MESSAGE.ASM` | `MS_` | Overlay `DIAG`: diagnostics by the reference's numbers, with their part, line and column, their text and arguments from `BASIE.MSG`, or the number and arguments without it; the decimal printer `SH_NUM` |
| `COMMAND.ASM` | `CL_` | The command line: the parts' names and every option of toolchain §5.3, checked as `BLINK` checks them; overlay `COMMAND` |
| `LIBRARY.ASM` | `LB_` | Overlay `START`, its two entries: the library check (header, version, helper-table key) and the streams' flags; then the compilation stamp, the streams opened and the parts named in the line stream |
| `PARTS.ASM` | `SH_` | Overlay `PARTS`: the parts loaded into memory and described in the part table, each part's include lines read and the parts they name loaded first (D33) |
| `FILENAME.ASM` | `CL_` | A CP/M file name parsed into the FCB; in the `COMMAND` and `PARTS` overlays |
| `PARTNAME.ASM` | `SH_` | The parts' names, the command line's and the part table's, spelled for the line stream and diagnostics; in the `COMMAND`, `START`, `DIAG` and `PARTS` overlays |
| `OVERLAY.ASM` | `OV_` | Resident: the overlay loader and `BASIE.OVL`'s format |
| `INIT.ASM` | `SH_`, `OV_` | The start-up, in the overlay area: the stack and the source's bounds, `BASIE.OVL` opened and checked (`OV_OPEN`, its header read into the area's last record, `OV_HDR`), then the shell goes on at `SH_GO` |
| `CHAIN.ASM` | `CH_` | The chain to `BLINK.COM`: its tail, and the loader copied to the top of memory; first, after a compilation, the streams closed (`CH_DONE`); overlay `CHAIN` |

`GRAMMAR.ASM` is generated from the grammar, `grammar/grammar.json`, by
`tools/llgen.ts` (`deno task grammar`; [grammar](grammar/README.md)), which
computes the prediction rows and every offset under the `GR_` scheme
([native compiler](../../docs/native-compiler.md) §2);
`tests/llgen_test.ts` checks the tables are current.

## State

| Extent | Bytes |
| --- | ---: |
| Compiler code | 17,494 |
| Immutable data | 290 |
| **Compiler core** | **17,784** |
| CP/M shell and overlay loader | 638 |
| **`BASIE.COM`** | **18,425** |
| Overlay area, after the image | 2,483 |
| `BASIE.OVL` (seven overlays, 7,296 bytes on disk) | 6,592 |
| Compiler workspace (not in the image) | 4,658 |
| Blob writer's workspace (not in the image) | 4,432 |

The image and the overlay area take 20,908 bytes, 5,716 to the 26K target
and 7,764 to the 28K limit (D43). `FLOAT`'s workspace is resident, between
the shell's and the blob writer's, so that it takes no record of the area. The compression pass before step 67c
took 1,626 bytes from the image and the one after 67d 94 more
([native compiler](../../docs/native-compiler.md) §4, which lists what
they did and what remains). Every increment follows D43's cycle: the
increment, a correctness review, a compression pass, a further review when
needed, and the census figure in the commit. `tests/native_compiler_test.ts`
pins the digests of `BASIE.COM` and `BASIE.OVL`, so a change to the
compiler updates them and the sizes in the same commit.

Every module carries the line-by-line commentary that D44 asks for.
