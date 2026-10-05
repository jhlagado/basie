/**
 * BASIE.COM's image: ATOM assembles the compiler's sources (design decision
 * D44) to the image recorded here, and it stays within the budget of D43.
 */
import { assertEquals } from "@std/assert";
import { buildBasie } from "../native/compiler/build.ts";

const TARGET = 26 * 1024;
const LIMIT = 28 * 1024;

Deno.test("BASIE.COM is the recorded image and within budget", async () => {
  const image = await buildBasie();
  const digest = await crypto.subtle.digest(
    "SHA-256",
    new Uint8Array(image.com),
  );
  const hex = [...new Uint8Array(digest)]
    .map((b) => b.toString(16).padStart(2, "0")).join("");
  // A change to the compiler updates this digest and the sizes below in the
  // same commit, with the census figure in its message (D43).
  assertEquals(hex, DIGEST);
  assertEquals(image.core, 12_457);
  assertEquals(image.com.length, 13_514);
  assertEquals(image.com.length <= LIMIT, true, `over the ${LIMIT}-byte limit`);
  console.log(
    `  BASIE.COM ${image.com.length} bytes: ${
      TARGET - image.com.length
    } to the target, ${LIMIT - image.com.length} to the limit`,
  );
});

const DIGEST =
  "2c47a3920c64488833c7cee41d2a3ec1ff3754d154a26e9ca624f6a35f6821ba";
