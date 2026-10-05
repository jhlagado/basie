/**
 * The native compiler's streams equal the reference compiler's (design
 * decision D45). Each claimed program in tests/native/programs is compiled
 * by the reference compiler with branch shrinking off and by BASIE.COM under
 * the CP/M harness, and NAME.$DR, $BY, $LN and $NM must agree byte for byte
 * before CP/M's padding of the last record, which must be zeros. The claimed
 * set only grows: a program once claimed must keep matching (native compiler
 * plan, 65.4).
 */
import { assertEquals } from "@std/assert";
import { buildBasie } from "../native/compiler/build.ts";
import { assembleFile, comBytes, runCom } from "./harness/cpm.ts";
import { buildRuntime } from "../tools/helpertable.ts";
import { messageFile } from "../ref/compile/messages.ts";

const { compile } = await import("../ref/compile/index.ts");
const basie = (await buildBasie()).com;
const DIR = "tests/native/programs";

/** The claimed programs, by stage of 65.4. */
const CLAIMED: Record<string, string[]> = {
  "a: empty routines": ["EMPTY", "FAILS", "SUBS"],
  "b: declarations and references": ["DECLS", "REFS"],
};

/** Compile NAME with BASIE.COM and the options; return the disk. */
function native(name: string, options = "") {
  const source = Deno.readFileSync(`${DIR}/${name}.BSI`);
  const run = runCom(basie, {
    tail: `${name}${options}`,
    files: { [`${name}.BSI`]: source },
    maxSteps: 50_000_000,
  });
  assertEquals(run.output, "", `${name}${options}`);
  return run.disk;
}

/** The reference's four streams for NAME, compiled with shrinking off. */
async function reference(name: string) {
  const result = await compile(`${DIR}/${name}.BSI`, { shrink: false });
  if (!result.ok) {
    throw new Error(
      `${name}: the reference refuses it: ${JSON.stringify(result)}`,
    );
  }
  return {
    "$DR": result.objects.directory,
    "$BY": result.objects.bytes,
    "$LN": result.objects.lines,
    "$NM": result.objects.names,
  };
}

function same(
  name: string,
  file: Uint8Array | undefined,
  expected: Uint8Array,
) {
  if (!file) throw new Error(`${name} was not written`);
  assertEquals(file.length % 128, 0, `${name} is whole records`);
  assertEquals(file.subarray(0, expected.length), expected, name);
  const padding = file.subarray(expected.length);
  assertEquals(padding.every((b) => b === 0), true, `${name}'s padding`);
  assertEquals(padding.length < 128, true, `${name} has no spare record`);
}

for (const [stage, names] of Object.entries(CLAIMED)) {
  for (const name of names) {
    Deno.test(`${stage}: ${name} compiles to the reference's streams`, async () => {
      const streams = await reference(name);
      const disk = native(name, " [M]");
      for (const [type, expected] of Object.entries(streams)) {
        same(`${name}.${type}`, disk.get(`${name}.${type}`), expected);
      }
      // Without M or Y there is no name stream; with N, no line stream.
      const plain = native(name);
      assertEquals(plain.has(`${name}.$NM`), false);
      same(`${name}.$DR`, plain.get(`${name}.$DR`), streams.$DR);
      const lineless = native(name, " [N]");
      assertEquals(lineless.has(`${name}.$LN`), false);
      same(`${name}.$BY`, lineless.get(`${name}.$BY`), streams.$BY);
    });
  }
}

Deno.test("BLINK links BASIE.COM's streams and the program runs", async () => {
  const blink = comBytes(await assembleFile("native/linker/BLINK.ASM"));
  const files: Record<string, Uint8Array> = {
    "BASIE.MSG": messageFile(),
    "CPM22.BRL": (await buildRuntime()).file,
  };
  const name = "EMPTY";
  const disk = native(name);
  for (const t of ["$DR", "$BY", "$LN"]) {
    files[`${name}.${t}`] = disk.get(`${name}.${t}`)!;
  }
  const linked = runCom(blink, { tail: name, files, maxSteps: 100_000_000 });
  assertEquals(linked.output, "");
  const com = linked.disk.get(`${name}.COM`)!;
  assertEquals(runCom(com, { maxSteps: 1_000_000 }).output, "");
});
