# Adversarial review of the specification (roadmap step 23)

- Date: 2026-10-05
- Documents: spec chapters 1 to 21, with design-decisions.md, memory-safety.md,
  services.md and standard-library.md as authorities.
- Method: three reviewers, each taking a group of chapters, checked the text
  against the design decisions, against the other chapters and against the
  reference compiler. They compiled a counterexample for each claim about
  behaviour. A program that behaves differently from the text counts as a
  finding against whichever is wrong, and each finding says which.
- Severity: critical when a program's meaning is wrong or undefined or safety
  is affected; major when implementations would differ; minor for stale
  references and small gaps.

Status of each finding is recorded where it is closed (the commit that
fixes it names the finding, as B1, A3 and so on).

## Group A: chapters 1 to 5

| # | Severity | Finding | Right |
| --- | --- | --- | --- |
| A1 | major | Chapters 3 and 5 say `id(...)` is always the conversion; 17.3 makes it the conversion only when no binding named `id` is visible, and the compiler follows 17.3, so one public `id` disables `id(...)` everywhere after it. | `id (` is always the conversion; no routine may be named `id` |
| A2 | major | Chapters 4 and 5 say forward declarations are routines only, though D40, 8.11, chapter 17 and the corpus have forward pools; their completion checks are missing. | Routines and pools |
| A3 | major | Whether a body repeats `private` is unclear; the compiler requires the completion's visibility to match the forward. | State the matching rule |
| A4 | major | Nothing stops a declaration starting in one part and ending in another; the compiler accepts it, and a split body sees the other part's private names. | Each part ends at top level; diagnose |
| A5 | major | The object format puts all part records first, but parts are discovered as includes are read. | Emit a part record when its number is fixed |
| A6 | major | "No other declaration may use the identity `main`" conflicts with fields and earlier locals named `main`, which the compiler accepts. | Program and part scope only |
| A7 | minor | Compile-time `assert` is missing from the top-level families, and can't be `private`. | Add, with the exception |
| A8 | minor | `.capacity` on `string[]` parameters is missing from 5.6's lookup table. | Add |
| A9 | minor | `handle` bodies and `some(NAME)` bindings are missing from 5.3 and 5.4. | Add |
| A10 | minor | Which part scope a body completing a forward from another part sees. | The body's part |
| A11 | minor | Chapter 1 names Nucleus documents and omits services, memory safety and code generation from the authority order. | Name the real documents |
| A12 | minor | "First compiler" is a Nucleus term; streaming is called a chapter 2 constraint but isn't in chapter 2. | Say `BASIE.COM`; add to 2.4 |
| A13 | minor | Stale cross-references to "Section 4.3" and "Chapter 1" diagnostic policy. | Fix |
| A14 | minor | Code fences tagged `nucleus`; the README still says chapters describe Nucleus 0.1. | Fix |
| A15 | minor | Reference diagnostics give a provisional part number for lexical errors in included parts. | Report the part's name |
| A16 | minor | Part identity by drive and name, drives in includes, required types, several command-line parts, and `L=`'s meaning differ between chapter 4, the toolchain and the reference. | Align |
| A17 | minor | Chapter 1 says the corpus has no `activation-capacity` trap; one test expects it. Tests are ranked lowest in 1.3 but called normative in 21.1. | Fix |
| A18 | minor | `private-is-part-local.bsi` has only one part. | Add a multipart test |
| A19 | minor | Because `id` lexes as `NAME`, `primary` and `type-atom` have two more LL(1) conflicts than the 17.4 table shows; the grammar check treats `id` as its own terminal. | Add the rows; check `id` as `NAME` |
| A20 | minor | 3.6 doesn't say whether a tiny float literal is rounded before it is flushed. | Rounded first |
| A21 | minor | Chapter 2's version 2 list omits generics and `repeat`. | Add |

## Group B: chapters 6 to 9

| # | Severity | Finding | Right |
| --- | --- | --- | --- |
| B1 | critical (closed) | `j.w = f()` through an identifier checks `j` before calling `f`, so `f` can free and reuse the slot and the store lands in the new occupant. 7.13 and 9.14 say the right side comes first, but 10.4 step 1 and 15.4 say the target path does, with no exception, and the compiler follows them. | 7.13: check the identifier after the right side |
| B2 | critical (closed) | An aggregate field reached through an identifier is passed as an alias into the slot, not copied (7.13), and `var` is accepted. The callee can free and reuse the slot. Copying an owning-type field would itself duplicate an owner. | Copy non-owning fields; forbid passing owning-type fields reached through identifiers; reject `var` |
| B3 | critical (closed) | A typed constant combined with a literal is computed in `u16`: `const a as u8 = 200` then `a * 2` gives 400, and `var b as u8 = a + 100` is rejected. | 8.4: the constant behaves like a `u8` |
| B4 | major (closed) | `id(n)` compares only the owner word, so a record at offset 0 of a node shares the node's address and `id(n)` names the wrong pool. | Also compare the slot's pool word |
| B5 | major | "A routine whose result is an owning type" is called fresh, and owning aggregates may be copied "unless fresh". Aggregate results are aliases, so no aggregate is ever fresh. | Say "owning handle type" |
| B6 | major | 6.5 keeps Nucleus statements: scalars only `u8`, `u16`, `boolean`; no local aggregates; results alias program storage. | Rewrite 6.5 to D8, D20 |
| B7 | major | Identifier comparison (`=`, `<>`, with `none`) is specified but not implemented. | Implement; state `id P` widens to `id P?` |
| B8 | major | Exact operands of `not`, `shl`, `shr` and bitwise operators: 9.7 and 9.10 conflict; the compiler rejects `var x as u8 = 1 shl 3`. | Define them from the context type |
| B9 | major | 8.10 says literals have no definite type, but 9.7 types `true`, characters, floats and comparisons, and the compiler accepts `var f = true`. | Restrict 8.10 to exact integers |
| B10 | major | Character literals are exact in one place and `u8` in another; substituting a constant for its literal changes validity. | One rule, stated once |
| B11 | major | `var f as f32 = 16777217` is accepted and rounds silently, though an exact integer adopts `f32` only when representable. | Reject; define `f32(...)` on exact operands |
| B12 | major | Exact arithmetic is done in host doubles: intermediates outside the range are neither rejected nor exact. | Check every intermediate |
| B13 | major | "Parameters without `var` are read-only, except scalar parameters" excludes handle parameters, which `move n` needs. | Add handle parameters |
| B14 | major | Open views (`string[]`, `T[]`) are accepted as local initializers and results, and then crash the compiler. | Diagnose them |
| B15 | major | String literals: chapter 9 admits them only in initializers and read-only arguments, chapter 17 in every argument; the compiler also accepts `s = "abc"` and literals in `new`. | Name every position |
| B16 | major (closed) | Whether an aggregate field reached through an owning local is copied or aliased is unclear; the compiler aliases. | Lease semantics for owner paths |
| B17 | minor | Chapter 6 omits handle fields, exact indexes, arrays of arrays and handles, and `T[]` identity. | Add |
| B18 | minor | Homes of `P` and `id P` omit routine results. | Add |
| B19 | minor | The example in 8.15 uses `step`, a reserved word. | Rename |
| B20 | minor | A duplicate in one scope is reported as `shadowed-name`. | `duplicate-name` |
| B21 | minor | 6.13's examples work only as locals. | Say so |
| B22 | minor | 9.17 lists `recordValue = other` as invalid, but as a statement it is assignment. | Use `if` |
| B23 | minor | 7.10's `new` examples use fields and pools not defined anywhere. | Use chapter 8's `Node` |
| B24 | minor | `move` from a ticket's field is allowed by 9.16 but rejected by the compiler and memory safety 5.12. | "writable parameter" |
| B25 | minor | 9.15 says designators are not constant, but named constants are designators. | Except named constants |
| B26 | minor | 7.7's `from` wording names a local. | Use D8's wording |
| B27 | minor | Field access through a fresh handle temporary is unspecified and badly diagnosed. | State invalid |
| B28 | minor | A record with an `id P?` field has no static initializer, which 8.9 doesn't say. | Say so |
| B29 | minor | The type grammar reads `u8[25][40]` backwards. | Note the binding |
| B30 | minor | Fences tagged `nucleus`; planning text in 6.12; memory safety says 4-byte slot headers, revision 6.1 says 6. | Fix |

## Group C: chapters 10 to 21

| # | Severity | Finding | Right |
| --- | --- | --- | --- |
| C1 | critical (closed) | Counted loops store the next value before testing it, so any loop ending at the edge of its counter's type traps with `loop-range` (every descending `u16` loop, `for c = 7 to 0 step -1` on `u8`, `0 to 255`), and the counter ends one step past the bound. | 12.5: test the next value wide, then store |
| C2 | critical (closed) | A `move` in an `elseif` condition is not seen by the `else` body, which can then read and write through `none`. | Each clause starts in the state after its own condition |
| C3 | critical (closed) | The state after a loop ignores `exit` paths, so a value moved before `exit` is used after the loop. | 12.6: meet the exits too |
| C4 | critical (closed) | `move` in a `while` condition is accepted; the second test moves `none`. | 10.8: reject |
| C5 | critical (closed) | `select` on a slot-holder gives a lease with direct access, but the slot-holder can name a program variable the arm can free: a use after free. | A slot-holder subject binds an identifier |
| C6 | critical (closed) | For an owning destination the spec evaluates the right side before the target path, which single-pass code can't do; the compiler evaluates a called index first and loses it. | Target path, right side, recheck, free, store |
| C7 | major (closed) | Exact loop bounds outside the counter's type are rejected, though 12.4 says they need not fit. | Compare mathematically |
| C8 | major (closed) | Named steps that are negative or `f32` are accepted. | Require a non-negative integer constant |
| C9 | major | `handle` on a local declaration is accepted. | Reject |
| C10 | major | 14.4 allows `else fail` only on scalar local declarations; the grammar and compiler allow any expression initializer. | Any expression initializer |
| C11 | major (closed) | `move` in `assert` conditions and `and`/`or` operands is accepted. | Reject |
| C12 | major | `File` comparison is specified but rejected. | Implement |
| C13 | major | `clock` and `DateTime` are in services revision 2 but have no layout and no implementation. | Define and implement, or remove |
| C14 | major (closed) | Whether an unreachable end of a loop body counts as a back edge. | Only when it can complete |
| C15 | major | Handle parameters without `var` can be assigned, against 10.4. | Scalar and handle parameters are local copies |
| C16 | major | "When the compiler proves" makes validity depend on cleverness. | Only constant operands |
| C17 | major | Typed `case` labels use conversion rules rather than representability. | Pick one rule |
| C18 | major | File-table generations saturate at $FFFF and the entry is reused, so a stale `File` can match a new file. | Withdraw the entry, as pool slots are |
| C19 | major | The reference compiler lacks 32-bit `select` and counted loops (one crashes). | Implement or record |
| C20 | minor | "in any order" for `case` arms contradicts `case else` last. | Fix wording |
| C21 | minor | 14.6 examples call `readStorageByte`, which doesn't exist. | Use `readInputByte` |
| C22 | minor | `head = move head.next` compiles under no declaration. | Use `h.next` |
| C23 | minor | Three places say a trap frees slots; 15.1 says it frees none. | Exclude traps |
| C24 | minor | 16.2 omits `textMode` and `binaryMode`. | Add |
| C25 | minor | `File` is absent from chapter 6 and the assignment and parameter rules. | Classify it |
| C26 | minor | `as var` results as `var` arguments are accepted but unstated. | State |
| C27 | minor | `var x as T[]` taking `T[N]` is missing from 13.4. | Add |
| C28 | minor | Nothing produces `float-invalid`. | Drop or name one |
| C29 | minor | Chapter 21 omits `library` and `services`, and misses `loop-range` and loop-boundary programs. | Update |
| C30 | minor | 14.2's header fragment lacks the `var` and `from` result clause. | Align with 13.2 |
| C31 | minor | `left = right = 0` is valid when `left` is boolean. | Better example |
| C32 | minor | An untyped constant `select` subject is unspecified. | State |
| C33 | minor | Stale text: a Skate reference, `nucleus` fences, a wrong services section, a "to be confirmed", an empty forward reference, `abort` of a zero `File`. | Fix |
| C34 | minor | "Source routine" excludes services. | "routine or service" |
