import { assertEquals, assertThrows } from "@std/assert";
import { parseExpectations, unescape } from "./conformance/expectations.ts";
import { runTest } from "./conformance/runner.ts";

Deno.test("expectation escapes", () => {
  assertEquals(unescape("a\\r\\n\\t\\\\\\x41"), "a\r\n\t\\A");
});

Deno.test("expectations are read from the leading comments", () => {
  const e = parseExpectations(
    [
      "// expect output: Hi\\r\\n",
      "// expect output: there",
      "// input: abc",
      "// file DATA.TXT: x",
      "// expect return: $FF01",
      "",
      "sub main()",
      "// expect output: ignored, after code",
      "end",
    ].join("\n"),
  );
  assertEquals(e.output, "Hi\r\nthere");
  assertEquals(e.input, "abc");
  assertEquals(e.files, { "DATA.TXT": "x" });
  assertEquals(e.returnCode, 0xff01);
});

Deno.test("a test can't expect both a failure and a run result", () => {
  assertThrows(() =>
    parseExpectations("// expect output: x\n// expect error: E1 at 1:1\n")
  );
});

Deno.test("the conformance corpus has no failures", async () => {
  const { walk } = await import("@std/fs/walk");
  const root = new URL("./conformance/", import.meta.url).pathname;
  const failures: string[] = [];
  let passed = 0;
  for await (const entry of walk(root, { exts: [".bsi"] })) {
    const outcome = await runTest(
      entry.path,
      await Deno.readTextFile(entry.path),
    );
    if (outcome.status === "fail") {
      failures.push(`${entry.path.slice(root.length)}: ${outcome.reason}`);
    }
    if (outcome.status === "pass") passed += 1;
  }
  assertEquals(failures, []);
  console.log(`  ${passed} conformance programs pass`);
});
