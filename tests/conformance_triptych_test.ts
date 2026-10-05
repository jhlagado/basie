/**
 * The conformance corpus under real CP/M 2.2 on the Triptych machine. The
 * minimal harness (tests/harness/cpm.ts) emulates BDOS by file name and keeps
 * every register; real CP/M uses FCB allocation maps, runs its BIOS on the
 * program's registers and pads files its own way. Each program that needs no
 * typed input runs here on a fresh disk, and its output, trap and files must
 * match its expectations exactly as under the minimal harness.
 */
import { assertEquals } from "@std/assert";
import { walk } from "@std/fs/walk";
import { compile } from "../ref/compile/index.ts";
import { lookup, readLineTable } from "../ref/toolchain/linetable.ts";
import { parseExpectations } from "./conformance/expectations.ts";
import { boot, readFile, systemDisk } from "./harness/triptych.ts";

/** Programs whose expectations rest on the minimal harness's devices. */
const HARNESS_ONLY = new Map([
  // The minimal harness writes printer bytes into the console stream; real
  // CP/M sends them to the list device.
  ["services/printer.bsi", "printer output"],
]);

const available = await exists(
  new URL("../../triptych/dist/wasm/", import.meta.url),
);

Deno.test({
  name: "the conformance corpus runs the same under real CP/M 2.2",
  ignore: !available,
  async fn() {
    const root = new URL("./conformance/", import.meta.url).pathname;
    const failures: string[] = [];
    let ran = 0;
    for await (const e of walk(root, { exts: [".bsi"] })) {
      const source = await Deno.readTextFile(e.path);
      const want = parseExpectations(source);
      if (want.output === undefined && !want.trap) continue;
      if (want.input !== "") continue; // typed input: see the examples test
      const name = e.path.slice(root.length);
      if (HARNESS_ONLY.has(name)) continue;
      const result = await compile(e.path, {
        mainSource: new TextEncoder().encode(source),
      });
      if (!result.ok) continue; // the minimal-harness run reports these
      const files: Record<string, Uint8Array> = { "T.COM": result.com };
      for (const [file, text] of Object.entries(want.files)) {
        files[file] = new TextEncoder().encode(text);
      }
      const cpm = await boot(await systemDisk(files));
      try {
        const output = cpm.command(`T${want.tail ? " " + want.tail : ""}`);
        ran += 1;
        if (want.trap) {
          const m = output.match(/TRAP ([a-z-]+) at ([0-9A-F]{4})\r\n$/);
          const line = m &&
            lookup(readLineTable(result.lineTable!), parseInt(m[2], 16))?.line;
          if (m?.[1] !== want.trap.reason || line !== want.trap.line) {
            failures.push(`${name}: ${JSON.stringify(output)}`);
          }
          continue;
        }
        if (output !== want.output) {
          failures.push(
            `${name}: ${JSON.stringify(output)}, expected ${
              JSON.stringify(want.output)
            }`,
          );
          continue;
        }
        const disk = cpm.disk();
        for (const [file, text] of Object.entries(want.expectFiles)) {
          let got: string | undefined;
          try {
            got = new TextDecoder().decode(readFile(disk, file));
          } catch {
            got = undefined;
          }
          if (got !== undefined && !text.includes("\x1a")) {
            const end = got.indexOf("\x1a");
            if (end >= 0) got = got.slice(0, end);
          }
          if (got !== text) {
            failures.push(`${name}: file ${file} ${JSON.stringify(got)}`);
          }
        }
        for (const file of want.absentFiles) {
          let present = true;
          try {
            readFile(disk, file);
          } catch {
            present = false;
          }
          if (present) failures.push(`${name}: file ${file} should not exist`);
        }
      } catch (error) {
        failures.push(`${name}: ${(error as Error).message.slice(0, 300)}`);
      } finally {
        cpm.close();
      }
    }
    assertEquals(failures, []);
    console.log(`  ${ran} conformance programs run under real CP/M`);
  },
});

Deno.test({
  name: "BASIE HELLO compiles, chains to BLINK and links under real CP/M 2.2",
  ignore: !available,
  async fn() {
    const { buildBasie } = await import("../native/compiler/build.ts");
    const { assembleFile, comBytes } = await import("./harness/cpm.ts");
    const { buildRuntime } = await import("../tools/helpertable.ts");
    const { messageFile } = await import("../ref/compile/messages.ts");
    const encode = (text: string) => new TextEncoder().encode(text);
    const cpm = await boot(
      await systemDisk({
        "BASIE.COM": (await buildBasie()).com,
        "BLINK.COM": comBytes(await assembleFile("native/linker/BLINK.ASM")),
        "CPM22.BRL": (await buildRuntime()).file,
        "BASIE.MSG": messageFile(),
        "HELLO.BSI": Deno.readFileSync("tests/conformance/basics/hello.bsi"),
        "BAD.BSI": encode("sub main()\nvalue = 1\nend\n"),
      }),
    );
    try {
      // The loader BASIE leaves at the top of memory reads BLINK.COM through
      // the real BDOS and starts it; BLINK publishes HELLO.COM and HELLO.LIN.
      assertEquals(cpm.command("BASIE HELLO", 400_000), "");
      assertEquals(cpm.command("HELLO"), "Hello\r\n");
      assertEquals(
        cpm.command("BASIE BAD", 400_000),
        "BAD.BSI 2:1 Error 57\r\n",
      );
      assertEquals(cpm.command("BASIE HELLO [O=HI.COM,K]", 400_000), "");
      assertEquals(cpm.command("HI"), "Hello\r\n");
      const disk = cpm.disk();
      for (const file of ["HELLO.LIN", "HI.LIN", "HELLO.$DR", "HELLO.$BY"]) {
        assertEquals(readFile(disk, file).length > 0, true, file);
      }
    } finally {
      cpm.close();
    }
  },
});

async function exists(url: URL) {
  try {
    await Deno.stat(url);
    return true;
  } catch {
    return false;
  }
}
