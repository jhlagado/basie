# 17. Complete grammar


## 17.1 Notation and lexical boundary

Quoted words and punctuation are terminals. Uppercase names are token categories from Chapter 3. Lowercase hyphenated names are nonterminals. `{ X }` means zero or more repetitions, `[ X ]` means optional, parentheses group alternatives, and `|` separates alternatives.

The lexical forms are:

```text
ascii-letter       ::= "A".."Z" | "a".."z"
decimal-digit      ::= "0".."9"
hexadecimal-digit  ::= decimal-digit | "A".."F" | "a".."f"
binary-digit       ::= "0" | "1"

identifier         ::= ascii-letter
                       { ascii-letter | decimal-digit | "_" }
integer-literal    ::= decimal-digit { decimal-digit }
                     | "$" hexadecimal-digit { hexadecimal-digit }
                     | "%" binary-digit { binary-digit }
float-literal      ::= decimal-digit { decimal-digit }
                       "." decimal-digit { decimal-digit } [ exponent ]
                     | decimal-digit { decimal-digit } exponent
exponent           ::= ( "e" | "E" ) [ "+" | "-" ]
                       decimal-digit { decimal-digit }
character-literal  ::= "'" literal-byte "'"
string-literal     ::= '"' { literal-byte } '"'
escape             ::= "\\0" | "\\n" | "\\r" | "\\t"
                     | "\\'" | '\\"' | "\\\\"
                     | "\\x" hexadecimal-digit hexadecimal-digit
line-comment       ::= "//" { source-byte } (line-ending | EOF)
line-ending        ::= LF | CR LF
```

Sections 3.2 through 3.10 define `literal-byte`, accepted source bytes, maximal token formation, case-sensitive keyword and identifier recognition, numeric range, and lexical errors. Hexadecimal digits also occur in escapes, but an escape remains part of a character or string literal rather than an integer token.

The tokenizer emits `NAME`, `NUMBER`, `FLOAT`, `CHARACTER`, `STRING`, keyword and punctuation terminals, `NEWLINE`, and `EOF`. It emits `NEWLINE` only at delimiter depth zero, collapses blank or comment-only lines, and synthesizes a source-part-boundary or final logical newline when Sections 3.4 and 4.3 require one. Source-part events and metadata remain outside the token grammar. Those stateful rules are part of the token contract and are not context-free productions.

## 17.2 Syntactic grammar

```text
compilation
    ::= source-part { source-part } EOF
source-part
    ::= { include-line } { top-level-declaration }
include-line
    ::= "include" STRING NEWLINE

top-level-declaration
    ::= [ "private" ] declaration
      | assert-declaration
declaration
    ::= const-declaration
      | program-var-declaration
      | record-declaration
      | enum-declaration
      | pool-declaration
      | forward-declaration
      | routine-definition

const-declaration
    ::= "const" NAME [ ":" type ] "=" static-initializer NEWLINE
assert-declaration
    ::= "assert" expression NEWLINE

program-var-declaration
    ::= "var" NAME ":" type [ "=" static-initializer ] NEWLINE
static-initializer
    ::= expression
      | STRING
      | record-initializer
      | array-initializer
record-initializer
    ::= "(" static-initializer { "," static-initializer } ")"
array-initializer
    ::= "[" static-initializer { "," static-initializer } "]"

enum-declaration
    ::= "enum" NAME NEWLINE
        NAME NEWLINE { NAME NEWLINE }
        "end" NEWLINE

record-declaration
    ::= "record" NAME NEWLINE
        field-declaration { field-declaration }
        "end" NEWLINE
field-declaration
    ::= NAME ":" type NEWLINE

pool-declaration
    ::= "pool" NAME ":" NAME "[" expression "]" NEWLINE
forward-declaration
    ::= "forward" ( "pool" NAME | routine-header ) NEWLINE

routine-definition
    ::= "sub" NAME [ routine-signature-tail ] NEWLINE
        block "end" NEWLINE
routine-header
    ::= "sub" NAME routine-signature-tail
routine-signature-tail
    ::= "(" [ formal-parameter { "," formal-parameter } ] ")"
        [ result-clause ] [ "fails" ]
formal-parameter
    ::= [ "var" ] NAME ":" type
result-clause
    ::= ":" [ "var" ] type [ "from" NAME { "," NAME } ]

type
    ::= type-atom { "[" [ expression ] "]" }
type-atom
    ::= scalar-type
      | "string" "[" [ expression ] "]"
      | "id" NAME [ "?" ]
      | NAME [ "?" ]
scalar-type
    ::= "u8" | "i8" | "u16" | "i16" | "u32" | "i32" | "f32" | "boolean"

block
    ::= { statement }
statement
    ::= local-declaration
      | name-statement name-statement-tail
      | "try" name-statement NEWLINE
      | other-simple-statement NEWLINE
      | if-statement
      | select-statement
      | while-statement
      | for-statement
local-declaration
    ::= "var" NAME ( ":" type [ "=" local-initializer ]
                   | "=" local-initializer ) NEWLINE
      | "const" NAME [ ":" type ] "=" static-initializer NEWLINE
local-initializer
    ::= [ "try" ] expression
      | STRING
      | record-initializer
      | array-initializer

name-statement
    ::= NAME { postfix-suffix } [ "=" [ "try" ] expression ]
name-statement-tail
    ::= NEWLINE
      | "handle" NAME NEWLINE block "end" NEWLINE
other-simple-statement
    ::= "return" [ expression ]
      | "fail" expression
      | "assert" expression
      | "exit"
      | "continue"

if-statement
    ::= "if" expression NEWLINE block
        { "elseif" expression NEWLINE block }
        [ "else" NEWLINE block ]
        "end" NEWLINE

select-statement
    ::= "select" [ "move" ] expression NEWLINE
        case-arm { case-arm }
        "end" NEWLINE
case-arm
    ::= "case" case-selector NEWLINE block
case-selector
    ::= "else"
      | "none"
      | "some" "(" NAME ")"
      | case-label { "," case-label }
case-label
    ::= expression [ "to" expression ]

while-statement
    ::= "while" expression NEWLINE block "end" NEWLINE
for-statement
    ::= "for" NAME "=" expression ( "to" | "until" ) expression
        [ "step" [ "+" | "-" ] ( NUMBER | NAME ) ] NEWLINE
        block "end" NEWLINE

expression
    ::= and-expression { ( "or" | "xor" ) and-expression }
and-expression
    ::= not-expression { "and" not-expression }
not-expression
    ::= "not" not-expression
      | additive [ comparison-operator additive ]
comparison-operator
    ::= "=" | "<>" | "<" | "<=" | ">" | ">="
additive
    ::= multiplicative { ( "+" | "-" ) multiplicative }
multiplicative
    ::= unary { ( "*" | "/" | "mod" | "shl" | "shr" ) unary }
unary
    ::= ( "+" | "-" ) unary
      | postfix-expression
postfix-expression
    ::= primary { postfix-suffix }
primary
    ::= NUMBER | FLOAT | CHARACTER | "true" | "false" | "none"
      | NAME
      | scalar-type "(" expression ")"
      | "(" expression ")"
      | "move" NAME { "[" expression "]" | "." NAME }
      | "id" "(" expression ")"
      | "new" [ "?" ] NAME argument-list
postfix-suffix
    ::= argument-list
      | "[" expression "]"
      | "." NAME
argument-list
    ::= "(" [ argument { "," argument } ] ")"
argument
    ::= [ "var" ] expression | STRING
```

`boolean(...)` matches the conversion production but is rejected semantically: there is no conversion to `boolean`. The `case-arm` sequence is constrained by Chapter 11: integer labels and `some`/`none` arms do not mix, and `case else` comes last. In `name-statement`, the `=` is required for an assignment and absent for a call; Section 17.3 selects between them. `"id" NAME` in `type-atom` and `"id" "("` in `primary` are the contextual uses of `id` (Chapter 3).

## 17.3 Semantic predicates

The grammar is deterministic with one token of lookahead, given these semantic predicates, each decided from declarations already seen:

| Predicate | Decision |
| --- | --- |
| `isCallableName` | At a statement head, the `NAME` is a routine or service: the statement is a call, and its suffixes must begin with an argument list. |
| `isWritableName` | At a statement head, the `NAME` is a variable, parameter or local: the statement is an assignment, and must contain `=`. |
| `isTypeName` | A `NAME` in a type is a record type or a pool; `?` is admitted only after a pool name. |
| `isContextualId` | `id` begins a handle type when followed by a pool name, and the `id(...)` form whenever followed by `(`, since no routine may be named `id`; otherwise it is a `NAME`. |
| `isInitializerForDeclaredType` | The declared type selects the scalar, string, record or array initializer; `(` begins a record initializer only when the expected type is a record. |
| `isConstantContext` | Constants, bounds, capacities, `select` labels, steps and static initializers admit only the operands of Chapter 8, Section 8.6. |
| `isIncompleteForwardName` | `sub NAME NEWLINE` is a body header only when `NAME` is one incomplete forward routine; its stored parameters become the body's bindings. |
| `isFailableCall` | `try` precedes, and `handle` follows, only a complete statement or initializer whose source is exactly one direct call to a failing routine. |

After an enum type name, `.NAME` resolves a qualified member of that enum (Section 6.16). Otherwise, field lookup after `.` uses the selected record or handle type, or the string intrinsics `.length` and `.capacity`. Static initializer checking descends the declared type and records the expected component before each nested initializer. These are static checks over a deterministic token stream, not backtracking.

## 17.4 Predictive analysis

The only predicate-resolved choices are the name-led statement (assignment or call), the type-directed initializer, and the contextual word `id`. The expression repetitions are written iteratively and associate to the left as Chapter 9, Section 9.3 specifies; unary operators and `not` are right-recursive by design.

Read as plain LL(1), the grammar has the conflicts below and no others. Each is resolved as the table says, by a predicate of Section 17.3 or by a fixed preference, so the parser still needs one token of lookahead and never backtracks.

| Rule | Tokens | Resolution |
| --- | --- | --- |
| `compilation` | `EOF` | Source-part boundaries are events of the include mechanism (Chapter 4, Section 17.1), not tokens, so the parser always knows where a part ends. |
| `source-part` | `include` | The same: an `include` line belongs to the part that holds it. |
| `source-part` | `assert` `const` `forward` `pool` `private` `record` `enum` `sub` `var` | The same: a declaration belongs to the part that holds it. |
| `static-initializer` | `(` | `isInitializerForDeclaredType`: `(` begins a record initializer when the expected type is a record, and a parenthesised expression otherwise. |
| `local-initializer` | `(` | The same predicate. |
| `case-selector` | `none` | `case none` is always the handle arm. An integer label can't be `none`, so nothing is lost. |
| `select-statement` | `move` | `select move` is always the moving form (Section 11.7.3). The form `select (move x)` is not needed: a moved value has no storage to select. |
| `primary` | `NAME` | `isContextualId`: `id` lexes as a `NAME`; followed by `(` it begins `id(...)`, and otherwise it is an ordinary name. |
| `type-atom` | `NAME` | `isContextualId`: in a type, `id` followed by a pool name begins an identifier type; any other `NAME` is a type name. |
| `primary` | `.` `[` | After `move NAME`, every following `.` and `[` extends the moved path. A moved handle can't be indexed or selected through, so no other reading is valid. |

A mechanical check of this grammar for left recursion, unreachable or unproductive nonterminals and conflicts not in this table is part of the conformance tooling (`tools/grammar.ts`, run by `tests/grammar_test.ts`). It reads the grammar from Section 17.2 and the table above, treating the contextual words of Chapter 3 as `NAME` as the lexer does, and also checks that the grammar's keywords and punctuation are those of Chapter 3 and of the reference lexer. It checks the grammar's shape, not the static rules collected in Chapter 18.
