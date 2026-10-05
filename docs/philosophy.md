# Basie: philosophy

*Basie: BASIC with the C dropped, and a nod to Count Basie, who made few notes count. The successor to Nucleus.*

## The question

A 64K Z80 machine leaves room for one program, and every byte of that program
has to justify itself. The question is how general a language can be on such a
machine without the machine paying for that generality at run time.

Languages of the CP/M era each made a different bargain:

- **BASIC** gave you convenience and an interpreter, at the cost of speed and
  structure.
- **Pascal** gave you structure and static types, and for dynamic memory `new`
  and `dispose`, or the cruder `Mark` and `Release`.
- **Forth** gave you the whole machine, along with every responsibility for it.
- **C** gave you speed and control, and left memory safety to the programmer.

Basie's aim is to keep the native speed and visible memory use of the last two
while keeping the safety and readability of the first two.

## The principle

> **What can be known before the program runs should be decided before it
> runs. The machine should pay at run time only for what can't be known any
> earlier.**

Several familiar conveniences break this rule in the same way: they make the
running machine rediscover, again and again, something that never changes.

- An **interpreter** works out what the program means every time it runs. A
  compiler works it out once.
- **Runtime type tags** make every operation check what kind of value it was
  given. Static types settle that once, at compile time, and free the tag bits
  for data.
- A **garbage collector** works out what is still alive every time it collects.
  The program's structure usually says when storage dies; the compiler can read
  that from the source once.
- **Placing code before knowing whether it is used** forces every program to
  carry routines it never calls. Basie chooses addresses only after the whole
  program has been seen.

Each of these moves work from the machine to the compiler, which does it once.

## Static types without tags

In a dynamically typed language every value carries a tag, and the tag takes
bits away from the value. In a statically typed language the compiler already
knows each value's representation, so no tag is needed. A `u8` takes one byte,
a `u16` two, an `i32` four, and all of their bits hold data.

This also settles how wide numbers should be. Basie's working size is 16 bits,
because the Z80 handles 16-bit values natively: a 16-bit add is one byte of
code. Wider types (`u32`, `i32`, `f32`) are there when a program asks for them,
and only programs that use them pay for the runtime helpers they need.

## Memory without a collector

Nucleus answered the memory question in the simplest way possible: every
aggregate lives for the whole program. Routines receive aggregates by alias,
an alias can't be stored, and since nothing is ever freed, nothing can dangle.

That answer is safe and cheap, but too narrow. Programs need temporary storage
shorter-lived than the program, and some need dynamic data. Basie extends
Nucleus in the same spirit rather than adopting a collector:

- **Second-class references.** An alias exists only as a parameter for the
  length of a call, or as a result the caller uses at once. It can't be stored
  in a variable or a data structure.
- **Local aggregates.** Records, arrays and strings may live for the length of
  a routine call. A routine may return an alias only into storage that outlives
  it, and its signature says which parameters a returned alias may point into.
  The compiler checks this locally, in one pass.
- **Pools.** Dynamic data lives in fixed pools of records, reached through
  handles. Each slot has exactly one owner and is freed automatically when its
  owner goes away; other references are identifiers, checked on every use. No
  reference counts and no collector are needed. Arenas, freed all at once, may
  follow in a later version.

### The case for garbage collection

The case for collection deserves a fair statement. Collection is memory-safe:
it prevents dangling references and double frees rather than causing them.
Some problems, such as graphs with cycles, have no natural single owner. And on
a large machine a generational collector can be fast.

Each of those points rests on surplus capacity: spare memory held as headroom,
spare bits in every object for bookkeeping, spare processor time for tracing.
A 64K machine has none to spare. On such a machine, collection is a tax levied
because the language declined to say who holds its storage. Basie states that
in the source, and uses runtime mechanisms only where the source genuinely
can't.

### Against manual memory

Manual memory management wastes almost nothing, but it is the main source of
memory bugs: leaks, dangling references and double frees. It also pushes
programmers into a defensive style of global arrays indexed by integers, chosen
because it makes memory use predictable.

Basie keeps the predictability of that style and makes it safe. Global arrays,
pools and indices remain first-class tools; the language adds the lifetime
rules that let the compiler check them.

## One pass, then one link step

The Basie compiler, like Nucleus's, reads its source exactly once and streams
its output. This keeps it small enough to run on the machine it targets, and it
shapes the language: names are declared before use, a forward declaration
carries a routine's complete signature, and every rule the compiler enforces
can be checked with what it has already seen.

One thing a single pass can't know is whether a routine will be called later in
the source. Nucleus placed every routine as soon as it was compiled, so unused
routines stayed in the output. Basie separates compilation from placement: the
compiler writes position-free code, and a small linker removes what is
unreachable before it assigns addresses. The
[build pipeline](build-pipeline.md) describes the design.

## Lessons from Nucleus

- **A strict specification pays for itself.** Nucleus specified every rule,
  capacity and trap before implementing it, and that made the compiler small
  and its behaviour predictable. Basie keeps that discipline.
- **Second-class aliases work.** Nucleus programs never needed to store a
  reference, and the rule removed lifetime problems entirely.
- **The type set was too small.** Without signed or wider integers, and without
  floating point, Nucleus was a systems kernel rather than a general language.
- **One lifetime is too few.** Program-lifetime storage alone forces every
  temporary buffer into a global.
- **Final addresses at emission cost too much.** They ruled out tree shaking,
  forced every forward branch to its longest form and made the compiler track
  every unresolved call site.

## The honest boundary

Some things really can't be known before the program runs:

- **Array indices** are checked at run time because their values are data.
- **Identifiers into pools** are checked on use, because whether a slot has
  been freed since is a run-time fact.
- **Memory size** varies between machines, so a program checks at startup that
  it fits.

Those run-time costs are the principle working correctly: they pay only for
what is truly unknown.

## Lineage

Basie descends from Nucleus, and through it from the long tradition of small
compiled languages: Pascal, Modula-2 and Oberon for single-pass compilation
and explicit declarations, BASIC and Lua for approachable syntax.

Its memory model draws on:

- **Swift's Ownership Manifesto** (2017): `inout` and the law of exclusivity.
- **Hylo** (formerly Val): mutable value semantics and second-class references.
- **Rust**: ownership and borrowing, made practical.
- **Tofte–Talpin regions** and **Turbo Pascal's `Mark`/`Release`**: arenas.
- **Generational indices**, as used in game engines, for pools.

## Why build it

Small systems are where language design shows what matters. A large machine can
carry an interpreter, a collector and generous headroom without anyone
noticing. At 64K, every mechanism has to pay for itself.

Basie claims you don't have to choose between programs that are safe and
readable and programs that use the machine well. It rests on one rule: the
running machine should never pay for what the compiler could have known.
