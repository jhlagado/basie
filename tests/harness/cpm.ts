/**
 * Minimal CP/M 2.2 environment on the portable Z80 runtime, for fast unit
 * tests. It provides page zero, the command tail and default FCB, and a BDOS
 * entry at $0005 that services the console and file functions Basiq's runtime
 * uses, over an in-memory disk. A jump to $0000 (warm boot) or a return to the
 * CCP's address ends the program.
 *
 * Full-fidelity proofs boot real CP/M 2.2 on the Triptych machine instead, as
 * Skate's proofs do; this harness is for quick checks of generated code.
 */
import { assembleAtomProject, materializeAtomGeneration } from "atom-z80";
import { createZ80Runtime } from "@jhlagado/z80-runtime";
import { dirname, fromFileUrl, relative } from "@std/path";

/** Address the harness treats as the CCP: a RET from the program lands here. */
const CCP_RETURN = 0xff00;
/** The BDOS entry the harness reports at $0006: the top of usable memory. */
const BDOS_ENTRY = 0xe406;
/** Bytes per CP/M record. */
const RECORD = 128;

export type CpmRun = {
  output: string;
  exit: "warm-boot" | "return";
  steps: number;
  cycles: number;
  /** The CP/M 3 program return code, if the program set one (BDOS 108). */
  returnCode: number | undefined;
  /** The disk after the run: file name to contents. */
  disk: Map<string, Uint8Array>;
};

export type CpmOptions = {
  /** Console input, consumed by BDOS 1, 6 and 10. */
  input?: string;
  /** The command tail, as typed after the program name. */
  tail?: string;
  /** Files present before the run, keyed by 8.3 name such as "DATA.TXT". */
  files?: Record<string, Uint8Array | string>;
  maxSteps?: number;
};

/** Assemble an ATOM source file and return its image. */
export async function assembleFile(path: string) {
  const root = dirname(path);
  const result = await assembleAtomProject({
    root,
    entry: relative(root, path),
    assembler: undefined,
    target: undefined,
    maxInstructions: 10_000_000,
    maxCycles: 100_000_000,
    sink: undefined,
  });
  const image = materializeAtomGeneration(result.generation);
  if (!image) throw new Error(`ATOM produced no image for ${path}`);
  const symbols = result.generation.symbols.map(
    (s: { name: string; value: number }) =>
      [s.name.toLowerCase(), s.value] as const,
  );
  return { ...image, symbols };
}

/** The bytes of an assembled image from $0100 on, as a .COM file holds them. */
export function comBytes(image: { base: number; bytes: ArrayLike<number> }) {
  const from = 0x0100 - image.base;
  if (from < 0) throw new Error("Image starts above $0100");
  return Uint8Array.from(image.bytes).slice(from);
}

/** Path of a file beside the calling module. */
export function here(url: string, name: string) {
  return fromFileUrl(new URL(name, url));
}

/** Run a .COM image (bytes loaded at $0100) under the minimal CP/M. */
export function runCom(bytes: Uint8Array, options: CpmOptions = {}): CpmRun {
  const input = options.input ?? "";
  const maxSteps = options.maxSteps ?? 10_000_000;
  const disk = new Map<string, Uint8Array>();
  for (const [name, data] of Object.entries(options.files ?? {})) {
    disk.set(
      name.toUpperCase(),
      typeof data === "string" ? new TextEncoder().encode(data) : data,
    );
  }

  const memory = new Uint8Array(65536);
  memory.set(bytes, 0x0100);
  // Page zero: warm-boot jump and the BDOS jump.
  memory.set([0xc3, 0x03, 0xff], 0x0000);
  memory.set([0xc3, BDOS_ENTRY & 0xff, BDOS_ENTRY >> 8], 0x0005);
  setCommandTail(memory, options.tail ?? "");

  const runtime = createZ80Runtime({ memory, startAddress: 0x0100 });
  const cpu = runtime.cpu;
  const mem = runtime.hardware.memory;
  // The CCP's return address on the program's entry stack.
  cpu.sp = 0xfefe;
  mem[0xfefe] = CCP_RETURN & 0xff;
  mem[0xfeff] = CCP_RETURN >> 8;

  let output = "";
  let inputAt = 0;
  let dma = 0x0080;
  let cycles = 0;
  let returnCode: number | undefined;
  let search: string[] = [];

  for (let steps = 0; steps < maxSteps; steps += 1) {
    if (cpu.pc === 0x0000 || cpu.pc === 0xff03) {
      return finish("warm-boot", steps);
    }
    if (cpu.pc === CCP_RETURN) return finish("return", steps);
    if (cpu.pc === BDOS_ENTRY) {
      bdos();
      const lo = mem[cpu.sp], hi = mem[(cpu.sp + 1) & 0xffff];
      cpu.sp = (cpu.sp + 2) & 0xffff;
      cpu.pc = lo | (hi << 8);
      continue;
    }
    cycles += runtime.step().cycles ?? 0;
  }
  throw new Error(`Program did not finish in ${maxSteps} steps`);

  function finish(exit: CpmRun["exit"], steps: number): CpmRun {
    return { output, exit, steps, cycles, returnCode, disk };
  }

  function result(value: number) {
    cpu.a = value & 0xff;
    cpu.l = value & 0xff;
    cpu.h = 0;
    cpu.b = 0;
  }

  function nextInput(): number {
    return inputAt < input.length ? input.charCodeAt(inputAt++) : 0x1a;
  }

  function bdos() {
    const fn = cpu.c;
    const de = (cpu.d << 8) | cpu.e;
    switch (fn) {
      case 1: { // console input with echo
        const ch = nextInput();
        output += String.fromCharCode(ch);
        return result(ch);
      }
      case 2: // console output
        output += String.fromCharCode(cpu.e);
        return;
      case 5: // list output: recorded with the console, marked
        output += `\u0000L${String.fromCharCode(cpu.e)}`;
        return;
      case 6: // direct console I/O
        if (cpu.e === 0xff) {
          return result(inputAt < input.length ? nextInput() : 0);
        }
        output += String.fromCharCode(cpu.e);
        return;
      case 9: { // print string to "$"
        for (let a = de; mem[a] !== 0x24; a = (a + 1) & 0xffff) {
          output += String.fromCharCode(mem[a]);
        }
        return;
      }
      case 10: { // read console buffer: DE -> max, count, text
        const max = mem[de];
        let count = 0;
        while (count < max && inputAt < input.length) {
          const ch = input.charCodeAt(inputAt++);
          if (ch === 13 || ch === 10) break;
          mem[de + 2 + count] = ch;
          count += 1;
        }
        mem[de + 1] = count;
        return;
      }
      case 11: // console status
        return result(inputAt < input.length ? 0xff : 0);
      case 12: // version: 2.2
        cpu.h = 0;
        cpu.l = 0x22;
        cpu.a = 0x22;
        cpu.b = 0;
        return;
      case 15: // open file
        return result(disk.has(fcbName(de)) ? (resetFcb(de), 0) : 0xff);
      case 16: // close file
        return result(disk.has(fcbName(de)) ? 0 : 0xff);
      case 17: // search first
        search = [...disk.keys()].filter((n) => matches(fcbPattern(de), n))
          .sort();
        return searchNext();
      case 18: // search next
        return searchNext();
      case 19: { // delete file
        const pattern = fcbPattern(de);
        const names = [...disk.keys()].filter((n) => matches(pattern, n));
        names.forEach((n) => disk.delete(n));
        return result(names.length > 0 ? 0 : 0xff);
      }
      case 20: // read sequential
        return result(transfer(de, sequentialRecord(de), "read", true));
      case 21: // write sequential
        return result(transfer(de, sequentialRecord(de), "write", true));
      case 22: { // make file
        const name = fcbName(de);
        if (disk.has(name)) throw new Error(`Make of existing file ${name}`);
        disk.set(name, new Uint8Array(0));
        resetFcb(de);
        return result(0);
      }
      case 23: { // rename: new name in the second half of the FCB
        const from = fcbName(de), to = fcbName(de + 16);
        if (!disk.has(from)) return result(0xff);
        if (disk.has(to)) throw new Error(`Rename onto existing file ${to}`);
        disk.set(to, disk.get(from)!);
        disk.delete(from);
        return result(0);
      }
      case 25: // current disk: A
        return result(0);
      case 26: // set DMA address
        dma = de;
        return;
      case 33: // read random
        return result(transfer(de, randomRecord(de), "read", false));
      case 34: // write random
        return result(transfer(de, randomRecord(de), "write", false));
      case 35: { // compute file size into the random record field
        const data = disk.get(fcbName(de));
        if (!data) return result(0xff);
        setRandomRecord(de, Math.ceil(data.length / RECORD));
        return result(0);
      }
      case 108: // CP/M 3: set program return code
        returnCode = de;
        return;
      default:
        throw new Error(`BDOS function ${fn} is not provided by the harness`);
    }
  }

  function searchNext() {
    const name = search.shift();
    if (name === undefined) return result(0xff);
    // Directory entry 0 of the DMA buffer: user 0, name, extent 0.
    mem.fill(0, dma, dma + 32);
    const [base, ext = ""] = name.split(".");
    const field = base.padEnd(8) + ext.padEnd(3);
    for (let i = 0; i < 11; i += 1) mem[dma + 1 + i] = field.charCodeAt(i);
    return result(0);
  }

  function transfer(
    fcb: number,
    record: number,
    direction: "read" | "write",
    advance: boolean,
  ): number {
    const name = fcbName(fcb);
    const data = disk.get(name);
    if (!data) return 0xff;
    const offset = record * RECORD;
    if (direction === "read") {
      if (offset >= data.length) return 1; // end of file
      const chunk = new Uint8Array(RECORD).fill(0x1a);
      chunk.set(data.subarray(offset, offset + RECORD));
      mem.set(chunk, dma);
    } else {
      const grown = new Uint8Array(Math.max(data.length, offset + RECORD));
      grown.set(data);
      grown.set(mem.subarray(dma, dma + RECORD), offset);
      disk.set(name, grown);
    }
    if (advance) setSequentialRecord(fcb, record + 1);
    return 0;
  }

  function sequentialRecord(fcb: number) {
    return mem[fcb + 12] * 128 + mem[fcb + 32];
  }

  function setSequentialRecord(fcb: number, record: number) {
    mem[fcb + 12] = Math.floor(record / 128);
    mem[fcb + 32] = record % 128;
  }

  function randomRecord(fcb: number) {
    return mem[fcb + 33] | (mem[fcb + 34] << 8) | (mem[fcb + 35] << 16);
  }

  function setRandomRecord(fcb: number, record: number) {
    mem[fcb + 33] = record & 0xff;
    mem[fcb + 34] = (record >> 8) & 0xff;
    mem[fcb + 35] = (record >> 16) & 0xff;
  }

  function resetFcb(fcb: number) {
    mem[fcb + 12] = 0;
    mem[fcb + 32] = 0;
  }

  function fcbPattern(fcb: number) {
    let text = "";
    for (let i = 1; i <= 11; i += 1) text += String.fromCharCode(mem[fcb + i]);
    return text;
  }

  function fcbName(fcb: number) {
    const raw = fcbPattern(fcb);
    const base = raw.slice(0, 8).trimEnd();
    const ext = raw.slice(8).trimEnd();
    return ext ? `${base}.${ext}` : base;
  }
}

/** Whether an 11-character FCB pattern, with `?` wildcards, matches a name. */
function matches(pattern: string, name: string) {
  const [base, ext = ""] = name.split(".");
  const field = base.padEnd(8) + ext.padEnd(3);
  for (let i = 0; i < 11; i += 1) {
    if (pattern[i] !== "?" && pattern[i] !== field[i]) return false;
  }
  return true;
}

/** Place the command tail at $0080 and parse the first name into $005C. */
function setCommandTail(memory: Uint8Array, tail: string) {
  const text = tail.toUpperCase().slice(0, 127);
  const spaced = text ? ` ${text}` : "";
  memory[0x0080] = spaced.length;
  for (let i = 0; i < spaced.length; i += 1) {
    memory[0x0081 + i] = spaced.charCodeAt(i);
  }
  memory.fill(0x20, 0x005d, 0x0068);
  memory.fill(0x20, 0x006d, 0x0078);
  const first = text.split(/\s+/)[0] ?? "";
  const [base, ext = ""] = first.split(".");
  for (let i = 0; i < Math.min(base.length, 8); i += 1) {
    memory[0x005d + i] = base.charCodeAt(i);
  }
  for (let i = 0; i < Math.min(ext.length, 3); i += 1) {
    memory[0x0065 + i] = ext.charCodeAt(i);
  }
}
