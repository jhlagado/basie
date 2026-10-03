# 21. Conformance examples


## 21.1 Complete accepted program

This program exercises records, complete aggregate initializers, exact-type record assignment, a checked fixed array, an aggregate alias parameter and result, scalar locals, a counted loop, a conditional chain, a call, and observable output:

```nucleus
record Cell
    value as u8
end

var template as Cell = (1)
var cells as Cell[4] = [(0), (0), (0), (0)]

sub cellAt(index as u8) as Cell
    return cells[index]
end

sub setCell(cell as Cell, value as u8)
    cell.value = value
end

sub main()
    var index as u8
    var code as u8

    for index = 0 until 4
        cells[index] = template
        setCell(template, index + 1)
    end

    cells[0].value = cellAt(0).value
    if cells[0].value = 1
        writeOutputByte('Y') handle code
            return
        end
    elseif cells[0].value = 0
        writeOutputByte('N') handle code
            return
        end
    end
end
```

Each aggregate assignment copies `template` into the selected array element before `template` is changed for the next iteration. The expected standard output is the byte for `Y`, provided the output service succeeds.

## 21.2 Recoverable error and propagation

```nucleus
const badByte = 10

sub checkedByte() as u8 fails
    var value as u8 = readInputByte() else fail
    if value = 0
        fail badByte
    end
    return value
end

sub emitByte() fails
    var value as u8 = checkedByte() else fail
    writeOutputByte(value) else fail
end

sub main() fails
    emitByte() else fail
end
```

For the minimum conformance-corpus run, standard input supplies byte `A` and the output service succeeds; the expected standard output is `A`. More generally, success copies one input byte to output. End of input or a service error propagates its standard code, a zero byte produces `badByte`, and any failure reaching `main` performs the `unhandled-error` trap with that code.

## 21.3 Recursion and control flow

```nucleus
forward sub odd(value as u16) as boolean

sub even(value as u16) as boolean
    if value = 0
        return true
    end
    return odd(value - 1)
end

sub odd
    if value = 0
        return false
    end
    return even(value - 1)
end

sub main()
    var index as u16
    var code as u8

    for index = 0 to 5
        if odd(index)
            continue
        elseif index = 4
            exit
        end
    end

    writeOutputByte(u8(index)) handle code
        return
    end
end
```

The program is valid and writes byte value 4 when the output service succeeds. The Chapter 21 conformance floor requires enough activation capacity for this execution; an implementation may perform `activation-capacity` only beyond its published, conformant limit.

## 21.4 Bounded-string aliasing and byte mutation

```nucleus
var text as string[4] = "A\0B"
var snapshot as string[4]

sub textAlias() as string[4]
    return text
end

sub mutate(value as string[4])
    value[1] = 'Z'
end

sub main() fails
    snapshot = textAlias()

    if snapshot.length = 3 and snapshot[1] = 0
        mutate(textAlias())
    end

    if text[1] = 'Z' and snapshot[1] = 0
        writeOutputByte('Y') else fail
    end
end
```

The literal's embedded zero is an ordinary byte, so its logical length is three. Assignment materializes `textAlias()` by copying it into the program-level `snapshot` object. Passing a second result directly to `mutate` forwards the transient alias without copying, so mutation changes `text` while `snapshot` retains its copied zero byte. The expected standard output is `Y`.

## 21.5 Result-free call propagation

```nucleus
sub emitMarker() fails
    writeOutputByte('R') else fail
end

sub relayMarker() fails
    emitMarker() else fail
    return
end

sub main() fails
    relayMarker() else fail
end
```

When output succeeds, `emitMarker` has no result, `relayMarker` returns successfully, and the expected standard output is `R`. An output failure propagates unchanged through both callers.

## 21.6 Same-destination error handling

```nucleus
const sampleFailure = 7

sub alwaysFails() as u8 fails
    fail sampleFailure
end

sub main() fails
    var code as u8

    code = alwaysFails() handle code
        writeOutputByte(code) else fail
        return
    end

    writeOutputByte(0) else fail
end
```

The failed assignment performs no success-result store and then stores `sampleFailure` in `code`, even though `code` is both destinations. The expected standard output is byte value 7.

## 21.7 Bulk-output cursor state

```nucleus
sub main() fails
    writeStorageByte('A') else fail
    writeStorageByte('B') else fail
    seekStorageOutput(0) else fail
    writeStorageByte('Z') else fail
end
```

The conformance output begins empty with its cursor at zero. The first two calls append `AB`; the seek returns to zero; the final call overwrites the first byte without inserting or truncating. The expected bulk output is `ZB`, with its cursor at offset one.

## 21.8 Runtime loop-range reachability

```nucleus
sub main()
    var index as u8

    for index = 250 to 300 step 10
        exit
    end
end
```

This program is valid and terminates normally with `index` equal to 250. Without the `exit`, the first increment would store 260 if it fit and the loop would continue, so execution would perform `loop-range`; the compiler must not reject the source merely because it can prove that possible runtime path.

## 21.9 Specified trap cases

Each listing below is valid source. The external conformance harness supplies the stated standard-input byte and observes the trap report.

```nucleus
var bytes as u8[2]

sub main() fails
    var index as u8 = readInputByte() else fail
    bytes[index] = 1
end
```

With input byte 2, the required result is `bounds` before the store.

```nucleus
sub divide(value as u16, divisor as u16) as u16
    return value / divisor
end

sub main() fails
    var divisor as u16 = readInputByte() else fail
    var result as u16 = divide(8, divisor)
end
```

With input byte zero, the required result is `division-by-zero`.

```nucleus
sub remainder(value as u16, divisor as u16) as u16
    return value mod divisor
end

sub main() fails
    var divisor as u16 = readInputByte() else fail
    var result as u16 = remainder(8, divisor)
end
```

With input byte zero, the required result is likewise `division-by-zero` at `mod`.

## 21.10 Complete rejected programs

Each program is rejected for the stated independent reason.

Failable call without consumption:

```nucleus
sub readOne() as u8 fails
    var value as u8 = readInputByte() else fail
    return value
end

sub main()
    var value as u8
    value = readOne()
end
```

Aggregate assignment between different nominal types:

```nucleus
record LeftCell
    value as u8
end

record RightCell
    value as u8
end

var left as LeftCell
var right as RightCell

sub main()
    left = right
end
```

Incomplete structured initializer:

```nucleus
record Color
    red as u8
    green as u8
    blue as u8
end

var color as Color = (1, 2)

sub main()
end
```

Aggregate local declaration:

```nucleus
record Cell
    value as u8
end

var cell as Cell

sub cellAlias() as Cell
    return cell
end

sub main()
    var held as Cell = cellAlias()
end
```

Every local must be scalar. A valid materializing form declares `held` as a program variable and assigns `cellAlias()` to it inside a routine.

Value routine with a reachable end:

```nucleus
sub choose(flag as boolean) as u8
    if flag
        return 1
    end
end

sub main()
end
```

Later declaration used before a forward signature:

```nucleus
sub main()
    later()
end

sub later()
end
```

Wrong entry signature:

```nucleus
sub main(argument as u8)
end
```

Assignment to an active counted-loop counter:

```nucleus
sub main()
    var index as u8

    for index = 0 until 4
        index = index + 1
    end
end
```

The counter is a valid scalar local, but it is read-only while its loop is active. A program variable or parameter used as the counter, or reuse of `index` by a nested counted loop, is independently invalid.

Exact integer constant outside the expected range at its use:

```nucleus
const Big = 300
var x as u8

sub main()
    x = Big
end
```

The constant declaration is valid. The assignment is invalid at the use of `Big` because 300 does not fit the destination's expected `u8` type.

Hexadecimal overflow:

```nucleus
const value = $10000

sub main()
end
```

Binary overflow:

```nucleus
const value = %10000000000000000

sub main()
end
```

Both programs fail lexically at the literal prefix. A hexadecimal literal has at most four digits, and a binary literal has at most sixteen.

## 21.11 Multipart input presentation

The conformance harness must also present the complete accepted program in Section 21.1 as at least two ordered source parts. It splits the program after a delimiter-depth-zero logical newline, assigns a distinct stable identity to each part, and otherwise preserves every source byte and the declared order. The expected output remains `Y`.

For the diagnostic case, the harness introduces an undeclared name in the second part. The compiler diagnostic must identify the second part's stable identity and the position of that name within the part. A separate run may use different physical files or transport chunks, but those changes must not alter tokens, declaration visibility, validity, or program behaviour.

The harness must also construct the same ordered parts from this flat manifest, using one selected base directory:

```text
model.nu

main.nu
```

It emits `model.nu` first and `main.nu` second. The blank line adds no part. The manifest text is not presented to the Baton tokenizer, and diagnostics for the second part use `main.nu` as its diagnostic name.

## 21.12 Case-sensitive names and forward parameters

This complete program uses three distinct case variants and a forward parameter binding:

```nucleus
forward sub render(Player as u8) as u8

var player as u8 = 1
var PLAYER as u8 = 2

sub render
    return Player + player + PLAYER
end

sub main() fails
    writeOutputByte(render(3)) else fail
end
```

The expected standard output is byte value 6. The lowercase keywords are recognized as keywords; `Player`, `player`, and `PLAYER` are distinct identifiers. The abbreviated body obtains `Player` from the forward signature.

Changing the body header to `sub Render` makes the program invalid because no incomplete forward named `Render` exists. Writing `SUB render` is also invalid: `SUB` is a `NAME`, not the keyword `sub`.

## 21.13 Caller-supplied aggregate destination

This program copies and changes a record through aggregate parameters without declaring aggregate storage inside the routine:

```nucleus
record Counter
    value as u8
end

var source as Counter = (1)
var destination as Counter

sub copyAndIncrement(input as Counter, output as Counter)
    output = input
    output.value = output.value + 1
end

sub main() fails
    copyAndIncrement(source, destination)
    if source.value = 1 and destination.value = 2
        writeOutputByte('Y') else fail
    end
end
```

`input` and `output` are fixed aliases to caller storage. Complete assignment copies `source` into `destination`, after which the scalar-field assignment changes only `destination`. The expected standard output is `Y`.

## 21.14 Aggregate selection and forwarding

This program returns and forwards an alias to one selected array element:

```nucleus
record Sample
    value as u8
end

var samples as Sample[2] = [(3), (7)]

sub select(items as Sample[2], index as u8) as Sample
    return items[index]
end

sub forwardSelection(items as Sample[2], index as u8) as Sample
    return select(items, index)
end

sub replace(item as Sample, value as u8)
    item.value = value
end

sub main() fails
    replace(forwardSelection(samples, 1), 9)
    if samples[1].value = 9
        writeOutputByte('Y') else fail
    end
end
```

Both result-bearing routines transfer transient aliases to storage inside `samples`. `replace` receives the forwarded alias and mutates the selected original object without an aggregate copy. The expected standard output is `Y`.

## 21.15 Inferred constant types

This program uses one exact integer constant in both integer widths and retains a separate Boolean constant:

```nucleus
const sharedValue = 200
const enabled = true
var byteUse as u8 = sharedValue
var wordUse as u16 = sharedValue

sub main() fails
    if enabled and byteUse = 200 and wordUse = 200
        writeOutputByte('Y') else fail
    end
end
```

`sharedValue` adopts `u8` for `byteUse` and `u16` for `wordUse`. `enabled` has type `boolean`. The expected standard output is `Y`.

## 21.16 Integer literal spellings

This program exercises hexadecimal and binary literals at ordinary and maximum word values:

```nucleus
const hexMask = $FF
const binaryMask = %10110000
const hexMaximum = $ffff
const binaryMaximum = %1111111111111111

sub main() fails
    if hexMask = 255 and binaryMask = 176 and hexMaximum = 65535 and binaryMaximum = 65535
        writeOutputByte(binaryMask) else fail
    end
end
```

All three literal spellings produce the same exact integer category. The expected standard output is byte value 176.

## 21.17 Integer exclusive OR

This program exercises constant and runtime `xor` at both integer widths. It also distinguishes left association at the shared `or` and `xor` precedence level:

```nucleus
const folded = 3 xor 1 or 1
var byteValue as u8 = $a5
var wordValue as u16 = $f0f0

sub main() fails
    byteValue = byteValue xor $ff
    wordValue = wordValue xor $ffff
    if folded = 3 and byteValue = $5a and wordValue = $0f0f
        writeOutputByte(byteValue) else fail
    end
end
```

The expected standard output is byte value 90.

Boolean operands are invalid:

```nucleus
sub main()
    if true xor false
    end
end
```

The second program is rejected at `xor` because exclusive OR is integer-only.

## 21.18 Integer remainder

This program exercises constant and runtime `mod` at both integer widths:

```nucleus
const folded = 100 mod 7
var byteValue as u8 = 250
var wordValue as u16 = 1000

sub main() fails
    byteValue = byteValue mod 16
    wordValue = wordValue mod 256
    if folded = 2 and byteValue = 10 and wordValue = 232
        writeOutputByte(byteValue) else fail
    end
end
```

The expected standard output is byte value 10.

A constant zero divisor is invalid:

```nucleus
const bad = 1 mod 0

sub main()
end
```

The second program is rejected at the zero divisor with the same division-by-zero diagnostic used by `/ 0`.

## 21.19 Compile-time assertions

This program states and uses a relationship between two earlier constants:

```nucleus
const Rows = 8
const Columns = 16
assert Rows * Columns = 128

sub main() fails
    writeOutputByte(Rows * Columns) else fail
end
```

The assertion is true, emits no target code, and the expected standard output is byte value 128.

A false assertion is invalid:

```nucleus
const Rows = 17
assert Rows <= 16

sub main()
end
```

The second program is rejected at `assert` with an assertion-failed diagnostic.

The assertion expression must be Boolean-valued:

```nucleus
const Rows = 8
assert Rows

sub main()
end
```

The third program is rejected at `assert` because an exact integer is not a Boolean condition.

## 21.20 Aggregate constants

This program reads record, array, and bounded-string constants, copies a constant into mutable storage, and deliberately demonstrates the non-transitive alias rule:

```nucleus
record Pair
    left as u8
    right as u16
end

const Origin as Pair = (7, 300)
const Values as u8[3] = [1, 2, 3]
const Text as string[3] = "A\0B"
var target as Pair

sub mutate(item as Pair)
    item.left = 9
end

sub main() fails
    target = Origin
    if target.left = 7 and Values[1] = 2 and Text.length = 3 and Text[2] = 'B'
        mutate(Origin)
        if Origin.left = 9 and target.left = 7
            writeOutputByte('Y') else fail
        end
    end
end
```

The direct named roots are readable aggregate sources. `target = Origin` copies the complete value. Passing `Origin` to `mutate` loses the direct-root read-only marker, so the mutation is permitted; this conformance execution uses writable proof storage and therefore observes the change. Portable programs do not depend on that mutation when a target places constants in physical read-only memory. The expected standard output is `Y`.

A direct constant-rooted assignment is invalid:

```nucleus
record Pair
    value as u8
end

const Origin as Pair = (1)

sub main()
    Origin.value = 2
end
```

The second program is rejected at `Origin`. The same rule rejects assignment to the whole constant, an array element, or a bounded-string byte reached directly from its constant name.
