# The native linker

`BLINK.COM`, the Basie linker for CP/M 2.2, in ATOM source ([linker](../../docs/linker.md),
design decision D44). `tests/blink_test.ts` runs it under the CP/M harness against
the reference linker and pins the image's digest, so a change to the code
updates the digest and the size in the same commit.

```text
deno task census:blink       size by file, against the 12K target and 14K budget
```

## Files

`BLINK.ASM` includes the others in image order and then holds the driver. ATOM
assembles each included file before its includer, so the list is the layout.

| File | Areas | Contents |
| --- | --- | --- |
| `HEAD.ASM` | | The jump to `LK_START` at `$0100` |
| `CPM.ASM` | `CPM_`, `CON_`, `RC_` | BDOS calls, console output, return codes |
| `FILE.ASM` | `FD_`, `FIL_` | Buffered files over CP/M's random-record calls |
| `CRC.ASM` | `CRC_` | CRC-16/CCITT-FALSE |
| `MSG.ASM` | `DG_`, `MSG_` | Diagnostics, with their text from `BASIE.MSG` |
| `TAIL.ASM` | `CMD_`, `OP_`, `OF_`, `OX_`, `SEEN_`, `FN_` | The command tail and its options |
| `PHASEA.ASM` | `RD_`, `DG_`, `TAB_`, `EDGE_`, `PA_` | Reading a directory, the tables, Phase A's records and trailers |
| `CHECKS.ASM` | `DIR_`, `PA_`, `TAB_`, `EDGE_` | The program directory's header, the profile, Phase A's closing checks |
| `PHASEB.ASM` | `PB_`, `TB_`, `DG_` | Phase B, marking; option W's table dump |
| `PHASEC.ASM` | `WK_`, `REF_`, `PC_`, `PF_`, `PS_` | Walking the directories pass by pass, Phase C |
| `PHASED.ASM` | `PD_`, `SRC_`, `OUT_`, `HEX_` | Phase D, writing the image, and Intel HEX |
| `LINES.ASM` | `LN_`, `LT_` | The line stream and the line table |
| `PUBLISH.ASM` | `PUB_` | Publication and clean-up |
| `REPORT.ASM` | `REP_`, `NM_` | Phase E's workspace, report text and the name readers |
| `PHASEE.ASM` | `PE_`, `MAP_`, `SY_` | Phase E: the map and the symbol file |
| `BLINK.ASM` | `LK_`, `LIB_` | The driver and the library's header |

ATOM refuses a source file over 64K, so a module that its commentary pushes
past that is split at routine boundaries into consecutive files: Phase A's
module became `PHASEA.ASM`, `CHECKS.ASM` and `PHASEB.ASM`, `PHASECD.ASM`
became `PHASEC.ASM` and `PHASED.ASM`, and Phase E's became `REPORT.ASM` and
`PHASEE.ASM`.

Each module opens with a banner giving its purpose, principal entries and data
layout. Each routine, private ones included, has a `;@ROUTINE IN … OUT …
CLOBBERS …` contract and a sentence on what it does, and every label,
instruction and data line carries a comment: at column 32 for labels and
`EQU`s, at column 36 for instructions and data.

## Names

The sources follow Basie's label convention ([naming guide](../../docs/naming.md),
in the style of ATOM's `../atom/docs/labels.md`): globals are
`AREA_WHAT` in at most eight characters, made of words; only what other
routines use is global, and loop heads, exits and single-caller helpers are
private to the routine that owns them; markers keep names that say what they
mark. `FREEMEM`, the end of the image where the tables begin, is such a marker.

Besides the approved short forms of that guide, the linker uses FD (file
descriptor), CRC, DIR (directory), LIB (library), PRG (program), SEC (section),
HEX (Intel HEX) and BSS, which are the specification's own terms, and CTRL
(control record), XFER (transfer), REN and DEL (CP/M's rename and delete),
GETB, PUTB and GETW (get or put a byte or word).

| Prefix | Area |
| --- | --- |
| `LK_` | The driver (`BLINK.ASM`) and a helper several areas share |
| `LIB_` | The library: its file, header, table, drive, name and the map's totals for it |
| `PRG_` | The program table and the map's totals for the program |
| `CPM_`, `CON_`, `RC_` | BDOS calls, console output, CP/M 3 return codes |
| `FD_`, `FIL_` | File descriptor layout, and the file routines |
| `CRC_` | The CRC |
| `DG_` | Diagnostics: printing them, their arguments, and the exits that report one and stop |
| `MSG_` | The message file `BASIE.MSG` and the words printed around a message |
| `CMD_`, `FN_` | The command tail, the first part, and a parsed file name |
| `OP_`, `OF_`, `OX_`, `SEEN_` | Option values, the option flags in `OP_FLAGS`, and `OP_SEEN`'s bits for W and the options with values |
| `RD_` | Reading a directory: the reader, the record being read and its file |
| `REF_` | Reading a blob's references |
| `E_`, `EF_`, `K_` | Table entry fields, entry flags, blob kinds |
| `TAB_` | The library and program tables as one: finding an entry, positions |
| `EDGE_` | The edge lists |
| `PS_` | Pseudo-objects: their ordinals and their table |
| `DIR_` | The program's directory file `NAME.$DR` and its header |
| `PA_`, `PB_` | Phase A (read and check) and Phase B (mark) |
| `TB_` | Option W's table dump |
| `PF_` | Fields of the library's profile block |
| `S_`, `WK_` | Sections, and walking the directories pass by pass |
| `PC_`, `FT_`, `DATA_`, `BSS_`, `IMG_` | Phase C (place): the cursor, the file table and the extents it computes |
| `PD_`, `SRC_`, `OUT_` | Phase D (write): the blob byte sources and the output image |
| `HEX_` | The Intel HEX writer |
| `LN_`, `LT_` | The line stream `NAME.$LN` and the line table `NAME.$LT` |
| `PUB_` | Publication, abandoning a failed link and deleting the intermediates |
| `PE_`, `REP_`, `MAP_`, `SY_`, `NM_`, `KIND_` | Phase E: report text, the map, the symbol file, the name readers |

A workspace variable takes the prefix of the area that writes it.

## Renaming

`tools/labels/` holds the label-renaming tools, pointed at `BLINK.ASM`, and
`tools/labels/maps/blink.json` records what each earlier name became, the
privates included (October 2026; the files were split after it, so its
private renames are keyed by the names of that time):

```text
deno run --config deno.runtime.json -A tools/labels/fingerprint.ts $PWD > build/baseline.json
deno run --config deno.runtime.json -A tools/labels/list.ts $PWD native/linker/*.ASM
deno run --config deno.runtime.json -A tools/labels/demote.ts $PWD
deno run --config deno.runtime.json -A tools/labels/apply.ts $PWD MAPS-DIR [--dry]
deno run --config deno.runtime.json -A tools/labels/verify.ts $PWD build/baseline.json MAPS-DIR
```

`list.ts` prints each definition as KEEP or as PRIV under the global that would
own it; `demote.ts` counts the globals that could still be private; `apply.ts`
rewrites the sources and the files a map lists under `others`, refusing a name
defined twice in one scope; `verify.ts` must print `VERIFIED`. Give a new map
its own file in a fresh directory, since `apply.ts` applies every map it finds,
and `blink.json` must not be applied again: some of its new names are other
entries' old ones (`NM_SLOT`).

## Findings of the commentary pass

The D44 pass read every line and changed no code. The faults it found are
fixed, each with a test against the reference linker in `tests/blink_test.ts`,
except these, which the CP/M harness cannot provoke, having no full disk and
no failing rename:

1. `DG_DISK` names `RD_NAME`, the file last read, when the table dump or a
   rename of publication fails; `REP_FAIL` names the report created last,
   which is not always the one that failed, and leaves the other unclosed.
2. The backup rename in `PUB_RUN` and the second open of the library for its
   name section in `PE_RUN` are not checked. On CP/M neither fails unless the
   disk is changed during the run.

Where BLINK still differs from the reference, by design or by size:

- Two live aliases at one address are listed in the symbol file in ordinal
  order; the reference lists them in the order its table first met them.
- The map's totals are 24-bit and printed as signed, so up to 8,388,607.
- `BSS` ending exactly at `$10000` with a stack reserve of 0 is
  `L-FIT-MEMORY`; the reference accepts it. The compiler's reserve is never 0.
- A name of 0 or more than 31 bytes is `L-FORMAT`, as the object format
  says, and `NAME.$NM` from another compilation is `L-STAMP`, as for the
  other program streams; the reference's reader accepts both.
