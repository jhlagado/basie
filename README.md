# Baton

A statically typed systems language for Z80 machines, compiled to native code
in a single pass, with memory whose lifetime the compiler can see.

Baton is the successor to [Nucleus](../nucleus). It is at the design stage, and
the name is a working title.

## The name

A relay baton is held by one runner at a time. It is passed on, never copied,
and the race depends on every hand-off being clean. Baton applies that idea to
storage: every object has one holder, access to it is handed to a routine for
the length of a call and then handed back, and no reference can outlive the
storage it points into.

## What Baton is

Nucleus showed that a small, strictly specified language can be compiled to
native Z80 code by a compiler that itself runs on the Z80, in one streaming
pass. It also showed where it was too narrow for general use: no signed
integers, nothing wider than 16 bits, no floating point, no storage shorter-lived
than the whole program, and no way to drop unused code from the output.

Baton keeps Nucleus's foundations and widens the language:

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

## The principle

> What can be known before the program runs should be decided before it runs.
> The machine should pay at run time only for what can't be known any earlier.

This is why Baton compiles instead of interpreting, uses static types instead
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

- [Philosophy](docs/philosophy.md): the motivation, the principle and what
  Baton learned from Nucleus.
- [Design decisions](docs/design-decisions.md): the language decisions made so
  far and the questions still open.
- [Feature inventory](docs/feature-inventory.md): every feature, its cost
  against the 24K compiler budget, and whether it is in version 1 or 2.
- [Input, output and effects](docs/io-and-effects.md): services and the
  external-effects channel instead of operating-system or port primitives.
- [Services](docs/services.md): the version 1 console, file, command-line and
  machine services, and their failure codes.
- [Memory safety](docs/memory-safety.md): how Baton is memory safe without a
  garbage collector: storage classes, aliases, pools and handles, `move`, and
  stack bounds.
- [Implementation plan](docs/implementation-plan.md): how Baton will be built:
  a reference toolchain in TypeScript on Deno, then the native Z80 toolchain.
- [Build pipeline](docs/build-pipeline.md): why Baton compiles to machine-code
  blobs and links them, and how the pieces fit.
- [Object format](docs/object-format.md): the files passed from the compiler to
  the linker, byte for byte.
- [Linker](docs/linker.md): marking, placement, output and diagnostics.
- [Toolchain](docs/toolchain.md): the `BATON` executable, its command line,
  files and memory plan.
- [CP/M target](docs/cpm-target.md): profiles, memory map, startup and exit.
