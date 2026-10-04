# Baton diagnostic codes

- Status: working register; grows with the reference compiler
- Related: [design decisions](design-decisions.md) D39 (message file),
  [roadmap](roadmap.md) step 48, [conformance tests](../tests/conformance/README.md)

Every compile-time diagnostic has a stable kebab-case **code**, used by the
conformance tests (`// expect error: CODE at LINE:COLUMN`) and, in the native
compiler, mapped to a message number in `BATON.MSG`. The position is the first
byte of the construct the diagnostic names. Codes are never reused for a
different meaning.

## Lexical (Chapter 3)

| Code | Meaning |
| --- | --- |
| `bad-byte` | A byte outside the source repertoire |
| `lone-cr` | CR not followed by LF |
| `bad-character` | A byte that begins no token, such as `_`, `;` or `!` |
| `malformed-number` | A malformed or out-of-range numeric literal |
| `bad-escape` | An unknown or incomplete escape |
| `empty-character`, `long-character` | A character literal of zero or several bytes |
| `unterminated-literal` | A literal ended by a line ending or the end of the part |
| `unmatched-delimiter`, `mismatched-delimiter`, `open-delimiter` | Delimiter errors |

## Structure and names (Chapters 4 and 5)

| Code | Meaning |
| --- | --- |
| `include-position` | `include` after a declaration |
| `include-cycle` | An `include` of a part still open |
| `include-missing` | An included file not found |
| `missing-main` | No `main` routine |
| `undeclared-name` | A name with no visible declaration |
| `duplicate-name` | An exact duplicate in one scope |
| `shadowed-name` | A declaration that would shadow a visible name |
| `wrong-class` | A name of the wrong declaration class for its position |
| `recursion-needs-forward` | A call to a routine not yet complete, without a forward declaration |

## Declarations and types (Chapters 6 and 8)

| Code | Meaning |
| --- | --- |
| `conversion-required` | A change of type that needs an explicit conversion |
| `type-mismatch` | An operand or value of the wrong type |
| `out-of-range` | A constant value outside its type's range |
| `constant-needs-type` | An untyped constant that is not an integer, character or boolean |
| `no-definite-type` | An inferred local whose initializer has no definite type |
| `assertion-false` | A compile-time or certainly false `assert` |
| `pool-needs-record` | A pool whose element type is not a record |
| `handle-must-be-optional` | A field, element or program variable of non-optional handle type |

## Expressions and statements (Chapters 9 to 12)

| Code | Meaning |
| --- | --- |
| `mixed-operands` | Operand types that don't widen to each other |
| `chained-comparison` | A second comparison operator |
| `index-type` | An index that is not `u8` or `u16` |
| `division-by-zero` | A constant zero divisor |
| `not-writable` | An assignment to a constant, a ticket or another read-only path |
| `duplicate-case` | Two `select` labels that cover one value |

## Ownership and routines (Chapters 7, 10 and 13)

| Code | Meaning |
| --- | --- |
| `needs-move` | An owning handle copied instead of moved |
| `owning-copy` | A copy of a record or array of an owning type |
| `use-after-move` | A non-optional owner used when it may have been moved |
| `statement-rule` | An owner used and moved or overwritten in one statement |
| `alias-escapes` | A returned alias rooted in a local or a parameter not in `from` |
