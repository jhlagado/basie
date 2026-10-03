# Baton memory safety

- Status: draft design, not yet reviewed
- Date: 2026-10-03
- Related: [philosophy](philosophy.md), [design decisions](design-decisions.md)
  (D8, O1, O2, O4), [CP/M target](cpm-target.md) (stack checking),
  [linker](linker.md)

## 1. The claim

Baton's central claim is that it is **memory safe without a garbage collector
or reference counting**. A Baton program, compiled from source, cannot:

1. read or write outside the bounds of an object;
2. read or write storage after its lifetime has ended, or after it has been
   reused for another object of a different type;
3. free storage twice, or free storage it does not own;
4. read storage that was never initialised;
5. treat storage of one type as another;
6. overflow its stack into other memory; or
7. leak owned dynamic storage.

Every one of these is prevented at compile time, or checked at run time with a
**trap**, never left undefined. The run-time checks are bounds checks,
handle-generation checks and stack checks. There is no collector, no reference
count and no hidden allocation.

The **trusted base** is outside the claim: the hand-written runtime library,
the BIOS and BDOS, and anything that changes memory behind the program's back,
such as an interrupt handler that is not Baton code. Baton 1.0 has no
interrupt routines and no way to write raw machine code in source.

## 2. Storage classes

Baton has exactly four places an object can live. Each has one lifetime rule.

| Class | Declared | Lifetime | Freed by |
| --- | --- | --- | --- |
| **Program storage** | top-level `var` and `const` | the whole run | never |
| **Activation storage** | locals in a routine, including local aggregates | one call | the return, automatically |
| **Pool storage** | slots of a top-level `pool` | from `new` to retirement | retiring the owning handle |
| **Arena storage** | later; see Section 9 | one scope | the end of the scope |

There is no general heap. Every byte of storage a program can use is declared
in the source, at a size fixed when the program is linked, as in Nucleus. The
linker's map shows it.

## 3. References

Baton has three ways to refer to an object other than by naming it. None of
them is a pointer the program can store freely or do arithmetic on.

### 3.1 Aliases

An **alias** is how a routine receives an aggregate: a record, array or string
passed by reference. Aliases come from Nucleus and are **second class**:

- an alias exists only as a parameter, for the length of a call, or as a
  routine result the caller uses at once;
- an alias can't be stored in a variable, a field, an array or a pool slot; and
- source code can't see or compute the address behind an alias.

An alias parameter has a mode:

| Mode | Written | Access | Term |
| --- | --- | --- | --- |
| read | `items as Entry[8]` | read only | ticket |
| modify | `items as inout Entry[8]` | read and write | lease |

Nucleus made every aggregate parameter writable. Baton makes read the default
and requires `inout` for writing, so a routine's signature says what it can
change. This costs nothing at run time; the compiler checks it.

### 3.2 Owned handles

An **owned handle**, type `own T`, identifies one slot of a pool of `T`
records and **owns** it: the slot stays allocated exactly as long as the handle
exists. An owned handle is **affine**: it is never copied. It can be moved, and
it is retired automatically when it goes out of scope without having been
moved. An optional owned handle, `own? T`, may also be `none`.

### 3.3 Identifiers

An **identifier**, type `id T`, is a copyable reference to a pool slot that
does not own it. It is how a program expresses sharing, back-links and graphs.
Each pool slot carries a **generation** counter that changes whenever the slot
is retired. An identifier records the generation it was made with, and every
use of it checks the generation; a stale identifier traps with `stale-handle`
instead of reaching a slot that has since been reused.

## 4. How each hazard is prevented

| Hazard | Prevention | When |
| --- | --- | --- |
| Out-of-bounds access | Every array, string and pool index is checked; `bounds` trap | run time, unless the compiler proves the index in range |
| Alias to a dead local | Aliases are second class, and a returned alias may point only into storage named in the routine's `from` clause (D8) | compile time |
| Alias into a freed pool slot | A routine that can free from a pool says so with a `frees` effect; no call made while an alias into that pool is live may have that effect (Section 6) | compile time |
| Stale owned handle | Impossible: an owned handle is never copied, so it is the slot's only owner | compile time |
| Stale identifier | Generation check on every use; `stale-handle` trap | run time |
| Double free | Retiring consumes the owned handle; a second retire is a use after move | compile time |
| Use after move | Flow analysis over structured control flow (Section 5.3) | compile time |
| Leak | An owned handle not moved is retired at the end of its scope, on every exit path including `fail`; owned fields are retired with their container (Section 5.4) | compile time placement, run time effect |
| Uninitialised read | Every variable, local and new pool slot has an initial value | compile time |
| Type confusion | Static types; no casts between handles, identifiers, integers or addresses; each pool holds one record type | compile time |
| Null dereference | No null. `own? T` must be tested before use | compile time |
| Stack overflow | Every cycle of calls is guarded by a stack check; the linker bounds the rest (Section 7) | run time check, link time bound |
| Integer overflow | Wraps by definition (D5); not a memory hazard, since every index is checked | — |

## 5. Pools and owned handles

### 5.1 Pools

A pool is a top-level declaration of a fixed number of slots of one record
type:

```nucleus
record Node
    value as u16
    next  as own? Node       // owns the rest of the list
end

pool nodes as Node[64]
```

The linker places a pool as a `bss` blob: the slots, one generation counter per
slot, and a free list. Its size is fixed and visible in the map. A pool never
grows or moves, so a slot's address is stable for the whole run, and a slot
only ever holds a `Node`. This **type stability** is a second line of defence:
even a logic error that reached a recycled slot would find a valid `Node`, not
other data.

### 5.2 Allocation

`new nodes(value, next)` takes a free slot, initialises every field from the
arguments, and returns `own Node`. Allocation can fail when the pool is full,
so `new` is failable, like a call to a routine marked `fails`. The slot is
reserved **before** the arguments are evaluated, so a failed allocation never
consumes an owned value passed as an argument:

```nucleus
sub push(list as inout own? Node, v as u16) fails
    var n as own Node = new nodes(v, take list) else fail
    list = n                     // moves n into list
end
```

`take list` moves the value out of `list` and leaves `none`; if the pool is
full, `new` fails before `take list` runs, and `list` is untouched. The
assignment `list = n` retires nothing, because the flow check knows `list` is
`none` after the `take`. Allocation never moves or invalidates any existing
slot, so it has no effect on live aliases.

### 5.3 Moves and the flow check

An owned value is **moved** when it is assigned to a variable or field, passed
as an argument of type `own T`, returned, or taken with `take`. After a move,
the source can't be used until it is assigned again.

The compiler checks this with a forward flow analysis over the routine's
structured control flow. It keeps one bit per owned local, meaning "holds a
value", and at each join point (the end of an `if`, the top and exit of a loop)
requires every incoming path to agree, or to be resolved by an implicit retire
on the path that still holds a value. Nucleus control flow is structured, with
no `goto`, so this analysis runs in the same single pass as code generation.

### 5.4 Retirement

**Retiring** an owned handle frees its slot: it retires every owned field of
the record first, then returns the slot to the pool's free list and advances
its generation. Retirement happens:

- **explicitly,** with `retire h`;
- **at scope exit,** for every owned local still holding a value, on every exit
  path, including `return`, `exit`, `continue` and `fail`; and
- **on overwrite,** when a value is assigned to an `own?` variable or field that
  may still hold one.

The compiler places every retire, as the philosophy promises. Retiring a long
list must not recurse once per element, which could overflow the stack: the
runtime retires owned chains iteratively, following the owned fields of each
record in turn with an explicit work list kept in the slots being freed.

A trap ends the program, so no retirement runs after one.

### 5.5 Records that own

A record type with an `own` or `own?` field, directly or in a nested record,
is an **owning type**. Owning types can't be copied: whole-record assignment and
by-value passing are compile-time errors, because a copy would create a second
owner. They can be passed by alias, moved field by field, and retired.

### 5.6 Owning variables and fields outside pools

An owned handle may live in a local, a top-level variable, or a field of a
record in program storage or in another pool slot. A top-level owning variable
keeps its slot for the whole run unless the program moves or retires it.

## 6. The `frees` effect

### 6.1 The problem

An alias is a raw address. If a routine receives an alias into a pool slot and,
during the call, that slot is retired and reused, the alias would reach a
different `Node`. Type stability keeps that from corrupting memory of another
type, but it is still a use after free.

A call site can't see every way a callee might retire a slot: the callee may
reach the owning handle through a global. Swift solves the general version of
this problem with run-time exclusivity checks on globals. Baton solves it
statically with an effect in the signature.

### 6.2 The rule

- A routine that can retire slots of pool `P` is declared with **`frees P`**:

  ```nucleus
  sub clear(list as inout own? Node) frees nodes
      list = none                  // retires the old list
  end
  ```

- The effect propagates like `fails`: a routine that calls a `frees P` routine,
  or retires a `P` handle itself, must declare `frees P`. The compiler checks
  each routine's body against its signature in the same pass.
- **The aliasing rule:** while an alias into a slot of `P` is live as an
  argument, the call it is passed to must not have the effect `frees P`.

An alias into a pool slot is live only during the call it is passed to, since
aliases are second class. The callee, lacking `frees P`, can't retire any `P`
slot, and nor can anything it calls. So no slot an alias points into can be
retired while the alias exists.

Forward declarations carry the effect like the rest of the signature, so the
rule is checkable in one pass.

### 6.3 What this replaces

This makes exclusivity (design decision O1) unnecessary for memory safety.
Overlapping aliases to program storage remain allowed, as in Nucleus: they are
visible through mutation but can never dangle, because program storage is never
freed. Only pool storage can be freed, and the `frees` effect covers it.

## 7. The stack

On a Z80 there is no guard page: a stack that grows into `BSS` silently
corrupts the program's data. Baton treats stack overflow as a memory-safety
hazard.

### 7.1 Cycles

In a single-pass language with declaration before use, a cycle of calls must
include either a routine calling itself or a call to a routine declared
`forward` and not yet defined at the call. The compiler puts an
**activation-capacity check** at every such call: it traps if the stack pointer,
less the callee's frame and a guard band, would fall below `FREE`. Every cycle
therefore passes a check on every turn.

### 7.2 The acyclic part

Without its cycles, a program's call graph is acyclic, and its deepest stack use
is a finite sum of frames along the worst path. The linker already holds the
complete reference graph. If each `code` blob also records its own maximum
stack use (its frame plus the deepest stack any helper call it makes needs),
the linker can compute the worst path through the live graph, cutting the
edges that the compiler guarded, and set `REQUIRED` from it. Startup's memory
check then guarantees the acyclic part can never overflow.

This needs a per-blob stack figure in the object format, which revision 3 of
the format does not yet carry. It is the one object-format change memory safety
requires (Section 10).

### 7.3 Interrupts

An interrupt-mode-1 BIOS pushes onto the program's stack. The guard band in
every stack check and in `REQUIRED` covers it; its size is a profile value.

## 8. What Baton gives up

- **A general heap.** All dynamic storage is in pools declared in the source.
  A program states its maximum number of nodes, as small-machine programs
  already do.
- **Shared ownership.** An object has one owner. Sharing is expressed with
  identifiers, which are checked on use. Cyclic structures use owned links in
  one direction and identifiers in the other.
- **Copying owning records.** A record that owns a slot can't be copied, only
  moved.
- **Retiring while an alias into the pool is live.** A routine that frees from a
  pool can't be called with an alias into that pool as an argument. The program
  passes an identifier or an owned handle instead.

## 9. Later: arenas

An arena is storage allocated in a scope and freed all at once when the scope
ends, such as a scratch buffer for one command. With second-class aliases, an
arena is activation storage whose size is decided at run time, and the `from`
rule already prevents its contents from escaping. Arenas are not part of the
first version of the design; the rules above leave room for them.

## 10. Changes this design makes elsewhere

- **Language:** parameter modes (`inout`); the `own`, `own?` and `id` types;
  `pool`, `new`, `take` and `retire`; the `frees` effect; the `stale-handle`
  trap. The [design decisions](design-decisions.md) record should take these up
  as decisions once this design is reviewed.
- **Object format:** a per-blob stack figure for the linker's stack bound
  (Section 7.2).
- **Linker:** the stack-bound computation in Phase B or C.
- **Runtime library:** pool allocation, iterative retirement, generation checks
  and the stack-check helper.

## 11. Open questions

1. **Generation width.** 8 bits per slot catches most stale identifiers and
   costs 1 byte per slot; 16 bits makes a missed detection practically
   impossible at 2 bytes. Because pools are type-stable, a missed detection is a
   logic error, not memory corruption; the claim in Section 1 holds either way
   for writes to other types, but a stale identifier passing its check reaches
   another live `Node`. Which width?
2. **Identifier representation:** slot index and generation in 2 bytes for pools
   of at most 256 slots, or 3 or 4 bytes in general?
3. **Syntax** for testing `own?` and `id` values, `take`, and `retire`.
4. **Stack figure in the format:** a field in the blob record, or a control
   record for `code` blobs only?
5. **Whether `frees` should name the pool,** as above, or be a single effect for
   all pools, which is simpler but rejects more programs.
