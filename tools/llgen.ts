/**
 * Generate the native compiler's LL(1) tables, native/compiler/GRAMMAR.ASM,
 * from its grammar, native/compiler/grammar/grammar.json (roadmap step 67;
 * native compiler plan §2, "Grammar encoding").
 *
 * The JSON holds the productions, with `a:` semantic actions and `x:`
 * islands (hand-written parsers) among the grammar symbols; the island's
 * FIRST sets (`externals`); the token kind of each terminal; the
 * diagnostic of each nonterminal; the routine of each action, in ordinal
 * order; and the equates other modules read. The generator computes the
 * FIRST and FOLLOW sets, the prediction rows, which must be LL(1), and
 * every offset, so nothing is counted by hand: ATOM takes a forward
 * reference only as one symbol and a small addend, so the directories hold
 * numbers, each with a comment naming the difference it stands for.
 *
 * Numbering. Nonterminals are numbered in order of their first production,
 * productions by their bodies: productions with the same body share one
 * number (every empty production is one), in order of the body's first
 * appearance. Actions are numbered in the order of `actions`.
 *
 * Usage: deno task grammar        write GRAMMAR.ASM
 *        deno task grammar --check  fail if GRAMMAR.ASM is not current
 */

type Production = { lhs: string; rhs: string[] };

export type GrammarFile = {
  start: string;
  terminals: Record<string, string>;
  diagnosticCodes: Record<string, string>;
  diagnostics: Record<string, string>;
  actions: Record<string, string>;
  equates: Record<string, string>;
  externals: Record<string, string[]>;
  productions: Production[];
};

const ROOT = new URL("../", import.meta.url).pathname;
export const GRAMMAR_JSON = `${ROOT}native/compiler/grammar/grammar.json`;
export const GRAMMAR_ASM = `${ROOT}native/compiler/GRAMMAR.ASM`;

const isAction = (s: string) => s.startsWith("a:") || s.startsWith("x:");
const actionName = (s: string) => s.slice(2);

/** The tables, as numbers, before they are written as source. */
export type Tables = {
  rows: string[];
  bodies: string[][];
  /** Production number of each production of the JSON, in order. */
  numbers: number[];
  /** Per row: its alternatives, a production number and predicting kinds. */
  predict: { prod: number; tokens: string[] }[][];
  split: number;
  actions: string[];
};

/** Build the tables, checking that the grammar is LL(1). */
export function buildTables(g: GrammarFile): Tables {
  const rows: string[] = [];
  for (const p of g.productions) if (!rows.includes(p.lhs)) rows.push(p.lhs);
  const actions = Object.keys(g.actions);
  const isRow = (s: string) => rows.includes(s);
  for (const p of g.productions) {
    for (const s of p.rhs) {
      if (isAction(s)) {
        if (!actions.includes(actionName(s))) {
          throw new Error(`${p.lhs}: no routine for the action ${s}`);
        }
        if (s.startsWith("x:") && !g.externals[actionName(s)]) {
          throw new Error(`${p.lhs}: no FIRST set for the island ${s}`);
        }
      } else if (!isRow(s) && !g.terminals[s]) {
        throw new Error(`${p.lhs}: ${s} is neither a nonterminal nor a token`);
      }
    }
  }
  // FIRST of a symbol sequence: tokens, and whether it can derive nothing.
  const first = new Map<string, Set<string>>(rows.map((r) => [r, new Set()]));
  const nullable = new Set<string>();
  const seqFirst = (seq: string[]): { set: Set<string>; empty: boolean } => {
    const set = new Set<string>();
    for (const s of seq) {
      if (s.startsWith("a:")) continue;
      if (s.startsWith("x:")) {
        for (const t of g.externals[actionName(s)]) set.add(t);
        return { set, empty: false };
      }
      if (!isRow(s)) {
        set.add(s);
        return { set, empty: false };
      }
      for (const t of first.get(s)!) set.add(t);
      if (!nullable.has(s)) return { set, empty: false };
    }
    return { set, empty: true };
  };
  for (let changed = true; changed;) {
    changed = false;
    for (const p of g.productions) {
      const f = seqFirst(p.rhs);
      const into = first.get(p.lhs)!;
      for (const t of f.set) {
        if (!into.has(t)) {
          into.add(t);
          changed = true;
        }
      }
      if (f.empty && !nullable.has(p.lhs)) {
        nullable.add(p.lhs);
        changed = true;
      }
    }
  }
  const follow = new Map<string, Set<string>>(rows.map((r) => [r, new Set()]));
  for (let changed = true; changed;) {
    changed = false;
    for (const p of g.productions) {
      p.rhs.forEach((s, i) => {
        if (!isRow(s)) return;
        const rest = seqFirst(p.rhs.slice(i + 1));
        const into = follow.get(s)!;
        const add = rest.empty
          ? [...rest.set, ...follow.get(p.lhs)!]
          : [...rest.set];
        for (const t of add) {
          if (!into.has(t)) {
            into.add(t);
            changed = true;
          }
        }
      });
    }
  }
  // Production numbers, shared by equal bodies.
  const bodies: string[][] = [];
  const numbers = g.productions.map((p) => {
    const key = JSON.stringify(p.rhs);
    let n = bodies.findIndex((b) => JSON.stringify(b) === key);
    if (n < 0) {
      n = bodies.length;
      bodies.push(p.rhs);
    }
    return n;
  });
  if (bodies.length > 128) throw new Error("more than 128 productions");
  const predict = rows.map((row) => {
    const alts: { prod: number; tokens: string[] }[] = [];
    const seen = new Set<string>();
    g.productions.forEach((p, i) => {
      if (p.lhs !== row) return;
      const f = seqFirst(p.rhs);
      const set = new Set(f.set);
      if (f.empty) { for (const t of follow.get(row)!) set.add(t); }
      const tokens = [...set].sort();
      for (const t of tokens) {
        if (seen.has(t)) {
          throw new Error(`${row}: ${t} predicts two productions (not LL(1))`);
        }
        seen.add(t);
      }
      if (tokens.length === 0) {
        throw new Error(`${row}: an unreachable production`);
      }
      alts.push({ prod: numbers[i], tokens });
    });
    return alts;
  });
  // Split the bodies so that each half's offsets fit a byte.
  let split = bodies.length;
  let offset = 0;
  for (let n = 0; n < bodies.length; n += 1) {
    if (offset + bodies[n].length > 255) {
      split = n;
      break;
    }
    offset += bodies[n].length;
  }
  const high = bodies.slice(split).reduce((a, b) => a + b.length, 0);
  if (high > 255) throw new Error("the production bodies need a third half");
  return { rows, bodies, numbers, predict, split, actions };
}

const pad = (s: string, col: number) =>
  s.length >= col ? s + " " : s + " ".repeat(col - s.length);
const line = (code: string, comment: string) =>
  pad(`    ${code}`, 35) + `; ${comment}`;

/** The source of GRAMMAR.ASM. */
export function grammarSource(g: GrammarFile): string {
  const t = buildTables(g);
  const out: string[] = [];
  const kind = (s: string) => g.terminals[s];
  const symbol = (s: string) => {
    if (isAction(s)) {
      return `$${(0x80 + t.actions.indexOf(actionName(s))).toString(16)}`;
    }
    const r = t.rows.indexOf(s);
    if (r >= 0) return `$${(0x40 + r).toString(16)}`;
    return kind(s);
  };
  const rowOf = (n: number) =>
    t.rows[
      g.productions[t.numbers.indexOf(n)]?.lhs === undefined
        ? 0
        : t.rows.indexOf(g.productions[t.numbers.indexOf(n)].lhs)
    ];
  if (t.rows.length > 64) throw new Error("more than 64 nonterminals");
  if (t.actions.length > 127) throw new Error("more than 127 actions");
  out.push(HEADER.trim());
  out.push("");
  out.push(
    pad(`GR_ROW_N EQU  ${t.rows.length}`, 35) + "; Nonterminals, one row each.",
  );
  out.push(pad(`GR_ALT_N EQU  ${t.bodies.length}`, 35) + "; Productions.");
  out.push(
    pad(`GR_SPLIT EQU  ${t.split}`, 35) +
      "; First production in the high directory.",
  );
  out.push(
    pad(`GR_ACT_N EQU  ${t.actions.length}`, 35) + "; Actions in GR_ACTX.",
  );
  out.push(
    pad(`GR_START EQU  $40`, 35) + `; Start symbol: ${g.start}, row 0.`,
  );
  if (t.rows[0] !== g.start) throw new Error("the start symbol must be row 0");
  for (const [name, target] of Object.entries(g.equates)) {
    const r = t.rows.indexOf(target);
    if (r >= 0) {
      out.push(
        pad(`${name} EQU  $40+${r}`, 35) +
          `; The ${target} nonterminal, row ${r}.`,
      );
    } else {
      const a = t.actions.indexOf(target);
      if (a < 0) throw new Error(`equate ${name}: no row or action ${target}`);
      out.push(
        pad(`${name} EQU  ${a}`, 35) +
          `; Action ordinal of ${target} (${g.actions[target]}).`,
      );
    }
  }
  out.push("");
  out.push(
    "; Row directory: offset from GR_ROWS, diagnostic when nothing is predicted.",
  );
  out.push("");
  out.push("GR_ROWX:");
  const rowBytes: string[][] = t.predict.map((alts) => {
    const b: string[] = [];
    alts.forEach((a, i) => {
      b.push(i === alts.length - 1 ? `${a.prod}+$80` : `${a.prod}`);
      a.tokens.forEach((tok, j) =>
        b.push(j === a.tokens.length - 1 ? `${kind(tok)}+$80` : kind(tok))
      );
    });
    return b;
  });
  let at = 0;
  t.rows.forEach((row, r) => {
    const diag = g.diagnosticCodes[g.diagnostics[row]];
    if (!diag) throw new Error(`${row}: no diagnostic`);
    out.push(line(`DB   ${at},${diag}`, `GR_ROW${r}-GR_ROWS; ${row}`));
    at += rowBytes[r].length;
  });
  if (at > 256) {
    throw new Error(`the rows take ${at} bytes, more than a byte's offsets`);
  }
  out.push(pad("GR_ROWXE:", 35) + "; End of the row directory.");
  out.push("");
  out.push(
    "; Rows: alternatives of production byte and predicting token kinds.",
  );
  out.push("");
  out.push(pad("GR_ROWS:", 35) + "; Base of the row offsets.");
  t.rows.forEach((row, r) => {
    out.push(pad(`GR_ROW${r}:`, 35) + `; ${row}`);
    for (const b of rowBytes[r]) out.push(`    DB   ${b}`);
  });
  out.push(pad("GR_ROW_E:", 35) + "; End of the rows.");
  out.push("");
  out.push(
    "; Production directories: body offsets, each list closed by an end entry.",
  );
  out.push("");
  out.push("GR_ALTX:");
  let off = 0;
  for (let n = 0; n < t.split; n += 1) {
    out.push(line(`DB   ${off}`, `GR_ALT${n}-GR_ALTS; ${rowOf(n)}`));
    off += t.bodies[n].length;
  }
  out.push(line(`DB   ${off}`, "GR_ALTHI-GR_ALTS"));
  out.push("GR_ALTXH:");
  off = 0;
  for (let n = t.split; n < t.bodies.length; n += 1) {
    out.push(line(`DB   ${off}`, `GR_ALT${n}-GR_ALTHI; ${rowOf(n)}`));
    off += t.bodies[n].length;
  }
  out.push(line(`DB   ${off}`, "GR_ALT_E-GR_ALTHI"));
  out.push(pad("GR_ALTXE:", 35) + "; End of the production directories.");
  out.push("");
  out.push("; Production bodies, each right side stored right to left.");
  out.push("");
  out.push(pad("GR_ALTS:", 35) + "; Base of the low productions' offsets.");
  t.bodies.forEach((body, n) => {
    if (n === t.split) {
      out.push(
        pad("GR_ALTHI:", 35) + "; Base of the high productions' offsets.",
      );
    }
    out.push(pad(`GR_ALT${n}:`, 35) + `; ${rowOf(n)}`);
    if (body.length > 0) {
      out.push(`    DB   ${[...body].reverse().map(symbol).join(",")}`);
    }
  });
  if (t.split === t.bodies.length) {
    out.push(pad("GR_ALTHI:", 35) + "; Base of the high productions' offsets.");
  }
  out.push(pad("GR_ALT_E:", 35) + "; End of the production bodies.");
  out.push("");
  out.push("; Action directory: the routine for each action ordinal.");
  out.push("");
  out.push("GR_ACTX:");
  const kinds = new Map<string, string>();
  for (const p of g.productions) {
    for (const s of p.rhs) if (isAction(s)) kinds.set(actionName(s), s);
  }
  for (const a of t.actions) {
    out.push(line(`DW   ${g.actions[a]}`, kinds.get(a) ?? `a:${a}`));
  }
  out.push(pad("GR_ACTXE:", 35) + "; End of the action directory.");
  out.push("");
  out.push(pad("GR_TAB_E:", 35) + "; End of the generated tables (marker).");
  out.push("");
  out.push(pad("GR_END:", 35) + "; End of the grammar tables (marker).");
  return out.join("\n") + "\n";
}

const HEADER = `
;==========================================================================
;  Grammar tables
;==========================================================================
;
;  The LL(1) tables that LL1.ASM interprets, generated by tools/llgen.ts
;  from grammar/grammar.json (deno task grammar); tests/llgen_test.ts
;  checks that this file is current. Edit the grammar, not this file.
;
;  Grammar symbols are bytes: $00..$3F a token kind, $40..$7F nonterminal
;  (row) n-$40, $80..$FE action n-$80 (LL1.ASM).
;
;  GR_ROWX   two bytes per nonterminal: the offset of its row from GR_ROWS,
;            then the diagnostic raised when no production of the row is
;            predicted by the next token.
;  GR_ROWS   the rows. A row is a list of alternatives: a production byte,
;            then the token kinds that predict it. Bit 7 marks the last
;            token of each alternative and, on the production byte, the
;            row's last alternative.
;  GR_ALTX   one byte per production below GR_SPLIT: the offset of its body
;            from GR_ALTS, then one entry more that ends the last body. The
;            length of a body is the next entry minus its own.
;  GR_ALTXH  the same for productions GR_SPLIT and up, renumbered from zero,
;            with bodies from GR_ALTHI. Splitting the bodies in two keeps
;            every offset within a byte.
;  GR_ALTS   production bodies, each stored right to left so that the engine
;            pushes it in one copy and its leftmost symbol ends on top.
;            Productions with the same body share it and its number.
;  GR_ACTX   one word per action: the routine LL1.ASM calls, with the
;            action ordinal in A.
;
;  Names. GR_ROWn is row n (nonterminal $40+n) and GR_ALTn production n.
;  An X suffix names a directory (GR_ROWX, GR_ALTX, GR_ALTXH, GR_ACTX), an S
;  the base its offsets count from (GR_ROWS, GR_ALTS; GR_ALTHI for the high
;  half), _N a count, and _E or XE an end. The directories hold numbers, not
;  label differences, because ATOM takes a forward reference only as one
;  symbol with a small addend; each entry's comment gives the difference it
;  stands for and the nonterminal. The row and body labels are kept for
;  those comments and for listings; nothing references them.
;
;  Comments on GR_ACTX name the grammar's action: a: is a semantic action,
;  x: an island where a hand-written parser (expressions, initializers,
;  steps, name statements) takes over. A routine that serves several
;  actions derives what differs from the ordinal (the equates below).
`;

if (import.meta.main) {
  const g = JSON.parse(await Deno.readTextFile(GRAMMAR_JSON)) as GrammarFile;
  const source = grammarSource(g);
  if (Deno.args.includes("--check")) {
    const now = await Deno.readTextFile(GRAMMAR_ASM);
    if (now !== source) {
      console.error("GRAMMAR.ASM is not current: run deno task grammar");
      Deno.exit(1);
    }
  } else {
    await Deno.writeTextFile(GRAMMAR_ASM, source);
    const t = buildTables(g);
    console.log(
      `GRAMMAR.ASM: ${t.rows.length} rows, ${t.bodies.length} productions ` +
        `(split at ${t.split}), ${t.actions.length} actions, ` +
        `${Object.keys(g.terminals).length} terminals`,
    );
  }
}
