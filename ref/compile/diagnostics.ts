/** Compile-time diagnostics (docs/diagnostics.md). */
import type { Position } from "./lexer.ts";

export class CompileError extends Error {
  /** The part's name, when the error comes before its number is fixed. */
  partName?: string;

  constructor(
    public readonly code: string,
    public readonly position: Position,
    message: string,
    /**
     * The arguments that replace ^1 and ^2 in the code's text in BASIE.MSG
     * (D39), where this site supplies them: a name, a number or a type, as
     * the native compiler prints them.
     */
    public readonly args?: string[],
  ) {
    super(`${code} at ${position.line}:${position.column}: ${message}`);
  }
}

export function fail(
  code: string,
  position: Position,
  message: string,
  args?: string[],
): never {
  throw new CompileError(code, position, message, args);
}
