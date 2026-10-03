# Third adversarial review of the memory-safety design

- Date: 2026-10-04
- Document: memory-safety.md revision 4, with design-decisions.md D1–D34,
  cpm-target.md §4.1 and §10, build-pipeline.md §6 (the routine buffer), the
  Nucleus specification chapters 7, 9, 12, 13, 14 and 15, and the three earlier
  reviews.
- Method: every guarantee in §2 was assumed false until a program failed to
  break it. Every mechanism added or changed since revision 3 (leases through
  `var` record parameters, `select` leases, `select move`, owner links, the
  idempotent cascade, fresh temporaries, block scope, the back-edge rule) was
  attacked with programs in the revision 4 syntax. Each rule was then checked
  against a single-pass streaming compiler with a routine buffer.

Counts: 3 unsound (R1–R3), 5 major (R4–R8), 10 minor (R9–R18). Of the last
review's nine unsound findings, six are fixed, two are partly fixed and one
fix introduces a new problem.

**Notation.** Programs use revision 4 syntax. "S(x)" is the slot owned by `x`.
Link values are written as slot names; 0 is the root link.

---

## 1. Verdicts on the whole-design review

| ID | Verdict | Note |
| --- | --- | --- |
| U1 | fixed | §5.7 restricts slot-holders to locations no slot owns. The restriction cannot be applied inside a `var` parameter's body, where the compiler cannot classify the referent (R1). |
| U2 | partly fixed | U1's restriction removes the route and the cascade is declared idempotent, but the mark it relies on has no representation that distinguishes it from a live owner link (R4). |
| U3 | fixed | The same-statement rule in §5.6. It is not applied to direct access through an owning local, which has the same hole in the destination position (R2). |
| U4 | fix introduces a new problem | The link is defined, roots are 0, and the stale window is argued correctly for identifier paths. But D30 made the lease a `var` record parameter, and inside such a routine the compiler cannot know whether a store lands in a slot or in a program record, so it cannot write the link the walk depends on (R1). Parameter and `select move` bindings are not stated to be stores (R5). |
| U5 | fixed | Anonymous local of the innermost statement. Loop conditions and short-circuit operands need two sentences (R10). |
| U6 | fixed | |
| U7 | deferred | Variants are version 2 (D24); §11 records the rules needed. Not a version 1 hazard. |
| U8 | fixed | Back-edge rule, checkable when each back edge is reached. |
| U9 | fixed | §5.12 and the identifier-path rule in §5.4. |
| F1 | fixed | `select move`. |
| F2 | fixed | `new` traps (D27); `new?` returns `none`. What `new?` does to moved arguments on exhaustion is unstated (R11). |
| F3 | fixed | D28. |
| F4 | fixed | `select` on an owning local is a lease. |
| F5 | fixed | `new` is infallible, so it may be an argument. |
| F6, F7 | fixed | D31. |
| F8 | partly fixed | D31 admits any integer type as a counter; the bound's widening rule is unstated. Not a memory hazard. |
| F9 | not fixed | Not a memory hazard. |
| F10 | not fixed | `var` results have no syntax and no assignment-root rule. Not a memory hazard on CP/M. |
| F11 | not fixed | Nothing says whether `from` may name a `var n as Node` parameter. It is sound if it may (R17). |
| F13 | deferred | §11 records the rule for version 2. |

---

## 2. New findings

### Unsound

#### R1. Inside a `var` record parameter's body the owner link cannot be written, and a wrong link defeats the cycle check or sends the walk through non-slot memory

**Where:** D30; §5.6 "the callee sees an ordinary `var` record: it can read and
write fields"; §5.9 "Every store of an owning handle writes the moved slot's
link: the destination slot's address when the destination is a field of a
slot, 0 otherwise"; §5.12 "Through a `var` parameter (`var h as Holder`), they
can be moved and overwritten".

`var n as Node` binds either a program or activation record or a leased pool
slot, and the routine is compiled once. At `n.next = move x` the compiler must
emit a link write of either 0 or the slot's address. It does not know which,
and at run time nothing distinguishes a slot's address from a record's.

If it writes 0:

```nucleus
record Node
    value as u16
    next  as nodes?
end
pool nodes as Node[8]

sub attach(var n as Node)
    n.next = new nodes(2, none)       // child C: link written as 0, but C is owned by S(h)
end

sub leak()
    var h = new nodes(1, none)        // S, link 0
    attach(h)                         // S.next = C, C.link = 0 (wrong: should be S)
    var i = id(h)
    select i.next
    case some(c)                      // identifier to C
        c.next = move h               // walk from C: C.link = 0, stop; h not met; no trap
    case none
    end
end                                   // h is none: nothing freed. S and C form a cycle: leaked
```

Claim 7 is violated. The same program through a slot-holder
(`push(n.next, 2)` inside `attach`) gives the same wrong link, and through an
open array (`sub fill(var kids as nodes?[])` bound to `n.kids`) the same
again.

If it instead writes the record's address, treating every `var` referent as a
slot, a program record poisons the walk:

```nucleus
var top as Node                       // program storage, no link word

sub bad()
    attach(top)                       // C.link = address of top
    select top.next
    case some(c)
        c.next = new nodes(3, none)   // walk from C reads C.link = &top, then reads a "link"
    case none                         //   at &top + offset: bytes of top or whatever follows it
    end
end
```

The walk compares garbage with the stored handle and follows it until it
happens on a zero word. It only reads, so it corrupts nothing, but it can loop
or trap `ownership-cycle` on a valid program.

The same ambiguity makes §5.7 and §5.12 contradict each other: §5.12 lets a
`var h as Holder` routine move and overwrite `h.head` "since the record is not
in a pool", but a `Holder` can be a pool's record type and `h` can then be a
lease. And `push(h.head, 1)` inside that routine is a slot-holder argument that
§5.7's list does not admit, though it is harmless.

**Fix.** Every `var` parameter whose type is an owning type (record, array,
or `nodes?` slot-holder) carries a hidden **owner word**: 0 when the argument
is in program or activation storage, the slot's address when the argument is
or lies inside a leased node. The caller supplies it, since the caller knows
(one `PUSH` of a constant or of the local's handle); a sub-alias forwarded from
a `var` parameter inherits the parameter's word; every owning-handle store
through the parameter writes the word as the moved slot's link. Slot-holder
arguments may then be fields of `var` owning-aggregate parameters, which
resolves the §5.7/§5.12 contradiction and makes `push(n.next, v)` legal and
sound inside `attach` (S is a root nothing can reach during the call). Cost:
2 bytes of stack per such parameter, 1 to 3 bytes at each call site, no change
at store sites (`LD HL,(IX+n)` replaces `LD HL,0`), about 100 bytes of
compiler. The word also gives `id(n)` a meaning inside the routine when it is
nonzero (R13).

The alternative, forbidding owning-field stores and slot-holder arguments
through every `var` aggregate parameter, is sound but removes the point of
D30 for any record with a `next` field.

#### R2. A direct access through an owning local is resolved after a right side that moves the same local, and writes through `none`

**Where:** §5.3 "Order of overwrite: evaluates the right side first, then
resolves the destination"; §5.8 "Accessing or moving a non-optional owning
local that may have been moved is an error"; §5.4 "resolved after all its
operands have been evaluated".

The flow check sees the destination `x.value` before the right side, when `x`
certainly holds. The generated code evaluates the right side first:

```nucleus
sub eat(n as nodes) as u16              // frees n at its end
    return 0
end

sub crash()
    var x = new nodes(1, none)
    x.value = eat(move x)               // right side: x moved and freed, x = 0
end                                     // destination: x.value resolves to address 0 + 0:
                                        //   a write over the warm-boot jump at $0000
```

The same through an index: `x.kids[eat(move x)] = 1`; through a field of the
same local: `x.next = move x`; and inside a `select move y case some(n)` arm:
`n.value = eat(move n)`. The lease rule of §5.6 forbids exactly this shape for
`var` arguments and for `select` leases, but a plain direct access has no
such rule, and the flow state at the destination was taken before the move.
Claims 1 and 2 are violated.

**Fix.** Extend the same-statement rule to every direct access: an owning
local that is accessed directly anywhere in a statement (as a destination, a
lease argument, a `select` subject, or a path prefix) may not be moved or
overwritten in that statement, except that `x = ...` with no other direct use
of `x` remains an overwrite. The compiler already collects per-statement
roles for the lease rule; this adds one role. Cost: nothing at run time.

#### R3. The link write on a `none` handle writes into page zero

**Where:** §5.9 "Every store of an owning handle writes the moved slot's
link"; §5.2 "Fields, array elements and program variables start out zeroed,
which is `none`".

`none` is the handle 0. A move of an optional location that holds `none` is
legal and common (`head = move other`, `new nodes(v, "", move list, none)`).
If the link store is unconditional, it writes two bytes at address 0 plus the
link offset: the warm-boot jump, IOBYTE, or the BDOS jump at `$0005`,
depending on the offset.

```nucleus
var a as nodes?
var b as nodes?
sub z()
    a = move b                           // b is none: the link write lands at 0 + offset
end
```

**Fix.** The link write is conditional on the moved handle being non-`none`
(`LD A,H / OR L / JR Z`, 4 bytes, about 20 T-states), or it is folded into the
helper that stores through an identifier path and the inline form is used only
for non-optional sources. State it and put it in the cost table; the "6 to 8
bytes" for `move` must include it.

### Major

#### R4. The cascade's mark has no representation, and the obvious one is ambiguous

**Where:** §5.10 "a slot being freed is marked, and a child that is already
marked or already free is not pushed"; §5.9 the link; §5.1 the FIFO free list.

One word per slot is the owner link (0 for a root, else a slot address), the
free-list link (0 for the tail, else a slot address), the work-list link (a
slot address or a terminator), and now the mark. A live child owned by a slot
has link = a slot address; a free slot has link = a slot address or 0; a slot
on the work list has link = a slot address. The test "already marked or
already free" cannot be made on the link alone, and the generation does not
help: live and free slots share the same generation values (a slot freed at
generation 3 is reallocated at 3). The design's own cycle example in NU10
therefore still double-pushes.

**Fix.** The cascade knows the parent it is reading: push a child only when
the child's link equals the parent's address. A correctly owned live child
always satisfies it; a child already free, already pushed, or with a stale
link never does. One 16-bit compare per child, no mark, no constraint on the
free-list or work-list encodings. A root freed from a local or local aggregate
is freed without the test, which needs a second entry point or a flag. State
also that a withdrawn slot's fields are never read again and that `new`'s
field stores are initialising stores, not overwrites.

#### R5. Binding an owning parameter or a `select move` name is not stated to be a store, and the stale link it leaves makes the walk loop forever

**Where:** §5.9 "A move out of a field leaves the moved slot's link unchanged
until the next store"; D19 "passed to an owning parameter".

If `sink(move i.next)` and `select move i.next case some(n)` do not write the
moved slot's link, the slot is a root with a stale link that outlives the
statement. One lease-path store then closes a loop in the links while
ownership is still a tree:

```nucleus
var head as nodes?                       // head -> H -> O

sub g(x as nodes)                        // x = O, O.link stale = H
    select move head
    case some(hh)                        // hh = H, H.link = 0
        x.next = move hh                 // owning-parameter path: no walk; H.link = O
    case none
    end
    var ix = id(x)
    select ix.next
    case some(jh)                        // jh = H
        jh.next = new nodes(9, none)     // walk from H: H.link = O, O.link = H, H ... never 0
    case none
    end
end

sub m()
    var ih = id(head)
    select ih
    case some(i)
        g(move i.next)                   // O to g's parameter: is the link written?
    case none
    end
end
```

Ownership after the first store is `x` → O → H, a tree. The walk hangs. With
the weaker outcome, a stale link that reaches a live chain, the walk meets a
root that owns nothing below the destination and traps `ownership-cycle` on a
valid program.

**Fix.** One sentence in §5.9: binding an owning argument to a parameter,
binding `some(n)` in `select move`, and holding a fresh value in a temporary
are stores and write 0. Then no link is stale beyond its statement, the links
are a forest whenever the walk runs, and the walk is bounded by the depth of
the destination.

#### R6. Whether a ticket (`n as Node`) can bind a node is unstated; if it can, the lease rule must apply or there is a use after free

**Where:** §1.1 "Ticket: a read-only alias: an ordinary aggregate parameter";
§5.6 (rules stated only for `var`); D30; the whole-design review's E2
("a ticket `n as Node` could bind an owning local's slot read-only").

```nucleus
sub show(n as Node, k as u16)
    print(n.value)                       // k is 0: n is a freed slot
end

sub bad()
    var h = new nodes(1, none)
    show(h, eat(move h))                 // if a ticket binds a node: alias taken, then h freed
end
```

Under §4 ("An alias points into a pool slot only as a lease") the call is an
error, and every read-only routine over a node must take `var` or `id nodes`.
Either answer is sound; the document gives neither where a reader looks.

**Fix.** State in §5.6: a ticket never binds a node, or a ticket binding a
node is a lease and obeys the same statement rule. The second is the better
language (it is what E2 asked for) and costs nothing beyond the rule already
implemented for `var`.

#### R7. The prologue needs two constants the single pass does not have until the routine ends, and self-recursion is discovered after the prologue is emitted

**Where:** §7 "Every self-recursive and every forward-declared routine begins
with an activation-capacity check" with `need(R)`; D28 (locals at any
statement position); build-pipeline §6 (a routine buffer of 2K to 4K, and
"a routine too large for the buffer is written as ..." unbuffered).

Three facts the prologue encodes are known only at the routine's `end`:
`frame(R)` (D28 lets locals appear anywhere, and fresh temporaries add slots),
`need(R)` (the maximum over callees), and whether `R` calls itself. Nucleus had
the declaration prefix, so its frame was known before the first statement;
revision 4 removes it without saying how the prologue is filled. For a buffered
routine the compiler can patch two 16-bit immediates, and can patch a reserved
5-byte check into `NOP`s or a call. For an unbuffered routine it cannot.

**Fix.** Choose and state one of: (a) the prologue loads `frame` and `need`
from a 4-byte `rodata` word pair emitted after the routine and referenced by
address, which the format already allows (2 bytes and about 10 T-states per
routine more than an immediate); (b) every routine reserves the 5-byte check
and the compiler nops it when the routine turns out not to need it; or (c) a
self-recursive routine must be forward-declared. (a) with (c) is the smallest.
Also state whether `frame(R)` is the sum or the maximum of its blocks' locals;
either is a sound bound as long as the prologue allocates what `need` counts.

#### R8. `new` cannot construct a record whose field is an owning record or an array of owning handles

**Where:** §5.3 "`new` allocates a slot and initialises every field from its
arguments"; §5.2 "Owning types can't be copied: whole-record assignment and
by-value passing are errors".

```nucleus
record Tree
    key  as u16
    kids as trees?[4]
end
pool trees as Tree[32]

var t = new trees(1, ???)                 // no expression of type trees?[4] exists:
                                          //   a local array is an owning type and can't be passed by value
```

Every pool whose record contains an array of owning handles, or a nested
owning record, is unconstructible. The whole-design review's E7 asked for
omitted trailing fields; nothing was decided.

**Fix.** `new` accepts `none` for an owning aggregate field, meaning zeroed,
or allows trailing arguments to be omitted and zeroes the fields. Either costs
a few bytes of compiler.

### Minor

#### R9. Signed index types are unspecified against the bounds check

D31 says nothing about which integer types may index. If `i8` or `i16`
indexes are admitted and the compiler widens an `i8` by zero extension before
the unsigned compare, `-1` becomes 255 and indexes element 255 of a 256-element
array without a trap: not outside the object, but a silent wrong element.
State that indexes are `u8` or `u16`, or that a signed index is compared as
signed and negative traps `bounds`. String length assignment has the same
shape: `s.length = n` with `n` as `i8` is a mixed-sign error under D31, which
is right; say so.

#### R10. Temporaries in loop conditions and short-circuit operands

"The innermost enclosing statement" of a temporary in a `while` condition is
the loop. Say that a temporary made in a condition is freed when the condition
has been tested, and that a temporary's anonymous local is set to `none` at
statement entry so that an operand not evaluated under `and`/`or` leaves
nothing to free. Say whether a temporary in a handled call lives through the
`handle` body.

#### R11. `new?` and moved arguments on exhaustion

"The slot is reserved before the arguments are evaluated, so exhaustion never
consumes a moved argument" implies that `new?` evaluates no argument when the
pool is full. State it, together with the flow state afterwards: a
non-optional local moved into a `new?` argument is **may** after the
statement, on both arms of the following `select`.

#### R12. Owning parameters as lease and `select` subjects

§5.6 says "the caller's own owning local, or a temporary". A `nodes`
parameter is this activation's root and is equally safe to lease or `select`
on. Say "local or parameter".

#### R13. `id(n)` has no meaning inside `var n as Node`

A routine working on a leased node cannot make an identifier to it, so it
cannot set a child's `parent` link. With R1's owner word the compiler can
form the identifier when the word is nonzero and trap or reject when it is
zero. Say which.

#### R14. Passing a pool record's aggregate field

§5.4: an aggregate field "can't be passed by alias, except through a lease".
Whether `g(i.name)` is an error or copies into a hidden temporary of the
field's size in the frame is unstated. If the latter, it changes `frame(R)`
and must be in the cost table.

#### R15. Where the generation and link live

The walk and the cascade follow slot addresses across pools, so the two words
must sit at a fixed offset from the record address (for example the four bytes
before it). Say so; otherwise a cross-pool walk needs the child's pool.

#### R16. The identifier's slot-index check

`id()` is the only constructor, identifiers are never cast, and owning handles
and identifiers live in `bss`, so the index can never be out of range. The
check costs about 15 T-states per access. Keep it only if a reason is stated
(re-entry with `GO` does not supply one: identifiers have no initialisers).

#### R17. `from` on a lease, and the lease result in the caller's statement

`sub first(var n as Node) as Node from n` is admitted by §4 as written and is
sound: the result is used within the statement, and the same-statement rule
on `h` in `first(h).value = eat(move h)` already rejects the only attack.
Say that a lease may be a `from` parameter, that a result rooted in one is
subject to the lease's statement rule at the call, and that `from` may not name
a slot-holder.

#### R18. The walk's cost in the patterns

Every store through an identifier path walks to the root: inserting at
position *k* of a list walks *k* links (about 60 T-states each), appending to a
64-node list about 4,000 T-states on top of the insert. The cost table's
"about 60 per level" should be paired with "levels = depth of the destination",
and §8's list patterns should say that the tail insert pays it.

---

## 3. Implementability and costs

Compiler figures are estimates over the 12K Nucleus base; program figures are
per site.

| Rule | Single pass, bounded memory? | Compiler cost | Program cost |
| --- | --- | --- | --- |
| Owning-type closure; copy ban (§5.2) | Yes: one bit per record type, set when a field of an owning type is declared | about 60 bytes | none |
| Flow states (§5.8) | Yes: 2 bits per owning local per open block; meet at `end`, `else`, `case` | about 150 bytes, plus 1 byte per 4 owning locals per open block | none (moves store `none`) |
| Back-edge rule (§5.8) | Yes: snapshot the states at loop entry, compare at each back edge | about 80 bytes; one snapshot per open loop | none |
| Same-statement rule for leases (§5.6), extended by R2 | Yes: 3 role bits per owning local, cleared per statement, checked at the statement's end | about 150 bytes | none |
| `select` lease arm restrictions (§5.5) | Yes: one "leased" bit per owning local per open `select` | about 50 bytes | none |
| Slot-holder argument classification (§5.7) | Yes, syntactic; with R1's owner word, `var` parameters' fields are admitted | about 60 bytes | 1 to 3 bytes per call (R1) |
| Owner-link writes (§5.9) | Yes: the destination kind is known at every store except through `var` parameters (R1) | about 120 bytes | 4 to 8 bytes per owning store (with R3's test) |
| Cycle walk at identifier-path stores | Yes: a helper call | about 20 bytes | helper about 40 bytes; 60 T-states per level |
| Descriptors (§5.10) | Yes: emitted when the record type ends; a pool reference per entry resolved by the linker | about 200 bytes | 4 to 5 bytes per owning field or array, per owning type |
| Cascade (§5.10) with R4's test | Yes, runtime | — | helper about 130 bytes; 200 to 280 T-states per slot |
| Fresh temporaries (§5.3) | Yes: anonymous locals through the ordinary local mechanism | about 100 bytes | 2 bytes of frame per temporary; a free at each exit |
| Freeing at block exit, every exit path (§5.3, D28) | Yes, but the code is per exit path: a `return` inside three blocks with five owning locals emits five frees | about 100 bytes | about 6 bytes per owning local per exit path. Cheaper: set every owning local to `none` in the prologue and free all of them in one routine epilogue, which `return`, `fail` and the end share (6 bytes per owning local per routine) |
| `need(R)` and the prologue (§7, R7) | Only with the routine buffer, or with R7's `rodata` pair | 2 bytes per routine | 5 bytes per checked routine, plus 2 under R7(a) |
| Generation check (§5.11) | Runtime helper per pool | — | 6 bytes per site, about 28 per pool; 165 T-states |
| Local aggregate zeroing and string length (§5.13) | Yes, at the declaration | about 40 bytes | 13 bytes plus 21 T-states per byte zeroed |
| String zero-fill on length raise (D25) | Runtime helper | — | about 20 bytes; 21 T-states per exposed byte |
| Arrays of arrays in descriptors and paths (D32) | Yes: flatten to stride and count | in D32's 0.3K | none |
| `include` ordering for `need` (D33) | Yes: included files are compiled first, so their routines are defined before use | none extra | none |
| Identifier path, one check (§5.4) | Yes: Nucleus's staging already buffers operands | about 80 bytes | none |

Total for the memory-safety machinery: roughly 1.3K to 1.8K of compiler and
a routine table 4 bytes per routine larger than Nucleus's. Nothing here is out
of line with 24K. Two things need watching:

1. The per-exit-path freeing is a program-size cost, not a compiler cost, and
   it grows with nesting. The shared-epilogue form above should be the stated
   rule.
2. The prologue patch (R7) ties block-scoped locals to the routine buffer.
   A routine too large for the buffer must still get a correct frame and
   check; R7(a) is the clean answer.

The per-statement role set, the lease bits and the flow states are all
transient and bounded by the number of owning locals in scope, so a
published limit such as 32 owning locals per routine keeps every table under
32 bytes.

---

## 4. Expressiveness

Each program is written against revision 4 as it stands. A line marked
**rejected** is one the rules do not admit; a line marked **walk** pays the
cycle walk; **check** is one generation check. Two assumptions are made
throughout and should be stated in the design: an `id nodes` value may be
assigned to an `id nodes?` location, and a `select` whose every arm does not
fall through does not fall through (the Nucleus §13.7 summary extended to
`select`).

### 4.1 Singly linked list: insert in order and delete

```nucleus
record Node
    key  as u16
    next as nodes?
end
pool nodes as Node[64]
var head as nodes?

sub insert(k as u16)
    var n = new nodes(k, none)
    select head
    case some(f)                           // identifier: head is a program variable
        if k <= f.key                      // check
            n.next = move head             // direct: n is an owning local; no walk
            head = move n
            return
        end
    case none
        head = move n
        return
    end
    var p = id(head)                       // id nodes?
    while true
        select p
        case some(i)                       // check
            select i.next                  // check
            case some(q)
                if k <= q.key              // check
                    n.next = move i.next   // check; no walk: destination is n's slot
                    i.next = move n        // check; walk: i's position in the list
                    return
                end
                p = q
            case none
                i.next = move n            // check; walk: the whole list
                return
            end
        case none
            return
        end
    end
end

sub delete(k as u16) as boolean
    select head
    case some(f)
        if f.key = k                       // check
            head = move f.next             // check; the old head is freed
            return true
        end
    case none
        return false
    end
    var p = id(head)
    while true
        select p
        case some(i)
            select i.next                  // check
            case some(q)
                if q.key = k               // check
                    i.next = move q.next   // check; q freed; walk: i's position
                    return true
                end
                p = q
            case none
                return false
            end
        case none
            return false
        end
    end
end
```

Nothing is rejected. `n` is a non-optional local declared before a loop that
moves it: the back-edge rule holds because every arm that moves it returns.
An append is O(*k*) checks plus an O(*k*) walk; the walk doubles the cost of
building a list by appending, which §8 should say.

### 4.2 Binary tree: insertion and in-order traversal

```nucleus
record Tree
    key   as u16
    left  as trees?
    right as trees?
end
pool trees as Tree[128]
var root as trees?

sub insert(k as u16)
    var n = new trees(k, none, none)
    var p = id(root)
    while true
        select p
        case some(i)                       // check
            if k < i.key                   // check
                select i.left              // check
                case some(l)
                    p = l
                case none
                    i.left = move n        // check; walk: depth
                    return
                end
            else
                select i.right             // check
                case some(r)
                    p = r
                case none
                    i.right = move n       // check; walk: depth
                    return
                end
            end
        case none                          // only on the first iteration
            root = move n
            return
        end
    end
end

sub walk(t as id trees?)                   // self-recursive: capacity check in the prologue (R7)
    select t
    case some(i)
        walk(id(i.left))                   // check for the field read, then the call
        print(i.key)                       // check
        walk(id(i.right))                  // check
    case none
    end
end
```

Nothing is rejected, but two shapes a programmer will try first are:

```nucleus
sub insertAt(var slot as trees?, k as u16)   // recursive insert through a slot-holder
    select slot
    case some(i)
        if k < i.key
            insertAt(i.left, k)            // rejected: i.left is a field of a pool slot (§5.7)
        ...
```

and a recursive walk over leases, `sub walk(var t as Tree)` calling
`walk(t.left)`, which is **rejected** because a lease comes only from a local
or temporary, never from a field. Recursive tree code therefore goes through
identifiers and pays three checks per node; the iterative insert pays a walk
per level on top. An iterative traversal needs an explicit stack of
identifiers, `var stack as id trees?[32]`, whose bound is a program choice: a
degenerate 128-node tree traps `bounds` at depth 32, safely but wrongly.

### 4.3 Doubly linked list with unlink

```nucleus
record DNode
    key  as u16
    next as dnodes?
    prev as id dnodes?
end
pool dnodes as DNode[64]
var first as dnodes?
var last  as id dnodes?

sub pushFront(k as u16)
    var n = new dnodes(k, none, none)
    select first
    case some(f)
        f.prev = id(n)                     // check
    case none
        last = id(n)
    end
    n.next = move first                    // direct; no walk
    first = move n
end

sub unlink(x as id dnodes)                 // traps stale-handle if x is dead
    var nx = move x.next                   // check; nx: dnodes?, now a root
    select nx
    case some(n)                           // lease: direct access to the successor
        n.prev = x.prev                    // check for x.prev
    case none
        last = x.prev                      // check
    end
    select x.prev                          // check
    case some(p)
        p.next = move nx                   // check; x's slot freed; walk: p's position
    case none
        first = move nx                    // x's slot freed; no walk
    end
end
```

Nothing is rejected. The node is freed by overwriting the field that owns it;
every copy of `x` is stale afterwards and `select` on them gives `none`. The
walk at `p.next = move nx` is the position of `p`, so unlinking the tail of a
64-node list walks 63 links.

### 4.4 A fixed-size LRU cache on a pool

```nucleus
record Entry
    key   as u16
    value as u16
    next  as entries?
    prev  as id entries?
end
pool entries as Entry[16]                  // the capacity
var mru   as entries?                      // owns the chain, most recent first
var lru   as id entries?                   // least recent
var count as u8 = 0
var hit   as u16                           // the value found by get

sub detach(x as id entries) as entries?    // unlink x and hand it back owned
    var nx = move x.next                   // check
    select nx
    case some(n)                           // lease
        n.prev = x.prev                    // check
    case none
        lru = x.prev                       // check
    end
    select x.prev                          // check
    case some(p)
        var owned = move p.next            // check; x's slot, now a root
        p.next = move nx                   // check; nothing freed; walk: p's position
        return move owned
    case none
        var owned = move mru
        mru = move nx
        return move owned
    end
end

sub attachFront(e as entries)              // owning parameter
    e.prev = none                          // direct
    select mru
    case some(m)
        m.prev = id(e)                     // check
    case none
        lru = id(e)
    end
    e.next = move mru                      // direct; no walk
    mru = move e
end

sub get(k as u16) as boolean
    var p = id(mru)
    while true
        select p
        case some(i)                       // check
            if i.key = k                   // check
                hit = i.value              // check
                var e = detach(i)          // entries?
                select move e
                case some(o)
                    attachFront(move o)    // o: entries
                case none
                end
                return true
            end
            p = id(i.next)                 // check
        case none
            return false
        end
    end
end

sub put(k as u16, v as u16)
    if get(k)                              // a hit is now at the front
        select mru
        case some(m)
            m.value = v                    // check
        case none
        end
        return
    end
    if count = 16
        select lru
        case some(t)
            detach(t)                      // the result is a temporary: freed at the end
            count = count - 1              //   of this statement, which is the eviction
        case none
        end
    end
    attachFront(new entries(k, v, none, none))   // fresh value: no move
    count = count + 1
end
```

Nothing is rejected. Two lines cost more than they look:

- `attachFront(detach(i))` is **rejected** (`entries?` to `entries`), so a
  hit pays the three-line `select move` in `get`; a checked conversion would
  remove it.
- Evicting the tail walks the whole chain inside `detach` (the `p.next`
  store), 15 links at this size.

The design's own constraint that a `var list as entries?` subject binds an
identifier rather than a lease does not bite here, because the chain hangs
from a program variable.

---

## 5. Freeze verdict

**Not ready.** Three mechanisms are unsound as written and two more cannot be
implemented from the text. The fixes are small, but each changes a sentence
the compiler will be written from, so they must be in the document before it
is frozen.

What must change:

1. **R1.** Add the owner word to every `var` parameter of an owning type, or
   forbid owning-field stores and slot-holder arguments through `var`
   aggregate parameters. Resolve the §5.7/§5.12 contradiction the same way.
2. **R2.** Extend the same-statement rule to direct access through an owning
   local: a local accessed directly in a statement is not moved or overwritten
   in it.
3. **R3.** The link write is conditional on a non-`none` handle; cost it.
4. **R4.** Replace "marked" with the child-link-equals-parent test, and say
   how a root is freed without it.
5. **R5.** Parameter binding, `select move` binding and temporaries are stores
   that write link 0.
6. **R6.** Say whether a ticket binds a node, and if so that it is a lease.
7. **R7.** Say how the prologue gets `frame(R)`, `need(R)` and the
   self-recursion check in one pass, including for routines that do not fit
   the routine buffer.

With those seven in, the remaining findings (R8 to R18) are wording, costs
and one `new` convenience that can follow without reopening the safety
argument. After R1 and R5, the ownership links are a forest at every walk, the
walk is bounded by the destination's depth, and I found no program that frees
a leased or slot-held slot, forms an unchecked cycle, or reaches freed storage
through an identifier.
