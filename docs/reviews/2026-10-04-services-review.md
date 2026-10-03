# Review of the services draft

- Date: 2026-10-04
- Document: services.md (draft, 2026-10-04), with io-and-effects.md,
  design-decisions.md D10, D25, D26, D31 and D33, memory-safety.md §2.1,
  implementation-plan.md §6 and §7, cpm-target.md and toolchain.md §5.3 and §6.
- Contracts: z80-services (README, architecture, byte-gateway-v0,
  console-and-storage-v0, capability-model-v0, target-profile-v0,
  bindings-and-conformance-v0, consumer-audit, `contracts/z80-services-v0.json`);
  z80-tool-services README and ABI v1; Skate `docs/ports.md` and
  `docs/public/external-effects.md`; Nucleus runtime contract §8.
- Method: each service was mapped to the contract it should adapt, then
  checked against the CP/M 2.2 BDOS as it behaves, then attacked as a
  memory-safety and a disk-safety boundary. Findings are numbered by section:
  A alignment, E errors, S safety, L limits, M missing and misplaced, C cost.

Counts: 46 findings. 6 critical (E1, E2, E3, E5, S1, S4), 17 major, 23 minor.
Critical means a program following the draft loses data, corrupts a disk, or
cannot do something the draft promises.

---

## 1. Alignment table and gaps

### 1.1 What the shared contracts actually define today

z80-services v0 defines **one** profile, `byteGateway/0`: six operations over
four fixed roles (standard input, standard output, storage input, storage
output), statuses 0 success, 1 `endOfInput`, 2 `inputFailure`,
3 `outputFailure`, 4 `storageFailure`, 254 `invalid`. The console-and-storage
paper says echo, line editing, CR/LF, Control-Z and terminal control are
**adapter policy, never contract**, and that named files need a separate
profile with opaque handles, open and close, read and write rules, seek and
truncation, capacity limits and failure atomicity, which must not expose
drive letters or FCBs. That profile does not exist yet.

The nearest existing named-object contract is z80-tool-services ABI v1
(`openRead`, `beginWrite`, `read`, `write`, `rewind`, `seek` (32-bit), `close`,
`commit`, `abort`; statuses 0 ok, 1 invalid, 2 unavailable, 3 notFound,
4 capacity, 5 access, 6 storage, 7 conflict; tentative generation published
atomically by `commit`; a failed write poisons the update; `abortAll` at
abnormal end). It is a build-tool contract, but it is the only one in the
family that has settled handle, seek and publication semantics, and the
future z80-services file profile will almost certainly be shaped like it.

### 1.2 Mapping

| Baton service | Contract and operation | Alignment |
| --- | --- | --- |
| `readByte(console)`, `readInputByte` | byteGateway `readInputByte` (0) | Aligned, with Baton policy on top (echo, Control-Z). **A1**: the policy's EOF code must be 1, not 4 |
| `writeByte(console)`, `writeOutputByte`, `writeText(console)` | byteGateway `writeOutputByte` (1) | Aligned. The BDOS 2 / 6 choice is adapter policy (E1) |
| `readLine(console)` | none; policy above the gateway (console-and-storage §Console bytes) | Baton-owned, as Skate's `read-line` is |
| `readKey`, `keyReady` | none; "input events" is a deferred profile | **Gap G1** |
| `printer` | none; the gateway has no list-device role | **Gap G2** |
| `openRead` | tool-services `openRead` | Aligned (handle at offset 0, `notFound`) |
| `openWrite` + `close` | tool-services `beginWrite` + `commit` | Aligned in intent; **A2** on failure rules |
| `openUpdate` | none: every tool-services write is tentative | **Gap G3**; Baton's in-place update is a CP/M provider feature the shared profile has not taken a position on |
| `close` on a write file that fails | tool-services `abort` | **A2**: Baton has no `abort`, and does not say whether a failed `close` has aborted |
| `readByte(f)`, `readBlock` | tool-services `read` (`result=0` is EOF, never a status) | Aligned for `readBlock`; `readByte` reports `endOfFile` as a status, which the gateway also does (1) |
| `writeByte(f)`, `writeBlock`, `writeText` | tool-services `write` (all-or-nothing) | **A3**: Baton does not say what a partial `writeBlock` leaves behind |
| `seek`, `position` | tool-services `seek` (u32, provider may permit beyond-end with zero fill); byteGateway `seekStorageOutput` (0..length inclusive) | **A4**: Baton rejects beyond-end; both contracts admit exactly-at-end; byteGateway requires it |
| `size` | none | Gap, minor (tool-services has no size; a future profile should) |
| `exists`, `delete`, `rename`, `findFirst`, `findNext` | none | **Gap G4**: directory operations |
| `argumentCount`, `argument`, `commandTail` | none; target-profile v0 leaves the command line to the target | Baton-owned; M9 says two of these are library |
| `freeMemory` | none; runtime-owned | Fine |
| `clock` | none; "clocks follow after the base profile" (architecture §Profiles) | **Gap G5** |
| (none) | byteGateway `readStorageByte`, `rewindStorageInput`, `writeStorageByte`, `seekStorageOutput` (2–5) | **A5**: Baton surfaces none of the storage roles, yet implementation-plan §6 says the z80-services vectors will test Baton's providers |

### 1.3 Findings

**A1 (major). Code 4 collides with the gateway's `storageFailure`, and the console's EOF is reported under two names.**
§7 gives 4 to `endOfFile`; z80-services and Nucleus give 4 to
`storageFailure`. §2 says `readByte(console)` on Control-Z gives `endOfFile`
(4), while §7 code 1 `endOfInput` is "standard input has ended". A program
`handle`-ing both codes for one loop over "any file" needs two cases, and a
CP/M provider that passes the z80-services vectors returns 4 for a storage
fault, which a Baton handler would read as end of file.
*Fix:* keep 1–4 and 254 with their z80-services meanings. Use **one** code,
1, for end of input on every file number, named `endOfInput` with
`endOfFile` as an alias of the same value if the file-flavoured name is wanted.
Map a CP/M storage fault to 4 and drop `ioFailure` (17), or make `ioFailure`
an alias of 4. Start Baton's own codes at 5. Reserve 254 and 255; §7's "32
upwards" for programs should be "32 to 253".

**A2 (major). No abort, and the state after a failed `close` is unstated.**
tool-services: a failed write poisons the update and only `abort` is then
valid; a failed commit leaves the old generation current. Baton's `close`
"fails", but §3.5 does not say whether the file number is released, whether
the temporary is deleted, or whether the program may retry.
*Fix:* state that `close` always releases the number, success or failure,
and that a failed `close` of an `openWrite` file has deleted the temporary and
left the old file intact. Add `abort(f)` (one BDOS 19 and a slot release,
about 20 bytes) so a program that discovers an error half-way can discard
its output deliberately rather than by trapping. Record both as the Baton
projection of `commit` and `abort`.

**A3 (major). Atomicity of `writeBlock`, `readBlock` and `seek` failures is unstated.**
Both contracts require that a failed operation changes neither bytes nor
cursor. `writeBlock(f, buf, 300)` that meets a full disk in the third record
has written 256 bytes. Is the position 256 or 0? Does a retry rewrite them?
*Fix:* adopt the tool-services rule: a failed write leaves the file position
where it was before the call (the bytes already in the runtime's record
buffer are kept, those sent to the BDOS cannot be recalled); say so, and say
that a `diskFull` failure poisons an `openWrite` file so that only `close`
(abort) is accepted afterwards. For `readBlock`, state that it returns the
count read so far rather than failing when an error follows a partial read,
or that it fails and leaves the position unchanged; pick one. For `seek`,
state that failure leaves the position unchanged.

**A4 (minor). Seek exactly to the end is rejected.**
"`seekFailure`: the position is beyond the file". Both contracts admit
`position = length`; byteGateway requires it; it is how a program appends.
*Fix:* admit `position <= size`; see E12 for extending update files.

**A5 (minor). The gateway's storage roles have no Baton surface.**
Nucleus's `readStorageByte`, `rewindStorageInput`, `writeStorageByte` and
`seekStorageOutput` are dropped silently (§2 says only the two console
routines "remain"). The plan's intention to run the z80-services vectors
through Baton's providers needs those roles to exist somewhere.
*Fix:* either say that the CP/M provider's storage roles are two named files
chosen by the harness and are not reachable from Baton source, so the vectors
test the provider but not the services; or expose them as two predeclared file
numbers. The first is cheaper and honest.

**A6 (minor). Status names should carry the contract's spelling.**
When the file profile arrives it will use the tool-services vocabulary
(`notFound`, `capacity`, `access`, `conflict`). Baton's `fileNotFound`,
`diskFull`/`directoryFull`, `readOnly`, `fileExists` are finer, which is
fine, but the mapping should be written down now so the runtime's error
table is built once.

### 1.4 Gaps to raise in z80-services

| Gap | What Baton needs | Should Baton wait? |
| --- | --- | --- |
| G1 raw key and key-ready | an input-events or "console status" operation | No. Both are two BDOS calls; define them as Baton policy and offer the shape upstream |
| G2 printer | a second output role, or a general "named stream" | No. Baton's `printer` file number is a sensible shape to propose |
| G3 named files | the whole named-file profile: handles, open and close, read and write, seek, publication, directory listing | No. Baton should adopt tool-services v1's handle, read, write, seek, commit and abort **semantics** now (they are settled and tested) and treat the eventual z80-services profile as a renaming |
| G4 directory operations | exists, delete, rename, enumerate | No; propose Baton's set, with the one-search rule stated as a provider limit |
| G5 clock | a date-time operation | No |

Where Baton should change to match the contracts: A1 (codes), A2 (abort and
failed close), A3 (atomicity), A4 (seek to end). Where the contract has a gap
Baton should not wait for: everything in §1.4.

---

## 2. Errors

### Console

**E1 (critical). BDOS 2 output and BDOS 6 input do not mix: a key can vanish into the BDOS.**
CP/M 2.2's console output path (functions 2, 9 and 10's echo) polls the
console for Control-S. When the waiting key is not Control-S, the BDOS keeps
it in its one-byte `kbchar` buffer for the next function 1, 10 or 11 call.
Function 6 bypasses that buffer. So:

```nucleus
writeText(console, "Press any key") else fail   // BDOS 2: user's key lands in kbchar
var k = readKey()                               // BDOS 6: never sees it; waits for a second key
```

and `keyReady()` (BDOS 11) returns true because `kbchar` is full while
`readKey()` (BDOS 6) blocks. The draft's "BDOS 2, or 6 for bytes BDOS 2 would
interpret" makes this worse: the only byte BDOS 2 interprets is TAB, so the
rule is "everything through BDOS 2", with the Control-S poll on every byte.
*Fix:* choose one path for the whole console. Recommended: **BDOS 6 for every
console byte** (output, `readKey`, `keyReady`, and `readByte` with the echo done
by the runtime), and BDOS 10 only for `readLine`. Because functions 1, 2, 9 and
11 are then never called, `kbchar` is never filled and BDOS 10 is safe to mix
in. State the costs: no Control-S pause, no Control-P printer echo, no tab
expansion (the draft already promises raw bytes), and Control-C no longer
aborts the program during output (which is a benefit: see S4). Note that on
CP/M 3 function 6 has `$FE` (status) and `$FD` (blocking read) which the CPM3
profile can use. `keyReady` must then be BDOS 6 with `$FF`, keeping the byte
it returns in a runtime one-byte lookahead that `readKey` and `readByte`
consume first.

**E2 (critical). `readByte(console)` cannot report Control-Z under the stated code, and the EOF is not sticky.**
See A1 for the code. Also: after Control-Z, does the next `readByte` read
again? Nucleus's gateway says EOF "leaves the cursor unchanged", so every later
read is EOF too. The draft is silent. With BDOS 1 (or 6) the next call simply
waits for a key.
*Fix:* state that end of input on the console is sticky for the run, or that
it is not; the sticky rule matches the gateway and lets `while readByte` loops
terminate.

**E3 (critical). BDOS 10 lets the user warm-boot past the runtime's cleanup.**
Control-C at the start of a line in function 10 (and Control-S then Control-C
in function 2) warm boots immediately. No `close`, no temporary deletion, no
return code. A program with an `openWrite` file in progress leaves
`NAME.$$$` on the disk and `NAME` untouched, which is the right outcome, but
§3.5's "the temporary file deleted at exit" is false for this exit, and a
stale `NAME.$$$` from the previous run then collides with the next `openWrite`
(E6).
*Fix:* say that exits the runtime does not control (Control-C in BDOS 10,
BDOS fatal errors, power loss) skip the cleanup; make `openWrite` delete any
existing temporary before `make` (needed anyway, E6); and with E1's BDOS 6
policy the only remaining route is BDOS 10.

**E4 (major). BDOS 10 details are unstated or wrong.**
The buffer is `max, count, bytes...`; `max` must be 1–255, and the string's
capacity may be 0 (`string[0]` is legal in Nucleus) so the runtime must guard
`max = 0`. On 2.2 the line ends **without** a carriage return when the buffer
fills, so `lineTooLong` is unreachable on the console (the draft only claims
it "on a file", good, but say so). The terminating CR is not stored; BDOS 10
echoes the CR but not a line feed, so the cursor is at column 0 of the same
line when the service returns [verify in the harness]: the library's prompt
routine must write LF (or CR LF) itself. BDOS 10 also handles Control-H,
Control-X, Control-U, Control-R, Control-E and Control-P, which the draft
should list as the editing the user gets. Control-Z is an ordinary character
to BDOS 10, so `readLine(console)` has no end-of-input unless Baton defines
one (Skate's `read-line` treats a line beginning with Control-Z as EOF).
*Fix:* document all of the above; define "a line whose first byte is
Control-Z is `endOfInput`" if console scripts under redirection (CP/M 3,
emulators) are to end cleanly.

**E5 (critical). CP/M 2.2 R/O and bad-sector errors never return to the program.**
`readOnly` (12) and `ioFailure` (17) are listed as failure codes, but on 2.2 a
write to a drive the BDOS has marked read-only (by BDOS 28 or by detecting a
changed disk), a delete, rename or write of a file with the R/O attribute, and
a bad sector all print `Bdos Err On d:` and either warm boot or wait for a
key, then warm boot. The program's `else fail` never runs; open files and
temporaries are abandoned.
*Fix:* the runtime pre-checks everything it can: BDOS 29 (R/O vector) for the
drive before `openWrite`, `openUpdate`, `delete` and `rename`; the file's
R/O attribute (bit 7 of the first type byte, visible after BDOS 17 or 15)
before `delete`, `rename`, `openUpdate` and, critically, at `openWrite` time
rather than at `close`, so that a program does not write a whole temporary
and then die replacing an R/O file. State that `readOnly` is produced by these
checks and that a fault the BDOS reports fatally ends the program outside the
runtime's control. `ioFailure` on 2.2 is then reachable only for the return
codes the BDOS does give (close returning `$FF`, random read code 1, random
write codes 3 and 6).

### Files

**E6 (critical). `NAME.$$$` is not unique, and `make` does not check for duplicates.**
BDOS 22 creates a second directory entry if the name exists; BDOS 23 renames
without checking the target. Three concrete failures:

1. Two `openWrite` calls whose names share a base, `MAIN.COM` and `MAIN.LIN`,
   both write `MAIN.$$$`. Baton's own toolchain avoids this with `.$$$` and
   `.$LT` (toolchain §3.2). A program copying a file set hits it at once.
2. A stale `NAME.$$$` from an interrupted run (E3) plus a new `make` gives two
   entries with the same name; the subsequent `rename` renames both.
3. `openWrite("NAME.$$$")` makes the temporary and the target the same name.

*Fix:* temporary name `NAME.$n$` where `n` is the slot's hexadecimal digit
(or `$$n`), chosen so that no two open files share one; delete any existing
file of that name before `make`; reject with `badName` a target whose type
begins with `$`. Document the pattern so users can `ERA *.$?$` after a crash
(the toolchain already warns about `$$$.SUB`).

**E7 (critical). Deleting or renaming a file that is open leaves a stale FCB that writes into another file's blocks.**
`openWrite("DATA.TXT")` while `DATA.TXT` is open for reading (the filter
pattern) is a good reason for the temporary scheme, but at `close` the runtime
deletes `DATA.TXT` while the read FCB still names its blocks. The read file
then returns data from blocks the next `make` may reallocate. Worse,
`delete(name)` or `rename(name, ...)` of a file open for `openUpdate`, followed
by `writeByte` on that number, writes through the stale FCB into blocks that
may now belong to another file. This is not a memory-safety breach but it is
a disk-corruption hazard the runtime can prevent for free, since it owns the
table.
*Fix:* `delete`, `rename` and the replacement step of `close` fail with a new
code `fileBusy` when the name is open on any file number (compare drive and
name against the table; about 40 bytes). The filter pattern then requires the
program to `close` its input before closing its output, which is the usual
order anyway.

**E8 (major). The FCB must be built correctly for every call, and the draft does not say which fields the runtime owns.**
`EX`, `S2` and `CR` must be zero at open and make (a nonzero `S2` makes
sequential I/O skip to the wrong extent); the random record bytes `r0 r1 r2`
are at 33–35 and `r2` must be zero (files are at most 8 MB in 2.2); attribute
bits are the high bits of the name bytes and must be masked when a name is
read back (E13) and must never be set from a name (S5). BDOS 35 overwrites
`r0`–`r2`, so `size` on an open file must save and restore the runtime's
position.
*Fix:* a short FCB-handling section listing these.

**E9 (major). Random read and write do not advance the record, and sequential calls after them reread it.**
After BDOS 33 or 34 the FCB's `CR` names the record just transferred; a
following BDOS 20 reads the **same** record. A runtime that uses random
functions for `seek` and sequential ones for the bytes after it will
duplicate one record.
*Fix:* in update mode use random functions only, tracking the record number
in the runtime; or after any random call bump `CR` (and handle the extent
boundary) before resuming sequential calls. Say which.

**E10 (major). `size` is wrong for a file open for writing.**
BDOS 35 reads the directory. A new file's directory entry is written at
`make` with no records and updated only when an extent fills or at `close`,
so `size` of an `openWrite` or `openUpdate` file that has been extended
reports the old size.
*Fix:* `size` on an open file returns the runtime's own high-water mark;
BDOS 35 is used only for files not open, or restrict `size` to `openRead`
and `openUpdate` and document the behaviour for `openUpdate` after extension.

**E11 (major). Text-mode rules are incomplete.**
- Lone CR is not mentioned (Skate folds CR, LF and CR LF). A WordStar or
  old editor file with bare CRs will read as one line.
- Writing byte 13 in text mode: passed through, so a program that writes
  "CR LF" itself gets CR CR LF. Say so, or swallow a CR immediately before
  LF on write.
- The last record on `close` must be padded with Control-Z in text mode; in
  binary mode the pad byte should be stated (zero is conventional for `.COM`).
- A final line with no terminator before Control-Z or the physical end: is it
  returned, then `endOfFile`? (Skate: yes.) Say so.
- On `lineTooLong`, what is in `line`? The first `capacity` bytes with
  `.length = capacity`, or untouched? The draft says the rest is left unread,
  so the next `readLine` returns the tail as a line; a handler that ignores
  the failure has silently split a line. Say which, and consider the Skate
  rule (discard to the end of the line) as the safer default.
- Do `readBlock` and `writeBlock` translate in text mode, or are they
  forbidden there? Say.
- A `mode` value other than `textMode` or `binaryMode`: trap or fail? Say.

**E12 (major). Update files cannot grow.**
`seekFailure` for any position beyond the file, and `openUpdate` is the only
random-write mode, so a record-structured database can never add a record.
*Fix:* in update mode admit any position below 8,388,608; a write beyond the
end extends the file, filling the gap with zeros (BDOS 40, which exists in
2.2, does exactly this for new blocks; or BDOS 34 after zeroing the record
buffer); a read beyond the end is `endOfFile`. This also gives append (M1)
for binary files.

**E13 (major). `findFirst`/`findNext` details.**
- The BDOS matches only `?`; `*` must be expanded to fill the field. State
  that the pattern is `?` and `*` in CP/M's sense.
- `EX` must be 0 (and `S2` 0) in the search FCB. With `EX = '?'` every
  directory entry matches, so a file over 16K is listed once per extent.
- The matched entry is 32 bytes at `A × 32` in the DMA buffer; the type bytes
  carry the R/O, SYS and archive bits in bit 7 and must be masked before the
  name is copied out, or the returned string is not a valid name.
- The drive byte `'?'` searches all user numbers and returns erased entries;
  never use it.
- Deleted entries are `$E5`, which `EX = 0` matching already excludes.
- `findNext` after another disk call: BDOS 18 continues from the BDOS's own
  directory cursor, which `open`, `close`, `make`, `delete`, `rename`, `size`
  and any `read` or `write` that crosses an extent have moved. The draft's
  "any other file service ends it" is right but understates it: a `readByte`
  on an already-open file can end a search. Console calls do not.
- `findNext` when no search is in progress must fail deterministically (a
  code, not `false`): add `noSearch` or reuse `notAvailable`.

**E14 (minor). `rename` and `delete` accept wildcards at the BDOS level.**
The draft rejects wildcards, which is right; add that `?` must also be
rejected in the FCB after case folding (it is a legal CCP character) and that
a name longer than 8 or 3 is `badName`, not silently truncated as the CCP
does.

**E15 (minor). `close` of an unmodified `openUpdate` file still calls BDOS 16.**
Harmless; mention that BDOS 16 returning `$FF` (entry vanished) is `ioFailure`,
and that `close` of an `openRead` file may skip BDOS 16 entirely (nothing to
flush), which saves a directory pass per file.

**E16 (minor). `position(f)` cannot fail but §2 says positioning the console fails.**
`position(console)` has no `fails` in its signature.
*Fix:* return 0 for the console and printer, or add `fails`.

### Command line

**E17 (minor). Tail parsing details.**
The tail at `$0080` begins with the delimiter the CCP stopped on (usually a
space); words are separated by spaces and the CCP does not convert tabs.
`argument` must skip leading blanks and treat tab as a separator. Under
CP/M 3 the CCP also upper-cases, so the sentence about case holds for both.
With `GO` re-entry (cpm-target §7) the tail is whatever the shell set.

### Other

**E18 (minor). A changed floppy makes the drive read-only.**
The BDOS detects a swapped disk by directory checksum and marks the drive
R/O; the next write is fatal (E5). Any program that says "insert the next
disk" must call BDOS 37 (reset drive, present in 2.2) or 13 first. Baton has
no way to do so. See M3.

**E19 (minor). `clock` on CP/M 3.**
BDOS 105 returns days since 1 January 1978 as a 16-bit count and hours and
minutes in BCD, seconds in `A`. Turning days into year, month and day is a
hundred-odd bytes of division; `DateTime` as "year, month, day" commits the
runtime to it (see C3).

---

## 3. Safety

**S1 (critical). The file-number generation check is unspecified, and the obvious layout wraps.**
"A 16-bit value… holds a slot and a generation, in the same way as an
identifier." Identifiers have a 16-bit generation that saturates (memory
safety §5.11). A 16-bit `File` with an 8-bit slot has an 8-bit generation,
which either wraps (a `File` copied 256 open/close cycles ago matches a live
file and the program reads or writes the wrong file) or saturates (a slot is
withdrawn after 255 reuses, so a long-running program that opens a log 1,000
times with `F=4` finds itself unable to open files). Neither is memory-unsafe,
because the runtime only ever indexes its own table, but the first is a
wrong-file hazard and the second a usability bug, and the draft's "detected
and reported as `fileClosed` rather than reaching another file" is an
unqualified promise.
*Fix:* choose and state. Recommended: `File` is 16 bits, slot in the low 5
bits (at most 32 files, about 5.4K of table, more than any CP/M program
needs; see L1), generation in the high 11 bits, running 1 to 2046 and
**withdrawing** the slot at 2047 as pools do; with the FIFO slot reuse that is
over 65,000 opens before the first withdrawal with `F=32`, and 8,000 with
`F=4`. Alternatively make `File` 4 bytes and copy the identifier design
exactly. Either way, say that generation 0 is never issued, so a zeroed `File`
variable is `fileClosed`.

**S2 (major). No conversion to or from `File` is stated.**
D4 and D31 list the numeric conversions; `File` is in none of them, and
services.md says only "not do arithmetic on". Say explicitly: there is no
conversion between `File` and any integer, `File` is not an index, and
`File` values arise only from `openRead`, `openWrite`, `openUpdate`,
`console` and `printer`. Baton has no reinterpretation of bytes as records,
so a `File` cannot be read from a file either. With that sentence the
forging question is closed; without it a reviewer of the specification will
reopen it.

**S3 (major). `console` and `printer` must not be forgeable or closable, and need slots.**
They are predeclared `File` values. If they occupy ordinary table slots, they
cost 170 bytes each. If they are reserved slot numbers (say 30 and 31) with a
fixed generation, the runtime's check must special-case them before the table
lookup. Say which, and say which code `close(console)` fails with
(`notAvailable`, presumably).

**S4 (critical). The exit rule for open files contradicts itself, and the trap path is underspecified.**
§3.2: a program that ends normally, by failure or by a trap "has its open
output files closed by the runtime, but a file being replaced keeps its old
contents". §3.5: a program that fails or traps "leaves the old file intact
and the temporary file deleted at exit". Read together, an `openWrite` file
that is never closed is **always** abandoned, even on a normal return from
`main`, so a program that forgets `close` silently loses its whole output,
while an `openUpdate` file is flushed. Skate flushes and closes at normal end.
*Fix:* state the rule in one place. Recommended: on normal return from `main`,
the runtime closes every open file as `close` would (replacement included);
on an unhandled failure or a trap it aborts `openWrite` files (deletes the
temporary) and closes `openUpdate` files so that their last record is not
lost. State that the trap reporter prints the report first, then runs the
cleanup, so a disk fault during cleanup cannot hide the trap; that the cleanup
makes only BDOS 16 and 19 calls; and that it must not depend on any service
state a trap may have interrupted (a service should make no BDOS call after
a point where it can trap, which is already true if `bounds` is checked
before any transfer). List the exits that skip cleanup (E3).

**S5 (major). Name validation must reject bytes with bit 7 set, and control bytes.**
A name byte `≥ $80` sets an attribute bit in the FCB: `openWrite` with a
name containing `$C1` would create an R/O or SYS file, and a `rename` to such
a name changes attributes. The draft's reject list is the CCP delimiters only.
*Fix:* accept exactly `A`–`Z`, `0`–`9` and the printable ASCII characters
CP/M allows (`! # $ % & ' ( ) - @ ^ _ \` { } ~`), after folding `a`–`z`;
reject everything else, including space, control bytes and bytes `≥ $80`.

**S6 (major). Services that take aliases: each is bounded, but say how.**
Checked against §2.1's obligations:

| Service | Alias | Extent respected? |
| --- | --- | --- |
| `readLine(console, s)` | `var string[]` | Yes: BDOS 10 into the runtime buffer, copy ≤ capacity, set length |
| `readLine(f, s)` | `var string[]` | Yes, if length is set ≤ capacity on every path including `lineTooLong` (E11) |
| `readBlock(f, buf, n)` | `var u8[]` | Yes: copy ≤ min(n, length) from the record buffer |
| `writeBlock(f, buf, n)` | `u8[]` ticket | Yes: `n > length` traps `bounds` **before** any transfer |
| `writeText(f, s)` | `string[]` ticket | Yes: reads ≤ length |
| `findFirst(p, name)` | `var string[]` | Only if capacity ≥ 12 (14 with a drive) is checked; otherwise the name is truncated. Fail with `lineTooLong` |
| `argument(n, w)`, `commandTail(t)` | `var string[]` | Yes |
| `clock(now)` | `var DateTime` | Fixed size |
| `openRead(name, m)` etc. | `string[]` ticket | Reads ≤ length |

Add the one permitted optimisation and its condition: `readBlock` and
`writeBlock` may set the DMA address into `buf` directly for whole records
only when at least 128 bytes of `buf` remain, and must restore the DMA address
before returning (§2.1). Without the condition a 128-byte BDOS read into a
100-byte array is exactly the breach io-and-effects §4 describes.

**S7 (minor). `writeBlock` traps inside a service.**
Fine under cpm-target §10.2 (a helper jumps to the reporter with its entry
stack restored), but the services section should say that services are
helpers for the reporter contract and list which can trap (`writeBlock` with
`bounds`; `readBlock` should not trap, since it clamps).

**S8 (minor). A failed `openWrite` must allocate no slot and leave no temporary.**
tool-services: "a failed open allocates no handle". With E6's
delete-before-make, a failed `make` (directory full) after a successful
delete has removed a stale temporary, which is fine, but the slot must be
released. Say so.

---

## 4. Limits

**L1 (major). `F=n` is not in the option table, and the runtime cannot size a `bss` blob from an option.**
toolchain §5.3 lists no `F`. The object format's blobs are fixed size and
`OPTIONS` is a 16-bit flag word with no room for a count. The file table
therefore cannot be a `bss` blob sized at link time without a new mechanism.
*Fix:* either add `F=n` to the toolchain and give the linker a way to emit a
sized `bss` blob (a new `LIMITS`-like record or a profile value the linker
writes into the runtime's table-size cell), or carve the table from `FREE` at
startup with `n` stored in a 1-byte runtime data cell the linker patches, and
add `n × 176` to `REQUIRED` so the memory check covers it. Set the maximum
from S1's slot width (32) and record that reason in the register; it is a
representation limit, like the pool-index width, not an arbitrary one.

**L2 (minor). The console `readLine` limit is 253, not 255.**
Bounded strings hold at most 253 (D25), so "the smaller of the capacity and
255" is always the capacity, and the register's "255 characters, BDOS 10"
should read "253, string capacity (BDOS 10 allows 255)".

**L3 (minor). Line length on files is 253 by the string representation.**
Reasonable, and the register already points long text at `u8[]`; add that
`readLine` on a file with a line over 253 bytes is a routine occurrence in
machine-written text (assembler listings, `.HEX` files are fine at 45) and
that the library's `readAll` or `readBlock` is the escape.

**L4 (minor). Argument count.**
At most 64 words fit in 127 bytes, so `u8` is right; say so.

**L5 (minor). Search state: one, CP/M.**
Correct; the register should name BDOS 17/18's directory cursor as the
reason and note E13's "any disk call" clarification.

**L6 (major). Name forms.**
"8.3 with an optional drive" is right for 2.2. User numbers have no name
syntax in 2.2 (ZCPR's `B3:` and CP/M 3's `du:` forms do); say that user
numbers are not addressable by name in version 1 and that M4's
`currentUser`/`setUser` cover them. The character rule needs S5's list.
Temporary names take a further type pattern `$?$` (E6), which must be
documented as reserved.

**L7 (minor). Failure codes.**
17 used, programs from 32: fine. Reserve 254 and 255 (A1), reserve 18–31 for
future services explicitly, and move `endOfFile` off 4. Nucleus compatibility
for 1–3 holds; for 4 it does not, unless A1 is adopted.

---

## 5. Missing and misplaced services

### Missing, and needed in version 1

**M1 (major). Append.**
Log files, output accumulated across runs. CP/M 2.2 has no append mode; the
runtime does it with `size` (BDOS 35) and a random write at the last record,
except that a text file's last record ends at its first Control-Z, so append
in text mode must read the last record, find the Control-Z and continue from
there. Give `openAppend(name, mode)`; cost about 120 bytes.

**M2 (major). Flush.**
CP/M 2.2 writes data records through at once but updates the directory entry
only at `close`, so a long-running program's log loses everything in the
current extent if the machine stops. `flush(f)` = BDOS 16 then BDOS 15 with
the position restored; about 40 bytes. Programs that print progress to a file
need it.

**M3 (major). Disk reset.**
`resetDisks()` (BDOS 13) and `resetDrive(d)` (BDOS 37). Without them a program
cannot survive a floppy swap (E18); every CP/M utility that prompts for a disk
calls one of them. Ten bytes each.

**M4 (major). Current drive and user.**
`currentDrive() as u8` (BDOS 25), `selectDrive(d)` (BDOS 14),
`currentUser() as u8` and `setUser(u)` (BDOS 32). Needed to display a prompt,
to resolve a bare name, and because files in another user area are otherwise
unreachable. Twenty bytes in all.

**M5 (minor). Read-only test and attributes.**
`driveReadOnly(d) as boolean` (BDOS 29) lets a program report before trying;
`setAttributes(name, readOnly, system)` (BDOS 30) is how utilities protect
files. Optional for 1.0; the runtime will have the BDOS 29 call anyway (E5).

**M6 (minor). Truncate.**
Not available in 2.2 (CP/M 3 has BDOS 99). `openWrite` rewrites; a library
`truncate` can copy the prefix. Say so rather than leaving the reader to look
for it.

**M7 (minor). Free space.**
BDOS 27 and 31 (allocation vector and DPB) give free space in about 150 bytes
of bit counting. Common in utilities; defer to a library over two small
services or to version 1.1, but record the decision.

**M8 (minor). Reading a whole file.**
`readBlock` with a large `u8[]` does it; add `readAll(f, var buf)` to the
library list in §6, with the note that CP/M cannot tell a binary file's exact
length.

**M9 (minor). A line without echo.**
Library over `readKey` and `writeByte`; add to §6.

**M10 (minor). An exit service.**
"There is no service to end the program early" is a defensible choice, but a
deep failure in a utility must be threaded up through every caller as `fails`.
Keep the decision; record that `fail` out of `main` with code 32+ is the idiom
and that the code is not visible on 2.2.

### Included, but should be library

**M11 (major). `argumentCount` and `argument` are string parsing.**
They read the tail and split on blanks. A library `word(text, n, var out)`
over `commandTail` does the same for any string, costs the runtime nothing,
and is tree-shaken when unused. Keep `commandTail` as the only service.

**M12 (minor). `exists` can be library over `findFirst`.**
But it then needs a 12-byte string and interacts with the one-search rule
exactly as the service would. Keep it as a service if the FCB-building code is
shared; otherwise drop it. Either is fine; say which.

**M13 (minor). `readInputByte` and `writeOutputByte`.**
Keep, as alias blobs costing nothing; say that Nucleus's four storage
routines are not provided (A5).

### The failure-code list

Right in shape, with these changes: A1 (4, 254, 255), E7 (`fileBusy`),
E13 (`noSearch`), and one more: `badMode` or a trap for an invalid `mode`
(E11). `seekFailure` should cover the 8 MB limit explicitly.

---

## 6. Cost

**C1 (minor). Console and printer, 0.2–0.4K: plausible.**
With E1's BDOS 6 policy: output 12 bytes, echoing input 20, `readKey` with
lookahead 25, `keyReady` 20, `readLine` through BDOS 10 with the guard and
copy 60, printer 12, the `console`/`printer` special-casing in the file-number
check 20. About 170–250 bytes.

**C2 (major). Files, open, close, bytes, blocks and text lines, 1.2–1.8K: low once the corrections above are in.**
Name parsing and validation with S5's character set about 150; FCB build and
temporary naming 60; `openRead`/`openWrite`/`openUpdate` with delete-before-
make, R/O pre-checks (BDOS 29 and the attribute) and busy check 220; `close`
with the replacement sequence, abort path and busy check 160; byte read and
write with record buffering, extent crossing and text translation 300; block
transfers 150; `readLine` and `writeText` 130; the file-number check with
generation 40; exit cleanup 70; BDOS return-code mapping 60; error table 40.
About 1.4–1.5K before E12's extension logic (another 100). Say 1.5–2.0K.

**C3 (minor). Machine, 0.1K: low if `clock` converts dates.**
`freeMemory` is 10 bytes. `clock` on CP/M 3 with BCD-to-binary and
days-to-date conversion is 150–200 bytes. Either raise the figure or define
`DateTime` as the BDOS 105 form (days since 1978, hour, minute, second) and
put the calendar conversion in the library.

**C4 (major). The compiler's helper table, 0.2K: low.**
About 35 service signatures, each needing its name (average 9 characters),
parameter kinds and types, result type, `fails` flag and ordinal: roughly 16
bytes each, 0.55K, plus the predeclared `File` and `DateTime` types and the
17 named constants (another 0.15K). Budget 0.7K, which comes out of D9's 24K.
A library-level `argument` (M11) removes two entries.

**C5 (minor). Per-file 170 bytes: right.**
FCB 36, record buffer 128, mode 1, flags 1, position 4, byte-in-record 1,
generation 2, dirty 1: 174. Round to 176.

---

## 7. Recommended changes, in priority order

1. **Console I/O through BDOS 6 only, BDOS 10 for `readLine`** (E1, E3): fixes
   the lost-key bug and removes Control-C's bypass of the cleanup.
2. **Unique temporaries, delete before make, busy check** (E6, E7): `NAME.$n$`
   per slot, delete any existing one, and refuse `delete`, `rename` and
   replacement of a name that is open. Without this the "safe replacement"
   claim is false and open files can write into other files' blocks.
3. **Pre-check R/O at open time** (E5): BDOS 29 and the R/O attribute before
   `openWrite`, `openUpdate`, `delete` and `rename`, so `readOnly` is a code
   the program can actually receive on 2.2.
4. **One exit rule** (S4): commit open files on normal return, abort
   `openWrite` and flush `openUpdate` on failure or trap; report before
   cleanup; list the exits that skip it.
5. **Fix the codes** (A1, L7): end of input is 1 everywhere, 4 stays
   `storageFailure`, Baton's codes start at 5, 254 and 255 reserved, add
   `fileBusy` and `noSearch`.
6. **Specify `File`** (S1, S2, S3): 5-bit slot and 11-bit saturating generation
   (or 4 bytes), no conversions, generation 0 never issued, reserved slots for
   `console` and `printer`.
7. **Adopt tool-services failure semantics now** (A2, A3, A4): add `abort`;
   a failed write leaves the position unchanged and poisons an `openWrite`
   file; `seek` to exactly the end is allowed; `close` always releases.
8. **Let update files grow and add append, flush, disk reset, drive and user**
   (E12, M1–M4): about 300 bytes in all, and without them common CP/M
   utilities cannot be written.
9. **Put `F=n` in the toolchain and give it a mechanism** (L1): a linker-
   patched size cell and `REQUIRED` accounting; maximum 32 from the `File`
   layout.
10. **Finish the text-mode and search rules** (E11, E13, E8, E9): lone CR,
    CR before LF on write, pad bytes, unterminated last line, what
    `lineTooLong` leaves, `readBlock` in text mode; `*` expansion, `EX = 0`,
    attribute masking, deterministic `findNext` failure; the FCB field list;
    random-then-sequential rereads.
11. **Reject unsafe name bytes** (S5): bit 7 and controls, and type `$?$`.
12. **Move `argumentCount` and `argument` to the library** (M11); add
    `readAll`, no-echo line and `truncate` to §6 (M6, M8, M9).
13. **Revise the cost figures** (C2, C3, C4): files 1.5–2.0K, helper table
    0.7K, `clock` either 0.2K or a raw `DateTime`.
14. **State the storage-role position and the alignment notes** (A5, A6,
    §1.4): which gateway roles the CP/M provider implements for the vectors,
    the code mapping to tool-services names, and the five gaps to raise.
