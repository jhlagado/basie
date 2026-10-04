/**
 * The reference linker (docs/linker.md): Phases A to D, producing the program
 * image, its addresses and the line table. Every check the linker
 * specification lists is reported as a LinkError with its diagnostic code.
 */
import { crc16 } from "../object/crc.ts";
import type { Library } from "../object/library.ts";
import type { BlobLines } from "../object/streams.ts";
import {
  alignmentBytes,
  type BlobRecord,
  Form,
  Kind,
  LIBRARY_FIRST,
  LIBRARY_LAST,
  PROGRAM_FIRST,
  PROGRAM_LAST,
  type ProgramDirectory,
  Pseudo,
  PSEUDO_FIRST,
  PSEUDO_LAST_DEFINED,
  type Reference,
} from "../object/types.ts";

export class LinkError extends Error {
  constructor(public readonly code: string, message: string) {
    super(`${code}: ${message}`);
  }
}

export type LinkOptions = {
  /** File-table entries (F=n); default 4. */
  files?: number;
  /** Re-runnable image (R). */
  rerunnable?: boolean;
  /** Keep the CCP resident (B). */
  keepCcp?: boolean;
  /** Option V: check that placeholder bytes are zero (L-PLACEHOLDER). */
  verify?: boolean;
  /** Minimum stack (STACK=n). */
  stack?: number;
  /** Output kind; default ".COM". */
  output?: "com" | "bin" | "hex";
  /** The program's byte-stream stamp, checked against the directory's. */
  byteStreamStamp?: number;
  /** Line stream, if one was written. */
  lines?: { stamp: number; parts: string[]; blobs: BlobLines[] };
};

type Owner = "library" | "program";

type Entry = {
  ordinal: number;
  owner: Owner;
  kind: number; // blob kind, or -1 for an alias
  size: number;
  align: number;
  root: boolean;
  defined: boolean;
  referenced: boolean;
  live: boolean;
  edges: number[];
  record?: BlobRecord;
  /** Offset of the blob's bytes in its owner's byte stream. */
  streamOffset: number;
  /** Directory position, for placement order. */
  sequence: number;
  aliasBase?: number;
  aliasOffset?: number;
  address: number;
};

export type LinkResult = {
  /** The output file's bytes (padded as the output kind requires). */
  output: Uint8Array;
  /** The stored image, without padding. */
  image: Uint8Array;
  imageBase: number;
  addresses: Map<number, number>;
  live: Set<number>;
  removed: number[];
  pseudo: Map<number, { address: number; size: number }>;
  lineTable?: Uint8Array;
  /** Every blob, live or removed, for the map. */
  blobs: BlobInfo[];
  stackReserve: number;
  largestFrame: number;
  recursive: boolean;
  /** Warnings such as L-FIT-NOMINAL; the link still succeeded. */
  warnings: string[];
};

export type BlobInfo = {
  ordinal: number;
  owner: "library" | "program";
  kind: number;
  size: number;
  align: number;
  live: boolean;
  address?: number;
  /** Padding inserted before this blob. */
  padding: number;
};

const WIDTH: Record<number, number> = {
  [Form.ABS16]: 2,
  [Form.LO8]: 1,
  [Form.HI8]: 1,
  [Form.SIZE16]: 2,
  [Form.BANK8]: 1,
};

/** Link one program with one blob library. */
export function link(
  library: Library,
  program: ProgramDirectory,
  programBytes: Uint8Array,
  options: LinkOptions = {},
): LinkResult {
  const profile = library.profile;
  const fileCount = options.files ?? 4;
  if (fileCount < 1 || fileCount > 255) {
    throw new LinkError("L-OPTION", `F=${fileCount} is outside 1 to 255`);
  }

  // ---- Phase A: read the directories and check them ----------------------
  checkCompatibility(library, program, options);
  const table = new Map<number, Entry>();
  let entryOrdinal: number | undefined;
  let limits:
    | { stackReserve: number; largestFrame: number; flags: number }
    | undefined;
  let sequence = 0;

  readDirectory("library", library.records, library.bytes.length);
  readDirectory("program", program.records, programBytes.length);

  if (entryOrdinal === undefined) {
    throw new LinkError("L-ENTRY", "the program has no ENTRY record");
  }
  const entryRecord = table.get(entryOrdinal);
  if (
    !entryRecord || entryRecord.owner !== "program" ||
    entryRecord.kind !== Kind.code
  ) {
    throw new LinkError(
      "L-ENTRY",
      "ENTRY must name a code blob in the program",
    );
  }
  if (!limits) throw new LinkError("L-LIMITS", "the program has no LIMITS");

  const startups = [...table.values()].filter((e) => e.kind === Kind.startup);
  if (startups.length !== 1) {
    throw new LinkError(
      "L-STARTUP",
      "the library needs exactly one startup blob",
    );
  }
  const startup = startups[0];
  const firstLibrary = library.records[0];
  if (
    !firstLibrary || firstLibrary.type !== "blob" ||
    firstLibrary.kind !== Kind.startup
  ) {
    throw new LinkError(
      "L-STARTUP",
      "startup must be the library's first record",
    );
  }
  if (!startup.edges.includes(Pseudo.MAIN)) {
    throw new LinkError("L-STARTUP", "startup does not reference MAIN");
  }
  for (const e of table.values()) {
    if (e.referenced && !e.defined) {
      throw new LinkError(
        "L-UNDEFINED",
        `ordinal $${hex4(e.ordinal)} is referenced but never defined`,
      );
    }
    if (e.kind === -1) {
      const base = table.get(e.aliasBase!);
      if (
        !base || !base.defined || base.kind === -1 || base.owner !== e.owner
      ) {
        throw new LinkError(
          "L-ALIAS",
          `alias $${hex4(e.ordinal)} has a bad base`,
        );
      }
      if (e.aliasOffset! >= base.size) {
        throw new LinkError(
          "L-ALIAS",
          `alias $${hex4(e.ordinal)} is outside its base`,
        );
      }
    }
  }

  // ---- Phase B: mark ------------------------------------------------------
  const stack: number[] = [];
  const presentClasses = new Set<number>();
  const mark = (ordinal: number) => {
    const e = table.get(ordinal)!;
    if (!e.live) {
      e.live = true;
      presentClasses.add(e.align);
      stack.push(ordinal);
    }
  };
  for (const e of table.values()) if (e.root && e.kind >= 0) mark(e.ordinal);
  let usesFiles = false;
  while (stack.length > 0) {
    const e = table.get(stack.pop()!)!;
    for (let target of e.edges) {
      if (target === Pseudo.FILES || target === Pseudo.FILECOUNT) {
        usesFiles = true;
      }
      if (target === Pseudo.MAIN) target = entryOrdinal;
      else if (target >= PSEUDO_FIRST) continue;
      const t = table.get(target)!;
      mark(t.kind === -1 ? t.aliasBase! : target);
    }
  }

  // ---- Phase C: place -------------------------------------------------------
  const separateData = !!options.rerunnable || profile.targetClass >= 3;
  const blobs = [...table.values()].filter((e) => e.kind >= 0);
  const order = (a: Entry, b: Entry) =>
    (b.align - a.align) ||
    (a.owner === b.owner ? 0 : a.owner === "library" ? -1 : 1) ||
    (a.sequence - b.sequence);
  const inSection = (e: Entry, section: string) => {
    if (!e.live) return false;
    switch (section) {
      case "START":
        return e.kind === Kind.startup;
      case "TEXT":
        return e.kind === Kind.code || e.kind === Kind.rodata ||
          (e.kind === Kind.data && !separateData);
      case "DATA":
        return e.kind === Kind.data && separateData;
      case "BSS":
        return e.kind === Kind.bss;
    }
    return false;
  };
  const sectionBlobs = (section: string) =>
    blobs.filter((e) => inSection(e, section)).sort(order);

  let cursor = profile.imageBase;
  const padding = new Map<number, number>();
  const place = (section: string): { start: number; end: number } => {
    const list = sectionBlobs(section);
    // A section starts aligned to its largest alignment, so that offsets
    // within it are aligned absolutely.
    const largest = list.reduce(
      (m, e) => Math.max(m, alignmentBytes(e.align)),
      1,
    );
    let previous = cursor;
    cursor = roundUp(cursor, largest);
    const start = cursor;
    for (const e of list) {
      const aligned = roundUp(cursor, alignmentBytes(e.align));
      // The first blob's padding includes rounding the section base.
      padding.set(e.ordinal, aligned - previous);
      previous = aligned + e.size;
      cursor = aligned;
      e.address = cursor;
      cursor += e.size;
    }
    return { start, end: cursor };
  };
  const rom = profile.targetClass >= 3;
  const startSection = place("START");
  place("TEXT");
  // On ROM, DATA and BSS go into RAM and only COPY is stored (§6.1).
  const romCursor = cursor;
  if (rom) cursor = profile.ramBase;
  const data = place("DATA");
  let copy = { start: data.end, end: data.end };
  if (separateData && data.end > data.start) {
    const at = rom ? romCursor : data.end;
    copy = { start: at, end: at + (data.end - data.start) };
  }
  const imageEnd = rom
    ? copy.end > copy.start ? copy.end : romCursor
    : Math.max(cursor, copy.end);
  if (!rom) cursor = imageEnd;
  const bss = place("BSS");
  let filesAddress = cursor;
  let filesSize = 0;
  if (usesFiles) {
    filesAddress = cursor;
    filesSize = fileCount * profile.fileEntrySize;
    cursor += filesSize;
  }
  const free = cursor;
  for (const e of table.values()) {
    if (e.kind === -1 && table.get(e.aliasBase!)!.live) {
      const base = table.get(e.aliasBase!)!;
      e.address = base.address + e.aliasOffset!;
      e.size = base.size - e.aliasOffset!;
    }
  }
  const reserve = Math.max(limits.stackReserve, options.stack ?? 0);
  const optionsWord = (options.keepCcp ? 1 : 0) |
    (separateData && options.rerunnable ? 2 : 0) |
    (options.lines ? 4 : 0);
  const pseudo = new Map<number, { address: number; size: number }>([
    [Pseudo.MAIN, { address: entryRecord.address, size: entryRecord.size }],
    [Pseudo.IMAGE, {
      address: profile.imageBase,
      size: imageEnd - profile.imageBase,
    }],
    [Pseudo.BSS, {
      address: bss.start,
      size: (bss.end - bss.start) + filesSize,
    }],
    [Pseudo.FREE, { address: free, size: 0 }],
    [Pseudo.REQUIRED, { address: free + reserve, size: reserve }],
    [Pseudo.DATA, { address: data.start, size: data.end - data.start }],
    [Pseudo.DATACOPY, {
      address: copy.end > copy.start ? copy.start : data.start,
      size: copy.end - copy.start,
    }],
    [Pseudo.OPTIONS, { address: optionsWord, size: 0 }],
    [Pseudo.FILES, { address: filesAddress, size: filesSize }],
    [Pseudo.FILECOUNT, { address: usesFiles ? fileCount : 0, size: 0 }],
  ]);
  if (startSection.start !== profile.imageBase) {
    throw new LinkError("L-STARTUP", "startup is not at the image base");
  }
  if (imageEnd > profile.imageLimit) {
    throw new LinkError(
      "L-FIT-IMAGE",
      `the image ends at $${hex4(imageEnd)}, beyond the limit $${
        hex4(profile.imageLimit)
      }`,
    );
  }
  if (free + reserve > 0x10000) {
    throw new LinkError(
      "L-FIT-MEMORY",
      "BSS and the stack exceed the address space",
    );
  }
  const warnings: string[] = [];
  if (rom) {
    if (free + reserve > profile.ramLimit) {
      throw new LinkError(
        "L-FIT-RAM",
        `DATA, BSS and the stack end at $${
          hex4(free + reserve)
        }, beyond the RAM limit $${hex4(profile.ramLimit)}`,
      );
    }
  } else {
    const top = options.keepCcp ? profile.imageLimit : profile.nominalTop;
    if (free + reserve > top) {
      warnings.push(
        `L-FIT-NOMINAL: the program needs memory to $${
          hex4(free + reserve)
        }, above the nominal top $${hex4(top)}`,
      );
    }
  }

  // ---- Phase D: write ------------------------------------------------------
  const image = new Uint8Array(imageEnd - profile.imageBase);
  const valueOf = (ref: Reference, owner: Entry): number => {
    const target = ref.target;
    const signed = ref.addend >= 0x8000 ? ref.addend - 0x10000 : ref.addend;
    if (ref.form === Form.SIZE16) {
      const size = target >= PSEUDO_FIRST
        ? pseudo.get(target)!.size
        : table.get(target)!.size;
      return (size + ref.addend) & 0xffff;
    }
    let address: number;
    let size: number;
    let checked = true;
    if (target >= PSEUDO_FIRST) {
      const p = pseudo.get(target)!;
      address = p.address;
      size = p.size;
      checked = target === Pseudo.MAIN;
    } else {
      const t = table.get(target)!;
      address = t.address;
      size = t.size;
    }
    const v = address + signed;
    if (
      v < 0 || v > 0xffff || (checked && (v < address || v > address + size))
    ) {
      throw new LinkError(
        "L-RANGE",
        `reference in $${hex4(owner.ordinal)} to $${hex4(target)}${
          signed >= 0 ? "+" : ""
        }${signed} is out of range`,
      );
    }
    return v & 0xffff;
  };
  const emit = (e: Entry, into: number) => {
    const source = e.owner === "library" ? library.bytes : programBytes;
    const bytes = source.slice(e.streamOffset, e.streamOffset + e.size);
    for (const ref of e.record!.references) {
      if (options.verify) {
        const width = ref.form === Form.ABS16 || ref.form === Form.SIZE16
          ? 2
          : 1;
        for (let i = 0; i < width; i += 1) {
          if (bytes[ref.offset + i] !== 0) {
            throw new LinkError(
              "L-PLACEHOLDER",
              `nonzero placeholder at $${hex4(e.ordinal)}+${ref.offset}`,
            );
          }
        }
      }
      const v = valueOf(ref, e);
      switch (ref.form) {
        case Form.ABS16:
        case Form.SIZE16:
          bytes[ref.offset] = v & 0xff;
          bytes[ref.offset + 1] = v >> 8;
          break;
        case Form.LO8:
          bytes[ref.offset] = v & 0xff;
          break;
        case Form.HI8:
          bytes[ref.offset] = v >> 8;
          break;
      }
    }
    image.set(bytes, into - profile.imageBase);
  };
  for (const section of ["START", "TEXT"]) {
    for (const e of sectionBlobs(section)) emit(e, e.address);
  }
  for (const e of sectionBlobs("DATA")) {
    emit(e, rom ? e.address - data.start + copy.start : e.address);
  }
  if (!rom && copy.end > copy.start) {
    image.copyWithin(
      copy.start - profile.imageBase,
      data.start - profile.imageBase,
      data.end - profile.imageBase,
    );
  }

  const addresses = new Map<number, number>();
  const live = new Set<number>();
  const removed: number[] = [];
  for (const e of table.values()) {
    if (e.kind === -1) {
      if (table.get(e.aliasBase!)!.live) addresses.set(e.ordinal, e.address);
      continue;
    }
    if (e.live) {
      live.add(e.ordinal);
      addresses.set(e.ordinal, e.address);
    } else removed.push(e.ordinal);
  }
  const output = makeOutput(image, profile.imageBase, options.output ?? "com");
  const lineTable = options.lines
    ? buildLineTable(options.lines, output, table, sectionBlobs)
    : undefined;
  const blobInfo: BlobInfo[] = blobs.map((e) => ({
    ordinal: e.ordinal,
    owner: e.owner,
    kind: e.kind,
    size: e.size,
    align: e.align,
    live: e.live,
    address: e.live ? e.address : undefined,
    padding: padding.get(e.ordinal) ?? 0,
  }));
  return {
    output,
    image,
    imageBase: profile.imageBase,
    addresses,
    live,
    removed,
    pseudo,
    lineTable,
    blobs: blobInfo,
    stackReserve: reserve,
    largestFrame: limits.largestFrame,
    recursive: (limits.flags & 1) !== 0,
    warnings,
  };

  // ---- Phase A helpers ------------------------------------------------------
  function entryFor(ordinal: number, owner: Owner): Entry {
    let e = table.get(ordinal);
    if (!e) {
      e = {
        ordinal,
        owner,
        kind: -2,
        size: 0,
        align: 0,
        root: false,
        defined: false,
        referenced: false,
        live: false,
        edges: [],
        streamOffset: 0,
        sequence: -1,
        address: 0,
      };
      table.set(ordinal, e);
    }
    return e;
  }

  function readDirectory(
    owner: Owner,
    records: typeof program.records,
    streamLength: number,
  ) {
    const [first, last] = owner === "library"
      ? [LIBRARY_FIRST, LIBRARY_LAST]
      : [PROGRAM_FIRST, PROGRAM_LAST];
    let streamOffset = 0;
    let sawLimits = false;
    let blobsAfterLimits = false;
    for (const r of records) {
      if (r.type === "bank") {
        throw new LinkError("L-RESERVED", "BANK records are reserved in 1.0");
      }
      if (r.type === "entry") {
        if (owner === "library") {
          throw new LinkError("L-ENTRY", "ENTRY in the library");
        }
        if (entryOrdinal !== undefined) {
          throw new LinkError("L-ENTRY", "more than one ENTRY record");
        }
        entryOrdinal = r.ordinal;
        continue;
      }
      if (r.type === "limits") {
        if (owner === "library" || sawLimits) {
          throw new LinkError(
            "L-LIMITS",
            "LIMITS must appear once, in the program",
          );
        }
        sawLimits = true;
        limits = r;
        continue;
      }
      if (r.type === "alias") {
        if (r.alias < first || r.alias > last) {
          throw new LinkError(
            "L-ALIAS",
            `alias $${hex4(r.alias)} outside its range`,
          );
        }
        const e = entryFor(r.alias, owner);
        if (e.defined) {
          throw new LinkError(
            "L-ORDINAL",
            `ordinal $${hex4(r.alias)} defined twice`,
          );
        }
        Object.assign(e, {
          owner,
          kind: -1,
          defined: true,
          aliasBase: r.base,
          aliasOffset: r.offset,
          sequence: sequence++,
        });
        entryFor(r.base, owner).referenced = true;
        continue;
      }
      // Blob record.
      if (sawLimits) blobsAfterLimits = true;
      if (r.ordinal < first || r.ordinal > last) {
        throw new LinkError(
          "L-ORDINAL",
          `ordinal $${hex4(r.ordinal)} outside its range`,
        );
      }
      if (r.size === 0) throw new LinkError("L-BLOB", "a blob of size 0");
      if ((r.kind === Kind.code || r.kind === Kind.startup) && r.align !== 0) {
        throw new LinkError(
          "L-BLOB",
          "code and startup blobs can't be aligned",
        );
      }
      if (r.kind === Kind.bss && r.references.length > 0) {
        throw new LinkError("L-BLOB", "a bss blob has references");
      }
      if (r.kind === Kind.startup && owner === "program") {
        throw new LinkError("L-BLOB", "a startup blob in the program");
      }
      const e = entryFor(r.ordinal, owner);
      if (e.defined) {
        throw new LinkError(
          "L-ORDINAL",
          `ordinal $${hex4(r.ordinal)} defined twice`,
        );
      }
      let end = 0;
      for (const ref of r.references) {
        const width = WIDTH[ref.form];
        if (width === undefined) {
          throw new LinkError("L-RESERVED", `reference form ${ref.form}`);
        }
        if (ref.form === Form.BANK8) {
          throw new LinkError(
            "L-RESERVED",
            "BANK8 references are reserved in 1.0",
          );
        }
        if (ref.offset < end || ref.offset + width > r.size) {
          throw new LinkError(
            "L-REFERENCE",
            `reference at ${ref.offset} overlaps or leaves the blob`,
          );
        }
        end = ref.offset + width;
        checkTarget(owner, ref, first);
      }
      const edges: number[] = [];
      for (const ref of r.references) {
        if (!edges.includes(ref.target)) edges.push(ref.target);
        if (ref.target < PSEUDO_FIRST) {
          entryFor(ref.target, owner).referenced = true;
        }
      }
      Object.assign(e, {
        owner,
        kind: r.kind,
        size: r.size,
        align: r.align,
        root: r.root,
        defined: true,
        edges,
        record: r,
        streamOffset: r.kind === Kind.bss ? 0 : streamOffset,
        sequence,
      });
      sequence += 1;
      if (r.kind !== Kind.bss) streamOffset += r.size;
    }
    if (blobsAfterLimits) {
      throw new LinkError(
        "L-LIMITS",
        "LIMITS must follow the last blob record",
      );
    }
    if (streamOffset !== streamLength) {
      throw new LinkError(
        "L-TRUNCATED",
        `${owner} byte stream is ${streamLength} bytes, records need ${streamOffset}`,
      );
    }
  }

  function checkTarget(owner: Owner, ref: Reference, first: number) {
    const t = ref.target;
    if (
      t === 0 || (t > PSEUDO_LAST_DEFINED && t <= 0xffff && t >= PSEUDO_FIRST)
    ) {
      throw new LinkError(
        "L-REFERENCE",
        `reference to invalid ordinal $${hex4(t)}`,
      );
    }
    if (
      owner === "library" && t < PSEUDO_FIRST &&
      (t >= PROGRAM_FIRST || t > library.trailer.highestOrdinal)
    ) {
      throw new LinkError("L-REFERENCE", `library reference to $${hex4(t)}`);
    }
    if (ref.form === Form.SIZE16 && t < PSEUDO_FIRST) {
      const e = table.get(t);
      if (e && e.kind === -1) {
        throw new LinkError("L-REFERENCE", "SIZE16 of an alias");
      }
    }
    void first;
  }
}

function checkCompatibility(
  library: Library,
  program: ProgramDirectory,
  options: LinkOptions,
) {
  const h = program.header;
  if (h.runtimeIdentity !== library.runtimeIdentity) {
    throw new LinkError("L-COMPAT", "runtime identities differ");
  }
  if (h.profileIdentity !== library.profileIdentity) {
    throw new LinkError("L-COMPAT", "profile identities differ");
  }
  if (library.helperVersion < h.helperVersion) {
    throw new LinkError("L-COMPAT", "the library's helper table is too old");
  }
  const key = library.keys[h.helperVersion - 1];
  if (h.helperKey !== 0 && key !== h.helperKey) {
    throw new LinkError("L-COMPAT", "helper-table key mismatch");
  }
  if (h.stamp === 0) throw new LinkError("L-STAMP", "compilation stamp 0");
  if (
    options.byteStreamStamp !== undefined && options.byteStreamStamp !== h.stamp
  ) {
    throw new LinkError("L-STAMP", "byte stream is from another compilation");
  }
  if (options.lines && options.lines.stamp !== h.stamp) {
    throw new LinkError("L-STAMP", "line stream is from another compilation");
  }
  const support = library.profile.optionSupport;
  if (options.keepCcp && !(support & 1)) {
    throw new LinkError("L-OPTION", "keep-CCP isn't supported by this profile");
  }
  if (options.rerunnable && !(support & 2)) {
    throw new LinkError(
      "L-OPTION",
      "re-runnable isn't supported by this profile",
    );
  }
  const kinds = library.profile.outputKinds;
  const wanted = { com: 1, bin: 2, hex: 4 }[options.output ?? "com"];
  if (!(kinds & wanted)) {
    throw new LinkError(
      "L-OUTPUT",
      `output kind ${options.output} isn't supported`,
    );
  }
}

function makeOutput(image: Uint8Array, base: number, kind: string): Uint8Array {
  if (kind === "hex") return intelHex(image, base);
  if (kind === "com" && base !== 0x100) {
    throw new LinkError("L-OUTPUT", ".COM output needs image base $0100");
  }
  const padded = new Uint8Array(Math.ceil(image.length / 128) * 128);
  padded.set(image);
  return padded;
}

/** Intel HEX, 16 bytes per data record, CR LF lines, padded with $1A. */
export function intelHex(image: Uint8Array, base: number): Uint8Array {
  const lines: string[] = [];
  for (let i = 0; i < image.length; i += 16) {
    const chunk = image.subarray(i, Math.min(i + 16, image.length));
    const address = base + i;
    const fields = [chunk.length, address >> 8, address & 0xff, 0, ...chunk];
    const sum = fields.reduce((a, b) => a + b, 0);
    fields.push((0x100 - (sum & 0xff)) & 0xff);
    lines.push(
      ":" +
        fields.map((b) => b.toString(16).toUpperCase().padStart(2, "0")).join(
          "",
        ),
    );
  }
  lines.push(":00000001FF");
  const text = new TextEncoder().encode(lines.join("\r\n") + "\r\n");
  const padded = new Uint8Array(Math.ceil(text.length / 128) * 128).fill(0x1a);
  padded.set(text);
  return padded;
}

function buildLineTable(
  lines: NonNullable<LinkOptions["lines"]>,
  output: Uint8Array,
  table: Map<number, Entry>,
  sectionBlobs: (s: string) => Entry[],
): Uint8Array {
  const byOrdinal = new Map(lines.blobs.map((b) => [b.ordinal, b]));
  const entries: [number, number, number][] = [];
  for (const section of ["START", "TEXT", "DATA"]) {
    for (const e of sectionBlobs(section)) {
      const own = e.owner === "program" && e.kind === Kind.code
        ? byOrdinal.get(e.ordinal)
        : undefined;
      if (own && own.entries.length > 0 && own.entries[0].offset === 0) {
        for (const l of own.entries) {
          entries.push([e.address + l.offset, l.part, l.source]);
        }
      } else {
        entries.push([e.address, 0xff, e.ordinal]);
        if (own) {
          for (const l of own.entries) {
            entries.push([e.address + l.offset, l.part, l.source]);
          }
        }
      }
    }
  }
  void table;
  const bytes: number[] = [];
  const ascii = (t: string) =>
    bytes.push(...[...t].map((c) => c.charCodeAt(0)));
  ascii("BTLT");
  bytes.push(1, 0, lines.parts.length, 0, 0);
  for (const p of lines.parts) {
    bytes.push(p.length);
    ascii(p);
  }
  for (const [address, part, source] of entries) {
    bytes.push(address & 0xff, address >> 8, part, source & 0xff, source >> 8);
  }
  bytes.push(0xff, 0xff, 0xff, 0xff, 0xff);
  bytes.push(entries.length & 0xff, entries.length >> 8);
  const imageCrc = crc16(output);
  bytes.push(imageCrc & 0xff, imageCrc >> 8);
  const crc = crc16(Uint8Array.from(bytes));
  bytes.push(crc & 0xff, crc >> 8);
  return Uint8Array.from(bytes);
}

function roundUp(value: number, alignment: number) {
  return Math.ceil(value / alignment) * alignment;
}

function hex4(n: number) {
  return n.toString(16).toUpperCase().padStart(4, "0");
}
