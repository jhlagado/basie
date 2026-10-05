// Build-time source adaptation only. Atom, not this module, resolves addresses.
import path from "node:path";
import { fileURLToPath } from "node:url";
import { assembleResolvedAtomProject, materializeAtomGeneration, writeAtomD8 } from "atom-z80";
import { flattenTranslatedEntry, scanAssembly, symbolMapFromLedger } from "./atom-source-translation.mjs";

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
let census;
export const assemblyCensus = () => census ??= scanAssembly({ asmRoot: path.join(root, "asm"), proofRoot: path.join(root, "proofs") });

// HEX is sparse: ORG gaps and uninitialised storage are not writes. The normal
// flat-binary renderer pads gaps, which would overwrite unrelated host memory.
export function sparseIntelHex(generation) {
  const materialized = materializeAtomGeneration(generation);
  const addresses = new Set();
  for (const image of generation.images) {
    for (let index = 0; index < image.bytes.length; index++) addresses.add(image.address + index);
  }
  for (const patch of generation.patches) {
    for (let index = 0; index < patch.bytes.length; index++) {
      if (!addresses.has(patch.address + index)) throw new Error("Atom patch is outside an emitted image");
    }
  }
  const sorted = [...addresses].sort((a, b) => a - b), records = [];
  const hexByte = value => (value & 255).toString(16).toUpperCase().padStart(2, "0");
  for (let index = 0; index < sorted.length;) {
    const start = sorted[index], data = [];
    do {
      data.push(materialized.bytes[sorted[index] - materialized.base]); index++;
    } while (data.length < 16 && sorted[index] === start + data.length);
    const record = [data.length, start >>> 8, start & 255, 0, ...data];
    record.push(-record.reduce((sum, value) => sum + value, 0) & 255);
    records.push(":" + record.map(hexByte).join(""));
  }
  return [...records, ":00000001FF", ""].join("\n");
}

// Apostrophes in AF' are not string delimiters. Character operands are made
// numeric so that Atom accepts arithmetic such as SUB 'a'-'0'. Strings stay intact.
export function normalizeLine(line) {
  let output = "";
  for (let i = 0; i < line.length; i++) {
    const char = line[i];
    if (char === ";") break;
    if ((char === "'" || char === '"') && !/[A-Za-z0-9_]/.test(line[i - 1] ?? "")) {
      let end = i + 1;
      while (end < line.length && line[end] !== char) {
        if (line[end] === "\\") end++;
        end++;
      }
      if (end >= line.length) throw new Error(`Unterminated string: ${line}`);
      output += end === i + 2 ? `$${line.charCodeAt(i + 1).toString(16)}` : line.slice(i, end + 1);
      i = end;
    } else output += char;
  }
  return output.trim();
}

function expressionTokens(expression) {
  return expression.match(/'(?:\\.|[^'\\])*'|"(?:\\.|[^"\\])*"|\$[0-9a-f]+|\b[0-9][0-9a-f]*h\b|\b[01]+b\b|\b\d+\b|[A-Za-z_][A-Za-z0-9_]*|\$/gi) ?? [];
}
const z80RegisterNames = new Set([
  "A", "F", "B", "C", "D", "E", "H", "L", "AF", "BC", "DE", "HL",
  "AF'", "IX", "IY", "SP", "PC", "I", "R", "IXH", "IXL", "IYH", "IYL",
]);
function references(expression) {
  return [...new Set(expressionTokens(expression).filter(token =>
    /^[A-Za-z_]/.test(token) &&
    !/^(LOW|HIGH)$/i.test(token) &&
    !z80RegisterNames.has(token.toUpperCase()),
  ))];
}
function locationDependent(expression) { return expressionTokens(expression).includes("$"); }
function operands(text) {
  const result = [];
  let quote = "", start = 0;
  for (let i = 0; i < text.length; i++) {
    const c = text[i];
    if (quote) {
      if (c === "\\") i++;
      else if (c === quote) quote = "";
    } else if (c === "'" || c === '"') quote = c;
    else if (c === ",") { result.push(text.slice(start, i)); start = i + 1; }
  }
  result.push(text.slice(start));
  return result;
}

// EQU is immutable and emits no bytes. It may move only when independent of
// the current location. Forward multi-symbol table operands become symbolic
// equates; no expression is evaluated using another assembler's symbol table.
export function scheduleEquates(input) {
  const known = new Set(), declared = new Set(), pending = [], output = [];
  const fail = (item, message) => { throw new Error(`${item.file}:${item.line}: ${message}`); };
  for (const item of input) {
    const text = normalizeLine(item.text);
    const name = /^([A-Za-z_][A-Za-z0-9_]*)(?:\s*:|\s+EQU\b)/i.exec(text)?.[1];
    if (name) {
      if (declared.has(name)) fail(item, `Duplicate symbol ${name}`);
      declared.add(name);
    }
  }
  let aliasOrdinal = 0;
  function alias() {
    let name;
    do { name = `X${(aliasOrdinal++).toString(36).toUpperCase().padStart(7, "0")}`; } while (declared.has(name));
    declared.add(name);
    return name;
  }
  function flush() {
    let changed;
    do {
      changed = false;
      for (let i = 0; i < pending.length; i++) {
        const item = pending[i];
        if (item.refs.every(name => known.has(name))) {
          output.push(item); known.add(item.name); pending.splice(i--, 1); changed = true;
        }
      }
    } while (changed);
  }
  for (const source of input) {
    const text = normalizeLine(source.text);
    if (!text) continue;
    const item = { ...source, text };
    const equ = /^([A-Za-z_][A-Za-z0-9_]*)\s+EQU\s+(.+)$/i.exec(text);
    if (equ) {
      const refs = references(equ[2]);
      if (locationDependent(equ[2])) {
        if (!refs.every(name => known.has(name))) fail(item, "Cannot defer a location-dependent EQU");
        output.push(item); known.add(equ[1]);
      } else pending.push({ ...item, name: equ[1], refs });
      flush();
      continue;
    }
    const data = /^(D[WB]\s+)(.+)$/i.exec(text);
    // Atom accepts the parenthesised form, but not a multi-symbol expression
    // inside it until the expression has been named by an EQU. Keep the
    // outer memory-reference syntax and schedule the inner expression just as
    // we already do for immediate operands.
    const immediate = /^(LD\s+(?:A|B|C|D|E|H|L|BC|DE|HL|SP|IX|IY),\s*)(.*)$/i.exec(text);
    const compareImmediate = /^(CP\s+)([^\s()].*)$/i.exec(text);
    const fields = data ?? immediate ?? compareImmediate;
    if (fields) item.text = fields[1] + operands(fields[2]).map(expression => {
      const wrapped = /^\((.*)\)$/.exec(expression.trim());
      const body = wrapped?.[1] ?? expression;
      const refs = references(body);
      if (refs.length < 2) return expression;
      if (locationDependent(body)) fail(item, "Cannot defer a location-dependent table expression");
      const name = alias();
      pending.push({ ...item, name, refs, text: `${name} EQU ${body}` });
      // If all dependencies are already known, emit the alias before this
      // instruction. Otherwise flush() emits it when its last dependency is
      // encountered later in the stream.
      flush();
      return wrapped ? `(${name})` : name;
    }).join(",");
    output.push(item);
    const label = /^([A-Za-z_][A-Za-z0-9_]*):/.exec(text);
    if (label) { known.add(label[1]); flush(); }
  }
  if (pending.length) fail(pending[0], `Unresolved or cyclic EQU definitions: ${pending.map(item => item.text).join("; ")}`);
  return output;
}

export function prepareAtomSource(entry, { report = assemblyCensus(), overrides = new Map() } = {}) {
  // Generated link contexts may declare symbols absent from checked-in source.
  // Append aliases without renumbering the recovered source ledger.
  const contextNames = new Set();
  for (const text of overrides.values()) {
    for (const line of text.split(/\n/)) {
      const name = /^\s*([A-Za-z_.$?][A-Za-z0-9_.$?]*)(?:\s*:|\s+\.equ\b)/i.exec(line)?.[1];
      if (name) contextNames.add(name);
    }
  }
  const ledger = [...report.ledger];
  const mapped = new Set(ledger.map(item => item.original));
  const used = new Set([...(report.sourceSymbolNames ?? []), ...contextNames, ...ledger.map(item => item.atom)].map(name => name.toUpperCase()));
  let ordinal = 0;
  for (const original of [...contextNames].filter(name => name.length > 8 && !mapped.has(name)).sort()) {
    let atom;
    do { atom = `G${(ordinal++).toString(36).toUpperCase().padStart(7, "0")}`; } while (used.has(atom));
    used.add(atom);
    ledger.push({ original, atom, permanentAtom: atom, migrationKind: "generated-context", localScope: null });
  }
  report = { ...report, ledger };
  const input = [], definitions = {}, sourceSymbols = new Map(), limits = {};
  const reverse = new Map([...symbolMapFromLedger(report.ledger)].map(([name, alias]) => [alias.toUpperCase(), name]));
  flattenTranslatedEntry(report, entry, {
    overrides, onLine: line => {
      input.push(line);
      const name = /^\s*([A-Za-z_][A-Za-z0-9_]*)(?:\s*:|\s+EQU\b)/i.exec(line.text)?.[1];
      if (name) sourceSymbols.set(name.toUpperCase(), reverse.get(name.toUpperCase()) ?? name);
      const limit = /;@ATOM-PROOF-LIMIT (\w+) (\d+)/.exec(line.text);
      if (limit) limits[limit[1]] = Number(limit[2]);
    }, onDefine: (name, value) => { definitions[name] = value; },
  });
  const lines = scheduleEquates(input);
  const parts = [], origins = [];
  let chunk = "", mapping = [];
  function emit() {
    const bytes = new TextEncoder().encode(chunk);
    parts.push({ ordinal: parts.length, bank: 0, logicalIdentity: `${entry}#${parts.length}`, originalBytes: bytes, compilerBytes: bytes });
    origins.push(mapping); chunk = ""; mapping = [];
  }
  for (const line of lines) {
    const bytes = Buffer.byteLength(line.text + "\n");
    if (bytes > 0xffff) throw new Error(`${line.file}:${line.line}: Atom source line exceeds part capacity`);
    if (Buffer.byteLength(chunk) + bytes > 0xffff) emit();
    mapping.push({ offset: Buffer.byteLength(chunk), file: line.file, line: line.line });
    chunk += line.text + "\n";
  }
  if (chunk) emit();
  for (const item of report.ledger) {
    if (/^[_\.]/.test(item.original) && item.localScope && sourceSymbols.has(item.atom.toUpperCase())) {
      sourceSymbols.set(item.atom.toUpperCase(), `${item.localScope.anchor}.${item.original}`);
    }
  }
  return { parts, origins, definitions, limits, sourceSymbols, aliases: symbolMapFromLedger(report.ledger) };
}

export async function assembleAtomSource(entry, options = {}) {
  const source = prepareAtomSource(entry, options);
  let result;
  try {
    result = await assembleResolvedAtomProject({ parts: source.parts }, {
      target: options.target ?? { start: 0, capacity: 0xffff },
      maxInstructions: 1_000_000_000, maxCycles: 10_000_000_000,
      nativeMemoryLayout: { symbolStart: 0x4100, symbolEnd: 0xc000, pendingStart: 0xc000, pendingEnd: 0xe000, partDescriptors: 0xe000 },
    });
  } catch (cause) {
    const origin = source.origins[cause.native?.part]?.findLast(item => item.offset <= cause.native.offset);
    throw new Error(`${origin ? `${origin.file}:${origin.line}` : entry}: ${cause.message}`, { cause });
  }
  const nativeSymbols = new Map(result.generation.symbols.map(symbol => [symbol.name, symbol.value]));
  const labels = new Map(writeAtomD8({ parts: source.parts }, result.generation).symbols
    .filter(symbol => symbol.address !== undefined)
    .map(symbol => [symbol.name, symbol.address]));
  const symbols = { ...source.definitions };
  const addresses = {};
  for (const [alias, original] of source.sourceSymbols) {
    if (!nativeSymbols.has(alias)) throw new Error(`${entry}: Atom omitted symbol ${original}`);
    symbols[original] = nativeSymbols.get(alias);
    if (labels.has(alias)) addresses[original] = labels.get(alias);
  }
  Object.assign(symbols, source.limits);
  return { hex: sparseIntelHex(result.generation), symbols, addresses, generation: result.generation, source, instructions: result.execution.instructions };
}
