/**
 * The reference compiler's f32 constants, read from the bytes it emits:
 * an integer zero becomes +0.0 however it was computed, since integers have
 * no negative zero (spec 6.4, 9.6), while an f32's own -0.0 is kept. A
 * program can't print the difference, so the bytes are the test.
 */
import { assertEquals } from "@std/assert";
import { compile } from "../ref/compile/index.ts";
import { readByteStream } from "../ref/object/program.ts";

async function bitsOf(initializer: string): Promise<number[]> {
  const source = `var f: f32 = ${initializer}\nsub main()\nend\n`;
  const result = await compile("F32.BSI", {
    mainSource: new TextEncoder().encode(source),
  });
  if (!result.ok) throw new Error(JSON.stringify(result));
  return [...readByteStream(result.objects.bytes).data.subarray(0, 4)];
}

Deno.test("an integer zero becomes the f32 +0.0", async () => {
  assertEquals(await bitsOf("0 * -1"), [0, 0, 0, 0]);
  assertEquals(await bitsOf("f32(0 * -1)"), [0, 0, 0, 0]);
  assertEquals(await bitsOf("f32(i16(-1) / 2)"), [0, 0, 0, 0]);
});

Deno.test("an f32's own -0.0 stays negative", async () => {
  assertEquals(await bitsOf("-0.0"), [0, 0, 0, 0x80]);
});
