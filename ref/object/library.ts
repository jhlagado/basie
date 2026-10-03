/** The blob library file (object format §7). */
import {
  ByteReader,
  ByteWriter,
  readRecords,
  RecordWriter,
  writeTrailer,
} from "./directory.ts";
import { crc16 } from "./crc.ts";
import {
  type DirectoryRecord,
  LIBRARY_FIRST,
  ObjectError,
  type Trailer,
} from "./types.ts";

export type Profile = {
  targetClass: number;
  outputKinds: number;
  imageBase: number;
  imageLimit: number;
  nominalTop: number;
  ccpSize: number;
  ramBase: number;
  ramLimit: number;
  guardBand: number;
  optionSupport: number;
  freeRestartVectors: number;
  debuggerMargin: number;
  fileEntrySize: number;
};

export type Library = {
  runtimeIdentity: number;
  helperVersion: number;
  profileIdentity: number;
  profile: Profile;
  records: DirectoryRecord[];
  trailer: Trailer;
  bytes: Uint8Array;
  keys: number[];
  names?: Uint8Array;
};

const PROFILE_FIELDS: (keyof Profile)[] = [
  "targetClass",
  "outputKinds",
  "imageBase",
  "imageLimit",
  "nominalTop",
  "ccpSize",
  "ramBase",
  "ramLimit",
  "guardBand",
  "optionSupport",
  "freeRestartVectors",
  "debuggerMargin",
  "fileEntrySize",
];
const BYTE_FIELDS = new Set<keyof Profile>([
  "targetClass",
  "outputKinds",
  "optionSupport",
  "freeRestartVectors",
]);

function pad128(out: ByteWriter) {
  while (out.length % 128 !== 0) out.u8(0);
}

/** Encode a blob library file. */
export function writeLibrary(lib: Omit<Library, "trailer">): Uint8Array {
  const out = new ByteWriter();
  // Header placeholder: 40 bytes, filled in once offsets are known.
  for (let i = 0; i < 40; i += 1) out.u8(0);
  const profile = new ByteWriter();
  for (const field of PROFILE_FIELDS) {
    if (BYTE_FIELDS.has(field)) profile.u8(lib.profile[field]);
    else profile.u16(lib.profile[field]);
  }
  out.u16(profile.length);
  out.raw(profile.toBytes());
  pad128(out);
  const directoryOffset = out.length;
  const writer = new RecordWriter(out, LIBRARY_FIRST);
  for (const r of lib.records) writer.write(r);
  writeTrailer(out, {
    blobCount: writer.blobCount,
    byteStreamLength: lib.bytes.length,
    highestOrdinal: writer.highestOrdinal,
  }, directoryOffset);
  pad128(out);
  const byteOffset = out.length;
  out.raw(lib.bytes);
  pad128(out);
  const keyOffset = out.length;
  out.u16(lib.keys.length);
  for (const k of lib.keys) out.u16(k);
  let nameOffset = 0;
  if (lib.names) {
    pad128(out);
    nameOffset = out.length;
    out.raw(lib.names);
  }
  const fileLength = out.length + 2;
  const bytes = out.toBytes();
  const header = new ByteWriter();
  header.ascii("BTNR");
  header.u8(1);
  header.u8(0);
  header.u16(lib.runtimeIdentity);
  header.u16(lib.helperVersion);
  header.u16(lib.profileIdentity);
  header.u32(directoryOffset);
  header.u32(byteOffset);
  header.u32(lib.bytes.length);
  header.u32(nameOffset);
  header.u32(fileLength);
  header.u32(keyOffset);
  header.u16(writer.highestOrdinal);
  header.u16(0);
  bytes.set(header.toBytes(), 0);
  const final = new Uint8Array(fileLength);
  final.set(bytes);
  const crc = crc16(bytes);
  final[fileLength - 2] = crc & 0xff;
  final[fileLength - 1] = crc >> 8;
  return final;
}

/** Decode and check a blob library file. */
export function readLibrary(file: Uint8Array, verify = false): Library {
  const h = new ByteReader(file, "library header");
  if (h.ascii(4) !== "BTNR") throw new ObjectError("L-FORMAT", "bad magic");
  if (h.u8() !== 1 || h.u8() > 0) throw new ObjectError("L-FORMAT", "version");
  const runtimeIdentity = h.u16();
  const helperVersion = h.u16();
  const profileIdentity = h.u16();
  const directoryOffset = h.u32();
  const byteOffset = h.u32();
  const byteLength = h.u32();
  const nameOffset = h.u32();
  const fileLength = h.u32();
  const keyOffset = h.u32();
  const highest = h.u16();
  h.u16();
  const profileLength = h.u16();
  const profile = {} as Profile;
  const p = new ByteReader(
    file.subarray(h.position, h.position + profileLength),
    "profile block",
  );
  for (const field of PROFILE_FIELDS) {
    if (p.done) {
      profile[field] = 0;
      continue;
    }
    profile[field] = BYTE_FIELDS.has(field) ? p.u8() : p.u16();
  }
  const d = new ByteReader(file, "library directory");
  d.position = directoryOffset;
  const { records, trailer } = readRecords(d, LIBRARY_FIRST, directoryOffset);
  if (trailer.byteStreamLength !== byteLength) {
    throw new ObjectError("L-TRUNCATED", "byte section length disagrees");
  }
  if (trailer.highestOrdinal !== highest) {
    throw new ObjectError("L-TRUNCATED", "highest ordinal disagrees");
  }
  const k = new ByteReader(file, "key table");
  k.position = keyOffset;
  const keys: number[] = [];
  for (let i = k.u16(); i > 0; i -= 1) keys.push(k.u16());
  if (verify) {
    const stored = file[fileLength - 2] | (file[fileLength - 1] << 8);
    if (crc16(file.subarray(0, fileLength - 2)) !== stored) {
      throw new ObjectError("L-TRUNCATED", "library CRC mismatch");
    }
  }
  return {
    runtimeIdentity,
    helperVersion,
    profileIdentity,
    profile,
    records,
    trailer,
    bytes: file.subarray(byteOffset, byteOffset + byteLength),
    keys,
    names: nameOffset
      ? file.subarray(
        nameOffset,
        keyOffset > nameOffset ? keyOffset : fileLength - 2,
      )
      : undefined,
  };
}
