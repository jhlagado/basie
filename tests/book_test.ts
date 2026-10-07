/**
 * The book's examples (roadmap step 71): every example program of
 * Programming Basie, in debug80-docs beside this checkout, compiles with
 * BASIE.COM to the reference compiler's streams, byte for byte. The book's
 * own script (debug80-docs, verify:basie-book) runs them on the reference
 * toolchain; this test holds the native compiler to the same programs. A
 * file name that is no CP/M name is given one.
 */
import { assertEquals } from "@std/assert";
import { buildBasie } from "../native/compiler/build.ts";
import { runCom } from "./harness/cpm.ts";
import { buildRuntime } from "../tools/helpertable.ts";
import { messageFile } from "../ref/compile/messages.ts";

const BOOK = new URL(
  "../../debug80-docs/basie/book1/examples/",
  import.meta.url,
);

Deno.test({
  name: "the book's examples compile natively as the reference's",
  ignore: !(await exists(BOOK)),
  async fn() {
    const { compile } = await import("../ref/compile/index.ts");
    const built = await buildBasie();
    const library = (await buildRuntime()).file;
    // The standard library's parts, which the examples include.
    const parts: Record<string, Uint8Array> = {};
    for (const e of Deno.readDirSync("lib")) {
      if (e.name.endsWith(".BSI")) {
        parts[e.name] = Deno.readFileSync(`lib/${e.name}`);
      }
    }
    const folder = BOOK.pathname;
    const names = [...Deno.readDirSync(folder)]
      .filter((e) => e.isFile && e.name.endsWith(".BSI"))
      .map((e) => e.name)
      .sort();
    let n = 0;
    for (const file of names) {
      const stem = /^[A-Z0-9]{1,8}\.BSI$/.test(file)
        ? file.replace(/\.BSI$/, "")
        : `BOOK${String(++n).padStart(2, "0")}`;
      const source = Deno.readFileSync(folder + file);
      const run = runCom(built.com, {
        tail: `${stem} [C,M]`,
        files: {
          ...parts,
          [`${stem}.BSI`]: source,
          "CPM22.BRL": library,
          "BASIE.OVL": built.ovl,
          "BASIE.MSG": messageFile(),
        },
        maxSteps: 400_000_000,
      });
      assertEquals(run.output, "", file);
      const directory = run.disk.get(`${stem}.$DR`)!;
      const ref = await compile(`${stem}.BSI`, {
        mainSource: source,
        libraryDirs: ["lib"],
        stamp: directory[6] | (directory[7] << 8),
      });
      if (!ref.ok) throw new Error(`${file}: the reference refuses it`);
      const streams: [string, Uint8Array][] = [
        ["$DR", ref.objects.directory],
        ["$BY", ref.objects.bytes],
        ["$LN", ref.objects.lines],
        ["$NM", ref.objects.names],
      ];
      for (const [type, expected] of streams) {
        const got = run.disk.get(`${stem}.${type}`)!;
        assertEquals(
          got.subarray(0, expected.length),
          expected,
          `${file} ${type}`,
        );
      }
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
