import { assertEquals, assertThrows } from "@std/assert";
import {
  LexError,
  parseF32,
  type Token,
  tokenize,
} from "../ref/compile/lexer.ts";

const enc = (s: string) => new TextEncoder().encode(s);

/** A compact rendering: NAME, keywords upper-case, NUMBER(n), and so on. */
function show(source: string): string {
  return tokenize(enc(source)).map((t: Token) => {
    switch (t.kind) {
      case "name":
        return "NAME";
      case "keyword":
        return t.text.toUpperCase();
      case "number":
        return `NUMBER(${t.value})`;
      case "float":
        return `FLOAT(${t.value})`;
      case "character":
        return `CHARACTER(${t.value})`;
      case "string":
        return `STRING(${Array.from(t.bytes).join(",")})`;
      case "punct":
        return t.text;
      case "newline":
        return "NEWLINE";
      case "eof":
        return "EOF";
    }
  }).join(" ");
}

function error(source: string): { code: string; line: number; column: number } {
  const e = assertThrows(() => tokenize(enc(source)), LexError);
  return { code: e.code, line: e.position.line, column: e.position.column };
}

Deno.test("the token examples of spec §3.11", () => {
  const ok: [string, string][] = [
    ["player_2", "NAME NEWLINE EOF"],
    ["elseif", "ELSEIF NEWLINE EOF"],
    ["ELSEIF", "NAME NEWLINE EOF"],
    ["elseifReady", "NAME NEWLINE EOF"],
    ["else if", "ELSE IF NEWLINE EOF"],
    ["42", "NUMBER(42) NEWLINE EOF"],
    ["-42", "- NUMBER(42) NEWLINE EOF"],
    ["$2a", "NUMBER(42) NEWLINE EOF"],
    ["%00101010", "NUMBER(42) NEWLINE EOF"],
    ["'A'", "CHARACTER(65) NEWLINE EOF"],
    ["'\\x41'", "CHARACTER(65) NEWLINE EOF"],
    ['""', "STRING() NEWLINE EOF"],
    ['"A\\nB"', "STRING(65,10,66) NEWLINE EOF"],
    ["a <= b", "NAME <= NAME NEWLINE EOF"],
    ["a / / b", "NAME / / NAME NEWLINE EOF"],
    ["a // note\n", "NAME NEWLINE EOF"],
    ["check(\n    table[index]\n)", "NAME ( NAME [ NAME ] ) NEWLINE EOF"],
  ];
  for (const [source, want] of ok) assertEquals(show(source), want, source);
  const bad: [string, string][] = [
    ["_player", "bad-character"],
    ["0x2a", "malformed-number"],
    ["$100000000", "malformed-number"],
    ["%1" + "0".repeat(32), "malformed-number"],
    ["''", "empty-character"],
    ['"A\\q"', "bad-escape"],
    ["a != b", "bad-character"],
    ["a; b", "bad-character"],
  ];
  for (const [source, code] of bad) {
    assertEquals(error(source).code, code, source);
  }
});

Deno.test("logical newlines: blank lines, comments and delimiters", () => {
  assertEquals(
    show("a\n\n// only a comment\n\nb\r\n"),
    "NAME NEWLINE NAME NEWLINE EOF",
  );
  assertEquals(show(""), "EOF");
  assertEquals(show("// just a comment"), "EOF");
  assertEquals(
    show("total = (first +\n    second)"),
    "NAME = ( NAME + NAME ) NEWLINE EOF",
  );
  assertEquals(
    show("total = first +\nsecond"),
    "NAME = NAME + NEWLINE NAME NEWLINE EOF",
  );
  // A non-final part ends with its boundary NEWLINE and no EOF.
  const part = tokenize(enc("x"), 1, false);
  assertEquals(part.map((t) => t.kind), ["name", "newline"]);
  assertEquals(part[0].part, 1);
});

Deno.test("positions count bytes; CRLF advances one line", () => {
  const t = tokenize(enc("a\r\n\tbb  c"));
  assertEquals(t.map((x) => [x.offset, x.line, x.column]), [
    [0, 1, 1],
    [1, 1, 2],
    [4, 2, 2],
    [8, 2, 6],
    [9, 2, 7],
    [9, 2, 7],
  ]);
  assertEquals(t[1].end, 3);
  assertEquals(error("a\rb"), { code: "lone-cr", line: 1, column: 2 });
  assertEquals(error("x = 1\n  y\x7f"), {
    code: "bad-byte",
    line: 2,
    column: 4,
  });
});

Deno.test("integer literal ranges", () => {
  assertEquals(
    show("4294967295 $FFFFFFFF"),
    "NUMBER(4294967295) NUMBER(4294967295) NEWLINE EOF",
  );
  assertEquals(error("4294967296").code, "malformed-number");
  assertEquals(error("$").code, "malformed-number");
  assertEquals(error("%102").code, "malformed-number");
  assertEquals(error("12u8").code, "malformed-number");
  assertEquals(error("1_000").code, "malformed-number");
  assertEquals(show("$ff.x"), "NUMBER(255) . NAME NEWLINE EOF");
});

Deno.test("floating-point literals round to the nearest f32", () => {
  assertEquals(
    show("1.5 0.25 1e3 2.5e-3"),
    `FLOAT(1.5) FLOAT(0.25) FLOAT(1000) FLOAT(${
      Math.fround(0.0025)
    }) NEWLINE EOF`,
  );
  assertEquals(error("var half: f32 = 5.").column, 17);
  assertEquals(show(".5"), ". NUMBER(5) NEWLINE EOF"); // the grammar rejects it
  assertEquals(error("1.5f").code, "malformed-number");
  assertEquals(error("1e").code, "malformed-number");
  assertEquals(error("1e39").code, "malformed-number");
  // Ties to even: 2^24 + 1 lies halfway between two f32 values.
  assertEquals(parseF32("16777217"), 16777216);
  assertEquals(parseF32("16777219"), 16777220);
  assertEquals(parseF32("0.1"), Math.fround(0.1));
  assertEquals(parseF32("3.4028235e38"), 3.4028234663852886e38);
  assertEquals(parseF32("3.40282356e38"), 3.4028234663852886e38); // just below halfway
  assertEquals(parseF32("3.4028236e38"), undefined); // just above: rounds to 2^128
  assertEquals(parseF32("3.5e38"), undefined);
  assertEquals(parseF32("1e-38"), 0); // below 2^-126, flushed
  assertEquals(parseF32("1.2e-38"), Math.fround(1.2e-38));
  assertEquals(parseF32("0.0"), 0);
});

Deno.test("literal errors", () => {
  assertEquals(error("'ab'").code, "long-character");
  assertEquals(error('"abc\n"').code, "unterminated-literal");
  assertEquals(error('"abc').code, "unterminated-literal");
  assertEquals(error('"\\x4"').code, "bad-escape");
  assertEquals(show(`'"' "'"`), "CHARACTER(34) STRING(39) NEWLINE EOF");
});

Deno.test("delimiter errors", () => {
  assertEquals(error("a)").code, "unmatched-delimiter");
  assertEquals(error("(a]").code, "mismatched-delimiter");
  assertEquals(error("f(a,\n b").code, "open-delimiter");
  assertEquals(error("f(a,\n b").column, 2);
});
