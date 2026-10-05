# 8. Constants and declarations


## 8.1 Scope

This chapter defines the Basie 1.0 declaration families, their source forms, constant expressions, initializers, type inference for variables, and declaration-time binding. Chapter 4 defines the source parts and top-level placement. Chapter 5 defines declaration points, scopes, `private`, name identity and collisions. Chapter 6 defines types, and Chapter 7 storage, ownership and lifetime. Chapter 13 defines routines and calls, and Chapter 14 failure codes.

Basie uses explicit declarations. Every declaration introduces exactly one name, except a routine header, which also introduces its parameters. A variable's type is written, or inferred from an initializer that has a definite type (Section 8.10). Basie has no implicit variables, grouped declarations, destructuring declarations, or general type-alias declaration.

## 8.2 Declaration families and placement

| Declaration            | Permitted location | Binding or storage established |
| ---------------------- | ------------------ | ------------------------------ |
| Named constant         | Top level, or any statement position in a routine body | One scalar value, untyped or typed, or one typed read-only aggregate |
| Compile-time assertion | Top level          | No binding or storage; one condition checked during compilation |
| Program variable       | Top level          | One mutable program-lifetime object |
| Record type            | Top level          | One nominal fixed-layout record type and its field scope |
| Forward pool           | Top level          | A pool name usable in handle types before the pool is declared |
| Pool                   | Top level          | One pool of slots of one record type, with program lifetime |
| Forward routine        | Top level          | One routine signature without a body |
| Routine definition     | Top level          | One routine signature and body, or the completion of an earlier forward |
| Formal parameter       | Routine header     | One parameter binding (Chapter 13) |
| Local variable         | Any statement position in a routine body | One per-activation object, scalar, handle or aggregate |
| Record field           | Inside a record declaration | One named subobject of every object of the record type |

Any top-level declaration except a compile-time assertion may be preceded by `private` (Chapter 5, Section 5.11). A local constant or local variable is visible from its declaration point to the end of the innermost enclosing block (Chapter 5, Section 5.3).

Inside a routine body, the word `assert` begins the run-time assertion statement of Chapter 10, not a compile-time assertion.

## 8.3 Syntax

The following skeleton defines declaration syntax. `type` is defined by Chapter 6, and `expression` by Chapter 9; `statement` is defined by Chapter 10 and includes `local-declaration`. Chapter 17 gives the complete grammar.

```text
top-level-declaration ::= [ "private" ] private-able-declaration
                        | assert-declaration
private-able-declaration
                      ::= const-declaration
                        | program-var-declaration
                        | record-declaration
                        | forward-pool-declaration
                        | pool-declaration
                        | forward-routine-declaration
                        | routine-definition

const-declaration     ::= "const" NAME [ "as" type ] "="
                          constant-initializer NEWLINE
assert-declaration    ::= "assert" constant-expression NEWLINE

program-var-declaration
                      ::= "var" NAME "as" type
                          [ "=" static-initializer ] NEWLINE

record-declaration    ::= "record" NAME NEWLINE
                          field-declaration { field-declaration }
                          "end" NEWLINE
field-declaration     ::= NAME "as" type NEWLINE

forward-pool-declaration
                      ::= "forward" "pool" NAME NEWLINE
pool-declaration      ::= "pool" NAME "as" NAME "[" constant-expression "]"
                          NEWLINE

forward-routine-declaration
                      ::= "forward" routine-header NEWLINE
routine-definition    ::= "sub" NAME ( routine-signature-tail NEWLINE
                                     | NEWLINE ) block "end" NEWLINE
routine-header        ::= "sub" NAME routine-signature-tail

local-declaration     ::= "var" NAME "as" type [ "=" local-initializer ]
                          NEWLINE
                        | "var" NAME "=" local-initializer NEWLINE
                        | const-declaration
local-initializer     ::= expression [ "else" "fail" ]
                        | static-initializer

constant-initializer  ::= constant-expression | static-initializer
static-initializer    ::= constant-expression
                        | STRING
                        | "(" static-initializer { "," static-initializer } ")"
                        | "[" static-initializer { "," static-initializer } "]"
```

`routine-signature-tail` is defined by Chapter 13; it includes parameters, an optional result type, an optional `from` clause and an optional `fails`. A forward routine declaration is distinguished from a forward pool by the token after `forward`.

The declared type selects the initializer form. A parenthesized scalar expression and a record initializer both begin with `(`; when the declared type is a record, `(` begins a record initializer, and otherwise an expression. No backtracking is needed. In the inferred form `var NAME = ...`, which has no declared type, the initializer is always an expression.

Parentheses and square brackets suppress logical newlines (Chapter 3), so a structured initializer may span physical lines.

## 8.4 Named constants

A named constant is **untyped** or **typed** (design decision D20):

```nucleus
const bufferLength = 64            // untyped
const enabled = true               // untyped
const big as u32 = 70000           // typed
const half as f32 = 0.5            // typed
const Origin as Point = (0, 0)     // aggregate constants are always typed
```

**Untyped constants.** Without `as`, the initializer must be a constant expression (Section 8.6) whose value is an exact integer, a `boolean`, or a character. An untyped integer constant behaves like an integer literal at every use: it adopts whatever integer type the context requires, if its value fits that type (Chapter 6). So `const Big = 300` is valid; a use of `Big` where `u8` is required is invalid at that use, while a use where `u16` or `i16` is required is valid. The compiler reports the incompatible use, not the declaration. An untyped constant whose initializer is a floating-point literal or a typed expression is invalid; it must be written with a type.

**Typed scalar constants.** With `as` and a scalar type, the constant has exactly that type at every use, as a variable of that type would. The initializer must be a constant expression compatible with the type under the ordinary conversion rules of Chapter 6; a value outside the type's range is an error at the declaration. A `f32` constant must be typed.

**Aggregate constants.** With `as` and a record, fixed-array or bounded-string type, the constant is a read-only aggregate (Section 8.5).

A scalar constant has no storage that source can observe. The compiler may place its value in generated code or read-only data. Named constants are the way to give integers symbolic names, including failure codes (Chapter 14, design decision D26). A constant declaration does not create an enumeration, subrange, distinct integer type or overload.

**Local constants.** A constant may be declared at any statement position in a routine body, with the same forms and rules. Its initializer is still a constant expression: it cannot read a parameter, local, variable or field, or call a routine. Its scope is its block (Chapter 5).

## 8.5 Aggregate constants

An aggregate constant declares one explicitly typed, statically initialized record, fixed array or bounded string:

```nucleus
const Origin as Point = (0, 0)
const Masks as u8[4] = [$01, $02, $04, $08]
const Prompt as string[8] = "READY"
```

The initializer is required and follows the static-initializer rules of Section 8.9. The type of an aggregate constant must not be an owning type (Chapter 6) and must contain no handle.

The named root is read-only. Assignment rooted directly at the constant's name is invalid: to the whole object, a field, an element or a byte of a bounded string. The constant is otherwise an ordinary aggregate: field and index selection, `.length`, whole-object assignment from it, and passing it as an argument are admitted.

An aggregate parameter without `var` is read-only in the routine (Chapter 13, design decision D17), and a constant cannot be passed to a `var` parameter, so no source operation can change an aggregate constant. An implementation may place aggregate constants in read-only storage.

## 8.6 Constant expressions

A **constant expression** contains only:

- integer, floating-point, character and Boolean literals;
- earlier named constants, untyped or typed scalar;
- parentheses; and
- the operators and explicit conversions that Chapter 9 admits in constant expressions.

It cannot read a variable, parameter, field, element or string, call a routine, use a handle, or perform an observable operation. It has no layout, address, offset or run-time length query.

The compiler evaluates a constant expression at compile time with exactly the operand types, result types, wrapping, rounding and trap rules that Chapter 9 gives the corresponding run-time operation. It must not substitute host arithmetic, widen a typed operation, or fold differently from the run-time operation. In particular, typed integer arithmetic wraps as at run time (design decision D5), and `f32` arithmetic rounds to nearest, ties to even, with results below the smallest normal flushed to zero (D7). An operation that Chapter 9 defines to trap at run time, such as division by zero or a narrowing conversion out of range, makes the constant expression invalid.

An expression made only of untyped operands is evaluated exactly, as a mathematical integer, until a typed operand, a conversion or the context supplies a type. Its value must then fit that type. An untyped intermediate value outside the range of `i32` and `u32` together, that is below −2,147,483,648 or above 4,294,967,295, is invalid.

An array length is a constant expression whose value must lie from 1 through 65,535, and a `string[N]` capacity one whose value must lie from 1 through 253. A pool capacity must lie from 1 through 65,535. The compiler evaluates each bound before constructing the type, so a later constant, a variable or a cycle cannot supply a bound. The string capacity limit belongs to `string[N]` alone; arrays, records and pools have no such ceiling, though an implementation may diagnose an object too large for its published capacity.

## 8.7 Compile-time assertions

A compile-time assertion has this top-level form:

```nucleus
assert Rows * Columns <= 256
```

Its operand must be a constant expression of type `boolean`; `assert Rows` is invalid. The compiler evaluates it while checking the declaration. A true result accepts the declaration. A false result is diagnosed as `assertion-false` at the `assert` keyword. The declaration introduces no name or storage and generates no code.

Inside a routine body, `assert` is the run-time statement of Chapter 10. A run-time assertion whose condition is a constant expression that evaluates to false is likewise diagnosed during compilation (design decision D37).

## 8.8 Record declarations

A record declaration introduces one nominal type:

```nucleus
record Point
    x as i16
    y as i16
end
```

The declaration contains at least one field. Each field declares one name and one type already declared or built in. Handle types naming a pool that has only a forward declaration are admitted (design decision D40). A field has no `var` or `const` keyword, initializer, default or mutability qualifier.

A field may have any type admitted by Chapter 6 except a non-optional handle type: a field of handle type is written `P?` or `id P?` (design decision D22), because a field starts as `none`. A record with a field of owning handle type, directly or through a nested record or array, is an **owning type** (Chapter 6).

The record type becomes visible only after its declaration is complete, so it cannot appear in its own field list. Recursive structures are built with handles into a pool, not by containment.

Field names use the record's field scope (Chapter 5). An exact duplicate within one record is invalid.

## 8.9 Program variables and static initializers

A top-level `var` declaration declares one mutable program-lifetime object of any type admitted by Chapter 6, except a non-optional handle type: a program variable of handle type is written `P?` or `id P?`. The type is always written; a program variable's type is not inferred.

Without an initializer, the object starts at its type's zero value (Chapter 7): integer and floating-point zero, `false`, an empty bounded string, `none` for every handle, and recursively zero for records and arrays.

An initializer is a **static initializer**:

| Declared type | Permitted initializer |
| --- | --- |
| A numeric type, `boolean` | One compatible constant expression |
| `string[N]` | One string literal of at most `N` decoded bytes |
| Record | `( ... )` with exactly one static initializer per field, in declaration order |
| Fixed array | `[ ... ]` with exactly one static initializer per element, in index order |
| A handle type | none; a handle variable cannot have an initializer |
| An owning type | none; it starts zeroed, with every handle `none` |

A string literal sets both the bytes and the length; a literal longer than the capacity is invalid and is never truncated. Nested records, arrays and strings use their own initializers at the corresponding positions. Every level is complete: too few or too many components are invalid. A static initializer cannot name a variable or another aggregate, or call a routine.

Aggregate constants use the same static initializers.

The variable becomes visible only after its type and initializer have been checked.

## 8.10 Local variables and inference

A local variable may be declared at any statement position in a routine body (design decision D28). It lives for one activation of its block: it is created when execution reaches the declaration and its lifetime ends when control leaves the innermost enclosing block. Its scope is described in Chapter 5.

**Types.** A local may have any type admitted by Chapter 6: a numeric type, `boolean`, a record, a fixed array, a bounded string, an array of arrays, or a handle type, including the non-optional forms `P` and `id P`. A local of non-optional handle type must have an initializer.

**Initial values.** A local with an initializer receives its value when execution reaches the declaration. Without one, a scalar starts at zero or `false`, a handle at `none`, a bounded string empty, and a record or array zeroed in full ([memory safety](../docs/memory-safety.md), Section 5.13). A local is always initialized before it can be read.

**Initializers.** A local's initializer is one of:

- an expression of a type compatible with the declared type (Chapters 6 and 9), evaluated once at the declaration;
- a direct call to a failing routine followed by `else fail` (Chapter 14); or
- for a declared record, array or string type, a static initializer (Section 8.9), which may then use only constants.

An initializer for an owning handle follows the transfer rules of Chapter 7: a fresh value, the result of `new` or of a routine returning an owning handle, is stored directly; an existing owner must be written with `move`.

**Inference.** A local declared without `as` takes the type of its initializer (design decision D21), which must have a **definite type**:

- a variable, parameter, typed constant or field, or an element or selection of one;
- the result of a routine call, a `new` or `new?` expression, or `id(...)`;
- an explicit conversion; or
- `true`, `false`, a floating-point literal or a comparison, which Chapter 9 types as `boolean` or `f32`, or a character literal, which an inferred local takes as `u8`; or
- an expression whose type Chapter 9 determines from operands that have definite types.

An exact integer has no definite type: an integer literal, an untyped integer constant, or an expression built only from them. A local initialized with one must state its type. So must a local initialized with a string literal or `none`. An open view (`string[]` or `T[]`) is never a local's type, so a `string[]` or `T[]` parameter can't initialize an inferred local (Chapter 6, Section 6.8):

```nucleus
var d = distance(a, b)        // the routine's result type
var p = Origin                // Point, from the constant's type
var n = new nodes(5, none)    // nodes, an owning handle
var count as u16 = 0          // a bare literal: the type must be written
var bad = 0                   // invalid: no definite type
```

An inferred local of a record, array or string type is a copy of its initializer, which must therefore not be of an owning type: no aggregate value is ever fresh, since aggregate results are aliases (Chapter 6, Section 6.5).

The local becomes visible only after its declaration has been checked, so its initializer cannot name it.

## 8.11 Pools

A pool declaration declares a pool of slots, each holding one record of a single record type (Chapter 7):

```nucleus
forward pool nodes

record Node
    value  as u16
    next   as nodes?          // owns the next node
    parent as id nodes?       // refers to the parent
end

pool nodes as Node[64]
```

- The element type after `as` must be a record type already declared. A pool of a scalar, array or string type is invalid; such data is wrapped in a record.
- The capacity in brackets is a constant expression from 1 through 65,535 (Section 8.6).
- A pool has program lifetime. Its slots start free. Pools are declared only at top level, and a pool may be `private`.
- The pool name, used as a type, denotes an owning handle into the pool (design decision D22); Chapter 6 defines the four handle types `P`, `P?`, `id P` and `id P?`. The pool name is also the operand of `new` and `new?` (Chapters 7 and 9).
- Each pool declares a distinct handle type, even when two pools have the same record type. Programs normally declare one pool per record type (design decision D23).

**Forward pools.** A record and its pool may refer to each other: the record has a field of the pool's handle type, and the pool names the record. `forward pool P` declares `P` before its record type and capacity are known (design decision D40). Until the matching pool declaration:

- `P` may be used only in handle types, which have a fixed size whatever the record is; and
- no `new P` or `new? P`, no access to a record through a handle of `P`, and no `id(...)` of such a handle is valid.

A forward pool must be completed by exactly one pool declaration of the same name in the same compilation, and a pool may have at most one forward declaration. A `private` forward pool must be completed in the same part and by a `private` pool declaration; a forward pool that is not `private` must be completed by a pool declaration that is not `private`. A forward pool still incomplete at the end of the compilation is diagnosed.

## 8.12 Routine declarations and parameters

A routine header declares a routine name, an ordered list of zero or more parameters, an optional result type, an optional `from` clause, and an optional `fails`. Each parameter is written `NAME as Type`, optionally preceded by `var` (design decision D17). Parameters have no initializers or defaults. Chapter 13 defines parameter passing, `var`, leases, `from`, results and calls.

A forward routine declaration contains the complete signature and no body. The later definition has the abbreviated header `sub NAME`, and the forward's parameter names become the body's parameter bindings (Chapter 4, Section 4.6). A routine whose body is not yet complete can be called only through a forward declaration, which includes a routine calling itself (Chapter 5, Section 5.9).

Routines are declared only at top level; Basie has no nested routines.

## 8.13 Initialization order

Constant expressions are evaluated during compilation. Aggregate constants and the initial values of program variables form a static image that exists before execution begins; static initializers have no effects and read no storage, so their order is not observable. Pools start with every slot free. Chapter 19 defines startup.

In a routine, parameters are bound when the routine is entered. Each local variable is initialized when execution reaches its declaration, in source order. A local declared in a loop body is created afresh, with its initializer evaluated again, on every iteration; an owning local in a loop body is freed at the end of each iteration (Chapter 7).

## 8.14 Diagnostics and capacity

The compiler must diagnose:

- a declaration in a location not permitted by Section 8.2, including a record, pool or routine inside a routine body;
- a type, bound, initializer or name not visible at its declaration point;
- an exact duplicate name or forbidden shadowing (Chapter 5);
- a nonconstant operand, or an operation that would trap, in a constant expression;
- an untyped constant whose value is not an exact integer, a character or a `boolean`;
- an initializer incompatible with its declared type, or a typed constant out of its type's range;
- an inferred local whose initializer has no definite type;
- an invalid array length, string capacity, pool capacity, string literal length, or initializer shape;
- a record with no fields, or a field, program variable or array element of non-optional handle type;
- a non-optional handle local without an initializer;
- a static initializer for a handle or an owning type;
- assignment rooted at an aggregate constant;
- a pool whose element type is not a record;
- a use of a forward pool other than in a handle type before its completion, and a forward pool not completed, completed twice, or completed with a different visibility; and
- a false compile-time assertion (`assertion-false`).

An implementation may bound the numbers of declarations, fields, parameters, locals, pools, constant-expression nesting, initializer depth and elements, and similar resources. It must publish each limit ([limits register](../docs/limits.md)) and diagnose an excess before any truncation, wrapping, omission or incorrect binding can occur.

## 8.15 Examples

These declarations are valid:

```nucleus
const cellCount = 8
const scale as f32 = 0.125
const notFound = 48               // a failure code (Chapter 14)

record Cell
    value as i16
    active as boolean
end

const defaultCell as Cell = (0, false)
const bitMasks as u8[4] = [1, 2, 4, 8]
var cells as Cell[cellCount]
var templates as Cell[2] = [(1, true), (-2, false)]
var title as string[12] = "BASIE"

forward pool nodes
record Node
    value as u16
    next as nodes?
end
pool nodes as Node[100]
var head as nodes?

private const scratchSize = 32
```

A routine declares locals where it needs them:

```nucleus
sub fill(var items as Cell[cellCount], start as i16)
    const step = 2
    var next = start                  // i16, from the parameter
    var i as u8
    for i = 0 until cellCount
        var cell as Cell = (0, true)  // a fresh local on every iteration
        cell.value = next
        items[i] = cell
        next = next + step
    end
end
```

These are invalid; they are not one compilation:

```nucleus
const Limit = 8
var Limit as u16                     // exact duplicate
const half = 0.5                     // a floating-point constant must be typed
const tiny as u8 = 300               // out of range for u8
var empty as u8[0]                   // an array length must be at least 1
var shortText as string[4] = "READY" // the literal is too long
var owner as nodes                   // a program variable of handle type must be optional
pool numbers as u16[10]              // a pool holds records

sub bad()
    var x = 0                        // no definite type
    var n as nodes                   // a non-optional handle needs an initializer
    defaultCell.value = 1            // assignment to a constant
end
```
