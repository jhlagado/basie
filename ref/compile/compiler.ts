/**
 * The reference compiler: one pass over the token stream, emitting blobs
 * (spec chapters 4 to 15; code generation contract). This file covers
 * declarations, scopes, routines, statements and expressions on the scalar
 * types, records, arrays and strings; later stages add pools and f32.
 */
import { Kind } from "../object/types.ts";
import type { DirectoryRecord } from "../object/types.ts";
import type { BlobLines } from "../object/streams.ts";
import { CompileError, fail } from "./diagnostics.ts";
import { Blob, dataBlob, JP_C, JP_NC, JP_NZ, JP_Z } from "./emit.ts";
import {
  CONSOLE_FILE,
  Helper,
  HELPER_STACK,
  HELPER_VERSION,
  PREDECLARED_CONSTANTS,
  PRINTER_FILE,
  REGISTER_HELPERS,
  SERVICES,
  TRAP_REPORTERS,
} from "./helpers.ts";
import type { Keyword, Position, Punctuation, Token } from "./lexer.ts";
import { tokenize } from "./lexer.ts";
import type { Part } from "./source.ts";
import {
  type Flow,
  type Parameter,
  type Scope,
  Scopes,
  type Signature,
  type Symbol,
} from "./symbols.ts";
import {
  BOOLEAN,
  commonType,
  fits,
  isAggregate,
  isInteger,
  isNumeric,
  isOwningType,
  isScalar,
  owningEntries,
  parameterWords,
  type PoolInfo,
  type RecordType,
  sameType,
  scalar,
  type ScalarName,
  SCALARS,
  sizeOf,
  type Type,
  typeName,
  U16,
  U8,
  widens,
} from "./types.ts";

export class NotImplemented extends Error {}

const GUARD_BAND = 64;

/** What an expression left behind. */
type Value =
  /** A compile-time constant; nothing emitted. `type` undefined = exact. */
  | { kind: "const"; type?: Type; value: number | boolean }
  /** In the registers for its type. */
  | { kind: "reg"; type: Type }
  /** A string literal, for a string[] argument or initializer. */
  | { kind: "literal"; bytes: Uint8Array }
  /** Aggregate storage: its address is in HL. */
  | { kind: "address"; type: Type; readonly: boolean }
  /** A fresh owning value in HL: new, move, or an owning result. */
  | { kind: "fresh"; type: Type }
  /** The empty handle, typed by its context. */
  | { kind: "none" };

/** A storage path, before any code is emitted for it. */
type Place =
  | { kind: "static"; ordinal: number; offset: number }
  | { kind: "frame"; offset: number }
  /** Through a word at IX+offset holding an address (an alias parameter). */
  | { kind: "alias"; offset: number; add: number }
  /** The address is in HL once `emitAddress` has run. */
  | { kind: "computed" };

type Designator = {
  place: Place;
  type: Type;
  readonly: boolean;
  /** The .length of a string[] parameter at this IX offset: set through STR_SETL. */
  setLength?: number;
  /** The frame word holding the record whose field this is, for owner links. */
  slotTemp?: number;
  /** How that record was reached: an owner needs no cycle walk; an identifier does. */
  slotKind?: "owner" | "identifier" | "lease";
  /** The designator is a bare name with no suffix. */
  rootOnly?: boolean;
  /** The designator's first token, for diagnostics. */
  at?: Token;
  symbol?: Symbol & { kind: "var" };
  /** Emit code leaving the address in HL (for computed places). */
  compute?: () => void;
};

type LoopContext = {
  exit: number;
  next: number;
  counter?: Symbol & { kind: "var" };
  /** The scope depth of the loop body; exits free the scopes above it. */
  depth: number;
  /** Flow states at loop entry, for the back-edge rule. */
  entryFlow: Map<Symbol, Flow>;
};

type RoutineState = {
  symbol: Symbol & { kind: "routine" };
  blob: Blob;
  /** Current frame offset (negative) and the deepest reached. */
  frame: number;
  deepest: number;
  /** Bytes pushed as expression temporaries right now. */
  pushed: number;
  maxCalleeNeed: number;
  helperStack: number;
  exitLabel: number;
  /** Where LD HL,-frame in the prologue is patched. */
  framePatch?: number;
  pairLabel: number;
  loops: LoopContext[];
  literals: { label: number; bytes: number[] }[];
  fallsThrough: boolean;
};

export type CompiledProgram = {
  records: DirectoryRecord[];
  bytes: Uint8Array;
  lines: BlobLines[];
  names: { ordinal: number; name: string }[];
  entry: number;
};

const CALL_CC: Record<string, number> = {};
void CALL_CC;

export class Compiler {
  private readonly scopes = new Scopes();
  private pos = 0;
  private blobs: Blob[] = [];
  private nextOrdinal = 0x400;
  private routine?: RoutineState;
  private mainOrdinal?: number;
  private currentPart = 0;
  private forwardsOpen: (Symbol & { kind: "routine" })[] = [];
  private forwardPools: {
    sym: Symbol & { kind: "pool" };
    at: Token;
    part: number;
    private: boolean;
  }[] = [];
  /** Owners used directly and moved in the current statement (10.8). */
  private stmtDirect = new Set<Symbol>();
  private stmtMoved = new Set<Symbol>();
  private anyForward = false;
  private largestFrame = 0;
  private readonly lineBlobs: BlobLines[] = [];

  constructor(
    private readonly tokens: Token[],
    private readonly parts: Part[],
    predeclare = true,
  ) {
    if (predeclare) this.predeclare();
  }

  // ---- predeclared names (chapter 16) ---------------------------------------

  private predeclare(): void {
    const at = this.tokens[0];
    for (const [name, value] of PREDECLARED_CONSTANTS) {
      this.scopes.declare({ kind: "const", name, value }, at);
    }
    for (
      const [name, value] of [["console", CONSOLE_FILE], [
        "printer",
        PRINTER_FILE,
      ]] as const
    ) {
      this.scopes.declare({
        kind: "const",
        name,
        type: { kind: "file" },
        value,
      }, at);
    }
    for (const service of SERVICES) {
      const sub = new Compiler(
        tokenize(new TextEncoder().encode(service.signature!)),
        [],
        false,
      );
      const sig = sub.parseHeader(sub.expectKeyword("sub"));
      this.scopes.declare({
        kind: "routine",
        name: sig.name,
        signature: sig,
        ordinal: service.ordinal,
        forward: false,
        complete: true,
        private: false,
        service: true,
        declaredAt: at,
        part: -1,
        need: service.stack,
        pendingNeeds: [],
      }, at);
    }
  }

  // ---- token access -----------------------------------------------------------

  private get token(): Token {
    return this.tokens[this.pos];
  }

  private peek(k = 1): Token {
    return this.tokens[Math.min(this.pos + k, this.tokens.length - 1)];
  }

  private advance(): Token {
    const t = this.tokens[this.pos];
    if (t.kind !== "eof") this.pos += 1;
    return t;
  }

  private isKeyword(text: Keyword, t: Token = this.token): boolean {
    return t.kind === "keyword" && t.text === text;
  }

  private isPunct(text: Punctuation, t: Token = this.token): boolean {
    return t.kind === "punct" && t.text === text;
  }

  private isName(text?: string, t: Token = this.token): boolean {
    return t.kind === "name" && (text === undefined || t.text === text);
  }

  private describe(t: Token): string {
    switch (t.kind) {
      case "name":
        return `name ${t.text}`;
      case "keyword":
      case "punct":
        return `'${t.text}'`;
      default:
        return t.kind;
    }
  }

  private expectKeyword(text: Keyword): Token {
    if (!this.isKeyword(text)) {
      fail(
        "syntax",
        this.token,
        `expected '${text}', found ${this.describe(this.token)}`,
      );
    }
    return this.advance();
  }

  private expectPunct(text: Punctuation): Token {
    if (!this.isPunct(text)) {
      fail(
        "syntax",
        this.token,
        `expected '${text}', found ${this.describe(this.token)}`,
      );
    }
    return this.advance();
  }

  private expectName(): Token & { kind: "name" } {
    if (this.token.kind !== "name") {
      fail(
        "syntax",
        this.token,
        `expected a name, found ${this.describe(this.token)}`,
      );
    }
    return this.advance() as Token & { kind: "name" };
  }

  private expectNewline(): void {
    if (this.token.kind !== "newline") {
      fail(
        "syntax",
        this.token,
        `expected the end of the line, found ${this.describe(this.token)}`,
      );
    }
    this.advance();
  }

  private acceptKeyword(text: Keyword): boolean {
    if (this.isKeyword(text)) {
      this.advance();
      return true;
    }
    return false;
  }

  private acceptPunct(text: Punctuation): boolean {
    if (this.isPunct(text)) {
      this.advance();
      return true;
    }
    return false;
  }

  // ---- the compilation ----------------------------------------------------------

  compile(): CompiledProgram {
    while (this.token.kind !== "eof") {
      if (this.token.part !== this.currentPart) this.endPart(this.token.part);
      if (this.token.kind === "newline") {
        this.advance();
        continue;
      }
      this.topLevel();
    }
    this.endPart(-1);
    if (this.mainOrdinal === undefined) {
      fail("missing-main", this.token, "no routine named main");
    }
    const main = this.scopes.lookup("main") as Symbol & { kind: "routine" };
    const records: DirectoryRecord[] = [];
    const bytes: number[] = [];
    const names: { ordinal: number; name: string }[] = [];
    for (const b of this.blobs) {
      b.finish();
      records.push({
        type: "blob",
        kind: b.kind,
        ordinal: b.ordinal,
        size: b.bytes.length,
        root: b.root,
        align: b.align,
        references: b.references,
      });
      if (b.kind !== Kind.bss) bytes.push(...b.bytes);
      names.push({ ordinal: b.ordinal, name: b.name });
    }
    records.push({ type: "entry", ordinal: this.mainOrdinal! });
    records.push({
      type: "limits",
      stackReserve: (main.need ?? 0) + GUARD_BAND,
      largestFrame: this.largestFrame,
      flags: this.anyForward ? 1 : 0,
    });
    return {
      records,
      bytes: Uint8Array.from(bytes),
      lines: this.lineBlobs,
      names,
      entry: this.mainOrdinal!,
    };
  }

  private endPart(next: number): void {
    for (const r of this.forwardsOpen) {
      if (r.private && r.forward && r.part === this.currentPart) {
        fail(
          "forward-incomplete",
          r.declaredAt,
          `private forward ${r.name} not completed in its part`,
        );
      }
    }
    for (const f of this.forwardPools) {
      if (
        f.sym.forward &&
        (next < 0 || (f.private && f.part === this.currentPart))
      ) {
        fail(
          "forward-incomplete",
          f.at,
          `forward pool ${f.sym.name} never completed`,
        );
      }
    }
    if (next < 0) {
      const open = this.forwardsOpen.find((r) => r.forward);
      if (open) {
        fail(
          "forward-incomplete",
          open.declaredAt,
          `forward ${open.name} never completed`,
        );
      }
      return;
    }
    this.currentPart = next;
    this.scopes.newPart();
  }

  private newBlob(kind: typeof Kind[keyof typeof Kind], name: string): Blob {
    const b = new Blob(this.nextOrdinal, kind, name);
    this.nextOrdinal += 1;
    if (this.nextOrdinal > 0xffdf) {
      fail("capacity", this.token, "too many blobs");
    }
    this.blobs.push(b);
    return b;
  }

  // ---- top-level declarations (chapter 8) ----------------------------------------

  private topLevel(): void {
    const isPrivate = this.acceptKeyword("private");
    const t = this.token;
    if (this.isKeyword("const")) this.constDeclaration(isPrivate);
    else if (this.isKeyword("var")) this.programVar(isPrivate);
    else if (this.isKeyword("record")) this.recordDeclaration(isPrivate);
    else if (this.isKeyword("pool")) this.poolDeclaration(isPrivate);
    else if (this.isKeyword("forward")) this.forwardDeclaration(isPrivate);
    else if (this.isKeyword("sub")) this.routineDefinition(isPrivate);
    else if (this.isKeyword("assert")) {
      if (isPrivate) fail("syntax", t, "assert can't be private");
      this.compileTimeAssert();
    } else if (this.isKeyword("include")) {
      fail("include-position", t, "include must come before declarations");
    } else {
      fail("syntax", t, `expected a declaration, found ${this.describe(t)}`);
    }
  }

  private compileTimeAssert(): void {
    const at = this.expectKeyword("assert");
    const v = this.constantExpression(BOOLEAN);
    if (v.value !== true) fail("assertion-false", at, "the assertion is false");
    this.expectNewline();
  }

  /** `const NAME [as type] = initializer`, at top level or in a block. */
  private constDeclaration(isPrivate: boolean): void {
    this.expectKeyword("const");
    const name = this.expectName();
    let type: Type | undefined;
    if (this.acceptKeyword("as")) type = this.parseType();
    this.expectPunct("=");
    if (type && isAggregate(type)) {
      const bytes = this.staticInitializer(type);
      const blob = this.newBlob(Kind.rodata, name.text);
      blob.raw(bytes);
      this.scopes.declare(
        {
          kind: "aggregateConst",
          name: name.text,
          type,
          ordinal: blob.ordinal,
        },
        name,
        isPrivate,
      );
    } else if (type) {
      const v = this.constantExpression(type);
      this.scopes.declare(
        { kind: "const", name: name.text, type, value: v.value },
        name,
        isPrivate,
      );
    } else {
      const at = this.token;
      const v = this.constantExpression();
      if (v.type && v.type.kind === "scalar" && v.type.name === "f32") {
        fail(
          "constant-needs-type",
          at,
          "a floating-point constant must be typed",
        );
      }
      if (
        v.type &&
        !(v.type.kind === "scalar" &&
          (v.type.name === "boolean" || v.type.name === "u8"))
      ) {
        fail(
          "constant-needs-type",
          at,
          "an untyped constant must be an integer, character or boolean",
        );
      }
      const untyped = typeof v.value === "boolean" ? BOOLEAN : undefined;
      this.scopes.declare(
        { kind: "const", name: name.text, type: untyped, value: v.value },
        name,
        isPrivate,
      );
    }
    this.expectNewline();
  }

  private programVar(isPrivate: boolean): void {
    this.expectKeyword("var");
    const name = this.expectName();
    this.expectKeyword("as");
    const type = this.parseType();
    if (type.kind === "handle" && !type.optional) {
      fail(
        "handle-must-be-optional",
        name,
        "a program variable of handle type must be optional",
      );
    }
    let blob: Blob;
    if (this.acceptPunct("=")) {
      if (type.kind === "handle" || isOwningType(type)) {
        fail(
          "static-initializer",
          name,
          "a handle or owning type can't have an initializer",
        );
      }
      blob = this.newBlob(Kind.data, name.text);
      blob.raw(this.staticInitializer(type));
    } else {
      blob = this.newBlob(Kind.bss, name.text);
      for (let i = 0; i < sizeOf(type); i += 1) blob.bytes.push(0);
    }
    this.expectNewline();
    this.scopes.declare(
      {
        kind: "var",
        name: name.text,
        type,
        storage: { kind: "static", ordinal: blob.ordinal, offset: 0 },
        readonly: false,
      },
      name,
      isPrivate,
    );
  }

  private recordDeclaration(isPrivate: boolean): void {
    this.expectKeyword("record");
    const name = this.expectName();
    this.expectNewline();
    const type: RecordType = {
      kind: "record",
      name: name.text,
      fields: [],
      size: 0,
      owning: false,
      pools: [],
    };
    const seen = new Set<string>();
    while (!this.isKeyword("end")) {
      if (this.token.kind === "newline") {
        this.advance();
        continue;
      }
      const field = this.expectName();
      this.expectKeyword("as");
      const typeAt = this.token;
      const ftype = this.parseType();
      if (ftype.kind === "handle" && !ftype.optional) {
        fail(
          "handle-must-be-optional",
          typeAt,
          "a field of handle type must be optional",
        );
      }
      if (seen.has(field.text)) {
        fail(
          "duplicate-name",
          field,
          `field ${field.text} is already declared`,
        );
      }
      seen.add(field.text);
      type.fields.push({ name: field.text, type: ftype, offset: type.size });
      type.size += sizeOf(ftype);
      if (isOwningType(ftype)) type.owning = true;
      this.expectNewline();
    }
    this.expectKeyword("end");
    this.expectNewline();
    if (type.fields.length === 0) {
      fail("empty-record", name, "a record needs at least one field");
    }
    if (type.size > 0xffff) {
      fail("out-of-range", name, "a record can't exceed 65,535 bytes");
    }
    this.scopes.declare(
      { kind: "record", name: name.text, type },
      name,
      isPrivate,
    );
  }

  // ---- types (chapter 6) ---------------------------------------------------------

  private parseType(): Type {
    const t = this.token;
    let base: Type;
    if (t.kind === "keyword" && t.text in SCALARS) {
      this.advance();
      base = scalar(t.text as ScalarName);
    } else if (this.isKeyword("string")) {
      this.advance();
      this.expectPunct("[");
      if (this.acceptPunct("]")) return { kind: "openString" };
      const n = this.constantExpression(U16).value as number;
      if (n < 1 || n > 253) {
        fail("out-of-range", t, "a string capacity is 1 to 253");
      }
      this.expectPunct("]");
      base = { kind: "string", capacity: n, size: n + 2 };
    } else if (this.isName("id") && this.peek().kind === "name") {
      this.advance();
      base = this.handleType(true);
    } else if (t.kind === "name") {
      const sym = this.scopes.lookup(t.text);
      if (sym?.kind === "record") {
        this.advance();
        base = sym.type;
      } else if (sym?.kind === "pool") {
        base = this.handleType(false);
      } else if (t.text === "File") {
        this.advance();
        base = { kind: "file" };
      } else if (!sym) {
        fail("undeclared-name", t, `${t.text} is not declared`);
      } else {
        fail("wrong-class", t, `${t.text} is not a type`);
      }
    } else {
      fail("syntax", t, `expected a type, found ${this.describe(t)}`);
    }
    // Array dimensions, outermost first in the source: u8[25][40].
    const dims: number[] = [];
    while (this.isPunct("[")) {
      this.advance();
      if (this.acceptPunct("]")) {
        if (dims.length > 0) {
          fail("syntax", t, "only the outermost dimension may be open");
        }
        const inner = this.parseArrayTail(base!);
        return { kind: "openArray", element: inner };
      }
      const n = this.constantExpression(U16).value as number;
      if (n < 1 || n > 0xffff) {
        fail("out-of-range", t, "an array length is 1 to 65,535");
      }
      this.expectPunct("]");
      dims.push(n);
    }
    let result = base!;
    for (let i = dims.length - 1; i >= 0; i -= 1) {
      const size = sizeOf(result) * dims[i];
      if (size > 0xffff) {
        fail("out-of-range", t, "an array can't exceed 65,535 bytes");
      }
      result = { kind: "array", element: result, length: dims[i], size };
    }
    return result;
  }

  private parseArrayTail(base: Type): Type {
    const dims: number[] = [];
    while (this.acceptPunct("[")) {
      const n = this.constantExpression(U16).value as number;
      this.expectPunct("]");
      dims.push(n);
    }
    let result = base;
    for (let i = dims.length - 1; i >= 0; i -= 1) {
      result = {
        kind: "array",
        element: result,
        length: dims[i],
        size: sizeOf(result) * dims[i],
      };
    }
    return result;
  }

  private handleType(id: boolean): Type {
    const name = this.expectName();
    const sym = this.scopes.lookup(name.text);
    if (sym?.kind !== "pool") {
      fail("wrong-class", name, `${name.text} is not a pool`);
    }
    const optional = this.acceptPunct("?");
    return {
      kind: "handle",
      pool: (sym as Symbol & { kind: "pool" }).info,
      id,
      optional,
    };
  }

  // ---- static initializers (chapter 8, 8.9) --------------------------------------

  private staticInitializer(type: Type): number[] {
    const at = this.token;
    switch (type.kind) {
      case "scalar": {
        const v = this.constantExpression(type);
        return this.encodeScalar(v.value, type.name);
      }
      case "string": {
        if (this.token.kind !== "string") {
          fail("syntax", at, "a string initializer needs a string literal");
        }
        const bytes = (this.advance() as Token & { kind: "string" }).bytes;
        if (bytes.length > type.capacity) {
          fail(
            "out-of-range",
            at,
            `the literal has ${bytes.length} bytes; the capacity is ${type.capacity}`,
          );
        }
        const out = new Array(type.size).fill(0);
        out[0] = bytes.length;
        bytes.forEach((b, i) => out[1 + i] = b);
        return out;
      }
      case "record": {
        this.expectPunct("(");
        const out: number[] = [];
        type.fields.forEach((f, i) => {
          if (i > 0) this.expectPunct(",");
          out.push(...this.staticInitializer(f.type));
        });
        this.expectPunct(")");
        return out;
      }
      case "array": {
        this.expectPunct("[");
        const out: number[] = [];
        for (let i = 0; i < type.length; i += 1) {
          if (i > 0) this.expectPunct(",");
          out.push(...this.staticInitializer(type.element));
        }
        this.expectPunct("]");
        return out;
      }
      default:
        fail(
          "static-initializer",
          at,
          `${typeName(type)} can't have a static initializer`,
        );
    }
  }

  private encodeScalar(value: number | boolean, name: ScalarName): number[] {
    if (name === "boolean") return [value ? 1 : 0];
    if (name === "f32") {
      const buf = new DataView(new ArrayBuffer(4));
      buf.setFloat32(0, value as number, true);
      return [
        buf.getUint8(0),
        buf.getUint8(1),
        buf.getUint8(2),
        buf.getUint8(3),
      ];
    }
    let v = (value as number) >>> 0;
    if ((value as number) < 0) v = ((value as number) + 0x100000000) >>> 0;
    const out: number[] = [];
    for (let i = 0; i < SCALARS[name].size; i += 1) {
      out.push(v & 0xff);
      v = Math.floor(v / 256);
    }
    return out;
  }

  // ---- constant expressions (8.6) ------------------------------------------------

  /** Parse an expression that must be constant; returns its typed or exact value. */
  private constantExpression(
    expected?: Type,
  ): { value: number | boolean; type?: Type } {
    const at = this.token;
    const v = this.expression(expected, true);
    if (v.kind !== "const") {
      fail("not-constant", at, "a constant expression is required");
    }
    if (expected) {
      const c = this.coerceConst(v, expected, at);
      return { value: c.value, type: expected };
    }
    return { value: v.value, type: v.type };
  }

  /** Check a constant against a type and give it that type. */
  private coerceConst(
    v: Value & { kind: "const" },
    to: Type,
    at: Position,
  ): Value & { kind: "const" } {
    if (to.kind === "file") {
      if (v.type?.kind === "file") return v;
      fail("type-mismatch", at, "a File value is required");
    }
    if (to.kind !== "scalar") {
      fail("type-mismatch", at, `a ${typeName(to)} is required`);
    }
    if (to.name === "boolean") {
      if (typeof v.value !== "boolean") {
        fail("type-mismatch", at, "a boolean is required");
      }
      return { kind: "const", type: BOOLEAN, value: v.value };
    }
    if (typeof v.value === "boolean") {
      fail("type-mismatch", at, "a number is required");
    }
    if (v.type) {
      if (v.type.kind !== "scalar" || v.type.name === "boolean") {
        fail("type-mismatch", at, "a number is required");
      }
      if (v.type.name === "f32" && to.name !== "f32") {
        fail(
          "type-mismatch",
          at,
          "a floating-point value never adapts to an integer type",
        );
      }
      if (!widens(v.type.name, to.name)) {
        fail(
          "conversion-required",
          at,
          `${v.type.name} doesn't convert to ${to.name} implicitly`,
        );
      }
      return { kind: "const", type: to, value: v.value };
    }
    if (!fits(v.value, to.name)) {
      fail("out-of-range", at, `${v.value} doesn't fit ${to.name}`);
    }
    return { kind: "const", type: to, value: v.value };
  }

  // ---- routines (chapter 13) ------------------------------------------------------

  private parseHeader(subToken: Token): Signature {
    void subToken;
    const name = this.expectName();
    this.expectPunct("(");
    const parameters: Parameter[] = [];
    if (!this.isPunct(")")) {
      do {
        const isVar = this.acceptKeyword("var");
        const pname = this.expectName();
        this.expectKeyword("as");
        const ptype = this.parseType();
        if (
          isVar &&
          (ptype.kind === "scalar" || ptype.kind === "file" ||
            (ptype.kind === "handle" && (ptype.id || !ptype.optional)))
        ) {
          fail(
            "var-parameter",
            pname,
            `var is not allowed on a ${typeName(ptype)} parameter`,
          );
        }
        if (parameters.some((p) => p.name === pname.text)) {
          fail(
            "duplicate-name",
            pname,
            `parameter ${pname.text} is already declared`,
          );
        }
        parameters.push({
          name: pname.text,
          type: ptype,
          var: isVar,
          offset: 0,
        });
      } while (this.acceptPunct(","));
    }
    this.expectPunct(")");
    let result: Type | undefined;
    let varResult = false;
    const from: string[] = [];
    if (this.acceptKeyword("as")) {
      varResult = this.acceptKeyword("var");
      result = this.parseType();
      if (this.isName("from")) {
        this.advance();
        do {
          const n = this.expectName();
          if (
            !parameters.some((p) => p.name === n.text && isAggregate(p.type))
          ) {
            fail("from-clause", n, `${n.text} is not an aggregate parameter`);
          }
          from.push(n.text);
        } while (this.acceptPunct(","));
      }
    }
    const fails = this.acceptKeyword("fails");
    // Offsets: the last parameter is at IX+4; each earlier one is above it.
    let offset = 4;
    for (let i = parameters.length - 1; i >= 0; i -= 1) {
      const p = parameters[i];
      p.offset = offset;
      offset += parameterWords(p.type) * 2;
      if (
        p.var &&
        (p.type.kind === "record" || isOwningType(p.type) ||
          (p.type.kind === "handle" && !p.type.id))
      ) {
        // Every var record parameter carries the owner word, so that id(n)
        // can tell a whole leased node from storage outside any pool
        // (memory safety §5.6, revision 6.1).
        p.ownerOffset = offset;
        offset += 2;
      }
    }
    return {
      name: name.text,
      parameters,
      result,
      varResult,
      from,
      fails,
      argumentBytes: offset - 4,
    };
  }

  private forwardDeclaration(isPrivate: boolean): void {
    const at = this.expectKeyword("forward");
    if (this.isKeyword("pool")) {
      this.advance();
      const name = this.expectName();
      this.expectNewline();
      const info: PoolInfo = { name: name.text, ordinal: this.nextOrdinal };
      this.nextOrdinal += 1;
      const sym: Symbol = {
        kind: "pool",
        name: name.text,
        info,
        forward: true,
      };
      this.scopes.declare(sym, name, isPrivate);
      this.forwardPools.push({
        sym,
        at: name,
        part: this.currentPart,
        private: isPrivate,
      });
      return;
    }
    const sub = this.expectKeyword("sub");
    const sig = this.parseHeader(sub);
    this.expectNewline();
    const blob = this.newBlob(Kind.code, sig.name);
    const sym: Symbol & { kind: "routine" } = {
      kind: "routine",
      name: sig.name,
      signature: sig,
      ordinal: blob.ordinal,
      forward: true,
      complete: false,
      private: isPrivate,
      service: false,
      declaredAt: at,
      part: this.currentPart,
      pendingNeeds: [],
    };
    this.scopes.declare(sym, at, isPrivate);
    this.forwardsOpen.push(sym);
    this.anyForward = true;
    this.blobs.splice(this.blobs.indexOf(blob), 1); // the body's blob is created later
    this.nextOrdinal -= 1;
    sym.ordinal = this.nextOrdinal;
    this.nextOrdinal += 1;
  }

  private routineDefinition(isPrivate: boolean): void {
    const sub = this.expectKeyword("sub");
    let sym: Symbol & { kind: "routine" };
    let wasForward = false;
    if (this.peek().kind === "newline") {
      // Abbreviated header completing a forward.
      const name = this.expectName();
      const existing = this.scopes.lookup(name.text);
      if (existing?.kind !== "routine" || !existing.forward) {
        fail(
          "forward-mismatch",
          name,
          `${name.text} has no incomplete forward declaration`,
        );
      }
      sym = existing as Symbol & { kind: "routine" };
      if (sym.private && sym.part !== this.currentPart) {
        fail(
          "forward-incomplete",
          name,
          `private forward ${name.text} must be completed in its part`,
        );
      }
      if (isPrivate !== sym.private) {
        fail(
          "forward-mismatch",
          name,
          "the completion's visibility must match the forward",
        );
      }
      wasForward = true;
    } else {
      const sig = this.parseHeader(sub);
      const existing = this.scopes.lookup(sig.name);
      if (existing?.kind === "routine" && existing.forward) {
        fail(
          "forward-mismatch",
          sub,
          `${sig.name} was declared forward; complete it with 'sub ${sig.name}'`,
        );
      }
      sym = {
        kind: "routine",
        name: sig.name,
        signature: sig,
        ordinal: 0,
        forward: false,
        complete: false,
        private: isPrivate,
        service: false,
        declaredAt: sub,
        part: this.currentPart,
        pendingNeeds: [],
      };
      this.scopes.declare(sym, sub, isPrivate);
    }
    this.expectNewline();
    const blob = wasForward
      ? (() => {
        const b = new Blob(sym.ordinal, Kind.code, sym.name);
        this.blobs.push(b);
        return b;
      })()
      : this.newBlob(Kind.code, sym.name);
    if (!wasForward) sym.ordinal = blob.ordinal;
    if (sym.name === "main") {
      if (this.mainOrdinal !== undefined) {
        fail("duplicate-name", sub, "main is already defined");
      }
      if (
        sym.signature.parameters.length > 0 || sym.signature.result || isPrivate
      ) {
        fail(
          "bad-main",
          sub,
          "main takes no parameters, returns nothing and can't be private",
        );
      }
      this.mainOrdinal = sym.ordinal;
    }
    this.compileBody(sym, blob, wasForward, sub);
  }

  private compileBody(
    sym: Symbol & { kind: "routine" },
    blob: Blob,
    checked: boolean,
    at: Token,
  ): void {
    const state: RoutineState = {
      symbol: sym,
      blob,
      frame: 0,
      deepest: 0,
      pushed: 0,
      maxCalleeNeed: 0,
      helperStack: 0,
      exitLabel: blob.newLabel(),
      pairLabel: blob.newLabel(),
      loops: [],
      literals: [],
      fallsThrough: true,
    };
    this.routine = state;
    this.scopes.open("routine", sym);
    for (const p of sym.signature.parameters) {
      this.scopes.declare({
        kind: "var",
        name: p.name,
        type: p.type,
        storage: { kind: "frame", offset: p.offset },
        readonly: isAggregate(p.type) && !p.var,
        parameter: p,
        flow: p.type.kind === "handle" && !p.type.id ? "value" : undefined,
        ownerOffset: p.ownerOffset,
      }, at);
    }
    blob.line(at.part, at.line);
    // Prologue.
    if (checked) {
      blob.u8(0x2a); // LD HL,(need): the pair label marks need(R)
      blob.labelOperand(state.pairLabel);
      blob.callBlob(Helper.STKCHK);
      state.helperStack = Math.max(state.helperStack, 2);
    }
    blob.u8(0xdd, 0xe5); // PUSH IX
    blob.u8(0xdd, 0x21, 0, 0); // LD IX,0
    blob.u8(0xdd, 0x39); // ADD IX,SP
    blob.u8(0x21); // LD HL,-frame (patched)
    state.framePatch = blob.offset;
    blob.u16(0);
    blob.u8(0x39); // ADD HL,SP
    blob.u8(0xf9); // LD SP,HL
    // Body.
    this.block(["end"]);
    this.expectKeyword("end");
    this.expectNewline();
    if (sym.signature.result && state.fallsThrough) {
      fail(
        "missing-return",
        this.token,
        `${sym.name} can reach its end without returning a value`,
      );
    }
    // The success exit: carry clear for fails routines and main.
    if (state.fallsThrough) this.emitReturn(undefined, at);
    blob.defineLabel(state.exitLabel);
    const argBytes = sym.signature.argumentBytes;
    if (argBytes === 0) {
      blob.u8(0xdd, 0xf9); // LD SP,IX
      blob.u8(0xdd, 0xe1); // POP IX
      blob.u8(0xc9); // RET
    } else {
      blob.u8(0xfd, 0x21); // LD IY,n
      blob.u16(argBytes);
      blob.jpBlob(Helper.RETN);
      state.helperStack = Math.max(state.helperStack, 4);
    }
    // The frame and need pair, then the literals.
    const frame = -state.deepest;
    blob.bytes[state.framePatch!] = (-frame) & 0xff;
    blob.bytes[state.framePatch! + 1] = ((-frame) >> 8) & 0xff;
    const need = frame + 4 + state.helperStack + state.maxCalleeNeed; // 4: IX and the return address
    // The pair sits after the code: frame, then need; the prologue's
    // LD HL,(need) reads the second word through the pair label.
    blob.u16(frame);
    blob.defineLabel(state.pairLabel);
    blob.u16(need);
    for (const lit of state.literals) {
      blob.defineLabel(lit.label);
      blob.raw(lit.bytes);
    }
    sym.need = need;
    sym.frame = frame;
    sym.complete = true;
    sym.forward = false;
    this.largestFrame = Math.max(this.largestFrame, frame);
    this.lineBlobs.push({ ordinal: blob.ordinal, entries: blob.lines });
    this.scopes.close();
    this.routine = undefined;
  }

  // ---- frames -------------------------------------------------------------------

  private allocLocal(size: number): number {
    const r = this.routine!;
    r.frame -= size;
    r.deepest = Math.min(r.deepest, r.frame - r.pushed);
    return r.frame;
  }

  /** Push the value in the registers for its size; pop it back. */
  private pushValue(size: number): void {
    const r = this.routine!;
    if (size === 1) r.blob.u8(0xf5); // PUSH AF
    else if (size === 2) r.blob.u8(0xe5); // PUSH HL
    else r.blob.u8(0xd5, 0xe5); // PUSH DE; PUSH HL
    this.push(size === 4 ? 4 : 2);
  }

  private popValue(size: number): void {
    const r = this.routine!;
    if (size === 1) r.blob.u8(0xf1); // POP AF
    else if (size === 2) r.blob.u8(0xe1); // POP HL
    else r.blob.u8(0xe1, 0xd1); // POP HL; POP DE
    this.pop(size === 4 ? 4 : 2);
  }

  private push(bytes: number): void {
    const r = this.routine!;
    r.pushed += bytes;
    r.deepest = Math.min(r.deepest, r.frame - r.pushed);
  }

  private pop(bytes: number): void {
    this.routine!.pushed -= bytes;
  }

  private callHelper(ordinal: number): void {
    const r = this.routine!;
    r.blob.callBlob(ordinal);
    r.helperStack = Math.max(r.helperStack, HELPER_STACK[ordinal] ?? 2);
  }

  private noteCall(callee: Symbol & { kind: "routine" }, at: Token): void {
    const r = this.routine!;
    if (callee === r.symbol || !callee.complete) {
      if (!callee.forward && !callee.service) {
        fail(
          "recursion-needs-forward",
          at,
          `${callee.name} is not complete; declare it forward`,
        );
      }
      return; // counts 0, per memory safety §7
    }
    r.maxCalleeNeed = Math.max(r.maxCalleeNeed, callee.need ?? 0);
  }

  // ---- blocks and statements (chapter 10) ------------------------------------------

  /** Compile statements until one of the terminators; the block scope is the caller's. */
  private block(terminators: Keyword[], bind?: () => void): void {
    this.scopes.open("block");
    const r = this.routine!;
    const frameAtEntry = r.frame;
    r.fallsThrough = true;
    if (bind) bind();
    while (true) {
      const t = this.token;
      if (t.kind === "newline") {
        this.advance();
        continue;
      }
      if (t.kind === "eof") fail("syntax", t, "unexpected end of the source");
      if (t.kind === "keyword" && terminators.includes(t.text)) break;
      this.statement();
    }
    this.emitFrees([this.scopes.current]);
    this.scopes.close();
    r.frame = frameAtEntry;
  }

  private statement(): void {
    const t = this.token;
    const r = this.routine!;
    r.blob.line(t.part, t.line);
    this.stmtDirect.clear();
    this.stmtMoved.clear();
    if (!r.fallsThrough) {
      // Unreachable statements are still compiled; nothing to diagnose.
    }
    if (this.isKeyword("var")) this.localVar();
    else if (this.isKeyword("const")) this.constDeclaration(false);
    else if (this.isKeyword("if")) this.ifStatement();
    else if (this.isKeyword("while")) this.whileStatement();
    else if (this.isKeyword("for")) this.forStatement();
    else if (this.isKeyword("select")) this.selectStatement();
    else if (this.isKeyword("return")) this.returnStatement();
    else if (this.isKeyword("fail")) this.failStatement();
    else if (this.isKeyword("assert")) this.assertStatement();
    else if (this.isKeyword("exit")) this.exitStatement("exit");
    else if (this.isKeyword("continue")) this.exitStatement("continue");
    else if (t.kind === "name") this.nameStatement();
    else fail("syntax", t, `expected a statement, found ${this.describe(t)}`);
  }

  private localVar(): void {
    this.expectKeyword("var");
    const name = this.expectName();
    let type: Type | undefined;
    if (this.acceptKeyword("as")) type = this.parseType();
    if (!type && !this.isPunct("=")) {
      fail("syntax", this.token, "a local without a type needs an initializer");
    }
    const r = this.routine!;
    if (this.acceptPunct("=")) {
      if (
        type &&
        (type.kind === "record" || type.kind === "array" ||
          type.kind === "string") &&
        this.startsStaticInitializer()
      ) {
        const bytes = this.staticInitializer(type);
        const offset = this.allocLocal(bytes.length);
        this.storeBytesToFrame(bytes, offset);
        this.declareLocal(name, type, offset);
        this.expectNewline();
        return;
      }
      const at = this.token;
      const v = this.expression(type);
      let actual: Type;
      if (type) {
        actual = type;
      } else {
        if (v.kind === "const" && !v.type) {
          fail(
            "no-definite-type",
            at,
            "the initializer has no definite type; write the type",
          );
        }
        if (v.kind === "literal") {
          fail(
            "no-definite-type",
            at,
            "a string literal has no definite type; write the type",
          );
        }
        if (v.kind === "none") {
          fail(
            "no-definite-type",
            at,
            "none has no definite type; write the type",
          );
        }
        actual = (v as { type: Type }).type;
      }
      if (isAggregate(actual)) {
        if (v.kind !== "address") {
          fail("type-mismatch", at, "an aggregate initializer is required");
        }
        if (isOwningType(actual)) {
          fail("owning-copy", at, `${typeName(actual)} can't be copied`);
        }
        const offset = this.allocLocal(sizeOf(actual));
        this.copyToFrame(actual, offset);
        this.declareLocal(name, actual, offset);
      } else if (actual.kind === "handle" && !actual.id) {
        this.ownValue(v, actual, at);
        this.callHelper(Helper.LINK0);
        const offset = this.allocLocal(2);
        this.storeRegisters(U16, { kind: "frame", offset });
        this.declareLocal(
          name,
          actual,
          offset,
          v.kind === "none" ? "none" : "value",
        );
      } else {
        this.toRegisters(v, actual, at);
        const offset = this.allocLocal(sizeOf(actual));
        this.storeRegisters(actual, { kind: "frame", offset });
        this.declareLocal(name, actual, offset);
      }
      this.nameStatementTail(name, undefined);
      return;
    }
    if (type!.kind === "handle" && !type!.optional) {
      fail(
        "needs-initializer",
        name,
        "a non-optional handle local needs an initializer",
      );
    }
    const size = sizeOf(type!);
    const offset = this.allocLocal(size);
    this.zeroFrame(offset, size);
    this.declareLocal(name, type!, offset, "none");
    this.expectNewline();
  }

  private startsStaticInitializer(): boolean {
    return this.isPunct("(") || this.isPunct("[") ||
      this.token.kind === "string";
  }

  private declareLocal(
    name: Token,
    type: Type,
    offset: number,
    flow?: Flow,
  ): void {
    this.scopes.declare({
      kind: "var",
      name: (name as Token & { kind: "name" }).text,
      type,
      storage: { kind: "frame", offset },
      readonly: false,
      flow: type.kind === "handle" && !type.id ? (flow ?? "none") : undefined,
    }, name);
  }

  private nameStatement(): void {
    const name = this.token as Token & { kind: "name" };
    const sym = this.scopes.lookup(name.text);
    if (!sym) fail("undeclared-name", name, `${name.text} is not declared`);
    if (sym!.kind === "routine") {
      this.advance();
      const v = this.call(sym as Symbol & { kind: "routine" }, name);
      this.discard(v);
      this.nameStatementTail(name, sym as Symbol & { kind: "routine" });
      return;
    }
    if (sym!.kind !== "var" && sym!.kind !== "aggregateConst") {
      fail("wrong-class", name, `${name.text} can't start a statement`);
    }
    const d = this.designator();
    this.expectPunct("=");
    if (d.readonly) fail("not-writable", name, `${name.text} is read-only`);
    if (d.symbol?.counting) {
      fail("not-writable", name, `${name.text} is a loop counter`);
    }
    this.assign(d, name);
    this.nameStatementTail(name, undefined);
  }

  /** After a call or assignment: NEWLINE, `else fail`, or `handle NAME`. */
  private nameStatementTail(
    at: Token,
    callee?: Symbol & { kind: "routine" },
  ): void {
    const pending = this.pendingFailure;
    this.pendingFailure = undefined;
    if (this.acceptKeyword("else")) {
      this.expectKeyword("fail");
      if (!pending || pending.kind !== "fail") {
        fail(
          "not-failable",
          at,
          "else fail follows a call to a routine that fails",
        );
      }
      this.expectNewline();
      return;
    }
    if (this.acceptKeyword("handle")) {
      if (!pending || pending.kind !== "handle") {
        fail(
          "not-failable",
          at,
          "handle follows a call to a routine that fails",
        );
      }
      const dest = this.expectName();
      const sym = this.scopes.lookup(dest.text);
      if (
        sym?.kind !== "var" || !isScalar(sym.type, "u8") || sym.readonly ||
        sym.counting
      ) {
        fail("handle-destination", dest, "handle needs a writable u8 variable");
      }
      this.expectNewline();
      const r = this.routine!;
      const skip = r.blob.newLabel();
      r.blob.jp(skip);
      r.blob.defineLabel(pending.failLabel);
      this.storeRegisters(U8, (sym as Symbol & { kind: "var" }).storage);
      this.block(["end"]);
      this.expectKeyword("end");
      this.expectNewline();
      r.blob.defineLabel(skip);
      r.fallsThrough = true;
      return;
    }
    if (pending) {
      fail(
        "failure-unconsumed",
        at,
        `${callee?.name ?? "the call"} fails; add else fail or handle`,
      );
    }
    this.expectNewline();
  }

  /** Set by a failing call: how its failure is consumed. */
  private pendingFailure?: { kind: "fail" } | {
    kind: "handle";
    failLabel: number;
  };

  private returnStatement(): void {
    const at = this.expectKeyword("return");
    const r = this.routine!;
    const sig = r.symbol.signature;
    if (this.token.kind === "newline") {
      if (sig.result) fail("return-form", at, "this routine returns a value");
      this.emitReturn(undefined, at);
    } else {
      if (!sig.result) fail("return-form", at, "this routine returns nothing");
      const exprAt = this.token;
      const v = this.expression(sig.result);
      this.emitReturn(v, exprAt);
    }
    this.expectNewline();
    r.fallsThrough = false;
  }

  private emitReturn(v: Value | undefined, at: Token): void {
    const r = this.routine!;
    const sig = r.symbol.signature;
    if (sig.result) {
      if (isAggregate(sig.result)) {
        if (v!.kind !== "address") {
          fail("type-mismatch", at, "an aggregate result is required");
        }
        // Alias rules (7.7): program storage or a from parameter.
        this.checkAliasEscape(v!, at);
      } else if (sig.result.kind === "handle" && !sig.result.id) {
        this.ownValue(v!, sig.result, at);
        this.callHelper(Helper.LINK0);
      } else {
        this.toRegisters(v!, sig.result, at);
      }
    }
    // Free the owning locals and parameters of every open scope, keeping
    // the result safe on the stack.
    const size = sig.result ? sizeOf(sig.result) : 0;
    const owners = this.scopes.scopesFrom(this.scopes.routineDepth());
    const anyOwner = owners.some((sc) =>
      [...sc.symbols.values()].some((x) =>
        x.kind === "var" && x.storage.kind === "frame" && !x.lease &&
        isOwningType(x.type)
      )
    );
    if (anyOwner) {
      if (size === 1) r.blob.u8(0xf5);
      else if (size === 2) r.blob.u8(0xe5);
      else if (size === 4) r.blob.u8(0xd5, 0xe5);
      this.emitFrees(owners);
      if (size === 1) r.blob.u8(0xf1);
      else if (size === 2) r.blob.u8(0xe1);
      else if (size === 4) r.blob.u8(0xe1, 0xd1);
    }
    if (sig.fails || r.symbol.name === "main") r.blob.u8(0xb7); // OR A: carry clear
    r.blob.jp(r.exitLabel);
  }

  private lastAddressRoot?: Symbol & { kind: "var" };
  private lastDesignator?: Designator;

  private checkAliasEscape(_v: Value, at: Token): void {
    const root = this.lastAddressRoot;
    if (!root) return; // program storage or a result forwarded
    if (root.storage.kind === "frame") {
      const p = root.parameter;
      const sig = this.routine!.symbol.signature;
      if (!p || !sig.from.includes(p.name)) {
        fail(
          "alias-escapes",
          at,
          "a result can't be rooted in a local or a parameter not named in from",
        );
      }
    }
  }

  private failStatement(): void {
    const at = this.expectKeyword("fail");
    const r = this.routine!;
    if (!r.symbol.signature.fails) {
      fail("not-failable", at, "fail needs a routine declared fails");
    }
    const v = this.expression(U8);
    this.toRegisters(v, U8, at);
    this.expectNewline();
    r.blob.u8(0xf5); // PUSH AF
    this.emitFrees(this.scopes.scopesFrom(this.scopes.routineDepth()));
    r.blob.u8(0xf1); // POP AF
    r.blob.u8(0x37); // SCF
    r.blob.jp(r.exitLabel);
    r.fallsThrough = false;
  }

  private assertStatement(): void {
    const at = this.expectKeyword("assert");
    const r = this.routine!;
    const v = this.expression(BOOLEAN);
    if (v.kind === "const") {
      if (v.value !== true) {
        fail("assertion-false", at, "the assertion is certainly false");
      }
      this.expectNewline();
      return;
    }
    this.toRegisters(v, BOOLEAN, at);
    r.blob.u8(0xb7); // OR A
    r.blob.callBlobIf(JP_Z, Helper.TRAP_ASSERTION);
    this.expectNewline();
  }

  private exitStatement(word: "exit" | "continue"): void {
    const at = this.expectKeyword(word);
    const r = this.routine!;
    const loop = r.loops.at(-1);
    if (!loop) fail("outside-loop", at, `${word} needs an enclosing loop`);
    this.expectNewline();
    if (word === "continue") this.checkBackEdge(loop!.entryFlow, at);
    this.emitFrees(this.scopes.scopesFrom(loop!.depth));
    r.blob.jp(word === "exit" ? loop!.exit : loop!.next);
    r.fallsThrough = false;
  }

  // ---- conditionals and loops (chapters 11 and 12) ---------------------------------

  private ifStatement(): void {
    this.expectKeyword("if");
    const r = this.routine!;
    const end = r.blob.newLabel();
    let anyFalls = false;
    let hasElse = false;
    let next = r.blob.newLabel();
    this.condition(next);
    this.expectNewline();
    const entryFlow = this.snapshotFlow();
    const armFlows: Map<Symbol, Flow>[] = [];
    this.block(["elseif", "else", "end"]);
    anyFalls ||= r.fallsThrough;
    if (r.fallsThrough) armFlows.push(this.snapshotFlow());
    this.restoreFlow(entryFlow);
    r.blob.jp(end);
    while (true) {
      if (this.acceptKeyword("elseif")) {
        r.blob.defineLabel(next);
        next = r.blob.newLabel();
        this.condition(next);
        this.expectNewline();
        this.block(["elseif", "else", "end"]);
        anyFalls ||= r.fallsThrough;
        if (r.fallsThrough) armFlows.push(this.snapshotFlow());
        this.restoreFlow(entryFlow);
        r.blob.jp(end);
        continue;
      }
      if (this.acceptKeyword("else")) {
        if (this.isKeyword("if")) {
          fail("syntax", this.token, "write elseif, not else if");
        }
        hasElse = true;
        this.expectNewline();
        r.blob.defineLabel(next);
        next = r.blob.newLabel();
        this.block(["end"]);
        anyFalls ||= r.fallsThrough;
        if (r.fallsThrough) armFlows.push(this.snapshotFlow());
        break;
      }
      break;
    }
    this.expectKeyword("end");
    this.expectNewline();
    r.blob.defineLabel(next);
    r.blob.defineLabel(end);
    if (!hasElse) armFlows.push(entryFlow);
    this.meetFlow(armFlows);
    r.fallsThrough = anyFalls || !hasElse;
  }

  // ---- select (11.7) ----------------------------------------------------------------

  private selectStatement(): void {
    const at = this.expectKeyword("select");
    const r = this.routine!;
    const isMove = this.acceptKeyword("move");
    const subjectAt = this.token;
    let subjectDesignator: Designator | undefined;
    let v: Value;
    if (
      this.token.kind === "name" &&
      this.scopes.lookup(this.token.text)?.kind === "var"
    ) {
      subjectDesignator = this.designator();
      if (subjectDesignator.type.kind === "handle") {
        this.selectHandle(subjectDesignator, isMove, subjectAt, at);
        return;
      }
      v = this.loadDesignator(subjectDesignator);
    } else {
      v = this.expression();
      if (
        (v.kind === "reg" || v.kind === "fresh") && v.type.kind === "handle"
      ) {
        this.selectHandle(undefined, isMove, subjectAt, at, v);
        return;
      }
    }
    if (isMove) fail("syntax", at, "select move takes an owning handle");
    if (v.kind === "const" && !v.type) {
      fail("no-definite-type", subjectAt, "a select subject needs a type");
    }
    const type = v.kind === "const"
      ? v.type!
      : v.kind === "reg"
      ? v.type
      : undefined;
    if (!type || type.kind === "handle") {
      fail("type-mismatch", subjectAt, "select takes an integer or a handle");
    }
    if (!isInteger(type)) {
      fail(
        "type-mismatch",
        subjectAt,
        "select takes an integer or an optional handle",
      );
    }
    const name = (type as { name: ScalarName }).name;
    const s = SCALARS[name];
    if (s.size > 2) throw new NotImplemented("32-bit select");
    this.expectNewline();
    // The subject lives in a hidden local for the arms' comparisons.
    this.toRegisters(v, type, subjectAt);
    const subject = this.allocLocal(s.size);
    this.storeRegisters(type, { kind: "frame", offset: subject });
    const end = r.blob.newLabel();
    const covered: [number, number][] = [];
    let sawElse = false;
    let anyArm = false;
    let anyFalls = false;
    const entryFlow = this.snapshotFlow();
    const armFlows: Map<Symbol, Flow>[] = [];
    while (true) {
      if (this.token.kind === "newline") {
        this.advance();
        continue;
      }
      if (this.isKeyword("end")) break;
      this.restoreFlow(entryFlow);
      const caseAt = this.expectKeyword("case");
      if (sawElse) fail("syntax", caseAt, "case else must be last");
      const body = r.blob.newLabel();
      const next = r.blob.newLabel();
      if (this.acceptKeyword("else")) {
        sawElse = true;
        this.expectNewline();
        r.blob.defineLabel(body);
        this.block(["case", "end"]);
        anyFalls ||= r.fallsThrough;
        if (r.fallsThrough) armFlows.push(this.snapshotFlow());
        r.blob.jp(end);
        r.blob.defineLabel(next);
        continue;
      }
      if (this.isKeyword("some") || this.isKeyword("none")) {
        fail(
          "type-mismatch",
          this.token,
          "some and none select on a handle, not an integer",
        );
      }
      anyArm = true;
      // Labels: constants and ranges, tested in turn.
      do {
        const labelAt = this.token;
        const low = this.constantExpression(type).value as number;
        let high = low;
        if (this.acceptKeyword("to")) {
          high = this.constantExpression(type).value as number;
          if (high < low) {
            fail(
              "syntax",
              labelAt,
              "a range's low bound exceeds its high bound",
            );
          }
        }
        for (const [a, b] of covered) {
          if (low <= b && high >= a) {
            fail(
              "duplicate-case",
              labelAt,
              "this label overlaps an earlier one",
            );
          }
        }
        covered.push([low, high]);
        this.emitLabelTest(subject, name, low, high, body);
      } while (this.acceptPunct(","));
      this.expectNewline();
      r.blob.jp(next);
      r.blob.defineLabel(body);
      this.block(["case", "end"]);
      anyFalls ||= r.fallsThrough;
      if (r.fallsThrough) armFlows.push(this.snapshotFlow());
      r.blob.jp(end);
      r.blob.defineLabel(next);
    }
    if (!anyArm) fail("syntax", at, "select needs at least one case");
    this.expectKeyword("end");
    this.expectNewline();
    r.blob.defineLabel(end);
    if (!sawElse) armFlows.push(entryFlow);
    this.meetFlow(armFlows);
    r.fallsThrough = anyFalls || !sawElse;
  }

  /** select on an optional handle or an identifier (11.7.3). */
  private selectHandle(
    d: Designator | undefined,
    isMove: boolean,
    subjectAt: Token,
    at: Token,
    value?: Value,
  ): void {
    const r = this.routine!;
    const type = (d ? d.type : (value as { type: Type }).type) as Type & {
      kind: "handle";
    };
    if (type.pool.record === undefined) {
      fail(
        "pool-incomplete",
        subjectAt,
        `pool ${type.pool.name} is only forward-declared`,
      );
    }
    const record = type.pool.record!;
    const owning = !type.id;
    if (owning && !type.optional && !isMove) {
      fail(
        "type-mismatch",
        subjectAt,
        "a non-optional owning handle always holds a value",
      );
    }
    const subjectSym = d?.symbol;
    const isLocalOwner = owning && d !== undefined && d.rootOnly === true &&
      d.symbol?.storage.kind === "frame" && !d.symbol.lease;
    if (isMove) {
      if (!d || !owning || !type.optional || d.readonly) {
        fail(
          "syntax",
          at,
          "select move takes a writable optional owning location",
        );
      }
      this.noteMove(d);
      this.emitMove(d);
    } else if (d) {
      if (owning) this.noteDirect(d);
      this.checkUsable(d);
      this.loadValue(d);
    } else {
      this.toRegisters(value!, type, subjectAt);
    }
    const temp = this.allocLocal(owning ? 2 : 4);
    this.storeRegisters(owning ? U16 : type, { kind: "frame", offset: temp });
    this.expectNewline();
    const end = r.blob.newLabel();
    let sawSome = false, sawNone = false, sawElse = false;
    let anyFalls = false;
    const entryFlow = this.snapshotFlow();
    const armFlows: Map<Symbol, Flow>[] = [];
    while (true) {
      if (this.token.kind === "newline") {
        this.advance();
        continue;
      }
      if (this.isKeyword("end")) break;
      this.restoreFlow(entryFlow);
      const caseAt = this.expectKeyword("case");
      if (sawElse) fail("syntax", caseAt, "case else must be last");
      const next = r.blob.newLabel();
      if (this.acceptKeyword("some")) {
        if (sawSome) fail("syntax", caseAt, "a second some arm");
        sawSome = true;
        this.expectPunct("(");
        const name = this.expectName();
        this.expectPunct(")");
        this.expectNewline();
        this.loadRegisters(owning ? U16 : type, {
          kind: "frame",
          offset: temp,
        });
        if (owning) r.blob.u8(0x7c, 0xb5); // LD A,H; OR L
        else this.callHelper(Helper.ID_TEST);
        r.blob.jpIf(JP_Z, next);
        const bind = () => {
          if (isMove) {
            const offset = this.allocLocal(2);
            this.loadRegisters(U16, { kind: "frame", offset: temp });
            this.callHelper(Helper.LINK0);
            this.storeRegisters(U16, { kind: "frame", offset });
            this.scopes.declare({
              kind: "var",
              name: name.text,
              type: {
                kind: "handle",
                pool: type.pool,
                id: false,
                optional: false,
              },
              storage: { kind: "frame", offset },
              readonly: false,
              flow: "value",
            }, name);
          } else if (!owning) {
            const offset = this.allocLocal(4);
            this.loadRegisters(type, { kind: "frame", offset: temp });
            this.storeRegisters(type, { kind: "frame", offset });
            this.scopes.declare({
              kind: "var",
              name: name.text,
              type: {
                kind: "handle",
                pool: type.pool,
                id: true,
                optional: false,
              },
              storage: { kind: "frame", offset },
              readonly: false,
            }, name);
          } else if (isLocalOwner || value?.kind === "fresh") {
            this.scopes.declare({
              kind: "var",
              name: name.text,
              type: record,
              storage: { kind: "frame", offset: temp },
              readonly: false,
              lease: true,
              slotOffset: temp,
            }, name);
            if (subjectSym) subjectSym.counting = true;
          } else {
            const offset = this.allocLocal(4);
            this.loadRegisters(U16, { kind: "frame", offset: temp });
            this.callHelper(Helper.ID_MAKE);
            const idType: Type = {
              kind: "handle",
              pool: type.pool,
              id: true,
              optional: false,
            };
            this.storeRegisters(idType, { kind: "frame", offset });
            this.scopes.declare({
              kind: "var",
              name: name.text,
              type: idType,
              storage: { kind: "frame", offset },
              readonly: false,
            }, name);
          }
        };
        this.block(["case", "end"], bind);
        if (subjectSym) subjectSym.counting = false;
        anyFalls ||= r.fallsThrough;
        if (r.fallsThrough) armFlows.push(this.snapshotFlow());
        r.blob.jp(end);
        r.blob.defineLabel(next);
        continue;
      }
      const isNone = this.acceptKeyword("none");
      if (!isNone) this.expectKeyword("else");
      if (sawNone || sawElse) {
        fail("syntax", caseAt, "a second none or else arm");
      }
      if (isNone) sawNone = true;
      else sawElse = true;
      this.expectNewline();
      this.loadRegisters(owning ? U16 : type, { kind: "frame", offset: temp });
      if (owning) r.blob.u8(0x7c, 0xb5);
      else this.callHelper(Helper.ID_TEST);
      r.blob.jpIf(JP_NZ, next);
      this.block(["case", "end"]);
      anyFalls ||= r.fallsThrough;
      if (r.fallsThrough) armFlows.push(this.snapshotFlow());
      r.blob.jp(end);
      r.blob.defineLabel(next);
    }
    if (!sawSome) fail("syntax", at, "a handle select needs a some arm");
    this.expectKeyword("end");
    this.expectNewline();
    r.blob.defineLabel(end);
    if (!sawNone && !sawElse) armFlows.push(entryFlow);
    this.meetFlow(armFlows);
    r.fallsThrough = anyFalls || !(sawNone || sawElse);
  }

  // ---- pools (chapter 7) ---------------------------------------------------------------

  private poolDeclaration(isPrivate: boolean): void {
    this.expectKeyword("pool");
    const name = this.expectName();
    this.expectKeyword("as");
    const recName = this.token;
    if (recName.kind !== "name") {
      fail("pool-needs-record", recName, "a pool holds records");
    }
    this.advance();
    const recSym = this.scopes.lookup(
      (recName as Token & { kind: "name" }).text,
    );
    if (recSym?.kind !== "record") {
      fail("pool-needs-record", recName, "a pool holds records");
    }
    const record = (recSym as Symbol & { kind: "record" }).type;
    this.expectPunct("[");
    const capacity = this.constantExpression(U16).value as number;
    if (capacity < 1) {
      fail("out-of-range", name, "a pool needs at least one slot");
    }
    this.expectPunct("]");
    this.expectNewline();
    const existing = this.scopes.lookup(name.text);
    let sym: Symbol & { kind: "pool" };
    if (existing?.kind === "pool" && existing.forward) {
      sym = existing as Symbol & { kind: "pool" };
      const f = this.forwardPools.find((x) => x.sym === sym)!;
      if (f.private !== isPrivate) {
        fail(
          "forward-mismatch",
          name,
          "the pool's visibility must match its forward declaration",
        );
      }
      if (f.private && f.part !== this.currentPart) {
        fail(
          "forward-incomplete",
          name,
          "a private forward pool is completed in its part",
        );
      }
    } else {
      sym = {
        kind: "pool",
        name: name.text,
        info: { name: name.text, ordinal: this.nextOrdinal },
        forward: false,
      };
      this.nextOrdinal += 1;
      this.scopes.declare(sym, name, isPrivate);
    }
    const slotSize = record.size + 6;
    if (6 + capacity * slotSize > 0xffff) {
      fail("out-of-range", name, "the pool exceeds 65,535 bytes");
    }
    const storage = this.newBlob(Kind.bss, `${name.text}.slots`);
    for (let i = 0; i < 6 + capacity * slotSize; i += 1) storage.bytes.push(0);
    const info = new Blob(sym.info.ordinal, Kind.rodata, name.text);
    this.blobs.push(info);
    info.abs16(storage.ordinal);
    info.u16(slotSize);
    info.u16(capacity);
    if (record.owning) info.abs16(this.descriptorOf(record));
    else info.u16(0);
    sym.info.record = record;
    sym.info.capacity = capacity;
    sym.info.storageOrdinal = storage.ordinal;
    sym.forward = false;
    record.pools.push(sym.info);
  }

  /** The ownership descriptor of a type (memory safety §5.10), emitted once. */
  private descriptorOf(type: Type): number {
    if (type.kind === "record" && type.descriptorOrdinal !== undefined) {
      return type.descriptorOrdinal;
    }
    const entries = owningEntries(type);
    if (entries.length > 255) {
      fail(
        "capacity",
        this.token,
        `${typeName(type)} has more than 255 owning fields`,
      );
    }
    const blob = this.newBlob(Kind.rodata, `${typeName(type)}.owners`);
    blob.u8(entries.length);
    for (const e of entries) {
      blob.u8(e.stride === undefined ? 0 : 1);
      blob.u16(e.offset);
      if (e.stride !== undefined) {
        blob.u16(e.stride);
        blob.u16(e.count!);
      }
    }
    if (type.kind === "record") type.descriptorOrdinal = blob.ordinal;
    return blob.ordinal;
  }

  /** new P(args) and new? P(args) (7.10, 9.13). */
  private newExpression(optional: boolean, at: Token): Value {
    const r = this.routine!;
    const name = this.expectName();
    const sym = this.scopes.lookup(name.text);
    if (sym?.kind !== "pool") {
      fail("wrong-class", name, `${name.text} is not a pool`);
    }
    const pool = (sym as Symbol & { kind: "pool" }).info;
    if (!pool.record) {
      fail(
        "pool-incomplete",
        name,
        `pool ${name.text} is only forward-declared`,
      );
    }
    const record = pool.record!;
    this.expectPunct("(");
    r.blob.u8(0x21); // LD HL,info
    r.blob.abs16(pool.ordinal);
    this.callHelper(Helper.POOL_TRY);
    r.blob.u8(0x7c, 0xb5); // LD A,H; OR L
    const done = r.blob.newLabel();
    if (optional) r.blob.jpIf(JP_Z, done);
    else r.blob.callBlobIf(JP_Z, Helper.TRAP_POOL_FULL);
    const temp = this.allocLocal(2);
    this.storeRegisters(U16, { kind: "frame", offset: temp });
    let i = 0;
    if (!this.isPunct(")")) {
      do {
        if (i >= record.fields.length) {
          fail(
            "arity",
            this.token,
            `${record.name} has ${record.fields.length} fields`,
          );
        }
        const f = record.fields[i];
        i += 1;
        const dest: Designator = {
          place: { kind: "computed" },
          type: f.type,
          readonly: false,
          compute: () => {
            this.loadRegisters(U16, { kind: "frame", offset: temp });
            this.addConst(f.offset);
          },
          slotTemp: temp,
          slotKind: "owner",
        };
        this.assign(dest, this.token);
      } while (this.acceptPunct(","));
    }
    this.expectPunct(")");
    this.loadRegisters(U16, { kind: "frame", offset: temp });
    r.blob.defineLabel(done);
    void at;
    return {
      kind: "fresh",
      type: { kind: "handle", pool, id: false, optional },
    };
  }

  /** move d: the handle out of an owning location, leaving none (9.13). */
  private moveExpression(at: Token): Value {
    const d = this.designator();
    if (d.type.kind !== "handle" || d.type.id) {
      fail("not-owner", at, "move takes an owning handle location");
    }
    if (d.readonly) fail("not-writable", at, "the location is read-only");
    this.checkUsable(d);
    this.noteMove(d, at);
    this.emitMove(d);
    if (d.rootOnly && d.symbol?.flow !== undefined) {
      d.symbol.flow = (d.type as { optional: boolean }).optional
        ? "none"
        : "maybe";
    }
    return { kind: "fresh", type: d.type };
  }

  /** HL = the handle at d; none is stored there. */
  private emitMove(d: Designator): void {
    const r = this.routine!;
    if (d.place.kind === "computed" || d.place.kind === "alias") {
      this.emitAddress(d);
      // LD E,(HL); LD (HL),0; INC HL; LD D,(HL); LD (HL),0; EX DE,HL
      r.blob.u8(0x5e, 0x36, 0x00, 0x23, 0x56, 0x36, 0x00, 0xeb);
      return;
    }
    this.loadRegisters(U16, d.place);
    r.blob.u8(0xe5, 0x21, 0x00, 0x00); // PUSH HL; LD HL,0
    this.storeRegisters(U16, d.place);
    r.blob.u8(0xe1); // POP HL
  }

  /** id(x) (7.9, 7.14). */
  private idExpression(at: Token): Value {
    const r = this.routine!;
    this.expectPunct("(");
    const d = this.designator();
    this.expectPunct(")");
    if (d.type.kind === "handle" && !d.type.id) {
      this.checkUsable(d);
      this.loadValue(d);
      this.callHelper(Helper.ID_MAKE);
      return {
        kind: "reg",
        type: {
          kind: "handle",
          pool: d.type.pool,
          id: true,
          optional: d.type.optional,
        },
      };
    }
    if (
      d.type.kind === "record" && d.rootOnly && d.symbol &&
      (d.symbol.lease || d.symbol.ownerOffset !== undefined)
    ) {
      const pools = d.type.pools;
      if (pools.length !== 1) {
        fail(
          "id-ambiguous",
          at,
          `${d.type.name} belongs to ${pools.length} pools`,
        );
      }
      const owner = d.symbol.lease
        ? d.symbol.slotOffset!
        : d.symbol.ownerOffset!;
      const alias = d.symbol.storage.offset;
      const none = r.blob.newLabel();
      const done = r.blob.newLabel();
      r.blob.u8(0xdd, 0x6e, owner & 0xff, 0xdd, 0x66, (owner + 1) & 0xff); // LD HL,owner
      r.blob.u8(0xdd, 0x5e, alias & 0xff, 0xdd, 0x56, (alias + 1) & 0xff); // LD DE,alias
      r.blob.u8(0xb7, 0xed, 0x52); // OR A; SBC HL,DE
      r.blob.jpIf(JP_NZ, none);
      r.blob.u8(0xeb); // EX DE,HL: HL = the record
      this.callHelper(Helper.ID_MAKE);
      r.blob.jp(done);
      r.blob.defineLabel(none);
      r.blob.u8(0x21, 0, 0, 0x11, 0, 0); // LD HL,0; LD DE,0
      r.blob.defineLabel(done);
      return {
        kind: "reg",
        type: { kind: "handle", pool: pools[0], id: true, optional: true },
      };
    }
    fail("not-owner", at, "id takes an owning handle or a record parameter");
  }

  /** Load the value at a designator into the registers for its type. */
  private loadValue(d: Designator): void {
    if (d.place.kind === "computed" || d.place.kind === "alias") {
      this.emitAddress(d);
      this.loadRegistersIndirect(d.type);
    } else this.loadRegisters(d.type, d.place);
  }

  /** A value for an owning location: none, fresh, or a move; HL afterwards. */
  private ownValue(
    v: Value,
    to: Type & { kind: "handle" },
    at: Position,
  ): void {
    const r = this.routine!;
    if (v.kind === "none") {
      if (!to.optional) {
        fail("type-mismatch", at, "none needs an optional handle");
      }
      r.blob.u8(0x21, 0, 0);
      return;
    }
    if (v.kind === "fresh") {
      const f = v.type as Type & { kind: "handle" };
      if (f.pool !== to.pool || f.id || (f.optional && !to.optional)) {
        fail(
          "type-mismatch",
          at,
          `a ${typeName(to)} is required, not ${typeName(v.type)}`,
        );
      }
      return;
    }
    if (v.kind === "reg" && v.type.kind === "handle" && !v.type.id) {
      fail(
        "needs-move",
        at,
        "an owning handle is moved, not copied: write move",
      );
    }
    fail("type-mismatch", at, `a ${typeName(to)} is required`);
  }

  /** HL = the value: free the old value at d, store, and set the owner link. */
  private storeOwning(d: Designator): void {
    const r = this.routine!;
    r.blob.u8(0xe5); // PUSH HL
    this.push(2);
    this.emitAddress(d);
    r.blob.u8(0xeb, 0xe1); // EX DE,HL; POP HL
    this.pop(2);
    if (d.slotTemp !== undefined) {
      r.blob.u8(
        0xdd,
        0x4e,
        d.slotTemp & 0xff,
        0xdd,
        0x46,
        (d.slotTemp + 1) & 0xff,
      ); // LD BC,(IX+t)
    } else r.blob.u8(0x01, 0, 0); // LD BC,0
    this.callHelper(
      d.slotKind === "identifier" ? Helper.OWN_SETC : Helper.OWN_SET,
    );
  }

  /** Store the 4-byte value in DEHL at d. */
  private store4(d: Designator): void {
    const r = this.routine!;
    if (d.place.kind === "static" || d.place.kind === "frame") {
      this.storeRegisters(d.type, d.place);
      return;
    }
    r.blob.u8(0xd5, 0xe5); // PUSH DE; PUSH HL
    this.push(4);
    this.emitAddress(d);
    r.blob.u8(0xd1, 0x73, 0x23, 0x72, 0x23); // POP DE; LD (HL),E; INC HL; LD (HL),D; INC HL
    r.blob.u8(0xd1, 0x73, 0x23, 0x72); // POP DE; LD (HL),E; INC HL; LD (HL),D
    this.pop(4);
  }

  // ---- freeing (7.12) and the flow check (7.17) --------------------------------------

  /** Free the owning locals of these scopes; registers are destroyed. */
  private emitFrees(scopes: Scope[]): void {
    const r = this.routine!;
    for (const scope of scopes) {
      for (const sym of scope.symbols.values()) {
        if (sym.kind !== "var" || sym.storage.kind !== "frame" || sym.lease) {
          continue;
        }
        // A slot-holder (var h as P?) is an alias to the caller's location.
        if (sym.parameter?.var) continue;
        const t = sym.type;
        if (t.kind === "handle" && !t.id) {
          this.loadRegisters(U16, sym.storage);
          r.blob.u8(0x7c, 0xb5); // LD A,H; OR L
          r.blob.u8(0xc4); // CALL NZ,POOL_DEL
          r.blob.abs16(Helper.POOL_DEL);
          r.helperStack = Math.max(
            r.helperStack,
            HELPER_STACK[Helper.POOL_DEL],
          );
          r.blob.u8(0x21, 0, 0); // LD HL,0
          this.storeRegisters(U16, sym.storage);
        } else if (
          (t.kind === "record" || t.kind === "array") && isOwningType(t) &&
          !sym.parameter
        ) {
          this.emitAddress({ place: sym.storage, type: t, readonly: false });
          r.blob.u8(0x11); // LD DE,descriptor
          r.blob.abs16(this.descriptorOf(t));
          this.callHelper(Helper.OBJ_FREE);
        }
      }
    }
  }

  private trackedOwners(): (Symbol & { kind: "var" })[] {
    const out: (Symbol & { kind: "var" })[] = [];
    const depth = this.scopes.routineDepth();
    if (depth < 0) return out;
    for (const scope of this.scopes.scopesFrom(depth)) {
      for (const sym of scope.symbols.values()) {
        if (sym.kind === "var" && sym.flow !== undefined) out.push(sym);
      }
    }
    return out;
  }

  private snapshotFlow(): Map<Symbol, Flow> {
    return new Map(this.trackedOwners().map((s) => [s, s.flow!]));
  }

  private restoreFlow(snap: Map<Symbol, Flow>): void {
    for (const [sym, flow] of snap) {
      (sym as Symbol & { kind: "var" }).flow = flow;
    }
  }

  /** The meet of several end states (11.4.1). */
  private meetFlow(snaps: Map<Symbol, Flow>[]): void {
    if (snaps.length === 0) return;
    for (const sym of this.trackedOwners()) {
      const states = snaps.map((m) => m.get(sym)).filter((x) =>
        x !== undefined
      ) as Flow[];
      if (states.length === 0) continue;
      sym.flow = states.every((x) => x === states[0]) ? states[0] : "maybe";
    }
  }

  /** The back-edge rule (12.5.1): non-optional owners hold values again. */
  private checkBackEdge(entry: Map<Symbol, Flow>, at: Token): void {
    for (const [sym, flow] of entry) {
      const v = sym as Symbol & { kind: "var" };
      if (
        flow === "value" && v.flow !== "value" && v.type.kind === "handle" &&
        !v.type.optional
      ) {
        fail(
          "loop-moves-owner",
          at,
          `${v.name} may have been moved when the loop repeats`,
        );
      }
    }
  }

  /** A non-optional owner that may have been moved can't be used (10.8). */
  private checkUsable(d: Designator): void {
    const sym = d.symbol;
    const at = d.at ?? this.token;
    if (
      sym && sym.flow === "maybe" && sym.type.kind === "handle" &&
      !sym.type.optional
    ) {
      fail("use-after-move", at, `${sym.name} may have been moved`);
    }
    if (sym && this.stmtMoved.has(sym) && !d.rootOnly) {
      fail(
        "statement-rule",
        at,
        `${sym.name} is moved elsewhere in this statement`,
      );
    }
  }

  private noteDirect(d: Designator): void {
    const sym = d.symbol;
    if (!sym || sym.flow === undefined) return;
    if (this.stmtMoved.has(sym)) {
      fail(
        "statement-rule",
        d.at ?? this.token,
        `${sym.name} is moved elsewhere in this statement`,
      );
    }
    this.stmtDirect.add(sym);
  }

  private noteMove(d: Designator, at: Token = d.at ?? this.token): void {
    const sym = d.symbol;
    if (!sym || sym.flow === undefined) return;
    if (sym.counting) {
      fail("not-writable", at, `${sym.name} is leased in this arm`);
    }
    if (this.stmtDirect.has(sym)) {
      fail(
        "statement-rule",
        at,
        `${sym.name} is used elsewhere in this statement`,
      );
    }
    this.stmtMoved.add(sym);
  }

  /** Evaluate a boolean condition and jump to `ifFalse` when it is false. */

  /** Jump to `body` if the subject at IX+offset lies in low..high. */
  private emitLabelTest(
    offset: number,
    name: ScalarName,
    low: number,
    high: number,
    body: number,
  ): void {
    const r = this.routine!;
    const s = SCALARS[name];
    const flip = s.signed ? (s.size === 1 ? 0x80 : 0x8000) : 0;
    const mask = s.size === 1 ? 0xff : 0xffff;
    // Signed values are compared unsigned after flipping the sign bit.
    const lo = ((low & mask) ^ flip) & mask;
    const hi = ((high & mask) ^ flip) & mask;
    if (s.size === 1) {
      r.blob.u8(0xdd, 0x7e, offset & 0xff); // LD A,(IX+o)
      if (flip) r.blob.u8(0xee, 0x80); // XOR $80
      if (lo === hi) {
        r.blob.u8(0xfe, lo); // CP n
        r.blob.jpIf(JP_Z, body);
        return;
      }
      const skip = r.blob.newLabel();
      r.blob.u8(0xfe, lo); // CP lo: carry if A < lo
      r.blob.jpIf(JP_C, skip);
      if (hi < 0xff) {
        r.blob.u8(0xfe, hi + 1); // CP hi+1: carry if A <= hi
        r.blob.jpIf(JP_C, body);
      } else r.blob.jp(body);
      r.blob.defineLabel(skip);
      return;
    }
    r.blob.u8(0xdd, 0x6e, offset & 0xff, 0xdd, 0x66, (offset + 1) & 0xff); // LD HL,(IX+o)
    if (flip) r.blob.u8(0x7c, 0xee, 0x80, 0x67); // LD A,H; XOR $80; LD H,A
    r.blob.u8(0x11); // LD DE,lo
    r.blob.u16(lo);
    r.blob.u8(0xb7, 0xed, 0x52); // OR A; SBC HL,DE: HL = v - lo
    if (lo === hi) {
      r.blob.u8(0x7c, 0xb5); // LD A,H; OR L
      r.blob.jpIf(JP_Z, body);
      return;
    }
    const skip = r.blob.newLabel();
    r.blob.jpIf(JP_C, skip); // v < lo
    r.blob.u8(0x11); // LD DE,hi-lo+1
    r.blob.u16(hi - lo + 1);
    r.blob.u8(0xb7, 0xed, 0x52); // OR A; SBC HL,DE: carry if v-lo <= hi-lo
    r.blob.jpIf(JP_C, body);
    r.blob.defineLabel(skip);
  }

  /** Evaluate a boolean condition and jump to `ifFalse` when it is false. */
  private condition(ifFalse: number): void {
    const at = this.token;
    const v = this.expression(BOOLEAN);
    const r = this.routine!;
    if (v.kind === "const") {
      if (typeof v.value !== "boolean") {
        fail("type-mismatch", at, "a boolean condition is required");
      }
      if (v.value === false) r.blob.jp(ifFalse);
      return;
    }
    this.toRegisters(v, BOOLEAN, at);
    r.blob.u8(0xb7); // OR A
    r.blob.jpIf(JP_Z, ifFalse);
  }

  private whileStatement(): void {
    this.expectKeyword("while");
    const r = this.routine!;
    const top = r.blob.newLabel();
    const exit = r.blob.newLabel();
    r.blob.defineLabel(top);
    this.condition(exit);
    this.expectNewline();
    const entryFlow = this.snapshotFlow();
    r.loops.push({ exit, next: top, depth: this.scopes.depth, entryFlow });
    this.block(["end"]);
    r.loops.pop();
    const endAt = this.expectKeyword("end");
    this.checkBackEdge(entryFlow, endAt);
    this.expectNewline();
    r.blob.jp(top);
    r.blob.defineLabel(exit);
    this.meetFlow([entryFlow, this.snapshotFlow()]);
    r.fallsThrough = true;
  }

  private forStatement(): void {
    const forAt = this.expectKeyword("for");
    const r = this.routine!;
    const name = this.expectName();
    const sym = this.scopes.lookup(name.text);
    if (
      sym?.kind !== "var" || sym.storage.kind !== "frame" || sym.parameter ||
      !isInteger(sym.type)
    ) {
      fail("loop-counter", name, "the counter must be an integer local");
    }
    const counter = sym as Symbol & { kind: "var" };
    if (counter.counting) {
      fail("not-writable", name, `${name.text} is already a loop counter`);
    }
    const ctype = counter.type as Type & { kind: "scalar" };
    if (SCALARS[ctype.name].size > 2) {
      throw new NotImplemented("32-bit loop counters");
    }
    this.expectPunct("=");
    const startAt = this.token;
    const start = this.expression(ctype);
    this.toRegisters(start, ctype, startAt);
    this.storeRegisters(ctype, counter.storage);
    let inclusive: boolean;
    if (this.acceptKeyword("to")) inclusive = true;
    else if (this.acceptKeyword("until")) inclusive = false;
    else fail("syntax", this.token, "expected to or until");
    // The bound is evaluated once, into a hidden local of the counter's type
    // widened with the bound's.
    const boundAt = this.token;
    const bound = this.expression(ctype);
    let boundType: ScalarName = ctype.name;
    if (bound.kind === "const" && !bound.type) {
      // An exact bound: keep it mathematical; a value beyond the counter's
      // type means the loop can run to the type's end or not at all.
      if (!fits(bound.value as number, ctype.name)) {
        boundType = ctype.name; // handled by the comparison in the wider sense below
      }
    } else if (bound.kind === "reg" || (bound.kind === "const" && bound.type)) {
      const bt = (bound as { type: Type }).type;
      if (bt.kind !== "scalar") {
        fail("type-mismatch", boundAt, "an integer bound is required");
      }
      const common = commonType(ctype.name, bt.name);
      if (!common || common === "f32") {
        fail(
          "mixed-operands",
          boundAt,
          `${ctype.name} and ${bt.name} don't mix`,
        );
      }
      boundType = common;
    }
    if (SCALARS[boundType].size > 2) {
      throw new NotImplemented("32-bit loop bounds");
    }
    const bt = scalar(boundType);
    this.toRegisters(bound, bt, boundAt);
    const boundOffset = this.allocLocal(2);
    if (SCALARS[boundType].size === 1) {
      this.widen(boundType, SCALARS[boundType].signed ? "i16" : "u16");
    }
    this.storeRegisters(U16, { kind: "frame", offset: boundOffset });
    let step = 1;
    if (this.acceptKeyword("step")) {
      let negative = false;
      if (this.acceptPunct("-")) negative = true;
      else this.acceptPunct("+");
      const st = this.token;
      let mag: number;
      if (st.kind === "number") {
        this.advance();
        mag = st.value;
      } else if (st.kind === "name") {
        const c = this.scopes.lookup(st.text);
        if (c?.kind !== "const" || typeof c.value !== "number") {
          fail("loop-step", st, "the step must be a constant");
        }
        this.advance();
        mag = (c as Symbol & { kind: "const" }).value as number;
      } else fail("loop-step", st, "the step must be a constant");
      if (mag! === 0 || mag! > SCALARS[ctype.name].max) {
        fail("loop-step", st, "the step must be nonzero and fit the counter");
      }
      step = negative ? -mag! : mag!;
    }
    this.expectNewline();
    const signed = SCALARS[ctype.name].signed;
    const test = r.blob.newLabel();
    const next = r.blob.newLabel();
    const exit = r.blob.newLabel();
    const body = r.blob.newLabel();
    // Test: counter <= bound (or <, >=, >) in 16-bit, counter widened.
    r.blob.defineLabel(test);
    this.loadCounterWide(counter, signed);
    r.blob.u8(
      0xdd,
      0x5e,
      boundOffset & 0xff,
      0xdd,
      0x56,
      (boundOffset + 1) & 0xff,
    ); // LD E,(IX+b); LD D,(IX+b+1)
    // continue while: step>0: inclusive ? HL<=DE : HL<DE; step<0: inclusive ? HL>=DE : HL>DE
    this.compare16ToFlags(signed);
    // after compare16ToFlags: carry set iff HL < DE; zero set iff equal (for unsigned);
    // for signed, we arrange the same meaning in the carry and zero flags.
    const less = JP_C, notLess = JP_NC;
    if (step > 0) {
      if (inclusive) {
        // continue if HL <= DE: i.e. not (DE < HL). We tested HL<DE: continue if carry or zero.
        r.blob.jpIf(less, body);
        r.blob.jpIf(JP_Z, body);
        r.blob.jp(exit);
      } else {
        r.blob.jpIf(notLess, exit);
      }
    } else {
      if (inclusive) {
        r.blob.jpIf(less, exit); // continue if HL >= DE
      } else {
        r.blob.jpIf(less, exit);
        r.blob.jpIf(JP_Z, exit);
      }
    }
    r.blob.defineLabel(body);
    counter.counting = true;
    const entryFlow = this.snapshotFlow();
    r.loops.push({ exit, next, counter, depth: this.scopes.depth, entryFlow });
    this.block(["end"]);
    r.loops.pop();
    counter.counting = false;
    const endAt = this.expectKeyword("end");
    this.checkBackEdge(entryFlow, endAt);
    this.meetFlow([entryFlow, this.snapshotFlow()]);
    this.expectNewline();
    // Next: counter + step, checked against the type before storing (loop-range).
    r.blob.defineLabel(next);
    this.loadCounterWide(counter, signed);
    const stepField = step < 0 ? (step + 0x10000) & 0xffff : step;
    r.blob.u8(0x11); // LD DE,step
    r.blob.u16(stepField);
    r.blob.u8(0x19); // ADD HL,DE
    this.checkFitsCounter(ctype.name, signed);
    this.storeCounterFromWide(counter);
    r.blob.jp(test);
    r.blob.defineLabel(exit);
    r.fallsThrough = true;
    void forAt;
  }

  /** HL = counter, sign- or zero-extended to 16 bits. */
  private loadCounterWide(
    counter: Symbol & { kind: "var" },
    signed: boolean,
  ): void {
    const r = this.routine!;
    const off = (counter.storage as { offset: number }).offset;
    if (sizeOf(counter.type) === 2) {
      this.loadRegisters(counter.type, counter.storage);
      return;
    }
    r.blob.u8(0xdd, 0x6e, off & 0xff); // LD L,(IX+d)
    if (signed) {
      r.blob.u8(0x7d, 0x07, 0x9f, 0x67); // LD A,L; RLCA; SBC A,A; LD H,A
    } else r.blob.u8(0x26, 0); // LD H,0
  }

  private storeCounterFromWide(counter: Symbol & { kind: "var" }): void {
    const r = this.routine!;
    const off = (counter.storage as { offset: number }).offset;
    if (sizeOf(counter.type) === 2) {
      this.storeRegisters(counter.type, counter.storage);
      return;
    }
    r.blob.u8(0xdd, 0x75, off & 0xff); // LD (IX+d),L
  }

  /** After ADD HL,DE in a counted loop: trap loop-range unless HL fits the type. */
  private checkFitsCounter(name: ScalarName, signed: boolean): void {
    const r = this.routine!;
    const size = SCALARS[name].size;
    if (size === 2) {
      // 16-bit: the add carried (unsigned) or overflowed (signed).
      if (!signed) {
        r.blob.callBlobIf(JP_C, Helper.TRAP_LOOP_RANGE);
      } else {
        // ADD HL,DE doesn't set P/V. Recompute with ADC-style: we test via
        // sign of operands: overflow if DE and old HL have the same sign and
        // the result differs. Simplest: redo as OR A; SBC back and ADC.
        r.blob.u8(0xb7, 0xed, 0x52); // OR A; SBC HL,DE  (HL = old)
        r.blob.u8(0xed, 0x5a); // ADC HL,DE sets P/V on overflow
        r.blob.callBlobIf(0xea, Helper.TRAP_LOOP_RANGE); // CALL PE
      }
      return;
    }
    // 8-bit counter: HL must be in the type's range.
    if (!signed) {
      r.blob.u8(0x7c, 0xb7); // LD A,H; OR A
      r.blob.callBlobIf(JP_NZ, Helper.TRAP_LOOP_RANGE);
    } else {
      // Fits i8 iff H is the sign extension of L: H = 0 and L < 128, or H = $FF and L >= 128.
      r.blob.u8(0x7d, 0x07, 0x9f, 0xac); // LD A,L; RLCA; SBC A,A; XOR H
      r.blob.callBlobIf(JP_NZ, Helper.TRAP_LOOP_RANGE);
    }
  }

  /** Compare HL with DE, leaving carry = HL < DE and zero = equal. */
  private compare16ToFlags(signed: boolean): void {
    const r = this.routine!;
    if (!signed) {
      r.blob.u8(0xb7, 0xed, 0x52); // OR A; SBC HL,DE
      return;
    }
    // Signed: flip the sign bits of both and compare unsigned.
    r.blob.u8(0x7c, 0xee, 0x80, 0x67); // LD A,H; XOR $80; LD H,A
    r.blob.u8(0x7a, 0xee, 0x80, 0x57); // LD A,D; XOR $80; LD D,A
    r.blob.u8(0xb7, 0xed, 0x52); // OR A; SBC HL,DE
  }

  // ---- assignment ---------------------------------------------------------------

  private assign(d: Designator, at: Token): void {
    const r = this.routine!;
    if (d.setLength !== undefined) {
      // s.length = e, through the runtime, which checks and zeroes (D25).
      const v = this.expression(U8);
      this.toRegisters(v, U8, at);
      const o = d.setLength;
      r.blob.u8(0x5f); // LD E,A
      r.blob.u8(0xdd, 0x56, (o + 2) & 0xff); // LD D,(IX+o+2): the capacity's low byte
      r.blob.u8(0xdd, 0x6e, o & 0xff, 0xdd, 0x66, (o + 1) & 0xff); // LD HL,(IX+o)
      this.callHelper(Helper.STR_SETL);
      return;
    }
    if (isAggregate(d.type)) {
      if (d.type.kind === "openString" || d.type.kind === "openArray") {
        fail("not-writable", at, "an open view can't be assigned as a whole");
      }
      if (isOwningType(d.type)) {
        fail(
          "owning-copy",
          at,
          `${typeName(d.type)} owns handles and can't be copied`,
        );
      }
      // Destination address first, then the source, then copy (10.4).
      this.emitAddress(d);
      r.blob.u8(0xe5); // PUSH HL
      this.push(2);
      const srcAt = this.token;
      const v = this.expression(d.type);
      if (v.kind === "literal" && d.type.kind === "string") {
        if (v.bytes.length > d.type.capacity) {
          fail(
            "out-of-range",
            srcAt,
            "the literal exceeds the string's capacity",
          );
        }
        const bytes = new Array(d.type.size).fill(0);
        bytes[0] = v.bytes.length;
        v.bytes.forEach((b, i) => bytes[1 + i] = b);
        const label = r.blob.newLabel();
        r.literals.push({ label, bytes });
        r.blob.u8(0x21); // LD HL,literal
        r.blob.labelOperand(label);
      } else if (v.kind !== "address" || !sameType(v.type, d.type)) {
        fail("type-mismatch", srcAt, `a ${typeName(d.type)} is required`);
      }
      r.blob.u8(0xd1); // POP DE
      this.pop(2);
      r.blob.u8(0x01); // LD BC,size
      r.blob.u16(sizeOf(d.type));
      r.blob.u8(0xed, 0xb0); // LDIR
      return;
    }
    if (d.type.kind === "handle") {
      if (d.symbol && !d.rootOnly) this.noteDirect(d);
      else if (d.symbol && d.rootOnly) this.noteMove(d);
      if (d.type.id) {
        const v = this.expression(d.type);
        this.toRegisters(v, d.type, at);
        this.store4(d);
        return;
      }
      const v = this.expression(d.type);
      this.ownValue(v, d.type, at);
      this.storeOwning(d);
      if (d.rootOnly && d.symbol?.flow !== undefined) {
        d.symbol.flow = v.kind === "none" ? "none" : "value";
      }
      return;
    }
    if (d.symbol && !d.rootOnly && d.symbol.flow !== undefined) {
      this.noteDirect(d);
    }
    if (d.place.kind === "computed") {
      this.emitAddress(d);
      r.blob.u8(0xe5); // PUSH HL
      this.push(2);
      const v = this.expression(d.type);
      this.toRegisters(v, d.type, at);
      if (sizeOf(d.type) === 4) {
        r.blob.u8(0xc1); // POP BC: the address
        r.blob.u8(0x7d, 0x02, 0x03, 0x7c, 0x02, 0x03); // LD A,L; LD (BC),A; INC BC; LD A,H; LD (BC),A; INC BC
        r.blob.u8(0x7b, 0x02, 0x03, 0x7a, 0x02); // LD A,E; LD (BC),A; INC BC; LD A,D; LD (BC),A
        this.pop(2);
        return;
      }
      r.blob.u8(0xd1); // POP DE
      this.pop(2);
      this.storeRegistersIndirect(d.type);
      return;
    }
    const v = this.expression(d.type);
    this.toRegisters(v, d.type, at);
    this.storeRegisters(d.type, d.place);
  }

  // ---- designators and places (9.4, 9.5) ------------------------------------------

  /** Parse NAME { suffix } for a variable, returning its place. */
  private designator(): Designator {
    const name = this.expectName();
    const sym = this.scopes.lookup(name.text);
    if (!sym) fail("undeclared-name", name, `${name.text} is not declared`);
    let d: Designator;
    if (sym!.kind === "var") {
      const v = sym as Symbol & { kind: "var" };
      this.lastAddressRoot = v;
      if (v.storage.kind === "static") {
        d = {
          place: { kind: "static", ordinal: v.storage.ordinal, offset: 0 },
          type: v.type,
          readonly: v.readonly,
          symbol: v,
        };
      } else if (
        v.type.kind === "handle" && v.parameter?.var && !v.type.id
      ) {
        // A slot-holder: the frame word holds the location's address.
        d = {
          place: { kind: "alias", offset: v.storage.offset, add: 0 },
          type: v.type,
          readonly: false,
          symbol: v,
          slotTemp: v.ownerOffset,
          slotKind: "owner",
        };
      } else if (isAggregate(v.type) && (v.parameter || v.lease)) {
        d = {
          place: { kind: "alias", offset: v.storage.offset, add: 0 },
          type: v.type,
          readonly: v.readonly,
          symbol: v,
        };
        if (v.lease) {
          d.slotTemp = v.slotOffset;
          d.slotKind = "lease";
        } else if (v.ownerOffset !== undefined) {
          d.slotTemp = v.ownerOffset;
          d.slotKind = "owner";
        }
      } else {
        d = {
          place: { kind: "frame", offset: v.storage.offset },
          type: v.type,
          readonly: v.readonly,
          symbol: v,
        };
      }
    } else if (sym!.kind === "aggregateConst") {
      const c = sym as Symbol & { kind: "aggregateConst" };
      this.lastAddressRoot = undefined;
      d = {
        place: { kind: "static", ordinal: c.ordinal, offset: 0 },
        type: c.type,
        readonly: true,
      };
    } else {
      fail("wrong-class", name, `${name.text} is not a variable`);
    }
    const root = this.lastAddressRoot;
    const start = this.pos;
    d!.at = name;
    const result = this.suffixes(d!);
    this.lastAddressRoot = root;
    result.rootOnly = this.pos === start;
    result.at = name;
    return result;
  }

  private suffixes(d: Designator): Designator {
    while (true) {
      if (this.isPunct(".") && d.type.kind === "handle") {
        const h = d.type;
        if (h.optional) {
          fail(
            "optional-handle",
            this.token,
            "an optional handle is tested with select before use",
          );
        }
        if (!h.pool.record) {
          fail(
            "pool-incomplete",
            this.token,
            `pool ${h.pool.name} is only forward-declared`,
          );
        }
        this.checkUsable(d);
        const base = d;
        const temp = this.allocLocal(2);
        const compute = () => {
          this.loadValue(base);
          if (h.id) this.callHelper(Helper.ID_CHK);
          this.storeRegisters(U16, { kind: "frame", offset: temp });
        };
        d = {
          place: { kind: "computed" },
          type: h.pool.record!,
          readonly: false,
          symbol: d.symbol,
          compute,
          slotTemp: temp,
          slotKind: h.id ? "identifier" : "owner",
        };
        continue;
      }
      if (this.isPunct(".")) {
        const dot = this.advance();
        const field = this.expectName();
        if (d.type.kind === "string" || d.type.kind === "openString") {
          if (field.text === "length") {
            if (d.type.kind === "openString" && d.place.kind === "alias") {
              const offset = d.place.offset;
              const writable = !d.readonly;
              d = this.offsetPlace(d, 0, U8, !writable);
              if (writable) d.setLength = offset;
            } else {
              d = this.offsetPlace(d, 0, U8, true); // a concrete string's length is read-only
            }
            continue;
          }
          if (field.text === "capacity" && d.type.kind === "openString") {
            d = this.openViewWord(d);
            continue;
          }
          fail("no-such-field", field, `strings have no field ${field.text}`);
        }
        if (d.type.kind === "openArray" && field.text === "length") {
          d = this.openViewWord(d);
          continue;
        }
        if (d.type.kind !== "record") {
          fail("no-such-field", dot, `${typeName(d.type)} has no fields`);
        }
        const f = (d.type as RecordType).fields.find((x) =>
          x.name === field.text
        );
        if (!f) {
          fail(
            "no-such-field",
            field,
            `no field ${field.text} in ${typeName(d.type)}`,
          );
        }
        d = this.offsetPlace(d, f!.offset, f!.type, d.readonly);
        continue;
      }
      if (this.isPunct("[")) {
        const bracket = this.advance();
        if (d.type.kind === "string" || d.type.kind === "openString") {
          d = this.indexString(d, bracket);
        } else if (d.type.kind === "array" || d.type.kind === "openArray") {
          d = this.indexArray(d, bracket);
        } else {fail(
            "not-indexable",
            bracket,
            `${typeName(d.type)} can't be indexed`,
          );}
        this.expectPunct("]");
        continue;
      }
      return d;
    }
  }

  private offsetPlace(
    d: Designator,
    add: number,
    type: Type,
    readonly: boolean,
  ): Designator {
    const p = d.place;
    if (p.kind === "static") {
      return {
        ...d,
        place: { kind: "static", ordinal: p.ordinal, offset: p.offset + add },
        type,
        readonly,
      };
    }
    if (p.kind === "frame") {
      return {
        ...d,
        place: { kind: "frame", offset: p.offset + add },
        type,
        readonly,
      };
    }
    if (p.kind === "alias") {
      return {
        ...d,
        place: { kind: "alias", offset: p.offset, add: p.add + add },
        type,
        readonly,
      };
    }
    const compute = d.compute!;
    return {
      ...d,
      type,
      readonly,
      place: { kind: "computed" },
      compute: () => {
        compute();
        if (add) this.addConst(add);
      },
    };
  }

  /** The hidden word of an open view (capacity or length), at IX+offset+2. */
  private openViewWord(d: Designator): Designator {
    const p = d.place;
    if (p.kind !== "alias") {
      fail("internal", this.token, "an open view is always a parameter");
    }
    return {
      place: { kind: "frame", offset: (p as { offset: number }).offset + 2 },
      type: U16,
      readonly: true,
    };
  }

  private indexArray(d: Designator, at: Token): Designator {
    const arr = d.type as Type & { kind: "array" | "openArray" };
    const element = arr.element;
    const stride = sizeOf(element);
    const idxAt = this.token;
    const idx = this.expression(U16);
    this.checkIndexType(idx, idxAt);
    if (idx.kind === "const" && arr.kind === "array") {
      const i = this.indexValue(idx, idxAt);
      if (i >= arr.length) {
        fail(
          "bounds",
          idxAt,
          `index ${i} is out of range for ${typeName(arr)}`,
        );
      }
      return this.offsetPlace(d, i * stride, element, d.readonly);
    }
    const base = d;
    const r = this.routine!;
    const compute = () => {
      // Index into HL (u16), bounds check, scale, add base.
      if (idx.kind === "const") {
        r.blob.u8(0x21);
        r.blob.u16(this.indexValue(idx, idxAt));
      } else {
        this.toRegisters(idx, U16, idxAt);
      }
      this.boundsCheck(base, arr);
      this.scaleHL(stride);
      r.blob.u8(0xe5); // PUSH HL
      this.push(2);
      this.emitAddress(base);
      r.blob.u8(0xd1); // POP DE
      this.pop(2);
      r.blob.u8(0x19); // ADD HL,DE
    };
    return {
      place: { kind: "computed" },
      type: element,
      readonly: d.readonly,
      symbol: d.symbol,
      compute,
    };
  }

  private checkIndexType(idx: Value, at: Token): void {
    if (idx.kind === "const") {
      this.indexValue(idx, at);
      return;
    }
    if (
      idx.kind !== "reg" || idx.type.kind !== "scalar" ||
      (idx.type.name !== "u8" && idx.type.name !== "u16")
    ) {
      fail("index-type", at, "an index must be u8 or u16; convert it");
    }
  }

  private indexValue(idx: Value & { kind: "const" }, at: Token): number {
    if (typeof idx.value !== "number" || !Number.isInteger(idx.value)) {
      fail("index-type", at, "an integer index is required");
    }
    if (
      idx.type &&
      !(idx.type.kind === "scalar" &&
        (idx.type.name === "u8" || idx.type.name === "u16"))
    ) {
      fail("index-type", at, "an index must be u8 or u16; convert it");
    }
    if (idx.value < 0 || idx.value > 0xffff) {
      fail("index-type", at, "an index must be 0 to 65,535");
    }
    return idx.value;
  }

  /** HL = index. Trap bounds unless HL < length. */
  private boundsCheck(
    base: Designator,
    arr: Type & { kind: "array" | "openArray" },
  ): void {
    const r = this.routine!;
    if (arr.kind === "array") {
      r.blob.u8(0x11); // LD DE,length
      r.blob.u16(arr.length);
    } else {
      const p = base.place as { kind: "alias"; offset: number };
      r.blob.u8(
        0xdd,
        0x5e,
        (p.offset + 2) & 0xff,
        0xdd,
        0x56,
        (p.offset + 3) & 0xff,
      ); // LD DE,(IX+off+2)
    }
    r.blob.u8(0xb7, 0xed, 0x52); // OR A; SBC HL,DE
    r.blob.callBlobIf(JP_NC, Helper.TRAP_BOUNDS);
    r.blob.u8(0x19); // ADD HL,DE
  }

  private indexString(d: Designator, at: Token): Designator {
    const idxAt = this.token;
    const idx = this.expression(U16);
    this.checkIndexType(idx, idxAt);
    const base = d;
    const r = this.routine!;
    const compute = () => {
      if (idx.kind === "const") {
        r.blob.u8(0x21);
        r.blob.u16(this.indexValue(idx, idxAt));
      } else this.toRegisters(idx, U16, idxAt);
      r.blob.u8(0xe5); // PUSH HL
      this.push(2);
      this.emitAddress(base); // HL = the string (length byte)
      r.blob.u8(0xd1); // POP DE: the index
      this.pop(2);
      // Check index < length: length in (HL).
      r.blob.u8(0x7e, 0xbb); // LD A,(HL); CP E  -> carry if length < index... need index < length
      // index < length  <=>  length > index  <=> not (length <= index). CP E computes A-E: carry if A<E.
      // We need trap when index >= length, i.e. when NOT (index < length) i.e. A <= E: carry clear and ... A==E too.
      r.blob.u8(0x7b, 0xbe); // LD A,E; CP (HL): carry iff index < length
      r.blob.callBlobIf(JP_NC, Helper.TRAP_BOUNDS);
      r.blob.u8(0x7a, 0xb7); // LD A,D; OR A: a 16-bit index with a high byte is out of range
      r.blob.callBlobIf(JP_NZ, Helper.TRAP_BOUNDS);
      r.blob.u8(0x23, 0x19); // INC HL; ADD HL,DE
    };
    void at;
    return {
      place: { kind: "computed" },
      type: U8,
      readonly: d.readonly,
      symbol: d.symbol,
      compute,
    };
  }

  /** Multiply HL by a constant stride. */
  private scaleHL(stride: number): void {
    const r = this.routine!;
    if (stride === 1) return;
    if ((stride & (stride - 1)) === 0) {
      for (let s = stride; s > 1; s >>= 1) r.blob.u8(0x29); // ADD HL,HL
      return;
    }
    // General: shift-and-add from a copy in DE.
    r.blob.u8(0x54, 0x5d); // LD D,H; LD E,L
    r.blob.u8(0x21, 0, 0); // LD HL,0
    let m = stride;
    let first = true;
    while (m > 0) {
      if (m & 1) {
        r.blob.u8(0x19); // ADD HL,DE
      }
      m >>= 1;
      if (m > 0) r.blob.u8(0xeb, 0x29, 0xeb); // EX DE,HL; ADD HL,HL; EX DE,HL  (DE *= 2)
      first = false;
    }
    void first;
  }

  private addConst(n: number): void {
    const r = this.routine!;
    if (n === 0) return;
    if (n <= 3) {
      for (let i = 0; i < n; i += 1) r.blob.u8(0x23); // INC HL
      return;
    }
    r.blob.u8(0x11); // LD DE,n
    r.blob.u16(n);
    r.blob.u8(0x19); // ADD HL,DE
  }

  /** Leave the designator's address in HL. */
  private emitAddress(d: Designator): void {
    const r = this.routine!;
    const p = d.place;
    switch (p.kind) {
      case "static":
        r.blob.u8(0x21); // LD HL,blob+offset
        r.blob.abs16(p.ordinal, p.offset);
        return;
      case "frame":
        r.blob.u8(0xdd, 0xe5, 0xe1); // PUSH IX; POP HL
        this.addSigned(p.offset);
        return;
      case "alias":
        r.blob.u8(
          0xdd,
          0x6e,
          p.offset & 0xff,
          0xdd,
          0x66,
          (p.offset + 1) & 0xff,
        ); // LD L,(IX+o); LD H,(IX+o+1)
        this.addConst(p.add);
        return;
      case "computed":
        d.compute!();
        return;
    }
  }

  private addSigned(n: number): void {
    const r = this.routine!;
    if (n === 0) return;
    r.blob.u8(0x11); // LD DE,n
    r.blob.u16(n & 0xffff);
    r.blob.u8(0x19); // ADD HL,DE
  }

  // ---- loads and stores -------------------------------------------------------------

  private loadRegisters(type: Type, place: Place): void {
    const r = this.routine!;
    const size = sizeOf(type);
    if (place.kind === "static") {
      if (size === 1) {
        r.blob.u8(0x3a); // LD A,(nn)
        r.blob.abs16(place.ordinal, place.offset);
      } else if (size === 2) {
        r.blob.u8(0x2a); // LD HL,(nn)
        r.blob.abs16(place.ordinal, place.offset);
      } else {
        r.blob.u8(0x2a);
        r.blob.abs16(place.ordinal, place.offset);
        r.blob.u8(0xed, 0x5b); // LD DE,(nn+2)
        r.blob.abs16(place.ordinal, place.offset + 2);
      }
      return;
    }
    if (place.kind === "frame") {
      const o = place.offset;
      if (size === 1) r.blob.u8(0xdd, 0x7e, o & 0xff); // LD A,(IX+o)
      else if (size === 2) {
        r.blob.u8(0xdd, 0x6e, o & 0xff, 0xdd, 0x66, (o + 1) & 0xff);
      } else {
        r.blob.u8(0xdd, 0x6e, o & 0xff, 0xdd, 0x66, (o + 1) & 0xff);
        r.blob.u8(0xdd, 0x5e, (o + 2) & 0xff, 0xdd, 0x56, (o + 3) & 0xff);
      }
      return;
    }
    // alias or computed: address in HL first.
    this.emitAddress({ place, type, readonly: true });
    this.loadRegistersIndirect(type);
  }

  /** HL = address; load the value for its type. */
  private loadRegistersIndirect(type: Type): void {
    const r = this.routine!;
    const size = sizeOf(type);
    if (size === 1) r.blob.u8(0x7e); // LD A,(HL)
    else if (size === 2) r.blob.u8(0x5e, 0x23, 0x56, 0xeb); // LD E,(HL); INC HL; LD D,(HL); EX DE,HL
    else {
      r.blob.u8(0x5e, 0x23, 0x56, 0x23); // LD E,(HL); INC HL; LD D,(HL); INC HL
      r.blob.u8(0xd5); // PUSH DE
      r.blob.u8(0x5e, 0x23, 0x56); // LD E,(HL); INC HL; LD D,(HL)
      r.blob.u8(0xe1); // POP HL
    }
  }

  private storeRegisters(type: Type, place: Place): void {
    const r = this.routine!;
    const size = sizeOf(type);
    if (place.kind === "static") {
      if (size === 1) {
        r.blob.u8(0x32); // LD (nn),A
        r.blob.abs16(place.ordinal, place.offset);
      } else if (size === 2) {
        r.blob.u8(0x22); // LD (nn),HL
        r.blob.abs16(place.ordinal, place.offset);
      } else {
        r.blob.u8(0x22);
        r.blob.abs16(place.ordinal, place.offset);
        r.blob.u8(0xed, 0x53); // LD (nn+2),DE
        r.blob.abs16(place.ordinal, place.offset + 2);
      }
      return;
    }
    if (place.kind === "frame") {
      const o = place.offset;
      if (size === 1) r.blob.u8(0xdd, 0x77, o & 0xff); // LD (IX+o),A
      else if (size === 2) {
        r.blob.u8(0xdd, 0x75, o & 0xff, 0xdd, 0x74, (o + 1) & 0xff);
      } else {
        r.blob.u8(0xdd, 0x75, o & 0xff, 0xdd, 0x74, (o + 1) & 0xff);
        r.blob.u8(0xdd, 0x73, (o + 2) & 0xff, 0xdd, 0x72, (o + 3) & 0xff);
      }
      return;
    }
    if (place.kind === "alias") {
      // Value in registers; address through the alias word. Save the value.
      if (size === 1) {
        r.blob.u8(
          0xdd,
          0x6e,
          place.offset & 0xff,
          0xdd,
          0x66,
          (place.offset + 1) & 0xff,
        );
        this.addConst(place.add);
        r.blob.u8(0x77); // LD (HL),A
      } else if (size === 2) {
        r.blob.u8(0xeb); // EX DE,HL: value in DE
        r.blob.u8(
          0xdd,
          0x6e,
          place.offset & 0xff,
          0xdd,
          0x66,
          (place.offset + 1) & 0xff,
        );
        this.addConst(place.add);
        r.blob.u8(0x73, 0x23, 0x72); // LD (HL),E; INC HL; LD (HL),D
      } else {
        r.blob.u8(0xd5, 0xe5); // PUSH DE; PUSH HL
        r.blob.u8(
          0xdd,
          0x6e,
          place.offset & 0xff,
          0xdd,
          0x66,
          (place.offset + 1) & 0xff,
        );
        this.addConst(place.add);
        r.blob.u8(0xd1, 0x73, 0x23, 0x72, 0x23); // POP DE; LD (HL),E; INC HL; LD (HL),D; INC HL
        r.blob.u8(0xd1, 0x73, 0x23, 0x72); // POP DE; LD (HL),E; INC HL; LD (HL),D
      }
      return;
    }
    throw new Error("storeRegisters on a computed place");
  }

  /** Value in registers, address in DE: store. */
  private storeRegistersIndirect(type: Type): void {
    const r = this.routine!;
    const size = sizeOf(type);
    if (size === 1) r.blob.u8(0x12); // LD (DE),A
    else if (size === 2) r.blob.u8(0xeb, 0x73, 0x23, 0x72); // EX DE,HL; LD (HL),E; INC HL; LD (HL),D
    else throw new NotImplemented("4-byte indirect stores");
  }

  private storeBytesToFrame(bytes: number[], offset: number): void {
    const r = this.routine!;
    for (let i = 0; i < bytes.length; i += 1) {
      r.blob.u8(0xdd, 0x36, (offset + i) & 0xff, bytes[i]); // LD (IX+o),n
    }
  }

  private zeroFrame(offset: number, size: number): void {
    const r = this.routine!;
    if (size <= 4) {
      for (let i = 0; i < size; i += 1) {
        r.blob.u8(0xdd, 0x36, (offset + i) & 0xff, 0);
      }
      return;
    }
    this.emitAddress({
      place: { kind: "frame", offset },
      type: U8,
      readonly: false,
    });
    r.blob.u8(0x36, 0x00); // LD (HL),0
    r.blob.u8(0x54, 0x5d, 0x13); // LD D,H; LD E,L; INC DE
    r.blob.u8(0x01); // LD BC,size-1
    r.blob.u16(size - 1);
    r.blob.u8(0xed, 0xb0); // LDIR
  }

  /** Source address in HL: copy an aggregate into the frame at offset. */
  private copyToFrame(type: Type, offset: number): void {
    const r = this.routine!;
    r.blob.u8(0xe5); // PUSH HL
    this.push(2);
    this.emitAddress({
      place: { kind: "frame", offset },
      type,
      readonly: false,
    });
    r.blob.u8(0xeb, 0xe1); // EX DE,HL; POP HL  (DE = dest, HL = src)
    this.pop(2);
    r.blob.u8(0x01);
    r.blob.u16(sizeOf(type));
    r.blob.u8(0xed, 0xb0); // LDIR
  }

  // ---- values into registers ------------------------------------------------------

  /** Make `v` a value of type `to` in the registers, converting implicitly. */
  private toRegisters(v: Value, to: Type, at: Position): void {
    const r = this.routine!;
    switch (v.kind) {
      case "const": {
        const c = this.coerceConst(v, to, at);
        this.loadConstant(c.value, to);
        return;
      }
      case "reg": {
        if (sameType(v.type, to)) return;
        if (v.type.kind === "handle" && to.kind === "handle") {
          if (
            v.type.pool === to.pool && v.type.id === to.id &&
            (to.optional || !v.type.optional)
          ) {
            if (!to.id) {
              fail(
                "needs-move",
                at,
                "an owning handle is moved, not copied: write move",
              );
            }
            return;
          }
          fail(
            "type-mismatch",
            at,
            `a ${typeName(to)} is required, not ${typeName(v.type)}`,
          );
        }
        if (
          v.type.kind === "scalar" && to.kind === "scalar" &&
          widens(v.type.name, to.name)
        ) {
          this.widen(v.type.name, to.name);
          return;
        }
        if (v.type.kind === "scalar" && to.kind === "scalar") {
          fail(
            "conversion-required",
            at,
            `${v.type.name} doesn't convert to ${to.name} implicitly`,
          );
        }
        fail(
          "type-mismatch",
          at,
          `a ${typeName(to)} is required, not ${typeName(v.type)}`,
        );
        return;
      }
      case "address":
        fail(
          "type-mismatch",
          at,
          `a ${typeName(to)} value is required, not an aggregate`,
        );
        return;
      case "literal":
        fail("type-mismatch", at, "a string literal is not a value here");
        return;
      case "fresh":
        if (to.kind === "handle") {
          this.ownValue(v, to, at);
          return;
        }
        fail("type-mismatch", at, `a ${typeName(to)} is required`);
        return;
      case "none":
        if (to.kind !== "handle" || !to.optional) {
          fail("type-mismatch", at, "none needs an optional handle context");
        }
        r.blob.u8(0x21, 0, 0); // LD HL,0
        if (to.id) r.blob.u8(0x11, 0, 0); // LD DE,0
        return;
    }
    void r;
  }

  private loadConstant(value: number | boolean, type: Type): void {
    const r = this.routine!;
    if (type.kind === "file") {
      r.blob.u8(0x21); // LD HL,n
      r.blob.u16(value as number);
      r.blob.u8(0x11, 0, 0); // LD DE,0
      return;
    }
    const name = (type as { name: ScalarName }).name;
    const bytes = this.encodeScalar(value, name);
    if (bytes.length === 1) r.blob.u8(0x3e, bytes[0]); // LD A,n
    else if (bytes.length === 2) r.blob.u8(0x21, bytes[0], bytes[1]); // LD HL,nn
    else {
      r.blob.u8(0x21, bytes[0], bytes[1]);
      r.blob.u8(0x11, bytes[2], bytes[3]);
    }
  }

  /** Widen the value in registers from one scalar type to another. */
  private widen(from: ScalarName, to: ScalarName): void {
    const r = this.routine!;
    const fs = SCALARS[from].size, ts = SCALARS[to].size;
    if (to === "f32") {
      // Exact for 8- and 16-bit types: through the 32-bit value.
      const signed = SCALARS[from].signed;
      this.widen(from, signed ? "i32" : "u32");
      this.callHelper(signed ? Helper.I2F : Helper.U2F);
      return;
    }
    if (fs === 1 && ts >= 2) {
      if (SCALARS[from].signed) r.blob.u8(0x6f, 0x07, 0x9f, 0x67); // LD L,A; RLCA; SBC A,A; LD H,A
      else r.blob.u8(0x6f, 0x26, 0x00); // LD L,A; LD H,0
    }
    if (ts === 4) {
      if (SCALARS[from].signed) r.blob.u8(0x7c, 0x07, 0x9f, 0x57, 0x5f); // LD A,H; RLCA; SBC A,A; LD D,A; LD E,A
      else r.blob.u8(0x11, 0, 0); // LD DE,0
    }
  }

  private discard(v: Value): void {
    if (v.kind === "fresh" && v.type.kind === "handle") {
      const r = this.routine!;
      r.blob.u8(0x7c, 0xb5); // LD A,H; OR L
      r.blob.u8(0xc4); // CALL NZ,POOL_DEL
      r.blob.abs16(Helper.POOL_DEL);
      r.helperStack = Math.max(r.helperStack, HELPER_STACK[Helper.POOL_DEL]);
    }
  }

  // ---- calls ----------------------------------------------------------------------

  private call(callee: Symbol & { kind: "routine" }, at: Token): Value {
    const r = this.routine!;
    const sig = callee.signature;
    this.expectPunct("(");
    let pushedHere = 0;
    sig.parameters.forEach((p, i) => {
      if (i > 0) this.expectPunct(",");
      if (this.isPunct(")")) {
        fail(
          "arity",
          this.token,
          `${callee.name} takes ${sig.parameters.length} arguments`,
        );
      }
      pushedHere += this.argument(p, callee);
    });
    if (!this.isPunct(")")) {
      fail(
        "arity",
        this.token,
        `${callee.name} takes ${sig.parameters.length} arguments`,
      );
    }
    this.advance();
    this.noteCall(callee, at);
    r.blob.callBlob(callee.ordinal);
    this.pop(pushedHere);
    if (sig.fails) {
      // The consumer follows the call directly (chapter 14): decide now.
      if (this.isKeyword("else") && this.isKeyword("fail", this.peek())) {
        if (!r.symbol.signature.fails) {
          fail("not-failable", at, "else fail needs a routine declared fails");
        }
        r.blob.jpIf(JP_C, r.exitLabel); // carry set, A = the code
        this.pendingFailure = { kind: "fail" };
      } else if (this.isKeyword("handle")) {
        const failLabel = r.blob.newLabel();
        r.blob.jpIf(JP_C, failLabel);
        this.pendingFailure = { kind: "handle", failLabel };
      } else {
        fail(
          "failure-unconsumed",
          at,
          `${callee.name} fails; add else fail or handle`,
        );
      }
    }
    this.lastAddressRoot = undefined;
    if (!sig.result) return { kind: "const", value: 0 }; // a result-free call; the statement discards it
    if (isAggregate(sig.result)) {
      return { kind: "address", type: sig.result, readonly: !sig.varResult };
    }
    if (sig.result.kind === "handle" && !sig.result.id) {
      return { kind: "fresh", type: sig.result };
    }
    return { kind: "reg", type: sig.result };
  }

  /** Evaluate and push one argument; returns the bytes pushed. */
  private argument(p: Parameter, callee: Symbol & { kind: "routine" }): number {
    const r = this.routine!;
    const at = this.token;
    const t = p.type;
    if (t.kind === "openString" || t.kind === "openArray") {
      // A view: capacity or length word, then the address.
      if (this.token.kind === "string") {
        if (p.var || t.kind !== "openString") {
          fail(
            "not-writable",
            at,
            "a literal can't be passed to a var parameter",
          );
        }
        const lit = this.advance() as Token & { kind: "string" };
        const bytes = this.literalString(lit.bytes);
        const label = r.blob.newLabel();
        r.literals.push({ label, bytes });
        r.blob.u8(0x11); // LD DE,capacity
        r.blob.u16(lit.bytes.length);
        r.blob.u8(0xd5); // PUSH DE
        r.blob.u8(0x21); // LD HL,literal
        r.blob.labelOperand(label);
        r.blob.u8(0xe5); // PUSH HL
        this.push(4);
        return 4;
      }
      const d = this.designator();
      if (p.var && d.readonly) {
        fail(
          "not-writable",
          at,
          "a read-only object can't be passed to a var parameter",
        );
      }
      if (t.kind === "openString") {
        if (d.type.kind === "string") {
          r.blob.u8(0x11);
          r.blob.u16(d.type.capacity);
          r.blob.u8(0xd5);
        } else if (d.type.kind === "openString") {
          const word = this.openViewWord(d);
          this.loadRegisters(U16, word.place);
          r.blob.u8(0xe5);
        } else fail("type-mismatch", at, "a string is required");
      } else {
        const elem = (t as { element: Type }).element;
        if (d.type.kind === "array" && sameType(d.type.element, elem)) {
          r.blob.u8(0x11);
          r.blob.u16(d.type.length);
          r.blob.u8(0xd5);
        } else if (
          d.type.kind === "openArray" && sameType(d.type.element, elem)
        ) {
          const word = this.openViewWord(d);
          this.loadRegisters(U16, word.place);
          r.blob.u8(0xe5);
        } else {fail(
            "type-mismatch",
            at,
            `a ${typeName(elem)} array is required`,
          );}
      }
      this.push(2);
      this.emitAddress(d);
      r.blob.u8(0xe5);
      this.push(2);
      return 4;
    }
    if (isAggregate(t)) {
      const v = this.expression(t);
      if (
        v.kind === "reg" && v.type.kind === "handle" && !v.type.id &&
        !v.type.optional && t.kind === "record" && v.type.pool.record === t
      ) {
        // A lease (7.14): the record in the caller's own owning local.
        const root = this.lastDesignator;
        if (
          !root || !root.rootOnly || root.symbol?.storage.kind !== "frame" ||
          root.symbol.lease
        ) {
          fail(
            "lease",
            at,
            "a lease comes from the routine's own owning local or parameter",
          );
        }
        this.noteDirect(root!);
        if (p.ownerOffset !== undefined) {
          r.blob.u8(0xe5); // PUSH HL: the owner word is the record itself
          this.push(2);
        }
        r.blob.u8(0xe5); // PUSH HL: the address
        this.push(2);
        return p.ownerOffset !== undefined ? 4 : 2;
      }
      if (v.kind !== "address" || !sameType(v.type, t)) {
        fail("type-mismatch", at, `a ${typeName(t)} is required`);
      }
      if (p.var && (v as { readonly: boolean }).readonly) {
        fail(
          "not-writable",
          at,
          "a read-only object can't be passed to a var parameter",
        );
      }
      if (p.ownerOffset !== undefined) {
        // The owner word: a parameter passes its own on, as does a field or
        // element of it; a lease passes its slot; anything else is 0.
        const root = this.lastAddressRoot;
        const word = root?.lease
          ? root.slotOffset
          : root?.ownerOffset !== undefined
          ? root.ownerOffset
          : undefined;
        if (word !== undefined) {
          r.blob.u8(0xdd, 0x5e, word & 0xff, 0xdd, 0x56, (word + 1) & 0xff); // LD DE,(IX+w)
        } else r.blob.u8(0x11, 0, 0); // LD DE,0
        r.blob.u8(0xd5); // PUSH DE
        this.push(2);
      }
      r.blob.u8(0xe5); // PUSH HL
      this.push(2);
      return p.ownerOffset !== undefined ? 4 : 2;
    }
    if (t.kind === "handle") {
      if (p.var) {
        // A slot-holder: the address of an owning location, after its owner word.
        const d = this.designator();
        if (
          d.type.kind !== "handle" || d.type.id || !d.type.optional ||
          d.type.pool !== t.pool
        ) {
          fail("type-mismatch", at, `a ${typeName(t)} location is required`);
        }
        if (d.readonly) fail("not-writable", at, "the location is read-only");
        if (d.slotKind === "identifier") {
          fail(
            "slot-holder",
            at,
            "a field reached through an identifier can't be a slot-holder",
          );
        }
        this.noteDirect(d);
        if (d.slotTemp !== undefined) {
          r.blob.u8(
            0xdd,
            0x6e,
            d.slotTemp & 0xff,
            0xdd,
            0x66,
            (d.slotTemp + 1) & 0xff,
          );
        } else r.blob.u8(0x21, 0, 0);
        r.blob.u8(0xe5); // PUSH HL: the owner word
        this.push(2);
        this.emitAddress(d);
        r.blob.u8(0xe5); // PUSH HL: the location
        this.push(2);
        return 4;
      }
      const v = this.expression(t);
      if (t.id) {
        this.toRegisters(v, t, at);
        r.blob.u8(0xd5, 0xe5); // PUSH DE; PUSH HL
        this.push(4);
        return 4;
      }
      this.ownValue(v, t, at);
      this.callHelper(Helper.LINK0);
      r.blob.u8(0xe5); // PUSH HL
      this.push(2);
      return 2;
    }
    // A scalar or File.
    const v = this.expression(t);
    this.toRegisters(v, t, at);
    const size = sizeOf(t);
    if (size === 1) {
      r.blob.u8(0x6f, 0x26, 0x00, 0xe5); // LD L,A; LD H,0; PUSH HL
      this.push(2);
      return 2;
    }
    if (size === 2) {
      r.blob.u8(0xe5);
      this.push(2);
      return 2;
    }
    r.blob.u8(0xd5, 0xe5); // PUSH DE; PUSH HL
    this.push(4);
    void callee;
    return 4;
  }

  /** The bytes of a string literal as a string[N] object: length, bytes, zero. */
  private literalString(bytes: Uint8Array): number[] {
    if (bytes.length > 253) {
      fail(
        "out-of-range",
        this.token,
        "a string literal holds at most 253 bytes",
      );
    }
    return [bytes.length, ...bytes, 0];
  }

  // ---- expressions (chapter 9) -------------------------------------------------------

  /**
   * Parse an expression. `expected` guides exact integers; `constant` demands
   * a constant expression. The value is in the registers unless constant.
   */
  private expression(expected?: Type, constant = false): Value {
    return this.orExpression(expected, constant);
  }

  private orExpression(expected: Type | undefined, constant: boolean): Value {
    let left = this.andExpression(expected, constant);
    while (this.isKeyword("or") || this.isKeyword("xor")) {
      const op = (this.advance() as Token & { kind: "keyword" }).text;
      left = this.logicalOrBitwise(
        op,
        left,
        () => this.andExpression(expected, constant),
        constant,
      );
    }
    return left;
  }

  private andExpression(expected: Type | undefined, constant: boolean): Value {
    let left = this.notExpression(expected, constant);
    while (this.isKeyword("and")) {
      this.advance();
      left = this.logicalOrBitwise(
        "and",
        left,
        () => this.notExpression(expected, constant),
        constant,
      );
    }
    return left;
  }

  private notExpression(expected: Type | undefined, constant: boolean): Value {
    if (this.isKeyword("not")) {
      const at = this.advance();
      const v = this.notExpression(expected, constant);
      return this.unaryNot(v, at);
    }
    return this.comparison(expected, constant);
  }

  private comparison(expected: Type | undefined, constant: boolean): Value {
    // Comparison operands have no expected type from a boolean context.
    const operandExpected = expected && isScalar(expected, "boolean")
      ? undefined
      : expected;
    const leftAt = this.token;
    const left = this.additive(operandExpected, constant);
    const t = this.token;
    if (
      t.kind === "punct" && ["=", "<>", "<", "<=", ">", ">="].includes(t.text)
    ) {
      this.advance();
      const result = this.binary(
        t.text,
        left,
        leftAt,
        () => this.additive(operandExpected, constant),
        constant,
      );
      const u = this.token;
      if (
        u.kind === "punct" && ["=", "<>", "<", "<=", ">", ">="].includes(u.text)
      ) {
        fail("chained-comparison", u, "comparisons don't chain; use and");
      }
      return result;
    }
    return left;
  }

  private additive(expected: Type | undefined, constant: boolean): Value {
    const leftAt = this.token;
    let left = this.multiplicative(expected, constant);
    while (this.isPunct("+") || this.isPunct("-")) {
      const op = (this.advance() as Token & { kind: "punct" }).text;
      left = this.binary(
        op,
        left,
        leftAt,
        () => this.multiplicative(expected, constant),
        constant,
      );
    }
    return left;
  }

  private multiplicative(expected: Type | undefined, constant: boolean): Value {
    const leftAt = this.token;
    let left = this.unary(expected, constant);
    while (
      this.isPunct("*") || this.isPunct("/") || this.isKeyword("mod") ||
      this.isKeyword("shl") ||
      this.isKeyword("shr")
    ) {
      const t = this.advance() as Token & { kind: "punct" | "keyword" };
      left = this.binary(
        t.text,
        left,
        leftAt,
        () => this.unary(expected, constant),
        constant,
      );
    }
    return left;
  }

  private unary(expected: Type | undefined, constant: boolean): Value {
    if (this.isPunct("-")) {
      const at = this.advance();
      const v = this.unary(expected, constant);
      return this.negate(v, at);
    }
    if (this.isPunct("+")) {
      this.advance();
      return this.unary(expected, constant);
    }
    return this.postfix(expected, constant);
  }

  private postfix(expected: Type | undefined, constant: boolean): Value {
    const t = this.token;
    switch (t.kind) {
      case "number":
        this.advance();
        return { kind: "const", value: t.value };
      case "float":
        this.advance();
        return { kind: "const", type: scalar("f32"), value: t.value };
      case "character":
        this.advance();
        return {
          kind: "const",
          value: t.value,
          type: this.characterType(expected),
        };
      case "string":
        this.advance();
        return { kind: "literal", bytes: t.bytes };
      case "keyword":
        if (t.text === "true" || t.text === "false") {
          this.advance();
          return { kind: "const", type: BOOLEAN, value: t.text === "true" };
        }
        if (t.text === "none") {
          this.advance();
          return { kind: "none" };
        }
        if (t.text === "move") {
          this.advance();
          if (constant) fail("not-constant", t, "move is not constant");
          return this.moveExpression(t);
        }
        if (t.text === "new") {
          this.advance();
          if (constant) fail("not-constant", t, "new is not constant");
          return this.newExpression(this.acceptPunct("?"), t);
        }
        if (t.text in SCALARS) {
          this.advance();
          return this.conversion(t.text as ScalarName, constant);
        }
        fail("syntax", t, `unexpected '${t.text}' in an expression`);
        break;
      case "punct":
        if (t.text === "(") {
          this.advance();
          const v = this.expression(expected, constant);
          this.expectPunct(")");
          return v;
        }
        fail("syntax", t, `unexpected '${t.text}' in an expression`);
        break;
      case "name":
        return this.nameExpression(constant);
      default:
        fail("syntax", t, `unexpected ${t.kind} in an expression`);
    }
  }

  /** A character literal is u8 alone, exact beside an exact operand (9.7). */
  private characterType(expected: Type | undefined): Type | undefined {
    void expected;
    return U8;
  }

  private nameExpression(constant: boolean): Value {
    const name = this.token as Token & { kind: "name" };
    if (
      name.text === "id" && this.isPunct("(", this.peek()) &&
      !this.scopes.lookup("id")
    ) {
      this.advance();
      if (constant) fail("not-constant", name, "id is not constant");
      return this.idExpression(name);
    }
    const sym = this.scopes.lookup(name.text);
    if (!sym) fail("undeclared-name", name, `${name.text} is not declared`);
    switch (sym!.kind) {
      case "const":
        this.advance();
        return { kind: "const", type: sym!.type, value: sym!.value };
      case "routine": {
        if (constant) fail("not-constant", name, "a call is not a constant");
        this.advance();
        const callee = sym as Symbol & { kind: "routine" };
        if (!callee.signature.result) {
          fail("no-value", name, `${name.text} returns nothing`);
        }
        const v = this.call(callee, name);
        if (v.kind === "address") {
          // Allow suffixes on an aggregate result.
          const d = this.suffixes({
            place: { kind: "computed" },
            type: v.type,
            readonly: v.readonly,
            compute: () => {},
          });
          if (
            d.place.kind !== "computed" ||
            d.compute !== undefined && d.type !== v.type
          ) {
            return this.loadDesignator(d);
          }
          return v;
        }
        if (this.isPunct(".") || this.isPunct("[")) {
          fail("not-indexable", this.token, "a scalar result has no fields");
        }
        return v;
      }
      case "var":
      case "aggregateConst": {
        if (constant) {
          fail("not-constant", name, "a variable is not a constant");
        }
        const d = this.designator();
        this.lastDesignator = d;
        return this.loadDesignator(d);
      }
      default:
        fail("wrong-class", name, `${name.text} is not a value`);
    }
  }

  private loadDesignator(d: Designator): Value {
    if (isAggregate(d.type)) {
      this.emitAddress(d);
      return { kind: "address", type: d.type, readonly: d.readonly };
    }
    if (d.type.kind === "handle") {
      this.checkUsable(d);
      this.loadValue(d);
      return { kind: "reg", type: d.type };
    }
    if (d.symbol?.flow === "maybe") {
      fail(
        "use-after-move",
        this.token,
        `${d.symbol.name} may have been moved`,
      );
    }
    if (d.place.kind === "computed" || d.place.kind === "alias") {
      this.emitAddress(d);
      this.loadRegistersIndirect(d.type);
    } else this.loadRegisters(d.type, d.place);
    return { kind: "reg", type: d.type };
  }

  private conversion(target: ScalarName, constant: boolean): Value {
    const at = this.expectPunct("(");
    const v = this.expression(undefined, constant);
    this.expectPunct(")");
    const to = scalar(target);
    if (target === "boolean") {
      fail("conversion-unavailable", at, "there is no conversion to boolean");
    }
    if (v.kind === "const") {
      if (typeof v.value === "boolean") {
        fail("conversion-unavailable", at, "a boolean doesn't convert");
      }
      if (v.type && !(v.type.kind === "scalar" && v.type.name !== "boolean")) {
        fail("conversion-unavailable", at, "not a numeric value");
      }
      let value = v.value;
      if (
        target !== "f32" && v.type?.kind === "scalar" && v.type.name === "f32"
      ) value = Math.trunc(value);
      if (target === "f32") value = Math.fround(value);
      if (!fits(value, target)) {
        fail("narrowing", at, `${v.value} doesn't fit ${target}`);
      }
      return { kind: "const", type: to, value };
    }
    if (
      v.kind !== "reg" || v.type.kind !== "scalar" || v.type.name === "boolean"
    ) {
      fail("conversion-unavailable", at, "not a numeric value");
    }
    const from = (v as { type: Type & { kind: "scalar" } }).type.name;
    if (from === target || widens(from, target)) {
      this.widen(from, target);
      return { kind: "reg", type: to };
    }
    this.checkedNarrow(from, target);
    return { kind: "reg", type: to };
  }

  /** Conversions to or from a 32-bit type, with the checks of 9.6. */
  private checkedNarrow32(from: ScalarName, to: ScalarName): void {
    const r = this.routine!;
    const fs = SCALARS[from], ts = SCALARS[to];
    const trapIf = (cc: number) => r.blob.callBlobIf(cc, Helper.TRAP_NARROWING);
    const deZero = () => {
      r.blob.u8(0x7a, 0xb3); // LD A,D; OR E
      trapIf(JP_NZ);
    };
    const deSignOfH = () => {
      r.blob.u8(0x7c, 0x17, 0x9f, 0xbb); // LD A,H; RLA; SBC A,A; CP E
      trapIf(JP_NZ);
      r.blob.u8(0xba); // CP D
      trapIf(JP_NZ);
    };
    const hZero = () => {
      r.blob.u8(0x7c, 0xb7); // LD A,H; OR A
      trapIf(JP_NZ);
    };
    const bit7Clear = (reg: number) => {
      r.blob.u8(reg, 0x17); // LD A,r; RLA
      trapIf(JP_C);
    };
    const hSignOfL = () => {
      r.blob.u8(0x7d, 0x17, 0x9f, 0xbc); // LD A,L; RLA; SBC A,A; CP H
      trapIf(JP_NZ);
    };
    if (fs.size === 4 && ts.size === 4) {
      bit7Clear(0x7a); // D: u32 <-> i32 need the top bit clear
      return;
    }
    if (fs.size === 4) {
      if (fs.signed && ts.signed) {
        deSignOfH();
        if (ts.size === 1) hSignOfL();
      } else {
        deZero();
        if (ts.size === 1) hZero();
        if (ts.signed) bit7Clear(ts.size === 1 ? 0x7d : 0x7c); // L or H
      }
      if (ts.size === 1) r.blob.u8(0x7d); // LD A,L
      return;
    }
    // To 32 bits from a signed 16- or 8-bit type into an unsigned one, or
    // from an unsigned type that widens (handled by widen()).
    if (fs.signed && !ts.signed) {
      bit7Clear(fs.size === 1 ? 0x7f : 0x7c); // A or H
      if (fs.size === 1) r.blob.u8(0x6f, 0x26, 0x00); // LD L,A; LD H,0
      r.blob.u8(0x11, 0, 0); // LD DE,0
      return;
    }
    this.widen(from, to);
  }

  /** Narrow the value in registers with a check (9.6). */
  private checkedNarrow(from: ScalarName, to: ScalarName): void {
    const r = this.routine!;
    const fs = SCALARS[from], ts = SCALARS[to];
    if (fs.float && ts.float) return;
    if (fs.float) {
      // Truncate toward zero into 32 bits, then narrow further if needed.
      this.callHelper(ts.signed ? Helper.F2I : Helper.F2U);
      if (ts.size < 4) this.checkedNarrow32(ts.signed ? "i32" : "u32", to);
      return;
    }
    if (ts.float) {
      // From u32 or i32: rounded to nearest even by the helper.
      this.callHelper(fs.signed ? Helper.I2F : Helper.U2F);
      return;
    }
    if (fs.size === 4 || ts.size === 4) {
      this.checkedNarrow32(from, to);
      return;
    }
    if (fs.size === 2 && ts.size === 1) {
      // HL -> A. u16->u8: H must be 0. i16->i8: H must be sign of L. u16->i8: H=0 and L<128.
      // i16->u8: H=0 (then L is the value; negative values have H=$FF).
      if (!fs.signed && !ts.signed || fs.signed && !ts.signed) {
        r.blob.u8(0x7c, 0xb7); // LD A,H; OR A
        r.blob.callBlobIf(JP_NZ, Helper.TRAP_NARROWING);
      } else if (fs.signed && ts.signed) {
        r.blob.u8(0x7d, 0x07, 0x9f, 0xac); // LD A,L; RLCA; SBC A,A; XOR H
        r.blob.callBlobIf(JP_NZ, Helper.TRAP_NARROWING);
      } else {
        // u16 -> i8: H = 0 and L < 128
        r.blob.u8(0x7c, 0xb7); // LD A,H; OR A
        r.blob.callBlobIf(JP_NZ, Helper.TRAP_NARROWING);
        r.blob.u8(0x7d, 0x07); // LD A,L; RLCA (carry = bit 7)
        r.blob.callBlobIf(JP_C, Helper.TRAP_NARROWING);
      }
      r.blob.u8(0x7d); // LD A,L
      return;
    }
    if (fs.size === 1 && ts.size === 1) {
      // u8 <-> i8: the top bit must be clear.
      r.blob.u8(0xb7); // OR A: sign flag = bit 7
      r.blob.callBlobIf(0xfc - 2, Helper.TRAP_NARROWING); // CALL M
      return;
    }
    // 16 <-> 16 (u16 <-> i16): bit 15 must be clear.
    r.blob.u8(0x7c, 0xb7); // LD A,H; OR A
    r.blob.callBlobIf(0xfc - 2, Helper.TRAP_NARROWING); // CALL M
  }

  // ---- operators ----------------------------------------------------------------------

  private unaryNot(v: Value, at: Token): Value {
    const r = this.routine!;
    if (v.kind === "const") {
      if (typeof v.value === "boolean") {
        return { kind: "const", type: BOOLEAN, value: !v.value };
      }
      if (!v.type) {
        fail("no-definite-type", at, "not needs a typed integer operand");
      }
      const name = (v.type as { name: ScalarName }).name;
      if (!isInteger(v.type)) {
        fail("type-mismatch", at, "not takes a boolean or integer");
      }
      const mask = SCALARS[name].size === 1
        ? 0xff
        : SCALARS[name].size === 2
        ? 0xffff
        : 0xffffffff;
      let value = (~(v.value as number)) & mask;
      if (SCALARS[name].signed && value > SCALARS[name].max) value -= mask + 1;
      return { kind: "const", type: v.type, value };
    }
    if (v.kind !== "reg") {
      fail("type-mismatch", at, "not takes a boolean or integer");
    }
    const t = (v as { type: Type }).type;
    if (isScalar(t, "boolean")) {
      r.blob.u8(0xee, 0x01); // XOR 1
      return v;
    }
    if (!isInteger(t)) {
      fail("type-mismatch", at, "not takes a boolean or integer");
    }
    const size = sizeOf(t);
    if (size === 1) r.blob.u8(0x2f); // CPL
    else if (size === 2) r.blob.u8(0x7c, 0x2f, 0x67, 0x7d, 0x2f, 0x6f); // LD A,H; CPL; LD H,A; LD A,L; CPL; LD L,A
    else {
      r.blob.u8(0x7c, 0x2f, 0x67, 0x7d, 0x2f, 0x6f);
      r.blob.u8(0x7a, 0x2f, 0x57, 0x7b, 0x2f, 0x5f); // LD A,D; CPL; LD D,A; LD A,E; CPL; LD E,A
    }
    return v;
  }

  private negate(v: Value, at: Token): Value {
    const r = this.routine!;
    if (v.kind === "const") {
      if (typeof v.value === "boolean") {
        fail("type-mismatch", at, "a boolean can't be negated");
      }
      if (!v.type) return { kind: "const", value: -v.value };
      const name = (v.type as { name: ScalarName }).name;
      if (name === "f32") {
        return { kind: "const", type: v.type, value: -v.value };
      }
      const mod = 2 ** (SCALARS[name].size * 8);
      let value = (-v.value) % mod;
      if (value < 0) value += mod;
      if (SCALARS[name].signed && value > SCALARS[name].max) value -= mod;
      return { kind: "const", type: v.type, value };
    }
    if (v.kind !== "reg" || !isNumeric((v as { type: Type }).type)) {
      fail("type-mismatch", at, "a number is required");
    }
    const t = (v as { type: Type }).type;
    const size = sizeOf(t);
    if (size === 1) r.blob.u8(0xed, 0x44); // NEG
    else if (size === 2) r.blob.u8(0xeb, 0x21, 0, 0, 0xb7, 0xed, 0x52); // EX DE,HL; LD HL,0; OR A; SBC HL,DE
    else if (isScalar(t, "f32")) r.blob.u8(0x7a, 0xee, 0x80, 0x57); // LD A,D; XOR $80; LD D,A
    else this.callHelper(Helper.NEG32);
    return v;
  }

  /** `and`, `or`, `xor`: logical with short-circuit, or bitwise. */
  private logicalOrBitwise(
    op: string,
    left: Value,
    right: () => Value,
    constant: boolean,
  ): Value {
    const r = this.routine!;
    const at = this.token;
    const leftIsBool = left.kind === "const"
      ? typeof left.value === "boolean"
      : left.kind === "reg" && isScalar(left.type, "boolean");
    if (leftIsBool) {
      if (left.kind === "const") {
        const lv = left.value as boolean;
        if (op !== "xor" && ((op === "and" && !lv) || (op === "or" && lv))) {
          // Short-circuit: the right operand is still parsed but not evaluated.
          const save = this.suppress();
          right();
          this.restore(save);
          return { kind: "const", type: BOOLEAN, value: lv };
        }
        const rv = right();
        if (rv.kind === "const" && typeof rv.value === "boolean") {
          const value = op === "and"
            ? lv && rv.value
            : op === "or"
            ? lv || rv.value
            : lv !== rv.value;
          return { kind: "const", type: BOOLEAN, value };
        }
        if (rv.kind !== "reg" || !isScalar(rv.type, "boolean")) {
          fail("type-mismatch", at, "boolean operands are required");
        }
        if (op === "xor") r.blob.u8(0xee, lv ? 1 : 0);
        return { kind: "reg", type: BOOLEAN };
      }
      if (constant) {
        fail("not-constant", at, "a constant expression is required");
      }
      if (op === "xor") {
        r.blob.u8(0xf5); // PUSH AF
        this.push(2);
        const rv = right();
        this.toRegisters(rv, BOOLEAN, at);
        r.blob.u8(0x5f, 0xf1, 0xab); // LD E,A; POP AF; XOR E
        this.pop(2);
        return { kind: "reg", type: BOOLEAN };
      }
      const skip = r.blob.newLabel();
      r.blob.u8(0xb7); // OR A
      r.blob.jpIf(op === "and" ? JP_Z : JP_NZ, skip);
      const rv = right();
      this.toRegisters(rv, BOOLEAN, at);
      r.blob.defineLabel(skip);
      return { kind: "reg", type: BOOLEAN };
    }
    return this.binary(op, left, at, right, constant);
  }

  /** Discard emitted code while parsing an operand that is never evaluated. */
  private suppress(): { bytes: number; refs: number; lines: number } {
    const b = this.routine!.blob;
    return {
      bytes: b.bytes.length,
      refs: b.references.length,
      lines: b.lines.length,
    };
  }

  private restore(s: { bytes: number; refs: number; lines: number }): void {
    const b = this.routine!.blob;
    b.bytes.length = s.bytes;
    b.references.length = s.refs;
    b.lines.length = s.lines;
  }

  /**
   * A binary operator on numeric operands: resolve the common type, fold
   * constants, or emit code (left pushed, right evaluated, then the op).
   */
  private binary(
    op: string,
    left: Value,
    leftAt: Token,
    right: () => Value,
    constant: boolean,
  ): Value {
    const r = this.routine!;
    const isComparison = ["=", "<>", "<", "<=", ">", ">="].includes(op);
    const isShift = op === "shl" || op === "shr";
    if (
      left.kind === "const" && typeof left.value === "boolean" && isComparison
    ) {
      const rv = right();
      if (op !== "=" && op !== "<>") {
        fail("type-mismatch", leftAt, "booleans compare only with = and <>");
      }
      if (rv.kind === "const" && typeof rv.value === "boolean") {
        return {
          kind: "const",
          type: BOOLEAN,
          value: op === "=" ? left.value === rv.value : left.value !== rv.value,
        };
      }
      this.toRegisters(rv, BOOLEAN, leftAt);
      r.blob.u8(0xee, left.value ? 1 : 0); // XOR
      if (op === "=") r.blob.u8(0xee, 0x01);
      return { kind: "reg", type: BOOLEAN };
    }
    if (left.kind === "reg" && isScalar(left.type, "boolean") && isComparison) {
      if (op !== "=" && op !== "<>") {
        fail("type-mismatch", leftAt, "booleans compare only with = and <>");
      }
      r.blob.u8(0xf5); // PUSH AF
      this.push(2);
      const rv = right();
      this.toRegisters(rv, BOOLEAN, leftAt);
      r.blob.u8(0x5f, 0xf1, 0xab); // LD E,A; POP AF; XOR E
      this.pop(2);
      if (op === "=") r.blob.u8(0xee, 0x01);
      return { kind: "reg", type: BOOLEAN };
    }
    // Numeric operands.
    const leftType = this.numericType(left, leftAt);
    if (left.kind === "const" && !left.type) {
      // Exact left: the right operand decides.
      const rightAt = this.token;
      const rv = right();
      if (rv.kind === "const" && !rv.type) {
        return this.foldExact(
          op,
          left.value as number,
          rv.value as number,
          leftAt,
        );
      }
      const rtype = this.numericType(rv, rightAt);
      const type = isShift ? undefined : rtype;
      if (isShift) {
        fail(
          "no-definite-type",
          leftAt,
          "a shifted exact value needs a type from its context",
        );
      }
      // Fold if both constant.
      if (rv.kind === "const") {
        const lc = this.coerceConst(left, type!, leftAt);
        return this.foldTyped(
          op,
          lc.value as number,
          rv.value as number,
          type!,
          leftAt,
        );
      }
      // Emit: right is in registers; left is a constant: materialize as DE/E.
      return this.emitBinaryConstLeft(op, left.value as number, type!, leftAt);
    }
    // Typed left.
    if (left.kind === "const") {
      const rightAt = this.token;
      const rv = right();
      if (rv.kind === "const") {
        const type = isShift
          ? leftType
          : this.resultType(leftType, this.numericType(rv, rightAt), rightAt);
        const lc = this.coerceConst(left, type, leftAt);
        const rc = isShift ? rv : this.coerceConst(rv, type, leftAt);
        return this.foldTyped(
          op,
          lc.value as number,
          rc.value as number,
          type,
          leftAt,
        );
      }
      const rtype = this.numericType(rv, rightAt);
      const type = isShift
        ? leftType
        : this.resultType(leftType, rtype, rightAt);
      if (
        !isShift && rtype.kind === "scalar" &&
        rtype.name !== (type as { name: ScalarName }).name
      ) {
        this.widen(rtype.name, (type as { name: ScalarName }).name);
      }
      if (isShift) return this.emitShift(op, left, rv, leftAt);
      return this.emitBinaryConstLeft(
        op,
        this.coerceConst(left, type, leftAt).value as number,
        type,
        leftAt,
      );
    }
    if (constant) {
      fail("not-constant", leftAt, "a constant expression is required");
    }
    // Left in registers: push it, evaluate the right, pop, operate.
    if (isShift) {
      const lsz = SCALARS[(leftType as { name: ScalarName }).name].size;
      this.pushValue(lsz);
      const rv = right();
      if (rv.kind === "const") this.popValue(lsz);
      return this.emitShift(op, left, rv, leftAt);
    }
    const lt = leftType as Type & { kind: "scalar" };
    const lsize = SCALARS[lt.name].size;
    this.pushValue(lsize);
    const rightAt = this.token;
    const rv = right();
    let rtype = this.numericType(rv, rightAt);
    if (rv.kind === "const") {
      if ((op === "/" || op === "mod") && rv.value === 0) {
        fail("division-by-zero", rightAt, "division by a constant zero");
      }
      // Pop the left and operate with an immediate.
      const type = rv.type ? this.resultType(lt, rtype, rightAt) : lt;
      const rc = this.coerceConst(rv, type, rightAt);
      this.popValue(lsize);
      if ((type as { name: ScalarName }).name !== lt.name) {
        this.widen(lt.name, (type as { name: ScalarName }).name);
      }
      return this.emitBinaryImmediate(op, rc.value as number, type, rightAt);
    }
    rtype = rtype as Type & { kind: "scalar" };
    const type = this.resultType(lt, rtype, rightAt);
    const tname = (type as { name: ScalarName }).name;
    const tsize = SCALARS[tname].size;
    // Right is in registers at rtype; widen it to type.
    if ((rtype as { name: ScalarName }).name !== tname) {
      this.widen((rtype as { name: ScalarName }).name, tname);
    }
    if (tsize === 4) {
      // The right goes to the alternates; the left comes back into DEHL.
      r.blob.u8(0xd9); // EXX
      this.popValue(lsize);
      if (lsize !== 4) this.widen(lt.name, tname);
      return this.emitBinaryRegisters(
        op,
        type as Type & { kind: "scalar" },
        rightAt,
      );
    }
    // Bring the left back: it was pushed at lsize.
    if (tsize === 1) {
      r.blob.u8(0x5f, 0xf1); // LD E,A; POP AF  (A = left, E = right)
    } else {
      // Right in HL. Left pushed as AF (1 byte) or HL (2 bytes).
      r.blob.u8(0xeb); // EX DE,HL: right in DE
      if (lsize === 1) {
        r.blob.u8(0xf1); // POP AF: left byte in A
        this.widen(lt.name, tname); // into HL
      } else r.blob.u8(0xe1); // POP HL
    }
    this.pop(2);
    return this.emitBinaryRegisters(
      op,
      type as Type & { kind: "scalar" },
      leftAt,
    );
  }

  private numericType(v: Value, at: Token): Type {
    if (v.kind === "const") {
      if (typeof v.value === "boolean") {
        fail("type-mismatch", at, "a number is required");
      }
      return v.type ?? { kind: "scalar", name: "u16" }; // exact: caller checks v.type
    }
    if (v.kind === "reg" && isNumeric(v.type)) return v.type;
    if (v.kind === "reg") {
      fail(
        "type-mismatch",
        at,
        `a number is required, not ${typeName(v.type)}`,
      );
    }
    fail("type-mismatch", at, "a number is required");
  }

  private resultType(a: Type, b: Type, at: Token): Type {
    const an = (a as { name: ScalarName }).name,
      bn = (b as { name: ScalarName }).name;
    const c = commonType(an, bn);
    if (!c) {
      fail(
        "mixed-operands",
        at,
        `${an} and ${bn} don't widen to each other; convert one`,
      );
    }
    return scalar(c!);
  }

  private foldExact(op: string, a: number, b: number, at: Token): Value {
    switch (op) {
      case "+":
        return { kind: "const", value: a + b };
      case "-":
        return { kind: "const", value: a - b };
      case "*":
        return { kind: "const", value: a * b };
      case "/":
        if (b === 0) fail("division-by-zero", at, "division by zero");
        return { kind: "const", value: Math.trunc(a / b) };
      case "mod":
        if (b === 0) fail("division-by-zero", at, "division by zero");
        return { kind: "const", value: a % b };
      case "=":
        return { kind: "const", type: BOOLEAN, value: a === b };
      case "<>":
        return { kind: "const", type: BOOLEAN, value: a !== b };
      case "<":
        return { kind: "const", type: BOOLEAN, value: a < b };
      case "<=":
        return { kind: "const", type: BOOLEAN, value: a <= b };
      case ">":
        return { kind: "const", type: BOOLEAN, value: a > b };
      case ">=":
        return { kind: "const", type: BOOLEAN, value: a >= b };
      case "and":
        return {
          kind: "const",
          value: this.exactBits(a, b, at, (x, y) => x & y),
        };
      case "or":
        return {
          kind: "const",
          value: this.exactBits(a, b, at, (x, y) => x | y),
        };
      case "xor":
        return {
          kind: "const",
          value: this.exactBits(a, b, at, (x, y) => x ^ y),
        };
      default:
        fail(
          "no-definite-type",
          at,
          "a shifted exact value needs a type from its context",
        );
    }
  }

  private exactBits(
    a: number,
    b: number,
    at: Token,
    f: (x: number, y: number) => number,
  ): number {
    if (a < 0 || b < 0 || a > 0xffffffff || b > 0xffffffff) {
      fail("out-of-range", at, "bitwise operands must be non-negative");
    }
    return (f(a >>> 0, b >>> 0)) >>> 0;
  }

  /** Fold a typed operation with the run-time rules (wrapping, trunc division). */
  private foldTyped(
    op: string,
    a: number,
    b: number,
    type: Type,
    at: Token,
  ): Value {
    const name = (type as { name: ScalarName }).name;
    const s = SCALARS[name];
    if (s.float) {
      let v: number;
      switch (op) {
        case "+":
          v = Math.fround(a + b);
          break;
        case "-":
          v = Math.fround(a - b);
          break;
        case "*":
          v = Math.fround(a * b);
          break;
        case "/":
          if (b === 0) fail("division-by-zero", at, "division by zero");
          v = Math.fround(a / b);
          break;
        case "=":
          return { kind: "const", type: BOOLEAN, value: a === b };
        case "<>":
          return { kind: "const", type: BOOLEAN, value: a !== b };
        case "<":
          return { kind: "const", type: BOOLEAN, value: a < b };
        case "<=":
          return { kind: "const", type: BOOLEAN, value: a <= b };
        case ">":
          return { kind: "const", type: BOOLEAN, value: a > b };
        case ">=":
          return { kind: "const", type: BOOLEAN, value: a >= b };
        default:
          fail("type-mismatch", at, `${op} is not defined for f32`);
      }
      if (!Number.isFinite(v!)) {
        fail("float-overflow", at, "the result exceeds f32");
      }
      if (Math.abs(v!) < 1.1754943508222875e-38) v = 0;
      return { kind: "const", type, value: v! };
    }
    const mod = 2 ** (s.size * 8);
    const wrap = (x: number) => {
      let v = x % mod;
      if (v < 0) v += mod;
      if (s.signed && v > s.max) v -= mod;
      return v;
    };
    switch (op) {
      case "+":
        return { kind: "const", type, value: wrap(a + b) };
      case "-":
        return { kind: "const", type, value: wrap(a - b) };
      case "*":
        return {
          kind: "const",
          type,
          value: wrap(Number(BigInt(a) * BigInt(b) % BigInt(mod))),
        };
      case "/":
        if (b === 0) fail("division-by-zero", at, "division by zero");
        return { kind: "const", type, value: wrap(Math.trunc(a / b)) };
      case "mod":
        if (b === 0) fail("division-by-zero", at, "division by zero");
        return { kind: "const", type, value: a % b };
      case "and":
        return {
          kind: "const",
          type,
          value: wrap(
            Number(
              BigInt.asUintN(32, BigInt(a)) & BigInt.asUintN(32, BigInt(b)),
            ),
          ),
        };
      case "or":
        return {
          kind: "const",
          type,
          value: wrap(
            Number(
              BigInt.asUintN(32, BigInt(a)) | BigInt.asUintN(32, BigInt(b)),
            ),
          ),
        };
      case "xor":
        return {
          kind: "const",
          type,
          value: wrap(
            Number(
              BigInt.asUintN(32, BigInt(a)) ^ BigInt.asUintN(32, BigInt(b)),
            ),
          ),
        };
      case "shl": {
        if (b < 0) fail("type-mismatch", at, "a shift count is unsigned");
        if (b >= s.size * 8) return { kind: "const", type, value: 0 };
        return {
          kind: "const",
          type,
          value: wrap(Number(BigInt(a) << BigInt(b) & BigInt(mod - 1))),
        };
      }
      case "shr": {
        if (b < 0) fail("type-mismatch", at, "a shift count is unsigned");
        if (b >= s.size * 8) {
          return { kind: "const", type, value: s.signed && a < 0 ? -1 : 0 };
        }
        return { kind: "const", type, value: Math.floor(a / 2 ** b) };
      }
      case "=":
        return { kind: "const", type: BOOLEAN, value: a === b };
      case "<>":
        return { kind: "const", type: BOOLEAN, value: a !== b };
      case "<":
        return { kind: "const", type: BOOLEAN, value: a < b };
      case "<=":
        return { kind: "const", type: BOOLEAN, value: a <= b };
      case ">":
        return { kind: "const", type: BOOLEAN, value: a > b };
      case ">=":
        return { kind: "const", type: BOOLEAN, value: a >= b };
    }
    fail("syntax", at, `unknown operator ${op}`);
  }

  /** Right operand in registers; left is a constant. */
  private emitBinaryConstLeft(
    op: string,
    leftValue: number,
    type: Type,
    at: Token,
  ): Value {
    const r = this.routine!;
    const name = (type as { name: ScalarName }).name;
    const size = SCALARS[name].size;
    const commutative = ["+", "*", "and", "or", "xor", "=", "<>"].includes(op);
    if (commutative) return this.emitBinaryImmediate(op, leftValue, type, at);
    // Non-commutative: swap. Right is in A/HL/DEHL; load the left as the left.
    const bytes = this.encodeScalar(leftValue, name);
    if (size === 1) {
      r.blob.u8(0x5f, 0x3e, bytes[0]); // LD E,A; LD A,n
    } else if (size === 2) {
      r.blob.u8(0xeb, 0x21, bytes[0], bytes[1]); // EX DE,HL; LD HL,nn
    } else {
      r.blob.u8(0xd9); // EXX: the right to the alternates
      r.blob.u8(0x21, bytes[0], bytes[1], 0x11, bytes[2], bytes[3]); // LD HL,lo; LD DE,hi
    }
    return this.emitBinaryRegisters(op, type as Type & { kind: "scalar" }, at);
  }

  /** Left in registers; right is a constant. */
  private emitBinaryImmediate(
    op: string,
    rightValue: number,
    type: Type,
    at: Token,
  ): Value {
    const r = this.routine!;
    const name = (type as { name: ScalarName }).name;
    const size = SCALARS[name].size;
    const bytes = this.encodeScalar(rightValue, name);
    if (size === 4) {
      // The right into the alternates.
      r.blob.u8(0xd9, 0x21, bytes[0], bytes[1], 0x11, bytes[2], bytes[3], 0xd9);
      return this.emitBinaryRegisters(
        op,
        type as Type & { kind: "scalar" },
        at,
      );
    }
    if (size === 1) {
      switch (op) {
        case "+":
          r.blob.u8(0xc6, bytes[0]); // ADD A,n
          return { kind: "reg", type };
        case "-":
          r.blob.u8(0xd6, bytes[0]); // SUB n
          return { kind: "reg", type };
        case "and":
          r.blob.u8(0xe6, bytes[0]);
          return { kind: "reg", type };
        case "or":
          r.blob.u8(0xf6, bytes[0]);
          return { kind: "reg", type };
        case "xor":
          r.blob.u8(0xee, bytes[0]);
          return { kind: "reg", type };
      }
      r.blob.u8(0x1e, bytes[0]); // LD E,n
      return this.emitBinaryRegisters(
        op,
        type as Type & { kind: "scalar" },
        at,
      );
    }
    r.blob.u8(0x11, bytes[0], bytes[1]); // LD DE,nn
    return this.emitBinaryRegisters(op, type as Type & { kind: "scalar" }, at);
  }

  /** Left in A/HL, right in E/DE. */
  private emitBinaryRegisters(
    op: string,
    type: Type & { kind: "scalar" },
    at: Token,
  ): Value {
    const r = this.routine!;
    const s = SCALARS[type.name];
    if (s.float) return this.emitBinaryF32(op, type, at);
    if (s.size === 4) return this.emitBinary32(op, type, at);
    if (s.size === 1) {
      switch (op) {
        case "+":
          r.blob.u8(0x83); // ADD A,E
          return { kind: "reg", type };
        case "-":
          r.blob.u8(0x93); // SUB E
          return { kind: "reg", type };
        case "and":
          r.blob.u8(0xa3);
          return { kind: "reg", type };
        case "or":
          r.blob.u8(0xb3);
          return { kind: "reg", type };
        case "xor":
          r.blob.u8(0xab);
          return { kind: "reg", type };
        case "*":
        case "/":
        case "mod": {
          // Widen A and E to HL and DE, use the 16-bit helper, take the low byte.
          if (s.signed) {
            r.blob.u8(0x6f, 0x07, 0x9f, 0x67); // LD L,A; RLCA; SBC A,A; LD H,A
            r.blob.u8(0x7b, 0x07, 0x9f, 0x57); // LD A,E; RLCA; SBC A,A; LD D,A
          } else {
            r.blob.u8(0x6f, 0x26, 0x00, 0x16, 0x00); // LD L,A; LD H,0; LD D,0
          }
          this.callHelper(
            op === "*" ? Helper.MUL16 : s.signed ? Helper.DIV16S : Helper.DIV16,
          );
          r.blob.u8(op === "mod" ? 0x7b : 0x7d); // LD A,E / LD A,L
          return { kind: "reg", type };
        }
        case "=":
          r.blob.u8(0x93, 0xd6, 0x01, 0x9f, 0xe6, 0x01); // SUB E; SUB 1; SBC A,A; AND 1
          return { kind: "reg", type: BOOLEAN };
        case "<>":
          r.blob.u8(0x93, 0xd6, 0x01, 0x9f, 0x3c); // SUB E; SUB 1; SBC A,A; INC A
          return { kind: "reg", type: BOOLEAN };
        case "<":
        case ">=":
        case ">":
        case "<=": {
          // Reduce to A < E (carry) possibly with swapped operands.
          const swapped = op === ">" || op === "<=";
          if (swapped) r.blob.u8(0x57, 0x7b, 0x5a); // LD D,A; LD A,E; LD E,D
          if (s.signed) {
            // Signed: flip sign bits then unsigned compare.
            r.blob.u8(0xee, 0x80, 0x57, 0x7b, 0xee, 0x80, 0x5f, 0x7a); // XOR $80; LD D,A; LD A,E; XOR $80; LD E,A; LD A,D
          }
          r.blob.u8(0xbb, 0x9f); // CP E; SBC A,A  ($FF if A<E)
          if (op === "<" || op === ">") r.blob.u8(0xe6, 0x01); // AND 1
          else r.blob.u8(0x3c); // INC A: 0 if less, 1 otherwise (>= or <=)
          return { kind: "reg", type: BOOLEAN };
        }
      }
      fail("syntax", at, `unknown operator ${op}`);
    }
    switch (op) {
      case "+":
        r.blob.u8(0x19); // ADD HL,DE
        return { kind: "reg", type };
      case "-":
        r.blob.u8(0xb7, 0xed, 0x52); // OR A; SBC HL,DE
        return { kind: "reg", type };
      case "and":
        r.blob.u8(0x7c, 0xa2, 0x67, 0x7d, 0xa3, 0x6f); // LD A,H; AND D; LD H,A; LD A,L; AND E; LD L,A
        return { kind: "reg", type };
      case "or":
        r.blob.u8(0x7c, 0xb2, 0x67, 0x7d, 0xb3, 0x6f);
        return { kind: "reg", type };
      case "xor":
        r.blob.u8(0x7c, 0xaa, 0x67, 0x7d, 0xab, 0x6f);
        return { kind: "reg", type };
      case "*":
        this.callHelper(Helper.MUL16);
        return { kind: "reg", type };
      case "/":
      case "mod":
        this.callHelper(s.signed ? Helper.DIV16S : Helper.DIV16);
        if (op === "mod") r.blob.u8(0xeb); // EX DE,HL
        return { kind: "reg", type };
      case "=":
        r.blob.u8(0xb7, 0xed, 0x52, 0x7c, 0xb5, 0xd6, 0x01, 0x9f, 0xe6, 0x01); // OR A; SBC HL,DE; LD A,H; OR L; SUB 1; SBC A,A; AND 1
        return { kind: "reg", type: BOOLEAN };
      case "<>":
        r.blob.u8(0xb7, 0xed, 0x52, 0x7c, 0xb5, 0xd6, 0x01, 0x9f, 0x3c);
        return { kind: "reg", type: BOOLEAN };
      case "<":
      case ">=":
      case ">":
      case "<=": {
        const swapped = op === ">" || op === "<=";
        if (swapped) r.blob.u8(0xeb); // EX DE,HL
        this.compare16ToFlags(s.signed);
        r.blob.u8(0x9f); // SBC A,A: $FF if HL<DE
        if (op === "<" || op === ">") r.blob.u8(0xe6, 0x01);
        else r.blob.u8(0x3c);
        return { kind: "reg", type: BOOLEAN };
      }
    }
    fail("syntax", at, `unknown operator ${op}`);
  }

  /** f32: left in DEHL, right in DE'HL', through the runtime (9.9). */
  private emitBinaryF32(
    op: string,
    type: Type & { kind: "scalar" },
    at: Token,
  ): Value {
    const r = this.routine!;
    switch (op) {
      case "+":
        this.callHelper(Helper.FADD);
        return { kind: "reg", type };
      case "-":
        this.callHelper(Helper.FSUB);
        return { kind: "reg", type };
      case "*":
        this.callHelper(Helper.FMUL);
        return { kind: "reg", type };
      case "/":
        this.callHelper(Helper.FDIV);
        return { kind: "reg", type };
      case "=":
      case "<>":
        this.callHelper(Helper.FCMP);
        this.boolFromCompare(false, op === "=");
        return { kind: "reg", type: BOOLEAN };
      case "<":
      case ">=":
        this.callHelper(Helper.FCMP);
        this.boolFromCompare(op === "<");
        return { kind: "reg", type: BOOLEAN };
      case ">":
      case "<=":
        r.blob.u8(0xd9); // EXX: compare right with left
        this.callHelper(Helper.FCMP);
        this.boolFromCompare(op === ">");
        return { kind: "reg", type: BOOLEAN };
    }
    fail("type-mismatch", at, `${op} is not defined for f32`);
  }

  /** A boolean in A from a compare helper's flags (carry = less, Z = equal). */
  private boolFromCompare(less: boolean, equalWanted?: boolean): void {
    const r = this.routine!;
    if (equalWanted !== undefined) {
      const skip = r.blob.newLabel();
      r.blob.u8(0x3e, 0x00); // LD A,0
      r.blob.jpIf(equalWanted ? JP_NZ : JP_Z, skip);
      r.blob.u8(0x3c); // INC A
      r.blob.defineLabel(skip);
      return;
    }
    r.blob.u8(0x9f); // SBC A,A: $FF if carry
    if (less) r.blob.u8(0xe6, 0x01); // AND 1
    else r.blob.u8(0x3c); // INC A
  }

  /** 32-bit: left in DEHL, right in DE'HL' (code generation §4). */
  private emitBinary32(
    op: string,
    type: Type & { kind: "scalar" },
    at: Token,
  ): Value {
    const r = this.routine!;
    const signed = SCALARS[type.name].signed;
    const boolFromFlags = (less: boolean, equalWanted?: boolean) => {
      if (equalWanted !== undefined) {
        // = : A = 1 iff Z; <> : A = 1 iff NZ
        const skip = r.blob.newLabel();
        r.blob.u8(0x3e, 0x00); // LD A,0
        r.blob.jpIf(equalWanted ? JP_NZ : JP_Z, skip);
        r.blob.u8(0x3c); // INC A
        r.blob.defineLabel(skip);
        return;
      }
      r.blob.u8(0x9f); // SBC A,A: $FF if carry
      if (less) r.blob.u8(0xe6, 0x01); // AND 1
      else r.blob.u8(0x3c); // INC A
    };
    switch (op) {
      case "+":
        this.callHelper(Helper.ADD32);
        return { kind: "reg", type };
      case "-":
        this.callHelper(Helper.SUB32);
        return { kind: "reg", type };
      case "*":
        this.callHelper(Helper.MUL32);
        return { kind: "reg", type };
      case "/":
        this.callHelper(signed ? Helper.DIV32S : Helper.DIV32U);
        return { kind: "reg", type };
      case "mod":
        this.callHelper(signed ? Helper.DIV32S : Helper.DIV32U);
        r.blob.u8(0xd9); // EXX: the remainder
        return { kind: "reg", type };
      case "and":
        this.callHelper(Helper.AND32);
        return { kind: "reg", type };
      case "or":
        this.callHelper(Helper.OR32);
        return { kind: "reg", type };
      case "xor":
        this.callHelper(Helper.XOR32);
        return { kind: "reg", type };
      case "=":
      case "<>":
        this.callHelper(signed ? Helper.CMP32S : Helper.CMP32U);
        boolFromFlags(false, op === "=");
        return { kind: "reg", type: BOOLEAN };
      case "<":
      case ">=":
        this.callHelper(signed ? Helper.CMP32S : Helper.CMP32U);
        boolFromFlags(op === "<");
        return { kind: "reg", type: BOOLEAN };
      case ">":
      case "<=":
        r.blob.u8(0xd9); // EXX: compare right with left
        this.callHelper(signed ? Helper.CMP32S : Helper.CMP32U);
        boolFromFlags(op === ">");
        return { kind: "reg", type: BOOLEAN };
    }
    fail("syntax", at, `unknown operator ${op}`);
  }

  private emitShift(op: string, left: Value, count: Value, at: Token): Value {
    const r = this.routine!;
    const type = this.numericType(left, at);
    if (left.kind === "const" && !left.type) {
      fail("no-definite-type", at, "a shifted exact value needs a type");
    }
    const name = (type as { name: ScalarName }).name;
    if (!isInteger(type)) fail("type-mismatch", at, "shifts take integers");
    const s = SCALARS[name];
    if (count.kind === "const") {
      if (typeof count.value !== "number" || count.value < 0) {
        fail("type-mismatch", at, "a shift count is unsigned");
      }
      if (
        count.type && count.type.kind === "scalar" &&
        SCALARS[count.type.name].signed
      ) {
        fail("type-mismatch", at, "a shift count must be unsigned; convert it");
      }
      if (left.kind === "const") {
        return this.foldTyped(op, left.value as number, count.value, type, at);
      }
      const n = Math.min(count.value, s.size * 8);
      this.emitShiftBy(op, s, n, true);
      return { kind: "reg", type };
    }
    // A variable count, in the registers after the left was pushed (see
    // binary()): clamp it to the width, then shift in a loop or a helper.
    if (
      count.kind !== "reg" || !isInteger(count.type) ||
      SCALARS[(count.type as { name: ScalarName }).name].signed
    ) {
      fail("type-mismatch", at, "a shift count must be an unsigned integer");
    }
    const csize = SCALARS[(count.type as { name: ScalarName }).name].size;
    const width = s.size * 8;
    if (csize >= 2) {
      // HL (or DEHL) holds the count: anything with a high byte clamps.
      const small = r.blob.newLabel();
      r.blob.u8(0x7c); // LD A,H
      if (csize === 4) r.blob.u8(0xb2, 0xb3); // OR D; OR E
      r.blob.u8(0xb7, 0x7d); // OR A; LD A,L
      r.blob.jpIf(JP_Z, small);
      r.blob.u8(0x3e, width); // LD A,width
      r.blob.defineLabel(small);
    }
    const ok = r.blob.newLabel();
    r.blob.u8(0xfe, width); // CP width
    r.blob.jpIf(JP_C, ok);
    r.blob.u8(0x3e, width); // LD A,width
    r.blob.defineLabel(ok);
    r.blob.u8(0x4f); // LD C,A: the clamped count
    this.popValue(s.size);
    if (s.size === 4) {
      r.blob.u8(0x79); // LD A,C
      this.callHelper(
        op === "shl" ? Helper.SHL32 : s.signed ? Helper.SHR32S : Helper.SHR32U,
      );
      return { kind: "reg", type };
    }
    const done = r.blob.newLabel();
    const loop = r.blob.newLabel();
    r.blob.u8(0x41); // LD B,C
    if (s.size === 1) r.blob.u8(0x6f, 0x79, 0xb7, 0x7d); // LD L,A; LD A,C; OR A; LD A,L
    else r.blob.u8(0x79, 0xb7); // LD A,C; OR A
    r.blob.jpIf(JP_Z, done);
    r.blob.defineLabel(loop);
    this.emitShiftBy(op, s, 1, false);
    r.blob.u8(0x05); // DEC B
    r.blob.jpIf(JP_NZ, loop);
    r.blob.defineLabel(done);
    return { kind: "reg", type };
  }

  private emitShiftBy(
    op: string,
    s: { size: number; signed: boolean },
    n: number,
    _c: boolean,
  ): void {
    const r = this.routine!;
    if (s.size === 4) {
      r.blob.u8(0x3e, Math.min(n, 32)); // LD A,n
      this.callHelper(
        op === "shl" ? Helper.SHL32 : s.signed ? Helper.SHR32S : Helper.SHR32U,
      );
      return;
    }
    if (n >= s.size * 8) {
      if (op === "shr" && s.signed) {
        if (s.size === 1) r.blob.u8(0x07, 0x9f); // RLCA; SBC A,A
        else r.blob.u8(0x7c, 0x07, 0x9f, 0x6f, 0x67); // LD A,H; RLCA; SBC A,A; LD L,A; LD H,A
      } else if (s.size === 1) r.blob.u8(0xaf); // XOR A
      else r.blob.u8(0x21, 0, 0);
      return;
    }
    for (let i = 0; i < n; i += 1) {
      if (s.size === 1) {
        if (op === "shl") r.blob.u8(0x87); // ADD A,A
        else if (s.signed) r.blob.u8(0xcb, 0x2f); // SRA A
        else r.blob.u8(0xcb, 0x3f); // SRL A
      } else {
        if (op === "shl") r.blob.u8(0x29); // ADD HL,HL
        else if (s.signed) r.blob.u8(0xcb, 0x2c, 0xcb, 0x1d); // SRA H; RR L
        else r.blob.u8(0xcb, 0x3c, 0xcb, 0x1d); // SRL H; RR L
      }
    }
  }
}

export function reporterOrdinal(reason: string): number {
  return TRAP_REPORTERS[reason];
}

export { CompileError, HELPER_VERSION, REGISTER_HELPERS };
void dataBlob;
