# Basie stretch goals

Date: 2026-10-06
Status: evaluation brief, not a language amendment

John requested these candidates be retained for evaluation if the completed native compiler has spare capacity. The Basie 1.0 specification remains authoritative and its feature list remains frozen. Earlier evaluation is permitted as an isolated experiment. Admission requires a design decision and corresponding specification and conformance changes. Existing version 2 plans are the starting point, not a promise to implement everything.

## Establish the capacity first

Complete the existing native language work and capacity corrections before spending the remaining budget on extensions. Measure the resident image, overlay area, writable workspace and stack separately. Account for generated program bytes, runtime helpers and disk latency as well as compiler size. Spare COM bytes alone do not establish spare RAM or acceptable performance.

## Candidates

| Candidate | Capability to evaluate | Cost evidence |
| --- | --- | --- |
| Nominal enumerations | A closed set of named values with exact type checks and exhaustive selection. Decide member naming, zero initialisation and boundary conversions explicitly. | No separate measured estimate. The feature inventory estimates enums and variants together at 1.7–2.7K. |
| Tagged unions or variants | Alternatives carrying different typed payloads, with selection binding only the active payload. Establish construction, mutation, alias lifetimes and automatic freeing of owning payloads. | The same combined 1.7–2.7K estimate, unmeasured. |
| Enumeration-indexed arrays | A finite table indexed by its declared enum type. Reject unrelated indices and evaluate complete initialisation. | No estimate yet. Evaluate independently from enums and variants. No implied adoption of subranges, ordinal arithmetic or Pascal's whole ordinal system. |
| Typed failure codes | Distinguish error domains while retaining explicit consumption and propagation. Evaluate payload-bearing errors separately. | The inventory estimates enum-named failure codes at 0.1K. This does not estimate rich errors with payloads. |
| Limited type parameters | Reuse algorithms across element types while preserving static checks. Start with a concrete library need that open views cannot express. | General generics have an unmeasured 1–2K estimate. No selected mechanism or committed syntax. |
| Routine values | Pass an operation to an algorithm, for example a comparison to a sorter. Investigate non-capturing routines first and distinguish them from closures. | Unmeasured 0.5–1K inventory estimate. Account for failure effects, signatures, stack bounds and ownership. |
| Explicit module interfaces | Describe dependencies and support independently checked or compiled units. Naming collisions alone are not the motivation: John accepts naming conventions. | Precompiled libraries have an unmeasured 1–2K estimate. This is not a measured module-system cost. |

Open strings and open arrays already generalise capacity or length. They do not generalise the element type or permit an operation to be supplied by the caller. Before adding type parameters, demonstrate why a concrete Basie library cannot be expressed adequately using existing views and ordinary routines. Evaluate single-pass checking, code duplication, object-format implications and the native compiler's storage needs. C++ template machinery is not the requested model.

## Audit inherited restrictions separately

A temporary Nucleus table size must not become a language restriction by default. The existing capacity audit already records replacements and acceptance minima. Complete that work regardless of whether stretch features are admitted.

At the observed commit c1384bc, examples reach the 16-literals-per-routine table and the 2,048-byte routine blob buffer. Other audit entries include the shared 96-entry symbol table, 32 routine records, 64 parameters across the program, 48 fields across records, eight control frames and sixteen expression-stack entries. These are implementation capacities to review against current contracts, not suggested language limits.

For semantic restrictions, review the current rationale rather than presuming inheritance: the 253-byte string capacity, unsigned indexing, constant loop steps, restricted failure-call positions, non-storable aggregate aliases and lack of routine values. Some protect the lifetime model or single-pass checking. Others may be representation conveniences. Changing one requires evidence and explicit design work. Preserve type safety, memory safety and defined behaviour throughout.

## Required result of an evaluation

Use one representative application or library and compare equivalent behaviour. Report the capability gained, compiler and program costs, overlay traffic, remaining capacities and safety proof obligations. Record a recommendation to adopt, defer or reject the candidate. Do not present the inventory's estimates as measured costs or use a new feature to postpone capacity defects.

References: [feature inventory](feature-inventory.md), [design decisions](design-decisions.md), [capacity audit](capacity-audit.md), [limits](limits.md) and [specification authority](../spec/01-status-and-conformance.md).

The [language capability discussion](language-capability-gaps.md) develops the everyday programming restrictions behind these candidates, including checked slices, aggregate value returns and composition of failing calls.
