/**
 * The integer runtime helpers against the host's arithmetic: edge values
 * (0, 1, -1, the extremes, values around each byte and word boundary) in
 * every pairing, then random operands, for every 32-bit helper and for the
 * 16-bit multiply and divides.
 */
import { assertEquals } from "@std/assert";
import type { Blob } from "../ref/compile/emit.ts";
import {
  type Case,
  flagsResult,
  hex8,
  rng,
  runHelpers,
} from "./harness/helper-driver.ts";

const OPS = [
  0x028, // 0 ADD32
  0x029, // 1 SUB32
  0x02d, // 2 MUL32
  0x02e, // 3 DIV32U: quotient, then remainder
  0x02f, // 4 DIV32S: quotient, then remainder
  0x02a, // 5 CMP32U
  0x02b, // 6 CMP32S
  0x02c, // 7 NEG32
  0x030, // 8 AND32
  0x031, // 9 OR32
  0x032, // 10 XOR32
  0x033, // 11 SHL32 by b's low byte
  0x034, // 12 SHR32U
  0x035, // 13 SHR32S
];

const count = (code: Blob) => code.u8(0xdd, 0x7e, 5); // LD A,(IX+5)
const quotientThenRemainder = (code: Blob, print: number) => {
  code.u8(0xcd); // CALL print: the quotient
  code.labelOperand(print);
  code.u8(0xd9); // EXX: the remainder is printed next
};

const OPERATIONS = OPS.map((ordinal, i) => ({
  ordinal,
  before: i >= 11 ? count : undefined,
  after: i === 3 || i === 4
    ? quotientThenRemainder
    : i === 5 || i === 6
    ? flagsResult
    : undefined,
}));

const M = 1n << 32n;
const u = (n: number) => BigInt(n >>> 0);
const s = (n: number) => BigInt(n | 0);
const w = (n: bigint) => Number(((n % M) + M) % M);

/** The lines a case prints, or undefined for one that would trap. */
function expect(c: Case): string[] | undefined {
  const [a, b] = [c.a, c.b];
  switch (c.op) {
    case 0:
      return [hex8(w(u(a) + u(b)))];
    case 1:
      return [hex8(w(u(a) - u(b)))];
    case 2:
      return [hex8(w(u(a) * u(b)))];
    case 3:
      if (b === 0) return undefined;
      return [hex8(w(u(a) / u(b))), hex8(w(u(a) % u(b)))];
    case 4: {
      if (b === 0) return undefined;
      if ((a | 0) === -2147483648 && (b | 0) === -1) {
        return [hex8(a), hex8(0)]; // wraps to itself (spec 9.8)
      }
      return [hex8(w(s(a) / s(b))), hex8(w(s(a) % s(b)))];
    }
    case 5:
      return [hex8((u(a) < u(b) ? 1 : 0) | (a === b ? 2 : 0))];
    case 6:
      return [hex8((s(a) < s(b) ? 1 : 0) | (a === b ? 2 : 0))];
    case 7:
      return [hex8(w(-u(a)))];
    case 8:
      return [hex8(w(u(a) & u(b)))];
    case 9:
      return [hex8(w(u(a) | u(b)))];
    case 10:
      return [hex8(w(u(a) ^ u(b)))];
    case 11: {
      const n = b & 0xff;
      return [hex8(n >= 32 ? 0 : w(u(a) << BigInt(n)))];
    }
    case 12: {
      const n = b & 0xff;
      return [hex8(n >= 32 ? 0 : w(u(a) >> BigInt(n)))];
    }
    case 13: {
      const n = Math.min(b & 0xff, 32);
      return [hex8(w(s(a) >> BigInt(n)))];
    }
  }
}

const EDGES = [
  0,
  1,
  2,
  3,
  7,
  10,
  0xff,
  0x100,
  0x7fff,
  0x8000,
  0xffff,
  0x10000,
  0x12345,
  0xffffff,
  0x1000000,
  0x7fffffff,
  0x80000000,
  0x80000001,
  0xfffffffe,
  0xffffffff,
  0xdeadbeef,
];
const COUNTS = [0, 1, 7, 8, 15, 16, 17, 24, 31, 32, 33, 40, 255];

function cases(): Case[] {
  const out: Case[] = [];
  const add = (op: number, a: number, b: number) => {
    const c = { op, a: a >>> 0, b: b >>> 0 };
    if (expect(c)) out.push(c);
  };
  for (let op = 0; op < 14; op += 1) {
    if (op >= 11) {
      for (const a of EDGES) for (const n of COUNTS) add(op, a, n);
    } else if (op === 7) {
      for (const a of EDGES) add(op, a, 0);
    } else {
      for (const a of EDGES) for (const b of EDGES) add(op, a, b);
    }
  }
  const next = rng(2024);
  for (let i = 0; i < 1400; i += 1) {
    const op = next() % 14;
    // Mix full-width operands with short ones, which divide more often.
    const pick = () => next() % 3 === 0 ? next() >>> (next() % 32) : next();
    add(op, pick(), op >= 11 ? next() % 40 : pick());
  }
  return out;
}

Deno.test("32-bit helpers agree with host arithmetic", async () => {
  const table = cases();
  // In pieces, so each table fits beside the code in one image.
  const lines: string[] = [];
  for (let i = 0; i < table.length; i += 2500) {
    lines.push(...await runHelpers(OPERATIONS, table.slice(i, i + 2500)));
  }
  const failures: string[] = [];
  let at = 0;
  for (const c of table) {
    const want = expect(c)!;
    const got = lines.slice(at, at + want.length);
    at += want.length;
    if (got.join() !== want.join()) {
      failures.push(
        `op ${c.op} a=${hex8(c.a)} b=${hex8(c.b)}: got ${got}, want ${want}`,
      );
    }
  }
  assertEquals(failures.slice(0, 12), []);
  assertEquals(lines.length, at);
  console.log(`  ${table.length} cases`);
});

// The 16-bit helpers take HL and DE and return HL (and DE, the remainder).
const right16 = (code: Blob) => code.u8(0xd9, 0xe5, 0xd9, 0xd1); // EXX; PUSH HL; EXX; POP DE
const widen = (code: Blob) => code.u8(0x11, 0, 0); // LD DE,0
const quotient16 = (code: Blob, print: number) => {
  code.u8(0xd5, 0x11, 0, 0, 0xcd); // PUSH DE; LD DE,0; CALL print
  code.labelOperand(print);
  code.u8(0xe1, 0x11, 0, 0); // POP HL; LD DE,0: the remainder next
};
const OPS16 = [
  { ordinal: 0x016, before: right16, after: widen }, // MUL16
  { ordinal: 0x017, before: right16, after: quotient16 }, // DIV16
  { ordinal: 0x018, before: right16, after: quotient16 }, // DIV16S
];

function expect16(c: Case): string[] | undefined {
  const [a, b] = [c.a & 0xffff, c.b & 0xffff];
  const sa = (a << 16) >> 16, sb = (b << 16) >> 16;
  switch (c.op) {
    case 0:
      return [hex8(Number((BigInt(a) * BigInt(b)) & 0xffffn))];
    case 1:
      return b === 0 ? undefined : [hex8(Math.floor(a / b)), hex8(a % b)];
    case 2:
      if (b === 0) return undefined;
      if (sa === -32768 && sb === -1) return [hex8(0x8000), hex8(0)];
      return [hex8(Math.trunc(sa / sb) & 0xffff), hex8((sa % sb) & 0xffff)];
  }
}

Deno.test("16-bit helpers agree with host arithmetic", async () => {
  const edges = [
    0,
    1,
    2,
    3,
    7,
    10,
    0xff,
    0x100,
    0x7ffe,
    0x7fff,
    0x8000,
    0x8001,
    0xfffe,
    0xffff,
    0x1234,
  ];
  const table: Case[] = [];
  for (let op = 0; op < 3; op += 1) {
    for (const a of edges) {
      for (const b of edges) {
        if (expect16({ op, a, b })) table.push({ op, a, b });
      }
    }
  }
  const next = rng(16);
  while (table.length < 1500) {
    const c = {
      op: next() % 3,
      a: next() & 0xffff,
      b: next() >>> (next() % 32) & 0xffff,
    };
    if (expect16(c)) table.push(c);
  }
  const lines = await runHelpers(OPS16, table);
  const failures: string[] = [];
  let at = 0;
  for (const c of table) {
    const want = expect16(c)!;
    const got = lines.slice(at, at + want.length);
    at += want.length;
    if (got.join() !== want.join()) {
      failures.push(`op ${c.op} a=${c.a} b=${c.b}: got ${got}, want ${want}`);
    }
  }
  assertEquals(failures.slice(0, 12), []);
  assertEquals(lines.length, at);
});
