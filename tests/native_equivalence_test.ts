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
  LOOPTRAP: "tests/conformance/statements/loop-range-traps.bsi",
  BOUNDS: "tests/conformance/basics/trap-bounds.bsi",
  INNERBND: "tests/conformance/types/inner-bound-traps.bsi",
  RECTRAP: "tests/conformance/scopes/recursion-traps.bsi",
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
  "f: control flow": ["IFS", "LOOPS", "FORS", "FLOW", "LOOPTRAP"],
  "g: failure": ["FAILURE", "RUNFLOW"],
  "h: records, arrays and strings": [
    "PATHS",
    "COPIES",
    "VIEWS",
    "FARPATH",
    "RUNPATHS",
    "BOUNDS",
    "LOCALAGG",
    "GRID",
    "INNERBND",
    "RECTRAP",
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
// (stage d) to locals and (stage e) to parameters, some (stage f) inside
// an if or a while, (stage h) with fields, elements and characters as
// operands and targets: each compiles to the reference's streams, or both
// compilers refuse it. The generator is deterministic, so a failure names a
// statement that can be rerun.
Deno.test("c to h: random expressions compile as the reference compiles them", async () => {
  let seed = 654;
  const rnd = (n: number) => {
    seed = (seed * 1103515245 + 12345) & 0x7fffffff;
    return seed % n;
  };
  const pick = <T>(a: T[]) => a[rnd(a.length)];
  const nums = ["0", "1", "2", "7", "15", "200", "255", "256", "300", "65535"];
  const paths = [
    "r.m",
    "r.n",
    "arr[1]",
    "arr[a and 3]",
    "wds[b mod 3]",
    "wds[2]",
    "s.length",
    "s[b and 3]",
  ];
  const integer = (d: number): string => {
    if (d <= 0 || rnd(3) === 0) {
      const leaf = rnd(10);
      return leaf < 4
        ? pick([...nums, "k", "big", "'A'"])
        : leaf < 8
        ? pick(["a", "b", "x", "y"])
        : pick(paths);
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
      return pick(["f", "g", "true", "false", "yes", "no", "r.g"]);
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
  const record = "record rec\nm as u8\nn as u16\ng as boolean\nend\n";
  const objects = "var r as rec\nvar arr as u8[4]\nvar wds as u16[3]\n" +
    'var s as string[5] = "abcd"\n';
  const aggregates = record + objects;
  // (h) The fourth head makes the aggregates locals too.
  const heads = [
    [`${aggregates}${names}${consts}sub main()\n`, ""],
    [`${aggregates}${consts}sub main()\n${names}`, ""],
    [
      `${aggregates}${consts}sub run(${params})\n`,
      "sub main()\nrun(200, 9, 1000, 2, false, true)\nend\n",
    ],
    [`${record}${consts}sub main()\n${names}${objects}`, ""],
  ];
  for (let i = 0; i < 300; i++) {
    const [head, tail] = heads[i % heads.length];
    const kind = rnd(4);
    const statement = kind === 0
      ? `${pick(["a", "b", "arr[b and 3]", "r.m", "s[a and 3]"])} = ${
        integer(4)
      }`
      : kind === 1
      ? `${pick(["x", "y", "wds[x mod 3]", "r.n"])} = ${integer(4)}`
      : kind === 2
      ? `${pick(["f", "g", "r.g"])} = ${boolean(4)}`
      : `${pick(["arr[1]", "wds[y and 1]"])} = ${integer(3)}`;
    // (f) Every fifth statement sits in an if or a while with a random
    // condition.
    const body = i % 5 !== 4
      ? statement
      : rnd(2) === 0
      ? `if ${boolean(2)}\n${statement}\nelseif ${boolean(1)}\nelse\nend`
      : `while ${boolean(2)}\n${statement}\nend`;
    const source = new TextEncoder().encode(
      `${head}${body}\nend\n${tail}`,
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
        `the reference refuses ${body}`,
      );
      continue;
    }
    // The one refusal allowed: an exact value outside 0..65535, which the
    // native compiler cannot fold (Error 61; native compiler plan §5).
    if (/ Error 61\r\n$/.test(run.output)) continue;
    assertEquals(run.output, "", body);
    same(body, run.disk.get("RANDOM.$DR"), ref.objects.directory);
    same(body, run.disk.get("RANDOM.$BY"), ref.objects.bytes);
    same(body, run.disk.get("RANDOM.$LN"), ref.objects.lines);
  }
});

Deno.test("BLINK links BASIE.COM's streams and the programs run", async () => {
  const blink = comBytes(await assembleFile("native/linker/BLINK.ASM"));
  const library: Record<string, Uint8Array> = {
    "BASIE.MSG": messageFile(),
    "CPM22.BRL": (await buildRuntime()).file,
  };
  // TRAP's arithmetic decides which of its two narrowings traps; RECURSE,
  // RUNFLOW and RUNPATHS reach their last statement's trap only when their
  // results are right; LOOPTRAP traps leaving its counter's type, BOUNDS
  // and INNERBND indexing past an array's end, RECTRAP recursing without
  // end.
  const run = [
    "EMPTY",
    "TRAP",
    "CALLS",
    "FORWARD",
    "RECURSE",
    "DIVZERO",
    "LOOPS",
    "FORS",
    "FAILURE",
    "RUNFLOW",
    "LOOPTRAP",
    "PATHS",
    "RUNPATHS",
    "BOUNDS",
    "LOCALAGG",
    "GRID",
    "INNERBND",
    "RECTRAP",
  ];
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
    if (name === "RECURSE" || name === "RUNFLOW") {
      assertEquals(/^TRAP narrowing/.test(expected), true);
    }
    if (name === "LOOPTRAP") {
      assertEquals(/^TRAP loop-range/.test(expected), true);
    }
    if (["RUNPATHS", "BOUNDS", "INNERBND"].includes(name)) {
      assertEquals(/^TRAP bounds/.test(expected), true);
    }
    if (name === "RECTRAP") {
      assertEquals(/^TRAP activation-capacity/.test(expected), true);
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
  "a value routine whose if has no else":
    "sub f(n as u8) as u8\nif n = 0\nreturn 1\nend\nend\nsub main()\nend\n",
  "a value routine ending in a loop":
    "sub f() as u8\nwhile true\nreturn 1\nend\nend\nsub main()\nend\n",
  "exit outside a loop": "sub main()\nexit\nend\n",
  "continue inside an if outside a loop":
    "sub main()\nif true\ncontinue\nend\nend\n",
  "a loop counter assigned":
    "sub main()\nvar i as u8\nfor i = 1 to 3\ni = 2\nend\nend\n",
  "a loop counter counting again":
    "sub main()\nvar i as u8\nfor i = 1 to 3\nfor i = 1 to 2\nend\nend\nend\n",
  "a loop counter as a handler's variable":
    "sub f() fails\nend\nsub main()\nvar i as u8\nfor i = 1 to 3\nf() handle i\nend\nend\nend\n",
  "a parameter as a counter":
    "sub f(i as u8)\nfor i = 1 to 3\nend\nend\nsub main()\nend\n",
  "a Boolean counter":
    "sub main()\nvar b as boolean\nfor b = 1 to 3\nend\nend\n",
  "a program variable as a counter":
    "var i as u8\nsub main()\nfor i = 1 to 3\nend\nend\n",
  "a step wider than a u8 counter":
    "sub main()\nvar i as u8\nfor i = 1 to 3 step 256\nend\nend\n",
  "a zero step": "sub main()\nvar i as u8\nfor i = 1 to 3 step 0\nend\nend\n",
  "a computed step":
    "var s as u8 = 1\nsub main()\nvar i as u8\nfor i = 1 to 3 step s\nend\nend\n",
  "a Boolean bound": "sub main()\nvar i as u8\nfor i = 1 to true\nend\nend\n",
  "a non-Boolean condition": "sub main()\nif 1\nend\nend\n",
  "a failable call unconsumed":
    "sub f() fails\nend\nsub main() fails\nf()\nend\n",
  "else fail in a routine that cannot fail":
    "sub f() fails\nend\nsub main()\nf() else fail\nend\n",
  "else fail after a call that cannot fail":
    "sub f()\nend\nsub main() fails\nf() else fail\nend\n",
  "handle after a call that cannot fail":
    "var e as u8\nsub f()\nend\nsub main()\nf() handle e\nend\nend\n",
  "a failable call as an operand's left":
    "sub f() as u8 fails\nreturn 1\nend\nsub main() fails\nvar x as u8\nx = f() + 1 else fail\nend\n",
  "a failable call in parentheses":
    "sub f() as u8 fails\nreturn 1\nend\nsub main() fails\nvar x as u8\nx = (f()) else fail\nend\n",
  "a failable call as an argument":
    "sub f() as u8 fails\nreturn 1\nend\nsub g(a as u8)\nend\nsub main() fails\ng(f()) else fail\nend\n",
  "a failable call in a condition":
    "sub f() as boolean fails\nreturn true\nend\nsub main() fails\nif f() else fail\nend\nend\n",
  "a failable call in a return":
    "sub f() as u8 fails\nreturn 1\nend\nsub g() as u8 fails\nreturn f() else fail\nend\nsub main()\nend\n",
  "a handler after a local's initializer":
    "var e as u8\nsub f() as u8 fails\nreturn 1\nend\nsub main()\nvar x as u8 = f() handle e\nend\nend\n",
  "a handler's variable of the wrong type":
    "var e as u16\nsub f() fails\nend\nsub main()\nf() handle e\nend\nend\n",
  "a handler's variable a constant":
    "const e = 1\nsub f() fails\nend\nsub main()\nf() handle e\nend\nend\n",
  "fail in a routine that cannot fail": "sub main()\nfail 1\nend\n",
  "fail with a u16 code": "sub f() fails\nfail 300\nend\nsub main()\nend\n",
  "else if for elseif": "sub main()\nif true\nelse if false\nend\nend\nend\n",
  "a failable start value":
    "sub f() as u8 fails\nreturn 1\nend\nsub main() fails\nvar i as u8\nfor i = f() else fail to 3\nend\nend\n",
  "else fail followed by a handler":
    "var e as u8\nsub f() fails\nend\nsub main() fails\nf() else fail handle e\nend\nend\n",
  // h: records, arrays and strings.
  "a constant index past the end":
    "var c as u8[4]\nsub main()\nc[4] = 1\nend\n",
  "a record indexed":
    "record r\na as u8\nend\nvar v as r\nsub main()\nv[0] = 1\nend\n",
  "a field of an array": "var c as u8[4]\nsub main()\nc.a = 1\nend\n",
  "a field of a scalar field":
    "record r\na as u8\nend\nvar v as r\nsub main()\nv.a.b = 1\nend\n",
  "a field the record lacks":
    "record r\na as u8\nend\nvar v as r\nsub main()\nv.b = 1\nend\n",
  "a Boolean index": "var c as u8[4]\nsub main()\nc[true] = 1\nend\n",
  "a field of a constant assigned":
    "record r\na as u8\nend\nconst k as r = (1)\nsub main()\nk.a = 2\nend\n",
  "a field of a parameter assigned":
    "record r\na as u8\nend\nsub f(p as r)\np.a = 2\nend\nsub main()\nend\n",
  "a string's length assigned":
    "var s as string[4]\nsub main()\ns.length = 2\nend\n",
  "a declared string's capacity":
    "var s as string[4]\nvar x as u8\nsub main()\nx = s.capacity\nend\n",
  "a literal longer than its string":
    'var s as string[4]\nsub main()\ns = "hello"\nend\n',
  "a literal copied to an array": 'var c as u8[4]\nsub main()\nc = "ab"\nend\n',
  "a copy between strings of two capacities":
    "var s as string[4]\nvar t as string[5]\nsub main()\ns = t\nend\n",
  "a call's result passed as a view":
    "var s as string[4]\nsub g() as string[4]\nreturn s\nend\nsub f(v as string[])\nend\nsub main()\nf(g())\nend\n",
  "a scalar passed as a view":
    "var x as u8\nsub f(v as string[])\nend\nsub main()\nf(x)\nend\n",
  "an array passed as a view":
    "var c as u8[4]\nsub f(v as string[])\nend\nsub main()\nf(c)\nend\n",
  "a result rooted at a parameter's field":
    "record r\nc as u8[2]\nend\nsub f(p as r) as u8[2]\nreturn p.c\nend\nsub main()\nend\n",
  "a result whose path a local indexes":
    "var t as u8[2][2]\nsub g() as u8[2][2]\nreturn t\nend\nsub f() as u8[2]\nvar i as u8\nreturn g()[i]\nend\nsub main()\nend\n",
  "an aggregate result of the wrong type":
    "var s as string[8]\nsub f() as u8[4]\nreturn s\nend\nsub main()\nend\n",
  "an aggregate as a scalar value":
    "var c as u8[4]\nvar x as u8\nsub main()\nx = c\nend\n",
  "an element of an aggregate result's scalar":
    "record r\na as u8\nend\nvar v as r\nsub f() as r\nreturn v\nend\nvar x as u8\nsub main()\nx = f().a.b\nend\n",
  "a local named in a returned path": Deno.readTextFileSync(
    "tests/conformance/statements/return-local-alias.bsi",
  ),
  "an open string as a local": Deno.readTextFileSync(
    "tests/conformance/types/open-view-not-local.bsi",
  ),
  "a local copied from a string of another capacity":
    "var t as string[5]\nsub main()\nvar s as string[4] = t\nend\n",
  "a local array's initializer one short":
    "sub main()\nvar a as u8[3] = [1, 2]\nend\n",
  "a literal longer than a local string":
    'sub main()\nvar s as string[2] = "abc"\nend\n',
  "a zero array bound": "sub main()\nvar a as u8[0]\nend\n",
  "an array bound that is a variable":
    "var n as u8 = 2\nsub main()\nvar a as u8[n]\nend\n",
  "an inner index past its own bound":
    "var g as u8[2][3]\nsub main()\ng[1][3] = 1\nend\n",
  "a local record from a call that fails, unhandled":
    "record r\na as u8\nend\nvar v as r\nsub f() as r fails\nreturn v\nend\nsub main()\nvar x as r = f()\nend\n",
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
