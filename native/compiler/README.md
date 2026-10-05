# The native compiler

`BASIE.COM` starts here as a fork of the Nucleus native compiler (roadmap step
64; implementation plan Phase 6). The sources are Nucleus's at commit
`8d1ed07` (2026-10-05): the 28 assembly files and the generated grammar tables
that the shipping composition `flat-target-z80-slice-proof.asm` includes, with
the grammar's JSON and generator, one proof manifest, and the AZM-to-ATOM
source translation (`tools/`). The Nucleus sources are licensed GPL-3.0-only;
Basie has not yet chosen its licence.

| Path | Contents |
| --- | --- |
| `asm/vertical-slice/` | The compiler, in AZM syntax, as forked |
| `asm/basie/` | `BASIE.COM`: the forked modules behind a CP/M shell ([native compiler](../../docs/native-compiler.md) §3) |
| `grammar/` | The packed LL(1) grammar, its tables and generator |
| `tools/` | The source translation that lets ATOM assemble AZM syntax |
| `proofs/` | Proof manifests, run by `proof.ts` |
| `build.ts` | Builds the image with ATOM and reports its extents |

## Baseline

At the fork the image is byte-identical to Nucleus's own ATOM build, and the
flat-target proof passes with Nucleus's exact counts (1,055,183 instructions,
10,384,694 T-states). `tests/native_compiler_test.ts` checks both.

| Extent | Bytes |
| --- | ---: |
| Compiler code | 14,893 |
| Immutable data | 393 |
| **Compiler core** | **15,286** |
| Workspace (not in the image) | 3,609 |

Against the budget of design decision D43, a 26K target (26,624 bytes) and a
28K limit (28,672), that leaves 11,338 bytes to the target and 13,386 to the
limit for everything Basie adds. Every increment follows the cycle of D43:
the increment, a correctness review, a compression pass, a further review when
needed, and the census figure in the commit.

Nucleus's own AZM proof harness currently fails at assembly because the
installed AZM checks register contracts more strictly than these sources were
written for. Basie builds with ATOM only, which assembles them unchanged.
