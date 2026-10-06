# Label naming

The Z80 sources of `BASIE.COM` and `BLINK.COM` follow one label convention
(design decision D44), in the style of ATOM's (`../atom/docs/labels.md`).

## Rules

- **Globals are `AREA_WHAT`**, at most eight characters: a short area prefix,
  an underscore, a word. Routines are verbs or operations; variables and
  equates are nouns. Upper case.
- **Only what other routines use is global.** A label used only within its
  owner's scope is private and takes a dotted name (`.LOOP`, `.DONE`, `.BAD`,
  `.TAIL`). The same private name may be reused under different owners but not
  twice under one. Where one scope holds two loops, say which (`.ROWLOOP`,
  `.COLLOOP`), never `.LOOP1`.
- **Words, not consonant strings.** The approved short forms are BEG END NEXT
  PREV FAIL DONE BAD OK LEN PTR IDX TMP ARG CHK NEW CNT MSG ERR SRC DST LO HI
  CFG REC TAB VAL SYM REF OPER PEND CMT PUB ORD CAP RNG TGT PRIV GLOB, and
  COPY JOIN MARK BUF POS NUM INT STR. When a name will not fit, choose another
  word rather than dropping vowels: never names like `PR_NAALI` or `EX_SRIGH`.
- **No disambiguating digits** and **no look-alike pairs**. A trailing digit is
  allowed only when it is part of the meaning (`GX_LD16`, `GR_ROW12`).
- **Markers keep their meaning.** A label that marks an extent is named for
  it, `XX_BEG`/`XX_END` or `XX_BASE`/`XX_LIM` or similar, and stays global.
- **Name by role.** A name says what the routine or datum does, never which
  stage of development introduced it.

## Compiler area prefixes

| Prefix | Area |
| --- | --- |
| `MM_` | Memory map: bases and limits of the image, workspace and target regions |
| `SH_` | The CP/M shell (`SHELL.ASM`), its workspace and messages |
| `CL_` | Command line and file names |
| `OV_` | Overlays |
| `CH_` | The chain loader |
| `MS_` | Diagnostic messages |
| `SRC_`, `PT_` | Source adapter and part descriptors |
| `TK_` | Tokenizer: routines, token kinds, token fields |
| `KW_` | Keyword and punctuation tables |
| `TR_` | The semantic transcript |
| `SY_` | Symbol table |
| `DG_` | Diagnostic numbers and the diagnostic routines |
| `PR_` | Parser driver and its shared helpers |
| `LL_` | The LL(1) engine |
| `GR_` | The generated grammar tables |
| `AC_` | Grammar actions |
| `EX_` | Expression parser |
| `VL_` | Exact and typed constant values |
| `CT_` | Structured control parser |
| `AG_` | Aggregate (record, array, string, constant) parser and its workspace |
| `RO_` | Routine, parameter, call and service parser and its workspace |
| `EM_` | Emitter primitives: bytes, words, patches, labels |
| `BL_` | Blob writing and branch shrinking |
| `OUT_` | The four output streams |
| `BD_` | BDOS entry and function numbers |
| `LB_` | The library check |
| `HP_` | Runtime helpers and predeclared names |
| `GX_` | Expression code generation |
| `RG_` | Routine and call code generation |
| `GA_` | Aggregate code generation |

A workspace variable takes the prefix of the module that owns it, which is the
one that writes it, even when it is defined in `STATE.ASM` or `CALLWORK.ASM`.
The linker's prefixes are listed in its [README](../native/linker/README.md).
