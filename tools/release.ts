/**
 * The release image (roadmap step 70): BASIE.COM, BASIE.OVL, BASIE.MSG,
 * BLINK.COM, CPM22.BRL, the standard library and the examples, each built
 * from source, written as loose files to build/release/ and onto a bootable
 * CP/M 2.2 disk, build/BASIE.DSK (the Triptych machine's 8-inch, 241K
 * format), which tests/release_test.ts boots to build the examples.
 *
 *   deno task release
 */
import { buildBasie } from "../native/compiler/build.ts";
import { assembleFile, comBytes } from "../tests/harness/cpm.ts";
import { systemDisk } from "../tests/harness/triptych.ts";
import { buildRuntime } from "./helpertable.ts";
import { messageFile } from "../ref/compile/messages.ts";

const ROOT = new URL("../", import.meta.url).pathname;

/** The guide on the disk, in CP/M's line ends. */
const GUIDE = `BASIE for CP/M 2.2

  BASIE NAME            compile NAME.BSI and link NAME.COM
  BASIE NAME [C]        compile only, leaving the streams for BLINK
  BLINK NAME            link the streams NAME.$DR, $BY and $LN

BASIE.COM chains to BLINK.COM, which it looks for on the current drive,
then on A:. BASIE.OVL, BASIE.MSG and CPM22.BRL must be on the current
drive or on A:. A part's includes are looked for on its own drive, then
on A:, where the standard library's parts are.

The library:  TEXTIO.BSI  FORMAT.BSI  PARSE.BSI  STRINGS.BSI  RANDOM.BSI
The examples: ADVENT.BSI  BUGS.BSI  DUMP.BSI

  BASIE ADVENT          then ADVENT
  BASIE DUMP            then DUMP README.TXT

Basie is free software under the GNU General Public License, version 3.
`.replaceAll("\n", "\r\n");

/** Every file of the release, by its CP/M name. */
export async function releaseFiles(): Promise<Record<string, Uint8Array>> {
  const basie = await buildBasie();
  const files: Record<string, Uint8Array> = {
    "BASIE.COM": basie.com,
    "BASIE.OVL": basie.ovl,
    "BASIE.MSG": messageFile(),
    "BLINK.COM": comBytes(
      await assembleFile(`${ROOT}native/linker/BLINK.ASM`, ROOT),
    ),
    "CPM22.BRL": (await buildRuntime()).file,
    "README.TXT": new TextEncoder().encode(GUIDE),
  };
  for (const dir of ["lib", "examples"]) {
    for (const entry of Deno.readDirSync(`${ROOT}${dir}`)) {
      if (/^[A-Z0-9]{1,8}\.BSI$/.test(entry.name)) {
        files[entry.name] = Deno.readFileSync(`${ROOT}${dir}/${entry.name}`);
      }
    }
  }
  return files;
}

/** A bootable CP/M 2.2 disk holding the release. */
export async function releaseDisk(): Promise<Uint8Array> {
  return await systemDisk(await releaseFiles());
}

if (import.meta.main) {
  const files = await releaseFiles();
  Deno.mkdirSync(`${ROOT}build/release`, { recursive: true });
  for (const [name, bytes] of Object.entries(files)) {
    Deno.writeFileSync(`${ROOT}build/release/${name}`, bytes);
    console.log(`${name.padEnd(12)} ${bytes.length} bytes`);
  }
  const disk = await systemDisk(files);
  Deno.writeFileSync(`${ROOT}build/BASIE.DSK`, disk);
  console.log(`build/BASIE.DSK ${disk.length} bytes`);
}
