# Basie design decisions

- Status: working record
- Date: 2026-10-04

This document records the language decisions made so far, with the reasons for
each, and the questions still open. The [specification](../spec/README.md) is
the authority for the rules; these entries record why they are as they are.

## Current version terminology

As of 2026-10-10, the software development line is **0.1**. Version **1.0** is
reserved for eventual language stabilization; the proposed language specification
remains a working draft. The formerly named "version two" scope is the **next
development milestone**, with no assigned release number. Older version-one and
version-two entries retain their historical wording; current status notes and
the [forward plan](development-plan.md) govern present planning. Format, ABI, helper and
CP/M version numbers are independent and unchanged.

## Decided

### D1. One source pass

The compiler reads its source once. Names are declared before use. A forward
declaration is a routine's complete and only signature, and the body that
completes it begins with the abbreviated header `sub NAME` (spec §4.6):

```basie
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

Basie's lexical rules (spec §3.4):

- a logical newline is the only statement terminator;
- a line ending inside `(` or `[` is whitespace, which is how an expression
  spans several lines; and
- blocks close with a plain `end`.

Control flow uses words: `if`, `elseif`, `else`, `for`, `while`, `and`, `or`,
`not`.

**Not adopted:** Lua's `then`, `do` and `function`. Each would reserve a word
and add scanner and table entries to the compiler without changing meaning.
The specification (§3.12) requires that any new reserved word be justified by
its cost.

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
- **Signed types.** A language with only `u8`, `u16` and `boolean` has a larger
  gap for general use than the lack of floating point.
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
  `i16(y)` traps with `narrowing` when the value doesn't fit (spec §9.6). When the compiler can prove from constants that it won't
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
type (spec §9.8): `65535 + 1` is `0` in `u16`. Signed types wrap in two's
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

Recoverable failures and traps are separate mechanisms (spec Chapters 14 and
15):

- **`fails`** marks a routine whose errors a caller can recover from, such as
  I/O. Callers must deal with them using `else fail` or `handle`.
- **A trap** ends the program immediately with a stable reason. It can't be
  caught, so it appears in no signature.

An expression that may trap, such as `a / b`, is not failable. New checks
(D4, D7) are traps.

The base trap reasons are `bounds`, `narrowing`, `division-by-zero`,
`loop-range`, `activation-capacity` and `unhandled-error`, with additions for
floating point (D7).

### D7. Floating point

`f32` uses the IEEE 754 single-precision storage layout: one sign bit, an 8-bit
exponent and a 23-bit fraction. Arithmetic is simplified for an 8-bit machine:

- **Round to nearest, ties to even,** with no other rounding modes and no
  exception flags.
- **Flush to zero.** IEEE's denormal numbers fill the gap between the smallest
  normal value (about 1.2 × 10⁻³⁸) and zero. Supporting them adds code to every
  operation. Basie treats denormal inputs as zero and returns zero for results
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

Basie allows records, arrays and bounded strings as routine locals, living for
the length of the call. Program-lifetime aggregates alone would force every
temporary buffer into a global.

A routine may return an alias, and the alias may point into storage that dies.
The rule:

- A returned alias may point into a **global**, or into a **parameter listed in
  the routine's `from` clause**.
- It may never point into the routine's own local.

```basie
sub pick(items as Entry[8], index as u8) as Entry from items
    return items[index]
end
```

At a call, the result lives exactly as long as the arguments passed for the
`from` parameters. If any of them is rooted in a local aggregate, the result may
be used within the calling routine but can't be returned from it, unless that
local is in turn a parameter listed in the caller's own `from` clause.

```basie
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

**Cost.** This gives up a simpler property: that aggregate results need no
lifetime information in signatures. Local aggregates also move
aggregate storage into activation frames, which changes how peak memory is
accounted.

### D9. Compiler budget and shape

The toolchain is two programs:

- **`BASIE.COM`**, the compiler, with a target of **26K** and a limit of
  **28K** including its tables (D43, which replaces the original 24K), leaving
  at least **28K** of working space on a CP/M 2.2 system with 56K free; and
- **`BLINK.COM`**, the linker, which `BASIE` runs automatically when compilation
  succeeds. CP/M 2.2 has no call to run another program, so `BASIE` copies a
  small loader to the top of memory, which reads `BLINK.COM` into place and
  starts it, as Turbo Pascal's `Execute` did. The user still types one command,
  and the linker gets nearly the whole program area for its tables.

Ways the compiler is kept within budget:

1. It grows from a compiler core for the base language (about 15K, measured).
2. 32-bit and `f32` operations are generated as calls to runtime helpers, never
   inline, so the compiler only checks types and selects helpers.
3. Diagnostic message text lives in a message file, `BASIE.MSG`, read only when
   a diagnostic is reported.
4. Rarely used parts, starting with decimal-to-`f32` literal conversion, are
   overlays loaded only when needed.
5. Strings, formatting and other library facilities are Basie source libraries,
   compiled with the program and tree-shaken, not compiler features.
6. Features are deferred to version 2 when they don't fit (D24).

Every feature is costed in compiler bytes and in generated-code bytes before it
is adopted, and the measurements are published.

### D10. Target machine

Basie programs and the Basie toolchain target a Z80 with 64K of RAM running
**CP/M 2.2**, which is the primary target; CP/M 3 is supported where it costs
nothing extra. TEC-1 ROM and other bare-machine targets are **not** design
considerations: features, formats and services are not shaped for them. Storage
is high-capacity: 720K or larger floppies
(1.2M and 1.44M high-density formats, the Triptych system's 2M disks) or a hard
disk. A single drive is enough to build any program. Early low-capacity
formats, such as 90K to 250K floppies, are not supported for large builds.

**Why.** It removes disk space as a design constraint on the build pipeline,
which writes temporary spools comparable in size to the program. Memory, not
disk, is the scarce resource Basie is designed around.

### D11. Trap reports identify the site by address

A trap site is a call to the runtime reporter for its reason, 3 bytes when the
check's result is in a testable condition flag and 5 bytes otherwise. The
reporter prints the reason and the site's address, such as
`TRAP bounds at 1A3F`, and the line table the linker writes turns the
address into a source line. A runtime helper that detects a failure jumps to
the reporter with its stack balanced, so the report gives the program's call to
the helper rather than an address inside it.

**Why.** A source position inline at each site costs about 8 bytes. A
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

Every declared name is followed by `as` and its type:

```basie
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
declaration and is familiar from TypeScript, Pascal, Go and Rust. But Basie
already has enough punctuation that a bare colon doesn't say what it does,
while `as` reads as a phrase, especially where modifiers stack up
(`var list as nodes?`), and keeps the BASIC character. The compiler cost
is the same either way.


### D15. One `select` statement

Basie version 1 has one selection statement, `select`, in the spirit of BASIC's
`SELECT CASE`:

- integer and character constants, lists of them, and ranges (`'0' to '9'`),
  with `case else`; and
- optional handles and identifiers: `some(x)` when there is a live value,
  `none` when there isn't. For an identifier, `none` covers both an empty
  identifier and one whose slot has been freed, so testing never traps.

```basie
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

**Later planning.** The original grouping below is superseded by the
[forward plan](development-plan.md): plain enums and typed failure codes are accepted
for the next milestone, with enums first as a dependency. Payload variants remain indefinitely deferred.

**Original version-two sketch.** Enumerations and variants whose cases carry data, with
exhaustiveness checking and one level of destructuring, come together in
version 2 (D24), since an enumeration is a variant without data. They extend
`select`; Rust-style nested patterns and guards are not planned. Version 1
programs use named constants.

**Why.** In version 1 the statement only chooses between constants, ranges and
`some`/`none`, so the BASIC name is the accurate one. Enumerations earn their
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

```basie
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
Basie passes every aggregate by reference anyway.

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

```basie
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

```basie
const limit = 10                  // untyped: behaves like the literal 10
const big as u32 = 70000          // typed
const half as f32 = 0.5
const Origin as Point = (0, 0)    // aggregate constants are always typed
```

- A scalar constant may be written with or without a type. An untyped one
  behaves like its literal at every use, adopting whichever
  compatible type the context needs. A typed one has exactly its declared type.
- Constants may also be declared inside routines, with the same rules.

**Why.** Untyped scalar constants alone would work with two integer types.
With eight numeric types, an untyped `70000` or `0.5` leaves the
reader guessing; an optional type removes the guess without forcing it on small
integers. Local constants mirror local variables and cost little.


### D21. A variable's type may be inferred from a typed initialiser

```basie
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

```basie
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
written for that pool's handles serves every structure in it. Basie 1.0 has no
generics; Pascal never had them either.

### D24. Version 1 scope

Version 1 includes the base language (declarations, records, arrays, bounded
strings, structured control, routines, failures and traps) and: signed and 32-bit integers, `f32`,
shifts and bitwise operators, `select` on integers, characters and optional
handles, local aggregates with `from`, arrays of arrays, `var` parameters, pools
and handles with `move`, `private` and `include`, run-time `assert`, and
services for I/O.

The list below records the original deferral from 1.0. Current priorities and
dispositions are in the [forward plan](development-plan.md) and
[catalogue](stretch-goals.md). Plain enums and typed failures are accepted
next-milestone directions, with design completion and separate measured budgets required.
The open-array descriptor correction is accepted for the next milestone before dependent
slice and array extensions, preserving address/extent calls and ownership rules.
Full typed noncapturing routine values are provisionally accepted for the next milestone, with
a whole-feature prototype and back-out gate. Temporary read-only array slices
are accepted for the next milestone, with checked ranges and transient lifetime/lease rules.
Writable and string slices, variants and precompiled libraries remain deferred. Closures are excluded. Limited type
parameters remain rejected.

Originally deferred to **version 2**: enumerations and variants whose cases carry data,
expression blocks (O3), arenas (O4), routine values (O5), default parameter
values (O6), generics (D23) and `repeat`.

**Why.** The deferred features are the largest compiler costs that ordinary
programs can do without, and the version 1 set is meant to fit the compiler budget (D9, D43).

### D25. Strings: bounded strings and a Basie library

Basie has bounded strings: `string[N]` with a fixed capacity of at most 253
and a current length; string literals as constants and as direct arguments; and
open `string[]` parameters, which accept any capacity and can read `.capacity`
and set `.length`. String building, comparison, searching and conversion between
numbers and text, including `f32`, are a **standard library written in Basie**,
compiled with the program and tree-shaken, not compiler features.

Raising a string's length makes the bytes it exposes zero, so a local string can
be initialised by zeroing only its length byte.

### D26. Failure codes are named constants; enumerations later

**Forward status, 2026-10-10.** Plain enums and enum-typed failure codes are
accepted for the next milestone, with enums first as a dependency. Their design completion and
separate measured budgets remain required. No payload errors or variants are
admitted. The current 0.1 completion scope remains unchanged and no implementation is requested now.

A failable routine reports a `u8` code, normally named by a
constant: `const fileMissing = 1`. In the next milestone, after enums are
implemented, a
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
- **Unary minus** wraps: on an unsigned type it is subtraction
  from zero modulo the width. On signed types it wraps in two's complement, so
  `-(-32768)` is `-32768` in `i16`.
- **Division** truncates toward zero, and `mod` takes the sign of the dividend:
  `-7 / 2` is `-3` and `-7 mod 2` is `-1`. `-32768 / -1` wraps to `-32768`.
  Division by zero traps.
- **Shifts** are written `shl` and `shr`, with an unsigned shift count. `shr`
  keeps the sign for signed types and shifts in zeros for unsigned ones. A shift
  by the type's width or more gives 0, or -1 for a negative signed value shifted
  right.
- **Bitwise operators:** `and`, `or`, `xor` and `not` work bit by bit on integer
  operands of the same type, and logically on `boolean` operands, as in Pascal.
- **Comparisons** follow the operand rules above; mixed signed and unsigned
  comparisons that don't widen are errors.
- **Counted loops** may use any integer type as the counter, with negative steps;
  the loop-range trap rules of spec §12 apply.
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
against its own bound. Open array parameters (`u8[]`) apply to the outermost
dimension.

**Why.** Screens, boards and grids are common in CP/M programs; the record-per-row
workaround is clumsy. It costs about 0.3K of compiler, and needs a type
encoding that does not assume arrays never nest.

### D33. `private` and `include`

- A top-level declaration marked `private` is visible only within its own source
  file.
- A source file may begin with `include "STRINGS.BSI"` lines naming the files it
  depends on. Each file is compiled once, before the files that include it. The
  command line then names only the main file.

**Why.** The standard library is written in Basie, so its internal routines need
to be hidden from programs, and programs need a way to pull in the library parts
they use. Together they cost about 0.5K. Full modules with qualified names are
not planned.

### D34. Case sensitivity and `assert`

- Names are **case-sensitive**: `Count` and `count` are different.
- **`assert condition`** checks a condition at run time and traps with
  `assertion` when it is false, reporting the site like any trap.

**Why.** Case sensitivity is simpler and faster for the compiler. A run-time `assert` costs about 0.1K and suits a language
whose errors stop the program with a located report.


### D35. Two implementation tracks

Basie is built in two tracks ([implementation plan](implementation-plan.md)):

- a **reference toolchain** in TypeScript on Deno, written in the same
  single-pass style as the native compiler, which implements each feature first
  and serves as the test oracle; and
- the **native toolchain**, `BASIE.COM` and `BLINK.COM` in Z80 assembly,
  assembled with ATOM as development tooling. The compiler grows in stages
  from a working core for the base language; the linker is written whole.

The native linker must produce byte-identical output to the reference linker; the
native compiler must produce programs that behave identically on the whole
conformance suite.

**Why.** Basie's language is large, and design
questions are far cheaper to settle in TypeScript than in Z80. A second
implementation catches errors a single one can't.


### D36. The version 1 standard library

The standard library is Basie source, compiled with the program through
`include` and tree-shaken. Version 1 provides:

- **Strings** (`STRINGS.BSI`): `clear(var s)`, `append(var s, t)`,
  `appendByte(var s, b)`, `copyFrom(var dest, src, start, count)`,
  `equal(a, b)`, `compare(a, b)` returning `i8`, `find(s, t)` returning the
  position or `$FFFF`, `toUpper`, `toLower`, `trim`. Each fails with
  `lineTooLong` rather than exceed the destination's capacity.
- **Numbers to text** (`FORMAT.BSI`): `appendU16`, `appendI16`, `appendU32`,
  `appendI32` in decimal; `appendHex8` and `appendHex16`; `appendF32(var s, x,
  places)` with a chosen number of decimal places.
- **Text to numbers** (`PARSE.BSI`): `parseU16`, `parseI16`, `parseU32`,
  `parseI32`, `parseF32`, each failing with `badNumber` (a library failure
  code, 32) on malformed or out-of-range text.
- **Console and files** (`TEXTIO.BSI`): `writeLine(f, s)` with CR LF,
  `prompt(text, var answer)`, `readSecret(var answer)` without echo,
  `word(text, n, var out)` for command-line words, `readAll(f, var buf)` and a
  copying `truncate(name, newSize, mode)`.
- **Pseudo-random numbers** (`RANDOM.BSI`): a 16-bit generator with a seed.

The [standard library](standard-library.md) document gives each routine's
exact contract.

**Why.** These are what a first program needs and what D25 left to the library;
written in Basie, they cost compiler bytes nothing and programs only what they
call.

### D37. `assert`

`assert condition` evaluates a `boolean` condition; if it is false, the program
traps with `assertion`, and the report gives the site's address like any trap.
There is no message argument: the line table names the source line. `assert`
with a condition the compiler can prove false from constants is a compile-time
error, as other guaranteed traps are (spec §15.3).

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

`BASIE` and `BLINK` hold diagnostics as numbers and read their text from
`BASIE.MSG`, with up to two substituted arguments
([toolchain](toolchain.md), Section 7.3). Without the file, the number and
arguments are printed instead.

**Why.** Message text is several kilobytes that the compiler would otherwise
carry through every compilation (D9).


### D40. Forward pool declarations

A record and its pool refer to each other: `record Node` has a field of type
`nodes?`, and `pool nodes as Node[64]` needs `Node`. Under declaration before
use, a **forward pool declaration** breaks the cycle, as `forward sub` does for
mutually recursive routines:

```basie
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

**Why.** Basie's stack bound (memory safety §7) assumes ordinary stack frames,
not a bounded activation arena, and two implementations plus a runtime library
can only agree if the convention is written down rather than left private to
one implementation.

### D42. The language is named Basie

The language is named **Basie**: BASIC with the C dropped,
and a nod to Count Basie, who was famous for playing few notes and making each
one count, which is this language's approach to a 64K machine. The tagline is
*few notes, make them count*, with "Count BASIC" as the pun beneath it.

The name is used throughout: the language, the specification, the
toolchain (`BASIE.COM`, `BASIE.MSG`, `BASIE.OVL`), the source extension
(`.bsi`, and `.BSI` on CP/M; `.BAS` is left to MBASIC), and the 4-byte magics
of the binary formats: `BSIP` program directory, `BSIB` byte stream, `BSIR`
blob library, `BSIN` name stream, `BSIL` line stream, `BSIT` line table and
`BSIM` message file.

**Why.** The name had to lean into the BASIC lineage without being merely
generic, be short and easy to remember, and be a space Basie can own.
Candidates checked and rejected: Basiq (an Australian open-banking API company
that sells to developers and asserts the name as a trademark), Basil, Basalt, Bascal,
Basilisk and Plinth (existing languages), Gosub and Bastion (established
software), Count BASIC (too long, and "count" alone is unsearchable), and
Basa and Baza (clear, but weaker links to BASIC and noisier searches). No
programming language, software product or retro-computing project uses Basie.

## Open

O3–O6 retain earlier design notes. The version-two labels are historical, not
release commitments. The [forward plan](development-plan.md) governs priorities.
Expression blocks, arenas and default parameters are indefinitely deferred.
Full noncapturing routine values are provisionally accepted under the
[catalogue](stretch-goals.md#typed-noncapturing-routine-values), with evaluation
of parameters and stored values together. Closures remain excluded.

### O1. Exclusivity (resolved)

Resolved by D16 and D17: Basie has no exclusivity rule. Overlapping aliases to
program storage remain allowed; they are visible through mutation
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

**Current status, 2026-10-10.** Provisionally accepted for the next milestone as the whole typed
noncapturing feature, including parameters and storage in variables and record
fields. This supersedes parameter-only and stored-reference deferral. Prototype
the full scope; an unacceptable complexity or measured budget requires an
explicit back-out decision. Signature checking, defined initialisation,
indirect-call stack safety and linker liveness are required. Closures remain
excluded. The current 0.1 completion scope is unchanged and no implementation is requested now.

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

### D43. The compiler's budget: 26K target, 28K limit, never 30K

`BASIE.COM`'s budget rises from 24K to a **target of 26K** and a **limit of
28K**, including its tables. 30K is the ceiling that no decision may cross. The
census measures the compiler after every native increment and reports it
against both figures: above the target it warns, above the limit it fails, and
no further features are added until size work or a move to version 2 brings it
back. The workspace left on a CP/M 2.2 system with 56.75K from `$0100` to the
BDOS entry is then at least 28.75K at the limit and about 30.75K at the target.

Every native increment follows a cycle that keeps the compiler small: **the
increment, a review for correctness, a compression pass** over its object
code, and a further review when the compression changed much. The compression
pass is part of the increment, not a later clean-up: an inefficient
implementation is not landed with the intention of fixing it afterwards. Each
increment's commit records the census figure.

**Why.** The compiler core for the base language measured about 15K, not the
12K the plan assumed, and the estimate for Basie's additions put the total
at 22K to 27K. A 24K limit would have forced either deferring features Basie
needs or a struggle that the incremental compression cycle handles better. 28K
keeps enough workspace for real programs, and the target keeps pressure on
every step. Compressing at every step, not at the end, is what gets a
comprehensive compiler into a small space.


### D44. Native code is ATOM source, named and commented in ATOM's style

Every native program, `BASIE.COM` and `BLINK.COM` alike, is written in the
**ATOM dialect** and assembled by ATOM alone. The compiler, first written in
AZM syntax, is converted to ATOM, and the source translation that let ATOM read
AZM is retired with it. The conversion is roadmap step 65.0, made before any
more compiler code is written, so nothing new is written twice.

The sources follow the conventions of ATOM's and Skate's own sources:

- **Labels** ([naming](naming.md), in the style of ATOM's `docs/labels.md`
  and Skate's `docs/labels.md`). Globals are
  `AREA_WHAT` in at most eight characters, made of words rather than consonant
  strings, from an approved list of short forms. Only names other routines use
  are global. Loop heads, join points, error exits and single-caller helpers
  are private `.NAMES` of the routine that owns them. There are no
  disambiguating digits and no look-alike pairs. Extent markers keep global
  names because host tools read them.
- **Commentary.** Each module opens with a header that states its purpose, its
  principal entries and its data layout. Each routine has a contract line
  (`;@ROUTINE IN … OUT … CLOBBERS …`) and a sentence on what it does. Every
  instruction carries a line comment that says why, not what.
- **Files** stay under 64K of source, ATOM's limit for one file; a module that
  outgrows it is split at routine boundaries into consecutive files.
- **File names** are 8.3 and upper case, so that the native toolchain could in
  principle be assembled on CP/M by ATOM itself. This is a goal, not yet a
  gate: it matters once ATOM's CP/M transient can hold a source tree this size.

**Order of work.** The conversion is done in two stages, each verified
byte-identical:

1. **Mechanically.** Translate the compiler into ATOM source with 8.3 names. Resolve
   the build-time conditionals for `BASIE.COM`'s one configuration, which
   removes the dead banked and proof branches. Give long names temporary
   ATOM names from a map. Assemble the result with ATOM directly to an image
   byte-identical to the AZM build.
2. **By curation, module by module.** Apply the label convention through
   rename maps, with label rename and verify tools (`tools/labels/`), and add the
   commentary. No output byte may change. `BLINK` receives the same pass.

New code is written to the convention from its first line.

**Why.** AZM is being retired across these projects. One dialect means one assembler to
trust, and no translation layer between the source and the image. Names that
fit ATOM's limits without a ledger can be read in the source, the listing and
the debugger alike. Line-by-line commentary is what keeps a 25K assembly
program reviewable through the increment, review and compression cycle of D43.

**Rejected.** Keeping AZM syntax behind the translation layer. It keeps the long
names, but it leaves two dialects, a ledger of unreadable eight-character
aliases in every listing, and contracts that nothing checks.

### D45. The native compiler's output equals the reference compiler's

From step 65.4, `BASIE.COM` writes the same `$DR`, `$BY`, `$LN` and `$NM`
streams as the reference compiler for every program it accepts, byte for
byte. The back end is rewritten to the reference's code
templates (`ref/compile/compiler.ts`, `ref/compile/emit.ts`) as each
construct is brought across. Its front end, the tokenizer, the LL(1) parser
and the actions, stays, and the semantic transcript is flushed and replayed
once per routine and top-level declaration. That way a routine's emitter
knows its frame, its need and its literals before it writes the routine.

The check is the conformance corpus. A test compiles each program the native
compiler claims with both compilers and compares the streams. Until native
branch shrinking existed (step 67c), the reference compiled with shrinking
off for this comparison; it now compiles with its default, shrinking on. The claimed set only grows: a program once claimed must keep
matching.

**Why.** The reference was built as an executable model of the native
algorithms (implementation plan). Comparing behaviour would catch a wrong
answer only when a test happens to observe it. Comparing streams catches
every divergence, in the program that first shows it. About 9K of compiler
code is still to be written, and a byte oracle is what keeps it correct. It
also makes the line streams, names and diagnostics positions match, which
behavioural tests would not see.

**Cost.** The native compiler inherits the reference's choices, including
some that are not the smallest code it could emit. An improvement to code
quality is made in the reference first and then carried across, so the two
never drift.

**Rejected.** Keeping the starting core's stack-machine templates and comparing
behaviour only. That makes it harder to find divergences, and the templates
would be rewritten anyway when D41's register conventions reach expressions.

**Amended at step 65.4 (a).** The transcript is not flushed and replayed
after all. The native compiler generates each construct's code as it parses
it, as the reference compiler does, into the blob writer's routine buffer,
which already gives the emitter what the replay was meant to: the frame is
patched into the prologue when the routine ends, the frame and need words
and the literals come after the code, and forward jumps are resolved when
their labels are defined ([native compiler](native-compiler.md) §2).

### D46. Restart vectors stay with the platform

Basie's own code never takes the Z80 restart vectors (`RST 0` to `RST 7`, in
page zero from `$0000` to `$0038`) for compression. Neither `BASIE.COM`,
`BLINK.COM`, the runtime library nor generated code installs a routine at a
restart vector or overwrites the platform's contents there to save bytes. The
vectors stay reserved for the BIOS and CP/M, and for the drivers, debuggers and
interrupt handlers the platform installs. Both CP/M profiles declare no free
restart vector ([CP/M target](cpm-target.md) §2 and §8); a warm-boot exit
through `RST 0` is a call to the platform, not a use of the vector.

**Why.** A compiler or program that replaces a vector breaks whatever the
platform put there, and the failure appears in some other program or tool, far
from its cause.

**Rejected.** Compressing `BASIE.COM` by calling its commonest emitters
(`EM_SEQ`, `EM_OP`, `DG_RAISE`) through `RST 1` to `RST 5`, which would save
about 250 bytes ([native compiler](native-compiler.md) §4). Compression uses
other means.

### D47. Traps report source positions

A trap reports where it happened in the source, in two ways (option 3 of
the choice John made on 2026-10-07):

1. **Trap lookup, always.** A trap prints its reason, the address of the call
   that trapped, and the command that finds the statement:
   `TRAP narrowing at 029D (BASIE name [T=029D])`, where `name` stands for
   the program's name, which a CP/M 2.2 program can't learn; `BASIE MAIN [T=029D]`
   reads `MAIN.LIN` and prints the part, line and column and the source line
   ([toolchain](toolchain.md) §8). The program carries nothing extra.
2. **An embedded table, by option.** Linked with the debug option, the image
   carries a compact table from addresses to parts, lines and columns, and the
   parts' names, and the runtime's trap reporter searches it and prints
   `TRAP narrowing at FILE.BSI:11:4` directly. The table costs program space
   (two to four bytes a statement, about 1-2K for a program of `ADVENT.BSI`'s
   size, and the lookup's code in the runtime), so it is off by default.

The line stream gains each statement's first column, so that both forms can
name it; the reference toolchain and the native one change together, as D45
requires.

**Why.** An address alone sends the programmer to a map. The lookup costs the
program nothing; the embedded table saves the second command when space
allows.

**Rejected.** Embedding the table always: on a CP/M machine the bytes come out
of every program's transient area.

### D58. A counted loop compared in 32 bits needs a 32-bit counter

When a counted loop's bound and its counter are compared in a 32-bit type,
`u32` or `i32`, the counter must be a 32-bit type too: `for i = 0 to n` with
`i` a `u8` or `u16` and `n` a `u32` is mixed-operands at the bound (spec §12.4),
in both compilers, as John chose on 2026-10-10. An exact bound is unaffected:
it takes the counter's type, or none.

**Why.** Neither compiler generated the 32-bit comparison for a narrower
counter: the reference stopped with an internal error and the native compiler
refused it. A program needing the range widens the counter, which costs it two
bytes of frame.

**Rejected.** Comparing a narrow counter against a 32-bit bound at run time in
both compilers: more code in each, for a loop that a wider counter writes as
plainly.

## Adopted for the next language version

D48–D52 record the 2026-10-10 directions following comparisons with
[Rust](rust-comparison.md) and Zig. Their numeric order is historical, not the
current priority. The proposed 1.0 language specification remains unchanged
until a direction has normative text and conformance tests. Each compiler
change must also pass the budget checks in D43.

The [forward plan](development-plan.md#2-selected-next-development-milestone) and
[catalogue](stretch-goals.md#priority-and-confidence) order the accepted next
milestone by value, confidence and dependencies. Call-site `var`, colon types,
restricted `try`, plain enums, exhaustive value selection and typed failure
codes are high-priority foundations. Plain enums have a clear safety purpose;
typed failures depend on them. Open-array descriptors are accepted compatibility
work before dependent slices. Temporary read-only slices need a bounded
range/lifetime prototype. Full noncapturing routine values, including storage,
have the greatest uncertainty and retain a whole-feature prototype and explicit
back-out gate. Confidence never waives measurements. Coordinate the broad source
migrations after the rules are specified.

Candidate selection is complete; design and measured admission remain open.
D50 is explicitly deferred, superseding its earlier adoption. Writable and
string slices, variants, libraries and interfaces remain deferred. Current 0.1
completion comes first; no language-feature implementation is requested now.

### D48. `try` passes a failure on

**Current status, 2026-10-10.** Accepted for the next milestone as a prefix replacement for
`else fail`, retaining the current failure-call position restrictions. The
feature is unimplemented; the current 0.1 completion scope is unchanged and no implementation is requested now.

`try` before a failable call propagates that call's failure with the same code
from the enclosing routine. It consumes one invocation's failure and requires
an enclosing routine declared `fails`.

```basie
try writeText(console, "Name? ")
var count = try parseU16(text)
count = try parseU16(otherText)
```

The call must be the complete expression initializer of a local declaration,
the complete assignment source or a complete routine-call statement. Preserve
the existing `handle` behaviour and exactly one failure consumer per call.
`try` does not propagate failures implicitly across a whole statement. Failable
calls remain forbidden inside arguments or larger expressions, including nested
`try` calls and `return try`. Successful results and cleanup on propagated
failure retain the current rules in specification §14.4.

The earlier illustration `try appendU16(report, try parseU16(text))` is outside
the accepted scope. Larger-expression failure handling remains a separate
deferred possibility, with no next-milestone nomination.

**Why.** About nine failures in ten are passed on: the library, examples and tests have 1,172 `else fail` and 120 `handle`. The commonest case should be the shortest, and `else fail` is ten characters repeated on most lines of input and output code. `try` is visible at the start of the line, like `move`, which also marks an effect before the expression it applies to. Zig and Swift use the same keyword for the same job.

**Rejected.** Implicit propagation, because every failable call would become a hidden exit. `?` after the call, because `?` already marks optional types and `new?`. `!` after the call, because one character at the end of a line is easy to miss, and readers of TypeScript, Kotlin and Swift take a trailing `!` to mean "this can't fail".

**To settle.** Prefix parsing, diagnostics and coordinated replacement of
`else fail` within the existing permitted positions. This is a spelling change,
not admission of nested failure calls or new expression positions.

### D49. A writable argument is marked `var` at the call

**Current status, 2026-10-10.** Accepted for the next-milestone plan after review.
The feature is unimplemented and does not change the
current 0.1 completion scope. It marks permission to mutate caller storage,
not ownership transfer or Rust-style exclusivity. Lease arguments and forwarded
writable-result spelling remain to settle. No implementation is requested now.

A call to a routine with a `var` parameter marks the argument:

```basie
sub update(var item as Reading, value as u16)
...
update(var current, 20)
```

The marker is required. A missing or unexpected `var` is a compile error. D17 is unchanged: `var` still marks the parameter, and `mut` was considered and declined on 2026-10-09.

**Why.** `var` in a declaration is easy to miss, and the reader of a call can't see it at all. With the marker, every call that can change the caller's data shows it where it happens, as Rust's `&mut` does.

**To settle.** The marker for a lease (`bump(var h)`, D30) and for passing on a `var` result.

### D50. `for … in` iterates over an array

**Current status, 2026-10-10.** Explicitly deferred, superseding earlier
adoption. Counted loops already express traversal; the added syntax and concepts
do not justify accepting this feature under cognitive smallness. It is not
accepted next-milestone scope and no implementation is requested. Read-only slices are
independently accepted for the next milestone; writable and string-slice extensions remain
deferred. The
sketch below retains the earlier proposal, not a current language rule.

A loop can run over an array's elements directly:

```basie
for item in readings          // item is a read-only alias to each element
    total = total + item.value
end

for var item in readings      // item is a mutable alias
    item.usable = false
end
```

The loop runs over the array's own length. A string can be iterated the same way, one byte at a time, because most whole traversals in the library walk a string. Open arrays use the length passed with them. An index can be named as well, as Zig's `for (items, 0..) |item, i|` allows:

```basie
for i, item in readings       // i counts 0, 1, 2 … as a u16
    total = total + item.value
end
```

**Earlier rationale.** Tying traversal to an object's extent could reduce mismatched loop bounds. Existing bounds checks already trap out-of-range indexing, but a shorter loop can silently omit elements. This convenience does not establish sufficient benefit to accept the additional syntax now.

**To settle.** Whether scalar elements and string bytes are bound as copies, and the index's type for arrays that fit a `u8`.

### D51. A value `select` needs `case else` unless it covers every value

**Current status, 2026-10-10.** Accepted for the next milestone. The feature is unimplemented;
the current 0.1 completion scope is unchanged and no implementation is requested now. Coverage is checked at
compile time. A selection must cover every possible subject value or have an
explicit `case else`. Intentional do-nothing behaviour must be explicit.

A `select` on an integer, character or Boolean subject must have `case else`, unless its labels cover every value of the subject's type.

**Why.** Today a value that matches no case runs nothing and passes unnoticed. Requiring `case else` makes that choice visible. Accepted next-milestone plain enums use the same exhaustiveness rule.

**To settle.** An empty `case else` is the intended explicit no-op; settle its
formal grammar. Handle-selection completeness is a separate unresolved question
and was not decided by this acceptance. The earlier suggestion to require both
`some` and `none` or `else` is not an accepted rule.

### D52. `:` in place of `as` for types

**Current status, 2026-10-10.** Accepted as a next-milestone plan item alongside D49.
Colon replaces `as` at type positions: declarations, parameters, results,
record fields and pool declarations. Typing, ownership permissions, name-first
order and single-pass parsing are preserved. Modifier placement and coordinated
migration remain to settle. The feature is unimplemented and is not current 0.1 completion
work. No implementation is requested now.

A declared name is followed by `:` and its type, in place of `as`:

```basie
var total: u32
sub distance(a: Point, b: Point): u16
record Node
    value: u16
    next: nodes?
end
```

This revises D14's choice of `as`. Name-first order and single-pass parsing are unchanged.

**Why.** The colon is shorter and familiar from TypeScript, Pascal, Rust and Zig. The earlier migration sketch grouped it with `try` (D48) and call-site `var` (D49) to coordinate rewriting the library, tests and book. D49, D52, restricted D48 and D51 are now accepted for the next milestone. Coordinate migration against their final specified rules.

**To settle.** Every place `as` appears today: declarations, parameters, results (`as var T` becomes `: var T`), record fields and pool declarations (`pool jobs as Job[1]`). Whether `as` remains anywhere. Colon has no token in Basie 1.0 (§3), so it is free to take.

### Withdrawn and deferred, 2026-10-10

Each adopted change was then tested against real Basie code, and only those that prevent a real bug, remove frequent friction or add a missing capability were kept ([stretch goals](stretch-goals.md)). `else` with a value, `defer`, default field values and block comments were withdrawn. Named record initialisers were deferred. Namespaced includes were grouped with module interfaces in the earlier next-milestone sketch. Both are now deferred in the [forward plan](development-plan.md). Shadowing stays refused (spec §5.6).
