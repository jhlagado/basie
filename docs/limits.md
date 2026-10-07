# Basie limits register

- Status: working record (roadmap step 4)
- Date: 2026-10-04
- Related: [implementation plan](implementation-plan.md) §7,
  [design decisions](design-decisions.md), [object format](object-format.md),
  [services](services.md), [capacity audit](capacity-audit.md)

## 1. The rule

**No limit is smaller than memory allows, unless the object format, CP/M or a
measured cost requires it.** Every limit is listed here with its reason, is
published in the documentation, and is reported by a diagnostic or a trap when
reached. No limit may be enforced by wrapping, truncating or silently dropping
anything.

Limits fall into four kinds:

| Kind | Meaning |
| --- | --- |
| **Language** | Part of Basie's definition; the same on every implementation |
| **Format** | Set by the object format or a file format |
| **CP/M** | Set by CP/M 2.2 itself |
| **Capacity** | Set by an implementation's memory. Basie 1.0 publishes a **guaranteed minimum** that `BASIE.COM` must meet within its 32K workspace, and a program may go beyond it while memory lasts |

## 2. Language limits

| Limit | Value | Reason |
| --- | --- | --- |
| Integer ranges | `u8`, `i8`, `u16`, `i16`, `u32`, `i32` as their widths | D3 |
| `f32` | IEEE single, finite values only | D7 |
| Array length, per dimension | 1 to 65,535 | 16-bit addressing; an array must also fit memory |
| Array dimensions | no fixed limit; each dimension is a separate bound | D32 |
| Bounded string capacity | 1 to 253 | One length byte and one capacity byte per string; large text uses `u8[]` buffers (D25). A representation choice that users meet as a language rule; under review in the [capacity audit](capacity-audit.md) §2.2 |
| Record or array extent | 65,535 bytes | 16-bit addressing |
| Failure codes | 256 (`u8`) | D26; 1–31 services, 32–47 the library, 48–253 programs, 254–255 reserved ([services](services.md) §9) |
| Integer literals | the range of the widest integer type, `u32` | D31 |
| Counted-loop step | nonzero, within the counter type's range | spec §12 |
| Pool slots | 1 to 65,535 per pool; an identifier holds the slot address | memory safety §5.11 |
| Files open at once | 1 to 255, chosen with `F=n`, default 4 | D38: one-byte slot in a file number |

## 3. Format limits

| Limit | Value | Reason |
| --- | --- | --- |
| Program ordinals | 64,480 | Object format §3.2 |
| Library ordinals | 1,023 | Object format §3.2 |
| Blob size | 65,535 bytes | 16-bit size field |
| References per blob | 65,535 | 16-bit count |
| Source part length | 65,535 bytes | 16-bit offsets in positions; lines are 16-bit and columns one byte (255 for 255 or beyond) in the line stream |
| Source parts in one program | 255 | One-byte part numbers in the line stream |
| Name length in the name stream | 31 bytes | Object format §9; names are truncated only in reports, never in compilation |
| Messages in `BASIE.MSG` | 65,535 | 16-bit offset table |

## 4. CP/M limits

| Limit | Value | Reason |
| --- | --- | --- |
| File names | 8.3, with an optional drive; no user-number syntax; types beginning `$` reserved for temporaries | CP/M directory entries ([services](services.md) §4.1) |
| Console line input | 253 characters | The string capacity; BDOS 10 itself allows 255 |
| Command tail | 127 characters | The CCP's buffer at `$0080` |
| Directory searches in progress | 1 | BDOS 17 and 18 keep their directory cursor inside the BDOS; any other disk call ends a search |
| File size | 8 megabytes | CP/M 2.2's random record range |
| Program image | below the CCP base, about 56K on a 62K system | The CCP's loader ([CP/M target](cpm-target.md) §4.2) |
| Return codes | CP/M 3 only | BDOS 108 doesn't exist on 2.2 |

## 5. Capacity limits and their guaranteed minimums

Each is bounded only by memory. The guaranteed minimum is an acceptance target
for the native compiler and linker; the reference toolchain has no such limits.
The figures are first estimates, to be confirmed by measurement in roadmap
steps 63 and 68.

### 5.1 Compiler (`BASIE.COM`, 32K workspace)

These are minimums unless a row says otherwise. Resources not yet listed (include depth, type descriptors, name storage, pools, scope nesting) are TBD in the [capacity audit](capacity-audit.md) §3.

| Capacity | Guaranteed minimum | Notes |
| --- | ---: | --- |
| Identifier length | 255 bytes | One length byte; the full spelling is the identity (spec §3.5), so this is a capacity, not a language rule |
| Top-level names (variables, constants, routines, records, pools) | 1,000 | Shared symbol table |
| Names visible in one routine (parameters and locals) | 128 | Released at the end of each routine |
| Parameters per routine | 32 | |
| Fields per record | 64 | |
| Forward declarations outstanding at once | 128 | |
| Statement and block nesting | 32 | |
| Expression nesting | 32 | |
| Structured-initializer nesting | 32 | |
| Arguments per call | 32 | |
| `select` cases per statement | 256 | |
| Owning locals tracked in one routine | 64 | Flow state per open block |
| Forward jumps outstanding in one routine | no limit | Pending jumps are chained through their operand fields ([capacity audit](capacity-audit.md) §2.1) |
| Undefined labels in one routine | 256 | One word per label while undefined; bounded by statement nesting |
| Source parts included | 255 | The format limit |
| Initialised data and constants | no compiler limit | Written to the byte stream, not held in memory |
| Routine size | no compiler limit | Routines too large for the routine buffer are written unbuffered |

**The native compiler today.** These minimums are the target for the finished
`BASIE.COM`. Until each table is replaced, the native compiler is held to its
fixed tables ([capacity audit](capacity-audit.md) §4) and to the
following limits of its CP/M shell (step 65.2, [native compiler](native-compiler.md) §3):

| Limit | Value | Until |
| --- | --- | --- |
| Source parts on the command line | 8 (`CL_PCAP`), each with the parts it includes | — |
| Source parts in one compilation | 255, the line stream's part number, while memory lasts: each part's bytes and a 21-byte entry in the part table; Error 190 (`source parts`) beyond 255 | — |
| Source text: the largest part, with the parts that include it while it loads, and the retained names | from `$9420` (after the blob writer's 4.3K workspace) up to the part table, which grows down from 1K below the BDOS entry (`$E006` with the BDOS entry at `$E406`): 19,430 bytes, about 19.0K, less 21 bytes a part, on a 62K system. While the parts load, a part's bytes stay until its include lines are read, each 128-byte record fitting below the table before it is copied there; as each part is compiled its bytes are read again at the base, in whole records below the name heap, which grows down from the table. Error 190 (`source size`) beyond | the streaming source adapter (step 67, capacity tables) |
| Includes open at once | 16 (`SH_ICAP`): the parts whose include lines are being read, each holding about 20 bytes of the stack; Error 190 (`include depth`) beyond | measured against the stack at step 68 |
| Include names | a CP/M name with its type, `[d:]name.type`, of the characters CP/M names may hold (services §4.1), at most 14 bytes once decoded; anything else is `include-syntax` (Error 24), where the reference, which allows any byte but a dot, a colon or a wildcard, finds no such file (`include-missing`) | — |
| Diagnostic order across parts | a program with errors in several parts may be reported at another of them first: the reference tokenizes each part whole before it loads the parts the part includes, so a lexical error or a misplaced `include` anywhere in a part comes before any error of its includes, where the native compiler reads only a part's include lines as it loads it and finds the rest as it compiles, part by part in stream order | — |
| Compiler stack | 1K below the BDOS entry | measured at step 68 |
| One blob's bytes | 2,048 (`BL_CCAP`), before its jumps shrink; a larger routine is refused | unbuffered writing of large routines |
| One blob's references | 146 (`BL_RCAP`, kept as given, seven bytes each, until the blob is written) | the 128-byte buffer spilling to `NAME.$RF` (toolchain §3.2) |
| One blob's line entries | 128 statements (`BL_LCAP`, five bytes each until the blob is written) | spilling with the references |
| A routine's short jumps | four bytes each, and four for the table's end, in the free memory between the source's last part and the part table, above the routine's waiting aggregate constants, while the routine is written; Error 190 (`source size`) when they do not fit | — |
| Labels in use at once in one routine | 32 (`EM_LCAP`), two of them the exit and the need word; an `if`, `while`, `for`, `select` or handler frees its labels when it ends (a `select` each arm's at the arm's end), and `and` and `or` theirs when they join, so the count is bounded by nesting (about 3 per level); `DG_LABEL` beyond | — |
| Open `if`, `while`, `for`, `select` and `handle` statements | 8 nested (`CT_FCAP`); `DG_NEST` (Error 190, `nesting`) beyond | 32 (§5.1) with the scoped symbol table (step 67) |
| Routines | 64 besides main (`RO_RCAP`, 16 bytes each); `DG_PROCS` (Error 190, `routines`) beyond | the hashed, scoped symbol table (step 67h) |
| Parameters | 160 in the whole program (`RO_PCAP`, 4 bytes each), and 255 bytes of arguments to one routine; `DG_PARAM` (Error 190, `parameters`) beyond | the symbol table (step 67h) |
| Calls nested in arguments | 8 (`RO_NCAP`); `DG_DEEP` (Error 190, `expression depth`) beyond | measured against the stack at step 68 |
| Nested expressions: parentheses, indexes, arguments, conversions | about 36 levels: each takes about 22 bytes of the 1K stack, and one that would leave less than `EX_SPARE` (192) bytes of it is `DG_DEEP` (Error 190, `expression depth`); unchecked before, 48 levels overran the stack into the part table | 32 (§5.1) |
| Names visible at once | 96 (`SY_CAP`): the program's constants, variables and record types with the current routine's parameters and the locals and local constants of its open blocks (a block's names are released at its end); `DG_SYMS` (Error 190, `symbols`) beyond | the hashed symbol table with a name heap (step 67, capacity tables) |
| One `f32` literal | about 150 significant digits before the point and 100 after (`FL_NB`, 64-byte exact arithmetic), counted from the first digit that is not zero to the last that is not: trailing zeros take no room; `capacity` (Error 190, `f32 digits`) beyond | — |
| One object's initializer | 1,024 bytes staged (`AG_ICAP`); `DG_DATA` (Error 190, `object size`) beyond | writing initializers to the blob as they are parsed |
| Aggregate types | 24 distinct string and array types and records (`AG_TCAP`), 16 records (`AG_RCAP`) and 48 fields in all records together (`AG_FCAP`); `DG_META` (Error 190, `types`) beyond | the scoped symbol table and type descriptors (step 67) |
| `select` labels | 63 ranges (`CT_RCAP`) for the selects open at once, a constant label one range, a list one each; a select's ranges are free when it ends; Error 190 (`labels`) beyond | — |
| String literals in one routine | 48 (`RO_LCAP`), each placed after the routine's need word; `DG_LITS` (Error 190, `literals`) beyond | measured at step 68 |
| Dimensions of one array type | 8 (`AG_DCAP`); `DG_META` (Error 190, `types`) beyond | the type descriptors of step 67 |
| One array type or object | 1,024 bytes (`AG_ICAP`), the initializer staging, even without an initializer; `DG_DATA` beyond | writing initializers to the blob as they are parsed |
| Constructs compiled | those of the claimed programs of 65.4 and step 67 (tests/native_equivalence_test.ts); every other construct is refused with `DG_NYI` (Error 191, `native-unsupported`), among them the type `f32`, a counted loop whose bound or step is 32-bit and whose counter is narrower (the reference's `NotImplemented` too), and `File` fields, elements, results and program-variable initializers | step 67 |
| A routine's aggregate constants | each waits, with its bytes, in the free memory between the source's last part and the part table until the routine's blob is written; Error 190 (`source size`) when they do not fit | writing them to a spill file |
| `File` values | `console`, `printer`, a service's result or a File variable, and only where a File is expected (an argument, an assignment, a File local's initializer); a File as an operand, as in `x = f + 1`, is refused (`type-mismatch`, Error 41, as the reference refuses it) | step 67 |
| `BLINK.COM` when `BASIE` chains to it | must end below the loader `BASIE` leaves under the BDOS entry, 77 bytes with its FCB; `BLINK` is 10.6K | — |
| Option `T`, trap lookup (toolchain §8) | read and checked, then refused as not yet available | a later step |
| Floating-point literals | refused (`DG_NYI`, Error 191) | the decimal-to-`f32` overlay (toolchain §7.3) |
| Overlays | 8 described by `BASIE.OVL` (`OV_DCAP`), in at most 255 records; eight today, so the directory is full and a ninth needs `OV_DCAP` raised: `COMMAND` 978 bytes, `START` 812, `NAMES` 947, `CHAIN` 448, `DIAG` 1,040, `PARTS` 915, `FLOAT` 1,460 and `OWNERS` 1,373, each loaded into the overlay area when needed | — |
| Overlay area | 2,611 bytes after the 22,277-byte resident image: `FLOAT` and `OWNERS` (the larger, 13 records) load above `NAMES`, from its last byte, each replacing the other, and the others at the start; the image and the area together must end below the compiler's workspace at `$6300` (`MM_WBASE`) | — |
| Owners in scope | 16 owning handle locals in scope at once (`FW_CAP`), each tracked for the flow check; Error 190 (`owners`) beyond | the capacity tables (step 67h) |
| Pools | 4 in one compilation (`PL_CAP`), forward or not, each a 7-byte entry; Error 190 (`pools`) beyond; a pool's slots at most 65,535 bytes (`out-of-range`, as the reference) | the capacity tables (step 67h) |
| Owner descriptors | one per owning record, at most 255 entries (Error 190, `types`, beyond); an array inside an array takes one entry per outer element | — |
| Handles | owning handle locals, parameters and results, program variables and fields, `new`, `new?` and `none`, their frees, fields through a handle local and `select` on a handle (leases and identifiers) are compiled (67g.1b), as are var owning handle parameters (slot-holders), parameters of owning record and array types, leases passed to record parameters and `id()` of a lease or a var record parameter, owning arguments to calls inside expressions, `id` parameters, and records, strings and arrays reached through an identifier passed to value parameters as copies (67g.1c); an `id` local's initializer, a handle or owning parameter or result, an owning record or array local whose descriptor no pool has written, an owner's value in an expression or as a source, an identifier or File in an expression but compared with `=` or `<>`, a `move` in a statement that also has `and` or `or`, or in a while's or an assert's condition, `id` results, a var parameter of an owning array type, `id()` of a record that belongs to two pools or to none, a lease from a call's result or an element, a handle followed by an operator where a record is passed, and a parenthesized argument for an aggregate parameter are refused (`DG_NYI`, Error 191) | stage 67g |
| A name in a diagnostic | its first 32 characters (`DG_ALEN`) | — |

### 5.2 Linker (`BLINK.COM`, 10.6K, about 45.4K for tables)

Measured on a CP/M 2.2 system with BDOS at `$E406` (57K transient area),
roadmap step 63, and rescaled for the current image:

| Capacity | Guaranteed minimum | Measured | Notes |
| --- | ---: | ---: | --- |
| Program blobs | 2,000 | about 5,600 with few references (5,450 measured at 12,262 bytes) | 8 bytes per ordinal, plus 4 per blob with references and 2 per distinct reference; `L-CAP-TABLES` beyond |
| Distinct references | 9,000 | shares the same space | 2 bytes each |
| Program size | the CP/M image limit | the image limit, `$DC00` | A 54K program of 1,044 blobs and 8 references each links; code fills the image before references fill the tables |

Table space is the memory from the end of BLINK's image (`FREEMEM`, which is
`$0100` plus the image's length) to the stack margin, 768 bytes below the BDOS
entry. It therefore grows by every byte the image loses. With the image at
10,876 bytes, `FREEMEM` is `$2B7C` and table space is `$E406` − `$0300` −
`$2B7C` = 46,474 bytes (45.4K). At step 63 the image was 12,262 bytes and the
same method gives 45,088 bytes (44.0K; this section said 44.7K then). The blob
count is the step-63 measurement scaled by the ratio of the two, 1.030,
since tables of few references cost the same bytes per blob; it is an estimate
until the capacity run is repeated.

Link time at 4 MHz under the minimal harness, excluding disk time: 2.6 s for
`hello` (910 bytes), 6.3 s for ADVENT (6.4K), 78 s for a 54K program. Option R
adds the `DATA` and `COPY` write passes, one per alignment class of `data`
blobs.

`BLINK.COM` refuses a ROM profile (target class 3 and above) with
`L-RESERVED`: the `CPM22` profile is class 1, and the reference linker's ROM
placement (`DATA` and `BSS` in RAM, only `COPY` stored) is not ported.

### 5.3 Running programs

| Capacity | Limit | Notes |
| --- | --- | --- |
| Call depth | memory | No fixed depth; the stack bound and activation checks guard it (memory safety §7) |
| Stack | from `FREE` to the top of memory | Checked at startup against `REQUIRED` |
| Pools | as declared | Fixed at link time; exhaustion traps or returns `none` (D27) |

## 6. Open items

- **The [capacity audit](capacity-audit.md)** lists every bounded resource with
  its minimum, its maximum in each implementation, its cause and its overflow
  behaviour, and the native compiler's fixed tables. Its Section 2 items need
  decisions, and its TBD resources need entries here.

- **Confirm the guaranteed minimums** by measuring the native compiler and linker
  (roadmap steps 63 and 68). If a minimum can't be met within the budget, the
  register and the budget are revisited together; the minimum is not silently
  lowered.
- **Longer strings.** Revisit 16-bit string lengths for version 2 if programs
  find `u8[]` buffers clumsy for large text.
