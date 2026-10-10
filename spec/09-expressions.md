# 9. Expressions


## 9.1 Scope

This chapter defines expression syntax, precedence, associativity, operand and result types, the numeric rules (design decision D31), conversions, designators, handle expressions, and evaluation order. Chapter 6 defines the types and the implicit widenings. Chapter 7 defines storage, aliases, pools and handles. Chapter 10 defines assignment and the statement contexts that contain expressions. Chapter 13 defines calls.

Basie uses one predictive expression grammar for every context: initializers, arguments, indexes, conditions, `select` subjects and returns. A context may restrict the result or supply an expected type, but it never selects another precedence ladder. The grammar needs no backtracking and no retained syntax tree.

## 9.2 Expression grammar

```text
expression          ::= or-expression
or-expression       ::= and-expression { ( "or" | "xor" ) and-expression }
and-expression      ::= not-expression { "and" not-expression }
not-expression      ::= "not" not-expression | comparison
comparison          ::= additive [ comparison-operator additive ]
comparison-operator ::= "=" | "<>" | "<" | "<=" | ">" | ">="
additive            ::= multiplicative { ( "+" | "-" ) multiplicative }
multiplicative      ::= unary
                        { ( "*" | "/" | "mod" | "shl" | "shr" ) unary }
unary               ::= ( "+" | "-" ) unary | postfix-expression
postfix-expression  ::= primary { postfix-suffix }
primary             ::= NUMBER | FLOAT | CHARACTER | "true" | "false"
                      | "none"
                      | NAME
                      | conversion
                      | "(" expression ")"
                      | "move" designator
                      | "id" "(" expression ")"
                      | "new" [ "?" ] NAME argument-list
conversion          ::= numeric-type "(" expression ")"
numeric-type        ::= "u8" | "i8" | "u16" | "i16" | "u32" | "i32" | "f32"
designator          ::= NAME { "[" expression "]" | "." NAME }
postfix-suffix      ::= argument-list | "[" expression "]" | "." NAME
argument-list       ::= "(" [ argument { "," argument } ] ")"
argument            ::= expression | STRING
```

`id` is the contextual word of Chapter 3: it begins the `id(...)` form whenever the next token is `(`, and no routine may be named `id`, so the reading never depends on what is declared; otherwise it is an ordinary `NAME`. Chapter 17 incorporates this fragment into the complete grammar. The semantic rules below reject suffix combinations that the compact syntax admits but Basie does not.

A string literal is not a general expression primary. It is admitted in exactly these positions, each with a bounded-string destination:

- a static initializer, and the initializer of a local of string type (Chapter 8);
- the right side of an assignment to a bounded string, which sets its bytes and length (Chapter 10, Section 10.4);
- an argument for a read-only `string[]` parameter (Chapter 13); and
- a `new` argument for a field of string type (Section 9.13).

In each, a literal longer than the destination's capacity is invalid. Anywhere else, including an argument for a `var` parameter or a scalar, it is invalid.

## 9.3 Precedence and associativity

From highest to lowest:

1. routine invocation, indexing, field selection, and parenthesized grouping;
2. unary `+` and `-`;
3. `*`, `/`, `mod`, `shl` and `shr`;
4. binary `+` and `-`;
5. one comparison;
6. `not`;
7. `and`;
8. `or` and `xor`.

`move`, `id(...)`, `new` and conversions are primaries and bind tightest. Binary operators at one level associate from left to right. Unary `+`, unary `-` and `not` associate from right to left. A comparison contains at most one comparison operator and has no associativity: `a < b < c` is invalid, and is written `a < b and b < c`.

`not` binds less tightly than comparison, so `not left = right` means `not (left = right)`. An integer complement used as a comparison operand needs parentheses: `(not mask) = expected`. Shifts bind as tightly as multiplication, so `a + b shl 2` means `a + (b shl 2)`.

## 9.4 Names, calls and suffixes

The compiler resolves each `NAME` before interpreting its suffixes. A constant, variable, parameter or local supplies its type. A routine name must be followed immediately by an argument list; routines are not values. A pool name is not an expression; it appears only after `new`.

**Calls.** An argument-list suffix invokes the routine named by the primary. Basie has no routine values, indirect calls, overloading or invocation of a parenthesized expression, and a second argument list is invalid. A call to a failing routine is admitted only in the positions Chapter 14 gives it. Chapter 13 defines argument passing and results.

**Indexing.** An index suffix applies to a fixed array, an open array parameter or a bounded string. The index must have type `u8` or `u16`, or be an exact integer that fits `u16`; a signed or 32-bit index must be converted explicitly, and the checked conversion traps if the value is negative or too large, so a negative index never wraps into a valid one. For an array, each index is checked against its own dimension's bound (design decision D32) and the result has the element type. For a bounded string, the result is a `u8` byte, checked against the current length. A failed check traps with `bounds` before any element is read or written. A constant-expression index out of range is diagnosed (Chapter 15, Section 15.3); any other index is checked at run time. An array of arrays is indexed one dimension at a time: `screen[r][c]`.

**Enum members.** `EnumName.NAME` denotes that enum's named constant (Section 6.16). An enum value itself has no fields.

**Field selection.** `.NAME` on a record designator resolves `NAME` in that record's field scope. On a bounded string, `.length` gives the current length as `u8`, and on a `string[]` parameter `.capacity` gives its capacity as `u8` (Chapter 6). On a non-optional handle, `.NAME` selects a field of the slot's record, through the access rules of Chapter 7, Section 7.13. An optional handle cannot be selected through; it must first be tested with `select`.

**Results.** Index and field suffixes may follow a call whose result is an aggregate alias; the suffix does not copy the object. A scalar result cannot take a suffix, nor can a handle result: `make().v` is invalid, and the handle is stored in a local first, which also gives a fresh owning result its owner (Chapter 7, Section 7.13), and a result-free call is not an expression.

## 9.5 Categories and designators

Expression checking records a type and one of these categories:

| Category | Use |
| --- | --- |
| Exact integer | Adopts an integer or `f32` type from its context (Section 9.7) |
| Value | A scalar or handle value; copied, converted, compared, passed or stored |
| Designator | A path to storage, which reads as its value in an expression, and may be written when its root is writable |
| Aggregate designator | A path to a record, array or string; selected, indexed, copied by exact-type assignment, or passed as an alias |
| Aggregate result | An alias returned by a call, consumed within the statement (Chapter 7) |
| Fresh owning value | The result of `new`, `new?`, a `move`, or a call returning an owning handle; may be stored in an owning location |

A **designator** begins with a variable, constant, parameter or local, and continues through field and index suffixes, and through field selections on non-optional handles. A bare aggregate designator is valid only where aggregate storage, an alias or an assignment operand is required. Basie has no aggregate comparison and no automatic copy of an aggregate argument or result.

## 9.6 Conversions

A conversion is written with the target type's name: `u8(x)`, `i8(x)`, `u16(x)`, `i16(x)`, `u32(x)`, `i32(x)` or `f32(x)`. The operand must have a numeric type or be an exact integer. The conversion evaluates its operand once and then:

- if the conversion is an implicit widening (Chapter 6, Section 6.4), or the identity, produces the same value in the target type;
- between integer types otherwise, produces the same value if the target type can represent it, and otherwise traps with `narrowing`;
- from an integer type to `f32`, rounds `u32` and `i32` values to nearest, ties to even, and is exact for the others; an exact operand is rounded the same way, so `f32(16777217)` is 16777216;
- from `f32` to an integer type, truncates toward zero, and traps with `narrowing` if the truncated value does not fit.

A conversion whose operand is known during compilation and does not fit is diagnosed instead of generating a guaranteed trap. Conversions never extract low bytes, reduce modulo a width, or reinterpret bits. There is no conversion to or from `boolean`, between handles and integers, or between aggregate types.

The type words are reserved words, not routine names, and cannot be redeclared.

## 9.7 Operand types and exact integers

**Mixed operands.** For a binary arithmetic, bitwise or comparison operator on two typed numeric operands, if the two types are equal the operation is done in that type. Otherwise, if one operand's type widens implicitly to the other's (Chapter 6, Section 6.4), that operand is widened and the operation is done in the wider type. Otherwise the expression is invalid, and one operand must be converted explicitly (design decision D31). So `u8 + i16` is an `i16` addition, `u16 + f32` an `f32` addition, and `u16 + i16`, `i32 + u32` and `u32 + f32` are invalid.

**Exact integers.** An integer literal, a character literal, an untyped integer constant, and an expression built only from them are **exact**: they have a mathematical integer value and no type yet. An exact operand takes its type from:

1. the other operand of the same binary operator, when that operand is typed: the exact value adopts that type, and must be representable in it (for `f32`, exactly representable);
2. otherwise, the expected type of the context: a declared or destination type, a parameter type, a result type, a conversion's operand position (where it stays exact), an index position (`u16`), or a `select` subject's type for its labels.

An expression made only of exact operands is evaluated exactly, as a constant expression (Chapter 8, Section 8.6), and its value then adopts its context's type. A value that does not fit the type it adopts is invalid; it is never truncated. An exact expression with no expected type where a type is required, as in `var x = 1 + 2`, is invalid (design decision D21). An exact comparison such as `3 < 5` needs no type and is a `boolean` constant.

A character literal is exact, with its byte's value; only where an exact value would have no type at all, as the initializer of an inferred local, does it take `u8`. An untyped constant initialized with a character literal is exact in the same way, so substituting one for the other never changes validity. A floating-point literal has type `f32` and never adopts an integer type. `true` and `false` have type `boolean`.

## 9.8 Integer arithmetic

`+`, `-`, `*`, `/` and `mod` take integer operands of one type after Section 9.7, and produce that type.

- **Wrapping.** `+`, `-`, `*` and unary `-` wrap modulo 2 to the power of the type's width (design decision D5). Signed types wrap in two's complement: in `i16`, `32767 + 1` is `-32768`, and `-(-32768)` is `-32768`. Unary `-` on an unsigned type is subtraction from zero: in `u8`, `-1` applied to a typed `1` gives `255`. Unary `+` returns its operand.
- **Division** truncates toward zero, and `mod` gives the remainder with the sign of the dividend: `-7 / 2` is `-3` and `-7 mod 2` is `-1`; `7 / -2` is `-3` and `7 mod -2` is `1`. For any `a` and nonzero `b`, `(a / b) * b + a mod b` equals `a`. The one quotient that does not fit, the most negative value divided by `-1`, wraps to itself: `-32768 / -1` is `-32768` in `i16`, and the matching `mod` is `0`.
- **Division by zero.** A zero divisor for `/` or `mod` traps with `division-by-zero` (Chapter 15). A divisor that is a constant zero is diagnosed.

The result type is fixed before evaluation; arithmetic does not widen because a result would overflow. A program that needs a wider result widens an operand first.

## 9.9 Floating-point arithmetic

`+`, `-`, `*` and `/` take `f32` operands, after Section 9.7, and produce `f32`; `mod` is not defined for `f32`. Each operation computes the exact result and rounds it to the nearest `f32`, ties to even (design decision D7). A rounded result whose magnitude is below the smallest normal `f32` becomes zero. A rounded result whose magnitude exceeds the largest finite `f32` traps with `float-overflow`. Division by zero traps with `division-by-zero`. Operands that are denormal are not possible, since every `f32` value is zero or normal.

Unary `-` changes the sign; `-0.0` is a value, equal to `0.0` in every comparison. There is no infinity or NaN, so every comparison of `f32` values is ordinary.

## 9.10 Shifts

`a shl n` and `a shr n` shift an integer `a` by `n` bit positions. The result has `a`'s type. When `a` and `n` are both exact, the shift is folded exactly like any exact expression (Section 9.7): `a shl n` is `a` times 2 to the power `n`, and `a shr n` is `a` divided by it, rounded down; so `1 shl 3` is 8 and `(1 shl 20) + 3` must fit wherever it is used. When `a` is exact and `n` is not, `a` takes the context's expected integer type, and without one the shift is invalid. The count `n` must have an unsigned integer type or be an exact non-negative integer; a signed count must be converted explicitly.

- `shl` shifts left, filling with zeros; bits shifted out are lost, and for a signed type the result wraps in two's complement.
- `shr` shifts right. For an unsigned type it fills with zeros. For a signed type it copies the sign bit, so `-8 shr 1` is `-4`.
- A count equal to or greater than the type's width gives 0, except that `shr` of a negative signed value gives `-1`.
- A count of 0 returns `a` unchanged.

Shifts are not defined for `f32` or `boolean`.

## 9.11 Comparison

The six comparison operators produce `boolean`.

- **Numeric operands** follow Section 9.7: they must have one type after widening, or the comparison is invalid. Integer comparison uses the type's ordering, signed or unsigned. `f32` comparison is ordinary, with `-0.0 = 0.0`.
- **Enum operands** admit only `=` and `<>`, and both operands must have the same nominal enum type (Section 6.16).
- **`boolean` operands** admit only `=` and `<>`.
- **Identifiers** of the same pool admit only `=` and `<>`; `id P` widens to `id P?` for the comparison, so either may be compared with the other. Two identifiers are equal when both are `none`, or when both were made from the same slot with the same generation. `none` may be compared with an optional identifier. Comparing identifiers performs no check and never traps; a stale identifier is not equal to `none` by comparison, though `select` treats it as `none`.
- **`File` values** admit only `=` and `<>`, comparing the entry and generation, so a value equals `console`, `printer` or a copy of itself (Chapter 16, Section 16.3).
- **Owning handles**, records, arrays and strings have no comparison operators.

## 9.12 `not`, `and`, `or` and `xor`

These operators work logically on `boolean` operands and bit by bit on integer operands, as in Pascal (design decision D31). Mixing a `boolean` and an integer operand is invalid. Integer operands follow Section 9.7 and the result has their common type; `f32` operands are invalid.

- `not` on a `boolean` exchanges `true` and `false`; on an integer it complements every bit of the operand's type. An exact operand takes the context's expected integer type, so `var b: u8 = not 0` gives 255; without one, `not` of an exact integer is invalid.
- `and`, `or` and `xor` on two exact integers are folded exactly; both must be non-negative, since an exact value has no width to complement.
- `and` and `or` on integers combine corresponding bits and evaluate both operands.
- `xor` combines by exclusive OR, on integers bit by bit and on `boolean` values logically. It always evaluates both operands.

`and` and `or` on `boolean` operands **short-circuit**. The left operand is evaluated first; if it is `false` for `and`, or `true` for `or`, the right operand is not evaluated and the result is the left value; otherwise the result is the right operand's value. An operand not evaluated performs no call, access, check or trap, and creates no temporary. A `move` is invalid inside an operand of `and` or `or` (Chapter 10, Section 10.8).

## 9.13 Handle expressions

**`none`** is the empty value of an optional handle. It has no type of its own and takes the optional handle type its context expects: a declared or destination type, a parameter type, a `new` argument for an optional handle field, a result, or the other operand of an identifier comparison. With no such context it is invalid.

**`move designator`** hands on the owning handle held in the designator (design decision D19), which must be an owning location: a local, a writable parameter (not a ticket), a program variable, or a field or element reached from one of them, from a lease, from a `var` owning-aggregate parameter, or through a handle, of type `P` or `P?`. The expression yields the handle, with the designator's type, and stores `none` in the designator. Its result is a fresh owning value. Moving a non-optional local or parameter changes its flow state to "certainly moved" (Chapter 7, Section 7.17). The designator is resolved when the `move` is evaluated, and the statement rule of Chapter 10, Section 10.8 applies.

**`id(expression)`** makes an identifier (Chapter 7, Section 7.9). Its operand is either an owning-handle designator, of type `P` or `P?`, giving `id P` or `id P?` without changing the operand; or a `var` record parameter whose record type belongs to exactly one pool, giving `id P?` as Chapter 7, Section 7.14 describes. A fresh value is not a valid operand.

**`new P(arguments)`** and **`new? P(arguments)`** allocate a slot of pool `P`, which must be complete (Chapter 7, Section 7.10). The arguments initialize the record's fields in order and follow the rules for assigning to those fields: an owning handle field takes `none`, a fresh value or a `move`; an aggregate field takes an aggregate of its exact type, copied. Trailing arguments may be omitted; their fields are zeroed. `new` has type `P` and traps with `pool-full` when the pool is full. `new?` has type `P?`; when the pool is full it evaluates no argument and yields `none`. In both forms the slot is reserved before any argument is evaluated.

## 9.14 Evaluation order

Basie fixes evaluation order:

- a unary operand is evaluated before its operator;
- binary operands are evaluated left to right, subject to short-circuiting;
- a postfix base is evaluated before its suffixes, which apply left to right, and each index is evaluated and checked when its suffix is reached;
- a handle used in a field access is resolved, and an identifier checked, after the access's other operands, immediately before the access; an identifier on an assignment's target path is checked again after the right side (Chapter 7, Section 7.13);
- routine arguments, and `new` arguments, are evaluated left to right;
- a conversion evaluates its operand before checking it.

When an operation traps, later operands and suffixes are not evaluated. A backend may reorder operations only when nothing observable, including calls, stores, checks and traps, can distinguish the order.

## 9.15 Constant expressions

The operators and conversions of Sections 9.6 to 9.12 are available in the constant expressions of Chapter 8, Section 8.6, with exactly the run-time rules for types, wrapping, rounding, comparison and short-circuiting. A constant operation that would trap at run time, such as division by zero, a narrowing conversion that does not fit, or an `f32` overflow, is invalid. A short-circuited operand is not evaluated and cannot cause such an error. Calls, designators other than named scalar constants, `move`, `id`, `new` and `none` are not constant expressions.

## 9.16 Diagnostics and capacity

The compiler must diagnose:

- a name of the wrong declaration class for its position;
- a routine name without its argument list, or an argument list on something other than a routine;
- an invalid field, index, suffix sequence or aggregate use, including selection through an optional handle;
- mixed operand types that do not widen, and operator and operand-type mismatches;
- an exact value that does not fit its adopted type, or an exact expression with no type where one is required;
- a chained comparison;
- an unavailable conversion;
- a result-free call used as a value;
- `none` without an optional handle context;
- a `move` of something that is not an owning location, or inside an operand of `and` or `or`;
- an invalid `id(...)` operand;
- a `new` of an incomplete pool, or `new` arguments that do not match the record's fields; and
- a bounds, narrowing, division or overflow failure provable during compilation.

An implementation may bound expression nesting, argument counts and expression-checking state. It must publish each limit and diagnose an excess; exhausting a capacity must never change precedence, omit a check, truncate an argument list or alter a type.

## 9.17 Examples

For `i16` values `a`, `b` and `c`:

```basie
a - b - c           // (a - b) - c
a + b shl 2         // a + (b shl 2)
- -a                // -(-a), wrapping in i16
not not flag        // not (not flag)
-7 / 2              // -3, an exact constant
-7 mod 2            // -1
```

Mixed operands:

```basie
var small: u8 = 200
var wide: i16 = -5
var x = small + wide        // i16 addition: u8 widens to i16; x is i16
var y = wide + 1            // i16; the literal adopts i16
var z = f32(wide) * 0.5     // f32
var w: u16 = 40000
var bad = w + wide          // invalid: u16 and i16 don't widen to each other
var ok = i32(w) + wide      // i32
```

Handles:

```basie
var n = new nodes(1, none)        // nodes
var spare = new? nodes(2, none)   // nodes?
var i = id(n)                     // id nodes
head = move n                     // n now holds none
```

Invalid forms:

```basie
first < second < third      // comparisons don't chain
flag + 1                    // boolean is not an integer
if recordValue = other      // records have no equality
x mod 1.5                   // mod is not defined for f32
cells[signedIndex]          // a signed index must be converted
var n2 = 0                  // no definite type
show(maybe.value)           // maybe is optional: test it with select
```
