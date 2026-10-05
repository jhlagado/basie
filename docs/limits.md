# Basie limits register

- Status: working record (roadmap step 4)
- Date: 2026-10-04
- Related: [implementation plan](implementation-plan.md) §7,
  [design decisions](design-decisions.md), [object format](object-format.md),
  [services](services.md); Nucleus's capacity ledger
  (`../../nucleus/docs/implementation-plan.md`)

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
| Counted-loop step | nonzero, within the counter type's range | Nucleus §12 |
| Pool slots | 1 to 65,535 per pool; an identifier holds the slot address | memory safety §5.11 |
| Files open at once | 1 to 255, chosen with `F=n`, default 4 | D38: one-byte slot in a file number |

## 3. Format limits

| Limit | Value | Reason |
| --- | --- | --- |
| Program ordinals | 64,480 | Object format §3.2 |
| Library ordinals | 1,023 | Object format §3.2 |
| Blob size | 65,535 bytes | 16-bit size field |
| References per blob | 65,535 | 16-bit count |
| Source part length | 65,535 bytes | 16-bit source offsets in the line stream |
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

These are minimums unless a row says otherwise. Resources not yet listed (include depth, type descriptors, name storage, pools, scope and initializer nesting) are TBD in the [capacity audit](capacity-audit.md) §3.

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
| Arguments per call | 32 | |
| `select` cases per statement | 256 | |
| Owning locals tracked in one routine | 64 | Flow state per open block |
| Forward jumps outstanding in one routine | no limit | Pending jumps are chained through their operand fields ([capacity audit](capacity-audit.md) §2.1) |
| Undefined labels in one routine | 256 | One word per label while undefined; bounded by statement nesting |
| Source parts included | 255 | The format limit |
| Initialised data and constants | no compiler limit | Written to the byte stream, not held in memory |
| Routine size | no compiler limit | Routines too large for the routine buffer are written unbuffered |

**The native compiler today.** These minimums are the target for the finished
`BASIE.COM`. Until each table is replaced, the native compiler is held to the
forked Nucleus tables ([capacity audit](capacity-audit.md) §4) and to the
following limits of its CP/M shell (step 65.2, [native compiler](native-compiler.md) §3):

| Limit | Value | Until |
| --- | --- | --- |
| Source parts on the command line | 8 (Nucleus `SourcePartCapacity`) | `include` and the part stack (step 67) |
| Source text, all parts together | resident, from `$6800` (after the blob writer's 3.7K workspace) to 1K below the BDOS entry: about 29.75K on a 62K system | the streaming source adapter with a name heap |
| Compiler stack | 1K below the BDOS entry | measured at step 68 |
| One blob's bytes | 2,048 (`BL_CCAP`); a larger routine is refused | branch shrinking and unbuffered writing of large routines |
| One blob's references | 512 bytes encoded (`BL_RCAP`), about 100 references | the 128-byte buffer spilling to `NAME.$RF` (toolchain §3.2) |
| One blob's line entries | 512 bytes encoded (`BL_LCAP`), about 120 statements | spilling with the references |
| Labels in one routine | 32 (`EM_LCAP`), two of them the exit and the need word; `DG_LABEL` beyond | a label table released by nesting (step 67) |
| One object's initializer | 1,024 bytes staged (`AG_ICAP`); `DG_DATA` beyond | writing initializers to the blob as they are parsed |
| Constructs compiled | those of the claimed programs of 65.4 (tests/native_equivalence_test.ts); every other construct is refused with `DG_NYI` (Error 95) | the later stages of 65.4 |

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
10,887 bytes, `FREEMEM` is `$2B87` and table space is `$E406` − `$0300` −
`$2B87` = 46,463 bytes (45.4K). At step 63 the image was 12,262 bytes and the
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

## 6. Nucleus limits Basie does not inherit

Nucleus's first implementation fixed small limits to fit its 16K compiler. They
are recorded here so that none survives into Basie by accident:

| Nucleus limit | Nucleus value | Basie |
| --- | ---: | --- |
| Source parts | 8 | 255 (format) |
| Ordinary binding symbols | 16 | at least 1,000 (§5.1) |
| Non-main routines | 4 | part of the 1,000 names |
| Retained parameters | 16 | 32 per routine |
| Records, fields | 5, 12 | memory; 64 fields per record minimum |
| Expression nesting | 16 | 32 |
| Active control frames | 8 | 32 |
| Branch fixups | 32 | 256 forward jumps per routine; no program-wide table |
| Structured-initializer depth | 4 | 32 |
| Initialised data, constants, zeroed data | 1,024 bytes each | no compiler limit; streamed to the object files |
| Image bytes per bank | 4,096 | the CP/M image limit |
| Activation bytes, activation depth | 3,840, 8 | memory; guarded by the stack bound |
| Service streams | 4 | files chosen with `F=n` |

## 7. Open items

- **The [capacity audit](capacity-audit.md)** lists every bounded resource with
  its minimum, its maximum in each implementation, its cause and its overflow
  behaviour, and the inherited Nucleus tables. Its Section 2 items need
  decisions, and its TBD resources need entries here.

- **Confirm the guaranteed minimums** by measuring the native compiler and linker
  (roadmap steps 63 and 68). If a minimum can't be met within the budget, the
  register and the budget are revisited together; the minimum is not silently
  lowered.
- **Longer strings.** Revisit 16-bit string lengths for version 2 if programs
  find `u8[]` buffers clumsy for large text.
