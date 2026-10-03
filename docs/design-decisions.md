# Baton design decisions

- Status: working record
- Date: 2026-10-03

This document records the language decisions made so far, with the reasons for
each, and the questions still open. Where Baton keeps a Nucleus rule unchanged,
the entry says so and points at the Nucleus specification
(`../nucleus/docs/specification.md`). Examples use Nucleus 0.1 syntax unless
they show a new feature.

## Decided

### D1. One source pass

The compiler reads its source once. Names are declared before use. A forward
declaration is a routine's complete and only signature, and the body that
completes it begins with the abbreviated header `sub NAME`, exactly as in
Nucleus §4.6:

```nucleus
forward sub relay(text as string[]) fails

sub emit(text as string[]) fails
    relay(text) else fail
end

sub relay
    emit(text) else fail
end
```

**Why.** It keeps the compiler small enough to run on the target, and it keeps
every rule checkable from what the compiler has already seen. A design rule
follows from it: **fixups fill in code addresses, never missing semantic
information.** Any fact the compiler needs at a call, such as a result's
lifetime (D8), must be in the signature before the call.

### D2. Statement syntax

Baton keeps Nucleus's lexical rules (§3.4):

- a logical newline is the only statement terminator;
- a line ending inside `(` or `[` is whitespace, which is how an expression
  spans several lines; and
- blocks close with a plain `end`.

Control flow uses words: `if`, `elseif`, `else`, `for`, `while`, `and`, `or`,
`not`.

**Not adopted:** Lua's `then`, `do` and `function`. Each would reserve a word
and add scanner and table entries to the compiler without changing meaning.
Nucleus §3 already requires that any new reserved word be justified by its
cost.

### D3. Numeric types

| Type | Size | Range or format |
| --- | --- | --- |
| `u8` | 1 | 0 to 255 |
| `i8` | 1 | −128 to 127 |
| `u16` | 2 | 0 to 65,535 |
| `i16` | 2 | −32,768 to 32,767 |
| `u32` | 4 | 0 to 4,294,967,295 |
| `i32` | 4 | −2,147,483,648 to 2,147,483,647 |
| `f32` | 4 | IEEE 754 single-precision layout (D7) |
| `boolean` | 1 | `false`, `true` |

**Why these.**

- **16 bits is the working size.** The Z80 handles 16-bit values natively: a
  16-bit add is the one-byte `ADD HL,DE`. Counters, indices, addresses and
  characters stay cheap.
- **Signed types are new.** Nucleus 0.1 had only `u8`, `u16` and `boolean`. Their
  absence was a larger gap for general use than the lack of floating point.
- **`i8`** is for signed displacements and small deltas stored in records.
- **32-bit types are opt-in.** The Z80 has three register pairs, so a 32-bit
  binary operation doesn't fit in registers and becomes a call to a runtime
  helper. Programs that never use 32-bit types don't carry those helpers; the
  link step removes them.
- **No tags, so no cell size.** Values are untyped bits at run time, sized by
  their static type. There is no reason to choose a width to leave room for tag
  bits.
- **No 24-bit integer.** With no tags to make room for, a 24-bit type has no
  arithmetic advantage. Its only use would be addresses on the eZ80 or banked
  "far" pointers, which would be a separate address type if they are ever
  needed.

### D4. Conversions

- **Widening is implicit where no value can be lost:** `u8` to `u16` to `u32`,
  `i8` to `i16` to `i32`, `u8` to `i16`, `u16` to `i32`, and integer to `f32`
  only where the conversion is exact (`u8`, `i8`, `u16` and `i16`).
- **Narrowing is explicit and checked.** A conversion such as `u8(x)` or
  `i16(y)` traps with `narrowing` when the value doesn't fit, as `u8(...)` does
  in Nucleus §9.5. When the compiler can prove from constants that it won't
  fit, the source is invalid.
- **Signedness changes are checked conversions.** Converting a negative value to
  an unsigned type traps. Converting an unsigned value above the signed range
  traps.
- **`f32` to integer** truncates toward zero and traps when the result is out
  of range.
- **Mixed signed and unsigned operands are an error,** not a promotion. A
  program converts one operand explicitly. This avoids C's most common
  arithmetic trap, where a negative signed value silently becomes a huge
  unsigned one.

### D5. Arithmetic wraps

Addition, subtraction, multiplication and negation wrap modulo the width of the
type, as in Nucleus §9: `65535 + 1` is `0` in `u16`. Signed types wrap in two's
complement.

**Why.** Trapping on overflow would add about 3 bytes and 10 T-states to every
unsigned add and subtract (`JP C,trap`), and more for signed operations,
because `ADD HL,DE` doesn't set the overflow flag and the check needs
`OR A` / `ADC HL,DE` / `JP PE,trap`. In arithmetic-heavy code that could be
roughly 5 to 10 per cent of code size. Narrowing (D4) is where values silently
become wrong, and checking it is cheap because it happens far less often than
addition. Checked arithmetic operators can be added later if programs need
them. Debug and release builds never behave differently.

### D6. Traps and failures stay separate

As in Nucleus §14 and §15:

- **`fails`** marks a routine whose errors a caller can recover from, such as
  I/O. Callers must deal with them using `else fail` or `handle`.
- **A trap** ends the program immediately with a stable reason. It can't be
  caught, so it appears in no signature.

An expression that may trap, such as `a / b`, is not failable. New checks
(D4, D7) are traps.

Trap reasons carry over from Nucleus (`bounds`, `narrowing`,
`division-by-zero`, `loop-range`, `activation-capacity`, `unhandled-error`),
with additions for floating point (D7).

### D7. Floating point

`f32` uses the IEEE 754 single-precision storage layout: one sign bit, an 8-bit
exponent and a 23-bit fraction. Arithmetic is simplified for an 8-bit machine:

- **Round to nearest, ties to even,** with no other rounding modes and no
  exception flags.
- **Flush to zero.** IEEE's denormal numbers fill the gap between the smallest
  normal value (about 1.2 × 10⁻³⁸) and zero. Supporting them adds code to every
  operation. Baton treats denormal inputs as zero and returns zero for results
  that would be denormal. The only visible effect is on values below
  10⁻³⁸, where two different numbers can subtract to zero.
- **No infinity or NaN.** Division by zero traps with `division-by-zero`, a
  result too large for `f32` traps with a new `float-overflow` reason, and an
  invalid operation such as the square root of a negative number traps with
  `float-invalid`. Every `f32` value is therefore an ordinary finite number,
  and comparison behaves normally (`x = x` is always true).

**Why.** The IEEE layout keeps values compatible with other tools and file
formats. The simplifications remove the most expensive parts of a software
float library while affecting almost no real program on this class of machine.

### D8. Local aggregates and the `from` clause

Baton allows records, arrays and bounded strings as routine locals, living for
the length of the call. Nucleus had only program-lifetime aggregates (§7.9),
which forced every temporary buffer into a global.

A routine may return an alias, as in Nucleus, but now the alias may point into
storage that dies. The rule:

- A returned alias may point into a **global**, or into a **parameter listed in
  the routine's `from` clause**.
- It may never point into the routine's own local.

```nucleus
sub pick(items as Entry[8], index as u8) as Entry from items
    return items[index]
end
```

At a call, the result lives exactly as long as the arguments passed for the
`from` parameters. If any of them is rooted in a local aggregate, the result may
be used within the calling routine but can't be returned from it, unless that
local is in turn a parameter listed in the caller's own `from` clause.

```nucleus
sub bad() as Entry
    var mine as Entry[8]
    return pick(mine, 0)        // error: result points into the local mine
end
```

A routine whose results always point into globals needs no `from` clause.

**Why an explicit clause instead of inference.** Inferring which parameters a
result may point into would need each callee compiled before its callers, which
a forward declaration breaks. The clause is part of the signature, so a forward
declaration states it, every call can be checked in one pass, and changing a
routine's body can't silently change whether its callers compile. Most routines
return results rooted in globals and need no clause.

**Rejected alternative:** forbidding any returned result from a call that
received a local-rooted argument. It needs no syntax but rejects reasonable
programs in a way that would surprise their authors.

**Cost.** This gives up a property Nucleus stated (§7.9): that aggregate results
need no lifetime information in signatures. Local aggregates also move
aggregate storage into activation frames, which changes how peak memory is
accounted.

### D9. Compiler budget

The compiler is no longer held to Nucleus's 16 KiB compiler-core limit, but
size remains a first-class constraint. Every feature is costed in compiler bytes
and in generated-code bytes before it is adopted, and the measurements are
published, as Nucleus did.

### D10. Target machine

Baton programs and the Baton toolchain assume a Z80 with 64K of RAM running
CP/M 2.2 or CP/M 3, with high-capacity disk storage: 720K or larger floppies
(1.2M and 1.44M high-density formats, the Triptych system's 2M disks) or a hard
disk. A single drive is enough to build any program. Early low-capacity
formats, such as 90K to 250K floppies, are not supported for large builds.

**Why.** It removes disk space as a design constraint on the build pipeline,
which writes temporary spools comparable in size to the program. Memory, not
disk, is the scarce resource Baton is designed around.

### D11. Trap reports identify the site by address

A trap site is a call to the runtime reporter for its reason, 3 bytes when the
check's result is in a testable condition flag and 5 bytes otherwise. The
reporter prints the reason and the site's address, such as
`TRAP bounds at 1A3F`, and the line table the linker writes turns the
address into a source line.

**Why.** Nucleus put the source position inline at each site, about 8 bytes. A
checked program has hundreds of sites, and the call form saves roughly 2K per
500 of them, all in code that runs only when there is a bug. The person fixing
a trap will have the line table. A later debug option may restore inline
positions; it would change only the report's format, not program behaviour.
See the [CP/M target](cpm-target.md), §10, and the [toolchain](toolchain.md), §8.

### D12. Re-running without reloading is opt-in

Some shells, such as Z-System's `GO`, re-enter a program already in memory
without reloading it, so initialised variables start with the previous run's
values. A target-profile option, **re-runnable**, keeps a second copy of the
initial values and restores them at every start. It is off by default.

**Why.** Most CP/M users never re-enter programs this way, so most programs
shouldn't pay for a second copy of their initial data. ROM targets need the same
copy mechanism, so offering the option costs no extra design. See the
[CP/M target](cpm-target.md), §7.

### D13. Build pipeline

The compiler emits position-free blobs with ordinal references, and a separate
linker removes unreachable blobs before assigning addresses. See the
[build pipeline](build-pipeline.md).

## Open

### O1. Exclusivity and `inout`

Swift's rule is that an `inout` argument may not overlap any other access
during the call. It makes routines easier to reason about and optimise, but it
can't be checked only at the call site, because a routine can touch globals by
name. This Nucleus example (§13) is the test case any rule must answer:

```nucleus
sub entryAt(index as u8) as Entry
    return entries[index]
end

sub update(items as Entry[8], index as u8)
    items[index].value = entryAt(index).value
end
```

The natural call `update(entries, i)` writes through `items` while `entryAt`
reads `entries` by name. Under Swift's rule that conflicts, two calls deep,
where the call site can't see it. Global arrays with accessor routines like
`entryAt` are idiomatic Nucleus style.

Options:

- **No exclusivity**, as in Nucleus: overlaps are permitted and visible
  through mutation. Safe while storage is never freed.
- **Effect summaries:** each signature records which globals the routine writes.
  This is whole-program information and conflicts with D1.
- **Run-time checks** on globals passed as `inout`.

Exclusivity becomes a **memory-safety** requirement, not just a reasoning aid,
once pools can free storage (O2): freeing a slot that another parameter still
aliases is a use after free. Without pools it is optional.

### O2. Pools with owned handles

A pool is a fixed array of records with a generation byte per slot. Allocation
returns an owned handle that must be moved or freed exactly once; plain indices
derived from it are copyable and checked by generation.

Known problems to solve before adopting it:

- **Copying.** Aggregate assignment copies a whole record (Nucleus §7.8). A
  record containing an owned handle can't be copied, so such records would be
  non-copyable, splitting the type system.
- **Absence.** An optional handle introduces a "no value" state, which Nucleus
  doesn't have (§7.2).
- **Failure paths.** Every owned handle must be freed or moved on every exit,
  including `fail`. Nucleus's structured `else fail` makes this checkable at
  compile time; traps end the program, so they need no cleanup.
- **Recursive free.** Freeing an owned list recursively uses stack in proportion
  to its length, so free must be iterative.
- **Generation width.** One generation byte wraps after 256 reuses of a slot, so
  it detects most stale indices but not all. Sixteen bits per slot makes the
  check reliable at twice the cost.

### O3. Expression blocks

A block that produces a value, with an explicit `result` statement supplying
the value and `return` still meaning "leave the routine". This borrows Rust's
composition without Rust's rule that a missing semicolon changes meaning. The
cost is a new reserved word and a check that every path through the block
supplies a value of the right type.

### O4. Arenas

Scope-bound regions freed all at once, for temporary data. Free memory between
the end of static storage and the stack is available for this at run time,
starting at the address of the `FREE` pseudo-object ([object format](object-format.md), §3.4).

### O5. Routine values

Function pointers or routine values. The build pipeline already handles them
for tree shaking (a routine whose address is taken by live code stays live),
but the type system, calling convention and interaction with `from` are not
designed.
