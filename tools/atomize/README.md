# Naming the converted compiler

The forked Nucleus compiler was converted to ATOM source at step 65.0 by
`tools/atomize.ts` (design decision D44), which was removed once the AZM
sources went; it is in the history at commit `fb22d8a`. Each JSON file
here maps every name a group of modules defines, from its Nucleus spelling to
its ATOM name: `"TokenizerNext": "TK_NEXT"` for a global, `"TokenizerSkipByte":
".SKIP"` for a private label. Together they are the record of what each Nucleus
name became.

The tool wrote worksheets of every definition with the status Skate's rule
gives it (global, or private under its owner), and checked the maps for
length, uniqueness and scope before writing the files.

## Rules

These are ATOM's and Skate's (`../atom/docs/labels.md`, Skate's
`docs/labels.md`):

- **Globals are `AREA_WHAT`**, at most eight characters: a short area prefix,
  an underscore, a word. Routines are verbs or operations; variables and
  equates are nouns. Upper case.
- **Only what other routines use is global.** A label whose status is `PRIVATE
  under OWNER` is mapped to a dotted name (`.LOOP`, `.DONE`, `.BAD`, `.TAIL`).
  It is visible only within its owner's scope, so the same private name may be
  reused under different owners but not twice under one. Where one scope holds
  two loops, say which (`.ROWLOOP`, `.COLLOOP`), never `.LOOP1`. A `GLOBAL`
  label must stay global.
- **Words, not consonant strings.** The approved short forms are BEG END NEXT
  PREV FAIL DONE BAD OK LEN PTR IDX TMP ARG CHK NEW CNT MSG ERR SRC DST LO HI
  CFG REC TAB VAL SYM REF OPER PEND CMT PUB ORD CAP RNG TGT PRIV GLOB, and
  COPY JOIN MARK BUF POS NUM INT STR. When a name will not fit, choose another
  word rather than dropping vowels: never names like `PR_NAALI` or `EX_SRIGH`.
- **No disambiguating digits** and **no look-alike pairs**. A trailing digit is
  allowed only when it is part of the meaning (`GX_LD16`, `GR_ROW12`).
- **Markers keep their meaning.** A name ending in `Start`, `End`, `Base` or
  `Limit` that marks an extent becomes `XX_BEG`/`XX_END`, `XX_BASE`/`XX_LIM`
  or similar, and stays global.
- **Nucleus history goes.** `Stage7`, `Stage8`, `Hybrid`, `Loop` and `Typed`
  were names of Nucleus's development stages. Name by role instead.

## Area prefixes

| Prefix | Area | Nucleus families |
| --- | --- | --- |
| `MM_` | Memory map: bases and limits of the image, workspace and target regions | `CompilerCoreBase`, `SourceBase`, `ProgramDataBase` |
| `SH_` | The CP/M shell (`SHELL.ASM`), its workspace and messages | `Basie*` |
| `SRC_` | Source adapter and part descriptors | `Source*` |
| `TK_` | Tokenizer: routines, token kinds, token fields | `Token*`, `Tokenizer*` |
| `KW_` | Keyword and punctuation tables | `Keyword*` |
| `TR_` | The semantic transcript (sink) | `SemanticSink*`, `Sink*` |
| `OP_` | Transcript operation codes | `Semantic*` operation equates |
| `SY_` | Symbol table | `Symbol*` |
| `DG_` | Diagnostic numbers and the diagnostic routines | `Diagnostic*`, `SetDiag*` |
| `PR_` | Parser driver and its shared helpers | `Parser*`, `Compile*` |
| `LL_` | The LL(1) engine | `HybridLL1*` engine |
| `GR_` | The generated grammar tables | `HybridLL1Row*`, table equates |
| `AC_` | Grammar actions | `Stage7Action*`, action routines |
| `EX_` | Expression parser | `Expression*` parser |
| `CT_` | Structured control parser | `Control*` parser |
| `AG_` | Aggregate (record, array, string, constant) parser and its workspace | `Aggregate*` |
| `RO_` | Routine, parameter, call and service parser and its workspace | `Stage7Routine*`, `Stage7Call*`, `Stage8Service*` |
| `EM_` | Emitter primitives: bytes, words, patches, labels | `Emit*` |
| `TG_` | Placed target output (deleted at 65.4) | `Target*` |
| `GX_` | Expression code generation | `Typed*` emitters |
| `GT_` | Code templates (`GENTMPL.ASM`) | `Typed*Bytes`, `*Prefix` |
| `GC_` | Control code generation | `EmitControl*` generation |
| `RG_` | Routine and call code generation | `Stage7*`/`Stage8*` emitters |
| `GA_` | Aggregate code generation | `EncodeAggregate*` |
| `RT_` | The Nucleus runtime's identity and state (target addresses) | `NucleusRuntime*`, `RunState` |

A workspace variable takes the prefix of the module that owns it, which is the
one that writes it, even when it is defined in `STATE.ASM` or `CALLWORK.ASM`.
