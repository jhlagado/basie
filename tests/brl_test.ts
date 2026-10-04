import { assertEquals, assertRejects } from "@std/assert";
import { BrlError, buildLibrary } from "../tools/brl.ts";
import { link, type LinkOptions } from "../ref/link/link.ts";
import { readLibrary } from "../ref/object/library.ts";
import { defaultHeader } from "../ref/object/program.ts";
import { type BlobRecord, Form, Kind, Pseudo } from "../ref/object/types.ts";
import { runCom } from "./harness/cpm.ts";
import { boot, systemDisk } from "./harness/triptych.ts";

const WORK = "build/test-brl";
const SOURCE = await Deno.readTextFile("runtime/cpm22/cpm22.asm");
const built = await buildLibrary(SOURCE, WORK);
const library = readLibrary(built.file, true);

const CONOUT = 0x007;
const TRAPBND = 0x008;

/** A hand-written program: main prints "HI" and maybe calls the reporter. */
function linkHi(trap: boolean, options: LinkOptions = {}) {
  const code = [
    0x3e,
    0x48,
    0xcd,
    0,
    0, // LD A,'H' / CALL CONOUT
    0x3e,
    0x49,
    0xcd,
    0,
    0, // LD A,'I' / CALL CONOUT
    ...(trap ? [0xcd, 0, 0] : []), // CALL TRAPBND
    0xb7, // OR A: main returns with carry clear
    0xc9,
  ];
  const refs = [
    { offset: 3, form: Form.ABS16, target: CONOUT, addend: 0 },
    { offset: 8, form: Form.ABS16, target: CONOUT, addend: 0 },
  ];
  if (trap) {
    refs.push({ offset: 11, form: Form.ABS16, target: TRAPBND, addend: 0 });
  }
  const main: BlobRecord = {
    type: "blob",
    kind: Kind.code,
    ordinal: 0x400,
    size: code.length,
    root: false,
    align: 0,
    references: refs as BlobRecord["references"],
  };
  const dir = {
    header: defaultHeader({ helperKey: built.helperKeys[0] }),
    records: [
      main,
      { type: "entry" as const, ordinal: 0x400 },
      { type: "limits" as const, stackReserve: 64, largestFrame: 0, flags: 0 },
    ],
    trailer: {
      blobCount: 1,
      byteStreamLength: code.length,
      highestOrdinal: 0x400,
    },
  };
  return link(library, dir, Uint8Array.from(code), options);
}

Deno.test("the library builds with its references recovered", () => {
  const startup = library.records.find((r) =>
    r.type === "blob" && r.ordinal === 1
  ) as BlobRecord;
  assertEquals(startup.kind, Kind.startup);
  const targets = new Set(startup.references.map((r) => r.target));
  for (
    const t of [
      Pseudo.MAIN,
      Pseudo.REQUIRED,
      Pseudo.OPTIONS,
      Pseudo.BSS,
      0x002,
      0x004,
    ]
  ) {
    assertEquals(targets.has(t), true, `startup refers to ${t.toString(16)}`);
  }
  const bssLen = startup.references.find((r) =>
    r.target === Pseudo.BSS && r.form === Form.SIZE16
  );
  assertEquals(bssLen !== undefined, true);
  assertEquals(library.bytes[0], 0x0e); // LD C,26, never RET
  assertEquals(built.names.get(CONOUT), "CON_OUT");
});

Deno.test("a hand-written program runs under the CP/M harness", () => {
  const result = linkHi(false);
  assertEquals(result.removed.includes(TRAPBND), true);
  const run = runCom(result.output);
  assertEquals(run.output, "HI");
  assertEquals(run.returnCode, 0);
});

Deno.test("the bounds reporter prints the site and returns $FF02", () => {
  const result = linkHi(true);
  const site = result.addresses.get(0x400)! + 10;
  const run = runCom(result.output);
  const hex = site.toString(16).toUpperCase().padStart(4, "0");
  assertEquals(run.output, `HITRAP bounds at ${hex}\r\n`);
  assertEquals(run.returnCode, 0xff02);
});

Deno.test("keep-CCP returns to the CCP instead of warm booting", () => {
  const run = runCom(linkHi(false, { keepCcp: true }).output);
  assertEquals(run.output, "HI");
});

Deno.test("the program runs on the Triptych CP/M 2.2 machine", async () => {
  const output = linkHi(true).output;
  const session = await boot(await systemDisk({ "HI.COM": output }));
  try {
    const text = session.command("HI");
    assertEquals(text.includes("HITRAP bounds at"), true, text);
  } finally {
    session.close();
  }
});

Deno.test("a cross-blob relative jump is rejected", async () => {
  const bad = `; @library BAD runtime=1 helpers=1 profile=1
; @blob $001 startup ONE
ONE:    JR      TWO
; @blob $002 code TWO
TWO:    RET
`;
  await assertRejects(() => buildLibrary(bad, `${WORK}-bad`), BrlError);
});
