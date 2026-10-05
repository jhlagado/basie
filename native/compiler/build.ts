/**
 * Build BASIE.COM from its ATOM sources (design decision D44) and report its
 * extents.
 *
 *   deno task build:compiler
 */
import { assembleFile, comBytes } from "../../tests/harness/cpm.ts";

export const ENTRY = "native/compiler/BASIE.ASM";

export type BasieImage = {
  /** The .COM file's bytes, from $0100 to the end of the image. */
  com: Uint8Array;
  /** Symbol values by upper-case name. */
  symbols: Record<string, number>;
  /** Bytes of compiler code, of immutable data, and the two together. */
  code: number;
  immutable: number;
  core: number;
  /** Bytes of the CP/M shell. */
  shell: number;
};

let cached: Promise<BasieImage> | undefined;

/** The image, built once per process: ATOM takes most of a minute. */
export function buildBasie(): Promise<BasieImage> {
  return cached ??= build();
}

async function build(): Promise<BasieImage> {
  const image = await assembleFile(ENTRY);
  const symbols: Record<string, number> = {};
  for (const [name, value] of image.symbols) symbols[name.toUpperCase()] = value;
  const at = (name: string) => {
    const value = symbols[name];
    if (value === undefined) throw new Error(`no symbol ${name}`);
    return value;
  };
  if (at("MM_END") > at("MM_WBASE")) {
    throw new Error(`BASIE.COM ends at ${at("MM_END")}, over its workspace`);
  }
  if (at("LL_WEND") > at("SH_WBEG")) {
    throw new Error("the compiler's workspace runs into the shell's");
  }
  if (at("SH_WEND") > at("MM_SRC")) {
    throw new Error("the shell's workspace runs into the source");
  }
  const com = comBytes(image).slice(0, at("MM_END") - at("MM_BEG"));
  return {
    com,
    symbols,
    code: at("MM_CEND") - at("MM_CBEG"),
    immutable: at("MM_IEND") - at("MM_IBEG"),
    core: at("MM_REND") - at("MM_CBEG"),
    shell: at("SH_CEND") - at("SH_CBEG"),
  };
}

if (import.meta.main) {
  const image = await buildBasie();
  console.log(
    `BASIE.COM ${image.com.length} bytes: compiler core ${image.core} (code ${image.code}, immutable ${image.immutable}), shell ${image.shell}`,
  );
}
