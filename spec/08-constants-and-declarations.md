# 8. Constants and declarations


## 8.1 Scope

This chapter defines the Baton 1.0 declaration families, their canonical source forms, constant expressions, initializers, and declaration-time binding. Chapter 4 defines the compilation-unit sequence and top-level placement. Chapter 5 defines declaration points, scopes, name identity, and collisions. Chapters 6 and 7 define types, storage ownership, aggregate aliases, and lifetime. Chapter 13 defines routine calls, results, and complete routine semantics.

Baton uses explicit declarations. Variables, fields, parameters, locals, routine results, and aggregate constants have explicit types; scalar named constants infer their type from the required initializer. Baton has no implicit variables, grouped declarations, destructuring declarations, or general type-alias declaration.

## 8.2 Declaration families and placement

The declaration families are:

| Declaration            | Permitted location                          | Binding or storage established                                                            |
| ---------------------- | ------------------------------------------- | ----------------------------------------------------------------------------------------- |
| Named constant         | Top level                                   | One inferred scalar value or one explicitly typed read-only aggregate root                |
| Compile-time assertion | Top level                                   | No binding or storage; one required compile-time condition                                |
| Program variable       | Top level                                   | One mutable program-lifetime scalar or aggregate object                                   |
| Record type            | Top level                                   | One nominal fixed-layout record type and its field scope                                  |
| Forward routine        | Top level                                   | One routine signature without a body                                                      |
| Routine definition     | Top level                                   | One routine signature and body, or completion of an earlier forward                       |
| Formal parameter       | Routine header                              | One scalar activation value, concrete aggregate-alias binding, or `string[]` view binding |
| Scalar local           | Contiguous routine declaration prefix       | One per-invocation scalar value                                                           |
| Record field           | Between a record header and its closing end | One named scalar or aggregate subobject in each object of the record type                 |

Only top-level declarations occur in the compilation-unit sequence. Parameters occur only in a routine header. Local declarations form one contiguous prefix after the header and before the first statement. A conditional or loop body cannot contain a declaration, and a declaration after the first statement of a routine is invalid.

Baton 1.0 has no routine-local constant declaration or assertion.

## 8.3 Canonical syntax

The following skeleton defines declaration syntax without defining statement grammar or the internal syntax of ordinary expressions:

```text
top-level-declaration ::= const-declaration
                        | assert-declaration
                        | program-var-declaration
                        | record-declaration
                        | forward-routine-declaration
                        | routine-definition

const-declaration     ::= "const" NAME "="
                          scalar-constant-expression NEWLINE
                        | "const" NAME "as" type "="
                          static-initializer NEWLINE

assert-declaration    ::= "assert" scalar-constant-expression NEWLINE

program-var-declaration
                      ::= "var" NAME "as" type
                          [ "=" program-initializer ] NEWLINE

record-declaration    ::= "record" NAME NEWLINE
                          field-declaration
                          { field-declaration }
                          "end" NEWLINE
field-declaration     ::= NAME "as" type NEWLINE

forward-routine-declaration
                      ::= "forward" routine-header NEWLINE
routine-definition    ::= "sub" NAME routine-definition-tail
routine-definition-tail
                      ::= routine-signature-tail NEWLINE routine-body
                        | NEWLINE routine-body
routine-body          ::= { local-declaration }
                          routine-statement-sequence
                          "end" NEWLINE
routine-header        ::= "sub" NAME routine-signature-tail
routine-signature-tail
                      ::= "(" [ formal-parameter
                          { "," formal-parameter } ] ")"
                          [ "as" type ] [ "fails" ]
formal-parameter      ::= NAME "as" type

local-declaration     ::= "var" NAME "as" scalar-type
                          [ "=" local-initializer ] NEWLINE
local-initializer     ::= expression [ "else" "fail" ]

program-initializer   ::= static-initializer
static-initializer    ::= scalar-constant-expression
                        | STRING
                        | record-initializer
                        | array-initializer
record-initializer    ::= "(" static-initializer
                          { "," static-initializer } ")"
array-initializer     ::= "[" static-initializer
                          { "," static-initializer } "]"
```

`type` and `scalar-type` are defined by Chapter 6. The parser selects a program initializer from the declared type. A parenthesized scalar expression and a record initializer share `(` as their first token; the already checked program-variable or component type selects the form without backtracking. `routine-statement-sequence` and `expression` are placeholders for later chapters, not additional declaration syntax.

Each constant, variable, record header, field, and local declaration introduces one name. A routine header introduces one routine name and its individually written parameters. Each field and parameter repeats the canonical `name as Type` form. No comma-separated field or variable group is permitted.

Parentheses and square brackets suppress logical newlines under Chapter 3. A structured initializer may therefore span physical lines without adding newline productions to this grammar.

## 8.4 Named constants

A scalar named constant declaration has this form:

```nucleus
const bufferLength = 64
const readyMask = 128
const enabled = true
```

The initializer determines the constant's type. A Boolean-valued initializer gives the constant type `boolean`. An integer-valued initializer gives it an exact integer type: the value has no fixed `u8` or `u16` type until each use supplies an expected integer type or an expression rule selects one.

An exact named integer constant behaves like an exact integer literal at every use. The same constant may adopt `u8` in one context and `u16` in another when its value fits both. A declaration such as `const Big = 300` is valid; a later use of `Big` where `u8` is required is invalid at that use, while a use where `u16` is required is valid. The compiler reports the position of the incompatible use rather than the constant declaration.

A scalar named constant denotes its compile-time scalar value. It does not declare storage and need not occupy runtime storage. The compiler may materialize the value in generated code or immutable implementation data, but no source operation exposes object identity for it.

The initializer is required and must be a scalar constant expression. Its completed value must be either integer-valued or Boolean-valued. A named constant becomes visible only after the compiler has checked the complete declaration, so its initializer cannot name itself. Chapter 5's declaration-order rule also excludes later names and constant cycles.

Named integer constants replace enumeration members where a program needs symbolic numeric values. A constant declaration does not create an enumeration, subrange, distinct integer type, or overload.

## 8.5 Aggregate constants

An aggregate constant declares one explicitly typed, statically initialized record, fixed array, or bounded string:

```nucleus
const Origin as Point = (0, 0)
const Masks as u8[4] = [$01, $02, $04, $08]
const Prompt as string[8] = "READY"
```

The initializer is required and follows the same complete, type-directed static-initializer rules as a program variable. Every scalar leaf is a compatible scalar constant expression. The declaration cannot use a runtime expression, read storage, call a routine, omit a component, or name the constant being declared. A scalar type after `as` is invalid: scalar constants retain the inferred form from Section 8.4.

The named root is read-only. Source assignment cannot be rooted directly at the aggregate constant name, including assignment to the complete object, one record field, one array element, or one bounded-string byte. The constant remains an ordinary aggregate source: field and index selection, `.length`, exact-type aggregate assignment, aggregate argument passing, and aggregate return are admitted.

Read-only status is deliberately not part of the aggregate alias type. Passing a constant to an aggregate parameter or returning it as an aggregate result removes the direct-root distinction, so mutation through that alias is permitted by the language and is not dynamically checked. A target that places the bytes in writable memory may observe the change; a target that places them in ROM may ignore or reject the physical write. Portable programs treat aggregate constants as immutable and do not depend on mutation through an alias. This bounded rule avoids a transitive const or permission type system.

## 8.6 Scalar constant expressions

A scalar constant expression contains only:

- an integer, character, or Boolean literal;
- an earlier named constant;
- parentheses; and
- a pure scalar operator or explicit scalar conversion that Chapter 9 admits in constant expressions.

It cannot read a variable, field, array element, or bounded string; call a routine; or perform an observable operation. Baton 1.0 constant expressions have no layout, address, offset, or runtime-length query. Fixed array lengths and string capacities use literals or earlier scalar constants instead.

The compiler evaluates a constant expression at compile time with the operand types, result type, overflow rule, and fault rule that Chapter 9 assigns to each admitted operator. It must not substitute host-language overflow, silently widen a typed operation, or fold an expression differently from the corresponding runtime operation. If Chapter 9 assigns no constant-expression rule to an operator, that operator is unavailable in this context.

An exact integer literal or earlier exact named integer constant remains exact until an operator rule or conversion supplies its type. The completed integer value of a named constant returns to the exact category for later uses. The implicit `u8`-to-`u16` conversion from Chapter 6 is permitted. A checked `u16`-to-`u8` conversion is valid at compile time only when its value lies from 0 through 255; otherwise the declaration is invalid. A constant operation that Chapter 9 defines to trap at runtime makes the constant expression invalid when the compiler proves that condition during evaluation.

An array length is a scalar constant expression whose value must lie from 1 through 65,535. A `string[N]` capacity is a scalar constant expression whose value must lie from 1 through 253. The compiler evaluates the bound before constructing the type identity. A later constant, a variable, or a cyclic dependency cannot supply a bound.

The bounded-string capacity is a property of that source type only. It does
not impose a 253- or 255-byte ceiling on a fixed array, record, array of
records, array of bounded strings, or record containing any of those types.
Their complete extents follow recursively from their declared members. An
implementation may still diagnose an otherwise valid declaration when the
complete object cannot fit its published program-data capacity.

## 8.7 Compile-time assertions

A compile-time assertion has this top-level form:

```nucleus
assert Rows * Columns <= 256
```

Its operand must be a Boolean scalar constant expression under Section 8.6. It may therefore use literals, earlier named constants, parentheses, pure scalar operators, and admitted conversions, but it cannot read storage or call a routine. An exact integer expression alone is not a condition: `assert Rows` is invalid, while `assert Rows <= 8` is Boolean-valued.

The compiler evaluates the expression while checking the declaration. A true result accepts the declaration. A false result makes the source invalid and produces an assertion diagnostic at the `assert` keyword. The declaration introduces no name or storage and emits no runtime operation or target code.

Assertions follow ordinary declaration order. They can state relationships among earlier constants, including relationships used to justify fixed capacities, but cannot refer to a later declaration.

## 8.8 Record declarations

A record declaration introduces one nominal type:

```nucleus
record Point
    x as u16
    y as u16
end
```

The declaration contains at least one field. Each field declares one name and one previously declared type. A field declaration has no `var` or `const` keyword, initializer, default value, placement clause, or mutability qualifier. Every object of the record type contains the same fields in declaration order.

The record type becomes visible only after the complete declaration has been checked. It is therefore unavailable in its own field list. This rule, the declaration-before-use rule, and Chapter 6's finite-size requirement reject direct and indirect recursive containment without a second declaration pass.

Record field names use the record's field scope under Chapter 5. An exact duplicate within that field scope is invalid; differently cased field names are distinct. Record layout offsets and backend encoding are outside this chapter.

## 8.9 Program variables

A top-level `var` declaration owns one mutable program-lifetime object. The declared type may be scalar, record, fixed array, or bounded string.

Every program variable has an initial value. With no initializer, the compiler establishes the type's zero value from Section 7.4 before the entry routine begins. The default is therefore integer zero, `false`, an empty bounded string with length zero, or the recursive zero value of a record or fixed array.

An explicit program initializer is permitted only in these forms:

| Declared type             | Permitted initializer                                                              |
| ------------------------- | ---------------------------------------------------------------------------------- |
| `u8`, `u16`, or `boolean` | One compatible scalar constant expression                                          |
| `string[N]`               | One fitting string literal                                                         |
| Record                    | One positional record initializer with exactly one initializer per field           |
| Fixed array               | One array initializer with exactly one compatible initializer per declared element |

Program initialization does not evaluate an ordinary runtime expression or read another variable. A string literal establishes both the decoded bytes and their logical length; embedded zero bytes count toward that length. A literal shorter than its capacity is valid, while one that exceeds the capacity is invalid and is never truncated.

A record initializer uses parentheses and supplies fields in declaration order. An array initializer uses square brackets and supplies elements in increasing index order. A nested record, fixed array, or bounded string uses its own initializer at the corresponding position, so the initializer delimiters mirror the finite aggregate type tree. Every scalar leaf is a compatible scalar constant expression. Every record and array level is complete: too few or too many components are invalid, and the compiler neither pads an explicit initializer nor discards components.

Baton has no named-field, partial, spread, or runtime aggregate initializer. A static initializer cannot name another aggregate object or call a routine. It is a declaration-only description of one static object image, not a general aggregate expression.

The program variable becomes visible only after the compiler has checked its type and initializer. Its initializer may therefore use earlier scalar constants but cannot use the variable itself or a later declaration.

## 8.10 Routine declarations and parameters

One routine header declares a routine name, an ordered list of zero or more formal parameters, and either no result type or one result type. Every parameter has an explicit `name as Type` declaration. Parameters have no initializer or default argument, and a header has no grouped names or multiple result list.

A scalar parameter denotes a per-invocation copied value. A concrete aggregate parameter establishes a fixed typed alias to caller-provided program-lifetime storage. A `string[]` parameter establishes a fixed view over one complete concrete bounded string and retains its actual capacity. Scalar-leaf mutation through either alias form is permitted and does not change the binding. Chapter 13 defines calls, result rules, and the value supplied for each parameter; this chapter defines only the bindings written in the header.

A forward routine declaration contains the complete and sole header and no body. The compiler retains its exact routine and parameter names, ordered parameter types, optional result type, and `fails` effect. The later abbreviated `sub NAME` header opens the body under Chapters 4 and 5; the forward's parameter names create that body's parameter bindings. The definition completes the existing routine binding and does not declare another routine or repeat its signature.

A routine definition without an earlier forward makes its checked signature visible before the local-declaration prefix and body. No nested routine declaration is permitted.

## 8.11 Local declarations

After parameter binding, scalar local declarations take effect in source order before the first statement. All local declarations remain in one contiguous prefix.

A scalar local owns one per-invocation scalar value. Its initializer is an ordinary expression or a direct failable call followed by `else fail` under Chapter 14, evaluated once when execution reaches the declaration. The successful result must be compatible with the declared scalar type. If the initializer is omitted, the compiler establishes zero for `u8` or `u16` and `false` for `boolean` at that point.

The declared local type must be `u8`, `u16`, or `boolean`. A record, fixed array, or bounded string is invalid in a local declaration whether or not an initializer is written. Routines receive aggregates only through formal parameters, reach aggregate subobjects through field and index paths, and may return transient aggregate aliases under Chapters 7 and 13.

A local becomes visible only after its complete declaration and initializer have been checked. Its initializer may name parameters, visible program declarations, and earlier locals. It cannot name itself or a later local. A local declaration inside a statement block or after the first statement is invalid.

## 8.12 Initialization order

Scalar constant expressions are evaluated during compilation and perform no source-level runtime operation. The compiler also constructs every aggregate constant's complete static value before source execution begins.

The compiler establishes every program variable's zero or explicit initial value exactly once before the entry routine begins. Aggregate constants and variables follow source declaration order. Static initializers have no source-level effects and cannot read storage, so this order is not otherwise observable. Every program-lifetime object has reached its initial value before source execution can read it. Chapter 7 defines lifetime, and Chapter 19 defines startup semantics and implementation requirements.

On each routine invocation, parameter binding precedes activation-local initialization. Scalar local declarations then take effect in source order, and each receives its zero or evaluated value at its declaration. After the last local declaration, execution continues with the first statement.

## 8.13 Invalid declarations and capacity failures

The compiler must diagnose:

- a declaration in a location not permitted by Section 8.2;
- a missing type;
- a type, bound, initializer, or name that is not visible at its declaration point;
- an exact duplicate name or forbidden shadowing under Chapter 5;
- a nonconstant operand or invalid folded operation in a constant expression;
- a scalar initializer incompatible with its declared type;
- an invalid array length, string capacity, string length, record field count, array element count, or nested initializer shape;
- a record field with an unavailable type or a record with no fields;
- a scalar type written on an aggregate-constant form, a nonconstant aggregate initializer, or an initializer form incompatible with its declared component type;
- assignment rooted directly at an aggregate constant name;
- a record, fixed array, or bounded string used as a local variable type;
- a concrete aggregate argument or result with a nonidentical referent type, except for a bounded string bound to `string[]`;
- an assignment between different aggregate types, including bounded strings with different capacities; and
- an abbreviated body without one matching incomplete forward, a second completion, or an uncompleted forward.

An implementation may bound top-level declarations, record fields, parameters, scalar locals, constant-expression nesting, structured-initializer depth and elements, decoded string bytes, type descriptors, retained signatures, and initialization records. It must publish each limit and issue a capacity diagnostic before truncation, wraparound, omitted initialization, dropped fields, or an incorrect binding can occur. A capacity failure does not change an otherwise conforming declaration into invalid source.

## 8.14 Examples

These top-level declarations are valid under this chapter:

```nucleus
const cellCount = 8
record Cell
    value as u16
    active as boolean
end

const defaultCell as Cell = (0, false)
const bitMasks as u8[4] = [1, 2, 4, 8]
const banner as string[8] = "READY"
var cells as Cell[cellCount]
var origin as Cell = (0, false)
var templates as Cell[2] = [(1, true), (2, false)]
var flags as u8[4] = [1, 2, 4, 8]
var prompt as string[8] = "READY"
var title as string[12] = "NUCLEUS"
var attempts as u8
```

`defaultCell`, `bitMasks`, and `banner` are aggregate constants whose direct named roots cannot be assignment targets. `cells` and `attempts` begin with their zero values, including every field of every `Cell`. `origin`, `templates`, `flags`, `prompt`, and `title` are mutable program-lifetime objects with the written initial contents. `title` begins with seven decoded bytes.

A routine manipulates selected aggregate storage directly through a parameter path:

```nucleus
sub update(items as Cell[cellCount], index as u8)
    var count as u16 = 0

    items[index].value = count
    return
end
```

The checked assignment updates the selected element of the caller's array. The routine creates no `Cell` object or local aggregate binding.

A program object or array element may supply an aggregate parameter:

```nucleus
record State
    code as u8
end

var primary as State
var states as State[4]

sub inspect(item as State)
    return
end

sub main()
    inspect(primary)
    inspect(states[2])
end
```

Each call binds `item` to existing program storage. Neither call copies a `State`.

A forward declaration supplies the sole signature, and its abbreviated definition supplies the body:

```nucleus
forward sub inspectState(item as State)

sub inspectState
    return
end
```

The following declarations illustrate valid and invalid boundary cases. They are not one compilation unit:

```nucleus
const Limit = 8
var limit as u16                    // valid: names are case-sensitive
var Limit as u16                    // invalid: exact duplicate

const flags as u8[4] = [1, 2, 4, 8]    // valid aggregate constant
const prompt as string[8] = "READY"    // valid aggregate constant
const missingType = [1, 2]              // invalid: aggregate type is required
const typedScalar as u8 = 1              // invalid: scalar constants infer type

const first = second         // later name is unavailable
const second = first         // the first error prevents a cycle

const noElements = 0
var empty as u8[noElements]         // fixed arrays must be nonempty
var lateBound as u8[laterLength]    // later constant is unavailable
const laterLength = 4

var shortText as string[4] = "READY" // decoded literal is too long
var copiedCell as Cell = cells[0]   // static initializers cannot read aggregate storage
defaultCell.value = 1               // invalid: direct constant-rooted write

sub invalidLocal()
    var aggregateLocal as Cell      // invalid: locals must be scalar
    return
end
```

Inside a routine, both `var current as Cell = cells[0]` and `var aggregateLocal as Cell` are invalid because every local must have scalar type. At top level, `var copiedCell as Cell = cells[0]` would read aggregate storage during static initialization and is independently invalid. Aggregate parameters and program variables remain valid aggregate-assignment destinations under the compatibility rules in Section 6.10.
