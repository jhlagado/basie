# Baton capacity audit

- Status: **standing practice**, begun 2026-10-04; revised with every limit introduced
- Related: [limits register](limits.md), [build pipeline](build-pipeline.md),
  [object format](object-format.md), [linker](linker.md),
  [implementation plan](implementation-plan.md)

## 1. Purpose

This audit lists every bounded resource found so far in the Baton
specification and implementation, and records for each:

| Field | Meaning |
| --- | --- |
| Resource | What is bounded |
| Minimum guarantee | What a conforming implementation must support |
| Implementation maximum | The actual ceiling of each implementation |
| Cause | Representation, memory budget, ABI, format, algorithm |
| Constant | The named source constant that controls it |
| Overflow | What happens when the maximum is reached |
| Status | Confirmed, TBD, or needs a decision |

It looks for **accidental maxima**: a small table, field width, buffer or test
threshold that has become a restriction without anyone deciding it should be.
A test sets a minimum, and must not quietly set the maximum as well.

### 1.0 Why this is permanent

Baton inherits Nucleus, which carried many unexamined assumptions, and its
development is driven largely by an LLM, which tends to choose the value that
satisfies an acceptance test rather than the best trade-off across the whole
machine. Every limit is therefore a **trade-off to be argued**, not a number to
be inherited. The machine is 64K: the operating system, the compiler, its
workspace, and later the finished program and its own data all share it, so
nothing is unlimited, and a limit that is merely byte-convenient (255, 256)
may be perfectly good, while a limit of 8 of anything is almost always a
mistake that would cripple a real program.

Rules of the practice:

1. Every commit that introduces or changes a table size, field width, buffer,
   or threshold, anywhere in Baton, updates this audit and the
   [limits register](limits.md) in the same commit.
2. Each entry is **classified** (Section 1.3) and says whether its figure is a
   minimum or a maximum.
3. Some entries will stay open for a long time. That is acceptable; an open,
   documented limit is fine, an unexamined one is not.
4. Decisions are made when the competing budgets can be seen together, usually
   when a native component is measured, and are recorded in
   [design decisions](design-decisions.md).

### 1.3 Classification

| Class | Meaning | Who is bound |
| --- | --- | --- |
| **Language** | Part of Baton's definition; changing it changes programs' meaning or validity on every implementation | everyone |
| **Representation** | Set by a format or data layout Baton defines (object format, string header, slot header); changing it is a format revision | every implementation of that format |
| **Machine** | Set by the 64K address space or by CP/M itself | everyone on this target |
| **Implementation** | Set by one implementation's tables or budget; another implementation may differ | that implementation only |

Most of the inventory is Implementation. A few entries are Language in effect
even though they arose from representation, and those need the most care: a
user meets them as a rule of the language.

### 1.1 Implementations covered

| Implementation | State | Where |
| --- | --- | --- |
| Reference toolchain (TypeScript) | Object format, linker, publication, blob-library tool and lexer written; compiler not yet | `ref/`, `tools/` |
| Native `BATON.COM` | Not yet written. It will be forked from the Nucleus compiler (roadmap M7, step 64), so Nucleus's fixed tables are what it **inherits** unless each is replaced deliberately | `../nucleus/asm/vertical-slice/*.asmi` |
| Native `BLINK.COM` | Not yet written; designed in [linker](linker.md) §2 | — |
| `CPM22` runtime | Minimal library written | `runtime/cpm22/` |

The Nucleus constants are recorded so that none of them crosses into Baton by
accident. [Limits](limits.md) §6 already lists the main ones. This audit adds
their source constant names.

### 1.2 Overflow classes

| Class | Meaning |
| --- | --- |
| Grow | Allocate more workspace |
| Spill | Move data to disk |
| Fallback | Switch to a lower-memory method |
| Reject | Issue a defined capacity diagnostic |
| Target | The program can't fit the target address space |
| Representation | A field or encoding can't represent a larger value |

Silent truncation, wrapping, corruption and undocumented failure are never
acceptable.

## 2. Open items and their trade-offs

These are the places where an estimate, a convenient size or an inherited
value is currently acting as a ceiling. Each has a short discussion and, where
one is defensible now, a **working position**: what we live with for the
moment, not a ruling. Rulings go to [design decisions](design-decisions.md).

### 2.1 Deferred references per routine (Implementation)

**Now:** about 256 outstanding forward references per routine, a 1.25K
in-memory list, and the only compiler limit that rejects a routine outright
([build pipeline](build-pipeline.md) §6.2). Minimum equals maximum, and the
number came from a workspace estimate.

**What it really bounds.** Three things share the list: forward jumps to
labels not yet defined, addresses of literals in the literal buffer, and jump
tables. Literals already fall back to inline placement. The jumps are the
problem: a long routine with many `if`s has many of them.

**Options.**

1. *Spill the list* like the in-order references. Awkward: a deferred entry is
   patched when its label is defined, so a spilled entry needs a random write.
2. *Chain fixups through the code.* The classic single-pass method: the
   operand field of each pending forward jump holds the offset of the previous
   pending jump to the same label, and defining the label walks the chain.
   Needs only one word per **label**, and outstanding labels are bounded by
   nesting depth times a small constant, not by jump count. Needs the routine
   buffer, or random writes to the byte stream for an unbuffered routine (CP/M
   random records make that cheap).
3. *Addend in the field.* Let a self-reference's addend live in the stored
   bytes instead of the directory record. Then a forward jump is an **in-order**
   reference (offset, this blob, 0) at emit time, and the compiler patches the
   field when the label is defined. The deferred list then holds only literals
   and jump tables. Cost: a format change ([object format](object-format.md)
   §5), the linker adds the field's value, and placeholder verification no
   longer applies to those fields.

**Decision (2026-10-05, at step 35).** Option 2. The reference compiler's
emitter (`ref/compile/emit.ts`) chains pending forward jumps through their
own operand fields and resolves the chain when the label is defined, so the
number of outstanding forward jumps is unbounded; only undefined labels cost
memory (one word each), and those are bounded by statement nesting. The
native compiler does the same inside its routine buffer and, for a routine
too large for the buffer, with CP/M random-record writes to the byte stream.
The deferred list now holds only literal addresses and jump tables, both of
which already have fallbacks. Option 3 (addend in the field) stays available
as a format refinement but is not needed. The [limits register](limits.md)
row "forward jumps outstanding in one routine" becomes "undefined labels in
one routine", bounded by nesting.

### 2.2 Bounded strings at 253 bytes (Language in effect; Representation in cause)

**Now:** `string[N]`, 1 ≤ N ≤ 253; one length byte and one capacity byte
(D25). A user meets this as a language rule: no string longer than 253.

**Trade-offs.**

- *Keep it.* Smallest header, 8-bit length arithmetic on a Z80, `.length` is a
  `u8`, Nucleus's library and semantics carry over unchanged. Large text goes in
  `u8[]` buffers with an explicit length variable, which is clumsy.
- *16-bit length and capacity.* Two more header bytes per string, every length
  operation is 16-bit (bigger and slower on the Z80), `.length` becomes `u16`
  and so do the loops over it. Lifts the ceiling to the address space.
- *Strings as `u8` vectors with a length.* Treat a string as an array of bytes
  plus a count, unifying it with `u8[]` and open arrays. This is the cleanest
  model, and the one worth thinking about for the long term; it changes the
  type system (what `string[]` parameters are) and the standard library.

**Working position.** Live with 253 for version 1: the specification and the
library are written to it, and a program that needs more has `u8[]`. Record the
vector model as the version 2 question, with the explicit note that the length
representation (one byte or two) is to be chosen then, not inherited.

### 2.3 Inherited Nucleus tables (Implementation)

Every Nucleus table in Section 4 is a defect if it survives the fork
unchanged. **Working position:** at roadmap step 64 the fork is audited
table by table against Section 4 before any Baton feature is added, and each
table gets a named constant, a budget and an overflow class.

### 2.4 Workspace budget for `BATON.COM` (Implementation)

The minimums in [limits](limits.md) §5.1 are not backed by a model showing
they fit together in 32K. **Working position:** build a paper model from
estimated entry sizes before the native compiler starts, so the native work
has a budget to meet rather than a figure to discover, then replace estimates
with measurements at step 68.

### 2.5 Resources missing from the register

Include depth, type descriptors, total name storage, number of pools, scope
nesting, initializer depth, constant-expression nesting and line entries per
routine have no entry. Each is listed as TBD in Section 3 with a first
classification. For include depth the practical cost is small (a file position
and a name per open level, or a 36-byte FCB if the file stays open), so a
byte-convenient maximum would be generous; **8** would be the kind of inherited
value to refuse.

### 2.6 The blob-library tool's 240-blob ceiling (Implementation, tool only)

From the reference-recovery method in `tools/brl.ts`, not from any format.
Lift by batching builds when the runtime approaches it.

### 2.7 The register mixes minimums and maxima

[Limits](limits.md) §2 lists identifier length (255) and string capacity (253)
as *language* limits; the first is an implementation maximum and the second a
representation choice that users meet as a language rule. This pass moves
identifier length to §5 and marks string capacity as under review.

## 3. Inventory

Entries follow the user's numbering. "Ref" is the reference toolchain;
"native" is the planned native toolchain; "Nucleus" is the inherited value.

### 3.1 Top-level names

- **Minimum:** 1,000 ([limits](limits.md) §5.1).
- **Maximum:** ref: memory (JavaScript maps). Native: TBD. Nucleus:
  `SymbolCapacity` = 16, a fixed table.
- **Cause:** native symbol table size within the 32K workspace.
- **Overflow:** must be Reject (capacity diagnostic).
- **Status:** TBD. The native table needs an explicit workspace budget, not
  "whatever is left".

### 3.2 Local names

- **Minimum:** 128 visible in one routine ([limits](limits.md) §5.1).
- **Maximum:** ref: memory. Native: TBD. Nucleus: locals share
  `SymbolCapacity` (16), and are scalar only.
- **Check:** 128 must remain a minimum, not a table size. Nucleus's
  scalar-only-local rule is gone from the language (D8); the fork must not
  keep it in the implementation.
- **Status:** TBD.

### 3.3 Parameters and arguments

- **Minimum:** 32 parameters per routine and 32 arguments per call
  ([limits](limits.md) §5.1).
- **Maximum:** ref: memory. Native: TBD. Nucleus: `Stage7ParameterCapacity` =
  16 (a program-wide parameter table), `Stage7CallFrameCapacity` = 4.
- **Also bounded:** per-parameter metadata (`var`, owning, lease and owner-word
  flags, `from` membership) and result metadata. Encoding widths are TBD.
- **ABI:** the calling convention is not yet fixed (roadmap steps 37 and 56), so any
  register-count effect is TBD.
- **Status:** TBD.

### 3.4 Deferred references (high priority)

- **Minimum:** 256 forward jumps outstanding per routine
  ([limits](limits.md) §5.1).
- **Maximum:** native design: about 256, so the maximum equals the minimum.
  Ref: not yet written.
- **Cause:** an in-memory list of 5-byte entries
  ([build pipeline](build-pipeline.md) §6.2). Literals fall back to inline
  placement when the list fills; forward jumps have no fallback.
- **Constant:** none yet; to be named.
- **Overflow:** Reject, asking for the routine to be split.
- **Status:** **needs a decision** (Section 2, item 1). Covers forward jumps,
  literal addresses and jump-table addresses. In-order references already
  spill to `MAIN.$RF` and have no limit.

### 3.5 Routine code buffer

- **Minimum:** routine size has no compiler limit; routines too large for the
  buffer are written unbuffered ([limits](limits.md) §5.1).
- **Maximum:** blob size 65,535 bytes (object format, 16-bit size). Buffer size
  2K to 4K, TBD ([build pipeline](build-pipeline.md) §6.3 and §8, item 4).
- **Overflow:** Fallback. An unbuffered routine keeps its forward branches long
  and writes its line entries directly. Correctness never depends on the
  buffer.
- **Interaction:** an unbuffered routine still uses the deferred list
  (§3.4).
- **Status:** behaviour confirmed by design; buffer size TBD.

### 3.6 Compiler workspace budget

- **Budget:** 32K workspace for `BATON.COM` (D9).
- **Model:** **missing.** A peak-live model is needed covering: global and
  local symbols, scopes and flow states, type descriptors, constants, routine
  signatures, forward signatures, deferred references, routine buffer, literal
  buffer, branch and line records, include stack, parser state, and I/O buffers
  (four output streams plus the source and the reference spill file, about
  1K at 128 bytes each).
- **Status:** **needs a decision** (Section 2, item 4).

### 3.7 Type descriptors

- **Minimum:** TBD; not in the limits register.
- **Maximum:** ref: memory. Native: TBD. Nucleus: `AggregateTypeCapacity` = 8
  interned aggregate types, `AggregateRecordCapacity` = 5,
  `AggregateFieldCapacity` = 12 fields in total; type-metadata capacity has its
  own diagnostic.
- **Dimensions:** distinct types, nesting of arrays of arrays (D32), records,
  pools and handle types, interned descriptor count, bytes per descriptor.
  Ownership descriptors for owning types also go to `rodata` (memory safety
  §5.10).
- **Status:** TBD.

### 3.8 Identifier length

- **Value:** 255 bytes ([limits](limits.md) §2, listed as a language limit).
- **Cause:** a one-byte length, in Nucleus's source-backed names and in the
  name stream (31 bytes there, truncated for reports only).
- **Question:** the spec (§3.5) makes the full spelling the identity and lets
  an implementation impose a published maximum. So 255 is an implementation
  maximum, not a language rule. The register should move it from §2 to §5.
- **Status:** needs reclassification.

### 3.9 Total name storage

- **Minimum:** TBD. **Maximum:** TBD.
- **Note:** Nucleus keeps names in the source ("source-backed"), which costs no
  name pool but needs the source in memory or re-readable. Baton reads source
  from disk in 128-byte records, so the native compiler must copy names. The
  byte budget for them is part of §3.6.
- **Status:** TBD.

### 3.10 Strings

- **Value:** capacity 1 to 253 ([limits](limits.md) §2, D25).
- **Cause:** one length byte and one capacity byte per string; 253 leaves the
  header and a permanent zero within 255.
- **Applies to:** `string[N]` only. Arrays, records and pools have no such
  ceiling ([spec](../spec/08-constants-and-declarations.md) §8.6).
- **Also bounded:** console line input is 253 because of this, though BDOS 10
  allows 255.
- **Status:** **needs a decision** (Section 2, item 2): compact strings, or a
  16-bit length and capacity.

### 3.11 Arrays

- **Value:** 1 to 65,535 elements per dimension; extent at most 65,535 bytes
  ([limits](limits.md) §2).
- **Cause:** 16-bit counts and offsets; the 64K address space. In practice the
  byte extent, not the element count, is the binding limit.
- **Bounds checks:** compare an unsigned 8- or 16-bit index with the bound.
- **Status:** confirmed as a representation maximum. The register should say
  "representation", not "language".

### 3.12 Records

- **Values:** extent at most 65,535 bytes. Fields per record: minimum 64
  ([limits](limits.md) §5.1). Nucleus: 12 fields in total across all records.
- **Field offsets:** 16-bit. Nesting depth and descriptor size: TBD.
- **Status:** field count and nesting TBD.

### 3.13 Pool capacity

- **Slot header:** 6 bytes (generation, owner link, pool), revision 6.1; a
  Representation choice. Each slot costs its record size plus 6.

- **Value:** 1 to 65,535 slots (spec §8.11).
- **Cause:** 16-bit capacity; each slot carries a 6-byte header before the
  record ([memory safety](memory-safety.md) §5.1). Practical capacity is set by
  the address space.
- **Free list:** a handle is an address, so the list needs no index width.
- **Status:** confirmed.

### 3.14 Pool generations

- **Width:** 16 bits. Generation 0 means never used, `$FFFF` means withdrawn.
- **Reuse:** a slot can be allocated 65,534 times, then is withdrawn
  permanently ([memory safety](memory-safety.md) §5.11). The FIFO free list
  spreads reuse, so a 64-slot pool withdraws its first slot after about four
  million frees.
- **Overflow:** the pool slowly shrinks; `new` eventually traps with
  `pool-full`.
- **Status:** confirmed as a deliberate representation choice. The register
  should list it.

### 3.15 Number of pools

- **Minimum / maximum:** TBD; not in the register.
- **Note:** pools are ordinary program blobs, so the format limit is the
  program ordinal space (§3.27). Compiler cost: one symbol and one descriptor
  each.
- **Status:** TBD.

### 3.16 Open files

- **Value:** 1 to 255, chosen with `F=n`, default 4 (D38).
- **Cause:** a one-byte count; the table lives in BSS at 176 bytes per entry
  ([services](services.md) §2). The `FILECOUNT` pseudo-object carries the
  count.
- **Constant:** linker option `files`; runtime entry size is the profile's
  `fileEntrySize`.
- **Status:** confirmed as an implementation maximum.

### 3.17 Source parts

- **Value:** 255 ([limits](limits.md) §3). Nucleus: `SourcePartCapacity` = 8.
- **Cause:** one-byte part numbers in the line stream (format §8) and the line
  table. A representation maximum.
- **Status:** confirmed as a format maximum. The compiler's own limit is TBD.

### 3.18 Include depth

- **Minimum / maximum:** TBD. The spec (§4.3.3) lets an implementation bound
  it, but no figure is given.
- **Cause:** each open include holds a file position (and an FCB if the file
  stays open) plus its name for cycle detection.
- **Status:** TBD; needs a register entry.

### 3.19 Total source size

- **Values:** a source part is at most 65,535 bytes, because line-stream source
  offsets are 16-bit ([limits](limits.md) §3). Total: 255 parts.
- **Note:** the 64K-per-part limit comes from the line stream, not from
  streaming compilation.
- **Status:** confirmed as a format maximum; worth reviewing.

### 3.20 Block and statement nesting

- **Minimum:** 32 ([limits](limits.md) §5.1). Nucleus: `ControlFrameCapacity`
  = 8.
- **Maximum:** TBD. Scope marks and flow states per open block are part of
  the cost.
- **Status:** TBD.

### 3.21 Expression nesting

- **Minimum:** 32 ([limits](limits.md) §5.1). Nucleus:
  `ExpressionStackCapacity` = 16, `HybridLL1StackCapacity` = 64.
- **Distinguish:** parentheses, operator depth, call nesting, constant
  expressions and initializer nesting. TBD for each.
- **Status:** TBD.

### 3.22 Aggregate initializers

- **Depth minimum:** 32 ([limits](limits.md) §6). Nucleus:
  `AggregateInitializerDepthCapacity` = 4.
- **Size:** no compiler limit; initialized data is streamed to the object files
  ([limits](limits.md) §5.1). Nucleus: `AggregateInitializerCapacity` and
  `StaticImageCapacity` = 1,024 bytes.
- **Status:** depth TBD; size confirmed by design.

### 3.23 Constant expressions

- **Intermediate width:** exact integers range from −2^31 to 2^32 − 1
  (spec §8.6); `f32` is exact as at run time.
- **Nesting and evaluation stack:** TBD.
- **Status:** TBD.

### 3.24 Loop counters

- **Decision already made:** a counter is a declared local of any integer type
  (D31, spec §12.4). There is no default counter type and no 8-bit shortcut, so
  loops over arrays of more than 256 elements use a `u16` or wider counter. The
  increment is checked mathematically and traps with `loop-range` rather than
  wrapping.
- **Status:** confirmed. The native code generator must handle every integer
  width; inherited 8-bit-only paths would be defects.

### 3.25 Routines

- **Compiler:** part of the 1,000 top-level names. Nucleus:
  `Stage7RoutineCapacity` = 4.
- **Format:** program ordinals, 64,480 (§3.27).
- **Linker:** 2,000 program blobs minimum ([limits](limits.md) §5.2).
- **Status:** compiler maximum TBD.

### 3.26 Globals by category

- One combined minimum (1,000 names) covers variables, constants, routines,
  records and pools. **Check** that the native compiler has no smaller
  per-category table hiding inside it, as Nucleus does (records 5, routines 4).
- **Status:** TBD.

### 3.27 Object-format ordinals and counts

| Field | Maximum | Encoding | Source |
| --- | --- | --- | --- |
| Program ordinals | 64,480 (`$0400`–`$FFDF`) | `u16` | format §3.2 |
| Library ordinals | 1,023 (`$0001`–`$03FF`) | `u16` | format §3.2 |
| Pseudo-objects | `$FFE0`–`$FFFF`, 10 defined | `u16` | format §3.4 |
| Blob size | 65,535 | `u16` | format §5 |
| References per blob | 65,535 | `u16` | format §5 |
| Reference offset | 65,535 | `u16` escape | format §5.2 |
| Alignment | 256 bytes | 3-bit code | format §5 |
| Name in name stream | 31 bytes | `u8`, truncated for reports only | format §9 |
| Line-table entries | 65,535 | `u16` count | format §11 |
| Library and file offsets | 4 GB | `u32` | format §7.1 |
| Blob-library tool | about 240 blobs per build | `tools/brl.ts`: 0x100 shifts within 64K | Section 2, item 6 |

All are representation maxima, except the blob-library tool's limit, which
comes from its method.

### 3.28 Linker tables

- **Ref:** JavaScript maps, bounded by host memory. No fixed maximum.
- **Native minimums:** 2,000 program blobs at 8 bytes per ordinal; 9,000
  distinct references at 2 bytes each ([limits](limits.md) §5.2).
- **Native maximum:** TBD; the design is "until the table space is exhausted",
  then `L-CAP-TABLES` ([linker](linker.md) §2.2).
- **Status:** to be measured (roadmap step 63).

### 3.29 Relocations in object files

- **Format:** references per blob are a `u16` count (§3.27). There is no
  whole-program count field.
- **Linker:** references are processed per blob while streaming, so only the
  per-ordinal tables stay in memory.
- **Status:** confirmed.

### 3.30 Stack and activation storage

| Item | Value | Status |
| --- | --- | --- |
| Activation size, local aggregates, parameter area | memory; summed into `need(R)` | no fixed limit by design |
| Recursion depth | memory; each cycle passes a checked forward-declared routine | confirmed |
| Stack reserve | `need(main)` + guard band, raised by `STACK=` | confirmed |
| Guard band | profile value, 64 bytes in `CPM22` | confirmed |
| Nucleus | `ActivationCapacity` = 8, a fixed activation-depth limit | must not be inherited |

No conservative estimate here may become a language restriction. `need(R)` is
computed exactly from frames and helper figures.

## 4. Nucleus constants the native compiler would inherit

From `../nucleus/asm/vertical-slice/*.asmi`. Each is a defect if it survives
the fork unchanged.

| Nucleus constant | Value | Baton replacement |
| --- | ---: | --- |
| `SymbolCapacity` | 16 | §3.1, §3.2: at least 1,000 names and 128 locals |
| `Stage7RoutineCapacity` | 4 | §3.25 |
| `Stage7ParameterCapacity` | 16 (program-wide) | §3.3: at least 32 per routine |
| `Stage7CallFrameCapacity` | 4 | §3.21: call nesting |
| `AggregateRecordCapacity` | 5 | §3.7, §3.26 |
| `AggregateFieldCapacity` | 12 (in total) | §3.12: at least 64 per record |
| `AggregateTypeCapacity` | 8 | §3.7 |
| `AggregateInitializerDepthCapacity` | 4 | §3.22: at least 32 |
| `AggregateInitializerCapacity`, `StaticImageCapacity` | 1,024 bytes | streamed; no limit |
| `ControlFrameCapacity` | 8 | §3.20: at least 32 |
| `ExpressionStackCapacity` | 16 | §3.21: at least 32 |
| `HybridLL1StackCapacity` | 64 | parser stack, TBD |
| `EmitControlFixupCapacity`, `EmitControlLabelCapacity` | 32 each | §3.4: per-routine deferred list |
| `EmitBooleanFixupCapacity` | 16 | §3.4 |
| `SourcePartCapacity` | 8 | §3.17: 255 |
| `ActivationCapacity` | 8 | §3.30: memory |
| `SegmentCapacity` | 4 | object-format blobs; none |
| `ServiceInputCapacity` and similar | 4 | `F=n` file table, §3.16 |
| `GeneratedRoDataCapacity` | 1K | streamed; none |
| `RuntimeProgramDataCapacity`, `RuntimeReadOnlyCapacity` | 2K, 4K | linker places everything; none |

## 5. Source-code discipline

- **Named constants.** Every finite capacity in the native compiler and linker
  is a named `EQU` in one file (planned: `limits.asmi`), and in the reference
  toolchain a named export in `ref/limits.ts` where the reference has a limit
  at all. The [limits register](limits.md) maps each published figure to its
  constant.
- **No bare numbers.** A table size, mask or loop bound over a compiler
  structure never appears as a bare literal.
- **Each constant states its overflow class** (Section 1.2) in a comment, and
  each Reject has a conformance or unit test at the boundary.
- **Tests at minimums.** Capacity tests check that the minimum is accepted.
  They don't check that the minimum plus one is rejected unless the minimum is
  also a deliberate maximum.

## 6. Next pass

1. Decide the items in Section 2.
2. Add register entries for every TBD resource, saying for each whether the
   figure is a minimum or a maximum.
3. When the native fork begins (roadmap step 64), trace every table in
   the forked source against this audit, and build the workspace model of
   §3.6 from measured entry sizes.
4. Search the specification and native source for "maximum", "limit",
   "capacity", "too many", "full" and the convenience numbers 8, 16, 32, 64,
   128, 255, 256, 512 and 1024, and add anything found here.
