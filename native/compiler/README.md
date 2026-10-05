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
file before its includer, so the list is the layout.

| File | Area | Contents |
| --- | --- | --- |
| `MEMORY.ASM` | `MM_` | Memory map: the image, workspaces, resident source and the forked target's regions |
| `STATE.ASM`, `CALLWORK.ASM`, `TGTWORK.ASM` | various | Workspace layout, diagnostic numbers, transcript operations, token kinds |
| `RTSTATE.ASM`, `RTIDENT.ASM` | `RT_` | The Nucleus runtime's state and identity, until blob output (65.4) |
| `HEAD.ASM` | `MM_` | The jump to the shell at `$0100` |
| `SOURCE.ASM` | `SRC_` | Source parts |
| `TOKEN.ASM` | `TK_` | Tokenizer |
| `TRANSCR.ASM` | `TR_` | Semantic transcript |
| `SYMBOLS.ASM` | `SY_` | Symbol table |
| `PARSER.ASM` | `PR_` | Parser driver |
| `EXPR.ASM`, `EXTERM.ASM`, `EXOPER.ASM`, `CONTROL.ASM`, `AGGR.ASM`, `ROUTINES.ASM`, `CALLS.ASM` | `EX_`, `CT_`, `AG_`, `RO_` | Expression (three files: ATOM takes at most 64K of source per file), control, aggregate and routine parsing (routine names and signatures, then calls and aggregate paths) |
| `LL1.ASM`, `GRAMMAR.ASM`, `ACTIONS.ASM`, `ACTSUB.ASM`, `ACTSTMT.ASM` | `LL_`, `GR_`, `AC_` | The LL(1) engine, its tables and their actions (three files: declarations, then routines and failure, then statements and flow) |
| `EMIT.ASM` | `EM_` | Emitter primitives |
| `TARGET.ASM` | `TG_` | Placed output, deleted at 65.4 |
| `GENEXPR.ASM`, `GENCTRL.ASM`, `GENCALL.ASM`, `GENAGGR.ASM`, `GENTMPL.ASM` | `GX_`, `GC_`, `RG_`, `GA_`, `GT_` | Code generation and its templates |
| `KEYWORDS.ASM` | `KW_` | Keyword and punctuation tables |
| `SHELL.ASM` | `SH_`, `PUB_` | The CP/M shell and the output stubs |

`GRAMMAR.ASM` was generated from Nucleus's grammar (`grammar/stage7-grammar.json`).
The generator, which wrote AZM, was retired with the conversion. Step 67 brings
a generator for Basie's grammar that writes ATOM under the `GR_` scheme
([native compiler](../../docs/native-compiler.md) §2).

## State

| Extent | Bytes |
| --- | ---: |
| Compiler code | 14,893 |
| Immutable data | 393 |
| **Compiler core** | **15,286** |
| CP/M shell | 786 |
| **`BASIE.COM`** | **16,075** |
| Workspace (not in the image) | 3,609 |

That leaves 10,549 bytes to the 26K target and 12,597 to the 28K limit (D43).
Every increment follows D43's cycle: the increment, a correctness review, a
compression pass, a further review when needed, and the census figure in the
commit. `tests/native_compiler_test.ts` pins the image's digest, so a change
to the compiler updates the digest and the sizes in the same commit.

The line-by-line commentary that D44 asks for is stage 2 of the conversion,
module by module. Until a module has had that pass, its comments are
Nucleus's.
