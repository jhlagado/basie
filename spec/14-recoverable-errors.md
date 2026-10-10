# 14. Recoverable errors


## 14.1 Two failure classes

A **recoverable error** is an expected unsuccessful result that source code may propagate or handle. A **trap** is a non-recoverable safety failure defined by Chapter 15. Error handling does not intercept, convert, or resume after a trap.

Basie represents a recoverable error with a code carried beside a routine's ordinary success result. The code is a member of the routine's **failure enum** (design decision D54), a plain enum (Chapter 6, Section 6.16) that the routine names after `fails`. The services fail with the predeclared enum `IoError` (Chapter 16); the standard library's number parsing fails with `ParseError`; a program declares enums of its own. Each enum is its own domain: a code passes on only to a routine of the same enum (Section 14.5), so codes from different sources can't be confused.

## 14.2 Failable signatures

A routine that can return a recoverable error writes `fails` and the name of its failure enum at the end of its header:

```text
routine-header ::= "sub" NAME "(" [ formal-parameter
                   { "," formal-parameter } ] ")"
                   [ result-clause ] [ "fails" NAME ]
result-clause  ::= ":" [ "var" ] type [ "from" NAME { "," NAME } ]
```

`fails` is part of the routine signature. A forward declaration records it once; the later abbreviated body header cannot repeat it. An ordinary routine without a forward includes it in its complete header. The clause does not change the declared parameters or optional success-result type.

Absent a trap, a failable invocation completes in exactly one of two ways:

- **success**, with the ordinary scalar value, aggregate alias, or no result declared by the header; or
- **failure**, with one code, a member of its failure enum, and no success result.

An infallible routine has only successful completion. It cannot use `fail` or propagate a callee's failure.

## 14.3 Producing failure

The statement

```text
fail-statement ::= "fail" expression
```

ends the current failable routine with failure. The expression is evaluated once and must be a value of the routine's failure enum, a qualified member or a variable of that enum; anything else is `type-mismatch`, at the expression. The activation ends after the code is obtained. No later statement in that routine executes.

`fail` in an infallible routine is invalid. A trap while evaluating the code remains a trap and does not become a recoverable error.

A routine's codes are its enum's members:

```basie
enum DigitError
    badDigit
    tooLarge
end

sub parseDigit(value: u8): u8 fails DigitError
    if value < '0' or value > '9'
        fail DigitError.badDigit
    end
    return value - '0'
end
```

## 14.4 Required consumption

Every call of a failable routine must consume failure at that call site. Basie provides exactly two forms:

1. `try` before the call propagates the code from the current failable routine (design decision D48).
2. Immediate `handle NAME ... end` after the call handles the code locally.

A failable invocation cannot appear inside an argument, arithmetic operation, comparison, condition, index, general conversion, or other larger expression. It may be only:

- the complete expression initializer of a local declaration, of any type, after `try`;
- the complete right side of an assignment, after `try` or followed by `handle`;
- the complete routine-call statement, after `try` or followed by `handle`.

Local declarations admit propagation but not handling. `return` admits no failable invocation: it represents success only. An unconsumed failable invocation, two consumers on one invocation, or a failable invocation in any other position is invalid. Program-variable and constant initializers cannot call routines under Chapter 8 and therefore cannot be failable.

## 14.5 Propagation

The propagation prefix is `try`, written directly before the routine's name:

```text
try-call ::= "try" NAME "(" [ arguments ] ")"
```

`try` must be followed by the name of a routine or service, which is called; anything else is a syntax error at the token after `try`. The call must end its statement: a token after its `)` other than the line's end is a syntax error there, so `try` never propagates from inside a larger expression, an argument, or another `try`, and `return try` is invalid. `try` before a routine that cannot fail is `not-failable`, at `try`.

On success, the surrounding declaration or assignment uses the callee's ordinary result, or the call statement continues. On failure, `try` immediately returns the same code from the enclosing routine, leaving every block as `fail` does, so its owning locals and parameters are freed (Section 7.12). The enclosing routine must declare `fails` with the callee's failure enum: `try` before a call of another enum is `failure-domain`, at the call. A failure crosses from one enum to another only explicitly, by `handle` and a `fail` of the other enum.

```basie
sub loadByte(): u8 fails IoError
    var value: u8 = try readInputByte()
    return value
end
```

Propagation is explicit at every intermediate call. Basie has no implicit propagation, error-set inclusion, implicit code remapping, handler stack, or unwinding.

## 14.6 Local handling

`handle NAME` occurs on the same logical line as the assignment or routine-call statement whose direct failable invocation it handles:

```text
failure-handler ::= "handle" NAME NEWLINE
                    statement-sequence "end" NEWLINE
```

The name must resolve to an existing writable variable, parameter or local whose type is the handled call's failure enum (`handle-destination` otherwise). A local serving as an active counted-loop counter is read-only and cannot be the error destination. The clause declares no binding. The handler body is a block with its own scope (Chapter 5).

On success, the call supplies its ordinary result, the assignment occurs when present, and the handler body is skipped. On failure, no success-result store occurs, then the compiler stores the error code in the named destination and executes the handler body. This ordering also applies when the assignment destination and error destination are the same variable: the variable receives the error code. Normal completion of the body continues after its closing `end`. A `return`, `fail`, `exit`, or `continue` inside the body has its ordinary enclosing context.

```basie
sub copyOne()
    var code: IoError
    var value: u8

    value = readInputByte() handle code
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

`try` can exit on failure and continue on success, so it does not by itself make following source unreachable. A `handle` body can complete normally unless it has a non-fallthrough statement on every path.

The fixed `main` routine may declare `fails`. A failure returned from `main` has no source caller and performs the unhandled-error trap in Chapter 15 with the returned code, reported as the member's ordinal, its position in its enum counting from zero. A successful return from `main` terminates normally.

### 14.7.1 Failure and owning values

`fail` leaves the routine like `return`: every block is left and its owning locals and parameters are freed (Chapter 13, Section 13.10). The failure code is evaluated before anything is freed. A routine whose result is an owning handle returns no handle when it fails, so nothing is transferred. When a call fails, a fresh owning argument already bound to the callee's parameter belongs to the callee and has been freed by it; a moved argument is not restored.

## 14.8 Lowering boundary

The source semantics require a success/failure discriminant and a code, the member's ordinal as a byte, for each failable result. The [code generation contract](../docs/code-generation.md) defines their required target behavior while leaving the carrier choice private. Carry plus a byte register is one possible calling convention, not source semantics.

Failure propagation is an ordinary conditional return. Local handling is an ordinary conditional branch. Basie has no exception object, stack walk, cleanup action, hidden handler registration, or resumable failure state. The all-caller-save-compatible call semantics in Chapter 13 apply to both outcomes.

## 14.9 Invalid forms and capacities

The compiler must diagnose:

- `fail` or `try` in an infallible routine;
- a `fails` clause that does not name an enum, or a failure code that is not a value of the routine's failure enum;
- `try` before a call whose failure enum is not the enclosing routine's (`failure-domain`);
- a failable invocation in a nested expression or unsupported context;
- a failable invocation with no consumer or more than one consumer;
- `handle` attached to an ineligible statement;
- a propagating `return` form;
- an error destination that is unavailable, non-writable, not of the call's failure enum, or an active counted-loop counter;
- a `fails` clause or other signature text repeated on an abbreviated forward body; and
- a result-bearing failable routine that can reach its end without success or failure.

An implementation may bound retained failable signatures, nested handlers, failure fixups, and active error destinations. It must publish each limit and issue a capacity diagnostic before exhaustion can discard a check, route a code to the wrong caller, or execute the wrong handler.
