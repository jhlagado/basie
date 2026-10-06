# The native compiler

`BASIE.COM`, in ATOM source (design decision D44). The compiler began as a fork
of the Nucleus native compiler at Nucleus commit `8d1ed07` (roadmap step 64).
At step 65.0 it was converted from AZM syntax to ATOM. The conversion resolved
the build-time conditionals for `BASIE.COM`'s configuration and gave every name
an ATOM name under the label convention ([naming guide](../../tools/atomize/README.md)).
ATOM assembles the result to an image byte-identical to the AZM build. The
Nucleus sources are licensed GPL-3.0-only; Basie has not yet chosen its
licence.

```text
deno task build:compiler     build BASIE.COM and BASIE.OVL and report the extents
deno task grammar            generate GRAMMAR.ASM from grammar/grammar.json
deno task census:basie       size by file, against the 26K target and 28K limit,
                             then the overlays and the overlay area
```

## Files

`BASIE.ASM` includes the resident files in image order. ATOM assembles each
included file before its includer, so the list is the layout, and
`BASIE.ASM`'s own lines, the markers that end the shell and the image and
begin the overlay area, come last.

The overlays are not included: `build.ts` assembles each on its own at its
load address in the overlay area (`OV_AREA`, the image's end), against an
equate for every resident name it uses (`build/ovl/NAME/RESIDENT.ASM`), and
writes `BASIE.OVL` (`OVERLAY.ASM` describes the file and the loader).
Wherever `BASIE.COM` goes, `BASIE.OVL` goes with it: the CP/M harness's
disks in the tests and the Triptych machine's.

| Overlay | Files | Bytes | Loaded |
| --- | --- | ---: | --- |
| `COMMAND` | `COMMAND.ASM`, `FILENAME.ASM`, `PARTNAME.ASM` | 978 | first, to read the command line |
| `START` | `LIBRARY.ASM`, `BLOPEN.ASM`, `PARTNAME.ASM` | 808 | to check the library, then, once the parts are loaded, to choose the stamp, open the streams and name the parts |
| `NAMES` | `PREDEF.ASM` | 947 | before the compilation, for all of it: the predeclared names stay where `RO_LIB` reads them, so lookups are as fast as from the image |
| `CHAIN` | `CHAIN.ASM`, `BLCLOSE.ASM` | 448 | after a compilation, to close the streams and, unless option C, run `BLINK`; with option X, to run `BLINK` alone |
| `DIAG` | `MESSAGE.ASM`, `PARTNAME.ASM` | 1,023 | to print a diagnostic |
| `PARTS` | `PARTS.ASM`, `FILENAME.ASM`, `PARTNAME.ASM` | 915 | to load the parts and the parts they include |

The overlay area is 1,024 bytes, the largest overlay in whole records.
`DIAG` is one byte short of it, so it cannot grow without widening the area
by a record; the others have room, and `START` and `CHAIN` the most. Code
that runs once, before the compilation or after it, belongs in an overlay
rather than the image: the streams' opening code is `START`'s, their
closing code `CHAIN`'s, and the decimal printer `SH_NUM` `DIAG`'s. The
conversion of decimal literals to `f32` is to be an overlay loaded above
`NAMES`, which stays loaded while it is used.

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
| `OUT.ASM`, `BLOB.ASM` | `OUT_`, `BL_` | Output streams and the blob writer: `NAME.$DR`, `$BY`, `$LN`, `$NM` |
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
| `CHAIN.ASM` | `CH_` | The chain to `BLINK.COM`: its tail, and the loader copied to the top of memory; first, after a compilation, the streams closed (`CH_DONE`); overlay `CHAIN` |

`GRAMMAR.ASM` is generated from the grammar, `grammar/grammar.json`, by
`tools/llgen.ts` (`deno task grammar`; [grammar](grammar/README.md)), which
computes the prediction rows and every offset under the `GR_` scheme
([native compiler](../../docs/native-compiler.md) §2);
`tests/llgen_test.ts` checks the tables are current. The grammar began as
Nucleus's, and from the conversion to ATOM until step 67 its tables were
edited by hand.

## State

| Extent | Bytes |
| --- | ---: |
| Compiler code | 15,832 |
| Immutable data | 263 |
| **Compiler core** | **16,095** |
| CP/M shell and overlay loader | 593 |
| **`BASIE.COM`** | **16,691** |
| Overlay area, after the image | 1,024 |
| `BASIE.OVL` (six overlays, 5,632 bytes on disk) | 5,119 |
| Compiler workspace (not in the image) | 4,160 |
| Blob writer's workspace (not in the image) | 3,789 |

The image and the overlay area take 17,715 bytes, 8,909 to the 26K target
and 10,957 to the 28K limit (D43). The compression pass before step 67c
took 1,626 bytes from the image ([native compiler](../../docs/native-compiler.md)
§4, which lists what it did and what remains). Every increment follows D43's cycle: the
increment, a correctness review, a compression pass, a further review when
needed, and the census figure in the commit. `tests/native_compiler_test.ts`
pins the digests of `BASIE.COM` and `BASIE.OVL`, so a change to the
compiler updates them and the sizes in the same commit.

The line-by-line commentary that D44 asks for is stage 2 of the conversion,
module by module. Until a module has had that pass, its comments are
Nucleus's. Code written since follows D44 from its first line.
