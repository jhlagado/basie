# Basie feature inventory

- Status: current 0.1 completion feature list fixed; historical costs retained
- Date: 2026-10-04
- Related: [design decisions](design-decisions.md) (D9 budget, D24 scope),
  [memory safety](memory-safety.md), [build pipeline](build-pipeline.md)

## 1. Purpose

This document lists every feature of Basie, its estimated costs and its
current disposition. It is the ledger the compiler budget is kept against.

All sizes are **estimates** until measured. They are anchored to one measured
figure: a compiler core for the base language (the first row of Section 3) is
about 15K; 12K is the aim for a compact one.

Two kinds of cost matter:

- **Compiler cost** is paid by every user, in the size of `BASIE.COM`, and comes
  out of the compiler's own working space, which limits how large a program it
  can compile.
- **Runtime cost** is paid only by programs that use the feature, because the
  linker removes unused runtime helpers.

## 2. The budget

`BASIE.COM` has a target of **26K** and a limit of **28K** (D43), including its tables, leaving at least **28K**
of working space (D9). The linker is a separate program, `BLINK.COM`, so its
code doesn't count against this.

The compiler is kept within budget by:

1. keeping the core of the base language to 12–15K;
2. generating 32-bit and `f32` operations as calls to runtime helpers, so the
   compiler only checks types and selects helpers;
3. keeping diagnostic text in `BASIE.MSG`, read only when needed;
4. keeping rarely used parts, starting with decimal-to-`f32` literal
   conversion, in `BASIE.OVL`;
5. writing strings, formatting and other library facilities in Basie source;
   and
6. deferring features that do not fit, without assigning them a release number.

## 3. Version 1

This historical heading names the current 0.1 completion scope, not a delivered
1.0 release. The table retains the original estimates.

| Feature | Compiler | Runtime, if used | Notes |
| --- | --- | --- | --- |
| Base language: declarations, records, arrays, bounded strings, `if`, `while`, `for`, routines, `fails`, traps | 12–15K | multiply, divide, bounds, copy, trap reporters | measured at about 15K |
| Signed `i8`, `i16` | 0.5K | 0.1–0.2K | D3 |
| Shifts and bitwise operators | 0.3K | 0.1K | |
| `u32`, `i32`, through helpers | 0.8K | 0.4–0.7K | D3, D9 |
| `f32`, through helpers; literal conversion in an overlay | 1K | 1–1.5K arithmetic; formatting and parsing in the library | D7 |
| `select` on integers, characters and optional handles | 0.6K | — | D15 |
| Arrays of arrays | 0.3K | — | D32 |
| `private` and `include` | 0.5K | — | D33 |
| Run-time `assert` | 0.1K | 0.05K | D34 |
| Local aggregates and `from` | 1K | — | D8 |
| `var` parameters | 0.2K | — | D17, D30 |
| Declarations anywhere, block scope | 0.2K | — | D28 |
| Typed and local constants; inference from typed initialisers | 0.2K | — | D20, D21 |
| Pools, handles, `forward pool`, `move`, automatic freeing, flow check | 2.5K | 0.4–0.7K | memory safety |
| Stack bound and checks | 0.2K | 0.1K | memory safety §7 |
| Services for I/O | 0.7K for the services' signatures | per service used | [services](services.md) |
| Blob output for the linker | about neutral against output placed at final addresses, which it replaces | — | build pipeline |
| CP/M shell: command line, buffered files, library check, compilation stamp, chain loader | 2.3K, about 1.3K of it in overlays | — | [native compiler](native-compiler.md) §4 |
| Branch shrinking | 0.3K | — | build pipeline §6.3 |
| **Total** | **about 25.5–27.5K** on a 15K core (22.5–24.5K on a 12K one), with the shell's one-shot parts in overlays | | at or just over the 26K target: compression passes and early removal of machinery Basie does not use are planned from the start (D43, [native compiler](native-compiler.md) §4) |

The standard library, written in Basie and tree-shaken, provides string
building, comparison and searching, conversion between numbers and text
(including `f32`), and the console and file conveniences built on the services.

**Feature selection frozen.** This list is the current 0.1 completion scope.
Earlier entries call it version one; that label is historical.
The specification remains a working draft; this is not a formal specification
freeze. Adding a feature to current completion requires a new design decision
that says what it displaces or which measured saving pays for it. Otherwise it
remains a future candidate, subject to the forward plan. The
standard library (D36), the message file (D39) and the link-time file table
(D38) add nothing to the compiler's language cost.

## 4. Historical extension estimates

These estimates retain the original version-two inventory. That earlier label
has been replaced by the next development milestone, without an assigned release
number. The table also contains deferred and rejected items outside that scope. The
[forward plan](version-2.md) governs nomination and admission. The plain enum
estimate in the [catalogue](stretch-goals.md) is separate from the combined
enum-and-variant row below. The catalogue gathers all proposals under review
and records deferrals and rejections.
A row here does not schedule a feature or authorise its estimated cost. Full
typed noncapturing routine values are provisionally accepted for the next milestone under the
catalogue's whole-feature prototype and explicit back-out gate; the O5 estimate
below remains unmeasured.

| Feature | Compiler | Notes |
| --- | --- | --- |
| Enumerations, and variants whose cases carry data, in `select` | 1.7–2.7K | D15, D24; rules in memory safety §11 |
| Failure codes named by an enumeration (`fails FileError`) | 0.1K | D26 |
| Expression blocks with `result`; `select` as an expression | 0.5K | O3 |
| Routine values | 0.5–1K | O5 |
| Arenas | 0.5–1K | O4 |
| Default parameter values | 0.3–0.5K | O6 |
| Generics | 1–2K | D23 |
| `repeat` and a general `loop` | 0.2K | convenience |
| Precompiled libraries | 1–2K | build pipeline §9.3 |

## 5. `select`

```basie
select key
case 'q', 'Q'
    exit
case '0' to '9'
    digit(key - '0')
case else
    beep()
end
```

- The subject is an integer, a character, a `boolean`, or an optional handle or
  identifier.
- Each `case` lists constants or constant ranges (`to`); values may not repeat.
- `case else` covers everything else and comes last.
- There is no fall-through.
- Over an optional handle, the cases are `some(x)` and `none`
  ([memory safety](memory-safety.md), Section 5.5).

**Code.** The compiler emits the case bodies first, with a jump around them, and
the dispatch code after the last case, when every value is known. It then chooses
between a compare chain for sparse values (4 to 6 bytes per value) and a jump
table for dense ranges (a bounds check and an indexed jump, then 2 bytes per
value). The dispatch jumps backwards into the bodies, so case labels need no
forward references.

**Cost.** About 0.6K of compiler, nothing at run time. It
replaces long `elseif` chains, which are larger and slower.

## 6. Earlier enumeration and variant sketch

Plain enums and typed failure codes are now accepted next-milestone directions, with enums
first and separate measured budgets required. Payload variants remain
indefinitely deferred. The [forward plan](version-2.md)
supersedes the schedule implied by this earlier sketch.

Rust's `match` is powerful because of variants whose cases carry data,
destructuring and exhaustiveness. The earlier Basie sketch proposed the first
and third with one level of destructuring, leaving out nested patterns and guards:

```basie
variant Shape
    circle(radius as u16)
    rect(width as u16, height as u16)
    empty
end

select s
case circle(r)
    area = 3 * u32(r) * u32(r)
case rect(w, h)
    area = u32(w) * u32(h)
case empty
    area = 0
end
```

A variant is stored as a tag byte followed by the largest case's fields.
Declarations precede use, so a single pass can check exhaustiveness. Variants
with owning payloads need the binding, construction and overwrite rules recorded
in memory safety §11.

## 7. Open questions

1. Which compiler parts, beyond `f32` literal conversion, go into overlays,
   decided by measurement.
2. The standard library's contents and the service set
   ([I/O and effects](io-and-effects.md)).
