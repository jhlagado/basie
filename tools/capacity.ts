/**
 * Capacity measurement for the native compiler (roadmap step 68): build
 * BASIE.COM, then find by bisection the largest generated program of each
 * shape it compiles under the CP/M harness (BDOS at $E406, a 57K transient
 * area), and time a set of builds at 4 MHz, excluding disk time.
 *
 *   deno run --config deno.runtime.json -A tools/capacity.ts
 *
 * The figures are published in the limits register (limits.md §5.1).
 */
import { buildBasie } from "../native/compiler/build.ts";
import { runCom } from "../tests/harness/cpm.ts";
import { buildRuntime } from "./helpertable.ts";
import { messageFile } from "../ref/compile/messages.ts";

const basie = await buildBasie();
const library = (await buildRuntime()).file;
const MSG = messageFile();
const encoder = new TextEncoder();

/** Compile the parts given (the first is the main part) with option C. */
function compile(parts: Record<string, string | Uint8Array>) {
  const files: Record<string, Uint8Array> = {
    "CPM22.BRL": library,
    "BASIE.OVL": basie.ovl,
    "BASIE.MSG": MSG,
  };
  for (const [name, text] of Object.entries(parts)) {
    files[name] = typeof text === "string" ? encoder.encode(text) : text;
  }
  const main = Object.keys(parts)[0].replace(/\.BSI$/, "");
  const run = runCom(basie.com, {
    tail: `${main} [C]`,
    files,
    maxSteps: 2_000_000_000,
  });
  return { ok: run.output === "", output: run.output, cycles: run.cycles };
}

/** The largest n in [lo, hi] for which make(n) compiles, by bisection. */
function largest(
  make: (n: number) => Record<string, string>,
  lo: number,
  hi: number,
) {
  if (!compile(make(lo)).ok) throw new Error(`${lo} does not compile`);
  let last = "";
  while (lo < hi) {
    const mid = Math.ceil((lo + hi) / 2);
    const r = compile(make(mid));
    if (r.ok) lo = mid;
    else {
      hi = mid - 1;
      last = r.output.trim();
    }
  }
  return { n: lo, beyond: last };
}

const bytes = (parts: Record<string, string>) =>
  Object.values(parts).reduce((t, p) => t + p.length, 0);
const report: string[] = [];
const say = (line: string) => {
  report.push(line);
  console.log(line);
};

// 1. One part of small routines: the largest source in one part.
{
  const make = (n: number) => ({
    "ONE.BSI": Array.from(
      { length: n },
      (_, i) =>
        `sub r${i}(a: u8): u8\n    var t: u8 = a + ${
          i % 200
        }\n    return t\nend\n`,
    ).join("") + "sub main()\n    var x: u8 = r0(1)\nend\n",
  });
  const r = largest(make, 10, 254);
  say(
    `one part of routines: ${r.n} routines, ${
      bytes(make(r.n))
    } bytes of source; beyond: ${r.beyond}`,
  );
}

// 2. Names visible at once: program variables in one part.
{
  const make = (n: number) => ({
    "NAMES.BSI": Array.from({ length: n }, (_, i) => `var v${i}: u16\n`)
      .join("") + `sub main()\n    v0 = v${n - 1}\nend\n`,
  });
  const r = largest(make, 100, 4000);
  say(
    `program variables in one part: ${r.n}, ${
      bytes(make(r.n))
    } bytes of source; beyond: ${r.beyond}`,
  );
}

// 3. Locals of one routine.
{
  const make = (n: number) => ({
    "LOCALS.BSI": "sub main()\n" +
      Array.from({ length: n }, (_, i) => `    var l${i}: u8 = ${i % 200}\n`)
        .join("") +
      `    l0 = l${n - 1}\nend\n`,
  });
  const r = largest(make, 100, 4000);
  say(`locals of one routine: ${r.n}; beyond: ${r.beyond}`);
}

// 4. One routine: the largest body, statements of an assignment each.
{
  const make = (n: number) => ({
    "BODY.BSI": "var g: u16\nvar h: u16\nsub main()\n" +
      Array.from({ length: n }, (_, i) => `    g = g + h * ${i % 50 + 1}\n`)
        .join("") +
      "end\n",
  });
  const r = largest(make, 100, 3000);
  say(
    `statements in one routine: ${r.n}, ${
      bytes(make(r.n))
    } bytes of source; beyond: ${r.beyond}`,
  );
}

// 5. Many parts: each of 12 routines and 20 program variables, included by
// the main part; the largest program in parts of about 1.7K.
{
  const part = (p: number) =>
    Array.from({ length: 20 }, (_, i) => `var p${p}v${i}: u16\n`).join("") +
    Array.from(
      { length: 12 },
      (_, i) =>
        `sub p${p}r${i}(a: u16): u16\n    p${p}v${i} = p${p}v${i} + a\n    return p${p}v${i}\nend\n`,
    ).join("");
  const make = (n: number) => {
    const parts: Record<string, string> = {
      "MANY.BSI": Array.from({ length: n }, (_, p) => `include "P${p}.BSI"\n`)
        .join("") + "sub main()\n    var x: u16 = p0r0(1)\nend\n",
    };
    for (let p = 0; p < n; p++) parts[`P${p}.BSI`] = part(p);
    return parts;
  };
  const r = largest(make, 2, 40);
  say(
    `parts of 12 routines and 20 variables: ${r.n} parts, ${
      bytes(make(r.n))
    } bytes of source, ${r.n * 12} routines, ${
      r.n * 20
    } variables; beyond: ${r.beyond}`,
  );
}

// 6. Build times at 4 MHz (BASIE alone, option C, no disk time).
{
  const programs: [string, string, string[]][] = [
    ["hello", "tests/conformance/basics/hello.bsi", []],
    ["ADVENT", "examples/ADVENT.BSI", []],
    ["BIGMAIN", "tests/native/programs/BIGMAIN.BSI", [
      "BIGA.BSI",
      "BIGB.BSI",
      "BIGC.BSI",
    ]],
    ["MANYRTN", "tests/native/programs/MANYRTN.BSI", []],
    ["CASE256", "tests/native/programs/CASE256.BSI", []],
    ["BIGSPILL", "tests/native/programs/BIGSPILL.BSI", []],
  ];
  for (const [label, path, includes] of programs) {
    const name = label.toUpperCase().slice(0, 8);
    const parts: Record<string, Uint8Array> = {
      [`${name}.BSI`]: Deno.readFileSync(path),
    };
    for (const inc of includes) {
      parts[inc] = Deno.readFileSync(`tests/native/programs/${inc}`);
    }
    for (const f of Deno.readDirSync("lib")) {
      if (/^[A-Z0-9]{1,8}\.BSI$/.test(f.name) && !parts[f.name]) {
        parts[f.name] = Deno.readFileSync(`lib/${f.name}`);
      }
    }
    const size = Deno.readFileSync(path).length +
      includes.reduce(
        (t, inc) => t + Deno.statSync(`tests/native/programs/${inc}`).size,
        0,
      );
    const r = compile(parts);
    say(
      `build ${label}: ${size} bytes of source, ${
        (r.cycles / 4e6).toFixed(1)
      } s at 4 MHz${r.ok ? "" : `, refused: ${r.output.trim()}`}`,
    );
  }
}
