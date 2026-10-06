# Basie language capability gaps

Date: 2026-10-06
Status: discussion document requested by John, not a language amendment

This document examines ordinary programming operations that the proposed Basie 1.0 language cannot express directly. It concerns the full language specification, not the native compiler's unfinished implementation. Its purpose is to identify useful capabilities and explain the restrictions before selecting mechanisms or measuring implementations.

Type safety, memory safety, defined behaviour and an understandable compiler remain design goals. A restriction is not justified merely because an earlier design had it. Nor does familiarity in another language establish that a feature belongs in Basie. The question is what a programmer cannot express cleanly and what information a safe implementation would need.

The [specification](../spec/README.md) remains authoritative. The [stretch-goals brief](stretch-goals.md) records evaluation priorities and existing cost estimates. Neither document admits new syntax into the frozen 1.0 language.

## Feedback into ongoing development

This records a design discussion of 6 October 2026 as input to the ongoing development. John wants these questions to stay on the agenda and authorises committing the discussion into the main repository. This is an account of the discussion and its rationale, not a verbatim transcript.

John's direction is to recover useful programming capability through checked compiler mechanisms rather than by weakening type safety or memory safety. Open strings and open arrays are the existing example: carrying the actual extent permits reusable library operations while preserving bounds. The next questions are whether similar bounded mechanisms can support regions of objects, constructed results, caller-supplied behaviour and reusable element types.

John explicitly supports retaining enumerations, tagged unions and enumeration-indexed arrays as stretch candidates. Their benefits should be discussed separately. He does not require Pascal's whole ordinal model and does not regard public-name collisions as a sufficient reason for a module system. Naming conventions are acceptable. He also asks that familiar restrictions be reconsidered rather than automatically treated as Basie requirements.

The examples and candidate mechanisms below are suggestions raised in that discussion. They are not all endorsed language changes. John asked for the capability argument to come before cost measurement: explain what ordinary programming becomes awkward or impossible to express directly, why a safe alternative could help and what obligations it introduces. Cost figures remain provisional and implementation requires a further design decision.

For the ongoing work: finish the existing 1.0 commitments and capacity corrections while retaining this agenda. Revisit the relevant candidate when changing its subsystem, record evidence and unresolved questions here and in the design record, and avoid silently treating either an existing restriction or a suggested extension as settled authority.

## Passing part of an existing object

A parser consumes a prefix of a buffer and passes the remainder to another routine. Basie permits an open array parameter to view a complete fixed array and retain its length. It does not permit a view with a chosen starting point and extent. Open strings likewise view complete bounded-string objects rather than substrings (spec 6.2, 6.8 and 6.11).

Today the programmer passes the original buffer, an offset and a count, or copies the required region. Those separate arguments describe a region by convention. Each routine must preserve their relationship and perform the appropriate checks.

A checked slice could package the region and its bounds together. The useful capability is borrowing part of storage, not exposing an address. A narrow design could keep slices parameter-only and transient, as existing aliases are. Construction must check that the region fits without arithmetic overflow. Indexing must check its extent. A slice cannot outlive its backing storage, and pool-backed storage needs the same lifetime protection as existing aliases.

String slices need a separate decision: a read-only sequence of bytes is different from a writable bounded string whose length can change. Slicing must not silently permit mutation of another object's length or capacity. Empty regions, writable views and alias results also require explicit rules.

## Returning a constructed record or array

A routine computes a point and wants to return the result as one object. Basie's aggregate results are aliases, never fresh aggregate values. An alias cannot refer to the callee's local storage. A caller can supply a writable destination, copy an alias to longer-lived storage, or receive a pool handle instead (spec 6.5, 7.7 and 13.6).

Value returns for non-owning aggregates would let a routine construct and return a result without arranging longer-lived storage. The caller could supply hidden result storage, keeping the source operation safe without retaining a pointer to an expired local. This is a candidate mechanism, not a chosen calling convention.

Records and arrays with owning fields are a separate problem. Copying them duplicates ownership and is invalid today. Moving whole owning aggregates would require its own transfer and cleanup rules. A limited non-owning value-return feature need not imply that extension.

The design must state result evaluation order, destination placement, alias interactions, stack costs and behaviour when the routine fails. Large fixed results can be safe and still expensive to copy.

## Supplying behaviour to an algorithm

Sorting records requires a comparison operation. Tree traversal requires an action at each node. Basie routines call named routines directly. They cannot receive another routine as an argument, store routine values or capture local state in a closure (spec 13.1 and 20.4).

A specialised sorter or walker can implement the algorithm today. The restriction is separation and reuse: application behaviour becomes part of the algorithm's implementation, or the implementation is duplicated.

Two bounded alternatives deserve separate discussion. Compile-time binding of a named operation could produce direct calls in a specialised algorithm. A call-bound routine parameter could lend behaviour for one invocation without allowing it to escape. Neither requires general closures. The former raises questions about source processing and duplicated code. The latter introduces indirect calls whose signatures, failure effects, stack requirements and alias rules must be checked. A context argument may be needed to supply state without capturing a caller's frame.

## Reusing an algorithm across element types

An open array generalises length while preserving the element type. One routine can accept several lengths of Point array, but cannot thereby accept an array of unrelated FileEntry records. A typed stack, queue or sorting library therefore needs separate type-specific implementations (spec 6.2 and 6.10).

Limited type parameters could describe what is shared while keeping element types exact. This does not select C++ templates, unrestricted compile-time execution or type erasure. A useful design must state which operations are available on a parameter type and how each use is checked. Algorithms that compare elements need a way to supply comparison behaviour as well as a type.

Possible costs include specialised code copies, retained declarations and additional compilation machinery. Passing byte widths and raw addresses is not an acceptable substitute for preserving type identity and object extents.

## Composing recoverable failures

Basie already distinguishes successful results, recoverable errors and terminating safety traps. Every failable call must have one explicit consumer. It can be a complete local initializer with propagation, a complete assignment source or a complete call statement. It cannot be nested in an argument or a larger expression (spec 14.4).

A programmer therefore extracts each potentially failing operation into a separate statement before combining results. This is often clear, but imposes extra staging in parsers and pipelines. Explicit propagation within expressions could preserve checked failure handling while permitting composition. Its design must define left-to-right evaluation, the first failure, ownership transferred by earlier arguments, temporary cleanup and whether a destination remains unchanged.

This is separate from typed errors. Enumerations could distinguish error domains, and tagged unions could attach data such as an input position. Payload-bearing errors would need transfer and lifetime rules. General result values could be stored and inspected, whereas the existing failure channel is attached to an invocation. These are independent capabilities, not one required replacement of fails and handle. Safety traps remain non-recoverable unless a separate design explicitly changes that contract.

## Representing finite alternatives

An enumeration defines a distinct type with a closed set of named values. It prevents unrelated integer codes being substituted and permits exhaustive selection. A tagged union adds differently typed payloads to alternatives. A command can be Quit, Move carrying a direction, or Take carrying an item identifier.

Today a record with a numeric kind and several fields can represent these cases, but it also represents meaningless combinations. A variant constructor and checked selection can enforce the relationship between the kind and the available payload. Selection may bind the payload in the active arm and diagnose missing alternatives. This is useful pattern matching without requiring nested patterns or guards.

Enumeration-indexed arrays are a separate extension. They describe one entry per member of a finite domain and reject indices of another type. They need not introduce subranges, ordinal arithmetic or every Pascal ordinal facility. Member names, default initialisation, external numeric data, representation and array initialisation require explicit choices.

Variants containing owners must free only the active payload and preserve ownership on construction, replacement and selection. A tag plus maximum-sized payload is one representation, not a guarantee of zero runtime cost.

## Storage sized by runtime input

Fixed arrays, bounded strings and fixed-capacity pools require the program to choose storage capacities in advance. Basie has no general heap or variable-sized local allocation (spec 6.11 and 7.4). Reading an unknown document or collecting an unknown number of results therefore requires a chosen maximum, chunked processing or external storage.

This is a stronger restriction than lack of reusable syntax. Runtime-sized storage changes allocation, failure and lifetime rules. Bounded arenas, variable-sized scoped objects and resizable collections should be considered independently. An arena alone does not establish safe resizing or references into relocated objects. Pools already support dynamic structures within declared capacities and should not be described as an absence of dynamic data.

## Organising separately developed code

Include and private provide source composition and file-local implementation details. Public declarations enter one ordered namespace. John accepts naming conventions for collisions. The additional capability to consider is explicit dependencies and independently checked interfaces, not qualification for its own sake (spec 4.3 and 5.11).

Selective imports, published interfaces and precompiled libraries are different mechanisms. Each must preserve complete signatures before use, including failure effects, mutability and result lifetimes. Separate compilation also needs a compatibility contract for types, services and object files.

## Distinguishing language choices from temporary capacities

The 16-literals-per-routine table and 2,048-byte routine output buffer currently block an example. These and the fixed symbol, field and nesting tables are implementation capacities recorded in the [capacity audit](capacity-audit.md). Correcting them belongs to completing the current language, not extending it.

Language choices such as the 253-byte string capacity, unsigned indices, constant loop steps and restrictions on alias retention deserve explicit rationale. Some support compact representation, others protect lifetimes or streaming checks. Review the current contracts before treating any as either essential or arbitrary.

## Discussion priorities

Start by clarifying the source-level operations wanted: bounded region borrowing, constructing aggregate results, separating algorithms from caller behaviour and representing alternatives precisely. These can be discussed independently of an implementation budget. Then choose the smallest coherent mechanism for each accepted capability and establish its safety rules. Measurement follows that choice and determines whether the mechanism fits the native system.

No feature in this document is approved for implementation. Its completion criterion is a reasoned disposition for each candidate, with unresolved semantic questions recorded before syntax or code is adopted.

## Restart vectors must remain available to the platform

John explicitly directed that Basie must not take over CP/M restart vectors for compiler compression. Preserve the platform's vector contents and their availability to drivers, debuggers and interrupt handlers. The existing CP/M target contract already declares no free restart vectors (cpm-target.md sections 2 and 8). The documented use of RST 0 for normal warm-boot exit is a call to the platform, not permission to replace its vector. Future compression work must respect this constraint and use other mechanisms. The decision is recorded as [D46](design-decisions.md).
