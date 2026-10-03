import { assertEquals } from "@std/assert";
import { assembleFile, comBytes, here, runCom } from "./harness/cpm.ts";

Deno.test("a CP/M program prints through BDOS and returns to the CCP", async () => {
  const image = await assembleFile(here(import.meta.url, "fixtures/hello.asm"));
  const run = runCom(comBytes(image));
  assertEquals(run.output, "HELLO FROM BATON\r\n");
  assertEquals(run.exit, "return");
});
