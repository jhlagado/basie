# Baton linker 1.0

- Status: draft specification, revision 2 (after adversarial review)
- Date: 2026-10-03
- Related: [object format](object-format.md), [toolchain](toolchain.md),
  [CP/M target](cpm-target.md), [build pipeline](build-pipeline.md),
  [review](reviews/2026-10-03-linker-spec-review.md)

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

The linker runs as a phase of the Baton executable, or alone in link-only
mode; see the [toolchain](toolchain.md).

## 2. Memory

### 2.1 Tables

| Table | Entry | Indexed by | Grows |
| --- | --- | --- | --- |
| Library table | 8 bytes | library ordinal, `$0000`–highest | fixed; its size is in the library header |
| Program table | 8 bytes | program ordinal minus `$0400` | upwards, after the library table |
| Pseudo table | 8 bytes | pseudo ordinal minus `$FFE0` | fixed, 8 entries |
| Edge lists | 2 bytes per edge, plus a 2-byte terminator per blob | — | downwards from the top of free memory |
| Mark stack | 2 bytes | — | in the gap between the tables and the edge lists, after Phase A |

The library table's size is known from the library header before any record is
read. The program table grows as Phase A meets program ordinals, whether as
definitions or as reference targets; a newly covered entry is zeroed. The edge
lists grow down from the top. If the program table and the edge lists meet,
the linker stops with `L-CAP-TABLES`.

**Table entry** (8 bytes):

| Field | Size | Meaning |
| --- | --- | --- |
| flags | 1 | Bits 0–2: kind. Bit 3: defined. Bit 4: referenced. Bit 5: live. Bit 6: alias. Bit 7: root |
| size | 2 | Blob size; for an alias, its offset |
| address | 2 | Assigned in Phase C; for an alias before Phase C, its base ordinal |
| edges | 2 | Address of the blob's first edge; the list ends with ordinal `$0000` |
| stamp | 1 | Deduplication stamp (Section 4.2) |

Pseudo-object entries hold the address and size the linker computes, and a
stamp.

### 2.2 Capacity

**[estimate]** At 8 bytes per ordinal, 4 bytes per blob for the edge
terminator and the mark stack, and 2 bytes per distinct edge:

| Program | Library ordinals | Program ordinals | Distinct edges | Memory |
| --- | ---: | ---: | ---: | ---: |
| Typical, 20K output | 200 | 800 | 4,000 | 1.6K + 6.4K + 4.0K + 8.0K = 20K |
| Large, 40K output | 200 | 2,000 | 9,000 | 1.6K + 16K + 8.8K + 18K = 44K |
| Largest, 56K output | 200 | 3,000 | 14,000 | 1.6K + 24K + 12.8K + 28K = 66K |

With literals inside their routines, a program has roughly one blob per
routine, top-level variable and top-level constant.

The [toolchain](toolchain.md) leaves about 47K for these tables on a CP/M 2.2
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

- **Blob record:** check it; fill its table entry and set the defined bit;
  append the distinct targets of its references to the edge lists, then a
  terminator; set the referenced bit of each target.
- **`ALIAS`:** check it; fill the alias's entry with the alias bit, the base
  ordinal and the offset.
- **`ENTRY`:** record the entry ordinal.
- **`LIMITS`:** record the stack reserve and flags.

Finally it checks each trailer and, once both directories are read, every
cross-record rule (Section 4.3).

### 4.2 Deduplication

Each blob record gets a sequence number from 1 to 255, counting blob records
across both directories. When the count would reach 256, the linker clears every
stamp in every table to 0 and restarts the count at 1.

Before appending a target, the linker compares the target's stamp with the
current sequence number. If they are equal, the target has already been
appended for this blob and is skipped. Otherwise the linker appends it and sets
the target's stamp to the sequence number. Since sequence numbers are never 0
and cleared stamps are 0, no blob's first reference to a target is ever
skipped.

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
| A `SIZE16` naming an alias; a reference to `$0000` or a reserved pseudo-object | `L-REFERENCE` |
| An alias outside its owner's range, whose base is an alias, is undefined, is in the other directory, or whose offset is not below the base's size | `L-ALIAS` |
| Not exactly one `ENTRY` record, or an entry ordinal that is not a `code` blob in the program | `L-ENTRY` |
| Not exactly one `LIMITS` record, or one before the last blob record | `L-LIMITS` |
| Not exactly one `startup` blob in the library, or a `startup` blob without a reference to `MAIN` | `L-STARTUP` |
| A referenced ordinal that is never defined | `L-UNDEFINED` |
| Missing or bad trailer, CRC, count or highest ordinal; library header and trailer disagree | `L-TRUNCATED` |
| The tables don't fit | `L-CAP-TABLES` |

`L-UNDEFINED` is found by scanning both tables at the end of Phase A for entries
with the referenced bit set and the defined bit clear. It signals a version
mismatch or a compiler fault, since the compiler rejects an incomplete forward
declaration.

## 5. Phase B: mark

1. Push every root.
2. While the stack is not empty, pop an ordinal and walk its edge list. For
   each target: resolve `MAIN` to the entry routine and an alias to its base;
   ignore other pseudo-objects; if the result is a blob without the live bit,
   set the bit and push it.

Each blob is pushed at most once, so marking takes time linear in blobs plus
edges. The live bits form the **live set**.

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

**Where sections go.**

- **CP/M:** `START`, `TEXT`, `DATA` and `COPY` follow one another from the image
  base, and `BSS` follows the stored image.
- **ROM:** `START`, `TEXT` and `COPY` go into ROM from the image base. `DATA`
  and `BSS` go into RAM from the RAM base; `DATA` occupies RAM addresses but has
  no stored bytes there.

### 6.2 Placement passes

Within each section, blobs are placed in **placement passes**:

1. one pass for each alignment class that has live blobs, from 256 down to 2
   bytes; then
2. one pass for unaligned blobs.

Within a pass, library blobs come before program blobs, each in directory
order. The order is a pure function of the inputs, so the same inputs always
produce the same image, byte for byte.

A pass places each blob at the next address rounded up to the blob's alignment.
Padding is zeros in stored sections. Each alignment class pays padding at most
once at its start, plus whatever its own blobs' sizes cause between them.

### 6.3 Assigning addresses

Placement order is directory order within a pass, and the tables are indexed
by ordinal, not by directory position. So Phase C reads both directories once
for each placement pass that has live blobs, in the same order Phase D will
use, and assigns each live blob in the pass the next address. This is the same
sequence of reads as Phase D (Section 7.1) without the byte streams.

Aliases take their base's address plus their offset. Then the linker computes
the pseudo-objects (object format, Section 3.4) from the section boundaries,
the `LIMITS` stack reserve and the options.

### 6.4 Fit checks

| Check | Result if it fails |
| --- | --- |
| Stored image ends at or below the profile's image limit, and no blob starts at `$FFFF` | `L-FIT-IMAGE`, error |
| `BSS` plus the stack reserve ends at or below 65,536 | `L-FIT-MEMORY`, error |
| `REQUIRED` at or below the profile's nominal top | `L-FIT-NOMINAL`, warning |
| ROM: `DATA` and `BSS` lie between the RAM base and the RAM limit | `L-FIT-RAM`, error |

`L-FIT-NOMINAL` is a warning because the real top of memory varies; startup
makes the final check on the running machine. On CP/M 2.2, `REQUIRED` may lie
above the image limit, because a running program may use the CCP's memory.

## 7. Phase D: write

### 7.1 Passes

Phase D writes the image by repeating the placement passes of Phase C, section
by section. Each pass reads the library directory and byte section and then the
program directory and byte stream, from their starts. A typical CP/M program has
no aligned blobs and no separate `DATA`, so its whole image is one pass.

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

### 7.3 Value checks

| Condition | Diagnostic |
| --- | --- |
| A value that breaks the range rule (object format, Section 5.1) | `L-RANGE` |
| A byte stream shorter or longer than its trailer says | `L-TRUNCATED` |
| Nonzero placeholder bytes, when verification is requested | `L-PLACEHOLDER` |

A live blob cannot reference a dead one, because marking follows every
reference.

### 7.4 Output kinds

| Kind | Contents |
| --- | --- |
| `.COM` | The stored image from the image base, as a flat binary. Requires image base `$0100`. The final 128-byte record is padded with zeros. |
| `.BIN` | The stored image from the image base, as a flat binary, padded likewise on CP/M. |
| `.HEX` | Intel HEX (Section 7.5). |

### 7.5 Intel HEX

- Data records only (type `00`), each holding at most 16 bytes, with absolute
  16-bit addresses. No extended address records.
- Each record is `:` then byte count, address (high byte first), type, data and
  checksum, as uppercase hexadecimal; the checksum is the two's complement of
  the low byte of the sum of every preceding byte of the record.
- Records break at every 16-byte boundary. Alignment padding is part of the
  image and is written as data.
- The file ends with `:00000001FF`. Each line ends with CR LF. On CP/M the file
  is padded with `$1A`.

### 7.6 The line table

When the program has a line stream and option `N` is not given, the linker
writes the line table during Phase D, in address order, with no sorting:

- In each pass, for every live blob that does not start with a statement, it
  writes a start entry (object format, Section 11) as it emits the blob.
- In the pass that emits unaligned `code` blobs, it reads the line stream
  forward in step with the program directory. Blob-lines records are in
  directory order, so when it emits a `code` blob, the blob's record is next in
  the line stream; it writes one entry per statement at the blob's address plus
  the statement's offset.

Passes run in address order, and each pass emits blobs in address order, so the
entries come out sorted. The image CRC goes in the line table's trailer, written
after the last pass. The line table is written under a temporary name and
published with the image ([toolchain](toolchain.md), Section 6).

### 7.7 Files and buffers

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
blob and alias, in address order, consisting of four uppercase hexadecimal
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

## 10. File reads

Let *P* be the number of placement passes (1 for a typical CP/M program).

| File | Reads |
| --- | --- |
| Library and program directories | Phase A once; Phase C *P* times; Phase D *P* times; the map *P* + 1 times when requested |
| Library byte section and program byte stream | Phase D once in total, across its passes, with dead bytes skipped |
| Line stream | once, in Phase D |
| Name stream and library name section | *P* + 1 times when the map or symbol file is requested; on a diagnostic, once more |

A typical build without a map reads each directory three times and each byte
stream once.

## 11. Conformance

An implementation conforms when it produces, for every valid input, exactly the
image these rules define, and rejects every invalid input with the diagnostic
named. The suite includes at least:

- a program with no dead blobs;
- dead blobs at the start, middle and end of each section, and in the library;
- a chain of references through a forward-declared routine, and a record
  following it;
- aliases, including one referenced only from an otherwise dead blob;
- more than 256 blob records, so the stamp clear happens, with a blob after the
  clear that references targets stamped before it;
- every reference form, including an `ABS16` spanning a 128-byte record in the
  directory, in the byte stream and in the output;
- end-pointer references at exactly `addr + size`, and one byte beyond (an
  error);
- aligned blobs of every class, checking padding, order and pass count;
- self-references and negative addends;
- empty `BSS` and empty `DATA`, checking that startup handles size 0;
- re-runnable and keep-CCP images, checking `OPTIONS`;
- every diagnostic in Section 9, from a minimal file that triggers it;
- the largest program the tables allow, and one ordinal beyond it; and
- linking the same inputs twice and comparing the outputs byte for byte.

## 12. Open questions

1. **Table sizes.** If measurement shows typical programs nearing
   `L-CAP-TABLES`, the edge lists could use 1-byte targets relative to a nearby
   base, or the compiler could write each blob's targets deduplicated so the
   linker stores them as they come.
2. **Placeholder verification** on by default, or only with option `V`?
