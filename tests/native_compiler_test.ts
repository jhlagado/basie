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
  assertEquals(image.core, 21_762);
  assertEquals(image.com.length, 22_431);
  assertEquals(image.ovl.length, 8_960);
  assertEquals(
    image.overlays.map((o) => [o.name, o.bytes.length]),
    [
      ["COMMAND", 978],
      ["START", 812],
      ["NAMES", 947],
      ["CHAIN", 448],
      ["DIAG", 1047],
      ["PARTS", 915],
      ["FLOAT", 1460],
      ["OWNERS", 1651],
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
  "485c52c8d49b4f0c211888f9fa2026ce81f5667f91de339ff5fc25e0e487df2b";
const OVL_DIGEST =
  "7f8201f6fbc7a6e71de33b6efdfb595dd9574a1a5ee4029d883404f523a88fe4";
