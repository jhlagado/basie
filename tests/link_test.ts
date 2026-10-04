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

Deno.test("the map lists live and removed blobs with totals", async () => {
  const { writeMap, writeSymbols } = await import("../ref/link/reports.ts");
  const result = linkProgram();
  const names = new Map([[0x400, "main"], [0x401, "unused"], [
    0x402,
    "greeting",
  ]]);
  const map = writeMap(result, {
    programName: "HELLO",
    libraryName: "TEST.BRL",
    runtimeIdentity: 1,
    profileIdentity: 1,
    outputKind: ".COM",
    profile,
    names,
  });
  assertEquals(map.includes("$0104      9  code       0  $0400    main"), true);
  assertEquals(map.includes("$0401      3  code     unused"), true);
  assertEquals(map.includes("Program   kept 18, removed 3"), true);
  const sym = new TextDecoder().decode(writeSymbols(result, names));
  assertEquals(sym.startsWith("0104 main\r\n010D greeting\r\n"), true);
});

// ---- Conformance list (linker §11) -----------------------------------------

const ref = (
  offset: number,
  form: number,
  target: number,
  addend = 0,
): Reference => ({ offset, form: form as Reference["form"], target, addend });

/** A code blob that CALLs each target in turn, then returns. */
function caller(ordinal: number, targets: number[]) {
  const bytes = targets.flatMap(() => [0xcd, 0, 0]).concat([0xc9]);
  return blob(
    Kind.code,
    ordinal,
    bytes,
    targets.map((t, i) => abs(i * 3 + 1, t)),
  );
}

Deno.test("a program with no dead blobs removes nothing", () => {
  const parts = [caller(0x400, [0x401]), blob(Kind.code, 0x401, [0xc9])];
  const result = linkProgram(parts);
  assertEquals(result.removed, []);
  assertEquals(result.addresses.get(0x401), 0x104 + 4);
});

Deno.test("dead blobs at the start, middle and end of every section", () => {
  const ret = [0xc9];
  const parts = [
    blob(Kind.code, 0x400, ret), // dead, first
    caller(0x401, [0x403, 0x405, 0x408, 0x40a]), // main
    blob(Kind.code, 0x402, ret), // dead, middle
    blob(Kind.code, 0x403, ret),
    blob(Kind.code, 0x404, ret), // dead, end of code
    blob(Kind.data, 0x405, [1]),
    blob(Kind.data, 0x406, [2]), // dead data
    blob(Kind.bss, 0x407, 4), // dead, first bss
    blob(Kind.bss, 0x408, 4),
    blob(Kind.bss, 0x409, 4), // dead, middle bss
    blob(Kind.bss, 0x40a, 4),
    blob(Kind.bss, 0x40b, 4), // dead, last bss
  ];
  const p = program(parts, [{ type: "entry", ordinal: 0x401 }]);
  const lib = library([blob(Kind.code, 2, ret), blob(Kind.bss, 3, 8)]);
  const result = link(lib, p.dir, p.bytes, { rerunnable: true });
  assertEquals(
    result.removed.sort((a, b) => a - b),
    [2, 3, 0x400, 0x402, 0x404, 0x406, 0x407, 0x409, 0x40b],
  );
  // Live blobs are packed with no gaps where the dead ones were.
  const main = result.addresses.get(0x401)!;
  assertEquals(result.addresses.get(0x403), main + 13);
  const bss = result.pseudo.get(Pseudo.BSS)!;
  assertEquals(result.addresses.get(0x408), bss.address);
  assertEquals(result.addresses.get(0x40a), bss.address + 4);
  assertEquals(bss.size, 8);
});

Deno.test("a chain of references through a routine defined later", () => {
  // main -> 0x403 -> 0x402 -> 0x401; 0x401 calls main back, as a cycle
  // through a forward-declared routine would.
  const parts = [
    caller(0x400, [0x403]),
    caller(0x401, [0x400]),
    caller(0x402, [0x401]),
    caller(0x403, [0x402]),
    blob(Kind.code, 0x404, [0xc9]),
  ];
  const result = linkProgram(parts);
  assertEquals(result.removed, [0x404]);
});

Deno.test("an alias referenced only from a dead blob keeps nothing live", () => {
  const lib = library([blob(Kind.code, 2, [0xc9, 0xc9, 0xc9])]);
  lib.records.push({ type: "alias", alias: 3, base: 2, offset: 1 });
  const parts = [...hello(), caller(0x403, [3])];
  const result = linkProgram(parts, {}, lib);
  assertEquals(result.live.has(2), false);
  assertEquals(result.addresses.has(3), false);
  assertEquals(result.removed.includes(0x403), true);
});

Deno.test("one target referenced many times, and hundreds of targets", () => {
  const many = caller(0x400, new Array(200).fill(0x401));
  const one = linkProgram([many, blob(Kind.code, 0x401, [0xc9])]);
  const target = one.addresses.get(0x401)!;
  const main = one.addresses.get(0x400)! - 0x100;
  for (let i = 0; i < 200; i += 1) {
    const at = main + i * 3 + 1;
    assertEquals(one.image[at] | one.image[at + 1] << 8, target);
  }
  const ordinals = Array.from({ length: 300 }, (_, i) => 0x401 + i);
  const parts = [
    caller(0x400, ordinals),
    ...ordinals.map((o) => blob(Kind.code, o, [0xc9])),
  ];
  const wide = linkProgram(parts);
  assertEquals(wide.removed, []);
  assertEquals(
    wide.addresses.get(0x401 + 299),
    wide.addresses.get(0x401)! + 299,
  );
});

Deno.test("every reference form, with ABS16 spanning a 128-byte record", () => {
  // Startup is 4 bytes at $0100; a filler puts main's ABS16 at $017F-$0180,
  // across the first record boundary of the .COM file.
  const filler = blob(Kind.code, 0x400, new Array(123).fill(0));
  const main = blob(Kind.code, 0x401, [0, 0, 0, 0, 0, 0xc9], [
    ref(0, Form.ABS16, 0x402, 1),
    ref(2, Form.LO8, 0x402),
    ref(3, Form.HI8, 0x402),
    ref(4, Form.SIZE16, 0x402),
  ]);
  main.record.size = 7;
  main.bytes.push(0);
  main.record.references[3] = ref(4, Form.SIZE16, 0x402);
  const table = blob(Kind.rodata, 0x402, new Array(300).fill(0xaa));
  const p = program([filler, main, table], [
    { type: "entry", ordinal: 0x401 },
  ]);
  filler.record.root = true;
  const result = link(library(), p.dir, p.bytes);
  const t = result.addresses.get(0x402)!;
  const at = result.addresses.get(0x401)! - 0x100;
  assertEquals(at, 0x7f);
  const out = result.output;
  assertEquals(out[0x7f] | out[0x80] << 8, t + 1);
  assertEquals(out[0x81], t & 0xff);
  assertEquals(out[0x82], t >> 8);
  assertEquals(out[0x83] | out[0x84] << 8, 300);
});

Deno.test("aligned blobs of every class: padding, order and alignment", () => {
  const parts = [
    caller(0x400, [0x401, 0x402, 0x403, 0x404, 0x405]),
    blob(Kind.rodata, 0x401, [9], [], { align: 3 }),
    blob(Kind.rodata, 0x402, [1, 2, 3], [], { align: 7 }),
    blob(Kind.data, 0x403, [4, 5], [], { align: 2 }),
    blob(Kind.bss, 0x404, 10, [], { align: 4 }),
    blob(Kind.bss, 0x405, 3),
  ];
  const result = linkProgram(parts, { rerunnable: true });
  const a = (o: number) => result.addresses.get(o)!;
  assertEquals(a(0x401) % 8, 0);
  assertEquals(a(0x402) % 256, 0);
  assertEquals(a(0x403) % 4, 0);
  assertEquals(a(0x404) % 16, 0);
  // Larger classes first within TEXT; the unaligned main comes last.
  assertEquals(a(0x402) < a(0x401) && a(0x401) < a(0x400), true);
  assertEquals(a(0x404) < a(0x405), true);
  const padded = result.blobs.find((b) => b.ordinal === 0x402)!;
  assertEquals(padded.padding, a(0x402) - (0x100 + 4));
});

Deno.test("self-references and negative addends", () => {
  // JP to itself, an end pointer to itself, and FREE-2.
  const self = blob(Kind.code, 0x400, [0xc3, 0, 0, 0, 0, 0, 0, 0xc9], [
    abs(1, 0x400),
    abs(3, 0x400, 8),
    abs(5, Pseudo.FREE, 0xfffe),
  ]);
  const result = linkProgram([self]);
  const main = result.addresses.get(0x400)!;
  const w = (o: number) =>
    result.image[main - 0x100 + o] | result.image[main - 0x100 + o + 1] << 8;
  assertEquals(w(1), main);
  assertEquals(w(3), main + 8);
  assertEquals(w(5), result.pseudo.get(Pseudo.FREE)!.address - 2);
});

Deno.test("empty BSS and DATA have size 0 and sensible addresses", () => {
  const result = linkProgram(hello(), { rerunnable: true });
  const bss = result.pseudo.get(Pseudo.BSS)!;
  const data = result.pseudo.get(Pseudo.DATA)!;
  assertEquals(bss.size, 0);
  assertEquals(bss.address, result.pseudo.get(Pseudo.FREE)!.address);
  assertEquals(data.size, 0);
  assertEquals(result.pseudo.get(Pseudo.DATACOPY)!.size, 0);
});

Deno.test("a re-runnable data blob may refer to a bss blob; COPY equals DATA", () => {
  const parts = [
    caller(0x400, [0x401]),
    blob(Kind.data, 0x401, [0, 0, 9], [abs(0, 0x402)]),
    blob(Kind.bss, 0x402, 4),
  ];
  const result = linkProgram(parts, { rerunnable: true, keepCcp: true });
  const data = result.pseudo.get(Pseudo.DATA)!;
  const copy = result.pseudo.get(Pseudo.DATACOPY)!;
  const slice = (a: number, n: number) =>
    Array.from(result.image.subarray(a - 0x100, a - 0x100 + n));
  assertEquals(slice(copy.address, 3), slice(data.address, 3));
  const bssAt = result.addresses.get(0x402)!;
  assertEquals(slice(data.address, 2), [bssAt & 0xff, bssAt >> 8]);
  assertEquals(result.pseudo.get(Pseudo.OPTIONS)!.address, 3);
});

Deno.test("a reference past an alias's effective end is an error", () => {
  const lib = library([blob(Kind.code, 2, [0xc9, 0xc9, 0xc9, 0xc9])]);
  lib.records.push({ type: "alias", alias: 3, base: 2, offset: 2 });
  const ok = hello();
  ok[0].record.references.push(abs(6, 3, 2)); // the end pointer
  linkProgram(ok, {}, lib);
  const bad = hello();
  bad[0].record.references.push(abs(6, 3, 3));
  assertEquals(
    assertThrows(() => linkProgram(bad, {}, lib), LinkError).code,
    "L-RANGE",
  );
});

Deno.test("the highest program ordinal links; the next is rejected", () => {
  const top = [caller(0x400, [0xffdf]), blob(Kind.code, 0xffdf, [0xc9])];
  linkProgram(top);
  const beyond = [
    blob(Kind.code, 0x400, [0xc9]),
    blob(Kind.code, 0xffe0, [0xc9]),
  ];
  assertEquals(
    assertThrows(() => linkProgram(beyond), LinkError).code,
    "L-ORDINAL",
  );
});

Deno.test("ROM targets place DATA and BSS in RAM and store only COPY", () => {
  const lib = library();
  lib.profile = {
    ...profile,
    targetClass: 3,
    outputKinds: 2,
    imageBase: 0x0000,
    imageLimit: 0x2000,
    ramBase: 0x8000,
    ramLimit: 0x9000,
  };
  const parts = [
    caller(0x400, [0x401, 0x402]),
    blob(Kind.data, 0x401, [5, 6, 7]),
    blob(Kind.bss, 0x402, 16),
  ];
  const result = linkProgram(parts, { output: "bin" }, lib);
  assertEquals(result.addresses.get(0x401), 0x8000);
  assertEquals(result.addresses.get(0x402), 0x8003);
  const copy = result.pseudo.get(Pseudo.DATACOPY)!;
  assertEquals(copy.address < 0x2000, true);
  assertEquals(
    Array.from(result.image.subarray(copy.address, copy.address + 3)),
    [5, 6, 7],
  );
  assertEquals(result.image.length, copy.address + 3);
  const tooBig = [...parts];
  tooBig[2] = blob(Kind.bss, 0x402, 0x1000);
  assertEquals(
    assertThrows(() => linkProgram(tooBig, { output: "bin" }, lib), LinkError)
      .code,
    "L-FIT-RAM",
  );
});

Deno.test("a program above the nominal top links with a warning", () => {
  const result = linkProgram(hello(), { stack: 0xe400 });
  assertEquals(result.warnings.length, 1);
  assertEquals(result.warnings[0].startsWith("L-FIT-NOMINAL"), true);
  assertEquals(linkProgram().warnings, []);
});

Deno.test("the remaining diagnostics", () => {
  const withRecords = (
    edit: (r: DirectoryRecord[]) => DirectoryRecord[],
    opts: LinkOptions = {},
  ) => {
    const p = program(hello());
    p.dir.records = edit(p.dir.records);
    return link(library(), p.dir, p.bytes, opts);
  };
  const cases: [string, () => unknown][] = [
    ["L-OUTPUT", () => {
      const lib = library();
      lib.profile = { ...profile, outputKinds: 1 };
      return linkProgram(hello(), { output: "hex" }, lib);
    }],
    ["L-RESERVED", () => withRecords((r) => [{ type: "bank", bank: 1 }, ...r])],
    ["L-RESERVED", () => {
      const parts = hello();
      parts[0].record.references[0] = ref(3, Form.BANK8, 0x402);
      return linkProgram(parts);
    }],
    ["L-ALIAS", () =>
      withRecords((r) => [
        ...r.slice(0, 3),
        { type: "alias", alias: 0x410, base: 0x402, offset: 9 },
        ...r.slice(3),
      ])],
    ["L-ENTRY", () => withRecords((r) => r.filter((x) => x.type !== "entry"))],
    [
      "L-ENTRY",
      () =>
        withRecords((
          r,
        ) => [
          ...r.slice(0, 3),
          { type: "entry", ordinal: 0x402 },
          ...r.slice(4),
        ]),
    ],
    [
      "L-LIMITS",
      () => withRecords((r) => r.filter((x) => x.type !== "limits")),
    ],
    ["L-LIMITS", () => withRecords((r) => [r.at(-1)!, ...r.slice(0, -1)])],
    ["L-TRUNCATED", () => {
      const p = program(hello());
      return link(library(), p.dir, p.bytes.slice(1));
    }],
    ["L-FIT-MEMORY", () => linkProgram(hello(), { stack: 0xff00 })],
    ["L-PLACEHOLDER", () => {
      const parts = hello();
      parts[0].bytes[3] = 1;
      return linkProgram(parts, { verify: true });
    }],
  ];
  for (const [code, run] of cases) {
    const error = assertThrows(run, LinkError, undefined, code);
    assertEquals(error.code, code);
  }
});
