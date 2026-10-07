# Basie stretch goals

Date: 2026-10-06
Status: evaluation brief, not a language amendment

These candidates are retained for evaluation if the completed native compiler has spare capacity. The Basie 1.0 specification remains authoritative and its feature list remains frozen. Earlier evaluation is permitted as an isolated experiment. Admission requires a design decision and corresponding specification and conformance changes. Existing version 2 plans are the starting point, not a promise to implement everything.

## Establish the capacity first

Complete the existing native language work and capacity corrections before spending the remaining budget on extensions. Measure the resident image, overlay area, writable workspace and stack separately. Account for generated program bytes, runtime helpers and disk latency as well as compiler size. Spare COM bytes alone do not establish spare RAM or acceptable performance.

## Candidates

| Candidate | Capability to evaluate | Cost evidence |
| --- | --- | --- |
| Nominal enumerations | A closed set of named values with exact type checks and exhaustive selection. Decide member naming, zero initialisation and boundary conversions explicitly. | No separate measured estimate. The feature inventory estimates enums and variants together at 1.7–2.7K. |
| Tagged unions or variants | Alternatives carrying different typed payloads, with selection binding only the active payload. Establish construction, mutation, alias lifetimes and automatic freeing of owning payloads. | The same combined 1.7–2.7K estimate, unmeasured. |
| Enumeration-indexed arrays | A finite table indexed by its declared enum type. Reject unrelated indices and evaluate complete initialisation. | No estimate yet. Evaluate independently from enums and variants. No implied adoption of subranges, ordinal arithmetic or Pascal's whole ordinal system. |
| Typed failure codes | Distinguish error domains while retaining explicit consumption and propagation. Evaluate payload-bearing errors separately. | The inventory estimates enum-named failure codes at 0.1K. This does not estimate rich errors with payloads. |
| Checked array slices | Pass a contiguous portion of existing storage with its extent, preserving element type, bounds and lifetime. Evaluate call-only views first. | No measured estimate. Include descriptor handling, range checks, parameter binding and generated code. |
| Limited type parameters | Reuse algorithms across element types while preserving static checks. Start with a concrete library need that open views cannot express. | General generics have an unmeasured 1–2K estimate. No selected mechanism or committed syntax. |
| Routine values | Pass an operation to an algorithm, for example a comparison to a sorter. Investigate non-capturing routines first and distinguish them from closures. | Unmeasured 0.5–1K inventory estimate. Account for failure effects, signatures, stack bounds and ownership. |
| Explicit module interfaces | Describe dependencies and support independently checked or compiled units. Dependency clarity and independent checking are the motivations. Naming conventions already address many collisions. | Precompiled libraries have an unmeasured 1–2K estimate. This is not a measured module-system cost. |
| Lighter failure propagation | Let a failable call inside a `fails` routine pass its failure on without writing `else fail` on every line. Compare three forms: implicit propagation, where the routine's `fails` is the only marker (as Java's checked exceptions); a trailing `?` on the call (as Rust's `?`); and today's explicit `else fail`. `handle` stays for calls treated differently, and a routine not declared `fails` still refuses an unconsumed failure. | Small: in both compilers the failure-unconsumed check becomes the jump `else fail` already emits. A trailing `?` also needs its reading settled against `?` for optional handles. |
| Shadowing | Let a parameter or local reuse a name visible where it is declared, the innermost declaration winning, as most block-structured languages allow. Today §5.6 refuses it (`shadowed-name`), so every program-wide name, and every public name of an included library part, is unavailable to locals and parameters everywhere after it, which surprises newcomers and grows with the library. Compare full shadowing with a middle course: locals and parameters may hide program and part bindings and predeclared names, but not an enclosing local or a parameter. Decide whether the compiler warns, how a hidden predeclared routine is reached, and what replaces §5.6's argument that lookup order affects only speed. | Small in both compilers: the `shadowed-name` check goes, and lookup must find the innermost binding first. The native symbol table searches its block scopes from the innermost already; the hashed table planned for 67h should keep that order possible. |

Open strings and open arrays already generalise capacity or length. They do not generalise the element type or permit an operation to be supplied by the caller. Before adding type parameters, demonstrate why a concrete Basie library cannot be expressed adequately using existing views and ordinary routines. Evaluate single-pass checking, code duplication, object-format implications and the native compiler's storage needs. C++ template machinery is not the requested model.

## Safety arguments for enums and slices

### Named alternatives and payloads

Enumerations prevent mixing unrelated numeric codes. Tagged unions additionally tie each alternative to its permitted data. A command represented by a numeric tag and unrelated record fields permits combinations such as a quit command with an item payload. A checked variant permits construction and access only for the selected alternative. Exhaustive selection can expose omitted cases when the type changes.

Evaluate plain enums separately from payload-bearing variants and enum-indexed arrays. Variants need rules for replacing an active payload, transferring owners, releasing owned descendants and preventing access to an inactive payload. Their storage can be a tag plus space for the largest alternative, so variants do not inherently require heap allocation. Payloads may still contain allocated objects. Basie's existing optional handles and checked failure handling remain useful mechanisms without general variants.

### A portion of an existing array

Open array parameters already let one routine process complete fixed arrays of different lengths. A checked slice would extend that capability to a contiguous portion, for example the occupied prefix of a fixed-capacity input buffer or a range of records being sorted. Today a buffer plus offset and count leaves more of the range relationship to application code. A slice would bind the starting location and extent as one checked argument.

Keep three quantities separate: reserved capacity, logical number of occupied elements and extent available through a particular view. Variable logical length can use fixed storage plus a count. It does not require a growable heap vector. A slice provides access to storage whose ownership remains elsewhere.

A bounded first design could allow slices only as routine arguments with call-length validity. Check range construction and indexing, preserve read-only or writable parameter permissions and prohibit a view escaping its storage lifetime. Specify empty ranges, endpoint conventions, nesting and arithmetic overflow. A descriptor must be constructible only from valid storage and a checked extent.

Writable slices require an explicit alias policy. Basie's current read-only tickets restrict writes through that path but do not globally freeze the object. Rust's prohibition on overlapping mutable borrows must not be assumed to exist in Basie. Evaluate whether existing alias semantics suffice or whether stronger exclusion is required for the proposed operation. A split into provably disjoint writable ranges is a separate candidate with its own checking and representation costs.

Use a fixed-buffer utility as the first comparison: process an occupied prefix, produce output in caller-provided storage and report the number of elements written. Compare the current buffer/offset/count interface with checked views at equivalent behaviour. Measure compiler bytes, descriptor workspace, generated bounds checks and runtime cost. Growable vectors, stored references, closures and general type parameters are separate extensions.

These proposals record capabilities for future evaluation, not an implementation commitment.

## Audit implementation restrictions separately

A temporary compiler table size must not become a language restriction by default. The existing capacity audit already records replacements and acceptance minima. Complete that work regardless of whether stretch features are admitted.

At the observed commit c1384bc, examples reach the 16-literals-per-routine table and the 2,048-byte routine blob buffer. Other audit entries include the shared 96-entry symbol table, 32 routine records, 64 parameters across the program, 48 fields across records, eight control frames and sixteen expression-stack entries. These are implementation capacities to review against current contracts, not suggested language limits.

For semantic restrictions, review the current rationale rather than presuming it: the 253-byte string capacity, unsigned indexing, constant loop steps, restricted failure-call positions, non-storable aggregate aliases and lack of routine values. Some protect the lifetime model or single-pass checking. Others may be representation conveniences. Changing one requires evidence and explicit design work. Preserve type safety, memory safety and defined behaviour throughout.

## Required result of an evaluation

Use one representative application or library and compare equivalent behaviour. Report the capability gained, compiler and program costs, overlay traffic, remaining capacities and safety proof obligations. Record a recommendation to adopt, defer or reject the candidate. Do not present the inventory's estimates as measured costs or use a new feature to postpone capacity defects.

References: [feature inventory](feature-inventory.md), [design decisions](design-decisions.md), [capacity audit](capacity-audit.md), [limits](limits.md) and [specification authority](../spec/01-status-and-conformance.md).

The [language capability discussion](language-capability-gaps.md) develops the everyday programming restrictions behind these candidates, including checked slices, aggregate value returns and composition of failing calls.
