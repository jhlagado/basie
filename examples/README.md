# Basie examples

Three complete programs, each a single source file using the standard
library. Compile one with the reference toolchain:

```bash
deno task basie examples/ADVENT.BSI build/ADVENT.COM
```

Then copy the `.COM` file to a CP/M 2.2 disk and run it.

| Program | What it shows |
| --- | --- |
| [`ADVENT.BSI`](ADVENT.BSI) | A small text adventure: constant tables of records, program variables, `prompt`, `word` and string comparison |
| [`DUMP.BSI`](DUMP.BSI) | A file utility: hex and ASCII dump of the file named on the command line, using `commandTail`, binary reads and hex formatting |
| [`BUGS.BSI`](BUGS.BSI) | A turn-based game whose bugs live in a pool, chained in a list that owns them; zapping one frees its slot, and `new?` finds the pool full |

`tests/examples_test.ts` plays scripted sessions of each, compares them with
recorded transcripts in `tests/examples/`, and runs the same sessions under
real CP/M 2.2 on the Triptych machine.
