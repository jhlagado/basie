# Basiq design decisions

- Status: working record
- Date: 2026-10-04

This document records the language decisions made so far, with the reasons for
each, and the questions still open. Where Basiq keeps a Nucleus rule unchanged,
the entry says so and points at the Nucleus specification
(`../../nucleus/docs/specification.md`). Examples use Nucleus 0.1 syntax unless
they show a new feature.

## Decided

### D1. One source pass

The compiler reads its source once. Names are declared before use. A forward
declaration is a routine's complete and only signature, and the body that
completes it begins with the abbreviated header `sub NAME`, exactly as in
Nucleus §4.6:

```nucleus
forward sub relay(text as string[]) fails

sub emit(text as string[]) fails
    relay(text) else fail
end

sub relay
    emit(text) else fail
end
```

**Why.** It keeps the compiler small enough to run on the target, and it keeps
every rule checkable from what the compiler has already seen. A design rule
follows from it: **fixups fill in code addresses, never missing semantic
information.** Any fact the compiler needs at a call, such as a result's
lifetime (D8), must be in the signature before the call.

### D2. Statement syntax

Basiq keeps Nucleus's lexical rules (§3.4):

- a logical newline is the only statement terminator;
- a line ending inside `(` or `[` is whitespace, which is how an expression
  spans several lines; and
- blocks close with a plain `end`.

Control flow uses words: `if`, `elseif`, `else`, `for`, `while`, `and`, `or`,
`not`.

**Not adopted:** Lua's `then`, `do` and `function`. Each would reserve a word
and add scanner and table entries to the compiler without changing meaning.
Nucleus §3 already requires that any new reserved word be justified by its
cost.

### D3. Numeric types

| Type | Size | Range or format |
| --- | --- | --- |
| `u8` | 1 | 0 to 255 |
| `i8` | 1 | −128 to 127 |
| `u16` | 2 | 0 to 65,535 |
| `i16` | 2 | −32,768 to 32,767 |
| `u32` | 4 | 0 to 4,294,967,295 |
| `i32` | 4 | −2,147,483,648 to 2,147,483,647 |
| `f32` | 4 | IEEE 754 single-precision layout (D7) |
| `boolean` | 1 | `false`, `true` |

**Why these.**

- **16 bits is the working size.** The Z80 handles 16-bit values natively: a
  16-bit add is the one-byte `ADD HL,DE`. Counters, indices, addresses and
  characters stay cheap.
- **Signed types are new.** Nucleus 0.1 had only `u8`, `u16` and `boolean`. Their
  absence was a larger gap for general use than the lack of floating point.
- **`i8`** is for signed displacements and small deltas stored in records.
- **32-bit types are opt-in.** The Z80 has three register pairs, so a 32-bit
  binary operation doesn't fit in registers and becomes a call to a runtime
  helper. Programs that never use 32-bit types don't carry those helpers; the
  link step removes them.
- **No tags, so no cell size.** Values are untyped bits at run time, sized by
  their static type. There is no reason to choose a width to leave room for tag
  bits.
- **No 24-bit integer.** With no tags to make room for, a 24-bit type has no
  arithmetic advantage. Its only use would be addresses on the eZ80 or banked
  "far" pointers, which would be a separate address type if they are ever
  needed.

### D4. Conversions

- **Widening is implicit where no value can be lost:** `u8` to `u16` to `u32`,
  `i8` to `i16` to `i32`, `u8` to `i16`, `u16` to `i32`, and integer to `f32`
  only where the conversion is exact (`u8`, `i8`, `u16` and `i16`).
- **Narrowing is explicit and checked.** A conversion such as `u8(x)` or
  `i16(y)` traps with `narrowing` when the value doesn't fit, as `u8(...)` does
  in Nucleus §9.5. When the compiler can prove from constants that it won't
  fit, the source is invalid.
- **Signedness changes are checked conversions.** Converting a negative value to
  an unsigned type traps. Converting an unsigned value above the signed range
  traps.
- **`f32` to integer** truncates toward zero and traps when the result is out
  of range.
- **Mixed signed and unsigned operands are an error,** not a promotion. A
  program converts one operand explicitly. This avoids C's most common
  arithmetic trap, where a negative signed value silently becomes a huge
  unsigned one.

### D5. Arithmetic wraps

Addition, subtraction, multiplication and negation wrap modulo the width of the
type, as in Nucleus §9: `65535 + 1` is `0` in `u16`. Signed types wrap in two's
complement.

**Why.** Trapping on overflow would add about 3 bytes and 10 T-states to every
unsigned add and subtract (`JP C,trap`), and more for signed operations,
because `ADD HL,DE` doesn't set the overflow flag and the check needs
`OR A` / `ADC HL,DE` / `JP PE,trap`. In arithmetic-heavy code that could be
roughly 5 to 10 per cent of code size. Narrowing (D4) is where values silently
become wrong, and checking it is cheap because it happens far less often than
addition. Checked arithmetic operators can be added later if programs need
them. Debug and release builds never behave differently.

### D6. Traps and failures stay separate

As in Nucleus §14 and §15:

- **`fails`** marks a routine whose errors a caller can recover from, such as
  I/O. Callers must deal with them using `else fail` or `handle`.
- **A trap** ends the program immediately with a stable reason. It can't be
  caught, so it appears in no signature.

An expression that may trap, such as `a / b`, is not failable. New checks
(D4, D7) are traps.

Trap reasons carry over from Nucleus (`bounds`, `narrowing`,
`division-by-zero`, `loop-range`, `activation-capacity`, `unhandled-error`),
with additions for floating point (D7).

### D7. Floating point

`f32` uses the IEEE 754 single-precision storage layout: one sign bit, an 8-bit
exponent and a 23-bit fraction. Arithmetic is simplified for an 8-bit machine:

- **Round to nearest, ties to even,** with no other rounding modes and no
  exception flags.
- **Flush to zero.** IEEE's denormal numbers fill the gap between the smallest
  normal value (about 1.2 × 10⁻³⁸) and zero. Supporting them adds code to every
  operation. Basiq treats denormal inputs as zero and returns zero for results
  that would be denormal. The only visible effect is on values below
  10⁻³⁸, where two different numbers can subtract to zero.
- **No infinity or NaN.** Division by zero traps with `division-by-zero`, a
  result too large for `f32` traps with a new `float-overflow` reason, and an
  invalid operation such as the square root of a negative number traps with
  `float-invalid`. Every `f32` value is therefore an ordinary finite number,
  and comparison behaves normally (`x = x` is always true).

**Why.** The IEEE layout keeps values compatible with other tools and file
formats. The simplifications remove the most expensive parts of a software
float library while affecting almost no real program on this class of machine.

### D8. Local aggregates and the `from` clause

Basiq allows records, arrays and bounded strings as routine locals, living for
the length of the call. Nucleus had only program-lifetime aggregates (§7.9),
which forced every temporary buffer into a global.

A routine may return an alias, as in Nucleus, but now the alias may point into
storage that dies. The rule:

- A returned alias may point into a **global**, or into a **parameter listed in
  the routine's `from` clause**.
- It may never point into the routine's own local.

```nucleus
sub pick(items as Entry[8], index as u8) as Entry from items
    return items[index]
end
```

At a call, the result lives exactly as long as the arguments passed for the
`from` parameters. If any of them is rooted in a local aggregate, the result may
be used within the calling routine but can't be returned from it, unless that
local is in turn a parameter listed in the caller's own `from` clause.

```nucleus
sub bad() as Entry
    var mine as Entry[8]
    return pick(mine, 0)        // error: result points into the local mine
end
```

A routine whose results always point into globals needs no `from` clause.

**Why an explicit clause instead of inference.** Inferring which parameters a
result may point into would need each callee compiled before its callers, which
a forward declaration breaks. The clause is part of the signature, so a forward
declaration states it, every call can be checked in one pass, and changing a
routine's body can't silently change whether its callers compile. Most routines
return results rooted in globals and need no clause.

**Rejected alternative:** forbidding any returned result from a call that
received a local-rooted argument. It needs no syntax but rejects reasonable
programs in a way that would surprise their authors.

**Cost.** This gives up a property Nucleus stated (§7.9): that aggregate results
need no lifetime information in signatures. Local aggregates also move
aggregate storage into activation frames, which changes how peak memory is
accounted.

### D9. Compiler budget and shape

The toolchain is two programs:

- **`BASIQ.COM`**, the compiler, at most **24K** including its tables, which
  leaves at least **32K** of working space on a CP/M 2.2 system with 56K free;
  and
- **`BLINK.COM`**, the linker, which `BASIQ` runs automatically when compilation
  succeeds. CP/M 2.2 has no call to run another program, so `BASIQ` copies a
  small loader to the top of memory, which reads `BLINK.COM` into place and
  starts it, as Turbo Pascal's `Execute` did. The user still types one command,
  and the linker gets nearly the whole program area for its tables.

Ways the compiler is kept within budget:

1. It is built on the 12K Nucleus compiler rewrite.
2. 32-bit and `f32` operations are generated as calls to runtime helpers, never
   inline, so the compiler only checks types and selects helpers.
3. Diagnostic message text lives in a message file, `BASIQ.MSG`, read only when
   a diagnostic is reported.
4. Rarely used parts, starting with decimal-to-`f32` literal conversion, are
   overlays loaded only when needed.
5. Strings, formatting and other library facilities are Basiq source libraries,
   compiled with the program and tree-shaken, not compiler features.
6. Features are deferred to version 2 when they don't fit (D24).

Every feature is costed in compiler bytes and in generated-code bytes before it
is adopted, and the measurements are published, as Nucleus did.

### D10. Target machine

Basiq programs and the Basiq toolchain target a Z80 with 64K of RAM running
**CP/M 2.2**, which is the primary target; CP/M 3 is supported where it costs
nothing extra. TEC-1 ROM and other bare-machine targets are **not** design
considerations: features, formats and services are not shaped for them. Storage
is high-capacity: 720K or larger floppies
(1.2M and 1.44M high-density formats, the Triptych system's 2M disks) or a hard
disk. A single drive is enough to build any program. Early low-capacity
formats, such as 90K to 250K floppies, are not supported for large builds.

**Why.** It removes disk space as a design constraint on the build pipeline,
which writes temporary spools comparable in size to the program. Memory, not
disk, is the scarce resource Basiq is designed around.

### D11. Trap reports identify the site by address

A trap site is a call to the runtime reporter for its reason, 3 bytes when the
check's result is in a testable condition flag and 5 bytes otherwise. The
reporter prints the reason and the site's address, such as
`TRAP bounds at 1A3F`, and the line table the linker writes turns the
address into a source line. A runtime helper that detects a failure jumps to
the reporter with its stack balanced, so the report gives the program's call to
the helper rather than an address inside it.

**Why.** Nucleus put the source position inline at each site, about 8 bytes. A
checked program has hundreds of sites, and the call form saves roughly 2K per
500 of them, all in code that runs only when there is a bug. The person fixing
a trap will have the line table. A later debug option may restore inline
positions; it would change only the report's format, not program behaviour.
See the [CP/M target](cpm-target.md), §10, and the [toolchain](toolchain.md), §8.

### D12. Re-running without reloading is opt-in

Some shells, such as Z-System's `GO`, re-enter a program already in memory
without reloading it, so initialised variables start with the previous run's
values. A target-profile option, **re-runnable**, keeps a second copy of the
initial values and restores them at every start. It is off by default.

**Why.** Most CP/M users never re-enter programs this way, so most programs
shouldn't pay for a second copy of their initial data. See the
[CP/M target](cpm-target.md), §7.

### D13. Build pipeline

The compiler emits position-free blobs with ordinal references, and a separate
linker removes unreachable blobs before assigning addresses. See the
[build pipeline](build-pipeline.md).


### D14. Type annotations use `as`, after the name

Every declared name is followed by `as` and its type, as in Nucleus:

```nucleus
var total as u32
sub distance(a as Point, b as Point) as u16
record Node
    value as u16
    next  as nodes?
end
```

`var` stays for variable declarations.

**Why name first.** After a name, the next token (`as`, `=`, `(`) tells a
single-pass parser what the statement is, without first looking up whether an
identifier is a type, which C's type-first grammar requires. The whole type
stays on one side of the name, which matters for arrays and, later, routine
types. Result types follow the parameter list where they are read. It leaves
room for inference (`var count = 0`). Nearly every language designed since about
2005 puts the name first.

**Why `as` rather than `:`.** The colon would save about three characters per
declaration and is familiar from TypeScript, Pascal, Go and Rust. But Basiq
already has enough punctuation that a bare colon doesn't say what it does,
while `as` reads as a phrase, especially where modifiers stack up
(`var list as nodes?`), and keeps the BASIC character. The compiler cost
is the same either way.


### D15. One `select` statement

Basiq version 1 has one selection statement, `select`, in the spirit of BASIC's
`SELECT CASE`:

- integer and character constants, lists of them, and ranges (`'0' to '9'`),
  with `case else`; and
- optional handles and identifiers: `some(x)` when there is a live value,
  `none` when there isn't. For an identifier, `none` covers both an empty
  identifier and one whose slot has been freed, so testing never traps.

```nucleus
select key
case 'q', 'Q'
    exit
case '0' to '9'
    digit(key - '0')
case else
    beep()
end

select head
case some(i)
    print(i.value)
case none
    print("empty")
end
```

There is no fall-through, and `select` is a statement, not an expression.

When the subject is an owning local, `some(n)` gives direct, unchecked access to
the node, as a lease does; for any other subject it binds an identifier.
`select move x` moves the value out of `x` and, in `some(n)`, binds `n` as a
non-optional owning local, which is how a `nodes?` becomes a `nodes`.

**Version 2.** Enumerations and variants whose cases carry data, with
exhaustiveness checking and one level of destructuring, come together in
version 2 (D24), since an enumeration is a variant without data. They extend
`select`; Rust-style nested patterns and guards are not planned. Version 1
programs use named constants, as Nucleus did.

**Why.** In version 1 the statement only chooses between constants, ranges and
`some`/`none`, so the BASIC name is the honest one. Enumerations earn their
place mainly alongside full matching, so they wait for it.

### D16. No aliases into pool storage

Pool records are reached only through handles, never through aliases:

- every access through a handle or identifier is one checked operation,
  resolved after all of its operands are evaluated, so nothing can free the
  slot between the check and the access;
- aggregate fields of pool records are copied out, not passed by alias;
- `select` on an optional handle binds an identifier, except that a `select` on
  the caller's own owning local gives direct access, as a lease does (D15);
- a record parameter, read-only or `var`, may be bound to a node held in the
  caller's own owning local, parameter or temporary, giving direct access for
  the call (D30); and
- storing an owned value through an identifier path is checked at run time so
  that it can't create an ownership cycle.

**Why.** Two adversarial reviews showed that aliases into pool slots needed an
effect system (`frees`), pool provenance on every alias and a statement-level
staging rule, and each round of fixes opened new holes. Without pool aliases,
none of that machinery is needed: aliases remain fully expressive for program
and activation storage, where the `from` rule makes them safe, and pool storage
is protected by unique ownership and generation checks. See
[memory safety](memory-safety.md).


### D17. `var` marks a parameter the routine may change

An aggregate parameter is read-only unless it is written with `var` before its
name, which lets the routine change the caller's object:

```nucleus
sub scale(var p as Point, factor as i16)    // may change the caller's Point
sub bump(var n as Node)                     // may change the caller's Node,
                                            //   wherever it lives (D30)
sub push(var list as nodes?, v as u16)      // may change what list holds
sub show(p as Point)                        // may only read it
```

This replaces the earlier working spelling `inout`. The caller's object stays the
caller's in every case; nothing is handed over unless the parameter has an
owning handle type such as `nodes`.

**Why `var`.** It is Pascal's "variable parameter", with exactly this meaning,
and it matches the `var` that declares variables, so it adds no reserved word.
`inout` suggested a round trip of ownership that doesn't happen. `byref` and
`ref` describe how data is passed rather than what the routine may do, and
Basiq passes every aggregate by reference anyway.

There is no `const` in the same position: read-only is already the default, and
a second spelling for it would add a keyword without adding meaning.

### D18. Freeing is automatic; there is no `free` keyword

Releasing a pool slot is called **freeing** it (replacing the working term
"retire"). Freeing is always implicit:

- when an owned handle goes out of scope without having been given away;
- when an owned variable or field is overwritten, including with `none`; and
- when the slot that owns it is freed, which frees everything it owns.

To free something early, assign `none` to the optional variable or field that
holds it: `head = none`. A non-optional owning handle is always a local or
parameter and is freed at the end of its scope.

**Why.** Every case already has a natural spelling, so a keyword would add a
second way to do the same thing.

### D19. Ownership is handed on with `move`

Handing on an owned value held in a variable, parameter or field is always
written with `move` at the point where it happens:

```nucleus
kept = move n                               // n's node moves to kept
sink(move n)                                // passed to an owning parameter
var n = new nodes(v, "", move list) else fail
```

`move` leaves the source empty (`none`). Assigning, passing or returning such a
value without `move` is a compile-time error, so a variable can never be emptied
silently. A fresh value, such as the result of `new` or of a routine returning
an owning type, needs no `move`, since nothing named is emptied. `move`
replaces the working keyword `take`, which was the same operation.

**Why.** Implicit moves are the commonest source of confusion in Rust. `give`
was considered because it paired with an `own` keyword; once D22 removed that
keyword, the neutral and familiar `move` described the action best.

### D20. Constants may be typed, and may be local

```nucleus
const limit = 10                  // untyped: behaves like the literal 10
const big as u32 = 70000          // typed
const half as f32 = 0.5
const Origin as Point = (0, 0)    // aggregate constants are always typed
```

- A scalar constant may be written with or without a type. An untyped one
  behaves like its literal at every use, as in Nucleus, adopting whichever
  compatible type the context needs. A typed one has exactly its declared type.
- Constants may also be declared inside routines, with the same rules.

**Why.** Nucleus forbade types on scalar constants, which worked with two
integer types. With eight numeric types, an untyped `70000` or `0.5` leaves the
reader guessing; an optional type removes the guess without forcing it on small
integers. Local constants mirror local variables and cost little.


### D21. A variable's type may be inferred from a typed initialiser

```nucleus
var d = distance(a, b)        // u16, from the routine's result type
var p = Origin                // Point, from the constant's type
var count as u16 = 0          // a bare literal: the type must be written
```

A variable declared without `as` takes the type of its initialiser, provided
the initialiser has a definite type: a typed variable, constant or field, a
routine result, or an expression built from them. A bare literal or an untyped
constant has no definite type, so a variable initialised with one must state
its type.

**Why.** Inference from a typed initialiser is safe and saves repetition. A
default type for bare literals would need a rule, and the obvious one, the
smallest type that fits, makes `var x = 0` a `u8` that silently wraps at 255.
Requiring the type there catches the moment when it matters which of eight
numeric types was meant.


### D22. A pool name as a type means owning; `id` marks a reference

A pool's name used as a type denotes a handle to one of its slots. On its own it
**owns** the slot. `id` before it makes a non-owning reference. `?` after the
type allows `none`:

| Type | Meaning |
| --- | --- |
| `nodes` | owns a slot of `nodes`; never empty |
| `nodes?` | owns a slot of `nodes`, or is `none` |
| `id nodes` | refers to a slot of `nodes` without owning it |
| `id nodes?` | refers to a slot, or is `none` |

```nucleus
forward pool nodes            // D40
record Node
    value  as u16
    next   as nodes?          // owns the next node
    parent as id nodes?       // refers to the parent
end

var head as nodes?
sub sink(n as nodes)          // takes ownership: caller writes sink(move n)
sub bump(var h as nodes)      // works on the caller's node; caller keeps it
sub show(i as id nodes)       // refers to a node
```

There is no `own` keyword. A non-optional owning handle is allowed only for
locals and parameters; fields and program variables that hold handles are
always optional.

**Why.** It reads like containment: a node contains the next node as a record
contains its fields. Owning links are the commoner kind in records, so the
rarer non-owning links carry the extra word. Forgetting either qualifier is a
compile-time error, not a silent fault: copying from an existing owner into an
owning field needs `move`, and storing a fresh node only in an identifier would
free it at once, which the compiler rejects.

**The `?` belongs to the type.** It makes a different type, an optional, which
must be tested with `select` before use, and it must be expressible wherever a
type appears: fields, variables, parameters, results and array elements
(`owners as nodes?[32]` is an array of 32 optional handles). A marker on the
name could not express a result or an element type.


### D23. One pool per record type is the expected style; no generics in 1.0

A pool is storage, not a container: any number of lists, trees or graphs can
share one pool. Programs normally declare one pool per record type, so code
written for that pool's handles serves every structure in it. Basiq 1.0 has no
generics; Pascal never had them either.

### D24. Version 1 scope

Version 1 includes the Nucleus core and: signed and 32-bit integers, `f32`,
shifts and bitwise operators, `select` on integers, characters and optional
handles, local aggregates with `from`, arrays of arrays, `var` parameters, pools
and handles with `move`, `private` and `include`, run-time `assert`, and
services for I/O.

Deferred to **version 2**: enumerations and variants whose cases carry data,
expression blocks (O3), arenas (O4), routine values (O5), default parameter
values (O6), generics (D23) and `repeat`.

**Why.** The deferred features are the largest compiler costs that ordinary
programs can do without, and the version 1 set fits the 24K budget (D9).

### D25. Strings: bounded strings and a Basiq library

Basiq keeps Nucleus's strings: `string[N]` with a fixed capacity of at most 253
and a current length; string literals as constants and as direct arguments; and
open `string[]` parameters, which accept any capacity and can read `.capacity`
and set `.length`. String building, comparison, searching and conversion between
numbers and text, including `f32`, are a **standard library written in Basiq**,
compiled with the program and tree-shaken, not compiler features.

Raising a string's length makes the bytes it exposes zero, so a local string can
be initialised by zeroing only its length byte.

### D26. Failure codes are named constants; enumerations later

A failable routine reports a `u8` code, as in Nucleus, normally named by a
constant: `const fileMissing = 1`. In version 2, when enumerations arrive, a
routine may name the enumeration its codes come from,
`sub open(name as string[]) fails FileError`, and the compiler checks that
`fail` and `handle` use that enumeration's values. Richer error values carrying
data wait for variants.

### D27. A full pool traps

`new nodes(...)` traps with `pool-full` when the pool has no free slot, as stack
overflow does: a full pool is a capacity bug. A program that wants to handle
exhaustion uses `new? nodes(...)`, which returns `nodes?` and is `none` when the
pool is full.

**Why.** Every allocation would otherwise need `else fail`, though most programs
size their pools so they never fill.

### D28. Declarations anywhere, with block scope

A local may be declared at any statement position. Its scope runs from its
declaration to the end of the innermost enclosing block (a routine body, an
`if` or `select` arm, or a loop body). Owning locals are freed at the end of that
block.

**Why.** The ownership patterns declare handles where they are made, and block
scope gives every owning local an exact end.

### D29. `id` is a contextual word

`id` is a keyword only before a pool name in a type. Elsewhere it is an ordinary
identifier, so `id` remains usable as a field or variable name.

### D30. Direct access to a node is a record parameter

A record parameter, read-only or `var`, accepts any record of its type in
program or activation storage, and also the node held by one of the caller's own
owning locals or owning parameters, or by a temporary. Inside, the routine has
direct, unchecked access. Passing a node is a lease: that local or parameter may
not appear anywhere else in the same statement except as `id(h)` or a read of a
scalar field. A `var` parameter of an owning type carries a hidden owner word so
that stores through it keep ownership links correct
([memory safety](memory-safety.md), Section 5.6). This replaces the separate
parameter kind `var h as nodes`.


### D31. Numeric rules

- **Implicit widening** only where no value can be lost: `u8` to `u16` to
  `u32`; `i8` to `i16` to `i32`; `u8` to `i16`; `u16` to `i32`; any 8- or 16-bit
  integer to `f32`. Every other change of type is an explicit, checked
  conversion (D4).
- **Mixed operands:** if one operand's type widens without loss to the other's,
  the operation is done in the wider type; otherwise it is an error and one
  operand must be converted explicitly. `u8 + i16` is an `i16` addition;
  `u16 + i16` is an error.
- **Literals** take the type their context requires and must fit it. A literal
  containing `.` or an exponent is an `f32` literal: `1.5`, `0.25`, `1e3`,
  `2.5e-3`. A digit is required before the decimal point.
- **Unary minus** wraps, as in Nucleus: on an unsigned type it is subtraction
  from zero modulo the width. On signed types it wraps in two's complement, so
  `-(-32768)` is `-32768` in `i16`.
- **Division** truncates toward zero, and `mod` takes the sign of the dividend:
  `-7 / 2` is `-3` and `-7 mod 2` is `-1`. `-32768 / -1` wraps to `-32768`.
  Division by zero traps, as in Nucleus.
- **Shifts** are written `shl` and `shr`, with an unsigned shift count. `shr`
  keeps the sign for signed types and shifts in zeros for unsigned ones. A shift
  by the type's width or more gives 0, or -1 for a negative signed value shifted
  right.
- **Bitwise operators:** `and`, `or`, `xor` and `not` work bit by bit on integer
  operands of the same type, and logically on `boolean` operands, as in Pascal.
- **Comparisons** follow the operand rules above; mixed signed and unsigned
  comparisons that don't widen are errors.
- **Counted loops** may use any integer type as the counter, with negative steps;
  Nucleus's loop-range trap rules apply.
- **Indexes** are `u8` or `u16`. A signed value must be converted explicitly,
  and the checked conversion traps if it is negative, so a negative index can
  never wrap into a valid one. Assigning a signed value to a string's `.length`
  is a mixed-sign error for the same reason.
- **Constant expressions** are evaluated exactly as at run time: integers exactly
  and then checked to fit, `f32` with round-to-nearest-even and flush-to-zero
  (D7).

**Why.** These are the conventional answers (C99, modern Pascal and ATOM agree on
division and `mod`), chosen so that no rule silently loses a value.

### D32. Arrays of arrays

Arrays may contain arrays, giving multi-dimensional arrays:
`var screen as u8[25][40]`, used as `screen[r][c]`. Each index is checked
against its own bound. Open array parameters (`u8[]`) work as in Nucleus, on the
outermost dimension.

**Why.** Screens, boards and grids are common in CP/M programs; the record-per-row
workaround is clumsy. It costs about 0.3K of compiler, and changes Nucleus's
internal type encoding, which assumed arrays never nest.

### D33. `private` and `include`

- A top-level declaration marked `private` is visible only within its own source
  file.
- A source file may begin with `include "STRINGS.BSQ"` lines naming the files it
  depends on. Each file is compiled once, before the files that include it, as
  in ATOM and Skate. The command line then names only the main file.

**Why.** The standard library is written in Basiq, so its internal routines need
to be hidden from programs, and programs need a way to pull in the library parts
they use. Together they cost about 0.5K. Full modules with qualified names are
not planned.

### D34. Case sensitivity and `assert`

- Names are **case-sensitive**, as in Nucleus: `Count` and `count` are different.
- **`assert condition`** checks a condition at run time and traps with
  `assertion` when it is false, reporting the site like any trap.

**Why.** Case sensitivity is simpler and faster for the compiler and is what
Nucleus already does. A run-time `assert` costs about 0.1K and suits a language
whose errors stop the program with a located report.


### D35. Two implementation tracks

Basiq is built in two tracks ([implementation plan](implementation-plan.md)):

- a **reference toolchain** in TypeScript on Deno, written in the same
  single-pass style as the native compiler, which implements each feature first
  and serves as the test oracle; and
- the **native toolchain**, `BASIQ.COM` and `BLINK.COM` in Z80 assembly,
  assembled with ATOM as development tooling. The compiler is forked from the
  Nucleus 12K rewrite and evolved in stages; the linker is new.

The native linker must produce byte-identical output to the reference linker; the
native compiler must produce programs that behave identically on the whole
conformance suite.

**Why.** Basiq's language is several times larger than Nucleus's, and design
questions are far cheaper to settle in TypeScript than in Z80. A second
implementation catches errors a single one can't.


### D36. The version 1 standard library

The standard library is Basiq source, compiled with the program through
`include` and tree-shaken. Version 1 provides:

- **Strings** (`STRINGS.BSQ`): `append(var s, t)`, `appendByte(var s, b)`,
  `copyFrom(var dest, src, start, count)`, `equal(a, b)`, `compare(a, b)`
  returning `i8`, `find(s, t)` returning the position or `$FFFF`, `toUpper`,
  `toLower`, `trim`. Each fails with `lineTooLong` rather than exceed the
  destination's capacity.
- **Numbers to text** (`FORMAT.BSQ`): `appendU16`, `appendI16`, `appendU32`,
  `appendI32` in decimal; `appendHex8` and `appendHex16`; `appendF32(var s, x,
  places)` with a chosen number of decimal places.
- **Text to numbers** (`PARSE.BSQ`): `parseU16`, `parseI16`, `parseU32`,
  `parseI32`, `parseF32`, each failing with `badNumber` (a library failure
  code, 32) on malformed or out-of-range text.
- **Console and files** (`TEXTIO.BSQ`): `writeLine(f, s)` with CR LF,
  `prompt(text, var answer)`, `readSecret(var answer)` without echo,
  `word(text, n, var out)` for command-line words, `readAll(f, var buf)` and a
  copying `truncate`.
- **Pseudo-random numbers** (`RANDOM.BSQ`): a 16-bit generator with a seed.

**Why.** These are what a first program needs and what D25 left to the library;
written in Basiq, they cost compiler bytes nothing and programs only what they
call.

### D37. `assert`

`assert condition` evaluates a `boolean` condition; if it is false, the program
traps with `assertion`, and the report gives the site's address like any trap.
There is no message argument: the line table names the source line. `assert`
with a condition the compiler can prove false from constants is a compile-time
error, as Nucleus does for other guaranteed traps.

### D38. The file table is sized at link time

The number of files open at once is chosen with the linker option `F=n`, 1 to
255, default 4. The linker allocates the file table at the end of `BSS`, sized
from a file-entry size in the library's profile block, and only when the
program uses a file service; the runtime reaches it through the `FILES` and
`FILECOUNT` pseudo-objects ([object format](object-format.md), Section 3.6).

**Why.** The limits register forbids arbitrary limits. 255 is the largest count
a one-byte slot in a file number can hold, far beyond what memory allows for
real programs.

### D39. Diagnostics come from a message file

`BASIQ` and `BLINK` hold diagnostics as numbers and read their text from
`BASIQ.MSG`, with up to two substituted arguments
([toolchain](toolchain.md), Section 7.3). Without the file, the number and
arguments are printed instead.

**Why.** Message text is several kilobytes that the compiler would otherwise
carry through every compilation (D9).


### D40. Forward pool declarations

A record and its pool refer to each other: `record Node` has a field of type
`nodes?`, and `pool nodes as Node[64]` needs `Node`. Under declaration before
use, a **forward pool declaration** breaks the cycle, as `forward sub` does for
mutually recursive routines:

```nucleus
forward pool nodes

record Node
    value as u16
    next  as nodes?
end

pool nodes as Node[64]
```

`forward pool P` makes `P` usable in handle types, which have a fixed size (2
bytes for owning handles, 4 for identifiers) whatever the record is. Nothing
else may use `P` until the pool declaration completes it: no `new`, no field
access through its handles. A forward pool must be completed in the same
compilation, and at most once.

**Why.** It keeps declaration before use, and with it the single pass, while
letting records hold handles to their own pool.

### D41. The code-generation contract

Frames live on the hardware stack with `IX` as the frame pointer; arguments
are pushed left to right and removed by the callee through a shared `RETN`
helper; results come back in `A`, `HL` or `DEHL`; a failing routine returns
with carry set and the code in `A`; expressions evaluate left to right into
those registers with temporaries pushed; every routine blob ends with its
`frame` and `need` words. The [code generation contract](code-generation.md)
has the detail. The reference compiler adopts it first; the native compiler and
the helper table follow it, and its calling-convention codes feed the helper
table's interface key.

**Why.** Nucleus left the convention private to its implementation and chose
a bounded activation arena with a depth of 8. Basiq's stack bound (memory
safety §7) assumes ordinary stack frames, and two implementations plus a
runtime library can only agree if the convention is written down.

### D42. The language is named Basiq

The working title Baton is replaced by **Basiq**: a BASIC with a twist. The
rename covers everything at once: the language, the specification, the
toolchain (`BASIQ.COM`, `BASIQ.MSG`, `BASIQ.OVL`), the source extension
(`.bsq`, and `.BSQ` on CP/M), and the 4-byte magics of the binary formats:
`BSQP` program directory, `BSQB` byte stream, `BSQR` blob library, `BSQM` name
stream, `BQLS` line stream, `BQLT` line table and `BQMS` message file. No file
in the old formats exists outside this repository's tests, so the magics were
changed without a compatibility path.

**Why.** The user wants the name to lean into what the language is: BASIC-like
syntax over a statically typed, memory-safe, natively compiled core.

## Open

### O1. Exclusivity (resolved)

Resolved by D16 and D17: Basiq has no exclusivity rule. Overlapping aliases to
program storage remain allowed, as in Nucleus; they are visible through mutation
but never a lifetime hazard, because program storage is never freed. Pool
storage is never aliased, so freeing can't reach an alias.

### O2. Pools with owned handles (resolved)

Resolved by D16, D18, D19 and D22, and specified in
[memory safety](memory-safety.md): owning records can't be copied (§5.2),
`none` is the empty value of optional handles (§5.2), failure paths free
automatically (§5.3), freeing never recurses (§5.10), and generations saturate
so they never repeat (§5.11).

### O3. Expression blocks (version 2)

A block that produces a value, with an explicit `result` statement supplying
the value and `return` still meaning "leave the routine". This borrows Rust's
composition without Rust's rule that a missing semicolon changes meaning. The
cost is a new reserved word and a check that every path through the block
supplies a value of the right type.

### O4. Arenas (version 2)

Scope-bound regions freed all at once, for temporary data. Free memory between
the end of static storage and the stack is available for this at run time,
starting at the address of the `FREE` pseudo-object ([object format](object-format.md), §3.4).

### O5. Routine values (version 2)

Function pointers or routine values. The build pipeline already handles them
for tree shaking (a routine whose address is taken by live code stays live),
but the type system, calling convention and interaction with `from` are not
designed.

### O6. Default parameter values (version 2)

Parameters with default values, as in TypeScript. Feasible in a single pass,
since defaults would be constant expressions carried by the signature and any
forward declaration, at perhaps 0.3–0.5K of compiler. Deferred: in a language
without overloading they add little, they raise questions for owning and `var`
parameters, and they can be added later without breaking existing programs.

### O7. Debug information (open)

A source-level debugger needs more than the trap lookup's line table: per
routine, the frame layout and type of each local and parameter; the record,
array and pool descriptors; statement boundaries within a line; and a way to
find the source text for a part and line. The format must be binary and
readable from CP/M in 128-byte records without a parser, as the line table
(object format §11) and the symbol file already are; D8 is the model for what
it should carry, not for its encoding. No debugger is planned yet. The format
is to be specified before one is built (roadmap step 73), and the compiler's
name and line streams should be kept rich enough that it can be produced
without a compiler change.
