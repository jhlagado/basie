# 4. Program and file structure


## 4.1 Scope

This chapter defines the source presented in one compilation, how source parts name the parts they depend on with `include`, the order of top-level declarations, the placement of executable statements, the completion of forward routine declarations, and the structural checks performed at end of input. Chapter 3 defines the byte and token streams. Chapters 5, 8, and 13 define scopes, declarations, and routines in detail.

Basiq compilation is declaration ordered and streaming. The rules in this chapter require neither backtracking nor a retained whole-program syntax tree.

## 4.2 Compilation unit

A **compilation unit** is one logical Basiq token stream formed from one or more ordered source parts and ending in one `EOF` token. The compiler processes that stream from beginning to end as a single ordered unit. A compilation unit supplies one outer declaration sequence; a source-part boundary does not begin a scope, clear declarations, or change declaration order. Chapter 5 defines the resulting scopes.

The structural skeleton is:

```text
compilation-unit ::= { top-level-declaration } EOF
```

The complete grammar in Chapter 17 replaces this skeleton. Its declaration productions consume the logical `NEWLINE` tokens defined in Chapter 3.

Blank and comment-only physical lines contribute no top-level item. If the final item has no physical line ending, Chapter 3 requires the tokenizer to emit its final `NEWLINE` before `EOF`.

## 4.3 Source parts

A compilation consists of one or more **source parts**, each a file of Basiq source. The parts come from two places:

- the **command line**, which names one or more parts in order ([toolchain](../docs/toolchain.md), Section 5); and
- **`include` lines** at the start of a part, which name the parts it depends on (Section 4.3.2).

The compiler forms one ordered logical token stream from the parts, as described below. A part boundary does not begin a scope, clear declarations, or change declaration order, except that a `private` declaration is visible only within its own part (Chapter 5).

### 4.3.1 The ordered stream

Each source part is tokenized separately under Chapter 3, starting at byte offset zero, line one and column one. Each part must end at delimiter depth zero. When a part's final bytes do not include LF or CRLF, the compiler supplies one zero-width line-ending event at its end; it supplies none when the part already ends with a physical line ending. Chapter 3 applies its ordinary comment, blank-line and `NEWLINE` rules to that event, so a part cannot continue a name, number, literal, comment or delimited expression into the next. Only the end of the last part produces `EOF`.

Each part has a **stable source identity**: its drive and file name in upper case, as `B:STRINGS.BSQ`. Two parts with the same identity are the same part. Every diagnostic from a part carries its identity and the Chapter 3 position within it. The source parts of one compilation are numbered from 0 in stream order, and the line stream records each part's identity under its number ([object format](../docs/object-format.md), Section 8).

Program scope, declaration order, forward completion and every other source rule continue across part boundaries exactly as within one part. Declaration before use therefore determines legal part order. The compiler does not infer signatures, construct a dependency graph or reorder declarations.

The compiler may read each part incrementally. It need not hold a whole part, or the whole stream, in memory.

### 4.3.2 `include`

A part may begin with `include` lines, each naming another part it depends on:

```text
include-line ::= "include" string-literal NEWLINE
```

```nucleus
include "STRINGS.BSQ"
include "FORMAT.BSQ"

sub main() fails
    ...
end
```

Rules:

1. **Position.** `include` lines must come before the part's first declaration. Blank and comment lines may precede or separate them. An `include` after a declaration is an error.
2. **Names.** The string is a CP/M file name, `[d:]name.type`, with the type required; it is converted to upper case. A name without a drive is looked for first on the drive of the including part, then on the library drive (option `L=`, by default `A:`). The first file found is the part. A name not found on either drive is an error at the `include` line.
3. **Order.** When the compiler reaches an `include` line, it compiles the named part, including that part's own `include`s first, before reading the rest of the including part. Each included part is therefore compiled before every part that includes it, and the stream order is the depth-first order in which parts are first reached.
4. **Once only.** A part already in the stream is not compiled again; a later `include` of it has no effect. This applies equally to parts named on the command line: a command-line part already included by an earlier part is skipped.
5. **Cycles.** An `include` of a part that is still open (one whose `include` lines are being processed, directly or through other parts) is an error, `include-cycle`, at the `include` line.

`include` names files; it does not import names selectively, create a namespace or qualify names. Every non-`private` declaration of an included part is visible to every later part, whether or not that part included it. Chapter 5 defines `private`.

The compiler itself opens included files; there is no separate manifest or packaging format.

### 4.3.3 Capacity

An implementation may bound the number of parts, the depth of open includes and the length of a part. `BASIQ.COM` publishes its limits in the [limits register](../docs/limits.md). Exceeding one is a capacity diagnostic.

## 4.4 Top-level declarations

Apart from `include` lines at the start of a part (Section 4.3.2), only top-level declarations may appear at top level. The Basiq 1.0 declaration families are:

- named constants (Chapter 8);
- record type declarations (Chapter 6);
- pool declarations and forward pool declarations (Chapters 7 and 8);
- top-level variable declarations (Chapters 6 to 8);
- forward routine declarations; and
- routine definitions (Chapter 13).

Any top-level declaration may be marked `private` (Chapter 5).

Inside a routine body, constants and variables may also be declared at any statement position, with block scope (Chapter 5, design decision D28). Record types, pools and routines are declared only at top level.

Executable statements must appear inside a routine body. A call, assignment, conditional, loop, or `return` at top level is invalid. Basiq has no implicit mainline block formed from loose statements.

## 4.5 Declaration order

Except for a routine use covered by an earlier forward declaration, each name must be declared before use. Chapter 5 defines the declaration point, visibility, and lookup rules.

This rule applies across source-part boundaries because all parts contribute to one ordered compilation unit. Moving a declaration to a later part moves it later in declaration order. Splitting a unit into more parts does not make later names visible sooner.

The types named by a constant, variable, record field, formal parameter, routine result, or forward signature must already be declared at that position. The exact scope and collision rules appear in Chapter 5. Constant-expression restrictions and initialization order appear in Chapter 8.

After a routine's complete signature has been checked, its routine name and signature are available in later declarations. A call to a routine whose definition has not yet been completed, including a call from a routine to itself, requires an earlier forward declaration: every cycle of calls must pass through a forward-declared routine, which carries the activation-capacity check (Chapter 13, and [memory safety](../docs/memory-safety.md), Section 7).

For example, this order satisfies the structural rules:

```nucleus
forward sub emit(value as u8)

sub run()
    var value as u8
    emit(value)
    return
end

sub emit
    return
end
```

The following order does not, because `emit` has no visible signature at the call:

```nucleus
sub run()
    emit(0)
    return
end

sub emit(value as u8)
    return
end
```

These examples establish declaration order only. Later chapters determine the remaining type, initialization, call, and return validity.

## 4.6 Forward routine declarations

A forward routine declaration supplies a routine signature without a body. It is the only source-language exception to ordinary declaration before use. It must appear at top level before the first use that depends on it.

The parameter and result types in a forward declaration must already be available. Once checked, the declaration makes the routine callable at later positions under the same rules as a routine whose body has already appeared. It creates no executable statement and does not begin a routine body.

The forward declaration is the complete and sole signature. It records the routine name, parameter names and ordered types, optional result type, and `fails` effect. The later body begins with the abbreviated header `sub NAME` followed by a logical newline. That name must resolve to exactly one incomplete forward. The parameters named by the forward become the parameter bindings in the body; the body cannot rename or redeclare them.

A routine may have at most one forward declaration and exactly one definition. A second forward declaration, a forward declaration after the definition, a second definition, an abbreviated body without an incomplete forward, or a completion with another name is invalid. Completing a forward declaration does not declare a second routine. An ordinary routine without a forward retains the complete parenthesized header defined in Chapter 13.

Forward declarations apply only to source routines. They do not provide a general forward reference for constants, types, variables, fields, or local names.

## 4.7 Program entry

Every Basiq 1.0 compilation unit defines exactly one routine named `main`. Its data signature is fixed: it has no parameters and no result. It may include the `fails` effect declared by Chapter 14. The definition must have a body by `EOF`; a forward declaration alone cannot satisfy the entry rule.

Execution enters an implicit implementation startup path, which establishes every program-lifetime initial value before calling `main`. Normal completion of `main` terminates successfully. A failure returned from `main` performs the unhandled-error trap in Chapter 15. The build does not select another entry name, and Basiq 1.0 defines no library-only compilation unit without `main`.

The startup entry is not a source declaration and cannot be called by source. Basiq defines no source-visible reset, vector, interrupt, or alternate entry declaration.

Program startup, initialization, termination, and system services are specified in Chapters 16 and 19.

## 4.8 End of input and duplicate completion

`EOF` ends the compilation unit; it does not close an open declaration or block. Reaching `EOF` before a required `end`, closing delimiter, declaration terminator, or routine body is complete makes the source invalid. Chapter 3 handles unclosed lexical delimiters before the parser receives `EOF`.

At `EOF`, the compiler must verify that:

- every forward routine declaration has one abbreviated body definition;
- every routine has at most one body;
- no top-level declaration remains structurally incomplete; and
- exactly one defined `main` satisfies Section 4.7.

The compiler may diagnose a duplicate declaration or mismatched completion as soon as it encounters the later declaration. It must not defer a detectable error merely because end-of-input validation also covers the condition. After any structural error, the initial compiler may stop under the diagnostic policy in Chapter 1; it must not report a successful translation.

## 4.9 Capacity limits and source parts

Documented compiler capacities apply to the complete logical compilation unit. A source-part boundary must not reset a symbol count, forward-signature count, nesting limit, or other unit-wide resource. Dividing the same ordered source among more parts neither increases a language-defined capacity nor creates extra scopes. Chapter 3 source-position counters restart for each part because diagnostics use part-relative positions.

An implementation may bound the complete logical source length, source-part count, source-identity or diagnostic-name length, number of declarations, number of unresolved forwards, or other storage required by this chapter. It must document each limit and issue a capacity diagnostic when the limit is exceeded. Under Chapter 1, that diagnostic does not make an otherwise conforming source program invalid.

The compiler's size budget (Chapter 2, design decision D9) does not change these structural rules.
