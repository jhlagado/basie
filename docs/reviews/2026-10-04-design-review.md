# Adversarial review of the Basie language design

- Date: 2026-10-04
- Documents: design-decisions.md (D1–D22, O1–O6), memory-safety.md revision 3,
  io-and-effects.md, feature-inventory.md, philosophy.md, README.md,
  cpm-target.md §4.1 and §10; the Nucleus 0.1 specification chapters 3, 6–16;
  Skate's external-effects.md and ports.md; the second memory-safety review
  (NU1–NU11, NG1–NG8).
- Method: every guarantee in revision 3 was attacked with a program written in
  the syntax the documents use. Every feature was checked against the Nucleus
  rule it inherits. Nothing here is a style comment unless the section says so.

Counts: 9 unsound or gap-to-unsound findings (U1–U9), 14 feature-interaction
problems (F1–F14), 16 ergonomic oddities (E1–E16), 9 I/O findings (I1–I9),
19 stale-text items (S1–S19), 18 decisions still needed (N1–N18).

## 0. Verdict on NU1–NU11 under revision 3

| ID | Verdict under handles-only | Note |
| --- | --- | --- |
| NU1 | moot | No aliases into pools, so no pool sets. |
| NU2 | moot | Same. |
| NU3 | moot | A returned alias can't point into a pool. |
| NU4 | half fixed | Handle bindings are identifiers now. Variant payload bindings are still aliases (feature inventory §4.2) and the subject is still not frozen: see U7. |
| NU5 | **reopened** | The slot-holder "reached through an identifier" (§5.7) is the handle-location parameter under another name: see U1. |
| NU6 | fixed | Lease rules forbid move and overwrite. A same-statement move still reaches it: U3. |
| NU7 | half fixed | "May have been moved" is now an error. But there is still no way to turn a `nodes?` into a `nodes`: see F1. |
| NU8 | fixed | Live generations 1..`$FFFE`; withdrawal sets `$FFFF`; the check rejects 0 and `$FFFF`. One wording ambiguity: U6. |
| NU9 | fixed | |
| NU10 | **reopened** | A cycle can be built through a slot-holder (U2), the owner link that the check walks is never maintained (U4), and a cycle, once built, makes the cascade loop or double free. |
| NU11 | fixed for freeing | Tag-dispatched descriptors. Constructing and overwriting an owning variant are still undefined (NG3): U7. |
| NG1 | fixed | Fresh temporaries freed at the end of the statement. See U5 for what "statement" must mean. |
| NG2 | fixed | Descriptor entries carry the pool. |
| NG3 | not fixed | U7. |
| NG4 | not fixed | U9. |
| NG8 | not fixed | The loop-top sentence in §5.8 is unchanged: U8. |

---

## 1. Unsound memory-safety findings

### U1. A slot-holder reached through an identifier can be freed during the call, and the callee then writes, moves from, or double-frees through it

**Where:** memory-safety §5.7 "Its argument may be any owning optional
location: a local, a program variable, or a field reached through an owner or
an identifier."

The location of a slot-holder whose argument is `i.next` is inside slot
*S(i)*. Nothing stops the callee, or anything it calls, from freeing *S(i)*,
because the owner of *S(i)* is reachable by name:

```nucleus
var head as nodes?

sub steal(var list as nodes?) fails
    head = none                 // frees the whole list, including the slot that holds `list`
    var x = move list           // reads a handle out of a freed slot: x now "owns" a slot on the free list
    var y = new nodes(1, "", none, none) else fail   // FIFO hands that same slot out again
end                             // x and y both freed: double free (claim 3)

sub main() fails
    match head
    case some(i)
        steal(i.next) else fail // allowed by §5.7: a field reached through an identifier
    case none
    end
end
```

Two more routes with the same shape: `list = move n` after `head = none`
stores an owning handle into a freed slot, which `new` later overwrites (a
leak, claim 7, then a dangling handle if a cascade ever reads it); and
`two(head, i.next)` with `sub two(var a as nodes?, var b as nodes?)` doing
`a = none` then `var x = move b`. No `match`, no identifier check, and no
flow state covers the slot-holder, because it is a `var` parameter and "every
other owning location is treated as possibly holding a value". Section 6's row
"Freeing a slot while it is leased" covers only leases.

**Fix.** A slot-holder argument must be a location that no slot owns: an
owning local of type `nodes?`, a program variable, or a field of a local or
program aggregate. A field of a pool slot may not be passed as a slot-holder.
The caller writes `match i.next ... i.next = move n` inline, or passes
`id nodes` and lets the callee store through the checked path. If pushing onto
"any node's list" must stay a routine, make an identifier-rooted slot-holder a
distinct parameter kind, represented as (identifier, offset), with every
access through it generation-checked; then `head = none` in the callee makes
`list = ...` trap with `stale-handle` instead of writing a dead slot. The first
fix is simpler and is the one assumed below.

### U2. An ownership cycle can be built through a slot-holder with no check

**Where:** §5.9 "Storing an owning handle through an owner path ... can't
create a cycle"; §5.7.

Section 5.9 lists owner paths as starting at "an owning local, a lease or a
program variable". A slot-holder is none of these and §5.7 lets it start
inside a slot. The argument "the stored handle was owned elsewhere, so it
can't be an ancestor of the destination" is false when the destination is a
field of a slot that the stored subtree contains:

```nucleus
sub cyc(var list as nodes?)
    var x = move head           // x owns the list; its first slot S holds `list`
    list = move x               // S.next = S. Owner path, so no check. x = none, head = none
end                             // S is unreachable, with a self-cycle
// main: match head  case some(i)  cyc(i.next)
```

The leak alone breaks claim 7. If an identifier to *S* survives,
`i.next = none` starts the cascade of §5.10 on *S*: it pops *S*, reads
`S.next = S`, pushes *S*, returns *S* to the free list, pops *S* again, and
either loops forever or puts *S* on the free list twice, which is a double
allocation and then a double free.

**Fix.** U1's restriction removes the route. Also state in §5.9 that a
slot-holder is an owner path only because its location is never inside a
slot. Independently, make the cascade idempotent as the second review's NU10
asked: a live slot's link is nonzero, a slot being freed is marked, a child
already marked or free is not pushed. It costs one test per child and turns
any cycle that slips through into a leak rather than a double free. State
claim 7 accordingly.

### U3. A local can be leased and moved in the same call

**Where:** §5.6 "the same local may not be passed twice in one call";
Nucleus §13.4 arguments evaluate left to right.

`move n` is an argument expression, not a lease, so the "passed twice" wording
does not obviously catch it:

```nucleus
sub f(var h as nodes, x as nodes)
    sink(move x)                // sink frees the slot
    h.value = 1                 // h is a lease on that slot: write after free, no check
end

sub g() fails
    var n = new nodes(1, "", none, none) else fail
    f(n, move n)                // lease taken first, then n moved
end
```

The same hole through a nested call: `f(n, wrap(move n))`, or through a
slot-holder in the same statement: `f(n, l)` is forbidden, but
`f(n, consume(move n))` is not. After the statement the flow check says `n`
is certainly `none`, which is right; the harm is during the call.

**Fix.** A local that is leased in a statement may not appear anywhere else in
that statement except as `id(n)` or as a read of a scalar field. State this as
the lease rule, not "passed twice".

### U4. The owner link that the cycle check walks is never maintained, and roots are indistinguishable from slots

**Where:** §5.9 "Each slot's link field holds its owner's address while it is
allocated, so the walk needs no extra storage"; §5.10 the work list is
"threaded through the link fields"; §5.1 the free list.

The design never says who writes the link. Every `move` into a field, every
`new` with a moved argument, every store through a slot-holder, every move
into a local or a program variable, every return of a fresh handle and every
cascade must update it, and the cost table's "`move` (store `none`), 3 to 4
bytes" does not include a 2-byte address store at the destination. Three
consequences:

1. **The walk can't stop.** "Follows the owner links upwards from *s*" needs
   to know when a link names a root (a local's stack address, a program
   variable, an array element) rather than a slot. Nothing distinguishes them.
   With a stack address as a link, the walk reads stack bytes as a slot's link
   and continues into arbitrary memory.
2. **A stale link gives a false negative.** After `var x = move i.next` the
   slot's link still names *S(i)*. If `x` is then stored under an identifier
   path into a slot inside its own subtree, the walk from the destination goes
   up through the stale link and never meets `x`. (Concretely:
   `var x = move i.next`; `match x case some(q) ... match q.next case some(r)
   ... r.next = move x`: the walk from *S(r)* reaches *S(q)*, whose link still
   says *S(i)*, so it never sees *S(q)*'s real owner, the local `x`, which is
   the handle being stored.)
3. **One field, four meanings.** The same word is the owner link, the
   free-list link, the work-list link and (after U2's fix) the mark. The free
   list is FIFO with head and tail, so a free slot's link is the next free
   slot. `new` must clear it to "owned by a root" before the owner is known.

**Fix.** Define the link: 0 while owned by anything that is not a slot (a
local, a program variable, a local or program aggregate), else the owning
slot's address. State that every store of an owning handle into a slot's
field writes the destination slot's address into the moved slot's link, every
store into a non-slot location writes 0, `new` writes 0, and a move out of a
field leaves the link stale until the next store. Then show that the stale
window is harmless: the cycle check runs at a store, and at that moment the
stored handle's own link is irrelevant (the walk starts at the destination and
looks for the handle, not its link), but the links of every slot *above* the
destination must be current, which they are because those slots were not
moved in this statement. With U1's fix, the only owner paths that store into
a slot start at an owning local or lease, whose slot is a root (link 0), so
one-field-deep stores need no walk at all. Cost the link store in §10.

### U5. "Freed at the end of the statement" is undefined for a `match` subject and for a temporary used as a lease

**Where:** §5.3 "at the end of the statement, if it is a fresh owning value
that nothing took".

A `match` is a statement whose arms are statements:

```nucleus
match build()               // build() as nodes?: a fresh temporary
case some(i)
    print(i.value)          // is the temporary alive here? "end of the statement" is ambiguous
case none
end
```

If the temporary is freed when the subject has been read, `i` is stale and
the arm traps, which is safe but useless. If it lives to the `end`, the
compiler must give it a hidden local and free it on every exit from the arms,
including `return` and `fail`. Similarly `bump(build())` would lease a
temporary, which §5.6 forbids ("the caller's own owning local") without saying
whether `build()` counts.

**Fix.** Say that a fresh owning temporary is held in an anonymous local of the
innermost enclosing statement, freed on every exit from that statement, and
that it may be leased and matched like a local. Or forbid it as a `match`
subject and a lease argument; either is sound, but the choice must be written.

### U6. Generation wording: "reaches `$FFFE` and is freed"

**Where:** §5.11.

"When a slot's generation reaches `$FFFE` and the slot is freed, it is
withdrawn" can be read as "live at `$FFFD`, freed to `$FFFE`, withdrawn" or
"live at `$FFFE`, freed, withdrawn at `$FFFF`". Both are sound (identifiers
never hold `$FFFF`, and the check rejects it), so this is a wording defect,
but a specification needs one of them, and the free-list pop that U2's
idempotence adds must test the same value.

**Fix.** "A slot is allocated only while its generation is below `$FFFF`.
Freeing advances the generation; a slot whose generation becomes `$FFFF` is
withdrawn instead of being put on the free list."

### U7. Variants with owning payloads: binding by copy is double ownership, payload aliases dangle, and construction and overwrite are undefined

**Where:** feature-inventory §4.2 "A scalar field is copied into the name; an
aggregate field is bound as an alias"; D15; memory-safety §5.10 (descriptors
only).

A handle is a scalar-sized field. Copying an owning payload into a binding
makes two owners:

```nucleus
variant Slot
    full(h as nodes?, tag as u16)
    empty
end
var s as Slot

match s
case full(h, t)             // h: a copy of an owning handle, per the inventory
    s = empty               // if overwrite frees the payload (undefined), h is freed
    kept = move h           // and now kept owns a freed slot
case empty
end
```

An aggregate payload (`name as string[16]`) bound as an alias is overlaid
when the arm assigns `s = empty` (NU4's second program, still open). If the
subject is a field of a pool record, `match i.shape case full(h, name)` binds
an alias into a pool slot, which D16 forbids. And there is no syntax to build
`full(move x, 3)` or to say what freeing the old payload on `s = ...` means.

**Fix.** (1) An owning payload field is bound as an identifier, like `some`.
(2) An aggregate payload is copied out when the subject is a pool field;
when the subject is a local or program variable it may be an alias, but then
the subject's storage path is frozen for the arm: no assignment to it or any
prefix of it, no `move` through it. (3) Define constructor assignment:
evaluate the constructor's arguments (moves), resolve the destination, free the
old payload through the tag table, store. (4) Add variant locations to §5.3's
"when the variable or field that owns it is overwritten".

### U8. The flow check's loop rule can't be implemented in one pass, and `continue` is unstated

**Where:** §5.8 "loops are checked with the state at the top assumed to be
the meet of the entry and every back edge, `continue` and `exit`."

A single-pass compiler has not seen the back edges when it is at the top. NG8
said this of revision 2 and the sentence is unchanged. `exit` is not a back
edge; it feeds the state *after* the loop.

```nucleus
var n = new nodes(1, "", none, none) else fail
while cond()
    n.value = 1             // checked against the entry state: certainly holds
    sink(move n)            // n = none
end                         // back edge: n may be none at the next test, and the body derefs it
```

**Fix.** State it as a back-edge check: at every back edge (`continue`, the
end of the body, and for `while` the condition re-test) the state of each
non-optional owning local must be *certainly holds* if it was at entry, which
the compiler can test when it reaches the back edge. The state after the loop
is the meet of the condition-false state and every `exit` state. Moves in a
`while` condition are already forbidden.

### U9. Local aggregates with owning fields: freeing, modes and copying are unstated

**Where:** D8, §5.3 "when its owning local or parameter goes out of scope",
§5.8 "flow states exist only for owning locals".

`var tmp as Holder` with `head as nodes?` is a local that owns, but §5.3
speaks of handles. Needed and absent: the epilogue walks `tmp` by descriptor
(every exit path, including `fail`); `var arr as nodes?[8]` is walked too;
a ticket `h as Holder` admits neither `h.head = none` nor `move h.head`
(both write through a read-only alias); `var h as Holder` admits both and
`h.head = move x` needs no cycle check because the alias is never into a slot;
whole-record copy of `Holder` is an error even as a `var` result. And a pool
record whose field is an owning record type (`sub as Holder` inside `Node`)
can't be copied out, so `i.sub` is unusable unless field chains through
non-handle aggregates (`i.sub.head = move x`, `i.kids[k]`) are one checked
operation. The access table in §5.4 shows only `i.value`.

**Fix.** State all of these. Say that a path through an identifier may select
any chain of record fields and checked array indices under one generation
check, and that only the leaf is read or written.

---

## 2. Feature-interaction problems

### F1. A `nodes?` can never become a `nodes`, so an owning parameter can't receive a node from a list

`match` binds an identifier, not a handle. `move head` has type `nodes?`.
Nothing converts it:

```nucleus
sub sink(n as nodes)
var head as nodes?
sink(move head)                 // nodes? to nodes: no rule admits it
```

The only owning non-optional values are `new`, fresh results, and locals
initialised from them. Every routine that takes `nodes` is therefore
callable only with freshly made nodes. The second review's NU7 fix asked for
a `match` that moves; D15 and §5.5 bind identifiers only.

**Fix.** Either a binding form that moves, `match move head case some(n)`
where `n` is a fresh `nodes` local and `head` becomes `none`, or a checked
conversion `nodes(move head)` trapping with a new `none-handle` reason. The
first keeps the "null dereference is compile time" row of §6.

### F2. `new` and routine calls disagree about what a failure does to moved arguments

§5.3: a failed `new` "never consumes a moved argument" because the slot is
reserved first. A failed routine call consumes them: `build(move n) else
fail` frees `n`'s node in `build`'s epilogue. Under `handle` the two differ
in the flow state of the handler body: after `n = new nodes(move l) handle
code`, `l` still holds; after `n = build(move l) handle code`, `l` is `none`.
Neither D19 nor §5.8 says so, and the reservation rule interacts with an
argument that itself calls `new` on the same pool (the reserved slot must be
invisible to it, and the argument's failure can't be handled inside an
argument anyway, so the only effect is that the inner `new` fails with one
slot fewer).

**Fix.** Choose one behaviour for both. Keeping the list on pool-full is the
useful one for `push`; then say that a failed call to a routine with owning
parameters frees them, and that `new` is the exception, and give the handler
body's flow state for each. Or evaluate `new`'s arguments first and free the
moved ones when allocation fails, which makes the two agree.

### F3. Locals must be declared in a prefix, but every pattern declares them mid-body

Nucleus §8.11: a local after the first statement is invalid. Every example in
memory-safety §8 (`var p = id(head)` after a loop), D19 (`var n = new ...`
inside `push`), and the flow check's "per open control level" assume
block-scoped declarations, and §5.3's "freed on `exit` and `continue`" only
means anything if a local can be declared inside a loop body. No decision
lifts the Nucleus rule.

**Fix.** Decide: declarations anywhere, scoped to the enclosing block, with
the usual single-pass cost (a scope mark per block). Then the `for` counter can
be declared by the loop (`for i as u8 = 0 until n`), which Nucleus also
forbids (§12.4).

### F4. `match` on an owning local pays an identifier check and defers a compile-time error to run time

```nucleus
var n as nodes? = build()
match n
case some(i)
    n = none                    // allowed: n is a local, not frozen
    i.value = 1                 // traps stale-handle at run time
end
```

Nothing is unsound, but a 165-T-state check on every access to a slot the
routine itself owns is the common case for local work, and the overwrite could
be rejected at compile time.

**Fix.** When the subject is an owning local or lease, freeze it for the arm
exactly as Nucleus freezes a counted-loop counter (§12.4), and bind `some(h)`
as a direct owner access with no check. Keep the identifier binding for every
other subject.

### F5. Fresh owning results in Nucleus's statement positions

Nucleus §14.4: a failable call may be only a local initialiser, the whole
right side of an assignment, or a call statement. So `new` (failable) can't
be an argument: `sink(new nodes(...) else fail)` is invalid, and every
allocation needs a named local. That is consistent, but D19's "a fresh value
needs no `move`" then applies almost only to infallible routines returning
handles. Say so, and consider letting `else fail` attach to an argument-level
`new` when the enclosing statement is itself a call statement or assignment.

### F6. Constant expressions wrap, which is wrong once signed types exist

Nucleus §9.7–9.8: two exact constants with no expected type use `u16` and
wrap, so `const n = 3 - 5` is 65534, and `print(3 - 5)` passes 65534 to a
`u16` parameter. With `i16` in the language a reader expects −2.

**Fix.** Evaluate constant expressions exactly (a signed 33-bit or wider
accumulator in the compiler), and require the result to fit at each use. An
exact negative constant then fits `i16` and is an error for `u16`, which is
what D4 says for run-time values.

### F7. "Mixed signed and unsigned is an error" is only half true

D4 admits `u8` to `i16` and `u16` to `i32` implicitly. So `i16var + u8var`
is fine and `i16var + u16var` is an error; `u16var < i32var` is fine. The
rule a reader can apply is "an error unless one operand widens exactly into
the other's type", and the table of widenings must include the signedness
crossings explicitly. Also undefined: unary minus on an unsigned operand
(Nucleus wraps; with signed types available it should be an error), the sign
of `mod` with a negative operand (truncated like `/`, say so), `i8(-128) / -1`
and `i8(-128) mod -1` (wrap to −128 and 0 under D5, say so), and whether
shifts of signed values are arithmetic.

### F8. `for` with signed counters

Nucleus §12: the counter is a `u8`/`u16` local, the step a signed constant,
the bound "an integer expression" compared after widening. With `i8`/`i16`
counters: the comparison must be signed; a `u16` bound against an `i16`
counter is a mixed-sign error unless the rule says the comparison happens in
`i32`; `u32`/`i32` counters would make every loop a helper call. The classic
`for i = n - 1 to 0 step -1` with `n = 0` and a `u16` `n` wraps the bound to
65535 before the loop starts, which is now a silent bug a signed-typed
language could catch.

**Fix.** Counter types `u8`, `u16`, `i8`, `i16`. The bound must widen exactly
to the counter's type. A constant bound that doesn't fit is an error. Say
whether `i32`/`u32` counters exist (recommend: no).

### F9. Type inference (D21) is underspecified for literals that do have a type

Nucleus gives a character literal type `u8` and `true`/`false` type
`boolean`, so `var c = 'a'` and `var ok = true` have definite types under the
letter of D21 but may not be intended. `var s = "abc"` has no rule (string
literals aren't expressions in Nucleus). `var t = text` where `text` is a
`string[]` view has no capacity to copy. `var e = entryAt(3)` copies the
record (an alias result materialised), which is right but should be said.

**Fix.** List the initialisers with a definite type: a typed variable,
constant, field or element; a routine result; a character literal (`u8`); a
Boolean literal; an expression over those. Exclude integer and float literals,
untyped constants, string literals and `string[]` views.

### F10. `var` results need an assignment root that Nucleus forbids

§4: "A result is read-only unless declared `var`". Nucleus §9.4 and §10.4: a
call "is not an assignment root", so `pick(items, 0).value = 3` is invalid
whatever `pick` declares. The syntax for a `var` result is also unwritten
(`as var Entry`?), and so is the call-site rule that a ticket or a constant
can't be passed to a `var` parameter.

**Fix.** Admit a `var` result as an assignment root and as a `var` argument.
Write the result syntax. State that a `var` argument must be rooted in a
program variable, a local, or a `var` parameter.

### F11. `from` cannot name a lease or slot-holder, and should say so

A lease or slot-holder is a handle, not aggregate storage, and no alias may
point into a pool (D16). A routine returning an identifier or a handle needs
no `from`. The only `from` parameters are aggregate tickets and `var`
aggregates. D8 should say this now that handles exist, or a reader will try
`sub first(var h as nodes) as Node from h`.

### F12. Expression blocks (O3) against the move and failure rules

If a block can appear inside an expression, then: `else fail` and `handle`
would occur inside expressions, which §14.4 forbids; moves inside `and`/`or`
operands are forbidden by §5.8, so a block in a right operand that moves must
be rejected; `return` inside a block inside an argument list leaves fresh
temporaries from earlier arguments to be freed by U5's rule; and a `match`
used as an expression needs every arm to end in `result`. These are solvable
but each is a rule the spec must state. Decide O3 before writing `match` as
an expression into the book.

### F13. Routine values (O5) need a declaration-site marker for the stack check

§11: "a call through one counts as a forward call for the stack rule". The
check lives in the *callee's* prologue, and a routine is compiled before any
later statement takes its address, so the compiler can't know to emit it.

**Fix.** A routine whose address may be taken must be forward-declared, or
declared with a marker, so the prologue check is emitted. Its type must carry
`fails`, `from`, parameter modes and owning parameters.

### F14. Error codes are `u8`, `handle` needs a writable `u8` variable, and nothing says how variants or enumerations change that

Nucleus §14.6: `handle NAME` names an existing `u8` variable. With
enumerations in the inventory and variants decided, a reader expects
`fails Error` and `handle e` with `e as Error`. See I8 and N6.

---

## 3. Ergonomic oddities

### E1. `id` as a reserved word collides with the commonest field name

`record Customer; id as u16` is the first record half the audience will
write. With `id nodes` as a type prefix and `id(h)` as a conversion, `id`
must be reserved (Nucleus has one namespace and no contextual keywords).
Suggest `ref nodes` and `ref(h)`, or make `id` contextual after `as` and
before `(`, and say which.

### E2. The lease is an alias into a pool slot in all but name

A `var h as nodes` parameter can't be moved, overwritten or passed on except
as a lease, so the compiler can pass the slot's address and every `h.field`
is a direct record access. That is an alias to the record, made safe by the
lease rules. If it were spelled `var n as Node` (the record type), the same
routine would serve local records, program records, array elements and
leased pool slots, and a ticket `n as Node` could bind an owning local's slot
read-only. D16's "never an alias into a pool slot" would become "only a lease,
whose rules make it safe". This removes a whole parameter kind from the book.

### E3. `var` means three things on a parameter

`var p as Point` (may overwrite the whole record), `var h as nodes` (may not
overwrite `h` at all), `var l as nodes?` (may overwrite `l`). A Pascal
programmer reads `var` as "may assign to it" and the lease breaks that. E2
resolves it.

### E4. Traversal needs `while true`, `match` and `return`

`total()` in §8 is twelve lines for a sum because `is some` was removed and
`match` is a statement. A condition-position binding, `while p is some(i)`
and `if p is some(i)`, in the manner of Rust's `while let`, would halve every
loop in §8 and is the form a BASIC programmer can read. One compiler path:
it is `match` with one arm and an implicit `exit`.

### E5. Plain pool-name type owns; plain record type borrows

`sub sink(n as nodes)` consumes; `sub show(p as Point)` borrows. The reader
needs to know `nodes` is a pool to read the signature. `move` at the call
site mitigates it, but `sink(make())` has no `move`. Consider requiring the
word at the parameter too, or accept and document.

### E6. A program variable's node is unreachable without `match`

Open question 1 in §12. The idiom "move into a local, lease, move back" is
three statements to call `bump` on `head`. E4 and F4 together make
`if head is some(h)` with a frozen subject and a direct binding the answer;
then `bump(h)` is a lease on it.

### E7. `new` takes every field positionally

`new nodes(5, "five", none, none)`: a ten-field record is ten arguments and
the handle fields are always `none` at creation. Allow trailing fields to be
omitted and zeroed, or named fields. Also note `new` passes a string literal
as an argument, which Nucleus §13.4 forbids; Basie must admit string literals
as arguments and initialisers (N5).

### E8. No arrays of arrays, no open arrays

Nucleus §6.2: an array element can't be an array; a concrete array parameter
has one exact length. `DIM grid(8,8)` becomes a record of eight arrays, and a
routine over `u8[16]` can't take a `u8[32]`. Only `string[]` is open. A
feature-complete language needs `T[][]` or `T[8,8]`, and an open array
parameter `T[]` carrying its length as `string[]` carries its capacity.

### E9. Strings can't be built, returned, compared or passed as literals

Nucleus §6.8: no append, slice, comparison or `length` assignment; `string[]`
can't be a result; a literal can't be an argument. The inventory puts "string
building" under *important*, not *essential*, and formatting into libraries.
A BASIC programmer's first program prints a number and joins two strings.
Minimum set: literal arguments, `=`/`<>`/`<` on strings, append of a string
or byte, truncate, slice to a `var` destination, integer and `f32` to text,
text to integer and `f32` (failable), and a `print` family over the console
service. See N3.

### E10. Case sensitivity

Nucleus is case-sensitive (§3.5). Both BASIC and Pascal are not. Decide and
say it on page one of the book; it will be the first error every reader hits.

### E11. Named-field access on identifiers that may be stale traps rather than being refused

`id nodes` (non-optional) traps with `stale-handle`; `id nodes?` must be
matched. A reader won't see why the non-optional form exists, since the slot
can die underneath it anyway. Say that `id nodes` is for the many calls where
the caller has just matched, and that the trap is the contract.

### E12. Identifier equality is undefined

Graph code needs "is `i` the same node as `j`". Nucleus has no alias
comparison; identifiers are values and should compare with `=` and `<>`
(index and generation), and the spec should say so.

### E13. Nested declaration prefix, `for` counters as separate locals, no `repeat`

Nucleus's declaration prefix, counter-as-declared-local and lack of
`repeat ... until` are each a small surprise; together they make a `for`
loop four lines of ceremony. F3 covers the first two; the inventory already
has `repeat`.

### E14. Compile-time `assert` exists; run-time `assert` doesn't

Nucleus §8.7 has `assert` over constants only. A run-time assertion that
traps with a reason is a one-helper feature and belongs in a checked language.

### E15. Enumerations are listed, not designed

Syntax, conversion to and from integers, ordering, `for` over an enumeration
and use as an array index are all unwritten, and D15's exhaustiveness check
depends on them.

### E16. Everything a complete language needs that no document mentions

In priority order: open arrays and arrays of arrays (E8); strings and
formatting (E9); modules with visibility (the inventory has "imports", not
namespaces or `private`); enumerations (E15); error types (F14); run-time
`assert` (E14); generics over pools (§12 question 3: the realistic answer is
"a routine over `id P` works for one pool", so recommend one pool per record
type as the idiom and no generics in 1.0); interfaces or polymorphism
(variants and `match` are the substitute; say so); routine values (O5); bit
fields and packed records (say no; `and`/`or`/shifts suffice); default
parameters (O6, deferred); `const` parameters (no, D17 says read-only is the
default).

---

## 4. I/O assessment and recommendation

### I1. Soundness and sufficiency for CP/M: files

Services with Basie signatures are the right boundary, but the proposal does
not say where a file's state lives. Under CP/M a file is an FCB of 36 bytes
plus a 128-byte record buffer. Two designs: a fixed table in the runtime
(`u8` handles, a profile limit of, say, four open files, 656 bytes always
present when files are used) or a program-declared opaque record
(`var f as File`) passed to every service as `var f as File`, so the program
pays for exactly the files it declares and memory stays "declared in the
source". The second fits Basie. It needs an *opaque* type kind: a `File` can't
be copied (two FCBs for one file corrupt the directory on close), can't have
its fields named, and must be closed before its scope ends or at program exit.
That is a lifetime rule like an owning handle's; say whether a `File` is freed
automatically (closed) at scope exit.

Needed and not listed: random read and write by record number (CP/M 2.2
functions 33 and 34; Nucleus had `seekStorageOutput`), file size, delete,
rename, directory search with a pattern, user number and drive selection, and
exact lengths (CP/M files are whole 128-byte records; a text file ends at
Control-Z; a binary file's length must be carried in the file). Skate's staged
open/write/commit model exists only on a host provider; on real CP/M a half-
written file is what you get, so answer open question 2 with "plain sequential
and random CP/M files; commit semantics only on profiles with a provider".

### I2. Console

Nucleus's `readInputByte`/`writeOutputByte` go through BDOS 1 and 2, which
expand tabs, echo, honour Control-S and abort on Control-C. A game or an
editor needs BDOS 6 (direct console I/O) and a "key waiting" poll (BDOS 11).
The proposal's `readLine` and `writeText` are right for programs; add
`keyPressed()`, `readKey()` (no echo, no wait semantics defined) and
`writeRaw` for the direct path, and say which BDOS function each uses on each
CP/M version, because the command channel (I4) can only be carried over the
raw path.

### I3. Command line

The DMA move at startup preserves `$0080` and the default FCBs. Services:
`commandTail(var text as string[])` and `argumentFile(n, var name as
string[])` for the two CCP-parsed FCBs. State that CP/M 2.2 upper-cases the
tail (cpm-target §6).

### I4. The command channel on a plain CP/M machine has no provider

Skate's framing (`ESC ~` plus CRC) works where a Triptych terminal or a host
emulator interprets it. On a stock CP/M system with a serial terminal, the
frames print as garbage. Full-screen CP/M programs of the period handled
this with a terminal-type choice (Turbo Pascal's `TINST`, WordStar's patch
area). The proposal needs a "terminal" service group that maps clear-screen,
cursor-position, attribute and bell onto a terminal description selected at
link time or run time (ADM-3A, VT52, VT100/ANSI, Kaypro, Osborne), with the
command channel as one more terminal type. Without this, "the same program
drives a Triptych terminal, a host emulator or a test harness" is true but
"or a real CP/M machine" is not.

### I5. TEC-1: the display is multiplexed by software

The TEC-1's six seven-segment digits have no latch per digit: the program
selects one digit and one segment pattern on two ports and scans them
continuously; stop scanning and the display goes dark. `writeDisplay(digits)`
as a one-shot service can't work. Three shapes: a blocking `showDisplay(var
digits as u8[6], ticks as u16)` that scans for a period (which is how most
TEC-1 monitor routines work), a `scanDisplayOnce()` the program's main loop
must call often (fragile), or an interrupt-driven scan from the TEC-1's
optional 4049 clock on NMI, which the memory-safety claim excludes ("Interrupts
and concurrency: Basie 1.0 has neither in source", but the runtime may use
one). Pick the first for 1.0 and state the second as an option. Keypad: the
74C923 encoder is polled on a port and raises an interrupt the runtime can
ignore; `readKeypad()` returning `u8?`-style "no key" needs an optional
scalar or a sentinel; use a `key as u8` with a named constant. Speaker: tone
generation is a timed loop in the runtime, which is fine. Timing: a
`delay(ms)` service calibrated per profile, and no clock on a stock TEC-1.

### I6. The raw escape hatch is answerable now

On a TEC-1 and its relatives, the hobbyist's reason to program is the new
board plugged into the bus: an LED matrix, a GLCD, a sound chip. Requiring a
runtime-library assembly blob for every one of them, before a line of Basie
can touch it, removes the audience the bare-machine profile exists for. On
those machines there is no MMU, no DMA controller and no operating system to
corrupt, so `IN`/`OUT` can't break the memory-safety claim: they can't write
program memory. (A port that controls bank switching is the exception; name
it per profile.) Peek and poke are different: they break every claim and
should never exist; anything that needs memory access is a service.

Recommendation: bare-machine profiles provide `inPort(port as u8) as u8` and
`outPort(port as u8, value as u8)` as ordinary services; CP/M profiles don't
provide them (a compile-time error, as §3.2 already provides). No profile
option, no "outside the claim" marker, because the claim is not affected.

### I7. Honest comparison with the direct approach

| | Direct (`bdos(fn, de)`, `in`/`out`, addresses) | Services (proposal) |
| --- | --- | --- |
| Call cost | 5–7 bytes inline, no helper | 3-byte `CALL` plus a blob, tree-shaken; same per call for the common case |
| Memory safety | Lost: a BDOS read writes 128 bytes at the DMA address, and the program would need an address | Kept: the runtime checks every alias's extent |
| Portability | None across CP/M 2.2, 3, TEC-1, Triptych | Chosen at link time by the blob library |
| New hardware | One line of source | A runtime blob in assembly, or I6's port services on bare machines |
| Testing | The host must emulate the BDOS or the ports | Substitute providers, as Nucleus and Skate do |
| What the compiler must know | BDOS function numbers, FCB layout, DMA; or nothing, if `bdos()` takes a buffer alias (unsafe) | A signature table it already has for helpers |

The direct approach's only advantage is the hobbyist's one line of `OUT`,
and I6 gives that back where it is safe. Adopt the proposal with I1–I6.

### I8. How services report errors

Keep `fails` with a `u8` code for 1.0, as Nucleus does, and predeclare the
codes as named constants per service group (`fileNotFound`, `diskFull`,
`endOfInput`, `noProvider`, ...), because `handle` binds a `u8` variable and
`else fail` propagates a byte in a register; both are one instruction. Do not
report errors as variants: a variant result makes every service call a
`match` and puts a tag byte and payload where a byte sufficed. If F14/N6 later
adds `fails Error` with an enumeration type, the service codes become that
enumeration's members with the same values, and nothing in the runtime
changes. Say now that codes are stable across profiles and that an unsupported
operation on a profile fails with one shared code rather than being absent.

### I9. Loose ends in the proposal text

- §3.1 "withdraws the port built-ins listed in revision 1 of the feature
  inventory": the current inventory lists none, so the reference dangles.
- §3.2 "the compiler learns each service's signature from the helper table":
  the helper table numbers blobs; it does not currently carry Basie
  signatures (parameter types, `var`, `fails`). Object-format §10 must grow a
  signature record, or the compiler must have a built-in service table per
  profile, which is what Nucleus did.
- "The runtime ... must restore the DMA address to its own buffer before
  returning" (memory-safety §2.1) is the right rule; add "and must never
  leave an alias's address in the DMA register across a return".

---

## 5. Stale text

| ID | File and line | Text | Why stale |
| --- | --- | --- | --- |
| S1 | design-decisions.md:274 | `next as own? nodes` (D14 example) | `own` removed by D22; should be `nodes?` |
| S2 | design-decisions.md:292 | `var list as own? nodes` | Same |
| S3 | design-decisions.md:341 | "a lease on a handle (`var h as own nodes`)" | Same; `var h as nodes` |
| S4 | design-decisions.md:353 | "The memory safety design is to be revised to match" | Done; revision 3 exists |
| S5 | design-decisions.md:363–364, 370 | `own nodes`, `own? nodes`, "unless the parameter's type is `own`" (D17) | Same as S1 |
| S6 | design-decisions.md:391 | "A non-optional `own` is always a local" (D18) | Same |
| S7 | design-decisions.md:511–543 | O1 "Exclusivity and `inout`" | Superseded: `inout` is `var` (D17); exclusivity is moot for program storage (never freed) and for pools (no aliases, D16). Mark resolved: "no exclusivity; overlap through globals is visible through mutation and never a lifetime hazard" |
| S8 | design-decisions.md:545–566 | O2 "Pools with owned handles" and its five problems | All five are decided (D16, D18, D19, D22; memory-safety §5.2, §5.3, §5.10, §5.11). Mark resolved and point at the sections |
| S9 | design-decisions.md:9 | `../nucleus/docs/specification.md` | Path resolves to `basie/nucleus/...`; should be `../../nucleus/docs/specification.md`. Also io-and-effects.md:5 and build-pipeline.md:9 |
| S10 | feature-inventory.md:53, 87–126, 154, 178, 184, 195, 224, 239 | `select` throughout | D15 named it `match`; the inventory still documents `select` and its examples use it |
| S11 | feature-inventory.md:57 | "Ownership: pools, `own`, `id`, `new`, `give`, flow check ... retirement" | `own` and `give` removed (D19, D22); "retirement" is "freeing" (D18); `move` missing |
| S12 | feature-inventory.md:169 | "an aggregate field is bound as an alias ... read-only unless the subject is a `var` parameter" | Contradicts memory-safety §5.5 (identifier bindings) and D16 for pool subjects; see U7 |
| S13 | feature-inventory.md:179 | "binding owned fields by move, except through `take`" | `take` removed (D19) |
| S14 | feature-inventory.md:190 | "`own? T` behaves as a variant with cases `some(h)` and `none`" | `own?` is `nodes?` |
| S15 | feature-inventory.md:195 | "the testing syntax that memory safety leaves open (its Section 11, question 3)" | Revision 3's §11 is "Later" and §12 has three different questions; the test syntax is decided (D15) |
| S16 | README.md:78 | "pools, owned handles, the `frees` effect and stack bounds" | `frees` was abandoned in D16 |
| S17 | README.md:61 | "free: Releasing a pool slot ... Mostly automatic" | D18: always automatic |
| S18 | README.md:62, philosophy.md:76–78 | "pool: A fixed array of records addressed by index"; "Dynamic data will live in fixed pools addressed by index ... later" | Pools are decided and addressed by handles, not indices |
| S19 | philosophy.md:141–144 | "Conflicting access through globals may need run-time checks once pools can free storage" | D16 removed the need; no such checks exist in revision 3 |

Also: io-and-effects.md:46 "revision 1 of the feature inventory" (I9);
memory-safety.md §5.5 defines `id(h)` only for non-optional owning handles
while §8 uses `id(head)` on a `nodes?` and `id(i.next)` through an identifier
(define `id` of `nodes?` as `id nodes?`); memory-safety.md §5.8's loop
sentence (U8); and cpm-target.md:238's trap list will need `none-handle` if
F1 chooses the conversion.

---

## 6. Decisions still needed, in priority order

1. **N1. Slot-holder arguments** (U1, U2): locations never inside a slot, or
   a checked identifier-rooted kind. Everything in §5.7 and §5.9 depends on
   it.
2. **N2. The owner link** (U4): who writes it, what a root looks like, and
   the cost of the store on every move. Without it the cycle check is a
   sentence, not a mechanism.
3. **N3. Strings** (E9): which operations are in the language, which are
   library, how a routine returns text, whether literals are arguments, and
   the number-to-text and text-to-number set including `f32` (format,
   precision, failure on parse). This is the largest hole for the book's
   first chapter.
4. **N4. Declarations anywhere, block scope, and loop-declared counters**
   (F3, E13): every pattern in the memory-safety design assumes it.
5. **N5. Optional to non-optional** (F1): `match move x case some(n)` or a
   trapping conversion. Without one, owning parameters are unusable.
6. **N6. Error values** (F14, I8): `u8` codes for 1.0 with named constants,
   and whether `fails T` over an enumeration is reserved for later.
7. **N7. The lease's spelling** (E2, E3): `var h as nodes` or `var n as
   Node`. The second collapses a parameter kind and answers open question 1.
8. **N8. Condition-position bindings** (E4, E6, F4): `if x is some(i)` and
   `while x is some(i)`, with the subject frozen when it is a local.
9. **N9. Arrays** (E8): arrays of arrays or two-dimensional arrays, and open
   array parameters.
10. **N10. The failure behaviour of `new` versus calls** (F2) and the handler
    body's flow state.
11. **N11. Fresh temporaries** (U5): where they live and when they die, for
    `match` subjects and lease arguments.
12. **N12. Variants with owning payloads** (U7): binding, construction,
    overwrite, pool-field subjects.
13. **N13. Numeric rules with signed types** (F6, F7, F8): exact constant
    evaluation, the exact widening table, unary minus on unsigned, `mod`
    sign, signed shifts, `for` counter types, `f32` literal syntax and
    compile-time folding with the runtime's rounding.
14. **N14. The I/O service set for 1.0** (I1–I6): file state as an opaque
    record, console raw path and polling, terminal types, TEC-1 display
    model, port services on bare machines, the service signature table.
15. **N15. `id` as a reserved word** (E1): rename or make contextual.
16. **N16. Enumerations** (E15): syntax, conversions, use as array index.
17. **N17. Modules and visibility** (E16): the inventory's "imports" without
    namespaces or `private` is not enough for a library of string and
    formatting routines in Basie source, which the inventory's §5 item 3
    relies on.
18. **N18. Case sensitivity, run-time `assert`, identifier equality,
    `repeat`** (E10, E14, E12, E13): small, but each appears in chapter one
    of a tutorial.

Open items O3 (expression blocks), O5 (routine values) and O6 (defaults)
can stay open for 1.0 provided F12 and F13 are recorded against them; O1 and
O2 should be closed (S7, S8); O4 (arenas) is correctly deferred.
