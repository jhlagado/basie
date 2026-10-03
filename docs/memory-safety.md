# Baton memory safety

- Status: draft design, revision 2 (after adversarial review)
- Date: 2026-10-03
- Related: [philosophy](philosophy.md), [design decisions](design-decisions.md)
  (D8, O1, O2, O4), [CP/M target](cpm-target.md) (stack checking, traps),
  [feature inventory](feature-inventory.md) (`select`),
  [review](reviews/2026-10-03-memory-safety-review.md)

Syntax in this document is provisional. `select` is the testing form proposed
in the feature inventory.

## 1. The claim

Baton's central claim is that it is **memory safe without a garbage collector
or reference counting**. A Baton program, compiled from source, cannot:

1. read or write outside the bounds of an object;
2. read or write storage after its lifetime has ended, whatever occupies it
   now;
3. free storage twice, or free storage it does not own;
4. read storage it never initialised;
5. treat storage of one type as another;
6. overflow its stack into other memory; or
7. leak owned dynamic storage.

Each is either rejected at compile time or checked at run time with a **trap**;
none is ever undefined. The run-time checks are bounds checks, identifier
generation checks and stack checks. There is no collector, no reference count
and no hidden allocation. The only hidden data is per-pool bookkeeping and
per-type retirement descriptors, which the map reports.

Claim 2 is the standard definition of temporal safety. It holds for identifiers
as well as for aliases and owned handles, because generations never repeat
(Section 5.6).

### 1.1 Outside the claim

- **The trusted base:** the hand-written runtime library, the BIOS and the BDOS.
  The runtime must respect the extents and modes of every alias it is given,
  must not keep any address after it returns, and must restore the DMA address
  to its own buffer before returning, so that no later disk read can write into
  a dead frame.
- **Interrupts and concurrency:** Baton 1.0 has no interrupt routines in source
  and no concurrency.
- **Hardware protection:** `TEXT` is writable RAM on CP/M. Code and constants
  are protected only by the language's rules.
- **Re-entry without reloading** under CP/M is covered by the re-runnable option
  ([CP/M target](cpm-target.md), Section 7). Owned variables are always in
  `bss`, since no initialiser can allocate, so startup's clearing of `bss` and
  of the pools keeps them consistent on re-entry.

## 2. Storage classes

| Class | Declared | Lifetime | Freed by |
| --- | --- | --- | --- |
| **Program storage** | top-level `var` and `const` | the whole run | never |
| **Activation storage** | locals, including local aggregates | one call | the return |
| **Pool storage** | slots of a top-level `pool` | from `new` to retirement | retiring the owning handle |
| **Arena storage** | later (Section 10) | one scope | the end of the scope |

There is no general heap. Every byte a program can use is declared in the
source, at a size fixed at link time.

## 3. References

### 3.1 Aliases

An alias is how a routine receives an aggregate by reference. As in Nucleus,
aliases are **second class**: an alias exists only as a parameter for the length
of a call, or as a routine result the caller uses at once, and is never stored.

**Modes.** An alias parameter is read-only (a **ticket**) unless declared
`inout` (a **lease**). A result alias is read-only unless declared `inout`,
which is allowed only when the result is rooted in an `inout` parameter or a
program variable. An alias rooted in a constant never binds to `inout`.

**Provenance.** The compiler gives every alias it handles a **provenance**,
known at compile time:

| Provenance | Meaning |
| --- | --- |
| program | rooted in program storage |
| local | rooted in this routine's activation storage |
| parameter *k* | rooted in alias parameter *k* |
| pools *S* | may point into a slot of any pool in the set *S* |

Field selection and indexing keep the provenance of what they select from.

- **Dereferencing an identifier** yields provenance *pools {P}*, where *P* is the
  identifier's pool.
- **Dereferencing an owned handle** yields the provenance of the handle's
  location: a local handle gives local provenance, an `inout` handle parameter
  gives that parameter's. The slot's lifetime is the handle's.
- **An alias parameter** has, inside its routine, provenance *parameter k*. For
  the `frees` rule, it is also treated as possibly pointing into **every pool
  whose record type contains its type**, directly or through fields and arrays,
  because the routine cannot know where its caller's alias came from.
- **A result** has the union of the provenances of the arguments passed for its
  `from` parameters. A result without `from` has *program* provenance plus every
  pool whose record type contains the result type.

**Returning aliases (D8, restated).** A returned alias must have *program*
provenance, *pools* provenance, or the provenance of a parameter listed in
`from`. Local provenance is never returnable, so `return deref(h)` for a local
owned handle `h` is rejected. `from` may name only alias parameters, including
`inout own? P` handle locations, never a by-value `own P` parameter, which the
routine retires unless it moves it.

### 3.2 Owned handles

An **owned handle** identifies one slot of a pool and owns it. Handle types name
the pool, not just the record type, so two pools of the same record type can't
be confused:

| Type | Meaning |
| --- | --- |
| `own nodes` | owns a slot of `nodes`; never `none` |
| `own? nodes` | owns a slot of `nodes`, or is `none` |

An owned handle is never copied. It is moved, or retired. Its representation is
the slot's address; `none` is 0, so zeroed storage holds `none`. Dereferencing an
owned handle needs no check, because an owned handle is never stale.

`own` without `?` is allowed only for locals and parameters, where the flow
check sees every use. Record fields, array elements and program variables that
hold handles are always `own?`.

### 3.3 Identifiers

An **identifier** is a copyable reference that does not own its slot:

| Type | Meaning |
| --- | --- |
| `id nodes` | refers to a slot of `nodes` |
| `id? nodes` | refers to a slot of `nodes`, or is `none` |

An identifier holds a slot index and the slot's **generation** when the
identifier was made. Every dereference compares the two and traps with
`stale-handle` if they differ. The zero identifier holds generation 0, which no
allocated slot ever has (Section 5.2), so an identifier that was never assigned
can never pass its check.

A non-trapping test is available through `select`:

```nucleus
select live(i)
case live(n)          // n is an alias into the slot, provenance pools {nodes}
    total = total + n.value
case stale
    count = count + 1
end
```

## 4. How each hazard is prevented

| Hazard | Prevention | When |
| --- | --- | --- |
| Out-of-bounds access | Every array, string and pool index is checked; string growth is checked against capacity; `bounds` trap | run time, unless proved in range |
| Alias to dead activation storage | Provenance: local provenance is never returnable (Section 3.1) | compile time |
| Alias to a retired slot | The statement rule of the `frees` effect (Section 6) | compile time |
| Stale owned handle | An owned handle is never copied | compile time |
| Stale identifier | Generation check on every dereference; generations never repeat | run time |
| Double free | Retiring consumes a handle; moving leaves `none`; `take` only on `own?` | compile and run time |
| Use after move | Flow check on owned locals (Section 5.4) | compile time |
| Leak | Owned locals retired at scope exit; owned fields retired with their container and on overwrite | placed at compile time |
| Uninitialised read | Every variable, local and new slot has an initial value (Section 5.8) | compile time |
| Type confusion | Static types; handles name their pool; no casts between handles, identifiers, integers or addresses | compile time |
| Null dereference | No null; `own?` and `id?` must be tested with `select` before use | compile time |
| Stack overflow | A compiler-computed stack bound checked at startup, and a check in every routine that can begin a cycle (Section 7) | run time |

## 5. Pools, handles and identifiers

### 5.1 Pools

```nucleus
record Node
    value as u16
    next  as own? nodes
end

pool nodes as Node[64]
```

A pool is placed as a `bss` blob. Each slot holds the record, a 2-byte
generation and a 2-byte link used by the free list and by retirement, both kept
outside the record so neither can overwrite a field. A pool also has a
high-water mark and a free-list head and tail. Pool storage never moves, and a
slot only ever holds its pool's record type.

### 5.2 Allocation

`new nodes(value, next)` allocates a slot and initialises every field from its
arguments. It takes the oldest slot on the free list if there is one, otherwise
the next never-used slot above the high-water mark; otherwise it fails, so
`new` is used like a failable call. A never-used slot's generation is 0; `new`
sets a fresh slot's generation to 1. Because the pool is in `bss` and every
counter starts at zero, pools need no initialisation code.

The slot is reserved before the arguments are evaluated, so a failed `new`
never consumes an owned value passed as an argument.

### 5.3 Moves

An owned value is **moved** when it is assigned to a variable or field, passed
as an argument of type `own P`, returned, or taken with `take`. A move stores
`none` into the source at run time (a 2-byte store), so the source never keeps a
stale copy. `take` applies only to `own?` locations.

Moves are not allowed inside an operand of `and` or `or`, where they would
happen on only some executions of the expression.

### 5.4 The flow check

The compiler tracks, for each owned local, whether it may hold a value. It
reports a **use after move** when a local that is certainly `none` is
dereferenced or moved, and a **move from a non-optional local** that may already
have been moved.

At joins it takes the meet of the incoming states and emits no code: because
moves store `none` at run time, a path that moved a value and a path that didn't
already agree in memory. Loops are checked with the state at the loop top
assumed to be the meet of the entry and every back edge; a non-optional `own`
local moved inside a loop body and not reassigned before the back edge is an
error.

Flow states exist only for owned locals, whose storage no other routine can
reach. Every other `own?` location is treated as possibly holding a value.

### 5.5 Retirement

**Retiring** a slot retires each of its owned fields first, then puts the slot
on its pool's free list and advances its generation. Retirement happens:

- **explicitly,** with `retire h`;
- **at scope exit,** for every owned local, on every exit path, including
  `return`, `exit`, `continue` and `fail`. Retiring `none` does nothing, so the
  compiler emits the same short epilogue whatever the flow state; and
- **on overwrite,** when a value is stored into an `own?` location.

**Order of overwrite.** An assignment to an `own?` location evaluates the
destination, then the right side, then retires the destination's old value
(which may by then be `none`), then stores. So `root = take deref(root).next`
takes the second node before the old head is retired.

**No recursion.** Retiring a structure must not use stack in proportion to its
size. The runtime keeps a work list threaded through the slots' link fields:
it reads every owned field of a slot, pushes each non-`none` child onto the work
list, then frees the slot, and repeats until the list is empty. The link is
outside the record, so pushing a child never overwrites a field not yet read.
Work-list links are addresses, so a list can span pools.

**Descriptors.** To find a slot's owned fields, the runtime uses a descriptor
per owning record type in `rodata`: the offset of each owned field, and the
offset, stride and count of each array of them, about 2 bytes per field and 3
per array. The linker keeps only the descriptors of types that live code
retires.

A trap ends the program, so no retirement runs after one.

### 5.6 Generations

A slot's generation starts at 1 when it is first allocated and advances by one
each time the slot is retired. Generations are 16 bits and **saturating**: when
advancing would wrap past `$FFFF`, the slot is withdrawn from use for the rest
of the run instead of being put on the free list. No slot ever returns to a
generation it has had, so a stale identifier can never pass its check.

The free list is first in, first out, so retirements spread across all slots. A
64-slot pool withdraws its first slot only after about four million
retirements.

### 5.7 Owning types

A record or variant with an `own?` field, directly or through a nested record or
array, is an **owning type**. Owning types are never copied: whole-record
assignment and by-value passing are errors. They can be passed by alias, moved
field by field, and retired.

### 5.8 Initial values

Every program variable and pool slot starts zeroed, or initialised. Every local
starts with an explicit or default value. For local aggregates, which are new
in Baton:

- a bounded string has only its length byte zeroed, since no byte beyond its
  length can be read;
- a record or array is zeroed in full, unless it has an initialiser.

Zeroing happens after the routine's stack check. A 2K local array costs about
11 ms to zero at 4 MHz on every call, so large arrays should be given an
initialiser or placed in program storage; a write-before-read rule may be added
later.

## 6. The `frees` effect

### 6.1 Declaring it

A routine that can retire slots of a pool declares it:

```nucleus
sub clear(list as inout own? nodes) frees nodes
    list = none                    // retires the old list
end
```

**Closure.** Retiring a slot retires everything it owns, so retiring a slot of
`P` can retire slots of every pool reachable from `P`'s record type through
owned fields, transitively. The compiler computes that closure once per record
type, and a routine that retires `P` handles must declare `frees` for every pool
in it.

**Propagation.** A routine that calls a routine with effect `frees S`, or itself
retires a handle (explicitly, at scope exit or on overwrite), must declare at
least those pools.

**Checked, never inferred.** The effect is part of the signature. The compiler
checks each body against it. For a forward declaration, the body is checked
against the effect stated in the forward declaration when the body is compiled,
so calls compiled earlier remain valid.

### 6.2 The statement rule

The rule that prevents an alias into a retired slot is stated at the level of
expression evaluation, not call arguments:

> **While an alias with provenance *pools S* is staged during the evaluation of
> a statement, no call whose effect includes a pool in *S* may be evaluated.**

An alias is **staged** from the moment it is formed (by a dereference, a field
selection, an index, or a call returning an alias) until the operation that
consumes it completes: an argument until its call returns, an assignment
destination until the store, an index base until the indexed access. The
compiler already tracks staged aliases, because Nucleus requires them to survive
later argument evaluation, so it attaches a pool set to each and checks every
call it emits against the union of the staged sets.

The rule rejects, for example:

```nucleus
show(deref(i), resetAll())     // the first argument is staged across resetAll
deref(i).value = count()       // the destination is staged across count
```

when `resetAll` or `count` frees `nodes`. The program writes the freeing call as
its own statement first.

**Inside a callee.** An alias parameter is staged for the whole call. Its
routine sees it with the conservative pool set of Section 3.1, so the routine
can't call anything that frees a pool the alias might point into. That is what
makes the rule hold across calls: a routine that receives a `Node` alias and
needs to call something that frees `nodes` must receive an identifier or a
handle instead.

### 6.3 What this replaces

Exclusivity (design decision O1) is not needed for memory safety. Overlapping
aliases to program storage are still allowed, as in Nucleus: they are visible
through mutation but can never dangle, because program storage is never freed.
Only pool storage can be freed, and the `frees` effect covers it.

### 6.4 Leases on handles

A routine that works on one pool record for a while can take the handle's
location as a lease:

```nucleus
sub bump(h as inout own nodes)
    h.value = h.value + 1          // no generation check: h is owned
end
```

Inside, every access is a direct address use with no check. The routine can't
retire `h` without the `frees nodes` effect. A caller holding the record only by
identifier pays one check to reach the owner, not one per access.

## 7. The stack

On a Z80 there is no guard page: a stack that grows into `BSS` silently
corrupts the program. Baton treats stack overflow as a memory-safety hazard.

### 7.1 The bound the compiler computes

Because names are declared before use, when the compiler finishes a routine
`R` it has already compiled every routine `R` calls, except `R` itself and
forward routines not yet defined. So it can compute, in its single pass:

```text
need(R) = frame(R) + helperStack(R)
          + the largest need(c) over the routines c that R calls,
            counting 0 for R itself and for forward routines not yet defined
```

`helperStack(R)` is the deepest stack any runtime helper `R` calls can use,
taken from figures published in the runtime's helper table.

### 7.2 Cycles

Every cycle of calls passes through a routine that calls itself or calls a
forward routine not yet defined at the call. Every **self-recursive** routine
and every **forward-declared** routine begins with an activation-capacity
check: it traps if `SP − need(R) − guard` would fall below `FREE`. The check
covers the whole subtree below `R`, so every turn of every cycle is checked,
and nothing below a checked routine needs its own check.

### 7.3 The acyclic part

`main` is compiled after every routine it calls directly, so `need(main)` bounds
the stack of everything reachable from `main` outside the cycles. The compiler
writes `need(main)` plus the guard into the `LIMITS` record as the stack reserve
([object format](object-format.md), Section 6). Startup's memory check then
guarantees the acyclic part never overflows. No change to the object format and
no graph computation in the linker is needed. Tree shaking only makes the bound
pessimistic.

### 7.4 The guard band

The guard band covers the trap reporter's call into the BDOS, which switches to
its own stack after a few pushes, and an interrupt-mode-1 BIOS that pushes onto
the program's stack. It is a profile value. Runtime helpers' own stack use is
counted in `helperStack`, not in the guard.

## 8. Data structures

These show the style the rules lead to.

**Singly linked list with deletion during traversal.** The list is reached by
identifier; the victim is retired by overwriting the field that owns it:

```nucleus
sub removeAll(v as u16) frees nodes
    while root is some and deref(root).value = v
        root = take deref(root).next
    end
    if root is none
        return
    end
    var p as id nodes = id(root)
    while deref(p).next is some
        if deref(deref(p).next).value = v
            deref(p).next = take deref(deref(p).next).next
        else
            p = id(deref(p).next)
        end
    end
end
```

(`is some` and `is none` here abbreviate a two-case `select`.)

**Doubly linked list and trees with parent links.** Owned links in one
direction, `id?` links in the other. Unlinking a node overwrites the owned link
that holds it, which retires it, and every identifier to it then traps on use.

**Graphs.** Every vertex is owned by one slot of an `own?` array; edges are
identifiers. Deleting a vertex makes every edge to it stale; a sweep uses the
non-trapping `select live(e)` to find and drop them.

**User-level free lists over program storage**, the Nucleus idiom of an array
and integer links, still compile and are memory safe by bounds checking alone,
but detect no stale index. Pools are what improve on them.

## 9. What Baton gives up

- **A general heap.** All dynamic storage is in declared pools.
- **Shared ownership.** One owner per slot; sharing is by identifier, checked on
  use.
- **Copying owning records.**
- **Freeing while an alias into the pool is staged.** A routine that receives a
  record alias can't call anything that frees that record's pool. Such code
  passes identifiers or handles instead, and pays a generation check per
  identifier dereference.
- **Slots after four million reuses.** A slot whose generation saturates is
  withdrawn.

## 10. Later: arenas and routine values

**Arenas** are storage allocated in a scope and freed when the scope ends. An
arena's size is decided at run time, so the static bound of Section 7 can't
cover it; each arena allocation needs its own capacity check, like a recursive
call.

**Routine values**, when added, must carry their `from` clause and their effect
in their type, and a call through one is checked against them. A routine value
of unknown target is treated as a forward call for the stack rule.

## 11. Costs

**[estimate]** Z80 at 4 MHz:

| Mechanism | Bytes | T-states |
| --- | --- | --- |
| Identifier dereference | 6 at the site, about 28 per pool in a helper | about 165 |
| Owned-handle dereference | 3 | 16 |
| `own?` or `id?` test | 5 | about 20 |
| Move (store `none`) | 3 to 4 | about 16 |
| Overwrite of an `own?` location | about 9 | about 40, plus the retirement |
| Retirement of one slot | about 6 at the site; a shared helper of about 120 and the descriptors | 200 to 250 per slot |
| Scope-exit retirement | about 3 per exit path, through a shared epilogue | about 55 per owned local, plus retirement |
| Activation-capacity check | 5 at the site, a 15-byte helper | 60 to 95, only in forward and self-recursive routines |
| Local aggregate zeroing | 13 | 40 plus 21 per byte |
| Pool overhead | 4 bytes per slot, plus about 6 per pool | — |

Compiler memory: about 7 bytes per routine (effect set, `from` mask, result
provenance, `need`) and 2 per parameter, plus a few tens of bytes of transient
flow state per routine. No control-flow graph is built.

## 12. Changes this design makes elsewhere

- **Language:** parameter and result modes; `own P`, `own? P`, `id P`, `id? P`;
  `pool`, `new`, `take`, `retire`, `live`; the `frees` effect; the
  `stale-handle` trap. These become design decisions once this revision is
  reviewed.
- **CP/M target:** the stack check uses `need(R)`, only in forward-declared and
  self-recursive routines; the `stale-handle` reporter is added
  ([CP/M target](cpm-target.md), Sections 4.1 and 10).
- **Object format:** none. The stack reserve in `LIMITS` becomes
  `need(main)` plus the guard.
- **Runtime library:** pool allocation, retirement with descriptors, generation
  checks, the stack-check helper, and published stack figures for every helper.

## 13. Open questions

1. **Generation width.** This revision chooses 16-bit saturating generations
   (2 bytes per slot). Eight bits would save a byte per slot but withdraw a slot
   after 255 reuses, which a busy program reaches quickly.
2. **The conservative pool set for alias parameters** (Section 3.1) may reject
   reasonable programs that pass strings or small arrays, since many pools may
   contain those types. If measurement on real programs shows it does, a
   signature annotation naming the pools an alias may come from would make it
   precise.
3. **Write-before-read for large local arrays,** instead of zeroing.
4. **Syntax** throughout, including `is some` as shorthand for a two-case
   `select`.
