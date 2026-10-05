# Nucleus grammar

This directory contains the machine-readable grammar used by the packed LL(1)
parser. The language specification remains authoritative for source-language
meaning; these files make its current Stage 7 syntax executable and testable.

| File                        | Purpose                                                                                                                    |
| --------------------------- | -------------------------------------------------------------------------------------------------------------------------- |
| `stage7-grammar.json`       | Grammar productions, external parser islands, and prediction diagnostics.                                                  |
| `generate-stage7.ts`        | Computes nullable, FIRST, FOLLOW, and prediction sets; rejects conflicts and packed-field overflow.                        |
| `stage7-tables.asmi`        | Generated prediction, production, and action tables included by the compiler; each row marks its final production in-band. |
| `stage7-proof-actions.asmi` | Generated action aliases used only by the isolated engine proof.                                                           |

Expressions, name-led statements, and type-directed aggregate initializers are
deliberate external islands. They require precedence or symbol and type
information that token lookahead alone cannot supply.

The packed statement grammar keeps failure consumption immediate: `else fail`
propagates a direct failable call, while same-line `handle NAME` opens its local
handler body. Boolean `or` remains entirely inside the expression island.

The generated files are locked by `test/ll1-stage7.test.ts`. Run that scoped
test after changing the grammar or generator.
