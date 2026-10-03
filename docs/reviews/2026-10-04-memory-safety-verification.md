# Verification of memory-safety revision 5 against review 3

- Date: 2026-10-04
- Documents: memory-safety.md revision 5; review 3 (R1–R18); design-decisions.md
  D27, D30, D31 (with D15, D16 for context); cpm-target.md §4.1; object-format.md
  §5 and build-pipeline.md §6.3 for the self-reference question.
- Scope: a verification pass, not a fourth review. Each of R1–R18 was checked
  against the revision 5 text, then the new text was attacked on the eight points
  listed in the brief.

Programs use revision 5 syntax. "S(x)" is the slot owned by `x`.

## 1. Verdicts on R1–R18

| ID | Verdict | Note |
| --- | --- | --- |
| R1 | applied | Owner word in §5.6; §5.7 admits fields of `var` owning-aggregate parameters; §5.12 rewritten. One wording gap (§2.1 below): only the parameter itself is said to pass its word on. |
| R2 | applied | §5.8 statement rule covers access paths, destinations, lease arguments and `select` subjects. The scalar-read exception depends on an evaluation-order fact the document does not state (§2.2). |
| R3 | applied | §5.9 and the cost table. The cycle walk should be stated to skip `none` too (§2.3). |
| R4 | applied | §5.10 link-equals-parent test, root freed without the test, withdrawn fields never read, `new` stores initialising. Two wording gaps (§2.3). |
| R5 | applied | §5.9: parameter binding, `select move` binding and temporaries write 0. |
| R6 | applied | §5.6: a ticket binds a node as a lease; `show(h, eat(move h))` is the worked error. D30 agrees. |
| R7 | applied | §7: self-recursive routines forward-declared, prologue pair after the code via self-reference. The object format supports it (addend in the reference record, references after the blob bytes), so unbuffered routines work. Enforcement wording missing (§2.6). |
| R8 | applied, limited | Trailing arguments omitted and zeroed. A record whose owning array is not its last field is still unconstructible: `record Tree  kids as trees?[4]  key as u16  end` has no `new trees(?, 1)`. Say that such a field must come last, or admit `none`. Not a safety issue. |
| R9 | applied | D31: indexes are `u8`/`u16`; signed index converts with a trap; signed `.length` is a mixed-sign error. |
| R10 | applied | §5.3: conditions, `and`/`or`, `handle` bodies all covered. |
| R11 | applied | §5.3: `new?` evaluates no argument when full; moved local is **may** on both arms. |
| R12 | partly applied | §5.6 and the glossary say "local or parameter"; §5.5's lease bullet still says "the caller's own owning local", and §9 says "Leasing from anything but a local". Change both to "local, parameter or temporary". |
| R13 | applied, but unsound | §5.6 defines `id(n)` from the owner word. See §2.4: the owner word can name a slot of a different record type. |
| R14 | applied | §5.4: hidden temporary, counted in the frame. |
| R15 | applied | §5.1: four bytes before the record. |
| R16 | applied | §5.11: no range check, with the reason. §5.4 still says "about 165 T-states" while §10 says "about 150"; pick one. |
| R17 | applied | §5.6 "Results". Say also what link a store through a `var` result rooted in a lease writes, and what owner word such a result carries when passed on (§2.1). |
| R18 | applied | §5.9, §8 and the cost table. |

## 2. Regressions in the new text

### 2.1 The owner word (R1): wording gaps, no unsoundness found

- **Passed on.** "A parameter passed on to another such parameter passes its
  own owner word" covers `bump(n)` from inside `attach(var n as Node)`, but
  not `fill(n.kids)` with `sub fill(var kids as nodes?[])`, nor `poke(n.sub)`
  with a `var` record parameter. The general rule "the slot's address when the
  argument ... lies inside [a leased node]" cannot be applied by `attach`, which
  does not know whether `n` is leased. §5.7 says it for slot-holders only.
  Change to: "An argument that is a `var` parameter, or a field or element of
  one, passes that parameter's owner word."
- **Field of a `var` aggregate as a slot-holder.** Correct: the word is the
  enclosing slot, which is a root nothing else can reach during the call.
- **Temporary.** Correct as written: a temporary is "a leased node", so the word
  is the temporary's slot. It must be, since the temporary's cascade at the end
  of the statement pushes only children whose link equals that slot.
- **Result rooted in a lease** (`bump(first(h))` with `from n`): nothing says
  the argument carries `h`'s slot as its word. Add it to §5.6 "Results".

### 2.2 The statement rule's exceptions (R2)

The rule is sound for every shape in R2. Two notes:

- The exception for "reads of scalar fields" admits `var v = eat(move x) + x.value`.
  It is sound only because a single-pass compiler evaluates operands in source
  order and the flow check sees `x` as moved when it reaches `x.value`. Neither
  fact is written down. Add to §5.8: "Operands and arguments are evaluated in
  source order, and the flow state changes at the move, so a direct use that
  follows a move in the same statement is rejected by the flow check."
- The exception "a plain `x = ...` with no other direct use of `x`" rejects
  `x = move x.next` (pop the head of a locally held list), which is sound under
  the order of overwrite. The `select move` workaround exists; no change needed
  unless expressiveness matters here.

### 2.3 The link test in the cascade (R3, R4)

- **`new`'s stores.** §5.9 says the link written is the destination slot's
  address "when the destination is a field of a slot reached through an owner,
  an identifier, or a lease's owner word; it is 0 otherwise." A field store made
  by `new nodes(v, "", move head, none)` is none of the three, so the pedantic
  reading writes 0, and the cascade that later frees the head skips its `next`
  child: the rest of every pushed list would leak. Add "or a field of the slot
  that `new` is initialising" to the list.
- **Freeing by overwriting a field.** `i.next = none` frees a child whose link
  is `i`'s slot, not 0, and it is not "freed from a local, parameter, temporary
  or local aggregate". Change §5.10 to: "The slot at the top of a cascade,
  whatever owned it, is freed without the test; only its descendants are
  tested."
- **The walk on `none`.** `i.next = none` at a list tail, or `i.next = move q.next`
  with `q.next` empty (as in §8's `removeAll`), stores the handle 0. A walk that
  compares each link with the stored handle before testing for the root traps
  `ownership-cycle` on a valid program. Add "non-`none`" to "Before storing
  handle *b*".

### 2.4 `id(n)` inside a lease (R13): unsound

The owner word is the slot's address whenever the argument lies inside a leased
node, including a nested record of a different type. `id(n)` then builds an
identifier of `n`'s pool from a slot of another pool:

```nucleus
record Sub
    x as u16
end
record Node
    value as u16
    sub   as Sub
    next  as nodes?
end
pool nodes as Node[8]
pool subs  as Sub[8]

sub poke(var s as Sub)
    var i = id(s)              // id subs?, built from the owner word: a nodes slot
    select i
    case some(j)
        j.x = 0                // Sub's layout applied to a Node slot: claim 5
    case none
    end
end

sub bump(var n as Node)
    poke(n.sub)                // n.sub lies inside the leased node: word = S(h)
end

sub go()
    var h = new nodes(1)
    bump(h)
end
```

The generation check passes, since the generation read is the Node slot's. The
same identifier can be stored in an `id subs?` field and used after `poke`
returns. Fix, in §5.6 "Identifiers inside a lease": "`id(n)` gives the node's
identifier when the owner word equals the address of `n`, and `none` otherwise"
(one 16-bit compare), and "It is an error if the record type has no pool or
more than one." Alternatively forbid passing a nested record of a `var`
owning-aggregate parameter to a `var` record parameter whose type has a pool;
the run-time compare is smaller and keeps D30's point.

### 2.5 The prologue pair through a self-reference (R7)

Sound and implementable: object-format §5 puts the addend in the reference
record and the references after the blob bytes, so a streaming compiler can
record "site 1, self + code length" when the routine ends. No change.

### 2.6 Self-recursive routines must be forward-declared (R7)

The rule is right but has no enforcement sentence. If the compiler registers a
routine's name when it reads its header, an unforward-declared `sub f() ... f()`
compiles with no capacity check, which is the hazard the rule exists to prevent.
Add to §7: "A call to the routine being compiled is an error unless that routine
was forward-declared."

### 2.7 Frame size as the largest live set (R7): a double free

§5.3 says an owning local is freed "at the end of its block, on every exit path"
and that "a routine's exits share one epilogue that frees its owning locals".
§7 lets side-by-side blocks share frame space. Together:

```nucleus
sub f(flag as boolean)
    if flag
        var a = new nodes(1)   // frame offset 0, freed at the end of the arm
    else
        var b = new nodes(2)   // the same offset 0, freed at the end of the arm
    end
end                            // the epilogue frees offset 0 once for a and once for b
```

Even without sharing, a block-end free followed by the epilogue's free of the
same local frees twice unless the first free leaves `none` behind. Nothing says
it does; §5.8's "a move stores `none`" does not cover frees. Add to §5.3:
"Freeing through an owning local, temporary or local aggregate stores `none`
into it, so the epilogue can free every owning frame slot without knowing
which block last used it." That one sentence makes both the shared epilogue and
the shared frame space safe.

### 2.8 Tickets that lease nodes (R6)

No hole found. A ticket has no owner word and cannot store, pass a field as a
slot-holder, or pass the node on to a `var` parameter; `select` on its owning
fields binds identifiers whose walks end at the leased root. Two wording points:
`id(n)` is defined only for `var` parameters, so say that a ticket cannot form
one (a read-only routine that needs an identifier takes `var` or `id nodes`);
and D16's fourth bullet still says only a `var` record parameter binds a node.

## 3. Consistency

- **D27:** §5.3 matches (trap `pool-full`; `new?` returns `none`); cpm-target
  §10 lists `pool-full`.
- **D30:** §5.6 matches, including tickets, the statement rule and the owner
  word. D16's bullet about `var` parameters is stale against it.
- **D31:** consistent. Revision 5's header lists D8, D15–D30 as the decisions
  it rests on; add D31, which §6's bounds row now depends on.
- **cpm-target §4.1:** matches §7 word for word on who is checked, what the
  check tests and what goes into `LIMITS`.
- **Internal:** §6's row "Freeing storage a slot-holder writes to: Slot-holders
  are never inside a pool slot" contradicts §5.7, which now admits a field of a
  leased node. Change to "outside every pool, or inside a leased node whose
  owner is unreachable". §9's "Pool fields as slot-holders" bullet needs the
  same qualification. §6's "Ownership cycle: only identifier paths can form
  one" should match §5.9's "or a lease" wording, or §5.9 should say that a
  leased slot is always a root (it is: every lease comes from a local,
  parameter or temporary), which also lets the compiler skip the walk through
  `var` parameters altogether.

## 4. Freeze verdict

**Not ready.** Remaining changes: (1) §5.6 `id(n)` yields the identifier only
when the owner word equals `n`'s address, else `none`, and is an error for a
type with no pool; (2) §5.3 freeing an owning local, temporary or local
aggregate stores `none`; (3) §5.9 `new`'s field stores write the new slot's
address as the link; (4) §5.10 the top of a cascade is freed without the test
whatever owned it; (5) §5.9 the walk and the link write apply to non-`none`
handles only; (6) §5.6 a field or element of a `var` parameter, and a result
rooted in a lease, pass that parameter's owner word; (7) §7 a call to the
routine being compiled is an error unless it was forward-declared; (8) §5.8
operands evaluate in source order and the flow state changes at the move;
(9) §5.5 and §9 "local, parameter or temporary"; (10) §6 slot-holder and cycle
rows, §5.4/§10 identifier cost, header decision list, D16 bullet four.
