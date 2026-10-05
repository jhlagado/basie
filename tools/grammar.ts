/**
 * The grammar check (roadmap step 22; spec §17.4). It reads the syntactic
 * grammar from spec/17-complete-grammar.md §17.2, so the specification is the
 * only copy, and checks:
 *
 * - every nonterminal used is defined, and every one defined is reachable
 *   from `compilation` and productive;
 * - no rule is left-recursive, directly or through nullable prefixes;
 * - the LL(1) conflicts (FIRST/FIRST and FIRST/FOLLOW) are exactly the
 *   resolved choices tabled in §17.4, each with its resolution;
 * - the grammar's keywords and punctuation are the reserved words,
 *   contextual words and punctuation of Chapter 3, and the lexer's.
 *
 * Usage: deno run --allow-read tools/grammar.ts
 */

type Item =
  | { kind: "t"; text: string } // a terminal: keyword, punctuation or token
  | { kind: "n"; name: string }
  | { kind: "opt" | "rep" | "group"; alts: Item[][] };

export type Grammar = Map<string, Item[][]>;

const ROOT = new URL("../", import.meta.url).pathname;

/** The fenced `text` blocks of a section of a markdown chapter. */
function blocks(doc: string, heading: string): string[] {
  const start = doc.indexOf(heading);
  if (start < 0) throw new Error(`no section ${heading}`);
  const rest = doc.slice(start + heading.length);
  const end = rest.search(/\n## /);
  const section = end < 0 ? rest : rest.slice(0, end);
  return [...section.matchAll(/```text\n([\s\S]*?)```/g)].map((m) => m[1]);
}

/** Parse EBNF text: `name ::= alternatives`, as Chapter 17 writes it. */
export function parseGrammar(text: string): Grammar {
  const tokens: string[] = [];
  const re =
    /\s*("(?:[^"\\]|\\.)*"|'(?:[^'\\]|\\.)*'|::=|[{}[\]()|]|[A-Za-z][\w-]*)/y;
  let at = 0;
  while (at < text.length) {
    re.lastIndex = at;
    const m = re.exec(text);
    if (!m) {
      if (/^\s*$/.test(text.slice(at))) break;
      throw new Error(`grammar text: unexpected ${text.slice(at, at + 20)}`);
    }
    tokens.push(m[1]);
    at = re.lastIndex;
  }
  const grammar: Grammar = new Map();
  let i = 0;
  const isRuleStart = (k: number) => tokens[k + 1] === "::=";
  const parseAlts = (): Item[][] => {
    const alts: Item[][] = [parseSeq()];
    while (tokens[i] === "|") {
      i += 1;
      alts.push(parseSeq());
    }
    return alts;
  };
  const parseSeq = (): Item[] => {
    const seq: Item[] = [];
    while (i < tokens.length && !isRuleStart(i)) {
      const t = tokens[i];
      if (t === "|" || t === ")" || t === "]" || t === "}") break;
      i += 1;
      if (t === "(" || t === "[" || t === "{") {
        const alts = parseAlts();
        const close = { "(": ")", "[": "]", "{": "}" }[t];
        if (tokens[i] !== close) throw new Error(`expected ${close}`);
        i += 1;
        seq.push({
          kind: t === "(" ? "group" : t === "[" ? "opt" : "rep",
          alts,
        });
      } else if (t.startsWith('"') || t.startsWith("'")) {
        seq.push({ kind: "t", text: t.slice(1, -1) });
      } else if (/^[A-Z]+$/.test(t)) {
        seq.push({ kind: "t", text: t });
      } else {
        seq.push({ kind: "n", name: t });
      }
    }
    return seq;
  };
  while (i < tokens.length) {
    const name = tokens[i];
    if (tokens[i + 1] !== "::=") throw new Error(`expected ::= after ${name}`);
    i += 2;
    if (grammar.has(name)) throw new Error(`${name} is defined twice`);
    grammar.set(name, parseAlts());
  }
  return grammar;
}

/** A plain BNF form: synthetic rules stand for groups, options, repeats. */
type Bnf = Map<string, string[][]>; // symbols: terminals are quoted

function toBnf(g: Grammar): { bnf: Bnf; owner: Map<string, string> } {
  const bnf: Bnf = new Map();
  const owner = new Map<string, string>(); // synthetic rule -> named rule
  let n = 0;
  const lower = (rule: string, items: Item[]): string[] =>
    items.map((it) => {
      if (it.kind === "t") return `"${it.text}"`;
      if (it.kind === "n") return it.name;
      const name = `${rule}#${++n}`;
      owner.set(name, rule);
      const alts = it.alts.map((a) => lower(rule, a));
      if (it.kind === "group") bnf.set(name, alts);
      else if (it.kind === "opt") bnf.set(name, [...alts, []]);
      else bnf.set(name, [...alts.map((a) => [...a, name]), []]);
      return name;
    });
  for (const [rule, alts] of g) {
    bnf.set(rule, alts.map((a) => lower(rule, a)));
    owner.set(rule, rule);
  }
  return { bnf, owner };
}

const isTerminal = (s: string) => s.startsWith('"');

export type Report = {
  undefined: string[];
  unreachable: string[];
  unproductive: string[];
  leftRecursive: string[];
  /** "rule: token token ..." for every LL(1) conflict, sorted. */
  conflicts: string[];
  terminals: Set<string>;
};

export function checkGrammar(g: Grammar, start: string): Report {
  const { bnf, owner } = toBnf(g);
  const used = new Set<string>();
  for (const alts of bnf.values()) {
    for (const a of alts) for (const s of a) if (!isTerminal(s)) used.add(s);
  }
  const undefinedNames = [...used].filter((s) => !bnf.has(s)).sort();
  // Reachability.
  const reach = new Set<string>([start]);
  const work = [start];
  while (work.length > 0) {
    for (const a of bnf.get(work.pop()!) ?? []) {
      for (const s of a) {
        if (!isTerminal(s) && !reach.has(s)) {
          reach.add(s);
          work.push(s);
        }
      }
    }
  }
  const unreachable = [...g.keys()].filter((r) => !reach.has(r)).sort();
  // Productivity.
  const productive = new Set<string>();
  for (let changed = true; changed;) {
    changed = false;
    for (const [r, alts] of bnf) {
      if (productive.has(r)) continue;
      if (
        alts.some((a) => a.every((s) => isTerminal(s) || productive.has(s)))
      ) {
        productive.add(r);
        changed = true;
      }
    }
  }
  const unproductive = [...g.keys()].filter((r) => !productive.has(r)).sort();
  // Nullable and FIRST.
  const nullable = new Set<string>();
  const first = new Map<string, Set<string>>();
  for (const r of bnf.keys()) first.set(r, new Set());
  const firstOfSeq = (
    seq: string[],
  ): { set: Set<string>; nullable: boolean } => {
    const set = new Set<string>();
    for (const s of seq) {
      if (isTerminal(s)) {
        set.add(s);
        return { set, nullable: false };
      }
      for (const t of first.get(s) ?? []) set.add(t);
      if (!nullable.has(s)) return { set, nullable: false };
    }
    return { set, nullable: true };
  };
  for (let changed = true; changed;) {
    changed = false;
    for (const [r, alts] of bnf) {
      for (const a of alts) {
        const f = firstOfSeq(a);
        const into = first.get(r)!;
        for (const t of f.set) {
          if (!into.has(t)) {
            into.add(t);
            changed = true;
          }
        }
        if (f.nullable && !nullable.has(r)) {
          nullable.add(r);
          changed = true;
        }
      }
    }
  }
  // FOLLOW.
  const follow = new Map<string, Set<string>>();
  for (const r of bnf.keys()) follow.set(r, new Set());
  follow.get(start)!.add('"EOF"');
  for (let changed = true; changed;) {
    changed = false;
    for (const [r, alts] of bnf) {
      for (const a of alts) {
        a.forEach((s, k) => {
          if (isTerminal(s) || !bnf.has(s)) return;
          const rest = firstOfSeq(a.slice(k + 1));
          const into = follow.get(s)!;
          const add = (t: string) => {
            if (!into.has(t)) {
              into.add(t);
              changed = true;
            }
          };
          rest.set.forEach(add);
          if (rest.nullable) follow.get(r)!.forEach(add);
        });
      }
    }
  }
  // Left recursion: a rule that can begin with itself.
  const leftRecursive: string[] = [];
  for (const r of g.keys()) {
    const seen = new Set<string>();
    const stack = [r];
    let found = false;
    while (stack.length > 0 && !found) {
      const x = stack.pop()!;
      for (const a of bnf.get(x) ?? []) {
        for (const s of a) {
          if (isTerminal(s)) break;
          if (s === r) found = true;
          if (!seen.has(s)) {
            seen.add(s);
            stack.push(s);
          }
          if (!nullable.has(s)) break;
        }
      }
    }
    if (found) leftRecursive.push(r);
  }
  // LL(1) conflicts: overlapping prediction sets of one rule's alternatives.
  const conflicts = new Set<string>();
  for (const [r, alts] of bnf) {
    const predict = alts.map((a) => {
      const f = firstOfSeq(a);
      const set = new Set(f.set);
      if (f.nullable) follow.get(r)!.forEach((t) => set.add(t));
      return set;
    });
    const clash = new Set<string>();
    for (let x = 0; x < predict.length; x += 1) {
      for (let y = x + 1; y < predict.length; y += 1) {
        for (const t of predict[x]) if (predict[y].has(t)) clash.add(t);
      }
    }
    if (clash.size > 0) {
      conflicts.add(`${owner.get(r)}: ${[...clash].sort().join(" ")}`);
    }
  }
  const terminals = new Set<string>();
  for (const alts of bnf.values()) {
    for (const a of alts) {
      for (const s of a) if (isTerminal(s)) terminals.add(s.slice(1, -1));
    }
  }
  return {
    undefined: undefinedNames,
    unreachable,
    unproductive,
    leftRecursive,
    conflicts: [...conflicts].sort(),
    terminals,
  };
}

/** The resolved choices tabled in §17.4: "rule: tokens" for each row. */
export function tabledChoices(doc: string): string[] {
  const start = doc.indexOf("## 17.4");
  const rows = doc.slice(start).split("\n").filter((l) =>
    /^\| `[a-z-]+` \|/.test(l)
  );
  return rows.map((row) => {
    const cells = row.split("|").map((c) => c.trim());
    const rule = cells[1].replaceAll("`", "");
    const tokens = [...cells[2].matchAll(/`([^`]+)`/g)].map((m) => `"${m[1]}"`)
      .sort();
    return `${rule}: ${tokens.join(" ")}`;
  }).sort();
}

/** Chapter 3's reserved words and contextual words. */
export function chapter3Words(
  doc: string,
): { reserved: string[]; contextual: string[] } {
  const section = doc.slice(doc.indexOf("## 3.5"), doc.indexOf("## 3.6"));
  const after = section.slice(section.indexOf("reserved words are:"));
  const table = after.match(/```text\n([\s\S]*?)```/)![1];
  const reserved = table.split(/\s+/).filter(Boolean).sort();
  const contextual = [
    ...section.matchAll(/`(\w+)` is a \*\*contextual word\*\*/g),
  ]
    .map((m) => m[1]).sort();
  return { reserved, contextual };
}

export async function grammarFromSpec(): Promise<Grammar> {
  const doc = await Deno.readTextFile(`${ROOT}spec/17-complete-grammar.md`);
  return parseGrammar(blocks(doc, "## 17.2").join("\n"));
}

if (import.meta.main) {
  const doc = await Deno.readTextFile(`${ROOT}spec/17-complete-grammar.md`);
  const report = checkGrammar(await grammarFromSpec(), "compilation");
  const tabled = tabledChoices(doc);
  console.log(
    JSON.stringify(
      { ...report, terminals: [...report.terminals].sort() },
      null,
      2,
    ),
  );
  console.log("tabled:", JSON.stringify(tabled, null, 2));
}
