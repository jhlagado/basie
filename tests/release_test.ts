/**
 * The release image (roadmap step 70): the release tools/release.ts builds
 * boots CP/M 2.2 on the Triptych machine, BASIE builds each example there,
 * chaining to BLINK, and each example plays its recorded sessions as the
 * reference compiler's build does (tests/examples_test.ts). The sessions'
 * input files are put on the disk beside the release's.
 */
import { assert, assertEquals } from "@std/assert";
import { releaseFiles } from "../tools/release.ts";
import { boot, readFile, systemDisk } from "./harness/triptych.ts";
import { SESSIONS } from "./examples/sessions.ts";

Deno.test({
  name: "the release boots and builds and plays the examples",
  ignore:
    !(await exists(new URL("../../triptych/dist/wasm/", import.meta.url))),
  async fn() {
    const files = await releaseFiles();
    for (const s of SESSIONS) {
      for (const [name, text] of Object.entries(s.files ?? {})) {
        files[name] = new TextEncoder().encode(text);
      }
    }
    const cpm = await boot(await systemDisk(files));
    try {
      for (const program of ["ADVENT", "BUGS", "DUMP"]) {
        assertEquals(cpm.command(`BASIE ${program}`, 20_000_000), "", program);
        assert(readFile(cpm.disk(), `${program}.COM`).length > 0, program);
      }
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
