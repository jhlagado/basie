import { assertEquals } from "@std/assert";
import {
  chapter3Words,
  checkGrammar,
  grammarFromSpec,
  parseGrammar,
  tabledChoices,
} from "../tools/grammar.ts";
import { KEYWORDS, PUNCTUATION } from "../ref/compile/lexer.ts";

const chapter17 = await Deno.readTextFile("spec/17-complete-grammar.md");
const chapter3 = await Deno.readTextFile(
  "spec/03-source-text-and-lexical-rules.md",
);
const report = checkGrammar(await grammarFromSpec(), "compilation");

Deno.test("the grammar is complete, reachable, productive and not left-recursive", () => {
  assertEquals(report.undefined, []);
  assertEquals(report.unreachable, []);
  assertEquals(report.unproductive, []);
  assertEquals(report.leftRecursive, []);
});

Deno.test("its only LL(1) conflicts are the choices tabled in 17.4", () => {
  assertEquals(report.conflicts, tabledChoices(chapter17));
});

Deno.test("its keywords are Chapter 3's words and the lexer's", () => {
  const { reserved, contextual } = chapter3Words(chapter3);
  const words = [...report.terminals].filter((t) => /^[a-z]/.test(t)).sort();
  assertEquals(words, [...reserved, ...contextual].sort());
  assertEquals([...KEYWORDS].sort(), reserved);
});

Deno.test("its punctuation is Chapter 3's and the lexer's", () => {
  const table = chapter3.slice(
    chapter3.indexOf("## 3.8"),
    chapter3.indexOf("## 3.9"),
  );
  const listed = new Set<string>();
  for (const row of table.split("\n").filter((l) => l.startsWith("| `"))) {
    for (const m of row.split("|")[1].matchAll(/`([^`]+)`/g)) listed.add(m[1]);
  }
  const used = [...report.terminals].filter((t) => /^[^\w]/.test(t)).sort();
  assertEquals(used, [...listed].sort());
  assertEquals([...PUNCTUATION].sort(), [...listed].sort());
});

Deno.test("the checker finds what it is meant to find", () => {
  const bad = checkGrammar(
    parseGrammar(`
      start ::= a | b | "x" start | missing
      a ::= a "y" | "z"
      b ::= "z" "w"
      lost ::= "q"
      never ::= never "r"
    `),
    "start",
  );
  assertEquals(bad.undefined, ["missing"]);
  assertEquals(bad.unreachable, ["lost", "never"]);
  assertEquals(
    bad.unproductive,
    ["missing", "never"].filter((n) => n !== "missing"),
  );
  assertEquals(bad.leftRecursive, ["a", "never"]);
  assertEquals(bad.conflicts.includes('start: "z"'), true);
});
