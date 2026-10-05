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

## Group B: chapters 6 to 9

| # | Severity | Finding | Right |
| --- | --- | --- | --- |
| B1 | critical | `j.w = f()` through an identifier checks `j` before calling `f`, so `f` can free and reuse the slot and the store lands in the new occupant. 7.13 and 9.14 say the right side comes first, but 10.4 step 1 and 15.4 say the target path does, with no exception, and the compiler follows them. | 7.13: check the identifier after the right side |
| B2 | critical | An aggregate field reached through an identifier is passed as an alias into the slot, not copied (7.13), and `var` is accepted. The callee can free and reuse the slot. Copying an owning-type field would itself duplicate an owner. | Copy non-owning fields; forbid passing owning-type fields reached through identifiers; reject `var` |
| B3 | critical | A typed constant combined with a literal is computed in `u16`: `const a as u8 = 200` then `a * 2` gives 400, and `var b as u8 = a + 100` is rejected. | 8.4: the constant behaves like a `u8` |
| B4 | major | `id(n)` compares only the owner word, so a record at offset 0 of a node shares the node's address and `id(n)` names the wrong pool. | Also compare the slot's pool word |
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
| B16 | major | Whether an aggregate field reached through an owning local is copied or aliased is unclear; the compiler aliases. | Lease semantics for owner paths |
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
