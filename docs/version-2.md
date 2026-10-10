# Forward development plan

Updated 2026-10-10. This is the authoritative plan for the current **0.1
toolchain line** and the **next development milestone**. Version **1.0** is
reserved for eventual language stabilization, not a delivered toolchain release.
The next milestone has no assigned release number; it replaces the earlier
"version two" label. The historical path `version-2.md` is retained.

Current 0.1 completion comes first. The selected scope comprises call-site `var`,
colon types, restricted `try`, plain enums, exhaustive value selection, typed
failure codes, the open-array descriptor correction and temporary read-only
array slices. Full typed noncapturing routine values are provisionally included
with an explicit back-out gate.

The [stretch-goals catalogue](stretch-goals.md) holds the feature arguments,
semantics to settle and deferred or rejected dispositions in one place. The
[feature inventory](feature-inventory.md) retains provisional estimates, not
measured budgets or implementation permission. Selection is complete for this
review; design and measured admission remain unfinished. No implementation is
requested now.

The [proposed 1.0 language specification](../spec/01-status-and-conformance.md)
governs current programs and remains a working draft. The feature-selection freeze for completion
excludes optional additions, not corrections to existing rules. It is separate
from formally freezing the eventual 1.0 language specification. A planned
feature requires normative text, conformance tests and an admitted native implementation before becoming
available. This plan and the [design decisions](design-decisions.md) record
forward directions; they add no syntax to the current language.

## 1. Complete the current language first

Basie is a general-purpose language for small systems, in the BASIC and Pascal
tradition. Extensions should make algorithms clearer while preserving static
typing, explicit ownership and `move`, transient aggregate aliases, fixed pools
and checked non-owning identifiers. They must remain understandable to readers
and implementable by the single-pass CP/M compiler. Cognitive smallness is the
primary admission criterion: preserve a small conventional imperative language
with few concepts and clear rules. Compact machine implementation is a separate
constraint.

Roadmap step 74 is recorded as complete for the current completion scope
(formerly called version one). Before extensions,
confirm the current conformance corpus, native/reference equivalence, capacity
minimums, stress tests and release workflow. Resolve capacity defects against
the existing contract. A correction to a compiler limit is not a new language
feature. Representation corrections deferred from current completion remain tracked below.

The [limits register](limits.md) and the current build's size checks supply the
capacity baseline. Historical source-area and image figures are not a budget
for new work. D43 sets a 26 KiB target and a 28 KiB limit, with 30 KiB a ceiling
that no decision may cross. This plan does not raise the 28 KiB limit.

Count the resident image and reserved overlay window together. Account for
writable workspace, buffers and stack separately. A smaller COM file does not
establish a smaller memory footprint. Repeated overlay loads can also make a
build slower. Compression and overlay changes need their own correctness and
latency measurements before their savings can fund an extension.

## 2. Selected next development milestone

Priority follows safety value, design confidence and dependencies, rather than
simply taking the smallest estimated implementation first. Plain nominal enums
are a high-confidence safety improvement: unrelated sets of codes become
distinct types, without payloads or Pascal's wider ordinal model. The enum,
exhaustiveness and typed-failure cluster is a high priority alongside clearer
call and declaration syntax.

| Tier | Accepted work | Why it belongs here | Design and verification still required |
| --- | --- | --- | --- |
| 1. Dependable foundations | Required call-site `var` (D49), colon types (D52), restricted `try` (D48); plain nominal enums, exhaustive value selection (D51), then enum-typed failure codes | Make writable access and propagation visible; distinguish code domains and expose missing cases. These have comparatively clear purposes and bounded scope. | Settle syntax, modifiers, enum representation and conversions, coverage and failure-domain rules. Verify each change's safety, diagnostics and compiler budget. |
| 2. Compatibility correction | Open-array type descriptors | Repair an existing representation restriction rather than add an optional language concept. This must precede dependent slice and array work. | Verify element matching, stride, scoped descriptor lifetime, workspace, diagnostics and unchanged address/extent calls. |
| 3. Bounded capability | Temporary read-only array slices | Let existing typed open-array routines process checked subranges without copying. The representation is familiar, but range and lifetime rules need a careful prototype. | Specify endpoints, empty ranges, overflow, nesting and transient lifetime/lease protection; measure checks, generated code and workspace. |
| 4. Greatest uncertainty | Full typed noncapturing routine values, including parameters, variables and record fields | Supply reusable behaviour and stored operations, with more extensive signature, target-liveness and indirect-call safety obligations. Inclusion remains provisional. | Prototype the whole feature; verify initialisation, signatures, result provenance, failures, stack checks and linker retention. Explicitly back out if complexity or measured budget is unacceptable. |

High confidence means less uncertainty about the feature's purpose and scope.
It does not mean a free implementation, settled semantics or waived measurements.
Every tier must pass section 5. Tiers express planning priority, not a rigid
implementation order: finish 0.1 first, correct descriptors before dependent
slices, and establish enums before typed failure codes. Coordinate the broad
`var`, colon and `try` source migrations after their rules are specified, so
library, test and book sources do not undergo repeated incompatible rewrites.
Descriptor work can proceed before that migration where its dependencies require it.

The [catalogue](stretch-goals.md#priority-and-confidence) records the same tiers
and each feature's unresolved rules. D48–D52 retain their original decision
order as history, not current priority. D50, `for … in`, is explicitly deferred;
counted loops remain, independently of accepted read-only slices.

Restricted `try` preserves the current complete local-initializer,
assignment-source and call-statement positions. It consumes one call's failure
in an enclosing `fails` routine and preserves `handle` and cleanup. Nested
failable calls, `return try`, implicit whole-statement propagation and general
expression extensions are outside this acceptance.

Exhaustive value selection requires compile-time whole-domain coverage or an
explicit `case else`. An empty default is intended, with formal grammar still
to settle. Handle-selection completeness remains separately undecided. Enums
have no payloads, ordinal arithmetic or enum-indexed arrays; typed failures
introduce compatible error domains, not rich payload errors.

Read-only slices forbid writes through the view while preserving transient
lifetimes and pool leases. They do not globally freeze backing storage or impose
Rust exclusivity. Writable slices and string slices remain separately deferred.
Routine values capture no local environment; closures remain excluded. No
feature implementation is requested and current 0.1 completion is unchanged.

## 3. Selected scope and deferred proposals

All feature arguments and unresolved semantics are in the
[catalogue](stretch-goals.md#accepted-next-milestone-directions). Its
[checkpoint](stretch-goals.md#review-checkpoint) records the completed review.
The selected scope does not automatically include nearby proposals: `for … in`,
writable and string slices, payload variants, libraries and module interfaces
remain deferred. Fresh aggregate value returns are rejected. Closures are
excluded. The other deferred and rejected items retain their recorded status.

Selection supplies planning scope, not missing semantics or verified costs.
Full routine values must be evaluated and prototyped with parameters, variables
and record fields together; an unacceptable result requires an explicit back-out
decision. All selected items remain subject to section 5 before implementation
admission. Current 0.1 completion remains the immediate obligation.

## 4. Open-array descriptor correction

The [descriptor correction](stretch-goals.md#open-array-descriptor-correction)
is accepted next-milestone compatibility and capacity work before dependent
slice and array extensions. It remains deferred from current 0.1 completion.
It concerns an existing facility rather than optional syntax or generics. Preserve address/extent calls and ownership, view and lease
rules. Complete the current 0.1 toolchain completion contract first, then verify this
correction before extensions that depend on the affected element types.
The older 150–250 byte estimate across about 20 ID-range tests is unmeasured.
No implementation is requested now.

## 5. Evaluation and admission

The primary admission criterion is cognitive smallness. A feature needs a
concrete safety or capability benefit in real Basie algorithms sufficient to
justify its additional language rules. Assess clarity and frequent friction
through the same examples. Elegance for an experienced programmer, familiar
syntax in another language and a shorter spelling do not establish that benefit.

Start with representative library or application code and compare equivalent
behaviour before and after. Include the clearest existing statement-based
solution as the alternative. Retain it when it adequately expresses the algorithm.
Assess the proposed language as a whole:

- additional concepts a reader must learn;
- special cases and interactions with existing rules;
- duplicate spellings or parallel statement and expression forms;
- subtle syntax that changes behaviour or requires expert interpretation.

Apply a high bar to each added facility. Even a compact implementation can add
substantial concepts and rules for readers. The conventional imperative
character remains a design constraint, even where a more expressive
alternative is technically feasible.

A candidate that clears this conceptual test may proceed to a bounded prototype.
Compiler bytes and measured machine costs are independent admission constraints.
Spare capacity does not justify extra language complexity. The prototype must measure:

- resident compiler code and immutable data, overlay file and reserved window;
- writable workspace, descriptors, buffers and peak stack;
- generated program bytes and runtime helpers, including cleanup machinery;
- compile CPU cost, overlay traffic and disk latency on a stated model or target;
- remaining source and routine capacities at the relevant conformance minimums.

Record the source baseline, equivalent functionality and limits of each
measurement. An estimate remains an estimate until a prototype establishes
its cost. Do not add independent provisional ranges as though they form a
measured package budget.

The outcome is an explicit **adopt**, **defer** or **reject** decision. Adoption
requires cognitive smallness, a coherent safety contract, concrete source-level
benefits and measured capacity under D43. Recover any required room before
landing the feature. Preserve restart-vector availability under D46. A proposal
to change the 28 KiB limit requires a separate decision and is not assumed by
this plan.

For provisionally included routine values, prototype parameters and stored
values together. Record an explicit back-out decision if complexity, safety or
measured capacity fails admission. Do not impose a parameter-only scope without
a new decision. Acceptance for evaluation does not bypass this gate.

For an admitted change, update the specification and reference compiler first,
then accepted and rejected conformance cases. Implement the native compiler
against those streams under D45. Follow the correctness, compression and review
cycle required by D43. Extend relevant stress generators and verify library,
book and release examples through the public compile/link/run workflow.

## 6. Work sequence and dispositions

| Stage | Work | Completion condition |
| --- | --- | --- |
| Immediate scope | Finish and verify the current 0.1 toolchain completion contract | Existing guarantees hold or have an explicit documented disposition. |
| Priority and dependencies | Develop the tier-1 foundations; establish enums before typed failures and descriptor corrections before dependent slices | Rules and dependencies are explicit; source migration is coordinated rather than repeated for each spelling change. |
| Bounded prototypes | Verify descriptor corrections and read-only slices; evaluate full routine values under the explicit back-out gate | Safety and machine costs are measured for each item. Routine-value scope includes parameters and storage together. |
| Implementation admission | Admit each change under section 5 | Specification, reference/native equivalence, independent safety tests and migrated examples pass within D43. Decisions to defer, reject or back out are explicit. |

Implementation of the next milestone has not started. Priority does not provide
missing semantics or a measured budget. The current 0.1 toolchain contract
remains the immediate obligation. Neither planning document changes the current
source language.
