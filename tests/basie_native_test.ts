/**
 * BASIE.COM, the native compiler in its CP/M shell (native compiler plan
 * 65.2, 65.2b and 65.5), under the CP/M harness: the command line and its
 * options, the library check, the compilation stamp, source parts read
 * from files, the spool drive, diagnostics, and the chain to BLINK.COM,
 * which the harness runs as CP/M would: the loader BASIE leaves at the top
 * of memory reads BLINK.COM from the harness's disk and starts it. The streams it writes are
 * checked against the reference compiler's by
 * tests/native_equivalence_test.ts; constructs not yet generated are
 * refused with Error 191 (65.4). Diagnostics are printed by the
 * reference's numbers, with their text from BASIE.MSG; the one-shot code
 * is in BASIE.OVL, beside BASIE.COM (step 66).
 */
import { assertEquals, assertNotEquals } from "@std/assert";
import { buildBasie } from "../native/compiler/build.ts";
import { assembleFile, comBytes, runCom } from "./harness/cpm.ts";
import { messageFile } from "../ref/compile/messages.ts";
import { buildRuntime } from "../tools/helpertable.ts";
import { HELPER_KEY, HELPER_VERSION } from "../ref/compile/helpers.ts";
import { compile } from "../ref/compile/index.ts";
import { readLineTable } from "../ref/toolchain/linetable.ts";
import { trapLookup } from "../ref/toolchain/traplookup.ts";

const built = await buildBasie();
const basie = built.com;
/** BASIE.OVL, which goes wherever BASIE.COM does (toolchain §7.3). */
const OVL = built.ovl;
const LIBRARY = (await buildRuntime()).file;

type Files = Record<string, string | Uint8Array>;

/** BASIE's message file, beside it on A:. */
const MSG = messageFile();

/**
 * Run BASIE with the tail and the files, BASIE.MSG on A:, and the CPM22
 * library there too unless `library` is false.
 */
function build(tail: string, files: Files = {}, library = true) {
  const tools: Files = { "BASIE.MSG": MSG, "BASIE.OVL": OVL };
  if (library) tools["CPM22.BRL"] = LIBRARY;
  return runCom(basie, {
    tail,
    files: { ...tools, ...files },
    maxSteps: 50_000_000,
  });
}

function run(tail: string, files: Files = {}) {
  return build(tail, files).output;
}

const USAGE = "Usage: BASIE PART[,PART...] [OPTIONS]\r\n";

const PROGRAM = "var value as u16 = 3\nvar cleared as u8\nsub main()\n" +
  "value = value * 2\nend\n";

const MAIN = { "MAIN.BSI": PROGRAM };

/** The bad-option report of the reference's L-COMMAND, as BLINK prints it. */
const bad = (word: string) =>
  `Error 224: ${word}: a bad or repeated option\r\n`;

/** A file not found (L-MISSING), as BLINK reports one. */
const missing = (name: string) => `Error 225: ${name} not found\r\n`;

/** NAME's diagnostic that `value` is not declared, at line 2 and column. */
const undeclared = (name: string, column: number) =>
  `${name}.BSI 2:${column}: 27: value is not declared\r\n`;

Deno.test("BASIE with no part prints its usage", () => {
  assertEquals(run(""), USAGE);
  assertEquals(run("[K]"), USAGE);
  assertEquals(run("TOOLONGNAME"), USAGE);
  assertEquals(run("MAIN;"), USAGE);
  // A comma must be followed by a part, and a dot by a type.
  for (const tail of ["MAIN,", "MAIN, ", "MAIN,[K]", "MAIN.", "MAIN. [K]"]) {
    assertEquals(run(tail, MAIN), USAGE, tail);
  }
  // A malformed command line is a source error to CP/M 3 (toolchain §5.4).
  assertEquals(build("").returnCode, 0xff11);
});

Deno.test("a failed build deletes A:$$$.SUB; a good one leaves it", () => {
  const files = { "$$$.SUB": "x", ...MAIN };
  let result = build("MAIN [C]", files);
  assertEquals(result.disk.has("$$$.SUB"), true);
  assertEquals(result.returnCode, undefined);
  result = build("OTHER", files);
  assertEquals(result.disk.has("$$$.SUB"), false);
  assertEquals(result.returnCode, 0xff11);
});

Deno.test("a failed compilation deletes its streams unless K keeps them", () => {
  const streams = ["$DR", "$BY", "$LN", "$NM"].map((t) => `MAIN.${t}`);
  const bad = { "MAIN.BSI": "sub main()\nvalue = 1\nend\n" };
  // A stale stream from an earlier build goes too.
  const stale = { ...bad, "MAIN.$NM": "old" };
  let result = build("MAIN [M]", stale);
  assertEquals(result.output, undeclared("MAIN", 1));
  assertEquals(result.returnCode, 0xff11);
  for (const name of streams) assertEquals(result.disk.has(name), false, name);
  result = build("MAIN [M,K]", bad);
  for (const name of streams) assertEquals(result.disk.has(name), true, name);
  // A good build keeps its streams.
  result = build("MAIN [M,C]", MAIN);
  for (const name of streams) assertEquals(result.disk.has(name), true, name);
});

Deno.test("BASIE reports a part it can't find", () => {
  assertEquals(run("MAIN"), missing("MAIN.BSI"));
  assertEquals(run("B:MAIN"), missing("B:MAIN.BSI"));
  assertEquals(run("MAIN.TXT", MAIN), missing("MAIN.TXT"));
});

Deno.test("BASIE compiles a program from a file", () => {
  assertEquals(run("MAIN [C]", MAIN), "");
  assertEquals(run("MAIN.BSI [M,C]", MAIN), "");
  // CR LF lines, and the end of file marked by $1A within the last record.
  const crlf = PROGRAM.replaceAll("\n", "\r\n") + "\x1a\x1a";
  assertEquals(run("MAIN [C]", { "MAIN.BSI": crlf }), "");
});

Deno.test("BASIE compiles a program of several parts", () => {
  const files = {
    "DATA.BSI": "var result as u8\n",
    "MAIN.BSI": "sub main()\nresult = 12\nend\n",
  };
  assertEquals(run("DATA, MAIN [C]", files), "");
  assertEquals(
    run("MAIN,DATA", files),
    "MAIN.BSI 2:1: 27: result is not declared\r\n",
  );
  const later = { ...files, "MAIN.BSI": "sub main()\nresult = missing\nend\n" };
  assertEquals(
    run("DATA,MAIN", later),
    "MAIN.BSI 2:10: 27: missing is not declared\r\n",
  );
});

// ---- 67a: include ------------------------------------------------------------

/** The names of the parts a build's line stream records, in order. */
function partsOf(lines: Uint8Array): string[] {
  const names: string[] = [];
  let at = 8; // after the magic, version and stamp
  while (lines[at] === 1) {
    const length = lines[at + 2];
    names.push(new TextDecoder().decode(lines.slice(at + 3, at + 3 + length)));
    at += 3 + length;
  }
  return names;
}

Deno.test("BASIE loads the parts a part includes, each once, before it", () => {
  const files = {
    "MAIN.BSI": 'include "LIB.BSI"\ninclude "BASE.BSI"\nsub main()\n' +
      "result = twice(3)\nend\n",
    "LIB.BSI": '// The library.\ninclude "BASE.BSI"\n\n' +
      "sub twice(n as u8) as u8\nreturn n + n + base\nend\n",
    "BASE.BSI": "var result as u8\nconst base = 0\n",
  };
  const result = build("MAIN [C,K]", files);
  assertEquals(result.output, "");
  assertEquals(partsOf(result.disk.get("MAIN.$LN")!), [
    "BASE.BSI",
    "LIB.BSI",
    "MAIN.BSI",
  ]);
  // A part the command line names that an earlier part included is
  // compiled once (spec 4.3.2, rule 4).
  const again = build("MAIN,BASE [C,K]", files);
  assertEquals(again.output, "");
  assertEquals(partsOf(again.disk.get("MAIN.$LN")!).length, 3);
});

Deno.test("an include is looked for on its part's drive, then on L's or A:", () => {
  const main = 'include "LIB.BSI"\nsub main()\nresult = 1\nend\n';
  const lib = "var result as u8\n";
  // On the including part's drive first,
  assertEquals(
    run("B:MAIN [C]", { "B:MAIN.BSI": main, "B:LIB.BSI": lib }),
    "",
  );
  // then on A:,
  assertEquals(run("B:MAIN [C]", { "B:MAIN.BSI": main, "LIB.BSI": lib }), "");
  // or on option L's drive instead of A:,
  assertEquals(
    run("B:MAIN [C,L=C]", {
      "B:MAIN.BSI": main,
      "C:LIB.BSI": lib,
      "C:CPM22.BRL": LIBRARY,
    }),
    "",
  );
  assertEquals(
    run("B:MAIN [C,L=C]", {
      "B:MAIN.BSI": main,
      "LIB.BSI": lib,
      "C:CPM22.BRL": LIBRARY,
    }),
    "B:MAIN.BSI 1:9: 23: LIB.BSI not found\r\n",
  );
  // and with a drive, there alone.
  assertEquals(
    run("MAIN [C]", {
      "MAIN.BSI": main.replace("LIB.BSI", "D:LIB.BSI"),
      "D:LIB.BSI": lib,
    }),
    "",
  );
  assertEquals(
    run("MAIN [C]", {
      "MAIN.BSI": main.replace("LIB.BSI", "D:LIB.BSI"),
      "LIB.BSI": lib,
    }),
    "MAIN.BSI 1:9: 23: LIB.BSI not found\r\n",
  );
});

Deno.test("includes open at once are counted, the parts by the line stream's byte", () => {
  // A chain of includes 16 deep loads; 17 deep is the capacity.
  const chain = (depth: number) => {
    const files: Files = {};
    for (let i = 0; i < depth; i++) {
      files[`P${i}.BSI`] = `include "P${i + 1}.BSI"\n`;
    }
    files[`P${depth}.BSI`] = "sub main()\nend\n";
    return files;
  };
  assertEquals(run("P0 [C]", chain(16)), "");
  assertEquals(
    run("P0 [C]", chain(17)),
    "P16.BSI 1:9: 190: A compiler capacity was exceeded: include depth\r\n",
  );
});

Deno.test("BASIE reports a diagnostic with its part, line and column", () => {
  const files = { "MAIN.BSI": "sub main()\n    value = 1\nend\n" };
  assertEquals(run("MAIN", files), undeclared("MAIN", 5));
  const parts = [..."ABCDEFGHI"];
  const empty = Object.fromEntries(parts.map((p) => [`${p}.BSI`, "\n"]));
  assertEquals(
    run(parts.join(","), empty),
    "Error 190: A compiler capacity was exceeded: source parts\r\n",
  );
});

Deno.test("without BASIE.MSG a diagnostic is its number and arguments", () => {
  const bare = (tail: string, files: Files) =>
    runCom(basie, {
      tail,
      files: { "CPM22.BRL": LIBRARY, "BASIE.OVL": OVL, ...files },
      maxSteps: 50_000_000,
    }).output;
  const files = { "MAIN.BSI": "sub main()\n    value = 1\nend\n" };
  assertEquals(
    bare("MAIN", files),
    "MAIN.BSI 2:5: 27: Message 27: value\r\n",
  );
  assertEquals(bare("OTHER", files), "Error 225: Message 225: OTHER.BSI\r\n");
  assertEquals(bare("MAIN [Q]", files), "Error 224: Message 224: Q\r\n");
  // A file that is not a message file is no message file.
  assertEquals(
    bare("OTHER", { ...files, "BASIE.MSG": "not a message file" }),
    "Error 225: Message 225: OTHER.BSI\r\n",
  );
  // It is looked for on L's drive, then on A:.
  assertEquals(
    bare("OTHER [L=B]", { ...files, "B:BASIE.MSG": MSG }),
    missing("OTHER.BSI"),
  );
  assertEquals(
    bare("OTHER [L=B]", { ...files, "BASIE.MSG": MSG }),
    missing("OTHER.BSI"),
  );
  assertEquals(
    bare("OTHER [L=B]", { ...files, "C:BASIE.MSG": MSG }),
    "Error 225: Message 225: OTHER.BSI\r\n",
  );
});

Deno.test("expressions nest 32 deep, the stack's bound, and deeper is a capacity", () => {
  // Each level of parentheses takes about 24 bytes of the stack (1.125K
  // since 68); the spec's minimum is 32 (limits §5.1). Unchecked, 48
  // levels ran into the part table below the stack.
  const nested = (n: number) =>
    `sub main()\n    var x as u16\n    x = ${"(".repeat(n)}x${
      " + 1)".repeat(n)
    }\nend\n`;
  assertEquals(run("MAIN [C]", { "MAIN.BSI": nested(32) }), "");
  // Nested to the right, each level keeps its left operand on the operand
  // stack (32 entries since 68) as well as the machine stack.
  const right = (n: number) =>
    `sub main()\n    var x as u16\n    x = ${"x + (".repeat(n)}x${
      ")".repeat(n)
    }\nend\n`;
  assertEquals(run("MAIN [C]", { "MAIN.BSI": right(32) }), "");
  assertEquals(
    run("MAIN", { "MAIN.BSI": nested(100) }),
    "MAIN.BSI 3:48: 190: A compiler capacity was exceeded: expression depth\r\n",
  );
});

Deno.test("statements nest 32 deep, and deeper is a capacity", () => {
  // The spec's minimum is 32 (limits §5.1): the control frames, the
  // grammar stack and the labels hold 32 nested whiles (16 until 68).
  const nested = (n: number) => {
    let body = "        n = n + 1\n";
    for (let i = n; i > 0; i--) {
      body = `${"    ".repeat(i)}while n < ${i}\n${body}${
        "    ".repeat(i)
      }end\n`;
    }
    return `var n as u8\nsub main()\n${body}end\n`;
  };
  assertEquals(run("MAIN [C]", { "MAIN.BSI": nested(32) }), "");
  assertEquals(
    run("MAIN", { "MAIN.BSI": nested(33) }),
    "MAIN.BSI 35:133: 190: A compiler capacity was exceeded: nesting\r\n",
  );
});

Deno.test("the source and the part table may fill memory to the stack below the BDOS entry", () => {
  // The harness's BDOS entry is $E406, so the source runs up from MM_SRC
  // and the part table down from MM_STACK bytes below it, 21 bytes a part
  // (1.125K since 68, for 32 nested expressions); each record must
  // fit below the table before it is read, which bounds the loader. The
  // symbol table and the name heap share the memory above the largest part
  // (67h.3), so a part a record smaller than the loader's bound leaves them
  // room; one byte past the bound is the loader's capacity.
  const top = 0xe406 - built.symbols.MM_STACK;
  const bound = Math.floor((top - 21 - built.symbols.MM_SRC) / 128) * 128;
  const room = bound - 128;
  const fill = (size: number) => {
    let text = PROGRAM;
    while (text.length < size - 70) text += "// " + "x".repeat(60) + "\n";
    return text + "//" + "x".repeat(size - text.length - 3) + "\n";
  };
  assertEquals(fill(room).length, room);
  assertEquals(run("MAIN [C]", { "MAIN.BSI": fill(room) }), "");
  assertEquals(
    run("MAIN", { "MAIN.BSI": fill(bound + 1) }),
    "Error 190: A compiler capacity was exceeded: source size\r\n",
  );
});

// ---- 65.2b: options, the library check and the stamp ----------------------

Deno.test("BASIE accepts every option of toolchain §5.3, in any case", () => {
  const all = "[C, K, M,Y,N,R,B,Z,V,P=CPM22,L=A,S=A,O=B:PROG.HEX,F=255," +
    "STACK=65535]";
  assertEquals(run(`MAIN ${all}`, MAIN), "");
  for (const o of ["O=PROG", "O=PROG.COM", "O=PROG.BIN", "F=1", "STACK=1"]) {
    assertEquals(run(`MAIN [${o},C]`, MAIN), "", o);
  }
  // The CP/M 3 CCP leaves the tail's case alone; BASIE reads it in any.
  const result = build("main [m , k,c]", MAIN);
  assertEquals(result.output, "");
  assertEquals(result.disk.has("MAIN.$NM"), true);
  // X links only: nothing is compiled, and BLINK, not on this disk, is run.
  const linked = build("MAIN [X]", MAIN);
  assertEquals(linked.output, missing("BLINK.COM"));
  assertEquals(linked.disk.has("MAIN.$DR"), false);
});

Deno.test("BASIE refuses a bad, repeated or misplaced option as BLINK does", () => {
  const cases: [string, string][] = [
    ["MAIN [Q]", bad("Q")],
    ["MAIN [W]", bad("W")],
    ["MAIN [M,M]", bad("M")],
    ["MAIN [C,X]", bad("X")],
    ["MAIN [KM]", bad("KM")],
    ["MAIN [K=1]", bad("K=1")],
    ["MAIN [P]", bad("P")],
    ["MAIN [S=Q]", bad("S=Q")],
    ["MAIN [L=]", bad("L=")],
    ["MAIN [L=AB]", bad("L=AB")],
    ["MAIN [S=B,S=C]", bad("S=C")],
    ["MAIN [P=]", bad("P=")],
    ["MAIN [P=A:LIB]", bad("P=A:LIB")],
    ["MAIN [P=LIB.BRL]", bad("P=LIB.BRL")],
    ["MAIN [P=TOOLONGLIB]", bad("P=TOOLONGLIB")],
    ["MAIN [O=]", bad("O=")],
    ["MAIN [O=PROG.TXT]", bad("O=PROG.TXT")],
    ["MAIN [O=Q:PROG]", bad("O=Q:PROG")],
    ["MAIN [F=0]", bad("F=0")],
    ["MAIN [F=256]", bad("F=256")],
    ["MAIN [F=X]", bad("F=X")],
    ["MAIN [STACK=0]", bad("STACK=0")],
    ["MAIN [STACK=65536]", bad("STACK=65536")],
    ["MAIN [STACK=000001]", bad("STACK=000001")],
    ["MAIN [STAK=1]", bad("STAK=1")],
    ["MAIN [T=]", bad("T=")],
    ["MAIN [T=12345]", bad("T=12345")],
    ["MAIN [T=G]", bad("T=G")],
    ["MAIN [T=1A3F,M]", bad("T=1A3F")],
    ["MAIN [M,T=1A3F]", bad("T=1A3F")],
    ["MAIN [K", bad("")],
    ["MAIN [K;M]", bad("K;M")],
    ["MAIN [K] X", bad("X")],
    ["MAIN [,K]", bad("")],
  ];
  for (const [tail, report] of cases) {
    const result = build(tail, MAIN);
    assertEquals(result.output, report, tail);
    assertEquals(result.returnCode, 0xff11, tail);
    assertEquals(result.disk.has("MAIN.$DR"), false, tail);
  }
});

/** A program that traps, compiled and linked by the reference. */
const TRAPPING = "var cells as u8[4]\nvar i as u8\nsub main()\n" +
  "    i = 9\n  cells[i] = 1\nend\n";
const linked = await compile("MAIN.BSI", {
  mainSource: new TextEncoder().encode(TRAPPING),
});
if (!linked.ok) throw new Error("the trapping program didn't compile");
const LOOKUP: Record<string, Uint8Array> = {
  "MAIN.BSI": new TextEncoder().encode(TRAPPING),
  "MAIN.COM": linked.com,
  "MAIN.LIN": linked.lineTable!,
};

/** BASIE's lookup of an address, and the reference's, for the files. */
function lookedUp(address: number, files: Record<string, Uint8Array>) {
  const hex = address.toString(16).toUpperCase();
  const native = build(`MAIN [T=${hex}]`, files);
  const want = trapLookup("MAIN", address, (f) => files[f]);
  return { native, want };
}

Deno.test("BASIE [T=hhhh] looks an address up as the reference does", () => {
  const table = readLineTable(linked.lineTable!);
  const addresses = new Set<number>([0, 0xffff]);
  for (const e of table.entries) {
    addresses.add(e.address);
    addresses.add(e.address + 1);
  }
  for (const address of addresses) {
    const { native, want } = lookedUp(address, LOOKUP);
    assertEquals(native.output, want.text, address.toString(16));
    assertEquals(native.returnCode === 0xff01, want.failed);
  }
  // The table as CP/M stores it, padded to a whole record, reads the same.
  const lin = LOOKUP["MAIN.LIN"];
  const padded = new Uint8Array(Math.ceil(lin.length / 128) * 128).fill(0x1a);
  padded.set(lin);
  for (const address of [...addresses].slice(0, 6)) {
    const { native, want } = lookedUp(address, {
      ...LOOKUP,
      "MAIN.LIN": padded,
    });
    assertEquals(want.failed, false);
    assertEquals(native.output, want.text, address.toString(16));
  }
  // A statement's own line, from its column on.
  const at = table.entries.find((e) => e.part === 0 && e.source === 5)!;
  assertEquals(
    lookedUp(at.address, LOOKUP).native.output,
    "MAIN.BSI 5:3  cells[i] = 1\r\n",
  );
  // Without the source the position alone.
  const { "MAIN.BSI": _, ...noSource } = LOOKUP;
  assertEquals(
    lookedUp(at.address, noSource).native.output,
    "MAIN.BSI 5:3\r\n",
  );
});

Deno.test("BASIE [T=hhhh] refuses a missing, damaged or stale line table", () => {
  const damaged = LOOKUP["MAIN.LIN"].slice();
  damaged[damaged.length - 1] ^= 1;
  const stale = LOOKUP["MAIN.COM"].slice();
  stale[3] ^= 1;
  const { "MAIN.COM": _c, ...noProgram } = LOOKUP;
  const { "MAIN.LIN": _l, ...noTable } = LOOKUP;
  const cases: [Record<string, Uint8Array>, string][] = [
    [noTable, "MAIN.LIN not found"],
    [{ ...LOOKUP, "MAIN.LIN": damaged }, "MAIN.LIN is damaged"],
    [{ ...LOOKUP, "MAIN.COM": stale }, "MAIN.LIN doesn't match the program"],
    [noProgram, "MAIN.COM not found"],
  ];
  for (const [files, text] of cases) {
    const { native, want } = lookedUp(0x0100, files);
    assertEquals(want.text, text + "\r\n");
    assertEquals(native.output, want.text, text);
    assertNotEquals(native.returnCode, 0);
  }
  // T joins only L.
  assertEquals(
    run("MAIN [L=B, T=100]", LOOKUP),
    lookedUp(0x100, LOOKUP).want.text,
  );
});

/** The library with its bytes at offset changed. */
function patched(at: number, ...bytes: number[]) {
  const copy = LIBRARY.slice();
  copy.set(bytes, at);
  return copy;
}

/** The key table's offset in the library. */
const KEYS = new DataView(LIBRARY.buffer).getUint32(32, true);

Deno.test("BASIE reads the library before any source, and refuses one it doesn't suit", () => {
  // The library is checked first: its absence is reported before the
  // missing part's.
  assertEquals(build("MAIN", {}, false).output, missing("CPM22.BRL"));
  assertEquals(build("MAIN", MAIN, false).returnCode, 0xff11);
  assertEquals(run("MAIN [P=OTHER]", MAIN), missing("OTHER.BRL"));
  const format = "Error 200: CPM22.BRL: bad magic or unsupported version\r\n";
  const compat = "Error 201: Program and library are not compatible\r\n";
  const short =
    "Error 214: CPM22.BRL: missing trailer, bad CRC or wrong length\r\n";
  const cases: [Uint8Array, string][] = [
    [patched(0, 0x42, 0x53, 0x49, 0x50), format], // BSIP, a program directory
    [patched(4, 2), format], // major version 2
    [patched(5, 1), format], // minor version 1
    [patched(8, HELPER_VERSION - 1, 0), compat], // an older helper table
    [patched(KEYS, HELPER_VERSION - 1, 0), compat], // a key short
    [patched(KEYS + 2 * HELPER_VERSION, ~HELPER_KEY & 0xff), compat],
    [LIBRARY.slice(0, 128), short], // the key table missing
    [new Uint8Array(0), short], // an empty file
  ];
  for (const [library, report] of cases) {
    const result = build("MAIN", { ...MAIN, "CPM22.BRL": library }, false);
    assertEquals(result.output, report);
    assertEquals(result.disk.has("MAIN.$DR"), false);
  }
  // A later helper table that keeps the compiler's version's key suits it.
  const later = patched(8, HELPER_VERSION + 1, 0);
  later.set([HELPER_VERSION + 1, 0], KEYS);
  later.set([0x34, 0x12], KEYS + 2 + 2 * HELPER_VERSION);
  assertEquals(run("MAIN [C]", { ...MAIN, "CPM22.BRL": later }), "");
  // P names another library, with the same rules.
  assertEquals(run("MAIN [P=MINE,C]", { ...MAIN, "MINE.BRL": LIBRARY }), "");
});

Deno.test("BASIE takes the identities of the library for the directory", () => {
  const library = patched(6, 7, 0);
  library.set([9, 0], 10);
  const result = build("MAIN [C]", { ...MAIN, "CPM22.BRL": library }, false);
  assertEquals(result.output, "");
  const header = result.disk.get("MAIN.$DR")!;
  const word = (at: number) => header[at] | (header[at + 1] << 8);
  assertEquals(word(8), 7); // runtime identity, from the library
  assertEquals(word(10), HELPER_VERSION); // compiled in
  assertEquals(word(12), HELPER_KEY);
  assertEquals(word(14), 9); // profile identity, from the library
});

Deno.test("BASIE looks for the library on L's drive or the first part's, then A:", () => {
  const onB = { "B:MAIN.BSI": PROGRAM };
  // On the first part's drive,
  assertEquals(
    build("B:MAIN [C]", { ...onB, "B:CPM22.BRL": LIBRARY }, false)
      .output,
    "",
  );
  // and then on A:;
  assertEquals(
    build("B:MAIN [C]", { ...onB, "CPM22.BRL": LIBRARY }, false)
      .output,
    "",
  );
  assertEquals(
    build("B:MAIN", { ...onB, "C:CPM22.BRL": LIBRARY }, false).output,
    missing("CPM22.BRL"),
  );
  // on L's drive, and then on A:.
  assertEquals(
    build("MAIN [L=C,C]", { ...MAIN, "C:CPM22.BRL": LIBRARY }, false)
      .output,
    "",
  );
  assertEquals(run("MAIN [L=C,C]", MAIN), "");
  assertEquals(
    build("MAIN [L=C]", { ...MAIN, "B:CPM22.BRL": LIBRARY }, false).output,
    missing("CPM22.BRL"),
  );
});

Deno.test("BASIE writes the streams on the spool drive, with the first part's name", () => {
  const streams = ["$DR", "$BY", "$LN", "$NM"];
  let result = build("B:MAIN,C:MORE [M,C]", {
    "B:MAIN.BSI": "var x as u8\n",
    "C:MORE.BSI": "sub main()\nx = 1\nend\n",
  });
  assertEquals(result.output, "");
  for (const t of streams) assertEquals(result.disk.has(`B:MAIN.${t}`), true);
  result = build("MAIN [M,S=D,C]", MAIN);
  assertEquals(result.output, "");
  for (const t of streams) {
    assertEquals(result.disk.has(`D:MAIN.${t}`), true, t);
    assertEquals(result.disk.has(`MAIN.${t}`), false, t);
  }
  // A failure deletes them there, unless K keeps them.
  const wrong = { "MAIN.BSI": "sub main()\nvalue = 1\nend\n" };
  result = build("MAIN [M,S=D]", { ...wrong, "D:MAIN.$LN": "old" });
  for (const t of streams) assertEquals(result.disk.has(`D:MAIN.${t}`), false);
  result = build("MAIN [M,S=D,K]", wrong);
  for (const t of streams) assertEquals(result.disk.has(`D:MAIN.${t}`), true);
});

Deno.test("BASIE chooses each compilation's stamp as object format §4.1 asks", () => {
  const stamp = (disk: Map<string, Uint8Array>, name = "MAIN.$DR") => {
    const header = disk.get(name)!;
    return header[6] | (header[7] << 8);
  };
  // With no earlier directory, a stamp from the source, never zero; every
  // stream carries it.
  let result = build("MAIN [M,C]", MAIN);
  const first = stamp(result.disk);
  assertNotEquals(first, 0);
  for (const t of ["$BY", "$LN", "$NM"]) {
    assertEquals(stamp(result.disk, `MAIN.${t}`), first, t);
  }
  // An earlier directory's stamp, plus one, skipping zero.
  for (const [old, next] of [[41, 42], [0xfffe, 0xffff], [0xffff, 1]]) {
    const header = result.disk.get("MAIN.$DR")!.slice();
    header.set([old & 0xff, old >> 8], 6);
    const again = build("MAIN [C]", { ...MAIN, "MAIN.$DR": header });
    assertEquals(stamp(again.disk), next, `after ${old}`);
  }
  // The earlier directory is looked for on the spool drive.
  const header = result.disk.get("MAIN.$DR")!.slice();
  header.set([0x10, 0x20], 6);
  result = build("MAIN [S=B,C]", { ...MAIN, "B:MAIN.$DR": header });
  assertEquals(stamp(result.disk, "B:MAIN.$DR"), 0x2011);
  // A file of that name that is no directory is ignored.
  result = build("MAIN [C]", { ...MAIN, "MAIN.$DR": "not a directory" });
  assertNotEquals(stamp(result.disk), 0);
});

// ---- 65.5: the chain to BLINK ---------------------------------------------

const BLINK = comBytes(await assembleFile("native/linker/BLINK.ASM"));
const HELLO = Deno.readFileSync("tests/conformance/basics/hello.bsi");

/** Run BASIE, and BLINK after it, with BLINK.COM and BASIE.MSG on A:. */
function chain(tail: string, files: Files = {}, tools = true) {
  return runCom(basie, {
    tail,
    files: tools
      ? {
        "CPM22.BRL": LIBRARY,
        "BLINK.COM": BLINK,
        "BASIE.MSG": MSG,
        "BASIE.OVL": OVL,
        ...files,
      }
      : files,
    maxSteps: 400_000_000,
  });
}

/** The output of a .COM file run under the harness. */
const output = (com: Uint8Array) => runCom(com).output;

const STREAMS = ["$DR", "$BY", "$LN", "$NM"];

Deno.test("BASIE HELLO compiles and links HELLO.COM, which prints Hello", () => {
  const result = chain("HELLO", { "HELLO.BSI": HELLO });
  assertEquals(result.output, "");
  assertEquals(result.returnCode, 0);
  assertEquals(output(result.disk.get("HELLO.COM")!), "Hello\r\n");
  assertEquals(result.disk.has("HELLO.LIN"), true);
  // BLINK deletes the intermediate files once it has published the program.
  for (const t of STREAMS) assertEquals(result.disk.has(`HELLO.${t}`), false);
  // Several parts: the program and its files take the first part's name.
  const parts = chain("DATA, MAIN", {
    "DATA.BSI": "var x as u8 = 72\n",
    "MAIN.BSI": "sub main() fails\nwriteByte(console, x) else fail\nend\n",
  });
  assertEquals(parts.output, "");
  assertEquals(output(parts.disk.get("DATA.COM")!), "H");
});

Deno.test("a failed build never runs BLINK", () => {
  const result = chain("HELLO", {
    "HELLO.BSI": "sub main()\nvalue = 1\nend\n",
  });
  assertEquals(result.output, undeclared("HELLO", 1));
  assertEquals(result.returnCode, 0xff11);
  assertEquals(result.disk.has("HELLO.COM"), false);
  for (const t of STREAMS) assertEquals(result.disk.has(`HELLO.${t}`), false);
});

Deno.test("BASIE passes BLINK's options through the chain", () => {
  const files = { "HELLO.BSI": HELLO };
  // K keeps the intermediate files, for BLINK as for BASIE.
  let result = chain("HELLO [M, K]", files);
  assertEquals(result.output, "");
  for (const t of STREAMS) assertEquals(result.disk.has(`HELLO.${t}`), true);
  assertEquals(result.disk.has("HELLO.MAP"), true);
  // A program already there becomes HELLO.BAK, unless Z.
  const old = { ...files, "HELLO.COM": "old" };
  result = chain("HELLO", old);
  assertEquals(new TextDecoder().decode(result.disk.get("HELLO.BAK")), "old");
  result = chain("HELLO [Z]", old);
  assertEquals(result.disk.has("HELLO.BAK"), false);
  assertEquals(output(result.disk.get("HELLO.COM")!), "Hello\r\n");
  // O= names the output, its drive and its kind.
  result = chain("HELLO [O=B:WORLD.HEX,Y]", files);
  assertEquals(result.output, "");
  assertEquals(result.disk.has("HELLO.COM"), false);
  assertEquals(result.disk.has("B:WORLD.HEX"), true);
  assertEquals(result.disk.has("B:WORLD.SYM"), true);
  // N: no line stream, so no line table.
  result = chain("HELLO [N]", files);
  assertEquals(result.disk.has("HELLO.LIN"), false);
  assertEquals(output(result.disk.get("HELLO.COM")!), "Hello\r\n");
  // S puts the intermediate files on the spool drive, where BLINK finds them.
  result = chain("hello [s=c]", files);
  assertEquals(result.output, "");
  assertEquals(output(result.disk.get("HELLO.COM")!), "Hello\r\n");
  for (const t of STREAMS) assertEquals(result.disk.has(`C:HELLO.${t}`), false);
});

Deno.test("C compiles only and X links only", () => {
  let result = chain("HELLO [C]", { "HELLO.BSI": HELLO });
  assertEquals(result.output, "");
  assertEquals(result.disk.has("HELLO.COM"), false);
  const kept: Files = {};
  for (const t of ["$DR", "$BY", "$LN"]) {
    kept[`HELLO.${t}`] = result.disk.get(`HELLO.${t}`)!;
  }
  // X, as running BLINK directly, needs no source.
  result = chain("HELLO [X,K]", kept);
  assertEquals(result.output, "");
  assertEquals(output(result.disk.get("HELLO.COM")!), "Hello\r\n");
  for (const t of ["$DR", "$BY", "$LN"]) {
    assertEquals(result.disk.has(`HELLO.${t}`), true);
  }
  result = chain("HELLO [X]", {});
  assertEquals(result.output, "Error 225: HELLO.$DR not found\r\n");
});

Deno.test("BASIE looks for BLINK.COM on L's drive or the current one, then A:", () => {
  const files = {
    "HELLO.BSI": HELLO,
    "CPM22.BRL": LIBRARY,
    "BASIE.MSG": MSG,
    "BASIE.OVL": OVL,
  };
  let result = chain("HELLO [L=B]", { ...files, "B:BLINK.COM": BLINK }, false);
  assertEquals(result.output, "");
  assertEquals(output(result.disk.get("HELLO.COM")!), "Hello\r\n");
  result = chain("HELLO [L=B]", { ...files, "BLINK.COM": BLINK }, false);
  assertEquals(result.output, "");
  // Without it, the streams stay for a later BLINK.
  result = chain("HELLO", files, false);
  assertEquals(result.output, missing("BLINK.COM"));
  assertEquals(result.returnCode, 0xff12);
  for (const t of ["$DR", "$BY", "$LN"]) {
    assertEquals(result.disk.has(`HELLO.${t}`), true);
  }
});

// ---- 66: the overlays ------------------------------------------------------

Deno.test("BASIE loads its overlays from BASIE.OVL on the current drive, then A:", () => {
  const plain = (files: Files) =>
    runCom(basie, {
      tail: "MAIN [C]",
      files: { "CPM22.BRL": LIBRARY, "BASIE.MSG": MSG, ...MAIN, ...files },
      maxSteps: 50_000_000,
    });
  assertEquals(plain({ "BASIE.OVL": OVL }).output, "");
  // The command line, option L included, is an overlay: BASIE.OVL is
  // looked for before it is read, on the current drive and then A:.
  const missing = "Error 225: Message 225: BASIE.OVL\r\n";
  const result = plain({});
  assertEquals(result.output, missing);
  assertEquals(result.returnCode, 0xff11);
  assertEquals(plain({ "B:BASIE.OVL": OVL }).output, missing);
  // An overlay file that belongs to another BASIE.COM is not used: its sum
  // of the resident image differs.
  const other = OVL.slice();
  other[6] ^= 1;
  assertEquals(plain({ "BASIE.OVL": other }).output, missing);
  const truncated = OVL.slice(0, 256);
  assertEquals(plain({ "BASIE.OVL": truncated }).output, missing);
});

Deno.test("BASIE.OVL describes every overlay, each loaded when first needed", () => {
  assertEquals([...OVL.subarray(0, 6)], [0x42, 0x53, 0x49, 0x4f, 1, 0]);
  const sum = basie.reduce((s, b) => (s + b) & 0xffff, 0);
  assertEquals(OVL[6] | (OVL[7] << 8), sum);
  assertEquals(OVL[8], built.overlays.length);
  const names = built.overlays.find((o) => o.name === "NAMES")!;
  for (const [i, o] of built.overlays.entries()) {
    const e = 9 + 4 * i;
    // FLOAT and OWNERS load above NAMES, from NAMES' last byte, since
    // NAMES stays while they are used; every other overlay at the area's
    // start.
    const at = ["FLOAT", "OWNERS"].includes(o.name)
      ? built.area + names.bytes.length
      : built.area;
    assertEquals(OVL[e] | (OVL[e + 1] << 8), at, o.name);
    const first = OVL[e + 2], records = OVL[e + 3];
    assertEquals(records, Math.ceil(o.bytes.length / 128), o.name);
    assertEquals(
      OVL.subarray(first * 128, first * 128 + o.bytes.length),
      o.bytes,
    );
  }
  // The area ends where the overlay that reaches furthest ends, in whole
  // records: FLOAT, above NAMES.
  const end = Math.max(
    ...built.overlays.map((o) => o.address + o.records * 128),
  );
  assertEquals(built.areaSize, end - built.area);
});
