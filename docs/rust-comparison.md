# Basie compared with Rust

Status: explanatory note, not normative. The [specification](../spec/01-status-and-conformance.md) governs every rule described here.

Basie looks very different from Rust on the surface. It uses BASIC-style keywords, `end` blocks and words instead of punctuation for types. Underneath, its ideas are close to Rust's: single ownership, explicit moves, access that can't outlive its storage and failures that every caller must handle. Basie enforces them with much smaller machinery, so that a compiler for them fits on a 64K Z80.

## The same program in both

```basie
record Reading
    value: u16
    usable: boolean
end

var current: Reading = (12, true)

sub update(var item: Reading, value: u16)
    item.value = value
end

sub main()
    update(var current, 20)
    assert current.value = 20
end
```

```rust
struct Reading {
    value: u16,
    usable: bool,
}

fn update(item: &mut Reading, value: u16) {
    item.value = value;
}

fn main() {
    let mut current = Reading { value: 12, usable: true };
    update(&mut current, 20);
    assert_eq!(current.value, 20);
}
```

Basie ends blocks with `end` and statements with a newline, where Rust uses braces and semicolons. In Basie `var` marks the parameter and the call is unmarked. In Rust `&mut` appears at both the parameter and the call. Basie record initialisers are positional, and Rust names each field.

## Lexical level

| | Basie | Rust |
| --- | --- | --- |
| Statement end | newline, continued inside `(` or `[` | `;` |
| Blocks | `if … end`, `sub … end` | `{ … }` |
| Comments | `//` only | `//`, `/* */`, `///` doc comments |
| Hexadecimal and binary | `$FF`, `%1010` | `0xFF`, `0b1010` |
| Literal suffixes and separators | none: `42u8` and `1_000` are errors | `42u8`, `1_000` |
| Characters | `'A'` is a byte, value 65 | `'A'` is a four-byte Unicode `char` |
| Strings | bytes, escapes such as `\x41`, no Unicode | UTF-8, `\u{…}` escapes, raw strings |
| Floating point | `f32` only | `f32` and `f64` |

## Declarations and types

| | Basie | Rust |
| --- | --- | --- |
| Variable | `var total: u16 = 0` | `let mut total: u16 = 0;` |
| Inferred type | `var count = 0` | `let count = 0;` |
| Constant | `const rows: u8 = 4` | `const ROWS: u8 = 4;` |
| Mutability | every `var` can be assigned | immutable unless `mut` |
| Type annotation | `name: type` | `name: type` |
| Integers | `u8`, `i8`, `u16`, `i16`, `u32`, `i32` | also 64-bit, 128-bit, `usize` and `isize` |
| Boolean | `boolean` | `bool` |
| Record | `record … end` with fields `name: type` | `struct` with fields `name: type` |
| Fixed array | `u8[4]` | `[u8; 4]` |
| Open array | `T[]` as a parameter, for the call only | `&[T]`, which can be stored |
| String | `string[32]`: fixed capacity plus a length | `String` or `&str` |
| Enumerations and tagged unions | none (a [stretch goal](stretch-goals.md)) | `enum` with payloads |
| Generics, traits and methods | none | central to the language |
| Tuples, closures and routine values | none | yes |

The largest structural difference is in the last three rows. A Rust program is organised around `impl` blocks, traits and generic types. A Basie program has records, arrays and free-standing routines, much like Pascal without units.

## Routines

| | Basie | Rust |
| --- | --- | --- |
| Keyword | `sub` | `fn` |
| Result type | `sub f(a: u8): u16` | `fn f(a: u8) -> u16` |
| Writable aggregate parameter | `var item: Reading` | `item: &mut Reading` |
| Read-only aggregate parameter | `item: Reading`, an alias with no `&` | `item: &Reading` |
| Scalar parameter | a copy | a copy for `Copy` types |
| Returning access | `as var Entry from items` names the source | lifetime annotations such as `-> &'a mut Entry` |
| A routine that can fail | `fails` in the header | `-> Result<T, E>` |
| Declaration order | declare before use, with `forward` for mutual recursion | any order |
| Shadowing | refused | allowed and common |
| Methods | none: write `update(r, 20)` | `r.update(20)` |

Basie's `from` clause does the job of a Rust lifetime annotation. It tells the compiler which parameter a returned alias comes from, which is what `'a` usually expresses.

## Expressions and operators

| | Basie | Rust |
| --- | --- | --- |
| Equality | `=`, read by context as assignment or comparison | `==`, with `=` for assignment |
| Not equal | `<>` | `!=` |
| Logic | `and`, `or`, `not`, `xor` | `&&`, `\|\|`, `!`, `^` |
| Bitwise operations | `and`, `or`, `xor`, `not` on integers | `&`, `\|`, `^`, `!` |
| Remainder | `mod` | `%` |
| Shifts | `shl`, `shr` | `<<`, `>>` |
| Narrowing conversion | `u8(x)` traps if the value doesn't fit | `x: u8` truncates, `u8::try_from(x)` checks |
| Integer overflow | wraps, and is defined | panics in debug builds and wraps in release builds |
| Division by zero | trap | panic |

Basie's narrowing rule is stricter than Rust's `as`. Its overflow rule is looser than a Rust debug build.

## Control flow

| | Basie | Rust |
| --- | --- | --- |
| Conditionals | `if … elseif … else … end` | `if … else if … else { }`, also usable as an expression |
| Selection | `select x` with `case 1, 3 to 5` and `case else` | `match x { 1 \| 3..=5 => …, _ => … }` |
| Exhaustive selection | not required for values | required |
| Counted loop | `for i = 0 until n step 2 … end` | `for i in (0..n).step_by(2) { }` |
| Inclusive bound | `to` | `..=` |
| Loop exits | `exit`, `continue` | `break`, `continue`, labelled breaks |
| Iterators | none | everywhere |

A Basie `for` counter is read-only and its bounds are evaluated once. A counter that would pass the end of its type traps. Rust gets the same safety from iterators over ranges.

## Ownership and memory

The two languages are closest in intent here and furthest apart in mechanism.

| | Basie | Rust |
| --- | --- | --- |
| Dynamic storage | a fixed pool per record type: `pool jobs: Job[8]` | a general heap: `Box`, `Vec`, `Rc` |
| Owning reference | a handle typed with the pool name: `first: jobs` | `Box<Job>` |
| Allocation | `new jobs(7)` traps if the pool is full, `new? jobs(7)` returns `none` | `Box::new(…)` aborts on exhausted memory |
| Optional owner | `jobs?`, empty value `none` | `Option<Box<Job>>` |
| Move | explicit: `consume(move first)` | implicit for every non-`Copy` value |
| Testing an option | `select move h` with `case some(x)` and `case none` | `match h { Some(x) => …, None => … }` |
| Release | automatic when the owner ends, no `free` | automatic `Drop` |
| Stored non-owning reference | `id jobs`, generation-checked, traps if stale | `Weak<T>`, or generational indexes from crates such as `slotmap` |
| Access for a call | an alias or a lease, valid for the call only | `&T` or `&mut T`, storable where lifetimes allow |
| Writable aliases | several may exist at once | `&mut` is exclusive |
| How safety is proved | aliases limited to calls, plus run-time generation checks | the borrow checker with lifetime inference |

Basie keeps the guarantees that Rust's ownership model exists to provide. Every access stays inside live storage, and every pool record has exactly one owner. Basie limits aliases to the length of a call, so the compiler needs no general lifetime analysis. The cost is that a Basie record can't hold a borrowed reference the way a Rust struct can. It can hold an `id` instead, which is checked each time it is used.

Rust also forbids two mutable paths to the same data. Basie allows them, and its memory safety doesn't depend on exclusivity. Two aliases can still interfere with each other's logic, as they can in Pascal or C. Rust's rule also prevents data races between threads, and Basie has no threads.

Basie marks every transfer of ownership with `move` at the point where it happens, where Rust moves values implicitly.

## Errors

| | Basie | Rust |
| --- | --- | --- |
| Declaring failure | `sub parse(…): u16 fails` | `-> Result<u16, E>` |
| Failing | `fail badNumber`, where the code is an integer constant | `return Err(E::BadNumber)` |
| Passing a failure on | `try` before the call | `?` after the call |
| Handling a failure | `x = f() handle code … end` | `match f() { Err(code) => …, Ok(v) => … }` |
| Unhandled failure from `main` | the runtime prints `FAIL 4` | `main` returns `Err` and the error is printed |
| Unrecoverable error | a trap, which nothing can catch | a panic, which `catch_unwind` can catch |
| Error data | an integer code only | any type |

In both languages failure is part of a routine's signature, and every call must deal with it. Basie's form is lighter but carries less information. The next version replaces `else fail` with `try` before the call, which does the job of Rust's `?` ([D48](design-decisions.md#adopted-for-the-next-language-version)).

## Program structure

| | Basie | Rust |
| --- | --- | --- |
| Multiple files | `include "TEXTIO.BSI"` joins source parts | `mod` and `use` over a module tree |
| Visibility | `private` hides a name from other parts | private by default, `pub` to export |
| Namespaces | one program-wide namespace | paths such as `std::io::Write` |
| Assertions | `assert x = 1` in routines, constant-only at top level | `assert!`, `debug_assert!`, constant assertions |
| Macros | none | central: `println!`, `vec!`, derives |
| Entry point | `sub main()` or `sub main() fails` | `fn main()` |

## Proposed syntax changes

The next language version brings the surface closer to Rust with `:` for `as` (D52) and `try` for `else fail` (D48). Routines keep `sub` and writable parameters keep `var`. Together the two changes turn this routine:

```basie
sub execute(text: string[]): u16 fails IoError
    var value = try parseU16(text)
    return value * 2
end
```

into:

```basie
sub execute(text: string[]): u16 fails IoError
    var value = try parseU16(text)
    return value * 2
end
```

which is close to Rust's:

```rust
fn execute(text: &str) -> Result<u16, ParseError> {
    let value = parse_u16(text)?;
    Ok(value * 2)
}
```

Some surface differences would remain:

- `sub` in place of `fn`
- `end` blocks and newlines in place of braces and semicolons
- the operator words `=`, `<>`, `and`, `or` and `mod`
- the `$` and `%` number prefixes
- `var` on a writable parameter and its argument, where Rust writes `&mut`
- read-only calls that pass a record without `&`
- explicit moves

The other adopted changes are `var` at the call site, `for … in` over arrays and strings, and required `case else` ([design decisions](design-decisions.md#adopted-for-the-next-language-version)). `var` at the call site and `for … in` bring Basie closer to Rust's `&mut` arguments and iterators. Shadowing stays refused, as in Zig. Namespaced includes, planned for version 2, would take the pressure off library names.

The differences of substance would also remain. Basie has pools in place of a heap and aliases limited to a call in place of stored borrows. Plain enums distinguish named code domains, without payloads. It has no generics, traits or methods.

A Rust programmer should find Basie's safety model familiar but its syntax old-fashioned and its type system small. A BASIC or Pascal programmer should find the syntax familiar and the ownership rules new.
