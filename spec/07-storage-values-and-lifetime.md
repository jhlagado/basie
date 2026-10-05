# 7. Storage, values, and lifetime


## 7.1 Scope

This chapter defines Basie's storage classes, object identity, copying, aliases, pools and handles, ownership, freeing, and the stack bound. It is the normative form of the [memory-safety design](../docs/memory-safety.md), revision 6, which gives the reasons and patterns. Chapter 6 defines the types, Chapter 8 the declarations and initializers, Chapter 10 the statement rule and the flow check, Chapter 11 handle selection, Chapter 13 parameters and calls, and Chapter 15 the traps.

The rules do not expose physical addresses, registers, stack positions or layouts, except where this chapter names an implementation structure to explain an observable rule. A conforming implementation preserves the source-level identity, lifetime and checking rules whatever its storage arrangement.

## 7.2 The safety property

A program compiled from Basie source cannot:

1. read or write outside the bounds of an object;
2. read or write storage after its lifetime has ended;
3. free storage twice, or free storage it does not own;
4. read storage it never initialized;
5. treat storage of one type as another;
6. overflow its stack into other memory; or
7. leak pool storage.

Each hazard is either rejected during compilation or detected during execution by a trap (Chapter 15): `bounds`, `stale-handle`, `ownership-cycle` and `activation-capacity`. The runtime library, the BIOS and the BDOS are trusted and outside the property. Basie 1.0 has no interrupts or concurrency in source.

## 7.3 Values, objects, aliases and handles

| Concept | Meaning |
| --- | --- |
| Scalar value | One value of a numeric type or `boolean`. Scalars are copied |
| Object | Storage of one type, in one of the storage classes of Section 7.4 |
| Subobject | A record field, an array element, or a byte of a bounded string, inside an object |
| Alias | An implicit, non-owning binding to an existing aggregate object or subobject, made by passing it to a parameter or returning it as a result (Section 7.7). Never stored, never seen |
| Handle | An explicit value that refers to a slot of a pool (Section 7.9). The only kind of reference that is a value |

An object has one identity throughout its lifetime. Writing into an object changes its contents, not its identity.

## 7.4 Storage classes

| Class | Declared by | Lifetime | Freed |
| --- | --- | --- | --- |
| Program storage | top-level `var` and aggregate `const` | the whole run | never |
| Activation storage | local variables, at any statement position | from the declaration to the end of the enclosing block | at the end of the block |
| Pool storage | the slots of a top-level `pool` | from `new` until freed | when its owner goes away |

There is no general heap: every byte a program uses is declared in the source with a size fixed when the program is linked. Arena storage, freed as a whole at the end of a scope, is planned for version 2 and is not part of Basie 1.0.

**Zero values.** Where Chapter 8 gives an object no explicit initial value, it starts at its type's zero value:

| Type | Zero value |
| --- | --- |
| Integer types | 0 |
| `f32` | +0.0 |
| `boolean` | `false` |
| Handle types `P?`, `id P?` | `none` |
| Record | every field at its zero value |
| `T[N]` | every element at its zero value |
| `string[N]` | the empty string |

The non-optional handle types `P` and `id P` have no zero value; Chapter 8 admits them only for parameters and initialized locals.

## 7.5 Program storage

A top-level variable owns one mutable object of program lifetime, and an aggregate constant one read-only object. Program objects exist before `main` begins, hold their initial values before any source can read them, and live until the program ends normally or by a trap. A pool is program storage as a whole, but each of its slots has its own lifetime (Section 7.9).

## 7.6 Activation storage

Each call of a routine creates a distinct **activation**, holding the routine's parameters and the local variables of its blocks. Two simultaneously active calls have distinct parameters and locals, including recursive calls.

**Lifetime.** A local's lifetime begins when execution reaches its declaration, which gives it its initial value (Chapter 8), and ends when control leaves its innermost enclosing block by any path: the end of the block, `exit`, `continue`, `return`, `fail` or a trap. A local in a loop body is created afresh on each iteration.

**Local aggregates.** A local may be a record, array, bounded string or array of arrays (design decision D8). It lives in the activation for the same block lifetime. A local record or array is zeroed in full unless it has an initializer; a local bounded string starts empty, and raising a string's length exposes zero bytes (design decision D25). Zeroing happens after the routine's activation-capacity check, if it has one.

**Freeing at block end.** When control leaves a block, every owning local of that block is freed (Section 7.12), and so is every owning handle inside a local aggregate of that block, found through its type's ownership descriptor. Freeing a local stores `none` into it, so a later shared exit path frees nothing twice.

An implementation may share storage between blocks that are not nested within each other. The **frame** of a routine is the largest total of locals and temporaries live at any one point; it is used in the stack bound of Section 7.18.

## 7.7 Aliases

An alias exists only as a parameter, for the length of a call, or as a routine result that the caller uses within one statement. It cannot be stored in a variable, field or array element, and source cannot observe or compare its address.

- An aggregate parameter without `var` is a **ticket**: a read-only alias. With `var` it is an alias through which the routine may write (design decision D17; Chapter 13).
- An aggregate result is read-only unless declared `var`, which is allowed only when it is rooted in a `var` parameter or in program storage. An alias rooted in a constant is never bound to `var`.
- A returned alias must be rooted in program storage, or in a parameter named in the routine's `from` clause; it is never rooted in the routine's own locals (design decision D8). At a call, the result lives as long as the arguments passed for the `from` parameters, so a result rooted in a caller's local can be used within the caller but returned from it only through the caller's own `from` clause.
- An alias into a pool slot exists only as a **lease** (Section 7.14). Otherwise an aggregate field of a pool record is copied to be passed (Section 7.13).

These rules need no run-time check: program storage is never freed; activation storage outlives every call made from its block; and a leased node's owner cannot be reached during the lease.

**Binding.** The caller evaluates every field selection and checked index forming an argument once, before the call. The binding cannot be changed. Writing through one alias is visible through every other path to the same subobject.

## 7.8 Copying and aggregate assignment

Scalar assignment copies a value. Aggregate assignment copies a whole aggregate into a destination of exactly the same concrete type; two bounded strings must have equal capacities. A `string[]` parameter is a view and cannot be a whole-object operand.

The compiler evaluates both paths once and validates both extents before the first destination byte changes; a trap leaves the destination unchanged. Under the type and containment rules, two aggregate designators are either identical or disjoint, so no overlap check is needed; an assignment of an object to itself has no effect.

**Owning types are not copied.** A record or array that contains an owning handle, directly or through nested records and arrays, is an owning type (Chapter 6). An object of owning type cannot be the source of an aggregate assignment, or be passed by copy. No aggregate value is fresh: aggregate results are aliases (Chapter 6, Section 6.5). Its handles move only through `move` (Section 7.11).

## 7.9 Pools, slots and handles

A pool (Chapter 8, Section 8.11) is a fixed array of **slots**, each able to hold one record of the pool's record type. A slot is **free** or **allocated**. Pool storage never moves, and a slot only ever holds its pool's record type. Each pool has a high-water mark and a first-in, first-out free list.

A **handle** names a slot. The four handle types of a pool `P` are (design decision D22):

| Type | Meaning | Allowed in |
| --- | --- | --- |
| `P` | owns a slot; never `none` | parameters, routine results, and locals with an initializer |
| `P?` | owns a slot, or is `none` | anywhere a type is written |
| `id P` | refers to a slot without owning it | parameters, routine results, and locals with an initializer |
| `id P?` | refers to a slot, or is `none` | anywhere a type is written |

**Owning handles** (`P`, `P?`). Every allocated slot has exactly one owner: one owning handle, held by a local, a parameter, a temporary, a program variable, a field or element of an aggregate, or a field of another slot. An owning handle is never copied; it is handed on only by `move`, or by storing a fresh value.

**Identifiers** (`id P`, `id P?`). An identifier records its slot and that slot's generation (Section 7.16). It may be copied freely, compared, and stored anywhere. Every access through an identifier checks that the slot is still allocated to the same occupant, and traps with `stale-handle` if it is not.

`id(h)` makes an identifier from an owning handle `h`: from `P` it gives `id P`, and from `P?` it gives `id P?`. It may be applied to any owning handle, including one reached through a field, and does not move or change it. Identifiers are made only by `id(...)`; they are never converted from or to integers.

An optional handle, owning or not, cannot be used to reach a record directly. It is tested with `select` (Chapter 11), which yields the non-optional value in its `some` arm.

## 7.10 Creating: `new` and `new?`

```basie
var n = new nodes(5, none)           // Chapter 8's Node: value, next
var m = new nodes(7)                 // trailing fields omitted: next is none
```

`new P(arguments)` allocates a slot of pool `P` and initializes the record's fields from the arguments, in field order. Trailing arguments may be omitted, and their fields are zeroed; a record with an array of owning handles, or a nested owning record, is built this way. The result is a fresh owning handle of type `P`. The stores into the new record are initializations, not overwrites, and free nothing.

`new` takes the oldest slot on the free list, or the next never-used slot above the high-water mark. If the pool has no free slot, `new` traps with `pool-full` (design decision D27).

`new? P(arguments)` has type `P?`. When the pool is full, it evaluates **none** of its arguments and yields `none`. In both forms, the slot is reserved before the arguments are evaluated, so exhaustion never consumes a moved argument; a non-optional local moved into a `new?` argument is "may be moved" afterwards, on both arms of the `select` that tests the result.

The pool must be complete (not only forward-declared) at a `new`.

## 7.11 Moving and transfer

An owning handle held in a variable, parameter or field is handed on only by `move x` (design decision D19), which yields the handle and leaves `none` in `x`. Chapter 9 defines `move` as an expression.

A **fresh** owning value, the result of `new`, of `new?`, or of a routine whose result is an owning handle, needs no `move`. Binding an owning argument to an owning parameter transfers ownership to the callee; the argument must be fresh or a `move`.

Storing into an owning location (Chapter 10, Section 10.4) requires a right side that is `none`, fresh or a `move`. Copying an owner, as in `a = b` with `b` an owning handle, is invalid.

## 7.12 Freeing

Freeing is automatic; there is no `free` statement (design decision D18). A slot is freed:

- when its owning local or parameter goes out of scope, at the end of its block, on every exit path;
- when the variable, field or element that owns it is overwritten, including with `none`;
- when the slot, or the local aggregate, that owns it is freed; and
- when the statement temporary holding it ends (Chapter 10, Section 10.8).

Freeing `none` does nothing. Freeing through an owning local, parameter, temporary or local aggregate stores `none` into it.

**Freeing what a slot owns.** Freeing a slot frees every slot it owns, and so on, without recursion and in constant stack space: the runtime keeps a work list, pushes each child found in the slot's owning fields **whose owner link equals the slot being freed** (Section 7.15), returns the slot to its pool, and repeats until the list is empty. The slot at the top of the cascade is freed without the link test. The test guarantees that the cascade neither loops nor frees a slot twice. The fields of a freed slot are never read again by source.

**Order of overwrite.** An assignment to an owning location evaluates the right side, then the destination, then frees the old value, then stores (Chapter 10, Section 10.4).

## 7.13 Accessing a pool record

A field of a pool record is reached through a non-optional handle by selection, as `n.value`. Each access is one operation, resolved after all its operands have been evaluated:

| Through | Check |
| --- | --- |
| An owning local or parameter | none; an owner is never stale |
| A lease (Section 7.14) | none |
| An identifier | the generation check; `stale-handle` if the slot is no longer the one identified |

A path through an identifier may select any chain of record fields and checked indexes under one check, as `i.pos.x` or `i.kids[k]`. A path never continues through a second handle without a new access: `i.next.value` is two accesses, and `i.next` is an optional handle that must be tested with `select` before it can be followed.

An identifier on an assignment's target path is checked twice: when the path is resolved, before the right side, and again after the right side, immediately before the store. So in `i.value = f()`, if `f` frees the slot, the second check traps with `stale-handle` and nothing is stored; nothing can free the slot between the last check and the store.

Scalar fields are read and written in place. An **aggregate field** is copied as a whole: `var s = i.name` copies it out, and `i.name = s` copies it in. Passed as an argument, an aggregate field is treated by how it was reached:

- **Through an identifier:** the callee could free the slot, so the field is copied into a hidden temporary of the caller, counted in its frame, and the callee sees the copy. It can't be passed to a `var` parameter, and a field of an owning type can't be passed at all, since a copy would duplicate its owning handles.
- **Through an owner or a lease:** the field is passed as an alias, to a ticket or a `var` parameter. The path starts at the routine's own non-optional owning local or parameter, which the callee can't reach, so nothing can free the slot during the call.

## 7.14 Leases and slot-holders

**Leases.** A record parameter, a ticket or `var`, accepts any record of its type in program or activation storage, and also the record in the slot owned by one of the caller's own owning locals or parameters, or by a temporary (design decision D30). Passing such a record is a **lease**:

- the owning local or parameter must not appear anywhere else in the same statement, except as `id(h)` or as a read of a scalar field (Chapter 10, Section 10.8); and
- the callee sees an ordinary record: through a `var` parameter it can read and write fields, but it has no handle to move, overwrite or free the slot.

`select` on the routine's own owning local, parameter or temporary leases the record to the `some` arm in the same way (Chapter 11). A lease needs no run-time check, because only the owner can free the slot and nothing else can reach the owner while the lease lasts.

**Owner words.** A `var` record parameter, a `var` parameter whose type is an owning type, and a slot-holder each carry a hidden owner word supplied by the caller: 0 when the argument is in program or activation storage, and the slot when the argument is a leased record or lies inside one. Every store of an owning handle through the parameter uses the owner word as the stored slot's owner link (Section 7.15). A parameter passed on to another such parameter passes its own owner word, as does a field or element of it, and a result rooted in it.

**Identifiers inside a lease.** In a routine with a `var` record parameter `n` whose record type belongs to exactly one pool `P`, `id(n)` has type `id P?`. It is the record's identifier when `n` is a whole leased record, and `none` otherwise, including when `n` is in program or activation storage or nested inside a record. `id(n)` is invalid if the record type belongs to no pool or to more than one.

**Slot-holders.** A `var` parameter of type `P?` lends a place that holds a handle or `none`; the callee may move into it, move out of it or overwrite it:

```basie
sub push(var list as nodes?, v as u16)
    var n = new nodes(v, move list)
    list = move n
end
```

The argument must be an owning local or parameter of type `P?`, a program variable, a field or element of a local or program aggregate, or a field or element of a `var` owning-aggregate parameter, including a leased record, in which case it inherits that parameter's owner word. A field of a pool record reached through an identifier cannot be passed as a slot-holder; nor can a local or parameter leased in the same statement. `from` cannot name a slot-holder.

## 7.15 Owner links and the cycle check

Each allocated slot records its owner link: 0 while it is owned by anything other than a field of a slot, and the owning slot while it is owned by a field of another slot. Every store of an owning handle other than `none` sets the stored slot's link: to the destination slot when the destination is a field of a slot, reached through an owner, an identifier, a lease's owner word, or the slot `new` is initializing; and to 0 otherwise. Binding an owning parameter, binding `some(n)` under `select move`, and holding a fresh value in a temporary all set 0. `new` sets the new slot's link to 0.

A slot must never own itself, directly or through a chain. Before storing a handle *b*, other than `none`, into a field of slot *s* that might not be a root, the runtime follows the links upwards from *s* until it reaches 0; if it meets *b*, the program traps with `ownership-cycle`. A store into a location no slot owns, or into a field of a slot reached through an owning local, owning parameter or temporary, cannot create a cycle and needs no walk.

## 7.16 Generations

Each slot has a 16-bit generation. A never-used slot has generation 0; `new` gives a fresh slot generation 1; freeing advances it. A slot is allocated only while its generation is below `$FFFF`; a slot whose generation reaches `$FFFF` is withdrawn permanently instead of being returned to the free list. No identifier carries generation 0 or `$FFFF`.

An identifier matches its slot only while the slot is allocated with the identifier's generation. Hence an access through an identifier traps with `stale-handle` exactly when the slot it identified has been freed since the identifier was made, and `select` on an identifier yields `none` in the same case. Because generations never repeat for a slot, a stale identifier never matches a later occupant.

## 7.17 The flow check

For each owning local and owning parameter, the compiler tracks whether it certainly holds a value, certainly holds `none`, or may hold either (Chapter 10, Section 10.8; Chapter 11; Chapter 12). Accessing or moving a non-optional owning local that may have been moved is invalid. Every other owning location is treated as possibly holding a value. Because a move stores `none` at run time, no code is needed where flow paths join.

## 7.18 The stack

Stack overflow is detected without a guard page:

- When the compiler completes a routine `R`, it computes `need(R)`: `R`'s frame (Section 7.6), plus the stack use of the runtime helpers it calls, plus the largest `need(c)` of the routines `c` that `R` calls, counting 0 for `R` itself and for forward-declared routines not yet complete.
- A call from a routine to itself, or to any routine whose body is not complete, is valid only through a forward declaration (Chapter 5, Section 5.9). So every cycle of calls passes through a forward-declared routine.
- Every forward-declared routine begins with the **activation-capacity check**: it traps with `activation-capacity` if the stack pointer minus `need(R)` minus the profile's guard band would fall below the start of free memory.
- `need(main)` plus the guard band is the program's stack reserve, which startup checks against the memory available before calling `main` ([CP/M target](../docs/cpm-target.md), Section 4).

Together these guarantee that no call can overflow the stack unchecked.

## 7.19 Diagnostics

Chapters 8, 10, 11 and 13 list the compile-time diagnostics for these rules. In summary, the compiler must diagnose: a copy of an owning value or of an object of owning type that is not fresh; a store into an owning location from something other than `none`, a fresh value or a `move`; a use of an optional handle to reach a record without `select`; a stored or retained alias; a returned alias rooted in a local or in a parameter not named in `from`; a lease or slot-holder argument that breaks Section 7.14; a violation of the statement rule or the flow check; a `new` on a forward-only pool; an `id(...)` of a lease whose record type has no single pool; and a recursive call without a forward declaration. The run-time traps are `bounds`, `stale-handle`, `ownership-cycle`, `pool-full` and `activation-capacity` (Chapter 15).
