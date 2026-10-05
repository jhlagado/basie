# 16. System boundary


## 16.1 Boundary model

A Basie program reaches the console, files, the command line and the machine only through **services**: predeclared routines supplied by the runtime library of the target profile. The source language exposes no BDOS or BIOS calls, ports, addresses, device registers or memory map ([I/O and effects](../docs/io-and-effects.md)).

The services, their signatures, behaviour and failure codes are defined normatively by **Basie Services, revision 2** ([services](../docs/services.md)), which is part of this specification. This chapter states the rules that bind them to the language.

## 16.2 Predeclared names

Before the first source token, the compiler establishes in the program scope:

- the **service routines** of the profile's helper table, with their signatures ([services](../docs/services.md), Sections 3 to 6);
- the type **`File`**, and the values **`console`** and **`printer`** of that type (Section 16.3);
- the **failure-code constants** of [services](../docs/services.md), Section 9, as untyped integer constants: `endOfInput` (1), `inputFailure` (2), `outputFailure` (3), `storageFailure` (4), `fileNotFound` (5), `fileExists` (6), `badName` (7), `tooManyFiles` (8), `fileClosed` (9), `diskFull` (10), `directoryFull` (11), `readOnly` (12), `seekFailure` (13), `lineTooLong` (14), `notAvailable` (15), `fileBusy` (16), `noSearch` (17), `badMode` (18) and `invalid` (254), with `endOfFile` another name for 1; and
- the mode constants **`textMode`** (0) and **`binaryMode`** (1) ([services](../docs/services.md), Section 4.2).

Revision 2 of the services uses no other predeclared type.

Predeclared names cannot be redeclared or shadowed (Chapter 5, Section 5.10). Service routines are called exactly like source routines; a service that can fail is declared `fails` and follows Chapter 14. A call to a service that the selected profile does not provide is a compile-time error. A program carries only the services it calls.

Nucleus's `readInputByte()` and `writeOutputByte(b)` remain as shorthands for `readByte(console)` and `writeByte(console, b)`. Nucleus's storage-stream routines are not provided.

## 16.3 `File`

`File` is a predeclared opaque type that identifies an open file, the console or the printer ([services](../docs/services.md), Section 2):

- A `File` value can be stored in variables, fields, array elements and parameters, copied, and compared with `=` and `<>`. It has no other operations, and no conversion to or from any other type.
- Its zero value refers to no file; a service given it fails with `fileClosed`. A `File` whose file has been closed also fails with `fileClosed`, never reaching another file.
- `File` values arise only from the opening services and from `console` and `printer`.
- `File` is not a handle and is not owned: closing a file is an explicit service call, and files still open when the program ends are closed by the runtime ([services](../docs/services.md), Section 7).

## 16.4 The standard library

Formatting and parsing numbers, building and comparing strings, splitting the command line into words and similar routines form a **standard library written in Basie** (design decision D36), supplied as source parts such as `STRINGS.BSI` and `FORMAT.BSI` and brought in with `include` (Chapter 4). They are ordinary Basie routines with no special status; their internal routines are `private`. They use failure codes 32 to 47. The [standard library](../docs/standard-library.md) document lists every routine and its contract.

## 16.5 Program startup and termination

The runtime's startup establishes every program variable's initial value and every pool's free state, then calls `main` ([CP/M target](../docs/cpm-target.md), Section 4). Before calling `main` it checks that the memory available covers the program's stack reserve, and otherwise reports that there is not enough memory and returns to the operating system without running the program.

A normal return from `main` ends the program successfully. There is no statement to end the program early: a program ends by returning from `main` or failing out of it. A failure returned from `main` performs the `unhandled-error` trap (Chapter 15). On CP/M 3 the program's return code distinguishes success, an unhandled failure, a trap and insufficient memory.

## 16.6 Safety of services

Services belong to the trusted base outside the safety property of Chapter 7, Section 7.2. A service given an alias respects its extent and mode, keeps no address after returning, and restores any state the language relies on. Services follow the trap reporter contract, so a trap in a service reports the program's call to it.

## 16.7 Excluded mechanisms

Arbitrary BDOS and BIOS calls, inline machine code, machine-code-call declarations, memory peeks and pokes, port access and callbacks are excluded. A new service needs a typed, target-independent contract, an entry in the helper table, and a revision of the service set.
