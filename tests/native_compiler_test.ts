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
  assertEquals(image.core, 24_457);
  assertEquals(image.com.length, 25_059);
  assertEquals(image.ovl.length, 9_984);
  assertEquals(
    image.overlays.map((o) => [o.name, o.bytes.length]),
    [
      ["BEGIN", 2558],
      ["NAMES", 947],
      ["CHAIN", 496],
      ["DIAG", 1110],
      ["LOOKUP", 1063],
      ["FLOAT", 1458],
      ["OWNERS", 1639],
      ["PREP", 165],
    ],
  );
  assertEquals(image.areaSize, 2_611);
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
  "350c8dae5d51c88f4628435fbfa2b3f264f6e6416ebed8e40fc92717f0251f1f";
const OVL_DIGEST =
  "1339d9b65574cbd4022be5f12e66857f669e9f4d51e9d69e9fe57eb19098cccd";
