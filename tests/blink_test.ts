/**
 * The native linker, BLINK.COM, under the CP/M harness: its command line,
 * files, CRC and diagnostics (roadmap step 59), and its Phase A and B tables,
 * compared with the reference linker's (step 60).
 */
import { assertEquals } from "@std/assert";
import { formatMessage, messageFile } from "../ref/compile/messages.ts";
import { buildRuntime } from "../tools/helpertable.ts";
import { assembleFile, comBytes, runCom } from "./harness/cpm.ts";
import { intelHex } from "../ref/link/link.ts";
import { crc16 } from "../ref/object/crc.ts";

const blink = comBytes(await assembleFile("native/linker/BLINK.ASM"));
const library = (await buildRuntime()).file;
const MSG = messageFile();
const { compile } = await import("../ref/compile/index.ts");
const hello = await compile("tests/conformance/basics/hello.bsi");
if (!hello.ok) throw new Error("hello didn't compile");
const HELLO_DR = hello.objects.directory;
const HELLO_BY = hello.objects.bytes;
const HELLO_LN = hello.objects.lines;
const HELLO_NM = hello.objects.names;

function run(tail: string, files: Record<string, Uint8Array> = {}) {
  return runCom(blink, { tail, files, maxSteps: 200_000_000 }).output;
}

const error = (n: number, args: string[] = []) =>
  `Error ${n}: ${formatMessage(n, args)}\r\n`;

Deno.test("BLINK.COM is the recorded image", async () => {
  const digest = await crypto.subtle.digest("SHA-256", blink);
  const hex = [...new Uint8Array(digest)]
    .map((b) => b.toString(16).padStart(2, "0")).join("");
  // Design decision D44: renames and commentary leave the image byte-identical.
  // A change to the linker's code updates this digest and size in the same
  // commit, so that no byte changes by accident.
  assertEquals(hex, BLINK_DIGEST);
  assertEquals(blink.length, 10_839);
});

const BLINK_DIGEST =
  "0b1e3f2641159eb6df6f23331e5e24f4d4d43cf33dda8105232afdc7e47a59cc";

Deno.test("BLINK with no name prints its usage", () => {
  assertEquals(run("", { "BASIE.MSG": MSG }), error(223));
});

Deno.test("without BASIE.MSG a diagnostic gives its number and arguments", () => {
  assertEquals(run(""), "Error 223: Message 223\r\n");
  assertEquals(run("HELLO"), "Error 225: Message 225: CPM22.BRL\r\n");
});

Deno.test("BLINK finds and checks the library, and its CRC with V", () => {
  const files = {
    "BASIE.MSG": MSG,
    "CPM22.BRL": library,
    "HELLO.$DR": HELLO_DR,
    "HELLO.$BY": HELLO_BY,
    "HELLO.$LN": HELLO_LN,
  };
  assertEquals(run("HELLO", files), "");
  assertEquals(run("HELLO [V]", files), "");
  const damaged = library.slice();
  damaged[200] ^= 1;
  assertEquals(
    run("HELLO [V]", { ...files, "CPM22.BRL": damaged }),
    error(214, ["CPM22.BRL"]),
  );
  // Without V, the directory's own CRC finds the same damage.
  assertEquals(
    run("HELLO", { ...files, "CPM22.BRL": damaged }),
    error(214, ["CPM22.BRL"]),
  );
  assertEquals(
    run("HELLO", { "BASIE.MSG": MSG, "CPM22.BRL": library }),
    error(225, ["HELLO.$DR"]),
  );
  const foreign = library.slice();
  foreign[0] = 0x58;
  assertEquals(
    run("HELLO", { ...files, "CPM22.BRL": foreign }),
    error(200, ["CPM22.BRL"]),
  );
});

Deno.test("BLINK looks for the library named by P=", () => {
  assertEquals(
    run("HELLO [P=OTHER]", { "BASIE.MSG": MSG }),
    error(225, ["OTHER.BRL"]),
  );
  assertEquals(
    run("hello [p=other]", {
      "BASIE.MSG": MSG,
      "OTHER.BRL": library,
      "HELLO.$DR": HELLO_DR,
      "HELLO.$BY": HELLO_BY,
      "HELLO.$LN": HELLO_LN,
    }),
    "",
  );
});

Deno.test("BLINK refuses bad and repeated options", () => {
  const files = {
    "BASIE.MSG": MSG,
    "CPM22.BRL": library,
    "HELLO.$DR": HELLO_DR,
    "HELLO.$BY": HELLO_BY,
    "HELLO.$LN": HELLO_LN,
  };
  assertEquals(run("HELLO [Q]", files), error(224, ["Q"]));
  assertEquals(run("HELLO [M,M]", files), error(224, ["M"]));
  assertEquals(run("HELLO [F=0]", files), error(224, ["F=0"]));
  assertEquals(run("HELLO [F=256]", files), error(224, ["F=256"]));
  assertEquals(run("HELLO [L=Q]", files), error(224, ["L=Q"]));
  assertEquals(run("HELLO [M, Y, F=6, STACK=512, O=B:OUT.HEX]", files), "");
  assertEquals(run("HELLO,UTIL [K]", files), "");
  assertEquals(run("TOOLONGNAME", files), error(224, ["TOOLONGNAME"]));
  assertEquals(run("HELLO [O=OUT.TXT]", files), error(224, ["O=OUT.TXT"]));
});

Deno.test("BLINK writes .BIN and Intel HEX images (linker §7.5, §7.6)", () => {
  if (!hello.ok) throw new Error();
  const files = {
    "BASIE.MSG": MSG,
    "CPM22.BRL": library,
    "HELLO.$DR": HELLO_DR,
    "HELLO.$BY": HELLO_BY,
    "HELLO.$LN": HELLO_LN,
  };
  const opts = { maxSteps: 100_000_000 };
  let run = runCom(blink, { tail: "HELLO [O=HELLO.BIN]", files, ...opts });
  assertEquals(run.output, "");
  assertEquals(run.disk.get("HELLO.BIN"), hello.com);
  run = runCom(blink, { tail: "HELLO [O=HELLO.HEX]", files, ...opts });
  assertEquals(run.output, "");
  const hex = intelHex(hello.link.image, hello.link.imageBase);
  assertEquals(run.disk.get("HELLO.HEX"), hex);
  // The line table carries the CRC of the output file as written.
  const table = run.disk.get("HELLO.LIN")!.subarray(0, hello.lineTable!.length);
  const crc = crc16(hex);
  assertEquals([table.at(-4), table.at(-3)], [crc & 0xff, crc >> 8]);
});

Deno.test("BLINK checks the options and output kind against the profile", () => {
  const files = {
    "BASIE.MSG": MSG,
    "HELLO.$DR": HELLO_DR,
    "HELLO.$BY": HELLO_BY,
    "HELLO.$LN": HELLO_LN,
  };
  const profile = (kinds: number, options: number, base = 0x100) => {
    const lib = library.slice();
    lib[43] = kinds;
    lib[44] = base & 0xff;
    lib[45] = base >> 8;
    lib[58] = options;
    return { ...files, "CPM22.BRL": lib };
  };
  assertEquals(run("HELLO [B]", profile(7, 2)), error(203));
  assertEquals(run("HELLO [R]", profile(7, 1)), error(203));
  assertEquals(run("HELLO [O=X.HEX]", profile(3, 3)), error(204));
  assertEquals(run("HELLO", profile(7, 3, 0x200)), error(204));
});

/** Read NAME.$TB: [ordinal, flags, size] per defined entry, and uses-files. */
function readTables(bytes: Uint8Array) {
  const entries: { ordinal: number; flags: number; size: number }[] = [];
  let at = 0;
  while (true) {
    const ordinal = bytes[at] | (bytes[at + 1] << 8);
    if (ordinal === 0xffff) return { entries, usesFiles: bytes[at + 2] === 1 };
    entries.push({
      ordinal,
      flags: bytes[at + 2],
      size: bytes[at + 3] | (bytes[at + 4] << 8),
    });
    at += 5;
  }
}

const PROGRAMS = [
  "examples/ADVENT.BSI",
  "examples/DUMP.BSI",
  "examples/BUGS.BSI",
  "tests/conformance/basics/hello.bsi",
  "tests/conformance/storage/linked-list.bsi",
  "tests/conformance/library/text-files.bsi",
];

for (const path of PROGRAMS) {
  Deno.test(`BLINK's Phase A and B tables match the reference for ${path}`, async () => {
    const result = await compile(path);
    if (!result.ok) throw new Error(JSON.stringify(result));
    const run = runCom(blink, {
      tail: "PROG [W]",
      files: {
        "BASIE.MSG": MSG,
        "CPM22.BRL": library,
        "PROG.$DR": result.objects.directory,
        "PROG.$BY": result.objects.bytes,
        "PROG.$LN": result.objects.lines,
      },
      maxSteps: 100_000_000,
    });
    assertEquals(run.output, "");
    const tables = readTables(run.disk.get("PROG.$TB")!);
    const blobs = tables.entries.filter((e) => !(e.flags & 0x40)).map((e) => ({
      ordinal: e.ordinal,
      kind: e.flags & 7,
      size: e.size,
      live: (e.flags & 0x20) !== 0,
    }));
    const want = [...result.blobs].sort((a, b) => a.ordinal - b.ordinal);
    assertEquals(blobs, want);
  });
}

Deno.test("BLINK checks the program against the library", () => {
  const files = {
    "BASIE.MSG": MSG,
    "CPM22.BRL": library,
    "HELLO.$BY": HELLO_BY,
    "HELLO.$LN": HELLO_LN,
  };
  const otherKey = HELLO_DR.slice();
  otherKey[12] ^= 1; // the helper-table key
  assertEquals(run("HELLO", { ...files, "HELLO.$DR": otherKey }), error(201));
  const noStamp = HELLO_DR.slice();
  noStamp[6] = 0;
  noStamp[7] = 0;
  assertEquals(run("HELLO", { ...files, "HELLO.$DR": noStamp }), error(202));
  const notProgram = HELLO_DR.slice();
  notProgram[3] = 0x58;
  assertEquals(
    run("HELLO", { ...files, "HELLO.$DR": notProgram }),
    error(200, ["HELLO.$DR"]),
  );
});

for (const path of PROGRAMS) {
  Deno.test(`BLINK writes the reference's image for ${path}`, async () => {
    const result = await compile(path);
    if (!result.ok) throw new Error(JSON.stringify(result));
    const run = runCom(blink, {
      tail: "PROG",
      files: {
        "BASIE.MSG": MSG,
        "CPM22.BRL": library,
        "PROG.$DR": result.objects.directory,
        "PROG.$BY": result.objects.bytes,
        "PROG.$LN": result.objects.lines,
      },
      maxSteps: 100_000_000,
    });
    assertEquals(run.output, "");
    const image = run.disk.get("PROG.COM")!;
    assertEquals(image.length, result.com.length);
    assertEquals(image, result.com);
    // The line table, padded to whole records on the disk.
    const table = run.disk.get("PROG.LIN")!;
    assertEquals(table.subarray(0, result.lineTable!.length), result.lineTable);
  });
}

Deno.test("with option N BLINK needs no line stream and writes no line table", () => {
  const run = runCom(blink, {
    tail: "HELLO [N]",
    files: {
      "BASIE.MSG": MSG,
      "CPM22.BRL": library,
      "HELLO.$DR": HELLO_DR,
      "HELLO.$BY": HELLO_BY,
    },
    maxSteps: 100_000_000,
  });
  assertEquals(run.output, "");
  assertEquals(run.disk.has("HELLO.LIN"), false);
  assertEquals(run.disk.has("HELLO.COM"), true);
});

Deno.test("BLINK publishes: a backup, the line table, no intermediates", () => {
  const files = {
    "BASIE.MSG": MSG,
    "CPM22.BRL": library,
    "HELLO.$DR": HELLO_DR,
    "HELLO.$BY": HELLO_BY,
    "HELLO.$LN": HELLO_LN,
    "HELLO.COM": new Uint8Array(128).fill(0x76),
    "HELLO.LIN": new Uint8Array(128).fill(1),
  };
  const opts = { maxSteps: 100_000_000 };
  let run = runCom(blink, { tail: "HELLO", files, ...opts });
  assertEquals(run.output, "");
  assertEquals(run.disk.get("HELLO.COM"), hello.com);
  assertEquals(run.disk.get("HELLO.BAK"), files["HELLO.COM"]);
  assertEquals(
    run.disk.get("HELLO.LIN")!.subarray(0, hello.lineTable!.length),
    hello.lineTable,
  );
  for (const t of ["$DR", "$BY", "$LN", "$$$", "$LT"]) {
    assertEquals(run.disk.has(`HELLO.${t}`), false, t);
  }
  // Z: no backup; K: the intermediates stay.
  run = runCom(blink, { tail: "HELLO [Z,K]", files, ...opts });
  assertEquals(run.disk.has("HELLO.BAK"), false);
  assertEquals(run.disk.has("HELLO.$DR"), true);
  // O=: another name and type.
  run = runCom(blink, { tail: "HELLO [O=OTHER.COM]", files, ...opts });
  assertEquals(run.disk.get("OTHER.COM"), hello.com);
  assertEquals(run.disk.get("HELLO.COM"), files["HELLO.COM"]);
});

Deno.test("a failed link leaves the outputs and removes the temporaries", () => {
  const noStamp = HELLO_DR.slice();
  noStamp[6] = 0;
  noStamp[7] = 0;
  const files = {
    "BASIE.MSG": MSG,
    "CPM22.BRL": library,
    "HELLO.$DR": noStamp,
    "HELLO.$BY": HELLO_BY,
    "HELLO.$LN": HELLO_LN,
    "HELLO.COM": new Uint8Array(128).fill(0x76),
  };
  const run = runCom(blink, { tail: "HELLO", files, maxSteps: 100_000_000 });
  assertEquals(run.output, error(202));
  assertEquals(run.disk.get("HELLO.COM"), files["HELLO.COM"]);
  assertEquals(run.disk.has("HELLO.$DR"), false);
  // A mistyped option is not a link: nothing is deleted.
  const typo = runCom(blink, { tail: "HELLO [Q]", files });
  assertEquals(typo.disk.has("HELLO.$DR"), true);
});

for (const path of PROGRAMS) {
  Deno.test(`BLINK writes the reference's map and symbol file for ${path}`, async () => {
    const { readLibrary } = await import("../ref/object/library.ts");
    const { readNameStream } = await import("../ref/object/streams.ts");
    const { writeMap, writeSymbols } = await import("../ref/link/reports.ts");
    const result = await compile(path);
    if (!result.ok) throw new Error(JSON.stringify(result));
    const lib = readLibrary(library);
    const names = new Map([
      ...readNameStream(lib.names!).names,
      ...readNameStream(result.objects.names).names,
    ]);
    const map = writeMap(result.link, {
      programName: "PROG",
      libraryName: "CPM22.BRL",
      runtimeIdentity: lib.runtimeIdentity,
      profileIdentity: lib.profileIdentity,
      outputKind: ".COM",
      profile: lib.profile,
      names,
    });
    const symbols = writeSymbols(result.link, names);
    const run = runCom(blink, {
      tail: "PROG [M,Y]",
      files: {
        "BASIE.MSG": MSG,
        "CPM22.BRL": library,
        "PROG.$DR": result.objects.directory,
        "PROG.$BY": result.objects.bytes,
        "PROG.$LN": result.objects.lines,
        "PROG.$NM": result.objects.names,
      },
      maxSteps: 300_000_000,
    });
    assertEquals(run.output, "");
    const got = new TextDecoder().decode(
      run.disk.get("PROG.MAP")!.subarray(0, map.length),
    );
    assertEquals(got, map);
    assertEquals(
      run.disk.get("PROG.SYM")!.subarray(0, symbols.length),
      symbols,
    );
  });
}

const {
  readLibrary,
} = await import("../ref/object/library.ts");
const { readNameStream, readLineStream } = await import(
  "../ref/object/streams.ts"
);
const {
  readByteStream,
  readProgramDirectory,
  writeByteStream,
  writeProgramDirectory,
} = await import("../ref/object/program.ts");
const { link } = await import("../ref/link/link.ts");
const { writeMap, writeSymbols } = await import("../ref/link/reports.ts");
const { Form, Kind, Pseudo } = await import("../ref/object/types.ts");
type Objects = {
  directory: Uint8Array;
  bytes: Uint8Array;
  lines: Uint8Array;
  names: Uint8Array;
};

/**
 * Link the objects with BLINK under `tail` and with the reference linker
 * under `rerunnable`, and compare the output file, the line table and, for
 * .COM, the map and the symbol file.
 */
function compareLink(
  objects: Objects,
  tail: string,
  rerunnable: boolean,
  libraryFile = library,
) {
  const lib = readLibrary(libraryFile);
  const dir = readProgramDirectory(objects.directory);
  const lines = readLineStream(objects.lines);
  const hex = tail.includes(".HEX");
  const result = link(lib, dir, readByteStream(objects.bytes).data, {
    rerunnable,
    output: hex ? "hex" : "com",
    byteStreamStamp: dir.header.stamp,
    lines: { stamp: lines.stamp, parts: lines.parts, blobs: lines.blobs },
  });
  const names = new Map([
    ...readNameStream(lib.names!).names,
    ...readNameStream(objects.names).names,
  ]);
  const run = runCom(blink, {
    tail,
    files: {
      "BASIE.MSG": MSG,
      "CPM22.BRL": libraryFile,
      "PROG.$DR": objects.directory,
      "PROG.$BY": objects.bytes,
      "PROG.$LN": objects.lines,
      "PROG.$NM": objects.names,
    },
    maxSteps: 300_000_000,
  });
  assertEquals(run.output, "");
  assertEquals(run.disk.get(hex ? "PROG.HEX" : "PROG.COM"), result.output);
  const table = run.disk.get("PROG.LIN")!;
  assertEquals(table.subarray(0, result.lineTable!.length), result.lineTable);
  if (hex) return result;
  const map = writeMap(result, {
    programName: "PROG",
    libraryName: "CPM22.BRL",
    runtimeIdentity: lib.runtimeIdentity,
    profileIdentity: lib.profileIdentity,
    outputKind: ".COM",
    profile: lib.profile,
    names,
  });
  const got = new TextDecoder().decode(
    run.disk.get("PROG.MAP")!.subarray(0, map.length),
  );
  assertEquals(got, map);
  // Blobs first, then aliases, each in address order (linker §8.2).
  const aliases = new Set(
    [...lib.records, ...dir.records].flatMap((r) =>
      r.type === "alias" ? [r.alias] : []
    ),
  );
  const symbols = writeSymbols(result, names, aliases);
  assertEquals(run.disk.get("PROG.SYM")!.subarray(0, symbols.length), symbols);
  return result;
}

const R_PROGRAMS = [
  "examples/ADVENT.BSI",
  "examples/BUGS.BSI",
  "examples/DUMP.BSI",
  "tests/conformance/basics/hello.bsi",
  "tests/conformance/library/random-numbers.bsi",
  "tests/conformance/storage/lru-cache.bsi",
];

for (const path of R_PROGRAMS) {
  Deno.test(`with option R BLINK matches the reference for ${path}`, async () => {
    const result = await compile(path);
    if (!result.ok) throw new Error(JSON.stringify(result));
    const linked = compareLink(result.objects, "PROG [R,M,Y]", true);
    const data = linked.blobs.filter((b) => b.live && b.kind === Kind.data);
    const p = linked.pseudo.get(Pseudo.DATA)!;
    assertEquals(p.size, data.reduce((n, b) => n + b.size, 0));
  });
}

/**
 * hello.bsi with more blobs: two aligned and two unaligned data blobs whose
 * references reach code, bss, other data and the DATA, DATACOPY, IMAGE and
 * BSS pseudo-objects in every form, and a rodata blob in TEXT that refers to
 * DATA.
 */
function withData(): Objects {
  if (!hello.ok) throw new Error();
  const dir = readProgramDirectory(HELLO_DR);
  const bytes = [...readByteStream(HELLO_BY).data];
  const main = dir.records.find((r) => r.type === "entry")!;
  if (main.type !== "entry") throw new Error();
  let next = Math.max(
    ...dir.records.map((r) => r.type === "blob" ? r.ordinal : 0),
  ) + 1;
  const [a, b, c, d, bss, ro] = [
    next++,
    next++,
    next++,
    next++,
    next++,
    next++,
  ];
  const ref = (offset: number, form: number, target: number, addend = 0) => ({
    offset,
    form: form as 0,
    target,
    addend,
  });
  const blob = (
    kind: number,
    ordinal: number,
    content: number[],
    references: ReturnType<typeof ref>[],
    align = 0,
    root = true,
  ) => {
    if (kind !== Kind.bss) bytes.push(...content);
    return {
      type: "blob" as const,
      kind: kind as 0,
      ordinal,
      size: content.length,
      root,
      align,
      references,
    };
  };
  const added = [
    blob(Kind.data, a, [0, 0, 0, 0, 0, 0, 0, 0, 0x11], [
      ref(0, Form.ABS16, main.ordinal),
      ref(2, Form.ABS16, bss, 2),
      ref(4, Form.ABS16, Pseudo.DATACOPY),
      ref(6, Form.SIZE16, Pseudo.DATA),
    ]),
    blob(Kind.data, b, [0, 0, 0, 0, 0x55], [
      ref(0, Form.LO8, Pseudo.DATA),
      ref(1, Form.HI8, Pseudo.DATACOPY),
      ref(2, Form.ABS16, a, 1),
    ], 3),
    blob(Kind.data, c, [0, 0, 0, 0, 0x77], [
      ref(0, Form.SIZE16, Pseudo.IMAGE),
      ref(2, Form.ABS16, Pseudo.BSS),
    ]),
    blob(Kind.data, d, [0, 0, 0x66], [ref(0, Form.ABS16, ro, 6)], 2),
    blob(Kind.bss, bss, new Array(6).fill(0), [], 0, false),
    blob(Kind.rodata, ro, [0, 0, 0, 0, 0, 0, 0x99], [
      ref(0, Form.ABS16, Pseudo.DATA),
      ref(2, Form.SIZE16, Pseudo.DATACOPY),
      ref(4, Form.ABS16, b),
    ]),
  ];
  const last = dir.records.findLastIndex((r) => r.type === "blob");
  const records = [
    ...dir.records.slice(0, last + 1),
    ...added,
    ...dir.records.slice(last + 1),
  ];
  const stream = Uint8Array.from(bytes);
  return {
    directory: writeProgramDirectory(dir.header, records, stream.length),
    bytes: writeByteStream(dir.header.stamp, stream),
    lines: HELLO_LN,
    names: hello.objects.names,
  };
}

Deno.test("with option R BLINK places DATA and COPY as the reference does", () => {
  const objects = withData();
  const r = compareLink(objects, "PROG [R,M,Y]", true);
  const data = r.pseudo.get(Pseudo.DATA)!;
  const copy = r.pseudo.get(Pseudo.DATACOPY)!;
  // By class: b (8-byte), 3 bytes' padding, d (4-byte), then a and c.
  assertEquals(data.size, 5 + 3 + 3 + 9 + 5);
  assertEquals(copy.address, data.address + data.size);
  assertEquals(copy.size, data.size);
  assertEquals(data.address % 8, 0);
  const first = r.blobs.find((x) => x.address === data.address)!;
  assertEquals(first.padding > 0, true); // TEXT's end rounded up
  // Without R the same blobs stay in TEXT.
  compareLink(objects, "PROG [M,Y]", false);
  // Intel HEX carries COPY too.
  compareLink(objects, "PROG [R,O=PROG.HEX]", true);
});

Deno.test("BLINK refuses a ROM profile (class 3), which it doesn't implement", () => {
  const lib = library.slice();
  lib[42] = 3;
  assertEquals(
    run("HELLO", {
      "BASIE.MSG": MSG,
      "CPM22.BRL": lib,
      "HELLO.$DR": HELLO_DR,
      "HELLO.$BY": HELLO_BY,
      "HELLO.$LN": HELLO_LN,
    }),
    error(206),
  );
});

// ---- faults found by the commentary pass (native/linker/README.md) --------

const { writeNameStream } = await import(
  "../ref/object/streams.ts"
);
type DirRecord = import("../ref/object/types.ts").DirectoryRecord;
type Named = { ordinal: number; name: string };

const reference = (offset: number, form: number, target: number) => ({
  offset,
  form: form as 0,
  target,
  addend: 0,
});

/** A blob record; bss blobs have no bytes in the stream. */
const blobRecord = (
  kind: number,
  ordinal: number,
  size: number,
  references: ReturnType<typeof reference>[] = [],
  root = false,
  align = 0,
): DirRecord => ({
  type: "blob",
  kind: kind as 0,
  ordinal,
  size,
  root,
  align,
  references,
});

const aliasRecord = (
  alias: number,
  base: number,
  offset: number,
): DirRecord => ({
  type: "alias",
  alias,
  base,
  offset,
});

/**
 * hello.bsi with `added` records after its last blob, `bytes` after its
 * byte stream and `names` after its name records.
 */
function extendHello(
  added: DirRecord[],
  bytes: ArrayLike<number> = [],
  names: Named[] = [],
  lines = HELLO_LN,
): Objects {
  const dir = readProgramDirectory(HELLO_DR);
  const last = dir.records.findLastIndex((r) => r.type === "blob");
  const records = [
    ...dir.records.slice(0, last + 1),
    ...added,
    ...dir.records.slice(last + 1),
  ];
  const own = readByteStream(HELLO_BY).data;
  const stream = new Uint8Array(own.length + bytes.length);
  stream.set(own);
  stream.set(Array.from(bytes), own.length);
  const ownNames = [...readNameStream(HELLO_NM).names].map((
    [ordinal, name],
  ) => ({ ordinal, name }));
  return {
    directory: writeProgramDirectory(dir.header, records, stream.length),
    bytes: writeByteStream(dir.header.stamp, stream),
    lines,
    names: writeNameStream(dir.header.stamp, [...ownNames, ...names]),
  };
}

Deno.test("BLINK lists aliases in the map and the symbol file as the reference does", () => {
  // R refers to three aliases of B, two of them at one address, the second
  // by SIZE16 before its ALIAS record; D and its alias are dead. Every name
  // record after an alias's must still reach its blob.
  const [r, b, a1, a2, d, a3, a4, e] = [
    0x401,
    0x402,
    0x403,
    0x404,
    0x405,
    0x406,
    0x407,
    0x408,
  ];
  const objects = extendHello(
    [
      blobRecord(Kind.rodata, r, 6, [
        reference(0, Form.ABS16, a1),
        reference(2, Form.SIZE16, a2),
        reference(4, Form.ABS16, a3),
      ], true),
      blobRecord(Kind.data, b, 8),
      aliasRecord(a1, b, 2),
      aliasRecord(a2, b, 2),
      blobRecord(Kind.data, d, 3),
      aliasRecord(a3, b, 5),
      aliasRecord(a4, d, 1),
      blobRecord(Kind.rodata, e, 2, [], true),
    ],
    new Array(6 + 8 + 3 + 2).fill(0),
    [
      { ordinal: r, name: "reader" },
      { ordinal: b, name: "bee" },
      { ordinal: a1, name: "bee_two" },
      { ordinal: a2, name: "bee_too" },
      { ordinal: d, name: "dee" },
      { ordinal: a3, name: "a_rather_long_alias_name" },
      { ordinal: a4, name: "dee_one" },
      { ordinal: e, name: "eee" },
    ],
  );
  const result = compareLink(objects, "PROG [M,Y]", false);
  assertEquals(result.addresses.get(a2), result.addresses.get(b)! + 2);
});
