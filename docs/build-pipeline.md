# Build pipeline: object spools and the layout step

- Status: design proposal, revision 2
- Date: 2026-10-03
- Replaces: the final-address model of the Nucleus Object Stream Format 0.1
  (`../nucleus/docs/nucleus-object-format.md`)
- Revision 2 incorporates a CP/M and Z80 toolchain review of revision 1. Its
  corrections are listed in Section 15.

Estimates marked **[estimate]** are reasoned but unmeasured. They must be
replaced by measurements of real compiler output before this document becomes a
specification.

## 1. Purpose

This document defines how Baton turns one compilation into a runnable program
image. Its main goal is **tree shaking**: the output contains only the
routines, constants, variables and runtime helpers the program can actually
reach. It keeps the Nucleus constraint that the compiler reads its source once,
in a single streaming pass.

The pipeline has two programs:

1. The **compiler** reads the source once and writes a set of append-only
   **object spools**. It never assigns final addresses.
2. The **layout tool** reads those spools and a prebuilt **runtime spool set**,
   finds the live parts of the program, assigns addresses and writes the
   program image, such as a CP/M `.COM` file.

The primary target is CP/M 2.2 and CP/M 3 on a 64K Z80, where both programs run
on the Z80 itself and read and write floppy or hard-disk files. Section 13
covers ROM and banked targets.

## 2. Why Nucleus's approach cannot shrink programs

Nucleus emits every byte at its final address as soon as it is generated.
Forward references become `PATCH` records with final replacement bytes;
backward references are written straight into image bytes and leave no record.

Under that model, deciding that a routine is unused is impossible in one pass.
A routine's last possible caller may be the final line of the source, so its
liveness is known only at the end of input. By then the routine already
occupies addresses, and later code has been assembled against those addresses.
Removing it would shift everything after it, and the output does not record
which bytes are addresses. Recovering that information means marking every
address operand, which is the core of a relocating linker.

Any design that removes unused code must therefore do one of three things:

1. delay the choice of addresses until liveness is known;
2. place code, then move it, which needs full relocation information; or
3. read the source twice.

Baton takes the first option. The compiler emits code without addresses, and
the layout step places only what is live.

## 3. Design rules

1. **One source pass.** The compiler reads each source byte once. Everything
   after that reads compact binary spools.
2. **No names in linking.** Blobs are identified by number (an **ordinal**),
   never by name. There is no symbol table, no library search and no name
   resolution in the layout tool. Names appear only in an optional spool used
   for reports and debugger symbols.
3. **One program per run.** The layout tool combines one compilation with one
   runtime spool set. It does not combine separately compiled modules.
4. **No backward seeks.** Every spool is written append-only. Readers move
   forward only. A reader may skip forward with a random read where the
   platform provides one; it never returns to an earlier position. The design
   therefore also works on sequential stores such as TEC-FS.
5. **Fixups only for code addresses.** The layout tool fills in addresses. It
   never supplies type information or any other semantic fact the compiler
   lacked. This is the same rule Baton applies to forward declarations.
6. **Every address use is a reference.** No absolute address appears in a blob
   except through a reference record. This one rule gives the layout tool the
   complete call and data graph.

## 4. Blobs and ordinals

### 4.1 Blobs

A **blob** is the unit of placement and of removal: a contiguous run of bytes
that the layout tool places as a whole or drops as a whole. Every blob has an
ordinal, a kind, a size, an alignment and a list of references.

| Kind | Contents | Stored bytes | Produced by |
| --- | --- | --- | --- |
| `code` | One routine, with any jump tables or inline constants it owns | yes | compiler or runtime |
| `rodata` | One constant: an aggregate constant, a string literal, an aligned lookup table | yes | compiler or runtime |
| `data` | One initialised top-level variable | yes | compiler or runtime |
| `bss` | One zero-initialised top-level variable or pool | no, size only | compiler or runtime |
| `startup` | The program's first code, placed at the image base | yes | runtime spool set only |

Each source routine produces exactly one `code` blob. Each top-level variable
or constant produces one blob of the matching kind. Each string literal the
compiler places in read-only storage produces its own `rodata` blob, so a
literal used only by a dead routine is removed with it.

A blob must be **position-independent with respect to every other blob**:

- no relative jump (`JR`, `DJNZ`) may leave the blob;
- execution may not fall through from the end of one blob into the next; and
- no code may assume that two blobs are adjacent or in a particular order.

Relative branches *within* a blob are unrestricted, because a blob always moves
as a whole.

**Alignment applies to whole blobs only.** A `code` blob always has alignment
zero. A table that must be page-aligned, for example one indexed through
`LD H,hi(table)`, is its own `rodata` blob with its own alignment. This keeps
alignment padding off routines, and it lets the compiler shrink branches inside
a routine without moving an aligned table (Section 10.3).

**Shared tails and fall-through.** Nucleus's backend may share tail code
between routines. Across blobs, a shared tail must become an explicit `JP` to a
shared helper blob. The loss is small **[estimate]**: a cross-routine tail was
already a `JP` unless the two routines happened to be adjacent, so the cost is
at most 3 bytes per routine that used to fall through. The larger effect is on
hand-written runtime helpers that fall into one another, such as a multiply
that falls into a normalise step. Each helper is its own blob joined by
explicit `JP`s, so that a program using only one of them doesn't carry the
other.

### 4.2 Ordinals

An ordinal is an unsigned 16-bit number. The ordinal space is partitioned:

| Range | Use |
| --- | --- |
| `$0000` | Reserved; never a valid target |
| `$0001`–`$00FF` | Runtime blobs, numbered by the runtime's published helper table |
| `$0100`–`$011F` | Pseudo-ordinals supplied by the layout tool (Section 8.4) |
| `$0120`–`$FFFF` | Program blobs, assigned by the compiler |

The compiler assigns program ordinals in increasing order as it creates blobs.
A routine named by a forward declaration receives its ordinal at the forward
declaration, so calls before the body can refer to it. Ordinal order does not
determine placement order (Section 8.3).

Program ordinals are dense, because every ordinal the compiler assigns becomes
a blob. A forward declaration that is never completed is a compile-time error,
as in Nucleus.

### 4.3 Runtime blobs

The runtime is prebuilt in the same blob format and shipped as a **runtime
spool set**: a directory spool and byte spools with their own header
(Section 7.2). Its blobs have fixed ordinals below `$0100`, so the compiler
refers to a helper such as 16-bit multiply by number, without knowing its
address or size and without any name.

Runtime blobs are ordinary blobs: an unused helper is removed like any other.
This matters more in Baton than in Nucleus. `i32` and `f32` support may cost
several hundred bytes to about a kilobyte, and a program that never uses them
should carry none of it.

The runtime spool set is specific to a target profile. It supplies the
`startup` blob (Section 9.2) and anything else that depends on the operating
environment, such as the trap reporter and the console and file services.

## 5. References

### 5.1 Reference forms

A reference says: "at byte offset *o* in this blob, write a value derived from
blob *t*, plus addend *a*."

| Form | Writes | Typical use |
| --- | --- | --- |
| `ABS16` | 2 bytes, little-endian: `addr(t) + a` | `CALL`, `JP`, `LD HL,nn`, `LD A,(nn)`, `LD SP,nn`, address words in tables |
| `LO8` | 1 byte: low byte of `addr(t) + a` | Split address loads |
| `HI8` | 1 byte: high byte of `addr(t) + a` | Page-aligned table lookups (`LD H,hi(table)`) |
| `SIZE16` | 2 bytes: `size(t) + a` | Block copies and clears whose length is another blob's size |

The form field has room for eight forms (Section 7.4); the other four codes
are reserved.

**Addend arithmetic is modulo 65,536.** The addend is a 16-bit value and the
sum wraps. Field and element offsets are positive addends, and `table-1`
tricks are negative addends written as their two's-complement value. Because
the addend is not limited to a signed 16-bit range, a constant index into a
48K `bss` array (`buf[40000]`) is representable. A result that wraps past
`$FFFF` for an address that must lie inside the target's memory is an error
(Section 8.5).

A blob refers to its own internal labels with a **self-reference**: the target
ordinal is the blob's own, and the addend is the label's offset. An absolute
`JP` inside a routine, or a jump-table entry, is therefore relocated with the
routine at no extra cost.

No form expresses a relative displacement between two blobs or the difference
between two blobs' addresses. That distance is unknown until layout, and the
rules of Section 4.1 make it unnecessary. A `SIZE16` reference covers the one
common case, a block whose length is the size of a blob.

**Jump tables are address words.** A dispatch table is a sequence of `ABS16`
self-references, used with `JP (HL)`. A table of consecutive `JP` instructions
indexed by `index × 3` is allowed only if the compiler marks its entries as
fixed-size, because branch shrinking must not change their length
(Section 10.3).

**Self-modifying code** that writes into its own operand bytes is allowed: the
writing instruction's address operand is a self-reference.

### 5.2 What references give the layout tool

Because every address use is a reference (rule 6), a blob's reference targets
are exactly the blobs it can reach: the routines it calls or jumps to, the
variables and constants it reads or writes, and the helpers the compiler called
on its behalf. The layout tool computes reachability from this graph without
the compiler recording a separate call graph.

Future routine values are safe by construction. Taking a routine's address is a
reference from the blob that takes it, so a routine whose address is taken by
live code is live, with no special case.

## 6. The compiler's spools

### 6.1 Spool set

One compilation writes these files, each append-only:

| Spool | Contents |
| --- | --- |
| **Directory spool** | Header, then one blob record per blob, each followed by that blob's references, then a trailer |
| **Byte spool** | Raw bytes of every blob with stored bytes, in directory order |
| **Line spool** (optional) | Source positions keyed by (ordinal, offset), for debugging and source maps (Section 11) |
| **Name spool** (optional) | Ordinal-to-name pairs for maps and debugger symbol files |

`bss` blobs have no bytes, so they appear only in the directory.

**One byte spool for CP/M.** Every blob with stored bytes goes into a single
byte spool in directory order, whatever its kind. On a `.COM` target all stored
blobs are placed in that order (Section 8.3), so the layout tool writes the
image in a single pass that reads the directory spool and the byte spool
together. A ROM target, which must separate initialised data from code, uses
per-kind byte spools instead (Section 13.1).

### 6.2 Why references follow the bytes

The compiler writes a blob's bytes as it generates them, but often learns a
reference's final form only later. A forward `JP` to a label later in the same
routine is the common case: the site's offset is known when the `JP` is
emitted, the label's offset only when the label is reached.

The compiler therefore keeps the routine's pending references in memory and
writes the blob record and all its references to the directory spool when the
routine ends. By then the blob's size and every self-reference addend are
known. The bytes have already gone to the byte spool, unless the routine is
buffered for branch shrinking (Section 10.3).

References within one blob record are written in strictly increasing offset
order. The compiler sorts its pending list before writing it; the list is short
and nearly sorted already, so an insertion sort suffices. Two references at the
same offset are invalid, and the layout tool rejects them.

The compiler's memory cost is the pending reference list for one routine at a
time, about 5 bytes per reference. The Nucleus pending-fixup table, which held
every unresolved cross-routine call site in the program, disappears. A
published capacity limits references per routine; exceeding it is a capacity
diagnostic, never a silent split.

### 6.3 Spool names and cleanup

Spools take their names from the program, with `$` in the file type so that
stray files are recognisable and `ERA *.$*` removes them: for a program `PROG`,
`PROG.$DR` (directory), `PROG.$BY` (bytes), `PROG.$LN` (lines) and `PROG.$NM`
(names). The compiler and the layout tool each accept a drive designator for
spools, in the manner of Microsoft's `M80` and `L80`, and the layout tool
accepts a separate drive for the runtime spool set.

The layout tool deletes the program's spools after it has written the output
successfully, unless asked to keep them.

## 7. Spool encodings

All multi-byte integers are little-endian.

### 7.1 Program directory header

| Field | Type | Meaning |
| --- | --- | --- |
| magic | 4 bytes | ASCII `BTND` |
| format version | `u8`, `u8` | Directory format major and minor version |
| runtime identity | `u16` | The runtime spool set this program was compiled against |
| helper-table version | `u16` | Minimum runtime helper-table version required |
| target profile | `u16` | Target profile identity |

### 7.2 Runtime directory header

| Field | Type | Meaning |
| --- | --- | --- |
| magic | 4 bytes | ASCII `BTNR` |
| format version | `u8`, `u8` | Directory format version |
| runtime identity | `u16` | Identity of this runtime |
| helper-table version | `u16` | Version of the helper ordinal table it provides |
| target profile | `u16` | Target profile it was built for |

### 7.3 Blob record

| Field | Type | Meaning |
| --- | --- | --- |
| header | `u8` | Bits 0–2: kind (five of eight codes used). Bit 3: an explicit ordinal follows. Bit 4: root (Section 8.2). Bits 5–7: alignment |
| ordinal | `u16`, optional | Present only when bit 3 is set; otherwise the ordinal is one more than the previous blob's |
| size | `u16` | Byte length: stored bytes, or reserved size for `bss` |
| reference count | `u8` | 0–254 references; 255 escapes to a following `u16` count |

The alignment field holds log2 of the alignment for values 0 to 6 (1 to 64
bytes). The value 7 means page alignment, 256 bytes. Alignment to 128 bytes is
not supported.

Records carry no tag byte, because the trailer gives the record count. A
typical record is 4 bytes. Only forward-declared routines, whose ordinals were
assigned out of sequence, need the explicit ordinal.

### 7.4 Reference entry

| Field | Type | Meaning |
| --- | --- | --- |
| control | `u8` | Bits 0–3: offset delta, 0–14, or 15 to escape to a following `u16` absolute offset. Bit 4: an addend follows. Bits 5–7: form |
| target | `u16` | Target ordinal, all 16 bits |
| addend | `u16`, optional | Present when bit 4 is set |

For a blob's first entry, the delta is its offset from the start of the blob.
For each later entry, it is the distance from the previous entry's offset and
must be at least 1, which enforces strictly increasing offsets. A delta of 0
after the first entry is invalid.

The four defined forms take codes 0–3; codes 4–7 are reserved. The typical
entry, a `CALL` with no addend, costs 3 bytes. A self-reference or field
reference costs 5, or 7 when the offset needs the escape.

### 7.5 Trailer

| Field | Type | Meaning |
| --- | --- | --- |
| marker | `u8` | `$FF`, which cannot begin a blob record because kind code 7 is undefined |
| blob count | `u16` | Number of blob records |
| byte spool length | `u16`, `u16` | Total stored bytes, as 32 bits |
| directory CRC | `u16` | CRC-16/CCITT-FALSE over every directory byte before this field |

The layout tool rejects a directory without a valid trailer, so an interrupted
compilation can never be laid out. It checks the byte spool's length against
the trailer rather than a CRC over its contents, because it skips the bytes of
dead blobs without reading them where it can (Section 8.5).

### 7.6 Size of the spools

**[estimate]** For a 40K program:

- **Blobs.** With every string literal a separate blob, 1,500 to 3,000 blobs.
  At about 4 bytes per record, 6K to 12K.
- **References.** Code that works on globals is dense in addresses: `x = y + z`
  on `u16` globals is `LD HL,(y)`, `LD DE,(z)`, `ADD HL,DE`, `LD (x),HL`, which
  is 10 bytes with three references. Checked array accesses and trap sites
  call helpers, and every 32-bit or `f32` operation is a helper call. Only
  locals and register arithmetic are reference-free. Expect one reference per
  4 to 5 bytes in code that works mainly on globals, so 8,000 to 10,000
  references, or 30K to 40K at 3 to 5 bytes each.
- **Directory spool**, then, 36K to 52K, comparable to or larger than the
  program itself. The byte spool is 40K.

The reference density must be measured on real compiler output before the
format is fixed. If it is near the top of this range, the directory spool is
the main disk cost of the design.

## 8. The layout tool

The layout tool is a separate CP/M program. It runs after the compiler has
exited, so it has the transient program area to itself.

### 8.1 Phase A: read the directories

Read the runtime directory spool, then the program directory spool, start to
end. Check both headers against each other and against the layout tool's own
format version (Section 12). For each blob, record in a table indexed by
ordinal:

| Field | Size |
| --- | --- |
| kind, flags and alignment | 1 byte |
| size | 2 bytes |
| address (filled in Phase C) | 2 bytes |
| first edge index | 2 bytes |
| last-seen stamp | 1 byte |

and append the distinct target ordinals of its references to an edge array.
Duplicates within one blob are dropped, since a routine that calls `print`
twenty times needs one edge. The **last-seen stamp** makes deduplication cheap:
before appending a target, compare its stamp with a per-blob counter; if they
match, the edge is a duplicate. The stamp wraps every 256 blobs, so on wrap the
tool clears every stamp, once per 256 blobs.

**Memory.** At 8 bytes per ordinal and 2 bytes per edge **[estimate]**:

| Program | Blobs | Distinct edges | Tables |
| --- | --- | --- | --- |
| Typical, 20K | 800 | 4,000 | 6K + 8K = 14K |
| Large, 40K | 2,000 | 9,000 | 16K + 18K = 34K |
| Largest, 56K | 3,000 | 14,000 | 24K + 28K = 52K |

The tool's code and buffers take a few kilobytes. Its tables get the rest of
the transient program area: about 44K to 56K, depending on the system
(Section 9.1). The largest programs approach that limit, and on a system with a
small transient program area they exceed it.

**Edge overflow is a capacity error.** If the tables don't fit, the layout tool
stops and reports the program's blob and edge counts and the memory it needed.
Revision 1 proposed a fallback that rescanned the directory spool until no new
blob was marked. That fallback is slow exactly when it is needed: declaration
before use makes almost every reference point to an earlier blob, so each scan
advances only one level down the call graph. A program 20 levels deep would
need about 20 scans of a 50K directory spool, several minutes on floppies.
Section 14 lists ways to reduce the table sizes if measurements show they
matter.

### 8.2 Phase B: mark live blobs

The **roots** are:

- the `startup` blob;
- blobs flagged as roots in either directory. In the runtime spool set, this
  covers code that the system reaches without a call from the program, such as
  restart vectors the startup code installs. In the program, it covers routines
  the source marks for fixed-address use (reserved for future interrupt and
  exported routines).

`main` is not a root by itself: `startup` reaches it through the `MAIN`
pseudo-ordinal (Section 8.4), which the layout tool binds to the program blob
the compiler flags as the entry routine.

Marking is a depth-first walk with an explicit stack of ordinals. Each blob is
marked once, so the cost is linear in blobs plus edges.

### 8.3 Phase C: assign addresses

For a CP/M `.COM` image the tool places live blobs in this order:

1. `startup`, at `$0100`;
2. every live blob with stored bytes, in directory order (runtime blobs first,
   then program blobs), except that blobs with nonzero alignment come first,
   largest alignment first, so that alignment padding is paid once rather than
   once per aligned blob;
3. live `bss` blobs, after the end of the stored image, aligned blobs first in
   the same way.

Directory order keeps related blobs together and makes the output
deterministic: the same spools always produce the same image. On a flat target
placement order has no effect on speed.

The tool then binds the pseudo-ordinals (Section 8.4), checks that the program
fits the target (Section 9.5), and stops with a report if it doesn't.

### 8.4 Pseudo-ordinals

The layout tool supplies values only it can know. Startup and runtime code
refer to them like any other blob:

| Pseudo-ordinal | Value |
| --- | --- |
| `MAIN` | Address of the program's entry routine |
| `IMAGE_END` | First address after the stored image |
| `BSS_START` | Address of the first `bss` byte |
| `BSS_SIZE` | Total `bss` size, read through a `SIZE16` reference |
| `FREE_START` | First address after `bss`, where free memory begins |
| `STACK_RESERVE` | The program's declared minimum stack, in bytes |
| `REQUIRED_TOP` | `FREE_START + STACK_RESERVE`: the lowest acceptable top of memory |
| `DATA_COPY`, `DATA_START`, `DATA_SIZE` | ROM and re-run support (Sections 9.6 and 13.1) |

### 8.5 Phase D: write the image

The tool reads the directory spools and byte spools forward, together, and
writes the output in address order. For each blob in placement order:

- **Dead blob:** skip its bytes in the byte spool. Where the platform supports
  random reads (CP/M BDOS function 33), skip whole dead records without reading
  them; otherwise read through them.
- **Live blob:** copy its bytes to the output, and as each reference's offset is
  reached, write the computed value in place of the placeholder bytes.

The tool keeps byte-level cursors into each spool, because blobs and references
cross 128-byte record boundaries: an `ABS16` at offset 127 of a record spans two
records.

Errors in this phase:

- a reference to an ordinal that has no blob (a version mismatch, since the
  compiler rejects incomplete forward declarations);
- a computed address that wraps past `$FFFF` or lies outside the target's
  memory;
- a `HI8` reference into a table that is not page-aligned, when the compiler
  flagged it as requiring alignment; and
- a byte spool shorter or longer than its trailer says.

A reference from a live blob to a dead blob cannot occur, because marking
followed every reference.

The final 128-byte record of a `.COM` file is padded with zeros. The layout tool
writes that record, so the padding is defined.

**Files.** Phase D has at most five files open: the runtime directory and byte
spools, the program directory and byte spools, and the output. Each needs a
36-byte file control block and a 128-byte buffer. Across a whole run the tool
touches about a dozen files: four runtime and program spools, the target
profile, the output, the map, the removal report and the symbol file.

**I/O cost [estimate].** For a 40K program, Phase A reads 40K to 55K of
directory and Phase D reads the same again plus 40K of bytes, then writes 40K of
output. With the compiler's 80K to 95K of spool writes, a build moves about
250K through BDOS, against about 80K for Nucleus's direct emission. At 2 to 4K
per second from a floppy, that is one to two minutes of transfer per build.

### 8.6 Reports

The tool writes:

- a **map**: each live blob's address, size, kind and ordinal, with names from
  the name spool where present, and the padding paid for each aligned blob;
- a **removal report**: the dead blobs and the bytes saved;
- the **memory budget**: image end, `bss` size, stack reserve, `REQUIRED_TOP`,
  and the margins described in Section 9.5; and
- optionally, a **`.SYM` file** for Digital Research's `SID` and `ZSID`
  debuggers. Their format is believed to be lines of a four-digit hexadecimal
  address followed by a name, with names limited to 16 characters; this must be
  checked against the debuggers. The name spool records names already
  shortened to that limit.

### 8.7 Output replacement

CP/M has no way to rename one file over another. CP/M 2.2's rename function is
believed not to check whether the new name already exists, which can leave two
directory entries with the same name; CP/M 3 returns an error instead. The
layout tool therefore replaces an existing output in this order:

1. write the image to `PROG.$$$` and close it;
2. delete `PROG.BAK`, rename `PROG.COM` to `PROG.BAK`;
3. rename `PROG.$$$` to `PROG.COM`.

Replacement is therefore not atomic. If the system stops between steps 2 and
3, `PROG.COM` is missing, but `PROG.BAK` holds the previous version and
`PROG.$$$` the new one. A profile option can skip the backup, at the cost of a
window with no program at all.

## 9. CP/M runtime environment

### 9.1 Memory and the top of usable memory

The word at `$0006` is the address of the lowest resident system component, not
always the BDOS:

- under CP/M 2.2 alone, it is the BDOS entry, six bytes above the BDOS base
  (the first six bytes hold the serial number);
- under `DDT`, `SID` or `ZSID`, it is the debugger, about 5K lower; and
- under CP/M 3, it is the resident BDOS or the lowest resident system
  extension (RSX).

In every case it is the correct top of memory for a program. Startup uses it as
the stack top: the first push lands on serial-number bytes, which nothing
checks after boot.

Typical transient program areas range from about 44K, on CP/M 2.2 systems with
large BIOSes or Z-System environments in high memory, to about 60K on banked
CP/M 3.

### 9.2 Startup

The `startup` blob comes from the runtime spool set, because it depends on the
operating environment. Under CP/M it does this in order:

1. **Set the DMA address** to a runtime buffer with BDOS function 26, before
   any other BDOS call. The command tail at `$0080` is overwritten only by BDOS
   calls that transfer through the default DMA address. Moving the DMA address
   first keeps the command tail and the default FCBs at `$005C` intact for the
   program's whole run, with no copy.
2. **Read the top of memory** from `$0006`.
3. **Check memory.** Compare the top of memory with `REQUIRED_TOP`. If it is too
   low, print a message with BDOS function 9 and return. The same `.COM` file
   runs on machines whose transient program areas differ by many kilobytes, and
   a program whose `bss` or stack overlapped the system would corrupt it. At
   this point the CCP's stack is still in use: it has seven free levels, enough
   for one BDOS call, which switches to the BDOS's own stack.
4. **Save the entry stack pointer** if the profile keeps the CCP resident
   (Section 9.3).
5. **Set the stack pointer** to the top of memory, or below the CCP if it is
   kept.
6. **Zero `bss`,** using `BSS_START` and `BSS_SIZE`. Memory beyond the file
   holds whatever the previous program left.
7. **Copy initialised data** if the profile supports re-running (Section 9.6).
8. **Call `main`** through the `MAIN` pseudo-ordinal.
9. **Exit** (Section 9.3).

The first byte of the image must not be `$C9` (`RET`). CP/M 3's loader treats a
`.COM` file whose first byte is `$C9` as carrying a 256-byte RSX header.

### 9.3 Exit

By default, startup gives the program the CCP's memory and exits with a warm
boot. `RST 0` is the one-byte form of `JP $0000`. Under CP/M 2.2 a warm boot
reloads the CCP and BDOS from the system tracks, about 5.5K, which takes
roughly 1 to 3 seconds on 8-inch floppies **[estimate]**; under CP/M 3 and on
most hard-disk systems it is fast. A warm boot also resets the DMA address and
the disk login.

A profile option keeps the CCP resident: startup saves the entry stack pointer,
places the program's stack below the CCP, and returns to the CCP through the
saved pointer. This costs about 2K of memory and avoids the warm boot.

### 9.4 Command line

The command tail is at `$0080`: a length byte followed by the text. The default
FCB at `$005C` is 36 bytes and runs to `$007F`, and the second default FCB at
`$006C` overlaps bytes 16 to 35 of the first. The CP/M 2.2 CCP converts the
whole command line to upper case, so Baton's argument interface can't promise
to preserve case.

CP/M 3 also uses `$0050` (the drive the program was loaded from) and `$0051` to
`$0056` (password pointers and lengths). Startup and the runtime must not treat
`$0040` to `$005B` as free memory; `$0040` to `$004F` is also conventionally
BIOS scratch.

### 9.5 Fit checks

The layout tool checks against the target profile:

| Check | Kind | Reason |
| --- | --- | --- |
| Stored image below the CCP base (CP/M 2.2) | Error | The 2.2 CCP loads the file record by record and stops with `BAD LOAD` if the next record would overwrite the CCP itself. A 62K system with the CCP at `$DC00` can load at most 56,064 bytes. |
| Stored image below the nominal top of memory (CP/M 3) | Error | CP/M 3 loads through the BDOS and has no resident CCP in the way. |
| `REQUIRED_TOP` below the nominal top of memory | Warning | The profile's figure is only nominal; startup decides on the real machine. |
| Margin under a debugger | Report | Under `DDT`, `SID` or `ZSID` the top of memory is about 5K lower. A program that fits with less margin than that can't be debugged. |

A program whose stored image is too large for the real machine is stopped by
the CCP with `BAD LOAD` before Baton's startup runs, so no Baton message
appears. The documentation must say so.

### 9.6 Re-running without reloading

Z-System's `GO` command and similar facilities re-enter a program at `$0100`
without reloading it from disk. `bss` is correct on re-entry, because startup
clears it. Initialised `data` blobs are not: they keep the values the previous
run left.

A profile option, **re-runnable**, handles this with the same mechanism as ROM
targets (Section 13.1). The layout tool stores a read-only copy of the initial
data in the image, and startup copies it into place before calling `main`. This
costs the size of the initialised data a second time. Without the option, the
documentation must state that re-entry without reloading is unsupported.

### 9.7 Page zero, restart vectors and interrupts

CP/M 2.2 itself uses only `$0000` to `$0007`, the default FCBs and the DMA
buffer. Other users of low memory:

- `DDT`, `SID` and `ZSID` use `RST 38h` for breakpoints;
- BIOSes running in interrupt mode 1, including Amstrad's CP/M and many
  home-built systems, use `RST 38h` as their interrupt entry; and
- the non-maskable interrupt vector at `$0066` falls inside the first default
  FCB, which matters only on hardware that generates NMIs.

A compact calling convention through `RST` (a one-byte call to a common helper)
would save two bytes per call. On CP/M it is safe only for vectors the target
profile declares free, and never for `RST 38h`. Startup installs such vectors,
and the runtime directory marks each installed helper as a root.

A Baton program must not change the interrupt mode or the `I` register, or
install anything at `$0038`, unless the target profile says the BIOS doesn't
depend on them. Future interrupt routines depend on the same profile statement.

### 9.8 Other CP/M environments

- **CP/M 3 (banked).** The transient program area can reach about 60K, the CCP
  is not resident during the run, and the top of memory is the resident BDOS or
  lowest RSX. The fit checks use the CP/M 3 rule of Section 9.5.
- **Z-System (ZCPR3).** The environment descriptor and resident command and
  flow-control packages in high memory reduce the transient program area by
  about 2K to 8K. The word at `$0006` still gives the correct top. `GO`
  re-entry is covered by Section 9.6.

## 10. Changes to the compiler

### 10.1 What the compiler stops doing

- It no longer knows any final address.
- It no longer keeps a program-wide table of unresolved call sites.
- It no longer emits `PATCH` records or a placed image.

### 10.2 What the compiler starts doing

- It assigns an ordinal to each blob and writes a blob record at the end of
  each routine and declaration.
- It emits every absolute address operand as a placeholder (zero bytes) with an
  entry in the pending reference list.
- It resolves branches within the routine itself, and records every relative
  branch in the routine, backward as well as forward, for shrinking.
- It flags the entry routine for the `MAIN` pseudo-ordinal.

### 10.3 Shorter forward branches

A one-pass streaming compiler must emit a forward branch before it knows the
distance, so Nucleus uses a 3-byte `JP` where a 2-byte `JR` would often do.
With a bounded routine buffer, the compiler can recover most of that byte.

**Method.**

1. Generate the routine into the buffer. Emit every forward local branch as
   `JP`. Record **every** relative and local branch in the routine: its site
   offset, target label, and whether it is shrinkable. Backward `JR` and `DJNZ`
   are recorded too, although they are already short.
2. When the routine ends, compute the fixed point on offsets alone, without
   moving any bytes. Start with every forward `JP` long. In each pass, mark as
   short every `JP` whose distance would fit a `JR` given the current choices.
   Making a branch short only shortens distances, so a branch that fits stays
   fitting, and the passes end when one changes nothing. Two or three passes
   are typical.
3. Write the routine to the byte spool in one compaction pass, dropping one byte
   from every shortened branch and **re-encoding every relative branch**,
   including the backward `JR` and `DJNZ` instructions, from the final offsets.
   A backward `DJNZ` whose range contains a shortened `JP` would otherwise be
   off by one.
4. Adjust the offsets of pending references and self-reference addends to
   match.

Only forward `JP` instructions to local labels may shrink. A conditional
`JP` shrinks only if its condition has a `JR` form (`Z`, `NZ`, `C`, `NC`);
`JP PE`, `JP PO`, `JP M` and `JP P` stay long. Entries the compiler flags as
fixed-size, such as a table of `JP` instructions indexed by multiplication,
never shrink.

Doing the fixed point on offsets and compacting once avoids moving the buffer
contents for each shortened branch. Moving them each time with `LDIR` would
cost on the order of a quarter of a second per large routine **[estimate]**.

**Cost [estimate].** A routine buffer of 2K to 4K, about 5 bytes per recorded
branch, and 300 to 500 bytes of compiler code.

**Fallback.** A routine too large for the buffer is written out as it is
generated, with every forward branch left as `JP`. Correctness never depends on
the buffer.

**Speed.** `JR` is one byte shorter than `JP`. Taken, it costs 12 T-states
against `JP`'s 10; not taken, it costs 7 against 10. The shrink is a size
optimisation and can be turned off for speed-critical code.

### 10.4 Unused routines in the user's source

The layout tool removes them. The compiler may still warn about a routine that
is never referenced, since it knows this at the end of input, but the warning
is advisory: the cost has already been avoided.

### 10.5 Failure while writing spools

A BDOS write error during compilation means the disk or its directory is full.
The compiler reports which, stops, closes and deletes the partial spools, and
leaves any previous output untouched. A spool that was never closed may not
appear in the directory at all, and its space is recovered at the next disk
login. Leftover spools can always be removed with `ERA *.$*` (Section 6.3).

## 11. Debugging and trap locations

Nucleus builds source maps from trace events keyed by final address. Under late
placement the compiler doesn't know final addresses, so it writes the optional
**line spool**: records of (ordinal, offset, source part, source offset) at
each statement boundary. The layout tool's map turns (ordinal, offset) into an
address, so a host tool can join the two into a source map, or a CP/M tool can
translate an address back to a source position.

Trap reporting has two options:

- **Inline source positions,** as in Nucleus: each trap site loads its source
  offset and a trap code before jumping to the trap reporter. About 8 bytes per
  site, and the report is readable with no other files.
- **Map-resolved addresses:** each trap site is `CALL trap` followed by a code
  byte, about 4 bytes. The trap reporter prints the return address, and the map
  and line spool translate it to a source position.

A checked program has many trap sites, so the second option saves several
kilobytes **[estimate]**, at the cost of needing the map to read a trap report.
This is an open question (Section 14).

## 12. Versions and compatibility

Three things must agree: the compiler, the runtime spool set and the layout
tool.

- **Runtime ordinals are append-only.** A new runtime version may add helpers at
  new ordinals but never renumbers or removes one. A program compiled against
  helper-table version *n* therefore lays out against any runtime with version
  *n* or later and the same runtime identity.
- **The layout tool checks** the program directory's format version, the
  runtime directory's format version, runtime identity, helper-table version
  and target profile, and stops on any mismatch it can't accept.

| Combination | Accepted |
| --- | --- |
| Program compiled against an older helper table, newer runtime | Yes |
| Program compiled against a newer helper table, older runtime | No |
| Different runtime identity or target profile | No |
| Directory format the layout tool doesn't know | No |

## 13. Other targets

### 13.1 ROM targets

A ROM image needs initialised data at two addresses: where it is stored in ROM
and where it lives in RAM. ROM targets use per-kind byte spools, so the layout
tool can place code and read-only data in ROM and initialised data both in ROM
(as a load copy) and in RAM. References to a `data` blob resolve to its RAM
address. Startup copies the load copy to RAM using the `DATA_COPY`,
`DATA_START` and `DATA_SIZE` pseudo-ordinals before calling `main`. The CP/M
re-runnable option (Section 9.6) uses the same mechanism.

### 13.2 Banked targets

Nucleus assigns banks by source part, and its compiler enforces the cross-bank
rules: for example, that aggregate constants are local to their bank. If the
layout tool chose banks instead, nothing would enforce those rules. A constant
placed in one bank and read from code in another would read the wrong memory
without any error. Calls reached by `JP` or through a routine value would cross
banks with no bank switch.

Baton therefore keeps Nucleus's model for banked targets: **the compiler
assigns each blob to a bank from its source part,** enforces the cross-bank
rules as Nucleus does, and emits the near or far call form itself. The blob
record gains a bank field, and the layout tool places each blob within its
assigned bank. Tree shaking works within each bank.

Layout-time bank packing, with call veneers generated by the layout tool, is a
possible later extension. It would need to solve the problems above and these:

- on TECM8, common memory is RAM, so veneers must be copied there at startup at
  12 to 16 bytes each **[estimate]**;
- the bank-select register is write-only, so a veneer needs a shadow copy of
  the current bank to restore the caller's bank; and
- packing blobs into banks must happen before address assignment and compete
  with the common-memory budget.

Banked layout is deferred until the flat CP/M target works.

### 13.3 Overlays

Because the layout tool knows the complete call graph, it could split a program
larger than the transient program area into a resident root and overlays
loaded on demand, in the manner of Digital Research's `LINK`. Each overlay
would be a separately placed image, cross-overlay calls would go through a
resident loader stub, and loading would use BDOS random reads. This is not part
of the first design, but nothing in the spool format prevents it.

### 13.4 Libraries

"One program per run" means libraries are compiled from source as part of every
build. On a 4 MHz Z80 reading floppies, that is the main cost of the design and
should be measured.

Precompiled libraries can be added later without changing the layout tool's
nature. Each would need its own ordinal range and a compiler-readable
interface file giving names, signatures and ordinals. Names would then return,
but only in the compiler, which reads interfaces; the layout tool would still
work by ordinal and read several spool sets. This is the same split as
Microsoft's `M80` and `L80`, with the names on the compiler's side.

Incremental builds are not offered. Any edit can renumber ordinals, so a
program is always compiled and laid out as a whole.

## 14. Open questions

1. **Reference density and blob count.** Measure on the largest available
   Nucleus programs, then fix the directory encoding and confirm the disk and
   memory estimates of Sections 7.6 and 8.1.
2. **Table size limits.** If measurements show the layout tool's tables
   overflow for realistic programs, options include 1-byte edges for targets
   within a nearby ordinal window, storing edges only for blobs not yet marked,
   or letting the compiler write a deduplicated edge list.
3. **Trap reporting.** Inline source positions (about 8 bytes per site) or
   map-resolved addresses (about 4 bytes per site)?
4. **String literal deduplication.** A compiler-side cache of recent short
   literals, about 1K, would catch most duplicates. The layout tool can't
   compare contents without reading the byte spool in Phase A.
5. **Routine buffer size** for branch shrinking, and the capacity limit on
   references per routine.
6. **Root marking in source.** The syntax for interrupt routines and other
   blobs reached only by fixed address.
7. **Target profile files.** Where the CP/M profile lives (CCP base, nominal
   top of memory, CP/M version, free restart vectors, keep-CCP and re-runnable
   options) and how it is versioned with the runtime spool set.
8. **Floppy capacity.** On a 90K 5.25-inch disk the source, spools and output
   don't fit together, and even on an 8-inch single-density disk (about 243K)
   a large program needs a second drive. Is two drives the stated minimum for
   large programs?

## 15. Changes in revision 2

A review of revision 1 from a CP/M and Z80 toolchain perspective found these
problems, now corrected:

- **Startup destroyed the command tail.** Revision 1 copied the tail into `bss`,
  then zeroed `bss`. Startup now moves the DMA address first, so no copy is
  needed (Section 9.2).
- **The edge-overflow fallback was slow, and its stated bound was backwards.**
  Declaration before use makes most references point backwards, so each rescan
  advanced one call level. Overflow is now a capacity error (Section 8.1).
- **Branch shrinking broke already-encoded relative branches.** A backward
  `DJNZ` spanning a shortened `JP` was left off by one. All relative branches
  are now recorded and re-encoded after the fixed point (Section 10.3).
- **Alignment inside code blobs** conflicted with shrinking. Aligned tables are
  now separate blobs (Section 4.1).
- **The reference encoding had no spare bits** and limited ordinals to 14 bits
  and addends to a signed range. The form moved into the control byte, ordinals
  are a full 16 bits, and addends wrap modulo 65,536 (Section 7.4).
- **Layout-time bank assignment** would have removed the compiler's enforcement
  of cross-bank rules. Banked targets keep compiler-assigned banks
  (Section 13.2).
- **The directory spool estimate omitted blob records** and underestimated
  reference density. Records are now about 4 bytes, and the estimate is revised
  upwards (Section 7.6).
- **Four byte spools** multiplied the directory reads. CP/M targets now use one
  byte spool (Section 6.1).
- **Atomic output replacement** isn't possible on CP/M. The replacement
  sequence and its failure window are now stated (Section 8.7).
- **The CP/M details were incomplete.** Additions: what the word at `$0006`
  really points to, CP/M 3's load rule, page-zero use, the `$C9` first byte,
  re-entry through `GO`, debugger margins, upper-case command lines, interrupt
  mode and restart vector conflicts (Section 9).
- **New sections:** where `startup` comes from and how it finds `main`
  (Sections 4.3 and 8.4), debugging and trap locations (Section 11), versions
  (Section 12), libraries and incremental builds (Section 13.4), and failure
  while writing spools (Section 10.5).
