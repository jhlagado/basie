# Baton feature inventory

- Status: draft for discussion
- Date: 2026-10-03
- Related: [design decisions](design-decisions.md), [memory safety](memory-safety.md),
  [build pipeline](build-pipeline.md)

## 1. Purpose

This document lists every feature a complete Baton needs, what each costs, and
what leaving it out would save. Its aim is a language that is **feature
complete**: everything a programmer reasonably expects of a systems language is
there. Where the budget is tight, it shows the order in which features would be
cut.

All sizes are **estimates**, to be replaced by measurement as features are
built. They are anchored to one measured figure: the Nucleus compiler core,
covering the Nucleus 0.1 language, is about 15K, with a rewrite aiming at 12K.

Two kinds of cost matter, and they are very different:

- **Compiler cost** is paid by every user, in the size of `BATON.COM`. The
  compiler's code competes with its own workspace: every kilobyte of compiler is
  a kilobyte less for symbol tables, which limits how large a program it can
  compile.
- **Runtime cost** is paid only by programs that use the feature, because the
  linker removes unused runtime helpers. A program that never touches `f32`
  carries none of the float library.

## 2. Inventory

### 2.1 The Nucleus core (kept)

| Feature | Compiler | Runtime | Notes |
| --- | --- | --- | --- |
| Lexer, declarations, scopes, forward routines | in the 15K | — | measured |
| `u8`, `u16`, `boolean`; arithmetic, comparison, logic | in the 15K | multiply, divide helpers | measured |
| Records, fixed arrays, bounded strings, constants | in the 15K | bounds checks, copy helpers | measured |
| `if`/`elseif`/`else`, `while`, counted `for`, `exit`, `continue` | in the 15K | — | measured |
| Routines, results, aggregate aliases | in the 15K | — | measured |
| `fails`, `else fail`, `handle`; traps | in the 15K | trap reporters | measured |

### 2.2 Essential additions

Without these, Baton is not a complete systems language.

| Feature | Compiler | Runtime, if used | Why essential |
| --- | --- | --- | --- |
| Signed `i8`, `i16` | 0.5–1K | 0.1–0.2K (signed divide, compare) | Displacements, deltas, coordinates; Nucleus's biggest gap |
| Shifts and bitwise operators on integers | 0.3–0.5K | 0.1K (variable shifts) | Device registers, flags, packing |
| `u32`, `i32` | 1–2K | 0.4–0.7K (multiply, divide, shifts, conversion) | File sizes, timers, products above 65,535 |
| `f32` | 1–1.5K, plus 0.5–1K to convert decimal literals | 1–1.5K arithmetic; 0.8–1.2K formatting and parsing | Measurement, graphics, games, science |
| `select` on integers and enums (Section 3) | 0.5–1K | — | Every menu, parser and state machine |
| Enumerations | 0.3–0.6K | — | Named states with checked exhaustiveness |
| Local aggregates and `from` (D8) | 0.8–1.5K | — | Temporary buffers without globals |
| Parameter modes (`var`) | 0.2K | — | Signatures say what a routine changes |
| Ownership: pools, `own`, `id`, `new`, `give`, flow check | 2–4K | 0.3–0.6K (allocation, retirement, generation checks) | The memory-safety claim |
| Stack checking | 0.2K | 0.1K | Part of the memory-safety claim |
| Port input and output (`in`, `out` built-ins) | 0.2K | — | Talking to hardware without unsafe code |
| Blob output for the linker | about neutral against NOBJ | — | Tree shaking |
| The linker phase | 5K, in the same executable but a separate phase | — | Tree shaking |

### 2.3 Important additions

A complete language has these, but a first release could ship without one or
two.

| Feature | Compiler | Runtime, if used | Notes |
| --- | --- | --- | --- |
| Variant records and pattern matching (Section 4) | 1.5–2.5K | — | Rust-style `match`, restricted to fit |
| Routine values (function pointers) | 0.5–1K | — | Callbacks, dispatch tables; needs a stack-bound rule |
| String building: append, truncate, slice | 0.4–0.8K | 0.2–0.4K | Nucleus strings can't change length |
| Source parts named in source (imports) | 0.3–0.6K | — | Instead of listing every part on the command line |
| Branch shrinking | 0.3–0.5K | — | About 1 byte per forward branch in every program |
| Expression blocks with `result` (O3) | 0.5K | — | Composition; also makes `select` usable as an expression |
| `repeat`/`until` and a general `loop` | 0.2K | — | Convenience; `while` covers both |

### 2.4 Later

| Feature | Compiler | Notes |
| --- | --- | --- |
| Arenas | 0.5–1K | Scope-bound dynamic storage |
| Interrupt routines | 0.5–1K | Needs a profile statement and register saving |
| Banked targets | 1–2K plus linker work | TEC banked ROM |
| Precompiled libraries | 1–2K | Names in the compiler, ordinals in the linker |

## 3. `select`

### 3.1 Form

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

- The subject is an integer, a `boolean` or an enumeration.
- Each `case` lists constants or constant ranges (`to`). Values may not repeat
  across cases.
- `case else` covers everything else and comes last.
- There is no fall-through: exactly one case runs.
- Over an enumeration, the cases must cover every value unless there is a
  `case else`. The compiler checks this.

### 3.2 Code

The compiler chooses between two shapes as it reads the cases:

- a **compare chain** for sparse values: about 4 to 6 bytes per value; and
- a **jump table** for dense ranges: a bounds check and an indexed jump, then 2
  bytes per value.

A single-pass compiler sees the cases before it must commit to a shape only if
it delays the dispatch code: it emits the case bodies first, with a jump around
them, and the dispatch code after the last case, when every value is known. The
dispatch then jumps backwards into the bodies, so no forward references are
needed for the case labels.

### 3.3 Cost

0.5 to 1K of compiler, nothing at run time. It replaces long `elseif` chains,
which are larger and slower, so most programs get smaller.

## 4. Pattern matching

### 4.1 What Rust's `match` is made of

Rust's `match` is powerful because of three things together:

1. **Sum types:** an `enum` whose variants carry data.
2. **Patterns:** destructuring a variant's data into names, at any depth, with
   guards.
3. **Exhaustiveness:** the compiler proves every case is handled.

Of these, nested patterns and guards are where the compiler cost and the type
system's complexity grow. Variants with data, one level of destructuring and
exhaustiveness give most of the benefit at a fraction of the cost.

### 4.2 A restricted form for Baton

```nucleus
variant Shape
    circle(radius as u16)
    rect(width as u16, height as u16)
    empty
end

sub area(s as Shape) as u32
    select s
    case circle(r)
        return 3 * u32(r) * u32(r)
    case rect(w, h)
        return u32(w) * u32(h)
    case empty
        return 0
    end
end
```

- **Representation:** a tag byte followed by the largest variant's fields. A
  `Shape` here is 5 bytes.
- **Bindings:** each case may name the variant's fields. A scalar field is
  copied into the name; an aggregate field is bound as an alias, valid within
  the case. Bindings are read-only unless the subject is a `var` parameter.
- **Exhaustiveness:** every variant must have a case, or there must be a `case
  else`.
- **Code:** a dispatch on the tag byte, as for an enumeration.

Left out, to keep the compiler small:

- nested patterns, such as a `rect` whose width is a constant;
- guards (`case circle(r) if r > 10`);
- `select` as an expression, unless expression blocks (O3) are adopted; and
- binding owned fields by move, except through `take`.

### 4.3 Is this too much for the type system?

No. Declarations precede use, so a variant type is fully known before any
`select` over it, and a single pass can check exhaustiveness by marking each
variant as its case is read. It adds one new kind of type, the variant, with
the same storage rules as a record.

It also unifies features the memory-safety design needs anyway:

- `own? T` behaves as a variant with cases `some(h)` and `none`;
- testing an identifier yields `some` if its slot is still live and `none` otherwise; and
- an enumeration is a variant whose cases carry no data.

So the testing syntax that memory safety leaves open (its Section 11, question
3) can be `select` itself, and one mechanism replaces three.

### 4.4 Cost

1.5 to 2.5K of compiler beyond `select` and enumerations, nothing at run time
beyond a byte per variant value. Ownership interacts in one place: a variant
holding an owned field is an owning type and can't be copied.

## 5. Totals and the budget

| Group | Compiler |
| --- | --- |
| Nucleus core | 12–15K (measured 15K; rewrite target 12K) |
| Essential additions | 7–12K |
| Important additions | 4–7K |
| Linker phase | 5K |
| **Total** | **28–39K** |

On a CP/M system with about 56K free, a 32K `BATON.COM` leaves about 24K for
the compiler's workspace: the symbol table, scopes, buffers and file buffers.
That may limit the largest programs Baton can compile, before the 64K limit of
the programs themselves matters.

Ways to recover space, in the order to consider them:

1. **Overlays for rarely used compiler code.** Decimal-to-float conversion,
   pattern-match exhaustiveness checking and the linker are each used at a
   known point. Loading them from an overlay file when needed costs a disk read,
   not a feature.
2. **Pay once for shared machinery.** Enumerations, variants, `select` and
   `own?` testing share one dispatch and exhaustiveness mechanism (Section 4.3).
   Built together, they cost less than the sum of the table rows.
3. **Move work from the compiler into Baton-source libraries.** Formatting,
   parsing and string building can be ordinary Baton routines compiled with the
   program and tree-shaken, rather than compiler built-ins.
4. **Cut features,** last of all, starting from Section 2.4 and then Section 2.3.

Cutting `f32` would save the most in one stroke (1.5–2.5K of compiler), but a
complete language needs it, and its runtime cost already falls only on programs
that use it.

## 6. Open questions

1. Are variant records and matching in the first release, or the second?
2. Is `select` usable as an expression, which needs expression blocks?
3. What is the compiler budget: a hard limit on `BATON.COM`, or a minimum
   workspace that sets the largest compilable program?
4. Which compiler parts, if any, go into overlays?
