/**
 * Minimal CP/M 2.2 environment on the portable Z80 runtime, for fast unit
 * tests. It provides page zero, a BDOS entry at $0005 that services the console
 * functions a test needs, and treats a jump to $0000 (warm boot) or a return
 * to the CCP's address as the end of the program.
 *
 * Full-fidelity proofs boot real CP/M 2.2 on the Triptych machine instead, as
 * Skate's proofs do; this harness is for quick checks of generated code.
 */
import { assembleAtomProject, materializeAtomGeneration } from "atom-z80";
import { createZ80Runtime } from "@jhlagado/z80-runtime";
import { dirname, fromFileUrl, relative } from "@std/path";

/** Address the harness treats as the CCP: a RET from the program lands here. */
const CCP_RETURN = 0xff00;
/** Top of the transient program area the harness reports at $0006. */
const BDOS_ENTRY = 0xe406;

export type CpmRun = {
  output: string;
  exit: "warm-boot" | "return";
  steps: number;
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
  return image;
}

/** The bytes of an assembled image from $0100 on, as a .COM file holds them. */
export function comBytes(image: { base: number; bytes: ArrayLike<number> }) {
  const from = 0x0100 - image.base;
  if (from < 0) throw new Error("Image starts above $0100");
  return Uint8Array.from(image.bytes).slice(from);
}

/** Run a .COM image (bytes loaded at $0100) under the minimal CP/M. */
export function runCom(
  bytes: Uint8Array,
  { input = "", maxSteps = 10_000_000 } = {},
): CpmRun {
  const memory = new Uint8Array(65536);
  memory.set(bytes, 0x0100);
  // Page zero: warm-boot jump and the BDOS jump.
  memory[0x0000] = 0xc3;
  memory[0x0001] = 0x03;
  memory[0x0002] = 0xff;
  memory[0x0005] = 0xc3;
  memory[0x0006] = BDOS_ENTRY & 0xff;
  memory[0x0007] = BDOS_ENTRY >> 8;
  const runtime = createZ80Runtime({ memory, startAddress: 0x0100 });
  const cpu = runtime.cpu;
  const mem = runtime.hardware.memory;
  // The CCP's return address on the program's entry stack.
  cpu.sp = 0xfefe;
  mem[0xfefe] = CCP_RETURN & 0xff;
  mem[0xfeff] = CCP_RETURN >> 8;

  let output = "";
  let inputAt = 0;
  for (let steps = 0; steps < maxSteps; steps += 1) {
    if (cpu.pc === 0x0000 || cpu.pc === 0xff03) {
      return { output, exit: "warm-boot", steps };
    }
    if (cpu.pc === CCP_RETURN) return { output, exit: "return", steps };
    if (cpu.pc === BDOS_ENTRY) {
      bdos();
      // Return from the BDOS call.
      const lo = mem[cpu.sp], hi = mem[(cpu.sp + 1) & 0xffff];
      cpu.sp = (cpu.sp + 2) & 0xffff;
      cpu.pc = lo | (hi << 8);
      continue;
    }
    runtime.step();
  }
  throw new Error(`Program did not finish in ${maxSteps} steps`);

  function bdos() {
    const fn = cpu.c;
    const de = (cpu.d << 8) | cpu.e;
    switch (fn) {
      case 1: { // console input with echo
        const ch = inputAt < input.length ? input.charCodeAt(inputAt++) : 0x1a;
        output += String.fromCharCode(ch);
        cpu.a = ch;
        cpu.l = ch;
        return;
      }
      case 2: // console output
        output += String.fromCharCode(cpu.e);
        return;
      case 6: // direct console I/O
        if (cpu.e === 0xff) {
          cpu.a = inputAt < input.length ? input.charCodeAt(inputAt++) : 0;
        } else {
          output += String.fromCharCode(cpu.e);
        }
        return;
      case 9: { // print string to "$"
        for (let a = de; mem[a] !== 0x24; a = (a + 1) & 0xffff) {
          output += String.fromCharCode(mem[a]);
        }
        return;
      }
      case 11: // console status
        cpu.a = inputAt < input.length ? 0xff : 0;
        return;
      case 26: // set DMA address: accepted, unused here
        return;
      default:
        throw new Error(`BDOS function ${fn} is not provided by the harness`);
    }
  }
}

/** Path of a file beside the calling module. */
export function here(url: string, name: string) {
  return fromFileUrl(new URL(name, url));
}
