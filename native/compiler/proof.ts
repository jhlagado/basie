/**
 * Run one of the native compiler's proof manifests (forked from Nucleus's
 * proofs/): build the image, run it on the Z80 from the manifest's entry until
 * it halts, and check the manifest's observations of memory.
 */
import { createZ80Runtime } from "@jhlagado/z80-runtime";
import { buildCompiler, type CompilerImage } from "./build.ts";

type Manifest = {
  name: string;
  execution: {
    entry: string;
    maxInstructions: number;
    maxCycles: number;
    halted: boolean;
  };
  observations: { at: string; width: "u8" | "u16"; equals: number }[];
};

export type ProofOutcome = {
  failures: string[];
  instructions: number;
  cycles: number;
  image: CompilerImage;
};

/** Load sparse Intel HEX into 64K of memory. */
function loadHex(hex: string): Uint8Array {
  const memory = new Uint8Array(0x10000);
  for (const line of hex.split(/\r?\n/)) {
    if (!line.startsWith(":")) continue;
    const bytes = line.slice(1).match(/../g)!.map((b) => parseInt(b, 16));
    const [count, hi, lo, type] = bytes;
    if (type !== 0) continue;
    memory.set(bytes.slice(4, 4 + count), (hi << 8) | lo);
  }
  return memory;
}

export async function runProof(manifestPath: string): Promise<ProofOutcome> {
  const manifest = JSON.parse(await Deno.readTextFile(manifestPath)) as Manifest;
  const image = await buildCompiler();
  const at = (name: string) => {
    const value = image.symbols[name];
    if (value === undefined) throw new Error(`no symbol ${name}`);
    return value;
  };
  const runtime = createZ80Runtime({
    memory: loadHex(image.hex),
    startAddress: at(manifest.execution.entry),
  });
  let instructions = 0;
  let cycles = 0;
  const { maxInstructions, maxCycles } = manifest.execution;
  while (
    instructions < maxInstructions && cycles <= maxCycles &&
    !runtime.isHalted()
  ) {
    cycles += runtime.step().cycles ?? 0;
    instructions += 1;
  }
  const failures: string[] = [];
  if (runtime.isHalted() !== manifest.execution.halted) {
    failures.push(`halted ${runtime.isHalted()}`);
  }
  const memory = runtime.hardware.memory;
  for (const o of manifest.observations) {
    const a = at(o.at);
    const value = o.width === "u8" ? memory[a] : memory[a] | (memory[a + 1] << 8);
    if (value !== o.equals) failures.push(`${o.at} = ${value}, expected ${o.equals}`);
  }
  return { failures, instructions, cycles, image };
}
