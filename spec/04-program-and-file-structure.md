# 4. Program and file structure


## 4.1 Scope

This chapter defines the source presented in one compilation, the order of top-level declarations, the placement of executable statements, the completion of forward routine declarations, and the structural checks performed at end of input. Chapter 3 defines the byte and token streams. Chapters 5, 8, and 13 define scopes, declarations, and routines in detail.

Baton compilation is declaration ordered and streaming. The rules in this chapter require neither backtracking nor a retained whole-program syntax tree.

## 4.2 Compilation unit

A **compilation unit** is one logical Baton token stream formed from one or more ordered source parts and ending in one `EOF` token. The compiler processes that stream from beginning to end as a single ordered unit. A compilation unit supplies one outer declaration sequence; a source-part boundary does not begin a scope, clear declarations, or change declaration order. Chapter 5 defines the resulting scopes.

The structural skeleton is:

```text
compilation-unit ::= { top-level-declaration } EOF
```

The complete grammar in Chapter 17 replaces this skeleton. Its declaration productions consume the logical `NEWLINE` tokens defined in Chapter 3.

Blank and comment-only physical lines contribute no top-level item. If the final item has no physical line ending, Chapter 3 requires the tokenizer to emit its final `NEWLINE` before `EOF`.

## 4.3 Multipart compilation stream

The core Baton 1.0 compiler does not open source files, search directories, or resolve source dependencies. An external packaging layer supplies one ordered logical compilation stream through these transport-neutral events or records:

```text
begin-compilation
begin-source-part(stable-source-identity, [diagnostic-name])
source-bytes(bytes)
end-source-part
end-compilation
```

A compilation contains one or more source parts. `source-bytes` may occur repeatedly within a part; its chunk boundaries have no lexical or semantic effect. The stable source identity is unique within the compilation and remains unchanged for every diagnostic from that part. The optional diagnostic name is display metadata. Neither value is part of the Baton byte stream, creates a token or identifier, opens a scope, or otherwise participates in program semantics.

Each source part must end at a logical source boundary with delimiter depth zero. When its final source bytes do not include LF or CRLF, the compiler input layer supplies one zero-width line-ending event at the end of that part. It supplies no additional event when the part already ends with a physical line ending. Chapter 3 applies its ordinary comment, blank-line, and `NEWLINE` rules to that event. The next part therefore cannot continue a name, number, literal, comment, parenthesized expression, bracketed expression, or other token sequence from the preceding part. `end-source-part` does not emit `EOF`; only `end-compilation` does so after the final part.

Program scope, declaration order, forward completion, and every other source rule continue across source-part boundaries exactly as they do within one part. Declaration before use determines legal part order. An earlier exact forward routine signature permits the later routine references already admitted by Chapters 4, 5, and 13; the compiler does not infer signatures or construct a dependency graph.

The external packaging layer owns physical files, filenames, dependency discovery, dependency ordering, duplicate suppression, and source transport. It must resolve or reject missing physical inputs and must not present duplicate stable source identities. These are packaging failures, not Baton source diagnostics, and the core compiler need not diagnose a host filesystem failure. Baton 1.0 retains no source-level `import`, `include`, `module`, or namespace declaration.

The compiler may consume each event and byte chunk incrementally. It need not materialize a source part or the complete compilation stream. A later compiler-input or transport specification may assign a concrete binary, serial, tape, image, memory, or host representation, but that representation must preserve this event order, the source bytes, stable identities, optional names, and boundary rule. No MIME syntax, operating system, filesystem, or project-file format is part of the Baton 1.0 contract. A host build tool, serial uploader, tape or image builder, CP/M driver, or memory-resident monitor can implement the packaging layer.

The packaging layer must not add declarations, replace tokens, perform textual macro processing, or make accepted source depend on a part's physical origin. A diagnostic from multipart input must carry the stable source-part identity and the Chapter 3 position within that part, allowing the packaging layer to map it back to a physical source when such a mapping exists.

#### 4.3.1 Flat source manifest

The standard authoring convention for this abstract stream is a flat ordered manifest. Each nonblank logical line contains one physical source name. Blank lines are ignored. The build driver processes entries in their written order, resolves every name within one base directory or storage namespace selected for that build, reads the named source, and emits one source part for it. The listed name is the part's diagnostic name. Its stable source identity combines that name with the entry's position, so a driver that permits a duplicate entry can still identify each part.

The manifest has no nesting, glob patterns, variables, conditional entries, dependency discovery, or recursive import meaning. It does not enter the source-byte stream, and the Baton tokenizer never sees it. The build driver defines how physical source names and line endings are encoded; a later compiler-input specification may define concrete multipart framing. Those transport choices do not change the ordered-part contract in Section 4.3.

The driver reports a missing physical source or an unresolvable source name before compilation. It may reject a duplicate manifest entry. If it emits the duplicate instead, the compiler processes both parts in order and ordinarily reports duplicate source declarations. A forgotten dependency ordinarily produces an unknown-name diagnostic; a wrong order produces the applicable declaration-before-use diagnostic; and a forward that no later part completes fails at `EOF`. The compiler does not search for another file or reorder parts in response.

## 4.4 Top-level declarations

Only top-level declarations may appear in a compilation unit. The current Baton 1.0 declaration families are:

- named constants;
- type declarations admitted by Chapter 6;
- top-level variable declarations admitted by Chapters 6 through 8;
- forward routine declarations; and
- routine definitions.

Executable statements must appear inside a routine body. A call, assignment, conditional, loop, or `return` at top level is invalid. Baton has no implicit mainline block formed from loose statements.

## 4.5 Declaration order

Except for a routine use covered by an earlier forward declaration, each name must be declared before use. Chapter 5 defines the declaration point, visibility, and lookup rules.

This rule applies across source-part boundaries because all parts contribute to one ordered compilation unit. Moving a declaration to a later part moves it later in declaration order. Splitting a unit into more parts does not make later names visible sooner.

The types named by a constant, variable, record field, formal parameter, routine result, or forward signature must already be declared at that position. The exact scope and collision rules appear in Chapter 5. Constant-expression restrictions and initialization order appear in Chapter 8.

After a routine's complete signature has been checked, its routine name and signature are available in its body and in later declarations. This permits the body to contain a direct self-call under Chapter 13. A call to another routine whose signature has not appeared requires an earlier forward declaration.

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

Every Baton 1.0 compilation unit defines exactly one routine named `main`. Its data signature is fixed: it has no parameters and no result. It may include the `fails` effect declared by Chapter 14. The definition must have a body by `EOF`; a forward declaration alone cannot satisfy the entry rule.

Execution enters an implicit implementation startup path, which establishes every program-lifetime initial value before calling `main`. Normal completion of `main` terminates successfully. A failure returned from `main` performs the unhandled-error trap in Chapter 15. The build does not select another entry name, and Baton 1.0 defines no library-only compilation unit without `main`.

The startup entry is not a source declaration and cannot be called by source. Baton defines no source-visible reset, vector, interrupt, or alternate entry declaration.

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

The first compiler's 16 KiB core gate does not change these structural rules. Project measurements account for the code and immutable data used to enforce them, while writable tables and source maps remain in their separately reported accounts under Chapter 2.
