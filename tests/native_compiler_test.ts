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
  assertEquals(image.core, 24_991);
  assertEquals(image.com.length, 25_626);
  assertEquals(image.resident, 25_445);
  assertEquals(image.ovl.length, 10_496);
  assertEquals(
    image.overlays.map((o) => [o.name, o.bytes.length]),
    [
      ["BEGIN", 2558],
      ["NAMES", 947],
      ["CHAIN", 496],
      ["DIAG", 1286],
      ["LOOKUP", 1063],
      ["FLOAT", 1458],
      ["OWNERS", 1663],
      ["PREP", 165],
      ["SPILL", 199],
    ],
  );
  assertEquals(image.areaSize, 2_611);
  // The budget counts the memory the compiler's code takes: the resident
  // image and the overlay area after it.
  const memory = image.resident + image.areaSize;
  assertEquals(memory <= LIMIT, true, `over the ${LIMIT}-byte limit`);
  console.log(
    `  BASIE.COM ${image.resident} bytes resident and a ${image.areaSize}-byte overlay area: ${
      TARGET - memory
    } to the target, ${LIMIT - memory} to the limit`,
  );
});

const DIGEST =
  "4bb845240ef32a5aaccf6659589fb464c4f712abc2c40d3320fa01f9dc7afb76";
const OVL_DIGEST =
  "ec18e856e39f5c44904df22ccb115d9f218245b9c076b3912a5168b24c9593c3";
