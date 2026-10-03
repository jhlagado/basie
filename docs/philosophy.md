# Baton: Scheme without a garbage collector

*Working title. A baton is held by one runner at a time and is handed on, never
copied: the ownership model in one object. Baton descends from Skate.*

## The question

A 64K CP/M machine leaves room for one program, and every byte of that program
has to justify itself. The question is how expressive a language can be on
such a machine without wasting memory to pay for that expressiveness.

Languages of the CP/M era each made a different bargain:

- **BASIC** gave you convenience and an interpreter, at the cost of speed and
  structure.
- **Pascal** gave you structure and static types. For dynamic memory it gave
  you `new` and `dispose`, or the cruder `Mark` and `Release`.
- **Forth** gave you the whole machine, along with every responsibility for
  it.
- **Lisps** such as muLISP and XLISP gave you real expressiveness: recursion,
  lists as values, procedures as data. They took part of your memory to pay for
  it and paused unpredictably while they collected garbage.

Skate is a modern version of that last bargain, done carefully: a Scheme
compiled to native Z80 code, with a compact runtime and a garbage collector.
Baton asks whether the bargain is necessary at all, and argues that it isn't.

## The principle

> **What can be known before the program runs should be decided before it
> runs. The machine should pay at run time only for what can't be known any
> earlier.**

Two long-accepted conveniences break this rule in the same way.

An interpreter works out what the program means **every time it runs**. It
decodes each operation, finds each variable and dispatches on each form, over
and over, though the answers never change between runs. A compiler works this
out once and leaves the machine only the work itself.

A garbage collector works out what is still alive **every time it collects**.
It traces from the roots, marks what it reaches and sweeps the rest. Yet the
program's structure already says when most values die: a value bound in a
`let` that isn't returned or stored dies when the `let` ends. The collector
spends cycles and memory recovering a fact the compiler could have read from
the source.

Both make the running machine pay, again and again, for something that could
have been decided once.

## Compilers, not interpreters

The CP/M era was full of interpreters: BASIC, UCSD Pascal's p-code, most
Lisps. They were easy to write, small to ship and convenient to use. They also
spent most of their time not running the program: fetching, decoding and
dispatching, sometimes ten instructions of overhead for every instruction of
real work.

Skate already rejected that bargain. It compiles to native Z80 code, so the
processor runs the program instead of an interpreter. Baton carries the same
stance from time into space. A compiler removes the interpreter's repeated
rediscovery of what the program means. Ownership removes the collector's
repeated rediscovery of what is still alive. In both cases the work moves to
the compiler, which does it once, and the machine is left with only the
program.

## Against garbage collection

Garbage collection rests on an assumption: the machine has capacity to spare.
It assumes memory can sit idle as headroom, that objects can carry bookkeeping
the program never uses, and that the processor can periodically stop useful
work to search the heap for what is dead. On a workstation that assumption is
usually true, and it has been quietly accepted as the price of convenience.

It isn't acceptable as a principle. A collector is a confession that the
language doesn't know when its values die, so it hires a runtime mechanism to
find out, repeatedly, at the machine's expense. For most values the
information was always there in the program text. A collector is the price of
a language that declines to read it.

On a 64K machine the price can't be hidden:

- **Headroom.** A collector works best when the heap is far from full. Memory
  held in reserve for collection is memory the program can't use for live
  data.
- **Metadata.** Each object carries mark bits, allocation bits and start maps.
  In Skate a pair takes eight bytes, and part of that serves the collector
  rather than the program. Skate's documented ceiling is 2,144 live pairs, and
  collector bookkeeping is one of the things holding it there.
- **Code.** The collector, root descriptors, page management and escape
  tracking all occupy the same 64K as the program.
- **Time.** Collections arrive when the heap fills, not when the program is
  idle. On a machine driving a terminal, a serial line or a sound chip, that
  unpredictability is a cost of its own.
- **Opacity.** A collected program never says when memory is released. You
  find out how much memory it needs by running it until it fails.

## The case for garbage collection

The argument against collection is only worth making if the argument for it
is stated fairly, and that argument is strong.

Garbage collection is almost as old as high-level programming. McCarthy
described it for Lisp in 1960, and practical collectors followed through the
1960s and 1970s: reference counting, copying collectors, then incremental and
generational designs. Since then most languages above C have been collected by
default, because their data outlives the code that creates it. A procedure
builds a structure, returns it, and the structure is stored, shared and passed
around long after the procedure is gone. Collection lets the programmer stop
asking who is responsible for it.

Three points in its favour deserve to be taken seriously.

1. **Garbage collection is memory-safe.** The industry's memory-safety
   campaign mostly contrasts C and C++ with everything else. Go, Java, C# and
   every collected scripting language count as safe. A collector doesn't
   cause dangling references or double frees; it prevents them. What Rust
   showed was not that collection is unsafe, but that safety can be had
   *without* a collector's costs.
2. **Some problems have no natural owner.** Graphs with cycles, a compiler's
   intermediate representation, user-interface object trees and caches shared
   between threads don't divide neatly into one holder per value. Even Rust
   handles them with reference counting (`Rc`, `Arc`) and arenas, which are
   runtime memory management under another name. Baton's pools with integer
   indices are the same concession. Ownership is persuasive because it covers
   the common case. It doesn't make the hard cases go away.
3. **On large machines, collection can be fast.** A generational collector
   allocates by bumping a pointer and reclaims short-lived objects in bulk. On
   a server with gigabytes of memory its total throughput can beat `malloc`
   and `free`. Go chose a collector deliberately: it bought fast compilation,
   simple concurrency and a gentle learning curve, and paid with memory and
   processor time the machine had to spare.

## Where that case ends

Every one of those points rests on the same condition: **surplus capacity**.
Collection is safe, convenient and sometimes fast because the machine can
afford to hold memory in reserve, carry bookkeeping in every object and spend
processor time tracing the heap. Go's bet is reasonable because the memory on
a server really is spare.

On a 64K machine nothing is spare. Every byte of headroom is a byte of data
the program can't hold. Every mark bit is a bit taken from a value. Every
cycle spent tracing is a cycle not spent on the program. The condition that
justifies collection is absent, and so collection becomes what it always
partly was: a tax on the machine, levied because the language declined to say
who owns its values.

A collector also hides a decision the language should make. It exists because
the language can't express ownership, so a runtime mechanism is hired to work
it out. That is a fallback presented as a foundation. Ownership brings
benefits beyond memory, too: files, buffers and hardware devices are released
at a known point, which collected languages have never handled well. Java's
finalizers, which ran at no predictable time or not at all, are the standard
example of that failure.

Baton's position is therefore narrower than "garbage collection is wrong":

> **Garbage collection is a tax that is justified only where the machine has
> surplus capacity. Ownership should be the default everywhere. A language
> should state ownership first, and use runtime memory management only for
> what ownership can't express.**

On a small system, that remainder should be pools and arenas, never a
collector.

## Against manual memory

The traditional alternative is to manage memory yourself, as in Pascal's
`dispose`, C's `free` or Forth's dictionary discipline. This wastes almost
nothing. It costs in other ways:

- **Bugs.** A missed free leaks memory. A free that comes too early leaves a
  dangling reference. Freeing twice corrupts the heap. Each is easy to write
  and hard to find.
- **Lost expressiveness.** A function that builds and returns a list carries
  an unwritten contract about who frees it. Programmers become defensive: they
  copy data "just in case", avoid building structures and prefer global
  arrays. The program fills up with bookkeeping, and the bookkeeping obscures
  the algorithm.

That defensive style, global arrays indexed by integers, is what experienced
small-machine programmers settle on. It works because it gives up dynamic
structure in exchange for knowing exactly how much memory everything uses.

## Ownership: the third bargain

Rust, and more gently Hylo and Mojo, showed a third option: **let the
structure of the program determine how long data lives, and let the compiler
write the frees.**

Every value has one owner. When the owner goes away, the value goes away. When
a value is handed on, ownership moves with it. Code that only needs to look at
a value borrows it temporarily, and a borrow can't outlive the call it was
passed to. The compiler sees all of this in the source text, so it knows
exactly where each value dies and emits the free at that point.

Baton names these ideas after its namesake. A value's owner is its
**holder**. Handing a value on is a **pass**, and the point in the program
where that happens is the **exchange**. A read-only borrow is a **ticket**,
after the railway practice in which a driver could enter a single-track
section on a ticket once shown the staff, which stayed with its holder. A
borrow that may change the value in place is a **lease**. Releasing a value's
memory is **retiring** it, and using a value after passing it is a
**double-spend**. The README's glossary defines each term.

The cost moves from run time to compile time. The analysis happens once, when
the program is compiled. The program then runs with the memory behaviour of
careful hand-written code:

- Peak memory is the live data and nothing more.
- Memory is freed the moment a value dies, not on some later collection pass.
- There are no pauses, no mark bits and no collector in the image.
- The memory a program needs follows from its structure, rather than from
  running it and watching.

## Why this fits Scheme

At first, ownership and Scheme look like a mismatch. Scheme grew up with a
garbage collector and shares structure freely. But most of Scheme's expressive
power doesn't come from sharing. It comes from:

- procedures as values, and recursion as the natural way to process data;
- lists and vectors as **values** that can be built, transformed and returned;
- a small, uniform syntax in which the program's structure is visible;
- writing what you mean, such as `(map f xs)`, instead of managing how it
  happens.

Most list processing in ordinary Scheme is already linear. A list is built,
passed along, transformed, consumed and discarded. Shared tails and closures
over shared mutable state exist, but they're the exception. Baton's bet is
that the common case can be made free and the uncommon cases can be made
explicit.

There is an unexpected payoff. When the compiler knows a list has exactly one
owner, a "pure" transformation like `map` can reuse the old cells for the new
list. Code written in a clean functional style becomes in-place mutation in
the machine. You write in the expressive style and get the memory behaviour of
the imperative one. Koka and Lean exploit this using reference counts. A
language with strict single ownership gets it with no counts at all.

Value semantics also make programs easier to reason about. When two names
can't silently refer to the same mutable object, a procedure's effects are
visible in its parameters. Programs become easier to read, test and change,
which matters even more when the debugger is a CP/M console.

## What it gives up

- **Shared list tails.** If two lists need the same tail, one of them gets a
  copy.
- **Closures sharing mutable state.** The classic `make-counter`, where
  several closures update one captured variable, is written another way: with
  an `inout` parameter or a slot in a vector.
- **Reusable continuations (`call/cc`).** Re-entering a frame whose values
  have been freed is meaningless. Escape-only exits remain, with cleanup on
  the way out.
- **Arbitrary object graphs.** Cyclic or heavily shared structures are
  expressed as **vectors plus integer indices**.

The last loss is the least painful, because indices are what small-machine
programmers already use. A graph stored as a vector of nodes with integer links
is compact, can be written to disk directly, never confuses an allocator and
makes its size visible. Baton doesn't force a foreign discipline on CP/M
programmers. It turns their existing habit into part of the language and
gives them lists, recursion and procedures as values around it.

The approach has precedent on CP/M. Forth's dictionary allocates by moving a
pointer and frees by moving it back. Turbo Pascal's `Mark` and `Release` freed
a whole region at once. Both are arenas, and arenas fit ownership naturally: a
scope that allocates temporary data and discards it all on exit.

## The design in brief

- **Dynamic types, static ownership.** Values keep their runtime tags, as in
  Scheme. Ownership comes from how variables are used, which the compiler can
  find without type annotations.
- **The last use of a variable passes its value.** Every other use gives a
  ticket.
- **Tickets and leases are second class.** They can be given to procedures,
  but they can't be stored or returned. Built-ins such as `car`, `cdr` and
  `vector-ref` may yield tickets to parts of a value; user procedures always
  return values they hold.
- **Storing or returning a ticketed value copies it.** The copy is free for
  numbers, characters and booleans, and is a deep copy for heap values. The
  compiler reports each heap copy so the cost isn't hidden.
- **Values retire where they die.** Dead values are retired before a tail call
  so proper tail calls survive, and long lists are retired iteratively.
- **Parameter modes** are the only new syntax: a ticket by default, `inout`
  for a lease, and `owned` for a parameter that takes the value by pass.
- **Globals are protected at run time.** While a global's value is out on a
  ticket or lease, assigning to that global traps. This replaces whole-program
  analysis, which a compiler running on the Z80 can't afford, and prevents a
  callee from retiring a value its caller is still using.
- **Escapes clean up.** Leaving frames through an escape retires what those
  frames held, either by running their retirements or by resetting a
  per-frame arena.
- **Vectors and indices** handle anything shaped like a graph.

A taste:

```scheme
(define (push (inout stack) x)        ; a lease on the caller's variable
  (set! stack (cons x stack)))        ; last use of stack: a pass

(define (sum xs)                      ; xs arrives on a ticket (the default)
  (let loop ((p xs) (acc 0))
    (if (null? p) acc
        (loop (cdr p) (+ acc (car p))))))

(let ((s '()))
  (push s 1) (push s 2)
  (write (sum s)))                    ; s retires here; no collector involved
```

## The honest boundary

The principle has to be applied consistently, or it becomes a slogan. Some
things really can't be known before the program runs:

- **Data that is genuinely shared.** These are the cases for indices and
  run-time checks.
- **Tickets and leases on globals.** The compiler can't see every procedure
  that touches a global, so Baton checks these at run time.
- **Escapes.** Where an escape will exit from isn't known until it happens, so
  cleanup must run on the way out.

Those run-time costs are the principle working correctly. They pay only for
what is truly unknown.

**Dynamic typing** faces the same test. Value tags make the machine rediscover
each value's type at run time. Some of that information is genuinely dynamic:
heterogeneous lists, generic printing, data read from a file. A lot of it
isn't. Within a procedure, `(+ i 1)` with an integer `i` doesn't need a tag
check. The consistent position is to keep tags where the type truly varies and
let the compiler remove them where it can prove the type, starting with local
inference over integers and lists. That puts type inference on the roadmap
under the same principle as ownership. It also pairs with the 24-bit value
plan: a value the compiler knows is an untagged integer can use all 24 bits
for its payload, with nothing taken by the tag.

## The real costs

Ownership isn't free. It moves the costs to new places:

- **Copies can be hidden.** Implicit deep copies keep the language feeling
  like Scheme, but they can surprise you. The compiler's notes on copies are
  what keep this honest.
- **Ticket and lease checks on globals happen at run time.** Each one is a bit
  test, cheap but not zero.
- **Unwinding has to be designed** carefully, because errors and escapes still
  need to retire what was allocated.
- **The compiler gets more complex.** Last-use analysis, retire placement and
  double-spend diagnostics all have to fit into a compiler that itself runs in 64K. A
  backward pass over s-expressions keeps this manageable. A full Rust-style
  borrow checker would not be.
- **Some programs get harder to write.** Programs that rely on heavy sharing,
  such as graph algorithms or memoisation tables, need indices or explicit
  copies.

These costs land in compile time, a few run-time bit tests and some deliberate
choices by the programmer. Garbage collection's costs fall on memory and
timing, which are exactly what a CP/M machine has least of.

## Lineage

Baton descends from [Skate](../../skate), a Scheme for Z80 CP/M machines
written in Z80 assembly. Skate supplies the reader, the CP/M toolchain, the
ATOM-based build, the value conventions, the four-byte cell contract, ports
and file I/O, and the proof harness. Baton keeps those and replaces the
garbage collector with ownership.

Prior art it draws on:

- **Linear logic** (Girard, 1987) and **"Linear types can change the world!"**
  (Wadler, 1990): the theory of values used exactly once.
- **Clean**: uniqueness types for in-place update.
- **Henry Baker's Linear Lisp** (1992): linear types applied to cons cells.
- **Rust**: affine ownership with borrowing, made practical.
- **Swift's Ownership Manifesto** (2017): `inout` and the law of exclusivity,
  enforced at run time for globals.
- **Hylo** (formerly Val): mutable value semantics and second-class
  references.
- **Koka's Perceus** and **Lean's "Counting Immutable Beans"**: in-place reuse
  of uniquely owned data.
- **Pre-Scheme** and **Carp**: Lisps without a garbage collector.
- **Tofte–Talpin regions**, **Forth's dictionary** and **Turbo Pascal's
  `Mark`/`Release`**: arenas.

## Why build it

Small systems are where language design shows what matters. On a large
machine, a language can carry a collector, a runtime and generous headroom
without anyone noticing. At 64K, every mechanism has to pay for itself.

Baton claims you don't have to choose between programs that say what they mean
and programs that use the machine well. The source reads like Scheme:
recursive, list-shaped and built from procedures. The resulting program frees
memory at the instant it dies, keeps no collector, reserves no headroom and
keeps its memory use visible in the source.

It rests on one rule: the running machine should never pay for what the
compiler could have known. Skate applied that rule to time by compiling instead
of interpreting. Baton applies it to memory by tracking ownership instead of
collecting garbage, and eventually to types by inferring them instead of
checking tags. On a 64K machine there are no spare resources to waste, and the
language shouldn't assume there are.
