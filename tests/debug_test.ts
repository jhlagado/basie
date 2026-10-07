/**
 * Debug information (roadmap step 73): the line table and the debug file a
 * link with option D writes round-trip through tools/where.ts, which
 * places every statement's address at its own position, inside the named
 * code blob it belongs to, for the reference linker's pair and BLINK's.
 */
import { assert, assertEquals } from "@std/assert";
import { assembleFile, comBytes, runCom } from "./harness/cpm.ts";
import { buildRuntime } from "../tools/helpertable.ts";
import { messageFile } from "../ref/compile/messages.ts";
import { readLibrary } from "../ref/object/library.ts";
import { readNameStream } from "../ref/object/streams.ts";
import { writeDebug } from "../ref/link/reports.ts";
import {
  type DebugFile,
  type LineTable,
  lookup,
  readDebugFile,
  readLineTable,
} from "../tools/where.ts";

const { compile } = await import("../ref/compile/index.ts");
const library = (await buildRuntime()).file;

/** Every statement maps back to itself, inside a named code blob. */
function roundTrip(lines: LineTable, debug: DebugFile) {
  assertEquals(debug.imageCrc, lines.imageCrc);
  const entries = lines.entries;
  let checked = 0;
  for (let i = 0; i < entries.length; i++) {
    const e = entries[i];
    if (e.part === 0xff) continue;
    // Of entries at one address, the last stands for it.
    if (i + 1 < entries.length && entries[i + 1].address === e.address) {
      continue;
    }
    const place = lookup(lines, debug, e.address);
    assertEquals(
      [place.part, place.line, place.column],
      [lines.parts[e.part], e.line, e.column],
    );
    const blob = debug.blobs.find((b) =>
      e.address >= b.address && e.address < b.address + b.size
    );
    assert(blob, `$${e.address.toString(16)} is in a named blob`);
    assertEquals(blob.kind, 0, "a statement is in code");
    assertEquals(place.blob, blob.name);
    checked++;
  }
  assert(checked > 0);
}

Deno.test("the reference's line table and debug file round-trip", async () => {
  const result = await compile("examples/ADVENT.BSI", { positions: true });
  if (!result.ok) throw new Error(JSON.stringify(result));
  const lib = readLibrary(library);
  const names = new Map([
    ...readNameStream(lib.names!).names,
    ...readNameStream(result.objects.names).names,
  ]);
  const lines = readLineTable(result.link.lineTable!);
  const debug = readDebugFile(writeDebug(result.link, names));
  roundTrip(lines, debug);
  // An address in a library helper is placed in it, with no source.
  const helper = debug.blobs.find((b) => b.kind === 0 && b.address < 0x200);
  assert(helper);
  const place = lookup(lines, debug, helper.address + 1);
  assertEquals(place.blob, helper.name);
});

Deno.test("BLINK's line table and debug file round-trip", async () => {
  const result = await compile("examples/BUGS.BSI");
  if (!result.ok) throw new Error(JSON.stringify(result));
  const blink = comBytes(await assembleFile("native/linker/BLINK.ASM"));
  const run = runCom(blink, {
    tail: "PROG [D]",
    files: {
      "BASIE.MSG": messageFile(),
      "CPM22.BRL": library,
      "PROG.$DR": result.objects.directory,
      "PROG.$BY": result.objects.bytes,
      "PROG.$LN": result.objects.lines,
      "PROG.$NM": result.objects.names,
    },
    maxSteps: 300_000_000,
  });
  assertEquals(run.output, "");
  roundTrip(
    readLineTable(run.disk.get("PROG.LIN")!),
    readDebugFile(run.disk.get("PROG.DBG")!),
  );
});
