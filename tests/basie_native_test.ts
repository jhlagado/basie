/**
 * BASIE.COM, the native compiler in its CP/M shell (native compiler plan
 * 65.2 and 65.2b), under the CP/M harness: the command line and its
 * options, the library check, the compilation stamp, source parts read
 * from files, the spool drive, and diagnostics. The streams it writes are
 * checked against the reference compiler's by
 * tests/native_equivalence_test.ts; constructs not yet generated are
 * refused with Error 95 (65.4).
 */
import { assertEquals, assertNotEquals } from "@std/assert";
import { buildBasie } from "../native/compiler/build.ts";
import { runCom } from "./harness/cpm.ts";
import { buildRuntime } from "../tools/helpertable.ts";
import { HELPER_KEY, HELPER_VERSION } from "../ref/compile/helpers.ts";

const basie = (await buildBasie()).com;
const LIBRARY = (await buildRuntime()).file;

type Files = Record<string, string | Uint8Array>;

/** Run BASIE with the tail and the files, the CPM22 library on A: too. */
function build(tail: string, files: Files = {}, library = true) {
  return runCom(basie, {
    tail,
    files: library ? { "CPM22.BRL": LIBRARY, ...files } : files,
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

/** The bad-option report of the reference's L-COMMAND. */
const bad = (word: string) => `${word}: a bad or repeated option\r\n`;

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
  let result = build("MAIN", files);
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
  assertEquals(result.output, "MAIN.BSI 2:1 Error 57\r\n");
  assertEquals(result.returnCode, 0xff11);
  for (const name of streams) assertEquals(result.disk.has(name), false, name);
  result = build("MAIN [M,K]", bad);
  for (const name of streams) assertEquals(result.disk.has(name), true, name);
  // A good build keeps its streams.
  result = build("MAIN [M]", MAIN);
  for (const name of streams) assertEquals(result.disk.has(name), true, name);
});

Deno.test("BASIE reports a part it can't find", () => {
  assertEquals(run("MAIN"), "MAIN.BSI not found\r\n");
  assertEquals(run("B:MAIN"), "B:MAIN.BSI not found\r\n");
  assertEquals(run("MAIN.TXT", MAIN), "MAIN.TXT not found\r\n");
});

Deno.test("BASIE compiles a program from a file", () => {
  assertEquals(run("MAIN", MAIN), "");
  assertEquals(run("MAIN.BSI [M]", MAIN), "");
  // CR LF lines, and the end of file marked by $1A within the last record.
  const crlf = PROGRAM.replaceAll("\n", "\r\n") + "\x1a\x1a";
  assertEquals(run("MAIN", { "MAIN.BSI": crlf }), "");
});

Deno.test("BASIE compiles a program of several parts", () => {
  const files = {
    "DATA.BSI": "var result as u8\n",
    "MAIN.BSI": "sub main()\nresult = 12\nend\n",
  };
  assertEquals(run("DATA, MAIN", files), "");
  assertEquals(run("MAIN,DATA", files), "MAIN.BSI 2:1 Error 57\r\n");
  const later = { ...files, "MAIN.BSI": "sub main()\nresult = missing\nend\n" };
  assertEquals(run("DATA,MAIN", later), "MAIN.BSI 2:10 Error 57\r\n");
});

Deno.test("BASIE reports a diagnostic with its part, line and column", () => {
  const files = { "MAIN.BSI": "sub main()\n    value = 1\nend\n" };
  assertEquals(run("MAIN", files), "MAIN.BSI 2:5 Error 57\r\n");
  const parts = [..."ABCDEFGHI"];
  const empty = Object.fromEntries(parts.map((p) => [`${p}.BSI`, "\n"]));
  assertEquals(run(parts.join(","), empty), "More than 8 source parts\r\n");
});

Deno.test("the source may fill memory to 1K below the BDOS entry", () => {
  // The harness's BDOS entry is $E406, so the source runs from $6800 to $E006.
  const room = 0xe006 - 0x6800;
  const fill = (size: number) => {
    let text = PROGRAM;
    while (text.length < size - 70) text += "// " + "x".repeat(60) + "\n";
    return text + "//" + "x".repeat(size - text.length - 3) + "\n";
  };
  assertEquals(fill(room).length, room);
  assertEquals(run("MAIN", { "MAIN.BSI": fill(room) }), "");
  assertEquals(
    run("MAIN", { "MAIN.BSI": fill(room + 1) }),
    "Source too large\r\n",
  );
});

// ---- 65.2b: options, the library check and the stamp ----------------------

Deno.test("BASIE accepts every option of toolchain §5.3, in any case", () => {
  const all = "[K, M,Y,N,R,B,Z,V,P=CPM22,L=A,S=A,O=B:PROG.HEX,F=255," +
    "STACK=65535]";
  assertEquals(run(`MAIN ${all}`, MAIN), "");
  assertEquals(run("MAIN [C]", MAIN), "");
  for (const o of ["O=PROG", "O=PROG.COM", "O=PROG.BIN", "F=1", "STACK=1"]) {
    assertEquals(run(`MAIN [${o}]`, MAIN), "", o);
  }
  // The CP/M 3 CCP leaves the tail's case alone; BASIE reads it in any.
  const result = build("main [m , k]", MAIN);
  assertEquals(result.output, "");
  assertEquals(result.disk.has("MAIN.$NM"), true);
  // X links only: nothing is compiled.
  const linked = build("MAIN [X]", MAIN);
  assertEquals(linked.output, "");
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

Deno.test("BASIE takes option T only with L, and has no trap lookup yet", () => {
  const not = "Trap lookup is not yet available\r\n";
  assertEquals(run("MAIN [T=1A3F]", MAIN), not);
  assertEquals(run("MAIN [L=B, T=0]", MAIN), not);
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
  assertEquals(build("MAIN", {}, false).output, "CPM22.BRL not found\r\n");
  assertEquals(build("MAIN", MAIN, false).returnCode, 0xff11);
  assertEquals(run("MAIN [P=OTHER]", MAIN), "OTHER.BRL not found\r\n");
  const format = "CPM22.BRL: bad magic or unsupported version\r\n";
  const compat = "Program and library are not compatible\r\n";
  const short = "CPM22.BRL: missing trailer, bad CRC or wrong length\r\n";
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
  assertEquals(run("MAIN", { ...MAIN, "CPM22.BRL": later }), "");
  // P names another library, with the same rules.
  assertEquals(run("MAIN [P=MINE]", { ...MAIN, "MINE.BRL": LIBRARY }), "");
});

Deno.test("BASIE takes the identities of the library for the directory", () => {
  const library = patched(6, 7, 0);
  library.set([9, 0], 10);
  const result = build("MAIN", { ...MAIN, "CPM22.BRL": library }, false);
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
    build("B:MAIN", { ...onB, "B:CPM22.BRL": LIBRARY }, false)
      .output,
    "",
  );
  // and then on A:;
  assertEquals(
    build("B:MAIN", { ...onB, "CPM22.BRL": LIBRARY }, false)
      .output,
    "",
  );
  assertEquals(
    build("B:MAIN", { ...onB, "C:CPM22.BRL": LIBRARY }, false).output,
    "CPM22.BRL not found\r\n",
  );
  // on L's drive, and then on A:.
  assertEquals(
    build("MAIN [L=C]", { ...MAIN, "C:CPM22.BRL": LIBRARY }, false)
      .output,
    "",
  );
  assertEquals(run("MAIN [L=C]", MAIN), "");
  assertEquals(
    build("MAIN [L=C]", { ...MAIN, "B:CPM22.BRL": LIBRARY }, false).output,
    "CPM22.BRL not found\r\n",
  );
});

Deno.test("BASIE writes the streams on the spool drive, with the first part's name", () => {
  const streams = ["$DR", "$BY", "$LN", "$NM"];
  let result = build("B:MAIN,C:MORE [M]", {
    "B:MAIN.BSI": "var x as u8\n",
    "C:MORE.BSI": "sub main()\nx = 1\nend\n",
  });
  assertEquals(result.output, "");
  for (const t of streams) assertEquals(result.disk.has(`B:MAIN.${t}`), true);
  result = build("MAIN [M,S=D]", MAIN);
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
  let result = build("MAIN [M]", MAIN);
  const first = stamp(result.disk);
  assertNotEquals(first, 0);
  for (const t of ["$BY", "$LN", "$NM"]) {
    assertEquals(stamp(result.disk, `MAIN.${t}`), first, t);
  }
  // An earlier directory's stamp, plus one, skipping zero.
  for (const [old, next] of [[41, 42], [0xfffe, 0xffff], [0xffff, 1]]) {
    const header = result.disk.get("MAIN.$DR")!.slice();
    header.set([old & 0xff, old >> 8], 6);
    const again = build("MAIN", { ...MAIN, "MAIN.$DR": header });
    assertEquals(stamp(again.disk), next, `after ${old}`);
  }
  // The earlier directory is looked for on the spool drive.
  const header = result.disk.get("MAIN.$DR")!.slice();
  header.set([0x10, 0x20], 6);
  result = build("MAIN [S=B]", { ...MAIN, "B:MAIN.$DR": header });
  assertEquals(stamp(result.disk, "B:MAIN.$DR"), 0x2011);
  // A file of that name that is no directory is ignored.
  result = build("MAIN", { ...MAIN, "MAIN.$DR": "not a directory" });
  assertNotEquals(stamp(result.disk), 0);
});
