# Basie code generation contract

- Status: draft 1 (2026-10-04), adopted for the reference compiler; the native
  compiler and the runtime's helper table follow it (design decision D41)
- Related: [memory safety](memory-safety.md) §7, [CP/M target](cpm-target.md)
  §10, [build pipeline](build-pipeline.md) §6, [services](services.md),
  [capacity audit](capacity-audit.md)

This document fixes what compiled code and the runtime library must agree on:
value representations, the frame, the calling convention, results and
failure, and how the stack bound is carried. It does not fix instruction
selection; two compilers may emit different code for the same statement as
long as every routine, helper and service meets this contract at its edges.

## 1. Representations

| Type | Bytes | In storage | In registers |
| --- | ---: | --- | --- |
| `u8`, `i8`, `boolean` | 1 | the byte; `boolean` is 0 or 1 | `A` |
| `u16`, `i16` | 2 | little-endian | `HL` |
| `u32`, `i32` | 4 | little-endian | `DEHL` (`DE` high) |
| `f32` | 4 | IEEE single, little-endian | `DEHL` |
| owning handle `P`, `P?` | 2 | slot address; `none` is 0 | `HL` |
| identifier `id P`, `id P?` | 4 | address, then generation; `none` is address 0 | `DEHL` (`DE` generation) |
| `File` | 4 | table-entry address, then generation | `DEHL` |
| record | sum of fields | packed, declaration order, no padding | by address in `HL` |
| `T[N]` | N × element | consecutive | by address |
| `string[N]` | N + 2 | length byte, N bytes, a permanent zero byte | by address of the length byte |

Pool slots carry a 4-byte header (generation, owner link) **before** the
record ([memory safety](memory-safety.md) §5.1); a handle addresses the
record, so the header is at `handle − 4`.

Signed arithmetic is two's complement at the stored width. Values held in a
wider register than their type keep their meaning only in the low bytes.

## 2. Registers

| Register | Use |
| --- | --- |
| `SP` | the hardware stack; frames live on it |
| `IX` | frame pointer of the current routine; callee-saved |
| `IY` | the argument size on entry to `RETN`; otherwise reserved for runtime helpers, and compiled code never relies on it |
| `A`, `BC`, `DE`, `HL`, `AF'`, `BC'`, `DE'`, `HL'` | scratch; destroyed by any call |

Nothing but `IX` and `SP` survives a call. Interrupts are not handled by
Basie code (CP/M target §8).

## 3. Frames and the calling convention

A call pushes its arguments **left to right**, so the last argument is nearest
the return address, then executes `CALL`. The callee's prologue is:

```text
PUSH IX
LD   IX,0
ADD  IX,SP          ; IX → saved IX; IX+2 → return address; IX+4 → last argument
```

followed, when the routine has locals, by a stack adjustment of the frame
size. The frame holds the routine's locals and temporaries at negative offsets
from `IX`, and its parameters at positive ones. Because the frame is on the
stack, every activation is distinct and recursion needs nothing more.

**Parameter sizes on the stack.** Each parameter occupies a whole number of
words:

| Parameter | Words | Contents |
| --- | ---: | --- |
| `u8`, `i8`, `boolean` | 1 | the byte in the low half; the high byte is 0 |
| `u16`, `i16`, 2-byte handles | 1 | the value |
| `u32`, `i32`, `f32`, identifiers, `File` | 2 | high word pushed first, so the low word sits at the lower address and the value is little-endian in memory |
| aggregate alias (record, `T[N]`, `string[N]`) | 1 | the address |
| open view `string[]`, `T[]` | 2 | capacity or length word, then the address nearest the return address |
| `var` record parameter, `var` parameter of an owning type, or a slot-holder `var h as P?` | +1 | the owner word, pushed before the address |

**Returning.** The callee removes its own arguments. Its epilogue is:

```text
LD   SP,IX
POP  IX
POP  DE             ; return address
<drop n argument bytes>
PUSH DE
RET
```

which the runtime provides as a shared helper, `RETN`, entered with the result
registers and flags intact and the argument size in `IY`, so each routine's
epilogue is `LD IY,n` / `JP RETN` (7 bytes), or `LD SP,IX` / `POP IX` / `RET`
when `n` is 0. `RETN` uses only the alternate registers and `IY`, so it
preserves `A`, `HL`, `DE` and the carry flag. All exits from a routine share
one epilogue; owning locals are freed before it ([memory
safety](memory-safety.md) §5.3).

**Results** are returned in the registers of Section 1: `A`, `HL` or `DEHL`.
An aggregate result is its address in `HL`. A `var` result is the same address;
the `var` marker is compile-time only.

**Failure.** A routine declared `fails` returns with the carry flag **set** and
the code in `A` on failure, and the carry **clear** on success, with the result
in its registers. `RETN` preserves the carry and `A`. A routine not declared
`fails` leaves the carry undefined, except `main`, which always returns with
the carry clear on success, because startup cannot know whether `main` was
declared `fails` and reports `FAIL` with the code in `A` when it returns with
the carry set.

## 4. Expression evaluation

Expressions are evaluated left to right into the result registers of Section
1. A binary operation evaluates its left operand, pushes it (one or two words),
evaluates its right operand, pops the left into `DE` (or `BC:DE` for 4 bytes)
and operates. This is the Nucleus scheme; it needs no register allocation and
its stack use is bounded by the expression nesting, which is counted into the
frame.

8-bit operations run in `A` with `E` as the second operand; 16-bit in `HL` with
`DE`; 32-bit and `f32` operations are calls to runtime helpers taking the left
operand in `DEHL` and the right on the stack, or in `BC'DE'`-style alternate
registers, as the helper table states for each.

## 5. Storage addressing

| Storage | Addressed by |
| --- | --- |
| program variable, aggregate constant, pool | an `ABS16` reference to its blob, optionally with an addend for a field or constant index |
| local, parameter | `IX+d`, `d` from −128 to +127; a slot beyond that range is reached through a computed address (`PUSH IX; POP HL; LD DE,d; ADD HL,DE`), with the registers the access must keep saved around it and the pushes counted in the frame's stack figure |
| field of a record reached by address | the address plus a constant offset |
| element with a variable index | address + index × stride, computed in `HL`, with the bounds check first |
| pool record through a handle | the handle; through an identifier, after the generation check |

## 6. Traps

A trap site is a `CALL cc,reporter` (3 bytes) or `JR cc,skip` / `CALL reporter`
(5 bytes) as the [CP/M target](cpm-target.md) §10.2 requires. A helper that
detects a failure restores its entry `SP` and jumps to the reporter. Compiled
code never tail-calls a helper.

## 7. The stack bound

Every routine's blob ends with a 4-byte pair after its code: `frame(R)` and
`need(R)` ([memory safety](memory-safety.md) §7). A forward-declared routine
begins with `LD HL,(pair+2)` / `CALL STKCHK`: it loads `need(R)` through a
self-reference to the pair and calls the activation-capacity helper, which
traps if `SP − need(R) − guard < FREE`, reporting the `CALL` as the site, which
the line table maps to the routine's header. `need(main)` + the guard band is the `LIMITS`
record's stack reserve.

`frame(R)` counts locals, temporaries, hidden string copies and expression
pushes at their deepest point. `need(R)` adds the helpers' published stack
use and the largest `need` of the routines called.

## 8. Runtime helpers and services

Helpers and services are library blobs reached by `CALL` with this same
convention: arguments on the stack for services (they are ordinary Basie
signatures), and in registers for arithmetic helpers, as the helper table
states per helper. Each helper publishes its stack use in the
[helper table](helper-table.md): the figures are computed from the helper's
code by a static analysis and checked against stack use measured under the
corpus, never written by hand. The table's interface key
([object format](object-format.md) §10) covers each helper's ordinal, kind
and calling-convention code, so a change here changes the key. The compiler
carries the table, generated from the runtime source, and writes its key
into every program it compiles.

## 9. Why these choices

- **Stack frames, not an arena.** Nucleus's bounded activation arena fixed
  recursion depth at 8. Frames on the stack cost two instructions per call
  and make depth a property of memory, checked by the stack bound.
- **Callee removes arguments.** One shared epilogue per routine instead of a
  stack adjustment at every call site; `RETN` makes it 5 bytes per routine.
- **Carry for failure.** The cheapest test on a Z80 (`JR C`), and `A` is free
  for the code because a failing routine has no result on failure.
- **Left to right, last argument nearest the return address.** Arguments are
  evaluated in source order with no reordering buffer, and a parameter's
  `IX` offset depends only on the parameters after it, which the compiler
  knows when it finishes the header.
- **No callee-saved scratch registers.** Saves prologue bytes in every routine;
  the expression scheme keeps nothing live across a call except on the stack.
