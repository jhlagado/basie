# Baton toolchain 1.0

- Status: draft specification, revision 3 (after two adversarial reviews)
- Date: 2026-10-03
- Related: [object format](object-format.md), [linker](linker.md),
  [CP/M target](cpm-target.md), [build pipeline](build-pipeline.md),
  reviews [1](reviews/2026-10-03-linker-spec-review.md) and
  [2](reviews/2026-10-03-linker-spec-review-2.md)

## 1. Scope

This document defines the Baton executable: what it reads and writes, in what
order, how it uses memory, and how it is invoked. It is the user's view of a
build. The object format and linker documents define the files and the linking
algorithm.

## 2. One executable

Building a program is one command:

```text
A>BATON MAIN
```

`BATON.COM` compiles the source and links the result in one run. The compiler
and the linker are two phases of one program.

**Why one executable.**

- **Precedent.** ATOM appends its materializer to `ATOM.COM`, and Skate's
  compiler, output writer and materializer are all one CP/M program. Both reuse
  the compiler's workspace for the later phase.
- **Memory.** The linker's tables are large. In one executable they occupy the
  compiler's code and workspace, which are dead once compilation finishes.
- **Shared code.** File handling, record buffering, CRC, diagnostics and
  console output are written once.
- **One command.** No script is needed to run two programs in order.

**Rejected alternatives.**

- **A separate `BLINK.COM`:** a second program load on every build, duplicated
  shared code, and two commands or a script.
- **An assembler as the second stage:** Baton generates machine code itself.
  No assembler takes part in building a Baton program.

## 3. Files

### 3.1 Inputs

| File | Example | Meaning |
| --- | --- | --- |
| Source parts | `MAIN.BTN`, `UTIL.BTN` | Baton source, in the order given on the command line |
| Blob library | `CPM22.BRL` | The prebuilt runtime and target profile, chosen by option `P` |

The compiler has the runtime's helper table compiled into it (object format,
Section 10). From the library it reads only the header, profile block and key
table, before compiling, to check compatibility and to learn the target class,
the default stack reserve and the free restart vectors. An incompatible library
is reported before any source is read.

### 3.2 Intermediate files

On the spool drive (option `S`):

| File | Written by | Read by | Meaning |
| --- | --- | --- | --- |
| `MAIN.$DR` | compiler | linker | Program directory stream |
| `MAIN.$BY` | compiler | linker | Program byte stream |
| `MAIN.$LN` | compiler | linker | Line stream, unless option `N` |
| `MAIN.$NM` | compiler | linker | Name stream, with option `M` or `Y` |
| `MAIN.$RF` | compiler | compiler | Scratch file for one routine's in-order references, used only when a routine's references overflow a 128-byte buffer; deleted when compilation ends |

On the output drive:

| File | Written by | Meaning |
| --- | --- | --- |
| `MAIN.$$$` | linker | The new image, before publication |
| `MAIN.$LT` | linker | The new line table, before publication |

The image and line table are written on the output drive because CP/M renames
only within a drive.

Before creating any file, `BATON` deletes any existing file of the same name.
CP/M's make-file function does not check for an existing name, and a crashed
build could otherwise leave two directory entries with one name.

### 3.3 Outputs

On the output drive, which is the first part's drive unless option `O` gives
another:

| File | Written when | Meaning |
| --- | --- | --- |
| `MAIN.COM` | by default | The program |
| `MAIN.BIN` or `MAIN.HEX` | instead of `.COM`, with option `O` | Other image kinds, where the profile allows |
| `MAIN.BAK` | when an older output existed, unless option `Z` | The previous output |
| `MAIN.LIN` | unless option `N` | Line table, for trap lookup |
| `MAIN.MAP` | option `M` | Link map and removal report |
| `MAIN.SYM` | option `Y` | Symbol file for `SID` and `ZSID` |

The base name is the first part's, unless option `O` names another.
Intermediate files always take the first part's name and the spool drive,
whatever `O` says, so a later link-only run finds them.

## 4. Phases

| Phase | Reads | Writes |
| --- | --- | --- |
| 1. Check | library header, profile block, key table | — |
| 2. Compile | source parts | `MAIN.$DR`, `MAIN.$BY`, `MAIN.$LN`, `MAIN.$NM` |
| 3. Handover | — | — (memory is reorganised; Section 7) |
| 4. Link A–C | library directory, program directory and stream headers | — |
| 5. Link D | library, `MAIN.$DR`, `MAIN.$BY`, `MAIN.$LN` | `MAIN.$$$`, `MAIN.$LT` |
| 6. Publish | — | renames (Section 6) |
| 7. Reports | directories, names | `MAIN.MAP`, `MAIN.SYM` |
| 8. Clean up | — | deletes intermediate files unless option `K` |

Each phase starts only if the previous one succeeded.

## 5. Command line

### 5.1 Reading the command line

`BATON` parses the raw command tail at `$0080` itself and ignores the default
FCBs, which the CCP fills by its own rules. The CP/M 2.2 CCP converts the tail
to upper case; option names are case-insensitive under CP/M 3 too.

### 5.2 Grammar

```text
command   = parts [ ws* options ]
parts     = part { ws* "," ws* part }
part      = filename
options   = "[" ws* option { ws* "," ws* option } ws* "]"
option    = flag | "P=" name | "L=" drive | "S=" drive | "O=" filename
          | "STACK=" decimal | "T=" hex
flag      = "K" | "C" | "X" | "M" | "Y" | "N" | "R" | "B" | "Z" | "V"
filename  = [ drive ":" ] name [ "." type ]
drive     = letter "A" to "P"
name      = 1 to 8 file-name characters
type      = 1 to 3 file-name characters
decimal   = 1 to 5 decimal digits, value 1 to 65535
hex       = 1 to 4 hexadecimal digits
ws        = a space
```

- A part without a type means `.BTN`. In `O=`, a missing type means `.COM`, and
  a missing drive means the first part's drive. User numbers are not supported.
- Each option may appear once; a repeated or unknown option is an error, as is
  a malformed value.
- `T=` (trap lookup) may be combined only with `L`, which says where to find
  the library named in the line table's header.

### 5.3 Options

| Option | Meaning | Default |
| --- | --- | --- |
| `P=name` | Blob library `name.BRL` | `CPM22` |
| `L=d` | Drive holding the blob library | look on the first part's drive, then on `A:` |
| `S=d` | Drive for intermediate files | the first part's drive |
| `O=[d:]name.type` | Output drive, name and kind (`.COM`, `.BIN` or `.HEX`) | the first part's drive and name, `.COM` |
| `K` | Keep intermediate files, including after a failure | delete them |
| `C` | Compile only, keeping the intermediate files | compile and link |
| `X` | Link only, from existing intermediate files | compile and link |
| `M` | Write the map | no map |
| `Y` | Write the symbol file | no symbol file |
| `N` | No line stream and no line table | written |
| `R` | Re-runnable image | off |
| `B` | Keep the CCP resident (CP/M 2.2) | warm boot on exit |
| `Z` | Don't keep a `.BAK` | keep one |
| `V` | Verify placeholder bytes and the library's whole-file CRC | off |
| `STACK=n` | Minimum stack in decimal bytes; the linker uses it when it exceeds the compiler's estimate, so it works with `X` | the compiler's estimate |
| `T=hhhh` | Trap lookup (Section 8) | — |

`C` and `X` are for diagnosing the toolchain, not for incremental compilation.
A link-only run refuses intermediate files whose compilation stamps disagree
(object format, Section 4.1).

### 5.4 Return codes

Under CP/M 3, `BATON` sets the program return code with BDOS function 108:

| Code | Meaning |
| --- | --- |
| `$0000` | Output published |
| `$FF11` | Source error |
| `$FF12` | Link error |
| `$FF13` | Disk error |

These differ from the codes a Baton program returns (`$FF01` to `$FF03`;
[CP/M target](cpm-target.md), Section 5), so a `SUBMIT` log shows which program
failed.

Values from `$FF00` count as failure to the CP/M 3 CCP's `:` conditional, so
`SUBMIT` files can stop on a failed build. Under CP/M 2.2, which has no return
codes, a failed build deletes `A:$$$.SUB` if it exists, which stops a running
`SUBMIT` job.

## 6. Publication and failure

### 6.1 Publishing

CP/M cannot rename one file over another, and CP/M 2.2's rename function is
believed not to check whether the new name exists. `BATON` publishes in this
order:

1. Close `MAIN.$$$` and `MAIN.$LT`.
2. If `MAIN.COM` exists: delete `MAIN.BAK` if it exists and rename `MAIN.COM` to
   `MAIN.BAK`; with option `Z`, delete `MAIN.COM` instead.
3. Rename `MAIN.$$$` to `MAIN.COM`.
4. Delete `MAIN.LIN` if it exists, and rename `MAIN.$LT` to `MAIN.LIN`.

Publication is not atomic. If the system stops between steps 2 and 3,
`MAIN.COM` is missing, but `MAIN.BAK` holds the previous version and `MAIN.$$$`
the new one. If it stops between steps 3 and 4, the line table is missing or
stale; its image CRC lets trap lookup detect this (Section 8).

### 6.2 Failures

| Failure | What `BATON` does |
| --- | --- |
| Source error | Reports it with file, line and column; deletes the intermediate files unless `K`; leaves the outputs untouched |
| Link error | Reports the linker diagnostic; deletes the intermediate files unless `K`, and deletes `MAIN.$$$` and `MAIN.$LT`; leaves the outputs untouched |
| Disk full, directory full or write error before publication | Reports the file and condition; deletes every file it created that is not yet published; leaves the outputs untouched |
| Failure while writing a report, after publication | Reports it; deletes the partial report; the published program and line table stand |
| Read error | Reports the file; deletes every file it created that is not yet published |

A file being written when the system stopped may not appear in the directory;
its space is recovered at the next disk login. Leftover intermediate files can
be removed with `ERA MAIN.$*`. (`ERA *.$*` on drive `A:` would also delete
`$$$.SUB` and stop a running `SUBMIT` job.)

## 7. Memory

### 7.1 Image layout

```text
$0100  shared core: startup, BDOS and file I/O, record buffers, CRC,
       diagnostics, console output, command-line parsing
       linker code
       compiler code
       --- end of BATON.COM, below the CCP ---
       compiler workspace: symbol tables, scopes, routine buffer,
       literal buffer, pending references, spool buffers
       ...
top    stack, below the word at $0006
```

`BATON.COM` must load below the CCP, so its file is at most the CCP base minus
`$0100`. Its workspace may extend over the CCP's memory, up to the address in
`$0006`, so `BATON` always exits with a warm boot.

At handover, the compiler's code and workspace become free, and the linker's
tables occupy everything from the start of the compiler code up to the stack.

### 7.2 Budget

**[estimate]** To be replaced by measurement:

| Region | Size |
| --- | --- |
| Shared core | about 3K |
| Linker code | about 5K |
| Linker file buffers (seven files) | about 1.2K |
| Stack | about 0.5K |
| **Fixed total during linking** | **about 9.7K** |
| Compiler code | not yet known; Nucleus's compiler core is about 15K |

The compiler's workspace during compilation, also estimates:

| Region | Size |
| --- | --- |
| Symbol table and scopes | not yet known; set by the number of declarations |
| Routine buffer, for branch shrinking | 2K to 4K |
| Literal buffer | about 1K |
| References for one routine | 128-byte in-order buffer (spilling to `MAIN.$RF`), plus about 256 deferred references at 5 bytes, 1.25K |
| Branch records, line entries and labels for one routine | about 1K, bounded by the routine buffer |
| File buffers: a source part, the four streams, and the library during the check | about 1K |

On a CP/M 2.2 system with 62K of memory, the area from `$0100` to the BDOS
entry at `$E406` is about 56.75K. Less the fixed 9.7K, about 47K remains for the
linker's tables. The compiler's code and workspace lie inside that area, so
their size doesn't reduce it.

### 7.3 Linker as an overlay

If the compiler needs the 5K the resident linker code occupies during
compilation, the linker code can be stored in a separate file, `BATON.OVL`, and
loaded into the compiler's code area at handover. This saves that memory during
compilation, at the cost of one more file read per build and a second file to
install. Baton 1.0 starts with the resident layout and adopts the overlay only
if measurements of the compiler's workspace show the need.

## 8. Trap lookup

```text
A>BATON MAIN [T=1A3F]
```

With option `T`, `BATON` neither compiles nor links. It reads `MAIN.LIN`, checks
its image CRC against the output file named in its header, finds the entry with
the greatest address not above the given one, opens that source part, and
prints the part, line and column and the source line:

```text
MAIN.BTN 57:9  total = items[index]
```

An address in a blob without source is reported with the blob's ordinal, and
its name from the library's name section when there is one. If `MAIN.LIN` is
missing, or the output file no longer matches its image CRC, `BATON` says so
rather than report a wrong line.

The address a trap prints is that of a call instruction inside the statement
that trapped ([CP/M target](cpm-target.md), Section 10), so the lookup finds that
statement.

## 9. Open questions

1. **Source parts named in source.** Whether a part can name the parts it
   depends on, as ATOM's `%INCLUDE` and Skate's `include` do, instead of the
   command line listing them all.
2. **Overlay or resident linker,** decided by measurement (Section 7.3).
3. **Library search under CP/M 3,** which records the drive `BATON.COM` was
   loaded from at `$0050`.
