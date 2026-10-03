# Baton memory safety

- Status: design, revision 5; ready to freeze once reviewed
- Date: 2026-10-04
- Decisions it rests on: [design decisions](design-decisions.md) D8, D15–D30
- Reviews: [1](reviews/2026-10-03-memory-safety-review.md),
  [2](reviews/2026-10-03-memory-safety-review-2.md),
  [whole design](reviews/2026-10-04-design-review.md),
  [3](reviews/2026-10-04-memory-safety-review-3.md)
- Related: [CP/M target](cpm-target.md) (stack checks, traps),
  [feature inventory](feature-inventory.md) (`select`)

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
| **`?`** | "May be empty". An optional value must be tested with `select` before use |
| **`none`** | The empty value of an optional handle |
| **`move`** | Hands an owning handle from a named variable, parameter or field to a new owner, leaving `none` behind |
| **Freeing** | Returning a slot to its pool. Always automatic |
| **Lease** | Direct access to a node held in the caller's own owning local or parameter, given by a record parameter or by `select` on it |
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
lent to a `var` record parameter, or reached through a `select` on that local,
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

A pool is placed as a `bss` blob. Each slot holds a 2-byte generation and a
2-byte link, **in the four bytes immediately before the record**, followed by
the record itself. A handle is the record's address, so the runtime can find
any slot's generation and link from its handle alone, whatever pool it is in.
The pool also has a high-water mark and a free-list head and tail. Pool storage
never moves, and a slot only ever holds its pool's record type. The expected
style is one pool per record type, shared by every structure that uses it (D23).

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
var t = new trees(1)              // trailing fields omitted: zeroed
```

`new` allocates a slot and initialises fields from its arguments, in order.
Trailing arguments may be omitted, and their fields are zeroed; this is how a
record with an array of owning handles, or a nested owning record, is built,
since such a field has no value that could be passed. `new`'s stores into the
new record are initialising stores, not overwrites.

`new` takes the oldest slot on the free list, or the next never-used slot above
the high-water mark. If the pool is full, it traps with `pool-full` (D27).
`new? nodes(...)` returns `nodes?` instead, and when the pool is full it
evaluates **none** of its arguments and returns `none`. In both forms the slot
is reserved before the arguments are evaluated, so exhaustion never consumes a
moved argument. A non-optional local moved into a `new?` argument is
**may be moved** afterwards, on both arms of the `select` that tests the result.

**Moving.** An owning handle held in a variable, parameter or field is handed on
only with `move`, which leaves `none` behind (D19). Fresh values, the results of
`new` and of routines returning owning types, need no `move`.

**Freeing** is automatic (D18). A slot is freed:

- when its owning local or parameter goes out of scope, at the end of its block,
  on every exit path, including `return`, `exit`, `continue` and `fail`;
- when the variable or field that owns it is overwritten, including with `none`;
- when the slot or the local aggregate that owns it is freed; and
- when the temporary holding it ends (below).

Freeing `none` does nothing. A routine's exits share one epilogue that frees its
owning locals, so freeing costs a jump per exit path, not a copy of the freeing
code.

**Fresh temporaries.** A fresh owning value that is not stored, such as an unused
result of `new` or of a routine, is held in an anonymous local of the innermost
enclosing statement, which is set to `none` when the statement begins. It is
freed on every exit from that statement. For a `select`, the statement is the
whole `select`, so a fresh subject lives until the end of the last arm. A
temporary made in a `while` or `if` condition is freed once the condition has
been tested. A temporary in a call with a `handle` body lives until the end of
the handle body. Because the anonymous local starts as `none`, an operand left
unevaluated by `and` or `or` leaves nothing to free. A temporary may be selected
on and leased like a local.

**Order of overwrite.** An assignment to an owning location evaluates the right
side first, then resolves the destination, then frees the old value, then
stores. So `head = move h.next` reads `h.next` before the old head is freed.

### 5.4 Accessing a pool record

Each access is one operation, resolved after all its operands have been
evaluated:

| Through | Example | Check | Notes |
| --- | --- | --- | --- |
| An owning local or parameter | `n.value = 1` | none: an owner is never stale | fastest |
| A lease | `n.value = 1` inside the callee or the `select` arm | none | Section 5.6 |
| An identifier | `i.value = 1` | generation check; `stale-handle` trap | about 165 T-states |

A path through an identifier may select any chain of record fields and checked
array indices under one generation check, such as `i.pos.x` or `i.kids[k]`; only
the leaf is read or written. A path never continues through a second handle
without a new access: `i.next.value` is two accesses, through the identifier
`i` and then through the handle in `i.next`.

An optional handle, owning or not, can't be used directly; it is tested with
`select` (Section 5.5).

Scalar fields are read and written in place. An aggregate field, such as
`name`, is copied as a whole: `var s = i.name` copies it out to a local, and
`i.name = s` copies it in. Passing it to a ticket parameter, `g(i.name)`, copies
it into a hidden temporary in the caller's frame and passes that; the
temporary is counted in the frame (Section 7). It can't be passed to a `var`
parameter, except through a lease.

Because every access resolves its handle after evaluating its operands,
`i.value = f()` calls `f` first, then checks `i`, then stores. Nothing can free
the slot between the check and the access.

### 5.5 Testing optional handles

```nucleus
select head
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
- `select move x` moves the value out of `x`. In `some(n)`, `n` is a non-optional
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

A record parameter, a ticket or `var`, accepts any record of its type in program
or activation storage, and also the node held by one of the caller's own owning
locals or owning parameters, or by a temporary (D30). Passing a node is a
**lease**:

- that local or parameter may not appear anywhere else in the same statement,
  except as `id(h)` or as a read of a scalar field (Section 5.8); and
- the callee sees an ordinary record: through a `var` parameter it can read and
  write fields, but it has no handle to move, overwrite or free.

Only the owner can free a slot, and the owner is a local or parameter of the
caller that nothing else can reach during the call. So the slot can't be freed
while it is leased.

**The owner word.** A `var` parameter whose type is an owning type (a record or
array containing owning handles, or a `nodes?` slot-holder) carries a hidden
**owner word**, supplied by the caller: 0 when the argument is in program or
activation storage, and the slot's address when the argument is a leased node or
lies inside one. Every store of an owning handle through the parameter writes
the owner word as the moved slot's link (Section 5.9). A parameter passed on to
another such parameter passes its own owner word. The cost is 2 bytes of stack
per such parameter and 1 to 3 bytes at each call site.

**Identifiers inside a lease.** In a routine with a `var` record parameter `n`,
`id(n)` gives `id P?`, where `P` is the pool of that record type: the node's
identifier when `n` is a leased node, and `none` when it is not. It is an error
if the record type has more than one pool.

**Results.** A lease may be named in a `from` clause. A result rooted in it is
used within the caller's statement, where the lease's statement rule already
applies. `from` may not name a slot-holder.

### 5.7 Slot-holders

A `var` parameter of type `nodes?` lends a place that holds a node or `none`.
The callee may move into it, move out of it, or overwrite it:

```nucleus
sub push(var list as nodes?, v as u16)
    var n = new nodes(v, "", move list, none)
    list = move n
end
```

Its argument must be one of:

- an owning local or parameter of type `nodes?`, or a program variable;
- a field or element of a local or program aggregate; or
- a field or element of a `var` owning-aggregate parameter, including a leased
  node, in which case the slot-holder inherits that parameter's owner word.

A field of a pool record reached through an **identifier** can't be passed as a
slot-holder; the program edits it inline, where every access is checked. A
slot-holder may not be a local or parameter leased in the same statement.

These rules keep a slot-holder's storage out of reach of anything that could
free it during the call: either it is outside every pool, or it lies in a
leased node whose owner nothing else can reach.

### 5.8 The flow check and the statement rule

For each owning local and owning parameter, the compiler tracks whether it
**certainly** holds a value, **certainly** holds `none`, or **may** hold either.

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

**The statement rule.** Within one statement, an owning local or parameter that
is used directly anywhere (as an access path such as `x.value` or `x.kids[k]`,
an assignment destination, a lease argument, or a `select` subject) may not be
moved or overwritten anywhere else in that statement. The exceptions are
`id(x)`, reads of scalar fields, and a plain `x = ...` with no other direct use
of `x`. So `x.value = eat(move x)` and `show(h, eat(move h))` are errors: the
right side would free the node the left side or the lease still uses.

Because a move stores `none` at run time, no code is needed at joins: a path
that moved a value and one that didn't already agree in memory. Flow states
exist only for owning locals and parameters; every other owning location is
treated as possibly holding a value.

### 5.9 Owner links and cycles

Each allocated slot's link records its owner:

- **0** while it is owned by anything that is not a pool slot: a local, a
  parameter, a temporary, a program variable, or a local or program aggregate;
  and
- **the owning slot's address** while it is owned by a field of another slot.

**Every store of a non-`none` owning handle writes the moved slot's link.** The
value written is the destination slot's address when the destination is a field
of a slot reached through an owner, an identifier, or a lease's owner word; it
is 0 otherwise. Binding an argument to an owning parameter, binding `some(n)` in
`select move`, and holding a fresh value in a temporary are stores that write 0.
`new` writes 0 into the new slot's link. A `none` handle has no slot, so no link
is written for it; the test costs 4 bytes and about 20 T-states, folded into the
store helper where one is used.

So no link is stale beyond the statement that moved its slot, and whenever the
cycle check runs, the links form a forest whose roots have link 0.

A slot must never own itself, directly or through a chain. A store into a
location no slot owns can't create a cycle. A store into a field of a slot that
is a root (reached through an owning local, an owning parameter or a temporary)
can't either. Only a store into a field of a slot reached through an
**identifier**, or through a lease of a slot that is not itself a root, can.
Before storing handle *b* into a field of slot *s*, the runtime follows the
links upwards from *s* until it reaches 0; if it meets *b*, it traps with
`ownership-cycle`. The walk takes one step per level between *s* and its root,
about 60 T-states each: appending to the end of a 64-node list walks the whole
list.

### 5.10 Freeing without recursion

Freeing a slot frees everything it owns. The runtime keeps a work list threaded
through the link words: it reads each owned field of a slot, pushes each child
**whose link equals the address of the slot being freed**, then returns the slot
to its pool, and repeats until the list is empty. Stack use is constant.

The link test replaces a mark bit. A correctly owned live child always passes
it; a child that is already free, already on the work list, or reached through a
cycle that slipped past the check never does, since its link no longer names
this slot. So the cascade can neither loop nor free a slot twice. The slot at
the top of a cascade, freed from a local, parameter, temporary or local
aggregate, has link 0 and is freed without the test. A withdrawn slot's fields
are never read again.

To find a slot's owned fields, the runtime uses a **descriptor** per owning type
in `rodata`: for each owning field, its offset; and for each array of them, the
offset, stride and count. Because the generation and link sit just before every
record, the descriptor needs no pool information. The linker keeps a descriptor
whenever live code can free a slot of that type, including through another
type's descriptor. The same descriptors free the owning fields of local
aggregates at the end of their block.

### 5.11 Generations

A never-used slot has generation 0. `new` gives a fresh slot generation 1. A slot
is allocated only while its generation is below `$FFFF`. Freeing advances the
generation; a slot whose generation becomes `$FFFF` is withdrawn instead of being
put on the free list. No identifier is ever made with generation 0 or `$FFFF`,
and the check rejects both, so withdrawn and never-used slots never match.

An identifier holds its slot's address and the generation, 4 bytes. Identifiers
are made only by `id()`, are never converted from integers, and start as `none`,
so an identifier's address always names a real slot; no range check is needed.

The free list is first in, first out, so frees spread across all slots. A
64-slot pool withdraws its first slot only after about four million frees.

### 5.12 Local aggregates that own

A local record or array may contain owning handles, for example
`var tmp as Holder` where `Holder` has a field `head as nodes?`, or
`var arr as nodes?[8]`. At the end of its block, the compiler frees its owning
fields using the type's descriptor, on every exit path.

- Through a ticket (`h as Holder`), owning fields can be read, tested with `select` and
  turned into identifiers, but not moved or overwritten.
- Through a `var` parameter (`var h as Holder`), they can be moved and
  overwritten. Such a store writes the parameter's owner word as the link
  (Section 5.6); when the word is 0 the record is not in a pool and no cycle
  check is needed.
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
| Null dereference | Optional handles must be tested with `select` | compile time |
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

`frame(R)` is the largest total of locals and temporaries live at any one point
in `R`: blocks nested inside one another add up, while blocks side by side share
space.

Every cycle of calls passes through a routine that calls itself or calls a
forward routine not yet defined at the call. **A routine that calls itself must
be forward-declared**, so every cycle passes through a forward-declared routine.
Every forward-declared routine begins with an activation-capacity check: it
traps if `SP − need(R) − guard` would fall below `FREE`.

**Filling in the prologue.** `frame(R)` and `need(R)` are known only when the
routine ends, after its prologue has been emitted. So the prologue reads them
from a 4-byte pair the compiler writes into the routine's blob after its code,
reached by a self-reference. This costs about 2 bytes and 10 T-states per
routine more than immediate operands, and works for routines too large for the
routine buffer. `need(main)` plus the guard is
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
        select p
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
    select move head
    case some(n)                      // n owns the node: direct access
        n.value = n.value + 1
        head = move n
    case none
    end
end
```

Appending at the tail through an identifier pays the cycle walk over the whole
list (Section 5.9); a list that grows at the tail should keep an identifier to
the tail's parent or be built at the head.

**Deleting matching nodes.**

```nucleus
sub removeAll(v as u16)
    while true                        // strip matching nodes from the head
        select head
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
        select p
        case some(i)
            select i.next
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
edge to it stale, and a sweep drops them with `select`, which never traps.

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
| Identifier access | 6 at the site, about 28 in a shared helper | about 150 |
| Owning-handle or lease access | 3 | 16 |
| `select` on an optional handle | 5 plus the arms | about 20 |
| `move` (store `none`; test for `none`; write the owner link) | 10 to 12 | about 60 |
| Overwrite of an owning location | about 9 | about 40, plus freeing |
| Freeing one slot | about 6 at the site; a shared helper and descriptors | 200 to 250 per slot |
| Cycle check | in the identifier store helper | about 60 per level between the destination and its root |
| Owner word for a `var` owning parameter | 1 to 3 at the call site | 2 bytes of stack |
| Activation-capacity check | 5 at the site, a 15-byte helper | 60 to 95, only in forward-declared routines |
| Pool overhead | 4 bytes per slot, before each record; about 6 per pool | — |
| Prologue figures | 4 bytes per routine, after its code | about 10 |

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
