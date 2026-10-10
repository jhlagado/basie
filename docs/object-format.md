# Basie Object Format 1.0

- Status: draft specification, revision 3 (after two adversarial reviews)
- Date: 2026-10-03
- Related: [build pipeline](build-pipeline.md) (overview and rationale),
  [linker](linker.md), [toolchain](toolchain.md), [CP/M target](cpm-target.md),
  reviews [1](archive/reviews/2026-10-03-linker-spec-review.md) and
  [2](archive/reviews/2026-10-03-linker-spec-review-2.md)

## 1. Scope

This document defines, byte for byte, the files that carry compiled Basie code
between the compiler and the linker:

- the **program object**, written by the compiler for one compilation, made of
  a directory stream and a byte stream;
- the **blob library**, which carries the prebuilt runtime and target profile;
- the **line stream** and **name stream**, which carry debugging information;
  and
- the **line table**, which the linker writes for trap lookup.

It does not define source syntax, code generation or the linker's algorithm,
except where a field's meaning depends on them.

## 2. Conventions

- All multi-byte integers are little-endian.
- `u8`, `u16` and `u32` are unsigned integers of 8, 16 and 32 bits.
- Bit 0 is the least significant bit.
- A **record** is a self-delimiting sequence of fields. Records are not aligned
  to anything and may cross 128-byte CP/M record boundaries.
- "Must" states a requirement on a producer. A consumer rejects a file that
  breaks one, with the diagnostic the linker document names.
- **CRC** means CRC-16/CCITT-FALSE: polynomial `$1021`, initial value `$FFFF`,
  no reflection, final XOR `$0000`. The check value for ASCII `123456789` is
  `$29B1`.
- On CP/M, a file whose length is not a multiple of 128 is padded after its
  last meaningful byte with `$1A`. Every file in this document either records
  its own length or ends in a recognisable trailer, so a consumer never needs to
  interpret padding.

## 3. Concepts

### 3.1 Blobs

A **blob** is the unit of placement and removal: a contiguous run of bytes the
linker places whole or drops whole.

| Kind code | Kind | Stored bytes | Meaning |
| ---: | --- | --- | --- |
| 0 | `code` | yes | One routine, with the jump tables and literals it owns |
| 1 | `rodata` | yes | One top-level read-only constant, or an aligned table |
| 2 | `data` | yes | One initialised, writable top-level variable |
| 3 | `bss` | no | One zero-initialised top-level variable, pool or buffer |
| 4 | `startup` | yes | The program's first code; exactly one, in the blob library only |
| 5 | — | — | Reserved |
| 6 | control | — | Not a blob; a control record (Section 6) |
| 7 | — | — | Never begins a record; `$FF` marks the trailer |

A blob obeys these rules:

1. **No relative transfer leaves a blob.** `JR`, `DJNZ` and any other
   relative displacement target a byte inside the same blob.
2. **No fall-through between blobs.** A blob that contains code never lets
   execution run off its end.
3. **No adjacency assumptions.** No code relies on two blobs being next to each
   other or in a particular order.
4. **Every absolute address is a reference.** Any byte whose final value
   depends on where any blob is placed, including the blob itself, is covered by
   a reference (Section 5). Its placeholder bytes are zero.
5. **Alignment belongs to the whole blob.** A `code` or `startup` blob has
   alignment 1. Anything that needs alignment is its own `rodata`, `data` or
   `bss` blob.
6. **A `bss` blob has no references.** It has no bytes to patch.

**Literals belong to their routine.** A string or aggregate literal that
appears inside a routine is stored in that routine's `code` blob, normally
after its code, and reached by a self-reference. A literal's liveness is its
routine's, so a separate blob would gain nothing. Only top-level constants are
`rodata` blobs. Identical literals in different routines are not merged.

### 3.2 Ordinals

Every blob, alias and pseudo-object has a 16-bit **ordinal**. Ordinals replace
names in linking: the linker never compares strings.

| Range | Owner | Use |
| --- | --- | --- |
| `$0000` | — | Invalid; never defined, never referenced |
| `$0001`–`$03FF` | blob library | Runtime blobs and aliases, numbered by the runtime's published helper table |
| `$0400`–`$FFDF` | compiler | Program blobs and aliases |
| `$FFE0`–`$FFFF` | linker | Pseudo-objects (Section 3.4) |

Within each owner's range an ordinal is defined at most once. Ordinals need not
be dense, but the linker's memory grows with the highest ordinal in each range,
so producers assign them densely from the bottom of their range.

The pseudo-objects sit at the top of the space, where a compiler counting up
from `$0400` never reaches them.

### 3.3 Aliases

An **alias** is an ordinal that denotes a fixed offset inside a blob:
`addr(alias) = addr(base) + offset`. Aliases give a blob more than one entry
point, which hand-written runtime code needs: a helper with two entries, one
falling through into the other, must be one blob.

A reference to an alias marks the alias's base blob live. For range checking,
an alias's size is its base's size minus its offset. A `SIZE16` reference to an
alias is invalid.

### 3.4 Pseudo-objects

The linker defines these ordinals after placement. Each has an address and a
size. A reference to a pseudo-object marks nothing live, except `MAIN`.

| Ordinal | Name | Address | Size |
| --- | --- | --- | --- |
| `$FFE0` | `MAIN` | The entry routine's address; marks that routine live | The entry routine's size |
| `$FFE1` | `IMAGE` | First address of the stored image | Length of the stored image |
| `$FFE2` | `BSS` | First `bss` address | Total `bss` length, including padding; may be 0 |
| `$FFE3` | `FREE` | First address after `bss` | 0 |
| `$FFE4` | `REQUIRED` | `FREE` plus the stack reserve: the lowest acceptable top of memory | The stack reserve |
| `$FFE5` | `DATA` | Run address of the first separately placed `data` blob | Total length of the `DATA` section; may be 0 |
| `$FFE6` | `DATACOPY` | Address of the stored copy of `DATA`; equal to `DATA` if none | Length of the copy; 0 if none |
| `$FFE7` | `OPTIONS` | A 16-bit flag word, used as a value rather than an address (Section 3.5) | 0 |
| `$FFE8` | `FILES` | First address of the file table the linker allocates in `BSS` (Section 3.6) | Its length: the file count times the profile's file-entry size |
| `$FFE9` | `FILECOUNT` | The number of file-table entries, used as a value | 0 |
| `$FFEA` | `LINES` | The position table (Section 11.1), after the stored image; 0 without option `D` | Its length; 0 without option `D` |
| `$FFEB`–`$FFFF` | — | Reserved; a reference is an error | — |

When there are no `bss` blobs, `BSS` has the address of `FREE` and size 0.
Likewise, when `DATA` is empty, `DATA` and `DATACOPY` have size 0. Code that
copies or clears using these sizes must handle 0, because `LDIR` with
`BC = 0` moves 65,536 bytes.

### 3.5 The `OPTIONS` word

`OPTIONS` lets prebuilt runtime code learn the link-time options. An `ABS16`
reference to it yields the flag word, for example as `LD HL,OPTIONS`.

| Bit | Meaning when set |
| ---: | --- |
| 0 | Keep the CCP resident and return to it (CP/M 2.2) |
| 1 | Re-runnable: restore `DATA` from `DATACOPY` at startup |
| 2 | A line table was written for this image |
| 3–15 | Zero |

### 3.6 The file table

The runtime's file services keep one entry per file that can be open at once.
The number of entries is chosen at link time (the linker's `F=n` option,
default 4, at most 255), so the table can't be a fixed `bss` blob in the
library. Instead, the linker allocates it as the last part of `BSS`, `n` times
the profile block's **file-entry size** long, and the runtime reaches it through
the `FILES` and `FILECOUNT` pseudo-objects. Startup's clearing of `BSS` clears
it. A program that calls no file service references neither pseudo-object, and
the linker then allocates nothing.

## 4. Program object

One compilation produces one program object: a **directory stream** and a
**byte stream**, written in parallel, plus the optional line and name streams.

### 4.1 Compilation stamp

The compiler chooses a 16-bit **compilation stamp** for each compilation and
writes it into the header of every stream it produces. The linker refuses
streams whose stamps differ, so a stale byte, line or name stream left from an
earlier compilation can never be combined with a newer directory.

The stamp must differ from that of any stream an earlier compilation could
have left behind, and it must be known when the first header is written. Before
deleting an existing program directory, the compiler reads its stamp and uses
that value plus one, skipping zero. Only when no earlier directory exists does
it derive a stamp from the CRC of the first source record combined with the
Z80's `R` register. CP/M 2.2 has no clock, and source content alone repeats
whenever a program is rebuilt unchanged, which is exactly when stale files are
likeliest.

### 4.2 Directory stream

```text
directory-stream = program-header record* trailer
record           = blob-record | control-record
```

#### Program header (20 bytes)

| Offset | Field | Type | Meaning |
| ---: | --- | --- | --- |
| 0 | magic | 4 bytes | ASCII `BSIP` |
| 4 | major version | `u8` | 1 |
| 5 | minor version | `u8` | 0 |
| 6 | compilation stamp | `u16` | Section 4.1 |
| 8 | runtime identity | `u16` | The runtime the compiler was built for |
| 10 | helper-table version | `u16` | The version of the helper table compiled into the compiler |
| 12 | helper-table key | `u16` | The interface key of that version (Section 10) |
| 14 | profile identity | `u16` | The profile the program was compiled for |
| 16 | ordinal base | `u16` | `$0400` in 1.0; reserved so a precompiled library's ordinals can later be relocated by addition |
| 18 | flags | `u8` | Bit 0: a line stream was written. Bit 1: a name stream was written. Bits 2–7: zero |
| 19 | reserved | `u8` | Zero |

Every header field is known before compilation starts. Facts learned only at
the end of input go in the `LIMITS` control record (Section 6).

#### Blob record

| Field | Type | Meaning |
| --- | --- | --- |
| header | `u8` | Bits 0–2: kind 0–4. Bit 3: an explicit ordinal follows. Bit 4: root. Bits 5–7: alignment code |
| ordinal | `u16`, optional | Present when bit 3 is set |
| size | `u16` | Stored length, or reserved length for `bss`; 1 to 65,535 |
| reference count | `u8` | 0 to 254; or 255 followed by a `u16` count, which must be 255 or more |
| references | — | The blob's references, in strictly increasing offset order (Section 5) |

**Implicit ordinals.** A record without an explicit ordinal takes the previous
blob record's ordinal plus one. The first blob record of a program directory
takes the ordinal base, `$0400`. Control records do not affect the sequence.

The compiler therefore tracks two values: the **next free ordinal**, which it
assigns as it meets declarations, and the **last written ordinal**, from which
it decides whether a record needs an explicit ordinal. A routine whose ordinal
was assigned at a forward declaration is written later with an explicit
ordinal, and so, usually, is the record after it.

**Alignment code.** Values 0 to 6 mean alignment to 2 raised to that power: 1,
2, 4 ... 64 bytes. Value 7 means 256 bytes. A `code` or `startup` blob must use
0.

**Root flag.** A root blob is live whatever references it. Basie 1.0 defines no
source feature that makes a program blob a root, so a 1.0 program directory has
none; the flag exists for future interrupt and exported routines.

**Size.** A blob of size 0 is invalid. Every routine has at least a return
instruction, and Basie has no empty aggregates.

### 4.3 Byte stream

```text
byte-stream = byte-header blob-bytes*
```

| Field | Type | Meaning |
| --- | --- | --- |
| magic | 4 bytes | ASCII `BSIB` |
| major, minor version | `u8`, `u8` | 1, 0 |
| compilation stamp | `u16` | Must equal the directory's |

After the 8-byte header come the stored bytes of every `code`, `rodata` and
`data` blob, in directory order, with no framing. The directory trailer records
their total length. Placeholder bytes covered by references must be zero.

### 4.4 Directory trailer (12 bytes)

| Field | Type | Meaning |
| --- | --- | --- |
| marker | `u8` | `$FF` |
| blob count | `u16` | Number of blob records, excluding control records |
| byte stream length | `u32` | Exact number of blob bytes after the byte-stream header |
| highest ordinal | `u16` | Highest ordinal defined in this directory |
| reserved | `u8` | Zero |
| CRC | `u16` | CRC over every directory byte from the magic up to, but not including, this field |

A directory without a valid trailer is rejected, so the linker never uses the
output of an interrupted compilation.

## 5. References

### 5.1 Meaning

A reference says: at offset *o* within this blob, write a value computed from
target *t* and addend *a*.

| Form code | Form | Bytes written | Value |
| ---: | --- | ---: | --- |
| 0 | `ABS16` | 2 | `(addr(t) + a) mod 65536`, little-endian |
| 1 | `LO8` | 1 | Low byte of `(addr(t) + a) mod 65536` |
| 2 | `HI8` | 1 | High byte of `(addr(t) + a) mod 65536` |
| 3 | `SIZE16` | 2 | `(size(t) + a) mod 65536`, little-endian |
| 4 | `BANK8` | 1 | Bank number of *t*; reserved; invalid under every 1.0 profile |
| 5–7 | — | — | Reserved |

The addend is a 16-bit value added modulo 65,536; a negative offset is written
as its two's-complement value.

The target may be any blob or alias, including the referring blob itself, or a
pseudo-object. A `SIZE16` target may be a blob or a pseudo-object but not an
alias.

**Self-references.** A blob that needs an absolute address inside itself, such
as an absolute jump to its own label, a jump-table entry, or the address of a
literal it owns, references its own ordinal with the offset as the addend.

**Range rule.** For `ABS16`, `LO8` and `HI8`, let `v = addr(t) + a`, computed
without the modulo, treating the addend as signed (−32,768 to 32,767). Then:

- `addr(t) ≤ v ≤ addr(t) + size(t)` must hold, so a reference may point at any
  byte of its target or one byte past its end, as end pointers do; and
- `v` must lie in 0 to 65,535.

The rule is relative to the target, not to the image, so references to RAM
below a ROM image are valid. Two kinds of reference are exempt from the first
condition: references to `OPTIONS`, whose value is not an address; and
references to `IMAGE`, `BSS`, `FREE`, `REQUIRED`, `DATA` and `DATACOPY`, whose
sizes may be 0 but which runtime code uses as region boundaries. For those, only
the second condition applies.

### 5.2 Encoding

Each reference entry is:

| Field | Type | Meaning |
| --- | --- | --- |
| control | `u8` | Bits 0–5: offset delta 0–62, or 63 to escape. Bit 6: an addend follows. Bit 7: a form byte follows |
| absolute offset | `u16`, optional | Present when the delta field is 63: the entry's offset from the start of the blob |
| form | `u8`, optional | Present when bit 7 is set: the form code 1–7. When absent, the form is `ABS16` |
| target | `u16` | Target ordinal |
| addend | `u16`, optional | Present when bit 6 is set; otherwise 0 |

For a blob's first entry, the delta is the offset from the start of the blob.
For each later entry, the delta is the distance from the previous entry's
offset and must be at least 1. The escaped field is always an absolute offset
from the start of the blob, and must be greater than the previous entry's
offset. Offsets are therefore strictly increasing. A form byte of 0 is
invalid, since `ABS16` is expressed by omitting it.

A reference's bytes must lie wholly inside the blob, and two references' bytes
must not overlap: after an `ABS16` or `SIZE16` at offset *o*, the next entry is
at *o* + 2 or later.

**Cost.** An `ABS16` with no addend within 62 bytes of the previous reference,
the commonest case, takes 3 bytes. Another form adds 1 byte, an addend 2, and
the escape 2.

**Restriction on library references.** A reference in the library may target
only library ordinals no higher than the header's highest ordinal, and
pseudo-objects. A library never references a program ordinal.

## 6. Control records

A control record has header `$06` combined with a subtype in bits 3 to 7:
`header = $06 | (subtype << 3)`.

| Subtype | Name | Payload | Where allowed |
| ---: | --- | --- | --- |
| 0 | `ALIAS` | alias `u16`, base `u16`, offset `u16` | Program directory, library |
| 1 | `ENTRY` | ordinal `u16` | Program directory, exactly once |
| 2 | `BANK` | bank `u8` | Banked profiles only; invalid in 1.0 |
| 3 | `LIMITS` | stack reserve `u16`, largest frame `u16`, flags `u8` | Program directory, exactly once, after the last blob record |
| 4–31 | — | — | Reserved |

**`ALIAS`.** Defines `alias` as `base + offset`. The alias lies in the same
owner's range as the directory. The base is a blob defined in the same
directory, before or after the alias. The offset is less than the base's size.
An alias's base is never another alias.

**`ENTRY`.** Names the program's entry routine. The ordinal is a `code` blob in
the program directory.

**`LIMITS`.** Facts the compiler knows only at the end of input:

- **stack reserve:** `need(main)` plus the profile's guard band: the most stack
  the program can use outside cycles of calls, computed by the compiler in its
  single pass ([memory safety](memory-safety.md), Section 7). Cycles are guarded
  by activation-capacity checks ([CP/M target](cpm-target.md), Section 4.1);
- **largest frame:** the largest single activation frame, for the map; and
- **flags:** bit 0 is set when any routine calls itself or calls a routine that
  is declared forward and not yet defined at the call, which are the only ways a
  single-pass compiler can see recursion arise.

## 7. Blob library

A blob library carries the prebuilt runtime for one target profile in one file:
a header, a profile block, a directory section, a byte section, a key table and
an optional name section.

### 7.1 Library header (40 bytes)

| Offset | Field | Type | Meaning |
| ---: | --- | --- | --- |
| 0 | magic | 4 bytes | ASCII `BSIR` |
| 4 | major version | `u8` | 1 |
| 5 | minor version | `u8` | 0 |
| 6 | runtime identity | `u16` | Identity of this runtime |
| 8 | helper-table version | `u16` | Version of the helper table this library provides |
| 10 | profile identity | `u16` | The target profile this library implements |
| 12 | directory offset | `u32` | Byte offset of the directory section |
| 16 | byte section offset | `u32` | Byte offset of the byte section |
| 20 | byte section length | `u32` | Length of the byte section |
| 24 | name section offset | `u32` | Byte offset of the name section, or 0 |
| 28 | file length | `u32` | Length of the file up to and including the whole-file CRC |
| 32 | key table offset | `u32` | Byte offset of the helper key table (Section 10) |
| 36 | highest ordinal | `u16` | Highest ordinal the library defines |
| 38 | reserved | `u16` | Zero |

The directory, byte section, name section and key table offsets are multiples
of 128, so a CP/M reader can position to each with a random read. Gaps are
filled with zeros.

### 7.2 Profile block

The profile block follows the header directly.

| Field | Type | Meaning |
| --- | --- | --- |
| length | `u16` | Length of the rest of the block |
| target class | `u8` | 1: CP/M 2.2. 2: CP/M 3. 3: flat ROM. 4: banked ROM (reserved) |
| output kinds | `u8` | Bit 0: `.COM`. Bit 1: `.BIN`. Bit 2: Intel HEX |
| image base | `u16` | Address of the first stored byte: `$0100` on CP/M |
| image limit | `u16` | First address the stored image may not reach: the CCP base on CP/M 2.2, the nominal top of memory on CP/M 3, the end of ROM on a ROM target |
| nominal top | `u16` | Typical top of memory, for warnings |
| CCP size | `u16` | CP/M 2.2: bytes the CCP occupies below the BDOS base, normally `$0800`. Otherwise 0 |
| RAM base | `u16` | ROM targets: first RAM address. CP/M: 0 |
| RAM limit | `u16` | ROM targets: first address after RAM. CP/M: 0 |
| guard band | `u16` | Stack bytes reserved beyond `need(main)` and in every activation-capacity check, for BDOS entry and interrupt pushes |
| option support | `u8` | Bit 0: keep-CCP supported. Bit 1: re-runnable supported |
| free restart vectors | `u8` | Bit *n* set: `RST n*8` is free for runtime use. Bits 0 and 7 must be clear on CP/M |
| debugger margin | `u16` | Bytes a resident debugger typically takes, for reports |
| file-entry size | `u16` | Bytes per file-table entry (Section 3.6); 0 if the library has no file services |
| further fields | — | Added in later minor versions; a reader skips them using the length |

### 7.3 Directory section

The directory section uses the record grammar of a program directory
(Sections 4.2, 5 and 6), with these differences:

- it has no header of its own; the library header serves instead;
- implicit ordinals start at `$0001`, and ordinals lie in `$0001`–`$03FF`;
- exactly one blob has kind `startup`; it is a root, and it is the first record
  of the directory section;
- the `startup` blob references `MAIN`;
- `ENTRY` and `LIMITS` records are not allowed; and
- `data` blobs are allowed, for runtime state. They are placed and, when
  re-runnable, restored like the program's.

Roots in a library mark code the system reaches without a call from the
program, such as restart-vector handlers that startup installs.

The section ends with a directory trailer (Section 4.4). Its CRC covers the
section from its first record byte. Its byte-stream length must equal the
header's byte section length, and its highest ordinal the header's.

### 7.4 Byte section

The stored bytes of the library's `code`, `rodata`, `data` and `startup` blobs,
in directory order, with no header.

### 7.5 Name section

Optional; the same format as a name stream (Section 9), with stamp 0.

### 7.6 Whole-file CRC

The 2 bytes ending at the file length (Section 7.1) are a CRC over every
preceding byte of the file. The linker checks it only when asked to verify a
library, because that reads the whole file again.

## 8. Line stream

Optional; written by default. It maps code positions to source positions.

```text
line-stream = line-header part-record* blob-lines* line-trailer
```

| Record | Layout |
| --- | --- |
| Line header | magic `BSIL` (4 bytes), major `u8` = 2, minor `u8` = 0, compilation stamp `u16` |
| Part record | tag `$01`, part `u8` (0–254), name length `u8`, name bytes |
| Blob lines | tag `$02`, ordinal `u16`, entry count `u16`, entries |
| Line trailer | tag `$FF`, CRC `u16` over every preceding byte |

Part records name each source part with the name the compiler opened, such as
`B:MAIN.BSI`. A part record may come anywhere in the stream, but before the
first entry that names its part. A single-pass compiler discovers parts only as
it reads their `include` lines, and fixes a part's number once that part's own
includes are loaded, before it compiles any of the part's declarations; it
writes the part record then. Each part is named once. Parts are numbered from
0; 255 is reserved.

The compiler writes a blob-lines record for each `code` blob at the same time as
the blob's directory record, so blob-lines records are in directory order.
Every `code` blob has one, and its first entry is at offset 0 and gives the
source position of the routine's header, so a trap in a routine's prologue
reports the routine.

Each entry marks the start of a statement:

| Field | Type | Meaning |
| --- | --- | --- |
| control | `u8` | Bits 0–6: code offset delta 0–126, or 127 to escape. Bit 7: a part number follows |
| absolute offset | `u16`, optional | Present when the delta field is 127 |
| part | `u8`, optional | Present when bit 7 is set; otherwise the previous entry's part |
| line | `u16` | The line of the statement's first token, from 1 |
| column | `u8` | Its column, from 1; 255 for 255 or beyond |

The first entry of every blob-lines record carries a part number. The first
entry's delta is its offset from the blob start; each later entry's delta is
the distance from the previous entry, and may be 0 only when the entry changes
part. The escaped field is an absolute offset from the blob start. A source part
is at most 65,535 bytes long.

## 9. Name stream

Optional. It maps ordinals to source names for maps, symbol files and
diagnostics.

| Record | Layout |
| --- | --- |
| Name header | magic `BSIN` (4 bytes), major `u8` = 1, minor `u8` = 0, compilation stamp `u16` |
| Name record | ordinal `u16`, name length `u8` (1–31), name bytes |
| Name trailer | ordinal `$0000`, CRC `u16` over every preceding byte |

The compiler writes each blob's name record when it writes the blob's
directory record, so name records are in directory order, and an alias's name
record when it writes the `ALIAS` record. Names are the source spelling,
truncated to 31 bytes. Names of generated blobs are invented by the compiler and
are not source identifiers.

## 10. Versions and compatibility

**Format version.** A consumer accepts a file whose major version it implements
and whose minor version is equal to or lower than its own. Reserved values stay
invalid until a version that defines them.

**Helper table.** The runtime's helper table assigns each runtime ordinal to a
helper, with its kind and calling convention. It is published as a generated
source file that is compiled into the compiler, so the compiler knows each
helper's ordinal without reading the library. The table is **append-only**: a
new version may define ordinals in unused slots but never renumbers, removes or
changes an existing one. The `CPM22` runtime's table, with each helper's
size and stack figures, is published as the [helper table](helper-table.md).

**Interface key.** Each version of the helper table has a 16-bit key: the CRC of
a canonical description of every helper defined in that version (ordinal, kind
and calling-convention code). A library carries a **key table** at the key table
offset: a `u16` count followed by the key of every version from 1 up to its own,
in order.

The canonical description for version *v* is 4 bytes per helper defined in
versions 1 to *v*, in increasing ordinal order: the ordinal (`u16`), the kind
(`u8`) and the calling-convention code (`u8`). The key is the CRC-16 of those
bytes (Section 7.6); a version with no helpers has the key `$FFFF`, the CRC of
nothing.

**Compatibility.** The linker accepts a program and a library together only if:

- their runtime identities are equal;
- their profile identities are equal;
- the library's helper-table version is equal to or higher than the program's;
  and
- the library's key for the program's helper-table version equals the
  program's key.

The key catches a library whose version number matches but whose helper table
was changed in violation of the append-only rule. The compiler checks the same
rule against the library's header and key table before it compiles anything, so
an incompatible library is reported at once.

## 11. Line table

The linker writes the line table while it writes the image (linker,
Section 7.7). Its entries are in increasing address order as written.

| Record | Layout |
| --- | --- |
| Header | magic `BSIT` (4 bytes), major `u8` = 2, minor `u8` = 0, part count `u8`, output name length `u8`, output name, library name length `u8`, library name |
| Part names | for each part in order: name length `u8`, name bytes |
| Entries | 6 bytes each, in increasing address order |
| Trailer | marker of six `$FF` bytes, entry count `u16`, image CRC `u16`, CRC `u16` over every preceding byte |

Each entry is: address `u16`, part `u8`, line `u16`, column `u8`.

- Each statement of a live program `code` blob contributes one entry. Its first
  entry is at the blob's start (Section 8).
- Each other live blob in a stored section (runtime blobs, `rodata`, `data` and
  `startup`) contributes one entry at its start address, with part `$FF` and
  the blob's ordinal in the line field and column 0.
- `bss` blobs and the `COPY` section contribute nothing. The table doesn't
  record where a blob ends, so an address past the last stored blob, or in
  `BSS`, is taken for the last entry's; only one below the first entry is
  outside the stored code.

Six `$FF` bytes can never form an entry: that would be a start entry for
ordinal `$FFFF`, which is a reserved pseudo-object, never a blob. They mark the
trailer unambiguously.

Version 2.0 of the line stream and the line table added each statement's
column (design decision D47), so that a trap can name `PART:LINE:COLUMN`; a
routine's first entry is its name's position.

The source position of an address is that of the entry with the greatest
address not above it. Part `$FF` means the address lies in a blob without
source; the ordinal identifies it.

The table's CRC ends it; CP/M stores the file in whole records, and a reader
ignores the padding after the CRC.

The **image CRC** is the CRC of the output file as stored, including whatever
padding the output kind uses, so a tool can check that a line table belongs to
a given program file. It is in the trailer because the linker knows
it only after the image is written.

### 11.1 The position table

Linked with option `D` (toolchain §5.3, design decision D47), the image
carries a position table, so that a trap prints its statement's part, line
and column rather than an address. The linker places it directly after the
stored image, before `BSS`, as part of the image; the `LINES` pseudo-object
gives its address and length (both 0 without `D`). The linker also links the
library's position reporter, the code blob at ordinal `$08F` (`TRAPLN` in
`CPM22`), which nothing refers to; the runtime's trap routine calls it
through the table's first word when `LINES` has a length. `D` needs the line
stream: with option `N`, or with a library without the reporter, the link
fails with `L-OPTION`.

| Field | Type | Meaning |
| --- | --- | --- |
| reporter | `u16` | The position reporter's address |
| parts | `u8` | The number of parts |
| names | | Each part's name, `NAME.TYP`, then a zero byte |
| entries | | The line table's entries (Section 11), in address order |

The entries are encoded against the one before, starting from address 0,
part 0 and line 0. An entry whose part is the one before's, whose address is
1 to 255 above it and whose line is within -128 to 127 of it takes three
bytes: the address's rise, the line's change as a signed byte, and the
column. Any other takes seven: a zero byte, then the address, the part (`$FF`
for a blob without source, as in the line table), the line (the ordinal for
a blob without source) and the column. A seven-byte entry at `$FFFF`, part
`$FF`, ends the table; no address the reporter looks up is above it.

The reporter finds the entry with the greatest address not above the one
asked about, as Section 11 does, and prints `NAME.TYP:line:column`; an
address before the first entry, or in a blob without source, has none, and
the trap prints its address and the lookup command instead.

## 12. Limits

| Item | Limit |
| --- | --- |
| Library ordinals | 1,023 |
| Program ordinals | 64,480 |
| Blob size | 65,535 bytes; in practice the target's memory |
| References per blob | 65,535 |
| Source parts in a line stream | 255 |
| Source part length | 65,535 bytes |
| Name length | 31 bytes |
| Table sizes in the linker | set by memory; [linker](linker.md), Section 2 |

## 13. Worked example

The source:

```basie
var count: u16

forward sub reset()

sub bump()
    count = count + 1
    if count = 100
        reset()
    end
end

sub reset
    count = 0
end
```

The compiler assigns ordinals as it meets declarations: `count` gets `$0400`,
the forward declaration of `reset` gets `$0401`, and `bump` gets `$0402`.

Machine code for `bump`, 17 bytes:

| Offset | Bytes | Instruction |
| ---: | --- | --- |
| 0 | `2A 00 00` | `LD HL,(count)` |
| 3 | `23` | `INC HL` |
| 4 | `22 00 00` | `LD (count),HL` |
| 7 | `11 64 00` | `LD DE,100` |
| 10 | `B7` | `OR A` |
| 11 | `ED 52` | `SBC HL,DE` |
| 13 | `C0` | `RET NZ` |
| 14 | `C3 00 00` | `JP reset` (a tail call) |

Machine code for `reset`, 7 bytes: `21 00 00` (`LD HL,0`), `22 00 00`
(`LD (count),HL`), `C9` (`RET`). One reference: `ABS16` at offset 4 to `count`.

Directory records:

```text
03 02 00 00            bss, implicit $0400, size 2, no references
08 02 04 11 00 03      code, explicit $0402, size 17, 3 references
   01 00 04            ABS16, delta 1  (offset 1)  -> $0400
   04 00 04            ABS16, delta 4  (offset 5)  -> $0400
   0A 01 04            ABS16, delta 10 (offset 15) -> $0401
08 01 04 07 00 01      code, explicit $0401, size 7, 1 reference
   04 00 04            ABS16, delta 4  (offset 4)  -> $0400
```

`bump` needs an explicit ordinal because the implicit sequence would give it
`$0401`, which the forward declaration holds. `reset` needs one because the
sequence would give it `$0403`. The next blob, ordinal `$0403`, also needs an
explicit ordinal, because after `reset` the implicit sequence gives `$0402`.
Implicit numbering resumes from there.

The byte stream, after its header, receives the 17 bytes of `bump` and then the
7 bytes of `reset`, with zeros at every referenced offset.

## 14. Debug file

Linked with option `D`, the linker also writes `NAME.DBG` (roadmap step 73,
design decision O7) beside the line table: what a debugger needs beyond the
line table's statements, readable from CP/M in 128-byte records without a
parser. The line table (Section 11) gives an address's statement; the debug
file gives the named blob it lies in, and has room for the frames and types
a later compiler may record.

| Record | Layout |
| --- | --- |
| Header | magic `BSID` (4 bytes), major `u8` = 1, minor `u8` = 0, image CRC `u16` |
| Blobs | for each live named blob with bytes, in increasing address order: kind `u8`, address `u16`, size `u16`, name length `u8`, name |
| End of the blobs | `$FF` |
| Frames | count `u16`, then the frames |
| Types | count `u16`, then the types |
| Trailer | CRC `u16` over every preceding byte |

- **Image CRC** is the line table's (Section 11): the CRC of the output file
  as stored, so that a tool can check that both describe one program.
- **Blobs** are named from the name stream and the library's name section
  (Section 9, 7.5): a program compiled without option `M` or `Y` has no name
  stream, and its blobs are left out. A blob of no bytes is left out, so no
  two rows share an address. The kind is the blob's (Section 3.1); no kind
  is `$FF`, which ends the rows.
- **Frames and types** are zero in version 1.0: neither compiler records a
  routine's frame layout or its locals' types yet. A frame, when one is
  recorded, will be the routine's blob's address `u16`, its frame size
  `u16`, a count `u8` of locals and parameters, and for each its IX
  displacement `i16`, its type's index `u16` in the types, its name length
  `u8` and name; a type its kind `u8` (scalar, record, array, string,
  handle), its size `u16` and a kind's fields (a record's fields as names,
  offsets and type indices; an array's element and count; a handle's pool's
  name). A version 1.0 reader skips both by their counts only when they are
  zero, and refuses a later major version.

The file ends with its CRC; CP/M stores it in whole records, and a reader
ignores the padding after the CRC. `tools/where.ts` (`deno task where NAME
ADDRESS`) reads the line table and the debug file and lists the source line
for an address, with the blob and the offset in it.

