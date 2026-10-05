import { assertEquals } from "@std/assert";
import { assembleFile, comBytes, here, runCom } from "./harness/cpm.ts";

Deno.test("a CP/M program prints through BDOS and returns to the CCP", async () => {
  const image = await assembleFile(here(import.meta.url, "fixtures/hello.asm"));
  const run = runCom(comBytes(image));
  assertEquals(run.output, "HELLO FROM BASIQ\r\n");
  assertEquals(run.exit, "return");
});

Deno.test("files, the command tail and return codes", async () => {
  const image = await assembleFile(
    here(import.meta.url, "fixtures/copyfile.asm"),
  );
  const text = "first line\r\n".repeat(20); // 240 bytes: two records
  const run = runCom(comBytes(image), {
    tail: "in.txt out.txt",
    files: { "IN.TXT": text },
  });
  assertEquals(run.output, " IN.TXT OUT.TXT");
  assertEquals(run.returnCode, 0);
  const copied = run.disk.get("OUT.TXT")!;
  assertEquals(copied.length, 256);
  assertEquals(new TextDecoder().decode(copied.subarray(0, 240)), text);
});

Deno.test("a missing input file sets a failure return code", async () => {
  const image = await assembleFile(
    here(import.meta.url, "fixtures/copyfile.asm"),
  );
  const run = runCom(comBytes(image));
  assertEquals(run.returnCode, 0xff01);
});
