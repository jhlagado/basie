/**
 * The f32 runtime helpers against the host's IEEE single arithmetic: a
 * table of operations runs on the Z80 under the CP/M harness and prints each
 * result, which must equal Math.fround's.
 */
import { assertEquals } from "@std/assert";
import { Blob } from "../ref/compile/emit.ts";
import { Helper } from "../ref/compile/helpers.ts";
import { runtimeLibrary } from "../ref/compile/index.ts";
import { link } from "../ref/link/link.ts";
import { defaultHeader } from "../ref/object/program.ts";
import { Kind } from "../ref/object/types.ts";
import { runCom } from "./harness/cpm.ts";

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

type Case = { op: number; a: number; b: number };

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
const MAX = 3.4028234663852886e38;
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

/** A deterministic generator. */
function rng(seed: number) {
  let s = seed >>> 0;
  return () => {
    s = (s * 1664525 + 1013904223) >>> 0;
    return s;
  };
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

/** The driver: runs every case and prints its result as 8 hex digits. */
function driver(table: Case[]): { records: unknown[]; bytes: Uint8Array } {
  const code = new Blob(0x400, Kind.code, "main");
  const data = new Blob(0x401, Kind.rodata, "table");
  for (const c of table) {
    data.u8(c.op);
    data.u32(c.a);
    data.u32(c.b);
  }
  data.u8(0xff);
  const next = code.newLabel();
  const done = code.newLabel();
  const print = code.newLabel();
  const hex2 = code.newLabel();
  const skipOps: number[] = [];
  code.u8(0xdd, 0x21); // LD IX,table
  code.abs16(0x401);
  code.defineLabel(next);
  code.u8(0xdd, 0x7e, 0); // LD A,(IX+0)
  code.u8(0xfe, 0xff); // CP $FF
  code.jpIf(0xca, done);
  code.u8(0xf5); // PUSH AF
  code.u8(0xdd, 0x6e, 5, 0xdd, 0x66, 6, 0xdd, 0x5e, 7, 0xdd, 0x56, 8); // b into DEHL
  code.u8(0xd9); // EXX
  code.u8(0xdd, 0x6e, 1, 0xdd, 0x66, 2, 0xdd, 0x5e, 3, 0xdd, 0x56, 4); // a into DEHL
  code.u8(0xf1); // POP AF
  // dispatch
  const after = code.newLabel();
  OPS.forEach((ordinal, i) => {
    const skip = code.newLabel();
    skipOps.push(skip);
    code.u8(0xfe, i); // CP i
    code.jpIf(0xc2, skip);
    code.callBlob(ordinal);
    if (ordinal === F.FCMP) {
      // DEHL = carry | Z<<1
      code.u8(0xf5); // PUSH AF: keep the flags
      code.u8(0x9f, 0xe6, 0x01, 0x6f); // SBC A,A; AND 1; LD L,A
      code.u8(0xf1); // POP AF
      code.u8(0x3e, 0x00); // LD A,0: flags intact
      const nz = code.newLabel();
      code.jpIf(0xc2, nz);
      code.u8(0x3e, 0x02); // LD A,2
      code.defineLabel(nz);
      code.u8(0xb5, 0x6f, 0x26, 0x00, 0x11, 0x00, 0x00); // OR L; LD L,A; LD H,0; LD DE,0
    }
    code.jp(after);
    code.defineLabel(skip);
  });
  code.defineLabel(after);
  code.u8(0xcd); // CALL print
  code.labelOperand(print);
  code.u8(0x01, 9, 0, 0xdd, 0x09); // LD BC,9; ADD IX,BC
  code.jp(next);
  code.defineLabel(done);
  code.u8(0xb7, 0xc9); // OR A; RET
  // print DEHL as hex, then CRLF
  code.defineLabel(print);
  code.u8(0x7a, 0xcd); // LD A,D; CALL hex2
  code.labelOperand(hex2);
  code.u8(0x7b, 0xcd); // LD A,E
  code.labelOperand(hex2);
  code.u8(0x7c, 0xcd); // LD A,H
  code.labelOperand(hex2);
  code.u8(0x7d, 0xcd); // LD A,L
  code.labelOperand(hex2);
  code.u8(0x3e, 13);
  code.callBlob(Helper.CONOUT);
  code.u8(0x3e, 10);
  code.callBlob(Helper.CONOUT);
  code.u8(0xc9);
  // hex2: print A as two hex digits, preserving HL and DE
  code.defineLabel(hex2);
  code.u8(0xe5, 0xd5, 0xf5); // PUSH HL; PUSH DE; PUSH AF
  code.u8(0x0f, 0x0f, 0x0f, 0x0f); // RRCA x4
  code.u8(0xe6, 0x0f, 0xc6, 0x90, 0x27, 0xce, 0x40, 0x27); // AND $0F; ADD $90; DAA; ADC $40; DAA
  code.callBlob(Helper.CONOUT);
  code.u8(0xf1); // POP AF
  code.u8(0xe6, 0x0f, 0xc6, 0x90, 0x27, 0xce, 0x40, 0x27);
  code.callBlob(Helper.CONOUT);
  code.u8(0xd1, 0xe1, 0xc9); // POP DE; POP HL; RET
  code.finish();
  data.finish();
  const blobs = [code, data];
  const records = blobs.map((b) => ({
    type: "blob" as const,
    kind: b.kind,
    ordinal: b.ordinal,
    size: b.bytes.length,
    root: false,
    align: 0,
    references: b.references,
  }));
  return {
    records: [
      ...records,
      { type: "entry", ordinal: 0x400 },
      { type: "limits", stackReserve: 64, largestFrame: 0, flags: 0 },
    ],
    bytes: Uint8Array.from([...code.bytes, ...data.bytes]),
  };
}

Deno.test("f32 helpers agree with IEEE single arithmetic", async () => {
  const { library, keys } = await runtimeLibrary();
  const table = cases(12345, 400);
  const program = driver(table);
  const dir = {
    header: defaultHeader({ helperKey: keys[0] }),
    records: program.records as never,
    trailer: {
      blobCount: 2,
      byteStreamLength: program.bytes.length,
      highestOrdinal: 0x401,
    },
  };
  const result = link(library, dir, program.bytes, {});
  const run = runCom(result.output, { maxSteps: 50_000_000 });
  const lines = run.output.split("\r\n").filter((l) => l.length > 0);
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
