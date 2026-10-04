# Baton linker 1.0

- Status: draft specification, revision 4
- Date: 2026-10-03
- Related: [object format](object-format.md), [toolchain](toolchain.md),
  [CP/M target](cpm-target.md), [build pipeline](build-pipeline.md),
  reviews [1](reviews/2026-10-03-linker-spec-review.md) and
  [2](reviews/2026-10-03-linker-spec-review-2.md)

## 1. Scope and purpose

The Baton linker combines one program object with one blob library and writes
one program image. Its purpose is **tree shaking**: the image contains exactly
the blobs reachable from the roots, and nothing else.

It is a relocating linker with deliberate limits:

- **One program per run.** A program's source, including any source libraries,
  is compiled as a whole.
- **Ordinals, not names.** It never compares names. Names appear only in
  reports and diagnostics.
- **No library search.** The blob library is read whole; its unused blobs are
  removed by the same rule as the program's.
- **Forward reading.** Within a pass it reads every file forward, skipping
  forward where the platform allows. Several phases read the same file again
  from its start; Section 10 counts them.
- **Output in address order.** It writes each output file once, sequentially.

The linker is a separate program, `BLINK.COM`, which `BATON` runs automatically
after a successful compilation, or which can be run directly; see the
[toolchain](toolchain.md).

## 2. Memory

### 2.1 Tables

| Table | Entry | Indexed by | Grows |
| --- | --- | --- | --- |
| Library table | 8 bytes | library ordinal, `$0000`–highest | fixed; its size is in the library header |
| Program table | 8 bytes | program ordinal minus `$0400` | upwards, after the library table |
| Pseudo table | 8 bytes | pseudo ordinal minus `$FFE0` | fixed, 8 entries |
| Edge lists | 2 bytes per edge, plus a 2-byte terminator per blob with edges | — | downwards from the top of free memory |
| Mark stack | 2 bytes | — | in the gap between the tables and the edge lists, after Phase A |

The library table's size is known from the library header before any record is
read. The program table grows as Phase A meets program ordinals: as blob
definitions, reference targets, `ALIAS` ordinals and bases, and the `ENTRY`
ordinal. A newly covered entry is zeroed. The edge lists grow down from the top.
If the program table and the edge lists meet, the linker stops with
`L-CAP-TABLES`. At the end of Phase A the gap between them must hold 2 bytes per
blob record for the mark stack, or the linker stops with `L-CAP-TABLES`.

**Edge list layout.** For a blob with references, Phase A writes a terminator
(`$0000`) at the next free position below the edge lists, then each distinct
target below it, and sets the blob's edges field to the address of the last
target written, the lowest. Marking walks upwards from that address to the
terminator. A blob with no references has edges field 0 and no terminator.

**Table entry** (8 bytes):

| Field | Size | Meaning |
| --- | --- | --- |
| flags | 1 | Bits 0–2: kind. Bit 3: defined. Bit 4: referenced. Bit 5: live. Bit 6: alias. Bit 7: root |
| size | 2 | Blob size. For an alias, its offset until Phase C, then its effective size: the base's size minus the offset |
| address | 2 | Assigned in Phase C. For an alias before Phase C, its base ordinal |
| edges | 2 | Address of the blob's lowest edge (see below), or 0 |
| layout | 1 | Bits 0–2: alignment code. Bits 3–7: reserved for the bank, zero in 1.0 |

Pseudo-object entries hold the address and size the linker computes.

### 2.2 Capacity

**[estimate]** At 8 bytes per ordinal, up to 4 bytes per blob for the edge
terminator and the mark stack, and 2 bytes per distinct edge:

| Program | Library ordinals | Program ordinals | Distinct edges | Memory |
| --- | ---: | ---: | ---: | ---: |
| Typical, 20K output | 200 | 800 | 4,000 | 1.6K + 6.4K + 4.0K + 8.0K = 20K |
| Large, 40K output | 200 | 2,000 | 9,000 | 1.6K + 16K + 8.8K + 18K = 44K |
| Largest, 56K output | 200 | 3,000 | 14,000 | 1.6K + 24K + 12.8K + 28K = 66K |

With literals inside their routines, a program has roughly one blob per
routine, top-level variable and top-level constant.

The [toolchain](toolchain.md) leaves about 48K for these tables on a CP/M 2.2
system with 62K of memory. Typical and large programs fit; the largest
programs the address space allows do not, and fail with `L-CAP-TABLES`.
The figures are estimates to be replaced by measurement (Section 12).

## 3. Roots

The linker marks these live before following any reference:

1. the library's `startup` blob; and
2. every blob whose header has the root flag, in either input.

The program's entry routine is not a root. The `startup` blob references
`MAIN`, and marking resolves `MAIN` to the routine named by the program's
`ENTRY` record. A library whose `startup` blob does not reference `MAIN` is
rejected with `L-STARTUP`.

## 4. Phase A: read the directories

### 4.1 Reading

The linker reads the library header, profile block, key table and directory
section, then the program directory and the headers of the byte, line and name
streams. Before reading any blob record it checks:

- every magic and version (`L-FORMAT`);
- the compatibility rule of the object format, Section 10 (`L-COMPAT`);
- that all program streams carry the same nonzero compilation stamp
  (`L-STAMP`); and
- that the options and output kind requested are supported by the profile
  (`L-OPTION`, `L-OUTPUT`).

Then, for each record in each directory:

- **Blob record:** check it; fill its table entry, including its alignment
  code, and set the defined bit; append the distinct targets of its references
  to the edge lists (Section 4.2); set the referenced bit of each target.
- **`ALIAS`:** check it; fill the alias's entry with the alias bit, the base
  ordinal and the offset, and set the defined bit.

Filling an entry never clears its referenced bit, which an earlier referrer may
have set. Defining an ordinal that is already defined, whether as a blob or an
alias, is `L-ORDINAL`.
- **`ENTRY`:** record the entry ordinal.
- **`LIMITS`:** record the stack reserve and flags.

Finally it checks each trailer and, once both directories are read, every
cross-record rule (Section 4.3).

### 4.2 Deduplication

Before appending a target, the linker scans the targets already appended for
the current blob, which lie between the current position and the blob's
terminator. If the target is among them it is skipped. Most blobs have a few
dozen distinct targets, so the scan is short; a very large routine with
hundreds of distinct targets costs a few hundred thousand comparisons, under a
second at 4 MHz. Revision 2's per-entry stamp is gone, which frees the entry's
last byte for the alignment code and a future bank number.

Every reference target is appended as its own ordinal, including aliases and
pseudo-objects. Marking resolves them (Section 5).

### 4.3 Checks

| Condition | Diagnostic |
| --- | --- |
| Bad magic, unknown major version or higher minor version | `L-FORMAT` |
| Runtime identity, profile identity, helper-table version or key incompatible | `L-COMPAT` |
| Program streams with different or zero compilation stamps | `L-STAMP` |
| An option, or the output kind, not supported by the profile | `L-OPTION`, `L-OUTPUT` |
| Ordinal outside its owner's range, or defined twice | `L-ORDINAL` |
| A reserved kind, form, subtype or field value; a form byte of 0; a `BANK` record or `BANK8` reference under a 1.0 profile | `L-RESERVED` |
| A blob of size 0; a `code` or `startup` blob with nonzero alignment; a `bss` blob with references; a `startup` blob in the program; a reference count escape below 255 | `L-BLOB` |
| Reference offsets not strictly increasing, overlapping, or outside the blob | `L-REFERENCE` |
| A `SIZE16` naming an alias; a reference to `$0000` or a reserved pseudo-object; a library reference to a program ordinal or above the library's highest ordinal | `L-REFERENCE` |
| An alias outside its owner's range, whose base is an alias, is undefined, is in the other directory, or whose offset is not below the base's size | `L-ALIAS` |
| Not exactly one `ENTRY` record, or an entry ordinal that is not a `code` blob in the program | `L-ENTRY` |
| Not exactly one `LIMITS` record, or one before the last blob record | `L-LIMITS` |
| Not exactly one `startup` blob in the library, a `startup` blob that is not the library's first record, or one without a reference to `MAIN` | `L-STARTUP` |
| A referenced ordinal that is never defined | `L-UNDEFINED` |
| Missing or bad trailer, CRC, count or highest ordinal; library header and trailer disagree | `L-TRUNCATED` |
| The tables don't fit | `L-CAP-TABLES` |

`L-UNDEFINED` is found by scanning both tables at the end of Phase A for entries
with the referenced bit set and the defined bit clear. It signals a version
mismatch or a compiler fault, since the compiler rejects an incomplete forward
declaration.

## 5. Phase B: mark

1. Push every root.
2. While the stack is not empty, pop an ordinal and walk its edge list upwards
   from its edges field to the terminator. For each target: resolve `MAIN` to
   the entry routine and an alias to its base; ignore other pseudo-objects; if
   the result is a blob without the live bit, set the bit, record its alignment
   class and section as present, and push it.

Each blob is pushed at most once, so marking takes time linear in blobs plus
edges. The live bits form the **live set**.

References from `data` and `rodata` blobs count like any other. A routine whose
address is stored in a live table or variable therefore stays live, which is
what future routine values need.

## 6. Phase C: place

### 6.1 Sections

| Section | Holds | Stored in the image |
| --- | --- | --- |
| `START` | the `startup` blob | yes |
| `TEXT` | live `code` and `rodata` blobs, and live `data` blobs when `DATA` is not separate | yes |
| `DATA` | live `data` blobs, when separate | on CP/M, yes; on ROM, no |
| `COPY` | the initial bytes of `DATA`, when separate | yes |
| `BSS` | live `bss` blobs | no |

**When `DATA` is separate.** On a CP/M target without the re-runnable option,
`data` blobs go in `TEXT`, `DATA` and `COPY` are empty, and the image is written
in as few passes as possible. With the re-runnable option, or on a ROM target,
`DATA` is separate so that it can be copied as one block.

**The file table.** If any live blob references `FILES` or `FILECOUNT`, the
linker appends the file table to `BSS`: `n` entries of the profile's file-entry
size, where `n` is the `F=n` option (default 4, at most 255). Otherwise it
allocates nothing ([object format](object-format.md), Section 3.6).

**Where sections go.**

- **CP/M:** `START`, `TEXT`, `DATA` and `COPY` follow one another from the image
  base, and `BSS` follows the stored image.
- **ROM:** `START`, `TEXT` and `COPY` go into ROM from the image base. `DATA`
  and `BSS` go into RAM from the RAM base; `DATA` occupies RAM addresses but has
  no stored bytes there.

### 6.2 Order

Within each section, live blobs are ordered:

1. by alignment class, from 256 bytes down to 2 bytes, then unaligned blobs;
2. within a class, library blobs before program blobs; and
3. within that, in directory order.

`START` holds only the `startup` blob. The order is a pure function of the
inputs, so the same inputs always produce the same image, byte for byte.

Each blob is placed at the next offset in its section rounded up to its
alignment. Padding is zeros in stored sections. Each class pays padding at most
once at its start, plus whatever its own blobs' sizes cause between them.

### 6.3 Assigning addresses

The tables are indexed by ordinal, not directory position, so Phase C recovers
directory order by reading the directories. It makes one **placement read** for
each alignment class that has live blobs in any section, from the largest class
down, ending with one read for unaligned blobs. Phase B records which classes
are live as it marks, from the table's alignment codes, so no extra read is
needed to find them.

In each placement read, the linker reads the library directory and then the
program directory, and gives each live blob of the current class an offset in
its section, keeping one cursor per section (`TEXT`, `DATA`, `BSS`). Because
the reads run from the largest class down, each section ends up ordered as
Section 6.2 requires.

Each section's base is rounded up to the largest alignment of any blob in it,
so that offsets aligned within the section are aligned absolutely.

After the last read, the linker knows each section's size. It computes the
section bases (`START` at the image base, followed by the others as Section 6.1
describes), then walks the tables by ordinal and adds each live blob's section
base to its offset. That walk reads no file. Each alias then takes its base's
address plus its offset, and its size field becomes the base's size minus the
offset, for range checks in Phase D. Finally the linker computes the
pseudo-objects (object format, Section 3.4) from the section boundaries, the
stack reserve and the options.

**Stack reserve.** The stack reserve used for `REQUIRED` is the larger of the
`LIMITS` value and the `STACK=` option, so the option works in link-only mode
too.

A typical program has no aligned blobs, so Phase C makes one read of each
directory.

### 6.4 Fit checks

| Check | Result if it fails |
| --- | --- |
| Stored image ends at or below the profile's image limit, and no blob starts at `$FFFF` | `L-FIT-IMAGE`, error |
| `BSS` plus the stack reserve ends at or below 65,536 | `L-FIT-MEMORY`, error |
| `REQUIRED` at or below the profile's nominal top; with keep-CCP, at or below the image limit (the CCP base) | `L-FIT-NOMINAL`, warning |
| ROM: `DATA` and `BSS` lie between the RAM base and the RAM limit | `L-FIT-RAM`, error |

`L-FIT-NOMINAL` is a warning, not an error, on every profile, because the real
top of memory varies from machine to machine: a CP/M 3 system with a larger
transient program area than the profile's nominal top runs the program, and
startup makes the final check on the machine where the program runs. On CP/M 2.2
without keep-CCP, `REQUIRED` may lie above the image limit, because a running
program may use the CCP's memory.

## 7. Phase D: write

### 7.1 Passes

Phase D writes the stored sections in address order. For each stored section,
it makes one **write pass** for each alignment class that has live blobs in that
section, from the largest down, then one for unaligned blobs. Each write pass
reads the library directory and byte section, then the program directory and
byte stream, from their starts, and emits that section's live blobs of that
class.

The `startup` blob is the library's first record, so the first write pass meets
it first and emits it before anything else; that is the `START` section.

When `DATA` is separate, its write passes are followed by the same passes again
to write `COPY` (Section 7.3).

A typical CP/M program has no aligned blobs and no separate `DATA`, so its whole
image is one write pass.

### 7.2 Emitting a blob

For each blob record read in a pass:

- **Dead, or not in this pass:** skip its stored bytes. Where the platform has
  random reads, the linker may skip whole 128-byte records. Under CP/M, a
  random read (BDOS function 33) leaves the file positioned so that the next
  sequential read returns the same record again; the linker accounts for this.
- **Live and in this pass:** write any alignment padding, then copy the blob's
  bytes. References are read one at a time in step with the copy: read the next
  reference, copy bytes up to its offset, compute its value, write it in place
  of the placeholder, skip the placeholder bytes, and repeat. No reference list
  is held in memory.

Every byte written is also added to the running image CRC.

### 7.3 The `COPY` section

`COPY` is a byte-for-byte image of `DATA`. It is produced by repeating the
`DATA` write passes with the output continuing at the `COPY` base, but with
every padding length and every reference value computed exactly as for `DATA`,
from `DATA` addresses. A reference inside a `data` blob that points at a `bss`
buffer therefore holds the same value in both copies, and startup's block copy
reproduces `DATA` exactly. `COPY` contributes no line-table entries.

### 7.4 Value checks

| Condition | Diagnostic |
| --- | --- |
| A value that breaks the range rule (object format, Section 5.1) | `L-RANGE` |
| A byte stream shorter or longer than its trailer says | `L-TRUNCATED` |
| Nonzero placeholder bytes, when verification is requested | `L-PLACEHOLDER` |

A live blob cannot reference a dead one, because marking follows every
reference.

### 7.5 Output kinds

| Kind | Contents |
| --- | --- |
| `.COM` | The stored image from the image base, as a flat binary. Requires image base `$0100`. The final 128-byte record is padded with zeros. |
| `.BIN` | The stored image from the image base, as a flat binary, padded likewise on CP/M. |
| `.HEX` | Intel HEX (Section 7.6). |

### 7.6 Intel HEX

- Data records only (type `00`), each holding at most 16 bytes, with absolute
  16-bit addresses. No extended address records.
- Each record is `:` then byte count, address (high byte first), type, data and
  checksum, as uppercase hexadecimal; the checksum is the two's complement of
  the low byte of the sum of every preceding byte of the record.
- Records break at every 16-byte boundary. Alignment padding is part of the
  image and is written as data.
- The file ends with `:00000001FF`. Each line ends with CR LF. On CP/M the file
  is padded with `$1A`.

### 7.7 The line table

When the program has a line stream and option `N` is not given, the linker
writes the line table during Phase D, in address order, with no sorting:

- Before the first write pass, it writes the header, copying the part names
  from the line stream's part records, which all precede its blob-lines records
  and were read in Phase A.
- In each write pass except those for `COPY`, for every live blob other than a
  program `code` blob, it writes a start entry (object format, Section 11) as it
  emits the blob.
- In the write pass that emits unaligned `TEXT` blobs, it reads the line stream
  forward in step with the program directory. Blob-lines records are in
  directory order, so when it emits a program `code` blob, that blob's record is
  next in the line stream; it writes one entry per statement at the blob's
  address plus the statement's offset. When the line stream ends, the linker
  checks its trailer CRC.

Write passes run in address order, and each emits blobs in address order, so the
entries come out sorted. The image CRC goes in the line table's trailer, written
after the last pass. The line table is written under a temporary name and
published with the image ([toolchain](toolchain.md), Section 6).

### 7.8 Files and buffers

At most seven files are open during Phase D: the library twice (for its
directory and its byte section), the program directory, byte stream and line
stream, the output, and the line table. CP/M allows a file to be opened for
reading with two file control blocks at once. Each open file takes a 36-byte
FCB and a 128-byte buffer, about 1.2K in all.

Records and references cross record boundaries, so the linker keeps a byte
cursor into each buffer. An `ABS16` at the last byte of a record spans two
records, in the byte stream and in the output.

## 8. Phase E: reports

After the image and line table are written and published, the linker writes the
reports requested on the command line. A failure here is reported but does not
undo publication; a partly written report is deleted.

### 8.1 Map

A text file in four parts:

1. **Summary:** input names, runtime and profile identities, output kind, image
   base and end, `BSS` start and size, stack reserve and largest frame, whether
   any routine can recurse, `REQUIRED`, the profile's image limit and nominal
   top, the margin to each, and the debugger margin.
2. **Live blobs,** one line each in address order: address, size, kind, padding
   paid, ordinal, and name.
3. **Removed blobs,** one line each in directory order: ordinal, kind, size and
   name.
4. **Totals:** bytes kept and removed, for the program and the library.

Addresses and ordinals are hexadecimal; sizes are decimal. Names come from the
name stream and the library's name section; where none exists, the ordinal
alone is printed.

**How it is produced.** Name records are in directory order, so the live-blob
list is written by repeating the placement passes once more, reading the name
stream in step with the program directory and the library's name section in
step with the library directory. The removed-blob list is one further pass over
both directories.

### 8.2 Symbol file

A `.SYM` file for Digital Research's `SID` and `ZSID`: one line per live named
blob in address order, then one per live named alias, each consisting of four uppercase hexadecimal
digits, one space and the name truncated to 16 characters, ending in CR LF; the
file ends with `$1A`. This format is believed correct and must be checked against
the `SID` manual before implementation. It is produced in the same pass as the
map's live list.

### 8.3 Names in diagnostics

A diagnostic from Phases A to D names the ordinal concerned. When a name stream
or name section exists, the linker then reads it forward to find and print the
name, which costs nothing unless an error occurs.

## 9. Diagnostics

An error stops the link and leaves the previous output in place
([toolchain](toolchain.md), Section 6).

| Code | Severity | Meaning |
| --- | --- | --- |
| `L-FORMAT` | error | Bad magic or an unsupported version |
| `L-COMPAT` | error | Program and library are not compatible |
| `L-STAMP` | error | Program streams from different compilations |
| `L-OPTION` | error | An option the profile doesn't support |
| `L-OUTPUT` | error | An output kind the profile doesn't support |
| `L-ORDINAL` | error | Ordinal out of range or defined twice |
| `L-RESERVED` | error | A reserved kind, form, subtype or value |
| `L-BLOB` | error | A malformed blob record |
| `L-REFERENCE` | error | A malformed reference |
| `L-ALIAS` | error | A malformed alias |
| `L-ENTRY` | error | A missing, repeated or invalid `ENTRY` |
| `L-LIMITS` | error | A missing, repeated or misplaced `LIMITS` |
| `L-STARTUP` | error | A missing, repeated or invalid `startup` blob |
| `L-UNDEFINED` | error | A reference to an ordinal never defined |
| `L-TRUNCATED` | error | A missing trailer, bad CRC or wrong length |
| `L-CAP-TABLES` | error | The tables don't fit in memory |
| `L-FIT-IMAGE` | error | The stored image exceeds the image limit |
| `L-FIT-MEMORY` | error | Image, `BSS` and stack exceed the address space |
| `L-FIT-RAM` | error | ROM: `DATA` and `BSS` exceed RAM |
| `L-FIT-NOMINAL` | warning | The program may not fit a typical machine |
| `L-RANGE` | error | A reference value breaks the range rule |
| `L-PLACEHOLDER` | error | Nonzero placeholder bytes, under verification |
| `L-IO` | error | A read or write failed, or a disk or directory is full |

A byte stream longer than its trailer says is detected only to 128-byte record
granularity, since CP/M records the length of a file only in whole records.

## 10. File reads

Let *C* be the number of alignment classes with live blobs, counting unaligned
as a class, and *W* the number of write passes: the classes present in each
stored section, summed over sections, with `DATA`'s counted twice when `COPY`
exists.

| File | Reads |
| --- | --- |
| Library and program directories | Phase A once; Phase C *C* times; Phase D *W* times; the map *W* + 1 times when requested |
| Library byte section and program byte stream | once per write pass, skipping blobs not in the pass |
| Line stream | Phase A, for the part records; once more in Phase D |
| Name stream and library name section | *W* + 1 times when the map or symbol file is requested; on a diagnostic, once more |

A typical CP/M build without a map has *C* = *W* = 1, so it reads each directory
three times, each byte stream once and the line stream twice.

## 11. Conformance

An implementation conforms when it produces, for every valid input, exactly the
image these rules define, and rejects every invalid input with the diagnostic
named. The suite includes at least:

- a program with no dead blobs;
- dead blobs at the start, middle and end of each section, and in the library;
- a chain of references through a forward-declared routine, and a record
  following it;
- aliases, including one referenced only from an otherwise dead blob;
- a blob that references the same target many times, and one with hundreds of
  distinct targets;
- every reference form, including an `ABS16` spanning a 128-byte record in the
  directory, in the byte stream and in the output;
- end-pointer references at exactly `addr + size`, and one byte beyond (an
  error);
- aligned blobs of every class, checking padding, order and pass count;
- self-references and negative addends;
- empty `BSS` and empty `DATA`, checking that startup handles size 0;
- re-runnable and keep-CCP images, checking `OPTIONS` and that `COPY` equals
  `DATA` byte for byte, including a `data` blob that references a `bss` blob;
- an alias with a reference past its effective end (an error);
- a library with aliases, linked with a program that references them;
- every diagnostic in Section 9, from a minimal file that triggers it;
- the largest program the tables allow, and one ordinal beyond it; and
- linking the same inputs twice and comparing the outputs byte for byte.

The reference linker (`ref/link`) has no fixed tables, so `L-CAP-TABLES` and
"the largest program the tables allow" apply only to `BLINK.COM`; its version
of these tests checks the highest program ordinal and the first one beyond it.
`L-IO` comes from the toolchain's disk layer (`ref/toolchain`) and is tested
there with injected disk faults.

## 12. Open questions

1. **Table sizes.** If measurement shows typical programs nearing
   `L-CAP-TABLES`, the edge lists could use 1-byte targets relative to a nearby
   base, or the compiler could write each blob's targets deduplicated so the
   linker stores them as they come.
2. **Placeholder verification** on by default, or only with option `V`?
