/**
 * The message table (design decision D39; toolchain §7.3): every diagnostic
 * code of the compiler and the linker, its stable number, and its text. This
 * table is the single source: `tools/msgfile.ts` generates `BASIE.MSG` and the
 * code tables of docs/diagnostics.md from it, and a test checks that every
 * code the toolchain raises is here.
 *
 * Numbers are append-only within their range: a number is never reused or
 * renumbered. `^1` and `^2` are replaced by arguments the program supplies.
 */

export type Message = {
  number: number;
  code: string;
  text: string;
  /** The register section the code belongs to. */
  group: Group;
};

export type Group =
  | "Lexical (Chapter 3)"
  | "Structure and names (Chapters 4 and 5)"
  | "Declarations and types (Chapters 6 and 8)"
  | "Expressions and statements (Chapters 9 to 12)"
  | "Ownership and routines (Chapters 7, 10, 13 and 14)"
  | "Capacity and internal"
  | "Linker";

const LEX: Group = "Lexical (Chapter 3)";
const NAMES: Group = "Structure and names (Chapters 4 and 5)";
const DECL: Group = "Declarations and types (Chapters 6 and 8)";
const EXPR: Group = "Expressions and statements (Chapters 9 to 12)";
const OWN: Group = "Ownership and routines (Chapters 7, 10, 13 and 14)";
const CAP: Group = "Capacity and internal";
const LINK: Group = "Linker";

/** [number, code, text, group] */
const TABLE: [number, string, string, Group][] = [
  // 1-19: lexical
  [1, "bad-byte", "A byte the source may not contain", LEX],
  [2, "lone-cr", "A carriage return without a line feed", LEX],
  [3, "bad-character", "A character that begins no token", LEX],
  [4, "malformed-number", "A malformed or out-of-range number", LEX],
  [5, "bad-escape", "An unknown or incomplete escape", LEX],
  [6, "empty-character", "An empty character literal", LEX],
  [7, "long-character", "A character literal holds one byte", LEX],
  [8, "unterminated-literal", "A literal without its closing quote", LEX],
  [9, "unmatched-delimiter", "A closing bracket with no opening one", LEX],
  [10, "mismatched-delimiter", "A closing bracket of the wrong kind", LEX],
  [11, "open-delimiter", "A bracket still open at the end of the part", LEX],
  // 20-39: structure and names
  [20, "syntax", "Expected ^1", NAMES],
  [21, "include-position", "include must come before declarations", NAMES],
  [22, "include-cycle", "^1 includes itself", NAMES],
  [23, "include-missing", "^1 not found", NAMES],
  [24, "include-syntax", "include takes one quoted file name", NAMES],
  [25, "missing-main", "No routine named main", NAMES],
  [
    26,
    "bad-main",
    "main takes no parameters, returns nothing and is not private",
    NAMES,
  ],
  [27, "undeclared-name", "^1 is not declared", NAMES],
  [28, "duplicate-name", "^1 is already declared", NAMES],
  [29, "shadowed-name", "^1 would hide a visible name", NAMES],
  [30, "wrong-class", "^1 can't be used here", NAMES],
  [
    31,
    "recursion-needs-forward",
    "^1 is not complete: declare it forward",
    NAMES,
  ],
  [32, "forward-mismatch", "^1 has no matching forward declaration", NAMES],
  [
    33,
    "forward-incomplete",
    "Forward declaration ^1 is never completed",
    NAMES,
  ],
  // 40-69: declarations and types
  [
    40,
    "conversion-required",
    "^1 doesn't convert to ^2 without a conversion",
    DECL,
  ],
  [41, "type-mismatch", "A ^1 is required", DECL],
  [42, "out-of-range", "The value doesn't fit ^1", DECL],
  [43, "constant-needs-type", "This constant needs a type", DECL],
  [
    44,
    "no-definite-type",
    "The initializer has no definite type: write the type",
    DECL,
  ],
  [45, "assertion-false", "The assertion is false", DECL],
  [46, "pool-needs-record", "A pool holds records", DECL],
  [
    47,
    "handle-must-be-optional",
    "A field, element or program variable of handle type must be optional",
    DECL,
  ],
  [48, "empty-record", "A record needs at least one field", DECL],
  [49, "static-initializer", "^1 can't have a static initializer", DECL],
  [50, "needs-initializer", "A non-optional handle needs an initializer", DECL],
  [51, "not-constant", "A constant expression is required", DECL],
  [52, "pool-incomplete", "Pool ^1 is only forward-declared", DECL],
  [53, "conversion-unavailable", "There is no conversion to ^1", DECL],
  [54, "var-parameter", "var is not allowed on a ^1 parameter", DECL],
  [55, "from-clause", "^1 is not an aggregate parameter", DECL],
  // 70-99: expressions and statements
  [
    70,
    "mixed-operands",
    "^1 and ^2 don't widen to each other: convert one",
    EXPR,
  ],
  [71, "chained-comparison", "Comparisons don't chain: use and", EXPR],
  [72, "index-type", "An index must be u8 or u16", EXPR],
  [73, "division-by-zero", "Division by a constant zero", EXPR],
  [74, "not-writable", "^1 is read-only", EXPR],
  [75, "duplicate-case", "This label overlaps an earlier one", EXPR],
  [76, "no-such-field", "No field ^1", EXPR],
  [77, "not-indexable", "^1 can't be indexed", EXPR],
  [78, "no-value", "^1 returns nothing", EXPR],
  [79, "narrowing", "The value doesn't fit ^1", EXPR],
  [80, "float-overflow", "The result exceeds f32", EXPR],
  [81, "bounds", "Index ^1 is out of range", EXPR],
  [82, "outside-loop", "^1 needs an enclosing loop", EXPR],
  [83, "loop-counter", "The counter must be an integer local", EXPR],
  [
    84,
    "loop-step",
    "The step must be a nonzero constant that fits the counter",
    EXPR,
  ],
  [
    85,
    "missing-return",
    "^1 can reach its end without returning a value",
    EXPR,
  ],
  [86, "return-form", "Wrong return for this routine", EXPR],
  // 100-129: ownership and routines
  [100, "needs-move", "An owning handle is moved, not copied: write move", OWN],
  [101, "owning-copy", "^1 owns handles and can't be copied", OWN],
  [102, "use-after-move", "^1 may have been moved", OWN],
  [103, "statement-rule", "^1 is used and moved in one statement", OWN],
  [
    104,
    "alias-escapes",
    "A result can't refer to a local, or to a parameter not named in from",
    OWN,
  ],
  [
    105,
    "optional-handle",
    "Test an optional handle with select before use",
    OWN,
  ],
  [106, "not-owner", "^1 is not an owning handle location", OWN],
  [
    107,
    "lease",
    "A lease comes from the routine's own owning local or parameter",
    OWN,
  ],
  [108, "slot-holder", "This location can't be a slot-holder", OWN],
  [
    109,
    "loop-moves-owner",
    "^1 may have been moved when the loop repeats",
    OWN,
  ],
  [110, "id-ambiguous", "^1 belongs to more than one pool", OWN],
  [111, "arity", "^1 takes ^2 arguments", OWN],
  [
    112,
    "not-failable",
    "else fail and handle follow a call to a routine that fails",
    OWN,
  ],
  [113, "failure-unconsumed", "^1 fails: add else fail or handle", OWN],
  [114, "handle-destination", "handle needs a writable u8 variable", OWN],
  [115, "move-position", "move can't appear in ^1", OWN],
  // 190-199: capacity and internal
  [190, "capacity", "A compiler capacity was exceeded: ^1", CAP],
  // The native compiler's own refusals of programs the reference accepts
  // (native compiler plan §3): constructs not yet brought across, and the
  // exact values its 16-bit folding cannot hold.
  [
    191,
    "native-unsupported",
    "The native compiler doesn't compile this yet",
    CAP,
  ],
  [
    192,
    "native-exact",
    "The native compiler holds exact values from 0 to 65,535 only",
    CAP,
  ],
  [199, "internal", "Internal compiler error: ^1", CAP],
  // 200-239: linker (linker §9)
  [200, "L-FORMAT", "^1: bad magic or unsupported version", LINK],
  [201, "L-COMPAT", "Program and library are not compatible", LINK],
  [202, "L-STAMP", "Program streams from different compilations", LINK],
  [203, "L-OPTION", "An option the profile doesn't support", LINK],
  [204, "L-OUTPUT", "An output kind the profile doesn't support", LINK],
  [205, "L-ORDINAL", "Ordinal ^1 out of range or defined twice", LINK],
  [206, "L-RESERVED", "A reserved kind, form or value", LINK],
  [207, "L-BLOB", "A malformed blob record", LINK],
  [208, "L-REFERENCE", "A malformed reference", LINK],
  [209, "L-ALIAS", "A malformed alias", LINK],
  [210, "L-ENTRY", "A missing, repeated or invalid entry", LINK],
  [211, "L-LIMITS", "A missing, repeated or misplaced limits record", LINK],
  [212, "L-STARTUP", "A missing, repeated or invalid startup blob", LINK],
  [213, "L-UNDEFINED", "Ordinal ^1 is referenced but never defined", LINK],
  [214, "L-TRUNCATED", "^1: missing trailer, bad CRC or wrong length", LINK],
  [215, "L-CAP-TABLES", "The linker's tables don't fit in memory", LINK],
  [216, "L-FIT-IMAGE", "The image exceeds the image limit", LINK],
  [217, "L-FIT-MEMORY", "Image, data and stack exceed the address space", LINK],
  [218, "L-FIT-RAM", "Data and stack exceed RAM", LINK],
  [
    219,
    "L-FIT-NOMINAL",
    "The program may not fit a typical machine",
    LINK,
  ],
  [220, "L-RANGE", "A reference value is out of range", LINK],
  [221, "L-PLACEHOLDER", "Nonzero placeholder bytes", LINK],
  [222, "L-IO", "^1: read or write failed, or the disk is full", LINK],
  [223, "L-USAGE", "Usage: BLINK NAME [options]", LINK],
  [224, "L-COMMAND", "^1: a bad or repeated option", LINK],
  [225, "L-MISSING", "^1 not found", LINK],
];

export const MESSAGES: Message[] = TABLE.map(([number, code, text, group]) => ({
  number,
  code,
  text,
  group,
}));

const BY_CODE = new Map(MESSAGES.map((m) => [m.code, m]));
const BY_NUMBER = new Map(MESSAGES.map((m) => [m.number, m]));

export function messageFor(code: string): Message | undefined {
  return BY_CODE.get(code);
}

export function messageNumber(code: string): number | undefined {
  return BY_CODE.get(code)?.number;
}

/** The text of a message with its arguments substituted. */
export function formatMessage(number: number, args: string[] = []): string {
  const m = BY_NUMBER.get(number);
  if (!m) {
    return `Message ${number}${args.length ? ": " + args.join(", ") : ""}`;
  }
  return m.text.replace(/\^([12])/g, (_, n) => args[Number(n) - 1] ?? "?");
}

/**
 * BASIE.MSG (toolchain §7.3): magic BSIM, version 1.0, a u16 count, a table
 * of u16 offsets indexed by message number (0 for a number with no message),
 * then each message as a length byte and its text.
 */
export function messageFile(): Uint8Array {
  const highest = Math.max(...MESSAGES.map((m) => m.number));
  const count = highest + 1;
  const header = 4 + 2 + 2;
  const tableBytes = count * 2;
  const bodies: number[] = [];
  const offsets = new Array(count).fill(0);
  for (const m of [...MESSAGES].sort((a, b) => a.number - b.number)) {
    const text = new TextEncoder().encode(m.text);
    if (text.length > 255) throw new Error(`message ${m.number} is too long`);
    offsets[m.number] = header + tableBytes + bodies.length;
    bodies.push(text.length, ...text);
  }
  const out = [..."BSIM"].map((c) => c.charCodeAt(0));
  out.push(1, 0, count & 0xff, count >> 8);
  for (const o of offsets) out.push(o & 0xff, o >> 8);
  out.push(...bodies);
  return Uint8Array.from(out);
}

/** Read a message back from a BASIE.MSG image, as the native toolchain does. */
export function readMessage(
  file: Uint8Array,
  number: number,
): string | undefined {
  const magic = String.fromCharCode(...file.subarray(0, 4));
  if (magic !== "BSIM") throw new Error("not a message file");
  const count = file[6] | (file[7] << 8);
  if (number >= count) return undefined;
  const offset = file[8 + number * 2] | (file[9 + number * 2] << 8);
  if (offset === 0) return undefined;
  const length = file[offset];
  return new TextDecoder().decode(
    file.subarray(offset + 1, offset + 1 + length),
  );
}
