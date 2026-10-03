# 7. Storage, values, and lifetime


## 7.1 Scope

This chapter defines source-level storage, object identity, value copying, aggregate aliases, storage duration, and lifetime. Chapter 6 defines the types that occupy storage. Chapter 8 defines declaration syntax, constants, initializers, and when a declaration installs a zero or explicit initial value. Chapter 13 defines routine syntax, result syntax, and calls.

The rules in this chapter do not expose physical addresses, banks, Z80 registers, stack positions, activation layouts, or compiler workspace. Those are implementation matters. A conforming implementation preserves the source-level identity and lifetime rules regardless of its storage arrangement.

## 7.2 Values, objects, subobjects, and aliases

Baton distinguishes four related concepts:

| Concept               | Source meaning                                                                                                                         |
| --------------------- | -------------------------------------------------------------------------------------------------------------------------------------- |
| Scalar value          | One `u8`, `u16`, or `boolean` value. Scalar values can be copied.                                                                      |
| Object                | Storage associated with a program variable.                                                                                            |
| Subobject             | A record field, fixed-array element, or existing bounded-string byte. A bounded string may itself be an object or aggregate subobject. |
| Typed aggregate alias | A non-owning, fixed binding to an existing record, fixed-array, or bounded-string object or subobject of one of those types.           |

An object has one identity throughout its lifetime. Writing a new scalar value into an object or subobject changes its contents, not its identity. An alias has the exact aggregate type of its target and does not create another object.

Every alias is bound to an object or aggregate subobject when the alias is established. Baton has no null, unbound, or reseatable aggregate alias. Source code cannot inspect, compare, convert, or perform arithmetic on the implementation carrier used for an alias.

## 7.3 Owned storage

A top-level variable owns one mutable object with program lifetime. A scalar variable owns one scalar cell. A record, fixed-array, or bounded-string variable owns the complete aggregate object, including every contained subobject. An aggregate constant owns one statically initialized program-lifetime aggregate object whose direct named root is read-only.

Scalar named constants denote values and need not occupy source-observable storage. Aggregate named constants occupy program-lifetime storage containing their complete static values. Their direct named roots are read-only under Section 7.8.

Aggregate storage occurs only in top-level variable or aggregate-constant objects and inline within other aggregate storage. A record field has storage within its containing record. An array element has storage within its containing array. A bounded string has its counted content within its containing string object. A routine cannot declare owned aggregate storage, and Baton allocates no activation-lifetime aggregate storage.

## 7.4 Program lifetime

Program-lifetime objects exist before the designated entry routine begins. Their lifetime ends when program execution terminates, whether normally or through a specified trap. Chapter 8 defines their initialization and the point at which each initial value is established before the first source read.

The zero value of each admitted type is:

| Type        | Zero value                                                  |
| ----------- | ----------------------------------------------------------- |
| `u8`, `u16` | integer zero                                                |
| `boolean`   | `false`                                                     |
| record      | the record whose fields recursively have their zero values  |
| `T[N]`      | the array whose elements recursively have their zero values |
| `string[N]` | the empty byte sequence                                     |

This table defines values, not a byte layout or a universal initialization rule. Chapter 8 specifies which declarations receive a zero value and which require an explicit initializer. An implementation must establish the required semantic value without exposing padding, headers, addresses, or backend-specific representations.

## 7.5 Routine activations

Each routine invocation creates a distinct logical activation. An activation contains that invocation's scalar parameters, scalar locals, and aggregate-parameter bindings. It begins when the call establishes the parameters and ends when the routine returns or program execution terminates.

A scalar parameter receives a copied value. Each scalar local belongs to one activation. Its source lifetime begins when execution reaches its declaration and Chapter 8 has established its initial value; its lifetime ends with the activation. A scalar result is copied from the returned expression to the caller. It is not shared storage in the callee.

An aggregate parameter is a typed alias to caller-provided storage. Its binding belongs to the activation, but the target retains program lifetime. An open-string parameter also carries the referent's concrete capacity within the activation. A routine has no other named aggregate binding.

Two simultaneously active invocations have distinct logical parameters and scalar locals. This rule applies even when the implementation assigns the same registers or physical storage to invocations that cannot overlap.

Recursive calls use the same activation rule. An implementation preserves distinct logical activation state at every active depth. Caller-save regions, hardware-stack entries, static-slot save areas, or another re-entry mechanism may implement that rule; none is source storage.

These rules divide storage into two practical planes. The aggregate plane contains fixed top-level program-lifetime objects and their aggregate subobjects. The activation plane contains copied scalar parameters, scalar locals, and aggregate-parameter bindings. Calls preserve overlapping activation-plane state; aggregate bytes remain in program storage.

Programs declare every aggregate object at top level, pass required objects or subobjects through aggregate parameters, and use scalar locals for per-invocation work. A routine that needs destination or scratch aggregate storage receives it from its caller. This rule keeps every aggregate allocation visible in the program declaration sequence and prevents hidden shared aggregate state inside recursion.

## 7.6 Aggregate parameter binding

An aggregate alias binds once when a call establishes an aggregate parameter. The argument is a compatible aggregate storage path rooted in a program variable, aggregate constant, or aggregate parameter, a field or fixed-array element reached from such a root, or a transient aggregate result admitted by Section 7.9. Every admitted source ultimately denotes top-level program storage. A `string[]` binding records both the address of one complete bounded string and its actual capacity; forwarding the view preserves that pair.

The caller evaluates every field selection and checked index used to form the argument once before the call begins. The callee receives the resulting typed alias, and its binding cannot be changed. The target type must satisfy the parameter-compatibility rule in Chapter 6.

An alias does not extend the target's lifetime. Scalar-leaf writes and compatible aggregate assignment through an aggregate alias are allowed under the ordinary assignment rules, including when the original target was named by an aggregate constant. Read-only status belongs only to the direct constant-rooted source path; it is not carried in the alias type or checked dynamically.

## 7.7 Subobject lifetime and identity

A subobject begins and ends its lifetime with its containing object. Nested containment does not create a separately managed lifetime. An alias to an aggregate record field or fixed-array element remains valid only while the containing object remains alive.

Distinct fields of one record, distinct elements of one fixed array, and distinct byte positions in one bounded string are distinct subobjects. An object overlaps each of its own subobjects, and a nested subobject overlaps every containing object on its path. Sibling fields, sibling array elements, and distinct string bytes do not overlap in source semantics.

Two aliases may denote the same object or overlapping objects. Baton provides no alias-identity comparison, but identity is observable through mutation: a scalar write through one path is visible through every other path to that scalar subobject. An implementation must preserve this effect even if it caches a scalar value or uses different carriers for the two paths.

## 7.8 Assignment and aggregate mutation

Scalar assignment copies a value into a scalar destination. The destination may be a scalar variable, parameter, record field, fixed-array element, or existing bounded-string byte. After the assignment, later changes to the source do not change the destination.

Aggregate assignment requires a mutable aggregate destination and an aggregate source of the exact same concrete type. It copies the complete packed value into the destination. Two bounded strings are assignment-compatible only when their capacities are equal. An open-string parameter is a view and cannot be a whole-object assignment operand.

The compiler evaluates the destination storage path once, then the source storage path or transient aggregate-alias result once, and validates both complete extents before the first destination byte changes. If evaluation or validation traps, no byte of the aggregate destination changes. A source and destination that denote the same object or subobject produce no change.

Under the Baton 1.0 type and containment rules, two designators admitted by aggregate assignment are either identical or disjoint. A proper partial overlap would require recursive by-value containment, an overlaid layout, a slice, or arbitrary address formation, all of which are absent. Aggregate assignment therefore needs no runtime overlap check.

Aggregate alias binding is not assignment. Once established, an aggregate parameter cannot be rebound. When an aggregate parameter is the destination of aggregate assignment, the copy changes its referent. It does not change the binding.

An assignment whose written target is rooted directly at an aggregate constant name is invalid, whether it names the whole object, a field, an array element, or a bounded-string byte. This is a source-path restriction, not transitive immutability. Passing that constant as an aggregate argument or returning it as an aggregate alias deliberately loses the direct-root marker; a callee may then mutate the target through its ordinary writable parameter. Whether such a write changes bytes, is ignored, or is rejected by the target platform depends on where the implementation places read-only data. Portable programs do not depend on mutation through an alias to an aggregate constant.

## 7.9 Aggregate results

An aggregate routine result is a transient typed alias to existing program-lifetime storage. The result preserves the target's exact aggregate type and denotes the same object.

Program-lifetime storage consists of top-level variable and aggregate-constant objects and their aggregate subobjects. Baton 1.0 has no routine-local aggregate declaration, activation-lifetime aggregate, heap aggregate, or variable-sized local, so every aggregate storage path, aggregate-parameter binding, and transient aggregate-alias result denotes program-lifetime storage. An aggregate result therefore always outlives the callee activation. The compiler retains the exact referent type and transient-result category, but it needs no lifetime-tracking bit, signature annotation, or parameter identity for this purpose.

An aggregate return source is a storage path rooted in a visible program variable, aggregate constant, or aggregate parameter, a field or fixed-array element reached from such a root, or a transient aggregate result forwarded from another call. Field selection and checked indexing continue to denote program-lifetime subobjects because every aggregate subobject has the lifetime of its containing object.

The caller must consume a returned aggregate alias immediately. It may discard the result, forward it as an aggregate argument or aggregate return, select a field or element from it, or use it as an aggregate-assignment source compatible under Section 7.8. Assignment is the materialization operation: it copies the value into program storage or into the referent of an aggregate parameter. A result cannot be stored as a carrier or survive beyond the containing source operation. Code that needs to retain the value assigns it to a program object or caller-supplied destination.

Immediate consumption does not permit a later call to destroy the transient carrier before it is used. When evaluation of another argument, index, or suffix can call a routine, the compiler must stage or preserve the typed carrier as live implementation state. This staging is not a source alias and ends with the containing operation.

Baton has no routine-local aggregate declaration, activation-lifetime aggregate object, aggregate temporary, heap object, or variable-sized local object. Every aggregate result selects storage that already existed before the call.

## 7.10 End of activation bindings

When an activation ends:

- its scalar parameters and scalar locals cease to exist;
- its aggregate-parameter bindings cease to exist;
- storage reached through those aliases is unaffected if that storage has a longer lifetime; and
- a valid returned scalar value or aggregate alias has already been transferred to the caller.

Every aggregate object and subobject remains alive until program termination. Baton 1.0 therefore has no source form that can create a dangling aggregate alias. The compiler checks exact referent types, admitted alias-binding sources, and the immediate-consumption rule for transient results; it does not track a separate aggregate-lifetime fact.

Baton 1.0 has no manual deallocation, destructors, `finally`, `defer`, variable-sized locals, or other scope-exit action. Returning from a routine performs no hidden source-level cleanup. A backend may restore saved implementation state, but that restoration does not run source operations or change the lifetime rules above.

## 7.11 Examples

The following declarations use program-lifetime record-array storage:

```nucleus
record Entry
    value as u16
end

var entries as Entry[8]

sub entryAt(index as u8) as Entry
    return entries[index]
end
```

`entryAt` returns an alias to one `Entry` subobject of `entries`. The bounds check occurs before the result is formed. The target has program lifetime and remains alive after the call.

An incoming aggregate alias also supplies a valid aggregate result:

```nucleus
sub choose(items as Entry[8], index as u8) as Entry
    return items[index]
end
```

The caller-provided array has program lifetime, so the returned element remains available after the `choose` activation ends.

This statement mutates a scalar leaf through the aggregate alias `item` without copying or rebinding the record:

```nucleus
item.value = 7
```

The assignment changes the caller's selected `Entry`. It does not create another `Entry`.

If `first` and `second` are aggregate parameters of type `Entry` and `otherEntries` is another `Entry[8]` object, these assignments copy complete aggregates:

```nucleus
first = second          // copy one Entry into first's referent
entries = otherEntries  // copy all eight Entry values
```

A routine may copy a selected value into caller-supplied storage without declaring an aggregate local:

```nucleus
sub copyEntry(items as Entry[8], index as u8, destination as Entry)
    destination = items[index]
end
```

`destination` remains bound to the caller's object. The assignment copies one complete `Entry` from the selected array element into that object.

A routine may also forward a selected alias without copying:

```nucleus
sub forwardedEntry(items as Entry[8], index as u8) as Entry
    return choose(items, index)
end
```

The forwarded alias still denotes an element of the caller-provided array. No aggregate object or local alias is created by either call.

## 7.12 Implementation independence and capacities

Language lifetime is independent of a value's physical location. Reusing a register or physical address at different times, overlaying non-overlapping locals, bank placement, and hardware-stack reuse do not merge source objects or activations. Conversely, two source paths to the same object retain shared identity even if a backend represents them differently.

An implementation may bound scalar locals, aggregate-parameter bindings, or the metadata used for their exact types and result categories. It must publish each limit. A compile-time excess requires a capacity diagnostic under Chapter 1. An implementation must not share live activation state or lose an alias binding when a limit is reached.

Runtime activation capacity is implementation-defined under Chapter 13. An implementation may bound simultaneous activation depth, activation-storage consumption, or both. Reaching either published limit at runtime performs the activation-capacity trap defined by Chapter 15. The limits and trap do not change the source lifetime of an activation that begins successfully.

Baton 1.0 exposes no raw pointer value, address arithmetic, heap allocation,
manual deallocation, open slice or view other than the parameter-only
`string[]` view, variable-sized local, or storage-layout query through this
chapter. Field byte offsets, array byte offsets, bounded-string encoding,
address carriers, aggregate-copy lowering, and call-state layouts belong to the
Z80 runtime and backend contract.
