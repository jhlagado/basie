# 10. Statements


## 10.1 Scope

This chapter defines statement syntax, blocks, local declarations as statements, name-led dispatch, assignment, routine-call statements, `assert`, the statement rule for owning values, and execution order. Chapters 11 and 12 define the compound conditional, selection and loop statements. Chapter 13 completes the rules for calls and `return`. Chapter 12 completes the rules for `exit` and `continue`.

Executable statements occur only in a routine body. A local variable or local constant may be declared at any statement position (Chapter 8, design decision D28). Every statement sequence that the grammar delimits is a **block** and opens a block scope (Chapter 5, Section 5.3).

## 10.2 Statement grammar

The reusable statement fragment is:

```text
block                   ::= { statement }
statement               ::= local-declaration
                          | name-statement name-statement-tail
                          | other-simple-statement NEWLINE
                          | if-statement
                          | select-statement
                          | while-statement
                          | for-statement
name-statement          ::= assignment-statement
                          | routine-call-statement
name-statement-tail     ::= NEWLINE
                          | "else" "fail" NEWLINE
                          | "handle" NAME NEWLINE
                            block "end" NEWLINE
other-simple-statement  ::= return-statement
                          | assert-statement
                          | "exit"
                          | "continue"
                          | fail-statement
assignment-statement    ::= assignment-target "=" expression
assignment-target       ::= NAME { postfix-suffix }
routine-call-statement  ::= NAME argument-list
return-statement        ::= "return" [ expression ]
assert-statement        ::= "assert" expression
```

`local-declaration` is defined in Chapter 8, `select-statement` in Chapter 11 and the loops in Chapter 12. Earlier chapters call a block a `statement-sequence`; the two terms are the same production.

Chapters 11 through 14 define the referenced productions and semantic restrictions. Chapter 17 replaces this fragment with the complete grammar for failable invocations, propagation, and immediate `handle` attachment.

A simple statement consumes one logical `NEWLINE`. An immediate handler consumes the newline after its call site and the newline after its closing `end`. Other compound statements consume the `NEWLINE` after their own closing `end`. Blank and comment-only physical lines produce no token under Chapter 3 and therefore do not create empty statements. A statement sequence may contain no statements; this permits an empty conditional clause, `select` arm, loop body, or handler body without a placeholder operation.

Basie has no semicolon, colon separator, multiple statements on one logical line, one-line compound statement, or empty-statement token.

## 10.3 Name-led dispatch

When a statement begins with `NAME`, the compiler resolves that name before selecting the statement form:

| Resolved declaration                                                         | Required continuation                                                                          |
| ---------------------------------------------------------------------------- | ---------------------------------------------------------------------------------------------- |
| Source routine                                                               | Its argument list, forming a routine-call statement.                                           |
| Mutable scalar variable, parameter, or local                                 | Zero or more field or index suffixes, followed by `=`.                                         |
| Handle variable, parameter, or local                                         | `=`, or field or index suffixes through the handle's record (Chapter 7), followed by `=`.     |
| Aggregate object or alias                                                    | Zero or more field or index suffixes ending at a mutable scalar or aggregate, followed by `=`. |
| Scalar constant, aggregate constant root, type, or another declaration class | No assignment or call statement form; the compiler diagnoses the class mismatch.               |

This dispatch uses the declaration class already established by Chapters 5 and 8. It requires no token backtracking. A routine name followed by `=` is invalid, and a variable followed by an argument list is invalid; the compiler does not reinterpret either name as another declaration class.

Basie has no `call` keyword. An already declared routine name followed by its parenthesized argument list is the canonical invocation statement.

## 10.4 Assignment

An assignment target is a writable path: a mutable scalar, handle or aggregate path rooted in a program variable, a local, or a parameter that the routine may change. A parameter without `var` is read-only, except a scalar or handle parameter, which is a local copy (Chapter 13, design decision D17): an owning handle parameter belongs to the routine and may be moved or overwritten, and an identifier parameter may be reassigned. A path rooted at a constant is never a target. A path through a handle to a pool record is writable under the access rules of Chapter 7. A bounded-string byte selected through a writable root is writable; `.length` of a `string[]` parameter is writable as Chapter 6 allows, and that of a concrete string is not.

A local used as the counter of an enclosing counted loop is read-only until that loop ends (Chapter 12).

**Order for ordinary destinations.** When the destination is not of an owning type, the compiler evaluates an assignment in this order:

1. evaluate the target path from left to right, including every index expression and bounds check, and the generation check of each identifier on the path;
2. evaluate the right-hand expression;
3. apply the destination compatibility and checked-conversion rules;
4. check each identifier on the target path again, since the right side may have freed its slot (Chapter 7, Section 7.13); and
5. store the scalar result, or copy the aggregate into the selected destination.

The target path is evaluated once. If target evaluation traps, the right-hand expression is not evaluated. If the right-hand expression or a checked conversion traps, the destination is not changed, although effects from the earlier target evaluation remain.

**Order for owning destinations.** When the destination holds an owning handle, or is of an owning type, the order is that of [memory safety](../docs/memory-safety.md), Section 5.3:

1. evaluate the target path, as for an ordinary destination;
2. evaluate the right-hand expression, which must be `none`, a fresh owning value, or a `move` (Chapter 7);
3. check each identifier on the target path again;
4. free the value the destination held, if any; and
5. store the new value.

What matters is that the right side comes before the free: `head = move h.next`, with `h` a lease of `head`, reads `h.next` before the old head is freed. Leases, the statement rule and the recheck in step 3 stop the right side from freeing anything the target path uses. Storing into an owning location inside a pool record also records the owner link and performs the cycle check of Chapter 7.

**Compatibility.** A scalar destination uses the conversion rules of Chapter 6. An aggregate destination requires a source of exactly the same concrete type. An aggregate of an owning type cannot be copied, so a whole-object assignment to it is invalid (Chapter 7); its handles move one at a time with `move`. A handle destination requires a source of a compatible handle type: an owning destination takes an owning value with the transfer rules of Chapter 7, and an identifier destination takes an identifier, or an owning handle converted with `id(...)`.

In this statement position, `=` is the assignment operator. Inside an expression, it is equality under Chapter 9. Assignment is not an expression and produces no value. Chained assignment, compound assignment such as `+=`, increment and decrement statements, and assignment inside a condition or argument are absent.

## 10.5 Routine-call statements

A routine-call statement invokes one visible routine or service with the argument list defined by Chapters 9 and 13. A result-free routine is valid in this form. A result may also be discarded; discarding it does not suppress argument evaluation, routine effects, checks, or traps. A discarded fresh owning result is held in the statement's temporary and freed when the statement ends (Section 10.8).

Only the invocation itself forms the statement. A scalar arithmetic expression, comparison, storage read, conversion, field selection, or index operation cannot stand as a statement. An aggregate result cannot be selected and then discarded as an expression statement. These restrictions keep name-led dispatch distinct from general expression parsing.

## 10.6 `return`, `fail`, `exit`, and `continue`

`return` leaves the current routine successfully under Chapter 13. Its permitted expression form depends on the routine's declared result. `fail` leaves a failable routine unsuccessfully under Chapter 14. Neither form is loop control.

`exit` and `continue` apply only to the innermost enclosing loop under Chapter 12. They do not leave a routine or terminate the program. Either word outside a loop is invalid.

All four are complete simple statements. No label, condition, target name, or trailing expression may follow `exit` or `continue`.

## 10.7 `assert`

`assert condition` evaluates a `boolean` condition when execution reaches it (design decision D37). If the condition is `true`, execution continues with the next statement. If it is `false`, the program traps with reason `assertion` (Chapter 15), and the trap report gives the site's address like any other trap.

There is no message operand; the line table names the source line. A condition that is a constant expression evaluating to `false` is diagnosed during compilation as `assertion-false`, as for other checks whose operands are all constant (Chapter 15, Section 15.3). A constant `true` condition generates no code.

The condition is evaluated once, with the order, short-circuiting and traps of Chapter 9. A `move` inside the condition is invalid.

## 10.8 Owning values in statements

Chapter 7 defines owning handles, moves and freeing. Three rules apply to statements.

**Fresh temporaries.** A fresh owning value that a statement creates but does not store, such as the unused result of `new` or of a routine returning an owning handle, is held in an anonymous local of that statement. The local is set to `none` when the statement begins and its value is freed on every exit from the statement. For a `select` statement, the statement is the whole `select`, so a fresh subject lives until the end of the last arm. A temporary created in an `if`, `elseif` or `while` condition is freed once the condition has been tested. A temporary in a call with a `handle` body lives until the end of the handle body.

**The statement rule.** Within one statement, an owning local or parameter that is used directly anywhere, as an access path such as `x.value` or `x.kids[k]`, an assignment destination, a lease argument, or a `select` subject, must not be moved or overwritten anywhere else in that statement ([memory safety](../docs/memory-safety.md), Section 5.8). The exceptions are `id(x)`, reads of scalar fields, and a plain `x = ...` with no other direct use of `x`. So these are invalid, because the right side would free a node the left side or a lease still uses:

```basie
x.value = eat(move x)        // invalid
show(h, eat(move h))         // invalid
```

**The flow check.** For each owning local and parameter, the compiler tracks whether it certainly holds a value, certainly holds `none`, or may hold either, as it reads each statement in order. Accessing or moving a non-optional owning local that may have been moved is invalid. The state changes at the point of each `move`. Chapters 11 and 12 define how states meet at the ends of conditional, selection and loop statements. `move` is not allowed inside an operand of `and` or `or`, or in a `while` condition.

## 10.9 Execution and bounded failure

Statements in a block begin in source order. A compound statement completes before the following statement begins. A `return`, `fail`, taken `exit`, taken `continue`, or trap prevents normal execution of the remaining statements on that path. When control leaves a block by any path other than a trap, the block's owning locals are freed (Chapter 7); a trap ends the program and frees nothing (Chapter 15, Section 15.1).

A compiler may emit semantic operations as it checks each statement. It need not retain a statement tree. Forward branches may use bounded fixup state under Chapter 2, provided capacity exhaustion produces a diagnostic rather than an unresolved or incorrect branch.

The compiler must diagnose an invalid statement start, a wrong-class name, a missing assignment operator or argument list, a non-writable assignment target, an assignment to an active counted-loop counter, an incompatible right-hand expression, a copy of an owning value, a forbidden general expression statement, a violation of the statement rule or the flow check, an `assert` that is certainly false, and any context-invalid `return`, `fail`, `exit`, or `continue`.

An implementation may bound statement nesting, active control contexts, branch fixups, and retained emission state. It must publish each limit and issue a capacity diagnostic before overflow changes statement association, branch targets, or execution order.

## 10.10 Examples

These are valid simple statements when the names have compatible declarations:

```basie
var total: u16 = 0
count = count + 1
assert count < limit
cells[index].value = nextValue()
cells[index] = template
updateDisplay()
measure(count)
return
exit
continue
```

`measure(count)` remains a routine-call statement even when `measure` has a result; the result is discarded. `exit` and `continue` require an enclosing loop, and bare `return` requires a result-free routine.

These forms are invalid:

```basie
count + 1                 // general expression statement
call updateDisplay()      // no call keyword
count = total = 0         // assignment is not an expression: with u16 locals,
                          // this compares total with 0 and can't store a boolean
cells = shorterCells      // invalid when the fixed-array types differ
cells[index]              // storage read is not a statement
```
