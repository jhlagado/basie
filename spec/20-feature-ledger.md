# 20. Feature ledger

## 20.1 Basiq 1.0

Basiq 1.0 is one language (design decision D24). Every conforming compiler provides all of it:

| Area | Forms |
| --- | --- |
| Source | Source parts with `include` and `private`; ASCII source, `//` comments, logical newlines; case-sensitive names; decimal, hexadecimal and binary integers to 32 bits; `f32` literals; characters and strings |
| Types | `u8`, `i8`, `u16`, `i16`, `u32`, `i32`, `f32`, `boolean`; records; fixed arrays, including arrays of arrays; bounded strings; open `string[]` and `T[]` parameters; pools and the handle types `P`, `P?`, `id P`, `id P?`; `File` |
| Declarations | Untyped and typed constants, at top level and in blocks; aggregate constants; compile-time `assert`; program variables; locals at any statement position with block scope; inference from definite initializers; records; pools and forward pools; routines and forward routines |
| Expressions | The numeric rules of D31, explicit checked conversions, shifts, bitwise and logical operators, one comparison, calls, indexing, selection, `move`, `id(...)`, `none`, `new` and `new?` |
| Statements | Assignment, calls, `return`, `fail`, run-time `assert`, `exit`, `continue`; `if`/`elseif`/`else`; `select` on integers, characters, ranges and optional handles, with `select move`; `while`; counted `for` with signed counters and steps |
| Routines | Scalar, aggregate, `var`, handle and slot-holder parameters; leases; results including aggregate aliases with `from`; recursion through forward declarations |
| Memory safety | Program, activation and pool storage; automatic freeing; generations; owner links and the cycle check; the statement rule and the flow check; the stack bound |
| Failure | `fails`, `fail`, `else fail`, `handle`; named failure codes; the traps of Chapter 15 |
| System | Basiq Services revision 2 and the standard library written in Basiq (Chapter 16) |

## 20.2 Implementation-defined limits

An implementation chooses and publishes capacities, never syntax or meaning ([limits register](../docs/limits.md)). Every limit must be high enough to compile and run the conformance suite. Diagnostic wording, internal representations, code generation and the calling convention are implementation choices that must preserve the source rules.

## 20.3 Version 2

Planned for version 2, and not part of Basiq 1.0 (design decision D24): enumerations, and variants whose cases carry data, with exhaustive `select`; expression blocks (O3); arenas (O4); routine values (O5); default parameter values (O6); generics; and `repeat`.

## 20.4 Excluded

Basiq excludes language levels and profiles; macros; raw pointers, address arithmetic, memory and port access, inline machine code and interrupt routines; unrestricted casts; a general heap and garbage collection; exceptions, unwinding, destructors, `finally` and `defer` beyond automatic freeing; overloading; nested routines; multiple results; assignment expressions, chained comparisons and conditional expressions; labels and `goto`; and resumable traps.
