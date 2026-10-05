# Conformance tests

Each test is a Basie source file, `NAME.bsi`, whose leading comment lines state
what the toolchain must do with it. The runner compiles, links and runs each
test under the CP/M harness and compares the results.

## Expectation lines

Expectations are `//` comments before the first line of code:

| Line | Meaning |
| --- | --- |
| `// expect output: TEXT` | The console output, with `\r`, `\n`, `\t`, `\\` and `\xHH` escapes. Several lines are joined in order |
| `// expect trap: REASON at LINE` | The program traps with this reason inside the statement on this source line |
| `// expect error: CODE at LINE:COLUMN` | Compilation fails with this diagnostic code at this position |
| `// expect link error: CODE` | Linking fails with this linker diagnostic |
| `// expect return: CODE` | The CP/M 3 return code, in decimal or `$`-hexadecimal |
| `// input: TEXT` | Console input supplied to the program, with the same escapes |
| `// tail: TEXT` | The command tail |
| `// file NAME: TEXT` | A file present on the disk before the run |
| `// expect file NAME: TEXT` | A file's contents after the run |
| `// spec: SECTION` | The specification section the test checks; informational |

A test states either errors (compile or link) or a run result, not both.

## Running

`deno task conformance` runs every test. Until the reference compiler handles a
test, it is reported as **pending**, not failed, so the corpus can be written
ahead of the compiler.
