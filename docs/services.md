# Basie services, version 1

- Status: draft, revision 2 (after review)
- Date: 2026-10-04
- Related: [input, output and effects](io-and-effects.md),
  [design decisions](design-decisions.md) (D10, D25, D26, D36, D38),
  [CP/M target](cpm-target.md), [memory safety](memory-safety.md) §2.1,
  [review](reviews/2026-10-04-services-review.md)
- Shared contracts: z80-services `byteGateway/0`; z80-tool-services ABI v1 for
  named-file semantics (Section 10)

## 1. What a service is

A **service** is a predeclared routine provided by the runtime library of the
target profile. It is how a Basie program reaches the console, files, the
command line and the machine. The language itself has no operating-system
calls, port instructions or addresses ([I/O and effects](io-and-effects.md)).

- **Signatures** are ordinary Basie signatures, compiled into the compiler from
  the runtime's helper table, so services are called like any routine, and a
  call to a service the profile lacks is a compile-time error.
- **Failure** uses Nucleus's mechanism: a service that can fail is marked
  `fails` and reports a `u8` code (Section 9).
- **Cost.** Each service is a runtime blob, so a program carries only the
  services it calls. On CP/M 2.2 a call is an ordinary `CALL`.
- **Safety.** Services are part of the trusted base. A service given an alias
  checks its extent and mode, keeps no address after returning, and restores the
  DMA address to the runtime's own buffer before it returns. Services are
  runtime helpers for the trap reporter contract ([CP/M target](cpm-target.md)
  §10.2); only `writeBlock` can trap (`bounds`), and it does so before any
  transfer.
- **Library above services.** Formatting, parsing, string building, splitting
  the command line into words, pseudo-random numbers and the external-effects
  frame encoding are Basie library routines (D36, Section 8).

The target is CP/M 2.2 (D10). Where CP/M 3 offers more, the service says so;
everything works on 2.2.

## 2. File numbers

A file, the console and the printer are all identified by a **file number**, of
the predeclared type `File`.

- A `File` is 4 bytes: the address of its entry in the runtime's file table and
  a 16-bit generation, checked on every use, exactly as identifiers are
  ([memory safety](memory-safety.md) §5.11). Generations start at 1 and are
  never 0. An entry whose generation reaches $FFFF is withdrawn and never used
  again, as a pool slot is, so no stale `File` can match a later file; and a zeroed `File` variable, or one whose file has been
  closed, fails with `fileClosed` instead of reaching another file.
- There is no conversion between `File` and any integer, no arithmetic on it, and
  no way to read one from data. `File` values arise only from the `open`
  services and the predeclared `console` and `printer`. Two `File` values may be
  compared with `=` and `<>`.
- `console` and `printer` are fixed values the runtime recognises before
  consulting the table; they occupy no table entry and can't be closed
  (`notAvailable`).
- The number of files open at once is chosen at link time with `F=n`, 1 to 255,
  default 4 (D38). The table lives at the end of `BSS`, so the startup memory
  check covers it; it costs 184 bytes per entry (the profile's file-entry size:
  a 56-byte header and a 128-byte record buffer), and nothing if the program
  opens no files.
- A failed `open` allocates no entry and leaves no temporary file.

## 3. Console and printer

### 3.1 How the console is driven

Every console byte goes through **BDOS 6**, in both directions, and `readLine`
alone uses BDOS 10. BDOS functions 1, 2, 9 and 11 are never called. This avoids
a CP/M 2.2 trap: the BDOS's ordinary output path polls the keyboard for
Control-S and keeps any other waiting key in a one-byte buffer that BDOS 6 never
sees, so a key typed during output would vanish.

The consequences:

- output is raw: no tab expansion, no Control-S pause and no Control-P printer
  echo;
- Control-C does not interrupt output; it is an ordinary key; and
- the runtime keeps a one-byte lookahead so that `keyReady` doesn't lose the key
  it saw; and
- the byte `$FF` is written through the BIOS's `CONOUT` entry instead, because
  BDOS 6 reads `E = $FF` as a request for input (and, on CP/M 3, `$FD` and `$FE`
  too, which the `CPM3` profile also sends through the BIOS).

### 3.2 Console services

| Service, on `console` | Meaning | CP/M 2.2 |
| --- | --- | --- |
| `writeByte(console, b)`, `writeText(console, s)` | Write bytes unchanged | BDOS 6 |
| `readByte(console)` | Read one key and echo it; Control-Z gives `endOfInput`, which is then sticky for the rest of the run | BDOS 6 |
| `readLine(console, var line)` | Read one edited line, up to the string's capacity, without its terminator (Section 3.3) | BDOS 10, through the runtime's buffer |
| `readKey() as u8` | Wait for one key, without echo | BDOS 6 `$FF`, repeated; the lookahead first |
| `keyReady() as boolean` | Whether a key is waiting | BDOS 6 `$FF`; a key found is kept in the lookahead |

On CP/M 3, the `CPM3` profile uses BDOS 6's blocking (`$FD`) and status (`$FE`)
forms.

Nucleus's `readInputByte()` and `writeOutputByte(b)` remain, as shorthands for
`readByte(console)` and `writeByte(console, b)`. Nucleus's four storage routines
are not provided.

### 3.3 `readLine` on the console

- BDOS 10 gives the user CP/M's line editing: backspace (Control-H), delete
  line (Control-X and Control-U), retype (Control-R), physical end of line
  (Control-E) and printer echo (Control-P).
- The line is limited to the string's capacity, at most 253 (D25), though BDOS 10
  itself allows 255. When the buffer fills, BDOS 10 ends the line without a
  return key, so the console never reports `lineTooLong`.
- BDOS 10 echoes the return key as a carriage return without a line feed; the
  library's `prompt` writes the line feed. (To be confirmed under the
  full-fidelity harness.)
- A line whose first character is Control-Z is `endOfInput`, so console scripts
  can end cleanly.
- Control-C typed at the start of a line makes CP/M warm-boot immediately; this
  is one of the exits the runtime can't control (Section 7).

### 3.4 The printer

`printer` accepts `writeByte` and `writeText` (BDOS 5). Any other operation on it
fails with `notAvailable`.

## 4. Files

### 4.1 Names

A file name is a CP/M name: up to 8 characters, optionally a dot and up to 3
more, optionally preceded by a drive letter and colon, such as `B:DATA.TXT`.
Lower-case letters are converted to upper case. Name characters are restricted
to `A`–`Z`, `0`–`9` and ``! # $ % & ' ( ) - @ ^ _ ` { } ~``. Anything else is
`badName`, including spaces, control characters, bytes `$80` and above (which
would set CP/M attribute bits), `?` and `*` (except in search patterns), a part
longer than 8 or 3 characters, and any type beginning with `$`, which is
reserved for temporary files. User numbers can't be named; see Section 6.

### 4.2 Opening and closing

| Service | Meaning |
| --- | --- |
| `openRead(name as string[], mode as u8) as File fails` | Open an existing file for reading |
| `openWrite(name as string[], mode as u8) as File fails` | Create a file that replaces any existing one when it is closed (Section 4.6) |
| `openAppend(name as string[], mode as u8) as File fails` | Open an existing file, or create it, positioned at its end |
| `openUpdate(name as string[]) as File fails` | Open an existing file for reading and writing anywhere, in binary mode |
| `close(f as File) fails` | Write out any buffered data and release the number |
| `abort(f as File)` | Discard an `openWrite` file's new contents, or close any other file without further writes, and release the number |
| `flush(f as File) fails` | Write out buffered data and the directory entry, so the data survives if the machine stops |

`mode` is `textMode` (0) or `binaryMode` (1), predeclared constants; any other
value fails with `badMode`.

`close` always releases the file number, whether it succeeds or fails. A failed
`close` of an `openWrite` file has deleted the temporary file and left the old
file untouched.

### 4.3 Text and binary modes

**Binary mode** transfers bytes unchanged. CP/M records whole 128-byte records,
so reading a binary file to its end includes the padding of its last record;
programs that need exact lengths record them in the file's own format. The last
record of a binary file is padded with zeros when written.

**Text mode**, for `readByte`, `readLine`, `writeByte` and `writeText`:

- On reading, CR LF, lone LF and lone CR each become one newline byte (10), and
  Control-Z ends the file.
- On writing, a newline byte becomes CR LF, and a CR written immediately before
  a newline is absorbed, so a program that writes CR LF itself gets one CR LF.
  The last record is padded with Control-Z.
- A last line with no terminator is returned as a line; the next read gives
  `endOfInput`.
- `readLine` on a line longer than the string's capacity fills the string to
  capacity, discards the rest of the line, and fails with `lineTooLong`.
- `readBlock` and `writeBlock` are binary operations; in text mode they fail
  with `badMode`.

### 4.4 Reading and writing

| Service | Meaning |
| --- | --- |
| `readByte(f as File) as u8 fails` | Read one byte; `endOfInput` at the end |
| `writeByte(f as File, b as u8) fails` | Write one byte |
| `readBlock(f as File, var buf as u8[], count as u16) as u16 fails` | Read up to `count` bytes, never more than `buf.length`; returns the number read, 0 only at the end |
| `writeBlock(f as File, buf as u8[], count as u16) fails` | Write the first `count` bytes of `buf`; `count` above `buf.length` traps `bounds` before anything is written |
| `readLine(f as File, var line as string[]) fails` | Read one line in text mode (Section 4.3) |
| `writeText(f as File, text as string[]) fails` | Write a string's bytes |

**Failure semantics,** following z80-tool-services:

- A failed write leaves the file's position where it was before the call. Bytes
  already passed to the BDOS can't be recalled.
- A `diskFull` or `directoryFull` failure on an `openWrite` file **poisons** it:
  only `close` and `abort` are then accepted, and `close` discards the new
  contents.
- `readBlock` that meets an error after reading some bytes returns the count read
  so far; the error is reported by the next call.

`readBlock` and `writeBlock` may transfer whole records directly between the
BDOS and `buf`, but only while at least 128 bytes of `buf` remain, and they
restore the DMA address before returning.

### 4.5 Positioning

| Service | Meaning |
| --- | --- |
| `seek(f as File, position as u32) fails` | Move to a byte position; binary, append and update files only |
| `position(f as File) as u32 fails` | The current byte position; `notAvailable` on the console and printer |
| `size(f as File) as u32 fails` | The file's size in bytes, a multiple of 128 |

- In an update file, any position below 8,388,608 is allowed. Writing past the
  end extends the file, filling any gap with zeros; reading past the end gives
  `endOfInput`.
- In a read or append file, a position from 0 up to and including the size is
  allowed; beyond it is `seekFailure`.
- A failed `seek` leaves the position unchanged.
- `size` of an open file reports the runtime's own record of how far the file
  extends, since CP/M updates the directory entry only at `close`.

Update files use CP/M's random record functions (BDOS 33 and 34) for every
transfer, with the record number kept by the runtime, because a sequential read
after a random one would read the same record again.

### 4.6 Replacing files safely

`openWrite` writes to a temporary file and replaces the named file only when
`close` succeeds:

1. The temporary is named after the target with the type `$` followed by two
   hexadecimal digits for the file-table entry, such as `REPORT.$03`, so no two
   open files share one. Any existing file of that name, left by an earlier
   interrupted run, is deleted first.
2. At `close`, the old file is deleted and the temporary renamed to the target.
3. If the program fails, traps or calls `abort`, the temporary is deleted and the
   old file is untouched.

Temporaries left by an exit the runtime can't control (Section 7) can be removed
with `ERA *.$??`.

### 4.7 Directory operations

| Service | Meaning |
| --- | --- |
| `exists(name as string[]) as boolean fails` | Whether a file exists |
| `delete(name as string[]) fails` | Delete a file; `fileNotFound` if it doesn't exist |
| `rename(oldName as string[], newName as string[]) fails` | Rename within a drive; `fileExists` if the new name is taken |
| `findFirst(pattern as string[], var name as string[]) as boolean fails` | Start a search; `false` if nothing matches |
| `findNext(var name as string[]) as boolean fails` | The next match, or `false` |

- `delete`, `rename` and the replacement step of `close` fail with `fileBusy` if
  the name is open on any file number.
- Search patterns may use `?` for one character and `*` for the rest of the name
  or type, in CP/M's sense. Files in other user areas, erased files and the
  extra directory entries of large files are never returned. Returned names have
  CP/M's attribute bits removed.
- `findFirst` and `findNext` fail with `lineTooLong` if `name` has room for fewer
  than 14 characters.
- Only one search can be in progress, because CP/M keeps its state. Any other
  disk service ends it; `findNext` with no search in progress fails with
  `noSearch`.

### 4.8 Read-only drives and files

On CP/M 2.2, writing to a read-only drive or file is a fatal BDOS error: CP/M
prints `Bdos Err` and warm-boots without returning to the program. The runtime
therefore checks first: before `openWrite`, `openAppend`, `openUpdate`, `delete`
and `rename`, it checks the drive's read-only status (BDOS 29) and the file's
read-only attribute, and fails with `readOnly`. A bad sector or a changed disk
the BDOS reports fatally still ends the program outside the runtime's control
(Section 7).

### 4.9 FCB handling

The runtime owns every FCB and builds it correctly for each call: the extent,
`S2` and current-record bytes are zero at open and make; the random record bytes
`r0`–`r2` are kept below 8 megabytes; BDOS 35's use of `r0`–`r2` is saved and
restored around `size`; attribute bits are never set from a name and are masked
from names read back; search FCBs use extent 0 and never drive `?`.

## 5. Command line

| Service | Meaning |
| --- | --- |
| `commandTail(var text as string[])` | The whole command tail as typed, without its leading separator, truncated to the capacity |

The library's `word(text, n, var out)` splits text into space- or
tab-separated words. The CP/M CCP converts the command line to upper case, so
programs can't rely on its case. The tail is preserved for the whole run because
startup moves the DMA address before any disk operation
([CP/M target](cpm-target.md) §4).

## 6. Drives, users and the machine

| Service | Meaning | CP/M 2.2 |
| --- | --- | --- |
| `resetDisks()` | Reset the disk system, after the user changes disks | BDOS 13 |
| `resetDrive(drive as u8)` | Reset one drive, 0 for A | BDOS 37 |
| `currentDrive() as u8` | The current drive, 0 for A | BDOS 25 |
| `selectDrive(drive as u8) fails` | Make a drive current | BDOS 14 |
| `currentUser() as u8` | The current user number | BDOS 32 |
| `setUser(user as u8) fails` | Change the user number, 0 to 15 | BDOS 32 |
| `driveReadOnly(drive as u8) as boolean` | Whether a drive is read-only | BDOS 29 |
| `freeMemory() as u16` | Bytes between the end of `BSS` and the stack | — |
| `clock(var now as DateTime) fails` | Date and time on CP/M 3; `notAvailable` on 2.2 | CP/M 3 BDOS 105 |

A program that asks the user to change disks must call `resetDisks` or
`resetDrive` afterwards; otherwise CP/M marks the drive read-only.

There is no service to end the program early: a program ends by returning from
`main` or failing out of it. Failing out of `main` with a code is the idiom for a
deep failure; the code is visible as a return code only on CP/M 3.

## 7. When the program ends

- **On a normal return from `main`,** the runtime closes every open file as
  `close` would, including the replacement of `openWrite` files.
- **On an unhandled failure or a trap,** the trap or failure is reported first.
  Then the runtime aborts every `openWrite` file, deleting its temporary, and
  closes every other file so that its buffered data isn't lost. The clean-up
  makes only close and delete calls, and depends on no state a trap may have
  interrupted.
- **Exits the runtime can't control** skip the clean-up: Control-C at the start
  of a `readLine` on the console, a fatal BDOS error (a bad sector or a changed
  disk), and power loss. They may leave temporaries, which never replace the old
  file.

## 8. Library routines over the services

Written in Basie (D36): number formatting and parsing, string building, `word`
for command-line words, `prompt`, a line read without echo (over `readKey`),
`readAll(f, var buf)` to read a whole file, a `truncate` that copies a file's
prefix (CP/M 2.2 has no truncation), pseudo-random numbers, and the
external-effects frame encoding, written to the console. Free disk space (BDOS 27
and 31) is left to a later library release.

## 9. Failure codes

Codes 1 to 4 and 254 keep their z80-services `byteGateway/0` meanings, which are
also Nucleus's. Every service shares one code space:

| Code | Name | Meaning |
| ---: | --- | --- |
| 1 | `endOfInput` | The end of a file or of console input. `endOfFile` is another name for it |
| 2 | `inputFailure` | Input failed for another reason |
| 3 | `outputFailure` | The console or printer could not accept a byte |
| 4 | `storageFailure` | A disk error the BDOS reported and returned from |
| 5 | `fileNotFound` | The file does not exist |
| 6 | `fileExists` | The new name is already taken |
| 7 | `badName` | Not a valid file name (Section 4.1) |
| 8 | `tooManyFiles` | The file table is full |
| 9 | `fileClosed` | The file number doesn't refer to an open file |
| 10 | `diskFull` | No space left on the disk |
| 11 | `directoryFull` | No directory entries left |
| 12 | `readOnly` | The drive or file is read-only |
| 13 | `seekFailure` | The position is outside what the file allows, or beyond CP/M's 8 megabytes |
| 14 | `lineTooLong` | A line or name didn't fit the string |
| 15 | `notAvailable` | The target or device doesn't provide this |
| 16 | `fileBusy` | The name is open on another file number |
| 17 | `noSearch` | `findNext` with no search in progress |
| 18 | `badMode` | An invalid mode, or a block operation on a text file |
| 19–31 | — | Reserved for future services |
| 32–47 | — | The standard library, starting with `badNumber` (32) |
| 48–253 | — | Programs |
| 254 | `invalid` | z80-services `invalid`, reserved |
| 255 | — | Reserved |

## 10. Alignment with the shared contracts

Basie's services are its language adapter over the shared contracts, as Skate's
ports and Nucleus's procedures are.

| Basie | Contract | Notes |
| --- | --- | --- |
| `readByte(console)`, `writeByte(console)` | `byteGateway/0` input and output roles | Echo, Control-Z and raw bytes are Basie policy, as the contract intends |
| `readLine(console)` | — | Basie policy above the gateway |
| `openRead`, `openWrite` + `close`, `abort`, `read`, `write`, `seek` | z80-tool-services ABI v1 `openRead`, `beginWrite` + `commit`, `abort`, `read`, `write`, `seek` | Basie adopts their semantics now: a failed open allocates nothing, a failed write leaves the position unchanged and poisons an update, `close` always releases, seeking to the end is allowed |
| Failure codes 5–18 | tool-services `notFound` (5), `capacity` (8, 10, 11), `access` (12), `conflict` (6, 16), `invalid` (7, 18) | Basie's codes are finer; the mapping is fixed here so the runtime's table is built once |

**Gaps in the shared contracts.** These are recorded here to be proposed to
z80-services, and Basie doesn't wait for them: raw keys and key status, the
printer, a named-file profile with update and append, directory operations, and
a clock.

**The gateway's storage roles.** The CP/M provider implements `byteGateway/0`'s
storage roles over two files chosen by the test harness, so that the
z80-services conformance vectors test the provider. They are not reachable from
Basie source.

## 11. Cost

**[estimate]** Runtime bytes, paid only by programs that use them:

| Group | Size |
| --- | --- |
| Console and printer | 0.3–0.5K |
| Files: open, close, abort, flush, bytes, blocks, text lines, temporaries, checks | 1.5–2.0K |
| Files: positioning, append, update growth | 0.4–0.6K |
| Directory operations | 0.4–0.5K |
| Command line, drives, users, machine | 0.2–0.3K |

The compiler carries the services' signatures in its helper table, about 0.7K.

## 12. Open questions

1. **Positioning in text files,** such as saving and restoring a reading
   position. A library question, settled in roadmap step 57.
2. **Typed results** for services, once variants arrive in version 2.
3. **File attributes** (BDOS 30) for utilities that protect files.
