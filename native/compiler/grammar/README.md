# Nucleus grammar (reference)

This directory contains the machine-readable grammar used by the packed LL(1)
parser. The language specification remains authoritative for source-language
meaning; these files make its current Stage 7 syntax executable and testable.

`stage7-grammar.json` is Nucleus's grammar, from which `../GRAMMAR.ASM` was
generated. The generator wrote AZM and was retired when the compiler moved to
ATOM (D44); step 67 replaces it with a generator for Basie's grammar.

Expressions, name-led statements, and type-directed aggregate initializers are
deliberate external islands. They require precedence or symbol and type
information that token lookahead alone cannot supply.

The packed statement grammar keeps failure consumption immediate: `else fail`
propagates a direct failable call, while same-line `handle NAME` opens its local
handler body. Boolean `or` remains entirely inside the expression island.

The generated files are locked by `test/ll1-stage7.test.ts`. Run that scoped
test after changing the grammar or generator.
