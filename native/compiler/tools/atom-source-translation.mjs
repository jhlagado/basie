// Source-only adaptation recovered from the Nucleus Atom migration.
// No assembly, layout rewrites or historical migration CLI lives here.
import { existsSync, readdirSync, readFileSync } from "node:fs";
import path from "node:path";

function scanAssembly({ asmRoot, proofRoot }) {
  const symbols = new Map(), occurrences = [], conditionals = new Set();
  const proofSymbols = collectProofSymbols(proofRoot);
  for (const file of findAssemblyFilesWithIncludes(asmRoot)) {
    const lines = readFileSync(file, "utf8").split(/\n/);
    for (let index = 0; index < lines.length; index++) {
      const code = stripComment(lines[index].replace(/\r$/, ""));
      for (const symbol of collectSourceIdentifiers(maskQuoted(code))) {
        occurrences.push({ symbol, file, line: index + 1 });
      }
      const conditional = /^\s*\.if\s+([A-Za-z_][A-Za-z0-9_]*)\s*$/i.exec(code);
      if (conditional) conditionals.add(conditional[1]);
      const label = /^\s*([A-Za-z_.$?][A-Za-z0-9_.$?]*):/.exec(code);
      if (label) recordSymbol(symbols, label[1], file, index + 1, proofSymbols, "label");
      const equ = /^\s*([A-Za-z_.$?][A-Za-z0-9_.$?]*)(?::\s*|\s+)\.equ\b/i.exec(code);
      if (equ) recordSymbol(symbols, equ[1], file, index + 1, proofSymbols, "equ");
    }
  }
  for (const name of conditionals) symbols.delete(name);
  const { plan } = buildPermanentSymbolPlan(symbols, occurrences, proofSymbols);
  const ledger = [...symbols.values()]
    .filter(entry => entry.original.length > 8)
    .sort((left, right) => left.original.localeCompare(right.original))
    .map((entry, index) => ({
      original: entry.original,
      atom: atomSymbolFor(index),
      ...plan.get(entry.original),
    }));
  return { asmRoot, ledger, sourceSymbolNames: [...symbols.keys()], preprocessorSymbols: [...conditionals] };
}

function collectProofSymbols(root) {
  const symbols = new Set();
  if (!existsSync(root)) return symbols;
  for (const file of recursiveFiles(root).filter((file) => file.endsWith(".json"))) {
    const value = JSON.parse(readFileSync(file, "utf8"));
    collectStrings(value, symbols);
  }
  return symbols;
}

function recursiveFiles(root) {
  if (!existsSync(root)) return [];
  return readdirSync(root, { withFileTypes: true }).flatMap((item) => {
    const file = path.join(root, item.name);
    return item.isDirectory() ? recursiveFiles(file) : item.isFile() ? [file] : [];
  }).sort();
}

function collectStrings(value, symbols) {
  if (typeof value === "string") {
    if (identifierPattern.test(value)) symbols.add(value);
    return;
  }
  if (Array.isArray(value)) {
    for (const item of value) collectStrings(item, symbols);
    return;
  }
  if (value !== null && typeof value === "object") {
    for (const [key, child] of Object.entries(value)) {
      if (key === "symbols" && child !== null && typeof child === "object" && !Array.isArray(child)) {
        for (const symbol of Object.keys(child)) {
          if (identifierPattern.test(symbol)) symbols.add(symbol);
        }
      }
      collectStrings(child, symbols);
    }
  }
}

const identifierPattern = /^[A-Za-z_.$?][A-Za-z0-9_.$?]*$/;

function findAssemblyFilesWithIncludes(asmRoot) {
  const root = sourcePackageRoot(asmRoot);
  const queue = findAssemblyFiles(asmRoot).map((file) => path.resolve(file));
  const seen = new Set();
  for (let index = 0; index < queue.length; index += 1) {
    const file = queue[index];
    if (seen.has(file)) continue;
    seen.add(file);
    if (!existsSync(file)) continue;
    for (const raw of readFileSync(file, "utf8").split(/\n/)) {
      const include = includeSpecifier(stripComment(raw.replace(/\r$/, "")));
      if (include === undefined) continue;
      const resolved = resolveConfinedInclude(file, include, root);
      if (!seen.has(resolved)) queue.push(resolved);
    }
  }
  return [...seen].sort();
}

function sourcePackageRoot(asmRoot) {
  const resolvedAsmRoot = path.resolve(asmRoot);
  return path.basename(resolvedAsmRoot) === "asm"
    ? path.dirname(resolvedAsmRoot)
    : resolvedAsmRoot;
}

function findAssemblyFiles(root) {
  return recursiveFiles(root).filter((file) => /\.(asm|asmi)$/.test(file));
}

function includeSpecifier(source) {
  const match = /^\s*\.include\s+"([^"\r\n]+)"\s*$/i.exec(source);
  return match?.[1];
}

function stripComment(line) {
  let quote = "";
  for (let index = 0; index < line.length; index += 1) {
    const char = line[index];
    if (quote !== "") {
      if (char === quote) quote = "";
      continue;
    }
    if (char === "\"" || char === "'") {
      quote = char;
      continue;
    }
    if (char === ";") return line.slice(0, index);
  }
  return line;
}

function resolveConfinedInclude(fromFile, include, root) {
  const resolved = path.resolve(path.dirname(fromFile), include);
  const relative = path.relative(root, resolved);
  if (relative.startsWith("..") || path.isAbsolute(relative)) {
    throw new Error(`include escapes Nucleus source root: ${include}`);
  }
  return resolved;
}

function collectSourceIdentifiers(unquotedCode) {
  const identifiers = [];
  for (const match of unquotedCode.matchAll(sourceIdentifierPattern)) {
    identifiers.push(match[2]);
  }
  return identifiers;
}

const sourceIdentifierPattern = /(^|[^A-Za-z0-9_.$?])([A-Za-z_.$?][A-Za-z0-9_.$?]*)(?=$|[^A-Za-z0-9_.$?])/g;

function maskQuoted(source) {
  let output = "";
  let quote = "";
  for (let index = 0; index < source.length; index += 1) {
    const character = source[index];
    if (quote !== "") {
      output += " ";
      if (character === quote) quote = "";
      continue;
    }
    if (character === "\"" || character === "'") {
      quote = character;
      output += " ";
      continue;
    }
    output += character;
  }
  return output;
}

function recordSymbol(symbols, original, file, line, proofSymbols, definitionKind) {
  const existing = symbols.get(original);
  if (existing !== undefined) {
    existing.definitions.push({ file, line });
    if (existing.definitionKind !== definitionKind) existing.definitionKind = "mixed";
    return;
  }
  symbols.set(original, {
    original,
    file,
    scope: classifyScope(original, file, proofSymbols),
    definitionKind,
    definitions: [{ file, line }],
  });
}

function classifyScope(symbol, file, proofSymbols) {
  if (proofSymbols.has(symbol)) return "exported-proof-symbol";
  const base = path.basename(file);
  if (base.includes("proof")) return "proof-only";
  if (symbol.startsWith(".") || symbol.startsWith("_")) return "private-or-local";
  return "global";
}

function buildPermanentSymbolPlan(symbols, occurrences, proofSymbols) {
  const entries = [...symbols.values()];
  const symbolOccurrences = new Map();
  for (const occurrence of occurrences) {
    if (!symbols.has(occurrence.symbol)) continue;
    const list = symbolOccurrences.get(occurrence.symbol) ?? [];
    list.push(occurrence);
    symbolOccurrences.set(occurrence.symbol, list);
  }

  const crossFileSymbols = new Set();
  for (const entry of entries) {
    const definitionFiles = new Set(entry.definitions.map(({ file }) => file));
    if ((symbolOccurrences.get(entry.original) ?? []).some(({ file }) => !definitionFiles.has(file))) {
      crossFileSymbols.add(entry.original);
    }
  }

  const labelEntriesByFile = new Map();
  for (const entry of entries) {
    if (entry.definitionKind !== "label") continue;
    for (const definition of entry.definitions) {
      const file = definition.file;
      const list = labelEntriesByFile.get(file) ?? [];
      list.push({ entry, definition });
      labelEntriesByFile.set(file, list);
    }
  }
  for (const list of labelEntriesByFile.values()) {
    list.sort((left, right) => left.definition.line - right.definition.line || left.entry.original.localeCompare(right.entry.original));
  }

  const anchorDefinitions = (list, nonLocalSymbols) => list
    .filter(({ entry }) => entry.original.length <= 8 || nonLocalSymbols.has(entry.original))
    .map(({ entry, definition }) => ({
      entry,
      line: definition.line,
    }))
    .sort((left, right) => left.line - right.line || left.entry.original.localeCompare(right.entry.original));

  const nonLocalSymbols = new Set();
  const isLocalEligible = (entry) => (
    entry.original.length > 8 &&
    entry.definitionKind === "label" &&
    entry.definitions.length === 1 &&
    !proofSymbols.has(entry.original) &&
    !crossFileSymbols.has(entry.original)
  );

  for (const [file, list] of labelEntriesByFile.entries()) {
    const first = list[0]?.entry;
    if (first !== undefined && isLocalEligible(first)) {
      nonLocalSymbols.add(first.original);
    }
    for (const { entry } of list) {
      if (!isLocalEligible(entry) || entry.original.length <= 8) {
        nonLocalSymbols.add(entry.original);
      }
      if (entry.original.length <= 8 || proofSymbols.has(entry.original) || crossFileSymbols.has(entry.original)) {
        nonLocalSymbols.add(entry.original);
      }
    }
  }

  let changed = true;
  while (changed) {
    changed = false;
    for (const [file, list] of labelEntriesByFile.entries()) {
      const anchors = anchorDefinitions(list, nonLocalSymbols);
      for (const { entry, definition } of list) {
        if (!isLocalEligible(entry) || nonLocalSymbols.has(entry.original)) continue;
        const line = definition.line;
        let anchor;
        let nextAnchor;
        for (const candidate of anchors) {
          const candidateLine = candidate.line;
          if (candidateLine < line) anchor = candidate;
          if (candidateLine > line) {
            nextAnchor = candidate;
            break;
          }
        }
        const start = anchor?.line;
        const end = nextAnchor?.line;
        const safe = start !== undefined && (symbolOccurrences.get(entry.original) ?? [])
          .every((occurrence) => occurrence.file === file && lineRangeContains(occurrence.line, start, end));
        if (!safe) {
          nonLocalSymbols.add(entry.original);
          changed = true;
        }
      }
    }
  }

  const localCounters = new Map();
  const plan = new Map();
  const usedGlobalNames = new Set(entries
    .filter((entry) => entry.original.length <= 8)
    .map((entry) => entry.original.toUpperCase()));

  for (const [file, list] of labelEntriesByFile.entries()) {
    const anchors = anchorDefinitions(list, nonLocalSymbols);
    for (const { entry, definition } of list) {
      if (!isLocalEligible(entry) || nonLocalSymbols.has(entry.original)) continue;
      const line = definition.line;
      let anchor;
      for (const candidate of anchors) {
        const candidateLine = candidate.line;
        if (candidateLine < line) anchor = candidate;
        if (candidateLine > line) break;
      }
      if (anchor === undefined) continue;
      const key = `${file}:${anchor.entry.original}:${anchor.line}`;
      const index = localCounters.get(key) ?? 0;
      localCounters.set(key, index + 1);
      plan.set(entry.original, {
        migrationKind: "local-label",
        permanentAtom: atomLocalSymbolFor(index),
        localScope: {
          anchor: anchor.entry.original,
          file: path.relative(process.cwd(), file),
          line: anchor.line,
        },
      });
    }
  }

  for (const entry of entries) {
    if (entry.original.length <= 8 || plan.has(entry.original)) continue;
    let migrationKind = "generated-global";
    if (proofSymbols.has(entry.original)) {
      migrationKind = "public-abbreviation-required";
    } else if (crossFileSymbols.has(entry.original)) {
      migrationKind = "cross-file-abbreviation-required";
    } else if (entry.definitionKind === "equ") {
      migrationKind = "equ-abbreviation-required";
    }
    plan.set(entry.original, {
      migrationKind,
      permanentAtom: uniqueAtomAbbreviation(entry.original, usedGlobalNames),
      localScope: null,
    });
  }

  return { plan, symbolOccurrences, crossFileSymbols };
}

function lineRangeContains(line, start, end) {
  return line > start && (end === undefined || line < end);
}

function atomLocalSymbolFor(index) {
  return `.L${index.toString(36).toUpperCase().padStart(5, "0")}`;
}

function uniqueAtomAbbreviation(symbol, usedNames) {
  const base = atomAbbreviationBase(symbol);
  let candidate = base;
  for (let index = 0; usedNames.has(candidate.toUpperCase()); index += 1) {
    const suffix = index.toString(36).toUpperCase();
    const suffixLength = Math.min(3, suffix.length);
    candidate = `${base.slice(0, 8 - suffixLength)}${suffix.slice(-suffixLength)}`;
    if (index > 0xfff) {
      throw new Error(`could not generate Atom abbreviation for ${symbol}`);
    }
  }
  usedNames.add(candidate.toUpperCase());
  return candidate;
}

function atomAbbreviationBase(symbol) {
  const words = splitSymbolWords(symbol);
  const squeezed = words.map(squeezeSymbolWord);
  const base = squeezed.length === 0
    ? symbol.toUpperCase().replace(/[^A-Z0-9]/g, "")
    : squeezed.join("");
  const normalized = base.replace(/^[0-9]+/, "").replace(/[^A-Z0-9]/g, "");
  return (normalized === "" ? "N" : normalized).slice(0, 8);
}

function splitSymbolWords(symbol) {
  return symbol
    .replace(/([a-z0-9])([A-Z])/g, "$1 $2")
    .replace(/([A-Za-z])([0-9])/g, "$1 $2")
    .replace(/([0-9])([A-Za-z])/g, "$1 $2")
    .split(/[^A-Za-z0-9]+/)
    .filter((word) => word.length > 0);
}

function squeezeSymbolWord(word) {
  const upper = word.toUpperCase();
  if (upper.length <= 2) return upper;
  return upper[0] + upper.slice(1).replace(/[AEIOU]/g, "");
}

function atomSymbolFor(index) {
  return `N${index.toString(36).toUpperCase().padStart(7, "0")}`;
}

function symbolMapFromLedger(ledger, { symbols = "preview" } = {}) {
  if (!["preview", "permanent"].includes(symbols)) {
    throw new Error("Nucleus Atom translated symbols must be preview or permanent");
  }
  const field = symbols === "permanent" ? "permanentAtom" : "atom";
  return new Map(ledger.map((entry) => [entry.original, entry[field]]));
}

function flattenTranslatedEntry(report, entry, { overrides = new Map(), onLine, onDefine } = {}) {
  const symbolMap = symbolMapFromLedger(report.ledger);
  const symbolMetadata = symbolMetadataFromLedger(report.ledger);
  const preprocessorSymbols = new Set(report.preprocessorSymbols);
  const stack = [];
  const definitions = new Map();
  const conditionStack = [];

  function active() {
    return conditionStack.every((condition) => condition.active);
  }

  function parseDefinitionValue(text) {
    const trimmed = text.trim();
    const value = numberValue(trimmed);
    if (value === undefined) {
      throw new Error(`unsupported Nucleus preview definition value: ${trimmed}`);
    }
    return value;
  }

  function handlePreprocessorLine(source, output) {
    const define = /^(\s*)([A-Za-z_.$?][A-Za-z0-9_.$?]*)(:\s*|\s+)\.equ\b(.*)$/i.exec(source);
    if (define !== null && preprocessorSymbols.has(define[2])) {
      if (active()) {
        const value = parseDefinitionValue(define[4]);
        definitions.set(define[2], value);
        onDefine?.(define[2], value);
        output.push(`${define[1]};@DEFINE ${define[2]} ${value}`);
      }
      return true;
    }

    const directive = /^\s*\.(if|else|endif)\b\s*(.*)$/i.exec(source);
    if (directive === null) return false;
    const name = directive[1].toLowerCase();
    const argument = directive[2].trim();
    if (name === "if") {
      if (!simpleConditionPattern.test(argument)) {
        throw new Error(`unsupported Nucleus preview conditional expression: ${argument}`);
      }
      const parentActive = active();
      const enabled = (definitions.get(argument) ?? 0) !== 0;
      conditionStack.push({ parentActive, conditionEnabled: enabled, active: parentActive && enabled, seenElse: false });
      output.push(`;@IF ${argument} ${enabled ? 1 : 0}`);
      return true;
    }
    if (name === "else") {
      const top = conditionStack.at(-1);
      if (top === undefined) throw new Error("Nucleus preview conditional .ELSE without .IF");
      if (top.seenElse) throw new Error("Nucleus conditional has more than one .ELSE");
      top.seenElse = true;
      top.active = top.parentActive && !top.conditionEnabled;
      output.push(";@ELSE");
      return true;
    }
    const top = conditionStack.pop();
    if (top === undefined) throw new Error("Nucleus preview conditional .ENDIF without .IF");
    output.push(";@ENDIF");
    return true;
  }

  function expand(file) {
    const real = path.resolve(file);
    const confined = path.relative(sourcePackageRoot(report.asmRoot), real);
    if (confined === ".." || confined.startsWith(`..${path.sep}`) || path.isAbsolute(confined)) {
      throw new Error(`include escapes Nucleus assembly root: ${file}`);
    }
    const activeIndex = stack.indexOf(real);
    if (activeIndex >= 0) {
      const cycle = [...stack.slice(activeIndex), real]
        .map((item) => path.relative(report.asmRoot, item).split(path.sep).join("/"))
        .join(" -> ");
      throw new Error(`include cycle while flattening Nucleus Atom preview: ${cycle}`);
    }
    stack.push(real);
    const relative = path.relative(report.asmRoot, real).split(path.sep).join("/");
    const lines = (overrides.get(relative) ?? readFileSync(real, "utf8")).split(/\n/);
    const output = [`;@SOURCE-BEGIN ${relative}`];
    for (let index = 0; index < lines.length; index += 1) {
      const line = lines[index];
      const source = stripComment(line);
      const comment = line.slice(source.length);
      if (handlePreprocessorLine(source, output)) {
        continue;
      }
      if (!active()) {
        continue;
      }
      const include = includeSpecifier(source);
      if (include !== undefined) {
        output.push(`;@INCLUDE-BEGIN ${include}${comment === "" ? "" : ` ${comment}`}`);
        output.push(expand(path.resolve(path.dirname(real), include)));
        output.push(`;@INCLUDE-END ${include}`);
        continue;
      }
      const translated = translateNucleusAzmLine(line, {
        sourceName: relative,
        lineNumber: index + 1,
        symbolMap,
        symbolMetadata,
        preprocessorSymbols,
      });
      output.push(translated);
      onLine?.({ text: translated, file: relative, line: index + 1 });
    }
    output.push(`;@SOURCE-END ${relative}`);
    stack.pop();
    if (stack.length === 0 && conditionStack.length !== 0) {
      throw new Error("Nucleus preview conditional .IF without .ENDIF");
    }
    return output.join("\n");
  }

  return expand(path.resolve(report.asmRoot, entry));
}

function symbolMetadataFromLedger(ledger) {
  return new Map(ledger.map((entry) => [entry.original, entry]));
}

function numberValue(text) {
  if (/^\$[0-9A-Fa-f]+$/.test(text)) return Number.parseInt(text.slice(1), 16);
  if (/^%[01]+$/.test(text)) return Number.parseInt(text.slice(1), 2);
  if (/^[0-9][0-9A-Fa-f]*[Hh]$/.test(text)) return Number.parseInt(text.slice(0, -1), 16);
  if (/^[01]+[Bb]$/.test(text)) return Number.parseInt(text.slice(0, -1), 2);
  if (/^[0-9]+$/.test(text)) return Number.parseInt(text, 10);
  return undefined;
}

const simpleConditionPattern = /^[A-Za-z_][A-Za-z0-9_]*$/;

function translateNucleusAzmLine(
  line,
  {
    sourceName = "<nucleus-asm>",
    lineNumber = 1,
    symbolMap = new Map(),
    symbolMetadata = new Map(),
    preprocessorSymbols = new Set(),
  } = {},
) {
  const source = stripComment(line);
  const comment = line.slice(source.length);
  const context = { file: sourceName, line: lineNumber };

  const leadingDirective = /^(\s*)\.([A-Za-z][A-Za-z0-9_]*)(\b.*)$/.exec(source);
  if (leadingDirective !== null) {
    const [, prefix, rawName, rest] = leadingDirective;
    const name = rawName.toLowerCase();
    if (name === "routine") {
      return `${prefix};@ROUTINE${rest.toUpperCase()}${comment}`;
    }
    if (name === "end") {
      return `${prefix};@AZM-END${comment}`;
    }
    const replacement = directiveTranslations.get(name);
    if (replacement === undefined) {
      throw new Error(`${context.file}:${context.line}: unsupported directive .${rawName}`);
    }
    return `${replaceSymbolsInSource(`${prefix}${replacement}${rest}`, symbolMap)}${comment}`;
  }

  const equ = /^(\s*[A-Za-z_.$?][A-Za-z0-9_.$?]*(?::\s*|\s+))\.equ(\b.*)$/i.exec(source);
  if (equ !== null) {
    const onePastLimit = /^(\s*)(AddressSpaceLimit|ProofMemoryEnd)(:?\s+)\.equ\s+\$10000\s*$/i.exec(source);
    if (onePastLimit !== null) {
      const original = onePastLimit[2];
      const atom = symbolMap.get(original) ?? original;
      return `${onePastLimit[1]}${atom}${onePastLimit[3]}EQU 0${declarationComment(original, symbolMetadata)} ;@ATOM-PROOF-LIMIT ${original} 65536${comment === "" ? "" : ` ${comment}`}`;
    }
    const preprocessorDefinition = /^(\s*)([A-Za-z_.$?][A-Za-z0-9_.$?]*)(:\s*|\s+)\.equ\b(.*)$/i.exec(source);
    if (preprocessorDefinition !== null && preprocessorSymbols.has(preprocessorDefinition[2])) {
      return `${preprocessorDefinition[1]}%DEFINE ${preprocessorDefinition[2]}${preprocessorDefinition[4]}${comment}`;
    }
    const equName = /^\s*([A-Za-z_.$?][A-Za-z0-9_.$?]*)/.exec(equ[1])?.[1];
    return `${replaceSymbolsInSource(`${equ[1]}EQU${equ[2]}`, symbolMap)}${equName === undefined ? "" : declarationComment(equName, symbolMetadata)}${comment}`;
  }

  const labelDirective = /^(\s*[A-Za-z_.$?][A-Za-z0-9_.$?]*(?::\s*|\s+))\.([A-Za-z][A-Za-z0-9_]*)(\b.*)$/i.exec(source);
  if (labelDirective !== null) {
    const [, prefix, rawName, rest] = labelDirective;
    const replacement = directiveTranslations.get(rawName.toLowerCase());
    if (replacement === undefined) {
      throw new Error(`${context.file}:${context.line}: unsupported directive .${rawName}`);
    }
    const labelName = /^\s*([A-Za-z_.$?][A-Za-z0-9_.$?]*)/.exec(prefix)?.[1];
    return `${replaceSymbolsInSource(`${prefix}${replacement}${rest}`, symbolMap)}${labelName === undefined ? "" : declarationComment(labelName, symbolMetadata)}${comment}`;
  }

  const translatedSource = replaceSymbolsInSource(convertLeadingImmediateGrouping(convertQuotedByteExpressions(source)), symbolMap);
  const label = /^\s*([A-Za-z_.$?][A-Za-z0-9_.$?]*):/.exec(source);
  return `${translatedSource}${label === null ? "" : declarationComment(label[1], symbolMetadata)}${comment}`;
}

const directiveTranslations = new Map([
  ["db", "DB"],
  ["ds", "DS"],
  ["dw", "DW"],
  ["else", "%ELSE"],
  ["endif", "%ENDIF"],
  ["equ", "EQU"],
  ["if", "%IF"],
  ["include", "%INCLUDE"],
  ["org", "ORG"],
]);

function replaceSymbolsInSource(source, symbolMap) {
  if (symbolMap.size === 0) return source;
  let output = "";
  let quote = "";
  for (let index = 0; index < source.length;) {
    const character = source[index];
    if (quote !== "") {
      output += character;
      index += 1;
      if (character === quote) quote = "";
      continue;
    }
    if (character === "\"" || character === "'") {
      quote = character;
      output += character;
      index += 1;
      continue;
    }
    const match = /^[A-Za-z_.$?][A-Za-z0-9_.$?]*/.exec(source.slice(index));
    if (match !== null) {
      const word = match[0];
      output += symbolMap.get(word) ?? word;
      index += word.length;
      continue;
    }
    output += character;
    index += 1;
  }
  return output;
}

function declarationComment(original, symbolMetadata) {
  const entry = symbolMetadata.get(original);
  if (entry === undefined) return "";
  if (entry.migrationKind === "local-label") return "";
  const permanent = entry.permanentAtom === entry.atom ? "" : ` PERMANENT ${entry.permanentAtom}`;
  return ` ;@NUC-GLOBAL ${entry.original}${permanent}`;
}

function convertLeadingImmediateGrouping(source) {
  return source.replace(
    /\b(LD\s+(?:BC|DE|HL|SP|IX|IY)\s*,\s*)\(([^()\r\n]*<<[^()\r\n]*)\)(?=\s*(?:[|+\-*/%&^]|$))/gi,
    "$1$2",
  );
}

function convertQuotedByteExpressions(source) {
  let output = "";
  let quote = "";
  for (let index = 0; index < source.length;) {
    const character = source[index];
    if (quote !== "") {
      output += character;
      index += 1;
      if (character === quote) quote = "";
      continue;
    }
    if (character === "'") {
      quote = character;
      output += character;
      index += 1;
      continue;
    }
    if (character === "\"") {
      const next = source[index + 1];
      const close = source[index + 2];
      if (next !== undefined && close === "\"") {
        output += `'${next === "'" ? "\\'" : next}'`;
        index += 3;
        continue;
      }
      if (next === "\\" && source[index + 3] === "\"") {
        const escaped = source[index + 2];
        if (escaped === undefined) {
          output += character;
          index += 1;
          continue;
        }
        output += `'\\${escaped}'`;
        index += 4;
        continue;
      }
      quote = character;
      output += character;
      index += 1;
      continue;
    }
    output += character;
    index += 1;
  }
  return output;
}

export { scanAssembly, symbolMapFromLedger, flattenTranslatedEntry };
