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

Deno.test("tests are pending until the compiler handles them", () => {
  const outcome = runTest("x.btn", "// expect output: x\nsub main()\nend\n");
  assertEquals(outcome.status, "pending");
});
