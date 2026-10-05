import { readFileSync, writeFileSync } from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

interface SourceProduction {
  readonly lhs: string;
  readonly rhs: readonly string[];
}

interface SourceGrammar {
  readonly start: string;
  readonly diagnostics: Readonly<Record<string, string>>;
  readonly externals: Readonly<Record<string, readonly string[]>>;
  readonly productions: readonly SourceProduction[];
}

export interface Stage7GrammarAnalysis {
  readonly nullable: readonly string[];
  readonly first: Readonly<Record<string, readonly string[]>>;
  readonly follow: Readonly<Record<string, readonly string[]>>;
  readonly predictions: readonly (readonly string[])[];
  readonly conflicts: readonly string[];
}

export interface Stage7ActionLayoutEntry {
  readonly logical: string;
  readonly handler: string;
  readonly parameter?: number;
}

export interface Stage7ActionFamilyMember {
  readonly logical: string;
  readonly parameter: number;
}

export interface Stage7ActionFamily {
  readonly handler: string;
  readonly parameterStep: 1 | -1;
  readonly ordinalParameterOffset?: number;
  readonly ordinalParameterMask?: number;
  readonly members: readonly Stage7ActionFamilyMember[];
}

// These are the only parameterised action families. The handler consumes the
// preserved zero-based logical action ordinal in A before calling any helper.
const actionFamilies: readonly Stage7ActionFamily[] = [
  {
    handler: "EmitTransferAction",
    parameterStep: 1,
    ordinalParameterOffset: -1,
    members: [
      { logical: "a:EmitExit", parameter: 45 },
      { logical: "a:EmitContinue", parameter: 46 },
    ],
  },
  {
    handler: "SelectForBoundAction",
    parameterStep: -1,
    ordinalParameterMask: 1,
    members: [
      { logical: "a:ForTo", parameter: 1 },
      { logical: "a:ForUntil", parameter: 0 },
    ],
  },
  {
    handler: "SetScalarTypeAction",
    parameterStep: 1,
    members: [
      { logical: "a:TypeU8", parameter: 1 },
      { logical: "a:TypeU16", parameter: 2 },
      { logical: "a:TypeBoolean", parameter: 3 },
    ],
  },
];

const here = path.dirname(fileURLToPath(import.meta.url));
const sourcePath = path.join(here, "stage7-grammar.json");
const actionSourcePath = path.join(
  here,
  "..",
  "asm",
  "vertical-slice",
  "stage7-ll1-actions.asm",
);

export function readStage7Grammar(): SourceGrammar {
  return JSON.parse(readFileSync(sourcePath, "utf8")) as SourceGrammar;
}

const grammarActions = (grammar: SourceGrammar): readonly string[] => [
  ...new Set(
    grammar.productions.flatMap(({ rhs }) =>
      rhs.filter((symbol) => isAction(symbol) || isExternal(symbol)),
    ),
  ),
];

export function stage7ActionLayout(
  grammar = readStage7Grammar(),
  families: readonly Stage7ActionFamily[] = actionFamilies,
): readonly Stage7ActionLayoutEntry[] {
  const actions = grammarActions(grammar);
  const actionSet = new Set(actions);
  const grouped = new Map<string, Omit<Stage7ActionLayoutEntry, "logical">>();
  const handlers = new Set<string>();
  for (const family of families) {
    if (!family.handler) throw new Error("missing physical action handler");
    if (
      family.ordinalParameterOffset !== undefined &&
      family.ordinalParameterMask !== undefined
    )
      throw new Error(`ambiguous action encoding ${family.handler}`);
    if (handlers.has(family.handler))
      throw new Error(`duplicate physical action handler ${family.handler}`);
    handlers.add(family.handler);
    const firstOrdinal = actions.indexOf(family.members[0]?.logical ?? "");
    const firstParameter = family.members[0]?.parameter;
    for (const [index, member] of family.members.entries()) {
      if (!actionSet.has(member.logical))
        throw new Error(`unknown logical action ${member.logical}`);
      if (grouped.has(member.logical))
        throw new Error(`duplicate action-family member ${member.logical}`);
      if (
        !Number.isInteger(member.parameter) ||
        member.parameter < 0 ||
        member.parameter > 255
      )
        throw new Error(`action parameter out of range for ${member.logical}`);
      if (actions.indexOf(member.logical) !== firstOrdinal + index)
        throw new Error(`noncontiguous action family ${family.handler}`);
      if (
        firstParameter === undefined ||
        member.parameter !== firstParameter + index * family.parameterStep
      )
        throw new Error(`nonlinear action parameters for ${family.handler}`);
      const ordinal = firstOrdinal + index;
      if (
        family.ordinalParameterOffset !== undefined &&
        member.parameter !== ordinal + family.ordinalParameterOffset
      )
        throw new Error(`action ordinal offset mismatch for ${family.handler}`);
      if (
        family.ordinalParameterMask !== undefined &&
        member.parameter !== (ordinal & family.ordinalParameterMask)
      )
        throw new Error(`action ordinal mask mismatch for ${family.handler}`);
      grouped.set(member.logical, {
        handler: family.handler,
        parameter: member.parameter,
      });
    }
  }
  return actions.map((logical) => ({
    logical,
    ...(grouped.get(logical) ?? { handler: logical.slice(2) }),
  }));
}

export function validateStage7PhysicalHandlers(
  source: string,
  families: readonly Stage7ActionFamily[] = actionFamilies,
): void {
  for (const { handler } of families) {
    if (!source.includes(`HybridLL1${handler}:`))
      throw new Error(`missing physical action handler HybridLL1${handler}`);
  }
}

const isAction = (symbol: string) => symbol.startsWith("a:");
const isExternal = (symbol: string) => symbol.startsWith("x:");
const externalName = (symbol: string) => symbol.slice(2);

export function analyzeStage7Grammar(
  grammar = readStage7Grammar(),
): Stage7GrammarAnalysis {
  const nonterminals = new Set(grammar.productions.map(({ lhs }) => lhs));
  if (!nonterminals.has(grammar.start)) throw new Error("missing start symbol");
  const nullable = new Set<string>();
  const symbolNullable = (symbol: string) =>
    isAction(symbol) || (nonterminals.has(symbol) && nullable.has(symbol));

  let changed = true;
  while (changed) {
    changed = false;
    for (const production of grammar.productions) {
      if (
        !nullable.has(production.lhs) &&
        production.rhs.every(symbolNullable)
      ) {
        nullable.add(production.lhs);
        changed = true;
      }
    }
  }

  const first = new Map<string, Set<string>>();
  for (const nonterminal of nonterminals) first.set(nonterminal, new Set());
  const firstOfSymbol = (symbol: string): ReadonlySet<string> => {
    if (isAction(symbol)) return new Set();
    if (isExternal(symbol)) {
      const tokens = grammar.externals[externalName(symbol)];
      if (!tokens) throw new Error(`unknown external ${symbol}`);
      return new Set(tokens);
    }
    if (nonterminals.has(symbol)) return first.get(symbol)!;
    if (!symbol.startsWith("Token"))
      throw new Error(`unknown symbol ${symbol}`);
    return new Set([symbol]);
  };
  const firstOfSequence = (rhs: readonly string[]) => {
    const result = new Set<string>();
    let sequenceNullable = true;
    for (const symbol of rhs) {
      for (const token of firstOfSymbol(symbol)) result.add(token);
      if (!symbolNullable(symbol)) {
        sequenceNullable = false;
        break;
      }
    }
    return { tokens: result, nullable: sequenceNullable };
  };

  changed = true;
  while (changed) {
    changed = false;
    for (const production of grammar.productions) {
      const target = first.get(production.lhs)!;
      const before = target.size;
      for (const token of firstOfSequence(production.rhs).tokens)
        target.add(token);
      if (target.size !== before) changed = true;
    }
  }

  const follow = new Map<string, Set<string>>();
  for (const nonterminal of nonterminals) follow.set(nonterminal, new Set());
  follow.get(grammar.start)!.add("TokenEof");
  changed = true;
  while (changed) {
    changed = false;
    for (const production of grammar.productions) {
      for (let index = 0; index < production.rhs.length; index += 1) {
        const symbol = production.rhs[index];
        if (!nonterminals.has(symbol)) continue;
        const target = follow.get(symbol)!;
        const before = target.size;
        const rest = firstOfSequence(production.rhs.slice(index + 1));
        for (const token of rest.tokens) target.add(token);
        if (rest.nullable) {
          for (const token of follow.get(production.lhs)!) target.add(token);
        }
        if (target.size !== before) changed = true;
      }
    }
  }

  const predictions = grammar.productions.map((production) => {
    const result = firstOfSequence(production.rhs);
    const tokens = new Set(result.tokens);
    if (result.nullable) {
      for (const token of follow.get(production.lhs)!) tokens.add(token);
    }
    return [...tokens].sort();
  });
  const cells = new Map<string, number>();
  const conflicts: string[] = [];
  grammar.productions.forEach((production, index) => {
    for (const token of predictions[index]) {
      const key = `${production.lhs}/${token}`;
      const previous = cells.get(key);
      if (previous !== undefined)
        conflicts.push(`${key}: productions ${previous} and ${index}`);
      else cells.set(key, index);
    }
  });

  const record = (sets: ReadonlyMap<string, Set<string>>) =>
    Object.fromEntries(
      [...sets].map(([name, values]) => [name, [...values].sort()]),
    );
  return {
    nullable: [...nullable].sort(),
    first: record(first),
    follow: record(follow),
    predictions,
    conflicts,
  };
}

export function generateStage7Tables(): string {
  const grammar = readStage7Grammar();
  const analysis = analyzeStage7Grammar(grammar);
  if (analysis.conflicts.length !== 0)
    throw new Error(`LL(1) conflicts:\n${analysis.conflicts.join("\n")}`);

  const nonterminals = [...new Set(grammar.productions.map(({ lhs }) => lhs))];
  const actionLayout = stage7ActionLayout(grammar);
  validateStage7PhysicalHandlers(readFileSync(actionSourcePath, "utf8"));
  const actions = actionLayout.map(({ logical }) => logical);
  const physicalProductions: SourceProduction[] = [];
  const physicalProductionByBody = new Map<string, number>();
  const logicalToPhysicalProduction = grammar.productions.map((production) => {
    const key = JSON.stringify(production.rhs);
    const existing = physicalProductionByBody.get(key);
    if (existing !== undefined) return existing;
    const ordinal = physicalProductions.length;
    physicalProductionByBody.set(key, ordinal);
    physicalProductions.push(production);
    return ordinal;
  });
  if (nonterminals.length > 64) throw new Error("too many nonterminals");
  if (actions.length > 127) throw new Error("too many actions/externals");
  if (physicalProductions.length > 127) throw new Error("too many productions");
  if (grammar.productions.some(({ rhs }) => rhs.length > 64))
    throw new Error("production exceeds parser stack capacity");
  const productionSplit = Math.ceil(physicalProductions.length / 2);
  let rowOffset = 0;
  for (const nonterminal of nonterminals) {
    if (rowOffset > 255)
      throw new Error(`row directory offset overflow at ${nonterminal}`);
    for (let index = 0; index < grammar.productions.length; index += 1) {
      if (grammar.productions[index]?.lhs !== nonterminal) continue;
      rowOffset += 1 + analysis.predictions[index]!.length;
    }
  }
  const productionHalfBytes = (from: number, to: number) =>
    physicalProductions
      .slice(from, to)
      .reduce((bytes, production) => bytes + production.rhs.length, 0);
  if (productionHalfBytes(0, productionSplit) > 255)
    throw new Error("low production directory offset overflow");
  if (productionHalfBytes(productionSplit, physicalProductions.length) > 255)
    throw new Error("high production directory offset overflow");

  const symbol = (name: string): string => {
    if (name.startsWith("Token")) return name;
    const nonterminal = nonterminals.indexOf(name);
    if (nonterminal >= 0)
      return `$${(0x40 + nonterminal).toString(16).padStart(2, "0")}`;
    const action = actions.indexOf(name);
    if (action >= 0) return `$${(0x80 + action).toString(16).padStart(2, "0")}`;
    throw new Error(`unencoded symbol ${name}`);
  };

  const lines = [
    "; Generated from stage7-grammar.json.",
    `HybridLL1NonterminalCount .equ ${nonterminals.length}`,
    `HybridLL1ProductionCount  .equ ${physicalProductions.length}`,
    `HybridLL1ProductionSplit  .equ ${productionSplit}`,
    `HybridLL1ActionCount      .equ ${actions.length}`,
    `HybridLL1StartSymbol      .equ ${symbol(grammar.start)}`,
    ...actionLayout.flatMap(({ logical, parameter }, ordinal) =>
      parameter === undefined
        ? []
        : [`HybridLL1ActionOrdinal${logical.slice(2)} .equ ${ordinal}`],
    ),
    "",
    "HybridLL1RowDirectory:",
    ...nonterminals.map((name, index) => {
      const diagnostic = grammar.diagnostics[name];
      if (!diagnostic) throw new Error(`missing diagnostic for ${name}`);
      return `            .db HybridLL1Row${index}-HybridLL1Rows,${diagnostic} ; ${name}`;
    }),
    "HybridLL1RowDirectoryEnd:",
    "HybridLL1Rows:",
  ];
  for (const [nonterminalIndex, name] of nonterminals.entries()) {
    lines.push(`HybridLL1Row${nonterminalIndex}: ; ${name}`);
    const rowProductions = grammar.productions
      .map((production, productionIndex) => ({ production, productionIndex }))
      .filter(({ production }) => production.lhs === name);
    rowProductions.forEach(({ production, productionIndex }, rowIndex) => {
      const predictions = analysis.predictions[productionIndex];
      if (predictions.length === 0)
        throw new Error(`production ${productionIndex} has no prediction`);
      lines.push(
        `            .db ${logicalToPhysicalProduction[productionIndex]}${rowIndex === rowProductions.length - 1 ? "+$80" : ""}`,
      );
      predictions.forEach((token, index) =>
        lines.push(
          `            .db ${token}${index === predictions.length - 1 ? "+$80" : ""}`,
        ),
      );
    });
  }
  lines.push("HybridLL1RowsEnd:", "", "HybridLL1ProductionDirectory:");
  physicalProductions
    .slice(0, productionSplit)
    .forEach((production, index) =>
      lines.push(
        `            .db HybridLL1Production${index}-HybridLL1Productions ; ${production.lhs}`,
      ),
    );
  lines.push(
    "            .db HybridLL1ProductionsHigh-HybridLL1Productions",
    "HybridLL1ProductionDirectoryHigh:",
  );
  physicalProductions.slice(productionSplit).forEach((production, relative) => {
    const index = productionSplit + relative;
    lines.push(
      `            .db HybridLL1Production${index}-HybridLL1ProductionsHigh ; ${production.lhs}`,
    );
  });
  lines.push(
    "            .db HybridLL1ProductionsEnd-HybridLL1ProductionsHigh",
    "HybridLL1ProductionDirectoryEnd:",
    "HybridLL1Productions:",
  );
  physicalProductions.forEach((production, index) => {
    if (index === productionSplit) lines.push("HybridLL1ProductionsHigh:");
    const reversed = [...production.rhs].reverse();
    lines.push(`HybridLL1Production${index}: ; ${production.lhs}`);
    if (reversed.length)
      lines.push(`            .db ${reversed.map(symbol).join(",")}`);
  });
  lines.push("HybridLL1ProductionsEnd:", "", "HybridLL1ActionDirectory:");
  for (const { logical, handler, parameter } of actionLayout) {
    const suffix = parameter === undefined ? "" : `, parameter ${parameter}`;
    lines.push(`            .dw HybridLL1${handler} ; ${logical}${suffix}`);
  }
  lines.push(
    "HybridLL1ActionDirectoryEnd:",
    "",
    "HybridLL1GeneratedTableEnd:",
    "",
  );
  return lines.join("\n");
}

export function generateStage7ProofActions(): string {
  const grammar = readStage7Grammar();
  const handlers = [
    ...new Set(stage7ActionLayout(grammar).map(({ handler }) => handler)),
  ];
  return [
    "; Generated proof-only action aliases from stage7-grammar.json.",
    ...handlers.map((handler) => `HybridLL1${handler}:`),
    "            RET",
    "",
  ].join("\n");
}

if (process.argv[1] === fileURLToPath(import.meta.url)) {
  writeFileSync(path.join(here, "stage7-tables.asmi"), generateStage7Tables());
  writeFileSync(
    path.join(here, "stage7-proof-actions.asmi"),
    generateStage7ProofActions(),
  );
}
