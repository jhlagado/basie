# Baton services, version 1

- Status: draft, not yet reviewed
- Date: 2026-10-04
- Related: [input, output and effects](io-and-effects.md),
  [design decisions](design-decisions.md) (D9, D10, D25, D26),
  [CP/M target](cpm-target.md), [memory safety](memory-safety.md) §2.1

## 1. What a service is

A **service** is a predeclared routine provided by the runtime library of the
target profile. It is how a Baton program reaches the console, files, the
command line and the machine. The language itself has no operating-system
calls, port instructions or addresses ([I/O and effects](io-and-effects.md)).

- **Signatures** are ordinary Baton signatures, compiled into the compiler from
  the runtime's helper table, so services are called like any routine and a
  call to a service the profile lacks is a compile-time error.
- **Failure** uses Nucleus's mechanism: a service that can fail is marked
  `fails` and reports a `u8` code, normally handled with `else fail` or
  `handle`. The codes are predeclared constants (Section 7).
- **Cost.** Each service is a runtime blob, so a program carries only the
  services it calls. On CP/M 2.2 a call is an ordinary `CALL`.
- **Safety.** Services are part of the trusted base. A service given an alias
  checks its extent and mode, keeps no address after returning, and restores the
  DMA address to the runtime's own buffer before it returns.
- **Library above services.** Formatting numbers, parsing text, string building,
  pseudo-random numbers and the external-effects frame encoding are written in
  Baton in the standard library, on top of these services.

The target is CP/M 2.2 (D10). Where CP/M 3 offers more, the service says so;
everything works on 2.2.

## 2. Console and printer

The console and the printer are **predeclared file numbers**, `console` and
`printer`, so the file services of Section 3 work on them too:

```nucleus
writeText(console, "Name? ") else fail
readLine(console, name) else fail
writeText(printer, report) else fail
```

| On `console` | Meaning | CP/M 2.2 |
| --- | --- | --- |
| `writeByte`, `writeText` | Write bytes unchanged | BDOS 2, or 6 for bytes BDOS 2 would interpret |
| `readByte` | Read one byte of standard input, with echo; Control-Z gives `endOfFile` | BDOS 1 |
| `readLine` | Read one edited line, up to the string's capacity, excluding its terminator | BDOS 10, through the runtime's own buffer |

`printer` accepts only writes (BDOS 5). Reading from it, or positioning either
device, fails with `notAvailable`. Neither can be closed.

Two services are for the console alone:

| Service | Meaning | CP/M 2.2 |
| --- | --- | --- |
| `readKey() as u8` | Wait for one key, without echo or interpretation | BDOS 6 with `$FF`, repeated until a key arrives |
| `keyReady() as boolean` | Whether a key is waiting | BDOS 11 |

Nucleus's `readInputByte()` and `writeOutputByte(b)` remain, as shorthand for
`readByte(console)` and `writeByte(console, b)`.

Console output is raw bytes: no newline translation is done, so the library
writes CR LF where a line ends. Terminal control, including the external-effects
command frames of Skate's protocol, is bytes written by library routines.

`readLine` on the console enforces the string's capacity: the runtime reads into
its own buffer, limited to the smaller of the capacity and 255, then copies, so
the BDOS never writes into program storage directly.

## 3. Files

### 3.1 File numbers

A file is identified by a **file number**, of the predeclared type `File`, a
16-bit value the program can copy and compare but not do arithmetic on. It
holds a slot in the runtime's file table and a generation, in the
same way as an identifier, so a file number used after its file is closed is
detected and reported as `fileClosed` rather than reaching another file. The
runtime keeps each open file's FCB and record buffer in its own storage; the
program never sees them.

The number of files open at once is **chosen by the program** at link time,
with `BLINK` option `F=n`, from 1 to 255, and is otherwise limited only by
memory: each entry costs about 170 bytes for its FCB, record buffer and state.
The default is 4. The linker allocates the table in `BSS` only when the program
uses a file service ([object format](object-format.md), Section 3.6).

### 3.2 Opening and closing

| Service | Meaning |
| --- | --- |
| `openRead(name as string[], mode as u8) as File fails` | Open an existing file for reading |
| `openWrite(name as string[], mode as u8) as File fails` | Create a file, replacing any existing one when it is closed (Section 3.5) |
| `openUpdate(name as string[]) as File fails` | Open an existing file for random reads and writes, in binary mode |
| `close(f as File) fails` | Flush and close |

`mode` is `textMode` or `binaryMode`:

- **Text mode** turns CR LF and lone LF into one newline byte (10) on reading,
  writes CR LF for each newline, and treats Control-Z as the end of the file, as
  Skate does.
- **Binary mode** transfers bytes unchanged. CP/M records whole 128-byte
  records, so a binary file read to its end includes the padding of its last
  record; programs that need exact lengths record them in the file's own format.

Names are CP/M 8.3 names with an optional drive, such as `B:DATA.TXT`. Lower
case is converted to upper case. Wildcards, spaces and the CP/M delimiters
`<>=,;[]|` are rejected with `badName`.

A program that ends, normally, by failure or by a trap, has its open output
files closed by the runtime, but a file being replaced (Section 3.5) keeps its
old contents.

### 3.3 Reading and writing

| Service | Meaning |
| --- | --- |
| `readByte(f as File) as u8 fails` | Read one byte; `endOfFile` at the end |
| `writeByte(f as File, b as u8) fails` | Write one byte |
| `readBlock(f as File, var buf as u8[], count as u16) as u16 fails` | Read up to `count` bytes into `buf`, never more than `buf.length`; returns the number read, 0 only at the end |
| `writeBlock(f as File, buf as u8[], count as u16) fails` | Write the first `count` bytes of `buf`; `count` above `buf.length` traps `bounds` |
| `readLine(f as File, var line as string[]) fails` | Read one line in text mode, up to the capacity; a longer line fails with `lineTooLong` and leaves the rest unread on a file |
| `writeText(f as File, text as string[]) fails` | Write a string's bytes |

### 3.4 Positioning, for binary and update files

| Service | Meaning |
| --- | --- |
| `seek(f as File, position as u32) fails` | Move to a byte position; CP/M 2.2 random records (BDOS 33, 34) |
| `position(f as File) as u32` | The current byte position |
| `size(f as File) as u32 fails` | The file's size in bytes, a multiple of 128 on CP/M (BDOS 35) |

### 3.5 Replacing files safely

`openWrite` writes to a temporary file and replaces the named file only when
`close` succeeds, using the sequence the toolchain uses for its own output
([toolchain](toolchain.md), Section 6.1): write `NAME.$$$`, delete the old file,
rename. A program that fails or traps before closing leaves the old file
intact and the temporary file deleted at exit.

### 3.6 Directory operations

| Service | Meaning |
| --- | --- |
| `exists(name as string[]) as boolean fails` | Whether a file exists |
| `delete(name as string[]) fails` | Delete a file; deleting a missing file fails with `fileNotFound` |
| `rename(from as string[], to as string[]) fails` | Rename within a drive; fails with `fileExists` if the new name is taken |
| `findFirst(pattern as string[], var name as string[]) as boolean fails` | Start a directory search; wildcards allowed here only; `false` when nothing matches |
| `findNext(var name as string[]) as boolean fails` | The next match, or `false` |

The search services use the runtime's own DMA buffer, and only one search can be
in progress at a time; any other file service ends it.

## 4. Command line

| Service | Meaning |
| --- | --- |
| `argumentCount() as u8` | The number of space-separated words in the command tail |
| `argument(n as u8, var word as string[]) fails` | Copy word `n`, counting from 0; `noArgument` if there is none, `lineTooLong` if it doesn't fit |
| `commandTail(var text as string[])` | The whole tail as typed, truncated to the capacity |

The CP/M 2.2 CCP converts the command line to upper case, so programs can't rely
on its case. The command tail is preserved for the whole run because startup
moves the DMA address before any disk operation ([CP/M target](cpm-target.md),
Section 4).

## 5. The machine

| Service | Meaning |
| --- | --- |
| `freeMemory() as u16` | Bytes between the end of `bss` and the stack, at the moment of the call |
| `clock(var now as DateTime) fails` | The date and time on CP/M 3 (BDOS 105); `notAvailable` on CP/M 2.2 |

`DateTime` is a predeclared record of year, month, day, hour, minute and second.

There is no service to end the program early: a program ends by returning from
`main` or failing out of it, and the CP/M 3 return code follows
([CP/M target](cpm-target.md), Section 5).

## 6. Not services

These are library routines in Baton, built on the services above:

- writing numbers in decimal and hexadecimal, and `f32` values with a chosen
  precision; parsing them back, failing on malformed text;
- string building, comparison and searching (D25);
- console conveniences such as writing a line with CR LF, and prompts;
- pseudo-random numbers;
- the external-effects frame encoding for terminals, video and sound on
  Triptych, written through `writeOutputByte` and read with `readKey`.

## 7. Failure codes

Predeclared constants, shared by all services so a handler can report any of
them:

| Code | Name | Meaning |
| ---: | --- | --- |
| 1 | `endOfInput` | Standard input has ended |
| 2 | `inputFailure` | Standard input failed for another reason |
| 3 | `outputFailure` | The console or printer could not accept a byte |
| 4 | `endOfFile` | A read reached the end of a file |
| 5 | `fileNotFound` | The file does not exist |
| 6 | `fileExists` | The new name is already taken |
| 7 | `badName` | The name is not a valid CP/M file name |
| 8 | `tooManyFiles` | The file table is full |
| 9 | `fileClosed` | The file number does not refer to an open file |
| 10 | `diskFull` | No space left on the disk |
| 11 | `directoryFull` | No directory entries left |
| 12 | `readOnly` | The file or disk is read-only |
| 13 | `seekFailure` | The position is beyond the file or the disk |
| 14 | `lineTooLong` | A line or word didn't fit the string |
| 15 | `noArgument` | There is no such command-line word |
| 16 | `notAvailable` | The target doesn't provide this |
| 17 | `ioFailure` | Another disk or device error |

Codes 1 to 3 keep Nucleus's values for the same conditions, except that
Nucleus's `storageFailure` (4) is replaced by the file codes. Programs may use
codes from 32 upwards for their own failures.

## 8. Cost

**[estimate]** Runtime bytes, paid only by programs that use them:

| Group | Size |
| --- | --- |
| Console and printer | 0.2–0.4K |
| Files: open, close, bytes, blocks, text lines | 1.2–1.8K |
| Files: positioning and directory operations | 0.4–0.6K |
| Command line | 0.2K |
| Machine | 0.1K |

The compiler carries only the signatures in its helper table, about 0.2K.

## 9. Open questions

1. **Alignment with z80-services.** Each service should map to an operation of
   the shared z80-services contracts (byte gateway, console and storage), as
   Skate's ports and Nucleus's procedures do.
2. **Text-mode `seek`.** Positioning is binary-only above; text files could
   support saving and restoring a position.
3. **Typed results** for the file services once variants exist in version 2.
