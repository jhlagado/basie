/**
 * Build BASIE.COM and BASIE.OVL from their ATOM sources (design decision
 * D44) and report their extents.
 *
 *   deno task build:compiler     build both and report the extents
 *
 * BASIE.ASM assembles to the resident image, BASIE.COM. Each overlay
 * (OVERLAY.ASM) is then assembled on its own, at its load address in the
 * overlay area, which begins at the image's end (OV_AREA), against the
 * resident image's symbols: build/ovl/NAME/ holds its sources and
 * RESIDENT.ASM, an equate for every resident name it uses and the ORG of
 * its load address. BASIE.OVL is then the header (magic BSIO, version 1.0,
 * the 16-bit sum of BASIE.COM's bytes, the count) and a directory entry
 * per overlay (load address, first record, records) in its first record,
 * and the overlays, each from a record boundary.
 */
import { assembleFile, comBytes } from "../../tests/harness/cpm.ts";
import { dirname, fromFileUrl, join } from "@std/path";

export const ENTRY = "native/compiler/BASIE.ASM";

const HERE = dirname(fromFileUrl(import.meta.url));
const ROOT = join(HERE, "../..");
const STAGE = join(ROOT, "build/ovl");

/**
 * The overlays, in the order of OVERLAY.ASM's OV_ numbers, each with its
 * sources and its offset in the overlay area. FLOAT, the f32 constants,
 * is loaded after NAMES, above it, both kept while the program compiles.
 */
export const OVERLAYS = [
  {
    name: "BEGIN",
    equate: "OV_BEGIN",
    files: [
      "COMMAND.ASM",
      "LIBRARY.ASM",
      "BLOPEN.ASM",
      "PARTS.ASM",
      "FILENAME.ASM",
      "PARTNAME.ASM",
    ],
    offset: 0,
  },
  { name: "NAMES", equate: "OV_NAMES", files: ["PREDEF.ASM"], offset: 0 },
  {
    name: "CHAIN",
    equate: "OV_CHAIN",
    files: ["CHAIN.ASM", "BLCLOSE.ASM"],
    offset: 0,
  },
  {
    name: "DIAG",
    equate: "OV_DIAG",
    files: ["MESSAGE.ASM", "PARTNAME.ASM"],
    offset: 0,
  },
  {
    name: "LOOKUP",
    equate: "OV_LOOK",
    files: ["LOOKUP.ASM", "FILENAME.ASM"],
    offset: 0,
  },
  // Above NAMES, which stays loaded while FLOAT is used: FLOAT starts at
  // NAMES' last byte, and build() checks that they do not overlap.
  {
    name: "FLOAT",
    equate: "OV_FLOAT",
    files: ["FLOAT.ASM"],
    offset: 0,
    after: "NAMES",
  },
  // Above NAMES too, in FLOAT's place: each is loaded again when needed.
  {
    name: "OWNERS",
    equate: "OV_OWNS",
    files: ["OWNERS.ASM"],
    offset: 0,
    after: "NAMES",
  },
  { name: "PREP", equate: "OV_PREP", files: ["PREP.ASM"], offset: 0 },
];

export type Overlay = {
  name: string;
  /** Its load address, in the overlay area. */
  address: number;
  /** Its bytes, and the records BASIE.OVL gives them. */
  bytes: Uint8Array;
  records: number;
};

export type BasieImage = {
  /** The .COM file's bytes, from $0100 to the end of the resident image. */
  com: Uint8Array;
  /** BASIE.OVL. */
  ovl: Uint8Array;
  overlays: Overlay[];
  /** The overlay area: its address and its bytes, whole records. */
  area: number;
  areaSize: number;
  /** Symbol values by upper-case name. */
  symbols: Record<string, number>;
  /** Bytes of compiler code, of immutable data, and the two together. */
  code: number;
  immutable: number;
  core: number;
  /** Bytes of the CP/M shell, the overlay loader included. */
  shell: number;
};

let cached: Promise<BasieImage> | undefined;

/** The image, built once per process: ATOM takes most of a minute. */
export function buildBasie(): Promise<BasieImage> {
  return cached ??= build();
}

/** The names a source defines: labels and equates. */
function defined(text: string): Set<string> {
  const out = new Set<string>();
  for (const line of text.split("\n")) {
    const m = line.match(/^([A-Za-z_][A-Za-z0-9_]*)(:|\s+EQU\b)/i);
    if (m) out.add(m[1].toUpperCase());
  }
  return out;
}

/** The names a source uses, outside its comments and strings. */
function used(text: string): Set<string> {
  const out = new Set<string>();
  for (const line of text.split("\n")) {
    const code = line.replace(/"[^"]*"|'[^']*'/g, "").replace(/;.*$/, "");
    for (const m of code.matchAll(/(?<![.\w$%])[A-Za-z_][A-Za-z0-9_]*/g)) {
      out.add(m[0].toUpperCase());
    }
  }
  return out;
}

const hex = (n: number) => "$" + n.toString(16).toUpperCase().padStart(4, "0");

async function build(): Promise<BasieImage> {
  const image = await assembleFile(ENTRY);
  const symbols: Record<string, number> = {};
  for (const [name, value] of image.symbols) {
    symbols[name.toUpperCase()] = value;
  }
  const at = (name: string) => {
    const value = symbols[name];
    if (value === undefined) throw new Error(`no symbol ${name}`);
    return value;
  };
  if (at("LL_CAP") > 255 || (at("LL_STACK") & 0xff) !== 0) {
    throw new Error("the LL(1) stack is not within one page");
  }
  if (
    at("FL_WEND") - at("FL_WBEG") !== at("FL_SIZE") ||
    (at("FL_WBEG") < at("LL_STACK") && at("FL_WEND") > at("LL_DEPTH")) ||
    (at("FL_WBEG") >= at("LL_STACK") &&
      at("FL_WBEG") < at("LL_STACK") + at("LL_CAP"))
  ) {
    throw new Error("the FLOAT overlay's workspace overlaps the LL(1) stack");
  }
  if (at("KW_IDX") - at("KW_TAB") > 256) {
    throw new Error("the keywords pass the index's byte offsets");
  }
  if (at("LL_WEND") > at("SH_WBEG")) {
    throw new Error("the compiler's workspace runs into the shell's");
  }
  if (at("SH_WEND") > at("MM_BLOB")) {
    throw new Error("the shell's workspace runs into the blob writer's");
  }
  if (at("BL_WEND") > at("MM_SRC")) {
    throw new Error("the blob writer's workspace runs into the source");
  }
  const com = comBytes(image).slice(0, at("MM_END") - at("MM_BEG"));
  const area = at("OV_AREA");
  const overlays: Overlay[] = [];
  for (const [i, o] of OVERLAYS.entries()) {
    if (at(o.equate) !== i) throw new Error(`${o.equate} is not ${i}`);
    // An overlay loaded above another starts at that one's last byte:
    // loading it later overwrites only the padding of the other's last
    // record, never its bytes.
    const below = "after" in o
      ? overlays.find((v) => v.name === o.after)!
      : undefined;
    const address = below
      ? below.address + below.bytes.length
      : area + o.offset;
    overlays.push(await overlay(o, address, symbols));
  }
  for (const o of OVERLAYS) {
    if (!("after" in o)) continue;
    const above = overlays.find((v) => v.name === o.name)!;
    const below = overlays.find((v) => v.name === o.after)!;
    if (below.address + below.bytes.length > above.address) {
      throw new Error(`${o.after} runs into ${o.name}, which loads above it`);
    }
  }
  const areaEnd = Math.max(
    ...overlays.map((o) => o.address + o.records * 128),
  );
  if (areaEnd > at("MM_WBASE")) {
    throw new Error(`the overlay area ends at ${hex(areaEnd)}, over MM_WBASE`);
  }
  if (overlays.length > at("OV_DCAP")) throw new Error("too many overlays");
  return {
    com,
    ovl: overlayFile(com, overlays),
    overlays,
    area,
    areaSize: areaEnd - area,
    symbols,
    code: at("MM_CEND") - at("MM_CBEG"),
    immutable: at("MM_IEND") - at("MM_IBEG"),
    core: at("MM_REND") - at("MM_CBEG"),
    shell: at("SH_CEND") - at("SH_CBEG"),
  };
}

/** Assemble one overlay at its address against the resident symbols. */
async function overlay(
  o: (typeof OVERLAYS)[number],
  address: number,
  symbols: Record<string, number>,
): Promise<Overlay> {
  const dir = join(STAGE, o.name);
  await Deno.mkdir(dir, { recursive: true });
  const own = new Set<string>();
  const uses = new Set<string>();
  for (const file of o.files) {
    const text = await Deno.readTextFile(join(HERE, file));
    await Deno.writeTextFile(join(dir, file), text);
    for (const n of defined(text)) own.add(n);
    for (const n of used(text)) uses.add(n);
  }
  const equates = [...uses].filter((n) =>
    !own.has(n) && symbols[n] !== undefined
  ).sort();
  await Deno.writeTextFile(
    join(dir, "RESIDENT.ASM"),
    [
      `; The resident names the ${o.name} overlay uses (build.ts).`,
      ...equates.map((n) => `${n} EQU  ${hex(symbols[n])}`),
      `    ORG  ${hex(address)}`,
      "",
    ].join("\n"),
  );
  await Deno.writeTextFile(
    join(dir, "OVERLAY.ASM"),
    [
      `; The ${o.name} overlay, at ${hex(address)} (build.ts).`,
      `%INCLUDE "RESIDENT.ASM"`,
      ...o.files.map((f) => `%INCLUDE "${f}"`),
      "",
    ].join("\n"),
  );
  const image = await assembleFile(join(dir, "OVERLAY.ASM"));
  const from = address - image.base;
  const bytes = Uint8Array.from(image.bytes).slice(
    from,
    image.end - image.base,
  );
  return {
    name: o.name,
    address,
    bytes,
    records: Math.ceil(bytes.length / 128),
  };
}

/** BASIE.OVL for the resident image `com` and its overlays. */
export function overlayFile(com: Uint8Array, overlays: Overlay[]): Uint8Array {
  const sum = com.reduce((s, b) => (s + b) & 0xffff, 0);
  const head = [..."BSIO"].map((c) => c.charCodeAt(0));
  head.push(1, 0, sum & 0xff, sum >> 8, overlays.length);
  let record = 1;
  for (const o of overlays) {
    head.push(o.address & 0xff, o.address >> 8, record, o.records);
    record += o.records;
  }
  if (head.length > 128 || record > 256) throw new Error("BASIE.OVL too big");
  const out = new Uint8Array(record * 128);
  out.set(head);
  let at = 128;
  for (const o of overlays) {
    out.set(o.bytes, at);
    at += o.records * 128;
  }
  return out;
}

if (import.meta.main) {
  const image = await buildBasie();
  console.log(
    `BASIE.COM ${image.com.length} bytes: compiler core ${image.core} (code ${image.code}, immutable ${image.immutable}), shell ${image.shell}`,
  );
  console.log(
    `BASIE.OVL ${image.ovl.length} bytes; overlay area ${
      hex(image.area)
    }, ${image.areaSize} bytes:`,
  );
  for (const o of image.overlays) {
    console.log(
      `  ${o.name.padEnd(8)} ${String(o.bytes.length).padStart(5)} bytes at ${
        hex(o.address)
      }, ${o.records} records`,
    );
  }
  if (Deno.args.includes("--write")) {
    await Deno.writeFile(join(ROOT, "build/BASIE.COM"), image.com);
    await Deno.writeFile(join(ROOT, "build/BASIE.OVL"), image.ovl);
    console.log("build/BASIE.COM and build/BASIE.OVL written");
  }
}
