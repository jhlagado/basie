/**
 * Blob emission: machine-code bytes, references, labels with forward-jump
 * fixup chains, and line entries for one blob at a time.
 *
 * Forward jumps use the single-pass chain: each pending jump's operand
 * holds the offset of the previous pending jump to the same label, and
 * defining the label walks the chain (capacity audit §2.1, option 2). So
 * the number of outstanding forward jumps is unbounded; only the number of
 * undefined labels costs memory, and that is bounded by nesting.
 */
import { Form, Kind, type KindCode, type Reference } from "../object/types.ts";
import type { LineEntry } from "../object/streams.ts";

export const NO_LABEL = -1;

export type Label = {
  /** Offset once defined; undefined while pending. */
  offset?: number;
  /** Head of the chain of pending 16-bit operand fields. */
  chain: number;
};

/** What `Blob.mark` records. */
export type BlobMark = {
  bytes: number;
  refs: number;
  lines: number;
  jumps: number;
  labels: Label[];
};

export class Blob {
  bytes: number[] = [];
  references: Reference[] = [];
  lines: LineEntry[] = [];
  private labels: Label[] = [];
  /** Local jumps that may shrink from JP to JR (build pipeline §6.3). */
  private jumps: { site: number; label: number; opcode: number }[] = [];

  constructor(
    public readonly ordinal: number,
    public readonly kind: KindCode,
    public readonly name: string,
    public root = false,
    public align = 0,
  ) {}

  get offset(): number {
    return this.bytes.length;
  }

  u8(...bs: number[]): void {
    for (const b of bs) this.bytes.push(b & 0xff);
  }

  u16(v: number): void {
    this.bytes.push(v & 0xff, (v >> 8) & 0xff);
  }

  u32(v: number): void {
    this.u16(v & 0xffff);
    this.u16((v >>> 16) & 0xffff);
  }

  raw(data: ArrayLike<number>): void {
    for (let i = 0; i < data.length; i += 1) this.bytes.push(data[i] & 0xff);
  }

  /** A 16-bit field referring to another blob or a pseudo-object. */
  abs16(target: number, addend = 0): void {
    this.references.push({
      offset: this.offset,
      form: Form.ABS16,
      target,
      addend: addend & 0xffff,
    });
    this.u16(0);
  }

  /** A 16-bit field holding another blob's size. */
  size16(target: number, addend = 0): void {
    this.references.push({
      offset: this.offset,
      form: Form.SIZE16,
      target,
      addend: addend & 0xffff,
    });
    this.u16(0);
  }

  /** A 16-bit field holding an address inside this blob. */
  self16(offsetInBlob: number): void {
    this.abs16(this.ordinal, offsetInBlob);
  }

  // ---- labels ---------------------------------------------------------------

  newLabel(): number {
    this.labels.push({ chain: NO_LABEL });
    return this.labels.length - 1;
  }

  /** Emit a 16-bit operand naming a label, resolving it now or later. */
  labelOperand(label: number): void {
    const l = this.labels[label];
    if (l.offset !== undefined) {
      this.self16(l.offset);
      return;
    }
    // Pending: the field holds the previous chain head; the reference
    // entry is added when the label is defined.
    const at = this.offset;
    this.u16(l.chain === NO_LABEL ? 0xffff : l.chain);
    l.chain = at;
  }

  defineLabel(label: number): void {
    const l = this.labels[label];
    if (l.offset !== undefined) throw new Error("label defined twice");
    l.offset = this.offset;
    let at = l.chain;
    while (at !== NO_LABEL) {
      const next = this.bytes[at] | (this.bytes[at + 1] << 8);
      this.bytes[at] = 0;
      this.bytes[at + 1] = 0;
      this.references.push({
        offset: at,
        form: Form.ABS16,
        target: this.ordinal,
        addend: l.offset,
      });
      at = next === 0xffff ? NO_LABEL : next;
    }
    l.chain = NO_LABEL;
  }

  labelOffset(label: number): number | undefined {
    return this.labels[label].offset;
  }

  /** A point that `rewind` returns the blob to. */
  mark(): BlobMark {
    return {
      bytes: this.bytes.length,
      refs: this.references.length,
      lines: this.lines.length,
      jumps: this.jumps.length,
      labels: this.labels.map((l) => ({ ...l })),
    };
  }

  /**
   * Discard everything written since the mark: bytes, references, line
   * entries, the jumps that might shrink, and the labels made since, and
   * give every older label back the chain it had, so that no pending
   * operand or shrinkable jump is left inside the discarded code.
   */
  rewind(m: BlobMark): void {
    this.bytes.length = m.bytes;
    this.references.length = m.refs;
    this.lines.length = m.lines;
    this.jumps.length = m.jumps;
    this.labels = m.labels;
  }

  /** Every label must be defined before the blob is finished. */
  finish(shrink = true): void {
    for (const l of this.labels) {
      if (l.offset === undefined && l.chain !== NO_LABEL) {
        throw new Error("a label was used but never defined");
      }
    }
    if (shrink && this.jumps.length > 0) this.shrinkJumps();
    this.references.sort((a, b) => a.offset - b.offset);
  }

  /**
   * Turn local JPs into JRs where the distance allows (build pipeline §6.3).
   * Start with every candidate short and drop those that don't fit; removing
   * a shrink only lengthens distances, so the loop ends. Then rewrite once:
   * drop a byte per shrunk jump, re-encode, and move every offset the blob
   * records (references, self-reference addends, line entries).
   */
  private shrinkJumps(): void {
    const target = (j: { label: number }) => this.labels[j.label].offset!;
    let short = new Set(this.jumps.filter((j) => target(j) !== undefined));
    const mapWith = (set: Set<typeof this.jumps[number]>) => {
      const sites = [...set].map((j) => j.site).sort((a, b) => a - b);
      return (o: number) => {
        // o moves back by one for each shrunk jump whose dropped byte (site+2) is before it
        let lo = 0, hi = sites.length;
        while (lo < hi) {
          const mid = (lo + hi) >> 1;
          if (sites[mid] + 2 < o) lo = mid + 1;
          else hi = mid;
        }
        return o - lo;
      };
    };
    while (true) {
      const map = mapWith(short);
      const fails = [...short].filter((j) => {
        const d = map(target(j)) - (map(j.site) + 2);
        return d < -128 || d > 127;
      });
      if (fails.length === 0) break;
      for (const j of fails) short.delete(j);
    }
    if (short.size === 0) return;
    const map = mapWith(short);
    const shrunkSites = new Set([...short].map((j) => j.site));
    // Drop the references held in shrunk operand fields.
    this.references = this.references.filter((r) =>
      !shrunkSites.has(r.offset - 1)
    );
    for (const r of this.references) {
      r.offset = map(r.offset);
      if (r.target === this.ordinal) r.addend = map(r.addend);
    }
    for (const l of this.lines) l.offset = map(l.offset);
    for (const l of this.labels) {
      if (l.offset !== undefined) l.offset = map(l.offset);
    }
    const out: number[] = [];
    const bySite = new Map([...short].map((j) => [j.site, j]));
    for (let i = 0; i < this.bytes.length; i += 1) {
      const j = bySite.get(i);
      if (j) {
        out.push(JR_FOR[j.opcode], (target(j) - (out.length + 2)) & 0xff);
        i += 2;
        continue;
      }
      out.push(this.bytes[i]);
    }
    this.bytes = out;
    short = new Set();
  }

  // ---- Z80 instructions used by the compiler ----------------------------------

  /** JP label (3 bytes, or 2 as JR once shrunk). */
  jp(label: number): void {
    this.jumps.push({ site: this.offset, label, opcode: 0xc3 });
    this.u8(0xc3);
    this.labelOperand(label);
  }
  /** JP cc,label. cc is the opcode: Z $ca, NZ $c2, C $da, NC $d2. */
  jpIf(cc: number, label: number): void {
    if (cc in JR_FOR) this.jumps.push({ site: this.offset, label, opcode: cc });
    this.u8(cc);
    this.labelOperand(label);
  }
  /** CALL to another blob. */
  callBlob(target: number, addend = 0): void {
    this.u8(0xcd);
    this.abs16(target, addend);
  }
  /** CALL cc,blob — the 3-byte trap-site form. */
  callBlobIf(cc: number, target: number): void {
    this.u8(cc + 0x02); // CALL cc is JP cc + 2
    this.abs16(target);
  }
  /** JP to another blob (tail calls between program routines). */
  jpBlob(target: number): void {
    this.u8(0xc3);
    this.abs16(target);
  }

  line(part: number, source: number): void {
    const last = this.lines.at(-1);
    if (last && last.offset === this.offset && last.part === part) {
      last.source = source;
      return;
    }
    this.lines.push({ offset: this.offset, part, source });
  }
}

/** The JR opcode for each JP that has one: JP, JP NZ, JP Z, JP NC, JP C. */
const JR_FOR: Record<number, number> = {
  0xc3: 0x18,
  0xc2: 0x20,
  0xca: 0x28,
  0xd2: 0x30,
  0xda: 0x38,
};

export const JP_Z = 0xca;
export const JP_NZ = 0xc2;
export const JP_C = 0xda;
export const JP_NC = 0xd2;
export const JP_PE = 0xea;
export const JP_PO = 0xe2;
export const JP_M = 0xfa;
export const JP_P = 0xf2;

/** A data blob with constant contents. */
export function dataBlob(
  ordinal: number,
  name: string,
  bytes: ArrayLike<number>,
  kind: KindCode = Kind.rodata,
): Blob {
  const b = new Blob(ordinal, kind, name);
  b.raw(bytes);
  return b;
}
