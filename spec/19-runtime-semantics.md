# 19. Runtime semantics

This chapter summarizes execution. The chapters cited are normative.

## 19.1 Startup

The runtime's startup (Chapter 16, Section 16.5; [CP/M target](../docs/cpm-target.md), Section 4) checks that memory covers the program's stack reserve, establishes the static image of program variables and constants, leaves every pool slot free, and calls `main`.

## 19.2 Evaluation

Expressions are evaluated left to right with short-circuit `and` and `or` (Chapter 9, Section 9.14). Integer arithmetic wraps; `f32` arithmetic rounds to nearest, ties to even, with flush to zero. Conversions that do not fit, out-of-range indexes, division by zero and `f32` overflow trap. Assignments follow the orders of Chapter 10, Section 10.4.

## 19.3 Storage and lifetime

Program storage lives for the run. A local lives from its declaration to the end of its block, and a local in a loop body is created on each iteration. Pool slots live from `new` until their owner goes away. Freeing is automatic and cascades through owned slots without recursion. Accesses through identifiers are checked against generations; stores of owning handles into pool records are checked for cycles (Chapter 7).

## 19.4 Calls

Arguments are evaluated and bound left to right; ownership passes to owning parameters; record arguments held by owners are leased. Forward-declared routines check activation capacity on entry. Leaving a routine by any path frees its owning locals and parameters, after evaluating any result (Chapter 13).

## 19.5 Failure and termination

A recoverable failure is a `u8` code returned beside the result and consumed explicitly (Chapter 14). A trap ends the program at once with a report naming the reason and the site's address (Chapter 15). A normal return from `main` ends the program successfully; a failure from `main` is reported as an unhandled error. On CP/M 3, return codes distinguish the cases.
