/**
 * The example programs (roadmap step 58): each is compiled and played from a
 * script under the CP/M harness, and its output compared with a recorded
 * transcript in tests/examples/. The same scripts then run under real CP/M
 * 2.2 on the Triptych machine, typing each line when the program prompts.
 * BDOS echoes what is typed there, so the test looks for the lines that show
 * the session went the same way.
 *
 * To record a transcript after changing an example on purpose, run this
 * file with RECORD=1 and read the diff before committing it.
 */
import { assert, assertEquals } from "@std/assert";
import { compile } from "../ref/compile/index.ts";
import { runCom } from "./harness/cpm.ts";
import { boot, systemDisk } from "./harness/triptych.ts";

type Session = {
  name: string;
  program: string;
  /** Console input; each line ends with a carriage return. */
  lines?: string[];
  tail?: string;
  files?: Record<string, string>;
  /** What the run must show under real CP/M. */
  shows: string[];
};

const SESSIONS: Session[] = [
  {
    name: "advent-win",
    program: "ADVENT",
    lines: [
      "look",
      "help",
      "xyzzy",
      "e",
      "n",
      "take lamp",
      "w",
      "take key",
      "i",
      "e",
      "e",
      "e",
      "take gold",
      "w",
      "w",
      "s",
      "drop gold",
    ],
    shows: ["There is a key here.", "You win!"],
  },
  {
    name: "advent-locked",
    program: "ADVENT",
    lines: ["n", "e", "e", "drop lamp", "quit"],
    shows: ["It is too dark to see.", "The iron door is locked.", "Goodbye."],
  },
  {
    name: "bugs-win",
    program: "BUGS",
    lines: [
      "n",
      "n",
      "z e",
      "z s",
      "n",
      "z w",
      "s",
      "n",
      "s",
      "n",
      "s",
      "w",
      "z s",
      "z w",
      "z s",
      "z s",
      "z s",
    ],
    shows: ["Zap!", "The cave is safe. You win!"],
  },
  {
    name: "bugs-lose",
    program: "BUGS",
    lines: ["s", "s", "s"],
    shows: ["A bug got you!"],
  },
  {
    name: "dump",
    program: "DUMP",
    tail: "HELLO.TXT",
    files: { "HELLO.TXT": "Hello, Basie!\r\nTwo lines.\r\n" },
    shows: ["0000: 48 65 6C 6C 6F 2C 20 42  61 73 69 65 21 0D 0A 54"],
  },
  {
    name: "dump-usage",
    program: "DUMP",
    shows: ["Usage: DUMP NAME.EXT"],
  },
  {
    name: "dump-missing",
    program: "DUMP",
    tail: "NOPE.TXT",
    shows: ["No file NOPE.TXT"],
  },
];

const ROOT = new URL("../", import.meta.url).pathname;
const images = new Map<string, Uint8Array>();

async function image(program: string): Promise<Uint8Array> {
  if (!images.has(program)) {
    const result = await compile(`${ROOT}examples/${program}.BSI`);
    if (!result.ok) {
      throw new Error(`${program}: ${JSON.stringify(result)}`);
    }
    images.set(program, result.com);
  }
  return images.get(program)!;
}

for (const s of SESSIONS) {
  Deno.test(`example ${s.name} plays as recorded`, async () => {
    const run = runCom(await image(s.program), {
      input: (s.lines ?? []).map((l) => l + "\r").join(""),
      tail: s.tail,
      files: s.files,
      maxSteps: 50_000_000,
    });
    const path = `${ROOT}tests/examples/${s.name}.txt`;
    if (Deno.env.get("RECORD")) await Deno.writeTextFile(path, run.output);
    assertEquals(run.output, await Deno.readTextFile(path));
  });
}

Deno.test({
  name: "the examples run under real CP/M 2.2 on the Triptych machine",
  ignore:
    !(await exists(new URL("../../triptych/dist/wasm/", import.meta.url))),
  async fn() {
    const files: Record<string, Uint8Array> = {};
    for (const s of SESSIONS) {
      files[`${s.program}.COM`] = await image(s.program);
      for (const [name, text] of Object.entries(s.files ?? {})) {
        files[name] = new TextEncoder().encode(text);
      }
    }
    const cpm = await boot(await systemDisk(files));
    try {
      for (const s of SESSIONS) {
        const text = cpm.converse(
          s.program + (s.tail ? ` ${s.tail}` : ""),
          "> ",
          s.lines ?? [],
        );
        for (const want of s.shows) {
          assert(
            text.includes(want),
            `${s.name}: no ${JSON.stringify(want)} in ${text}`,
          );
        }
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
