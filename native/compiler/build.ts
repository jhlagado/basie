/**
 * Build the native compiler from its AZM sources with ATOM, through the
 * source translation forked from Nucleus (tools/atom-source.mjs). Returns
 * the image as sparse Intel HEX, its symbols and its extents.
 *
 *   deno task build:compiler
 */
// @ts-types="./tools/atom-source.d.ts"
import { assembleAtomSource } from "./tools/atom-source.mjs";

/** The shipping composition: the compiler and its proof runtime. */
export const ENTRY = "vertical-slice/flat-target-z80-slice-proof.asm";

export type CompilerImage = {
  hex: string;
  symbols: Record<string, number>;
  /** Bytes of compiler code, of immutable data, and the two together. */
  code: number;
  immutable: number;
  core: number;
};

/** BASIE.COM: the compiler in its CP/M shell (native compiler plan 65.2). */
export const BASIE_ENTRY = "basie/basie.asm";

export type BasieImage = CompilerImage & {
  /** The .COM file's bytes, from $0100 to the end of the image. */
  com: Uint8Array;
};

const cached = new Map<string, Promise<CompilerImage>>();

/** The image, built once per process: ATOM takes most of a minute. */
export function buildCompiler(entry = ENTRY): Promise<CompilerImage> {
  let image = cached.get(entry);
  if (!image) cached.set(entry, image = build(entry));
  return image;
}

/** BASIE.COM, checked to end below its workspace. */
export async function buildBasie(): Promise<BasieImage> {
  const image = await buildCompiler(BASIE_ENTRY);
  const start = image.symbols["BasieImageStart"];
  const end = image.symbols["BasieImageEnd"];
  const at = (name: string) => image.symbols[name];
  if (end > at("CompilerWorkBase")) {
    throw new Error(`BASIE.COM ends at ${end}, over its workspace`);
  }
  if (at("HybridLL1WorkspaceEnd") > at("BasieWorkBase")) {
    throw new Error("the compiler's workspace runs into the shell's");
  }
  if (at("BasieWorkEnd") > at("SourceBase")) {
    throw new Error("the shell's workspace runs into the source");
  }
  const memory = new Uint8Array(0x10000);
  for (const line of image.hex.split(/\r?\n/)) {
    if (!line.startsWith(":")) continue;
    const bytes = line.slice(1).match(/../g)!.map((b) => parseInt(b, 16));
    if (bytes[3] === 0) {
      memory.set(bytes.slice(4, 4 + bytes[0]), (bytes[1] << 8) | bytes[2]);
    }
  }
  return { ...image, com: memory.slice(start, end) };
}

async function build(entry: string): Promise<CompilerImage> {
  const result = await assembleAtomSource(entry);
  const symbols = { ...result.symbols, ...result.addresses };
  const at = (name: string) => {
    const value = symbols[name];
    if (value === undefined) throw new Error(`no symbol ${name}`);
    return value;
  };
  return {
    hex: result.hex,
    symbols,
    code: at("CompilerCodeEnd") - at("CompilerCodeStart"),
    immutable: at("CompilerImmutableEnd") - at("CompilerImmutableStart"),
    core: at("CompilerCoreEnd") - at("CompilerCodeStart"),
  };
}

if (import.meta.main) {
  const image = await buildCompiler();
  console.log(
    `compiler core ${image.core} bytes: code ${image.code}, immutable ${image.immutable}`,
  );
  const basie = await buildBasie();
  console.log(`BASIE.COM ${basie.com.length} bytes`);
}
