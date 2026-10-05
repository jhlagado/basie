# Linker prior art for Basie

- Status: research note
- Date: 2026-10-03
- Context: `../build-pipeline.md` (object spools, blobs, ordinals, tree shaking)

This note surveys object formats and linkers that Basie's spool format and
linker can learn from. It covers the CP/M tools of the period, the later
small-machine toolchains, and the modern linkers that remove dead code. It
ends with design lessons for Basie.

## How to read the evidence marks

Each factual claim carries one of two marks:

- **[V Sn]** means verified in this session from source *Sn* in the
  [sources list](#sources). These sources were fetched and read.
- **[R]** means recalled from background knowledge and not checked against a
  source in this session. Treat these as leads to confirm before relying on
  them. Where recall is uncertain, the text says so.

Coverage is uneven. Sections 1 to 6 and 9 rest on primary manuals, format
documents and source code fetched in this session. Sections 7 (Turbo Pascal),
8 (Oberon) and 10.4 (ordinals) are **recalled**: the research pass covering
them had not reported when this note was finalised. They are marked **[R]**
throughout and are the first candidates for a follow-up verification pass.

## Summary table

| Tool or format | Unit of linking | Reference forms | Dead-code removal | Symbols | Library search |
| --- | --- | --- | --- | --- | --- |
| Microsoft REL, L80 | Module | Abs 16-bit word (prog, data, common relative); later postfix expressions with HIGH and LOW | Module-level only, through library search | Names, 3-bit length field (7 characters max) | Sequential scan; whole modules pulled |
| DRI LINK-80, RMAC | Module | Same REL forms; RMAC restricts expressions | Module-level only | Names truncated to 6 characters by RMAC | Sequential, or IRL index |
| DRI PRL, SPR, RSX | Whole image | High-byte page relocation only | None | None | None |
| SLR Z80ASM, SLRNK | Module | REL forms plus RPN expressions, byte and word | Module-level only | 16 characters in SLR REL; 6 or 7 in M-REL | `/S` scan, `.REQUEST` |
| Phoenix PLINK-II | Module, segments grouped into sections | REL forms | Module-level only | Names | One-pass `LIBRARY` or repeating `SEARCH` |
| Hi-Tech C 3.09 LINK | Module, placed by psect | Psect-, name- and PC-relative, 1 to 4 bytes; no LOW/HIGH | Module-level only | Names, record-bounded | LIBR directory, single scan |
| ASxxxx, sdld | Module, placed by area | Byte, word, PC-relative, MSB or LSB, paged | None beyond module pull-in | Names, effectively unlimited in sdld | Text `.lib` lists or archives, repeated |
| z88dk z80asm | Module, placed by section | Range-coded patches; expressions stored as text | None beyond module pull-in | Names, unlimited | Z80LMF library, restart after each pull |
| Turbo Pascal 3 | None (no linker) | Not applicable | None; whole runtime always present [R] | Not applicable | Not applicable |
| Turbo Pascal 4+ | Procedure and variable inside a unit [R] | Fixup lists per routine [R] | Yes, per routine ("smart linking") [R] | Names in unit interface [R] | Units by name |
| Oberon (PO 2013) | Module (loaded whole) | Fixup chains through instructions [R] | None (dynamic loading) | Module name plus entry number [R] | Modules by name plus key [R] |
| ELF `--gc-sections` | Input section | Many relocation types | Yes, mark from roots | Names | Archive index |
| wasm-ld | Function, data segment, global | Index relocations padded to 5-byte LEB | Yes, mark from exports | Indexes in output, names in objects | Archive index |
| Go linker | Symbol | Per-symbol relocations | Yes, reachability from `main` | Names | Packages |
| Plan 9 `8l` and kin | Instruction stream | Pseudo-instructions, linker selects encodings | Unreachable instructions only, not functions | Names | `__.SYMDEF` index, repeated |

## 1. Microsoft REL format (M80, L80, LIB-80)

### Unit of linking

The unit is the **module** (a "program" in Microsoft's terms): everything
between a program-name item and an end-module item [V S4, S5]. A library is a
plain concatenation of modules [V S6]. L80 loads or omits a library module as a
whole: with `/S` it searches the file "to satisfy any undefined globals" [V S4].
There is nothing smaller than a module that can be dropped.

### Relocation and reference model

The record stream is a **bit stream** that is not byte-aligned. A `0` bit is
followed by an 8-bit absolute byte. A `1` bit is followed by a 2-bit type: `00`
introduces a special link item; `01`, `10` and `11` introduce a 16-bit word
that is relative to the program segment, the data segment or the currently
selected COMMON block [V S1, S4].

So the base format has **only one relocatable form: a full 16-bit word**,
relative to one of three segment bases (plus absolute segments). Externals are
expressed by special items:

- **Chain external (6):** the value field is the head of a chain that ends in
  absolute 0. "Each element of the chain is to be replaced with the value of the
  external symbol" [V S1]. The chain threads through the word placeholders
  themselves.
- **External plus offset (9):** "The A value will be added to the two bytes
  starting at the current location counter immediately before execution"
  [V S4]. DRI's text says the offset is applied "after all chains have been
  processed" [V S1]. This item exists because a chained placeholder holds the
  chain link, so it has no room for an addend.
- **External minus offset (8):** documented by Microsoft as "Used for JMP and
  CALL to externals" [V S4]; Nestor80's reverse engineering found that M80 never
  generates it [V S6].
- **Chain address (12):** a chain of placeholders to be filled with the current
  location counter [V S1, S4]. It is the forward-reference backpatch a
  single-pass translator needs. M80 never generates it [V S6].

Later M80 versions (3.4x) added **extension link items** under the type 4
special item that the original manuals reserved [V S4, S6]. Their symbol field
carries a subtype byte: `41h` arithmetic operator, `42h` external reference,
`43h` segment-qualified value. Together they form a **postfix (RPN)
expression** that ends with a "store as byte" (operator 1) or "store as word"
(operator 2) item. The operators are high byte (3), low byte (4), NOT (5),
unary minus (6), subtract (7), add (8), multiply (9), divide (10) and modulo
(11). There is no AND, OR or shift [V S6]. This is how M80 expresses
`LD A,LOW EXT##` or `LD A,3+(NOT FOO##)`: a byte-sized reference cannot be
chained, because one byte cannot hold a 16-bit chain link [V S6]. The LINK-80
manuals of 1980 and 1981 do not define type 4, so DRI's LINK-80 cannot read
expression items [V S1, S4].

There is **no PC-relative relocation**. A `JR` to another module cannot be
expressed, so the Z80 relative branches are confined to a module [R, follows
from the item list in V S4].

### Dead-code elimination

Module granularity only, through library search. An "entry symbol" item (0)
names the publics at the head of each module "so the module should be linked
if the current file is being searched" [V S1]. Code inside a loaded module that
nothing references is kept.

### Symbol model

Names, in 8-bit ASCII, with a **3-bit length** field [V S1, S4]. The field can
express 0 to 7 characters. LINK-80 3.44 "refuses a symbol of 8 or more
characters, and an external of 7 or more inside a link-time expression"
[V S7]. (The `42h` extension item spends one of its bytes on the subtype, so
only 6 characters remain [V S6].) Publics are "define entry point" items (7)
with a value and a name; externals appear only as chain-external items at the
end of the module, one per distinct external [V S1, S6].

### Encoding

Byte-level summary [V S1, S4, S6]:

```
absolute byte        0 bbbbbbbb                                9 bits
relocatable word     1 tt wwwwwwww wwwwwwww  (tt = 01/10/11)   19 bits (LE word)
special item         1 00 cccc [tt 16-bit value] [nnn name...]
end module (14)      ... then pad to a byte boundary
end file (15)        1 00 1111
```

Absolute code costs 12.5% overhead (9 bits per byte); a relocated word costs
19 bits for 16. A public definition with a 6-character name costs 3 + 4 + 2 +
16 + 3 + 48 = 76 bits, about 9.5 bytes. Microsoft states the motive: the bit
stream "keeps the size of object files to a minimum, thereby decreasing the
number of disk reads/writes" [V S4]. The price is that a reader must decode bit
by bit, and no field can be found without parsing everything before it.

### Library search

LIB-80 builds libraries by concatenation [V S6]. L80 searches a file marked
`/S` once, in order, and always searches the system library before exit
[V S4]. A module in a library that references a symbol defined *earlier* in the
same library is not resolved on a single scan, so library order matters and
users repeat a library on the command line. This order dependence is
well-known folklore [R]. The TDL Z80 linker of 1978, by contrast, searched
"iteratively in the order given, until a complete pass over the libraries yields
no new modules" [V S12].

### Memory and I/O

L80 is a **linking loader**. It loads each module into memory at or near its
final address while it reads, so the program image lives in RAM during the link
[V S4]. The manual requires "a minimum of 40K RAM" [V S4]. Its error messages
expose the model: "Origin Above (Below) Loader Memory, Move Anyway", and
"Intersecting Program Area: … an address or external chain entry is in this
intersection" [V S4]. The input is read once and sequentially; the output is
written at the end with `/N` and `/E`.

### Known problems

- Names limited to 7 characters, and to 6 inside expressions [V S6, S7]. Long
  high-level-language names had to be mangled or truncated.
- Byte references to externals need the later expression extension, which DRI
  LINK-80 cannot read [V S1, S6].
- Library order dependence with a single scan [R].
- Chains live in the image; an overlapping data/program layout breaks chain
  resolution ("Intersecting Program Area") [V S4].
- L80 3.44 has layout and COMMON quirks found by modern reimplementers: it
  "miscomputes a COMMON-relative value past the end of its block" [V S7].

## 2. Digital Research REL, LINK-80, RMAC, and PRL, SPR, RSX

### LINK-80 and RMAC

DRI adopted the Microsoft REL format unchanged: LINK reads REL "produced by
PL/I-80, RMAC, or any other language translator that produces relocatable object
modules in the Microsoft format" [V S1]. The item table in DRI's manual matches
Microsoft's, except that types 3, 4 and 8 are listed as unused [V S1].

- **Unit of linking:** module. With the S switch LINK will "include only those
  modules containing symbols which are referenced but not defined in the modules
  already linked" [V S1].
- **Relocation:** the REL forms, 16-bit words only. RMAC restricts
  expressions: `A+B` with relocatable or external `A` needs constant `B`; `A-B`
  is allowed between two relocatables of the same segment; "in all other
  arithmetic and logical operations, both operands must be absolute" [V S2]. So
  RMAC cannot emit `HIGH ext` or `LOW reloc`.
- **Dead-code elimination:** module-level only [V S1].
- **Symbols:** names. "While symbol names may be up to 16 characters, the first
  six characters of all symbols in PUBLIC, EXTRN and COMMON statements must be
  unique, since symbols are truncated to six characters in the object module"
  [V S2]. PL/I runtime names begin with `?` to stay out of the user's namespace,
  and LINK hides them unless asked [V S1].
- **Library search and IRL:** LIB concatenates REL files and can build an
  **indexed library (IRL)** [V S3]. An IRL is a 128-byte header (extent and
  record of the REL section), an index of entries `e r b name… 0FEh` giving the
  extent, record and byte offset of the module that defines each entry symbol,
  terminated by an entry whose first character is `0FFh`, then the REL section
  [V S1]. The index lets LINK seek straight to needed modules instead of
  decoding the whole bit stream. LINK searches `PLILIB.IRL` automatically for
  PL/I programs [V S1].
- **Memory and I/O:** LINK keeps its symbol table in memory and may create "up
  to eight temporary files" (`XXABS.$$$`, `XXPROG.$$$`, `XXDATA.$$$`,
  `XXCOMM.$$$` and `YY…` counterparts) on the default disk [V S1]. The A switch
  trades buffers for symbol space: it "causes the internal buffers to be stored
  on the disk, thus slowing down the linking process considerably" [V S1]. LINK
  reports a "use factor", the share of its memory used [V S1].
- **Known problems:** "FIRST COMMON NOT LARGEST" makes module order matter
  [V S1]; six-character significance [V S2]; no byte relocation.

### PRL, SPR and RSX page relocation

These are **load-time** relocation formats, not link formats, but they are the
period's most compact answer to "relocate an image at load time".

- **PRL:** a 256-byte header (image size at offset 1, uninitialised data size
  at offset 4, load address at 7 for OVL files), then the image assembled as if
  loaded at 0100h, then a **relocation bitmap** of `(bytes + 7) / 8` bytes: one
  bit per image byte [V S8]. Bit 7 of the first map byte covers the first image
  byte [V S10, S11]. A set bit means the byte is the **high byte** of an
  address; the loader adds the load page to it. Low bytes are never touched,
  hence "page relocatable" [V S11].
- **SPR:** the same layout, assembled as if loaded at 0000h; used for CP/M 3
  and MP/M system modules that GENCPM or GENSYS places [V S8].
- **RSX:** a PRL-format module attached to a COM file by GENCOM. GENCOM adds a
  256-byte header that starts with `0C9h` (RET), holds the original COM length
  and a table of up to 15 16-byte RSX records (offset, length, non-banked flag,
  8-character name) [V S9]. The loader relocates each RSX below the BDOS.
- **How bitmaps were made:** DRI built some PRL tools by assembling twice, "the
  second time 100H higher", and GENMOD took the relocation bits from the bytes
  that differ [V S10, S11]. LINK-80's OP switch produces PRL directly [V S1].
- **Cost:** a fixed 12.5% of image size, independent of how many addresses
  there are, plus the 256-byte header. It cannot express byte-granular
  relocation, low-byte references, or anything except "add the page".
- **Known limitation:** page alignment is required by construction, so a PRL
  can only be loaded on a 256-byte boundary [V S11].

## 3. SLR Systems Z80ASM, SLRNK, and Phoenix PLINK II

### SLR Z80ASM, SLRNK and SLRNK+

- **Two object formats.** Z80ASM writes Microsoft REL with `/M` (6 or 7
  significant characters by `/6` or `/7`) or **SLR-format REL** with `/R`
  [V S60, S61]. Symbols are significant to 16 characters; SLR format carries
  all 16 to the linker, while M-REL truncates them [V S61]. Jay Sage warns that
  mixing formats causes trouble because M-REL truncates names to 6 characters
  "but the SLR REL format will include the first 16!", and calls SLR files
  "shorter and faster" [V S60]. No byte-level description of SLR format was
  found; it is probably in the SLRNK manual (S13), which needs a login.
- **Unit of linking:** the module. With `/S` libraries are "'S'canned so that
  only the modules required by PROG will be linked in"; without it the whole
  library is linked [V S60].
- **Relocation forms:** program-, data-, common-relative or external values,
  "or any mathematical combination". Unresolvable expressions are "passed in
  reverse polish form to SLRNK for resolution at link time", including
  byte-sized ones such as `LD E,DATAITEM*EXTERNAL1+EXTERNAL2`; SLRNK reports
  out-of-range byte results [V S61]. Up to 15 program, data and common areas
  [V S61].
- **Library search:** `.REQUEST lib1,lib2` names libraries to search in order
  [V S61]. Whether `/S` makes one pass or repeats was not found.
- **Passes and memory:** Z80ASM is one-pass by default, with an optional
  second pass for full listings, and claims over 6000 lines per minute
  [V S61]. SLRNK claims to link Microsoft files "7 times faster than L80"; SLRNK+
  overflows its tables to disk and can produce a full 64K output whatever the
  TPA size [V S62]. SLRNK+ adds PRL and SPR output and 8 address spaces
  [V S62].
- **Dead-code elimination:** library-module selection only [V S60].
- **Known problems:** slash options are processed before files, so an early
  `/E` ends the link before inputs are read; `/A` puts DSEG before CSEG, which
  breaks the ZCPR3 header [V S60].

### Phoenix PLINK-II (1981)

- **Input:** "PSA and MicroSoft relocatable files"; IRL is not supported
  [V S63].
- **Unit:** the module, split into segments (code, data, COMMONs) that can be
  grouped into sections; each overlay is a section. `CONCATENATE` gives each
  module its own slice of a COMMON, useful for building tables. Duplicate
  definitions are allowed, first one wins, with a warning [V S63].
- **Library search:** `FILE` links every module; `LIBRARY` makes one pass;
  `SEARCH` "may make multiple passes" until nothing more resolves, which "should
  hardly ever be necessary". `INCLUDE` and `EXCLUDE` filter modules [V S63].
- **Overlays:** nested `BEGINAREA … OVERLAY … ENDAREA` areas "up to 32 levels
  deep". Calls into overlays are rewritten into vector stubs that call an
  automatically linked loader. Because PLINK-II cannot tell code addresses from
  data addresses, every reference into an overlay is treated as a call or jump
  [V S63].
- **Passes and memory:** "Plink-II is a two-pass linkage editor. That is, each
  of the input files is read twice." The output is built on disk, so it can
  fill all 64K, and overlaid programs of up to 4 megabytes are claimed [V S63].
  Uninitialised segments are sorted to the end of each section so they take no
  disk space [V S63].
- **Dead-code elimination:** module-level only [V S63].
- **Known problems:** with Microsoft REL input, overlapping commons used by the
  same module give error #93, "because fixups are expressed as memory
  addresses" [V S63].

## 4. Hi-Tech C for CP/M (LINK, LIBR, psects)

Sources are Hi-Tech's own `OBJCODE.TXT` and user manual from the freeware
3.09 distribution, and a decompilation of the 3.09 `LINK.COM` and `LIBR.COM`
checked for equivalence with the originals [V S64, S65, S66].

- **Record envelope:** 16-bit length (low byte first), 8-bit type, then data,
  at most 512 bytes in practice; names are NUL-terminated [V S64].
- **Record types:** TEXT 1 (u32 offset, psect name, bytes), PSECT 2 (u16
  flags, name), RELOC 3 (entries for the preceding TEXT: u16 offset, u8 type,
  name), SYM 4 (u32 value, u16 flags, psect name, symbol name), START 5, END 6,
  IDENT 7 (byte order, machine name), XPSECT 8 [V S64]. The 3.09 LINK handles
  only types 1 to 8 [V S66].
- **Psects:** flags GLOBAL, PURE, OVRLD, ABS, BIGSEG, BPAGE [V S64]. Psects are
  global by default and concatenated across modules unless OVRLD [V S65]. LINK
  places them with `-Pname=link/load,…` and defines `__Lpsect`, `__Hpsect` and
  `__Bpsect` for each [V S65, S66]. The CP/M order is text, data, bss; bss is
  not stored in the `.COM` [V S65].
- **Relocation:** a type byte with the kind in the high nibble and size (1 to
  4 bytes) in the low nibble. Kinds: absolute, psect-relative, name-relative,
  PC-relative to psect or name, segment forms, and RCPLX, a stack-machine
  expression with LOW, HIGH and arithmetic operators [V S64]. **The 3.09 LINK
  rejects RCPLX** with "illegal relocation type", so it has no low- or
  high-byte-of-address relocation; a 1-byte fixup that does not fit gives
  "Fixup overflow" [V S66].
- **Symbols:** names with no format limit, bounded by the record size; a fixed
  997-slot hash table fails with "Too many symbols", and there are at most 20
  psects [V S66].
- **LIBR format:** a header (directory size, module count), a directory
  listing each module's size, name and symbols with a type byte (defined,
  common, undefined), then the modules [V S66].
- **Library search:** one linear scan of each library's directory in pass 1;
  a module is pulled in if it defines a currently undefined symbol. Pass 2
  reads only flagged modules and seeks past the rest [V S66]. Order matters;
  the remedy is naming the library twice [V S65].
- **Passes, memory and I/O:** two passes, inputs re-read from disk; symbol and
  psect tables in RAM with no overflow to disk. With `-C` each TEXT block is
  placed in the output by `fseek`, so the image is never held in memory
  [V S66].
- **Dead-code elimination:** module-level library selection only [V S65].

## 5. ASxxxx and SDCC sdld (.rel text format)

- **Unit of linking:** the module (one `.rel` file or library member). Areas
  (named sections) are concatenated across modules by name [V S20]. An area
  is a placement unit, not a removal unit.
- **Areas:** flag bits give `CON` (0x00) or `OVR` (0x04), `REL` (0x00) or `ABS`
  (0x08), and `PAG` (0x10). Matching relocatable areas concatenate; absolute
  areas from different modules overlay [V S20]. sdld adds address-space flags
  such as `A_CODE` and `A_XDATA` and a bank flag [V S21].
- **Format:** a line-oriented **text** file [V S20]:

  ```
  XL2                       radix X/D/Q, byte order H/L, address width 2/3/4
  H aa areas gg global symbols
  M name                    module name
  A label size ss flags ff [bank bb]
  S name Defnnnn | S name Refnnnn
  T xx xx nn nn ...         offset then data bytes
  R 0 0 nn nn n1 n2 xx xx   relocations in groups of 4
  P ...                     paging, same layout as R
  B name base ... size ...  bank (newer versions)
  ```

- **Relocation forms:** the richest set in this survey. V3 mode bits: byte or
  word (`R3_BYTE 0x01`), symbol or area (`R3_SYM 0x02`), PC-relative
  (`R3_PCR 0x04`), unsigned (`0x10`), page 0 (`0x20`), paged (`0x40`), and MSB
  selection (`R3_MSB 0x80`) [V S20, S21]. V4 adds 1 to 4 byte widths,
  signed/unsigned/MSB selection, PC-relative variants with offsets and
  no-range-check forms, and merge modes [V S20, S21]. sdld extends V3 with a
  third byte (`R_BYT3`) and a high-byte selector (`R_HIB`) [V S21].
- **Symbols:** names; Def or Ref. In sdld `NCPS` is `PATH_MAX`, so there is
  effectively no length limit [V S21]. Older aslink versions limited names to 8
  characters [R].
- **Library search:** aslink `.lib` files are text lists of module files. "The
  first module that defines a missing symbol is linked", and the search repeats
  so back references resolve [V S20]. sdld also reads `ar` and sdcclib
  archives; its `search()` loops until a full pass finds nothing new, and each
  match imports the whole module [V S22].
- **Dead-code elimination:** none. SDCC feature request #635, "Unused
  functions are not removed", opened in 2019, is still open; the maintainer's
  answer is to put functions in libraries [V S23]. A contributor wrote an
  external tool (`sdccrm`) that removes dead code from the assembly instead
  [V S23].
- **Passes, memory and I/O:** two passes. Pass 1 builds areas, sizes and
  symbols and searches libraries; pass 2 reads `T`, `R` and `P` lines,
  relocates and writes output. Inputs are re-read from disk in pass 2; there
  are no temporary files [V S20, S24].
- **Known problems:** no section GC, so libraries must be one function per
  module [V S23]; verbose text objects are large and slow to parse [R].

## 6. z88dk z80asm

- **Unit of linking:** the module, one per source file. Sections with the
  same name are joined across modules in the order the linker sees them, so a
  CRT module linked first fixes section order [V S25].
- **Object format (`Z80RMF18`):** little-endian 32-bit integers; strings as
  indexes into a string table. Header: 8-byte signature, CPU id, IX/IY swap
  flag, six file pointers (module name, expressions, defined symbols,
  externals, sections, string table) [V S26].
- **Relocation forms:** each expression record has a range code: JR
  displacement, unsigned byte, signed byte, 16-bit little-endian, 16-bit
  big-endian, 32-bit, byte widened to 16, 24-bit, a byte offset to `0xFF00`,
  link-time `DEFC`, 16-bit relative jump, and others. It also records the
  section, the instruction start, the patch offset and the opcode size, and
  **stores the expression as source text, re-parsed at link time** [V S26].
- **Symbols:** scope local or public; type constant, section-relative address
  or computed at link time. Externals are a list of names. Names are long
  strings since v16, so effectively unlimited [V S26].
- **Library format (`Z80LMF18`):** signature, pointer to a public-symbol list,
  then a chain of members (next pointer, size, embedded object) [V S26].
- **Library search:** all objects and libraries are loaded into memory. Every
  `.o` is linked. While unresolved symbols remain, the linker walks libraries
  in command-line order, takes the first member that resolves something, and
  restarts so that member's dependencies come in [V S27].
- **Dead-code elimination:** none below module granularity. Issue #45 (open
  since 2017): "the unit of granularity of the extraction is the file" [V S28].
  A maintainer explains that z80asm "only links necessary objects, but it is
  limited to the resolution of a file", which is why the libraries are written
  one function per file [V S29]. Issue #692: a `defc` alias pulls in the
  module it names even when the alias is unused [V S30].
- **Known problems:** text expressions make linking slow, the stated motive
  for a planned v19 format with plain symbol-plus-addend relocation records and
  a library symbol index [V S31]. The z88dk tools run on a host, not on the
  Z80.

## 7. Turbo Pascal 3 and Turbo Pascal 4+ smart linking

*All [R]; the Turbo Pascal research pass had not reported.*

- **Turbo Pascal 3:** compiles source to machine code in memory in one pass,
  with no separate linker. Every `.COM` file starts with the whole runtime
  library (around 8 to 10K on CP/M, more on DOS) whether or not the program uses
  it [R]. Large programs used include files, overlays, and `Chain`/`Execute`
  [R]. The lesson is that fast single-pass compilation without a linker pays a
  fixed size tax on every program.
- **Turbo Pascal 4.0 (1987):** introduced units (`.TPU`) and a linker. The
  linker removed unused procedures and functions, marketed as **smart
  linking**. Later versions extended this to unused variables and typed
  constants [R].
- **How:** a TPU stores each routine's code as a separate block with its own
  fixup list, so the linker can trace references from the main program and
  emit only reached routines [R]. This is exactly Basie's blob model.
- **Limits:** code linked from `.OBJ` files with `{$L}` was all-or-nothing [R,
  uncertain]. A type's virtual method table references every virtual method,
  so any instantiated object type keeps all its virtual methods alive [R]. TPU
  files are tied to one compiler version, so every upgrade forced recompiling
  all units [R].

## 8. Oberon module files and the loader (Project Oberon)

*All [R]; the Oberon research pass had not reported.*

- **Unit of linking:** the module, loaded whole and dynamically. There is no
  dead-code removal [R].
- **References by number:** an imported object is identified by **module
  number** (index into the importing module's import list) and **entry number**
  (index into the exporter's entry table), never by name [R]. Imports are listed
  by module name together with a **key**, a fingerprint of the exporter's
  interface. The loader refuses a module whose recorded key differs from the
  loaded exporter's key [R].
- **Fixup chains (Project Oberon 2013):** the compiler threads three chains
  (procedure calls, data references, type descriptors) through the instruction
  words themselves. Each unresolved instruction holds the module number, entry
  number and the distance to the previous link in the chain. The object file
  records only the chain heads, and the loader walks each chain and patches it
  [R]. This makes the object file very small: no relocation table at all.
- **Original Oberon on Ceres (NS32032):** external calls went through the
  processor's module link tables (the `CXP` instruction and a per-module link
  table), so code needed no patching [R].
- **Pitfalls:** reordering or adding exports renumbers entries, which changes
  the key and forces clients to recompile [R]. The chain link field has a fixed
  width, which bounds the distance between links [R]. A wrong chain patches
  arbitrary instruction words with no error.

## 9. Modern equivalents

### ELF with `-ffunction-sections` and `--gc-sections`

- **Unit:** the input section. GCC places "each function or data item into its
  own section" [V S40]. Code left in one `.text` section cannot be split [R].
- **Roots:** GNU ld keeps "the section containing the entry symbol and all
  sections containing symbols undefined on the command-line", plus sections
  referenced by dynamic objects [V S41], and `KEEP()` sections in linker
  scripts [V S42]. lld's `MarkLive.cpp` also roots init, fini and preinit
  arrays, `.ctors`/`.dtors`, `SHF_GNU_RETAIN` sections and ungrouped notes; it
  keeps non-allocated sections such as debug info by default [V S43].
- **Mark phase:** each input section has a live bit; a worklist pops a live
  section, resolves its relocations to target sections and enqueues them, plus
  the other members of its section group [V S43]. `.eh_frame` is handled per
  CIE and FDE so that an FDE does not keep its own function alive [V S43].
- **`__start_`/`__stop_`:** a live reference to `__start_X` used to keep every
  section named `X`; ld.lld 13 defaults to `-z start-stop-gc`, which stops that
  [V S44, S45].
- **Reporting:** `--print-gc-sections` lists removed sections [V S41].
- **Costs:** per GCC, larger and slower objects, and the options "prevent
  optimizations … using relative locations inside a translation unit", such as
  relaxing calls to short forms [V S40].
- **ICF:** lld merges identical read-only sections by partitioning on a hash
  and refining to a fixpoint [V S46].

### WebAssembly wasm-ld

- **Unit:** functions, data segments, globals, tags and tables, each with a
  live bit [V S47]. GC is on by default: "all unused functions and data
  segments will be stripped" [V S48].
- **Roots:** the entry point, all exports, and what they reference [V S48].
  Constructors are reached only through a synthesised function that "does not
  contain relocations", so they are marked live by hand [V S47].
- **Ordinals and padding:** `call` takes a function index. Relocated LEB128
  values "must be maximally padded so that they can be rewritten without
  affecting the position of any other bytes"; index 3 becomes
  `83 80 80 80 00` [V S49]. `--compress-relocations` removes the padding
  afterwards and is incompatible with debug info [V S48].

### Go linker

- **Unit:** the symbol, by flood fill over relocations from `main.main`, init
  tasks and runtime roots [V S50].
- **Methods:** a method is kept if its type is reachable and an interface
  method with a matching signature is used; a reachable function marked
  `REFLECTMETHOD` keeps "all exported methods of all reachable types" [V S50].
- **History:** Go 1.3 moved "the instruction selection phase that was part of
  the linker" into the compiler [V S51]. Cox's design note cites Thompson's
  "compile quickly, load slowly" and calls the linker the slowest part of the
  toolchain [V S52].
- **Memory:** in 2019 linking `cmd/compile` read 56 MiB of objects but
  allocated 229 MiB, because the linker held every input "even if it
  eliminates most symbols as unreachable". The redesign proposed dense symbol
  indices instead of names [V S53].

### Plan 9 object files and linkers (`8l`, `vl`, and others)

- **Format:** objects are "binary forms of assembly language, similar to what
  might be passed between the first and second passes of an assembler" [V S54].
- **Link-time code work:** the loader reorders code to remove branches,
  resolves branch lengths "with a multiple pass algorithm", fills delay slots
  [V S54], "folds branches … and discards unreachable code", and drops NOPs
  [V S55]. `span()` recomputes every instruction's size and repeats while any
  size changes, aborting after 50 passes ("span must be looping") [V S56].
- **No function-level dead-code removal:** `8l` has no deadcode pass; the
  unreachable-code removal is instruction-level within a function, and "the
  first instruction of every function is assumed to be reachable" [V S55, S56].
  Function-level removal arrived in Go's fork [V S57].
- **Libraries:** an `__.SYMDEF` table of contents, searched until no
  undefined symbol is resolved [V S56].
- **Trade-off:** "Compile quickly, load slowly, and produce medium quality
  object code" [V S54].

## 10. Cross-cutting topics

### 10.1 Fixup chains

**Who used them.** Microsoft REL (chain external, chain address) [V S1, S4];
Oberon 2013 (three chains through instruction words) [R]; one-pass
assemblers and compilers for forward references within a unit [R].

**What goes wrong.** Each item below is visible in the REL record set:

1. **The placeholder must hold the link.** A byte operand cannot hold a 16-bit
   link, so byte references to externals could not be chained. M80 had to add
   postfix expression items for `LOW` and `HIGH` [V S6].
2. **No room for an addend.** `EXT+4` cannot be chained, because the slot holds
   the link, not the offset. REL needs the separate "external plus offset" item,
   applied "after all chains have been processed" [V S1].
3. **Random access to the image.** Walking a chain jumps backwards through the
   module's bytes. L80 therefore holds the image in RAM and fails when the
   program and data areas overlap a chain entry [V S4]. A linker that streams
   output, or drops blobs, cannot walk chains through bytes it has not kept.
4. **Silent corruption.** A broken chain writes the resolved value over
   arbitrary bytes; there is nothing to check it against [R].
5. **Bounded distance.** Chains with narrow link fields limit how far apart
   references may be [R, Oberon].
6. **Code movement breaks chains.** Shrinking a branch inside a chained region
   moves every later link [R].

### 10.2 Branch relaxation at link time versus compile time

- **Link time, Plan 9:** `8l`'s `span()` re-sizes every instruction each pass
  until nothing changes, choosing a 2-byte or 6-byte conditional jump by
  displacement, and gives up after 50 passes [V S56]. Go 1.3 moved this work
  out of the linker because linking had become the slowest step [V S51, S52].
- **Link time, modern:** GNU ld `--relax` performs "target specific, global
  optimizations that become possible when the linker resolves addressing"
  [V S41]. RISC-V relaxation deletes bytes (`auipc+jalr` to `jal`), which forces
  alignment tracking, iteration to convergence and DWARF bloat [V S58]. lld
  adds range-extension thunks on ARM, AArch64, MIPS, PPC and others, iterating
  thunk creation to a fixpoint and failing with "address assignment did not
  converge" after 30 passes [V S59]. Apple's ld64 inserts branch islands at
  fixed intervals [V S59a].
- **Theory:** Szymanski (1978) showed that choosing branch sizes is efficiently
  solvable when operands are labels or restricted expressions, and NP-complete
  with general assembly-time expressions [V S59b, abstract only]. The standard
  practical algorithm starts every branch short and only lengthens, which
  terminates [R].
- **Compile time, CP/M:** Z80ASM was a one-pass assembler by default [V S61];
  JR versus JP was chosen by the assembler or programmer.
- **Period CP/M linkers:** none of the REL-based linkers did relaxation, and
  could not: REL has no PC-relative form, and it carries no record of which
  bytes are instructions [V S1, S4]. A modern L80 reimplementation confirms
  that "LINK-80 has no PC-relative operator", so a JR to an external is an
  error [V S7]. Hi-Tech's format does have PC-relative relocations, but only to
  fill in a displacement, not to change instruction size [V S64, S66]. No
  CP/M-era linker was found that relaxed JP to JR (absence of evidence, not
  proof).

### 10.3 Tree shaking in period CP/M tools

No period CP/M linker found here shook below module granularity: L80 and
LINK-80 [V S1, S4], SLRNK [V S60], PLINK-II [V S63] and Hi-Tech LINK [V S65]
all select whole modules. Neither do the later ASxxxx/sdld and z88dk
linkers, whose maintainers point users to one-function-per-module libraries
instead [V S23, S29]. The reasons visible in the sources:

- **The format had no smaller unit.** A REL module has one program segment and
  one data segment, and nothing marks where one routine ends and another
  begins [V S1, S4].
- **References were implicit.** Intra-module references are relocatable words
  relative to the segment base; they say "this word is relative to CSEG" but not
  "this word refers to routine X". The linker cannot build a routine-level graph
  from them [V S1].
- **Fixed tables.** Hi-Tech LINK keeps symbols in a fixed 997-slot hash table
  with no overflow to disk [V S66]; a routine-level graph multiplies the entry
  count.
- **Memory.** L80 holds the image in RAM and LINK-80 already spills buffers to
  disk to fit its symbol table [V S1, S4]. A routine-level graph would compete
  for the same memory.
- **Workaround.** Library authors split runtimes into many small modules, and
  module-level search did the rest; PL/I-80's `PLILIB.IRL` shows dozens of
  small modules being pulled in for one program [V S1].

The first widely used small-machine tool to shake at routine level appears to
be Turbo Pascal 4's smart linker on DOS (1987) [R].

### 10.4 Ordinal references instead of names

- **Oberon:** module and entry numbers, guarded by a per-module key [R].
- **Windows DLLs:** imports may be by ordinal, which is faster and smaller,
  but ordinals shift between DLL versions unless pinned with `@n` in the `.DEF`
  file. Microsoft's guidance discourages importing system DLLs by ordinal [R].
- **Amiga libraries:** functions are reached at fixed negative offsets (LVOs)
  from the library base; the discipline is append-only [R].
- **CP/M BDOS:** function numbers in register C are an ordinal interface with
  the same append-only discipline [R].
- **WebAssembly:** function indices patched by the linker [R].
- **Pitfalls:** numbers drift when the defining side reorders; a mismatch fails
  silently unless something such as a key or version check catches it; and
  numbers are unreadable in diagnostics unless a name table travels alongside.

## Lessons for Basie

1. **Make the routine the unit, in the format itself.** Every CP/M linker in
   this survey was limited to module-level removal because REL and its
   relatives had nothing smaller than a module (Section 10.3). Turbo Pascal 4
   shook per routine because the TPU stored each routine as its own block with
   its own fixups (Section 7). Basie's one-blob-per-routine rule is the right
   decision; keep it absolute, including for runtime helpers.

2. **Make every reference explicit and target-named.** REL relocatable words
   say only "relative to CSEG", so no routine-level graph can be built from them
   (Section 10.3). Basie's "every address use is a reference" rule is what makes
   reachability possible. Never allow a "segment-relative" reference form that
   bypasses it.

3. **Do not thread fixup chains through blob bytes.** Chains cannot represent
   byte operands or addends, need random access to the image and fail silently
   (Section 10.1). A dropped blob would also take part of a chain with it.
   Keep explicit reference records: blob ordinal, site offset, form, target
   ordinal and addend. z88dk's planned v19 format moves the same way, from
   expressions to plain symbol-plus-addend records, for link speed
   (Section 6).

4. **Include low-byte, high-byte and addend forms from day one.** M80 had to
   bolt on postfix expressions for `LOW` and `HIGH` externals, DRI's LINK-80
   never read them (Section 1), and Hi-Tech's 3.09 LINK rejects its own
   complex relocations (Section 4). Basie's page-aligned tables used through
   `LD H,hi(table)` need a high-byte form; `table+k` needs an addend. A fixed
   small set (word, low byte, high byte, each with a signed addend) covers this
   without a general expression evaluator.

5. **Never carry PC-relative references between blobs.** REL had no relative
   form, and the period linkers never relaxed branches (Section 10.2). Basie's
   rule that `JR` and `DJNZ` stay inside a blob keeps the linker from needing
   instruction knowledge, as in the period tools. Branch shrinking belongs in the
   compiler, inside a routine, where the bytes are still at hand (Plan 9 shows
   the cost of doing it in the linker: the whole program in memory).

6. **Prefer byte-aligned records to a bit stream.** REL's bit stream saves
   about 1.5 bytes per relocated word but forces bit-by-bit decoding and makes
   skipping impossible (Section 1). DRI had to bolt an index onto it (IRL) to
   make library search tolerable (Section 2). Byte-aligned records with
   explicit lengths allow skipping a dead blob's bytes without decoding them.

7. **Put a directory where the linker needs it.** IRL's index lets LINK-80
   seek straight to a module (Section 2); LIBR and `__.SYMDEF` play the same role
   (Sections 4, 9). Basie's runtime spool set should carry a directory of blob
   sizes and reference lists, separate from the bytes, so the mark phase reads
   only the graph and the place phase reads only live bytes.

8. **Separate graph, placement and emission passes over sequential data.**
   L80 needed the whole image in RAM and a 40K minimum (Section 1); LINK-80
   spilled to eight temporary files when memory ran out (Section 2). Hi-Tech's
   LINK shows the better shape: tables in RAM, two passes, output placed by
   seeking so the image is never held in memory (Section 4); PLINK-II and
   SLRNK+ built the output on disk (Section 3). Basie's
   linker should hold only per-ordinal tables (live bit, size, address) in
   memory, about 4 to 5 bytes per blob, and stream bytes from disk to output.
   State the capacity limit as a number of blobs, and report it as a clear
   error.

9. **Number things, but guard the numbers.** Ordinals are compact and need no
   name table (Oberon, wasm, BDOS functions), but numbers drift when the
   defining side changes, and mismatches are silent (Section 10.4). Oberon's
   per-module key is the guard. Basie's runtime spool set should carry a
   version stamp or interface hash that the compiler records and the linker
   checks, so a stale runtime is refused rather than mislinked.

10. **Fix runtime ordinals append-only.** Windows ordinals and Amiga LVOs
    show the discipline that works: assigned numbers never move, and new
    entries are appended (Section 10.4). Reserve a fixed ordinal range for the
    runtime and never reuse a retired number.

11. **Keep names out of linking but available for reports.** REL's 6- and
    7-character limits forced name mangling (Sections 1 and 2), while numbers
    are unreadable in error messages (Section 10.4). Basie's optional name
    spool gives the best of both, provided every linker diagnostic and map line
    prints names when the spool is present.

12. **Make roots explicit and give a way to keep.** ELF needs `KEEP()` and
    `__start_`/`__stop_` because some tables are reached only by convention;
    forgetting them silently deletes code (Section 9). Basie's startup blob and
    linker pseudo-ordinals are its roots; any table reached only indirectly (an
    interrupt vector, a dispatch table filled at run time) needs an explicit
    "keep" flag in the format, not a convention.

13. **Watch for structures that keep everything alive.** Turbo Pascal's VMTs
    and Go's reflection keep every method reachable (Sections 7 and 9). If
    Basie gains procedure tables, interfaces or variant dispatch, a table that
    references every member defeats shaking. Prefer per-call-site references,
    or a table per used subset.

14. **Report what was removed.** `--print-gc-sections` exists because
    silent removal confuses users (Section 9), and LINK-80 already reported a
    map and a "use factor" (Section 2). Basie's map should list removed blobs
    by name, and the capacity margin, so users can trust the shaker and see how
    close they are to the limits.

15. **Do not let one-big-blob escape hatches spread.** ELF code in one
    `.text` section, `.OBJ` files in Turbo Pascal and multi-function modules in
    z88dk all defeat routine-level removal (Sections 6, 7, 9). Hand-written
    runtime code is the likely offender in Basie; enforce one helper per blob in
    the runtime build, as the build pipeline already proposes.

## Addendum: verified findings for Sections 7, 8 and 10.4

A later research pass checked the sections above that were marked as recalled.
Its findings supersede them where they differ. Claims still without a primary
source are marked [R].

### Turbo Pascal 3 (CP/M-80)

- **No linker.** The compiler writes to memory, a `.COM` file or a `.CHN` file.
  A `.COM` "contains the program code and Pascal run-time library"; a `.CHN`
  contains the program code without it. Code starts at "the end address of the
  Pascal library plus one", so every `.COM` carries the whole library. Its size,
  about 8K to 12K, is [R]. (TP3 CP/M manual, pp. 143–145)
- **No symbolic externals.** External routines are bound to absolute addresses
  (`external $EC00`). Reuse is by `{$I}` include files. (§22.15, ch. 17)
- **One pass, all in RAM.** When compiling to memory, code is generated upwards
  from the end of the source text, and the symbol table grows down from 1K
  below the top of memory. (pp. 170–171)
- **Overlays.** An `overlay` procedure's code goes to a numbered file; a group of
  consecutive overlays shares one area the size of its largest member, and
  members of a group must not call each other. (ch. 18)

### Turbo Pascal 4 to 7: smart linking

- **Granularity.** "The linker automatically removes unused code on a
  per-procedure basis" (TP4, p. 372). TP6 and TP7 extend removal to variables
  and typed constants, but per **declaration section**, not per variable: one
  referenced variable keeps its whole `var` section. (TP6 Programmer's Guide
  p. 258; TP7 Language Guide pp. 250–251)
- **Two passes.** Pass 1 marks every called procedure; pass 2 builds the `.EXE`
  from the marked procedures in the `.TPU` files. `{$L+}` keeps the units in
  memory between passes, `{$L-}` rereads them. (TP4, p. 540) TP7 disables smart
  linking when compiling to memory. (TP7 LG, p. 250)
- **Unit format.** Unpublished. Reconstructions show each code, constant and
  variable block with its own reference list; marking starts from the main
  program, unused blocks keep offset `$FFFF`, and relocations are written only
  for placed blocks. (turbopascal.org; INTRFC)
- **`.OBJ` files.** Converted from OMF, keeping only the standard code, constant
  and data segments. That a whole `.OBJ` is kept when anything in it is
  referenced is [R].
- **Virtual methods.** A method table references every virtual method, so a
  live constructor keeps them all; this is documented for C++ in LLVM, and Free
  Pascal's whole-program optimisation works around it. That Turbo Pascal behaved
  the same way is [R].

### Oberon

- **Ceres (NS32000).** Wirth compared fixup lists with an indirection table and
  chose the **link table**: one conversion per referenced object, code left
  untouched, short call addresses. Direct addressing tested 15–20 per cent
  larger. (Project Oberon, 2005, §6.1–6.2)
- **Project Oberon 2013 (RISC).** Linking is by number: clients see only a
  procedure number, an index into the callee's entry table; "procedure names
  are not needed". Export numbers are assigned in declaration order. Calls are
  fixed up through **chains** in the instruction fields (4-bit module, 8-bit
  procedure, 12-bit displacement); the compiler reports "fixup impossible" when
  a gap reaches 1000H words, which caps imports at 15 and entries at 256.
  (ORG.Mod, Modules.Mod, PO.System §6)
- **Keys.** A key is a checksum of the symbol file that changes if and only if
  the interface changes; the loader refuses a mismatched import. Reordering
  exports renumbers them and changes the key.

### Ordinals elsewhere

- **Win16.** Exports are an ordinal-indexed table; names live in a resident
  table and a non-resident one read only on demand. Imports within a segment
  are threaded through their placeholders as a chain ending at `$FFFF`.
  (Raymond Chen, *The Old New Thing*, July 2006)
- **Win32.** Ordinals assigned automatically by the linker are not stable:
  `LocalAlloc` was 314 in NT 3.1 and 501 in Windows 95. Microsoft recommends
  exporting by ordinal only for legacy clients. (Chen; Microsoft Learn)
- **Amiga.** A library function's vector offset "is always the same on every
  system and is not subject to change". (Amiga RKM Libraries) Appending new
  functions only at the end is [R].
- **Lilith Modula-2.** `CX 1 0` calls external module 1, procedure 0, in 3
  bytes. (afborchert/lilith)

### What this changes for Basie

- **Turbo Pascal 4 is confirmed** as the closest precedent: per-procedure blocks,
  each with its own reference list, marked from the main program. Its data
  granularity was coarser than Basie's, which removes each variable and
  constant individually.
- **Ordinals need fixed assignment, not linker-assigned numbering.** The Win32
  `LocalAlloc` case is the failure Basie's append-only helper table prevents:
  runtime ordinals are published and fixed by the runtime, never assigned by a
  tool at build time.
- **Oberon's key is the model for the interface check** Basie should add: a
  checksum of the helper table carried by the blob library and recorded by the
  compiler, so a library with the same version number but a different
  interface is refused.

## Follow-up verification

These recalled claims matter most to the design and should be checked first:

- Turbo Pascal 4 TPU per-routine fixup structure and the `.OBJ` limitation
  (Section 7).
- Oberon 2013 fixup chain field widths and the key check (Section 8).
- The byte-level SLR REL format (Section 3), in the SLRNK manual.
- Windows and Amiga ordinal practice (Section 10.4).

## Sources

Verified in this session (fetched and read):

- **S1** Digital Research, *LINK-80 Operator's Guide* (1980), chapter 1: LINK
  operation, switches, REL and IRL formats.
  <http://www.gaby.de/cpm/manuals/archive/link80/html/link80-1.htm>
- **S2** Same, chapter 2: RMAC.
  <http://www.gaby.de/cpm/manuals/archive/link80/html/link80-2.htm>
- **S3** Same, chapter 3: LIB.
  <http://www.gaby.de/cpm/manuals/archive/link80/html/link80-3.htm>
- **S4** Microsoft, *LINK-80 Linking Loader* reference (L80 manual, Heath/Zenith
  edition), including the object file format.
  <https://deramp.com/downloads/mfe_archive/040-Software/Microsoft/M-80%20and%20L-80%20Assembly%20Language%20Package/L-80%20Linker/Microsoft%20L80%20Linker%20searchable.pdf>
- **S5** John Elliott, *CP/M information archive: REL file format*.
  <https://www.seasip.info/Cpm/rel.html>
- **S6** Konamiman, *Nestor80 relocatable file format reference* (reverse
  engineering of M80 output, extension items).
  <https://github.com/Konamiman/Nestor80/blob/master/docs/RelocatableFileFormat.md>
- **S7** avwohl, *um80_and_friends release v0.3.49* (LINK-80 3.44 name limits
  and quirks). <https://github.com/avwohl/um80_and_friends/releases/tag/v0.3.49>
- **S8** John Elliott, *CP/M information archive: PRL file format*.
  <https://www.seasip.info/Cpm/prl.html>
- **S9** John Elliott, *CP/M information archive: CP/M 3 COM file header*.
  <https://www.seasip.info/Cpm/rsxrec.html>
- **S10** avwohl, *um80_and_friends release v0.3.48* (PRL origin, GENMOD).
  <https://github.com/avwohl/um80_and_friends/releases/tag/v0.3.48>
- **S11** *Relocation (computing)*, HandWiki (page relocation and bitmap
  construction). <https://handwiki.org/wiki/Relocation_(computing)>
- **S12** TDL, *Z80 Linker User's Manual* (1978), seen through a search
  excerpt only (iterative library search, six-character identifiers).
  <https://www.bitsavers.org/pdf/tdl/TDL_Z80_Linker_197803.pdf>

- **S20** A. R. Baldwin, *ASxxxx linker documentation* (object format, R-line
  modes, libraries). <https://shop-pdp.net/ashtml/asls01.htm>
- **S21** SDCC, `sdas/linksrc/aslink.h`.
  <https://sourceforge.net/p/sdcc/code/HEAD/tree/trunk/sdcc/sdas/linksrc/aslink.h>
- **S22** SDCC, `sdas/linksrc/lklibr.c`.
  <https://sourceforge.net/p/sdcc/code/HEAD/tree/trunk/sdcc/sdas/linksrc/lklibr.c>
- **S23** SDCC feature request #635, "Unused functions are not removed".
  <https://sourceforge.net/p/sdcc/feature-requests/635/>
- **S24** SDCC, `sdas/linksrc/lkmain.c`.
  <https://sourceforge.net/p/sdcc/code/HEAD/tree/trunk/sdcc/sdas/linksrc/lkmain.c>
- **S25** z88dk wiki, *z80asm directives* and *Tool - z80asm*.
  <https://github.com/z88dk/z88dk/wiki/Tool---z80asm---directives>,
  <https://github.com/z88dk/z88dk/wiki/Tool---z80asm>
- **S26** z88dk, object file format v18 and `objfile.h`.
  <https://github.com/z88dk/z88dk/blob/master/src/z80nm/object-file-format/obj_v18.txt>
- **S27** z88dk, `src/z80asm/src/c/modlink.c`.
  <https://github.com/z88dk/z88dk/blob/master/src/z80asm/src/c/modlink.c>
- **S28** z88dk issue #45. <https://github.com/z88dk/z88dk/issues/45>
- **S29** z88dk issue #2058. <https://github.com/z88dk/z88dk/issues/2058>
- **S30** z88dk issue #692. <https://github.com/z88dk/z88dk/issues/692>
- **S31** z88dk, object file format v19.
  <https://github.com/z88dk/z88dk/blob/master/src/z80nm/object-file-format/obj_v19.txt>
- **S40** GCC manual, *Optimize Options* (`-ffunction-sections`).
  <https://gcc.gnu.org/onlinedocs/gcc/Optimize-Options.html>
- **S41** GNU ld manual, *Options*. <https://sourceware.org/binutils/docs/ld/Options.html>
- **S42** GNU ld manual, *Input Section Keep*.
  <https://sourceware.org/binutils/docs/ld/Input-Section-Keep.html>
- **S43** LLVM lld, `lld/ELF/MarkLive.cpp`.
  <https://github.com/llvm/llvm-project/blob/main/lld/ELF/MarkLive.cpp>
- **S44** lld, *start-stop-gc*. <https://lld.llvm.org/ELF/start-stop-gc.html>
- **S45** F. Song (MaskRay), *Linker garbage collection*.
  <https://maskray.me/blog/2021-02-28-linker-garbage-collection>
- **S46** LLVM lld, `lld/ELF/ICF.cpp`.
  <https://github.com/llvm/llvm-project/blob/main/lld/ELF/ICF.cpp>
- **S47** LLVM lld, `lld/wasm/MarkLive.cpp`.
  <https://github.com/llvm/llvm-project/blob/main/lld/wasm/MarkLive.cpp>
- **S48** lld, *WebAssembly lld port*. <https://lld.llvm.org/WebAssembly.html>
- **S49** WebAssembly tool conventions, *Linking.md*.
  <https://github.com/WebAssembly/tool-conventions/blob/main/Linking.md>
- **S50** Go, `src/cmd/link/internal/ld/deadcode.go`.
  <https://github.com/golang/go/blob/master/src/cmd/link/internal/ld/deadcode.go>
- **S51** *Go 1.3 Release Notes*. <https://go.dev/doc/go1.3>
- **S52** R. Cox, *Go 1.3 Linker Overhaul*.
  <https://docs.google.com/document/d/1xN-g6qjjWflecSP08LNgh2uFsKjWb-rR9KA11ip_DIE/mobilebasic>
- **S53** A. Clements, *Building a better Go linker* (2019).
  <https://docs.google.com/document/d/1D13QhciikbdLtaI67U6Ble5d_1nsI4befEd6_k1z91U/mobilebasic>
- **S54** K. Thompson, *Plan 9 C Compilers*. <https://9p.io/sys/doc/compiler.html>
- **S55** R. Pike, *A Manual for the Plan 9 assembler*. <https://9p.io/sys/doc/asm.html>
- **S56** Plan 9 `8l` sources (`obj.c`, `pass.c`, `span.c`).
  <https://github.com/plan9foundation/plan9/tree/main/sys/src/cmd/8l>
- **S57** Go 1.2 `src/cmd/ld/go.c` (`deadcode()`).
  <https://github.com/golang/go/blob/release-branch.go1.2/src/cmd/ld/go.c>
- **S58** F. Song (MaskRay), *The dark side of RISC-V linker relaxation*.
  <https://maskray.me/blog/2021-03-14-the-dark-side-of-riscv-linker-relaxation>
- **S59** LLVM lld, `lld/ELF/Thunks.cpp` and `lld/ELF/Writer.cpp`.
  <https://github.com/llvm/llvm-project/blob/main/lld/ELF/Thunks.cpp>
- **S59a** Apple ld64, `branch_island.cpp`.
  <https://github.com/apple-oss-distributions/ld64/blob/main/src/ld/passes/branch_island.cpp>
- **S59b** T. G. Szymanski, "Assembling code for machines with span-dependent
  instructions", *CACM* 21(4), 1978 (abstract).
  <https://dl.acm.org/doi/10.1145/359460.359474>
- **S60** J. Sage, `SYNTAX.HLP` for SLRNK.
  <https://deramp.com/downloads/mfe_archive/040-Software/SLR%20Systems/SLRNK/SYNTAX.HLP>
- **S61** SLR Systems, *Z80ASM manual*.
  <https://www.s100computers.com/Software%20Folder/Assembler%20Collection/z80asm%20(SLR%20Systems).pdf>
- **S62** SLR Systems leaflet (SLRNK, SLRNK+), Internet Archive.
  <https://archive.org/details/slr-systems-z-80-asm-leaflet-zilog-mnemonic-relocating-macro-assembler>
- **S63** Phoenix Software Associates, *PLINK-II manual* (January 1981).
  <https://bitsavers.org/pdf/phoenixSoftwareAssociates/PLINK-II_Jan1981.pdf>
- **S64** Hi-Tech Software, `OBJCODE.TXT` (object format).
  <https://github.com/agn453/HI-TECH-Z80-C/blob/master/doc/OBJCODE.TXT>
- **S65** Hi-Tech Software, *HI-TECH C Z80 user manual* (`HTCZ80.TXT`).
  <https://github.com/agn453/HI-TECH-Z80-C/blob/master/doc/HTCZ80.TXT>
- **S66** A. Nikitin and M. Ogden, decompiled Hi-Tech 3.09 LINK and LIBR.
  <https://github.com/ogdenpm/hitech>

Located but not readable in this session:

- **S13** SLR Systems, *SLRNK Super-Linker User's Guide* (1984); requires a
  login. <https://oldcomputers.dyndns.org/public/pub/manuals/slrnk.pdf>
- **S14** Microsoft, *8080 Utility Software Package Reference Manual* (1981),
  scanned images without a text layer.
  <https://www.bitsavers.org/pdf/microsoft/cpm/Microsoft_8080_Utility_Software_Package_1981.pdf>
- **S15** Digital Research, *CP/M Plus Programmer's Guide* (RSX prefix and
  loader), not read.
  <https://www.df.lth.se/~pi/cpm/files/ftp.mayn.de/pub/cpm/systems/cpm-3/cpm3doc/cpm3-pgr.pdf>

Recalled references for the [R] sections (not fetched in this session):

- Niklaus Wirth and Jürg Gutknecht, *Project Oberon* (2013 edition),
  <https://people.inf.ethz.ch/wirth/ProjectOberon/>.
- Microsoft Learn, *Exporting from a DLL Using DEF Files* (ordinals and
  `NONAME`).
