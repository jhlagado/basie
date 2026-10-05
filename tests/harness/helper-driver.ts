/**
 * A driver for testing register helpers against host arithmetic: a table of
 * cases (an operation and two 32-bit operands) runs on the Z80 under the
 * CP/M harness, and each result is printed as 8 hex digits on its own line.
 * The left operand arrives in DEHL and the right in DE'HL', as the 32-bit
 * and f32 helpers take them (code generation §4).
 */
import { Blob } from "../../ref/compile/emit.ts";
import { Helper } from "../../ref/compile/helpers.ts";
import { runtimeLibrary } from "../../ref/compile/index.ts";
import { link } from "../../ref/link/link.ts";
import { defaultHeader } from "../../ref/object/program.ts";
import { Kind } from "../../ref/object/types.ts";
import { runCom } from "./cpm.ts";

export type Case = { op: number; a: number; b: number };

export type Operation = {
  ordinal: number;
  /** Code before the call; IX addresses the case (op, a, b at +1, +5). */
  before?: (code: Blob) => void;
  /**
   * Code after the call, before DEHL is printed. `print` is the label of a
   * routine that prints DEHL and a line end, preserving DE'HL'.
   */
  after?: (code: Blob, print: number) => void;
};

/** After a comparison: DEHL = carry | Z << 1, from the flags. */
export function flagsResult(code: Blob): void {
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

function driver(ops: Operation[], table: Case[]) {
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
  const after = code.newLabel();
  ops.forEach((op, i) => {
    const skip = code.newLabel();
    code.u8(0xfe, i); // CP i
    code.jpIf(0xc2, skip);
    op.before?.(code);
    code.callBlob(op.ordinal);
    op.after?.(code, print);
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
  // print DEHL as hex, then CR LF; DE'HL' survive
  code.defineLabel(print);
  for (const r of [0x7a, 0x7b, 0x7c, 0x7d]) { // LD A,D / E / H / L
    code.u8(r, 0xcd);
    code.labelOperand(hex2);
  }
  code.u8(0x3e, 13);
  code.callBlob(Helper.CONOUT);
  code.u8(0x3e, 10);
  code.callBlob(Helper.CONOUT);
  code.u8(0xc9);
  // hex2: print A as two hex digits, preserving HL, DE and the alternates
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
  const records = [code, data].map((b) => ({
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

/** Run the table and return the printed lines, as upper-case hex. */
export async function runHelpers(
  ops: Operation[],
  table: Case[],
): Promise<string[]> {
  const library = await runtimeLibrary();
  const program = driver(ops, table);
  const dir = {
    header: defaultHeader({ helperKey: library.keys[0] }),
    records: program.records as never,
    trailer: {
      blobCount: 2,
      byteStreamLength: program.bytes.length,
      highestOrdinal: 0x401,
    },
  };
  const result = link(library, dir, program.bytes, {});
  const run = runCom(result.output, { maxSteps: 80_000_000 });
  return run.output.split("\r\n").filter((l) => l.length > 0);
}

/** A deterministic generator. */
export function rng(seed: number) {
  let s = seed >>> 0;
  return () => {
    s = (s * 1664525 + 1013904223) >>> 0;
    return s;
  };
}

export const hex8 = (n: number) =>
  (n >>> 0).toString(16).toUpperCase().padStart(8, "0");
