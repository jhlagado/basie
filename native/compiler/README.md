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
deno task build:compiler     build and report the extents
deno task census:basie       size by file, against the 26K target and 28K limit
```

## Files

`BASIE.ASM` includes the others in image order. ATOM assembles each included
file before its includer, so the list is the layout, and `BASIE.ASM`'s own
two lines, the markers that end the shell and the image, come last.

Code is generated as it is parsed, in the reference compiler's templates,
and each routine and top-level declaration is written as a blob (design
decision D45; [native compiler](../../docs/native-compiler.md) §2 and §3,
65.4). `tests/native_equivalence_test.ts` compiles every claimed program in
`tests/native/programs` with both compilers and compares the four streams
byte for byte. A construct not yet generated this way is refused with Error
95 (`DG_NYI`).

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
| `PREDEF.ASM` | `HP_` | The predeclared names: constants, `console` and `printer`, and the services with their signatures, ordinals and stack figures, generated from the reference's helper table and `ref/compile/helpers.ts` by `deno task helpers` (`tests/helper_table_test.ts` checks it is current) |
| `SHELL.ASM` | `SH_` | The CP/M shell: its course, source parts, streams on the spool drive (deleted after a failure unless option `K`), diagnostics and return codes |
| `COMMAND.ASM` | `CL_` | The command line: the parts' names and every option of toolchain §5.3, checked as `BLINK` checks them (one-shot code, for an overlay at step 66) |
| `LIBRARY.ASM` | `LB_` | The library check (header, version, helper-table key) and the compilation stamp (one-shot code, for an overlay at step 66) |

`GRAMMAR.ASM` was generated from Nucleus's grammar (`grammar/stage7-grammar.json`).
The generator, which wrote AZM, was retired with the conversion. Step 67 brings
a generator for Basie's grammar that writes ATOM under the `GR_` scheme
([native compiler](../../docs/native-compiler.md) §2). Until then the tables
are edited by hand and the JSON is kept in step with them (65.4 h: locals of
any type, and arrays of arrays; 65.4 i: a local whose type is inferred from
its initializer).

## State

| Extent | Bytes |
| --- | ---: |
| Compiler code | 12,498 |
| Immutable data | 1,194 |
| **Compiler core** | **13,692** |
| CP/M shell | 2,202 |
| **`BASIE.COM`** | **15,897** |
| Compiler workspace (not in the image) | 3,589 |
| Blob writer's workspace (not in the image) | 3,787 |

That leaves 10,727 bytes to the 26K target and 12,775 to the 28K limit (D43).
Every increment follows D43's cycle: the increment, a correctness review, a
compression pass, a further review when needed, and the census figure in the
commit. `tests/native_compiler_test.ts` pins the image's digest, so a change
to the compiler updates the digest and the sizes in the same commit.

The line-by-line commentary that D44 asks for is stage 2 of the conversion,
module by module. Until a module has had that pass, its comments are
Nucleus's. Code written since follows D44 from its first line.
