# Basie capacity audit

- Status: **standing practice**, begun 2026-10-04; revised with every limit introduced
- Related: [limits register](limits.md), [build pipeline](build-pipeline.md),
  [object format](object-format.md), [linker](linker.md),
  [implementation plan](implementation-plan.md)

## 1. Purpose

This audit lists every bounded resource found so far in the Basie
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

A limit chosen to satisfy one acceptance test is rarely the best trade-off
across the whole machine. Every limit is therefore a **trade-off to be argued**, not a
number to be carried over. The machine is 64K: the operating system, the compiler, its
workspace, and later the finished program and its own data all share it, so
nothing is unlimited, and a limit that is merely byte-convenient (255, 256)
may be perfectly good, while a limit of 8 of anything is almost always a
mistake that would cripple a real program.

Rules of the practice:

1. Every commit that introduces or changes a table size, field width, buffer,
   or threshold, anywhere in Basie, updates this audit and the
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
| **Language** | Part of Basie's definition; changing it changes programs' meaning or validity on every implementation | everyone |
| **Representation** | Set by a format or data layout Basie defines (object format, string header, slot header); changing it is a format revision | every implementation of that format |
| **Machine** | Set by the 64K address space or by CP/M itself | everyone on this target |
| **Implementation** | Set by one implementation's tables or budget; another implementation may differ | that implementation only |

Most of the inventory is Implementation. A few entries are Language in effect
even though they arose from representation, and those need the most care: a
user meets them as a rule of the language.

### 1.1 Implementations covered

| Implementation | State | Where |
| --- | --- | --- |
| Reference toolchain (TypeScript) | Object format, linker, publication, blob-library tool and lexer written; compiler not yet | `ref/`, `tools/` |
| Native `BASIE.COM` | Written; several of its tables are still fixed sizes below the Basie minimums (Section 4), each to be replaced deliberately | `native/compiler/` |
| Native `BLINK.COM` | Phases A to E written: .COM, .BIN and Intel HEX, options R, B, V, N, M and Y; ROM profiles refused | `native/linker/` |
| `CPM22` runtime | Minimal library written | `runtime/cpm22/` |

Section 4 lists the native compiler's fixed tables with their source constant
names, so that none of them becomes a Basie limit by accident.

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

These are the places where an estimate, a convenient size or a fixed table
is currently acting as a ceiling. Each has a short discussion and, where
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
  `u8`, and the library and semantics stay as they are. Large text goes in
  `u8[]` buffers with an explicit length variable, which is clumsy.
- *16-bit length and capacity.* Two more header bytes per string, every length
  operation is 16-bit (bigger and slower on the Z80), `.length` becomes `u16`
  and so do the loops over it. Lifts the ceiling to the address space.
- *Strings as `u8` vectors with a length.* Treat a string as an array of bytes
  plus a count, unifying it with `u8[]` and open arrays. This is the cleanest
  model, and the one worth thinking about for the long term; it changes the
  type system (what `string[]` parameters are) and the standard library.

**Settled for version 1** (step 57, on this working position). Live with 253 for version 1: the specification and the
library are written to it, and a program that needs more has `u8[]`. Record the
vector model as the version 2 question, with the explicit note that the length
representation (one byte or two) is to be chosen then, on its merits.

### 2.3 The native compiler's fixed tables (Implementation)

Every table in Section 4 is a defect if it stays below the Basie minimum it
serves. **Working position:** each table has a named constant, a budget and an
overflow class, and is replaced deliberately, at the step named for it.

**At step 65.2** the tables are unchanged. `BASIE.COM` adds a CP/M shell with
three limits of its own, all Reject class and all temporary: eight source parts
on the command line, resident source text (about 33.75K on a 62K system) and
a 1K stack. They are listed in [limits](limits.md) §5.1 under "The native
compiler today", each with the step that removes it.

**At step 66** the one-shot code and the predeclared names leave the
resident image for `BASIE.OVL`. Two limits come with it, both Reject class:
`BASIE.OVL` describes at most 8 overlays (`OV_DCAP`, its directory kept in
the shell's workspace), and the overlay area, as large as the largest
overlay, must end with the image below the compiler's workspace, which
`native/compiler/build.ts` checks. A diagnostic names at most a name's first
32 characters (`DG_ALEN`). All three are in [limits](limits.md) §5.1.

**At step 67a** declarations may come anywhere, with block scope. The
symbol table keeps its 96 records, and scopes are its prefixes: a block's
names follow its enclosing block's, and its end cuts the table back to
where it began, as a routine's end already did (each control frame keeps
the count, `CT_FSYMS`, so the cost is a byte a frame). Locals no longer
have to come first, and the limit that said so is gone, with the refusal
of declarations after `main`.

**At step 67b** the numeric types came. A known value is five bytes, so
the symbol table's records grew from seven bytes to nine (a scalar
constant's value after its payload) and the operand stack's entries from
thirteen to sixteen, and a control frame from sixteen bytes to eighteen
(a long counter's four-byte step); with the folding scratch the
compiler's workspace grew to 3,908 bytes (3,925 at 67e, with a bit for
each parameter a from clause names, `RO_FROM`, a var record's owner word
in the path's block, and the end of a routine's waiting aggregate
constants, which wait in the free memory above the source; 4,160 after the
compression pass before 67c, which starts the LL(1) stack on a page, at
$6000, still below the shell's workspace at $6240). The workspace, the shell's and the blob
writer's, and the source area after them, moved 2K up (`MM_WBASE` `$5000`), so that the
image and the overlay area can grow towards the target; the source area
shrank by as much, to about 26.75K on a 62K system ([limits](limits.md)
§5.1). The 16-bit exact range, refused beyond with `native-exact`, is gone.

**At step 67a** `include` and `private` came, and the eight-part table
went: the parts the command line names and the parts they include are
described in a part table of 21-byte entries that grows down from the top
of the source area as the parts' bytes grow up from its base, so the
count is bounded by memory and by the line stream's one-byte part number,
255. Includes open at once are bounded at 16 (`SH_ICAP`), the stack each
holds being small but not measured yet. Private names need a bit for each
symbol (`SY_PRIV`, 12 bytes) and a flag in each routine record.

**At step 67g** pools and handle types came (67g.1a). A pool is an entry
of seven bytes in a table of four (`PL_CAP`, `pools`, Error 190, beyond):
its ordinal, its record, its visibility, its part and its name's address,
so that a forward pool still open at a part's or the program's end is
named where it was declared. Handle types take type IDs `$68` to `$77`,
four for each pool (owning or `id`, optional or not), so the pools'
count is bounded by the type IDs as well as the table; the capacity
tables of 67h widen both. Each aggregate type has a bit marking it
owning (`PL_OWNB`, 3 bytes) and a word for its owner descriptor's
ordinal (`PL_DESC`, 48 bytes), written once, at the first pool of its
record; a descriptor has at most 255 entries (`types`, Error 190,
beyond). The workspace grew, and the workspaces and the source area moved
1K up (`MM_WBASE` `$5800`), so the source area is 1K smaller, about 24.3K
on a 62K system. A build check keeps the pools' table below the LL(1)
stack (`PL_WEND` at or below `LL_DEPTH`). The descriptor writer is the
eighth overlay, `OWNERS`, so `BASIE.OVL`'s directory (`OV_DCAP`, 8) is
full. With `new` and the frees (67g.1b, `HANDLES.ASM`) the image grew
again, and the workspaces and the source area moved another 1K up
(`MM_WBASE` `$5C00`), so the source area is about 23.3K on a 62K system;
with `select` on handles, $200 more (`$5E00`, about 22.8K), and $100 more
after its review (`$5F00`, about 22.5K). The pool declarations' actions
then moved into the `OWNERS` overlay (918 bytes with the descriptor
writer), so the image shrank by 478 bytes, leaving room below `$5F00`
for the rest of 67g. The flow check of owning handles (`FLOW.ASM`) keeps
each owner's state in byte 7 of its symbol record and, for each control
frame, a four-byte snapshot of the owners' states and a four-byte meet
(`FW_TAB`, 64 bytes), so at most 16 owners may be in scope at once (`owners`,
Error 190, beyond); the table pushed the LL(1) stack a page up, and the
image's growth the workspaces another $100 (`MM_WBASE` `$6000`), so the
source area is about 21.9K on a 62K system, below the 22K the plan
expected before the streaming source of 67h. Owning handle parameters
and results took the workspaces another $100 up (`$6100`, about 21.6K),
and freeing owners on `else fail` another (`$6200`, about 21.4K). The
compression pass after 67g.1c moved a handle select's actions into the
`OWNERS` overlay (1,373 bytes), so the workspaces came back to `$6000`
(about 21.9K); identifiers (67g.1c, second part) took them to `$6200`
(about 21.4K); slot-holders (67g.1c, third part) fitted below it, and
leases and `id()` of records (the fourth) took them to `$6300`
(about 21.1K), and `OWNERS` grew past `FLOAT` to thirteen records, the
overlay area with it (2,611 bytes). The copies of fields reached
through an identifier took the workspaces to `$6400` (about 20.9K), and identifier and
File equality to `$6500` (about 20.6K), and the operand
diagnostics to `$6600` (about 20.4K). The compression pass after
67g moved the blob writer's end and a routine's end into a ninth overlay,
`CLOSE`, and the workspaces came back to `$6300` (about 21.1K). At step 67h
(first part) the routine table went from 32 records to 64 and the parameter
table from 64 to 160, so that the whole standard library and a program of its
own size fit (`parse-integers` was refused); the shell's, the `FLOAT`
overlay's and the blob writer's workspaces moved $300 up, and the source area
after them, from `$8D20`, shrank to about 20.2K until the source streams.
A `new` takes a two-byte frame temporary until its block ends, as the
reference's does; the frees need no table, walking the symbols of each
scope from the control frames' counts.

### 2.4 Workspace budget for `BASIE.COM` (Implementation)

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
byte-convenient maximum would be generous; **8** would be the kind of
convenient value to refuse.

### 2.6 The blob-library tool's 240-blob ceiling (Implementation, tool only)

From the reference-recovery method in `tools/brl.ts`, not from any format.
Lift by batching builds when the runtime approaches it. With the services in
place the runtime is 141 blobs (11,220 bytes of library), so about 100 remain;
the standard library is Basie source and does not count against it.

### 2.7 The register mixes minimums and maxima

[Limits](limits.md) §2 lists identifier length (255) and string capacity (253)
as *language* limits; the first is an implementation maximum and the second a
representation choice that users meet as a language rule. This pass moves
identifier length to §5 and marks string capacity as under review.

## 3. Inventory

Entries follow the user's numbering. "Ref" is the reference toolchain;
"native" is the native toolchain.

### 3.1 Top-level names

- **Minimum:** 1,000 ([limits](limits.md) §5.1).
- **Maximum:** ref: memory (JavaScript maps). Native: TBD; 96 records
  (`SY_CAP`) today, a fixed table (Section 4).
- **Cause:** native symbol table size within the 32K workspace.
- **Overflow:** must be Reject (capacity diagnostic).
- **Status:** TBD. The native table needs an explicit workspace budget, not
  "whatever is left".

### 3.2 Local names

- **Minimum:** 128 visible in one routine ([limits](limits.md) §5.1).
- **Maximum:** ref: memory. Native: TBD; at 65.4 (d) locals share the 96
  records of `SY_CAP` with the program's names.
- **Check:** 128 must remain a minimum, not a table size. Locals may be
  aggregates (D8); the native compiler must not restrict them to scalars.
- **Status:** TBD.

### 3.3 Parameters and arguments

- **Minimum:** 32 parameters per routine and 32 arguments per call
  ([limits](limits.md) §5.1).
- **Maximum:** ref: memory. Native: TBD; at 65.4 (e) 64 parameters in the
  whole program (`RO_PCAP`) with at most 255 bytes of arguments per routine,
  and calls nested eight deep in arguments (`RO_NCAP`).
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
- **Native compiler at 65.4:** forward jumps cost nothing per jump. Each is
  written at once as an in-order reference whose addend word holds the link
  to the previous pending operand of the same label, and defining the label
  writes its offset into every addend on the chain (`EMIT.ASM`, `EM_LREF`,
  `EM_LDEF`). The bound is on labels in use at once, 32 per routine
  (`EM_LCAP`): from 65.4 (f) each control statement frees its labels when it
  ends and `and` and `or` theirs when they join, so the bound is nesting, not
  routine length; and on the routine's references, 146 of seven bytes
  (`BL_RCAP`, from 67c, when references are kept as given until the
  routine is written, for branch shrinking). A string literal's operand is
  chained the same way, through an entry of the routine's literal table, 48
  of six bytes (`RO_LCAP`, 16 until 67c; `DG_LITS` beyond), which places
  each literal after the need word.

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
- **Native compiler at 67c:** the buffer is 2,048 bytes (`BL_CCAP`) and a
  larger routine is refused (`DG_BLOB`): every routine of the corpus is
  below 1,700 bytes, so the unbuffered fallback is not built. Branch
  shrinking runs on every routine, as the reference's default build does;
  its table of short jumps, four bytes each, lives in the free memory
  above the source while the routine is written (`source size` when it
  does not fit). The source area shrank by 384 bytes for the larger
  reference and line buffers, to about 26.4K on a 62K system.

### 3.6 Compiler workspace budget

- **Budget:** 32K workspace for `BASIE.COM` (D9).
- **Model:** **missing.** A peak-live model is needed covering: global and
  local symbols, scopes and flow states, type descriptors, constants, routine
  signatures, forward signatures, deferred references, routine buffer, literal
  buffer, branch and line records, include stack, parser state, and I/O buffers
  (four output streams plus the source and the reference spill file, about
  1K at 128 bytes each).
- **Status:** **needs a decision** (Section 2, item 4).

### 3.7 Type descriptors

- **Minimum:** TBD; not in the limits register.
- **Maximum:** ref: memory. Native: TBD; type-metadata capacity has its own
  diagnostic. At 65.4 (h) the native compiler holds 24 types
  (`AG_TCAP`), 16 records (`AG_RCAP`) and 48 fields in all (`AG_FCAP`),
  `DG_META` beyond, and an array type of up to eight dimensions
  (`AG_DCAP`, `DG_BOUND` beyond), whose bounds wait until the type is
  complete ([limits](limits.md) §5.1).
- **Dimensions:** distinct types, nesting of arrays of arrays (D32), records,
  pools and handle types, interned descriptor count, bytes per descriptor.
  Ownership descriptors for owning types also go to `rodata` (memory safety
  §5.10).
- **Status:** TBD.

### 3.8 Identifier length

- **Value:** 255 bytes ([limits](limits.md) §2, listed as a language limit).
- **Cause:** a one-byte length, in the compiler's names and in the name
  stream (31 bytes there, truncated for reports only).
- **Question:** the spec (§3.5) makes the full spelling the identity and lets
  an implementation impose a published maximum. So 255 is an implementation
  maximum, not a language rule. The register should move it from §2 to §5.
- **Status:** needs reclassification.

### 3.9 Total name storage

- **Minimum:** TBD. **Maximum:** TBD.
- **Note:** names kept in the source ("source-backed") cost no name pool but
  need the source in memory or re-readable. Once Basie reads source from disk
  in 128-byte records, the native compiler must copy names. The
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
- **Status:** settled at 253 for version 1 (Section 2.2); the representation
  is to be chosen afresh for version 2.

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
  ([limits](limits.md) §5.1); native today 48 in all records together
  (`AG_FCAP`).
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
- **Cause:** a one-byte count; the table lives in BSS at 184 bytes per entry,
  a 56-byte header and a 128-byte record buffer ([services](services.md) §2).
  The default table is 736 bytes. The `FILECOUNT` pseudo-object carries the
  count.
- **Constant:** linker option `files`; runtime entry size is the profile's
  `fileEntrySize`.
- **Status:** confirmed as an implementation maximum.

### 3.17 Source parts

- **Value:** 255 ([limits](limits.md) §3).
- **Cause:** one-byte part numbers in the line stream (format §8) and the line
  table. A representation maximum.
- **Status:** confirmed as a format maximum. The native compiler's, from
  67a: 255 while memory lasts, each part a 21-byte entry in a part table at
  the top of the source area and its bytes below it; 8 on the command line
  (`CL_PCAP`), each with the parts it includes.
- **Reference toolchain:** takes one part on its command line (`deno task
  basie NAME.BSI`); every other part comes through `include`. It identifies a
  part by its resolved host path and maps every drive letter to its folders.
  These are limits of the reference tool, not of the language.

### 3.18 Include depth

- **Minimum / maximum:** the spec (§4.3.3) lets an implementation bound it.
  Native, from 67a: 16 open at once (`SH_ICAP`), Error 190 (`include
  depth`) beyond.
- **Cause:** a part is read whole before its include lines are, so an open
  include holds no file: only the tokenizer's 14 bytes of state and the
  part's entry on the stack. The cycle check uses the part table, where a
  part whose includes are being read has no number yet.
- **Status:** register entry made ([limits](limits.md) §5.1); the stack
  measurement of step 68 may raise it.

### 3.19 Total source size

- **Values:** a source part is at most 65,535 bytes, because line-stream source
  offsets are 16-bit ([limits](limits.md) §3). Total: 255 parts.
- **Note:** the 64K-per-part limit comes from the line stream, not from
  streaming compilation.
- **Status:** confirmed as a format maximum; worth reviewing.

### 3.20 Block and statement nesting

- **Minimum:** 32 ([limits](limits.md) §5.1).
- **Maximum:** TBD. Scope marks and flow states per open block are part of
  the cost.
- **Native compiler at 65.4 (f):** 8 open `if`, `while`, `for` and `handle`
  statements (`CT_FCAP`, `DG_NEST`), sixteen bytes each, 130 bytes with the
  depth and fallthrough bytes; at 67b eighteen bytes each (a long
  counter's four-byte step), 146 bytes. At 67d a `select` takes a frame
  too, and its labels eight bytes each in a table after the LL(1) stack, 63
  for the selects open at once (`CT_RCAP`, 506 bytes with its top; Error
  190, `labels`, beyond), in what had been the gap between the compiler's
  workspace and the shell's; each label is checked against the earlier
  ones of its select (`duplicate-case`), so a select with n labels costs
  n²/2 comparisons, at compile time only.
- **Status:** TBD.

### 3.21 Expression nesting

- **Minimum:** 32 ([limits](limits.md) §5.1). Native: 16 operand-stack
  entries (`EX_STCAP`) and a 64-symbol grammar stack (`LL_CAP`).
- **Distinguish:** parentheses, operator depth, call nesting, constant
  expressions and initializer nesting. TBD for each.
- **Status:** TBD.

### 3.22 Aggregate initializers

- **Depth minimum:** 32 ([limits](limits.md) §5.1). Native: 4 (`AG_LCAP`).
- **Size:** no compiler limit; initialized data is streamed to the object files
  ([limits](limits.md) §5.1). Native: one object's initializer is staged in
  1,024 bytes (`AG_ICAP`).
- **Status:** depth TBD; size confirmed by design.

### 3.23 Constant expressions

- **Intermediate width:** exact integers range from −2^31 to 2^32 − 1
  (spec §8.6); `f32` is exact as at run time.
- **Native compiler at 65.4 (c):** exact values are folded in sixteen bits,
  unsigned; a result or operand outside 0 to 65,535, a negative one
  included, is refused with `DG_RANGE` rather than folded differently.
  Typed operations wrap at their width, as the spec says.
- **Nesting and evaluation stack:** TBD.
- **Native compiler at 67b:** the exact range of the spec, folded in five
  bytes (`VALUE.ASM`); the 16-bit range and `native-exact` are gone.
- **Status:** TBD for nesting; the range is confirmed.

### 3.24 Loop counters

- **Decision already made:** a counter is a declared local of any integer type
  (D31, spec §12.4). There is no default counter type and no 8-bit shortcut, so
  loops over arrays of more than 256 elements use a `u16` or wider counter. The
  increment is checked mathematically and traps with `loop-range` rather than
  wrapping.
- **Status:** confirmed. The native code generator must handle every integer
  width; 8-bit-only paths would be defects.

### 3.25 Routines

- **Compiler:** part of the 1,000 top-level names; native at 65.4 (e), 64
  routines besides main (`RO_RCAP`, 32 until 67h).
- **Format:** program ordinals, 64,480 (§3.27).
- **Linker:** 2,000 program blobs minimum ([limits](limits.md) §5.2).
- **Status:** compiler maximum TBD.

### 3.26 Globals by category

- One combined minimum (1,000 names) covers variables, constants, routines,
  records and pools. **Check** that the native compiler has no smaller
  per-category table hiding inside it. Today it has two: 16 records
  (`AG_RCAP`) and 64 routines (`RO_RCAP`).
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
| Message file | 65,535 messages; text 255 bytes each; numbers in ranges of 20 to 40 | `u16` offsets, a length byte; ranges in docs/diagnostics.md | Representation; the ranges are a convention, and a full range takes the next free block |
| Blob-library tool | about 240 blobs per build | `tools/brl.ts`: 0x100 shifts within 64K | Section 2, item 6 |
| ATOM's pending-reference arena | 8K by default; `tools/brl.ts` asks for 20K | ATOM `nativeMemoryLayout`; found when the runtime reached 68 blobs | Tool limit; raise again if a build fails with an output-sink error |
| ATOM relative jumps | 128 bytes | Z80 `JR`; ATOM reports it at the label reached | The tool now names the error |

All are representation maxima, except the blob-library tool's limit, which
comes from its method.

### 3.28 Linker tables

- **Ref:** JavaScript maps, bounded by host memory. No fixed maximum.
- **Native minimums:** 2,000 program blobs at 8 bytes per ordinal; 9,000
  distinct references at 2 bytes each ([limits](limits.md) §5.2).
- **Native maximum:** measured (roadmap step 63) and rescaled: table space
  runs from the end of `BLINK.COM`'s image to a 768-byte stack margin, so on a
  57K CP/M 2.2 system it is 46,474 bytes (45.4K) with the image at 10,876
  bytes. Step 63 measured about 5,450 blobs with few references at 12,262
  bytes (45,088 bytes of tables); scaled by table space that is about 5,600,
  after which `L-CAP-TABLES`. With ordinary programs the image limit is
  reached first: a 54K program with 8 references per routine links.
- **Trade-off:** the image shrank by 1,375 bytes in the compression pass after
  option R, and table space grew by the same. About 1,270 bytes of that came
  from buffers whose lives don't overlap sharing memory: the reports' FDs and
  publication's backup FD reuse Phase D's, which are finished with by
  publication, and the command tail and the map's name buffers live in Phase
  D's FDs outside Phase D. The cost is that each shared buffer's lifetime must
  stay disjoint; the comments at each `EQU` record what it relies on.
- **Status:** confirmed as an implementation maximum, set by memory. The 7K
  code estimate in the toolchain was low; the map, the symbol file and
  publication account for most of the difference.
- **ROM targets:** `BLINK.COM` refuses a profile of target class 3 or above
  with `L-RESERVED`. Classified as an implementation limit: no Basie profile is
  a ROM target yet, and porting the reference's ROM placement would cost code
  for a case nothing builds.

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
| Frame slot reach | any 16-bit offset: slots within IX−128..IX+127 use `(IX+d)`, slots beyond it a computed address | confirmed; a 200-byte local array once wrapped `(IX+d)` and corrupted the frame. The native compiler has both forms from 65.4 (d) (`GX_FACC`; `FARFRAME` in its equivalence test) |
| Recursion depth | memory; each cycle passes a checked forward-declared routine | confirmed |
| Stack reserve | `need(main)` + guard band, raised by `STACK=` | confirmed |
| Guard band | profile value, 64 bytes in `CPM22` | confirmed |
| Helper stack figures | computed per helper by `tools/stack.ts`; the largest ending path is 26 bytes, within the guard band ([helper table](helper-table.md)) | confirmed; a test checks every ending path against the guard band and every measured figure against the computed one |

No conservative estimate here may become a language restriction. `need(R)` is
computed exactly from frames and helper figures.

## 4. The native compiler's fixed tables

`native/compiler/STATE.ASM`, `CALLWORK.ASM` and the modules named. Each is a
defect if it stays below the Basie minimum it serves; each has a named
constant, a capacity diagnostic and a budget to argue.

| Table | Native today | Basie target |
| --- | --- | --- |
| Symbol records | 96 (`SY_CAP`), nine bytes each, shared by the program's names and the current routine's parameters, locals and local constants, released at each block's end; the aggregate type and a scalar constant's five-byte value held in the record | §3.1, §3.2: at least 1,000 names and 128 locals; a hashed table with a name heap replaces it in step 67's capacity stage |
| Routine records | 64 besides main (`RO_RCAP`), twelve bytes each, holding each routine's ordinal, need and argument bytes | §3.25 |
| Parameters | 160 program-wide (`RO_PCAP`), and 255 bytes of arguments per routine | §3.3: at least 32 per routine |
| Calls nested in arguments | 8 (`RO_NCAP`); a call being parsed keeps its state on the machine stack | §3.21: call nesting |
| Record types | 16 (`AG_RCAP`) | §3.7, §3.26 |
| Fields | 48 in all records together (`AG_FCAP`) | §3.12: at least 64 per record |
| Aggregate types | 24 (`AG_TCAP`) | §3.7 |
| Initializer nesting | 4 (`AG_LCAP`) | §3.22: at least 32 |
| Initializer staging | one object's initializer in 1,024 bytes (`AG_ICAP`); each declaration is otherwise written as its blob at once | §3.22: no compiler limit, to be streamed |
| Control frames | 8 (`CT_FCAP`), eighteen bytes each, holding the frame's labels, the label count and frame size to restore, and a for loop's counter, bound and step | §3.20: at least 32 |
| Operand stack | 16 entries (`EX_STCAP`), sixteen bytes each: the left operand's five-byte value and the two operands' first offsets | §3.21: at least 32 |
| Grammar stack | 64 symbols (`LL_CAP`) | parser stack, TBD |
| Labels | 32 in use at once per routine (`EM_LCAP`), released by nesting; pending operands are chained through their references' addend words (`EMIT.ASM`, no limit) | §3.4 |
| Source parts | 255 while memory lasts, in a part table that grows down from the top of the source area (`SOURCE.ASM`); 8 on the command line (`CL_PCAP`) | §3.17: 255 |
| Predeclared names | the reference's 58, generated from its helper table into `PREDEF.ASM`; the services' records are read in place, so they have no capacity of their own | — |
| Pools | 4 (`PL_CAP`), seven bytes each (`PL_TAB`), with a bit for each aggregate type marking it owning (`PL_OWNB`) and a word for each holding its owner descriptor's ordinal (`PL_DESC`); handle type IDs are `$68` to `$77`, four forms for each pool; an owner descriptor takes 255 entries | §3.7 |
| Grammar terminals | 46: 45 of the kinds below 62 (`DG_TOKEN` plus a kind is a syntax diagnostic below 190), and `select` at 62, with the five pseudo-kinds of the syntax diagnostics; 12 left free below 62, and 63 for a terminal never expected alone. The eight type keywords are one terminal, `TK_TYPE`, its payload the type; the operators, which only the expression island reads, take kinds from `$44` on, and `new` `$52` (`tests/llgen_test.ts` counts the free kinds) | native compiler §2 |

Code is generated as it is parsed, into a routine's blob ([native
compiler](native-compiler.md) §2); blobs take 16-bit ordinals from `$0400`
(`RG_ORD`), the linker places everything, and activation storage is the
stack (§3.30), so the compiler has no static image, segment, read-only data,
transcript or activation table to bound.

## 5. Source-code discipline

- **Named constants.** Every finite capacity in the native compiler and linker
  is a named `EQU` in one file, and in the reference
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
3. Trace every table in the native source against this audit, and build the
   workspace model of §3.6 from measured entry sizes.
4. Search the specification and native source for "maximum", "limit",
   "capacity", "too many", "full" and the convenience numbers 8, 16, 32, 64,
   128, 255, 256, 512 and 1024, and add anything found here.
