/** Line and name streams (object format §8, §9). */
import { ByteReader, ByteWriter } from "./directory.ts";
import { crc16 } from "./crc.ts";
import { ObjectError } from "./types.ts";

export type LineEntry = { offset: number; part: number; source: number };
export type BlobLines = { ordinal: number; entries: LineEntry[] };

export function writeLineStream(
  stamp: number,
  parts: string[],
  blobs: BlobLines[],
): Uint8Array {
  const out = new ByteWriter();
  out.ascii("BSIL");
  out.u8(1);
  out.u8(0);
  out.u16(stamp);
  parts.forEach((name, i) => {
    out.u8(0x01);
    out.u8(i);
    out.u8(name.length);
    out.ascii(name);
  });
  for (const b of blobs) {
    out.u8(0x02);
    out.u16(b.ordinal);
    out.u16(b.entries.length);
    let last: number | undefined;
    let part: number | undefined;
    for (const e of b.entries) {
      const delta = last === undefined ? e.offset : e.offset - last;
      if (delta < 0) throw new RangeError("line offsets must not decrease");
      const changes = part === undefined || e.part !== part;
      if (delta === 0 && last !== undefined && !changes) {
        throw new RangeError("two entries at one offset need different parts");
      }
      const escape = delta > 126;
      out.u8((escape ? 127 : delta) | (changes ? 0x80 : 0));
      if (escape) out.u16(e.offset);
      if (changes) out.u8(e.part);
      out.u16(e.source);
      last = e.offset;
      part = e.part;
    }
  }
  out.u8(0xff);
  out.u16(crc16(out.toBytes()));
  return out.toBytes();
}

export function readLineStream(bytes: Uint8Array) {
  const r = new ByteReader(bytes, "line stream");
  if (r.ascii(4) !== "BSIL") throw new ObjectError("L-FORMAT", "bad magic");
  if (r.u8() !== 1 || r.u8() > 0) throw new ObjectError("L-FORMAT", "version");
  const stamp = r.u16();
  const parts: string[] = [];
  const blobs: BlobLines[] = [];
  while (true) {
    const tag = r.u8();
    if (tag === 0xff) break;
    if (tag === 0x01) {
      if (blobs.length > 0) {
        throw new ObjectError("L-FORMAT", "part record after blob lines");
      }
      const index = r.u8();
      parts[index] = r.ascii(r.u8());
    } else if (tag === 0x02) {
      const ordinal = r.u16();
      const entries: LineEntry[] = [];
      let last: number | undefined;
      let part: number | undefined;
      for (let n = r.u16(); n > 0; n -= 1) {
        const control = r.u8();
        const field = control & 0x7f;
        const offset = field === 127
          ? r.u16()
          : last === undefined
          ? field
          : last + field;
        if (control & 0x80) part = r.u8();
        if (part === undefined) {
          throw new ObjectError("L-FORMAT", "first line entry has no part");
        }
        entries.push({ offset, part, source: r.u16() });
        last = offset;
      }
      blobs.push({ ordinal, entries });
    } else {
      throw new ObjectError("L-FORMAT", `line record tag ${tag}`);
    }
  }
  const end = r.position;
  if (r.u16() !== crc16(bytes.subarray(0, end))) {
    throw new ObjectError("L-TRUNCATED", "line stream CRC mismatch");
  }
  return { stamp, parts, blobs };
}

export function writeNameStream(
  stamp: number,
  names: { ordinal: number; name: string }[],
): Uint8Array {
  const out = new ByteWriter();
  out.ascii("BSIN");
  out.u8(1);
  out.u8(0);
  out.u16(stamp);
  for (const { ordinal, name } of names) {
    const text = name.slice(0, 31);
    out.u16(ordinal);
    out.u8(text.length);
    out.ascii(text);
  }
  out.u16(0);
  out.u16(crc16(out.toBytes()));
  return out.toBytes();
}

export function readNameStream(bytes: Uint8Array) {
  const r = new ByteReader(bytes, "name stream");
  if (r.ascii(4) !== "BSIN") throw new ObjectError("L-FORMAT", "bad magic");
  if (r.u8() !== 1 || r.u8() > 0) throw new ObjectError("L-FORMAT", "version");
  const stamp = r.u16();
  const names = new Map<number, string>();
  while (true) {
    const ordinal = r.u16();
    if (ordinal === 0) break;
    names.set(ordinal, r.ascii(r.u8()));
  }
  const end = r.position;
  if (r.u16() !== crc16(bytes.subarray(0, end))) {
    throw new ObjectError("L-TRUNCATED", "name stream CRC mismatch");
  }
  return { stamp, names };
}
