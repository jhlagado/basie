# Adversarial review of the memory-safety design

- Date: 2026-10-03
- Document: memory-safety.md (draft, "not yet reviewed"), with
  design-decisions.md D1, D3–D8, O1–O5; cpm-target.md §4.1 and §10;
  philosophy.md; the Nucleus specification chapters 7, 13, 14 and 15;
  object-format.md and linker.md for the stack bound.
- Method: each guarantee in memory-safety §1 and each rule in §§3–7 was
  attacked with concrete programs. Every finding below is a program or an
  operation sequence that breaks a stated guarantee, or a rule that cannot be
  implemented as written. Nothing here is a style comment.

Counts: 9 unsound, 12 major gaps, 11 minor issues (32 findings).

**Notation.** The design leaves syntax open (§11.3). Examples use `deref(h)`
for the record alias behind an owned handle or identifier, `id(h)` to make an
identifier from a handle or an `own?` field, `h is none` / `h is some` for the
optional test, and `retire h`. `string[]` is Nucleus's open string. Nothing
turns on the spelling.

---

## 1. Findings

### Unsound

#### U1. A returned alias may point into a slot owned by a local handle

**Where:** §4 row "Alias to a dead local"; §3.1; D8.

D8's rule is phrased in terms of roots: a returned alias may point into a
global or a `from` parameter, never into the routine's own local. A pool is a
top-level declaration, so an alias into a pool slot is rooted in a global. But
the slot's lifetime is that of its owning handle, which can be a local.

```nucleus
pool nodes as Node[64]

sub fresh(v as u16) as Node fails
    var h as own Node = new nodes(v, none) else fail
    return deref(h)             // root is pool nodes: a global, so D8 admits it
end                             // h not moved: retired here, slot freed

sub main() fails
    var n as u16
    n = fresh(7).value          // reads a freed slot, or a slot new has reused
end
```

No `frees` is involved at the caller: `fresh` retires its own local at scope
exit, and the design says that counts as retiring (§5.4), so `fresh` carries
`frees nodes`; but the caller passes no alias into `fresh`, so the aliasing
rule in §6.2 is satisfied. Claim 2 is violated.

**Fix.** An alias obtained by dereferencing a handle is rooted in the *handle's
location*, not in the pool. Then `deref(h)` for a local `h` is rooted in a
local and D8 rejects the return. For a parameter handle (`h as own T`, see U3)
or an `inout own? T` parameter, the alias is rooted in that parameter and may
be returned only under `from`, and only with the further condition in U3. For
an identifier, the alias is rooted in the pool (the identifier does not own the
slot), and the caller is protected by the generation check at the next
dereference and by the `frees` rule as repaired in U2. Cost: one provenance
field per alias (see G1).

#### U2. A pool alias staged inside one statement is live across a `frees` call in the same statement

**Where:** §6.2, "while an alias into a slot of `P` is live as an argument, the
call it is passed to must not have the effect `frees P`"; §3.1, "a routine
result the caller uses at once"; Nucleus §7.9 and §13.6 (staging).

The rule constrains only the call an alias is *passed to*. Nucleus evaluates
arguments left to right and keeps an aggregate carrier staged across later
argument evaluation (§13.6), and an assignment evaluates its destination path
before its right side (§15.4). Three programs:

```nucleus
var root as own? Node

sub reset() frees nodes
    root = none                 // retires the whole list
end

sub show(n as Node, k as u16)   // no frees
end

sub a(i as id Node) frees nodes
    show(deref(i), reset_k())   // 1: alias staged; reset_k calls reset(); show reads a freed slot
end

sub b(i as id Node) frees nodes
    deref(i).value = count()    // 2: destination path formed, then count() frees, then the store
end

sub c(i as id Node) frees nodes
    deref(i).items[next()] = 1  // 3: same, through an index expression
end
```

In each, the generation check ran before the freeing call, and the alias it
produced is used after it. `show` has no `frees`, so §6.2 as written accepts
program 1 outright. Programs 2 and 3 have no call the alias is "passed to" at
all. Claim 2 is violated.

The same hole exists with owned handles and `take`:

```nucleus
sub d(h as own Node) frees nodes
    show(deref(h), sink(take h))    // sink retires h; show gets the freed slot
end
```

**Fix.** Replace the aliasing rule with a statement-level rule: *no call with
effect `frees P` may be evaluated while any carrier of an alias into `P` is
staged.* Concretely, in the compiler's expression evaluation, every staged
aggregate carrier carries a pool set (G1); emitting a call whose effect
intersects the union of the staged sets is an error. This covers arguments,
assignment destinations, index expressions and field suffixes in one rule.
Cost: a pool bitset on each staged carrier (1–2 bytes each) and one `and`
per call. It rejects `deref(i).value = count()` when `count` frees; the
program writes `var c = count()` first, which is the right answer.

#### U3. `from` on an owned parameter returns an alias into a slot the callee retires

**Where:** D8; §5.3 (passing an argument of type `own T` is a move).

D8 says the result lives "exactly as long as the arguments passed for the
`from` parameters". For an owned parameter the argument is moved in, and the
callee owns and retires it at return unless it moves it on.

```nucleus
sub inspect(h as own Node) as Node from h
    return deref(h)             // rooted in parameter h, listed in from
end                             // h retired here

sub main() fails
    var h as own Node = new nodes(1, none) else fail
    var v as u16 = inspect(take h).value    // freed slot
end
```

The `from` rule is satisfied, no `frees` call is made with an alias as an
argument, and the caller cannot see that `inspect` retired its parameter.

**Fix.** `from` may name only alias parameters (ticket, lease, `inout own? T`
and `inout own T` locations), never a by-value `own T` parameter. A result
rooted in an `inout own? T` parameter must additionally be treated as a pool
alias of that pool for the purposes of U2 at the call site, because the slot
can be retired by overwriting the location after the call returns:

```nucleus
sub peek(link as inout own? Node) as Node from link
    return deref(link)
end
root_use(peek(root), reset())   // U2 again unless the result carries pool provenance
```

#### U4. Claim 6 is false as the stack rules stand: the call-site check cannot be emitted, and the acyclic part is unbounded

**Where:** §7.1, §7.2; cpm-target §4.1; object-format §6 `LIMITS`; linker
§6.3.

Three separate defects:

1. §7.1 puts the activation-capacity check "at every such call" and has it
   subtract "the callee's frame". At a call to a forward-declared routine
   whose body has not been seen, the callee's frame size is unknown; it is not
   in the signature, and D1 forbids fixups that fill in semantic facts. The
   rule cannot be implemented as written. cpm-target §4.1 contradicts it and
   puts the check in the callee's prologue, which is implementable.

2. cpm-target §4.1 checks only routines "whose activation frame is larger than
   a profile threshold" and routines that "can recurse". A chain of routines
   each just under the threshold overflows with no check at all:

   ```nucleus
   sub l1()  var b as u8[500]  ... end    // 500 < threshold, no check
   sub l2()  var b as u8[500]  l1() end
   ...
   sub l40() var b as u8[500]  l39() end  // 20,000 bytes of frames, no cycle
   sub main() l40() end
   ```

   `REQUIRED` is 512 plus the largest frame (object-format §6), so startup
   passes on any machine with 1K free, and the stack walks through `BSS`
   into the pool's generation counters. The previous review (NM9) already
   showed this; memory-safety §7.2 answers it with a linker computation that
   §7.2 and §10 admit does not yet exist. Until it exists, claim 6 does not
   hold.

3. §7.2 says the linker cuts "the edges that the compiler guarded". The
   linker holds a *reference* graph, not a call graph (object-format §5.1):
   a self-reference is how a routine addresses its own literals and jump
   tables, a `data` blob may reference a routine, and nothing in a reference
   says whether it is a call, whether the call was guarded, or whether the
   target was defined before the call site. The linker cannot identify the
   guarded edges from the format even with a per-blob stack figure added.

**Fix (all three at once, no format change).** Put every check in the
callee's prologue, and have the compiler compute per-routine subtree figures
in its single pass. Because names are declared before use, every callee of a
routine `R` has already been compiled when `R` is, except `R` itself and
forward routines not yet defined, so

```text
need(R) = frame(R) + helperStack(R) + max over calls c in R of
            ( c is R, or c is forward and undefined at the call : 0
            ; otherwise                                          : need(c) )
```

is computable when `R`'s body ends. Every self-recursive routine and every
forward-declared routine begins with the check `SP − need(R) − guard ≥ FREE`.
Every cycle passes through at least one such routine (see the verification in
§6 below), so every cycle is checked on every turn, and the check covers the
whole unguarded subtree below it, which the design's per-frame check does
not. `main` is compiled after everything it calls directly, so `need(main)`
is the acyclic bound and the compiler writes it into `LIMITS` as the stack
reserve. The linker then needs no graph computation and the object format
needs no change. Cost: 2 bytes per routine in the compiler's routine table;
the prologue check is ~13 bytes inline or 5 bytes plus a 15-byte helper, ~60
to 95 T-states, only in forward and self-recursive routines. Tree shaking
makes the bound an overestimate, which is harmless.

#### U5. `frees P` is not closed under ownership, so a cascade frees a pool the signature does not name

**Where:** §5.4 (retirement retires every owned field first), §6.2.

```nucleus
record Leaf
    v as u16
end
record Node
    child as own? Leaf
    next  as own? Node
end
pool leaves as Leaf[32]
pool nodes  as Node[32]

var root as own? Node

sub dropHead() frees nodes          // retires a Node, which cascades into leaves
    root = take deref(root).next    // old head retired on overwrite
end

sub paint(l as inout Leaf)          // no frees: receives an alias into leaves
    dropHead()                      // allowed: paint passes no alias, and the
                                    // effect it must propagate is only frees nodes
    l.v = 0                         // l's slot is on the leaves free list
end
```

`paint` must declare `frees nodes` by propagation, and its caller may not
pass it an alias into `nodes`. But the caller passed an alias into `leaves`,
and nothing names `leaves`. Claim 2 is violated.

**Fix.** Define the effect of retiring a handle of pool `P` as `frees` of
every pool reachable from `P`'s record type through `own`/`own?` fields,
transitively; record types are complete before any pool or routine that uses
them, so the compiler can compute the closure once per record type. Then
`dropHead` must declare `frees nodes, leaves`, `paint` inherits both, and the
call `paint(deref(someLeafId))` is rejected. This also answers §11.5: a
per-pool effect with closure is strictly more precise than a single global
effect and costs one bitset per routine.

#### U6. Generation wrap is reachable in seconds, so a stale identifier passes its check

**Where:** §3.3; §11.1; O2.

Pools return slots through a free list. A LIFO free list hands the most
recently retired slot back first, so one slot is reused on every iteration of
any allocate-then-free loop, and its generation advances once per iteration:

```nucleus
sub main() fails
    var h as own Node = new nodes(0, none) else fail
    var stale as id Node = id(h)
    retire h                                // generation of slot s becomes g+1
    for k = 0 until 256                     // (65536 for a 16-bit counter)
        h = new nodes(k, none) else fail    // slot s again, LIFO
        retire h                            // generation g+2, g+3, ... wraps to g
    end
    var v as u16 = deref(stale).value       // passes: generation is g again
end
```

The loop body is a `new` and a `retire`, roughly 500 T-states; 256 iterations
is 0.03 s and 65,536 iterations is about 8 s at 4 MHz. "Practically
impossible" (§11.1) is not true for a 16-bit counter on a hot slot. The
design's own text concedes the consequence: the stale identifier "reaches
another live `Node`". Under the standard definition that is a use after free
(see §2 of this review).

**Fix (cheap, makes it a guarantee).** Make the generation *saturating*: when
advancing it would wrap, the slot is withdrawn from the free list for the rest
of the run. A stale identifier can then never match, because no slot ever
returns to a generation it had before. The cost is one compare in `retire`
(~15 T-states) and, in the worst case, the loss of a slot after 255 or
65,535 reuses of it, which a FIFO free list spreads evenly across the pool.
With this, 8-bit generations become defensible: a 64-slot pool loses its
first slot only after about 16,000 retirements. Report the loss in the pool's
statistics if the toolchain has any.

#### U7. The flow bit is trusted for a location that is not a local, so an owned value is overwritten without retirement

**Where:** §5.2, "`list = n` retires nothing, because the flow check knows
`list` is `none` after the `take`"; §5.3, "one bit per owned local".

`list` in the §5.2 example is `inout own? Node`, an alias to a location the
caller and any routine that reaches it through a global can also write. A
flow bit for it is a guess:

```nucleus
var root as own? Node

sub refill() fails
    root = new nodes(99, none) else fail     // root was none; nothing retired
end

sub push(list as inout own? Node, v as u16) fails frees nodes
    var n as own Node = new nodes(v, take list) else fail   // list is none now
    refill() else fail                       // root, which list aliases, holds 99 again
    list = n                                 // "retires nothing": node 99 leaked
end

sub main() fails
    push(root, 1) else fail
end
```

Claim 7 (no leak) is violated. If the compiler's elision ever goes the other
way, trusting a bit that says "holds" when the location is `none`, the
unconditional retire of `none` corrupts the free list unless `retire` tests
for `none` at run time anyway.

**Fix.** Flow bits exist only for owned *locals* (whose address no other
routine can take). Every overwrite of an `own?` location that is not a local,
including `inout` parameters, record fields, array elements and globals,
emits the run-time test-and-retire (~9 bytes, ~40 T-states plus the retire).
`retire` of a `none` is always a run-time no-op. State both rules.

#### U8. The zero value of `id T` passes the generation check

**Where:** §4 row "Uninitialised read" ("every variable ... has an initial
value"); §3.3; cpm-target §4 step 6 (`BSS` is zeroed).

An `id T` in `bss` is all zero bytes: slot 0, generation 0. A fresh pool is
also all zero bytes: every slot has generation 0.

```nucleus
var cursor as id Node                       // zero: slot 0, generation 0

sub main() fails
    var h as own Node = new nodes(5, none) else fail    // takes slot 0
    var v as u16 = deref(cursor).value      // check passes: 0 = 0; reads h's node
end
```

`cursor` was never assigned, so this is a read of a value the program never
established (claim 4), and if `new` had not yet run it reads a slot that was
never allocated. The design has no `id?` and no `none` for identifiers, so
there is nothing else a zero `id` could mean.

**Fix.** Either (a) generations start at 1, so the zero identifier never
matches; `new` of a fresh slot sets generation 1, and `bss` zero means
"never allocated"; or (b) add `id? T` with `none` as the zero value and
require a test before dereference, as for `own?`. (a) is one `INC` in the
allocation path. Do (a) and also (b), because the doubly linked list needs
`id?` anyway (G7).

#### U9. `take` from a non-optional `own T` field leaves a hole that a later cascade retires

**Where:** §5.3, "taken with `take`"; §5.2, "`take list` ... leaves `none`";
§5.4 (retirement retires every owned field).

`own T` has no `none`. If `take` is allowed on it, the field afterwards holds
a stale handle, and retiring the container retires it again:

```nucleus
record Pair
    left  as own Node
    right as own Node
end
pool pairs as Pair[8]

sub split(p as own Pair) frees pairs, nodes
    var l as own Node = take deref(p).left   // left is now a hole: old bits remain
    sink(take l)                             // l's slot retired by sink
end                                          // p retired: cascade retires left again

```

Double free (claim 3) through the free list, and the second retire advances
the generation of a slot that may already have been reallocated, which makes
a *valid* identifier to the new occupant look stale or, worse, makes a stale
one look valid once the counter laps. The same applies to arrays
`own Node[N]` and to `take` of an element.

**Fix.** `take` is defined only on `own?` locations. A non-optional `own`
field or element can be moved only by moving its whole container, or by
swapping in a replacement (`p.left = take other` is an overwrite, which
retires the old value, not a move out). Alternatively drop non-optional `own`
in fields and arrays altogether, keeping it for locals and parameters where
the flow check can see every use.

### Major gaps

#### G1. Alias provenance is not in the type or the signature, so "an alias into a slot of `P`" is not decidable at a call site

**Where:** §6.2; §3.1; D8.

An alias of type `Node` may point into pool `nodes`, into a global
`var top as Node`, into a local `var tmp as Node`, into a field of a record in
another pool, or into a result. The call-site rule needs to know which. The
cases the design does not answer:

- **Parameters.** In `sub visit(n as Node)`, `n` could be anything. If
  `visit` calls `retireAll()` (`frees nodes`), propagation forces
  `frees nodes` onto `visit`, and then no caller may pass it a pool alias:
  `visit(deref(i))` is rejected while `visit(top)` is accepted. That is sound
  but only if the compiler treats a parameter of type `T` as possibly in every
  pool whose slot type *contains* `T`, transitively through fields and
  arrays. For `string[]` and small arrays such as `u8[16]` that means nearly
  every pool. State the rule.
- **Results without `from`.** D8 says such a result "points into a global".
  A pool is a global, so `sub head() as Node; return deref(root)` needs no
  `from` and the caller cannot tell its result is a pool alias. Either the
  signature must carry pool provenance for aggregate results (`as Node in
  nodes`), or every result whose type could live in a pool is assumed to be
  in all such pools. The second is simpler and rejects more.
- **Aliases from the result of an `inout own?` dereference**, as in U3.

**Fix.** Give every alias carrier, at compile time, a provenance: `{global,
local, param(k), pools(S)}` where `S` is a pool bitset. Field selection and
indexing keep the provenance; `deref` of an identifier yields `pools({P})`;
`deref` of a handle yields the handle's location (U1); a result yields the
union over its `from` parameters' arguments plus the signature's pool set. The
U2 rule then reads the bitset. Compiler cost: 1–2 bytes per parameter and
per staged carrier, 2 bytes per routine for the result's pool set; pools are
bounded (16 is enough) and the bound is published.

#### G2. The join rule cannot insert a retire on a branch that has already been emitted, and it is unstated for loops and short-circuit operands

**Where:** §5.3, "at each join point ... requires every incoming path to
agree, or to be resolved by an implicit retire on the path that still holds a
value".

```nucleus
if c
    keep(h)                 // branch 1: h still held; jump to join emitted now
elseif d
    sink(take h)            // branch 2: h moved
else
    keep(h)                 // branch 3: held
end                         // join: branches 1 and 3 need an implicit retire
```

When branch 1 ends, the compiler has emitted its jump to the join and does not
yet know that branch 2 will move `h`. It cannot go back and insert a retire
before that jump. Nucleus's single pass has no mechanism for this.

Loops have the mirror problem: at the loop top the compiler has not seen the
body, so it cannot know the back-edge state. And a move inside a short-circuit
operand (`if a() and sink(take h)`) is a data-dependent move the flow check
cannot resolve at all.

**Fix (choose one).**

- *Trampolines:* each branch's jump to the join is a fixup; at the join, a
  branch whose state differs from the meet is redirected to a stub `retire h;
  JP join` emitted there. Cost: 6 bytes per stub, plus per-branch state
  snapshots in the compiler (one bit per owned local per open branch).
- *Run-time `none`:* every owned local is physically nullable; `take` and
  moves write `none` into the source; scope exit retires unconditionally
  through the run-time test; the flow bit is used only to diagnose
  use-after-move and nothing is ever "implicitly retired" at a join. Joins
  then need no code and any disagreement is simply the meet. Cost: a 2-byte
  store per move (~16 T-states), and one test per retire. This also makes
  U7's rule uniform. I recommend it.

Either way: define loops (back edge and every `exit` must reconcile to the
entry state; a path that holds when the entry state does not gets a retire; the
reverse is an error) and forbid moves inside `and`/`or` operands.

#### G3. The order of overwrite and retire is unspecified, and the natural order frees what the right side still reads

**Where:** §5.4 "on overwrite".

```nucleus
root = take deref(root).next        // remove the head
```

If the compiler retires the old value of `root` when it forms the
destination path (Nucleus evaluates the destination first, §15.4), the right
side then dereferences a freed slot. If it retires after evaluating the right
side, the program is correct and the cascade stops at the field that was
taken. The design does not say. Specify: destination path, then right side,
then retire the old value, then store. Add the mirror case: if the right side
itself retires the destination's old value (through a `frees` routine), the
overwrite must find `none`, which U7's run-time test guarantees.

#### G4. The iterative retirement scheme is underspecified for trees, for cross-pool ownership and for link storage

**Where:** §5.4, "an explicit work list kept in the slots being freed".

- **Link storage.** If the free-list link lives inside the slot's payload,
  pushing a child onto the work list overwrites the child's first bytes
  before its own owned fields have been read. With `Node.child` at offset 0,
  the cascade loses the subtree, which is a leak (claim 7), or follows a
  corrupted handle, which is a wild free (claim 3). Either keep the link
  outside the payload (2 bytes per slot, beside the generation), or lay
  records out so that no owned field occupies the first two bytes, or push
  a slot only after reading all its owned fields into the list (which needs
  one link per *child*, so the same problem recurs one level down).
- **Cross-pool chains.** A `Node` owns a `Leaf` in another pool; the work
  list spans pools, so links must be addresses, not indices, and the runtime
  must know each entry's pool to find its generation counter and free list.
- **Which fields own.** The runtime must find the owned fields of every
  record type, including fields of nested records and elements of arrays of
  `own?` inside a record. That needs a per-type descriptor (offset list, or
  offset-plus-stride-plus-count for arrays) in `rodata`, or a generated
  retire routine per owning type. The design says "no hidden allocation",
  which is true, but there is hidden metadata, and it should be costed:
  about 2 bytes per owned field plus 3 per array of owned fields, per owning
  type.

#### G5. Which routines are checked, and what the check compares, differ between the two documents

**Where:** memory-safety §7.1 (call site, callee's frame, `FREE`); cpm-target
§4.1 (callee prologue, threshold, `FREE` plus 64).

Beyond U4: cpm-target's prologue check "passing its frame size" protects only
that frame. A forward routine `F` with a 20-byte frame that calls an
unguarded `G` with a 2,000-byte local array passes its own check and
overflows in `G`. The check must use the subtree figure `need(F)` from U4's
fix. Rewrite §4.1 to match, and remove the threshold rule: with `need(main)`
in `LIMITS`, large non-recursive frames need no check at all.

#### G6. When a routine acquires `frees` is only half stated, and forward bodies are not said to be checked against it

**Where:** §5.4, §6.2.

A routine with an `own T` local that is not moved on every path retires it at
scope exit, which is "retiring a `P` handle itself", so it needs `frees P`.
The same for an `own T` parameter and for an `own?` local or field that may
be overwritten. State that the effect is *checked* (declared in the signature,
verified against the body), never inferred, and that for a forward
declaration the body is verified against the forward's effect when the body
is compiled, so a disagreeing body is an error at the body even though the
calls were already accepted.

#### G7. There is no optional identifier, and identifiers do not name their pool

**Where:** §3.3; §8 "Cyclic structures use owned links in one direction and
identifiers in the other".

A doubly linked list needs `prev` to be absent on the head; a tree needs
`parent` to be absent on the root. With no `id?`, the program must invent a
sentinel, and U8 shows the zero identifier is a valid-looking one. Add
`id? T` with the same test discipline as `own?`.

Separately, if two pools hold the same record type (`pool a as Node[8]`,
`pool b as Node[8]`), an `id Node` does not say which pool its index is
into; a stale `id` from `a` used on `b` passes `b`'s generation check by
coincidence and reaches a live, wrong node. Make `own` and `id` name the pool
(`own a`, `id a`), or allow one pool per record type.

#### G8. The effect partitions programs: any routine that holds a pool alias cannot call anything that ever frees that pool

**Where:** §6.2 propagation rule; §8 last bullet.

```nucleus
sub printNode(n as Node)          // receives a ticket
    log("node")                   // log() keeps a bounded log in pool entries,
                                  // dropping the oldest: frees entries
end
```

`printNode` must declare `frees entries`; then it cannot be called with any
alias into `entries`. That is fine for this example, but take `n as Node` in
pool `nodes` and any logging, caching or allocation helper that frees from
`nodes` even on a path that is never taken: no routine that receives a pool
alias may call it. In practice every routine that touches a pool record must
take `id` or `own`, and every access pays a generation check. §3 of this
review shows the consequence for the common structures. This is a design
choice, but §8 should say it this plainly, and the design should consider
the cheaper alternative for the common case: a routine that receives an
`own T` *lease* (`h as inout own T`) owns exclusive access for the call and
needs no generation checks inside, while the effect rule still forbids
retiring `h` itself.

#### G9. Pool free lists are never initialised

**Where:** §5.1, "a `bss` blob: the slots, one generation counter per slot,
and a free list"; cpm-target §4 step 6.

`BSS` is zeroed. A zeroed free list is not a free list, and nothing in
startup, the linker or the design builds one. Either each pool is a root
blob with an initialiser that startup calls (needs a per-pool hook the
format lacks), or allocation uses a high-water mark: take from the free list
if non-empty, else from the next never-used slot, else fail. The second
needs no initialisation (zero high-water mark, empty list), costs one
compare, and with U8's fix "generation 0" means "never allocated" for free.
Say which.

#### G10. Local aggregates cost a zeroing loop on every call, and the design does not say what is zeroed

**Where:** §4 row "Uninitialised read"; D8.

A `var buf as u8[2048]` local must be zeroed to honour claim 4: 13 bytes of
code and 21 T-states per byte, 43,000 T-states, about 11 ms at 4 MHz, per
call. Nucleus had no such cost because it had no local aggregates. State the
rule and reduce it: a bounded string need only have its length byte zeroed
(no byte beyond the length is observable); a record of scalars needs full
zeroing; an array needs full zeroing unless it has an initialiser. Consider
an uninitialised-but-write-only form later. In every case the zeroing must
come after the stack check, not before.

#### G11. Services that write into program aggregates are outside the stated claim

**Where:** §1 "trusted base"; Nucleus §16.

Nucleus's services move single bytes, and the runtime owns the DMA buffer
(cpm-target §4 step 1). Baton will presumably add a record read into a
program buffer. A BDOS read writes 128 bytes at the DMA address regardless
of the caller's buffer. If the service takes `string[]` or `u8[]`, the
runtime has the capacity and must check it; if it takes `u8[128]` the type
is exact. Either way the claim should say that the trusted base must respect
alias extents and modes, that no service retains an address past its return
(a service that set the DMA address to a local aggregate and returned would
let a later read write into a dead frame), and that the runtime restores the
DMA address to its own buffer before returning.

#### G12. Result aliases carry no mode, so a ticket or a constant becomes writable through a result

**Where:** §3.1 modes; D8; Nucleus §7.8.

```nucleus
const table as Entry[4] = ...

sub pick(items as Entry[4], i as u8) as Entry from items   // items is a ticket
    return items[i]
end

sub main()
    pick(table, 0).value = 9         // result alias: writable? the design is silent
end
```

Nucleus already loses the read-only marker through an alias and says
portable programs must not rely on it. Baton has modes and should close
this: a result alias has a mode, read by default; a routine returning an
alias rooted in an `inout` parameter or a global variable may declare the
result `inout`; a constant-rooted path never binds to `inout`. This is not a
memory-safety hole on CP/M (`TEXT` is RAM) but it is on a ROM target, where
the write is silently ignored, and it undermines the signature-tells-you
promise of §3.1.

### Minor issues

#### m1. The trap reporter list lacks `stale-handle`

cpm-target §10.1 enumerates the reporters; memory-safety §10 adds the
`stale-handle` trap. Add the reporter, and note that the generation-check
helper must follow §10.2 (jump with the site's return address on top), so
the report names the dereference, not the helper.

#### m2. The representation of `own T`, `own? T` and `none` is unspecified

Whether an owned handle is a 2-byte address or a 1-byte index decides whether
`none` can be zero (so that `own?` globals and fields in `bss` and in
re-newed slots are `none` for free), whether dereference costs an address
computation, and whether U9's "hole" is detectable. Recommend: `own` is the
slot address, `none` is 0; `id` is index plus generation.

#### m3. Re-entry without reloading is memory-unsafe, not just wrong, once owned globals exist

cpm-target §7: without re-runnable, initialised data keeps the previous
run's values. An `own? T` global that was `some` at exit holds a handle into
a pool that startup has just zeroed: a dangling owned handle, which is a
double free waiting to happen. Either owned globals must always be in `bss`
(they can be, since no initialiser can call `new`), or the document must say
re-entry violates the safety claim.

#### m4. The guard band is asserted, not derived

64 bytes must cover the deepest runtime helper's own pushes, the trap
reporter's BDOS call (the BDOS switches stacks after a few pushes), and an
IM1 BIOS that pushes `PC` and typically six register pairs. Publish the
helper figures in the library's helper table so the compiler can use them in
`need(R)` (U4) instead of relying on the band.

#### m5. Routine values must carry `from` and `frees`

O5 is future, but the rule should be recorded now: a routine type includes
its `from` clause and its effect set, and a call through a routine value is
checked against them. Without that, every call through a value is an
unguarded edge for both the alias rule and the stack rule.

#### m6. Say what is excluded

The document should state in one place: no interrupt routines in source; no
concurrency; the runtime library may use self-modifying code and is trusted;
`TEXT` is writable RAM on CP/M so there is no hardware protection of code or
constants.

#### m7. String growth needs a capacity trap

Nucleus strings cannot change length. If Baton adds append or length
assignment, the check against capacity is a new `bounds` site; `string[]`
carries the capacity so it is implementable. Note it under claim 1.

#### m8. Aliases to aggregate constants

Subsumed by G12 for results; for parameters, the `inout` rule already
rejects a constant-rooted argument, and the document should say so.

#### m9. Per-pool versus single `frees` (§11.5)

With U5's closure, the per-pool form is the single-effect form restricted to
the reachable pools, and costs one bitset. Keep per-pool.

#### m10. Arenas as "activation storage whose size is decided at run time" break the stack bound

§9 says arenas are activation storage sized at run time. U4's fix bounds the
stack with static frame sizes. A run-time-sized frame needs its own capacity
check at allocation, like the recursive case. Note it so §9 does not later
undo §7.

#### m11. "An alias into a pool slot is live only during the call it is passed to" is false for the callee

Inside the callee the alias parameter is live for the whole body, across
every call the callee makes. The argument in §6.2 works only because
propagation forces the effect onto the callee; say so, because the sentence
as written suggests the callee's own calls are unconstrained.

---

## 2. Temporal safety

The usual definition: no access to storage after its lifetime has ended,
whatever now occupies it. Claim 2 as written adds "or after it has been
reused for another object of a different type", which quietly admits access
after reuse by the *same* type, and §6.1 and §11.1 confirm that reading is
intended: a stale identifier that passes the check "reaches another live
`Node`".

As drafted, the design meets the usual definition for aliases (statically,
once U1–U3 and U5 are fixed) and for owned handles (statically, once U7 and
U9 are fixed), and does *not* meet it for identifiers, because the
generation check is probabilistic with a period of 256 or 65,536 reuses of
one slot, which U6 shows is minutes or seconds away on a LIFO free list.

The cheapest fix that makes it a guarantee is the saturating generation in
U6: a slot whose counter would wrap is withdrawn. Then no identifier ever
matches a generation it did not record, and the claim can drop the "different
type" qualifier. Cost: one compare in `retire`, one byte or two per slot as
now, and the loss of a slot after 255 or 65,535 reuses. With a FIFO free list
and 8-bit counters, a 64-slot pool withdraws its first slot after roughly
16,000 retirements; with 16-bit counters, after four million. Type stability
then stays as a second line of defence against *runtime* bugs, which is
where it belongs, rather than as a weakening of the claim.

---

## 3. Expressiveness

Each program below uses the design as drafted plus the fixes above that are
needed to make it compile (`id?`, saturating generations, U2's statement-level
rule). Where the design as drafted rejects the natural form, the rejected form
is shown first.

### 3.1 Singly linked list with deletion during traversal

The natural Nucleus form is rejected: a routine that receives a `Node` alias
cannot free from `nodes`.

```nucleus
sub removeAll(n as inout Node, v as u16) frees nodes   // error: n may be in nodes,
    ...                                                 // and this frees nodes
end
```

With identifiers it is writable, and every step pays generation checks:

```nucleus
record Node
    value as u16
    next  as own? Node
end
pool nodes as Node[64]
var root as own? Node

sub removeAll(v as u16) frees nodes
    // head
    while root is some and deref(root).value = v
        root = take deref(root).next          // old head retired on overwrite
    end
    if root is none
        return
    end
    var p as id Node = id(root)
    while deref(p).next is some
        if deref(deref(p).next).value = v
            deref(p).next = take deref(deref(p).next).next   // victim retired; its
                                                             // next was taken, so the
                                                             // cascade stops (G3 order)
        else
            p = id(deref(p).next)
        end
    end
end
```

Four to six generation checks per element (each `deref`), about 150 T-states
each. A lease form (`h as inout own Node`, G8) would remove them.

### 3.2 Free-list allocator

A pool *is* one. A user-level allocator over program storage is the Nucleus
idiom and still compiles, with bounds checks and no temporal check at all:

```nucleus
record Cell
    payload as u16
    link    as u8
end
var cells as Cell[64]
var free  as u8          // index of first free cell; 255 is "none"

sub allocate() as u8 fails
    if free = 255
        fail poolFull
    end
    var c as u8 = free
    free = cells[c].link
    return c
end

sub release(c as u8)
    cells[c].link = free
    free = c
end
```

Stale indices go undetected, as in Nucleus; the program is memory safe by
bounds alone. This is what pools improve on, and the comparison is worth
keeping in the document.

### 3.3 Doubly linked list

Needs `id?` (G7). With it:

```nucleus
record Node
    value as u16
    next  as own? Node
    prev  as id? Node
end
pool nodes as Node[32]
var head as own? Node

sub unlink(x as id Node) frees nodes
    var nx as own? Node = take deref(x).next
    if nx is some
        deref(nx).prev = deref(x).prev
    end
    if deref(x).prev is some
        var p as id Node = deref(x).prev        // owner of x is p.next
        deref(p).next = take nx                 // overwrite retires x
    else
        head = take nx                          // overwrite retires x
    end
end
```

Note the trick: the caller holds `x` only as an identifier, and `x` is
retired by *overwriting the field that owns it*. There is no way to say
`retire x` for an identifier, which is correct. After `unlink`, every copy of
`x` traps on use.

### 3.4 Tree with parent links

```nucleus
record Tree
    key    as u16
    left   as own? Tree
    right  as own? Tree
    parent as id? Tree
end
pool trees as Tree[128]
var top as own? Tree

sub insert(k as u16) fails
    if top is none
        top = new trees(k, none, none, none) else fail
        return
    end
    var p as id Tree = id(top)
    while true
        if k < deref(p).key
            if deref(p).left is none
                deref(p).left = new trees(k, none, none, p) else fail
                return
            end
            p = id(deref(p).left)
        else
            if deref(p).right is none
                deref(p).right = new trees(k, none, none, p) else fail
                return
            end
            p = id(deref(p).right)
        end
    end
end
```

Deleting a subtree is one overwrite (`deref(p).left = none`), and the
iterative retirement must handle two owned fields per record (G4).
Rotations move subtrees between owners with `take`, and each `take` of an
`own?` leaves `none`, so a rotation that temporarily holds three subtrees in
locals compiles under the flow check.

### 3.5 Graph

```nucleus
record Vertex
    label as u16
    edges as id Vertex[4]     // see U8/G7: needs id? or a count
    count as u8
end
pool vertices as Vertex[32]
var owners as own? Vertex[32]  // every vertex owned by one array slot
```

Writable. Deleting a vertex is `owners[k] = none`; every identifier to it in
other vertices' `edges` becomes stale and *traps* when traversed. The program
must sweep or tombstone, and the design should say that this is the intended
discipline: a stale identifier in a graph is a program bug reported at the
use, not silently skipped. A `isLive(id)` query that returns a boolean
without trapping would make sweeps cheap and should be considered.

---

## 4. Costs

Z80 at 4 MHz. Figures are for the obvious code; a size-tuned runtime could do
somewhat better.

| Mechanism | Where | Bytes | T-states | Notes |
| --- | --- | --- | --- | --- |
| Identifier dereference, pool ≤ 256 slots, power-of-two slot size | site + per-pool helper | 6 at site; ~28 helper per pool | ~165 | load id, add to generation table, compare, trap, shift index, add base. Non-power-of-two sizes: +~40 with a 512-byte address table or +~200 with a multiply |
| Owned-handle dereference (address representation) | site | 3 | 16 | `LD HL,(h)`; zero if already in a register |
| `own?` test | site | 5 | ~20 | `LD A,H / OR L / JR Z` |
| Overwrite of an `own?` location | site | ~9 | ~40 + retire | test old, call retire, store new |
| Retire, one slot, one owned field | site + helper | 6 at site; ~80 helper per pool, or ~120 shared + descriptor | 200–250 per slot | test none, walk owned fields via descriptor, push free list, bump generation; saturating check +15 |
| Scope-exit retire, per owned local per exit path | site | ~9 | ~55 + retire | with a shared epilogue and run-time `none` (G2): 3 bytes per exit path |
| Activation-capacity check | prologue of forward and self-recursive routines only | 13 inline, or 5 + 15 helper | 60–95 | compares `SP − need(R) − guard` with `FREE` |
| Local aggregate zeroing | prologue | 13 | 40 + 21 per byte | 2K buffer: ~11 ms per call; string: 1 byte |
| Bounds check on array/string index | site | as Nucleus | as Nucleus | pool index via `id` needs none with per-pool `id` types |
| Trap site | site | 3 or 5 | — | D11 |
| Owned-field descriptor | rodata per owning type | 2 per owned field, 3 per array of them | — | hidden metadata, G4 |
| Pool overhead | bss per slot | 1 (8-bit gen) or 2 (16-bit) + 2 (free/work link outside payload) | — | G4 |

Compiler memory for the checks, single pass:

| Fact | Per | Bytes |
| --- | --- | --- |
| `frees` effect set, ≤ 16 pools | routine | 2 |
| `from` mask, ≤ 8 alias params | routine | 1 |
| Result pool provenance | routine | 2 |
| Subtree stack figure `need(R)` | routine | 2 |
| Parameter pool provenance | parameter | 2 |
| Owned-local flow bits | owned local × (if/loop nesting + 1) | 1 bit; e.g. 16 locals × 9 levels = 18 bytes, transient |
| Branch retire trampolines (G2, option 1) | branch × local needing a retire | 2 (fixup) |
| Staged-carrier pool set | expression-stack entry | 2 |

Roughly 7 bytes per routine and 2 per parameter on top of Nucleus's tables,
plus a few tens of bytes of transient state per routine. The flow analysis
itself needs no control-flow graph.

---

## 5. Questions for the designer

1. Is an alias obtained from `deref(h)` for a *local* `h` meant to be
   returnable? U1 says the current wording allows it. If not, what is the
   provenance of such an alias in the signature-level rules?
2. Does `frees P` include the pools reachable from `P` by ownership (U5)? If
   the answer is "a single effect for all pools" (§11.5), say so and drop the
   pool name.
3. Is `take` meant to apply to non-optional `own T` fields (U9)? If so, what
   does the field hold afterwards?
4. Which representation: `own` as address and `id` as index-plus-generation
   (m2)? Does `none` have to be zero?
5. Saturating generations (U6): acceptable to lose a slot after 255 reuses
   with 8-bit counters, or would you rather pay 2 bytes per slot and lose it
   after 65,535?
6. Flow check: trampolines or run-time `none` (G2)? The second removes
   "implicit retire at joins" from the language description entirely.
7. Stack: will you accept the compiler computing `need(main)` into `LIMITS`
   (U4), which removes the object-format change in §10 and the linker
   computation in §7.2?
8. Is a lease (`h as inout own T`) worth adding so that routines on pool
   records do not pay a generation check per access (G8)? Under the effect
   rule it is sound: the callee cannot retire `h` (that needs the location's
   owner) and no `frees P` call can reach `h`'s slot while the lease is an
   argument.
9. What does a stale identifier in a graph's edge list do during a sweep: trap,
   or is there a non-trapping liveness query (§3.5)?
10. For local aggregates, is full zeroing acceptable (G10), or should a
    large array require an initialiser or be write-before-read by rule?
