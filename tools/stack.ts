/**
 * Static stack analysis of runtime blobs (code generation §7; memory safety
 * §7). For each blob it follows every path from the entry and finds the most
 * bytes the blob pushes below the stack pointer it was entered with, its own
 * calls included. The figures this computes are the ones the helper table
 * publishes; the CP/M harness's stack probes check them against measured use.
 *
 * Each figure counts the 2-byte return address of the CALL that reaches the
 * blob, so a helper that pushes nothing has the figure 2. Two figures are
 * kept apart:
 *
 * - **returning**: the most a call can use and still return. It feeds
 *   `need(R)`.
 * - **ending**: the most any path uses, including one that ends the program
 *   through a trap or EXIT. Such a path runs in the guard band.
 *
 * A blob the analysis can't follow states its figure with `stack=N` on its
 * `@blob` line. A blob with an indirect jump names where it goes with
 * `indirect=NAME`, or `indirect=bios` for a BIOS entry, which returns and
 * whose own stack use is part of the guard band.
 */

export type StackBlob = {
  ordinal: number;
  name: string;
  /** The blob's bytes, with zeros where references go. */
  bytes: number[];
  /** References by byte offset: the target ordinal and addend. */
  references: Map<number, { target: number; addend: number }>;
  /** A stated figure, for a blob the analysis can't follow. */
  stack?: number;
  /** Where an indirect jump goes: a blob name, or "bios". */
  indirect?: string;
};

export type StackFigure = {
  /** Whether any path returns to the caller. */
  returns: boolean;
  /** Bytes used by a call that returns, with the return address. */
  returning: number;
  /** Bytes used by any path, with the return address. */
  ending: number;
};

export class StackError extends Error {}

/** BDOS calls run on CP/M's own stack: only the return address is ours. */
const BDOS = 0x0005;

const LEN2 = new Set([
  0x06,
  0x0e,
  0x16,
  0x1e,
  0x26,
  0x2e,
  0x36,
  0x3e,
  0x10,
  0x18,
  0x20,
  0x28,
  0x30,
  0x38,
  0xc6,
  0xce,
  0xd6,
  0xde,
  0xe6,
  0xee,
  0xf6,
  0xfe,
  0xd3,
  0xdb,
  0xcb,
]);
const LEN3 = new Set([
  0x01,
  0x11,
  0x21,
  0x31,
  0x22,
  0x2a,
  0x32,
  0x3a,
  0xc2,
  0xc3,
  0xca,
  0xd2,
  0xda,
  0xe2,
  0xea,
  0xf2,
  0xfa,
  0xc4,
  0xcc,
  0xd4,
  0xdc,
  0xe4,
  0xec,
  0xf4,
  0xfc,
  0xcd,
]);
/** IX/IY instructions that take a displacement byte. */
const DISPLACED = new Set([
  0x34,
  0x35,
  0x36,
  0x46,
  0x4e,
  0x56,
  0x5e,
  0x66,
  0x6e,
  0x7e,
  0x70,
  0x71,
  0x72,
  0x73,
  0x74,
  0x75,
  0x77,
  0x86,
  0x8e,
  0x96,
  0x9e,
  0xa6,
  0xae,
  0xb6,
  0xbe,
]);
const PUSHES = new Set([0xc5, 0xd5, 0xe5, 0xf5]);
const POPS = new Set([0xc1, 0xd1, 0xe1, 0xf1]);
const RET_CC = new Set([0xc0, 0xc8, 0xd0, 0xd8, 0xe0, 0xe8, 0xf0, 0xf8]);
const JP_CC = new Set([0xc2, 0xca, 0xd2, 0xda, 0xe2, 0xea, 0xf2, 0xfa]);
const CALL_CC = new Set([0xc4, 0xcc, 0xd4, 0xdc, 0xe4, 0xec, 0xf4, 0xfc]);
const JR_CC = new Set([0x20, 0x28, 0x30, 0x38]);

function length(b: number[], o: number): number {
  const op = b[o];
  if (op === 0xed) {
    return [0x43, 0x4b, 0x53, 0x5b, 0x63, 0x6b, 0x73, 0x7b].includes(b[o + 1])
      ? 4
      : 2;
  }
  if (op === 0xdd || op === 0xfd) {
    const op2 = b[o + 1];
    if (op2 === 0xcb) return 4;
    return 1 + length(b, o + 1) + (DISPLACED.has(op2) ? 1 : 0);
  }
  return LEN3.has(op) ? 3 : LEN2.has(op) ? 2 : 1;
}

/** The figures of every blob, keyed by ordinal. */
export function analyzeStack(blobs: StackBlob[]): Map<number, StackFigure> {
  const byOrdinal = new Map(blobs.map((b) => [b.ordinal, b]));
  const byName = new Map(blobs.map((b) => [b.name.toUpperCase(), b]));
  const units = new Map<string, StackFigure>();
  const busy = new Set<string>();
  const BIOS: StackFigure = { returns: true, returning: 2, ending: 2 };

  function unit(blob: StackBlob, entry: number): StackFigure {
    if (blob.stack !== undefined) {
      return { returns: true, returning: blob.stack, ending: blob.stack };
    }
    const key = `${blob.ordinal}:${entry}`;
    const known = units.get(key);
    if (known) return known;
    if (busy.has(key)) {
      throw new StackError(`${blob.name}: recursion; state its figure`);
    }
    busy.add(key);
    const figure = follow(blob, entry);
    busy.delete(key);
    units.set(key, figure);
    return figure;
  }

  function target(blob: StackBlob, at: number, what: string) {
    const r = blob.references.get(at);
    if (r) return { blob: byOrdinal.get(r.target), offset: r.addend, r };
    return {
      blob: undefined,
      offset: blob.bytes[at] | (blob.bytes[at + 1] << 8),
      r,
      what,
    };
  }

  /** Walk one entry of a blob. Depths exclude the caller's return address. */
  function follow(blob: StackBlob, entry: number): StackFigure {
    const b = blob.bytes;
    let returns = false, returning = 0, ending = 0;
    type State = { o: number; depth: number; ix?: number | "zero" };
    const work: State[] = [{ o: entry, depth: 0 }];
    const seen = new Map<number, Set<string>>();
    const fail = (o: number, why: string): never => {
      throw new StackError(`${blob.name}+${o}: ${why}`);
    };
    const callee = (depth: number, f: StackFigure, viaCall: boolean) => {
      const extra = viaCall ? depth + 2 : depth;
      ending = Math.max(ending, extra + f.ending - 2);
      if (f.returns) returning = Math.max(returning, extra + f.returning - 2);
    };
    while (work.length > 0) {
      const s = work.pop()!;
      const { o, depth } = s;
      if (o < 0 || o >= b.length) fail(o, "a path leaves the blob");
      const tag = `${depth}:${s.ix}`;
      const at = seen.get(o) ?? new Set<string>();
      if (at.has(tag)) continue;
      at.add(tag);
      seen.set(o, at);
      if (at.size > 8) fail(o, "the stack depth here keeps changing");
      // A trap reporter pops its caller's return address: the trap site.
      if (depth < -2) fail(o, "pops past the entry");
      returning = Math.max(returning, depth);
      ending = Math.max(ending, depth);
      const len = length(b, o);
      const next = (depth2 = depth, ix = s.ix) =>
        work.push({ o: o + len, depth: depth2, ix });
      const op = b[o];
      // Calls and jumps to an absolute operand.
      if (op === 0xcd || CALL_CC.has(op) || op === 0xc3 || JP_CC.has(op)) {
        const isCall = op === 0xcd || CALL_CC.has(op);
        const conditional = op !== 0xcd && op !== 0xc3;
        const t = target(blob, o + 1, "jump");
        if (!t.blob) {
          if (t.r) fail(o, "a jump to a pseudo-object");
          if (t.offset === BDOS) {
            callee(depth, BIOS, isCall);
            if (isCall || conditional) next();
            if (!isCall) returns = true;
            continue;
          }
          if (!isCall && t.offset === 0) { // warm boot
            if (conditional) next();
            continue;
          }
          fail(o, `a jump to absolute $${t.offset.toString(16)}`);
        }
        if (!isCall && t.blob === blob) { // a jump within the blob
          work.push({ o: t.offset, depth, ix: s.ix });
          if (conditional) next();
          continue;
        }
        const f = unit(t.blob!, t.offset);
        callee(depth, f, isCall);
        if (isCall) {
          if (f.returns) next();
          if (conditional && !f.returns) next();
        } else {
          if (f.returns) returns = true;
          if (conditional) next();
        }
        continue;
      }
      if (op === 0x18 || JR_CC.has(op) || op === 0x10) {
        const d = b[o + 1] < 128 ? b[o + 1] : b[o + 1] - 256;
        work.push({ o: o + 2 + d, depth, ix: s.ix });
        if (op !== 0x18) next();
        continue;
      }
      if (op === 0xc9 || RET_CC.has(op)) {
        if (depth !== 0) fail(o, `a return with ${depth} bytes pushed`);
        returns = true;
        if (op !== 0xc9) next();
        continue;
      }
      if (PUSHES.has(op)) {
        next(depth + 2);
        continue;
      }
      if (POPS.has(op)) {
        next(depth - 2);
        continue;
      }
      if (op === 0x33) { // INC SP
        next(depth - 1);
        continue;
      }
      if (op === 0x3b) { // DEC SP
        next(depth + 1);
        continue;
      }
      if (op === 0xc7) continue; // RST 0: warm boot
      if (op === 0x76) continue; // HALT
      if (op === 0x31 || (op === 0xed && b[o + 1] === 0x7b)) {
        continue; // LD SP,nn / LD SP,(nn): the program's stack is abandoned
      }
      if ((op & 0xc7) === 0xc7) fail(o, "a restart");
      if (op === 0xf9) fail(o, "LD SP,HL; state the figure");
      if (op === 0xe9 || ((op === 0xdd || op === 0xfd) && b[o + 1] === 0xe9)) {
        const where = blob.indirect?.toUpperCase();
        if (!where) fail(o, "an indirect jump; name it with indirect=");
        const f = where === "BIOS"
          ? BIOS
          : byName.get(where!)
          ? unit(byName.get(where!)!, 0)
          : fail(o, `indirect=${where}: no such blob`);
        callee(depth, f, false);
        if (f.returns) returns = true;
        continue;
      }
      if (op === 0xed && (b[o + 1] === 0x45 || b[o + 1] === 0x4d)) {
        returns = true; // RETN, RETI
        continue;
      }
      if (op === 0xdd || op === 0xfd) {
        const op2 = b[o + 1];
        const isIX = op === 0xdd;
        if (op2 === 0xe5) next(depth + 2);
        else if (op2 === 0xe1) next(depth - 2, isIX ? undefined : s.ix);
        else if (op2 === 0xf9) {
          if (!isIX || typeof s.ix !== "number") {
            fail(o, "LD SP from an unknown frame pointer");
          }
          next(s.ix as number);
        } else if (op2 === 0x21 && isIX) {
          const zero = !blob.references.has(o + 2) && b[o + 2] === 0 &&
            b[o + 3] === 0;
          next(depth, zero ? "zero" : undefined);
        } else if (op2 === 0x39 && isIX) {
          next(depth, s.ix === "zero" ? depth : undefined);
        } else if (isIX && [0x2a, 0x23, 0x2b, 0x09, 0x19, 0x29].includes(op2)) {
          next(depth, undefined); // IX changes
        } else next();
        continue;
      }
      next();
    }
    return { returns, returning: returning + 2, ending: ending + 2 };
  }

  const out = new Map<number, StackFigure>();
  for (const blob of blobs) out.set(blob.ordinal, unit(blob, 0));
  return out;
}
