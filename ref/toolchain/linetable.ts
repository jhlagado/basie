/** Reading the line table the linker writes (object format §11). */
import { ByteReader } from "../object/directory.ts";
import { crc16 } from "../object/crc.ts";
import { ObjectError } from "../object/types.ts";

export type LineTable = {
  parts: string[];
  outputName: string;
  libraryName: string;
  /** Statement entries in address order; part 255 marks a blob start. */
  entries: { address: number; part: number; source: number }[];
  imageCrc: number;
};

export function readLineTable(bytes: Uint8Array): LineTable {
  const r = new ByteReader(bytes, "line table");
  if (r.ascii(4) !== "BTLT") throw new ObjectError("L-FORMAT", "bad magic");
  if (r.u8() !== 1 || r.u8() > 0) throw new ObjectError("L-FORMAT", "version");
  const partCount = r.u8();
  const outputName = r.ascii(r.u8());
  const libraryName = r.ascii(r.u8());
  const parts: string[] = [];
  for (let i = 0; i < partCount; i += 1) parts.push(r.ascii(r.u8()));
  const entries: LineTable["entries"] = [];
  while (true) {
    const address = r.u16();
    const part = r.u8();
    const source = r.u16();
    if (address === 0xffff && part === 0xff && source === 0xffff) break;
    entries.push({ address, part, source });
  }
  const count = r.u16();
  if (count !== entries.length) {
    throw new ObjectError("L-TRUNCATED", "entry count");
  }
  const imageCrc = r.u16();
  const stored = r.u16();
  if (stored !== crc16(bytes.subarray(0, bytes.length - 2))) {
    throw new ObjectError("L-TRUNCATED", "line table CRC");
  }
  return { parts, outputName, libraryName, entries, imageCrc };
}

/** The statement containing an address: its part and source line, if any. */
export function lookup(
  table: LineTable,
  address: number,
): { part: string; line: number } | undefined {
  let best: LineTable["entries"][number] | undefined;
  for (const e of table.entries) {
    if (e.address > address) break;
    if (e.part !== 0xff) best = e;
    else best = undefined; // a blob without lines
  }
  if (!best) return undefined;
  return { part: table.parts[best.part], line: best.source };
}
