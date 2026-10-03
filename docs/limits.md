# Baton limits register

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
| **Language** | Part of Baton's definition; the same on every implementation |
| **Format** | Set by the object format or a file format |
| **CP/M** | Set by CP/M 2.2 itself |
| **Capacity** | Set by an implementation's memory. Baton 1.0 publishes a **guaranteed minimum** that `BATON.COM` must meet within its 32K workspace, and a program may go beyond it while memory lasts |

## 2. Language limits

| Limit | Value | Reason |
| --- | --- | --- |
| Integer ranges | `u8`, `i8`, `u16`, `i16`, `u32`, `i32` as their widths | D3 |
| `f32` | IEEE single, finite values only | D7 |
| Array length, per dimension | 1 to 65,535 | 16-bit addressing; an array must also fit memory |
| Array dimensions | no fixed limit; each dimension is a separate bound | D32 |
| Bounded string capacity | 1 to 253 | One length byte and one capacity byte per string; large text uses `u8[]` buffers (D25) |
| Record or array extent | 65,535 bytes | 16-bit addressing |
| Failure codes | 256 (`u8`) | D26; 1–31 services, 32–47 the library, 48–253 programs, 254–255 reserved ([services](services.md) §9) |
| Identifier length | 255 bytes | One length byte, as in Nucleus |
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
| Messages in `BATON.MSG` | 65,535 | 16-bit offset table |

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

### 5.1 Compiler (`BATON.COM`, 32K workspace)

| Capacity | Guaranteed minimum | Notes |
| --- | ---: | --- |
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
| Forward jumps outstanding in one routine | 256 | Deferred references (build pipeline §6.2) |
| Source parts included | 255 | The format limit |
| Initialised data and constants | no compiler limit | Written to the byte stream, not held in memory |
| Routine size | no compiler limit | Routines too large for the routine buffer are written unbuffered |

### 5.2 Linker (`BLINK.COM`, about 48K for tables)

| Capacity | Guaranteed minimum | Notes |
| --- | ---: | --- |
| Program blobs | 2,000 | 8 bytes per ordinal |
| Distinct references | 9,000 | 2 bytes each |
| Program size | the CP/M image limit | The tables, not the image, are the constraint |

### 5.3 Running programs

| Capacity | Limit | Notes |
| --- | --- | --- |
| Call depth | memory | No fixed depth; the stack bound and activation checks guard it (memory safety §7) |
| Stack | from `FREE` to the top of memory | Checked at startup against `REQUIRED` |
| Pools | as declared | Fixed at link time; exhaustion traps or returns `none` (D27) |

## 6. Nucleus limits Baton does not inherit

Nucleus's first implementation fixed small limits to fit its 16K compiler. They
are recorded here so that none survives into Baton by accident:

| Nucleus limit | Nucleus value | Baton |
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

- **Confirm the guaranteed minimums** by measuring the native compiler and linker
  (roadmap steps 63 and 68). If a minimum can't be met within the budget, the
  register and the budget are revisited together; the minimum is not silently
  lowered.
- **Longer strings.** Revisit 16-bit string lengths for version 2 if programs
  find `u8[]` buffers clumsy for large text.
