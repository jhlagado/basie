/**
 * Source parts and `include` (spec chapter 4, section 4.3). Builds one
 * token stream from the parts of a compilation, compiling each included
 * part before the rest of the part that includes it, once only.
 */
import { basename, dirname, join } from "@std/path";
import { CompileError, fail } from "./diagnostics.ts";
import { LexError, type Token, tokenize } from "./lexer.ts";

export type Part = {
  /** Part number in stream order, from 0. */
  number: number;
  /** The CP/M-style identity: the upper-case file name. */
  name: string;
  path: string;
};

export type SourceStream = {
  parts: Part[];
  tokens: Token[];
};

export type Reader = {
  /** The bytes of a file, or undefined if it does not exist. */
  read(path: string): Uint8Array | undefined;
};

export const fileReader: Reader = {
  read(path) {
    try {
      return Deno.readFileSync(path);
    } catch {
      return undefined;
    }
  },
};

export type SourceOptions = {
  /** Directories searched after the including part's own, in order. */
  libraryDirs?: string[];
  reader?: Reader;
};

/** Load a main part and everything it includes. */
export function loadSource(
  mainPath: string,
  options: SourceOptions = {},
  mainBytes?: Uint8Array,
): SourceStream {
  const reader = options.reader ?? fileReader;
  const libraryDirs = options.libraryDirs ?? [];
  const parts: Part[] = [];
  const tokens: Token[] = [];
  const loaded = new Map<string, Part>(); // by resolved path
  const open = new Set<string>();

  const load = (path: string, bytes: Uint8Array): void => {
    // Parts are numbered in stream order, so the number is known only
    // after the part's includes have been loaded; tokens are renumbered then.
    const part: Part = { number: -1, name: basename(path).toUpperCase(), path };
    loaded.set(path, part);
    open.add(path);
    const provisional = parts.length;
    try {
      loadPart(part, path, bytes, provisional);
    } catch (e) {
      // Errors before the part's number is fixed carry its name (1.6, 3.3).
      if (
        e instanceof CompileError && e.partName === undefined &&
        e.position.part === provisional && part.number < 0
      ) e.partName = part.name;
      throw e;
    }
  };

  const loadPart = (
    part: Part,
    path: string,
    bytes: Uint8Array,
    provisional: number,
  ): void => {
    let partTokens: Token[];
    try {
      partTokens = tokenize(bytes, provisional, false);
    } catch (e) {
      if (e instanceof LexError) {
        throw new CompileError(e.code, e.position, e.text);
      }
      throw e;
    }
    // Include lines come first; each is `include STRING NEWLINE`.
    let i = 0;
    while (i < partTokens.length) {
      const t = partTokens[i];
      if (t.kind !== "keyword" || t.text !== "include") break;
      const name = partTokens[i + 1];
      const end = partTokens[i + 2];
      if (!name || name.kind !== "string") {
        fail("include-syntax", t, "include needs a quoted file name");
      }
      if (!end || end.kind !== "newline") {
        fail("include-syntax", end ?? t, "include takes one file name");
      }
      const text = new TextDecoder().decode(
        (name as Token & { kind: "string" }).bytes,
      )
        .toUpperCase();
      const resolved = resolve(text, dirname(path));
      if (resolved === undefined) {
        fail("include-missing", name, `${text} not found`);
      }
      if (open.has(resolved!)) {
        fail("include-cycle", name, `${text} includes itself`);
      }
      if (!loaded.has(resolved!)) {
        load(resolved!, reader.read(resolved!)!);
      }
      i += 3;
    }
    // A later include is an error (4.3.2, rule 1).
    for (let k = i; k < partTokens.length; k += 1) {
      const t = partTokens[k];
      if (t.kind === "keyword" && t.text === "include") {
        fail("include-position", t, "include must come before declarations");
      }
    }
    part.number = parts.length;
    parts.push(part);
    for (const t of partTokens) t.part = part.number;
    tokens.push(...partTokens.slice(i));
    open.delete(path);
  };

  const resolve = (name: string, ownDir: string): string | undefined => {
    for (const dir of [ownDir, ...libraryDirs]) {
      for (
        const candidate of [join(dir, name), join(dir, name.toLowerCase())]
      ) {
        if (reader.read(candidate) !== undefined) return candidate;
      }
    }
    return undefined;
  };

  const bytes = mainBytes ?? reader.read(mainPath);
  if (bytes === undefined) {
    throw new CompileError(
      "include-missing",
      { part: 0, offset: 0, line: 1, column: 1 },
      `${mainPath} not found`,
    );
  }
  load(mainPath, bytes);
  const last = tokens.at(-1);
  const at = last
    ? {
      part: last.part,
      offset: last.end,
      line: last.line,
      column: last.column,
    }
    : { part: 0, offset: 0, line: 1, column: 1 };
  tokens.push({ ...at, end: at.offset, kind: "eof" });
  return { parts, tokens };
}
