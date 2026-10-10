# Specification change log

2026-10-11: D52 replaces `as` with `:` at every type position: declarations,
parameters, results (`): var T`), record fields and pools. `:` is a new
punctuation token; `as` is no longer a reserved word.

2026-10-10: D51 makes value selection exhaustive: an integer or enum `select`
without `case else` must cover every value of its subject's type
(`select-incomplete`, 117); an empty `case else` is the explicit no-op. Such a
selection always executes an arm, for flow states and fall-through. Handle
selection is unchanged.

2026-10-10: D53 adds plain nominal byte enums: declarations, qualified members,
exact-type scalar storage and calls, equality and enum selection. Numeric
conversions and ranges are excluded. Existing selection fall-through remains;
typed failures and exhaustive selection are not implemented by this change.

This log records, chapter by chapter, which design decisions
([design decisions](../docs/design-decisions.md)) each chapter of the Basie 1.0
specification carries. A decision that changes a chapter is added to its row.

| Chapter | Design decisions |
| --- | --- |
| 1. Status and conformance | Basie's status; one language, version 1 scope (D24) |
| 2. Design constraints | Single pass (D1), budget and two programs (D9), CP/M 2.2 target (D10), memory-safety claim |
| 3. Source text and lexical rules | `f32` literals and 32-bit literals (D31); keywords `select`, `case`, `move`, `pool`, `new`, `shl`, `shr`, `private`, `include`, `assert`, `some`, `none`; contextual `id` (D29); case sensitivity (D34) |
| 4. Program and file structure | `include` and `private` (D33); declarations anywhere (D28); forward pools (D40) |
| 5. Names and scopes | Block scope (D28), `private` visibility (D33), contextual `id` (D29), forward pools (D40) |
| 6. Types | Eight numeric types (D3), handle types (D22), owning types, arrays of arrays (D32), open arrays, conversions (D4, D31) |
| 7. Storage, values and lifetime | Activation storage and local aggregates (D8), pools and handles, the memory-safety rules (memory safety, revision 6) |
| 8. Constants and declarations | Typed and local constants (D20), inference (D21), `pool` declarations, `new` |
| 9. Expressions | Numeric rules (D31), conversions (D4), shifts and bitwise operators, `move`, `id()`, unsigned indexes |
| 10. Statements | Declarations anywhere (D28), `assert` (D37), the statement rule (memory safety §5.8) |
| 11. Conditional control | `select` (D15), with `some` and `none` and `select move`; exhaustive value selection (D51) |
| 12. Loop control | Signed counters and negative steps (D31), back-edge flow rule, a 32-bit comparison needs a 32-bit counter (D58) |
| 13. Routines and calls | `var` parameters (D17), leases and owner words (D30), `from` (D8), forward declaration required for self-calls (memory safety §7) |
| 14. Recoverable errors | Named failure constants (D26), service codes (services §7) |
| 15. Safety failures and traps | Traps `stale-handle`, `ownership-cycle`, `pool-full`, `assertion`, `float-overflow`, `float-invalid`; trap reports by address (D11) |
| 16. System boundary | Services (services draft), standard library (D36), file table (D38) |
| 17. Complete grammar | Every syntax change above |
| 18. Static semantics | Summary of the above |
| 19. Runtime semantics | Summary of the above |
| 20. Feature ledger | Version 1 and 2 features (D24), budget (D9) |
| 21. Conformance examples | Examples for every chapter; the corpus in `tests/conformance` |
