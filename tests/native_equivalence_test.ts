/**
 * The native compiler's streams equal the reference compiler's (design
 * decision D45). Each claimed program in tests/native/programs is compiled
 * by the reference compiler with branch shrinking off and by BASIE.COM under
 * the CP/M harness, and NAME.$DR, $BY, $LN and $NM must agree byte for byte
 * before CP/M's padding of the last record, which must be zeros. The claimed
 * set only grows: a program once claimed must keep matching (native compiler
 * plan, 65.4).
 */
import { assertEquals } from "@std/assert";
import { buildBasie } from "../native/compiler/build.ts";
import { assembleFile, comBytes, runCom } from "./harness/cpm.ts";
import { buildRuntime } from "../tools/helpertable.ts";
import { messageFile } from "../ref/compile/messages.ts";

const { compile } = await import("../ref/compile/index.ts");
const basie = (await buildBasie()).com;
const DIR = "tests/native/programs";

/** Programs of the conformance suite inside the subset, by their 8.3 names. */
const CONFORMANCE: Record<string, string> = {
  NARROW: "tests/conformance/types/narrowing-traps.bsi",
  DIVZERO: "tests/conformance/expressions/division-by-zero-traps.bsi",
};

/** The source file of a claimed program. */
const path = (name: string) => CONFORMANCE[name] ?? `${DIR}/${name}.BSI`;

/** The claimed programs, by stage of 65.4. */
const CLAIMED: Record<string, string[]> = {
  "a: empty routines": ["EMPTY", "FAILS", "SUBS"],
  "b: declarations and references": ["DECLS", "REFS"],
  "c: expressions and assignment": [
    "WORDS",
    "BYTES",
    "MIXED",
    "COMPARE",
    "LOGIC",
    "FOLD",
    "TRAP",
  ],
  "d: locals and frames": ["LOCALS", "FARFRAME"],
  "e: calls, parameters and results": [
    "CALLS",
    "FORWARD",
    "AGGARGS",
    "WIDE",
    "RECURSE",
    "NARROW",
    "DIVZERO",
  ],
};

/** Compile NAME with BASIE.COM and the options; return the disk. */
function native(name: string, options = "") {
  const source = Deno.readFileSync(path(name));
  const run = runCom(basie, {
    tail: `${name}${options}`,
    files: { [`${name}.BSI`]: source },
    maxSteps: 50_000_000,
  });
  assertEquals(run.output, "", `${name}${options}`);
  return run.disk;
}

/** The reference's four streams for NAME, compiled with shrinking off. */
async function reference(name: string) {
  const result = await compile(`${name}.BSI`, {
    shrink: false,
    mainSource: Deno.readFileSync(path(name)),
  });
  if (!result.ok) {
    throw new Error(
      `${name}: the reference refuses it: ${JSON.stringify(result)}`,
    );
  }
  return {
    "$DR": result.objects.directory,
    "$BY": result.objects.bytes,
    "$LN": result.objects.lines,
    "$NM": result.objects.names,
  };
}

function same(
  name: string,
  file: Uint8Array | undefined,
  expected: Uint8Array,
) {
  if (!file) throw new Error(`${name} was not written`);
  assertEquals(file.length % 128, 0, `${name} is whole records`);
  assertEquals(file.subarray(0, expected.length), expected, name);
  const padding = file.subarray(expected.length);
  assertEquals(padding.every((b) => b === 0), true, `${name}'s padding`);
  assertEquals(padding.length < 128, true, `${name} has no spare record`);
}

for (const [stage, names] of Object.entries(CLAIMED)) {
  for (const name of names) {
    Deno.test(`${stage}: ${name} compiles to the reference's streams`, async () => {
      const streams = await reference(name);
      const disk = native(name, " [M]");
      for (const [type, expected] of Object.entries(streams)) {
        same(`${name}.${type}`, disk.get(`${name}.${type}`), expected);
      }
      // Without M or Y there is no name stream; with N, no line stream.
      const plain = native(name);
      assertEquals(plain.has(`${name}.$NM`), false);
      same(`${name}.$DR`, plain.get(`${name}.$DR`), streams.$DR);
      const lineless = native(name, " [N]");
      assertEquals(lineless.has(`${name}.$LN`), false);
      same(`${name}.$BY`, lineless.get(`${name}.$BY`), streams.$BY);
    });
  }
}

// Random assignments over the stage (c) subset, to program variables,
// (stage d) to locals and (stage e) to parameters: each compiles to the reference's streams, or both
// compilers refuse it. The generator is deterministic, so a failure names a
// statement that can be rerun.
Deno.test("c, d, e: random expressions compile as the reference compiles them", async () => {
  let seed = 654;
  const rnd = (n: number) => {
    seed = (seed * 1103515245 + 12345) & 0x7fffffff;
    return seed % n;
  };
  const pick = <T>(a: T[]) => a[rnd(a.length)];
  const nums = ["0", "1", "2", "7", "15", "200", "255", "256", "300", "65535"];
  const integer = (d: number): string => {
    if (d <= 0 || rnd(3) === 0) {
      return rnd(5) < 2
        ? pick([...nums, "k", "big", "'A'"])
        : pick(["a", "b", "x", "y"]);
    }
    const r = rnd(10);
    if (r === 0) return `u8(${integer(d - 1)})`;
    if (r === 1) return `u16(${integer(d - 1)})`;
    if (r === 2) return `(${integer(d - 1)})`;
    if (r === 3) return `-${integer(d - 1)}`;
    if (r === 4) return `not ${integer(d - 1)}`;
    const op = pick(["+", "-", "*", "/", "mod", "and", "or", "xor"]);
    return `${integer(d - 1)} ${op} ${integer(d - 1)}`;
  };
  const boolean = (d: number): string => {
    if (d <= 0 || rnd(4) === 0) {
      return pick(["f", "g", "true", "false", "yes", "no"]);
    }
    const r = rnd(7);
    if (r === 0) return `not ${boolean(d - 1)}`;
    if (r === 1) return `(${boolean(d - 1)})`;
    const rel = pick(["=", "<>", "<", "<=", ">", ">="]);
    if (r <= 3) return `${integer(d - 1)} ${rel} ${integer(d - 1)}`;
    if (r === 4) {
      return `${pick(["f", "g"])} ${pick(["=", "<>"])} ${boolean(d - 1)}`;
    }
    return `${boolean(d - 1)} ${pick(["and", "or"])} ${boolean(d - 1)}`;
  };
  const names = "var a as u8 = 200\nvar b as u8 = 9\nvar x as u16 = 1000\n" +
    "var y as u16 = 2\nvar f as boolean\nvar g as boolean = true\n";
  const consts =
    "const k = 12\nconst big = 60000\nconst yes = true\nconst no = false\n";
  const params = "a as u8, b as u8, x as u16, y as u16, f as boolean, " +
    "g as boolean";
  const heads = [
    [`${names}${consts}sub main()\n`, ""],
    [`${consts}sub main()\n${names}`, ""],
    [
      `${consts}sub run(${params})\n`,
      "sub main()\nrun(200, 9, 1000, 2, false, true)\nend\n",
    ],
  ];
  for (let i = 0; i < 300; i++) {
    const [head, tail] = heads[i % heads.length];
    const kind = rnd(3);
    const statement = kind === 0
      ? `${pick(["a", "b"])} = ${integer(4)}`
      : kind === 1
      ? `${pick(["x", "y"])} = ${integer(4)}`
      : `${pick(["f", "g"])} = ${boolean(4)}`;
    const source = new TextEncoder().encode(
      `${head}${statement}\nend\n${tail}`,
    );
    const ref = await compile("RANDOM.BSI", {
      shrink: false,
      mainSource: source,
    });
    const run = runCom(basie, {
      tail: "RANDOM",
      files: { "RANDOM.BSI": source },
      maxSteps: 50_000_000,
    });
    if (!ref.ok) {
      assertEquals(
        run.output !== "",
        true,
        `the reference refuses ${statement}`,
      );
      continue;
    }
    // The one refusal allowed: an exact value outside 0..65535, which the
    // native compiler cannot fold (Error 61; native compiler plan §5).
    if (/ Error 61\r\n$/.test(run.output)) continue;
    assertEquals(run.output, "", statement);
    same(statement, run.disk.get("RANDOM.$DR"), ref.objects.directory);
    same(statement, run.disk.get("RANDOM.$BY"), ref.objects.bytes);
    same(statement, run.disk.get("RANDOM.$LN"), ref.objects.lines);
  }
});

Deno.test("BLINK links BASIE.COM's streams and the programs run", async () => {
  const blink = comBytes(await assembleFile("native/linker/BLINK.ASM"));
  const library: Record<string, Uint8Array> = {
    "BASIE.MSG": messageFile(),
    "CPM22.BRL": (await buildRuntime()).file,
  };
  // TRAP's arithmetic decides which of its two narrowings traps; RECURSE
  // reaches its last statement's trap only when its results are right.
  const run = ["EMPTY", "TRAP", "CALLS", "FORWARD", "RECURSE", "DIVZERO"];
  for (const name of run) {
    const disk = native(name);
    const files = { ...library };
    for (const t of ["$DR", "$BY", "$LN"]) {
      files[`${name}.${t}`] = disk.get(`${name}.${t}`)!;
    }
    const linked = runCom(blink, { tail: name, files, maxSteps: 100_000_000 });
    assertEquals(linked.output, "", name);
    const com = linked.disk.get(`${name}.COM`)!;
    const ref = await compile(`${name}.BSI`, {
      shrink: false,
      mainSource: Deno.readFileSync(path(name)),
    });
    if (!ref.ok) throw new Error(`${name}: the reference refuses it`);
    const expected = runCom(ref.com, { maxSteps: 1_000_000 }).output;
    assertEquals(runCom(com, { maxSteps: 1_000_000 }).output, expected, name);
    if (name === "RECURSE") {
      assertEquals(/^TRAP narrowing/.test(expected), true);
    }
  }
});

// Programs both compilers refuse: the native compiler may refuse more than
// the reference, never less.
const REFUSED: Record<string, string> = {
  "a routine calls itself without a forward":
    "sub f(n as u8)\nf(n)\nend\nsub main()\nend\n",
  "a routine without a result used as a value":
    "var x as u8\nsub f()\nend\nsub main()\nx = f()\nend\n",
  "a parameter's storage returned":
    "sub f(p as u8[2]) as u8[2]\nreturn p\nend\nsub main()\nend\n",
  "too few arguments": "sub f(a as u8, b as u8)\nend\nsub main()\nf(1)\nend\n",
  "too many arguments": "sub f(a as u8)\nend\nsub main()\nf(1, 2)\nend\n",
  "an argument of the wrong type":
    "sub f(a as u8)\nend\nsub main()\nf(true)\nend\n",
  "an aggregate argument of the wrong type":
    "var s as u8[3]\nsub f(a as u8[2])\nend\nsub main()\nf(s)\nend\n",
  "a forward never completed": "forward sub f()\nsub main()\nend\n",
  "a routine named id": Deno.readTextFileSync(
    "tests/conformance/scopes/no-routine-named-id.bsi",
  ),
  "a forward completed twice":
    "forward sub f()\nsub f\nend\nsub f\nend\nsub main()\nend\n",
};

for (const [what, text] of Object.entries(REFUSED)) {
  Deno.test(`both compilers refuse ${what}`, async () => {
    const source = new TextEncoder().encode(text);
    const ref = await compile("REFUSED.BSI", {
      shrink: false,
      mainSource: source,
    });
    assertEquals(ref.ok, false, "the reference accepts it");
    const run = runCom(basie, {
      tail: "REFUSED",
      files: { "REFUSED.BSI": source },
      maxSteps: 50_000_000,
    });
    assertEquals(/ Error \d+\r\n$/.test(run.output), true, run.output);
  });
}
