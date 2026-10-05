# 21. Conformance examples

## 21.1 The conformance suite

The normative conformance examples for Basiq 1.0 are the programs in [`tests/conformance`](../tests/conformance), organized by topic: `lexical`, `types`, `structure`, `scopes`, `declarations`, `expressions`, `statements`, `storage` and `basics`. Each program states in its leading comments the specification section it checks and what a conforming toolchain must do with it: produce given output and return code, trap with a given reason on a given line, or reject the program with a given diagnostic code at a given position ([format](../tests/conformance/README.md)). Diagnostic codes are listed in the [diagnostic register](../docs/diagnostics.md).

A conforming implementation compiles, links and runs every accepted program with the stated result, and rejects every rejected program with the stated diagnostic as its first. Implementation limits must be high enough for every program in the suite (Chapter 20, Section 20.2).

## 21.2 Coverage

Every chapter that defines source behaviour has programs in the suite: accepted programs for its main forms, rejected programs for the diagnostics it requires, and trapping programs for each run-time check it introduces. A change to the specification that changes observable behaviour changes or adds a program in the same revision.

## 21.3 The reference toolchain as oracle

The reference toolchain (Chapter 2, Section 2.5) runs the suite under a CP/M 2.2 harness, and under the Triptych CP/M 2.2 machine for programs that need a real BDOS. The native toolchain must produce the same results on every program, and the native linker byte-identical images.
