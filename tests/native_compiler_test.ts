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
  const digest = await crypto.subtle.digest("SHA-256", new Uint8Array(image.com));
  const hex = [...new Uint8Array(digest)]
    .map((b) => b.toString(16).padStart(2, "0")).join("");
  // Step 65.0: byte-identical to the AZM build of step 65.2. A change to the
  // compiler updates this digest and the sizes below in the same commit.
  assertEquals(hex, DIGEST);
  assertEquals(image.core, 15_286);
  assertEquals(image.com.length, 16_075);
  assertEquals(image.com.length <= LIMIT, true, `over the ${LIMIT}-byte limit`);
  console.log(
    `  BASIE.COM ${image.com.length} bytes: ${
      TARGET - image.com.length
    } to the target, ${LIMIT - image.com.length} to the limit`,
  );
});

const DIGEST =
  "ea0ce9efabb5f90041bc2c2325f81a59ed40cd67cc4221e661d8c9103d60a9d8";
