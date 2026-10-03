# 6. Types


## 6.1 Scope

This chapter defines the Baton 1.0 type set, type identity, compatibility, scalar conversions, aggregate categories, and the static type carried by aggregate aliases. Chapter 7 defines storage duration and lifetime. Chapter 8 defines declarations and initialization. Chapter 9 defines expression syntax and operator typing, and Chapter 13 defines routine syntax and parameter passing.

The type system supports local checking during one streaming source pass. A compiler can determine the type of a name, field, array element, literal in context, or routine result from declarations already processed. It requires neither whole-program inference nor runtime type tags.

## 6.2 Type set

Baton 1.0 has three scalar types, three owned aggregate forms, and one
parameter-only aggregate view:

| Category        | Types or forms                       |
| --------------- | ------------------------------------ |
| Scalar          | `u8`, `u16`, `boolean`               |
| Owned aggregate | nominal records, `T[N]`, `string[N]` |
| Parameter view  | `string[]`                           |

The following skeleton records type formation without defining declaration grammar:

```text
type             ::= scalar-type
                   | record-type-name
                   | fixed-array-type
                   | bounded-string-type
scalar-type      ::= "u8" | "u16" | "boolean"
fixed-array-type ::= element-type "[" array-length "]"
element-type     ::= scalar-type | record-type-name | bounded-string-type
bounded-string-type
                 ::= "string" "[" [ string-capacity ] "]"
```

An array has one dimension. An array element may be a scalar, record, or bounded string, but not another array. Records may contain fields of any admitted type, including fixed arrays.

`string[N]` is the owned bounded-text form. An omitted capacity is admitted only
in a formal parameter: `string[]` denotes a view whose actual capacity comes
from the argument. `string` is a core reserved word. No other type word is
added by this chapter.

## 6.3 Scalar types

`u8` is the unsigned integer type whose values range from 0 through 255. `u16` is the unsigned integer type whose values range from 0 through 65,535. Their widths and ranges do not vary by target.

`boolean` has exactly the values `false` and `true`. It is distinct from both integer types. An integer is not a condition, a Boolean value is not an integer, and Baton 1.0 provides no Boolean-to-integer or integer-to-Boolean conversion.

A scalar variable, parameter, field, array element, or routine result holds a scalar value. Scalar assignment and scalar argument passing copy the value. A compiler may use any private register or memory representation that preserves the type and value; that representation does not alter source compatibility.

## 6.4 Literals and scalar conversion

An integer literal is exact and has no fixed integer type until an expected integer type or an expression rule supplies one. In a declaration initializer, scalar argument, assignment, return, array index, or other expected-type position, a literal may take type `u8` or `u16` when its value lies in that type's range. A literal outside the expected range is invalid; it is not truncated or wrapped.

Chapter 9 defines the treatment of an integer literal with no expected type and the result types of operators. This chapter does not assign an expression-wide default type.

A character literal has type `u8` and its value is the decoded byte from Chapter 3. Baton has no separate character type. The ordinary `u8`-to-`u16` widening rule permits a character literal where a `u16` value is expected.

The only implicit conversion between declared scalar types is `u8` to `u16`. It preserves every source value and zero-extends in representations where extension is required. The same conversion applies to assignment, initialization, scalar arguments, scalar results, and operands when Chapter 9 admits a mixed-width operation.

Conversion from `u16` to `u8` requires an explicit checked narrowing operation. Chapter 9 defines its expression spelling. When the source value is known and exceeds 255, the compiler must issue a diagnostic. When the value is not known until execution, the generated program must trap before producing or storing a `u8` result if the value exceeds 255. Checked narrowing never means low-byte extraction, modulo reduction, or reinterpretation.

No implicit or explicit scalar conversion changes `boolean` into an integer or an integer into `boolean`. Baton 1.0 also has no arbitrary cast or same-width reinterpretation operation.

## 6.5 Values, aggregate storage, and aliases

The source type and the way a source occurrence denotes data are separate properties:

| Category                | Meaning                                                                                            |
| ----------------------- | -------------------------------------------------------------------------------------------------- |
| Scalar value            | A `u8`, `u16`, or `boolean` value that can be copied by assignment, argument passing, or return.   |
| Owned aggregate storage | Storage containing one record, fixed array, or bounded string for a lifetime defined in Chapter 7. |
| Aggregate alias         | A typed, non-owning binding to existing aggregate storage.                                         |

A scalar named constant has either an exact integer type inferred from its initializer or type `boolean`. A record, fixed array, or bounded-string constant has an explicit aggregate type and complete static initializer under Chapter 8.

Top-level variables and aggregate constants provide owned aggregate storage. Aggregate storage may also occur inline as a record field or fixed-array element. A routine cannot declare aggregate storage or an aggregate-alias local. The permitted declaration sites, initialization rules, mutability, and storage duration appear in Chapters 7 and 8.

An aggregate parameter is a fixed typed alias to caller-provided storage. Its binding cannot be changed, but mutation through it changes the caller's object. A parameter declared as `string[]` additionally retains the concrete argument's capacity for checked access. A routine may also return a transient aggregate alias to existing storage, but an open-string view cannot be a result.

Assignment between aggregate designators of the exact same concrete type copies the complete value into the destination. This includes two bounded strings with the same capacity. Assignment changes the destination object's contents and never rebinds an alias. Routine arguments and aggregate results transfer aliases rather than copying automatically. Concrete aggregate parameters and all aggregate results require exact type identity; `string[]` parameters use the specific compatibility rule in Section 6.10.

An aggregate routine result is a transient typed alias to existing program-lifetime storage. Chapter 7 defines its permitted consumption, and Chapter 13 defines result syntax. Baton has no aggregate storage whose lifetime ends with a call, so aggregate results require no separate escape analysis.

## 6.6 Record types

A record declaration creates one nominal type. Two record declarations create different types even when their fields have identical names and types. Record storage and aliases are compatible only with the type created by the same declaration.

Every record has one fixed field sequence and one fixed layout. Each field has a name and one previously declared type. A field may have scalar, record, fixed-array, or bounded-string type. The complete field sequence is known when the record declaration ends.

A record must have finite size. A field therefore must not contain its own record type directly or through a cycle of record and array containment. Variant records, unions, and overlaid layouts are absent.

Selecting a scalar field produces a scalar occurrence of the field's declared type. Selecting an aggregate field produces a storage path or aggregate alias with the field's exact aggregate type. Selection does not expose a byte offset or address to source code.

Chapter 8 defines record declaration and field syntax. Runtime byte offsets and packed layout belong to the Z80 runtime and backend contract.

## 6.7 Fixed-array types

`T[N]` is a one-dimensional fixed array with element type `T` and length `N`. `N` must be a positive compile-time integer from 1 through 65,535. A compiler may publish a smaller capacity for a particular storage region or implementation, but exceeding that capacity is a capacity failure rather than another array type.

The index domain is always zero through `N - 1`. Baton has no arbitrary lower bound, subrange index, enumeration index, or range type. The length and element type are part of the array type.

Two fixed-array types are identical when their element types are identical and their lengths are equal. Thus `u8[16]` and `u8[16]` are the same type, while `u8[16]`, `u8[32]`, and `u16[16]` are three different types.

An array index must have type `u8` or `u16`; `u8` widens to `u16` when the checking operation requires it. A constant index outside the array domain is invalid. A dynamic index must be checked before the access unless the compiler proves from information already available at that point that it lies in the domain. A failed dynamic check performs the bounds trap specified by Chapter 15 before any element load or store.

Indexing an array of scalars produces a scalar occurrence with the element type. Indexing an array of records or bounded strings produces a storage path or aggregate alias with the element type. The index operation never produces an untyped address.

## 6.8 Bounded strings

`string[N]` is a fixed-capacity counted sequence of bytes with a current length from 0 through `N`. `N` is a compile-time integer from 1 through 253 and is part of the type. The empty string is a valid value. Payload bytes may have any value from 0 through 255, including zero.

A string literal is a contextual bounded-string initializer. It is compatible with `string[N]` when its decoded byte length does not exceed `N`. A literal that is too long is invalid. The literal does not create an open-ended string type or infer a capacity independently of its context.

Two concrete bounded-string types are identical only when their capacities are equal. An alias to `string[16]` cannot bind to a `string[32]` parameter or result, even when the current contents would fit both. Concrete aggregate aliases and results therefore retain an exact extent.

A bounded string is an aggregate, not a `u8` array. It has no source-level header field, payload field, or terminator field. Baton 1.0 provides two intrinsic postfix operations without exposing that representation:

- `text.length` is a read-only `u8` value equal to the current logical byte length.
- `text[index]` selects one existing byte as a `u8` storage path. The index must have type `u8` or `u16` and must be less than the current length. A failed check performs the `bounds` trap before a read or write.

A bounded string's length is established by static initialization or copied as part of exact-type aggregate assignment. A byte assignment replaces exactly one existing byte and does not change the string's length or capacity. These operations provide no append, insertion, resize, truncation, slice, or splice. Source code cannot build counted text by filling bytes and then changing the length. Embedded zero bytes are ordinary content.

Bounded strings have no comparison operators. A library routine can compare two `string[]` parameters by checking their lengths and indexed bytes.

The `.length` intrinsic applies only when the postfix base has bounded-string type. On a record base, `.length` remains ordinary lookup in that record's field scope. Any other field suffix on a bounded string is invalid.

`string[]` is a parameter-only, capacity-polymorphic view. A call may bind it to a concrete `string[N]` storage path or transient alias, for any admitted `N`, or forward another `string[]` parameter. The view retains the actual capacity for `.length` and checked indexing. It does not own storage and is invalid as a variable, constant, record field, array element, local, or routine result. Whole-object assignment and comparison through an open view are invalid.

A string literal remains a contextual static initializer, not a general aggregate expression or argument. Passing literal text therefore requires a named concrete bounded-string object in this version. `string[]` is not a slice: it always views one complete bounded-string object, has no offset or independently chosen length, and cannot be rebound.

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
| `u8`            | The predefined `u8` type.                                          |
| `u16`           | The predefined `u16` type.                                         |
| `boolean`       | The predefined Boolean type.                                       |
| Record          | The single declaration that introduced the record.                 |
| Fixed array     | Identical element type and identical fixed length.                 |
| `string[N]`     | Identical capacity `N`.                                            |
| `string[]`      | Parameter-only view over one complete concrete bounded string.     |
| Aggregate alias | The exact referent type; aliasing adds a category, not a new type. |

The compiler applies these compatibility rules:

| Context                                                | Required compatibility                                                                                          |
| ------------------------------------------------------ | --------------------------------------------------------------------------------------------------------------- |
| Scalar assignment, initialization, argument, or result | Exact scalar type, fitting exact integer literal or named constant, or implicit `u8`-to-`u16` widening.         |
| Checked narrowing to `u8`                              | Explicit operation and successful range check.                                                                  |
| Boolean condition or destination                       | `boolean` only.                                                                                                 |
| Record field selection                                 | The field's declared type.                                                                                      |
| Fixed-array index                                      | `u8` or `u16` index; result has the exact element type.                                                         |
| Bounded-string `.length`                               | Read-only `u8` value equal to the current logical length.                                                       |
| Bounded-string index                                   | `u8` or `u16` index below the current length; result is a writable `u8` path.                                   |
| Concrete aggregate parameter                           | Exact referent-type identity.                                                                                   |
| `string[]` parameter                                   | Any concrete bounded-string storage path or transient alias, or another `string[]`; retain the actual capacity. |
| Aggregate assignment                                   | Exact concrete type identity; copy the complete aggregate into the destination.                                 |
| Aggregate result                                       | Exact referent-type identity and immediate consumption under Chapter 7.                                         |
| Aggregate by-value argument or result                  | Invalid; calls transfer aggregate aliases.                                                                      |

Compatibility is checked at the source operation. The backend does not infer compatibility from equal byte widths, equal layouts, compiler storage ordinals, registers, or runtime addresses.

## 6.11 Excluded type mechanisms

Baton 1.0 has none of the following:

- raw pointer or address types visible to source;
- pointer or address arithmetic;
- implicit word/address interchange;
- enumeration or subrange types;
- set types;
- variant records, unions, or overlaid aggregate layouts;
- structural equivalence between distinct record declarations;
- arbitrary casts, type punning, or unchecked narrowing;
- generic types or generic parameters other than the single built-in `string[]` form;
- open arrays, slices, or user-defined variable-capacity views;
- heap-allocated or resizable types;
- variable-sized local allocation; or
- unrestricted dynamic data.

An implementation must diagnose a source form that requires one of these mechanisms. Equal storage width or a convenient machine representation does not admit the source operation.

## 6.12 Type metadata and capacity

Exact type identity is checked from retained metadata without reconstructing source text. Record declarations require nominal IDs. Predefined scalars, fixed arrays, and bounded strings have compact, bounded structural descriptions: kind, element type when applicable, and length or capacity. A compiler may store those descriptions directly in symbols and signatures or intern them behind compact ordinals. Measurements of compiler-core bytes, immutable data, writable workspace, and comparison code determine the representation used by the first implementation.

One direct representation fits every admitted type in four bytes. Its kind byte distinguishes the three scalars, records, bounded strings, and the five permitted array-element families. A second byte carries a record ordinal or string capacity where needed, and two bytes carry an array length. Folding the element family into the array kind is valid because arrays cannot contain arrays. It does not remove arrays of records, arrays of bounded strings, or aliases to any aggregate type; alias category is stored separately from referent-type identity.

Four inline bytes are not automatically cheaper than one ordinal per symbol. With mostly distinct types, direct descriptors avoid an interning table; with many repeated types, ordinals reduce writable symbol storage. The measurement package reports both retained-data totals for representative symbol populations. The first compiler also counts the code and scratch state for descriptor construction, interning, exhaustion checks, and equality before selecting either form.

Every selected representation has a published capacity. An ordinal representation diagnoses exhaustion before an ID wraps or aliases another type. An inline representation diagnoses any limit on element-type nesting, length, capacity, symbol entries, record fields, or signatures before truncation changes a compatibility result. A byte-sized type ID remains a candidate, not a language or target requirement.

The numeric type ID has no source meaning and need not match across compilations. Z80 registers and compiler-managed storage locations are untagged; the compiler's symbol and expression metadata supply their current source types. Runtime type tags, reflection, and dynamic type tests are absent.

## 6.13 Examples

These declarations illustrate scalar compatibility:

```nucleus
var byteValue as u8 = 42
var wordValue as u16 = byteValue
var code as u8 = 'A'
var flag as boolean = true
```

Each of the following is invalid under this chapter:

```nucleus
var tooSmall as u8 = 256       // literal does not fit
var narrowed as u8 = wordValue // explicit checked narrowing required
var truth as boolean = 1       // integer is not Boolean
var count as u16 = false       // Boolean is not integer
```

Record identity is nominal:

```nucleus
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

```nucleus
var bytes as u8[16]
var name as string[12]
```

`bytes[0]` through `bytes[15]` are within the declared domain. `bytes[16]` is a compile-time error. A runtime value used as the index is checked before access. `string[12]` and `string[16]` are different types, and a thirteen-byte literal cannot initialize `name`.

For a bounded string `name`, `name.length` reads its logical length and `name[index]` reads or replaces one existing byte. An index equal to the current length traps; assignment through the index does not append or change `name.length`.
