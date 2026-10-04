# Changes from Nucleus 0.1

The Baton 1.0 specification was forked from the Nucleus 0.1 specification
(Nucleus commit `89f51a6`, 2026-08-15), with the language renamed throughout.
This log records, chapter by chapter, which design decisions each chapter must
absorb and whether it has.

Status: **pending** (still Nucleus text), **in progress**, or **applied**.

| Chapter | Decisions to apply | Status |
| --- | --- | --- |
| 1. Status and conformance | Baton's status; one language, version 1 scope (D24) | pending |
| 2. Design constraints | Single pass (D1), budget and two programs (D9), CP/M 2.2 target (D10), memory-safety claim | pending |
| 3. Source text and lexical rules | `f32` literals and 32-bit literals (D31); keywords `select`, `case`, `move`, `pool`, `new`, `shl`, `shr`, `private`, `include`, `assert`, `some`, `none`; contextual `id` (D29); case sensitivity kept (D34) | applied |
| 4. Program and file structure | `include` and `private` (D33); declarations anywhere (D28) | applied |
| 5. Names and scopes | Block scope (D28), `private` visibility (D33), contextual `id` (D29) | applied |
| 6. Types | Eight numeric types (D3), handle types (D22), owning types, arrays of arrays (D32), open arrays, conversions (D4, D31) | applied |
| 7. Storage, values and lifetime | Activation storage and local aggregates (D8), pools and handles, the memory-safety rules (memory safety, revision 6) | applied |
| 8. Constants and declarations | Typed and local constants (D20), inference (D21), `pool` declarations, `new` | applied |
| 9. Expressions | Numeric rules (D31), conversions (D4), shifts and bitwise operators, `move`, `id()`, unsigned indexes | pending |
| 10. Statements | Declarations anywhere (D28), `assert` (D37), the statement rule (memory safety §5.8) | applied |
| 11. Conditional control | `select` (D15), with `some` and `none` and `select move` | applied |
| 12. Loop control | Signed counters and negative steps (D31), back-edge flow rule | pending |
| 13. Routines and calls | `var` parameters (D17), leases and owner words (D30), `from` (D8), forward declaration required for self-calls (memory safety §7) | pending |
| 14. Recoverable errors | Named failure constants (D26), service codes (services §7) | pending |
| 15. Safety failures and traps | New traps: `stale-handle`, `ownership-cycle`, `pool-full`, `assertion`, `float-overflow`, `float-invalid`; trap reports by address (D11) | pending |
| 16. System boundary | Services (services draft), standard library (D36), file table (D38) | pending |
| 17. Complete grammar | Every syntax change above | pending |
| 18. Static semantics | Summary of the above | pending |
| 19. Runtime semantics | Summary of the above | pending |
| 20. Feature ledger | Version 1 and 2 features (D24), budget (D9) | pending |
| 21. Conformance examples | New examples for every changed chapter; the corpus in `tests/conformance` | pending |
