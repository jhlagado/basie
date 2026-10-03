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
character-literal  ::= "'" literal-byte "'"
string-literal     ::= '"' { literal-byte } '"'
escape             ::= "\\0" | "\\n" | "\\r" | "\\t"
                     | "\\'" | '\\"' | "\\\\"
                     | "\\x" hexadecimal-digit hexadecimal-digit
line-comment       ::= "//" { source-byte } (line-ending | EOF)
line-ending        ::= LF | CR LF
```

Sections 3.2 through 3.10 define `literal-byte`, accepted source bytes, maximal token formation, case-sensitive keyword and identifier recognition, numeric range, and lexical errors. Hexadecimal digits also occur in escapes, but an escape remains part of a character or string literal rather than an integer token.

The tokenizer emits `NAME`, `NUMBER`, `CHARACTER`, `STRING`, keyword and punctuation terminals, `NEWLINE`, and `EOF`. It emits `NEWLINE` only at delimiter depth zero, collapses blank or comment-only lines, and synthesizes a source-part-boundary or final logical newline when Sections 3.4 and 4.3 require one. Source-part events and metadata remain outside the token grammar. Those stateful rules are part of the token contract and are not context-free productions.

## 17.2 Syntactic grammar

```text
compilation-unit
    ::= { top-level-declaration } EOF

top-level-declaration
    ::= const-declaration
      | assert-declaration
      | program-var-declaration
      | record-declaration
      | forward-routine
      | routine-definition

const-declaration
    ::= "const" NAME const-declaration-tail
const-declaration-tail
    ::= "=" expression NEWLINE
      | "as" type "=" static-initializer NEWLINE

assert-declaration
    ::= "assert" expression NEWLINE

program-var-declaration
    ::= "var" NAME "as" type [ "=" program-initializer ] NEWLINE
program-initializer
    ::= static-initializer
static-initializer
    ::= expression
      | STRING
      | record-initializer
      | array-initializer
record-initializer
    ::= "(" static-initializer
        { "," static-initializer } ")"
array-initializer
    ::= "[" static-initializer
        { "," static-initializer } "]"

record-declaration
    ::= "record" NAME NEWLINE
        field-declaration { field-declaration }
        "end" NEWLINE
field-declaration
    ::= NAME "as" type NEWLINE

forward-routine
    ::= "forward" routine-header NEWLINE
routine-definition
    ::= "sub" NAME routine-definition-tail
routine-definition-tail
    ::= routine-signature-tail NEWLINE routine-body
      | NEWLINE routine-body
routine-body
    ::= { local-declaration } statement-sequence "end" NEWLINE
routine-header
    ::= "sub" NAME routine-signature-tail
routine-signature-tail
    ::= "(" [ formal-parameter
        { "," formal-parameter } ] ")"
        [ "as" type ] [ "fails" ]
formal-parameter
    ::= NAME "as" type

local-declaration
    ::= "var" NAME "as" scalar-type
        [ "=" local-initializer ] NEWLINE
local-initializer
    ::= expression [ failure-propagation ]

type
    ::= type-atom [ "[" expression "]" ]
type-atom
    ::= scalar-type | NAME | bounded-string-type
scalar-type
    ::= "u8" | "u16" | "boolean"
bounded-string-type
    ::= "string" "[" [ expression ] "]"

statement-sequence
    ::= { statement }
statement
    ::= name-statement name-statement-tail
      | other-simple-statement NEWLINE
      | if-statement
      | while-statement
      | for-statement

name-statement
    ::= assignment-statement
      | routine-call-statement
name-statement-tail
    ::= NEWLINE
      | failure-propagation NEWLINE
      | failure-handler
other-simple-statement
    ::= return-statement
      | "exit"
      | "continue"
      | fail-statement

assignment-statement
    ::= assignment-target "=" assignment-source
assignment-target
    ::= NAME { field-suffix | index-suffix }
assignment-source
    ::= expression

routine-call-statement
    ::= NAME argument-list
return-statement
    ::= "return" [ return-source ]
return-source
    ::= expression
fail-statement
    ::= "fail" expression

failure-propagation
    ::= "else" "fail"
failure-handler
    ::= "handle" NAME NEWLINE
        statement-sequence "end" NEWLINE

if-statement
    ::= "if" expression NEWLINE statement-sequence
        { "elseif" expression NEWLINE statement-sequence }
        [ "else" NEWLINE statement-sequence ]
        "end" NEWLINE

while-statement
    ::= "while" expression NEWLINE
        statement-sequence
        "end" NEWLINE

for-statement
    ::= "for" NAME "=" expression
        for-bound expression
        [ "step" step-constant ] NEWLINE
        statement-sequence
        "end" NEWLINE
for-bound
    ::= "to" | "until"
step-constant
    ::= [ "+" | "-" ] (NUMBER | NAME)

expression
    ::= or-expression
or-expression
    ::= and-expression { ("or" | "xor") and-expression }
and-expression
    ::= not-expression { "and" not-expression }
not-expression
    ::= "not" not-expression | comparison
comparison
    ::= additive [ comparison-operator additive ]
comparison-operator
    ::= "=" | "<>" | "<" | "<=" | ">" | ">="
additive
    ::= multiplicative { ("+" | "-") multiplicative }
multiplicative
    ::= unary { ("*" | "/" | "mod") unary }
unary
    ::= ("+" | "-") unary | postfix-expression
postfix-expression
    ::= primary { postfix-suffix }
primary
    ::= NUMBER | CHARACTER | "true" | "false"
      | NAME | conversion | "(" expression ")"
conversion
    ::= ("u8" | "u16") "(" expression ")"
postfix-suffix
    ::= argument-list | index-suffix | field-suffix
argument-list
    ::= "(" [ expression { "," expression } ] ")"
index-suffix
    ::= "[" expression "]"
field-suffix
    ::= "." NAME
```

The grammar uses the general `expression` nonterminal for scalar constant leaves and type bounds. Chapter 8's constant-context predicate rejects variables, calls, nonconstant operations, and values outside the required range. An omitted bounded-string bound is admitted only in a formal parameter; every other type position rejects it. The declared type and current aggregate component select a scalar expression, string literal, parenthesized record initializer, or bracketed array initializer. This type-directed choice resolves the shared opening `(` of a parenthesized scalar expression and a record initializer without backtracking. `type` permits at most one array suffix outside a bounded-string atom, which admits arrays of scalars, records, and bounded strings but not arrays of arrays.

## 17.3 Semantic predicates

The grammar uses these declared semantic predicates:

| Predicate                      | Decision                                                                                                                                                                           |
| ------------------------------ | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `isCallableName`               | At statement head, select a routine-call statement; in an expression, admit a call suffix only on a visible source routine or service, and retain its result and failure category. |
| `isWritableName`               | At statement head, select assignment only when the resolved declaration is a mutable scalar or aggregate root; an aggregate constant root is rejected before suffix parsing.       |
| `isRecordTypeName`             | Accept a `NAME` as a type atom only when it resolves to a visible record type.                                                                                                     |
| `isInitializerForDeclaredType` | Select and check the scalar, string, positional record, recursive array, or zero-default rule from the declared variable, aggregate constant, or current component type.           |
| `isConstantContext`            | In constants, type bounds, array lengths, string capacities, and program initializers, admit only the compile-time operands and operations from Chapter 8.                         |
| `isIntegerConstantName`        | Admit a `NAME` as a counted-loop step magnitude only when it denotes an earlier `u8` or `u16` constant.                                                                            |
| `isIncompleteForwardName`      | Admit `sub NAME NEWLINE` as a body header only when the exact name resolves to one incomplete forward; install that forward's stored parameter bindings for the body.              |

Field lookup after `.` uses the selected record type, except that a bounded-string base admits only the intrinsic read-only suffix `.length`. Index selection uses a fixed-array domain or a bounded string's current logical length according to the base type; this distinction needs no grammar change. Static initializer checking descends the finite declared type tree and records the expected component before parsing each nested initializer. The `NAME` in `step-constant` must denote an earlier integer constant. A call suffix first produces a call expression with the visible signature's result and failure category. The checker then rejects a failable call unless an eligible initializer, assignment, or complete call statement immediately consumes that direct call under Chapter 14. A return source is always an ordinary successful expression and cannot contain a failable invocation. These are static semantic checks over an otherwise deterministic token stream, not token backtracking.

## 17.4 Predictive analysis

The repository grammar analyzer mechanically expanded the grammar above to 173 BNF rules over 95 nonterminals. It found no nullable-prefix left-recursion cycle, unreachable nonterminal, or unproductive nonterminal. The only predicate-resolved conflict sites are the name-led statement choice and the type-directed initializer choice. The focused test reads this Chapter 17 block directly, so the analyzer evidence does not create a second grammar authority.

| Nonterminal                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                        | Lookahead | Conflict                                           | Resolution                          |
| -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | --------- | -------------------------------------------------- | ----------------------------------- |
| `name-statement`                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                   | `NAME`    | assignment versus routine call                     | `isWritableName` / `isCallableName` |
| `static-initializer`                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                               | `(`       | record initializer versus parenthesized expression | `isInitializerForDeclaredType`      |
| No unexplained FIRST/FIRST or FIRST/FOLLOW conflict remains. The expression repetitions expand to right-recursive analysis rules while their semantic actions preserve the left association specified in Section 9.6. Unary and `not` recursion remains right-recursive by design. `or` is exclusively the Boolean operator. A same-line `else fail` is selected only after a complete name-led statement or local initializer, while `else` at the start of the following logical line remains an `if` clause. The newline makes those cases deterministic without backtracking. The completed source before `else fail` must be exactly one direct failable invocation. Other reported conflicts require their named predicate or an audited equivalent; a compiler must report a specification defect rather than change the language silently. |

The analyzer result checks the collected grammar's formal shape. It does not prove the static compatibility, lifetime, capacity, or flow rules consolidated in Chapter 18.
