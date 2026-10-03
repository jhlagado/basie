# Input, output and external effects

- Status: proposal, not yet reviewed
- Date: 2026-10-04
- Related: Nucleus runtime contract, Section 8 (`../../nucleus/docs/z80-runtime-contract.md`);
  Skate's [external effects](../../skate/docs/public/external-effects.md) and
  [ports](../../skate/docs/ports.md); [memory safety](memory-safety.md);
  [CP/M target](cpm-target.md)

## 1. The question

How does a Baton program talk to the world: the console, files, the command
line, the screen and sound? There are two broad approaches:

1. **Direct:** the language can call the operating system (BDOS functions) or
   touch hardware (`IN` and `OUT` on Z80 ports) itself.
2. **Indirect:** the language knows nothing about operating systems or ports.
   Programs use a small set of **services** provided by the runtime library for
   each target, and talk to devices by sending commands over byte streams, which
   a **provider** interprets.

Nucleus and Skate both took the indirect approach. This document proposes that
Baton does too, and says exactly where the boundary lies.

## 2. What Nucleus and Skate do

**Nucleus** has six stable services, called like ordinary failable routines:
`readInputByte`, `writeOutputByte`, and four bulk-storage operations. Each target
adapter implements them; generated code never calls the BDOS or a port
directly.

**Skate** uses ordinary bytes for standard input and output. Devices are reached
through an optional **command channel**: framed messages on the same byte stream
(`ESC ~`, a version, kind, opcode, correlation number, length, payload and CRC),
which a provider such as a Triptych terminal interprets. A provider owns the
meaning of each capability and reports unsupported operations as errors. The
CP/M bridge carries plain console bytes; full framing needs a channel that can
carry every byte. Skate exposes no port addresses or hardware primitives in the
language.

## 3. Proposal

### 3.1 No operating-system or port primitives in the language

Baton source has no way to call a BDOS function, execute `IN` or `OUT`, or name
a memory address. This withdraws the port built-ins listed in an earlier draft of the
[feature inventory](feature-inventory.md).

### 3.2 Services

The runtime library for each profile provides **services**: predeclared routines
with Baton signatures, failable where the operation can fail, as in Nucleus.

| Group | Examples | Profiles |
| --- | --- | --- |
| Console | `readInputByte`, `writeOutputByte`, `readLine`, `writeText` | all |
| Files | open, read, write, close, delete, rename, with handles and bounded names | CP/M, and hosts with a file provider |
| Command line | the command tail and default file names | CP/M |
| Time | ticks or a clock, where the machine has one | where available |
| Devices | `sendCommand`, `receiveEvent` over the command channel | profiles with a provider |

Services are runtime blobs in the blob library, so a program carries only the
services it calls (tree shaking), and on CP/M a call to a service is an
ordinary `CALL`, with no indirection.

The compiler learns each service's signature from the helper table compiled into
it, the same table that numbers runtime helpers (object format, Section 10). A
program that calls a service its profile doesn't provide gets a compile-time
error.

### 3.3 Devices through the command channel

Video, sound and rich terminal control are reached as in Skate: a Baton library
encodes commands into the external-effects frame format and sends them through a
service; the provider on the other end interprets them. The language knows only
bytes. This lets the same Baton program drive a Triptych terminal, a host
emulator or a test harness without change.

## 4. Why indirect

- **Memory safety.** A direct `OUT` or BDOS call can do anything: a BDOS read
  writes 128 bytes wherever the DMA address points. Keeping every such operation
  inside the trusted runtime, which checks extents and modes (memory safety,
  Section 2.1), is what lets the safety claim hold for all source code.
- **Portability.** The same program runs on CP/M 2.2, CP/M 3, Triptych or a host
  emulator, with the target chosen at link time by the blob library.
- **Testing.** The proof harness can substitute providers and record exactly
  what a program asked for, as Nucleus and Skate already do.
- **Cost.** With services as runtime blobs, there is no vector table and no
  indirection on CP/M, and tree shaking removes unused ones. The command channel
  costs framing bytes only for programs that use devices.

## 5. What it costs

- **No ad hoc hardware access.** A program that needs a device its profile
  doesn't expose can't reach it from source. The remedy is a profile variant
  with a new service, written in the runtime library, which is trusted code and
  takes more effort than a line of source.
- **The service set must be designed** and versioned, as the helper table
  already is.

## 6. Open questions

1. **The standard service set** for 1.0: which console, file, command-line and
   time services, with which signatures and error codes.
2. **File services:** Skate's staged open/write/commit model with bounded
   handles, or plain CP/M sequential files?
3. **Typed service results:** with variants available, should services report
   errors as richer values than the `u8` codes Nucleus uses?
4. **A raw escape hatch for experts,** such as unchecked BDOS access. If
   adopted, programs using it fall outside the memory-safety claim, and the
   compiler would say so. With CP/M 2.2 as the only target, the standard
   services may make it unnecessary.
