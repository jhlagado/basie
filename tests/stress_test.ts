/**
 * Large programs and stress tests (roadmap step 69): BASIE.COM compiles a
 * program at each of the specification's capacity minimums (limits §5.1)
 * as the reference compiler does, byte for byte; random whole programs
 * compile alike; and a large program in many parts, linked by BLINK.COM,
 * runs as the reference's does.
 */
import { assertEquals } from "@std/assert";
import { buildBasie } from "../native/compiler/build.ts";
import { assembleFile, comBytes, runCom } from "./harness/cpm.ts";
import { buildRuntime } from "../tools/helpertable.ts";
import { messageFile } from "../ref/compile/messages.ts";

const { compile } = await import("../ref/compile/index.ts");
const built = await buildBasie();
const LIBRARY = (await buildRuntime()).file;
const MSG = messageFile();
const encoder = new TextEncoder();

type Parts = Record<string, string>;

/** The first part's stem, the name BASIE is given. */
const stem = (parts: Parts) => Object.keys(parts)[0].replace(/\.BSI$/, "");

/** Compile the parts natively, with option C: the disk and the output. */
function native(parts: Parts) {
  const files: Record<string, Uint8Array> = {
    "CPM22.BRL": LIBRARY,
    "BASIE.OVL": built.ovl,
    "BASIE.MSG": MSG,
  };
  for (const [name, text] of Object.entries(parts)) {
    files[name] = encoder.encode(text);
  }
  return runCom(built.com, {
    tail: `${stem(parts)} [C]`,
    files,
    maxSteps: 2_000_000_000,
  });
}

/** The reference compiled from the same parts, with the native stamp. */
async function reference(parts: Parts, disk: Map<string, Uint8Array>) {
  const name = stem(parts);
  const directory = disk.get(`${name}.$DR`);
  const sources = new Map(
    Object.entries(parts).map(([n, t]) => [n, encoder.encode(t)]),
  );
  return await compile(`${name}.BSI`, {
    mainSource: sources.get(`${name}.BSI`)!,
    reader: {
      read: (path: string) => sources.get(path.split("/").pop()!.toUpperCase()),
    },
    stamp: directory ? directory[6] | (directory[7] << 8) : 1,
  });
}

/** Both compilers accept the parts and write the same streams. */
async function alike(what: string, parts: Parts) {
  const run = native(parts);
  assertEquals(run.output, "", what);
  const ref = await reference(parts, run.disk);
  if (!ref.ok) throw new Error(`${what}: the reference refuses it`);
  const name = stem(parts);
  const streams: [string, Uint8Array][] = [
    ["$DR", ref.objects.directory],
    ["$BY", ref.objects.bytes],
    ["$LN", ref.objects.lines],
  ];
  for (const [type, expected] of streams) {
    const file = run.disk.get(`${name}.${type}`)!;
    assertEquals(
      file.subarray(0, expected.length),
      expected,
      `${what} ${type}`,
    );
  }
  return run;
}

const lines = (n: number, f: (i: number) => string) =>
  Array.from({ length: n }, (_, i) => f(i)).join("");

// ---- 69.1: the specification's minimums (limits §5.1) ----------------

Deno.test("an identifier of 255 bytes", async () => {
  const name = "n" + "x".repeat(254);
  await alike("identifier", {
    "IDENT.BSI": `var ${name}: u8\nsub main()\n    ${name} = 1\nend\n`,
  });
});

Deno.test("1,000 top-level names, in four parts", async () => {
  const part = (p: number) =>
    lines(240, (i) => `var p${p}v${i}: u8\n`) +
    lines(5, (i) => `sub p${p}r${i}()\n    p${p}v${i} = ${i}\nend\n`) +
    lines(5, (i) => `const p${p}c${i}: u16 = ${i * 7}\n`);
  await alike("top-level names", {
    "NAMES.BSI": lines(4, (p) => `include "P${p}.BSI"\n`) +
      "sub main()\n    p0r0()\n    p3v239 = u8(p3c4)\nend\n",
    "P0.BSI": part(0),
    "P1.BSI": part(1),
    "P2.BSI": part(2),
    "P3.BSI": part(3),
  });
});

Deno.test("128 names visible in one routine", async () => {
  await alike("locals", {
    "LOCALS.BSI": "sub main()\n" +
      lines(128, (i) => `    var l${i}: u8 = ${i}\n`) +
      "    l0 = l127\nend\n",
  });
});

Deno.test("32 parameters and 32 arguments", async () => {
  const params = lines(32, (i) => `${i ? ", " : ""}p${i}: u8`);
  const args = lines(32, (i) => `${i ? ", " : ""}${i}`);
  await alike("parameters", {
    "PARAMS.BSI": `sub f(${params}): u8\n    return p0 + p31\nend\n` +
      `sub main()\n    var x: u8 = f(${args})\nend\n`,
  });
});

Deno.test("64 fields in one record", async () => {
  await alike("fields", {
    "FIELDS.BSI": "record R\n" + lines(64, (i) => `    m${i}: u8\n`) +
      "end\nvar r: R\nsub main()\n    r.m63 = r.m0\nend\n",
  });
});

Deno.test("128 forward declarations outstanding at once", async () => {
  await alike("forwards", {
    "FWD.BSI": lines(128, (i) => `forward sub q${i}()\n`) +
      "sub main()\n" + lines(128, (i) => `    q${i}()\n`) + "end\n" +
      lines(128, (i) => `sub q${i}\nend\n`),
  });
});

Deno.test("statements nested 32 deep, mixed", async () => {
  let body = "            g = g + 1\n";
  for (let i = 31; i >= 0; i--) {
    const pad = "    ".repeat(i + 1);
    body = i % 3 === 0
      ? `${pad}if g < ${
        200 + i
      }\n${body}${pad}else\n${pad}    g = 0\n${pad}end\n`
      : i % 3 === 1
      ? `${pad}for k${i} = 1 to 2\n${body}${pad}end\n`
      : `${pad}select g\n${pad}case 0 to 100\n${body}${pad}case else\n${pad}end\n`;
  }
  const counters = lines(32, (i) => i % 3 === 1 ? `    var k${i}: u8\n` : "");
  await alike("nesting", {
    "NEST.BSI": `var g: u8\nsub main()\n${counters}${body}end\n`,
  });
});

Deno.test("expressions nested 32 deep, an operator pending at each", async () => {
  let e = "x";
  for (let i = 0; i < 32; i++) e = `x * ${i % 5 + 1} + (${e})`;
  await alike("expressions", {
    "EXPRS.BSI": `var x: u16\nsub main()\n    x = ${e}\nend\n`,
  });
});

Deno.test("a select of 256 cases", async () => {
  await alike("cases", {
    "CASES.BSI": "var g: u8\nvar h: u16\nsub main()\n    select h\n" +
      lines(256, (i) => `    case ${i * 3}\n        g = ${i % 256}\n`) +
      "    case else\n        g = 0\n    end\nend\n",
  });
});

Deno.test("64 owning locals in one routine", async () => {
  await alike("owners", {
    "OWNERS.BSI": "forward pool nodes\nrecord Node\n    value: u8\n" +
      "    next: nodes?\nend\npool nodes: Node[70]\nsub main()\n" +
      lines(64, (i) => `    var o${i} = new nodes(${i}, none)\n`) + "end\n",
  });
});

Deno.test("255 source parts", async () => {
  const parts: Parts = {
    "PARTS.BSI": lines(254, (p) => `include "Q${p}.BSI"\n`) +
      "sub main()\n    q0()\n    q253()\nend\n",
  };
  for (let p = 0; p < 254; p++) {
    parts[`Q${p}.BSI`] = `sub q${p}()\nend\n`;
  }
  await alike("parts", parts);
});

// ---- 69.2: random whole programs -------------------------------------

/** A small deterministic generator, so that a failure can be replayed. */
function generator(seed: number) {
  let state = seed >>> 0 || 1;
  const next = () => {
    state ^= state << 13;
    state ^= state >>> 17;
    state ^= state << 5;
    return (state >>> 0) / 4294967296;
  };
  const rnd = (n: number) => Math.floor(next() * n);
  const pick = <T>(xs: T[]) => xs[rnd(xs.length)];
  return { rnd, pick };
}

/**
 * A random program: globals, routines calling earlier ones, a main. Most
 * are valid: a parameter or a loop counter is only read, every integer is
 * a u16 but where a conversion is written, a product has a variable on one
 * side so that constants fold within 16 bits, and the signed global is
 * compared only with literals.
 */
function randomProgram(seed: number) {
  const { rnd, pick } = generator(seed);
  let text =
    "var ga: u16\nvar gb: u16\nvar gc: i16\nvar gf: boolean\n" +
    "var gt: u8[16]\nrecord Pt\n    x: u16\n    y: i16\nend\nvar gp: Pt\n";
  const routines: string[] = [];
  const word = (vars: string[], depth: number): string => {
    if (depth <= 0 || rnd(3) === 0) {
      return pick([...vars, `${rnd(100)}`, "gp.x", `u16(gt[${rnd(16)}])`]);
    }
    const r = rnd(9);
    if (r === 0 && routines.length) {
      return `${pick(routines)}(${word(vars, depth - 1)}, ${rnd(9)})`;
    }
    if (r === 1) return `(${word(vars, depth - 1)} mod ${1 + rnd(50)})`;
    if (r === 2) return `(${word(vars, depth - 1)} shl ${rnd(4)})`;
    if (r === 3) return `(${pick(vars)} * ${word(vars, depth - 1)})`;
    const op = pick(["+", "-", "and", "or", "xor"]);
    return `(${word(vars, depth - 1)} ${op} ${word(vars, depth - 1)})`;
  };
  const condition = (vars: string[]) =>
    pick([
      `${word(vars, 2)} < ${word(vars, 1)}`,
      `${word(vars, 1)} = ${rnd(50)}`,
      "gf",
      `not gf and ${word(vars, 1)} <> 0`,
      `gc < ${rnd(100) - 50}`,
    ]);
  const block = (
    reads: string[],
    writes: string[],
    depth: number,
    pad: string,
  ): string => {
    let out = "";
    for (let n = 1 + rnd(3); n > 0; n--) {
      const k = depth > 0 ? rnd(7) : rnd(3);
      const inner = pad + "    ";
      if (k <= 1) {
        const target = pick([...writes, "ga", "gb", "gp.x", `gt[${rnd(16)}]`]);
        out += target.startsWith("gt[")
          ? `${pad}${target} = u8(${word(reads, 2)} and 255)\n`
          : `${pad}${target} = ${word(reads, 3)}\n`;
      } else if (k === 2) {
        out += `${pad}gc = i16(${word(reads, 2)} and 255) - ${rnd(100)}\n`;
      } else if (k === 3) {
        out += `${pad}if ${condition(reads)}\n` +
          block(reads, writes, depth - 1, inner) +
          (rnd(2)
            ? `${pad}else\n${block(reads, writes, depth - 1, inner)}`
            : "") +
          `${pad}end\n`;
      } else if (k === 4) {
        const c = `k${depth}`;
        out += `${pad}for ${c} = 1 to ${1 + rnd(5)}\n` +
          block([...reads, c], writes, depth - 1, inner) + `${pad}end\n`;
      } else if (k === 5) {
        out += `${pad}select ${pick(reads)}\n`;
        for (let a = 1 + rnd(3), low = 0; a > 0; a--, low += 10) {
          out += `${pad}case ${low}${rnd(2) ? ` to ${low + 5}` : ""}\n` +
            block(reads, writes, depth - 1, inner);
        }
        out += (rnd(2)
          ? `${pad}case else\n${inner}gf = true\n`
          : `${pad}case else\n`) +
          `${pad}end\n`;
      } else {
        out += `${pad}gf = ${condition(reads)}\n`;
      }
    }
    return out;
  };
  const counters = (d: number) =>
    Array.from({ length: d + 1 }, (_, i) => `    var k${i}: u16\n`).join("");
  for (let r = 0; r < 3 + rnd(6); r++) {
    const name = `r${r}`;
    const body = block(["p", "q", "t"], ["t"], 2, "    ");
    text +=
      `sub ${name}(p: u16, q: u16): u16\n    var t: u16 = p + q\n` +
      `${counters(2)}${body}    return t + ${word(["p", "t"], 2)}\nend\n`;
    routines.push(name);
  }
  text += `sub main()\n    var m: u16 = ${rnd(100)}\n${counters(3)}` +
    block(["m", "ga", "gb"], ["m"], 3, "    ") + "end\n";
  return text;
}

Deno.test("random whole programs compile as the reference's", async () => {
  // STRESS_SEEDS=n runs n programs rather than the 40 of every build.
  const seeds = Number(Deno.env.get("STRESS_SEEDS") ?? 40);
  for (let seed = 1; seed <= seeds; seed++) {
    const text = randomProgram(seed * 7919);
    const run = native({ "RANDOM.BSI": text });
    const ref = await reference({ "RANDOM.BSI": text }, run.disk);
    if (!ref.ok) {
      // Refused alike: the reference's diagnostic at its line and column.
      if (!("diagnostics" in ref)) throw new Error("no diagnostic");
      const want = ref.diagnostics[0];
      const m = run.output.match(/ (\d+):(\d+): (\d+): /);
      assertEquals(
        m ? [Number(m[3]), Number(m[1]), Number(m[2])] : run.output,
        [want.number, want.line, want.column],
        `seed ${seed}: the reference refuses it`,
      );
      continue;
    }
    assertEquals(run.output, "", `seed ${seed}`);
    for (
      const [type, expected] of [
        ["$DR", ref.objects.directory],
        ["$BY", ref.objects.bytes],
        ["$LN", ref.objects.lines],
      ] as [string, Uint8Array][]
    ) {
      const file = run.disk.get(`RANDOM.${type}`)!;
      assertEquals(
        file.subarray(0, expected.length),
        expected,
        `seed ${seed} ${type}`,
      );
    }
  }
});

// ---- 69.3: a large program, linked and run ---------------------------

Deno.test("a program of 16 parts and 160 routines links and runs as the reference's", async () => {
  // The main part includes sixteen parts in turn, each of twenty variables
  // and ten routines, each routine adding into its part's variables and
  // calling the routine before it, the first of a part calling the last of
  // the part before; main calls the last and prints a checksum, which the
  // reference's build prints too.
  const parts: Parts = {};
  let include = "";
  for (let p = 0; p < 16; p++) {
    let text = lines(20, (i) => `var p${p}v${i}: u16\n`);
    for (let r = 0; r < 10; r++) {
      const prev = r ? `p${p}r${r - 1}` : p ? `p${p - 1}r9` : "";
      text += `sub p${p}r${r}(a: u16): u16\n` +
        `    p${p}v${r} = p${p}v${r} + a * ${r + 1}\n` +
        `    p${p}v${r + 10} = p${p}v${r} xor ${p * 10 + r}\n` +
        (prev
          ? `    return ${prev}(p${p}v${r} and 255) + 1\n`
          : "    return a\n") +
        "end\n";
    }
    parts[`L${p}.BSI`] = text;
    include += `include "L${p}.BSI"\n`;
  }
  const main =
    `${include}sub main() fails\n    var s: u16 = 0\n    var k: u16\n` +
    "    for k = 1 to 5\n        s = s + p15r9(k)\n    end\n" +
    '    try writeText(console, "sum ")\n' +
    "    try writeByte(console, u8(48 + (s mod 10)))\n" +
    '    try writeText(console, "\\r\\n")\nend\n';
  const all: Parts = { "LARGE.BSI": main, ...parts };
  const run = await alike("large", all);
  const blink = comBytes(await assembleFile("native/linker/BLINK.ASM"));
  const files: Record<string, Uint8Array> = {
    "BASIE.MSG": MSG,
    "CPM22.BRL": LIBRARY,
  };
  for (const t of ["$DR", "$BY", "$LN"]) {
    files[`LARGE.${t}`] = run.disk.get(`LARGE.${t}`)!;
  }
  const linked = runCom(blink, { tail: "LARGE", files, maxSteps: 200_000_000 });
  assertEquals(linked.output, "");
  const ref = await reference(all, run.disk);
  if (!ref.ok) throw new Error("the reference refuses it");
  const theirs = runCom(ref.com, { maxSteps: 50_000_000 });
  const ours = runCom(linked.disk.get("LARGE.COM")!, { maxSteps: 50_000_000 });
  assertEquals(ours.output, theirs.output);
  assertEquals(ours.output.startsWith("sum "), true, ours.output);
});
