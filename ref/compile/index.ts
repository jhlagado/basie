/**
 * The reference compiler's entry point: source parts in, a linked .COM
 * image out (build pipeline §4).
 */
import { link, LinkError, type LinkResult } from "../link/link.ts";
import { type Library, readLibrary } from "../object/library.ts";
import {
  defaultHeader,
  writeByteStream,
  writeProgramDirectory,
} from "../object/program.ts";
import { writeLineStream, writeNameStream } from "../object/streams.ts";
import { buildLibrary } from "../../tools/brl.ts";
import { Compiler, NotImplemented } from "./compiler.ts";
import { CompileError } from "./diagnostics.ts";
import { HELPER_KEY, HELPER_VERSION } from "./helpers.ts";
import { messageNumber } from "./messages.ts";
import { loadSource, type SourceOptions } from "./source.ts";

export { NotImplemented };

export type Diagnostic = {
  code: string;
  /** The message number in BASIE.MSG (D39). */
  number: number;
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
    /** The exact image size, before padding to 128-byte records. */
    imageSize: number;
    lineTable?: Uint8Array;
    addresses: Map<number, number>;
    /**
     * The intermediate files the native linker reads (toolchain §3.2): the
     * program directory, byte stream and line stream.
     */
    objects: {
      directory: Uint8Array;
      bytes: Uint8Array;
      lines: Uint8Array;
      names: Uint8Array;
    };
    /** The reference linker's result, for building its reports. */
    link: LinkResult;
    /** The reference linker's view of every blob, for comparing linkers. */
    blobs: { ordinal: number; kind: number; size: number; live: boolean }[];
  }
  | { ok: false; diagnostics: Diagnostic[] }
  | { ok: false; linkError: string };

export type CompileOptions = SourceOptions & {
  library?: Library;
  /** The source of the main part, when not read from disk. */
  mainSource?: Uint8Array;
  /** Shrink forward jumps to JR (default on; off to measure the gain). */
  shrink?: boolean;
};

let cachedLibrary: Library | undefined;

/** The CPM22 runtime library, built once from its source. */
export async function runtimeLibrary(): Promise<Library> {
  if (!cachedLibrary) {
    const root = new URL("../../", import.meta.url).pathname;
    const source = await Deno.readTextFile(`${root}runtime/cpm22/cpm22.asm`);
    const built = await buildLibrary(
      source,
      `${root}build/compile-brl`,
      `${root}runtime/cpm22`,
    );
    cachedLibrary = readLibrary(built.file);
  }
  return cachedLibrary;
}

/** Compile and link one Basie program to a .COM image. */
export async function compile(
  mainPath: string,
  options: CompileOptions = {},
): Promise<CompileResult> {
  const library = options.library ?? await runtimeLibrary();
  const root = new URL("../../", import.meta.url).pathname;
  const libraryDirs = options.libraryDirs ?? [`${root}lib`];
  let partNames: string[] = [];
  try {
    const stream = loadSource(
      mainPath,
      { ...options, libraryDirs },
      options.mainSource,
    );
    partNames = stream.parts.map((p) => p.name);
    const compiler = new Compiler(
      stream.tokens,
      stream.parts,
      true,
      options.shrink ?? true,
    );
    const program = compiler.compile();
    const stamp = 1;
    const dir = {
      header: defaultHeader({
        stamp,
        runtimeIdentity: library.runtimeIdentity,
        helperVersion: HELPER_VERSION,
        // The key of the table compiled into the compiler: the linker
        // refuses a library whose key for this version differs.
        helperKey: HELPER_KEY,
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
    const parts = stream.parts.map((p) => p.name);
    return {
      ok: true,
      imageSize: result.image.length,
      com: result.output,
      lineTable: result.lineTable,
      addresses: result.addresses,
      objects: {
        directory: writeProgramDirectory(
          dir.header,
          program.records,
          program.bytes.length,
        ),
        bytes: writeByteStream(stamp, program.bytes),
        lines: writeLineStream(stamp, parts, program.lines),
        names: writeNameStream(stamp, program.names),
      },
      link: result,
      blobs: result.blobs.map((b) => ({
        ordinal: b.ordinal,
        kind: b.kind,
        size: b.size,
        live: b.live,
      })),
    };
  } catch (e) {
    if (e instanceof CompileError) {
      return {
        ok: false,
        diagnostics: [{
          code: e.code,
          number: messageNumber(e.code) ?? 0,
          line: e.position.line,
          column: e.position.column,
          part: e.partName ?? partNames[e.position.part] ??
            `part ${e.position.part}`,
          message: e.message,
        }],
      };
    }
    if (e instanceof LinkError) return { ok: false, linkError: e.code };
    throw e;
  }
}
