# 14. Recoverable errors


## 14.1 Two failure classes

A **recoverable error** is an expected unsuccessful result that source code may propagate or handle. A **trap** is a non-recoverable safety failure defined by Chapter 15. Error handling does not intercept, convert, or resume after a trap.

Basiq represents a recoverable error with a `u8` code carried beside a routine's ordinary success result. The code has no separate error-set type. Programs give codes names with constants (design decision D26). The code space is shared by every routine and divided as follows ([services](../docs/services.md), Section 9):

| Codes | Use |
| --- | --- |
| 1–31 | Services; 1 to 18 are defined, the rest reserved (Chapter 16) |
| 32–47 | The standard library |
| 48–253 | Programs |
| 0, 254, 255 | Reserved; 254 is `invalid` |

The compiler does not enforce the ranges; they are a convention that keeps codes from different sources distinct. Enumerations of failure codes, checked at `fail` and `handle`, are planned for version 2.

## 14.2 Failable signatures

A routine that can return a recoverable error writes `fails` at the end of its header:

```text
routine-header ::= "sub" NAME "(" [ formal-parameter
                   { "," formal-parameter } ] ")"
                   [ "as" type ] [ "fails" ]
```

`fails` is part of the routine signature. A forward declaration records it once; the later abbreviated body header cannot repeat it. An ordinary routine without a forward includes it in its complete header. The clause does not change the declared parameters or optional success-result type.

Absent a trap, a failable invocation completes in exactly one of two ways:

- **success**, with the ordinary scalar value, aggregate alias, or no result declared by the header; or
- **failure**, with one `u8` error code and no success result.

An infallible routine has only successful completion. It cannot use `fail` or propagate a callee's failure.

## 14.3 Producing failure

The statement

```text
fail-statement ::= "fail" expression
```

ends the current failable routine with failure. The expression is evaluated once and must be compatible with `u8`; an exact literal must fit, and `u16` requires explicit checked narrowing. The activation ends after the code is obtained. No later statement in that routine executes.

`fail` in an infallible routine is invalid. A trap while evaluating the code remains a trap and does not become a recoverable error.

Named codes are ordinary constants:

```nucleus
const badDigit = 1
const tooLarge = 2

sub parseDigit(value as u8) as u8 fails
    if value < '0' or value > '9'
        fail badDigit
    end
    return value - '0'
end
```

## 14.4 Required consumption

Every call of a failable routine must consume failure at that call site. Basiq provides exactly two forms:

1. `else fail` propagates the code from the current failable routine.
2. Immediate `handle NAME ... end` handles the code locally.

A failable invocation cannot appear inside an argument, arithmetic operation, comparison, condition, index, general conversion, or other larger expression. It may be only:

- the complete initializer of a scalar local declaration, followed by `else fail`;
- the complete right side of an assignment, followed by `else fail` or `handle`;
- the complete routine-call statement, followed by `else fail` or `handle`.

Local declarations admit propagation but not handling. `return` admits no failable invocation: it represents success only. An unconsumed failable invocation, two consumers on one invocation, or a failable invocation in any other position is invalid. Program-variable and constant initializers cannot call routines under Chapter 8 and therefore cannot be failable.

## 14.5 Propagation

The propagation suffix is:

```text
failure-propagation ::= "else" "fail"
```

On success, the surrounding declaration or assignment uses the callee's ordinary result, or the call statement continues. On failure, `else fail` immediately returns the same `u8` code from the enclosing routine. The enclosing routine must declare `fails`.

```nucleus
sub loadByte() as u8 fails
    var value as u8 = readStorageByte() else fail
    return value
end
```

Propagation is explicit at every intermediate call. Basiq has no implicit propagation, error-set inclusion, code remapping, handler stack, or unwinding.

## 14.6 Local handling

`handle NAME` occurs on the same logical line as the assignment or routine-call statement whose direct failable invocation it handles:

```text
failure-handler ::= "handle" NAME NEWLINE
                    statement-sequence "end" NEWLINE
```

The name must resolve to an existing writable `u8` variable, parameter or local. A local serving as an active counted-loop counter is read-only and cannot be the error destination. The clause declares no binding. The handler body is a block with its own scope (Chapter 5).

On success, the call supplies its ordinary result, the assignment occurs when present, and the handler body is skipped. On failure, no success-result store occurs, then the compiler stores the error code in the named `u8` destination and executes the handler body. This ordering also applies when the assignment destination and error destination are the same variable: the variable receives the error code. Normal completion of the body continues after its closing `end`. A `return`, `fail`, `exit`, or `continue` inside the body has its ordinary enclosing context.

```nucleus
sub copyOne()
    var code as u8
    var value as u8

    value = readStorageByte() handle code
        return
    end

    writeOutputByte(value) handle code
        return
    end
end
```

The handled call must be the complete right side of the assignment or the complete call statement. The handler begins after that line's `NEWLINE`; attachment state never survives the newline. A handler cannot attach to a local declaration, `return`, compound statement, infallible call, propagated call, or another statement.

## 14.7 Results, flow, and entry failure

Ordinary `return` denotes successful completion only. A result-free failable routine may use bare `return` or reach its closing `end`. A result-bearing failable routine must return a compatible success result or fail on every path under the fallthrough rules in Section 13.7, extended so `fail` does not fall through. A caller that needs to propagate a failable result does so in a preceding local initializer, assignment, or call statement, then returns only the successful result.

`else fail` can exit on failure and continue on success, so it does not by itself make following source unreachable. A `handle` body can complete normally unless it has a non-fallthrough statement on every path.

The fixed `main` routine may declare `fails`. A failure returned from `main` has no source caller and performs the unhandled-error trap in Chapter 15 with the returned code. A successful return from `main` terminates normally.

### 14.7.1 Failure and owning values

`fail` leaves the routine like `return`: every block is left and its owning locals and parameters are freed (Chapter 13, Section 13.10). The failure code is evaluated before anything is freed. A routine whose result is an owning handle returns no handle when it fails, so nothing is transferred. When a call fails, a fresh owning argument already bound to the callee's parameter belongs to the callee and has been freed by it; a moved argument is not restored.

## 14.8 Lowering boundary

The source semantics require a success/failure discriminant and a `u8` code for each failable result. The Z80 runtime and backend contract defines their required target behavior while leaving the carrier choice private. Carry plus a byte register is one possible calling convention, not source semantics.

Failure propagation is an ordinary conditional return. Local handling is an ordinary conditional branch. Basiq has no exception object, stack walk, cleanup action, hidden handler registration, or resumable failure state. The all-caller-save-compatible call semantics in Chapter 13 apply to both outcomes.

## 14.9 Invalid forms and capacities

The compiler must diagnose:

- `fail` or `else fail` in an infallible routine;
- a failure code incompatible with `u8`;
- a failable invocation in a nested expression or unsupported context;
- a failable invocation with no consumer or more than one consumer;
- `handle` attached to an ineligible statement;
- a propagating `return` form;
- an error destination that is unavailable, non-writable, not `u8`, or an active counted-loop counter;
- a `fails` clause or other signature text repeated on an abbreviated forward body; and
- a result-bearing failable routine that can reach its end without success or failure.

An implementation may bound retained failable signatures, nested handlers, failure fixups, and active error destinations. It must publish each limit and issue a capacity diagnostic before exhaustion can discard a check, route a code to the wrong caller, or execute the wrong handler.
