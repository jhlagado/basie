# 13. Routines and calls


## 13.1 Scope

This chapter defines routine declarations as callable interfaces, invocation, argument binding, results, `return`, routine completion, recursive calls, and source-level activation behaviour. Chapters 4, 5, and 8 define declaration order, forwards, names, headers, parameters, and local declarations. Chapters 6 and 7 define value copying, aggregate aliases, and lifetime.

Baton has one routine family. A routine declares no result or one result type. It has no overload, nested declaration, multiple-result form, implicit result variable, routine-name assignment, routine value, indirect call, or callback type.

## 13.2 Routine syntax

The routine fragment is:

```text
routine-header       ::= "sub" NAME routine-signature-tail
routine-signature-tail
                     ::= "(" [ formal-parameter
                         { "," formal-parameter } ] ")"
                         [ "as" type ] [ "fails" ]
formal-parameter     ::= NAME "as" type

forward-routine      ::= "forward" routine-header NEWLINE
routine-definition   ::= "sub" NAME routine-definition-tail
routine-definition-tail
                     ::= routine-signature-tail NEWLINE routine-body
                       | NEWLINE routine-body
routine-body         ::= { local-declaration }
                         statement-sequence "end" NEWLINE

routine-invocation   ::= NAME argument-list
argument-list        ::= "(" [ expression { "," expression } ] ")"
return-statement     ::= "return" [ expression ]
```

Chapter 8 remains authoritative for declaration placement and the local-declaration prefix. The fragments here complete their call and result meaning. Parentheses are required in every complete header and invocation, including a routine with no parameters or arguments. The abbreviated header is available only to the body that completes an earlier forward.

An omitted result type declares a result-free routine. A written type declares one result of that exact scalar or aggregate type. The optional `fails` effect is defined by Chapter 14. The header has no separate procedure/function keyword and no result-name declaration.

## 13.3 Visible signatures and invocation

A routine invocation begins with a visible routine name whose complete signature has already been checked. An earlier forward declaration supplies that signature when the definition appears later. The compiler does not infer a signature from arguments or defer checking until another pass.

The invocation must supply exactly one argument for each formal parameter, in declaration order. Baton has no optional, named, variadic, grouped, or default arguments. An infallible result-free routine may be used only as the complete call statement from Chapter 10. An infallible result-bearing routine may be used as an expression or as a call statement that discards the result. Chapter 14 restricts every failable call to a position with one explicit failure consumer.

A call expression takes its static result type directly from the signature. A scalar result is a scalar value. An aggregate result is a transient typed alias and may take the field or index suffixes admitted by Chapter 9. It must then be consumed under Section 13.6; a routine name without its argument list is invalid in every expression and statement context.

## 13.4 Argument evaluation and compatibility

Arguments are evaluated from left to right. Each scalar argument is evaluated and converted if permitted, and its resulting value is retained before evaluation of the next argument. Each aggregate argument evaluates its storage path, including field selection and checked indexing, and establishes the alias value supplied to the parameter.

If argument evaluation traps, no later argument is evaluated and the routine body does not begin. Effects from earlier arguments remain observable.

A scalar argument must have the exact parameter type, be an exact literal that fits it, or use the implicit `u8`-to-`u16` widening. Passing `u16` to `u8` requires explicit checked `u8(...)`. Boolean and integer arguments do not convert between each other.

An argument for a concrete aggregate parameter must be an aggregate storage path or transient alias with exact referent-type identity. An argument for `string[]` may instead have any concrete bounded-string capacity or be another open-string parameter. In every case the call transfers an alias rather than copying the object. An open-string binding also retains the actual capacity so `.length` and indexing use the referent's real bound. Scalar-leaf mutation through the parameter is visible through every other path to the same storage.

A string literal is not an aggregate argument. Source that passes fixed text first declares a concrete bounded-string constant and passes that name. This keeps argument evaluation within the ordinary storage-and-alias model.

Baton has no parameter modes, implicit read-only aggregate parameter, write permission, copy-in/copy-out aggregate parameter, or hidden source-level pointer conversion.

## 13.5 Activation semantics

A successful call begins one logical activation after all arguments have been evaluated. The activation contains that invocation's copied scalar parameters, aggregate-parameter bindings, and scalar locals. Activation-local initialization follows Section 8.12 before the first statement begins.

Each simultaneously active invocation has distinct activation state. Calling another routine does not change the caller's scalar parameters, scalar locals, or aggregate-parameter bindings. The callee may change program-lifetime storage that it can name or reach through an aggregate argument, and those mutations remain visible to the caller.

The caller resumes after the invocation when the callee returns normally. For an expression call, the result is transferred before evaluation continues in the containing expression. For a call statement, any result is discarded after transfer.

## 13.6 `return` and results

A result-free routine uses bare `return`, or reaches its closing `end`. Every `return expression` is invalid in a result-free routine, including an expression that is a failable invocation. A failable result-free call must consume failure as its own statement before a later successful `return`.

A result-bearing routine uses `return expression`. Bare `return` is invalid. The expression is evaluated once before the activation ends and must be compatible with the declared result type. It cannot be a failable invocation: failure must be propagated or handled by an earlier statement, and `return` represents success only.

A scalar result follows the scalar destination rules: exact type, fitting exact literal, or implicit `u8`-to-`u16` widening. Checked narrowing must be written explicitly. The caller receives a copied scalar value.

An aggregate result must be an aggregate storage path or transient aggregate-alias result with exact referent-type identity. The storage path is rooted in a visible program variable, aggregate constant, or aggregate parameter. The caller receives a transient alias to the same existing program-lifetime object, not a copy. Section 7.9 establishes the lifetime of every admitted aggregate result without another result check.

The caller may consume that transient alias only by discarding it as a complete call statement, passing it directly to a compatible aggregate parameter, forwarding it as an aggregate return, applying an immediate field or index suffix, or using it as an exact-type aggregate-assignment source. It cannot be retained in a source variable. To retain the returned value, the caller assigns the call result into a program object or caller-supplied aggregate destination, causing the copy defined by Section 7.8.

If evaluating a later argument or suffix performs another call, the compiler preserves the transient carrier until its containing operation consumes it. Backend liveness or argument staging provides that protection; it does not create a source-visible pointer or extend the result beyond the operation.

`return` may appear anywhere in a routine statement sequence, including inside a conditional or loop. It ends the current activation immediately after transferring the result, if any. It does not execute later statements in the routine.

## 13.7 Value-routine completion

A value routine is invalid when its closing `end` is reachable without executing `return expression`. Baton does not supply an implicit value, result variable, or default return.

The static rule uses a bounded structured fallthrough summary:

- `return expression` does not fall through;
- assignment and call statements fall through;
- an `if` does not fall through only when it has an `else` and every clause body does not fall through;
- an `if` without `else` may fall through; and
- every `while` and `for` is treated as able to finish, regardless of a constant condition or its body.

A statement sequence can reach its end when control can pass through every statement on a path. Once a statement on a path does not fall through, later statements on that path do not restore fallthrough. This rule permits one streaming summary per nested statement and requires no control-flow graph.

The conservative loop rule is part of Baton 1.0 validity. A value routine whose only non-returning path is an apparently indefinite loop still requires a structurally reachable `return expression` after that loop or another arrangement that satisfies the rules above.

## 13.8 Forward definitions and recursion

A forward declaration contains the routine's complete and sole signature, including its parameter names. Its later body begins with `sub NAME` and a logical newline. That name must resolve to exactly one incomplete forward under Chapters 4, 5, and 8. The stored parameter names bind the body; no parameter, result, or `fails` clause is repeated. The forward declaration and body definition denote one routine.

The body does not repeat the signature, so the compiler performs no body-signature comparison. A streaming compiler must retain the forward's parameter names as well as its type and effect metadata until it compiles the body. The current compiler uses the measured retained routine and parameter tables published in the implementation plan.

After its complete signature has been checked, a routine may call itself directly. Mutually recursive routines require an earlier forward signature for every routine called before its definition. Recursive calls use the ordinary argument, activation, result, and lifetime rules; Baton has no separate recursive syntax.

Recursion is admitted in Baton 1.0 and implemented by the current compiler. Standard language mode must not reinterpret or reject recursive source within the implementation's documented compile-time capacities.

## 13.9 Activation capacity

Runtime activation capacity is implementation-defined. An implementation may bound the number of simultaneously active routine invocations, the storage consumed by their activation state, or both. It must publish every bound and provide at least the capacity needed by every complete accepted program in Chapter 21 under its stated inputs. Before beginning a call that would exceed a published bound, the program performs the activation-capacity trap specified by Chapter 15; it must not overwrite a live activation, alias one activation's locals with another, or continue with partial parameter binding.

The trap point is after argument evaluation and before the new activation begins. Effects from evaluated arguments remain observable, while the callee performs no local initialization or body statement.

This runtime limit does not create a non-recursive language profile. A compiler accepts recursive call graphs subject to its ordinary compile-time capacities; active depth is a runtime property.

## 13.10 Cleanup and lowering boundary

Baton routines have no destructors, `finally`, `defer`, exception unwinding, variable-sized local allocation, or other source-level scope-exit action. A `return` therefore performs no hidden source cleanup before transferring control.

The source semantics permit an all-caller-save implementation. A backend may save live implementation values before a call, place arguments, invoke the callee, capture a result before restoring overlapping state, and restore the caller afterward. Recursive calls may use the same rule for each activation. These operations are backend mechanics, not source-visible registers, clobber declarations, or parameter modes.

The compiler may lower calls and returns to regular semantic operations while parsing. This specification does not define register assignments, save regions, hardware-stack use, helper entry points, or the physical calling convention. The Z80 runtime and backend contract supplies the required target-level effects.

## 13.11 Invalid calls and capacity limits

The compiler must diagnose an unavailable or non-routine callee, a missing argument list, wrong arity, an incompatible scalar argument or result, an aggregate argument or result with the wrong referent type, a result-free call used as a value, the wrong `return` form, a value routine whose end is reachable, an abbreviated body without one incomplete forward, and a duplicate or missing forward completion.

An implementation may bound parameters, arguments, active expression-call nesting, retained signatures, fallthrough-summary depth, and compile-time call-graph metadata. It must publish each limit and issue a capacity diagnostic before dropping an argument, corrupting a signature, losing a result, merging live state, or changing a call target. Runtime activation capacity follows Section 13.9 rather than this compile-time capacity rule.

## 13.12 Examples

A result-free routine and a value routine use the same declaration family:

```nucleus
sub display(value as u8)
    return
end

sub maximum(left as u16, right as u16) as u16
    if left >= right
        return left
    else
        return right
    end
end
```

Both paths through `maximum` return a compatible value. The result may be used directly:

```nucleus
largest = maximum(first, second)
```

An aggregate result preserves alias identity:

```nucleus
sub entryAt(index as u8) as Entry
    return entries[index]
end

sub update(items as Entry[8], index as u8)
    items[index].value = entryAt(index).value
end
```

`entryAt` returns an alias to program-lifetime storage. The call itself copies no `Entry`; an aggregate assignment using that result copies into its destination.

To retain the complete returned value, the caller provides destination storage:

```nucleus
sub retain(index as u8, destination as Entry)
    destination = entryAt(index)
end
```

`destination` remains bound to the caller's object. The assignment materializes the transient result without declaring an aggregate local.

Direct and mutual recursion use ordinary signatures:

```nucleus
forward sub odd(value as u16) as boolean

sub even(value as u16) as boolean
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

```nucleus
sub missing(value as u8) as u8
    if value = 0
        return 1
    end
end                              // value path reaches end

sub procedure()
    return 1                     // result-free routine
end

sub value() as u8
    return                       // value routine requires an expression
end
```
