# Basie

A statically typed systems language for Z80 machines, compiled to native code
in a single pass, with memory whose lifetime the compiler can see.

## The name

Basie is BASIC with the C dropped, and a nod to Count Basie, who was famous
for playing few notes and making every one of them count. That is the
language's whole approach: a BASIC that reads like the structured BASICs and
Pascals of the CP/M era, with keyword-led statements, `if`/`elseif`/`end`,
counted `for` loops and `select` with `case`, compiled in a single pass to
Z80 machine code in which every byte has to justify itself. The twist is
underneath: static types, and memory safety without a garbage collector,
where every object has one owner, access is lent to a routine for the length
of a call, and no reference can outlive the storage it points into.

*Few notes. Make them count.*

## Status

Version 1 is complete: the native compiler `BASIE.COM` and linker `BLINK.COM`
run on CP/M 2.2 and compile every program the reference toolchain compiles,
byte for byte, apart from the open arrays of handles that wait for version 2
([roadmap](docs/roadmap.md) step 74, [limits](docs/limits.md)). `BASIE.COM`
takes 24,927 bytes and a 2,611-byte overlay area, 1,134 bytes under its 28K
limit. Version 2 is planned in [the version 2 plan](docs/version-2.md).

## What Basie is

Basie is a small, strictly specified language compiled to native Z80 code by
a compiler that itself runs on the Z80, in one streaming pass. It is meant for
general use: it has signed and unsigned integers of 8, 16 and 32 bits,
floating point, storage that lives only as long as a routine call or a pool
slot's owner, and a linker that drops unused code from the output.

Its foundations:

- **Single-pass compilation.** The compiler reads its source once.
  Declarations come before use, and a forward declaration is a routine's
  complete signature.
- **Static types, no tags.** Every value's representation is known at compile
  time, so nothing at run time spends bits or cycles rediscovering it.
- **Plain syntax.** Statements end at a newline, blocks end with `end`, and
  control flow uses words such as `if`, `elseif`, `for` and `and`. The style is
  closer to BASIC and Lua than to C.
- **Second-class references.** Routines receive aggregates by alias, and an
  alias can't be stored, so it can never dangle.
- **Checked safety.** Out-of-range indexing, narrowing conversions and division
  by zero trap rather than corrupting memory.
- **Tree shaking.** A separate link step places only the routines, data and
  runtime helpers the program can reach.

## Building and running

The toolchain is built and tested with [Deno](https://deno.com):

```
deno task test       # the whole test suite
deno task release    # build/BASIE.DSK, a bootable CP/M 2.2 disk
deno task disktime   # a build's time on modelled 8-inch and 5.25-inch floppies
```

The release disk holds `BASIE.COM`, the compiler, with its overlays
(`BASIE.OVL`) and messages (`BASIE.MSG`); `BLINK.COM`, the linker;
`CPM22.BRL`, the runtime library; the standard library's parts; and the
examples. On CP/M, `BASIE ADVENT` compiles `ADVENT.BSI` and links
`ADVENT.COM`.

## The principle

> What can be known before the program runs should be decided before it runs.
> The machine should pay at run time only for what can't be known any earlier.

This is why Basie compiles instead of interpreting, uses static types instead
of runtime tags, checks storage lifetimes at compile time instead of collecting
garbage, and chooses addresses only once it knows which code is live.

## Terms

These terms are provisional, but the documents use them consistently.

| Term | Meaning |
| --- | --- |
| **holder** | The variable, field or slot that owns an object's storage. |
| **ticket** | Temporary read access to an object that stays with its holder. An aggregate parameter is a ticket: it can be used during the call but not stored or returned except as an alias the signature declares. |
| **lease** | Direct access to a node held in the caller's own owning local, for the length of a call or a `select` arm. |
| **`var` parameter** | A parameter the routine may change, written `var` before its name. |
| **move** | Handing ownership of a pool slot to a new owner, written `move x`. The source is left empty. |
| **free** | Releasing a pool slot when its owner is finished with it. Always automatic. |
| **pool** | A fixed number of slots of one record type, reached through handles, used for dynamic or graph-shaped data. |
| **handle** | A reference to a pool slot: owning (`nodes`, `nodes?`) or an identifier (`id nodes`, `id nodes?`). |
| **arena** | A region freed all at once, for temporary data within a scope. |
| **blob** | The unit the linker places or removes: one routine, constant or variable. |

## Documents

- [Philosophy](docs/philosophy.md): the motivation, the principle and the
  constraints that shape the design.
- [Basie compared with Rust](docs/rust-comparison.md): syntax, types,
  ownership and errors side by side with Rust.
- [Design decisions](docs/design-decisions.md): the language decisions made so
  far and the questions still open.
- [Feature inventory](docs/feature-inventory.md): every feature, its cost
  against the compiler budget (26K target, 28K limit), and whether it is in version 1 or 2.
- [Input, output and effects](docs/io-and-effects.md): services and the
  external-effects channel instead of operating-system or port primitives.
- [Services](docs/services.md): the version 1 console, file, command-line and
  machine services, and their failure codes.
- [Memory safety](docs/memory-safety.md): how Basie is memory safe without a
  garbage collector: storage classes, aliases, pools and handles, `move`, and
  stack bounds.
- [Roadmap](docs/roadmap.md): the implementation broken into numbered steps
  and milestones.
- [Limits register](docs/limits.md): every limit in Basie, its reason, and the
  minimum capacities the toolchain guarantees.
- [Test report](docs/test-report.md): what the test suite proves, the large
  programs and stress tests, and the limits they found.
- [Version 2 plan](docs/version-2.md): enumerations and variants, typed
  failure codes, expression blocks and routine values, and the room they
  need.
- [Implementation plan](docs/implementation-plan.md): how Basie will be built:
  a reference toolchain in TypeScript on Deno, then the native Z80 toolchain.
- [Build pipeline](docs/build-pipeline.md): why Basie compiles to machine-code
  blobs and links them, and how the pieces fit.
- [Object format](docs/object-format.md): the files passed from the compiler to
  the linker, byte for byte.
- [Linker](docs/linker.md): marking, placement, output and diagnostics.
- [Toolchain](docs/toolchain.md): the `BASIE` executable, its command line,
  files and memory plan.
- [CP/M target](docs/cpm-target.md): profiles, memory map, startup and exit.

## Licence

Basie is free software, released under the GNU General Public License,
version 3 ([LICENSE](LICENSE)).
