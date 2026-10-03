# 11. Conditional control


## 11.1 Scope

This chapter defines the Baton `if` statement, its repeated `elseif` clauses, its optional `else` clause, condition evaluation, and clause selection. Chapter 9 defines Boolean expressions. Chapter 10 defines statement sequences. Chapter 17 supplies the complete grammar.

Baton uses one multiline conditional form. It has no conditional expression, pattern matching, or general multi-way selection statement.

## 11.2 Syntax

The conditional grammar is:

```text
if-statement    ::= "if" expression NEWLINE statement-sequence
                    { "elseif" expression NEWLINE statement-sequence }
                    [ "else" NEWLINE statement-sequence ]
                    "end" NEWLINE
```

`elseif` is one token. The complete chain has one closing `end`. Each clause body is a statement sequence and may be empty. A clause body opens no declaration scope; Chapter 5's routine scope remains in effect throughout the chain.

A logical `NEWLINE` terminates each condition header. Physical line endings inside parentheses or brackets remain suppressed under Chapter 3, so a parenthesized condition may span physical lines without changing this grammar.

## 11.3 Conditions

Every `if` and `elseif` condition must have type `boolean`. Baton does not treat zero, a nonzero integer, an aggregate, an alias carrier, or a routine name as a condition. A call used in a condition must return `boolean`.

The compiler evaluates a condition only when control reaches its clause. It evaluates that expression once, with the order, short-circuiting, checks, and traps defined by Chapter 9. A trap in a condition prevents selection of any clause body.

## 11.4 Clause selection

Execution tests the `if` condition first. If it is `true`, the corresponding body executes and control continues after the closing `end`. If it is `false`, execution tests each `elseif` condition in source order until one is `true`. After a true condition, its body executes and no later condition or body is evaluated.

When every written condition is `false`, the `else` body executes if present. With no `else`, the statement performs no body operation. After the selected body completes normally, execution continues with the statement following the closing `end`.

Effects from an evaluated false condition remain observable. Conditions after a selected true clause are not evaluated and perform no calls, storage accesses, checks, or traps.

## 11.5 Flat and nested forms

The flat form is:

```nucleus
if firstCondition
    firstAction()
elseif secondCondition
    secondAction()
else
    fallbackAction()
end
```

A genuinely nested conditional has another `if` statement and another `end` in a clause body:

```nucleus
if outerCondition
    if innerCondition
        innerAction()
    end
else
    fallbackAction()
end
```

An `if` that is the sole statement of an `else` body can express the same simple truth conditions as a flat `elseif` chain. Baton retains `elseif` because the token marks the clause directly, one `end` closes the chain, and the parser can process repeated clauses with one iterative path. The two spellings do not create different Boolean semantics.

`else if` is not an alternative spelling for `elseif`. It produces two tokens. After `else`, this grammar requires `NEWLINE`; a nested `if` begins as a statement on a following logical line and has its own `end`.

## 11.6 Conditional header termination

Baton conditional headers do not use `then`. The logical newline already separates the condition from its body, and Chapter 9 has no conditional expression whose tokens could extend across that boundary. A `then` keyword would add a reserved word and grammar token without resolving a parsing choice.

Consequently, `then` remains an identifier under Chapter 3. A Boolean variable named `then` may appear as the complete condition in `if then`; the following logical newline terminates that header.

## 11.7 Lowering boundary

The source semantics require ordered condition evaluation and selection of at most one body. A compiler may lower the statement to comparisons, conditional branches, and ordinary branches while parsing it. The internal semantic-operation interface requires no dedicated `if`, `elseif`, or `else` operation.

Branch fixups and active clause state are implementation details. They must preserve the source order above, skip every unselected body, and continue after the one closing `end`.

## 11.8 Excluded conditional mechanisms

Baton 1.0 has no:

- one-line `if` form;
- postfix or statement-modifier condition;
- conditional expression;
- `select` or `case` statement;
- pattern matching;
- fall-through selection; or
- implicit integer truth test.

A restricted dense nonnegative selection form remains a possible later candidate under Chapter 2. It is not standard syntax unless a later specification revision admits it after measurement.

## 11.9 Invalid conditionals and capacity limits

The compiler must diagnose a non-Boolean condition, `elseif` after `else`, more than one `else`, `else if` used as a flat-clause spelling, a missing logical newline, a missing closing `end`, and any clause token outside its conditional context.

An implementation may bound nested conditional depth, clause count, and branch-fixup state. It must publish each limit and issue a capacity diagnostic before overflow changes clause association, skips a selected body, evaluates an unselected condition, or emits an unresolved branch.

## 11.10 Examples

This chain evaluates `ready` first and `waiting` only when `ready` is false:

```nucleus
if ready
    run()
elseif waiting
    poll()
else
    stop()
end
```

An empty body is valid:

```nucleus
if unchanged
elseif needsUpdate
    update()
end
```

These headers are invalid:

```nucleus
if count              // u16 is not a condition
if ready then         // then is an identifier, not a header marker
else if waiting       // not the flat elseif token
```
