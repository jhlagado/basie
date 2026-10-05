import { assertEquals } from "@std/assert";
import { walk } from "@std/fs/walk";
import {
  formatMessage,
  messageFile,
  messageFor,
  MESSAGES,
  readMessage,
} from "../ref/compile/messages.ts";
import { updateRegister } from "../tools/msgfile.ts";

/** Every diagnostic code raised anywhere in the reference toolchain. */
async function raisedCodes(): Promise<Map<string, string>> {
  const codes = new Map<string, string>();
  const pattern =
    /(?:fail|LexError|CompileError|LinkError|ObjectError)\(\s*"([a-zA-Z][a-zA-Z0-9-]*)"/g;
  for await (const e of walk("ref", { exts: [".ts"] })) {
    const text = await Deno.readTextFile(e.path);
    for (const m of text.matchAll(pattern)) codes.set(m[1], e.path);
  }
  return codes;
}

Deno.test("every code the toolchain raises has a message", async () => {
  const missing: string[] = [];
  for (const [code, file] of await raisedCodes()) {
    if (!messageFor(code)) missing.push(`${code} (${file})`);
  }
  assertEquals(missing, []);
});

Deno.test("every code a conformance test expects has a message", async () => {
  const missing: string[] = [];
  for await (const e of walk("tests/conformance", { exts: [".bsi"] })) {
    const m = (await Deno.readTextFile(e.path)).match(
      /expect error: ([a-z-]+) at/,
    );
    if (m && !messageFor(m[1])) missing.push(`${m[1]} (${e.path})`);
  }
  assertEquals(missing, []);
});

Deno.test("numbers and codes are unique", () => {
  assertEquals(
    new Set(MESSAGES.map((m) => m.number)).size,
    MESSAGES.length,
  );
  assertEquals(new Set(MESSAGES.map((m) => m.code)).size, MESSAGES.length);
});

Deno.test("BASIE.MSG holds every message and substitutes arguments", () => {
  const file = messageFile();
  for (const m of MESSAGES) assertEquals(readMessage(file, m.number), m.text);
  assertEquals(readMessage(file, 12), undefined); // an unused number
  assertEquals(formatMessage(27, ["count"]), "count is not declared");
  assertEquals(
    formatMessage(70, ["u16", "i16"]),
    "u16 and i16 don't widen to each other: convert one",
  );
  assertEquals(formatMessage(9999, ["x"]), "Message 9999: x");
});

Deno.test("the register's tables match the message table", async () => {
  const doc = await Deno.readTextFile("docs/diagnostics.md");
  assertEquals(updateRegister(doc), doc, "run deno task msg");
});
