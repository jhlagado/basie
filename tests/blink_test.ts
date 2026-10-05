/**
 * The native linker, BLINK.COM, under the CP/M harness: its command line,
 * files, CRC and diagnostics (roadmap step 59), and its Phase A and B tables,
 * compared with the reference linker's (step 60).
 */
import { assertEquals } from "@std/assert";
import { formatMessage, messageFile } from "../ref/compile/messages.ts";
import { buildRuntime } from "../tools/helpertable.ts";
import { assembleFile, comBytes, runCom } from "./harness/cpm.ts";

const blink = comBytes(await assembleFile("native/linker/BLINK.ASM"));
const library = (await buildRuntime()).file;
const MSG = messageFile();
const { compile } = await import("../ref/compile/index.ts");
const hello = await compile("tests/conformance/basics/hello.bsi");
if (!hello.ok) throw new Error("hello didn't compile");
const HELLO_DR = hello.objects.directory;
const HELLO_BY = hello.objects.bytes;
const HELLO_LN = hello.objects.lines;

function run(tail: string, files: Record<string, Uint8Array> = {}) {
  return runCom(blink, { tail, files, maxSteps: 200_000_000 }).output;
}

const error = (n: number, args: string[] = []) =>
  `Error ${n}: ${formatMessage(n, args)}\r\n`;

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
