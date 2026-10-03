# Adversarial review of the build-pipeline specifications

- Date: 2026-10-03
- Documents: object-format.md, linker.md, toolchain.md, cpm-target.md,
  build-pipeline.md (all "draft, not yet reviewed")
- Method: every byte of §13 decoded by hand; the linker walked on small
  programs through phases A to E; every figure recomputed; CP/M facts checked
  against the DRI manuals and seasip where reachable; the compiler side
  checked against the single-pass rule and the Nucleus contract.

Counts: 9 blocking, 22 major, 16 minor.

---

## Blocking

### B1. The keep-CCP option cannot reach the startup blob

**Where:** cpm-target §4 steps 2, 4 and §5; toolchain §5.3 option `B`;
object-format §3.4.

**Defect.** `startup` is a prebuilt blob in the library, "exactly one". Its
behaviour must differ under keep-CCP: subtract the CCP size, save the entry
`SP`, return through it instead of `RST 0`. The only link-time values a blob
can read are the pseudo-objects, and none carries options. Re-runnable is
detectable (`DATACOPY` size ≠ 0) but keep-CCP is not. The linker has no way
to tell startup which exit to use.

**Scenario.** `BATON MAIN [B]`. The linker sets nothing the startup can read.
Startup either always warm-boots (option ignored) or always keeps the CCP
(the program's stack goes below `$DC00` on every build and the top 2K is lost
to everyone).

**Fix.** Define pseudo-object `$0107 OPTIONS`: address = a flag word (bit 0
keep-CCP, bit 1 re-runnable, bit 2 line table present...), size = 0. Startup
does `LD HL,OPTIONS` (an `ABS16` reference) and tests bits. Alternatively let a
library carry two `startup` blobs and have a header flag select by option,
but that changes the "exactly one" rule and every check that depends on it.

### B2. The linker cannot size its object table before reading the directory

**Where:** linker §2.1 ("covers ordinals `$0000` to the highest ordinal
defined in either input"), §2.2, §4; object-format §4.1, §4.3.

**Defect.** The highest ordinal appears nowhere before the records. The
program header has no ordinal count; the trailer has only a blob count, and
ordinals "need not be dense". The linker reads forward-only, so it meets the
trailer last. The object table and the edge array are both appended during
Phase A, so neither can be placed without knowing the other's size.

**Scenario.** Program with 700 blobs, highest ordinal `$03DC`. Where does the
edge array start? Any fixed split (say object table = 8 × blob-count) is
wrong whenever a forward-declared routine or a string literal leaves a gap,
and the compiler is free to leave gaps.

**Fix.** Allocate the object table from the bottom of free memory growing up
and the edge array from the top growing down; `L-CAP-TABLES` when they meet.
Extend the object table (zero-filled) whenever a record or reference names
an ordinal above the current top. The mark stack is allocated after Phase A
in the gap. This also removes any need for a count in the header, which a
streaming compiler could not write anyway (see B7).

### B3. The stamp deduplication loses every edge of blob 0, 256, 512...

**Where:** linker §4 "Deduplication".

**Defect.** "compares the target's stamp with the current blob's sequence
number modulo 256. If equal, skip. ... When the sequence number wraps to 0,
the linker clears every stamp." Cleared stamps are 0 and the sequence number
after the clear is 0, so every target of that blob compares equal and is
skipped. The same happens for the very first blob if the table is zeroed at
start.

**Scenario.** Library blob 0 is `startup` (sequence 0). Its references to
`MAIN`, `BSS`, `REQUIRED`, `DATA`, `DATACOPY` are all dropped. `MAIN` is never
reached through startup; the entry routine survives only because Phase B
pushes it directly (M11), and every helper reached only from startup is
removed.

**Fix.** Keep sequence numbers in 1..255 and clear stamps to 0 (clear when
the sequence would reach 256, then restart at 1). Or store `seq + 1`.
Also state which entries receive stamps: pseudo-objects (`MAIN` is stored as
an edge, so `$0100` needs a stamp) and ordinals not yet defined.

### B4. Phase C cannot produce "directory order" from the tables it has

**Where:** linker §6.2 (order within a section: alignment class, library
before program, "within that, in directory order"); §2.1 (object table fields);
§1 and §7.1 ("reads the program directory twice": Phase A and once per
Phase D pass).

**Defect.** The object table is indexed by ordinal and holds kind, size,
address, first-edge, stamp. Nothing records directory position, and
directory order ≠ ordinal order whenever an explicit ordinal appears (§13:
`reset` is `$0121` but is written after `bump` `$0122`; every routine that
contains a string literal is written after the literal but numbered before
it). So Phase C has no way to assign addresses in the order Phase D will
emit them, unless it re-reads the directory, which §7.1 says it does not.

**Scenario.** Program: `count` `$0120` (bss), forward `reset` `$0121`,
`bump` `$0122` with record written first, `reset` body written last. Phase C
walking the table by ordinal places `reset` before `bump`; Phase D reading
the directory emits `bump` first. Every reference to `reset` or `bump` is
wrong by the other's size.

**Fix (choose one, and correct §1/§7.1 either way).**
(a) Phase C re-reads both directories once; the directory is small next to
the byte streams. Then the program directory is read 2 + passes times.
(b) Append a 2-byte "begin blob *n*" marker (high bit set; ordinals never
exceed `$7FFF`? they do: `$0120`–`$FFFF`, so instead use a separate
directory-order array of ordinals, 2 bytes per blob, 1.6K–6K). Phase C then
walks that array once per alignment class. Add it to the capacity table.
(c) Redefine the order within a class as *ordinal* order and make Phase D
read in ordinal order, which breaks forward-only reading; rejected.

### B5. `MAIN.$$$` is on the spool drive but must be renamed onto the output drive

**Where:** toolchain §3.2 ("Created during the build, on the spool drive
(option `S`)", listing `MAIN.$$$`); §6.1 step 3 ("Rename `MAIN.$$$` to
`MAIN.COM`").

**Defect.** CP/M rename (function 23) renames within one drive. With
`S=B` and the output on `A:`, step 3 is impossible.

**Fix.** State that `MAIN.$$$` is created on the output drive, not the spool
drive, and that `O=` may carry a drive. Add the output drive to §3.3.

### B6. The program header carries values a streaming compiler does not know yet

**Where:** object-format §4.1 header fields "stack reserve" (offset 13) and
"helper-table version the program needs" (offset 8); build-pipeline rule 6
("every file is written once, sequentially").

**Defect.** The header is the first thing written. The stack a program needs
is known at end of input (max frame, call depth, local aggregates per D8),
and the highest helper ordinal used is known at end of input. Either the
compiler seeks back (forbidden) or the fields are fiction.

**Scenario.** A program whose last routine declares a 2K local array.
Header already says stack reserve 0. `REQUIRED` is wrong by 2K and the
startup memory check passes a machine that will crash.

**Fix.** Move both to the directory trailer (grow it to 14 bytes) or add a
control record subtype 3 `LIMITS` {stack reserve u16, helper version u16}
written last. If stack reserve is a source pragma instead, say so, and say
what the compiler does about recursion.

### B7. `L-RANGE` rejects correct code: end pointers, and all RAM references on ROM profiles

**Where:** object-format §5.1 "Range" ("must, after addition, denote an
address within the target's memory"); linker §7.3 ("below the image base, or
at or above 65,536 before the modulo, unless the addend is negative and the
result is inside the target's memory").

**Defect 1.** `LD DE,table+size` (loop sentinel) and `LD HL,buffer+len`
(append cursor) denote one past the end. Under the wording they are outside
the target's memory.

**Defect 2.** On the flat-ROM class (profile block target class 3, linker
§6.1), RAM is commonly below ROM (Nucleus TEC-1 profile: image `$8000`,
writable `$2000`). Every `ABS16` to a `data` or `bss` blob is "below the
image base" and fails.

**Defect 3.** The wording "at or above 65,536 before the modulo" with a
negative addend `−1` on `BSS` of size 0 at `$FE00` yields `$FDFF`, legal by
the clause but outside any blob.

**Fix.** Define the valid range per target as `[addr(t), addr(t) + size(t)]`
inclusive at the top (half-open plus the end address), with `size` of an
alias taken from its base minus the alias offset, and pseudo-objects given
their stated sizes. Drop any mention of the image base; the check is relative
to the target, not the image. Say what `LO8`/`HI8` of an end address means
(same rule).

### B8. A streaming compiler cannot write string literals as separate blobs without buffering

**Where:** object-format §4.2 ("byte stream is the concatenation ... in
directory order"), §9 ("compiler-generated blobs, such as string literals");
build-pipeline §6.2 ("bytes have already gone to the byte stream, unless the
routine was buffered"), §6.3 fallback ("a routine too large for the buffer is
written as it is generated").

**Defect.** A literal met inside a routine is a complete blob the moment it
is seen, but its bytes cannot enter the byte stream until the routine's bytes
end (byte order = directory order, and the routine's record cannot be written
until its size and references are known). So either the routine is buffered
whole (fine while it fits) or every literal met in an unbuffered routine must
be held until the routine ends. The fallback path therefore needs an
unbounded literal buffer, which the memory plan does not mention.

**Scenario.** A 5K routine (over the 2–4K buffer) printing 40 messages.
The compiler is streaming its bytes; the 40 literals (say 1.2K) must be held
somewhere until the routine's `RET`.

**Fix.** Put literals owned by a routine inside the routine's `code` blob
(after the final transfer, referenced by self-reference with addend); the
kind table already allows "inline constants it owns". Separate `rodata`
blobs remain for top-level constants. This also removes the explicit-ordinal
churn of M12 and loses nothing: a literal's liveness equals its routine's.
Deduplication across routines (open question 4) is then a non-goal; say so.

### B9. Interrupted builds leave files that the next build will duplicate

**Where:** toolchain §6.2 ("Any that do appear can be removed with
`ERA *.$*`"), §4 phase 1, §6.1 step 1.

**Defect.** BDOS function 22 (Make) does not check for an existing name; the
CP/M 2.2 manual says the caller must delete first or duplicates occur. The
spec never says BATON erases `MAIN.$DR`, `$BY`, `$LN`, `$NM`, `$$$` before
creating them. After a crash (or a `K` build) the next build creates second
directory entries with the same names; open returns whichever entry comes
first, so the linker may read the *old* spool.

**Fix.** Phase 1 and phase 4 begin by deleting each file they will create.
State it. (Then `ERA *.$*` is only advice, not a requirement.)

---

## Major

### M1. Keep-CCP subtracts 2K from the BDOS entry and lands inside the CCP

**Where:** cpm-target §4 step 2, §5.

Word at `$0006` = `$E406` on the 62K system the document uses. `$E406 − $800
= $DC06`. The CCP begins at `$DC00`. The first push writes `$DC04–$DC05`,
which is CCP code. The subtraction must be `(word at $0006) − 6 − $800`
(= CCP base), or the profile block should carry a "CCP size" field, or
startup should read the CCP base from the warm-boot vector at `$0001`
minus BIOS offsets (unreliable). Simplest: `top = ($0006) − $806`.

### M2. Traps inside runtime helpers report the helper's address

**Where:** cpm-target §10; toolchain §8; design D11; Nucleus runtime contract
§9.4 ("Entering a shared helper must not replace the source location").

Division, narrowing, `f32` overflow, string bounds in helpers detect the
condition inside the helper and `CALL` the reporter from there. The reporter
prints "return address − 3" = an address in the helper. The lookup says "in
runtime blob div16". This is a regression against Nucleus and makes most
arithmetic traps unlocatable.

**Fix.** Either (a) helpers never trap: they return a condition flag and the
inline site calls the reporter (costs 3 bytes per call site that can trap);
or (b) define a second reporter entry `trap-from-helper` that takes the
*helper's* return address (the site of `CALL helper`, still inside the
statement) and require helpers to call it with `SP` pointing at that return
address, i.e. no pushes outstanding, or with a documented frame size.
State the reporter's calling convention either way (see M17).

### M3. The line-table sort does not fit, and is not needed

**Where:** linker §8.3; open question 1.

5 bytes per live statement. The reused edge array is 8K for the "typical"
program, so 1,600 statements. A 20K program has 3,000–5,000 statements.
Typical programs would hit `L-CAP-LINES` or the unspecified merge.

**Fix.** No sort is needed. Only `code` blobs have statements; `code`
blobs have alignment 1 and are emitted in directory order within `TEXT`;
the line stream is written in directory order with offsets ascending. So the
line table can be streamed during the unaligned `TEXT` pass of Phase D, as a
sixth open file: when the pass emits blob *n*, read its blob-lines record and
write entries `address + offset`. Blobs without lines (aligned `rodata`,
library blobs) contribute their one start entry in the same pass. The only
out-of-order entries are start entries for blobs in *other* passes
(aligned, `DATA`, `COPY`); write those in a second run and merge, or drop
them (the lookup only needs them for "inside a constant" reports). Delete
`L-CAP-LINES`. Note the image CRC in the header must then be known before
the entries: write the line table to a temporary and copy, or put the CRC in
the trailer.

### M4. `$BY`, `$LN` and `$NM` are not bound to `$DR`; link-only can link the wrong files silently

**Where:** object-format §4.2 (byte stream "has no header"), §8, §9;
toolchain §5.3 `X`.

Only the byte-stream *length* ties `$BY` to `$DR`. A `$LN` from an earlier
compile (e.g. `C` with lines, then `C` with `N`, then `X`) has a valid CRC
and produces a confidently wrong line table. Fix: a 16-bit compilation
stamp in all four headers (`$BY` gets a 16-byte header), chosen by the
compiler (R register XOR source CRC XOR byte count is adequate on 2.2,
which has no clock); `L-COMPAT` on mismatch.

### M5. The library whole-file CRC cannot be located; two byte-length fields may disagree

**Where:** object-format §7.6 ("last 2 bytes before any padding"), §7.1
offset 20, §7.3 ("Its byte-stream length field gives the byte section's
length").

Padding is `$1A`; a CRC byte can be `$1A`, so scanning back from EOF is
ambiguous. Fix: use the reserved `u32` at offset 28 as "file length to and
including the CRC". Say the header's byte-section length and the directory
trailer's length must be equal (`L-TRUNCATED` otherwise).

### M6. The 4-bit offset delta makes the "3-byte CALL" claim rarely true

**Where:** object-format §5.2 ("A `CALL` with no addend costs 3 bytes").

Delta 0–14 means consecutive references ≤ 14 bytes apart. Two calls with
argument setup between them are typically 16–30 bytes apart, so most calls
cost 5 bytes (escape). Worked numbers: `CALL a / LD HL,x / LD DE,y / CALL b`
= offsets 1 and 8: fine. `CALL a / LD HL,(v) / INC HL / LD (v),HL / LD DE,n /
CALL b` = offsets 1 and 15: escape. The directory-size estimate
(build-pipeline §8) depends on this.

**Fix.** Re-layout the control byte: bits 0–5 delta 0–62, 63 = escape; bit
6 addend follows; bit 7 "form byte follows" (absent = `ABS16`). `ABS16`
without addend within 62 bytes then costs 3 bytes; other forms 4; the
escape 5–6. Keep the first entry's delta as an absolute offset.

### M7. Phase D must consume references in step with bytes; references in `bss` must be forbidden

**Where:** linker §7.2; object-format §5.2, §4.1.

§7.2 reads as if the record (with up to 65,535 references) is read before the
bytes are copied, which needs a per-blob reference buffer (a 256-entry jump
table = 1.3K). Say explicitly: because references are sorted, the pass reads
one reference, copies bytes up to its offset, patches, reads the next; no
buffer. Separately, a `bss` record may carry references under the grammar
("bytes must lie wholly inside the blob" is satisfied by size) but has no
bytes to patch. Add: reference count of a `bss` blob must be 0 (`L-BLOB`).

### M8. Startup copy and clear loops meet size 0 and `LDIR` 64K

**Where:** cpm-target §4 steps 6–7; object-format §3.4 ("`BSS` ... size 0",
`DATACOPY` "0 if none").

One startup blob serves all option combinations. `LD BC,SIZE16(BSS); LDIR`
with BC = 0 copies 65,536 bytes and destroys the system. The classic fill
idiom `LD BC,size−1` with addend `−1` wraps to `$FFFF` for size 0. The spec
must say sizes may be 0 and that startup guards (`LD A,B / OR C / JR Z`), or
define `BSS` and `DATACOPY` as never empty (pad to 1 byte). Add both cases
to the conformance list.

### M9. Diagnostics that are missing or unreachable

**Where:** linker §4, §9; toolchain §5.3, §3.3.

| Condition | Current result |
| --- | --- |
| Output kind not in the profile's output-kinds bits | none ("where the profile allows") |
| Option `B` or `R` when the profile's option-support bit is clear | none |
| Kind `startup` in the *program* directory | undefined (object-format §3.1 says "in the blob library") |
| `ENTRY` naming a library ordinal, a non-`code` blob, or an undefined ordinal | `L-ENTRY` covers only the count |
| `ALIAS` whose base lies in the other directory | "same directory" rule has no diagnostic |
| `BANK8` under a flat profile | form 4 is defined, not reserved; no rule |
| Reference target a `bss` blob with `LO8`/`HI8` of an address ≥ 65,536 after wrap | covered by B7 fix |
| `L-UNDEFINED` | needs a "referenced" flag bit; stamps are cleared, so there is nothing to scan |
| Line table write fails after publication | partial `.LIN` left; say it is deleted |

Add `L-OPTION` and `L-OUTPUT`, extend `L-ENTRY`, `L-ALIAS`, `L-BLOB` and
`L-RESERVED` text, and add the flag bit to the object-table entry (bit in
the kind/flags byte).

### M10. Phase B contradicts §3: the entry routine is pushed directly

**Where:** linker §3 item 3 ("only through `MAIN`"), §5 step 1 ("Push every
root, and the entry routine").

Pick one. If pushed directly, a library whose startup forgets `MAIN` still
links (and B3's lost edges are masked). Recommend: push roots only; `MAIN`
resolves to the entry during marking; a library startup without a `MAIN`
reference is an `L-STARTUP` error detectable at end of Phase A.

### M11. The explicit-ordinal rule forces the compiler to track "last written ordinal", and §13 understates it

**Where:** object-format §4.1, §13.

After `reset` (`$0121`) is written last, the next record's implicit ordinal
would be `$0122` = `bump`. Every record after a forward body, and every
record after a routine containing a literal (B8), needs an explicit ordinal.
The compiler state is two words: next-free ordinal and last-written ordinal.
Say so in build-pipeline §6.2; §13 should show the record for `reset` and
the one after it.

### M12. Branch shrinking forgets the line entries and the literal problem

**Where:** build-pipeline §6.3 step 4 ("Adjust pending reference offsets and
self-reference addends").

Statement offsets recorded for the line stream during generation also move.
For a buffered routine the line entries must be held (≈4–5 bytes each) and
adjusted, which is more memory than the "5 bytes per recorded branch"
estimate admits. Also "entries flagged fixed-size" implies a flag the branch
record needs; cost 1 bit, fine, but say it. Add: line entries are buffered
per routine and adjusted in step 4; the unbuffered fallback writes them as
generated.

### M13. Name lookup for diagnostics and the map is unspecified and the name stream is in the wrong order

**Where:** linker §8.1, §9 ("where useful the ordinal and name"); object-format §9.

The name stream is written when ordinals are assigned (declaration order),
so it is neither ordinal order nor directory order. Printing the live list
in address order with names needs either the whole stream in memory
(34 bytes × 800 = 27K) or a rescan per blob. Fix: the compiler writes each
name record when it writes the blob's directory record (directory order),
and the map's live list is produced per Phase D pass by merging. Diagnostics
during Phase A can print the name by one forward scan on error.

### M14. Toolchain §6.2 contradicts §6.1 on failures after publication

"Disk or directory full ... deletes every file the build created" would
delete `MAIN.COM` and `MAIN.BAK` if the failure is in phase 6 (reports),
while §6.1 says "the published program stands". Say: files not yet
published.

### M15. Capacity arithmetic and the "58K TPA"

**Where:** linker §2.2; toolchain §7.2; cpm-target §4.

- Mark stack (2 bytes × blobs, 1.6K–6K) is missing from the capacity table.
- Toolchain §7.2 rows sum to 8.5K–10.5K, text says 9K–11K.
- "58K TPA" is `$0100`–`$E400` (58,112 bytes, 56.75 KiB) on the 62K system,
  which includes the CCP. `BATON.COM` can only be *loaded* below `$DC00`
  (cpm-target §4: 56,064 bytes) and may use the CCP's 2K only as workspace,
  which obliges BATON to exit by warm boot. Say so in toolchain §7.
- Object table from `$0000`: entries `$0000`–`$011F` (288 × 8 = 2,304 bytes)
  are almost all empty. Index library ordinals from 0 and program ordinals
  from `$0120 − 0x100` (store the base per owner) to recover 2K, or accept
  and state the waste.

### M16. The runtime ordinal range (255) is a hard ceiling with no escape

**Where:** object-format §3.2.

Baton's runtime has `u32`/`i32` (mul, div, mod, shifts, compares, conversions),
`f32` (add, sub, mul, div, sqrt, compares, four conversions, rounding),
strings, aggregates, CP/M services, ~8 trap reporters plus aliases. 120–200
ordinals is plausible; 255 is reachable within two runtime versions and the
pseudo-objects sit at `$0100`. Move pseudo-objects to `$FFE0`–`$FFFF`
(top of the space, never reached by a compiler counting up) and give the
library `$0001`–`$03FF`.

### M17. Trap reporter contract is unwritten

**Where:** cpm-target §10; toolchain §8; D11.

Must state: the site ends in a 3-byte `CALL` (never `JP cc` or `RST`), so
"return address − 3" holds for 3- and 5-byte sites; the reporter pops the
return address before any push; which registers it may destroy (none
matter); how the 5-byte form is shaped; how a conditional `CALL cc` interacts
(the address is on the stack only when taken, which is the only case that
matters). And M2 for helpers.

### M18. Command-line grammar is not implementable from the text

**Where:** toolchain §5.1–§5.3.

Unstated: that BATON parses the raw tail at `$0080` and ignores the default
FCBs (the CCP's FCB parse treats `,` and `[` unpredictably and only yields
two names); whether `[` `]` are required; separators (`,` only? spaces?);
drive letters in `O=`; user numbers; repeated options; unknown options;
case under CP/M 3 quoting; whether `T=` may combine with others; the meaning
of "`L=d` ... the drive of the first source part, then `A:`" (fallback on
open failure, or a search order?). Write a grammar.

### M19. How the compiler learns helper ordinals and the profile is unspecified

**Where:** object-format §3.2 ("numbered by the library's published helper
table"), §10; toolchain §4 ("reads the library's header and profile block ...
use the profile's values").

Say: the helper table is a generated source include compiled into BATON,
keyed by runtime identity; the compiler's header value "helper-table version
needed" is that table's version (conservative but constant, which resolves
half of B6); the compiler uses from the profile only the free-restart-vector
byte and the target class (list them). State what happens when `P=` names a
library whose runtime identity differs from the compiler's constant
(`L-COMPAT` before compiling, not after).

### M20. `.SYM` and `.HEX` formats are left to the implementer

`.HEX`: no checksum rule (two's complement of the byte sum), no EOF record
form (`:00000001FF`), no case, no statement that addresses are absolute
16-bit (type 00 only, no type 02/04). `.SYM`: open. For SID the format is
`hhhh name` lines, name up to 16 characters, CR LF, terminated by `$1A`;
verify against the SID manual and write it down.

### M21. CP/M 3 return code value and the `:` conditional are unspecified

**Where:** toolchain §5.4; cpm-target §5, §10.

"Failure" must be a value in `$FF00`–`$FF7F` for the CCP's `:` conditional to
skip; `$0001` would be reported as success. State `$FF01` for a source or
link error and `$FF02` for a trap, or similar.

### M22. Future-proofing that costs nothing now

- **Precompiled libraries (build-pipeline §9.3):** give every directory an
  ordinal base so a library's ordinals can be relocated by addition; 2 bytes
  in the header, zero for 1.0.
- **Banked (§9.2):** the object table has no bank byte and no spare bits;
  the 8-byte entry becomes 9. The Nucleus model (every bank carries the
  whole runtime) is incompatible with one ordinal per helper; decide now
  whether helpers are per-bank copies with aliased ordinals or a common
  bank.
- **Routine values (O5):** fine as references, but a value taken inside
  `data` must keep the target live; the marking rule already covers it.
  Say so.

---

## Minor

### m1. Line stream first-entry rule contradicts itself
object-format §8: the field table says the first entry without bit 7 takes
"the part of the blob's first statement", the text says "must carry a part
number". Keep the second. Also say whether parts number from 0 or 1; the
line table reserves `$FF`, so 1-based numbering with 255 parts collides.

### m2. Line table start entries duplicate real entries
§11: "Every live blob also contributes an entry at its own start address".
For a code blob whose first statement is at offset 0 there are two entries at
one address. Say the start entry is written only when no statement starts at
offset 0, or only for blobs without lines.

### m3. Image CRC "as written" is ambiguous
`.COM` is padded to a 128-byte record with zeros. Say the CRC covers the file
as stored (padding included) so trap lookup can hash the file.

### m4. Trap lookup does not know the output kind or library
`.LIN` has no field for the output file name/kind (`O=GAME.HEX`) or for the
library whose name section gives runtime names. Add both to the header.

### m5. Free-restart-vector bit 0 must be clear
`RST 0` is the warm-boot jump; the profile block only forbids bit 7.

### m6. Startup order: setting the DMA first is not needed for the memory check
Step 1 before step 3 only matters if a DMA-using call precedes step 3; BDOS
9 does not. Harmless, but the rationale in step 1 overstates it.

### m7. `K` is ignored on a source error
§6.2 "Source error ... deletes the intermediate files" even with `K`, which
defeats `K` for diagnosing the compiler.

### m8. Random read then sequential read re-reads the same record
CP/M 2.2 function 33 sets the FCB so the next sequential read returns the
record just read. An implementer skipping records with function 33 and then
continuing with function 20 will read one record twice. Note it in §7.2.

### m9. `L-FIT-NOMINAL` on CP/M 3 is weaker than it looks
`CPM3` has image limit = nominal top = `$E000`. An image that fills to the
limit leaves no stack and gets only a warning.

### m10. `ERA *.$*` erases a running `$$$.SUB`
If the spool drive is `A:` the suggested clean-up aborts any SUBMIT in
progress. Suggest `ERA MAIN.$*`.

### m11. "Alignment classes first ... paid as few times as possible" overclaims
Descending alignment order is a heuristic. `TEXT` begins at startup's
unaligned end, so the first page-aligned blob always pays up to 255 bytes.
Say "once per class at most".

### m12. §7.1 "the only exception to forward-only reading" is false after Phase E
Phase E re-reads `$DR` (toolchain §4 phase 6) and `$LN`. Count the reads.

### m13. The library trailer duplicates the header's blob count semantics
§7.3 reuses the program trailer; its blob-count field must equal the number
of library blob records, and the CRC "covers the directory section only":
say from the first record byte, since there is no header in the section.

### m14. The serial-number claim
cpm-target §3.2 "the first push lands on serial-number bytes, which nothing
checks after boot". Harmless under warm-boot exit; under keep-CCP the stack
is below the CCP anyway. Unverified; see below.

### m15. CP/M 3 `$C9` rule is trivially satisfied
Startup is at `$0100` and begins with code; the rule is worth keeping only as
a conformance check on the library.

### m16. §13 decodes correctly
All bytes verified: `03 02 00 00`, `08 22 01 11 00 03`, `01 20 01`,
`04 20 01`, `0A 21 01`; opcodes and the 17-byte length are right. Note that
`JP reset` is a tail call returning to `bump`'s caller, which is fine but
differs from what a reader of the source expects.

---

## Hand-constructed cases (results)

- **`ABS16` straddling a 128-byte record in input and output:** encodable;
  the pass cursor handles it as §7.5 says. Must be in the conformance suite
  for *both* the directory (a reference entry split across records) and the
  byte stream.
- **First reference at offset ≥ 15:** `control = $0F | form<<5`, then `u16`
  offset: 5 bytes without addend, 7 with. Unambiguous.
- **Two references > 14 bytes apart:** escape with absolute offset; the
  "must be at least 1" rule applies to the absolute value too; say so.
- **255+ references:** `FF` then `u16` ≥ 255. A count of `FF 00 00` (0) or
  `FF FE 00` (254) is invalid; add to `L-BLOB`.
- **Alias referenced from an otherwise dead blob:** correct; the edge is to
  the alias ordinal, the dead referrer is never popped, so nothing is marked.
- **Forward-declared routine:** correct given M11.
- **Explicit followed by implicit:** implicit = explicit + 1; unambiguous.
- **`$FF` vs headers:** blob headers have kind 0–4 in bits 0–2; control
  headers have bits 0–2 = 110; `$FF` has 111. No collision for any subtype
  0–31 (`$06`–`$FE`) or any blob flag combination.
- **Stale stamps:** handled by the wrap-clear only if B3 is fixed.
- **Pseudo-object references:** `SIZE16` of `FREE` is 0; `ABS16` of
  `REQUIRED` fine; reference to `$0107` → `L-REFERENCE`. OK.
- **Determinism:** holds once B4 defines the order; add "ties between
  zero-reference blobs" if option (b) is chosen.

---

## Unverified facts

| Claim | Confidence | Basis |
| --- | --- | --- |
| CCP leaves 7 free stack levels on entry | High | CP/M 2.2 Interface Guide §5 ("eight-level stack ... leaving seven levels"), via search excerpt |
| BDOS switches to its own stack on entry (so one BDOS call fits) | High | CP/M 2.2 BDOS source (`entsp`), recalled |
| `RST 0` warm-boots | High | `RST 0` = call `$0000` = `JP WBOOT`; the pushed word is irrelevant |
| BDOS 108 values; `$FF00`+ unsuccessful; CCP zeroes it per load | High | seasip bdos.html; CP/M 3 Programmer's Guide via search |
| Erasing `$$$.SUB` aborts SUBMIT under 2.2 | High | CP/M 2.2 manual §1 (quoted in search) |
| `$$$.SUB` is always on drive A: | Medium | recalled from CCP source |
| Two FCBs may read one file concurrently | High | each FCB carries its own extent/record state |
| CP/M 2.2 rename does not check for an existing new name | Medium–high | BDOS source recalled; seasip is silent; CP/M 3 is documented to check |
| Make (22) creates duplicates if the name exists | High | CP/M 2.2 manual function 22 ("a preceding delete operation is sufficient") |
| `BAD LOAD` when a record would reach the CCP; exact comparison | Medium | CCP source compares the next DMA page with the CCP page; whether the test is `<` or `≤` on the high byte affects the 56,064 figure by at most 128 bytes |
| CP/M 3 loader treats a first byte of `$C9` as an RSX header | High | seasip rsxrec.html |
| Debugger margin "about 5K" | Medium | DDT ≈ 4.5–5K; SID ≈ 8K, ZSID larger; 5,120 is low for SID |
| Z-System `GO` re-enters at `$0100` without reloading | High | Z-System User's Guide via search |
| Random read sets the FCB so the next sequential read returns the same record | High | seasip bdos.html F_READRAND |
| Amstrad CP/M uses IM 1 (`RST 38h`) | Medium–high | recalled |
| Nothing checks the BDOS serial bytes after boot | Low | the 2.2 CCP/BDOS serial check exists at boot; unknown whether a `RET` to the CCP after corrupting `$E400`–`$E405` is harmless on every build of 2.2 |
| CP/M 3 `$0050` holds the load drive | High | CP/M 3 Programmer's Guide |
| CRC-16/CCITT-FALSE check value `$29B1` | High | standard |
| Warm boot reloads ≈ 5.5K (CCP 2K + BDOS 3.5K) | High | standard sizes |

---

## Questions for the designer

1. How does startup learn link-time options (B1): a pseudo-object flag word,
   or alternative startup blobs?
2. Which of B4's fixes: a Phase C directory read, or a directory-order array
   in memory?
3. Where do stack reserve and helper-table version live (B6): trailer,
   control record, or a source pragma? What is the stack reserve for a
   recursive program?
4. Are string literals inline in their routine (B8), or is the routine
   buffer made mandatory with a hard routine-size limit?
5. Pseudo-object placement and the runtime ordinal ceiling (M16): move to the
   top of the ordinal space now?
6. Do helpers trap, or return flags for the site to trap (M2)?
7. Is the line table streamed in Phase D (M3), or does `L-CAP-LINES` stay?
8. Reference control-byte layout (M6): keep 4-bit deltas or re-layout?
9. Which drive holds `MAIN.$$$` and may `O=` carry a drive (B5)?
10. Compilation stamp across the four spool files (M4): yes or accept the
    risk and document `X` as unsafe after a `N` compile?
11. Output kinds beyond `.COM` in 1.0 at all? If `.BIN`/`.HEX` stay, the HEX
    checksum and the ROM-profile range rule (B7) must be written.
12. Should `L-FIT-NOMINAL` be an error when `REQUIRED > image limit` on
    CP/M 3, where limit = nominal top?
13. Is a `data` blob allowed in the library (runtime state)? The spec implies
    yes; the re-runnable copy then restores runtime state too, which is the
    desired behaviour, but say it.
14. Names: written in directory order (M13), or dropped from diagnostics?
