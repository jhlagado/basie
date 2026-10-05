/**
 * The native compiler's streams equal the reference compiler's (design
 * decision D45). Each claimed program in tests/native/programs is compiled
 * by the reference compiler with branch shrinking off and by BASIE.COM under
 * the CP/M harness, and NAME.$DR, $BY, $LN and $NM must agree byte for byte
 * before CP/M's padding of the last record, which must be zeros. BASIE.COM
 * chooses each compilation's stamp as object format §4.1 asks, from the
 * source and the R register, where the reference always writes 1, so the
 * reference is given the stamp the native run chose (CompileOptions.stamp)
 * and the streams, their CRCs included, are compared whole. The claimed
 * set only grows: a program once claimed must keep matching (native compiler
 * plan, 65.4). The parts a program includes are on the disk beside it: the
 * source parts of its own folder and of lib/, as the reference finds them
 * (its libraryDirs).
 */
import { assertEquals } from "@std/assert";
import { dirname } from "@std/path";
import { buildBasie } from "../native/compiler/build.ts";
import { assembleFile, comBytes, runCom } from "./harness/cpm.ts";
import { buildRuntime } from "../tools/helpertable.ts";
import {
  formatMessage,
  messageFile,
  MESSAGES,
} from "../ref/compile/messages.ts";
import { parseExpectations } from "./conformance/expectations.ts";

const { compile } = await import("../ref/compile/index.ts");
const built = await buildBasie();
const basie = built.com;
const OVL = built.ovl;
const DIR = "tests/native/programs";

/** Programs of the conformance suite inside the subset, by their 8.3 names. */
const CONFORMANCE: Record<string, string> = {
  NARROW: "tests/conformance/types/narrowing-traps.bsi",
  DIVZERO: "tests/conformance/expressions/division-by-zero-traps.bsi",
  LOOPTRAP: "tests/conformance/statements/loop-range-traps.bsi",
  BOUNDS: "tests/conformance/basics/trap-bounds.bsi",
  INNERBND: "tests/conformance/types/inner-bound-traps.bsi",
  RECTRAP: "tests/conformance/scopes/recursion-traps.bsi",
  HELLO: "tests/conformance/basics/hello.bsi",
  CMDTAIL: "tests/conformance/services/command-tail.bsi",
  READLINE: "tests/conformance/services/console-read-line.bsi",
  APPEND: "tests/conformance/services/append-text.bsi",
  RUNCLOSE: "tests/conformance/services/end-of-run-close.bsi",
  RUNABORT: "tests/conformance/services/end-of-run-abort.bsi",
  WBOUNDS: "tests/conformance/services/write-block-bounds.bsi",
  NOJUMPS: "tests/conformance/expressions/discarded-arm-leaves-no-jumps.bsi",
  NOLIT: "tests/conformance/expressions/discarded-arm-leaves-no-literal.bsi",
  NESTED: "tests/conformance/types/arrays-of-arrays.bsi",
  INTURN: "tests/conformance/types/computed-indexes-in-turn.bsi",
  RECFWD: "tests/conformance/scopes/recursion-with-forward.bsi",
  DECLANY: "tests/conformance/declarations/declare-anywhere.bsi",
  LOCALCON: "tests/conformance/declarations/local-constant.bsi",
  SIBLING: "tests/conformance/scopes/sibling-blocks-reuse.bsi",
  KEYS: "tests/conformance/services/keys.bsi",
  PRIVPART: "tests/conformance/structure/private-across-parts.bsi",
  PRIVLOC: "tests/conformance/structure/private-is-part-local.bsi",
  INCONCE: "tests/conformance/structure/include-once.bsi",
  NEGIDX: "tests/conformance/expressions/negative-index-conversion-traps.bsi",
  NEGUNS: "tests/conformance/types/negative-to-unsigned-traps.bsi",
  BYTEWORD: "tests/conformance/types/byte-to-word-conversion.bsi",
  SAMETYPE: "tests/conformance/types/same-type-conversion.bsi",
  LOOPTR32: "tests/conformance/statements/loop-range-traps-32.bsi",
};

/** The source file of a claimed program. */
const path = (name: string) => CONFORMANCE[name] ?? `${DIR}/${name}.BSI`;

/** The claimed programs, by stage of 65.4 and of step 67. */
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
    "DISCARD",
  ],
  "i: services": [
    "SERVICES",
    "FILES",
    "HELLO",
    "CMDTAIL",
    "READLINE",
    "APPEND",
    "RUNCLOSE",
    "RUNABORT",
    "WBOUNDS",
    "NOJUMPS",
    "NOLIT",
    "NESTED",
    "INTURN",
    "RECFWD",
  ],
  "67a: declarations anywhere, block scope, typed and local constants": [
    "SCOPES",
    "CONSTS",
    "INFER",
    "LATER",
    "DECLANY",
    "LOCALCON",
    "SIBLING",
    "KEYS",
  ],
  "67a: include and private": ["INCMAIN", "PRIVPART", "PRIVLOC", "INCONCE"],
  "67b: signed bytes and words, shifts and exact values": [
    "SIGNED",
    "SHIFTS",
    "EXACT",
    "CONVERT",
    "SLOOPS",
    "RUNNUM",
    "NEGIDX",
    "NEGUNS",
    "BYTEWORD",
  ],
  "67b: 32-bit values, counters and file positions": [
    "LONGS",
    "LLOOPS",
    "RUNLONG",
    "LSEEK",
    "SAMETYPE",
    "LOOPTR32",
  ],
};

/** The CPM22 library, which BASIE.COM checks before it compiles. */
const LIBRARY = (await buildRuntime()).file;

/**
 * The source parts a program may include, by their CP/M names: the 8.3
 * upper-case parts of its folder (its includes' own folder), then lib/'s.
 */
function partsBeside(file: string): Record<string, Uint8Array> {
  const parts: Record<string, Uint8Array> = {};
  for (const dir of ["lib", dirname(file)]) {
    for (const f of Deno.readDirSync(dir)) {
      if (/^[A-Z0-9]{1,8}\.BSI$/.test(f.name)) {
        parts[f.name] = Deno.readFileSync(`${dir}/${f.name}`);
      }
    }
  }
  return parts;
}

/**
 * Compile NAME with BASIE.COM and the options, with C, so that BASIE does
 * not chain to BLINK; return the disk.
 */
function native(name: string, options = "") {
  const source = Deno.readFileSync(path(name));
  const run = runCom(basie, {
    tail: `${name} [C${options}]`,
    files: {
      ...partsBeside(path(name)),
      [`${name}.BSI`]: source,
      "CPM22.BRL": LIBRARY,
      "BASIE.OVL": OVL,
    },
    maxSteps: 50_000_000,
  });
  assertEquals(run.output, "", `${name}${options}`);
  return run.disk;
}

/** The compilation stamp BASIE.COM gave NAME's streams on a disk. */
function stampOf(disk: Map<string, Uint8Array>, name: string) {
  const directory = disk.get(`${name}.$DR`)!;
  return directory[6] | (directory[7] << 8);
}

/**
 * The reference's four streams for NAME, compiled with shrinking off and
 * the stamp the native run on the disk chose.
 */
async function reference(name: string, disk: Map<string, Uint8Array>) {
  const result = await compile(`${name}.BSI`, {
    shrink: false,
    mainSource: Deno.readFileSync(path(name)),
    libraryDirs: [dirname(path(name)), "lib"],
    stamp: stampOf(disk, name),
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
      const disk = native(name, ",M");
      const streams = await reference(name, disk);
      for (const [type, expected] of Object.entries(streams)) {
        same(`${name}.${type}`, disk.get(`${name}.${type}`), expected);
      }
      // Without M or Y there is no name stream; with N, no line stream.
      const plain = native(name);
      assertEquals(plain.has(`${name}.$NM`), false);
      same(
        `${name}.$DR`,
        plain.get(`${name}.$DR`),
        (await reference(name, plain)).$DR,
      );
      const lineless = native(name, ",N");
      assertEquals(lineless.has(`${name}.$LN`), false);
      same(
        `${name}.$BY`,
        lineless.get(`${name}.$BY`),
        (await reference(name, lineless)).$BY,
      );
    });
  }
}

// Random assignments over the stage (c) subset, to program variables,
// (stage d) to locals and (stage e) to parameters, some (stage f) inside
// an if or a while, (stage h) with fields, elements and characters as
// operands and targets, (stage i) with predeclared constants as operands
// and locals whose types are inferred, one from a service's result,
// (67a) with locals declared after a statement and inside the if or the
// while, typed constants as operands, and (67b) with i8 and i16
// variables, fields and elements, signed and wide exact constants,
// shifts and conversions to every byte and word type, and (67b) with u32
// and i32 variables, parameters, fields and constants and conversions to
// them: each compiles to
// the reference's streams, or both compilers refuse it, with the same
// diagnostic at the same place. The generator is deterministic, so a
// failure names a statement that can be rerun.
Deno.test("c to i: random expressions compile as the reference compiles them", async () => {
  let seed = 654;
  const rnd = (n: number) => {
    seed = (seed * 1103515245 + 12345) & 0x7fffffff;
    return seed % n;
  };
  const pick = <T>(a: T[]) => a[rnd(a.length)];
  const nums = [
    "0",
    "1",
    "2",
    "7",
    "15",
    "200",
    "255",
    "256",
    "300",
    "65535",
    "70000",
    "-5",
    "4294967295",
    "-200",
    "endOfInput",
    "binaryMode",
    "invalid",
  ];
  const paths = [
    "r.m",
    "r.n",
    "arr[1]",
    "arr[a and 3]",
    "wds[b mod 3]",
    "wds[2]",
    "s.length",
    "s[b and 3]",
    "r.p",
    "sarr[a and 1]",
    "r.w",
  ];
  const integer = (d: number): string => {
    if (d <= 0 || rnd(3) === 0) {
      const leaf = rnd(10);
      return leaf < 4
        ? pick([...nums, "k", "big", "'A'", "tk", "tw", "ti", "tn", "tl", "tm"])
        : leaf < 8
        ? pick(["a", "b", "x", "y", "p", "q", "l", "m"])
        : pick(paths);
    }
    const r = rnd(12);
    if (r === 0) {
      return `${pick(["u8", "i8", "u16", "i16", "u32", "i32"])}(${
        integer(d - 1)
      })`;
    }
    if (r === 1) {
      return `${integer(d - 1)} ${pick(["shl", "shr"])} ${
        pick(["1", "9", "a", "k"])
      }`;
    }
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
    "var y as u16 = 2\nvar f as boolean\nvar g as boolean = true\n" +
    "var p as i8 = -7\nvar q as i16 = -300\nvar l as u32 = 100000\n" +
    "var m as i32 = -70000\n";
  const consts =
    "const k = 12\nconst big = 60000\nconst yes = true\nconst no = false\n" +
    "const tk as u8 = 99\nconst tw as u16 = 4000\nconst ti as i8 = -9\n" +
    "const tn as i16 = -3000\nconst tl as u32 = 3000000000\n" +
    "const tm as i32 = -100000\n";
  const params = "a as u8, b as u8, x as u16, y as u16, f as boolean, " +
    "g as boolean, p as i8, q as i16, l as u32, m as i32";
  const record =
    "record rec\nm as u8\nn as u16\ng as boolean\np as i16\nw as u32\nend\n";
  const objects = "var r as rec\nvar arr as u8[4]\nvar wds as u16[3]\n" +
    'var s as string[5] = "abcd"\nvar sarr as i8[2]\n';
  const aggregates = record + objects;
  // (h) The fourth head makes the aggregates locals too; (i) the fifth
  // infers the locals' types from their initializers.
  const inferred = "var a = u8(200)\nvar b = currentUser() + 9\n" +
    "var x = u16(1000)\nvar y = u16(a) - 198\nvar f = a < 100\n" +
    "var g = true\nvar p = i8(-7)\nvar q = i16(a) - 500\n" +
    "var l = u32(x) * 100\nvar m = i32(q) * 140\n";
  const heads = [
    [`${aggregates}${names}${consts}sub main()\n`, ""],
    [`${aggregates}${consts}sub main()\n${names}`, ""],
    [
      `${aggregates}${consts}sub run(${params})\n`,
      "sub main()\nrun(200, 9, 1000, 2, false, true, -7, -300, 100000, -70000)\nend\n",
    ],
    [`${record}${consts}sub main()\n${names}${objects}`, ""],
    [`${aggregates}${consts}sub main()\n${inferred}`, ""],
    [
      `${record}${consts}sub main()\nvar z as u8 = 1\nz = z + 1\n${names}${objects}`,
      "",
    ],
  ];
  for (let i = 0; i < 300; i++) {
    const [head, tail] = heads[i % heads.length];
    const kind = rnd(4);
    const statement = kind === 0
      ? `${
        pick(["a", "b", "arr[b and 3]", "r.m", "s[a and 3]", "p", "sarr[1]"])
      } = ${integer(4)}`
      : kind === 1
      ? `${
        pick(["x", "y", "wds[x mod 3]", "r.n", "q", "r.p", "l", "m", "r.w"])
      } = ${integer(4)}`
      : kind === 2
      ? `${pick(["f", "g", "r.g"])} = ${boolean(4)}`
      : `${pick(["arr[1]", "wds[y and 1]"])} = ${integer(3)}`;
    // (f) Every fifth statement sits in an if or a while with a random
    // condition.
    // (67a) A local declared in the block comes and goes with it.
    const local = rnd(2) === 0 ? "" : `var t${i} as u16 = ${integer(2)}\n`;
    const body = i % 5 !== 4
      ? statement
      : rnd(2) === 0
      ? `if ${boolean(2)}\n${local}${statement}\nelseif ${
        boolean(1)
      }\n${local}else\n${local}end`
      : `while ${boolean(2)}\n${local}${statement}\nend`;
    const source = new TextEncoder().encode(
      `${head}${body}\nend\n${tail}`,
    );
    const run = runCom(basie, {
      tail: "RANDOM [C]",
      files: { "RANDOM.BSI": source, "CPM22.BRL": LIBRARY, "BASIE.OVL": OVL },
      maxSteps: 50_000_000,
    });
    const ref = await compile("RANDOM.BSI", {
      shrink: false,
      mainSource: source,
      stamp: run.disk.has("RANDOM.$DR") ? stampOf(run.disk, "RANDOM") : 1,
    });
    if (!ref.ok) {
      // Refused alike: the reference's diagnostic, at its line and column.
      if (!("diagnostics" in ref)) throw new Error("no diagnostic");
      const want = ref.diagnostics[0];
      const m = run.output.match(/ (\d+):(\d+): (\d+): /);
      assertEquals(
        m ? [Number(m[3]), Number(m[1]), Number(m[2])] : run.output,
        [want.number, want.line, want.column],
        `the reference refuses ${body}`,
      );
      continue;
    }
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
    "CPM22.BRL": LIBRARY,
  };
  // TRAP's arithmetic decides which of its two narrowings traps; RECURSE,
  // RUNFLOW and RUNPATHS reach their last statement's trap only when their
  // results are right; LOOPTRAP traps leaving its counter's type, BOUNDS,
  // INNERBND and WBOUNDS indexing past an array's end, RECTRAP recursing
  // without end. Each runs with the console input, command tail and files
  // its expectations give, and its output, return code and files must be
  // the reference build's.
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
    ...CLAIMED["i: services"],
    ...CLAIMED[
      "67a: declarations anywhere, block scope, typed and local constants"
    ],
    ...CLAIMED["67a: include and private"],
    ...CLAIMED["67b: signed bytes and words, shifts and exact values"],
    ...CLAIMED["67b: 32-bit values, counters and file positions"],
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
      libraryDirs: [dirname(path(name)), "lib"],
    });
    if (!ref.ok) throw new Error(`${name}: the reference refuses it`);
    const want = parseExpectations(Deno.readTextFileSync(path(name)));
    const options = {
      input: want.input,
      tail: want.tail,
      files: want.files,
      maxSteps: 5_000_000,
    };
    const theirs = runCom(ref.com, options);
    const ours = runCom(com, options);
    const expected = theirs.output;
    assertEquals(ours.output, expected, name);
    assertEquals(ours.returnCode, theirs.returnCode, name);
    for (const [file, data] of theirs.disk) {
      if (!file.startsWith(`${name}.`)) {
        assertEquals(ours.disk.get(file), data, `${name}: ${file}`);
      }
    }
    if (want.output !== undefined) assertEquals(expected, want.output, name);
    if (
      [
        "RECURSE",
        "RUNFLOW",
        "RUNNUM",
        "NEGIDX",
        "NEGUNS",
        "BYTEWORD",
        "RUNLONG",
        "LSEEK",
        "SAMETYPE",
      ].includes(name)
    ) {
      assertEquals(/^TRAP narrowing/.test(expected), true);
    }
    if (["LOOPTRAP", "LOOPTR32"].includes(name)) {
      assertEquals(/^TRAP loop-range/.test(expected), true);
    }
    if (["RUNPATHS", "BOUNDS", "INNERBND", "WBOUNDS"].includes(name)) {
      assertEquals(/^TRAP bounds/.test(expected), true);
    }
    if (name === "RECTRAP") {
      assertEquals(/^TRAP activation-capacity/.test(expected), true);
    }
  }
});

// Programs both compilers refuse: the native compiler may refuse more than
// the reference, never less. Each is refused with the reference's
// diagnostic: its number and code, at its part, line and column, and, where
// both compilers supply them, with its arguments (BASIE.MSG's ^1 and ^2).
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
  // i: services and the predeclared names.
  "a routine named after a service": "sub size()\nend\nsub main()\nend\n",
  "a variable named after a constant":
    "var fileNotFound as u8\nsub main()\nend\n",
  "a local named console": "sub main()\nvar console as u8\nend\n",
  "a parameter named close": "sub f(close as u8)\nend\nsub main()\nend\n",
  "a record named printer": "record printer\na as u8\nend\nsub main()\nend\n",
  "a constant named textMode": "const textMode = 2\nsub main()\nend\n",
  "a predeclared constant assigned": "sub main()\nendOfInput = 2\nend\n",
  "a service named as a value": "var x as u8\nsub main()\nx = readKey\nend\n",
  "a service's failure unconsumed":
    "sub main() fails\nwriteByte(console, 1)\nend\n",
  "else fail after a service that cannot fail":
    "sub main() fails\nresetDisks() else fail\nend\n",
  "a service given too few arguments":
    "sub main() fails\nwriteText(console) else fail\nend\n",
  "a number passed as a File":
    "sub main() fails\nwriteByte(1, 2) else fail\nend\n",
  "a File as an operand":
    "var f as File\nvar x as u16\nsub main()\nx = f + 1\nend\n",
  "a File where a number is wanted":
    "var x as u8\nsub main()\nx = console\nend\n",
  "a literal passed to a var string[]":
    'sub main() fails\nreadLine(console, "abc") else fail\nend\n',
  "a string[] parameter passed to a var string[]":
    "sub f(s as string[]) fails\nreadLine(console, s) else fail\nend\nsub main()\nend\n",
  "a constant passed to a var string[]":
    'const k as string[4] = "ab"\nsub main() fails\nreadLine(console, k) else fail\nend\n',
  "a u16 array passed as a u8[]":
    "var w as u16[4]\nsub main() fails\nwriteBlock(console, w, 2) else fail\nend\n",
  "a string passed as a u8[]":
    "var s as string[4]\nsub main() fails\nwriteBlock(console, s, 2) else fail\nend\n",
  "an array passed as a string[]":
    "var c as u8[4]\nsub main() fails\nwriteText(console, c) else fail\nend\n",
  "a File as a step":
    "sub main()\nvar i as u8\nfor i = 1 to 3 step console\nend\nend\n",
  "a zero step from a predeclared constant":
    "sub main()\nvar i as u8\nfor i = 1 to 3 step textMode\nend\nend\n",
  "an exact initializer without a type": "sub main()\nvar n = 5\nend\n",
  "a literal initializer without a type": 'sub main()\nvar s = "ab"\nend\n',
  "a local without a type or an initializer": "sub main()\nvar n\nend\n",
  "a File local from a number": "sub main()\nvar f as File = 3\nend\n",
  "a File assigned a Boolean": "var f as File\nsub main()\nf = true\nend\n",
  "a field of a File": "var f as File\nvar x as u8\nsub main()\nx = f.a\nend\n",
  // 67a: declarations anywhere, block scope, typed and local constants.
  "a local used after its block": Deno.readTextFileSync(
    "tests/conformance/scopes/block-scope-ends.bsi",
  ),
  "a local hiding an enclosing block's": Deno.readTextFileSync(
    "tests/conformance/scopes/no-shadowing.bsi",
  ),
  "a local hiding a parameter":
    "sub f(n as u8)\nif n > 1\nvar n as u8\nend\nend\nsub main()\nend\n",
  "a local hiding a program variable":
    "var g as u8\nsub main()\ng = 1\nvar g as u8\nend\n",
  "a local declared twice in one block":
    "sub main()\nif true\nvar a as u8\nvar a as u16\nend\nend\n",
  "a local constant hiding a routine":
    "sub f()\nend\nsub main()\nconst f = 1\nend\n",
  "a local constant declared twice":
    "sub main()\nconst k = 1\nwhile true\nconst j = 2\nconst j = 3\nend\nend\n",
  "a local hiding a later block's counter":
    "sub main()\nvar i as u8\nfor i = 1 to 2\nvar i as u16\nend\nend\n",
  "a counter declared inside its loop":
    "sub main()\nfor i = 1 to 2\nvar i as u8\nend\nend\n",
  "a typed constant out of range": Deno.readTextFileSync(
    "tests/conformance/declarations/typed-constant-range.bsi",
  ),
  "a local typed constant out of range":
    "sub main()\nconst k as u8 = 256\nend\n",
  "an untyped constant of a u16 value": "const k = u16(5)\nsub main()\nend\n",
  "a typed constant of the wrong type":
    "const k as u8 = true\nsub main()\nend\n",
  "a typed constant assigned": "const k as u8 = 1\nsub main()\nk = 2\nend\n",
  "a typed Boolean constant as a step":
    "const b as boolean = true\nsub main()\nvar i as u8\nfor i = 1 to 3 step b\nend\nend\n",
  "a character expression inferred": "sub main()\nvar c = 'A' + 1\nend\n",
  "an untyped constant inferred": "const k = 'A'\nsub main()\nvar c = k\nend\n",
  "an open string inferred":
    "sub f(s as string[])\nvar t = s\nend\nsub main()\nend\n",
  "main declared twice": "sub main()\nend\nsub main()\nend\n",
  "main completed as a forward": "sub main()\nend\nsub main\nend\n",
  "a forward declared again in full":
    "forward sub f()\nsub f()\nend\nsub main()\nend\n",
  "a completed forward declared again":
    "forward sub f()\nsub f\nend\nsub f()\nend\nsub main()\nend\n",
  // 67b: the signed types, shifts, conversions and exact values.
  "mixed signs in an operation":
    "var a as u16\nvar b as i16\nsub main()\na = a + b\nend\n",
  "an i8 assigned to a u16":
    "var a as u16\nvar b as i8 = 3\nsub main()\na = b\nend\n",
  "a negative shift count": "var a as u8\nsub main()\na = a shl -1\nend\n",
  "a signed shift count":
    "var a as u8\nvar s as i8 = 1\nsub main()\na = a shl s\nend\n",
  "a conversion to Boolean": "var a as u8\nsub main()\na = boolean(1)\nend\n",
  "a Boolean converted":
    "var a as u8\nvar f as boolean\nsub main()\na = u8(f)\nend\n",
  "a decimal number beyond 32 bits":
    "var a as u16\nsub main()\na = 5000000000\nend\n",
  "an exact result beyond 32 bits":
    "var a as u16\nsub main()\na = 4294967295 + 1 - 1\nend\n",
  "an i8 index":
    "var cells as u8[4]\nvar i as i8 = 1\nsub main()\ncells[i] = 1\nend\n",
  "a negative constant index":
    "var cells as u8[4]\nsub main()\ncells[-1] = 1\nend\n",
  "a step beyond an i8 counter":
    "sub main()\nvar i as i8\nfor i = 0 to 10 step 128\nend\nend\n",
  "a negative named step":
    "sub main()\nvar i as i16\nconst s as i8 = -2\nfor i = 0 to 10 step s\nend\nend\n",
  "an i8 assigned 200": "var c as i8\nsub main()\nc = 200\nend\n",
  "an exact conversion that does not fit":
    "var c as i8\nsub main()\nc = i8(200)\nend\n",
  "an exact shift beyond the range":
    "var w as u16\nsub main()\nw = (1 shl 40) shr 30\nend\n",
  "an exact negative and": "var w as u16\nsub main()\nw = -1 and 3\nend\n",
  "an exact product beyond 32 bits":
    "var w as u16\nsub main()\nw = 65536 * 65536\nend\n",
  "a constant of mixed signs": "const k = u8(3) + i8(2)\nsub main()\nend\n",
  "an untyped constant of an i16 value": "const k = i16(3)\nsub main()\nend\n",
  "an exact division by zero": "var w as u16\nsub main()\nw = 7 / 0\nend\n",
  "a signed division by zero": "var w as i16\nsub main()\nw = w / 0\nend\n",
  "an i8 bound for a u8 counter":
    "sub main()\nvar i as u8\nvar b as i8 = 3\nfor i = 0 to b\nend\nend\n",
  "a hexadecimal number of nine digits":
    "var a as i8\nsub main()\na = $FFFFFFFFF\nend\n",
  "a number running into a name": "var a as u8\nsub main()\na = 12a\nend\n",
  "an i32 assigned 3000000000":
    "var m as i32\nsub main()\nm = 3000000000\nend\n",
  "a u32 assigned a negative": "var l as u32\nsub main()\nl = -1\nend\n",
  "a u32 mixed with an i32":
    "var l as u32\nvar m as i32\nsub main()\nl = l + m\nend\n",
  "a u32 index":
    "var cells as u8[4]\nvar l as u32\nsub main()\ncells[l] = 1\nend\n",
  "a step beyond an i32 counter":
    "sub main()\nvar j as i32\nfor j = 0 to 10 step 2147483648\nend\nend\n",
  "a u32 assigned to a u16 unconverted":
    "var w as u16\nvar l as u32\nsub main()\nw = l\nend\n",
  "a u32 exact sum beyond its range":
    "var l as u32\nsub main()\nl = 4294967295 + 1\nend\n",
};

/** The code of a message number, from the message table. */
const codeOf = (n: number) => MESSAGES.find((m) => m.number === n)?.code;

// Programs of the conformance suite both compilers refuse, with the parts
// of their folder beside them (67a: include and private).
const REFUSED_WITH_PARTS: Record<string, string> = {
  "an include after a declaration":
    "tests/conformance/structure/include-after-declaration.bsi",
  "a declaration split across parts":
    "tests/conformance/structure/split-declaration.bsi",
  "an include of a part not on the disk":
    "tests/conformance/structure/include-missing.bsi",
  "an include cycle": "tests/conformance/structure/include-cycle.bsi",
  "an include with a wildcard":
    "tests/conformance/structure/include-wildcard.bsi",
  "an include without a type":
    "tests/conformance/structure/include-needs-type.bsi",
  "a private forward left open in its part":
    "tests/conformance/structure/private-forward-in-part.bsi",
  "a public forward completed as private":
    "tests/conformance/structure/private-completion-mismatch.bsi",
  "a part's private name used by the part that includes it":
    "tests/native/programs/INCPRIV.BSI",
  "a lexical error in an included part's first line":
    "tests/native/programs/INCLEX.BSI",
  "an include of a name too long": "tests/native/programs/INCLONG.BSI",
  "an include of a string with more after it":
    "tests/native/programs/INCMORE.BSI",
  "an include of no name": "tests/native/programs/INCNONE.BSI",
};

const refusals: [string, string, string | undefined][] = [
  ...Object.entries(REFUSED).map(([w, t]): [string, string, undefined] => [
    w,
    t,
    undefined,
  ]),
  ...Object.entries(REFUSED_WITH_PARTS).map((
    [w, f],
  ): [string, string, string] => [w, Deno.readTextFileSync(f), f]),
];

for (const [what, text, file] of refusals) {
  Deno.test(`both compilers refuse ${what}`, async () => {
    const source = new TextEncoder().encode(text);
    const ref = await compile("REFUSED.BSI", {
      shrink: false,
      mainSource: source,
      ...(file ? { libraryDirs: [dirname(file), "lib"] } : {}),
    });
    if (ref.ok || !("diagnostics" in ref)) {
      throw new Error("the reference accepts it");
    }
    const want = ref.diagnostics[0];
    const run = runCom(basie, {
      tail: "REFUSED",
      files: {
        ...(file ? partsBeside(file) : {}),
        "REFUSED.BSI": source,
        "CPM22.BRL": LIBRARY,
        "BASIE.OVL": OVL,
        "BASIE.MSG": messageFile(),
      },
      maxSteps: 50_000_000,
    });
    // As the reference toolchain prints it: PART LINE:COLUMN: N: text.
    const m = run.output.match(/^(\S+) (\d+):(\d+): (\d+): (.*)\r\n$/);
    if (!m) throw new Error(`not a diagnostic: ${JSON.stringify(run.output)}`);
    const number = Number(m[4]);
    assertEquals(
      {
        part: m[1],
        code: codeOf(number),
        number,
        line: Number(m[2]),
        column: Number(m[3]),
      },
      {
        part: want.part,
        code: want.code,
        number: want.number,
        line: want.line,
        column: want.column,
      },
      want.message,
    );
    // The native compiler supplied arguments when its text is not the
    // template's with none; then they must be the reference's, if it
    // supplies them too.
    if (want.args && m[5] !== formatMessage(number, [])) {
      assertEquals(m[5], formatMessage(number, want.args));
    }
  });
}
