/**
 * The native compiler's streams equal the reference compiler's (design
 * decision D45). Each claimed program in tests/native/programs is compiled
 * by the reference compiler, its jumps shrunk as its default build shrinks
 * them (BASIE.COM always shrinks; the toolchain has no option to turn it
 * off, so a comparison without shrinking would add nothing), and by BASIE.COM under
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

/** Programs of the conformance suite and the examples inside the subset, by their 8.3 names. */
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
  FROMCL: "tests/conformance/statements/from-clause.bsi",
  FARFIELD: "tests/conformance/statements/var-parameter-far-field.bsi",
  ASSERTT: "tests/conformance/statements/assert-traps.bsi",
  TXTCON: "tests/conformance/library/text-console.bsi",
  TRUNCREF: "tests/conformance/library/truncate-refuses.bsi",
  DIRECTRY: "tests/conformance/services/directory.bsi",
  ADVENT: "examples/ADVENT.BSI",
  SELINT: "tests/conformance/statements/select-integers.bsi",
  SELSIGN: "tests/conformance/statements/select-signed-range.bsi",
  SEL32: "tests/conformance/statements/select-32-bit.bsi",
  SELWORD: "tests/conformance/statements/select-whole-word-range.bsi",
  DUMP: "examples/DUMP.BSI",
  INFERCON: "tests/conformance/declarations/inference.bsi",
  TCARITH: "tests/conformance/declarations/typed-constant-arithmetic.bsi",
  TCONSTS: "tests/conformance/declarations/typed-constants.bsi",
  EXSHNOT: "tests/conformance/expressions/exact-shifts-and-not.bsi",
  FOVTRAP: "tests/conformance/expressions/float-overflow-traps.bsi",
  FTRUNC: "tests/conformance/expressions/float-truncates.bsi",
  MIXWIDE: "tests/conformance/expressions/mixed-widening.bsi",
  MOSTNEG: "tests/conformance/expressions/most-negative-divided.bsi",
  MULTIPLY: "tests/conformance/expressions/multiply.bsi",
  SHIFTMUL: "tests/conformance/expressions/shift-binds-like-multiply.bsi",
  SHIFTSC: "tests/conformance/expressions/shifts.bsi",
  SIGNDIV: "tests/conformance/expressions/signed-division.bsi",
  WIDEARIT: "tests/conformance/expressions/wide-arithmetic.bsi",
  WRAPPING: "tests/conformance/expressions/wrapping.bsi",
  FLITS: "tests/conformance/lexical/float-literals.bsi",
  IDCONTXT: "tests/conformance/lexical/id-is-contextual.bsi",
  WIDELITS: "tests/conformance/lexical/wide-literals.bsi",
  FMTHEX: "tests/conformance/library/format-hex.bsi",
  PARSEF32: "tests/conformance/library/parse-f32.bsi",
  RANDOMS: "tests/conformance/library/random-numbers.bsi",
  STRROUT: "tests/conformance/library/string-routines.bsi",
  TXTFILES: "tests/conformance/library/text-files.bsi",
  DEEPREC: "tests/conformance/scopes/deep-recursion-runs.bsi",
  BADNAME: "tests/conformance/services/bad-name.bsi",
  BINSEEK: "tests/conformance/services/binary-seek.bsi",
  READBYTE: "tests/conformance/services/console-read-byte.bsi",
  MACHINE: "tests/conformance/services/machine.bsi",
  OPENMISS: "tests/conformance/services/open-missing.bsi",
  PRINTER: "tests/conformance/services/printer.bsi",
  TEXTCOPY: "tests/conformance/services/text-copy.bsi",
  TOOMANY: "tests/conformance/services/too-many-files.bsi",
  HANDROPS: "tests/conformance/statements/handle-drops-temporaries.bsi",
  HANDCODE: "tests/conformance/statements/handle-stores-code.bsi",
  LOCAGGR: "tests/conformance/statements/local-aggregate.bsi",
  LOOP32: "tests/conformance/statements/loop-32-bit.bsi",
  LOOPBND: "tests/conformance/statements/loop-boundaries.bsi",
  OPENPARM: "tests/conformance/statements/open-array-param.bsi",
  SLOOPDN: "tests/conformance/statements/signed-loop-down.bsi",
  VARWRITE: "tests/conformance/statements/var-parameter-writes.bsi",
  CHAREXCT: "tests/conformance/types/character-literals-are-exact.bsi",
  WIDENING: "tests/conformance/types/widening.bsi",
  INTZERO: "tests/conformance/types/integer-zero-to-f32.bsi",
  FREEREUS: "tests/conformance/storage/freeing-reuses-slots.bsi",
  POOLFULL: "tests/conformance/storage/pool-full-traps.bsi",
  SIBOWNER: "tests/conformance/storage/sibling-owners.bsi",
  NEWSEL: "tests/conformance/storage/new-and-select.bsi",
  NEWFULL: "tests/conformance/storage/new-optional-when-full.bsi",
  NEWTRAIL: "tests/conformance/storage/new-trailing-fields.bsi",
  MOVELEAV: "tests/conformance/storage/move-leaves-none.bsi",
  MOVENONE: "tests/conformance/storage/move-none.bsi",
  SELMOVEC: "tests/conformance/storage/select-move.bsi",
  OWNDEST: "tests/conformance/storage/owning-destination-order.bsi",
  ELSEFREE: "tests/conformance/storage/else-fail-frees-owners.bsi",
  STALEHAN: "tests/conformance/storage/stale-handle-traps.bsi",
  STALEIDE: "tests/conformance/storage/stale-identifier-selects-none.bsi",
  OWNCYCLE: "tests/conformance/storage/ownership-cycle-traps.bsi",
  SLOTHOLD: "tests/conformance/storage/slot-holder.bsi",
  SELSLOT: "tests/conformance/storage/select-slot-holder.bsi",
  LEASE: "tests/conformance/storage/lease.bsi",
  LEASECYC: "tests/conformance/storage/lease-link-cycle-traps.bsi",
  REBIND: "tests/conformance/storage/rebind-links.bsi",
  IDNEST: "tests/conformance/storage/id-of-nested-at-start.bsi",
  IDNESTL: "tests/conformance/storage/id-of-nested-lease.bsi",
  DLINKED: "tests/conformance/storage/doubly-linked.bsi",
  FREEREU2: "tests/conformance/storage/free-several-then-reuse.bsi",
  LRUCACHE: "tests/conformance/storage/lru-cache.bsi",
  IDFCOPY: "tests/conformance/storage/identifier-field-passed-as-copy.bsi",
  BOOLXOR: "tests/conformance/expressions/boolean-xor.bsi",
  IDFEQ: "tests/conformance/expressions/identifier-and-file-equality.bsi",
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
  "67e: var parameters, open arrays, from clauses and assert": [
    "VARPARM",
    "OPENARR",
    "ASSERTS",
    "RUNVAR",
    "FROMCL",
    "FARFIELD",
    "ASSERTT",
    "TXTCON",
    "TRUNCREF",
    "DIRECTRY",
  ],
  "67e: aggregate constants in routines' bodies": ["LCONSTS"],
  "67c: branch shrinking": ["SHRINK", "ADVENT"],
  "67d: select on integers": [
    "SELECTS",
    "RUNSEL",
    "SELINT",
    "SELSIGN",
    "SEL32",
    "SELWORD",
  ],
  "67f: f32, and the programs of the library inside the subset": [
    "FLOATS",
    "FCODE",
    "RUNF32",
    "DUMP",
    "INFERCON",
    "TCARITH",
    "TCONSTS",
    "EXSHNOT",
    "FOVTRAP",
    "FTRUNC",
    "MIXWIDE",
    "MOSTNEG",
    "MULTIPLY",
    "SHIFTMUL",
    "SHIFTSC",
    "SIGNDIV",
    "WIDEARIT",
    "WRAPPING",
    "FLITS",
    "IDCONTXT",
    "WIDELITS",
    "FMTHEX",
    "PARSEF32",
    "RANDOMS",
    "STRROUT",
    "TXTFILES",
    "DEEPREC",
    "BADNAME",
    "BINSEEK",
    "READBYTE",
    "MACHINE",
    "OPENMISS",
    "PRINTER",
    "TEXTCOPY",
    "TOOMANY",
    "HANDROPS",
    "HANDCODE",
    "LOCAGGR",
    "LOOP32",
    "LOOPBND",
    "OPENPARM",
    "SLOOPDN",
    "VARWRITE",
    "CHAREXCT",
    "WIDENING",
    "INTZERO",
    "FEXPS",
    "FZEROS",
  ],
  "67g: pools and handle types": [
    "POOLDECL",
    "POOLDSC",
    "POOLPRV",
    "POOLNEST",
    "POOLF32",
    "NEWFREE",
    "FREEREUS",
    "POOLFULL",
    "SIBOWNER",
    "HANDSEL",
    "HANDPATH",
    "NEWSEL",
    "NEWFULL",
    "NEWTRAIL",
    "HANDARG",
    "CONDTMP",
    "CONDTMPW",
    "LOCTMP",
    "LEASEIN",
    "MOVEARMS",
    "MOVELOOP",
    "MOVEOPT",
    "MOVEFLD",
    "SELMOVE",
    "MOVELEAV",
    "MOVENONE",
    "SELMOVEC",
    "HANDPARM",
    "OWNDEST",
    "HANDDISC",
    "ELSEFREE",
    "SELF32",
    "IDVALS",
    "STALEHAN",
    "STALEIDE",
    "OWNCYCLE",
    "IDVAR",
    "SLOTHOLD",
    "SELSLOT",
    "SLOTS",
    "SLOTRET",
    "SLOTIDX",
    "LEASE",
    "LEASECYC",
    "REBIND",
    "LEASPARM",
    "LEASFLD",
    "IDREC",
    "IDNEST",
    "IDNESTL",
    "MOVEXPR",
    "NEWEXPR",
    "IDPARM",
    "DLINKED",
    "FREEREU2",
    "LRUCACHE",
    "IDCOPY",
    "IDFCOPY",
    "IDCALL",
    "BXOR",
    "BOOLXOR",
    "IDEQ",
    "IDFEQ",
    "OWNLOC",
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
 * The reference's four streams for NAME, compiled with its jumps shrunk and
 * the stamp the native run on the disk chose.
 */
async function reference(name: string, disk: Map<string, Uint8Array>) {
  const result = await compile(`${name}.BSI`, {
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
// them, and (67e) with the aggregates var parameters, fixed or open: each
// compiles to the reference's streams, or both compilers refuse it, with the same
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
    // (67e) The aggregates are var parameters, then open views.
    [
      `${record}${consts}sub run(var r as rec, var arr as u8[4], ` +
      `var wds as u16[3], var s as string[5], var sarr as i8[2])\n${names}`,
      `sub main()\n${objects}run(r, arr, wds, s, sarr)\nend\n`,
    ],
    [
      `${record}${consts}sub run(var r as rec, var arr as u8[], ` +
      `var wds as u16[], var s as string[], var sarr as i8[])\n${names}`,
      `sub main()\n${objects}run(r, arr, wds, s, sarr)\nend\n`,
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
    // (67d) or in an arm of a select on a random subject, with labels
    // and ranges at random (overlaps and labels beyond the type are
    // refused alike).
    const label = () => {
      const low = pick(["0", "1", "7", "200", "255", "-5", "300", "tk", "'A'"]);
      return rnd(3) === 0
        ? `${low} to ${pick(["9", "255", "65535", "-1", "tw"])}`
        : low;
    };
    const select = () => {
      let arms = "";
      for (let n = 1 + rnd(3); n > 0; n -= 1) {
        arms += `case ${label()}${rnd(2) ? `, ${label()}` : ""}\n${local}${
          rnd(2) ? statement + "\n" : ""
        }`;
      }
      if (rnd(2)) arms += `case else\n${statement}\n`;
      const subject = pick([
        "a",
        "x",
        "p",
        "q",
        "l",
        "m",
        "r.n",
        "arr[b and 3]",
        "(a + b)",
        "u16(a) * 2",
        "tw",
        integer(1),
      ]);
      return `select ${subject}\n${arms}end`;
    };
    const shape = rnd(3);
    const body = i % 5 !== 4
      ? statement
      : shape === 0
      ? `if ${boolean(2)}\n${local}${statement}\nelseif ${
        boolean(1)
      }\n${local}else\n${local}end`
      : shape === 1
      ? `while ${boolean(2)}\n${local}${statement}\nend`
      : select();
    const source = new TextEncoder().encode(
      `${head}${body}\nend\n${tail}`,
    );
    const run = runCom(basie, {
      tail: "RANDOM [C]",
      files: { "RANDOM.BSI": source, "CPM22.BRL": LIBRARY, "BASIE.OVL": OVL },
      maxSteps: 50_000_000,
    });
    const ref = await compile("RANDOM.BSI", {
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

// (67f) Random f32 statements: assignments of f32 expressions mixing
// literals, variables, constants, fields, elements, integers and
// conversions both ways; comparisons; a routine taking and returning an
// f32; inferred locals; f32 where only an integer will do (loop counters,
// bounds and steps, select subjects, shifts, `not`, `mod`); constant
// divisions by zero and folds past the largest f32. Each compiles to the
// reference's streams or both compilers refuse it alike.
Deno.test("67f: random f32 statements compile as the reference compiles them", async () => {
  let seed = 2654435761;
  const rnd = (n: number) => {
    seed ^= seed << 13;
    seed >>>= 0;
    seed ^= seed >>> 17;
    seed ^= seed << 5;
    seed >>>= 0;
    return Math.floor((seed / 4294967296) * n);
  };
  const pick = <T>(a: T[]) => a[rnd(a.length)];
  const literals = [
    "0.0",
    "1.0",
    "0.5",
    "2.5",
    "1e10",
    "3.4028234e38",
    "1.17549435e-38",
    "0.1",
    "100.0",
    "16777216.0",
    "3.0e-5",
    "7.25",
    "1e-40",
    "65535.0",
    "4294967296.0",
    "1.5e3",
  ];
  const ints = [
    "0",
    "1",
    "7",
    "300",
    "65535",
    "16777217",
    "-5",
    "4294967295",
    "k",
    "tk",
    "tw",
    "a",
    "x",
    "q",
    "l",
  ];
  const constants = [...literals, "cf", "cg", "k", "tk", "tw", "-5", "7"];
  const known = ["7", "k", "tw", "300", "tk"];
  const leaf = () =>
    pick([...literals, "f", "g", "h", "cf", "cg", "fa[1]", "fa[a and 3]"]);
  const float = (d: number, only = false): string => {
    if (d <= 0 || rnd(3) === 0) {
      if (only) return pick(constants);
      return rnd(4) === 0 ? pick(ints) : leaf();
    }
    const r = rnd(14);
    if (r === 0) {
      return `f32(${rnd(2) ? float(d - 1, only) : integer(d - 1, only)})`;
    }
    if (r === 1) return `(${float(d - 1, only)})`;
    if (r === 2) return `-${float(d - 1, only)}`;
    if (r === 3) {
      return `${float(d - 1, only)} ${pick(["mod", "shl"])} ${
        pick(only ? known : ints)
      }`;
    }
    if (r === 4) return `not ${float(d - 1, only)}`;
    const op = pick(["+", "-", "*", "/", "+", "*"]);
    return `${float(d - 1, only)} ${op} ${
      rnd(4) ? float(d - 1, only) : integer(d - 1, only)
    }`;
  };
  const integer = (d: number, only = false): string => {
    if (d <= 0 || rnd(2) === 0) return pick(only ? known : ints);
    if (rnd(4) === 0) {
      return `${pick(["u8", "i8", "u16", "i16", "u32", "i32"])}(${
        float(d - 1, only)
      })`;
    }
    const from = only ? known : ints;
    return `${pick(from)} ${pick(["+", "*", "-"])} ${pick(from)}`;
  };
  const compare = (d: number) =>
    `${float(d)} ${pick(["=", "<>", "<", "<=", ">", ">="])} ${float(d)}`;
  const head = "record rec\nm as u8\nv as f32\nend\n" +
    "const k = 12\nconst tk as u8 = 99\nconst tw as u16 = 4000\n" +
    "const cf as f32 = 1.5\nconst cg as f32 = -1e-3\n" +
    "var r as rec\nvar fa as f32[4]\nvar t as boolean\n" +
    "sub half(p as f32, i as i16) as f32\nreturn p / 2.0 + i\nend\n";
  const locals = "var a as u8 = 200\nvar x as u16 = 1000\n" +
    "var q as i16 = -300\nvar l as u32 = 100000\nvar f as f32 = 1.25\n" +
    "var g as f32 = -3.5\nvar h as f32\nvar n as i32\nvar u as u8\n";
  for (let i = 0; i < 300; i++) {
    const target = pick(["f", "g", "h", "fa[2]", "r.v", "fa[a and 3]"]);
    const kind = rnd(5);
    const plain = kind === 0
      ? `t = ${compare(2)}`
      : kind === 1
      ? `${pick(["n", "u", "a", "x", "l", "q"])} = ${integer(3)}`
      : kind === 2
      ? `const z as f32 = ${float(3, true)}\n${target} = z`
      : `${target} = ${float(3)}`;
    const special = [
      `var v = ${float(2)}\nf = v`,
      `f = half(${float(2)}, ${pick(ints)})`,
      `for n = 1 to ${float(1)}\nend`,
      "for h = 1 to 3\nend",
      `for q = 1 to 9 step ${pick(["1.5", "cf", "2", "k"])}\nend`,
      `select ${float(1)}\ncase 1\nend`,
      `l = u32(${float(2)}) + l`,
      `n = i32(${float(2)}) * 2`,
      "f = f32(l) + f32(n)",
      `f = ${pick(ints)} / ${pick(["0.0", "-0.0", "0", "f"])}`,
      `f = ${pick(["3.4e38", "1e38", "f"])} * ${pick(["10.0", "2", "f"])}`,
      `assert ${compare(1)}`,
      `while ${compare(1)}\nf = f + 1\nend`,
      `x = ${pick(["u16", "u8"])}(${float(2)}) shr 1`,
    ];
    const statement = rnd(3) === 0 ? pick(special) : plain;
    const body = rnd(3) === 0
      ? `if ${compare(1)}\n${statement}\nend`
      : statement;
    const source = new TextEncoder().encode(
      `${head}sub main()\n${locals}${body}\nend\n`,
    );
    const run = runCom(basie, {
      tail: "RANDOM [C]",
      files: { "RANDOM.BSI": source, "CPM22.BRL": LIBRARY, "BASIE.OVL": OVL },
      maxSteps: 50_000_000,
    });
    const ref = await compile("RANDOM.BSI", {
      mainSource: source,
      stamp: run.disk.has("RANDOM.$DR") ? stampOf(run.disk, "RANDOM") : 1,
    });
    if (!ref.ok) {
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
    ...CLAIMED["67e: var parameters, open arrays, from clauses and assert"],
    ...CLAIMED["67e: aggregate constants in routines' bodies"],
    ...CLAIMED["67c: branch shrinking"],
    ...CLAIMED["67d: select on integers"],
    ...CLAIMED["67f: f32, and the programs of the library inside the subset"],
    ...CLAIMED["67g: pools and handle types"],
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
        "RUNVAR",
        "RUNF32",
      ].includes(name)
    ) {
      assertEquals(/^TRAP narrowing/.test(expected), true);
    }
    if (name === "ASSERTT") {
      assertEquals(/^TRAP assertion/.test(expected), true);
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
  "an f32 loop counter": "sub main()\nvar f as f32\nfor f = 1 to 3\nend\nend\n",
  "an f32 select subject":
    "sub main()\nvar f as f32 = 1.5\nselect f\ncase 1\nend\nend\n",
  "an f32 literal step":
    "sub main()\nvar n as u8\nfor n = 1 to 9 step 1.5\nend\nend\n",
  "an f32 constant step":
    "const s as f32 = 2.0\nsub main()\nvar n as u8\nfor n = 1 to 9 step s\nend\nend\n",
  "an f32 bound for an integer counter":
    "sub main()\nvar n as u8\nfor n = 1 to 2.5\nend\nend\n",
  "mod on f32 values": "sub main()\nvar f as f32 = 7.5\nf = f mod 2.0\nend\n",
  "mod on a known f32": "var f as f32 = 7.5 mod 2.0\nsub main()\nend\n",
  "mod of an f32 by a known zero":
    "sub main()\nvar f as f32 = 7.5\nf = f mod 0.0\nend\n",
  "an untyped f32 constant": "const c = 1.5\nsub main()\nend\n",
  "a known f32 for an integer": "var x as u8 = 1.5\nsub main()\nend\n",
  "a computed f32 for an integer":
    "sub main()\nvar f as f32 = 1.5\nvar x as u16 = f\nend\n",
  "an integer not exactly an f32": "var f as f32 = 16777217\nsub main()\nend\n",
  "an integer operand not exactly an f32":
    "sub main()\nvar f as f32 = 1.5\nf = f + 16777217\nend\n",
  "an f32 literal past the largest": "var f as f32 = 1e39\nsub main()\nend\n",
  "an f32 literal's exponent without digits":
    "var f as f32 = 1.5e+\nsub main()\nend\n",
  "an f32 literal run into a name": "var f as f32 = 1.5f\nsub main()\nend\n",
  "an f32 fold past the largest":
    "const c as f32 = 3e38 * 10.0\nsub main()\nend\n",
  "an f32 constant divided by zero":
    "const c as f32 = 1.0 / 0.0\nsub main()\nend\n",
  "an f32 divided by a known minus zero":
    "sub main()\nvar f as f32 = 1.5\nf = f / -0.0\nend\n",
  "not on an f32": "sub main()\nvar f as f32 = 1.5\nf = not f\nend\n",
  "an f32 shifted": "sub main()\nvar f as f32 = 1.5\nf = f shl 1\nend\n",
  "an f32 count":
    "sub main()\nvar n as u16 = 1\nvar f as f32 = 1.5\nn = n shl f\nend\n",
  "an f32 and an i32 mixed":
    "sub main()\nvar f as f32 = 1.5\nvar n as i32 = 2\nf = f + n\nend\n",
  "an f32 conversion that does not fit":
    "var x as u8 = u8(256.5)\nsub main()\nend\n",
  "an f32 conversion of 2^32":
    "var x as u32 = u32(4294967296.0)\nsub main()\nend\n",
  "an f32 to a Boolean": "sub main()\nvar g as boolean = f32(1)\nend\n",
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
  "var on a u8 parameter": "sub f(var n as u8)\nend\nsub main()\nend\n",
  "var on a File parameter": "sub f(var n as File)\nend\nsub main()\nend\n",
  "a from clause naming no parameter":
    "sub f(a as u8[4]) as u8 from b\nreturn 1\nend\nsub main()\nend\n",
  "a from clause naming a scalar parameter":
    "sub f(a as u8) as u8 from a\nreturn 1\nend\nsub main()\nend\n",
  "a from clause without a name":
    "sub f() as u8 from\nreturn 1\nend\nsub main()\nend\n",
  "a name in place of from":
    "sub f() as u8 fromx a\nreturn 1\nend\nsub main()\nend\n",
  "a result rooted in a parameter outside from":
    "record R\na as u8\nend\nsub f(a as R, b as R) as R from a\nreturn b\nend\nsub main()\nend\n",
  "a constant passed to a var parameter":
    "record R\na as u8\nend\nconst k as R = (1)\nsub h(var r as R)\nend\nsub main()\nh(k)\nend\n",
  "a read-only parameter passed to a var parameter":
    "record R\na as u8\nend\nsub h(var r as R)\nend\nsub g(r as R)\nh(r)\nend\nsub main()\nend\n",
  "a read-only call result passed to a var parameter":
    "record R\na as u8\nend\nvar v as R\nsub f() as R\nreturn v\nend\nsub h(var r as R)\nend\nsub main()\nh(f())\nend\n",
  "an open string assigned whole":
    'sub h(var s as string[])\ns = "abc"\nend\nsub main()\nend\n',
  "an open array assigned whole":
    "sub h(var a as u8[], b as u8[])\na = b\nend\nsub main()\nend\n",
  "a literal passed to a user's var string[]":
    'sub h(var s as string[])\nend\nsub main()\nh("abc")\nend\n',
  "a literal passed to an open array":
    'sub h(a as u8[])\nend\nsub main()\nh("abc")\nend\n',
  "an open dimension inside": "sub h(a as u8[3][])\nend\nsub main()\nend\n",
  "two open dimensions": "sub h(a as u8[][])\nend\nsub main()\nend\n",
  "a u8 array passed as a u16[]":
    "sub h(a as u16[])\nend\nsub main()\nvar b as u8[4]\nh(b)\nend\n",
  "a fixed string's length assigned":
    "sub h(var s as string[10])\ns.length = 2\nend\nsub main()\nend\n",
  "a read-only open string's length assigned":
    "sub h(s as string[])\ns.length = 2\nend\nsub main()\nend\n",
  "an open array's length assigned":
    "sub h(var a as u8[])\na.length = 2\nend\nsub main()\nend\n",
  "an open array's field other than length":
    "sub h(a as u8[])\nvar n as u16 = a.size\nend\nsub main()\nend\n",
  "an open array local": "sub main()\nvar a as u8[]\nend\n",
  "an open array program variable": "var a as u8[]\nsub main()\nend\n",
  "an open array field": "record R\na as u8[]\nend\nsub main()\nend\n",
  "an open array result": "sub f() as u8[]\nend\nsub main()\nend\n",
  "an open array local inferred":
    "sub h(a as u8[])\nvar b = a\nend\nsub main()\nend\n",
  "a certainly false assert": "sub main()\nassert false\nend\n",
  "an assert of a number": "sub main()\nassert 5\nend\n",
  "an assert of a u8": "var x as u8\nsub main()\nassert x\nend\n",
  "a failable call in an assert":
    "sub f() as boolean fails\nreturn true\nend\nsub main()\nassert f()\nend\n",
  "an assert with more after it":
    "var x as u8\nsub main()\nassert x = 3 x\nend\n",
  "an assert of nothing": "sub main()\nassert\nend\n",
  "a routine's aggregate constant written":
    "sub main()\nconst k as u8[2] = [1, 2]\nk[0] = 3\nend\n",
  "a block's aggregate constant used after the block":
    "sub main()\nif true\nconst k as u8[2] = [1, 2]\nend\nvar c as u8 = k[0]\nend\n",
  "a routine's aggregate constant of an open type":
    "sub main()\nconst k as u8[] = [1, 2]\nend\n",
  "a select subject that goes on past a variable":
    "var x as u8\nsub main()\nselect x + 1\ncase 1\nend\nend\n",
  "an exact select subject": "sub main()\nselect 5\ncase 1\nend\nend\n",
  "a character as a select subject":
    "sub main()\nselect 'a'\ncase 1\nend\nend\n",
  "a Boolean select subject":
    "var b as boolean\nsub main()\nselect b\ncase 1\nend\nend\n",
  "a record as a select subject":
    "record r\na as u8\nend\nvar v as r\nsub main()\nselect v\ncase 1\nend\nend\n",
  "a string literal as a select subject":
    'sub main()\nselect "a"\ncase 1\nend\nend\n',
  "a File as a select subject":
    "sub main()\nselect console\ncase 1\nend\nend\n",
  "select move on an integer":
    "var x as u8\nsub main()\nselect move x\ncase 1\nend\nend\n",
  "a select with only case else":
    "var x as u8\nsub main()\nselect x\ncase else\nend\nend\n",
  "a case after case else":
    "var x as u8\nsub main()\nselect x\ncase 1\ncase else\ncase 2\nend\nend\n",
  "labels that overlap in one arm":
    "var x as u8\nsub main()\nselect x\ncase 1, 1\nend\nend\n",
  "signed labels that overlap":
    "sub main()\nvar i as i8\nselect i\ncase -5 to 5\ncase -1\nend\nend\n",
  "a reversed range":
    "var x as u8\nsub main()\nselect x\ncase 5 to 1\nend\nend\n",
  "a label beyond the subject's type":
    "var x as u8\nsub main()\nselect x\ncase 300\nend\nend\n",
  "a negative label for a u8":
    "var x as u8\nsub main()\nselect x\ncase -1\nend\nend\n",
  "a label that is no constant":
    "var x as u8\nvar y as u8\nsub main()\nselect x\ncase y\nend\nend\n",
  "a u16 constant labelling a u8":
    "var x as u8\nconst big as u16 = 3\nsub main()\nselect x\ncase big\nend\nend\n",
  "a Boolean label": "var x as u8\nsub main()\nselect x\ncase true\nend\nend\n",
  "some on an integer":
    "var x as u8\nsub main()\nselect x\ncase some(x)\nend\nend\n",
  "none on an integer":
    "var x as u8\nsub main()\nselect x\ncase none\nend\nend\n",
  "a statement before the first case":
    "var x as u8\nsub main()\nselect x\nx = 1\ncase 1\nend\nend\n",
  "a failable select subject":
    "sub f() as u8 fails\nreturn 1\nend\nsub main() fails\nselect f()\ncase 1\nend\nend\n",
  "else fail after a select subject":
    "sub f() as u8 fails\nreturn 1\nend\nsub main() fails\nselect f() else fail\ncase 1\nend\nend\n",
  "exit in a select outside a loop":
    "var x as u8\nsub main()\nselect x\ncase 1\nexit\nend\nend\n",
  "a value routine whose select has no case else":
    "sub g(n as u8) as u8\nselect n\ncase 1\nreturn 1\nend\nend\nsub main()\nend\n",
  "move as a name": "sub main()\nvar move as u8\nend\n",
  "overlapping select labels": Deno.readTextFileSync(
    "tests/conformance/statements/select-overlap.bsi",
  ),
  "pool of a scalar": "pool p as u8[4]\nsub main()\nend\n",
  "pool of an undeclared": "pool p as Nope[4]\nsub main()\nend\n",
  "pool of zero slots":
    "record R\nv as u8\nend\npool p as R[0]\nsub main()\nend\n",
  "pool too large":
    "record R\nv as u8[200]\nend\npool p as R[400]\nsub main()\nend\n",
  "pool named twice":
    "record R\nv as u8\nend\npool p as R[2]\npool p as R[2]\nsub main()\nend\n",
  "forward pool never completed": "forward pool p\nsub main()\nend\n",
  "forward pool completed private":
    "record R\nv as u8\nend\nforward pool p\nprivate pool p as R[2]\nsub main()\nend\n",
  "non-optional handle field":
    "forward pool p\nrecord R\nh as p\nend\npool p as R[2]\nsub main()\nend\n",
  "non-optional handle variable":
    "record R\nv as u8\nend\npool p as R[2]\nvar h as p\nsub main()\nend\n",
  "optional record type":
    "record R\nv as u8\nend\nvar r as R?\nsub main()\nend\n",
  "id of a record": "record R\nv as u8\nend\nvar r as id R\nsub main()\nend\n",
  "capacity not constant":
    "record R\nv as u8\nend\nvar n as u16 = 3\npool p as R[n]\nsub main()\nend\n",
  "an initializer on a handle variable":
    "record R\nv as u8\nend\npool p as R[2]\nvar g as p? = 0\nsub main()\nend\n",
  "an initializer on an id variable":
    "record R\nv as u8\nend\npool p as R[2]\nvar g as id p? = 0\nsub main()\nend\n",
  "an initializer on an owning record variable":
    "forward pool p\nrecord R\nh as p?\nk as u8\nend\npool p as R[2]\nvar s as R = (none, 1)\nsub main()\nend\n",
  "a handle field repeating a name":
    "forward pool p\nrecord R\nh as u8\nh as p\nend\npool p as R[2]\nsub main()\nend\n",
  "a field repeating a name, its type unknown":
    "record R\nh as u8\nh as Nope\nend\nsub main()\nend\n",
  "a forward pool with more on its line":
    "var p as u8\nforward pool p x\nsub main()\nend\n",
  "two forward pools never completed":
    "forward pool a\nforward pool b\nsub main()\nend\n",
  "a public and a private forward pool never completed":
    "forward pool a\nprivate forward pool b\nsub main()\nend\n",
  "an owner descriptor of more than 255 entries":
    "forward pool p\nrecord R\nh as p?[256][1]\nend\npool p as R[1]\nsub main()\nend\n",
  "a pool as a value":
    "record R\nv as u8\nend\npool p as R[2]\nvar k as u8\nsub main()\nk = p\nend\n",
  "a pool assigned":
    "record R\nv as u8\nend\npool p as R[2]\nsub main()\np = 1\nend\n",
  "a pool called":
    "record R\nv as u8\nend\npool p as R[2]\nsub main()\np()\nend\n",
  "a pool as a bound":
    "record R\nv as u8\nend\npool p as R[2]\nvar a as u8[p]\nsub main()\nend\n",
  "a record type as a value":
    "record R\nv as u8\nend\nvar k as u8\nsub main()\nk = R\nend\n",
  "a record type assigned": "record R\nv as u8\nend\nsub main()\nR = 1\nend\n",
  "a non-optional handle local without an initializer":
    "forward pool nodes\nrecord Node\n    value as u8\n    next as nodes?\nend\npool nodes as Node[4]\nsub main()\n    var a as nodes\nend\n",
  "new of a forward pool":
    "forward pool p\nrecord R\n    h as p?\nend\nsub main()\n    var a = new p(none)\nend\npool p as R[2]\n",
  "new of a record":
    "forward pool nodes\nrecord Node\n    value as u8\n    next as nodes?\nend\npool nodes as Node[4]\nsub main()\n    var a = new Node(1)\nend\n",
  "new of an undeclared name":
    "forward pool nodes\nrecord Node\n    value as u8\n    next as nodes?\nend\npool nodes as Node[4]\nsub main()\n    var a = new nope(1)\nend\n",
  "new with too many fields":
    "forward pool nodes\nrecord Node\n    value as u8\n    next as nodes?\nend\npool nodes as Node[4]\nsub main()\n    var a = new nodes(1, none, 3)\nend\n",
  "new? for a non-optional local":
    "forward pool nodes\nrecord Node\n    value as u8\n    next as nodes?\nend\npool nodes as Node[4]\nsub main()\n    var a as nodes = new? nodes(1)\nend\n",
  "none for a non-optional local":
    "forward pool nodes\nrecord Node\n    value as u8\n    next as nodes?\nend\npool nodes as Node[4]\nsub main()\n    var a as nodes = none\nend\n",
  "none inferred":
    "forward pool nodes\nrecord Node\n    value as u8\n    next as nodes?\nend\npool nodes as Node[4]\nsub main()\n    var a = none\nend\n",
  "new of another pool":
    "forward pool nodes\nrecord Node\n    value as u8\n    next as nodes?\nend\npool nodes as Node[4]\nrecord Leaf\n    v as u8\nend\npool leaves as Leaf[2]\nsub main()\n    var a as nodes? = new leaves(1)\nend\n",
  "a field value of the wrong type":
    "forward pool nodes\nrecord Node\n    value as u8\n    next as nodes?\nend\npool nodes as Node[4]\nsub main()\n    var a = new nodes(300)\nend\n",
  "new without parentheses":
    "forward pool nodes\nrecord Node\n    value as u8\n    next as nodes?\nend\npool nodes as Node[4]\nsub main()\n    var a = new nodes\nend\n",
  "new without a name":
    "forward pool nodes\nrecord Node\n    value as u8\n    next as nodes?\nend\npool nodes as Node[4]\nsub main()\n    var a = new (1)\nend\n",
  "none assigned to a non-optional owner":
    "forward pool nodes\nrecord Node\n    value as u8\n    next as nodes?\nend\npool nodes as Node[4]\nrecord Leaf\n    v as u8\nend\npool leaves as Leaf[2]\nvar head as nodes?\nsub main()\n    var a = new nodes(1, none)\n    a = none\nend\n",
  "new? assigned to a non-optional owner":
    "forward pool nodes\nrecord Node\n    value as u8\n    next as nodes?\nend\npool nodes as Node[4]\nrecord Leaf\n    v as u8\nend\npool leaves as Leaf[2]\nvar head as nodes?\nsub main()\n    var a = new nodes(1, none)\n    a = new? nodes(2, none)\nend\n",
  "another pool's handle assigned to a program variable":
    "forward pool nodes\nrecord Node\n    value as u8\n    next as nodes?\nend\npool nodes as Node[4]\nrecord Leaf\n    v as u8\nend\npool leaves as Leaf[2]\nvar head as nodes?\nsub main()\n    head = new leaves(1)\nend\n",
  "another pool's handle assigned to a field":
    "forward pool nodes\nrecord Node\n    value as u8\n    next as nodes?\nend\npool nodes as Node[4]\nrecord Leaf\n    v as u8\nend\npool leaves as Leaf[2]\nvar head as nodes?\nvar gw as Node\nsub main()\n    gw.next = new leaves(1)\nend\n",
  "another pool's handle as a field of new":
    "forward pool nodes\nrecord Node\n    value as u8\n    next as nodes?\nend\npool nodes as Node[4]\nrecord Leaf\n    v as u8\nend\npool leaves as Leaf[2]\nvar head as nodes?\nsub main()\n    var a = new nodes(1, new leaves(2))\nend\n",
  "a missing field after a comma in new":
    "forward pool nodes\nrecord Node\n    value as u8\n    next as nodes?\nend\npool nodes as Node[4]\nrecord Leaf\n    v as u8\nend\npool leaves as Leaf[2]\nvar head as nodes?\nsub main()\n    var a = new nodes()\n    var b = new nodes(1,)\nend\n",
  "a record of the wrong type as a field of new":
    "forward pool nodes\nrecord Node\n    value as u8\n    next as nodes?\nend\npool nodes as Node[4]\nrecord Leaf\n    v as u8\nend\npool leaves as Leaf[2]\nvar head as nodes?\nrecord R\n    a as Leaf\nend\npool rs as R[2]\nvar gn as Node\nsub main()\n    var a = new rs(gn)\nend\n",
  "a second some arm":
    "forward pool nodes\nrecord Node\n    value as u8\n    next as nodes?\nend\npool nodes as Node[4]\nvar g as u8\nsub main()\n    var a as nodes? = new nodes(1, none)\n    select a\n    case some(x)\n    case some(y)\n    end\nend\n",
  "a second none arm":
    "forward pool nodes\nrecord Node\n    value as u8\n    next as nodes?\nend\npool nodes as Node[4]\nvar g as u8\nsub main()\n    var a as nodes? = new nodes(1, none)\n    select a\n    case some(x)\n    case none\n    case none\n    end\nend\n",
  "none and case else":
    "forward pool nodes\nrecord Node\n    value as u8\n    next as nodes?\nend\npool nodes as Node[4]\nvar g as u8\nsub main()\n    var a as nodes? = new nodes(1, none)\n    select a\n    case some(x)\n    case none\n    case else\n    end\nend\n",
  "a handle select without some":
    "forward pool nodes\nrecord Node\n    value as u8\n    next as nodes?\nend\npool nodes as Node[4]\nvar g as u8\nsub main()\n    var a as nodes? = new nodes(1, none)\n    select a\n    case none\n    end\nend\n",
  "a non-optional owner selected":
    "forward pool nodes\nrecord Node\n    value as u8\n    next as nodes?\nend\npool nodes as Node[4]\nvar g as u8\nsub main()\n    var a = new nodes(1, none)\n    select a\n    case some(x)\n    end\nend\n",
  "a field of an optional handle":
    "forward pool nodes\nrecord Node\n    value as u8\n    next as nodes?\nend\npool nodes as Node[4]\nvar g as u8\nsub main()\n    var a as nodes? = new nodes(1, none)\n    g = a.value\nend\n",
  "a number labelling a handle arm":
    "forward pool nodes\nrecord Node\n    value as u8\n    next as nodes?\nend\npool nodes as Node[4]\nvar g as u8\nsub main()\n    var a as nodes? = new nodes(1, none)\n    select a\n    case 1\n    end\nend\n",
  "some without parentheses":
    "forward pool nodes\nrecord Node\n    value as u8\n    next as nodes?\nend\npool nodes as Node[4]\nvar g as u8\nsub main()\n    var a as nodes? = new nodes(1, none)\n    select a\n    case some x\n    end\nend\n",
  "a lease's name repeated in its arm":
    "forward pool nodes\nrecord Node\n    value as u8\n    next as nodes?\nend\npool nodes as Node[4]\nvar g as u8\nsub main()\n    var a as nodes? = new nodes(1, none)\n    select a\n    case some(x)\n        var x as u8\n    end\nend\n",
  "a lease's field of the wrong type":
    "forward pool nodes\nrecord Node\n    value as u8\n    next as nodes?\nend\npool nodes as Node[4]\nvar g as u8\nsub main()\n    var a as nodes? = new nodes(1, none)\n    select a\n    case some(x)\n        x.value = 300\n    end\nend\n",
  "case else before some":
    "forward pool nodes\nrecord Node\n    value as u8\n    next as nodes?\nend\npool nodes as Node[4]\nvar g as u8\nsub main()\n    var a as nodes? = new nodes(1, none)\n    select a\n    case else\n    case some(x)\n    end\nend\n",
  "an element through a handle":
    "forward pool nodes\nrecord Node\n    value as u8\n    next as nodes?\nend\npool nodes as Node[4]\nvar g as u8\nsub main()\n    var a = new nodes(1, none)\n    g = a[1]\nend\n",
  "a lease's subject assigned in its arm":
    "forward pool nodes\nrecord Node\n    value as u8\n    next as nodes?\nend\npool nodes as Node[4]\nvar g as u8\nsub main()\n    var a as nodes? = new? nodes(1, none)\n    select a\n    case some(x)\n        a = new? nodes(2)\n    end\nend\n",
  "a lease's subject assigned none in its arm":
    "forward pool nodes\nrecord Node\n    value as u8\n    next as nodes?\nend\npool nodes as Node[4]\nvar g as u8\nsub main()\n    var a as nodes? = new? nodes(1, none)\n    select a\n    case some(x)\n        a = none\n    end\nend\n",
  "a lease's subject assigned in an if in its arm":
    "forward pool nodes\nrecord Node\n    value as u8\n    next as nodes?\nend\npool nodes as Node[4]\nvar g as u8\nsub main()\n    var a as nodes? = new? nodes(1)\n    select a\n    case some(x)\n        if g = 1\n            a = none\n        end\n    end\nend\n",
  "a lease's string length written":
    'forward pool nodes\nrecord Node\n    value as u8\n    next as nodes?\nend\npool nodes as Node[4]\nrecord Leaf\n    v as u8\n    s as string[3]\nend\npool leaves as Leaf[3]\nvar head as nodes?\nvar gl as Leaf\nvar gh as leaves?\nvar g as u8\nsub fv(r as Leaf)\nend\nsub fr(var r as Leaf)\nend\nsub main()\n    var a as nodes? = new? nodes(1, none)\n    var b as leaves? = new? leaves(1, "ab")\n    select b\n    case some(x)\n        x.s.length = 1\n    end\nend\n',
  "a lease indexed":
    'forward pool nodes\nrecord Node\n    value as u8\n    next as nodes?\nend\npool nodes as Node[4]\nrecord Leaf\n    v as u8\n    s as string[3]\nend\npool leaves as Leaf[3]\nvar head as nodes?\nvar gl as Leaf\nvar gh as leaves?\nvar g as u8\nsub fv(r as Leaf)\nend\nsub fr(var r as Leaf)\nend\nsub main()\n    var a as nodes? = new? nodes(1, none)\n    var b as leaves? = new? leaves(1, "ab")\n    select b\n    case some(x)\n        g = x[1]\n    end\nend\n',
  "a field through an identifier passed to a var parameter (M05)":
    "record Leaf\n    v as u8\n    s as string[3]\nend\nrecord Outer\n    w as u8\n    inn as Leaf\n    arr as Leaf[2]\nend\npool outers as Outer[3]\nvar go as outers?\nvar gl as Leaf\nvar g as u8\nsub fv(r as Leaf)\n    g = r.v\nend\nsub fr(var r as Leaf)\n    r.v = 1\nend\nsub fs(var s as string[])\nend\nsub fo(var o as Outer)\nend\nsub main()\n    select go\n    case some(x)\n        fs(x.inn.s)\n    end\nend\n",
  "a field through an identifier passed to a var parameter (T04)":
    "record Leaf\n    v as u8\n    s as string[3]\n    arr as u8[2]\nend\npool leaves as Leaf[3]\nvar g as u8\nvar gh as leaves?\nsub fs(var s as string[])\nend\nsub fa(a as u8[])\nend\nsub main()\n    select gh\n    case some(j)\n        fs(j.s)\n    end\nend\n",
  "use after move":
    "forward pool nodes\nrecord Node\n    value as u8\n    next as nodes?\nend\npool nodes as Node[8]\nvar head as nodes?\nvar g as u8\nvar c as boolean\nsub main()\n    var a = new nodes(1, none)\n    head = move a\n    g = a.value\nend\n",
  "use after a move in one arm":
    "forward pool nodes\nrecord Node\n    value as u8\n    next as nodes?\nend\npool nodes as Node[8]\nvar head as nodes?\nvar g as u8\nvar c as boolean\nsub main()\n    var a = new nodes(1, none)\n    if c\n        head = move a\n    end\n    g = a.value\nend\n",
  "loop moves an owner":
    "forward pool nodes\nrecord Node\n    value as u8\n    next as nodes?\nend\npool nodes as Node[8]\nvar head as nodes?\nvar g as u8\nvar c as boolean\nsub main()\n    var a = new nodes(1, none)\n    while c\n        head = move a\n    end\nend\n",
  "loop moves an owner, continue":
    "forward pool nodes\nrecord Node\n    value as u8\n    next as nodes?\nend\npool nodes as Node[8]\nvar head as nodes?\nvar g as u8\nvar c as boolean\nsub main()\n    var a = new nodes(1, none)\n    while c\n        head = move a\n        if c\n            continue\n        end\n        a = new nodes(2, none)\n    end\nend\n",
  "for moves an owner":
    "forward pool nodes\nrecord Node\n    value as u8\n    next as nodes?\nend\npool nodes as Node[8]\nvar head as nodes?\nvar g as u8\nvar c as boolean\nsub main()\n    var a = new nodes(1, none)\n    var i as u8\n    for i = 1 to 3\n        head = move a\n    end\nend\n",
  "exit after a move":
    "forward pool nodes\nrecord Node\n    value as u8\n    next as nodes?\nend\npool nodes as Node[8]\nvar head as nodes?\nvar g as u8\nvar c as boolean\nsub main()\n    var a = new nodes(1, none)\n    while c\n        head = move a\n        exit\n    end\n    g = a.value\nend\n",
  "statement rule: move and use":
    "forward pool nodes\nrecord Node\n    value as u8\n    next as nodes?\nend\npool nodes as Node[8]\nvar head as nodes?\nvar g as u8\nvar c as boolean\nsub main()\n    var a = new nodes(1, none)\n    a.next = move a\nend\n",
  "move of a non-owner":
    "forward pool nodes\nrecord Node\n    value as u8\n    next as nodes?\nend\npool nodes as Node[8]\nvar head as nodes?\nvar g as u8\nvar c as boolean\nsub main()\n    var a = new nodes(1, none)\n    g = 1\n    head = move g\nend\n",
  "move of a lease subject in its arm":
    "forward pool nodes\nrecord Node\n    value as u8\n    next as nodes?\nend\npool nodes as Node[8]\nvar head as nodes?\nvar g as u8\nvar c as boolean\nsub main()\n    var a as nodes? = new nodes(1, none)\n    select a\n    case some(x)\n        head = move a\n    end\nend\n",
  "select on a moved owner":
    "forward pool nodes\nrecord Node\n    value as u8\n    next as nodes?\nend\npool nodes as Node[8]\nvar head as nodes?\nvar g as u8\nvar c as boolean\nsub main()\n    var a = new nodes(1, none)\n    var b as nodes? = move a\n    select a\n    case some(x)\n    end\nend\n",
  "select move of a non-optional":
    "forward pool nodes\nrecord Node\n    value as u8\n    next as nodes?\nend\npool nodes as Node[8]\nvar head as nodes?\nvar g as u8\nvar c as boolean\nsub main()\n    var a = new nodes(1, none)\n    select move a\n    case some(x)\n    end\nend\n",
  "integer select arms merge moves":
    "forward pool nodes\nrecord Node\n    value as u8\n    next as nodes?\nend\npool nodes as Node[8]\nvar head as nodes?\nvar g as u8\nvar c as boolean\nsub main()\n    var a = new nodes(1, none)\n    select g\n    case 1\n        head = move a\n    case else\n        g = 2\n    end\n    g = a.value\nend\n",
  "inferred move":
    "forward pool nodes\nrecord Node\n    value as u8\n    next as nodes?\nend\npool nodes as Node[8]\nvar head as nodes?\nvar g as u8\nvar c as boolean\nsub main()\n    var a = new nodes(1, none)\n    var b = move a\n    g = b.value\n    g = a.value\nend\n",
  "move routine":
    "forward pool nodes\nrecord Node\n    value as u8\n    next as nodes?\nend\npool nodes as Node[8]\nvar head as nodes?\nvar g as u8\nvar c as boolean\nsub main()\n    head = move main\nend\n",
  "move const":
    "forward pool nodes\nrecord Node\n    value as u8\n    next as nodes?\nend\npool nodes as Node[8]\nvar head as nodes?\nvar g as u8\nvar c as boolean\nconst k = 5\nsub main()\n    head = move k\nend\n",
  "move local const":
    "forward pool nodes\nrecord Node\n    value as u8\n    next as nodes?\nend\npool nodes as Node[8]\nvar head as nodes?\nvar g as u8\nvar c as boolean\nsub main()\n    const k = 5\n    head = move k\nend\n",
  "move scalar dot":
    "forward pool nodes\nrecord Node\n    value as u8\n    next as nodes?\nend\npool nodes as Node[8]\nvar head as nodes?\nvar g as u8\nvar c as boolean\nsub main()\n    head = move g.x\nend\n",
  "move record const":
    "forward pool nodes\nrecord Node\n    value as u8\n    next as nodes?\nend\npool nodes as Node[8]\nvar head as nodes?\nvar g as u8\nvar c as boolean\nconst rc as u8[2] = [1, 2]\nsub main()\n    head = move rc\nend\n",
  "move lease":
    "forward pool nodes\nrecord Node\n    value as u8\n    next as nodes?\nend\npool nodes as Node[8]\nvar head as nodes?\nvar g as u8\nvar c as boolean\nsub main()\n    var a as nodes? = new nodes(1, none)\n    select a\n    case some(x)\n        head = move x\n    end\nend\n",
  "select move lease":
    "forward pool nodes\nrecord Node\n    value as u8\n    next as nodes?\nend\npool nodes as Node[8]\nvar head as nodes?\nvar g as u8\nvar c as boolean\nsub main()\n    var a as nodes? = new nodes(1, none)\n    select a\n    case some(x)\n        select move x\n        case some(y)\n        end\n    end\nend\n",
  "select move int":
    "forward pool nodes\nrecord Node\n    value as u8\n    next as nodes?\nend\npool nodes as Node[8]\nvar head as nodes?\nvar g as u8\nvar c as boolean\nsub main()\n    select move g\n    case 1\n    end\nend\n",
  "select move int expr":
    "forward pool nodes\nrecord Node\n    value as u8\n    next as nodes?\nend\npool nodes as Node[8]\nvar head as nodes?\nvar g as u8\nvar c as boolean\nsub main()\n    select move 1 + g\n    case 1\n    end\nend\n",
  "move to identifier":
    "forward pool nodes\nrecord Node\n    value as u8\n    next as nodes?\nend\npool nodes as Node[8]\nvar head as nodes?\nvar g as u8\nvar c as boolean\nsub main()\n    var a = new nodes(1, none)\n    var i as nodes# = move a\nend\n",
  "move stmt rule a.next = new(move a)":
    "forward pool nodes\nrecord Node\n    value as u8\n    next as nodes?\nend\npool nodes as Node[8]\nvar head as nodes?\nvar g as u8\nvar c as boolean\nsub main()\n    var a = new nodes(1, none)\n    a.next = new nodes(1, move a)\nend\n",
  "g = main":
    "forward pool nodes\nrecord Node\n    value as u8\n    next as nodes?\nend\npool nodes as Node[8]\nvar head as nodes?\nvar g as u8\nvar c as boolean\nsub main()\n    g = main\nend\n",
  "move sub f":
    "forward pool nodes\nrecord Node\n    value as u8\n    next as nodes?\nend\npool nodes as Node[8]\nvar head as nodes?\nvar g as u8\nvar c as boolean\nsub f()\nend\nsub main()\n    head = move f\nend\n",
  "g = f":
    "forward pool nodes\nrecord Node\n    value as u8\n    next as nodes?\nend\npool nodes as Node[8]\nvar head as nodes?\nvar g as u8\nvar c as boolean\nsub f()\nend\nsub main()\n    g = f\nend\n",
  "move type name":
    "forward pool nodes\nrecord Node\n    value as u8\n    next as nodes?\nend\npool nodes as Node[8]\nvar head as nodes?\nvar g as u8\nvar c as boolean\nsub main()\n    head = move Node\nend\n",
  "move pool name":
    "forward pool nodes\nrecord Node\n    value as u8\n    next as nodes?\nend\npool nodes as Node[8]\nvar head as nodes?\nvar g as u8\nvar c as boolean\nsub main()\n    head = move nodes\nend\n",
  "select move const":
    "forward pool nodes\nrecord Node\n    value as u8\n    next as nodes?\nend\npool nodes as Node[8]\nvar head as nodes?\nvar g as u8\nvar c as boolean\nconst k = 5\nsub main()\n    select move k\n    case 1\n    end\nend\n",
  "move const array idx":
    "forward pool nodes\nrecord Node\n    value as u8\n    next as nodes?\nend\npool nodes as Node[8]\nvar head as nodes?\nvar g as u8\nvar c as boolean\nconst rc as u8[2] = [1, 2]\nsub main()\n    head = move rc[1]\nend\n",
  "move u8 array elem":
    "forward pool nodes\nrecord Node\n    value as u8\n    next as nodes?\nend\npool nodes as Node[8]\nvar head as nodes?\nvar g as u8\nvar c as boolean\nsub main()\n    var arr as u8[2]\n    head = move arr[1]\nend\n",
  "move g[1]":
    "forward pool nodes\nrecord Node\n    value as u8\n    next as nodes?\nend\npool nodes as Node[8]\nvar head as nodes?\nvar g as u8\nvar c as boolean\nsub main()\n    head = move g[1]\nend\n",
  "move string len":
    "forward pool nodes\nrecord Node\n    value as u8\n    next as nodes?\nend\npool nodes as Node[8]\nvar head as nodes?\nvar g as u8\nvar c as boolean\nsub main()\n    var s as string[4]\n    head = move s.length\nend\n",
  "local init move const":
    "forward pool nodes\nrecord Node\n    value as u8\n    next as nodes?\nend\npool nodes as Node[8]\nvar head as nodes?\nvar g as u8\nvar c as boolean\nconst k = 5\nsub main()\n    var b = move k\nend\n",
  "typed local init move const":
    "forward pool nodes\nrecord Node\n    value as u8\n    next as nodes?\nend\npool nodes as Node[8]\nvar head as nodes?\nvar g as u8\nvar c as boolean\nconst k = 5\nsub main()\n    var b as nodes? = move k\nend\n",
  "new field move const":
    "forward pool nodes\nrecord Node\n    value as u8\n    next as nodes?\nend\npool nodes as Node[8]\nvar head as nodes?\nvar g as u8\nvar c as boolean\nconst k = 5\nsub main()\n    head = new nodes(1, move k)\nend\n",
  "a field read through an owner the statement reassigns":
    "forward pool nodes\nrecord Node\n    value as u8\n    next as nodes?\nend\npool nodes as Node[8]\nvar head as nodes?\nvar g as u8\nvar c as boolean\nsub main()\n    var a = new nodes(1, none)\n    a = new nodes(a.value, none)\nend\n",
  "a select's last arm moving, then a use":
    "forward pool nodes\nrecord Node\n    value as u8\n    next as nodes?\nend\npool nodes as Node[8]\nvar head as nodes?\nvar g as u8\nvar c as boolean\nsub main()\n    var a = new nodes(1, none)\n    select g\n    case 1\n        return\n    case else\n        head = move a\n        return\n    end\n    g = a.value\nend\n",
  "a handle select's none arm moving, then a use":
    "forward pool nodes\nrecord Node\n    value as u8\n    next as nodes?\nend\npool nodes as Node[8]\nvar head as nodes?\nvar g as u8\nvar c as boolean\nsub main()\n    var a = new nodes(1, none)\n    select head\n    case some(x)\n        return\n    case none\n        head = move a\n        return\n    end\n    g = a.value\nend\n",
  "none returned for a non-optional handle":
    "forward pool nodes\nrecord Node\n    value as u8\n    next as nodes?\nend\npool nodes as Node[8]\nrecord Leaf\n    v as u8\nend\npool leaves as Leaf[2]\nvar head as nodes?\nvar g as u8\nsub mk() as nodes\n    return none\nend\nsub main()\nend\n",
  "another pool's handle returned":
    "forward pool nodes\nrecord Node\n    value as u8\n    next as nodes?\nend\npool nodes as Node[8]\nrecord Leaf\n    v as u8\nend\npool leaves as Leaf[2]\nvar head as nodes?\nvar g as u8\nsub mk() as nodes?\n    return new leaves(1)\nend\nsub main()\nend\n",
  "a bare return from a handle routine":
    "forward pool nodes\nrecord Node\n    value as u8\n    next as nodes?\nend\npool nodes as Node[8]\nrecord Leaf\n    v as u8\nend\npool leaves as Leaf[2]\nvar head as nodes?\nvar g as u8\nsub mk() as nodes?\n    return\nend\nsub main()\nend\n",
  "a handle routine that can end without a value":
    "forward pool nodes\nrecord Node\n    value as u8\n    next as nodes?\nend\npool nodes as Node[8]\nrecord Leaf\n    v as u8\nend\npool leaves as Leaf[2]\nvar head as nodes?\nvar g as u8\nsub mk() as nodes?\n    g = 1\nend\nsub main()\nend\n",
  "none passed for a non-optional handle":
    "forward pool nodes\nrecord Node\n    value as u8\n    next as nodes?\nend\npool nodes as Node[8]\nrecord Leaf\n    v as u8\nend\npool leaves as Leaf[2]\nvar head as nodes?\nvar g as u8\nsub f(n as nodes)\nend\nsub main()\n    f(none)\nend\n",
  "another pool's handle passed":
    "forward pool nodes\nrecord Node\n    value as u8\n    next as nodes?\nend\npool nodes as Node[8]\nrecord Leaf\n    v as u8\nend\npool leaves as Leaf[2]\nvar head as nodes?\nvar g as u8\nsub f(n as nodes?)\nend\nsub main()\n    f(new leaves(1))\nend\n",
  "a number passed for a handle":
    "forward pool nodes\nrecord Node\n    value as u8\n    next as nodes?\nend\npool nodes as Node[8]\nrecord Leaf\n    v as u8\nend\npool leaves as Leaf[2]\nvar head as nodes?\nvar g as u8\nsub f(n as nodes?)\nend\nsub main()\n    f(3)\nend\n",
  "a parameter used after it is moved":
    "forward pool nodes\nrecord Node\n    value as u8\n    next as nodes?\nend\npool nodes as Node[8]\nrecord Leaf\n    v as u8\nend\npool leaves as Leaf[2]\nvar head as nodes?\nvar g as u8\nsub f(n as nodes)\n    head = move n\n    g = n.value\nend\nsub main()\nend\n",
  "a parameter moved in a loop":
    "forward pool nodes\nrecord Node\n    value as u8\n    next as nodes?\nend\npool nodes as Node[8]\nrecord Leaf\n    v as u8\nend\npool leaves as Leaf[2]\nvar head as nodes?\nvar g as u8\nsub f(n as nodes)\n    while g < 3\n        head = move n\n    end\nend\nsub main()\nend\n",
  "an optional parameter dereferenced":
    "forward pool nodes\nrecord Node\n    value as u8\n    next as nodes?\nend\npool nodes as Node[8]\nrecord Leaf\n    v as u8\nend\npool leaves as Leaf[2]\nvar head as nodes?\nvar g as u8\nsub f(n as nodes?)\n    g = n.value\nend\nsub main()\nend\n",
  "a parameter named twice":
    "forward pool nodes\nrecord Node\n    value as u8\n    next as nodes?\nend\npool nodes as Node[8]\nrecord Leaf\n    v as u8\nend\npool leaves as Leaf[2]\nvar head as nodes?\nvar g as u8\nsub f(n as nodes, n as u8)\nend\nsub main()\nend\n",
  "a parameter not optional for a field's handle":
    "forward pool nodes\nrecord Node\n    value as u8\n    next as nodes?\nend\npool nodes as Node[8]\nrecord Leaf\n    v as u8\nend\npool leaves as Leaf[2]\nvar head as nodes?\nvar g as u8\nsub f(n as nodes)\nend\nsub main()\n    var a as nodes? = none\n    f(move a)\nend\n",
  "bare return from a u8 routine":
    "var g as u8\nsub mk() as u8\n    return\nend\nsub main()\nend\n",
  "a value from a routine without a result":
    "var g as u8\nsub mk()\n    return 3\nend\nsub main()\nend\n",
  "a value returned from main": "sub main()\n    return 1\nend\n",
  "from naming a handle parameter":
    "forward pool nodes\nrecord Node\n    value as u8\n    next as nodes?\nend\npool nodes as Node[8]\nvar head as nodes?\nvar g as u8\nvar s as string[8]\nsub make(v as u8) as nodes\n    return new nodes(v, none)\nend\nsub nothing()\nend\nsub f(n as nodes) as string[8] from n\n    return s\nend\nsub main()\nend\n",
  "a call without a result as an owner's value":
    "forward pool nodes\nrecord Node\n    value as u8\n    next as nodes?\nend\npool nodes as Node[8]\nvar head as nodes?\nvar g as u8\nvar s as string[8]\nsub make(v as u8) as nodes\n    return new nodes(v, none)\nend\nsub nothing()\nend\nsub main()\n    head = nothing()\nend\n",
  "a call without a result returned as a handle":
    "forward pool nodes\nrecord Node\n    value as u8\n    next as nodes?\nend\npool nodes as Node[8]\nvar head as nodes?\nvar g as u8\nvar s as string[8]\nsub make(v as u8) as nodes\n    return new nodes(v, none)\nend\nsub nothing()\nend\nsub f() as nodes\n    return nothing()\nend\nsub main()\nend\n",
  "an undeclared name as an owner's value":
    "forward pool nodes\nrecord Node\n    value as u8\n    next as nodes?\nend\npool nodes as Node[8]\nvar head as nodes?\nvar g as u8\nvar s as string[8]\nsub make(v as u8) as nodes\n    return new nodes(v, none)\nend\nsub nothing()\nend\nsub main()\n    head = nope()\nend\n",
  "id of a scalar":
    "forward pool nodes\nrecord Node\n    value as u8\n    next as nodes?\nend\npool nodes as Node[8]\nrecord Leaf\n    v as u8\nend\npool leaves as Leaf[2]\nvar g as u8\nvar keep as id nodes?\nsub main()\n    var n = new nodes(1, none)\n    var i = id(g)\nend\n",
  "id of an identifier":
    "forward pool nodes\nrecord Node\n    value as u8\n    next as nodes?\nend\npool nodes as Node[8]\nrecord Leaf\n    v as u8\nend\npool leaves as Leaf[2]\nvar g as u8\nvar keep as id nodes?\nsub main()\n    var n = new nodes(1, none)\n    var i = id(n)\n    var j = id(i)\nend\n",
  "id of another pool's handle into a location":
    "forward pool nodes\nrecord Node\n    value as u8\n    next as nodes?\nend\npool nodes as Node[8]\nrecord Leaf\n    v as u8\nend\npool leaves as Leaf[2]\nvar g as u8\nvar keep as id nodes?\nsub main()\n    var n = new nodes(1, none)\n    var l = new leaves(1)\n    keep = id(l)\nend\n",
  "none for a non-optional identifier":
    "forward pool nodes\nrecord Node\n    value as u8\n    next as nodes?\nend\npool nodes as Node[8]\nrecord Leaf\n    v as u8\nend\npool leaves as Leaf[2]\nvar g as u8\nvar keep as id nodes?\nsub main()\n    var n = new nodes(1, none)\n    var i as id nodes = none\nend\n",
  "an optional identifier for a non-optional one":
    "forward pool nodes\nrecord Node\n    value as u8\n    next as nodes?\nend\npool nodes as Node[8]\nrecord Leaf\n    v as u8\nend\npool leaves as Leaf[2]\nvar g as u8\nvar keep as id nodes?\nsub main()\n    var n = new nodes(1, none)\n    var i as id nodes = keep\nend\n",
  "an owner for an identifier":
    "forward pool nodes\nrecord Node\n    value as u8\n    next as nodes?\nend\npool nodes as Node[8]\nrecord Leaf\n    v as u8\nend\npool leaves as Leaf[2]\nvar g as u8\nvar keep as id nodes?\nsub main()\n    var n = new nodes(1, none)\n    keep = n\nend\n",
  "an identifier for an owner":
    "forward pool nodes\nrecord Node\n    value as u8\n    next as nodes?\nend\npool nodes as Node[8]\nrecord Leaf\n    v as u8\nend\npool leaves as Leaf[2]\nvar g as u8\nvar keep as id nodes?\nsub main()\n    var n = new nodes(1, none)\n    var i = id(n)\n    var h as nodes? = i\nend\n",
  "id of a moved owner":
    "forward pool nodes\nrecord Node\n    value as u8\n    next as nodes?\nend\npool nodes as Node[8]\nrecord Leaf\n    v as u8\nend\npool leaves as Leaf[2]\nvar g as u8\nvar keep as id nodes?\nsub main()\n    var n = new nodes(1, none)\n    var h as nodes? = move n\n    keep = id(n)\nend\n",
  "a number for an identifier":
    "forward pool nodes\nrecord Node\n    value as u8\n    next as nodes?\nend\npool nodes as Node[8]\nrecord Leaf\n    v as u8\nend\npool leaves as Leaf[2]\nvar g as u8\nvar keep as id nodes?\nsub main()\n    var n = new nodes(1, none)\n    keep = 3\nend\n",
  "id without parentheses":
    "forward pool nodes\nrecord Node\n    value as u8\n    next as nodes?\nend\npool nodes as Node[8]\nrecord Leaf\n    v as u8\nend\npool leaves as Leaf[2]\nvar g as u8\nvar keep as id nodes?\nsub main()\n    var n = new nodes(1, none)\n    keep = id n\nend\n",
  "an owner copied into a local":
    "forward pool nodes\nrecord Node\n    value as u8\n    next as nodes?\nend\npool nodes as Node[8]\nrecord Leaf\n    v as u8\nend\npool leaves as Leaf[2]\nvar g as u8\nvar keep as id nodes?\nsub main()\n    var n = new nodes(1, none)\n    var b = n\nend\n",
  "an owner copied into an optional local":
    "forward pool nodes\nrecord Node\n    value as u8\n    next as nodes?\nend\npool nodes as Node[8]\nrecord Leaf\n    v as u8\nend\npool leaves as Leaf[2]\nvar g as u8\nvar keep as id nodes?\nsub main()\n    var n = new nodes(1, none)\n    var b as nodes? = n\nend\n",
  "an owner copied": Deno.readTextFileSync(
    "tests/conformance/storage/owner-not-copied.bsi",
  ),
  "a scalar assigned to an owning field":
    "forward pool nodes\nrecord Node\n    value as u8\n    next as nodes?\n    peer as id nodes?\n    ps as id nodes?[2]\nend\npool nodes as Node[8]\nvar keep as id nodes?\nvar ks as id nodes?[3]\nvar g as u8\nvar head as nodes?\nsub take(x as nodes?)\nend\nsub main()\n    var n as nodes? = new nodes(1, none, none)\n    var o = new nodes(2, none, none)\n    o.next = g\nend\n",
  "a scalar assigned to an owning variable":
    "forward pool nodes\nrecord Node\n    value as u8\n    next as nodes?\n    peer as id nodes?\n    ps as id nodes?[2]\nend\npool nodes as Node[8]\nvar keep as id nodes?\nvar ks as id nodes?[3]\nvar g as u8\nvar head as nodes?\nsub take(x as nodes?)\nend\nsub main()\n    var n as nodes? = new nodes(1, none, none)\n    var o = new nodes(2, none, none)\n    head = g\nend\n",
  "a scalar assigned to an identifier field":
    "forward pool nodes\nrecord Node\n    value as u8\n    next as nodes?\n    peer as id nodes?\n    ps as id nodes?[2]\nend\npool nodes as Node[8]\nvar keep as id nodes?\nvar ks as id nodes?[3]\nvar g as u8\nvar head as nodes?\nsub take(x as nodes?)\nend\nsub main()\n    var n as nodes? = new nodes(1, none, none)\n    var o = new nodes(2, none, none)\n    o.peer = g\nend\n",
  "a scalar plus an undeclared name for an owner":
    "forward pool nodes\nrecord Node\n    value as u8\n    next as nodes?\n    peer as id nodes?\n    ps as id nodes?[2]\nend\npool nodes as Node[8]\nvar keep as id nodes?\nvar ks as id nodes?[3]\nvar g as u8\nvar head as nodes?\nsub take(x as nodes?)\nend\nsub main()\n    var n as nodes? = new nodes(1, none, none)\n    var o = new nodes(2, none, none)\n    o.next = g + zz\nend\n",
  "id alone inferred":
    "forward pool nodes\nrecord Node\n    value as u8\n    next as nodes?\n    peer as id nodes?\n    ps as id nodes?[2]\nend\npool nodes as Node[8]\nvar keep as id nodes?\nvar ks as id nodes?[3]\nvar g as u8\nvar head as nodes?\nsub take(x as nodes?)\nend\nsub main()\n    var n as nodes? = new nodes(1, none, none)\n    var o = new nodes(2, none, none)\n    var i = id\nend\n",
  "id plus one inferred":
    "forward pool nodes\nrecord Node\n    value as u8\n    next as nodes?\n    peer as id nodes?\n    ps as id nodes?[2]\nend\npool nodes as Node[8]\nvar keep as id nodes?\nvar ks as id nodes?[3]\nvar g as u8\nvar head as nodes?\nsub take(x as nodes?)\nend\nsub main()\n    var n as nodes? = new nodes(1, none, none)\n    var o = new nodes(2, none, none)\n    var b = id + 1\nend\n",
  "id alone for a u8":
    "forward pool nodes\nrecord Node\n    value as u8\n    next as nodes?\n    peer as id nodes?\n    ps as id nodes?[2]\nend\npool nodes as Node[8]\nvar keep as id nodes?\nvar ks as id nodes?[3]\nvar g as u8\nvar head as nodes?\nsub take(x as nodes?)\nend\nsub main()\n    var n as nodes? = new nodes(1, none, none)\n    var o = new nodes(2, none, none)\n    var b as u8 = id\nend\n",
  "pool of a string": "pool p as string[4][2]\nsub main()\nend\n",
  "operands: int plus bool":
    "var a as boolean\nvar n as u8\nvar w as u16\nvar s as i8\nsub main()\n    n = n + a\nend\n",
  "operands: int plus bool expr":
    "var a as boolean\nvar n as u8\nvar w as u16\nvar s as i8\nsub main()\n    n = n + (a and a)\nend\n",
  "operands: bool plus int":
    "var a as boolean\nvar n as u8\nvar w as u16\nvar s as i8\nsub main()\n    n = a + n\nend\n",
  "operands: bool times":
    "var a as boolean\nvar n as u8\nvar w as u16\nvar s as i8\nsub main()\n    n = a * a\nend\n",
  "operands: int or bool":
    "var a as boolean\nvar n as u8\nvar w as u16\nvar s as i8\nsub main()\n    n = n or a\nend\n",
  "operands: int and bool":
    "var a as boolean\nvar n as u8\nvar w as u16\nvar s as i8\nsub main()\n    n = n and a\nend\n",
  "operands: bool and int":
    "var a as boolean\nvar n as u8\nvar w as u16\nvar s as i8\nsub main()\n    a = a and n\nend\n",
  "operands: bool or int":
    "var a as boolean\nvar n as u8\nvar w as u16\nvar s as i8\nsub main()\n    a = a or n\nend\n",
  "operands: bool and known int":
    "var a as boolean\nvar n as u8\nvar w as u16\nvar s as i8\nsub main()\n    a = a and 1\nend\n",
  "operands: known bool and int":
    "var a as boolean\nvar n as u8\nvar w as u16\nvar s as i8\nsub main()\n    a = true and n\nend\n",
  "operands: bool xor int":
    "var a as boolean\nvar n as u8\nvar w as u16\nvar s as i8\nsub main()\n    a = a xor n\nend\n",
  "operands: bool less":
    "var a as boolean\nvar n as u8\nvar w as u16\nvar s as i8\nsub main()\n    a = a < a\nend\n",
  "operands: int eq bool":
    "var a as boolean\nvar n as u8\nvar w as u16\nvar s as i8\nsub main()\n    a = n = a\nend\n",
  "operands: bool eq int":
    "var a as boolean\nvar n as u8\nvar w as u16\nvar s as i8\nsub main()\n    a = a = n\nend\n",
  "operands: mixed sign":
    "var a as boolean\nvar n as u8\nvar w as u16\nvar s as i8\nsub main()\n    n = n + s\nend\n",
  "operands: nested right":
    "var a as boolean\nvar n as u8\nvar w as u16\nvar s as i8\nsub main()\n    n = n + n * a\nend\n",
  "operands: nested left":
    "var a as boolean\nvar n as u8\nvar w as u16\nvar s as i8\nsub main()\n    n = n * a + n\nend\n",
  "operands: chain":
    "var a as boolean\nvar n as u8\nvar w as u16\nvar s as i8\nsub main()\n    a = n < n < n\nend\n",
  "operands: paren right":
    "var a as boolean\nvar n as u8\nvar w as u16\nvar s as i8\nsub main()\n    n = n + (n * a)\nend\n",
  "operands: int shl bool":
    "var a as boolean\nvar n as u8\nvar w as u16\nvar s as i8\nsub main()\n    n = n << a\nend\n",
  "operands: neg bool":
    "var a as boolean\nvar n as u8\nvar w as u16\nvar s as i8\nsub main()\n    n = -a\nend\n",
  "operands: not int":
    "var a as boolean\nvar n as u8\nvar w as u16\nvar s as i8\nsub main()\n    a = not n\nend\n",
  "operands: bool xor int (xor)":
    "var a as boolean\nvar n as u8\nsub main()\n    a = a xor n\nend\n",
  "operands: known bool xor int (xor)":
    "var a as boolean\nvar n as u8\nsub main()\n    a = true xor n\nend\n",
  "operands: int xor bool (xor)":
    "var a as boolean\nvar n as u8\nsub main()\n    n = n xor a\nend\n",
  "operands: known bool xor known int (xor)":
    "var a as boolean\nvar n as u8\nsub main()\n    a = true xor 3\nend\n",
  "an owning record assigned to a field":
    "forward pool nodes\nrecord Node\n    next as nodes?\nend\nrecord Box\n    n as Node\n    v as u8\nend\npool nodes as Node[4]\nvar a as Node\nvar b as Box\nvar c as Box\nsub main()\n    b.n = a\nend\n",
  "a record holding an owning record assigned":
    "forward pool nodes\nrecord Node\n    next as nodes?\nend\nrecord Box\n    n as Node\n    v as u8\nend\npool nodes as Node[4]\nvar a as Node\nvar b as Box\nvar c as Box\nsub main()\n    b = c\nend\n",
  "an owning record parameter assigned":
    "forward pool nodes\nrecord Node\n    next as nodes?\nend\nrecord Box\n    n as Node\n    v as u8\nend\npool nodes as Node[4]\nvar a as Node\nvar b as Box\nvar c as Box\nsub f(x as Node)\n    a = x\nend\nsub main()\nend\n",
  "a record through an owner assigned":
    "forward pool nodes\nrecord Node\n    next as nodes?\nend\nrecord Box\n    n as Node\n    v as u8\nend\npool nodes as Node[4]\nvar a as Node\nvar b as Box\nvar c as Box\nsub main()\n    var h = new nodes(none)\n    a = h\nend\n",
  "owning records copied": Deno.readTextFileSync(
    "tests/conformance/types/owning-records-dont-copy.bsi",
  ),
  "identifiers of two pools compared":
    "forward pool nodes\nrecord Node\n    value as u8\nend\npool nodes as Node[4]\nrecord Leaf\n    v as u8\nend\npool leaves as Leaf[2]\nvar keep as id nodes?\nvar lk as id leaves?\nvar f as File\nvar b as boolean\nvar n as u8\nsub main()\n    b = keep = lk\nend\n",
  "an identifier compared with a number":
    "forward pool nodes\nrecord Node\n    value as u8\nend\npool nodes as Node[4]\nrecord Leaf\n    v as u8\nend\npool leaves as Leaf[2]\nvar keep as id nodes?\nvar lk as id leaves?\nvar f as File\nvar b as boolean\nvar n as u8\nsub main()\n    b = keep = 3\nend\n",
  "Files ordered":
    "forward pool nodes\nrecord Node\n    value as u8\nend\npool nodes as Node[4]\nrecord Leaf\n    v as u8\nend\npool leaves as Leaf[2]\nvar keep as id nodes?\nvar lk as id leaves?\nvar f as File\nvar b as boolean\nvar n as u8\nsub main()\n    b = f < console\nend\n",
  "a File compared with a number":
    "forward pool nodes\nrecord Node\n    value as u8\nend\npool nodes as Node[4]\nrecord Leaf\n    v as u8\nend\npool leaves as Leaf[2]\nvar keep as id nodes?\nvar lk as id leaves?\nvar f as File\nvar b as boolean\nvar n as u8\nsub main()\n    b = f = 1\nend\n",
  "a File as an operand of +":
    "forward pool nodes\nrecord Node\n    value as u8\nend\npool nodes as Node[4]\nrecord Leaf\n    v as u8\nend\npool leaves as Leaf[2]\nvar keep as id nodes?\nvar lk as id leaves?\nvar f as File\nvar b as boolean\nvar n as u8\nsub main()\n    n = f + 1\nend\n",
  "an identifier compared with an owner":
    "forward pool nodes\nrecord Node\n    value as u8\nend\npool nodes as Node[4]\nrecord Leaf\n    v as u8\nend\npool leaves as Leaf[2]\nvar keep as id nodes?\nvar lk as id leaves?\nvar f as File\nvar b as boolean\nvar n as u8\nsub main()\n    var a = new nodes(1)\n    b = keep = a\nend\n",
  "a record of another type through an identifier":
    "forward pool boxes\nforward pool nodes\nrecord Node\n    value as u8\n    next as nodes?\nend\nrecord A\n    w as u16\nend\nrecord B\n    q as u8\nend\nrecord Holder\n    h as nodes?\nend\nrecord Box\n    a as A\n    b as B\n    hold as Holder\n    name as string[4]\n    own as nodes?\nend\npool boxes as Box[2]\npool nodes as Node[2]\nvar keep as id boxes?\nvar gl as A\nsub mk() as A\n    return gl\nend\nsub two(x as A, y as A)\nend\nsub pb(x as B)\nend\nsub vb(var x as B)\nend\nsub ph(x as Holder)\nend\nsub vs(var s as string[])\nend\nsub ps(s as string[])\nend\nsub main()\n    select keep\n    case some(i)\n        pb(i.a)\n    case none\n    end\nend\n",
  "a record of another type through an identifier to a var parameter":
    "forward pool boxes\nforward pool nodes\nrecord Node\n    value as u8\n    next as nodes?\nend\nrecord A\n    w as u16\nend\nrecord B\n    q as u8\nend\nrecord Holder\n    h as nodes?\nend\nrecord Box\n    a as A\n    b as B\n    hold as Holder\n    name as string[4]\n    own as nodes?\nend\npool boxes as Box[2]\npool nodes as Node[2]\nvar keep as id boxes?\nvar gl as A\nsub mk() as A\n    return gl\nend\nsub two(x as A, y as A)\nend\nsub pb(x as B)\nend\nsub vb(var x as B)\nend\nsub ph(x as Holder)\nend\nsub vs(var s as string[])\nend\nsub ps(s as string[])\nend\nsub main()\n    select keep\n    case some(i)\n        vb(i.a)\n    case none\n    end\nend\n",
  "an owning record of another type through an identifier":
    "forward pool boxes\nforward pool nodes\nrecord Node\n    value as u8\n    next as nodes?\nend\nrecord A\n    w as u16\nend\nrecord B\n    q as u8\nend\nrecord Holder\n    h as nodes?\nend\nrecord Box\n    a as A\n    b as B\n    hold as Holder\n    name as string[4]\n    own as nodes?\nend\npool boxes as Box[2]\npool nodes as Node[2]\nvar keep as id boxes?\nvar gl as A\nsub mk() as A\n    return gl\nend\nsub two(x as A, y as A)\nend\nsub pb(x as B)\nend\nsub vb(var x as B)\nend\nsub ph(x as Holder)\nend\nsub vs(var s as string[])\nend\nsub ps(s as string[])\nend\nsub main()\n    select keep\n    case some(i)\n        pb(i.hold)\n    case none\n    end\nend\n",
  "an owning record through an identifier copied":
    "forward pool boxes\nforward pool nodes\nrecord Node\n    value as u8\n    next as nodes?\nend\nrecord A\n    w as u16\nend\nrecord B\n    q as u8\nend\nrecord Holder\n    h as nodes?\nend\nrecord Box\n    a as A\n    b as B\n    hold as Holder\n    name as string[4]\n    own as nodes?\nend\npool boxes as Box[2]\npool nodes as Node[2]\nvar keep as id boxes?\nvar gl as A\nsub mk() as A\n    return gl\nend\nsub two(x as A, y as A)\nend\nsub pb(x as B)\nend\nsub vb(var x as B)\nend\nsub ph(x as Holder)\nend\nsub vs(var s as string[])\nend\nsub ps(s as string[])\nend\nsub main()\n    select keep\n    case some(i)\n        ph(i.hold)\n    case none\n    end\nend\n",
  "a handle field through an identifier for a string":
    "forward pool boxes\nforward pool nodes\nrecord Node\n    value as u8\n    next as nodes?\nend\nrecord A\n    w as u16\nend\nrecord B\n    q as u8\nend\nrecord Holder\n    h as nodes?\nend\nrecord Box\n    a as A\n    b as B\n    hold as Holder\n    name as string[4]\n    own as nodes?\nend\npool boxes as Box[2]\npool nodes as Node[2]\nvar keep as id boxes?\nvar gl as A\nsub mk() as A\n    return gl\nend\nsub two(x as A, y as A)\nend\nsub pb(x as B)\nend\nsub vb(var x as B)\nend\nsub ph(x as Holder)\nend\nsub vs(var s as string[])\nend\nsub ps(s as string[])\nend\nsub main()\n    select keep\n    case some(i)\n        ps(i.own)\n    case none\n    end\nend\n",
  "a string through an identifier to a var string parameter":
    "forward pool boxes\nforward pool nodes\nrecord Node\n    value as u8\n    next as nodes?\nend\nrecord A\n    w as u16\nend\nrecord B\n    q as u8\nend\nrecord Holder\n    h as nodes?\nend\nrecord Box\n    a as A\n    b as B\n    hold as Holder\n    name as string[4]\n    own as nodes?\nend\npool boxes as Box[2]\npool nodes as Node[2]\nvar keep as id boxes?\nvar gl as A\nsub mk() as A\n    return gl\nend\nsub two(x as A, y as A)\nend\nsub pb(x as B)\nend\nsub vb(var x as B)\nend\nsub ph(x as Holder)\nend\nsub vs(var s as string[])\nend\nsub ps(s as string[])\nend\nsub main()\n    select keep\n    case some(i)\n        vs(i.name)\n    case none\n    end\nend\n",
  "an owner for an identifier parameter":
    "forward pool nodes\nrecord Node\n    value as u8\n    next as nodes?\nend\nrecord Leaf\n    v as u8\nend\npool nodes as Node[8]\npool leaves as Leaf[2]\nvar list as nodes?\nvar keep as id nodes?\nvar g as u8\nsub look(i as id nodes?)\n    select i\n    case some(n)\n        g = n.value\n    case none\n    end\nend\nsub must(i as id nodes)\n    g = i.value\nend\nsub main()\n    var a = new nodes(1, none)\n    look(a)\nend\n",
  "none for a non-optional identifier parameter":
    "forward pool nodes\nrecord Node\n    value as u8\n    next as nodes?\nend\nrecord Leaf\n    v as u8\nend\npool nodes as Node[8]\npool leaves as Leaf[2]\nvar list as nodes?\nvar keep as id nodes?\nvar g as u8\nsub look(i as id nodes?)\n    select i\n    case some(n)\n        g = n.value\n    case none\n    end\nend\nsub must(i as id nodes)\n    g = i.value\nend\nsub main()\n    must(none)\nend\n",
  "an optional identifier for a non-optional parameter":
    "forward pool nodes\nrecord Node\n    value as u8\n    next as nodes?\nend\nrecord Leaf\n    v as u8\nend\npool nodes as Node[8]\npool leaves as Leaf[2]\nvar list as nodes?\nvar keep as id nodes?\nvar g as u8\nsub look(i as id nodes?)\n    select i\n    case some(n)\n        g = n.value\n    case none\n    end\nend\nsub must(i as id nodes)\n    g = i.value\nend\nsub main()\n    must(keep)\nend\n",
  "another pool's identifier passed":
    "forward pool nodes\nrecord Node\n    value as u8\n    next as nodes?\nend\nrecord Leaf\n    v as u8\nend\npool nodes as Node[8]\npool leaves as Leaf[2]\nvar list as nodes?\nvar keep as id nodes?\nvar g as u8\nsub look(i as id nodes?)\n    select i\n    case some(n)\n        g = n.value\n    case none\n    end\nend\nsub must(i as id nodes)\n    g = i.value\nend\nsub main()\n    var a = new leaves(1)\n    look(id(a))\nend\n",
  "a number for an identifier parameter":
    "forward pool nodes\nrecord Node\n    value as u8\n    next as nodes?\nend\nrecord Leaf\n    v as u8\nend\npool nodes as Node[8]\npool leaves as Leaf[2]\nvar list as nodes?\nvar keep as id nodes?\nvar g as u8\nsub look(i as id nodes?)\n    select i\n    case some(n)\n        g = n.value\n    case none\n    end\nend\nsub must(i as id nodes)\n    g = i.value\nend\nsub main()\n    look(5)\nend\n",
  "id of a moved owner passed":
    "forward pool nodes\nrecord Node\n    value as u8\n    next as nodes?\nend\nrecord Leaf\n    v as u8\nend\npool nodes as Node[8]\npool leaves as Leaf[2]\nvar list as nodes?\nvar keep as id nodes?\nvar g as u8\nsub look(i as id nodes?)\n    select i\n    case some(n)\n        g = n.value\n    case none\n    end\nend\nsub must(i as id nodes)\n    g = i.value\nend\nsub main()\n    var a = new nodes(1, none)\n    var b = move a\n    look(id(a))\nend\n",
  "an owner moved twice in one expression":
    "forward pool nodes\nrecord Node\n    value as u8\n    next as nodes?\nend\npool nodes as Node[8]\nvar g as u8\nvar b as boolean\nsub eat(n as nodes) as u8\n    return n.value\nend\nsub maybe(n as nodes?) as u8\n    return 1\nend\nsub take(n as nodes) as nodes\n    return move n\nend\nsub main()\n    var x = new nodes(1, none)\n    g = eat(move x) + eat(move x)\nend\n",
  "an owner used after its move in one expression":
    "forward pool nodes\nrecord Node\n    value as u8\n    next as nodes?\nend\npool nodes as Node[8]\nvar g as u8\nvar b as boolean\nsub eat(n as nodes) as u8\n    return n.value\nend\nsub maybe(n as nodes?) as u8\n    return 1\nend\nsub take(n as nodes) as nodes\n    return move n\nend\nsub main()\n    var x = new nodes(1, none)\n    g = eat(move x) + x.value\nend\n",
  "an owner copied to a call in an expression":
    "forward pool nodes\nrecord Node\n    value as u8\n    next as nodes?\nend\npool nodes as Node[8]\nvar g as u8\nvar b as boolean\nsub eat(n as nodes) as u8\n    return n.value\nend\nsub maybe(n as nodes?) as u8\n    return 1\nend\nsub take(n as nodes) as nodes\n    return move n\nend\nsub main()\n    var x = new nodes(1, none)\n    g = eat(x)\nend\n",
  "an owner used after a move in an expression":
    "forward pool nodes\nrecord Node\n    value as u8\n    next as nodes?\nend\npool nodes as Node[8]\nvar g as u8\nvar b as boolean\nsub eat(n as nodes) as u8\n    return n.value\nend\nsub maybe(n as nodes?) as u8\n    return 1\nend\nsub take(n as nodes) as nodes\n    return move n\nend\nsub main()\n    var x = new nodes(1, none)\n    g = eat(move x)\n    g = x.value\nend\n",
  "an owner moved in a condition used in the else arm":
    "forward pool nodes\nrecord Node\n    value as u8\n    next as nodes?\nend\npool nodes as Node[8]\nvar g as u8\nvar b as boolean\nsub eat(n as nodes) as u8\n    return n.value\nend\nsub maybe(n as nodes?) as u8\n    return 1\nend\nsub take(n as nodes) as nodes\n    return move n\nend\nsub main()\n    var x = new nodes(1, none)\n    if eat(move x) = 1\n        g = 1\n    else\n        g = x.value\n    end\nend\n",
  "an owner moved in an expression in a loop":
    "forward pool nodes\nrecord Node\n    value as u8\n    next as nodes?\nend\npool nodes as Node[8]\nvar g as u8\nvar b as boolean\nsub eat(n as nodes) as u8\n    return n.value\nend\nsub maybe(n as nodes?) as u8\n    return 1\nend\nsub take(n as nodes) as nodes\n    return move n\nend\nsub main()\n    var x = new nodes(1, none)\n    while b\n        g = eat(move x)\n    end\nend\n",
  "an owner moved in its own assignment's value":
    "forward pool nodes\nrecord Node\n    value as u8\n    next as nodes?\nend\npool nodes as Node[8]\nvar g as u8\nvar b as boolean\nsub eat(n as nodes) as u8\n    return n.value\nend\nsub maybe(n as nodes?) as u8\n    return 1\nend\nsub take(n as nodes) as nodes\n    return move n\nend\nsub main()\n    var x = new nodes(1, none)\n    x.value = eat(take(move x))\nend\n",
  "the statement rule": Deno.readTextFileSync(
    "tests/conformance/storage/statement-rule.bsi",
  ),
  "a lease then a move in one statement": Deno.readTextFileSync(
    "tests/conformance/storage/lease-then-move.bsi",
  ),
  "a move in an elseif condition": Deno.readTextFileSync(
    "tests/conformance/storage/move-in-elseif-condition.bsi",
  ),
  "a maybe-moved owner of another pool lent":
    "forward pool nodes\nrecord Node\n    value as u8\n    next as nodes?\nend\nrecord Leaf\n    v as u8\nend\npool nodes as Node[8]\npool leaves as Leaf[2]\nvar list as nodes?\nvar keep as id nodes?\nvar g as u8\nsub bump(var n as Node)\n    n.value = n.value + 1\nend\nsub look(n as Node)\n    g = n.value\nend\nsub make() as nodes\n    return new nodes(1, none)\nend\nsub main()\n    var a = new leaves(1)\n    if g = 1\n        var b = move a\n    end\n    bump(a)\nend\n",
  "id of a value record parameter":
    "forward pool nodes\nrecord Node\n    value as u8\n    next as nodes?\nend\nrecord Leaf\n    v as u8\nend\npool nodes as Node[8]\npool leaves as Leaf[2]\nvar list as nodes?\nvar keep as id nodes?\nvar g as u8\nsub bump(var n as Node)\n    n.value = n.value + 1\nend\nsub look(n as Node)\n    g = n.value\nend\nsub make() as nodes\n    return new nodes(1, none)\nend\nsub f(n as Node)\n    var i = id(n)\nend\nsub main()\nend\n",
  "id of a local record":
    "forward pool nodes\nrecord Node\n    value as u8\n    next as nodes?\nend\nrecord Leaf\n    v as u8\nend\npool nodes as Node[8]\npool leaves as Leaf[2]\nvar list as nodes?\nvar keep as id nodes?\nvar g as u8\nsub bump(var n as Node)\n    n.value = n.value + 1\nend\nsub look(n as Node)\n    g = n.value\nend\nsub make() as nodes\n    return new nodes(1, none)\nend\nsub f()\n    var r as Leaf\n    var i = id(r)\nend\nsub main()\nend\n",
  "id of a var record parameter's field":
    "forward pool nodes\nrecord Node\n    value as u8\n    next as nodes?\nend\nrecord Leaf\n    v as u8\nend\npool nodes as Node[8]\npool leaves as Leaf[2]\nvar list as nodes?\nvar keep as id nodes?\nvar g as u8\nsub bump(var n as Node)\n    n.value = n.value + 1\nend\nsub look(n as Node)\n    g = n.value\nend\nsub make() as nodes\n    return new nodes(1, none)\nend\nrecord Box\n    l as Leaf\nend\nsub f(var b as Box)\n    var i = id(b.l)\nend\nsub main()\nend\n",
  "id of a program variable record":
    "forward pool nodes\nrecord Node\n    value as u8\n    next as nodes?\nend\nrecord Leaf\n    v as u8\nend\npool nodes as Node[8]\npool leaves as Leaf[2]\nvar list as nodes?\nvar keep as id nodes?\nvar g as u8\nsub bump(var n as Node)\n    n.value = n.value + 1\nend\nsub look(n as Node)\n    g = n.value\nend\nsub make() as nodes\n    return new nodes(1, none)\nend\nvar r as Leaf\nsub main()\n    var i = id(r)\nend\n",
  "id of a record for another pool's identifier":
    "forward pool nodes\nrecord Node\n    value as u8\n    next as nodes?\nend\nrecord Leaf\n    v as u8\nend\npool nodes as Node[8]\npool leaves as Leaf[2]\nvar list as nodes?\nvar keep as id nodes?\nvar g as u8\nsub bump(var n as Node)\n    n.value = n.value + 1\nend\nsub look(n as Node)\n    g = n.value\nend\nsub make() as nodes\n    return new nodes(1, none)\nend\nsub f(var x as Node)\n    var i as id leaves? = id(x)\nend\nsub main()\nend\n",
  "id of a var array parameter":
    "forward pool nodes\nrecord Node\n    value as u8\n    next as nodes?\nend\nrecord Leaf\n    v as u8\nend\npool nodes as Node[8]\npool leaves as Leaf[2]\nvar list as nodes?\nvar keep as id nodes?\nvar g as u8\nsub bump(var n as Node)\n    n.value = n.value + 1\nend\nsub look(n as Node)\n    g = n.value\nend\nsub make() as nodes\n    return new nodes(1, none)\nend\nsub f(var a as u8[2])\n    var i = id(a)\nend\nsub main()\nend\n",
  "an optional owner lent":
    "forward pool nodes\nrecord Node\n    value as u8\n    next as nodes?\nend\nrecord Leaf\n    v as u8\nend\npool nodes as Node[8]\npool leaves as Leaf[2]\nvar list as nodes?\nvar keep as id nodes?\nvar g as u8\nsub bump(var n as Node)\n    n.value = n.value + 1\nend\nsub look(n as Node)\n    g = n.value\nend\nsub make() as nodes\n    return new nodes(1, none)\nend\nsub main()\n    var a as nodes? = new nodes(1, none)\n    bump(a)\nend\n",
  "an identifier lent":
    "forward pool nodes\nrecord Node\n    value as u8\n    next as nodes?\nend\nrecord Leaf\n    v as u8\nend\npool nodes as Node[8]\npool leaves as Leaf[2]\nvar list as nodes?\nvar keep as id nodes?\nvar g as u8\nsub bump(var n as Node)\n    n.value = n.value + 1\nend\nsub look(n as Node)\n    g = n.value\nend\nsub make() as nodes\n    return new nodes(1, none)\nend\nsub main()\n    var a = id(list)\n    bump(a)\nend\n",
  "another pool's owner lent":
    "forward pool nodes\nrecord Node\n    value as u8\n    next as nodes?\nend\nrecord Leaf\n    v as u8\nend\npool nodes as Node[8]\npool leaves as Leaf[2]\nvar list as nodes?\nvar keep as id nodes?\nvar g as u8\nsub bump(var n as Node)\n    n.value = n.value + 1\nend\nsub look(n as Node)\n    g = n.value\nend\nsub make() as nodes\n    return new nodes(1, none)\nend\nsub main()\n    var a = new leaves(1)\n    bump(a)\nend\n",
  "a program variable lent":
    "forward pool nodes\nrecord Node\n    value as u8\n    next as nodes?\nend\nrecord Leaf\n    v as u8\nend\npool nodes as Node[8]\npool leaves as Leaf[2]\nvar list as nodes?\nvar keep as id nodes?\nvar g as u8\nsub bump(var n as Node)\n    n.value = n.value + 1\nend\nsub look(n as Node)\n    g = n.value\nend\nsub make() as nodes\n    return new nodes(1, none)\nend\nsub main()\n    bump(list)\nend\n",
  "a moved owner lent":
    "forward pool nodes\nrecord Node\n    value as u8\n    next as nodes?\nend\nrecord Leaf\n    v as u8\nend\npool nodes as Node[8]\npool leaves as Leaf[2]\nvar list as nodes?\nvar keep as id nodes?\nvar g as u8\nsub bump(var n as Node)\n    n.value = n.value + 1\nend\nsub look(n as Node)\n    g = n.value\nend\nsub make() as nodes\n    return new nodes(1, none)\nend\nsub main()\n    var a = new nodes(1, none)\n    var b = move a\n    bump(a)\nend\n",
  "a maybe-moved owner lent":
    "forward pool nodes\nrecord Node\n    value as u8\n    next as nodes?\nend\nrecord Leaf\n    v as u8\nend\npool nodes as Node[8]\npool leaves as Leaf[2]\nvar list as nodes?\nvar keep as id nodes?\nvar g as u8\nsub bump(var n as Node)\n    n.value = n.value + 1\nend\nsub look(n as Node)\n    g = n.value\nend\nsub make() as nodes\n    return new nodes(1, none)\nend\nsub main()\n    var a = new nodes(1, none)\n    if g = 1\n        var b = move a\n    end\n    bump(a)\nend\n",
  "a lease passed to a var record parameter":
    "forward pool nodes\nrecord Node\n    value as u8\n    next as nodes?\nend\nrecord Leaf\n    v as u8\nend\npool nodes as Node[8]\npool leaves as Leaf[2]\nvar list as nodes?\nvar keep as id nodes?\nvar g as u8\nsub bump(var n as Node)\n    n.value = n.value + 1\nend\nsub look(n as Node)\n    g = n.value\nend\nsub make() as nodes\n    return new nodes(1, none)\nend\nsub main()\n    select list\n    case some(k)\n        bump(k)\n    case none\n    end\nend\n",
  "an owning field lent":
    "forward pool nodes\nrecord Node\n    value as u8\n    next as nodes?\nend\nrecord Leaf\n    v as u8\nend\npool nodes as Node[8]\npool leaves as Leaf[2]\nvar list as nodes?\nvar keep as id nodes?\nvar g as u8\nsub bump(var n as Node)\n    n.value = n.value + 1\nend\nsub look(n as Node)\n    g = n.value\nend\nsub make() as nodes\n    return new nodes(1, none)\nend\nsub main()\n    var a = new nodes(1, none)\n    bump(a.next)\nend\n",
  "a value record parameter's owner moved":
    "forward pool nodes\nrecord Node\n    value as u8\n    next as nodes?\nend\nrecord Leaf\n    v as u8\nend\npool nodes as Node[8]\npool leaves as Leaf[2]\nvar list as nodes?\nvar keep as id nodes?\nvar g as u8\nsub bump(var n as Node)\n    n.value = n.value + 1\nend\nsub look(n as Node)\n    g = n.value\nend\nsub make() as nodes\n    return new nodes(1, none)\nend\nsub f(n as Node)\n    var x = move n.next\nend\nsub main()\nend\n",
  "a number for an owning record parameter":
    "forward pool nodes\nrecord Node\n    value as u8\n    next as nodes?\nend\nrecord Leaf\n    v as u8\nend\npool nodes as Node[8]\npool leaves as Leaf[2]\nvar list as nodes?\nvar keep as id nodes?\nvar g as u8\nsub bump(var n as Node)\n    n.value = n.value + 1\nend\nsub look(n as Node)\n    g = n.value\nend\nsub make() as nodes\n    return new nodes(1, none)\nend\nsub main()\n    bump(5)\nend\n",
  "a number for a record parameter":
    "forward pool nodes\nrecord Node\n    value as u8\n    next as nodes?\nend\nrecord Leaf\n    v as u8\nend\npool nodes as Node[8]\npool leaves as Leaf[2]\nvar list as nodes?\nvar keep as id nodes?\nvar g as u8\nsub bump(var n as Node)\n    n.value = n.value + 1\nend\nsub look(n as Node)\n    g = n.value\nend\nsub make() as nodes\n    return new nodes(1, none)\nend\nsub l(x as Leaf)\nend\nsub main()\n    l(5)\nend\n",
  "a var non-optional owning parameter":
    "forward pool nodes\nrecord Node\n    value as u8\n    next as nodes?\nend\nrecord Box\n    head as nodes?\nend\npool nodes as Node[8]\npool other as Node[2]\nvar list as nodes?\nvar keep as id nodes?\nvar o as other?\nvar g as u8\nsub push(var l as nodes?, v as u8)\n    l = new nodes(v, none)\nend\nsub f(var l as nodes)\nend\nsub main()\nend\n",
  "a var identifier parameter":
    "forward pool nodes\nrecord Node\n    value as u8\n    next as nodes?\nend\nrecord Box\n    head as nodes?\nend\npool nodes as Node[8]\npool other as Node[2]\nvar list as nodes?\nvar keep as id nodes?\nvar o as other?\nvar g as u8\nsub push(var l as nodes?, v as u8)\n    l = new nodes(v, none)\nend\nsub f(var l as id nodes?)\nend\nsub main()\nend\n",
  "a scalar for a slot-holder":
    "forward pool nodes\nrecord Node\n    value as u8\n    next as nodes?\nend\nrecord Box\n    head as nodes?\nend\npool nodes as Node[8]\npool other as Node[2]\nvar list as nodes?\nvar keep as id nodes?\nvar o as other?\nvar g as u8\nsub push(var l as nodes?, v as u8)\n    l = new nodes(v, none)\nend\nsub main()\n    push(g, 1)\nend\n",
  "another pool's owner for a slot-holder":
    "forward pool nodes\nrecord Node\n    value as u8\n    next as nodes?\nend\nrecord Box\n    head as nodes?\nend\npool nodes as Node[8]\npool other as Node[2]\nvar list as nodes?\nvar keep as id nodes?\nvar o as other?\nvar g as u8\nsub push(var l as nodes?, v as u8)\n    l = new nodes(v, none)\nend\nsub main()\n    push(o, 1)\nend\n",
  "a slot-holder through an identifier":
    "forward pool nodes\nrecord Node\n    value as u8\n    next as nodes?\nend\nrecord Box\n    head as nodes?\nend\npool nodes as Node[8]\npool other as Node[2]\nvar list as nodes?\nvar keep as id nodes?\nvar o as other?\nvar g as u8\nsub push(var l as nodes?, v as u8)\n    l = new nodes(v, none)\nend\nsub main()\n    select keep\n    case some(k)\n        push(k.next, 1)\n    case none\n    end\nend\n",
  "a slot-holder through a lease":
    "forward pool nodes\nrecord Node\n    value as u8\n    next as nodes?\nend\nrecord Box\n    head as nodes?\nend\npool nodes as Node[8]\npool other as Node[2]\nvar list as nodes?\nvar keep as id nodes?\nvar o as other?\nvar g as u8\nsub push(var l as nodes?, v as u8)\n    l = new nodes(v, none)\nend\nsub main()\n    select list\n    case some(k)\n        push(k.next, 1)\n    case none\n    end\nend\n",
  "none for a slot-holder":
    "forward pool nodes\nrecord Node\n    value as u8\n    next as nodes?\nend\nrecord Box\n    head as nodes?\nend\npool nodes as Node[8]\npool other as Node[2]\nvar list as nodes?\nvar keep as id nodes?\nvar o as other?\nvar g as u8\nsub push(var l as nodes?, v as u8)\n    l = new nodes(v, none)\nend\nsub main()\n    push(none, 1)\nend\n",
  "a move for a slot-holder":
    "forward pool nodes\nrecord Node\n    value as u8\n    next as nodes?\nend\nrecord Box\n    head as nodes?\nend\npool nodes as Node[8]\npool other as Node[2]\nvar list as nodes?\nvar keep as id nodes?\nvar o as other?\nvar g as u8\nsub push(var l as nodes?, v as u8)\n    l = new nodes(v, none)\nend\nsub main()\n    push(move list, 1)\nend\n",
  "a non-optional owner for a slot-holder":
    "forward pool nodes\nrecord Node\n    value as u8\n    next as nodes?\nend\nrecord Box\n    head as nodes?\nend\npool nodes as Node[8]\npool other as Node[2]\nvar list as nodes?\nvar keep as id nodes?\nvar o as other?\nvar g as u8\nsub push(var l as nodes?, v as u8)\n    l = new nodes(v, none)\nend\nsub main()\n    var a as nodes = new nodes(1, none)\n    push(a, 1)\nend\n",
  "a routine for a slot-holder":
    "forward pool nodes\nrecord Node\n    value as u8\n    next as nodes?\nend\nrecord Box\n    head as nodes?\nend\npool nodes as Node[8]\npool other as Node[2]\nvar list as nodes?\nvar keep as id nodes?\nvar o as other?\nvar g as u8\nsub push(var l as nodes?, v as u8)\n    l = new nodes(v, none)\nend\nsub main()\n    push(main, 1)\nend\n",
  "a slot-holder copied":
    "forward pool nodes\nrecord Node\n    value as u8\n    next as nodes?\nend\npool nodes as Node[8]\nvar list as nodes?\nsub push(var l as nodes?, v as u8)\n    l = new nodes(v, none)\nend\nsub f(var l as nodes?)\n    var a = l\nend\nsub main()\nend\n",
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
