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
| `COMMAND` | `COMMAND.ASM`, `PARTNAME.ASM` | 986 | first, to read the command line |
| `START` | `PARTS.ASM`, `LIBRARY.ASM`, `PARTNAME.ASM` | 727 | to check the library, load the parts, choose the stamp and open the streams |
| `NAMES` | `PREDEF.ASM` | 947 | before the compilation, for all of it: the predeclared names stay where `RO_LIB` reads them, so lookups are as fast as from the image |
| `CHAIN` | `CHAIN.ASM` | 285 | to run `BLINK` |
| `DIAG` | `MESSAGE.ASM`, `PARTNAME.ASM` | 969 | to print a diagnostic |

The overlay area is 1,024 bytes, the largest overlay in whole records. The
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
| `SOURCE.ASM` | `SRC_` | Source parts |
| `TOKEN.ASM` | `TK_` | Tokenizer |
| `TRANSCR.ASM` | `TR_` | The refusal (`DG_NYI`) of constructs whose code generation has not yet moved to blob output |
| `SYMBOLS.ASM` | `SY_` | Symbol table: 96 records of seven bytes |
| `PARSER.ASM` | `PR_` | Parser driver |
| `EXPR.ASM`, `EXTERM.ASM`, `EXOPER.ASM`, `CONTROL.ASM`, `AGGR.ASM`, `ROUTINES.ASM`, `CALLS.ASM` | `EX_`, `CT_`, `AG_`, `RO_` | Expression (three files: ATOM takes at most 64K of source per file), control (frames, conditions and counted loops), aggregate and routine parsing (routine names and signatures, then calls to routines and services, failable calls, File values and aggregate paths, each kept as a place: static, frame, alias or computed) |
| `LL1.ASM`, `GRAMMAR.ASM`, `ACTIONS.ASM`, `ACTSUB.ASM`, `ACTSTMT.ASM` | `LL_`, `GR_`, `AC_` | The LL(1) engine, its tables and their actions (three files: declarations, then routines and failure, then statements and flow) |
| `OUT.ASM`, `BLOB.ASM` | `OUT_`, `BL_` | Output streams and the blob writer: `NAME.$DR`, `$BY`, `$LN`, `$NM` |
| `EMIT.ASM` | `EM_` | Emitter primitives: bytes, references, helper calls, labels and jumps, frame accounting |
| `GENEXPR.ASM` | `GX_` | Expression templates: loads and stores of program variables and of frame slots (near and far), constants, widening, the operators, comparisons, short circuits and conversions |
| `GENAGGR.ASM` | `GA_` | Path templates: a place's address, fields and constant elements, checked elements and characters at run-time indexes, loads and stores at a place (a File's four bytes too), aggregate locals zeroed, initialized and copied, and the routine's string literals, placed after its need word |
| `GENCALL.ASM` | `RG_` | Routine and declaration blobs, ordinals, prologues (checked for a forward routine) and exits (through `RETN` when there are arguments), the entry and limits records |
| `KEYWORDS.ASM` | `KW_` | Keyword and punctuation tables |
| `PREDEF.ASM` | `HP_` | Overlay `NAMES`: the predeclared names: constants, `console` and `printer`, and the services with their signatures, ordinals and stack figures, generated from the reference's helper table and `ref/compile/helpers.ts` by `deno task helpers` (`tests/helper_table_test.ts` checks it is current) |
| `SHELL.ASM` | `SH_` | The CP/M shell: its course, source parts, streams on the spool drive (deleted after a failure unless option `K`), diagnostics with their part, line and column, and return codes; on success it chains to `BLINK` |
| `MESSAGE.ASM` | `MS_` | Overlay `DIAG`: diagnostics by the reference's numbers, with their part, line and column, their text and arguments from `BASIE.MSG`, or the number and arguments without it |
| `COMMAND.ASM` | `CL_` | The command line: the parts' names and every option of toolchain §5.3, checked as `BLINK` checks them; overlay `COMMAND` |
| `LIBRARY.ASM` | `LB_` | The library check (header, version, helper-table key) and the compilation stamp; overlay `START` |
| `PARTS.ASM` | `SH_` | Overlay `START`, its entry: the library check, the parts loaded into memory, the stamp, the streams opened and the parts named in the line stream |
| `PARTNAME.ASM` | `SH_` | The parts' saved names, spelled for the line stream and diagnostics; in the `COMMAND`, `START` and `DIAG` overlays |
| `OVERLAY.ASM` | `OV_` | Resident: the overlay loader and `BASIE.OVL`'s format |
| `CHAIN.ASM` | `CH_` | The chain to `BLINK.COM`: its tail, and the loader copied to the top of memory; overlay `CHAIN` |

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
| Compiler code | 12,999 |
| Immutable data | 248 |
| **Compiler core** | **13,247** |
| CP/M shell and overlay loader | 645 |
| **`BASIE.COM`** | **13,895** |
| Overlay area, after the image | 1,024 |
| `BASIE.OVL` (five overlays, 4,352 bytes on disk) | 3,914 |
| Compiler workspace (not in the image) | 3,595 |
| Blob writer's workspace (not in the image) | 3,787 |

The image and the overlay area take 14,919 bytes, 11,705 to the 26K target
and 13,753 to the 28K limit (D43). Every increment follows D43's cycle: the
increment, a correctness review, a compression pass, a further review when
needed, and the census figure in the commit. `tests/native_compiler_test.ts`
pins the digests of `BASIE.COM` and `BASIE.OVL`, so a change to the
compiler updates them and the sizes in the same commit.

The line-by-line commentary that D44 asks for is stage 2 of the conversion,
module by module. Until a module has had that pass, its comments are
Nucleus's. Code written since follows D44 from its first line.
