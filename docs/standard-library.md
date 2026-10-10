# Basie standard library

The version 1 standard library (design decision D36; spec §16.4). It is
Basie source in `lib/`, brought in with `include` and tree-shaken by the
linker. A program pays only for the routines it calls, and the compiler
carries none of it. Its routines have no special status: anything here a
program could have written itself. Internal routines are `private`.

## 1. Conventions

- **Failure codes.** Every library routine that can fail names its failure
  enum (spec §14.1, D54). `PARSE.BSI` declares `ParseError`, with one member,
  `badNumber`, for its parsing routines. The others fail with `IoError`, the
  services' enum (`IoError.lineTooLong`, `IoError.endOfInput`,
  `IoError.fileExists`, and any code a service they call returns).
- **Strings.** A routine that writes a string fails with `IoError.lineTooLong` rather
  than exceed the destination's capacity. What it wrote before the failure
  stays. Strings are at most 253 bytes (D25; capacity audit §2.2).
- **Blanks** are spaces and tabs.
- **Positions** count from 0, like indexes.
- **Including.** `FORMAT.BSI` and `TEXTIO.BSI` include `STRINGS.BSI`.
  Including a part twice is harmless: a part is loaded once. Because an
  `include` looks in the including file's own folder first, a program file
  named like a library part (`strings.bsi`, `random.bsi`) hides it.

## 2. Strings: `STRINGS.BSI`

| Routine | Meaning |
| --- | --- |
| `clear(var s: string[])` | Make `s` empty |
| `appendByte(var s: string[], b: u8) fails IoError` | Add one byte |
| `append(var s: string[], t: string[]) fails IoError` | Add `t` |
| `copyFrom(var dest: string[], src: string[], start: u8, count: u8) fails IoError` | `dest` becomes `count` bytes of `src` from `start`, fewer where `src` ends first; empty when `start` is at or past the end |
| `equal(a: string[], b: string[]): boolean` | Same length and bytes |
| `compare(a: string[], b: string[]): i8` | −1, 0 or 1 as `a` sorts before, with or after `b`, byte by byte; a prefix sorts first |
| `find(s: string[], t: string[]): u16` | The position of the first `t` in `s`, or `$FFFF`; an empty `t` is at 0 |
| `toUpper(var s: string[])`, `toLower(var s: string[])` | ASCII letters only |
| `trim(var s: string[])` | Remove leading and trailing blanks |

These rest on one language rule: through a `var string[]` parameter,
`.length` can be assigned, and raising it exposes zero bytes (spec §6.8).
A program can't set the length of its own strings any other way, so `clear`
is how it empties one.

## 3. Numbers to text: `FORMAT.BSI`

| Routine | Meaning |
| --- | --- |
| `appendU16(var s, v: u16)`, `appendI16(var s, v: i16)` | Decimal; a minus sign for negatives |
| `appendU32(var s, v: u32)`, `appendI32(var s, v: i32)` | Decimal |
| `appendHex8(var s, v: u8)`, `appendHex16(var s, v: u16)` | Two or four upper-case hex digits, no prefix |
| `appendF32(var s, x: f32, places: u8)` | Fixed point with `places` decimals, rounded half up; `x` scaled by `10^places` must fit a `u32` |
| `appendIoError(var s, e: IoError)` | The member's name, such as `fileNotFound` |

Each takes `var s: string[]` first and `fails IoError` with `IoError.lineTooLong`.

## 4. Text to numbers: `PARSE.BSI`

| Routine | Accepts |
| --- | --- |
| `parseU16(text: string[]): u16 fails ParseError` | Decimal digits, or `$` and hex digits (either case) |
| `parseU32(text: string[]): u32 fails ParseError` | The same |
| `parseI16(text: string[]): i16 fails ParseError` | An optional `+` or `-`, then decimal digits |
| `parseI32(text: string[]): i32 fails ParseError` | The same |
| `parseF32(text: string[]): f32 fails ParseError` | An optional sign, digits with an optional `.` and fraction (at least one digit in all), and an optional exponent `e` or `E`, sign, digits: `1.5`, `.25`, `3.`, `-6.02e23` |

Blanks may surround the number. Anything else, an empty text, or a value
outside the result type fails with `ParseError.badNumber`, so the full range of each
type parses, including `-32768` and `-2147483648`.

`parseF32` keeps the first 9 significant digits. A value too small for `f32`
becomes zero, following `f32`'s flush-to-zero rule; one too large fails with
`ParseError.badNumber` rather than trapping. The result is the nearest `f32` when the
number has at most 7 significant digits and needs a decimal scale of at most
10 either way, which covers ordinary input. Otherwise it can be up to 3 units
in the last place away: a sweep of 200,000 random cases on the host found no
larger error. Correct rounding in every case would need wider arithmetic
than the library's size justifies.

## 5. Console and files: `TEXTIO.BSI`

| Routine | Meaning |
| --- | --- |
| `writeLine(f: File, s: string[]) fails IoError` | `s`, then CR LF |
| `prompt(text: string[], var answer: string[]) fails IoError` | Write `text` to the console, read one edited line (services §3.3), then write the line feed BDOS 10 leaves out |
| `readSecret(var answer: string[]) fails IoError` | Read keys without echo until return; backspace and delete remove the last character; Control-Z at the start is `IoError.endOfInput`; ends with CR LF |
| `word(text: string[], n: u8, var out: string[]): boolean fails IoError` | Word `n` (0 first), words separated by blanks; false, with `out` empty, when there are fewer |
| `readAll(f: File, var buf: u8[]): u16 fails IoError` | Read to the end of `f`, returning the count; stops when `buf` is full, so a count equal to `buf.length` may mean more remains |
| `truncate(name: string[], newSize: u32, mode: u8) fails IoError` | Cut the file to its first `newSize` bytes |

`readAll` reads as the file's mode does: a text file ends at Control-Z and
its line ends read as one byte each, while a binary file reads whole 128-byte
records, padding included (services §4.3).

`truncate` copies, because CP/M 2.2 can't shorten a file. It copies the
prefix to `NAME.~`, deletes the file and renames the copy, so a failure
part-way leaves the original whole. In `textMode` it counts and copies bytes
as text mode reads them and writes a text file. In `binaryMode` it copies raw
bytes, and the last record is padded with zeros. It fails with `fileExists`,
touching nothing, if `NAME.~` already exists, since that file may be the
user's. (The runtime reserves file types beginning with `$` for its own
temporaries.)

A command line is `commandTail` (services §5) split with `word`. CP/M's CCP
upper-cases the tail before the program sees it.

## 6. Pseudo-random numbers: `RANDOM.BSI`

| Routine | Meaning |
| --- | --- |
| `seedRandom(seed: u16)` | Restart the sequence from `seed`; 0 chooses the default |
| `random(): u16` | The next value, 1 to 65535 |
| `randomBelow(n: u16): u16` | 0 to `n` − 1, each equally likely; 0 when `n` is 0 |

The generator is a 16-bit xorshift with shifts 7, 9 and 8. From any non-zero
seed it visits every value from 1 to 65535 once before repeating. Without
`seedRandom`, every run gives the same sequence, which suits tests. A
game seeds it from something that varies, such as how long the player takes
to press a key. `randomBelow` rejects the few values that would favour small
results, so it is unbiased. None of this is suitable for cryptography.

## 7. Tests

Each part has conformance programs in `tests/conformance/library/`, run
under the CP/M harness with the rest of the corpus. The expected values of
`RANDOM.BSI` were computed on the host, and the `parseF32` cases were checked
against host IEEE single arithmetic.
