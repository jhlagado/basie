# Basie stretch-goals catalogue

Updated 2026-10-10. The current toolchain development line is **0.1**; **1.0**
is reserved for eventual language stabilization. The previously named "version
two" scope is the **next development milestone**, without an assigned release
number. This naming change preserves every accepted, deferred and rejected
disposition below.

This is the single catalogue of selected next-milestone directions,
deferred possibilities and rejected proposals. The selected planning scope is:
call-site `var`, colon types, restricted `try`, plain enums, exhaustive value
selection, typed failure codes, the open-array descriptor correction and
temporary read-only array slices. Full typed noncapturing routine values are
also included provisionally, with a whole-feature prototype and explicit
back-out gate. Candidate sorting is complete for this review.

Plan selection is distinct from implementation admission. Specification,
prototype safety and measured budgets remain required; no feature implementation
is requested now. The [forward development plan](version-2.md) defines admission
and dependencies. The [proposed 1.0 language specification](../spec/01-status-and-conformance.md)
remains authoritative for current programs and remains a working draft. Its
feature-selection freeze for completion work is separate from formally freezing
the specification. Nothing here changes the immediate current 0.1 completion scope.

**Indefinitely deferred** means potentially useful but without an implementation
commitment or scheduled release. A representative program may justify renewed
evaluation. **Rejected** means excluded by the latest decisions. Reconsideration
requires an explicit new decision, not merely spare compiler bytes.

## Review checkpoint

The larger-feature and syntax discussions are complete. No implementation nomination follows
from completing that review. Current dispositions are:

| Item | Recorded disposition |
| --- | --- |
| Required call-site `var` | Accepted next-milestone plan item after renewed review; unimplemented, with no request to implement or change to current 0.1 completion scope. |
| Colon type syntax | Accepted next-milestone plan item alongside call-site `var`; unimplemented, with modifier placement and coordinated migration still to settle. Current 0.1 scope is unchanged. |
| Restricted `try` | Accepted next-milestone prefix replacement for `else fail` within current call positions; unimplemented. Nested failable calls and general expression use are outside scope. |
| Plain enums and enum-typed failures | Accepted next-milestone directions: enums first, then typed failures. Separate design completion and measured budgets remain required; unimplemented, with no change to current 0.1 completion scope. |
| Exhaustive value selection | Accepted next-milestone plan item: compile-time whole-domain coverage or explicit `case else`. Empty default is intended; formal grammar remains to settle. Handle completeness is undecided. |
| Open-array descriptor correction | Accepted next-milestone compatibility/capacity work before dependent slice and array extensions. Preserve address/extent calls and ownership/view/lease rules; verify types, diagnostics and workspace. |
| Temporary read-only array slices | Accepted next-milestone direction: checked subrange arguments for typed open-array routines, with no copy. Bounds, empty ranges, arithmetic, nesting and lifetime/lease rules require specification and measurement. |
| Full typed noncapturing routine values | Provisionally accepted next-milestone scope: parameters, variables and record fields. Evaluate and prototype the whole feature; back out explicitly if complexity or measured budget is unacceptable. |
| `for … in` | Explicitly deferred, superseding earlier adoption. Counted loops remain; it is not accepted next-milestone scope. |
| Libraries and interfaces | Deferred; no active implementation project. |
| Mutable array slices, string slices and payload variants | Separately deferred. |
| Named record initialisers | Explicitly deferred; no current next-milestone nomination. |
| Scoped storage and arenas | Retain as deferred stretch goals. |
| Default parameter values; `repeat` and general `loop` | Explicitly deferred. |
| Fresh non-owning aggregate value returns | Rejected; earlier deferral superseded. |
| Closures | Excluded from the language direction. |

The selected next-milestone scope is recorded above. `for … in` remains deferred, and full
routine values have a provisional back-out gate. Semantics, dependency ordering
and measured implementation admission still require work. Complete the current
0.1 toolchain contract before implementing the next milestone.

## Evaluation criteria

Cognitive smallness is the primary admission criterion in the forward plan.
A concrete safety or capability gain in real Basie algorithms must justify added
concepts, special cases and interacting rules. Compare equivalent behaviour and
the clearest existing statement-based alternative. An adequate existing form
remains the preferred design. Admission requires strong evidence for duplicate
spellings, parallel statement and expression forms and subtle syntax. Assess
frequent friction and clarity through those examples. Elegance or compact
implementation alone does not justify a feature.

Compiler bytes and measured machine costs remain independent constraints after
that conceptual test. Spare capacity does not authorise language complexity.

The recorded 2026-10-10 comparison used the library, examples and book code,
37 files and about 1,900 lines. Compiler tests served a different purpose and
were excluded from that comparison. Those counts describe the evidence behind
the dispositions, not limits on the language or permanent usage statistics.
A larger application may justify a deferred feature.

Complete current 0.1 conformance and capacity work before extensions. A bounded
prototype follows a worthwhile source-level comparison. Measure resident code,
immutable data, overlay file and window, workspace, stack, generated and runtime
bytes, compilation time and disk latency. Preserve type and memory safety,
single-pass compilation and D43's 26 KiB target and 28 KiB limit. Spare COM bytes
alone do not establish spare memory or acceptable performance.

The result must be an explicit adopt, defer or reject decision. The
[plan's admission process](version-2.md#5-evaluation-and-admission) governs it.
All cost ranges below are provisional and unmeasured.

## Accepted next-milestone directions

The selected scope below has no implementation slot during current 0.1 completion.
Enums precede typed failure codes. The open-array descriptor correction precedes
dependent slice and array extensions. Full noncapturing routine values require
a whole-feature prototype and an explicit back-out decision if their complexity
or measured costs are unacceptable. Libraries and interfaces remain deferred.
Evaluation priority is distinct from permission to implement.

### Priority and confidence

The accepted scope is ordered by safety value, design confidence and dependencies.
The following tiers are planning priorities, not a fixed implementation sequence
or permission to start before current 0.1 completion.

| Tier | Scope | Rationale and remaining gate |
| --- | --- | --- |
| 1. Dependable foundations | Call-site `var`, colon types and restricted whole-call `try`; plain nominal enums, exhaustive value selection and then typed failure codes | Clearer calls and declarations; distinct code domains and explicit coverage. Plain enums are a high-confidence accepted safety feature. Settle syntax, representation, conversions, coverage and error domains; verify each compiler budget. |
| 2. Compatibility correction | Open-array descriptors | Correct an existing element-type restriction before dependent slice or array extensions. Verify matching, stride, scoped descriptors, diagnostics, workspace and call compatibility. |
| 3. Bounded capability | Temporary read-only array slices | Checked subranges and copy avoidance through existing typed open-array calls. Specify and prototype range arithmetic, empty views, nesting and lifetime/lease rules; measure all costs. |
| 4. Greatest uncertainty | Full typed noncapturing routine values, including parameters, variables and record fields | Reusable and stored behaviour needs broader signature, initialisation, stack and linker proofs. Prototype the whole feature and explicitly back out if complexity or measured budget is unacceptable. |

The enum, exhaustiveness and typed-failure cluster is high priority; typed
failure codes depend on enums. Descriptor corrections must precede dependent
slice work even though they appear in a separate tier. Coordinate `var`, colon
and `try` migrations once their rules are settled to avoid repeated source churn.
High confidence does not waive normal budget verification or resolve every
semantic detail. Every accepted change remains subject to the
[plan's admission gate](version-2.md#5-evaluation-and-admission).

### Earlier directions and current dispositions

D48 to D52 record earlier adopted directions for the next development milestone
in their original decision order, not current priority.
D49, D52, D48 and D51 are assigned to the next-milestone plan. D50 is explicitly deferred,
superseding its earlier adopted direction. The complete selected planning scope
is recorded above. None of these decisions amends the current working draft.

| Original order | Change and decision | Purpose | Remaining design work |
| --- | --- | --- | --- |
| 1 | Restricted `try` replaces `else fail`, accepted for the next-milestone plan, [D48](design-decisions.md#d48-try-passes-a-failure-on) | Make explicit propagation concise and visible before the call. The recorded comparison found 146 propagations in about 1,900 lines of library, example and book code, and 1,172 across the larger source set. | Retain current permitted positions: complete local initializer, assignment source or call statement. One `try` consumes one call's failure in an enclosing `fails` routine. Preserve `handle` and current cleanup rules. Settle prefix parsing, diagnostics and migration; nested calls, `return try` and general expression use are outside scope. |
| 2 | Required call-site `var`, accepted for the next-milestone plan, [D49](design-decisions.md#d49-a-writable-argument-is-marked-var-at-the-call) | Make mutation of caller storage visible at the call, as well as in the declaration. | Missing or unexpected `var` is an error. Settle markers for leases under D30 and for passing on a writable aggregate result. This marks writable access, not an ownership transfer or Rust-style exclusivity. |
| 3, earlier order; now deferred | `for … in` over arrays and strings, [D50](design-decisions.md#d50-for--in-iterates-over-an-array) | Keep a traversal's bound tied to the object instead of an independently maintained counter. | Aggregate elements bind as read-only aliases, or writable aliases with `for var`. Settle scalar and string-byte binding and the index type. Cover fixed and open arrays, string length, evaluation of the iterated object and lifetime protection throughout the loop. Preserve the applicable lease rules without assuming global alias exclusivity. |
| 4 | Exhaustive value selection, accepted for the next-milestone plan, [D51](design-decisions.md#d51-a-value-select-needs-case-else-unless-it-covers-every-value) | Make an unhandled value explicit. | Integer, character and Boolean subjects require `case else` unless whole-domain coverage is proved. An empty default is the intended explicit no-op; settle its formal grammar. Handle-selection completeness is a separate undecided question. Compare coverage-check costs for each scalar domain. Accepted next-milestone plain enums use the same exhaustiveness rule. |
| 5 | `:` replaces `as` for types, accepted for the next-milestone plan, [D52](design-decisions.md#d52--in-place-of-as-for-types) | Shorten type declarations while retaining name-first order and single-pass parsing. | Cover declarations, parameters, result permissions, record fields and pool declarations. Resolve remaining uses of `as`, tokenisation and modifier placement. |

D49 has been explicitly accepted for the next-milestone plan after review. `var` appears in the
parameter declaration and at each writable argument, marking permission to
mutate caller storage. Missing or unexpected markers are diagnosed. This does
not transfer ownership or impose Rust-style exclusivity. Lease arguments and
forwarded writable aggregate results still need their spelling settled. The
feature is unimplemented and does not change current 0.1 toolchain completion scope.
Acceptance for next-milestone planning is not an instruction to implement now.

D52 is explicitly accepted as a next-milestone plan item alongside D49. Replace `as`
with `:` at type positions in declarations, parameters, results, record fields
and pool declarations. Preserve typing, ownership permissions, name-first order
and single-pass parsing. Modifier placement and coordinated source migration
remain to settle. Colon syntax is unimplemented and is outside current 0.1 completion work.
No implementation is requested now.

D48 is accepted for the next milestone as the simple prefix spelling of current propagation.
A failable call must be the complete local initializer, complete assignment
source or complete call statement. `try` consumes that call's failure; the
enclosing routine must declare `fails`. Keep exactly one consumer per invocation
and preserve existing `handle` behaviour and cleanup rules. No nested failable
calls, `return try`, whole-statement implicit propagation or general expression
extension is admitted. The earlier nested-call sketch is not accepted scope.
The feature is unimplemented and does not change current 0.1 completion work.

D51 is accepted for the next milestone. A value `select` must cover every possible value of its
subject type, checked at compile time, or contain an explicit `case else`.
Intentional do-nothing behaviour must be explicit. An empty default is the
intended option, with its formal grammar still to settle. Apply the same rule to
accepted plain enums when implemented. Handle-selection completeness is a separate unresolved question. The feature is unimplemented;
the current 0.1 completion scope is unchanged and no implementation is requested now.

D50 is explicitly deferred. Counted loops remain the existing form. Retain
`for … in` as a [stretch goal](#array-and-string-traversal), not accepted next-milestone scope.
Read-only slices are independently accepted for the next milestone. Their acceptance does not
include new loop syntax.

These changes were selected for frequent friction, preventable mistakes and
readability. Their implementation costs remain unmeasured. Small token changes
can still require non-trivial failure-flow or lifetime work.

`try`, call-site `var` and `:` would affect most sources. For admitted changes,
migrate the library, conformance tests, examples and book in a coordinated update after the rules
are specified. Keep the current corpus reproducible. D49, D52, D48 and
D51 belong to the next-milestone plan, as do plain enums and typed failure codes below.
Deferred projects add no implementation work to this migration.

### Plain nominal enums

Accepted for the next milestone, separately from payload variants. The nominal type prevents
integer-domain mixups and supports exhaustive selection. Implement enums before
typed failure codes. Design completion and an independently measured enum budget
remain required. The feature is unimplemented; the current 0.1 completion scope is unchanged and no
implementation is requested now.

A closed set of named values has its own type. It prevents unrelated numeric
codes being substituted and supports exhaustive selection. The recorded source
comparison found 26 grouped constants and 11 failure codes represented by
integers. Error domains are a strong use case alongside directions and states.

The accepted scope is plain enums without payloads, ordinal arithmetic or
enum-indexed arrays. It does not admit variants or Pascal's full ordinal model.
The earlier D15 and D24 grouping is historical planning, superseded by the
accepted plain-enum and typed-failure directions.

The previous sketch proposed qualified members, a byte representation with at
most 256 members, default initialisation to the first member, equality without
ordering or arithmetic, and checked explicit numeric conversions. These are
useful starting questions, not settled semantics. Decide representation and
member capacity, initialisation, conversion and external-data validation,
qualified versus contextual member names, forward availability and exhaustive
selection. Define enum identity across modules if interfaces are adopted.

Plain enums have a provisional 0.5–1 KiB compiler estimate in this
catalogue. No implementation measurement establishes that range. A real-code
comparison and bounded prototype must demonstrate enough safety and clarity
per byte. Plan acceptance does not authorise any unmeasured budget or exceeding D43.

### Typed failure codes

Accepted for the next milestone after plain enums, distinguishing error domains without payloads.
This acceptance depends on enums and has its own design and measured budget
requirements. It does not admit richer error values or variants. The feature is
unimplemented; the current 0.1 completion scope is unchanged and no implementation is requested now.

D26 proposes enum-named failure domains, so a routine's `fails` declaration
identifies the type of its codes. Each `fail`, handler and propagation must use
a compatible domain. The recorded comparison found 11 failure codes across
three numeric ranges separated only by convention.

This is a closely connected follow-on to plain enums. It can prevent a file
error being confused with a parser error without introducing payloads. Specify
propagation between domains, handlers, unqualified member names, compatibility
with existing `u8` failures and, if separately admitted, precompiled signatures.
Preserve the distinction between recoverable failures and terminating safety
traps.

The inventory's incremental estimate is 0.1 KiB once enums exist, unmeasured.
It does not cover rich errors with payloads, conversions between domains or a
general stored result type. Admit this increment on its own measured costs.

### Temporary read-only array slices

An existing typed open-array routine can process a whole fixed array of varying
length. A checked slice would let the same routine process a contiguous subrange
without copying it into another array. An occupied input prefix or a range of
records would carry its starting address and extent together, rather than
passing buffer, offset and count whose relationship is maintained by convention.
No generic element types are implied: the slice retains the array's element type.

Accepted for the next milestone, superseding expected inclusion and deferred nomination.
The feature supplies checked subrange arguments to existing typed open-array
routines without copying. It does not introduce arbitrary generic element types.
The feature is unimplemented; the current 0.1 completion scope is unchanged and no implementation is requested
now. Range and lifetime design and measured costs remain required. Writable
array slices and string-slice semantics remain separately deferred.

A bounded first design uses temporary read-only views as call arguments to
existing typed open-array routines, with address/extent compatibility verified.

Read-only means writes are forbidden through the view. It does not freeze the
backing storage globally or introduce Rust-style exclusivity. Preserve Basie's
transient alias lifetimes and applicable pool lease protections. A view must not
outlive its backing object or escape through storage or a result beyond the
permitted lifetime. Calls through existing writable parameters must not accept
this view as writable access.

Specify endpoint conventions, valid empty ranges, overflow checks, out-of-range
construction, reborrowing and nested slicing. Construction checks must establish an extent
within the source object before access. Verify zero-length and boundary cases
without dereferencing invalid storage. Keep fixed capacity, logical occupied
length and view extent distinct. The open-array descriptor correction remains
a prerequisite for element types the current encoding cannot represent.

Compare a fixed-buffer utility using buffer/offset/count with the same operation
using a checked view. Measure construction checks, binding, descriptor workspace,
generated bytes and avoided copies. There is no measured cost estimate. Existing
open-array calling conventions may supply part of the representation; they do
not establish that construction and lifetime checks are free.

Mutable array slices remain separately deferred because overlapping writable
views and ownership require more design work. String slices also require a
separate decision about byte extent, logical length and reserved capacity.
Neither follows from admitting a temporary read-only array view.

### Typed noncapturing routine values

Provisionally accepted for the next milestone as the whole feature: routine parameters and
routine values stored in variables or record fields. This supersedes both
parameter-only evaluation and stored-reference deferral. Evaluate and prototype
the full scope, then back out explicitly if complexity or measured budget is
unacceptable. The feature is unimplemented; the current 0.1 completion scope is unchanged and no implementation
is requested now. A parameter-only restriction is not the accepted scope.

A sorter could receive a comparison routine; a record could retain a typed
operation for a later call. Compatible named top-level routines capture no
caller environment. They may access global storage under the existing rules.
Closures and captured frames remain excluded. Routine storage does not imply
heap allocation or a garbage collector.

The routine-value type must specify argument and result types, writable modes,
ownership permissions, failure effects and result provenance through `from`.
Type-check every supplied target, assignment and indirect call against that
signature, including typed failure domains once implemented. Preserve permissions
and result lifetimes across forwarding and delayed invocation.

Define initialisation and target validity before invocation, assignment and
field updates, forwarding and result use. Do not replace these design obligations
with a prohibition on stored routine values. Mutable fields and variables can
change the possible call target, so signature matching alone is insufficient.
Preserve indirect-call stack safety and retain every possible live target through
the linker. An address alone does not supply a callee's stack requirement.

The old O5 sketch proposed two-byte addresses, complete signatures and an
indirect-call helper. Its 0.5–1 KiB estimate is unmeasured and does not establish
the full feature's cost. Measure signature handling, descriptors and workspace,
generated calls, runtime helpers, stack checks and linker liveness through real
algorithms that pass and store routine values.

The admission gate applies to the full proposal. Verify accepted and rejected
signature cases, initialisation, assignments and record fields, live-target
retention, indirect stack checks, failures, ownership and result lifetimes.
Compare cognitive complexity and measured costs against D43. An unacceptable
result requires an explicit back-out decision before implementation admission;
it does not silently reduce the accepted scope to parameters only.

## Accepted next-milestone compatibility work

### Open-array descriptor correction

Accepted for the next milestone as compatibility and capacity work, before dependent slice
and array extensions. It remains deferred from current 0.1 toolchain completion. It corrects the representation of an existing language
facility. It is not speculative syntax, generics or an optional capability.
Complete the current 0.1 toolchain completion contract first, then address this correction
before dependent extensions. No implementation is scheduled yet.

An open array's ID currently combines `AG_OPEN` with its element ID, restricting
elements to IDs below `$28`. An open array of handles or `File`s cannot use that
encoding. Late-declared aggregate types also reach the ID restriction. Open
arrays of records that own handles already work, but wrapping a handle in a
record is a workaround for the encoding restriction, not the final design.

Use an interned type descriptor with an open-array kind and an element ID.
Replace ID-range tests such as `AG_ISVW`, `CP AG_OPEN` and `SUB AG_OPEN` with
kind and element queries. Audit parameter matching, descriptor lifetime,
scoping, generated element stride and the failure diagnostics. Preserve
ownership, view and lease rules for writable elements and the existing call
representation of address plus extent. Spare numeric IDs are not the chosen
solution.

The old plan estimated 150–250 additional compiler bytes across about 20
ID-range tests. This is unmeasured, bounded but cross-cutting representation work.
Recheck both figures against current source and verify matching, element stride,
scoped descriptor lifetime and diagnostics. Measure descriptor workspace as well
as resident code. Track the correction separately from optional extensions
and retain its deferral from current 0.1 completion until it is implemented and verified.

## Excluded design boundary

Closures are excluded from the proposed language direction. Accepted routine
values capture no local environment. No captured frame, general heap or
garbage collector is part of these proposals. This is a design boundary, not
an indefinitely deferred closure project.

## Indefinitely deferred possibilities

### Array and string traversal

`for … in` (D50) is explicitly deferred because it adds traversal sugar and
language concepts where counted loops already suffice. This supersedes the
earlier adoption and excludes it from accepted next-milestone scope. No implementation is
requested. Checked read-only slices remain independent: subrange access with
bounds information and copy avoidance does not require new loop syntax.

Retain the earlier questions about scalar copies, read-only or writable
aggregate aliases, optional index binding, fixed and open arrays and string
length. Any future reconsideration must preserve lifetime and lease rules and
justify the added concept through real algorithms. Existing counted loops remain
the alternative for whole-object traversal.

### Precompiled libraries and module interfaces

Explicitly retained as deferred after final candidate sorting, outside accepted
next-milestone scope. No implementation is requested.

This substantial project is indefinitely deferred, with no implementation
commitment or assigned release. Its capability is separately checked code and
programs larger than a single source compilation can hold. Existing `include`
and `private` support source composition. Interfaces would make dependencies
and separately compiled contracts explicit. Namespaced includes belong in this work if qualification
improves real library use. Avoid treating name collisions alone as sufficient
justification.

Specify exported types and complete routine signatures before use, including
parameter permissions, ownership, `fails` and result provenance through `from`.
Define type identity across compilations, private declarations, dependency
ordering and compatibility of services, profiles and object formats. The
single-pass compiler must check a client against an available interface without
loading an unrestricted collection of implementation sources.

The inventory's precompiled-library estimate is 1–2 KiB, unmeasured. The
catalogue's namespace estimate is another 300–600 bytes, also unmeasured.
Neither is a measured cost for a complete module system. Compare these mechanisms
separately before deciding what a bounded first implementation includes.

### Named record initialisers

Explicitly deferred: retain this stretch goal without implementation or current
next-milestone nomination. The capability argument below does not change that disposition.

Named fields can prevent silent mistakes after reordering fields of the same
type. The recorded comparison found this possibility in four of fourteen record
types, but only about six positional initialisers. A larger set of initialisers
could justify the feature.

Specify omitted or duplicated fields, evaluation order and moves into owning
fields. Preserve existing initialisation and cleanup guarantees. The earlier
estimate was 150–250 compiler bytes. Default field values are separately rejected.

### Payload variants and richer errors

A tagged union connects an alternative with its permitted data. A numeric tag
beside unrelated record fields allows invalid combinations, such as a quit
command with an item payload. A checked variant could limit construction and
access to the active alternative and expose missing cases through selection.
The recorded application set did not demonstrate enough need to schedule it.
Variants remain explicitly deferred: their capability is attractive but ownership
and compiler complexity are likely too costly for the current Z80 budget.
This judgement is a disposition, not a measured implementation cost.

Keep this separate from plain enums, enum-typed failure codes and enum-indexed
arrays. The old sketch used a tag followed by storage for the largest payload,
without requiring heap allocation. It proposed constructors in declaration
order, exhaustive selection and one level of read-only payload binding, with
no nested patterns or guards. Representation, construction and binding syntax
remain unsettled.

An owning payload requires explicit transfer on construction, cleanup of the
old active payload on replacement and cleanup at scope exit. Selection must
provide safe access without duplicating an owner. A tag-directed descriptor
could extend `OBJ_FREE`, with a versioned runtime-helper change. Writable
payload bindings need a separate alias policy. Payloads containing pool objects
retain their lifetime and generation obligations.

The inventory's combined enum-and-variant estimate is 1.7–2.7 KiB. The earlier version-two
sketch attributed 1.1–1.7 KiB to variants plus a runtime change. These are distinct
provisional estimates, not measured incremental costs after plain enums.
Rich errors with payloads and general stored success/failure values need their
own justification and propagation rules.

### Select expressions and expression blocks

Basie retains conventional imperative control flow: `if` and `select` remain
statements. Parallel statement and expression forms would add syntax and reader
rules, including distinctions that can be easy to miss. That complexity is a
reason to defer these proposals even at the cost of some expression composition.
They remain deferred possibilities outside the selected next-milestone scope.

Reopening requires strong evidence from equivalent real Basie programs and an
economical implementation. Compare the benefit with ordinary statement forms
and the additional language rules. Modern-language precedent alone is insufficient.
Discussion of possible benefits does not authorise an expression feature.

O3 proposed an explicit `result` statement for a block's value, while `return`
still leaves the routine. This could compose choices without a separately
assigned variable. Scalar select expressions can be evaluated independently
of variants. They do not require payload matching to exist first.

The old sketch required every continuing path to produce a value of a compatible
type, while trapping or failing paths produced none. Scalar results could join
in ordinary result registers. Check evaluation order, failure propagation,
cleanup and control-flow joins in a single pass. Aggregate results introduce
storage and lifetime work and are a separate decision. The old estimate was
0.5 KiB. No representative application currently justifies implementation admission.

### Mutable array slices and string slices

Mutable array slices are separately deferred, outside the selected milestone. Define
writable access, overlapping views, owning elements and pool lease protection
against Basie's actual alias model. Existing overlapping mutable references are
not prohibited by a general Rust-style rule. A split into provably disjoint
writable ranges is another bounded possibility, with its own construction and
lifetime checks. Do not infer mutable support from the read-only candidate.

String slices need a separate length/capacity contract. A read-only byte sequence
is not automatically a bounded string with its own length field or writable
capacity. Decide whether a view describes logical characters or reserved bytes,
which existing routines can accept it and how empty views and nesting work.
A fixed buffer plus a count already supports variable logical length; a slice
does not require a growable heap vector.

Preserve transient lifetimes, escape restrictions and applicable lease rules
for both proposals. Compare buffer/offset/count utilities against checked views.
Include caller-provided output and the count written when evaluating writable
views. No measured cost exists for either extension.

### Scoped storage and arenas

Retain scoped storage and arenas as deferred stretch goals after review. No
implementation or next-milestone nomination is made.

O4 proposed scope-bound regions freed together, using free memory between static
storage and the stack, starting at the `FREE` pseudo-object. Pools already
support dynamic structures within fixed capacities. Arenas would address a
different need for temporary storage sized by runtime input.

Specify allocation failure, lifetime, escape prevention, cleanup and interaction
with stack bounds. Arena allocation does not establish safe resizing or aliases
into relocated objects. Runtime-sized locals, growable vectors and resizable
collections remain separate possibilities with no adopted design. The inventory
estimated arenas at 0.5–1 KiB, unmeasured.

### Failable calls in larger expressions

The earlier D48 sketch allowed nested calls such as
`try appendU16(report, try parseU16(text))`. That extension remains separately
deferred with no next-milestone nomination. The accepted `try` direction preserves the
current invocation positions instead. Any larger-expression proposal needs its
own evaluation of order, failure consumers, moved arguments, temporary cleanup
and destination state. It must not follow implicitly from prefix propagation.

### Other retained possibilities

Default parameter values and `repeat` or general-loop additions are explicitly
deferred after review. No implementation or next-milestone nomination is made.

O6's default parameter values could be constant expressions carried in complete
signatures and forward declarations. They offer little in a language without
overloading and require rules for owning and writable arguments. The provisional
estimate is 0.3–0.5 KiB. They are indefinitely deferred, distinct from rejected
default record-field values.

`repeat` and a general `loop` could simplify particular control flows. Existing
loops remain the alternative until real code establishes enough benefit. The
inventory's provisional estimate is 0.2 KiB. They have no scheduled release.

## Rejected proposals

The latest selection rejected these items. Earlier sketches remain historical
notes, not a route around this disposition. A future need requires an explicit
new decision before any implementation is scheduled.

| Proposal | Reason for rejection and retained boundary |
| --- | --- |
| Fresh non-owning aggregate value returns | Rejected: explicit caller-supplied destinations and pool-handle returns cover the need. Implicit result buffers, statement temporaries, lifetime and cleanup rules and stack accounting add unwanted machinery. See the rationale below. |
| `else` with a value | Only one of eleven recorded `handle` blocks sets a default. Existing handling covers that case. |
| `defer` | The recorded code has three file opens and run-end cleanup already closes files. A long-running recovery loop could supply new evidence, but arbitrary deferred actions add failure and cleanup complexity. |
| Default field values | The recorded initialisers do not repeat non-zero defaults. This is separate from deferred named initialisers and default parameters. |
| Block comments | Nine runs of three or more line comments did not establish enough benefit over editor operations. |
| `fn` in place of `sub` | Cosmetic migration of every file and the book, with loss of the BASIC character. |
| Limited type parameters | No duplicated algorithm across element types was found in the recorded code. The 1–2 KiB estimate is unmeasured. Behaviour-dependent algorithms would also need an operation-binding mechanism. |
| Enum-indexed arrays | The recorded need is served by constant indices. Plain enums do not imply ordinal array domains or arithmetic. |
| Shadowing | Withdrawn in favour of retaining specification §5.6. Module qualification must preserve that rule. |
| Implicit failure propagation, or trailing `?` or `!` | D48 selected visible `try`. `?` overlaps optional types and `new?`; a trailing `!` is easy to miss and can suggest a non-failing assertion. |
| `mut` on parameters | D17's `var` remains. D49 adds the required call-site marker. |

### Fresh aggregate value returns

Rejected on 2026-10-10, superseding the earlier deferred disposition. Explicit
caller-supplied writable destinations and pool-handle returns already cover
construction of a result. Existing aggregate results remain aliases with a
`from` relationship and cannot refer to expired callee-local storage.

Hidden caller-result storage is technically feasible. Supporting a nested call
such as `draw(makePoint(...))` would also require implicit statement temporaries,
well-defined lifetimes and cleanup, evaluation order and stack accounting.
That added machinery conflicts with Basie's language and compiler design
constraints. The rejection is a design choice, not a claim that safe aggregate
value returns are impossible.

Do not implement or nominate this proposal as a next-milestone candidate. Returning owning
aggregates by move would require additional transfer and descendant-cleanup
rules; it does not follow from any existing pool-handle return mechanism.

## Implementation restrictions and semantic boundaries

Audit capacities against the current [capacity audit](capacity-audit.md) and
[limits register](limits.md). The old 16-literal and 2,048-byte routine-buffer
restrictions were temporary implementation limits, not language goals. Historical
table sizes likewise must not become permanent semantics through repetition.
Use current source and contracts before concluding that a reported limit remains.

The open-array encoding correction is explicitly retained in the forward plan.
Other current-toolchain defects must be resolved against the existing contract before
extensions. Review semantic restrictions such as bounded strings, unsigned
indexing, constant loop steps and transient aliases against their actual safety
or representation rationale. Accepted D48 changes propagation spelling while
preserving the current failure-call position restrictions. Full typed routine
values are provisionally accepted for the next milestone, with whole-feature evaluation and
an explicit back-out gate. Closures remain excluded.
Preserve type safety, memory safety, defined behaviour and platform restart
vectors under D46 throughout.

References: [forward plan](version-2.md), [feature inventory](feature-inventory.md),
[design decisions](design-decisions.md), [memory safety](memory-safety.md),
[build pipeline](build-pipeline.md) and
[capability discussion](language-capability-gaps.md). The capability discussion
retains earlier motivations. Its candidate lists do not supersede the dispositions
recorded here or the nomination and admission process in the plan.
