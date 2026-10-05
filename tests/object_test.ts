import { assertEquals, assertThrows } from "@std/assert";
import { crc16 } from "../ref/object/crc.ts";
import {
  defaultHeader,
  readByteStream,
  readProgramDirectory,
  writeByteStream,
  writeProgramDirectory,
} from "../ref/object/program.ts";
import { readLibrary, writeLibrary } from "../ref/object/library.ts";
import {
  readLineStream,
  readNameStream,
  writeLineStream,
  writeNameStream,
} from "../ref/object/streams.ts";
import {
  type DirectoryRecord,
  Form,
  Kind,
  ObjectError,
  type Reference,
} from "../ref/object/types.ts";

const hex = (s: string) =>
  Uint8Array.from(s.trim().split(/\s+/).map((b) => parseInt(b, 16)));

/** The worked example of object format §13. */
const example: DirectoryRecord[] = [
  {
    type: "blob",
    kind: Kind.bss,
    ordinal: 0x400,
    size: 2,
    root: false,
    align: 0,
    references: [],
  },
  {
    type: "blob",
    kind: Kind.code,
    ordinal: 0x402,
    size: 17,
    root: false,
    align: 0,
    references: [
      { offset: 1, form: Form.ABS16, target: 0x400, addend: 0 },
      { offset: 5, form: Form.ABS16, target: 0x400, addend: 0 },
      { offset: 15, form: Form.ABS16, target: 0x401, addend: 0 },
    ],
  },
  {
    type: "blob",
    kind: Kind.code,
    ordinal: 0x401,
    size: 7,
    root: false,
    align: 0,
    references: [{ offset: 4, form: Form.ABS16, target: 0x400, addend: 0 }],
  },
];

Deno.test("CRC-16/CCITT-FALSE check value", () => {
  assertEquals(crc16(new TextEncoder().encode("123456789")), 0x29b1);
});

Deno.test("the worked example encodes byte for byte", () => {
  const dir = writeProgramDirectory(defaultHeader(), example, 24);
  const records = dir.subarray(20, dir.length - 12);
  assertEquals(
    records,
    hex(`03 02 00 00
         08 02 04 11 00 03  01 00 04  04 00 04  0A 01 04
         08 01 04 07 00 01  04 00 04`),
  );
});

Deno.test("program directories round-trip", () => {
  const header = defaultHeader({ stamp: 0x1234, flags: 3 });
  const records: DirectoryRecord[] = [
    ...example,
    { type: "alias", alias: 0x403, base: 0x402, offset: 14 },
    { type: "entry", ordinal: 0x402 },
    { type: "limits", stackReserve: 600, largestFrame: 40, flags: 1 },
  ];
  const decoded = readProgramDirectory(
    writeProgramDirectory(header, records, 24),
  );
  assertEquals(decoded.header, header);
  assertEquals(decoded.records, records);
  assertEquals(decoded.trailer, {
    blobCount: 3,
    byteStreamLength: 24,
    highestOrdinal: 0x403,
  });
});

Deno.test("reference escapes, forms, addends and large counts", () => {
  const references: Reference[] = [
    { offset: 0, form: Form.ABS16, target: 0x401, addend: 0 },
    { offset: 70, form: Form.HI8, target: 0x401, addend: 0xffff },
    { offset: 72, form: Form.SIZE16, target: 0xffe2, addend: 0 },
  ];
  for (let i = 0; i < 300; i += 1) {
    references.push({
      offset: 100 + i * 3,
      form: Form.LO8,
      target: 0x400 + (i % 7),
      addend: i,
    });
  }
  const records: DirectoryRecord[] = [{
    type: "blob",
    kind: Kind.code,
    ordinal: 0x400,
    size: 1100,
    root: true,
    align: 0,
    references,
  }, {
    type: "blob",
    kind: Kind.rodata,
    ordinal: 0x401,
    size: 256,
    root: false,
    align: 7,
    references: [],
  }];
  const decoded = readProgramDirectory(
    writeProgramDirectory(defaultHeader(), records, 1356),
  );
  assertEquals(decoded.records, records);
});

Deno.test("a damaged directory is rejected", () => {
  const dir = writeProgramDirectory(defaultHeader(), example, 24);
  const bad = Uint8Array.from(dir);
  bad[22] ^= 0x01;
  const error = assertThrows(() => readProgramDirectory(bad), ObjectError);
  assertEquals(error.code, "L-TRUNCATED");
  assertThrows(
    () => readProgramDirectory(dir.subarray(0, dir.length - 3)),
    ObjectError,
  );
});

Deno.test("byte streams carry their stamp", () => {
  const data = Uint8Array.from([1, 2, 3]);
  const decoded = readByteStream(writeByteStream(0xbeef, data));
  assertEquals(decoded.stamp, 0xbeef);
  assertEquals(decoded.data, data);
});

Deno.test("blob libraries round-trip", () => {
  const records: DirectoryRecord[] = [
    {
      type: "blob",
      kind: Kind.startup,
      ordinal: 1,
      size: 4,
      root: true,
      align: 0,
      references: [{ offset: 1, form: Form.ABS16, target: 0xffe0, addend: 0 }],
    },
    { type: "alias", alias: 2, base: 1, offset: 3 },
  ];
  const lib = {
    runtimeIdentity: 7,
    helperVersion: 2,
    profileIdentity: 1,
    profile: {
      targetClass: 1,
      outputKinds: 1,
      imageBase: 0x100,
      imageLimit: 0xdc00,
      nominalTop: 0xe406,
      ccpSize: 0x800,
      ramBase: 0,
      ramLimit: 0,
      guardBand: 64,
      optionSupport: 3,
      freeRestartVectors: 0,
      debuggerMargin: 8192,
      fileEntrySize: 176,
    },
    records,
    bytes: Uint8Array.from([0xcd, 0, 0, 0xc7]),
    keys: [0x1111, 0x2222],
  };
  const file = writeLibrary(lib);
  assertEquals(file.length % 1, 0);
  const decoded = readLibrary(file, true);
  assertEquals(decoded.profile, lib.profile);
  assertEquals(decoded.records, records);
  assertEquals(decoded.bytes, lib.bytes);
  assertEquals(decoded.keys, lib.keys);
  assertEquals(decoded.trailer.highestOrdinal, 2);
});

Deno.test("line and name streams round-trip", () => {
  const blobs = [{
    ordinal: 0x402,
    entries: [
      { offset: 0, part: 0, source: 120 },
      { offset: 7, part: 0, source: 140 },
      { offset: 200, part: 1, source: 3 },
      { offset: 200, part: 0, source: 160 },
    ],
  }];
  const lines = readLineStream(
    writeLineStream(9, ["A:MAIN.BSI", "A:UTIL.BSI"], blobs),
  );
  assertEquals(lines.parts, ["A:MAIN.BSI", "A:UTIL.BSI"]);
  assertEquals(lines.blobs, blobs);
  const names = readNameStream(writeNameStream(9, [
    { ordinal: 0x400, name: "count" },
    { ordinal: 0x402, name: "bump" },
  ]));
  assertEquals(names.names.get(0x402), "bump");
});
