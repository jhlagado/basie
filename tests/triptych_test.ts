import { assertEquals } from "@std/assert";
import { assembleFile, comBytes, here } from "./harness/cpm.ts";
import { boot, readFile, systemDisk } from "./harness/triptych.ts";

Deno.test({
  name: "programs run under real CP/M 2.2 on the Triptych machine",
  ignore:
    !(await exists(new URL("../../triptych/dist/wasm/", import.meta.url))),
  async fn() {
    const hello = comBytes(
      await assembleFile(here(import.meta.url, "fixtures/hello.asm")),
    );
    const copy = comBytes(
      await assembleFile(here(import.meta.url, "fixtures/copyfile.asm")),
    );
    const disk = await systemDisk({
      "HELLO.COM": hello,
      "COPYFILE.COM": copy,
      "IN.TXT": new TextEncoder().encode("first line\r\n".repeat(20)),
    });
    const cpm = await boot(disk);
    try {
      assertEquals(cpm.command("HELLO"), "HELLO FROM BASIQ\r\n");
      cpm.command("COPYFILE IN.TXT OUT.TXT");
      const copied = readFile(cpm.disk(), "OUT.TXT");
      assertEquals(
        new TextDecoder().decode(copied.subarray(0, 240)),
        "first line\r\n".repeat(20),
      );
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
