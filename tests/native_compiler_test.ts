/**
 * The native compiler (roadmap step 64): the fork builds byte-identically to
 * Nucleus's image, its proof passes, and it stays within the budget of design
 * decision D43.
 */
import { assertEquals } from "@std/assert";
import { buildCompiler } from "../native/compiler/build.ts";
import { runProof } from "../native/compiler/proof.ts";

const TARGET = 26 * 1024;
const LIMIT = 28 * 1024;

Deno.test("the forked compiler runs its flat-target proof", async () => {
  const outcome = await runProof(
    "native/compiler/proofs/flat-target-z80-slice-proof.json",
  );
  assertEquals(outcome.failures, []);
  assertEquals(outcome.instructions, 1_055_183);
  assertEquals(outcome.cycles, 10_384_694);
});

Deno.test("the compiler is byte-identical to the fork and within budget", async () => {
  const image = await buildCompiler();
  const digest = await crypto.subtle.digest(
    "SHA-256",
    new TextEncoder().encode(image.hex),
  );
  const hex = [...new Uint8Array(digest)]
    .map((b) => b.toString(16).padStart(2, "0")).join("");
  // Nucleus commit 8d1ed07's image. This changes with the first Basie stage.
  assertEquals(
    hex,
    "6e496733450801b108b44c0e6880f74c94541a421f80c033d0a1a2f27b3f6a22",
  );
  assertEquals(image.core, 15_286);
  assertEquals(image.core <= LIMIT, true, `over the ${LIMIT}-byte limit`);
  console.log(
    `  compiler core ${image.core} bytes: ${
      TARGET - image.core
    } to the target, ${LIMIT - image.core} to the limit`,
  );
});
