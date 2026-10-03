/**
 * Encoding and decoding of directory records, shared by program directories
 * and library directory sections (object format §4.2, §5.2, §6).
 */
import {
  type BlobRecord,
  type DirectoryRecord,
  type FormCode,
  ObjectError,
  type Reference,
  type Trailer,
} from "./types.ts";
import { crc16 } from "./crc.ts";

/** A growable little-endian byte buffer. */
export class ByteWriter {
  private bytes: number[] = [];
  u8(value: number) {
    if (value < 0 || value > 0xff) throw new RangeError(`u8 ${value}`);
    this.bytes.push(value);
  }
  u16(value: number) {
    if (value < 0 || value > 0xffff) throw new RangeError(`u16 ${value}`);
    this.bytes.push(value & 0xff, value >> 8);
  }
  u32(value: number) {
    this.u16(value & 0xffff);
    this.u16(Math.floor(value / 0x10000) & 0xffff);
  }
  raw(data: ArrayLike<number>) {
    for (let i = 0; i < data.length; i += 1) this.bytes.push(data[i]);
  }
  ascii(text: string) {
    for (const ch of text) this.bytes.push(ch.charCodeAt(0));
  }
  get length() {
    return this.bytes.length;
  }
  toBytes() {
    return Uint8Array.from(this.bytes);
  }
}

/** A cursor over a byte array that reports truncation as an ObjectError. */
export class ByteReader {
  position = 0;
  constructor(readonly bytes: Uint8Array, readonly what: string) {}
  private need(count: number) {
    if (this.position + count > this.bytes.length) {
      throw new ObjectError("L-TRUNCATED", `${this.what} ends early`);
    }
  }
  u8(): number {
    this.need(1);
    return this.bytes[this.position++];
  }
  u16(): number {
    this.need(2);
    const v = this.bytes[this.position] | (this.bytes[this.position + 1] << 8);
    this.position += 2;
    return v;
  }
  u32(): number {
    const lo = this.u16();
    return lo + this.u16() * 0x10000;
  }
  ascii(count: number): string {
    this.need(count);
    const text = String.fromCharCode(
      ...this.bytes.subarray(this.position, this.position + count),
    );
    this.position += count;
    return text;
  }
  peek(): number {
    this.need(1);
    return this.bytes[this.position];
  }
  get done() {
    return this.position >= this.bytes.length;
  }
}

/** Write directory records, tracking the implicit ordinal sequence. */
export class RecordWriter {
  private previous: number | undefined;
  blobCount = 0;
  highestOrdinal = 0;
  constructor(readonly out: ByteWriter, readonly ordinalBase: number) {}

  write(record: DirectoryRecord) {
    switch (record.type) {
      case "blob":
        return this.blob(record);
      case "alias":
        this.out.u8(0x06 | (0 << 3));
        this.out.u16(record.alias);
        this.out.u16(record.base);
        this.out.u16(record.offset);
        this.note(record.alias);
        return;
      case "entry":
        this.out.u8(0x06 | (1 << 3));
        this.out.u16(record.ordinal);
        return;
      case "bank":
        this.out.u8(0x06 | (2 << 3));
        this.out.u8(record.bank);
        return;
      case "limits":
        this.out.u8(0x06 | (3 << 3));
        this.out.u16(record.stackReserve);
        this.out.u16(record.largestFrame);
        this.out.u8(record.flags);
        return;
    }
  }

  private note(ordinal: number) {
    if (ordinal > this.highestOrdinal) this.highestOrdinal = ordinal;
  }

  private blob(b: BlobRecord) {
    const implicit = this.previous === undefined
      ? this.ordinalBase
      : this.previous + 1;
    const explicit = b.ordinal !== implicit;
    if (b.kind > 4) throw new RangeError(`kind ${b.kind}`);
    if (b.align < 0 || b.align > 7) throw new RangeError(`align ${b.align}`);
    this.out.u8(
      b.kind | (explicit ? 0x08 : 0) | (b.root ? 0x10 : 0) | (b.align << 5),
    );
    if (explicit) this.out.u16(b.ordinal);
    this.out.u16(b.size);
    const count = b.references.length;
    if (count < 255) this.out.u8(count);
    else {
      this.out.u8(255);
      this.out.u16(count);
    }
    writeReferences(this.out, b.references);
    this.previous = b.ordinal;
    this.blobCount += 1;
    this.note(b.ordinal);
  }
}

function writeReferences(out: ByteWriter, refs: Reference[]) {
  let previous: number | undefined;
  for (const r of refs) {
    const delta = previous === undefined ? r.offset : r.offset - previous;
    if (previous !== undefined && delta < 1) {
      throw new RangeError("reference offsets must increase");
    }
    const escape = delta > 62;
    const control = (escape ? 63 : delta) |
      (r.addend !== 0 ? 0x40 : 0) | (r.form !== 0 ? 0x80 : 0);
    out.u8(control);
    if (escape) out.u16(r.offset);
    if (r.form !== 0) out.u8(r.form);
    out.u16(r.target);
    if (r.addend !== 0) out.u16(r.addend & 0xffff);
    previous = r.offset;
  }
}

/** Write a directory trailer, with its CRC over everything before it. */
export function writeTrailer(out: ByteWriter, t: Trailer, crcFrom = 0) {
  out.u8(0xff);
  out.u16(t.blobCount);
  out.u32(t.byteStreamLength);
  out.u16(t.highestOrdinal);
  out.u8(0);
  const bytes = out.toBytes();
  out.u16(crc16(bytes.subarray(crcFrom)));
}

/** Read records until the trailer marker; return the records and trailer. */
export function readRecords(
  reader: ByteReader,
  ordinalBase: number,
  crcFrom: number,
): { records: DirectoryRecord[]; trailer: Trailer } {
  const records: DirectoryRecord[] = [];
  let previous: number | undefined;
  while (true) {
    const header = reader.u8();
    if (header === 0xff) break;
    const kind = header & 0x07;
    if (kind === 6) {
      records.push(readControl(reader, header >> 3));
      continue;
    }
    if (kind > 4) {
      throw new ObjectError(
        "L-RESERVED",
        `kind ${kind} at ${reader.position - 1}`,
      );
    }
    const ordinal = header & 0x08
      ? reader.u16()
      : previous === undefined
      ? ordinalBase
      : previous + 1;
    const size = reader.u16();
    let count = reader.u8();
    if (count === 255) {
      count = reader.u16();
      if (count < 255) {
        throw new ObjectError("L-BLOB", `reference count escape below 255`);
      }
    }
    const references: Reference[] = [];
    let last: number | undefined;
    for (let i = 0; i < count; i += 1) {
      const control = reader.u8();
      const deltaField = control & 0x3f;
      let offset: number;
      if (deltaField === 63) {
        offset = reader.u16();
        if (last !== undefined && offset <= last) {
          throw new ObjectError("L-REFERENCE", "offsets not increasing");
        }
      } else {
        if (last !== undefined && deltaField === 0) {
          throw new ObjectError("L-REFERENCE", "zero offset delta");
        }
        offset = last === undefined ? deltaField : last + deltaField;
      }
      let form = 0;
      if (control & 0x80) {
        form = reader.u8();
        if (form === 0) throw new ObjectError("L-RESERVED", "form byte 0");
      }
      const target = reader.u16();
      const addend = control & 0x40 ? reader.u16() : 0;
      references.push({ offset, form: form as FormCode, target, addend });
      last = offset;
    }
    records.push({
      type: "blob",
      kind: kind as BlobRecord["kind"],
      ordinal,
      size,
      root: (header & 0x10) !== 0,
      align: header >> 5,
      references,
    });
    previous = ordinal;
  }
  const blobCount = reader.u16();
  const byteStreamLength = reader.u32();
  const highestOrdinal = reader.u16();
  reader.u8();
  const crcEnd = reader.position;
  const stored = reader.u16();
  const actual = crc16(reader.bytes.subarray(crcFrom, crcEnd));
  if (stored !== actual) throw new ObjectError("L-TRUNCATED", "CRC mismatch");
  const counted = records.filter((r) => r.type === "blob").length;
  if (counted !== blobCount) {
    throw new ObjectError("L-TRUNCATED", "blob count mismatch");
  }
  return { records, trailer: { blobCount, byteStreamLength, highestOrdinal } };
}

function readControl(reader: ByteReader, subtype: number): DirectoryRecord {
  switch (subtype) {
    case 0:
      return {
        type: "alias",
        alias: reader.u16(),
        base: reader.u16(),
        offset: reader.u16(),
      };
    case 1:
      return { type: "entry", ordinal: reader.u16() };
    case 2:
      return { type: "bank", bank: reader.u8() };
    case 3:
      return {
        type: "limits",
        stackReserve: reader.u16(),
        largestFrame: reader.u16(),
        flags: reader.u8(),
      };
    default:
      throw new ObjectError("L-RESERVED", `control subtype ${subtype}`);
  }
}
