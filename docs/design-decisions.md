# Baton design decisions

- Status: working record
- Date: 2026-10-04

This document records the language decisions made so far, with the reasons for
each, and the questions still open. Where Baton keeps a Nucleus rule unchanged,
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

Baton keeps Nucleus's lexical rules (§3.4):

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
  operation. Baton treats denormal inputs as zero and returns zero for results
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

Baton allows records, arrays and bounded strings as routine locals, living for
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

- **`BATON.COM`**, the compiler, at most **24K** including its tables, which
  leaves at least **32K** of working space on a CP/M 2.2 system with 56K free;
  and
- **`BLINK.COM`**, the linker, which `BATON` runs automatically when compilation
  succeeds. CP/M 2.2 has no call to run another program, so `BATON` copies a
  small loader to the top of memory, which reads `BLINK.COM` into place and
  starts it, as Turbo Pascal's `Execute` did. The user still types one command,
  and the linker gets nearly the whole program area for its tables.

Ways the compiler is kept within budget:

1. It is built on the 12K Nucleus compiler rewrite.
2. 32-bit and `f32` operations are generated as calls to runtime helpers, never
   inline, so the compiler only checks types and selects helpers.
3. Diagnostic message text lives in a message file, `BATON.MSG`, read only when
   a diagnostic is reported.
4. Rarely used parts, starting with decimal-to-`f32` literal conversion, are
   overlays loaded only when needed.
5. Strings, formatting and other library facilities are Baton source libraries,
   compiled with the program and tree-shaken, not compiler features.
6. Features are deferred to version 2 when they don't fit (D24).

Every feature is costed in compiler bytes and in generated-code bytes before it
is adopted, and the measurements are published, as Nucleus did.

### D10. Target machine

Baton programs and the Baton toolchain target a Z80 with 64K of RAM running
**CP/M 2.2**, which is the primary target; CP/M 3 is supported where it costs
nothing extra. TEC-1 ROM and other bare-machine targets are **not** design
considerations: features, formats and services are not shaped for them. Storage
is high-capacity: 720K or larger floppies
(1.2M and 1.44M high-density formats, the Triptych system's 2M disks) or a hard
disk. A single drive is enough to build any program. Early low-capacity
formats, such as 90K to 250K floppies, are not supported for large builds.

**Why.** It removes disk space as a design constraint on the build pipeline,
which writes temporary spools comparable in size to the program. Memory, not
disk, is the scarce resource Baton is designed around.

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
declaration and is familiar from TypeScript, Pascal, Go and Rust. But Baton
already has enough punctuation that a bare colon doesn't say what it does,
while `as` reads as a phrase, especially where modifiers stack up
(`var list as nodes?`), and keeps the BASIC character. The compiler cost
is the same either way.


### D15. One `match` statement

Baton has a single selection statement, `match`, instead of a BASIC-style
`select` alongside a separate pattern-matching form. Rust's `match` is a
superset of `SELECT CASE`, so one statement covers both:

- integer and character constants, lists of them, and ranges (`'0' to '9'`),
  with `case else`;
- enumerations, with a check that every value is covered unless there is a
  `case else`;
- optional handles and identifiers: `some(x)` when there is a live value,
  `none` when there isn't. For an identifier, `none` covers both an empty
  identifier and one whose slot has been freed, so testing never traps; and
- in version 2, variants whose cases carry data (D24).

When the subject of a `match` is an owning local, `some(n)` gives direct,
unchecked access to the node, as a lease does; for any other subject it binds an
identifier. `match move x` moves the value out of `x` and, in `some(n)`, binds
`n` as a non-optional owning local, which is how a `nodes?` becomes a `nodes`.

```nucleus
match key
case 'q', 'Q'
    exit
case '0' to '9'
    digit(key - '0')
case else
    beep()
end
```

There is no fall-through. `match` is a statement; using it as an expression
waits on expression blocks (O3). Nested patterns and guards are left out to keep
the compiler small. See the [feature inventory](feature-inventory.md),
Sections 3 and 4.

**Why.** Two statements would mean two parsers, two rule sets and two things to
learn, when one does everything both would. The parts share one dispatch and
one exhaustiveness mechanism, so building them together costs less than adding
them separately.

### D16. No aliases into pool storage

Pool records are reached only through handles, never through aliases:

- every access through a handle or identifier is one checked operation,
  resolved after all of its operands are evaluated, so nothing can free the
  slot between the check and the access;
- aggregate fields of pool records are copied out, not passed by alias;
- `match` on an optional handle binds an identifier, except that a match on
  the caller's own owning local gives direct access, as a lease does (D15);
- a `var` parameter of record type may be bound to a node held in the
  caller's own owning local, giving direct access for the call (D30); and
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
Baton passes every aggregate by reference anyway.

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
must be tested with `match` before use, and it must be expressible wherever a
type appears: fields, variables, parameters, results and array elements
(`owners as nodes?[32]` is an array of 32 optional handles). A marker on the
name could not express a result or an element type.


### D23. One pool per record type is the expected style; no generics in 1.0

A pool is storage, not a container: any number of lists, trees or graphs can
share one pool. Programs normally declare one pool per record type, so code
written for that pool's handles serves every structure in it. Baton 1.0 has no
generics; Pascal never had them either.

### D24. Version 1 scope

Version 1 includes the Nucleus core and: signed and 32-bit integers, `f32`,
shifts and bitwise operators, `match` on integers, characters, enumerations and
optional handles, enumerations, local aggregates with `from`, `var` parameters,
pools and handles with `move`, and services for I/O.

Deferred to **version 2**: variants whose cases carry data, expression blocks
(O3), arenas (O4), routine values (O5), default parameter values (O6) and
generics (D23).

**Why.** The deferred features are the largest compiler costs that ordinary
programs can do without, and the version 1 set fits the 24K budget (D9).

### D25. Strings: bounded strings and a Baton library

Baton keeps Nucleus's strings: `string[N]` with a fixed capacity of at most 253
and a current length; string literals as constants and as direct arguments; and
open `string[]` parameters, which accept any capacity and can read `.capacity`
and set `.length`. String building, comparison, searching and conversion between
numbers and text, including `f32`, are a **standard library written in Baton**,
compiled with the program and tree-shaken, not compiler features.

Raising a string's length makes the bytes it exposes zero, so a local string can
be initialised by zeroing only its length byte.

### D26. Failure codes may be named by an enumeration

A failable routine still reports a `u8` code, as in Nucleus, but may name the
enumeration its codes come from: `sub open(name as string[]) fails FileError`.
The compiler then checks that `fail` and `handle` use that enumeration's values.
Richer error values carrying data wait for variants (D24).

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
`if` or `match` arm, or a loop body). Owning locals are freed at the end of that
block.

**Why.** The ownership patterns declare handles where they are made, and block
scope gives every owning local an exact end.

### D29. `id` is a contextual word

`id` is a keyword only before a pool name in a type. Elsewhere it is an ordinary
identifier, so `id` remains usable as a field or variable name.

### D30. Direct access to a node is a `var` record parameter

A `var` parameter of record type, `var n as Node`, accepts any `Node` the caller
can change: one in program or activation storage, or the node held by one of the
caller's own owning locals of a pool of `Node`. Inside, the routine has direct,
unchecked access. For a node, the rules of a lease apply: the argument must be
the caller's own owning local, and that local may not appear anywhere else in
the same statement except as `id(n)`. This replaces the separate parameter kind
`var h as nodes`.

## Open

### O1. Exclusivity (resolved)

Resolved by D16 and D17: Baton has no exclusivity rule. Overlapping aliases to
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
