import { assert, assertEquals } from "@std/assert";
import { walk } from "@std/fs/walk";
import { compile, runtimeLibrary } from "../ref/compile/index.ts";
import {
  Helper,
  HELPER_KEY,
  HELPER_TABLE,
  HELPER_VERSION,
  SERVICES,
  TRAP_REPORTERS,
} from "../ref/compile/helpers.ts";
import {
  buildRuntime,
  DOC,
  helperModule,
  helperTables,
  MODULE,
  NAMES,
  NATIVE,
  nativeHelpers,
  nativeNames,
  serviceNames,
  updateDoc,
} from "../tools/helpertable.ts";
import { analyzeStack, StackError } from "../tools/stack.ts";
import { runTest, type StackUse } from "./conformance/runner.ts";
import { assertThrows } from "@std/assert";

const built = await buildRuntime();
const byOrdinal = new Map(HELPER_TABLE.map((h) => [h.ordinal, h]));
const hello = new TextEncoder().encode(
  'sub main() fails\n    writeText(console, "hi") else fail\nend\n',
);

Deno.test("the compiler's helper table and the published one are current", async () => {
  assertEquals(
    await Deno.readTextFile(MODULE),
    helperModule(built),
    "run deno task helpers",
  );
  assertEquals(
    await Deno.readTextFile(NATIVE),
    nativeHelpers(built),
    "run deno task helpers",
  );
  assertEquals(
    await Deno.readTextFile(NAMES),
    nativeNames(built),
    "run deno task helpers",
  );
  const doc = await Deno.readTextFile(DOC);
  assertEquals(
    updateDoc(doc, helperTables(built, await serviceNames())),
    doc,
    "run deno task helpers",
  );
  assertEquals(HELPER_VERSION, built.helperVersion);
  assertEquals(HELPER_KEY, built.helperKeys[HELPER_VERSION - 1]);
});

Deno.test("every helper the compiler calls is in the table with its convention", () => {
  const wrong: string[] = [];
  const notHelpers = new Set<number>([
    Helper.STARTUP,
    Helper.EXIT,
    Helper.TRAP,
  ]);
  for (const [name, ordinal] of Object.entries(Helper)) {
    if (notHelpers.has(ordinal)) continue;
    if (byOrdinal.get(ordinal)?.convention !== 2) wrong.push(name);
  }
  for (const ordinal of Object.values(TRAP_REPORTERS)) {
    if (byOrdinal.get(ordinal)?.convention !== 2) wrong.push(`trap ${ordinal}`);
  }
  for (const s of SERVICES) {
    if (byOrdinal.get(s.ordinal)?.convention !== 1) wrong.push(s.name);
  }
  assertEquals(wrong, []);
});

Deno.test("every ending path fits the guard band", async () => {
  const library = await runtimeLibrary();
  const guard = library.profile.guardBand;
  const over = HELPER_TABLE.filter((h) => h.endingStack - h.stack > guard)
    .map((h) => `${h.name}: ${h.endingStack} - ${h.stack} > ${guard}`);
  assertEquals(over, []);
});

Deno.test("the linker refuses a library whose helper table differs", async () => {
  const library = await runtimeLibrary();
  const ok = await compile("HI.BSI", { mainSource: hello, library });
  assert(ok.ok);
  const changed = { ...library, keys: library.keys.map((k) => k ^ 1) };
  const bad = await compile("HI.BSI", { mainSource: hello, library: changed });
  assertEquals("linkError" in bad && bad.linkError, "L-COMPAT");
  const older = { ...library, helperVersion: HELPER_VERSION - 1, keys: [] };
  const old = await compile("HI.BSI", { mainSource: hello, library: older });
  assertEquals("linkError" in old && old.linkError, "L-COMPAT");
  const newer = {
    ...library,
    helperVersion: HELPER_VERSION + 1,
    keys: [...library.keys, 0x1234],
  };
  const fine = await compile("HI.BSI", { mainSource: hello, library: newer });
  assert(fine.ok, "a later version that keeps the earlier key links");
});

Deno.test("the stack analysis follows calls, tail jumps and frame resets", () => {
  const blob = (
    ordinal: number,
    name: string,
    bytes: number[],
    refs: [number, number, number][] = [],
    extra = {},
  ) => ({
    ordinal,
    name,
    bytes,
    references: new Map(
      refs.map(([offset, target, addend]) => [offset, { target, addend }]),
    ),
    ...extra,
  });
  const leaf = blob(1, "LEAF", [0xc5, 0xd5, 0xd1, 0xc1, 0xc9]); // 4 pushed
  const caller = blob(2, "CALLER", [0xe5, 0xcd, 0, 0, 0xe1, 0xc9], [[2, 1, 0]]);
  const tail = blob(3, "TAIL", [0xe5, 0xe1, 0xc3, 0, 0], [[3, 1, 0]]);
  const ending = blob(4, "END", [0xe5, 0xe5, 0xc7]); // RST 0
  const either = blob(5, "EITHER", [0x38, 3, 0xcd, 0, 0, 0xc9], [[3, 4, 0]]);
  // PUSH IX; LD IX,0; ADD IX,SP; PUSH HL; PUSH HL; LD SP,IX; POP IX; RET
  const frame = blob(6, "FRAME", [
    0xdd,
    0xe5,
    0xdd,
    0x21,
    0,
    0,
    0xdd,
    0x39,
    0xe5,
    0xe5,
    0xdd,
    0xf9,
    0xdd,
    0xe1,
    0xc9,
  ]);
  const f = analyzeStack([leaf, caller, tail, ending, either, frame]);
  assertEquals(f.get(1), { returns: true, returning: 6, ending: 6 });
  assertEquals(f.get(2), { returns: true, returning: 10, ending: 10 });
  assertEquals(f.get(3), { returns: true, returning: 6, ending: 6 });
  assertEquals(f.get(4), { returns: false, returning: 6, ending: 6 });
  assertEquals(f.get(5), { returns: true, returning: 2, ending: 8 });
  assertEquals(f.get(6), { returns: true, returning: 8, ending: 8 });
  assertThrows(
    () => analyzeStack([blob(7, "LOOP", [0xe5, 0x18, 0xfd])]),
    StackError,
  );
  assertThrows(
    () => analyzeStack([blob(8, "IND", [0xe9])]),
    StackError,
    "indirect",
  );
});

Deno.test("no helper uses more stack than its figure under the corpus", async () => {
  const use: StackUse = { returning: new Map(), ending: new Map() };
  const root = new URL("./conformance/", import.meta.url).pathname;
  for await (const e of walk(root, { exts: [".bsi"] })) {
    await runTest(e.path, await Deno.readTextFile(e.path), use);
  }
  const over: string[] = [];
  const name = (o: number) => built.names.get(o) ?? `$${o.toString(16)}`;
  for (const [ordinal, bytes] of use.returning) {
    const f = built.stack.get(ordinal);
    if (f && bytes > f.returning) {
      over.push(`${name(ordinal)} returning ${bytes} > ${f.returning}`);
    }
  }
  for (const [ordinal, bytes] of use.ending) {
    const f = built.stack.get(ordinal);
    if (f && bytes > f.ending) {
      over.push(`${name(ordinal)} ending ${bytes} > ${f.ending}`);
    }
  }
  assertEquals(over, []);
  assert(use.returning.size > 60, "the corpus exercises most helpers");
});
