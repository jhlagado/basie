# Baton feature inventory

- Status: working record
- Date: 2026-10-04
- Related: [design decisions](design-decisions.md) (D9 budget, D24 scope),
  [memory safety](memory-safety.md), [build pipeline](build-pipeline.md)

## 1. Purpose

This document lists every feature of Baton, what each costs, and which version
it belongs to. It is the ledger the compiler budget is kept against.

All sizes are **estimates** until measured. They are anchored to one measured
figure: the Nucleus compiler core, covering the Nucleus 0.1 language, is about
15K, and its rewrite aims at 12K.

Two kinds of cost matter:

- **Compiler cost** is paid by every user, in the size of `BATON.COM`, and comes
  out of the compiler's own working space, which limits how large a program it
  can compile.
- **Runtime cost** is paid only by programs that use the feature, because the
  linker removes unused runtime helpers.

## 2. The budget

`BATON.COM` is at most **24K**, including its tables, leaving at least **32K**
of working space (D9). The linker is a separate program, `BLINK.COM`, so its
code doesn't count against this.

The compiler is kept within budget by:

1. building on the 12K Nucleus compiler rewrite;
2. generating 32-bit and `f32` operations as calls to runtime helpers, so the
   compiler only checks types and selects helpers;
3. keeping diagnostic text in `BATON.MSG`, read only when needed;
4. keeping rarely used parts, starting with decimal-to-`f32` literal
   conversion, in `BATON.OVL`;
5. writing strings, formatting and other library facilities in Baton source;
   and
6. deferring features to version 2 when they don't fit.

## 3. Version 1

| Feature | Compiler | Runtime, if used | Notes |
| --- | --- | --- | --- |
| Nucleus core: declarations, records, arrays, bounded strings, `if`, `while`, `for`, routines, `fails`, traps | 12–14K | multiply, divide, bounds, copy, trap reporters | built on the rewrite |
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
| Pools, handles, `move`, automatic freeing, flow check | 2.5K | 0.4–0.7K | memory safety |
| Stack bound and checks | 0.2K | 0.1K | memory safety §7 |
| Services for I/O | 0.2K for the service table | per service used | [I/O and effects](io-and-effects.md) |
| Blob output for the linker | about neutral against Nucleus's output | — | build pipeline |
| Branch shrinking | 0.3K | — | build pipeline §6.3 |
| **Total** | **about 21–23K** | | within 24K, with little room to spare |

The standard library, written in Baton and tree-shaken, provides string
building, comparison and searching, conversion between numbers and text
(including `f32`), and the console and file conveniences built on the services.

## 4. Version 2

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

```nucleus
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

## 6. Enumerations and variants, in version 2

Rust's `match` is powerful because of variants whose cases carry data,
destructuring, and exhaustiveness. Baton's version 2 takes the first and third
with one level of destructuring, leaving out nested patterns and guards:

```nucleus
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
