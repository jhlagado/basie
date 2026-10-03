# Baton linker 1.0

- Status: draft specification, not yet reviewed
- Date: 2026-10-03
- Related: [object format](object-format.md), [toolchain](toolchain.md),
  [CP/M target](cpm-target.md), [build pipeline](build-pipeline.md)

## 1. Scope and purpose

The Baton linker combines one program object with one blob library and writes
one program image. Its purpose is **tree shaking**: the image contains exactly
the blobs reachable from the program's roots, and nothing else.

It is a relocating linker with deliberate limits:

- **One program per run.** It does not combine separately compiled program
  objects. A program's source, including any source libraries, is compiled as a
  whole.
- **Ordinals, not names.** It never compares names. Names appear only in
  optional reports.
- **No library search.** The blob library is read whole; its unused blobs are
  removed by the same reachability rule as the program's.
- **Forward-only reading.** It reads every input from start to end, skipping
  forward with random reads where the platform allows, and never returns to an
  earlier position in a file, except that it reads the program directory twice
  (Section 7).
- **Output in address order.** It writes each output file once, sequentially.

The linker runs as the second phase of the Baton executable, or alone in
link-only mode; see the [toolchain](toolchain.md).

## 2. Memory

### 2.1 Tables

The linker keeps three tables in memory, sized from the inputs:

| Table | Entry | Indexed by | Contents |
| --- | --- | --- | --- |
| Object table | 8 bytes | ordinal | Kind and flags (1), size (2), address (2), first-edge index (2), stamp (1) |
| Edge array | 2 bytes | position | Target ordinals, grouped by source blob, duplicates removed |
| Mark stack | 2 bytes | position | Ordinals waiting to be scanned during marking |

For an alias, the object-table entry holds the base ordinal in the
first-edge field and the offset in the size field, with a kind value marking
it as an alias.

The object table covers ordinals `$0000` to the highest ordinal defined in
either input. Its size is therefore fixed by the compiler's ordinal count, not
by how many blobs are live. The mark stack never holds more entries than there
are blobs.

### 2.2 Capacity

The tables use all memory left after the linker's code and its I/O buffers
(Section 7.5). The [toolchain](toolchain.md) document places them over the
compiler's code and workspace, which are dead once compilation ends.

| Program | Ordinals | Distinct edges | Tables |
| --- | ---: | ---: | ---: |
| Typical, 20K output | 800 | 4,000 | 6K + 8K = about 15K |
| Large, 40K output | 2,000 | 9,000 | 16K + 18K = about 38K |
| Largest, 56K output | 3,000 | 14,000 | 24K + 28K = about 58K |

These figures are estimates and must be replaced by measurements. On a CP/M
system with a 58K transient program area, the [toolchain](toolchain.md)
leaves about 47K to 49K for tables after the shared code, the linker's code,
its buffers and the stack. The largest programs may exceed it.

If the tables don't fit, the linker stops with diagnostic `L-CAP-TABLES`,
reporting the ordinal count, the edge count reached and the memory needed. It
does not fall back to a slower method; a rescanning fallback would make the
cases that need it the slowest of all.

## 3. Roots

The linker marks these objects live before following any reference:

1. the library's `startup` blob;
2. every blob whose header has the root flag, in either input; and
3. the program's entry routine, but only through `MAIN`: the `startup` blob
   references `MAIN`, and a reference to `MAIN` marks the routine named by the
   `ENTRY` record.

A program directory without exactly one `ENTRY` record is rejected with
`L-ENTRY`.

## 4. Phase A: read the directories

The linker reads the library's directory section, then the program directory,
each from start to end.

For each input it:

1. checks the header: magic, major and minor version, and, after both headers
   are read, the compatibility rule of the object format (Section 10);
2. for each blob record, fills the blob's object-table entry, and appends the
   distinct targets of its references to the edge array;
3. for each `ALIAS` record, fills the alias's entry;
4. for each `ENTRY` record, records the entry ordinal; and
5. checks the trailer: the marker, the blob count, the CRC and, later, the byte
   stream length.

**Deduplication.** Before appending a target to the edge array, the linker
compares the target's stamp with the current blob's sequence number modulo 256.
If they are equal, the target has already been appended for this blob and is
skipped. Otherwise the linker appends it and sets the stamp. When the sequence
number wraps to 0, the linker clears every stamp, once per 256 blobs.

**Edges to pseudo-objects** are not stored, except that an edge to `MAIN` is
stored as an edge to the entry routine once the `ENTRY` record has been read.
Because `ENTRY` may follow the blobs that reference `MAIN`, the linker stores
`MAIN` edges as `MAIN` and resolves them during marking.

**Checks during Phase A:**

| Condition | Diagnostic |
| --- | --- |
| Bad magic, unknown major version or higher minor version | `L-FORMAT` |
| Runtime identity, profile identity or helper-table version incompatible | `L-COMPAT` |
| Ordinal outside its owner's range, or defined twice | `L-ORDINAL` |
| Reserved kind, form or subtype | `L-RESERVED` |
| Blob of size 0; `code` blob with nonzero alignment | `L-BLOB` |
| Reference offsets not strictly increasing, overlapping, or outside the blob | `L-REFERENCE` |
| `SIZE16` naming an alias; reference to `$0000` or a reserved pseudo-object | `L-REFERENCE` |
| Alias whose base is an alias, is undefined, or whose offset is outside the base | `L-ALIAS` |
| Missing, bad or mismatched trailer or CRC | `L-TRUNCATED` |
| Not exactly one `startup` blob in the library | `L-STARTUP` |
| A `BANK` record under a flat profile | `L-RESERVED` |
| Tables full | `L-CAP-TABLES` |

A reference to an ordinal that is never defined is detected at the end of
Phase A, once every definition has been read: `L-UNDEFINED`. This is the
signature of a version mismatch or a compiler fault, because the compiler
rejects an incomplete forward declaration.

## 5. Phase B: mark

Marking is a depth-first walk with the mark stack:

1. Push every root, and the entry routine.
2. While the stack is not empty, pop an ordinal. For each edge of that blob:
   resolve an alias to its base and `MAIN` to the entry routine; if the target
   is a blob not yet marked, mark it and push it.

Each blob is pushed at most once, so marking takes time linear in the number of
blobs plus edges. The result is the **live set**.

## 6. Phase C: place

### 6.1 Sections

The linker places live blobs into these sections, in this order:

| Section | Holds | Stored in the image |
| --- | --- | --- |
| `START` | the `startup` blob | yes |
| `TEXT` | live `code` and `rodata` blobs | yes |
| `DATA` | live `data` blobs | yes |
| `COPY` | a copy of `DATA`, when the profile or options need one (Section 6.4) | yes |
| `BSS` | live `bss` blobs | no |

On a CP/M target without the re-runnable option, `data` blobs are placed in
`TEXT` alongside code and read-only data, in directory order, so the stored
image is written in a single pass, and the `DATA` and `COPY` sections are
empty. With the re-runnable option, `DATA` is a separate section so that it can
be copied as one block. On CP/M, all stored sections follow one another from
the image base, and `BSS` follows the stored image. On a ROM target, `START`, `TEXT` and `COPY` go into
ROM from the image base, and `DATA` and `BSS` go into RAM from the RAM base;
`DATA` then holds no stored bytes of its own (Section 6.4).

### 6.2 Order within a section

Within a section, blobs are placed:

1. blobs with page alignment first, then those with 64-byte alignment, and so
   on down to 2-byte alignment, so that padding is paid as few times as
   possible;
2. within each alignment class, library blobs before program blobs; and
3. within that, in directory order.

The order is a pure function of the inputs, so the same inputs always produce
the same image, byte for byte.

Padding inserted before an aligned blob is filled with zeros in stored
sections. The map reports it.

### 6.3 Addresses

The `START` section begins at the profile's image base. Each section begins
where the previous one ends, except that a RAM section on a ROM target begins at
the RAM base. Each blob's address is the next address in its section rounded up
to its alignment. Aliases take their base's address plus their offset.

Then the linker defines the pseudo-objects (object format, Section 3.4).

### 6.4 Initialised data

- **CP/M, default.** `data` blobs are stored in place within `TEXT`. No copy
  exists, and the `DATA` and `DATACOPY` pseudo-objects have size 0.
- **CP/M, re-runnable option.** The linker adds a `COPY` section after `DATA`
  holding a second copy of the initial data. Startup copies `COPY` over `DATA`
  before calling `main`. See the [CP/M target](cpm-target.md).
- **ROM targets.** `DATA` has RAM addresses; its initial bytes are stored only
  in `COPY`, in ROM. Startup copies them into RAM.

### 6.5 Fit checks

| Check | Result if it fails |
| --- | --- |
| Stored image ends at or below the profile's image limit | `L-FIT-IMAGE`, error |
| `BSS` and stack reserve fit below 65,536 | `L-FIT-MEMORY`, error |
| `REQUIRED` at or below the profile's nominal top | `L-FIT-NOMINAL`, warning |
| ROM targets: `DATA` and `BSS` fit between RAM base and RAM limit | `L-FIT-RAM`, error |

The warning is not an error because the real top of memory varies from machine
to machine. The startup code makes the final check on the machine where the
program runs.

## 7. Phase D: write

### 7.1 Order

The linker writes each stored section in address order. For each section it
reads the library's directory and byte sections and the program's directory and
byte stream forward, in step, emitting the section's live blobs in placement
order.

Placement order puts aligned blobs first (Section 6.2), which is not
directory order. The linker therefore makes one forward pass per alignment
class that has live blobs in the section, plus one for unaligned blobs. A
typical CP/M program has no aligned blobs and no separate `DATA` section, so
its whole image is written in one pass. A separate `DATA` or `COPY` section
adds one pass each.

Each pass reads the directories again from the start. The program directory is
therefore read in Phase A and once more for every pass in Phase D. This is the
only exception to forward-only reading, and it is a fresh read from the start
of the file, not a seek backwards within a pass.

### 7.2 Emitting a blob

For each blob record read during a pass:

- **Not in the pass, or dead:** skip its stored bytes in the byte stream. Where
  the platform has random reads, skip whole 128-byte records without reading
  them.
- **In the pass and live:** copy its stored bytes to the output. When the copy
  reaches a reference's offset, compute the value (object format, Section 5.1)
  and write it in place of the placeholder bytes.

Padding for alignment is written before the blob as zeros.

### 7.3 Value checks

| Condition | Diagnostic |
| --- | --- |
| `ABS16`, `LO8` or `HI8` value outside the target's memory: below the image base, or at or above 65,536 before the modulo, unless the addend is negative and the result is inside the target's memory | `L-RANGE` |
| Byte stream shorter or longer than its trailer says | `L-TRUNCATED` |
| Nonzero placeholder bytes, when verification is requested | `L-PLACEHOLDER` |

A reference from a live blob to a dead blob cannot occur, because marking
follows every reference.

### 7.4 Output kinds

| Kind | Contents |
| --- | --- |
| `.COM` | The stored image from the image base, as a flat binary. Requires image base `$0100`. The final 128-byte record is padded with zeros. |
| `.BIN` | The stored image from the image base, as a flat binary. On CP/M, the final record is padded with zeros. |
| `.HEX` | Intel HEX: data records (type `00`) of at most 16 bytes each with absolute addresses, then an end-of-file record (type `01`). Each line ends with CR LF. On CP/M, the file is padded with `$1A`. |

The profile's output-kinds field limits which kinds may be written.

### 7.5 Files and buffers

During Phase D the linker has at most five files open: the library (opened
twice, once for its directory section and once for its byte section), the
program directory, the program byte stream and the output. CP/M permits the
same file to be opened with two file control blocks for reading.

Each open file needs a 36-byte file control block and a 128-byte record
buffer, about 820 bytes in all. Blobs and references cross record boundaries,
so the linker keeps a byte cursor into each buffer and refills it as it goes.
An `ABS16` at the last byte of a record spans two records.

## 8. Phase E: reports and line table

After the image is written, the linker writes the reports requested on the
command line (see the [toolchain](toolchain.md)).

### 8.1 Map

A text file with these sections, in order:

1. **Summary:** input file names, runtime and profile identities, output kind,
   image base and end, `BSS` start and size, stack reserve, `REQUIRED`, the
   profile's image limit and nominal top, and the margin to each.
2. **Live blobs,** one per line in address order: address, size, kind,
   alignment padding paid, ordinal, and name if a name stream is available.
3. **Removed blobs,** one per line in ordinal order: ordinal, kind, size and
   name; then the total bytes removed from the program and from the library.

Addresses and ordinals are written in hexadecimal, sizes in decimal.

### 8.2 Symbol file

A `.SYM` file for Digital Research's `SID` and `ZSID` debuggers: one line per
live blob and alias with a name, giving the address as four hexadecimal digits,
a space and the name. The exact format these debuggers accept, including the
name length limit and separator, must be verified before implementation.

### 8.3 Line table

When the program directory's flags say a line stream exists, the linker reads
it, translates each entry's (ordinal, offset) to an address, discards entries
for dead blobs, sorts the rest by address and writes the line table (object
format, Section 11).

Sorting needs memory proportional to the number of live statements: 5 bytes
each. The object table is no longer needed at this point except for addresses
and live flags, so the linker reuses the edge array's space. If the entries do
not fit, the linker writes the line table in several sorted runs and merges
them, or reports `L-CAP-LINES` and skips the line table without failing the
link. Which of these 1.0 does is an open question (Section 11).

## 9. Diagnostics

Every diagnostic is reported with its code, a message, and where useful the
ordinal and name concerned. An error stops the link; the previous output is
left in place (see the [toolchain](toolchain.md)).

| Code | Severity | Meaning |
| --- | --- | --- |
| `L-FORMAT` | error | Bad magic or an unsupported version |
| `L-COMPAT` | error | Program and library are not compatible |
| `L-ORDINAL` | error | Ordinal out of range or defined twice |
| `L-RESERVED` | error | A reserved kind, form, subtype or field value |
| `L-BLOB` | error | A malformed blob record |
| `L-REFERENCE` | error | A malformed reference |
| `L-ALIAS` | error | A malformed alias |
| `L-ENTRY` | error | Not exactly one `ENTRY` record |
| `L-STARTUP` | error | Not exactly one `startup` blob in the library |
| `L-UNDEFINED` | error | A reference to an ordinal never defined |
| `L-TRUNCATED` | error | A missing trailer, bad CRC or wrong byte-stream length |
| `L-CAP-TABLES` | error | The tables don't fit in memory |
| `L-FIT-IMAGE` | error | The stored image exceeds the profile's image limit |
| `L-FIT-MEMORY` | error | The image, `BSS` and stack exceed the address space |
| `L-FIT-RAM` | error | ROM targets: `DATA` and `BSS` exceed RAM |
| `L-FIT-NOMINAL` | warning | The program may not fit a typical machine |
| `L-RANGE` | error | A computed address is outside the target's memory |
| `L-PLACEHOLDER` | error | Nonzero placeholder bytes, under verification |
| `L-CAP-LINES` | warning | The line table could not be written |
| `L-IO` | error | A disk read or write failed, or the disk or directory is full |

## 10. Conformance

An implementation conforms when it produces, for every valid input, exactly the
image the rules above define, and rejects every invalid input with the
diagnostic named. The conformance suite must include at least:

- a program with no dead blobs, whose image equals the unlinked concatenation;
- programs where dead blobs occur at the start, the middle and the end of each
  section, and in the library;
- a chain of references through a forward-declared routine;
- aliases, including a reference to an alias in a blob otherwise dead;
- every reference form at every alignment, including an `ABS16` spanning a
  128-byte record boundary in the input and in the output;
- aligned blobs of every class, checking padding and order;
- self-references and negative addends;
- each diagnostic in Section 9, from a minimal file that triggers it;
- the largest program the tables allow, and one ordinal beyond it; and
- re-linking the same inputs and comparing the outputs byte for byte.

## 11. Open questions

1. **Line table memory.** Sorted runs and a merge, or skip the line table with
   a warning when it doesn't fit?
2. **Table sizes.** If measurements show programs reaching `L-CAP-TABLES`, the
   edge array could store 1-byte relative targets, or the compiler could write
   each blob's edges deduplicated so the linker stores them as they come.
3. **Symbol file format** for `SID` and `ZSID`, to be verified.
4. **Placeholder verification** on by default, or only on request?
