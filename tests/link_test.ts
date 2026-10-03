import { assertEquals, assertThrows } from "@std/assert";
import { link, LinkError, type LinkOptions } from "../ref/link/link.ts";
import { type Library, type Profile } from "../ref/object/library.ts";
import { defaultHeader } from "../ref/object/program.ts";
import {
  type BlobRecord,
  type DirectoryRecord,
  Form,
  Kind,
  type ProgramDirectory,
  Pseudo,
  type Reference,
} from "../ref/object/types.ts";
import { runCom } from "./harness/cpm.ts";

const profile: Profile = {
  targetClass: 1,
  outputKinds: 7,
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
};

function blob(
  kind: number,
  ordinal: number,
  bytes: number[] | number,
  references: Reference[] = [],
  extra: Partial<BlobRecord> = {},
): { record: BlobRecord; bytes: number[] } {
  const size = typeof bytes === "number" ? bytes : bytes.length;
  return {
    record: {
      type: "blob",
      kind: kind as BlobRecord["kind"],
      ordinal,
      size,
      root: kind === Kind.startup,
      align: 0,
      references,
      ...extra,
    },
    bytes: typeof bytes === "number" ? [] : bytes,
  };
}

const abs = (offset: number, target: number, addend = 0): Reference => ({
  offset,
  form: Form.ABS16,
  target,
  addend,
});

/** A library whose startup calls MAIN and returns to the CCP. */
function library(extra: ReturnType<typeof blob>[] = []): Library {
  const startup = blob(Kind.startup, 1, [0xcd, 0, 0, 0xc9], [
    abs(1, Pseudo.MAIN),
  ]);
  const parts = [startup, ...extra];
  return {
    runtimeIdentity: 1,
    helperVersion: 1,
    profileIdentity: 1,
    profile,
    records: parts.map((p) => p.record),
    trailer: {
      blobCount: parts.length,
      byteStreamLength: 0,
      highestOrdinal: Math.max(...parts.map((p) => p.record.ordinal)),
    },
    bytes: Uint8Array.from(parts.flatMap((p) => p.bytes)),
    keys: [0],
  };
}

function program(
  parts: ReturnType<typeof blob>[],
  control: DirectoryRecord[] = [],
): { dir: ProgramDirectory; bytes: Uint8Array } {
  const records: DirectoryRecord[] = [
    ...parts.map((p) => p.record),
    ...control,
  ];
  if (!control.some((c) => c.type === "entry")) {
    records.push({ type: "entry", ordinal: parts[0].record.ordinal });
  }
  if (!control.some((c) => c.type === "limits")) {
    records.push({
      type: "limits",
      stackReserve: 64,
      largestFrame: 0,
      flags: 0,
    });
  }
  return {
    dir: {
      header: defaultHeader(),
      records,
      trailer: {
        blobCount: parts.length,
        byteStreamLength: 0,
        highestOrdinal: 0,
      },
    },
    bytes: Uint8Array.from(parts.flatMap((p) => p.bytes)),
  };
}

const hello = () => [
  // main: LD C,9 / LD DE,message / CALL 5 / RET
  blob(Kind.code, 0x400, [0x0e, 9, 0x11, 0, 0, 0xcd, 5, 0, 0xc9], [
    abs(3, 0x402),
  ]),
  // a routine nothing calls
  blob(Kind.code, 0x401, [0xc9, 0xc9, 0xc9]),
  blob(Kind.rodata, 0x402, [...new TextEncoder().encode("LINKED\r\n$")]),
];

function linkProgram(parts = hello(), opts: LinkOptions = {}, lib = library()) {
  const p = program(parts);
  return link(lib, p.dir, p.bytes, opts);
}

Deno.test("a linked program runs, with unused blobs removed", () => {
  const result = linkProgram();
  assertEquals(result.removed, [0x401]);
  assertEquals(result.addresses.get(0x400), 0x104);
  assertEquals(result.addresses.get(0x402), 0x10d);
  const run = runCom(result.output);
  assertEquals(run.output, "LINKED\r\n");
  assertEquals(result.output.length, 128);
});

Deno.test("linking is deterministic", () => {
  assertEquals(linkProgram().output, linkProgram().output);
});

Deno.test("aligned blobs come first in their section", () => {
  const parts = hello();
  parts.push(
    blob(Kind.rodata, 0x403, [1, 2, 3, 4], [], { align: 7 }),
  );
  parts[0].record.references.unshift({
    offset: 0,
    form: Form.LO8,
    target: 0x403,
    addend: 0,
  });
  parts[0].bytes[0] = 0;
  // LO8 of a page-aligned table is 0, so main's first byte stays a NOP.
  const result = linkProgram(parts);
  assertEquals(result.addresses.get(0x403)! % 256, 0);
  assertEquals(result.addresses.get(0x403), 0x200);
});

Deno.test("bss, free and required are placed after the image", () => {
  const parts = hello();
  parts.push(blob(Kind.bss, 0x403, 100));
  parts[0].record.references.push(abs(6, 0x403)); // inside CALL 5's operand?
  parts[0].record.references.pop();
  parts.splice(1, 0); // keep order
  const withBss = hello();
  withBss.push(blob(Kind.bss, 0x403, 100));
  withBss[2].record.references.push(abs(0, 0x403));
  withBss[2].bytes[0] = 0;
  withBss[2].bytes[1] = 0;
  const result = linkProgram(withBss);
  const bss = result.pseudo.get(Pseudo.BSS)!;
  assertEquals(bss.address, 0x100 + result.image.length);
  assertEquals(bss.size, 100);
  assertEquals(result.pseudo.get(Pseudo.FREE)!.address, bss.address + 100);
  assertEquals(
    result.pseudo.get(Pseudo.REQUIRED)!.address,
    bss.address + 100 + 64,
  );
});

Deno.test("the file table is allocated only when used", () => {
  const plain = linkProgram();
  assertEquals(plain.pseudo.get(Pseudo.FILES)!.size, 0);
  const parts = hello();
  parts[0].record.references.push(abs(6, Pseudo.FILECOUNT));
  // CALL 5 becomes CALL FILECOUNT's value: only addresses matter here.
  const result = linkProgram(parts, { files: 6 });
  assertEquals(result.pseudo.get(Pseudo.FILES)!.size, 6 * 176);
  assertEquals(result.pseudo.get(Pseudo.FILECOUNT)!.address, 6);
});

Deno.test("end pointers are allowed and one past them is an error", () => {
  const ok = hello();
  ok[0].record.references[0] = abs(3, 0x402, 9); // one past the 9-byte text
  linkProgram(ok);
  const bad = hello();
  bad[0].record.references[0] = abs(3, 0x402, 10);
  const error = assertThrows(() => linkProgram(bad), LinkError);
  assertEquals(error.code, "L-RANGE");
});

Deno.test("aliases resolve to their base and keep it live", () => {
  const lib = library([blob(Kind.code, 2, [0xc9, 0xc9, 0xc9])]);
  lib.records.push({ type: "alias", alias: 3, base: 2, offset: 2 });
  lib.trailer.highestOrdinal = 3;
  const parts = hello();
  parts[0].record.references.push(abs(6, 3));
  const result = linkProgram(parts, {}, lib);
  assertEquals(result.live.has(2), true);
  assertEquals(result.addresses.get(3), result.addresses.get(2)! + 2);
});

Deno.test("re-runnable images store a copy of DATA", () => {
  const parts = hello();
  parts.push(blob(Kind.data, 0x403, [7, 8, 9]));
  parts[0].record.references.push(abs(6, 0x403));
  const result = linkProgram(parts, { rerunnable: true });
  const data = result.pseudo.get(Pseudo.DATA)!;
  const copy = result.pseudo.get(Pseudo.DATACOPY)!;
  assertEquals(copy.size, 3);
  const at = (a: number) => result.image[a - 0x100];
  assertEquals([at(copy.address), at(copy.address + 1)], [
    at(data.address),
    at(data.address + 1),
  ]);
  assertEquals(result.pseudo.get(Pseudo.OPTIONS)!.address & 2, 2);
});

Deno.test("Intel HEX output", () => {
  const result = linkProgram(hello(), { output: "hex" });
  const text = new TextDecoder().decode(result.output).split("\u001a")[0];
  const lines = text.trim().split("\r\n");
  assertEquals(lines.at(-1), ":00000001FF");
  assertEquals(lines[0].startsWith(":10010000"), true);
});

Deno.test("diagnostics", () => {
  const cases: [string, () => unknown][] = [
    ["L-UNDEFINED", () => {
      const parts = hello();
      parts[0].record.references[0] = abs(3, 0x499);
      return linkProgram(parts);
    }],
    ["L-ORDINAL", () => {
      const parts = hello();
      parts[1].record.ordinal = 0x400;
      return linkProgram(parts);
    }],
    ["L-BLOB", () => linkProgram([...hello(), blob(Kind.code, 0x403, 0)])],
    ["L-REFERENCE", () => {
      const parts = hello();
      parts[0].record.references[0] = abs(8, 0x402); // runs off the end
      return linkProgram(parts);
    }],
    ["L-COMPAT", () => {
      const lib = library();
      lib.runtimeIdentity = 9;
      return linkProgram(hello(), {}, lib);
    }],
    ["L-STAMP", () => linkProgram(hello(), { byteStreamStamp: 7 })],
    ["L-OPTION", () => linkProgram(hello(), { files: 0 })],
    ["L-STARTUP", () => {
      const lib = library();
      lib.records[0].type === "blob" && (lib.records[0].references = []);
      return linkProgram(hello(), {}, lib);
    }],
    [
      "L-FIT-IMAGE",
      () => {
        const parts = [
          ...hello(),
          blob(Kind.rodata, 0x403, new Array(0xdc00).fill(0)),
        ];
        parts[0].record.references.push(abs(6, 0x403)); // keep it live
        return linkProgram(parts);
      },
    ],
  ];
  for (const [code, run] of cases) {
    const error = assertThrows(run, LinkError, undefined, code);
    assertEquals(error.code, code);
  }
});

Deno.test("a line table is written in address order", () => {
  const p = program(hello());
  const result = link(library(), p.dir, p.bytes, {
    lines: {
      stamp: 1,
      parts: ["A:MAIN.BTN"],
      blobs: [{
        ordinal: 0x400,
        entries: [{ offset: 0, part: 0, source: 10 }, {
          offset: 5,
          part: 0,
          source: 30,
        }],
      }],
    },
  });
  const t = result.lineTable!;
  assertEquals(new TextDecoder().decode(t.subarray(0, 4)), "BTLT");
});
