/**
 * Build a blob library (.BRL) from annotated ATOM source (roadmap step 30).
 *
 * The source is split at "; @blob" lines. The tool generates three
 * assemblies of the whole source: A, unshifted; B, with blob i moved up by
 * i*$100; C, with blob i moved up by i*S, where S is the largest blob
 * alignment. Pseudo-objects and their sizes are EQUs whose values move the
 * same way, with indexes after the blobs'. A 16-bit word that changes by
 * exactly k*$100 in B and k*S in C is an ABS16 (or SIZE16) reference to
 * target k, with addend A's word minus target k's A address. Any other
 * changed byte is an error. Reference fields are stored as zero.
 *
 * Usage: deno run -A --config deno.runtime.json tools/brl.ts SOURCE.asm OUT.BRL
 */
import {
  assembleResolvedAtomProject,
  materializeAtomGeneration,
  resolveAtomProject,
} from "atom-z80";

/**
 * ATOM's default arenas suit small programs; a whole runtime has hundreds of
 * labels and forward references across blobs, so the pending arena is
 * enlarged (capacity audit: a tool limit, not a Basie one).
 */
const ATOM_LAYOUT = {
  symbolStart: 0x4100,
  symbolEnd: 0xa000,
  pendingStart: 0xa000,
  pendingEnd: 0xf000,
  partDescriptors: 0xf000,
};
import { basename, dirname, join } from "@std/path";
import { crc16 } from "../ref/object/crc.ts";
import { type Profile, writeLibrary } from "../ref/object/library.ts";
import { writeNameStream } from "../ref/object/streams.ts";
import {
  analyzeStack,
  type StackBlob,
  StackError,
  type StackFigure,
} from "./stack.ts";
import {
  type BlobRecord,
  Form,
  Kind,
  type KindCode,
  Pseudo,
  type Reference,
} from "../ref/object/types.ts";

export class BrlError extends Error {}

type BlobSource = {
  ordinal: number;
  kind: KindCode;
  name: string;
  align: number;
  helper?: number;
  since: number;
  /** A stated stack figure (tools/stack.ts), for code it can't follow. */
  stack?: number;
  /** Where the blob's indirect jump goes (tools/stack.ts). */
  indirect?: string;
  text: string;
};

type Parsed = {
  name: string;
  runtimeIdentity: number;
  helperVersion: number;
  profileIdentity: number;
  profile: Profile;
  prelude: string;
  blobs: BlobSource[];
};

/** Pseudo-object symbols: [name, target, form]. */
const PSEUDO_SYMBOLS: [string, number, number][] = [
  ["MAIN", Pseudo.MAIN, Form.ABS16],
  ["IMAGE", Pseudo.IMAGE, Form.ABS16],
  ["BSS", Pseudo.BSS, Form.ABS16],
  ["FREE", Pseudo.FREE, Form.ABS16],
  ["REQUIRED", Pseudo.REQUIRED, Form.ABS16],
  ["DATA", Pseudo.DATA, Form.ABS16],
  ["DATACOPY", Pseudo.DATACOPY, Form.ABS16],
  ["OPTIONS", Pseudo.OPTIONS, Form.ABS16],
  ["FILES", Pseudo.FILES, Form.ABS16],
  ["FILECNT", Pseudo.FILECOUNT, Form.ABS16],
  ["IMAGELEN", Pseudo.IMAGE, Form.SIZE16],
  ["BSSLEN", Pseudo.BSS, Form.SIZE16],
  ["DATALEN", Pseudo.DATA, Form.SIZE16],
  ["COPYLEN", Pseudo.DATACOPY, Form.SIZE16],
  ["FILESLEN", Pseudo.FILES, Form.SIZE16],
];
const PSEUDO_BASE = 0x8000;

const PROFILE_KEYS: Record<string, keyof Profile> = {
  class: "targetClass",
  kinds: "outputKinds",
  base: "imageBase",
  limit: "imageLimit",
  top: "nominalTop",
  ccp: "ccpSize",
  ram: "ramBase",
  ramlimit: "ramLimit",
  guard: "guardBand",
  options: "optionSupport",
  rst: "freeRestartVectors",
  debugger: "debuggerMargin",
  file: "fileEntrySize",
};

function number(text: string): number {
  const n = text.startsWith("$")
    ? parseInt(text.slice(1), 16)
    : parseInt(text, 10);
  if (Number.isNaN(n)) throw new BrlError(`not a number: ${text}`);
  return n;
}

function keyValues(words: string[]): Record<string, string> {
  const out: Record<string, string> = {};
  for (const w of words) {
    const [k, v] = w.split("=");
    if (v === undefined) throw new BrlError(`expected key=value: ${w}`);
    out[k] = v;
  }
  return out;
}

export function parseSource(source: string): Parsed {
  const profile: Profile = {
    targetClass: 0,
    outputKinds: 0,
    imageBase: 0,
    imageLimit: 0,
    nominalTop: 0,
    ccpSize: 0,
    ramBase: 0,
    ramLimit: 0,
    guardBand: 0,
    optionSupport: 0,
    freeRestartVectors: 0,
    debuggerMargin: 0,
    fileEntrySize: 0,
  };
  let name = "";
  let ids = { runtime: 0, helpers: 0, profile: 0 };
  const prelude: string[] = [];
  const blobs: BlobSource[] = [];
  let current: string[] = prelude;
  for (const line of source.split(/\r?\n/)) {
    const m = line.match(/^;\s*@(library|profile|blob)\s+(.*)$/);
    if (!m) {
      current.push(line);
      continue;
    }
    const words = m[2].trim().split(/\s+/);
    if (m[1] === "library") {
      name = words[0];
      const kv = keyValues(words.slice(1));
      ids = {
        runtime: number(kv.runtime ?? "0"),
        helpers: number(kv.helpers ?? "0"),
        profile: number(kv.profile ?? "0"),
      };
    } else if (m[1] === "profile") {
      for (const [k, v] of Object.entries(keyValues(words))) {
        const field = PROFILE_KEYS[k];
        if (!field) throw new BrlError(`unknown profile key ${k}`);
        profile[field] = number(v);
      }
    } else {
      const [ord, kind, blobName, ...rest] = words;
      if (!(kind in Kind)) throw new BrlError(`unknown kind ${kind}`);
      const kv = keyValues(rest);
      const align = number(kv.align ?? "1");
      if (align & (align - 1) || align > 256) {
        throw new BrlError(
          `${blobName}: alignment must be a power of 2 up to 256`,
        );
      }
      if (blobName.length > 8) {
        throw new BrlError(
          `${blobName}: a blob name is at most 8 characters (ATOM's limit)`,
        );
      }
      current = [];
      blobs.push({
        ordinal: number(ord),
        kind: Kind[kind as keyof typeof Kind],
        name: blobName,
        align,
        helper: kv.helper === undefined ? undefined : number(kv.helper),
        since: number(kv.since ?? "1"),
        stack: kv.stack === undefined ? undefined : number(kv.stack),
        indirect: kv.indirect,
        text: "",
      });
      (blobs.at(-1) as BlobSource & { lines: string[] }).lines = current;
    }
  }
  for (const b of blobs) {
    b.text = (b as BlobSource & { lines: string[] }).lines.join("\n");
  }
  if (!name) throw new BrlError("no @library line");
  if (blobs.length === 0) throw new BrlError("no blobs");
  return {
    name,
    runtimeIdentity: ids.runtime,
    helperVersion: ids.helpers,
    profileIdentity: ids.profile,
    profile,
    prelude: prelude.join("\n"),
    blobs,
  };
}

const h = (n: number) =>
  "$" + (n & 0xffff).toString(16).toUpperCase().padStart(4, "0");

/**
 * ATOM source parts are limited to 65,535 bytes, so a variant is split at
 * blob boundaries into parts below PART_LIMIT. Each part includes the one
 * before it, and ATOM assembles a dependency before its importer, so the
 * parts assemble in order (a capacity of the tool, not of Basie).
 */
const PART_LIMIT = 48_000;

/** Source for one variant, as ordered parts; step is the per-index shift. */
function variant(p: Parsed, step: number): string[] {
  const n = p.blobs.length;
  const head: string[] = [];
  PSEUDO_SYMBOLS.forEach(([name], j) => {
    head.push(`${name} EQU ${h(PSEUDO_BASE + (n + 1 + j) * step)}`);
  });
  head.push(p.prelude, "        ORG     $0000");
  const parts: string[][] = [head];
  let size = head.join("\n").length;
  p.blobs.forEach((b, i) => {
    const lines: string[] = [];
    if (step) lines.push(`        DS      ${h(step)}`);
    if (b.align > 1) lines.push(`        ALIGN   ${b.align}`);
    lines.push(b.text, `Z__${(i + 1).toString(16).padStart(3, "0")}:`);
    const text = lines.join("\n");
    if (size + text.length > PART_LIMIT) {
      parts.push([]);
      size = 0;
    }
    parts.at(-1)!.push(text);
    size += text.length + 1;
  });
  return parts.map((lines) => lines.join("\n") + "\n");
}

async function assemble(dir: string, file: string, parts: string[]) {
  // Part k includes part k-1; the entry file includes the last part.
  const stem = file.replace(/\.ASM$/, "");
  const names = parts.map((_, k) =>
    `${stem}${k.toString().padStart(2, "0")}.ASM`
  );
  for (let k = 0; k < parts.length; k += 1) {
    const header = k === 0 ? "" : `%INCLUDE "${names[k - 1]}"\n`;
    await Deno.writeTextFile(join(dir, names[k]), header + parts[k]);
  }
  await Deno.writeTextFile(join(dir, file), `%INCLUDE "${names.at(-1)}"\n`);
  let result;
  try {
    const project = await resolveAtomProject({
      root: dir,
      entry: file,
      assembler: undefined,
      definitions: {},
      placement: { defaultBank: 0, banks: {} },
      limits: { maxParts: 255, maxBank: 0 },
    });
    result = await assembleResolvedAtomProject(project, {
      maxInstructions: 100_000_000,
      maxCycles: 1_000_000_000,
      nativeMemoryLayout: ATOM_LAYOUT,
    });
  } catch (e) {
    const d = (e as { diagnostic?: { line: number; column: number } })
      .diagnostic;
    const native = (e as { native?: { statementDetail?: number } }).native;
    const where = d ? ` at line ${d.line}, column ${d.column}` : "";
    const why = native?.statementDetail === 4
      ? " (a relative jump out of range, reported at the label it reaches)"
      : file === "A.ASM"
      ? ""
      : " (a relative jump between blobs?)";
    throw new BrlError(`${file}: ${(e as Error).message}${where}${why}`);
  }
  const image = materializeAtomGeneration(result.generation);
  const symbols = new Map<string, number>();
  for (
    const s of result.generation.symbols as { name: string; value: number }[]
  ) {
    symbols.set(s.name.toUpperCase(), s.value);
  }
  const at = (a: number) => image ? image.bytes[a - image.base] ?? 0 : 0;
  return { at, symbols };
}

/** One row of the published helper table (object format §10). */
export type HelperRow = {
  ordinal: number;
  name: string;
  kind: KindCode;
  convention: number;
  since: number;
  size: number;
} & StackFigure;

export type BuiltLibrary = {
  file: Uint8Array;
  names: Map<number, string>;
  helperKeys: number[];
  helperVersion: number;
  /** Every helper, in ordinal order, with its size and stack figures. */
  helpers: HelperRow[];
  /** The stack figures of every code blob, helper or not, by ordinal. */
  stack: Map<number, StackFigure>;
};

/** Inline `; @include FILE` lines, relative to `dir`. */
export async function expandIncludes(
  source: string,
  dir: string,
): Promise<string> {
  const out: string[] = [];
  for (const line of source.split(/\r?\n/)) {
    const m = line.match(/^;\s*@include\s+(\S+)/);
    if (m) {
      const text = await Deno.readTextFile(join(dir, m[1]));
      out.push(await expandIncludes(text, dir));
    } else out.push(line);
  }
  return out.join("\n");
}

export async function buildLibrary(
  source: string,
  workDir: string,
  sourceDir?: string,
): Promise<BuiltLibrary> {
  if (sourceDir) source = await expandIncludes(source, sourceDir);
  const p = parseSource(source);
  const n = p.blobs.length;
  const targets = n + PSEUDO_SYMBOLS.length;
  const maxAlign = Math.max(1, ...p.blobs.map((b) => b.align));
  if (targets * Math.max(0x100, maxAlign) > 0xffff) {
    throw new BrlError(`too many blobs for one build: ${n}`);
  }
  await Deno.mkdir(workDir, { recursive: true });
  const [a, b, c] = await Promise.all([
    assemble(workDir, "A.ASM", variant(p, 0)),
    assemble(workDir, "B.ASM", variant(p, 0x100)),
    assemble(workDir, "C.ASM", variant(p, maxAlign)),
  ]);
  const sym = (v: typeof a, name: string) => {
    const s = v.symbols.get(name.toUpperCase());
    if (s === undefined) throw new BrlError(`${name}: no such label`);
    return s;
  };
  const records: BlobRecord[] = [];
  const bytes: number[] = [];
  const names = new Map<number, string>();
  const stackBlobs: StackBlob[] = [];
  p.blobs.forEach((blob, i) => {
    const end = `Z__${(i + 1).toString(16).padStart(3, "0")}`;
    const startA = sym(a, blob.name);
    const size = sym(a, end) - startA;
    const startB = sym(b, blob.name);
    const startC = sym(c, blob.name);
    if (
      startB - startA !== (i + 1) * 0x100 ||
      startC - startA !== (i + 1) * maxAlign
    ) {
      throw new BrlError(`${blob.name}: label is not at the start of its blob`);
    }
    if (startA % blob.align !== 0) {
      throw new BrlError(`${blob.name}: not aligned`);
    }
    const references: Reference[] = [];
    const own: number[] = [];
    for (let o = 0; o < size; o += 1) {
      const va = a.at(startA + o);
      const vb = b.at(startB + o);
      const vc = c.at(startC + o);
      if (va === vb && va === vc) {
        own.push(va);
        continue;
      }
      const wa = va | a.at(startA + o + 1) << 8;
      const wb = vb | b.at(startB + o + 1) << 8;
      const wc = vc | c.at(startC + o + 1) << 8;
      const db = (wb - wa) & 0xffff;
      const dc = (wc - wa) & 0xffff;
      const k = db >> 8;
      if (
        o + 1 >= size || (db & 0xff) !== 0 || k < 1 || k > targets ||
        dc !== ((k * maxAlign) & 0xffff)
      ) {
        throw new BrlError(
          `${blob.name}+${o}: a relocatable byte that is not a 16-bit reference`,
        );
      }
      let target: number, form: number, base: number;
      if (k <= n) {
        target = p.blobs[k - 1].ordinal;
        form = Form.ABS16;
        base = sym(a, p.blobs[k - 1].name);
      } else {
        [, target, form] = PSEUDO_SYMBOLS[k - n - 1];
        base = PSEUDO_BASE;
      }
      references.push({
        offset: o,
        form: form as Reference["form"],
        target,
        addend: (wa - base) & 0xffff,
      });
      own.push(0, 0);
      o += 1;
    }
    if (blob.kind === Kind.code) {
      stackBlobs.push({
        ordinal: blob.ordinal,
        name: blob.name,
        bytes: own,
        references: new Map(
          references.map((r) => [r.offset, {
            target: r.target,
            addend: r.addend,
          }]),
        ),
        stack: blob.stack,
        indirect: blob.indirect,
      });
    }
    if (blob.kind !== Kind.bss) bytes.push(...own);
    else if (own.some((x) => x !== 0)) {
      throw new BrlError(`${blob.name}: a bss blob holds no bytes`);
    }
    records.push({
      type: "blob",
      kind: blob.kind,
      ordinal: blob.ordinal,
      size,
      root: blob.kind === Kind.startup,
      align: Math.log2(blob.align) === 8 ? 7 : Math.log2(blob.align),
      references,
    });
    names.set(blob.ordinal, blob.name);
  });
  const helperKeys = interfaceKeys(p);
  let figures: Map<number, StackFigure>;
  try {
    figures = analyzeStack(stackBlobs);
  } catch (e) {
    if (e instanceof StackError) throw new BrlError(e.message);
    throw e;
  }
  const helpers: HelperRow[] = p.blobs
    .filter((b) => b.helper !== undefined)
    .sort((x, y) => x.ordinal - y.ordinal)
    .map((b) => {
      const f = figures.get(b.ordinal);
      if (!f) throw new BrlError(`${b.name}: a helper must be code`);
      return {
        ordinal: b.ordinal,
        name: b.name,
        kind: b.kind,
        convention: b.helper!,
        since: b.since,
        size: records.find((r) => r.type === "blob" && r.ordinal === b.ordinal)!
          .size,
        ...f,
      };
    });
  const file = writeLibrary({
    runtimeIdentity: p.runtimeIdentity,
    helperVersion: p.helperVersion,
    profileIdentity: p.profileIdentity,
    profile: p.profile,
    records,
    bytes: Uint8Array.from(bytes),
    keys: helperKeys,
    names: writeNameStream(
      0,
      [...names].map(([ordinal, name]) => ({ ordinal, name })),
    ),
  });
  return {
    file,
    names,
    helperKeys,
    helperVersion: p.helperVersion,
    helpers,
    stack: figures,
  };
}

/**
 * Interface keys (object format §10): for each helper-table version v, the
 * CRC of 4 bytes per helper defined by v, in ordinal order: ordinal (u16),
 * kind (u8), calling-convention code (u8).
 */
export function interfaceKeys(p: Parsed): number[] {
  const keys: number[] = [];
  for (let v = 1; v <= p.helperVersion; v += 1) {
    const desc: number[] = [];
    for (const b of [...p.blobs].sort((x, y) => x.ordinal - y.ordinal)) {
      if (b.helper === undefined || b.since > v) continue;
      desc.push(b.ordinal & 0xff, b.ordinal >> 8, b.kind, b.helper);
    }
    keys.push(crc16(Uint8Array.from(desc)));
  }
  return keys;
}

if (import.meta.main) {
  const [src, out] = Deno.args;
  if (!src || !out) {
    console.error("usage: brl.ts SOURCE.asm OUT.BRL");
    Deno.exit(2);
  }
  const work = join(dirname(out), `.${basename(out)}.work`);
  const built = await buildLibrary(
    await Deno.readTextFile(src),
    work,
    dirname(src),
  );
  await Deno.remove(work, { recursive: true });
  await Deno.writeFile(out, built.file);
  console.log(`${out}: ${built.file.length} bytes, ${built.names.size} blobs`);
}
