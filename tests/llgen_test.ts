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

// The token kinds (STATE.ASM): a terminal the grammar names is below $40,
// the encoding's limit, and one it may expect below 62, so that DG_TOKEN
// plus it is a syntax diagnostic; no other kind takes one of their
// ordinals. The kinds left free below 62 are the room the grammar has for
// new terminals (native compiler plan §2).
Deno.test("the token kinds leave the grammar room for new terminals", async () => {
  const state = await Deno.readTextFile(
    new URL("../native/compiler/STATE.ASM", import.meta.url),
  );
  const kinds = new Map<string, number>();
  for (const m of state.matchAll(/^(TK_[A-Z]+) EQU {2}(\$?)([0-9A-F]+)\b/gm)) {
    kinds.set(m[1], parseInt(m[3], m[2] ? 16 : 10));
  }
  const named = new Set(Object.values(grammar.terminals));
  const pseudo = ["TK_XEXPR", "TK_XTYPE", "TK_XDECL", "TK_XSTMT", "TK_XUPTO"];
  const used = new Map<number, string>();
  for (const [name, kind] of kinds) {
    if (kind < 0x40 && !named.has(name) && !pseudo.includes(name)) {
      throw new Error(`${name} takes kind ${kind}, which the grammar needs`);
    }
    if (used.has(kind)) throw new Error(`${name} and ${used.get(kind)}`);
    used.set(kind, name);
  }
  for (const name of named) {
    const kind = kinds.get(name)!;
    assertEquals(kind < (name === "TK_SEL" ? 0x40 : 62), true, name);
  }
  const free = [];
  for (let k = 0; k < 62; k += 1) if (!used.has(k)) free.push(k);
  assertEquals(named.size, 47);
  assertEquals(free, [27, 32, 33, 34, 35, 36, 37, 39, 50, 53, 54]);
});
