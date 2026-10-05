# 6. Types


## 6.1 Scope

This chapter defines the Basie 1.0 type set, type identity, compatibility, scalar conversions, aggregate categories, and the static type carried by aggregate aliases. Chapter 7 defines storage duration and lifetime. Chapter 8 defines declarations and initialization. Chapter 9 defines expression syntax and operator typing, and Chapter 13 defines routine syntax and parameter passing.

The type system supports local checking during one streaming source pass. A compiler can determine the type of a name, field, array element, literal in context, or routine result from declarations already processed. It requires neither whole-program inference nor runtime type tags.

## 6.2 Type set

Basie 1.0 has eight scalar types, four handle forms, three owned aggregate
forms, two parameter-only aggregate views, and the predeclared type `File`:

| Category        | Types or forms                                         |
| --------------- | ------------------------------------------------------ |
| Scalar          | `u8`, `i8`, `u16`, `i16`, `u32`, `i32`, `f32`, `boolean` |
| Handle          | `P`, `P?`, `id P`, `id P?` for a pool `P` (Section 6.14) |
| Owned aggregate | nominal records, `T[N]`, `string[N]`                   |
| Parameter view  | `string[]`, `T[]`                                      |
| File            | `File` (Chapter 16, Section 16.3)                      |

`File` is an opaque 4-byte value naming an open file or device. It is copied
like a scalar: it may be the type of a constant (`console` or `printer`), a
program variable, a field, a local, a parameter without `var` and a result,
and its zero value is a closed file. It has no arithmetic, no ordering and no
conversion to or from any other type; it compares only with `=` and `<>`
(Chapter 9, Section 9.11). Like a scalar, it can't be a `var` parameter.

The following skeleton records type formation without defining declaration grammar:

```text
type             ::= scalar-type
                   | handle-type
                   | record-type-name
                   | fixed-array-type
                   | bounded-string-type
scalar-type      ::= "u8" | "i8" | "u16" | "i16" | "u32" | "i32"
                   | "f32" | "boolean"
handle-type      ::= [ "id" ] pool-name [ "?" ]
fixed-array-type ::= element-type "[" array-length "]"
                   | element-type "[" "]"
element-type     ::= scalar-type | handle-type | record-type-name
                   | bounded-string-type | fixed-array-type
bounded-string-type
                 ::= "string" "[" [ string-capacity ] "]"
```

An array element may be a scalar, a handle, a record, a bounded string or another fixed array, so arrays may have several dimensions (design decision D32): `u8[25][40]` is an array of 25 elements, each an array of 40 `u8`. Records may contain fields of any admitted type, including fixed arrays and handles.

`string[N]` is the owned bounded-text form. An omitted capacity is admitted only
in a formal parameter: `string[]` denotes a view whose actual capacity comes
from the argument. Likewise `T[]`, an **open array**, is admitted only as a
formal parameter and denotes a view of any complete `T[N]` argument, retaining
its length as `.length`; for a multi-dimensional array only the outermost
dimension may be open. `string` and the eight scalar type names are reserved
words; `id` is contextual (Chapter 3).

## 6.3 Scalar types

The integer types and their ranges are:

| Type | Width | Range |
| --- | ---: | --- |
| `u8` | 8 | 0 through 255 |
| `i8` | 8 | −128 through 127 |
| `u16` | 16 | 0 through 65,535 |
| `i16` | 16 | −32,768 through 32,767 |
| `u32` | 32 | 0 through 4,294,967,295 |
| `i32` | 32 | −2,147,483,648 through 2,147,483,647 |

Signed types use two's complement. Their widths and ranges do not vary by target.

`f32` holds IEEE 754 single-precision values in the IEEE storage layout, restricted to finite values: there is no infinity and no NaN, and denormal values are flushed to zero (design decision D7). An operation whose result would be infinite or invalid traps (Chapter 15). `f32` is a numeric type but not an integer type: it can't index an array, count a loop or take part in a shift or bitwise operation.

`boolean` has exactly the values `false` and `true`. It is distinct from both integer types. An integer is not a condition, a Boolean value is not an integer, and Basie 1.0 provides no Boolean-to-integer or integer-to-Boolean conversion.

A scalar variable, parameter, field, array element, or routine result holds a scalar value. Scalar assignment and scalar argument passing copy the value. A compiler may use any private register or memory representation that preserves the type and value; that representation does not alter source compatibility.

## 6.4 Literals and scalar conversion

An integer literal is exact and has no fixed integer type until an expected integer type or an expression rule supplies one. In a declaration initializer, scalar argument, assignment, return, array index, or other expected-type position, a literal may take any integer type whose range contains its value, and an `f32` type when its value is exactly representable. A literal outside the expected range is invalid; it is not truncated or wrapped. A floating-point literal (Chapter 3) has type `f32` and never takes an integer type.

Chapter 9 defines the treatment of an integer literal with no expected type and the result types of operators. This chapter does not assign an expression-wide default type.

A character literal is an exact integer whose value is the decoded byte from Chapter 3, so it adopts any integer type that holds the value, as `var a as i8 = 'A'` does. Where nothing else gives it a type, as in `var c = 'A'`, it is `u8` (Chapter 9, Section 9.7). Basie has no separate character type.

**Implicit widening** is admitted only where every source value is preserved (design decisions D4 and D31):

| From | To |
| --- | --- |
| `u8` | `u16`, `u32`, `i16`, `i32`, `f32` |
| `i8` | `i16`, `i32`, `f32` |
| `u16` | `u32`, `i32`, `f32` |
| `i16` | `i32`, `f32` |

Unsigned values are zero-extended and signed values sign-extended. The same widening applies to assignment, initialization, scalar arguments, scalar results, and operands when Chapter 9 admits a mixed operation. `u32` and `i32` don't widen implicitly to `f32`, because not every 32-bit value is exactly representable.

**Every other conversion between numeric types is explicit and checked.** Chapter 9 defines the spelling, which uses the target type's name as a conversion, such as `u8(x)`, `i16(y)` or `f32(n)`. When the source value is known at compile time and does not fit, the compiler issues a diagnostic. Otherwise the generated program traps with `narrowing` before producing a result that does not fit. A negative value never converts to an unsigned type, and an unsigned value above a signed type's range never converts to it. Conversion from `f32` to an integer type truncates toward zero and traps if the result does not fit. Conversion from `u32` or `i32` to `f32` rounds to nearest, ties to even. Checked conversion never means low-byte extraction, modulo reduction, or reinterpretation.

No implicit or explicit scalar conversion changes `boolean` into an integer or an integer into `boolean`. Basie 1.0 also has no arbitrary cast or same-width reinterpretation operation.

## 6.5 Values, aggregate storage, and aliases

The source type and the way a source occurrence denotes data are separate properties:

| Category                | Meaning                                                                                            |
| ----------------------- | -------------------------------------------------------------------------------------------------- |
| Scalar value            | An integer, `f32` or `boolean` value, copied by assignment, argument passing and return.           |
| Owned aggregate storage | Storage containing one record, fixed array, or bounded string for a lifetime defined in Chapter 7. |
| Aggregate alias         | A typed, non-owning binding to existing aggregate storage.                                         |

A scalar named constant is exact when it is untyped and its value is an integer, and otherwise has its written or literal type, which may be any scalar type (design decision D20; Chapter 8, Section 8.4). A record, fixed array, or bounded-string constant has an explicit aggregate type and complete static initializer under Chapter 8.

Top-level variables, aggregate constants and aggregate locals provide owned aggregate storage; a local's storage lives in its routine's frame for the length of its block (design decision D8; Chapter 7, Section 7.6). Aggregate storage may also occur inline as a record field or fixed-array element, including in a pool slot. A routine cannot declare an aggregate-alias local. The permitted declaration sites, initialization rules, mutability, and storage duration appear in Chapters 7 and 8.

An aggregate parameter is a fixed typed alias to caller-provided storage. Its binding cannot be changed, but mutation through it changes the caller's object. A parameter declared as `string[]` additionally retains the concrete argument's capacity for checked access. A routine may also return a transient aggregate alias to existing storage, but an open-string view cannot be a result.

Assignment between aggregate designators of the exact same concrete type copies the complete value into the destination. This includes two bounded strings with the same capacity. Assignment changes the destination object's contents and never rebinds an alias. Routine arguments and aggregate results transfer aliases rather than copying automatically. Concrete aggregate parameters and all aggregate results require exact type identity; `string[]` parameters use the specific compatibility rule in Section 6.10.

An aggregate routine result is a transient typed alias to storage that outlives the call: program storage, or storage reached through a parameter named in the routine's `from` clause. It can never refer to the routine's own locals, which the `from` rule checks (design decision D8; Chapter 13, Section 13.6). Chapter 7 defines its permitted consumption.

## 6.6 Record types

A record declaration creates one nominal type. Two record declarations create different types even when their fields have identical names and types. Record storage and aliases are compatible only with the type created by the same declaration.

Every record has one fixed field sequence and one fixed layout. Each field has a name and one previously declared type. A field may have scalar, record, fixed-array, or bounded-string type. The complete field sequence is known when the record declaration ends.

A record must have finite size. A field therefore must not contain its own record type directly or through a cycle of record and array containment. Variant records, unions, and overlaid layouts are absent.

Selecting a scalar field produces a scalar occurrence of the field's declared type. Selecting an aggregate field produces a storage path or aggregate alias with the field's exact aggregate type. Selection does not expose a byte offset or address to source code.

Chapter 8 defines record declaration and field syntax. Runtime byte offsets and packed layout belong to the Z80 runtime and backend contract.

## 6.7 Fixed-array types

`T[N]` is a one-dimensional fixed array with element type `T` and length `N`. `N` must be a positive compile-time integer from 1 through 65,535. A compiler may publish a smaller capacity for a particular storage region or implementation, but exceeding that capacity is a capacity failure rather than another array type.

The index domain is always zero through `N - 1`. Basie has no arbitrary lower bound, subrange index, enumeration index, or range type. The length and element type are part of the array type.

Two fixed-array types are identical when their element types are identical and their lengths are equal. Thus `u8[16]` and `u8[16]` are the same type, while `u8[16]`, `u8[32]`, and `u16[16]` are three different types.

An array index must have type `u8` or `u16`; `u8` widens to `u16` when the checking operation requires it. A constant index outside the array domain is invalid. A dynamic index must be checked before the access unless the compiler proves from information already available at that point that it lies in the domain. A failed dynamic check performs the bounds trap specified by Chapter 15 before any element load or store.

Indexing an array of scalars produces a scalar occurrence with the element type. Indexing an array of records or bounded strings produces a storage path or aggregate alias with the element type. The index operation never produces an untyped address.

## 6.8 Bounded strings

`string[N]` is a fixed-capacity counted sequence of bytes with a current length from 0 through `N`. `N` is a compile-time integer from 1 through 253 and is part of the type. The empty string is a valid value. Payload bytes may have any value from 0 through 255, including zero.

A string literal is a contextual bounded-string initializer. It is compatible with `string[N]` when its decoded byte length does not exceed `N`. A literal that is too long is invalid. The literal does not create an open-ended string type or infer a capacity independently of its context.

Two concrete bounded-string types are identical only when their capacities are equal. An alias to `string[16]` cannot bind to a `string[32]` parameter or result, even when the current contents would fit both. Concrete aggregate aliases and results therefore retain an exact extent.

A bounded string is an aggregate, not a `u8` array. It has no source-level header field, payload field, or terminator field. Basie 1.0 provides two intrinsic postfix operations without exposing that representation:

- `text.length` is a `u8` value equal to the current logical byte length. It is read-only, except through a `var string[]` parameter (below).
- `text[index]` selects one existing byte as a `u8` storage path. The index must have type `u8` or `u16` and must be less than the current length. A failed check performs the `bounds` trap before a read or write.

A bounded string's length is established by static initialization, copied as part of exact-type aggregate assignment, or assigned through a `var string[]` parameter (design decision D25). A byte assignment replaces exactly one existing byte and does not change the string's length or capacity. Embedded zero bytes are ordinary content.

Through a `var string[]` parameter, `.length` is a writable `u8` path. Assigning it a value above the view's capacity performs the `bounds` trap. Raising the length makes every newly exposed byte zero, so no earlier contents reappear; lowering it truncates. This is the one way to change a string's length in place, and the standard library builds append, copy and trim on it (Chapter 16, Section 16.4).

Bounded strings have no comparison operators. A library routine can compare two `string[]` parameters by checking their lengths and indexed bytes.

The `.length` intrinsic applies only when the postfix base has bounded-string type. On a record base, `.length` remains ordinary lookup in that record's field scope. Any other field suffix on a bounded string is invalid.

`string[]` is a parameter-only, capacity-polymorphic view. A call may bind it to a concrete `string[N]` storage path or transient alias, for any admitted `N`, or forward another `string[]` parameter. The view retains the actual capacity for `.length` and checked indexing, and gives it as `.capacity`, a read-only `u8`. It does not own storage and is invalid as a variable, constant, record field, array element, local, or routine result. Whole-object assignment and comparison through an open view are invalid.

A string literal remains a contextual static initializer, not a general aggregate expression. As an argument it may bind only a read-only `string[]` parameter, where the compiler supplies it as a constant (Chapter 13, Section 13.4); a `var` parameter needs a named writable object. `string[]` is not a slice: it always views one complete bounded-string object, has no offset or independently chosen length, and cannot be rebound.

This chapter fixes the semantic domain and capacity, not the stored layout. Chapter 7 defines storage identity and lifetime, Chapter 8 defines declaration initialization, and the Z80 runtime and backend contract defines the physical representation and byte encoding. That representation preserves embedded zero bytes, logical lengths through 253, and alias-visible byte mutation.

## 6.9 Aggregate aliases and address separation

An aggregate alias has the same source type as its referent and a separate alias category. For example, an alias to a `Person` record permits `Person` field selection, and an alias to `u8[64]` permits indexing with the fixed bound 64. The alias does not create a reference type that can be named independently.

The compiler must retain the referent type through aggregate parameters, field and element selection, scalar and aggregate assignments, calls, and aggregate results. Passing or returning a concrete alias requires exact referent-type identity. Binding `string[]` retains the argument's concrete capacity separately from its address; forwarding the parameter preserves both.

A direct backend may represent a concrete alias at runtime with one untagged address because compiler metadata records its extent. An open-string parameter additionally needs the actual capacity supplied by its caller. These carriers have no source spelling or runtime type tag. Source code cannot read, write, compare, convert, store, return as a scalar, or perform arithmetic on a carrier itself.

An alias carrier and `u16` remain different typed entities even though both occupy one word. No conversion exists in either direction. Address derivation for field and element access is a checked compiler or backend operation, not `u16` arithmetic visible to the program.

## 6.10 Type identity and compatibility

Type identity is determined as follows:

| Type form       | Identity rule                                                      |
| --------------- | ------------------------------------------------------------------ |
| Scalar          | Each predefined scalar type is its own type.                       |
| Handle          | The same pool, the same kind (owning or `id`), and the same optionality. |
| Record          | The single declaration that introduced the record.                 |
| Fixed array     | Identical element type and identical fixed length.                 |
| `string[N]`     | Identical capacity `N`.                                            |
| `string[]`      | Parameter-only view over one complete concrete bounded string.     |
| Aggregate alias | The exact referent type; aliasing adds a category, not a new type. |

The compiler applies these compatibility rules:

| Context                                                | Required compatibility                                                                                          |
| ------------------------------------------------------ | --------------------------------------------------------------------------------------------------------------- |
| Scalar assignment, initialization, argument, or result | Exact scalar type, a fitting literal or untyped constant, or an implicit widening from Section 6.4.              |
| Checked conversion                                     | Explicit operation and successful range check.                                                                  |
| Handle assignment, argument or result                  | Exact handle type, except that `P` may be used where `P?` is expected, and `id P` where `id P?` is expected; an owning handle is moved (Chapter 7). |
| Boolean condition or destination                       | `boolean` only.                                                                                                 |
| Record field selection                                 | The field's declared type.                                                                                      |
| Fixed-array index                                      | `u8` or `u16` index, never signed (D31); result has the exact element type.                                    |
| Bounded-string `.length`                               | `u8` value equal to the current logical length; writable only through a `var string[]` parameter.               |
| Bounded-string index                                   | `u8` or `u16` index below the current length; result is a writable `u8` path.                                   |
| Concrete aggregate parameter                           | Exact referent-type identity.                                                                                   |
| `string[]` parameter                                   | Any concrete bounded-string storage path or transient alias, or another `string[]`; retain the actual capacity. |
| `T[]` parameter                                        | Any complete `T[N]` storage path or transient alias, or another `T[]`; retain the actual length.               |
| Aggregate assignment                                   | Exact concrete type identity; copy the complete aggregate into the destination.                                 |
| Aggregate result                                       | Exact referent-type identity and immediate consumption under Chapter 7.                                         |
| Aggregate by-value argument or result                  | Invalid; calls transfer aggregate aliases.                                                                      |

Compatibility is checked at the source operation. The backend does not infer compatibility from equal byte widths, equal layouts, compiler storage ordinals, registers, or runtime addresses.

## 6.11 Excluded type mechanisms

Basie 1.0 has none of the following:

- raw pointer or address types visible to source;
- pointer or address arithmetic;
- implicit word/address interchange;
- enumeration or subrange types (enumerations are planned for version 2);
- set types;
- variant records, unions, or overlaid aggregate layouts (variants are planned for version 2);
- structural equivalence between distinct record declarations;
- arbitrary casts, type punning, or unchecked narrowing;
- generic types or generic parameters other than the built-in `string[]` and `T[]` views;
- slices or user-defined variable-capacity views;
- a general heap, or resizable types;
- variable-sized local allocation; or
- dynamic data outside declared pools (Chapter 7).

An implementation must diagnose a source form that requires one of these mechanisms. Equal storage width or a convenient machine representation does not admit the source operation.

## 6.12 Type metadata and capacity

Exact type identity is checked from retained metadata without reconstructing source text. Record declarations require nominal IDs. Predefined scalars, fixed arrays, and bounded strings have compact, bounded structural descriptions: kind, element type when applicable, and length or capacity. A compiler may store those descriptions directly in symbols and signatures or intern them behind compact ordinals. Measurements of compiler-core bytes, immutable data, writable workspace, and comparison code determine the representation used by the first implementation.

Nucleus could fit every type in four bytes because its arrays could not contain arrays. Basie's arrays can nest and its handles name pools, so a type description may need a chain of element descriptions. A compiler may intern descriptions behind ordinals or store short descriptions inline; either way the chosen representation must describe nested arrays to any depth the source uses, within a published capacity.

Four inline bytes are not automatically cheaper than one ordinal per symbol. With mostly distinct types, direct descriptors avoid an interning table; with many repeated types, ordinals reduce writable symbol storage. The measurement package reports both retained-data totals for representative symbol populations. The first compiler also counts the code and scratch state for descriptor construction, interning, exhaustion checks, and equality before selecting either form.

Every selected representation has a published capacity. An ordinal representation diagnoses exhaustion before an ID wraps or aliases another type. An inline representation diagnoses any limit on element-type nesting, length, capacity, symbol entries, record fields, or signatures before truncation changes a compatibility result. A byte-sized type ID remains a candidate, not a language or target requirement.

The numeric type ID has no source meaning and need not match across compilations. Z80 registers and compiler-managed storage locations are untagged; the compiler's symbol and expression metadata supply their current source types. Runtime type tags, reflection, and dynamic type tests are absent.

## 6.13 Examples

These declarations illustrate scalar compatibility:

```basie
var byteValue as u8 = 42
var wordValue as u16 = byteValue    // u8 widens to u16
var delta as i8 = -3
var offset as i16 = delta           // i8 widens to i16
var big as u32 = 70000
var ratio as f32 = 0.25
var scaled as f32 = wordValue       // u16 widens to f32
var code as u8 = 'A'
var flag as boolean = true
```

Each of the following is invalid under this chapter:

```basie
var tooSmall as u8 = 256       // literal does not fit
var narrowed as u8 = wordValue // explicit checked conversion required
var unsigned as u16 = delta    // i8 does not widen to u16
var fromBig as f32 = big       // u32 does not widen to f32
var whole as u16 = 1.5         // a floating-point literal is f32
var truth as boolean = 1       // integer is not Boolean
var count as u16 = false       // Boolean is not integer
```

Record identity is nominal:

```basie
record LeftPoint
    x as u16
    y as u16
end

record RightPoint
    x as u16
    y as u16
end
```

`LeftPoint` and `RightPoint` are different types despite their equal field lists. An alias or parameter of one type cannot bind storage of the other.

Array and bounded-string bounds are part of their types:

```basie
var bytes as u8[16]
var name as string[12]
```

`bytes[0]` through `bytes[15]` are within the declared domain. `bytes[16]` is a compile-time error. A runtime value used as the index is checked before access. `string[12]` and `string[16]` are different types, and a thirteen-byte literal cannot initialize `name`.

For a bounded string `name`, `name.length` reads its logical length and `name[index]` reads or replaces one existing byte. An index equal to the current length traps; assignment through the index does not append or change `name.length`.

## 6.14 Handle types

A pool declaration (Chapter 7) names a fixed set of slots of one record type.
The pool's name, used as a type, denotes a **handle** to one of its slots
(design decision D22):

| Type | Meaning |
| --- | --- |
| `P` | owns a slot of pool `P`; never empty |
| `P?` | owns a slot of `P`, or is `none` |
| `id P` | refers to a slot of `P` without owning it |
| `id P?` | refers to a slot of `P`, or is `none` |

A record may name a pool declared after it only if the pool was announced
earlier with `forward pool P` (design decision D40); a forward pool may appear in
handle types, whose size doesn't depend on the record, but in nothing else until
the pool declaration completes it.

The non-optional forms are admitted only for locals with an initializer and for
parameters. Fields, array elements and program variables of handle type are
always optional, since they start as `none`.

A handle is not an address the program can see: there is no conversion between
handles and integers, no handle arithmetic, and no comparison of owning handles.
Identifiers of the same type may be compared with `=` and `<>`.

Owning handles are never copied; they are moved with `move` (Chapter 9). An
identifier is copied freely, and every use of it is checked (Chapter 7).

## 6.15 Owning types

A record type is an **owning type** if any of its fields has an owning handle
type (`P` or `P?`) or an owning type, directly or as the element of an array. An
array whose element type is owning is also an owning type. Owning types can't be
copied: whole-object assignment, by-value initialization and returning one by
value are invalid. They may be passed by alias, and their fields moved
individually (Chapter 7).
