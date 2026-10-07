/**
 * List the source for an address of a linked Basie program (roadmap step
 * 73): the statement the line table places there (NAME.LIN, object format
 * §11), the named blob the debug file places it in (NAME.DBG, §14, written
 * with link option D), and the source line, read from the part's file.
 *
 *   deno task where NAME ADDRESS [DIRECTORY...]
 *
 * ADDRESS is hexadecimal, with or without `$`. The parts are looked for in
 * NAME's directory, then in each DIRECTORY given, then in lib/.
 */
import { crc16 } from "../ref/object/crc.ts";

export type LineTable = {
  output: string;
  parts: string[];
  /** In increasing address order. */
  entries: { address: number; part: number; line: number; column: number }[];
  imageCrc: number;
};

export type DebugFile = {
  imageCrc: number;
  /** Live named blobs with bytes, in address order. */
  blobs: { kind: number; address: number; size: number; name: string }[];
};

const decoder = new TextDecoder();
const u16 = (b: Uint8Array, i: number) => b[i] | (b[i + 1] << 8);

/** Read a line table (object format §11). */
export function readLineTable(b: Uint8Array): LineTable {
  if (decoder.decode(b.subarray(0, 4)) !== "BSIT") {
    throw new Error("not a line table");
  }
  let i = 6;
  const partCount = b[i++];
  const outputLength = b[i++];
  const output = decoder.decode(b.subarray(i, i + outputLength));
  i += outputLength;
  i += 1 + b[i]; // the library's name
  const parts: string[] = [];
  for (let p = 0; p < partCount; p++) {
    const n = b[i++];
    parts.push(decoder.decode(b.subarray(i, i + n)));
    i += n;
  }
  const entries: LineTable["entries"] = [];
  while (!b.subarray(i, i + 6).every((x) => x === 0xff)) {
    entries.push({
      address: u16(b, i),
      part: b[i + 2],
      line: u16(b, i + 3),
      column: b[i + 5],
    });
    i += 6;
  }
  const imageCrc = u16(b, i + 8);
  if (crc16(b.subarray(0, i + 10)) !== u16(b, i + 10)) {
    throw new Error("the line table's CRC is wrong");
  }
  return { output, parts, entries, imageCrc };
}

/** Read a debug file (object format §14). */
export function readDebugFile(b: Uint8Array): DebugFile {
  if (decoder.decode(b.subarray(0, 4)) !== "BSID" || b[4] !== 1) {
    throw new Error("not a debug file of version 1");
  }
  const imageCrc = u16(b, 6);
  let i = 8;
  const blobs: DebugFile["blobs"] = [];
  while (b[i] !== 0xff) {
    const n = b[i + 5];
    blobs.push({
      kind: b[i],
      address: u16(b, i + 1),
      size: u16(b, i + 3),
      name: decoder.decode(b.subarray(i + 6, i + 6 + n)),
    });
    i += 6 + n;
  }
  i += 5; // $FF, no frames, no types
  if (crc16(b.subarray(0, i)) !== u16(b, i)) {
    throw new Error("the debug file's CRC is wrong");
  }
  return { imageCrc, blobs };
}

export type Place = {
  part?: string;
  line?: number;
  column?: number;
  blob?: string;
  offset?: number;
};

/** Where an address lies: its statement and the named blob it is in. */
export function lookup(
  lines: LineTable,
  debug: DebugFile | undefined,
  address: number,
): Place {
  const place: Place = {};
  let found;
  for (const e of lines.entries) {
    if (e.address > address) break;
    found = e;
  }
  if (found && found.part !== 0xff) {
    place.part = lines.parts[found.part];
    place.line = found.line;
    place.column = found.column;
  }
  for (const b of debug?.blobs ?? []) {
    if (address >= b.address && address < b.address + b.size) {
      place.blob = b.name;
      place.offset = address - b.address;
    }
  }
  return place;
}

if (import.meta.main) {
  const [name, text, ...dirs] = Deno.args;
  if (!name || !text) {
    console.log("Usage: deno task where NAME ADDRESS [DIRECTORY...]");
    Deno.exit(1);
  }
  const base = name.replace(/\.(COM|LIN|DBG)$/i, "");
  const lines = readLineTable(Deno.readFileSync(`${base}.LIN`));
  let debug: DebugFile | undefined;
  try {
    debug = readDebugFile(Deno.readFileSync(`${base}.DBG`));
    if (debug.imageCrc !== lines.imageCrc) {
      console.log(`${base}.DBG is not for the program ${base}.LIN describes`);
      debug = undefined;
    }
  } catch {
    debug = undefined;
  }
  const address = parseInt(text.replace(/^\$/, ""), 16);
  const place = lookup(lines, debug, address);
  const hex = (n: number) =>
    "$" + n.toString(16).toUpperCase().padStart(4, "0");
  const where = place.part
    ? `${place.part}:${place.line}:${place.column}`
    : "no source";
  const within = place.blob ? ` in ${place.blob}+${hex(place.offset!)}` : "";
  console.log(`${lines.output} ${hex(address)}: ${where}${within}`);
  if (place.part) {
    const folder = base.includes("/") ? base.replace(/\/[^/]*$/, "") : ".";
    for (const dir of [folder, ...dirs, "lib"]) {
      try {
        const source = decoder.decode(
          Deno.readFileSync(`${dir}/${place.part}`),
        );
        const row = source.split(/\r?\n/)[place.line! - 1] ?? "";
        const label = String(place.line).padStart(5);
        console.log(`${label} | ${row}`);
        console.log(`${" ".repeat(5)} | ${" ".repeat(place.column! - 1)}^`);
        break;
      } catch {
        continue;
      }
    }
  }
}
