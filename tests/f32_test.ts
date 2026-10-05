/**
 * The f32 runtime helpers against the host's IEEE single arithmetic: a
 * table of operations runs on the Z80 under the CP/M harness and prints each
 * result, which must equal Math.fround's.
 */
import { assertEquals } from "@std/assert";
import {
  type Case,
  flagsResult,
  rng,
  runHelpers,
} from "./harness/helper-driver.ts";

const F = {
  FADD: 0x03a,
  FSUB: 0x03b,
  FMUL: 0x03c,
  FDIV: 0x03d,
  FCMP: 0x03e,
  I2F: 0x03f,
  U2F: 0x040,
  F2I: 0x041,
  F2U: 0x042,
};
const OPS = [
  F.FADD,
  F.FSUB,
  F.FMUL,
  F.FDIV,
  F.FCMP,
  F.I2F,
  F.U2F,
  F.F2I,
  F.F2U,
];

const bits = (x: number) => {
  const v = new DataView(new ArrayBuffer(4));
  v.setFloat32(0, x, true);
  return v.getUint32(0, true);
};
const float = (u: number) => {
  const v = new DataView(new ArrayBuffer(4));
  v.setUint32(0, u >>> 0, true);
  return v.getFloat32(0, true);
};
const MIN_NORMAL = 1.1754943508222875e-38;
/** The expected bits: Basie's rules are fround with flush to zero. */
function expect(c: Case): number | undefined {
  const flushIn = (x: number) =>
    Math.abs(x) < MIN_NORMAL ? (x < 0 || Object.is(x, -0) ? -0 : 0) : x;
  const [a, b] = [flushIn(float(c.a)), flushIn(float(c.b))];
  const flush = (x: number) =>
    Math.abs(x) < MIN_NORMAL ? (Object.is(x, -0) || x < 0 ? -0 : 0) : x;
  const pack = (x: number) => {
    const r = Math.fround(x);
    if (!Number.isFinite(r)) return undefined; // traps
    return bits(flush(r));
  };
  switch (c.op) {
    case 0:
      return pack(a + b);
    case 1:
      return pack(a - b);
    case 2:
      return pack(a * b);
    case 3:
      return b === 0 ? undefined : pack(a / b);
    case 4:
      return (a < b ? 1 : 0) | (a === b ? 2 : 0);
    case 5:
      return bits(Math.fround(c.a | 0));
    case 6:
      return bits(Math.fround(c.a >>> 0));
    case 7: {
      const t = Math.trunc(a);
      if (t < -2147483648 || t > 2147483647) return undefined;
      return t >>> 0;
    }
    case 8: {
      const t = Math.trunc(a);
      if (t < 0 || t > 4294967295 || (a < 0 && !Object.is(a, -0))) {
        return undefined;
      }
      return t >>> 0;
    }
  }
}

function randomFloatBits(next: () => number): number {
  const r = next();
  const kind = r % 8;
  if (kind === 0) return next() & 0x80000000; // a zero
  if (kind === 1) return bits((next() % 2000) - 1000); // a small integer
  // A random normal: exponent near the middle more often than not.
  const exp = kind < 5 ? 100 + (next() % 56) : 1 + (next() % 254);
  const mant = next() & 0x7fffff;
  const sign = next() & 1 ? 0x80000000 : 0;
  return (sign | (exp << 23) | mant) >>> 0;
}

function cases(seed: number, count: number): Case[] {
  const next = rng(seed);
  const out: Case[] = [];
  while (out.length < count) {
    const op = next() % 9;
    let a: number, b: number;
    if (op === 5 || op === 7 || op === 8) {
      a = op === 5 ? next() : randomFloatBits(next);
      b = 0;
      if (op === 7 || op === 8) {
        // keep most in range
        if (next() % 4 !== 0) {
          a = bits((next() % 2000000) - 1000000 + (next() % 100) / 7);
        }
      }
    } else if (op === 6) {
      a = next();
      b = 0;
    } else {
      a = randomFloatBits(next);
      b = randomFloatBits(next);
      if (op === 0 || op === 1) {
        // make exponents close often, to exercise cancellation and ties
        if (next() % 2 === 0) b = (b & 0x807fffff) | (a & 0x7f800000) | 0;
        b >>>= 0;
      }
    }
    const c = { op, a: a >>> 0, b: b >>> 0 };
    if (expect(c) !== undefined) out.push(c);
  }
  return out;
}

Deno.test("f32 helpers agree with IEEE single arithmetic", async () => {
  const table = cases(12345, 400);
  const lines = await runHelpers(
    OPS.map((ordinal) => ({
      ordinal,
      after: ordinal === F.FCMP ? flagsResult : undefined,
    })),
    table,
  );
  const failures: string[] = [];
  table.forEach((c, i) => {
    const got = lines[i];
    const want = expect(c)!.toString(16).toUpperCase().padStart(8, "0");
    if (got !== want) {
      failures.push(
        `#${i} op ${c.op} a=${c.a.toString(16)} (${float(c.a)}) b=${
          c.b.toString(16)
        } (${float(c.b)}): got ${got}, want ${want}`,
      );
    }
  });
  assertEquals(failures.slice(0, 12), []);
  assertEquals(lines.length, table.length);
});
