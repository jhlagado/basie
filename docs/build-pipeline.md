# Build pipeline

- Status: design overview, revision 5
- Date: 2026-10-03
- Specifications: [object format](object-format.md), [linker](linker.md),
  [toolchain](toolchain.md), [CP/M target](cpm-target.md)
- Research: [linker prior art](research/linker-prior-art.md)

This document explains why Basie builds programs the way it does and how the
pieces fit together. The four specifications above define the details; where
this overview and a specification disagree, the specification governs.

## 1. Summary

Building a Basie program is one command, `BASIE MAIN`, which runs two programs
in turn: the compiler, `BASIE.COM`, and the linker, `BLINK.COM`, which `BASIE`
starts automatically:

1. **Compile.** The compiler reads the source once and generates Z80 machine
   code. It writes the code as **blobs**: one per routine, constant or
   variable, each a run of bytes plus a list of the places that hold
   addresses. It never chooses a final address.
2. **Link.** The linker reads the blobs and a prebuilt **blob library** holding
   the runtime for the target. It keeps only the blobs reachable from its
   roots, assigns their addresses, fills in every address and writes
   the program image.

No assembler takes part. The compiler generates machine code; the linker
writes the binary.

The linker exists for one reason: **tree shaking**. The output contains only the
routines, constants, variables and runtime helpers the program can reach.

## 2. Why a linker

A compiler could emit every byte at its final address as soon as it generated
it, turning forward references into patch records and writing backward
references straight into the image.

Under that model a single-pass compiler cannot drop unused code. A routine's
last possible caller may be the final line of the source, so the routine's
liveness is known only at the end of input. By then it occupies addresses that
later code has been built against. Removing it would shift everything after
it, and nothing records which bytes are addresses.

Any design that removes unused code must therefore:

1. delay the choice of addresses until liveness is known;
2. place code, then move it, which needs a record of every address; or
3. read the source twice.

Reading the source twice breaks Basie's single-pass rule. Options 1 and 2 both
need a record of every address in the code, which is what a relocating linker
works from. Basie takes option 1 and builds a small linker designed for the
purpose, rather than pretending not to need one.

## 3. Design rules

1. **One source pass.** The compiler reads each source byte once. Everything
   after that reads compact binary files.
2. **Machine code from the compiler.** The compiler generates instructions and
   encodes them. No assembler, assembly text or intermediate code is involved.
3. **Ordinals, not names.** Blobs refer to each other by number. The linker
   never compares strings. Names exist only for maps, symbol files and trap
   lookup.
4. **One program per link.** The linker combines one program object with one
   blob library. Source libraries are compiled with the program.
5. **Every address is a reference.** No byte whose value depends on placement
   escapes the reference list. This gives the linker the complete call and data
   graph.
6. **Forward-only I/O.** Every file is written once, sequentially, and read from
   start to end. Readers may skip forward.
7. **Fixups fill in addresses, never meaning.** The linker supplies addresses
   and sizes. It never supplies a type or any other fact the compiler lacked.
8. **Deterministic output.** The same inputs always produce the same image,
   byte for byte.

## 4. How the pieces fit

```text
 MAIN.BSI  UTIL.BSI                     CPM22.BRL
     │         │                     (runtime + profile)
     └────┬────┘                         │      │
          ▼                              │      │
   ┌──────────────┐  header and profile  │      │
   │   compile    │◄─────────────────────┘      │
   └──────┬───────┘                             │
          │ MAIN.$DR  directory: blob records, references
          │ MAIN.$BY  bytes: machine code and data
          │ MAIN.$LN  line stream     MAIN.$NM  name stream
          ▼                                     │
   ┌──────────────┐◄────────────────────────────┘
   │     link     │  A read · B mark · C place · D write · E report
   └──────┬───────┘
          ▼
   MAIN.COM   MAIN.LIN   [MAIN.MAP]   [MAIN.SYM]
```

| Piece | Specified in |
| --- | --- |
| Blobs, ordinals, references, file layouts | [Object format](object-format.md) |
| Reading, marking, placing, writing, reports, diagnostics | [Linker](linker.md) |
| The two programs, command line, file lifecycle, memory plan | [Toolchain](toolchain.md) |
| Profiles, memory map, startup, exit, traps under CP/M | [CP/M target](cpm-target.md) |

## 5. Prior art

The [prior-art survey](research/linker-prior-art.md) examined period CP/M
linkers and modern ones. What Basie borrows, and what it avoids:

| Prior art | What it did | What Basie takes or avoids |
| --- | --- | --- |
| Microsoft REL and `L80`; Digital Research `LINK-80` | Linked whole **modules**; relocatable words said only "relative to the code segment"; names of 6 or 7 characters; a bit-stream encoding | Avoided. Module granularity is why no CP/M linker shook below the module. Basie's unit is the blob, and every reference names its target. Byte-aligned records replace the bit stream so dead blobs can be skipped without decoding. |
| REL chained externals; Oberon fixup chains | Threaded unresolved references through the placeholder bytes | Avoided. Chains can't hold an addend or a byte operand, need random access to the image, and corrupt silently when broken. Basie keeps explicit reference records. |
| M80's late `LOW`/`HIGH` items | Byte references to externals added as an afterthought | Taken from the start: `LO8`, `HI8` and an addend on every form. |
| `LINK-80` IRL index; `LIBR` and `__.SYMDEF` directories | A directory separate from the code, so the linker could find what it needed | Taken: the directory stream and the blob library's directory section hold the graph, so marking never reads code bytes. |
| `L80`'s whole image in RAM; `LINK-80`'s spill files | Memory limits shaped the linker | Avoided: Basie's linker holds per-ordinal tables only and streams bytes from disk to output, with a stated capacity error. |
| Turbo Pascal 4 smart linking | Removed unused routines because each routine was its own block with its own fixups | Taken: the closest precedent for Basie's design, on the same class of machine. Its weak point, `.OBJ` files and method tables that kept everything alive, is a warning for Basie's runtime and any future dispatch tables. |
| ELF `--gc-sections`, `wasm-ld`, Go | Mark from roots over a reference graph; `KEEP` for things reached by convention; reports of what was removed | Taken: marking from roots, an explicit root flag instead of a convention, and a removal report in the map. |
| Plan 9 `8l` | Chose instruction encodings and shortened branches at link time, holding the whole program in memory | Avoided: branch shrinking stays in the compiler, inside one routine, where the bytes are still in memory. |
| Windows import ordinals; Oberon module keys | Numbered references, which drift when the defining side changes | Taken with the guard: runtime ordinals are append-only, and the linker checks runtime identity and helper-table version before linking. |
| Digital Research PRL, SPR and RSX | Page relocation by bitmap, for whole images | Not needed for 1.0. A page-relocatable output is a possible later output kind, since the linker knows every `HI8` and `ABS16` site. |

The survey found no period CP/M linker that removed code below the module
level. Basie's design differs from them mainly in its unit of linking: the
format makes every routine its own blob, and every address use a named
reference.

## 6. The compiler's side

The specifications define what the compiler must write. This section records
what the compiler does to write it.

### 6.1 What the compiler does not do

- It knows no final address.
- It keeps no program-wide table of unresolved call sites.
- It emits no patch records and no placed image.

### 6.2 What the compiler does

- It chooses a compilation stamp and writes it into the header of every stream.
- It assigns an ordinal to each blob as it meets the declaration, including at
  a forward declaration. It tracks the next free ordinal and the last ordinal
  it wrote, and writes an explicit ordinal whenever a record's ordinal doesn't
  follow the last one written.
- It emits every absolute address operand as zero placeholder bytes, with an
  entry in the routine's pending reference list.
- At the end of each routine or declaration, it writes the blob's record and
  references to the directory stream, sorted by offset. The bytes have already
  gone to the byte stream, unless the routine was buffered for branch shrinking.
- It writes the line-stream and name-stream records for each blob at the same
  time as the blob's directory record, so all three are in directory order.
- It writes the `ENTRY` record naming `main`, and, after the last blob, the
  `LIMITS` record with the stack reserve and recursion flag it knows only at
  the end of input.

**References for one routine.** The record can't be written until the routine
ends, because its header needs the size and reference count and its references
must be sorted. Most references are produced in offset order as code is
emitted: calls, global loads and stores, backward jumps. A few are **deferred**,
because their value is learned later: forward jumps to labels later in the
routine, addresses of literals in the literal buffer, and the address of a jump
table placed after its arms. The compiler handles the two kinds separately:

- **In-order references** are encoded as they are produced into a 128-byte
  buffer, which spills to a scratch file, `MAIN.$RF`, when it fills. They have
  no limit.
- **Deferred references** are held in memory, in a list of about 256 entries
  (5 bytes each, 1.25K). Forward jumps are **not** deferred references: a
  pending jump's operand field holds the offset of the previous pending jump
  to the same label, and defining the label walks the chain and emits the
  self-references in order ([capacity audit](capacity-audit.md) §2.1).
- **At the end of the routine,** the compiler merges the two sorted sequences
  into the directory record, reading the scratch file forward once if it was
  used, and then empties it for the next routine.

When the deferred list fills, further literals are placed inline, which makes
their references in-order. Jump tables go after the arms they dispatch to, so a
table costs one deferred reference, not one per entry. So no count of
references limits a routine; the only per-routine table is the labels not yet
defined, one word each, bounded by nesting. No program-wide table of unresolved
call sites is needed.

### 6.3 Shorter forward branches

A streaming compiler must emit a forward branch before it knows the distance,
so it must choose a 3-byte `JP` where a 2-byte `JR` would often do. With a bounded
routine buffer, the compiler can recover most of that byte:

1. Generate the routine into the buffer, emitting every forward local branch as
   `JP`. Record every relative and local branch: its site, its target label, and
   whether it may shrink. Record backward `JR` and `DJNZ` too, although they are
   already short.
2. At the end of the routine, find the fixed point on offsets alone, without
   moving bytes. Start with every forward `JP` long; in each pass, mark short
   every `JP` whose distance fits a `JR` given the current choices. Shortening a
   branch only shortens distances, so a branch that fits keeps fitting, and the
   passes end when one changes nothing.
3. Write the routine out in one compaction pass, dropping a byte from each
   shortened branch and re-encoding every relative branch from the final
   offsets. A backward `DJNZ` whose range contains a shortened `JP` would
   otherwise be off by one.
4. Adjust pending reference offsets and self-reference addends to match.

Only forward `JP` instructions to local labels may shrink, and only with a
condition `JR` supports (`Z`, `NZ`, `C`, `NC`, or none). Entries the compiler
flags as fixed-size, such as a table of `JP` instructions indexed by
multiplication, never shrink. A routine too large for the buffer is written as
it is generated, with forward branches left long; correctness never depends on
the buffer.

The estimated cost is a routine buffer of 2K to 4K, about 5 bytes per recorded
branch and 300 to 500 bytes of compiler code.

**Measured gain (2026-10-05, reference compiler):** 1.2% of total image size
across the 62 accepted conformance programs (75,413 to 74,535 bytes; 0.8% to
1.8% per program). The earlier hypothesis of 10% to 15% was wrong: branches are
a small share of the code. The larger costs are the expression scheme (left
operands pushed and popped) and frame access through `IX`, so code-generation
improvements there are worth more than shrinking. The native compiler should
weigh shrinking's 300 to 500 bytes of compiler code against a 1% gain. `JR` is a byte shorter than `JP`;
taken, it costs 12 T-states against 10, and not taken, 7 against 10.

### 6.4 Literals

A string or aggregate literal inside a routine belongs to that routine's blob
([object format](object-format.md), Section 3.1). The compiler can't write a
literal into the byte stream where it meets it, because the routine's code is
still being written there. It holds the routine's literals in a **literal
buffer** and appends them after the routine's code when the routine ends,
reaching each by a self-reference.

If the literal buffer fills, the compiler writes further literals inline at the
point of use, preceded by a jump over them, and loads their address with a
self-reference. The jump is a `JR` (2 bytes) for literals up to 127 bytes and a
`JP` with a self-reference (3 bytes) for longer ones. Correctness never depends
on the buffer's size. Identical literals are not merged. The literal buffer is
about 1K in the first estimate.

### 6.5 Line entries during shrinking

Statement offsets for the line stream move when branches shrink. For a buffered
routine, the compiler holds the routine's line entries, 6 bytes each, and
adjusts them in step 4 of Section 6.3 along with the references. An unbuffered
routine writes its line entries as it generates them, since nothing moves.

### 6.6 Shared tails and fall-through

**Tail calls.** Program routines may tail-call each other with `JP`. Compiled
code never tail-calls a runtime helper, because a trap inside the helper would
then report the wrong call site ([CP/M target](cpm-target.md), Section 10.2).

Blobs may not fall through into one another or share code by adjacency. A tail
shared between routines is an explicit `JP` to a shared blob. The loss is
small: a cross-routine tail would be a `JP` anyway unless the two routines
happened to be adjacent. Hand-written runtime helpers that fall
into one another are either one blob with aliases for their extra entry points,
or separate blobs joined by `JP`, whichever lets programs carry less.

### 6.7 Unused routines in the user's source

The linker removes them. The compiler may still warn about a routine that is
never referenced, since it knows at the end of input, but the warning is
advisory.

## 7. Compared with placing code at emission

| | Final addresses at emission | Basie |
| --- | --- | --- |
| Addresses chosen by | compiler, at emission | linker, after liveness is known |
| Unused code removed | no | yes: routines, data, constants, runtime helpers |
| Cross-routine references | pending table in the compiler, then patches | references in each blob's record |
| Compiler memory for fixups | one entry per unresolved site in the program | one routine's references at a time |
| Forward branches | always `JP` | `JR` where it fits, for buffered routines |
| Runtime | linked whole for the target | blob library; unused helpers removed |
| Output | image and patch spools, merged by a materializer | written in address order by the linker |
| Executables | compiler, plus a materializer | compiler `BASIE.COM` (26K target, 28K limit), then linker `BLINK.COM`, chained automatically |

What does not depend on placement is kept: append-only output files, a CRC that makes
partial output unusable, a publication sequence that never destroys the
previous good output, and the separation between compiling a program and the
target it runs on.

## 8. Costs

- **More disk traffic per build.** The directory stream may be as large as the
  program itself, and the linker reads it at least three times. On the 720K-and-larger
  disks Basie assumes, space is not a concern, but transfer time is. The
  reference density of real compiled code must be measured to size this.
- **Placeholders hide addresses from the compiler.** It cannot fold or compare
  addresses. Basie source cannot observe addresses, so no feature is lost, but
  the backend cannot exploit a particular placement.
- **Granularity is the blob.** Code inside a live routine that is never executed
  is not removed; that is the compiler's job, through constant folding.
- **No incremental builds.** Any edit can renumber ordinals, so a program is
  always compiled and linked whole.
- **Libraries are compiled every build.** Precompiled program libraries would
  need names in the compiler (Section 9.3).

## 9. Other targets and later work

### 9.1 ROM and banked targets

TEC-1 ROM and banked targets are no longer design considerations (design
decision D10). The format keeps its reserved target classes, `BANK` record and
`BANK8` form so that they could be added later, but nothing in Basie 1.0 is
shaped for them.

### 9.3 Precompiled libraries

A library compiled once and linked into many programs needs its own ordinal
range and an interface file that the compiler reads, giving names, signatures
and ordinals. Names would return, but only in the compiler; the linker would
still work by number. It is not part of 1.0.

### 9.4 Overlays

Because the linker knows the whole call graph, it could split a program larger
than memory into a resident root and overlays loaded on demand. Nothing in the
format prevents it. It is not part of 1.0.

## 10. Open questions

These are collected from the specifications:

1. **Reference density and blob counts** of real compiled code, which size the
   directory stream, the linker's tables and the build time.
2. **Linker table capacity** for the largest programs, and how to shrink the
   tables if needed ([linker](linker.md), Section 12).
3. **The activation-capacity threshold** above which a routine checks its
   stack in its prologue ([CP/M target](cpm-target.md), Section 4.1).
4. **Routine, literal and deferred-reference buffer sizes,** fixed by
   measurement.
5. **Stack reserve for recursive programs,** beyond the default reserve and the
   runtime's activation-capacity trap.
6. **Source parts named in source** rather than on the command line.
7. **Resident linker or overlay** ([toolchain](toolchain.md), Section 7.3).
8. **Symbol file format** for `SID` and `ZSID`, to be verified.

## 11. History

- **Revision 1** proposed blobs, ordinals and a separate layout tool.
- **Revision 2** incorporated a CP/M and Z80 toolchain review, which corrected
  startup destroying the command tail, a slow fallback with a backwards
  termination argument, branch shrinking that broke backward branches, a
  reference encoding with no spare bits, linker-assigned banks, underestimated
  file sizes and the claim of atomic output replacement.
- **Revision 3** split the design into this overview and four specifications,
  named the layout tool the linker, made it a phase of the single `BASIE`
  executable, and added aliases, pseudo-objects as regions, the blob library
  file with its profile block, the line table and the trap lookup mode.
- **Revision 4** incorporated an adversarial review of the four
  specifications ([review](reviews/2026-10-03-linker-spec-review.md)). Its
  main corrections: an `OPTIONS` pseudo-object so prebuilt startup code can see
  link options; stamp deduplication that no longer drops the first blob's
  edges; Phase C reading the directories to recover placement order; literals
  inside their routine's blob; a `LIMITS` record for facts known only at the
  end of input; a range rule relative to the target, which accepts end pointers
  and RAM below ROM; helpers that jump to the trap reporter with the stack
  balanced so traps report the call site; a line table written during Phase D
  without sorting; a wider reference delta; pseudo-objects moved to the top of
  the ordinal space and the library range widened; a compilation stamp binding
  the streams; the image written on the output drive; and deleting files before
  creating them.
- **Revision 5** incorporated a second adversarial review
  ([review 2](reviews/2026-10-03-linker-spec-review-2.md)): part records first
  in the line stream; aliases' effective sizes for range checks; the reporter
  contract extended to forbid tail calls to helpers and to cover nested helpers
  and restart-vector helpers; alignment codes stored in the linker's tables, with
  one placement read per alignment class and the `startup` blob first in the
  library; an exact definition of `COPY`; aliases setting the defined bit; the
  edge list layout; a compilation stamp derived from the previous directory; a
  `JP` for long inline literals; the stack reserve as a lower bound guarded by
  an activation-capacity check; and a per-routine reference capacity.
- **Revision 5 addendum (2026-10-04):** the linker became a separate program,
  `BLINK.COM`, chained from `BASIE.COM`, to keep the compiler within its budget (26K target, 28K limit)
  budget (design decision D9).
