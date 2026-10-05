# 11. Conditional control


## 11.1 Scope

This chapter defines the Basie `if` statement, with its `elseif` and `else` clauses, and the `select` statement (design decision D15), which chooses among integer constants, ranges, and the states of an optional handle. It also defines how the flow states of owning locals meet at the end of each. Chapter 9 defines Boolean expressions. Chapter 10 defines statement sequences. Chapter 17 supplies the complete grammar.

Both statements are multiline. Basie has no conditional expression and no general pattern matching.

## 11.2 Syntax

The conditional grammar is:

```text
if-statement    ::= "if" expression NEWLINE statement-sequence
                    { "elseif" expression NEWLINE statement-sequence }
                    [ "else" NEWLINE statement-sequence ]
                    "end" NEWLINE
```

`elseif` is one token. The complete chain has one closing `end`. Each clause body is a block and may be empty. Each body opens its own block scope (Chapter 5, Section 5.3), so a local declared in one clause is not visible in another or after the `end`.

A logical `NEWLINE` terminates each condition header. Physical line endings inside parentheses or brackets remain suppressed under Chapter 3, so a parenthesized condition may span physical lines without changing this grammar.

## 11.3 Conditions

Every `if` and `elseif` condition must have type `boolean`. Basie does not treat zero, a nonzero integer, an aggregate, an alias carrier, or a routine name as a condition. A call used in a condition must return `boolean`.

The compiler evaluates a condition only when control reaches its clause. It evaluates that expression once, with the order, short-circuiting, checks, and traps defined by Chapter 9. A trap in a condition prevents selection of any clause body.

## 11.4 Clause selection

Execution tests the `if` condition first. If it is `true`, the corresponding body executes and control continues after the closing `end`. If it is `false`, execution tests each `elseif` condition in source order until one is `true`. After a true condition, its body executes and no later condition or body is evaluated.

When every written condition is `false`, the `else` body executes if present. With no `else`, the statement performs no body operation. After the selected body completes normally, execution continues with the statement following the closing `end`.

Effects from an evaluated false condition remain observable. Conditions after a selected true clause are not evaluated and perform no calls, storage accesses, checks, or traps.

### 11.4.1 Flow states after `if`

Each clause body starts in the state after its own condition, which follows every earlier condition, since those were all evaluated before it. The `else` body starts in the state after the last condition. So a `move` in an `elseif` condition is seen by that clause, by every later clause and by the `else` body.

The flow state of each owning local after an `if` statement (Chapter 10, Section 10.8) is the meet of the states at the end of every clause body that can complete normally, together with the state after the last condition when there is no `else`. The meet of two equal states is that state; the meet of different states is "may hold either". A body that always ends with `return`, `fail`, `exit` or `continue` does not contribute.

## 11.5 Flat and nested forms

The flat form is:

```basie
if firstCondition
    firstAction()
elseif secondCondition
    secondAction()
else
    fallbackAction()
end
```

A genuinely nested conditional has another `if` statement and another `end` in a clause body:

```basie
if outerCondition
    if innerCondition
        innerAction()
    end
else
    fallbackAction()
end
```

An `if` that is the sole statement of an `else` body can express the same simple truth conditions as a flat `elseif` chain. Basie retains `elseif` because the token marks the clause directly, one `end` closes the chain, and the parser can process repeated clauses with one iterative path. The two spellings do not create different Boolean semantics.

`else if` is not an alternative spelling for `elseif`. It produces two tokens. After `else`, this grammar requires `NEWLINE`; a nested `if` begins as a statement on a following logical line and has its own `end`.

## 11.6 Conditional header termination

Basie conditional headers do not use `then`. The logical newline already separates the condition from its body, and Chapter 9 has no conditional expression whose tokens could extend across that boundary. A `then` keyword would add a reserved word and grammar token without resolving a parsing choice.

Consequently, `then` remains an identifier under Chapter 3. A Boolean variable named `then` may appear as the complete condition in `if then`; the following logical newline terminates that header.

## 11.7 `select`

### 11.7.1 Syntax

```text
select-statement ::= "select" [ "move" ] expression NEWLINE
                     case-arm { case-arm }
                     [ "case" "else" NEWLINE block ]
                     "end" NEWLINE
case-arm         ::= "case" case-label { "," case-label } NEWLINE block
                   | "case" "some" "(" NAME ")" NEWLINE block
                   | "case" "none" NEWLINE block
case-label       ::= constant-expression [ "to" constant-expression ]
```

The expression after `select` is the **subject**. A `select` has at least one `case` arm before any `case else`, and at most one `case else`, which comes last. Each arm's body is a block with its own scope. There is no fall-through: after an arm's body completes, execution continues after the `end`. `select` is a statement, not an expression.

A `select` is either an **integer selection** or a **handle selection**, chosen by the subject's type.

### 11.7.2 Integer selection

The subject has an integer type: `u8`, `i8`, `u16`, `i16`, `u32` or `i32`. An exact subject, such as a literal or an untyped constant, has no type to select on and is invalid (`no-definite-type`). Labels written as character literals are exact (Chapter 6), so selections on characters are usually `u8` selections. `move` is invalid.

Each label is a constant expression, or a range `low to high` of two. Each label is converted to the subject's type as an assignment would convert it: an exact label must fit the type, and a typed constant label must widen to it without a conversion, so a `u16` constant can't label a `u8` subject even when its value would fit (Chapter 6, Section 6.4). In a range `low` must not exceed `high`. No value may be covered by two labels, in the same arm or in different arms; an overlap is diagnosed as `duplicate-case`. `some` and `none` arms are invalid.

The subject is evaluated once, before any label is compared. If its value is covered by a label, that arm's body executes. Otherwise the `case else` body executes if present; with no `case else`, no body executes. The arms need not cover every value.

```basie
select key
case 'q', 'Q'
    exit
case '0' to '9'
    digit(key - '0')
case else
    beep()
end
```

A compiler may implement the comparison by tests, a jump table or a search; the choice is not observable.

### 11.7.3 Handle selection

The subject has an optional handle type, `P?` or `id P?`, or the non-optional identifier type `id P`. A non-optional owning subject of type `P` is invalid, since it always holds a value. The arms are exactly one `case some(NAME)`, and either one `case none` or one `case else`; `case none` may come before or after the `some` arm, but `case else` comes last. The second arm may be omitted. Integer labels are invalid.

- For an identifier subject, `some` means that the slot the identifier names is still live, and `none` means that the identifier is empty or its slot has been freed. The test never traps.
- For an owning subject, `some` means that it holds a handle, and `none` that it is `none`.

The name in `some(NAME)` is declared in that arm's block scope. What it denotes depends on the subject ([memory safety](../docs/memory-safety.md), Section 5.5):

| Subject | `NAME` in `some(NAME)` |
| --- | --- |
| An identifier | An identifier of type `id P` |
| An owning program variable, an owning field, or a slot-holder (a `var` handle parameter, which may name either) | An identifier of type `id P` |
| The routine's own owning local, owning parameter (not a slot-holder) or temporary, without `move` | A lease: direct access to the record for the length of the arm (Chapter 7). The subject cannot be moved, overwritten or passed to a slot-holder within the arm |
| Any owning location, with `select move` | A non-optional owning local of type `P`, owned by the arm |

**`select move`.** `select move x` requires `x` to be an owning location of type `P?`. It moves the value out of `x`, leaving `none`, before choosing the arm. In `some(n)`, `n` owns the value and is freed at the end of the arm unless it is moved on; this is how a `P?` becomes a `P`. In `none`, nothing was moved. After the `select`, `x` certainly holds `none` if it is a local or parameter.

```basie
select head
case some(i)          // head is a program variable: i is an identifier
    show(i.value)
case none
    showEmpty()
end

select move spare
case some(n)          // n is a nodes, owned by this arm
    keep(move n)
case none
end
```

A fresh subject is held in the statement's temporary (Chapter 10, Section 10.8) and lives until the end of the last arm.

### 11.7.4 Flow states after `select`

As for `if` (Section 11.4.1), the flow state of each owning local after a `select` is the meet of the states at the end of every arm that can complete normally, together with the state after the subject when no arm need execute: an integer selection without `case else`, or a handle selection with only a `some` arm.

## 11.8 Lowering boundary

The source semantics require ordered condition evaluation and selection of at most one body. A compiler may lower the statement to comparisons, conditional branches, and ordinary branches while parsing it. The internal semantic-operation interface requires no dedicated `if`, `elseif`, or `else` operation.

Branch fixups and active clause state are implementation details. They must preserve the source order above, skip every unselected body, and continue after the one closing `end`.

## 11.9 Excluded conditional mechanisms

Basie 1.0 has no:

- one-line `if` form;
- postfix or statement-modifier condition;
- conditional expression;
- general pattern matching, guards or destructuring;
- selection on strings, records or `f32` values;
- fall-through between `select` arms; or
- implicit integer truth test.

Enumerations, and variants whose cases carry data, with exhaustiveness checking, are planned for version 2 as extensions of `select` (design decision D24).

## 11.10 Invalid conditionals and capacity limits

The compiler must diagnose a non-Boolean condition, `elseif` after `else`, more than one `else`, `else if` used as a flat-clause spelling, a missing logical newline, a missing closing `end`, and any clause token outside its conditional context. For `select` it must diagnose a subject of another type, a label that is not constant or not representable in the subject's type, a reversed range, an overlapping label (`duplicate-case`), a `select` with no `case` arm, `case else` not last or repeated, integer labels in a handle selection, `some` or `none` in an integer selection, a repeated `some` or `none` arm, both `case none` and `case else`, `select move` on a subject that is not an owning location of optional type, and any use of a leased subject that the lease forbids.

An implementation may bound nested conditional depth, clause count, `select` labels, and branch-fixup state. It must publish each limit and issue a capacity diagnostic before overflow changes clause association, skips a selected body, evaluates an unselected condition, or emits an unresolved branch.

## 11.11 Examples

This chain evaluates `ready` first and `waiting` only when `ready` is false:

```basie
if ready
    run()
elseif waiting
    poll()
else
    stop()
end
```

An empty body is valid:

```basie
if unchanged
elseif needsUpdate
    update()
end
```

These headers are invalid:

```basie
if count              // u16 is not a condition
if ready then         // then is an identifier, not a header marker
else if waiting       // not the flat elseif token
```
