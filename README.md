# Baton

A Scheme-like language for Z80 machines running CP/M, with memory managed by
ownership instead of a garbage collector.

Baton is at the design stage. The name is a working title.

## The name

A relay baton is held by one runner at a time. It is passed on, never copied,
and the race depends on every hand-off being clean. That is the whole memory
model in one object: every value has exactly one holder, values move from
holder to holder, and when the last holder is finished with a value, its
memory is released at once.

## The problem

Baton descends from [Skate](../skate), a Scheme compiled to native Z80 code for
64K CP/M machines. Skate showed that a real Scheme fits on such a machine. It
also showed where the strain is. Scheme's memory model assumes a garbage
collector, and a garbage collector assumes spare capacity:

- spare memory, held back as headroom so the collector can work;
- spare bytes in every object, for mark and allocation bits;
- spare code space, for the collector itself;
- spare processor time, spent tracing the heap instead of running the program.

A 64K machine has none of these to spare. Skate looked for a collector cheap
enough to stop mattering and didn't find one. Every design moved the cost
somewhere else rather than removing it.

## The idea

Baton treats memory management as an **ownership problem** and gives it to the
**compiler**.

For most values, the program text already says when they die: a list built in
a `let` and never returned or stored dies when the `let` ends. A garbage
collector rediscovers that fact at run time, repeatedly, at the machine's
expense. Baton's compiler reads it from the source once and emits the release
at the exact point the value dies. The running program carries no collector,
no mark bits and no headroom. Its peak memory is its live data.

This is the same move Skate already made for execution. An interpreter works
out what a program means every time it runs; a compiler works it out once.
Baton applies that principle to memory:

> What can be known before the program runs should be decided before it runs.
> The machine should pay at run time only for what can't be known any earlier.

## Where this comes from

Garbage collection is almost as old as high-level programming. McCarthy
described it for Lisp in 1960, and practical collectors followed through the
1960s and 1970s: reference counting, copying collectors, then incremental and
generational ones. Since then, most languages above C have been garbage
collected by default, because their data outlives the code that creates it.

The alternative, managing memory by hand, has proved unsafe at scale. Leaks,
dangling references and double frees are a leading source of security
vulnerabilities in C and C++ code. Memory safety is now an industry-wide
concern, and Rust showed that it can be achieved without a collector: the
compiler tracks who owns each value and when it is released. Swift, Hylo and
Mojo have since made that idea gentler, with fewer annotations and more
inference.

Baton brings this modern answer to an old machine, where it matters most.

## Terms

These terms are provisional, but the documents use them consistently.

| Term | Meaning |
| --- | --- |
| **holder** | The one variable, field or slot that owns a value. Every heap value has exactly one. |
| **pass** | Moving a value to a new holder. The old holder can no longer use it. The last use of a variable passes its value. |
| **exchange** | The point in the program where a pass happens. |
| **ticket** | Temporary read access to a value that stays with its holder. A ticket can be given to a procedure but can't be stored or returned. (From railway single-line working, where a driver could proceed on a ticket after being shown the staff, which stayed with its holder.) |
| **lease** | Temporary exclusive access to change a value in place, returned to the holder when the call ends. Written `inout` in parameter lists. |
| **retire** | Releasing a value's memory when its holder is finished with it. The compiler places every retire. |
| **copy** | Making a second, independent value. Free for numbers, characters and booleans; a deep copy for heap values, and the compiler reports each one. |
| **double-spend** | Using a value after it has been passed. This is a compile-time error. |
| **pool** | A vector of records addressed by integer index, used for shared or graph-shaped data. |
| **arena** | A region that is freed all at once, for temporary data within a scope. |

## Compared with Skate

| | Skate | Baton |
| --- | --- | --- |
| Language | Scheme subset | Scheme-like; values instead of shared places |
| Compilation | Native Z80, compiled on CP/M | Same |
| Memory | Garbage collected heap | Ownership; the compiler places every release |
| Run-time memory cost | Collector code, mark and allocation metadata, headroom | None beyond the live data |
| Timing | Pauses when the heap fills | No collection pauses |
| Sharing | Shared list tails and shared closure state | One holder per value; copies or pools when sharing is needed |
| Closures | Capture shared mutable variables | Capture by copy or by pass |
| Continuations | One-shot `call/ec` | Escapes that retire what they leave behind |
| Graphs | Pointers | Pools and integer indices |
| Errors found | At run time, often as heap exhaustion | Ownership errors at compile time |

Baton expects to reuse much of Skate: the reader, the CP/M toolchain and
ATOM-based build, the value conventions and four-byte cell contract, ports and
file I/O, and the proof harness.

## Documents

- [Philosophy](docs/philosophy.md): the motivation and the design in brief,
  including what Baton gives up and what it costs.
