/** In-memory forms of the Basie object format (docs/object-format.md). */

export const Kind = {
  code: 0,
  rodata: 1,
  data: 2,
  bss: 3,
  startup: 4,
} as const;
export type KindCode = (typeof Kind)[keyof typeof Kind];

export const Form = {
  ABS16: 0,
  LO8: 1,
  HI8: 2,
  SIZE16: 3,
  BANK8: 4,
} as const;
export type FormCode = (typeof Form)[keyof typeof Form];

/** Ordinal ranges (object format §3.2). */
export const LIBRARY_FIRST = 0x0001;
export const LIBRARY_LAST = 0x03ff;
export const PROGRAM_FIRST = 0x0400;
export const PROGRAM_LAST = 0xffdf;
export const PSEUDO_FIRST = 0xffe0;

/** Pseudo-object ordinals (object format §3.4). */
export const Pseudo = {
  MAIN: 0xffe0,
  IMAGE: 0xffe1,
  BSS: 0xffe2,
  FREE: 0xffe3,
  REQUIRED: 0xffe4,
  DATA: 0xffe5,
  DATACOPY: 0xffe6,
  OPTIONS: 0xffe7,
  FILES: 0xffe8,
  FILECOUNT: 0xffe9,
} as const;
export const PSEUDO_LAST_DEFINED = 0xffe9;

export type Reference = {
  offset: number;
  form: FormCode;
  target: number;
  addend: number; // 0..65535; negative offsets as two's complement
};

export type BlobRecord = {
  type: "blob";
  kind: KindCode;
  ordinal: number;
  size: number;
  root: boolean;
  /** Alignment code 0..7: 2**code bytes for 0..6, 256 bytes for 7. */
  align: number;
  references: Reference[];
};

export type AliasRecord = {
  type: "alias";
  alias: number;
  base: number;
  offset: number;
};
export type EntryRecord = { type: "entry"; ordinal: number };
export type BankRecord = { type: "bank"; bank: number };
export type LimitsRecord = {
  type: "limits";
  stackReserve: number;
  largestFrame: number;
  flags: number;
};

export type DirectoryRecord =
  | BlobRecord
  | AliasRecord
  | EntryRecord
  | BankRecord
  | LimitsRecord;

export type ProgramHeader = {
  major: number;
  minor: number;
  stamp: number;
  runtimeIdentity: number;
  helperVersion: number;
  helperKey: number;
  profileIdentity: number;
  ordinalBase: number;
  flags: number;
};

export type Trailer = {
  blobCount: number;
  byteStreamLength: number;
  highestOrdinal: number;
};

export type ProgramDirectory = {
  header: ProgramHeader;
  records: DirectoryRecord[];
  trailer: Trailer;
};

/** Bytes of alignment for an alignment code. */
export function alignmentBytes(code: number): number {
  return code === 7 ? 256 : 1 << code;
}

/** A diagnostic raised while reading an object file. */
export class ObjectError extends Error {
  constructor(public readonly code: string, message: string) {
    super(`${code}: ${message}`);
  }
}
