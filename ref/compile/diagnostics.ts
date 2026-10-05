/** Compile-time diagnostics (docs/diagnostics.md). */
import type { Position } from "./lexer.ts";

export class CompileError extends Error {
  /** The part's name, when the error comes before its number is fixed. */
  partName?: string;

  constructor(
    public readonly code: string,
    public readonly position: Position,
    message: string,
  ) {
    super(`${code} at ${position.line}:${position.column}: ${message}`);
  }
}

export function fail(
  code: string,
  position: Position,
  message: string,
): never {
  throw new CompileError(code, position, message);
}
