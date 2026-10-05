/**
 * The native compiler's grammar tables are generated: GRAMMAR.ASM is what
 * tools/llgen.ts makes of native/compiler/grammar/grammar.json, and the
 * grammar is LL(1) (roadmap step 67).
 */
import { assertEquals } from "@std/assert";
import {
  buildTables,
  GRAMMAR_ASM,
  GRAMMAR_JSON,
  type GrammarFile,
  grammarSource,
} from "../tools/llgen.ts";

const grammar = JSON.parse(
  await Deno.readTextFile(GRAMMAR_JSON),
) as GrammarFile;

Deno.test("GRAMMAR.ASM is generated from the grammar: run deno task grammar", async () => {
  assertEquals(await Deno.readTextFile(GRAMMAR_ASM), grammarSource(grammar));
});

Deno.test("the grammar's terminals fit the 64 token kinds of the encoding", () => {
  const t = buildTables(grammar);
  assertEquals(Object.keys(grammar.terminals).length <= 64, true);
  assertEquals(t.rows.length <= 64, true);
});
