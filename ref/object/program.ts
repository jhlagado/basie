/** The program object: directory stream and byte stream (object format §4). */
import {
  ByteReader,
  ByteWriter,
  readRecords,
  RecordWriter,
  writeTrailer,
} from "./directory.ts";
import {
  type DirectoryRecord,
  ObjectError,
  PROGRAM_FIRST,
  type ProgramDirectory,
  type ProgramHeader,
} from "./types.ts";

export function defaultHeader(
  over: Partial<ProgramHeader> = {},
): ProgramHeader {
  return {
    major: 1,
    minor: 0,
    stamp: 1,
    runtimeIdentity: 1,
    helperVersion: 1,
    helperKey: 0,
    profileIdentity: 1,
    ordinalBase: PROGRAM_FIRST,
    flags: 0,
    ...over,
  };
}

/** Encode a program directory stream. */
export function writeProgramDirectory(
  header: ProgramHeader,
  records: DirectoryRecord[],
  byteStreamLength: number,
): Uint8Array {
  const out = new ByteWriter();
  out.ascii("BSQP");
  out.u8(header.major);
  out.u8(header.minor);
  out.u16(header.stamp);
  out.u16(header.runtimeIdentity);
  out.u16(header.helperVersion);
  out.u16(header.helperKey);
  out.u16(header.profileIdentity);
  out.u16(header.ordinalBase);
  out.u8(header.flags);
  out.u8(0);
  const writer = new RecordWriter(out, header.ordinalBase);
  for (const r of records) writer.write(r);
  writeTrailer(out, {
    blobCount: writer.blobCount,
    byteStreamLength,
    highestOrdinal: writer.highestOrdinal,
  });
  return out.toBytes();
}

/** Decode and check a program directory stream. */
export function readProgramDirectory(bytes: Uint8Array): ProgramDirectory {
  const r = new ByteReader(bytes, "program directory");
  if (r.ascii(4) !== "BSQP") throw new ObjectError("L-FORMAT", "bad magic");
  const header: ProgramHeader = {
    major: r.u8(),
    minor: r.u8(),
    stamp: r.u16(),
    runtimeIdentity: r.u16(),
    helperVersion: r.u16(),
    helperKey: r.u16(),
    profileIdentity: r.u16(),
    ordinalBase: r.u16(),
    flags: r.u8(),
  };
  r.u8();
  if (header.major !== 1 || header.minor > 0) {
    throw new ObjectError(
      "L-FORMAT",
      `version ${header.major}.${header.minor}`,
    );
  }
  const { records, trailer } = readRecords(r, header.ordinalBase, 0);
  return { header, records, trailer };
}

/** Encode a byte stream: header, then the stored bytes of the blobs. */
export function writeByteStream(stamp: number, data: Uint8Array): Uint8Array {
  const out = new ByteWriter();
  out.ascii("BSQB");
  out.u8(1);
  out.u8(0);
  out.u16(stamp);
  out.raw(data);
  return out.toBytes();
}

/** Decode a byte stream; returns its stamp and the blob bytes. */
export function readByteStream(bytes: Uint8Array) {
  const r = new ByteReader(bytes, "byte stream");
  if (r.ascii(4) !== "BSQB") throw new ObjectError("L-FORMAT", "bad magic");
  if (r.u8() !== 1 || r.u8() > 0) throw new ObjectError("L-FORMAT", "version");
  const stamp = r.u16();
  return { stamp, data: bytes.subarray(8) };
}
