/**
 * The native blob writer (native compiler plan 65.3): a test program writes
 * hello's objects through native/compiler/BLOB.ASM, and the four streams
 * equal the reference compiler's, byte for byte, before CP/M's padding.
 */
import { assertEquals } from "@std/assert";
import { assembleFile, comBytes, runCom } from "./harness/cpm.ts";
import {
  writeByteStream,
  writeProgramDirectory,
} from "../ref/object/program.ts";
import { writeLineStream, writeNameStream } from "../ref/object/streams.ts";
import type { DirectoryRecord } from "../ref/object/types.ts";
import { buildRuntime } from "../tools/helpertable.ts";
import { messageFile } from "../ref/compile/messages.ts";

const program = comBytes(
  await assembleFile("tests/native/BLOBTEST.ASM", "."),
);
const { compile } = await import("../ref/compile/index.ts");
const hello = await compile("tests/conformance/basics/hello.bsi");
if (!hello.ok) throw new Error("hello didn't compile");

Deno.test("the blob writer writes the reference's streams for hello", async () => {
  const run = runCom(program, { tail: "", files: {}, maxSteps: 50_000_000 });
  assertEquals(run.output, "");
  const streams = {
    "HELLO.$DR": hello.objects.directory,
    "HELLO.$BY": hello.objects.bytes,
    "HELLO.$LN": hello.objects.lines,
    "HELLO.$NM": hello.objects.names,
  };
  for (const [name, expected] of Object.entries(streams)) {
    const file = run.disk.get(name)!;
    assertEquals(file.length % 128, 0, name);
    assertEquals(file.subarray(0, expected.length), expected, name);
    assertEquals(
      file.subarray(expected.length).every((b) => b === 0),
      true,
      name,
    );
  }
  // BLINK links the streams, and the program runs.
  const blink = comBytes(await assembleFile("native/linker/BLINK.ASM"));
  const files: Record<string, Uint8Array> = {
    "BASIE.MSG": messageFile(),
    "CPM22.BRL": (await buildRuntime()).file,
  };
  for (const t of ["$DR", "$BY", "$LN"]) {
    files[`HELLO.${t}`] = run.disk.get(`HELLO.${t}`)!;
  }
  const linked = runCom(blink, { tail: "HELLO", files, maxSteps: 100_000_000 });
  assertEquals(linked.output, "");
  const com = linked.disk.get("HELLO.COM")!;
  assertEquals(runCom(com, { maxSteps: 1_000_000 }).output, "Hello\r\n");
});

Deno.test("the blob writer's escapes, forms, kinds and line rules", async () => {
  const edge = comBytes(await assembleFile("tests/native/BLOBEDGE.ASM", "."));
  const run = runCom(edge, { tail: "", files: {}, maxSteps: 50_000_000 });
  assertEquals(run.output, "");
  const stamp = 7;
  const records: DirectoryRecord[] = [
    {
      type: "blob",
      kind: 0,
      ordinal: 0x400,
      size: 150,
      root: false,
      align: 0,
      references: [
        { offset: 0, form: 1, target: 0x401, addend: 0 },
        { offset: 70, form: 2, target: 0x401, addend: 5 },
        { offset: 71, form: 3, target: 0x402, addend: 0 },
      ],
    },
    {
      type: "blob",
      kind: 2,
      ordinal: 0x405,
      size: 4,
      root: true,
      align: 3,
      references: [],
    },
    {
      type: "blob",
      kind: 3,
      ordinal: 0x406,
      size: 300,
      root: false,
      align: 0,
      references: [],
    },
  ];
  const header = {
    major: 1,
    minor: 0,
    stamp,
    runtimeIdentity: 1,
    helperVersion: 1,
    helperKey: 0,
    profileIdentity: 1,
    ordinalBase: 0x400,
    flags: 0,
  };
  const name = "a_name_of_forty_characters_exactly_here_";
  const streams = {
    "EDGE.$DR": writeProgramDirectory(header, records, 154),
    "EDGE.$BY": writeByteStream(stamp, new Uint8Array(154)),
    "EDGE.$LN": writeLineStream(stamp, ["A.BSI", "B.BSI"], [{
      ordinal: 0x400,
      entries: [
        { offset: 0, part: 0, source: 1 },
        { offset: 0, part: 1, source: 3 },
        { offset: 140, part: 1, source: 9 },
      ],
    }]),
    "EDGE.$NM": writeNameStream(stamp, [{ ordinal: 0x405, name }]),
  };
  for (const [file, expected] of Object.entries(streams)) {
    const got = run.disk.get(file)!;
    assertEquals(got.subarray(0, expected.length), expected, file);
  }
});
