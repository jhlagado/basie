# 3. Source text and lexical rules


## 3.1 Scope

This chapter defines how the source bytes in each ordered source part become one logical token stream. It defines source bytes, line endings, whitespace, comments, names, reserved words, literals, punctuation, source positions, and lexical errors. Chapter 4 defines the multipart input around those bytes. Later chapters define grammar, name resolution, types, expression precedence, and runtime meaning.

The rules are deterministic and require no backtracking. Rules stated for source text, token identity, or lexical errors apply to every conforming compiler. Project acceptance requires the first compiler to consume the source in order with bounded state and without retaining a complete source copy. This is a Chapter 2 project constraint, not a required internal organization for another compiler. Another compiler may organize tokenization differently, but it must produce the same tokens. One byte of lookahead is sufficient for every token rule in this chapter.

## 3.2 Source bytes

A Baton source part is a sequence of bytes in an ASCII-compatible encoding. The accepted source-byte repertoire is:

| Bytes        | Use              |
| ------------ | ---------------- |
| `09`         | horizontal tab   |
| `0A`         | LF line ending   |
| `0D 0A`      | CRLF line ending |
| `20` to `7E` | printable ASCII  |

`0D` is valid only as the first byte of CRLF. A lone CR is a lexical error. Every other byte, including NUL, vertical tab, form feed, DEL, bytes above `7F`, and a UTF-8 byte-order mark, is a lexical error.

EOF is an input condition, not a source byte. An implementation may use an internal sentinel when its source interface cannot return a separate EOF condition, but that sentinel must not be accepted as source text.

This repertoire excludes Unicode identifiers, Unicode normalization, and locale-dependent character classification. Escape sequences may denote byte values outside printable ASCII without placing those values in the source stream.

## 3.3 Lines and source positions

LF and CRLF each form one physical line ending. The tokenizer normalizes either spelling to the same line-break event. A final physical line need not contain a line ending.

Diagnostics must identify a reproducible source position. Each source part starts at byte offset zero, line one, and byte column one. Each token has the stable source-part identity from Section 4.3, a half-open byte span within that part, and a one-based line and byte column for the span's start. Each lexical error identifies:

- the stable source-part identity;
- a zero-based byte offset within that part;
- a one-based line number; and
- a one-based byte column within that line.

When CRLF produces `NEWLINE`, its two bytes occupy one token span, advance the byte offset by two, and advance the line number once. A synthesized source-part-boundary or final `NEWLINE` has a zero-width span at the end of its source part. A horizontal tab advances the byte column by one; the column is not a display-cell count. The optional diagnostic name from Section 4.3 may accompany a diagnostic but does not replace the stable identity. These counters permit streaming diagnostics without a resident source map. An implementation that bounds a counter or source-part length must publish the limit and diagnose overflow.

## 3.4 Whitespace, comments, and logical newlines

ASCII space and horizontal tab are the only horizontal whitespace. They separate tokens where separation is needed and are otherwise ignored. Indentation has no syntactic meaning. Whitespace never joins adjacent names, numbers, or literals into one token.

`//` begins the one ordinary comment form. It is recognized outside character and string literals and consumes bytes up to, but not including, the next physical line ending or EOF. The comment produces no token. A line comment at EOF is complete; it does not require a closing marker. Baton 1.0 has no block, nested, or documentation comments.

A logical newline is the only statement terminator. Baton has no semicolon terminator and no second interchangeable terminator.

Delimiter state tracks open parentheses and square brackets. A physical line ending produces `NEWLINE` only when no delimiter is open. Inside either delimiter, a physical line ending is whitespace and produces no token. Parentheses and brackets inside a comment or literal do not affect this state. The first compiler represents it with a bounded stack; another compiler may use a different representation.

This is a tokenizer-parser interface rule rather than statement grammar: the tokenizer emits `NEWLINE` under this rule, while later chapters specify which grammar positions accept it. Delimiter state must distinguish `(` from `[`. A closing delimiter with no matching opener, a mismatched closing delimiter, an open delimiter at EOF, or implementation-capacity exhaustion is diagnosed.

Blank and comment-only physical lines produce no `NEWLINE`. Consecutive physical line endings therefore cannot create empty statements. After any token on a delimiter-depth-zero line, its physical line ending produces one `NEWLINE`. Section 4.3 supplies the same line-ending event at a source-part boundary when the part has no final physical line ending. If EOF follows a token line without either event, the tokenizer emits one final `NEWLINE` before `EOF`. EOF following an empty or comment-only final line produces only `EOF`.

Examples:

```nucleus
total = (first +
    second)

value = table[
    index
]
```

Neither physical line ending inside the delimiters produces `NEWLINE`. By contrast, this source contains a logical newline after `+` and is rejected later by the statement or expression grammar:

```nucleus
total = first +
second
```

## 3.5 Identifiers and reserved words

An identifier begins with an ASCII letter. Each following byte is an ASCII letter, decimal digit, or underscore:

```text
identifier ::= ascii-letter (ascii-letter | decimal-digit | "_")*
```

Leading underscores are not identifiers. Baton does not assign implementation names through a source spelling convention; compiler-generated names remain outside the source namespace.

Identifiers are case-sensitive and preserve their source spelling. `Player`, `player`, and `PLAYER` are three distinct identifiers. No locale participates in comparison.

The complete preserved spelling is an identifier's identity. An implementation must not fold case, truncate a spelling, compare only a prefix, or treat an unchecked hash match as equality. It may use hashes to locate candidates only if it resolves collisions by exact byte comparison. An implementation may impose a maximum identifier length and a maximum number of retained names. It must publish each limit, and exceeding one is a capacity diagnostic.

After scanning the longest identifier, the tokenizer compares its exact spelling with a fixed reserved-word table. A reserved word is recognized only in the canonical lowercase spelling listed below. A longer name is never split at a keyword boundary: `elseifReady` is one `NAME`, not `elseif` followed by `NAME`.

The Baton 1.0 reserved words are:

```text
and      as       assert   boolean  case     const    continue
else     elseif   end      exit     f32      fail     fails
false    for      forward  handle   i16      i32      i8
if       include  mod      move     new      none     not
or       pool     private  record   return   select   shl
shr      some     step     string   sub      to       true
u16      u32      u8       until    var      while    xor
```

`id` is a **contextual word**, not a reserved word: it is a keyword only where a
type is expected and it is followed by a pool name (`id nodes`), and in the
conversion form `id(...)`. Everywhere else it is an ordinary identifier, so a
record may have a field named `id`.

`elseif` is one keyword. `else if` produces the two keywords `else` and `if` and does not form an `elseif` clause. `ELSEIF` is a `NAME`, not a keyword.

Chapter 14 defines the recoverable-error forms that use `fail`, `fails`, and `handle`. `on` and `error` are ordinary identifiers.

Baton uses name-led routine invocation and has no `call` keyword. `call` remains an identifier.

## 3.6 Numeric literals

Baton admits unsigned decimal, hexadecimal, and binary integer literals, and
decimal floating-point literals:

```text
decimal-literal ::= decimal-digit+
hexadecimal-literal ::= "$" hexadecimal-digit+
binary-literal ::= "%" binary-digit+
integer-literal ::= decimal-literal
                  | hexadecimal-literal
                  | binary-literal
```

Hexadecimal digits may use either letter case. The `$` and `%` prefixes are part of the literal and do not form separate punctuation tokens. A prefix must be followed by at least one digit of its base.

The tokenizer computes an exact unsigned value from zero through 4,294,967,295, the range of `u32`. A decimal literal whose value exceeds 4,294,967,295 is a lexical error. A hexadecimal literal may contain at most eight digits, and a binary literal may contain at most thirty-two digits; an additional digit is an overflow even when it is a leading or trailing zero. Later type checking decides whether the value fits its context, including each integer type, an array bound, or a counted-loop parameter.

A **floating-point literal** is written in decimal with a decimal point, an exponent, or both:

```text
float-literal ::= decimal-digit+ "." decimal-digit+ exponent?
                | decimal-digit+ exponent
exponent      ::= ("e" | "E") ("+" | "-")? decimal-digit+
```

A digit is required on both sides of the decimal point, so `1.0`, `0.25`, `1e3` and `2.5e-3` are valid and `.5` and `5.` are not. The tokenizer converts the literal to the nearest `f32` value, rounding to nearest with ties to even and flushing values below the smallest normal `f32` to zero (design decision D7). A literal whose value exceeds the largest finite `f32` is a lexical error. A floating-point literal has type `f32`; it never adapts to an integer context.

A leading `+` or `-` is a separate punctuation token and is never part of the literal. Thus `-32768` begins with `-` followed by the literal `32768`; expression and constant rules determine whether that combination is valid.

A letter or underscore immediately following any numeric literal makes the numeric token malformed instead of beginning an adjacent identifier, except for the `e` or `E` that begins an exponent of a decimal literal. This rejects forms such as `0x2a`, `12u8`, `$ffu8`, `1.5f` and `%10value` with one diagnostic. A decimal digit other than zero or one inside a binary literal is likewise malformed rather than the start of a following decimal token. A decimal point after a hexadecimal or binary literal is not part of it.

Octal literals, hexadecimal floating-point literals, numeric separators and type suffixes are absent. In particular, `1_000` and `42u8` are not alternative integer spellings. The later word operator `mod` is distinct from the `%` binary-literal prefix.

## 3.7 Character and string literals

A character literal uses single quotes and denotes exactly one decoded byte. A string literal uses double quotes and denotes a possibly empty sequence of decoded bytes:

```text
character-literal ::= "'" literal-byte "'"
string-literal    ::= '"' literal-byte* '"'
```

A direct literal byte is printable ASCII from space through `~`, excluding the literal's closing quote and backslash. A single quote may appear directly in a string, and a double quote may appear directly in a character literal.

Both literal forms accept only these escapes:

```text
\0  \n  \r  \t  \'  \"  \\  \xHH
```

`HH` is exactly two hexadecimal digits. The escape letters are lowercase; hexadecimal digits may use either case. The decoded values of `\0`, `\n`, `\r`, and `\t` are 0, 10, 13, and 9. `\xHH` contributes the byte whose value is `HH`.

A character literal must decode to exactly one byte. `''` and `'ab'` are errors. A string literal may decode to zero bytes, so `""` is valid. A physical line ending or EOF before the closing quote is an unterminated-literal error. A backslash followed by a physical line ending does not continue a literal.

The token records decoded bytes. Later chapters determine which character or bounded-string contexts accept those bytes. The tokenizer does not infer a string capacity or type from a literal.

Baton 1.0 has no interpolated, raw, or multiline literal family. It has no Unicode escape or encoding conversion. Adjacent string literals remain separate tokens; the tokenizer does not concatenate them.

An implementation may impose a maximum decoded literal length. It must publish the limit and diagnose an excess before discarding, wrapping, or truncating any byte.

## 3.8 Operators, punctuation, and delimiters

The tokenizer recognizes these punctuation tokens:

| Spelling | Token or use                                           |
| -------- | ------------------------------------------------------ |
| `(` `)`  | grouping, calls, declarations, and record initializers |
| `[` `]`  | array types, indexing, and array initializers          |
| `,`      | item and argument separator                            |
| `.`      | record-field selection; also the decimal point inside a floating-point literal |
| `?`      | the optional suffix on a handle type (`nodes?`)        |
| `+` `-`  | arithmetic punctuation; also unary punctuation         |
| `*` `/`  | arithmetic punctuation                                 |
| `=`      | assignment or equality, according to grammar context   |
| `<>`     | not equal                                              |
| `<` `<=` | less-than comparisons                                  |
| `>` `>=` | greater-than comparisons                               |

Chapter 9 defines which expression operators are admitted, their operand types, precedence, and associativity. Listing a punctuation token here defines its formation, not every grammar position in which it is valid.

At each punctuation start, the tokenizer uses deterministic longest match. It recognizes `//` before `/`, and `<>`, `<=`, and `>=` before their one-character prefixes. No other two-character punctuation token is formed. `!=` and `==` are not comparison spellings.

Braces, colon, semicolon, hash, at sign, and backtick have no token in this draft. A source byte that begins no name, number, literal, comment, whitespace, line ending, or listed punctuation token is a lexical error. Baton 1.0 has no lexical preprocessor directive or macro form.

## 3.9 Token contract

The tokenizer emits the following token categories. Identifier spelling is part of the token contract.

| Category    | Payload                                                       |
| ----------- | ------------------------------------------------------------- |
| `NAME`      | exact preserved identifier spelling and source span           |
| keyword     | fixed reserved-word ordinal and source span                   |
| `NUMBER`    | exact integer value from 0 through 4,294,967,295 and source span |
| `FLOAT`     | the nearest `f32` value and source span                        |
| `CHARACTER` | one decoded byte and source span                              |
| `STRING`    | decoded byte sequence and source span                         |
| punctuation | fixed punctuation ordinal and source span                     |
| `NEWLINE`   | source position of the terminating physical line or final EOF |
| `EOF`       | final source position                                         |

Comments and horizontal whitespace produce no tokens. `EOF` is emitted after any synthesized final `NEWLINE` and marks the end of the token stream.

For reuse in Chapter 17, the lexical grammar is:

```text
ascii-letter       ::= "A".."Z" | "a".."z"
decimal-digit      ::= "0".."9"
hexadecimal-digit  ::= decimal-digit | "A".."F" | "a".."f"
binary-digit       ::= "0" | "1"

identifier         ::= ascii-letter
                       (ascii-letter | decimal-digit | "_")*
integer-literal    ::= decimal-digit+
                     | "$" hexadecimal-digit+
                     | "%" binary-digit+
float-literal      ::= decimal-digit+ "." decimal-digit+ exponent?
                     | decimal-digit+ exponent
exponent           ::= ("e" | "E") ("+" | "-")? decimal-digit+
character-literal  ::= "'" literal-byte "'"
string-literal     ::= '"' literal-byte* '"'
literal-byte       ::= direct-literal-byte | escape
escape             ::= "\\0" | "\\n" | "\\r" | "\\t"
                     | "\\'" | '\\"' | "\\\\"
                     | "\\x" hexadecimal-digit hexadecimal-digit
line-comment       ::= "//" source-byte* (line-ending | EOF)
line-ending        ::= LF | CR LF
```

`direct-literal-byte` and the different closing delimiters obey Section 3.7. `source-byte*` in `line-comment` stops before a line ending. `NEWLINE` synthesis and delimiter suppression are stateful interface rules from Section 3.4 rather than context-free productions.

## 3.10 Lexical errors and bounded failure

The first compiler stops after its first lexical diagnostic. Another compiler may continue only to report additional diagnostics; it must not accept the source by guessing, replacing, truncating, or silently resynchronizing tokens, and it must not report successful compilation.

Lexical errors include:

- a byte outside the accepted source repertoire;
- a lone CR;
- a malformed or out-of-range numeric literal;
- an unknown or incomplete escape;
- an empty or multi-byte character literal;
- a character or string literal terminated by a physical line ending or EOF;
- an unrecognized punctuation byte;
- an identifier or literal longer than a documented capacity;
- delimiter-nesting capacity exhaustion, unmatched or mismatched delimiters, or an open delimiter at EOF; and
- source-position or other published tokenizer-capacity exhaustion.

The `//` form cannot be unterminated because a physical line ending or EOF completes it. Text beginning `/*` is not a block comment; it begins `/` and `*` tokens and is rejected if the later grammar has no valid use for them.

Capacity failure must not change token identity. In particular, an overlong name or literal must not be truncated, split, wrapped, or accepted through a hash collision. The diagnostic must identify the capacity that was exceeded.

## 3.11 Token examples

| Source                     | Result or required diagnostic                 |
| -------------------------- | --------------------------------------------- |
| `player_2`                 | one `NAME`                                    |
| `_player`                  | lexical error at `_`                          |
| `elseif`                   | one `ELSEIF` keyword                          |
| `ELSEIF`                   | one `NAME`; keywords require lowercase        |
| `elseifReady`              | one `NAME`                                    |
| `else if`                  | `ELSE IF`; not an `ELSEIF` clause             |
| `42`                       | `NUMBER(42)`                                  |
| `-42`                      | `- NUMBER(42)`                                |
| `$2a`                      | `NUMBER(42)`                                  |
| `0x2a`                     | malformed-number diagnostic                   |
| `%00101010`                | `NUMBER(42)`                                  |
| `$10000`                   | malformed-number diagnostic; too many digits  |
| `%10000000000000000`       | malformed-number diagnostic; too many digits  |
| `'A'`                      | `CHARACTER(65)`                               |
| `'\x41'`                   | `CHARACTER(65)`                               |
| `''`                       | empty-character diagnostic                    |
| `""`                       | empty `STRING`                                |
| `"A\nB"`                   | `STRING` containing bytes 65, 10, 66          |
| `"A\q"`                    | invalid-escape diagnostic                     |
| `a <= b`                   | `NAME <= NAME`                                |
| `a != b`                   | lexical error at `!`                          |
| `a; b`                     | lexical error at `;`                          |
| `a / / b`                  | `NAME / / NAME`; not a comment                |
| `a // note` followed by LF | `NAME NEWLINE`; the comment produces no token |

For this source:

```nucleus
check(
    table[index]
)
```

the token sequence is:

```text
NAME ( NAME [ NAME ] ) NEWLINE EOF
```

The two physical line endings inside delimiters do not appear in the token sequence.

## 3.12 Reserved-word and literal decisions

Chapter 10 admits `assert` (D37). Chapter 9 admits `mod`, `not`, `and`, `or`, `xor`, `shl` and `shr`, and `move`. Chapter 11 admits `select`, `case`, `some` and `none`. Chapter 4 admits `include` and Chapter 5 `private` (D33). Chapter 7 admits `pool` and `new`. Chapter 6 admits the type names `i8`, `i16`, `u32`, `i32` and `f32`. Chapter 14 admits `fail`, `fails`, and `handle`. `id` is contextual (D29). Chapter 11 omits a conditional header marker, so `then` remains an identifier. Baton integer literals use decimal digits, `$` hexadecimal, or `%` binary, and floating-point literals use decimal digits with a decimal point or an exponent (D31). A later revision that needs another token requires an amendment here and cost accounting for the added scanner, table, test, and diagnostic work.
