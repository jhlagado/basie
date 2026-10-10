/**
 * The Basie tokenizer (spec chapter 3). One source part at a time, one byte
 * of lookahead, no backtracking.
 */

export const KEYWORDS = [
  "and",
  "as",
  "assert",
  "boolean",
  "case",
  "const",
  "continue",
  "else",
  "elseif",
  "end",
  "enum",
  "exit",
  "f32",
  "fail",
  "fails",
  "false",
  "for",
  "forward",
  "handle",
  "i16",
  "i32",
  "i8",
  "if",
  "include",
  "mod",
  "move",
  "new",
  "none",
  "not",
  "or",
  "pool",
  "private",
  "record",
  "return",
  "select",
  "shl",
  "shr",
  "some",
  "step",
  "string",
  "sub",
  "to",
  "true",
  "u16",
  "u32",
  "u8",
  "until",
  "var",
  "while",
  "xor",
] as const;
export type Keyword = (typeof KEYWORDS)[number];
const KEYWORD_SET = new Set<string>(KEYWORDS);

export const PUNCTUATION = [
  "(",
  ")",
  "[",
  "]",
  ",",
  ".",
  "?",
  "+",
  "-",
  "*",
  "/",
  "=",
  "<>",
  "<",
  "<=",
  ">",
  ">=",
] as const;
export type Punctuation = (typeof PUNCTUATION)[number];

export type Position = {
  part: number;
  offset: number;
  line: number;
  column: number;
};

export type TokenBody =
  | { kind: "name"; text: string }
  | { kind: "keyword"; text: Keyword }
  | { kind: "number"; value: number }
  | { kind: "float"; value: number }
  | { kind: "character"; value: number }
  | { kind: "string"; bytes: Uint8Array }
  | { kind: "punct"; text: Punctuation }
  | { kind: "newline" }
  | { kind: "eof" };

export type Token = Position & { end: number } & TokenBody;

export class LexError extends Error {
  constructor(
    public readonly code: string,
    public readonly position: Position,
    public readonly text: string,
  ) {
    super(`${code} at ${position.line}:${position.column}: ${text}`);
  }
}

const isLetter = (b: number) =>
  (b >= 0x41 && b <= 0x5a) || (b >= 0x61 && b <= 0x7a);
const isDigit = (b: number) => b >= 0x30 && b <= 0x39;
const isHex = (b: number) =>
  isDigit(b) || (b >= 0x41 && b <= 0x46) || (b >= 0x61 && b <= 0x66);
const hexValue = (b: number) => isDigit(b) ? b - 0x30 : (b | 0x20) - 0x57;

const U32_MAX = 0xffffffff;

/**
 * Tokenize one source part. `final` marks the last part, which ends with
 * EOF; other parts end at their boundary NEWLINE (spec §3.4, §4.3).
 */
export function tokenize(
  source: Uint8Array,
  part = 0,
  final = true,
): Token[] {
  const tokens: Token[] = [];
  let i = 0;
  let line = 1;
  let lineStart = 0;
  const delimiters: { open: number; at: Position }[] = [];
  let lineHasToken = false;

  const pos = (offset = i): Position => ({
    part,
    offset,
    line,
    column: offset - lineStart + 1,
  });
  const fail = (code: string, message: string, offset = i): never => {
    throw new LexError(code, pos(offset), message);
  };
  const push = (start: Position, t: TokenBody) => {
    tokens.push({ ...start, end: i, ...t } as Token);
    lineHasToken = true;
  };
  const peek = (k = 0) => (i + k < source.length ? source[i + k] : -1);

  while (i < source.length) {
    const b = source[i];
    const start = pos();
    // Line endings.
    if (b === 0x0a || b === 0x0d) {
      if (b === 0x0d && peek(1) !== 0x0a) fail("lone-cr", "CR without LF");
      const width = b === 0x0d ? 2 : 1;
      i += width;
      if (delimiters.length === 0 && lineHasToken) {
        tokens.push({ ...start, end: i, kind: "newline" });
      }
      if (delimiters.length === 0) lineHasToken = false;
      line += 1;
      lineStart = i;
      continue;
    }
    if (b === 0x20 || b === 0x09) {
      i += 1;
      continue;
    }
    if (b < 0x20 || b > 0x7e) fail("bad-byte", `byte $${b.toString(16)}`);
    // Comments.
    if (b === 0x2f && peek(1) === 0x2f) {
      while (i < source.length && source[i] !== 0x0a && source[i] !== 0x0d) {
        const c = source[i];
        if (c !== 0x09 && (c < 0x20 || c > 0x7e)) {
          fail("bad-byte", `byte $${c.toString(16)}`);
        }
        i += 1;
      }
      continue;
    }
    if (isLetter(b)) {
      while (
        i < source.length &&
        (isLetter(source[i]) || isDigit(source[i]) || source[i] === 0x5f)
      ) i += 1;
      const text = new TextDecoder().decode(source.subarray(start.offset, i));
      if (KEYWORD_SET.has(text)) {
        push(start, { kind: "keyword", text: text as Keyword });
      } else push(start, { kind: "name", text });
      continue;
    }
    if (isDigit(b) || b === 0x24 || b === 0x25) {
      push(start, number());
      continue;
    }
    if (b === 0x27 || b === 0x22) {
      const bytes = literal(b);
      if (b === 0x27) {
        if (bytes.length !== 1) {
          fail(
            bytes.length === 0 ? "empty-character" : "long-character",
            "a character literal holds exactly one byte",
            start.offset,
          );
        }
        push(start, { kind: "character", value: bytes[0] });
      } else push(start, { kind: "string", bytes: Uint8Array.from(bytes) });
      continue;
    }
    const two = String.fromCharCode(b) +
      (peek(1) >= 0 ? String.fromCharCode(peek(1)) : "");
    const p = (["<>", "<=", ">="] as const).find((x) => x === two) ??
      (PUNCTUATION as readonly string[]).find((x) =>
        x.length === 1 && x.charCodeAt(0) === b
      );
    if (!p) fail("bad-character", `unexpected '${String.fromCharCode(b)}'`);
    i += p!.length;
    if (p === "(" || p === "[") delimiters.push({ open: b, at: start });
    if (p === ")" || p === "]") {
      const open = delimiters.pop();
      if (!open) {
        fail("unmatched-delimiter", `'${p}' with no opener`, start.offset);
      }
      if ((open!.open === 0x28) !== (p === ")")) {
        fail(
          "mismatched-delimiter",
          `'${p}' closes '${String.fromCharCode(open!.open)}'`,
          start.offset,
        );
      }
    }
    push(start, { kind: "punct", text: p as Punctuation });
  }
  if (delimiters.length > 0) {
    const open = delimiters.at(-1)!;
    throw new LexError(
      "open-delimiter",
      open.at,
      "delimiter still open at the end of the part",
    );
  }
  if (lineHasToken) tokens.push({ ...pos(), end: i, kind: "newline" });
  if (final) tokens.push({ ...pos(), end: i, kind: "eof" });
  return tokens;

  function number(): TokenBody {
    const start = i;
    const b = source[i];
    const malformed = (why: string): never =>
      fail("malformed-number", why, start);
    const trailing = () => {
      const c = peek();
      if (c >= 0 && (isLetter(c) || c === 0x5f || isDigit(c))) {
        malformed("a number can't run into a name or digit");
      }
    };
    if (b === 0x24 || b === 0x25) {
      const radix = b === 0x24 ? 16 : 2;
      const limit = radix === 16 ? 8 : 32;
      i += 1;
      let value = 0;
      let digits = 0;
      while (true) {
        const c = peek();
        const ok = radix === 16 ? isHex(c) : c === 0x30 || c === 0x31;
        if (!ok) break;
        value = value * radix + (radix === 16 ? hexValue(c) : c - 0x30);
        digits += 1;
        i += 1;
      }
      if (digits === 0) malformed("a prefix needs at least one digit");
      if (digits > limit) malformed("too many digits");
      trailing();
      return { kind: "number", value };
    }
    while (isDigit(peek())) i += 1;
    let isFloat = false;
    if (peek() === 0x2e && isDigit(peek(1))) {
      isFloat = true;
      i += 1;
      while (isDigit(peek())) i += 1;
    } else if (peek() === 0x2e) {
      malformed("a decimal point needs a digit after it");
    }
    if (peek() === 0x65 || peek() === 0x45) {
      const save = i;
      i += 1;
      if (peek() === 0x2b || peek() === 0x2d) i += 1;
      if (!isDigit(peek())) {
        i = save;
        malformed("an exponent needs digits");
      }
      while (isDigit(peek())) i += 1;
      isFloat = true;
    }
    trailing();
    const text = new TextDecoder().decode(source.subarray(start, i));
    if (isFloat) {
      const value = parseF32(text);
      if (value === undefined) malformed("beyond the largest f32");
      return { kind: "float", value: value! };
    }
    const value = Number(text);
    if (value > U32_MAX) malformed("beyond the range of u32");
    return { kind: "number", value };
  }

  function literal(quote: number): number[] {
    const start = i;
    i += 1;
    const out: number[] = [];
    while (true) {
      const c = peek();
      if (c < 0 || c === 0x0a || c === 0x0d) {
        fail("unterminated-literal", "no closing quote", start);
      }
      if (c === quote) {
        i += 1;
        return out;
      }
      if (c === 0x5c) {
        const e = peek(1);
        const simple: Record<number, number> = {
          0x30: 0,
          0x6e: 10,
          0x72: 13,
          0x74: 9,
          0x27: 0x27,
          0x22: 0x22,
          0x5c: 0x5c,
        };
        if (e in simple) {
          out.push(simple[e]);
          i += 2;
        } else if (e === 0x78 && isHex(peek(2)) && isHex(peek(3))) {
          out.push(hexValue(peek(2)) * 16 + hexValue(peek(3)));
          i += 4;
        } else fail("bad-escape", "unknown or incomplete escape");
        continue;
      }
      if (c < 0x20 || c > 0x7e) {
        if (c !== 0x09) fail("bad-byte", `byte $${c.toString(16)}`);
        fail("bad-byte", "a tab must be written \\t in a literal");
      }
      out.push(c);
      i += 1;
    }
  }
}

/**
 * The nearest f32 to a decimal literal, ties to even, with values below the
 * smallest normal flushed to zero (D7). Undefined if beyond the largest f32.
 */
export function parseF32(text: string): number | undefined {
  const m = text.match(/^(\d+)(?:\.(\d+))?(?:[eE]([+-]?\d+))?$/)!;
  const digits = (m[1] + (m[2] ?? "")).replace(/^0+(?=\d)/, "");
  const exp10 = Number(m[3] ?? 0) - (m[2]?.length ?? 0);
  const n = BigInt(digits);
  if (n === 0n) return 0;
  // Bound absurd exponents before building big numbers.
  if (exp10 > 60) return undefined;
  if (exp10 + digits.length < -60) return 0;
  let num = n, den = 1n;
  if (exp10 >= 0) num *= 10n ** BigInt(exp10);
  else den = 10n ** BigInt(-exp10);
  // Find e with 2^23 <= num/den / 2^e < 2^24.
  let e = num.toString(2).length - den.toString(2).length - 23;
  const scaled = (k: number) =>
    k >= 0 ? [num, den << BigInt(k)] : [num << BigInt(-k), den];
  let [a, b] = scaled(e);
  if (a < (b << 23n)) {
    e -= 1;
    [a, b] = scaled(e);
  } else if (a >= (b << 24n)) {
    e += 1;
    [a, b] = scaled(e);
  }
  let q = a / b;
  const r = a - q * b;
  if (r * 2n > b || (r * 2n === b && (q & 1n) === 1n)) q += 1n;
  if (q === 1n << 24n) {
    q >>= 1n;
    e += 1;
  }
  // q in [2^23, 2^24), value = q * 2^e. Normal range: 2^-126 .. (2^24-1)*2^104.
  if (e + 23 > 127) return undefined;
  if (e + 23 < -126) return 0;
  return Number(q) * 2 ** e;
}
