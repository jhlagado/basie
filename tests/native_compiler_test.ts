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
  assertEquals(image.core, 24_104);
  assertEquals(image.com.length, 24_802);
  assertEquals(image.ovl.length, 8_960);
  assertEquals(
    image.overlays.map((o) => [o.name, o.bytes.length]),
    [
      ["BEGIN", 2468],
      ["NAMES", 947],
      ["CHAIN", 448],
      ["DIAG", 1047],
      ["LOOKUP", 1063],
      ["FLOAT", 1460],
      ["OWNERS", 874],
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
  "c026b1c7fe898c68d1207d2b9557c83f71fd48a2d02d24e03694aae9cf468732";
const OVL_DIGEST =
  "7d6c7f512733096fdc1b28da003bdc34cf1367a2ee3761565bbade6c8ea18d7c";
