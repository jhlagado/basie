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
| Source text: the largest part, with the parts that include it while it loads, and the retained names | from `$8484` (after the blob writer's 885-byte workspace) up to the part table, which grows down from the stack, 1.125K below the BDOS entry (`$DF86` with the BDOS entry at `$E406`): 23,202 bytes from 74 (22,502 at 73), about 22.6K, less 21 bytes a part, on a 62K system, shared from 67h.3 with the symbol table, which takes twelve bytes a name above the largest part, and from 68 with the blob being written. While the parts load, a part's bytes stay until its include lines are read, each 128-byte record fitting below the table before it is copied there; as each part is compiled its bytes are read again at the base, in whole records below the name heap, which grows down from the table. Error 190 (`source size`) beyond | the streaming source adapter (step 67, capacity tables) |
| Includes open at once | 16 (`SH_ICAP`): the parts whose include lines are being read, each holding about 20 bytes of the stack; Error 190 (`include depth`) beyond | measured against the stack at step 68 |
| Include names | a CP/M name with its type, `[d:]name.type`, of the characters CP/M names may hold (services §4.1), at most 14 bytes once decoded; anything else is `include-syntax` (Error 24), where the reference, which allows any byte but a dot, a colon or a wildcard, finds no such file (`include-missing`) | — |
| Diagnostic order across parts | a program with errors in several parts may be reported at another of them first: the reference tokenizes each part whole before it loads the parts the part includes, so a lexical error or a misplaced `include` anywhere in a part comes before any error of its includes, where the native compiler reads only a part's include lines as it loads it and finds the rest as it compiles, part by part in stream order | — |
| Compiler stack | 1.125K below the BDOS entry (`MM_STACK`, from 1K at 68, for 32 nested expressions) | — |
| One blob: its bytes, references and line entries | below 16K of bytes (`BL_OVER`, Error 190, `routine size`), and its log while memory lasts: from 68 a blob is built in the free memory of the source area, its bytes after the symbol table and the routine's waiting aggregate constants, moving up as they grow, and its log, seven bytes for each reference, statement, string literal and `select` label (fourteen for a label of a 32-bit subject), below the name heap, moving down as it grows. When they meet, the bytes' whole records spill to `NAME.$CD` (68.4), read back as the blob is written, so the log alone fills memory: Error 190 (`source size`) then. A statement takes about 10 bytes of code and 20 of log; a routine of about 5.4K beside its 9.6K part compiles (`BIGSPILL.BSI`); before 68 the buffers held 2,048 bytes, 146 references and 128 statements | — |
| A routine's short jumps | four bytes each, and four for the table's end, in the free memory between the blob's bytes and its log, while the routine is written; Error 190 (`source size`) when they do not fit | — |
| Labels in use at once in one routine | 128 (`EM_LCAP`, 64 before 68), two of them the exit and the need word; an `if`, `while`, `for`, `select` or handler frees its labels when it ends (a `select` each arm's at the arm's end), and `and` and `or` theirs when they join, so the count is bounded by nesting (about 3 per level); `DG_LABEL` beyond | — |
| Open `if`, `while`, `for`, `select` and `handle` statements | 32 nested (`CT_FCAP`, 16 before 68, so the spec's minimum, §5.1), within a grammar stack of 254 symbols (`LL_CAP`, `grammar stack` beyond); `DG_NEST` (Error 190, `nesting`) beyond | — |
| Routines | while memory lasts (from 74; 255 at 68, 64 before): a routine is named by its record's address, its record, 20 bytes, and its parameters', five bytes each, kept below the name heap once its signature is complete, linked in declaration order; with the name, about 24 bytes a routine without parameters beside the part's source, so 400 such routines compile beside their 6K part, and 600 beside a 9K part do not (`source size`, Error 190) | separate compilation and linking (version 2) |
| Parameters | 64 for one routine (`RO_SCAP`, the signature being parsed), and 255 bytes of arguments to one routine, five bytes each below the name heap with the routine's record, while memory lasts (160 in the whole program before 68); `DG_PARAM` (Error 190, `parameters`) beyond | — |
| Calls nested in arguments | 8 (`RO_NCAP`); `DG_DEEP` (Error 190, `expression depth`) beyond | — |
| Nested expressions: parentheses, indexes, arguments, conversions | 32 with an operator pending at each level, as `x + (x + (...))` (the operand stack, `EX_STCAP`, 32 entries from 16 at 68), and about 39 parentheses without: each level takes about 24 bytes of the stack, and one that would leave less than `EX_SPARE` (192) bytes of it is `DG_DEEP` (Error 190, `expression depth`) | — |
| Names visible at once | while memory lasts: the program's constants, variables and record types with the current routine's parameters and the locals and local constants of its open blocks (a block's names are released at its end), twelve bytes each in a table above the largest part (`SY_BTM`), found through 32 hash chains, growing towards the name heap; Error 190 (`source size`) when they meet | — |
| One `f32` literal | about 150 significant digits before the point and 100 after (`FL_NB`, 64-byte exact arithmetic), counted from the first digit that is not zero to the last that is not: trailing zeros take no room; `capacity` (Error 190, `f32 digits`) beyond | — |
| One object's initializer | at top level, a program variable's or a constant's, below 16K (`AG_TCAPB`, a blob's bytes): up to 1K is staged (`AG_ICAP`), a larger one streamed into its data blob as it is parsed, spilling to disk as a routine's bytes do, so it need not fit beside its part's source (`BIGTEXT.BSI`, 16,320 bytes from a 16.5K part); in a routine's body, a local's or a constant's, 1K staged; `DG_DATA` (Error 190, `object size`) beyond, at the initializer; an object without one, and every type, may be as large as 64K (from 69) | 1K at top level before 74 |
| Aggregate types | 48 distinct string and array types and records (`AG_TCAP`) at once, the types a routine's body makes for its locals released at its end (67h.4a), an open array only of a type whose ID is below `$28` (`types` beyond), 46 records (`AG_RCAP`) and 255 fields in all records together, each a twelve-byte record of the symbol table (`AG_FCAP`); `DG_META` (Error 190, `types`) beyond | the scoped symbol table and type descriptors (step 67) |
| `select` labels | while memory lasts (63 ranges for the selects open at once before 68): each label is an entry of the routine's log, seven bytes (fourteen for a 32-bit subject) kept until the routine is written, checked against its select's earlier labels; a select of 256 cases, the spec's minimum (§5.1), compiles beside its 7K part, its bytes spilling (`CASE256.BSI`); Error 190 (`source size`) beyond | — |
| String literals in one routine | while memory lasts (48 before 68), each an entry of the routine's log after its operand's reference, placed after the routine's need word | — |
| Dimensions of one array type | 8 (`AG_DCAP`); `DG_META` (Error 190, `types`) beyond | the type descriptors of step 67 |
| One array type or object | 65,535 bytes (`out-of-range` beyond, as the reference); 1,024 bytes (`AG_ICAP`) before 69, the initializer staging, even without an initializer | — |
| Constructs compiled | those of the claimed programs of 65.4 and step 67 (tests/native_equivalence_test.ts); every other construct is refused with `DG_NYI` (Error 191, `native-unsupported`), among them a counted loop whose bound or step is 32-bit and whose counter is narrower (the reference's `NotImplemented` too), `File` fields, elements, results and program-variable initializers; local arrays of owning handles and records compile from 69, and from 74 a `var` parameter of an owning array type and a routine's result that is an identifier or an owning aggregate | step 67 |
| A routine's aggregate constants | each waits, with its bytes, in the free memory above the symbol table (moving up as the table grows, `RG_LIFT`) until the routine's blob is written; Error 190 (`source size`) when they do not fit | writing them to a spill file |
| `File` values | `console`, `printer`, a service's result or a File variable, and only where a File is expected (an argument, an assignment, a File local's initializer); a File as an operand, as in `x = f + 1`, is refused (`type-mismatch`, Error 41, as the reference refuses it) | step 67 |
| `BLINK.COM` when `BASIE` chains to it | must end below the loader `BASIE` leaves under the BDOS entry, 77 bytes with its FCB; `BLINK` is 11,632 bytes | — |
| Overlays | 7 described by `BASIE.OVL` (`OV_DCAP`), in at most 255 records, all in use: `BEGIN` 2,465 bytes (the command line, the library check, the parts and the streams, loaded once at the start), `NAMES` 947 (the predeclared names, kept while compiling), `CHAIN` 448, `DIAG` 1,047, `LOOKUP` 1,063 (option T), `FLOAT` 1,460 and `OWNERS` 912 (pool declarations); a build loads `BEGIN`, `NAMES` and `CHAIN`, and `FLOAT` and `OWNERS` when it uses them | — |
| Overlay area | 2,560 bytes, `BEGIN`'s twenty records, after the resident image: `FLOAT` and `OWNERS` load above `NAMES`, from its last byte, each replacing the other, and the others at the start; the image and the area together must end below the compiler's workspace (`MM_WBASE`) | — |
| Owners in scope | 16 owning handle locals in scope at once (`FW_CAP`), each tracked for the flow check; Error 190 (`owners`) beyond | the capacity tables (step 67h) |
| Pools | 4 in one compilation (`PL_CAP`), forward or not, each a 7-byte entry; Error 190 (`pools`) beyond; a pool's slots at most 65,535 bytes (`out-of-range`, as the reference) | the capacity tables (step 67h) |
| Owner descriptors | one per owning record, at most 255 entries (Error 190, `types`, beyond); an array inside an array takes one entry per outer element | — |
| Handles | owning handle locals, parameters and results, program variables and fields, `new`, `new?` and `none`, their frees, fields through a handle local and `select` on a handle (leases and identifiers) are compiled (67g.1b), as are var owning handle parameters (slot-holders), parameters of owning record and array types, leases passed to record parameters and `id()` of a lease or a var record parameter, owning arguments to calls inside expressions, `id` parameters, and records, strings and arrays reached through an identifier passed to value parameters as copies (67g.1c); an `id` local's initializer, a handle or owning parameter or result, an owning record or array local whose descriptor no pool has written, an owner's value in an expression or as a source, an identifier or File in an expression but compared with `=` or `<>`, a `move` in a statement that also has `and` or `or`, or in a while's or an assert's condition, `id()` of a record that belongs to two pools or to none, a lease from a call's result or an element, a handle followed by an operator where a record is passed, and a parenthesized argument for an aggregate parameter are refused (`DG_NYI`, Error 191) | stage 67g |
| A name in a diagnostic | its first 32 characters (`DG_ALEN`) | — |

**Measured (step 68).** On the CP/M harness with the BDOS entry at
`$E406`, `tools/capacity.ts` finds by bisection the largest program of
each shape that `BASIE.COM` compiles, and times builds at 4 MHz,
excluding disk time:

| Capacity | Guaranteed minimum | Measured | Bound |
| --- | ---: | ---: | --- |
| One part of small routines (`sub rN(a as u8) as u8`, a local, a return) | — | 234 routines, 15.1K of source | memory: the part's bytes, the symbols and the routines' records |
| Program variables in one part | 1,000 top-level names | 708 in 11K of source | memory; spread over parts, more fit (below) |
| Locals of one routine | 128 | 476 | memory |
| Statements in one routine, an assignment each | no limit | 413, 7.6K of source | the routine's log (references and statements) in memory beside its part |
| A program in parts of 12 routines and 20 variables | — | 21 parts, 24.3K of source, 252 routines, 420 variables (68) | 255 routines at 68; memory from 74 |
| `select` cases | 256 | 256 (`CASE256.BSI`) | memory |
| Statement nesting | 32 | 32 (`NEST32.BSI`) | `CT_FCAP` |
| Expression nesting | 32 | 32 with an operator pending at each level | `EX_STCAP` and the stack |

Build times at 4 MHz: 0.6 s for `hello`; 6.3 s for `BIGMAIN.BSI` (four
parts, 21K); 11.7 s for `ADVENT.BSI` with the library parts it includes;
14.9 s for `MANYRTN.BSI` (200 routines, 11K); 13.7 s for `BIGSPILL.BSI` (a
5.4K routine, its bytes spilled); 24.2 s for `CASE256.BSI` (a select of
256 cases). Most of a build is the tokenizer and the name lookups: the
keywords are found through an index by first letter, the symbols and the
routines through 32 hash chains each, and the predeclared names by a
linear search. The routine limit, 255, is a byte's numbers; the 1,000
top-level names of the specification are met only with fewer than 255
routines among them.

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
