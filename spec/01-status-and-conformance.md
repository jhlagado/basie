# 1. Status and conformance


## 1.1 Status

This specification is a working draft. Basie 1.0 has not been frozen or released as a standard, and later revisions may change rules recorded here. This revision defines the complete proposed Basie 1.0 source language and supports conformance review, but the project may still correct it before the freeze.

The current software development line is **0.1**. The **1.0** designation in
this specification refers to the proposed language standard when ready to
stabilize, not to a delivered toolchain release. The previously named "version
two" development work is the **next development milestone**; no next software
release number is assigned. These labels do not change source semantics,
conformance requirements, target contracts or binary format versions.

The language under design is named **Basie 1.0**. It has one source language: no language levels, selectable language profiles, or compiler-selected subsets of standard syntax exist.

## 1.2 Scope

This specification defines the source-language syntax, static semantics, runtime semantics, required diagnostics, specified safety failures, and abstract compilation-input contract of Basie 1.0. It defines the conditions for a source program or compiler to claim Basie 1.0 conformance.

The separate implementation contracts define how a program is represented and run: [code generation](../docs/code-generation.md) (frames, calls and helpers), [memory safety](../docs/memory-safety.md) (the pool and handle machinery), [services](../docs/services.md) (the services Chapter 16 makes normative), the [CP/M target](../docs/cpm-target.md) and the [object format](../docs/object-format.md). Non-normative implementation plans and design papers record compiler strategies and project constraints; they do not add source-language semantics.

Basie is implemented twice: a reference toolchain in TypeScript, and a native compiler and linker, `BASIE.COM` and `BLINK.COM`, that run on CP/M 2.2 and emit Z80 machine code directly. The native compiler has a budget of 26K, with a 28K limit (Chapter 2). That budget does not create a smaller Basie dialect or alter the meaning of a conforming program.

## 1.3 Authority

When repository materials disagree, apply this order:

1. This specification governs Basie 1.0 source syntax and semantics.
2. The implementation contracts named in Section 1.2 govern representation, generated code, the runtime and its services. They cannot change the meaning this specification requires; [services](../docs/services.md) is normative for the services as Chapter 16 says.
3. The implementation plan is non-normative. It records construction order, budgets, measurements, and implementation choices.
4. Architecture and design-rationale papers explain decisions but do not override either authority.
5. Conformance tests provide evidence that an implementation follows the specifications. A conflicting test is a test defect, not a language amendment. The examples Chapter 21 calls normative are normative as statements of this specification's rules, not as a separate authority.

An unwritten rule cannot be supplied by a lower-ranked document. Until this specification states the rule, the point remains unresolved for Basie 1.0 conformance.

## 1.4 Normative words

This specification uses four requirement words:

| Word         | Meaning                                                                                                          |
| ------------ | ---------------------------------------------------------------------------------------------------------------- |
| **must**     | The rule is required for conformance.                                                                            |
| **must not** | The described form or behaviour is prohibited.                                                                   |
| **may**      | The form or implementation choice is permitted but not required.                                                 |
| **should**   | The rule is recommended. A departure needs a documented reason and must not violate a `must` or `must not` rule. |

Declarative syntax and semantic rules are normative even when they contain none of these words. Notes, rationale, examples, and implementation sketches are non-normative unless they explicitly state a rule.

## 1.5 Conforming source programs

A conforming Basie 1.0 source program:

- uses only syntax and features admitted by this specification;
- satisfies the complete grammar and all applicable static-semantic rules;
- depends only on specified behaviour or on a choice that this specification explicitly marks as implementation-defined;
- does not depend on an extension or an unadmitted design candidate.

Exceeding one compiler's documented capacity does not affect a program's language conformance. The compiler may reject the program with a capacity diagnostic; that diagnostic reports an implementation limit rather than a source-language violation.

The complete accepted programs in Chapter 21 form the minimum conformance corpus. A conforming compiler and execution environment must compile and execute each program under its stated inputs without a capacity diagnostic, and without an `activation-capacity` trap except in a program whose stated purpose is to show one. An implementation may publish smaller limits than another implementation only above this floor. This requirement establishes a minimum useful implementation without creating a language profile or changing the conformance of larger source programs.

A program can use this complete working revision to establish conformance. Such a claim identifies the exact specification revision because the draft may still change before the 1.0 freeze.

## 1.6 Conforming compilers

A compiler claiming Basie 1.0 conformance must:

- compile every complete accepted program in Chapter 21 without a capacity diagnostic;
- accept and translate every conforming source program within its documented capacity limits;
- accept an in-capacity program presented through the multipart compilation stream in Section 4.3;
- preserve the specified observable results, side effects, and runtime traps of each accepted program;
- issue a diagnostic for compile-time invalid source rather than silently translating it with another meaning;
- issue a diagnostic when a documented capacity limit prevents translation;
- identify each source diagnostic by stable source-part identity and position within that part;
- identify and document every implementation-defined choice it makes;
- keep extensions separate from standard Basie mode.

A compiler must not report successful translation and then emit code with semantics that differ from this specification. Diagnostic wording and presentation are implementation-defined unless a later chapter requires a particular machine-readable result.

The native compiler passes an additional project acceptance gate only if it fits its budget (Chapter 2). A compiler may conform to the language and fail that size gate. Conversely, fitting the budget does not excuse a compiler that rejects an in-capacity conforming program, accepts invalid source without a diagnostic, or changes program meaning.

## 1.7 Extensions

An implementation may provide extensions only through an explicit selection, such as a distinct mode or option. Standard mode must diagnose source that requires an extension. An extension must not change the syntax, validity, or meaning of a conforming Basie 1.0 program.

Source that requires an extension is not a conforming Basie 1.0 program unless a later specification revision admits that feature into the language.

## 1.8 Implementation-defined choices

An implementation-defined choice is permitted only where this specification uses that term. The implementation must identify the choice, document the selected behaviour, and apply it consistently for the documented configuration.

Basie does not use undefined behaviour as an escape hatch for source-language errors. If this working draft omits a necessary rule, the omission is a specification gap; it does not permit arbitrary compiler or runtime behaviour.

## 1.9 Invalid source, capacity failures, and runtime traps

These cases are distinct:

| Case                                                                                   | Required treatment                                                                                                                       |
| -------------------------------------------------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------- |
| A grammar or static-semantic rule is violated.                                         | The source is invalid. The compiler must issue a compile-time diagnostic and must not present an executable as a successful translation. |
| A conforming program exceeds a documented compiler capacity.                           | The compiler may stop with a capacity diagnostic. The source does not become invalid.                                                    |
| A conforming program reaches a condition for which this specification requires a trap. | The generated program must perform the specified runtime trap unless a later chapter explicitly permits compile-time rejection.          |
| This draft has not yet specified the case.                                             | No conformance result can be inferred until the specification supplies the missing rule.                                                 |

A runtime trap is specified behaviour, not undefined behaviour and not evidence that the source was necessarily invalid.

**Diagnostic policy.** A compiler may stop at its first diagnostic, as `BASIE.COM` and the reference compiler do; another may continue to report further diagnostics. Neither may ever report a successful translation of invalid source. Later chapters define which failures are compile-time invalid, which are recoverable, and which trap at runtime.

## 1.10 Provisional features

Design candidates may be prototyped and measured while Basie 1.0 remains a working draft. Before 1.0 is frozen, the project either admits each candidate to the single normative language or omits it. Basie does not expose candidates as language levels or standard profiles.

A program that depends on an unadmitted candidate is not yet a conforming Basie 1.0 program. Prototype support for that candidate follows the extension rules in Section 1.7.

## 1.11 Direct Z80 implementation

`BASIE.COM` emits Z80 machine code directly and follows the [code generation contract](../docs/code-generation.md), the [CP/M target](../docs/cpm-target.md) and the [object format](../docs/object-format.md). It has no intermediate bytecode or transcript format.

Another compiler may use a different internal organization or target only when it preserves the same source semantics, diagnostics, and specified traps. An implementation choice does not create another Basie language profile.

## 1.12 Non-requirements

This working draft makes no claim that Basie 1.0 is frozen or implementation-validated. It does not require the first compiler to be written in Basie or compile its own source. It also does not require another conforming compiler to copy the first compiler's internal organization.
