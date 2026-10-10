# 13. Routines and calls


## 13.1 Scope

This chapter defines routine declarations as callable interfaces, invocation, parameter kinds including `var` parameters, leases and slot-holders, argument binding, results and the `from` clause, `return`, routine completion, recursive calls, the activation-capacity check, and freeing on exit. Chapters 4, 5, and 8 define declaration order, forwards, names, headers, parameters, and local declarations. Chapters 6 and 7 define value copying, aggregate aliases, and lifetime.

Basie has one routine family. A routine declares no result or one result type. It has no overload, nested declaration, multiple-result form, implicit result variable, routine-name assignment, routine value, indirect call, or callback type.

## 13.2 Routine syntax

The routine fragment is:

```text
routine-header       ::= "sub" NAME routine-signature-tail
routine-signature-tail
                     ::= "(" [ formal-parameter
                         { "," formal-parameter } ] ")"
                         [ result-clause ] [ "fails" ]
formal-parameter     ::= [ "var" ] NAME ":" type
result-clause        ::= ":" [ "var" ] type [ "from" NAME { "," NAME } ]

forward-routine      ::= "forward" routine-header NEWLINE
routine-definition   ::= "sub" NAME routine-definition-tail
routine-definition-tail
                     ::= routine-signature-tail NEWLINE routine-body
                       | NEWLINE routine-body
routine-body         ::= block "end" NEWLINE

routine-invocation   ::= NAME argument-list
argument-list        ::= "(" [ expression { "," expression } ] ")"
return-statement     ::= "return" [ expression ]
```

Chapter 8 remains authoritative for declaration placement; a routine body is a block, in which locals may be declared at any statement position. The fragments here complete their call and result meaning. Parentheses are required in every complete header and invocation, including a routine with no parameters or arguments. The abbreviated header is available only to the body that completes an earlier forward.

An omitted result clause declares a result-free routine. A written type declares one result of that type: a scalar, a handle, or an aggregate returned as an alias (Section 13.6). The optional `fails` effect is defined by Chapter 14. The header has no separate procedure/function keyword and no result-name declaration.

## 13.3 Visible signatures and invocation

A routine invocation begins with a visible routine name whose complete signature has already been checked. An earlier forward declaration supplies that signature when the definition appears later. The compiler does not infer a signature from arguments or defer checking until another pass.

The invocation must supply exactly one argument for each formal parameter, in declaration order. Basie has no optional, named, variadic, grouped, or default arguments. An infallible result-free routine may be used only as the complete call statement from Chapter 10. An infallible result-bearing routine may be used as an expression or as a call statement that discards the result. Chapter 14 restricts every failable call to a position with one explicit failure consumer.

A call expression takes its static result type directly from the signature. A scalar result is a scalar value. An aggregate result is a transient typed alias and may take the field or index suffixes admitted by Chapter 9. It must then be consumed under Section 13.6; a routine name without its argument list is invalid in every expression and statement context.

## 13.4 Parameters and arguments

Arguments are evaluated from left to right, and each is bound before the next is evaluated. If argument evaluation traps, no later argument is evaluated and the body does not begin; effects of earlier arguments remain.

**Scalar parameters.** A scalar parameter receives a copy of its argument, which must be compatible with the parameter type under Chapter 6: the same type, an implicit widening, or an exact value that fits. Narrowing must be written explicitly. Within the routine, a scalar parameter is a local copy and may be assigned. `var` is invalid on a scalar parameter.

**Aggregate parameters.** A record, array or bounded-string parameter is an alias to the caller's object; no copy is made (Chapter 7, Section 7.7).

- Without `var` it is a **ticket**: read-only in the routine (design decision D17). Its argument may be any aggregate designator or aggregate result of exactly the parameter's type, including a constant. For a read-only `string[]` parameter, the argument may be a bounded string of any capacity, or a string literal, which the compiler supplies as a constant.
- With `var`, the routine may write through it. The argument must be a writable designator of exactly the parameter's type, or of any bounded-string capacity for `var s: string[]`, or any complete `T[N]` for `var a: T[]`; a constant or string literal is invalid. A call to a routine whose result is `as var` is also a writable designator, so it may be passed (Section 13.6).
- A `string[]` parameter carries its argument's capacity, so `.length`, `.capacity` and indexing use the real bound.
- An aggregate field of a pool record reached through a handle is copied into a hidden temporary of the caller when passed to a ticket (Chapter 7, Section 7.13); it cannot be passed to a `var` parameter except through a lease.

**Leases.** A record parameter, ticket or `var`, also accepts the record in the slot owned by one of the caller's own owning locals or parameters, or by a temporary, written as that handle: `bump(h)` (design decision D30). This is a **lease** (Chapter 7, Section 7.14): the handle must not appear elsewhere in the same statement except as `id(h)` or a read of a scalar field, and the callee sees an ordinary record with no handle to move or free.

**Handle parameters.**

| Parameter | Argument | Effect |
| --- | --- | --- |
| `n: P` | a fresh `P` or `move` of a non-optional owner | the callee owns the slot; it is freed when `n` goes out of scope unless moved on |
| `n: P?` | `none`, a fresh value or a `move` | as above, or `none` |
| `var n: P?` | a slot-holder: an owning location of type `P?` (Chapter 7, Section 7.14) | the callee may move into it, out of it, or overwrite it |
| `i: id P`, `i: id P?` | an identifier of the type, or `id(...)` | a copy of the identifier |

`var` is invalid on a parameter of type `P`, `id P` or `id P?`.

**Owner words.** A `var` record parameter, a `var` parameter of an owning type, and a slot-holder each carry a hidden owner word supplied by the caller (Chapter 7, Section 7.14). It is not visible in source.

There are no optional, named, variadic or default arguments.

## 13.5 Activation semantics

A successful call begins one activation after all arguments have been evaluated and bound. The activation holds that call's parameters and the locals of its blocks (Chapter 7, Section 7.6). If the routine is forward-declared, its activation-capacity check (Section 13.9) runs first.

Each simultaneously active invocation has distinct activation state. Calling another routine does not change the caller's parameters or locals, except through a `var` parameter or slot-holder that the caller passed. The callee may change program-lifetime storage that it can name or reach through an aggregate argument, and those mutations remain visible to the caller.

The caller resumes after the invocation when the callee returns normally. For an expression call, the result is transferred before evaluation continues in the containing expression. For a call statement, any result is discarded after transfer.

## 13.6 `return` and results

A result-free routine uses bare `return`, or reaches its closing `end`. Every `return expression` is invalid in a result-free routine, including an expression that is a failable invocation. A failable result-free call must consume failure as its own statement before a later successful `return`.

A result-bearing routine uses `return expression`. Bare `return` is invalid. The expression is evaluated once before the activation ends and must be compatible with the declared result type. It cannot be a failable invocation: failure must be propagated or handled by an earlier statement, and `return` represents success only.

A scalar result follows the scalar destination rules of Chapter 6. The caller receives a copied value.

A **handle result** of an owning type `P` or `P?` is a fresh owning value for the caller (Chapter 7, Section 7.11). Its `return` expression must be `none`, a fresh value, or a `move`; returning an owning local or parameter requires `move`, as `return move n`. An identifier result is a copy. A routine cannot return a record or array of an owning type by value.

An **aggregate result** is an alias to an existing object of exactly the result type, not a copy (Chapter 7, Section 7.7). Its root must be program storage, or a parameter named in the routine's `from` clause; it must never be rooted in the routine's own locals (design decision D8). A `from` clause names parameters of aggregate type; it cannot name a slot-holder. Without a `from` clause, every aggregate result must be rooted in program storage.

```basie
sub pick(items: Entry[8], index: u8): Entry from items
    return items[index]
end
```

At a call, the result lives as long as the arguments passed for the `from` parameters. If any of them is rooted in a local of the caller, the result may be used within the caller but can't be returned from it. It can be returned only when every such argument is rooted in program storage or in a parameter that the caller's own `from` clause names (design decision D8).

The result is read-only unless the result clause says `as var Type`. A `var` result must be rooted in a `var` parameter named in `from`, or in program storage other than a constant.

The caller consumes an aggregate result within the statement: by discarding it, passing it to a compatible parameter, returning it, applying a field or index suffix, or using it as the source of an exact-type assignment, which copies it. It cannot be stored.

If evaluating a later argument or suffix performs another call, the compiler preserves the transient carrier until its containing operation consumes it. Backend liveness or argument staging provides that protection; it does not create a source-visible pointer or extend the result beyond the operation.

`return` may appear anywhere in a routine statement sequence, including inside a conditional or loop. It ends the current activation immediately after transferring the result, if any. It does not execute later statements in the routine.

## 13.7 Value-routine completion

A value routine is invalid when its closing `end` is reachable without executing `return expression`. Basie supplies no implicit value.

The rule uses a structured summary of whether each statement can **fall through**:

- `return`, `fail` and an `exit` or `continue` do not fall through; other simple statements and local declarations do;
- an `if` does not fall through only when it has an `else` and no clause body falls through;
- a `select` does not fall through only when some arm always executes, which is when it is an integer or enum selection (Chapter 11 requires one to cover every value) or a handle selection with both a `some` arm and a `none` or `else` arm, and no arm body falls through; and
- every `while` and `for` is treated as able to finish, whatever its condition.

A block falls through when control can pass through every statement on some path. This needs no control-flow graph.

## 13.8 Forward definitions and recursion

A forward declaration contains the routine's complete and sole signature, including parameter names, `var` markers, result clause and `fails`. Its body begins with `sub NAME`; the stored parameter names bind the body, and nothing is repeated.

A call to a routine whose body is not yet complete, including a call from a routine to itself, is valid only if the routine was declared `forward` (Chapter 5, Section 5.9; diagnostic `recursion-needs-forward`). Mutually recursive routines need a forward declaration for every routine called before its definition. So every cycle of calls passes through a forward-declared routine. Recursive calls otherwise follow the ordinary rules.

## 13.9 Activation capacity

When the compiler completes a routine `R`, it computes `need(R)`, the most stack `R`'s calls can use outside cycles (Chapter 7, Section 7.18). Every forward-declared routine begins with the **activation-capacity check**: before its locals are initialized or its body begins, it traps with `activation-capacity` if the stack pointer minus `need(R)` minus the profile's guard band would fall below the start of free memory. Startup checks `need(main)` before calling `main`. So no call overflows the stack unchecked, and a routine that is not forward-declared needs no check.

The check runs after argument evaluation; effects of the arguments remain, and the callee performs nothing.

## 13.10 Exit and lowering boundary

When a routine is left by `return`, `fail` or reaching its `end`, every block it is in is left: its owning locals and owning parameters that still hold values are freed, and so are the owning handles inside its local aggregates (Chapter 7, Section 7.12). A result is evaluated before anything is freed, so `return move n` hands `n` on and frees nothing. A routine's exits may share one epilogue. There are no destructors, `finally` or `defer` beyond this automatic freeing.

This specification does not define registers, save areas, the hardware stack layout, helper entry points or the calling convention. A compiler may lower calls and returns while parsing, and may save and restore implementation state around a call, without any source-visible effect.

## 13.11 Invalid calls and capacity limits

The compiler must diagnose an unavailable or non-routine callee, a missing argument list, wrong arity, an incompatible scalar argument or result, an aggregate argument or result with the wrong type, a constant or literal passed to a `var` parameter, `var` on a parameter type that does not admit it, a lease or slot-holder argument that breaks Section 13.4, a handle argument or result that is not `none`, fresh or a `move` where ownership passes, an aggregate result rooted in a local or in a parameter not named in `from`, a `from` naming a non-aggregate parameter or a slot-holder, a `var` result not rooted as required, a result-free call used as a value, the wrong `return` form, a value routine whose end is reachable, a recursive call without a forward declaration, an abbreviated body without one incomplete forward, and a duplicate or missing forward completion.

An implementation may bound parameters, arguments, active expression-call nesting, retained signatures, fallthrough-summary depth, and compile-time call-graph metadata. It must publish each limit and issue a capacity diagnostic before dropping an argument, corrupting a signature, losing a result, merging live state, or changing a call target. Run-time stack capacity follows Section 13.9.

## 13.12 Examples

A result-free routine and a value routine use the same declaration family:

```basie
sub display(value: u8)
    return
end

sub maximum(left: u16, right: u16): u16
    if left >= right
        return left
    else
        return right
    end
end
```

Both paths through `maximum` return a compatible value. The result may be used directly:

```basie
largest = maximum(first, second)
```

An aggregate result preserves alias identity:

```basie
sub entryAt(index: u8): Entry
    return entries[index]
end

sub update(var items: Entry[8], index: u8)
    items[index].value = entryAt(index).value
end
```

`entryAt` returns an alias to program-lifetime storage. The call itself copies no `Entry`; an aggregate assignment using that result copies into its destination.

To retain the complete returned value, the caller provides destination storage:

```basie
sub retain(index: u8, var destination: Entry)
    destination = entryAt(index)
end
```

or declares a local: `var copy = entryAt(index)` copies the entry into activation storage.

Parameters with ownership:

```basie
sub sink(n: nodes)                 // takes ownership; n is freed at its end
end

sub push(var list: nodes?, v: u16)
    var n = new nodes(v, move list)
    list = move n
end

sub bump(var n: Node)              // a lease when passed a handle
    n.value = n.value + 1
end

sub demo()
    var h = new nodes(1, none)
    bump(h)                          // lends h's record
    push(head, 2)                    // head is a slot-holder
    sink(move h)                     // h now holds none
end
```

Mutual recursion needs a forward declaration for the routine called first; `even` calls the forward-declared `odd`, which carries the activation-capacity check:

```basie
forward sub odd(value: u16): boolean

sub even(value: u16): boolean
    if value = 0
        return true
    end
    return odd(value - 1)
end

sub odd
    if value = 0
        return false
    end
    return even(value - 1)
end
```

These forms are invalid:

```basie
sub missing(value: u8): u8
    if value = 0
        return 1
    end
end                              // value path reaches end

sub procedure()
    return 1                     // result-free routine
end

sub value(): u8
    return                       // value routine requires an expression
end
```
