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

let cached: Promise<CompilerImage> | undefined;

/** The image, built once per process: ATOM takes most of a minute. */
export function buildCompiler(): Promise<CompilerImage> {
  return cached ??= build();
}

async function build(): Promise<CompilerImage> {
  const result = await assembleAtomSource(ENTRY);
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
}
