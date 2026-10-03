# Baton Object Format 1.0

- Status: draft specification, not yet reviewed
- Date: 2026-10-03
- Related: [build pipeline](build-pipeline.md) (overview and rationale),
  [linker](linker.md), [toolchain](toolchain.md), [CP/M target](cpm-target.md)

## 1. Scope

This document defines, byte for byte, the files that carry compiled Baton code
between the compiler and the linker:

- the **program object**, written by the compiler for one compilation;
- the **blob library**, which carries the prebuilt runtime for one target;
- the **line stream** and **name stream**, which carry debugging information;
  and
- the **line table**, which the linker writes for trap lookup.

It does not define source syntax, code generation or the linker's algorithm,
except where a field's meaning depends on them. The linker document defines how
these files are consumed. The toolchain document defines file names, the
command line and the order in which files are created and deleted.

## 2. Conventions

- All multi-byte integers are little-endian.
- `u8`, `u16` and `u32` are unsigned integers of 8, 16 and 32 bits.
- Bit 0 is the least significant bit.
- A **record** is a self-delimiting sequence of fields. Records are not aligned
  to anything and may cross 128-byte CP/M record boundaries.
- "Must" states a requirement on a producer. A consumer rejects any file that
  breaks one, with the diagnostic named in the linker document.
- Every file ends with a trailer containing a CRC-16/CCITT-FALSE value:
  polynomial `$1021`, initial value `$FFFF`, no reflection, final XOR `$0000`.
  The check value for ASCII `123456789` is `$29B1`.
- On CP/M, a file's final 128-byte record is padded with `$1A` after the
  trailer. A consumer stops at the trailer and ignores the padding.

## 3. Concepts

### 3.1 Blobs

A **blob** is the unit of placement and removal: a contiguous run of bytes the
linker places whole or drops whole.

| Kind code | Kind | Stored bytes | Meaning |
| ---: | --- | --- | --- |
| 0 | `code` | yes | One routine, with any jump tables and inline constants it owns |
| 1 | `rodata` | yes | One read-only constant: an aggregate constant, a string literal, an aligned table |
| 2 | `data` | yes | One initialised, writable top-level variable |
| 3 | `bss` | no | One zero-initialised top-level variable, pool or buffer |
| 4 | `startup` | yes | The program's first code; exactly one, in the blob library |
| 5 | — | — | Reserved; a consumer rejects it |
| 6 | control | — | Not a blob; a control record (Section 6) |
| 7 | — | — | Never begins a record; `$FF` marks the trailer |

A blob obeys these rules:

1. **No relative transfer leaves a blob.** `JR`, `DJNZ` and any other
   relative displacement must target a byte inside the same blob.
2. **No fall-through between blobs.** Execution never runs off the end of one
   blob into the next. A blob that ends in code ends in an unconditional
   transfer or return.
3. **No adjacency assumptions.** No code may rely on two blobs being next to
   each other or in a particular order.
4. **Every absolute address is a reference.** Any byte whose final value
   depends on where any blob is placed, including the blob itself, is covered
   by a reference (Section 5). Its stored placeholder bytes must be zero.
5. **Alignment belongs to the whole blob.** A `code` blob has alignment 1.
   Anything that needs alignment is its own `rodata`, `data` or `bss` blob.

### 3.2 Ordinals

Every blob, alias and pseudo-object has a 16-bit **ordinal**. Ordinals replace
names in linking: the linker never compares strings.

| Range | Owner | Use |
| --- | --- | --- |
| `$0000` | — | Invalid; never defined, never referenced |
| `$0001`–`$00FF` | blob library | Runtime blobs and aliases, numbered by the library's published helper table |
| `$0100`–`$011F` | linker | Pseudo-objects (Section 3.4) |
| `$0120`–`$FFFF` | compiler | Program blobs and aliases |

Within each owner's range, an ordinal is defined at most once. Ordinals need
not be dense; the linker sizes its tables by the highest ordinal defined.

A runtime ordinal, once published for a runtime identity, keeps its meaning in
every later version of that runtime (Section 10).

### 3.3 Aliases

An **alias** is an ordinal that denotes a fixed offset inside a blob:
`addr(alias) = addr(base) + offset`. Aliases give a blob more than one entry
point, which hand-written runtime code needs. For example, a multiply helper
may have a second entry that skips loading an operand, and both entries must
live in one blob because one falls through to the other.

A reference to an alias marks the alias's base blob live. An alias has no size
of its own; a `SIZE16` reference to an alias is invalid.

### 3.4 Pseudo-objects

The linker defines these ordinals after placement. Each has an address and a
size. A reference to a pseudo-object marks nothing live, except as stated.

| Ordinal | Name | Address | Size |
| --- | --- | --- | --- |
| `$0100` | `MAIN` | The entry routine's address; marks that routine live | The entry routine's size |
| `$0101` | `IMAGE` | First address of the stored image | Length of the stored image |
| `$0102` | `BSS` | First `bss` address | Total `bss` length, including padding |
| `$0103` | `FREE` | First address after `bss` | 0 |
| `$0104` | `REQUIRED` | `FREE` plus the stack reserve: the lowest acceptable top of memory | The stack reserve |
| `$0105` | `DATA` | Run address of the first `data` blob | Total `data` length, including padding |
| `$0106` | `DATACOPY` | Address of the stored copy of `DATA`, if one exists; otherwise equal to `DATA` | The copy's length, or 0 if none |
| `$0107`–`$011F` | — | Reserved; a reference is an error | — |

When a program has no `bss` blobs, `BSS` has the address `FREE` and size 0, and
likewise for `DATA`.

## 4. Program object

One compilation produces one program object, held in two files written in
parallel: a **directory stream** and a **byte stream**.

### 4.1 Directory stream

```text
directory-stream = program-header record* trailer
record           = blob-record | control-record
```

#### Program header (18 bytes)

| Offset | Field | Type | Meaning |
| ---: | --- | --- | --- |
| 0 | magic | 4 bytes | ASCII `BTNP` |
| 4 | major version | `u8` | 1 |
| 5 | minor version | `u8` | 0 |
| 6 | runtime identity | `u16` | The runtime this program was compiled against |
| 8 | helper-table version | `u16` | The lowest helper-table version the program needs |
| 10 | profile identity | `u16` | The target profile this program was compiled for |
| 12 | flags | `u8` | Bit 0: a line stream was written. Bit 1: a name stream was written. Bits 2–7: zero |
| 13 | stack reserve | `u16` | Minimum stack in bytes; 0 means the profile's default |
| 15 | compiler version | `u16` | Informational; not checked |
| 17 | reserved | `u8` | Zero |

#### Blob record

| Field | Type | Meaning |
| --- | --- | --- |
| header | `u8` | Bits 0–2: kind 0–4. Bit 3: an explicit ordinal follows. Bit 4: root. Bits 5–7: alignment code |
| ordinal | `u16`, optional | Present when bit 3 is set |
| size | `u16` | Stored length, or reserved length for `bss`; 1 to 65,535 |
| reference count | `u8` | 0–254, or 255 followed by a `u16` count of 255 or more |
| references | — | The blob's references, in strictly increasing offset order (Section 5) |

**Implicit ordinals.** A record without an explicit ordinal takes the previous
blob record's ordinal plus one. The first blob record of a program directory
takes `$0120`. Control records do not affect the sequence. A producer writes an
explicit ordinal whenever the next ordinal differs from that rule, as it does
for a routine whose ordinal was assigned at a forward declaration.

**Alignment code.** Values 0–6 mean alignment to 2 raised to that power: 1, 2,
4 ... 64 bytes. Value 7 means 256 bytes (page alignment). A `code` or `startup`
blob must have code 0.

**Root flag.** A root blob is live whatever references it (Section 3 of the
linker document). A program uses roots only for routines the source marks for
fixed-address use; Baton 1.0 defines no such source feature, so a program
directory from a 1.0 compiler has no roots.

**Size.** A blob of size 0 is invalid. A routine always has at least a `RET`;
an empty aggregate is not representable in Baton.

### 4.2 Byte stream

The byte stream is the concatenation of the stored bytes of every blob of kind
`code`, `rodata` or `data`, in directory order. It has no header, framing or
trailer of its own. Its length is recorded in the directory trailer, and a
consumer checks it.

Placeholder bytes covered by references must be zero. A consumer may check
this; a nonzero placeholder means a compiler fault.

### 4.3 Directory trailer (10 bytes)

| Field | Type | Meaning |
| --- | --- | --- |
| marker | `u8` | `$FF` |
| blob count | `u16` | Number of blob records, excluding control records |
| byte stream length | `u32` | Exact number of bytes in the byte stream |
| reserved | `u8` | Zero |
| CRC | `u16` | CRC over every directory byte from the magic up to, but not including, this field |

A directory without a valid trailer is rejected, so the linker can never use
the output of an interrupted compilation.

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
| 4 | `BANK8` | 1 | Bank number of target *t*; reserved for banked profiles |
| 5–7 | — | — | Reserved; a consumer rejects them |

The addend is a 16-bit value added modulo 65,536. A negative offset is written
as its two's-complement value.

The target may be:

- any blob or alias, including the referring blob itself;
- a pseudo-object; or
- for `SIZE16`, a blob or a pseudo-object, but not an alias.

**Self-references.** A blob that needs an absolute address inside itself, such
as an absolute `JP` to its own label or a jump-table entry, references its own
ordinal with the label's offset as the addend.

**Range.** `ABS16`, `LO8` and `HI8` targets must, after addition, denote an
address within the target's memory as the linker document defines. The
modulo arithmetic exists so that addends can be negative and large positive
offsets into big arrays are representable, not so that addresses may wrap.

### 5.2 Encoding

Each reference entry is:

| Field | Type | Meaning |
| --- | --- | --- |
| control | `u8` | Bits 0–3: offset delta 0–14, or 15 to escape. Bit 4: an addend follows. Bits 5–7: form code |
| absolute offset | `u16`, optional | Present when the delta field is 15 |
| target | `u16` | Target ordinal |
| addend | `u16`, optional | Present when bit 4 is set; otherwise the addend is 0 |

For a blob's first entry, the delta is the offset from the start of the blob.
For each later entry, it is the distance from the previous entry's offset and
must be at least 1. Offsets are strictly increasing.

A reference's bytes must lie wholly inside the blob, and two references'
bytes must not overlap. Since offsets are strictly increasing, an `ABS16` at
offset *o* requires the next entry, if any, to be at offset *o* + 2 or later.

A `CALL` with no addend costs 3 bytes of directory. A self-reference or field
reference costs 5 bytes, or 7 when its offset needs the escape.

## 6. Control records

A control record has header `$06` combined with a subtype in bits 3–7:
`header = $06 | (subtype << 3)`.

| Subtype | Name | Payload | Where allowed |
| ---: | --- | --- | --- |
| 0 | `ALIAS` | alias `u16`, base `u16`, offset `u16` | Program directory, blob library |
| 1 | `ENTRY` | ordinal `u16` | Program directory, exactly once |
| 2 | `BANK` | bank `u8` | Banked profiles only |
| 3–31 | — | — | Reserved; a consumer rejects them |

**`ALIAS`.** Defines `alias` as `base + offset`. The base must be a blob
defined somewhere in the same directory; it need not precede the alias. The
offset must be less than the base blob's size. An alias may not have another
alias as its base.

**`ENTRY`.** Names the program's entry routine, which `MAIN` resolves to. The
ordinal must be a `code` blob in the program directory.

**`BANK`.** Sets the bank of the blob records that follow it, until the next
`BANK` record. Without one, blobs are in bank 0. A flat profile rejects any
`BANK` record. Banked linking is not part of Baton 1.0; the record is reserved
so the format need not change when it is added.

## 7. Blob library

A blob library carries the prebuilt runtime for one target profile in a single
file: a header, a profile block, a directory section, a byte section and an
optional name section.

### 7.1 Library header (32 bytes)

| Offset | Field | Type | Meaning |
| ---: | --- | --- | --- |
| 0 | magic | 4 bytes | ASCII `BTNR` |
| 4 | major version | `u8` | 1 |
| 5 | minor version | `u8` | 0 |
| 6 | runtime identity | `u16` | Identity of this runtime |
| 8 | helper-table version | `u16` | Version of the helper ordinal table this library provides |
| 10 | profile identity | `u16` | The target profile this library implements |
| 12 | directory offset | `u32` | Byte offset of the directory section from the start of the file |
| 16 | byte section offset | `u32` | Byte offset of the byte section |
| 20 | byte section length | `u32` | Length of the byte section |
| 24 | name section offset | `u32` | Byte offset of the name section, or 0 if none |
| 28 | reserved | `u32` | Zero |

Each offset must be a multiple of 128, so that a CP/M reader can position to a
section with a random read (BDOS function 33). The gap before an offset is
filled with zeros.

### 7.2 Profile block

The profile block follows the header directly. It describes the target the
library was built for, so that one file carries both the runtime and the target
description.

| Field | Type | Meaning |
| --- | --- | --- |
| length | `u16` | Length of the rest of the block |
| target class | `u8` | 1: CP/M 2.2. 2: CP/M 3. 3: flat ROM. 4: banked ROM (reserved) |
| output kinds | `u8` | Bit 0: `.COM`. Bit 1: `.BIN`. Bit 2: Intel HEX |
| image base | `u16` | Address of the first stored byte: `$0100` on CP/M |
| image limit | `u16` | First address the stored image may not reach: the CCP base on CP/M 2.2, the nominal top of memory on CP/M 3, the end of ROM on a ROM target |
| nominal top | `u16` | Typical top of memory, for warnings |
| RAM base | `u16` | ROM targets: first RAM address. CP/M: 0 |
| RAM limit | `u16` | ROM targets: first address after RAM. CP/M: 0 |
| default stack reserve | `u16` | Bytes of stack if the program asks for none |
| option support | `u8` | Bit 0: keep-CCP supported. Bit 1: re-runnable supported. Bits 2–7: zero |
| free restart vectors | `u8` | Bit *n* set: `RST n*8` is free for runtime use. Bit 7 (`RST 38h`) must be clear on CP/M |
| debugger margin | `u16` | Bytes a resident debugger typically takes, for reports |
| further fields | — | Fields added in later minor versions; a reader skips them using the length |

### 7.3 Directory section

The directory section uses the same record grammar as a program directory
(Sections 4.1, 5 and 6), with these differences:

- there is no program header; the library header serves instead;
- implicit ordinals start at `$0001`;
- ordinals must lie in `$0001`–`$00FF`;
- exactly one blob has kind `startup`, and it is a root; and
- `ENTRY` records are not allowed.

Roots in a library mark code the system reaches without a call from the
program, such as restart-vector handlers the startup blob installs.

The section ends with a trailer of the program-directory form (Section 4.3).
Its byte-stream length field gives the byte section's length, and its CRC
covers the directory section only.

### 7.4 Byte section

The stored bytes of the library's `code`, `rodata`, `data` and `startup` blobs,
in directory order, exactly as in a program byte stream.

### 7.5 Name section

Optional. The same format as a name stream (Section 9), for the library's own
ordinals.

### 7.6 Whole-file check

The last 2 bytes before any padding are a CRC over every preceding byte of the
file. The linker checks the directory CRC when it reads the directory. It
checks the whole-file CRC only when asked to verify a library, because doing so
reads the whole file an extra time.

## 8. Line stream

Optional, written by default. It maps code positions to source positions for
trap lookup and source maps.

```text
line-stream = line-header part-record* blob-lines* line-trailer
```

| Record | Layout |
| --- | --- |
| Line header | magic `BTLS` (4 bytes), major version `u8` = 1, minor `u8` = 0 |
| Part record | tag `$01`, part `u8`, name length `u8`, name bytes |
| Blob lines | tag `$02`, ordinal `u16`, entry count `u16`, entries |
| Line trailer | tag `$FF`, CRC `u16` over every preceding byte |

Part records name each source part, using the name the compiler opened, such as
`B:MAIN.BTN`. They precede any blob-lines record that uses the part.

Each entry of a blob-lines record marks the start of a statement:

| Field | Type | Meaning |
| --- | --- | --- |
| control | `u8` | Bits 0–6: code offset delta 0–126, or 127 to escape. Bit 7: a part number follows |
| absolute offset | `u16`, optional | Present when the delta field is 127 |
| part | `u8`, optional | Present when bit 7 is set; otherwise the previous entry's part, or for the first entry the part of the blob's first statement |
| source offset | `u16` | Byte offset of the statement in its source part |

The first entry's delta is its offset from the start of the blob; each later
entry's delta is the distance from the previous entry. Two entries may share an
offset only if they are in different parts. A source part may be at most
65,535 bytes long, so a `u16` offset suffices. The first entry of each
blob-lines record must carry a part number.

## 9. Name stream

Optional. It maps ordinals to source names for maps and debugger symbol files.

| Record | Layout |
| --- | --- |
| Name header | magic `BTNM` (4 bytes), major version `u8` = 1, minor `u8` = 0 |
| Name record | ordinal `u16`, name length `u8` (1–31), name bytes |
| Name trailer | ordinal `$0000`, CRC `u16` over every preceding byte |

Names are the source spelling, truncated to 31 bytes. Compiler-generated blobs,
such as string literals, may have names the compiler invents, such as
`main.str3`; tools must not treat them as source identifiers.

## 10. Versions and compatibility

**Format version.** A consumer accepts a file whose major version it
implements and whose minor version is equal to or lower than its own. A higher
minor version may add fields only where this document says a reader skips
unknown fields (the profile block) and may define reserved kinds, forms or
subtypes; a consumer rejects any reserved value it does not implement.

**Runtime compatibility.** The linker accepts a program and a library together
only if:

- their runtime identities are equal;
- their profile identities are equal; and
- the library's helper-table version is equal to or higher than the program's.

A runtime identity's helper table is append-only: a new version may define new
ordinals in unused slots but never renumbers, removes or changes the kind of an
existing one. A helper whose implementation changes keeps its ordinal.

## 11. Line table

The linker writes the line table after placement, from the line stream and the
final addresses, before it deletes the program object.

| Record | Layout |
| --- | --- |
| Header | magic `BTLT` (4 bytes), major `u8` = 1, minor `u8` = 0, image CRC `u16`, part count `u8` |
| Part names | for each part in order: name length `u8`, name bytes |
| Entries | entry count `u16`, then entries sorted by address |
| Trailer | CRC `u16` over every preceding byte |

Each entry is 5 bytes: address `u16`, part `u8`, source offset `u16`. Only live
blobs contribute entries. Every live blob also contributes an entry at its own
start address: for a blob without line information, such as a runtime blob or
a constant, that entry has part `$FF` and its source offset holds the blob's
ordinal. The source position of an address is that of the entry with the
greatest address not above it; part `$FF` means the address lies in a blob
without source.

The image CRC is the CRC-16/CCITT-FALSE of the stored image as written, so a
tool can tell whether a line table belongs to a given program file.

## 12. Limits

| Item | Limit | Source of the limit |
| --- | --- | --- |
| Ordinals | 65,535 values, partitioned as in Section 3.2 | Format |
| Blob size | 65,535 bytes | Format; in practice the target's memory |
| References per blob | 65,535 | Format |
| Program byte stream | 4 GiB | Format; in practice under 64K |
| Source parts named in a line stream | 255 | Format |
| Source part length | 65,535 bytes | Format |
| Name length | 31 bytes | Format |
| Table sizes in the linker | Set by available memory | Linker document, Section 2 |

## 13. Worked example

The source:

```nucleus
var count as u16

forward sub reset()

sub bump()
    count = count + 1
    if count = 100
        reset()
    end
end
```

The compiler assigns ordinals as it meets declarations: `count` gets `$0120`,
the forward declaration of `reset` gets `$0121`, and `bump` gets `$0122`.

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
| 14 | `C3 00 00` | `JP reset` |

References: `ABS16` at offsets 1, 5 and 15, targeting `$0120`, `$0120` and
`$0121`.

Directory records, assuming `count` is the first program blob:

```text
03 02 00 00            bss, implicit ordinal $0120, size 2, no references
08 22 01 11 00 03      code, explicit ordinal $0122, size 17, 3 references
   01 20 01            ABS16, delta 1  (offset 1)  -> $0120
   04 20 01            ABS16, delta 4  (offset 5)  -> $0120
   0A 21 01            ABS16, delta 10 (offset 15) -> $0121
```

`bump` needs an explicit ordinal because the implicit sequence would give it
`$0121`, which the forward declaration of `reset` already holds. The `bss`
record for `count` carries no bytes. The byte stream receives the 17 bytes of
`bump`, with zeros at offsets 1–2, 5–6 and 15–16. When the body of `reset`
arrives later, its record also carries an explicit ordinal, `$0121`.
