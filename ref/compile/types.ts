/** The Baton type model (spec chapter 6) and storage sizes (code generation §1). */

export type ScalarName =
  | "u8"
  | "i8"
  | "u16"
  | "i16"
  | "u32"
  | "i32"
  | "f32"
  | "boolean";

export type Field = { name: string; type: Type; offset: number };

export type RecordType = {
  kind: "record";
  name: string;
  fields: Field[];
  size: number;
  /** Set when any field, directly or nested, is an owning handle. */
  owning: boolean;
  /** Pools whose element type this is; used by id(n) on a lease. */
  pools: PoolInfo[];
  /** The ordinal of its ownership descriptor, once emitted. */
  descriptorOrdinal?: number;
};

export type PoolInfo = {
  name: string;
  /** Undefined while only forward-declared. */
  record?: RecordType;
  capacity?: number;
  /** Program-blob ordinal of the pool's info block (rodata). */
  ordinal: number;
  /** Ordinal of the pool's storage (bss), once declared. */
  storageOrdinal?: number;
};

/** One entry of an ownership descriptor (memory safety §5.10). */
export type OwningEntry = {
  offset: number;
  /** For an array of owning elements: its stride and count. */
  stride?: number;
  count?: number;
};

/** The owning-handle fields of a type, flattened to offsets from its start. */
export function owningEntries(t: Type, base = 0): OwningEntry[] {
  switch (t.kind) {
    case "handle":
      return t.id ? [] : [{ offset: base }];
    case "record": {
      const out: OwningEntry[] = [];
      for (const f of t.fields) {
        out.push(...owningEntries(f.type, base + f.offset));
      }
      return out;
    }
    case "array": {
      const inner = owningEntries(t.element, 0);
      const out: OwningEntry[] = [];
      const stride = sizeOf(t.element);
      for (const e of inner) {
        if (e.stride === undefined) {
          out.push({ offset: base + e.offset, stride, count: t.length });
        } else {
          // An array inside an array: one entry per outer element.
          for (let i = 0; i < t.length; i += 1) {
            out.push({
              offset: base + i * stride + e.offset,
              stride: e.stride,
              count: e.count,
            });
          }
        }
      }
      return out;
    }
    default:
      return [];
  }
}

export type Type =
  | { kind: "scalar"; name: ScalarName }
  | RecordType
  | { kind: "array"; element: Type; length: number; size: number }
  | { kind: "openArray"; element: Type }
  | { kind: "string"; capacity: number; size: number }
  | { kind: "openString" }
  | { kind: "handle"; pool: PoolInfo; id: boolean; optional: boolean }
  | { kind: "file" };

export const SCALARS: Record<
  ScalarName,
  { size: number; signed: boolean; float?: boolean; min: number; max: number }
> = {
  u8: { size: 1, signed: false, min: 0, max: 255 },
  i8: { size: 1, signed: true, min: -128, max: 127 },
  u16: { size: 2, signed: false, min: 0, max: 65535 },
  i16: { size: 2, signed: true, min: -32768, max: 32767 },
  u32: { size: 4, signed: false, min: 0, max: 4294967295 },
  i32: { size: 4, signed: true, min: -2147483648, max: 2147483647 },
  f32: {
    size: 4,
    signed: true,
    float: true,
    min: -3.4028234663852886e38,
    max: 3.4028234663852886e38,
  },
  boolean: { size: 1, signed: false, min: 0, max: 1 },
};

export const scalar = (name: ScalarName): Type => ({ kind: "scalar", name });
export const U8 = scalar("u8");
export const U16 = scalar("u16");
export const BOOLEAN = scalar("boolean");

export function isInteger(t: Type): boolean {
  return t.kind === "scalar" && t.name !== "f32" && t.name !== "boolean";
}
export function isNumeric(t: Type): boolean {
  return t.kind === "scalar" && t.name !== "boolean";
}
export function isScalar(t: Type, name?: ScalarName): boolean {
  return t.kind === "scalar" && (name === undefined || t.name === name);
}
export function isAggregate(t: Type): boolean {
  return t.kind === "record" || t.kind === "array" || t.kind === "string" ||
    t.kind === "openArray" || t.kind === "openString";
}
export function isOwningHandle(t: Type): boolean {
  return t.kind === "handle" && !t.id;
}
/** Owning types can't be copied (spec §6.15). */
export function isOwningType(t: Type): boolean {
  if (t.kind === "handle") return !t.id;
  if (t.kind === "record") return t.owning;
  if (t.kind === "array") return isOwningType(t.element);
  return false;
}

/** Bytes of storage for a type (code generation §1). */
export function sizeOf(t: Type): number {
  switch (t.kind) {
    case "scalar":
      return SCALARS[t.name].size;
    case "record":
      return t.size;
    case "array":
      return t.size;
    case "string":
      return t.size;
    case "handle":
      return t.id ? 4 : 2;
    case "file":
      return 4;
    case "openArray":
    case "openString":
      return 4; // the view: length or capacity, and the address
  }
}

/** Words a parameter of this type occupies on the stack (code generation §3). */
export function parameterWords(t: Type): number {
  switch (t.kind) {
    case "scalar":
      return SCALARS[t.name].size === 4 ? 2 : 1;
    case "handle":
      return t.id ? 2 : 1;
    case "file":
      return 2;
    case "openArray":
    case "openString":
      return 2;
    default:
      return 1; // an alias
  }
}

/** The implicit widenings of spec §6.4: from → to. */
const WIDENS: Record<ScalarName, ScalarName[]> = {
  u8: ["u16", "u32", "i16", "i32", "f32"],
  i8: ["i16", "i32", "f32"],
  u16: ["u32", "i32", "f32"],
  i16: ["i32", "f32"],
  u32: [],
  i32: [],
  f32: [],
  boolean: [],
};

export function widens(from: ScalarName, to: ScalarName): boolean {
  return from === to || WIDENS[from].includes(to);
}

/** The common type of two typed numeric operands (spec §9.7), or undefined. */
export function commonType(
  a: ScalarName,
  b: ScalarName,
): ScalarName | undefined {
  if (a === b) return a;
  if (widens(a, b)) return b;
  if (widens(b, a)) return a;
  return undefined;
}

export function sameType(a: Type, b: Type): boolean {
  if (a.kind !== b.kind) return false;
  switch (a.kind) {
    case "scalar":
      return a.name === (b as typeof a).name;
    case "record":
      return a === b;
    case "array":
      return a.length === (b as typeof a).length &&
        sameType(a.element, (b as typeof a).element);
    case "openArray":
      return sameType(a.element, (b as typeof a).element);
    case "string":
      return a.capacity === (b as typeof a).capacity;
    case "openString":
    case "file":
      return true;
    case "handle": {
      const o = b as typeof a;
      return a.pool === o.pool && a.id === o.id && a.optional === o.optional;
    }
  }
}

export function typeName(t: Type): string {
  switch (t.kind) {
    case "scalar":
      return t.name;
    case "record":
      return t.name;
    case "array":
      return `${typeName(t.element)}[${t.length}]`;
    case "openArray":
      return `${typeName(t.element)}[]`;
    case "string":
      return `string[${t.capacity}]`;
    case "openString":
      return "string[]";
    case "handle":
      return `${t.id ? "id " : ""}${t.pool.name}${t.optional ? "?" : ""}`;
    case "file":
      return "File";
  }
}

/** Whether a value fits a scalar type; exact integers are checked by range. */
export function fits(value: number, name: ScalarName): boolean {
  const s = SCALARS[name];
  if (s.float) return Number.isFinite(value) && Math.abs(value) <= s.max;
  return Number.isInteger(value) && value >= s.min && value <= s.max;
}
