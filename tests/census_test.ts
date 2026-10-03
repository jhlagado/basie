import { assertEquals } from "@std/assert";
import { attribute } from "../tools/census.ts";

Deno.test("bytes are attributed to the files that define their labels", () => {
  const owner = new Map([
    ["start", "core/start.asm"],
    ["print", "core/print.asm"],
    ["table", "data/table.asm"],
  ]);
  const census = attribute(
    [["start", 0x100], ["print", 0x110], ["table", 0x140], ["other", 0x150]],
    owner,
    0x100,
    0x160,
  );
  assertEquals(census.total, 0x60);
  assertEquals(census.byFile.get("core/start.asm"), 0x10);
  assertEquals(census.byFile.get("core/print.asm"), 0x30);
  assertEquals(census.byFile.get("data/table.asm"), 0x20);
  assertEquals(census.byDirectory.get("core"), 0x40);
});
