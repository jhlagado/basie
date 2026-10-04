/**
 * The reference compiler's entry point: source parts in, a linked .COM
 * image out (build pipeline §4).
 */
import { link, LinkError } from "../link/link.ts";
import { type Library, readLibrary } from "../object/library.ts";
import { defaultHeader } from "../object/program.ts";
import { buildLibrary } from "../../tools/brl.ts";
import { Compiler, NotImplemented } from "./compiler.ts";
import { CompileError } from "./diagnostics.ts";
import { HELPER_VERSION } from "./helpers.ts";
import { loadSource, type SourceOptions } from "./source.ts";

export { NotImplemented };

export type Diagnostic = {
  code: string;
  line: number;
  column: number;
  /** The part's name, as the line table records it. */
  part: string;
  message: string;
};

export type CompileResult =
  | {
    ok: true;
    com: Uint8Array;
    lineTable?: Uint8Array;
    addresses: Map<number, number>;
  }
  | { ok: false; diagnostics: Diagnostic[] }
  | { ok: false; linkError: string };

export type CompileOptions = SourceOptions & {
  library?: Library;
  /** The source of the main part, when not read from disk. */
  mainSource?: Uint8Array;
};

let cachedLibrary: Library | undefined;
let cachedKeys: number[] | undefined;

/** The CPM22 runtime library, built once from its source. */
export async function runtimeLibrary(): Promise<
  { library: Library; keys: number[] }
> {
  if (!cachedLibrary) {
    const root = new URL("../../", import.meta.url).pathname;
    const source = await Deno.readTextFile(`${root}runtime/cpm22/cpm22.asm`);
    const built = await buildLibrary(source, `${root}build/compile-brl`);
    cachedLibrary = readLibrary(built.file);
    cachedKeys = built.helperKeys;
  }
  return { library: cachedLibrary, keys: cachedKeys! };
}

/** Compile and link one Baton program to a .COM image. */
export async function compile(
  mainPath: string,
  options: CompileOptions = {},
): Promise<CompileResult> {
  const { library, keys } = options.library
    ? { library: options.library, keys: options.library.keys }
    : await runtimeLibrary();
  const root = new URL("../../", import.meta.url).pathname;
  const libraryDirs = options.libraryDirs ?? [`${root}lib`];
  try {
    const stream = loadSource(
      mainPath,
      { ...options, libraryDirs },
      options.mainSource,
    );
    const compiler = new Compiler(stream.tokens, stream.parts);
    const program = compiler.compile();
    const stamp = 1;
    const dir = {
      header: defaultHeader({
        stamp,
        runtimeIdentity: library.runtimeIdentity,
        helperVersion: HELPER_VERSION,
        helperKey: keys[HELPER_VERSION - 1],
        profileIdentity: library.profileIdentity,
      }),
      records: program.records,
      trailer: {
        blobCount: program.records.filter((r) => r.type === "blob").length,
        byteStreamLength: program.bytes.length,
        highestOrdinal: Math.max(
          ...program.records.map((r) => r.type === "blob" ? r.ordinal : 0),
        ),
      },
    };
    const result = link(library, dir, program.bytes, {
      byteStreamStamp: stamp,
      lines: {
        stamp,
        parts: stream.parts.map((p) => p.name),
        blobs: program.lines,
      },
    });
    return {
      ok: true,
      com: result.output,
      lineTable: result.lineTable,
      addresses: result.addresses,
    };
  } catch (e) {
    if (e instanceof CompileError) {
      return {
        ok: false,
        diagnostics: [{
          code: e.code,
          line: e.position.line,
          column: e.position.column,
          part: `part ${e.position.part}`,
          message: e.message,
        }],
      };
    }
    if (e instanceof LinkError) return { ok: false, linkError: e.code };
    throw e;
  }
}
