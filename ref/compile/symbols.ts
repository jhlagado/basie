/** Scopes and symbols (spec chapter 5). */
import type { Position } from "./lexer.ts";
import { fail } from "./diagnostics.ts";
import type { PoolInfo, RecordType, Type } from "./types.ts";

export type Storage =
  | { kind: "program"; ordinal: number; offset: number }
  /** Frame-relative: IX + offset. */
  | { kind: "frame"; offset: number };

export type ConstValue = number | boolean;

export type Parameter = {
  name: string;
  type: Type;
  var: boolean;
  /** IX offset of the parameter's first word, known after the header. */
  offset: number;
  /** IX offset of the hidden owner word, for var owning parameters. */
  ownerOffset?: number;
};

export type Signature = {
  name: string;
  parameters: Parameter[];
  result?: Type;
  varResult: boolean;
  from: string[];
  fails: boolean;
  /** Bytes of arguments on the stack. */
  argumentBytes: number;
};

/** The flow state of an owning local or parameter (memory safety §5.8). */
export type Flow = "value" | "none" | "maybe";

export type Symbol =
  | {
    kind: "const";
    name: string;
    /** Undefined for an untyped constant. */
    type?: Type;
    value: ConstValue;
  }
  | {
    kind: "aggregateConst";
    name: string;
    type: Type;
    ordinal: number;
  }
  | {
    kind: "var";
    name: string;
    type: Type;
    storage: Storage;
    /** A parameter without var, or an alias result: read-only. */
    readonly: boolean;
    parameter?: Parameter;
    flow?: Flow;
    /** Set while the local is the counter of an active loop. */
    counting?: boolean;
  }
  | { kind: "record"; name: string; type: RecordType }
  | { kind: "pool"; name: string; info: PoolInfo; forward: boolean }
  | {
    kind: "routine";
    name: string;
    signature: Signature;
    ordinal: number;
    /** Declared forward and not yet completed. */
    forward: boolean;
    /** The body has been compiled. */
    complete: boolean;
    private: boolean;
    /** Library blob: a service. */
    service: boolean;
    declaredAt: Position;
    part: number;
    /** Stack need and frame, known when the body is complete. */
    need?: number;
    frame?: number;
    /** Calls of this routine made before its body was complete. */
    pendingNeeds: { caller: Symbol & { kind: "routine" } }[];
  };

export type ScopeKind = "program" | "part" | "routine" | "block";

export type Scope = {
  kind: ScopeKind;
  symbols: Map<string, Symbol>;
  /** The routine a routine or block scope belongs to. */
  routine?: Symbol & { kind: "routine" };
};

export class Scopes {
  private readonly stack: Scope[];
  private program: Scope;
  private part: Scope;

  constructor() {
    this.program = { kind: "program", symbols: new Map() };
    this.part = { kind: "part", symbols: new Map() };
    this.stack = [this.program, this.part];
  }

  get current(): Scope {
    return this.stack[this.stack.length - 1];
  }

  get depth(): number {
    return this.stack.length;
  }

  /** The innermost routine scope's routine, if inside one. */
  get routine(): (Symbol & { kind: "routine" }) | undefined {
    for (let i = this.stack.length - 1; i >= 0; i -= 1) {
      const r = this.stack[i].routine;
      if (r) return r;
    }
    return undefined;
  }

  /** A new source part: the previous part's private names go out of scope. */
  newPart(): void {
    if (this.stack.length !== 2) throw new Error("part change inside a scope");
    this.part = { kind: "part", symbols: new Map() };
    this.stack[1] = this.part;
  }

  open(
    kind: "routine" | "block",
    routine?: Symbol & { kind: "routine" },
  ): void {
    this.stack.push({ kind, symbols: new Map(), routine });
  }

  close(): Scope {
    if (this.stack.length <= 2) throw new Error("closing the part scope");
    return this.stack.pop()!;
  }

  lookup(name: string): Symbol | undefined {
    for (let i = this.stack.length - 1; i >= 0; i -= 1) {
      const s = this.stack[i].symbols.get(name);
      if (s) return s;
    }
    return undefined;
  }

  /** Declare in the current scope, or in the part scope when private. */
  declare(sym: Symbol, at: Position, isPrivate = false): void {
    const existing = this.lookup(sym.name);
    if (existing) {
      const here = this.current.symbols.has(sym.name) ||
        (isPrivate && this.part.symbols.has(sym.name));
      fail(
        here ? "duplicate-name" : "shadowed-name",
        at,
        here
          ? `${sym.name} is already declared`
          : `${sym.name} would hide a visible name`,
      );
    }
    const target = isPrivate ? this.part : this.current;
    target.symbols.set(sym.name, sym);
  }

  /** Every symbol of the current scope, for block-end freeing. */
  symbolsHere(): Symbol[] {
    return [...this.current.symbols.values()];
  }

  /** Symbols of every scope inside the current routine, innermost first. */
  routineSymbols(): Symbol[] {
    const out: Symbol[] = [];
    for (let i = this.stack.length - 1; i >= 2; i -= 1) {
      out.push(...this.stack[i].symbols.values());
      if (this.stack[i].kind === "routine") break;
    }
    return out;
  }
}
