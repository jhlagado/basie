# Baton memory safety

- Status: draft design, revision 3
- Date: 2026-10-04
- Decisions it rests on: [design decisions](design-decisions.md) D8, D15–D22
- Reviews: [1](reviews/2026-10-03-memory-safety-review.md),
  [2](reviews/2026-10-03-memory-safety-review-2.md)
- Related: [CP/M target](cpm-target.md) (stack checks, traps),
  [feature inventory](feature-inventory.md) (`match`)

## 1. In plain terms

Baton is **memory safe without a garbage collector**. A program can't read or
write memory it shouldn't, can't use storage after it has been freed, and can't
leak dynamic storage. Most mistakes are compile-time errors; the rest stop the
program with a report naming the source line.

### 1.1 Glossary

| Term | Meaning |
| --- | --- |
| **Program storage** | Top-level `var` and `const`: lives for the whole run |
| **Activation storage** | A routine's locals, including local records and arrays: lives for one call |
| **Pool** | A top-level declaration of a fixed number of slots of one record type, allocated and freed one at a time |
| **Alias** | The implicit reference a routine gets when it is passed a record, array or string. Never seen, never stored |
| **Ticket** | A read-only alias: an ordinary aggregate parameter |
| **`var` parameter** | An alias the routine may change through |
| **Handle** | An explicit reference to a pool slot. The only kind of reference that is a value |
| **Owning handle** | A handle of type `nodes` or `nodes?`. Exactly one owner per slot; the slot is freed when its owner goes away |
| **Identifier** | A handle of type `id nodes` or `id nodes?`. Refers to a slot without owning it; checked on every use |
| **`?`** | "May be empty". An optional value must be tested with `match` before use |
| **`none`** | The empty value of an optional handle |
| **`move`** | Hands an owning handle from a named variable, parameter or field to a new owner, leaving `none` behind |
| **Freeing** | Returning a slot to its pool. Always automatic |
| **Lease** | A `var` parameter of handle type: lends the caller's owning local for one call |
| **Generation** | A counter in each slot that changes whenever the slot is freed, so stale identifiers can be detected |

### 1.2 The two kinds of reference

**Aliases** are for program and activation storage: globals and locals. They are
how records, arrays and strings are passed to routines. They are implicit, can't
be stored, and live only for the call they were passed to.

**Handles** are for pool storage, and only for pool storage. They are explicit
values: you can store them in variables and fields. An owning handle is never
copied, only moved; an identifier can be copied freely and is checked whenever
it is used.

The two meet in exactly one place, the lease: a `var` parameter of handle type,
which is an alias to the caller's handle variable.

There is never an alias pointing into a pool slot (decision D16). That one rule
is what keeps the design simple.

## 2. The claim

A Baton program compiled from source cannot:

1. read or write outside the bounds of an object;
2. read or write storage after its lifetime has ended, whatever occupies it
   now;
3. free storage twice, or free storage it does not own;
4. read storage it never initialised;
5. treat storage of one type as another;
6. overflow its stack into other memory; or
7. leak pool storage.

Each is either rejected at compile time or checked at run time with a trap.
The run-time checks are bounds checks, identifier generation checks, ownership
cycle checks and stack checks.

### 2.1 Outside the claim

- **The trusted base:** the runtime library, the BIOS and the BDOS. The runtime
  must respect the extent and mode of every alias it is given, must keep no
  address after it returns, and must restore the DMA address to its own buffer
  before returning.
- **Interrupts and concurrency:** Baton 1.0 has neither in source.
- **Hardware protection:** none on CP/M; code and constants are protected only by
  the language's rules.

## 3. Storage classes

| Class | Declared | Lifetime | Freed |
| --- | --- | --- | --- |
| Program storage | top-level `var`, `const` | the whole run | never |
| Activation storage | locals | one call | on return |
| Pool storage | slots of a top-level `pool` | from `new` until freed | when its owner goes away |
| Arena storage | later (Section 11) | one scope | at the end of the scope |

There is no general heap. Every byte a program can use is declared in the
source, at a size fixed when the program is linked.

## 4. Aliases

As in Nucleus, an alias exists only as a parameter, for the length of a call, or
as a result the caller uses at once. It can't be stored in a variable, field or
array, and source code can't see its address.

- A parameter is a **ticket** (read-only) unless declared `var` (D17).
- A result is read-only unless declared `var`, which is allowed only when it is
  rooted in a `var` parameter or a program variable. An alias rooted in a
  constant never binds to `var`.
- A returned alias must be rooted in program storage or in a parameter listed in
  the routine's `from` clause, never in the routine's own locals (D8).
- An alias never points into a pool slot. A pool record's aggregate fields are
  copied out to be passed on (Section 5.4).

These rules make aliases safe without any further checking: program storage is
never freed, activation storage outlives every call made from it, and pool
storage is never aliased.

## 5. Pools and handles

### 5.1 Pools

```nucleus
record Node
    value  as u16
    name   as string[16]
    next   as nodes?          // owns the next node
    parent as id nodes?       // refers to the previous one
end

pool nodes as Node[64]
```

A pool is placed as a `bss` blob. Each slot holds the record, a 2-byte
generation and a 2-byte link kept outside the record. The pool also has a
high-water mark and a free-list head and tail. Pool storage never moves, and a
slot only ever holds its pool's record type. Programs may declare any number of
pools.

### 5.2 Handle types

| Type | Meaning | Allowed in |
| --- | --- | --- |
| `nodes` | owns a slot; never empty | locals and parameters |
| `nodes?` | owns a slot, or `none` | anywhere a type is written |
| `id nodes` | refers to a slot | locals and parameters |
| `id nodes?` | refers to a slot, or `none` | anywhere a type is written |

Fields, array elements and program variables start out zeroed, which is
`none`, so the non-optional forms are allowed only where the compiler can see
the value being set: locals with an initialiser, and parameters.

A record or variant with a handle field is an **owning type** if any of its
handle fields owns. Owning types can't be copied: whole-record assignment and
by-value passing are errors.

### 5.3 Creating, moving and freeing

```nucleus
var n = new nodes(5, "five", none, none) else fail
```

`new` allocates a slot and initialises every field from its arguments. It takes
the oldest slot on the free list, or the next never-used slot above the
high-water mark, or fails if the pool is full. The slot is reserved before the
arguments are evaluated, so a failed `new` never consumes a moved argument. If
an argument traps, the program ends, so the reserved slot doesn't matter.

**Moving.** An owning handle held in a variable, parameter or field is handed on
only with `move`, which leaves `none` behind (D19). Fresh values, the results of
`new` and of routines returning owning types, need no `move`.

**Freeing** is automatic (D18). A slot is freed:

- when its owning local or parameter goes out of scope, on every exit path,
  including `return`, `exit`, `continue` and `fail`;
- when the variable or field that owns it is overwritten, including with `none`;
- when the slot that owns it is freed; and
- at the end of the statement, if it is a fresh owning value that nothing took,
  such as an unused result of `new` or of a routine.

Freeing `none` does nothing, so the compiler emits the same epilogue whatever
path was taken.

**Order of overwrite.** An assignment to an owning location evaluates the right
side first, then resolves the destination, then frees the old value, then
stores. So `head = move h.next` reads `h.next` before the old head is freed.

### 5.4 Accessing a pool record

There are three ways to reach a record, and each access is one operation,
resolved after all its operands have been evaluated:

| Through | Example | Check | Notes |
| --- | --- | --- | --- |
| An owning local or parameter | `n.value = 1` | none: an owner is never stale | fastest |
| A lease | `h.value = 1` | none | Section 5.6 |
| An identifier | `i.value = 1` | generation check; `stale-handle` trap | about 165 T-states |

An optional handle, owning or not, can't be used directly; it is tested with
`match`, which binds an identifier for the slot (Section 5.5).

Scalar fields are read and written in place. An aggregate field, such as
`name` above, is copied as a whole: `var s = i.name` copies it out to a local,
and `i.name = s` copies it in. It can't be passed by alias.

Because every access resolves its handle after evaluating its operands,
`i.value = f()` calls `f` first, then checks `i`, then stores. Nothing can free
the slot between the check and the access.

### 5.5 Testing optional handles

```nucleus
match head
case some(i)          // i is an identifier for the slot
    print(i.value)
case none
    print("empty")
end
```

For an identifier, `some` means the slot is still live and `none` means the
identifier is empty or stale; the test never traps (D15). For an owning
optional, `some` means it holds a slot.

A non-optional identifier can be made from any owning handle with `id(h)`, in
the same style as a conversion such as `u16(x)`.

### 5.6 Leases

```nucleus
sub bump(var h as nodes)
    h.value = h.value + 1     // direct access: no check
end

var n = new nodes(1, "a", none, none) else fail
bump(n)
```

A `var` parameter of non-optional owning handle type is a **lease**. The rules:

- the argument must be the caller's own owning local;
- the callee may read and write the record's fields through it, with no check;
- the callee may not move it, overwrite it, or pass it on except as a lease; and
- the same local may not be passed twice in one call.

Only the owner can free a slot, and the owner is the caller's local, which
nothing else can reach during the call, so the slot can't be freed while it is
leased.

### 5.7 Optional slot-holders

A `var` parameter of type `nodes?` lends a place that holds a node or `none`.
The callee may move into it, move out of it, or overwrite it:

```nucleus
sub push(var list as nodes?, v as u16) fails
    var n = new nodes(v, "", move list, none) else fail
    list = move n
end
```

Its argument may be any owning optional location: a local, a program variable,
or a field reached through an owner or an identifier. It may not be a local
that is leased in the same call.

### 5.8 The flow check

For each owning local, the compiler tracks whether it **certainly** holds a
value, **certainly** holds `none`, or **may** hold either. Joins take the meet;
loops are checked with the state at the top assumed to be the meet of the entry
and every back edge, `continue` and `exit`.

- Accessing or moving a non-optional owning local that **may** have been moved
  is an error.
- Moves are not allowed inside an operand of `and` or `or`, or in a `while`
  condition.

Because a move stores `none` at run time, no code is needed at joins: a path
that moved a value and one that didn't already agree in memory. Flow states
exist only for owning locals; every other owning location is treated as
possibly holding a value.

### 5.9 Ownership cycles

A slot must never own itself, directly or through a chain. Storing an owning
handle through an **owner path**, one that starts at an owning local, a lease or
a program variable and follows owning fields, can't create a cycle: the stored
handle was owned elsewhere, so it can't be an ancestor of the destination.

Storing an owning handle through a path that starts at an **identifier** can,
because the identifier might point inside the subtree being stored. The runtime
then checks: before storing handle *b* into a field of slot *s*, it follows the
owner links upwards from *s*; if it meets *b*, it traps with `ownership-cycle`.
Each slot's link field holds its owner's address while it is allocated, so the
walk needs no extra storage. It costs one step per level of nesting, and happens
only on structural edits through identifiers.

### 5.10 Freeing without recursion

Freeing a slot frees everything it owns. The runtime keeps a work list threaded
through the link fields: it reads each owned field of a slot, pushes each
non-empty child, then returns the slot to its pool, and repeats until the list
is empty. Stack use is constant.

To find a slot's owned fields, the runtime uses a **descriptor** per owning type
in `rodata`: for each owning field, its offset and the pool it points into; for
each array of them, the offset, stride, count and pool; and for a variant, a
table selected by the tag. The linker keeps a descriptor whenever any live code
can free a slot of that type, including through another type's descriptor.

### 5.11 Generations

A never-used slot has generation 0. `new` gives a fresh slot generation 1, and
each free advances it by one. Generations are 16 bits and **saturating**: when a
slot's generation reaches `$FFFE` and the slot is freed, it is withdrawn from
use for the rest of the run, and its generation is set to `$FFFF`. No identifier
is ever made with generation 0 or `$FFFF`, and the check also rejects them, so
withdrawn and never-used slots never match.

An identifier's slot index is checked against the pool's size as part of the
generation check.

The free list is first in, first out, so frees spread across all slots. A
64-slot pool withdraws its first slot only after about four million frees.

### 5.12 Initial values

Program variables and pool slots start zeroed or initialised. Locals start with
an explicit or default value. For local aggregates:

- a bounded string has its length byte zeroed, which is enough because no
  operation exposes bytes beyond the length;
- a record or array is zeroed in full unless it has an initialiser; and
- zeroing happens after the routine's stack check.

## 6. How each hazard is prevented

| Hazard | Prevention | When |
| --- | --- | --- |
| Out-of-bounds access | Every index is checked; string growth is checked against capacity | run time, unless proved |
| Alias to dead activation storage | Aliases can't be stored; `from` rule on results | compile time |
| Alias to a freed pool slot | No aliases into pools (D16) | compile time |
| Stale owning handle | Owning handles are never copied | compile time |
| Stale identifier | Generation check; generations never repeat | run time |
| Freeing a slot while it is leased | Leases come only from owning locals and can't be moved or overwritten | compile time |
| Double free | Moves leave `none`; owning handles are never copied; cycles are prevented | compile and run time |
| Use after move | Flow check | compile time |
| Leak | Automatic freeing on every exit, overwrite and cascade | placed at compile time |
| Ownership cycle | Owner paths can't form one; identifier paths are checked | compile and run time |
| Uninitialised read | Every storage class has an initial value | compile time |
| Type confusion | Static types; handles name their pool; no casts to or from addresses | compile time |
| Null dereference | Optional handles must be tested with `match` | compile time |
| Stack overflow | Compiler-computed bound and cycle checks (Section 7) | run time |

## 7. The stack

On a Z80 there is no guard page, so stack overflow is a memory-safety hazard.

When the compiler finishes a routine `R`, it has already compiled every routine
`R` calls, except `R` itself and forward routines not yet defined. So it
computes, in its single pass:

```text
need(R) = frame(R) + helperStack(R)
          + the largest need(c) over the routines c that R calls,
            counting 0 for R itself and for forward routines not yet defined
```

`helperStack(R)` comes from the stack figures published for each runtime
helper.

Every cycle of calls passes through a routine that calls itself or calls a
forward routine not yet defined at the call. Every self-recursive and every
forward-declared routine begins with an activation-capacity check: it traps if
`SP − need(R) − guard` would fall below `FREE`. `need(main)` plus the guard is
written into the `LIMITS` record as the stack reserve, so startup's memory check
guarantees the rest. The guard band is a profile value covering BDOS entry and
interrupt-mode-1 pushes. See the [CP/M target](cpm-target.md), Section 4.1.

## 8. Patterns

**A list.**

```nucleus
var head as nodes?

sub push(v as u16) fails
    var n = new nodes(v, "", move head, none) else fail
    head = move n
end

sub total() as u32
    var sum as u32 = 0
    var p = id(head)                  // id nodes?
    while true
        match p
        case some(i)
            sum = sum + u32(i.value)
            p = id(i.next)
        case none
            return sum
        end
    end
end
```

**Deleting matching nodes.**

```nucleus
sub removeAll(v as u16)
    while true                        // strip matching nodes from the head
        match head
        case some(i)
            if i.value <> v
                exit
            end
            head = move i.next        // the old head is freed
        case none
            return
        end
    end
    var p = id(head)
    while true                        // then walk the rest
        match p
        case some(i)
            match i.next
            case some(q)
                if q.value = v
                    i.next = move q.next   // q is freed; cycle check runs
                else
                    p = id(q)
                end
            case none
                return
            end
        case none
            return
        end
    end
end
```

**A tree with parent links:** `left` and `right` are `trees?` and own their
subtrees; `parent` is `id trees?`. Removing a subtree is one assignment of
`none`.

**A graph:** every vertex is owned by one element of a program array
`vertices as verts?[32]`; edges are `id verts?`. Removing a vertex makes every
edge to it stale, and a sweep drops them with `match`, which never traps.

**A Nucleus-style free list** over a program array with integer links still
compiles and is memory safe by bounds checking, but detects no stale index.

## 9. What Baton gives up

- **A general heap.** All dynamic storage is in declared pools.
- **Shared ownership.** One owner per slot; sharing is by identifier.
- **Copying owning records.**
- **Aliases into pool records.** Aggregate fields are copied out; records are
  passed as identifiers, leases or slot-holders.
- **Leasing from anything but a local.** A node owned by a program variable is
  moved into a local to be leased, and moved back.

## 10. Costs

**[estimate]** Z80 at 4 MHz:

| Mechanism | Bytes | T-states |
| --- | --- | --- |
| Identifier access | 6 at the site, about 28 per pool in a helper | about 165 |
| Owning-handle or lease access | 3 | 16 |
| `match` on an optional handle | 5 plus the arms | about 20 |
| `move` (store `none`) | 3 to 4 | about 16 |
| Overwrite of an owning location | about 9 | about 40, plus freeing |
| Freeing one slot | about 6 at the site; a shared helper and descriptors | 200 to 250 per slot |
| Cycle check | in the identifier store helper | about 60 per level |
| Activation-capacity check | 5 at the site, a 15-byte helper | 60 to 95, only in forward and self-recursive routines |
| Pool overhead | 4 bytes per slot, about 6 per pool | — |

Compiler memory: a flow state per owning local per open control level, and
`need` per routine. No effect sets and no alias provenance are needed.

## 11. Later

**Arenas** give temporary storage whose size is known only at run time, freed
when a scope ends. Their contents would be reached only by aliases, which can't
escape the scope. Each allocation needs its own capacity check, because the
static stack bound can't cover a run-time size.

**Routine values** must carry their `from` clause in their type, and a call
through one counts as a forward call for the stack rule.

## 12. Open questions

1. **Access to a node owned by a program variable** costs a `match` and
   identifier checks, or a move into a local and back for a lease. Is a cheaper
   form needed?
2. **Write-before-read for large local arrays,** instead of zeroing them.
3. **Generics.** A routine works on one pool's handles; code for two pools of
   the same record type must be written twice.
