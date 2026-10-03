# Build pipeline

- Status: design overview, revision 3
- Date: 2026-10-03
- Specifications: [object format](object-format.md), [linker](linker.md),
  [toolchain](toolchain.md), [CP/M target](cpm-target.md)
- Research: [linker prior art](research/linker-prior-art.md)
- Replaces: the final-address model of the Nucleus Object Stream Format 0.1
  (`../nucleus/docs/nucleus-object-format.md`)

This document explains why Baton builds programs the way it does and how the
pieces fit together. The four specifications above define the details; where
this overview and a specification disagree, the specification governs.

## 1. Summary

Building a Baton program is one command, `BATON MAIN`, which runs two phases of
one executable:

1. **Compile.** The compiler reads the source once and generates Z80 machine
   code. It writes the code as **blobs**: one per routine, constant or
   variable, each a run of bytes plus a list of the places that hold
   addresses. It never chooses a final address.
2. **Link.** The linker reads the blobs and a prebuilt **blob library** holding
   the runtime for the target. It keeps only the blobs reachable from the
   program's entry, assigns their addresses, fills in every address and writes
   the program image.

No assembler takes part. The compiler generates machine code; the linker
writes the binary.

The linker exists for one reason: **tree shaking**. The output contains only the
routines, constants, variables and runtime helpers the program can reach.

## 2. Why a linker

Nucleus emitted every byte at its final address as soon as it generated it.
Forward references became patch records; backward references were written
straight into the image.

Under that model a single-pass compiler cannot drop unused code. A routine's
last possible caller may be the final line of the source, so the routine's
liveness is known only at the end of input. By then it occupies addresses that
later code has been built against. Removing it would shift everything after
it, and nothing records which bytes are addresses.

Any design that removes unused code must therefore:

1. delay the choice of addresses until liveness is known;
2. place code, then move it, which needs a record of every address; or
3. read the source twice.

Reading the source twice breaks Baton's single-pass rule. Options 1 and 2 both
need a record of every address in the code, which is what a relocating linker
works from. Baton takes option 1 and builds a small linker designed for the
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
 MAIN.BTN  UTIL.BTN                     CPM22.BRL
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
| The executable, command line, file lifecycle, memory plan | [Toolchain](toolchain.md) |
| Profiles, memory map, startup, exit, traps under CP/M | [CP/M target](cpm-target.md) |

## 5. Prior art

The [prior-art survey](research/linker-prior-art.md) examined period CP/M
linkers and modern ones. What Baton borrows, and what it avoids:

*This section summarises the survey and is completed from it.*

## 6. The compiler's side

The specifications define what the compiler must write. This section records
how the compiler changes from Nucleus to write it.

### 6.1 What the compiler stops doing

- It no longer knows any final address.
- It no longer keeps a program-wide table of unresolved call sites.
- It no longer emits patch records or a placed image.

### 6.2 What the compiler starts doing

- It assigns an ordinal to each blob as it meets the declaration, including at
  a forward declaration.
- It emits every absolute address operand as zero placeholder bytes, with an
  entry in the routine's pending reference list.
- At the end of each routine or declaration, it writes the blob's record and
  references to the directory stream, sorted by offset. The bytes have already
  gone to the byte stream, unless the routine was buffered for branch shrinking.
- It writes the `ENTRY` record naming `main`.

Its memory cost for references is one routine's pending list at a time, about
5 bytes per reference, instead of Nucleus's program-wide table of unresolved
sites.

### 6.3 Shorter forward branches

A streaming compiler must emit a forward branch before it knows the distance,
so Nucleus uses a 3-byte `JP` where a 2-byte `JR` would often do. With a bounded
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
branch and 300 to 500 bytes of compiler code. `JR` is a byte shorter than `JP`;
taken, it costs 12 T-states against 10, and not taken, 7 against 10.

### 6.4 Shared tails and fall-through

Blobs may not fall through into one another or share code by adjacency. A tail
the Nucleus backend shared between routines becomes an explicit `JP` to a
shared blob. The loss is small: a cross-routine tail was already a `JP` unless
the two routines happened to be adjacent. Hand-written runtime helpers that fall
into one another are either one blob with aliases for their extra entry points,
or separate blobs joined by `JP`, whichever lets programs carry less.

### 6.5 Unused routines in the user's source

The linker removes them. The compiler may still warn about a routine that is
never referenced, since it knows at the end of input, but the warning is
advisory.

## 7. Comparison with Nucleus

| | Nucleus NOBJ 0.1 | Baton |
| --- | --- | --- |
| Addresses chosen by | compiler, at emission | linker, after liveness is known |
| Unused code removed | no | yes: routines, data, constants, runtime helpers |
| Cross-routine references | pending table in the compiler, then patches | references in each blob's record |
| Compiler memory for fixups | one entry per unresolved site in the program | one routine's references at a time |
| Forward branches | always `JP` | `JR` where it fits, for buffered routines |
| Runtime | linked whole for the target | blob library; unused helpers removed |
| Output | image and patch spools, merged by a materializer | written in address order by the linker |
| Executables | compiler, plus a materializer | one executable with compile and link phases |

What carries over from Nucleus: append-only output files, a CRC that makes
partial output unusable, a publication sequence that never destroys the
previous good output, and the separation between compiling a program and the
target it runs on.

## 8. Costs

- **More disk traffic per build.** The directory stream may be as large as the
  program itself, and the linker reads it at least twice. On the 720K-and-larger
  disks Baton assumes, space is not a concern, but transfer time is. The
  reference density of real compiled code must be measured to size this.
- **Placeholders hide addresses from the compiler.** It cannot fold or compare
  addresses. Baton source cannot observe addresses, so no feature is lost, but
  the backend cannot exploit a particular placement.
- **Granularity is the blob.** Code inside a live routine that is never executed
  is not removed; that is the compiler's job, through constant folding.
- **No incremental builds.** Any edit can renumber ordinals, so a program is
  always compiled and linked whole.
- **Libraries are compiled every build.** Precompiled program libraries would
  need names in the compiler (Section 9.3).

## 9. Other targets and later work

### 9.1 ROM targets

A ROM image stores initialised data in ROM and runs it from RAM. The linker
places `DATA` at RAM addresses and stores its initial bytes in a `COPY` section
in ROM; startup copies them before calling `main`. The CP/M re-runnable option
uses the same mechanism.

### 9.2 Banked targets

Nucleus assigns banks by source part, and its compiler enforces the cross-bank
rules. If the linker chose banks, nothing would enforce them: a constant placed
in one bank and read from another would silently read the wrong memory, and a
tail call or routine value could cross banks with no switch. Baton therefore
keeps compiler-assigned banks: the `BANK` control record carries each blob's
bank, and the linker places blobs within their banks. Banked linking is
reserved in the format but not part of Baton 1.0.

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
   tables if needed ([linker](linker.md), Section 11).
3. **Line table memory** when a program has many statements.
4. **String literal deduplication,** by a compiler-side cache of recent
   literals.
5. **Routine buffer size** for branch shrinking, and the limit on references
   per routine.
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
  named the layout tool the linker, made it a phase of the single `BATON`
  executable, and added aliases, pseudo-objects as regions, the blob library
  file with its profile block, the line table and the trap lookup mode.
