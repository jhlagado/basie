# 12. Loop control


## 12.1 Scope

This chapter defines the two Basie 1.0 loop forms, counted-loop direction and bounds, and the required `exit` and `continue` statements. Chapter 9 defines expressions, and Chapter 10 defines statement sequences.

Basie has one pre-test conditional loop and one counted loop. Both use ordinary comparisons and direct Z80 branches; neither requires a dedicated loop runtime mechanism.

## 12.2 Grammar

The reusable loop fragment is:

```text
while-statement       ::= "while" expression NEWLINE
                          statement-sequence
                          "end" NEWLINE

for-statement         ::= "for" NAME "=" expression
                          for-bound expression
                          [ "step" step-constant ] NEWLINE
                          statement-sequence
                          "end" NEWLINE
for-bound             ::= "to" | "until"
step-constant         ::= [ "+" | "-" ] step-magnitude
step-magnitude        ::= NUMBER | NAME
```

A `NAME` used as a step magnitude must denote an earlier named constant whose value is a non-negative integer: an untyped integer constant, or a typed constant of an integer type. The optional sign belongs to the counted-loop header. A written numeric magnitude follows Chapter 3's integer-literal forms.

Each loop body is a block and may be empty. The body opens a block scope (Chapter 5), entered afresh on each iteration: a local declared in the body is created and initialized on every iteration, and the body's owning locals are freed at the end of every iteration, including one ended by `continue` or `exit` (Chapter 7). The loop's `end` closes only that loop.

## 12.3 `while`

A `while` condition must have type `boolean`. The condition is evaluated before every possible iteration. When it produces `true`, the body executes. Normal completion of the body returns control to the condition. When the condition produces `false`, execution continues after the loop.

The loop may execute zero times. Calls, checks, mutations, and traps performed by each evaluated condition remain observable. A condition is evaluated once per test; a trap prevents entry to the body or any later iteration.

An indefinite loop uses `while true`. Basie has no separate unconditional-loop keyword.

A `move` is invalid in a `while` condition. A fresh temporary created in the condition is freed once the condition has been tested (Chapter 10, Section 10.8).

## 12.4 Counted-loop counter and operands

The counter name must resolve to a local variable of an integer type, `u8`, `i8`, `u16`, `i16`, `u32` or `i32` (design decision D31), declared before the loop in an enclosing block. A program variable, parameter, constant, `f32` or `boolean` local, aggregate, handle, routine, field path or indexed path is invalid. The loop introduces no declaration.

The counter becomes read-only to source statements from the beginning of the loop body through its closing `end`. The body may read it and pass its scalar value, but it cannot assign to it. A nested counted loop cannot reuse the same local as its counter because its initialization would be another write. The compiler enforces both restrictions by comparing the resolved local binding with the counters in its active loop contexts; it needs no call-graph analysis because another routine cannot name a caller's local.

The start expression must be assignment-compatible with the counter type. The bound must be an integer expression whose type and the counter's type are compatible under the mixed-operand rule of Chapter 9, Section 9.7; the comparison is done in the wider type. An exact bound remains mathematical for the loop comparison and need not fit the counter, because the bound is never stored in it.

The compiler evaluates the start expression and then the bound expression exactly once when the loop begins. It performs both evaluations before storing the converted start in the counter. A bound expression that reads the counter therefore reads its pre-loop value. If either evaluation or the start conversion traps, the counter is not initialized by the loop and the body does not begin.

`step` defaults to `+1`. A written step is a compile-time signed constant. The compiler resolves a named magnitude under Chapter 5, applies the optional sign, and requires a nonzero magnitude no greater than the largest value of the counter's type. `step 0` and `step -0` are invalid. A negative step is valid for unsigned counters as well as signed ones: the sign gives the direction, and the counter itself never holds a negative value it cannot represent.

## 12.5 Counted-loop tests

`to` makes the bound inclusive. `until` makes it exclusive. The step sign selects the comparison:

| Step direction | `to` continues while | `until` continues while |
| -------------- | -------------------- | ----------------------- |
| Positive       | counter `<=` bound   | counter `<` bound       |
| Negative       | counter `>=` bound   | counter `>` bound       |

The compiler stores the converted start in the counter and performs this test before the first iteration. A start already beyond the bound in the selected direction therefore executes zero iterations and leaves the counter holding the start value.

After normal body completion, and after `continue`, the implementation computes the next counter value mathematically and tests it against the bound before storing it. A value that fails the next test ends the loop without being stored. A value that would continue must fit the counter type. Every such overflow is the runtime `loop-range` trap defined by Chapter 15, even when the compiler can prove it from source constants. The trap occurs only if execution reaches the increment path; an earlier `exit`, `return`, `fail`, or other terminating transfer from the body prevents that increment and its trap.

This order prevents the loop machinery from wrapping an unsigned counter at its terminal boundary. Because the body cannot change the counter, the value reaching the increment still satisfies the comparison that admitted the current iteration. The implementation may use that invariant when comparing the remaining distance with the constant step.

After the loop, the counter retains the last value stored. A zero-iteration loop leaves the converted start. `exit` also leaves the current counter value unchanged.

### 12.5.1 Flow states in loops

The flow check (Chapter 10, Section 10.8) treats loops at their **back edges**: the end of the body when it can complete normally (Chapter 13, Section 13.7), every `continue`, and, for `while`, the return to the condition. At each back edge, every non-optional owning local that certainly held a value when the loop began must certainly hold one again; otherwise the program is invalid. The compiler checks this when it reaches each back edge, so the rule needs no look-ahead.

The flow state after a loop is the meet of the state when the loop's test fails and the state at every `exit` from that loop.

## 12.6 `to`, `until`, and collection traversal

The canonical traversal of indices from zero through a length minus one uses the exclusive form:

```basie
for index = 0 until itemCount
    visit(index)
end
```

The inclusive form directly expresses a closed ordinal interval. Positive and negative steps use the same surface forms; the sign, not the spelling `to` or `until`, determines direction.

The start and bound are not reevaluated after the loop begins. A change to storage read by the original bound expression does not change the saved bound for the active loop.

Basie has no `for in`, iterator protocol, range object, callback traversal, anonymous counter, omitted start, omitted bound, implicit array-length bound, or source form that declares the counter. The counter and both endpoint expressions are explicit.

## 12.7 `exit` and `continue`

Every Basie loop supports bare `exit` and bare `continue`. They are unlabeled and apply to the innermost enclosing loop.

`exit` transfers control to the statement after that loop's closing `end`. It does not leave the routine or terminate the program.

In a `while` loop, `continue` transfers control to the next condition test. In a counted `for` loop, it transfers control to the increment-and-next-test path from Section 12.5. It does not skip the increment.

Either statement outside a loop is invalid. Basie has no labelled transfer, numeric loop depth, `break` synonym, or transfer directly to an outer loop. An early `return` under Chapter 13 remains the way to leave the routine from inside nested loops.

The grammar adds only the two simple statements, and their lowering uses the active loop's existing continue and exit branch targets. This low incremental structure is a settled language decision; target-byte cost remains subject to the Chapter 2 ledger.

## 12.8 Lowering boundary

A counted loop has the same source effect as ordered start and bound evaluation, counter initialization, a direction-specific comparison, a conditional branch, a body in which the counter is read-only, a checked mathematical increment, and a backward branch. `to` and `until` differ only in whether the bound comparison is inclusive.

The semantic-operation interface requires no dedicated `for`, `while`, `exit`, or `continue` operation. A compiler may emit ordinary comparisons and branches, provided it preserves one-time operand evaluation, the test and store order, and the transfer targets above.

## 12.9 Excluded loop forms

Basie 1.0 has no:

- `repeat until` or `do while` loop;
- post-test loop;
- general unconditional `loop` statement;
- collection or iterator loop;
- omission-based counted-loop variant; or
- labelled loop or labelled transfer.

These omissions leave `while` for condition-controlled iteration and one mechanically specified `for` for counted traversal.

## 12.10 Invalid loops and capacity limits

The compiler must diagnose a non-Boolean `while` condition, a `move` in a `while` condition, a back edge that breaks the flow rule of Section 12.5.1, a counter that is not a local of an integer type, assignment to an active counter, reuse of an active counter by a nested loop, an incompatible start or bound, an unavailable or nonconstant step magnitude, a zero step, a missing header `NEWLINE` or closing `end`, and `exit` or `continue` outside a loop.

An implementation may bound loop nesting, retained saved bounds, active counter bindings, active branch targets, and fixup state. It must publish each limit and issue a capacity diagnostic before overflow changes a loop's bound, direction, target, or counter update.

## 12.11 Examples

With `level`, `index`, `row`, and `position` declared as integer locals, these counted loops visit ascending, exclusive, and descending ranges:

```basie
for level = 1 to 10
    loadLevel(level)
end

for index = 0 until itemCount
    visit(index)
end

for row = 7 to 0 step -1
    clearRow(row)
end

var offset as i16
for offset = -3 to 3
    plot(centre + offset)
end
```

This direction mismatch executes zero iterations:

```basie
for position = 7 to 0 step 1
    unreachableAction()
end
```

Nested transfer targets the inner loop:

```basie
while active
    for index = 0 until itemCount
        if skip(index)
            continue
        elseif stop(index)
            exit
        end
        visit(index)
    end
    update()
end
```

The `continue` advances and retests the `for`; the `exit` leaves that `for` and proceeds to `update()`.

These forms are invalid:

```basie
for index = 0 until itemCount
    index = index + 1       // the active counter is read-only
end

for index = 0 until itemCount
    for index = 0 until 4   // a nested loop cannot reuse it
    end
end
```

A program variable or parameter is likewise unavailable as a counted-loop counter. A `while` loop remains available when a program needs to update its progress variable explicitly.
