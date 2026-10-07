# Version 2 plan

Roadmap step 72. Basie 1.0's specification is frozen; this plan proposes
what version 2 adds, in what order, and what it costs, so that each feature
can be admitted by a design decision with its specification and conformance
changes. It builds on the [feature inventory](feature-inventory.md) §4 and §6,
design decisions D15, D24, D26 and O3 to O5, [memory safety](memory-safety.md)
§11 and the [stretch goals](stretch-goals.md) brief.

## 1. Where version 1 stands

At step 71 the native toolchain compiles the whole of Basie 1.0 that the
conformance corpus and the claimed programs use, byte for byte as the
reference compiler does (D45), with a few constructs still refused (limits
§5.1, "Constructs compiled"). Its capacities are measured (limits §5.1): the
specification's minimums hold, with a source area of 22.5K beside a
`BASIE.COM` of 25,441 bytes and a 2,560-byte overlay area, 28,001 bytes in all.

That total is the binding constraint. D43 sets a 26K target and a 28K limit
(28,672 bytes) and forbids crossing 30K; version 1 ends 671 bytes under the
limit. The headline version 2 features are estimated at 2.7 to 4.2K of compiler
(§3), more than the margin, so version 2 begins with room.

## 2. Room first

No version 2 feature lands until an increment before it recovers at least its
measured cost. The sources of room, in the order to try them:

1. **Compression passes** over the resident image. Step 68's census found the
   largest routines (`AC_LABEL`, `BL_WRITE`, `RO_ARGS`, `GX_TRIM`, `RO_ASGN`)
   and the repeated sequences; 68.5 took the first 32 bytes. A systematic
   pass, file by file, counting a pattern's sites before rewriting any one
   of them (`deno task census:basie`), is expected to find 0.5 to 1K.
2. **Declaration code into overlays.** Record, pool, constant and type
   declarations run once each and only at top level; moving them out of the
   resident image costs an overlay load at the first declaration of each kind,
   which the user has asked to keep rare. Only code that a typical build calls
   once may move; profiles (step 68) decide it.
3. **A second overlay phase** ([overlay phase exploration](overlay-phase-exploration.md)):
   the statement compiler and the declaration compiler in separate overlays,
   swapped per top-level declaration. Larger saving, but a load per routine;
   measured on the corpus before adoption.
4. **The limit itself.** D43 allows a limit up to, but never at, 30K. Every
   byte above 28K comes out of the source area, now 22.5K, and so out of the
   largest compilable part and routine (limits §5.1). A raised limit needs its
   own decision weighing those losses.

Each feature below states its estimated cost; its increment measures the
real cost, and the room it needs is found before it starts.

## 3. Features

### 3.1 Enumerations

A closed set of named values, a distinct type with no implicit conversion to
or from integers.

```basie
enum Direction
    north
    east
    south
    west
end

var heading as Direction = Direction.north

select heading
case north, south
    vertical()
case east, west
    horizontal()
end
```

- **Representation:** a byte, the members numbered from zero in declaration
  order; at most 256 members. A program variable without an initializer is
  its first member, as zero storage gives.
- **Names:** a member is written `Direction.north`, qualified, so that members
  of different enumerations never collide and shadowing (§5.6) is not
  disturbed; in a `case` whose subject is an enumeration, the member alone.
- **Conversions:** `u8(d)` gives the member's number; `Direction(n)` converts
  a number, trapping when it names no member, as a narrowing conversion does.
- **Selection:** `select` over an enumeration is checked for exhaustiveness
  when it has no `case else`: a missing member is a compile-time diagnostic,
  so adding a member finds every selection that must handle it.
- **Equality** `=` and `<>` only; no ordering, arithmetic or ranges, which are
  Pascal's ordinal model and not proposed.
- **Cost:** estimated 0.6 to 1K (the inventory's 1.7 to 2.7K covers
  enumerations and variants together).

### 3.2 Typed failure codes

D26 in full: `sub open(name as string[]) fails FileError` names the
enumeration its codes come from; `fail FileError.missing` and `fail missing`
are checked against it, and `handle` arms select on it as on an enumeration.
An unqualified `fails` keeps today's `u8` codes. Estimated 0.1K once
enumerations exist.

### 3.3 Variants

Alternatives carrying differently typed payloads, the inventory's §6:

```basie
variant Shape
    circle(radius as u16)
    rect(width as u16, height as u16)
    empty
end

var s as Shape = Shape.rect(4, 5)

select s
case circle(r)
    area = 3 * u32(r) * u32(r)
case rect(w, h)
    area = u32(w) * u32(h)
case empty
    area = 0
end
```

- **Representation:** a tag byte followed by the largest case's fields; no
  allocation. An enumeration is a variant whose cases carry nothing, and the
  two share the compiler's code.
- **Construction** by `Shape.rect(4, 5)`, the payload in declaration order;
  assignment replaces the whole value.
- **Selection** binds an arm's payload as read-only names, one level deep: no
  nested patterns and no guards. Exhaustive as for enumerations.
- **Owning payloads** (memory safety §11): a handle in a payload binds as an
  identifier, not an owner; construction moves an owner in; overwriting a
  value frees the old payload's owners through a descriptor selected by the
  old tag, which the runtime's `OBJ_FREE` gains (the helper table's version
  rises); a variant with an owning case is an owning type, so local variants
  are freed at their scope's end as local records are.
- **Cost:** estimated 1.1 to 1.7K, the larger part of the inventory's figure,
  and a runtime helper change.

### 3.4 Expression blocks and `select` as an expression

O3: a block that yields a value with `result`, `return` still leaving the
routine; first as `select` used as an expression.

```basie
var cost as u16 = select s
case circle(r)
    result r * 3
case rect(w, h)
    result w * h
case empty
    result 0
end
```

- Every path through every arm must reach `result` with a value of one type;
  arms that trap or `fail` need none. The single pass checks it as it checks
  that a routine returns.
- The value is left in the registers a scalar result uses (A, HL, DEHL), so
  the join needs no temporary; an aggregate result is not proposed.
- **Cost:** estimated 0.5K.

### 3.5 Routine values

O5: passing an operation, such as a comparison to a sort, without closures.

```basie
type Order = sub(a as Item, b as Item) as boolean

sub sort(var items as Item[], before as Order)
    ...
    if before(items[j], items[i])
    ...
end

sort(stock, byPrice)
```

- A routine value is a non-capturing routine's address, two bytes; a type
  names its signature, including `fails` and any `from` clause (memory
  safety §11). Only routines declared at top level may be values.
- A call through a value is indirect (a small runtime helper, `CALL (HL)`'s
  equivalent), and counts as a call to a forward routine for the stack rule:
  the callee's need is unknown, so the call checks the stack as recursion
  does.
- A routine whose address is taken by live code stays live in the linker
  already (O5); the object format needs no change.
- Values may be parameters, locals, fields and program variables; there are
  no closures and no values that capture a frame.
- **Cost:** estimated 0.5 to 1K, and one runtime helper.

## 4. Order of work

Each feature is one roadmap step, run as version 1's were: the reference
compiler and the specification first, conformance programs that pass on the
reference toolchain, then the native compiler, byte for byte (D45), with the
D43 cycle and its census at every increment.

| Step | Work | Depends on |
| --- | --- | --- |
| V2.0 | Room: compression and overlay increments to at least 1.5K below the limit | — |
| V2.1 | Enumerations, exhaustive `select` | V2.0 |
| V2.2 | Typed failure codes | V2.1 |
| V2.3 | Variants, owning payloads, `OBJ_FREE` by tag | V2.1, room |
| V2.4 | `select` as an expression, then expression blocks | V2.3 for variant arms |
| V2.5 | Routine values | room |
| V2.6 | The book's version 2 chapters, the release | all |

Room is found again before V2.3 and V2.5, the two largest.

## 5. Tests

- Conformance programs for each feature, accepted and refused, in the
  reference corpus first.
- Native equivalence: each feature's claimed programs, linked and run, and its
  refusals refused alike.
- The stress generator (`tests/stress_test.ts`) extended with each feature:
  random enumerations in `select`, variants constructed and selected,
  `select` expressions and routine values passed to sorts.
- Programming Basie gains chapters, verified by its script and by
  `tests/book_test.ts`.

## 6. Open questions

1. Whether a variant's payload may be bound writable (`case circle(var r)`),
   and what that does to the alias rules.
2. Whether enumeration-indexed arrays (stretch goals) come with V2.1 or wait.
3. The syntax of routine value types: `type` declarations, or the signature
   written in place.
4. Whether a `select` expression may yield an aggregate, by a hidden local.
5. How much of §2's room comes from overlays rather than compression, given
   the preference for few overlay loads.

## 7. Not in version 2

Arenas (O4), default parameter values (O6), generics (D23), `repeat` and a
general `loop`, precompiled libraries, checked slices and module interfaces
stay in the [stretch goals](stretch-goals.md) for evaluation, as do the
syntax proposals there (`mut`, `fun`, `:` and shadowing).
