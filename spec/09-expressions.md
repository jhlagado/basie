# 9. Expressions


## 9.1 Scope

This chapter defines expression syntax, precedence, associativity, operand and result types, scalar conversions, designator formation, and evaluation order. Chapter 6 defines the type set and compatibility rules. Chapter 7 defines storage identity and aggregate aliases. Chapter 10 defines assignment and the statement contexts that contain expressions. Chapter 13 defines routine signatures, argument passing, and result transfer.

Baton uses one predictive expression grammar for ordinary, initializer, argument, index, condition, and return contexts. A context may restrict the resulting category or supply an expected type, but it does not select another precedence ladder. The grammar requires no backtracking or retained syntax tree.

## 9.2 Expression grammar

The reusable expression fragment is:

```text
expression             ::= or-expression
or-expression          ::= and-expression { ( "or" | "xor" ) and-expression }
and-expression         ::= not-expression { "and" not-expression }
not-expression         ::= "not" not-expression | comparison
comparison             ::= additive [ comparison-operator additive ]
comparison-operator    ::= "=" | "<>" | "<" | "<=" | ">" | ">="
additive               ::= multiplicative
                           { ( "+" | "-" ) multiplicative }
multiplicative         ::= unary { ( "*" | "/" | "mod" ) unary }
unary                  ::= ( "+" | "-" ) unary | postfix-expression
postfix-expression     ::= primary { postfix-suffix }
primary                ::= NUMBER | CHARACTER | "true" | "false"
                         | NAME | conversion | "(" expression ")"
conversion             ::= ( "u8" | "u16" ) "(" expression ")"
postfix-suffix         ::= argument-list | "[" expression "]" | "." NAME
argument-list          ::= "(" [ expression { "," expression } ] ")"
```

Chapter 17 incorporates this fragment into the complete grammar. The semantic restrictions below reject suffix combinations that the compact syntactic loop can recognize but Baton does not admit.

A string literal is not a general expression primary. Chapter 8 permits it as a bounded-string initializer. A later system or bounded-string operation may accept a string literal in an explicitly defined operand position without turning it into a copyable aggregate value.

## 9.3 Names, calls, and postfix operations

The compiler resolves each `NAME` before interpreting its postfix suffixes. A visible scalar constant, scalar variable, parameter, or local supplies its declared scalar type. A visible aggregate object or alias supplies its exact aggregate type and storage category. A visible routine name must be followed immediately by an argument list; routine names are not values.

An argument-list suffix in an ordinary expression invokes only an infallible source routine named by the primary. Baton has no routine values, indirect calls, callable results, overload resolution, or invocation of an arbitrary parenthesized expression. A second argument-list suffix is invalid. Chapter 13 defines argument and result compatibility, and Chapter 14 gives failable calls their restricted statement, initializer, and assignment positions.

An index suffix requires a fixed-array or bounded-string storage path or typed alias. Its expression must have type `u8` or `u16`. For a fixed array, the result has the array's exact element type; the compiler diagnoses a statically out-of-range index and emits a checked access for a dynamic index unless it proves the index is in range. For a bounded string, the result is a `u8` storage path and the implementation checks the index against the current logical length before every access unless it proves that access safe. A failed check occurs before the element or byte is read or written.

A field suffix on a record storage path or typed record alias resolves the field name only in that record's field scope and produces the field's declared type. A `.length` suffix on a bounded-string storage path or alias produces its read-only `u8` logical length. Other field suffixes on bounded strings are invalid. Selection does not expose an offset, header, or address to source code.

Index and field suffixes may follow an aggregate result from a routine call. The result remains a transient typed alias to the object established by Chapter 13; the suffix does not copy that object. A scalar result cannot be indexed or selected, and a result-free call cannot take another suffix.

## 9.4 Expression categories and storage paths

Expression checking records both a type and one of these source categories:

| Category                         | Permitted use                                                                                                                                          |
| -------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------ |
| Exact integer constant           | Adopts an admitted integer type from context or the rules in Section 9.7.                                                                              |
| Scalar value                     | May be copied, converted, compared, passed, returned, or stored in a compatible scalar destination.                                                    |
| Scalar storage path              | Reads as its scalar value in an expression and may be a writable destination when its root is mutable.                                                 |
| Aggregate storage path           | May be indexed, selected, copied by exact-type assignment, passed as an aggregate argument, or returned under Chapter 7's consumption rules.           |
| Transient aggregate-alias result | Denotes compatible storage for one containing operation and may be selected, indexed, copied by exact-type assignment, passed, returned, or discarded. |
| Result-free invocation           | Is valid only as a complete call statement; when failable, its failure is consumed under Chapter 14.                                                   |

A **storage path** begins with a visible program variable, aggregate constant, parameter, or local and continues through zero or more field and index suffixes. Each suffix preserves the root object's identity while selecting a subobject. An aggregate-constant-rooted path is readable but not a direct assignment target. A scalar constant and a routine call are not storage-path roots. A call that returns an aggregate alias may be selected or indexed in a value context, but Chapter 10 does not admit it as an assignment root.

A bare aggregate storage path is valid where a rule requires compatible aggregate storage, an alias, or an aggregate-assignment operand. It is not otherwise a general expression value. Baton has no aggregate comparison, aggregate truth test, automatic argument copy, or automatic result copy.

## 9.5 Explicit integer conversions

`u16(expression)` performs the explicit form of the `u8`-to-`u16` conversion. Its operand must have type `u8` or `u16`. A `u8` operand is widened without changing its value; a `u16` operand is unchanged.

`u8(expression)` performs checked narrowing. Its operand must have type `u8` or `u16`. A `u8` operand is unchanged. A known `u16` value outside 0 through 255 makes the source invalid. For a value known only at runtime, the generated program checks the range and performs the Chapter 15 narrowing trap before producing a result when the value is outside that range.

Both forms evaluate their operand once. They do not reinterpret bits, extract a low byte, wrap, or expose a machine representation. `boolean(expression)`, record conversions, array conversions, string-capacity conversions, and conversions between `u16` and an aggregate-alias carrier are absent.

The type words in these two forms are fixed tokens, not routine names. A user declaration cannot override them, and conversion syntax does not participate in routine lookup.

## 9.6 Precedence and associativity

Precedence from highest to lowest is:

1. routine invocation, indexing, field selection, and parenthesized grouping;
2. unary `+` and unary `-`;
3. multiplication, division, and modulo;
4. addition and subtraction;
5. one comparison;
6. `not`;
7. `and`;
8. `or` and `xor`.

Binary arithmetic, `and`, `or`, and `xor` associate from left to right. Unary `+`, unary `-`, and `not` associate from right to left. A comparison contains at most one comparison operator and therefore has no associativity.

`not` binds less tightly than comparison. Thus `not left = right` means `not (left = right)`. An integer complement used as a comparison operand requires parentheses, as in `(not mask) = expected`.

The repeated forms in Section 9.2 preserve left association without a left-recursive predictive grammar. The first handwritten compiler implements the binary levels with one precedence-driven loop and a compact operator table; comparison's single-use rule and Boolean short-circuit emission remain explicit cases in that loop. Separate parsing remains appropriate for primary, postfix, unary, and right-recursive `not`. Another conforming compiler may use a different parser family only if it accepts the same token sequences and produces the same association and evaluation order.

## 9.7 Exact-integer resolution

An exact integer literal or exact named integer constant adopts an expected `u8` or `u16` type when its value fits. The expected type may come from a declaration initializer, scalar destination, parameter, result, conversion operand, or a typed operand in the same arithmetic operation. An expected type never narrows an already typed operand implicitly.

For an integer operation:

- when one operand has integer type and the other is an exact integer constant, the constant adopts that type when it fits;
- when the operands have types `u8` and `u16`, the `u8` operand widens and the operation uses `u16`;
- when both operands are exact integer constants, an expected integer result type applies when both operands fit; otherwise the operation uses `u16`; and
- when a standalone exact integer literal has no expected type, it uses `u16`.

An exact value that does not fit the selected type makes the source invalid. The compiler does not truncate the literal or select a wider intermediate type after the context has fixed a narrower operation.

A character literal has type `u8`. It follows the ordinary implicit widening rule when combined with or supplied to `u16`. `true` and `false` have type `boolean` and never adopt an integer type.

## 9.8 Integer arithmetic

`+`, `-`, `*`, `/`, and `mod` accept integer operands. After literal resolution and implicit widening, both operands have the same type and the result has that type.

Addition, subtraction, multiplication, and unary minus use arithmetic modulo 256 for `u8` and modulo 65,536 for `u16`. Unary minus is subtraction from zero in the selected width. Unary plus preserves the operand and its type. These rules define wraparound; overflow is neither undefined nor a narrowing conversion.

Division produces the unsigned integer quotient with any remainder discarded. Modulo produces the unsigned remainder from the same division. A zero divisor for either operation performs the `division-by-zero` trap specified by Chapter 15 at the divisor. When the divisor is a compile-time constant zero, the source is invalid and the compiler issues the same diagnostic at that divisor instead of emitting a guaranteed trap.

The result width is determined before evaluation. Arithmetic does not widen merely because a mathematical result would exceed that width. A program that requires a wider result widens an operand explicitly or supplies a `u16` operand before the operation.

## 9.9 Comparison

The six comparison operators accept compatible integer operands and produce `boolean`. Literal resolution and `u8`-to-`u16` widening follow Section 9.7. Integer comparison uses unsigned ordering.

Boolean operands support only `=` and `<>`. Both operands must have type `boolean`. Boolean ordering is invalid.

Records, fixed arrays, and bounded strings, including aliases to them, have no comparison operation in Baton 1.0. Equal layout or identity of the referred object does not add an equality operator.

Comparison chaining is invalid. `minimum <= value <= maximum` is not two comparisons; after the first comparison, the left side would be Boolean and the grammar permits no second comparison operator. The equivalent valid form is `minimum <= value and value <= maximum`.

## 9.10 `not`, `and`, `or`, and `xor`

`not` accepts one `boolean`, `u8`, or `u16` operand. For `boolean`, it exchanges `true` and `false`. For an integer, it complements every bit in the operand's declared width and produces the same integer type.

`and` and `or` accept either two Boolean operands or two compatible integer operands. Mixed Boolean and integer operands are invalid. Integer operands use literal resolution and widening from Section 9.7, combine corresponding bits, evaluate both operands, and produce the resolved integer type.

`xor` accepts only two compatible integer operands. It uses the same literal resolution and widening rules, evaluates both operands from left to right, combines corresponding bits by exclusive OR, and produces the resolved integer type. A Boolean operand is invalid. This deliberate restriction avoids placing an eager Boolean operator at the same precedence as short-circuiting Boolean `or`.

Boolean `and` and `or` short-circuit. The left operand is evaluated first:

| Operator | Left value | Right operand | Result                            |
| -------- | ---------- | ------------- | --------------------------------- |
| `and`    | `false`    | not evaluated | `false`                           |
| `and`    | `true`     | evaluated     | the right operand's Boolean value |
| `or`     | `true`     | not evaluated | `true`                            |
| `or`     | `false`    | evaluated     | the right operand's Boolean value |

An operand that is not evaluated performs no call, storage access, bounds check, conversion check, arithmetic trap, or other source operation. The Boolean and integer meanings are selected by static types and create no parsing ambiguity.

Shifts, rotations, power, and symbolic Boolean operators are absent. A later proposal for one of these operators requires its own measured admission and a Chapter 3 token amendment when it uses a word.

## 9.11 Evaluation order

Baton fixes evaluation order:

- a unary operand is evaluated before its operator;
- binary operands are evaluated from left to right, subject to Boolean short-circuiting;
- a postfix base is evaluated before its suffixes, and suffixes are applied from left to right;
- each index expression is evaluated and checked when its suffix is reached;
- routine arguments are evaluated from left to right under Chapter 13; and
- an explicit conversion evaluates its operand before checking or producing the result.

If an earlier operation traps, later operands and suffixes are not evaluated. Field selection performs no source-level read by itself, but evaluation of its base and any preceding index or call remains observable.

A backend may reorder operations only when it proves that no result, call, mutation, storage access, check, trap, or other observable behaviour can distinguish the order. The permitted implementation arrangement does not change source semantics.

## 9.12 Constant expressions

The scalar operators and conversions in this chapter are available to the scalar constant expressions defined by Chapter 8. The compiler applies the same literal resolution, width, wraparound, comparison, and short-circuit rules used at runtime.

A constant division by zero is invalid. A checked `u8` conversion of a known value outside 0 through 255 is invalid. A short-circuited constant operand is not evaluated and therefore cannot contribute a fault.

Routine calls and storage paths remain unavailable in constant expressions. The presence of a pure-looking routine or a program variable with a constant initializer does not extend the constant-expression grammar.

## 9.13 Invalid expressions and capacity limits

The compiler must diagnose:

- a name of the wrong declaration class for its expression position;
- a routine name without its argument list or an argument-list suffix on a non-routine;
- an invalid field, index, suffix sequence, or aggregate use;
- an operand-type mismatch or a literal that does not fit its resolved type;
- a chained comparison;
- an implicit narrowing or unavailable conversion;
- a result-free call used as a value;
- an aggregate used where a scalar value is required; and
- a statically provable bounds, narrowing, or division failure.

An implementation may bound expression nesting, prefix depth, postfix depth, arguments, and retained expression-checking state. It must publish each limit and issue a capacity diagnostic before a stack, counter, temporary pool, or type record overflows. Capacity exhaustion must not change precedence, omit a check, truncate an argument list, or alter an expression's type.

## 9.14 Examples

For `u16` values `a`, `b`, and `c`, these expressions associate as shown:

```nucleus
a - b - c       // (a - b) - c
a / b * c       // (a / b) * c
- -a            // -( -a ) in u16 arithmetic
not not flag    // not (not flag)
```

Postfix operations share one left-to-right path:

```nucleus
cells[index].value
entryAt(index).value
measure(cells[index].value)
```

`entryAt` must return an aggregate alias with the selected record type, and `measure` must have a compatible visible signature. The index is checked before field selection or argument transfer.

These forms illustrate comparison and conversion rules:

```nucleus
minimum <= value and value <= maximum
u16(byteValue) + wordValue
u8(wordValue)
(not (mask and readyMask)) = 0
```

The first expression contains two non-chained comparisons. The third performs checked narrowing. In the last expression, parentheses make the integer complement the left comparison operand; without them, `not` would apply to the Boolean comparison result.

Each of these forms is invalid:

```nucleus
first < second < third  // comparisons do not chain
flag + 1               // Boolean is not integer
recordValue = other    // record equality is absent
shortText < longText   // strings have no comparison operators
routineName            // a routine name is not a value
boolean(value)          // Boolean conversion is absent
```
