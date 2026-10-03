# 16. System boundary


## 16.1 Boundary model

Baton 1.0 defines a small portable service boundary for byte-stream input and output, slow bulk storage, successful termination, and trap reporting. Programs invoke typed predefined routines and use predefined constants. The source language exposes no service numbers, ports, firmware entry points, raw addresses, file descriptors, device registers, or machine-specific memory map.

Baton source contains no physical placement, and a target description contains no source-symbol reference. The source manifest selects and orders declarations; the target description supplies bounded execution regions. Neither input can name or rewrite entities owned by the other.

The **Baton System Services 0.1** set is versioned with this language revision. A conforming execution environment supplies every service in Section 16.3 with the stated source contract and the initial stream states stated there. Later additions require a language revision or an explicit extension under Section 1.7 and measured admission under Chapter 2.

## 16.2 Predefined error codes

The compiler establishes these `u8` constants before the first source token:

| Name             | Value | Meaning                                                                      |
| ---------------- | ----: | ---------------------------------------------------------------------------- |
| `endOfInput`     |     1 | The selected input stream has no further byte.                               |
| `inputFailure`   |     2 | Standard input could not supply a byte for a reason other than end of input. |
| `outputFailure`  |     3 | Standard output could not accept a byte.                                     |
| `storageFailure` |     4 | A bulk-storage read, write, rewind, or seek failed.                          |

The names occupy the ordinary program namespace and cannot be redeclared or shadowed. They are named recoverable-error codes, not enumeration members or a distinct error type.

## 16.3 Predefined routines

The compiler establishes these routine signatures before the first source token:

```nucleus
sub readInputByte() as u8 fails
sub writeOutputByte(value as u8) fails
sub readStorageByte() as u8 fails
sub rewindStorageInput() fails
sub writeStorageByte(value as u8) fails
sub seekStorageOutput(offset as u16) fails
```

The declarations above state interfaces; they are not source definitions and do not require completing bodies in the compilation unit.

Standard input starts with its cursor before the first supplied byte. `readInputByte` obtains the next byte from standard input. It may block until a byte, end-of-input condition, or input failure is available. It succeeds with the byte and advances the cursor, fails with `endOfInput` at the end, else fails with `inputFailure` for another input error. Failure leaves the cursor unchanged.

Standard output starts empty and is append-only. `writeOutputByte` appends one byte to standard output. It succeeds after the byte has been accepted else fails with `outputFailure`. Successful writes occur in call order; failure leaves the output unchanged.

The bulk-storage routines operate on one logical input stream and one logical output stream selected by the execution environment. Both cursors start at offset zero. The output supplied to a Chapter 21 conformance run starts empty. `readStorageByte` advances the input cursor after a successful byte and reports `endOfInput` or `storageFailure` otherwise. `rewindStorageInput` moves the input cursor to offset zero or reports `storageFailure`.

`writeStorageByte` overwrites the existing byte when the output cursor is below the current end, appends when the cursor is exactly at the end, and advances the cursor by one on success. It never inserts a byte or truncates later bytes. `seekStorageOutput` moves that cursor to an existing offset or exactly to the current end; seeking past the end fails with `storageFailure`. Every failed bulk-storage operation is atomic: it leaves its affected cursor and all output contents unchanged.

These contracts support streaming programs without exposing a filesystem. Baton 1.0 source cannot open, close, name, enumerate, create, or delete files. A launcher or build tool selects the streams outside the source language.

## 16.4 Program startup and termination

The implementation enters its implicit startup path before `main`. Startup establishes explicit program-variable initializers, establishes zero values for the remaining program variables, and then transfers to `main`. These operations are complete before source execution begins and are not source-callable. The environment supplies no command-line arguments or implicit source values. Source code obtains input only through the predefined services.

Normal return from `main` terminates successfully. Baton 1.0 has no source statement for process exit status or immediate successful termination. Failure returned from `main` and every safety trap terminate unsuccessfully under Chapter 15.

The external representation of success, recoverable-error codes, and trap reasons is implementation-defined only where the Z80 runtime and backend contract explicitly says so. That representation must preserve the source-level distinction among normal termination, unhandled recoverable error, and each required trap reason.

## 16.5 Portability and implementation

An environment may implement services with CP/M calls, a monitor, port I/O, host callbacks, or another mechanism. It may buffer transfers if buffering preserves call order, failure points, and visible bytes. Those choices do not add source names or expose their addresses.

Arbitrary BIOS calls, machine-code-call declarations, inline assembly, memory peeks and pokes, port access, and callbacks are excluded from the safe source boundary. A later service must have a typed target-independent contract and pass the measured admission rule before it enters the standard set.

The target adapter may place the program in ROM, loaded RAM, or bank-switched ROM while preserving the same startup and source semantics. The target-system specification and Z80 runtime contract govern bank assignment and calls. Source code supplies neither a bank number nor a target address, and a target restriction on cross-bank references does not alter source validity.
