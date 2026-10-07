/**
 * BASIE.COM's image and its overlays, BASIE.OVL: ATOM assembles the
 * compiler's sources (design decision D44) to the images recorded here,
 * and the resident image and the overlay area stay within the budget of
 * D43.
 */
import { assertEquals } from "@std/assert";
import { buildBasie } from "../native/compiler/build.ts";

const TARGET = 26 * 1024;
const LIMIT = 28 * 1024;

const sha256 = async (bytes: Uint8Array) =>
  [
    ...new Uint8Array(
      await crypto.subtle.digest("SHA-256", new Uint8Array(bytes)),
    ),
  ].map((b) => b.toString(16).padStart(2, "0")).join("");

Deno.test("BASIE.COM and BASIE.OVL are the recorded images and within budget", async () => {
  const image = await buildBasie();
  // A change to the compiler updates these digests and the sizes below in
  // the same commit, with the census figure in its message (D43).
  assertEquals(await sha256(image.com), DIGEST);
  assertEquals(await sha256(image.ovl), OVL_DIGEST);
  assertEquals(image.core, 24_742);
  assertEquals(image.com.length, 25_441);
  assertEquals(image.ovl.length, 9_472);
  assertEquals(
    image.overlays.map((o) => [o.name, o.bytes.length]),
    [
      ["BEGIN", 2466],
      ["NAMES", 947],
      ["CHAIN", 448],
      ["DIAG", 1047],
      ["LOOKUP", 1063],
      ["FLOAT", 1458],
      ["OWNERS", 1287],
    ],
  );
  assertEquals(image.areaSize, 2_560);
  // The budget counts the memory the compiler's code takes: the resident
  // image and the overlay area after it.
  const memory = image.com.length + image.areaSize;
  assertEquals(memory <= LIMIT, true, `over the ${LIMIT}-byte limit`);
  console.log(
    `  BASIE.COM ${image.com.length} bytes and a ${image.areaSize}-byte overlay area: ${
      TARGET - memory
    } to the target, ${LIMIT - memory} to the limit`,
  );
});

const DIGEST =
  "0dee630a9ecc9b10cb330b4cfc46b098cdc9597786499854d6b7b7973cfcd454";
const OVL_DIGEST =
  "0a44d4c99964174d20a3b257bffd27ffde6ceb4dc74e8a3c2638200e02813d5f";
