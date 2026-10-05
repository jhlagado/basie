# 18. Static semantics

This chapter summarizes the compile-time rules. The chapters cited are normative; where this summary and a cited chapter differ, the cited chapter governs.

## 18.1 Compilation order

The compiler reads the source parts in stream order (Chapter 4): each part's `include`s first, depth first, once each. Every use needs an earlier visible declaration, except that a forward declaration makes a routine or pool usable before its completion. A call to a routine whose body is not complete, including a call to itself, needs a forward declaration. At the end of the compilation, every forward is completed and exactly one `main` exists.

## 18.2 Names and scopes

Identifiers are case-sensitive. Scopes are the program, each part (`private`), each routine, each block and each record's fields (Chapter 5). There is no shadowing at any level; blocks that do not enclose each other may reuse a name. A name is resolved, then its declaration class is checked for its position. Predeclared services, `File`, `console`, `printer` and failure codes are visible from the start (Chapter 16).

## 18.3 Types

Every expression and declaration has one static type (Chapter 6). Records and pools are nominal. Implicit widening is admitted only where no value can be lost; every other numeric conversion is explicit and checked. Mixed operands use the wider type when one widens to the other, and are otherwise invalid. Exact integers adopt the type their context or the other operand supplies, and must fit it. An inferred local needs an initializer with a definite type (Chapters 8 and 9).

## 18.4 Storage, aliases and ownership

- Aliases exist only as parameters and as results consumed within a statement; a returned alias is rooted in program storage or a `from` parameter, never in a local (Chapter 7, Section 7.7; Chapter 13).
- Parameters without `var` are read-only, except scalar and handle parameters, which are local copies (Chapter 13).
- Owning handles and objects of owning type are never copied: ownership passes by a fresh value or `move` (Chapter 7, Section 7.11).
- Optional handles are reached only through `select` (Chapter 11).
- Fields, array elements and program variables of handle type are optional; non-optional handle locals have initializers (Chapter 8).
- Leases and slot-holders follow Chapter 7, Section 7.14.
- The statement rule and the flow check apply to every owning local and parameter (Chapter 10, Section 10.8; Chapters 11 and 12).

## 18.5 Constants and initialization

Constant expressions are evaluated exactly as at run time; an operation that would trap is an error (Chapter 8, Section 8.6). Bounds and capacities are constants in their ranges. Static initializers are complete and type-directed. Every object is initialized before it can be read.

## 18.6 Routines and failure

Calls match their signatures in arity, order, type and parameter kind. Every failing call has exactly one consumer: `else fail` in a failing routine, or `handle` (Chapter 14). A value routine's end must be unreachable without `return` (Chapter 13, Section 13.7).

## 18.7 Control

Conditions are `boolean`. `select` labels are constants of the subject's type with no overlap (Chapter 11). A counted-loop counter is an integer local declared before the loop and read-only within it (Chapter 12). `exit` and `continue` need an enclosing loop.

## 18.8 Invalid source and capacities

Any violation of these rules makes the source invalid; the compiler reports a diagnostic and produces no program. An implementation may bound its capacities, publishes every limit ([limits register](../docs/limits.md)), and diagnoses an excess without changing meaning. Its limits must compile every accepted program of the conformance suite.
