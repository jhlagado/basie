# Basiq runtime libraries

Each runtime is ATOM assembly source split into blobs, built into a blob
library (`.BRL`, [object format](../docs/object-format.md) §7) by
[`tools/brl.ts`](../tools/brl.ts):

```bash
deno task brl
```

writes `build/CPM22.BRL` from [`cpm22/cpm22.asm`](cpm22/cpm22.asm).

## Source format

- `; @library NAME runtime=R helpers=H profile=P` gives the identities.
- `; @profile key=value ...` gives the profile block: `class`, `kinds`, `base`,
  `limit`, `top`, `ccp`, `ram`, `ramlimit`, `guard`, `options`, `rst`,
  `debugger` and `file`.
- `; @blob ORDINAL KIND NAME [align=N] [helper=CC] [since=V]` starts a blob,
  which runs to the next one. `NAME` must be the blob's first label. `helper=`
  puts it in the helper table with calling-convention code `CC`, from
  helper-table version `V` (default 1). Lines before the first blob, such as
  `EQU`s, are shared by every blob.
- The pseudo-objects are `MAIN`, `IMAGE`, `BSS`, `FREE`, `REQUIRED`, `DATA`,
  `DATACOPY`, `OPTIONS`, `FILES` and `FILECNT`, and their sizes are `IMAGELEN`,
  `BSSLEN`, `DATALEN`, `COPYLEN` and `FILESLEN`.

## Labels

ATOM names are at most 8 characters and case-insensitive. A blob's entry
point is its only global label, written `AREA_WHAT` with an underscore
(`TRAP_DIV`, `WR_TEXT`, `STK_CHK`); everything inside a blob is a private
`.label`, which ATOM scopes to the enclosing global, so `.LOOP` and `.DONE`
can be reused freely. Prefixes that merely say "runtime" are not used: every
label in this file is in the runtime.

## How references are recovered

ATOM produces absolute images, not relocatable objects, so the tool assembles
the whole source three times: once as written, once with blob *i* moved up by
*i* × `$100`, and once moved by *i* × the largest alignment. The pseudo-object
symbols move the same way, with indexes after the blobs. A 16-bit word that
changes by exactly *k* × `$100` and *k* × the alignment is a reference to
target *k*, and its addend is its first value minus the target's first
address. Moving each blob by a different amount makes every target, end
pointers included, unambiguous.

Any other changed byte is an error. That catches relative jumps between blobs
and byte references, which the runtime doesn't use. Reference fields are
stored as zero, and `bss` blobs store no bytes.

## Limits

One build holds at most about 240 blobs, because moved blobs must still fit in
64K. Larger runtimes will be built in several batches when needed.
