/**
 * The example programs (roadmap step 58): each is compiled and played from a
 * script under the CP/M harness, and its output compared with a recorded
 * transcript in tests/examples/. The same scripts then run under real CP/M
 * 2.2 on the Triptych machine, typing each line when the program prompts.
 * BDOS echoes what is typed there, so the test looks for the lines that show
 * the session went the same way.
 *
 * To record a transcript after changing an example on purpose, run this
 * file with RECORD=1 and read the diff before committing it.
 */
import { assert, assertEquals } from "@std/assert";
import { compile } from "../ref/compile/index.ts";
import { runCom } from "./harness/cpm.ts";
import { boot, systemDisk } from "./harness/triptych.ts";
import { SESSIONS } from "./examples/sessions.ts";

const ROOT = new URL("../", import.meta.url).pathname;
const images = new Map<string, Uint8Array>();

async function image(program: string): Promise<Uint8Array> {
  if (!images.has(program)) {
    const result = await compile(`${ROOT}examples/${program}.BSI`);
    if (!result.ok) {
      throw new Error(`${program}: ${JSON.stringify(result)}`);
    }
    images.set(program, result.com);
  }
  return images.get(program)!;
}

for (const s of SESSIONS) {
  Deno.test(`example ${s.name} plays as recorded`, async () => {
    const run = runCom(await image(s.program), {
      input: (s.lines ?? []).map((l) => l + "\r").join(""),
      tail: s.tail,
      files: s.files,
      maxSteps: 50_000_000,
    });
    const path = `${ROOT}tests/examples/${s.name}.txt`;
    if (Deno.env.get("RECORD")) await Deno.writeTextFile(path, run.output);
    assertEquals(run.output, await Deno.readTextFile(path));
  });
}

Deno.test({
  name: "the examples run under real CP/M 2.2 on the Triptych machine",
  ignore:
    !(await exists(new URL("../../triptych/dist/wasm/", import.meta.url))),
  async fn() {
    const files: Record<string, Uint8Array> = {};
    for (const s of SESSIONS) {
      files[`${s.program}.COM`] = await image(s.program);
      for (const [name, text] of Object.entries(s.files ?? {})) {
        files[name] = new TextEncoder().encode(text);
      }
    }
    const cpm = await boot(await systemDisk(files));
    try {
      for (const s of SESSIONS) {
        const text = cpm.converse(
          s.program + (s.tail ? ` ${s.tail}` : ""),
          "> ",
          s.lines ?? [],
        );
        for (const want of s.shows) {
          assert(
            text.includes(want),
            `${s.name}: no ${JSON.stringify(want)} in ${text}`,
          );
        }
      }
    } finally {
      cpm.close();
    }
  },
});

async function exists(url: URL) {
  try {
    await Deno.stat(url);
    return true;
  } catch {
    return false;
  }
}
