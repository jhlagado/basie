# Baton toolchain 1.0

- Status: draft specification, not yet reviewed
- Date: 2026-10-03
- Related: [object format](object-format.md), [linker](linker.md),
  [CP/M target](cpm-target.md), [build pipeline](build-pipeline.md)

## 1. Scope

This document defines the Baton executable: what it reads, what it writes, in
what order, how it uses memory, and how it is invoked. It is the user's view of
the build. The object format and linker documents define the files and the
linking algorithm in detail.

## 2. One executable

Building a program is one command:

```text
A>BATON MAIN
```

`BATON.COM` compiles the source and links the result in one run. The compiler
and the linker are two phases of the same program, not two programs.

**Why one executable.**

- **Precedent.** ATOM appends its materializer to `ATOM.COM`, and Skate's
  compiler, output writer and materializer are all one CP/M program. Both reuse
  the compiler's workspace for the later phase once compilation ends.
- **Memory.** The linker's tables are large (linker, Section 2). In one
  executable they can occupy the compiler's code and workspace, which are dead
  once compilation finishes. A separate linker program would get the same
  memory, but only after a second program load.
- **Shared code.** File handling, record buffering, CRC, diagnostics and
  console output are written once.
- **One command.** No build script is needed to run two programs in order.

**Rejected alternatives.**

- **A separate `BLINK.COM`.** It costs a second program load on every build,
  duplicates the shared code, and needs a script or two commands.
- **An assembler as the second stage.** Baton generates machine code itself.
  No assembler takes part in building a Baton program.

## 3. Files

### 3.1 Inputs

| File | Example | Meaning |
| --- | --- | --- |
| Source parts | `MAIN.BTN`, `UTIL.BTN` | Baton source, in the order given on the command line (Section 5.2) |
| Blob library | `CPM22.BRL` | The prebuilt runtime and target profile; selected by option `P` |

### 3.2 Intermediate files

Created during the build, on the spool drive (option `S`), and deleted when the
build succeeds unless option `K` is given.

| File | Written by | Read by | Meaning |
| --- | --- | --- | --- |
| `MAIN.$DR` | compiler | linker | Program directory stream |
| `MAIN.$BY` | compiler | linker | Program byte stream |
| `MAIN.$LN` | compiler | linker | Line stream, unless option `N` |
| `MAIN.$NM` | compiler | linker | Name stream, when option `M` or `Y` is given |
| `MAIN.$$$` | linker | — | The new output, before it replaces the old one |

The `$` in each file type marks it as temporary. `ERA *.$*` removes any left by
an interrupted build.

### 3.3 Outputs

| File | Written when | Meaning |
| --- | --- | --- |
| `MAIN.COM` | always, by default | The program |
| `MAIN.BIN` or `MAIN.HEX` | instead of `.COM`, with option `O` | Other image kinds, where the profile allows |
| `MAIN.BAK` | when an older output existed | The previous output (Section 6) |
| `MAIN.LIN` | unless option `N` | Line table, for trap lookup |
| `MAIN.MAP` | option `M` | Link map and removal report |
| `MAIN.SYM` | option `Y` | Symbol file for `SID` and `ZSID` |

The output's base name is that of the first source part, unless option `O`
names it.

## 4. Phases

A build runs these phases in order. Each phase starts only if the previous one
succeeded.

| Phase | Reads | Writes |
| --- | --- | --- |
| 1. Compile | source parts, library header and profile block | `MAIN.$DR`, `MAIN.$BY`, `MAIN.$LN`, `MAIN.$NM` |
| 2. Handover | — | — (memory is reorganised; Section 7) |
| 3. Link, phases A to C | library directory, `MAIN.$DR` | — |
| 4. Link, phase D | library, `MAIN.$DR`, `MAIN.$BY` | `MAIN.$$$` |
| 5. Publish | — | renames `MAIN.$$$` to the output name (Section 6) |
| 6. Reports | `MAIN.$LN`, `MAIN.$NM`, `MAIN.$DR` | `MAIN.LIN`, `MAIN.MAP`, `MAIN.SYM` |
| 7. Clean up | — | deletes intermediate files |

The compiler reads the library's header and profile block before it starts, so
it can check the runtime identity and use the profile's values. It never reads
the library's blobs.

## 5. Command line

### 5.1 Syntax

```text
BATON part[,part...] [options]
```

Options follow Digital Research's convention: a bracketed, comma-separated list
after the file names, such as `BATON MAIN,UTIL [M,S=B,P=CPM3]`. The CP/M 2.2 CCP
converts the command line to upper case; option letters are case-insensitive.

### 5.2 Source parts

Each part is a CP/M file name, with an optional drive. A missing file type means
`.BTN`. Parts are compiled in the order given, as one compilation unit, as in
Nucleus's source manifest. How a program names its own parts inside source is
a language question not yet settled; until it is, the command line is the
manifest.

### 5.3 Options

| Option | Meaning | Default |
| --- | --- | --- |
| `P=name` | Blob library to use: `name.BRL` | `CPM22` |
| `L=d` | Drive holding the blob library | the drive of the first source part, then `A:` |
| `S=d` | Drive for intermediate files | the drive of the first source part |
| `O=name` | Output file name and kind, such as `O=GAME.HEX` | first part's name, `.COM` |
| `K` | Keep intermediate files | delete them |
| `C` | Compile only: stop after phase 1 and keep the intermediate files | compile and link |
| `X` | Link only: skip phase 1 and link existing intermediate files | compile and link |
| `M` | Write the map | no map |
| `Y` | Write the symbol file | no symbol file |
| `N` | No line stream and no line table | line table written |
| `R` | Re-runnable image (CP/M target, Section 7) | off |
| `B` | Keep the CCP resident (CP/M 2.2 target) | warm boot on exit |
| `Z` | Don't keep a `.BAK` of the previous output | keep one |
| `V` | Verify: check placeholder bytes and the library's whole-file CRC | off |
| `T=hhhh` | Trap lookup (Section 8) | — |

`C` and `X` exist for diagnosing the toolchain. They are not incremental
compilation: a link-only run links exactly what the last compile-only run
produced.

### 5.4 Return codes

Under CP/M 3, `BATON` sets the program return code with BDOS function 108:
success when the output was published, failure otherwise, so `SUBMIT` files can
stop on a failed build. Under CP/M 2.2, a failed build deletes `A:$$$.SUB` if it
exists, which stops a running `SUBMIT` job, as several period tools did. This
second behaviour can be disabled with an option if it proves unwelcome.

## 6. Publication and failure

### 6.1 Publishing the output

CP/M cannot rename one file over another. CP/M 2.2's rename function is
believed not to check whether the new name already exists, which can leave two
directory entries with the same name; CP/M 3 returns an error. `BATON`
therefore publishes in this order:

1. Write the image to `MAIN.$$$` and close it.
2. If `MAIN.COM` exists: delete `MAIN.BAK` if it exists, then rename `MAIN.COM`
   to `MAIN.BAK`. With option `Z`, delete `MAIN.COM` instead.
3. Rename `MAIN.$$$` to `MAIN.COM`.

Publication is not atomic. If the system stops between steps 2 and 3,
`MAIN.COM` is missing, but `MAIN.BAK` holds the previous version and `MAIN.$$$`
the new one.

Reports are written after publication. A failure while writing a report is
reported, but the published program stands.

### 6.2 Failures

| Failure | What `BATON` does |
| --- | --- |
| Source error | Reports it with file, line and column; deletes the intermediate files; leaves the old output untouched |
| Link error | Reports the linker diagnostic; keeps the intermediate files if `K` was given, otherwise deletes them; leaves the old output untouched |
| Disk or directory full, or another write error | Reports which file and which condition; deletes every file the build created; leaves the old output untouched |
| Read error | Reports the file; deletes the files the build created |

A file that was being written when the system stopped may not appear in the
directory at all; its space is recovered at the next disk login. Any that do
appear can be removed with `ERA *.$*`.

## 7. Memory

### 7.1 Image layout

`BATON.COM` is laid out so that the link phase can take over the compiler's
memory:

```text
$0100  shared core: startup, BDOS and file I/O, record buffers, CRC,
       diagnostics, console output, command-line parsing
       linker code
       compiler code
       --- end of BATON.COM ---
       compiler workspace: symbol tables, scopes, routine buffer,
       pending references, spool buffers
       ...
top    stack
```

During compilation, the linker's code sits unused. At handover, the compiler's
code and workspace become free, and the linker's tables occupy everything from
the start of the compiler code up to the stack.

### 7.2 Budget

These figures are estimates for planning and must be replaced by measurements:

| Region | Size |
| --- | --- |
| Shared core | about 3K |
| Linker code | about 4K to 6K |
| Compiler code | not yet known; Nucleus's compiler core is about 15K, and Baton's language is larger |
| File buffers in use during linking | about 1K |
| Stack | about 0.5K |

On a CP/M system with a 58K transient program area, the shared core, linker
code, buffers and stack take about 9K to 11K, leaving about 47K to 49K for the
linker's tables. The compiler's code and workspace both lie inside that space,
so their size doesn't reduce it.

### 7.3 Linker as an overlay

If the compiler needs the 4K to 6K that the resident linker code occupies
during compilation, the linker code can instead be stored in a separate file,
`BATON.OVL`, and loaded into the compiler's code area at handover. This saves
that memory during compilation, at the cost of one extra file read per build
and a second file to install. Baton 1.0 starts with the resident layout. The
overlay is adopted only if measurements of the compiler's workspace show the
need.

## 8. Trap lookup

```text
A>BATON MAIN [T=1A3F]
```

With option `T`, `BATON` doesn't compile or link. It reads `MAIN.LIN`, finds the
statement containing the address, opens that source part, and prints the file
name, line, column and the source line itself:

```text
MAIN.BTN 57:9  total = items[index]
```

The trap reporter prints the address of the call at the trap site, which lies
within the statement's code, so the lookup finds the right statement. An
address inside a runtime blob is reported as such, with the blob's name if the
library has a name section.

The line table records the CRC of the image it was built with. If `MAIN.LIN`
is missing, or `MAIN.COM` no longer matches that CRC because it was rebuilt
without a line table, `BATON` says so instead of reporting a wrong line.

## 9. Open questions

1. **Source parts named in source.** Whether a part can name the parts it
   depends on, as ATOM's `%INCLUDE` and Skate's `include` do, instead of the
   command line listing them all.
2. **Overlay or resident linker,** decided by measurement (Section 7.3).
3. **Library search order** for option `L` under CP/M 3, which can report the
   drive `BATON.COM` was loaded from at `$0050`.
