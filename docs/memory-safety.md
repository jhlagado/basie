# Baton memory safety

- Status: draft design, revision 4
- Date: 2026-10-04
- Decisions it rests on: [design decisions](design-decisions.md) D8, D15–D30
- Reviews: [1](reviews/2026-10-03-memory-safety-review.md),
  [2](reviews/2026-10-03-memory-safety-review-2.md),
  [whole design](reviews/2026-10-04-design-review.md)
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
| **Activation storage** | A routine's locals, including local records and arrays: lives until the end of the block that declares it |
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
| **Lease** | Direct access to a node held in the caller's own owning local, given by a `var` record parameter or by `match` on that local |
| **Generation** | A counter in each slot that changes whenever the slot is freed, so stale identifiers can be detected |

### 1.2 The two kinds of reference

**Aliases** are for program and activation storage: globals and locals. They are
how records, arrays and strings are passed to routines. They are implicit, can't
be stored, and live only for the call they were passed to.

**Handles** are for pool storage, and only for pool storage. They are explicit
values: you can store them in variables and fields. An owning handle is never
copied, only moved; an identifier can be copied freely and is checked whenever
it is used.

The two meet in one place, the **lease**: a node held in an owning local can be
lent to a `var` record parameter, or reached through a `match` on that local,
with direct access for as long as the call or the arm lasts. Nothing else can
reach the node meanwhile, so it can't be freed underneath.

Otherwise, there is never an alias pointing into a pool slot (D16). That rule is
what keeps the design simple.

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
| Activation storage | locals, at any statement position (D28) | to the end of the enclosing block | at the end of the block |
| Pool storage | slots of a top-level `pool` | from `new` until freed | when its owner goes away |
| Arena storage | version 2 | one scope | at the end of the scope |

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
- An alias points into a pool slot only as a lease (Section 5.6). A pool
  record's aggregate fields are otherwise copied out to be passed on
  (Section 5.4).

These rules make aliases safe without further checking: program storage is
never freed, activation storage outlives every call made from its block, and a
leased node's owner can't be reached during the lease.

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
slot only ever holds its pool's record type. The expected style is one pool per
record type, shared by every structure that uses it (D23).

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

`id(h)` makes an identifier: from `nodes` it gives `id nodes`, and from `nodes?`
it gives `id nodes?`. It may be applied to any owning handle, including one
reached through a field.

A record with an owning handle field, directly or through a nested record or
array, is an **owning type**. Owning types can't be copied: whole-record
assignment and by-value passing are errors.

### 5.3 Creating, moving and freeing

```nucleus
var n = new nodes(5, "five", none, none)
```

`new` allocates a slot and initialises every field from its arguments. It takes
the oldest slot on the free list, or the next never-used slot above the
high-water mark. If the pool is full, it traps with `pool-full` (D27);
`new? nodes(...)` returns `nodes?` instead, `none` when the pool is full. The
slot is reserved before the arguments are evaluated, so exhaustion never
consumes a moved argument.

**Moving.** An owning handle held in a variable, parameter or field is handed on
only with `move`, which leaves `none` behind (D19). Fresh values, the results of
`new` and of routines returning owning types, need no `move`.

**Freeing** is automatic (D18). A slot is freed:

- when its owning local or parameter goes out of scope, at the end of its block,
  on every exit path, including `return`, `exit`, `continue` and `fail`;
- when the variable or field that owns it is overwritten, including with `none`;
- when the slot or the local aggregate that owns it is freed; and
- when the temporary holding it ends (below).

Freeing `none` does nothing, so the compiler emits the same epilogue whatever
path was taken.

**Fresh temporaries.** A fresh owning value that is not stored, such as an unused
result of `new` or of a routine, is held in an anonymous local of the innermost
enclosing statement. It is freed on every exit from that statement. For a
`match`, the statement is the whole `match`, so a fresh subject lives until the
end of the last arm. A temporary may be matched and leased like a local.

**Order of overwrite.** An assignment to an owning location evaluates the right
side first, then resolves the destination, then frees the old value, then
stores. So `head = move h.next` reads `h.next` before the old head is freed.

### 5.4 Accessing a pool record

Each access is one operation, resolved after all its operands have been
evaluated:

| Through | Example | Check | Notes |
| --- | --- | --- | --- |
| An owning local or parameter | `n.value = 1` | none: an owner is never stale | fastest |
| A lease | `n.value = 1` inside the callee or the `match` arm | none | Section 5.6 |
| An identifier | `i.value = 1` | generation check; `stale-handle` trap | about 165 T-states |

A path through an identifier may select any chain of record fields and checked
array indices under one generation check, such as `i.pos.x` or `i.kids[k]`; only
the leaf is read or written. A path never continues through a second handle
without a new access: `i.next.value` is two accesses, through the identifier
`i` and then through the handle in `i.next`.

An optional handle, owning or not, can't be used directly; it is tested with
`match` (Section 5.5).

Scalar fields are read and written in place. An aggregate field, such as
`name`, is copied as a whole: `var s = i.name` copies it out to a local, and
`i.name = s` copies it in. It can't be passed by alias, except through a lease.

Because every access resolves its handle after evaluating its operands,
`i.value = f()` calls `f` first, then checks `i`, then stores. Nothing can free
the slot between the check and the access.

### 5.5 Testing optional handles

```nucleus
match head
case some(i)          // head is a program variable: i is an identifier
    print(i.value)
case none
    print("empty")
end
```

- For an identifier subject, `some` means the slot is still live, and `none`
  means the identifier is empty or stale. The test never traps (D15).
- For an owning subject that is a **program variable or a field**, `some(i)`
  binds an identifier.
- For an owning subject that is the **caller's own owning local**, `some(n)`
  gives direct access to the node, a lease for the length of the arm. The local
  can't be moved, overwritten or passed to a slot-holder within the arm.
- `match move x` moves the value out of `x`. In `some(n)`, `n` is a non-optional
  owning local of the arm, which is how a `nodes?` becomes a `nodes`; in `none`,
  nothing was moved.

### 5.6 Leases

```nucleus
sub bump(var n as Node)
    n.value = n.value + 1     // direct access: no check
end

var h = new nodes(1, "a", none, none)
bump(h)                       // lends h's node
var p as Node
bump(p)                       // a Node in activation storage works too
```

A `var` record parameter accepts any record of its type that the caller can
change, including the node held by one of the caller's own owning locals (D30).
For a node:

- the argument must be the caller's own owning local, or a temporary;
- that local may not appear anywhere else in the same statement, except as
  `id(h)` or as a read of a scalar field; and
- the callee sees an ordinary `var` record: it can read and write fields, but it
  has no handle to move, overwrite or free.

Only the owner can free a slot, and the owner is a local of the caller that
nothing else can reach during the call. So the slot can't be freed while it is
leased.

### 5.7 Slot-holders

A `var` parameter of type `nodes?` lends a place that holds a node or `none`.
The callee may move into it, move out of it, or overwrite it:

```nucleus
sub push(var list as nodes?, v as u16)
    var n = new nodes(v, "", move list, none)
    list = move n
end
```

Its argument must be a location that **no pool slot owns**: an owning local, a
program variable, or a field or element of a local or program aggregate. A field
of a pool record can't be passed as a slot-holder; the program edits it inline
through an identifier, where every access is checked. It may not be a local
leased in the same statement.

This keeps a slot-holder's storage outside every pool, so nothing the callee
does can free the storage it is writing to.

### 5.8 The flow check

For each owning local, the compiler tracks whether it **certainly** holds a
value, **certainly** holds `none`, or **may** hold either.

- Accessing or moving a non-optional owning local that **may** have been moved
  is an error.
- Joins take the meet of the incoming states.
- **Loops** are checked at their back edges: at the end of the body, at every
  `continue`, and at a `while` condition's re-test, each non-optional owning
  local that **certainly** held a value at loop entry must certainly hold one
  again. The compiler checks this when it reaches each back edge, so the rule
  needs no look-ahead. The state after the loop is the meet of the
  condition-false state and every `exit`.
- Moves are not allowed inside an operand of `and` or `or`, or in a `while`
  condition.

Because a move stores `none` at run time, no code is needed at joins: a path
that moved a value and one that didn't already agree in memory. Flow states
exist only for owning locals; every other owning location is treated as
possibly holding a value.

### 5.9 Owner links and cycles

Each allocated slot's link field records its owner:

- **0** while it is owned by anything that is not a pool slot: a local, a
  program variable, or a local or program aggregate; and
- **the owning slot's address** while it is owned by a field of another slot.

`new` writes 0. Every store of an owning handle writes the moved slot's link: the
destination slot's address when the destination is a field of a slot, 0
otherwise. A move out of a field leaves the moved slot's link unchanged until the
next store, which is harmless: the cycle check below reads the links of slots
**above** the destination, and those were not moved in the same statement.

A slot must never own itself, directly or through a chain. A store into a
location that no slot owns can't create a cycle. A store into a field of a slot
reached through an owning local or a lease can't either, because that slot's
link is 0: it is a root. Only a store into a field of a slot reached through an
**identifier** can, because the identifier may point inside the subtree being
stored. Before storing handle *b* into a field of slot *s*, the runtime follows
the links upwards from *s* until it reaches 0; if it meets *b*, it traps with
`ownership-cycle`. Each step costs one link read.

### 5.10 Freeing without recursion

Freeing a slot frees everything it owns. The runtime keeps a work list threaded
through the link fields: it reads each owned field of a slot, pushes each
non-empty child, then returns the slot to its pool, and repeats until the list
is empty. Stack use is constant.

The cascade is **idempotent**: a slot being freed is marked, and a child that is
already marked or already free is not pushed. Any cycle that slipped through
would then become a leak, not a double free.

To find a slot's owned fields, the runtime uses a **descriptor** per owning type
in `rodata`: for each owning field, its offset and the pool it points into; and
for each array of them, the offset, stride, count and pool. The linker keeps a
descriptor whenever live code can free a slot of that type, including through
another type's descriptor. The same descriptors free the owning fields of local
aggregates at the end of their block.

### 5.11 Generations

A never-used slot has generation 0. `new` gives a fresh slot generation 1. A slot
is allocated only while its generation is below `$FFFF`. Freeing advances the
generation; a slot whose generation becomes `$FFFF` is withdrawn instead of being
put on the free list. No identifier is ever made with generation 0 or `$FFFF`,
and the check rejects both, so withdrawn and never-used slots never match. An
identifier's slot index is checked against the pool's size as part of the same
check.

The free list is first in, first out, so frees spread across all slots. A
64-slot pool withdraws its first slot only after about four million frees.

### 5.12 Local aggregates that own

A local record or array may contain owning handles, for example
`var tmp as Holder` where `Holder` has a field `head as nodes?`, or
`var arr as nodes?[8]`. At the end of its block, the compiler frees its owning
fields using the type's descriptor, on every exit path.

- Through a ticket (`h as Holder`), owning fields can be read, matched and
  turned into identifiers, but not moved or overwritten.
- Through a `var` parameter (`var h as Holder`), they can be moved and
  overwritten; such a store needs no cycle check, since the record is not in a
  pool.
- A pool record with a field of an owning record type is reached through an
  identifier path such as `i.sub.head`, under one check (Section 5.4).

### 5.13 Initial values

Program variables and pool slots start zeroed or initialised. Locals start with
an explicit or default value. For local aggregates:

- a bounded string has its length byte zeroed, and raising a string's length
  zeroes the bytes it exposes (D25);
- a record or array is zeroed in full unless it has an initialiser; and
- zeroing happens after the routine's stack check.

## 6. How each hazard is prevented

| Hazard | Prevention | When |
| --- | --- | --- |
| Out-of-bounds access | Every index is checked; string length is checked against capacity | run time, unless proved |
| Alias to dead activation storage | Aliases can't be stored; `from` rule on results | compile time |
| Alias to a freed pool slot | Only leases alias pool slots, and a leased slot's owner is unreachable | compile time |
| Stale owning handle | Owning handles are never copied | compile time |
| Stale identifier | Generation check; generations never repeat | run time |
| Freeing storage a slot-holder writes to | Slot-holders are never inside a pool slot | compile time |
| Double free | Moves leave `none`; owning handles are never copied; cycles are prevented; the cascade is idempotent | compile and run time |
| Use after move | Flow check | compile time |
| Leak | Automatic freeing at block exit, on overwrite, through cascades and of temporaries | placed at compile time |
| Ownership cycle | Only identifier paths can form one, and they are checked | run time |
| Uninitialised read | Every storage class has an initial value | compile time |
| Type confusion | Static types; handles name their pool; no casts to or from addresses | compile time |
| Null dereference | Optional handles must be tested with `match` | compile time |
| Pool exhaustion | `new` traps; `new?` returns `none` | run time |
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

sub push(v as u16)
    var n = new nodes(v, "", move head, none)
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

**Working fast on one node owned by a program variable.** Move it into a local,
work on it there, and move it back:

```nucleus
sub bumpHead()
    match move head
    case some(n)                      // n owns the node: direct access
        n.value = n.value + 1
        head = move n
    case none
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
- **Aliases into pool records,** except leases. Aggregate fields are otherwise
  copied out.
- **Pool fields as slot-holders.** They are edited inline through identifiers.
- **Leasing from anything but a local.** A node owned by a program variable is
  moved into a local to be leased, and moved back.

## 10. Costs

**[estimate]** Z80 at 4 MHz:

| Mechanism | Bytes | T-states |
| --- | --- | --- |
| Identifier access | 6 at the site, about 28 per pool in a helper | about 165 |
| Owning-handle or lease access | 3 | 16 |
| `match` on an optional handle | 5 plus the arms | about 20 |
| `move` (store `none`, write the owner link) | 6 to 8 | about 40 |
| Overwrite of an owning location | about 9 | about 40, plus freeing |
| Freeing one slot | about 6 at the site; a shared helper and descriptors | 200 to 250 per slot |
| Cycle check | in the identifier store helper | about 60 per level |
| Activation-capacity check | 5 at the site, a 15-byte helper | 60 to 95, only in forward and self-recursive routines |
| Pool overhead | 4 bytes per slot, about 6 per pool | — |

Compiler memory: a flow state per owning local per open block, and `need` per
routine. No effect sets and no alias provenance are needed.

## 11. Version 2

**Variants with owning payloads** need rules for binding (an owning payload binds
as an identifier), construction, overwrite (the old payload is freed through a
tag-selected descriptor) and pool-field subjects.

**Arenas** give temporary storage whose size is known only at run time. Each
allocation needs its own capacity check, because the static stack bound can't
cover a run-time size.

**Routine values** must carry their `from` clause in their type, and a call
through one counts as a forward call for the stack rule.

## 12. Open questions

1. **Write-before-read for large local arrays,** instead of zeroing them.
