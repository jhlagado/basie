/**
 * Convert the forked Nucleus compiler from AZM syntax to ATOM source (design
 * decision D44, native compiler plan 65.0). One-shot: once the ATOM tree is
 * verified and the AZM tree removed, the name map stays as the record of what
 * each Nucleus name became.
 *
 *   deno run -A tools/atomize.ts sheets   worksheets of every name, by module
 *   deno run -A tools/atomize.ts check    validate tools/atomize/*.json
 *   deno run -A tools/atomize.ts write    write native/compiler/*.ASM
 *
 * The AZM composition `basie/basie.asm` is flattened by the forked source
 * translation with no renaming, which resolves its conditionals and turns its
 * directives into ATOM's. Each label's references decide whether it may
 * become private, by Skate's rule (tools/labels/demote.ts there): every
 * reference lies between the labels around it that stay global, in the same
 * file. The maps give every defined name its ATOM name: `NAME` for a global,
 * `.NAME` for a private label.
 */
// @ts-types="../native/compiler/tools/atom-source.d.ts"
import {
  assemblyCensus,
} from "../native/compiler/tools/atom-source.mjs";
import { buildBasie } from "../native/compiler/build.ts";
// @ts-ignore: an untyped module
import { flattenTranslatedEntry } from "../native/compiler/tools/atom-source-translation.mjs";

const ROOT = new URL("../", import.meta.url).pathname;
const MAPS = `${ROOT}tools/atomize/`;
const OUT = `${ROOT}native/compiler/`;

/** Each AZM file's ATOM file, in 8.3 form. A file resumed after an include
 * takes the second name. */
export const FILES: Record<string, string[]> = {
  "basie/basie.asm": [
    "BASIE.ASM",
    "HEAD.ASM",
    "KEYWORDS.ASM",
    "KEYWORDS.ASM",
    "SHELL.ASM",
  ],
  "basie/basie-memory-map.asmi": ["MEMORY.ASM"],
  "vertical-slice/loop-compiler-state.asmi": ["STATE.ASM"],
  "vertical-slice/aggregate-call-state.asmi": ["CALLWORK.ASM"],
  "vertical-slice/target-output-state.asmi": ["TGTWORK.ASM"],
  "vertical-slice/loop-z80-state.asmi": ["RTSTATE.ASM"],
  "vertical-slice/nucleus-runtime-identity.asmi": ["RTIDENT.ASM"],
  "vertical-slice/source-adapter.asm": ["SOURCE.ASM"],
  "vertical-slice/loop-tokenizer.asm": ["TOKEN.ASM"],
  "vertical-slice/loop-semantic-sink.asm": ["TRANSCR.ASM"],
  "vertical-slice/loop-symbols.asm": ["SYMBOLS.ASM"],
  "vertical-slice/loop-parser.asm": ["PARSER.ASM"],
  "vertical-slice/typed-expression-parser.asm": ["EXPR.ASM"],
  "vertical-slice/structured-control-parser.asm": ["CONTROL.ASM"],
  "vertical-slice/aggregate-parser.asm": ["AGGR.ASM"],
  "vertical-slice/aggregate-call-parser.asm": ["ROUTINES.ASM"],
  "vertical-slice/stage7-ll1-parser.asm": ["LL1.ASM", "GRAMMAR.ASM"],
  "../grammar/stage7-tables.asmi": ["GRAMMAR.ASM"],
  "vertical-slice/stage7-ll1-actions.asm": ["ACTIONS.ASM"],
  "vertical-slice/loop-z80-sink.asm": ["EMIT.ASM"],
  "vertical-slice/target-output.asm": ["TARGET.ASM"],
  "vertical-slice/typed-expression-z80.asm": ["GENEXPR.ASM", "GENTMPL.ASM"],
  "vertical-slice/structured-control-z80.asm": ["GENCTRL.ASM"],
  "vertical-slice/aggregate-call-z80.asm": ["GENCALL.ASM"],
  "vertical-slice/aggregate-z80.asm": ["GENAGGR.ASM"],
  "vertical-slice/loop-keywords.asmi": ["KEYWORDS.ASM"],
  "basie/basie-shell.asm": ["SHELL.ASM"],
};

/** Names that host code reads from the symbol table: they stay global. */
export const PINNED = new Set([
  "BasieImageStart",
  "BasieImageEnd",
  "CompilerCodeStart",
  "CompilerCodeEnd",
  "CompilerImmutableStart",
  "CompilerImmutableEnd",
  "CompilerCoreEnd",
  "CompilerWorkBase",
  "HybridLL1WorkspaceEnd",
  "BasieWorkBase",
  "BasieWorkEnd",
  "SourceBase",
  "ShellCodeStart",
  "ShellCodeEnd",
]);

export type Line = {
  file: string; // the ATOM file
  source: string; // the AZM file and line, for messages
  text: string;
  code: string;
  order: number;
};
type Def = {
  name: string;
  kind: "label" | "equ";
  file: string;
  order: number;
  source: string;
};

const ID = /[A-Za-z_][A-Za-z0-9_]*/g;
const MNEMONICS = new Set(
  `ADC ADD AND BIT CALL CCF CP CPD CPDR CPI CPIR CPL DAA DEC DI DJNZ EI EX EXX
  HALT IM IN INC IND INDR INI INIR JP JR LD LDD LDDR LDI LDIR NEG NOP OR OTDR
  OTIR OUT OUTD OUTI POP PUSH RES RET RETI RETN RL RLA RLC RLCA RLD RR RRA RRC
  RRCA RRD RST SBC SCF SET SLA SRA SRL SUB XOR DB DW DS EQU ORG A B C D E H L I
  R AF BC DE HL SP IX IY IXH IXL IYH IYL NZ Z NC PO PE P M LOW HIGH`.split(/\s+/),
);

/** Blank quoted text and drop the comment, keeping columns. */
export function codeOf(text: string): string {
  let out = "", quote: string | null = null;
  for (let i = 0; i < text.length; i++) {
    const c = text[i];
    if (quote) {
      out += " ";
      if (c === quote) quote = null;
    } else if (c === ";") break;
    else if (c === '"' || (c === "'" && !/AF$/i.test(out.trimEnd()))) {
      quote = c;
      out += " ";
    } else out += c;
  }
  return out;
}

/** The composition as ATOM lines, with original names, split into files. */
export function flatten(): Line[] {
  const raw: { file: string; line: number; text: string }[] = [];
  flattenTranslatedEntry({ ...assemblyCensus(), ledger: [] }, "basie/basie.asm", {
    overrides: new Map(),
    onLine: (l: { file: string; line: number; text: string }) => raw.push(l),
    onDefine: () => {},
  });
  // Split into runs of one source file; a run of blank lines is dropped.
  const runs: (typeof raw)[] = [];
  for (const l of raw) {
    const last = runs.at(-1);
    if (last && last[0].file === l.file) last.push(l);
    else runs.push([l]);
  }
  const seen = new Map<string, number>();
  const out: Line[] = [];
  for (const run of runs) {
    const index = seen.get(run[0].file) ?? 0;
    seen.set(run[0].file, index + 1);
    if (index > 0 && run.every((l) => l.text.trim() === "")) continue;
    const names = FILES[run[0].file];
    if (!names) throw new Error(`no ATOM name for ${run[0].file}`);
    const file = names[Math.min(index, names.length - 1)];
    for (const l of run) {
      out.push({
        file,
        source: `${l.file}:${l.line}`,
        text: l.text.replace(/\s+$/, ""),
        code: codeOf(l.text),
        order: out.length,
      });
    }
  }
  return out;
}

/** Definitions and operand references. */
export function scan(lines: Line[]) {
  const defs: Def[] = [];
  const refs = new Map<string, number[]>();
  for (const l of lines) {
    let rest = l.code;
    let m = /^\s*([A-Za-z_][A-Za-z0-9_]*):/.exec(rest);
    if (m) {
      const equ = /^\s*EQU\b/i.test(rest.slice(m[0].length));
      defs.push({
        name: m[1],
        kind: equ ? "equ" : "label",
        file: l.file,
        order: l.order,
        source: l.source,
      });
      rest = rest.slice(m[0].length);
      if (equ) rest = rest.replace(/^\s*EQU\b/i, "");
    } else if ((m = /^\s*([A-Za-z_][A-Za-z0-9_]*)\s+EQU\b/i.exec(rest))) {
      defs.push({
        name: m[1],
        kind: "equ",
        file: l.file,
        order: l.order,
        source: l.source,
      });
      rest = rest.slice(m[0].length);
    } else if (/^\s*%/.test(rest)) rest = "";
    const body = rest.trim();
    const mnemonic = /^[A-Za-z]+/.exec(body);
    const operands = mnemonic && MNEMONICS.has(mnemonic[0].toUpperCase())
      ? body.slice(mnemonic[0].length)
      : body;
    for (const id of operands.matchAll(ID)) {
      const before = operands[id.index! - 1];
      if (before && /[0-9$%.]/.test(before)) continue;
      if (MNEMONICS.has(id[0].toUpperCase())) continue;
      const list = refs.get(id[0]) ?? refs.set(id[0], []).get(id[0])!;
      list.push(l.order);
    }
  }
  return { defs, refs };
}

/** Which labels may become private, and the global that would own each. */
export function analyse(lines: Line[]) {
  const { defs, refs } = scan(lines);
  const labels = defs.filter((d) => d.kind === "label");
  const fileEnd = new Map<string, number>();
  for (const l of lines) fileEnd.set(l.file, l.order + 1);
  const kept = labels.map(() => true);
  let changed = true;
  while (changed) {
    changed = false;
    for (let i = 0; i < labels.length; i++) {
      if (!kept[i] || PINNED.has(labels[i].name)) continue;
      if (/(Start|End|Base|Limit)$/.test(labels[i].name)) continue; // markers
      let p = i - 1;
      while (p >= 0 && !kept[p]) p--;
      let n = i + 1;
      while (n < labels.length && !kept[n]) n++;
      if (p < 0 || labels[p].file !== labels[i].file) continue;
      const lo = labels[p].order;
      const hi = n < labels.length && labels[n].file === labels[i].file
        ? labels[n].order
        : fileEnd.get(labels[i].file)!;
      const rs = refs.get(labels[i].name) ?? [];
      if (rs.every((o) => o > lo && o < hi)) {
        kept[i] = false;
        changed = true;
      }
    }
  }
  const owner = new Map<string, string>();
  let current = "";
  for (const [i, d] of labels.entries()) {
    if (kept[i]) current = d.name;
    else owner.set(d.name, current);
  }
  return { defs, refs, owner };
}

/** Worksheets: one per ATOM file, a line per definition. */
function sheets() {
  const lines = flatten();
  const { defs, refs, owner } = analyse(lines);
  const fileOf = new Map(lines.map((l) => [l.order, l.file]));
  const out = new Map<string, string[]>();
  for (const d of defs) {
    const users = new Set(
      (refs.get(d.name) ?? []).map((o) => fileOf.get(o)!).filter((f) =>
        f !== d.file
      ),
    );
    const status = d.kind === "equ"
      ? "EQU"
      : owner.has(d.name)
      ? `PRIVATE under ${owner.get(d.name)}`
      : PINNED.has(d.name)
      ? "GLOBAL pinned"
      : "GLOBAL";
    const row = [
      d.name,
      status,
      d.source,
      `refs ${(refs.get(d.name) ?? []).length}`,
      users.size ? `used in ${[...users].join(" ")}` : "",
    ].join("\t");
    (out.get(d.file) ?? out.set(d.file, []).get(d.file)!).push(row);
  }
  Deno.mkdirSync(`${MAPS}sheets`, { recursive: true });
  for (const [file, rows] of out) {
    Deno.writeTextFileSync(
      `${MAPS}sheets/${file.replace(".ASM", ".tsv")}`,
      rows.join("\n") + "\n",
    );
  }
  console.log(
    `${defs.length} names; ${owner.size} may be private; sheets in ${MAPS}sheets`,
  );
}

const RESERVED = new Set([...MNEMONICS, "AF'"]);

/** Every map in tools/atomize/, merged and checked against the analysis. */
export function loadMap(lines: Line[]) {
  const { defs, owner } = analyse(lines);
  const map = new Map<string, string>();
  for (const e of Deno.readDirSync(MAPS)) {
    if (!e.name.endsWith(".json")) continue;
    const part = JSON.parse(Deno.readTextFileSync(MAPS + e.name)) as Record<
      string,
      string
    >;
    for (const [from, to] of Object.entries(part)) {
      if (map.has(from) && map.get(from) !== to) {
        throw new Error(`${from} mapped twice (${e.name})`);
      }
      map.set(from, to);
    }
  }
  const errors: string[] = [];
  const globals = new Map<string, string>();
  const privates = new Map<string, string>();
  for (const d of defs) {
    const to = map.get(d.name);
    if (to === undefined) {
      errors.push(`${d.source}: ${d.name} has no ATOM name`);
      continue;
    }
    const isPrivate = to.startsWith(".");
    const bare = isPrivate ? to.slice(1) : to;
    if (!/^[A-Z_][A-Z0-9_]{0,7}$/.test(bare)) {
      errors.push(`${d.name} -> ${to}: not 1 to 8 upper-case characters`);
    }
    if (RESERVED.has(bare)) errors.push(`${d.name} -> ${to}: reserved word`);
    if (isPrivate) {
      if (d.kind !== "label" || !owner.has(d.name)) {
        errors.push(`${d.name} -> ${to}: must stay global`);
        continue;
      }
      const key = `${owner.get(d.name)}${to}`;
      if (privates.has(key)) {
        errors.push(`${to} twice under ${owner.get(d.name)}`);
      }
      privates.set(key, d.name);
    } else {
      if (globals.has(bare)) {
        errors.push(`${bare} names both ${globals.get(bare)} and ${d.name}`);
      }
      globals.set(bare, d.name);
    }
  }
  // A demoted label's owner must itself stay global under the map.
  for (const [name, own] of owner) {
    const to = map.get(name);
    if (to && !to.startsWith(".")) continue;
    if (map.get(own)?.startsWith(".")) {
      errors.push(`${name}'s owner ${own} is mapped private`);
    }
  }
  return { map, errors, defs, owner };
}

/** Rewrite one line's names and lay it out in ATOM's columns. */
function render(
  text: string,
  map: Map<string, string>,
  aliases: Map<string, string>,
) {
  const code = codeOf(text);
  const comment = text.slice(code.length);
  // A forward alias is replaced by its renamed expression.
  const rename = (s: string): string =>
    s.replace(ID, (id, at: number, whole: string) => {
      const before = whole[at - 1];
      if (before && /[0-9$%.]/.test(before)) return id;
      const alias = aliases.get(id);
      if (alias !== undefined) return rename(alias);
      return map.get(id) ?? id;
    });
  // Names in quoted text are left alone: rename only outside quotes.
  let renamed = "";
  let quote: string | null = null;
  let chunk = "";
  for (let i = 0; i < code.length; i++) {
    const c = text[i];
    if (quote) {
      renamed += c;
      if (c === quote) quote = null;
    } else if (c === '"' || (c === "'" && !/AF$/i.test(chunk.trimEnd()))) {
      renamed += rename(chunk) + c;
      chunk = "";
      quote = c;
    } else chunk += c;
  }
  renamed += rename(chunk);
  const commentText = comment.replace(
    /[A-Z][a-z0-9]+(?:[A-Z][A-Za-z0-9]*)+/g,
    (w) => map.get(w) ?? w,
  );
  return layout(renamed, commentText);
}

/** ATOM's columns: labels at the margin, instructions at 4, comments at 36. */
function layout(code: string, comment: string) {
  const trimmed = code.trim();
  if (trimmed === "") {
    const c = comment.trim();
    return c === "" ? "" : (code.length > 0 && /^\s/.test(code) ? c : c);
  }
  let label = "", body = trimmed;
  const m = /^(\.?[A-Za-z_][A-Za-z0-9_]*:)\s*(.*)$/.exec(trimmed);
  const equ = /^([A-Za-z_][A-Za-z0-9_]*)\s+(EQU\b.*)$/i.exec(trimmed);
  if (m) {
    label = m[1];
    body = m[2];
  } else if (equ) {
    label = equ[1];
    body = equ[2];
  }
  let line: string;
  const parts = /^([A-Za-z%]+)\s*(.*)$/.exec(body);
  const instr = parts
    ? parts[1].toUpperCase().padEnd(5) + parts[2].replace(/\s+$/, "")
    : body;
  if (label === "") line = "    " + instr.trimEnd();
  else if (body === "") line = label;
  else if (equ) line = `${label} ${instr.trimEnd()}`;
  else if (label.length < 4) line = label.padEnd(4) + instr.trimEnd();
  else line = `${label} ${instr.trimEnd()}`;
  const c = comment.trim();
  if (c === "") return line;
  return line.length < 35 ? `${line.padEnd(35)}${c}` : `${line} ${c}`;
}

/**
 * ATOM takes a forward reference only as one symbol and a small addend, and
 * an EQU only when it is already resolved. The fork leans on its translation
 * layer for both, in two places: an EQU that aliases a later label is
 * inlined at its uses, and a DB operand that subtracts two later labels (the
 * generated grammar's row offsets) is replaced by its value in the AZM build,
 * with the expression kept in the comment.
 */
async function forwardFixes(lines: Line[]) {
  const { defs } = scan(lines);
  const at = new Map(defs.map((d) => [d.name, d.order]));
  const aliases = new Map<string, string>();
  const values = new Map<number, string>(); // line order -> replacement text
  const image = await buildBasie();
  const value = (expr: string) => {
    const js = expr.replace(ID, (id) => {
      const v = image.symbols[id];
      if (v === undefined) throw new Error(`no value for ${id}`);
      return String(v);
    }).replace(/\$([0-9A-Fa-f]+)/g, "0x$1");
    return (new Function(`return (${js})`))() as number;
  };
  for (const l of lines) {
    const equ = /^\s*([A-Za-z_][A-Za-z0-9_]*):?\s+EQU\s+(.*?)\s*$/i.exec(l.code);
    const later = (text: string) =>
      [...text.matchAll(ID)].map((m) => m[0]).filter((n) =>
        (at.get(n) ?? -1) > l.order
      );
    if (equ) {
      if (later(equ[2]).length) aliases.set(equ[1], equ[2].trim());
      continue;
    }
    const db = /^(\s*(?:[A-Za-z_][A-Za-z0-9_]*:)?\s*DB\s+)(.*)$/i.exec(l.code);
    if (!db) continue;
    const operands = db[2].split(",");
    if (!operands.some((o) => later(o).length > 1)) continue;
    const fixed = operands.map((o) =>
      later(o).length > 1 ? String(value(o.trim()) & 255) : o.trim()
    );
    const exprs = operands.filter((o) => later(o).length > 1).map((o) =>
      o.trim()
    );
    values.set(l.order, `${db[1]}${fixed.join(",")}\x00${exprs.join(", ")}`);
  }
  return { aliases, values };
}

async function write() {
  const lines = flatten();
  const { map, errors, owner } = loadMap(lines);
  if (errors.length) {
    console.error(errors.join("\n"));
    Deno.exit(1);
  }
  const { aliases, values } = await forwardFixes(lines);
  for (const l of lines) {
    const fix = values.get(l.order);
    if (fix) {
      const [code, exprs] = fix.split("\x00");
      const comment = l.text.slice(l.code.length).replace(/^\s*;\s*/, "");
      l.text = `${code} ; ${exprs}${comment ? "; " + comment : ""}`;
      continue;
    }
    const equ = /^\s*([A-Za-z_][A-Za-z0-9_]*):?\s+EQU\b/i.exec(l.code);
    if (equ && aliases.has(equ[1])) {
      const comment = l.text.slice(l.code.length).trim();
      l.text = comment;
      continue;
    }
  }
  // A private label's references use the dotted name, which the map gives.
  void owner;
  const files = new Map<string, string[]>();
  const order: string[] = [];
  for (const l of lines) {
    if (!files.has(l.file)) {
      files.set(l.file, []);
      order.push(l.file);
    }
    files.get(l.file)!.push(render(l.text, map, aliases));
  }
  // Each file's lines must be one run, so that the include list keeps the
  // image's order: ATOM assembles each included file before its includer.
  let last = "";
  const closed = new Set<string>();
  for (const l of lines) {
    if (l.file === last) continue;
    if (closed.has(l.file)) throw new Error(`${l.file} is not one run`);
    if (last) closed.add(last);
    last = l.file;
  }
  for (const [file, body] of files) {
    let text = body.join("\n").replace(/\n{3,}/g, "\n\n").trim() + "\n";
    if (file === "BASIE.ASM") {
      text += "\n" + order.filter((f) => f !== file).map((f) =>
        `%INCLUDE "${f}"`
      ).join("\n") + "\n";
    }
    Deno.writeTextFileSync(OUT + file, text);
  }
  console.log(`wrote ${order.length} files: ${order.join(" ")}`);
}

if (import.meta.main) {
  const command = Deno.args[0];
  if (command === "sheets") sheets();
  else if (command === "check") {
    // With file names, report missing names only for those files.
    const only = new Set(Deno.args.slice(1));
    const { errors, defs } = loadMap(flatten());
    const fileOf = new Map(defs.map((d) => [d.source, d.file]));
    const shown = errors.filter((e) => {
      if (!/ has no ATOM name$/.test(e) || only.size === 0) return true;
      return only.has(fileOf.get(e.split(": ")[0]) ?? "");
    });
    console.log(shown.slice(0, 300).join("\n"));
    console.log(`${defs.length} names, ${shown.length} problems shown`);
  } else if (command === "write") await write();
  else console.error("usage: atomize.ts sheets | check | write");
}
