/**
 * BASIE.COM, the native compiler in its CP/M shell (native compiler plan
 * 65.2), under the CP/M harness: the command line, source parts read from
 * files, and diagnostics. Output is discarded until blob output (65.4).
 */
import { assertEquals } from "@std/assert";
import { buildBasie } from "../native/compiler/build.ts";
import { runCom } from "./harness/cpm.ts";

const basie = (await buildBasie()).com;

function run(tail: string, files: Record<string, string | Uint8Array> = {}) {
  return runCom(basie, { tail, files, maxSteps: 50_000_000 }).output;
}

const PROGRAM = "var value as u16 = 3\nvar cleared as u8\nsub main()\n" +
  "value = value * 2\nend\n";

Deno.test("BASIE with no part prints its usage", () => {
  assertEquals(run(""), "Usage: BASIE PART[,PART...] [OPTIONS]\r\n");
  assertEquals(run("[K]"), "Usage: BASIE PART[,PART...] [OPTIONS]\r\n");
  assertEquals(run("TOOLONGNAME"), "Usage: BASIE PART[,PART...] [OPTIONS]\r\n");
  assertEquals(run("MAIN;"), "Usage: BASIE PART[,PART...] [OPTIONS]\r\n");
});

Deno.test("a failed build deletes A:$$$.SUB; a good one leaves it", () => {
  const files = { "$$$.SUB": "x", "MAIN.BSI": PROGRAM };
  let result = runCom(basie, { tail: "MAIN", files, maxSteps: 50_000_000 });
  assertEquals(result.disk.has("$$$.SUB"), true);
  result = runCom(basie, { tail: "OTHER", files, maxSteps: 50_000_000 });
  assertEquals(result.disk.has("$$$.SUB"), false);
});

Deno.test("BASIE reports a part it can't find", () => {
  assertEquals(run("MAIN"), "MAIN.BSI not found\r\n");
  assertEquals(run("MAIN.TXT", { "MAIN.BSI": PROGRAM }), "MAIN.TXT not found\r\n");
});

Deno.test("BASIE compiles a program from a file", () => {
  assertEquals(run("MAIN", { "MAIN.BSI": PROGRAM }), "");
  assertEquals(run("MAIN.BSI [M]", { "MAIN.BSI": PROGRAM }), "");
  // CR LF lines, and the end of file marked by $1A within the last record.
  const crlf = PROGRAM.replaceAll("\n", "\r\n") + "\x1a\x1a";
  assertEquals(run("MAIN", { "MAIN.BSI": crlf }), "");
});

Deno.test("BASIE compiles a program of several parts", () => {
  const files = {
    "DATA.BSI": "var result as u8\n",
    "MAIN.BSI": "sub main()\nresult = 12\nend\n",
  };
  assertEquals(run("DATA, MAIN", files), "");
  assertEquals(run("MAIN,DATA", files), "MAIN.BSI 2:1 Error 57\r\n");
  const later = { ...files, "MAIN.BSI": "sub main()\nresult = missing\nend\n" };
  assertEquals(run("DATA,MAIN", later), "MAIN.BSI 2:10 Error 57\r\n");
});

Deno.test("BASIE reports a diagnostic with its part, line and column", () => {
  const files = { "MAIN.BSI": "sub main()\n    value = 1\nend\n" };
  assertEquals(run("MAIN", files), "MAIN.BSI 2:5 Error 57\r\n");
  const parts = [..."ABCDEFGHI"];
  const empty = Object.fromEntries(parts.map((p) => [`${p}.BSI`, "\n"]));
  assertEquals(run(parts.join(","), empty), "More than 8 source parts\r\n");
});
