# Second adversarial review of the build-pipeline specifications

- Date: 2026-10-03
- Documents: object-format.md, linker.md, toolchain.md, cpm-target.md,
  build-pipeline.md (all "revision 2" / "revision 4"), design-decisions.md
  D11 and D12
- First review: [2026-10-03-linker-spec-review.md](2026-10-03-linker-spec-review.md)
- Method: every first-review finding checked against the revised text; §13
  re-decoded byte by byte under the new reference encoding; several reference
  entries encoded and decoded by hand; the linker walked through Phases A to E
  on small programs with aliases, aligned blobs, separate `DATA` and more than
  255 records; every figure recomputed; every cross-reference followed.

Verdicts: 39 fixed, 5 partly fixed, 1 not fixed, 2 fixes that introduce a new
problem (47 findings). New: 4 blocking, 11 major, 15 minor.

---

## 1. Verdicts on the first review

| ID | Verdict | Notes |
| --- | --- | --- |
| B1 | Fixed | `OPTIONS` `$FFE7` (object-format §3.4, §3.5); startup reads it (cpm-target §4); exempt from the range rule's first condition. `LO8`/`HI8` of it give the flag bytes, which is the useful form (`LD A,n` then bit tests). |
| B2 | Fixed | Library table sized from header offset 36; program table grows up, edge lists grow down, `L-CAP-TABLES` when they meet (linker §2.1). The walk direction of a downward-grown list is unstated: see NM3. |
| B3 | Fixed | Sequence 1–255, clear to 0 when the count would reach 256 (linker §4.2). Pseudo entries and alias entries carry stamps. Conformance case added (§11). |
| B4 | Fix introduces a new problem | Phase C now re-reads the directories once per pass (§6.3), and §10 counts it. But the table entry has no alignment field, so the linker cannot know which passes exist without an extra read, and the `START`/`BSS` passes make the "three reads, one pass" claim false. See NB4. |
| B5 | Fixed | `MAIN.$$$` and `MAIN.$LT` on the output drive; `O=[d:]name.type` (toolchain §3.2, §5.3). |
| B6 | Fixed | `LIMITS` subtype 3 after the last blob record (object-format §6); header fields are all known at start (§4.2). The stack-reserve formula is weak: see NM9. |
| B7 | Fix introduces a new problem | The rule itself is right (object-format §5.1): target-relative, end pointer allowed, pseudo regions and `OPTIONS` exempt. But for an alias target the check needs the base's size, and linker §2.1 overwrites the alias's base ordinal with its address in Phase C, so Phase D cannot compute `size(alias)`. See NB2. |
| B8 | Fixed | Literals in the routine's `code` blob (object-format §3.1), literal buffer with inline fallback (build-pipeline §6.4). The fallback's `JR` cannot skip a literal longer than 127 bytes: see NM6. |
| B9 | Fixed | Delete before create (toolchain §3.2). |
| M1 | Fixed | `($0006) − 6 − CCP size` (cpm-target §3.2); CCP size in the profile block. |
| M2 | Partly fixed | Helpers jump with SP restored (cpm-target §10.2). Wrong for a helper reached by tail call from compiled code, for a trapping helper called from another helper, and for `RST`-entered helpers. See NB3, Nm11. |
| M3 | Partly fixed | Streamed in Phase D with the CRC in the trailer (linker §7.6, object-format §11). But the header needs the part count and names before any entry, and the line stream lets part records appear anywhere (NB1); `bss` blobs get entries in §11 but none in §7.6 (NM4); `COPY` would emit duplicates (NM1). |
| M4 | Fixed | Stamp in all four headers; `L-STAMP`. Derivation is weak: see NM5. |
| M5 | Fixed | File length at offset 28; CRC is the 2 bytes ending there (§7.1, §7.6); trailer and header lengths must agree (§7.3). |
| M6 | Fixed | 6-bit delta, bit 6 addend, bit 7 form byte (§5.2). Encodings verified by hand (Section 2 below). The "absolute offset" field is a 16-bit delta for later entries; the name misleads (Nm1). |
| M7 | Fixed | In-step patching (linker §7.2); `bss` with references is `L-BLOB` (§4.3, object-format §3.1 rule 6). |
| M8 | Fixed | Sizes may be 0; startup tests before `LDIR` (object-format §3.4, cpm-target §4); size-0 blobs invalid. |
| M9 | Fixed | `L-OPTION`, `L-OUTPUT`, extended `L-ENTRY`, `L-ALIAS`, `L-BLOB`, `L-RESERVED`; referenced bit for `L-UNDEFINED`; partial reports deleted. The referenced/defined scan has a new hole for aliases: NM2. |
| M10 | Fixed | Roots are startup and flagged blobs only; `L-STARTUP` when startup lacks `MAIN` (linker §3). |
| M11 | Fixed | Two tracked ordinals (object-format §4.2, build-pipeline §6.2); §13 shows `reset` and describes the record after it. |
| M12 | Fixed | Line entries buffered and adjusted (build-pipeline §6.5); fixed-size flag named (§6.3). Entry size is understated (Nm9). |
| M13 | Fixed | Names in directory order (object-format §9); map by repeated passes (linker §8.1); one scan on a diagnostic (§8.3). `.SYM` "address order" with aliases is not achievable this way (Nm5). |
| M14 | Fixed | "not yet published" (toolchain §6.2). |
| M15 | Fixed | Mark stack counted (linker §2.2); 9.7K fixed total sums; 56.75K and 47K agree in both documents; CCP-workspace rule stated (toolchain §7.1); tables indexed from each range's base. |
| M16 | Fixed | Pseudo-objects at `$FFE0`; library `$0001`–`$03FF`; limits table right (64,480). |
| M17 | Partly fixed | The contract exists (cpm-target §10.2) and covers `CALL cc` and the 5-byte form. Same gaps as M2. |
| M18 | Partly fixed | Grammar written (toolchain §5.2), raw tail parsed, FCBs ignored, repeats and unknowns rejected. Gaps: `ws` between parts and `[` is mandatory by the grammar but spaces are "allowed" inside brackets only; `filename`, `drive` and `hex` are undefined terminals (`L=B` or `L=B:`?); `O=GAME` without a type has no stated default; whether `O=` renames the intermediate files is unstated, which matters for `X` (NM8). |
| M19 | Fixed | Helper table compiled in; key table and compatibility rule (object-format §10); what the compiler takes from the profile (toolchain §3.1). |
| M20 | Fixed | HEX fully specified (linker §7.5); `.SYM` specified and honestly marked unverified (§8.2). |
| M21 | Fixed | `$FF01`–`$FF03` in both documents. The two documents give `$FF03` different meanings (Nm13). |
| M22 | Partly fixed | Ordinal base field added. The banked question (bank byte, per-bank helpers) is deferred without a decision, and the 8-byte table entry now has no spare bit at all. Routine values in `data` keeping targets live is still not stated. |
| m1 | Fixed | First entry carries a part; parts 0–254 (object-format §8). |
| m2 | Fixed | Start entry only for blobs that don't start with a statement (§11). |
| m3 | Fixed | CRC over the file as stored. Wording says "zero padding", which is wrong for `.HEX` (Nm8). |
| m4 | Fixed | Output and library names in the header (§11). |
| m5 | Fixed | Bits 0 and 7 must be clear (§7.2). |
| m6 | Fixed | Step 1's rationale is now the command tail (cpm-target §4). |
| m7 | Fixed | "unless `K`" on source error (toolchain §6.2). |
| m8 | Fixed | linker §7.2. |
| m9 | Not fixed | `CPM3` image limit = nominal top = `$E000` (cpm-target §2); `L-FIT-NOMINAL` stays a warning (linker §6.4). First-review question 12 is unanswered. |
| m10 | Fixed | `ERA MAIN.$*` (toolchain §6.2). |
| m11 | Fixed | "at most once at its start" (linker §6.2). |
| m12 | Fixed | linker §1 and §10 count reads. The counts themselves are wrong (NB4). |
| m13 | Fixed | object-format §7.3. |
| m14 | Fixed | cpm-target §3.2 ties the harmlessness to the warm-boot exit. |
| m15 | Fixed | Conformance check (cpm-target §4). |
| m16 | Fixed | §13 re-verified under the new encoding; every byte is right (Section 2). |

---

## 2. Hand checks that passed

- **§13.** `03 02 00 00` = `bss`, implicit `$0400`, size 2. `08 02 04 11 00 03`
  = `code`, explicit `$0402`, size 17, 3 references: `01 00 04` offset 1 →
  `$0400`; `04 00 04` offset 5 → `$0400`; `0A 01 04` offset 15 → `$0401`.
  `08 01 04 07 00 01` = `code`, explicit `$0401`, size 7; `04 00 04` offset 4.
  The 17 bytes `2A 00 00 23 22 00 00 11 64 00 B7 ED 52 C0 C3 00 00` decode as
  listed; operands sit at offsets 1, 5 and 15. The ordinal commentary (`$0401`,
  `$0403`, `$0402`) is right.
- **Reference encodings.** `LO8` with addend −1 at delta 3: `C3 01 00 04 FF FF`
  (6 bytes). First entry at offset 200: `3F C8 00 00 04` (5 bytes). Delta 62:
  `3E 00 04`. `SIZE16` at escape delta 63: `BF 3F 00 03 00 04`. All match the
  cost table. Control values never collide with the trailer or control headers.
- **Layouts.** Program header 20 bytes, trailer 12, library header 40, profile
  block payload 20. `$06 | subtype<<3` ranges `$06`–`$FE`; `$FF` is free.
- **Capacity rows.** 19.5K, 43.4K, 64.8K: the rounding to 20K, 44K, 66K is
  fair. `$E406 − $0100` = 58,118 = 56.76K; less 9.7K = 47.1K. Both documents
  say 47K.
- **Stamp deduplication.** Walked for blobs 1, 255, 256 (clear, then seq 1)
  and 257 with repeated, aliased and pseudo targets: no first reference is
  dropped and no duplicate survives.
- **Trailer marker.** Entries are read in 5-byte frames. A frame of five `$FF`
  needs address `$FFFF`, part `$FF` and ordinal `$FFFF`; the last is a reserved
  pseudo-ordinal, never a blob. So the marker is unambiguous even without the
  `$FFFF` placement rule (Nm3).
- **Literal fallback and shrinking.** The `JR` over an inline literal spans no
  shrinkable `JP`, so its displacement is stable whether or not it is recorded;
  the self-reference's site offset and addend both move and both are adjusted
  in step 4. Correct, apart from NM6.
- **Publication windows.** Steps 1–4 and the two stated windows are right. A
  window between step 2's delete and rename (with `Z`: neither `.COM` nor
  `.BAK`) is implied but not stated; harmless, `.$$$` survives.

---

## 3. New findings

### Blocking

#### NB1. The line-table header cannot be written while streaming

**Where:** object-format §8 ("A part record precedes every blob-lines record
that uses its part"), §11 (header: part count, then part names, then
entries); linker §7.6.

**Counterexample.** Parts `MAIN.BTN` and `UTIL.BTN`. The compiler writes the
part record for part 1 just before the first `UTIL` routine's blob-lines
record, halfway through the stream. The linker writes the line-table header
(part count, part names) before its first entry, during the `START` pass,
having read nothing of the line stream. It cannot know the count or the second
name. Forward-only I/O forbids patching the header afterwards.

**Fix.** The parts are all on the command line, so the compiler knows them
before it compiles anything. Require every part record to precede the first
blob-lines record, in part order, and have the linker copy them into the
header in Phase A (or at the start of Phase D). If source-named parts
(toolchain open question 1) are ever adopted, move the part names into the
line-table trailer instead.

#### NB2. `L-RANGE` for an alias target cannot be computed after Phase C

**Where:** linker §2.1 ("address: Assigned in Phase C; for an alias before
Phase C, its base ordinal"; "size: for an alias, its offset"), §7.3;
object-format §3.3 ("an alias's size is its base's size minus its offset").

**Counterexample.** Library blob `strcpy` (ordinal `$0010`, size 40) with alias
`strcpy-tail` = `$0010 + 24` (ordinal `$0011`). Program reference
`ABS16 $0011 + 20`. The range rule needs `size($0011) = 40 − 24 = 16`, so the
value is 4 past the end and must be `L-RANGE`. In Phase D the alias entry holds
address `base + 24` and size 24 (its offset); the base ordinal was overwritten
in Phase C. The linker can only compute `addr + 20 ≤ addr + 24`, which passes.

**Fix.** In Phase C, when an alias takes its address, replace its size field
with `base.size − offset`. The offset is not needed afterwards (the map prints
addresses). State this in §2.1 and §6.3.

#### NB3. The reporter contract gives a wrong site for tail calls and nested helpers

**Where:** cpm-target §10.2; D11; build-pipeline §6.6; object-format §13
(`JP reset`, "a tail call").

**Counterexample 1, tail call.** The compiler emits tail calls (§13). Routine
`f` ends with `JP div16` (tail call to a trapping helper). `div16` detects
zero, restores SP to its entry value and jumps to the reporter. The top of the
stack is the return address of whoever called `f`; "minus 3" is the `CALL f`
in a different routine and statement. The report is silently wrong.

**Counterexample 2, helper calling helper.** `f32div` calls `div32`, which
traps. `div32` restores its own entry SP; the top of the stack is a return
address inside `f32div`. The report says "inside runtime blob `f32div`":
exactly the M2 regression, one level up.

**Fix.** Add to §10.2: (a) compiled code never tail-calls a helper that can
trap, and never tail-calls through a helper to one; (b) a helper that can trap
is entered only by a 3-byte `CALL` from compiled code, or by a tail `JP` from
another helper that has first restored its own entry SP; a helper that needs a
trapping helper as a subroutine takes a condition flag instead. Add a
conformance check that every library helper's trap path reaches the reporter
with SP equal to the program's call frame. State in build-pipeline §6.6 that
tail calls apply to program routines only (or to non-trapping helpers).

#### NB4. The linker cannot know which placement passes exist, and the read counts are wrong

**Where:** linker §2.1 (table entry has no alignment field), §6.2 ("one pass
for each alignment class that has live blobs"), §6.3, §7.1 ("its whole image
is one pass"), §10 ("A typical build without a map reads each directory three
times").

**Counterexample.** After Phase B the linker holds, per ordinal, kind, flags,
size and edges. Whether any *live* blob has alignment 256 is not in any table:
alignment is in the record header, which Phase A read and discarded, and
liveness is known only after Phase B. To decide whether to run the 256-byte
pass the linker must read the directories once more, or run all eight class
passes regardless (16 extra directory reads across C and D).

Independently, the passes in §6.2 are per section. Phase C must place `START`
(library directory), `TEXT` (both), and `BSS` (both: library `bss` is allowed),
in that order, and `BSS` addresses depend on `TEXT`'s end. That is three reads
of the library directory in Phase C alone for the "typical" program, and the
`startup` blob is only first in `TEXT`'s read order if it is first in the
library directory, which nothing requires.

**Fix.** Three changes. (1) Record alignment classes during Phase A: a 5-bit
mask per section of classes present among *defined* blobs is not enough (dead
blobs), so either store the alignment code in the table (the stamp can shrink
to 5 bits, with clears every 31 records, freeing 3 bits), or have Phase B set a
per-section class mask when it marks a blob (this needs alignment in the
table too). Storing the 3-bit code in the table is simplest. (2) Place in one
directory read per alignment class with a cursor per section, assigning
section-relative offsets; then add each section's base to its blobs in a
table scan by ordinal, which reads no file. `START` folds into the first pass
if the `startup` blob is required to be the first record of the library
directory; add that to object-format §7.3 and `L-STARTUP`. (3) Restate §10
with the real counts: Phase C = classes present + 1 (unaligned), Phase D the
same minus any class with no stored blobs, plus one for `COPY` when separate.
Correct build-pipeline §8 ("at least twice") to match.

### Major

#### NM1. The `COPY` pass is unspecified

**Where:** linker §6.1, §7.1, §7.6, §10; object-format §3.4 `DATACOPY`.

**Counterexample.** Re-runnable program, `data` blob `cursor` holding the
address of a `bss` buffer (an `ABS16` inside a `data` blob) and a `data` table
aligned to 16. In the `COPY` pass: (a) is `cursor`'s reference patched with the
`DATA` address (right) or with the `COPY` address (wrong)? Unstated. (b) The
alignment padding inside `COPY` must mirror `DATA`'s, which depends on `DATA`'s
absolute addresses, not `COPY`'s cursor; §6.2's "rounded up to the blob's
alignment" applied at the `COPY` cursor gives a different layout and a wrong
`DATACOPY` size. (c) The byte stream is read twice for `data` blobs, but §10
says "Phase D once in total". (d) §7.6 "in each pass, for every live blob ...
writes a start entry" produces a second entry per `data` blob at its `COPY`
address, against §11's "one entry".

**Fix.** Define `COPY` as a byte-for-byte image of the `DATA` section
(padding and patched references identical), produced by repeating the `DATA`
passes with the output cursor at the `COPY` base and all values computed from
`DATA` addresses; no line-table entries; count the extra byte-stream read in
§10.

#### NM2. An `ALIAS` record does not set the defined bit, so every referenced alias is `L-UNDEFINED`

**Where:** linker §4.1 ("fill the alias's entry with the alias bit, the base
ordinal and the offset"), §4.3 (`L-UNDEFINED` = referenced and not defined).

**Counterexample.** Library alias `$0011`, referenced by a program blob. Phase
A sets its referenced bit on the reference and the alias bit on the `ALIAS`
record; nothing sets defined. The end-of-Phase-A scan reports `L-UNDEFINED`.
Every library with an alias fails to link.

**Fix.** "fill ... and set the defined bit" for `ALIAS`, and say that filling
never clears the referenced bit or the stamp set by an earlier referrer.
Then "defined twice" also catches an alias and a blob sharing an ordinal.

#### NM3. The direction of an edge list is unstated

**Where:** linker §2.1 (edge lists "grow downwards"; "edges: address of the
blob's first edge; the list ends with ordinal `$0000`"), §5.

**Counterexample.** Phase A appends targets for blob *n* at `top−2`, `top−4`,
..., then the terminator. If "first edge" is the highest address, marking must
walk by decrementing; if the implementer writes the terminator first and the
field points at the lowest address, it walks by incrementing. Either works,
but an implementation of §5 reading "walk its edge list" and assuming ascending
addresses with the first layout reads the previous blob's edges and the
terminator at once, marking nothing.

**Fix.** State the layout: the edges field holds the address of the most
recently appended (lowest) target or of the first (highest), and the walk
direction accordingly. Suggest: write the terminator first, then targets
downward, set the field to the last target written, walk upward to the
terminator. Then a blob with no references can have field 0 and no terminator.

#### NM4. `bss` blobs have line-table entries in §11 and none in §7.6

**Where:** object-format §11 ("Each live blob that does not start with a
statement contributes one entry"); linker §7.6 (entries written "as it emits
the blob"; `bss` is never emitted).

**Fix.** Say that only blobs in stored sections contribute entries, and that an
address above the stored image is reported as "not in the image". Rename or
reword the "no blob at `$FFFF`" check, which currently names `L-FIT-IMAGE` for
a `bss` placement outside the image (see Nm3).

#### NM5. The compilation stamp can repeat exactly when it must not

**Where:** object-format §4.1 ("CRC of the first source part's first 128-byte
record, combined with the Z80's `R` register sampled while waiting for that
record").

**Counterexample.** The case M4 protects against is: `C`, then `C` with `N`,
then `X`. The source is unchanged, so the CRC term is identical. `R` has 7
bits and the BDOS read is a synchronous call; on a RAM disk or an
interrupt-driven BIOS its value on return is the same every run. The stale
`MAIN.$LN` then has the same stamp as the new `MAIN.$DR` and is linked.

**Fix.** Before deleting the old `MAIN.$DR`, read its stamp and use `old + 1`
(skipping 0); use the CRC-and-`R` value only when no old directory exists.
This guarantees the one property needed: the stamp differs from every file
that could be left over.

#### NM6. The inline-literal fallback cannot jump over a literal longer than 127 bytes

**Where:** build-pipeline §6.4 ("preceded by a `JR` over them").

**Counterexample.** Literal buffer full; a 200-byte string literal met. `JR`
reaches +127 from the following byte.

**Fix.** Use `JP` with a self-reference (3 bytes) when the literal exceeds 127
bytes, or state the literal size limit. Also give the literal buffer a size
estimate in §6.3's cost list, since it is now on the critical path.

#### NM7. Keep-CCP changes the usable top but not the fit check

**Where:** linker §6.4 (`L-FIT-NOMINAL` against the nominal top; "On CP/M 2.2
`REQUIRED` may lie above the image limit, because a running program may use
the CCP's memory"); cpm-target §3.2.

**Counterexample.** `BATON MAIN [B]`, `REQUIRED = $E000`. Nominal top `$E406`:
no warning. Usable top under keep-CCP is `$DC00`: the program refuses to start
on every typical 62K machine.

**Fix.** With option `B`, compare `REQUIRED` with the image limit (the CCP
base) and make that an error or at least the warning.

#### NM8. `O=` and the names of intermediate files

**Where:** toolchain §3.2 (table shows `MAIN.$DR` etc.), §3.3 ("The base name
is the first part's, unless option `O` names another"), §5.3 `X`.

**Counterexample.** `BATON MAIN [O=GAME.COM]` then `BATON MAIN [X,O=GAME.COM]`.
Are the intermediates `MAIN.$DR` or `GAME.$DR`? The second command must find
them. Also `BATON MAIN [O=B:GAME]`: is the type `.COM` or an error?

**Fix.** Intermediates always take the first part's name and the spool drive;
outputs take `O=`'s name and drive; a missing type in `O=` means `.COM`.
Define the terminals: `drive = letter`, `filename = [drive ":"] name ["." type]`,
`hex = 1*4 hexdigit`; make `ws` before `[` optional.

#### NM9. The stack reserve is a guess presented as a requirement

**Where:** object-format §6 (`LIMITS`: "the profile's default stack reserve
plus the largest activation frame"), §3.4 `REQUIRED` ("the lowest acceptable
top of memory"), cpm-target §4 step 3; toolchain §5.3 `STACK=`.

**Counterexample.** `main → a → b → c`, each with a 300-byte frame, no
recursion. Reserve = 512 + 300 = 812; actual need ≈ 1,200 plus runtime
helpers' stack. The startup check passes a machine that then traps on
activation capacity (if that check exists) or crashes. Separately, `STACK=n`
is consumed by the compiler, so under `X` it has no effect.

**Fix.** Either compute the bound the single pass can compute (sum of all
frames, pessimistic) or state plainly that `REQUIRED` is a lower bound and the
runtime's activation-capacity check is the guard. Define that check (what it
compares `SP` with; `FREE` is available as a pseudo-object). Let the linker,
not the compiler, apply `STACK=n` as a maximum with the `LIMITS` value, so it
works under `X`. Define the recursion flag's rule: set when a routine calls
itself or any routine declared forward and not yet defined.

#### NM10. No capacity check for the mark stack

**Where:** linker §2.1 ("Mark stack ... in the gap ... after Phase A"), §5.

**Counterexample.** Tables and edges leave a 200-byte gap; 900 blobs are live
along a long chain. The stack overflows into the edge lists.

**Fix.** At the end of Phase A, require `gap ≥ 2 × (blob records)` (both
trailers give the counts), else `L-CAP-TABLES`.

#### NM11. An unbuffered routine's pending reference list is unbounded

**Where:** build-pipeline §6.2 ("one routine's pending list at a time, about
5 bytes per reference"), §6.3 ("A routine too large for the buffer is written
as it is generated"); open question 4.

**Counterexample.** A 6K routine, over the routine buffer, with 700 references
(every call, every global, every literal). Its bytes stream out, but its
record, with all 700 references sorted and encoded, is written only at the
routine's end, so 3.5K of pending references are held with no stated limit
and no fallback. The line entries have a fallback (§6.5); the references do
not.

**Fix.** State a per-routine reference limit and the error (the directory
format allows 65,535; the compiler allows what its buffer allows), or spill
the pending list to the directory stream as a provisional record. Count the
pending list in the memory plan.

### Minor

#### Nm1. The "absolute offset" field is a delta

object-format §5.2: for every entry after the first, the escaped `u16` is "the
distance from the previous entry's offset", so it is a 16-bit delta, not an
absolute offset. Rename it "wide delta" or make it absolute (the first review's
hand case assumed a delta; §13 doesn't exercise it). Either is fine; say which.

#### Nm2. Line-stream deltas: "at least 1" contradicts "may share an offset"

object-format §8 says offsets are "measured as in Section 5.2" (later deltas
≥ 1) and that "two entries may share an offset only if they are in different
parts". Allow delta 0 explicitly when the part changes.

#### Nm3. The `$FFFF` rule is redundant and misnamed

object-format §11, linker §6.4. A start entry has part `$FF` and an ordinal;
ordinal `$FFFF` is reserved, so five `$FF` bytes never form an entry. Drop the
rule, or keep it and stop calling a `bss` placement failure `L-FIT-IMAGE`.

#### Nm4. A trap in a routine's prologue reports "a blob without source"

object-format §11: a `code` blob whose first byte is not a statement gets a
start entry with part `$FF`. The activation-capacity trap lives in the
prologue. Use the routine's first statement's part and source offset for a
`code` blob's start entry, so the report names the routine's line.

#### Nm5. `.SYM` in address order with aliases

linker §8.2: aliases are listed "in address order" but the in-step walk meets
an `ALIAS` record anywhere in the directory. SID does not need sorted symbols;
drop "address order" or append aliases after the blobs.

#### Nm6. Stale text in build-pipeline

§8 "reads it at least twice" (now at least three); §10 item 2 cites linker
§11 (open questions are §12); §10 item 3 "line table memory" is no longer an
open question; §11 lists revision 4 before revision 3; §1 "reachable from the
program's entry" (from the roots).

#### Nm7. Library references to program ordinals and table bounds

linker §4.3: nothing forbids a library reference to `$0400`+ or to a library
ordinal above the header's highest (which indexes past the fixed library
table). Add both to `L-REFERENCE`.

#### Nm8. Image CRC wording for `.HEX`

object-format §11 "including the zero padding"; linker §7.5 pads `.HEX` with
`$1A`. Say "including whatever padding the output kind uses".

#### Nm9. Line entries are 5 bytes, not "about 4"

build-pipeline §6.5: part, code offset, source offset = 5 bytes.

#### Nm10. `T=` with `P` and `L`

toolchain §5.2 allows `P` with `T=`, but the `.LIN` header names the library.
Say which wins, or allow only `L` (where to find the named library).

#### Nm11. `RST`-entered helpers and the reporter

cpm-target §8 permits `RST` helpers under profiles with free vectors; §10.2's
"minus 3" is wrong for a return address pushed by `RST` (1-byte instruction).
State that `RST`-entered helpers never trap, or that the site rule is "minus 1"
for them.

#### Nm12. Stream trailers must still be verified

linker §7.3, §7.6: the line stream is consumed in step during one pass; say
its trailer CRC is checked when it ends, and that "longer than its trailer
says" for the byte stream is detected at 128-byte granularity only.

#### Nm13. `$FF03` means two things

toolchain §5.4 (`BATON`: disk error) and cpm-target §5 (program: not enough
memory). Different programs, same code; confusing in a `SUBMIT` log. Use
distinct values or note the overlap.

#### Nm14. Phase A table growth triggers

linker §2.1: the program table grows on "definitions or reference targets".
`ENTRY` ordinals and `ALIAS` bases also index the table; say so.

#### Nm15. `L-FIT-NOMINAL` on CP/M 3 (m9, unresolved)

Image limit equals nominal top; an image filling to the limit gets only a
warning. Answer first-review question 12.

---

## 4. Implementability for a single-pass compiler

- **`LIMITS`:** implementable. Largest frame is a running maximum; the
  recursion flag needs the rule in NM9.
- **`ENTRY`:** write it when `main`'s ordinal is assigned (declaration or
  forward); fine.
- **Line and name streams in directory order:** fine, since both records are
  written with the blob's directory record and the name is in the symbol table.
  Part records must all be written first (NB1).
- **Explicit ordinals:** two words, as specified.
- **Reference lists sorted by offset:** come out sorted naturally, provided
  literal self-references are recorded at the load site and their addends
  patched at routine end; say that no sort is needed.
- **Memory the specifications do not count:** the symbol table (not in any
  budget); the literal buffer (unsized); the pending reference list, unbounded
  for an unbuffered routine (NM11); the branch records and line entries
  (bounded by the routine buffer, but the three per-routine lists peak
  together); label table per routine; six files during compilation (source,
  library during phase 1, `$DR`, `$BY`, `$LN`, `$NM`) at about 164 bytes each.
  toolchain §7.2 says "Compiler code: not yet known" but lists no compiler
  workspace rows at all; add them as estimates.

---

## 5. Questions for the designer

1. NB4: alignment code in the table (shrinking the stamp to 5 bits), or a
   per-section class mask gathered in Phase B? And is `startup` required to be
   the first library record so `START` folds into the first pass?
2. NB3: are tail calls to runtime helpers allowed at all? If yes, which
   helpers trap?
3. NM9: is `REQUIRED` a guarantee or a hint? Does the activation-capacity
   check exist in 1.0, and what does it compare against?
4. NM5: stamp from the previous `$DR` plus one, or accept the risk?
5. NM1: is `COPY` an exact image of `DATA` including padding, and are the
   references in it patched with `DATA` addresses?
6. NM8: do intermediates follow the first part's name under `O=`?
7. m9/NM7: should `L-FIT-NOMINAL` be an error on CP/M 3 and under keep-CCP?
8. M22: a bank byte in the table entry now (9 bytes) or never?
9. Nm1: is the escaped offset field absolute or a wide delta?
10. NM11: what is the per-routine reference limit, and what is the error?
