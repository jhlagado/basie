# Second adversarial review of the memory-safety design

- Date: 2026-10-03
- Document: memory-safety.md revision 2, with cpm-target.md §4.1 and §10,
  object-format.md §6 (`LIMITS`), design-decisions.md D8, feature-inventory.md
  §3 and §4, and the Nucleus specification chapters 7, 9, 10, 12, 13, 14, 15.
- Method: every fix from the first review was assumed wrong until a program
  showed otherwise; every new mechanism was attacked with programs. Nothing
  here is a style comment.

Counts: 11 unsound, 8 major, 9 minor (28 new findings). Of the 32 first-review
findings, 20 are fixed, 10 partly fixed, 2 introduce a new problem.

**Notation** as in the first review: `deref(x)` for the record alias behind a
handle or identifier, `id(x)` for making an identifier, `h is some`, `retire h`.
Owned handles are addresses, `none` is 0, as the design now says.

---

## 1. Verdicts on the first review

| ID | Verdict | Note |
| --- | --- | --- |
| U1 | partly fixed | Handle-location provenance closes the `deref(h)` route. The identifier route is open: `return deref(i)` is staged across the routine's own scope-exit retirement (NU3). |
| U2 | fix introduces a new problem | The statement rule is adopted, but the pool set fed to it is wrong for every handle whose location is not a pool slot: `deref(root)`, `deref(h)`, `deref(tmp.head)` carry no pool (NU1). The rule also doesn't say whether built-in retirements count as calls (NU5), and the one reading that makes §8 compile is the unsound one. |
| U3 | partly fixed | `from` no longer names `own P` by-value parameters. The second half of the fix, that a result rooted in an `inout own? P` parameter carries pool `P`, was dropped: `peek(root)` has program provenance (NU2). |
| U4 | fixed | `need(R)` in the single pass, checks in forward and self-recursive prologues, `need(main)` in `LIMITS`. Verified below (§2.9); no counter-cycle found. |
| U5 | fixed | Closure over ownership. Variants are an owning type but the closure text says "record type"; see Nm5. |
| U6 | fix introduces a new problem | Saturation withdraws the slot but leaves its generation at `$FFFF`, so identifiers made in the slot's last life still match (NU8). |
| U7 | fixed | |
| U8 | partly fixed | Generations start at 1, but a never-used slot has generation 0 and so does the zero identifier: `deref` of a zero `id nodes` passes on slot 0 until slot 0 is first allocated (NU9). |
| U9 | fixed | |
| G1 | partly fixed | Provenance exists but conflates two facts, the root (for returnability) and the pool set (for `frees`). A handle deref uses the root for both (NU1). |
| G2 | partly fixed | Run-time `none` and the meet at joins are right. The use rule for non-optional `own` locals is too weak: only a *certainly* `none` deref is an error, so a *may be* `none` deref is accepted and dereferences address 0 (NU7). Moves in `while` conditions and `exit` states are unstated. |
| G3 | fixed | |
| G4 | partly fixed | Link outside the record, work list, descriptors. Descriptor entries carry only an offset, so a cross-pool child's pool, free list and own descriptor can't be found (NG2); variant payloads need tag-dispatched descriptors (NU11). |
| G5 | fixed | |
| G6 | fixed | |
| G7 | fixed | |
| G8 | fixed | Leases exist. They are attackable (NU6). |
| G9 | fixed | |
| G10 | fixed | See Nm3 for the string rule's edge. |
| G11 | fixed | |
| G12 | fixed | Pool-rooted `inout` results are not admitted by the wording (NG6). |
| m1 | fixed | |
| m2 | partly fixed | `own` is an address, `none` is 0. The `id` representation and the pool size limit it implies are still unstated (Nm1). |
| m3 | fixed | |
| m4 | partly fixed | Helper figures are in `need(R)`. The guard band is still a profile assertion for the IM1 BIOS; acceptable if stated as a trusted-base assumption (Nm4). |
| m5 | fixed | |
| m6 | fixed | |
| m7 | fixed | |
| m8 | fixed | |
| m9 | fixed | |
| m10 | fixed | |
| m11 | fixed | |

---

## 2. New findings

### Unsound

#### NU1. A handle dereference carries no pool set unless the handle's location is itself a pool slot

**Where:** §3.1 "Dereferencing an owned handle yields the provenance of the
handle's location"; §6.2.

The provenance table has one axis. The root of an alias decides whether it is
returnable; the pool set decides which calls may run while it is staged. For
`deref(h)` the design takes both from the handle's *location*, so a handle
held in a program variable, a local, a local aggregate's field or a parameter
location yields an alias with an empty pool set, and the statement rule never
fires. Four programs, each accepted by §6.2 as written:

```nucleus
var root as own? nodes

sub dropHead() as u16 frees nodes
    root = take deref(root).next
    return 0
end

sub a()
    deref(root).value = dropHead()      // 1: destination has program provenance;
end                                     //    dropHead frees its slot; store into a freed slot

sub sink(x as own nodes) frees nodes
end                                     // retires x at scope exit

sub b() fails
    var h as own nodes = new nodes(1, none) else fail
    show(deref(h), sink(h))             // 2: alias has local provenance; sink frees the slot
end

record Holder
    head as own? nodes
end

sub drop(x as inout Holder) frees nodes
    x.head = none
end

sub c() fails
    var tmp as Holder
    tmp.head = new nodes(1, none) else fail
    show(deref(tmp.head), drop(tmp))    // 3: local provenance; drop frees the slot;
end                                     //    drop's parameter set is "pools containing Holder", empty

sub d() fails
    var h as own nodes = new nodes(1, none) else fail
    deref(h).value = f(h)               // 4: f takes own nodes and retires it
end
```

In each, an alias into pool `nodes` is staged while a call with `frees nodes`
runs. Program 1 is the design's own idiom (`root` as a program variable, as in
§8) with one more call. Claim 2 is violated.

**Fix.** Provenance is a pair: a *root* in {program, local, parameter *k*,
pool} and a *pool set*. Field selection and indexing keep both. `deref` of an
identifier of pool `P` gives (pool, {P}). `deref` of a handle of pool `P` gives
(root of the handle's location, {P}). The return rule reads the root; the
statement rule reads the pool set. This makes `show(deref(h), f())` an error
when `f` frees `nodes` even though a local handle's slot cannot be reached by
`f`; that conservatism is cheap and avoids a second rule for "moved in the same
statement".

#### NU2. A result rooted in an `inout own? P` parameter loses pool `P` through `from`

**Where:** §3.1 "A result has the union of the provenances of the arguments
passed for its `from` parameters"; U3's fix, second half.

```nucleus
sub peek(link as inout own? nodes) as Node from link
    select link
    case some(h)
        return deref(h)              // provenance: parameter link
    case none
        ...
    end
end

sub peek2(link as inout own? nodes) as Node from link
    return peek(link)                // provenance: parameter link
end

sub reset() as u16 frees nodes
    root = none
    return 0
end

sub e()
    show(peek2(root), reset())       // result provenance = provenance of root = program
end                                  // show reads a freed slot
```

The deref happened inside `peek`, where the pool is known, but the signature
carries no pool set and the caller computes the result's provenance from the
argument, a program variable. Chains of `from` lose nothing further; the loss
is at the first hop.

**Fix.** Every aggregate result, with or without `from`, carries the
conservative result pool set: every pool whose record type contains the result
type, in union with the pool sets of the `from` arguments. The design already
states this set for results without `from`; apply it to all. A result of type
`Node` is then always in `{nodes}`.

#### NU3. A returned pool alias is staged across the routine's own scope-exit retirement

**Where:** §5.5 "at scope exit, for every owned local"; §6.2; §3.1 returning
aliases.

Scope exit is a retirement with effect `frees closure(P)` for every owned local
of pool `P`, and the design's propagation rule says so. But the statement rule
is checked only against calls, and the return value is formed before the
epilogue runs.

```nucleus
sub first() as Node frees nodes
    var h as own? nodes = take root
    var i as id? nodes = id(h)
    select live(i)
    case live(n)
        return n                     // pool provenance: returnable
    case stale
        return deref(fallback)
    end
end                                  // h retired here: n's slot is freed

sub g()
    var v as u16 = first().value     // reads a freed slot
end
```

No `frees` call runs while anything is staged in `g`; `first` declares
`frees nodes` honestly, and `g` passes it no alias. This is U1 by another road.
The same hole exists for a result rooted in a handle-location parameter whose
slot an owned local has come to own (`deref(x).next = take root` followed by
`return deref(link)` where `link` was `deref(root).next`).

**Fix.** At every `return` of an alias with pool set `S`, the epilogue's
retirements are checked against `S`: for each owned local whose pool closure
meets `S`, the flow state at the `return` must be *certainly `none`*, else the
return is an error. The compiler has that state; no new analysis is needed.

#### NU4. `select` bindings are aliases that live across statements without being staged, and the subject can be overwritten under them

**Where:** §3.3 `select live(i)`; feature-inventory §4.2 bindings; §6.2.

A `select` binding is an alias with a pool set that survives for the whole
case body, like an alias parameter, but nothing stages it: the statement rule
sees each statement of the body separately.

```nucleus
sub count(i as id? nodes) frees nodes
    select live(i)
    case live(n)                     // n: pools {nodes}
        dropAll()                    // frees nodes: its own statement, nothing staged
        total = total + n.value      // n dangles
    case stale
    end
end
```

Variant payload bindings have a second hole: the subject can be assigned a
different case inside the case body, overlaying the payload the binding
aliases:

```nucleus
variant Slot
    full(h as own? nodes, tag as u16)
    empty
end
var s as Slot

sub h1() frees nodes
    select s
    case full(link, t)               // link: alias to the own? field in s's payload
        s = empty                    // (NG3: should retire the payload) then overlays it
        deref(link).value = 1        // link's bytes are now the empty case's padding, or
    case empty                       //   the handle of a slot that s = empty retired
    end
end
```

With a payload whose other case holds scalars, writing through an aggregate
binding after a tag change is type confusion (claim 5) in program storage; with
an owned payload it is a use after free.

**Fix.** (1) A binding introduced by `select` is staged for the whole case
body, with its pool set, so every call and retirement inside the body is
checked against it; a binding over `live(i)` has `{P}`, a payload binding has
the subject's set. (2) Within a case body with any aggregate binding, the
subject's storage path is frozen: no assignment to it or to any prefix of it,
no `take` through it, and no call with `frees` meeting its pool set. The
compiler already tracks the counted-loop counter the same way.

#### NU5. Built-in retirements are not "calls", so retirements inside a routine holding handle-location or alias parameters are unchecked

**Where:** §6.2 "no call whose effect includes a pool in *S*"; §5.5; §6.4.

The rule names calls. Overwrite retirement, explicit `retire`, and the lease
rule "can't retire `h` without `frees nodes`" show the design treats
retirements as effects of the routine, but not as events the staged set is
checked against. Three programs:

```nucleus
sub f(a as inout own? nodes) frees nodes
    root = none                      // overwrite retirement, not a call
    a = new nodes(1, none) else fail // a's location may be inside the list just freed
end
// caller: f(deref(i).next) where i identifies a node in root's list:
// the store writes a handle into a freed slot (leak now, corruption when reallocated);
// `take a` instead of the store yields a freed handle (double free)

sub both(a as inout own nodes, b as inout own nodes) frees nodes
    a = new nodes(0, none) else fail // retires a's old slot
    b.value = 1                      // b is the same location: writes a freed slot
end
// caller: both(h, h)

sub f3(a as inout own? nodes, x as own nodes) frees nodes
    retire x                         // x's subtree contains a's location
    a = none                         // writes into a freed slot
end
// caller: f3(deref(h).next, h)   -- argument 1 is formed before h is moved
```

Inside each callee, parameter `a` (or `b`) is "staged for the whole call" and
its conservative set contains `nodes`, but no *call* with `frees nodes` is made.

The opposite reading, that a retirement is a call, rejects the design's own
`clear` (§6.1: `list = none` with `list` staged) and `removeAll` (§8, see
Section 3). So the rule as written is either unsound or rejects §8.

**Fix.** Every retirement, whether by call, explicit `retire`, overwrite or
scope exit, is checked against the staged set with the retired pool closure,
with exactly one exemption: an overwrite's retirement is not checked against
the destination path of that same assignment (the path's slots are ancestors
of the retired subtree in the ownership forest, which NU10's fix makes an
invariant). At a `return` the staged set is the result alias (NU3). This
admits `clear`, `push`, `bump` and both `removeAll` lines, and rejects the
three programs above. See Section 3 for the consequence on routines that take
a list by `inout own? P`.

#### NU6. A lease or handle-location parameter can be moved from or retired, leaving the caller's non-optional `own` local holding `none`

**Where:** §6.4; §5.3; §5.4 "flow states exist only for owned locals".

`h as inout own nodes` is a location of type `own nodes`. Nothing forbids
moving its content: an owned value "is moved when it is ... passed as an
argument of type `own P`", and the flow check does not cover the location
because it is not a local.

```nucleus
sub steal(h as inout own nodes) frees nodes
    sink(h)                          // moves: stores none into the caller's local
end

sub k() fails
    var h as own nodes = new nodes(1, none) else fail
    steal(h)
    deref(h).value = 2               // caller's flow state says h holds; h is 0: write to page zero
end
```

`retire h` inside the callee (with `frees nodes`) does the same. Passing `h` on
as an `own nodes` argument is the same move.

**Fix.** An `inout own P` location admits only dereference and
overwrite-with-replacement (`h = v`, which retires the old value under
`frees`). `take`, move and `retire` through it are errors. The same restriction
is not needed for `inout own? P`, whose `none` the caller must test.

#### NU7. A non-optional `own` local that *may* have been moved can be dereferenced, and a value that may be `none` can reach an `own P` parameter

**Where:** §5.4 "a use after move when a local that is certainly `none` is
dereferenced or moved, and a move from a non-optional local that may already
have been moved"; §5.3.

The deref case is only an error when the local is *certainly* `none`:

```nucleus
sub m(c as boolean) fails
    var h as own nodes = new nodes(1, none) else fail
    if c
        sink(h)                      // h = none at run time
    end
    deref(h).value = 1               // h may be none: not listed as an error; writes to address 0
end
```

Address 0 under CP/M is the warm-boot jump. Three more routes to the same
state:

- a move in a `while` *condition*: `while consume(h) ... end` moves `h` on the
  first test and passes `none` on the second; the loop rule speaks only of the
  body;
- `exit` after a move: the state after the loop is never stated to include the
  `exit` paths, so a single-pass compiler that assumes the entry state after
  the loop accepts a deref;
- `sink(take root)`: `take` yields an `own?` value (`root` may be `none`) and
  the design does not say it cannot bind to an `own P` parameter. Inside
  `sink`, `x` is non-optional and dereferenced without a test.

**Fix.** For non-optional `own` locals and parameters, every use (deref, move,
pass, return) requires the state *certainly holds*; the state after a loop is
the meet of the condition-false state and every `exit` state; a `while`
condition is part of the loop for the move rule. An `own P` argument must be a
certainly-holding `own P` local or parameter, a `new`, or an `own P` result;
`take` has type `own? P` and binds only to `own? P`. Provide the conversion as
a `select` whose `some` case *moves* into a fresh `own P` local (`select take
root case some(h) ...`), since the feature inventory excludes binding by move.

#### NU8. A withdrawn slot keeps generation `$FFFF`, so identifiers made in its last life still pass

**Where:** §5.6 "when advancing would wrap past `$FFFF`, the slot is withdrawn
... instead of being put on the free list".

The slot's last allocation was at generation `$FFFF`. Every identifier made
during that life holds `$FFFF`. Retirement withdraws the slot without
advancing, so those identifiers match forever:

```nucleus
// slot s has generation $FFFF (after 65,534 reuses under FIFO)
var h as own nodes = new nodes(1, none) else fail      // takes s eventually
var i as id nodes = id(h)
retire h                             // cascade retires deref(h).next; s withdrawn, gen stays $FFFF
var n as u16 = deref(i).value        // passes: $FFFF = $FFFF
deref(i).next = take other           // writes a handle into a dead slot: leaked
var c as own? nodes = take deref(i).next   // if retirement did not null the field: a freed handle,
                                     // reallocated by then: double ownership
```

The slot is never reallocated, but its owned fields were retired, so reading
them through the stale alias reaches slots that are.

**Fix.** Allocate only slots with generation below `$FFFF`; retirement always
advances; a slot at `$FFFF` is withdrawn. Identifiers then hold `1`..`$FFFE`
and `$FFFF` matches none. Cost: nothing extra, the compare moves from retire
to the free-list pop. State also that retirement stores `none` into each
owned field as it reads it, so a dead slot never holds a freed handle.

#### NU9. The zero identifier matches a never-used slot 0

**Where:** §3.3 "The zero identifier holds generation 0, which no allocated
slot ever has"; §5.2.

Allocated slots have generation ≥ 1. Slot 0 before its first allocation has
generation 0, as does a zeroed `id nodes` program variable:

```nucleus
var cursor as id nodes               // bss: slot 0, generation 0

sub main() fails
    deref(cursor).next = new nodes(5, none) else fail   // passes: 0 = 0; stores into a slot
                                                        // that new will hand out and reinitialise
end                                                     // the new node is leaked
```

A read is of storage the program never established (claim 4); the write leaks
the moved handle. `id? nodes` has the same bytes for `none`, so `live(i)` and
`deref` must test `none` before comparing, or `none` is "live" on slot 0.

**Fix.** The generation compare rejects 0 (one extra test in the per-pool
helper), and `live`/`deref` of `id?` test `none` first. Additionally forbid
`id P` (non-optional) program variables and fields, which have no sensible
zero value; locals of type `id P` need an initialiser.

#### NU10. An ownership cycle can be built by a move, and retirement of a cycle frees a slot repeatedly

**Where:** §5.3, §5.5 "No recursion", claim 7.

A handle can be moved into a field of the slot it owns, or into a field of a
slot in its own subtree:

```nucleus
sub cyc() fails
    var h as own nodes = new nodes(1, none) else fail
    deref(h).next = h                // destination formed, then h moved: S.next = S
end                                  // epilogue retires h = none; S is unreachable: a leak

sub cyc2()
    deref(root).next = take root     // S.next = S, root = none: the whole list is unreachable
end
```

A leak violates claim 7 but is contained. It becomes a double free the moment
the cycle is retired, which needs only an identifier to it:

```nucleus
var i as id nodes = id(h)            // before the move in cyc
...
deref(i).next = none                 // retires S.next = S: work list pops S, reads S.next = S,
                                     // pushes S, frees S; pops S again, frees S again ...
```

Whether the cascade loops forever or stops, S is appended to the FIFO twice,
is handed out to two owners, and both retire it (claim 3). Static prevention
is impossible when the moved value and the destination are reached through
identifiers.

**Fix.** Make retirement idempotent per slot with the link field as a mark:
`new` clears the slot's link; a live slot's link is 0; pushing a child onto
the work list is skipped when its link is nonzero (already queued or already
free); a popped slot keeps a nonzero link while its fields are read. Cost: one
2-byte store in `new`, one 2-byte test per child. State claim 7 as "no owned
storage is leaked at scope exit or on overwrite; a program can still build an
unreachable cycle". The exemption in NU5's fix relies on ownership being a
forest; with cycles tolerated rather than prevented, the exemption must be
restated as "the destination path is not retired by the overwrite unless the
program built a cycle, in which case the mark prevents a double free and the
dangling destination write is a write into a free slot's record, which `new`
reinitialises". That is a weaker claim; if it is unacceptable, cycles must be
prevented at run time by walking the moved value's subtree at every store into
a pool field, which is not affordable.

#### NU11. Retirement descriptors are not tag-aware, so a variant with an owned payload in one case is retired as that case whatever its tag

**Where:** §5.5 descriptors; feature-inventory §4.2 representation ("a tag byte
followed by the largest variant's fields"); §5.7.

```nucleus
variant Shape
    circle(h as own? nodes)          // payload byte 1..2: a handle
    rect(w as u16, hgt as u16)       // payload byte 1..2: w
end
record Cell
    shape as Shape
end
pool cells as Cell[8]
```

The descriptor for `Cell` lists "the offset of each owned field": offset 1.
Retiring a `Cell` whose shape is `rect(300, 7)` reads 300 as a handle, pushes
address 300 onto the work list, and frees whatever is there (claim 3, claim
5). The closure computation has the same shape: it must include pools owned
through any case.

**Fix.** A descriptor entry for a variant field holds the tag offset and one
sub-descriptor per case; the runtime dispatches on the tag. Say so and cost it
(about 2 bytes per case plus the per-field cost).

### Major gaps

#### NG1. Owned results can be discarded or dereferenced as temporaries, which leaks

**Where:** §5.3; Nucleus §13.3 ("an infallible result-bearing routine may be
used as ... a call statement that discards the result").

`make()` as a statement, where `make` returns `own nodes`, discards an owned
value: nobody retires it. `show(deref(make()))` dereferences an owned
temporary that no location holds; after the statement it is gone. Either form
leaks (claim 7).

**Fix.** An owned result must be consumed by a move (assignment, argument,
`return`, `new` argument) in the statement that produces it. Discarding it and
dereferencing it in place are errors. If dereferencing a temporary is wanted,
define the temporary as an anonymous owned local of the statement, retired at
its end, and give the routine `frees`.

#### NG2. Descriptor entries cannot identify a cross-pool child's pool, and the tree-shaking rule drops descriptors reached only through cascades

**Where:** §5.5 "the offset of each owned field ... about 2 bytes per field";
"The linker keeps only the descriptors of types that live code retires".

A `Node` owning a `Leaf` in another pool: the work list holds the leaf's
address, from which the runtime can find the generation and link (fixed
offsets from the record), but not the pool's free-list head and tail, nor the
`Leaf` descriptor. An offset alone is not enough; each entry needs the child
pool (2 bytes), or the pool must be found by address-range search over a pool
table. And `Leaf` is never retired by live code directly, only by the cascade
from `Node`; "types that live code retires" drops its descriptor unless
descriptors are blobs whose entries are references, so that `Node`'s
descriptor references `leaves`'s pool record, which references `Leaf`'s
descriptor.

**Fix.** Define the descriptor as: per owned field, offset and child pool
reference (4 bytes); per array, offset, stride, count and pool reference
(5 bytes). A pool record in `bss`/`rodata` holds the free-list head, tail,
high-water mark and a reference to the record descriptor. Say that these are
blobs with references so the linker keeps them by reachability, not by "what
live code retires".

#### NG3. Overwriting or constructing an owning variant is undefined

**Where:** §5.5 "on overwrite, when a value is stored into an `own?` location";
§5.7; feature-inventory §4.4.

A variant location is not an `own?` location, so `s = empty` over a
`full(h, t)` retires nothing (leak), and `s = full(take root, 3)` is a
whole-value assignment of an owning type, which §5.7 forbids. There is no way
to put an owned value into a variant, and no way to take one out without
leaking.

**Fix.** Define constructor assignment to a variant location as: evaluate the
destination, evaluate the constructor's arguments (moves), retire the old
payload through the tag-dispatched descriptor (NU11), store. It requires
`frees` of the closure of every case. Define `take` on an owned payload field
through an `inout` subject binding.

#### NG4. Local aggregates with `own?` fields: retirement at scope exit, the `frees` requirement, and `take` through tickets are unstated

**Where:** §5.5 "for every owned local"; §3.1 modes; D8.

`var tmp as Holder` with `tmp.head as own? nodes` is a local that owns. "Every
owned local" presumably includes it, so the epilogue must walk it by
descriptor and the routine must declare `frees nodes`; neither is said. Also
unsaid: `take x.head` and `x.head = none` through a read-only ticket `x as
Holder` must be errors, since both write the location. Nucleus lost read-only
through aliases; Basie has modes and must enforce them for these two
operations or U7's reasoning fails for tickets.

**Fix.** State all three.

#### NG5. The ambiguity in NU5 is settled by the design's own examples in the unsound direction, and the sound direction needs a parameter annotation to keep lists-by-parameter writable

See NU5 for the hole and Section 3 for the practicality cost. Recorded here
because the fix is a language change: a handle-location parameter can be
declared as not pool-resident (`list as inout own? nodes in storage`, syntax
open), checked at every call site (the argument's root must be program or
local), and then has an empty pool set inside the callee. Without it,
`removeAll(list as inout own? nodes, v)` is rejected under the sound rule.

#### NG6. No `inout` result can be rooted in a pool slot reached by identifier

**Where:** §3.1 "A result alias is read-only unless declared `inout`, which is
allowed only when the result is rooted in an `inout` parameter or a program
variable."

`sub at(i as id nodes) as inout Node` returning `deref(i)` has pool
provenance, which is neither. No routine can hand a caller a writable alias
into a pool slot; every pool mutation must be written inline. Likewise,
`select` bindings are "read-only unless the subject is passed `inout`", which
makes every binding over a program variable or an identifier dereference
read-only.

**Fix.** Admit pool-rooted `inout` results and `inout` bindings over writable
subjects; the mode is about tickets and constants, not about pools.

#### NG7. Dereferencing an `own?` or `id?` location directly is forbidden by §4 and used throughout §8

**Where:** §4 "Null dereference: `own?` and `id?` must be tested with `select`
before use, compile time"; §8 `deref(root)`, `deref(deref(p).next)`, `id(root)`.

`deref(root)` where `root` is `own? nodes`, and `id(root)` yielding `id nodes`
rather than `id? nodes`, appear on five lines of `removeAll`. The `is some`
test before `deref(root)` in the `while` condition cannot establish anything
for a program variable under §5.4 ("every other `own?` location is treated as
possibly holding a value"), and `select` is a statement, so `is some` cannot
be `select` sugar inside a condition.

**Fix.** One of: (a) a checked dereference of `own?`/`id?` that traps
`none-handle`, and `id()` of an `own?` yielding `id?`; or (b) a narrow
flow-typing rule: within one statement or condition, after `x is some` on a
path with no intervening call, move, overwrite or `and`/`or` right operand
that moves, `x` may be dereferenced. (b) keeps the compile-time claim; (a) is
what §8 is actually written against. Choose and rewrite §8.

#### NG8. The design's flow check cannot know, at the loop top, the state at the back edges, and the stated rule leaves `own?` locals and `continue` undefined

**Where:** §5.4 "Loops are checked with the state at the loop top assumed to be
the meet of the entry and every back edge".

A single pass has not seen the body at the loop top. The design's own
resolution (an error if a non-optional local is moved and not reassigned
before the back edge) is a back-edge check, not a loop-top meet; `continue` is
a back edge and must be checked too. For `own?` locals the loop-top state is
only a diagnostic matter since a deref needs `select`, but the text should say
that. Fold into NU7's fix.

### Minor

#### Nm1. The `id` representation and the pool size limit are unstated

The cost table assumes "6 at the site, about 28 per pool in a helper" and
4 bytes of pool overhead per slot. Whether an identifier is 3 bytes (8-bit
index) or 4, and therefore whether a pool may exceed 256 slots, is not said.
Identifier slot indices need no bounds check only because `id()` is the sole
constructor and `id` values cannot be cast; state that invariant beside the
representation.

#### Nm2. Descriptor cost

"About 2 bytes per field and 3 per array" becomes 4 and 5 with the pool
reference (NG2).

#### Nm3. Length-only zeroing of local strings is sound only if no operation raises the length without writing the bytes

Whole-string assignment copies the capacity, including bytes beyond the
source's length, into a destination whose length becomes the source's; still
unobservable. Comparison is by length and indexed bytes. A service that
writes a string to disk must write only `length` bytes, which belongs in the
trusted-base clause. Append writes before it raises the length. A length
assignment (`s.length = n`) would expose stale frame bytes; say it is absent,
or that it zero-fills.

#### Nm4. The guard band

The reporter's BDOS entry is derivable; an IM1 BIOS's push depth is not. Say
the guard covers a stated maximum interrupt push depth as a trusted-base
assumption.

#### Nm5. The conservative pool set: say "contains or is", include variants, and define it for `string[]`

"Every pool whose record type contains its type" should read "is or contains",
should walk variant cases, and for `string[]` should match every string
capacity. The closure in §6.1 says "record type" and must include variants and
arrays of variants.

#### Nm6. `is some` cannot be `select` sugar in a condition

`select` is a statement; `while root is some and ...` needs `is some` to be an
operator on `own?`/`id?` locations. Say so.

#### Nm7. Does a routine whose owned locals are moved on every path need `frees`?

The epilogue "emits the same short epilogue whatever the flow state", so the
retire code is present. If its presence requires `frees P`, no routine with a
`Node` alias parameter may hold an `own nodes` temporary even to move it on.
Say that `frees` is required only when some exit's state is not certainly
`none`.

#### Nm8. `id()` is used but never defined in revision 2

Define it for `own P`, `own? P` (yielding `id? P`), and handle-location
parameters.

#### Nm9. `new` reserves before evaluating arguments: say what happens to the reserved slot if an argument traps

Nothing, since a trap ends the program; but say it, and say the reservation is
not visible to an argument that calls `new` on the same pool.

---

## 3. Practicality

### 3.1 `removeAll` against the rules as written

```nucleus
sub removeAll(v as u16) frees nodes
    while root is some and deref(root).value = v        // L1
        root = take deref(root).next                    // L2
    end
    if root is none                                     // L3
        return
    end
    var p as id nodes = id(root)                        // L4
    while deref(p).next is some                         // L5
        if deref(deref(p).next).value = v               // L6
            deref(p).next = take deref(deref(p).next).next   // L7
        else
            p = id(deref(p).next)                       // L8
        end
    end
end
```

- **L1.** `root is some` as an operand of `and`: `select` is not an expression
  (Nm6). `deref(root)` on an `own?` program variable: rejected by §4's
  compile-time null rule, since no flow state exists for `root` (NG7).
- **L2.** `deref(root)` again (NG7). Otherwise correct under the order rule:
  destination `root` (not an alias), right side takes the second node, old head
  retired, stored. Under NU5's fix the retirement is checked against the staged
  set, which is empty: admitted.
- **L4.** `id(root)` of an `own?` has type `id? nodes`, not `id nodes` (Nm8,
  NG7).
- **L5, L6.** `deref(deref(p).next)` dereferences an `own?` field (NG7).
- **L7.** Destination `deref(p).next` has pool set `{nodes}` and is staged
  until the store. The overwrite retirement of its old value runs before the
  store with effect `frees nodes`. If a retirement counts as a call (the only
  reading that makes NU5's programs rejected), **this line violates the
  design's own rule.** If it does not count, NU5 holds. The design's example and
  its rule cannot both stand as written.
- **L8.** `id(deref(p).next)` is `id? nodes` assigned to `id nodes` (Nm8).

So as written the example is rejected on L1, L2, L4, L5, L6, L8 by NG7/Nm8, and
L7 is rejected or unsound depending on the reading of §6.2.

### 3.2 A precise rule that admits L7 soundly

> Every retirement (a call with effect `frees S`, an explicit `retire`, an
> overwrite of an `own?` or owning-variant location, or scope exit at a
> `return` that carries an alias) is checked against the union of the pool sets
> of every staged alias: alias parameters, `select` bindings of enclosing
> cases, and the aliases of the current statement. An overwrite's retirement is
> not checked against the destination path of that assignment. At a `return`,
> the staged set is the returned alias.

Why the exemption is sound: at the moment the overwrite retires, the right
side has been consumed (its value is a handle, not an alias), so the only
aliases of the statement still staged are the destination path's. The retired
storage is the ownership subtree of the destination field's old content. The
destination path's slots are the field's container and the container's
ancestors on the path, and in an ownership forest no slot is in its own
descendant's subtree. NU10 makes the forest property hold or makes its
violation harmless.

What this rule costs: a routine that holds a handle-location parameter into
pool `P` (`list as inout own? nodes`) cannot overwrite any other `own? nodes`
location, since the parameter's location may be inside the retired subtree.
`removeAll` written over a *parameter* rather than the program variable `root`
is therefore rejected at L7. That rejection is correct in general
(`removeAll(deref(i).next, v)` with `i` naming the victim is a dangling
`list`), and NG5's annotation recovers the common case where the location is a
program variable or local.

### 3.3 The other §8 structures

- **Doubly linked list** (`unlink(x as id nodes)`): `deref(nx)` on a local
  `own?` needs `select` (NG7); otherwise admitted under the rule above, since
  `x` is an identifier, not a staged alias.
- **Trees with parent links:** `deref(p).left = new trees(...)` is admitted;
  `deref(p).left = none` is admitted. Rotations that hold three subtrees in
  `own?` locals are admitted.
- **Graphs:** `owners[k] = none` is admitted; the sweep with `select live(e)`
  is admitted only after NU4's fix stages `e`'s binding, which then forbids
  calling anything that frees `vertices` inside the case; a sweep that drops
  edges does not free vertices, so it compiles.
- **Leases:** `bump(h)` is admitted. Any routine with two leases on the same
  pool and `frees` of it is rejected (NU5), which is right.

---

## 4. Questions for the designer

1. Is a retirement a "call" for the purposes of §6.2? The two answers reject
   §8 and admit NU5 respectively; Section 3.2 offers the rule that does neither.
2. Is `deref` of an `own?`/`id?` location meant to be a checked run-time
   operation (trap on `none`), or must every such dereference go through
   `select`? §4 says the latter; §8 is written against the former (NG7).
3. What is the type of `take x`, and how does an `own? P` value become an
   `own P` argument or local (NU7)?
4. Is a `select` binding over an owned payload an alias to the location, a
   moved handle, or forbidden? The feature inventory excludes binding by move
   and the memory-safety design uses `some(h)` without saying (NU4, NG3).
5. Should a handle-location parameter be annotatable as not pool-resident
   (NG5), or is "lists are reached through program variables" the intended
   style?
6. Is the leak of an unreachable ownership cycle acceptable under claim 7
   (NU10), or must cycles be prevented, at the cost of a subtree walk on every
   store into a pool field?
7. Should non-optional `id P` be allowed anywhere its zero value can be
   observed (program variables, fields, uninitialised locals) (NU9)?
8. Is `inout` meant to be expressible for results and bindings rooted in pool
   slots (NG6)? If not, how is a pool record mutated by a helper routine other
   than through a lease?
9. Are descriptors blobs with references, so the linker keeps them by
   reachability (NG2)? If they are one table, what keeps a cascade-only type's
   descriptor alive?
10. Can a runtime helper ever call program code? The stack argument in §7
    assumes not; routine values (§10) will make it false, and the design should
    say now that a routine value's target is counted as a forward call in
    `need` and checked in its own prologue.
