/** Focused proof of nominal enums through both public toolchains. */
import { assert, assertEquals } from "@std/assert";
import { compile } from "../ref/compile/index.ts";
import { buildBasie } from "../native/compiler/build.ts";
import { messageFile } from "../ref/compile/messages.ts";
import { buildRuntime } from "../tools/helpertable.ts";
import { assembleFile, comBytes, runCom } from "./harness/cpm.ts";

const encoder = new TextEncoder();
const values = Deno.readTextFileSync("tests/conformance/enums/values.bsi");
const parts = Object.fromEntries(
  ["ENUMPA.BSI", "ENUMPB.BSI"].map((
    name,
  ) => [name, Deno.readFileSync(`tests/conformance/enums/${name}`)]),
);
const members = (count: number) =>
  `enum Wide\n${
    Array.from({ length: count }, (_, i) => `    m${i}`).join("\n")
  }\nend\n`;
const many = Array.from(
  { length: 12 },
  (_, i) => `enum E${i}\n    first\n    last\nend\n`,
).join("\n");
function openArraySource(enumCount: number): string {
  const last = enumCount - 1;
  return `${
    Array.from({ length: enumCount }, (_, i) =>
      `enum E${i}\n    first\n    last\nend\n`).join("\n")
  }
sub first(items: E${last}[]): E${last}
    return items[0]
end
sub passOn(items: E${last}[]): E${last}
    return first(items)
end
sub main() fails IoError
    var items: E${last}[1] = [E${last}.last]
    assert passOn(items) = E${last}.last
    try writeText(console, "V\\r\\n")
end
`;
}
const accepted = [
  { name: "ENUMS", source: values, output: "E\r\n" },
  {
    name: "ENOPEN39",
    source: openArraySource(23),
    output: "V\r\n",
  },
  {
    name: "ENUMPRIV",
    source: Deno.readTextFileSync("tests/conformance/enums/private-parts.bsi"),
    output: "P\r\n",
  },
  {
    name: "MANYENUM",
    source: `${many}
var early: E0
var late: E11
sub last(value: E11): E11
    return value
end
sub main() fails IoError
    assert early = E0.first
    assert late = E11.first
    late = last(E11.last)
    assert late = E11.last
    try writeText(console, "M\\r\\n")
end
`,
    output: "M\r\n",
  },
  {
    name: "ENUM256",
    source: `${members(256)}
var value: Wide
var items: Wide[2] = [Wide.m0, Wide.m255]
sub echo(input: Wide): Wide
    return input
end
sub main() fails IoError
    assert value = Wide.m0
    value = echo(items[1])
    assert value = Wide.m255
    var found: boolean
    select value
    case Wide.m255
        found = true
    case else
        found = false
    end
    assert found
    try writeText(console, "W\\r\\n")
end
`,
    output: "W\r\n",
  },
  {
    name: "ENUM48",
    source: `${
      Array.from({ length: 47 }, (_, i) =>
        `enum E${i}\n    first\n    last\nend\nvar v${i}: E${i}\n`).join("\n")
    }
sub main() fails IoError
    assert v0 = E0.first
    assert v46 = E46.first
    v46 = E46.last
    assert v46 = E46.last
    try writeText(console, "T\\r\\n")
end
`,
    output: "T\r\n",
  },
];

const types = `enum Direction
    north
    south
end
enum Colour
    north
    blue
end
`;
const body = (statement: string) =>
  `${types}sub main()\n    var direction: Direction = Direction.north\n    ${statement}\nend\n`;
const refused = [
  ["empty declaration", "enum Empty\nend\nsub main()\nend\n", "empty-enum"],
  [
    "duplicate member",
    "enum E\n    a\n    a\nend\nsub main()\nend\n",
    "duplicate-name",
  ],
  ["257 members", `${members(257)}sub main()\nend\n`, "capacity"],
  [
    "unknown qualified member",
    body("direction = Direction.missing"),
    "undeclared-name",
  ],
  ["bare type is not a value", body("direction = Direction"), "wrong-class"],
  ["unqualified member", body("direction = north"), "undeclared-name"],
  [
    "different enum assignment",
    body("direction = Colour.north"),
    "type-mismatch",
  ],
  ["integer assignment", body("direction = 0"), "type-mismatch"],
  ["enum into integer", body("var number: u8 = direction"), "type-mismatch"],
  [
    "different enum constant",
    `${types}const x: Direction = Colour.north\nsub main()\nend\n`,
    "type-mismatch",
  ],
  [
    "inferred enum constant keeps nominal identity",
    `${types}const alien = Colour.north\nconst bad: Direction = alien\nsub main()\nend\n`,
    "type-mismatch",
  ],
  [
    "different enum parameter",
    `${types}sub take(value: Direction)\nend\nsub main()\n    take(Colour.north)\nend\n`,
    "type-mismatch",
  ],
  [
    "different enum return",
    `${types}sub get(): Direction\n    return Colour.north\nend\nsub main()\nend\n`,
    "type-mismatch",
  ],
  [
    "different enum array element",
    `${types}var x: Direction[1] = [Colour.north]\nsub main()\nend\n`,
    "type-mismatch",
  ],
  [
    "different enum record field",
    `${types}record R\n    d: Direction\nend\nvar x: R = (Colour.north)\nsub main()\nend\n`,
    "type-mismatch",
  ],
  [
    "different enum equality",
    body("var same = direction = Colour.north"),
    "type-mismatch",
  ],
  ["integer equality", body("var same = direction = 0"), "type-mismatch"],
  [
    "ordered comparison",
    body("var less = direction < Direction.south"),
    "type-mismatch",
  ],
  [
    "arithmetic",
    body("direction = direction + Direction.north"),
    "type-mismatch",
  ],
  ["unary plus", body("direction = +direction"), "type-mismatch"],
  ["unary minus", body("direction = -direction"), "type-mismatch"],
  ["bitwise not", body("direction = not direction"), "type-mismatch"],
  [
    "bitwise and",
    body("direction = direction and Direction.north"),
    "type-mismatch",
  ],
  ["bit shift", body("direction = direction shl 1"), "type-mismatch"],
  [
    "enum as constant shift count",
    body("var shifted: u8 = u8(1) shl Direction.north"),
    "type-mismatch",
  ],
  [
    "enum as computed shift count",
    body("var shifted: u8 = u8(1) shl direction"),
    "type-mismatch",
  ],
  [
    "enum: index",
    body("var items: u8[2]\n    var element: u8 = items[direction]"),
    "index-type",
  ],
  [
    "numeric left plus enum right",
    body("var number: u8 = u8(1) + direction"),
    "type-mismatch",
  ],
  [
    "exact shift cannot infer enum",
    body("var count: u8 = 1\n    var result: Direction = 1 shl count"),
    "no-definite-type",
  ],
  [
    "different enum case",
    body("select direction\n    case Colour.north\n    end"),
    "type-mismatch",
  ],
  [
    "integer case",
    body("select direction\n    case 0\n    end"),
    "type-mismatch",
  ],
  [
    "enum case range",
    body(
      "select direction\n    case Direction.north to Direction.south\n    end",
    ),
    "type-mismatch",
  ],
  [
    "pool of enums",
    `${types}pool p: Direction[4]\nsub main()\nend\n`,
    "pool-needs-record",
  ],
  [
    "pool name is not a value",
    `record N\n    a: u8\nend\nvar big: u8[600]\npool nodes: N[4]\nsub main()\n    var y = nodes.x\nend\n`,
    "wrong-class",
  ],
  [
    "computed enum for boolean",
    body("var flag: boolean\n    var same = flag = direction"),
    "type-mismatch",
  ],
  [
    "computed enum after or",
    body("var flag: boolean\n    var either = flag or direction"),
    "type-mismatch",
  ],
  [
    "enum loop bound",
    body("var i: u8\n    for i = 0 to direction\n    end"),
    "type-mismatch",
  ],
  [
    "enum constant loop bound",
    body("var i: u8\n    for i = 0 to Direction.south\n    end"),
    "type-mismatch",
  ],
] as const;

for (const fixture of accepted) {
  Deno.test(`plain enums reference: ${fixture.name} runs`, async () => {
    const result = await compile(`${fixture.name}.BSI`, {
      mainSource: encoder.encode(fixture.source),
      libraryDirs: ["tests/conformance/enums"],
    });
    assert(result.ok, JSON.stringify(result));
    const execution = runCom(result.com, { maxSteps: 5_000_000 });
    assertEquals(execution.output, fixture.output);
    assertEquals(execution.returnCode, 0);
  });
}

for (const [name, source, code] of refused) {
  Deno.test(`plain enums reference: refuses ${name}`, async () => {
    const result = await compile("REFUSED.BSI", {
      mainSource: encoder.encode(source),
    });
    assert(!result.ok && "diagnostics" in result, JSON.stringify(result));
    assertEquals(result.diagnostics[0].code, code);
  });
}

// IoError, predeclared (D54), takes the first of the 48 shared slots.
Deno.test("plain enums native: 48 declared types exceed the shared descriptor capacity", async () => {
  const { compiler, runtime } = await native();
  const source = encoder.encode(
    `${
      Array.from({ length: 48 }, (_, i) => `enum E${i}\n    first\nend\n`).join(
        "\n",
      )
    }sub main()\nend\n`,
  );
  // The reference has no native descriptor-table limit. This is a capacity
  // diagnostic on a valid program, rather than rejection of enum syntax.
  const reference = await compile("ENUM49.BSI", { mainSource: source });
  assert(reference.ok, JSON.stringify(reference));
  const compiled = runCom(compiler.com, {
    tail: "ENUM49 [C]",
    files: {
      "ENUM49.BSI": source,
      "BASIE.OVL": compiler.ovl,
      "BASIE.MSG": messageFile(),
      "CPM22.BRL": runtime,
    },
    maxSteps: 100_000_000,
  });
  assertMatchCapacity(compiled.output);
  assertEquals(compiled.disk.has("ENUM49.COM"), false);
});

function assertMatchCapacity(output: string) {
  assert(/^ENUM49\.BSI \d+:\d+: 190: .*\r\n$/.test(output), output);
}

Deno.test("plain enums reference: open-array enum ID40 runs", async () => {
  const reference = await compile("ENOPEN40.BSI", {
    mainSource: encoder.encode(openArraySource(24)),
  });
  assert(reference.ok, JSON.stringify(reference));
  assertEquals(runCom(reference.com, { maxSteps: 5_000_000 }).output, "V\r\n");
});

Deno.test("plain enums native: open-array enum ID40 reaches encoding capacity", async () => {
  const { compiler, runtime } = await native();
  const source = encoder.encode(openArraySource(24));
  const reference = await compile("ENOPEN40.BSI", { mainSource: source });
  assert(reference.ok, JSON.stringify(reference));
  const compiled = runCom(compiler.com, {
    tail: "ENOPEN40 [C]",
    files: {
      "ENOPEN40.BSI": source,
      "BASIE.OVL": compiler.ovl,
      "BASIE.MSG": messageFile(),
      "CPM22.BRL": runtime,
    },
    maxSteps: 100_000_000,
  });
  assert(
    /^ENOPEN40\.BSI \d+:\d+: 190: .*\r\n$/.test(compiled.output),
    compiled.output,
  );
  assertEquals(compiled.disk.has("ENOPEN40.COM"), false);
});

// Build lazily so --filter 'plain enums reference' exercises the reference
// before the native implementation exists, without assembling the native one.
let nativeBuild: ReturnType<typeof buildNative> | undefined;
async function buildNative() {
  const compiler = await buildBasie();
  const runtime = (await buildRuntime()).file;
  const linker = comBytes(await assembleFile("native/linker/BLINK.ASM"));
  return { compiler, runtime, linker };
}
function native() {
  return nativeBuild ??= buildNative();
}

for (const fixture of accepted) {
  Deno.test(`plain enums native: ${fixture.name} compiles, links and runs`, async () => {
    const { compiler, runtime, linker } = await native();
    const compiled = runCom(compiler.com, {
      tail: `${fixture.name} [C,M]`,
      files: {
        ...parts,
        [`${fixture.name}.BSI`]: encoder.encode(fixture.source),
        "BASIE.OVL": compiler.ovl,
        "BASIE.MSG": messageFile(),
        "CPM22.BRL": runtime,
      },
      maxSteps: 100_000_000,
    });
    assertEquals(compiled.output, "");
    const directory = compiled.disk.get(`${fixture.name}.$DR`);
    assert(directory, "native compiler did not write the object directory");
    const reference = await compile(`${fixture.name}.BSI`, {
      mainSource: encoder.encode(fixture.source),
      libraryDirs: ["tests/conformance/enums"],
      stamp: directory[6] | (directory[7] << 8),
    });
    assert(reference.ok, JSON.stringify(reference));
    for (
      const [suffix, expected] of Object.entries({
        "$DR": reference.objects.directory,
        "$BY": reference.objects.bytes,
        "$LN": reference.objects.lines,
        "$NM": reference.objects.names,
      })
    ) {
      const actual = compiled.disk.get(`${fixture.name}.${suffix}`);
      assert(actual, `${suffix} was not written`);
      assertEquals(actual.subarray(0, expected.length), expected, suffix);
      assert(actual.length - expected.length < 128, `${suffix} spare record`);
      assert(actual.subarray(expected.length).every((byte) => byte === 0));
    }
    const linked = runCom(linker, {
      tail: fixture.name,
      files: Object.fromEntries([
        ...compiled.disk,
        ["CPM22.BRL", runtime],
        ["BASIE.MSG", messageFile()],
      ]),
      maxSteps: 100_000_000,
    });
    assertEquals(linked.output, "");
    const executable = linked.disk.get(`${fixture.name}.COM`);
    assert(executable, "BLINK did not write the executable");
    const execution = runCom(executable, { maxSteps: 5_000_000 });
    assertEquals(execution.output, fixture.output);
    assertEquals(execution.returnCode, 0);
  });
}

for (const [name, source, code] of refused) {
  Deno.test(`plain enums native: refuses ${name}`, async () => {
    const { compiler, runtime } = await native();
    const reference = await compile("REFUSED.BSI", {
      mainSource: encoder.encode(source),
    });
    assert(!reference.ok && "diagnostics" in reference);
    const expected = reference.diagnostics[0];
    assertEquals(expected.code, code);
    const compiled = runCom(compiler.com, {
      tail: "REFUSED [C]",
      files: {
        "REFUSED.BSI": encoder.encode(source),
        "BASIE.OVL": compiler.ovl,
        "BASIE.MSG": messageFile(),
        "CPM22.BRL": runtime,
      },
      maxSteps: 100_000_000,
    });
    const diagnostic = compiled.output.match(
      /^(\S+) (\d+):(\d+): (\d+): (.*)\r\n$/,
    );
    assert(diagnostic, JSON.stringify(compiled.output));
    assertEquals({
      part: diagnostic[1],
      line: Number(diagnostic[2]),
      column: Number(diagnostic[3]),
      number: Number(diagnostic[4]),
    }, {
      part: expected.part,
      line: expected.line,
      column: expected.column,
      number: expected.number,
    });
    assertEquals(compiled.disk.has("REFUSED.COM"), false);
  });
}
